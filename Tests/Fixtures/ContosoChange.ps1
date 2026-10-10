<#
    A made-up morning of Contoso changes for ChangeHistory.Tests.ps1 (to
    12:00 UTC, 9 Oct 2026), as the Activity Log and Resource Graph return
    them:

      11:00  bob deletes an NSG rule (rg-net)                     High, manual
      10:00  ada reads stdata's keys (listKeys)                   High, manual
      09:00  ada resizes vm-web-1 D2s -> D4s; an Sev1 alert on it at 09:10
             and Resource Health 'Degraded' at 09:15              High (linked), manual
      08:00  eve's write fails                                    left out (unless -IncludeFailed)
      07:00  a pipeline creates stnew                              Low, automation
      06:00  an app deletes kv-old                                  High, automation
      a read, and a Policy event                                    left out
#>
function Get-AACContosoChange {
    $sub = '11111111-1111-1111-1111-111111111111'
    $t = { param([int] $Hour, [int] $Minute = 0) [datetime]::new(2026, 10, 9, $Hour, $Minute, 0, [DateTimeKind]::Utc) }
    $res = { param([string] $Group, [string] $Type, [string] $Name) "/subscriptions/$sub/resourceGroups/$Group/providers/$Type/$Name" }
    $event = {
        param([string] $Correlation, [datetime] $When, [string] $Caller, [string] $Action, [string] $ResourceId, [string] $Status = 'Succeeded', [string] $Category = 'Administrative')
        @(
            @{ correlationId = $Correlation; eventTimestamp = $When.ToString('o'); caller = $Caller; status = @{ value = 'Started' }; category = @{ value = $Category }; operationName = @{ value = $Action; localizedValue = $Action }; authorization = @{ action = $Action; scope = $ResourceId }; resourceId = $ResourceId; httpRequest = @{ clientIpAddress = '203.0.113.7' }; eventDataId = "$Correlation-1" }
            @{ correlationId = $Correlation; eventTimestamp = $When.AddSeconds(30).ToString('o'); caller = $Caller; status = @{ value = $Status }; category = @{ value = $Category }; operationName = @{ value = $Action; localizedValue = $Action }; authorization = @{ action = $Action; scope = $ResourceId }; resourceId = $ResourceId; eventDataId = "$Correlation-2" }
        )
    }
    $vm = & $res 'rg-app' 'Microsoft.Compute/virtualMachines' 'vm-web-1'
    $pipeline = 'aaaaaaaa-0000-0000-0000-00000000c1c1'
    $cleanup = 'bbbbbbbb-0000-0000-0000-00000000dead'
    @{
        Subscription = $sub
        Names        = @{ $sub = 'sub-prod' }
        Events       = @(
            & $event 'c3' (& $t 11) 'bob@contoso.example' 'Microsoft.Network/networkSecurityGroups/securityRules/delete' (& $res 'rg-net' 'Microsoft.Network/networkSecurityGroups' 'nsg-web/securityRules/allow-https')
            & $event 'c4' (& $t 10) 'ada@contoso.example' 'Microsoft.Storage/storageAccounts/listKeys/action' (& $res 'rg-app' 'Microsoft.Storage/storageAccounts' 'stdata')
            & $event 'c1' (& $t 9) 'ada@contoso.example' 'Microsoft.Compute/virtualMachines/write' $vm
            & $event 'c5' (& $t 8) 'eve@contoso.example' 'Microsoft.Web/sites/write' (& $res 'rg-app' 'Microsoft.Web/sites' 'app-web') 'Failed'
            & $event 'c2' (& $t 7) $pipeline 'Microsoft.Storage/storageAccounts/write' (& $res 'rg-app' 'Microsoft.Storage/storageAccounts' 'stnew')
            & $event 'c8' (& $t 6) $cleanup 'Microsoft.KeyVault/vaults/delete' (& $res 'rg-old' 'Microsoft.KeyVault/vaults' 'kv-old')
            & $event 'c6' (& $t 5) 'ada@contoso.example' 'Microsoft.Compute/virtualMachines/read' $vm
            & $event 'c7' (& $t 4) 'Microsoft.PolicyInsights' 'Microsoft.Authorization/policies/audit/action' $vm 'Succeeded' 'Policy'
        )
        Changes      = @(
            @{ id = 'rc1'; at = (& $t 9 0).AddSeconds(20); changeType = 'Update'; resourceId = $vm.ToLowerInvariant(); correlationId = 'c1'; changes = @{ 'properties.hardwareProfile.vmSize' = @{ beforeValue = 'Standard_D2s_v5'; afterValue = 'Standard_D4s_v5'; changeCategory = 'User' }; 'properties.provisioningState' = @{ beforeValue = 'Succeeded'; afterValue = 'Updating'; changeCategory = 'System' } } }
            @{ id = 'rc2'; at = (& $t 7 0).AddSeconds(20); changeType = 'Create'; resourceId = (& $res 'rg-app' 'Microsoft.Storage/storageAccounts' 'stnew').ToLowerInvariant(); correlationId = 'c2'; changes = $null }
        )
        Alerts       = @(@{ id = 'al1'; fired = (& $t 9 10); name = 'CPU over 90%'; severity = 'Sev1'; state = 'Fired'; target = $vm.ToLowerInvariant(); targetGroup = 'rg-app'; signal = 'Metric'; description = 'Percentage CPU > 90' })
        Health       = @(@{ id = 'h1'; resourceId = $vm.ToLowerInvariant(); state = 'Degraded'; summary = 'The VM is responding slowly'; since = (& $t 9 15).ToString('o') })
    }
}
