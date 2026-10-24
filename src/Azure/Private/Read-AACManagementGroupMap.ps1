function Read-AACManagementGroupMap {
    <#
    .SYNOPSIS
        Reads the management group hierarchy and builds it as a map model -
        the tenant root and management groups as nested boxes, each
        subscription a node inside its group - with how many subscriptions,
        policy assignments and role assignments sit at each level.
    .DESCRIPTION
        For Show-AACManagementGroupMap and Export-AACDiagram -View
        Governance. Call it inside Invoke-AACProgress. Reads, tenant-wide in
        Azure Resource Graph: the management groups and their parents, the
        subscriptions and their chains (Resolve-AACScope), the policy and
        role assignments per scope, and the resources per subscription.

        Scoped (-ManagementGroupId or -SubscriptionId), only the
        subscriptions in scope and the groups above them appear; unscoped,
        every group, empty ones too.
        Returns @{ Map (Clusters, Nodes, Edges, Stats, Hierarchy - a row per
        management group: name, parent, depth, subscriptions (direct and
        below), policy and role assignments at it); Title; Facts }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string[]] $ManagementGroupId = @(),

        [string[]] $SubscriptionId = @(),

        [string] $Title
    )

    Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
    $scope = Resolve-AACScope -SubscriptionId $SubscriptionId -ManagementGroupId $ManagementGroupId
    Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"
    Update-AACProgress -Id 'hierarchy' -Indeterminate -Description 'Reading the management groups and what is assigned at each'
    $read = Invoke-AACGraphBatch -Query ([ordered]@{
            groups    = @{ Tenant = $true; Query = "resourcecontainers | where type =~ 'microsoft.management/managementgroups' | project name = tolower(name), displayName = tostring(properties.displayName), parent = tolower(tostring(properties.details.parent.name))" }
            policies  = @{ Tenant = $true; Query = "policyresources | where type =~ 'microsoft.authorization/policyassignments' | summarize used = count() by scope = tolower(tostring(properties.scope))" }
            roles     = @{ Tenant = $true; Query = "authorizationresources | where type =~ 'microsoft.authorization/roleassignments' | extend scope = tolower(tostring(properties.scope)) | where scope startswith '/providers/microsoft.management/managementgroups/' or scope matches regex '^/subscriptions/[^/]+$' or scope == '/' | summarize used = count() by scope" }
            resources = "resources | summarize used = count() by subscriptionId = tolower(subscriptionId)"
        }) -SubscriptionId $scope.GraphScope -AllowFailure @('policies', 'roles', 'resources')
    $groupRows = @($read.Rows['groups'] | Where-Object { $_ })
    Update-AACProgress -Id 'hierarchy' -Complete -Description ('Read {0:N0} management group(s)' -f $groupRows.Count)

    $count = @{}
    foreach ($key in 'policies', 'roles') { $count[$key] = @{}; foreach ($row in @($read.Rows[$key] | Where-Object { $_ })) { $count[$key][[string]$row['scope']] = [int]$row['used'] } }
    $resourceCount = @{}; foreach ($row in @($read.Rows['resources'] | Where-Object { $_ })) { $resourceCount[[string]$row['subscriptionId']] = [int]$row['used'] }
    $at = { param([string] $Kind, [string] $Scope) if ($count[$Kind].Contains($Scope)) { $count[$Kind][$Scope] } else { 0 } }

    # The groups: names, parents; the root is the one without a parent.
    $groups = [ordered]@{}
    foreach ($row in $groupRows) { $groups[[string]$row['name']] = @{ Name = [string]$row['name']; Display = $(if ($row['displayName']) { [string]$row['displayName'] } else { [string]$row['name'] }); Parent = [string]$row['parent']; Subs = 0; Below = 0 } }
    $root = @($groups.Values | Where-Object { -not $_.Parent -or -not $groups.Contains($_.Parent) }) | Select-Object -First 1
    $scoped = [bool](@($ManagementGroupId | Where-Object { $_ }).Count -or @($SubscriptionId | Where-Object { $_ }).Count)
    $wanted = @{}
    $subOf = @{}
    foreach ($s in $scope.Subscriptions) {
        $id = ([string]$s['subscriptionId']).ToLowerInvariant()
        $chain = @(@($s['chain']) | Where-Object { $_ -is [System.Collections.IDictionary] } | ForEach-Object { ([string]$_['name']).ToLowerInvariant() })
        $subOf[$id] = if ($chain.Count) { $chain[0] } else { '' }
        foreach ($g in $chain) { $wanted[$g] = $true; if ($groups.Contains($g)) { $groups[$g].Below++ } }
        if ($chain.Count -and $groups.Contains($chain[0])) { $groups[$chain[0]].Subs++ }
    }
    $keep = { param([string] $Name) (-not $scoped) -or $wanted.Contains($Name) }
    $depthOf = { param([string] $Name) $d = 0; $g = $Name; while ($groups.Contains($g) -and $groups[$g].Parent -and $groups.Contains($groups[$g].Parent) -and $d -lt 20) { $d++; $g = $groups[$g].Parent }; $d }
    $clusterId = { param([string] $Name) if ($root -and $Name -eq $root.Name) { 'tenant' } else { "/providers/microsoft.management/managementgroups/$Name" } }

    $clusters = [System.Collections.Generic.List[object]]::new()
    $hierarchy = [System.Collections.Generic.List[object]]::new()
    foreach ($g in @($groups.Values | Sort-Object { & $depthOf $_.Name }, { $_.Display })) {
        if (-not (& $keep $g.Name)) { continue }
        $scopeId = "/providers/microsoft.management/managementgroups/$($g.Name)"
        $policies = & $at 'policies' $scopeId
        $roles = & $at 'roles' $scopeId
        if ($root -and $g.Name -eq $root.Name) { $roles += & $at 'roles' '/' }
        $detail = @(@($(if ($g.Below) { "$($g.Below) subscription(s)" } else { 'no subscriptions' }); $(if ($policies) { "$policies policy assignment(s)" }); $(if ($roles) { "$roles role assignment(s)" })) | Where-Object { $_ })
        $isRoot = $root -and $g.Name -eq $root.Name
        $clusters.Add(@{ id = (& $clusterId $g.Name); kind = $(if ($isRoot) { 'tenant' } else { 'managementgroup' }); parent = $(if ($isRoot -or -not $g.Parent) { '' } else { & $clusterId $g.Parent }); name = $g.Display; detail = @($g.Name, ($detail -join ' · ')); icon = 'resource'; external = $false; badges = @(); chips = @() })
        $row = [pscustomobject][ordered]@{
            ManagementGroup   = $g.Display
            Name              = $g.Name
            Parent            = $(if ($g.Parent -and $groups.Contains($g.Parent)) { $groups[$g.Parent].Display } else { '' })
            Depth             = & $depthOf $g.Name
            Subscriptions     = $g.Subs
            SubscriptionsBelow = $g.Below
            PolicyAssignments = $policies
            RoleAssignments   = $roles
            Id                = $scopeId
        }
        $row.PSObject.TypeNames.Insert(0, 'AAC.ManagementGroup')
        $hierarchy.Add($row)
    }

    $nodes = [System.Collections.Generic.List[object]]::new()
    foreach ($s in @($scope.Subscriptions | Sort-Object { [string]$_['name'] })) {
        $id = ([string]$s['subscriptionId']).ToLowerInvariant()
        $sid = "/subscriptions/$id"
        $parentGroup = $subOf[$id]
        $facts = @(@($(& $at 'policies' $sid) | Where-Object { $_ } | ForEach-Object { "$_ policy assignment(s)" }) + @($(& $at 'roles' $sid) | Where-Object { $_ } | ForEach-Object { "$_ role assignment(s)" }) + @($(if ($resourceCount.Contains($id)) { "$($resourceCount[$id]) resource(s)" })) | Where-Object { $_ })
        $nodes.Add(@{
                id = $sid; parent = $(if ($parentGroup -and $groups.Contains($parentGroup)) { & $clusterId $parentGroup } else { '' }); name = [string]$s['name']; type = 'microsoft.resources/subscriptions'; typeLabel = 'Subscription'; icon = 'subscription'; kind = 'resource'
                location = ''; resourceGroup = ''; subscriptionId = $id; subscription = [string]$s['name']; sku = ''; facts = $facts; tags = $null; orphan = ''; external = $false
                chips = @(); chip = ''; appliedTo = @(); risk = ''; rules = @(); routes = @(); propagation = ''
            })
    }

    $policyTotal = 0; foreach ($h in $hierarchy) { $policyTotal += $h.PolicyAssignments }
    $map = @{
        Clusters  = @($clusters)
        Nodes     = @($nodes)
        Edges     = @()
        Hierarchy = @($hierarchy)
        Stats     = @{ ManagementGroups = $hierarchy.Count; Subscriptions = $nodes.Count; Depth = $(if ($hierarchy.Count) { ($hierarchy | Measure-Object -Property Depth -Maximum).Maximum } else { 0 }); PolicyAssignments = $policyTotal }
    }
    $facts = @("$($hierarchy.Count) management group(s)", "$($nodes.Count) subscription(s)", "$($map.Stats.Depth) level(s) below the root", "drawn $((Get-Date).ToString('d MMM yyyy HH:mm'))")
    @{ Map = $map; Title = $(if ($Title) { $Title } else { "Management groups: $($scope.Label)" }); Facts = $facts }
}
