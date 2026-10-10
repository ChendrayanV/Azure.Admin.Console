<#
    Unit tests for Get-AACResourceUtilization: made-up Contoso metrics
    (Fixtures\ContosoUtilization.ps1) - idle, under-used, hot, right sized
    and silent resources, VM memory from free bytes, trends, right-sizing
    with retail prices, the cost and chargeback - and the command with
    Resource Graph, Azure Monitor, the prices and Cost Management faked.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoUtilization.ps1')
    $script:f = Get-AACContosoUtilization
    $script:rate = {
        param([hashtable] $More = @{})
        $f = $script:f
        # One set of parameters, $More's winning (an explicit parameter would win over a splatted one).
        $parameters = @{ Resource = @($f.Resources | Where-Object { $_.power -ne 'PowerState/deallocated' }); Metric = $f.Metrics; Size = $f.Sizes; Price = $f.Prices; Cost = $f.Cost; SubscriptionName = $f.Names }
        foreach ($k in $More.Keys) { $parameters[$k] = $More[$k] }
        InModuleScope 'Azure.Admin.Console' -Parameters @{ P = $parameters } { param($P) ConvertTo-AACResourceUtilization @P }
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
        $console.Profile.Width = 220
        $console.Profile.Capabilities.Unicode = $false
        try { [Spectre.Console.AnsiConsole]::Console = $console; $output = @(& $Render) }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
}

Describe 'Azure Admin Console - resource utilization' {
    BeforeAll { $script:r = & $script:rate }

    It 'rates each resource idle, under-used, hot, right sized or without data - waste first' {
        @($script:r.Rows | ForEach-Object { "$($_.Category) | $($_.Resource) | $($_.CpuP95) | $($_.Trend)" }) | Should -Be @(
            'Idle | vm-idle | 2 | Stable'
            'Idle | st-old |  | Stable'
            'Under-used | vm-big | 20 | Stable'
            'Hot | vm-hot | 92 | Growing'
            'Right sized | plan-shop | 59 | Stable'
            'No data | sqldb |  | Stable'
        )
        ($script:r.Rows | Where-Object Resource -EQ 'vm-hot').Severity | Should -Be 'High' -Because 'hot and still growing'
        $script:r.Rows[0].PSObject.TypeNames | Should -Contain 'AAC.ResourceUtilization'
    }

    It 'works out a VM''s memory use from its free memory and size, and resizes it within its family' {
        $big = $script:r.Rows | Where-Object Resource -EQ 'vm-big'
        "$($big.MemoryP95) | $($big.SuggestedSize) | $($big.EstimatedSaving) $($big.Currency)" | Should -Be '25 | Standard_D4s_v5 | 146 USD' -Because '(0.40 - 0.20) an hour x 730'
        $big.Remediation | Should -Be 'Scale down: resize to Standard_D4s_v5.'
        $tight = & $script:rate @{ Size = @{ 'westeurope|standard_d8s_v5' = @{ Cores = 8; MemoryMB = 32768 }; 'westeurope|standard_d4s_v5' = @{ Cores = 4; MemoryMB = 8192 } } }
        ($tight.Rows | Where-Object Resource -EQ 'vm-big').SuggestedSize | Should -BeNullOrEmpty -Because '8 GB used, with 20% to spare, doesn''t fit in 8 GB'
    }

    It 'charges back the unused share of the cost, and estimates the saving' {
        $idle = $script:r.Rows | Where-Object Resource -EQ 'vm-idle'
        "$($idle.MonthlyCost) $($idle.UnusedCost) $($idle.EstimatedSaving) $($idle.Currency)" | Should -Be '100 98.5 100 EUR' -Because 'an idle resource saves all of its cost'
        ($script:r.Rows | Where-Object Resource -EQ 'plan-shop').UnusedCost | Should -Be 100 -Because '200 a month at 50% average CPU'
        $script:r.Stats.SavingText | Should -Be '100 EUR; 146 USD'
    }

    It 'can be made stricter or looser' {
        (& $script:rate @{ LowPercent = 15 }).Rows | Where-Object Resource -EQ 'vm-big' | ForEach-Object { $_.Category } | Should -Be 'Right sized'
        (& $script:rate @{ HighPercent = 95 }).Rows | Where-Object Resource -EQ 'vm-hot' | ForEach-Object { $_.Category } | Should -Be 'Right sized'
    }
}

