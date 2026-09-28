# Azure.Admin.Console

[![CI](https://github.com/ChendrayanV/Azure.Admin.Console/actions/workflows/ci.yml/badge.svg)](https://github.com/ChendrayanV/Azure.Admin.Console/actions/workflows/ci.yml)
[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/Azure.Admin.Console?label=PowerShell%20Gallery)](https://www.powershellgallery.com/packages/Azure.Admin.Console)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Azure admin reports and checks from PowerShell, over plain REST. No Az or
Microsoft.Graph modules, and no app registration.

- **Azure Advisor report.** Every Advisor recommendation (Cost, Security,
  Reliability, Operational excellence, Performance) flattened to one row per
  resource, with estimated savings, retirement dates and postponed/dismissed
  status, shown as a colour-coded console view.
- **Azure Firewall rules.** Every Firewall Policy rule (DNAT, network,
  application) with IP Groups resolved to names and addresses, shown one
  colour-coded table per rule collection.
- **PSRule for Azure.** Its 500+ Well-Architected rules, the module's own
  rules and your custom rules, run on the live estate. You can leave rules
  out by name or wildcard.
- **Application Insights.** Your application's exceptions, flattened, or any
  KQL query, from a Log Analytics workspace or an Application Insights
  resource.
- **Resource and cost charts.** Colourful console charts of what you run (by
  type, region, resource group or subscription) and what it costs (month to
  date by subscription and service, and the monthly trend), plus a full
  resource inventory.
- **Output your way.** A console view, PowerShell objects, CSV, PDF or an
  interactive HTML report, from the same command.

Everything is read-only. Reader access on the subscriptions is enough (costs
need Cost Management Reader or Reader).

## Install

```powershell
Install-PSResource -Name Azure.Admin.Console     # PSResourceGet
# or
Install-Module -Name Azure.Admin.Console -Scope CurrentUser
```

One module is installed with it: PSRule for Azure (PSRule.Rules.Azure 1.47
or later, with PSRule), for `Invoke-AACPSRule`. There are no Az or
Microsoft.Graph modules.

| | Windows | Linux / macOS |
|---|---|---|
| Console views, objects, CSV, HTML | PowerShell 7.2+ | PowerShell 7.2+ |
| PDF reports | PowerShell 7.4+ | not supported (needs Windows fonts) |

## Quick start

```powershell
Import-Module Azure.Admin.Console
Connect-AAC                                  # opens your browser to sign in

# Azure Advisor: the console view, or CSV, PDF and interactive HTML reports
Get-AACAdvisorRecommendation
Get-AACAdvisorRecommendation -CsvPath .\Advisor.csv -PdfPath .\Advisor.pdf -HtmlPath .\Advisor.html

# Azure Firewall Policy rules, as an interactive HTML report
Get-AACFirewallRule -HtmlPath .\FirewallRules.html

# Which firewall rules let 10.1.2.3 reach 10.0.0.4 on UDP 53?
Get-AACFirewallRule -SourceAddress 10.1.2.3 -DestinationAddress 10.0.0.4 -Port 53 -Protocol UDP

# What you run, and what it costs
Show-AACResource
Show-AACResource -HtmlPath .\Inventory.html     # every resource, with portal links
Show-AACCost

# PSRule for Azure on the live estate, as a clickable HTML report
Invoke-AACPSRule -HtmlPath .\PSRule.html

# The last 2 hours of exceptions from Application Insights
Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-contoso-prod'
```

### Console view or reports

Every command works the same way:
- **Console view:** at the prompt, a command draws its view. A view longer
  than the terminal is shown a page at a time: press any key for the next
  page, or A for the rest. `-NoPaging` turns paging off, and it's skipped
  automatically when output is redirected.
- **Reports:** with `-CsvPath`, `-PdfPath` or `-HtmlPath`, the report is in
  the files. The console shows only the progress and the files written, not
  the view. Add `-PassThru` to get the objects as well.
- **Progress:** every command shows the same progress display: the title,
  then one line per step with a bar, a percentage and the elapsed time, each
  finishing with what it did.

The HTML reports are single, self-contained files with no external scripts,
styles or fonts, so they open offline and work as email attachments or
pipeline artifacts. Each one has:
- clickable tiles and bar charts that filter the table;
- search, filter drop-downs, sortable columns, and grouping with subtotals;
- Azure portal links and *Copy ID* for every resource;
- a CSV download of exactly the rows shown;
- light and dark themes, and a layout that works on a phone.

## Commands

| Command | What it does |
|---|---|
| [`Connect-AAC`](docs/Connect-AAC.md) | Signs in with a browser (OAuth 2.0 + PKCE, localhost redirect). Uses the Azure CLI's pre-consented public client ID unless you pass `-ClientId`. |
| [`Disconnect-AAC`](docs/Disconnect-AAC.md) | Forgets the sign-in. It was only ever in memory. |
| [`Get-AACAdvisorRecommendation`](docs/Get-AACAdvisorRecommendation.md) | A consolidated, flattened view of Azure Advisor: a console view at the prompt, objects down a pipeline, CSV and/or PDF exports. |
| [`Get-AACFirewallRule`](docs/Get-AACFirewallRule.md) | Every Azure Firewall Policy rule: a console view at the prompt (Allow in green, Deny in red), objects down a pipeline, CSV and/or PDF exports. |
| [`Show-AACResource`](docs/Show-AACResource.md) | A colourful bar chart of your resources by type, location, resource group or subscription. |
| [`Get-AACInventory`](docs/Get-AACInventory.md) | The tenant as a tree: management groups, subscriptions, resource groups and resources, with counts at every level. A console tree, objects, and CSV, PDF and interactive HTML reports. |
| [`Show-AACResourceMap`](docs/Show-AACResourceMap.md) | A map of one or more resource groups, opened in your browser: the resources with their Azure icons, in subscription, resource group, VNet and subnet boxes, with their connections, dependencies and network paths. Saves as PNG or JPEG. |
| [`Show-AACCost`](docs/Show-AACCost.md) | Subscription costs: month to date by subscription and by service, and a monthly trend, as charts and a table. |
| [`Invoke-AACPSRule`](docs/Invoke-AACPSRule.md) | PSRule for Azure, the module's own rules and your custom rules on the live estate: include or exclude rules by name or wildcard, with a baseline or settings. |
| [`Invoke-AACApplicationInsightQuery`](docs/Invoke-AACApplicationInsightQuery.md) | Application Insights exceptions, flattened, from a Log Analytics workspace or Application Insights resource, or any KQL query. |

Full help:
- **In PowerShell:** run `Get-Help <command> -Full`, or `Get-Help about_Azure.Admin.Console` for the module overview.
- **On the web:** see [docs/](docs/Azure.Admin.Console.md).

## Azure Advisor recommendations

`Get-AACAdvisorRecommendation` reads the `advisorresources` table in Azure
Resource Graph (one query for every subscription, paged). What it returns
depends on where it runs:

| Where | You get |
|---|---|
| At the prompt | A Spectre.Console view: account and scope, tiles for the totals, then one colour-coded table per category, a screen at a time |
| Piped onward (`\| Where-Object`, `\| Export-Csv`) | The objects, with no view |
| `-PassThru` | The view and the objects |
| `-NoDisplay` | The objects only, for scripts and scheduled tasks |

```text
──────────────────── Azure Admin Console :: Azure Advisor ────────────────────
admin@contoso.com · tenant 72f988bf-… · all subscriptions · 25 Sept 2026 12:47

╭─────────────────╮ ╭─────────────╮ ╭───────────────╮ ╭────────────╮ ╭──────────────────────╮ ╭────────────────────────╮
│       60        │ │     20      │ │      20       │ │     20     │ │          45          │ │       USD 6,738        │
│ recommendations │ │ high impact │ │ medium impact │ │ low impact │ │  resources affected  │ │  est. savings / month  │
╰─────────────────╯ ╰─────────────╯ ╰───────────────╯ ╰────────────╯ ╰──────────────────────╯ ╰────────────────────────╯

                         ● Cost · 4 recommendations · 4 resources · USD 525 / month
╭──────────┬──────────────────────────────────────┬─────────────────┬─────────────────────────┬────────────────────╮
│ Impact   │ Recommendation                       │ Resource        │ Subscription · RG       │ Savings / retire…  │
├──────────┼──────────────────────────────────────┼─────────────────┼─────────────────────────┼────────────────────┤
│  HIGH    │ Right-size or shutdown underutilized │ vm-app-06       │ sub-prod · rg-app-0     │ USD 105.00 / mo    │
│          │ virtual machines                     │ virtualMachines │                         │                    │
│          │                                      │ vm-app-12       │ sub-prod · rg-app-0     │ USD 210.00 / mo    │
╰──────────┴──────────────────────────────────────┴─────────────────┴─────────────────────────┴────────────────────╯
```

In the view:
- **Rows** are grouped by recommendation under an impact badge: HIGH red, MEDIUM orange, LOW grey.
- **Savings** are green.
- **Retirement dates** are red within 90 days, orange within 180 and gold after that.
- **Paging:** a view longer than the terminal is shown a screen at a time. Press any key for the next page, or A for the rest. `-NoPaging` turns this off, and it's skipped automatically when output is redirected.

`-HtmlPath` writes the interactive report. It has tiles for impact, resources,
savings and retirements, and charts by category, impact, subscription and
recommendation. Every recommendation is in one table, grouped by
recommendation, with the savings subtotalled per group.

PowerShell can't tell `$r = Get-AACAdvisorRecommendation` apart from a plain
call. To keep the objects in a variable, add `-PassThru` or `-NoDisplay`.

Each recommendation's nested JSON is flattened into one row:

| Column | |
|---|---|
| `Category`, `Impact`, `Status` | Portal category names. `Status` is Active, Postponed or Dismissed. |
| `SubscriptionName`, `SubscriptionId`, `ResourceGroup` | Where the resource lives. |
| `ResourceName`, `ResourceType`, `ResourceId` | The affected resource. |
| `Problem`, `Solution`, `PotentialBenefits`, `SubCategory` | What Advisor recommends. |
| `MonthlySavings`, `AnnualSavings`, `SavingsCurrency` | Advisor's estimates, as numbers. |
| `RetirementDate`, `RetiringFeature` | Service retirement recommendations. |
| `LastUpdated`, `SuppressionExpires`, `RecommendationTypeId`, `LearnMoreLink`, `RecommendationId` | Tracking. |
| `ExtendedProperties` | Advisor's free-form details as `key=value; key=value`. |
| `Ext_<key>` | With `-ExpandExtendedProperty`: one column per key. |

Every row has the same columns. `Export-Csv` takes its header row from the
first object, so rows with different columns would silently drop data.

```powershell
# The high-impact view, keeping the objects
$high = Get-AACAdvisorRecommendation -Impact High -Category Cost, Security, Reliability -PassThru

# Estimated monthly savings, per currency
Get-AACAdvisorRecommendation -Category Cost |
    Group-Object SavingsCurrency |
    ForEach-Object { '{0} {1:N2}' -f $_.Name, ($_.Group | Measure-Object MonthlySavings -Sum).Sum }

# Upcoming service retirements, soonest first
Get-AACAdvisorRecommendation -Category Reliability |
    Where-Object RetirementDate | Sort-Object RetirementDate |
    Format-Table RetirementDate, RetiringFeature, ResourceName, SubscriptionName

# A scheduled export: no view, postponed/dismissed included, one column per extended property
Get-AACAdvisorRecommendation -NoDisplay -IncludeSuppressed -ExpandExtendedProperty -CsvPath .\Advisor-full.csv
```

The PDF report is landscape A4 and has three parts:
1. **Summary:** totals, category by impact, subscriptions, and estimated savings.
2. **Recommendations by type:** each distinct recommendation once, with how many resources and subscriptions it affects.
3. **One section per category:** the affected resources under each recommendation.

Savings are Advisor's estimates, totalled per currency. Recommendations can
overlap (for example, a reservation and a right-size for the same VM), so a
total is an upper bound.

## Azure Firewall rules

`Get-AACFirewallRule` reads every Firewall Policy rule from Azure Resource
Graph. It returns output the same way as `Get-AACAdvisorRecommendation`:
- **At the prompt:** a console view.
- **Piped onward:** the objects, with no view.
- **`-PassThru`:** both. **`-NoDisplay`:** the objects only.
- **`-CsvPath`, `-PdfPath` and `-HtmlPath`:** the report is in the files,
  and the console shows only the progress.

The HTML report groups the rules by rule collection and flags Allow rules open
to any source or destination (`*`, `0.0.0.0/0`). Click the tile to list just
those rules.

```powershell
Get-AACFirewallRule                                          # the console view
Get-AACFirewallRule -CsvPath .\rules.csv -PdfPath .\rules.pdf -HtmlPath .\rules.html
Get-AACFirewallRule -FirewallPolicyName 'fwpol-hub-*' |
    Where-Object { $_.Action -eq 'Allow' -and $_.SourceAddresses -match '(^|, )\*($|,)' }
```

The view follows the policy hierarchy:
1. **Tiles** for the rules, allow, deny and DNAT counts, policies and rule collections.
2. **A policies table** with each policy's base policy, attached firewalls and rule counts.
3. **One section per policy**, with one table per rule collection in priority order:

```text
╭──── rcg-platform · 100 › Allow-Web · 200 · Filter · 2 rules   ALLOW ────╮   (green border)
│ Rule          │ Source             │ Destination        │ Protocols · ports │ Translation · TLS  │
│ web-out       │ 10.0.0.0/16        │ fqdn *.contoso.com │ Https:443         │ TLS inspection off │
│ application   │ ipg-spokes (IP     │                    │                   │                    │
│ rule          │ group)             │                    │                   │                    │
│               │ 10.1.0.0/16, …     │                    │                   │                    │
╰───────────────────────────────────────────────────────────────────────────────────────────────╯
╭──── rcg-platform · 100 › Block-Legacy · 300 · Filter · 1 rule   DENY ────╮   (red border)
```

In each table:
- The border and badge carry the collection's action: **Allow** in green, **Deny** in red, **DNAT** in orange.
- IP Groups show their addresses underneath.
- A `*` source or destination on an Allow rule is highlighted in yellow as `* (any)`.
- The last column shows the DNAT translation, or whether TLS inspection is on for application rules.
- Long output is paged; `-NoPaging` turns paging off.

### Searching rules

Search parameters narrow the rules. You can combine them, and each takes several values:
- **All given filters must match.** A rule appears only if it satisfies every search parameter you pass.
- **Any value of one filter will do.** `-Port 22, 3389` matches a rule for either port.

Addresses and ports match by containment, so a search answers "which rules
let this source reach that destination?":

| Parameter | Matches |
|---|---|
| `-SourceAddress`, `-DestinationAddress` | An IP, CIDR or `a-b` range (IPv4 or IPv6). It matches rules that cover or overlap it, including through IP Groups, and a `*` rule matches any address. |
| `-Port` | A port or range (`443`, `8000-8080`), overlapping the rule's ports. For application rules, each protocol's port counts. |
| `-Protocol` | `TCP`, `UDP` or `ICMP`, where a rule for `Any` matches all; or `Http`, `Https` or `Mssql` for application rules. |
| `-Fqdn` | A host name covered by the rule's FQDNs (`*.contoso.com` covers `www.contoso.com`), or a wildcard pattern. |
| `-Action`, `-RuleName` | `Allow`, `Deny` or `DNAT`; a rule-name wildcard. |

```powershell
Get-AACFirewallRule -SourceAddress 10.1.2.3 -DestinationAddress 10.0.0.4 -Port 53 -Protocol UDP
Get-AACFirewallRule -Action Allow -SourceAddress 0.0.0.0/0 -Port 3389, 22     # RDP/SSH open to any source
Get-AACFirewallRule -Fqdn www.contoso.com -Protocol Https -CsvPath .\contoso.csv
```

The results come back in priority order, allow and deny alike, so the first
match is the one Azure Firewall applies. Service tags (such as `AzureCloud`)
aren't expanded, so an address search doesn't match them.

The rules are listed in the order the Azure portal shows them. The CSV has one
row per rule, with the base policy and attached firewalls on every row. The
PDF groups rules by policy, rule collection group and collection, with the
same colours.

## Resources and costs

`Show-AACResource` counts every resource you can see with two Resource Graph
queries, and draws one bar per type, each in its own colour:

```text
Resources by type (top 20 of 57)
  compute/virtualmachines  ███████████████████████████████████████████ 412
network/networkinterfaces  █████████████████████████████████████████ 398
  storage/storageaccounts  █████████████████ 164
           37 other types  ██████ 61
```

```powershell
Show-AACResource                                  # by type, top 20
Show-AACResource -By Location                     # or ResourceGroup, Subscription
Show-AACResource -ResourceType 'microsoft.network/*' -Top 10
Show-AACResource -By Subscription -PassThru | Export-Csv .\PerSubscription.csv
Show-AACResource -HtmlPath .\Inventory.html        # an interactive inventory
```

`-HtmlPath` writes an interactive inventory of every resource: name, type,
resource group, location, subscription, kind, SKU and tags, with portal links.
Charts by type, location, subscription and resource group filter it. This
needs one more Resource Graph query, for the resources themselves.

`Show-AACCost` reads each subscription's actual cost from the Cost Management
Query API, broken down by month, service and resource group, with one query
per subscription. It shows:
- tiles for month to date, last month, the period total and the top service;
- month to date by subscription (with several subscriptions), by service and by resource group;
- a bar chart of the last months, with this month marked "to date";
- a subscription-by-month table with a total column and a total row, and each subscription's highest month in gold.

When Cost Management reports no cost for the whole period, the view says so
instead of drawing empty charts.

```powershell
Show-AACCost                                      # month to date + last 6 months
Show-AACCost -Months 12 -SubscriptionId '00000000-0000-0000-0000-000000000000'
Show-AACCost -Months 12 -CsvPath .\Cost.csv -PdfPath .\Cost.pdf   # the detail and a report
Show-AACCost -Months 12 -HtmlPath .\Cost.html                     # an interactive report
Show-AACCost -PassThru | Export-Csv .\CostSummary.csv                  # one row per subscription
```

| Export | Contents |
|---|---|
| `-CsvPath` | The detail: one row per subscription, month, resource group and service (`SubscriptionName`, `SubscriptionId`, `Month`, `ResourceGroup`, `Service`, `Cost`, `Currency`), ready for an Excel pivot table |
| `-PdfPath` | Landscape A4. A summary with totals, the subscription-by-month table, and this month's top services and resource groups; then a page per subscription with its services and resource groups month by month |
| `-HtmlPath` | Tiles and charts by month, subscription, service and resource group, which filter the detail table; a subscription-by-month table; and every detail row, with the total of whatever is shown |
| `-PassThru` | One object per subscription, with `MonthToDate`, one property per month (`2026-07`, ...), `Total`, `TopServices` and `Status` |

Costs stay in each subscription's billing currency, and each currency gets its
own charts. Cost Management allows only a few queries a minute, so a progress
display shows each subscription as it is read, and throttled calls are
retried. A subscription that Cost Management can't report on, such as some
offer types or one you lack permission for, is listed with the reason.

A subscription with no cost in the period isn't an error either: a new or
empty subscription, or one whose usage is billed elsewhere. It's left out of
the charts and totals. Its `Status` is `No cost`, and every output says so:
the console, the HTML report (a tile and a note) and the PDF (its own
table).

## Tenant inventory

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

| Level | Secure score |
|---|---|
| Subscription | Defender's own secure score (points out of the maximum) |
| Management group, tenant | The subscriptions' scores added up, as Defender does |
| Resource, resource group | The share of assessed recommendations that are healthy |

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

**Output**
- **Objects:** one `AAC.InventoryItem` per node, with Level, Path, the
  management group, subscription and resource group it's in, type, location,
  SKU, state, counts, most common types, secure score, rating, findings by
  severity, top findings, tags and ID.
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

## Resource map

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

| Connection | For example |
|---|---|
| Network association | A VM and its NIC, a NIC and its public IP, a subnet and its NSG, VNet integration |
| Resource dependency | An app on its plan, a VM on its disks, a database on its server |
| VNet peering | Two networks, with the peering state |
| Private link | A private endpoint and the resource it serves |
| Route (next hop) | A route table and the firewall or appliance its routes send traffic to, e.g. `0.0.0.0/0 -> 10.0.1.4` |
| Private DNS link | A private DNS zone and the networks it's linked to |

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

| Colour | NSG | Route table |
|---|---|---|
| Red: high risk | Allows every port, or a management or database port (SSH, RDP, WinRM, SMB, Telnet, FTP, SQL, MySQL, PostgreSQL, Oracle, MongoDB, Redis, Elasticsearch), from the internet (`*`, `Internet`, `0.0.0.0/0`) | A next-hop IP that no resource you can see has: the traffic may be dropped |
| Amber: worth a review | Allows a wide port range (over 100 ports) from the internet | `0.0.0.0/0` straight to the internet, around any firewall |

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

The page is one self-contained file that opens offline. Its layout comes from
the [Eclipse Layout Kernel](https://eclipse.dev/elk/) (`elkjs`, EPL-2.0), and
it uses Microsoft's
[Azure architecture icons](https://learn.microsoft.com/azure/architecture/icons/),
under Microsoft's terms for architecture diagrams. `-PassThru` also returns
the map's resources and connections as objects, e.g. `(... -PassThru).Nodes |
Where-Object Orphan`.

## PSRule for Azure

`Invoke-AACPSRule` checks your live estate with
[PSRule for Azure](https://azure.github.io/PSRule.Rules.Azure/): its 500+
rules, following the Azure Well-Architected Framework, on every resource,
resource group and subscription you can see. The module's own rules and your
custom rules run alongside them.

```powershell
Connect-AAC
Invoke-AACPSRule                                                  # the console view
Invoke-AACPSRule -SubscriptionId '00000000-0000-0000-0000-000000000000' -HtmlPath .\PSRule.html
Invoke-AACPSRule -CsvPath .\PSRule.csv -PdfPath .\PSRule.pdf -FailedOnly
Invoke-AACPSRule -Rule 'Azure.Storage.*', 'Azure.KeyVault.*'      # only these rules
Invoke-AACPSRule -ExcludeRule 'Azure.Resource.UseTags', 'AAC.*'    # leave these out
Invoke-AACPSRule -Baseline 'Azure.Pillar.Security'                 # a PSRule for Azure baseline
Invoke-AACPSRule -FailedOnly | Group-Object RuleName | Sort-Object Count -Descending
```

The console view has tiles for objects checked, rules, passed, failed,
"could not evaluate" and pass rate. A bar chart shows the failures by pillar.
Then each pillar gets a table of its failing rules, most severe first, with
the resources each one failed on and why. The HTML report opens on the
failures, grouped by rule, with portal and rule documentation links. The PDF
lists every failing resource under its rule, with the rule's recommendation.

### The rules

| Source | Rules | |
|---|---|---|
| PSRule for Azure | Every rule of the installed PSRule.Rules.Azure | `-Baseline` picks one of its baselines |
| Azure.Admin.Console | `AAC.Resource.RequiredTags`, `AAC.ResourceGroup.RequiredTags`, `AAC.Resource.AllowedTagValues` | Off until configured; in `PSRule\Rules` |
| Custom | Your own rule files, from `-RulePath` | `*.Rule.ps1`, `*.Rule.yaml` or `*.Rule.jsonc` |

`-Rule` runs only the rules named, and `-ExcludeRule` leaves rules out. Both
take names or wildcards. `-Configuration` passes settings to every rule:
PSRule for Azure's
[options](https://azure.github.io/PSRule.Rules.Azure/setup/configuring-options/),
the module's `AAC_*` settings, or your rules' own.

```powershell
Invoke-AACPSRule -Configuration @{
    AAC_REQUIRED_TAGS                = @('Owner', 'CostCenter', 'Environment')
    AAC_ALLOWED_TAG_VALUES           = @{ Environment = @('prod', 'test', 'dev') }
    AZURE_RESOURCE_ALLOWED_LOCATIONS = @('uksouth', 'ukwest')
}
```

### Your own rules

Write rules the way PSRule does:
[PowerShell, YAML or JSON](https://microsoft.github.io/PSRule/v2/authoring/writing-rules/).
Then pass the file or folder to `-RulePath`. PSRule for Azure's binding
applies to them too, so `-Type 'Microsoft.Storage/storageAccounts'` works. A
`# Synopsis:` comment names the rule, and an `Azure.WAF/pillar` tag places it
in a pillar. A help file in `en\<rule name>.md` next to it adds the severity,
recommendation and documentation link. See `PSRule\Rules` for examples.

```powershell
# .\MyRules\Contoso.Storage.Rule.ps1
# Synopsis: Storage accounts use the Contoso naming convention.
Rule 'Contoso.Storage.Name' -Type 'Microsoft.Storage/storageAccounts' -Tag @{ 'Azure.WAF/pillar' = 'Operational Excellence' } {
    $Assert.Match($TargetObject, 'name', '^stcontoso')
}
```

```powershell
Invoke-AACPSRule -RulePath .\MyRules -Rule 'Contoso.*'
```

### How it reads the estate

PSRule for Azure normally reads its data from `Export-AzRuleData`, which
needs the Az modules. This reads the same data with the `Connect-AAC`
sign-in instead:
- Resource Graph returns every resource with its properties, plus the
  resource groups and subscriptions.
- Azure Resource Manager provides the child settings PSRule's rules look at,
  such as storage blob services and containers, SQL auditing and firewall
  rules, Key Vault diagnostic settings, App Service config, and API
  Management APIs, products and policies. It reads the same children, with
  the same API versions, as `Export-AzRuleData` (PSRule.Rules.Azure v1.47).

Reader access is enough. When a setting can't be read, the command warns and
names it, because the rules using it may be wrong for that resource. VPN
connection shared keys are masked before PSRule sees them. A rule that can't
evaluate a resource is reported as "could not evaluate" for that resource,
and every other rule still runs. PSRule runs in a `pwsh` process of its own,
so its `YamlDotNet.dll` never clashes with the different versions that
platyPS, powershell-yaml or Az.Aks may have loaded into your session.

## Application Insights

`Invoke-AACApplicationInsightQuery` reads your application's exceptions, or
runs any KQL query. It works against a Log Analytics workspace
(`-LogWorkspaceName`, for workspace-based Application Insights, table
`AppExceptions`) or an Application Insights resource
(`-ApplicationInsightsName`, classic tables such as `exceptions`). The
resource is found by name with Resource Graph. The query runs through the Log
Analytics or Application Insights query API (`api.loganalytics.azure.com`,
`api.applicationinsights.io`). The token for that API comes from the
`Connect-AAC` sign-in, so there's no second sign-in and no Az module. It needs
Log Analytics Reader (or Reader). With an App Registration of your own
(`Connect-AAC -ClientId`), give it the delegated **Data.Read** permission of
the Log Analytics API and the Application Insights API.

A workspace only holds the exceptions of the Application Insights resources
that send to it. When a workspace has no exceptions, a warning says which
resources send there. If none do, it lists the ones you can see, where each
sends its data, and the `-ApplicationInsightsName` command to query one
directly. The portal's `exceptions | limit 5` runs in an Application Insights
resource, so it can show data that isn't in the workspace you queried.

```powershell
Invoke-AACApplicationInsightQuery -SubscriptionId '00000000-0000-0000-0000-000000000000' -LogWorkspaceName 'law-contoso-prod'
Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-contoso-prod' -Last 1d -MinimumSeverity Error -AppRoleName 'orders-api'
Invoke-AACApplicationInsightQuery -ApplicationInsightsName 'appi-contoso-portal' -ExceptionType '*SqlException' -Search 'timeout'
Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-contoso-prod' -Last 7d -HtmlPath .\Exceptions.html
Invoke-AACApplicationInsightQuery -ApplicationInsightsName 'appi-contoso-portal' -TableName requests -Last 15d
Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-contoso-prod' -TableName traces -MinimumSeverity Warning
Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-contoso-prod' -Query 'AppRequests | where Success == false | summarize count() by Name'
```

| Parameter | Default | |
|---|---|---|
| `-TableName` | `exceptions` | The table to read: `requests`, `dependencies`, `traces`, `customEvents`, `pageViews`, `availabilityResults` and so on. Either schema's name works for either source (`requests` or `AppRequests`), and Tab completes them. A workspace's other tables work too. |
| `-Last` | `2h` | How far back: `30m`, `2h`, `7d` and so on. It also bounds `-Query`. |
| `-MinimumSeverity` | all | `Verbose`, `Information`, `Warning`, `Error` or `Critical`, and worse. For exceptions and traces. |
| `-ExceptionType` | all | Exception types; wildcards work (`'*SqlException'`). For exceptions. |
| `-AppRoleName` | all | Apps or cloud roles. |
| `-Search` | none | Text in the type or messages; with `-TableName`, in any column. |
| `-Top` | all | The newest this many. By default every row in the period is read, up to the query API's limit of 500,000, and the view pages through them all. |
| `-Query` | | Any KQL instead of the exceptions query; its columns become the objects' properties. |

The values you give are escaped before they go into the KQL.

Each exception is flattened into one object, the same from either table:
- **When and how bad:** time (UTC) and severity.
- **What:** type and message, plus the outer and innermost exception.
- **The `details` array:** the first entry's type, message and severity
  level, the number of entries, and the top stack frame (method, file and
  line).
- **Where it came from:** method, assembly, problem ID, operation name and
  ID, app/role, role instance, app version, client country and city.
- **Sampling and extras:** item count (for sampled telemetry) and custom
  properties.

The console view has tiles, a timeline of exceptions, a severity breakdown,
the top exception types, the top problems (a type thrown from one place) and
every exception, newest first. `-CsvPath` and `-HtmlPath` export them. With
`-TableName`, the view is a table of every row, with the table's most useful
columns first, for example time, name, result code, success and duration for
`requests`. The objects have all the columns.

If the table doesn't exist, the error panel says so and names the tables the
source does have. The closest names come first, then how many rows each has
in the period:

```text
There is no table 'request' in appi-contoso-portal.
Fix  Did you mean 'requests'? Tables in appi-contoso-portal with data in the
     last 15d: dependencies (40,211), requests (18,204), traces (9,120),
     exceptions (57). No data: availabilityResults, customEvents, ...
```

## Troubleshooting

**When a command fails.** At the console, the progress line of the step that
was running turns red, and a red panel says what failed, that step, and what
to do:

```text
╭─ ✗ Invoke-AACApplicationInsightQuery failed ─────────────────────────────╮
│ Azure refused the request (403): The client ... does not have            │
│ authorization to perform action 'Microsoft.OperationalInsights/...'      │
│                                                                          │
│ Step  Running the exceptions query over the last 2h                      │
│ Fix   Your account needs a role that allows this: ... Log Analytics      │
│       Reader for Invoke-AACApplicationInsightQuery.                      │
╰──────────────────────────────────────────────────────────────────────────╯
```

Then the command stops with a normal PowerShell error of its own, so
`try`/`catch`, `$Error` and `-ErrorVariable` work as usual. Scripts can check
its `FullyQualifiedErrorId`: `AzureRequestFailed<status>` (for example
`AzureRequestFailed403,Show-AACCost`), `CommandFailed` or `InternalError`.
Output that isn't an interactive console (CI, redirected) and
`-ErrorAction SilentlyContinue` get no panel. An `InternalError` is a bug in
the module: its message gives the module file and line. Please
[report it](https://github.com/ChendrayanV/Azure.Admin.Console/issues) with
that message.

**`?` instead of symbols, or `+` and `-` in the progress.** Windows consoles
often default to a legacy code page (437 or 850), which has no `●`, `→` or
`✓`. The module detects this: in such a console it draws its symbols in plain
ASCII (`*`, `->`, `+`, `-`), so nothing is printed as `?`. The tests check
every view against code pages 437 and 850. For the full Unicode display,
switch the session to UTF-8 and import the module again:

```powershell
[Console]::OutputEncoding = [Text.Encoding]::UTF8   # add to your $PROFILE to keep it
Import-Module Azure.Admin.Console -Force
```

Windows Terminal and the VS Code terminal display the full Unicode output once
the encoding is UTF-8.

**"requires a minimum Windows PowerShell version of '7.2'".** The module runs
on PowerShell 7.2 or later (7.4+ for PDF export), on Windows, Linux and macOS,
not on Windows PowerShell 5.1. Install PowerShell 7 (`winget install
Microsoft.PowerShell`) and run it as `pwsh`.

## Design and security

- **No Az / Microsoft.Graph modules.** Every Azure call is a plain REST call
  (`Invoke-RestMethod` / `Invoke-WebRequest`) to Azure Resource Manager and
  Azure Resource Graph.
- **No app registration and no secrets.** The sign-in uses the authorization
  code flow with PKCE (RFC 7636) and a one-shot localhost listener. Tokens stay
  in memory for the session and are never written to disk.
- **Read-only.** No command or check changes anything in Azure. Key Vault keys
  and secrets are listed as metadata only, never their values.
- **Pinned bundled libraries.** [Spectre.Console](https://spectreconsole.net)
  (console UI) and PDFsharp + MigraDoc (PDF) ship in `lib\`, all MIT-licensed.
  Each DLL is checked against a pinned SHA-256 hash before it loads. See
  `lib\pdf\SOURCES.md`.

## Development

```text
Azure.Admin.Console/
  Azure.Admin.Console.psd1   Module manifest
  Azure.Admin.Console.psm1   Loads lib\Spectre.Console.dll, then Private\ and Public\
  Public/                    Exported commands, one per file, with comment-based help
  Private/                   Internal helpers (REST, Resource Graph, PKCE, PDF, console views, progress)
  PSRule/                    PSRuleRunner.ps1 (runs PSRule in its own pwsh) and Rules\ (the AAC.* rules and their help)
  Parked/                    Invoke-AACPester and its estate check, set aside (not loaded or packaged)
  lib/                       Vendored Spectre.Console and PDFsharp/MigraDoc (MIT)
  en-US/                     about_ help topic and the MAML help Get-Help shows (built by PlatyPS)
  docs/                      Markdown help, one page per command (built by PlatyPS)
  tools/                     Build-Help.ps1: builds docs\ and the MAML with PlatyPS (not packaged)
  Tests/                     Unit tests, no Azure needed (not packaged)
  .github/workflows/         CI and release pipelines
  build.ps1                  Docs, tests, packaging and publishing
  CHANGELOG.md, LICENSE
```

### Testing

The unit tests in `Tests\` cover every command, with no Azure account needed.
Each one mocks the point where the module leaves the machine and runs
everything on this side for real:

| Command | Mocked | Tested for real |
|---|---|---|
| `Connect-AAC` | The browser (`Start-Process`) and the token endpoint (`Invoke-RestMethod`) | The PKCE code, the localhost listener receiving the redirect, state (CSRF) validation, the token exchange and the stored session |
| `Get-AACAdvisorRecommendation`, `Get-AACFirewallRule`, `Show-AACResource` | Resource Graph (`Invoke-AACResourceGraphQuery`) with hand-built rows | Flattening, filters and search, output modes, CSV, PDF and HTML, and the console view |
| `Show-AACCost` | The Cost Management query (`Invoke-AACCostQuery`) | Month and service totals, failed subscriptions, the charts, PDF and HTML; also the query's paging |
| `Invoke-AACPSRule` | The engine (`Invoke-AACPSRuleEngine`) | Output modes, `-FailedOnly`, settings passed on, CSV and HTML |
| PSRule for Azure data (`Get-AACRuleData`) | Azure Resource Manager (`Invoke-AACArmRequest`) | The Export-AzRuleData shape, child settings, 403/404 handling, masked shared keys, type filters |
| PSRule runner | Nothing | Real PSRule for Azure in a child `pwsh`: the AAC.* rules, `-Type` binding for custom rules, wildcard include/exclude, a rule error not stopping the run |
| `Invoke-AACApplicationInsightQuery` | Resource Graph and the query API (`Invoke-AACArmRequest`) | The KQL built from the parameters (with escaping), both table schemas flattened, `-Query`, errors, the view and the exports |

The console views are checked by swapping the Spectre console for one that
writes to a text buffer, then looking for what should be drawn. For a new
command, copy the nearest test file and change its mocks.

The comment-based help in each `Public\*.ps1` file is the single source of
command help. The Docs task builds two things from it with
[Microsoft.PowerShell.PlatyPS](https://github.com/PowerShell/platyPS) 1.0:
- `docs\<Command>.md`, the PlatyPS Markdown pages;
- `en-US\Azure.Admin.Console-help.xml`, the MAML help that `Get-Help` shows.
  Each command points at it with `.EXTERNALHELP`.

PlatyPS is needed only on the build machine, not by the installed module.
It runs in a `pwsh` process of its own, because PlatyPS and PSRule each load a
different `YamlDotNet.dll`. CI fails when `docs\` or `en-US\` is out of date.

```powershell
Install-PSResource Microsoft.PowerShell.PlatyPS -Scope CurrentUser   # once, to build the help
./build.ps1                   # Docs + Test + Build: a validated package in out\Azure.Admin.Console
./build.ps1 -Task Docs        # rebuild docs\ and the MAML help after editing help
./build.ps1 -Task Test        # unit tests only
```

The Build task copies only the runtime files into `out\Azure.Admin.Console`.
It then checks the staged copy: the manifest is valid, the exports match
`Public\`, a clean import succeeds, and PSScriptAnalyzer reports no errors.

### CI

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on every push to
`main` and every pull request:
- **Unit tests** on Windows, Ubuntu and macOS, with JUnit results kept as artifacts.
- **On Windows:** checks that `docs\` is up to date with the help, then builds and validates the package and keeps it as an artifact.

### Releasing to the PowerShell Gallery

1. Bump `ModuleVersion` in `Azure.Admin.Console.psd1` and add the release to
   `CHANGELOG.md`. A published version can never be replaced.
2. Commit, then push a tag that matches the version:

   ```powershell
   git tag -a v0.12.0 -m "Azure.Admin.Console v0.12.0"
   git push origin v0.12.0
   ```

Only a version tag publishes. Pushes and pull requests run CI only.
[`.github/workflows/release.yml`](.github/workflows/release.yml) first runs a
gate with no secrets and no approval. It stops the release unless all of
these hold:
- the tag matches `ModuleVersion`;
- the tagged commit is on `main`;
- `CHANGELOG.md` has a `## v<version>` entry;
- the version is higher than the one on the PowerShell Gallery.

The run summary shows each check. Only after the gate passes, the workflow:
1. waits for approval in the `psgallery` environment,
2. runs the tests and builds the package,
3. publishes to the PowerShell Gallery,
4. creates a GitHub release with the changelog entry and the package zip.

Setup, once:
- Create a `psgallery` environment in the repository settings. Add yourself as a required reviewer, and limit its deployment tags to `v*`.
- Add a `PSGALLERY_API_KEY` secret to that environment.

To publish by hand instead:

```powershell
./build.ps1
$env:PSGALLERY_API_KEY = '<API key from powershellgallery.com>'
./build.ps1 -Task Publish -WhatIf     # dry run
./build.ps1 -Task Publish
```

## License

[MIT](LICENSE). The bundled libraries keep their own MIT licenses in `lib\`.
