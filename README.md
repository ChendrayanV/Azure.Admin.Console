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
- **Tenant inventory.** Management groups, subscriptions, resource groups
  and resources as one tree, with counts, the Defender for Cloud secure score
  and findings, and - with `-Cost` - what everything costs, at every level.
- **Security posture.** Microsoft Defender for Cloud and Azure Policy in
  one report: secure scores, recommendations by control with remediation
  links, active alerts, Defender plans, regulatory compliance traced to the
  failing resources, and policy compliance.
- **Network security groups.** Every NSG assessed: where it's applied, every
  rule in evaluation order, flow logs and diagnostic settings, and findings
  by severity with what to do.
- **Azure Policy compliance.** Every resource's policy states, with their
  initiative, assignment and effect - by management group, subscription or
  resource group - and compliance per assignment, policy and scope.
- **Entra ID group membership.** Who is in your groups - direct members and
  everyone in nested groups - flattened to one row per group and member,
  with guests and disabled accounts flagged. Read from Microsoft Graph.
- **Resource map.** A diagram of one or more resource groups in your
  browser, with Azure icons, VNets and subnets, network paths, NSGs and
  route tables. Saves as PNG or JPEG.
- **PSRule for Azure.** Its 500+ Well-Architected rules, the module's own
  naming and tag rules, and your custom rules, run on the live estate. You
  can leave rules out by name or wildcard.
- **Fast.** One pooled HTTPS connection for every call, and independent
  reads in parallel within each Azure API's limits.
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
need Cost Management Reader or Reader; group membership needs an account
allowed to read groups in Entra ID, as tenant members are by default).

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

# The tenant as a tree, with secure scores and costs
Get-AACInventory -Cost -HtmlPath .\Inventory.html

# Defender for Cloud and Azure Policy: scores, recommendations, alerts, plans, compliance
Get-AACSecurityPosture -HtmlPath .\Security.html

# Every network security group, assessed
Get-AACNetworkSecurityGroup

# Azure Policy: every resource's compliance, for one management group
Get-AACPolicyState -ManagementGroupId 'mg-landingzones' -HtmlPath .\Policy.html

# Which VM sizes a new three-zone AKS node pool can use, and why not
Get-AACSkuAvailability -ClusterName 'aks-contoso' -Zone 1, 2, 3 -Series D, E -NodeCount 3

# Who is in your Entra ID groups, nested groups included
Get-AACEntraGroupMembership -GroupNameStartsWith 'grp-' -HtmlPath .\Groups.html

# A diagram of a resource group, in your browser
Show-AACResourceMap -ResourceGroupName 'rg-app'

# PSRule for Azure on the live estate, as a clickable HTML report
Invoke-AACPSRule -HtmlPath .\PSRule.html

# Just the module's naming and tag rules - quick: names, types and tags only
Invoke-AACPSRule -Rule 'AAC.*'

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
- **Objects:** piped onward, or with `-NoDisplay`, a command returns its
  objects and draws no view. Stopping early is fine:
  `Get-AACSkuAvailability -Location uksouth | Select-Object -First 5` ends the
  command quietly and the rest of your script carries on.
- **Progress:** every command shows the same progress display: the title,
  then one line per step with a bar, a percentage and the elapsed time, each
  finishing with what it did.

