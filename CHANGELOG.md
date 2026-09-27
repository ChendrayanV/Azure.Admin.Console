# Changelog

All notable changes to Azure.Admin.Console. Versions before 0.10.0 were never published to the PowerShell Gallery.

## v0.11.0

- **Fixed:** the console-view unit tests no longer depend on the CI system they run on. Spectre.Console's default enrichers detect GitHub Actions, Azure Pipelines and others and switch on ANSI colour and Unicode for every new console, overriding the plain-text console the tests render to - which broke the v0.10.0 release run. The tests' consoles now turn that detection off. No change to the module's commands.
- **Released:** the first PowerShell Gallery release, with everything listed under v0.10.0 (which was tagged but never published).

## v0.10.0

- **New:** `Invoke-AACPSRule` - PSRule for Azure (every rule of the installed PSRule.Rules.Azure, 500+ in v1.47) on the live estate, without the Az modules: the data `Export-AzRuleData` would export is read with the `Connect-AAC` sign-in (Resource Graph, then the same child settings and API versions as its resource expansion) and PSRule runs in a `pwsh` process of its own, so its `YamlDotNet.dll` never clashes with another version in the session. A console view (tiles, failures by Well-Architected pillar, a table per pillar of failing rules - most severe first - with resources and reasons), `AAC.PSRuleResult` objects, and CSV, PDF and interactive HTML reports; `-FailedOnly`. `-Rule` and `-ExcludeRule` take names or wildcards; `-Baseline`; `-Configuration` for PSRule for Azure's options and custom rules' settings. A rule that can't evaluate a resource is reported for that resource instead of stopping the run.
- **New:** custom PSRule rules. The module ships its own - `AAC.Resource.RequiredTags`, `AAC.ResourceGroup.RequiredTags`, `AAC.Resource.AllowedTagValues`, off until `AAC_REQUIRED_TAGS` / `AAC_ALLOWED_TAG_VALUES` are set - with help (severity, recommendation, link) in `PSRule\Rules\en`; `-RulePath` adds your own rule files or folders (PowerShell, YAML or JSON), with PSRule for Azure's type binding so `-Type` works in them too.
- **New:** `Invoke-AACApplicationInsightQuery` - Application Insights exceptions from a Log Analytics workspace (`-LogWorkspaceName`, `AppExceptions`) or an Application Insights resource (`-ApplicationInsightsName`, `exceptions`), found by name and queried through Azure Resource Manager with the `Connect-AAC` sign-in. `-Last` (`30m`, `2h`, `7d`), `-MinimumSeverity`, `-ExceptionType` (wildcards), `-AppRoleName`, `-Search` and `-Top` build the KQL (values escaped); `-Query` runs any KQL. Each exception is flattened (type, message, outer/innermost exception, the details array's type, message and severity level, top stack frame, operation, app, client, item count, custom properties). A console view (tiles, timeline, severity, top types, top problems, latest exceptions), objects, CSV and HTML.
- **Parked:** `Invoke-AACPester`, its Azure estate check, its `-PSRule` check and its PDF/HTML reports are set aside for now: not exported, loaded or packaged, and no longer requiring Pester. They are kept in `Parked\` with how to bring them back.
- **New:** `Get-AACAdvisorRecommendation` shows a Spectre.Console view at the prompt (scope, tiles for recommendations, impact, resources and savings, then a colour-coded table per category, paged a screen at a time; `-NoPaging` to turn paging off), returns objects when piped onward, with `-PassThru` or `-NoDisplay`, and exports a consolidated, flattened report of every Azure Advisor recommendation (Resource Graph advisorresources: Cost, Security, Reliability, Operational excellence, Performance) as objects, a CSV file (Export-Csv, identical columns on every row, optional Ext_ column per extendedProperties key) and/or a PDF report (summary by category, impact and subscription, recommendations consolidated by type, affected resources per category), with estimated savings per currency, service retirement dates and Advisor postponed/dismissed status - no Az modules.
- **New:** `-HtmlPath` on `Get-AACAdvisorRecommendation`, `Get-AACFirewallRule`, `Show-AACResource` and `Show-AACCost`: a self-contained, interactive HTML report with clickable tiles and bar charts that filter its tables, and tables with search, filter drop-downs, sortable columns, grouping with subtotals, Azure portal links, copy ID and a CSV download of the rows shown. Advisor is grouped by recommendation with savings subtotals; Firewall is grouped by rule collection, with Allow rules open to any address flagged; `Show-AACResource -HtmlPath` is a full inventory of every resource (name, type, group, location, subscription, kind, SKU, tags); Cost has tiles and charts per currency, a subscription-by-month table and every detail row.
- **Changed:** with `-CsvPath`, `-PdfPath` or `-HtmlPath` (on every command), the console shows only the title, the progress and the files written - the report is in the files. Add `-PassThru` for the objects too.
- **Changed:** `Show-AACResource` and `Show-AACCost` page their views like the other commands, with `-NoPaging`.
- **Changed:** PSRule.Rules.Azure (1.47.0 or later) is the one required module; Pester is no longer required.
- **Changed:** the help is built with Microsoft.PowerShell.PlatyPS 1.0 (`tools\Build-Help.ps1`, run by `./build.ps1 -Task Docs`): PlatyPS Markdown in `docs\` and MAML help in `en-US\Azure.Admin.Console-help.xml`, which `Get-Help` now shows (with `-Online` links to the GitHub pages). The comment-based help stays the single source. PlatyPS is a build-time tool only.
- **Changed:** `Export-AACFirewallRule` is renamed `Get-AACFirewallRule`. At the prompt it now shows a Spectre.Console view: tiles for rules, allow, deny and DNAT, a policies table, then one table per rule collection in priority order, bordered green for Allow, red for Deny and orange for DNAT, with IP Groups expanded and Allow rules open to any source or destination called out. It returns objects when piped onward, with `-PassThru` or `-NoDisplay`, and `-CsvPath` / `-PdfPath` export in any mode, as with `Get-AACAdvisorRecommendation`.
- **New:** `Get-AACFirewallRule` search: `-SourceAddress`, `-DestinationAddress`, `-Port`, `-Protocol`, `-Fqdn`, `-Action` and `-RuleName`. Addresses and ports match by containment (an IP inside a CIDR, IP Group or `*`; overlapping ranges; IPv4 and IPv6), so a search answers "which rules let this source reach that destination on this port?".
- **New:** `Show-AACResource` - a colourful bar chart of resources by type, location, resource group or subscription, from Resource Graph.
- **New:** `Show-AACCost` - subscription costs from the Cost Management Query API, one query per subscription by month, service and resource group: month to date by subscription, service and resource group, the last N months and a subscription-by-month table with totals, per billing currency, with throttling retries and per-subscription errors listed. `-CsvPath` writes the detail (one row per subscription, month, resource group and service) and `-PdfPath` a report with a page per subscription. Month values are read in whatever form Cost Management returns them - a `[datetime]` after `Invoke-RestMethod`'s conversion, an ISO string or `20260701` - so no month is shown as a silent zero.
- **New:** unit tests for every command, with Azure mocked at the REST boundary: `Connect-AAC`'s full PKCE sign-in (fake browser and token endpoint, real listener), the firewall search, `Show-AACResource`, `Show-AACCost`, and `Invoke-AACPester` in a child process.
- **Fixed:** symbols printed as `?` (for example `? Security` in `Get-AACAdvisorRecommendation`) in consoles that aren't UTF-8. The console views now draw `●`, `·`, `→`, `›` and `✓` only when the console can show them, and `*`, `-`, `->`, `>` and `+` otherwise; fixed headers are plain ASCII. The unit tests render every view as a legacy console would and check each character against code pages 437 and 850.
- **Changed:** every command shows progress the same way, in the same colours: the title rule first, then one Spectre.Console progress line per step (reading from Azure, each Cost Management subscription, the browser sign-in and token exchange, CSV and PDF exports), each finishing with what it did - for exports, the file written. The old single-line spinner is gone.
- **Changed:** `Show-AACCost` shows the same kind of progress display as every command: the title first, then one line per step (finding subscriptions, reading each subscription's costs, writing the CSV and PDF), each finishing with what it did. When the console isn't UTF-8 and the display falls back to `+` and `-`, a one-time tip says how to switch it.
- **Removed:** `Tests\ResourceLocation.Tests.ps1` (the location rule is part of the estate check, `-Tag Governance`), its private helper `Get-AACResourceInventory` and its unit tests, and the `demo\` folder.
- **Docs:** per-cmdlet help pages in `docs\`, an `about_Azure.Admin.Console` help topic, a rewritten README, and an MIT `LICENSE`.
- **Packaging:** `build.ps1` stages a clean package in `out\` and validates it for the PowerShell Gallery.

## v0.9.0

Export-AACFirewallRule exports every Azure Firewall Policy rule (DNAT, network, application) from Azure Resource Graph as objects, a CSV file (Export-Csv) and/or a PDF report, with source and destination IP Groups resolved to names and addresses, base policy and attached firewalls - no Az modules. PDF reports -Export-AACPesterReport and Invoke-AACPester -PdfPath write the results as an A4 PDF (summary and verdict, results by check, every test with its failure message), using PDFsharp + MigraDoc 6.2.4 (MIT) vendored in lib\pdf from signature-verified nuget.org packages and loaded only after a SHA-256 check of every DLL; Spectre.Console.dll is now hash-checked at import too. Invoke-AACPester -FailedOnly lists only failed tests. Tests\AzureEstate.Tests.ps1: live governance, security, networking and operations checks of an Azure estate, including PSRule for Azure's Service Bus and Application Gateway rules, with a ResourceType filter.

## v0.8.0

slimmed down to a generic Pester runner - Invoke-AACPester (any test path, -Tag/-ExcludeTag/-TestName filters, -Data for test parameters, -CI JUnit output, -NoSpinner) plus Connect-AAC/Disconnect-AAC. Removed every other cmdlet (inventories, firewall, NSG, policy, validation, prerequisites, interactive console) and their helpers and tests; Invoke-AACPesterValidation is replaced by Invoke-AACPester. A backup of v0.7.0 is in ..\backup.

## v0.7.0

added a live resource-location Pester check (Tests\ResourceLocation.Tests.ps1 - every resource, grouped by type, must be in UK South by default) and a richer Invoke-AACPesterValidation report (results tree by file/block with failures called out, pass/fail breakdown chart, ALL PASSED/FAILED banner, test files that fail to load are reported); running the bundled tests no longer signs you out.

## v0.6.0

added Azure Firewall inventory - Get-AACFirewallInventory (firewalls, SKU, VNet/Virtual WAN hub, addresses, threat intel, rule counts, findings), Get-AACFirewallRule (classic and Firewall Policy rules in processing order, with inheritance, collection-level action and address/port/protocol filters) and Get-AACFirewallPolicyInventory (policy inheritance tree, attached firewalls, orphaned policies, IDPS/TLS/DNS proxy settings).

## v0.5.0

added Get-AACNsgRiskReport (scans every NSG for rules open to the Internet, ranked Critical/High/Medium via Azure Resource Graph).

## v0.4.1

added Show-AACBarChartDemo (Spectre.Console bar chart demo/reference cmdlet).

## v0.4.0

added Get-AACVNetInventory (virtual network/subnet inventory - available IPs, NSG rules, route tables - via Azure Resource Graph plus the subnet usage REST API).

## v0.3.0

added Get-AACPolicyInventory (Azure Policy assignment inventory with resolved Deny/Allow effect icons and parameter-level detail).

## v0.2.0

switched to Spectre.Console.dll used directly (no PwshSpectreConsole dependency), removed all Az/Microsoft.Graph module dependencies in favor of REST calls, added Connect-AAC (PKCE loopback sign-in) and Get-AACSubscription.

