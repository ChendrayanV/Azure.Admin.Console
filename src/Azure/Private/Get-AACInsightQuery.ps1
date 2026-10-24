function Get-AACInsightQuery {
    <#
    .SYNOPSIS
        The Azure Resource Graph queries behind Get-AACInventory -Insight:
        the estate mix, hygiene and network capacity - read in the same
        parallel batch as the inventory itself.
    .DESCRIPTION
          insightVms         VMs: size, OS (type, image, name and version),
                             power state
          insightArc         Azure Arc-enabled servers: OS, connection status
          insightDisks       managed disks: state (attached or not), size, SKU
          insightPublicIps   public IPs: SKU, allocation, whether anything
                             uses them
          insightNics        network interfaces: whether anything uses them
          insightStorage     storage accounts: replication (SKU), kind, tier
          insightDatabases   Azure SQL databases, SQL managed instances,
                             Cosmos DB, PostgreSQL and MySQL flexible servers:
                             tier, SKU, serverless or provisioned
          insightSubnets     every subnet: prefix and IP configurations in it
          insightConnections VPN and ExpressRoute connections: status
          insightCircuits    ExpressRoute circuits: provider and states
          insightClassic     classic (ASM) resources
        -GroupFilter is a KQL clause ('| where resourceGroup in~ (...)') to
        narrow each query to resource groups.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [string] $GroupFilter = ''
    )

    $of = { param([string] $Type) "resources | where type =~ '$Type'$GroupFilter" }
    [ordered]@{
        insightVms         = "$(& $of 'microsoft.compute/virtualmachines') | project id, name, resourceGroup, subscriptionId, location, size = tostring(properties.hardwareProfile.vmSize), osType = tostring(properties.storageProfile.osDisk.osType), publisher = tostring(properties.storageProfile.imageReference.publisher), offer = tostring(properties.storageProfile.imageReference.offer), imageSku = tostring(properties.storageProfile.imageReference.sku), osName = tostring(properties.extended.instanceView.osName), osVersion = tostring(properties.extended.instanceView.osVersion), power = tostring(properties.extended.instanceView.powerState.code)"
        insightArc         = "$(& $of 'microsoft.hybridcompute/machines') | project id, name, resourceGroup, subscriptionId, location, osType = tostring(properties.osType), osName = tostring(properties.osName), osSku = tostring(properties.osSku), osVersion = tostring(properties.osVersion), status = tostring(properties.status)"
        insightDisks       = "$(& $of 'microsoft.compute/disks') | project id, name, resourceGroup, subscriptionId, location, state = tostring(properties.diskState), sizeGb = toint(properties.diskSizeGB), sku = tostring(sku.name), managedBy = tostring(managedBy)"
        insightPublicIps   = "$(& $of 'microsoft.network/publicipaddresses') | project id, name, resourceGroup, subscriptionId, location, sku = tostring(sku.name), allocation = tostring(properties.publicIPAllocationMethod), address = tostring(properties.ipAddress), usedBy = tostring(coalesce(properties.ipConfiguration.id, properties.natGateway.id))"
        insightNics        = "$(& $of 'microsoft.network/networkinterfaces') | project id, name, resourceGroup, subscriptionId, location, usedBy = tostring(coalesce(properties.virtualMachine.id, properties.privateEndpoint.id, properties.privateLinkService.id))"
        insightStorage     = "$(& $of 'microsoft.storage/storageaccounts') | project id, name, resourceGroup, subscriptionId, location, sku = tostring(sku.name), kind, accessTier = tostring(properties.accessTier)"
        insightDatabases   = "resources | where type in~ ('microsoft.sql/servers/databases', 'microsoft.sql/managedinstances', 'microsoft.documentdb/databaseaccounts', 'microsoft.dbforpostgresql/flexibleservers', 'microsoft.dbformysql/flexibleservers')$GroupFilter | where not(type =~ 'microsoft.sql/servers/databases' and name endswith '/master') and name != 'master' | project id, name, type = tolower(type), resourceGroup, subscriptionId, location, skuName = tostring(sku.name), skuTier = tostring(sku.tier), kind, capabilities = tostring(properties.capabilities)"
        insightSubnets     = "$(& $of 'microsoft.network/virtualnetworks') | mv-expand subnet = properties.subnets | project vnetId = id, vnet = name, resourceGroup, subscriptionId, location, subnet = tostring(subnet.name), prefix = tostring(coalesce(subnet.properties.addressPrefix, subnet.properties.addressPrefixes[0])), used = array_length(subnet.properties.ipConfigurations)"
        insightConnections = "$(& $of 'microsoft.network/connections') | project id, name, resourceGroup, subscriptionId, location, connectionType = tostring(properties.connectionType), status = tostring(properties.connectionStatus), state = tostring(properties.provisioningState)"
        insightCircuits    = "$(& $of 'microsoft.network/expressroutecircuits') | project id, name, resourceGroup, subscriptionId, location, provider = tostring(properties.serviceProviderProperties.serviceProviderName), bandwidth = toint(properties.serviceProviderProperties.bandwidthInMbps), providerState = tostring(properties.serviceProviderProvisioningState), circuitState = tostring(properties.circuitProvisioningState)"
        insightClassic     = "resources | where type startswith 'microsoft.classic'$GroupFilter | project id, name, type = tolower(type), resourceGroup, subscriptionId, location"
    }
}