Describe 'Azure Admin Console - Get-AACResourceUtilization' {
    BeforeEach {
        $script:metricUris = [System.Collections.Generic.List[string]]::new()
        $script:priced = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            if ($Query.Contains('subscriptions')) { return @{ Rows = @{ subscriptions = @(@{ subscriptionId = $script:f.Sub; name = 'sub-prod'; state = 'Enabled'; chain = @() }) }; Errors = @{} } }
            $script:resourceQuery = $Query.resources
            @{ Rows = @{ resources = $script:f.Resources }; Errors = @{} }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $answers = @{}
            foreach ($u in $Uri) {
                if ($u -like '*/vmSizes*') { $answers[$u] = @{ Status = 200; Error = ''; Items = @($script:f.Sizes.Keys | ForEach-Object { @{ name = ($_ -split '\|')[1]; numberOfCores = $script:f.Sizes[$_].Cores; memoryInMB = $script:f.Sizes[$_].MemoryMB } }) }; continue }
                $script:metricUris.Add($u)
                $id = ($u -replace '/providers/Microsoft.Insights/metrics.*$', '').ToLowerInvariant()
                $answers[$u] = if ($script:f.Metrics.Contains($id)) { @{ Status = 200; Error = ''; Body = @{ value = $script:f.Metrics[$id] } } } else { @{ Status = 400; Error = 'Failed to find metric configuration.' } }
            }
            $answers
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACRetailPrice -MockWith { $script:priced.Add("$Location|$Size|$Os"); $script:f.Prices["$Location|$($Size.ToLowerInvariant())|$Os"] }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Read-AACInventoryCost -MockWith {
            @{ ThisMonth = '2026-10'; LastMonth = '2026-09'; Notice = @(); Status = @{}; Rows = @(
                    [pscustomobject]@{ ResourceId = '/subscriptions/11111111-1111-1111-1111-111111111111/resourcegroups/rg-app/providers/microsoft.compute/virtualmachines/vm-idle'; BillingMonth = [datetime]'2026-09-01'; Cost = 100; Currency = 'EUR' }
                    [pscustomobject]@{ ResourceId = '/subscriptions/11111111-1111-1111-1111-111111111111/resourcegroups/rg-app/providers/microsoft.compute/virtualmachines/vm-idle'; BillingMonth = [datetime]'2026-10-01'; Cost = 30; Currency = 'EUR' }
                ) }
        }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.example'; TenantId = 't-1'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1) } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'reads the metrics of each running resource hourly, retries with the first metric, and prices only the sizes it suggests' {
        $rows = @(Get-AACResourceUtilization -Days 7 -NoDisplay)
        @($rows.Resource) | Should -Not -Contain 'vm-off' -Because 'deallocated VMs aren''t billed for compute'
        @($script:metricUris | Where-Object { $_ -like '*vm-idle/*' })[0] | Should -BeLike '*/providers/Microsoft.Insights/metrics?api-version=2023-10-01&metricnames=Percentage%20CPU%2CAvailable%20Memory%20Bytes%2CNetwork%20In%20Total&timespan=*&interval=PT1H&aggregation=Average,Maximum,Minimum,Total'
        @($script:metricUris | Where-Object { $_ -like '*sqldb*' }).Count | Should -Be 2 -Because 'the second time, CPU only'
        @($script:priced | Sort-Object) | Should -Be @('westeurope|Standard_D4s_v5|linux', 'westeurope|Standard_D8s_v5|linux')
        ($rows | Where-Object Resource -EQ 'vm-big').EstimatedSaving | Should -Be 146
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Read-AACInventoryCost -Times 0 -Exactly
    }

    It 'adds each resource''s cost with -IncludeCost - last month''s - and filters by type' {
        $rows = @(Get-AACResourceUtilization -IncludeCost -NoDisplay)
        "$(($rows | Where-Object Resource -EQ 'vm-idle').MonthlyCost)" | Should -Be '100'
        $null = Get-AACResourceUtilization -ResourceType 'microsoft.compute/*' -NoDisplay
        $script:resourceQuery | Should -BeLike "*type in~ ('microsoft.compute/virtualmachines', 'microsoft.compute/virtualmachinescalesets')*"
        { Get-AACResourceUtilization -ResourceType 'microsoft.nope/*' -NoDisplay } | Should -Throw '*is one this command measures*'
    }

    It 'shows the use at the prompt' {
        $text = (& $script:capture { Get-AACResourceUtilization -NoPaging }).Text
        foreach ($expected in 'Azure Admin Console :: Resource utilization', '6 resource(s): 2 idle, 1 under-used, 1 hot, 1 right sized', 'Resources (6)', 'Standard_D4s_v5', 'Resources by use', '1 deallocated VM(s) left out') { $text | Should -Match ([regex]::Escape($expected)) }
    }
}
