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
  application) with IP Groups resolved to names and addresses.
- **Azure estate check.** 85 live, read-only checks across every subscription
  you can see. 75 of them follow [PSRule for Azure](https://azure.github.io/PSRule.Rules.Azure/).
  They run as Pester tests, with a live progress display and a report.
- **Output your way.** PowerShell objects, CSV (`Export-Csv`) or a PDF report,
  from the same command.

Everything is read-only. Reader access on the subscriptions is enough.

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

# Azure Firewall Policy rules, to CSV
Export-AACFirewallRule -CsvPath .\FirewallRules.csv

# The estate check: failures only, with a PDF copy
Invoke-AACPester -FailedOnly -PdfPath .\Estate.pdf
```

## Commands

| Command | What it does |
|---|---|
| [`Connect-AAC`](docs/Connect-AAC.md) | Signs in with a browser (OAuth 2.0 + PKCE, localhost redirect). Uses the Azure CLI's pre-consented public client ID unless you pass `-ClientId`. |
| [`Disconnect-AAC`](docs/Disconnect-AAC.md) | Forgets the sign-in. It was only ever in memory. |
| [`Get-AACAdvisorRecommendation`](docs/Get-AACAdvisorRecommendation.md) | A consolidated, flattened view of Azure Advisor: a console view at the prompt, objects down a pipeline, CSV and/or PDF exports. |
| [`Export-AACFirewallRule`](docs/Export-AACFirewallRule.md) | Every Azure Firewall Policy rule as objects, CSV and/or PDF. |
| [`Invoke-AACPester`](docs/Invoke-AACPester.md) | Runs any Pester v5 tests with a progress display, a console report and an optional PDF. With no `-Path` it runs the bundled estate check. |
| [`Export-AACPesterReport`](docs/Export-AACPesterReport.md) | Writes a Pester result as a PDF. |

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

```powershell
Export-AACFirewallRule -CsvPath .\rules.csv -PdfPath .\rules.pdf
Export-AACFirewallRule -FirewallPolicyName 'fwpol-hub-*' |
    Where-Object { $_.Action -eq 'Allow' -and $_.SourceAddresses -match '(^|, )\*($|,)' }
```

There is one row per rule, in the order the portal lists them. Source and
destination IP Groups are resolved to names and addresses, and each row also
shows the base policy and the firewalls the policy is attached to.

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

[`.github/workflows/release.yml`](.github/workflows/release.yml) then:
1. checks the tag matches `ModuleVersion`,
2. runs the tests and builds the package,
3. waits for approval in the `psgallery` environment,
4. publishes to the PowerShell Gallery,
5. creates a GitHub release with the changelog entry and the package zip.

Setup, once:
- Create a `psgallery` environment in the repository settings, with yourself as a required reviewer.
- Add a `PSGALLERY_API_KEY` secret to it.

To publish by hand instead:

```powershell
./build.ps1
$env:PSGALLERY_API_KEY = '<API key from powershellgallery.com>'
./build.ps1 -Task Publish -WhatIf     # dry run
./build.ps1 -Task Publish
```

## License

[MIT](LICENSE). The bundled libraries keep their own MIT licenses in `lib\`.
