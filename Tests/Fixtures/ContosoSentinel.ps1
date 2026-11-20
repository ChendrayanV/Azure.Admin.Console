<#
    A made-up Microsoft Sentinel workspace for the Invoke-AACSentinelAssessment
    tests, in the shapes Azure returns: the workspace, its Sentinel resources
    (Resource Manager) and KQL rows. Built so every rule has something to find:
    an enabled rule failing, a disabled rule failing (not reported), a table
    that stopped receiving data and no enabled rule reads, a failing connector,
    a template to enable, a rule with a newer template, MITRE gaps, an old open
    incident with no owner, slow closes, a noisy rule, and expired and disabled
    automation.

    The Get-AACSentinel* commands share it: Arm also has watchlists, saved
    searches and Content hub packages (installed, catalog, templates); Kql has
    SecurityAlert rows, the incidents those alerts are in, and watchlist item
    counts. Each command has something to find: alerts with entities to
    parse, a recurring alert, alerts in no incident; a watchlist in use, one
    stale and unused, one empty, one failed; a solution with an update, one
    deprecated, one with no rule enabled.

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
        @{ name = 'a-1'; properties = @{ displayName = 'Assign to the SOC'; order = 1; triggeringLogic = @{ isEnabled = $true; triggersOn = 'Incidents'; triggersWhen = 'Created'; conditions = @(@{ conditionType = 'Property' }) }; actions = @(@{ order = 1; actionType = 'ModifyProperties' }, @{ order = 2; actionType = 'RunPlaybook'; actionConfiguration = @{ logicAppResourceId = "/subscriptions/$sub/resourceGroups/rg-contoso-sec/providers/Microsoft.Logic/workflows/pb-assign"; tenantId = 'tenant' } }); lastModifiedBy = @{ email = 'admin@contoso.example' } } }
        @{ name = 'a-2'; properties = @{ displayName = 'Suppress during migration'; order = 2; triggeringLogic = @{ isEnabled = $true; expirationTimeUtc = (& $iso $now.AddDays(-3)); triggersOn = 'Incidents'; triggersWhen = 'Created' }; actions = @(@{ order = 1; actionType = 'ModifyProperties' }) } }
        @{ name = 'a-3'; properties = @{ displayName = 'Old notification'; order = 3; triggeringLogic = @{ isEnabled = $false; triggersOn = 'Alerts'; triggersWhen = 'Created' }; actions = @(@{ order = 1; actionType = 'RunPlaybook'; actionConfiguration = @{ logicAppResourceId = "/subscriptions/$sub/resourceGroups/rg-contoso-sec/providers/Microsoft.Logic/workflows/pb-notify" } }) } }
        @{ name = 'a-4'; properties = @{ displayName = 'Temporary tagging'; order = 4; triggeringLogic = @{ isEnabled = $true; expirationTimeUtc = (& $iso $now.AddDays(3)); triggersOn = 'Incidents'; triggersWhen = 'Updated' }; actions = @(@{ order = 1; actionType = 'AddIncidentTask' }, @{ order = 2; actionType = 'RunPlaybook'; actionConfiguration = @{ logicAppResourceId = "/subscriptions/$sub/resourceGroups/rg-contoso-sec/providers/Microsoft.Logic/workflows/pb-gone" } }) } }
    )
    alertRules     = & $list @(
        @{ name = 'rule-1'; kind = 'Scheduled'; properties = @{ displayName = 'Brute force on VMs'; enabled = $true; severity = 'High'; tactics = @('CredentialAccess'); techniques = @('T1110'); query = 'SecurityEvent | where EventID == 4625'; queryFrequency = 'PT1H'; queryPeriod = 'PT1H'; alertRuleTemplateName = 'tmpl-1'; templateVersion = '1.0.0'; lastModifiedUtc = '2026-09-01T10:00:00Z'; incidentConfiguration = @{ createIncident = $true }; entityMappings = @(@{ entityType = 'Host'; fieldMappings = @(@{ identifier = 'HostName'; columnName = 'Computer' }) }, @{ entityType = 'Account'; fieldMappings = @(@{ identifier = 'Name'; columnName = 'TargetAccount' }) }) } }
        @{ name = 'rule-2'; kind = 'Scheduled'; properties = @{ displayName = 'Rare admin sign-in'; enabled = $true; severity = 'Medium'; tactics = @('InitialAccess', 'Persistence'); query = 'SigninLogs | where UserPrincipalName in (_GetWatchlist(''VIPUsers'') | project SearchKey)'; queryFrequency = 'PT5H'; queryPeriod = 'P1D'; incidentConfiguration = @{ createIncident = $true } } }
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
# --- For the Get-AACSentinel* commands ---------------------------------------------------------------------------
$watchlist = {
    param([string] $Id, [string] $DisplayName, [string] $Alias, [int] $UpdatedDaysAgo, [string] $State = 'Succeeded')
    @{ name = $Id; properties = @{
            displayName = $DisplayName; watchlistAlias = $Alias; itemsSearchKey = 'Key'; provider = 'Microsoft'; source = "$Alias.csv"; sourceType = 'Local file'
            created = (& $iso $now.AddDays(-500)); updated = (& $iso $now.AddDays(-$UpdatedDaysAgo)); updatedBy = @{ email = 'admin@contoso.example'; name = 'Contoso Admin' }
            provisioningState = $State; labels = @('soc'); defaultDuration = 'P30D'
        }
    }
}
$arm['watchlists'] = & $list @(
    (& $watchlist 'wl-vip' 'VIP users' 'VIPUsers' 10)
    (& $watchlist 'wl-old' 'Old IP ranges' 'OldRanges' 400)
    (& $watchlist 'wl-empty' 'Empty list' 'EmptyList' 5)
    (& $watchlist 'wl-broken' 'Broken upload' 'Broken' 2 'Failed')
)
$arm['savedSearches'] = & $list @(
    @{ name = 'hq-1'; properties = @{ category = 'Hunting Queries'; displayName = 'Sign-ins from the empty list'; query = 'SigninLogs | where IPAddress in (_GetWatchlist("EmptyList") | project SearchKey)' } }
    # Not a hunting query: a saved search that names a watchlist isn't counted.
    @{ name = 'ss-1'; properties = @{ category = 'Log Management'; displayName = 'Old ranges report'; query = '_GetWatchlist(''OldRanges'')' } }
)
$package = {
    param([string] $ContentId, [string] $DisplayName, [string] $Version, [string] $Tier, [hashtable] $Extra = @{})
    $properties = @{ contentId = $ContentId; displayName = $DisplayName; contentKind = 'Solution'; version = $Version; publisherDisplayName = 'Contoso'; support = @{ tier = $Tier }; categories = @{ domains = @('Security - Others') }; lastPublishDate = '2026-08-01' }
    foreach ($k in $Extra.Keys) { $properties[$k] = $Extra[$k] }
    @{ name = $ContentId; properties = $properties }
}
$arm['contentPackages'] = & $list @(
    (& $package 'contoso.entra' 'Microsoft Entra ID' '3.0.5' 'Microsoft')
    (& $package 'contoso.windows' 'Windows Security Events' '2.0.0' 'Microsoft')
    (& $package 'contoso.legacyfw' 'Legacy Firewall' '1.0.0' 'Partner')
)
$arm['contentProductPackages'] = & $list @(
    (& $package 'contoso.entra' 'Microsoft Entra ID' '3.1.0' 'Microsoft' @{ installedVersion = '3.0.5' })
    (& $package 'contoso.windows' 'Windows Security Events' '2.0.0' 'Microsoft' @{ installedVersion = '2.0.0' })
    (& $package 'contoso.legacyfw' 'Legacy Firewall' '1.0.0' 'Partner' @{ installedVersion = '1.0.0'; isDeprecated = 'true' })
    (& $package 'contoso.okta' 'Okta Single Sign-On' '3.0.0' 'Partner')
)
$template = { param([string] $Id, [string] $PackageId, [string] $Kind) @{ name = "ct-$Id"; properties = @{ contentId = $Id; packageId = $PackageId; contentKind = $Kind; displayName = $Id } } }
$arm['contentTemplates'] = & $list @(
    # tmpl-1 is the template rule-1 (enabled) was created from.
    (& $template 'tmpl-1' 'contoso.entra' 'AnalyticsRule'), (& $template 'tmpl-2' 'contoso.entra' 'AnalyticsRule')
    (& $template 'wb-entra' 'contoso.entra' 'Workbook'), (& $template 'hq-entra' 'contoso.entra' 'HuntingQuery')
    (& $template 'tmpl-win-1' 'contoso.windows' 'AnalyticsRule'), (& $template 'tmpl-win-2' 'contoso.windows' 'AnalyticsRule')
    (& $template 'dc-win' 'contoso.windows' 'DataConnector'), (& $template 'parser-fw' 'contoso.legacyfw' 'Parser')
)
$kql = @{
    Errors = @{}
    Rows   = @{
        # SecurityAlert: the alert's entities, techniques and details are JSON text, as the table holds them.
        alerts        = @(
            [ordered]@{ TimeGenerated = (& $iso $now.AddHours(-2)); SystemAlertId = 'alert-1'; AlertName = 'Brute force on VMs'; AlertSeverity = 'High'; Status = 'New'; AlertType = 'Contoso_BruteForce'; ProviderName = 'ASI Scheduled Alerts'; ProductName = 'Azure Sentinel'; ProductComponentName = 'Scheduled Alerts'; VendorName = 'Microsoft'; CompromisedEntity = 'vm-web-01'; Tactics = 'CredentialAccess'; Techniques = '["T1110"]'; Description = 'Many failed sign-ins.'; RemediationSteps = '["Reset the password.","Block the IP address."]'; Entities = '[{"$id":"2","HostName":"vm-web-01","Type":"host"},{"$id":"3","Name":"alice","UPNSuffix":"contoso.example","Type":"account"},{"$id":"4","Address":"203.0.113.10","Type":"ip"},{"$ref":"2"}]'; ExtendedProperties = '{"Query Period":"01:00:00","Alert generation status":"Full alert created"}'; StartTime = (& $iso $now.AddHours(-3)); EndTime = (& $iso $now.AddHours(-2)); AlertLink = 'https://portal.azure.com/#alert/1' }
            foreach ($n in 2..4) {
                [ordered]@{ TimeGenerated = (& $iso $now.AddHours(-10 * $n)); SystemAlertId = "alert-$n"; AlertName = 'Rare admin sign-in'; AlertSeverity = 'Medium'; Status = $(if ($n -eq 4) { 'Resolved' } else { 'New' }); AlertType = 'Contoso_RareAdmin'; ProviderName = 'ASI Scheduled Alerts'; ProductName = 'Azure Sentinel'; ProductComponentName = 'Scheduled Alerts'; VendorName = 'Microsoft'; CompromisedEntity = 'bob@contoso.example'; Tactics = 'InitialAccess, Persistence'; Techniques = ''; Description = ''; RemediationSteps = ''; Entities = '[{"$id":"2","Name":"bob","NTDomain":"CONTOSO","Type":"account"}]'; ExtendedProperties = ''; StartTime = $null; EndTime = $null; AlertLink = '' }
            }
            [ordered]@{ TimeGenerated = (& $iso $now.AddDays(-3)); SystemAlertId = 'alert-5'; AlertName = 'Suspicious PowerShell command line'; AlertSeverity = 'Low'; Status = 'New'; AlertType = 'MDE_PowerShell'; ProviderName = 'MDATP'; ProductName = 'Microsoft Defender Advanced Threat Protection'; ProductComponentName = ''; VendorName = 'Microsoft'; CompromisedEntity = 'laptop-07'; Tactics = 'Execution, Unknown'; Techniques = '["T1059","T1059.001"]'; Description = 'PowerShell ran an encoded command.'; RemediationSteps = 'Isolate the device.'; Entities = '[{"$id":"2","HostName":"laptop-07","Type":"host"},{"$id":"3","CommandLine":"powershell -enc AAAA","Type":"process"}]'; ExtendedProperties = 'not json'; StartTime = $null; EndTime = $null; AlertLink = '' }
        )
        # Which incident each alert is in (SecurityIncident's AlertIds, expanded); IDs match in any case.
        incidents     = @(
            [ordered]@{ AlertId = 'alert-1'; IncidentNumber = 1; IncidentTitle = 'Incident 1'; IncidentStatus = 'New' }
            [ordered]@{ AlertId = 'ALERT-2'; IncidentNumber = 2; IncidentTitle = 'Incident 2'; IncidentStatus = 'Active' }
        )
        # Watchlist items now: EmptyList and Broken have none.
        items         = @(
            [ordered]@{ WatchlistAlias = 'VIPUsers'; Items = 25; LastItemUpdate = (& $iso $now.AddDays(-10)) }
            [ordered]@{ WatchlistAlias = 'OldRanges'; Items = 3; LastItemUpdate = (& $iso $now.AddDays(-400)) }
        )
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

# --- Playbooks: Resource Graph rows, their runs, and role assignments per resource group ------------------------
$workflowId = { param([string] $Group, [string] $Name) "/subscriptions/$sub/resourceGroups/$Group/providers/Microsoft.Logic/workflows/$Name" }
$sentinelTrigger = { param([string] $Path) @{ Microsoft_Sentinel_trigger = @{ type = 'ApiConnectionWebhook'; inputs = @{ host = @{ connection = @{ name = "@parameters('`$connections')['azuresentinel']['connectionId']" } }; path = $Path } } } }
$connection = { param([string] $Auth) $c = @{ connectionId = "/subscriptions/$sub/resourceGroups/rg/providers/Microsoft.Web/connections/azuresentinel"; id = "/subscriptions/$sub/providers/Microsoft.Web/locations/uksouth/managedApis/azuresentinel" }; if ($Auth) { $c['connectionProperties'] = @{ authentication = @{ type = $Auth } } }; @{ azuresentinel = $c } }
$playbooks = @(
    # Run by an enabled automation rule, with a managed identity; two of ten runs failed.
    @{ id = (& $workflowId 'rg-contoso-sec' 'pb-assign'); name = 'pb-assign'; resourceGroup = 'rg-contoso-sec'; subscriptionId = $sub; location = 'uksouth'; state = 'Enabled'; identityType = 'SystemAssigned'; triggers = (& $sentinelTrigger '/incident-creation'); connections = (& $connection 'ManagedServiceIdentity'); changedTime = '2026-09-01T00:00:00Z' }
    # Disabled, run only by a disabled automation rule, its connection signed in as an account.
    @{ id = (& $workflowId 'rg-contoso-sec' 'pb-notify'); name = 'pb-notify'; resourceGroup = 'rg-contoso-sec'; subscriptionId = $sub; location = 'uksouth'; state = 'Disabled'; identityType = ''; triggers = (& $sentinelTrigger '/subscribe'); connections = (& $connection ''); changedTime = '2026-01-01T00:00:00Z' }
    # In a resource group where Sentinel holds no Automation Contributor.
    @{ id = (& $workflowId 'rg-contoso-soar' 'pb-enrich'); name = 'pb-enrich'; resourceGroup = 'rg-contoso-soar'; subscriptionId = $sub; location = 'uksouth'; state = 'Enabled'; identityType = 'SystemAssigned'; triggers = (& $sentinelTrigger "/entity/@{encodeURIComponent('Account')}"); connections = (& $connection 'ManagedServiceIdentity'); changedTime = '2026-09-01T00:00:00Z' }
)
$run = { param([string] $Status, [int] $HoursAgo, [string] $Code = '') $r = @{ name = [guid]::NewGuid().ToString('n'); properties = @{ status = $Status; startTime = (& $iso $now.AddHours(-$HoursAgo)) } }; if ($Code) { $r.properties['error'] = @{ code = $Code; message = 'The incident was not found.' } }; $r }
$playbookRuns = @{
    'pb-assign' = & $list @((1..8 | ForEach-Object { & $run 'Succeeded' $_ }) + @((& $run 'Failed' 2 'NotFound'), (& $run 'Failed' 30 'Unauthorized')))
    'pb-notify' = & $list @()
    'pb-enrich' = & $list @()
}
$roleAssignments = @{
    'rg-contoso-sec'  = & $list @(@{ name = 'ra-1'; properties = @{ roleDefinitionId = "/subscriptions/$sub/providers/Microsoft.Authorization/roleDefinitions/f4c81013-99ee-4d62-a7ee-b3f1f648599a"; principalType = 'ServicePrincipal' } })
    'rg-contoso-soar' = & $list @(@{ name = 'ra-2'; properties = @{ roleDefinitionId = "/subscriptions/$sub/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"; principalType = 'User' } })
}

# --- Threat intelligence: STIX rows only (the legacy table is absent). Times are from the real clock,
# because the command measures freshness from now.
$real = [datetime]::UtcNow
$kql.Rows['stix'] = @(
    [ordered]@{ Source = 'Microsoft Defender Threat Intelligence'; IndicatorType = 'ipv4-addr'; Indicators = 1000; Active = 900; Expired = 100; ExpiringSoon = 50; AverageConfidence = 80.4; LowConfidence = 10; LastUpdated = (& $iso $real.AddHours(-1)) }
    [ordered]@{ Source = 'Contoso TAXII'; IndicatorType = 'domain-name'; Indicators = 200; Active = 0; Expired = 200; ExpiringSoon = 0; AverageConfidence = 30; LowConfidence = 150; LastUpdated = (& $iso $real.AddDays(-20)) }
)
$kql.Rows['stixList'] = @(
    [ordered]@{ Id = 'i-1'; IndicatorType = 'ipv4-addr'; Value = '203.0.113.10'; Source = 'Microsoft Defender Threat Intelligence'; Confidence = 90; IsActive = $true; ValidFrom = (& $iso $real.AddDays(-2)); ValidUntil = (& $iso $real.AddDays(30)); LastUpdated = (& $iso $real.AddHours(-1)); Tags = '["botnet","c2"]'; Name = 'C2 server'; Description = 'Command and control.' }
    [ordered]@{ Id = 'i-2'; IndicatorType = 'ipv4-addr'; Value = '198.51.100.7'; Source = 'Microsoft Defender Threat Intelligence'; Confidence = 60; IsActive = $true; ValidFrom = (& $iso $real.AddDays(-40)); ValidUntil = (& $iso $real.AddDays(-1)); LastUpdated = (& $iso $real.AddDays(-2)); Tags = ''; Name = ''; Description = '' }
    [ordered]@{ Id = 'i-3'; IndicatorType = 'domain-name'; Value = 'bad.contoso.example'; Source = 'Contoso TAXII'; Confidence = 20; IsActive = $false; ValidFrom = $null; ValidUntil = $null; LastUpdated = (& $iso $real.AddDays(-20)); Tags = ''; Name = ''; Description = '' }
)

# --- Ingestion delay per table (the 'delay' query) ---------------------------------------------------------------
$kql.Rows['delay'] = @(
    [ordered]@{ TableName = 'SecurityEvent'; Records = 5000; P50 = 2.0; P95 = 5.5; MaxDelay = 40.0; LastRecord = (& $iso $now.AddMinutes(-10)); LastIngested = (& $iso $now.AddMinutes(-5)) }
    [ordered]@{ TableName = 'SigninLogs'; Records = 800; P50 = 20.0; P95 = 75.0; MaxDelay = 180.0; LastRecord = (& $iso $now.AddMinutes(-30)); LastIngested = (& $iso $now.AddMinutes(-2)) }
)

@{ Now = $now; WorkspaceId = $customerId; ResourceId = $ws; Workspace = $workspace; Arm = $arm; Kql = $kql; Playbooks = $playbooks; PlaybookRuns = $playbookRuns; RoleAssignments = $roleAssignments }