**Nothing is cut off.** Console views wrap long text - reasons,
recommendations, messages - rather than truncating it, and list every
finding; the PSRule view lists up to 50 resources per rule and says how many
more there are. The objects' default tables at the prompt wrap too
(`Azure.Admin.Console.Format.ps1xml`), and `Format-List *` or
`Select-Object *` shows every property.

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
| [`Get-AACInventory`](docs/Get-AACInventory.md) | The tenant as a tree: management groups, subscriptions, resource groups and resources, with counts, the Defender for Cloud secure score and - with `-Cost` - the cost at every level. A console tree, objects, and CSV, PDF and interactive HTML reports. |
| [`Get-AACSecurityPosture`](docs/Get-AACSecurityPosture.md) | Microsoft Defender for Cloud and Azure Policy in one report: secure scores, recommendations grouped by control with remediation links, active alerts, Defender plans, regulatory compliance traced to the failing resources, and policy compliance per assignment - one list of findings. A console view, objects, and CSV, PDF and interactive HTML reports. |
| [`Get-AACSkuAvailability`](docs/Get-AACSkuAvailability.md) | Which VM sizes you can use for virtual machines or AKS node pools in a region and its availability zones - the subscription's restrictions, vCPU quota and AKS's rules - and why a size can't be used; an AKS cluster's node pools. Read-only REST, nothing deployed. A console view, objects, and CSV, PDF and interactive HTML reports. |
| [`Get-AACPolicyState`](docs/Get-AACPolicyState.md) | Azure Policy compliance for every resource - one row per resource and policy, with initiative, assignment, effect and when it was evaluated - by management group, subscription or resource group, with compliance per assignment, policy, subscription and resource group. A console view, objects, and CSV, PDF and interactive HTML reports. |
| [`Get-AACNetworkSecurityGroup`](docs/Get-AACNetworkSecurityGroup.md) | A detailed assessment of network security groups: associations, every rule, flow logs and diagnostic settings, and findings by severity (open to the internet, shadowed rules, subnet and NIC conflicts, logging gaps). A console view, objects, and CSV, PDF and interactive HTML reports. |
| [`Get-AACEntraGroupMembership`](docs/Get-AACEntraGroupMembership.md) | Entra ID groups and everyone in them - direct and through nested groups - one row per group and member, with type, source, guests and disabled accounts. A console view with each group's members as a tree, objects, and CSV, PDF and interactive HTML reports. |
| [`Show-AACResourceMap`](docs/Show-AACResourceMap.md) | A map of one or more resource groups, opened in your browser: the resources with their Azure icons, in subscription, resource group, VNet and subnet boxes, with their connections, dependencies and network paths. Saves as PNG or JPEG. |
| [`Show-AACCost`](docs/Show-AACCost.md) | Subscription costs: month to date by subscription and by service, and a monthly trend, as charts and a table. |
| [`Invoke-AACPSRule`](docs/Invoke-AACPSRule.md) | PSRule for Azure, the module's own naming and tag rules and your custom rules on the live estate: include or exclude rules by name or wildcard, with a baseline or settings. Runs of only the module's rules read just names, types and tags. |
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

## Security posture

`Get-AACSecurityPosture` reads Microsoft Defender for Cloud and Azure Policy
with Azure Resource Graph (`securityresources`, `policyresources`), every
query at once. Reader or Security Reader is enough.

```powershell
Get-AACSecurityPosture                                                 # every section, every subscription
Get-AACSecurityPosture -Tag @{ Environment = 'Prod' } -HtmlPath .\Security.html
Get-AACSecurityPosture -Section Alerts, Plans                          # just the alerts and the Defender plans
Get-AACSecurityPosture -Section Compliance -Standard '*ISO*' -PdfPath .\ISO.pdf
Get-AACSecurityPosture -NoDisplay | Where-Object { $_.Section -eq 'Recommendation' -and $_.Severity -eq 'High' } | Group-Object Title
```

| Section | What it shows |
|---|---|
| `Score` | Each subscription's secure score - Defender's points, added up across subscriptions as Defender does - and the controls with the potential increase of fixing each |
| `Recommendations` | Every unhealthy recommendation on each resource: severity, the secure score control it belongs to, category, description, remediation steps and its portal page |
| `Alerts` | Active and in-progress security alerts: severity, intent, resource, age and the alert's page |
| `Plans` | Which Defender plans are on or off in each subscription |
| `Compliance` | Each regulatory standard's passed and failed controls; a failed control is traced to the resources failing the recommendations behind it |
| `Policy` | Azure Policy compliance per assignment (display names, even for management group assignments), and every non-compliant resource with the policy and its effect |

