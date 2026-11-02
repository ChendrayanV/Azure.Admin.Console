<#
    A made-up Microsoft Sentinel workspace for the Invoke-AACSentinelAssessment
    tests, in the shapes Azure returns: the workspace, its Sentinel resources
    (Resource Manager) and KQL rows. Built so every rule has something to find:
    an enabled rule failing, a disabled rule failing (not reported), a table
    that stopped receiving data and no enabled rule reads, a failing connector,
    a template to enable, a rule with a newer template, MITRE gaps, an old open
    incident with no owner, slow closes, a noisy rule, and expired and disabled
    automation.

    Returns @{ Now; WorkspaceId; ResourceId; Workspace; Arm; Kql }.
#>
$now = [datetime]::new(2026, 10, 2, 12, 0, 0, [DateTimeKind]::Utc)
$sub = '11111111-1111-1111-1111-111111111111'
$ws = "/subscriptions/$sub/resourceGroups/rg-contoso-sec/providers/Microsoft.OperationalInsights/workspaces/law-contoso-sentinel"
$customerId = 'aaaaaaaa-bbbb-cccc-dddd-ffffffffffff'
$iso = { param([datetime] $When) $When.ToString('yyyy-MM-ddTHH:mm:ss.fffZ') }
$ruleId = { param([string] $Name) "$ws/providers/Microsoft.SecurityInsights/alertRules/$Name" }
$list = { param($Items) @{ Status = 200; Error = ''; Body = $null; Items = @($Items) } }

