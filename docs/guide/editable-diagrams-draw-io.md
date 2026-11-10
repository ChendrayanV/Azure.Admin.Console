# Editable diagrams (draw.io)

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`New-AACDesignDiagram`](../New-AACDesignDiagram.md) · [`Export-AACDiagram`](../Export-AACDiagram.md) · [`Show-AACApplicationGatewayMap`](../Show-AACApplicationGatewayMap.md)

`Export-AACDiagram` draws your existing resources as a diagram you can
**edit** - not a picture. It writes a `.drawio` file. You open it in
draw.io: the desktop app, [app.diagrams.net](https://app.diagrams.net), the
*Draw.io Integration* extension for VS Code, or Confluence. From there you
can export to Visio (`.vsdx`), PNG, SVG or PDF.

```powershell
Export-AACDiagram -ResourceGroupName 'rg-hub', 'rg-spoke-app' -Path .\estate.drawio -Open
Export-AACDiagram -SubscriptionId $sub -SplitBy ResourceGroup -Path .\estate.drawio        # a page per resource group
Export-AACDiagram -View Network -ManagementGroupId 'mg-landingzones' -Path .\network.drawio
Export-AACDiagram -View ApplicationGateway -ResourceGroupName 'rg-edge' -IncludeHealth -Path .\gateways.drawio
Export-AACDiagram -ResourceGroupName 'rg-hub', 'rg-spoke-app' -Path .\estate.drawio -Update # refresh, keep your edits
```

**What's drawn.** `-View` chooses the picture: the same model as the
browser maps.

| `-View` | What it draws | Like |
|---|---|---|
| `Resources` (default) | The resources in resource groups or subscriptions, with network links, peerings, private endpoints, routes, DNS links and dependencies | `Show-AACResourceMap` |
| `Network` | The topology of a tenant, management groups, subscriptions or regions: hubs and spokes, peerings, gateways, firewalls, appliances | `Show-AACNetworkTopology` |
| `ApplicationGateway` | Each gateway's flow, a column per stage: frontends, listeners, rules, path rules, backend settings, pools and targets, with probes, WAF policies and health | `Show-AACApplicationGatewayMap` |
| `Governance` | The management group hierarchy: the tenant root and management groups as nested boxes, each subscription inside its group, with the policy and role assignments at each level | `Show-AACManagementGroupMap` |

**Made to edit.**
- **Boxes are draw.io containers:** subscription, resource group, virtual
  network, subnet, and so on. Move a box and everything in it moves too;
  drag a resource into another box and it belongs there.
- **Resources** carry the official Azure icons (vector, sharp at any zoom),
  their name and type. Unattached resources are red, and those outside the
  selection are faded.
- **Connections are attached at both ends**, so they follow what you move,
  and draw.io re-routes them.
- **Every shape keeps its data:** resource ID, type, location, resource group
  and subscription. See it with *Edit > Edit Data* or by hovering;
  Ctrl+click opens the resource in the Azure portal.
- **A Legend page** shows the kinds of box and connection used, what was
  read and when (`-NoLegend` leaves it out).
- **`-SplitBy`** puts each subscription, resource group, management group,
  region or gateway on a page of its own, for large estates.

**Refresh without losing your edits.** Move things, restyle them, rename
them, and add notes, users or on-premises shapes. Then run the same command
with `-Update`. It reads Azure again and merges into your file:
- what you moved, restyled or renamed stays as you left it;
- new resources are added into their box (which grows to fit) and marked
  green until the next refresh;
- resources no longer in Azure are faded red, with the date they went.
  `-Prune` deletes them instead;
- shapes and connections you drew yourself are left alone.

The merge works because every shape's ID comes from its Azure resource ID,
so a refresh finds it again. Without `-Update`, an existing file isn't
overwritten unless you add `-Force`.

**A clean copy to view or share.** Add `-HtmlPath`, `-PdfPath` or both to
write the same diagram in light colours, with a legend of its connections,
boxes and flags:
- **HTML**: an interactive page that works offline, to pan, zoom, search and
  click a resource for its details.
- **PDF**: one page with the title, what was read and when, the whole diagram
  and its legend. It is vector, so it stays sharp when you zoom in or print
  it. Microsoft Edge or Google Chrome draws it, headless.

Both show what was read from Azure this time, on one page whatever
`-SplitBy` says. They don't include the changes you made in draw.io.

```powershell
Export-AACDiagram -SubscriptionId $sub -Path .\estate.drawio -HtmlPath .\estate.html -PdfPath .\estate.pdf
```

**From the browser maps.** `Show-AACResourceMap`, `Show-AACNetworkTopology`
and `Show-AACApplicationGatewayMap` have a **draw.io** button at the top of
the page. It saves the map exactly as laid out there, bends included, with
the same shape IDs, so `Export-AACDiagram -Update` can refresh it later.

**What it needs.** Reader on what you draw, and nothing to install: the
diagram is written by PowerShell, with no Graphviz, Python or Visio.
`-PdfPath` uses Microsoft Edge or Google Chrome if either is installed.

## Drawing a design before it exists

`New-AACDesignDiagram` draws a hub and spoke design from a few parameters, offline: nothing is read from Azure, so it works before there is a subscription for it. `Export-AACDiagram` draws what is deployed; this draws what you are about to build.

```powershell
New-AACDesignDiagram -Name contoso -Firewall -Bastion -Spoke orders, payments -Resource FunctionApp, WebApp, StorageAccount, KeyVault -Open
```

| It plans | How |
|---|---|
| Subnets and address ranges | Each network's subnets at the size Microsoft recommends for what is in them (AzureFirewallSubnet /26, a delegated App Service integration subnet, a private endpoint subnet...), the smallest supported when the space is tight. A spoke given as a name takes the next free /16 |
| Routing | With `-Firewall`, a route table per spoke sending 0.0.0.0/0 to the firewall's private IP |
| Peering | Every spoke to the hub; with `-VpnGateway`, with gateway transit and the on-premises connection |
| Resources | Named `{type}-{spoke}-{env}-{region}`: Web and Function Apps with VNet integration and an App Service plan; storage, Key Vault, SQL, Cosmos DB, Redis, Service Bus, Event Hubs and registries behind private endpoints, their private DNS zones in the hub; VMs, AKS, Application Gateway and API Management in subnets of their own |

The diagram has a box for every subscription, region, resource group, virtual network and subnet, with each name and range on it, and a Legend page. Networks that overlap, or a network too small for its subnets, stop the command, rather than drawing addresses that can't exist.

For full control, give a spoke as a hashtable - its own range, subscription, resource group and subnets:

```powershell
New-AACDesignDiagram -Name contoso -Firewall -VpnGateway -HubAddressSpace 10.100.0.0/22 -Spoke @(
    @{ Name = 'orders'; AddressSpace = '10.110.0.0/20'; Subscription = 'sub-orders-prod'
       Subnets = @( @{ Name = 'snet-app'; AddressPrefix = '10.110.0.0/24'; Resources = 'FunctionApp' }
                    @{ Name = 'snet-pe';  AddressPrefix = '10.110.1.0/26'; Resources = 'StorageAccount', 'ServiceBus' } ) }
    @{ Name = 'web'; AddressSpace = '10.120.0.0/20'; Resources = 'ApplicationGateway', 'WebApp', 'SqlDatabase' }
) -Path .\contoso.drawio -CsvPath .\contoso-ip-plan.csv
```

Change the parameters and run it again with `-Update`: the diagram is redrawn and the changes you made to it in draw.io are kept. `-CsvPath` writes the address plan, and `-HtmlPath` or `-PdfPath` a page or PDF to share.