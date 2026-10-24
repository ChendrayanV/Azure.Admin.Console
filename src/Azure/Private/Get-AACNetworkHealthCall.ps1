function Get-AACNetworkHealthCall {
    <#
    .SYNOPSIS
        The metric calls Get-AACNetworkHealth makes for each network resource
        (Read-AACMetric's -Call).
    .DESCRIPTION
          ExpressRoute circuit   bgp     BgpAvailability, ArpAvailability by
                                         PeeringType and Peer
                                 bits    BitsIn/OutPerSecond by DeviceRole
                                         (primary, secondary link)
                                 qos     QosDropBitsIn/OutPerSecond
          ExpressRoute gateway   perf    CPU and packets per second
          (VNet or Virtual WAN)  routes  routes advertised to and learned
                                         from the peer
          VPN gateway            bw      AverageBandwidth (bytes/s)
          (VNet or Virtual WAN)  tunnels TunnelAverageBandwidth and packet
                                         drops by ConnectionName
                                 bgp     BgpPeerStatus by BgpPeerAddress (with BGP)
                                 p2s     P2SConnectionCount (with point-to-site)
          Point-to-site gateway  p2s     P2SConnectionCount
          Azure Firewall         fw      FirewallHealth, SNATPortUtilization,
                                         Throughput
                                 latency FirewallLatencyPng
          NAT gateway            nat     DatapathAvailability,
                                         SNATConnectionCount, PacketDropCount
        Each call stands alone, so a metric one resource lacks fails only
        that call.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyCollection()]
        [object[]] $Resource = @()
    )

    $call = { param($Id, $Key, [string[]] $Metric, [string[]] $Aggregation, [string] $Filter = '') @{ Id = $Id; Key = $Key; Metric = $Metric; Aggregation = $Aggregation; Filter = $Filter } }
    foreach ($r in $Resource) {
        $id = [string]$r['id']
        $p = $r['properties']
        $type = [string]$r['type']
        $gatewayType = if ($p -is [System.Collections.IDictionary] -and $p.Contains('gatewayType')) { [string]$p['gatewayType'] } else { '' }
        switch ($type) {
            'microsoft.network/expressroutecircuits' {
                & $call $id 'bgp' @('BgpAvailability', 'ArpAvailability') @('Average', 'Minimum') "PeeringType eq '*' and Peer eq '*'"
                & $call $id 'bits' @('BitsInPerSecond', 'BitsOutPerSecond') @('Average', 'Maximum') "DeviceRole eq '*'"
                & $call $id 'qos' @('QosDropBitsInPerSecond', 'QosDropBitsOutPerSecond') @('Average', 'Maximum')
            }
            { $_ -eq 'microsoft.network/expressroutegateways' -or ($_ -eq 'microsoft.network/virtualnetworkgateways' -and $gatewayType -eq 'ExpressRoute') } {
                & $call $id 'perf' @('ExpressRouteGatewayCpuUtilization', 'ExpressRouteGatewayPacketsPerSecond') @('Average', 'Maximum')
                & $call $id 'routes' @('ExpressRouteGatewayCountOfRoutesAdvertisedToPeer', 'ExpressRouteGatewayCountOfRoutesLearnedFromPeer') @('Maximum')
            }
            { $_ -eq 'microsoft.network/vpngateways' -or ($_ -eq 'microsoft.network/virtualnetworkgateways' -and $gatewayType -eq 'Vpn') } {
                & $call $id 'bw' @('AverageBandwidth') @('Average', 'Maximum')
                & $call $id 'tunnels' @('TunnelAverageBandwidth', 'TunnelEgressPacketDropCount', 'TunnelIngressPacketDropCount') @('Average', 'Maximum', 'Total') "ConnectionName eq '*'"
                $bgp = $_ -eq 'microsoft.network/vpngateways' -or ($p['enableBgp'] -eq $true)
                if ($bgp) { & $call $id 'bgp' @('BgpPeerStatus') @('Average', 'Minimum') "BgpPeerAddress eq '*'" }
                if ($_ -eq 'microsoft.network/virtualnetworkgateways' -and $p['vpnClientConfiguration']) { & $call $id 'p2s' @('P2SConnectionCount') @('Maximum') }
            }
            'microsoft.network/p2svpngateways' { & $call $id 'p2s' @('P2SConnectionCount') @('Maximum') }
            'microsoft.network/azurefirewalls' {
                & $call $id 'fw' @('FirewallHealth', 'SNATPortUtilization', 'Throughput') @('Average', 'Maximum', 'Minimum')
                & $call $id 'latency' @('FirewallLatencyPng') @('Average', 'Maximum')
            }
            'microsoft.network/natgateways' { & $call $id 'nat' @('DatapathAvailability', 'SNATConnectionCount', 'PacketDropCount') @('Average', 'Maximum', 'Minimum', 'Total') }
        }
    }
}
