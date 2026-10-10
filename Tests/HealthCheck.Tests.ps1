<#
    Unit tests for Invoke-AACHealthCheck: the checks built from probes and
    reads (availability, latency, certificates, private databases, queues,
    Resource Health, Service Health, alerts, the SLA), the real TCP probe
    against local listeners, and the command with the probes, Resource
    Graph and Resource Manager faked.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    $script:now = [datetime]'2026-10-09T12:00:00Z'
    $attempts = { param([bool[]] $Ok, [int[]] $Ms) @(for ($i = 0; $i -lt $Ok.Count; $i++) { @{ Ok = $Ok[$i]; Status = $(if ($Ok[$i]) { 200 } else { 503 }); LatencyMs = $Ms[$i]; Error = $(if ($Ok[$i]) { '' } else { 'HTTP 503 Service Unavailable' }) } }) }
    $script:input = @{
        Endpoint     = @(
            @{ Key = 'shop'; Name = 'shop'; Kind = 'Http'; Uri = 'https://shop.contoso.example/health'; Tier = 'Critical' }
            @{ Key = 'api'; Name = 'api'; Kind = 'Http'; Uri = 'https://api.contoso.example/'; Tier = 'API' }
            @{ Key = 'docs'; Name = 'docs'; Kind = 'Http'; Uri = 'https://docs.contoso.example/'; Tier = 'Web' }
            @{ Key = 'sql'; Name = 'sql-prod'; Kind = 'Tcp'; Host = 'sql-prod.database.windows.net'; Port = 1433; Tier = 'Data'; Private = $true }
            @{ Key = 'pg'; Name = 'pg-prod'; Kind = 'Tcp'; Host = 'pg-prod.postgres.database.azure.com'; Port = 5432; Tier = 'Data' }
        )
        ProbeResult  = @{
            shop = & $attempts @($true, $false, $true) @(120, 0, 140)
            api  = & $attempts @($true, $true, $true, $true) @(2500, 2600, 2400, 3000)
            docs = & $attempts @($true, $true) @(80, 90)
            sql  = @(@{ Ok = $false; Status = 0; LatencyMs = 10000; Error = 'no answer within 10 seconds' })
            pg   = @(@{ Ok = $true; Status = 0; LatencyMs = 35; Error = '' })
        }
        Certificate  = @{ shop = @{ NotAfter = $script:now.AddDays(200) }; api = @{ NotAfter = $script:now.AddDays(12) }; docs = @{ NotAfter = $script:now.AddDays(-3) } }
        Queue        = @(@{ Namespace = 'sb-prod'; Queue = 'orders'; Status = 'Active'; Active = 12; DeadLetter = 4; ResourceId = 'q1' }, @{ Namespace = 'sb-prod'; Queue = 'mail'; Status = 'Active'; Active = 5; DeadLetter = 0; ResourceId = 'q2' }, @{ Namespace = 'sb-prod'; Queue = 'legacy'; Status = 'Disabled'; Active = 0; DeadLetter = 0; ResourceId = 'q3' })
        HealthStatus = @(@{ resourceId = '/subscriptions/s/resourceGroups/rg/providers/Microsoft.Compute/virtualMachines/vm-1'; state = 'Available' }, @{ resourceId = '/subscriptions/s/resourceGroups/rg/providers/Microsoft.Compute/virtualMachines/vm-2'; state = 'Unavailable'; summary = 'The VM stopped' })
        ServiceEvent = @(@{ trackingId = 'TRK-1'; title = 'Storage - West Europe'; eventType = 'ServiceIssue' })
        Alert        = @(@{ name = 'CPU over 90%'; severity = 'Sev2'; fired = '2026-10-09T11:00:00Z'; target = '/subscriptions/s/resourcegroups/rg/providers/microsoft.compute/virtualmachines/vm-1' })
        Now          = $script:now
    }
    $script:check = { param([hashtable] $More = @{}) $in = @{} + $script:input + $More; InModuleScope 'Azure.Admin.Console' -Parameters @{ I = $in } { param($I) ConvertTo-AACHealthCheck @I } }
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
        $console.Profile.Capabilities.Unicode = $false
        try { [Spectre.Console.AnsiConsole]::Console = $console; $output = @(& $Render) }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
}

