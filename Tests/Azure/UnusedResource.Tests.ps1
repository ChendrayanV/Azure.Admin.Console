<#
    Unit tests for Get-AACUnusedResource: what is unused in a made-up Contoso
    estate (Fixtures\ContosoUnused.ps1) - disks, IPs, pools, plans, VMs,
    snapshots, resource groups - how it is rated and billed, the queries,
    and the command with Resource Graph and Cost Management faked.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    . (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Fixtures/ContosoUnused.ps1')
    $script:f = Get-AACContosoUnused
    $script:build = { param([hashtable] $Read = $script:f.Read, [hashtable] $Cost = @{}) $f = $script:f; InModuleScope 'Azure.Admin.Console' -Parameters @{ R = $Read; F = $f; C = $Cost } { param($R, $F, $C) ConvertTo-AACUnusedResource -Read $R -SubscriptionName $F.Names -Cost $C } }
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

Describe 'Azure Admin Console - unused resources' {
    BeforeAll { $script:r = & $script:build }

    It 'finds what is unused, the costliest kinds first, and leaves the busy ones alone' {
        @($script:r.Items | ForEach-Object { "$($_.Severity) | $($_.Category) | $($_.Resource) | $($_.Billed)" }) | Should -Be @(
            'High | Application Gateway with no backends | agw-empty | Yes'
            'High | Empty App Service plan | plan-p1 | Yes'
            'High | Empty SQL elastic pool | pool-empty | Yes'
            'High | Stopped VM still billed | vm-stopped | Yes'
            'High | Unused DDoS protection plan | ddos-plan | Yes'
            'Medium | Load balancer with no backends | lb-empty | Yes'
            'Medium | Unassociated public IP | pip-std | Yes'
            'Medium | Unattached disk | disk-premium | Yes'
            'Low | Deallocated VM | vm-dealloc | Partly'
            'Low | Empty App Service plan | plan-free | No'
            'Low | Empty resource group | rg-empty | No'
            'Low | Old snapshot | snap-old | Yes'
            'Low | Unassociated public IP | pip-basic | No'
            'Low | Unattached disk | disk-std | Yes'
            'Low | Unattached network interface | nic-old | No'
        )
        $script:r.Items[0].PSObject.TypeNames | Should -Contain 'AAC.UnusedResource'
        foreach ($busy in 'lb-busy', 'pool-busy', 'snap-new', 'rg-app', 'rg-managed', 'disk-other') { @($script:r.Items.Resource) | Should -Not -Contain $busy }
    }

    It 'says since when, and how much it is' {
        $disk = $script:r.Items | Where-Object Resource -EQ 'disk-premium'
        "$($disk.AgeDays) | $($disk.Sku) | $($disk.ResourceGroup) | $($disk.Subscription)" | Should -Be '40 | Premium_LRS | rg-app | sub-prod'
        $disk.Detail | Should -BeLike 'Premium_LRS, 1024 GiB, unattached since * (40 day(s)).'
        ($script:r.Items | Where-Object Resource -EQ 'snap-old').AgeDays | Should -Be 200
        ($script:r.Items | Where-Object Resource -EQ 'pip-basic').Detail | Should -BeLike '*Basic public IPs were retired*'
        "$($script:r.Stats.Items) $($script:r.Stats.High) $($script:r.Stats.Billed) $($script:r.Stats.Groups)" | Should -Be '15 5 10 1'
    }

    It 'adds last month''s cost, and puts the costliest first within a severity' {
        $cost = @{ ($script:f.Read.Rows.ddosPlans[0].id) = @{ Cost = 2944.0; Currency = 'USD' }; ($script:f.Read.Rows.vms[0].id) = @{ Cost = 140.5; Currency = 'USD' } }
        $r = & $script:build $script:f.Read $cost
        @($r.Items | Select-Object -First 2 | ForEach-Object Resource) | Should -Be @('ddos-plan', 'vm-stopped')
        "$($r.Stats.Monthly) $($r.Stats.Currency) $($r.Stats.Priced)" | Should -Be '3084.5 USD 2'
    }
}

Describe 'Azure Admin Console - unused resource queries' {
    It 'reads every kind, narrowed to the resource groups but for the counts' {
        $q = InModuleScope 'Azure.Admin.Console' { Get-AACUnusedResourceQuery -ResourceGroupName 'rg-a' }
        $q.Count | Should -Be 22
        $q.disks | Should -Match ([regex]::Escape("where resourceGroup in~ ('rg-a')"))
        $q.disks | Should -Match "diskState\) =~ 'Unattached'"
        $q.groupCounts | Should -Not -Match 'rg-a'
    }
}

Describe 'Azure Admin Console - Get-AACUnusedResource' {
    BeforeEach {
        $script:calls = [System.Collections.Generic.List[object]]::new()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $script:calls.Add(@{ Query = $Query; AllowFailure = @($AllowFailure) })
            if ($Query.Contains('subscriptions')) { return @{ Rows = @{ subscriptions = @(@{ subscriptionId = $script:f.Subscription; name = 'sub-prod'; state = 'Enabled' }) }; Errors = @{} } }
            $script:f.Read
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Read-AACInventoryCost -MockWith {
            @{ LastMonth = '2026-09'; Notice = ''; Rows = @(
                    [pscustomobject]@{ ResourceId = $script:f.Read.Rows.ddosPlans[0].id.ToUpperInvariant(); BillingMonth = '2026-09-01T00:00:00'; Cost = 2944.0; Currency = 'USD' }
                    [pscustomobject]@{ ResourceId = $script:f.Read.Rows.ddosPlans[0].id; BillingMonth = '2026-10-01T00:00:00'; Cost = 1000.0; Currency = 'USD' }
                ) }
        }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.example'; TenantId = 't-1'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1) } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'reads every kind in one batch, each allowed to fail, and filters by kind, type and severity' {
        @(Get-AACUnusedResource -NoDisplay).Count | Should -Be 15
        $script:calls[1].AllowFailure.Count | Should -Be 22
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Read-AACInventoryCost -Times 0
        @(Get-AACUnusedResource -Category 'Unattached*' -NoDisplay).Resource | Should -Be @('disk-premium', 'disk-std', 'nic-old')
        @(Get-AACUnusedResource -ResourceType '*/virtualmachines' -NoDisplay).Resource | Should -Be @('vm-stopped', 'vm-dealloc')
        @(Get-AACUnusedResource -Severity High -NoDisplay).Count | Should -Be 5
    }

    It 'reads last month''s cost with -IncludeCost' {
        $ddos = @(Get-AACUnusedResource -IncludeCost -NoDisplay)[0]
        "$($ddos.Resource) $($ddos.MonthlyCost) $($ddos.Currency)" | Should -Be 'ddos-plan 2944 USD' -Because 'only last month counts'
    }

    It 'shows the resources at the prompt, in characters any console can show' {
        $text = (& $script:capture { Get-AACUnusedResource -NoPaging }).Text
        foreach ($expected in 'Azure Admin Console :: Unused resources', '15 unused resource(s): 10 still billed, 5 high', 'By kind', 'Unused resources (15)', 'agw-empty', 'Stopped VM still billed') { $text | Should -Match ([regex]::Escape($expected)) }
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ }) | Should -BeNullOrEmpty
        }
    }

    It 'writes the resources to CSV and an HTML report' {
        $csv = Join-Path $TestDrive 'unused.csv'
        $html = Join-Path $TestDrive 'unused.html'
        $null = & $script:capture { Get-AACUnusedResource -CsvPath $csv -HtmlPath $html }
        @(Import-Csv -LiteralPath $csv)[0].Resource | Should -Be 'agw-empty'
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.tables.id) | Should -Be @('unused')
        ($model.tiles | Where-Object label -EQ 'still billed').filters.Billed | Should -Be 'Yes'
    }
}
