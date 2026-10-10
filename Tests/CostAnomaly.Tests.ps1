<#
    Unit tests for Get-AACCostAnomaly: the detection over made-up Contoso
    daily costs (Fixtures\ContosoCost.ps1) - spikes, new spend, drops,
    trends, the forecast and the benchmark - the resources behind an
    anomaly, and the command with Cost Management and Resource Graph faked:
    the queries, root cause, the view and the reports.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
    $script:canWritePdf = $IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4'
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoCost.ps1')
    $script:f = Get-AACContosoCost
    $script:detect = {
        param([hashtable] $More = @{})
        $f = $script:f
        InModuleScope 'Azure.Admin.Console' -Parameters @{ F = $f; M = $More } {
            param($F, $M)
            ConvertTo-AACCostAnomaly -Cost $F.Cost -SubscriptionName $F.Names -End $F.End -Days 60 @M
        }
    }
    $script:capture = {
        param([scriptblock] $Render)
        $real = [Spectre.Console.AnsiConsole]::Console
        $buffer = [System.IO.StringWriter]::new()
        $settings = [Spectre.Console.AnsiConsoleSettings]::new()
        $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer)
        $settings.Ansi = [Spectre.Console.AnsiSupport]::No
        $settings.Enrichment.UseDefaultEnrichers = $false
        $console = [Spectre.Console.AnsiConsole]::Create($settings)
        $console.Profile.Width = 180
        $console.Profile.Capabilities.Unicode = $false
        try { [Spectre.Console.AnsiConsole]::Console = $console; $output = @(& $Render) }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
}

Describe 'Azure Admin Console - cost anomaly detection' {
    BeforeAll { $script:r = & $script:detect }

    It 'finds the spike, the new spend, the drop and the steady rise - and nothing in the noise' {
        @($script:r.Anomalies | ForEach-Object { "$($_.Kind) $($_.Name) $($_.Start.ToString('MM-dd'))..$($_.End.ToString('MM-dd')) $($_.Actual) $($_.Expected)" } | Sort-Object) | Should -Be @(
            'Drop SQL Database 10-07..10-08 0 100'
            'Forecast sub-dev 10-01..10-31 1575.45 1075.17'
            'New Microsoft Defender for Cloud 10-06..10-08 45 0'
            'Spike Storage 10-06..10-08 120 60'
            'Spike Virtual Machines 10-06..10-06 400 100'
            'Trend Log Analytics 08-10..10-08 1854.65 1168.21'
        )
        @($script:r.Anomalies.Name) | Should -Not -Contain 'Bandwidth' -Because 'a few cents a day is under -MinimumImpact'
    }

    It 'rates each by its cost against the subscription''s month, most severe and largest first, with what to do' {
        @($script:r.Anomalies | ForEach-Object { "$($_.Severity) $($_.Kind) $($_.CostImpact)" }) | Should -Be @('High Forecast 500.28', 'High Spike 300', 'Medium Trend 686.44', 'Medium Spike 60', 'Medium New 45', 'Low Drop -100')
        $first = $script:r.Anomalies | Where-Object Name -EQ 'Virtual Machines'
        "$($first.Severity) $($first.Kind) $($first.Name) $($first.CostImpact) $($first.ImpactPercent)" | Should -Be 'High Spike Virtual Machines 300 300'
        $first.PSObject.TypeNames | Should -Contain 'AAC.CostAnomaly'
        $first.Finding | Should -Be 'Virtual Machines: spend spiked to 400.00 EUR on 6 Oct (expected 100.00 EUR)'
        $first.Impact | Should -Be '+300.00 EUR (+300%)'
        $first.Remediation | Should -BeLike 'Open Cost analysis for sub-prod on 6 Oct*Get-AACChangeHistory*'
        ($script:r.Anomalies | Where-Object Kind -EQ 'Drop').Severity | Should -Be 'Low'
    }

    It 'forecasts each month end from the median day, and benchmarks the subscriptions against each other' {
        $prod = $script:r.Subscriptions | Where-Object Subscription -EQ 'sub-prod'
        "$($prod.MonthToDate) $($prod.LastMonth) $($prod.GrowthPercent)" | Should -Be '1668 5100 25.99'
        $prod.Forecast | Should -Be 5555 -Because 'the median day (170) for each day left: the 505 spike day doesn''t project'
        @($script:r.Anomalies | Where-Object { $_.Kind -eq 'Forecast' }).Name | Should -Be @('sub-dev')
        $script:r.Stats.PeerGrowth | Should -Be 18.96
        @($script:r.Daily).Count | Should -Be 60
    }

    It 'is more or less sensitive as asked, and says which subscriptions couldn''t be read' {
        $low = & $script:detect @{ Sensitivity = 'Low'; MinimumImpact = 50 }
        @($low.Anomalies | Where-Object Kind -In 'Spike', 'New').Name | Should -Be @('Virtual Machines')
        $cost = @{} + $script:f.Cost
        $cost["/subscriptions/$($script:f.Dev)"] = @{ Rows = @(); Status = 'The client does not have authorization.' }
        $partial = InModuleScope 'Azure.Admin.Console' -Parameters @{ C = $cost; F = $script:f } { param($C, $F) ConvertTo-AACCostAnomaly -Cost $C -SubscriptionName $F.Names -End $F.End -Days 60 }
        $partial.Notices | Should -Be @("Cost Management couldn't be read for sub-dev: The client does not have authorization.")
        $partial.Stats.Unread | Should -Be 1
    }

    It 'names the resources whose cost rose during an anomaly' {
        $top = @(InModuleScope 'Azure.Admin.Console' -Parameters @{ R = $script:f.Resources } { param($R) Get-AACCostContributor -Rows $R -Start ([datetime]'2026-10-06') -End ([datetime]'2026-10-06') })
        @($top | ForEach-Object { "$($_.Resource) $($_.Before) $($_.During) $($_.Change)" }) | Should -Be @('vm-batch-01 20 320 300') -Because 'vm-web-01 cost the same'
    }
}

