@{
    RootModule           = 'Azure.Admin.Console.psm1'
    ModuleVersion        = '0.12.0'
    GUID                 = '9923da59-cf92-4a4a-b855-f59a088a3f09'
    Author               = 'Chendrayan Venkatesan'
    CompanyName          = 'Golden Five Consulting'
    Copyright            = '(c) 2026 Chendrayan Venkatesan. Licensed under the MIT License.'
    Description          = 'Azure admin reports and checks from PowerShell, over plain REST - no Az or Microsoft.Graph modules, no app registration. Get-AACAdvisorRecommendation: a consolidated, flattened Azure Advisor view (Cost, Security, Reliability, Operational excellence, Performance). Get-AACFirewallRule: every Azure Firewall Policy rule, searchable by source, destination, port and protocol (Allow green, Deny red). Show-AACResource and Show-AACCost: your resources and subscription costs, with a full resource inventory. Invoke-AACPSRule: PSRule for Azure (500+ Well-Architected rules), the module''s own rules and your custom rules on the live estate, with rules excluded by name or wildcard. Invoke-AACApplicationInsightQuery: Application Insights exceptions (or any KQL query) from a Log Analytics workspace or Application Insights resource, flattened. Every command: a colourful console view, objects, CSV, PDF and interactive HTML reports. PDF export needs Windows and PowerShell 7.4+.'
    PowerShellVersion    = '7.2'
    CompatiblePSEditions = @('Core')

    # PSRule for Azure is the only PowerShell module dependency. The console UI comes from
    # the vendored .\lib\Spectre.Console.dll (loaded directly via Add-Type in the
    # root module, MIT licensed, see .\lib\Spectre.Console.LICENSE), and Azure
    # access comes from plain REST calls (Invoke-RestMethod) against Azure
    # Resource Manager - no Az.* or Microsoft.Graph.* modules anywhere. PDF
    # reports use the vendored PDFsharp + MigraDoc assemblies in .\lib\pdf
    # (MIT, see lib\pdf\SOURCES.md), loaded only on export after a SHA-256
    # check of every file.
    # PSRule.Rules.Azure (and PSRule, which it requires) powers
    # Invoke-AACPSRule. Importing it takes under a second and loads no
    # YamlDotNet.dll; the rules themselves run in a child pwsh process
    # (PSRule\PSRuleRunner.ps1), so PSRule's YamlDotNet never meets another
    # version of it (platyPS, powershell-yaml, Az.Aks) in the session.
    # Pester is not needed while Invoke-AACPester is parked (see Parked\).
    RequiredModules      = @(
        @{ ModuleName = 'PSRule.Rules.Azure'; ModuleVersion = '1.47.0' }
    )

    FunctionsToExport    = @(
        'Connect-AAC'
        'Disconnect-AAC'
        'Get-AACAdvisorRecommendation'
        'Get-AACFirewallRule'
        'Get-AACInventory'
        'Invoke-AACApplicationInsightQuery'
        'Invoke-AACPSRule'
        'Show-AACCost'
        'Show-AACResource'
        'Show-AACResourceMap'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags         = @('Azure', 'AzureAdvisor', 'AzureFirewall', 'CostManagement', 'Inventory', 'FirewallPolicy', 'ResourceGraph', 'Governance', 'Report', 'PDF', 'CSV', 'ApplicationInsights', 'LogAnalytics', 'KQL', 'PSRule', 'WellArchitected', 'HTML', 'Compliance', 'SpectreConsole', 'REST', 'PKCE', 'PSEdition_Core', 'Windows', 'Linux', 'MacOS')
            ProjectUri   = 'https://github.com/ChendrayanV/Azure.Admin.Console'
            LicenseUri   = 'https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/LICENSE'
            ReleaseNotes = 'v0.12.0 - NEW Get-AACInventory: the tenant as a tree (management groups > subscriptions > resource groups > resources) with counts and the Microsoft Defender for Cloud secure score and findings by severity in colour on every node; console tree, objects, CSV, PDF and interactive HTML (searchable tree, security controls and recommendations). NEW Show-AACResourceMap: a map of one or more resource groups in the browser - Azure icons, subscription > resource group > VNet > subnet boxes, network, dependency, peering, private link, route and private DNS connections, NSGs and route tables as chips with their rules, routes and risks, unattached resources flagged - saved as PNG or JPEG. Invoke-AACApplicationInsightQuery: -TableName reads any table; uses the documented Log Analytics and Application Insights query APIs; reads every row unless -Top; a missing table''s error names the tables that exist. FIXED: Show-AACCost -PdfPath failing when a subscription has no costs (now shown as No cost); Invoke-AACApplicationInsightQuery failing on an empty result and with -ApplicationInsightsName; Get-AACFirewallRule missing rules with one address plus one IP Group address. Errors are shown as a Spectre.Console panel with the step that failed and what to do. Full history: CHANGELOG.md.'
        }
    }
}