**One list of findings** (`AAC.SecurityFinding`), the same in the objects,
CSV, HTML and PDF: Section, Severity, Title, Category, Control, the
resource, State, Detail, the portal link and since when - most severe first.
`-ResourceGroupName` and `-Tag` narrow the findings to those resources (tag
values match exactly, not as substrings); scores, plans and standards are
per subscription. It tells you when Defender plans are off, because then an
empty alert list doesn't mean nothing happened.

For every policy state in detail - compliant ones too - use
`Get-AACPolicyState`; both commands read the same query.

`Get-AACInventory` and `Get-AACSecurityPosture` share their Defender queries
and objects: the inventory puts each node's score and findings in the tree,
and this command is the posture itself.

## Azure Policy compliance

`Get-AACPolicyState` reads the Azure Policy states with one Azure Resource
Graph KQL query (`policyresources`), with the policies' and initiatives'
display names. The assignments' names, scopes and enforcement are read
tenant-wide, because many are assigned at a management group. Reader is
enough.

```powershell
Get-AACPolicyState                                                           # every subscription you can see
Get-AACPolicyState -ManagementGroupId 'mg-landingzones'                      # every subscription under a management group
Get-AACPolicyState -SubscriptionId $sub -ResourceGroupName 'rg-app', 'rg-data'
Get-AACPolicyState -ComplianceState NonCompliant -HtmlPath .\Policy.html -PdfPath .\Policy.pdf -CsvPath .\Policy.csv
Get-AACPolicyState -ComplianceState NonCompliant -NoDisplay | Group-Object Policy | Sort-Object Count -Descending
```

| Scope | |
|---|---|
| `-ManagementGroupId` | Every subscription under these management groups |
| `-SubscriptionId` | These subscriptions |
| `-ResourceGroupName` | Only these resource groups, with either of the above or on its own |
| `-ComplianceState` | Only NonCompliant, Compliant, Exempt, Unknown, Conflict or Error states - filtered in the query |

**One row per resource and policy** (`AAC.PolicyState`): compliance state,
resource, type, resource group, subscription, location, policy, initiative,
assignment, where it is assigned (management group, subscription or resource
group, by name), enforcement, effect and when it was evaluated.

From those rows:
- each **resource** takes the state that ranks first across its policies,
  as the Azure portal does: Non-compliant, Compliant, Error, Conflicting,
  Protected, Exempt, Unknown;
- **compliance (%)** is the portal's: (compliant + exempt + unknown +
  protected resources) / every resource evaluated; *Not started* states
  aren't counted;
- compliance **per assignment** (least compliant first, with enforcement),
  **per subscription**, **per resource group** and **per policy**.

The console shows tiles, compliance by subscription and by resource group,
the assignments, and every non-compliant resource grouped by policy. The
HTML report has a donut of the states and charts that filter tables of
resources, states, assignments, policies, subscriptions and resource groups.
The PDF has the summary, the scopes, the assignments and the non-compliant
resources by policy. `-CsvPath` writes every state.

## VM size availability (virtual machines and AKS)

`Get-AACSkuAvailability` answers "can I use this VM size here?" before you
deploy: for virtual machines, or for AKS node pools. It only reads - Reader
is enough, and nothing is created - over REST:

| Read | From |
|---|---|
| The sizes offered in the region, their zones and capabilities, and what's restricted for your subscription (the region, or single zones) | `Microsoft.Compute/skus` |
| Each family's and the region's vCPU quota | `Microsoft.Compute/locations/{region}/usages` |
| Which physical zone each logical zone is (it differs between subscriptions) | the subscription's locations |
| An AKS cluster's region and node pools (`-ClusterName`) | Azure Resource Graph |

