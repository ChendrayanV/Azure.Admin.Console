<#
    Unit tests for Get-AACRoleAssignment: made-up assignments
    (Fixtures\ContosoRbac.ps1) - every principal type, inherited and
    direct, permanent, activated and eligible, orphaned, risky - with their
    findings and the custom roles, and the command with Resource Graph,
    PIM and Microsoft Graph faked.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoRbac.ps1')
    $script:f = Get-AACContosoRbac
    $script:scope = {
        param([switch] $All)
        $subs = if ($All) { $script:f.Subscriptions } else { @($script:f.Subscriptions[0]) }
        $names = @{}; foreach ($s in $script:f.Subscriptions) { $names[$s.subscriptionId] = $s.name }
        @{ Subscriptions = $subs; Ids = @($subs | ForEach-Object { $_.subscriptionId }); GraphScope = $(if ($All) { @() } else { @($subs | ForEach-Object { $_.subscriptionId }) }); Names = $names; Label = 'test' }
    }
    $script:build = {
        param([hashtable] $Scope = (& $script:scope), $Directory = $script:f.Directory, $Pim = $script:f.Pim, $Members = $script:f.Members)
        InModuleScope 'Azure.Admin.Console' -Parameters @{ R = $script:f.Read; S = $Scope; D = $Directory; P = $Pim; M = $Members; T = $script:f.TenantId } {
            param($R, $S, $D, $P, $M, $T)
            ConvertTo-AACRoleAssignment -Read $R -Scope $S -Directory $D -Pim $P -Members $M -TenantId $T
        }
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

Describe 'Azure Admin Console - role assignments' {
    BeforeAll { $script:r = & $script:build }

    It 'lists every assignment that reaches the scope, the riskiest first' {
        @($script:r.Assignments | ForEach-Object { "$($_.Severity) | $($_.ScopeType) | $($_.Scope) | $($_.Role) | $($_.Principal)" }) | Should -Be @(
            'High | Subscription | sub-prod | Contributor | Carol'
            'High | Subscription | sub-prod | Owner | app-orders'
            'High | Resource | vm1 (rg-app) | Contoso Super Admin | Dave'
            'Medium | Management group | Platform | Owner | Alice'
            'Medium | Subscription | sub-prod | Deleted role (dddddddd-0000-0000-0000-000000000000) | Alice'
            'Medium | Subscription | sub-prod | Owner | Erin'
            'Medium | Subscription | sub-prod | Reader | Identity not found (User)'
            'Info | Root | Root (/) | Owner | Platform Admins'
            'Info | Subscription | sub-prod | Owner | Frank'
            'Info | Subscription | sub-prod | Reader | Vendor Monitoring'
            'Info | Resource group | rg-app (sub-prod) | Contoso Access Granter | uai-deploy'
            'Info | Resource group | rg-app (sub-prod) | Reader | vm-web-01'
        )
        $script:r.Assignments[0].PSObject.TypeNames | Should -Contain 'AAC.RoleAssignment'
    }

    It 'tells each kind of principal apart' {
        $type = @{}; foreach ($a in $script:r.Assignments) { $type[$a.Principal] = $a.PrincipalType }
        "$($type['Carol']) | $($type['app-orders']) | $($type['Vendor Monitoring']) | $($type['vm-web-01']) | $($type['uai-deploy']) | $($type['Platform Admins']) | $($type['Identity not found (User)'])" |
            Should -Be 'Guest | Application | Application (external) | Managed identity (system-assigned) | Managed identity (user-assigned) | Group | Deleted'
    }

    It 'shows what the role can do, how far it reaches, PIM, members and who created it' {
        $root = $script:r.Assignments | Where-Object ScopeType -EQ 'Root'
        "$($root.Reach) | $($root.Members) | $($root.MemberNames)" | Should -Be 'Inherited by 1 subscription(s) | 3 | alice@contoso.example, bob@contoso.example, ops-bot'
        $granter = $script:r.Assignments | Where-Object Role -EQ 'Contoso Access Granter'
        "$($granter.RoleType) $($granter.Privileged) $($granter.CanWriteRoleAssignments)" | Should -Be 'Custom True True'
        ($script:r.Assignments | Where-Object Role -EQ 'Contributor').CanWriteRoleAssignments | Should -BeFalse
        ($script:r.Assignments | Where-Object Principal -EQ 'Erin').Assignment | Should -Be 'Activated (PIM)'
        $frank = @($script:r.Assignments | Where-Object Principal -EQ 'Frank')
        "$($frank.Count) $($frank[0].Assignment) $($frank[0].EndsOn.Year)" | Should -Be '1 Eligible (PIM) 2027'
        ($script:r.Assignments | Where-Object Principal -EQ 'Alice' | Select-Object -First 1).CreatedBy | Should -Be 'admin@contoso.example'
    }

    It 'says why each finding matters' {
        ($script:r.Assignments | Where-Object Principal -EQ 'Alice' | Where-Object ScopeType -EQ 'Management group').Findings | Should -Be 'Owner given to a user directly - give it to a group, so access is reviewed in one place. Standing privileged access: make it eligible in PIM, activated when needed.'
        ($script:r.Assignments | Where-Object Principal -EQ 'Erin').Findings | Should -Not -BeLike '*Standing*'
        ($script:r.Assignments | Where-Object Principal -EQ 'app-orders').Findings | Should -BeLike 'An application or managed identity is Owner on a subscription*'
        ($script:r.Assignments | Where-Object Principal -EQ 'Dave').Findings | Should -BeLike '*Contoso Super Admin is equivalent to Owner*'
    }

    It 'lists the custom roles: equivalent to Owner, unused, used only by a policy' {
        @($script:r.CustomRoles | ForEach-Object { "$($_.Role) | $($_.Assignments) | $($_.Unused) | $($_.OwnerEquivalent) | $($_.UsedByPolicy)" }) | Should -Be @(
            'Contoso Super Admin | 1 | False | True | False'
            'Contoso Unused | 0 | True | False | False'
            'Contoso Access Granter | 1 | False | False | False'
            'Contoso Policy Role | 0 | False | False | True'
        )
        "$($script:r.Stats.UnusedRoles) $($script:r.Stats.OwnerRoles) $($script:r.Stats.Orphaned) $($script:r.Stats.High)" | Should -Be '1 1 2 3'
    }

    It 'covers the whole tenant when unscoped' {
        $all = & $script:build (& $script:scope -All)
        @($all.Assignments).Count | Should -Be 14
        @($all.Assignments | Where-Object Scope -EQ 'Other').Count | Should -Be 1
    }

    It 'shows principals by ID, and no deleted ones, without Entra ID' {
        $r = & $script:build (& $script:scope) @{ Error = 'Forbidden'; Objects = @{} } $script:f.Pim $null
        @($r.Assignments | Where-Object PrincipalType -EQ 'Deleted').Count | Should -Be 0
        ($r.Assignments | Where-Object PrincipalId -EQ 'sp-app').PrincipalType | Should -Be 'Service principal'
        $r.Notices | Should -Contain "The principals couldn't be looked up in Entra ID (Forbidden): they are shown by ID, and deleted ones can't be told apart."
    }
}

Describe 'Azure Admin Console - Get-AACRoleAssignment' {
    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            if ($Query.Contains('subscriptions')) { return @{ Rows = @{ subscriptions = $script:f.Subscriptions }; Errors = @{} } }
            $script:f.Read
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $answers = @{}
            foreach ($u in $Uri) { $answers[$u] = @{ Status = 200; Error = $null; Body = $null; Items = $(if ($u -match 'roleEligibility') { $script:f.Pim.Eligible } else { $script:f.Pim.Instances }) } }
            $answers
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACDirectoryObject -MockWith { $script:f.Directory }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Read-AACGraphQuery -MockWith { @{ Data = @{ 'g-admins' = @(@{ userPrincipalName = 'alice@contoso.example' }, @{ userPrincipalName = 'bob@contoso.example' }, @{ displayName = 'ops-bot' }) }; Errors = @{} } }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.example'; TenantId = 't-1'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1) } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'filters by principal type, role, scope type, privilege and finding' {
        @(Get-AACRoleAssignment -ManagementGroupId 'mg-platform' -NoDisplay).Count | Should -Be 12
        @(Get-AACRoleAssignment -ManagementGroupId 'mg-platform' -PrincipalType Guest, Deleted -NoDisplay).Principal | Should -Be @('Carol', 'Identity not found (User)')
        @(Get-AACRoleAssignment -ManagementGroupId 'mg-platform' -RoleName '*Owner*' -ScopeType Subscription -NoDisplay).Count | Should -Be 3
        @(Get-AACRoleAssignment -ManagementGroupId 'mg-platform' -Privileged -WithFinding -NoDisplay).Count | Should -Be 5
        $both = @(Get-AACRoleAssignment -ManagementGroupId 'mg-platform' -IncludeCustomRole -NoDisplay)
        "$(@($both | Where-Object { $_.PSObject.TypeNames -contains 'AAC.RoleAssignment' }).Count) $(@($both | Where-Object { $_.PSObject.TypeNames -contains 'AAC.CustomRole' }).Count)" | Should -Be '12 4'
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Read-AACGraphQuery -Times 0
    }

    It 'reads the groups'' members with -ExpandGroup, and skips PIM and Entra ID when told' {
        (Get-AACRoleAssignment -ManagementGroupId 'mg-platform' -ExpandGroup -NoDisplay | Where-Object ScopeType -EQ 'Root').Members | Should -Be 3
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Read-AACGraphQuery -Times 1
        $null = Get-AACRoleAssignment -ManagementGroupId 'mg-platform' -SkipPim -SkipEntra -NoDisplay
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -Times 1 -Exactly
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Get-AACDirectoryObject -Times 1 -Exactly
    }

    It 'shows the assignments at the prompt, in characters any console can show' {
        $text = (& $script:capture { Get-AACRoleAssignment -ManagementGroupId 'mg-platform' -NoPaging }).Text
        foreach ($expected in 'Azure Admin Console :: Role assignments', '12 role assignment(s)', 'Role assignments (12)', 'Custom roles (4)', 'app-orders') { $text | Should -Match ([regex]::Escape($expected)) }
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ }) | Should -BeNullOrEmpty
        }
    }

    It 'writes the assignments to CSV and an HTML report with the custom roles' {
        $csv = Join-Path $TestDrive 'rbac.csv'
        $html = Join-Path $TestDrive 'rbac.html'
        $null = & $script:capture { Get-AACRoleAssignment -ManagementGroupId 'mg-platform' -CsvPath $csv -HtmlPath $html }
        @(Import-Csv -LiteralPath $csv)[0].Principal | Should -Be 'Carol'
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.tables.id) | Should -Be @('assignments', 'customRoles')
    }
}
