<#
    Unit tests for Get-AACGovernanceSetting, Get-AACTagUsage and
    Get-AACResourceLock: made-up settings, tags and locks
    (Fixtures\ContosoGovernance.ps1), and the commands with Resource Graph
    and Resource Manager faked.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoGovernance.ps1')
    $script:f = Get-AACContosoGovernance
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
    $script:asciiOnly = {
        param([string] $Text)
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            @($Text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ }) | Should -BeNullOrEmpty
        }
    }
    # Resource Manager answers, by URI.
    $script:arm = {
        param([string[]] $Uri)
        $answers = @{}
        foreach ($u in $Uri) {
            $sub = if ($u -match '^/subscriptions/([^/]+)') { $Matches[1] } else { '' }
            $data = if ($sub) { $script:f.PerSubscription[$sub] } else { $null }
            $answers[$u] = switch -Regex ($u) {
                'managementGroups/mg-root/providers/microsoft.insights' { @{ Status = 200; Error = $null; Body = $null; Items = $script:f.GroupDiag['mg-root'].Items } }
                'settings/default' { @{ Status = 200; Error = $null; Body = $script:f.Hierarchy; Items = $null } }
                'securityContacts' { @{ Status = 200; Error = $null; Body = $null; Items = $data.Contacts } }
                'classicAdministrators' { @{ Status = 200; Error = $null; Body = $null; Items = $data.Classic } }
                'Microsoft.Features' { @{ Status = 200; Error = $null; Body = $null; Items = $data.Features } }
                'locks' { @{ Status = 200; Error = $null; Body = $null; Items = @($script:f.Locks | Where-Object { $_.id -like "/subscriptions/$sub*" }) } }
                default { @{ Status = 200; Error = $null; Body = $null; Items = $data.Providers } }
            }
        }
        $answers
    }
}

Describe 'Azure Admin Console - governance settings' {
    BeforeAll {
        $subs = @(foreach ($s in $script:f.Subscriptions) { $c = @{} + $s; $d = $script:f.Details | Where-Object subscriptionId -EQ $s.subscriptionId; $c.quotaId = $d.quotaId; $c.spendingLimit = $d.spendingLimit; $c })
        $script:r = InModuleScope 'Azure.Admin.Console' -Parameters @{ F = $script:f; S = $subs } { param($F, $S) ConvertTo-AACGovernanceSetting -Hierarchy $F.Hierarchy -TenantId $F.TenantId -Subscription $S -PerSubscription $F.PerSubscription -GroupDiagnostics $F.GroupDiag }
    }

    It 'flags the settings to fix first' {
        @($script:r.Settings | Where-Object Status -EQ 'Warning' | ForEach-Object { "$($_.Area) | $($_.Scope) | $($_.Setting)" }) | Should -Be @(
            'Management groups | Tenant root group | Default management group for new subscriptions'
            'Management groups | Tenant root group | Who can create management groups'
            'Diagnostics | management group mg-platform | Activity log exported'
            'Defender contacts | sub-dev | Security contact email'
            'Classic administrators | sub-dev | Co-administrators'
        )
        $script:r.Settings[0].PSObject.TypeNames | Should -Contain 'AAC.GovernanceSetting'
    }

    It 'reports offers, notifications, preview features and uneven providers' {
        $info = @($script:r.Settings | Where-Object Status -EQ 'Info' | ForEach-Object { "$($_.Area) | $($_.Scope) | $($_.Setting) | $($_.Value)" })
        $info | Should -Contain 'Subscription | sub-dev | Offer | Visual Studio / MSDN (dev and test)'
        $info | Should -Contain 'Subscription | sub-dev | Spending limit | On'
        $info | Should -Contain 'Defender contacts | sub-prod | Notifications to roles | AccountAdmin'
        $info | Should -Contain 'Preview features | sub-dev | Microsoft.Network/AllowPreviewThing | Registered'
        $info | Should -Contain 'Resource providers | 1 of 2 subscription(s) | Microsoft.Kusto | Registered in: sub-prod'
        @($script:r.Settings | Where-Object Setting -EQ 'Microsoft.Compute').Count | Should -Be 0
        ($script:r.Settings | Where-Object { $_.Scope -eq 'sub-prod' -and $_.Setting -eq 'Alert notifications' }).Value | Should -Be 'On (from High severity)'
    }

    It 'says when the hierarchy settings couldn''t be read' {
        $r = InModuleScope 'Azure.Admin.Console' { ConvertTo-AACGovernanceSetting -HierarchyError 'Forbidden' }
        $r.Notices | Should -Contain "The management group hierarchy settings couldn't be read (Forbidden): reading them needs Reader on the tenant root group."
    }
}

