<#
    Unit tests for New-AACApplicationPermission: an enterprise application
    given rights over specific Entra groups only - an administrative unit,
    a custom (or built-in) role, a role assignment scoped to the unit -
    planned, applied and verified against a faked Microsoft Graph that keeps
    what is written (Fixtures\ContosoApplicationPermission.ps1).
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    . (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Fixtures/ContosoApplicationPermission.ps1')
    $script:capture = {
        param([scriptblock] $Render)
        $real = [Spectre.Console.AnsiConsole]::Console
        $buffer = [System.IO.StringWriter]::new()
        $settings = [Spectre.Console.AnsiConsoleSettings]::new()
        $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer)
        $settings.Ansi = [Spectre.Console.AnsiSupport]::No
        $settings.Enrichment.UseDefaultEnrichers = $false
        $console = [Spectre.Console.AnsiConsole]::Create($settings)
        $console.Profile.Width = 170
        $console.Profile.Capabilities.Unicode = $false
        try { [Spectre.Console.AnsiConsole]::Console = $console; $output = @(& $Render) }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
}

Describe 'Azure Admin Console - New-AACApplicationPermission' {
    BeforeEach {
        $script:tenant = Get-AACContosoApplicationPermission
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACHttp -MockWith { Invoke-AACContosoEntraGraph -State $script:tenant -Method $Method -Uri $Uri -Body $Body }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Start-Sleep -MockWith { }
    }

    It 'plans the unit, the custom role and the scoped assignment with -WhatIf - and writes nothing' {
        $result = New-AACApplicationPermission -ServicePrincipal 'My-Enterprise-App' -Group 'SG-Group-One', 'SG-Group-Two' -WhatIf -NoDisplay
        $result.Status | Should -Be 'Planned'
        @($result.Changes | ForEach-Object { "$($_.Action) | $($_.Resource)" }) | Should -Be @(
            'Create | Administrative unit AU-My-Enterprise-App-Managed-Groups'
            'Add | Group SG-Group-One to the unit'
            'Add | Group SG-Group-Two to the unit'
            'Create | Role Group access (scoped) - My-Enterprise-App'
            'Assign | Role assignment on AU-My-Enterprise-App-Managed-Groups'
        )
        $result.Actions | Should -Be @('microsoft.directory/groups/standard/read', 'microsoft.directory/groups/members/read', 'microsoft.directory/groups/members/update')
        ($result.Findings | Where-Object Severity -EQ 'High').Finding | Should -Be 'Tenant-wide Graph permission GroupMember.ReadWrite.All'
        $script:tenant.Writes.Count | Should -Be 0
    }

    It 'applies in order - the new IDs in place of the placeholders - verifies, and plans nothing the second time' {
        $result = New-AACApplicationPermission -ServicePrincipal 'My-Enterprise-App' -Group 'SG-Group-One', 'SG-Group-Two' -RemoveTenantWidePermission -Force -NoDisplay
        $result.Status | Should -Be 'Applied'
        @($result.Applied.Status | Select-Object -Unique) | Should -Be 'Applied'
        $result.Verification | Should -BeNullOrEmpty
        $unit = $script:tenant.AdministrativeUnits[0]
        $result.AdministrativeUnitId | Should -Be $unit.id
        @($script:tenant.UnitMembers[$unit.id].displayName) | Should -Be @('SG-Group-One', 'SG-Group-Two')
        $role = @($script:tenant.RoleDefinitions | Where-Object { -not $_.isBuiltIn })[0]
        $assignment = $script:tenant.RoleAssignments[0]
        "$($assignment.principalId) $($assignment.roleDefinitionId) $($assignment.directoryScopeId)" | Should -Be "aaaaaaaa-0000-0000-0000-0000000000a1 $($role.id) /administrativeUnits/$($unit.id)"
        @($script:tenant.AppRoleAssignments.id) | Should -Be 'assignment-2' -Because 'only the tenant-wide group permission is removed, not User.Read.All'
        @($script:tenant.Writes | ForEach-Object { "$($_.Method) $($_.Path)" }) | Should -Not -Contain 'Post /directory/administrativeUnits/{au}/members/$ref'

        $again = New-AACApplicationPermission -ServicePrincipal 'My-Enterprise-App' -Group 'SG-Group-One', 'SG-Group-Two' -Force -NoDisplay
        $again.Status | Should -Be 'NoChanges'
        $again.Findings | Should -BeNullOrEmpty
    }

    It 'updates a custom role whose actions differ, uses a built-in role as it is, and finds the application by its ID' {
        $null = New-AACApplicationPermission -ServicePrincipal 'My-Enterprise-App' -Group 'SG-Group-One' -Force -NoDisplay
        $read = New-AACApplicationPermission -ServicePrincipal 'bbbbbbbb-0000-0000-0000-0000000000b1' -Group 'cccccccc-0000-0000-0000-000000000001' -Access MemberRead -WhatIf -NoDisplay
        @($read.Changes | Where-Object Action -NE 'NoChange' | ForEach-Object { "$($_.Action) | $($_.Resource)" }) | Should -Be 'Update | Role Group access (scoped) - My-Enterprise-App'
        $builtIn = New-AACApplicationPermission -ServicePrincipal 'My-Enterprise-App' -Group 'SG-Group-One' -RoleName 'Groups Administrator' -Force -NoDisplay
        @($builtIn.Applied | ForEach-Object { "$($_.Action) | $($_.Resource)" }) | Should -Be 'Assign | Role assignment on AU-My-Enterprise-App-Managed-Groups'
        $script:tenant.RoleAssignments[-1].roleDefinitionId | Should -Be 'fdd7a751-b60b-444a-984c-02652fe8fa1c'
        @($script:tenant.RoleDefinitions | Where-Object { $_.displayName -eq 'Groups Administrator' }).Count | Should -Be 1
    }

    It 'says what undoes the scope or won''t work, and stops on an ambiguous or missing name' {
        $plan = New-AACApplicationPermission -ServicePrincipal 'My-Enterprise-App' -Group 'SG-Group-One', 'SG-Dynamic' -WhatIf -NoDisplay
        @($plan.Findings | ForEach-Object { "$($_.Severity) | $($_.Finding)" }) | Should -Contain 'Medium | Dynamic group'
        { New-AACApplicationPermission -ServicePrincipal 'func-twins' -Group 'SG-Group-One' -WhatIf -NoDisplay } | Should -Throw '*found 2 service principals named*'
        { New-AACApplicationPermission -ServicePrincipal 'Nope' -Group 'SG-Group-One' -WhatIf -NoDisplay } | Should -Throw '*no enterprise application or managed identity named*'
        { New-AACApplicationPermission -ServicePrincipal 'My-Enterprise-App' -Group 'SG-Nope' -WhatIf -NoDisplay } | Should -Throw "*found no group 'SG-Nope'*"
        { New-AACApplicationPermission -ServicePrincipal 'My-Enterprise-App' -Group 'SG-Group-One' -AllowedResourceAction 'microsoft.directory/users/password/update' -WhatIf -NoDisplay } | Should -Throw '*give group actions only*'
        $script:tenant.Writes.Count | Should -Be 0
    }

    It 'stops at the first failure, says what was applied, and shows the plan at the prompt' {
        $text = (& $script:capture { New-AACApplicationPermission -ServicePrincipal 'My-Enterprise-App' -Group 'SG-Group-One' -WhatIf }).Text
        foreach ($expected in 'Application permission', 'Administrative unit AU-My-Enterprise-App-Managed-Groups', 'Tenant-wide Graph permission GroupMember.ReadWrite.All') { $text | Should -BeLike "*$expected*" }

        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACHttp -ParameterFilter { $Method -eq 'Post' -and $Uri -like '*roleDefinitions' } -MockWith { $e = [System.Exception]::new('Insufficient privileges to complete the operation.'); $e.Data['StatusCode'] = 403; throw $e }
        { New-AACApplicationPermission -ServicePrincipal 'My-Enterprise-App' -Group 'SG-Group-One' -Force -NoDisplay } | Should -Throw '*Role Group access (scoped) - My-Enterprise-App couldn''t be changed: Insufficient privileges*'
        $script:tenant.AdministrativeUnits.Count | Should -Be 1 -Because 'what was applied before the failure stays'
        $script:tenant.RoleAssignments.Count | Should -Be 0
    }
}

