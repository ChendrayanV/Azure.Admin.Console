# Changelog

All notable changes to Azure.Admin.Console. Versions before 0.10.0 were never published to the PowerShell Gallery.

## v0.10.0

- **New:** `Get-AACAdvisorRecommendation` shows a Spectre.Console view at the prompt (scope, tiles for recommendations, impact, resources and savings, then a colour-coded table per category, paged a screen at a time; `-NoPaging` to turn paging off), returns objects when piped onward, with `-PassThru` or `-NoDisplay`, and exports a consolidated, flattened report of every Azure Advisor recommendation (Resource Graph advisorresources: Cost, Security, Reliability, Operational excellence, Performance) as objects, a CSV file (Export-Csv, identical columns on every row, optional Ext_ column per extendedProperties key) and/or a PDF report (summary by category, impact and subscription, recommendations consolidated by type, affected resources per category), with estimated savings per currency, service retirement dates and Advisor postponed/dismissed status - no Az modules.
- **New:** the Azure estate check covers API Management with PSRule for Azure's 20 current `Azure.APIM.*` rules. The API Management child resources (APIs, products, backends, named values, API and product policies, Defender for APIs collections) are read over REST once per service. Operation-level policies and the deprecated `Azure.APIM.ProductTerms` rule are not checked.
- **New:** the Azure estate check covers Application Insights with PSRule for Azure's `Azure.AppInsights.*` rules: Workspace, LocalAuth, Name, and Naming (only when the new `AppInsightsNameFormat` setting is given).
- **New:** the Azure estate check covers Azure Managed Grafana with PSRule for Azure's `Azure.Grafana.*` rules: Version (Grafana 11 or later) and AvailabilityZone (zone redundancy in regions with zones).
- **New:** the Azure estate check covers PSRule for Azure's 10 `Azure.KeyVault.*` rules: SoftDelete, PurgeProtect (the existing purge-protection check), RBAC, Firewall, AccessPolicy (no All or Purge), Logs (AuditEvent or the audit/allLogs group), AutoRotationPolicy, and the Name, KeyName and SecretName naming rules. Keys and secrets are listed as metadata through Azure Resource Manager - never their values - with two calls per vault.
- **New:** the Azure estate check covers PSRule for Azure's `Azure.LogicApp.LimitHTTPTrigger` rule: a Logic App workflow with an HTTP request trigger must list its allowed caller IP ranges.
- **New:** the Azure estate check covers PSRule for Azure's 15 `Azure.Storage.*` rules: UseReplication, SecureTransfer, MinTLS and BlobPublicAccess (the existing storage checks, now with PSRule's FileStorage exception), Firewall, LocalAuth, BlobAccessType, SoftDelete, ContainerSoftDelete, FileShareSoftDelete, Defender.MalwareScan, Defender.DataScan (preview), Name, and - only when asked for with the new `StorageAccountNameFormat` and `StorageDefenderPerAccount` settings - Naming and DefenderCloud. Blob services, containers, file services and Defender for Storage settings are read over REST, up to three calls per account.
- **Changed:** `Invoke-AACPester` shows a Spectre.Console progress display instead of a spinner. It has a line for the Pester run, and the estate check adds lines for reading the estate and evaluating its rules, rule by rule, each with a bar, percentage and elapsed time. PowerShell's own web-request progress bars and per-call verbose output no longer draw over it. Without an interactive terminal (CI), each finished step is written as one plain line.
- **Changed:** the live Azure estate check moved from `Tests\AzureEstate.Tests.ps1` to `Checks\AzureEstate.Tests.ps1`, and `Invoke-AACPester` now defaults to the `Checks` folder. `Tests\` holds only the module's own unit tests and is not part of the published package.
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

