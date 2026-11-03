function Read-AACServiceBlueprintPolicy {
    <#
    .SYNOPSIS
        What Azure Policy says about a blueprint's planned resources: the
        policies assigned for each type, the tenant's guardrails, and - in a
        subscription - Azure's own verdict on each planned body.
    .DESCRIPTION
        Assigned (Get-AACAssignedPolicy -ExpandPolicySet): the policies in
        force at the scope - assigned there or inherited, not excluding it,
        not disabled - that target the component's type, or every type.
        An assignment below the scope isn't counted: it doesn't reach a new
        resource group.

        Guardrails: allowed locations, allowed and not allowed resource types
        from the parameter values of the enforced assignments, and whether
        public network access is refused.

        Verdicts, with -SubscriptionId (checkPolicyRestrictions, which works
        on a subscription or resource group, not a management group): Blocks,
        Audits or Changes for the planned body; then the same body opened to
        the internet, so 'public access is refused' is Azure's answer. Under a
        management group the public access guardrail comes from policy names
        only, and says so.

        Returns @{ Policies; Guardrails; Verdicts (component ID -> evaluations
        and restrictions); Notices; Checked }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Component,

        [string] $SubscriptionId,

        [string] $ManagementGroupId,

        [Parameter(Mandatory)]
        [string] $Region
    )

    $notices = [System.Collections.Generic.List[string]]::new()
    $target = if ($SubscriptionId) { "/subscriptions/$SubscriptionId" } else { "/providers/Microsoft.Management/managementGroups/$ManagementGroupId" }
    $scope = if ($SubscriptionId) { @{ SubscriptionId = $SubscriptionId } } else { @{ ManagementGroupId = $ManagementGroupId } }
    $rows = @(Get-AACAssignedPolicy @scope -ExpandPolicySet -NoDisplay)

    $reaches = {
        param($Row)
        if (-not $Row.Inherited -and ([string]$Row.AssignmentScope).TrimEnd('/') -ine $target) { return $false }
        -not @(([string]$Row.NotScopes) -split ',\s*' | Where-Object { $_ -and $target -ieq $_.TrimEnd('/') }).Count
    }
    $inForce = @($rows | Where-Object { (& $reaches $_) -and [string]$_.Effect -ine 'disabled' })
    $names = @{}
    foreach ($row in $rows) { $names[([string]$row.AssignmentId).ToLowerInvariant()] = $(if ($row.AssignmentDisplayName) { [string]$row.AssignmentDisplayName } else { [string]$row.AssignmentName }) }

    $targets = {
        param([string] $Types, [string] $Type)
        if ($Types -eq 'All') { return $true }
        if ($Types.StartsWith('All except ')) { return -not @($Types.Substring(11) -split ', ' | Where-Object { $Type -like $_ }).Count }
        [bool]@($Types -split ', ' | Where-Object { $_ -and $Type -like $_ }).Count
    }
    $impactOf = {
        param([string] $Effect, [string] $Enforcement)
        $impact = switch ($Effect.ToLowerInvariant()) {
            'deny' { 'Blocks' } 'denyaction' { 'Blocks delete' } 'audit' { 'Audits' } 'auditifnotexists' { 'Audits' }
            'modify' { 'Changes' } 'append' { 'Changes' } 'deployifnotexists' { 'Deploys' } 'manual' { 'Manual' }
            default { 'Unknown' }
        }
        if ($Enforcement -eq 'DoNotEnforce' -and $impact -in 'Blocks', 'Blocks delete', 'Changes', 'Deploys') { 'Reports only' } else { $impact }
    }
    $policies = @(foreach ($item in $Component) {
            $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($row in $inForce) {
                if (-not (& $targets ([string]$row.ResourceType) $item.Type) -or -not $seen.Add("$($row.AssignmentId)|$($row.ReferenceId)|$($row.PolicyId)")) { continue }
                [pscustomobject][ordered]@{
                    PSTypeName = 'AAC.ServiceBlueprintPolicy'; ComponentId = $item.Id; Component = $item.Name; ResourceType = $item.Type; Impact = (& $impactOf ([string]$row.Effect) $row.EnforcementMode); Policy = $row.PolicyDisplayName
                    Effect = $row.Effect; Initiative = $row.PolicySetDisplayName; Assignment = $names[([string]$row.AssignmentId).ToLowerInvariant()]; AssignedAt = $row.ScopeName; Enforcement = $row.EnforcementMode; Category = $row.Category
                }
            }
        })

    # --- Azure's verdict on each planned body ---------------------------------------------------------
    $verdicts = @{}
    $allowedByAzure = [System.Collections.Generic.List[string]]::new()
    if ($SubscriptionId) {
        Update-AACProgress -Id 'blueprint-verdict' -Total ([Math]::Max(1, @($Component).Count)) -Description 'Asking Azure Policy about each planned resource'
        foreach ($item in $Component) {
            # No planned body, so there is nothing to ask about: it stays not checked.
            if (-not $item.Resource) { Update-AACProgress -Id 'blueprint-verdict' -Increment 1; continue }
            $content = [ordered]@{ type = $item.Type; name = $item.Name; location = $Region }
            foreach ($key in $item.Resource.Keys) { $content[$key] = $item.Resource[$key] }
            $check = Invoke-AACPolicyRestrictionCheck -Scope $target -ResourceContent $content -ApiVersion $item.ApiVersion -PendingField @('location') -AssignmentName $names
            $publicBlocked = @()
            if (-not $check.Error -and $item.Public.Count) {
                # The same body, open to the internet: only what opening it adds counts.
                $open = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $content -Depth 50) -AsHashtable
                foreach ($key in $item.Public.Keys) { $open['properties'][$key] = $item.Public[$key] }
                $probe = Invoke-AACPolicyRestrictionCheck -Scope $target -ResourceContent $open -ApiVersion $item.ApiVersion -AssignmentName $names
                $already = @($check.Evaluations | ForEach-Object { "$($_.AssignmentId)|$($_.ReferenceId)" })
                if ($probe.Error) { $notices.Add("Azure Policy couldn't be asked about public access to $($item.Name): $($probe.Error)") }
                else { $publicBlocked = @($probe.Evaluations | Where-Object { $_.Outcome -eq 'Blocks' -and "$($_.AssignmentId)|$($_.ReferenceId)" -notin $already }) }
            }
            if ($check.Error) { $notices.Add("Azure Policy couldn't be asked about $($item.Name), so it isn't checked: $($check.Error)") }
            foreach ($restriction in @($check.Restrictions | Where-Object { $_.Field -eq 'location' -and $_.Result -eq 'Required' })) { foreach ($value in $restriction.Values) { if (-not $allowedByAzure.Contains($value)) { $allowedByAzure.Add($value) } } }
            $verdicts[$item.Id] = @{ Checked = -not $check.Error; Evaluations = @($check.Evaluations); Restrictions = @($check.Restrictions); PublicBlocked = $publicBlocked }
            Update-AACProgress -Id 'blueprint-verdict' -Increment 1
        }
        Update-AACProgress -Id 'blueprint-verdict' -Complete -Description "Asked Azure Policy about $(@($Component).Count) planned resource(s)"
    }

    # --- The guardrails ------------------------------------------------------------------------------------
    $enforced = @($inForce | Where-Object { $_.EnforcementMode -ne 'DoNotEnforce' })
    $valuesOf = {
        param([string] $Parameter)
        @($enforced | Where-Object ParameterName -EQ $Parameter | ForEach-Object { , @{ Assignment = $names[([string]$_.AssignmentId).ToLowerInvariant()]; Values = @(([string]$_.EffectiveValue) -split ',\s*' | Where-Object { $_ }) } })
    }
    $guardrails = [System.Collections.Generic.List[object]]::new()
    $addGuard = {
        param([string] $Guardrail, [string] $Applies, [string] $Outcome, [string] $Detail, [string] $Source, [string] $Assignment = '', [string] $ComponentId = '')
        $guardrails.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.ServiceBlueprintGuardrail'; Guardrail = $Guardrail; AppliesTo = $Applies; Outcome = $Outcome; Detail = $Detail; Source = $Source; Assignment = $Assignment; ComponentId = $ComponentId })
    }
    $locations = @(& $valuesOf 'listOfAllowedLocations')
    if ($locations.Count -or $allowedByAzure.Count) {
        $allowed = if ($allowedByAzure.Count) { $allowedByAzure.ToArray() } else { $sets = @($locations | ForEach-Object { , $_.Values }); $common = @($sets[0]); foreach ($set in $sets) { $common = @($common | Where-Object { $set -contains $_ }) }; $common }
        & $addGuard 'Allowed region' $Region $(if (@($allowed | Where-Object { $_ -ieq $Region }).Count) { 'Allowed' } else { 'Blocks' }) "Allowed: $($allowed -join ', ')" $(if ($allowedByAzure.Count) { 'Azure Policy (checked)' } else { 'Assigned parameter values' }) (@($locations | ForEach-Object Assignment | Select-Object -Unique) -join ', ')
    }
    else { & $addGuard 'Allowed region' $Region 'Allowed' 'No enforced assignment limits the region.' 'Assigned parameter values' }
    $allowedTypes = @(& $valuesOf 'listOfResourceTypesAllowed')
    $deniedTypes = @(& $valuesOf 'listOfResourceTypesNotAllowed')
    foreach ($item in $Component) {
        $refused = @($allowedTypes | Where-Object { -not @($_.Values | Where-Object { $item.Type -ieq $_ }).Count }) + @($deniedTypes | Where-Object { @($_.Values | Where-Object { $item.Type -ieq $_ }).Count })
        & $addGuard 'Allowed resource type' $item.Type $(if ($refused.Count) { 'Blocks' } else { 'Allowed' }) $(if ($refused.Count) { 'An enforced assignment doesn''t allow this type.' } elseif ($allowedTypes.Count -or $deniedTypes.Count) { 'Allowed by the enforced assignments.' } else { 'No enforced assignment limits resource types.' }) 'Assigned parameter values' (@($refused | ForEach-Object Assignment | Select-Object -Unique) -join ', ') $item.Id
        if (-not $item.Public.Count) { continue }
        if ($SubscriptionId -and $verdicts[$item.Id].Checked) {
            $blocked = @($verdicts[$item.Id].PublicBlocked)
            & $addGuard 'Public network access' $item.Type $(if ($blocked.Count) { 'Refused' } else { 'Not refused' }) $(if ($blocked.Count) { 'Azure Policy refuses this resource when it is open to the internet.' } else { 'Azure Policy doesn''t refuse it open to the internet; the blueprint keeps it private anyway.' }) 'Azure Policy (checked)' (@($blocked | ForEach-Object Assignment | Select-Object -Unique) -join ', ') $item.Id
        }
        else {
            $named = @($policies | Where-Object { $_.ComponentId -eq $item.Id -and $_.Impact -eq 'Blocks' -and $_.Policy -match '(?i)public (network )?access|private link|private endpoint' })
            & $addGuard 'Public network access' $item.Type $(if ($named.Count) { 'Probably refused' } else { 'Unknown' }) $(if ($named.Count) { 'From policy names only: a deny policy mentions public access or private link.' } else { 'No deny policy mentions it by name. Use -SubscriptionId for Azure''s answer.' }) 'Policy names' (@($named | ForEach-Object Assignment | Select-Object -Unique) -join ', ') $item.Id
        }
    }
    @{ Policies = $policies; Guardrails = $guardrails.ToArray(); Verdicts = $verdicts; Notices = $notices.ToArray(); Checked = [bool]$SubscriptionId }
}
