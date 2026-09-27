<#
    Unit tests for Get-AACResourceInventory, the helper behind
    ResourceLocation.Tests.ps1. Azure responses are hand-built JSON parsed
    with ConvertFrom-Json, and every REST/Resource Graph call is mocked, so no
    network call or active Connect-AAC session is required.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

Describe 'Azure Admin Console - resource inventory for the location check' {
    BeforeAll {
        # Keep the real Connect-AAC sign-in (if any); it installs a fake one below.
        $script:aacSavedSession = $global:AACSession
    }

    AfterAll {
        $global:AACSession = $script:aacSavedSession
    }

    BeforeEach {
        $global:AACSession = [pscustomobject]@{
            PSTypeName   = 'AAC.Session'
            Account      = 'tester@example.com'
            TenantId     = 'tenant-1'
            ClientId     = 'client-1'
            Scope        = @('https://management.azure.com/.default')
            AccessToken  = 'fake-token'
            RefreshToken = $null
            ExpiresOn    = (Get-Date).AddHours(1)
            ConnectedAt  = Get-Date
        }

        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACPagedRestMethod -MockWith {
            @('[{"subscriptionId":"11111111-1111-1111-1111-111111111111","displayName":"sub-prod","state":"Enabled"},
                {"subscriptionId":"22222222-2222-2222-2222-222222222222","displayName":"sub-old","state":"Disabled"}]' | ConvertFrom-Json)
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACResourceGraphQuery -MockWith {
            @('[{"id":"/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-app/providers/Microsoft.Storage/storageAccounts/stapp01","name":"stapp01","type":"microsoft.storage/storageaccounts","location":"uksouth","resourceGroup":"rg-app"},
                {"id":"/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-app/providers/Microsoft.Web/sites/app-web01","name":"app-web01","type":"microsoft.web/sites","location":"West Europe","resourceGroup":"rg-app"},
                {"id":"/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-dns/providers/Microsoft.Network/dnszones/contoso.com","name":"contoso.com","type":"microsoft.network/dnszones","resourceGroup":"rg-dns","location":"global"}]' | ConvertFrom-Json)
        }
    }

    It 'queries only Enabled subscriptions and normalizes locations for comparison' {
        $resources = @(InModuleScope 'Azure.Admin.Console' { Get-AACResourceInventory })

        $resources.Count | Should -Be 3
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACResourceGraphQuery -Times 1 -Exactly
        ($resources | Where-Object Name -eq 'app-web01').NormalizedLocation | Should -BeExactly 'westeurope'
        ($resources | Where-Object Name -eq 'app-web01').Location | Should -BeExactly 'West Europe'
        ($resources | Where-Object Name -eq 'stapp01').SubscriptionName | Should -BeExactly 'sub-prod'
        ($resources | Where-Object Name -eq 'contoso.com').NormalizedLocation | Should -BeExactly 'global'
    }

    It 'fails clearly for a subscription the account cannot see or that is not Enabled' {
        { InModuleScope 'Azure.Admin.Console' { Get-AACResourceInventory -SubscriptionId '22222222-2222-2222-2222-222222222222' } } |
            Should -Throw '*not visible to the signed-in account, or not Enabled: 22222222-2222-2222-2222-222222222222*'
    }
}
