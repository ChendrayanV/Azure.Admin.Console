@{
    RootModule           = 'Azure.Admin.Console.psm1'
    ModuleVersion        = '0.14.1'
    GUID                 = '9923da59-cf92-4a4a-b855-f59a088a3f09'
    Author               = 'Chendrayan Venkatesan'
    CompanyName          = 'Freelancer'
    Copyright            = '(c) 2026 Chendrayan Venkatesan. Licensed under the MIT License.'
    Description          = 'Azure admin reports and checks from PowerShell, over plain REST - no Az or Microsoft.Graph modules, no app registration. Get-AACAdvisorRecommendation: a consolidated, flattened Azure Advisor view (Cost, Security, Reliability, Operational excellence, Performance). Get-AACFirewallRule: every Azure Firewall Policy rule, searchable by source, destination, port and protocol (Allow green, Deny red). Show-AACResource and Show-AACCost: your resources and subscription costs, with a full resource inventory. Invoke-AACPSRule: PSRule for Azure (500+ Well-Architected rules), the module''s own rules and your custom rules on the live estate, with rules excluded by name or wildcard. Invoke-AACApplicationInsightQuery: Application Insights exceptions (or any KQL query) from a Log Analytics workspace or Application Insights resource, flattened. Get-AACInventory: the tenant as a tree (management groups, subscriptions, resource groups, resources) with Defender for Cloud secure scores and costs. Get-AACNetworkSecurityGroup: a detailed NSG assessment with findings by severity. Show-AACResourceMap: an interactive diagram of resource groups in the browser, saved as PNG or JPEG. Get-AACPolicyState: Azure Policy compliance for every resource, by management group, subscription or resource group. Get-AACSkuAvailability: which VM sizes you can use for VMs or AKS node pools in a region and its zones - restrictions, vCPU quota, AKS rules - and why not. Get-AACSecurityPosture: Defender for Cloud and Azure Policy - secure scores, recommendations, alerts, plans, regulatory and policy compliance. Get-AACEntraGroupMembership: Entra ID groups and everyone in them, nested groups included, one row per group and member (Microsoft Graph). Get-AACAssignedPolicy: every Azure Policy assignment with the default, assigned and effective value of each parameter and the resource types the policy applies to. Get-AACStorageAccountContainerSize: every blob container''s size, access tiers and largest blobs, read in parallel. Invoke-AACDefenderAssessment: Microsoft Defender for Cloud end to end - recommendations, attack paths, alerts, inventory, vulnerabilities, posture, compliance and settings - in a tabbed HTML report. Invoke-AACPolicyAssessment: Azure Policy assessed as a whole, initiatives opened up to their member policies. Every command: a colourful console view, objects, CSV and interactive HTML reports, and most a PDF. PDF export needs Windows and PowerShell 7.4+.'
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

    # How the objects look at the prompt: long text wrapped, not cut off.
    FormatsToProcess     = @('Azure.Admin.Console.Format.ps1xml')

    FunctionsToExport    = @(
        'Connect-AAC'
        'Deploy-AACStorageAccount'
        'Disconnect-AAC'
        'Get-AACAdvisorRecommendation'
        'Get-AACAssignedPolicy'
        'Get-AACDiagnosticSetting'
        'Get-AACEntraGroupMembership'
        'Get-AACFirewallRule'
        'Get-AACInventory'
        'Get-AACNetworkSecurityGroup'
        'Get-AACPolicyState'
        'Get-AACSecurityPosture'
        'Get-AACSkuAvailability'
        'Get-AACStorageAccountContainerSize'
        'Get-AACTerraformPlan'
        'Invoke-AACAksAssessment'
        'Invoke-AACApplicationInsightQuery'
        'Invoke-AACAssessment'
        'Invoke-AACDefenderAssessment'
        'Invoke-AACLogAnalyticsWorkspaceAssessment'
        'Invoke-AACPolicyAssessment'
        'Invoke-AACPSRule'
        'Invoke-AACVirtualNetworkAssessment'
        'Show-AACCost'
        'Show-AACResource'
        'Show-AACResourceMap'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags         = @('Azure', 'AzureAdvisor', 'AzureFirewall', 'CostManagement', 'Inventory', 'FirewallPolicy', 'ResourceGraph', 'Governance', 'EntraID', 'MicrosoftGraph', 'Groups', 'DefenderForCloud', 'Storage', 'BlobStorage', 'AzurePolicy', 'SecureScore', 'Report', 'PDF', 'CSV', 'ApplicationInsights', 'LogAnalytics', 'KQL', 'PSRule', 'WellArchitected', 'HTML', 'Compliance', 'SpectreConsole', 'REST', 'PKCE', 'PSEdition_Core', 'Windows', 'Linux', 'MacOS')
            ProjectUri   = 'https://github.com/ChendrayanV/Azure.Admin.Console'
            LicenseUri   = 'https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/LICENSE'
            ReleaseNotes = 'v0.14.1 - NEW Invoke-AACDefenderAssessment: Microsoft Defender for Cloud across subscriptions - every recommendation (unhealthy, healthy and not applicable resources, risk level), attack paths step by step, security alerts with MITRE tactics and remediation, inventory with each resource''s plan coverage, vulnerabilities (CVEs), secure score controls, Defender plans with extensions, regulatory compliance and environment settings (contacts, notifications, integrations, connectors, just-in-time) - with findings on how Defender is set up; console, object, CSV and a tabbed HTML report. Get-AACAssignedPolicy -ExpandPolicySet and Invoke-AACPolicyAssessment open up initiatives: each member policy with its effect (overrides included) and the value every parameter ends up with. HTML reports: each table scrolls in its own box (sticky header row and first column), Fit/Centered width and Compact/Comfortable rows that follow the screen, a details panel with every field of a row, and tabs for large reports. Full history: CHANGELOG.md.'
        }
    }
}
