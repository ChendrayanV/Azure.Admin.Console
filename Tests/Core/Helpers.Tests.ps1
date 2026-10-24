<#
    Unit tests for the small shared helpers: KQL string literals, retry
    delays from a headers dictionary, -TimeRange, the shared Resource Graph
    queries, and Get-AACMember by separate keys.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

Describe 'Azure Admin Console - shared helpers' {
    It 'quotes a KQL string literal, escaping backslashes and single quotes' {
        InModuleScope 'Azure.Admin.Console' {
            ConvertTo-AACKqlLiteral -Text "rg-o'brien" | Should -BeExactly "'rg-o\'brien'"
            ConvertTo-AACKqlLiteral -Text 'C:\temp\' | Should -BeExactly "'C:\\temp\\'"
            ConvertTo-AACKqlLiteral -Text 'RG-App' -Lower | Should -BeExactly "'rg-app'"
            ConvertTo-AACKqlLiteral -Text '' | Should -BeExactly "''"
        }
    }

    It 'reads the retry delay from a headers dictionary as from a response: seconds, a date, the services'' own headers, at most 60' {
        InModuleScope 'Azure.Admin.Console' {
            Get-AACRetryDelay -Headers @{} -Status 200 | Should -Be 5
            Get-AACRetryDelay -Headers @{ 'Retry-After' = '7' } -Status 200 | Should -Be 7
            Get-AACRetryDelay -Headers @{ 'Retry-After' = '999' } -Status 200 | Should -Be 60
            [int](Get-AACRetryDelay -Headers @{ 'Retry-After' = [datetime]::UtcNow.AddSeconds(30).ToString('r') } -Status 200) | Should -BeIn 28, 29, 30
            Get-AACRetryDelay -Headers @{ 'x-ms-user-quota-resets-after' = '00:00:12' } -Status 200 | Should -Be 12
            Get-AACRetryDelay -Headers @{ 'x-ms-ratelimit-microsoft.costmanagement-qpu-retry-after' = '20'; 'Retry-After' = '3' } -Status 429 | Should -Be 20
        }
    }

    It 'turns a -TimeRange into hours and a metric grain' {
        InModuleScope 'Azure.Admin.Console' {
            (Get-AACTimeRange -TimeRange '1h') -join ' ' | Should -Be '1 PT5M'
            (Get-AACTimeRange -TimeRange '1d') -join ' ' | Should -Be '24 PT1H'
            (Get-AACTimeRange -TimeRange '30d') -join ' ' | Should -Be '720 P1D'
        }
    }

    It 'writes the shared Resource Graph queries once' {
        InModuleScope 'Azure.Admin.Console' {
            Get-AACCommonQuery -Kind DefenderPlan -Plan 'KeyVaults' | Should -BeLike "*microsoft.security/pricings' and name =~ 'KeyVaults' | project subscriptionId*"
            Get-AACCommonQuery -Kind DefenderAlert -ResourceType 'microsoft.storage/storageaccounts' -Filter ' | where resourceGroup in~ (''rg-a'')' | Should -BeLike "*contains 'microsoft.storage/storageaccounts' | where resourceGroup in~ ('rg-a') | where todatetime*"
            $workspaces = Get-AACCommonQuery -Kind WorkspaceName
            "$($workspaces.Tenant) $($workspaces.Query)" | Should -Be "True resources | where type =~ 'microsoft.operationalinsights/workspaces' | project id = tolower(id), name"
        }
    }

    It 'reads a member by separate keys - a key may hold a dot - exact case first, then any case' {
        InModuleScope 'Azure.Admin.Console' {
            $row = @{ properties = @{ '@odata.type' = 'user'; Status = @{ code = 'ok' } } }
            Get-AACMember -InputObject $row -Key 'properties', '@odata.type' | Should -Be 'user'
            Get-AACMember -InputObject $row -Key 'Properties', 'status', 'CODE' | Should -Be 'ok'
            Get-AACMember -InputObject $row -Path 'properties.status.code' | Should -Be 'ok'
            Get-AACMember -InputObject $row -Key 'properties', 'missing' | Should -BeNullOrEmpty
        }
    }
}
