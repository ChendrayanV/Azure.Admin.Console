#Requires -Version 7.2
Set-StrictMode -Version Latest

$moduleRoot = $PSScriptRoot

# $PSScriptRoot inside a dot-sourced *.ps1 resolves to that file's own folder, not
# the module root, so any function that needs the module root (e.g. to find the
# bundled Tests folder or the vendored Spectre.Console.dll) reads this instead.
$script:AACModuleRoot = $moduleRoot

# The active sign-in, set by Connect-AAC and read/refreshed by Get-AACAccessToken.
# Module-scoped, so its access and refresh tokens can't be read (or
# replaced) by other code in the session - only the module's own functions
# see it. Declared here rather than left implicitly $null because
# Set-StrictMode -Version Latest treats reading a variable that was never
# assigned as an error.
$script:AACSession = $null

# Set by Import-AACPdfLibrary once the PDF assemblies in .\lib\pdf are loaded
# (only when a PDF report is first exported).
$script:AACPdfLibraryLoaded = $false

# The live Spectre.Console progress display (Invoke-AACProgress) and its
# tasks by Id (Update-AACProgress); $null when no display is running.
$script:AACProgressContext = $null
$script:AACProgressTasks = @{}
# True while Invoke-AACProgress runs without a live display (output is not
# an interactive terminal): finished tasks are then written as plain lines.
$script:AACProgressPlain = $false
# Set once Invoke-AACProgress has told the user how to get the Unicode display.
$script:AACUnicodeHintShown = $false
# The resource map's page template, ELK and icons (Get-AACResourceMapAsset),
# read and checked once per session.
$script:AACResourceMapAsset = $null
# The Azure icon set (Get-AACAzureIconSet), shared by the resource map and the
# architecture diagrams; read and checked once per session.
$script:AACAzureIconSet = $null
# The HttpClient Invoke-AACArmParallel sends its requests through - one per
# session, so connections are pooled and reused.
$script:AACHttpClient = $null

# This module renders its UI with Spectre.Console (https://spectreconsole.net)
# loaded directly from the vendored DLL in .\lib - no PowerShell wrapper module
# in between. That DLL must be loaded before anything else, because a function
# whose parameters are typed as a Spectre.Console type (e.g. [Spectre.Console.Color])
# needs that type resolvable at *parse* time, not just when the function runs.
$spectreConsolePath = Join-Path -Path $moduleRoot -ChildPath 'lib/Spectre.Console.dll'
if (-not (Test-Path -LiteralPath $spectreConsolePath)) {
    throw "Azure Admin Console could not find its vendored Spectre.Console.dll at '$spectreConsolePath'. Reinstall the module."
}
# Pinned SHA-256 of the vendored Spectre.Console 0.49.1 - a swapped or
# tampered DLL is refused rather than loaded. Update it together with the DLL.
$spectreConsoleHash = '26BB8DC1CA36D7ADA9979FFC9DDF658FF48068CEE0154AC540A8870FA7434359'
# .NET's SHA-256 rather than Get-FileHash: the same check, about 70 ms sooner at every import.
if ([System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.IO.File]::ReadAllBytes($spectreConsolePath))) -ne $spectreConsoleHash) {
    throw "Azure Admin Console refused to load '$spectreConsolePath': its SHA-256 hash doesn't match the Spectre.Console.dll this module was released with. Reinstall the module."
}
try {
    Add-Type -Path $spectreConsolePath -ErrorAction Stop
}
catch {
    throw "Azure Admin Console failed to load Spectre.Console.dll: $($_.Exception.Message)"
}

