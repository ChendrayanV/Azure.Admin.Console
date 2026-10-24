function ConvertTo-AACAzureLimit {
    <#
    .SYNOPSIS
        Builds Test-AACAzureLimit's list (AAC.AzureLimit) from the Resource
        Graph totals of Get-AACAzureLimitQuery: each scope's use of each
        Azure limit, how close it is, and what to do.
    .DESCRIPTION
        No Azure calls. -Read is Invoke-AACGraphBatch's result; -Scope is
        Resolve-AACScope's (the subscriptions in scope, their names and
        management group chains; an empty GraphScope means every
        subscription the account can see). Management groups count when one of the subscriptions in
        scope sits under them (or, unscoped, all of them).

        The limits (Microsoft Learn, "Azure subscription and service
        limits"), each overridable with -Maximum (name -> number):
          RoleAssignmentsPerSubscription     4,000   at or below a subscription
          RoleAssignmentsPerManagementGroup    500   at a management group
          CustomRolesPerTenant               5,000
          PolicyAssignmentsPerScope            200   management group, subscription, resource group
          PolicyDefinitionsPerScope            500   custom, management group or subscription
          PolicySetDefinitionsPerScope         200   custom, management group or subscription
          PolicySetDefinitionsPerTenant      2,500
          PolicyExemptionsPerScope           1,000
          ResourceGroupsPerSubscription        980
          TagsPerSubscription                   50
          TagsPerResourceGroup                  50   the resource group with the most, per subscription
          TagsPerResource                       50   the resource with the most, per subscription
          ManagementGroupDepth                   6   levels below the root
          ManagementGroupsPerTenant         10,000

        Status: Critical at -CriticalPercent (95) or more of the maximum,
        Warning at -WarningPercent (80), else OK. Nothing in use is left
        out; resource groups only appear when they reach the warning level.
        Returns @{ Limits (worst first); Notices; Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Read,

        [Parameter(Mandatory)]
        [hashtable] $Scope,

        [hashtable] $Maximum = @{},

        [ValidateRange(1, 100)]
        [int] $WarningPercent = 80,

        [ValidateRange(1, 100)]
        [int] $CriticalPercent = 95
    )

    $get = ${function:Get-AACMember}
    $text = { param($Object, [string] $Path) $v = & $get $Object $Path; if ($null -eq $v) { '' } else { [string]$v } }
    $number = { param($Object, [string] $Path) $v = & $get $Object $Path; if ($null -eq $v -or '' -eq $v) { 0 } else { [int64]$v } }
    $rowsOf = { param([string] $Name) @(if ($Read.Rows -and $Read.Rows.Contains($Name)) { $Read.Rows[$Name] | Where-Object { $null -ne $_ } }) }
    $notices = [System.Collections.Generic.List[string]]::new()
    $what = @{ rbacBySubscription = 'role assignments'; rbacByGroup = 'management group role assignments'; customRoles = 'custom roles'; policyAssignments = 'policy assignments'; policyDefinitions = 'policy definitions'; policySets = 'initiative definitions'; policyExemptions = 'policy exemptions'; managementGroups = 'management groups'; resourceGroups = 'resource groups'; subscriptionTags = 'subscription tags'; groupTags = 'resource group tags'; resourceTags = 'resource tags' }
    foreach ($key in @($Read.Errors.Keys | Sort-Object)) { $notices.Add("The $(if ($what.Contains($key)) { $what[$key] } else { $key }) couldn't be counted: $($Read.Errors[$key] -replace '\s+', ' ')") }

    $limits = [ordered]@{
        RoleAssignmentsPerSubscription    = @{ Max = 4000; Label = 'Role assignments'; Advice = 'Assign roles to groups, not to each user; remove orphaned and duplicate assignments (Get-AACRoleAssignment lists them).' }
        RoleAssignmentsPerManagementGroup = @{ Max = 500; Label = 'Role assignments'; Advice = 'Assign roles to groups; move assignments that only one subscription needs down to it.' }
        CustomRolesPerTenant              = @{ Max = 5000; Label = 'Custom roles'; Advice = 'Delete unused custom roles and merge near-duplicates (Get-AACRoleAssignment lists the unused ones).' }
        PolicyAssignmentsPerScope         = @{ Max = 200; Label = 'Policy assignments'; Advice = 'Group policies into initiatives and assign the initiative once; assign at a management group rather than each subscription.' }
        PolicyDefinitionsPerScope         = @{ Max = 500; Label = 'Custom policy definitions'; Advice = 'Delete unused definitions; parameterise near-duplicates into one; keep definitions at a parent management group.' }
        PolicySetDefinitionsPerScope      = @{ Max = 200; Label = 'Custom initiatives'; Advice = 'Delete unused initiatives and merge overlapping ones.' }
        PolicySetDefinitionsPerTenant     = @{ Max = 2500; Label = 'Custom initiatives'; Advice = 'Delete unused initiatives and merge overlapping ones.' }
        PolicyExemptionsPerScope          = @{ Max = 1000; Label = 'Policy exemptions'; Advice = 'Remove expired exemptions; exempt at a broader scope, or exclude the scope in the assignment instead.' }
        ResourceGroupsPerSubscription     = @{ Max = 980; Label = 'Resource groups'; Advice = 'Delete empty resource groups (Get-AACUnusedResource), or spread workloads across subscriptions.' }
        TagsPerSubscription               = @{ Max = 50; Label = 'Tags'; Advice = 'Combine related tags into one (a JSON value), and drop tags nobody reads.' }
        TagsPerResourceGroup              = @{ Max = 50; Label = 'Tags (resource group with the most)'; Advice = 'Combine related tags into one, and drop tags nobody reads.' }
        TagsPerResource                   = @{ Max = 50; Label = 'Tags (resource with the most)'; Advice = 'Combine related tags into one, and drop tags nobody reads.' }
        ManagementGroupDepth              = @{ Max = 6; Label = 'Management group depth'; Advice = 'Flatten the hierarchy: group by policy and access needs, not by organisation chart.' }
        ManagementGroupsPerTenant         = @{ Max = 10000; Label = 'Management groups'; Advice = 'Remove empty management groups.' }
    }
    foreach ($key in @($Maximum.Keys)) {
        if (-not $limits.Contains($key)) { throw "Azure Admin Console doesn't know the limit '$key'. Use one of: $($limits.Keys -join ', ')." }
        $limits[$key].Max = [int64]$Maximum[$key]
    }

    # What is in scope: the subscriptions, and the management groups above them.
    $inScope = @{}
    $groupsInScope = @{}
    foreach ($s in @($Scope.Subscriptions)) {
        $inScope[([string]$s['subscriptionId']).ToLowerInvariant()] = $true
        foreach ($m in @($s['chain'])) { if ($m -is [System.Collections.IDictionary]) { $groupsInScope[([string]$m['name']).ToLowerInvariant()] = $true } }
    }
    $unscoped = -not @($Scope['GraphScope'] | Where-Object { $_ }).Count
    $groupName = @{}
    foreach ($row in (& $rowsOf 'managementGroups')) { $groupName[(& $text $row 'name')] = $(if (& $text $row 'displayName') { & $text $row 'displayName' } else { & $text $row 'name' }) }
    $subName = { param([string] $Id) if ($Scope.Names -and $Scope.Names.Contains($Id)) { $Scope.Names[$Id] } else { $Id } }
    # A scope string's kind, name and whether it is in scope.
    $describe = {
        param([string] $ScopeId)
        $s = $ScopeId.ToLowerInvariant()
        if ($s -match '^/providers/microsoft\.management/managementgroups/([^/]+)$') {
            $g = $Matches[1]
            return @{ Type = 'Management group'; Name = $(if ($groupName.Contains($g)) { $groupName[$g] } else { $g }); In = ($unscoped -or $groupsInScope.Contains($g)) }
        }
        if ($s -match '^/subscriptions/([^/]+)/resourcegroups/([^/]+)$') { return @{ Type = 'Resource group'; Name = "$($Matches[2]) ($(& $subName $Matches[1]))"; In = $inScope.Contains($Matches[1]) } }
        if ($s -match '^/subscriptions/([^/]+)$') { return @{ Type = 'Subscription'; Name = (& $subName $Matches[1]); In = $inScope.Contains($Matches[1]) } }
        @{ Type = 'Other'; Name = $ScopeId; In = $false }
    }

    $items = [System.Collections.Generic.List[object]]::new()
    $add = {
        param([string] $Key, [string] $ScopeType, [string] $ScopeName, [string] $ScopeId, [int64] $Used, [string] $Detail = '')
        if ($Used -le 0) { return }
        $limit = $limits[$Key]
        $percent = [Math]::Round(100.0 * $Used / [Math]::Max(1, $limit.Max), 1)
        $status = if ($percent -ge $CriticalPercent) { 'Critical' } elseif ($percent -ge $WarningPercent) { 'Warning' } else { 'OK' }
        if ($ScopeType -eq 'Resource group' -and $status -eq 'OK') { return }
        $item = [pscustomobject][ordered]@{
            Status    = $status
            Limit     = $limit.Label
            ScopeType = $ScopeType
            Scope     = $ScopeName
            Used      = $Used
            Maximum   = $limit.Max
            Percent   = $percent
            Remaining = [Math]::Max(0, $limit.Max - $Used)
            Detail    = $Detail
            Advice    = $(if ($status -eq 'OK') { '' } else { $limit.Advice })
            LimitName = $Key
            ScopeId   = $ScopeId
        }
        $item.PSObject.TypeNames.Insert(0, 'AAC.AzureLimit')
        $items.Add($item)
    }

    # --- Tenant ------------------------------------------------------------------------------------------------------------
    $customRoles = 0; foreach ($row in (& $rowsOf 'customRoles')) { $customRoles += & $number $row 'used' }
    & $add 'CustomRolesPerTenant' 'Tenant' 'Tenant' '/' $customRoles
    $setsTotal = 0; foreach ($row in (& $rowsOf 'policySets')) { $setsTotal += & $number $row 'used' }
    & $add 'PolicySetDefinitionsPerTenant' 'Tenant' 'Tenant' '/' $setsTotal
    $groups = @(& $rowsOf 'managementGroups')
    & $add 'ManagementGroupsPerTenant' 'Tenant' 'Tenant' '/' $groups.Count
    if ($groups.Count) {
        $deepest = @($groups | Sort-Object { & $number $_ 'depth' } -Descending)[0]
        $depth = & $number $deepest 'depth'
        & $add 'ManagementGroupDepth' 'Tenant' 'Tenant' '/' $depth "Deepest: $(& $text $deepest 'displayName')"
    }

    # --- Role assignments ----------------------------------------------------------------------------------------------------
    foreach ($row in (& $rowsOf 'rbacBySubscription')) {
        $id = (& $text $row 'subscriptionId').ToLowerInvariant()
        if ($inScope.Contains($id)) { & $add 'RoleAssignmentsPerSubscription' 'Subscription' (& $subName $id) "/subscriptions/$id" (& $number $row 'used') }
    }
    foreach ($row in (& $rowsOf 'rbacByGroup')) {
        $d = & $describe (& $text $row 'scope')
        if ($d.In) { & $add 'RoleAssignmentsPerManagementGroup' $d.Type $d.Name (& $text $row 'scope') (& $number $row 'used') }
    }

    # --- Policy, per scope ----------------------------------------------------------------------------------------------------
    foreach ($pair in @(@('policyAssignments', 'PolicyAssignmentsPerScope'), @('policyDefinitions', 'PolicyDefinitionsPerScope'), @('policySets', 'PolicySetDefinitionsPerScope'), @('policyExemptions', 'PolicyExemptionsPerScope'))) {
        foreach ($row in (& $rowsOf $pair[0])) {
            $d = & $describe (& $text $row 'scope')
            if ($d.In) { & $add $pair[1] $d.Type $d.Name (& $text $row 'scope') (& $number $row 'used') }
        }
    }

    # --- Per subscription ----------------------------------------------------------------------------------------------------
    foreach ($row in (& $rowsOf 'resourceGroups')) {
        $id = (& $text $row 'subscriptionId').ToLowerInvariant()
        if ($inScope.Contains($id)) { & $add 'ResourceGroupsPerSubscription' 'Subscription' (& $subName $id) "/subscriptions/$id" (& $number $row 'used') }
    }
    foreach ($row in (& $rowsOf 'subscriptionTags')) {
        $id = (& $text $row 'subscriptionId').ToLowerInvariant()
        if ($inScope.Contains($id)) { & $add 'TagsPerSubscription' 'Subscription' (& $subName $id) "/subscriptions/$id" (& $number $row 'used') }
    }
    foreach ($row in (& $rowsOf 'groupTags')) {
        $id = (& $text $row 'subscriptionId').ToLowerInvariant()
        if ($inScope.Contains($id)) { & $add 'TagsPerResourceGroup' 'Subscription' (& $subName $id) "/subscriptions/$id" (& $number $row 'used') "Most: resource group $(& $text $row 'name')" }
    }
    foreach ($row in (& $rowsOf 'resourceTags')) {
        $id = (& $text $row 'subscriptionId').ToLowerInvariant()
        if ($inScope.Contains($id)) { & $add 'TagsPerResource' 'Subscription' (& $subName $id) "/subscriptions/$id" (& $number $row 'used') "Most: $(& $text $row 'name') ($((& $text $row 'type') -replace '^.*/', ''))" }
    }

    $rank = @{ Critical = 0; Warning = 1; OK = 2 }
    $sorted = @($items | Sort-Object -Property @{ Expression = { $rank[$_.Status] } }, @{ Expression = 'Percent'; Descending = $true }, Limit, Scope)
    @{
        Limits  = $sorted
        Notices = @($notices)
        Stats   = @{
            Limits   = $sorted.Count
            Critical = @($sorted | Where-Object Status -EQ 'Critical').Count
            Warning  = @($sorted | Where-Object Status -EQ 'Warning').Count
            Highest  = $(if ($sorted.Count) { (@($sorted | Sort-Object Percent -Descending))[0].Percent } else { 0 })
        }
    }
}
