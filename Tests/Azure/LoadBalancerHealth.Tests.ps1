<#
    Unit tests for Get-AACLoadBalancerHealth: made-up load balancers,
    Application Gateways and Traffic Manager profiles with their metrics
    (Fixtures\ContosoLoadBalancer.ps1) - backend health from the probe and
    host metrics, balancer health, the findings - the queries, and the
    command with Resource Graph and Azure Monitor faked.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    . (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Fixtures/ContosoLoadBalancer.ps1')
    $script:f = Get-AACContosoLoadBalancer
    $script:build = { param([hashtable] $Metric = $script:f.Metric) $f = $script:f; InModuleScope 'Azure.Admin.Console' -Parameters @{ F = $f; M = $Metric } { param($F, $M) ConvertTo-AACLoadBalancerHealth -Read $F.Read -Metric $M -SubscriptionName $F.Names } }
    $script:capture = {
        param([scriptblock] $Render)
        $real = [Spectre.Console.AnsiConsole]::Console
        $buffer = [System.IO.StringWriter]::new()
        $settings = [Spectre.Console.AnsiConsoleSettings]::new()
        $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer)
        $settings.Ansi = [Spectre.Console.AnsiSupport]::No
        $settings.Enrichment.UseDefaultEnrichers = $false
        $console = [Spectre.Console.AnsiConsole]::Create($settings)
        $console.Profile.Width = 200
        $console.Profile.Capabilities.Unicode = $false
        try { [Spectre.Console.AnsiConsole]::Console = $console; $output = @(& $Render) }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
}

Describe 'Azure Admin Console - load balancer health' {
    BeforeAll { $script:r = & $script:build }

    It 'rates every backend from its latest probe or host count, the failing first' {
        @($script:r.Backends | ForEach-Object { "$($_.Health) | $($_.Balancer) | $($_.Pool) | $($_.Backend) | $($_.Address) | $($_.Availability)" }) | Should -Be @(
            'Unhealthy | agw-v2 | empty | (empty) |  | '
            'Unhealthy | lb-api | pool | vm-api | 10.0.1.4 | 0'
            'Unhealthy | lb-web | pool | vm-web2 | 10.0.0.5 | 0'
            'Unhealthy | tm-global | Priority | ep-us | us.contoso.com | '
            'Partial | agw-v2 | app | 2 backend(s) via settings1 |  | 50'
            'Not measured | lb-old | pool | vm-old-nic | 10.0.2.4 | '
            'Disabled | tm-global | Priority | ep-asia | asia.contoso.com | '
            'Healthy | lb-web | pool | vm-web1 | 10.0.0.4 | 100'
            'Healthy | tm-global | Priority | ep-eu | eu.contoso.com | '
        )
        ($script:r.Backends | Where-Object Backend -EQ 'vm-web1').Probe | Should -Be 'Http 80 /health'
        $script:r.Backends[0].PSObject.TypeNames | Should -Contain 'AAC.LoadBalancerBackend'
    }

    It 'rates each balancer, with its data path and issues' {
        @($script:r.Balancers | ForEach-Object { "$($_.Health) | $($_.Balancer) | $($_.Backends) | $($_.Unhealthy) | $($_.DataPath) | $($_.Issues)" }) | Should -Be @(
            'Unhealthy | lb-api | 1 | 1 | 80 | pool pool down, data path 80%'
            'Degraded | agw-v2 | 2 | 2 |  | app partly unhealthy'
            'Degraded | lb-web | 2 | 1 | 100 | 1 backend(s) failing'
            'Degraded | tm-global | 2 | 1 |  | 1 endpoint(s) degraded'
            'Unknown | lb-old | 1 | 0 |  | Basic SKU retired'
        )
    }

    It 'lists the findings, each with what to do' {
        @($script:r.Findings | ForEach-Object { "$($_.Severity) | $($_.Category) | $($_.Resource) | $($_.Finding)" }) | Should -Be @(
            'High | Configuration | agw-v2 | Empty backend pool'
            'High | Health | lb-api | Data path availability below 100%'
            'High | Health | lb-api | Every backend in the pool is down'
            'High | Retirement | lb-old | Basic Load Balancer (retired)'
            'Medium | Configuration | lb-api | Load-balancing rule without a health probe'
            'Medium | Health | agw-v2 | Unhealthy backend hosts'
            'Medium | Health | lb-web | Backends failing their health probe'
            'Medium | Health | tm-global | Traffic Manager endpoints degraded'
            'Medium | Resilience | agw-v2 | Application Gateway with one instance'
            'Low | Resilience | lb-api | Backend pool with a single backend'
            'Low | Resilience | lb-old | Backend pool with a single backend'
        )
        ($script:r.Findings | Where-Object Finding -EQ 'Backends failing their health probe').Detail | Should -Be 'Pool pool of lb-web: vm-web2 (0%) of 2 backend(s).'
        "$($script:r.Stats.Balancers) $($script:r.Stats.Unhealthy) $($script:r.Stats.Degraded) $($script:r.Stats.Down) $($script:r.Stats.Retired)" | Should -Be '5 1 3 5 1'
    }

    It 'says Not measured without metrics, and Unknown when they failed' {
        $none = & $script:build @{}
        @($none.Backends | Where-Object Kind -EQ 'Load balancer' | ForEach-Object Health | Select-Object -Unique) | Should -Be @('Not measured')
        $failed = & $script:build @{ ($script:f.Read.Rows.loadBalancers[0].id) = @{ Error = 'denied'; Dip = $null; Vip = $null; Hosts = $null } }
        @($failed.Backends | Where-Object Balancer -EQ 'lb-web' | ForEach-Object Health | Select-Object -Unique) | Should -Be @('Unknown')
    }
}

