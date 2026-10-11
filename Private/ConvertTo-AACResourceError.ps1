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
    # ARM's error JSON (possibly nested, possibly a string inside a string) -> the innermost code and message.
    $errorOf = {
        param([string] $Raw)
        $result = @{ Code = ''; Message = '' }
        if (-not $Raw) { return $result }
        $parsed = $null
        try { $parsed = ConvertFrom-Json -InputObject $Raw -AsHashtable -Depth 32 -ErrorAction Stop } catch { $result.Message = $Raw; return $result }
        $node = $parsed
        for ($depth = 0; $depth -lt 6 -and $node -is [System.Collections.IDictionary]; $depth++) {
            $inner = & $get $node 'error'
            if ($inner -is [System.Collections.IDictionary]) { $node = $inner }
            $code = & $text $node 'code'; $message = & $text $node 'message'
            if ($code -and $code -notin 'DeploymentFailed', 'ResourceDeploymentFailure', 'Conflict' -or -not $result.Code) { if ($code) { $result.Code = $code }; if ($message) { $result.Message = $message } }
            $details = @(& $get $node 'details' | Where-Object { $_ -is [System.Collections.IDictionary] })
            if (-not $details.Count) { break }
            $node = $details[0]
            # A detail's message is sometimes the error JSON again.
            $nested = & $text $node 'message'
            if ($nested -match '^\s*\{') { try { $node = ConvertFrom-Json -InputObject $nested -AsHashtable -Depth 32 -ErrorAction Stop } catch { $null = $_ } }
        }
        if (-not $result.Message -and $parsed -is [System.Collections.IDictionary]) { $result.Message = (& $text $parsed 'Message') }
        $result
    }
    $docs = 'https://learn.microsoft.com/azure'
    $classify = {
        param([string] $Code, [string] $Message, [string] $StatusCode, [string] $Operation, [string] $Category)
        $c = "$Code $StatusCode"
        if ($Category -eq 'Policy' -or $c -match '(?i)RequestDisallowedByPolicy|PolicyViolation' -or $Operation -match '(?i)policies/deny') { return @{ Category = 'Policy'; Fix = 'Change the request to comply with the policy named in the message, or ask its owner for an exemption (scoped and with an expiry).'; Link = "$docs/governance/policy/troubleshoot/general" } }
        if ($c -match '(?i)Authoriz|Forbidden|InvalidAuthenticationToken|AuthenticationFailed|PermissionMismatch') { return @{ Category = 'Authorization'; Fix = 'Grant the caller a role with the refused action at that scope (the narrowest role and scope that work) - or, with PIM, activate the eligible role first.'; Link = "$docs/role-based-access-control/troubleshooting" } }
        if ($c -match '(?i)Quota' -or ($Code -match '(?i)OperationNotAllowed' -and $Message -match '(?i)quota|exceed|limit')) { return @{ Category = 'Quota'; Fix = 'Request a quota increase for the region and family (Quotas in the portal), or deploy to another region or VM family.'; Link = "$docs/quotas/per-vm-quota-requests" } }
        if ($c -match '(?i)SkuNotAvailable|AllocationFailed|ZonalAllocationFailed|OverconstrainedAllocation|OverconstrainedZonalAllocation|CapacityNotAvailable') { return @{ Category = 'Capacity'; Fix = 'Try another size, zone or region (Get-AACSkuAvailability shows what you can use) - or reserve capacity (on-demand capacity reservations) for what must start.'; Link = "$docs/virtual-machines/troubleshooting/allocation-failure" } }
        if ($c -match '(?i)TooManyRequests|Throttl|\b429\b') { return @{ Category = 'Throttling'; Fix = 'Slow the caller down: retry with back-off (honour Retry-After), batch reads, cache what doesn''t change.'; Link = "$docs/azure-resource-manager/management/request-limits-and-throttling" } }
        if ($c -match '(?i)ScopeLocked' -or $Message -match '(?i)\block\b.*\b(scope|resource)|is locked') { return @{ Category = 'Lock'; Fix = 'A lock (CanNotDelete or ReadOnly) blocks the change: remove it for the change, then put it back - or leave it if the lock is doing its job.'; Link = "$docs/azure-resource-manager/management/lock-resources" } }
        if ($c -match '(?i)NotFound') { return @{ Category = 'Not found'; Fix = 'Something it needs doesn''t exist (yet): check names and IDs, and that dependencies are deployed first (dependsOn).'; Link = "$docs/azure-resource-manager/troubleshooting/error-not-found" } }
        if ($c -match '(?i)Conflict|AnotherOperationInProgress|InUse|RetryableError') { return @{ Category = 'Conflict'; Fix = 'Another operation was running on the resource, or its state didn''t allow this one: wait for it to finish and retry.'; Link = "$docs/azure-resource-manager/troubleshooting/common-deployment-errors" } }
        if ($c -match '(?i)Invalid|BadRequest|Validation|DeploymentFailed|MissingSubscriptionRegistration|NoRegisteredProviderFound|Unsupported') { return @{ Category = 'Validation'; Fix = $(if ($c -match '(?i)MissingSubscriptionRegistration|NoRegisteredProviderFound') { 'Register the resource provider in the subscription (Resource providers in the portal).' } else { 'Fix the template or request: the message names the property or parameter Azure rejected.' }); Link = "$docs/azure-resource-manager/troubleshooting/common-deployment-errors" } }
        @{ Category = 'Other'; Fix = 'Read the message; retry if it was transient, and check Resource Health and Service Health for the region.'; Link = "$docs/azure-resource-manager/troubleshooting/common-deployment-errors" }
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
            $parsed = & $errorOf (& $text $e 'properties.statusMessage')
            $statusCode = & $text $e 'properties.statusCode'
            $subStatus = & $value $e 'subStatus'
            $code = if ($parsed.Code) { $parsed.Code } elseif ($subStatus) { $subStatus } else { $statusCode }
            $message = ($parsed.Message -replace '\s+', ' ').Trim()
            $operation = & $value $e 'operationName'
            $kind = & $classify $code $message $statusCode $operation (& $value $e 'category')
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
