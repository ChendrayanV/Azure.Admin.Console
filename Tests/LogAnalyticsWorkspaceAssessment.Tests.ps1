<#
    Unit tests for Invoke-AACLogAnalyticsWorkspaceAssessment over a made-up
    Contoso workspace (Fixtures\ContosoWorkspace.ps1): Resource Manager,
    Resource Graph and the KQL queries are faked; the query batch, the
    assessment's rules, the view and the exports run for real.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    $script:contoso = & (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoWorkspace.ps1')
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
            $arguments = @{ Workspace = $C.Workspace; Arm = $C.Arm; Kql = $C.Kql; Graph = $C.Graph; Days = 30; Now = $C.Now }
            foreach ($key in $O.Keys) { $arguments[$key] = $O[$key] }
            ConvertTo-AACWorkspaceAssessment @arguments
        }
    }
}

Describe 'Azure Admin Console - the Log Analytics query batch' {
    It 'runs each query as its own POST to the query API, and keeps one failure from stopping the rest' {
        # Only the HTTP send is faked: the batch engine, its callbacks and the
        # progress counting run for real, as against Azure.
        $result = InModuleScope 'Azure.Admin.Console' {
            $script:sent = [System.Collections.Generic.List[object]]::new()
            $script:progress = [System.Collections.Generic.List[string]]::new()
            Mock Get-AACAccessToken { "token-for-$Resource" }
            Mock Send-AACHttpRequest {
                $script:sent.Add([pscustomobject]@{ Method = $Method; Uri = $Uri; Body = $Body; Token = $Token })
                $query = ($Body | ConvertFrom-Json).query
                $status, $text = if ($query -like 'LAQueryLogs*') {
                    400, '{"error":{"code":"BadArgumentError","message":"The request had some invalid properties","innererror":{"code":"SemanticError","message":"Failed to resolve table or column expression named ''LAQueryLogs''"}}}'
                }
                else {
                    200, '{"tables":[{"name":"PrimaryResult","columns":[{"name":"Table","type":"string"},{"name":"GB","type":"real"}],"rows":[["Perf",1.5],["Syslog",0.25]]}]}'
                }
                $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]$status)
                $response.Content = [System.Net.Http.StringContent]::new($text)
                [System.Threading.Tasks.Task]::FromResult($response)
            }
            $batch = Invoke-AACLogQueryBatch -WorkspaceId 'ws-guid' -Query ([ordered]@{ counts = 'Usage | summarize'; audit = @{ Query = 'LAQueryLogs'; Timespan = 'P1D' } }) -Timespan 'P30D' -OnProgress {
                param($Name, $Done, $Total)
                $script:progress.Add("$Name $Done/$Total")
            }
            @{ Batch = $batch; Sent = @($script:sent | Sort-Object { ($_.Body | ConvertFrom-Json).query } -Descending); Progress = @($script:progress) }
        }
        $result.Sent.Count | Should -Be 2
        @($result.Sent.Method | Select-Object -Unique) | Should -Be 'Post'
        $result.Sent[0].Uri | Should -Be 'https://api.loganalytics.azure.com/v1/workspaces/ws-guid/query'
        $result.Sent[0].Token | Should -Be 'token-for-https://api.loganalytics.io' -Because 'the query API takes a Log Analytics token, not an ARM one'
        ($result.Sent[0].Body | ConvertFrom-Json).timespan | Should -Be 'P30D'
        ($result.Sent[1].Body | ConvertFrom-Json).timespan | Should -Be 'P1D' -Because 'a query can carry its own timespan'
        @($result.Progress | ForEach-Object { ($_ -split ' ')[1] } | Sort-Object) | Should -Be @('1/2', '2/2') -Because 'progress counts each finished query'
        $result.Batch.Rows['counts'].Count | Should -Be 2
        $result.Batch.Rows['counts'][1]['Table'] | Should -Be 'Syslog'
        $result.Batch.Rows['counts'][1]['GB'] | Should -Be 0.25
        $result.Batch.Errors['audit'] | Should -Match 'LAQueryLogs'
        @($result.Batch.Rows['audit']).Count | Should -Be 0
    }
}