Describe 'Azure Admin Console - health checks' {
    BeforeAll { $script:r = & $script:check }

    It 'rates each endpoint by availability, latency and certificate - failures first' {
        $byName = @{}; foreach ($c in $script:r.Checks) { $byName[$c.Check] = $c }
        "$($byName['shop'].Status) $($byName['shop'].Severity) $($byName['shop'].Availability)" | Should -Be 'Failed Critical 66.67' -Because 'one in three failed, on the critical tier'
        $byName['shop'].Detail | Should -Be '66.67% available (2 of 3), under the 99.9% target'
        "$($byName['api'].Status) $($byName['api'].LatencyP95) $($byName['api'].CertificateDays)" | Should -Be 'Warning 3000 12'
        $byName['api'].Detail | Should -Be 'Slow: 95% of answers within 3000 ms (over 2000 ms); the TLS certificate expires in 12 day(s)'
        $byName['docs'].Status | Should -Be 'Failed'
        $byName['docs'].Detail | Should -BeLike '*the TLS certificate expired 3 day(s) ago*'
        $script:r.Checks[0].PSObject.TypeNames | Should -Contain 'AAC.HealthCheck'
        @($script:r.Checks | Select-Object -First 1).Status | Should -Be 'Failed'
    }

    It 'expects a private database to be out of reach from here, but not a public one' {
        $sql = $script:r.Checks | Where-Object Check -EQ 'sql-prod'
        "$($sql.Status) | $($sql.Detail)" | Should -BeLike "Warning | Not reachable from here: no answer within 10 seconds - it allows private access only*"
        ($script:r.Checks | Where-Object Check -EQ 'pg-prod').Detail | Should -Be 'Connected in 35 ms'
    }

    It 'checks the queues, Resource Health, Service Health and alerts' {
        @($script:r.Checks | Where-Object Category -EQ 'Queue' | ForEach-Object { "$($_.Check) $($_.Status)" } | Sort-Object) | Should -Be @('sb-prod/legacy Failed', 'sb-prod/mail Success', 'sb-prod/orders Warning')
        ($script:r.Checks | Where-Object Check -EQ 'sb-prod/orders').Detail | Should -Be '4 dead-lettered message(s)'
        ($script:r.Checks | Where-Object Check -EQ 'vm-2').Status | Should -Be 'Failed'
        ($script:r.Checks | Where-Object Check -EQ 'All resources').Target | Should -Be '1 of 2 available'
        ($script:r.Checks | Where-Object Category -EQ 'Service Health').Status | Should -Be 'Failed'
        ($script:r.Checks | Where-Object Category -EQ 'Alert').Status | Should -Be 'Warning'
    }

    It 'reports each endpoint against the SLA target' {
        @($script:r.Sla | ForEach-Object { "$($_.Endpoint) $($_.Availability) $($_.Met)" }) | Should -Be @('shop 66.67 No', 'api 100 Yes', 'docs 100 Yes')
        "$($script:r.Stats.Availability) $($script:r.Stats.SlaMet)/$($script:r.Stats.Endpoints)" | Should -Be '88.89 2/3'
        (& $script:check @{ SlaTarget = 60 }).Sla[0].Met | Should -Be 'Yes'
    }

    It 'connects over TCP for real: an open port answers, a closed one doesn''t' {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $listener.Start()
        try {
            $open = $listener.LocalEndpoint.Port
            $closed = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0); $closed.Start(); $closedPort = $closed.LocalEndpoint.Port; $closed.Stop()
            $result = InModuleScope 'Azure.Admin.Console' -Parameters @{ O = $open; C = $closedPort } { param($O, $C) Invoke-AACEndpointProbe -Probe @(@{ Key = 'open'; Kind = 'Tcp'; Host = '127.0.0.1'; Port = $O; TimeoutSeconds = 5 }, @{ Key = 'closed'; Kind = 'Tcp'; Host = '127.0.0.1'; Port = $C; TimeoutSeconds = 5 }) -Round 2 -IntervalSeconds 0 }
            @($result['open'].Ok) | Should -Be @($true, $true)
            @($result['closed'].Ok) | Should -Be @($false, $false)
            $result['closed'][0].Error | Should -Not -BeNullOrEmpty
        }
        finally { $listener.Stop() }
    }
}

