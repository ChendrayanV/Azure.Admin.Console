<#
    Unit tests for Invoke-AACServiceBusAssessment: namespaces, every queue,
    topic and subscription's messages, health, Premium capacity, posture,
    resilience, cost, findings and the heat map - with Resource Graph,
    Resource Manager and Azure Monitor mocked (Fixtures\ContosoServiceBus.ps1).
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
    $script:canWritePdf = $IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4'
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoServiceBus.ps1')
    $script:sb = Get-AACContosoServiceBus
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

Describe 'Azure Admin Console - Invoke-AACServiceBusAssessment' {
    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Resolve-AACScope -MockWith { $script:sb.Scope }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $rows = @{}; foreach ($n in @($Query.Keys)) { $rows[$n] = @($script:sb.Graph[$n]) }; @{ Rows = $rows; Errors = @{} }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $out = @{}
            foreach ($u in $Uri) {
                $path = ($u -split '\?', 2)[0]
                if ($path -match '/providers/Microsoft\.Insights/metrics$') {
                    $resource = ($u -split '/providers/Microsoft.Insights/metrics', 2)[0]
                    $call = if ($u -match 'NamespaceCpuUsage') { 'Premium' } else { 'Core' }
                    $body = $script:sb.Metrics["$resource|$call"]
                    $out[$u] = if ($body) { @{ Status = 200; Body = $body; Items = $null; Error = '' } } else { @{ Status = 400; Body = $null; Items = $null; Error = 'Failed to find metric configuration.' } }
                    continue
                }
                $answer = $script:sb.Arm[$path]
                $out[$u] = if ($answer) { $answer } else { @{ Status = 404; Body = $null; Items = $null; Error = 'The resource was not found.' } }
            }
            $out
        }
    }

    It 'reads each namespace: health, Premium capacity and the messages waiting now' {
        $rows = @(Invoke-AACServiceBusAssessment -NoDisplay)
        $orders = $rows | Where-Object Namespace -EQ 'sb-orders'
        "$($orders.Tier) $($orders.MessagingUnits) $($orders.Queues) $($orders.Topics) $($orders.Subscriptions)" | Should -Be 'Premium 2 2 1 2'
        "$($orders.ActiveMessages) $($orders.DeadLetters) $($orders.FullestPct)" | Should -Be '12170 1503 78.1'
        "$($orders.Requests) $($orders.Throttled) $($orders.ServerErrors) $($orders.ErrorRate) $($orders.CpuMax) $($orders.MemoryMax)" | Should -Be '100000 2000 50 2.05 85 40'
        "$($orders.Network) $($orders.LocalAuth) $($orders.ZoneRedundant) $($orders.GeoDr) $($orders.LogsTo) $($orders.Encryption)" | Should -Be 'Private False True Alias law-prod Customer-managed key'
        $orders.PSObject.TypeNames | Should -Contain 'AAC.ServiceBusAssessment'
        ($rows | Where-Object Namespace -EQ 'sb-basic').MetricsError | Should -Be 'Failed to find metric configuration.'
    }

    It 'lists every queue, topic and subscription with its messages, worst first' {
        $entities = @(Invoke-AACServiceBusAssessment -View Entity -NoDisplay)
        @($entities | ForEach-Object { "$($_.Namespace) $($_.Type) $($_.Entity) $($_.ActiveMessages) $($_.DeadLetters)" }) | Select-Object -First 3 | Should -Be @(
            'sb-orders Queue orders 120 1500'
            'sb-orders Subscription events/billing 50 3'
            'sb-orders Subscription events/audit 12000 0'
        )
        $old = $entities | Where-Object Entity -EQ 'old-jobs'
        "$($old.IdleDays) $($old.MessagesExpire) $($old.DeadLetterOnExpiration)" | Should -Be ' True False'
        ($entities | Where-Object Entity -EQ 'orphan').Subscriptions | Should -Be 0
        $entities[0].PSObject.TypeNames | Should -Contain 'AAC.ServiceBusEntity'
    }

    It 'finds what to fix: messages, health, capacity, security, resilience and cost' {
        $findings = @(Invoke-AACServiceBusAssessment -View Finding -NoDisplay)
        $have = @($findings | ForEach-Object { "$($_.Severity) | $($_.Namespace) | $($_.Entity) | $($_.Finding)" })
        foreach ($expected in @(
                'High | sb-orders | orders | Dead-lettered messages'
                'Medium | sb-orders | orders | Entity filling up'
                'Medium | sb-orders | events/billing | Dead-lettered messages'
                'Medium | sb-orders | events/audit | Backlog of active messages'
                'High | sb-orders |  | Requests throttled'
                'High | sb-orders |  | CPU close to its limit'
                'High | sb-legacy |  | TLS below 1.2 accepted'
                'Medium | sb-legacy |  | SAS keys allowed (local authentication)'
                'Low | sb-legacy |  | More than one namespace-wide Manage key'
                'Medium | sb-legacy |  | Open to every network'
                'Medium | sb-legacy |  | No logs to Log Analytics'
                'Medium | sb-legacy | orphan | Topic with no subscriptions'
                'Low | sb-legacy | old-jobs | Expired messages are dropped'
                'Low | sb-legacy | old-jobs | Not used for 30 days or more'
                'Low | sb-legacy |  | No requests in the period'
                'Low | sb-basic |  | Basic tier'
            )) { $have | Should -Contain $expected }
        $have | Should -Not -Contain 'Medium | sb-orders |  | Not zone redundant'
        $have | Should -Not -Contain 'Low | sb-orders |  | No geo-disaster recovery'
        $have | Should -Not -Contain 'Medium | sb-orders |  | Memory close to its limit'
        $findings[0].Severity | Should -Be 'High'
    }

    It 'shows the heat map and findings at the prompt, in characters any console can show' {
        $text = (& $script:capture { Invoke-AACServiceBusAssessment -NoPaging }).Text
        foreach ($expected in 'Service Bus namespaces by signal', 'sb-orders', 'sb-legacy', 'Dead-lettered messages', 'Findings') { $text | Should -BeLike "*$expected*" }
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ }) | Should -BeNullOrEmpty
        }
    }

    It 'writes CSV by -View and an HTML report with the heat map and tabs' {
        $csv = Join-Path $TestDrive 'sb.csv'
        $html = Join-Path $TestDrive 'sb.html'
        $null = & $script:capture { Invoke-AACServiceBusAssessment -View Entity -CsvPath $csv -HtmlPath $html }
        @(Import-Csv -LiteralPath $csv).Count | Should -Be 7
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        $model.heatmaps[0].title | Should -Be 'Service Bus namespaces by signal'
        @($model.heatmaps[0].columns) | Should -Be @('Health', 'Capacity', 'Messages', 'Security', 'Resilience', 'Cost')
        @($model.tables.id) | Should -Be @('namespaces', 'entities', 'posture', 'findings')
    }

    It 'narrows by -Name, and writes a PDF report' -Skip:(-not $script:canWritePdf) {
        @(Invoke-AACServiceBusAssessment -Name 'sb-o*' -NoDisplay).Namespace | Should -Be @('sb-orders')
        $pdf = Join-Path $TestDrive 'sb.pdf'
        $null = & $script:capture { Invoke-AACServiceBusAssessment -PdfPath $pdf }
        (Get-Item -LiteralPath $pdf).Length | Should -BeGreaterThan 1000
    }
}
