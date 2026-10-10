function Get-AACDependencyQuery {
    <#
    .SYNOPSIS
        The Azure Resource Graph queries behind Get-AACDependencyGraph: the
        resources that depend on each other and what links them - compute
        and its network, load balancers, gateways and Front Door to their
        backends, apps to their plans, private endpoints to their targets,
        managed identities to what their roles reach - and what makes each
        redundant (zones, instances, SKUs).
    .DESCRIPTION
        -ResourceGroupName narrows the compute and data queries; role
        assignments are read tenant-wide (filtered to resource scopes later).
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [string[]] $ResourceGroupName = @()
    )

    $quote = { param([string] $Text) "'" + ($Text -replace "'", "\'") + "'" }
    $groups = if ($ResourceGroupName.Count) { " | where resourceGroup in~ ($((@($ResourceGroupName | ForEach-Object { & $quote $_ })) -join ', '))" } else { '' }
    [ordered]@{
        vms        = "resources | where type =~ 'microsoft.compute/virtualmachines'$groups | project id = tolower(id), name, type = tolower(type), resourceGroup, subscriptionId, zones, avset = tolower(tostring(properties.availabilitySet.id)), osDisk = tolower(tostring(properties.storageProfile.osDisk.managedDisk.id)), dataDisks = properties.storageProfile.dataDisks, identity"
        nics       = "resources | where type =~ 'microsoft.network/networkinterfaces' | project id = tolower(id), vm = tolower(tostring(properties.virtualMachine.id)), ipConfigs = properties.ipConfigurations"
        vnets      = "resources | where type =~ 'microsoft.network/virtualnetworks' | project id = tolower(id), name, type = tolower(type), resourceGroup, subscriptionId, peerings = properties.virtualNetworkPeerings"
        balancers  = "resources | where type in~ ('microsoft.network/loadbalancers', 'microsoft.network/applicationgateways')$groups | project id = tolower(id), name, type = tolower(type), resourceGroup, subscriptionId, zones, capacity = toint(properties.sku.capacity), autoscale = properties.autoscaleConfiguration, pools = properties.backendAddressPools"
        origins    = "resources | where type =~ 'microsoft.cdn/profiles/origingroups/origins' | project id = tolower(id), profile = tolower(tostring(split(id, '/originGroups/')[0])), host = tolower(tostring(properties.hostName))"
        profiles   = "resources | where type =~ 'microsoft.cdn/profiles'$groups | project id = tolower(id), name, type = tolower(type), resourceGroup, subscriptionId"
        web        = "resources | where type =~ 'microsoft.web/sites'$groups | project id = tolower(id), name, type = tolower(type), kind, resourceGroup, subscriptionId, plan = tolower(tostring(properties.serverFarmId)), subnet = tolower(tostring(properties.virtualNetworkSubnetId)), hosts = properties.enabledHostNames, identity"
        plans      = "resources | where type =~ 'microsoft.web/serverfarms'$groups | project id = tolower(id), name, type = tolower(type), resourceGroup, subscriptionId, capacity = toint(sku.capacity), tier = tostring(sku.tier), zoneRedundant = tobool(properties.zoneRedundant)"
        endpoints  = "resources | where type =~ 'microsoft.network/privateendpoints'$groups | project id = tolower(id), name, type = tolower(type), resourceGroup, subscriptionId, subnet = tolower(tostring(properties.subnet.id)), links = array_concat(properties.privateLinkServiceConnections, properties.manualPrivateLinkServiceConnections)"
        clusters   = "resources | where type =~ 'microsoft.containerservice/managedclusters'$groups | project id = tolower(id), name, type = tolower(type), resourceGroup, subscriptionId, pools = properties.agentPoolProfiles, identity, kubelet = tostring(properties.identityProfile.kubeletidentity.objectId)"
        data       = "resources | where type in~ ('microsoft.storage/storageaccounts', 'microsoft.sql/servers', 'microsoft.sql/servers/databases', 'microsoft.documentdb/databaseaccounts', 'microsoft.cache/redis', 'microsoft.keyvault/vaults', 'microsoft.servicebus/namespaces', 'microsoft.eventhub/namespaces', 'microsoft.dbforpostgresql/flexibleservers', 'microsoft.dbformysql/flexibleservers', 'microsoft.containerregistry/registries')$groups | project id = tolower(id), name, type = tolower(type), resourceGroup, subscriptionId, zones, sku = tostring(sku.name), tier = tostring(sku.tier), zoneRedundant = tobool(properties.zoneRedundant), host = tolower(coalesce(tostring(properties.fullyQualifiedDomainName), tostring(properties.hostName), tostring(parse_url(tostring(properties.vaultUri)).Host), tostring(parse_url(tostring(properties.serviceBusEndpoint)).Host), tostring(parse_url(tostring(properties.primaryEndpoints.blob)).Host), tostring(properties.loginServer))), locations = properties.locations, ha = tostring(properties.highAvailability.mode)"
        identities = "resources | where type =~ 'microsoft.managedidentity/userassignedidentities' | project id = tolower(id), principalId = tostring(properties.principalId)"
        roles      = @{ Tenant = $true; Query = "authorizationresources | where type =~ 'microsoft.authorization/roleassignments' | extend scope = tolower(tostring(properties.scope)) | where scope has '/providers/' and scope !startswith '/providers/microsoft.management' | project id, principalId = tostring(properties.principalId), scope, roleId = tolower(tostring(properties.roleDefinitionId))" }
        insights   = "resources | where type =~ 'microsoft.insights/components'$groups | project id = tolower(id), name, workspace = tolower(tostring(properties.WorkspaceResourceId))"
        workspaces = "resources | where type =~ 'microsoft.operationalinsights/workspaces' | project id = tolower(id), customerId = tostring(properties.customerId)"
    }
}
