function ConvertTo-AACPolicyState {
    <#
    .SYNOPSIS
        Builds Get-AACPolicyState's result from Azure Policy state rows
        (Get-AACPolicyStateQuery): one flattened row per resource and
        policy, and the compliance per resource, assignment, subscription,
        resource group and policy.
    .DESCRIPTION
        Rolled up exactly as the Azure portal does
        (https://learn.microsoft.com/azure/governance/policy/concepts/compliance-states):
          - a resource's state across several policies is the one that
            ranks first: Non-compliant, Compliant, Error, Conflicting,
            Protected, Exempt, Unknown - so a resource non-compliant with one
            policy is non-compliant, and one only exempt or unknown
            everywhere else stays compliant when one policy finds it so
          - Not started and Not registered states aren't counted
          - compliance (%) = (Compliant + Exempt + Unknown + Protected
            resources) / every resource counted (those, plus Non-compliant,
            Conflicting and Error)
        per assignment (its policies), per subscription and resource group
        (every assignment in them), per policy (its resources) and overall.

        -Assignment rows name the assignments (display name, scope,
        enforcement); -SubscriptionName and -ManagementGroupName name the
        scopes.

        Returns @{ States (AAC.PolicyState); Resources (AAC.PolicyResource);
        Assignments (AAC.PolicyAssignmentCompliance); Scopes
        (AAC.PolicyScope: subscriptions and resource groups); Policies
        (AAC.PolicyCompliance: one per policy definition, as the portal
        counts them); Stats } - Stats with the portal's tiles:
        CompliantCounted of Resources, NonCompliantInitiatives of
        Initiatives, NonCompliantPolicies of Policies.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyCollection()]
        [object[]] $Row = @(),

        [AllowEmptyCollection()]
        [object[]] $Assignment = @(),

        [hashtable] $SubscriptionName = @{},

        [hashtable] $ManagementGroupName = @{}
    )

    $value = { param($Object, [string] $Key) if ($Object -is [System.Collections.IDictionary]) { if ($Object.Contains($Key)) { $Object[$Key] } } else { Get-AACPropertyValue -InputObject $Object -Name $Key } }
    $text = { param($Object, [string] $Key) $v = & $value $Object $Key; if ($null -eq $v) { '' } else { [string]$v } }
    $subscriptionLabel = { param([string] $Id) $key = $Id.ToLowerInvariant(); if ($SubscriptionName.Contains($key)) { $SubscriptionName[$key] } else { $Id } }
    $scopeLabel = {
        param([string] $Scope)
        if ($Scope -match '(?i)/managementGroups/([^/]+)$') { $mg = $Matches[1]; return "Management group $(if ($ManagementGroupName.Contains($mg.ToLowerInvariant())) { $ManagementGroupName[$mg.ToLowerInvariant()] } else { $mg })" }
        if ($Scope -match '(?i)^/subscriptions/([^/]+)/resourceGroups/([^/]+)$') { return "Resource group $($Matches[2]) ($(& $subscriptionLabel $Matches[1]))" }
        if ($Scope -match '(?i)^/subscriptions/([^/]+)$') { return "Subscription $(& $subscriptionLabel $Matches[1])" }
        $Scope
    }
    $assignments = @{}
    foreach ($entry in $Assignment) {
        $assignments[(& $text $entry 'assignmentId').ToLowerInvariant()] = @{
            Name        = $(if (& $text $entry 'displayName') { & $text $entry 'displayName' } else { & $text $entry 'name' })
            Scope       = & $text $entry 'scope'
            Enforcement = & $text $entry 'enforcement'
        }
    }
    # Azure Policy's rank: the state that wins when a resource has several.
    $stateRank = @{ NonCompliant = 0; Compliant = 1; Error = 2; Conflict = 3; Protected = 4; Exempt = 5; Unknown = 6 }
    # The state names Resource Graph and the portal use, as one spelling.
    $normalize = {
        param([string] $State)
        switch -Regex ($State) {
            '^(?i)noncompliant$|^(?i)non-compliant$' { 'NonCompliant' }
            '^(?i)compliant$' { 'Compliant' }
            '^(?i)exempt(ed)?$' { 'Exempt' }
            '^(?i)conflict(ing)?$' { 'Conflict' }
            '^(?i)error$' { 'Error' }
            '^(?i)protected$' { 'Protected' }
            '^(?i)unknown$' { 'Unknown' }
            default { $State }
        }
    }

    # --- One row per resource and policy -------------------------------------------------------------
    $states = @(foreach ($entry in $Row) {
            $id = & $text $entry 'resourceId'
            $subscription = (& $text $entry 'subscriptionId').ToLowerInvariant()
            if (-not $subscription -and $id -match '^/subscriptions/([^/]+)') { $subscription = $Matches[1] }
            $assignmentId = (& $text $entry 'assignmentId').ToLowerInvariant()
            $known = if ($assignments.Contains($assignmentId)) { $assignments[$assignmentId] } else { $null }
            $group = & $text $entry 'resourceGroup'
            if (-not $group -and $id -match '/resourcegroups/([^/]+)') { $group = $Matches[1] }
            $evaluated = [datetime]::MinValue
            $scope = if ($known -and $known.Scope) { $known.Scope } else { & $text $entry 'assignmentScope' }
            [pscustomobject][ordered]@{
                PSTypeName         = 'AAC.PolicyState'
                ComplianceState    = & $normalize (& $text $entry 'state')
                Resource           = $(if ($id -match '^/subscriptions/[^/]+$') { & $subscriptionLabel $subscription } else { ($id -split '/')[-1] })
                ResourceType       = & $text $entry 'resourceType'
                ResourceGroup      = $group
                SubscriptionName   = & $subscriptionLabel $subscription
                Location           = & $text $entry 'location'
                Policy             = $(if (& $text $entry 'policy') { & $text $entry 'policy' } else { & $text $entry 'definitionName' })
                PolicySet          = $(if (& $text $entry 'policySet') { & $text $entry 'policySet' } else { & $text $entry 'setName' })
                Assignment         = $(if ($known) { $known.Name } elseif (& $text $entry 'assignment') { & $text $entry 'assignment' } else { ($assignmentId -split '/')[-1] })
                AssignmentScope    = & $scopeLabel $scope
                Enforcement        = $(if ($known) { $known.Enforcement } else { '' })
                Effect             = & $text $entry 'effect'
                EvaluatedAt        = $(if ([datetime]::TryParse((& $text $entry 'evaluated'), [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$evaluated)) { $evaluated } else { $null })
                SubscriptionId     = $subscription
                ResourceId         = $id
                PolicyDefinitionId = & $text $entry 'definitionId'
                PolicySetDefinitionId = (& $text $entry 'setId').ToLowerInvariant()
                AssignmentId       = $assignmentId
            }
        })
    $states = @($states | Sort-Object -Property @{ Expression = { if ($stateRank.Contains($_.ComplianceState)) { $stateRank[$_.ComplianceState] } else { 9 } } }, SubscriptionName, ResourceGroup, Resource, Policy)
    # Not started and Not registered: shown, but not part of any roll-up.
    $counted = @($states | Where-Object { $stateRank.Contains($_.ComplianceState) })

    # How a set of states rolls up to its resources: each resource once.
    $verdict = {
        param([object[]] $Items)
        $by = @{}
        foreach ($item in $Items) {
            if (-not $stateRank.Contains($item.ComplianceState)) { continue }
            $key = $item.ResourceId
            if (-not $by.Contains($key) -or $stateRank[$item.ComplianceState] -lt $stateRank[$by[$key]]) { $by[$key] = $item.ComplianceState }
        }
        $counts = @{ NonCompliant = 0; Compliant = 0; Error = 0; Conflict = 0; Protected = 0; Exempt = 0; Unknown = 0 }
        foreach ($v in $by.Values) { $counts[$v]++ }
        $counts.Resources = $by.Count
        # The portal's compliance percentage.
        $good = $counts.Compliant + $counts.Exempt + $counts.Unknown + $counts.Protected
        $counts.Good = $good
        $counts.Rate = if ($by.Count) { [Math]::Round(100 * $good / $by.Count) } else { $null }
        $counts.Verdict = @{}
        foreach ($key in $by.Keys) { $counts.Verdict[$key] = $by[$key] }
        $counts
    }

    # --- Per resource ---------------------------------------------------------------------------------------
    $resources = @(foreach ($group in @($states | Group-Object -Property ResourceId)) {
            $first = $group.Group[0]
            $counts = & $verdict $group.Group
            $bad = @($group.Group | Where-Object ComplianceState -EQ 'NonCompliant')
            [pscustomobject][ordered]@{
                PSTypeName           = 'AAC.PolicyResource'
                Resource             = $first.Resource
                ResourceType         = $first.ResourceType
                ResourceGroup        = $first.ResourceGroup
                SubscriptionName     = $first.SubscriptionName
                Location             = $first.Location
                Compliance           = $(if ($counts.Verdict.Contains($first.ResourceId)) { $counts.Verdict[$first.ResourceId] } else { $first.ComplianceState })
                NonCompliantPolicies = @($bad | ForEach-Object Policy | Select-Object -Unique).Count
                PoliciesEvaluated    = @($group.Group.Policy | Select-Object -Unique).Count
                NonCompliantWith     = (@($bad | ForEach-Object Policy | Select-Object -Unique) -join '; ')
                ResourceId           = $first.ResourceId
            }
        })
    $resources = @($resources | Sort-Object -Property @{ Expression = { if ($stateRank.Contains($_.Compliance)) { $stateRank[$_.Compliance] } else { 9 } } }, @{ Expression = 'NonCompliantPolicies'; Descending = $true }, SubscriptionName, Resource)

    # --- Per assignment, scope and policy ----------------------------------------------------------------------
    $assignmentRows = @(foreach ($group in @($states | Group-Object -Property AssignmentId)) {
            $first = $group.Group[0]
            $counts = & $verdict $group.Group
            [pscustomobject][ordered]@{
                PSTypeName           = 'AAC.PolicyAssignmentCompliance'
                Assignment           = $first.Assignment
                Scope                = $first.AssignmentScope
                Enforcement          = $first.Enforcement
                ComplianceRate       = $counts.Rate
                NonCompliant         = $counts.NonCompliant
                Compliant            = $counts.Compliant
                Exempt               = $counts.Exempt
                NonCompliantPolicies = @($group.Group | Where-Object ComplianceState -EQ 'NonCompliant' | ForEach-Object Policy | Select-Object -Unique).Count
                AssignmentId         = $first.AssignmentId
            }
        })
    $assignmentRows = @($assignmentRows | Sort-Object -Property @{ Expression = { if ($null -eq $_.ComplianceRate) { 101 } else { $_.ComplianceRate } } }, Assignment)
    $scopes = @(
        foreach ($group in @($states | Group-Object -Property SubscriptionId)) {
            $counts = & $verdict $group.Group
            [pscustomobject][ordered]@{ PSTypeName = 'AAC.PolicyScope'; Level = 'Subscription'; Name = $group.Group[0].SubscriptionName; SubscriptionName = $group.Group[0].SubscriptionName; ComplianceRate = $counts.Rate; Resources = $counts.Resources; NonCompliant = $counts.NonCompliant; Compliant = $counts.Compliant; Exempt = $counts.Exempt; SubscriptionId = $group.Name }
        }
        foreach ($group in @($states | Where-Object ResourceGroup | Group-Object -Property { "$($_.SubscriptionId)|$($_.ResourceGroup.ToLowerInvariant())" })) {
            $counts = & $verdict $group.Group
            [pscustomobject][ordered]@{ PSTypeName = 'AAC.PolicyScope'; Level = 'ResourceGroup'; Name = $group.Group[0].ResourceGroup; SubscriptionName = $group.Group[0].SubscriptionName; ComplianceRate = $counts.Rate; Resources = $counts.Resources; NonCompliant = $counts.NonCompliant; Compliant = $counts.Compliant; Exempt = $counts.Exempt; SubscriptionId = $group.Group[0].SubscriptionId }
        }
    )
    $scopes = @($scopes | Sort-Object -Property @{ Expression = { if ($_.Level -eq 'Subscription') { 0 } else { 1 } } }, @{ Expression = { if ($null -eq $_.ComplianceRate) { 101 } else { $_.ComplianceRate } } }, SubscriptionName, Name)
    # A policy is a definition (as the portal counts them), whatever its name.
    $policies = @(foreach ($group in @($states | Group-Object -Property { if ($_.PolicyDefinitionId) { $_.PolicyDefinitionId } else { $_.Policy } })) {
            $counts = & $verdict $group.Group
            [pscustomobject][ordered]@{
                PSTypeName     = 'AAC.PolicyCompliance'
                Policy         = $group.Group[0].Policy
                PolicySet      = (@($group.Group.PolicySet | Where-Object { $_ } | Select-Object -Unique) -join '; ')
                Effect         = (@($group.Group.Effect | Where-Object { $_ } | Select-Object -Unique) -join ', ')
                ComplianceRate = $counts.Rate
                NonCompliant   = $counts.NonCompliant
                Compliant      = $counts.Compliant
                Exempt         = $counts.Exempt
                Assignments    = (@($group.Group.Assignment | Select-Object -Unique) -join '; ')
            }
        })
    $policies = @($policies | Sort-Object -Property @{ Expression = 'NonCompliant'; Descending = $true }, Policy)

    $overall = & $verdict $counted
    # Initiatives, as the portal counts them: each initiative once, non-compliant
    # when any of its policies finds a resource so.
    $initiatives = @($counted | Where-Object PolicySetDefinitionId | Group-Object -Property PolicySetDefinitionId)
    @{
        States      = $states
        Resources   = $resources
        Assignments = $assignmentRows
        Scopes      = $scopes
        Policies    = $policies
        # Get-AACPolicyState adds what the reader should know.
        Notice      = @()
        Stats       = @{
            States               = $states.Count
            Resources            = $overall.Resources
            # The portal's "313 out of 2560": compliant, exempt, unknown and protected.
            CompliantCounted     = $overall.Good
            Compliant            = $overall.Compliant
            NonCompliant         = $overall.NonCompliant
            Exempt               = $overall.Exempt
            Unknown              = $overall.Unknown
            Error                = $overall.Error
            Conflict             = $overall.Conflict
            Protected            = $overall.Protected
            NotCounted           = $states.Count - $counted.Count
            ComplianceRate       = $overall.Rate
            Assignments          = $assignmentRows.Count
            Policies             = $policies.Count
            NonCompliantPolicies = @($policies | Where-Object NonCompliant -GT 0).Count
            Initiatives          = $initiatives.Count
            NonCompliantInitiatives = @($initiatives | Where-Object { @($_.Group | Where-Object ComplianceState -EQ 'NonCompliant').Count }).Count
            Subscriptions        = @($scopes | Where-Object Level -EQ 'Subscription').Count
            ResourceGroups       = @($scopes | Where-Object Level -EQ 'ResourceGroup').Count
            ByState              = @($states | Group-Object ComplianceState | ForEach-Object { [pscustomobject]@{ Label = $_.Name; Value = $_.Count } } | Sort-Object Value -Descending)
        }
    }
}
