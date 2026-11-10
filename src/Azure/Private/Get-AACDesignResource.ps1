function Get-AACDesignResource {
    <#
    .SYNOPSIS
        The resources New-AACDesignDiagram can place in a spoke, and how each one
        joins the network.
    .DESCRIPTION
        Access is how a resource reaches the virtual network, which decides where
        it is drawn:
          Integration      outside the network, with VNet integration through a
                           subnet delegated to Microsoft.Web/serverFarms (App
                           Service and Functions)
          PrivateEndpoint  outside the network, reached through a private
                           endpoint in the spoke's private endpoint subnet, with
                           the private DNS zone it needs in the hub
          Subnet           inside a subnet of its own kind (a VM, AKS, an
                           Application Gateway, API Management)

        Subnet sizes are Preferred, or Minimum when the address space is tight;
        they follow Microsoft's guidance for each service. Returns an ordered
        hashtable: the resource's key -> @{ Label; Type; Icon; Abbreviation;
        Access; Subnet; Zone; NoHyphen }.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()

    [ordered]@{
        FunctionApp        = @{ Label = 'Function App'; Type = 'Microsoft.Web/sites'; Icon = 'functionapp'; Abbreviation = 'func'; Access = 'Integration'; Subnet = 'integration' }
        WebApp             = @{ Label = 'Web App'; Type = 'Microsoft.Web/sites'; Icon = 'appservice'; Abbreviation = 'app'; Access = 'Integration'; Subnet = 'integration' }
        StorageAccount     = @{ Label = 'Storage account'; Type = 'Microsoft.Storage/storageAccounts'; Icon = 'storage'; Abbreviation = 'st'; Access = 'PrivateEndpoint'; Subnet = 'privateendpoints'; Zone = 'privatelink.blob.core.windows.net'; NoHyphen = $true }
        KeyVault           = @{ Label = 'Key Vault'; Type = 'Microsoft.KeyVault/vaults'; Icon = 'keyvault'; Abbreviation = 'kv'; Access = 'PrivateEndpoint'; Subnet = 'privateendpoints'; Zone = 'privatelink.vaultcore.azure.net' }
        SqlDatabase        = @{ Label = 'Azure SQL Database'; Type = 'Microsoft.Sql/servers'; Icon = 'sqldb'; Abbreviation = 'sql'; Access = 'PrivateEndpoint'; Subnet = 'privateendpoints'; Zone = 'privatelink.database.windows.net' }
        CosmosDb           = @{ Label = 'Cosmos DB'; Type = 'Microsoft.DocumentDB/databaseAccounts'; Icon = 'cosmos'; Abbreviation = 'cosmos'; Access = 'PrivateEndpoint'; Subnet = 'privateendpoints'; Zone = 'privatelink.documents.azure.com' }
        Redis              = @{ Label = 'Azure Cache for Redis'; Type = 'Microsoft.Cache/redis'; Icon = 'redis'; Abbreviation = 'redis'; Access = 'PrivateEndpoint'; Subnet = 'privateendpoints'; Zone = 'privatelink.redis.cache.windows.net' }
        ServiceBus         = @{ Label = 'Service Bus namespace'; Type = 'Microsoft.ServiceBus/namespaces'; Icon = 'servicebus'; Abbreviation = 'sbns'; Access = 'PrivateEndpoint'; Subnet = 'privateendpoints'; Zone = 'privatelink.servicebus.windows.net' }
        EventHub           = @{ Label = 'Event Hubs namespace'; Type = 'Microsoft.EventHub/namespaces'; Icon = 'eventhub'; Abbreviation = 'evhns'; Access = 'PrivateEndpoint'; Subnet = 'privateendpoints'; Zone = 'privatelink.servicebus.windows.net' }
        ContainerRegistry  = @{ Label = 'Container registry'; Type = 'Microsoft.ContainerRegistry/registries'; Icon = 'acr'; Abbreviation = 'cr'; Access = 'PrivateEndpoint'; Subnet = 'privateendpoints'; Zone = 'privatelink.azurecr.io'; NoHyphen = $true }
        VirtualMachine     = @{ Label = 'Virtual machine'; Type = 'Microsoft.Compute/virtualMachines'; Icon = 'vm'; Abbreviation = 'vm'; Access = 'Subnet'; Subnet = 'workload' }
        Aks                = @{ Label = 'AKS cluster'; Type = 'Microsoft.ContainerService/managedClusters'; Icon = 'aks'; Abbreviation = 'aks'; Access = 'Subnet'; Subnet = 'aks' }
        ApplicationGateway = @{ Label = 'Application Gateway'; Type = 'Microsoft.Network/applicationGateways'; Icon = 'appgw'; Abbreviation = 'agw'; Access = 'Subnet'; Subnet = 'appgw' }
        ApiManagement      = @{ Label = 'API Management'; Type = 'Microsoft.ApiManagement/service'; Icon = 'apim'; Abbreviation = 'apim'; Access = 'Subnet'; Subnet = 'apim' }
    }
}
