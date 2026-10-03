@{
    RootModule           = 'Azure.Admin.Console.psm1'
    ModuleVersion        = '0.13.0'
    GUID                 = '9923da59-cf92-4a4a-b855-f59a088a3f09'
    Author               = 'Chendrayan Venkatesan'
    CompanyName          = 'Freelancer'
    Copyright            = '(c) 2026 Chendrayan Venkatesan. Licensed under the MIT License.'
    Description          = 'Azure admin reports and checks from PowerShell, over plain REST - no Az or Microsoft.Graph modules, no app registration. Get-AACAdvisorRecommendation: a consolidated, flattened Azure Advisor view (Cost, Security, Reliability, Operational excellence, Performance). Get-AACFirewallRule: every Azure Firewall Policy rule, searchable by source, destination, port and protocol (Allow green, Deny red). Show-AACResource and Show-AACCost: your resources and subscription costs, with a full resource inventory. Invoke-AACPSRule: PSRule for Azure (500+ Well-Architected rules), the module''s own rules and your custom rules on the live estate, with rules excluded by name or wildcard. Invoke-AACApplicationInsightQuery: Application Insights exceptions (or any KQL query) from a Log Analytics workspace or Application Insights resource, flattened. Get-AACInventory: the tenant as a tree (management groups, subscriptions, resource groups, resources) with Defender for Cloud secure scores and costs. Get-AACNetworkSecurityGroup: a detailed NSG assessment with findings by severity. Show-AACResourceMap: an interactive diagram of resource groups in the browser, saved as PNG or JPEG. Get-AACPolicyState: Azure Policy compliance for every resource, by management group, subscription or resource group. Get-AACSkuAvailability: which VM sizes you can use for VMs or AKS node pools in a region and its zones - restrictions, vCPU quota, AKS rules - and why not. Get-AACSecurityPosture: Defender for Cloud and Azure Policy - secure scores, recommendations, alerts, plans, regulatory and policy compliance. Get-AACEntraGroupMembership: Entra ID groups and everyone in them, nested groups included, one row per group and member (Microsoft Graph). Get-AACAssignedPolicy: every Azure Policy assignment with the default, assigned and effective value of each parameter and the resource types the policy applies to. Get-AACStorageAccountContainerSize: every blob container''s size, access tiers and largest blobs, read in parallel. Every command: a colourful console view, objects, CSV and interactive HTML reports, and most a PDF. PDF export needs Windows and PowerShell 7.4+.'
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
        'Invoke-AACApplicationInsightQuery'
        'Invoke-AACLogAnalyticsWorkspaceAssessment'
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
            Tags         = @('Azure', 'AzureAdvisor', 'AzureFirewall', 'CostManagement', 'Inventory', 'FirewallPolicy', 'ResourceGraph', 'Governance', 'EntraID', 'MicrosoftGraph', 'Groups', 'DefenderForCloud', 'Storage', 'BlobStorage', 'AzurePolicy', 'SecureScore', 'Report', 'PDF', 'CSV', 'ApplicationInsights', 'LogAnalytics', 'KQL', 'PSRule', 'WellArchitected', 'HTML', 'Compliance', 'SpectreConsole', 'REST', 'PKCE', 'PSEdition_Core', 'Windows', 'Linux', 'MacOS')
            ProjectUri   = 'https://github.com/ChendrayanV/Azure.Admin.Console'
            LicenseUri   = 'https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/LICENSE'
            ReleaseNotes = 'v0.13.0 - NEW Get-AACAssignedPolicy: every Azure Policy assignment and its parameters, one row per assignment and parameter - default, assigned and effective value, where it comes from, allowed values - with the resource types the policy applies to (its rule''s type conditions, parameters resolved; for an initiative, the member policies using each parameter); -SubscriptionId or -ManagementGroupId include assignments inherited from management groups; a few Resource Graph queries, not one call per assignment; console, objects, CSV and HTML. NEW Get-AACStorageAccountContainerSize: every blob container''s blobs, size per access tier, snapshots, versions and deleted blobs, newest change and largest blobs; containers read in parallel (-ThrottleLimit), 5,000 blobs a page, added up as they arrive by a parser compiled on first use (about 275,000 blobs a second), memory flat; -AuthMode EntraId (Storage Blob Data Reader), AccountSas (4-hour read-only SAS, in memory only) or Auto; what can''t be read is reported with the reason and what to do; console, objects, CSV (-CsvPath, -BlobCsvPath) and HTML. NEW Get-AACSkuAvailability: which VM sizes you can use for virtual machines or AKS node pools in a region and its availability zones - the subscription''s region and zone restrictions, family and regional vCPU quota for -NodeCount, AKS''s rules, the zone mapping, an AKS cluster''s node pools (-ClusterName) - and why not; read-only REST, nothing deployed; -Series, -Sku, -Architecture, -Zone; console, objects, CSV, HTML and PDF. NEW Get-AACPolicyState: Azure Policy compliance for every resource (one KQL query) - by -ManagementGroupId, -SubscriptionId, -ResourceGroupName, -ComplianceState; one row per resource and policy with initiative, assignment, scope, effect; compliance per resource, assignment, subscription, resource group and policy; console, objects, CSV, HTML and PDF. NEW Get-AACInventory -Insight: VM sizes, operating systems, power states, Azure and Arc, storage replication, database tiers, tag coverage; what needs attention (unattached disks, unused public IPs and NICs, VMs stopped but billed, classic resources, nearly full subnets, connections down) with its cost; subnet IP usage; donut charts in HTML. Get-AACNetworkSecurityGroup counts the VMs each NSG protects. NEW Get-AACSecurityPosture: Defender for Cloud and Azure Policy in one report - secure scores and controls, recommendations with their control and remediation link, active alerts, Defender plans, regulatory compliance traced to failing resources, and policy compliance per assignment - one list of findings; -Section, -ResourceGroupName, -Tag, -Standard; console, objects, CSV, HTML and PDF. NEW Get-AACEntraGroupMembership: Entra ID groups (-GroupName, -GroupNameStartsWith, or all) and everyone in them, direct and through nested groups followed to the end, flattened to one row per group and member (group type and source; member type, UPN, member or guest, enabled or disabled; Direct, Nested with the path, or Empty) - console view with member trees, objects, CSV (-CsvPath or -OutputPath), interactive HTML and PDF; uses the Connect-AAC sign-in for Microsoft Graph (no second prompt), reads 8 at a time. NEW Get-AACNetworkSecurityGroup: a detailed assessment of network security groups (all of them by default, or by -SubscriptionId, -ResourceGroupName and -Name, wildcards allowed): metadata, the subnets and NICs each is applied to, every rule in evaluation order (5-tuple and action, application security groups by name), diagnostic settings and their destinations, NSG and virtual network flow logs with retention and Traffic Analytics. Findings by severity with what to do: rules open to the internet (every port, management and database ports, wide ranges, ICMP), everything allowed from the virtual network, shadowed rules, unassociated NSGs, subnet and NIC NSGs that disagree (both evaluated as Azure does), missing or short-lived flow logs, NSG flow logs retiring on 30 September 2027, missing diagnostic settings, the rule limit. Console view, AAC.NetworkSecurityGroup objects, CSV of every rule, interactive HTML (NSGs, findings, rules, associations, logging) and PDF (a page per NSG with its rules). NEW Get-AACInventory -Cost: the actual cost month to date and last month of every resource, rolled up to resource groups, subscriptions, management groups and the tenant - one Cost Management query for the tenant root group when the billing account allows it, otherwise one per subscription, 3 at a time; deleted resources and charges not tied to a resource under their subscription; never converted between currencies; in the console, HTML, PDF and objects. NEW AAC.Resource.Naming: PSRule naming checks for resource groups and about 30 resource types against the Cloud Adoption Framework abbreviations, with no setting needed (AAC_NAMING_PATTERNS and AAC_NAMING_IGNORE to change them); a naming-only run reads just those types and no child settings. Tag rules read their tags from Get-AACTagDefault in PSRule\Rules\AAC.Tags.Rule.ps1, and a tag rule with no tags to check says so. NOTHING CUT OFF: the PSRule view lists every failing resource (up to 50 per rule) with its whole reason; object tables at the prompt wrap long text (Azure.Admin.Console.Format.ps1xml); the NSG, inventory and Application Insights views wrap and list everything. Invoke-AACPSRule reads only names, types and tags when only AAC.* rules run (-NoExpand for your own), and refuses a -Rule that is a file path or matches no rule. FASTER: every Azure call shares one pooled HTTPS connection with the same retry rules; independent Resource Graph queries run in parallel (Get-AACInventory, Get-AACNetworkSecurityGroup, Get-AACFirewallRule, Get-AACAdvisorRecommendation, Show-AACResource, Show-AACResourceMap); NSG diagnostic settings are read 12 at a time; Show-AACCost reads 3 subscriptions at a time. FIXED: piping any command to Select-Object -First no longer fails with "The pipeline has been stopped." - the command just stops and the script carries on (Ctrl+C still stops everything). Invoke-AACPSRule reads resource settings in parallel (12 at a time, a level of children at a time): API Management services with many APIs and operations take seconds instead of minutes. Full history: CHANGELOG.md.'
        }
    }
}
