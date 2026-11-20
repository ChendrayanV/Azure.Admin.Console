<#
    Unit tests for the Get-AACSentinel* commands and Export-AACSentinelAnalyticsRule
    over the made-up Contoso workspace (Fixtures\ContosoSentinel.ps1): Resource
    Manager, Resource Graph and the KQL queries are faked; the conversions, the
    filters, the views and the files run for real.
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
    # The fixture's Resource Manager lists, by the path the commands read.
    $script:armFor = {
        param([string] $Uri)
        switch -Regex ($Uri) {
            '/workspaces/law-contoso-sentinel\?' { return @{ Status = 200; Body = $script:contoso.Workspace; Items = $null; Error = '' } }
            '/onboardingStates\?' { return $script:onboarding }
            '/alertRules\?' { return $script:contoso.Arm.alertRules }
            '/alertRuleTemplates\?' { return $script:contoso.Arm.alertRuleTemplates }
            '/incidents\?' { return $script:contoso.Arm.incidents }
            '/automationRules\?' { return $script:contoso.Arm.automationRules }
            '/watchlists\?' { return $script:contoso.Arm.watchlists }
            '/dataConnectors\?' { return $script:contoso.Arm.dataConnectors }
            '/workspaces/law-contoso-sentinel/tables\?' { return $script:contoso.Arm.tables }
            '/savedSearches\?' { return $script:contoso.Arm.savedSearches }
            '/contentPackages\?' { return $script:contoso.Arm.contentPackages }
            '/contentProductPackages\?' { return $script:contoso.Arm.contentProductPackages }
            '/contentTemplates\?' { return $script:contoso.Arm.contentTemplates }
            '/workflows/([^/]+)/runs\?' { return $script:contoso.PlaybookRuns[$Matches[1]] }
            '/resourceGroups/([^/]+)/providers/Microsoft\.Authorization/roleAssignments\?' { return $script:contoso.RoleAssignments[$Matches[1]] }
        }
        @{ Status = 404; Body = $null; Items = $null; Error = "No fake for $Uri" }
    }
}

