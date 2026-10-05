function Write-AACVirtualNetworkHtml {
    <#
    .SYNOPSIS
        Writes the virtual network assessment
        (ConvertTo-AACVirtualNetworkAssessment) as an interactive HTML report.
    .DESCRIPTION
        Tiles (networks, subnets, IPs available, subnets 80% used or more,
        peering problems, findings by severity - each filtering its table),
        charts (findings by severity and by category, the fullest subnets,
        networks with the most findings), and tables - each collapsible,
        searchable, filterable, groupable and downloadable as CSV:
          Virtual networks   metadata, role, address space, IPs, DNS, DDoS,
                             encryption, flow logs, gateways, firewalls,
                             Bastion, overlaps, findings
          Subnets            capacity, purpose, NSG, routes, outbound path,
                             endpoints, delegations, NICs, flow logs
          Peerings           state, sync, remote network, flags
          Free ranges        the CIDR blocks a new subnet can take
          Findings           severity, category, where, what to do
          Private endpoints  target, group, connection, private DNS zone
          ASGs               members and the NSG rules naming them
          NSG rules          the rules of the NSGs on these networks
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Assessment,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Title,

        [System.Collections.IDictionary] $Detail
    )

    $stats = $Assessment.Stats
    $severityTones = @{ High = 'bad'; Medium = 'warn'; Low = 'info'; Info = 'neutral' }
    $yesNo = { param($Value) if ($null -eq $Value) { '' } elseif ($Value) { 'Yes' } else { 'No' } }
    $nested = 'Subnets', 'Peerings', 'FreeRangeList', 'PrivateEndpointList', 'Findings'

    $tiles = @(
        @{ Value = '{0:N0}' -f $stats.VirtualNetworks; Label = 'virtual networks'; Tone = 'info'; Table = 'vnets' }
        @{ Value = '{0:N0}' -f $stats.Subnets; Label = 'subnets'; Tone = 'neutral'; Table = 'subnets' }
        @{ Value = '{0:N0}' -f $stats.AvailableIps; Label = "IPs available in subnets ($($stats.UsedPercent)% used)"; Tone = 'good'; Table = 'subnets' }
        @{ Value = '{0:N0}' -f $stats.UnallocatedIps; Label = 'IPs in no subnet'; Tone = 'neutral'; Table = 'free' }
        @{ Value = '{0:N0}' -f $stats.FullSubnets; Label = 'subnets 80% used or more'; Tone = $(if ($stats.FullSubnets) { 'warn' } else { 'good' }); Table = 'findings'; Filters = @{ Category = 'Capacity' } }
        @{ Value = '{0:N0}' -f $stats.PeeringProblems; Label = 'peering problems'; Tone = $(if ($stats.PeeringProblems) { 'bad' } else { 'good' }); Table = 'peerings' }
        @{ Value = '{0:N0}' -f $stats.High; Label = 'high-severity findings'; Tone = $(if ($stats.High) { 'bad' } else { 'good' }); Table = 'findings'; Filters = @{ Severity = 'High' } }
        @{ Value = '{0:N0}' -f $stats.Medium; Label = 'medium-severity findings'; Tone = $(if ($stats.Medium) { 'warn' } else { 'good' }); Table = 'findings'; Filters = @{ Severity = 'Medium' } }
        @{ Value = '{0:N0}' -f $stats.Low; Label = 'low-severity findings'; Tone = 'info'; Table = 'findings'; Filters = @{ Severity = 'Low' } }
    )
    $bySeverity = @(foreach ($level in 'High', 'Medium', 'Low', 'Info') {
            $n = @($Assessment.Findings | Where-Object Severity -EQ $level).Count
            if ($n) { @{ Label = $level; Value = $n; Tone = $severityTones[$level] -replace 'neutral', ''; Filter = $level } }
        })
    $byCategory = @($Assessment.Findings | Group-Object -Property Category | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, Name | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } })
    $fullest = @($Assessment.Subnets | Where-Object { $null -ne $_.UsedPercent -and $_.Used -gt 0 } | Sort-Object -Property @{ Expression = 'UsedPercent'; Descending = $true }, Subnet | Select-AACFirst 15 | ForEach-Object {
            @{ Label = "$($_.VirtualNetwork)/$($_.Subnet)"; Value = $_.UsedPercent; Display = "$($_.UsedPercent)% ($($_.Used) of $($_.Usable))"; Tone = $(if ($_.UsedPercent -ge 95) { 'bad' } elseif ($_.UsedPercent -ge 80) { 'warn' } else { 'good' }); Filter = $_.Subnet }
        })
    $byRisk = @($Assessment.VirtualNetworks | Where-Object { $_.High + $_.Medium + $_.Low } | Sort-Object -Property @{ Expression = { $_.High * 1000 + $_.Medium * 10 + $_.Low }; Descending = $true } | Select-AACFirst 12 | ForEach-Object {
            @{ Label = $_.Name; Value = $_.High + $_.Medium + $_.Low; Display = "H$($_.High) M$($_.Medium) L$($_.Low)"; Tone = $(if ($_.High) { 'bad' } elseif ($_.Medium) { 'warn' } else { 'info' }); Filter = $_.Name }
        })
    $charts = @(
        @{ Title = 'Findings by severity'; Items = $bySeverity; Table = 'findings'; Column = 'Severity' }
        @{ Title = 'Findings by category'; Items = $byCategory; Table = 'findings'; Column = 'Category'; Tone = 'warn' }
        @{ Title = 'Subnets by IPs used (%)'; Items = $fullest; Table = 'subnets'; Column = 'Subnet' }
        @{ Title = 'Networks with the most findings'; Items = $byRisk; Table = 'findings'; Column = 'VirtualNetwork' }
    )

    $vnetRows = @($Assessment.VirtualNetworks | Select-Object -Property * -ExcludeProperty $nested)
    $peeringRows = @($Assessment.Peerings | Select-Object -Property *, @{ Name = 'GlobalText'; Expression = { & $yesNo $_.Global } }, @{ Name = 'Transit'; Expression = { if ($_.AllowGatewayTransit) { 'Offers' } elseif ($_.UseRemoteGateways) { 'Uses remote' } else { 'None' } } },
        @{ Name = 'Forwarded'; Expression = { & $yesNo $_.AllowForwardedTraffic } }, @{ Name = 'Access'; Expression = { & $yesNo $_.AllowVirtualNetworkAccess } }, @{ Name = 'Visible'; Expression = { & $yesNo $_.RemoteVisible } }, @{ Name = 'Reverse'; Expression = { & $yesNo $_.ReversePeering } })
    $nsgRules = @(if ($Assessment['Nsg']) { $Assessment['Nsg'].Rules | Where-Object { -not $_.IsDefault } })

    $tables = @(
        @{
            Id = 'vnets'; Title = 'Virtual networks'; Note = 'Most at risk first. Usable IPs leave out the 5 Azure keeps in every subnet; unallocated IPs are in no subnet.'; Noun = 'virtual networks'; File = 'virtual-networks'; Rows = $vnetRows; GroupBy = @('SubscriptionName', 'Location', 'Role')
            Columns = @(
                @{ Key = 'Name'; Label = 'Virtual network'; Type = 'resource'; IdKey = 'ResourceId' }
                @{ Key = 'Role'; Label = 'Role'; Type = 'badge'; Tones = @{ Hub = 'violet'; Spoke = 'info'; Peered = 'info'; Standalone = 'neutral' }; Facet = $true }
                @{ Key = 'High'; Label = 'High'; Type = 'number'; Sum = $true; Format = 'N0'; Tone = 'bad' }
                @{ Key = 'Medium'; Label = 'Medium'; Type = 'number'; Sum = $true; Format = 'N0'; Tone = 'warn' }
                @{ Key = 'Low'; Label = 'Low'; Type = 'number'; Sum = $true; Format = 'N0' }
                @{ Key = 'AddressSpace'; Label = 'Address space'; Type = 'wide' }
                @{ Key = 'TotalIps'; Label = 'IPs'; Type = 'number'; Sum = $true; Format = 'N0' }
                @{ Key = 'UnallocatedIps'; Label = 'Unallocated'; Type = 'number'; Sum = $true; Format = 'N0' }
                @{ Key = 'UsableIps'; Label = 'Usable'; Type = 'number'; Sum = $true; Format = 'N0' }
                @{ Key = 'UsedIps'; Label = 'Used'; Type = 'number'; Sum = $true; Format = 'N0' }
                @{ Key = 'AvailableIps'; Label = 'Available'; Type = 'number'; Sum = $true; Format = 'N0'; Tone = 'good' }
                @{ Key = 'UsedPercent'; Label = '% used'; Type = 'number' }
                @{ Key = 'SubnetCount'; Label = 'Subnets'; Type = 'number'; Sum = $true }
                @{ Key = 'FreeRanges'; Label = 'Largest free ranges'; Type = 'wide' }
                @{ Key = 'PeeringCount'; Label = 'Peerings'; Type = 'number' }
                @{ Key = 'PeeringsNotConnected'; Label = 'Not connected'; Type = 'number'; Tone = 'bad' }
                @{ Key = 'DnsServers'; Label = 'DNS servers' }
                @{ Key = 'PrivateDnsZones'; Label = 'Private DNS zones linked'; Type = 'wide' }
                @{ Key = 'DnsResolvers'; Label = 'DNS resolvers' }
                @{ Key = 'DdosProtection'; Label = 'DDoS'; Type = 'badge'; Tones = @{ 'Infrastructure only' = 'warn' }; Facet = $true }
                @{ Key = 'Encryption'; Label = 'Encryption'; Facet = $true }
                @{ Key = 'FlowLogs'; Label = 'Flow logs'; Type = 'badge'; Tones = @{ None = 'bad' }; Facet = $true }
                @{ Key = 'Gateways'; Label = 'Gateways'; Type = 'wide' }
                @{ Key = 'Firewalls'; Label = 'Firewalls' }
                @{ Key = 'Bastions'; Label = 'Bastion' }
                @{ Key = 'Nics'; Label = 'NICs'; Type = 'number'; Sum = $true }
                @{ Key = 'PrivateEndpoints'; Label = 'Private endpoints'; Type = 'number'; Sum = $true }
                @{ Key = 'PublicIps'; Label = 'Public IPs'; Type = 'number'; Sum = $true }
                @{ Key = 'Overlaps'; Label = 'Overlaps with'; Type = 'wide' }
                @{ Key = 'FlowTimeoutMinutes'; Label = 'Flow timeout (min)'; Type = 'number' }
                @{ Key = 'BgpCommunity'; Label = 'BGP community' }
                @{ Key = 'Location'; Label = 'Location'; Facet = $true }
                @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                @{ Key = 'SubscriptionName'; Label = 'Subscription'; Facet = $true }
                @{ Key = 'Tags'; Label = 'Tags'; Type = 'wide' }
                @{ Key = 'ProvisioningState'; Label = 'State'; Hidden = $true }
                @{ Key = 'ResourceId'; Label = 'Resource ID'; Hidden = $true }
            )
        }
        @{
            Id = 'findings'; Title = 'Findings'; Note = 'Most severe first. Source NSG: the rule-by-rule assessment of the NSGs on these networks (Get-AACNetworkSecurityGroup).'; Noun = 'findings'; File = 'vnet-findings'; Rows = @($Assessment.Findings)
            GroupBy = @('VirtualNetwork', 'Category', 'Severity', 'Finding')
            Columns = @(
                @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $severityTones; Facet = $true }
                @{ Key = 'Category'; Label = 'Category'; Facet = $true }
                @{ Key = 'Finding'; Label = 'Finding'; Facet = $true }
                @{ Key = 'VirtualNetwork'; Label = 'Virtual network'; Facet = $true }
                @{ Key = 'Item'; Label = 'Subnet, peering or resource'; Type = 'resource'; IdKey = 'ResourceId' }
                @{ Key = 'Detail'; Label = 'What was found'; Type = 'wide' }
                @{ Key = 'Action'; Label = 'What to do'; Type = 'wide' }
                @{ Key = 'Source'; Label = 'Source'; Type = 'badge'; Tones = @{ Assessment = 'info'; NSG = 'violet' }; Facet = $true }
                @{ Key = 'ResourceId'; Label = 'Resource ID'; Hidden = $true }
            )
        }
        @{
            Id = 'subnets'; Title = 'Subnets'; Note = 'Usable: the prefix''s addresses less the 5 Azure keeps. Used: IP configurations in the subnet (NICs, private endpoints, gateways, load balancers...). Delegated services may use more than they show.'; Noun = 'subnets'; File = 'subnets'; Rows = @($Assessment.Subnets)
            GroupBy = @('VirtualNetwork', 'Purpose', 'Outbound', 'Nsg'); Group = 'VirtualNetwork'
            Columns = @(
                @{ Key = 'VirtualNetwork'; Label = 'Virtual network'; Facet = $true }
                @{ Key = 'Subnet'; Label = 'Subnet'; Type = 'resource'; IdKey = 'SubnetId' }
                @{ Key = 'Purpose'; Label = 'Purpose'; Facet = $true }
                @{ Key = 'Prefix'; Label = 'Prefix' }
                @{ Key = 'Size'; Label = 'Addresses'; Type = 'number'; Sum = $true; Format = 'N0' }
                @{ Key = 'Usable'; Label = 'Usable'; Type = 'number'; Sum = $true; Format = 'N0' }
                @{ Key = 'Used'; Label = 'Used'; Type = 'number'; Sum = $true; Format = 'N0' }
                @{ Key = 'Available'; Label = 'Available'; Type = 'number'; Sum = $true; Format = 'N0'; Tone = 'good' }
                @{ Key = 'UsedPercent'; Label = '% used'; Type = 'number' }
                @{ Key = 'Nsg'; Label = 'NSG'; Facet = $true }
                @{ Key = 'RouteTable'; Label = 'Route table'; Facet = $true }
                @{ Key = 'DefaultRoute'; Label = 'Default route (0.0.0.0/0)' }
                @{ Key = 'BgpPropagation'; Label = 'BGP propagation'; Facet = $true }
                @{ Key = 'NatGateway'; Label = 'NAT gateway' }
                @{ Key = 'Outbound'; Label = 'Outbound path'; Type = 'badge'; Tones = @{ 'Default outbound access' = 'warn'; 'Public IPs on NICs' = 'warn'; 'NAT gateway' = 'good'; 'Firewall / NVA (route table)' = 'good'; 'None (private subnet)' = 'good' }; Facet = $true }
                @{ Key = 'DefaultOutboundAccess'; Label = 'Default outbound access'; Facet = $true }
                @{ Key = 'ServiceEndpoints'; Label = 'Service endpoints'; Type = 'wide' }
                @{ Key = 'ServiceEndpointPolicies'; Label = 'Endpoint policies' }
                @{ Key = 'Delegations'; Label = 'Delegations' }
                @{ Key = 'PrivateEndpoints'; Label = 'Private endpoints'; Type = 'number'; Sum = $true }
                @{ Key = 'PrivateEndpointPolicies'; Label = 'PE network policies'; Facet = $true }
                @{ Key = 'PrivateLinkPolicies'; Label = 'Private Link service policies'; Hidden = $true }
                @{ Key = 'Nics'; Label = 'NICs'; Type = 'number'; Sum = $true }
                @{ Key = 'Vms'; Label = 'VMs'; Type = 'number'; Sum = $true }
                @{ Key = 'PublicIpNics'; Label = 'NICs with public IPs'; Type = 'number'; Sum = $true; Tone = 'warn' }
                @{ Key = 'IpForwardingNics'; Label = 'IP forwarding NICs'; Type = 'number' }
                @{ Key = 'FlowLogs'; Label = 'Flow logs'; Type = 'badge'; Tones = @{ None = 'bad'; 'NSG flow log' = 'warn'; 'VNet flow log' = 'good'; 'Subnet flow log' = 'good' }; Facet = $true }
                @{ Key = 'SubscriptionName'; Label = 'Subscription'; Hidden = $true }
                @{ Key = 'ResourceGroup'; Label = 'Resource group'; Hidden = $true }
            )
        }
        @{
            Id = 'peerings'; Title = 'Peerings'; Note = 'Each network''s side of a peering. Reverse: whether the remote network peers back (unknown where it can''t be read).'; Noun = 'peerings'; File = 'peerings'; Rows = $peeringRows; GroupBy = @('VirtualNetwork', 'State', 'Sync')
            Columns = @(
                @{ Key = 'VirtualNetwork'; Label = 'Virtual network'; Facet = $true }
                @{ Key = 'Peering'; Label = 'Peering' }
                @{ Key = 'RemoteVirtualNetwork'; Label = 'Remote network'; Type = 'resource'; IdKey = 'RemoteVirtualNetworkId' }
                @{ Key = 'RemoteSubscription'; Label = 'Remote subscription'; Facet = $true }
                @{ Key = 'RemoteLocation'; Label = 'Remote region' }
                @{ Key = 'State'; Label = 'State'; Type = 'badge'; Tones = @{ Connected = 'good'; Initiated = 'bad'; Disconnected = 'bad' }; Facet = $true }
                @{ Key = 'Sync'; Label = 'Sync'; Type = 'badge'; Tones = @{ FullyInSync = 'good'; LocalNotInSync = 'warn'; RemoteNotInSync = 'warn'; LocalAndRemoteNotInSync = 'warn' }; Facet = $true }
                @{ Key = 'GlobalText'; Label = 'Global'; Facet = $true }
                @{ Key = 'Access'; Label = 'VNet access'; Facet = $true }
                @{ Key = 'Forwarded'; Label = 'Forwarded traffic'; Facet = $true }
                @{ Key = 'Transit'; Label = 'Gateway transit'; Facet = $true }
                @{ Key = 'RemoteAddressSpace'; Label = 'Remote address space'; Type = 'wide' }
                @{ Key = 'SubnetPeering'; Label = 'Subnet peering'; Type = 'wide' }
                @{ Key = 'Visible'; Label = 'Remote readable'; Facet = $true }
                @{ Key = 'Reverse'; Label = 'Reverse peering'; Type = 'badge'; Tones = @{ Yes = 'good'; No = 'bad' }; Facet = $true }
            )
        }
        @{
            Id = 'free'; Title = 'Free address ranges'; Note = 'The address space no subnet uses, as the largest CIDR blocks that fit - where new subnets can go.'; Noun = 'ranges'; File = 'free-ranges'; Rows = @($Assessment.FreeRanges); GroupBy = @('VirtualNetwork', 'AddressSpace')
            Columns = @(
                @{ Key = 'VirtualNetwork'; Label = 'Virtual network'; Facet = $true }
                @{ Key = 'AddressSpace'; Label = 'Address space'; Facet = $true }
                @{ Key = 'Prefix'; Label = 'Free range' }
                @{ Key = 'Size'; Label = 'Addresses'; Type = 'number'; Sum = $true; Format = 'N0' }
            )
        }
        @{
            Id = 'endpoints'; Title = 'Private endpoints'; Note = 'Zone linked: whether the privatelink DNS zone for the endpoint is linked to its network (when the network uses Azure DNS).'; Noun = 'private endpoints'; File = 'private-endpoints'; Rows = @($Assessment.PrivateEndpoints); GroupBy = @('VirtualNetwork', 'TargetType', 'Status')
            Columns = @(
                @{ Key = 'VirtualNetwork'; Label = 'Virtual network'; Facet = $true }
                @{ Key = 'Subnet'; Label = 'Subnet'; Facet = $true }
                @{ Key = 'PrivateEndpoint'; Label = 'Private endpoint'; Type = 'resource'; IdKey = 'ResourceId' }
                @{ Key = 'Target'; Label = 'Target' }
                @{ Key = 'TargetType'; Label = 'Target type'; Facet = $true }
                @{ Key = 'Groups'; Label = 'Sub-resource'; Facet = $true }
                @{ Key = 'Status'; Label = 'Connection'; Type = 'badge'; Tones = @{ Approved = 'good'; Pending = 'warn'; Rejected = 'bad'; Disconnected = 'bad' }; Facet = $true }
                @{ Key = 'ZoneLinked'; Label = 'Zone linked'; Type = 'badge'; Tones = @{ Yes = 'good'; No = 'bad' }; Facet = $true }
            )
        }
        @{
            Id = 'asgs'; Title = 'Application security groups'; Note = 'In the subscriptions of these networks: the NICs in each, and the NSG rules that name it.'; Noun = 'ASGs'; File = 'asgs'; Rows = @($Assessment.Asgs); GroupBy = @('ResourceGroup', 'SubscriptionName')
            Columns = @(
                @{ Key = 'Asg'; Label = 'ASG'; Type = 'resource'; IdKey = 'ResourceId' }
                @{ Key = 'Nics'; Label = 'NICs'; Type = 'number'; Sum = $true }
                @{ Key = 'Members'; Label = 'Members'; Type = 'wide' }
                @{ Key = 'VirtualNetworks'; Label = 'Virtual networks' }
                @{ Key = 'Rules'; Label = 'Rules'; Type = 'number' }
                @{ Key = 'RuleNames'; Label = 'NSG rules naming it'; Type = 'wide' }
                @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                @{ Key = 'SubscriptionName'; Label = 'Subscription'; Facet = $true }
                @{ Key = 'Location'; Label = 'Location'; Facet = $true }
            )
        }
        @{
            Id = 'nsgrules'; Title = 'NSG rules'; Note = 'The custom rules of the NSGs on these networks, in the order Azure evaluates them (Get-AACNetworkSecurityGroup has the defaults and more).'; Noun = 'rules'; File = 'nsg-rules'; Rows = $nsgRules
            GroupBy = @('Nsg', 'Direction', 'Access', 'Risk'); Group = 'Nsg'
            Columns = @(
                @{ Key = 'Nsg'; Label = 'NSG'; Facet = $true }
                @{ Key = 'Direction'; Label = 'Direction'; Type = 'badge'; Tones = @{ Inbound = 'info'; Outbound = 'violet' }; Facet = $true }
                @{ Key = 'Priority'; Label = 'Priority'; Type = 'number' }
                @{ Key = 'Name'; Label = 'Rule' }
                @{ Key = 'Access'; Label = 'Access'; Type = 'badge'; Tones = @{ Allow = 'good'; Deny = 'bad' }; Facet = $true }
                @{ Key = 'Protocol'; Label = 'Protocol'; Facet = $true }
                @{ Key = 'Source'; Label = 'Source'; Type = 'wide' }
                @{ Key = 'Destination'; Label = 'Destination'; Type = 'wide' }
                @{ Key = 'DestinationPorts'; Label = 'Destination ports' }
                @{ Key = 'Risk'; Label = 'Risk'; Type = 'badge'; Tones = $severityTones; Facet = $true }
                @{ Key = 'Finding'; Label = 'Finding'; Type = 'wide' }
            )
        }
    )
    $notices = @(foreach ($key in @($Assessment['Failed'] | Where-Object { $_ })) { @{ Tone = 'warn'; Text = "The $key couldn't be read: the findings that need them may be missing." } })
    Write-AACHtmlReport -Path $Path -Title $Title -Subtitle 'Virtual networks: address space and IPs, subnets, peerings, NSGs, ASGs, DNS and security' -Fact $Detail -Tile $tiles -Chart $charts -Table $tables -Notice $notices
}