Describe 'Azure Admin Console - the workspace assessment''s rules' {
    It 'sizes every table with data - billable and not - and keeps custom and non-default ones' {
        $a = & $script:convert
        $byName = @{}; foreach ($t in $a.Tables) { $byName[$t.Table] = $t }
        $byName['ContainerLogV2'].Billing | Should -Be 'Billable'
        $byName['ContainerLogV2'].SharePercent | Should -Be 45.5 -Because '45 of 99 billable GB'
        $byName['ContainerLogV2'].DailyAverageGB | Should -Be 1.5
        $byName['AzureActivity'].Billing | Should -Be 'Not billable'
        $byName['AzureActivity'].NonBillableGB | Should -Be 1.5
        $byName['App_CL'].Type | Should -Be 'Custom'
        $byName['Old_CL'].Billing | Should -Be 'No data' -Because 'custom tables are listed even when empty'
        $byName['SecurityEvent'].RetentionDays | Should -Be 180 -Because 'a table on non-default retention is listed'
        $byName.Contains('W3CIISLog') | Should -BeFalse -Because 'an Azure table with no data and default settings is left out'
        $a.Tables[0].Table | Should -Be 'ContainerLogV2' -Because 'largest first'
        $a.Stats.BillableGB | Should -Be 99
        $a.Stats.BillableTables | Should -Be 5
        $a.Stats.NonBillableTables | Should -Be 1
    }

    It 'lists every table with -IncludeEmptyTable' {
        (& $script:convert @{ IncludeEmptyTable = $true }).Tables.Table | Should -Contain 'W3CIISLog'
    }

    It 'reads every setting, and anything new under Other' {
        $settings = @((& $script:convert).Settings)
        $value = { param([string] $Name) ($settings | Where-Object Setting -EQ $Name).Value }
        & $value 'Workspace ID' | Should -Be $script:contoso.WorkspaceId
        & $value 'Pricing tier' | Should -Be 'PerGB2018'
        & $value 'Daily cap (GB)' | Should -Be '5'
        & $value 'Retention (days)' | Should -Be '90'
        & $value 'Local authentication (shared keys)' | Should -Be 'Enabled'
        & $value 'Access control mode' | Should -Be 'Resource or workspace permissions'
        & $value 'Workspace transformation DCR' | Should -Be 'dcr-workspace-transform'
        & $value 'Tags' | Should -Be 'env=prod; owner=platform'
        & $value 'export-to-adx' | Should -Be 'Enabled - 2 table(s) to stcontosoexport'
        & $value 'Saved searches and functions' | Should -Be '2'
        & $value 'someNewSetting' | Should -Be 'preview-value'
        & $value 'features.legacy' | Should -Be '0'
        ($settings | Where-Object Category -EQ 'Diagnostic settings').Setting | Should -Be '(none)'
    }

    It 'recommends, by severity: <Title>' -ForEach @(
        @{ Title = 'Consider a commitment tier'; Severity = 'High'; Source = 'Azure Advisor' }
        @{ Title = 'The daily cap stopped data collection'; Severity = 'High'; Source = 'Assessment' }
        @{ Title = '1 computer(s) still use the retired Log Analytics agent'; Severity = 'High'; Source = 'Assessment' }
        @{ Title = '2 agent(s) stopped sending heartbeats'; Severity = 'Medium'; Source = 'Assessment' }
        @{ Title = 'ContainerLogV2 could use the Basic or Auxiliary plan'; Severity = 'Medium'; Source = 'Assessment' }
        @{ Title = 'App_CL could use the Basic or Auxiliary plan'; Severity = 'Medium'; Source = 'Assessment' }
        @{ Title = 'Shared keys (local authentication) are enabled'; Severity = 'Medium'; Source = 'Assessment' }
        @{ Title = 'Ingestion spike'; Severity = 'Low'; Source = 'Assessment' }
        @{ Title = '1 custom table(s) with no data'; Severity = 'Low'; Source = 'Assessment' }
        @{ Title = '1 data collection rule(s) with no associations'; Severity = 'Low'; Source = 'Assessment' }
        @{ Title = 'Query auditing is off'; Severity = 'Low'; Source = 'Assessment' }
        @{ Title = 'No diagnostic settings on the workspace'; Severity = 'Low'; Source = 'Assessment' }
        @{ Title = 'Open to ingestion and queries from any network'; Severity = 'Low'; Source = 'Assessment' }
    ) {
        $found = @((& $script:convert).Recommendations | Where-Object Recommendation -EQ $Title)
        $found.Count | Should -Be 1
        $found[0].Severity | Should -Be $Severity
        $found[0].Source | Should -Be $Source
        $found[0].Action | Should -Not -BeNullOrEmpty
    }

    It 'leaves out what doesn''t apply: retention within Sentinel''s free 90 days, Perf for the Basic plan, operation errors already explained by the daily cap' {
        $titles = @((& $script:convert).Recommendations.Recommendation)
        $titles | Should -Not -Match 'Interactive retention'
        $titles | Should -Not -Match '^Perf could'
        $titles | Should -Not -Match "error\(s\) in the workspace's operations"
        $titles | Should -Not -Match 'No daily cap'
    }

    It 'orders recommendations High, Medium, Low' {
        $order = @{ High = 0; Medium = 1; Low = 2 }
        $severities = @((& $script:convert).Recommendations | ForEach-Object { $order[$_.Severity] })
        $severities | Should -Be @($severities | Sort-Object)
    }

    It 'recommends a commitment tier from 100 GB a day, and warns before the daily cap' {
        $kql = @{ Rows = @{ daily = @(1..30 | ForEach-Object { [ordered]@{ Day = $script:contoso.Now.Date.AddDays(-$_).ToString('o'); BillableGB = 120.0; NonBillableGB = 0 } }) }; Errors = @{} }
        $titles = @((& $script:convert @{ Kql = $kql }).Recommendations.Recommendation)
        $titles | Should -Contain 'A commitment tier would cost less'
        $titles | Should -Contain 'Ingestion is close to the daily cap' -Because 'a 5 GB cap against 120 GB a day, and no cap events'
    }

    It 'gives each agent its state and type' {
        $agents = @((& $script:convert).Agents)
        ($agents | Where-Object Computer -EQ 'vm-web01').State | Should -Be 'Healthy'
        ($agents | Where-Object Computer -EQ 'vm-sql01').State | Should -Be 'Unhealthy'
        ($agents | Where-Object Computer -EQ 'vm-sql01').AgentType | Should -Be 'Log Analytics agent (MMA)'
        ($agents | Where-Object Computer -EQ 'onprem-app01').State | Should -Be 'Not reporting'
    }

    It 'describes each data collection rule and what it is associated with' {
        $rules = @((& $script:convert).DataCollectionRules)
        $windows = $rules | Where-Object Name -EQ 'dcr-windows'
        $windows.DataSources | Should -Be 'performanceCounters (1), windowsEventLogs (2)'
        $windows.Transformations | Should -Be 1 -Because "'source' alone is no transformation"
        $windows.Associations | Should -Be 1
        $windows.AssociatedResources | Should -Be 'vm-web01'
        ($rules | Where-Object Name -EQ 'dcr-workspace-transform').WorkspaceTransform | Should -BeTrue
    }

    It 'keeps the workspace''s own changes in the change log, finished ones only' {
        $changes = @((& $script:convert).ChangeLog)
        $changes.Count | Should -Be 2
        $changes[0].Operation | Should -Be 'Create Workspace' -Because 'newest first'
        $changes[0].Resource | Should -Be '(workspace)'
        $changes[1].Resource | Should -Be 'tables/SecurityEvent'
        $changes[1].Status | Should -Be 'Failed'
    }

    It 'turns a missing LAQueryLogs into a notice, not an error, and reports real failures' {
        $a = & $script:convert
        $a.Notices | Should -Match 'Query auditing is off'
        $a.Errors.Count | Should -Be 0 -Because 'a 404 (no linked services) and a missing audit table are not errors'
        $kql = @{ Rows = $script:contoso.Kql.Rows; Errors = @{ operations = 'Query timed out' } }
        (& $script:convert @{ Kql = $kql }).Errors['kql:operations'] | Should -Be 'Query timed out'
    }

    It 'fills every Workspace Insights tab' {
        $insights = (& $script:convert).Insights
        @($insights.Keys) | Should -Be @('Overview', 'Usage', 'Health', 'Agents', 'QueryAudit', 'DataCollectionRules', 'ChangeLog')
        ($insights.Overview.Summary | Where-Object Metric -EQ 'Pricing tier').Value | Should -Be 'PerGB2018'
        $insights.Usage.Daily.Count | Should -Be 30
        $insights.Usage.Resources[0].Resource | Should -Be 'vm-web01'
        $insights.Usage.Resources[1].Resource | Should -Be '(no resource)'
        $insights.Health.Operations[0].Level | Should -Be 'Error'
        $insights.Health.Latency[0].P95Seconds | Should -Be 95
        ($insights.Agents.ByType | Where-Object AgentType -EQ 'Azure Monitor Agent').Computers | Should -Be 2
    }
}

