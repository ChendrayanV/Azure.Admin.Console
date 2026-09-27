<#
    Unit tests for Invoke-AACApplicationInsightQuery. Resource Graph (finding
    the workspace) and Azure Resource Manager (the query API) are mocked, so
    the KQL the command builds, the flattening of both table schemas, the
    view and the exports run for real without Azure.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

Describe 'Azure Admin Console - Invoke-AACApplicationInsightQuery' {
    BeforeAll {
        $script:sub = '11111111-1111-1111-1111-111111111111'
        $script:workspaceId = "/subscriptions/$script:sub/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-prod"
        $script:componentId = "/subscriptions/$script:sub/resourceGroups/rg-monitoring/providers/Microsoft.Insights/components/appi-prod"
        $details = '[{"message":"Timeout expired.","type":"System.Data.SqlClient.SqlException","severityLevel":3,"parsedStack":[{"level":0,"method":"Orders.Repo.SaveAsync","fileName":"/src/Repo.cs","line":42}]},{"message":"inner","type":"System.ComponentModel.Win32Exception"}]'
        $script:workspaceTable = @{
            tables = @(@{
                    name    = 'PrimaryResult'
                    columns = @('TimeGenerated', 'ExceptionType', 'Message', 'OuterMessage', 'SeverityLevel', 'Details', 'Properties', 'ProblemId', 'OperationName', 'AppRoleName', 'Method', 'ItemCount', 'ClientCountryOrRegion') | ForEach-Object { @{ name = $_; type = 'string' } }
                    rows    = @(
                        , @('2026-09-27T10:15:00Z', 'System.Data.SqlClient.SqlException', 'Timeout expired.', 'Timeout expired.', 3, $details, '{"Env":"prod","Region":"uksouth"}', 'Sql at Save', 'POST /orders', 'orders-api', 'Orders.Repo.SaveAsync', 2, 'United Kingdom')
                        , @('2026-09-27T10:10:00Z', 'System.NullReferenceException', 'Object reference not set.', '', 4, '[]', '{}', 'Null at Profile', 'GET /profile', 'portal-web', 'Portal.Profile', 1, 'Ireland')
                    )
                })
        }
        $script:classicTable = @{
            tables = @(@{
                    name    = 'PrimaryResult'
                    columns = @('timestamp', 'type', 'message', 'severityLevel', 'details', 'customDimensions', 'operation_Name', 'cloud_RoleName', 'cloud_RoleInstance', 'itemCount') | ForEach-Object { @{ name = $_; type = 'string' } }
                    rows    = @(, @('2026-09-27T09:00:00Z', 'System.TimeoutException', 'The operation timed out.', 2, $details, '{"Env":"test"}', 'GET /search', 'catalog-api', 'catalog-1', 1))
                })
        }
    }

    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACResourceGraphQuery -ParameterFilter { $Query -match 'operationalinsights/workspaces' } -MockWith {
            if ($Query -match "name =~ 'law-prod'") { [pscustomobject]@{ id = $workspaceId; name = 'law-prod'; resourceGroup = 'rg-monitoring'; subscriptionId = $sub; location = 'uksouth' } }
            elseif ($Query -match "name =~ 'law-twice'") {
                [pscustomobject]@{ id = "$workspaceId-1"; name = 'law-twice'; resourceGroup = 'rg-a'; subscriptionId = $sub; location = 'uksouth' }
                [pscustomobject]@{ id = "$workspaceId-2"; name = 'law-twice'; resourceGroup = 'rg-b'; subscriptionId = $sub; location = 'uksouth' }
            }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACResourceGraphQuery -ParameterFilter { $Query -match 'insights/components' } -MockWith {
            [pscustomobject]@{ id = $componentId; name = 'appi-prod'; resourceGroup = 'rg-monitoring'; subscriptionId = $sub; location = 'uksouth' }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -ParameterFilter { $Uri -like '*/workspaces/*' } -MockWith { $workspaceTable }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -ParameterFilter { $Uri -like '*/components/*' } -MockWith { $classicTable }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Show-AACExceptionView -MockWith { }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Show-AACQueryResultView -MockWith { }
    }

    It 'queries the workspace''s AppExceptions table for the last 2 hours by default, through ARM' {
        $null = Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-prod' -NoDisplay
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -Times 1 -Exactly -ParameterFilter {
            $body = $Body | ConvertFrom-Json
            $Method -eq 'Post' -and $Uri -eq "$workspaceId/api/query?api-version=2020-08-01" -and
            $body.timespan -eq 'PT2H' -and $body.query -match '^AppExceptions' -and $body.query -match 'TimeGenerated > ago\(2h\)' -and $body.query -match 'top 1000 by TimeGenerated desc'
        }
    }

    It 'turns the parameters into KQL filters, escaping the values' {
        $null = Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-prod' -NoDisplay -Last 30m -MinimumSeverity Error -AppRoleName 'orders-api', "o'brien" -ExceptionType '*SqlException', 'System.Net.*' -Search "can't connect" -Top 50
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -Times 1 -Exactly -ParameterFilter {
            $q = ($Body | ConvertFrom-Json).query
            ($Body | ConvertFrom-Json).timespan -eq 'PT30M' -and
            $q -match 'ago\(30m\)' -and $q -match 'toint\(SeverityLevel\) >= 3' -and
            $q.Contains("AppRoleName in~ ('orders-api', 'o\'brien')") -and
            $q.Contains("matches regex @'(?i)^(.*SqlException|System\.Net\..*)$'") -and
            $q.Contains("contains 'can\'t connect'") -and $q -match 'top 50 by'
        }
    }

    It 'flattens each exception: type, message, severity, details, stack, properties' {
        $rows = @(Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-prod' -NoDisplay)
        $rows.Count | Should -Be 2
        $first = $rows[0]
        $first.PSObject.TypeNames | Should -Contain 'AAC.ApplicationInsightsException'
        $first.TimeGenerated | Should -Be ([datetime]::new(2026, 9, 27, 10, 15, 0, [DateTimeKind]::Utc))
        $first.Severity | Should -Be 'Error'
        $first.SeverityLevel | Should -Be 3
        $first.ExceptionType | Should -Be 'System.Data.SqlClient.SqlException'
        $first.DetailType | Should -Be 'System.Data.SqlClient.SqlException'
        $first.DetailMessage | Should -Be 'Timeout expired.'
        $first.DetailSeverityLevel | Should -Be '3'
        $first.DetailCount | Should -Be 2
        $first.StackTop | Should -Be 'Orders.Repo.SaveAsync (/src/Repo.cs:42)'
        $first.CustomProperties | Should -Be 'Env=prod; Region=uksouth'
        $first.ItemCount | Should -Be 2
        $first.Source | Should -Be 'law-prod'
        $rows[1].Severity | Should -Be 'Critical'
        $rows[1].DetailCount | Should -Be 0
    }

    It 'reads an Application Insights resource''s classic exceptions table into the same shape' {
        $rows = @(Invoke-AACApplicationInsightQuery -ApplicationInsightsName 'appi-prod' -NoDisplay -Last 1d)
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -Times 1 -Exactly -ParameterFilter {
            $q = ($Body | ConvertFrom-Json).query
            $Uri -eq "$componentId/api/query?api-version=2018-04-20" -and $q -match '^exceptions' -and $q -match 'timestamp > ago\(1d\)' -and ($Body | ConvertFrom-Json).timespan -eq 'P1D'
        }
        $rows[0].ExceptionType | Should -Be 'System.TimeoutException'
        $rows[0].Severity | Should -Be 'Warning'
        $rows[0].AppRoleName | Should -Be 'catalog-api'
        $rows[0].AppRoleInstance | Should -Be 'catalog-1'
        $rows[0].OperationName | Should -Be 'GET /search'
        $rows[0].CustomProperties | Should -Be 'Env=test'
    }

    It 'runs any KQL with -Query, returning its columns as objects' {
        $rows = @(Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-prod' -Query 'AppRequests | take 5' -NoDisplay)
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -Times 1 -Exactly -ParameterFilter { ($Body | ConvertFrom-Json).query -eq 'AppRequests | take 5' }
        $rows[0].PSObject.Properties.Name | Should -Contain 'ExceptionType'
        $rows[0].PSObject.TypeNames | Should -Not -Contain 'AAC.ApplicationInsightsException'
    }

    It 'refuses the exception filters together with -Query' {
        { Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-prod' -Query 'AppRequests' -MinimumSeverity Error -NoDisplay } | Should -Throw '*-MinimumSeverity*'
    }

    It 'says so when the workspace is not found, or is found more than once' {
        { Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-missing' -NoDisplay } | Should -Throw "*No Log Analytics workspace named 'law-missing'*"
        { Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-twice' -NoDisplay } | Should -Throw '*-SubscriptionId or -ResourceGroupName*'
    }

    It 'rejects a -Last it cannot read' {
        { Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-prod' -Last '2 hours' -NoDisplay } | Should -Throw
    }

    It 'shows the view at the prompt, and writes CSV and HTML instead of it' {
        @(Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-prod' -NoPaging).Count | Should -Be 0
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Show-AACExceptionView -Times 1 -Exactly
        $csv = Join-Path -Path $TestDrive -ChildPath 'ex.csv'
        $html = Join-Path -Path $TestDrive -ChildPath 'ex.html'
        $null = Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-prod' -CsvPath $csv -HtmlPath $html
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Show-AACExceptionView -Times 1 -Exactly
        @(Import-Csv -LiteralPath $csv).Count | Should -Be 2
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        $model.tables[0].rows.Count | Should -Be 2
        ($model.tiles | Where-Object label -EQ 'exceptions').value | Should -Be '3' -Because 'counts use ItemCount'
    }
}

Describe 'Azure Admin Console - exceptions view' {
    It 'draws the tiles, the timeline, the types, problems and latest exceptions using only code page 437/850 characters' {
        $exceptions = InModuleScope 'Azure.Admin.Console' {
            $now = [datetime]::UtcNow
            foreach ($i in 0..11) {
                ConvertTo-AACExceptionRecord -Source 'law' -Row ([ordered]@{
                        TimeGenerated = $now.AddMinutes(-$i * 9).ToString('o'); ExceptionType = $(if ($i % 3) { 'System.TimeoutException' } else { 'System.NullReferenceException' })
                        Message = "Something failed $i"; SeverityLevel = $i % 5; OperationName = 'GET /x'; AppRoleName = 'api'; ProblemId = "p$($i % 3)"; ItemCount = 1
                    })
            }
        }
        $text = InModuleScope 'Azure.Admin.Console' -Parameters @{ Items = $exceptions } {
            param($Items)
            $real = [Spectre.Console.AnsiConsole]::Console
            $buffer = [System.IO.StringWriter]::new()
            $settings = [Spectre.Console.AnsiConsoleSettings]::new()
            $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer)
            $settings.Ansi = [Spectre.Console.AnsiSupport]::No
            # No CI detection: on GitHub Actions (or Azure Pipelines...) Spectre's
            # default enrichers would switch on ANSI colour and Unicode, overriding
            # what this console is set to - and the text checks would fail.
            $settings.Enrichment.UseDefaultEnrichers = $false
            $console = [Spectre.Console.AnsiConsole]::Create($settings)
            $console.Profile.Width = 140
            $console.Profile.Capabilities.Unicode = $false
            try {
                [Spectre.Console.AnsiConsole]::Console = $console
                Show-AACExceptionView -Exception $Items -Scope ([ordered]@{ Source = 'law' }) -Range ([timespan]::FromHours(2))
            }
            finally { [Spectre.Console.AnsiConsole]::Console = $real }
            $buffer.ToString()
        }
        foreach ($expected in 'exceptions', 'problems', 'Exceptions over time', 'Top exception types', 'Top problems', 'Latest exceptions', 'System.TimeoutException', 'CRITICAL') {
            $text | Should -BeLike "*$expected*"
        }
        $bad = @($text.ToCharArray() | Where-Object { [int]$_ -gt 126 -and -not [System.Text.Encoding]::GetEncoding(437).GetString([System.Text.Encoding]::GetEncoding(437).GetBytes([string]$_)).Equals([string]$_) } | Select-Object -Unique)
        $bad | Should -BeNullOrEmpty
    }
}
