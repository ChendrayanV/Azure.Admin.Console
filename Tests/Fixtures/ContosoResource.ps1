<#
    Made-up resources for ExportResource.Tests.ps1 (and the demo), as the
    Resource Graph query of Get-AACResourceExportQuery returns them - joined
    to their subscription and resource group:

      sub-contoso-prod  Tenant Root Group > Contoso > Landing zones
        rg-app       vm-web-01 (Linux, running, 2 data disks), nic-web
        rg-data      stcontosodata (TLS 1.2, Data Lake), sql-contoso/sqldb-orders
        rg-aks       aks-contoso (3 + 2 nodes, private)
        rg-security  kv-contoso
      sub-contoso-dev   Tenant Root Group > Contoso > Sandbox
        rg-dev       disk-old (unattached), pip-old (no tags)

    Tags: Environment on 4 resources (one spelt 'environment'), Owner on 2,
    CostCenter on 1; sqldb-orders, nic-web and pip-old have none.
#>
function Get-AACContosoResource {
    $prod = '11111111-1111-1111-1111-111111111111'
    $dev = '22222222-2222-2222-2222-222222222222'
    $root = @{ displayName = 'Tenant Root Group'; name = 'contoso-tenant' }
    $contoso = @{ displayName = 'Contoso'; name = 'mg-contoso' }
    $chain = @{ $prod = @(@{ displayName = 'Landing zones'; name = 'mg-landingzones' }, $contoso, $root); $dev = @(@{ displayName = 'Sandbox'; name = 'mg-sandbox' }, $contoso, $root) }
    $subName = @{ $prod = 'sub-contoso-prod'; $dev = 'sub-contoso-dev' }
    $row = {
        param([string] $Sub, [string] $Group, [string] $Type, [string] $Name, [hashtable] $Properties = @{}, [hashtable] $Extra = @{})
        $r = @{
            id = "/subscriptions/$Sub/resourceGroups/$Group/providers/$Type/$Name"; name = ($Name -split '/')[-1]; type = $Type.ToLowerInvariant(); kind = ''; location = 'uksouth'
            resourceGroup = $Group; subscriptionId = $Sub; subscriptionName = $subName[$Sub]; subscriptionState = 'Enabled'; managementGroupChain = $chain[$Sub]
            groupTags = @{ Owner = 'platform' }; groupLocation = 'uksouth'; zones = $null; sku = $null; plan = $null; identity = $null; managedBy = ''; tags = $null; extendedLocation = $null
            properties = @{ provisioningState = 'Succeeded' } + $Properties
        }
        foreach ($k in $Extra.Keys) { $r[$k] = $Extra[$k] }
        $r
    }
    $vmId = "/subscriptions/$prod/resourceGroups/rg-app/providers/Microsoft.Compute/virtualMachines/vm-web-01"

    @{
        Prod = $prod
        Dev  = $dev
        Rows = @(
            (& $row $prod 'rg-app' 'Microsoft.Compute/virtualMachines' 'vm-web-01' @{
                    hardwareProfile = @{ vmSize = 'Standard_D2s_v5' }; timeCreated = '2025-03-01T10:00:00Z'
                    storageProfile  = @{ osDisk = @{ osType = 'Linux' }; imageReference = @{ offer = '0001-com-ubuntu-server-jammy'; sku = '22_04-lts-gen2' }; dataDisks = @(@{ lun = 0 }, @{ lun = 1 }) }
                    extended        = @{ instanceView = @{ powerState = @{ displayStatus = 'VM running' }; osName = 'ubuntu' } }
                } @{ zones = @('1'); identity = @{ type = 'SystemAssigned' }; tags = @{ Environment = 'prod'; Owner = 'apps' } })
            (& $row $prod 'rg-app' 'Microsoft.Network/networkInterfaces' 'nic-web' @{
                    ipConfigurations = @(@{ name = 'ipconfig1'; properties = @{ privateIPAddress = '10.0.1.4'; subnet = @{ id = "/subscriptions/$prod/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-hub/subnets/snet-web" } } })
                    virtualMachine   = @{ id = $vmId }; networkSecurityGroup = @{ id = "/subscriptions/$prod/resourceGroups/rg-net/providers/Microsoft.Network/networkSecurityGroups/nsg-web" }; enableAcceleratedNetworking = $true
                })
            (& $row $prod 'rg-data' 'Microsoft.Storage/storageAccounts' 'stcontosodata' @{
                    minimumTlsVersion = 'TLS1_2'; allowBlobPublicAccess = $false; allowSharedKeyAccess = $true; supportsHttpsTrafficOnly = $true; isHnsEnabled = $true; accessTier = 'Hot'
                    networkAcls = @{ defaultAction = 'Deny'; ipRules = @(@{ value = '203.0.113.0/24' }, @{ value = '198.51.100.7' }) }; creationTime = '2024-11-05T08:00:00Z'; publicNetworkAccess = 'Enabled'
                } @{ kind = 'StorageV2'; sku = @{ name = 'Standard_ZRS'; tier = 'Standard' }; tags = @{ Environment = 'prod'; CostCenter = 'CC-1001' } })
            (& $row $prod 'rg-data' 'Microsoft.Sql/servers/databases' 'sql-contoso/databases/sqldb-orders' @{ status = 'Online'; maxSizeBytes = 34359738368; zoneRedundant = $false } @{ sku = @{ name = 'GP_S_Gen5'; tier = 'GeneralPurpose'; capacity = 2 } })
            (& $row $prod 'rg-aks' 'Microsoft.ContainerService/managedClusters' 'aks-contoso' @{
                    kubernetesVersion = '1.30.3'; agentPoolProfiles = @(@{ name = 'system'; count = 3 }, @{ name = 'user'; count = 2 }); networkProfile = @{ networkPlugin = 'azure' }; apiServerAccessProfile = @{ enablePrivateCluster = $true }
                } @{ sku = @{ name = 'Base'; tier = 'Standard' }; identity = @{ type = 'UserAssigned' }; tags = @{ Owner = 'platform' } })
            (& $row $prod 'rg-security' 'Microsoft.KeyVault/vaults' 'kv-contoso' @{ enableSoftDelete = $true; enablePurgeProtection = $true; enableRbacAuthorization = $true; publicNetworkAccess = 'Disabled'; softDeleteRetentionInDays = 90 } @{ tags = @{ Environment = 'prod' } })
            (& $row $dev 'rg-dev' 'Microsoft.Compute/disks' 'disk-old' @{ diskSizeGB = 128; diskState = 'Unattached'; osType = '' } @{ sku = @{ name = 'Premium_LRS'; tier = 'Premium' }; tags = @{ environment = 'dev' } })
            (& $row $dev 'rg-dev' 'Microsoft.Network/publicIPAddresses' 'pip-old' @{ ipAddress = '20.0.0.9'; publicIPAllocationMethod = 'Static' } @{ sku = @{ name = 'Standard'; tier = 'Regional' } })
            # A type with no Details of its own, and no sku, properties or tags to speak of.
            (& $row $dev 'rg-dev' 'Microsoft.Insights/actionGroups' 'ag-oncall' @{} @{ location = 'global'; properties = $null; groupTags = $null })
        )
    }
}
