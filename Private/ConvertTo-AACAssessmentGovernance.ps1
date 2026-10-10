function ConvertTo-AACAssessmentGovernance {
    <#
    .SYNOPSIS
        Builds Invoke-AACAssessment's governance sheets: policy compliance
        (by initiative, by resource group, by standard and control, and each
        non-compliant resource with why and how to fix it), the policy
        inventory, PSRule for Azure's results, and one list of every
        recommendation for the resources.
    .DESCRIPTION
        Sheets, in ConvertTo-AACAssessment's shape (so the CSV, HTML and PDF
        writers take them as they are):
          Policy             Compliance by initiative, Compliance by resource
                             group, Compliance by standard (the controls of
                             the initiatives that group their policies, as
                             the regulatory ones do), Non-compliant resources
          Policy inventory   Policy assignments, Policies (each policy in
                             force, per assignment: effect, resource types,
                             controls, status - Failed, Passed, Manual
                             review, Exempt, Not evaluated or Disabled)
          PSRule             PSRule rules (checked, passed, failed), PSRule
                             results (the failures and errors)
          Recommendations    Resource recommendations: Advisor, Defender for
                             Cloud, retirements, unattached and empty
                             resources, policy non-compliance and PSRule's
                             failures, each with a severity, a category
                             (Cost, Security, Reliability, Operational
                             excellence, Performance, Governance) and what
                             to do
        Returns @{ Sheets; Stats; Notices }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        # ConvertTo-AACAssessment's sheets: Advisor, Defender, retirements
        # and the inventory feed the recommendations.
        [object[]] $Sheet = @(),

        # The Estate read's policy rows (per assignment and policy).
        [object[]] $Policy = @(),

        # Policy compliance per resource group (policyByGroup).
        [object[]] $PolicyByGroup = @(),

        # The non-compliant resources (policyResources).
        [object[]] $PolicyResource = @(),

        # ConvertTo-AACAssignedPolicy's result: the assignments and their policies.
        [hashtable] $AssignedPolicy,

        # Invoke-AACPSRuleEngine's results.
        [object[]] $PSRuleResult = @(),

        [System.Collections.IDictionary] $SubscriptionName = @{},

        [switch] $PolicyRead,

        [switch] $PSRuleRead,

        # The cap on the non-compliant resources read, to say when it was reached.
        [int] $PolicyResourceLimit = 5000,

        [datetime] $Now = [datetime]::UtcNow
    )

    $value = {
        param($Row, [string] $Name)
        if ($Row -is [System.Collections.IDictionary]) { $Row[$Name] }
        elseif ($null -ne $Row -and $Row.PSObject.Properties[$Name]) { $Row.PSObject.Properties[$Name].Value }
    }
    $lower = { param($Text) ([string]$Text).ToLowerInvariant() }
    $leaf = { param($Id) if ($Id) { ([string]$Id).TrimEnd('/') -replace '^.*/', '' } else { '' } }
    $typeOf = { param($Id) if ([string]$Id -match '(?i)/providers/([^/]+/[^/]+)/[^/]+$') { $Matches[1].ToLowerInvariant() } elseif ([string]$Id -match '(?i)/resourceGroups/[^/]+$') { 'microsoft.resources/resourcegroups' } else { '' } }
    $slug = { param([string] $Name) ($Name.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-') }
    $percent = { param([int] $Good, [int] $Bad) if ($Good + $Bad) { [Math]::Round($Good / ($Good + $Bad) * 100, 1) } else { $null } }
    $subscriptionLabel = { param($Id) $key = & $lower $Id; if ($SubscriptionName.Contains($key)) { [string]$SubscriptionName[$key] } else { [string]$Id } }
    $newSheet = {
        param([string] $Category, [string] $Name, [System.Collections.IDictionary] $Types, [object[]] $Rows, [string[]] $Key, [string] $Note)
        @{ Id = & $slug $Name; Kind = 'Governance'; Category = $Category; Sheet = $Name; Columns = @($Types.Keys); Types = $Types; Rows = @($Rows); Key = @($Key); Error = ''; Note = $Note }
    }
    $findSheet = { param([string] $Name) @($Sheet | Where-Object { $_.Sheet -eq $Name }) | Select-Object -First 1 }
    $sheets = [System.Collections.Generic.List[hashtable]]::new()
    $notices = [System.Collections.Generic.List[string]]::new()
    $learn = 'https://learn.microsoft.com/azure/governance/policy/how-to'

    # A policy's status from its states: what the compliance chart counts.
    $statusOf = {
        param([int] $NonCompliant, [int] $Compliant, [int] $Exempt, [int] $Other, [string] $Effect)
        if ($Effect -eq 'disabled') { 'Disabled' }
        elseif ($NonCompliant) { 'Failed' }
        elseif ($Effect -eq 'manual' -or ($Other -and -not $Compliant)) { 'Manual review' }
        elseif ($Compliant) { 'Passed' }
        elseif ($Exempt) { 'Exempt' }
        else { 'Not evaluated' }
    }
    $remedy = {
        param([string] $Effect)
        switch ($Effect.ToLowerInvariant()) {
            { $_ -in 'deployifnotexists', 'modify' } { 'Create a remediation task for the assignment (Azure Policy > Remediation): it deploys or changes what the policy expects on the existing resources.'; break }
            'deny' { 'Change the resource to meet the policy - new and updated resources that don''t are already denied - or exempt it, with a reason.'; break }
            'auditifnotexists' { 'Deploy or configure the related resource the policy looks for (diagnostic settings, an extension, a setting), or exempt the resource, with a reason.'; break }
            'audit' { 'Change the resource''s configuration to meet the policy, or exempt it, with a reason.'; break }
            'manual' { 'Attest its compliance (a policy attestation), with the evidence.'; break }
            default { 'Review what the policy requires and change the resource, or exempt it, with a reason.' }
        }
    }
    # Resource Graph gives the effect in lower case; the definitions, as written.
    $effectNames = @{ deny = 'Deny'; audit = 'Audit'; auditifnotexists = 'AuditIfNotExists'; deployifnotexists = 'DeployIfNotExists'; modify = 'Modify'; append = 'Append'; manual = 'Manual'; disabled = 'Disabled'; denyaction = 'DenyAction' }
    $effectName = { param($Effect) $key = ([string]$Effect).ToLowerInvariant(); if ($effectNames.Contains($key)) { $effectNames[$key] } else { [string]$Effect } }
    $remedyLink = { param([string] $Effect) if ($Effect -in 'deployifnotexists', 'modify') { "$learn/remediate-resources" } else { "$learn/determine-non-compliance" } }

    # --- Policy: the compliance per assignment and policy (the Estate read) -------------------------------------------------
    $stateOf = @{}   # assignmentId|definitionId -> the row
    foreach ($row in $Policy) { $stateOf["$(& $lower (& $value $row 'assignmentId'))|$(& $lower (& $value $row 'definitionId'))"] = $row }
    $policyStatus = @{}   # the same key -> Failed, Passed, ...
    foreach ($key in $stateOf.Keys) {
        $row = $stateOf[$key]
        $policyStatus[$key] = & $statusOf ([int](& $value $row 'nonCompliant')) ([int](& $value $row 'compliant')) ([int](& $value $row 'exempt')) ([int](& $value $row 'other')) (& $lower (& $value $row 'effect'))
    }
    $byAssignment = @{}
    foreach ($row in $Policy) {
        $id = & $lower (& $value $row 'assignmentId')
        if (-not $byAssignment.Contains($id)) { $byAssignment[$id] = [System.Collections.Generic.List[object]]::new() }
        $byAssignment[$id].Add($row)
    }
    $assignmentTotals = @{}
    foreach ($id in $byAssignment.Keys) {
        $rows = @($byAssignment[$id])
        $sum = { param([string] $Name) [int](@($rows | ForEach-Object { [int](& $value $_ $Name) }) | Measure-Object -Sum).Sum }
        $statuses = @($rows | ForEach-Object { $policyStatus["$id|$(& $lower (& $value $_ 'definitionId'))"] })
        $assignmentTotals[$id] = @{
            Policies = $rows.Count; Failed = @($statuses | Where-Object { $_ -eq 'Failed' }).Count
            NonCompliant = & $sum 'nonCompliant'; Compliant = & $sum 'compliant'; Exempt = & $sum 'exempt'; Other = & $sum 'other'
            Status = $(if ($statuses -contains 'Failed') { 'Failed' } elseif ($statuses -contains 'Manual review') { 'Manual review' } elseif ($statuses -contains 'Passed') { 'Passed' } elseif ($statuses -contains 'Exempt') { 'Exempt' } else { 'Not evaluated' })
            First = $rows[0]
        }
    }

    $nonCompliantResources = 0
    if ($PolicyRead) {
        $initiativeRows = foreach ($id in $assignmentTotals.Keys) {
            $t = $assignmentTotals[$id]; $first = $t.First
            $setName = [string](& $value $first 'policySet')
            [pscustomobject][ordered]@{
                'Assignment' = [string]$(@((& $value $first 'assignment'), (& $value $first 'assignmentName')) | Where-Object { $_ } | Select-Object -First 1)
                'Initiative or policy' = $(if ($setName) { $setName } elseif ((& $value $first 'setId')) { & $leaf (& $value $first 'setId') } else { [string]$(@((& $value $first 'policy'), (& $leaf (& $value $first 'definitionId'))) | Where-Object { $_ } | Select-Object -First 1) })
                'Kind' = $(if ((& $value $first 'setId')) { 'Initiative' } else { 'Policy' })
                'Status' = $t.Status; 'Policies' = $t.Policies; 'Failed policies' = $t.Failed
                'Non-compliant' = $t.NonCompliant; 'Compliant' = $t.Compliant; 'Exempt' = $t.Exempt; 'Compliance (%)' = & $percent $t.Compliant $t.NonCompliant
                'Scope' = [string](& $value $first 'assignmentScope'); 'ResourceId' = [string](& $value $first 'assignmentId')
            }
        }
        $sheets.Add((& $newSheet 'Policy' 'Compliance by initiative' ([ordered]@{ 'Assignment' = 'text'; 'Initiative or policy' = 'wide'; 'Kind' = 'badge'; 'Status' = 'badge'; 'Policies' = 'number'; 'Failed policies' = 'number'; 'Non-compliant' = 'number'; 'Compliant' = 'number'; 'Exempt' = 'number'; 'Compliance (%)' = 'score'; 'Scope' = 'mono' }) `
                    @($initiativeRows | Sort-Object -Property @{ Expression = 'Failed policies'; Descending = $true }, @{ Expression = 'Non-compliant'; Descending = $true }, Assignment) @('Assignment', 'Initiative or policy', 'Status', 'Failed policies', 'Compliance (%)') `
                    'Each assignment: its policies by status, and the resource states (one per resource and policy) in each compliance state.'))

        $groupRows = foreach ($row in $PolicyByGroup) {
            $subscriptionId = [string](& $value $row 'subscriptionId'); $group = [string](& $value $row 'resourceGroup')
            $bad = [int](& $value $row 'nonCompliant'); $good = [int](& $value $row 'compliant'); $exempt = [int](& $value $row 'exempt')
            [pscustomobject][ordered]@{
                'Subscription' = & $subscriptionLabel $subscriptionId; 'Resource group' = $(if ($group) { $group } else { '(the subscription)' })
                'Status' = $(if ($bad) { 'Failed' } elseif ($good) { 'Passed' } elseif ($exempt) { 'Exempt' } else { 'Not evaluated' })
                'Resources' = [int](& $value $row 'resources'); 'Non-compliant' = $bad; 'Compliant' = $good; 'Exempt' = $exempt; 'Compliance (%)' = & $percent $good $bad
                'Non-compliant states' = [int](& $value $row 'nonCompliantStates')
                'ResourceId' = $(if ($group) { "/subscriptions/$subscriptionId/resourceGroups/$group" } else { "/subscriptions/$subscriptionId" })
            }
        }
        $sheets.Add((& $newSheet 'Policy' 'Compliance by resource group' ([ordered]@{ 'Subscription' = 'text'; 'Resource group' = 'resource'; 'Status' = 'badge'; 'Resources' = 'number'; 'Non-compliant' = 'number'; 'Compliant' = 'number'; 'Exempt' = 'number'; 'Compliance (%)' = 'score'; 'Non-compliant states' = 'number' }) `
                    @($groupRows | Sort-Object -Property @{ Expression = 'Non-compliant'; Descending = $true }, Subscription, 'Resource group') @('Subscription', 'Resource group', 'Status', 'Non-compliant', 'Compliance (%)') `
                    'Resources counted once: non-compliant with any policy, else compliant (or exempt).'))

        $resourceRows = foreach ($row in $PolicyResource) {
            $resourceId = [string](& $value $row 'resourceId'); $effect = [string](& $value $row 'effect')
            $policyName = [string]$(@((& $value $row 'policy'), (& $leaf (& $value $row 'definitionId'))) | Where-Object { $_ } | Select-Object -First 1)
            $description = [string](& $value $row 'description')
            $code = [string](& $value $row 'reasonCode')
            $why = switch ($effect.ToLowerInvariant()) {
                'auditifnotexists' { 'The related resource or setting the policy checks for is missing, or not configured as it requires.'; break }
                'deployifnotexists' { 'The related resource or setting the policy deploys is missing, or not configured as it requires.'; break }
                'manual' { 'Its compliance is attested by hand, and hasn''t been.'; break }
                default { 'The resource''s configuration doesn''t match what the policy requires.' }
            }
            [pscustomobject][ordered]@{
                'Resource' = & $leaf $resourceId; 'Resource type' = [string](& $value $row 'resourceType'); 'Resource group' = [string](& $value $row 'resourceGroup')
                'Subscription' = & $subscriptionLabel (& $value $row 'subscriptionId'); 'Policy' = $policyName
                'Initiative' = [string](& $value $row 'policySet'); 'Assignment' = [string]$(@((& $value $row 'assignment'), (& $leaf (& $value $row 'assignmentId'))) | Where-Object { $_ } | Select-Object -First 1)
                'Effect' = & $effectName $effect
                'Reason' = (@($why, $(if ($code) { "Reason code: $code." }), $(if ($description) { "The policy: $description" })) | Where-Object { $_ }) -join ' '
                'Remediation' = & $remedy $effect; 'Evaluated' = [string](& $value $row 'evaluated'); 'Link' = & $remedyLink ($effect.ToLowerInvariant())
                'Controls' = [string](& $value $row 'groups'); 'ResourceId' = $resourceId
            }
        }
        $resourceRows = @($resourceRows)
        $nonCompliantResources = @($resourceRows | ForEach-Object { & $lower $_.ResourceId } | Select-Object -Unique).Count
        if ($resourceRows.Count -ge $PolicyResourceLimit) { $notices.Add("The non-compliant resources list stops at $PolicyResourceLimit resource-and-policy pairs; Compliance by resource group counts them all. Narrow the scope (-SubscriptionId, -ResourceGroupName) for the rest.") }
        $sheets.Add((& $newSheet 'Policy' 'Non-compliant resources' ([ordered]@{ 'Resource' = 'resource'; 'Resource type' = 'mono'; 'Resource group' = 'text'; 'Subscription' = 'text'; 'Policy' = 'wide'; 'Initiative' = 'text'; 'Assignment' = 'text'; 'Effect' = 'badge'; 'Reason' = 'wide'; 'Remediation' = 'wide'; 'Evaluated' = 'text'; 'Link' = 'link'; 'Controls' = 'wide' }) `
                    @($resourceRows | Sort-Object Subscription, 'Resource group', Resource, Policy) @('Resource', 'Resource group', 'Policy', 'Effect', 'Reason') `
                    'Each resource and the policy it fails: why, and how to fix it. For the evaluated field and its value, open the resource''s compliance details in the Azure portal (Policy > Compliance).'))
    }

    # --- Policy inventory: the assignments and every policy in force -----------------------------------------------------
    $policyRows = @()
    if ($AssignedPolicy) {
        $assignmentRows = foreach ($a in @($AssignedPolicy.Assignments)) {
            $id = & $lower $a.AssignmentId
            $t = if ($assignmentTotals.Contains($id)) { $assignmentTotals[$id] } else { $null }
            [pscustomobject][ordered]@{
                'Assignment' = [string]$a.AssignmentDisplayName; 'Definition' = [string]$a.DefinitionDisplayName; 'Kind' = $(if ($a.DefinitionType -eq 'PolicySet') { 'Initiative' } else { 'Policy' })
                'Status' = $(if ($t) { $t.Status } else { 'Not evaluated' }); 'Enforcement' = [string]$a.EnforcementMode
                'Scope' = "$($a.ScopeType): $($a.ScopeName)"; 'Inherited' = $(if ($a.Inherited) { 'Yes' } else { 'No' }); 'Policies' = [int]$a.Members; 'Category' = [string]$a.Category
                'Policy type' = [string]$a.PolicyType; 'Resource types' = [string]$a.ResourceType
                'Non-compliant' = $(if ($t) { $t.NonCompliant } else { 0 }); 'Compliance (%)' = $(if ($t) { & $percent $t.Compliant $t.NonCompliant } else { $null })
                'Not scopes' = [string]$a.NotScopes; 'ResourceId' = [string]$a.AssignmentId
            }
        }
        $sheets.Add((& $newSheet 'Policy inventory' 'Policy assignments' ([ordered]@{ 'Assignment' = 'text'; 'Definition' = 'wide'; 'Kind' = 'badge'; 'Status' = 'badge'; 'Enforcement' = 'badge'; 'Scope' = 'text'; 'Inherited' = 'badge'; 'Policies' = 'number'; 'Category' = 'text'; 'Policy type' = 'text'; 'Resource types' = 'wide'; 'Non-compliant' = 'number'; 'Compliance (%)' = 'score'; 'Not scopes' = 'wide' }) `
                    @($assignmentRows) @('Assignment', 'Definition', 'Kind', 'Status', 'Enforcement', 'Scope') 'Every policy assignment in force on the scope - inherited from management groups too.'))

        # Members come one per parameter: one row per assignment and policy.
        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $policyRows = @(foreach ($m in @($AssignedPolicy.Members)) {
                $key = "$(& $lower $m.AssignmentId)|$(& $lower $m.PolicyId)"
                if (-not $seen.Add("$key|$($m.ReferenceId)")) { continue }
                $state = if ($stateOf.Contains($key)) { $stateOf[$key] } else { $null }
                $effect = [string]$m.Effect
                $status = if ($effect -eq 'Disabled') { 'Disabled' } elseif ($policyStatus.Contains($key)) { $policyStatus[$key] } elseif ($effect -eq 'Manual') { 'Manual review' } else { 'Not evaluated' }
                $bad = if ($state) { [int](& $value $state 'nonCompliant') } else { 0 }
                $good = if ($state) { [int](& $value $state 'compliant') } else { 0 }
                [pscustomobject][ordered]@{
                    'Policy' = [string]$m.PolicyDisplayName; 'Status' = $status; 'Effect' = $effect; 'Assignment' = [string]$m.AssignmentDisplayName
                    'Initiative' = [string]$m.PolicySetDisplayName; 'Category' = [string]$m.Category; 'Policy type' = [string]$m.PolicyType
                    'Resource types' = [string]$m.ResourceType; 'Controls' = [string]$m.Groups
                    'Non-compliant' = $bad; 'Compliant' = $good; 'Compliance (%)' = & $percent $good $bad
                    'Scope' = "$($m.ScopeType): $($m.ScopeName)"; 'ResourceId' = [string]$m.PolicyId; 'AssignmentId' = [string]$m.AssignmentId
                }
            })
        $statusRank = @{ Failed = 0; 'Manual review' = 1; 'Not evaluated' = 2; Exempt = 3; Passed = 4; Disabled = 5 }
        $sheets.Add((& $newSheet 'Policy inventory' 'Policies' ([ordered]@{ 'Policy' = 'wide'; 'Status' = 'badge'; 'Effect' = 'badge'; 'Assignment' = 'text'; 'Initiative' = 'text'; 'Category' = 'text'; 'Policy type' = 'text'; 'Resource types' = 'wide'; 'Controls' = 'wide'; 'Non-compliant' = 'number'; 'Compliant' = 'number'; 'Compliance (%)' = 'score'; 'Scope' = 'text' }) `
                    @($policyRows | Sort-Object -Property @{ Expression = { $statusRank[$_.Status] } }, @{ Expression = 'Non-compliant'; Descending = $true }, Assignment, Policy) @('Policy', 'Status', 'Effect', 'Assignment', 'Resource types') `
                    'Every policy in force, per assignment: its effect (with the assignment''s parameters), the resource types it targets, the controls it maps to, and its status - Failed, Passed, Manual review, Exempt, Not evaluated or Disabled.'))

        # --- Compliance by standard: the initiatives' controls (their policy definition groups) ----------------------------
        $controls = [ordered]@{}
        foreach ($p in $policyRows) {
            if (-not $p.Controls -or -not $p.Initiative) { continue }
            foreach ($control in @(([string]$p.Controls) -split ',\s*' | Where-Object { $_ })) {
                $key = "$($p.AssignmentId)|$control"
                if (-not $controls.Contains($key)) { $controls[$key] = @{ Standard = $p.Initiative; Assignment = $p.Assignment; Control = $control; Policies = [System.Collections.Generic.List[object]]::new(); AssignmentId = $p.AssignmentId } }
                $controls[$key].Policies.Add($p)
            }
        }
        $standardRows = foreach ($c in $controls.Values) {
            $statuses = @($c.Policies.Status)
            [pscustomobject][ordered]@{
                'Standard' = $c.Standard; 'Control' = $c.Control
                'Status' = $(if ($statuses -contains 'Failed') { 'Failed' } elseif ($statuses -contains 'Manual review') { 'Manual review' } elseif ($statuses -contains 'Passed') { 'Passed' } elseif ($statuses -contains 'Exempt') { 'Exempt' } elseif (-not @($statuses | Where-Object { $_ -ne 'Disabled' }).Count) { 'Disabled' } else { 'Not evaluated' })
                'Policies' = $c.Policies.Count; 'Failed policies' = @($statuses | Where-Object { $_ -eq 'Failed' }).Count
                'Non-compliant' = [int](@($c.Policies | ForEach-Object { $_.'Non-compliant' }) | Measure-Object -Sum).Sum
                'Failing policies' = (@($c.Policies | Where-Object Status -EQ 'Failed' | ForEach-Object { $_.Policy }) | Select-Object -Unique) -join '; '
                'Assignment' = $c.Assignment; 'ResourceId' = $c.AssignmentId
            }
        }
        if (@($standardRows).Count) {
            $sheets.Add((& $newSheet 'Policy' 'Compliance by standard' ([ordered]@{ 'Standard' = 'text'; 'Control' = 'mono'; 'Status' = 'badge'; 'Policies' = 'number'; 'Failed policies' = 'number'; 'Non-compliant' = 'number'; 'Failing policies' = 'wide'; 'Assignment' = 'text' }) `
                        @($standardRows | Sort-Object Standard, @{ Expression = { $statusRank[$_.Status] } }, Control) @('Standard', 'Control', 'Status', 'Failed policies') `
                        'The controls of each initiative that maps its policies to a standard (its policy definition groups - CIS, NIST, ISO 27001, the Microsoft cloud security benchmark ...), with the policies behind each.'))
        }
    }
    elseif ($PolicyRead) { $notices.Add('The policy assignments couldn''t be read, so the policy inventory is missing.') }

    # --- PSRule for Azure ----------------------------------------------------------------------------------------------
    $psruleRows = @($PSRuleResult | Where-Object { $_ })
    if ($PSRuleRead) {
        $joinText = { param($Item) (@($Item) | Where-Object { $_ } | ForEach-Object { [string]$_ }) -join ' ' }
        $ruleRows = foreach ($group in @($psruleRows | Group-Object -Property RuleName)) {
            $first = $group.Group[0]
            $passed = @($group.Group | Where-Object Outcome -EQ 'Pass').Count; $failed = @($group.Group | Where-Object Outcome -EQ 'Fail').Count
            [pscustomobject][ordered]@{
                'Rule' = $(if ($first.Title) { [string]$first.Title } else { [string]$first.RuleName }); 'Name' = [string]$first.RuleName; 'Pillar' = [string]$first.Pillar; 'Severity' = [string]$first.Severity
                'Status' = $(if ($failed) { 'Failed' } elseif (@($group.Group | Where-Object Outcome -EQ 'Error').Count) { 'Error' } else { 'Passed' })
                'Checked' = $group.Count; 'Passed' = $passed; 'Failed' = $failed; 'Errors' = @($group.Group | Where-Object Outcome -EQ 'Error').Count
                'Pass (%)' = & $percent $passed $failed; 'Recommendation' = & $joinText $first.Recommendation; 'Link' = [string]$first.Link; 'ResourceId' = ''
            }
        }
        $sheets.Add((& $newSheet 'PSRule' 'PSRule rules' ([ordered]@{ 'Rule' = 'wide'; 'Name' = 'mono'; 'Pillar' = 'text'; 'Severity' = 'badge'; 'Status' = 'badge'; 'Checked' = 'number'; 'Passed' = 'number'; 'Failed' = 'number'; 'Errors' = 'number'; 'Pass (%)' = 'score'; 'Recommendation' = 'wide'; 'Link' = 'link' }) `
                    @($ruleRows | Sort-Object -Property @{ Expression = 'Failed'; Descending = $true }, Rule) @('Rule', 'Pillar', 'Severity', 'Checked', 'Passed', 'Failed') `
                    'Each PSRule for Azure rule run on the resources: how many it checked, passed and failed, and its documentation.'))
        $resultRows = foreach ($r in @($psruleRows | Where-Object { $_.Outcome -in 'Fail', 'Error' })) {
            [pscustomobject][ordered]@{
                'Outcome' = [string]$r.Outcome; 'Severity' = [string]$r.Severity; 'Rule' = $(if ($r.Title) { [string]$r.Title } else { [string]$r.RuleName }); 'Pillar' = [string]$r.Pillar
                'Resource' = [string]$r.ResourceName; 'Resource type' = [string]$r.ResourceType; 'Resource group' = [string]$r.ResourceGroup; 'Subscription' = [string]$r.SubscriptionName
                'Reason' = & $joinText $r.Reason; 'Recommendation' = & $joinText $r.Recommendation; 'Link' = [string]$r.Link; 'Name' = [string]$r.RuleName; 'ResourceId' = [string]$r.ResourceId
            }
        }
        $sheets.Add((& $newSheet 'PSRule' 'PSRule results' ([ordered]@{ 'Outcome' = 'badge'; 'Severity' = 'badge'; 'Rule' = 'wide'; 'Pillar' = 'text'; 'Resource' = 'resource'; 'Resource type' = 'mono'; 'Resource group' = 'text'; 'Subscription' = 'text'; 'Reason' = 'wide'; 'Recommendation' = 'wide'; 'Link' = 'link'; 'Name' = 'mono' }) `
                    @($resultRows) @('Outcome', 'Severity', 'Rule', 'Resource', 'Reason') 'The resources that failed a rule (or that it couldn''t check), with why.'))
    }

    # --- Resource recommendations: everything to act on, in one list --------------------------------------------------------
    $categoryOf = {
        param([string] $Text)
        switch -Regex ($Text) {
            '(?i)^cost' { 'Cost'; break }
            '(?i)secur' { 'Security'; break }
            '(?i)reliab|availab|resilien' { 'Reliability'; break }
            '(?i)perform' { 'Performance'; break }
            '(?i)operation' { 'Operational excellence'; break }
            default { 'Governance' }
        }
    }
    $recommendations = [System.Collections.Generic.List[object]]::new()
    $add = {
        param([string] $Severity, [string] $Category, [string] $Source, [string] $Recommendation, $Row, [string] $Remediation, [string] $Link, [string] $ResourceId)
        if (-not $ResourceId) { $ResourceId = [string](& $value $Row 'ResourceId') }
        $resourceName = [string](& $value $Row 'Resource')
        $recommendations.Add([pscustomobject][ordered]@{
                'Severity' = $Severity; 'Category' = $Category; 'Source' = $Source; 'Recommendation' = $Recommendation
                'Resource' = $(if ($resourceName) { $resourceName } else { & $leaf $ResourceId })
                'Resource type' = $(if ((& $value $Row 'Resource type')) { [string](& $value $Row 'Resource type') } else { & $typeOf $ResourceId })
                'Resource group' = $(if ((& $value $Row 'Resource group')) { [string](& $value $Row 'Resource group') } elseif ($ResourceId -match '(?i)/resourceGroups/([^/]+)') { $Matches[1] } else { '' })
                'Subscription' = $(if ((& $value $Row 'Subscription')) { [string](& $value $Row 'Subscription') } elseif ($ResourceId -match '(?i)^/subscriptions/([^/]+)') { & $subscriptionLabel $Matches[1] } else { '' })
                'Remediation' = $Remediation; 'Link' = $Link; 'ResourceId' = $ResourceId
            })
    }
    $advisorLink = 'https://portal.azure.com/#view/Microsoft_Azure_Expert/AdvisorMenuBlade/~/overview'
    $advisor = & $findSheet 'Advisor recommendations'
    if ($advisor) { foreach ($row in @($advisor.Rows)) { & $add ([string]$row.Impact) (& $categoryOf ([string]$row.Category)) 'Azure Advisor' ([string]$row.Problem) $row ([string]$row.Solution) $advisorLink '' } }
    $security = & $findSheet 'Security recommendations'
    if ($security) { foreach ($row in @($security.Rows)) { & $add ([string]$row.Severity) 'Security' 'Defender for Cloud' ([string]$row.Recommendation) $row ([string]$row.Remediation) 'https://portal.azure.com/#view/Microsoft_Azure_Security/SecurityMenuBlade/~/5' '' } }
    $retirements = & $findSheet 'Retirements'
    if ($retirements) {
        foreach ($row in @($retirements.Rows)) {
            $date = [datetime]::MinValue
            $known = [datetime]::TryParse([string]$row.'Retirement date', [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$date)
            $days = if ($known) { ($date.ToUniversalTime() - $Now).TotalDays } else { 365 }
            & $add $(if ($days -le 90) { 'High' } elseif ($days -le 365) { 'Medium' } else { 'Low' }) 'Reliability' 'Retirements' "Retiring$(if ($known) { " on $($date.ToString('yyyy-MM-dd'))" }): $($row.Retiring)" $row ([string]$row.'What to do') 'https://azure.microsoft.com/updates/?updateType=retirements' ''
        }
    }
    foreach ($s in @($Sheet | Where-Object { $_.Kind -eq 'Inventory' -and ($_.Columns -contains 'Orphaned' -or $_.Columns -contains 'Empty') })) {
        foreach ($label in 'Orphaned', 'Empty') {
            if ($s.Columns -notcontains $label) { continue }
            foreach ($row in @($s.Rows | Where-Object { $_.$label -eq 'Yes' })) {
                & $add 'Low' 'Cost' 'Inventory' "$($s.Sheet): $(if ($label -eq 'Orphaned') { 'not attached to anything' } else { 'empty' })" $row 'Confirm it isn''t needed (it may be kept for a reason - a reserved IP, a standby disk), then delete it: it costs, and widens what has to be governed.' '' ''
            }
        }
    }
    $disks = & $findSheet 'Disks'
    if ($disks -and $disks.Columns -notcontains 'Orphaned') {
        foreach ($row in @($disks.Rows | Where-Object { $_.State -eq 'Unattached' })) { & $add 'Low' 'Cost' 'Inventory' 'Disk not attached to any VM' $row 'Snapshot it if it might be needed, then delete it: an unattached disk is billed in full.' '' '' }
    }
    $groups = & $findSheet 'Resource groups'
    if ($groups) { foreach ($row in @($groups.Rows | Where-Object { $_.Empty -eq 'Yes' })) { & $add 'Low' 'Operational excellence' 'Inventory' 'Empty resource group' $row 'Delete it if nothing is due to be deployed in it: empty groups keep their role assignments and policies, and clutter the estate.' '' '' } }
    $nonCompliant = @($sheets | Where-Object { $_.Sheet -eq 'Non-compliant resources' }) | Select-Object -First 1
    if ($nonCompliant) {
        foreach ($row in @($nonCompliant.Rows)) {
            $effect = ([string]$row.Effect).ToLowerInvariant()
            & $add $(if ($effect -in 'deny', 'deployifnotexists', 'modify') { 'Medium' } else { 'Low' }) 'Governance' 'Azure Policy' "Non-compliant: $($row.Policy)" $row ([string]$row.Remediation) ([string]$row.Link) ''
        }
    }
    $psruleSeverity = @{ Critical = 'Critical'; Important = 'High'; Awareness = 'Low' }
    if ($PSRuleRead) {
        foreach ($r in @($psruleRows | Where-Object Outcome -EQ 'Fail')) {
            $row = @{ Resource = [string]$r.ResourceName; 'Resource type' = [string]$r.ResourceType; 'Resource group' = [string]$r.ResourceGroup; Subscription = [string]$r.SubscriptionName }
            $severity = if ($psruleSeverity.Contains([string]$r.Severity)) { $psruleSeverity[[string]$r.Severity] } else { 'Medium' }
            & $add $severity (& $categoryOf ([string]$r.Pillar)) 'PSRule for Azure' $(if ($r.Title) { [string]$r.Title } else { [string]$r.RuleName }) $row ((@($r.Recommendation) | Where-Object { $_ }) -join ' ') ([string]$r.Link) ([string]$r.ResourceId)
        }
    }
    $severityRank = @{ Critical = 0; High = 1; Medium = 2; Low = 3 }
    $recommendationRows = @($recommendations | Sort-Object -Property @{ Expression = { if ($severityRank.Contains($_.Severity)) { $severityRank[$_.Severity] } else { 4 } } }, Category, Recommendation, Resource)
    $sheets.Add((& $newSheet 'Recommendations' 'Resource recommendations' ([ordered]@{ 'Severity' = 'badge'; 'Category' = 'badge'; 'Source' = 'text'; 'Recommendation' = 'wide'; 'Resource' = 'resource'; 'Resource type' = 'mono'; 'Resource group' = 'text'; 'Subscription' = 'text'; 'Remediation' = 'wide'; 'Link' = 'link' }) `
                $recommendationRows @('Severity', 'Category', 'Source', 'Recommendation', 'Resource') `
                'Everything to act on, in one list: Azure Advisor, Defender for Cloud, retirements, unattached and empty resources, policy non-compliance and PSRule for Azure - most severe first.'))

    $countOf = { param($Rows, [string] $Property, [string] $Value) @($Rows | Where-Object { $_.$Property -eq $Value }).Count }
    $stats = [ordered]@{
        PolicyAssignments      = $(if ($AssignedPolicy) { @($AssignedPolicy.Assignments).Count } else { $byAssignment.Count })
        Policies               = $(if ($AssignedPolicy) { $policyRows.Count } else { $stateOf.Count })
        PoliciesFailed         = $(if ($AssignedPolicy) { & $countOf $policyRows 'Status' 'Failed' } else { @($policyStatus.Values | Where-Object { $_ -eq 'Failed' }).Count })
        PoliciesPassed         = $(if ($AssignedPolicy) { & $countOf $policyRows 'Status' 'Passed' } else { @($policyStatus.Values | Where-Object { $_ -eq 'Passed' }).Count })
        PoliciesManual         = $(if ($AssignedPolicy) { & $countOf $policyRows 'Status' 'Manual review' } else { @($policyStatus.Values | Where-Object { $_ -eq 'Manual review' }).Count })
        NonCompliantResources  = $nonCompliantResources
        PSRuleRules            = $(if ($PSRuleRead) { @($psruleRows | ForEach-Object { $_.RuleName } | Select-Object -Unique).Count } else { $null })
        PSRulePassed           = $(if ($PSRuleRead) { & $countOf $psruleRows 'Outcome' 'Pass' } else { $null })
        PSRuleFailed           = $(if ($PSRuleRead) { & $countOf $psruleRows 'Outcome' 'Fail' } else { $null })
        Recommendations        = $recommendationRows.Count
        RecommendationsUrgent  = @($recommendationRows | Where-Object { $_.Severity -in 'Critical', 'High' }).Count
    }
    @{ Sheets = $sheets.ToArray(); Stats = $stats; Notices = $notices.ToArray() }
}
