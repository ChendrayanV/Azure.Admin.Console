<#
    Unit tests for Get-AACServicePrincipalInsight: made-up service
    principals with Azure roles - an in-house app with expiring and
    long-lived secrets, another tenant's app as Owner, an app with only
    expired credentials, system-, user- and policy-assigned identities, an
    unattached and an over-shared user-assigned identity - and the command
    with Resource Graph and Microsoft Graph faked.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    $sub = '11111111-1111-1111-1111-111111111111'
    $now = [datetime]::UtcNow
    $iso = { param([int] $Days) $now.AddDays($Days).ToString('o') }
    $owner = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'; $reader = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
    $ra = { param([string] $Principal, [string] $Role, [string] $Scope = "/subscriptions/$sub") @{ id = "ra-$Principal-$Role"; principalId = $Principal; roleId = "/providers/microsoft.authorization/roledefinitions/$Role"; scope = $Scope } }
    $sp = { param([string] $Name, [string] $Type, [string] $Tenant = 't-1', [string[]] $Alt = @()) @{ '@odata.type' = '#microsoft.graph.servicePrincipal'; displayName = $Name; servicePrincipalType = $Type; appId = "app-$Name"; appOwnerOrganizationId = $Tenant; alternativeNames = $Alt; passwordCredentials = @(); keyCredentials = @() } }
    $uai = { param([string] $Name) "/subscriptions/$sub/resourcegroups/rg-id/providers/microsoft.managedidentity/userassignedidentities/$Name" }
    $script:sub = $sub
    $script:read = @{
        Errors = @{}
        Rows   = @{
            roleAssignments = @(
                (& $ra 'sp-orders' $reader), (& $ra 'sp-vendor' $owner), (& $ra 'sp-old' $reader), (& $ra 'mi-vm' $reader)
                (& $ra 'mi-loose' $reader), (& $ra 'mi-shared' $owner), (& $ra 'mi-policy' 'b24988ac-6180-42a0-ab88-20f7382dd24c' '/providers/microsoft.management/managementgroups/mg-platform'), (& $ra 'p-deleted' $owner)
            )
            roleDefinitions = @(@{ id = "/providers/microsoft.authorization/roledefinitions/$owner"; roleName = 'Owner' }, @{ id = "/providers/microsoft.authorization/roledefinitions/$reader"; roleName = 'Reader' }, @{ id = '/providers/microsoft.authorization/roledefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c'; roleName = 'Contributor' })
            userIdentities  = @(@{ id = (& $uai 'uai-loose'); name = 'uai-loose'; principalId = 'mi-loose' }, @{ id = (& $uai 'uai-shared'); name = 'uai-shared'; principalId = 'mi-shared' })
            attached        = @(1..12 | ForEach-Object { @{ id = "/subscriptions/$sub/resourcegroups/rg/providers/microsoft.web/sites/app$_"; identities = @{ (& $uai 'uai-shared').ToUpperInvariant() = @{} } } })
        }
    }
    $script:directory = @{ Error = ''; Objects = @{
            'sp-orders' = (& $sp 'orders-api' 'Application')
            'sp-vendor' = (& $sp 'Vendor Backup' 'Application' 't-vendor')
            'sp-old'    = (& $sp 'old-batch' 'Application')
            'mi-vm'     = (& $sp 'vm-web-01' 'ManagedIdentity' 't-1' @('isExplicit=False', "/subscriptions/$sub/resourcegroups/rg/providers/Microsoft.Compute/virtualMachines/vm-web-01"))
            'mi-loose'  = (& $sp 'uai-loose' 'ManagedIdentity' 't-1' @('isExplicit=True', (& $uai 'uai-loose')))
            'mi-shared' = (& $sp 'uai-shared' 'ManagedIdentity' 't-1' @('isExplicit=True', (& $uai 'uai-shared')))
            'mi-policy' = (& $sp 'deploy-diag' 'ManagedIdentity' 't-1' @('isExplicit=False', '/providers/Microsoft.Management/managementGroups/mg-platform/providers/Microsoft.Authorization/policyAssignments/deploy-diag'))
        } }
    $script:apps = @{
        'app-orders-api' = @{ appId = 'app-orders-api'; passwordCredentials = @(@{ startDateTime = (& $iso -700); endDateTime = (& $iso 12) }, @{ startDateTime = (& $iso -10); endDateTime = (& $iso 720) }); keyCredentials = @() }
        'app-old-batch'  = @{ appId = 'app-old-batch'; passwordCredentials = @(@{ startDateTime = (& $iso -400); endDateTime = (& $iso -30) }); keyCredentials = @() }
    }
    $script:build = { InModuleScope 'Azure.Admin.Console' -Parameters @{ R = $script:read; D = $script:directory; A = $script:apps } { param($R, $D, $A) ConvertTo-AACServicePrincipalInsight -Read $R -Directory $D -Application $A -TenantId 't-1' } }
}

