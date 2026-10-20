<#
    Unit tests for Get-AACGovernanceChange: made-up policy and access
    changes - definitions, initiatives, assignments (one switched to
    DoNotEnforce), a custom role and role assignments (one privileged) -
    in and out of the window and scope, with their authors, and the command
    with Resource Graph and Microsoft Graph faked.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    $prod = '11111111-1111-1111-1111-111111111111'; $out = '99999999-9999-9999-9999-999999999999'
    $alice = 'aaaaaaaa-0000-0000-0000-000000000001'; $bob = 'bbbbbbbb-0000-0000-0000-000000000002'; $gone = 'dddddddd-0000-0000-0000-000000000009'
    $ago = { param([int] $Days) [datetime]::UtcNow.AddDays(-$Days).ToString('o') }
    $mg = '/providers/microsoft.management/managementgroups/mg-platform'
    $script:prod = $prod
    $script:read = @{
        Errors = @{}
        Rows   = @{
            policyDefinitions = @(@{ id = "$mg/providers/microsoft.authorization/policydefinitions/deny-ip"; name = 'Deny public IPs'; scope = $mg; createdOn = (& $ago 3); createdBy = $alice; updatedOn = ''; updatedBy = '' })
            policySets        = @(@{ id = "$mg/providers/microsoft.authorization/policysetdefinitions/baseline"; name = 'Baseline'; scope = $mg; createdOn = (& $ago 200); createdBy = $alice; updatedOn = (& $ago 5); updatedBy = $bob })
            policyAssignments = @(
                @{ id = "/subscriptions/$prod/providers/microsoft.authorization/policyassignments/a1"; name = 'Baseline (prod)'; scope = "/subscriptions/$prod"; enforcement = 'DoNotEnforce'; createdOn = (& $ago 40); createdBy = $alice; updatedOn = (& $ago 1); updatedBy = $gone }
                @{ id = "/subscriptions/$out/providers/microsoft.authorization/policyassignments/a2"; name = 'Elsewhere'; scope = "/subscriptions/$out"; enforcement = 'Default'; createdOn = (& $ago 2); createdBy = $alice; updatedOn = ''; updatedBy = '' }
            )
            roleDefinitions   = @(@{ id = '/providers/microsoft.authorization/roledefinitions/c1'; name = 'Contoso Operator'; scope = "/subscriptions/$prod"; createdOn = (& $ago 10); createdBy = $bob; updatedOn = (& $ago 10); updatedBy = $bob })
            roleAssignments   = @(
                @{ id = 'ra1'; name = 'ra1'; scope = "/subscriptions/$prod"; roleId = '/providers/microsoft.authorization/roledefinitions/8e3af657-a8ff-443c-a75c-2fe8c4bcb635'; principalId = $bob; principalType = 'User'; createdOn = (& $ago 2); createdBy = $alice; updatedOn = (& $ago 2); updatedBy = $alice }
                @{ id = 'ra2'; name = 'ra2'; scope = "/subscriptions/$prod/resourcegroups/rg-app"; roleId = '/providers/microsoft.authorization/roledefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'; principalId = $alice; principalType = 'User'; createdOn = (& $ago 6); createdBy = $bob; updatedOn = ''; updatedBy = '' }
            )
            roleNames         = @(@{ id = '/providers/microsoft.authorization/roledefinitions/8e3af657-a8ff-443c-a75c-2fe8c4bcb635'; roleName = 'Owner' }, @{ id = '/providers/microsoft.authorization/roledefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'; roleName = 'Reader' })
        }
    }
    $script:directory = @{ Error = ''; Objects = @{ $alice = @{ userPrincipalName = 'alice@contoso.example' }; $bob = @{ userPrincipalName = 'bob@contoso.example' } } }
}

Describe 'Azure Admin Console - governance changes' {
    BeforeAll {
        $script:r = InModuleScope 'Azure.Admin.Console' -Parameters @{ R = $script:read; D = $script:directory; P = $script:prod } {
            param($R, $D, $P)
            ConvertTo-AACGovernanceChange -Read $R -Directory $D -Since ([datetime]::UtcNow.AddDays(-30)) -InScope { param([string] $Scope) $Scope -notmatch '^/subscriptions/' -or $Scope -match "^/subscriptions/$P" }.GetNewClosure()
        }
    }

    It 'lists the changes in the window and scope, newest first, with their authors' {
        @($script:r.Changes | ForEach-Object { "$($_.Severity) | $($_.Change) | $($_.Kind) | $($_.Name) | $($_.By)" }) | Should -Be @(
            'Medium | Updated | Policy assignment | Baseline (prod) | dddddddd-0000-0000-0000-000000000009 (deleted)'
            'Medium | Created | Role assignment | ra1 | alice@contoso.example'
            'Info | Created | Policy definition | Deny public IPs | alice@contoso.example'
            'Info | Updated | Initiative | Baseline | bob@contoso.example'
            'Info | Created | Role assignment | ra2 | bob@contoso.example'
            'Medium | Created | Custom role | Contoso Operator | bob@contoso.example'
        )
        $script:r.Changes[0].PSObject.TypeNames | Should -Contain 'AAC.GovernanceChange'
    }

    It 'says what changed and why it matters' {
        ($script:r.Changes | Where-Object Name -EQ 'ra1') | ForEach-Object { "$($_.Detail) | $($_.Note) | $($_.Scope)" } | Should -Be 'Owner to bob@contoso.example (User) | Privileged access granted: Owner. | subscription 11111111-1111-1111-1111-111111111111'
        ($script:r.Changes | Where-Object Name -EQ 'Baseline (prod)').Note | Should -BeLike 'The assignment does not enforce (DoNotEnforce)*'
        "$($script:r.Stats.Changes) $($script:r.Stats.Notable) $($script:r.Stats.Privileged)" | Should -Be '6 3 1'
    }
}

Describe 'Azure Admin Console - Get-AACGovernanceChange' {
    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            if ($Query.Contains('subscriptions')) { return @{ Rows = @{ subscriptions = @(@{ subscriptionId = $script:prod; name = 'sub-prod'; state = 'Enabled'; chain = @(@{ name = 'mg-platform' }) }) }; Errors = @{} } }
            $script:read
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACDirectoryObject -MockWith { $script:directory }
    }

    It 'scopes to the subscriptions and the management groups above them, and filters by kind and author' {
        @(Get-AACGovernanceChange -SubscriptionId $script:prod -NoDisplay).Count | Should -Be 6
        @(Get-AACGovernanceChange -SubscriptionId $script:prod -Kind RoleAssignment -NoDisplay).Name | Should -Be @('ra1', 'ra2')
        @(Get-AACGovernanceChange -SubscriptionId $script:prod -By 'bob*' -NoDisplay).Count | Should -Be 3
        @(Get-AACGovernanceChange -SkipEntra -NoDisplay).Count | Should -Be 7
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Get-AACDirectoryObject -Times 3 -Exactly
    }
}
