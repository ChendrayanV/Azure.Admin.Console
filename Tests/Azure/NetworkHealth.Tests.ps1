<#
    Unit tests for Get-AACNetworkHealth: ExpressRoute circuits and gateways,
    VPN gateways, connections and tunnels, Azure Firewall and NAT gateway -
    availability, % of capacity, drops, limits, Resource Health, findings
    and the heat map - with Resource Graph and Azure Monitor mocked
    (Fixtures\ContosoNetworkHealth.ps1).
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
    $script:canWritePdf = $IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4'
}

BeforeAll {
    . (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Fixtures/ContosoNetworkHealth.ps1')
    $script:net = Get-AACContosoNetworkHealth
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
    $script:keyOf = @{ BgpAvailability = 'bgp'; BitsInPerSecond = 'bits'; QosDropBitsInPerSecond = 'qos'; ExpressRouteGatewayCpuUtilization = 'perf'; ExpressRouteGatewayCountOfRoutesAdvertisedToPeer = 'routes'; AverageBandwidth = 'bw'; TunnelAverageBandwidth = 'tunnels'; BgpPeerStatus = 'bgp'; P2SConnectionCount = 'p2s'; FirewallHealth = 'fw'; FirewallLatencyPng = 'latency'; DatapathAvailability = 'nat' }
}

Describe 'Azure Admin Console - Get-AACNetworkHealth' {
    BeforeEach {
        $script:queries = $null
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Resolve-AACScope -MockWith { $script:net.Scope }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $script:queries = $Query
            $rows = @{}; foreach ($n in @($Query.Keys)) { $rows[$n] = @($script:net.Graph[$n]) }; @{ Rows = $rows; Errors = @{} }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $out = @{}
            foreach ($u in $Uri) {
                if ($u -match '^(.+)/providers/Microsoft\.ResourceHealth/availabilityStatuses/current') {
                    $target = $Matches[1]
                    $status = @($script:net.Graph.health | Where-Object { $_.target -eq $target })
                    $out[$u] = if ($status.Count) { @{ Status = 200; Body = @{ properties = @{ availabilityState = $status[0].state; reasonType = $status[0].reason; summary = $status[0].summary; occuredTime = $status[0]['since'] } }; Items = $null; Error = '' } } else { @{ Status = 404; Body = $null; Items = $null; Error = 'Not found' } }
                    continue
                }
                $resource = ($u -split '/providers/Microsoft.Insights/metrics', 2)[0]
                $first = ([System.Uri]::UnescapeDataString(($u -split 'metricnames=')[1]) -split '[,&]')[0]
                $key = "$resource|$($script:keyOf[$first])"
                $out[$u] = if ($script:net.Metrics.Contains($key)) { @{ Status = 200; Body = @{ value = $script:net.Metrics[$key] }; Items = $null; Error = '' } } else { @{ Status = 400; Body = $null; Items = $null; Error = 'Failed to find metric configuration.' } }
            }
            $out
        }
    }

    It 'measures each component: availability, % of capacity, drops, limits, Resource Health' {
        $c = @(Get-AACNetworkHealth -NoDisplay)
        $one = { param($Name) $c | Where-Object Name -EQ $Name }
        "$((& $one 'er-london').Availability) $((& $one 'er-london').PeakUtilization) $((& $one 'er-london').Drops) $((& $one 'er-london').Health)" | Should -Be '99.5 90 1000 Available'
        (& $one 'ergw-hub').CapacityUsed | Should -Be 95 -Because 'routes advertised 950 of 1,000 is the highest of CPU 85, pps 50 and routes'
        "$((& $one 'vpngw-hub').PeakUtilization) $((& $one 'vpngw-hub').Availability)" | Should -Be '92.3 0' -Because '75 MB/s is 600 Mbps of 650, and one BGP peer was down'
        "$((& $one 'afw-hub').Availability) $((& $one 'afw-hub').CapacityUsed) $((& $one 'afw-hub').PeakUtilization) $((& $one 'afw-hub').Health)" | Should -Be '95 97 10 Degraded'
        (& $one 'natgw-app').CapacityUsed | Should -Be 93 -Because '60,000 of 64,512 ports'
        "$((& $one 'conn-berlin').Availability) $((& $one 'conn-paris').Drops)" | Should -Be '0 15'
        (& $one 'conn-paris').Component | Should -Be 'IPsec connection'
        $c.Count | Should -Be 9
        $c[0].PSObject.TypeNames | Should -Contain 'AAC.NetworkHealth'
    }

    It 'finds what is down, near a limit or not resilient' {
        $f = @(Get-AACNetworkHealth -View Finding -NoDisplay)
        $has = { param($Severity, $Name, $Finding) @($f | Where-Object { $_.Severity -eq $Severity -and $_.Name -eq $Name -and $_.Finding -like $Finding }).Count }
        & $has 'High' 'er-london' 'Bgp availability below 100%' | Should -Be 1
        & $has 'Medium' 'er-london' 'Link at 90% of bandwidth' | Should -Be 1
        & $has 'Medium' 'er-london' 'Traffic on one link' | Should -Be 1
        & $has 'Medium' 'er-london' 'Packets dropped (QoS)' | Should -Be 1
        & $has 'High' 'er-idle' 'Circuit not provisioned by the provider' | Should -Be 1
        & $has 'High' 'ergw-hub' 'Routes advertised to the peer near the limit' | Should -Be 1
        & $has 'Medium' 'ergw-hub' 'Gateway CPU at 85%' | Should -Be 1
        & $has 'Medium' 'ergw-hub' 'Gateway not zone-redundant' | Should -Be 1
        & $has 'High' 'vpngw-hub' 'BGP peer down' | Should -Be 1
        & $has 'Medium' 'vpngw-hub' 'Gateway bandwidth at 92% of the SKU' | Should -Be 1
        & $has 'Medium' 'vpngw-hub' 'VPN gateway not active-active' | Should -Be 1
        & $has 'High' 'conn-berlin' 'Connection not connected' | Should -Be 1
        & $has 'Low' 'conn-berlin' 'Static routing (no BGP)' | Should -Be 1
        & $has 'Medium' 'conn-paris' 'Tunnel packets dropped' | Should -Be 1
        & $has 'High' 'afw-hub' 'SNAT ports at 97%' | Should -Be 1
        & $has 'Medium' 'afw-hub' 'Firewall health below 100%' | Should -Be 1
        & $has 'Medium' 'afw-hub' 'Resource Health: Degraded' | Should -Be 1
        & $has 'Medium' 'natgw-app' 'SNAT connections at 93% of capacity' | Should -Be 1
        @($f | Where-Object Name -EQ 'conn-er') | Should -BeNullOrEmpty
        $f[0].Severity | Should -Be 'High'
    }

    It 'says when: the peak, the first and last time seen, and since when Resource Health has said so' {
        $f = @(Get-AACNetworkHealth -View Finding -NoDisplay)
        $when = { param($Name, $Finding) ($f | Where-Object { $_.Name -eq $Name -and $_.Finding -like $Finding }).When }
        & $when 'er-london' 'Bgp availability below 100%' | Should -Be 'at 2026-10-15 09:00 UTC'
        & $when 'er-london' 'Link at 90% of bandwidth' | Should -Be 'peak at 2026-10-15 14:00 UTC'
        & $when 'vpngw-hub' 'BGP peer down' | Should -Be '2026-10-15 08:00 to 2026-10-16 07:00 UTC'
        & $when 'afw-hub' 'SNAT ports at 97%' | Should -Be 'peak at 2026-10-15 18:30 UTC'
        & $when 'afw-hub' 'Resource Health: Degraded' | Should -Be 'since 2026-10-15 18:00 UTC'
        ($f | Where-Object Finding -EQ 'BGP peer down').FirstSeen | Should -Be ([datetime]::new(2026, 10, 15, 8, 0, 0, [System.DateTimeKind]::Utc))
        $c = @(Get-AACNetworkHealth -NoDisplay)
        ($c | Where-Object Name -EQ 'er-london').PeakAt | Should -Be ([datetime]::new(2026, 10, 15, 14, 0, 0, [System.DateTimeKind]::Utc))
        ($c | Where-Object Name -EQ 'afw-hub').HealthSince | Should -Be ([datetime]::new(2026, 10, 15, 18, 0, 0, [System.DateTimeKind]::Utc))
        $text = (& $script:capture { Get-AACNetworkHealth -NoPaging }).Text
        $text | Should -Match 'Period: \d{4}-\d{2}-\d{2} \d{2}:\d{2} to \d{4}-\d{2}-\d{2} \d{2}:\d{2} UTC, every 1 h'
        $text | Should -BeLike '*Generated:*UTC*'
    }

    It 'reads only the components asked for' {
        $c = @(Get-AACNetworkHealth -Component Firewall -NoDisplay)
        @($script:queries.Keys) | Should -Be @('firewalls')
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -ParameterFilter { @($Uri | Where-Object { $_ -like '*/azurefirewalls/afw-hub/providers/Microsoft.ResourceHealth/availabilityStatuses/current*' }).Count -eq 1 }
        @($c.Name) | Should -Be @('afw-hub')
        $vpn = @(Get-AACNetworkHealth -Component Vpn -NoDisplay)
        @($vpn | Where-Object Component -EQ 'ExpressRoute gateway') | Should -BeNullOrEmpty
        ($vpn | Where-Object Name -EQ 'vpngw-hub') | Should -Not -BeNullOrEmpty
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -ParameterFilter { @($Uri | Where-Object { $_ -match 'ConnectionName' }).Count -eq 1 }
    }

    It 'shows the heat map and findings at the prompt, in characters any console can show' {
        $text = (& $script:capture { Get-AACNetworkHealth -NoPaging }).Text
        foreach ($expected in 'Network components by signal', 'Utilization', 'er-london', 'afw-hub', 'BGP peer down', 'Findings') { $text | Should -BeLike "*$expected*" }
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ }) | Should -BeNullOrEmpty
        }
    }

    It 'writes CSV by -View and an HTML report with the heat map' {
        $csv = Join-Path $TestDrive 'net.csv'
        $html = Join-Path $TestDrive 'net.html'
        $null = & $script:capture { Get-AACNetworkHealth -View Finding -CsvPath $csv -HtmlPath $html }
        @(Import-Csv -LiteralPath $csv)[0].PSObject.Properties.Name | Should -Contain 'Recommendation'
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.heatmaps[0].columns) | Should -Be @('Availability', 'Utilization', 'Drops', 'Capacity', 'Health')
        @($model.tables.id) | Should -Be @('components', 'findings')
    }

    It 'writes a PDF report' -Skip:(-not $script:canWritePdf) {
        $pdf = Join-Path $TestDrive 'net.pdf'
        $null = & $script:capture { Get-AACNetworkHealth -PdfPath $pdf }
        (Get-Item -LiteralPath $pdf).Length | Should -BeGreaterThan 1000
    }
}