```powershell
Get-AACSkuAvailability -Location uksouth -Zone 1, 2, 3 -Series D, E               # D and E series usable in all three zones
Get-AACSkuAvailability -ClusterName 'aks-contoso' -Zone 1, 2, 3 -NodeCount 3      # a new 3-node, 3-zone pool on a cluster
Get-AACSkuAvailability -Service Aks -Location uksouth, ukwest -Architecture Arm64 -HtmlPath .\Skus.html
Get-AACSkuAvailability -Location westeurope -Zone 1, 2, 3 -NoDisplay |
    Where-Object { $_.Status -eq 'Available' -and $_.vCPUs -eq 4 -and $_.MemoryGB -ge 16 }
```

Each size gets a **status**, the first that applies, with the reason:

| Status | Why |
|---|---|
| `Restricted` | Not offered to your subscription in the region (`NotAvailableForSubscription`) |
| `NotSupported` | `-Service Aks` (or `-ClusterName`): fewer than 2 vCPUs, which AKS can't use |
| `ZoneUnavailable` | None of the `-Zone` zones can host it (not offered there, or restricted for you) |
| `Partial` | Some of the `-Zone` zones can't |
| `NoQuota` | The family's or the region's free vCPUs are fewer than vCPUs x `-NodeCount` |
| `Available` | Nothing stops it |

For AKS it also notes sizes with less than 4 GB (user node pools only) and
burstable B-series sizes (not recommended for system node pools). With
`-ClusterName` the region and subscription are the cluster's, the sizes its
node pools use are marked, and each pool is shown with its size's status now
and the family's free vCPUs - whether it can scale out.

Narrow the sizes with `-Series` (the letters of the name: `D`, `E`, `NC`,
`DC`; wildcards allowed), `-Sku` (`Standard_D4s_v5`, `D4s_v5` or `*s_v5`) and
`-Architecture x64|Arm64`. Each row (`AAC.SkuAvailability`) has the size's
vCPUs, memory, zones (and the ones missing), family and regional free vCPUs,
architecture, ephemeral OS disk, accelerated networking, premium storage,
Spot, GPUs, data disks and Hyper-V generations.

The console shows tiles, the zone mapping, the vCPU quota (most used first),
the cluster's node pools and each size, usable first. The HTML report has a
donut of the statuses and charts that filter tables of sizes, quota, zones and
node pools; the PDF has the same. `-CsvPath` writes every size.

What no read can tell you is whether there's capacity at the moment you
deploy (`ZonalAllocationFailed` and similar); nothing here deploys to find
out. More services (disks, storage, SQL, PostgreSQL and MySQL flexible
server, App Service) will follow the same pattern.

## Entra ID group membership

`Get-AACEntraGroupMembership` reads Entra ID groups and their members from
Microsoft Graph and follows nested groups to the end:

```powershell
Get-AACEntraGroupMembership -GroupName 'grp-finance', 'grp-hr'            # these groups, by exact name
Get-AACEntraGroupMembership -GroupNameStartsWith 'grp-azure-'             # every group whose name starts with this
Get-AACEntraGroupMembership                                                # every group in the tenant
Get-AACEntraGroupMembership -GroupNameStartsWith 'grp-' -HtmlPath .\Groups.html -CsvPath .\Groups.csv -PdfPath .\Groups.pdf
Get-AACEntraGroupMembership -GroupNameStartsWith 'grp-' -NoDisplay | Where-Object UserType -EQ 'Guest'   # the guests, and through which group
```

```text
grp-finance  Security - Cloud - 3 direct - 3 users
|-- Ada Lovelace  ada@contoso.example
|-- Gus Guest  gus_fabrikam.example#EXT#@contoso.example   GUEST
`-- GROUP grp-finance-emea
    |-- Grace Hopper  grace@contoso.example   DISABLED
    `-- Service principal app-payroll
```

**One row per group and member** (`AAC.EntraGroupMember`), the same in the
objects, CSV, HTML and PDF: the group (name, type - Microsoft 365, Security,
Mail-enabled security, Distribution, dynamic, role-assignable - and whether
it's cloud or synced from on-premises AD), the member (name, type - user,
group, device, service principal, contact - user principal name, mail,
member or guest, enabled or disabled, job title, department), and how it's
in the group: **Direct**, **Nested** (with **Via**, the path of nested
groups, and the depth), or **Empty** for a group with no members, so every
group appears. A group met again on its own path (a loop) is listed but not
followed twice. The console and reports also show each group's totals:
direct members, nested groups, and unique users, guests and disabled
accounts at every level.

