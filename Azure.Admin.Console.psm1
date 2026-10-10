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
if ((Get-FileHash -LiteralPath $spectreConsolePath -Algorithm SHA256).Hash -ne $spectreConsoleHash) {
    throw "Azure Admin Console refused to load '$spectreConsolePath': its SHA-256 hash doesn't match the Spectre.Console.dll this module was released with. Reinstall the module."
}
try {
    Add-Type -Path $spectreConsolePath -ErrorAction Stop
}
catch {
    throw "Azure Admin Console failed to load Spectre.Console.dll: $($_.Exception.Message)"
}

# Load order matters: Private helpers first, then the public, exported
# commands that use them.
foreach ($folder in 'Private', 'Public') {
    $folderPath = Join-Path -Path $moduleRoot -ChildPath $folder
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
    }
}

# Get-AACFirewallRule's objects carry ~35 properties (all of them go to
# CSV); at the console show a readable table by default. Select-Object * or
# Format-List * shows everything.
Update-TypeData -TypeName 'AAC.FirewallRule' -DefaultDisplayPropertySet 'FirewallPolicy', 'RuleCollection', 'RuleName', 'Action' -Force
# Same for Get-AACAdvisorRecommendation's ~25 (or more, with Ext_ columns).
Update-TypeData -TypeName 'AAC.AdvisorRecommendation' -DefaultDisplayPropertySet 'Category', 'Impact', 'ResourceName', 'Problem' -Force
# Invoke-AACApplicationInsightQuery's ~30 properties per exception.
Update-TypeData -TypeName 'AAC.ApplicationInsightsException' -DefaultDisplayPropertySet 'TimeGenerated', 'Severity', 'ExceptionType', 'Message', 'AppRoleName' -Force
# Invoke-AACPSRule's ~18 properties.
Update-TypeData -TypeName 'AAC.PSRuleResult' -DefaultDisplayPropertySet 'Outcome', 'RuleName', 'ResourceName', 'Reason' -Force
# Show-AACCost -PassThru: one property per month on top of these.
# Get-AACTerraformPlan's ~20 properties per resource change.
Update-TypeData -TypeName 'AAC.TerraformChange' -DefaultDisplayPropertySet 'Action', 'Address', 'ResourceName', 'ChangedAttributes' -Force
# Invoke-AACLogAnalyticsWorkspaceAssessment: one object per workspace, its sections as properties.
Update-TypeData -TypeName 'AAC.LogAnalyticsWorkspaceAssessment' -DefaultDisplayPropertySet 'Name', 'PricingTier', 'RetentionDays', 'BillableGB', 'AverageDailyGB', 'Recommendations' -Force
Update-TypeData -TypeName 'AAC.LogAnalyticsTable' -DefaultDisplayPropertySet 'Table', 'Billing', 'BillableGB', 'NonBillableGB', 'SharePercent', 'Plan', 'RetentionDays' -Force
Update-TypeData -TypeName 'AAC.LogAnalyticsRecommendation' -DefaultDisplayPropertySet 'Severity', 'Category', 'Recommendation', 'Action' -Force
# Get-AACDiagnosticSetting: coverage per resource, one row per setting, findings.
Update-TypeData -TypeName 'AAC.DiagnosticCoverage' -DefaultDisplayPropertySet 'Status', 'Resource', 'ResourceType', 'Workspaces', 'MissingCategories' -Force
Update-TypeData -TypeName 'AAC.DiagnosticSettingDetail' -DefaultDisplayPropertySet 'Resource', 'Setting', 'Destinations', 'Workspace', 'LogsEnabled' -Force
Update-TypeData -TypeName 'AAC.DiagnosticFinding' -DefaultDisplayPropertySet 'Severity', 'Finding', 'Resource', 'Detail' -Force
# Deploy-AACStorageAccount: the deployment, its changes, gates and apply results.
Update-TypeData -TypeName 'AAC.StorageDeployment' -DefaultDisplayPropertySet 'Name', 'Status', 'Writes', 'ResourceGroupName', 'Location' -Force
Update-TypeData -TypeName 'AAC.StorageChange' -DefaultDisplayPropertySet 'Order', 'Action', 'Resource', 'Reason' -Force
Update-TypeData -TypeName 'AAC.StorageGate' -DefaultDisplayPropertySet 'Outcome', 'Gate', 'Resource', 'Item', 'Detail' -Force
Update-TypeData -TypeName 'AAC.StorageApplyResult' -DefaultDisplayPropertySet 'Status', 'Resource', 'Action', 'Seconds', 'Detail' -Force
# Invoke-AACAksAssessment: clusters, node pools, settings, checks, findings, policy views.
Update-TypeData -TypeName 'AAC.AksCluster' -DefaultDisplayPropertySet 'Name', 'Version', 'Support', 'Tier', 'Nodes', 'WafScore', 'High', 'Medium', 'Low', 'PolicyViolations' -Force
Update-TypeData -TypeName 'AAC.AksNodePool' -DefaultDisplayPropertySet 'Cluster', 'Pool', 'Mode', 'VmSize', 'Nodes', 'Autoscale', 'Zones', 'Version', 'NodeImageAge' -Force
Update-TypeData -TypeName 'AAC.AksSetting' -DefaultDisplayPropertySet 'Cluster', 'Area', 'Setting', 'Value' -Force
Update-TypeData -TypeName 'AAC.AksCheck' -DefaultDisplayPropertySet 'Cluster', 'Pillar', 'Check', 'Status', 'Severity' -Force
Update-TypeData -TypeName 'AAC.AksFinding' -DefaultDisplayPropertySet 'Severity', 'Pillar', 'Source', 'Cluster', 'Check' -Force
Update-TypeData -TypeName 'AAC.AksUpgrade' -DefaultDisplayPropertySet 'Cluster', 'Component', 'Current', 'Support', 'Available' -Force
Update-TypeData -TypeName 'AAC.AksPolicyViolation' -DefaultDisplayPropertySet 'Cluster', 'Namespace', 'Workload', 'Component', 'Policy', 'Effect' -Force
Update-TypeData -TypeName 'AAC.AksPolicyNamespace' -DefaultDisplayPropertySet 'Namespace', 'Violations', 'Workloads', 'Policies', 'Deny' -Force
Update-TypeData -TypeName 'AAC.AksPolicyWorkload' -DefaultDisplayPropertySet 'Cluster', 'Namespace', 'WorkloadKind', 'Workload', 'Violations', 'Policies' -Force
Update-TypeData -TypeName 'AAC.AksPolicySummary' -DefaultDisplayPropertySet 'Policy', 'Effect', 'Violations', 'Clusters', 'Namespaces', 'Workloads' -Force
# Invoke-AACPolicyAssessment: assignments, compliance, exemptions, definitions, findings.
Update-TypeData -TypeName 'AAC.PolicyAssignmentReport' -DefaultDisplayPropertySet 'Assignment', 'Scope', 'Kind', 'Enforcement', 'CompliancePercent', 'Rating', 'NonCompliant', 'Exemptions' -Force
Update-TypeData -TypeName 'AAC.PolicyAssignmentCompliance' -DefaultDisplayPropertySet 'Assignment', 'Subscription', 'CompliancePercent', 'Rating', 'NonCompliant', 'Resources' -Force
Update-TypeData -TypeName 'AAC.PolicyAssessmentPolicy' -DefaultDisplayPropertySet 'Assignment', 'Policy', 'Effect', 'Category', 'CompliancePercent', 'NonCompliant' -Force
Update-TypeData -TypeName 'AAC.PolicyInitiativeMember' -DefaultDisplayPropertySet 'Assignment', 'Policy', 'Effect', 'Parameters', 'CompliancePercent', 'NonCompliant' -Force
Update-TypeData -TypeName 'AAC.PolicyCategory'-DefaultDisplayPropertySet 'Category', 'Policies', 'Assignments', 'CompliancePercent', 'Rating', 'NonCompliant' -Force
Update-TypeData -TypeName 'AAC.PolicySubscription' -DefaultDisplayPropertySet 'Subscription', 'ManagementGroups', 'CompliancePercent', 'Rating', 'NonCompliant', 'Assignments', 'Exemptions' -Force
Update-TypeData -TypeName 'AAC.PolicyManagementGroup' -DefaultDisplayPropertySet 'ManagementGroup', 'Parent', 'CompliancePercent', 'Rating', 'Assignments', 'Subscriptions' -Force
Update-TypeData -TypeName 'AAC.PolicyInitiative' -DefaultDisplayPropertySet 'Initiative', 'PolicyType', 'Category', 'Policies', 'Assigned', 'Deprecated' -Force
Update-TypeData -TypeName 'AAC.PolicyDefinitionReport' -DefaultDisplayPropertySet 'Definition', 'PolicyType', 'Category', 'Effect', 'Assigned', 'Deprecated' -Force
Update-TypeData -TypeName 'AAC.PolicyExemptionReport' -DefaultDisplayPropertySet 'Exemption', 'Assignment', 'Scope', 'Category', 'ExpiresOn', 'Status' -Force
Update-TypeData -TypeName 'AAC.PolicyRoleAssignment' -DefaultDisplayPropertySet 'Assignment', 'Identity', 'Role', 'Scope', 'Required' -Force
Update-TypeData -TypeName 'AAC.PolicyFinding' -DefaultDisplayPropertySet 'Severity', 'Area', 'Finding', 'Item', 'Scope' -Force
# Invoke-AACDefenderAssessment: the assessment, and the rows of each of its tables.
Update-TypeData -TypeName 'AAC.DefenderAssessment' -DefaultDisplayPropertySet 'SecureScore', 'Subscriptions', 'Findings', 'Recommendations', 'AttackPaths', 'Alerts', 'Inventory' -Force
Update-TypeData -TypeName 'AAC.DefenderFinding' -DefaultDisplayPropertySet 'Severity', 'Area', 'Finding', 'Item', 'SubscriptionName' -Force
Update-TypeData -TypeName 'AAC.DefenderSubscription' -DefaultDisplayPropertySet 'Subscription', 'SecureScore', 'PlansOn', 'UnhealthyResources', 'AttackPaths', 'ActiveAlerts', 'Findings' -Force
Update-TypeData -TypeName 'AAC.DefenderRecommendation' -DefaultDisplayPropertySet 'Recommendation', 'Severity', 'RiskLevel', 'Status', 'UnhealthyResources', 'HealthyResources', 'Control' -Force
Update-TypeData -TypeName 'AAC.DefenderUnhealthyResource' -DefaultDisplayPropertySet 'Resource', 'Recommendation', 'Severity', 'RiskLevel', 'SubscriptionName' -Force
Update-TypeData -TypeName 'AAC.DefenderAttackPath' -DefaultDisplayPropertySet 'AttackPath', 'RiskLevel', 'EntryPoint', 'Target', 'Steps' -Force
Update-TypeData -TypeName 'AAC.DefenderAlert' -DefaultDisplayPropertySet 'Alert', 'Severity', 'Status', 'Resource', 'Tactics', 'TimeGenerated' -Force
Update-TypeData -TypeName 'AAC.DefenderResource' -DefaultDisplayPropertySet 'Resource', 'Type', 'Plan', 'PlanState', 'Unhealthy', 'High', 'Vulnerabilities', 'Alerts', 'AttackPaths' -Force
Update-TypeData -TypeName 'AAC.DefenderVulnerability' -DefaultDisplayPropertySet 'Vulnerability', 'Severity', 'CVEs', 'Resource', 'Patchable' -Force
Update-TypeData -TypeName 'AAC.DefenderPlanReport' -DefaultDisplayPropertySet 'SubscriptionName', 'Plan', 'State', 'SubPlan', 'Resources' -Force
Update-TypeData -TypeName 'AAC.DefenderSetting' -DefaultDisplayPropertySet 'SubscriptionName', 'Setting', 'Value', 'Status' -Force
Update-TypeData -TypeName 'AAC.DefenderComplianceControl' -DefaultDisplayPropertySet 'Standard', 'Control', 'State', 'FailedAssessments', 'SubscriptionName' -Force
# Invoke-AACM365Assessment: the assessment, and the rows of its tables.
Update-TypeData -TypeName 'AAC.M365Assessment' -DefaultDisplayPropertySet 'Tenant', 'SecureScore', 'Findings', 'ConditionalAccess', 'RoleAssignments', 'ManagedDevices', 'Permissions' -Force
Update-TypeData -TypeName 'AAC.M365Finding' -DefaultDisplayPropertySet 'Severity', 'Area', 'Finding', 'Item' -Force
Update-TypeData -TypeName 'AAC.M365Setting' -DefaultDisplayPropertySet 'Area', 'Setting', 'Value', 'Status' -Force
Update-TypeData -TypeName 'AAC.M365ConditionalAccessPolicy' -DefaultDisplayPropertySet 'Policy', 'State', 'Users', 'Applications', 'Grant' -Force
Update-TypeData -TypeName 'AAC.M365RoleAssignment' -DefaultDisplayPropertySet 'Role', 'Principal', 'Assignment', 'Privileged', 'MfaRegistered' -Force
Update-TypeData -TypeName 'AAC.M365UserRegistration' -DefaultDisplayPropertySet 'UserPrincipalName', 'Admin', 'MfaRegistered', 'DefaultMethod' -Force
Update-TypeData -TypeName 'AAC.M365SecureScoreControl' -DefaultDisplayPropertySet 'Control', 'Status', 'Score', 'MaxScore', 'Category' -Force
Update-TypeData -TypeName 'AAC.M365ManagedDevice' -DefaultDisplayPropertySet 'Device', 'User', 'OS', 'Compliance', 'Encrypted', 'LastSync', 'Stale' -Force
Update-TypeData -TypeName 'AAC.M365EntraDevice' -DefaultDisplayPropertySet 'Device', 'OS', 'Join', 'Managed', 'LastSignIn', 'Stale' -Force
Update-TypeData -TypeName 'AAC.M365Permission' -DefaultDisplayPropertySet 'Data', 'Status', 'Permission' -Force
Update-TypeData -TypeName 'AAC.M365MfaCoverage' -DefaultDisplayPropertySet 'Scope', 'Users', 'MfaPercent', 'PhishingResistantPercent', 'NoMethod' -Force
Update-TypeData -TypeName 'AAC.M365EmergencyAccount' -DefaultDisplayPropertySet 'UserPrincipalName', 'DetectedBy', 'GlobalAdministrator', 'CloudOnly', 'PhishingResistant' -Force
Update-TypeData -TypeName 'AAC.M365PrivilegedAccount' -DefaultDisplayPropertySet 'Principal', 'Roles', 'Dangling', 'Issues', 'Overlap' -Force
Update-TypeData -TypeName 'AAC.M365AppCredential' -DefaultDisplayPropertySet 'App', 'Type', 'Status', 'End', 'DaysLeft', 'ValidityDays' -Force
Update-TypeData -TypeName 'AAC.M365AppPermission' -DefaultDisplayPropertySet 'App', 'Permission', 'Kind', 'Risk', 'Owner' -Force
Update-TypeData -TypeName 'AAC.M365RedirectUri' -DefaultDisplayPropertySet 'App', 'Uri', 'Resolves', 'Issue', 'Severity' -Force
Update-TypeData -TypeName 'AAC.M365LegacySignIn' -DefaultDisplayPropertySet 'Protocol', 'Successful', 'Failed', 'Users', 'Latest' -Force
Update-TypeData -TypeName 'AAC.M365PimRoleSetting' -DefaultDisplayPropertySet 'Role', 'MfaOnActivation', 'Approval', 'MaxActivationHours', 'PermanentActive' -Force
Update-TypeData -TypeName 'AAC.M365GroupExposure' -DefaultDisplayPropertySet 'Group', 'Why', 'Members', 'Guests', 'Dynamic' -Force
Update-TypeData -TypeName 'AAC.M365AccessReview' -DefaultDisplayPropertySet 'Review', 'Covers', 'Status', 'Recurrence' -Force
Update-TypeData -TypeName 'AAC.M365RiskyUser' -DefaultDisplayPropertySet 'UserPrincipalName', 'RiskLevel', 'RiskState', 'Updated' -Force
Update-TypeData -TypeName 'AAC.M365RiskDetection' -DefaultDisplayPropertySet 'Detection', 'Detections', 'High', 'Users', 'Latest' -Force
Update-TypeData -TypeName 'AAC.M365Incident' -DefaultDisplayPropertySet 'Incident', 'Severity', 'Status', 'AssignedTo', 'AgeDays' -Force
Update-TypeData -TypeName 'AAC.M365InactiveUser' -DefaultDisplayPropertySet 'UserPrincipalName', 'Products', 'LastActivity' -Force
Update-TypeData -TypeName 'AAC.M365AppProtectionPolicy' -DefaultDisplayPropertySet 'Policy', 'Platform', 'Assigned', 'PinRequired', 'SendDataTo' -Force
Update-TypeData -TypeName 'AAC.M365Coverage' -DefaultDisplayPropertySet 'Area', 'Lens', 'Status', 'Reads', 'Reason' -Force
# Invoke-AACAssessment: the run's summary (its sheets are plain rows).
Update-TypeData -TypeName 'AAC.Assessment' -DefaultDisplayPropertySet 'Subscriptions', 'Resources', 'ResourceTypes', 'AdvisorHigh', 'Retirements', 'SecurityHigh', 'ReportFolder' -Force
# Invoke-AACVirtualNetworkAssessment: networks, subnets, peerings, free ranges, findings.
Update-TypeData -TypeName 'AAC.VirtualNetwork' -DefaultDisplayPropertySet 'Name', 'Role', 'AddressSpace', 'UsedIps', 'AvailableIps', 'UsedPercent', 'SubnetCount', 'PeeringCount', 'High', 'Medium', 'Low' -Force
Update-TypeData -TypeName 'AAC.VirtualNetworkSubnet' -DefaultDisplayPropertySet 'VirtualNetwork', 'Subnet', 'Prefix', 'Usable', 'Used', 'Available', 'UsedPercent', 'Nsg', 'Outbound' -Force
Update-TypeData -TypeName 'AAC.VirtualNetworkPeering' -DefaultDisplayPropertySet 'VirtualNetwork', 'Peering', 'RemoteVirtualNetwork', 'State', 'Sync', 'UseRemoteGateways', 'AllowGatewayTransit' -Force
Update-TypeData -TypeName 'AAC.VirtualNetworkFreeRange' -DefaultDisplayPropertySet 'VirtualNetwork', 'AddressSpace', 'Prefix', 'Size' -Force
Update-TypeData -TypeName 'AAC.VirtualNetworkFinding' -DefaultDisplayPropertySet 'Severity', 'Category', 'Finding', 'VirtualNetwork', 'Item', 'Action' -Force
Update-TypeData -TypeName 'AAC.VirtualNetworkPrivateEndpoint' -DefaultDisplayPropertySet 'VirtualNetwork', 'Subnet', 'PrivateEndpoint', 'Target', 'Groups', 'Status', 'ZoneLinked' -Force
Update-TypeData -TypeName 'AAC.ApplicationSecurityGroupUse' -DefaultDisplayPropertySet 'Asg', 'Nics', 'Rules', 'VirtualNetworks', 'ResourceGroup' -Force
Update-TypeData -TypeName 'AAC.SubscriptionCost' -DefaultDisplayPropertySet 'SubscriptionName', 'Currency', 'MonthToDate', 'Total', 'TopServices', 'Status' -Force

