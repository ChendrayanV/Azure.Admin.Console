# Tenant inventory

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Get-AACInventory`](../Get-AACInventory.md)

`Get-AACInventory` reads the tenant with Azure Resource Graph and shows it as a
tree:

```text
TENANT Contoso · 5 management groups · 3 subscriptions · 5 resource groups · 17 resources
├── MG Tenant Root Group
│   ├── MG Landing Zones · 1 subscription · 10 resources
│   │   └── MG Corp
│   │       └── SUB sub-corp-apps  Enabled · 3 resource groups · 10 resources
│   │           ├── RG rg-app  uksouth · 7 resources · disks 2, virtualmachines 2, ...
│   │           └── RG rg-empty  uksouth  empty
│   └── MG Platform ...
└── SUB sub-legacy  Warned · 1 resource group · 1 resource
```

```powershell
Get-AACInventory                                              # the whole tenant, down to resource groups
Get-AACInventory -ManagementGroupId 'mg-landingzones' -Depth Resource
Get-AACInventory -SubscriptionId $sub1, $sub2 -ResourceGroupName 'rg-app', 'rg-data'
Get-AACInventory -HtmlPath .\Inventory.html -PdfPath .\Inventory.pdf -CsvPath .\Inventory.csv
Get-AACInventory -NoDisplay | Where-Object { $_.Level -eq 'ResourceGroup' -and $_.Resources -eq 0 }   # empty resource groups
Get-AACInventory -Cost -HtmlPath .\Inventory.html                # with what everything costs
Get-AACInventory -Insight -Cost -HtmlPath .\Inventory.html       # plus the estate's mix and what needs attention
```

**How the tree is built**

- **Counts:** every node shows the subscriptions, resource groups and
  resources below it, and each resource group shows its most common types.
- **Management groups** are nested as in Azure. A group with no subscriptions
  in the result is left out, unless you ask for it with `-ManagementGroupId`.
- **A subscription whose management group you can't read** is shown under
  the tenant.
- **Empty resource groups** are flagged.
- **Scope:** `-ManagementGroupId`, `-SubscriptionId` and `-ResourceGroupName`
  each take several values. `-Depth` (ManagementGroup, Subscription,
  ResourceGroup or Resource) sets how deep the console tree goes. The objects
  and exports always have everything.

**Security posture** comes from Microsoft Defender for Cloud, through
Resource Graph's `securityresources`, so Reader access is enough:

| Level                    | Secure score                                            |
| ------------------------ | ------------------------------------------------------- |
| Subscription             | Defender's own secure score (points out of the maximum) |
| Management group, tenant | The subscriptions' scores added up, as Defender does    |
| Resource, resource group | The share of assessed recommendations that are healthy  |

- **Colours:** **Good** is 70% or more (green), **Fair** 40–69% (amber),
  **Poor** under 40% (red). Findings are counted by severity on every node:
  **H** red, **M** amber, **L** blue.
- **Controls:** the **security controls** are listed with the **potential
  score increase** of fixing each (their impact). The console shows the ones
  with the most to gain.
- **Recommendations:** every unhealthy **recommendation**, with its severity,
  user impact, effort, category and resource.
- **Without Defender data** (not enabled, or no access), the inventory is
  shown without it. `-NoSecurity` skips reading it.

**Cost** (`-Cost`) comes from Azure Cost Management, so it needs Cost
Management Reader (or Reader) on the subscriptions. Every node shows its
actual cost month to date and last month:

```text
└── SUB sub-corp-apps  3 resource groups · 10 resources  212.00 USD MTD · last month 150.00 USD
    ├── RG rg-app  7 resources  150.00 USD MTD · last month 150.00 USD
    └── DEL Deleted resources  costs of resources no longer in Azure (2), and charges not tied to a resource  32.00 USD MTD
```

- **Queries:** one for the whole tenant root group (or `-ManagementGroupId`)
  when the billing account allows it (Enterprise Agreement, Microsoft
  Customer Agreement); otherwise one per subscription, 3 at a time, retried
  as Cost Management's throttling headers ask.
- **Every charge placed:** a child resource's cost goes to the closest
  resource above it; costs of deleted resources, and charges not tied to a
  resource, go under their subscription as **Deleted resources**.
- **Never converted:** amounts stay in each subscription's billing
  currency. A level whose subscriptions are billed in different currencies
  says so instead of adding them up.
- **Unreadable subscriptions** (some offer types, or no permission) say why
  in `CostStatus`; the rest of the inventory is unaffected.

**Output**

- **Objects:** one `AAC.InventoryItem` per node, with Level, Path, the
  management group, subscription and resource group it's in, type, location,
  SKU, state, counts, most common types, secure score, rating, findings by
  severity, top findings, cost (`CostMonthToDate`, `CostLastMonth`,
  `Currency`, `CostStatus`), tags and ID.
- **`-CsvPath`:** every node, one row each.
- **`-HtmlPath`:** secure score and finding tiles; charts, including
  findings by severity and the controls with the most to gain; the hierarchy
  as a collapsible, searchable tree, with each node's score and findings as
  coloured pills, where clicking a node shows it in the tables; and tables of
  management groups, subscriptions, resource groups, resources, security
  controls and recommendations, each with its own CSV download.
- **`-PdfPath`:** the summary, the hierarchy with coloured scores, the
  security posture (subscription scores, controls, recommendations),
  subscriptions, resource groups, resources by type, and the resources.