**Sign-in.** It uses your `Connect-AAC` sign-in - no second prompt: a
Microsoft Graph token is taken from it silently, the way Application
Insights gets its Log Analytics token.
- Your account needs to be allowed to read groups in Entra ID, which members
  of the tenant are by default (guests, or tenants that restrict it, may
  not be).
- With an App Registration of your own (`Connect-AAC -ClientId`), give it
  Microsoft Graph's delegated **Group.Read.All** and **User.Read.All**
  permissions.
- Reads run 8 at a time, a level of nesting at a time, each group read
  once however many groups it's nested in; throttling waits as Graph asks.
  A group whose members can't be read is reported, and the rest carry on.

`-CsvPath` (alias `-OutputPath`) writes the rows; with no export parameter
the command shows the console view, as every command does.

## Network security groups

`Get-AACNetworkSecurityGroup` assesses network security groups the way an
auditor would. Without parameters it covers every NSG you can see.

```powershell
Get-AACNetworkSecurityGroup                                                  # every NSG
Get-AACNetworkSecurityGroup -SubscriptionId $sub -ResourceGroupName 'rg-network' -Name 'nsg-web', 'nsg-app'
Get-AACNetworkSecurityGroup -HtmlPath .\NSG.html -PdfPath .\NSG.pdf -CsvPath .\NSG-rules.csv
(Get-AACNetworkSecurityGroup -NoDisplay).Findings | Where-Object Severity -EQ 'High'
```

**What each NSG records**

| Area | What's captured |
|---|---|
| Metadata | Name, resource ID, subscription, resource group, location, tags |
| Associations | The subnets (VNet, prefix) and network interfaces (VM, private IP) it's applied to, and how many VMs it protects through either - charted as "VMs protected per NSG" to show how standard the perimeter is |
| Rules | Every rule, custom and default, in the order Azure evaluates them: priority, direction, protocol, source, source port, destination, destination port and action. Application security groups are shown by name. |
| Telemetry | Diagnostic settings (Log Analytics workspace, storage account, event hub; log categories), and flow logs with retention and Traffic Analytics. Either an NSG flow log or a virtual network flow log on its VNet, subnet or NIC counts. |

**Findings**, each with what to do:

| Severity | Finding |
|---|---|
| High | An inbound Allow from `*`, `Internet` or `0.0.0.0/0` to every port, or to a management or database port (SSH, RDP, WinRM, SMB, SQL, Redis, …) |
| Medium | A wide port range open to the internet. An NSG on no subnet and no NIC. **A NIC NSG and its subnet's NSG that disagree:** Azure evaluates both, so if one allows what the other denies, the traffic is blocked. No flow log, or a disabled one. |
| Low | ICMP from the internet. Everything allowed from the virtual network. **A shadowed rule:** an earlier rule covers it, so it never applies. Flow logs kept under 90 days. No diagnostic settings. |
| Info | Flow logs without Traffic Analytics. Only an NSG flow log (NSG flow logs retire on 30 September 2027). Over 800 of the 1,000 rules an NSG can hold. |

**Output**
- **At the prompt:** tiles, the NSGs ordered by risk, the High and Medium
  findings, and, for up to three NSGs, each one in detail with its rules.
- **Objects:** `AAC.NetworkSecurityGroup`, carrying their rules, findings,
  associations and logging.
- **`-CsvPath`:** every rule, with its risk and finding.
- **`-HtmlPath`:** tables of NSGs, findings, rules, associations and logging,
  each with a CSV download.
