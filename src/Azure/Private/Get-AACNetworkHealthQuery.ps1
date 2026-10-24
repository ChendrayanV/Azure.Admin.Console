function Get-AACNetworkHealthQuery {
    <#
    .SYNOPSIS
        The Resource Graph batch Get-AACNetworkHealth reads: ExpressRoute
        circuits, gateways (VNet and Virtual WAN, ExpressRoute and VPN),
        connections, Azure Firewalls and NAT gateways.
    .DESCRIPTION
        One query per kind asked for (-Component), each projecting id, name,
        type, location, resource group, subscription, sku, zones and
        properties. -ResourceGroupName narrows them. (Resource Health is read
        per resource by Get-AACNetworkHealth: Resource Graph's
        healthresources doesn't cover network resources.)
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [ValidateSet('ExpressRoute', 'Gateway', 'Vpn', 'Firewall', 'NatGateway')]
        [string[]] $Component = @('ExpressRoute', 'Gateway', 'Vpn', 'Firewall', 'NatGateway'),

        [string[]] $ResourceGroupName
    )

    $quote = { param([string] $Text) ConvertTo-AACKqlLiteral -Text $Text }
    $groups = @($ResourceGroupName | Where-Object { $_ })
    $in = if ($groups.Count) { " | where resourceGroup in~ ($((@($groups | ForEach-Object { & $quote $_ })) -join ', '))" } else { '' }
    $columns = '| project id = tolower(id), name, type = tolower(type), location, resourceGroup, subscriptionId = tolower(subscriptionId), sku, zones, properties'
    $of = { param([string[]] $Types, [string] $Where) "resources | where type in~ ($((@($Types | ForEach-Object { & $quote $_ })) -join ', '))$(if ($Where) { " | where $Where" })$in $columns" }
    $queries = [ordered]@{}
    if ('ExpressRoute' -in $Component) { $queries['circuits'] = & $of @('microsoft.network/expressroutecircuits') }
    if ('Gateway' -in $Component -or 'Vpn' -in $Component) {
        $queries['gateways'] = & $of @('microsoft.network/virtualnetworkgateways', 'microsoft.network/expressroutegateways', 'microsoft.network/vpngateways', 'microsoft.network/p2svpngateways')
        $queries['connections'] = & $of @('microsoft.network/connections')
    }
    if ('Firewall' -in $Component) { $queries['firewalls'] = & $of @('microsoft.network/azurefirewalls') }
    if ('NatGateway' -in $Component) { $queries['natgateways'] = & $of @('microsoft.network/natgateways') }
    $queries
}