Describe 'Azure Admin Console - tag usage' {
    BeforeAll { $script:t = InModuleScope 'Azure.Admin.Console' -Parameters @{ R = $script:f.TagRead } { param($R) ConvertTo-AACTagUsage -Read $R -RequiredTag 'owner', 'costcode' } }

    It 'finds casing clashes, near-duplicates, mixed-case values, required tags missing and one-offs' {
        @($script:t.Tags | ForEach-Object { "$($_.Severity) | $($_.Tag) | $($_.Resources)/$($_.ResourceGroups)/$($_.Subscriptions) | $($_.Coverage)" }) | Should -Be @(
            'Medium | Environment | 6/3/2 | 60'
            'Medium | owner | 2/3/0 | 20'
            'Medium | environment | 2/0/0 | 20'
            'Medium | costcode | 0/0/0 | 0'
            'Low | cost-center | 4/0/0 | 40'
            'Low | CostCenter | 3/0/0 | 30'
            'Info | tmp | 1/0/0 | 10'
        )
        $script:t.Tags[0].PSObject.TypeNames | Should -Contain 'AAC.TagUsage'
        ($script:t.Tags | Where-Object Tag -CEQ 'Environment').Findings | Should -BeLike "Also spelled 'environment'*Values differ only in casing: Prod/prod*"
        ($script:t.Tags | Where-Object Tag -EQ 'cost-center').Findings | Should -BeLike "Near-duplicate of 'CostCenter'*"
        ($script:t.Tags | Where-Object Tag -EQ 'owner').Findings | Should -BeLike 'Required, but on only 20% of resources (2 of 10)*'
        "$($script:t.Stats.Coverage) $($script:t.Stats.CaseClashes)" | Should -Be '80 2'
    }
}

Describe 'Azure Admin Console - resource locks' {
    BeforeAll { $script:l = InModuleScope 'Azure.Admin.Console' -Parameters @{ F = $script:f } { param($F) ConvertTo-AACResourceLock -Lock $F.Locks -ResourceGroup $F.Groups -Resource $F.Critical -SubscriptionName $F.Names } }

    It 'lists every lock and the critical resources nothing protects' {
        @($script:l.Locks | ForEach-Object { "$($_.Severity) | $($_.Status) | $($_.Level) | $($_.ScopeType) | $($_.Scope)" }) | Should -Be @(
            'Medium | Locked | ReadOnly | Subscription | sub-dev'
            'Low | Unlocked |  | Resource | sql-legacy (rg-old)'
            'Info | Locked | CanNotDelete | Resource group | rg-core (sub-prod)'
            'Info | Locked | CanNotDelete | Resource | kv-app (rg-app)'
        )
        $script:l.Locks[0].PSObject.TypeNames | Should -Contain 'AAC.ResourceLock'
        $s = $script:l.Stats
        "$($s.Locks) $($s.ReadOnly) $($s.Direct) $($s.Inherited) $($s.Unlocked) $($s.GroupsCovered)/$($s.Groups)" | Should -Be '3 1 1 2 1 2/4'
        ($script:l.Locks | Where-Object Status -EQ 'Unlocked').ResourceType | Should -Be 'microsoft.sql/servers'
    }
}

Describe 'Azure Admin Console - the governance commands' {
    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            if ($Query.Contains('subscriptions')) { return @{ Rows = @{ subscriptions = $script:f.Subscriptions }; Errors = @{} } }
            if ($Query.Contains('details')) { return @{ Rows = @{ details = $script:f.Details }; Errors = @{} } }
            if ($Query.Contains('groups')) { return @{ Rows = @{ groups = $script:f.Groups; resources = $script:f.Critical }; Errors = @{} } }
            $script:f.TagRead
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith { & $script:arm $Uri }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.example'; TenantId = 't-1'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1) } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'Get-AACGovernanceSetting filters by area and status, and shows a view any console can show' {
        @(Get-AACGovernanceSetting -Status Warning -NoDisplay).Count | Should -Be 4
        (Get-AACGovernanceSetting -Area Diagnostics -NoDisplay).Value | Should -Be 'Log Analytics law-platform (Administrative, Policy)'
        @(Get-AACGovernanceSetting -Area PreviewFeatures -NoDisplay).Setting | Should -Be 'Microsoft.Network/AllowPreviewThing'
        $text = (& $script:capture { Get-AACGovernanceSetting -NoPaging }).Text
        foreach ($expected in 'Azure Admin Console :: Governance settings', '4 setting(s) to fix', 'Governance settings (') { $text | Should -Match ([regex]::Escape($expected)) }
        & $script:asciiOnly $text
    }

    It 'Get-AACTagUsage returns the tags, and writes CSV and HTML' {
        @(Get-AACTagUsage -RequiredTag owner -WithFinding -NoDisplay).Count | Should -Be 6
        $csv = Join-Path $TestDrive 'tags.csv'; $html = Join-Path $TestDrive 'tags.html'
        $text = (& $script:capture { Get-AACTagUsage -NoPaging }).Text
        foreach ($expected in 'Azure Admin Console :: Tag usage', '6 tag name(s); 80% of resources carry a tag') { $text | Should -Match ([regex]::Escape($expected)) }
        & $script:asciiOnly $text
        $null = & $script:capture { Get-AACTagUsage -CsvPath $csv -HtmlPath $html }
        @(Import-Csv -LiteralPath $csv)[0].Tag | Should -Be 'Environment'
        Test-Path -LiteralPath $html | Should -BeTrue
    }

    It 'Get-AACResourceLock reads each subscription''s locks and filters by status' {
        @(Get-AACResourceLock -NoDisplay).Count | Should -Be 4
        @(Get-AACResourceLock -Status Unlocked -NoDisplay).Scope | Should -Be 'sql-legacy (rg-old)'
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -ParameterFilter { @($Uri | Where-Object { $_ -match '/locks\?' }).Count -eq 2 }
        $text = (& $script:capture { Get-AACResourceLock -NoPaging }).Text
        foreach ($expected in 'Azure Admin Console :: Resource locks', '3 lock(s) (1 ReadOnly)', '1 unlocked') { $text | Should -Match ([regex]::Escape($expected)) }
        & $script:asciiOnly $text
    }
}
