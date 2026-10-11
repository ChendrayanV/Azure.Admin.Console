<#
    Unit tests for Get-AACLegacyAuthentication: made-up Azure resources
    (keys, passwords, local accounts, old TLS) and Entra ID answers
    (legacy-protocol sign-ins, Conditional Access, app registrations,
    authentication methods), the findings and their order, and the command
    with Resource Graph, Resource Manager and Microsoft Graph faked.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoLegacyAuth.ps1')
    $f = Get-AACContosoLegacyAuth
    $script:sub = $f.Sub
    $script:read = $f.Read
    $script:entra = $f.Entra
    $script:app1 = $f.App1
    $script:app2 = $f.App2
    $script:publishing = $f.Publishing
    $script:names = $f.Names
    $script:build = {
        $a = @{ R = $script:read; E = $script:entra; P = $script:publishing; N = $script:names }
        InModuleScope 'Azure.Admin.Console' -Parameters $a { param($R, $E, $P, $N) ConvertTo-AACLegacyAuthentication -Read $R -Entra $E -Publishing $P -Protocols (Get-AACLegacyAuthenticationQuery).Protocols -SubscriptionName $N }
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

Describe 'Azure Admin Console - legacy authentication' {
    BeforeAll { $script:r = & $script:build }

    It 'finds every legacy pattern in Azure and Entra ID, the riskiest first' {
        @($script:r.Findings | ForEach-Object { "$($_.Severity) | $($_.Area) | $($_.Finding) | $($_.Resource)" }) | Should -Be @(
            'High | Azure | AKS cluster without Entra ID integration | aks-noentra'
            'High | Azure | Redis non-TLS port open | redis1'
            'High | Azure | Storage account accepts TLS 1.0/1.1 | st-keys'
            'High | Entra ID | Successful sign-ins over IMAP4 | IMAP4'
            'Medium | Azure | Local authentication enabled | batch1'
            'Medium | Azure | Local authentication enabled | cosmos1'
            'Medium | Azure | Redis access key authentication enabled | redis1'
            'Medium | Azure | Storage account accepts shared keys | st-keys'
            'Medium | Azure | AKS local accounts enabled | aks-local'
            'Medium | Azure | Basic authentication for deployment (SCM) enabled | app1'
            'Medium | Azure | Container registry admin user enabled | acr1'
            'Medium | Azure | Linux VM allows password login | vm-linux'
            'Medium | Azure | SQL authentication enabled | sql1'
            'Medium | Entra ID | Implicit grant issues access tokens | app-implicit'
            'Medium | Entra ID | Public client flows allowed | app-ropc'
            'Medium | Entra ID | Failed sign-ins over POP3 | POP3'
            'Medium | Entra ID | Legacy authentication block is report-only | Block legacy auth'
            'Medium | Entra ID | Sms enabled as an authentication method | Sms'
            'Low | Azure | Local authentication enabled | la1'
            'Low | Azure | Key Vault uses access policies | kv1'
            'Low | Entra ID | App registrations authenticate with client secrets | 2 app(s)'
        )
        $script:r.Findings[0].PSObject.TypeNames | Should -Contain 'AAC.LegacyAuthentication'
    }

    It 'says who signed in with legacy protocols, and what couldn''t be read' {
        $imap = $script:r.Findings | Where-Object Finding -EQ 'Successful sign-ins over IMAP4'
        $imap.Detail | Should -Be '2 successful of 3 sign-in(s) in 7 day(s), by 2 user(s): alice@contoso.com (2), bob@contoso.com (1).'
        $imap.Count | Should -Be 2
        ($script:r.Findings | Where-Object Finding -Like '*client secrets').Detail | Should -BeLike '2 app registration(s)*app-implicit, app-secret.'
        $script:r.Notices | Should -Contain "The publishing credential policies of 1 app(s) couldn't be read."
        @($script:r.Notices | Where-Object { $_ -like "Sign-ins couldn't be read*Entra ID P1" }).Count | Should -Be 1
        "$($script:r.Stats.High) $($script:r.Stats.Azure) $($script:r.Stats.Entra) $($script:r.Stats.Resources) $($script:r.Stats.SignIns)" | Should -Be '4 14 7 12 2'
    }

    It 'says legacy authentication isn''t blocked when nothing blocks it' {
        $entra = @{ Errors = @{}; Data = @{ conditionalAccess = @(); securityDefaults = @{ isEnabled = $false } } }
        $r = InModuleScope 'Azure.Admin.Console' -Parameters @{ E = $entra } { param($E) ConvertTo-AACLegacyAuthentication -Read @{ Rows = @{}; Errors = @{} } -Entra $E }
        $r.Findings[0].Finding | Should -Be 'Legacy authentication not blocked'
        $entra.Data.securityDefaults.isEnabled = $true
        $r = InModuleScope 'Azure.Admin.Console' -Parameters @{ E = $entra } { param($E) ConvertTo-AACLegacyAuthentication -Read @{ Rows = @{}; Errors = @{} } -Entra $E }
        $r.Findings.Count | Should -Be 0 -Because 'security defaults block legacy authentication'
    }
}

Describe 'Azure Admin Console - legacy authentication queries' {
    It 'reads every kind of resource, and one sign-in query per legacy protocol' {
        $q = InModuleScope 'Azure.Admin.Console' { Get-AACLegacyAuthenticationQuery -ResourceGroupName 'rg-app' -SignInDays 3 -Now ([datetime]'2026-10-11T00:00:00Z').ToUniversalTime() }
        $q.Graph.Count | Should -Be 10
        $q.Graph.storage | Should -Match ([regex]::Escape("resourceGroup in~ ('rg-app')"))
        @($q.Entra.Keys | Where-Object { $_ -like 'signIns|*' }).Count | Should -Be 10
        $q.Entra['signIns|IMAP4'].Uri | Should -Match ([regex]::Escape([System.Uri]::EscapeDataString("createdDateTime ge 2026-10-08T00:00:00Z and clientAppUsed eq 'IMAP4'")))
    }
}

Describe 'Azure Admin Console - Get-AACLegacyAuthentication' {
    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            if ($Query.Contains('subscriptions')) { return @{ Rows = @{ subscriptions = @(@{ subscriptionId = $script:sub; name = 'sub-prod'; state = 'Enabled' }) }; Errors = @{} } }
            $script:read
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $answers = @{}
            foreach ($u in $Uri) {
                $answers[$u] = if ($u -like "$script:app1/*") { @{ Status = 200; Error = $null; Body = $null; Items = @(@{ name = 'ftp'; properties = @{ allow = $false } }, @{ name = 'scm'; properties = @{ allow = $true } }) } } else { @{ Status = 403; Error = 'denied'; Body = $null; Items = $null } }
            }
            $answers
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Read-AACGraphQuery -MockWith { $script:entra }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.example'; TenantId = 't-1'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1) } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'reads Azure and Entra ID, and narrows by area, type and severity' {
        @(Get-AACLegacyAuthentication -NoDisplay).Count | Should -Be 21
        @(Get-AACLegacyAuthentication -Area EntraID -NoDisplay).Count | Should -Be 7
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -Times 1 -Because '-Area EntraID reads no Azure resources'
        @(Get-AACLegacyAuthentication -SkipEntra -NoDisplay).Area | Select-Object -Unique | Should -Be 'Azure'
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Read-AACGraphQuery -Times 2
        @(Get-AACLegacyAuthentication -SkipEntra -ResourceType '*/redis' -NoDisplay).Finding | Should -Be @('Redis non-TLS port open', 'Redis access key authentication enabled')
        @(Get-AACLegacyAuthentication -Severity High -NoDisplay).Count | Should -Be 4
    }

    It 'shows the findings at the prompt, in characters any console can show' {
        $text = (& $script:capture { Get-AACLegacyAuthentication -NoPaging }).Text
        foreach ($expected in 'Azure Admin Console :: Legacy authentication', '21 finding(s): 4 high; 12 Azure resource(s) accept keys, passwords or old TLS; 2 successful legacy sign-in(s)', 'Legacy authentication (21)', 'aks-noentra') { $text | Should -Match ([regex]::Escape($expected)) }
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ }) | Should -BeNullOrEmpty
        }
    }

    It 'writes the findings to CSV and an HTML report' {
        $csv = Join-Path $TestDrive 'legacy.csv'
        $html = Join-Path $TestDrive 'legacy.html'
        $null = & $script:capture { Get-AACLegacyAuthentication -CsvPath $csv -HtmlPath $html }
        @(Import-Csv -LiteralPath $csv)[0].Finding | Should -Be 'AKS cluster without Entra ID integration'
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.tables.id) | Should -Be @('findings')
    }
}
