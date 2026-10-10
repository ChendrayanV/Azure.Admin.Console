<#
    Unit tests for Get-AACDependencyGraph: the graph of a made-up Contoso
    shop (Fixtures\ContosoDependency.ps1) - edges from networks, pools,
    Front Door, plans, private endpoints, identities and telemetry - blast
    radius, redundancy, single points of failure, cycles, critical
    services; and the command with Resource Graph and Log Analytics faked,
    and its Graphviz DOT file.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoDependency.ps1')
    $script:f = Get-AACContosoDependency
    $script:graph = { param([object[]] $Telemetry = $script:f.Telemetry) $f = $script:f; InModuleScope 'Azure.Admin.Console' -Parameters @{ F = $f; T = $Telemetry } { param($F, $T) ConvertTo-AACDependencyGraph -Read $F.Read -Telemetry $T -SubscriptionName $F.Names } }
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
    $script:edge = { param($Result, [string] $From, [string] $Relation) @($Result.Edges | Where-Object { $_.From -eq $From -and $_.Relation -eq $Relation } | ForEach-Object { $_.To } | Sort-Object) }
}

Describe 'Azure Admin Console - the dependency graph' {
    BeforeAll { $script:r = & $script:graph }

    It 'links what depends on what - pools, Front Door, plans, private endpoints, identities and calls' {
        & $script:edge $script:r 'lb-web' 'balances' | Should -Be @('vm-web-1', 'vm-web-2')
        & $script:edge $script:r 'agw-shop' 'routes to' | Should -Be @('app-shop', 'legacy.contoso.example', 'vm-api') -Because 'by IP, by host name, and outside Azure'
        & $script:edge $script:r 'fd-shop' 'routes to' | Should -Be @('app-shop')
        & $script:edge $script:r 'app-shop' 'hosted on' | Should -Be @('plan-shop')
        & $script:edge $script:r 'app-shop' 'has a role on' | Should -Be @('sqldb-orders', 'stshop') -Because 'a role on a container or a database is a dependency on it'
        & $script:edge $script:r 'app-shop' 'calls' | Should -Be @('api.stripe.com', 'app-api', 'sqlsrv')
        & $script:edge $script:r 'pe-sql' 'private link' | Should -Be @('sqlsrv')
        & $script:edge $script:r 'sqldb-orders' 'hosted on' | Should -Be @('sqlsrv')
        & $script:edge $script:r 'vnet-spoke' 'peered' | Should -Be @('vnet-hub')
        ($script:r.Edges | Where-Object { $_.Relation -eq 'calls' -and $_.To -eq 'sqlsrv' }).Detail | Should -Be '5,000 call(s), 1% failed (SQL)'
    }

    It 'measures each resource''s blast radius - everything that depends on it, through others too' {
        $byName = @{}; foreach ($n in $script:r.Nodes) { $byName[$n.Resource] = $n }
        "$($byName['plan-shop'].BlastRadius) $($byName['plan-shop'].Dependents) $($byName['plan-shop'].DependentsList)" | Should -Be '4 2 app-shop, app-api' -Because 'the two apps, and the gateway and Front Door in front of them'
        $byName['vnet-hub'].BlastRadius | Should -Be 0 -Because 'peering isn''t a dependency'
        $byName['vnet-spoke'].BlastRadius | Should -Be 10
        $script:r.Nodes[0].PSObject.TypeNames | Should -Contain 'AAC.DependencyNode'
    }

    It 'finds the single points of failure - but not VMs that share a pool - and the circular dependency' {
        @($script:r.Findings | Where-Object Category -EQ 'Single point of failure' | ForEach-Object { "$($_.Severity) $($_.Resource) $($_.BlastRadius)" }) | Should -Be @('High plan-shop 4', 'High sqldb-orders 4', 'High stshop 4', 'Medium vm-api 1')
        ($script:r.Findings | Where-Object Resource -EQ 'stshop').Detail | Should -Be 'Standard_LRS: one datacenter. Directly depended on by: app-shop'
        ($script:r.Findings | Where-Object Resource -EQ 'stshop').Remediation | Should -BeLike 'Move to zone-redundant storage*'
        @($script:r.Findings.Resource) | Should -Not -Contain 'vm-web-1'
        ($script:r.Findings | Where-Object Category -EQ 'Circular dependency').Finding | Should -Be 'app-api > app-shop > app-api'
        @($script:r.Findings | Where-Object Category -EQ 'Critical service' | ForEach-Object { $_.Resource }) | Should -Be @('vnet-spoke', 'sqlsrv', 'api.stripe.com', 'app-api', 'app-shop') -Because 'the single points of failure are reported already - and an external service counts'
    }

    It 'has no calls, cycles or external targets without telemetry' {
        $quiet = & $script:graph @()
        "$($quiet.Stats.Cycles) $($quiet.Stats.External)" | Should -Be '0 1' -Because 'only the gateway''s legacy host is outside Azure'
        @($quiet.Edges | Where-Object Relation -EQ 'calls').Count | Should -Be 0
    }
}

Describe 'Azure Admin Console - Get-AACDependencyGraph' {
    BeforeEach {
        $script:logQueries = [System.Collections.Generic.List[object]]::new()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            if ($Query.Contains('subscriptions')) { return @{ Rows = @{ subscriptions = @(@{ subscriptionId = $script:f.Subscription; name = 'sub-prod'; state = 'Enabled'; chain = @() }) }; Errors = @{} } }
            $script:f.Read
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACLogQueryBatch -MockWith { $script:logQueries.Add(@{ WorkspaceId = $WorkspaceId; Query = $Query }); @{ Rows = @{ dependencies = $script:f.Telemetry }; Errors = @{} } }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.example'; TenantId = 't-1'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1) } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'reads telemetry only when asked, from each Application Insights workspace' {
        $null = Get-AACDependencyGraph -NoDisplay
        $script:logQueries.Count | Should -Be 0
        $nodes = @(Get-AACDependencyGraph -IncludeTelemetry -TelemetryHours 48 -NoDisplay)
        $script:logQueries[0].WorkspaceId | Should -Be 'ws-guid'
        $script:logQueries[0].Query.dependencies | Should -BeLike 'AppDependencies | where TimeGenerated > ago(48h)*'
        @($nodes | Where-Object SinglePointOfFailure -EQ 'Yes').Count | Should -Be 4
    }

    It 'writes the graph for Graphviz, single points of failure in red' {
        $dot = Join-Path $TestDrive 'deps.dot'
        $null = Get-AACDependencyGraph -IncludeTelemetry -DotPath $dot -NoDisplay
        $text = Get-Content -LiteralPath $dot -Raw
        $text | Should -BeLike 'digraph AzureDependencies {*'
        $text | Should -Match '"/subscriptions/[^"]+/microsoft.web/serverfarms/plan-shop" \[label="plan-shop\nweb/serverfarms", fillcolor="#FEE2E2"\];'
        $text | Should -Match '-> "external:api.stripe.com" \[label="calls"\];'
        $text | Should -Match '\[label="peered", dir=both, style=dashed\];'
    }

    It 'shows the findings and the resources at the prompt' {
        $text = (& $script:capture { Get-AACDependencyGraph -IncludeTelemetry -NoPaging }).Text
        foreach ($expected in 'Azure Admin Console :: Dependency graph', '4 single point(s) of failure, 1 circular dependenc(ies)', 'Findings (', 'Single point of failure', 'Widest blast radius', 'Resources (top 15 of 22)') { $text | Should -Match ([regex]::Escape($expected)) }
    }
}
