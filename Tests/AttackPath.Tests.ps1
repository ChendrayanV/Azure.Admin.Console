<#
    Unit tests for Get-AACAttackPath: the paths built from a made-up Contoso
    estate (Fixtures\ContosoAttack.ps1) - NSG rules in priority order, Basic
    and Standard public IPs, identities and their roles, key vault access
    policies, blast radius, data stores, Defender's paths - and the command
    with Resource Graph faked: the scope, the filters, the view and reports.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoAttack.ps1')
    $script:f = Get-AACContosoAttack
    $script:build = { param([hashtable] $Read = $script:f.Read) $f = $script:f; InModuleScope 'Azure.Admin.Console' -Parameters @{ R = $Read; F = $f } { param($R, $F) ConvertTo-AACAttackPath -Read $R -SubscriptionName $F.Names -SubscriptionChain $F.Chain } }
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

Describe 'Azure Admin Console - attack paths' {
    BeforeAll { $script:r = & $script:build }

    It 'finds each way in, most dangerous and widest first' {
        @($script:r.Paths | ForEach-Object { "$($_.Severity) | $($_.Category) | $($_.Resource) | $($_.BlastRadius)" }) | Should -Be @(
            'Critical | Internet to subscription control | vm-jump | 18'
            'Critical | Defender for Cloud attack path | vm-jump | 3'
            'High | Internet to data | app-api | 2'
            'High | Management port open to the Internet | vm-basic | 2'
            'High | Data store open to the Internet | stpublic | 1'
            'Medium | Port open to the Internet | vm-web | 2'
            'Medium | Public API server | aks-dev | 1'
            'Medium | Data store open to the Internet | kv-app | 1'
            'Medium | Data store open to the Internet | sql-prod | 1'
        )
        $script:r.Paths[0].PSObject.TypeNames | Should -Contain 'AAC.AttackPath'
    }

    It 'reads the NSG rules in priority order, and knows a Standard IP is closed and a Basic one open without an NSG' {
        ($script:r.Paths | Where-Object Resource -EQ 'vm-web').Exposure | Should -Be 'public IP 20.0.0.2: HTTPS 443' -Because 'SSH is denied at 100 before the allow at 200'
        ($script:r.Paths | Where-Object Resource -EQ 'vm-basic').Exposure | Should -BeLike '*every port (no NSG, Basic public IP)'
        @($script:r.Paths.Resource) | Should -Not -Contain 'vm-closed'
        @($script:r.Paths.Resource) | Should -Not -Contain 'app-site' -Because 'a public app with no identity reaches nothing beyond itself'
        @($script:r.Paths.Resource) | Should -Not -Contain 'stdata' -Because 'it denies other networks'
        "$($script:r.Stats.ExposedVms) $($script:r.Stats.Management)" | Should -Be '3 2'
    }

    It 'follows the identity to what it controls and reads, and adds up the blast radius' {
        $jump = $script:r.Paths[0]
        $jump.Path | Should -Be 'Internet > vm-jump (public IP 20.0.0.1: RDP 3389) > system-assigned identity > Contributor on subscription sub-prod'
        $jump.Targets | Should -Be 'Contributor on subscription sub-prod (system-assigned identity); Key Vault access policy (secrets, keys or certificates) on key vault kv-app (system-assigned identity)'
        $jump.Detail | Should -BeLike '*Lateral: 1 other VM(s) in the same virtual network*'
        $jump.Impact | Should -Be 'An attacker who compromises it can reach 18 resource(s) - and take over the subscription.' -Because '15 in the subscription, the vault, a neighbour and itself'
        $jump.Remediation | Should -BeLike 'Close the management ports to the Internet*Least privilege: replace Contributor*'
        ($script:r.Paths | Where-Object Resource -EQ 'app-api').Path | Should -Be 'Internet > app-api (public endpoint app-api.azurewebsites.net) > user-assigned identity id-api > Storage Blob Data Reader on stdata'
    }

    It 'counts a management group''s subscriptions in its blast radius' {
        $read = @{ Errors = @{}; Rows = @{} + $script:f.Read.Rows }
        $read.Rows.roleAssignments = @(@{ id = 'ra1'; principalId = 'p-jump'; principalType = 'ServicePrincipal'; roleId = '/providers/microsoft.authorization/roledefinitions/8e3af657-a8ff-443c-a75c-2fe8c4bcb635'; scope = '/providers/microsoft.management/managementgroups/mg-prod' })
        $path = (& $script:build $read).Paths[0]
        $path.Path | Should -BeLike '*Owner on management group mg-prod'
        $path.BlastRadius | Should -Be 18 -Because 'the 15 in sub-prod (under mg-prod), the vault, a neighbour and itself'
    }

    It 'says when Defender for Cloud''s paths couldn''t be read, and still derives the rest' {
        $read = @{ Errors = @{ defender = 'The subscription has no Defender CSPM plan.' }; Rows = @{} + $script:f.Read.Rows }
        $read.Rows.defender = @()
        $result = & $script:build $read
        $result.Notices[0] | Should -BeLike "Defender for Cloud's attack paths couldn't be read (they need Defender CSPM)*derived from the estate."
        $result.Stats.Paths | Should -Be 8
    }
}

