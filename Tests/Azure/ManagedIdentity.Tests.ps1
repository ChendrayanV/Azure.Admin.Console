<#
    Unit tests for Get-AACManagedIdentity: made-up managed identities - a
    user-assigned identity shared by 12 apps as Owner, one attached to
    nothing that still holds a role, an empty one, one federated with GitHub
    as Contributor, an AKS kubelet and a policy assignment's user-assigned
    identity; system-assigned identities with Microsoft Graph permissions
    (one that can take over the tenant), and a policy assignment's - and the
    command with Resource Graph, Resource Manager and Microsoft Graph faked.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    $sub = '11111111-1111-1111-1111-111111111111'
    $owner = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'; $reader = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'; $contributor = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
    $ra = { param([string] $Principal, [string] $Role, [string] $Scope = "/subscriptions/$sub") @{ id = "ra-$Principal-$Role"; principalId = $Principal; roleId = "/providers/microsoft.authorization/roledefinitions/$Role"; scope = $Scope } }
    $uaiId = { param([string] $Name) "/subscriptions/$sub/resourcegroups/rg-id/providers/microsoft.managedidentity/userassignedidentities/$Name" }
    $uai = { param([string] $Name) @{ id = (& $uaiId $Name); name = $Name; resourceGroup = 'rg-id'; subscriptionId = $sub; location = 'westeurope'; tags = @{ env = 'prod'; owner = 'team-a' }; principalId = "mi-$($Name -replace '^uai-')"; clientId = "client-$Name" } }
    $sys = { param([string] $Name, [string] $Type, [string] $Principal, [hashtable] $Uses) @{ id = "/subscriptions/$sub/resourcegroups/rg-app/providers/$Type/$Name"; name = $Name; type = $Type; resourceGroup = 'rg-app'; subscriptionId = $sub; location = 'westeurope'; tags = $null; principalId = $Principal; identities = $Uses } }
    $script:sub = $sub
    $script:read = @{
        Errors = @{}
        Rows   = @{
            userIdentities   = @((& $uai 'uai-shared'), (& $uai 'uai-loose'), (& $uai 'uai-empty'), (& $uai 'uai-gh'), (& $uai 'uai-kube'), (& $uai 'uai-policy'))
            systemIdentities = @(
                (& $sys 'func-orders' 'microsoft.web/sites' 'mi-func' @{ (& $uaiId 'uai-shared') = @{} })
                (& $sys 'vm-web-01' 'microsoft.compute/virtualmachines' 'mi-vm' $null)
                (& $sys 'stlogs' 'microsoft.storage/storageaccounts' 'mi-st' $null)
            )
            attached         = @(
                @(1..12 | ForEach-Object { @{ id = "/subscriptions/$sub/resourcegroups/rg-app/providers/microsoft.web/sites/app$_"; identities = @{ (& $uaiId 'uai-shared').ToUpperInvariant() = @{} }; kubelet = '' } })
                @{ id = "/subscriptions/$sub/resourcegroups/rg-aks/providers/microsoft.containerservice/managedclusters/aks-01"; identities = $null; kubelet = (& $uaiId 'uai-kube') }
            )
            policyIdentities = @(
                @{ id = '/providers/microsoft.management/managementgroups/mg-platform/providers/microsoft.authorization/policyassignments/deploy-diag'; name = 'deploy-diag'; displayName = 'Deploy diagnostics'; location = 'westeurope'; scope = '/providers/microsoft.management/managementgroups/mg-platform'; principalId = 'mi-deploydiag'; identities = $null }
                @{ id = "/subscriptions/$sub/providers/microsoft.authorization/policyassignments/tag-inherit"; name = 'tag-inherit'; displayName = 'Inherit tags'; location = 'westeurope'; scope = "/subscriptions/$sub"; principalId = ''; identities = @{ (& $uaiId 'uai-policy') = @{} } }
            )
            roleAssignments  = @((& $ra 'mi-shared' $owner), (& $ra 'mi-loose' $reader "/subscriptions/$sub/resourcegroups/rg-app"), (& $ra 'mi-gh' $contributor), (& $ra 'mi-deploydiag' $contributor '/providers/microsoft.management/managementgroups/mg-platform'))
            roleDefinitions  = @(@{ id = "/providers/microsoft.authorization/roledefinitions/$owner"; roleName = 'Owner' }, @{ id = "/providers/microsoft.authorization/roledefinitions/$reader"; roleName = 'Reader' }, @{ id = "/providers/microsoft.authorization/roledefinitions/$contributor"; roleName = 'Contributor' })
        }
    }
    $script:permission = @{
        'mi-func' = @(@{ resourceId = 'graph-sp'; resourceDisplayName = 'Microsoft Graph'; appRoleId = 'r-user' }, @{ resourceId = 'graph-sp'; resourceDisplayName = 'Microsoft Graph'; appRoleId = 'r-mail' })
        'mi-vm'   = @(@{ resourceId = 'graph-sp'; resourceDisplayName = 'Microsoft Graph'; appRoleId = 'r-ara' })
    }
    $script:graphSp = @{ id = 'graph-sp'; displayName = 'Microsoft Graph'; appRoles = @(@{ id = 'r-user'; value = 'User.Read.All' }, @{ id = 'r-mail'; value = 'Mail.Send' }, @{ id = 'r-ara'; value = 'AppRoleAssignment.ReadWrite.All' }) }
    $script:federated = @{ (& $uaiId 'uai-gh') = @(@{ name = 'gh-main'; properties = @{ issuer = 'https://token.actions.githubusercontent.com'; subject = 'repo:contoso/orders:ref:refs/heads/main' } }) }
    $script:build = {
        InModuleScope 'Azure.Admin.Console' -Parameters @{ R = $script:read; P = $script:permission; G = $script:graphSp; F = $script:federated } {
            param($R, $P, $G, $F)
            ConvertTo-AACManagedIdentity -Read $R -Federated $F -Permission $P -ApiRole @{ 'graph-sp' = @{ Name = $G.displayName; Roles = @{ 'r-user' = 'User.Read.All'; 'r-mail' = 'Mail.Send'; 'r-ara' = 'AppRoleAssignment.ReadWrite.All' } } }
        }
    }
}

