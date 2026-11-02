<#
    A made-up Contoso estate for ActivityLog.Tests.ps1, as Resource Manager,
    the Activity Log REST API and a Log Analytics workspace return it:

      sub-prod  sends its Activity Log to workspace law-central (90 days'
                retention) - read from Log Analytics, already summarised:
                  st-prod   written by ada (twice) and a pipeline; ada read
                            its keys (listKeys)
                  kv-prod   ada added a role assignment on it (a child ID)
                  vm-old    nothing in the window, last changed in 2025: idle
                  vm-temp   deleted by the pipeline - not in the inventory
      sub-dev   no export - read from the REST API:
                  app-dev   a guest changed its settings (Started, then
                            Succeeded: one operation); 12 failed restarts
                            by an app
#>
function Get-AACContosoActivityLog {
    $prod = '11111111-1111-1111-1111-111111111111'
    $dev = '22222222-2222-2222-2222-222222222222'
    $id = { param([string] $Sub, [string] $Group, [string] $Type, [string] $Name) "/subscriptions/$Sub/resourceGroups/$Group/providers/$Type/$Name" }
    $ids = @{
        Storage = (& $id $prod 'rg-data' 'Microsoft.Storage/storageAccounts' 'st-prod')
        Vault   = (& $id $prod 'rg-data' 'Microsoft.KeyVault/vaults' 'kv-prod')
        OldVm   = (& $id $prod 'rg-app' 'Microsoft.Compute/virtualMachines' 'vm-old')
        TempVm  = (& $id $prod 'rg-app' 'Microsoft.Compute/virtualMachines' 'vm-temp')
        App     = (& $id $dev 'rg-dev' 'Microsoft.Web/sites' 'app-dev')
    }
    $pipeline = 'aaaaaaaa-0000-0000-0000-00000000c1c1'
    $now = [datetime]::UtcNow
    $summary = {
        param([string] $ResourceId, [string] $Caller, [string] $Operation, [int] $Count, [int] $DaysAgo, [string] $Status = 'Succeeded', [string] $TokenType = '')
        [ordered]@{
            ResourceId = $ResourceId.ToLowerInvariant(); Caller = $Caller; Mirid = ''; AppId = ''; TokenType = $TokenType; Upn = ''; Operation = $Operation; OperationName = $Operation; Status = $Status; Category = 'Administrative'
            Count = $Count; First = $now.AddDays(-$DaysAgo - 1).ToString('o'); Last = $now.AddDays(-$DaysAgo).ToString('o'); CallerIp = '203.0.113.7'
        }
    }
    $event = {
        param([string] $Correlation, [string] $ResourceId, [string] $Caller, [string] $Operation, [string] $Status, [int] $HoursAgo, [hashtable] $Claims = @{}, [string] $Category = 'Administrative')
        @{
            eventTimestamp = $now.AddHours(-$HoursAgo).ToString('o'); caller = $Caller; claims = $Claims; operationName = @{ value = $Operation; localizedValue = $Operation }; status = @{ value = $Status }
            resourceId = $ResourceId; correlationId = $Correlation; operationId = "op-$Correlation"; category = @{ value = $Category }; httpRequest = @{ clientIpAddress = '198.51.100.4' }
        }
    }
    $guest = 'eve_fabrikam.com#EXT#@contoso.onmicrosoft.com'
    $restarts = @(1..12 | ForEach-Object { & $event "r$_" $ids.App $pipeline 'Microsoft.Web/sites/restart/action' 'Failed' (10 + $_) @{ idtyp = 'app'; appid = 'app-1' } })

    @{
        Prod          = $prod
        Dev           = $dev
        Ids           = $ids
        Subscriptions = @(
            @{ subscriptionId = $prod; name = 'sub-prod'; state = 'Enabled'; chain = @() }
            @{ subscriptionId = $dev; name = 'sub-dev'; state = 'Enabled'; chain = @() }
        )
        Settings      = @{
            $prod = @(@{ name = 'to-law'; properties = @{ workspaceId = "/subscriptions/$prod/resourceGroups/rg-ops/providers/Microsoft.OperationalInsights/workspaces/law-central"; logs = @(@{ category = 'Administrative'; enabled = $true }) } })
            $dev  = @()
        }
        Workspace     = @{ id = "/subscriptions/$prod/resourceGroups/rg-ops/providers/Microsoft.OperationalInsights/workspaces/law-central"; name = 'law-central'; properties = @{ customerId = 'c0ffee00-0000-0000-0000-000000000001'; retentionInDays = 90 } }
        Resources     = @{
            $prod = @(
                @{ id = $ids.Storage; name = 'st-prod'; type = 'Microsoft.Storage/storageAccounts'; location = 'uksouth'; tags = @{ CostCenter = 'cc-1' }; createdTime = '2024-01-10T00:00:00Z'; changedTime = $now.AddDays(-2).ToString('o') }
                @{ id = $ids.Vault; name = 'kv-prod'; type = 'Microsoft.KeyVault/vaults'; location = 'uksouth'; tags = @{ CostCenter = 'cc-1' }; createdTime = '2024-01-10T00:00:00Z'; changedTime = '2024-02-01T00:00:00Z' }
                @{ id = $ids.OldVm; name = 'vm-old'; type = 'Microsoft.Compute/virtualMachines'; location = 'uksouth'; tags = @{}; createdTime = '2024-03-01T00:00:00Z'; changedTime = '2025-05-01T00:00:00Z' }
            )
            $dev  = @(
                @{ id = $ids.App; name = 'app-dev'; type = 'Microsoft.Web/sites'; location = 'westeurope'; tags = @{ CostCenter = 'cc-9' }; createdTime = '2025-01-01T00:00:00Z'; changedTime = $now.AddDays(-1).ToString('o') }
            )
        }
        # Log Analytics: Get-AACActivityLogQuery's rows for sub-prod.
        Summary       = @(
            & $summary $ids.Storage 'ada@contoso.example' 'Microsoft.Storage/storageAccounts/write' 2 2
            & $summary $ids.Storage $pipeline 'Microsoft.Storage/storageAccounts/write' 5 3 -TokenType 'app'
            & $summary $ids.Storage 'ada@contoso.example' 'Microsoft.Storage/storageAccounts/listKeys/action' 1 4
            & $summary "$($ids.Vault)/providers/Microsoft.Authorization/roleAssignments/ra-1" 'ada@contoso.example' 'Microsoft.Authorization/roleAssignments/write' 1 6
            & $summary $ids.TempVm $pipeline 'Microsoft.Compute/virtualMachines/delete' 1 8 -TokenType 'app'
        )
        # The REST API: sub-dev's events.
        Events        = @(
            & $event 'g1' $ids.App $guest 'Microsoft.Web/sites/config/write' 'Started' 5
            & $event 'g1' $ids.App $guest 'Microsoft.Web/sites/config/write' 'Succeeded' 4
            & $event 'p1' $ids.App 'Azure Policy' 'Microsoft.Authorization/policies/audit/action' 'Succeeded' 3 @{} 'Policy'
        ) + $restarts
    }
}
