@{
    RootModule           = 'Azure.Admin.Console.psm1'
    ModuleVersion        = '0.14.4'
    GUID                 = '9923da59-cf92-4a4a-b855-f59a088a3f09'
    Author               = 'Chendrayan Venkatesan'
    CompanyName          = 'Freelancer'
    Copyright            = '(c) 2026 Chendrayan Venkatesan. Licensed under the MIT License.'
    Description          = 'Azure administration from PowerShell over plain REST - no Az or Microsoft.Graph modules, no app registration. Inventory and resource export, cost, Advisor, security (Defender for Cloud, alerts, attack paths, access reviews, legacy authentication), Azure Policy and compliance, operations and troubleshooting (Resource Health, failed operations, load balancers, private endpoints, unused resources, diagnostic bundles), networks, AKS, Log Analytics and Microsoft 365 - each command with a console view, objects, and CSV, HTML and PDF reports. Documentation: https://github.com/ChendrayanV/Azure.Admin.Console/tree/main/docs'
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
        'Export-AACDiagnosticBundle'
        'Export-AACResource'
        'Export-AACWafQuestionnaire'
        'Get-AACAccessReview'
        'Get-AACAdvisorRecommendation'
        'Get-AACAssignedPolicy'
        'Get-AACAttackPath'
        'Get-AACChangeHistory'
        'Get-AACComplianceGap'
        'Get-AACConfigurationDrift'
        'Get-AACCostAnomaly'
        'Get-AACDependencyGraph'
        'Get-AACDiagnosticSetting'
        'Get-AACEntraGroupMembership'
        'Get-AACFailoverReadiness'
        'Get-AACFirewallRule'
        'Get-AACKeyVaultInsight'
        'Get-AACInventory'
        'Get-AACLegacyAuthentication'
        'Get-AACLoadBalancerHealth'
        'Get-AACNetworkSecurityGroup'
        'Get-AACOrphanedIdentity'
        'Get-AACPolicyState'
        'Get-AACPrivateEndpoint'
        'Get-AACResourceError'
        'Get-AACResourceHealth'
        'Get-AACResourceUtilization'
        'Get-AACSecurityAlert'
        'Get-AACSecurityPosture'
        'Get-AACSkuAvailability'
        'Get-AACStorageAccountContainerSize'
        'Get-AACTerraformPlan'
        'Get-AACUnusedResource'
        'Get-AACWafCheck'
        'Invoke-AACAksAssessment'
        'Invoke-AACApplicationInsightQuery'
        'Invoke-AACAssessment'
        'Invoke-AACDefenderAssessment'
        'Invoke-AACHealthCheck'
        'Invoke-AACLogAnalyticsWorkspaceAssessment'
        'Invoke-AACM365Assessment'
        'Invoke-AACPolicyAssessment'
        'Invoke-AACPSRule'
        'Invoke-AACVirtualNetworkAssessment'
        'Invoke-AACWafAssessment'
        'Show-AACApplicationGatewayMap'
        'Show-AACCost'
        'Show-AACDashboard'
        'Show-AACJson'
        'Show-AACNetworkTopology'
        'Show-AACResource'
        'Show-AACResourceMap'
        'Test-AACGoLiveReadiness'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags         = @('Azure', 'AzureAdvisor', 'AzureFirewall', 'CostManagement', 'Inventory', 'FirewallPolicy', 'ResourceGraph', 'Governance', 'EntraID', 'MicrosoftGraph', 'Groups', 'DefenderForCloud', 'Storage', 'BlobStorage', 'AzurePolicy', 'SecureScore', 'Report', 'PDF', 'CSV', 'ApplicationInsights', 'LogAnalytics', 'KQL', 'PSRule', 'WellArchitected', 'HTML', 'Compliance', 'SpectreConsole', 'Dashboard', 'ResourceHealth', 'ServiceHealth', 'PrivateEndpoint', 'PrivateLink', 'LoadBalancer', 'ApplicationGateway', 'SecurityAlerts', 'ActivityLog', 'Identity', 'Tags', 'Export', 'JSON', 'REST', 'PKCE', 'PSEdition_Core', 'Windows', 'Linux', 'MacOS')
            ProjectUri   = 'https://github.com/ChendrayanV/Azure.Admin.Console'
            LicenseUri   = 'https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/LICENSE'
            ReleaseNotes = 'v0.14.4 - FIXED Export-AACResource: resources whose type has no details table entry (such as action groups) broke the export; their Details are now empty. v0.14.3 - NEW Export-AACResource: every resource with its subscription, management group path, resource group, tags as columns and key settings per type, to CSV, HTML and PDF, filtered in Resource Graph (type, group, name, location, tag, missing tag, KQL) and read in parallel. NEW Get-AACSecurityAlert (the Get-AzSecurityAlert equivalent, across every subscription). NEW for operations and troubleshooting (issue 8): Get-AACResourceHealth, Get-AACUnusedResource, Get-AACResourceError, Get-AACPrivateEndpoint, Get-AACLoadBalancerHealth, Get-AACLegacyAuthentication, Get-AACOrphanedIdentity, Export-AACDiagnosticBundle. HTML reports about five times faster. FIXED: Defender alert queries failed to parse in Get-AACSecurityPosture and Invoke-AACDefenderAssessment; an empty tab bar was drawn over the HTML tiles; console paging was off in VS Code. Full history: CHANGELOG.md.'
        }
    }
}