Describe 'Azure Admin Console - managed identity list' {
    BeforeAll { $script:r = & $script:build }

    It 'lists every system- and user-assigned identity, the riskiest first' {
        @($script:r.Identities | ForEach-Object { "$($_.Severity) | $($_.Name) | $($_.Kind)" }) | Should -Be @(
            'High | uai-shared | User-assigned'
            'High | vm-web-01 | System-assigned'
            'Medium | func-orders | System-assigned'
            'Medium | Deploy diagnostics | Policy assignment'
            'Medium | uai-gh | User-assigned'
            'Medium | uai-loose | User-assigned'
            'Low | uai-empty | User-assigned'
            'Info | stlogs | System-assigned'
            'Info | uai-kube | User-assigned'
            'Info | uai-policy | User-assigned'
        )
        $script:r.Identities[0].PSObject.TypeNames | Should -Contain 'AAC.ManagedIdentity'
    }

    It 'shows API permissions the portal does not, and the ones that can take over the tenant' {
        $func = $script:r.Identities | Where-Object Name -EQ 'func-orders'
        "$($func.ApiPermissions) | $($func.Permissions) | $($func.PrivilegedPermissions)" | Should -Be '2 | Microsoft Graph: Mail.Send, User.Read.All | Mail.Send'
        $func.Findings | Should -BeLike 'Privileged API permission(s) Mail.Send*also uses user-assigned identit(ies) uai-shared*'
        ($script:r.Identities | Where-Object Name -EQ 'vm-web-01').Findings | Should -BeLike 'Microsoft Graph AppRoleAssignment.ReadWrite.All can take over the tenant*'
        @($script:r.Access | Where-Object Type -EQ 'API permission').Count | Should -Be 3
        @($script:r.Access | Where-Object Type -EQ 'Azure role').Count | Should -Be 4
    }

    It 'counts attachments from resources, AKS kubelets and policy assignments, and reads federated credentials' {
        $shared = $script:r.Identities | Where-Object Name -EQ 'uai-shared'
        "$($shared.AttachedTo) | $($shared.PrivilegedRoles) | $($shared.Tags)" | Should -Be '12 | Owner | env=prod; owner=team-a'
        $shared.Findings | Should -BeLike 'Owner on subscription *Shared by 12 resources*'
        ($script:r.Identities | Where-Object Name -EQ 'uai-kube').AttachedTo | Should -Be 1
        ($script:r.Identities | Where-Object Name -EQ 'uai-policy').AttachedTo | Should -Be 1
        ($script:r.Identities | Where-Object Name -EQ 'uai-loose').Findings | Should -BeLike 'Attached to nothing*still holds access*'
        $gh = $script:r.Identities | Where-Object Name -EQ 'uai-gh'
        "$($gh.FederatedCredentials) | $($gh.FederatedIssuers)" | Should -Be '1 | token.actions.githubusercontent.com'
        $gh.Findings | Should -BeLike '*Federated with token.actions.githubusercontent.com and holds privileged access*'
        "$($script:r.Stats.System) $($script:r.Stats.User) $($script:r.Stats.WithApi) $($script:r.Stats.Unattached) $($script:r.Stats.Federated)" | Should -Be '4 6 2 2 1'
    }

    It 'keeps to the subscriptions in scope, but counts policy assignments above them' {
        $scoped = InModuleScope 'Azure.Admin.Console' -Parameters @{ R = $script:read } { param($R) ConvertTo-AACManagedIdentity -Read $R -InScope @('22222222-2222-2222-2222-222222222222') }
        @($scoped.Identities).Name | Should -Be 'Deploy diagnostics'
        $scoped.Identities[0].ApiPermissions | Should -BeNullOrEmpty
    }
}

