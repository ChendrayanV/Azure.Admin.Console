function Get-AACLoadBalancerQuery {
    <#
    .SYNOPSIS
        The Azure Resource Graph queries behind Get-AACLoadBalancerHealth:
        load balancers, Application Gateways and Traffic Manager profiles
        with their pools, probes, rules and endpoints - and the backend NICs'
        IP addresses, to put a name on each probed address.
    .DESCRIPTION
          loadBalancers  SKU, frontends, backend pools (NIC IP configurations
                         and IP addresses), probes and rules
          appGateways    SKU and tier, capacity and autoscale, state, backend
                         pools, HTTP settings, probes, request routing rules
          trafficManager status, routing method, monitor status, endpoints
                         with their status and health
          backendNics    the NIC IP configurations in a load balancer's pool:
                         private IP and VM
        -ResourceGroupName narrows the balancers, not the NICs.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [string[]] $ResourceGroupName
    )

    $quote = { param([string] $Text) "'" + ($Text -replace "'", "\'") + "'" }
    $groups = @($ResourceGroupName | Where-Object { $_ })
    $in = if ($groups.Count) { " | where resourceGroup in~ ($((@($groups | ForEach-Object { & $quote $_ })) -join ', '))" } else { '' }

    [ordered]@{
        loadBalancers  = "resources | where type =~ 'microsoft.network/loadbalancers'$in | project id = tolower(id), name, resourceGroup, subscriptionId, location, sku = tostring(sku.name), frontends = coalesce(array_length(properties.frontendIPConfigurations), 0), pools = properties.backendAddressPools, probes = properties.probes, rules = properties.loadBalancingRules"
        appGateways    = "resources | where type =~ 'microsoft.network/applicationgateways'$in | project id = tolower(id), name, resourceGroup, subscriptionId, location, sku = tostring(properties.sku.name), tier = tostring(properties.sku.tier), capacity = toint(properties.sku.capacity), minCapacity = toint(properties.autoscaleConfiguration.minCapacity), maxCapacity = toint(properties.autoscaleConfiguration.maxCapacity), state = tostring(properties.operationalState), zones, pools = properties.backendAddressPools, settings = properties.backendHttpSettingsCollection, probes = properties.probes, rules = coalesce(array_length(properties.requestRoutingRules), 0)"
        trafficManager = "resources | where type =~ 'microsoft.network/trafficmanagerprofiles'$in | project id = tolower(id), name, resourceGroup, subscriptionId, location, status = tostring(properties.profileStatus), routing = tostring(properties.trafficRoutingMethod), monitor = tostring(properties.monitorConfig.profileMonitorStatus), monitorProtocol = tostring(properties.monitorConfig.protocol), monitorPort = toint(properties.monitorConfig.port), monitorPath = tostring(properties.monitorConfig.path), endpoints = properties.endpoints"
        backendNics    = "resources | where type =~ 'microsoft.network/networkinterfaces' | mv-expand c = properties.ipConfigurations | where coalesce(array_length(c.properties.loadBalancerBackendAddressPools), 0) > 0 | project id = tolower(tostring(c.id)), ip = tostring(c.properties.privateIPAddress), vm = tolower(tostring(properties.virtualMachine.id)), nic = name"
    }
}
