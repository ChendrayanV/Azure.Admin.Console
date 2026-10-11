<#
    Made-up Resource Health and Service Health for ResourceHealth.Tests.ps1,
    as Azure Resource Graph returns them (Get-AACResourceHealthQuery):

      vm-down     Unavailable for 5 hours (platform, unplanned), hit by
                  service issue TRK-1; rebooted by the platform 5 hours ago
      sql-slow    Degraded for 1 hour
      vm-ok       Available; live-migrated 2 days ago
      kv-ok       Available
      st-unknown  Unknown
      vm-other    a subscription not in scope (left out)
    Service Health: TRK-1 an active service issue in West Europe (Virtual
    Machines), TRK-2 planned maintenance resolved yesterday; TRK-9 in the
    other subscription.
    History of vm-down: Available from 100 hours ago, Unavailable 12-10 and
    5-0 hours ago: over a day, 17 of 24 hours available, 3 changes.
#>
function Get-AACContosoHealth {
    $sub = '11111111-1111-1111-1111-111111111111'
    $other = '99999999-9999-9999-9999-999999999999'
    $now = [datetime]::UtcNow
    $ago = { param([double] $Hours) $now.AddHours(-$Hours).ToString('o', [cultureinfo]::InvariantCulture) }
    $res = { param([string] $Group, [string] $Type, [string] $Name, [string] $Sub = $sub) "/subscriptions/$Sub/resourcegroups/$Group/providers/$Type/$Name" }
    $vmDown = & $res 'rg-app' 'microsoft.compute/virtualmachines' 'vm-down'
    $vmOk = & $res 'rg-app' 'microsoft.compute/virtualmachines' 'vm-ok'
    $sql = & $res 'rg-data' 'microsoft.sql/servers/sql-srv/databases' 'sql-slow'
    $status = {
        param([string] $Id, [string] $State, [double] $Hours, [string] $Reason = '', [string] $Summary = '', [string] $Sub = $sub)
        @{ id = "$Id/providers/Microsoft.ResourceHealth/availabilityStatuses/current"; resourceId = $Id; subscriptionId = $Sub; location = 'westeurope'; state = $State; reason = $Reason; heading = ''; summary = $Summary; since = (& $ago $Hours); chronicity = 'Persistent'; eta = ''; category = ''; context = '' }
    }

    @{
        Subscription = $sub
        VmDown       = $vmDown
        Names        = @{ $sub = 'sub-prod' }
        Read         = @{
            Errors = @{}
            Rows   = @{
                statuses = @(
                    (& $status $vmOk 'Available' 400)
                    (& $status (& $res 'rg-data' 'microsoft.keyvault/vaults' 'kv-ok') 'Available' 900)
                    (& $status $sql 'Degraded' 1 'Unplanned' 'The database is <b>slow</b>.')
                    (& $status (& $res 'rg-data' 'microsoft.storage/storageaccounts' 'st-unknown') 'Unknown' 2)
                    (& $status $vmDown 'Unavailable' 5 'Unplanned' 'We&#39;re sorry, your VM is unavailable.')
                    (& $status (& $res 'rg-x' 'microsoft.compute/virtualmachines' 'vm-other' $other) 'Unavailable' 50 '' '' $other)
                )
                events   = @(
                    @{ id = 'e1'; resourceId = $vmDown; annotation = 'VirtualMachineRestarted'; summary = 'Rebooted by the platform'; reason = ''; occurred = (& $ago 5); context = 'Platform Initiated'; category = 'Unplanned'; impact = 'Downtime' }
                    @{ id = 'e2'; resourceId = $vmOk; annotation = 'LiveMigrationSucceeded'; summary = 'Live migrated'; reason = ''; occurred = (& $ago 48); context = 'Platform Initiated'; category = 'Planned'; impact = 'Freeze' }
                    @{ id = 'e3'; resourceId = $sql; annotation = 'Old'; summary = 'Too old'; reason = ''; occurred = (& $ago 400); context = ''; category = ''; impact = '' }
                )
                service  = @(
                    @{ id = 's1'; subscriptionId = $sub; trackingId = 'TRK-2'; eventType = 'PlannedMaintenance'; status = 'Resolved'; level = 'Informational'; heading = 'Maintenance on SQL'; summary = '<p>Done.</p>'; started = (& $ago 30); mitigated = (& $ago 24); updated = (& $ago 24); impact = @(@{ ImpactedService = 'SQL Database'; ImpactedRegions = @(@{ ImpactedRegion = 'North Europe' }) }) }
                    @{ id = 's2'; subscriptionId = $sub; trackingId = 'TRK-1'; eventType = 'ServiceIssue'; status = 'Active'; level = 'Error'; heading = 'Virtual Machines - West Europe'; summary = 'Investigating.'; started = (& $ago 6); mitigated = ''; updated = (& $ago 1); impact = @(@{ ImpactedService = 'Virtual Machines'; ImpactedRegions = @(@{ ImpactedRegion = 'West Europe' }) }) }
                    @{ id = 's9'; subscriptionId = $other; trackingId = 'TRK-9'; eventType = 'ServiceIssue'; status = 'Active'; level = 'Error'; heading = 'Elsewhere'; summary = ''; started = (& $ago 2); mitigated = ''; updated = (& $ago 1); impact = @() }
                )
                impacted = @(@{ id = 'i1'; trackingId = 'TRK-1'; resourceId = $vmDown; region = 'westeurope' })
            }
        }
        History      = @{
            $vmDown = @(
                @{ properties = @{ availabilityState = 'Unavailable'; occuredTime = (& $ago 5) } }
                @{ properties = @{ availabilityState = 'Available'; occuredTime = (& $ago 10) } }
                @{ properties = @{ availabilityState = 'Unavailable'; occuredTime = (& $ago 12) } }
                @{ properties = @{ availabilityState = 'Available'; occuredTime = (& $ago 100) } }
            )
        }
    }
}
