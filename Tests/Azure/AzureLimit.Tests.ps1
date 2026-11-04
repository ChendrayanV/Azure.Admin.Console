<#
    Unit tests for Test-AACAzureLimit: made-up Resource Graph totals
    (Fixtures\ContosoLimit.ps1) turned into each scope's use of each Azure
    limit - in and out of scope, warning and critical, raised maximums -
    and the command with Resource Graph faked.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    . (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Fixtures/ContosoLimit.ps1')
    $script:f = Get-AACContosoLimit
    # The scope Resolve-AACScope returns: the two platform subscriptions (scoped), or all three (unscoped).
    $script:scope = {
        param([switch] $All)
        $subs = if ($All) { $script:f.Subscriptions } else { @($script:f.Subscriptions | Select-Object -First 2) }
        $names = @{}; foreach ($s in $script:f.Subscriptions) { $names[$s.subscriptionId] = $s.name }
        @{ Subscriptions = $subs; Ids = @($subs | ForEach-Object { $_.subscriptionId }); GraphScope = $(if ($All) { @() } else { @($subs | ForEach-Object { $_.subscriptionId }) }); Names = $names; Label = 'test' }
    }
    $script:build = {
        param([hashtable] $Scope = (& $script:scope), [hashtable] $Maximum = @{})
        InModuleScope 'Azure.Admin.Console' -Parameters @{ R = $script:f.Read; S = $Scope; M = $Maximum } { param($R, $S, $M) ConvertTo-AACAzureLimit -Read $R -Scope $S -Maximum $M }
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
        $console.Profile.Width = 200
        $console.Profile.Capabilities.Unicode = $false
        try { [Spectre.Console.AnsiConsole]::Console = $console; $output = @(& $Render) }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
}

Describe 'Azure Admin Console - Azure limits' {
    It 'rates each scope''s use of each limit, the closest first' {
        $r = & $script:build
        @($r.Limits | Where-Object Status -NE 'OK' | ForEach-Object { "$($_.Status) | $($_.Limit) | $($_.Scope) | $($_.Used)/$($_.Maximum)" }) | Should -Be @(
            'Critical | Role assignments | sub-prod | 3900/4000'
            'Critical | Policy assignments | rg-hot (sub-prod) | 190/200'
            'Warning | Tags (resource with the most) | sub-prod | 46/50'
            'Warning | Policy assignments | Platform | 170/200'
            'Warning | Role assignments | Platform | 420/500'
            'Warning | Management group depth | Tenant | 5/6'
            'Warning | Custom roles | Tenant | 4100/5000'
        )
        $r.Limits[0].PSObject.TypeNames | Should -Contain 'AAC.AzureLimit'
        $r.Limits[0].Advice | Should -BeLike 'Assign roles to groups*'
        ($r.Limits | Where-Object Limit -EQ 'Tags (resource with the most)').Detail | Should -Be 'Most: vm-tagged (virtualmachines)'
        ($r.Limits | Where-Object Limit -EQ 'Management group depth').Detail | Should -Be 'Deepest: Deep team'
    }

    It 'leaves out what is out of scope, unused, and resource groups below the warning level' {
        $r = & $script:build
        @($r.Limits | Where-Object Scope -Match 'sub-out|Other|rg-cool').Count | Should -Be 0
        @($r.Limits | Where-Object Used -LE 0).Count | Should -Be 0
        ($r.Limits | Where-Object { $_.Limit -eq 'Role assignments' -and $_.Scope -eq 'sub-dev' }).Status | Should -Be 'OK'
        $all = & $script:build (& $script:scope -All)
        @($all.Limits | Where-Object Scope -In 'sub-out', 'Other').Count | Should -Be 2
    }

    It 'takes a raised maximum, and refuses a limit it doesn''t know' {
        $r = & $script:build (& $script:scope) @{ RoleAssignmentsPerSubscription = 6000 }
        ($r.Limits | Where-Object { $_.Limit -eq 'Role assignments' -and $_.Scope -eq 'sub-prod' }) | ForEach-Object { "$($_.Status) $($_.Maximum) $($_.Percent)" } | Should -Be 'OK 6000 65'
        { & $script:build (& $script:scope) @{ NoSuchLimit = 1 } } | Should -Throw "*doesn't know the limit 'NoSuchLimit'*"
    }

    It 'says which counts couldn''t be read' {
        $read = @{ Errors = @{ policyAssignments = 'BadRequest' }; Rows = $script:f.Read.Rows }
        $r = InModuleScope 'Azure.Admin.Console' -Parameters @{ R = $read; S = (& $script:scope) } { param($R, $S) ConvertTo-AACAzureLimit -Read $R -Scope $S }
        $r.Notices | Should -Contain "The policy assignments couldn't be counted: BadRequest"
    }
}

Describe 'Azure Admin Console - Test-AACAzureLimit' {
    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            if ($Query.Contains('subscriptions')) { return @{ Rows = @{ subscriptions = $script:f.Subscriptions }; Errors = @{} } }
            $script:f.Read
        }
    }

    It 'returns the limits, and filters by status' {
        $all = @(Test-AACAzureLimit -ManagementGroupId 'mg-platform' -NoDisplay)
        $all.Count | Should -BeGreaterThan 10
        @(Test-AACAzureLimit -ManagementGroupId 'mg-platform' -Status Critical -NoDisplay).Count | Should -Be 2
    }

    It 'fails a pipeline at the limit it is told to' {
        { Test-AACAzureLimit -ManagementGroupId 'mg-platform' -FailOnLimit Critical -NoDisplay } | Should -Throw '*2 limit(s) at or above 95%*'
        { Test-AACAzureLimit -ManagementGroupId 'mg-platform' -Maximum @{ RoleAssignmentsPerSubscription = 9000; PolicyAssignmentsPerScope = 900 } -FailOnLimit Critical -NoDisplay } | Should -Not -Throw
        { Test-AACAzureLimit -WarningPercent 90 -CriticalPercent 80 } | Should -Throw '*-WarningPercent (90) is above -CriticalPercent (80)*'
    }

    It 'shows the limits at the prompt, in characters any console can show' {
        $text = (& $script:capture { Test-AACAzureLimit -ManagementGroupId 'mg-platform' -NoPaging }).Text
        foreach ($expected in 'Azure Admin Console :: Azure limits', '2 limit(s) critical and 5 close', 'Azure limits (', 'sub-prod') { $text | Should -Match ([regex]::Escape($expected)) }
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ }) | Should -BeNullOrEmpty
        }
    }

    It 'reads the quota of each region in use only with -IncludeQuota, and rates it against Azure''s own maximum' {
        $prod = @($script:f.Subscriptions | Select-Object -First 1)[0].subscriptionId
        $script:quotaUris = @()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            if ($Query.Contains('subscriptions')) { return @{ Rows = @{ subscriptions = $script:f.Subscriptions }; Errors = @{} } }
            if ($Query.Contains('quotaLocations')) { return @{ Rows = @{ quotaLocations = @(@{ subscriptionId = $script:prodId; location = 'westeurope' }) }; Errors = @{} } }
            $script:f.Read
        }
        $script:prodId = $prod
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $script:quotaUris = @($Uri)
            $answers = @{}
            foreach ($item in $Uri) {
                $answers[$item] = switch -Wildcard ($item) {
                    '*Microsoft.Compute*' { @{ Status = 200; Error = ''; Items = @(@{ name = @{ value = 'cores'; localizedValue = 'Total Regional vCPUs' }; currentValue = 96; limit = 100 }, @{ name = @{ value = 'availabilitySets'; localizedValue = 'Availability Sets' }; currentValue = 0; limit = 2500 }, @{ name = @{ value = 'nope'; localizedValue = 'Not offered' }; currentValue = 3; limit = 0 }) } }
                    '*Microsoft.Network*' { @{ Status = 200; Error = ''; Items = @(@{ name = @{ value = 'PublicIPAddresses'; localizedValue = 'Public IP Addresses' }; currentValue = 85; limit = 100 }) } }
                    default { @{ Status = 409; Error = 'Not registered'; Items = $null } }
                }
            }
            $answers
        }
        $plain = @(Test-AACAzureLimit -ManagementGroupId 'mg-platform' -NoDisplay)
        @($plain | Where-Object ScopeType -EQ 'Region').Count | Should -Be 0
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -Times 0 -Exactly
        $all = @(Test-AACAzureLimit -ManagementGroupId 'mg-platform' -IncludeQuota -NoDisplay)
        @($script:quotaUris | Where-Object { $_ -like "*/subscriptions/$prod/providers/Microsoft.*/locations/westeurope/usages*" }).Count | Should -Be 3
        $regions = @($all | Where-Object ScopeType -EQ 'Region')
        @($regions | ForEach-Object { "$($_.Status) | $($_.Limit) | $($_.Used)/$($_.Maximum)" }) | Should -Be @('Critical | Compute quota: Total Regional vCPUs | 96/100', 'Warning | Network quota: Public IP Addresses | 85/100') -Because 'unused quotas, and those with no maximum, are left out'
        $regions[0].Scope | Should -BeLike 'westeurope (*'
        $regions[0].Advice | Should -BeLike 'Request a quota increase*'
        { Test-AACAzureLimit -ManagementGroupId 'mg-platform' -Maximum @{ RoleAssignmentsPerSubscription = 9000; PolicyAssignmentsPerScope = 900 } -IncludeQuota -FailOnLimit Critical -NoDisplay } | Should -Throw '*vCPUs*'
    }

    It 'says when quota couldn''t be read, beyond a provider that isn''t registered' {
        $answers = { param($Status, $ErrorText) @{ Status = $Status; Error = $ErrorText; Items = $null } }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith { $map = @{}; foreach ($item in $Uri) { $map[$item] = @{ Status = 403; Error = 'Authorization failed'; Items = $null } }; $map }
        $read = InModuleScope 'Azure.Admin.Console' { Get-AACAzureQuota -Location @(@{ subscriptionId = 's'; location = 'westeurope' }) }
        @($read.Rows).Count | Should -Be 0
        @($read.Notices)[0] | Should -BeLike "3 of 3 quota answer(s) couldn't be read*Authorization failed*"
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith { $map = @{}; foreach ($item in $Uri) { $map[$item] = @{ Status = 404; Error = 'Not found'; Items = $null } }; $map }
        @((InModuleScope 'Azure.Admin.Console' { Get-AACAzureQuota -Location @(@{ subscriptionId = 's'; location = 'westeurope' }) }).Notices).Count | Should -Be 0
    }

    It 'writes the limits to CSV and an HTML report' {
        $csv = Join-Path $TestDrive 'limits.csv'
        $html = Join-Path $TestDrive 'limits.html'
        $null = & $script:capture { Test-AACAzureLimit -ManagementGroupId 'mg-platform' -CsvPath $csv -HtmlPath $html }
        @(Import-Csv -LiteralPath $csv)[0].Scope | Should -Be 'sub-prod'
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.tables.id) | Should -Be @('limits')
    }
}
