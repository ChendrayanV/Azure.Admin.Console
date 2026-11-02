<#
    Unit tests for Invoke-AACSentinelAssessment over a made-up Contoso workspace
    (Fixtures\ContosoSentinel.ps1): Resource Manager, Resource Graph and the
    KQL queries are faked; the assessment's rules, the view and the exports run
    for real.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    $script:contoso = & (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Fixtures/ContosoSentinel.ps1')
    $script:capture = {
        param([scriptblock] $Render)
        $real = [Spectre.Console.AnsiConsole]::Console
        $buffer = [System.IO.StringWriter]::new()
        $settings = [Spectre.Console.AnsiConsoleSettings]::new()
        $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer)
        $settings.Ansi = [Spectre.Console.AnsiSupport]::No
        $settings.Enrichment.UseDefaultEnrichers = $false
        $console = [Spectre.Console.AnsiConsole]::Create($settings)
        $console.Profile.Width = 220
        try { [Spectre.Console.AnsiConsole]::Console = $console; $output = @(& $Render) }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
    $script:convert = {
        param([hashtable] $Override = @{})
        $c = $script:contoso
        InModuleScope 'Azure.Admin.Console' -Parameters @{ C = $c; O = $Override } {
            param($C, $O)
            $arguments = @{ Workspace = $C.Workspace; Arm = $C.Arm; Kql = $C.Kql; Days = 30; Now = $C.Now }
            foreach ($key in $O.Keys) { $arguments[$key] = $O[$key] }
            ConvertTo-AACSentinelAssessment @arguments
        }
    }
}

Describe 'Azure Admin Console - the Sentinel assessment''s queries' {
    It 'turns Usage''s MB into GB and looks back -Days' {
        $queries = InModuleScope 'Azure.Admin.Console' { Get-AACSentinelAssessmentQuery -Days 7 }
        $queries['tables'] | Should -Match 'ago\(7d\)'
        $queries['tables'] | Should -Match '/ 1000\.' -Because 'Usage''s Quantity is in MB'
        $queries['health'] | Should -Match '^_SentinelHealth\(\)' -Because 'Microsoft recommends the function over the table'
        $queries['health'] | Should -Match 'ago\(7d\)'
    }

    It 'asks only for what the sections need' {
        @(InModuleScope 'Azure.Admin.Console' { (Get-AACSentinelAssessmentQuery -Section DataConnectors).Keys }).Count | Should -Be 0
        @(InModuleScope 'Azure.Admin.Console' { (Get-AACSentinelAssessmentQuery -Section Health).Keys }) | Should -Be @('health')
        @(InModuleScope 'Azure.Admin.Console' { (Get-AACSentinelAssessmentQuery -Section Incidents).Keys }) | Should -Be @('incidentTimes')
        @(InModuleScope 'Azure.Admin.Console' { (Get-AACSentinelAssessmentQuery -Section RuleTemplates).Keys }) | Should -Be @('tables') -Because 'a template is suggested only if its data is arriving'
    }
}

