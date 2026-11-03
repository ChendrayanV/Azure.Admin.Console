# Virtual network assessment

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Invoke-AACVirtualNetworkAssessment`](../Invoke-AACVirtualNetworkAssessment.md)

`Invoke-AACVirtualNetworkAssessment` assesses virtual networks - every one you
can see, or those you name - from Azure Resource Graph, read-only:

```powershell
Invoke-AACVirtualNetworkAssessment                                                          # every network
Invoke-AACVirtualNetworkAssessment -SubscriptionId $sub -Name 'vnet-hub-*', 'vnet-spoke-app'  # some, in detail
Invoke-AACVirtualNetworkAssessment -ManagementGroupId 'mg-landingzones' -HtmlPath .\VNet.html -PdfPath .\VNet.pdf -CsvPath .\Subnets.csv
(Invoke-AACVirtualNetworkAssessment -NoDisplay).Subnets | Where-Object UsedPercent -GE 80    # running out of IPs
Invoke-AACVirtualNetworkAssessment -Name 'vnet-spoke-app' -NoDisplay | Select-Object -ExpandProperty FreeRangeList  # where a subnet fits
```

| Area                  | What's captured                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Metadata              | Name, role (hub, spoke, peered, standalone), location, resource group, subscription, tags, flow timeout, BGP community                                                                                                                                                                                                                                                                                                                                                                    |
| Address space and IPs | The prefixes; total IPs, IPs in subnets and unallocated; usable (Azure keeps 5 per subnet), used and available; **the free CIDR blocks a new subnet can take**; overlaps with any other network you can see                                                                                                                                                                                                                                                                               |
| Subnets               | Prefix, usable / used / available IPs and % used, purpose (gateway, firewall, Bastion, Route Server, delegated, private endpoints), NSG, route table and its default route, BGP propagation, NAT gateway, **the outbound path** (NAT gateway, firewall or NVA, forced tunnelling, public IPs, private subnet, default outbound access), service endpoints and policies, delegations, private endpoints and their network policies, NICs, VMs, public-IP and IP-forwarding NICs, flow logs |
| Peerings              | State, sync, remote network / subscription / region, global, the allow flags, gateway transit, remote address space, subnet peering, whether the remote side peers back                                                                                                                                                                                                                                                                                                                   |
| Security              | DNS servers and linked private DNS zones, DNS resolvers, DDoS protection, virtual network encryption, flow logs, gateways, Azure Firewall, Bastion, private endpoints (connection, DNS zone), application security groups (members, the NSG rules naming them), and the NSGs on the subnets, assessed rule by rule as `Get-AACNetworkSecurityGroup` does                                                                                                                                  |

**Findings**, each with what to do:

| Severity | Finding                                                                                                                                                                                                                                                                                                                                                                                                                       |
| -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| High     | A full subnet (or 95% used). A peering not Connected. An NSG, or a 0.0.0.0/0 route, on GatewaySubnet. AzureBastionSubnet, AzureFirewallSubnet or RouteServerSubnet too small. An NSG rule open to the internet on a management or database port.                                                                                                                                                                              |
| Medium   | A subnet 80% used. A peering out of sync. Workloads in a subnet with no NSG. VMs with public IPs. **Default outbound access** (being retired - use a NAT gateway or a firewall). Public IPs without DDoS Network Protection. No virtual network flow logs. Private endpoints whose privatelink zone isn't linked (with Azure DNS). Private endpoint connections not approved. A Basic VPN gateway. A GatewaySubnet under /27. |
| Low      | Oversized or empty subnets. No free address space. Overlapping address spaces. Encryption off. A single DNS server. Private endpoint network policies off. IP forwarding with no route to it. Empty or unused ASGs. Gateways that aren't zone-redundant.                                                                                                                                                                      |
| Info     | Global peering (charged per GB). A remote network you can't read. No Bastion where VMs have public IPs.                                                                                                                                                                                                                                                                                                                       |

**Output**

- **At the prompt:** tiles, the networks with their IP capacity and risk, the
  fullest subnets, the High and Medium findings, and, for up to three networks,
  each in detail with its subnets, peerings and free ranges.
- **Objects:** `AAC.VirtualNetwork`, each with its `Subnets`, `Peerings`,
  `FreeRangeList`, `PrivateEndpointList` and `Findings`.
- **`-CsvPath`:** every subnet.
- **`-HtmlPath`:** tables of networks, findings, subnets, peerings, free ranges,
  private endpoints, ASGs and NSG rules, each collapsible and downloadable as CSV.
- **`-PdfPath`:** a summary, the findings, and a section (and bookmark) per network.

The networks' NICs, NSGs, route tables, endpoints and gateways are read in
their subscriptions; every network and private DNS zone link you can see is
read too, for remote peerings, overlaps and zones linked from a hub. Used IPs
are the IP configurations in a subnet; a delegated service may hold more than
it shows.