# The module is a parent with child areas under src\ - Core (sign-in, the REST
# helpers, views and reports), then Azure, M365 and DevOps - each with its own
# Public\ (one exported command per file) and Private\ (helpers). An area may
# use Core and itself, not another area (Tests\Core\Module.Tests.ps1 checks
# it); src\<Area>\area.psd1 says what the area is and its load order.
#
# The packaged module (build.ps1) carries every function in one file, which
# loads 1.5-2 seconds faster than ~400 files dot-sourced one by one; it also
# sets $publicFunctionNames. The repository loads the files themselves - area
# by area (Core first), each area's Private helpers before its commands.
$bundlePath = Join-Path -Path $moduleRoot -ChildPath 'Azure.Admin.Console.Functions.ps1'
if (Test-Path -LiteralPath $bundlePath) {
    try {
        . $bundlePath
    }
    catch {
        throw "Azure Admin Console failed to load its functions ('$bundlePath'): $($_.Exception.Message) Reinstall the module."
    }
}
else {
    $areas = @(Get-ChildItem -LiteralPath (Join-Path -Path $moduleRoot -ChildPath 'src') -Directory |
            Where-Object { Test-Path -LiteralPath (Join-Path -Path $_.FullName -ChildPath 'area.psd1') } |
            Sort-Object -Property @{ Expression = { [int](Import-PowerShellDataFile -LiteralPath (Join-Path -Path $_.FullName -ChildPath 'area.psd1')).Order } }, Name)
    $publicFunctionNames = [System.Collections.Generic.List[string]]::new()
    foreach ($area in $areas) {
        foreach ($folder in 'Private', 'Public') {
            $folderPath = Join-Path -Path $area.FullName -ChildPath $folder
            if (-not (Test-Path -LiteralPath $folderPath)) {
                continue
            }

            $files = Get-ChildItem -LiteralPath $folderPath -Filter '*.ps1' -File | Sort-Object -Property Name
            foreach ($file in $files) {
                try {
                    . $file.FullName
                }
                catch {
                    throw "Azure Admin Console failed to load '$($file.FullName)': $($_.Exception.Message)"
                }
                if ($folder -eq 'Public') { $publicFunctionNames.Add($file.BaseName) }
            }
        }
    }
}

