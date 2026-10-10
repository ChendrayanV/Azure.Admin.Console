<#
    Made-up Contoso recovery for FailoverReadiness.Tests.ps1 (9 Oct 2026,
    12:00 UTC), as Resource Graph and Resource Manager return it:

      vm-a        backed up 3 h ago, restored 20 days ago, replicated
                  (healthy, RPO 2 min, test failover 30 days ago)     -> ready, 100
      vm-b        last backup failed, never restored, not replicated;
                  its vault is locally redundant, soft delete off      -> 15
      vm-c        nothing                                              -> 0
      vm-d        replicated only: warnings, RPO 40 min, never tested  -> 40, at risk
      share-docs  Azure Files, last backup 30 h ago                    -> 45
      vault-geo   GRS, cross-region restore, soft delete, locked immutability
      vault-lrs   LRS, soft delete off, no immutability
      plan-erp    never test-failed over; runbooks: rb-ok (published),
                  rb-draft (edit), rb-gone (missing)
#>
function Get-AACContosoRecovery {
    $sub = '11111111-1111-1111-1111-111111111111'
    $now = [datetime]'2026-10-09T12:00:00Z'
    $res = { param([string] $Group, [string] $Type, [string] $Name) "/subscriptions/$sub/resourcegroups/$Group/providers/$Type/$Name" }
    $vm = { param([string] $Name) @{ id = (& $res 'rg-app' 'microsoft.compute/virtualmachines' $Name); name = $Name; resourceGroup = 'rg-app'; subscriptionId = $sub; location = 'westeurope' } }
    $geo = & $res 'rg-bcdr' 'microsoft.recoveryservices/vaults' 'vault-geo'
    $lrs = & $res 'rg-bcdr' 'microsoft.recoveryservices/vaults' 'vault-lrs'
    $item = { param([string] $Vault, [string] $Name, [string] $Source, [string] $Type, [string] $Status, [datetime] $Last) @{ id = "$Vault/backupfabrics/azure/protectioncontainers/c/protecteditems/$Name"; vault = $Vault; item = $Name; sourceId = $Source; workloadType = $Type; protectionState = 'Protected'; lastBackupStatus = $Status; lastBackupTime = $Last.ToString('o'); policy = 'DefaultPolicy' } }
    $runbook = { param([string] $Name) "/subscriptions/$sub/resourcegroups/rg-bcdr/providers/microsoft.automation/automationaccounts/aa-dr/runbooks/$Name" }
    $action = { param([string] $Name, [string] $Runbook) @{ actionName = $Name; customDetails = @{ instanceType = 'AutomationRunbookActionDetails'; runbookId = $Runbook } } }
    @{
        Now       = $now
        Sub       = $sub
        Names     = @{ $sub = 'sub-prod' }
        Vm        = @((& $vm 'vm-a'), (& $vm 'vm-b'), (& $vm 'vm-c'), (& $vm 'vm-d'))
        Vault     = @(
            @{ id = $geo; name = 'vault-geo'; resourceGroup = 'rg-bcdr'; subscriptionId = $sub; redundancy = 'GeoRedundant'; crossRegionRestore = 'Enabled'; softDelete = 'AlwaysON'; immutability = 'Locked' }
            @{ id = $lrs; name = 'vault-lrs'; resourceGroup = 'rg-bcdr'; subscriptionId = $sub; redundancy = 'LocallyRedundant'; crossRegionRestore = ''; softDelete = 'Disabled'; immutability = '' }
        )
        Items     = @(
            (& $item $geo 'vm-a' (& $res 'rg-app' 'microsoft.compute/virtualmachines' 'vm-a') 'VM' 'Completed' $now.AddHours(-3))
            (& $item $lrs 'vm-b' (& $res 'rg-app' 'microsoft.compute/virtualmachines' 'vm-b') 'VM' 'Failed' $now.AddHours(-30))
            (& $item $geo 'share-docs' (& $res 'rg-data' 'microsoft.storage/storageaccounts' 'stdocs') 'AzureFileShare' 'Completed' $now.AddHours(-30))
            (& $item $geo 'vm-z' (& $res 'rg-other' 'microsoft.compute/virtualmachines' 'vm-z') 'VM' 'Completed' $now.AddHours(-1))
        )
        Restores  = @(@{ id = 'j1'; entity = 'vm-a'; status = 'Completed'; start = $now.AddDays(-20).ToString('o') }, @{ id = 'j2'; entity = 'vm-b'; status = 'Failed'; start = $now.AddDays(-5).ToString('o') })
        Replicas  = @(
            @{ id = 'r1'; vault = $geo; properties = @{ friendlyName = 'vm-a'; replicationHealth = 'Normal'; lastSuccessfulTestFailoverTime = $now.AddDays(-30).ToString('o'); allowedOperations = @('PlannedFailover', 'UnplannedFailover', 'TestFailover'); providerSpecificDetails = @{ fabricObjectId = (& $res 'rg-app' 'microsoft.compute/virtualmachines' 'vm-a'); rpoInSeconds = 120 } } }
            @{ id = 'r2'; vault = $geo; properties = @{ friendlyName = 'vm-d'; replicationHealth = 'Warning'; lastSuccessfulTestFailoverTime = '0001-01-01T00:00:00Z'; allowedOperations = @('UnplannedFailover', 'TestFailover'); providerSpecificDetails = @{ fabricObjectId = (& $res 'rg-app' 'microsoft.compute/virtualmachines' 'vm-d'); rpoInSeconds = 2400 } } }
        )
        Plans     = @(@{ id = "$geo/replicationrecoveryplans/plan-erp"; name = 'plan-erp'; vault = $geo; properties = @{ friendlyName = 'plan-erp'; lastTestFailoverTime = $null; groups = @(@{ startGroupActions = @((& $action 'Stop app' (& $runbook 'rb-ok'))); endGroupActions = @((& $action 'Fix DNS' (& $runbook 'rb-draft')), (& $action 'Notify' (& $runbook 'rb-gone'))) }) } })
        Runbooks  = @{ (& $runbook 'rb-ok') = @{ State = 'Published'; Error = '' }; (& $runbook 'rb-draft') = @{ State = 'Edit'; Error = '' }; (& $runbook 'rb-gone') = @{ State = ''; Error = 'ResourceNotFound: The Resource was not found.' } }
    }
}
