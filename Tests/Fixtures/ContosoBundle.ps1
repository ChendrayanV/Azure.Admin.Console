<#
    Made-up resources for DiagnosticBundle.Tests.ps1 (and the demo), as
    Get-AACDiagnosticBundleQuery's Resource Graph queries and the Resource
    Manager calls of Export-AACDiagnosticBundle return them:

      vm1    unavailable, an admin password in its configuration, 2 alerts, an
             Advisor recommendation, a failed write in the Activity Log, a
             diagnostic setting
      st1    an account key inside a connection string, a policy state, a lock,
             no diagnostic settings, no Resource Health (404)
      gone   not found
    The changes couldn't be read (throttled).
    ArmFor answers one Resource Manager URI.
#>
function Get-AACContosoBundle {
    $sub = '11111111-1111-1111-1111-111111111111'
    $vmId = "/subscriptions/$sub/resourceGroups/rg-app/providers/Microsoft.Compute/virtualMachines/vm1"
    $stId = "/subscriptions/$sub/resourceGroups/rg-app/providers/Microsoft.Storage/storageAccounts/st1"
    $vm = $vmId.ToLowerInvariant(); $st = $stId.ToLowerInvariant()
    $armFor = {
        param([string] $Uri)
        if ($Uri -match '/eventtypes/management/') {
            $target = [System.Uri]::UnescapeDataString($Uri) -replace "^.*resourceUri eq '([^']+)'.*$", '$1'
            $items = if ($target -eq $vm) { @(@{ status = @{ value = 'Failed' }; operationName = @{ value = 'write' } }, @{ status = @{ value = 'Succeeded' }; operationName = @{ value = 'start' } }) } else { @() }
            return @{ Status = 200; Error = $null; Body = $null; Items = $items }
        }
        if ($Uri -match '/diagnosticSettings') { if ($Uri -like "$st/*") { return @{ Status = 200; Error = $null; Body = $null; Items = @() } }; return @{ Status = 200; Error = $null; Body = $null; Items = @(@{ name = 'to-la'; properties = @{ workspaceId = '/x/la'; storageAccountId = $null } }) } }
        if ($Uri -match '/locks') { return @{ Status = 200; Error = $null; Body = $null; Items = $(if ($Uri -like "$st/*") { @(@{ name = 'no-delete'; properties = @{ level = 'CanNotDelete' } }) } else { @() }) } }
        if ($Uri -match '/availabilityStatuses') { if ($Uri -like "$st/*") { return @{ Status = 404; Error = 'Resource Health is not supported for this type'; Body = $null; Items = $null } }; return @{ Status = 200; Error = $null; Body = $null; Items = @(@{ properties = @{ availabilityState = 'Unavailable' } }) } }
        @{ Status = 500; Error = 'unexpected'; Body = $null; Items = $null }
    }.GetNewClosure()

    @{
        Sub    = $sub
        Vm     = $vmId
        St     = $stId
        Gone   = "/subscriptions/$sub/resourceGroups/rg-app/providers/Microsoft.Web/sites/gone"
        ArmFor = $armFor
        Read   = @{
            Errors = @{ changes = 'Too many requests' }
            Rows   = @{
                config          = @(
                    @{ id = $vmId; target = $vm; name = 'vm1'; type = 'microsoft.compute/virtualmachines'; resourceGroup = 'rg-app'; subscriptionId = $sub; properties = @{ osProfile = @{ adminUsername = 'azureuser'; adminPassword = 'P@ssw0rd!' }; hardwareProfile = @{ vmSize = 'Standard_B2s' } } }
                    @{ id = $stId; target = $st; name = 'st1'; type = 'microsoft.storage/storageaccounts'; resourceGroup = 'rg-app'; subscriptionId = $sub; properties = @{ primaryEndpoints = @{ blob = 'https://st1.blob.core.windows.net/' }; keySource = 'Microsoft.Storage'; note = 'DefaultEndpointsProtocol=https;AccountName=st1;AccountKey=abc123==;EndpointSuffix=core.windows.net' } }
                )
                health          = @(@{ id = 'h1'; target = $vm; state = 'Unavailable'; reason = 'Unplanned'; summary = 'Down'; since = '2026-10-11T00:00:00Z' }, @{ id = 'h2'; target = $st; state = 'Available' })
                healthEvents    = @()
                advisor         = @(@{ id = 'a1'; target = $vm; category = 'Cost'; impact = 'High'; problem = 'Right-size' })
                defender        = @()
                policy          = @(@{ id = 'p1'; target = $st; assignment = 'Deny public'; effect = 'audit' })
                alerts          = @(@{ id = 'al1'; target = $vm; name = 'CPU high'; severity = 'Sev2' }, @{ id = 'al2'; target = $vm; name = 'Heartbeat'; severity = 'Sev1' })
                changes         = @()
                roleAssignments = @()
            }
        }
    }
}