Describe 'Azure Admin Console - the Sentinel assessment''s rules' {
    It 'reads every analytics rule, failing rules first' {
        $rules = @((& $script:convert).AnalyticsRules)
        $rules.Count | Should -Be 4
        $rules[0].Name | Should -Be 'Brute force on VMs'
        $rules[0].Failures | Should -Be 12
        $rules[0].Kind | Should -Be 'Scheduled'
        $rules[0].Techniques | Should -Be 'T1110'
        $rules[0].CreatesIncident | Should -BeTrue
        ($rules | Where-Object Name -EQ 'Rare admin sign-in').Tactics | Should -Be 'InitialAccess, Persistence'
        ($rules | Where-Object Name -EQ 'Rare admin sign-in').Failures | Should -Be 0
        ($rules | Where-Object Kind -EQ 'Fusion').Frequency | Should -BeNullOrEmpty -Because 'only scheduled rules have a frequency'
    }

    It 'matches health to a rule by display name when health has no resource ID' {
        $row = [ordered]@{ SentinelResourceType = 'Analytics Rule'; SentinelResourceName = 'Rare admin sign-in'; SentinelResourceId = ''; OperationName = 'Run'; Records = 2; Failures = 2; LastFailure = $script:contoso.Now.ToString('o'); Reason = 'x' }
        $a = & $script:convert @{ Kql = @{ Rows = @{ health = @($row) }; Errors = @{} } }
        ($a.AnalyticsRules | Where-Object Name -EQ 'Rare admin sign-in').Failures | Should -Be 2
    }

    It 'reads each connector''s state, whichever way the connector reports it' {
        $connectors = @((& $script:convert).DataConnectors)
        $state = { param([string] $Id) ($connectors | Where-Object ConnectorId -EQ $Id) }
        (& $state 'c-office').State | Should -Be 'Connected' -Because 'one data type on is enough'
        (& $state 'c-office').DataTypes | Should -Be 'exchange, sharePoint, teams'
        (& $state 'c-tip').State | Should -Be 'Disconnected'
        (& $state 'c-poller').State | Should -Be 'Connected'
        (& $state 'c-poller').Name | Should -Be 'Contoso API'
        (& $state 'c-poller').DataTypes | Should -Be 'ContosoApi_CL'
        (& $state 'c-ui').State | Should -Be 'Unknown'
        (& $state 'c-ui').Name | Should -Be 'Contoso legacy feed'
    }

    It 'merges ingestion with table properties, largest first, keeping custom tables' {
        $a = & $script:convert
        $tables = @($a.Tables)
        $tables[0].Table | Should -Be 'SecurityEvent'
        $tables[0].SharePercent | Should -Be 60
        $tables[0].DailyAverageGB | Should -Be 2
        $tables[0].TotalRetentionDays | Should -Be 365
        ($tables | Where-Object Table -EQ 'App_CL').Plan | Should -Be 'Basic'
        $tables.Table | Should -Contain 'Unused_CL' -Because 'custom tables are listed even when empty'
        $tables.Table | Should -Not -Contain 'W3CIISLog' -Because 'an empty Azure table is left out'
        $a.Stats.BillableGB | Should -Be 100
        $a.Stats.TablesWithData | Should -Be 4
    }

    It 'lists every table with -IncludeEmptyTable' {
        (& $script:convert @{ IncludeEmptyTable = $true }).Tables.Table | Should -Contain 'W3CIISLog'
    }

    It 'calls a billable table silent after 48 hours, and leaves free tables out' {
        $tables = @((& $script:convert).Tables)
        ($tables | Where-Object Table -EQ 'Syslog').Silent | Should -BeTrue
        ($tables | Where-Object Table -EQ 'SigninLogs').Silent | Should -BeFalse
        ($tables | Where-Object Table -EQ 'Operation').Silent | Should -BeFalse -Because 'free tables are written now and then by design'
        ($tables | Where-Object Table -EQ 'Unused_CL').Silent | Should -BeFalse -Because 'it had no data to stop'
    }

    It 'recommends, by severity: <Title>' -ForEach @(
        @{ Title = '1 enabled analytics rule(s) are failing'; Severity = 'High' }
        @{ Title = '1 table(s) stopped receiving data'; Severity = 'High' }
        @{ Title = '1 connector or automation operation(s) reported failures'; Severity = 'Medium' }
        @{ Title = '1 billable table(s) aren''t read by any enabled rule'; Severity = 'Medium' }
        @{ Title = '1 rule template(s) could be enabled'; Severity = 'Medium' }
        @{ Title = 'No enabled rule covers 11 of 14 MITRE ATT&CK tactics'; Severity = 'Medium' }
        @{ Title = '1 open incident(s) have no owner'; Severity = 'Medium' }
        @{ Title = 'Incidents are slow to close'; Severity = 'Medium' }
        @{ Title = '1 analytics rule(s) are noisy'; Severity = 'Low' }
        @{ Title = '1 automation rule(s) have expired'; Severity = 'Low' }
        @{ Title = '1 automation rule(s) are disabled'; Severity = 'Low' }
        @{ Title = '1 enabled rule(s) have a newer template'; Severity = 'Low' }
    ) {
        $found = @((& $script:convert).Recommendations | Where-Object Recommendation -EQ $Title)
        $found.Count | Should -Be 1
        $found[0].Severity | Should -Be $Severity
        $found[0].Action | Should -Not -BeNullOrEmpty
        $found[0].LearnMore | Should -Match '^https://learn\.microsoft\.com/'
    }

    It 'counts the enabled rules that name a table, whole words only' {
        $tables = @((& $script:convert).Tables)
        ($tables | Where-Object Table -EQ 'SecurityEvent').UsedByRules | Should -Be 1
        ($tables | Where-Object Table -EQ 'Syslog').UsedByRules | Should -Be 0 -Because 'only a disabled rule reads it'
        $arm = @{} + $script:contoso.Arm
        $arm['alertRules'] = @{ Status = 200; Error = ''; Body = $null; Items = @(@{ name = 'r'; kind = 'Scheduled'; properties = @{ displayName = 'r'; enabled = $true; query = 'SecurityEvents_Old | take 1' } }) }
        ((& $script:convert @{ Arm = $arm }).Tables | Where-Object Table -EQ 'SecurityEvent').UsedByRules | Should -Be 0 -Because 'another table''s name containing this one is no use of it'
    }

    It 'leaves table use unknown, and raises nothing about it, when the rules couldn''t be read' {
        $arm = @{} + $script:contoso.Arm
        $arm['alertRules'] = @{ Status = 403; Error = 'Forbidden'; Body = $null; Items = $null }
        $a = & $script:convert @{ Arm = $arm }
        ($a.Tables | Where-Object Table -EQ 'Syslog').UsedByRules | Should -BeNullOrEmpty
        $a.Recommendations.Recommendation | Should -Not -Match 'read by any enabled rule|could be enabled|MITRE'
        @($a.TacticCoverage).Count | Should -Be 0
    }

    It 'counts MITRE tactics from enabled rules only, and keeps disabled ones apart' {
        $arm = @{} + $script:contoso.Arm
        $arm['alertRules'] = @{ Status = 200; Error = ''; Body = $null; Items = @(@{ name = 'r'; kind = 'Scheduled'; properties = @{ displayName = 'r'; enabled = $false; tactics = @('Impact') } }) }
        $a = & $script:convert @{ Arm = $arm }
        $impact = $a.TacticCoverage | Where-Object Tactic -EQ 'Impact'
        $impact.EnabledRules | Should -Be 0
        $impact.DisabledRules | Should -Be 1
        $a.Stats.TacticsCovered | Should -Be 0
        $a.Stats.TacticsTotal | Should -Be 14
    }

    It 'suggests a template only when its data arrives, no rule uses it and it is available' {
        $templates = @((& $script:convert).RuleTemplates)
        $templates[0].Name | Should -Be 'Impossible travel' -Because 'candidates come first'
        $templates[0].Candidate | Should -BeTrue
        $byId = @{}; foreach ($t in $templates) { $byId[$t.TemplateId] = $t }
        $byId['tmpl-1'].Candidate | Should -BeFalse -Because 'a rule uses it'
        $byId['tmpl-1'].InUse | Should -BeTrue
        $byId['tmpl-3'].MissingData | Should -Be 'CommonSecurityLog' -Because 'the note after the table name is dropped'
        $byId['tmpl-3'].Candidate | Should -BeFalse
        $byId['tmpl-4'].InUse | Should -BeTrue -Because 'Azure counts a rule made from it'
        $byId['tmpl-5'].DataAvailable | Should -BeTrue
        $byId['tmpl-5'].Candidate | Should -BeFalse -Because 'it isn''t available'
        $byId['tmpl-fusion'].Candidate | Should -BeFalse -Because 'without data types there is no evidence for it'
    }

    It 'suggests no template when ingestion couldn''t be read' {
        $kql = @{ Rows = @{ tables = @() }; Errors = @{ tables = 'Query timed out' } }
        @((& $script:convert @{ Kql = $kql }).RuleTemplates | Where-Object Candidate).Count | Should -Be 0
    }

    It 'flags a rule whose template moved on, comparing versions as numbers' {
        $rule = (& $script:convert).AnalyticsRules | Where-Object Name -EQ 'Brute force on VMs'
        $rule.TemplateUpdate | Should -BeTrue
        $rule.LatestTemplate | Should -Be '1.2.0'
        $arm = @{} + $script:contoso.Arm
        $arm['alertRuleTemplates'] = @{ Status = 200; Error = ''; Body = $null; Items = @(@{ name = 'tmpl-1'; properties = @{ version = '1.0.0' } }) }
        ((& $script:convert @{ Arm = $arm }).AnalyticsRules | Where-Object Name -EQ 'Brute force on VMs').TemplateUpdate | Should -BeFalse
    }

    It 'reads incidents, taking close times from SecurityIncident for closed ones only' {
        $incidents = @((& $script:convert).Incidents)
        $incidents.Count | Should -Be 9
        $incidents[0].Number | Should -Be 3 -Because 'newest first'
        $byNumber = @{}; foreach ($i in $incidents) { $byNumber[[int]$i.Number] = $i }
        $byNumber[4].HoursToClose | Should -Be 100
        $byNumber[9].HoursToClose | Should -BeNullOrEmpty -Because 'no close time is left blank, not estimated'
        $byNumber[2].HoursToClose | Should -BeNullOrEmpty -Because 'it is open, whatever an earlier close said'
        $byNumber[2].HoursOpen | Should -Be 120
        $byNumber[2].Owner | Should -Be 'analyst@contoso.example'
        $byNumber[1].Owner | Should -Be ''
        $byNumber[1].Alerts | Should -Be 2
    }

    It 'gives only incidents open over a day as having no owner' {
        $found = (& $script:convert).Recommendations | Where-Object Recommendation -Match 'no owner'
        $found.Detail | Should -Match '#1 Incident 1'
        $found.Detail | Should -Not -Match '#3 Incident 3' -Because 'it is two hours old'
    }

    It 'works out the incident stats, and credits a rule with its incidents' {
        $a = & $script:convert
        $a.Stats.Incidents | Should -Be 9
        $a.Stats.OpenIncidents | Should -Be 3
        $a.Stats.MedianHoursToClose | Should -Be 100
        $a.Stats.FalsePositivePercent | Should -Be 66.7
        $rule = $a.AnalyticsRules | Where-Object Name -EQ 'Rare admin sign-in'
        $rule.Incidents | Should -Be 6
        $rule.ClosedIncidents | Should -Be 6
        $rule.FalsePositives | Should -Be 4
    }

    It 'calls a rule noisy only after enough closed incidents' {
        $few = @{ Status = 200; Error = ''; Body = $null; Items = @(@($script:contoso.Arm.incidents.Items) | Where-Object { $_.properties.incidentNumber -le 7 }) }
        $arm = @{} + $script:contoso.Arm
        $arm['incidents'] = $few
        (& $script:convert @{ Arm = $arm }).Recommendations.Recommendation | Should -Not -Contain '1 analytics rule(s) are noisy' -Because 'four closed incidents are too few to call it a pattern'
    }

    It 'doesn''t report a missing SecurityIncident table, and reports other failures' {
        $missing = @{ Rows = @{ incidentTimes = @() }; Errors = @{ incidentTimes = "Failed to resolve table or column expression named 'SecurityIncident'" } }
        (& $script:convert @{ Kql = $missing }).Errors.Count | Should -Be 0
        $failed = @{ Rows = @{ incidentTimes = @() }; Errors = @{ incidentTimes = 'Query timed out' } }
        (& $script:convert @{ Kql = $failed }).Errors['Incident times (SecurityIncident)'] | Should -Be 'Query timed out'
    }

    It 'gives each automation rule its state, in the order they run' {
        $rules = @((& $script:convert).AutomationRules)
        @($rules.Name) | Should -Be @('Assign to the SOC', 'Suppress during migration', 'Old notification', 'Temporary tagging')
        @($rules.State) | Should -Be @('Enabled', 'Expired', 'Disabled', 'Enabled') -Because 'an expiry still ahead is not expired'
        $rules[0].Actions | Should -Be 'ModifyProperties, RunPlaybook'
        $rules[0].Conditions | Should -Be 1
        $rules[1].Conditions | Should -Be 0
        $rules[0].ModifiedBy | Should -Be 'admin@contoso.example'
    }

    It 'names only enabled rules as failing' {
        $found = (& $script:convert).Recommendations | Where-Object Recommendation -Match 'are failing'
        $found.Detail | Should -Match 'Brute force on VMs'
        $found.Detail | Should -Not -Match 'Old disabled rule'
    }

    It 'orders recommendations High, Medium, Low' {
        $order = @{ High = 0; Medium = 1; Low = 2 }
        $severities = @((& $script:convert).Recommendations | ForEach-Object { $order[$_.Severity] })
        $severities | Should -Be @($severities | Sort-Object)
    }

    It 'treats a missing _SentinelHealth as health monitoring off, not a read error' -ForEach @(
        @{ Message = "Failed to resolve table or column expression named '_SentinelHealth'" }
        @{ Message = "Unknown function: '_SentinelHealth'" }
    ) {
        $a = & $script:convert @{ Kql = @{ Rows = @{ health = @() }; Errors = @{ health = $Message } } }
        $a.HealthState | Should -Be 'Off'
        $a.Errors.Count | Should -Be 0
        $a.Recommendations.Recommendation | Should -Contain 'Sentinel health monitoring appears to be off'
    }

    It 'treats no health records as health monitoring off' {
        $a = & $script:convert @{ Kql = @{ Rows = @{ health = @() }; Errors = @{} } }
        $a.HealthState | Should -Be 'NoRecords'
        $a.Recommendations.Recommendation | Should -Contain 'Sentinel health monitoring appears to be off'
    }

    It 'doesn''t say health is off when health wasn''t read, or when the query failed for another reason' {
        (& $script:convert @{ Kql = @{ Rows = @{}; Errors = @{} } }).Recommendations.Recommendation | Should -Not -Contain 'Sentinel health monitoring appears to be off'
        $a = & $script:convert @{ Kql = @{ Rows = @{ health = @() }; Errors = @{ health = 'Query timed out' } } }
        $a.HealthState | Should -Be 'Unknown'
        $a.Errors['Health (_SentinelHealth)'] | Should -Be 'Query timed out'
        $a.Recommendations.Recommendation | Should -Not -Contain 'Sentinel health monitoring appears to be off'
    }

    It 'reports what couldn''t be read, with the role to ask for, and carries on' {
        $arm = @{} + $script:contoso.Arm
        $arm['alertRules'] = @{ Status = 403; Error = 'Forbidden'; Body = $null; Items = $null }
        $a = & $script:convert @{ Arm = $arm }
        $a.Errors['Analytics rules'] | Should -Match 'Microsoft Sentinel Reader'
        @($a.AnalyticsRules).Count | Should -Be 0
        @($a.Tables).Count | Should -BeGreaterThan 0
    }

    It 'says so when Sentinel isn''t enabled, without treating that as an error' {
        $a = & $script:convert @{ Arm = @{ onboarding = @{ Status = 404; Error = 'Not found'; Body = $null; Items = $null } }; Kql = @{ Rows = @{}; Errors = @{} }; NotOnboarded = $true }
        $a.Workspace.SentinelEnabled | Should -BeFalse
        $a.Errors.Count | Should -Be 0
        $a.Recommendations[0].Severity | Should -Be 'High'
        $a.Recommendations[0].Recommendation | Should -Be 'Microsoft Sentinel is not enabled on this workspace'
        @($a.Recommendations).Count | Should -Be 1
    }
}

