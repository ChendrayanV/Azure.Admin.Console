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
- **Azure estate check.** 85 live, read-only checks across every subscription
  you can see. 75 of them follow [PSRule for Azure](https://azure.github.io/PSRule.Rules.Azure/).
  They run as Pester tests, with a live progress display and a report.
- **Resource and cost charts.** Colourful console charts of what you run (by
  type, region, resource group or subscription) and what it costs (month to
  date by subscription and service, and the monthly trend).
- **Output your way.** PowerShell objects, CSV (`Export-Csv`) or a PDF report,
  from the same command.

Everything is read-only. Reader access on the subscriptions is enough (costs
need Cost Management Reader or Reader).

## Install

```powershell
Install-PSResource -Name Azure.Admin.Console     # PSResourceGet
# or
Install-Module -Name Azure.Admin.Console -Scope CurrentUser
```

Pester 5.7.1 or later is installed with it. It is the only dependency.

| | Windows | Linux / macOS |
|---|---|---|
| Objects, CSV, estate check | PowerShell 7.2+ | PowerShell 7.2+ |
| PDF reports | PowerShell 7.4+ | not supported (needs Windows fonts) |

## Quick start

```powershell
Import-Module Azure.Admin.Console
Connect-AAC                                  # opens your browser to sign in

# Azure Advisor: the console view, plus CSV and PDF reports
Get-AACAdvisorRecommendation -CsvPath .\Advisor.csv -PdfPath .\Advisor.pdf

# Azure Firewall Policy rules: the console view, plus a CSV file
Get-AACFirewallRule -CsvPath .\FirewallRules.csv

# Which firewall rules let 10.1.2.3 reach 10.0.0.4 on UDP 53?
Get-AACFirewallRule -SourceAddress 10.1.2.3 -DestinationAddress 10.0.0.4 -Port 53 -Protocol UDP

# What you run, and what it costs
Show-AACResource
Show-AACCost

# The estate check: failures only, with a PDF copy
Invoke-AACPester -FailedOnly -PdfPath .\Estate.pdf
```

## Commands

| Command | What it does |
|---|---|
| [`Connect-AAC`](docs/Connect-AAC.md) | Signs in with a browser (OAuth 2.0 + PKCE, localhost redirect). Uses the Azure CLI's pre-consented public client ID unless you pass `-ClientId`. |
| [`Disconnect-AAC`](docs/Disconnect-AAC.md) | Forgets the sign-in. It was only ever in memory. |
| [`Get-AACAdvisorRecommendation`](docs/Get-AACAdvisorRecommendation.md) | A consolidated, flattened view of Azure Advisor: a console view at the prompt, objects down a pipeline, CSV and/or PDF exports. |
| [`Get-AACFirewallRule`](docs/Get-AACFirewallRule.md) | Every Azure Firewall Policy rule: a console view at the prompt (Allow in green, Deny in red), objects down a pipeline, CSV and/or PDF exports. |
| [`Show-AACResource`](docs/Show-AACResource.md) | A colourful bar chart of your resources by type, location, resource group or subscription. |
| [`Show-AACCost`](docs/Show-AACCost.md) | Subscription costs: month to date by subscription and by service, and a monthly trend, as charts and a table. |
| [`Invoke-AACPester`](docs/Invoke-AACPester.md) | Runs any Pester v5 tests with a progress display, a console report and an optional PDF. With no `-Path` it runs the bundled estate check. |

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
- **`-CsvPath` and `-PdfPath`:** export in any of these modes.

```powershell
Get-AACFirewallRule                                          # the console view
Get-AACFirewallRule -CsvPath .\rules.csv -PdfPath .\rules.pdf # the view, plus CSV and PDF
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
```

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
Show-AACCost -PassThru | Export-Csv .\CostSummary.csv                  # one row per subscription
```

| Export | Contents |
|---|---|
| `-CsvPath` | The detail: one row per subscription, month, resource group and service (`SubscriptionName`, `SubscriptionId`, `Month`, `ResourceGroup`, `Service`, `Cost`, `Currency`), ready for an Excel pivot table |
| `-PdfPath` | Landscape A4. A summary with totals, the subscription-by-month table, and this month's top services and resource groups; then a page per subscription with its services and resource groups month by month |
| `-PassThru` | One object per subscription, with `MonthToDate`, one property per month (`2026-07`, ...), `Total`, `TopServices` and `Status` |

Costs stay in each subscription's billing currency, and each currency gets its
own charts. Cost Management allows only a few queries a minute, so a progress
display shows each subscription as it is read, and throttled calls are
retried. A subscription that Cost Management can't report on, such as some
offer types or one you lack permission for, is listed with the reason.

## Azure estate check

`Invoke-AACPester` with no `-Path` runs `Checks\AzureEstate.Tests.ps1` from
the module folder. It checks every resource the signed-in account can see:

```powershell
Connect-AAC
Invoke-AACPester                                                       # everything
Invoke-AACPester -Tag Security -FailedOnly                              # one area, failures only
Invoke-AACPester -Data @{ ResourceType = 'microsoft.keyvault/vaults' }  # one resource type
Invoke-AACPester -PdfPath .\Estate.pdf                                  # with a PDF report
```

### What it checks

Each check belongs to one area: `Governance`, `Security`, `Networking` or
`Operations`. Pick areas with `-Tag`. When a check follows a PSRule for Azure
rule, its failure message names that rule.

| Resource | Checks | PSRule rules |
|---|---|---|
| Every resource | Deployed in an approved region; has the required tags | |
| Storage accounts | Name rules and your own name format; HTTPS only; TLS 1.2+; no anonymous blob access; private containers; firewall denies by default; no shared key access; Defender malware and sensitive-data scanning (and Defender on every account, if you ask); geo or zone replication; blob, container and file-share soft delete | 15 `Azure.Storage.*` |
| Key Vault | Vault, key and secret names; purge protection; soft delete; Azure RBAC; firewall; no All/Purge access policies; audit logs; keys rotate automatically | 10 `Azure.KeyVault.*` |
| API Management | Name; managed identity; no SSL 3.0 / TLS 1.0 / 1.1; no weak ciphers; HTTPS-only APIs and backends; named values in Key Vault; products need a subscription and approval; no sample products; no wildcard CORS; `<base />` in API and product policies; Defender for APIs; certificates not expiring within 30 days; availability zones; multi-region with gateways enabled; minimum API version 2021-08-01; APIs and products described | 20 `Azure.APIM.*` |
| Application Gateway | Name; WAF SKU and WAF enabled when Internet-facing; TLS 1.2 SSL policy; HTTP redirected to HTTPS; classic WAF in prevention mode, OWASP 3.x and all rules on; 2+ instances; Medium or larger; v2 SKU; WAF policy instead of classic WAF; availability zones | 13 `Azure.AppGw.*` |
| Application Gateway WAF policies | Enabled; prevention mode; no exclusions; default and bot manager rule sets | 4 `Azure.AppGwWAF.*` |
| Service Bus | Local (SAS key) auth disabled; TLS 1.2+; audit logs (Premium); geo-replicated, with replicas in approved regions; in use | 6 `Azure.ServiceBus.*` |
| Application Insights | Name and your own name format; local auth disabled; workspace-based | 4 `Azure.AppInsights.*` |
| Managed Grafana | Version 11 or later; zone redundant | 2 `Azure.Grafana.*` |
| Logic Apps | HTTP request triggers limited to allowed caller IPs | 1 `Azure.LogicApp.*` |
| SQL servers, App Service, managed disks | Public network access disabled; HTTPS only; customer-managed key encryption | |
| NSGs, public IPs, virtual networks | No RDP/SSH from the Internet; public IPs attached; custom (hub) DNS servers | |
| VMs and other monitored types | Protected by Azure Backup; diagnostic logs sent to Log Analytics | |

### Settings

Change the rules with `-Data`. Each key sets one of the check's parameters:

```powershell
Invoke-AACPester -Tag Governance, Security -Data @{
    SubscriptionId  = '00000000-0000-0000-0000-000000000000'
    AllowedLocation = 'uksouth', 'ukwest', 'global'
    RequiredTag     = 'Owner', 'CostCenter'
}
```

| Setting | Default | |
|---|---|---|
| `SubscriptionId` | every subscription you can see | Only check these subscriptions. |
| `ResourceType` | every type | Only check these types; wildcards work (`'microsoft.network/*'`). |
| `AllowedLocation` | `uksouth`, `ukwest`, `global` | Approved regions. |
| `RequiredTag` | `Owner`, `CostCenter`, `Environment` | Tags every resource must have. |
| `DnsServer` | any custom DNS | The DNS servers every VNet must use. |
| `LogAnalyticsWorkspaceId` | any workspace | The workspace diagnostic logs must go to. |
| `BackupExemptEnvironment` | `dev` | VMs with this `Environment` tag don't need a backup. |
| `DiagnosticResourceType` | Key Vault, App Service, SQL databases, NSGs | Types that must send diagnostic logs. |
| `AppInsightsNameFormat` | off | A case-sensitive regular expression every Application Insights name must match, such as `'^appi-'`. |
| `StorageAccountNameFormat` | off | The same, for storage account names, such as `'^st'`. |
| `StorageDefenderPerAccount` | `$false` | `$true` to require Defender for Storage on each account, rather than per subscription. |

### Progress and cost

`Invoke-AACPester` shows a live Spectre.Console progress display with a spinner, bar, percentage and elapsed time:

```text
✓ Pester: 1,204 tests - 1,150 passed, 48 failed, 6 skipped ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ 100% 00:01:12
✓ Read 1,204 resources in 12 subscription(s)              ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ 100% 00:00:04
⠹ Security: Key Vault keys rotate automatically           ━━━━━━━━━━━━━━━━━━━━━━━━╸━━━━━━━━━━━  66% 00:00:51
```

The rules line names each rule as it's checked. In CI and redirected output,
each finished step is written as a single plain line instead.

Most settings come from three Resource Graph queries. The rest are read over
REST, and each read is shared by every rule that needs it:

| What | Calls |
|---|---|
| Diagnostic settings | One per resource of a `DiagnosticResourceType`, plus Key Vaults and Premium Service Bus namespaces |
| Storage accounts | Up to three per account (blob services, containers, Defender settings; file services for FileStorage) |
| Key Vault | Two per vault (keys and secrets, as metadata only; never secret values) |
| API Management | About six per service, plus one per API and one per product |
| Service Bus | Up to two per namespace |
| Availability zones | One per subscription for each resource provider involved |

### Your own tests

`Invoke-AACPester -Path .\MyTests` runs any Pester v5 tests with the same
report. The report has:
- a table of every test,
- a tree grouped by file and block, with the failures called out,
- a pass/fail chart,
- a summary and a verdict banner.

Other options:
- `-Tag`, `-ExcludeTag` and `-TestName` filter the tests.
- `-Data` passes values to the test files' `param()` blocks.
- `-FailedOnly` lists only failures.
- `-CI` writes JUnit XML.
- `-PdfPath` saves a PDF report.

Test files can add their own progress lines. See the help in `Private\Update-AACProgress.ps1`.

## Troubleshooting

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
  Checks/                    The live Azure estate check, run by Invoke-AACPester
  lib/                       Vendored Spectre.Console and PDFsharp/MigraDoc (MIT)
  en-US/                     about_Azure.Admin.Console help topic
  docs/                      Generated Markdown help, one page per command
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
| `Get-AACAdvisorRecommendation`, `Get-AACFirewallRule`, `Show-AACResource` | Resource Graph (`Invoke-AACResourceGraphQuery`) with hand-built rows | Flattening, filters and search, output modes, CSV and PDF, and the console view |
| `Show-AACCost` | The Cost Management query (`Invoke-AACCostQuery`) | Month and service totals, failed subscriptions, the charts; also the query's paging |
| `Invoke-AACPester` | Nothing | It runs in a child `pwsh` process against a sample test file, because Pester can't run inside Pester |

The console views are checked by swapping the Spectre console for one that
writes to a text buffer, then looking for what should be drawn. For a new
command, copy the nearest test file and change its mocks.

The comment-based help in each `Public\*.ps1` file is the single source of
command help. `Get-Help` reads it directly, and `docs\` is generated from it.

```powershell
./build.ps1                   # Docs + Test + Build: a validated package in out\Azure.Admin.Console
./build.ps1 -Task Docs        # regenerate docs\ after editing help
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
   git tag v0.10.0
   git push origin v0.10.0
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
