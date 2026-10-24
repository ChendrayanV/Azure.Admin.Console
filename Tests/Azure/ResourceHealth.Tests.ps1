<#
    Unit tests for Get-AACResourceHealth: made-up Resource Health and
    Service Health (Fixtures\ContosoHealth.ps1) - order, events, service
    issues, availability from the history - the queries, and the command
    with Resource Graph and the history calls faked.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    . (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Fixtures/ContosoHealth.ps1')
    $script:f = Get-AACContosoHealth
    $script:build = { param([hashtable] $History = @{}, [int] $Days = 7) $f = $script:f; InModuleScope 'Azure.Admin.Console' -Parameters @{ F = $f; H = $History; D = $Days } { param($F, $H, $D) ConvertTo-AACResourceHealth -Read $F.Read -SubscriptionName $F.Names -History $H -Days $D } }
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

Describe 'Azure Admin Console - resource health' {
    BeforeAll { $script:r = & $script:build }

    It 'lists every resource in scope, worst and longest down first' {
        @($script:r.Resources | ForEach-Object { "$($_.State) | $($_.Resource) | $($_.ResourceType)" }) | Should -Be @(
            'Unavailable | vm-down | microsoft.compute/virtualmachines'
            'Degraded | sql-slow | microsoft.sql/servers/databases'
            'Unknown | st-unknown | microsoft.storage/storageaccounts'
            'Available | kv-ok | microsoft.keyvault/vaults'
            'Available | vm-ok | microsoft.compute/virtualmachines'
        )
        $script:r.Resources[0].PSObject.TypeNames | Should -Contain 'AAC.ResourceHealth'
    }

    It 'says why, since when, the latest event in the window and the service issue that hit it' {
        $down = $script:r.Resources[0]
        "$($down.Reason) | $($down.Summary) | $($down.Hours) | $($down.ResourceGroup) | $($down.Subscription)" | Should -Be "Unplanned | We're sorry, your VM is unavailable. | 5 | rg-app | sub-prod"
        "$($down.LastEvent) | $($down.LastEventContext) | $($down.ServiceIssues)" | Should -Be 'VirtualMachineRestarted | Platform Initiated | TRK-1'
        ($script:r.Resources | Where-Object Resource -EQ 'vm-ok').LastEvent | Should -Be 'LiveMigrationSucceeded'
        ($script:r.Resources | Where-Object Resource -EQ 'sql-slow').LastEvent | Should -Be '' -Because 'its event is older than the window'
        ($script:r.Resources | Where-Object Resource -EQ 'sql-slow').Summary | Should -Be 'The database is slow.'
        ($script:r.Resources | Where-Object Resource -EQ 'vm-ok').Hours | Should -BeNullOrEmpty -Because 'only what is not available is counted in hours'
    }

    It 'lists the Service Health events in scope, active first, with the resources they hit' {
        @($script:r.Events | ForEach-Object { "$($_.Status) | $($_.EventType) | $($_.TrackingId) | $($_.Regions) | $($_.ImpactedResources)" }) | Should -Be @(
            'Active | Service issue | TRK-1 | West Europe | 1'
            'Resolved | Planned maintenance | TRK-2 | North Europe | 0'
        )
        $script:r.Events[0].PSObject.TypeNames | Should -Contain 'AAC.ServiceHealthEvent'
        $script:r.Events[0].Link | Should -Be 'https://app.azure.com/h/TRK-1'
        $script:r.Events[1].Summary | Should -Be 'Done.'
        "$($script:r.Stats.Unavailable) $($script:r.Stats.Degraded) $($script:r.Stats.ActiveIssues) $($script:r.Stats.Recent)" | Should -Be '1 1 1 2'
    }

    It 'works out the availability and the state changes from the history' {
        $r = & $script:build $script:f.History 1
        $down = $r.Resources[0]
        "$($down.Availability) $($down.StateChanges)" | Should -Be '70.83 3' -Because '17 of the last 24 hours were Available'
    }
}

Describe 'Azure Admin Console - resource health queries' {
    It 'narrows to the resource groups and reads the window''s events' {
        $q = InModuleScope 'Azure.Admin.Console' { Get-AACResourceHealthQuery -ResourceGroupName 'RG-App' -Days 14 }
        @($q.Keys) | Should -Be @('statuses', 'events', 'service', 'impacted')
        $q.statuses | Should -Match ([regex]::Escape("in ('rg-app')"))
        $q.service | Should -Match ([regex]::Escape('ago(14d)'))
        $q.statuses | Should -Match ([regex]::Escape("properties['title']")) -Because 'title is a KQL keyword'
    }
}

Describe 'Azure Admin Console - Get-AACResourceHealth' {
    BeforeEach {
        $script:uris = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            if ($Query.Contains('subscriptions')) { return @{ Rows = @{ subscriptions = @(@{ subscriptionId = $script:f.Subscription; name = 'sub-prod'; state = 'Enabled' }) }; Errors = @{} } }
            $script:f.Read
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $answers = @{}
            foreach ($u in $Uri) { $script:uris.Add($u); $answers[$u] = @{ Status = 200; Error = $null; Body = $null; Items = $(if ($u -like "$($script:f.VmDown)/*") { $script:f.History[$script:f.VmDown] } else { @() }) } }
            $answers
        }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.example'; TenantId = 't-1'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1) } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'filters by state, type and resource, and returns the Service Health events with -ServiceHealth' {
        @(Get-AACResourceHealth -NoDisplay).Count | Should -Be 5
        @(Get-AACResourceHealth -State Unavailable, Degraded -NoDisplay).Resource | Should -Be @('vm-down', 'sql-slow')
        @(Get-AACResourceHealth -ResourceType '*/virtualmachines' -NoDisplay).Resource | Should -Be @('vm-down', 'vm-ok')
        @([pscustomobject]@{ Id = $script:f.VmDown.ToUpperInvariant() } | Get-AACResourceHealth -NoDisplay).Resource | Should -Be @('vm-down')
        @(Get-AACResourceHealth -ServiceHealth -NoDisplay).TrackingId | Should -Be @('TRK-1', 'TRK-2')
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -Times 0
    }

    It 'reads the history of what is not available or had an event, with -IncludeHistory' {
        $down = @(Get-AACResourceHealth -IncludeHistory -Days 1 -NoDisplay)[0]
        $down.Availability | Should -Be 70.83
        @($script:uris | ForEach-Object { ($_ -split '/providers/microsoft.resourcehealth', 2, 'IgnoreCase')[0] -replace '^.*/', '' }) | Sort-Object | Should -Be @('sql-slow', 'st-unknown', 'vm-down', 'vm-ok')
    }

    It 'shows the health at the prompt, in characters any console can show' {
        $text = (& $script:capture { Get-AACResourceHealth -NoPaging }).Text
        foreach ($expected in 'Azure Admin Console :: Resource health', '1 unavailable, 1 degraded, 2 available of 5 resource(s); 1 active Azure service issue(s)', 'Resource health (5)', 'Azure Service Health (2)', 'vm-down', 'Virtual Machines - West Europe') { $text | Should -Match ([regex]::Escape($expected)) }
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ }) | Should -BeNullOrEmpty
        }
    }

    It 'writes the resources to CSV and an HTML report with both tables' {
        $csv = Join-Path $TestDrive 'health.csv'
        $html = Join-Path $TestDrive 'health.html'
        $null = & $script:capture { Get-AACResourceHealth -CsvPath $csv -HtmlPath $html }
        @(Import-Csv -LiteralPath $csv)[0].Resource | Should -Be 'vm-down'
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.tables.id) | Should -Be @('health', 'events')
        ($model.tiles | Where-Object label -EQ 'unavailable').filters.State | Should -Be 'Unavailable'
    }
}