Describe 'Azure Admin Console - Get-AACManagedIdentity' {
    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            if ($Query.Contains('subscriptions')) { return @{ Rows = @{ subscriptions = @(@{ subscriptionId = $script:sub; name = 'sub-prod'; state = 'Enabled'; chain = @(@{ name = 'mg-platform' }) }) }; Errors = @{} } }
            @{ Errors = @{}; Rows = @{} + $script:read.Rows }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $answers = @{}
            foreach ($u in $Uri) { $id = $u -replace '/federatedIdentityCredentials\?.*$', ''; $answers[$u] = @{ Error = $null; Items = @(if ($script:federated.Contains($id)) { $script:federated[$id] }) } }
            $answers
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Read-AACGraphQuery -MockWith {
            $data = @{}
            foreach ($key in @($Query.Keys)) { $data[$key] = if ($key -eq 'graph-sp') { $script:graphSp } elseif ($script:permission.Contains($key)) { $script:permission[$key] } else { @() } }
            @{ Data = $data; Errors = @{} }
        }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.example'; TenantId = 't-1'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1) } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'returns every identity, with API permissions and federated credentials read' {
        $all = @(Get-AACManagedIdentity -NoDisplay)
        $all.Count | Should -Be 10
        ($all | Where-Object Name -EQ 'func-orders').Permissions | Should -Be 'Microsoft Graph: Mail.Send, User.Read.All'
        ($all | Where-Object Name -EQ 'uai-gh').FederatedCredentials | Should -Be 1
    }

    It 'filters by kind, name and resource group before reading Microsoft Graph' {
        @(Get-AACManagedIdentity -UserAssigned -NoDisplay).Count | Should -Be 6
        @(Get-AACManagedIdentity -SystemAssigned -NoDisplay).Count | Should -Be 4
        @(Get-AACManagedIdentity -SystemAssigned -UserAssigned -NoDisplay).Count | Should -Be 10
        @(Get-AACManagedIdentity -ResourceGroupName 'rg-app' -NoDisplay).Name | Sort-Object | Should -Be @('func-orders', 'stlogs', 'vm-web-01')
        @(Get-AACManagedIdentity -Name 'func-*' -NoDisplay).Name | Should -Be 'func-orders'
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Read-AACGraphQuery -ParameterFilter { $Query.Count -eq 1 -and $Query.Contains('mi-func') }
    }

    It 'leaves Microsoft Graph out with -SkipEntra' {
        $all = @(Get-AACManagedIdentity -SkipEntra -NoDisplay)
        @($all | Where-Object { $null -ne $_.ApiPermissions }).Count | Should -Be 0
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Read-AACGraphQuery -Times 0 -Exactly
    }

    It 'pipes into Get-AACApplicationPermission by PrincipalId only' {
        $identity = @(Get-AACManagedIdentity -Name 'vm-web-01' -NoDisplay)[0]
        $parameter = (Get-Command -Name Get-AACApplicationPermission).Parameters['Identity']
        $parameter.Aliases | Should -Contain 'PrincipalId'
        # Any other property named like the parameter or an alias could bind first.
        @($identity.PSObject.Properties.Name | Where-Object { $_ -eq 'Identity' -or $parameter.Aliases -contains $_ }) | Should -Be 'PrincipalId'
    }

    It 'writes CSV and HTML reports' {
        $csv = Join-Path -Path $TestDrive -ChildPath 'mi.csv'
        $html = Join-Path -Path $TestDrive -ChildPath 'mi.html'
        Get-AACManagedIdentity -NoDisplay -CsvPath $csv -HtmlPath $html | Out-Null
        Get-Content -LiteralPath $html -Raw | Should -Match 'Access: every Azure role and API permission'
        @(Import-Csv -LiteralPath $csv).Count | Should -Be 10
    }
}
