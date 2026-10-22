function Get-AACUnusedResourceQuery {
    <#
    .SYNOPSIS
        The Azure Resource Graph queries behind Get-AACUnusedResource: the
        resources that are attached to nothing, serve nothing or are switched
        off - and the resource groups and pools to tell an empty one from a
        busy one.
    .DESCRIPTION
        One query per kind, each projecting id (lower case), name, type,
        resourceGroup, subscriptionId, location and what tells it is unused:
          disks            unattached managed disks (and since when)
          nics             NICs on no VM, private endpoint or private link
                           service
          publicIps        public IPs on nothing (no IP configuration, no NAT
                           gateway)
          nsgs             NSGs on no subnet or NIC
          routeTables      route tables on no subnet
          natGateways      NAT gateways on no subnet
          loadBalancers    load balancers, with their backend pools
          appGateways      Application Gateways, with their backend pools
          plans            App Service plans with no apps
          availabilitySets availability sets with no VMs
          vms              VMs stopped (still billed) or deallocated
          snapshots        disk snapshots, with when they were taken
          dnsZones         private DNS zones linked to no virtual network
          trafficManager   Traffic Manager profiles with no endpoints
          ipGroups         IP groups no firewall or policy uses
          ddosPlans        DDoS protection plans protecting no network
          wafPolicies      WAF policies attached to nothing
          certificates     App Service certificates, with their expiry
          elasticPools     SQL elastic pools
          pooledDatabases  the databases in a pool (to find empty pools)
          groups           resource groups
          groupCounts      resources per resource group
        -ResourceGroupName narrows every query but the resource groups'
        counts (an empty group has no rows there).
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [string[]] $ResourceGroupName
    )

    $quote = { param([string] $Text) ConvertTo-AACKqlLiteral -Text $Text }
    $groups = @($ResourceGroupName | Where-Object { $_ })
    $in = if ($groups.Count) { " | where resourceGroup in~ ($((@($groups | ForEach-Object { & $quote $_ })) -join ', '))" } else { '' }
    $base = { param([string] $Type, [string] $Where, [string] $Extra) "resources | where type =~ '$Type'$in$(if ($Where) { " | where $Where" }) | project id = tolower(id), name, type = tolower(type), resourceGroup, subscriptionId, location$(if ($Extra) { ", $Extra" })" }
    $none = { param([string] $Path) "coalesce(array_length($Path), 0) == 0" }

    [ordered]@{
        disks            = & $base 'microsoft.compute/disks' "tostring(properties.diskState) =~ 'Unattached' and isempty(managedBy)" 'sku = tostring(sku.name), sizeGb = toint(properties.diskSizeGB), created = tostring(properties.timeCreated), detached = tostring(properties.LastOwnershipUpdateTime)'
        nics             = & $base 'microsoft.network/networkinterfaces' "isempty(tostring(properties.virtualMachine.id)) and isempty(tostring(properties.privateEndpoint.id)) and isempty(tostring(properties.privateLinkService.id)) and $(& $none 'properties.hostedWorkloads')" ''
        publicIps        = & $base 'microsoft.network/publicipaddresses' 'isempty(tostring(properties.ipConfiguration.id)) and isempty(tostring(properties.natGateway.id))' 'sku = tostring(sku.name), ip = tostring(properties.ipAddress), allocation = tostring(properties.publicIPAllocationMethod)'
        nsgs             = & $base 'microsoft.network/networksecuritygroups' "$(& $none 'properties.subnets') and $(& $none 'properties.networkInterfaces')" ''
        routeTables      = & $base 'microsoft.network/routetables' (& $none 'properties.subnets') 'routes = coalesce(array_length(properties.routes), 0)'
        natGateways      = & $base 'microsoft.network/natgateways' (& $none 'properties.subnets') 'sku = tostring(sku.name)'
        loadBalancers    = & $base 'microsoft.network/loadbalancers' '' 'sku = tostring(sku.name), pools = properties.backendAddressPools, rules = coalesce(array_length(properties.loadBalancingRules), 0)'
        appGateways      = & $base 'microsoft.network/applicationgateways' '' 'sku = tostring(properties.sku.name), pools = properties.backendAddressPools, state = tostring(properties.operationalState)'
        plans            = & $base 'microsoft.web/serverfarms' 'toint(properties.numberOfSites) == 0' 'sku = tostring(sku.name), tier = tostring(sku.tier), workers = toint(sku.capacity)'
        availabilitySets = & $base 'microsoft.compute/availabilitysets' (& $none 'properties.virtualMachines') ''
        vms              = & $base 'microsoft.compute/virtualmachines' "tostring(properties.extended.instanceView.powerState.code) in~ ('PowerState/stopped', 'PowerState/deallocated')" 'size = tostring(properties.hardwareProfile.vmSize), power = tostring(properties.extended.instanceView.powerState.code)'
        snapshots        = & $base 'microsoft.compute/snapshots' '' 'sku = tostring(sku.name), sizeGb = toint(properties.diskSizeGB), created = tostring(properties.timeCreated), incremental = tobool(properties.incremental)'
        dnsZones         = & $base 'microsoft.network/privatednszones' 'toint(properties.numberOfVirtualNetworkLinks) == 0' 'records = toint(properties.numberOfRecordSets)'
        trafficManager   = & $base 'microsoft.network/trafficmanagerprofiles' (& $none 'properties.endpoints') ''
        ipGroups         = & $base 'microsoft.network/ipgroups' "$(& $none 'properties.firewalls') and $(& $none 'properties.firewallPolicies')" ''
        ddosPlans        = & $base 'microsoft.network/ddosprotectionplans' (& $none 'properties.virtualNetworks') ''
        wafPolicies      = "resources | where type in~ ('microsoft.network/applicationgatewaywebapplicationfirewallpolicies', 'microsoft.network/frontdoorwebapplicationfirewallpolicies')$in | where $(& $none 'properties.applicationGateways') and $(& $none 'properties.httpListeners') and $(& $none 'properties.pathBasedRules') and $(& $none 'properties.frontendEndpointLinks') and $(& $none 'properties.securityPolicyLinks') | project id = tolower(id), name, type = tolower(type), resourceGroup, subscriptionId, location"
        certificates     = & $base 'microsoft.web/certificates' '' 'expires = tostring(properties.expirationDate), subject = tostring(properties.subjectName)'
        elasticPools     = & $base 'microsoft.sql/servers/elasticpools' '' 'sku = tostring(sku.name), tier = tostring(sku.tier)'
        pooledDatabases  = "resources | where type =~ 'microsoft.sql/servers/databases' and isnotempty(properties.elasticPoolId) | summarize databases = count() by pool = tolower(tostring(properties.elasticPoolId))"
        groups           = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions/resourcegroups'$in | project id = tolower(id), name, resourceGroup = name, subscriptionId, location, locked = tostring(properties.provisioningState), managedBy = tostring(managedBy)"
        groupCounts      = "resources | summarize resources = count() by subscriptionId = tolower(subscriptionId), resourceGroup = tolower(resourceGroup)"
    }
}
