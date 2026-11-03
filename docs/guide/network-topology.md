# Network topology

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Show-AACNetworkTopology`](../Show-AACNetworkTopology.md)

`Show-AACNetworkTopology` draws the networks of the whole tenant - or of
management groups, subscriptions or regions - and opens the diagram in your
browser. Read-only, with Resource Graph; Reader is enough.

```powershell
Show-AACNetworkTopology                                                     # every network you can see
Show-AACNetworkTopology -ManagementGroupId 'mg-landingzones' -GroupBy Subscription -Layout Hierarchy
Show-AACNetworkTopology -NetworkOnly -Location 'uksouth', 'ukwest' -Theme Light -HtmlPath .\Network.html -NoBrowser
(Show-AACNetworkTopology -NoBrowser -PassThru).Findings | Where-Object Severity -EQ 'High'
```

**What it reads**, in every region:

- virtual networks, subnets and peerings, across subscriptions and to
  networks you can't see
- VPN and ExpressRoute gateways, connections, circuits and local gateways;
  Virtual WAN and its hubs
- Azure Firewalls, network virtual appliances (VMs whose NIC forwards IP
  traffic), NSGs, route tables, NAT gateways, Bastion, load balancers,
  Application Gateways, private link services and DNS resolvers
- VMs, scale sets and private endpoints in their subnets, and the PaaS
  resources the endpoints serve (`-NetworkOnly` leaves these out)

A peering outside the scope is followed to the network at its other end, and
a route's next hop to the firewall or appliance that owns the IP, so a
spoke's diagram reaches its hub.

**Roles.** Each network is a **hub** (gateway transit, or a gateway, firewall
or appliance and peerings, or three or more peerings), a **spoke** of a hub,
**peered** or **standalone**.

**Two layouts**, switched at the top of the page:

| Layout                  | What you see                                                                                                                                                                                                                 |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Hub & spoke (`-Layout HubSpoke`) | Each hub at the centre, its spokes in rings around it, hubs side by side, other networks below. Each network's box names its subscription, region and resource group. The default when there are hubs with spokes. |
| Hierarchy (`-Layout Hierarchy`)  | Boxes inside boxes, packed in a grid: tenant, management group, subscription, region, resource group, network, subnet (`-GroupBy Subscription` or `Region` for fewer levels).                                     |

In both, subnets are drawn in rows inside their network, as wide as their
prefix is big, and resources in a grid inside their subnet. A VM shows its
NIC's IPs and NSG; an appliance is outlined in the route colour.

**The lines.** Peerings between networks, with their state and what they let
through (red and dashed when not Connected); private endpoints to the PaaS
they serve; routes from a subnet to the firewall or appliance that inspects
its traffic (one line per spoke in the hub & spoke view); a gateway's
connections and circuits. Subnets in a network reach each other through
Azure's system routes, so no lines are drawn between them.

**At the prompt**, tiles, the hubs with their transit (firewall, gateway,
appliance) and spokes, and findings:

| Severity | Finding                                                                                                   |
| -------- | --------------------------------------------------------------------------------------------------------- |
| High     | A peering that isn't Connected; a route to an IP no resource you can see has                              |
| Medium   | A spoke subnet with VMs whose internet traffic isn't sent through a firewall or appliance (no `0.0.0.0/0`) |
| Info     | A peering to a network you can't see (another tenant, or no Reader); a standalone network                 |
