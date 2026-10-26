<#
    Unit tests for Invoke-AACFunctionAppAssessment: made-up Contoso function
    apps (Fixtures\ContosoFunctionApp.ps1) on Elastic Premium, Consumption
    and Flex Consumption - hosting, runtime support, usage, functions and
    triggers, configuration, app settings by name only, networking,
    deployments, slots, backups, connections, the Activity Log, the
    Well-Architected checks, PSRule, Advisor and Defender - with Resource
    Graph, Resource Manager and Azure Monitor mocked.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
    $script:canWritePdf = $IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4'
}

BeforeAll {
    . (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Fixtures/ContosoFunctionApp.ps1')
    $script:fx = Get-AACContosoFunctionApp
    $script:capture = {
        param([scriptblock] $Render)
        $real = [Spectre.Console.AnsiConsole]::Console
        $buffer = [System.IO.StringWriter]::new()
        $settings = [Spectre.Console.AnsiConsoleSettings]::new()
        $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer)
        $settings.Ansi = [Spectre.Console.AnsiSupport]::No
        $settings.Enrichment.UseDefaultEnrichers = $false
        $console = [Spectre.Console.AnsiConsole]::Create($settings)
        $console.Profile.Width = 170
        $console.Profile.Capabilities.Unicode = $false
        try { [Spectre.Console.AnsiConsole]::Console = $console; $output = @(& $Render) }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
}

Describe 'Azure Admin Console - Invoke-AACFunctionAppAssessment' {
    BeforeEach {
        $script:denySettings = $false
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $rows = @{}
            foreach ($key in @($Query.Keys)) { $rows[$key] = [System.Collections.Generic.List[object]]@($script:fx.Rows[$key]) }
            @{ Rows = $rows; Errors = @{} }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $out = @{}
            foreach ($u in $Uri) { $out[$u] = Get-AACContosoFunctionAppAnswer -Data $script:fx -Uri $u }
            $out
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -MockWith {
            if ($script:denySettings) { $e = [System.Exception]::new('The client does not have authorization.'); $e.Data['StatusCode'] = 403; throw $e }
            $app = ([regex]::Match($Uri, '/sites/([^/]+)/')).Groups[1].Value
            if ($Uri -like '*appsettings/list*') { @{ properties = $script:fx.Settings[$app] } } else { @{ properties = @{ Db = @{ type = 'SQLAzure'; value = 'Server=x;Password=hidden' } } } }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Read-AACMetric -MockWith { $script:fx.Metrics }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.com'; TenantId = 't'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1); RefreshToken = 'r'; ClientId = 'c'; Scope = @('s') } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'assesses each app: hosting, runtime and its support, usage, inbound access and health' {
        $apps = @(Invoke-AACFunctionAppAssessment -SkipPSRule -NoDisplay)
        @($apps | Sort-Object App | ForEach-Object { "$($_.App) | $($_.Hosting) | $($_.Runtime) | $($_.RuntimeSupport) | $($_.Model) | $($_.Health) | $($_.Inbound) | $($_.Idle)" }) | Should -Be @(
            'func-ingest-flex | Flex Consumption | python 3.12 | Supported |  | Available | Private | False'
            'func-orders-prod | Elastic Premium | dotnet v6.0 | Out of support | In-process | Available | Public | False'
            'func-reports-dev | Consumption | python 3.8 | Out of support |  | Degraded | Restricted | True'
        )
        $orders = $apps | Where-Object App -EQ 'func-orders-prod'
        "$($orders.Executions) | $($orders.GbSeconds) | $($orders.Requests) | $($orders.ErrorRate) | $($orders.AvgResponseMs) | $($orders.MemoryMaxMB) | $($orders.Functions) | $($orders.Slots) | $($orders.Deployment) | $($orders.Owner)" | Should -Be '50000 | 2000 | 10000 | 8 | 1500 | 600 | 3 | 1 | GitHub Actions | alice@contoso.com'
        ($apps | Where-Object App -EQ 'func-ingest-flex').Score | Should -Be 100
        ($apps | Where-Object App -EQ 'func-reports-dev').EstimatedMonthlyUsd | Should -Be 0 -Because 'an idle Consumption app costs nothing'
        $apps[0].PSObject.TypeNames | Should -Contain 'AAC.FunctionApp'
        $plans = @(Invoke-AACFunctionAppAssessment -SkipPSRule -View Plan -NoDisplay)
        @($plans.Plan) | Should -Be @('plan-ep-prod', 'plan-y1', 'plan-fc1') -Because 'only the apps'' plans are assessed'
        ($plans | Where-Object Plan -EQ 'plan-ep-prod').CpuMax | Should -Be 15
    }

    It 'turns failed Well-Architected checks, Activity Log patterns, Advisor and Defender into findings' {
        $have = @(Invoke-AACFunctionAppAssessment -SkipPSRule -View Finding -NoDisplay | ForEach-Object { "$($_.Severity) | $($_.App) | $($_.Finding)" })
        foreach ($expected in @(
                'High | func-orders-prod | No secrets in plain app settings'
                'High | func-orders-prod | Error rate under 5%'
                'High | func-reports-dev | HTTPS only'
                'High | func-reports-dev | Minimum TLS 1.2'
                'High | func-reports-dev | Language runtime supported'
                'Medium | func-orders-prod | HTTP functions require a key or sign-in'
                'Medium | func-orders-prod | Basic publishing credentials off'
                'Medium | func-orders-prod | CORS not open to every origin'
                'Medium | func-orders-prod | Advisor: Enable zone redundancy for the plan'
                'Medium | func-reports-dev | Defender: Function App should only be accessible over HTTPS'
                'Low | func-orders-prod | Frequent restarts'
                'Low | func-orders-prod | Storage account shared with other apps'
                'Low | plan-ep-prod | Plan over-provisioned'
                'Info | func-orders-prod | App settings or keys read'
            )) { $have | Should -Contain $expected }
        @($have | Where-Object { $_ -like '* | func-ingest-flex | *' }) | Should -BeNullOrEmpty
        $checks = @(Invoke-AACFunctionAppAssessment -SkipPSRule -View Check -NoDisplay)
        @($checks | Where-Object { $_.App -eq 'func-reports-dev' -and $_.Check -eq 'Always On' }).Status | Should -Be 'N/A' -Because 'Always On is for dedicated plans'
        @($checks | Where-Object { $_.App -eq 'func-orders-prod' -and $_.Check -eq '.NET isolated worker model' }).Status | Should -Be 'Fail'
    }

    It 'lists every function with its trigger, auth level, schedule and bindings - and says which apps couldn''t be listed' {
        $functions = @(Invoke-AACFunctionAppAssessment -SkipPSRule -View Function -NoDisplay)
        @($functions | ForEach-Object { "$($_.App)/$($_.Function) | $($_.Trigger) | $($_.AuthLevel) | $($_.Schedule) | $($_.Outputs) | $($_.Connection)" }) | Should -Be @(
            'func-orders-prod/GetOrder | http | anonymous |  | http | '
            'func-orders-prod/Cleanup | timer |  | 0 0 2 * * * |  | '
            'func-orders-prod/ProcessOrder | serviceBus |  |  | cosmosDB | ServiceBusConnection, CosmosConnection'
            'func-ingest-flex/Ingest | eventHub |  |  |  | EventHub'
        )
        $text = (& $script:capture { Invoke-AACFunctionAppAssessment -SkipPSRule -NoPaging }).Text
        $text | Should -BeLike '*functions of 1 app(s) couldn''t be listed*'
    }

    It 'reads app settings by name and kind - never their values - and the services they name' {
        $settings = @(Invoke-AACFunctionAppAssessment -SkipPSRule -View AppSetting -NoDisplay | Where-Object App -EQ 'func-orders-prod')
        @($settings | ForEach-Object { "$($_.Setting) | $($_.Kind)" }) | Should -Be @(
            'ApiKey | Key Vault reference'
            'APPLICATIONINSIGHTS_CONNECTION_STRING | Platform'
            'AzureWebJobsStorage | Key or connection string'
            'FUNCTIONS_EXTENSION_VERSION | Platform'
            'FUNCTIONS_WORKER_RUNTIME | Platform'
            'Region | Plain value'
            'ServiceBusConnection | Key or connection string'
            'SqlPassword | Plain value'
        )
        $connections = @(Invoke-AACFunctionAppAssessment -SkipPSRule -View Connection -NoDisplay)
        @($connections | ForEach-Object { "$($_.App) | $($_.Source) | $($_.Target) | $($_.TargetType) | $($_.Auth)" }) | Should -Contain 'func-ingest-flex | Service Connector | stingest | Microsoft.Storage/storageAccounts | systemAssignedIdentity'
        @($connections | ForEach-Object { "$($_.App) | $($_.Target) | $($_.Auth)" }) | Should -Contain 'func-orders-prod | kv-orders | Managed identity (Key Vault reference)'
        $csv = Join-Path $TestDrive 'settings.csv'; $html = Join-Path $TestDrive 'func.html'
        $null = & $script:capture { Invoke-AACFunctionAppAssessment -SkipPSRule -View AppSetting -CsvPath $csv -HtmlPath $html }
        foreach ($file in $csv, $html) { foreach ($secret in $script:fx.Secrets) { (Get-Content -LiteralPath $file -Raw) | Should -Not -Match ([regex]::Escape($secret)) -Because "$secret must never reach $(Split-Path -Leaf $file)" } }
    }

    It 'says when app settings can''t be listed, stops asking, and leaves the checks that need them N/A' {
        $script:denySettings = $true
        $text = (& $script:capture { Invoke-AACFunctionAppAssessment -SkipPSRule -NoPaging }).Text
        $text | Should -BeLike '*can''t list app settings*'
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -Times 1 -Exactly -Because 'one 403 means the others will fail too'
        @(Invoke-AACFunctionAppAssessment -SkipPSRule -View AppSetting -NoDisplay) | Should -BeNullOrEmpty
        @(Invoke-AACFunctionAppAssessment -SkipPSRule -View Check -NoDisplay | Where-Object Check -EQ 'No secrets in plain app settings').Status | Select-Object -Unique | Should -Be 'N/A'
        $null = Invoke-AACFunctionAppAssessment -SkipPSRule -SkipSettings -NoDisplay
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -Times 3 -Exactly -Because '-SkipSettings asks nothing (the 3 calls are the earlier runs)'
    }

    It 'reads the last week''s Activity Log: one row per operation, what kind of change, who and whether it worked' {
        $activity = @(Invoke-AACFunctionAppAssessment -SkipPSRule -View Activity -NoDisplay | Where-Object App -EQ 'func-orders-prod')
        @($activity | Group-Object -Property Kind | Sort-Object Name | ForEach-Object { "$($_.Name) $($_.Count)" }) | Should -Be @('Configuration change 1', 'Restart 4', 'Secrets or keys read 1', 'Slot swap 1') -Because 'reads are left out, and the started and succeeded events of one write are one row'
        ($activity | Where-Object Kind -EQ 'Slot swap') | ForEach-Object { "$($_.Status) | $($_.Caller)" } | Should -Be 'Failed | pipeline-sp'
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -ParameterFilter { @($Uri | Where-Object { $_ -like '*eventtypes/management/values*' }).Count -eq 3 }
    }

    It 'reports deployments, slots, backups and networking for each app' {
        @(Invoke-AACFunctionAppAssessment -SkipPSRule -View Deployment -NoDisplay | ForEach-Object { "$($_.App) | $($_.Status) | $($_.Deployer) | $($_.Message)" }) | Should -Be @('func-orders-prod | Succeeded | GitHub | Deploy 1.4.2', 'func-orders-prod | Failed | GitHub | Deploy 1.4.1', 'func-ingest-flex | Succeeded | OneDeploy | Deploy')
        (Invoke-AACFunctionAppAssessment -SkipPSRule -View Slot -NoDisplay).Slot | Should -Be 'staging'
        @(Invoke-AACFunctionAppAssessment -SkipPSRule -View Backup -NoDisplay | ForEach-Object { "$($_.App) | $($_.Supported)" }) | Should -Be @('func-orders-prod | False', 'func-reports-dev | False', 'func-ingest-flex | False')
        $network = @(Invoke-AACFunctionAppAssessment -SkipPSRule -View Network -NoDisplay)
        @($network | ForEach-Object { "$($_.App) | $($_.Inbound) | $($_.AccessRules) | $($_.PrivateEndpoints) | $($_.VnetIntegration) | $($_.Cors)" }) | Should -Be @(
            'func-orders-prod | Public | 0 | 0 |  | *'
            'func-reports-dev | Restricted | 1 | 0 |  | '
            'func-ingest-flex | Private | 0 | 1 | vnet-app/snet-func | '
        )
        @(Invoke-AACFunctionAppAssessment -SkipPSRule -View Setting -NoDisplay | Where-Object { $_.App -eq 'func-orders-prod' -and $_.Setting -eq 'FTP state' }).Value | Should -Be 'AllAllowed'
    }

    It 'runs PSRule for Azure on the apps and plans, and keeps only their results' {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-Module -ParameterFilter { $Name -eq 'PSRule.Rules.Azure' } -MockWith { [pscustomobject]@{ Name = 'PSRule.Rules.Azure' } }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACRuleData -MockWith { @{ Resources = @(@{ id = 'x' }); Warnings = @() } }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACPSRuleEngine -MockWith {
            $orders = $script:fx.Rows.apps[0].id
            @{ Results = @(
                    [pscustomobject]@{ Outcome = 'Fail'; Pillar = 'Security'; RuleName = 'Azure.AppService.MinTLS'; Title = 'Minimum TLS'; Severity = 'Critical'; ResourceName = 'func-orders-prod'; Reason = 'TLS'; Recommendation = 'Use TLS 1.2'; Link = 'https://azure.github.io/PSRule.Rules.Azure/en/rules/Azure.AppService.MinTLS/'; ResourceId = $orders }
                    [pscustomobject]@{ Outcome = 'Pass'; Pillar = 'Reliability'; RuleName = 'Azure.AppService.PlanInstanceCount'; Title = ''; Severity = ''; ResourceName = 'other'; Reason = ''; Recommendation = ''; Link = ''; ResourceId = '/subscriptions/x/resourceGroups/y/providers/Microsoft.Web/sites/other' }
                ) }
        }
        $psrule = @(Invoke-AACFunctionAppAssessment -View PSRule -NoDisplay)
        $psrule.RuleName | Should -Be 'Azure.AppService.MinTLS' -Because 'results for other resources are left out'
        @(Invoke-AACFunctionAppAssessment -View Finding -NoDisplay | Where-Object Source -EQ 'PSRule').Finding | Should -Be 'PSRule: Azure.AppService.MinTLS'
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Get-AACRuleData -ParameterFilter { @($ResourceType) -contains 'Microsoft.Web/sites' -and @($ResourceId).Count -eq 6 }
    }

    It 'narrows to the apps named, and says what to check when none is found' {
        @(Invoke-AACFunctionAppAssessment -SkipPSRule -Name 'func-orders-*' -NoDisplay).App | Should -Be 'func-orders-prod'
        { Invoke-AACFunctionAppAssessment -SkipPSRule -Name 'func-nothing' -NoDisplay } | Should -Throw '*No function app named*'
    }

    It 'shows the view, and writes a tabbed HTML report with an app selector and hover cards' {
        $text = (& $script:capture { Invoke-AACFunctionAppAssessment -SkipPSRule -NoPaging }).Text
        foreach ($expected in 'Function App assessment', 'func-orders-prod', 'Well-Architected') { $text | Should -BeLike "*$expected*" }
        $html = Join-Path $TestDrive 'func-report.html'
        $null = & $script:capture { Invoke-AACFunctionAppAssessment -SkipPSRule -HtmlPath $html }
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.tabs.name) | Should -Be @('Service summary', 'Apps & plans', 'Usage', 'Functions', 'Configuration', 'Networking', 'Deployment', 'Backups & connections', 'Activity Log', 'Well-Architected', 'PSRule', 'Recommendations', 'Findings')
        foreach ($t in $model.tables) { @($t.hover).Count | Should -BeGreaterThan 0 -Because "$($t.id) has a hover card" }
        "$($model.scope.key) | $($model.scope.card) | $(@($model.scope.values) -join ', ')" | Should -Be 'App | service | func-ingest-flex, func-orders-prod, func-reports-dev'
    }

    It 'writes a PDF report' -Skip:(-not $script:canWritePdf) {
        $pdf = Join-Path $TestDrive 'func.pdf'
        $null = & $script:capture { Invoke-AACFunctionAppAssessment -SkipPSRule -PdfPath $pdf }
        (Get-Item -LiteralPath $pdf).Length | Should -BeGreaterThan 1000
    }
}
