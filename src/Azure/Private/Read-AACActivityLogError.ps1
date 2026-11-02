function Read-AACActivityLogError {
    <#
    .SYNOPSIS
        Why an Activity Log event failed, in plain terms: the innermost error
        code, message and target of its statusMessage, what kind of failure
        it is, and what to do about it. Shared by Get-AACResourceError,
        Invoke-AACActivityLogAssessment and Show-AACActivityLogEvent.
    .DESCRIPTION
        -StatusMessage is the event's properties.statusMessage: ARM's error
        JSON, possibly nested (a deployment's details) and possibly a JSON
        string inside a message. The innermost code wins, except the
        wrappers DeploymentFailed, ResourceDeploymentFailure and Conflict.
        Without a code, -SubStatus then -StatusCode stand in.

        Category follows the code (and -Operation, -EventCategory):
          Policy         RequestDisallowedByPolicy, a policy deny event
          Authorization  AuthorizationFailed, Forbidden...
          Quota          QuotaExceeded, OperationNotAllowed over a quota
          Capacity       SkuNotAvailable, AllocationFailed...
          Throttling     TooManyRequests, throttled
          Lock           ScopeLocked
          Not found      ResourceNotFound, any *NotFound code
          Conflict       Conflict, AnotherOperationInProgress
          Validation     InvalidTemplate, BadRequest, unregistered providers...
          Other          anything else
        Returns @{ Code; Message (whitespace collapsed); Target; Category;
        Fix; Link }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyString()]
        [string] $StatusMessage = '',

        [AllowEmptyString()]
        [string] $StatusCode = '',

        [AllowEmptyString()]
        [string] $SubStatus = '',

        [AllowEmptyString()]
        [string] $Operation = '',

        [AllowEmptyString()]
        [string] $EventCategory = ''
    )

    $get = ${function:Get-AACMember}
    $text = { param($Object, [string] $Path) $v = & $get $Object $Path; if ($null -eq $v) { '' } else { [string]$v } }

    # ARM's error JSON (possibly nested, possibly a string inside a string) -> the innermost code and message.
    $result = @{ Code = ''; Message = ''; Target = '' }
    if ($StatusMessage) {
        $parsed = $null
        try { $parsed = ConvertFrom-Json -InputObject $StatusMessage -AsHashtable -Depth 32 -ErrorAction Stop } catch { $result.Message = $StatusMessage }
        if ($parsed -is [System.Collections.IDictionary]) {
            $node = $parsed
            for ($depth = 0; $depth -lt 6 -and $node -is [System.Collections.IDictionary]; $depth++) {
                $inner = & $get $node 'error'
                if ($inner -is [System.Collections.IDictionary]) { $node = $inner }
                $code = & $text $node 'code'; $message = & $text $node 'message'; $target = & $text $node 'target'
                if ($code -and $code -notin 'DeploymentFailed', 'ResourceDeploymentFailure', 'Conflict' -or -not $result.Code) {
                    if ($code) { $result.Code = $code }
                    if ($message) { $result.Message = $message }
                    if ($target) { $result.Target = $target }
                }
                $details = @(& $get $node 'details' | Where-Object { $_ -is [System.Collections.IDictionary] })
                if (-not $details.Count) { break }
                $node = $details[0]
                # A detail's message is sometimes the error JSON again.
                $nested = & $text $node 'message'
                if ($nested -match '^\s*\{') { try { $node = ConvertFrom-Json -InputObject $nested -AsHashtable -Depth 32 -ErrorAction Stop } catch { $null = $_ } }
            }
            if (-not $result.Message) { $result.Message = (& $text $parsed 'Message') }
        }
    }
    if (-not $result.Code) { $result.Code = if ($SubStatus) { $SubStatus } else { $StatusCode } }
    $result.Message = ($result.Message -replace '\s+', ' ').Trim()

    $docs = 'https://learn.microsoft.com/azure'
    $c = "$($result.Code) $StatusCode"
    $kind = if ($EventCategory -eq 'Policy' -or $c -match '(?i)RequestDisallowedByPolicy|PolicyViolation' -or $Operation -match '(?i)policies/deny') { @{ Category = 'Policy'; Fix = 'Change the request to comply with the policy named in the message, or ask its owner for an exemption (scoped and with an expiry).'; Link = "$docs/governance/policy/troubleshoot/general" } }
    elseif ($c -match '(?i)Authoriz|Forbidden|InvalidAuthenticationToken|AuthenticationFailed|PermissionMismatch') { @{ Category = 'Authorization'; Fix = 'Grant the caller a role with the refused action at that scope (the narrowest role and scope that work) - or, with PIM, activate the eligible role first.'; Link = "$docs/role-based-access-control/troubleshooting" } }
    elseif ($c -match '(?i)Quota' -or ($result.Code -match '(?i)OperationNotAllowed' -and $result.Message -match '(?i)quota|exceed|limit')) { @{ Category = 'Quota'; Fix = 'Request a quota increase for the region and family (Quotas in the portal), or deploy to another region or VM family.'; Link = "$docs/quotas/per-vm-quota-requests" } }
    elseif ($c -match '(?i)SkuNotAvailable|AllocationFailed|ZonalAllocationFailed|OverconstrainedAllocation|OverconstrainedZonalAllocation|CapacityNotAvailable') { @{ Category = 'Capacity'; Fix = 'Try another size, zone or region (Get-AACSkuAvailability shows what you can use) - or reserve capacity (on-demand capacity reservations) for what must start.'; Link = "$docs/virtual-machines/troubleshooting/allocation-failure" } }
    elseif ($c -match '(?i)TooManyRequests|Throttl|\b429\b') { @{ Category = 'Throttling'; Fix = 'Slow the caller down: retry with back-off (honour Retry-After), batch reads, cache what doesn''t change.'; Link = "$docs/azure-resource-manager/management/request-limits-and-throttling" } }
    elseif ($c -match '(?i)ScopeLocked' -or $result.Message -match '(?i)\block\b.*\b(scope|resource)|is locked') { @{ Category = 'Lock'; Fix = 'A lock (CanNotDelete or ReadOnly) blocks the change: remove it for the change, then put it back - or leave it if the lock is doing its job.'; Link = "$docs/azure-resource-manager/management/lock-resources" } }
    elseif ($c -match '(?i)NotFound|\b404\b') { @{ Category = 'Not found'; Fix = 'Something it needs doesn''t exist (yet), or not where it was asked for: check names, IDs, versions and the region, and that dependencies are deployed first (dependsOn).'; Link = "$docs/azure-resource-manager/troubleshooting/error-not-found" } }
    elseif ($c -match '(?i)Conflict|AnotherOperationInProgress|InUse|RetryableError') { @{ Category = 'Conflict'; Fix = 'Another operation was running on the resource, or its state didn''t allow this one: wait for it to finish and retry.'; Link = "$docs/azure-resource-manager/troubleshooting/common-deployment-errors" } }
    elseif ($c -match '(?i)Invalid|BadRequest|Validation|DeploymentFailed|MissingSubscriptionRegistration|NoRegisteredProviderFound|Unsupported') { @{ Category = 'Validation'; Fix = $(if ($c -match '(?i)MissingSubscriptionRegistration|NoRegisteredProviderFound') { 'Register the resource provider in the subscription (Resource providers in the portal).' } else { 'Fix the template or request: the message names the property or parameter Azure rejected.' }); Link = "$docs/azure-resource-manager/troubleshooting/common-deployment-errors" } }
    else { @{ Category = 'Other'; Fix = 'Read the message; retry if it was transient, and check Resource Health and Service Health for the region.'; Link = "$docs/azure-resource-manager/troubleshooting/common-deployment-errors" } }
    @{ Code = $result.Code; Message = $result.Message; Target = $result.Target; Category = $kind.Category; Fix = $kind.Fix; Link = $kind.Link }
}