Describe 'Azure Admin Console - the Sentinel commands' {
    BeforeEach {
        $script:armUris = @(); $script:kqlQueries = @{}; $script:kqlTimespan = $null; $script:kqlErrors = @{}
        # Per test: rows to return instead of the fixture's, by query name; result counts for replayed rule windows.
        $script:kqlRows = @{}; $script:windowCounts = @{}; $script:kqlTimespans = @{}
        $script:schema = @('TimeGenerated', 'Computer', 'Account', 'IpAddress')
        $script:onboarding = $script:contoso.Arm.onboarding
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            if ($Query.Contains('playbooks')) { return @{ Rows = @{ playbooks = @($script:contoso.Playbooks) }; Errors = @{} } }
            @{ Rows = @{ workspace = @(@{ id = $script:contoso.ResourceId }) }; Errors = @{} }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $script:armUris += @($Uri)
            $out = @{}
            foreach ($u in $Uri) { $out[$u] = & $script:armFor $u }
            $out
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACLogQueryBatch -MockWith {
            foreach ($name in @($Query.Keys)) { $script:kqlQueries[$name] = $Query[$name] }
            $script:kqlTimespan = $Timespan
            $rows = @{}
            $errors = @{}
            foreach ($name in @($Query.Keys)) {
                if ($Query[$name] -is [System.Collections.IDictionary]) { $script:kqlTimespans[$name] = $Query[$name]['Timespan'] }
                if ($script:kqlErrors.Contains($name)) { $errors[$name] = $script:kqlErrors[$name]; $rows[$name] = @() }
                elseif ($script:kqlRows.Contains($name)) { $rows[$name] = @($script:kqlRows[$name]) }
                # Test-AACSentinelRuleQuery's windows (q1r0...), schema and sample.
                elseif ($name -match '^q\d+r\d+$') { $rows[$name] = @([ordered]@{ Count = $(if ($script:windowCounts.Contains($name)) { $script:windowCounts[$name] } else { 0 }) }) }
                elseif ($name -match '^q\d+schema$') { $rows[$name] = @($script:schema | ForEach-Object { [ordered]@{ ColumnName = $_ } }) }
                elseif ($name -match '^q\d+sample$') { $rows[$name] = @([ordered]@{ Computer = 'vm-web-01'; Account = 'alice' }) }
                else { $rows[$name] = @($script:contoso.Kql.Rows[$name]) }
            }
            @{ Rows = $rows; Errors = $errors }
        }
    }

    Context 'Finding the workspace' {
        It 'stops with what to do when Sentinel isn''t enabled' {
            $script:onboarding = @{ Status = 404; Error = 'Not found'; Body = $null; Items = $null }
            { $null = & $script:capture { Get-AACSentinelIncident -WorkspaceId $script:contoso.ResourceId -NoDisplay } } | Should -Throw -ExpectedMessage '*found no Microsoft Sentinel on the workspace law-contoso-sentinel*'
        }

        It 'finds the workspace by its workspace ID' {
            $null = Get-AACSentinelWatchlist -WorkspaceId $script:contoso.WorkspaceId -NoDisplay
            Should -Invoke -ModuleName 'Azure.Admin.Console' Invoke-AACGraphBatch -Times 1
            Should -Invoke -ModuleName 'Azure.Admin.Console' Invoke-AACLogQueryBatch -ParameterFilter { $WorkspaceId -eq $script:contoso.WorkspaceId }
        }

        It 'reads every Sentinel list with the current stable API' {
            $null = Get-AACSentinelContentHub -WorkspaceId $script:contoso.ResourceId -NoDisplay
            $null = Get-AACSentinelAnalyticsRule -WorkspaceId $script:contoso.ResourceId -NoDisplay
            @($script:armUris | Where-Object { $_ -like '*/providers/Microsoft.SecurityInsights/*' -and $_ -notlike '*api-version=2025-09-01*' }).Count | Should -Be 0
        }
    }

    Context 'Get-AACSentinelIncident' {
        It 'lists the open incidents of any age by default, newest first' {
            $incidents = @(Get-AACSentinelIncident -WorkspaceId $script:contoso.ResourceId -NoDisplay)
            $incidents.Count | Should -Be 3
            $incidents[0].PSObject.TypeNames[0] | Should -Be 'AAC.SentinelIncident'
            $incidents.Number | Should -Be @(3, 1, 2)
            $uri = @($script:armUris | Where-Object { $_ -match '/incidents\?' })[0]
            [uri]::UnescapeDataString($uri) | Should -Match "properties/status eq 'New' or properties/status eq 'Active'"
            $uri | Should -Not -Match 'createdTimeUtc%20ge' -Because 'an open incident is open however old it is'
            Should -Invoke -ModuleName 'Azure.Admin.Console' Invoke-AACLogQueryBatch -Exactly 0 -Because 'close times are only needed for closed incidents'
        }

        It 'reads closed incidents of the last 30 days, with when each closed' {
            $closed = @(Get-AACSentinelIncident -WorkspaceId $script:contoso.ResourceId -Status Closed -NoDisplay)
            $closed.Count | Should -Be 6
            ($closed | Where-Object Number -EQ 4).HoursToClose | Should -Be 100
            $uri = [uri]::UnescapeDataString(@($script:armUris | Where-Object { $_ -match '/incidents\?' })[0])
            $uri | Should -Match "properties/createdTimeUtc ge \d{4}-\d{2}-\d{2}T"
            $uri | Should -Match "properties/status eq 'Closed'"
            $script:kqlQueries['incidentTimes'] | Should -Match 'ago\(30d\)'
        }

        It 'filters: <Title>' -ForEach @(
            @{ Title = 'severity'; Arguments = @{ Severity = 'High' }; Expected = @(1) }
            @{ Title = 'no owner'; Arguments = @{ Unassigned = $true }; Expected = @(3, 1) }
            @{ Title = 'owner, with wildcards'; Arguments = @{ Owner = 'analyst@*' }; Expected = @(2) }
            @{ Title = 'number, whatever its state'; Arguments = @{ Number = 5 }; Expected = @(5) }
            @{ Title = 'classification'; Arguments = @{ Status = 'Closed'; Classification = 'FalsePositive' }; Expected = @(7, 6, 5, 4) }
            @{ Title = 'title'; Arguments = @{ Name = 'Incident 2' }; Expected = @(2) }
        ) {
            $found = @(Get-AACSentinelIncident -WorkspaceId $script:contoso.ResourceId @Arguments -NoDisplay)
            @($found.Number | Sort-Object -Descending) | Should -Be @($Expected | Sort-Object -Descending)
        }

        It 'carries the incident''s ID, labels and the rules that raised it' {
            $incident = @(Get-AACSentinelIncident -WorkspaceId $script:contoso.ResourceId -Number 1 -NoDisplay)[0]
            $incident.IncidentId | Should -Be 'inc-1'
            $incident.RuleIds | Should -Be 'rule-1'
        }

        It 'shows the open incidents' {
            $shown = & $script:capture { Get-AACSentinelIncident -WorkspaceId $script:contoso.ResourceId -NoPaging }
            $shown.Text | Should -Match 'Microsoft Sentinel incidents'
            $shown.Text | Should -Match '3 open incident\(s\): 1 high, 2 with no owner'
            $shown.Output.Count | Should -Be 0 -Because 'at the prompt, the view is all'
        }

        It 'writes CSV and HTML reports' {
            $csv = Join-Path -Path $TestDrive -ChildPath 'incidents.csv'
            $html = Join-Path -Path $TestDrive -ChildPath 'incidents.html'
            $null = & $script:capture { Get-AACSentinelIncident -WorkspaceId $script:contoso.ResourceId -Status New, Active, Closed -CsvPath $csv -HtmlPath $html }
            @(Import-Csv -LiteralPath $csv).Count | Should -Be 9
            Get-Content -LiteralPath $html -Raw | Should -Match 'Microsoft Sentinel incidents'
        }
    }

    Context 'Get-AACSentinelAlert' {
        It 'queries the last 7 days of SecurityAlert by default' {
            $null = Get-AACSentinelAlert -WorkspaceId $script:contoso.ResourceId -NoDisplay
            $script:kqlQueries['alerts'] | Should -Match '^SecurityAlert'
            $script:kqlQueries['alerts'] | Should -Match 'ago\(7d\)'
            $script:kqlQueries['alerts'] | Should -Match 'arg_max\(TimeGenerated, \*\) by SystemAlertId' -Because 'an alert is written again when its status changes'
            $script:kqlQueries['incidents'] | Should -Match 'mv-expand AlertId = AlertIds'
            $script:kqlTimespan | Should -Be 'P7D'
        }

        It 'puts -Severity in the query' {
            $null = Get-AACSentinelAlert -WorkspaceId $script:contoso.ResourceId -Severity High, Medium -Days 30 -NoDisplay
            $script:kqlQueries['alerts'] | Should -Match "AlertSeverity in~ \('High', 'Medium'\)"
            $script:kqlQueries['alerts'] | Should -Match 'ago\(30d\)'
        }

        It 'parses the entities, techniques and details, and finds the incident' {
            $alerts = @(Get-AACSentinelAlert -WorkspaceId $script:contoso.ResourceId -NoDisplay)
            $alerts.Count | Should -Be 5
            $alerts[0].PSObject.TypeNames[0] | Should -Be 'AAC.SentinelAlert'
            $brute = $alerts[0]
            $brute.Alert | Should -Be 'Brute force on VMs'
            $brute.Hosts | Should -Be 'vm-web-01' -Because 'a $ref repeats an entity and isn''t counted twice'
            $brute.Accounts | Should -Be 'alice@contoso.example'
            $brute.IpAddresses | Should -Be '203.0.113.10'
            $brute.Techniques | Should -Be 'T1110'
            $brute.Remediation | Should -Be 'Reset the password. Block the IP address.'
            $brute.ExtendedProperties['Query Period'] | Should -Be '01:00:00'
            $brute.IncidentNumber | Should -Be 1
            $brute.Open | Should -BeTrue
            ($alerts | Where-Object AlertId -EQ 'alert-2').IncidentNumber | Should -Be 2 -Because 'alert IDs match in any case'
            ($alerts | Where-Object AlertId -EQ 'alert-2').Accounts | Should -Be 'CONTOSO\bob'
        }

        It 'drops Sentinel''s Unknown tactic and keeps JSON that doesn''t parse out of the way' {
            $powershell = @(Get-AACSentinelAlert -WorkspaceId $script:contoso.ResourceId -NoDisplay) | Where-Object AlertId -EQ 'alert-5'
            $powershell.Tactics | Should -Be 'Execution'
            $powershell.Techniques | Should -Be 'T1059, T1059.001'
            $powershell.Entities | Should -Be 'process: powershell -enc AAAA'
            $powershell.ExtendedProperties.Count | Should -Be 0
            $powershell.Remediation | Should -Be 'Isolate the device.'
        }

        It 'counts the alerts raised again for one entity' {
            $alerts = @(Get-AACSentinelAlert -WorkspaceId $script:contoso.ResourceId -NoDisplay)
            @($alerts | Where-Object Alert -EQ 'Rare admin sign-in' | ForEach-Object Occurrences | Select-Object -Unique) | Should -Be @(3)
            ($alerts | Where-Object AlertId -EQ 'alert-1').Occurrences | Should -Be 1
        }

        It 'filters: <Title>' -ForEach @(
            @{ Title = 'in an incident'; Arguments = @{ IncidentNumber = 1 }; Expected = @('alert-1') }
            @{ Title = 'in no incident'; Arguments = @{ NoIncident = $true }; Expected = @('alert-3', 'alert-4', 'alert-5') }
            @{ Title = 'entity, with wildcards'; Arguments = @{ Entity = '*alice*' }; Expected = @('alert-1') }
            @{ Title = 'IP address as an entity'; Arguments = @{ Entity = '203.0.113.*' }; Expected = @('alert-1') }
            @{ Title = 'product'; Arguments = @{ Product = 'Microsoft Defender*' }; Expected = @('alert-5') }
            @{ Title = 'status'; Arguments = @{ Status = 'Resolved' }; Expected = @('alert-4') }
            @{ Title = 'tactic'; Arguments = @{ Tactic = 'Persist*' }; Expected = @('alert-2', 'alert-3', 'alert-4') }
        ) {
            @(Get-AACSentinelAlert -WorkspaceId $script:contoso.ResourceId @Arguments -NoDisplay | ForEach-Object AlertId | Sort-Object) | Should -Be $Expected
        }

        It 'refuses -IncidentNumber with -NoIncident' {
            { $null = & $script:capture { Get-AACSentinelAlert -WorkspaceId $script:contoso.ResourceId -IncidentNumber 1 -NoIncident -NoDisplay } } | Should -Throw -ExpectedMessage '*Use one of -IncidentNumber or -NoIncident*'
        }

        It 'returns nothing, not an error, when no alert was ever written' {
            $script:kqlErrors = @{ alerts = "'where' operator: Failed to resolve table or column expression named 'SecurityAlert'" }
            @(Get-AACSentinelAlert -WorkspaceId $script:contoso.ResourceId -NoDisplay).Count | Should -Be 0
        }

        It 'stops when the alerts can''t be queried for another reason' {
            $script:kqlErrors = @{ alerts = 'Forbidden' }
            { $null = & $script:capture { Get-AACSentinelAlert -WorkspaceId $script:contoso.ResourceId -NoDisplay } } | Should -Throw -ExpectedMessage '*couldn''t query the alerts*Forbidden*'
        }

        It 'shows the alerts and the recurring ones' {
            $shown = & $script:capture { Get-AACSentinelAlert -WorkspaceId $script:contoso.ResourceId -NoPaging }
            $shown.Text | Should -Match '5 alert\(s\) in the last 7 day\(s\) from 2 product\(s\): 1 high, 3 medium; 3 in no incident'
            $shown.Text | Should -Match 'Recurring alerts'
        }
    }

    Context 'Get-AACSentinelAnalyticsRule' {
        It 'lists every rule, failing first, with incidents and health' {
            $rules = @(Get-AACSentinelAnalyticsRule -WorkspaceId $script:contoso.ResourceId -NoDisplay)
            $rules.Count | Should -Be 4
            $rules[0].PSObject.TypeNames[0] | Should -Be 'AAC.SentinelAnalyticsRule'
            $rules[0].Name | Should -Be 'Brute force on VMs'
            $rules[0].Failures | Should -Be 12
            $rules[0].TemplateUpdate | Should -BeTrue
            ($rules | Where-Object Name -EQ 'Rare admin sign-in').FalsePositives | Should -Be 4
            @($script:kqlQueries.Keys) | Should -Be @('health')
        }

        It 'filters: <Title>' -ForEach @(
            @{ Title = 'disabled'; Arguments = @{ State = 'Disabled' }; Expected = @('rule-3') }
            @{ Title = 'enabled and failing'; Arguments = @{ State = 'Enabled'; Failing = $true }; Expected = @('rule-1') }
            @{ Title = 'newer template'; Arguments = @{ TemplateUpdate = $true }; Expected = @('rule-1') }
            @{ Title = 'kind'; Arguments = @{ Kind = 'Fusion' }; Expected = @('rule-4') }
            @{ Title = 'tactic'; Arguments = @{ Tactic = 'Credential*' }; Expected = @('rule-1') }
            @{ Title = 'name'; Arguments = @{ Name = 'Rare*' }; Expected = @('rule-2') }
        ) {
            @(Get-AACSentinelAnalyticsRule -WorkspaceId $script:contoso.ResourceId @Arguments -NoDisplay | ForEach-Object RuleId | Sort-Object) | Should -Be $Expected
        }

        It 'shows the rules and says health monitoring is off when it is' {
            $script:kqlErrors = @{ health = "Failed to resolve scalar expression named '_SentinelHealth'" }
            $shown = & $script:capture { Get-AACSentinelAnalyticsRule -WorkspaceId $script:contoso.ResourceId -NoPaging }
            $shown.Text | Should -Match '4 analytics rule\(s\), 3 enabled'
            $shown.Text | Should -Match 'health monitoring has no records'
        }
    }

    Context 'Get-AACSentinelWatchlist' {
        BeforeEach {
            $script:watchlists = @(Get-AACSentinelWatchlist -WorkspaceId $script:contoso.ResourceId -NoDisplay)
            $script:byAlias = @{}
            foreach ($w in $script:watchlists) { $script:byAlias[$w.Alias] = $w }
        }

        It 'lists every watchlist, the ones with findings first' {
            $script:watchlists.Count | Should -Be 4
            $script:watchlists[0].PSObject.TypeNames[0] | Should -Be 'AAC.SentinelWatchlist'
            $script:watchlists[-1].Alias | Should -Be 'VIPUsers'
            $script:watchlists[-1].Findings | Should -BeNullOrEmpty
        }

        It 'counts the items, and the rules and hunting queries that call _GetWatchlist' {
            $script:byAlias['VIPUsers'].Items | Should -Be 25
            $script:byAlias['VIPUsers'].Rules | Should -Be 1
            $script:byAlias['VIPUsers'].UsedBy | Should -Be 'Rare admin sign-in'
            $script:byAlias['VIPUsers'].UpdatedBy | Should -Be 'admin@contoso.example'
            $script:byAlias['EmptyList'].HuntingQueries | Should -Be 1 -Because 'double quotes work as well as single'
            $script:byAlias['OldRanges'].HuntingQueries | Should -Be 0 -Because 'a saved search that isn''t a hunting query doesn''t count'
        }

        It 'finds: <Alias> - <Finding>' -ForEach @(
            @{ Alias = 'OldRanges'; Finding = 'Unused' }
            # Counted from today, and the fixture's dates are fixed: the number of days grows.
            @{ Alias = 'OldRanges'; Finding = 'Not updated for \d+ days' }
            @{ Alias = 'EmptyList'; Finding = 'No items' }
            @{ Alias = 'Broken'; Finding = 'Upload failed' }
        ) {
            $script:byAlias[$Alias].Findings | Should -Match $Finding
        }

        It 'counts zero items when the Watchlist table doesn''t exist yet' {
            $script:kqlErrors = @{ items = "Failed to resolve table expression named 'Watchlist'" }
            $found = @(Get-AACSentinelWatchlist -WorkspaceId $script:contoso.ResourceId -NoDisplay)
            @($found | Where-Object Items -NE 0).Count | Should -Be 0
        }

        It 'leaves the items blank, and says so, when they can''t be counted' {
            $script:kqlErrors = @{ items = 'Forbidden' }
            $shown = & $script:capture { Get-AACSentinelWatchlist -WorkspaceId $script:contoso.ResourceId -NoPaging -PassThru }
            @($shown.Output | Where-Object { $null -ne $_.Items }).Count | Should -Be 0
            @($shown.Output | Where-Object Findings -Match 'No items').Count | Should -Be 0 -Because 'unknown isn''t empty'
            $shown.Text | Should -Match 'couldn''t be counted'
        }

        It 'takes -StaleAfterDays and -Name' {
            # A week past the fixture's "now": VIP users (10 days before it) and Old IP ranges are stale.
            $stale = [int][Math]::Floor(([datetime]::UtcNow - $script:contoso.Now).TotalDays) + 7
            @(Get-AACSentinelWatchlist -WorkspaceId $script:contoso.ResourceId -StaleAfterDays $stale -NoDisplay | Where-Object Findings -Match 'Not updated' | ForEach-Object Alias | Sort-Object) | Should -Be @('OldRanges', 'VIPUsers')
            @(Get-AACSentinelWatchlist -WorkspaceId $script:contoso.ResourceId -Name 'VIP*' -NoDisplay).Alias | Should -Be @('VIPUsers')
        }
    }

    Context 'Get-AACSentinelContentHub' {
        BeforeEach {
            $script:packages = @(Get-AACSentinelContentHub -WorkspaceId $script:contoso.ResourceId -NoDisplay)
            $script:byId = @{}
            foreach ($p in $script:packages) { $script:byId[$p.ContentId] = $p }
        }

        It 'lists what is installed, with the latest version from the catalog' {
            $script:packages.Count | Should -Be 3
            $script:packages[0].PSObject.TypeNames[0] | Should -Be 'AAC.SentinelContentPackage'
            $entra = $script:byId['contoso.entra']
            $entra.InstalledVersion | Should -Be '3.0.5'
            $entra.LatestVersion | Should -Be '3.1.0'
            $entra.UpdateAvailable | Should -BeTrue
            $entra.Findings | Should -Match 'Update available \(3\.0\.5 to 3\.1\.0\)'
        }

        It 'counts the templates each package brought and the rules made from them' {
            $entra = $script:byId['contoso.entra']
            $entra.AnalyticsRuleTemplates | Should -Be 2
            $entra.TemplatesUsed | Should -Be 1
            $entra.RulesEnabled | Should -Be 1
            $entra.Workbooks | Should -Be 1
            $entra.HuntingQueries | Should -Be 1
            $script:byId['contoso.windows'].DataConnectors | Should -Be 1
            $script:byId['contoso.legacyfw'].Parsers | Should -Be 1
        }

        It 'finds deprecated packages and ones with no enabled rule' {
            $script:byId['contoso.legacyfw'].Deprecated | Should -BeTrue
            $script:byId['contoso.legacyfw'].Findings | Should -Not -Match 'No enabled rule' -Because 'it brought no analytics templates'
            $script:byId['contoso.windows'].Findings | Should -Be 'No enabled rule from its 2 analytics template(s)'
        }

        It 'filters with -UpdateAvailable, and adds the catalog with -IncludeAvailable' {
            @(Get-AACSentinelContentHub -WorkspaceId $script:contoso.ResourceId -UpdateAvailable -NoDisplay).ContentId | Should -Be @('contoso.entra')
            $all = @(Get-AACSentinelContentHub -WorkspaceId $script:contoso.ResourceId -IncludeAvailable -NoDisplay)
            $all.Count | Should -Be 4
            ($all | Where-Object ContentId -EQ 'contoso.okta').State | Should -Be 'Available'
            $all[-1].State | Should -Be 'Available' -Because 'installed packages come first'
        }

        It 'shows the packages' {
            $shown = & $script:capture { Get-AACSentinelContentHub -WorkspaceId $script:contoso.ResourceId -NoPaging }
            $shown.Text | Should -Match '3 package\(s\) installed: 1 with an update, 1 deprecated, 1 with no enabled rule'
        }
    }

    Context 'Get-AACSentinelPlaybook' {
        BeforeEach {
            $script:playbooks = @(Get-AACSentinelPlaybook -WorkspaceId $script:contoso.ResourceId -NoDisplay)
            $script:byName = @{}
            foreach ($p in $script:playbooks) { $script:byName[$p.Name] = $p }
        }

        It 'lists the Logic Apps with a Sentinel trigger, and the playbooks automation rules miss' {
            $script:playbooks.Count | Should -Be 4
            $script:playbooks[0].PSObject.TypeNames[0] | Should -Be 'AAC.SentinelPlaybook'
            $script:playbooks[0].Severity | Should -Be 'High' -Because 'the worst come first'
            $script:byName['pb-gone'].State | Should -Be 'Missing'
            $script:byName['pb-gone'].RuleNames | Should -Be 'Temporary tagging'
        }

        It 'reads the trigger, the runs and the rules that run it' {
            $assign = $script:byName['pb-assign']
            $assign.Trigger | Should -Be 'Incident'
            $assign.AutomationRules | Should -Be 1
            $assign.RuleNames | Should -Be 'Assign to the SOC'
            $assign.Runs | Should -Be 10
            $assign.Failed | Should -Be 2
            $assign.FailurePercent | Should -Be 20
            $assign.LastError | Should -Be 'NotFound: The incident was not found.'
            $assign.SentinelAuth | Should -Be 'ManagedIdentity'
            $assign.SentinelCanRun | Should -BeTrue
            $assign.Severity | Should -Be 'Medium'
            $script:byName['pb-notify'].Trigger | Should -Be 'Alert'
            $script:byName['pb-enrich'].Trigger | Should -Be 'Entity'
        }

        It 'finds: <Playbook> - <Finding>' -ForEach @(
            @{ Playbook = 'pb-enrich'; Finding = 'Sentinel can''t run it' }
            @{ Playbook = 'pb-notify'; Finding = 'signs in as an account' }
            @{ Playbook = 'pb-notify'; Finding = 'Only disabled or expired automation rules run it' }
            @{ Playbook = 'pb-assign'; Finding = '2 of 10 run\(s\) failed' }
        ) {
            $script:byName[$Playbook].Findings | Should -Match $Finding
        }

        It 'reads the runs of -Days, and each resource group''s role assignments once' {
            $runUri = [uri]::UnescapeDataString(@($script:armUris | Where-Object { $_ -match '/workflows/pb-assign/runs\?' })[0])
            $runUri | Should -Match 'startTime ge \d{4}-\d{2}-\d{2}T'
            @($script:armUris | Where-Object { $_ -match 'roleAssignments\?' }).Count | Should -Be 2
            @(Get-AACSentinelPlaybook -WorkspaceId $script:contoso.ResourceId -Trigger Incident -NoDisplay).Name | Should -Be @('pb-assign')
        }

        It 'flags a disabled playbook a live rule runs, and a missing one a live rule names' {
            $result = @(InModuleScope 'Azure.Admin.Console' -Parameters @{ C = $script:contoso } {
                    param($C)
                    $workflows = @($C.Playbooks | ForEach-Object { $w = @{} + $_; if ($w.name -eq 'pb-assign') { $w.state = 'Disabled' }; $w })
                    ConvertTo-AACSentinelPlaybook -Workflow $workflows -AutomationRule @($C.Arm.automationRules.Items) -Now $C.Now
                })
            ($result | Where-Object Name -EQ 'pb-assign').Findings | Should -Match 'Disabled, but 1 enabled automation rule\(s\) run it'
            ($result | Where-Object Name -EQ 'pb-gone').Severity | Should -Be 'High' -Because 'the rule naming it was live then'
            ($result | Where-Object Name -EQ 'pb-assign').Runs | Should -BeNullOrEmpty -Because 'no runs were read'
            ($result | Where-Object Name -EQ 'pb-assign').SentinelCanRun | Should -BeNullOrEmpty -Because 'unknown isn''t no'
        }

        It 'shows the playbooks' {
            $shown = & $script:capture { Get-AACSentinelPlaybook -WorkspaceId $script:contoso.ResourceId -NoPaging }
            $shown.Text | Should -Match '4 playbook\(s\): \d need attention now, 1 with failed runs \(2 of 10 run\(s\)'
        }
    }

    Context 'Get-AACSentinelThreatIntelligence' {
        BeforeEach {
            # The legacy table doesn't exist in this workspace.
            $script:kqlErrors = @{
                legacy     = "'where' operator: Failed to resolve table or column expression named 'ThreatIntelligenceIndicator'"
                legacyList = "'where' operator: Failed to resolve table or column expression named 'ThreatIntelligenceIndicator'"
            }
        }

        It 'summarises by source and type, the ones with findings first' {
            $sources = @(Get-AACSentinelThreatIntelligence -WorkspaceId $script:contoso.ResourceId -NoDisplay)
            $sources.Count | Should -Be 2
            $sources[0].PSObject.TypeNames[0] | Should -Be 'AAC.SentinelThreatIntelSource'
            $sources[0].Source | Should -Be 'Contoso TAXII'
            $sources[0].Findings | Should -Match 'No update for 20 days'
            $sources[0].Findings | Should -Match 'None active'
            $sources[0].Findings | Should -Match 'Mostly low confidence'
            $sources[1].Findings | Should -BeNullOrEmpty
            $sources[1].AverageConfidence | Should -Be 80.4
            $sources[1].Table | Should -Be 'ThreatIntelIndicators'
            $script:kqlQueries['stix'] | Should -Match 'ago\(30d\)'
            $script:kqlQueries.Contains('stixList') | Should -BeFalse -Because 'the indicators are read only with -Indicator'
        }

        It 'says when no rule matches on the indicators and a feed is disconnected' {
            $shown = & $script:capture { Get-AACSentinelThreatIntelligence -WorkspaceId $script:contoso.ResourceId -NoPaging }
            $shown.Text | Should -Match '1,200 indicator\(s\) from 2 source\(s\): 900 active'
            $shown.Text | Should -Match 'No enabled analytics rule reads the threat intelligence tables'
            $shown.Text | Should -Match 'is disconnected'
        }

        It 'lists the active indicators with -Indicator: <Title>' -ForEach @(
            @{ Title = 'active only'; Arguments = @{}; Expected = @('i-1') }
            @{ Title = 'with expired'; Arguments = @{ IncludeExpired = $true }; Expected = @('i-1', 'i-2', 'i-3') }
            @{ Title = 'by value'; Arguments = @{ IncludeExpired = $true; Value = '198.51.*' }; Expected = @('i-2') }
            @{ Title = 'by type'; Arguments = @{ IncludeExpired = $true; IndicatorType = 'domain*' }; Expected = @('i-3') }
        ) {
            @(Get-AACSentinelThreatIntelligence -WorkspaceId $script:contoso.ResourceId -Indicator @Arguments -NoDisplay | ForEach-Object Id | Sort-Object) | Should -Be $Expected
        }

        It 'parses the tags of an indicator' {
            $one = @(Get-AACSentinelThreatIntelligence -WorkspaceId $script:contoso.ResourceId -Indicator -NoDisplay)[0]
            $one.PSObject.TypeNames[0] | Should -Be 'AAC.SentinelThreatIndicator'
            $one.Tags | Should -Be 'botnet, c2'
            $one.Confidence | Should -Be 90
        }

        It 'refuses -Value without -Indicator' {
            { $null = & $script:capture { Get-AACSentinelThreatIntelligence -WorkspaceId $script:contoso.ResourceId -Value '1.2.3.4' -NoDisplay } } | Should -Throw -ExpectedMessage '*only with -Indicator*'
        }

        It 'says no indicators arrive when neither table exists' {
            $script:kqlErrors['stix'] = "Failed to resolve table or column expression named 'ThreatIntelIndicators'"
            $shown = & $script:capture { Get-AACSentinelThreatIntelligence -WorkspaceId $script:contoso.ResourceId -NoPaging -PassThru }
            $shown.Output.Count | Should -Be 0
            $shown.Text | Should -Match 'No threat indicators arrived'
        }

        It 'stops when both tables fail for another reason' {
            $script:kqlErrors = @{ stix = 'Forbidden'; legacy = 'Forbidden' }
            { $null = & $script:capture { Get-AACSentinelThreatIntelligence -WorkspaceId $script:contoso.ResourceId -NoDisplay } } | Should -Throw -ExpectedMessage '*couldn''t query the threat intelligence*'
        }

        It 'points rules at the current table when they read the empty legacy one' {
            $intel = InModuleScope 'Azure.Admin.Console' -Parameters @{ C = $script:contoso } {
                param($C)
                $rule = [pscustomobject]@{ Name = 'TI map IP'; Enabled = $true; Query = 'ThreatIntelligenceIndicator | where isnotempty(NetworkIP)' }
                ConvertTo-AACSentinelThreatIntel -Kql @{ Rows = @{ stix = $C.Kql.Rows['stix'] }; Errors = @{ legacy = 'Failed to resolve table expression named ''ThreatIntelligenceIndicator''' } } -Rule @($rule)
            }
            @($intel.Notices.Text) -join ' ' | Should -Match 'read ThreatIntelligenceIndicator, which has no indicators: move them to ThreatIntelIndicators \(TI map IP\)'
            $intel.Errors.Count | Should -Be 0 -Because 'a missing table is an answer, not an error'
        }
    }

    Context 'Test-AACSentinelRuleQuery' {
        It 'replays a rule''s last windows, one frequency apart, each looking back its period' {
            $test = @(Test-AACSentinelRuleQuery -WorkspaceId $script:contoso.ResourceId -Name 'Brute force*' -NoDisplay)
            $test.Count | Should -Be 1
            $test[0].PSObject.TypeNames[0] | Should -Be 'AAC.SentinelRuleQueryTest'
            $test[0].Runs | Should -Be 6
            @($script:kqlQueries.Keys | Where-Object { $_ -match '^q1r\d$' }).Count | Should -Be 6
            $script:kqlQueries['q1r0']['Query'] | Should -Match '\n\| count$'
            $script:kqlQueries['q1schema']['Query'] | Should -Match 'getschema'
            $span = { param([string] $Name) @($script:kqlTimespans[$Name] -split '/' | ForEach-Object { [datetime]::Parse($_, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal) }) }
            $first = & $span 'q1r0'; $second = & $span 'q1r1'
            ($first[1] - $first[0]).TotalHours | Should -Be 1 -Because 'the rule looks back PT1H'
            ($first[1] - $second[1]).TotalHours | Should -Be 1 -Because 'the rule runs every PT1H'
        }

        It 'counts the runs that would alert, and finds the columns the rule maps but doesn''t return' {
            $script:windowCounts = @{ q1r0 = 3 }
            $test = @(Test-AACSentinelRuleQuery -WorkspaceId $script:contoso.ResourceId -Name 'Brute force*' -NoDisplay)[0]
            $test.LatestResults | Should -Be 3
            $test.RunsAlerting | Should -Be 1
            $test.EstimatedAlerts | Should -Be 1
            $test.MissingColumns | Should -Be 'TargetAccount' -Because 'Computer is in the results, TargetAccount isn''t'
            $test.Status | Should -Be 'Warning'
            $test.Sample.Count | Should -Be 1
            @($test.RunDetail).Count | Should -Be 6
        }

        It 'calls a rule that alerts in every run likely noisy' {
            $script:windowCounts = @{ q1r0 = 1; q1r1 = 2; q1r2 = 1; q1r3 = 4; q1r4 = 1; q1r5 = 1 }
            $script:schema = @('TimeGenerated', 'Computer', 'TargetAccount')
            $test = @(Test-AACSentinelRuleQuery -WorkspaceId $script:contoso.ResourceId -Name 'Brute force*' -NoDisplay)[0]
            $test.Findings | Should -Match 'Would alert in every one of the 6 runs'
            $test.MissingColumns | Should -BeNullOrEmpty
        }

        It 'reports a query that fails' {
            $script:kqlErrors = @{ q1schema = "Failed to resolve table expression named 'SecurityEvent'" }
            $test = @(Test-AACSentinelRuleQuery -WorkspaceId $script:contoso.ResourceId -Name 'Brute force*' -NoDisplay)[0]
            $test.Status | Should -Be 'Error'
            $test.Findings | Should -Match '^Query fails'
        }

        It 'tests every enabled scheduled and NRT rule by default, and what is piped in' {
            @(Test-AACSentinelRuleQuery -WorkspaceId $script:contoso.ResourceId -Runs 1 -NoDisplay).RuleId | Should -Be @('rule-1', 'rule-2')
            $piped = @(Get-AACSentinelAnalyticsRule -WorkspaceId $script:contoso.ResourceId -State Disabled -NoDisplay | Test-AACSentinelRuleQuery -WorkspaceId $script:contoso.ResourceId -Runs 1 -NoDisplay)
            $piped.RuleId | Should -Be @('rule-3')
        }

        It 'keeps the rule''s schedule' {
            $test = @(Test-AACSentinelRuleQuery -WorkspaceId $script:contoso.ResourceId -Name 'Rare admin sign-in' -Runs 2 -NoDisplay)[0]
            $test.Frequency | Should -Be 'PT5H'
            $test.Period | Should -Be 'P1D'
        }

        It 'tests an ad hoc query, only in its latest window when it calls ago()' {
            $test = @(Test-AACSentinelRuleQuery -WorkspaceId $script:contoso.ResourceId -Query 'SigninLogs | where TimeGenerated > ago(1h)' -Frequency PT2H -Period PT1H -NoDisplay)[0]
            $test.Name | Should -Be 'Ad hoc query'
            $test.Runs | Should -Be 1
            $test.Note | Should -Match 'ago\(\) or now\(\)'
            $test.Findings | Should -Match 'Runs every PT2H but looks back PT1H'
            Should -Invoke -ModuleName 'Azure.Admin.Console' Invoke-AACArmParallel -ParameterFilter { @($Uri | Where-Object { $_ -match '/alertRules\?' }).Count } -Exactly 0
        }

        It 'stops when no rule matches' {
            { $null = & $script:capture { Test-AACSentinelRuleQuery -WorkspaceId $script:contoso.ResourceId -Name 'Nothing like this' -NoDisplay } } | Should -Throw -ExpectedMessage '*found no scheduled or NRT rule*'
        }

        It 'shows the results' {
            $script:windowCounts = @{ q1r0 = 3 }
            $shown = & $script:capture { Test-AACSentinelRuleQuery -WorkspaceId $script:contoso.ResourceId -Name 'Brute force*' -NoPaging }
            $shown.Text | Should -Match '1 rule\(s\) replayed over up to 6 window\(s\): 0 failing, 1 with findings, 1 would alert now'
        }
    }

    Context 'Get-AACSentinelDataConnector' {
        It 'lists the connectors, the failing one first' {
            $connectors = @(Get-AACSentinelDataConnector -WorkspaceId $script:contoso.ResourceId -NoDisplay)
            $connectors.Count | Should -Be 4
            $connectors[0].PSObject.TypeNames[0] | Should -Be 'AAC.SentinelConnectorHealth'
            $connectors[0].ConnectorId | Should -Be 'c-office'
            $connectors[0].Status | Should -Be 'Failing'
            $connectors[0].Findings | Should -Match 'Unauthorized \[401\]'
            ($connectors | Where-Object ConnectorId -EQ 'c-tip').Status | Should -Be 'Disconnected'
        }

        It 'measures delay only in the tables with data in the last day' {
            $null = Get-AACSentinelDataConnector -WorkspaceId $script:contoso.ResourceId -NoDisplay
            $script:kqlQueries.Contains('delay') | Should -BeFalse -Because 'the fixture''s Usage is weeks old by the real clock'
            $script:kqlRows = @{ tables = @([ordered]@{ Table = 'SecurityEvent'; BillableGB = 6.0; NonBillableGB = 0.0; LastRecord = [datetime]::UtcNow.AddHours(-1).ToString('o'); Solution = 'Security' }) }
            $tables = @(Get-AACSentinelDataConnector -WorkspaceId $script:contoso.ResourceId -View Table -NoDisplay)
            $script:kqlQueries['delay'] | Should -Match "union isfuzzy=true withsource=TableName \['SecurityEvent'\]"
            $script:kqlTimespan | Should -Be 'P2D'
            $tables[0].PSObject.TypeNames[0] | Should -Be 'AAC.SentinelTableIngestion'
            $tables[0].DelayP95Minutes | Should -Be 5.5
        }

        It 'skips the delay query with -SkipLatency' {
            $script:kqlRows = @{ tables = @([ordered]@{ Table = 'SecurityEvent'; BillableGB = 6.0; NonBillableGB = 0.0; LastRecord = [datetime]::UtcNow.AddHours(-1).ToString('o'); Solution = 'Security' }) }
            $null = Get-AACSentinelDataConnector -WorkspaceId $script:contoso.ResourceId -SkipLatency -NoDisplay
            $script:kqlQueries.Contains('delay') | Should -BeFalse
        }

        It 'works out each connector''s and table''s status' {
            $health = InModuleScope 'Azure.Admin.Console' -Parameters @{ C = $script:contoso } {
                param($C)
                $a = ConvertTo-AACSentinelAssessment -Workspace $C.Workspace -Arm $C.Arm -Kql $C.Kql -Days 30 -Now $C.Now
                $aad = [pscustomobject]@{ Name = 'Microsoft Entra ID'; ConnectorId = 'c-aad'; Kind = 'AzureActiveDirectory'; State = 'Connected'; DataTypes = '' }
                ConvertTo-AACSentinelConnectorHealth -Connector (@($a.DataConnectors) + $aad) -Table @($a.Tables) -Latency @($C.Kql.Rows['delay']) -HealthFailure @($a.HealthFailures) -Now $C.Now
            }
            $connector = @{}; foreach ($c in $health.Connectors) { $connector[$c.ConnectorId] = $c }
            $connector['c-office'].Status | Should -Be 'Failing'
            $connector['c-tip'].Status | Should -Be 'Disconnected'
            $connector['c-aad'].Status | Should -Be 'Delayed'
            $connector['c-aad'].Tables | Should -Match '^SigninLogs, AuditLogs'
            $connector['c-aad'].TablesWithData | Should -Be 1
            $connector['c-aad'].DelayP95Minutes | Should -Be 75
            $connector['c-ui'].Status | Should -Be 'Unknown'
            $table = @{}; foreach ($t in $health.Tables) { $table[$t.Table] = $t }
            $table['SecurityEvent'].Status | Should -Be 'Healthy'
            $table['SigninLogs'].Status | Should -Be 'Delayed'
            $table['SigninLogs'].Connectors | Should -Be 'Microsoft Entra ID'
            $table['Syslog'].Status | Should -Be 'Silent'
            $table['Syslog'].RecentRecords | Should -Be 0 -Because 'measured, and nothing arrived in 6 hours'
            $health.Tables[0].Status | Should -Be 'Silent' -Because 'the worst come first'
        }

        It 'shows the connectors' {
            $shown = & $script:capture { Get-AACSentinelDataConnector -WorkspaceId $script:contoso.ResourceId -NoPaging }
            $shown.Text | Should -Match '4 connector\(s\): \d unhealthy - 1 failing, 1 disconnected'
        }
    }

    Context 'Export-AACSentinelAnalyticsRule' {
        BeforeEach {
            $script:folder = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('n'))
        }

        It 'writes one ARM template per analytics rule' {
            $written = @(Export-AACSentinelAnalyticsRule -WorkspaceId $script:contoso.ResourceId -Path $script:folder -NoDisplay)
            $written.Count | Should -Be 4
            $written[0].PSObject.TypeNames[0] | Should -Be 'AAC.SentinelRuleExport'
            @($written | Where-Object Status -NE 'Written').Count | Should -Be 0
            $file = Join-Path -Path $script:folder -ChildPath 'Brute force on VMs.json'
            $template = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -AsHashtable
            $template['$schema'] | Should -Match 'deploymentTemplate\.json'
            $template['parameters']['workspace']['type'] | Should -Be 'String'
            $resource = $template['resources'][0]
            $resource['type'] | Should -Be 'Microsoft.OperationalInsights/workspaces/providers/alertRules'
            $resource['kind'] | Should -Be 'Scheduled'
            $resource['name'] | Should -Be "[concat(parameters('workspace'),'/Microsoft.SecurityInsights/rule-1')]"
            $resource['properties']['query'] | Should -Be 'SecurityEvent | where EventID == 4625'
            $resource['properties'].Contains('lastModifiedUtc') | Should -BeFalse -Because 'Azure sets it'
        }

        It 'keeps only what can be set on a built-in kind' {
            $null = Export-AACSentinelAnalyticsRule -WorkspaceId $script:contoso.ResourceId -Path $script:folder -Kind Fusion -NoDisplay
            $template = Get-Content -LiteralPath (Join-Path -Path $script:folder -ChildPath 'Advanced multistage attack detection.json') -Raw | ConvertFrom-Json -AsHashtable
            @($template['resources'][0]['properties'].Keys | Sort-Object) | Should -Be @('alertRuleTemplateName', 'enabled')
        }

        It 'leaves existing files alone unless -Force, and writes the same file twice' {
            $null = Export-AACSentinelAnalyticsRule -WorkspaceId $script:contoso.ResourceId -Path $script:folder -NoDisplay
            $file = Join-Path -Path $script:folder -ChildPath 'Rare admin sign-in.json'
            $first = Get-Content -LiteralPath $file -Raw
            @(Export-AACSentinelAnalyticsRule -WorkspaceId $script:contoso.ResourceId -Path $script:folder -NoDisplay | Where-Object Status -EQ 'Exists').Count | Should -Be 4
            @(Export-AACSentinelAnalyticsRule -WorkspaceId $script:contoso.ResourceId -Path $script:folder -Force -NoDisplay | Where-Object Status -EQ 'Written').Count | Should -Be 4
            Get-Content -LiteralPath $file -Raw | Should -BeExactly $first -Because 'an unchanged rule gives the same file'
        }

        It 'writes nothing with -WhatIf' {
            $result = @(Export-AACSentinelAnalyticsRule -WorkspaceId $script:contoso.ResourceId -Path $script:folder -WhatIf -NoDisplay)
            @($result | Where-Object Status -EQ 'Skipped').Count | Should -Be 4
            Test-Path -LiteralPath $script:folder | Should -BeFalse
        }

        It 'adds the automation rules in their own folder, without who changed them' {
            $result = @(Export-AACSentinelAnalyticsRule -WorkspaceId $script:contoso.ResourceId -Path $script:folder -IncludeAutomationRule -State Enabled -NoDisplay)
            @($result | Where-Object Type -EQ 'Analytics rule').Count | Should -Be 3
            @($result | Where-Object Type -EQ 'Automation rule').Count | Should -Be 4
            $file = Join-Path -Path $script:folder -ChildPath 'AutomationRules/Assign to the SOC.json'
            $template = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -AsHashtable
            $template['resources'][0]['type'] | Should -Be 'Microsoft.OperationalInsights/workspaces/providers/automationRules'
            $template['resources'][0]['properties'].Contains('lastModifiedBy') | Should -BeFalse
        }

        It 'refuses a -Path that is a file' {
            $file = Join-Path -Path $TestDrive -ChildPath 'not-a-folder.txt'
            Set-Content -LiteralPath $file -Value 'x'
            { $null = & $script:capture { Export-AACSentinelAnalyticsRule -WorkspaceId $script:contoso.ResourceId -Path $file -NoDisplay } } | Should -Throw -ExpectedMessage '*Give -Path a folder*'
        }
    }
}