Describe 'Azure Admin Console - Invoke-AACSentinelAssessment' {
    BeforeEach {
        $script:graphQueries = @(); $script:armUris = @(); $script:kqlQueries = @(); $script:kqlWorkspace = $null
        $script:onboarding = $script:contoso.Arm.onboarding
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $script:graphQueries += @($Query.Keys)
            @{ Rows = @{ workspace = @(@{ id = $script:contoso.ResourceId }) }; Errors = @{} }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $script:armUris += @($Uri)
            $out = @{}
            foreach ($u in $Uri) {
                $out[$u] = switch -Regex ($u) {
                    '/workspaces/law-contoso-sentinel\?' { @{ Status = 200; Body = $script:contoso.Workspace; Items = $null; Error = '' } }
                    '/onboardingStates\?' { $script:onboarding }
                    '/alertRules\?' { $script:contoso.Arm.alertRules }
                    '/alertRuleTemplates\?' { $script:contoso.Arm.alertRuleTemplates }
                    '/incidents\?' { $script:contoso.Arm.incidents }
                    '/automationRules\?' { $script:contoso.Arm.automationRules }
                    '/dataConnectors\?' { $script:contoso.Arm.dataConnectors }
                    '/tables\?' { $script:contoso.Arm.tables }
                }
            }
            $out
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACLogQueryBatch -MockWith {
            $script:kqlWorkspace = $WorkspaceId
            $script:kqlQueries = @($Query.Keys)
            $rows = @{}
            foreach ($name in @($Query.Keys)) { $rows[$name] = @($script:contoso.Kql.Rows[$name]) }
            @{ Rows = $rows; Errors = @{} }
        }
    }

    It 'finds the workspace by its workspace ID and returns one assessment' {
        $result = Invoke-AACSentinelAssessment -WorkspaceId $script:contoso.WorkspaceId -NoDisplay
        $result.PSObject.TypeNames[0] | Should -Be 'AAC.SentinelAssessment'
        $result.Name | Should -Be 'law-contoso-sentinel'
        $result.SentinelEnabled | Should -BeTrue
        $result.BillableGB | Should -Be 100
        $result.AnalyticsRules[0].PSObject.TypeNames[0] | Should -Be 'AAC.SentinelAnalyticsRule'
        $result.DataConnectors[0].PSObject.TypeNames[0] | Should -Be 'AAC.SentinelDataConnector'
        $result.Tables[0].PSObject.TypeNames[0] | Should -Be 'AAC.SentinelTable'
        $result.HealthFailures[0].PSObject.TypeNames[0] | Should -Be 'AAC.SentinelHealthFailure'
        $result.Recommendations[0].PSObject.TypeNames[0] | Should -Be 'AAC.SentinelRecommendation'
        $script:graphQueries | Should -Contain 'workspace'
        $script:kqlWorkspace | Should -Be $script:contoso.WorkspaceId -Because 'KQL goes to the workspace ID'
    }

    It 'takes a resource ID without a Resource Graph lookup, and reads the current stable Sentinel API' {
        $null = Invoke-AACSentinelAssessment -WorkspaceId $script:contoso.ResourceId -NoDisplay
        $script:graphQueries | Should -Not -Contain 'workspace'
        @($script:armUris | Where-Object { $_ -like '*/providers/Microsoft.SecurityInsights/*' }).Count | Should -Be 6
        @($script:armUris | Where-Object { $_ -like '*/providers/Microsoft.SecurityInsights/*' -and $_ -notlike '*api-version=2025-09-01*' }).Count | Should -Be 0
    }

    It 'asks only for the incidents of the last -Days' {
        $null = Invoke-AACSentinelAssessment -WorkspaceId $script:contoso.ResourceId -Section Incidents -Days 7 -NoDisplay
        $uri = @($script:armUris | Where-Object { $_ -match '/incidents\?' })[0]
        $uri | Should -Match '\$filter=properties%2FcreatedTimeUtc%20ge%20\d{4}-\d{2}-\d{2}T\d{2}%3A\d{2}%3A\d{2}Z'
        $since = [datetime]::Parse([uri]::UnescapeDataString(($uri -split '%20ge%20')[1]), [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
        ([datetime]::UtcNow - $since).TotalDays | Should -BeGreaterOrEqual 6.9
        ([datetime]::UtcNow - $since).TotalDays | Should -BeLessOrEqual 7.1
    }

    It 'reads the rules and ingestion a template''s candidacy depends on' {
        $result = Invoke-AACSentinelAssessment -WorkspaceId $script:contoso.ResourceId -Section RuleTemplates -NoDisplay
        @($script:armUris | Where-Object { $_ -match '/alertRules\?|/alertRuleTemplates\?|/tables\?' }).Count | Should -Be 3
        @($script:kqlQueries) | Should -Be @('tables')
        @($result.RuleTemplates | Where-Object Candidate).Count | Should -BeGreaterThan 0
    }

    It 'reads only what -Section asks for' {
        $result = Invoke-AACSentinelAssessment -WorkspaceId $script:contoso.ResourceId -Section DataConnectors -NoDisplay
        @($script:kqlQueries).Count | Should -Be 0
        @($script:armUris | Where-Object { $_ -match '/alertRules\?|/tables\?' }).Count | Should -Be 0
        @($result.DataConnectors).Count | Should -Be 4
        $result.HealthState | Should -Be 'Unknown'
    }

    It 'looks back -Days in the queries' {
        $null = Invoke-AACSentinelAssessment -WorkspaceId $script:contoso.ResourceId -Days 7 -NoDisplay
        Should -Invoke -ModuleName 'Azure.Admin.Console' Invoke-AACLogQueryBatch -ParameterFilter { $Timespan -eq 'P7D' -and $Query['tables'] -match 'ago\(7d\)' }
    }

    It 'stops at the recommendation when Sentinel isn''t enabled: <Title>' -ForEach @(
        @{ Title = 'a 404'; State = @{ Status = 404; Error = 'Not found'; Body = $null; Items = $null } }
        @{ Title = 'an empty list'; State = @{ Status = 200; Error = ''; Body = $null; Items = @() } }
    ) {
        $script:onboarding = $State
        $result = Invoke-AACSentinelAssessment -WorkspaceId $script:contoso.ResourceId -NoDisplay
        $result.SentinelEnabled | Should -BeFalse
        $result.Recommendations[0].Recommendation | Should -Be 'Microsoft Sentinel is not enabled on this workspace'
        @($script:armUris | Where-Object { $_ -match '/alertRules\?|/dataConnectors\?|/tables\?' }).Count | Should -Be 0
        Should -Invoke -ModuleName 'Azure.Admin.Console' Invoke-AACLogQueryBatch -Exactly 0
    }

    It 'carries on when the onboarding state can''t be read for lack of permission' {
        $script:onboarding = @{ Status = 403; Error = 'Forbidden'; Body = $null; Items = $null }
        $result = Invoke-AACSentinelAssessment -WorkspaceId $script:contoso.ResourceId -NoDisplay
        $result.SentinelEnabled | Should -BeTrue
        $result.Errors['Onboarding state'] | Should -Match 'Microsoft Sentinel Reader'
        @($result.AnalyticsRules).Count | Should -Be 4
    }

    It 'says when no workspace has that workspace ID' {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith { @{ Rows = @{ workspace = @() }; Errors = @{} } }
        { $null = & $script:capture { Invoke-AACSentinelAssessment -WorkspaceId '99999999-9999-9999-9999-999999999999' -NoDisplay } } | Should -Throw -ExpectedMessage '*No Log Analytics workspace with workspace ID 99999999*'
    }

    It 'shows recommendations, rules, connectors, tables and health failures' {
        $text = (& $script:capture { Invoke-AACSentinelAssessment -WorkspaceId $script:contoso.ResourceId -NoPaging }).Text
        foreach ($expected in 'Recommendations', '1 enabled analytics rule(s) are failing', 'Analytics rules', 'Brute force on VMs', 'Enabled rules per MITRE ATT&CK tactic', 'CredentialAccess', 'Rule templates to consider', 'Impossible travel', 'Data connectors', 'Contoso API', 'Tables and ingestion', 'SecurityEvent', 'Health failures', 'The query timed out', 'Unauthorized [401]', 'Open incidents', 'Incident 1', 'median to close', 'Automation rules', 'Assign to the SOC', 'Expired') {
            $text | Should -Match ([regex]::Escape($expected))
        }
    }

    It 'writes the analytics rules to CSV, and every section to a tabbed HTML report, instead of the view' {
        $csv = Join-Path $TestDrive 'rules.csv'
        $html = Join-Path $TestDrive 'sentinel.html'
        $text = (& $script:capture { Invoke-AACSentinelAssessment -WorkspaceId $script:contoso.ResourceId -CsvPath $csv -HtmlPath $html }).Text
        $text | Should -Not -Match 'Tables and ingestion'
        $rows = @(Import-Csv -LiteralPath $csv)
        $rows.Count | Should -Be 4
        $rows.Name | Should -Contain 'Brute force on VMs'
        $rows[0].PSObject.Properties.Name | Should -Contain 'Query'
        $page = Get-Content -LiteralPath $html -Raw
        $model = [regex]::Match($page, '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        $model.overviewTab | Should -Be 'Summary'
        @($model.tabs.name) | Should -Be @('Recommendations', 'Analytics rules', 'Rule templates', 'Data connectors', 'Tables', 'Health', 'Incidents', 'Automation rules')
        ($model.tables | Where-Object id -EQ 'tactics').section | Should -Be 'Analytics rules'
        ($model.tables | Where-Object id -EQ 'incidents').section | Should -Be 'Incidents'
        foreach ($expected in 'Analytics rules', 'MITRE ATT&CK coverage', 'Rule templates', 'Data connectors', 'Tables and ingestion', 'Health failures (_SentinelHealth)', 'Incidents', 'Automation rules') {
            @($model.tables.title) | Should -Contain $expected
        }
    }

    It 'gives only the sections asked for a tab' {
        $html = Join-Path $TestDrive 'some.html'
        $null = & $script:capture { Invoke-AACSentinelAssessment -WorkspaceId $script:contoso.ResourceId -Section Incidents, Recommendations -HtmlPath $html }
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.tabs.name) | Should -Be @('Recommendations', 'Incidents')
    }

    It 'writes a report saying so when Sentinel isn''t enabled' {
        $script:onboarding = @{ Status = 404; Error = 'Not found'; Body = $null; Items = $null }
        $html = Join-Path $TestDrive 'not-enabled.html'
        $null = & $script:capture { Invoke-AACSentinelAssessment -WorkspaceId $script:contoso.ResourceId -HtmlPath $html }
        $page = Get-Content -LiteralPath $html -Raw
        $page | Should -Match 'Microsoft Sentinel is not enabled on this workspace'
        $model = [regex]::Match($page, '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.tabs.name) | Should -Be @('Recommendations')
    }

    It 'writes a PDF report, a bookmarked heading per section' -Skip:(-not ($IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4')) {
        $pdf = Join-Path $TestDrive 'sentinel.pdf'
        $null = & $script:capture { Invoke-AACSentinelAssessment -WorkspaceId $script:contoso.ResourceId -PdfPath $pdf }
        (Get-Item -LiteralPath $pdf).Length | Should -BeGreaterThan 1000
        [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($pdf), 0, 5) | Should -Be '%PDF-'
    }

    It 'keeps the AAC type names of what it returns after drawing the view (-PassThru)' {
        $result = (& $script:capture { Invoke-AACSentinelAssessment -WorkspaceId $script:contoso.ResourceId -NoPaging -PassThru }).Output[0]
        @($result.AnalyticsRules | ForEach-Object { $_.PSObject.TypeNames[0] } | Select-Object -Unique) | Should -Be @('AAC.SentinelAnalyticsRule')
        @($result.Tables | ForEach-Object { $_.PSObject.TypeNames[0] } | Select-Object -Unique) | Should -Be @('AAC.SentinelTable')
    }

    It 'shows only the sections asked for' {
        $text = (& $script:capture { Invoke-AACSentinelAssessment -WorkspaceId $script:contoso.ResourceId -Section DataConnectors -NoPaging }).Text
        $text | Should -Match 'Data connectors'
        $text | Should -Not -Match 'Tables and ingestion'
        $text | Should -Not -Match 'Brute force on VMs'
    }

    It 'shows only the recommendation when Sentinel isn''t enabled' {
        $script:onboarding = @{ Status = 404; Error = 'Not found'; Body = $null; Items = $null }
        $text = (& $script:capture { Invoke-AACSentinelAssessment -WorkspaceId $script:contoso.ResourceId -NoPaging }).Text
        $text | Should -Match 'Not enabled'
        $text | Should -Match 'Microsoft Sentinel is not enabled on this workspace'
        $text | Should -Not -Match 'Tables and ingestion'
    }
}