# Show-AACDashboard: the status and headline first.
Update-TypeData -TypeName 'AAC.Dashboard' -DefaultDisplayPropertySet 'Status', 'Headline', 'Resources', 'Regions', 'AdvisorHigh', 'Health' -Force
Update-TypeData -TypeName 'AAC.DashboardChange' -DefaultDisplayPropertySet 'Time', 'Change', 'Resource', 'ResourceGroup', 'ChangedBy' -Force
Update-TypeData -TypeName 'AAC.DashboardServiceEvent' -DefaultDisplayPropertySet 'Type', 'Title', 'TrackingId', 'Started', 'Subscription' -Force
Update-TypeData -TypeName 'AAC.DashboardUnhealthyResource' -DefaultDisplayPropertySet 'Resource', 'State', 'Summary', 'ResourceGroup' -Force

# The expert commands (issue 10): what matters first at the prompt.
Update-TypeData -TypeName 'AAC.CostAnomaly' -DefaultDisplayPropertySet 'Severity', 'Kind', 'Name', 'Subscription', 'Start', 'CostImpact', 'Currency' -Force
Update-TypeData -TypeName 'AAC.AttackPath' -DefaultDisplayPropertySet 'Severity', 'Category', 'Resource', 'BlastRadius', 'Path' -Force
Update-TypeData -TypeName 'AAC.AccessAssignment' -DefaultDisplayPropertySet 'Severity', 'Principal', 'PrincipalType', 'Role', 'Scope', 'Assignment', 'Recommendation' -Force
Update-TypeData -TypeName 'AAC.ChangeRecord' -DefaultDisplayPropertySet 'Time', 'Severity', 'Category', 'Resource', 'Caller', 'Status', 'Detail' -Force
Update-TypeData -TypeName 'AAC.HealthCheck' -DefaultDisplayPropertySet 'Status', 'Tier', 'Category', 'Check', 'Detail' -Force
Update-TypeData -TypeName 'AAC.ComplianceGap' -DefaultDisplayPropertySet 'Severity', 'Phase', 'Framework', 'ControlId', 'FailingResources', 'Effort' -Force
Update-TypeData -TypeName 'AAC.FailoverReadiness' -DefaultDisplayPropertySet 'Severity', 'Resource', 'Protection', 'Confidence', 'Rpo', 'Finding' -Force
Update-TypeData -TypeName 'AAC.DependencyNode' -DefaultDisplayPropertySet 'Resource', 'Type', 'BlastRadius', 'Dependents', 'Redundant', 'SinglePointOfFailure' -Force
Update-TypeData -TypeName 'AAC.ResourceUtilization' -DefaultDisplayPropertySet 'Category', 'Resource', 'Kind', 'CpuP95', 'MemoryP95', 'Trend', 'SuggestedSize', 'EstimatedSaving' -Force
Update-TypeData -TypeName 'AAC.ConfigurationDrift' -DefaultDisplayPropertySet 'Severity', 'Resource', 'Category', 'Property', 'Detail', 'Origin', 'Strategy' -Force

$publicFunctionNames = Get-ChildItem -LiteralPath (Join-Path -Path $moduleRoot -ChildPath 'Public') -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty BaseName

Export-ModuleMember -Function $publicFunctionNames
