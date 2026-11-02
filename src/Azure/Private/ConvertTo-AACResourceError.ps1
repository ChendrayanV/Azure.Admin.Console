function ConvertTo-AACResourceError {
    <#
    .SYNOPSIS
        Builds Get-AACResourceError's model from Activity Log events: every
        failed operation (one per correlation ID) with why it failed - access
        denied, an Azure Policy deny, a quota, no capacity, throttling, a
        lock, an invalid deployment, something missing - and what to do;
        and the errors grouped by code.
    .DESCRIPTION
        No Azure calls. -Entry is the Activity Log's events (as ARM returns
        them, several subscriptions together); only failed ones and Azure
        Policy denies are kept, one per correlation ID - the event with the
        most telling error. Events of subscriptions not in -SubscriptionName
        are left out.

        The error code and message come from the event's statusMessage
        (ARM's JSON error, its innermost detail for deployments) or its
        statusCode and sub-status. The category follows the code:
          Authorization  AuthorizationFailed, LinkedAuthorizationFailed,
                         Forbidden... - the action and scope that were
                         refused are read from the message
          Policy         RequestDisallowedByPolicy, a policy deny event
          Quota          QuotaExceeded, OperationNotAllowed over a quota
          Capacity       SkuNotAvailable, AllocationFailed, ZonalAllocation
                         Failed...
          Throttling     TooManyRequests, SubscriptionRequestsThrottled
          Lock           ScopeLocked
          Conflict       Conflict, AnotherOperationInProgress
          Validation     InvalidTemplate, InvalidParameter, BadRequest...
          Not found      ResourceNotFound, ResourceGroupNotFound...
          Other          anything else

        Returns @{ Errors (AAC.ResourceError, newest first); Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyCollection()]
        [object[]] $Entry = @(),

        [hashtable] $SubscriptionName = @{}
    )

    $get = ${function:Get-AACMember}
    $text = { param($Object, [string] $Path) $v = & $get $Object $Path; if ($null -eq $v) { '' } else { [string]$v } }
    $value = { param($Object, [string] $Path) $v = & $get $Object $Path; if ($v -is [System.Collections.IDictionary]) { $t = & $text $v 'value'; if ($t) { $t } else { & $text $v 'localizedValue' } } elseif ($null -eq $v) { '' } else { [string]$v } }
    $date = {
        param([string] $Value)
        $d = [datetime]::MinValue
        if ($Value -and [datetime]::TryParse($Value, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$d)) { $d } else { $null }
    }

    # --- Failed events, one per correlation ID -----------------------------------------------------------------------
    $failed = @($Entry | Where-Object {
            $_ -is [System.Collections.IDictionary] -and
            $SubscriptionName.Contains((& $text $_ 'subscriptionId').ToLowerInvariant()) -and
            ((& $value $_ 'status') -eq 'Failed' -or ((& $value $_ 'category') -eq 'Policy' -and (& $value $_ 'operationName') -match '(?i)deny'))
        })
    $errors = @(foreach ($group in @($failed | Group-Object { $c = & $text $_ 'correlationId'; if ($c) { $c } else { & $text $_ 'eventDataId' } })) {
            # The event that says the most: a status message, else any.
            $events = @($group.Group | Sort-Object { & $text $_ 'eventTimestamp' })
            $best = @($events | Where-Object { & $text $_ 'properties.statusMessage' } | Select-Object -Last 1)
            $e = if ($best.Count) { $best[0] } else { $events[-1] }
            $statusCode = & $text $e 'properties.statusCode'
            $operation = & $value $e 'operationName'
            $kind = Read-AACActivityLogError -StatusMessage (& $text $e 'properties.statusMessage') -StatusCode $statusCode -SubStatus (& $value $e 'subStatus') -Operation $operation -EventCategory (& $value $e 'category')
            $code = $kind.Code
            $message = $kind.Message
            $action = ''; $scope = ''
            if ($message -match "(?i)authorization to perform action '([^']+)' over scope '([^']+)'") { $action = $Matches[1]; $scope = $Matches[2] }
            elseif ($kind.Category -eq 'Authorization') { $action = & $text $e 'authorization.action'; $scope = & $text $e 'authorization.scope' }
            $resourceId = & $text $e 'resourceId'
            $subscription = (& $text $e 'subscriptionId').ToLowerInvariant()
            $item = [pscustomobject][ordered]@{
                Time          = & $date (& $text $events[0] 'eventTimestamp')
                Category      = $kind.Category
                ErrorCode     = $code
                Message       = $(if ($message.Length -gt 600) { $message.Substring(0, 597) + '...' } else { $message })
                Operation     = $(if ($operation) { (& $text $e 'operationName.localizedValue') -replace '^$', $operation } else { '' })
                OperationName = $operation
                Resource      = $(if ($resourceId) { ($resourceId.TrimEnd('/') -split '/')[-1] } else { '' })
                ResourceType  = (& $value $e 'resourceType').ToLowerInvariant()
                ResourceGroup = & $text $e 'resourceGroupName'
                Subscription  = $(if ($SubscriptionName.Contains($subscription)) { $SubscriptionName[$subscription] } else { $subscription })
                Caller        = & $text $e 'caller'
                ClientIp      = & $text $e 'httpRequest.clientIpAddress'
                StatusCode    = $statusCode
                Action        = $action
                Scope         = $scope
                Events        = $events.Count
                Remediation   = $kind.Fix
                Link          = $kind.Link
                CorrelationId = & $text $e 'correlationId'
                SubscriptionId = $subscription
                ResourceId    = $resourceId
            }

            $item.PSObject.TypeNames.Insert(0, 'AAC.ResourceError')
            $item
        })
    $errors = @($errors | Sort-Object -Property @{ Expression = 'Time'; Descending = $true })

    @{
        Errors = $errors
        Stats  = @{
            Errors        = $errors.Count
            Authorization = @($errors | Where-Object Category -EQ 'Authorization').Count
            Policy        = @($errors | Where-Object Category -EQ 'Policy').Count
            Quota         = @($errors | Where-Object { $_.Category -in 'Quota', 'Capacity' }).Count
            Deployments   = @($errors | Where-Object { $_.OperationName -match '(?i)microsoft\.resources/deployments/' }).Count
            Callers       = @($errors | ForEach-Object { $_.Caller } | Where-Object { $_ } | Select-Object -Unique).Count
        }
    }
}