Describe 'Azure Admin Console - Get-AACAttackPath' {
    BeforeEach {
        $script:calls = [System.Collections.Generic.List[object]]::new()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $script:calls.Add(@{ Keys = @($Query.Keys); SubscriptionId = @($SubscriptionId | Where-Object { $_ }); AllowFailure = @($AllowFailure) })
            if ($Query.Contains('subscriptions')) { return @{ Rows = @{ subscriptions = @(@{ subscriptionId = $script:f.Subscription; name = 'sub-prod'; state = 'Enabled'; chain = @(@{ name = 'mg-prod' }) }) }; Errors = @{} } }
            $script:f.Read
        }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.example'; TenantId = 't-1'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1) } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'reads the estate in one batch, Defender optional, and filters by risk and resource group' {
        $paths = @(Get-AACAttackPath -SubscriptionId $script:f.Subscription -NoDisplay)
        $paths.Count | Should -Be 9
        $script:calls[1].SubscriptionId | Should -Be @($script:f.Subscription)
        $script:calls[1].AllowFailure | Should -Contain 'defender'
        $script:calls[1].AllowFailure | Should -Not -Contain 'roleAssignments'
        @(Get-AACAttackPath -Severity Critical -NoDisplay).Count | Should -Be 2
        @(Get-AACAttackPath -ResourceGroupName 'rg-data' -NoDisplay).Resource | Should -Be @('stpublic', 'kv-app', 'sql-prod')
    }

    It 'shows the paths at the prompt, in characters any console can show' {
        $text = (& $script:capture { Get-AACAttackPath -NoPaging }).Text
        foreach ($expected in 'Azure Admin Console :: Attack paths', 'x 9 attack path(s): 2 critical, 3 high - the largest blast radius is 18 resource(s)', 'critical paths', 'Paths by kind', 'Attack paths (9)', 'x Critical', 'vm-jump', 'Internet > vm-jump (public IP 20.0.0.1: RDP 3389)') { $text | Should -Match ([regex]::Escape($expected)) }
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ }) | Should -BeNullOrEmpty
        }
    }

    It 'writes the paths to CSV and an HTML report' {
        $csv = Join-Path $TestDrive 'paths.csv'
        $html = Join-Path $TestDrive 'paths.html'
        $null = & $script:capture { Get-AACAttackPath -CsvPath $csv -HtmlPath $html }
        @(Import-Csv -LiteralPath $csv)[0].Path | Should -BeLike 'Internet > vm-jump*'
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.tables.id) | Should -Be @('paths')
        ($model.tiles | Where-Object label -EQ 'critical paths').filters.Severity | Should -Be 'Critical'
    }
}
