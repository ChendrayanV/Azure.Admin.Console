function ConvertTo-AACPolicyAssessment {
    <#
    .SYNOPSIS
        Assesses Azure Policy across a scope - what is assigned, how
        compliant it is by subscription, assignment, policy and category,
        the exemptions and the managed identities' roles - and what to
        improve: the model behind Invoke-AACPolicyAssessment (AzPolicyLens's
        analysis, in the spirit of github.com/Azure/AzPolicyLens).
    .DESCRIPTION
        No Azure calls: every input is Resource Graph rows
        (Get-AACPolicyAssessmentQuery). The scope:
          (nothing)            everything the account can see
          -ManagementGroupId   that management group and everything under it
          -SubscriptionId      those subscriptions (an application team's),
                               and the assignments that reach them - from
                               their management groups too
        -Audience Platform (AzPolicyLens's detailed wiki) adds the
        management group hierarchy, unassigned custom definitions and
        initiatives, metadata hygiene and hidden- metadata and tags;
        Application (its basic wiki) leaves those out.

        Compliance is counted as AzPolicyLens counts it: each resource once,
        at its worst state (NonCompliant, then Compliant, Conflict, Exempt);
        compliance = (compliant + exempt) / all. A rate below
        -ComplianceWarningPercent is Warning, below half of it Poor.

        Every assigned initiative is opened up (InitiativePolicies): each
        member policy with its effect and the effective value of its
        parameters - through the initiative's parameters and the
        assignment's (Resolve-AACPolicySetMember) - and its compliance,
        policies with no compliance data included.

        Returns a hashtable: Assignments, AssignmentCompliance (per
        assignment and subscription), Policies (per assignment and policy),
        InitiativePolicies (per initiative assignment and member policy),
        Categories, Subscriptions, ManagementGroups, Initiatives,
        Definitions, Exemptions, Roles, Findings, Tree (for the HTML
        report), Stats.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyCollection()] [object[]] $Subscription = @(),
        [AllowEmptyCollection()] [object[]] $ManagementGroup = @(),
        [AllowEmptyCollection()] [object[]] $Assignment = @(),
        [AllowEmptyCollection()] [object[]] $Exemption = @(),
        # Definition or initiative ID (lower case) -> its row: every custom one, and the built-in ones assigned.
        [hashtable] $Definition = @{},
        [AllowEmptyCollection()] [object[]] $RoleAssignment = @(),
        [AllowEmptyCollection()] [object[]] $RoleDefinition = @(),
        [AllowEmptyCollection()] [object[]] $ComplianceBySubscription = @(),
        [AllowEmptyCollection()] [object[]] $ComplianceByAssignment = @(),
        [AllowEmptyCollection()] [object[]] $ComplianceByPolicy = @(),
        [string[]] $SubscriptionId = @(),
        [string] $ManagementGroupId,
        [ValidateSet('Platform', 'Application')]
        [string] $Audience = 'Platform',
        [ValidateRange(1, 99)]
        [int] $ComplianceWarningPercent = 80,
        [ValidateRange(1, 365)]
        [int] $ExemptionWarningDays = 30,
        [datetime] $Now = (Get-Date)
    )

    # --- Helpers -----------------------------------------------------------------------------------------------------
    $at = {
        param($Item, [string] $Path)
        foreach ($part in ($Path -split '\.')) {
            if ($Item -is [System.Collections.IDictionary]) { $Item = if ($Item.Contains($part)) { $Item[$part] } else { $null } }
            elseif ($null -ne $Item -and $Item -isnot [string] -and $Item -isnot [ValueType] -and $Item -isnot [System.Collections.IEnumerable]) { $Item = Get-AACPropertyValue -InputObject $Item -Name $part }
            else { return $null }
        }
        $Item
    }
    $list = { param($Item) @(if ($Item -is [System.Collections.IEnumerable] -and $Item -isnot [string] -and $Item -isnot [System.Collections.IDictionary]) { $Item } elseif ($null -ne $Item) { , $Item }) | Where-Object { $null -ne $_ } }
    $lower = { param($Text) ([string]$Text).ToLowerInvariant() }
    $leaf = { param($Id) if ($Id) { ([string]$Id).TrimEnd('/') -replace '^.*/', '' } else { '' } }
    $isTrue = { param($Value) $null -ne $Value -and [string]$Value -in 'True', 'true' }
    $object = { param([string] $TypeName, [System.Collections.IDictionary] $Property) $item = [pscustomobject]$Property; $item.PSObject.TypeNames.Insert(0, $TypeName); $item }
    $platform = $Audience -eq 'Platform'
    $docs = 'https://learn.microsoft.com/azure/governance/policy'
    $percent = {
        param([long] $Compliant, [long] $Exempt, [long] $Total)
        if ($Total -le 0) { return $null }
        [Math]::Round(($Compliant + $Exempt) / $Total * 100, 1)
    }
    $rate = { param($Percent) if ($null -eq $Percent) { 'No data' } elseif ($Percent -ge $ComplianceWarningPercent) { 'Good' } elseif ($Percent -ge $ComplianceWarningPercent / 2) { 'Warning' } else { 'Poor' } }
    $hidden = {
        # Metadata (or tags) named hidden-* or hidden_*: for the platform team only.
        param($Bag)
        if (-not $platform -or $Bag -isnot [System.Collections.IDictionary]) { return '' }
        (@($Bag.Keys | Where-Object { $_ -match '^hidden[-_]' } | Sort-Object | ForEach-Object { "$_=$(if ($Bag[$_] -is [string] -or $Bag[$_] -is [ValueType]) { $Bag[$_] } else { ConvertTo-Json -InputObject $Bag[$_] -Compress -Depth 5 })" })) -join '; '
    }
    $findings = [System.Collections.Generic.List[object]]::new()
    $finding = {
        param([string] $Severity, [string] $Area, [string] $Title, [string] $Item, [string] $Detail, [string] $Action, [string] $Link, [string] $Scope, [string] $Id)
        $findings.Add((& $object 'AAC.PolicyFinding' ([ordered]@{ Severity = $Severity; Area = $Area; Finding = $Title; Item = $Item; Detail = $Detail; Recommendation = $Action; Link = $Link; Scope = $Scope; ResourceId = $Id })))
    }

    # --- The hierarchy, and what is in scope --------------------------------------------------------------------------
    $groupNames = @{}; $groupParent = @{}
    foreach ($row in $ManagementGroup) { $key = & $lower (& $at $row 'name'); $groupNames[$key] = [string]$(if (& $at $row 'displayName') { & $at $row 'displayName' } else { & $at $row 'name' }); $groupParent[$key] = & $lower (& $at $row 'parent') }
    $ancestorsOfGroup = {
        param([string] $Name)
        $chain = [System.Collections.Generic.List[string]]::new(); $walk = $groupParent[(& $lower $Name)]; $guard = 0
        while ($walk -and $guard -lt 20) { $chain.Add($walk); $walk = $groupParent[$walk]; $guard++ }
        , $chain.ToArray()
    }
    $subscriptionNames = @{}; $subscriptionChain = @{}
    foreach ($row in $Subscription) {
        $key = & $lower (& $at $row 'subscriptionId')
        $subscriptionNames[$key] = [string](& $at $row 'name')
        $subscriptionChain[$key] = @(@(& $list (& $at $row 'chain')) | ForEach-Object { & $lower (& $at $_ 'name') } | Where-Object { $_ })
    }
    $scopeGroup = & $lower $ManagementGroupId
    $wantedSubscriptions = @($SubscriptionId | Where-Object { $_ } | ForEach-Object { & $lower $_ })
    $inScopeSubscriptions = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($key in $subscriptionNames.Keys) {
        if ($wantedSubscriptions.Count) { if ($wantedSubscriptions -contains $key) { [void]$inScopeSubscriptions.Add($key) } }
        elseif ($scopeGroup) { if ($subscriptionChain[$key] -contains $scopeGroup) { [void]$inScopeSubscriptions.Add($key) } }
        else { [void]$inScopeSubscriptions.Add($key) }
    }
    $inScopeGroups = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($key in $groupNames.Keys) {
        if ($wantedSubscriptions.Count) { foreach ($sub in $inScopeSubscriptions) { if ($subscriptionChain[$sub] -contains $key) { [void]$inScopeGroups.Add($key) } } }
        elseif ($scopeGroup) { if ($key -eq $scopeGroup -or (& $ancestorsOfGroup $key) -contains $scopeGroup) { [void]$inScopeGroups.Add($key) } }
        else { [void]$inScopeGroups.Add($key) }
    }
    # Where a scope ID sits: a management group, a subscription (and below).
    $scopeOf = {
        param([string] $ScopeId)
        if ($ScopeId -match '(?i)/providers/Microsoft\.Management/managementGroups/([^/]+)') { return @{ Type = 'Management group'; Group = $Matches[1].ToLowerInvariant(); Subscription = ''; Name = $(if ($groupNames.Contains($Matches[1].ToLowerInvariant())) { $groupNames[$Matches[1].ToLowerInvariant()] } else { $Matches[1] }) } }
        if ($ScopeId -match '(?i)^/subscriptions/([^/]+)(/resourceGroups/([^/]+))?') {
            $sub = $Matches[1].ToLowerInvariant(); $name = if ($subscriptionNames.Contains($sub)) { $subscriptionNames[$sub] } else { $sub }
            return @{ Type = $(if ($Matches[3]) { 'Resource group' } else { 'Subscription' }); Group = ''; Subscription = $sub; Name = $(if ($Matches[3]) { "$name / $($Matches[3])" } else { $name }) }
        }
        @{ Type = 'Tenant'; Group = ''; Subscription = ''; Name = $ScopeId }
    }
    # The subscriptions an assignment applies to (its excluded scopes taken off).
    $reach = {
        param($Row)
        $where = & $scopeOf ([string](& $at $Row 'scope'))
        $excluded = @(@(& $list (& $at $Row 'notScopes')) | ForEach-Object { & $scopeOf ([string]$_) })
        @(foreach ($sub in $subscriptionNames.Keys) {
                $applies = if ($where.Group) { $subscriptionChain[$sub] -contains $where.Group } else { $where.Subscription -eq $sub }
                if (-not $applies) { continue }
                if (@($excluded | Where-Object { ($_.Type -eq 'Subscription' -and $_.Subscription -eq $sub) -or ($_.Group -and $subscriptionChain[$sub] -contains $_.Group) }).Count) { continue }
                $sub
            })
    }

    # --- Definitions, and what each assignment assigns ------------------------------------------------------------------
    $definitionOf = { param($Id) $key = & $lower $Id; if ($key -and $Definition.Contains($key)) { $Definition[$key] } else { $null } }
    $isSet = { param($Id) [string]$Id -match '(?i)/policySetDefinitions/' }
    $deprecated = { param($Row) (& $isTrue (& $at $Row 'metadata.deprecated')) -or [string](& $at $Row 'displayName') -match '^\s*\[Deprecated\]' }
    $preview = { param($Row) (& $isTrue (& $at $Row 'metadata.preview')) -or [string](& $at $Row 'displayName') -match '^\s*\[Preview\]' }
    $nameOf = { param($Id) $row = & $definitionOf $Id; if ($row -and (& $at $row 'displayName')) { [string](& $at $row 'displayName') } else { & $leaf $Id } }
    $effectOf = {
        # A definition's effect: the literal, or its effect parameter's value - the assignment's, else the default.
        param($Row, $Parameters)
        $effect = [string](& $at $Row 'rule.then.effect')
        if ($effect -match "^\[parameters\('([^']+)'\)\]$") {
            $name = $Matches[1]
            $value = & $at $Parameters "$name.value"
            if ($null -eq $value) { $value = & $at $Row "parameters.$name.defaultValue" }
            $effect = [string]$value
        }
        $effect
    }
    $rolesOf = { param($Row) @(@(& $list (& $at $Row 'rule.then.details.roleDefinitionIds')) | ForEach-Object { & $leaf $_ } | ForEach-Object { $_.ToLowerInvariant() }) }
    $roleNames = @{}
    foreach ($row in $RoleDefinition) { $roleNames[(& $lower (& $at $row 'name'))] = [string](& $at $row 'roleName') }
    $assignedDefinitions = [System.Collections.Generic.HashSet[string]]::new()
    $memberCount = @{}

    # --- Assignments in scope -----------------------------------------------------------------------------------------
    $inScope = @(foreach ($row in $Assignment) {
            $where = & $scopeOf ([string](& $at $row 'scope'))
            $subs = @(& $reach $row)
            $keep = if ($wantedSubscriptions.Count) { @($subs | Where-Object { $inScopeSubscriptions.Contains($_) }).Count -gt 0 }
            elseif ($scopeGroup) { ($where.Group -and $inScopeGroups.Contains($where.Group)) -or ($where.Subscription -and $inScopeSubscriptions.Contains($where.Subscription)) }
            else { $true }
            if ($keep) { @{ Row = $row; Where = $where; Subscriptions = @($subs | Where-Object { $inScopeSubscriptions.Contains($_) }) } }
        })
    $assignmentIds = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($entry in $inScope) { [void]$assignmentIds.Add((& $lower (& $at $entry.Row 'id'))) }
    $compliance = @{}
    foreach ($row in $ComplianceByAssignment) {
        $sub = & $lower (& $at $row 'subscriptionId')
        if (-not $inScopeSubscriptions.Contains($sub)) { continue }
        $key = & $lower (& $at $row 'assignmentId')
        if (-not $compliance.Contains($key)) { $compliance[$key] = @{ NonCompliant = 0L; Compliant = 0L; Conflict = 0L; Exempt = 0L } }
        foreach ($state in 'NonCompliant', 'Compliant', 'Conflict', 'Exempt') { $compliance[$key][$state] += [long](& $at $row ($state.Substring(0, 1).ToLowerInvariant() + $state.Substring(1))) }
    }
    $exemptionsOf = @{}
    foreach ($row in $Exemption) { $key = & $lower (& $at $row 'assignmentId'); $exemptionsOf[$key] = 1 + $(if ($exemptionsOf.Contains($key)) { $exemptionsOf[$key] } else { 0 }) }
    $principalRoles = @{}
    foreach ($row in $RoleAssignment) {
        $principal = & $lower (& $at $row 'principalId')
        if (-not $principalRoles.Contains($principal)) { $principalRoles[$principal] = [System.Collections.Generic.List[object]]::new() }
        $principalRoles[$principal].Add($row)
    }
    $principalOf = {
        param($Row)
        $identity = & $at $Row 'identity'
        $type = [string](& $at $identity 'type')
        if ($type -match 'SystemAssigned') { return @{ Type = 'System-assigned'; Principals = @(& $lower (& $at $identity 'principalId')) } }
        if ($type -match 'UserAssigned') { $users = & $at $identity 'userAssignedIdentities'; return @{ Type = 'User-assigned'; Principals = @(if ($users -is [System.Collections.IDictionary]) { foreach ($k in $users.Keys) { & $lower (& $at $users[$k] 'principalId') } }) } }
        @{ Type = ''; Principals = @() }
    }

    $assignmentRows = [System.Collections.Generic.List[object]]::new()
    $roleRows = [System.Collections.Generic.List[object]]::new()
    $memberEntries = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $inScope) {
        $row = $entry.Row
        $id = [string](& $at $row 'id'); $key = & $lower $id
        $definitionId = [string](& $at $row 'definitionId')
        $target = & $definitionOf $definitionId
        $set = & $isSet $definitionId
        [void]$assignedDefinitions.Add((& $lower $definitionId))
        $members = @(if ($set) { & $list (& $at $target 'members') })
        foreach ($member in $members) { [void]$assignedDefinitions.Add((& $lower (& $at $member 'policyDefinitionId'))) }
        if ($set -and $members.Count) {
            $memberEntries.Add(@{ Row = $row; Where = $entry.Where; Set = $target; Resolved = @(Resolve-AACPolicySetMember -Member $members -SetParameter (& $at $target 'parameters') -Assigned (& $at $row 'parameters') -Override @(& $list (& $at $row 'overrides')) -Definition $Definition) })
        }
        $memberCount[(& $lower $definitionId)] = 1 + $(if ($memberCount.Contains((& $lower $definitionId))) { $memberCount[(& $lower $definitionId)] } else { 0 })
        $parameters = & $at $row 'parameters'
        $counts = if ($compliance.Contains($key)) { $compliance[$key] } else { @{ NonCompliant = 0L; Compliant = 0L; Conflict = 0L; Exempt = 0L } }
        $total = $counts.NonCompliant + $counts.Compliant + $counts.Conflict + $counts.Exempt
        $pct = & $percent $counts.Compliant $counts.Exempt $total
        $identity = & $principalOf $row
        # The roles the assignment's policies need to remediate (DeployIfNotExists, Modify).
        $needed = @(@(if ($set) { foreach ($member in $members) { & $rolesOf (& $definitionOf (& $at $member 'policyDefinitionId')) } } else { & $rolesOf $target }) | Sort-Object -Unique)
        $held = @(foreach ($principal in $identity.Principals) { if ($principalRoles.Contains($principal)) { $principalRoles[$principal] } })
        foreach ($role in $held) {
            $roleRows.Add((& $object 'AAC.PolicyRoleAssignment' ([ordered]@{
                            Assignment = [string]$(if (& $at $row 'displayName') { & $at $row 'displayName' } else { & $at $row 'name' }); Identity = $identity.Type; PrincipalId = [string](& $at $role 'principalId')
                            Role = $(if ($roleNames.Contains((& $leaf (& $at $role 'roleDefinitionId')))) { $roleNames[(& $leaf (& $at $role 'roleDefinitionId'))] } else { & $leaf (& $at $role 'roleDefinitionId') })
                            Scope = (& $scopeOf ([string](& $at $role 'scope'))).Name; ScopeId = [string](& $at $role 'scope'); Required = $(if ($needed -contains (& $leaf (& $at $role 'roleDefinitionId'))) { 'Yes' } else { 'No' }); AssignmentId = $id
                        })))
        }
        $heldRoles = @($held | ForEach-Object { & $leaf (& $at $_ 'roleDefinitionId') } | ForEach-Object { $_.ToLowerInvariant() })
        $missingRoles = @($needed | Where-Object { $heldRoles -notcontains $_ })
        $display = [string]$(if (& $at $row 'displayName') { & $at $row 'displayName' } else { & $at $row 'name' })
        $effect = if ($set) { [string](& $at $parameters 'effect.value') } else { & $effectOf $target $parameters }
        $assignmentRows.Add((& $object 'AAC.PolicyAssignmentReport' ([ordered]@{
                        Assignment = $display; Name = [string](& $at $row 'name'); Scope = $entry.Where.Name; ScopeType = $entry.Where.Type
                        Definition = & $nameOf $definitionId; Kind = $(if ($set) { 'Initiative' } else { 'Policy' }); PolicyType = [string](& $at $target 'policyType')
                        Policies = $(if ($set) { $members.Count } else { 1 }); Category = [string](& $at $target 'metadata.category')
                        Enforcement = $(if (& $at $row 'enforcement') { [string](& $at $row 'enforcement') } else { 'Default' }); Effect = $effect
                        Parameters = $(if ($parameters -is [System.Collections.IDictionary]) { $parameters.Count } else { 0 })
                        ExcludedScopes = @(& $list (& $at $row 'notScopes')).Count; Overrides = @(& $list (& $at $row 'overrides')).Count; ResourceSelectors = @(& $list (& $at $row 'resourceSelectors')).Count
                        NonComplianceMessage = $(if (@(& $list (& $at $row 'messages')).Count) { 'Yes' } else { 'No' })
                        Identity = $identity.Type; RolesNeeded = (@($needed | ForEach-Object { if ($roleNames.Contains($_)) { $roleNames[$_] } else { $_ } }) -join ', ')
                        RolesMissing = (@($missingRoles | ForEach-Object { if ($roleNames.Contains($_)) { $roleNames[$_] } else { $_ } }) -join ', ')
                        Exemptions = $(if ($exemptionsOf.Contains($key)) { $exemptionsOf[$key] } else { 0 }); Subscriptions = $entry.Subscriptions.Count
                        NonCompliant = $counts.NonCompliant; Compliant = $counts.Compliant; Conflict = $counts.Conflict; Exempt = $counts.Exempt; Resources = $total
                        CompliancePercent = $pct; Rating = & $rate $pct
                        AssignedBy = [string](& $at $row 'metadata.assignedBy'); DefinitionVersion = [string](& $at $row 'definitionVersion'); Description = [string](& $at $row 'description')
                        HiddenMetadata = & $hidden (& $at $row 'metadata'); ResourceId = $id; DefinitionId = $definitionId
                    })))

        # --- Assignment findings ---------------------------------------------------------------------------------------
        $scopeText = $entry.Where.Name
        if (-not $target) { & $finding 'Medium' 'Assignment' 'Definition not found' $display "The assignment's $(if ($set) { 'initiative' } else { 'definition' }) ($definitionId) couldn't be read: deleted, or defined at a scope you can't see." 'Delete the assignment if its definition is gone, or check access to the definition''s scope.' "$docs/concepts/assignment-structure" $scopeText $id }
        if (-not $set -and $target) { & $finding 'Low' 'Assignment' 'Policy definition assigned directly' $display "'$(& $nameOf $definitionId)' is assigned on its own, not through an initiative." 'Group related policies into initiatives and assign those: fewer assignments, one set of parameters, and controls you can map.' "$docs/concepts/initiative-definition-structure" $scopeText $id }
        if ([string](& $at $row 'enforcement') -eq 'DoNotEnforce') { & $finding 'Medium' 'Assignment' 'Not enforced (DoNotEnforce)' $display 'The assignment is evaluated but not enforced: Deny doesn''t block, and DeployIfNotExists and Modify don''t act on new resources.' 'Set enforcement to Default once the impact is understood, or document why it stays audit-only.' "$docs/concepts/assignment-structure#enforcement-mode" $scopeText $id }
        if ($needed.Count -and -not $identity.Principals.Count) { & $finding 'High' 'Identity' 'Remediation without a managed identity' $display "Its policies deploy or modify resources (they need $(@($needed | ForEach-Object { if ($roleNames.Contains($_)) { $roleNames[$_] } else { $_ } }) -join ', ')), but the assignment has no managed identity: nothing can be remediated." 'Give the assignment a system- or user-assigned managed identity with the roles its policies list.' "$docs/how-to/remediate-resources" $scopeText $id }
        elseif ($missingRoles.Count) { & $finding 'High' 'Identity' 'Managed identity missing roles' $display "The assignment's identity lacks $(@($missingRoles | ForEach-Object { if ($roleNames.Contains($_)) { $roleNames[$_] } else { $_ } }) -join ', '), which its policies need to remediate." 'Grant the identity those roles at the assignment''s scope (the portal does it when the assignment is created there).' "$docs/how-to/remediate-resources#configure-the-managed-identity" $scopeText $id }
        if ($null -ne $pct -and $pct -lt $ComplianceWarningPercent) { & $finding $(if ($pct -lt $ComplianceWarningPercent / 2) { 'High' } else { 'Medium' }) 'Compliance' 'Assignment below the compliance threshold' $display "$pct% compliant ($($counts.NonCompliant) non-compliant of $total resources), under $ComplianceWarningPercent%." 'Remediate the non-compliant resources (or exempt them on purpose), starting with the policies with the most non-compliant resources.' "$docs/how-to/get-compliance-data" $scopeText $id }
        if ($target) {
            $assignedDeprecated = @(@($target) + @($members | ForEach-Object { & $definitionOf (& $at $_ 'policyDefinitionId') }) | Where-Object { $_ -and (& $deprecated $_) })
            foreach ($item in $assignedDeprecated) { & $finding 'Medium' $(if (& $isSet (& $at $item 'id')) { 'Initiative' } else { 'Definition' }) 'Deprecated policy assigned' $display "'$(& $at $item 'displayName')' is deprecated and may stop being supported." 'Replace it with its up-to-date replacement, or plan to remove it.' "$docs/concepts/definition-structure-basics#common-metadata-properties" $scopeText $id }
            if (& $preview $target) { & $finding 'Low' $(if ($set) { 'Initiative' } else { 'Definition' }) 'Preview policy assigned' $display "'$(& $at $target 'displayName')' is in preview: it can change." 'Use preview policies with audit effects only, and review them when they reach general availability.' "$docs/concepts/definition-structure-basics#common-metadata-properties" $scopeText $id }
        }
        foreach ($notScope in @(& $list (& $at $row 'notScopes'))) {
            $excluded = & $scopeOf ([string]$notScope)
            $exists = if ($excluded.Group) { $groupNames.Contains($excluded.Group) } elseif ($excluded.Type -eq 'Subscription') { $subscriptionNames.Contains($excluded.Subscription) } else { $true }
            if (-not $exists) { & $finding 'Low' 'Assignment' 'Excluded scope that doesn''t exist' $display "It excludes $notScope, which can't be found." 'Remove the excluded scope (or check it is only out of your sight).' "$docs/concepts/assignment-structure#excluded-scopes" $scopeText $id }
        }
        if ([string](& $at $row 'enforcement') -ne 'DoNotEnforce' -and $effect -eq 'deny' -and -not @(& $list (& $at $row 'messages')).Count) { & $finding 'Low' 'Assignment' 'Deny without a non-compliance message' $display 'People who are blocked see only the policy''s name.' 'Add a non-compliance message that says why, and who to ask.' "$docs/concepts/assignment-structure#non-compliance-messages" $scopeText $id }
    }
    # The same definition assigned twice on one scope path.
    $scopeById = @{}
    foreach ($entry in $inScope) { $scopeById[(& $lower (& $at $entry.Row 'id'))] = [string](& $at $entry.Row 'scope') }
    foreach ($group in $assignmentRows | Group-Object { & $lower $_.DefinitionId } | Where-Object Count -GT 1) {
        $rows = @($group.Group)
        for ($i = 0; $i -lt $rows.Count; $i++) {
            for ($j = $i + 1; $j -lt $rows.Count; $j++) {
                $a = & $scopeOf $scopeById[(& $lower $rows[$i].ResourceId)]; $b = & $scopeOf $scopeById[(& $lower $rows[$j].ResourceId)]
                $nested = ($a.Group -and $b.Group -and ($a.Group -eq $b.Group -or (& $ancestorsOfGroup $a.Group) -contains $b.Group -or (& $ancestorsOfGroup $b.Group) -contains $a.Group)) -or
                ($a.Group -and $b.Subscription -and $subscriptionChain[$b.Subscription] -contains $a.Group) -or ($b.Group -and $a.Subscription -and $subscriptionChain[$a.Subscription] -contains $b.Group) -or
                ($a.Subscription -and $a.Subscription -eq $b.Subscription)
                if ($nested) { & $finding 'Low' 'Assignment' 'Assigned twice on the same scope path' "$($rows[$i].Assignment) / $($rows[$j].Assignment)" "'$($rows[$i].Definition)' is assigned at $($rows[$i].Scope) and at $($rows[$j].Scope): resources under both are evaluated twice." 'Keep one assignment (at the higher scope), with exclusions or overrides where the lower one differs.' "$docs/concepts/assignment-structure" $rows[$i].Scope $rows[$i].ResourceId }
            }
        }
    }

    # --- Compliance by subscription, assignment and policy ------------------------------------------------------------------
    $subscriptionRows = @(foreach ($sub in $inScopeSubscriptions) {
            $row = (@($ComplianceBySubscription | Where-Object { (& $lower (& $at $_ 'subscriptionId')) -eq $sub }) | Select-Object -First 1)
            $c = [long](& $at $row 'compliant'); $e = [long](& $at $row 'exempt'); $n = [long](& $at $row 'nonCompliant'); $x = [long](& $at $row 'conflict')
            $pct = & $percent $c $e ($c + $e + $n + $x)
            $tags = & $at ((@($Subscription | Where-Object { (& $lower (& $at $_ 'subscriptionId')) -eq $sub }) | Select-Object -First 1)) 'tags'
            $chain = @($subscriptionChain[$sub])
            [array]::Reverse($chain)
            & $object 'AAC.PolicySubscription' ([ordered]@{
                    Subscription = $subscriptionNames[$sub]; SubscriptionId = $sub; ManagementGroups = (@($chain | ForEach-Object { if ($groupNames.Contains($_)) { $groupNames[$_] } else { $_ } }) -join ' > ')
                    Assignments = @($inScope | Where-Object { $_.Subscriptions -contains $sub }).Count
                    Exemptions = @($Exemption | Where-Object { (& $lower (& $at $_ 'subscriptionId')) -eq $sub -or ([string](& $at $_ 'id')) -match "(?i)^/subscriptions/$sub/" }).Count
                    NonCompliant = $n; Compliant = $c; Conflict = $x; Exempt = $e; Resources = $c + $e + $n + $x; CompliancePercent = $pct; Rating = & $rate $pct
                    HiddenTags = & $hidden $tags; ResourceId = "/subscriptions/$sub"
                })
            if ($null -ne $pct -and $pct -lt $ComplianceWarningPercent) { & $finding 'Medium' 'Compliance' 'Subscription below the compliance threshold' $subscriptionNames[$sub] "$pct% of its resources are compliant ($n non-compliant), under $ComplianceWarningPercent%." 'Work through its non-compliant assignments and policies (the Policies table, by subscription).' "$docs/how-to/get-compliance-data" $subscriptionNames[$sub] "/subscriptions/$sub" }
        }) | Sort-Object -Property @{ Expression = { if ($null -eq $_.CompliancePercent) { 101 } else { $_.CompliancePercent } } }, Subscription
    $assignmentCompliance = @(foreach ($row in $ComplianceByAssignment) {
            $key = & $lower (& $at $row 'assignmentId'); $sub = & $lower (& $at $row 'subscriptionId')
            if (-not $assignmentIds.Contains($key) -or -not $inScopeSubscriptions.Contains($sub)) { continue }
            $report = (@($assignmentRows | Where-Object { (& $lower $_.ResourceId) -eq $key }) | Select-Object -First 1)
            $c = [long](& $at $row 'compliant'); $e = [long](& $at $row 'exempt'); $n = [long](& $at $row 'nonCompliant'); $x = [long](& $at $row 'conflict')
            $pct = & $percent $c $e ($c + $e + $n + $x)
            & $object 'AAC.PolicyAssignmentCompliance' ([ordered]@{ Assignment = $report.Assignment; Subscription = $subscriptionNames[$sub]; NonCompliant = $n; Compliant = $c; Conflict = $x; Exempt = $e; Resources = $c + $e + $n + $x; CompliancePercent = $pct; Rating = & $rate $pct; AssignmentId = $report.ResourceId })
        }) | Sort-Object -Property @{ Expression = 'NonCompliant'; Descending = $true }
    $policyGroups = @{}
    foreach ($row in $ComplianceByPolicy) {
        $key = & $lower (& $at $row 'assignmentId'); $sub = & $lower (& $at $row 'subscriptionId')
        if (-not $assignmentIds.Contains($key) -or -not $inScopeSubscriptions.Contains($sub)) { continue }
        $groupKey = "$key|$(& $at $row 'referenceId')|$(& $lower (& $at $row 'definitionId'))"
        if (-not $policyGroups.Contains($groupKey)) { $policyGroups[$groupKey] = @{ Row = $row; NonCompliant = 0L; Compliant = 0L; Conflict = 0L; Exempt = 0L; Subscriptions = [System.Collections.Generic.HashSet[string]]::new() } }
        foreach ($state in 'NonCompliant', 'Compliant', 'Conflict', 'Exempt') { $policyGroups[$groupKey][$state] += [long](& $at $row ($state.Substring(0, 1).ToLowerInvariant() + $state.Substring(1))) }
        [void]$policyGroups[$groupKey].Subscriptions.Add($sub)
    }
    $policyRows = @(foreach ($groupKey in $policyGroups.Keys) {
            $entry = $policyGroups[$groupKey]; $row = $entry.Row
            $report = (@($assignmentRows | Where-Object { (& $lower $_.ResourceId) -eq (& $lower (& $at $row 'assignmentId')) }) | Select-Object -First 1)
            $policyDefinition = & $definitionOf (& $at $row 'definitionId')
            $member = (@(if ($report.Kind -eq 'Initiative') { @(& $list (& $at (& $definitionOf $report.DefinitionId) 'members')) | Where-Object { [string](& $at $_ 'policyDefinitionReferenceId') -eq [string](& $at $row 'referenceId') } }) | Select-Object -First 1)
            $total = $entry.NonCompliant + $entry.Compliant + $entry.Conflict + $entry.Exempt
            $pct = & $percent $entry.Compliant $entry.Exempt $total
            & $object 'AAC.PolicyAssessmentPolicy' ([ordered]@{
                    Assignment = $report.Assignment; Policy = & $nameOf (& $at $row 'definitionId'); ReferenceId = [string](& $at $row 'referenceId'); Effect = [string](& $at $row 'effect')
                    Category = [string](& $at $policyDefinition 'metadata.category'); Groups = (@(& $list (& $at $member 'groupNames')) -join ', ')
                    NonCompliant = $entry.NonCompliant; Compliant = $entry.Compliant; Conflict = $entry.Conflict; Exempt = $entry.Exempt; Resources = $total
                    CompliancePercent = $pct; Rating = & $rate $pct; Subscriptions = $entry.Subscriptions.Count; PolicyType = [string](& $at $policyDefinition 'policyType')
                    AssignmentId = $report.ResourceId; DefinitionId = [string](& $at $row 'definitionId')
                })
        }) | Sort-Object -Property @{ Expression = 'NonCompliant'; Descending = $true }, Assignment, Policy
    $categoryRows = @(foreach ($group in $policyRows | Group-Object { if ($_.Category) { $_.Category } else { '(no category)' } }) {
            $n = [long](($group.Group | Measure-Object NonCompliant -Sum).Sum); $c = [long](($group.Group | Measure-Object Compliant -Sum).Sum); $e = [long](($group.Group | Measure-Object Exempt -Sum).Sum); $x = [long](($group.Group | Measure-Object Conflict -Sum).Sum)
            $pct = & $percent $c $e ($n + $c + $e + $x)
            & $object 'AAC.PolicyCategory' ([ordered]@{ Category = $group.Name; Policies = @($group.Group | ForEach-Object DefinitionId | Sort-Object -Unique).Count; Assignments = @($group.Group | ForEach-Object AssignmentId | Sort-Object -Unique).Count; NonCompliant = $n; Compliant = $c; Conflict = $x; Exempt = $e; CompliancePercent = $pct; Rating = & $rate $pct })
        }) | Sort-Object -Property @{ Expression = { if ($null -eq $_.CompliancePercent) { 101 } else { $_.CompliancePercent } } }, Category

    # --- The policies inside the assigned initiatives: effect, parameter values, compliance ---------------------------------
    $memberRows = @(foreach ($item in $memberEntries) {
            $row = $item.Row
            $assignmentKey = & $lower (& $at $row 'id')
            $display = [string]$(if (& $at $row 'displayName') { & $at $row 'displayName' } else { & $at $row 'name' })
            foreach ($member in $item.Resolved) {
                $groupKey = "$assignmentKey|$($member.ReferenceId)|$(& $lower $member.DefinitionId)"
                $counts = if ($policyGroups.Contains($groupKey)) { $policyGroups[$groupKey] } else { @{ NonCompliant = 0L; Compliant = 0L; Conflict = 0L; Exempt = 0L } }
                $total = $counts.NonCompliant + $counts.Compliant + $counts.Conflict + $counts.Exempt
                $pct = & $percent $counts.Compliant $counts.Exempt $total
                $values = @($member.Parameters | Where-Object Name -NE 'effect' | ForEach-Object { "$($_.Name) = $(Format-AACPolicyValue -Value $_.Value)$(if ($_.Source -ne 'Assigned') { " ($($_.Source.ToLowerInvariant()))" })" })
                & $object 'AAC.PolicyInitiativeMember' ([ordered]@{
                        Assignment = $display; Scope = $item.Where.Name; Initiative = [string](& $at $item.Set 'displayName'); ReferenceId = $member.ReferenceId
                        Policy = & $nameOf $member.DefinitionId; PolicyType = [string](& $at $member.Definition 'policyType'); Category = [string](& $at $member.Definition 'metadata.category')
                        Effect = $member.Effect; EffectSource = $(if ($member.Effect) { $member.EffectSource } else { '' }); Groups = @($member.Groups) -join ', '
                        Parameters = $values -join '; '; ParametersAssigned = @($member.Parameters | Where-Object Source -EQ 'Assigned').Count
                        NonCompliant = $counts.NonCompliant; Compliant = $counts.Compliant; Conflict = $counts.Conflict; Exempt = $counts.Exempt; Resources = $total
                        CompliancePercent = $pct; Rating = & $rate $pct
                        Deprecated = $(if ($member.Definition -and (& $deprecated $member.Definition)) { 'Yes' } else { 'No' })
                        AssignmentId = [string](& $at $row 'id'); InitiativeId = [string](& $at $item.Set 'id'); DefinitionId = $member.DefinitionId
                    })
            }
        }) | Sort-Object -Property Assignment, @{ Expression = 'NonCompliant'; Descending = $true }, Policy

    # --- Exemptions -----------------------------------------------------------------------------------------------------
    $allAssignmentIds = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($row in $Assignment) { [void]$allAssignmentIds.Add((& $lower (& $at $row 'id'))) }
    $exemptionRows = @(foreach ($row in $Exemption) {
            $id = [string](& $at $row 'id')
            $scopeId = $id -replace '(?i)/providers/Microsoft\.Authorization/policyExemptions/.*$', ''
            $where = & $scopeOf $scopeId
            $assignmentKey = & $lower (& $at $row 'assignmentId')
            $inScopeExemption = if ($wantedSubscriptions.Count -or $scopeGroup) { $assignmentIds.Contains($assignmentKey) -and (($where.Subscription -and $inScopeSubscriptions.Contains($where.Subscription)) -or ($where.Group -and $inScopeGroups.Contains($where.Group))) } else { $true }
            if (-not $inScopeExemption) { continue }
            $expires = [string](& $at $row 'expiresOn')
            $date = [datetime]::MinValue
            $expiry = if ($expires -and [datetime]::TryParse($expires, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$date)) { $date } else { $null }
            $days = if ($expiry) { [int][Math]::Floor(($expiry - $Now.ToUniversalTime()).TotalDays) } else { $null }
            $status = if (-not $expiry) { 'No expiry' } elseif ($days -lt 0) { 'Expired' } elseif ($days -le $ExemptionWarningDays) { 'Expiring' } else { 'Active' }
            $display = [string]$(if (& $at $row 'displayName') { & $at $row 'displayName' } else { & $at $row 'name' })
            $assignmentName = (@($Assignment | Where-Object { (& $lower (& $at $_ 'id')) -eq $assignmentKey } | ForEach-Object { [string]$(if (& $at $_ 'displayName') { & $at $_ 'displayName' } else { & $at $_ 'name' }) }) | Select-Object -First 1)
            & $object 'AAC.PolicyExemptionReport' ([ordered]@{
                    Exemption = $display; Assignment = $(if ($assignmentName) { $assignmentName } else { & $leaf $assignmentKey }); Category = [string](& $at $row 'category'); Scope = $where.Name; ScopeType = $where.Type
                    Policies = $(if (@(& $list (& $at $row 'referenceIds')).Count) { (@(& $list (& $at $row 'referenceIds')) -join ', ') } else { 'All' }); ExpiresOn = $(if ($expiry) { $expiry.ToString('yyyy-MM-dd') } else { '' }); DaysLeft = $days; Status = $status
                    Description = [string](& $at $row 'description'); HiddenMetadata = & $hidden (& $at $row 'metadata'); ResourceId = $id
                })
            switch ($status) {
                'Expired' { & $finding 'Medium' 'Exemption' 'Exemption expired' $display "Expired $(-$days) day(s) ago ($($expiry.ToString('yyyy-MM-dd'))): the resources are evaluated again, so they may show as non-compliant." 'Remove the exemption, or renew it with a new expiry if it is still needed.' "$docs/concepts/exemption-structure#expiration" $where.Name $id }
                'Expiring' { & $finding 'Low' 'Exemption' 'Exemption expiring soon' $display "Expires in $days day(s) ($($expiry.ToString('yyyy-MM-dd')))." 'Fix the resources before then, or agree a renewal with the owner.' "$docs/concepts/exemption-structure#expiration" $where.Name $id }
                'No expiry' { & $finding 'Low' 'Exemption' 'Exemption with no expiry' $display "A$(if ([string](& $at $row 'category') -eq 'Waiver') { ' waiver' } else { 'n exemption' }) that never expires is easily forgotten." 'Give every exemption an expiry date, and review it then.' "$docs/concepts/exemption-structure#expiration" $where.Name $id }
            }
            if (-not $allAssignmentIds.Contains($assignmentKey)) { & $finding 'Low' 'Exemption' 'Exemption for an assignment that doesn''t exist' $display "Its assignment ($assignmentKey) is gone." 'Delete the exemption.' "$docs/concepts/exemption-structure" $where.Name $id }
        }) | Sort-Object -Property @{ Expression = { @{ Expired = 0; Expiring = 1; 'No expiry' = 2; Active = 3 }[$_.Status] } }, ExpiresOn

    # --- Initiatives and definitions -----------------------------------------------------------------------------------
    $definitionScope = { param([string] $Id) if ($Id -match '(?i)^/providers/Microsoft\.Authorization/') { 'Built-in' } else { (& $scopeOf ($Id -replace '(?i)/providers/Microsoft\.Authorization/policy(Set)?Definitions/.*$', '')).Name } }
    $definedInScope = {
        param([string] $Id)
        if ($Id -match '(?i)^/providers/Microsoft\.Authorization/') { return $false }
        $where = & $scopeOf ($Id -replace '(?i)/providers/Microsoft\.Authorization/policy(Set)?Definitions/.*$', '')
        if (-not ($wantedSubscriptions.Count -or $scopeGroup)) { return $true }
        ($where.Group -and $inScopeGroups.Contains($where.Group)) -or ($where.Subscription -and $inScopeSubscriptions.Contains($where.Subscription))
    }
    $usedByInitiative = @{}
    foreach ($key in $Definition.Keys) {
        if (-not (& $isSet $key)) { continue }
        foreach ($member in @(& $list (& $at $Definition[$key] 'members'))) { $m = & $lower (& $at $member 'policyDefinitionId'); $usedByInitiative[$m] = 1 + $(if ($usedByInitiative.Contains($m)) { $usedByInitiative[$m] } else { 0 }) }
    }
    $initiativeRows = [System.Collections.Generic.List[object]]::new()
    $definitionRows = [System.Collections.Generic.List[object]]::new()
    $groupMetadata = @{}
    foreach ($key in $Definition.Keys) {
        $row = $Definition[$key]
        $id = [string](& $at $row 'id')
        $assigned = $assignedDefinitions.Contains($key)
        $custom = [string](& $at $row 'policyType') -eq 'Custom'
        if (-not $assigned -and -not ($custom -and $platform -and (& $definedInScope $id))) { continue }
        $display = [string](& $at $row 'displayName')
        if (& $isSet $key) {
            $members = @(& $list (& $at $row 'members'))
            $groups = @(& $list (& $at $row 'groups'))
            $usedGroups = @($members | ForEach-Object { @(& $list (& $at $_ 'groupNames')) } | Sort-Object -Unique)
            $unused = @($groups | Where-Object { $usedGroups -notcontains [string](& $at $_ 'name') } | ForEach-Object { [string](& $at $_ 'name') })
            $initiativeRows.Add((& $object 'AAC.PolicyInitiative' ([ordered]@{
                            Initiative = $display; PolicyType = [string](& $at $row 'policyType'); Category = [string](& $at $row 'metadata.category'); Version = [string]$(if (& $at $row 'version') { & $at $row 'version' } else { & $at $row 'metadata.version' })
                            Policies = $members.Count; Groups = $groups.Count; Assignments = $(if ($memberCount.Contains($key)) { $memberCount[$key] } else { 0 }); Assigned = $(if ($assigned) { 'Yes' } else { 'No' })
                            Deprecated = $(if (& $deprecated $row) { 'Yes' } else { 'No' }); Preview = $(if (& $preview $row) { 'Yes' } else { 'No' }); DefinedAt = & $definitionScope $id
                            Description = [string](& $at $row 'description'); HiddenMetadata = & $hidden (& $at $row 'metadata'); ResourceId = $id
                        })))
            if ($custom -and $platform) {
                if (-not $assigned) { & $finding 'Low' 'Initiative' 'Unassigned custom initiative' $display 'Not assigned anywhere in scope: perhaps a test, or no longer needed.' 'Assign it, or delete it if it isn''t needed.' "$docs/concepts/initiative-definition-structure" (& $definitionScope $id) $id }
                if ($unused.Count) { & $finding 'Low' 'Initiative' 'Unused policy definition groups' $display "Groups no policy uses: $($unused -join ', ')." 'Remove them from the initiative, or map its policies to them.' "$docs/concepts/initiative-definition-structure#policy-definition-groups" (& $definitionScope $id) $id }
                if (-not (& $at $row 'metadata.category')) { & $finding 'Info' 'Initiative' 'No category in the metadata' $display 'Without metadata.category, compliance can''t be read by category.' 'Set metadata.category (Azure''s common metadata properties).' "$docs/concepts/definition-structure-basics#common-metadata-properties" (& $definitionScope $id) $id }
                foreach ($group in $groups) {
                    $metadataId = & $lower (& $at $group 'additionalMetadataId')
                    if (-not $metadataId) { continue }
                    if (-not $groupMetadata.Contains($metadataId)) { $groupMetadata[$metadataId] = [System.Collections.Generic.List[object]]::new() }
                    $groupMetadata[$metadataId].Add(@{ Name = [string](& $at $group 'name'); Initiative = $display; Id = $id })
                }
            }
        }
        else {
            $effect = & $effectOf $row $null
            $definitionRows.Add((& $object 'AAC.PolicyDefinitionReport' ([ordered]@{
                            Definition = $display; PolicyType = [string](& $at $row 'policyType'); Mode = [string](& $at $row 'mode'); Category = [string](& $at $row 'metadata.category')
                            Version = [string]$(if (& $at $row 'version') { & $at $row 'version' } else { & $at $row 'metadata.version' }); Effect = $effect
                            AllowedEffects = (@(& $list (& $at $row 'parameters.effect.allowedValues')) -join ', '); RolesNeeded = (@(& $rolesOf $row | ForEach-Object { if ($roleNames.Contains($_)) { $roleNames[$_] } else { $_ } }) -join ', ')
                            Initiatives = $(if ($usedByInitiative.Contains($key)) { $usedByInitiative[$key] } else { 0 }); DirectAssignments = $(if ($memberCount.Contains($key)) { $memberCount[$key] } else { 0 }); Assigned = $(if ($assigned) { 'Yes' } else { 'No' })
                            Deprecated = $(if (& $deprecated $row) { 'Yes' } else { 'No' }); Preview = $(if (& $preview $row) { 'Yes' } else { 'No' }); DefinedAt = & $definitionScope $id
                            Description = [string](& $at $row 'description'); HiddenMetadata = & $hidden (& $at $row 'metadata'); ResourceId = $id
                        })))
            if ($custom -and $platform) {
                if (-not $assigned -and -not $usedByInitiative.Contains($key)) { & $finding 'Low' 'Definition' 'Unassigned custom policy definition' $display 'Neither assigned nor in an initiative: perhaps a test, or no longer needed.' 'Assign it (in an initiative), or delete it if it isn''t needed.' "$docs/concepts/definition-structure-basics" (& $definitionScope $id) $id }
                if (-not (& $at $row 'metadata.category')) { & $finding 'Info' 'Definition' 'No category in the metadata' $display 'Without metadata.category, compliance can''t be read by category.' 'Set metadata.category (Azure''s common metadata properties).' "$docs/concepts/definition-structure-basics#common-metadata-properties" (& $definitionScope $id) $id }
            }
        }
    }
    foreach ($metadataId in $groupMetadata.Keys) {
        $names = @($groupMetadata[$metadataId] | ForEach-Object Name | Sort-Object -Unique)
        if ($names.Count -gt 1) { & $finding 'Low' 'Initiative' 'Same control, different group names' (& $leaf $metadataId) "Policy definition groups for $(& $leaf $metadataId) are named $($names -join ', ') in $(@($groupMetadata[$metadataId] | ForEach-Object Initiative | Sort-Object -Unique) -join ', ')." 'Name the groups for a control the same in every initiative.' "$docs/concepts/initiative-definition-structure#policy-definition-groups" '' $metadataId }
    }

    # --- Management groups (the hierarchy) and the tenant tree -----------------------------------------------------------------
    $subscriptionRate = @{}
    foreach ($row in $subscriptionRows) { $subscriptionRate[$row.SubscriptionId] = $row }
    $groupRows = @(foreach ($key in $inScopeGroups) {
            $under = @($inScopeSubscriptions | Where-Object { $subscriptionChain[$_] -contains $key })
            $n = [long](($under | ForEach-Object { $subscriptionRate[$_].NonCompliant } | Measure-Object -Sum).Sum); $c = [long](($under | ForEach-Object { $subscriptionRate[$_].Compliant } | Measure-Object -Sum).Sum)
            $e = [long](($under | ForEach-Object { $subscriptionRate[$_].Exempt } | Measure-Object -Sum).Sum); $x = [long](($under | ForEach-Object { $subscriptionRate[$_].Conflict } | Measure-Object -Sum).Sum)
            $pct = & $percent $c $e ($n + $c + $e + $x)
            & $object 'AAC.PolicyManagementGroup' ([ordered]@{
                    ManagementGroup = $groupNames[$key]; Name = $key; Parent = $(if ($groupNames.Contains($groupParent[$key])) { $groupNames[$groupParent[$key]] } else { '' }); Depth = @(& $ancestorsOfGroup $key).Count
                    Assignments = @($inScope | Where-Object { $_.Where.Group -eq $key }).Count; Subscriptions = $under.Count
                    NonCompliant = $n; Compliant = $c; Conflict = $x; Exempt = $e; CompliancePercent = $pct; Rating = & $rate $pct
                    ResourceId = "/providers/Microsoft.Management/managementGroups/$key"
                })
        }) | Sort-Object Depth, ManagementGroup
    $node = {
        param([string] $Group, [int] $Depth)
        $row = (@($groupRows | Where-Object Name -EQ $Group) | Select-Object -First 1)
        @{
            l = 'm'; n = $groupNames[$Group]; d = $Group; p = $(if ($null -ne $row.CompliancePercent) { [int]$row.CompliancePercent }); c = @(, @($row.Assignments, 'assignments'))
            f = @{ table = 'policy-assignments'; filters = @{ Scope = $groupNames[$Group] } }
            k = @(
                if ($Depth -lt 12) { foreach ($child in @($groupRows | Where-Object { $groupParent[$_.Name] -eq $Group } | Sort-Object ManagementGroup)) { & $node $child.Name ($Depth + 1) } }
                foreach ($sub in @($subscriptionRows | Where-Object { (@($subscriptionChain[$_.SubscriptionId]) | Select-Object -First 1) -eq $Group } | Sort-Object Subscription)) {
                    @{ l = 's'; n = $sub.Subscription; d = $sub.SubscriptionId; p = $(if ($null -ne $sub.CompliancePercent) { [int]$sub.CompliancePercent }); c = @(@($sub.Assignments, 'assignments'), @($sub.NonCompliant, 'non-compliant')); f = @{ table = 'policy-subscriptions'; filters = @{ Subscription = $sub.Subscription } } }
                }
            )
        }
    }
    $roots = @($groupRows | Where-Object { -not $inScopeGroups.Contains($groupParent[$_.Name]) })
    $overallN = [long](($subscriptionRows | Measure-Object NonCompliant -Sum).Sum); $overallC = [long](($subscriptionRows | Measure-Object Compliant -Sum).Sum)
    $overallE = [long](($subscriptionRows | Measure-Object Exempt -Sum).Sum); $overallX = [long](($subscriptionRows | Measure-Object Conflict -Sum).Sum)
    $overall = & $percent $overallC $overallE ($overallN + $overallC + $overallE + $overallX)
    $tree = @{ l = 't'; n = 'Azure Policy'; p = $(if ($null -ne $overall) { [int]$overall }); c = @(@($assignmentRows.Count, 'assignments'), @($subscriptionRows.Count, 'subscriptions')); k = @(
            foreach ($root in $roots) { & $node $root.Name 0 }
            # Subscriptions whose management group isn't in sight.
            foreach ($sub in @($subscriptionRows | Where-Object { -not $inScopeGroups.Contains([string](@($subscriptionChain[$_.SubscriptionId]) | Select-Object -First 1)) } | Sort-Object Subscription)) {
                @{ l = 's'; n = $sub.Subscription; d = $sub.SubscriptionId; p = $(if ($null -ne $sub.CompliancePercent) { [int]$sub.CompliancePercent }); c = @(@($sub.Assignments, 'assignments'), @($sub.NonCompliant, 'non-compliant')); f = @{ table = 'policy-subscriptions'; filters = @{ Subscription = $sub.Subscription } } }
            }
        )
    }

    $rank = @{ High = 0; Medium = 1; Low = 2; Info = 3 }
    $sorted = @($findings | Sort-Object -Property @{ Expression = { $rank[$_.Severity] } }, Area, Finding, Item)
    @{
        Assignments          = @($assignmentRows | Sort-Object -Property @{ Expression = { if ($null -eq $_.CompliancePercent) { 101 } else { $_.CompliancePercent } } }, Assignment)
        AssignmentCompliance = @($assignmentCompliance)
        Policies             = @($policyRows)
        InitiativePolicies   = @($memberRows)
        Categories           = @($categoryRows)
        Subscriptions        = @($subscriptionRows)
        ManagementGroups     = @($groupRows)
        Initiatives          = @($initiativeRows | Sort-Object Assigned, Initiative -Descending)
        Definitions          = @($definitionRows | Sort-Object Assigned, Definition -Descending)
        Exemptions           = @($exemptionRows)
        Roles                = $roleRows.ToArray()
        Findings             = $sorted
        Tree                 = $tree
        Audience             = $Audience
        Stats                = [ordered]@{
            Assignments          = $assignmentRows.Count
            Initiatives          = @($initiativeRows | Where-Object Assigned -EQ 'Yes').Count
            Definitions          = @($definitionRows | Where-Object Assigned -EQ 'Yes').Count
            Subscriptions        = @($subscriptionRows).Count
            ManagementGroups     = @($groupRows).Count
            Exemptions           = @($exemptionRows).Count
            ExpiringExemptions   = @($exemptionRows | Where-Object { $_.Status -in 'Expired', 'Expiring' }).Count
            CompliancePercent    = $overall
            Rating               = & $rate $overall
            NonCompliant         = $overallN
            Resources            = $overallN + $overallC + $overallE + $overallX
            NotEnforced          = @($assignmentRows | Where-Object Enforcement -EQ 'DoNotEnforce').Count
            High                 = @($sorted | Where-Object Severity -EQ 'High').Count
            Medium               = @($sorted | Where-Object Severity -EQ 'Medium').Count
            Low                  = @($sorted | Where-Object Severity -EQ 'Low').Count
            Info                 = @($sorted | Where-Object Severity -EQ 'Info').Count
        }
    }
}
