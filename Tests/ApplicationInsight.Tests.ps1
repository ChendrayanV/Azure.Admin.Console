<#
    Unit tests for Invoke-AACApplicationInsightQuery. Resource Graph (finding
    the workspace) and the query APIs (Invoke-AACArmRequest) are mocked, so
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
        # What the query APIs address them by: the workspace ID and the app ID.
        $script:workspaceGuid = 'aaaaaaaa-0000-0000-0000-000000000001'
        $script:appGuid = 'bbbbbbbb-0000-0000-0000-000000000002'
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
            if ($Query -match "name =~ 'law-prod'") { [pscustomobject]@{ id = $workspaceId; name = 'law-prod'; resourceGroup = 'rg-monitoring'; subscriptionId = $sub; location = 'uksouth'; customerId = $workspaceGuid } }
            elseif ($Query -match "name =~ 'law-twice'") {
                [pscustomobject]@{ id = "$workspaceId-1"; name = 'law-twice'; resourceGroup = 'rg-a'; subscriptionId = $sub; location = 'uksouth' }
                [pscustomobject]@{ id = "$workspaceId-2"; name = 'law-twice'; resourceGroup = 'rg-b'; subscriptionId = $sub; location = 'uksouth' }
            }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACResourceGraphQuery -ParameterFilter { $Query -match 'insights/components' } -MockWith {
            [pscustomobject]@{ id = $componentId; name = 'appi-prod'; resourceGroup = 'rg-monitoring'; subscriptionId = $sub; location = 'uksouth'; appId = $appGuid }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -ParameterFilter { $Uri -like '*/workspaces/*' } -MockWith { $workspaceTable }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -ParameterFilter { $Uri -like '*/apps/*' } -MockWith { $classicTable }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Show-AACExceptionView -MockWith { }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Show-AACQueryResultView -MockWith { }
    }

    It 'queries the workspace''s AppExceptions table for the last 2 hours by default, through the Log Analytics API' {
        $null = Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-prod' -NoDisplay
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -Times 1 -Exactly -ParameterFilter {
            $body = $Body | ConvertFrom-Json
            $Method -eq 'Post' -and $Uri -eq "https://api.loganalytics.azure.com/v1/workspaces/$workspaceGuid/query" -and $Resource -eq 'https://api.loganalytics.io' -and
            $body.timespan -eq 'PT2H' -and $body.query -match '^AppExceptions' -and $body.query -match 'TimeGenerated > ago\(2h\)' -and $body.query -match 'order by TimeGenerated desc$'
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
            $Uri -eq "https://api.applicationinsights.io/v1/apps/$appGuid/query" -and $Resource -eq 'https://api.applicationinsights.io' -and $q -match '^exceptions' -and $q -match 'timestamp > ago\(1d\)' -and ($Body | ConvertFrom-Json).timespan -eq 'P1D'
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

    It 'reads another table with -TableName: the workspace name for a workspace, newest first, as plain rows' {
        $rows = @(Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-prod' -TableName requests -Last 1d -NoDisplay)
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -Times 1 -Exactly -ParameterFilter {
            $q = ($Body | ConvertFrom-Json).query
            $q -match '^AppRequests\n' -and $q -match 'TimeGenerated > ago\(1d\)' -and $q -match 'order by TimeGenerated desc$'
        }
        $rows.Count | Should -Be 2
        $rows[0].PSObject.TypeNames | Should -Not -Contain 'AAC.ApplicationInsightsException'
    }

    It 'turns a workspace table name into the resource''s classic one, and filters any table' {
        $null = Invoke-AACApplicationInsightQuery -ApplicationInsightsName 'appi-prod' -TableName AppTraces -MinimumSeverity Warning -AppRoleName 'orders-api' -Search "it's" -NoDisplay
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -Times 1 -Exactly -ParameterFilter {
            $q = ($Body | ConvertFrom-Json).query
            $q -match '^traces\n' -and $q -match 'timestamp > ago\(2h\)' -and $q -match 'toint\(severityLevel\) >= 2' -and
            $q -match "column_ifexists\('cloud_RoleName', ''\)\) in~ \('orders-api'\)" -and $q -match "tostring\(pack_all\(\)\) contains 'it\\'s'"
        }
    }

    It 'shows a table''s useful columns first, under its name' {
        $null = Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-prod' -TableName requests -NoPaging
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Show-AACQueryResultView -Times 1 -Exactly -ParameterFilter {
            $Title -eq 'AppRequests' -and $PreferredColumn[0] -eq 'TimeGenerated' -and $PreferredColumn -contains 'ResultCode' -and $Scope['Table'] -eq 'AppRequests'
        }
    }

    It 'reads the exceptions as usual with -TableName exceptions' {
        $rows = @(Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-prod' -TableName exceptions -NoDisplay)
        $rows[0].PSObject.TypeNames | Should -Contain 'AAC.ApplicationInsightsException'
    }

    It 'refuses filters a table can''t take, and table names that aren''t names' {
        { Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-prod' -TableName requests -ExceptionType '*Sql*' -NoDisplay } | Should -Throw '*-ExceptionType is for the exceptions*AppRequests*'
        { Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-prod' -TableName requests -MinimumSeverity Error -NoDisplay } | Should -Throw '*-MinimumSeverity is for exceptions and traces*'
        { Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-prod' -TableName requests -Query 'AppRequests' -NoDisplay } | Should -Throw '*-TableName*'
        { Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-prod' -TableName 'AppRequests | take 1' -NoDisplay } | Should -Throw
    }

    It 'refuses the exception filters together with -Query' {
        { Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-prod' -Query 'AppRequests' -MinimumSeverity Error -NoDisplay } | Should -Throw '*-MinimumSeverity*'
    }

    It 'says so when the workspace is not found, or is found more than once' {
        { Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-missing' -NoDisplay } | Should -Throw "*No Log Analytics workspace named 'law-missing'*"
        { Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-twice' -NoDisplay } | Should -Throw '*-SubscriptionId or -ResourceGroupName*'
    }

    It 'returns nothing - and no error - when the query finds no rows' {
        $empty = @{ tables = @(@{ name = 'PrimaryResult'; columns = @(@{ name = 'TimeGenerated'; type = 'datetime' }); rows = @() }) }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -ParameterFilter { $Uri -like '*/workspaces/*' } -MockWith { $empty }.GetNewClosure()
        @(Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-prod' -NoDisplay).Count | Should -Be 0
        @(Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-prod' -Query 'AppRequests' -NoDisplay).Count | Should -Be 0
        $null = Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-prod' -NoPaging
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Show-AACExceptionView -Times 1 -Exactly
    }

    It 'explains no exceptions in a workspace: no Application Insights resource sends to it' {
        $empty = @{ tables = @(@{ name = 'PrimaryResult'; columns = @(@{ name = 'TimeGenerated'; type = 'datetime' }); rows = @() }) }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -ParameterFilter { $Uri -like '*/workspaces/*' } -MockWith { $empty }.GetNewClosure()
        # appi-prod sends to another workspace; appi-old is classic.
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACResourceGraphQuery -ParameterFilter { $Query -match 'insights/components' -and $Query -notmatch 'name =~' } -MockWith {
            [pscustomobject]@{ name = 'appi-prod'; resourceGroup = 'rg-app'; subscriptionId = $sub; workspaceId = "/subscriptions/$sub/resourceGroups/rg-other/providers/Microsoft.OperationalInsights/workspaces/law-other" }
            [pscustomobject]@{ name = 'appi-old'; resourceGroup = 'rg-app'; subscriptionId = $sub; workspaceId = '' }
        }
        $null = Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-prod' -Last 15d -NoDisplay -WarningVariable warnings -WarningAction SilentlyContinue
        "$warnings" | Should -BeLike 'No Application Insights resource sends to law-prod*appi-prod (sends to law-other), appi-old (classic, keeps its own data)*'
        "$warnings" | Should -BeLike "*Invoke-AACApplicationInsightQuery -ApplicationInsightsName 'appi-prod' -Last 15d"
    }

    It 'explains no exceptions in a workspace that Application Insights does send to' {
        $empty = @{ tables = @(@{ name = 'PrimaryResult'; columns = @(@{ name = 'TimeGenerated'; type = 'datetime' }); rows = @() }) }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -ParameterFilter { $Uri -like '*/workspaces/*' } -MockWith { $empty }.GetNewClosure()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACResourceGraphQuery -ParameterFilter { $Query -match 'insights/components' -and $Query -notmatch 'name =~' } -MockWith {
            [pscustomobject]@{ name = 'appi-prod'; resourceGroup = 'rg-app'; subscriptionId = $sub; workspaceId = $workspaceId.ToUpperInvariant() }
        }
        $null = Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-prod' -NoDisplay -WarningVariable warnings -WarningAction SilentlyContinue
        "$warnings" | Should -BeLike '*that send to it - appi-prod - recorded none in that time*'
        # A query of your own gets no such note.
        $null = Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-prod' -Query 'AppRequests' -NoDisplay -WarningVariable ownQuery -WarningAction SilentlyContinue
        $ownQuery | Should -BeNullOrEmpty
    }

    It 'fails - rather than returning nothing - when the query API replies without a result table' {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -ParameterFilter { $Uri -like '*/workspaces/*' } -MockWith { @{ value = @() } }
        { Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-prod' -NoDisplay } | Should -Throw '*query API returned no result table ({"value":`[`]})*'
    }

    It 'says so when Resource Graph has no workspace ID to query by' {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACResourceGraphQuery -ParameterFilter { $Query -match 'operationalinsights/workspaces' } -MockWith {
            [pscustomobject]@{ id = $workspaceId; name = 'law-prod'; resourceGroup = 'rg-monitoring'; subscriptionId = $sub; location = 'uksouth' }
        }
        { Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-prod' -NoDisplay } | Should -Throw '*no workspace ID (customerId)*'
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

Describe 'Azure Admin Console - errors' {
    BeforeAll {
        $script:sub = '11111111-1111-1111-1111-111111111111'
        # A console like a real terminal (interactive, so the error panel is
        # drawn), writing plain text into a buffer.
        $script:captureInteractive = {
            param([scriptblock] $Render)
            $real = [Spectre.Console.AnsiConsole]::Console
            $buffer = [System.IO.StringWriter]::new()
            $settings = [Spectre.Console.AnsiConsoleSettings]::new()
            $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer)
            $settings.Ansi = [Spectre.Console.AnsiSupport]::No
            $settings.Interactive = [Spectre.Console.InteractionSupport]::Yes
            $settings.Enrichment.UseDefaultEnrichers = $false
            $console = [Spectre.Console.AnsiConsole]::Create($settings)
            $console.Profile.Width = 160
            $failure = $null
            try {
                [Spectre.Console.AnsiConsole]::Console = $console
                try { $null = & $Render } catch { $failure = $_ }
            }
            finally {
                [Spectre.Console.AnsiConsole]::Console = $real
            }
            [pscustomobject]@{ Text = $buffer.ToString(); Error = $failure }
        }
    }

    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACResourceGraphQuery -MockWith {
            [pscustomobject]@{ id = "/subscriptions/$sub/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/law-prod"; name = 'law-prod'; resourceGroup = 'rg'; subscriptionId = $sub; location = 'uksouth'; customerId = 'aaaaaaaa-0000-0000-0000-000000000001' }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Show-AACExceptionView -MockWith { }
    }

    It 'stops with the command''s own error, pointing at the caller - not a line inside the module' {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACResourceGraphQuery -MockWith { }
        $failure = $null
        try { Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-missing' -NoDisplay } catch { $failure = $_ }
        $failure.FullyQualifiedErrorId | Should -BeExactly 'CommandFailed,Invoke-AACApplicationInsightQuery'
        $failure.Exception.Message | Should -BeLike "No Log Analytics workspace named 'law-missing'*"
        $failure.InvocationInfo.ScriptName | Should -Be $PSCommandPath -Because 'the error points at the line that ran the command'
    }

    It 'explains an Azure refusal by its status, with what to do' {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -MockWith {
            $exception = [System.Exception]::new("The client 'someone' does not have authorization to perform action 'Microsoft.OperationalInsights/workspaces/query/read'.")
            $exception.Data['StatusCode'] = 403
            throw $exception
        }
        $failure = $null
        try { Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-prod' -NoDisplay } catch { $failure = $_ }
        $failure.FullyQualifiedErrorId | Should -BeExactly 'AzureRequestFailed403,Invoke-AACApplicationInsightQuery'
        $failure.CategoryInfo.Category | Should -Be 'PermissionDenied'
        $failure.Exception.Message | Should -BeLike 'Azure refused the request (403): The client*Log Analytics Reader*'
    }

    It 'calls a mistake in the module a bug, with where it happened and where to report it' {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -MockWith {
            Set-StrictMode -Version Latest
            ([pscustomobject]@{ Name = 'x' }).Missing
        }
        $failure = $null
        try { Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-prod' -NoDisplay } catch { $failure = $_ }
        $failure.FullyQualifiedErrorId | Should -BeExactly 'InternalError,Invoke-AACApplicationInsightQuery'
        $failure.Exception.Message | Should -BeLike "Azure.Admin.Console hit an internal error: The property 'Missing' cannot be found*github.com/ChendrayanV/Azure.Admin.Console/issues*"
        $failure.Exception.InnerException | Should -BeOfType [System.Management.Automation.PropertyNotFoundException]
    }

    It 'draws a red panel at the console: what failed, the step that was running and what to do' {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -MockWith {
            $exception = [System.Exception]::new('Forbidden.')
            $exception.Data['StatusCode'] = 403
            throw $exception
        }
        $run = & $script:captureInteractive { Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-prod' -NoPaging }
        $run.Error | Should -Not -BeNullOrEmpty
        $run.Text | Should -BeLike '*Invoke-AACApplicationInsightQuery failed*'
        $run.Text | Should -BeLike '*Azure refused the request (403): Forbidden.*'
        $run.Text | Should -BeLike '*Step*Running the exceptions query over the last 2h*'
        $run.Text | Should -BeLike '*Fix*Your account needs a role*'
        $run.Text | Should -BeLike '*Running the exceptions query over the last 2h - failed*' -Because 'the progress line of the failed step says so'
    }

    It 'passes on the query API''s own reason for a bad query, innermost detail included' {
        InModuleScope 'Azure.Admin.Console' {
            Mock Get-AACAccessToken { 'fake-token' }
            Mock Send-AACHttpRequest {
                $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::BadRequest)
                $response.Content = [System.Net.Http.StringContent]::new('{"error":{"message":"The request had some invalid properties","code":"BadArgumentError","innererror":{"code":"SemanticError","message":"A semantic error occurred.","innererror":{"code":"SEM0100","message":"Failed to resolve column Nope"}}}}')
                [System.Threading.Tasks.Task]::FromResult($response)
            }
            $failure = $null
            try { Invoke-AACLogQuery -Kind Workspace -Id 'aaaaaaaa-0000-0000-0000-000000000001' -Query 'AppRequests | where Nope > 1' } catch { $failure = $_ }
            $failure.Exception.Message | Should -BeExactly 'The request had some invalid properties A semantic error occurred. Failed to resolve column Nope'
            $failure.Exception.Data['StatusCode'] | Should -Be 400
            Should -Invoke Get-AACAccessToken -ParameterFilter { $Resource -eq 'https://api.loganalytics.io' }
            Should -Invoke Send-AACHttpRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'https://api.loganalytics.azure.com/v1/workspaces/aaaaaaaa-0000-0000-0000-000000000001/query' -and $Token -eq 'fake-token' } -Because 'a 400 is not retried'
        }
    }

    It 'names the tables that do exist - closest first, with their rows - when the table doesn''t' {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -ParameterFilter { $Uri -like '*/metadata' } -MockWith {
            @{ tables = @(
                    @{ name = 'AppRequests'; timespanColumn = 'TimeGenerated' }, @{ name = 'AppTraces'; timespanColumn = 'TimeGenerated' },
                    @{ name = 'AppExceptions'; timespanColumn = 'TimeGenerated' }, @{ name = 'Heartbeat'; timespanColumn = 'TimeGenerated' }, @{ name = 'Perf'; timespanColumn = 'TimeGenerated' }) }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -ParameterFilter { $Body -match 'union isfuzzy' } -MockWith {
            @{ tables = @(@{ name = 'PrimaryResult'; columns = @(@{ name = 'AACTable' }, @{ name = 'Rows' }); rows = @(, @('AppRequests', 1204)) }) }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -ParameterFilter { $Uri -like '*/query' -and $Body -notmatch 'union isfuzzy' } -MockWith {
            $exception = [System.Exception]::new("The request had some invalid properties 'where' operator: Failed to resolve table or column expression named 'AppReqests'")
            $exception.Data['StatusCode'] = 400
            throw $exception
        }
        $run = & $script:captureInteractive { Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-prod' -TableName AppReqests -Last 15d -NoPaging }
        $run.Error.Exception.Message | Should -BeLike "There is no table 'AppReqests' in law-prod.*Did you mean 'AppRequests'?*"
        $run.Error.Exception.Message | Should -BeLike '*Tables in law-prod with data in the last 15d: AppRequests (1,204).*No data: AppExceptions, AppTraces.*'
        $run.Error.Exception.Message | Should -BeLike '*(2 more in its metadata.)*' -Because 'a workspace''s other tables are counted, not listed'
        $run.Text | Should -BeLike '*Invoke-AACApplicationInsightQuery failed*'
        $run.Text | Should -BeLike "*There is no table 'AppReqests' in law-prod.*"
        $run.Text | Should -BeLike "*Fix*Did you mean 'AppRequests'?*"
        $run.Text | Should -BeLike '*Step*Running the AppReqests query over the last 15d*'
    }

    It 'still names the Application Insights tables when the metadata can''t be read' {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -MockWith { throw 'Forbidden' }
        InModuleScope 'Azure.Admin.Console' {
            Get-AACTableSuggestion -Kind Component -Id 'x' -TableName 'reqests' -SourceName 'appi-prod' -Last '2h'
        } | Should -BeLike "appi-prod's Application Insights tables are: requests, dependencies, exceptions*"
    }

    It 'draws no panel when errors are silenced' {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACResourceGraphQuery -MockWith { }
        $run = & $script:captureInteractive { Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-missing' -NoPaging -ErrorAction SilentlyContinue }
        $run.Text | Should -Not -BeLike '*Invoke-AACApplicationInsightQuery failed*'
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
