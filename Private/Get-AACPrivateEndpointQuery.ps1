function Get-AACPrivateEndpointQuery {
    <#
    .SYNOPSIS
        The Azure Resource Graph queries behind Get-AACPrivateEndpoint: the
        private endpoints and their connections, the private DNS zones and
        their virtual network links, the virtual networks (DNS servers and
        peerings), and every resource that takes private endpoint
        connections (does the target exist, is it still public?).
    .DESCRIPTION
          endpoints  each private endpoint: subnet, state, connections (auto
                     and manual), custom DNS configs, NICs, IP configurations
          zones      private DNS zones: record sets and links
          links      each zone's virtual network links
          vnets      virtual networks: DNS servers and peerings
          targets    resources with private endpoint connections: their
                     type, public network access and default network action
        -ResourceGroupName narrows the endpoints only: their zones, networks
        and targets can be anywhere.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [string[]] $ResourceGroupName
    )

    $quote = { param([string] $Text) "'" + ($Text -replace "'", "\'") + "'" }
    $groups = @($ResourceGroupName | Where-Object { $_ })
    $in = if ($groups.Count) { " | where resourceGroup in~ ($((@($groups | ForEach-Object { & $quote $_ })) -join ', '))" } else { '' }

    [ordered]@{
        endpoints = "resources | where type =~ 'microsoft.network/privateendpoints'$in | project id = tolower(id), name, resourceGroup, subscriptionId, location, subnet = tolower(tostring(properties.subnet.id)), state = tostring(properties.provisioningState), connections = properties.privateLinkServiceConnections, manual = properties.manualPrivateLinkServiceConnections, dns = properties.customDnsConfigs, nics = properties.networkInterfaces, ipConfigs = properties.ipConfigurations"
        zones     = "resources | where type =~ 'microsoft.network/privatednszones' | project id = tolower(id), name = tolower(name), resourceGroup, subscriptionId, records = toint(properties.numberOfRecordSets), links = toint(properties.numberOfVirtualNetworkLinks)"
        links     = "resources | where type =~ 'microsoft.network/privatednszones/virtualnetworklinks' | project id = tolower(id), zone = tostring(split(tolower(id), '/virtualnetworklinks/')[0]), vnet = tolower(tostring(properties.virtualNetwork.id)), registration = tobool(properties.registrationEnabled), linkState = tostring(properties.virtualNetworkLinkState)"
        vnets     = "resources | where type =~ 'microsoft.network/virtualnetworks' | project id = tolower(id), name, subscriptionId, dnsServers = properties.dhcpOptions.dnsServers, peerings = properties.virtualNetworkPeerings"
        targets   = "resources | where isnotnull(properties.privateEndpointConnections) | project id = tolower(id), name, type = tolower(type), subscriptionId, publicAccess = tostring(properties.publicNetworkAccess), defaultAction = coalesce(tostring(properties.networkAcls.defaultAction), tostring(properties.networkRuleSet.defaultAction))"
    }
}
