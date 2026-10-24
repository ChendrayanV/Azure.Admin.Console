function ConvertTo-AACOrganizationMap {
    <#
    .SYNOPSIS
        Turns the tenant's organization - management groups, subscriptions
        and resource groups - into the resource map's model (boxes and
        nodes), for Invoke-AACAssessment's organization diagram.
    .DESCRIPTION
        Management groups are nested boxes; a subscription is a box in its
        management group, with its resource groups in it as nodes (their
        resource counts and location as details; an empty one is flagged).
        A subscription with no resource groups, or - past -MaxGroups
        resource groups in all - every subscription, is drawn as a node
        instead, so a large tenant's diagram stays readable. A management
        group with nothing in it is a node too.

        Inputs are Invoke-AACAssessment's rows: -ManagementGroup (name,
        displayName, parent), -Subscription (subscriptionId, name, state,
        chain), -ResourceGroup (id, name, subscriptionId, location) and
        -ResourceCount ('subscription|group' -> resources). Returns
        @{ Clusters; Nodes; Edges; Stats } as ConvertTo-AACResourceMap does.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyCollection()] [object[]] $ManagementGroup = @(),
        [AllowEmptyCollection()] [object[]] $Subscription = @(),
        [AllowEmptyCollection()] [object[]] $ResourceGroup = @(),
        [hashtable] $ResourceCount = @{},
        [int] $MaxGroups = 1500
    )

    $value = { param($Row, [string] $Key) if ($Row -is [System.Collections.IDictionary]) { if ($Row.Contains($Key)) { $Row[$Key] } } elseif ($null -ne $Row) { Get-AACPropertyValue -InputObject $Row -Name $Key } }
    $lower = { param($Text) ([string]$Text).ToLowerInvariant() }
    $mgId = { param([string] $Name) "/providers/Microsoft.Management/managementGroups/$Name" }
    $clusters = [ordered]@{}
    $nodes = [ordered]@{}
    $node = {
        param([string] $Id, [string] $Parent, [string] $Name, [string] $Type, [string] $TypeLabel, [string] $Icon, [string[]] $Facts, [string] $Flag, [string] $SubscriptionId, [string] $SubscriptionName, [string] $Location)
        $nodes[$Id] = @{
            id = $Id; parent = $Parent; name = $Name; type = $Type; typeLabel = $TypeLabel; icon = $Icon; kind = ''; location = $Location; resourceGroup = $(if ($Type -eq 'microsoft.resources/resourcegroups') { $Name } else { '' })
            subscriptionId = $SubscriptionId; subscription = $SubscriptionName; sku = ''; facts = @($Facts | Where-Object { $_ }); tags = $null; orphan = $Flag; external = $false
            chips = @(); chip = ''; appliedTo = @(); risk = ''; rules = @(); routes = @(); propagation = ''
        }
    }
    $cluster = {
        param([string] $Id, [string] $Kind, [string] $Parent, [string] $Name, [string[]] $Detail, [string] $Icon)
        $clusters[$Id] = @{ id = $Id; kind = $Kind; parent = $Parent; name = $Name; detail = @($Detail | Where-Object { $_ }); icon = $Icon; external = $false; badges = @(); chips = @() }
    }

    $known = @{}
    foreach ($row in $ManagementGroup) { $known[(& $lower (& $value $row 'name'))] = $row }
    $groupsOf = @{}
    foreach ($row in $ResourceGroup) {
        $sub = & $lower (& $value $row 'subscriptionId')
        if (-not $groupsOf.Contains($sub)) { $groupsOf[$sub] = [System.Collections.Generic.List[object]]::new() }
        $groupsOf[$sub].Add($row)
    }
    $drawGroups = @($ResourceGroup).Count -le $MaxGroups

    # Which management groups hold something (a subscription, or a group that does).
    $occupied = [System.Collections.Generic.HashSet[string]]::new()
    $parentOf = { param([string] $Name) $row = $known[(& $lower $Name)]; if ($row) { [string](& $value $row 'parent') } else { '' } }
    $subscriptionParent = @{}
    foreach ($row in $Subscription) {
        $chain = @(& $value $row 'chain' | Where-Object { $_ })
        $parent = if ($chain.Count) { [string](& $value $chain[0] 'name') } else { '' }
        $subscriptionParent[(& $lower (& $value $row 'subscriptionId'))] = $parent
        $walk = $parent
        $guard = 0
        while ($walk -and $known.Contains((& $lower $walk)) -and $guard -lt 20) { [void]$occupied.Add((& $lower $walk)); $walk = & $parentOf $walk; $guard++ }
    }
    foreach ($row in $ManagementGroup) {
        $name = [string](& $value $row 'name')
        $parent = [string](& $value $row 'parent')
        $parentId = if ($parent -and $known.Contains((& $lower $parent))) { & $mgId $parent } else { '' }
        $label = [string]$(if (& $value $row 'displayName') { & $value $row 'displayName' } else { $name })
        if ($occupied.Contains((& $lower $name))) { & $cluster (& $mgId $name) 'managementgroup' $parentId $label @($name) 'resource' }
        else { & $node (& $mgId $name) $parentId $label 'microsoft.management/managementgroups' 'Management group' 'resource' @($name, 'no subscriptions') '' '' '' '' }
    }
    foreach ($row in $Subscription) {
        $id = [string](& $value $row 'subscriptionId')
        $key = & $lower $id
        $parent = $subscriptionParent[$key]
        $parentId = if ($parent -and $known.Contains((& $lower $parent))) { & $mgId $parent } else { '' }
        $name = [string](& $value $row 'name')
        $groups = @(if ($groupsOf.Contains($key)) { $groupsOf[$key] })
        $resources = 0
        foreach ($group in $groups) { $count = $ResourceCount["$key|$(& $lower (& $value $group 'name'))"]; if ($count) { $resources += [int]$count } }
        $facts = @($id, [string](& $value $row 'state'), "$($groups.Count) resource group(s)", "$resources resource(s)")
        if ($drawGroups -and $groups.Count) {
            & $cluster "/subscriptions/$id" 'subscription' $parentId $name $facts 'subscription'
            foreach ($group in $groups | Sort-Object { [string](& $value $_ 'name') }) {
                $groupName = [string](& $value $group 'name')
                $count = [int]$ResourceCount["$key|$(& $lower $groupName)"]
                & $node ([string](& $value $group 'id')) "/subscriptions/$id" $groupName 'microsoft.resources/resourcegroups' 'Resource group' 'resourcegroup' @("$count resource(s)", [string](& $value $group 'location')) $(if (-not $count) { 'an empty resource group' } else { '' }) $id $name ([string](& $value $group 'location'))
            }
        }
        else {
            & $node "/subscriptions/$id" $parentId $name 'microsoft.resources/subscriptions' 'Subscription' 'subscription' $facts '' $id $name ''
        }
    }

    $nodeList = @($nodes.Values)
    @{
        Clusters = @($clusters.Values)
        Nodes    = $nodeList
        Edges    = @()
        Stats    = @{
            ManagementGroups = @($ManagementGroup).Count
            Subscriptions    = @($Subscription).Count
            Groups           = @($ResourceGroup).Count
            GroupsDrawn      = $drawGroups
            Resources        = $nodeList.Count
            Connections      = 0
        }
    }
}