Describe 'Azure Admin Console - Get-AACCostAnomaly' {
    BeforeEach {
        $script:bodies = [System.Collections.Generic.List[object]]::new()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            @{ Rows = @{ subscriptions = @(@{ subscriptionId = $script:f.Prod; name = 'sub-prod'; state = 'Enabled'; chain = @(@{ name = 'mg-prod' }) }, @{ subscriptionId = $script:f.Dev; name = 'sub-dev'; state = 'Enabled'; chain = @(@{ name = 'mg-dev' }) }) }; Errors = @{} }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACCostBatch -MockWith {
            $script:bodies.Add(@{ Scope = @($Scope); Body = $Body })
            # The daily series, moved so they end on the command's last complete day.
            $shift = ([datetime]::UtcNow.Date.AddDays(-2) - $script:f.End).Days
            $move = { param($Row) $copy = [ordered]@{}; foreach ($p in $Row.PSObject.Properties) { $copy[$p.Name] = $p.Value }; $copy.UsageDate = [int]([datetime]::ParseExact([string]$Row.UsageDate, 'yyyyMMdd', $null).AddDays($shift).ToString('yyyyMMdd')); [pscustomobject]$copy }
            $result = @{}
            foreach ($s in $Scope) {
                $rows = if ($Body.dataset.grouping[0].name -eq 'ResourceId') { $script:f.Resources } else { $script:f.Cost[$s].Rows }
                $result[$s] = @{ Rows = @($rows | ForEach-Object { & $move $_ }); Status = 'OK' }
            }
            $result
        }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.example'; TenantId = 't-1'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1) } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'reads each subscription''s daily cost by the dimension asked for, then the resources behind the largest rises' {
        $anomalies = @(Get-AACCostAnomaly -ManagementGroupId 'mg-prod' -By ServiceName -RootCause 1 -NoDisplay)
        $script:bodies[0].Scope | Should -Be @("/subscriptions/$($script:f.Prod)") -Because 'only the subscription under mg-prod'
        $script:bodies[0].Body.dataset.granularity | Should -Be 'Daily'
        $script:bodies[0].Body.dataset.grouping[0].name | Should -Be 'ServiceName'
        $script:bodies[1].Body.dataset.grouping[0].name | Should -Be 'ResourceId'
        $script:bodies[1].Body.dataset.filter.dimensions.values | Should -Be @('Virtual Machines')
        ($anomalies | Where-Object Name -EQ 'Virtual Machines').TopResources | Should -Be 'vm-batch-01 (+300.00 a day)'
        $null = Get-AACCostAnomaly -SubscriptionId $script:f.Dev -By ResourceGroup -ResourceGroupName 'rg-app' -RootCause 0 -NoDisplay
        $script:bodies[-1].Body.dataset.grouping[0].name | Should -Be 'ResourceGroupName'
        $script:bodies[-1].Body.dataset.filter.dimensions.values | Should -Be @('rg-app')
    }

    It 'shows the anomalies at the prompt, in characters any console can show' {
        $text = (& $script:capture { Get-AACCostAnomaly -NoPaging -RootCause 0 }).Text
        foreach ($expected in 'Azure Admin Console :: Cost anomalies', 'x 6 anomaly(ies)', 'Anomalies (6)', 'x High', 'Virtual Machines', 'Subscriptions: last 7 days', 'Daily cost, last 14 days') { $text | Should -Match ([regex]::Escape($expected)) }
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ }) | Should -BeNullOrEmpty
        }
    }

    It 'writes the anomalies to CSV, and the HTML and PDF reports' {
        $csv = Join-Path $TestDrive 'anomalies.csv'
        $html = Join-Path $TestDrive 'anomalies.html'
        $pdf = Join-Path $TestDrive 'anomalies.pdf'
        $null = & $script:capture { Get-AACCostAnomaly -RootCause 0 -CsvPath $csv -HtmlPath $html -PdfPath $(if ($script:canWritePdf) { $pdf }) }
        @(Import-Csv -LiteralPath $csv).Count | Should -Be 6
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.tables.id) | Should -Be @('anomalies', 'subscriptions', 'daily')
        ($model.charts | Where-Object title -EQ 'Anomalies by kind').table | Should -Be 'anomalies'
        @($model.charts.title) | Should -Not -Contain 'Daily cost, last 14 days' -Because 'that chart is the console''s'
        $model.notices[0].text | Should -BeLike '6 anomaly(ies)*'
        if ($script:canWritePdf) { (Get-Item -LiteralPath $pdf).Length | Should -BeGreaterThan 1000 }
    }
}
