<#
    Unit tests for Invoke-AACCosmosDBAssessment: accounts, databases,
    containers and throughput in each API, availability, rate limiting,
    storage, posture, resilience, cost, findings and the heat map - with
    Resource Graph, Resource Manager and Azure Monitor mocked
    (Fixtures\ContosoCosmosDB.ps1).
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
    $script:canWritePdf = $IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4'
}

BeforeAll {
    . (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Fixtures/ContosoCosmosDB.ps1')
    $script:cdb = Get-AACContosoCosmosDB
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

Describe 'Azure Admin Console - Invoke-AACCosmosDBAssessment' {
    BeforeEach {
        $script:asked = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Resolve-AACScope -MockWith { $script:cdb.Scope }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $rows = @{}; foreach ($n in @($Query.Keys)) { $rows[$n] = @($script:cdb.Graph[$n]) }; @{ Rows = $rows; Errors = @{} }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $out = @{}
            foreach ($u in $Uri) {
                $path = ($u -split '\?', 2)[0]
                $script:asked.Add($path)
                if ($path -match '/providers/Microsoft\.Insights/metrics$') {
                    $resource = ($u -split '/providers/Microsoft.Insights/metrics', 2)[0]
                    $first = ([System.Uri]::UnescapeDataString(($u -split 'metricnames=')[1]) -split '[,&]')[0]
                    $call = @{ TotalRequests = 'Requests'; TotalRequestUnits = 'Usage'; ServiceAvailability = 'Availability'; ServerSideLatency = 'Latency'; DataUsage = 'Storage' }[$first]
                    $body = $script:cdb.Metrics["$resource|$call"]
                    $out[$u] = if ($body) { @{ Status = 200; Body = $body; Items = $null; Error = '' } } else { @{ Status = 400; Body = $null; Items = $null; Error = 'Failed to find metric configuration.' } }
                    continue
                }
                $answer = $script:cdb.Arm[$path]
                $out[$u] = if ($answer) { $answer } else { @{ Status = 404; Body = $null; Items = $null; Error = 'The resource was not found.' } }
            }
            $out
        }
    }

    It 'reads each account: requests by status, throughput and its use, availability and storage' {
        $rows = @(Invoke-AACCosmosDBAssessment -NoDisplay)
        $orders = $rows | Where-Object Account -EQ 'cosmos-orders'
        "$($orders.Api) $($orders.CapacityMode) $($orders.Databases) $($orders.Containers) $($orders.ProvisionedRU) $($orders.AutoscaleMaxRU)" | Should -Be 'NoSQL Provisioned 1 2 0 14000'
        "$($orders.Requests) $($orders.Throttled) $($orders.ThrottleRate) $($orders.ServerErrors) $($orders.NormalizedRuMax)" | Should -Be '93520 3000 3.21 20 100'
        "$($orders.Availability) $($orders.LatencyMs) $($orders.DataGB) $($orders.IndexGB) $($orders.Documents) $($orders.RequestUnits)" | Should -Be '99.995 4 50 5 2000000 5000000'
        "$($orders.RegionCount) $($orders.AutomaticFailover) $($orders.ZoneRedundant) $($orders.Backup) $($orders.Network) $($orders.LogsTo)" | Should -Be '2 True True Continuous 7Days Private law-prod'
        $orders.PSObject.TypeNames | Should -Contain 'AAC.CosmosDBAssessment'
        $mongo = $rows | Where-Object Account -EQ 'mongo-catalog'
        "$($mongo.Api) $($mongo.CapacityMode) $($mongo.Containers) $($mongo.MetricsError)" | Should -Be 'MongoDB Serverless 1 Failed to find metric configuration.'
        @($script:asked | Where-Object { $_ -like '*mongo-catalog*throughputSettings*' }).Count | Should -Be 0 -Because 'serverless accounts have no throughput to read'
    }

    It 'lists every container with its partition key and throughput, the most RU/s first' {
        $containers = @(Invoke-AACCosmosDBAssessment -View Container -NoDisplay)
        @($containers | Select-Object -First 3 | ForEach-Object { "$($_.Account) $($_.Database) $($_.Container) $($_.PartitionKey) $($_.ThroughputMode) $($_.RU)" }) | Should -Be @(
            'cosmos-orders shop orders /customerId Autoscale 10000'
            'cosmos-orders shop carts /cartId Shared database 4000'
            'cosmos-legacy legacydb reports /id Manual 2000'
        )
        ($containers | Where-Object Container -EQ 'products') | ForEach-Object { "$($_.PartitionKey) $($_.ThroughputMode)" } | Should -Be 'sku Serverless'
        $containers.Count | Should -Be 8
    }

    It 'finds what to fix: availability, throttling, security, resilience and cost' {
        $have = @(Invoke-AACCosmosDBAssessment -View Finding -NoDisplay | ForEach-Object { "$($_.Severity) | $($_.Account) | $($_.Finding)" })
        foreach ($expected in @(
                'High | cosmos-orders | Requests rate limited (429)'
                'Medium | cosmos-legacy | Availability below 99.99%'
                'High | cosmos-legacy | TLS below 1.2 accepted'
                'High | cosmos-legacy | Open to every network'
                'Medium | cosmos-legacy | Account keys allowed (local authentication)'
                'Low | cosmos-legacy | Keys can change databases and containers'
                'Medium | cosmos-legacy | No logs to Log Analytics'
                'Low | cosmos-legacy | Defender for Azure Cosmos DB off'
                'Medium | cosmos-legacy | Single region'
                'Low | cosmos-legacy | No availability zones'
                'Low | cosmos-legacy | Periodic backup only'
                'Low | cosmos-legacy | Backups stored in one datacentre'
                'Low | cosmos-legacy | Throughput higher than needed'
                'Low | cosmos-legacy | Many small containers with their own throughput'
                'Medium | mongo-catalog | Single region'
            )) { $have | Should -Contain $expected }
        @($have | Where-Object { $_ -like '* | cosmos-orders | *' }) | Should -Be @('High | cosmos-orders | Requests rate limited (429)')
    }

    It 'shows the heat map and findings at the prompt, in characters any console can show' {
        $text = (& $script:capture { Invoke-AACCosmosDBAssessment -NoPaging }).Text
        foreach ($expected in 'Cosmos DB accounts by signal', 'cosmos-orders', 'cosmos-legacy', 'Requests rate limited (429)', 'Findings') { $text | Should -BeLike "*$expected*" }
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ }) | Should -BeNullOrEmpty
        }
    }

    It 'writes CSV by -View and an HTML report with the heat map and tabs' {
        $csv = Join-Path $TestDrive 'cdb.csv'
        $html = Join-Path $TestDrive 'cdb.html'
        $null = & $script:capture { Invoke-AACCosmosDBAssessment -View Container -CsvPath $csv -HtmlPath $html }
        @(Import-Csv -LiteralPath $csv).Count | Should -Be 8
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        $model.heatmaps[0].title | Should -Be 'Cosmos DB accounts by signal'
        @($model.heatmaps[0].columns) | Should -Be @('Availability', 'Throttling', 'Errors', 'Security', 'Resilience', 'Cost')
        @($model.tables.id) | Should -Be @('accounts', 'containers', 'posture', 'findings')
    }

    It 'narrows by -Name, and writes a PDF report' -Skip:(-not $script:canWritePdf) {
        @(Invoke-AACCosmosDBAssessment -Name 'cosmos-o*' -NoDisplay).Account | Should -Be @('cosmos-orders')
        $pdf = Join-Path $TestDrive 'cdb.pdf'
        $null = & $script:capture { Invoke-AACCosmosDBAssessment -PdfPath $pdf }
        (Get-Item -LiteralPath $pdf).Length | Should -BeGreaterThan 1000
    }
}
