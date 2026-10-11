<#
    Made-up Activity Log events for ResourceError.Tests.ps1 (and the demo), as
    the Activity Log returns them:

      c-auth      sp-pipeline denied Microsoft.Compute/virtualMachines/write
                  on vm1 (a Started and a Failed event)
      c-quota     a deployment failing on a regional cores quota (nested)
      c-policy    an Azure Policy deny, and the write it denied
      c-sku       Standard_D4s_v5 not available in westeurope zone 1
      c-lock      a delete blocked by a lock
      c-throttle  TooManyRequests
      c-odd       an error that isn't JSON
      c-ok        a write that succeeded               -> left out
      c-other     a failure in a subscription not in scope -> left out
#>
function Get-AACContosoResourceError {
    $sub = '11111111-1111-1111-1111-111111111111'
    $other = '99999999-9999-9999-9999-999999999999'
    $now = [datetime]::UtcNow
    $ago = { param([double] $Hours) $now.AddHours(-$Hours).ToString('o', [cultureinfo]::InvariantCulture) }
    $res = { param([string] $Group, [string] $Type, [string] $Name) "/subscriptions/$sub/resourceGroups/$Group/providers/$Type/$Name" }
    $entry = {
        param([string] $Correlation, [double] $Hours, [string] $Status, [string] $Operation, [string] $ResourceId, [string] $Caller, [hashtable] $Properties = @{}, [string] $Category = 'Administrative', [string] $SubStatus = '', [string] $Sub = $sub)
        @{
            correlationId = $Correlation; eventDataId = [guid]::NewGuid().ToString(); eventTimestamp = (& $ago $Hours); subscriptionId = $Sub
            status = @{ value = $Status; localizedValue = $Status }; subStatus = @{ value = $SubStatus; localizedValue = $SubStatus }
            operationName = @{ value = $Operation; localizedValue = "Op: $Operation" }; category = @{ value = $Category }
            resourceId = $ResourceId; resourceGroupName = ($ResourceId -split '/')[4]; resourceType = @{ value = (($ResourceId -split '/providers/')[1] -replace '/[^/]+$', '') }
            caller = $Caller; httpRequest = @{ clientIpAddress = '203.0.113.9' }; authorization = @{ action = $Operation; scope = $ResourceId }; properties = $Properties
        }
    }
    $vm = & $res 'rg-app' 'Microsoft.Compute/virtualMachines' 'vm1'
    $deployment = & $res 'rg-app' 'Microsoft.Resources/deployments' 'main'
    $st = & $res 'rg-data' 'Microsoft.Storage/storageAccounts' 'st1'
    $json = { param($Object) $Object | ConvertTo-Json -Depth 10 -Compress }

    @{
        Sub    = $sub
        Other  = $other
        Names  = @{ $sub = 'sub-prod' }
        Events = @(
            (& $entry 'c-auth' 1.1 'Started' 'Microsoft.Compute/virtualMachines/write' $vm 'sp-pipeline')
            (& $entry 'c-auth' 1 'Failed' 'Microsoft.Compute/virtualMachines/write' $vm 'sp-pipeline' @{ statusCode = 'Forbidden'; statusMessage = (& $json @{ error = @{ code = 'AuthorizationFailed'; message = "The client 'sp-pipeline' with object id 'o1' does not have authorization to perform action 'Microsoft.Compute/virtualMachines/write' over scope '$vm' or the scope is invalid." } }) })
            (& $entry 'c-quota' 2 'Failed' 'Microsoft.Resources/deployments/write' $deployment 'alice@contoso.com' @{ statusCode = 'Conflict'; statusMessage = (& $json @{ status = 'Failed'; error = @{ code = 'DeploymentFailed'; message = 'At least one resource deployment operation failed.'; details = @(@{ code = 'QuotaExceeded'; message = 'Operation could not be completed as it results in exceeding approved Total Regional Cores quota.' }) } }) })
            (& $entry 'c-policy' 3 'Succeeded' 'Microsoft.Authorization/policies/deny/action' $st 'bob@contoso.com' @{ policies = '[]' } 'Policy')
            (& $entry 'c-policy' 3 'Failed' 'Microsoft.Storage/storageAccounts/write' $st 'bob@contoso.com' @{ statusCode = 'Forbidden'; statusMessage = (& $json @{ error = @{ code = 'RequestDisallowedByPolicy'; message = "Resource 'st1' was disallowed by policy 'Deny public storage'." } }) })
            (& $entry 'c-sku' 4 'Failed' 'Microsoft.Compute/virtualMachines/write' $vm 'alice@contoso.com' @{ statusCode = 'Conflict'; statusMessage = (& $json @{ error = @{ code = 'SkuNotAvailable'; message = "The requested VM size Standard_D4s_v5 is currently not available in location 'westeurope' zones '1'." } }) })
            (& $entry 'c-lock' 5 'Failed' 'Microsoft.Storage/storageAccounts/delete' $st 'alice@contoso.com' @{ statusCode = 'Conflict'; statusMessage = (& $json @{ error = @{ code = 'ScopeLocked'; message = "The scope '$st' cannot perform delete operation because following scope(s) are locked." } }) })
            (& $entry 'c-throttle' 6 'Failed' 'Microsoft.Compute/virtualMachines/read' $vm 'sp-monitor' @{ statusCode = 'TooManyRequests' } 'Administrative' 'TooManyRequests')
            (& $entry 'c-odd' 7 'Failed' 'Microsoft.Storage/storageAccounts/write' $st 'alice@contoso.com' @{ statusCode = 'InternalServerError'; statusMessage = 'Something odd happened' })
            (& $entry 'c-ok' 1 'Succeeded' 'Microsoft.Compute/virtualMachines/write' $vm 'alice@contoso.com')
            (& $entry 'c-other' 1 'Failed' 'Microsoft.Compute/virtualMachines/write' $vm 'eve@contoso.com' @{ statusCode = 'Forbidden' } 'Administrative' '' $other)
        )
    }
}