# What each AAC.* type shows at the console by default (Select-Object * or
# Format-List * shows everything) - registered in one Update-TypeData call below:
# a call per type rebuilt the session's type table 113 times, about 1.4 seconds
# of every import.
$displayProperties = [ordered]@{
    # Get-AACFirewallRule's objects carry ~35 properties (all of them go to
    # CSV); at the console show a readable table by default. Select-Object * or
    # Format-List * shows everything.
    'AAC.FirewallRule' = 'FirewallPolicy', 'RuleCollection', 'RuleName', 'Action'
    # Same for Get-AACAdvisorRecommendation's ~25 (or more, with Ext_ columns).
    'AAC.AdvisorRecommendation' = 'Category', 'Impact', 'ResourceName', 'Problem'
    # Invoke-AACApplicationInsightQuery's ~30 properties per exception.
    'AAC.ApplicationInsightsException' = 'TimeGenerated', 'Severity', 'ExceptionType', 'Message', 'AppRoleName'
    # Invoke-AACPSRule's ~18 properties.
    'AAC.PSRuleResult' = 'Outcome', 'RuleName', 'ResourceName', 'Reason'
    # Show-AACCost -PassThru: one property per month on top of these.
    # Get-AACTerraformPlan's ~20 properties per resource change.
    'AAC.TerraformChange' = 'Action', 'Address', 'ResourceName', 'ChangedAttributes'
    # Invoke-AACLogAnalyticsWorkspaceAssessment: one object per workspace, its sections as properties.
    'AAC.LogAnalyticsWorkspaceAssessment' = 'Name', 'PricingTier', 'RetentionDays', 'BillableGB', 'AverageDailyGB', 'Recommendations'
    'AAC.LogAnalyticsTable' = 'Table', 'Billing', 'BillableGB', 'NonBillableGB', 'SharePercent', 'Plan', 'RetentionDays'
    'AAC.LogAnalyticsRecommendation' = 'Severity', 'Category', 'Recommendation', 'Action'
    # Get-AACDiagnosticSetting: coverage per resource, one row per setting, findings.
    'AAC.DiagnosticCoverage' = 'Status', 'Resource', 'ResourceType', 'Workspaces', 'MissingCategories'
    'AAC.DiagnosticSettingDetail' = 'Resource', 'Setting', 'Destinations', 'Workspace', 'LogsEnabled'
    'AAC.DiagnosticFinding' = 'Severity', 'Finding', 'Resource', 'Detail'
    # Deploy-AACStorageAccount: the deployment, its changes, gates and apply results.
    'AAC.StorageDeployment' = 'Name', 'Status', 'Writes', 'ResourceGroupName', 'Location'
    'AAC.StorageChange' = 'Order', 'Action', 'Resource', 'Reason'
    'AAC.StorageGate' = 'Outcome', 'Gate', 'Resource', 'Item', 'Detail'
    'AAC.StorageApplyResult' = 'Status', 'Resource', 'Action', 'Seconds', 'Detail'
    # Invoke-AACAksAssessment: clusters, node pools, settings, checks, findings, policy views.
    'AAC.AksCluster' = 'Name', 'Version', 'Support', 'Tier', 'Nodes', 'WafScore', 'High', 'Medium', 'Low', 'PolicyViolations'
    'AAC.AksNodePool' = 'Cluster', 'Pool', 'Mode', 'VmSize', 'Nodes', 'Autoscale', 'Zones', 'Version', 'NodeImageAge'
    'AAC.AksSetting' = 'Cluster', 'Area', 'Setting', 'Value'
    'AAC.AksCheck' = 'Cluster', 'Pillar', 'Check', 'Status', 'Severity'
    'AAC.AksFinding' = 'Severity', 'Pillar', 'Source', 'Cluster', 'Check'
    'AAC.AksUpgrade' = 'Cluster', 'Component', 'Current', 'Support', 'Available'
    'AAC.AksPolicyViolation' = 'Cluster', 'Namespace', 'Workload', 'Component', 'Policy', 'Effect'
    'AAC.AksPolicyNamespace' = 'Namespace', 'Violations', 'Workloads', 'Policies', 'Deny'
    'AAC.AksPolicyWorkload' = 'Cluster', 'Namespace', 'WorkloadKind', 'Workload', 'Violations', 'Policies'
    'AAC.AksPolicySummary' = 'Policy', 'Effect', 'Violations', 'Clusters', 'Namespaces', 'Workloads'
    # Invoke-AACPolicyAssessment: assignments, compliance, exemptions, definitions, findings.
    'AAC.PolicyAssignmentReport' = 'Assignment', 'Scope', 'Kind', 'Enforcement', 'CompliancePercent', 'Rating', 'NonCompliant', 'Exemptions'
    'AAC.PolicyAssignmentCompliance' = 'Assignment', 'Subscription', 'CompliancePercent', 'Rating', 'NonCompliant', 'Resources'
    'AAC.PolicyAssessmentPolicy' = 'Assignment', 'Policy', 'Effect', 'Category', 'CompliancePercent', 'NonCompliant'
    'AAC.PolicyInitiativeMember' = 'Assignment', 'Policy', 'Effect', 'Parameters', 'CompliancePercent', 'NonCompliant'
    'AAC.PolicyCategory' = 'Category', 'Policies', 'Assignments', 'CompliancePercent', 'Rating', 'NonCompliant'
    'AAC.PolicySubscription' = 'Subscription', 'ManagementGroups', 'CompliancePercent', 'Rating', 'NonCompliant', 'Assignments', 'Exemptions'
    'AAC.PolicyManagementGroup' = 'ManagementGroup', 'Parent', 'CompliancePercent', 'Rating', 'Assignments', 'Subscriptions'
    'AAC.PolicyInitiative' = 'Initiative', 'PolicyType', 'Category', 'Policies', 'Assigned', 'Deprecated'
    'AAC.PolicyDefinitionReport' = 'Definition', 'PolicyType', 'Category', 'Effect', 'Assigned', 'Deprecated'
    'AAC.PolicyExemptionReport' = 'Exemption', 'Assignment', 'Scope', 'Category', 'ExpiresOn', 'Status'
    'AAC.PolicyRoleAssignment' = 'Assignment', 'Identity', 'Role', 'Scope', 'Required'
    'AAC.PolicyFinding' = 'Severity', 'Area', 'Finding', 'Item', 'Scope'
    # Invoke-AACDefenderAssessment: the assessment, and the rows of each of its tables.
    'AAC.DefenderAssessment' = 'SecureScore', 'Subscriptions', 'Findings', 'Recommendations', 'AttackPaths', 'Alerts', 'Inventory'
    'AAC.DefenderFinding' = 'Severity', 'Area', 'Finding', 'Item', 'SubscriptionName'
    'AAC.DefenderSubscription' = 'Subscription', 'SecureScore', 'PlansOn', 'UnhealthyResources', 'AttackPaths', 'ActiveAlerts', 'Findings'
    'AAC.DefenderRecommendation' = 'Recommendation', 'Severity', 'RiskLevel', 'Status', 'UnhealthyResources', 'HealthyResources', 'Control'
    'AAC.DefenderUnhealthyResource' = 'Resource', 'Recommendation', 'Severity', 'RiskLevel', 'SubscriptionName'
    'AAC.DefenderAttackPath' = 'AttackPath', 'RiskLevel', 'EntryPoint', 'Target', 'Steps'
    'AAC.DefenderAlert' = 'Alert', 'Severity', 'Status', 'Resource', 'Tactics', 'TimeGenerated'
    'AAC.DefenderResource' = 'Resource', 'Type', 'Plan', 'PlanState', 'Unhealthy', 'High', 'Vulnerabilities', 'Alerts', 'AttackPaths'
    'AAC.DefenderVulnerability' = 'Vulnerability', 'Severity', 'CVEs', 'Resource', 'Patchable'
    'AAC.DefenderPlanReport' = 'SubscriptionName', 'Plan', 'State', 'SubPlan', 'Resources'
    'AAC.DefenderSetting' = 'SubscriptionName', 'Setting', 'Value', 'Status'
    'AAC.DefenderComplianceControl' = 'Standard', 'Control', 'State', 'FailedAssessments', 'SubscriptionName'
    # Invoke-AACM365Assessment: the assessment, and the rows of its tables.
    'AAC.M365Assessment' = 'Tenant', 'SecureScore', 'Findings', 'ConditionalAccess', 'RoleAssignments', 'ManagedDevices', 'Permissions'
    'AAC.M365Finding' = 'Severity', 'Area', 'Finding', 'Item'
    'AAC.M365Setting' = 'Area', 'Setting', 'Value', 'Status'
    'AAC.M365ConditionalAccessPolicy' = 'Policy', 'State', 'Users', 'Applications', 'Grant'
    'AAC.M365RoleAssignment' = 'Role', 'Principal', 'Assignment', 'Privileged', 'MfaRegistered'
    'AAC.M365UserRegistration' = 'UserPrincipalName', 'Admin', 'MfaRegistered', 'DefaultMethod'
    'AAC.M365SecureScoreControl' = 'Control', 'Status', 'Score', 'MaxScore', 'Category'
    'AAC.M365ManagedDevice' = 'Device', 'User', 'OS', 'Compliance', 'Encrypted', 'LastSync', 'Stale'
    'AAC.M365EntraDevice' = 'Device', 'OS', 'Join', 'Managed', 'LastSignIn', 'Stale'
    'AAC.M365Permission' = 'Data', 'Status', 'Permission'
    'AAC.M365MfaCoverage' = 'Scope', 'Users', 'MfaPercent', 'PhishingResistantPercent', 'NoMethod'
    'AAC.M365EmergencyAccount' = 'UserPrincipalName', 'DetectedBy', 'GlobalAdministrator', 'CloudOnly', 'PhishingResistant'
    'AAC.M365PrivilegedAccount' = 'Principal', 'Roles', 'Dangling', 'Issues', 'Overlap'
    'AAC.M365AppCredential' = 'App', 'Type', 'Status', 'End', 'DaysLeft', 'ValidityDays'
    'AAC.M365AppPermission' = 'App', 'Permission', 'Kind', 'Risk', 'Owner'
    'AAC.M365RedirectUri' = 'App', 'Uri', 'Resolves', 'Issue', 'Severity'
    'AAC.M365LegacySignIn' = 'Protocol', 'Successful', 'Failed', 'Users', 'Latest'
    'AAC.M365PimRoleSetting' = 'Role', 'MfaOnActivation', 'Approval', 'MaxActivationHours', 'PermanentActive'
    'AAC.M365GroupExposure' = 'Group', 'Why', 'Members', 'Guests', 'Dynamic'
    'AAC.M365AccessReview' = 'Review', 'Covers', 'Status', 'Recurrence'
    'AAC.M365RiskyUser' = 'UserPrincipalName', 'RiskLevel', 'RiskState', 'Updated'
    'AAC.M365RiskDetection' = 'Detection', 'Detections', 'High', 'Users', 'Latest'
    'AAC.M365Incident' = 'Incident', 'Severity', 'Status', 'AssignedTo', 'AgeDays'
    'AAC.M365InactiveUser' = 'UserPrincipalName', 'Products', 'LastActivity'
    'AAC.M365AppProtectionPolicy' = 'Policy', 'Platform', 'Assigned', 'PinRequired', 'SendDataTo'
    'AAC.M365Coverage' = 'Area', 'Lens', 'Status', 'Reads', 'Reason'
    # Invoke-AACTenantAssessment: the run's summary (its sheets are plain rows).
    # The Architecture area: a brief, a design, patterns and findings, one line each.
    'AAC.ArchitectureBrief' = 'Name', 'CatalogVersion', 'Open', 'Assumed'
    'AAC.ArchitectureDesign' = 'Name', 'Regions', 'Components', 'Patterns', 'LandingZone'
    'AAC.ArchitecturePattern' = 'Rank', 'Name', 'Recommended', 'Score', 'Why'
    'AAC.ArchitectureFinding' = 'Severity', 'Status', 'Rule', 'Finding', 'Component'
    'AAC.TenantAssessment' ='Subscriptions', 'Resources', 'ResourceTypes', 'AdvisorHigh', 'Retirements', 'SecurityHigh', 'WafScore', 'AnnualSavings'
    # Invoke-AACVirtualNetworkAssessment: networks, subnets, peerings, free ranges, findings.
    'AAC.VirtualNetwork' = 'Name', 'Role', 'AddressSpace', 'UsedIps', 'AvailableIps', 'UsedPercent', 'SubnetCount', 'PeeringCount', 'High', 'Medium', 'Low'
    'AAC.VirtualNetworkSubnet' = 'VirtualNetwork', 'Subnet', 'Prefix', 'Usable', 'Used', 'Available', 'UsedPercent', 'Nsg', 'Outbound'
    'AAC.VirtualNetworkPeering' = 'VirtualNetwork', 'Peering', 'RemoteVirtualNetwork', 'State', 'Sync', 'UseRemoteGateways', 'AllowGatewayTransit'
    'AAC.VirtualNetworkFreeRange' = 'VirtualNetwork', 'AddressSpace', 'Prefix', 'Size'
    'AAC.VirtualNetworkFinding' = 'Severity', 'Category', 'Finding', 'VirtualNetwork', 'Item', 'Action'
    'AAC.VirtualNetworkPrivateEndpoint' = 'VirtualNetwork', 'Subnet', 'PrivateEndpoint', 'Target', 'Groups', 'Status', 'ZoneLinked'
    'AAC.ApplicationSecurityGroupUse' = 'Asg', 'Nics', 'Rules', 'VirtualNetworks', 'ResourceGroup'
    'AAC.SubscriptionCost' = 'SubscriptionName', 'Currency', 'MonthToDate', 'Total', 'TopServices', 'Status'

    # Show-AACDashboard: the status and headline first.
    'AAC.Dashboard' = 'Status', 'Headline', 'Resources', 'Regions', 'AdvisorHigh', 'Health'
    'AAC.DashboardChange' = 'Time', 'Change', 'Resource', 'ResourceGroup', 'ChangedBy'
    'AAC.DashboardServiceEvent' = 'Type', 'Title', 'TrackingId', 'Started', 'Subscription'
    'AAC.DashboardUnhealthyResource' = 'Resource', 'State', 'Summary', 'ResourceGroup'

    # The expert commands (issue 10): what matters first at the prompt.
    'AAC.CostAnomaly' = 'Severity', 'Kind', 'Name', 'Subscription', 'Start', 'CostImpact', 'Currency'
    'AAC.AttackPath' = 'Severity', 'Category', 'Resource', 'BlastRadius', 'Path'
    'AAC.AccessAssignment' = 'Severity', 'Principal', 'PrincipalType', 'Role', 'Scope', 'Assignment', 'Recommendation'
    'AAC.ChangeRecord' = 'Time', 'Severity', 'Category', 'Resource', 'Caller', 'Status', 'Detail'
    'AAC.HealthCheck' = 'Status', 'Tier', 'Category', 'Check', 'Detail'
    'AAC.ComplianceGap' = 'Severity', 'Phase', 'Framework', 'ControlId', 'FailingResources', 'Effort'
    'AAC.FailoverReadiness' = 'Severity', 'Resource', 'Protection', 'Confidence', 'Rpo', 'Finding'
    'AAC.DependencyNode' = 'Resource', 'Type', 'BlastRadius', 'Dependents', 'Redundant', 'SinglePointOfFailure'
    'AAC.ResourceUtilization' = 'Category', 'Resource', 'Kind', 'CpuP95', 'MemoryP95', 'Trend', 'SuggestedSize', 'EstimatedSaving'
    'AAC.ConfigurationDrift' = 'Severity', 'Resource', 'Category', 'Property', 'Detail', 'Origin', 'Strategy'

    # Security alerts, operations and troubleshooting (issue 8), and the resource export.
    'AAC.SecurityAlert' = 'Severity', 'Status', 'Alert', 'Resource', 'Intent', 'AgeDays'
    'AAC.ResourceHealth' = 'State', 'Resource', 'ResourceType', 'Summary', 'Hours', 'LastEvent'
    'AAC.ServiceHealthEvent' = 'Status', 'EventType', 'Title', 'Regions', 'ImpactedResources', 'TrackingId'
    'AAC.UnusedResource' = 'Severity', 'Category', 'Resource', 'Billed', 'AgeDays', 'MonthlyCost', 'ResourceGroup'
    'AAC.ResourceError' = 'Time', 'Category', 'ErrorCode', 'Resource', 'Caller', 'Message'
    'AAC.PrivateEndpoint' = 'Status', 'Endpoint', 'Target', 'GroupId', 'ConnectionState', 'ZoneLinked', 'Issues'
    'AAC.PrivateEndpointFinding' = 'Severity', 'Finding', 'Resource', 'Detail'
    'AAC.LoadBalancerBackend' = 'Health', 'Balancer', 'Pool', 'Backend', 'Address', 'Availability'
    'AAC.LoadBalancer' = 'Health', 'Balancer', 'Kind', 'Sku', 'Backends', 'Unhealthy', 'Issues'
    'AAC.LoadBalancerFinding' = 'Severity', 'Finding', 'Resource', 'Detail'
    'AAC.LegacyAuthentication' = 'Severity', 'Area', 'Finding', 'Resource', 'ResourceGroup'
    'AAC.OrphanedIdentity' = 'Severity', 'Kind', 'Identity', 'RoleAssignments', 'LastSignIn', 'Reason'
    'AAC.DiagnosticBundle' = 'Path', 'Resources', 'Files', 'SizeKB', 'Redacted'
    'AAC.DiagnosticBundleResource' = 'Status', 'Resource', 'ResourceType', 'Health', 'FailedOperations', 'Alerts', 'Issues'
    'AAC.Resource' = 'Name', 'ResourceType', 'ResourceGroup', 'Subscription', 'Location', 'Details'
}
$typeData = foreach ($typeName in $displayProperties.Keys) {
    $type = [System.Management.Automation.Runspaces.TypeData]::new($typeName)
    $type.DefaultDisplayPropertySet = [System.Management.Automation.Runspaces.PropertySetData]::new([string[]]$displayProperties[$typeName])
    $type
}
Update-TypeData -TypeData $typeData -Force

Export-ModuleMember -Function $publicFunctionNames
