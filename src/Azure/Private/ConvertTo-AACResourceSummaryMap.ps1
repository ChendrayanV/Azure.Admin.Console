function ConvertTo-AACResourceSummaryMap {
    <#
    .SYNOPSIS
        Turns every resource into the resource map's model as ARI's
        "resources" view draws it: each subscription a box, holding a node
        per resource type with how many there are - for
        Invoke-AACAssessment's <name>-Resources.html.
    .DESCRIPTION
        A node per subscription and resource type: the type's Azure icon and
        name, the count, and the locations and resource groups they're in.
        It stays readable at any tenant size, where a node per resource
        wouldn't (-DiagramFullEnvironment's network diagram draws those).

        -Resource: rows with type and subscriptionId (and location,
        resourceGroup); -IconType: type -> icon key; -IconLabel: icon key ->
        product name. Returns @{ Clusters; Nodes; Edges; Stats } as
        ConvertTo-AACResourceMap does.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyCollection()] [object[]] $Resource = @(),
        [hashtable] $SubscriptionName = @{},
        [hashtable] $IconType = @{},
        [hashtable] $IconLabel = @{}
    )

    $value = { param($Row, [string] $Key) if ($Row -is [System.Collections.IDictionary]) { if ($Row.Contains($Key)) { $Row[$Key] } } elseif ($null -ne $Row) { Get-AACPropertyValue -InputObject $Row -Name $Key } }
    $clusters = [System.Collections.Generic.List[hashtable]]::new()
    $nodes = [System.Collections.Generic.List[hashtable]]::new()
    $bySubscription = @($Resource | Group-Object { ([string](& $value $_ 'subscriptionId')).ToLowerInvariant() } | Sort-Object { if ($SubscriptionName.Contains($_.Name)) { $SubscriptionName[$_.Name] } else { $_.Name } })
    foreach ($subscription in $bySubscription) {
        $sub = $subscription.Name
        $subName = if ($SubscriptionName.Contains($sub)) { $SubscriptionName[$sub] } else { $sub }
        $types = @($subscription.Group | Group-Object { ([string](& $value $_ 'type')).ToLowerInvariant() } | Sort-Object Count -Descending)
        $clusters.Add(@{ id = "/subscriptions/$sub"; kind = 'subscription'; parent = ''; name = $subName; detail = @($sub, "$($subscription.Count) resource(s)", "$($types.Count) type(s)"); icon = 'subscription'; external = $false; badges = @(); chips = @() })
        foreach ($type in $types) {
            $icon = if ($IconType.Contains($type.Name)) { $IconType[$type.Name] } else { 'resource' }
            $label = if ($icon -ne 'resource' -and $IconLabel.Contains($icon) -and $IconLabel[$icon]) { $IconLabel[$icon] } else { ($type.Name -split '/')[-1] }
            $locations = @($type.Group | ForEach-Object { [string](& $value $_ 'location') } | Where-Object { $_ } | Sort-Object -Unique)
            $groups = @($type.Group | ForEach-Object { [string](& $value $_ 'resourceGroup') } | Where-Object { $_ } | Sort-Object -Unique)
            $nodes.Add(@{
                    id = "/subscriptions/$sub/types/$($type.Name)"; parent = "/subscriptions/$sub"; name = "$label ($($type.Count))"; type = $type.Name; typeLabel = $label; icon = $icon; kind = ''
                    location = ($locations -join ', '); resourceGroup = ''; subscriptionId = $sub; subscription = $subName; sku = ''
                    facts = @("$($type.Count) resource(s)", "$($groups.Count) resource group(s)", $(if ($locations.Count -le 4) { $locations -join ', ' } else { "$($locations.Count) locations" }))
                    tags = $null; orphan = ''; external = $false; chips = @(); chip = ''; appliedTo = @(); risk = ''; rules = @(); routes = @(); propagation = ''
                })
        }
    }
    @{
        Clusters = $clusters.ToArray()
        Nodes    = $nodes.ToArray()
        Edges    = @()
        Stats    = @{ Subscriptions = $clusters.Count; Types = $nodes.Count; Resources = @($Resource).Count; Connections = 0 }
    }
}
