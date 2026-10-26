function Get-AACAssessmentInsightQuery {
    <#
    .SYNOPSIS
        The Resource Graph queries behind Invoke-AACTenantAssessment's
        Identity and access, Architecture, Operations and Service delivery
        tabs.
    .DESCRIPTION
        One batch:
          roleAssignments, roleDefinitions  every role assignment and role
                            (tenant-wide, as Get-AACRoleAssignment reads them)
          policyAssignments every policy assignment and its scope (tenant)
          pricings          Defender for Cloud plans per subscription
          nsgRules          inbound Allow rules from the internet (any source)
          paas              PaaS resources and their network access settings
          resilience        the critical resources, with zones and
                            redundancy settings
          backupItems       what Azure Backup protects
          asrItems          what Azure Site Recovery replicates
          vnets, hubs, gateways, dnsZones, dnsLinks   the network topology
          workspaces        Log Analytics workspaces
          alerts, actionGroups   alert rules and action groups
          patches           Update Manager's latest patch assessments
          arc               Azure Arc servers
          deprecated        resources on retired or retiring SKUs and kinds
        -Filter is Get-AACAssessmentQuery -Filter's resource group and tag
        filter, for the queries of the resources table. Returns an ordered
        hashtable: name -> query (or @{ Query; Tenant = $true }).
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [string] $Filter = '',

        [switch] $SkipIdentity
    )

    $queries = [ordered]@{}
    if (-not $SkipIdentity) {
        $roles = Get-AACRoleAssignmentQuery
        $queries['roleAssignments'] = $roles['roleAssignments']
        $queries['roleDefinitions'] = $roles['roleDefinitions']
    }
    $queries['policyAssignments'] = @{ Tenant = $true; Query = "policyresources | where type =~ 'microsoft.authorization/policyassignments' | project id = tolower(id), scope = tolower(tostring(properties.scope)), name = tostring(properties.displayName), enforcement = tostring(properties.enforcementMode)" }
    $queries['pricings'] = "securityresources | where type =~ 'microsoft.security/pricings' | project id = tolower(id), subscriptionId = tolower(subscriptionId), name, tier = tostring(properties.pricingTier), subPlan = tostring(properties.subPlan)"
    $queries['nsgRules'] = @(
        "resources$Filter | where type =~ 'microsoft.network/networksecuritygroups'"
        '| mv-expand rule = properties.securityRules | extend r = rule.properties'
        "| where tostring(r.direction) =~ 'Inbound' and tostring(r.access) =~ 'Allow'"
        "| extend sources = array_concat(pack_array(tostring(r.sourceAddressPrefix)), iff(isnull(r.sourceAddressPrefixes), dynamic([]), r.sourceAddressPrefixes)), ports = array_concat(pack_array(tostring(r.destinationPortRange)), iff(isnull(r.destinationPortRanges), dynamic([]), r.destinationPortRanges))"
        "| where sources has_any ('*', 'Internet', '0.0.0.0/0', 'Any')"
        "| project id = strcat(tolower(id), '/', tostring(rule.name)), nsgId = tolower(id), nsg = name, resourceGroup, subscriptionId = tolower(subscriptionId), rule = tostring(rule.name), priority = toint(r.priority), protocol = tostring(r.protocol), sources, ports, subnets = array_length(properties.subnets), nics = array_length(properties.networkInterfaces)"
    ) -join ' '
    $paasTypes = @(
        'microsoft.storage/storageaccounts', 'microsoft.keyvault/vaults', 'microsoft.sql/servers', 'microsoft.documentdb/databaseaccounts', 'microsoft.cognitiveservices/accounts'
        'microsoft.web/sites', 'microsoft.containerregistry/registries', 'microsoft.cache/redis', 'microsoft.eventhub/namespaces', 'microsoft.servicebus/namespaces'
        'microsoft.dbforpostgresql/flexibleservers', 'microsoft.dbformysql/flexibleservers', 'microsoft.search/searchservices', 'microsoft.machinelearningservices/workspaces'
        'microsoft.synapse/workspaces', 'microsoft.datafactory/factories', 'microsoft.appconfiguration/configurationstores', 'microsoft.signalrservice/signalr'
    ) | ForEach-Object { "'$_'" }
    $queries['paas'] = "resources$Filter | where type in~ ($($paasTypes -join ', ')) | project id = tolower(id), name, type = tolower(type), resourceGroup, subscriptionId = tolower(subscriptionId), publicAccess = tostring(properties.publicNetworkAccess), defaultAction = tostring(coalesce(properties.networkAcls.defaultAction, properties.networkRuleSet.defaultAction)), ipRules = array_length(coalesce(properties.networkAcls.ipRules, properties.networkRuleSet.ipRules, properties.ipRules)), privateEndpoints = array_length(properties.privateEndpointConnections), kind"
    $criticalTypes = @(
        'microsoft.compute/virtualmachines', 'microsoft.sql/servers/databases', 'microsoft.storage/storageaccounts', 'microsoft.containerservice/managedclusters', 'microsoft.web/serverfarms'
        'microsoft.cache/redis', 'microsoft.documentdb/databaseaccounts', 'microsoft.network/applicationgateways', 'microsoft.dbforpostgresql/flexibleservers', 'microsoft.dbformysql/flexibleservers'
    ) | ForEach-Object { "'$_'" }
    $queries['resilience'] = "resources$Filter | where type in~ ($($criticalTypes -join ', ')) | where not(type =~ 'microsoft.sql/servers/databases' and name =~ 'master') | project id = tolower(id), name, type = tolower(type), resourceGroup, subscriptionId = tolower(subscriptionId), location, zones, sku = tostring(sku.name), skuTier = tostring(sku.tier), zoneRedundant = tostring(properties.zoneRedundant), poolZones = properties.agentPoolProfiles, cosmosLocations = properties.locations, ha = tostring(properties.highAvailability.mode), tags"
    $queries['backupItems'] = "recoveryservicesresources | where type =~ 'microsoft.recoveryservices/vaults/backupfabrics/protectioncontainers/protecteditems' | project id = tolower(id), source = tolower(tostring(properties.sourceResourceId)), lastBackup = tostring(properties.lastBackupTime), health = tostring(properties.healthStatus) | where isnotempty(source)"
    $queries['asrItems'] = "recoveryservicesresources | where type =~ 'microsoft.recoveryservices/vaults/replicationfabrics/replicationprotectioncontainers/replicationprotecteditems' | project id = tolower(id), source = tolower(tostring(coalesce(properties.providerSpecificDetails.fabricObjectId, properties.providerSpecificDetails.dataSourceInfo.resourceId))), name = tostring(properties.friendlyName), health = tostring(properties.replicationHealth)"
    $queries['vnets'] = "resources$Filter | where type =~ 'microsoft.network/virtualnetworks' | mv-apply s = properties.subnets on (summarize subnetNames = make_list(tostring(s.name))) | mv-apply p = properties.virtualNetworkPeerings on (summarize remotes = make_list(tolower(tostring(p.properties.remoteVirtualNetwork.id))), gatewayTransit = countif(tobool(p.properties.allowGatewayTransit)), useRemote = countif(tobool(p.properties.useRemoteGateways))) | project id = tolower(id), name, resourceGroup, subscriptionId = tolower(subscriptionId), location, prefixes = properties.addressSpace.addressPrefixes, dns = properties.dhcpOptions.dnsServers, subnetNames, remotes, gatewayTransit, useRemote"
    $queries['hubs'] = "resources | where type =~ 'microsoft.network/virtualhubs' | project id = tolower(id), name, resourceGroup, subscriptionId = tolower(subscriptionId), location, prefix = tostring(properties.addressPrefix), vwan = tolower(tostring(properties.virtualWan.id))"
    $queries['gateways'] = "resources$Filter | where type in~ ('microsoft.network/azurefirewalls', 'microsoft.network/virtualnetworkgateways') | project id = tolower(id), name, type = tolower(type), subscriptionId = tolower(subscriptionId), vnet = tolower(tostring(split(tostring(properties.ipConfigurations[0].properties.subnet.id), '/subnets/')[0])), hub = tolower(tostring(properties.virtualHub.id))"
    $queries['dnsZones'] = "resources$Filter | where type =~ 'microsoft.network/privatednszones' | project id = tolower(id), name, resourceGroup, subscriptionId = tolower(subscriptionId), records = toint(properties.numberOfRecordSets), links = toint(properties.numberOfVirtualNetworkLinks)"
    $queries['dnsLinks'] = "resources | where type =~ 'microsoft.network/privatednszones/virtualnetworklinks' | project id = tolower(id), zone = tostring(split(tolower(id), '/virtualnetworklinks/')[0]), vnet = tolower(tostring(properties.virtualNetwork.id)), registration = tobool(properties.registrationEnabled)"
    $queries['workspaces'] = "resources$Filter | where type =~ 'microsoft.operationalinsights/workspaces' | project id = tolower(id), name, resourceGroup, subscriptionId = tolower(subscriptionId), location, sku = tostring(properties.sku.name), retention = toint(properties.retentionInDays), cap = todouble(properties.workspaceCapping.dailyQuotaGb)"
    $queries['alerts'] = "resources | where type in~ ('microsoft.insights/activitylogalerts', 'microsoft.insights/metricalerts', 'microsoft.insights/scheduledqueryrules') | project id = tolower(id), name, type = tolower(type), resourceGroup, subscriptionId = tolower(subscriptionId), enabled = tostring(properties.enabled), actions = properties.actions, condition = properties.condition, scopes = properties.scopes"
    $queries['actionGroups'] = "resources | where type =~ 'microsoft.insights/actiongroups' | project id = tolower(id), name, subscriptionId = tolower(subscriptionId), enabled = tostring(properties.enabled)"
    $queries['patches'] = "patchassessmentresources | where type in~ ('microsoft.compute/virtualmachines/patchassessmentresults', 'microsoft.hybridcompute/machines/patchassessmentresults') | project id = tolower(id), machine = tostring(split(tolower(id), '/patchassessmentresults/')[0]), status = tostring(properties.status), last = tostring(properties.lastModifiedDateTime), os = tostring(properties.osType), critical = toint(coalesce(properties.availablePatchCountByClassification.critical, 0)), security = toint(coalesce(properties.availablePatchCountByClassification.security, 0)), other = toint(coalesce(properties.availablePatchCountByClassification.other, 0)) + toint(coalesce(properties.availablePatchCountByClassification.updates, 0)) + toint(coalesce(properties.availablePatchCountByClassification.updateRollup, 0)), reboot = tostring(properties.rebootPending)"
    $queries['arc'] = "resources$Filter | where type =~ 'microsoft.hybridcompute/machines' | project id = tolower(id), name, resourceGroup, subscriptionId = tolower(subscriptionId), location, status = tostring(properties.status), agent = tostring(properties.agentVersion), os = tostring(coalesce(properties.osSku, properties.osName)), osType = tostring(properties.osType), lastChange = tostring(properties.lastStatusChange)"
    $queries['deprecated'] = @(
        "resources$Filter | extend t = tolower(type)"
        "| where (t =~ 'microsoft.network/publicipaddresses' and tostring(sku.name) =~ 'Basic')"
        "or (t =~ 'microsoft.network/loadbalancers' and tostring(sku.name) =~ 'Basic')"
        "or (t =~ 'microsoft.compute/virtualmachines' and (isnotempty(tostring(properties.storageProfile.osDisk.vhd.uri)) or tolower(tostring(properties.hardwareProfile.vmSize)) matches regex '^(basic_a[0-9]+|standard_a[0-9]+)$'))"
        "or t startswith 'microsoft.classic'"
        "or (t =~ 'microsoft.network/virtualnetworkgateways' and tostring(properties.sku.name) =~ 'Basic')"
        "or (t =~ 'microsoft.network/applicationgateways' and tostring(properties.sku.tier) in~ ('Standard', 'WAF'))"
        "or t in~ ('microsoft.dbformysql/servers', 'microsoft.dbforpostgresql/servers')"
        "or (t =~ 'microsoft.cache/redis' and tostring(properties.redisVersion) startswith '4')"
        "| project id = tolower(id), name, type = t, resourceGroup, subscriptionId = tolower(subscriptionId), sku = tostring(sku.name), size = tostring(properties.hardwareProfile.vmSize), vhd = tostring(properties.storageProfile.osDisk.vhd.uri), gatewaySku = tostring(properties.sku.name), agTier = tostring(properties.sku.tier), redis = tostring(properties.redisVersion)"
    ) -join ' '
    $queries
}
