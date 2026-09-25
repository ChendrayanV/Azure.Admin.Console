# Azure.Admin.Console 0.10.0

Azure admin reports and checks from PowerShell, over plain REST - no Az or Microsoft.Graph modules, no app registration. Get-AACAdvisorRecommendation: a consolidated, flattened Azure Advisor view (Cost, Security, Reliability, Operational excellence, Performance) as a colour-coded console view, objects, CSV or PDF. Export-AACFirewallRule: every Azure Firewall Policy rule as objects, CSV or PDF. Invoke-AACPester: runs any Pester v5 tests with a live progress display, a rich report and optional PDF - by default the bundled Azure estate check, 85 read-only checks (75 following PSRule for Azure) across Storage, Key Vault, API Management, Application Gateway and WAF, Service Bus, Application Insights, Managed Grafana, Logic Apps, networking, backup and diagnostics. PDF export needs Windows and PowerShell 7.4+.

Start with [about_Azure.Admin.Console](about_Azure.Admin.Console.md), or `Get-Help about_Azure.Admin.Console` once the module is imported.

## Commands

| Command | Synopsis |
|---|---|
| [Connect-AAC](Connect-AAC.md) | Signs in to Azure interactively using the OAuth 2.0 Authorization Code flow with PKCE and a loopback redirect - no Az or Microsoft.Graph module, and no app registration required by default. |
| [Disconnect-AAC](Disconnect-AAC.md) | Clears the current Azure sign-in from memory. |
| [Export-AACFirewallRule](Export-AACFirewallRule.md) | Exports every Azure Firewall Policy rule - DNAT, network and application - as PowerShell objects, a CSV file and/or a PDF report. |
| [Export-AACPesterReport](Export-AACPesterReport.md) | Writes a Pester v5 result as a PDF report: a summary page, pass/fail counts per check, and every test result with the reason for each failure. |
| [Get-AACAdvisorRecommendation](Get-AACAdvisorRecommendation.md) | Gets a consolidated, flattened view of Azure Advisor recommendations (Resource Graph's advisorresources table): a Spectre.Console summary at the prompt, PowerShell objects down a pipeline, and optional CSV and PDF exports. |
| [Invoke-AACPester](Invoke-AACPester.md) | Runs any Pester v5 tests and renders the results with Spectre.Console: a table of every test, a tree grouped by file and block with the failures called out, a pass/fail chart, a summary and a banner. |