$workspace = @{ id = $ws; name = 'law-contoso-sentinel'; location = 'uksouth'; properties = @{ customerId = $customerId } }
$table = { param([string] $Name, [string] $Type = 'Microsoft', [int] $Retention = 90, [int] $Total = 90, [string] $Plan = 'Analytics')
    @{ name = $Name; properties = @{ plan = $Plan; retentionInDays = $Retention; totalRetentionInDays = $Total; schema = @{ name = $Name; tableType = $Type } } }
}
$incident = {
    param([int] $Number, [string] $Status, [int] $AgeHours, [string] $RuleName, [string] $Owner = '', [string] $Classification = '', [string] $Severity = 'Medium')
    @{ name = "inc-$Number"; properties = @{
            incidentNumber = $Number; title = "Incident $Number"; severity = $Severity; status = $Status; classification = $Classification
            createdTimeUtc = (& $iso $now.AddHours(-$AgeHours)); lastModifiedTimeUtc = (& $iso $now.AddHours(-1)); providerName = 'Azure Sentinel'; incidentUrl = "https://portal.azure.com/#incident/$Number"
            owner = @{ objectId = $null; email = $null; assignedTo = $(if ($Owner) { $Owner } else { $null }); userPrincipalName = $null }
            additionalData = @{ alertsCount = 2; tactics = @('InitialAccess') }; relatedAnalyticRuleIds = @(& $ruleId $RuleName)
        }
    }
}
# Six closed from rule-2, four of them false positives; each took 100 hours except the last.
$closedIncidents = @(
    foreach ($n in 4..9) { & $incident $n 'Closed' 200 'rule-2' 'analyst@contoso.example' $(if ($n -le 7) { 'FalsePositive' } else { 'TruePositive' }) }
)
$arm = @{
    onboarding     = & $list @(@{ name = 'default'; properties = @{ customerManagedKey = $false } })
    alertRuleTemplates = & $list @(
        @{ name = 'tmpl-1'; kind = 'Scheduled'; properties = @{ displayName = 'Brute force on VMs'; severity = 'High'; status = 'Installed'; version = '1.2.0'; requiredDataConnectors = @(@{ connectorId = 'SecurityEvents'; dataTypes = @('SecurityEvent') }) } }
        @{ name = 'tmpl-2'; kind = 'Scheduled'; properties = @{ displayName = 'Impossible travel'; severity = 'Medium'; status = 'Available'; version = '1.0.0'; tactics = @('InitialAccess'); requiredDataConnectors = @(@{ connectorId = 'AzureActiveDirectory'; dataTypes = @('SigninLogs') }) } }
        @{ name = 'tmpl-3'; kind = 'Scheduled'; properties = @{ displayName = 'Firewall port scan'; severity = 'Low'; status = 'Available'; version = '1.0.0'; requiredDataConnectors = @(@{ connectorId = 'Fortinet'; dataTypes = @('CommonSecurityLog (Fortinet)') }) } }
        @{ name = 'tmpl-4'; kind = 'Scheduled'; properties = @{ displayName = 'Already has a rule'; severity = 'High'; status = 'Available'; version = '1.0.0'; alertRulesCreatedByTemplateCount = 1; requiredDataConnectors = @(@{ connectorId = 'SecurityEvents'; dataTypes = @('SecurityEvent') }, @{ connectorId = 'AzureActiveDirectory'; dataTypes = @('SigninLogs') }) } }
        @{ name = 'tmpl-5'; kind = 'Scheduled'; properties = @{ displayName = 'Unavailable template'; severity = 'High'; status = 'NotAvailable'; version = '1.0.0'; requiredDataConnectors = @(@{ connectorId = 'Syslog'; dataTypes = @('Syslog') }) } }
        @{ name = 'tmpl-fusion'; kind = 'Fusion'; properties = @{ displayName = 'Fusion needs no table'; severity = 'High'; status = 'Available' } }
    )
    incidents      = & $list @(
        (& $incident 1 'New' 72 'rule-1' -Severity 'High')
        (& $incident 2 'Active' 120 'rule-1' 'analyst@contoso.example')
        (& $incident 3 'New' 2 'rule-1')
        $closedIncidents
    )
    automationRules = & $list @(
        @{ name = 'a-1'; properties = @{ displayName = 'Assign to the SOC'; order = 1; triggeringLogic = @{ isEnabled = $true; triggersOn = 'Incidents'; triggersWhen = 'Created'; conditions = @(@{ conditionType = 'Property' }) }; actions = @(@{ order = 1; actionType = 'ModifyProperties' }, @{ order = 2; actionType = 'RunPlaybook' }); lastModifiedBy = @{ email = 'admin@contoso.example' } } }
        @{ name = 'a-2'; properties = @{ displayName = 'Suppress during migration'; order = 2; triggeringLogic = @{ isEnabled = $true; expirationTimeUtc = (& $iso $now.AddDays(-3)); triggersOn = 'Incidents'; triggersWhen = 'Created' }; actions = @(@{ order = 1; actionType = 'ModifyProperties' }) } }
        @{ name = 'a-3'; properties = @{ displayName = 'Old notification'; order = 3; triggeringLogic = @{ isEnabled = $false; triggersOn = 'Alerts'; triggersWhen = 'Created' }; actions = @(@{ order = 1; actionType = 'RunPlaybook' }) } }
        @{ name = 'a-4'; properties = @{ displayName = 'Temporary tagging'; order = 4; triggeringLogic = @{ isEnabled = $true; expirationTimeUtc = (& $iso $now.AddDays(3)); triggersOn = 'Incidents'; triggersWhen = 'Updated' }; actions = @(@{ order = 1; actionType = 'AddIncidentTask' }) } }
    )
    alertRules     = & $list @(
        @{ name = 'rule-1'; kind = 'Scheduled'; properties = @{ displayName = 'Brute force on VMs'; enabled = $true; severity = 'High'; tactics = @('CredentialAccess'); techniques = @('T1110'); query = 'SecurityEvent | where EventID == 4625'; queryFrequency = 'PT1H'; queryPeriod = 'PT1H'; alertRuleTemplateName = 'tmpl-1'; templateVersion = '1.0.0'; lastModifiedUtc = '2026-09-01T10:00:00Z'; incidentConfiguration = @{ createIncident = $true } } }
        @{ name = 'rule-2'; kind = 'Scheduled'; properties = @{ displayName = 'Rare admin sign-in'; enabled = $true; severity = 'Medium'; tactics = @('InitialAccess', 'Persistence'); query = 'SigninLogs'; queryFrequency = 'PT5H'; queryPeriod = 'P1D'; incidentConfiguration = @{ createIncident = $true } } }
        @{ name = 'rule-3'; kind = 'Scheduled'; properties = @{ displayName = 'Old disabled rule'; enabled = $false; severity = 'Low'; query = 'Syslog'; queryFrequency = 'P1D'; queryPeriod = 'P1D' } }
        @{ name = 'rule-4'; kind = 'Fusion'; properties = @{ displayName = 'Advanced multistage attack detection'; enabled = $true; severity = 'High'; alertRuleTemplateName = 'tmpl-fusion' } }
    )
    dataConnectors = & $list @(
        @{ name = 'c-office'; kind = 'Office365'; properties = @{ dataTypes = @{ exchange = @{ state = 'Enabled' }; sharePoint = @{ state = 'Disabled' }; teams = @{ state = 'Disabled' } } } }
        @{ name = 'c-tip'; kind = 'ThreatIntelligence'; properties = @{ dataTypes = @{ indicators = @{ state = 'Disabled' } } } }
        @{ name = 'c-poller'; kind = 'RestApiPoller'; properties = @{ connectorDefinitionName = 'Contoso API'; dataType = 'ContosoApi_CL'; isActive = $true } }
        @{ name = 'c-ui'; kind = 'GenericUI'; properties = @{ connectorUiConfig = @{ title = 'Contoso legacy feed' } } }
    )
    tables         = & $list @(
        (& $table 'SecurityEvent' -Total 365), (& $table 'SigninLogs'), (& $table 'Syslog'), (& $table 'Operation')
        (& $table 'App_CL' -Type 'CustomLog' -Plan 'Basic'), (& $table 'Unused_CL' -Type 'CustomLog')
        (& $table 'W3CIISLog')
    )
}
$kql = @{
    Errors = @{}
    Rows   = @{
        # Quantity is already turned into GB by the query.
        tables = @(
            [ordered]@{ Table = 'SecurityEvent'; BillableGB = 60.0; NonBillableGB = 0.0; LastRecord = (& $iso $now.AddHours(-1)); Solution = 'Security' }
            [ordered]@{ Table = 'SigninLogs'; BillableGB = 30.0; NonBillableGB = 0.0; LastRecord = (& $iso $now.AddHours(-2)); Solution = 'LogManagement' }
            [ordered]@{ Table = 'Syslog'; BillableGB = 10.0; NonBillableGB = 0.0; LastRecord = (& $iso $now.AddDays(-5)); Solution = 'LogManagement' }
            [ordered]@{ Table = 'Operation'; BillableGB = 0.0; NonBillableGB = 0.5; LastRecord = (& $iso $now.AddDays(-20)); Solution = 'LogManagement' }
        )
        incidentTimes = @(
            foreach ($n in 4..8) { [ordered]@{ IncidentNumber = $n; ClosedTime = (& $iso $now.AddHours(-100)); FirstModifiedTime = (& $iso $now.AddHours(-190)) } }
            # Closed, but with no ClosedTime in the table: its hours to close stay blank.
            [ordered]@{ IncidentNumber = 9; ClosedTime = $null; FirstModifiedTime = $null }
            # Still open: a ClosedTime from before it was reopened doesn't count.
            [ordered]@{ IncidentNumber = 2; ClosedTime = (& $iso $now.AddHours(-50)); FirstModifiedTime = (& $iso $now.AddHours(-60)) }
        )
        health = @(
            [ordered]@{ SentinelResourceType = 'Analytics Rule'; SentinelResourceName = 'Brute force on VMs'; SentinelResourceId = (& $ruleId 'rule-1'); OperationName = 'Scheduled analytics rule run'; Records = 720; Failures = 12; LastFailure = (& $iso $now.AddHours(-3)); Reason = 'The query timed out' }
            [ordered]@{ SentinelResourceType = 'Analytics Rule'; SentinelResourceName = 'Old disabled rule'; SentinelResourceId = (& $ruleId 'rule-3'); OperationName = 'Scheduled analytics rule run'; Records = 5; Failures = 5; LastFailure = (& $iso $now.AddDays(-25)); Reason = 'Table not found' }
            [ordered]@{ SentinelResourceType = 'Analytics Rule'; SentinelResourceName = 'Rare admin sign-in'; SentinelResourceId = (& $ruleId 'rule-2'); OperationName = 'Scheduled analytics rule run'; Records = 144; Failures = 0; LastFailure = $null; Reason = '' }
            [ordered]@{ SentinelResourceType = 'Data connector'; SentinelResourceName = 'Office 365'; SentinelResourceId = 'c-office'; OperationName = 'Data fetch status change'; Records = 30; Failures = 3; LastFailure = (& $iso $now.AddHours(-30)); Reason = 'Unauthorized [401]' }
        )
    }
}
@{ Now = $now; WorkspaceId = $customerId; ResourceId = $ws; Workspace = $workspace; Arm = $arm; Kql = $kql }
