@{
    RootModule           = 'Azure.Admin.Console.psm1'
    ModuleVersion        = '0.14.8'
    GUID                 = '9923da59-cf92-4a4a-b855-f59a088a3f09'
    Author               = 'Chendrayan Venkatesan'
    CompanyName          = 'Freelancer'
    Copyright            = '(c) 2026 Chendrayan Venkatesan. Licensed under the MIT License.'
    Description          = 'Azure administration from PowerShell over plain REST - no Az or Microsoft.Graph modules, no app registration. Inventory and resource export, cost, Advisor, security (Defender for Cloud, alerts, attack paths, access reviews, legacy authentication), Azure Policy and compliance, operations and troubleshooting (Resource Health, failed operations, load balancers, private endpoints, unused resources, diagnostic bundles), networks, AKS, Log Analytics, Microsoft 365 and Entra ID (application permissions, groups), and Azure DevOps (pipelines, the tools they run, security posture, delivery metrics) - each command with a console view, objects, and CSV, HTML and PDF reports. Documentation: https://github.com/ChendrayanV/Azure.Admin.Console/tree/main/docs'
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
        'Export-AACDiagram'
        'Export-AACResource'
        'Export-AACTerraform'
        'Export-AACWafQuestionnaire'
        'Get-AACAccessReview'
        'Invoke-AACADOAssessment'
        'New-AACArchitectureBrief'
        'Get-AACArchitecturePattern'
        'New-AACArchitectureDesign'
        'Test-AACArchitectureDesign'
        'New-AACArchitectureDiagram'
        'Export-AACArchitectureDecision'
        'Get-AACAdvisorRecommendation'
        'Get-AACApplicationPermission'
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
        'Get-AACGovernanceSetting'
        'Get-AACGovernanceChange'
        'Get-AACInventory'
        'Get-AACIPAMReport'
        'Get-AACLegacyAuthentication'
        'Get-AACLoadBalancerHealth'
        'Get-AACNetworkHealth'
        'Get-AACNetworkSecurityGroup'
        'Get-AACOrphanedIdentity'
        'Get-AACPolicyRemediation'
        'Get-AACPolicyState'
        'Get-AACPrivateEndpoint'
        'Get-AACResourceError'
        'Get-AACResourceHealth'
        'Get-AACResourceLock'
        'Get-AACResourceUtilization'
        'Get-AACRoleAssignment'
        'Get-AACSecurityAlert'
        'Get-AACSecurityPosture'
        'Get-AACServicePrincipalInsight'
        'Get-AACSkuAvailability'
        'Get-AACStorageAccountContainerSize'
        'Get-AACTagUsage'
        'Get-AACTerraformPlan'
        'Get-AACUnusedResource'
        'Get-AACWafCheck'
        'Invoke-AACAksAssessment'
        'Invoke-AACApplicationInsightQuery'
        'Invoke-AACTenantAssessment'
        'Invoke-AACCosmosDBAssessment'
        'Invoke-AACDefenderAssessment'
        'Invoke-AACFunctionAppAssessment'
        'Invoke-AACGovernanceAssessment'
        'Invoke-AACHealthCheck'
        'Invoke-AACLogAnalyticsWorkspaceAssessment'
        'Invoke-AACM365Assessment'
        'Invoke-AACPolicyAssessment'
        'Invoke-AACPSRule'
        'Invoke-AACServiceBusAssessment'
        'Show-AACServiceBusEntity'
        'Invoke-AACStorageAccountAssessment'
        'Invoke-AACVirtualNetworkAssessment'
        'Invoke-AACWafAssessment'
        'New-AACApplicationPermission'
        'Show-AACApplicationGatewayMap'
        'Show-AACCost'
        'Show-AACDashboard'
        'Show-AACJson'
        'Show-AACManagementGroupMap'
        'Show-AACNetworkTopology'
        'Show-AACResource'
        'Show-AACResourceMap'
        'Test-AACAlzPolicy'
        'Test-AACAzureLimit'
        'Test-AACGoLiveReadiness'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags         = @('Azure', 'AzureAdvisor', 'AzureFirewall', 'CostManagement', 'Inventory', 'FirewallPolicy', 'ResourceGraph', 'Governance', 'EntraID', 'MicrosoftGraph', 'Groups', 'DefenderForCloud', 'Storage', 'BlobStorage', 'AzurePolicy', 'SecureScore', 'Report', 'PDF', 'CSV', 'ApplicationInsights', 'LogAnalytics', 'KQL', 'PSRule', 'WellArchitected', 'HTML', 'Compliance', 'SpectreConsole', 'Dashboard', 'ResourceHealth', 'ServiceHealth', 'PrivateEndpoint', 'PrivateLink', 'LoadBalancer', 'ApplicationGateway', 'SecurityAlerts', 'ActivityLog', 'Identity', 'AzureDevOps', 'DevOps', 'Pipelines', 'Tags', 'Export', 'JSON', 'REST', 'PKCE', 'PSEdition_Core', 'Windows', 'Linux', 'MacOS')
            ProjectUri   = 'https://github.com/ChendrayanV/Azure.Admin.Console'
            LicenseUri   = 'https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/LICENSE'
            ReleaseNotes = 'v0.14.8 - NEW Architecture area: New-AACArchitectureBrief, Get-AACArchitecturePattern, New-AACArchitectureDesign, Test-AACArchitectureDesign, New-AACArchitectureDiagram (multi-page draw.io with Azure icons), Export-AACArchitectureDecision. BREAKING Invoke-AACAssessment renamed Invoke-AACTenantAssessment (audience tabs, WAF, FinOps, -HtmlPath/-PdfPath/-CsvPath; -Output removed); Get-AACADOInventory renamed Invoke-AACADOAssessment (SBOM tab). Tabbed HTML and PDF for Invoke-AACLogAnalyticsWorkspaceAssessment. See CHANGELOG.md. v0.14.7 - NEW Get-AACADOInventory (Azure DevOps: pipelines, tools with evidence, security posture, delivery metrics), Get-AACApplicationPermission, New-AACApplicationPermission (Entra group rights scoped to an administrative unit). CHANGED the module is organised in child areas (Core, Azure, M365, DevOps); faster import. FIXED Get-AACChangeHistory alerts for windows older than 14 days. Includes everything in 0.14.6-preview1. v0.14.6 - NEW governance across the tenant (11 commands, Invoke-AACGovernanceAssessment workbook), Invoke-AACServiceBusAssessment and Invoke-AACCosmosDBAssessment, Export-AACTerraform (existing resources as Terraform, batches, resume, azapi fallback, terraform plan check), editable draw.io diagrams (Export-AACDiagram), Show-AACDashboard second edition (scores, security, policy, governance, cost, what to do next). Pre-release preview1. v0.14.5 - NEW Invoke-AACWafAssessment (Well-Architected, five pillars, heat maps, questionnaire, trend), Test-AACGoLiveReadiness (go-live gate, -FailOnGap for pipelines), Export-AACWafQuestionnaire, Get-AACWafCheck, Get-AACKeyVaultInsight (the Key Vault workbook plus saturation, posture, callers and expiring objects), Show-AACApplicationGatewayMap (connection flow, health, findings), Get-AACNetworkHealth (ExpressRoute, gateways, VPN, Azure Firewall, NAT - with timestamps), Invoke-AACStorageAccountAssessment (the Storage accounts workbook plus availability, security, data protection and cost), Show-AACNetworkTopology (hub and spoke or hierarchy). Heat maps in every report. Get-AACDiagnosticSetting -Status. Entra group membership: nested members expanded, service principals, owners, created and membership type, clearer reports. FIXED false VNet peerings on maps. v0.14.4 - FIXED Export-AACResource: resources whose type has no details table entry (such as action groups) broke the export; their Details are now empty. v0.14.3 - NEW Export-AACResource: every resource with its subscription, management group path, resource group, tags as columns and key settings per type, to CSV, HTML and PDF, filtered in Resource Graph (type, group, name, location, tag, missing tag, KQL) and read in parallel. NEW Get-AACSecurityAlert (the Get-AzSecurityAlert equivalent, across every subscription). NEW for operations and troubleshooting (issue 8): Get-AACResourceHealth, Get-AACUnusedResource, Get-AACResourceError, Get-AACPrivateEndpoint, Get-AACLoadBalancerHealth, Get-AACLegacyAuthentication, Get-AACOrphanedIdentity, Export-AACDiagnosticBundle. HTML reports about five times faster. FIXED: Defender alert queries failed to parse in Get-AACSecurityPosture and Invoke-AACDefenderAssessment; an empty tab bar was drawn over the HTML tiles; console paging was off in VS Code. Full history: CHANGELOG.md.'
        }
    }
}