Describe 'Azure Admin Console - Invoke-AACLogAnalyticsWorkspaceAssessment' {
    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $script:graphQueries += @($Query.Keys)
            $rows = @{}
            foreach ($name in @($Query.Keys)) { $rows[$name] = @($script:contoso.Graph.Rows[$name]) }
            @{ Rows = $rows; Errors = @{} }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $script:armUris += @($Uri)
            $out = @{}
            foreach ($u in $Uri) {
                $name = switch -Regex ($u) {
                    '/workspaces/law-contoso\?' { 'workspace' } '/tables\?' { 'tables' } '/dataExports\?' { 'dataExports' } '/linkedServices\?' { 'linkedServices' }
                    '/linkedStorageAccounts\?' { 'linkedStorageAccounts' } 'diagnosticSettings\?' { 'diagnosticSettings' } '/savedSearches\?' { 'savedSearches' } 'eventtypes/management' { 'activityLog' }
                }
                $out[$u] = if ($name -eq 'workspace') { @{ Status = 200; Body = $script:contoso.Workspace; Items = $null; Error = '' } } else { $script:contoso.Arm[$name] }
            }
            $out
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACLogQueryBatch -MockWith {
            $script:kqlWorkspace = $WorkspaceId
            $script:kqlQueries = @($Query.Keys)
            $rows = @{}; $errors = @{}
            foreach ($name in @($Query.Keys)) {
                $rows[$name] = @($script:contoso.Kql.Rows[$name])
                if ($script:contoso.Kql.Errors.Contains($name)) { $errors[$name] = $script:contoso.Kql.Errors[$name] }
            }
            @{ Rows = $rows; Errors = $errors }
        }
        $script:graphQueries = @(); $script:armUris = @(); $script:kqlQueries = @(); $script:kqlWorkspace = $null
    }

    It 'finds the workspace by its workspace ID and returns one assessment' {
        $result = Invoke-AACLogAnalyticsWorkspaceAssessment -WorkspaceId $script:contoso.WorkspaceId -NoDisplay
        $result.PSObject.TypeNames[0] | Should -Be 'AAC.LogAnalyticsWorkspaceAssessment'
        $result.Name | Should -Be 'law-contoso'
        $result.BillableGB | Should -Be 99
        $result.Tables[0].PSObject.TypeNames[0] | Should -Be 'AAC.LogAnalyticsTable'
        $result.Recommendations[0].PSObject.TypeNames[0] | Should -Be 'AAC.LogAnalyticsRecommendation'
        $script:graphQueries | Should -Contain 'workspace'
        $script:kqlWorkspace | Should -Be $script:contoso.WorkspaceId -Because 'KQL goes to the workspace ID'
        $script:graphQueries | Should -Contain 'associations' -Because 'the rules found are looked up for associations'
    }

    It 'takes a resource ID without a Resource Graph lookup' {
        $null = Invoke-AACLogAnalyticsWorkspaceAssessment -WorkspaceId $script:contoso.ResourceId -NoDisplay
        $script:graphQueries | Should -Not -Contain 'workspace'
        @($script:armUris | Where-Object { $_ -like "$($script:contoso.ResourceId)?api-version=*" }).Count | Should -Be 1
    }

    It 'reads only what -Section asks for' {
        $result = Invoke-AACLogAnalyticsWorkspaceAssessment -WorkspaceId $script:contoso.ResourceId -Section Tables -NoDisplay
        @($script:kqlQueries) | Should -Be @('tables')
        @($script:armUris | Where-Object { $_ -match 'eventtypes|dataExports|diagnosticSettings' }).Count | Should -Be 0
        $result.Tables.Count | Should -BeGreaterThan 0
    }

    It 'looks back -Days in the queries and the activity log' {
        $null = Invoke-AACLogAnalyticsWorkspaceAssessment -WorkspaceId $script:contoso.ResourceId -Days 7 -NoDisplay
        Should -Invoke -ModuleName 'Azure.Admin.Console' Invoke-AACLogQueryBatch -ParameterFilter { $Timespan -eq 'P7D' -and $Query['tables'] -match 'ago\(7d\)' }
        @($script:armUris | Where-Object { $_ -match 'eventtypes/management' -and $_ -match 'resourceGroupName%20eq%20%27rg-contoso-ops%27' }).Count | Should -Be 1
    }

    It 'says when no workspace has that workspace ID' {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith { @{ Rows = @{ workspace = @() }; Errors = @{} } }
        { $null = & $script:capture { Invoke-AACLogAnalyticsWorkspaceAssessment -WorkspaceId '99999999-9999-9999-9999-999999999999' -NoDisplay } } | Should -Throw -ExpectedMessage '*No Log Analytics workspace with workspace ID 99999999*'
    }

    It 'shows recommendations, billable and not billable tables, settings and every insights tab' {
        $text = (& $script:capture { Invoke-AACLogAnalyticsWorkspaceAssessment -WorkspaceId $script:contoso.ResourceId -NoPaging }).Text
        foreach ($expected in 'Recommendations', 'The daily cap stopped data collection', 'Billable tables', 'Not billable tables', 'ContainerLogV2', 'AzureActivity',
            'Workspace settings', 'Local authentication', 'Usage', 'Billable GB per day', 'By computer, last 24 hours', 'Health', 'Data collection Stopped',
            'Agents by type', 'Agents without a recent heartbeat', 'vm-sql01', 'Query audit', 'Data collection rules', 'dcr-windows', 'Change log', 'tables/SecurityEvent', 'Query auditing is off') {
            $text | Should -Match ([regex]::Escape($expected))
        }
    }

    It 'keeps the AAC type names of what it returns after drawing the view (-PassThru)' {
        $result = (& $script:capture { Invoke-AACLogAnalyticsWorkspaceAssessment -WorkspaceId $script:contoso.ResourceId -NoPaging -PassThru }).Output[0]
        @($result.Tables | ForEach-Object { $_.PSObject.TypeNames[0] } | Select-Object -Unique) | Should -Be @('AAC.LogAnalyticsTable')
        @($result.Agents | ForEach-Object { $_.PSObject.TypeNames[0] } | Select-Object -Unique) | Should -Be @('AAC.LogAnalyticsAgent')
        @($result.ChangeLog | ForEach-Object { $_.PSObject.TypeNames[0] } | Select-Object -Unique) | Should -Be @('AAC.LogAnalyticsChange')
    }

    It 'shows only the sections asked for' {
        $text = (& $script:capture { Invoke-AACLogAnalyticsWorkspaceAssessment -WorkspaceId $script:contoso.ResourceId -Section Agents -NoPaging }).Text
        $text | Should -Match 'Agents by type'
        $text | Should -Not -Match 'Workspace settings'
        $text | Should -Not -Match 'Billable tables'
    }

    It 'writes the tables to CSV and every section to an HTML report' {
        $csv = Join-Path $TestDrive 'tables.csv'
        $html = Join-Path $TestDrive 'workspace.html'
        $null = & $script:capture { Invoke-AACLogAnalyticsWorkspaceAssessment -WorkspaceId $script:contoso.ResourceId -CsvPath $csv -HtmlPath $html }
        $rows = @(Import-Csv -LiteralPath $csv)
        $rows.Table | Should -Contain 'ContainerLogV2'
        $rows[0].PSObject.Properties.Name | Should -Contain 'BillableGB'
        $page = Get-Content -LiteralPath $html -Raw
        foreach ($expected in 'Recommendations', 'Workspace settings', 'Usage: ingestion per day', 'Health: operations', 'Agents', 'Query audit: by user and app', 'Data collection rules sending to this workspace', 'Change log') {
            $page | Should -Match ([regex]::Escape($expected))
        }
    }
}
