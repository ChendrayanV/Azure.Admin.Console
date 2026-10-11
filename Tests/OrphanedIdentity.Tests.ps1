<#
    Unit tests for Get-AACOrphanedIdentity: made-up identities
    (Fixtures\ContosoIdentity.ps1) - deleted principals, unattached
    user-assigned identities, managed identities of deleted resources,
    stale, disabled and abandoned applications - rated by the access they
    hold, and the command with Resource Graph, Resource Manager and
    Microsoft Graph faked.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoIdentity.ps1')
    $script:f = Get-AACContosoIdentity
    $script:build = {
        param([hashtable] $Entra = $script:f.Entra, [hashtable] $Directory = $script:f.Directory)
        $a = @{ F = $script:f; E = $Entra; D = $Directory }
        InModuleScope 'Azure.Admin.Console' -Parameters $a { param($F, $E, $D) ConvertTo-AACOrphanedIdentity -Read $F.Read -Federated $F.Federated -Directory $D -Entra $E -TenantId $F.TenantId -SubscriptionName $F.Names }
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

Describe 'Azure Admin Console - orphaned identities' {
    BeforeAll { $script:r = & $script:build }

    It 'finds the identities nobody uses, the ones with the most access first' {
        @($script:r.Identities | ForEach-Object { "$($_.Severity) | $($_.Kind) | $($_.Identity) | $($_.RoleAssignments)" }) | Should -Be @(
            'High | Application | app-stale | 1'
            'High | Deleted principal | Identity not found (User) | 1'
            'Medium | Application | app-disabled | 1'
            'Medium | Deleted principal | Identity not found (ServicePrincipal) | 1'
            'Medium | Managed identity | app-deleted | 1'
            'Medium | User-assigned identity | uai-loose | 1'
            'Medium | Application | app-expired | 0'
            'Low | Application | app-noowner | 0'
            'Low | User-assigned identity | uai-unread | 0'
        )
        $script:r.Identities[0].PSObject.TypeNames | Should -Contain 'AAC.OrphanedIdentity'
    }

    It 'says why, and what access is left' {
        $stale = $script:r.Identities[0]
        "$($stale.Reason) | $($stale.Roles) | $($stale.DaysInactive)" | Should -Be ('No sign-in for 200 days (last ' + $stale.LastSignIn.ToString('yyyy-MM-dd') + '). | Owner on management group mg-root | 200')
        ($script:r.Identities | Where-Object Identity -EQ 'Identity not found (User)').Roles | Should -Be 'Owner on subscription sub-prod'
        ($script:r.Identities | Where-Object Identity -EQ 'app-expired').Reason | Should -BeLike 'Every credential has expired (the last on *): nothing can sign in as it. No owners: nobody is accountable for it.'
        ($script:r.Identities | Where-Object Identity -EQ 'app-expired').Credentials | Should -Be '2 secret(s), 0 certificate(s), all expired'
        ($script:r.Identities | Where-Object Identity -EQ 'uai-unread').Reason | Should -Be 'Attached to no resource (federated credentials not checked).'
        ($script:r.Identities | Where-Object Identity -EQ 'app-deleted').ResourceId | Should -BeLike '*/microsoft.web/sites/app-deleted'
        "$($script:r.Stats.Identities) $($script:r.Stats.High) $($script:r.Stats.Deleted) $($script:r.Stats.Unattached) $($script:r.Stats.WithAccess) $($script:r.Stats.Assignments)" | Should -Be '9 2 2 2 6 6'
    }

    It 'lists no stale applications without sign-in activity, and says so' {
        $entra = @{ Errors = @{ signIns = 'Forbidden' }; Data = @{} + $script:f.Entra.Data }
        $entra.Data.Remove('signIns')
        $r = & $script:build $entra
        @($r.Identities | Where-Object Identity -EQ 'app-stale').Count | Should -Be 0
        $r.Notices | Should -Contain 'Without sign-in activity, inactive service principals can''t be told apart: only expired credentials, missing owners and disabled ones are listed.'
    }

    It 'checks no deleted principals when the directory couldn''t be read' {
        $r = & $script:build $script:f.Entra @{ Error = 'Forbidden'; Objects = @{} }
        @($r.Identities | Where-Object Kind -EQ 'Deleted principal').Count | Should -Be 0
        $r.Notices | Should -Contain "The role assignments' principals couldn't be looked up in Entra ID: Forbidden"
    }
}

Describe 'Azure Admin Console - Get-AACOrphanedIdentity' {
    BeforeEach {
        $script:uris = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            if ($Query.Contains('subscriptions')) { return @{ Rows = @{ subscriptions = @(@{ subscriptionId = $script:f.Subscription; name = 'sub-prod'; state = 'Enabled' }) }; Errors = @{} } }
            $script:f.Read
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $answers = @{}
            foreach ($u in $Uri) {
                $script:uris.Add($u)
                $id = $u -replace '/federatedIdentityCredentials\?.*$', ''
                $answers[$u] = if ($script:f.Federated.Contains($id)) { @{ Status = 200; Error = $null; Body = $null; Items = @(1..$script:f.Federated[$id] | Where-Object { $script:f.Federated[$id] } | ForEach-Object { @{ name = "fic$_" } }) } } else { @{ Status = 403; Error = 'denied'; Body = $null; Items = $null } }
            }
            $answers
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACDirectoryObject -MockWith { $script:f.Directory }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Read-AACGraphQuery -MockWith { $script:f.Entra }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.example'; TenantId = 't-1'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1) } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'reads the federated credentials of the unattached identities only, and filters by kind and severity' {
        @(Get-AACOrphanedIdentity -NoDisplay).Count | Should -Be 9
        @($script:uris | ForEach-Object { ($_ -split '/federatedIdentityCredentials')[0] -replace '^.*/', '' }) | Sort-Object | Should -Be @('uai-fed', 'uai-loose', 'uai-unread')
        @(Get-AACOrphanedIdentity -Kind DeletedPrincipal -NoDisplay).Identity | Should -Be @('Identity not found (User)', 'Identity not found (ServicePrincipal)')
        @(Get-AACOrphanedIdentity -Severity High -NoDisplay).Count | Should -Be 2
    }

    It 'reads Azure only with -SkipEntra' {
        @(Get-AACOrphanedIdentity -SkipEntra -NoDisplay).Identity | Should -Be @('uai-loose', 'uai-unread')
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Read-AACGraphQuery -Times 0
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Get-AACDirectoryObject -Times 0
    }

    It 'shows the identities at the prompt, in characters any console can show' {
        $text = (& $script:capture { Get-AACOrphanedIdentity -NoPaging }).Text
        foreach ($expected in 'Azure Admin Console :: Orphaned identities', '9 identit(ies) look unused: 6 still hold role assignments, 2 a privileged role', 'Orphaned identities (9)', 'app-stale') { $text | Should -Match ([regex]::Escape($expected)) }
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ }) | Should -BeNullOrEmpty
        }
    }

    It 'writes the identities to CSV and an HTML report' {
        $csv = Join-Path $TestDrive 'identities.csv'
        $html = Join-Path $TestDrive 'identities.html'
        $null = & $script:capture { Get-AACOrphanedIdentity -CsvPath $csv -HtmlPath $html }
        @(Import-Csv -LiteralPath $csv)[0].Identity | Should -Be 'app-stale'
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.tables.id) | Should -Be @('identities')
    }
}
