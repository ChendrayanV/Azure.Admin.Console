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

        Returns @{ Rows (AAC.AssignedPolicy); Assignments
        (AAC.PolicyAssignmentSummary); Missing (definition IDs not found);
        Stats }.
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
    $format = $null
    $format = {
        param($Value)
        if ($null -eq $Value) { return '' }
        if ($Value -is [string]) { return $Value }
        if ($Value -is [bool]) { return $Value.ToString().ToLowerInvariant() }
        if ($Value -is [System.Collections.IDictionary]) { return (ConvertTo-Json -InputObject $Value -Compress -Depth 20) }
        if ($Value -is [System.Collections.IList]) {
            return (@(foreach ($item in $Value) { if ($item -is [System.Collections.IDictionary] -or $item -is [System.Collections.IList]) { ConvertTo-Json -InputObject $item -Compress -Depth 20 } else { & $format $item } }) -join ', ')
        }
        [string]::Format([cultureinfo]::InvariantCulture, '{0}', $Value)
    }

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

        # Resource types: per parameter for an initiative (its members that use it).
        $rowTypes = @{}
        $allTypes = [System.Collections.Generic.SortedSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $memberCount = 0
        if ($policy -and $kind -eq 'PolicySet') {
            $byParameter = @{}
            $unrestricted = [System.Collections.Generic.List[string]]::new()
            foreach ($member in @($policy.Members)) {
                if ($member -isnot [System.Collections.IDictionary]) { continue }
                $memberCount++
                $memberDefinition = $Definition[([string](& $get $member 'policyDefinitionId')).ToLowerInvariant()]
                $memberValues = @{}
                $memberRefs = & $get $member 'parameters'
                $uses = [System.Collections.Generic.List[string]]::new()
                if ($memberDefinition -and $memberDefinition.Parameters -is [System.Collections.IDictionary]) {
                    foreach ($pn in $memberDefinition.Parameters.Keys) {
                        if (& $has $memberRefs $pn) {
                            $v = & $get (& $get $memberRefs $pn) 'value'
                            if ($v -is [string] -and $v -match "^\[parameters\('([^']+)'\)\]$") {
                                $setName = $Matches[1]
                                $uses.Add($setName)
                                $memberValues[$pn] = & $get $effective $setName
                            }
                            else { $memberValues[$pn] = $v }
                        }
                        elseif (& $has $memberDefinition.Parameters[$pn] 'defaultValue') { $memberValues[$pn] = & $get $memberDefinition.Parameters[$pn] 'defaultValue' }
                    }
                }
                if (-not $memberDefinition) { continue }
                $found = Get-AACPolicyResourceType -Rule $memberDefinition.Rule -Parameter $memberValues
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
    @{
        Rows        = $sortedRows
        Assignments = $sortedSummaries
        Missing     = @($missing)
        Stats       = @{
            Assignments   = $sortedSummaries.Count
            Initiatives   = @($sortedSummaries | Where-Object DefinitionType -EQ 'PolicySet').Count
            Policies      = @($sortedSummaries | Where-Object DefinitionType -EQ 'Policy').Count
            Rows          = $sortedRows.Count
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
