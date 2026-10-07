function ConvertTo-AACAssignedPolicy {
    <#
    .SYNOPSIS
        Flattens Azure Policy assignments to one row per assignment and
        parameter - the default, assigned and effective value, and the
        resource types the policy applies to - for Get-AACAssignedPolicy.
    .DESCRIPTION
        -Assignment are Resource Graph rows of
        microsoft.authorization/policyassignments (id, name, displayName,
        scope, definitionId, parameters, enforcement, notScopes,
        description). -Definition maps a definition's or initiative's
        lower-case ID to @{ Id; Name; DisplayName; Kind ('Policy' or
        'PolicySet'); PolicyType; Category; Parameters; Rule; Members }.

        Which assignments: all of them, or - with -SubscriptionId or
        -ManagementGroupId - those that apply there: at the scope or below
        it, and those inherited from the management groups above it
        (Inherited = $true), as the portal lists a scope's assignments.
        -SubscriptionChain and -GroupChain give each subscription's and
        management group's ancestors, root first. -AssignmentName keeps the
        assignments whose name or display name matches (wildcards).

        Each parameter of the definition (or initiative) is one row:
        DefaultValue (the definition's), AssignedValue (the assignment's),
        EffectiveValue (assigned, else the default) and ValueSource
        (Assigned, Default, Not set); arrays are joined with ', ', objects
        written as compact JSON. A definition without parameters is one row
        with no parameter, so every assignment is listed.

        ResourceType: the types the policy's rule targets
        (Get-AACPolicyResourceType), with [parameters()] resolved to the
        effective values - so "Not allowed resource types" shows the types
        it denies. For an initiative, the types of the member policies that use
        the row's parameter (each member's parameters resolved through the
        initiative's), or of every member for a row with no parameter -
        'All' when one of them names no type.

        Members: one row per policy the assignment puts in force and its
        parameter (AAC.AssignedPolicyMember) - an initiative's member
        policies, or the one policy assigned - with the value each parameter
        ends up with through the initiative and the assignment
        (Resolve-AACPolicySetMember), the effect and the policy's resource
        types.

        Returns @{ Rows (AAC.AssignedPolicy); Members
        (AAC.AssignedPolicyMember); Assignments (AAC.PolicyAssignmentSummary);
        Missing (definition IDs not found); Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Assignment,

        [System.Collections.IDictionary] $Definition = @{},

        [System.Collections.IDictionary] $SubscriptionName = @{},

        [System.Collections.IDictionary] $ManagementGroupName = @{},

        # Subscription ID (lower case) -> management group names, root first.
        [System.Collections.IDictionary] $SubscriptionChain = @{},

        # Management group name (lower case) -> its ancestors and itself, root first.
        [System.Collections.IDictionary] $GroupChain = @{},

        [string[]] $SubscriptionId = @(),

        [string[]] $ManagementGroupId = @(),

        [string[]] $AssignmentName = @()
    )

    $get = {
        param($Map, [string] $Name)
        if ($Map -isnot [System.Collections.IDictionary]) { return }
        foreach ($k in $Map.Keys) { if ($k -eq $Name) { return $Map[$k] } }
    }
    $has = {
        param($Map, [string] $Name)
        if ($Map -isnot [System.Collections.IDictionary]) { return $false }
        foreach ($k in $Map.Keys) { if ($k -eq $Name) { return $true } }
        $false
    }
    $format = { param($Value) Format-AACPolicyValue -Value $Value }

    # --- Where each scope sits: root management group first -------------------------------------
    $pathOf = {
        param([string] $Scope)
        $scope = $Scope.ToLowerInvariant().TrimEnd('/')
        if ($scope -match '^/providers/microsoft\.management/managementgroups/([^/]+)$') {
            $mg = $Matches[1]
            $chain = if ($GroupChain.Contains($mg)) { @($GroupChain[$mg]) } else { @($mg) }
            return @($chain | ForEach-Object { "mg:$($_.ToLowerInvariant())" })
        }
        if ($scope -match '^/subscriptions/([^/]+)(/resourcegroups/([^/]+))?(/.+)?$') {
            $sub = $Matches[1]; $group = $Matches[3]; $rest = $Matches[4]
            $path = [System.Collections.Generic.List[string]]::new()
            if ($SubscriptionChain.Contains($sub)) { foreach ($mg in @($SubscriptionChain[$sub])) { $path.Add("mg:$(([string]$mg).ToLowerInvariant())") } }
            $path.Add("sub:$sub")
            if ($group) { $path.Add("rg:$sub/$group") }
            if ($rest) { $path.Add("res:$scope") }
            return $path.ToArray()
        }
        @($scope)
    }
    $startsWith = {
        param([string[]] $Short, [string[]] $Long)
        if ($Short.Count -gt $Long.Count) { return $false }
        for ($i = 0; $i -lt $Short.Count; $i++) { if ($Short[$i] -ne $Long[$i]) { return $false } }
        $true
    }
    $targets = @(
        foreach ($id in $SubscriptionId) { , (& $pathOf "/subscriptions/$id") }
        foreach ($id in $ManagementGroupId) { , (& $pathOf "/providers/Microsoft.Management/managementGroups/$id") }
    )
    $subscriptionLabel = { param([string] $Id) if ($SubscriptionName.Contains($Id.ToLowerInvariant())) { $SubscriptionName[$Id.ToLowerInvariant()] } else { $Id } }
    $scopeInfo = {
        param([string] $Scope)
        if ($Scope -match '(?i)/managementGroups/([^/]+)$') {
            $mg = $Matches[1]
            return @{ Type = 'Management group'; Name = $(if ($ManagementGroupName.Contains($mg.ToLowerInvariant())) { $ManagementGroupName[$mg.ToLowerInvariant()] } else { $mg }) }
        }
        if ($Scope -match '(?i)^/subscriptions/([^/]+)/resourceGroups/([^/]+)$') { return @{ Type = 'Resource group'; Name = "$($Matches[2]) ($(& $subscriptionLabel $Matches[1]))" } }
        if ($Scope -match '(?i)^/subscriptions/([^/]+)$') { return @{ Type = 'Subscription'; Name = (& $subscriptionLabel $Matches[1]) } }
        if ($Scope -match '(?i)^/subscriptions/([^/]+)/resourceGroups/([^/]+)/providers/.+/([^/]+)$') { return @{ Type = 'Resource'; Name = "$($Matches[3]) ($($Matches[2]))" } }
        @{ Type = 'Other'; Name = $Scope }
    }

    # --- One definition's parameters, effective values and resource types --------------------------
    $effectiveOf = {
        param($Parameters, $Assigned)
        $values = [ordered]@{}
        if ($Parameters -is [System.Collections.IDictionary]) {
            foreach ($name in $Parameters.Keys) {
                $spec = $Parameters[$name]
                if (& $has $Assigned $name) { $values[$name] = & $get (& $get $Assigned $name) 'value' }
                elseif (& $has $spec 'defaultValue') { $values[$name] = & $get $spec 'defaultValue' }
                else { $values[$name] = $null }
            }
        }
        $values
    }
    $specific = { param($Types) if ($Types.Include.Count) { $Types.Include } else { $Types.Aliased } }

    $rows = [System.Collections.Generic.List[object]]::new()
    $memberRows = [System.Collections.Generic.List[object]]::new()
    $summaries = [System.Collections.Generic.List[object]]::new()
    $missing = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $typeCounts = @{}

    foreach ($a in $Assignment) {
        $name = [string](& $get $a 'name')
        $displayName = [string](& $get $a 'displayName')
        if ($AssignmentName.Count -and -not @($AssignmentName | Where-Object { $name -like $_ -or $displayName -like $_ }).Count) { continue }
        $scope = [string](& $get $a 'scope')
        $inherited = $false
        if ($targets.Count) {
            $path = & $pathOf $scope
            $below = $false; $above = $false
            foreach ($target in $targets) {
                if (& $startsWith $target $path) { $below = $true }
                elseif (& $startsWith $path $target) { $above = $true }
            }
            if (-not ($below -or $above)) { continue }
            $inherited = $above -and -not $below
        }

        $definitionId = [string](& $get $a 'definitionId')
        $policy = $Definition[$definitionId.ToLowerInvariant()]
        $assigned = & $get $a 'parameters'
        $info = & $scopeInfo $scope
        $kind = if ($policy) { $policy.Kind } elseif ($definitionId -match '(?i)/policySetDefinitions/') { 'PolicySet' } else { 'Policy' }
        if (-not $policy) { $null = $missing.Add($definitionId) }
        $parameters = if ($policy) { $policy.Parameters } else { $null }
        $effective = & $effectiveOf $parameters $assigned

        # The policies the assignment puts in force, each parameter's value
        # resolved: an initiative's members, or the one policy assigned.
        $resolved = @(if ($policy -and $kind -eq 'PolicySet') {
                Resolve-AACPolicySetMember -Member @($policy.Members) -SetParameter $policy.Parameters -Assigned $assigned -Override @(& $get $a 'overrides') -Definition $Definition
            }
            elseif ($kind -eq 'Policy') {
                $refs = @{}
                if ($assigned -is [System.Collections.IDictionary]) { foreach ($k in $assigned.Keys) { $refs[$k] = @{ value = "[parameters('$k')]" } } }
                Resolve-AACPolicySetMember -Member @(@{ policyDefinitionId = $definitionId; parameters = $refs }) -Assigned $assigned -Override @(& $get $a 'overrides') -Definition $Definition
            })

        # Resource types: per parameter for an initiative (its members that use it).
        $rowTypes = @{}
        $allTypes = [System.Collections.Generic.SortedSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $memberCount = 0
        if ($policy -and $kind -eq 'PolicySet') {
            $byParameter = @{}
            $unrestricted = [System.Collections.Generic.List[string]]::new()
            foreach ($member in $resolved) {
                $memberCount++
                if (-not $member.Definition) { continue }
                $uses = @($member.Parameters | Where-Object SetParameter | ForEach-Object SetParameter)
                $found = Get-AACPolicyResourceType -Rule $member.Definition.Rule -Parameter $member.Values
                $member.ResourceType = $found.Text
                $types = @(& $specific $found)
                # A member that names no type ('All', 'All except ...') applies
                # to every type: whatever uses its parameter does too.
                if (-not $types.Count) { $unrestricted.Add($found.Text) }
                foreach ($t in $types) { $null = $allTypes.Add($t) }
                foreach ($setName in $uses) {
                    $key = $setName.ToLowerInvariant()
                    if (-not $byParameter.ContainsKey($key)) { $byParameter[$key] = @{ Types = [System.Collections.Generic.SortedSet[string]]::new([StringComparer]::OrdinalIgnoreCase); Open = [System.Collections.Generic.List[string]]::new() } }
                    foreach ($t in $types) { $null = $byParameter[$key].Types.Add($t) }
                    if (-not $types.Count) { $byParameter[$key].Open.Add($found.Text) }
                }
            }
            $openText = { param($Open, $Types) $distinct = @($Open | Select-Object -Unique); if (-not $Types.Count -and $distinct.Count -eq 1) { $distinct[0] } else { 'All' } }
            foreach ($key in $byParameter.Keys) {
                $entry = $byParameter[$key]
                $rowTypes[$key] = if ($entry.Open.Count) { & $openText $entry.Open $entry.Types } elseif ($entry.Types.Count) { @($entry.Types) -join ', ' } else { 'All' }
            }
            $assignmentTypes = if ($unrestricted.Count) { & $openText $unrestricted $allTypes } elseif ($allTypes.Count) { @($allTypes) -join ', ' } else { 'All' }
        }
        elseif ($policy) {
            $types = Get-AACPolicyResourceType -Rule $policy.Rule -Parameter $effective
            foreach ($t in @(& $specific $types)) { $null = $allTypes.Add($t) }
            $assignmentTypes = $types.Text
        }
        else { $assignmentTypes = '' }
        foreach ($t in $allTypes) { $typeCounts[$t] = 1 + [int]$typeCounts[$t] }

        $base = [ordered]@{
            PSTypeName            = 'AAC.AssignedPolicy'
            AssignmentName        = $name
            AssignmentDisplayName = $displayName
            ScopeType             = $info.Type
            ScopeName             = $info.Name
            Inherited             = $inherited
            EnforcementMode       = $(if (& $get $a 'enforcement') { [string](& $get $a 'enforcement') } else { 'Default' })
            DefinitionType        = $kind
            DefinitionName        = $(if ($policy) { $policy.Name } else { ($definitionId -split '/')[-1] })
            DefinitionDisplayName = $(if ($policy) { $policy.DisplayName } else { '(definition not found)' })
            PolicyType            = $(if ($policy) { $policy.PolicyType } else { '' })
            Category              = $(if ($policy) { $policy.Category } else { '' })
            ResourceType          = $assignmentTypes
            ParameterName         = ''
            ParameterDisplayName  = ''
            ParameterType         = ''
            DefaultValue          = ''
            AssignedValue         = ''
            EffectiveValue        = ''
            ValueSource           = ''
            AllowedValues         = ''
            NotScopes             = (@(& $get $a 'notScopes') | Where-Object { $_ }) -join ', '
            AssignmentScope       = $scope
            AssignmentId          = [string](& $get $a 'id')
            DefinitionId          = $definitionId
        }

        $names = @(if ($parameters -is [System.Collections.IDictionary]) { $parameters.Keys } elseif ($assigned -is [System.Collections.IDictionary]) { $assigned.Keys })
        $assignedCount = 0
        if (-not $names.Count) { $rows.Add([pscustomobject]$base) }
        foreach ($parameterName in $names) {
            $spec = & $get $parameters $parameterName
            $row = [ordered]@{}
            foreach ($key in $base.Keys) { $row[$key] = $base[$key] }
            $row.ParameterName = [string]$parameterName
            $row.ParameterDisplayName = [string](& $get (& $get $spec 'metadata') 'displayName')
            $row.ParameterType = [string](& $get $spec 'type')
            $isAssigned = & $has $assigned $parameterName
            $hasDefault = & $has $spec 'defaultValue'
            $assignedValue = if ($isAssigned) { & $get (& $get $assigned $parameterName) 'value' } else { $null }
            $defaultValue = if ($hasDefault) { & $get $spec 'defaultValue' } else { $null }
            $row.DefaultValue = & $format $defaultValue
            $row.AssignedValue = & $format $assignedValue
            $row.EffectiveValue = $(if ($isAssigned) { $row.AssignedValue } else { $row.DefaultValue })
            $row.ValueSource = $(if ($isAssigned) { 'Assigned' } elseif ($hasDefault) { 'Default' } else { 'Not set' })
            $row.AllowedValues = & $format (& $get $spec 'allowedValues')
            if ($kind -eq 'PolicySet' -and $policy) {
                $row.ResourceType = $(if ($rowTypes.ContainsKey(([string]$parameterName).ToLowerInvariant())) { $rowTypes[([string]$parameterName).ToLowerInvariant()] } else { $assignmentTypes })
            }
            if ($isAssigned) { $assignedCount++ }
            $rows.Add([pscustomobject]$row)
        }

        # One row per policy in force and its parameter (-ExpandPolicySet).
        foreach ($member in $resolved) {
            $memberDefinition = $member.Definition
            $inSet = $kind -eq 'PolicySet'
            $memberBase = [ordered]@{
                PSTypeName            = 'AAC.AssignedPolicyMember'
                AssignmentName        = $name
                AssignmentDisplayName = $displayName
                ScopeType             = $info.Type
                ScopeName             = $info.Name
                Inherited             = $inherited
                EnforcementMode       = $base.EnforcementMode
                DefinitionType        = $kind
                PolicySetName         = $(if ($inSet) { $base.DefinitionName } else { '' })
                PolicySetDisplayName  = $(if ($inSet) { $base.DefinitionDisplayName } else { '' })
                ReferenceId           = $member.ReferenceId
                PolicyName            = $(if ($memberDefinition) { $memberDefinition.Name } else { ($member.DefinitionId -split '/')[-1] })
                PolicyDisplayName     = $(if ($memberDefinition) { $memberDefinition.DisplayName } else { '(definition not found)' })
                PolicyType            = $(if ($memberDefinition) { $memberDefinition.PolicyType } else { '' })
                Category              = $(if ($memberDefinition) { $memberDefinition.Category } else { '' })
                Effect                = $member.Effect
                EffectSource          = $(if ($member.Effect) { $member.EffectSource } else { '' })
                Groups                = @($member.Groups) -join ', '
                ResourceType          = $(if ($inSet) { [string]$member.ResourceType } else { $assignmentTypes })
                ParameterName         = ''
                ParameterDisplayName  = ''
                ParameterType         = ''
                DefaultValue          = ''
                InitiativeValue       = ''
                InitiativeParameter   = ''
                EffectiveValue        = ''
                ValueSource           = ''
                AllowedValues         = ''
                NotScopes             = $base.NotScopes
                AssignmentScope       = $scope
                AssignmentId          = $base.AssignmentId
                PolicySetId           = $(if ($inSet) { $definitionId } else { '' })
                PolicyId              = $member.DefinitionId
            }
            if (-not @($member.Parameters).Count) { $memberRows.Add([pscustomobject]$memberBase) }
            foreach ($p in $member.Parameters) {
                $row = [ordered]@{}
                foreach ($key in $memberBase.Keys) { $row[$key] = $memberBase[$key] }
                $row.ParameterName = $p.Name
                $row.ParameterDisplayName = $p.DisplayName
                $row.ParameterType = $p.Type
                $row.DefaultValue = & $format $p.DefaultValue
                # A single policy's values come from the assignment, not an initiative.
                if ($inSet) {
                    $row.InitiativeValue = & $format $p.SetValue
                    $row.InitiativeParameter = $p.SetParameter
                }
                $row.EffectiveValue = & $format $p.Value
                $row.ValueSource = $p.Source
                $row.AllowedValues = & $format $p.AllowedValues
                $memberRows.Add([pscustomobject]$row)
            }
        }

        $summaries.Add([pscustomobject][ordered]@{
                PSTypeName            = 'AAC.PolicyAssignmentSummary'
                AssignmentName        = $name
                AssignmentDisplayName = $(if ($displayName) { $displayName } else { $name })
                ScopeType             = $info.Type
                ScopeName             = $info.Name
                Inherited             = $inherited
                EnforcementMode       = $base.EnforcementMode
                DefinitionType        = $kind
                DefinitionDisplayName = $base.DefinitionDisplayName
                PolicyType            = $base.PolicyType
                Category              = $base.Category
                Members               = $memberCount
                Parameters            = $names.Count
                Assigned              = $assignedCount
                ResourceType          = $assignmentTypes
                ResourceTypes         = $allTypes.Count
                NotScopes             = $base.NotScopes
                AssignmentScope       = $scope
                AssignmentId          = $base.AssignmentId
                DefinitionId          = $definitionId
            })
    }

    $scopeOrder = @{ 'Management group' = 0; Subscription = 1; 'Resource group' = 2; Resource = 3; Other = 4 }
    $sortedRows = @($rows | Sort-Object -Property @{ Expression = { $scopeOrder[$_.ScopeType] } }, ScopeName, AssignmentDisplayName, AssignmentName, ParameterName)
    $sortedSummaries = @($summaries | Sort-Object -Property @{ Expression = { $scopeOrder[$_.ScopeType] } }, ScopeName, AssignmentDisplayName)
    $parameterRows = @($sortedRows | Where-Object ParameterName)
    $sortedMembers = @($memberRows | Sort-Object -Property @{ Expression = { $scopeOrder[$_.ScopeType] } }, ScopeName, AssignmentDisplayName, AssignmentName, PolicyDisplayName, ReferenceId, ParameterName)
    $setMembers = @($sortedMembers | Where-Object DefinitionType -EQ 'PolicySet')
    @{
        Rows        = $sortedRows
        Members     = $sortedMembers
        Assignments = $sortedSummaries
        Missing     = @($missing)
        Stats       = @{
            Assignments   = $sortedSummaries.Count
            Initiatives   = @($sortedSummaries | Where-Object DefinitionType -EQ 'PolicySet').Count
            Policies      = @($sortedSummaries | Where-Object DefinitionType -EQ 'Policy').Count
            Rows          = $sortedRows.Count
            # The policies inside the assigned initiatives (per assignment), and their parameters.
            MemberPolicies   = @($setMembers | ForEach-Object { "$($_.AssignmentId)|$($_.ReferenceId)|$($_.PolicyId)" } | Select-Object -Unique).Count
            MemberParameters = @($setMembers | Where-Object ParameterName).Count
            Parameters    = $parameterRows.Count
            Assigned      = @($parameterRows | Where-Object ValueSource -EQ 'Assigned').Count
            Default       = @($parameterRows | Where-Object ValueSource -EQ 'Default').Count
            NotSet        = @($parameterRows | Where-Object ValueSource -EQ 'Not set').Count
            DoNotEnforce  = @($sortedSummaries | Where-Object EnforcementMode -EQ 'DoNotEnforce').Count
            Inherited     = @($sortedSummaries | Where-Object Inherited).Count
            Custom        = @($sortedSummaries | Where-Object PolicyType -EQ 'Custom').Count
            Missing       = $missing.Count
            ResourceTypes = @($typeCounts.GetEnumerator() | Sort-Object -Property @{ Expression = 'Value'; Descending = $true }, Name | ForEach-Object { @{ Label = $_.Name; Value = $_.Value } })
        }
    }
}
