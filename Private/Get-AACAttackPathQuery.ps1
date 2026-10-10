function Get-AACAttackPathQuery {
    <#
    .SYNOPSIS
        The Azure Resource Graph queries behind Get-AACAttackPath: the
        exposure (public IPs, NICs, NSGs, subnets), the compute an attacker
        lands on (VMs, App Service, AKS) and its managed identities, the
        data stores, the role assignments and definitions, resource counts
        for the blast radius, and Defender for Cloud's own attack paths.
    .DESCRIPTION
        Role assignments and definitions are read tenant-wide, so roles
        granted at a management group count too. defender may fail (it
        needs Defender CSPM); the rest is derived from the estate.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()

    [ordered]@{
        publicIps       = "resources | where type =~ 'microsoft.network/publicipaddresses' | project id = tolower(id), name, ip = tostring(properties.ipAddress), sku = tostring(sku.name), attachedTo = tolower(tostring(properties.ipConfiguration.id))"
        nics            = "resources | where type =~ 'microsoft.network/networkinterfaces' | project id = tolower(id), vm = tolower(tostring(properties.virtualMachine.id)), nsg = tolower(tostring(properties.networkSecurityGroup.id)), ipConfigs = properties.ipConfigurations"
        nsgs            = "resources | where type =~ 'microsoft.network/networksecuritygroups' | project id = tolower(id), name, rules = properties.securityRules"
        subnets         = "resources | where type =~ 'microsoft.network/virtualnetworks' | mv-expand subnet = properties.subnets | project id = tolower(tostring(subnet.id)), nsg = tolower(tostring(subnet.properties.networkSecurityGroup.id)), vnet = tolower(id)"
        vms             = "resources | where type =~ 'microsoft.compute/virtualmachines' | project id = tolower(id), name, resourceGroup, subscriptionId, identity"
        apps            = "resources | where type =~ 'microsoft.web/sites' | project id = tolower(id), name, kind, resourceGroup, subscriptionId, publicAccess = tostring(properties.publicNetworkAccess), hostname = tostring(properties.defaultHostName), identity"
        clusters        = "resources | where type =~ 'microsoft.containerservice/managedclusters' | project id = tolower(id), name, resourceGroup, subscriptionId, private = tobool(properties.apiServerAccessProfile.enablePrivateCluster), ranges = properties.apiServerAccessProfile.authorizedIPRanges, identity, kubelet = tostring(properties.identityProfile.kubeletidentity.objectId)"
        stores          = "resources | where type in~ ('microsoft.storage/storageaccounts', 'microsoft.keyvault/vaults', 'microsoft.sql/servers', 'microsoft.documentdb/databaseaccounts', 'microsoft.dbforpostgresql/flexibleservers', 'microsoft.dbformysql/flexibleservers') | project id = tolower(id), name, type = tolower(type), resourceGroup, subscriptionId, publicAccess = coalesce(tostring(properties.publicNetworkAccess), tostring(properties.network.publicNetworkAccess)), defaultAction = tostring(properties.networkAcls.defaultAction), blobPublic = tostring(properties.allowBlobPublicAccess), accessPolicies = properties.accessPolicies"
        identities      = "resources | where type =~ 'microsoft.managedidentity/userassignedidentities' | project id = tolower(id), name, principalId = tostring(properties.principalId)"
        roleAssignments = @{ Tenant = $true; Query = "authorizationresources | where type =~ 'microsoft.authorization/roleassignments' | project id, principalId = tostring(properties.principalId), principalType = tostring(properties.principalType), roleId = tolower(tostring(properties.roleDefinitionId)), scope = tolower(tostring(properties.scope))" }
        roleDefinitions = @{ Tenant = $true; Query = "authorizationresources | where type =~ 'microsoft.authorization/roledefinitions' | project id = tolower(id), roleName = tostring(properties.roleName), roleType = tostring(properties.type), permissions = properties.permissions" }
        counts          = "resources | summarize resources = count() by subscriptionId, resourceGroup = tolower(resourceGroup) | extend id = strcat(subscriptionId, '/', resourceGroup)"
        defender        = "securityresources | where type =~ 'microsoft.security/attackpaths' | project id, subscriptionId, properties"
    }
}