- **`-PdfPath`:** a summary, the findings, and a page per NSG with its rules.
- **`-NoDiagnosticSetting`:** skips the diagnostic-settings calls (one per
  NSG).

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
| Azure.Admin.Console | `AAC.Resource.RequiredTags`, `AAC.ResourceGroup.RequiredTags`, `AAC.Resource.AllowedTagValues` | Check the tags named in `Get-AACTagDefault` (`PSRule\Rules\AAC.Tags.Rule.ps1`, empty as shipped) or in `AAC_REQUIRED_TAGS` / `AAC_ALLOWED_TAG_VALUES`; with no tags named they check nothing, and the command says so |
| Azure.Admin.Console | `AAC.Resource.Naming` | On by default: the Cloud Adoption Framework abbreviations (`rg-`, `vnet-`, `kv-`, `st...`), or your own with `AAC_NAMING_PATTERNS` |
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

**Insights** (`-Insight`) add what the estate is made of and what needs
attention, from the same parallel Resource Graph read (about 11 more
queries):

| | |
|---|---|
| **Mix** | VM sizes, operating systems (Windows Server 2022, Ubuntu 22.04, ... - from the VM's instance view, or its image), VM power states, Azure VMs and Azure Arc servers, storage account replication, database tiers (Azure SQL DTU / vCore / serverless, Cosmos DB, PostgreSQL, MySQL), tag coverage |
| **Needs attention** | Unattached disks (with their size), unused public IPs and NICs, VMs **stopped but still billed** (stopped in the OS, not deallocated), disconnected Arc servers, classic resources (retired), subnets 80% full or more, VPN and ExpressRoute connections down, empty resource groups - each with its cost this month when `-Cost` is given too |
| **Network** | Every subnet's used and usable IPs (Azure keeps 5 per subnet), and the VPN and ExpressRoute connections with their status |

The console shows them as proportion charts and a table; the HTML report as
donut charts that filter a machines table, and tables of what needs
attention, subnets and connections; the PDF as a page of its own.

**Tags.** The tag rules check the tags you name. Name them for one run with
`-Configuration`, or for every run in `Get-AACTagDefault` in
`PSRule\Rules\AAC.Tags.Rule.ps1`:

```powershell
function global:Get-AACTagDefault {
    @{
        RequiredTags  = @('Owner', 'CostCenter', 'Environment')
        AllowedValues = @{ Environment = @('prod', 'test', 'dev') }
    }
}
```

`-Configuration` wins over the defaults. When a tag rule you asked for has
no tags to check, the view (and `-HtmlPath`, or a warning with `-NoDisplay`)
says so instead of leaving it out silently.

**Naming conventions.** `AAC.Resource.Naming` checks the names of resource
groups and about 30 common resource types against Microsoft's
[Cloud Adoption Framework abbreviations](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations),
with no setting needed. Run on its own, it reads only the types it checks and
no child settings: a few Resource Graph queries, however large the estate.
Names Azure creates and manages (`MC_*`, `NetworkWatcherRG`, ...) are skipped.

```powershell
Invoke-AACPSRule -Rule 'AAC.Resource.Naming'                       # the defaults
Invoke-AACPSRule -Rule 'AAC.Resource.Naming' -Configuration @{
    AAC_NAMING_PATTERNS = @{ 'Microsoft.Compute/virtualMachines' = '^vm-(prod|test|dev)-'; 'Microsoft.Web/sites' = '' }   # '' = don't check
    AAC_NAMING_IGNORE   = @('^legacy-')
}
```

To change the defaults for everyone who uses your copy of the module, edit
the table in `PSRule\Rules\AAC.Naming.Rule.ps1` (`Get-AACNamingDefault`), one
line per type. To keep your own convention without editing the module, set
it once in your profile:
`$PSDefaultParameterValues['Invoke-AACPSRule:Configuration'] = @{ AAC_NAMING_PATTERNS = @{ ... } }`.

`-Rule` takes rule names, not files: the module's rules always load, and
`-RulePath` adds rule files of your own. A `-Rule` that matches no rule is an
error rather than an empty result.

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

When only the module's `AAC.*` rules run, the child settings aren't read:
those rules look only at names, types and tags. `-NoExpand` does the same for
your own rules that need nothing more.

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

**"The pipeline has been stopped."** Before v0.13.0, piping a command to
`Select-Object -First` (or anything else that stops a pipeline early) ended
it with this error and a red panel. It isn't a failure: update to v0.13.0 or
later, where the command just stops. Ctrl+C still stops everything.

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
  to Azure Resource Manager, Resource Graph and Cost Management, through one
  pooled `HttpClient`. Independent calls run in parallel, within each API's
  limits: Resource Manager 12 at a time, Resource Graph 4, Cost Management 3.
  Throttled calls wait as long as Azure's retry headers ask.
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
| The transport (`Invoke-AACHttp`, `Invoke-AACArmParallel`, `Invoke-AACGraphBatch`) | The single HTTP send (`Send-AACHttpRequest`), or nothing (a local test server) | Retries as Azure's retry headers ask (`Retry-After`, Cost Management's and Resource Graph's own), paging (`nextLink`, `$skipToken`), the throttle limit, Azure's error messages, failures allowed per query |
| `Get-AACAdvisorRecommendation`, `Get-AACFirewallRule`, `Show-AACResource` | Resource Graph, with hand-built rows (through a shim that runs each batched query one by one) | Flattening, filters and search, output modes, CSV, PDF and HTML, and the console view |
| `Get-AACInventory` | Resource Graph and Cost Management, with a made-up Contoso tenant | The tree and its rolled-up counts, secure scores, cost (management group scope and the per-subscription fallback, deleted resources, currencies), insights (the mix, what needs attention, subnets), the views and the exports |
| `Get-AACPolicyState` | Resource Graph, with made-up policy states | The KQL and its filters, management group, subscription and resource group scope, each resource's verdict, compliance per assignment, scope and policy, the view and the exports |
| `Get-AACSkuAvailability` | The parallel ARM reads and Resource Graph, with made-up Compute SKUs, usage and zones | Region and zone restrictions, zones asked for, family and regional quota, AKS's rules, series, size and architecture filters, a cluster's node pools, errors, the view and the exports |
| `Get-AACSecurityPosture` | Resource Graph, with made-up Defender for Cloud and Azure Policy rows | Findings across sections, scores, compliance traced to resources, plans, policy compliance, resource group and tag narrowing, the queries per section, the view and the exports |
| `Get-AACNetworkSecurityGroup` | Resource Graph and the parallel ARM reads | Rule evaluation, associations and VMs protected, NIC-and-subnet conflicts, flow logs, findings, the view and the exports |
| `Show-AACResourceMap` | Resource Graph, with a made-up hub-and-spoke estate | Boxes, placement, connections, network paths, NSGs and route tables, the page |
| `Get-AACEntraGroupMembership` | Microsoft Graph (`Send-AACHttpRequest`), with made-up groups | Name filters and OData quoting, paging, nested groups and loops, a group that can't be read, the Connect-AAC Graph token, the view and the exports |
| `Show-AACCost` | Cost Management (`Invoke-AACCostBatch`, through a shim) | Month and service totals, failed subscriptions, the charts, PDF and HTML; also the query's paging |
| `Invoke-AACPSRule` | The engine (`Invoke-AACPSRuleEngine`) | Output modes, `-FailedOnly`, settings passed on, CSV and HTML; what is read for the rules asked for; `-Rule` checks; the view listing every resource |
| PSRule for Azure data (`Get-AACRuleData`) | Azure Resource Manager (`Invoke-AACArmRequest`, `Invoke-AACArmParallel`) | The Export-AzRuleData shape, child settings, 403/404 handling, masked shared keys, type filters in the query, `-NoExpand` |
| PSRule runner | Nothing | Real PSRule for Azure in a child `pwsh`: the AAC.* rules (naming with its defaults, tags), `-Type` binding for custom rules, wildcard include/exclude, a rule error not stopping the run |
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
   git tag -a v0.13.0 -m "Azure.Admin.Console v0.13.0"
   git push origin v0.13.0
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