Describe 'Azure Admin Console - load balancer queries' {
    It 'reads balancers, gateways, profiles and the backend NICs' {
        $q = InModuleScope 'Azure.Admin.Console' { Get-AACLoadBalancerQuery -ResourceGroupName 'rg-net' }
        @($q.Keys) | Should -Be @('loadBalancers', 'appGateways', 'trafficManager', 'backendNics')
        $q.loadBalancers | Should -Match ([regex]::Escape("resourceGroup in~ ('rg-net')"))
        $q.backendNics | Should -Not -Match 'rg-net'
    }
}

Describe 'Azure Admin Console - Get-AACLoadBalancerHealth' {
    BeforeEach {
        $script:uris = [System.Collections.Generic.List[string]]::new()
        $script:queries = [System.Collections.Generic.List[object]]::new()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            if ($Query.Contains('subscriptions')) { return @{ Rows = @{ subscriptions = @(@{ subscriptionId = $script:f.Subscription; name = 'sub-prod'; state = 'Enabled' }) }; Errors = @{} } }
            $script:queries.Add(@($Query.Keys))
            $rows = @{}
            foreach ($k in $Query.Keys) { $rows[$k] = $script:f.Read.Rows[$k] }
            @{ Errors = @{}; Rows = $rows }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $answers = @{}
            foreach ($u in $Uri) {
                $script:uris.Add($u)
                $id = ($u -split '/providers/Microsoft.Insights/', 2)[0]
                $part = if ($u -match 'DipAvailability') { 'Dip' } elseif ($u -match 'VipAvailability') { 'Vip' } else { 'Hosts' }
                $body = if ($script:f.Metric.Contains($id)) { $script:f.Metric[$id][$part] } else { @{ value = @() } }
                $answers[$u] = @{ Status = 200; Error = $null; Body = $body; Items = $null }
            }
            $answers
        }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.example'; TenantId = 't-1'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1) } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'reads the metrics of Standard load balancers and v2 gateways only, and filters by health, kind and name' {
        @(Get-AACLoadBalancerHealth -NoDisplay).Count | Should -Be 9
        $script:uris.Count | Should -Be 5 -Because 'lb-web and lb-api twice (probe, data path), agw-v2 once; not lb-old (Basic) or lb-other (out of scope)'
        ($script:uris | Where-Object { $_ -match 'DipAvailability' } | Select-Object -First 1) | Should -Match ([regex]::Escape('&$filter=BackendIPAddress%20eq%20%27%2A%27'))
        @(Get-AACLoadBalancerHealth -Health NotMeasured -NoDisplay).Backend | Should -Be @('vm-old-nic')
        @(Get-AACLoadBalancerHealth -Kind TrafficManager -NoDisplay).Backend | Should -Be @('ep-us', 'ep-asia', 'ep-eu')
        $script:queries[-1] | Should -Be @('trafficManager') -Because 'only what was asked for is read'
        @(Get-AACLoadBalancerHealth -Name 'lb-w*' -NoDisplay).Backend | Should -Be @('vm-web2', 'vm-web1')
    }

    It 'reads no metrics with -SkipMetrics' {
        $null = Get-AACLoadBalancerHealth -SkipMetrics -NoDisplay
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -Times 0
    }

    It 'shows the balancers at the prompt, in characters any console can show' {
        $text = (& $script:capture { Get-AACLoadBalancerHealth -NoPaging }).Text
        foreach ($expected in 'Azure Admin Console :: Load balancer health', '5 balancer(s): 1 unhealthy, 3 degraded; 5 backend(s) failing their health check', 'Balancers (5)', 'Findings (11)', 'Backends (9)', 'vm-web2') { $text | Should -Match ([regex]::Escape($expected)) }
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ }) | Should -BeNullOrEmpty
        }
    }

    It 'writes the backends to CSV and an HTML report' {
        $csv = Join-Path $TestDrive 'lb.csv'
        $html = Join-Path $TestDrive 'lb.html'
        $null = & $script:capture { Get-AACLoadBalancerHealth -CsvPath $csv -HtmlPath $html }
        @(Import-Csv -LiteralPath $csv)[0].Balancer | Should -Be 'agw-v2'
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.tables.id) | Should -Be @('balancers', 'findings', 'backends')
    }
}
