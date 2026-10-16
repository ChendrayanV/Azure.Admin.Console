<#
    Made-up Contoso hybrid network for NetworkHealth.Tests.ps1: Resource Graph
    rows, Resource Health and Azure Monitor metrics.

      er-london   ExpressRoute circuit, 1 Gbps, provisioned: BGP 100% on the
                  primary link, 99.5% on the secondary; the primary peaks at
                  900 Mbps (90%) and carries all the traffic; QoS drops
      er-idle     ExpressRoute circuit, not provisioned by the provider
      ergw-hub    ExpressRoute VNet gateway, Standard (not zone-redundant):
                  CPU 85%, 50,000 pps, 950 routes advertised (95%)
      vpngw-hub   VPN gateway VpnGw1, not active-active, BGP, point-to-site:
                  600 Mbps peak (92%), BGP peer 10.2.2.2 down, 100 P2S users
      conn-paris  IPsec, Connected, BGP, 15 packets dropped
      conn-berlin IPsec, NotConnected, static routing
      conn-er     ExpressRoute, Connected
      afw-hub     Azure Firewall Premium, zones 1-3: health down to 95%, SNAT
                  97%, 10 Gbps peak; Resource Health Degraded
      natgw-app   NAT gateway, 1 public IP, 60,000 SNAT connections (93%)
