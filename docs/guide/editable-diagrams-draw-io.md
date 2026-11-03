# Editable diagrams (draw.io)

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Export-AACDiagram`](../Export-AACDiagram.md) · [`Show-AACApplicationGatewayMap`](../Show-AACApplicationGatewayMap.md)

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