Describe 'Azure Admin Console - service principal insight' {
    BeforeAll { $script:r = & $script:build }

    It 'tells each kind apart and puts the riskiest first' {
        @($script:r.Principals | ForEach-Object { "$($_.Severity) | $($_.ServicePrincipal) | $($_.Kind)" }) | Should -Be @(
            'High | Vendor Backup | Application (external)'
            'Medium | old-batch | Application'
            'Medium | uai-loose | Managed identity (user-assigned)'
            'Medium | uai-shared | Managed identity (user-assigned)'
            'Low | orders-api | Application'
            'Info | deploy-diag | Managed identity (policy assignment)'
            'Info | vm-web-01 | Managed identity (system-assigned: microsoft.compute/virtualmachines)'
        )
        $script:r.Principals[0].PSObject.TypeNames | Should -Contain 'AAC.ServicePrincipalInsight'
    }

    It 'shows roles, attachments and credentials, and says why each matters' {
        $orders = $script:r.Principals | Where-Object ServicePrincipal -EQ 'orders-api'
        "$($orders.Credentials) | $($orders.NextExpiry.ToString('yyyy-MM-dd'))" | Should -Be "2 secret(s), 0 certificate(s) | $([datetime]::UtcNow.AddDays(12).ToString('yyyy-MM-dd'))"
        $orders.Findings | Should -BeLike 'A secret expires in 12 day(s)*A client secret is valid for more than a year*'
        ($script:r.Principals | Where-Object ServicePrincipal -EQ 'Vendor Backup').Findings | Should -BeLike "Another tenant's application holds Owner*"
        ($script:r.Principals | Where-Object ServicePrincipal -EQ 'old-batch').Findings | Should -BeLike 'Every credential has expired*'
        $shared = $script:r.Principals | Where-Object ServicePrincipal -EQ 'uai-shared'
        "$($shared.AttachedResources) | $($shared.PrivilegedRoles)" | Should -Be '12 | Owner'
        $shared.Findings | Should -BeLike 'Shared by 12 resources with Owner*'
        ($script:r.Principals | Where-Object ServicePrincipal -EQ 'uai-loose').AttachedResources | Should -Be 0
        @($script:r.Principals | Where-Object PrincipalId -EQ 'p-deleted').Count | Should -Be 0
        "$($script:r.Stats.External) $($script:r.Stats.Managed) $($script:r.Stats.Expiring)" | Should -Be '1 4 1'
    }
}

Describe 'Azure Admin Console - Get-AACServicePrincipalInsight' {
    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            if ($Query.Contains('subscriptions')) { return @{ Rows = @{ subscriptions = @(@{ subscriptionId = $script:sub; name = 'sub-prod'; state = 'Enabled'; chain = @(@{ name = 'mg-platform' }) }) }; Errors = @{} } }
            @{ Errors = @{}; Rows = @{} + $script:read.Rows }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACDirectoryObject -MockWith { $script:directory }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Read-AACGraphQuery -MockWith { @{ Data = @{ apps0 = @($script:apps.Values) }; Errors = @{} } }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.example'; TenantId = 't-1'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1) } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'reads the in-house app registrations only, and filters by kind' {
        @(Get-AACServicePrincipalInsight -NoDisplay).Count | Should -Be 7
        @(Get-AACServicePrincipalInsight -Kind ExternalApplication -NoDisplay).ServicePrincipal | Should -Be 'Vendor Backup'
        @(Get-AACServicePrincipalInsight -Kind ManagedIdentity -NoDisplay).Count | Should -Be 4
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Read-AACGraphQuery -ParameterFilter { $Query['apps0'] -match "appId in \('app-old-batch','app-orders-api'\)" }
    }
}
