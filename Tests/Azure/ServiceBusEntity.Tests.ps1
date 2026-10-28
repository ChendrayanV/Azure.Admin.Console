<#
    Unit tests for Show-AACServiceBusEntity: queues and topics read as the
    user - with a role on the namespace (metrics, wildcards, listing) or only
    on an entity (live state, -Sample) - with Resource Manager and Azure
    Monitor mocked (Fixtures\ContosoServiceBusEntity.ps1).
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
    $script:canWritePdf = $IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4'
}

BeforeAll {
    . (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Fixtures/ContosoServiceBusEntity.ps1')
    $script:sb = Get-AACContosoServiceBusEntity
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

Describe 'Azure Admin Console - Show-AACServiceBusEntity' {
    BeforeEach {
        $script:teamReads = 0
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Start-Sleep -MockWith { }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $out = @{}
            foreach ($u in $Uri) {
                $path = [System.Uri]::UnescapeDataString(($u -split '\?', 2)[0])
                if ($path -match '/providers/Microsoft\.Insights/metrics$') {
                    $resource = ($path -split '/providers/Microsoft.Insights/metrics', 2)[0]
                    $call = switch -Regex ($u) { 'IncomingMessages' { 'Traffic' } 'IncomingRequests' { 'Requests' } 'ActiveMessages' { 'Backlog' } 'CompleteMessage' { 'Settlement' } 'IncomingBytes' { 'Bytes' } 'ServerSendLatency' { 'Latency' } 'NamespaceCpuUsage' { 'Premium' } }
                    $answer = $script:sb.Metrics["$resource|$call"]
                    $out[$u] = if ($answer) { $answer } elseif ($resource -eq $script:sb.Team) { $script:sb.Forbidden } else { @{ Status = 404; Body = $null; Items = $null; Error = 'Not found.' } }
                    continue
                }
                if ($path -eq "$($script:sb.Team)/queues/team-orders") {
                    # Each read finds 10 more messages waiting.
                    $script:teamReads++
                    $out[$u] = @{ Status = 200; Body = (& $script:sb.TeamOrders (100 + 10 * $script:teamReads)); Items = $null; Error = '' }
                    continue
                }
                $answer = $script:sb.Arm[$path]
                $out[$u] = if ($answer) { $answer } elseif ($path.StartsWith($script:sb.Team)) { $script:sb.Forbidden } else { @{ Status = 404; Body = $null; Items = $null; Error = 'The resource was not found.' } }
            }
            $out
        }
    }

    Context 'with a role on the namespace' {
        It 'reads each named entity''s live state and its metrics' {
            $rows = @(Show-AACServiceBusEntity -NamespaceId $script:sb.Shared -EntityName 'orders', 'events' -NoDisplay)
            $orders = $rows | Where-Object Entity -EQ 'orders'
            "$($orders.Kind) $($orders.Status) $($orders.Access) $($orders.Metrics)" | Should -Be 'Queue Active Namespace Read'
            "$($orders.Active) $($orders.DeadLettered) $($orders.UsedPct)" | Should -Be '120 1500 83'
            "$($orders.Incoming) $($orders.Outgoing) $($orders.Throttled) $($orders.PeakActive) $($orders.AvgSendLatencyMs)" | Should -Be '600 400 5 130 10'
            $orders.ActiveTrend | Should -Not -BeNullOrEmpty
            $orders.LockDuration | Should -Be '1m'
            $orders.DefaultTtl | Should -Be 'never'
            $orders.PSObject.TypeNames | Should -Contain 'AAC.ServiceBusLookup'
            $events = $rows | Where-Object Entity -EQ 'events'
            "$($events.Kind) $($events.Active) $($events.DeadLettered) $($events.Scheduled) $($events.Subscriptions)" | Should -Be 'Topic 12050 3 4 2' -Because 'a topic''s counts are the sum of its subscriptions'''
        }

        It 'lists every queue and topic when no name is given, and matches wildcards' {
            @(Show-AACServiceBusEntity -NamespaceId $script:sb.Shared -SkipMetrics -NoDisplay | ForEach-Object Entity | Sort-Object) | Should -Be @('events', 'orders', 'payments')
            @(Show-AACServiceBusEntity -NamespaceId $script:sb.Shared -EntityName 'pay*' -SkipMetrics -NoDisplay).Entity | Should -Be 'payments'
            (Show-AACServiceBusEntity -NamespaceId $script:sb.Shared -EntityName 'payments' -SkipMetrics -NoDisplay).Metrics | Should -Be 'Skipped'
        }

        It 'summarises each metric, with the namespace''s Premium CPU, and survives a metric group the tier doesn''t publish' {
            $metrics = @(Show-AACServiceBusEntity -NamespaceId $script:sb.Shared -EntityName 'orders' -View Metric -NoDisplay)
            $incoming = $metrics | Where-Object { $_.Entity -eq 'orders' -and $_.MetricName -eq 'IncomingMessages' }
            "$($incoming.Total) $($incoming.Peak) $($incoming.Points)" | Should -Be '600 300 3'
            $incoming.Trend | Should -Be ([string]::new(@([char]0x2581, [char]0x2585, [char]0x2588)))
            ($metrics | Where-Object { $_.Entity -eq '(namespace)' -and $_.MetricName -eq 'NamespaceCpuUsage' }).Peak | Should -Be 85
            $metrics[0].PSObject.TypeNames | Should -Contain 'AAC.ServiceBusLookupMetric'
            $shown = & $script:capture { Show-AACServiceBusEntity -NamespaceId $script:sb.Shared -EntityName 'orders' -NoPaging }
            $shown.Text | Should -BeLike '*settlement metrics couldn''t be read*'
        }

        It 'returns each topic subscription' {
            $subs = @(Show-AACServiceBusEntity -NamespaceId $script:sb.Shared -EntityName 'events' -View Subscription -NoDisplay)
            @($subs | ForEach-Object { "$($_.Topic)/$($_.Subscription) $($_.Active) $($_.DeadLettered)" }) | Should -Be @('events/billing 50 3', 'events/audit 12000 0')
            ($subs | Where-Object Subscription -EQ 'billing').DeadLetterOnFilterError | Should -BeTrue
        }

        It 'finds dead-letters, a filling queue, throttling and a growing backlog' {
            $findings = @(Show-AACServiceBusEntity -NamespaceId $script:sb.Shared -EntityName 'orders', 'events', 'payments' -View Finding -NoDisplay)
            $orders = @($findings | Where-Object Entity -EQ 'orders' | ForEach-Object Finding)
            foreach ($expected in 'Dead-lettered messages', 'Entity filling up', 'Requests throttled', 'Backlog growing') { $orders | Should -Contain $expected }
            ($findings | Where-Object Entity -EQ 'events/billing').Finding | Should -Be 'Dead-lettered messages'
            ($findings | Where-Object Entity -EQ 'payments').Finding | Should -Be 'Expired messages are dropped'
            $findings[0].Severity | Should -Be 'High'
        }

        It 'says when a name isn''t a queue or a topic' {
            $row = Show-AACServiceBusEntity -NamespaceId $script:sb.Shared -EntityName 'nope' -NoDisplay
            "$($row.Status) $($row.Access)" | Should -Be 'Not found None'
            $row.Error | Should -BeLike '*No queue or topic by this name (404)*'
        }

        It 'refuses a namespace that doesn''t exist' {
            { Show-AACServiceBusEntity -NamespaceId ($script:sb.Shared -replace 'sb-shared', 'sb-gone') -EntityName 'orders' -NoDisplay } | Should -Throw '*can''t find the Service Bus namespace*'
        }
    }

    Context 'with a role on an entity only' {
        It 'reads the entity''s live state, says metrics need the namespace, and which entities have no role' {
            $rows = @(Show-AACServiceBusEntity -NamespaceId $script:sb.Team -EntityName 'team-orders', 'secret' -NoDisplay)
            $mine = $rows | Where-Object Entity -EQ 'team-orders'
            "$($mine.Kind) $($mine.Access) $($mine.Metrics) $($mine.Active)" | Should -Be 'Queue Entity No permission 110'
            $secret = $rows | Where-Object Entity -EQ 'secret'
            "$($secret.Status) $($secret.Access)" | Should -Be 'No role None'
            $access = @(Show-AACServiceBusEntity -NamespaceId $script:sb.Team -EntityName 'team-orders', 'secret' -View Access -NoDisplay)
            ($access | Where-Object Entity -EQ 'team-orders').Needed | Should -BeLike '*Monitoring Reader*namespace*'
            ($access | Where-Object Entity -EQ 'secret').Needed | Should -BeLike '*Data Receiver*'
        }

        It 'needs exact names: no listing, and wildcards are skipped with a reason' {
            { Show-AACServiceBusEntity -NamespaceId $script:sb.Team -NoDisplay } | Should -Throw '*Give the queue or topic names with -EntityName*'
            $shown = & $script:capture { Show-AACServiceBusEntity -NamespaceId $script:sb.Team -EntityName 'team-orders', 'team-*' -NoPaging }
            $shown.Text | Should -BeLike '*wildcards need read access on the namespace*'
        }

        It 'samples the live counts for a backlog trend' {
            $samples = @(Show-AACServiceBusEntity -NamespaceId $script:sb.Team -EntityName 'team-orders' -Sample 3 -SampleInterval '00:00:05' -View Sample -NoDisplay)
            @($samples | ForEach-Object Active) | Should -Be @(120, 130, 140)
            $samples[0].PSObject.TypeNames | Should -Contain 'AAC.ServiceBusLookupSample'
            Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Start-Sleep -Times 2 -Exactly
            $script:teamReads = 0
            $row = Show-AACServiceBusEntity -NamespaceId $script:sb.Team -EntityName 'team-orders' -Sample 3 -SampleInterval '00:00:05' -NoDisplay
            $row.SampledChange | Should -Be 20
            $row.ActiveTrend | Should -Not -BeNullOrEmpty
            (@(Show-AACServiceBusEntity -NamespaceId $script:sb.Team -EntityName 'team-orders' -Sample 3 -SampleInterval '00:00:05' -View Finding -NoDisplay).Finding) | Should -Contain 'Backlog growing'
        }
    }

    Context 'output' {
        It 'shows the view at the prompt' {
            $shown = & $script:capture { Show-AACServiceBusEntity -NamespaceId $script:sb.Shared -EntityName 'orders', 'events' -NoPaging }
            $shown.Text | Should -BeLike '*Service Bus entities*'
            $shown.Text | Should -BeLike '*orders*'
            $shown.Output.Count | Should -Be 0 -Because 'at the prompt the view is shown and nothing is returned'
        }

        It 'writes a tabbed HTML report and the CSV' {
            $html = Join-Path -Path $TestDrive -ChildPath 'sb.html'
            $csv = Join-Path -Path $TestDrive -ChildPath 'sb.csv'
            $null = & $script:capture { Show-AACServiceBusEntity -NamespaceId $script:sb.Shared -EntityName 'orders', 'events' -HtmlPath $html -CsvPath $csv }
            $page = Get-Content -LiteralPath $html -Raw
            foreach ($expected in 'Live state', 'Dead-letter', 'Subscriptions', 'Configuration', 'Metrics', 'What you can see') { $page | Should -BeLike "*$expected*" }
            @(Import-Csv -LiteralPath $csv).Count | Should -Be 2
        }

        It 'writes a PDF report' -Skip:(-not $script:canWritePdf) {
            $pdf = Join-Path -Path $TestDrive -ChildPath 'sb.pdf'
            $null = & $script:capture { Show-AACServiceBusEntity -NamespaceId $script:sb.Team -EntityName 'team-orders', 'secret' -PdfPath $pdf }
            (Get-Item -LiteralPath $pdf).Length | Should -BeGreaterThan 1000
        }
    }
}

Describe 'Azure Admin Console - ConvertTo-AACSparkline' {
    It 'draws the lowest value as the lowest block and the highest as the full one' {
        InModuleScope 'Azure.Admin.Console' {
            ConvertTo-AACSparkline -Value @(0, 4, 8) | Should -Be ([string]::new(@([char]0x2581, [char]0x2585, [char]0x2588)))
            ConvertTo-AACSparkline -Value @(3, 3) | Should -Be ([string]::new([char]0x2581, 2))
            ConvertTo-AACSparkline -Value @($null, 1, 2) | Should -HaveCount 1
            ConvertTo-AACSparkline -Value @() | Should -Be ''
        }
    }
}