#>
function Get-AACContosoNetworkHealth {
    $sub = '11111111-1111-1111-1111-111111111111'
    $id = { param($Type, $Name) "/subscriptions/$sub/resourcegroups/rg-net/providers/microsoft.network/$Type/$Name" }
    $row = { param($Type, $Name, $Properties, $Sku = $null, $Zones = $null) @{ id = (& $id $Type $Name); name = $Name; type = "microsoft.network/$Type"; location = 'uksouth'; resourceGroup = 'rg-net'; subscriptionId = $sub; sku = $Sku; zones = $Zones; properties = $Properties } }
    $vpnId = & $id 'virtualnetworkgateways' 'vpngw-hub'
    $graph = @{
        circuits    = @(
            & $row 'expressroutecircuits' 'er-london' @{ serviceProviderProvisioningState = 'Provisioned'; circuitProvisioningState = 'Enabled'; serviceProviderProperties = @{ bandwidthInMbps = 1000; serviceProviderName = 'Equinix'; peeringLocation = 'London' }; peerings = @(@{ name = 'AzurePrivatePeering' }) } @{ tier = 'Standard'; family = 'MeteredData' }
            & $row 'expressroutecircuits' 'er-idle' @{ serviceProviderProvisioningState = 'NotProvisioned'; circuitProvisioningState = 'Enabled'; serviceProviderProperties = @{ bandwidthInMbps = 200 }; peerings = @() } @{ tier = 'Standard'; family = 'MeteredData' }
        )
        gateways    = @(
            & $row 'virtualnetworkgateways' 'ergw-hub' @{ gatewayType = 'ExpressRoute'; sku = @{ name = 'Standard' }; provisioningState = 'Succeeded' }
            & $row 'virtualnetworkgateways' 'vpngw-hub' @{ gatewayType = 'Vpn'; sku = @{ name = 'VpnGw1' }; vpnGatewayGeneration = 'Generation1'; activeActive = $false; enableBgp = $true; vpnClientConfiguration = @{ vpnClientProtocols = @('OpenVPN') }; provisioningState = 'Succeeded' }
        )
        connections = @(
            & $row 'connections' 'conn-paris' @{ connectionType = 'IPsec'; connectionStatus = 'Connected'; enableBgp = $true; virtualNetworkGateway1 = @{ id = $vpnId } }
            & $row 'connections' 'conn-berlin' @{ connectionType = 'IPsec'; connectionStatus = 'NotConnected'; enableBgp = $false; virtualNetworkGateway1 = @{ id = $vpnId } }
            & $row 'connections' 'conn-er' @{ connectionType = 'ExpressRoute'; connectionStatus = 'Connected'; virtualNetworkGateway1 = @{ id = (& $id 'virtualnetworkgateways' 'ergw-hub') } }
        )
        firewalls   = @(& $row 'azurefirewalls' 'afw-hub' @{ sku = @{ name = 'AZFW_VNet'; tier = 'Premium' }; ipConfigurations = @(@{ name = 'ip1' }); provisioningState = 'Succeeded' } $null @('1', '2', '3'))
        natgateways = @(& $row 'natgateways' 'natgw-app' @{ publicIpAddresses = @(@{ id = 'pip-nat' }); subnets = @(@{ id = 'snet-app' }); provisioningState = 'Succeeded' } @{ name = 'Standard' })
        health      = @(
            @{ target = (& $id 'expressroutecircuits' 'er-london'); state = 'Available'; reason = ''; summary = 'There aren''t any known Azure platform problems.' }
            @{ target = (& $id 'azurefirewalls' 'afw-hub'); state = 'Degraded'; reason = 'Unplanned'; summary = 'The firewall is experiencing high SNAT utilization.'; since = '2026-10-15T18:00:00Z' }
        )
    }
    $point = { param([hashtable] $Values) $Values }
    $series = { param($Name, [hashtable] $Dims, [object[]] $Points) @{ name = @{ value = $Name }; timeseries = @(@{ metadatavalues = @(foreach ($k in $Dims.Keys) { @{ name = @{ value = $k }; value = $Dims[$k] } }); data = $Points }) } }
    $london = & $id 'expressroutecircuits' 'er-london'
    $erg = & $id 'virtualnetworkgateways' 'ergw-hub'
    $fw = & $id 'azurefirewalls' 'afw-hub'
    $nat = & $id 'natgateways' 'natgw-app'
    $metrics = @{
        "$london|bgp"     = @(
            & $series 'BgpAvailability' @{ PeeringType = 'Private'; Peer = 'Primary-IPv4' } @(@{ average = 100 }, @{ average = 100 })
            & $series 'BgpAvailability' @{ PeeringType = 'Private'; Peer = 'Secondary-IPv4' } @(@{ timeStamp = '2026-10-15T09:00:00Z'; average = 99 }, @{ timeStamp = '2026-10-15T10:00:00Z'; average = 100 })
            & $series 'ArpAvailability' @{ PeeringType = 'Private'; Peer = 'Primary-IPv4' } @(@{ average = 100 }))
        "$london|bits"    = @(
            & $series 'BitsInPerSecond' @{ DeviceRole = 'Primary' } @(@{ timeStamp = '2026-10-15T14:00:00Z'; average = 500e6; maximum = 900e6 }, @{ timeStamp = '2026-10-15T15:00:00Z'; average = 500e6; maximum = 700e6 })
            & $series 'BitsInPerSecond' @{ DeviceRole = 'Secondary' } @(@{ average = 0; maximum = 0 }, @{ average = 0; maximum = 0 })
            & $series 'BitsOutPerSecond' @{ DeviceRole = 'Primary' } @(@{ average = 100e6; maximum = 200e6 }))
        "$london|qos"     = @(& $series 'QosDropBitsInPerSecond' @{} @(@{ average = 10; maximum = 1000 }))
        "$erg|perf"       = @((& $series 'ExpressRouteGatewayCpuUtilization' @{} @(@{ average = 40; maximum = 85 })), (& $series 'ExpressRouteGatewayPacketsPerSecond' @{} @(@{ average = 20000; maximum = 50000 })))
        "$erg|routes"     = @((& $series 'ExpressRouteGatewayCountOfRoutesAdvertisedToPeer' @{} @(@{ maximum = 950 })), (& $series 'ExpressRouteGatewayCountOfRoutesLearnedFromPeer' @{} @(@{ maximum = 1000 })))
        "$vpnId|bw"       = @(& $series 'AverageBandwidth' @{} @(@{ average = 20e6; maximum = 75e6 }))
        "$vpnId|tunnels"  = @(
            & $series 'TunnelAverageBandwidth' @{ ConnectionName = 'conn-paris' } @(@{ average = 5e6; maximum = 10e6 })
            & $series 'TunnelEgressPacketDropCount' @{ ConnectionName = 'conn-paris' } @(@{ total = 10 }, @{ total = 5 })
            & $series 'TunnelEgressPacketDropCount' @{ ConnectionName = 'conn-berlin' } @(@{ total = 0 }))
        "$vpnId|bgp"      = @((& $series 'BgpPeerStatus' @{ BgpPeerAddress = '10.1.1.1' } @(@{ average = 1 })), (& $series 'BgpPeerStatus' @{ BgpPeerAddress = '10.2.2.2' } @(@{ timeStamp = '2026-10-15T08:00:00Z'; average = 0 }, @{ timeStamp = '2026-10-16T07:00:00Z'; average = 0 })))
        "$vpnId|p2s"      = @(& $series 'P2SConnectionCount' @{} @(@{ maximum = 100 }))
        "$fw|fw"          = @((& $series 'FirewallHealth' @{} @(@{ average = 98; minimum = 95 })), (& $series 'SNATPortUtilization' @{} @(@{ timeStamp = '2026-10-15T18:30:00Z'; average = 60; maximum = 97 })), (& $series 'Throughput' @{} @(@{ average = 2e9; maximum = 10e9 })))
        "$fw|latency"     = @(& $series 'FirewallLatencyPng' @{} @(@{ average = 5; maximum = 9 }))
        "$nat|nat"        = @((& $series 'DatapathAvailability' @{} @(@{ average = 100 })), (& $series 'PacketDropCount' @{} @(@{ total = 0 })), (& $series 'SNATConnectionCount' @{} @(@{ maximum = 60000 })))
    }
    @{
        Graph   = $graph
        Metrics = $metrics
        Scope   = @{ Subscriptions = @(@{ subscriptionId = $sub; name = 'Contoso Connectivity' }); Ids = @($sub); GraphScope = @(); Label = 'all 1 subscription(s)'; Names = @{ $sub = 'Contoso Connectivity' } }
    }
}