Describe 'Azure Admin Console - the Sentinel rule export''s files' {
    It 'escapes a string that starts with [ so ARM reads it as text' {
        $files = @(InModuleScope 'Azure.Admin.Console' {
                ConvertTo-AACSentinelRuleExport -AnalyticsRule @(@{ name = 'r1'; kind = 'Scheduled'; properties = @{ displayName = '[Preview] Odd sign-in'; enabled = $true; query = 'SigninLogs' } })
            })
        $files[0].FileName | Should -Be '[Preview] Odd sign-in.json'
        $files[0].Content | Should -Match '"displayName": "\[\[Preview\] Odd sign-in"'
    }

    It 'leaves strings as they are with -Format Json' {
        $files = @(InModuleScope 'Azure.Admin.Console' {
                ConvertTo-AACSentinelRuleExport -Format Json -AnalyticsRule @(@{ name = 'r1'; kind = 'Scheduled'; properties = @{ displayName = '[Preview] Odd sign-in'; enabled = $true; lastModifiedUtc = '2026-01-01' } })
            })
        $json = $files[0].Content | ConvertFrom-Json -AsHashtable
        $json['name'] | Should -Be 'r1'
        $json['properties']['displayName'] | Should -Be '[Preview] Odd sign-in'
        $json['properties'].Contains('lastModifiedUtc') | Should -BeFalse
    }

    It 'sorts keys, and makes file names safe and unique' {
        $files = @(InModuleScope 'Azure.Admin.Console' {
                ConvertTo-AACSentinelRuleExport -AnalyticsRule @(
                    @{ name = 'aaaaaaaa-1111'; kind = 'NRT'; properties = @{ displayName = 'Same: name?'; severity = 'High'; enabled = $true } }
                    @{ name = 'bbbbbbbb-2222'; kind = 'NRT'; properties = @{ displayName = 'Same: name?'; enabled = $false; severity = 'Low' } }
                )
            })
        $files.FileName | Should -Be @('Same- name-aaaaaaaa.json', 'Same- name-bbbbbbbb.json')
        $files[0].Content.IndexOf('"displayName"') | Should -BeLessThan $files[0].Content.IndexOf('"enabled"')
        $files[0].Content.IndexOf('"enabled"') | Should -BeLessThan $files[0].Content.IndexOf('"severity"')
    }
}
