# Azure.Admin.Console 0.10.0

Azure admin reports and checks from PowerShell, over plain REST - no Az or Microsoft.Graph modules, no app registration. Get-AACAdvisorRecommendation: a consolidated, flattened Azure Advisor view (Cost, Security, Reliability, Operational excellence, Performance) as a colour-coded console view, objects, CSV or PDF. Get-AACFirewallRule: every Azure Firewall Policy rule, searchable by source, destination, port and protocol, as a colour-coded console view (Allow green, Deny red), objects, CSV or PDF. Show-AACResource and Show-AACCost: colourful console charts of your resources and subscription costs. Invoke-AACPester: runs any Pester v5 tests with a live progress display, a rich report and optional PDF - by default the bundled Azure estate check, 85 read-only checks (75 following PSRule for Azure) across Storage, Key Vault, API Management, Application Gateway and WAF, Service Bus, Application Insights, Managed Grafana, Logic Apps, networking, backup and diagnostics. PDF export needs Windows and PowerShell 7.4+.

Start with [about_Azure.Admin.Console](about_Azure.Admin.Console.md), or `Get-Help about_Azure.Admin.Console` once the module is imported.

## Commands

| Command | Synopsis |
|---|---|
| [Connect-AAC](Connect-AAC.md) | Signs in to Azure interactively using the OAuth 2.0 Authorization Code flow with PKCE and a loopback redirect - no Az or Microsoft.Graph module, and no app registration required by default. |
| [Disconnect-AAC](Disconnect-AAC.md) | Clears the current Azure sign-in from memory. |
| [Get-AACAdvisorRecommendation](Get-AACAdvisorRecommendation.md) | Gets a consolidated, flattened view of Azure Advisor recommendations (Resource Graph's advisorresources table): a Spectre.Console summary at the prompt, PowerShell objects down a pipeline, and optional CSV and PDF exports. |
| [Get-AACFirewallRule](Get-AACFirewallRule.md) | Gets every Azure Firewall Policy rule - DNAT, network and application: a colour-coded Spectre.Console view at the prompt, PowerShell objects down a pipeline, and optional CSV and PDF exports. |
| [Invoke-AACPester](Invoke-AACPester.md) | Runs any Pester v5 tests and renders the results with Spectre.Console: a table of every test, a tree grouped by file and block with the failures called out, a pass/fail chart, a summary and a banner. |
| [Show-AACCost](Show-AACCost.md) | Shows what your Azure subscriptions cost - month to date and the last few months - as colourful Spectre.Console charts, with optional CSV and PDF exports of the detail. |
| [Show-AACResource](Show-AACResource.md) | Shows how many Azure resources you have - by type, location, resource group or subscription - as a colourful Spectre.Console bar chart. |
