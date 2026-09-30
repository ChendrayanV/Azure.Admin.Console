<#
    Made-up Microsoft.Compute SKUs, vCPU usage and zone mappings for UK
    South in the Contoso sub-corp-apps subscription, and an AKS cluster, as
    the REST APIs and Azure Resource Graph return them (hashtables), for
    SkuAvailability.Tests.ps1:

      Standard_D4s_v5    zones 1-3, the cluster's system pool
      Standard_D2s_v5    zones 1-3, zone 3 restricted for the subscription
      Standard_E8s_v5    zones 1-3; its family has 2 vCPUs free (8 of 10 used)
      Standard_B1s       1 vCPU: fine for a VM, not for AKS
      Standard_D4ps_v5   Arm64, zones 1 and 2 only
      Standard_M8ms      no availability zones here
      Standard_NC24ads_A100_v4  not offered to the subscription here
    plus a disk SKU, which isn't a VM size.
#>
function Get-AACContosoSku {
    $corp = '22222222-2222-2222-2222-222222222222'
    $vm = {
        param($Name, $Family, [int] $VCpus, [double] $Memory, [string[]] $Zones, [object[]] $Restrictions = @(), $Arch = 'x64')
        @{
            resourceType = 'virtualMachines'; name = $Name; tier = 'Standard'; family = $Family; locations = @('UKSouth')
            locationInfo = @(@{ location = 'UKSouth'; zones = $Zones; zoneDetails = @() })
            capabilities = @(
                @{ name = 'vCPUs'; value = "$VCpus" }, @{ name = 'MemoryGB'; value = "$Memory" }, @{ name = 'CpuArchitectureType'; value = $Arch }
                @{ name = 'EphemeralOSDiskSupported'; value = 'True' }, @{ name = 'AcceleratedNetworkingEnabled'; value = 'True' }, @{ name = 'PremiumIO'; value = 'True' }
                @{ name = 'LowPriorityCapable'; value = 'True' }, @{ name = 'MaxDataDiskCount'; value = '8' }, @{ name = 'HyperVGenerations'; value = 'V1,V2' }
            )
            restrictions = $Restrictions
        }
    }
    @{
        Corp          = $corp
        Subscriptions = @(@{ subscriptionId = $corp; displayName = 'sub-corp-apps'; state = 'Enabled' })
        Skus          = @(
            & $vm 'Standard_D4s_v5' 'standardDSv5Family' 4 16 @('1', '2', '3')
            & $vm 'Standard_D2s_v5' 'standardDSv5Family' 2 8 @('1', '2', '3') @(@{ type = 'Zone'; values = @('UKSouth'); restrictionInfo = @{ locations = @('UKSouth'); zones = @('3') }; reasonCode = 'NotAvailableForSubscription' })
            & $vm 'Standard_E8s_v5' 'standardESv5Family' 8 64 @('1', '2', '3')
            & $vm 'Standard_B1s' 'standardBSFamily' 1 1 @('1', '2', '3')
            & $vm 'Standard_D4ps_v5' 'standardDPSv5Family' 4 16 @('1', '2') @() 'Arm64'
            & $vm 'Standard_M8ms' 'standardMSFamily' 8 218.75 @()
            & $vm 'Standard_NC24ads_A100_v4' 'standardNCADSA100v4Family' 24 220 @('1', '2', '3') @(@{ type = 'Location'; values = @('UKSouth'); restrictionInfo = @{ locations = @('UKSouth') }; reasonCode = 'NotAvailableForSubscription' })
            @{ resourceType = 'disks'; name = 'Premium_LRS'; locations = @('UKSouth'); locationInfo = @(@{ location = 'UKSouth'; zones = @('1', '2', '3') }); capabilities = @(); restrictions = @() }
        )
        Usages        = @(
            @{ name = @{ value = 'cores'; localizedValue = 'Total Regional vCPUs' }; currentValue = 20; limit = 100 }
            @{ name = @{ value = 'standardDSv5Family'; localizedValue = 'Standard DSv5 Family vCPUs' }; currentValue = 12; limit = 100 }
            @{ name = @{ value = 'standardESv5Family'; localizedValue = 'Standard ESv5 Family vCPUs' }; currentValue = 8; limit = 10 }
            @{ name = @{ value = 'standardBSFamily'; localizedValue = 'Standard BS Family vCPUs' }; currentValue = 0; limit = 20 }
            @{ name = @{ value = 'standardDPSv5Family'; localizedValue = 'Standard DPSv5 Family vCPUs' }; currentValue = 0; limit = 50 }
            @{ name = @{ value = 'standardMSFamily'; localizedValue = 'Standard MS Family vCPUs' }; currentValue = 0; limit = 20 }
            @{ name = @{ value = 'standardNCADSA100v4Family'; localizedValue = 'Standard NCADS A100 v4 Family vCPUs' }; currentValue = 0; limit = 0 }
        )
        Locations     = @(
            @{ name = 'uksouth'; availabilityZoneMappings = @(@{ logicalZone = '1'; physicalZone = 'uksouth-az2' }, @{ logicalZone = '2'; physicalZone = 'uksouth-az1' }, @{ logicalZone = '3'; physicalZone = 'uksouth-az3' }) }
            @{ name = 'ukwest'; availabilityZoneMappings = @() }
        )
        Cluster       = @{
            id = "/subscriptions/$corp/resourcegroups/rg-aks/providers/microsoft.containerservice/managedclusters/aks-contoso"; name = 'aks-contoso'; resourceGroup = 'rg-aks'; subscriptionId = $corp; location = 'uksouth'
            pools = @(
                @{ name = 'system'; mode = 'System'; vmSize = 'Standard_D4s_v5'; count = 3; availabilityZones = @('1', '2', '3'); osType = 'Linux' }
                @{ name = 'memory'; mode = 'User'; vmSize = 'Standard_E8s_v5'; count = 1; availabilityZones = @('1', '2'); osType = 'Linux' }
            )
        }
    }
}
