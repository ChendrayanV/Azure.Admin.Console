<#
    Made-up Get-AACInsightQuery rows for the Contoso tenant, for
    Inventory.Tests.ps1's -Insight tests:

      VMs      vm-web-01 (D2s_v5, Windows Server 2022, running),
               vm-web-02 (D2s_v5, Ubuntu 22.04, stopped - still billed),
               vm-batch (B2s, Ubuntu from its image, deallocated)
      Arc      arc-onprem-01 (Windows Server 2019, connected),
               arc-onprem-02 (Ubuntu 20.04, disconnected)
      Waste    disk-old (128 GB, unattached), pip-spare, nic-orphan,
               a classic storage account
      Network  snet-app 91% full (10 of 11 usable IPs), a VPN connection
               not connected, an ExpressRoute circuit provisioned
#>
function Get-AACContosoInsight {
    $connectivity = '11111111-1111-1111-1111-111111111111'
    $corp = '22222222-2222-2222-2222-222222222222'
    $id = { param($Sub, $Group, $Type, $Name) "/subscriptions/$Sub/resourceGroups/$Group/providers/$Type/$Name" }
    $base = { param($Sub, $Group, $Type, $Name) @{ id = (& $id $Sub $Group $Type $Name); name = $Name; resourceGroup = $Group; subscriptionId = $Sub; location = 'uksouth' } }
    $with = { param([hashtable] $Row, [hashtable] $More) foreach ($key in $More.Keys) { $Row[$key] = $More[$key] }; $Row }
    @{
        DiskId             = & $id $corp 'rg-app' 'Microsoft.Compute/disks' 'disk-old'
        insightVms         = @(
            & $with (& $base $corp 'rg-app' 'Microsoft.Compute/virtualMachines' 'vm-web-01') @{ size = 'Standard_D2s_v5'; osType = 'Windows'; publisher = 'MicrosoftWindowsServer'; offer = 'WindowsServer'; imageSku = '2022-datacenter-azure-edition'; osName = 'Windows Server 2022 Datacenter Azure Edition'; osVersion = '10.0.20348'; power = 'PowerState/running' }
            & $with (& $base $corp 'rg-app' 'Microsoft.Compute/virtualMachines' 'vm-web-02') @{ size = 'Standard_D2s_v5'; osType = 'Linux'; publisher = 'Canonical'; offer = '0001-com-ubuntu-server-jammy'; imageSku = '22_04-lts-gen2'; osName = 'ubuntu'; osVersion = '22.04'; power = 'PowerState/stopped' }
            & $with (& $base $corp 'rg-app' 'Microsoft.Compute/virtualMachines' 'vm-batch') @{ size = 'Standard_B2s'; osType = 'Linux'; publisher = 'Canonical'; offer = '0001-com-ubuntu-server-jammy'; imageSku = '22_04-lts-gen2'; osName = ''; osVersion = ''; power = 'PowerState/deallocated' }
        )
        insightArc         = @(
            & $with (& $base $corp 'rg-onprem' 'Microsoft.HybridCompute/machines' 'arc-onprem-01') @{ osType = 'windows'; osName = 'Windows Server 2019 Standard'; osSku = 'Windows Server 2019 Standard'; osVersion = '10.0.17763'; status = 'Connected' }
            & $with (& $base $corp 'rg-onprem' 'Microsoft.HybridCompute/machines' 'arc-onprem-02') @{ osType = 'linux'; osName = 'ubuntu'; osSku = 'Ubuntu 20.04.6 LTS'; osVersion = '20.04'; status = 'Disconnected' }
        )
        insightDisks       = @(
            & $with (& $base $corp 'rg-app' 'Microsoft.Compute/disks' 'disk-old') @{ state = 'Unattached'; sizeGb = 128; sku = 'Premium_LRS'; managedBy = '' }
            & $with (& $base $corp 'rg-app' 'Microsoft.Compute/disks' 'vm-web-01_OsDisk') @{ state = 'Attached'; sizeGb = 127; sku = 'Premium_LRS'; managedBy = (& $id $corp 'rg-app' 'Microsoft.Compute/virtualMachines' 'vm-web-01') }
        )
        insightPublicIps   = @(
            & $with (& $base $connectivity 'rg-hub' 'Microsoft.Network/publicIPAddresses' 'pip-afw') @{ sku = 'Standard'; allocation = 'Static'; address = '203.0.113.10'; usedBy = '/subscriptions/x/ipconfig' }
            & $with (& $base $connectivity 'rg-hub' 'Microsoft.Network/publicIPAddresses' 'pip-spare') @{ sku = 'Standard'; allocation = 'Static'; address = '203.0.113.11'; usedBy = '' }
        )
        insightNics        = @(
            & $with (& $base $corp 'rg-app' 'Microsoft.Network/networkInterfaces' 'nic-web-01') @{ usedBy = '/subscriptions/x/vm' }
            & $with (& $base $corp 'rg-app' 'Microsoft.Network/networkInterfaces' 'nic-orphan') @{ usedBy = '' }
        )
        insightStorage     = @(
            & $with (& $base $corp 'rg-data' 'Microsoft.Storage/storageAccounts' 'stordersdata') @{ sku = 'Standard_ZRS'; kind = 'StorageV2'; accessTier = 'Hot' }
            & $with (& $base $corp 'rg-data' 'Microsoft.Storage/storageAccounts' 'stlogs') @{ sku = 'Standard_RAGRS'; kind = 'StorageV2'; accessTier = 'Cool' }
            & $with (& $base $corp 'rg-app' 'Microsoft.Storage/storageAccounts' 'stdev') @{ sku = 'Standard_LRS'; kind = 'StorageV2'; accessTier = 'Hot' }
        )
        insightDatabases   = @(
            & $with (& $base $corp 'rg-data' 'Microsoft.Sql/servers/databases' 'sql-orders/sqldb-orders') @{ type = 'microsoft.sql/servers/databases'; skuName = 'GP_Gen5_2'; skuTier = 'GeneralPurpose'; kind = 'v12.0,user,vcore'; capabilities = '' }
            & $with (& $base $corp 'rg-data' 'Microsoft.Sql/servers/databases' 'sql-orders/sqldb-dev') @{ type = 'microsoft.sql/servers/databases'; skuName = 'GP_S_Gen5_1'; skuTier = 'GeneralPurpose'; kind = 'v12.0,user,vcore,serverless'; capabilities = '' }
            & $with (& $base $corp 'rg-data' 'Microsoft.DocumentDB/databaseAccounts' 'cosmos-app') @{ type = 'microsoft.documentdb/databaseaccounts'; skuName = ''; skuTier = ''; kind = 'GlobalDocumentDB'; capabilities = '[{"name":"EnableServerless"}]' }
            & $with (& $base $corp 'rg-data' 'Microsoft.DBforPostgreSQL/flexibleServers' 'psql-app') @{ type = 'microsoft.dbforpostgresql/flexibleservers'; skuName = 'Standard_B1ms'; skuTier = 'Burstable'; kind = ''; capabilities = '' }
        )
        insightSubnets     = @(
            @{ vnetId = (& $id $connectivity 'rg-hub' 'Microsoft.Network/virtualNetworks' 'vnet-hub'); vnet = 'vnet-hub'; resourceGroup = 'rg-hub'; subscriptionId = $connectivity; location = 'uksouth'; subnet = 'GatewaySubnet'; prefix = '10.0.0.0/27'; used = 2 }
            @{ vnetId = (& $id $corp 'rg-app' 'Microsoft.Network/virtualNetworks' 'vnet-app'); vnet = 'vnet-app'; resourceGroup = 'rg-app'; subscriptionId = $corp; location = 'uksouth'; subnet = 'snet-app'; prefix = '10.1.0.0/28'; used = 10 }
            @{ vnetId = (& $id $corp 'rg-app' 'Microsoft.Network/virtualNetworks' 'vnet-app'); vnet = 'vnet-app'; resourceGroup = 'rg-app'; subscriptionId = $corp; location = 'uksouth'; subnet = 'snet-data'; prefix = '10.1.1.0/24'; used = $null }
        )
        insightConnections = @(
            & $with (& $base $connectivity 'rg-hub' 'Microsoft.Network/connections' 'cn-onprem') @{ connectionType = 'IPsec'; status = 'Connected'; state = 'Succeeded' }
            & $with (& $base $connectivity 'rg-hub' 'Microsoft.Network/connections' 'cn-branch') @{ connectionType = 'IPsec'; status = 'NotConnected'; state = 'Succeeded' }
        )
        insightCircuits    = @(
            & $with (& $base $connectivity 'rg-hub' 'Microsoft.Network/expressRouteCircuits' 'er-london') @{ provider = 'Contoso Telecom'; bandwidth = 1000; providerState = 'Provisioned'; circuitState = 'Enabled' }
        )
        insightClassic     = @(
            @{ id = "/subscriptions/$corp/resourceGroups/rg-old-classic/providers/Microsoft.ClassicStorage/storageAccounts/classicstore"; name = 'classicstore'; type = 'microsoft.classicstorage/storageaccounts'; resourceGroup = 'rg-old-classic'; subscriptionId = $corp; location = 'uksouth' }
        )
    }
}