Describe 'Azure Admin Console - Get-AACApplicationPermission' {
    BeforeAll {
        . (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Fixtures/ContosoApplicationGrant.ps1')
    }
    BeforeEach {
        $script:grant = Get-AACContosoApplicationGrant
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Read-AACGraphQuery -MockWith { Get-AACContosoApplicationGrantAnswer -Data $script:grant -Query $Query }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACDirectoryObject -MockWith { $found = @{}; foreach ($i in $Id) { if ($script:grant.Objects.Contains($i)) { $found[$i] = $script:grant.Objects[$i] } }; @{ Objects = $found; Error = '' } }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAzureRoleAssignment -MockWith { $found = @{}; foreach ($i in $PrincipalId) { if ($script:grant.Azure.Contains($i)) { $found[$i] = $script:grant.Azure[$i] } }; @{ Assignments = $found; Errors = @() } }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith { @{ Rows = @{ identity = @(@{ principalId = 'a1a1a1a1-0000-0000-0000-000000000001' }) }; Errors = @{} } }
    }

    It 'lists every kind of permission - API, delegated, directory roles with their scope, through groups, Azure, owned, not granted' {
        $rows = @(Get-AACApplicationPermission -Identity 'My-Enterprise-App' -NoDisplay)
        $have = @($rows | ForEach-Object { "$($_.Kind) | $($_.Api) | $($_.Permission) | $($_.Scope) | $($_.Via)" })
        foreach ($expected in @(
                'Application permission | Microsoft Graph | GroupMember.ReadWrite.All | Tenant | Direct'
                'Application permission | Microsoft Graph | User.Read.All | Tenant | Direct'
                'Delegated permission | Microsoft Graph | Mail.Send | All users (admin consent) | Direct'
                'Delegated permission | Microsoft Graph | User.Read | All users (admin consent) | Direct'
                'Directory role | Microsoft Entra ID | Group access (scoped) - My-Enterprise-App | administrative unit AU-Apps | Direct'
                'Directory role | Microsoft Entra ID | Groups Administrator | Tenant | Direct'
                'Directory role | Microsoft Entra ID | Application Administrator | Tenant | group GRP-Role'
                'Azure role | Azure Resource Manager | Contributor | subscription Contoso Production | Direct'
                'Azure role | Azure Resource Manager | Reader | resource group rg-app (Contoso Production) | group GRP-Plain'
                'Owner | Microsoft Entra ID | Other-App | application | Direct'
                'Group membership | Microsoft Entra ID | GRP-Role | group | Direct'
                'Requested (not granted) | Microsoft Graph | Sites.Read.All | Application permission | App registration'
                'Requested (not granted) | Microsoft Graph | Files.Read | Delegated permission | App registration'
            )) { $have | Should -Contain $expected }
        @($rows | Where-Object Kind -EQ 'Requested (not granted)').Count | Should -Be 2 -Because 'the permissions that were granted are not listed as requested'
        ($rows | Where-Object Permission -Like 'Group access*').Detail | Should -Be 'Covers: SG-Group-One - Custom role: microsoft.directory/groups/members/update'
        $rows[0].PSObject.TypeNames | Should -Contain 'AAC.ApplicationPermissionEntry'
    }

    It 'finds the privileged ones, and says what couldn''t be read without failing' {
        $findings = @(Get-AACApplicationPermission -Identity 'My-Enterprise-App' -View Finding -NoDisplay | ForEach-Object { "$($_.Severity) | $($_.Item) | $($_.Finding)" })
        foreach ($expected in @(
                'High | Microsoft Graph GroupMember.ReadWrite.All | Privileged application permission'
                'High | Groups Administrator | Privileged directory role on the whole tenant'
                'High | Application Administrator | Privileged directory role on the whole tenant'
                'Medium | Microsoft Graph Mail.Send | Privileged delegated permission for everyone'
                'Medium | Contributor on subscription Contoso Production | Contributor on a whole subscription or more'
                'Medium | Other-App | Owns another application'
            )) { $findings | Should -Contain $expected }
        $findings | Should -Not -Contain 'Medium | Directory Readers | Directory role on the whole tenant'
        @($findings | Where-Object { $_ -like '*User.Read.All*' }).Count | Should -Be 0
        $text = (& $script:capture { Get-AACApplicationPermission -Identity 'My-Enterprise-App' -NoPaging }).Text
        foreach ($expected in 'Application permissions', 'GroupMember.ReadWrite.All', 'administrative unit AU-Apps', "PIM-eligible directory roles weren't read: the sign-in's Microsoft Graph token has no RoleManagement.Read.Directory") { $text | Should -BeLike "*$expected*" }
    }

    It 'finds the principal by object ID, application ID, app registration ID or managed identity resource ID - and stops on an ambiguous name' {
        foreach ($identity in 'a1a1a1a1-0000-0000-0000-000000000001', 'e1e1e1e1-0000-0000-0000-000000000001', 'a9a9a9a9-0000-0000-0000-000000000009', '/subscriptions/s-1/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-app') {
            (Get-AACApplicationPermission -Identity $identity -View Summary -NoDisplay).Principal | Should -Be 'My-Enterprise-App'
        }
        { Get-AACApplicationPermission -Identity 'func-twins' -NoDisplay } | Should -Throw '*found 2 service principals named*'
        { Get-AACApplicationPermission -Identity 'Nope' -NoDisplay } | Should -Throw '*no enterprise application or managed identity named*'
        $summary = @('My-Enterprise-App', 'Nope' | Get-AACApplicationPermission -View Summary -NoDisplay)
        $summary.Count | Should -Be 1 -Because 'one that can''t be found doesn''t stop the others'
        "$($summary.ApplicationPermissions) $($summary.DelegatedPermissions) $($summary.DirectoryRoles) $($summary.AzureRoles) $($summary.NotGranted)" | Should -Be '2 2 4 2 2'
    }

    It 'leaves Azure out with -SkipAzure, and writes the CSV and an HTML report' {
        @(Get-AACApplicationPermission -Identity 'My-Enterprise-App' -SkipAzure -NoDisplay | Where-Object Kind -EQ 'Azure role').Count | Should -Be 0
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAzureRoleAssignment -Times 0 -Exactly
        $csv = Join-Path $TestDrive 'perm.csv'; $html = Join-Path $TestDrive 'perm.html'
        $null = & $script:capture { Get-AACApplicationPermission -Identity 'My-Enterprise-App' -CsvPath $csv -HtmlPath $html }
        @(Import-Csv -LiteralPath $csv).Count | Should -BeGreaterThan 10
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.tables.id) | Should -Be @('permissions', 'findings', 'applications')
    }
}