Describe 'Azure Admin Console - Invoke-AACHealthCheck' {
    BeforeEach {
        $script:probed = $null
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACTlsCertificate -MockWith { @{ NotAfter = [datetime]::UtcNow.AddDays(90); Subject = "CN=$HostName"; Issuer = 'CN=Test'; Error = '' } }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACEndpointProbe -MockWith {
            $script:probed = @($Probe)
            $result = @{}
            foreach ($p in $Probe) { $result[[string]$p.Key] = @(1..$Round | ForEach-Object { @{ Ok = $true; Status = 200; LatencyMs = 100; Error = '' } }) }
            $result
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            if ($Query.Contains('subscriptions')) { return @{ Rows = @{ subscriptions = @(@{ subscriptionId = '11111111-1111-1111-1111-111111111111'; name = 'sub-prod'; state = 'Enabled'; chain = @() }) }; Errors = @{} } }
            $script:queries = $Query
            @{ Rows = @{
                    health    = $script:input.HealthStatus; events = @(); alerts = @(); services = @(@{ id = '/subscriptions/s/resourceGroups/rg/providers/Microsoft.ServiceBus/namespaces/sb-prod'; name = 'sb-prod' })
                    web       = @(@{ id = 'w1'; name = 'app-web'; type = 'microsoft.web/sites'; host = 'app-web.azurewebsites.net' }, @{ id = 'a1'; name = 'apim-prod'; type = 'microsoft.apimanagement/service'; host = 'apim-prod.azure-api.net' })
                    databases = @(@{ id = 'd1'; name = 'sql-prod'; type = 'microsoft.sql/servers'; host = 'sql-prod.database.windows.net'; publicAccess = 'Disabled' })
                }; Errors = @{}
            }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $answers = @{}
            foreach ($u in $Uri) { $answers[$u] = @{ Status = 200; Error = ''; Items = @(@{ id = 'q1'; name = 'orders'; properties = @{ status = 'Active'; countDetails = @{ activeMessageCount = 3; deadLetterMessageCount = 0 } } }) } }
            $answers
        }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.example'; TenantId = 't-1'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1) } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'discovers the endpoints and databases to probe - API Management by its status endpoint - and reads the queues' {
        $checks = @(Invoke-AACHealthCheck -Discover -IncludeDatabase -Count 2 -IntervalSeconds 0 -NoDisplay)
        @($script:probed | ForEach-Object { if ($_.Kind -eq 'Tcp') { "$($_.Host):$($_.Port) private=$($_.Private)" } else { "$($_.Uri) $($_.Tier)" } }) | Should -Be @('https://app-web.azurewebsites.net/ Web', 'https://apim-prod.azure-api.net/status-0123456789abcdef API', 'sql-prod.database.windows.net:1433 private=True')
        $script:probed[0].ExpectedStatus | Should -Be 'Below500'
        ($checks | Where-Object Category -EQ 'Queue').Check | Should -Be 'sb-prod/orders'
        @($checks | Where-Object Category -EQ 'Endpoint').Attempts | Should -Be @(2, 2)
    }

    It 'probes only what it''s given with -SkipAzure, without signing in, and says what''s missing' {
        $checks = @(Invoke-AACHealthCheck -SkipAzure -Uri 'https://shop.contoso.example/health' -Endpoint @{ Name = 'Checkout'; Uri = 'https://shop.contoso.example/checkout'; Tier = 'Critical'; Contains = 'ok' } -Count 1 -NoDisplay)
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -Times 0 -Exactly
        @($script:probed.Name) | Should -Be @('shop.contoso.example/health', 'Checkout')
        $script:probed[1].Contains | Should -Be 'ok'
        @($checks.Status) | Should -Be @('Success', 'Success')
        { Invoke-AACHealthCheck -SkipAzure -NoDisplay } | Should -Throw '*Nothing to check*'
        { Invoke-AACHealthCheck -SkipAzure -Discover -Uri 'https://x.example' -NoDisplay } | Should -Throw '*leave out -SkipAzure*'
    }

    It 'shows the checks at the prompt and writes the SLA report' {
        $text = (& $script:capture { Invoke-AACHealthCheck -Discover -Count 1 -NoPaging }).Text
        foreach ($expected in 'Azure Admin Console :: Health check', 'x 5 check(s): 1 failed', 'met the SLA', 'Checks (5)', 'x Failed', 'vm-2', 'SLA (2)') { $text | Should -Match ([regex]::Escape($expected)) }
        $html = Join-Path $TestDrive 'health.html'
        $null = & $script:capture { Invoke-AACHealthCheck -Discover -Count 1 -HtmlPath $html }
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.tables.id) | Should -Be @('checks', 'sla')
    }
}
