# Azure.Admin.Console 0.10.0

Azure admin reports and checks from PowerShell, over plain REST - no Az or Microsoft.Graph modules, no app registration. Get-AACAdvisorRecommendation: a consolidated, flattened Azure Advisor view (Cost, Security, Reliability, Operational excellence, Performance). Get-AACFirewallRule: every Azure Firewall Policy rule, searchable by source, destination, port and protocol (Allow green, Deny red). Show-AACResource and Show-AACCost: your resources and subscription costs, with a full resource inventory. Invoke-AACPSRule: PSRule for Azure (500+ Well-Architected rules), the module's own rules and your custom rules on the live estate, with rules excluded by name or wildcard. Invoke-AACApplicationInsightQuery: Application Insights exceptions (or any KQL query) from a Log Analytics workspace or Application Insights resource, flattened. Every command: a colourful console view, objects, CSV, PDF and interactive HTML reports. PDF export needs Windows and PowerShell 7.4+.

Start with [about_Azure.Admin.Console](about_Azure.Admin.Console.md), or `Get-Help about_Azure.Admin.Console` once the module is imported. Every command also has full help in PowerShell: `Get-Help <command> -Full`.

## Commands

| Command | Synopsis |
|---|---|
| [Connect-AAC](Connect-AAC.md) | Signs in to Azure interactively using the OAuth 2.0 Authorization Code flow with PKCE and a loopback redirect - no Az or Microsoft.Graph module, and no app registration required by default. |
| [Disconnect-AAC](Disconnect-AAC.md) | Clears the current Azure sign-in from memory. |
| [Get-AACAdvisorRecommendation](Get-AACAdvisorRecommendation.md) | Gets a consolidated, flattened view of Azure Advisor recommendations (Resource Graph's advisorresources table): a Spectre.Console summary at the prompt, PowerShell objects down a pipeline, and optional CSV PDF and interactive HTML exports. |
| [Get-AACFirewallRule](Get-AACFirewallRule.md) | Gets every Azure Firewall Policy rule - DNAT, network and application: a colour-coded Spectre.Console view at the prompt, PowerShell objects down a pipeline, and optional CSV, PDF and interactive HTML exports. |
| [Invoke-AACApplicationInsightQuery](Invoke-AACApplicationInsightQuery.md) | Queries Application Insights - the exceptions of the last few hours by default, or any KQL query - from a Log Analytics workspace or an Application Insights resource, with a Spectre.Console view, flattened objects, and CSV and interactive HTML exports. |
| [Invoke-AACPSRule](Invoke-AACPSRule.md) | Checks your live Azure estate with PSRule for Azure - its Azure Well-Architected Framework rules, the module's own rules and your custom rules - with a console view, objects, and CSV, PDF and interactive HTML reports. |
| [Show-AACCost](Show-AACCost.md) | Shows what your Azure subscriptions cost - month to date and the last few months - as colourful Spectre.Console charts, with optional CSV, PDF and interactive HTML exports of the detail. |
| [Show-AACResource](Show-AACResource.md) | Shows how many Azure resources you have - by type, location, resource group or subscription - as a colourful Spectre.Console bar chart. |
