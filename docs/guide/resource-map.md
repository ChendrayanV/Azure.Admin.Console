# Resource map

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Show-AACResourceMap`](../Show-AACResourceMap.md)

`Show-AACResourceMap` draws the resources in one or more resource groups, in
one or more subscriptions, and opens the map in your browser:

```powershell
Show-AACResourceMap -SubscriptionId '00000000-0000-0000-0000-000000000000' -ResourceGroupName 'rg-app'
Show-AACResourceMap -SubscriptionId $hub, $spoke -ResourceGroupName 'rg-hub', 'rg-spoke-app' -Direction TopToBottom
Show-AACResourceMap -ResourceGroupName 'rg-app' -Theme Light -HtmlPath .\rg-app-map.html -NoBrowser
```

**What's drawn.** Each resource appears with its official Azure icon, its
name, its product, and a useful detail such as a VM's size, an IP address or
a disk's size.

- **Boxes.** Resources sit in boxes: subscription, then resource group, then
  virtual network, then subnet.
- **Subnet placement.** A resource with an IP in a subnet is drawn in that
  subnet: a NIC, private endpoint, firewall, gateway, Bastion, internal load
  balancer, AKS or API Management. A VM is drawn in the subnet of its NIC.
- **Subnet labels.** Each subnet's box shows its address prefix, how many of
  its addresses are in use (`3 of 251 IPs used`; Azure keeps 5 in every
  subnet) and what it's delegated to.

**The connections** come from the resource IDs in each resource's properties,
each drawn in its own style:

| Connection          | For example                                                                                          |
| ------------------- | ---------------------------------------------------------------------------------------------------- |
| Network association | A VM and its NIC, a NIC and its public IP, a subnet and its NSG, VNet integration                    |
| Resource dependency | An app on its plan, a VM on its disks, a database on its server                                      |
| VNet peering        | Two networks, with the peering state                                                                 |
| Private link        | A private endpoint and the resource it serves                                                        |
| Route (next hop)    | A route table and the firewall or appliance its routes send traffic to, e.g. `0.0.0.0/0 -> 10.0.1.4` |
| Private DNS link    | A private DNS zone and the networks it's linked to                                                   |

**NSGs and route tables** are drawn the way a network engineer reads them:
as **chips** on the subnets and NICs they're applied to, not as boxes with
long lines. An NSG shared by three subnets shows on all three.

- **Click a chip** for its rules or routes.
  - **An NSG** shows its inbound and outbound rules by priority, with
    application security groups by name and the default rules folded away.
  - **A route table** shows each route with its next hop resolved to the
    resource that owns the IP, e.g. `10.0.1.4 -> afw-hub`, and whether
    gateway route propagation is off.
- **Routes from the subnet:** a subnet's routes are drawn from the subnet
  itself to the firewall or appliance they go through, e.g. `0.0.0.0/0 via
rt-spoke`. The next hop is looked up in every subscription you can see, so
  a spoke's map reaches the hub's firewall.
- **Chip colours** flag what deserves a look:

| Colour                | NSG                                                                                                                                                                                                      | Route table                                                                |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| Red: high risk        | Allows every port, or a management or database port (SSH, RDP, WinRM, SMB, Telnet, FTP, SQL, MySQL, PostgreSQL, Oracle, MongoDB, Redis, Elasticsearch), from the internet (`*`, `Internet`, `0.0.0.0/0`) | A next-hop IP that no resource you can see has: the traffic may be dropped |
| Amber: worth a review | Allows a wide port range (over 100 ports) from the internet                                                                                                                                              | `0.0.0.0/0` straight to the internet, around any firewall                  |

A legend switch shows only what's flagged, and another draws NSGs and route
tables as **cards** with lines instead (`-NsgView Cards` starts that way).
Each peering says what it lets through: forwarded traffic, gateway transit,
remote gateway.

**Beyond the selection.**

- **Outside the selection:** a resource outside the chosen resource groups
  that a chosen one uses is drawn too, in its own resource group's box, marked
  as outside the selection. A typical case is the hub's VNet for a spoke.
- **Unattached:** resources attached to nothing are flagged in amber. That
  covers a NIC without a VM, a public IP without a configuration, an
  unattached disk, or an NSG or route table on nothing.

**In the browser:**

- pan and zoom;
- click a resource to light up its connections and see its details, with a
  link to the Azure portal;
- search;
- switch left-to-right or top-to-bottom, and the Dark, Light and Blueprint
  themes;
- hide a kind of connection;
- **Save PNG** or **Save JPEG**, at twice the screen's resolution, or SVG.
- **draw.io**: the map as you see it, as an editable draw.io diagram (see
  [Editable diagrams](editable-diagrams-draw-io.md)).

The page is one self-contained file that opens offline. Its layout comes from
the [Eclipse Layout Kernel](https://eclipse.dev/elk/) (`elkjs`, EPL-2.0), and
it uses Microsoft's
[Azure architecture icons](https://learn.microsoft.com/azure/architecture/icons/),
under Microsoft's terms for architecture diagrams. `-PassThru` also returns
the map's resources and connections as objects, e.g. `(... -PassThru).Nodes |
Where-Object Orphan`.
