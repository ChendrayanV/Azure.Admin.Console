function Get-AACAssessmentCatalog {
    <#
    .SYNOPSIS
        The resource types Invoke-AACAssessment inventories, one sheet each:
        what to read and which columns to show - in the spirit of Azure
        Resource Inventory's (ARI) inventory modules, as Resource Graph
        projections.
    .DESCRIPTION
        Each sheet is a hashtable:
          Category   Compute, Containers, Databases, Analytics, AI,
                     Integration, IoT, Management, Monitoring, Networking,
                     Security, Storage, Web, Hybrid
          Sheet      its name (a CSV file, an HTML table, a PDF section)
          Type       the resource type(s) it reads (one, or several)
          Table      the Resource Graph table (resources by default)
          Where      more KQL filters ('| where ...'), optional
          Pre        KQL after the filters - mv-expand (a row per subnet,
                     peering, rule...) or a join - optional
          NameLabel  what the Name column is called (default 'Name'):
                     'Virtual network' for its subnets, ...
          Columns    an ordered dictionary: label -> spec (below)
          Key        the labels the PDF shows (it can't show them all)

        Every sheet also gets Subscription, Resource group, Name and
        Location first, and - from Invoke-AACAssessment - Retirement, Advisor,
        cost and tags columns after its own, and the resource ID.

        Column specs:
          'properties.a.b'     the value at that path, as text (also sku.*,
                               kind, identity.*, zones, tags...)
          'int:path'           a whole number        'num:path' a number
          'gb:path'            bytes as GB           'len:path' an array's length
          'join:path'          an array of text, joined with ', '
          'leaf:path'          the name at the end of a resource ID
          'vnet:path'          the virtual network in a subnet ID
          'subnet:path'        the subnet in a subnet ID
          'date:path'          a date
          'kql:expression'     any KQL expression
          '@names:path'        an array of objects: their names       (in
          '@leafs:path'        an array of {id}: the names at the end  Power-
          '@subnets:path'      an array of {id}: 'vnet/subnet'         Shell,
          '@pick:path|a.b'     an array: each item's a.b, joined       after
          '@pickleaf:path|a.b' each item's a.b ID's name, joined       the
          '@sum:path|a.b'      an array: the sum of each item's a.b    query)
          '@keys:path'         an object's keys, joined
          'x:name'             filled in after the query by
                               Invoke-AACAssessment: vmCpu, vmMemory
                               (Compute SKUs), subnetUsable, subnetFree
    #>
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param()

    $sheets = [System.Collections.Generic.List[hashtable]]::new()
    $add = { param([hashtable] $Definition) $sheets.Add($Definition) }

    # Shared bits.
    $nic0 = 'properties.ipConfigurations[0].properties'
    $peConnection = 'coalesce(tostring(properties.privateLinkServiceConnections[0].properties.privateLinkServiceId), tostring(properties.manualPrivateLinkServiceConnections[0].properties.privateLinkServiceId))'
    $idName = { param([string] $Expression) "extract(@'[^/]+`$', 0, tostring($Expression))" }

    # --- Compute -----------------------------------------------------------------------------------------------
    & $add @{
        Category = 'Compute'; Sheet = 'Virtual machines'; Type = 'microsoft.compute/virtualmachines'
        # The first NIC's IP, subnet, NSG and public IP - two joins.
        Pre = "| extend nicId = tolower(tostring(properties.networkProfile.networkInterfaces[0].id)) | join kind=leftouter (resources | where type =~ 'microsoft.network/networkinterfaces' | project nicId = tolower(id), nicNsg = tostring(properties.networkSecurityGroup.id), nicAccel = tostring(properties.enableAcceleratedNetworking), nicIp = tostring(properties.ipConfigurations[0].properties.privateIPAddress), nicSubnet = tostring(properties.ipConfigurations[0].properties.subnet.id), pipId = tolower(tostring(properties.ipConfigurations[0].properties.publicIPAddress.id))) on nicId | join kind=leftouter (resources | where type =~ 'microsoft.network/publicipaddresses' | project pipId = tolower(id), pipAddress = tostring(properties.ipAddress)) on pipId"
        Columns = [ordered]@{
            'Size' = 'properties.hardwareProfile.vmSize'; 'vCPUs' = 'x:vmCpu'; 'Memory (GB)' = 'x:vmMemory'
            'Power state' = 'properties.extended.instanceView.powerState.displayStatus'
            'OS type' = 'properties.storageProfile.osDisk.osType'
            'OS' = 'kql:coalesce(tostring(properties.extended.instanceView.osName), tostring(properties.storageProfile.imageReference.offer))'
            'OS version' = 'kql:coalesce(tostring(properties.extended.instanceView.osVersion), tostring(properties.storageProfile.imageReference.sku))'
            'Image publisher' = 'properties.storageProfile.imageReference.publisher'
            'Computer name' = 'properties.osProfile.computerName'; 'Zones' = 'join:zones'
            'Availability set' = 'leaf:properties.availabilitySet.id'; 'Proximity placement group' = 'leaf:properties.proximityPlacementGroup.id'
            'Priority' = 'properties.priority'; 'License' = 'properties.licenseType'
            'OS disk type' = 'properties.storageProfile.osDisk.managedDisk.storageAccountType'; 'OS disk (GB)' = 'int:properties.storageProfile.osDisk.diskSizeGB'
            'Data disks' = 'len:properties.storageProfile.dataDisks'; 'Data disks (GB)' = '@sum:properties.storageProfile.dataDisks|diskSizeGB'
            'Private IP' = 'nicIp'; 'Virtual network' = 'vnet:nicSubnet'; 'Subnet' = 'subnet:nicSubnet'; 'NIC NSG' = 'leaf:nicNsg'
            'Public IP' = 'pipAddress'; 'Accelerated networking' = 'nicAccel'; 'NICs' = 'len:properties.networkProfile.networkInterfaces'
            'Security type' = 'properties.securityProfile.securityType'; 'Secure boot' = 'properties.securityProfile.uefiSettings.secureBootEnabled'
            'Encryption at host' = 'properties.securityProfile.encryptionAtHost'; 'Boot diagnostics' = 'properties.diagnosticsProfile.bootDiagnostics.enabled'
            'Patch mode' = 'kql:coalesce(tostring(properties.osProfile.windowsConfiguration.patchSettings.patchMode), tostring(properties.osProfile.linuxConfiguration.patchSettings.patchMode))'
            'Password sign-in disabled' = 'properties.osProfile.linuxConfiguration.disablePasswordAuthentication'
            'Admin user' = 'properties.osProfile.adminUsername'; 'Identity' = 'identity.type'; 'Created' = 'date:properties.timeCreated'
        }
        Key = @('Size', 'Power state', 'OS', 'Private IP', 'Virtual network', 'Public IP')
    }
    & $add @{
        Category = 'Compute'; Sheet = 'VM extensions'; Type = 'microsoft.compute/virtualmachines/extensions'; NameLabel = 'Extension'
        Columns = [ordered]@{
            'Virtual machine' = "kql:tostring(split(id, '/')[8])"; 'Publisher' = 'properties.publisher'; 'Type' = 'properties.type'
            'Version' = 'properties.typeHandlerVersion'; 'Auto upgrade' = 'properties.autoUpgradeMinorVersion'; 'Automatic upgrade' = 'properties.enableAutomaticUpgrade'
            'State' = 'properties.provisioningState'
        }
        Key = @('Virtual machine', 'Publisher', 'Type', 'Version', 'State')
    }
    & $add @{
        Category = 'Compute'; Sheet = 'Scale sets'; Type = 'microsoft.compute/virtualmachinescalesets'
        Columns = [ordered]@{
            'Size' = 'sku.name'; 'Instances' = 'int:sku.capacity'; 'vCPUs (each)' = 'x:vmCpu'; 'Memory (GB, each)' = 'x:vmMemory'
            'Orchestration' = 'properties.orchestrationMode'; 'Upgrade policy' = 'properties.upgradePolicy.mode'
            'OS type' = 'properties.virtualMachineProfile.storageProfile.osDisk.osType'
            'Image' = 'kql:strcat(tostring(properties.virtualMachineProfile.storageProfile.imageReference.offer), " ", tostring(properties.virtualMachineProfile.storageProfile.imageReference.sku))'
            'Zones' = 'join:zones'; 'Zone balance' = 'properties.zoneBalance'; 'Single placement group' = 'properties.singlePlacementGroup'
            'OS disk type' = 'properties.virtualMachineProfile.storageProfile.osDisk.managedDisk.storageAccountType'; 'OS disk (GB)' = 'int:properties.virtualMachineProfile.storageProfile.osDisk.diskSizeGB'
            'Virtual network' = 'vnet:properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations[0].properties.ipConfigurations[0].properties.subnet.id'
            'Subnet' = 'subnet:properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations[0].properties.ipConfigurations[0].properties.subnet.id'
            'NSG' = 'leaf:properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations[0].properties.networkSecurityGroup.id'
            'Accelerated networking' = 'properties.virtualMachineProfile.networkProfile.networkInterfaceConfigurations[0].properties.enableAcceleratedNetworking'
            'AKS node pool' = "kql:tostring(tags['aks-managed-poolName'])"; 'Admin user' = 'properties.virtualMachineProfile.osProfile.adminUsername'
            'Created' = 'date:properties.timeCreated'
        }
        Key = @('Size', 'Instances', 'Orchestration', 'OS type', 'Zones', 'Virtual network')
    }
    & $add @{
        Category = 'Compute'; Sheet = 'Disks'; Type = 'microsoft.compute/disks'
        Columns = [ordered]@{
            'State' = 'properties.diskState'; 'Attached to' = 'leaf:managedBy'; 'SKU' = 'sku.name'; 'Size (GB)' = 'int:properties.diskSizeGB'
            'Performance tier' = 'properties.tier'; 'IOPS' = 'int:properties.diskIOPSReadWrite'; 'MBps' = 'int:properties.diskMBpsReadWrite'
            'OS type' = 'properties.osType'; 'Zones' = 'join:zones'; 'Encryption' = 'properties.encryption.type'
            'Network access' = 'properties.networkAccessPolicy'; 'Public network access' = 'properties.publicNetworkAccess'
            'Bursting' = 'properties.burstingEnabled'; 'Max shares' = 'int:properties.maxShares'; 'Created' = 'date:properties.timeCreated'
        }
        Key = @('State', 'Attached to', 'SKU', 'Size (GB)', 'Network access')
    }
    & $add @{
        Category = 'Compute'; Sheet = 'Snapshots'; Type = 'microsoft.compute/snapshots'
        Columns = [ordered]@{
            'SKU' = 'sku.name'; 'Size (GB)' = 'int:properties.diskSizeGB'; 'Incremental' = 'properties.incremental'; 'Source' = 'leaf:properties.creationData.sourceResourceId'
            'OS type' = 'properties.osType'; 'Network access' = 'properties.networkAccessPolicy'; 'Created' = 'date:properties.timeCreated'
        }
        Key = @('SKU', 'Size (GB)', 'Incremental', 'Source', 'Created')
    }
    & $add @{
        Category = 'Compute'; Sheet = 'Availability sets'; Type = 'microsoft.compute/availabilitysets'
        Columns = [ordered]@{
            'SKU' = 'sku.name'; 'Fault domains' = 'int:properties.platformFaultDomainCount'; 'Update domains' = 'int:properties.platformUpdateDomainCount'
            'VMs' = 'len:properties.virtualMachines'; 'Virtual machines' = '@leafs:properties.virtualMachines'; 'Proximity placement group' = 'leaf:properties.proximityPlacementGroup.id'
        }
        Key = @('Fault domains', 'Update domains', 'VMs', 'Virtual machines')
    }
    & $add @{
        Category = 'Compute'; Sheet = 'Proximity placement groups'; Type = 'microsoft.compute/proximityplacementgroups'
        Columns = [ordered]@{ 'Type' = 'properties.proximityPlacementGroupType'; 'VMs' = 'len:properties.virtualMachines'; 'Availability sets' = 'len:properties.availabilitySets'; 'Scale sets' = 'len:properties.virtualMachineScaleSets'; 'Zones' = 'join:zones' }
        Key = @('Type', 'VMs', 'Availability sets', 'Scale sets')
    }
    & $add @{
        Category = 'Compute'; Sheet = 'Cloud services'; Type = @('microsoft.compute/cloudservices', 'microsoft.classiccompute/domainnames')
        Columns = [ordered]@{ 'Type' = 'type'; 'Upgrade mode' = 'properties.upgradeMode'; 'Roles' = '@names:properties.roleProfile.roles'; 'Status' = 'properties.status'; 'Label' = 'properties.label'; 'Host name' = 'properties.hostName' }
        Key = @('Type', 'Upgrade mode', 'Roles', 'Status')
    }
    & $add @{
        Category = 'Compute'; Sheet = 'Virtual desktop host pools'; Type = 'microsoft.desktopvirtualization/hostpools'
        Columns = [ordered]@{
            'Pool type' = 'properties.hostPoolType'; 'Load balancing' = 'properties.loadBalancerType'; 'Max sessions' = 'int:properties.maxSessionLimit'
            'Preferred app group' = 'properties.preferredAppGroupType'; 'Validation' = 'properties.validationEnvironment'; 'Start VM on connect' = 'properties.startVMOnConnect'
            'App groups' = 'len:properties.applicationGroupReferences'
        }
        Key = @('Pool type', 'Load balancing', 'Max sessions', 'App groups')
    }
    & $add @{
        Category = 'Compute'; Sheet = 'Virtual desktop session hosts'; Type = 'microsoft.desktopvirtualization/hostpools/sessionhosts'; Table = 'desktopvirtualizationresources'; NameLabel = 'Session host'
        Columns = [ordered]@{
            'Host pool' = "kql:tostring(split(id, '/')[8])"; 'Status' = 'properties.status'; 'Sessions' = 'int:properties.sessions'; 'Allow new sessions' = 'properties.allowNewSession'
            'Assigned user' = 'properties.assignedUser'; 'Agent version' = 'properties.agentVersion'; 'OS version' = 'properties.osVersion'; 'Update state' = 'properties.updateState'
            'Virtual machine' = 'leaf:properties.resourceId'
        }
        Key = @('Host pool', 'Status', 'Sessions', 'Assigned user', 'Agent version')
    }
    & $add @{
        Category = 'Compute'; Sheet = 'Azure VMware Solution'; Type = 'microsoft.avs/privateclouds'
        Columns = [ordered]@{
            'SKU' = 'sku.name'; 'Hosts' = 'int:properties.managementCluster.clusterSize'; 'Availability' = 'properties.availability.strategy'; 'Network block' = 'properties.networkBlock'
            'Internet' = 'properties.internet'; 'Encryption' = 'properties.encryption.status'; 'vCenter' = 'properties.endpoints.vcsa'; 'NSX-T' = 'properties.endpoints.nsxtManager'
        }
        Key = @('SKU', 'Hosts', 'Availability', 'Network block')
    }

    # --- Hybrid -------------------------------------------------------------------------------------------------
    & $add @{
        Category = 'Hybrid'; Sheet = 'Arc servers'; Type = 'microsoft.hybridcompute/machines'
        Columns = [ordered]@{
            'Status' = 'properties.status'; 'Last status change' = 'date:properties.lastStatusChange'; 'OS' = 'properties.osName'; 'OS version' = 'properties.osVersion'; 'OS SKU' = 'properties.osSku'
            'Agent version' = 'properties.agentVersion'; 'Domain' = 'properties.domainName'; 'FQDN' = 'properties.dnsFqdn'; 'Cloud provider' = 'properties.cloudMetadata.provider'
            'Manufacturer' = 'properties.detectedProperties.manufacturer'; 'Model' = 'properties.detectedProperties.model'; 'Logical cores' = 'int:properties.detectedProperties.logicalCoreCount'
            'Memory (GB)' = 'num:properties.detectedProperties.totalPhysicalMemoryInGigabytes'; 'SQL Server found' = 'properties.mssqlDiscovered'
            'License status' = 'properties.licenseProfile.licenseStatus'; 'ESU' = 'properties.licenseProfile.esuProfile.licenseAssignmentState'
        }
        Key = @('Status', 'OS', 'Agent version', 'Cloud provider', 'Last status change')
    }

    # --- Containers -------------------------------------------------------------------------------------------
    & $add @{
        Category = 'Containers'; Sheet = 'AKS clusters'; Type = 'microsoft.containerservice/managedclusters'
        Columns = [ordered]@{
            'Kubernetes version' = 'kql:coalesce(tostring(properties.currentKubernetesVersion), tostring(properties.kubernetesVersion))'; 'Tier' = 'sku.tier'; 'Power state' = 'properties.powerState.code'
            'Node pools' = 'len:properties.agentPoolProfiles'; 'Nodes' = '@sum:properties.agentPoolProfiles|count'; 'Node sizes' = '@pick:properties.agentPoolProfiles|vmSize'
            'Network plugin' = 'properties.networkProfile.networkPlugin'; 'Plugin mode' = 'properties.networkProfile.networkPluginMode'; 'Network policy' = 'properties.networkProfile.networkPolicy'
            'Outbound' = 'properties.networkProfile.outboundType'; 'Pod CIDR' = 'properties.networkProfile.podCidr'; 'Service CIDR' = 'properties.networkProfile.serviceCidr'
            'Private cluster' = 'properties.apiServerAccessProfile.enablePrivateCluster'; 'Authorized IP ranges' = 'len:properties.apiServerAccessProfile.authorizedIPRanges'
            'Entra ID' = 'kql:iff(isnotempty(tostring(properties.aadProfile)), "Yes", "No")'; 'Azure RBAC' = 'properties.aadProfile.enableAzureRBAC'; 'Local accounts disabled' = 'properties.disableLocalAccounts'
            'Upgrade channel' = 'properties.autoUpgradeProfile.upgradeChannel'; 'Node OS upgrade' = 'properties.autoUpgradeProfile.nodeOSUpgradeChannel'
            'Container insights' = 'kql:coalesce(tostring(properties.addonProfiles.omsagent.enabled), tostring(properties.addonProfiles.omsAgent.enabled))'
            'Azure Policy' = 'properties.addonProfiles.azurepolicy.enabled'; 'Defender' = 'properties.securityProfile.defender.securityMonitoring.enabled'
            'Workload identity' = 'properties.securityProfile.workloadIdentity.enabled'; 'FQDN' = 'kql:coalesce(tostring(properties.fqdn), tostring(properties.privateFQDN))'
            'Node resource group' = 'properties.nodeResourceGroup'
        }
        Key = @('Kubernetes version', 'Tier', 'Nodes', 'Network plugin', 'Private cluster', 'Upgrade channel')
    }
    & $add @{
        Category = 'Containers'; Sheet = 'AKS node pools'; Type = 'microsoft.containerservice/managedclusters'; NameLabel = 'Cluster'
        Pre = '| mv-expand pool = properties.agentPoolProfiles'
        Columns = [ordered]@{
            'Node pool' = 'pool.name'; 'Mode' = 'pool.mode'; 'Size' = 'pool.vmSize'; 'Nodes' = 'int:pool.count'; 'Autoscale' = 'pool.enableAutoScaling'; 'Min' = 'int:pool.minCount'; 'Max' = 'int:pool.maxCount'
            'OS' = 'pool.osType'; 'OS SKU' = 'pool.osSKU'; 'Version' = 'pool.orchestratorVersion'; 'Zones' = 'join:pool.availabilityZones'; 'Max pods' = 'int:pool.maxPods'
            'OS disk (GB)' = 'int:pool.osDiskSizeGB'; 'OS disk type' = 'pool.osDiskType'; 'Priority' = 'pool.scaleSetPriority'; 'Power state' = 'pool.powerState.code'
            'Virtual network' = 'vnet:pool.vnetSubnetID'; 'Subnet' = 'subnet:pool.vnetSubnetID'
        }
        Key = @('Node pool', 'Mode', 'Size', 'Nodes', 'Version', 'Zones')
    }
    & $add @{
        Category = 'Containers'; Sheet = 'OpenShift clusters'; Type = 'microsoft.redhatopenshift/openshiftclusters'
        Columns = [ordered]@{
            'Version' = 'properties.clusterProfile.version'; 'Domain' = 'properties.clusterProfile.domain'; 'Outbound' = 'properties.networkProfile.outboundType'
            'API visibility' = 'properties.apiserverProfile.visibility'; 'API URL' = 'properties.apiserverProfile.url'; 'Console' = 'properties.consoleProfile.url'
            'Master size' = 'properties.masterProfile.vmSize'; 'Worker size' = 'kql:tostring(properties.workerProfiles[0].vmSize)'; 'Workers' = '@sum:properties.workerProfiles|count'
            'Pod CIDR' = 'properties.networkProfile.podCidr'; 'Service CIDR' = 'properties.networkProfile.serviceCidr'
        }
        Key = @('Version', 'API visibility', 'Master size', 'Worker size', 'Workers')
    }
    & $add @{
        Category = 'Containers'; Sheet = 'Container apps'; Type = 'microsoft.app/containerapps'
        Columns = [ordered]@{
            'Environment' = 'kql:extract(@"[^/]+$", 0, coalesce(tostring(properties.managedEnvironmentId), tostring(properties.environmentId)))'; 'Status' = 'properties.runningStatus'
            'Workload profile' = 'properties.workloadProfileName'; 'Revision mode' = 'properties.configuration.activeRevisionsMode'
            'External ingress' = 'properties.configuration.ingress.external'; 'Target port' = 'int:properties.configuration.ingress.targetPort'; 'Transport' = 'properties.configuration.ingress.transport'
            'Insecure allowed' = 'properties.configuration.ingress.allowInsecure'; 'FQDN' = 'properties.configuration.ingress.fqdn'
            'Min replicas' = 'int:properties.template.scale.minReplicas'; 'Max replicas' = 'int:properties.template.scale.maxReplicas'
            'Containers' = 'len:properties.template.containers'; 'Images' = '@pick:properties.template.containers|image'; 'Dapr' = 'properties.configuration.dapr.enabled'; 'Identity' = 'identity.type'
        }
        Key = @('Environment', 'Status', 'External ingress', 'Min replicas', 'Max replicas', 'Images')
    }
    & $add @{
        Category = 'Containers'; Sheet = 'Container app environments'; Type = 'microsoft.app/managedenvironments'
        Columns = [ordered]@{
            'Zone redundant' = 'properties.zoneRedundant'; 'Internal' = 'properties.vnetConfiguration.internal'; 'Static IP' = 'properties.staticIp'; 'Public network access' = 'properties.publicNetworkAccess'
            'Virtual network' = 'vnet:properties.vnetConfiguration.infrastructureSubnetId'; 'Subnet' = 'subnet:properties.vnetConfiguration.infrastructureSubnetId'
            'Workload profiles' = '@names:properties.workloadProfiles'; 'Logs' = 'properties.appLogsConfiguration.destination'; 'Default domain' = 'properties.defaultDomain'
        }
        Key = @('Zone redundant', 'Internal', 'Virtual network', 'Workload profiles')
    }
    & $add @{
        Category = 'Containers'; Sheet = 'Container instances'; Type = 'microsoft.containerinstance/containergroups'
        Columns = [ordered]@{
            'OS' = 'properties.osType'; 'State' = 'properties.instanceView.state'; 'Restart policy' = 'properties.restartPolicy'; 'SKU' = 'properties.sku'
            'IP' = 'properties.ipAddress.ip'; 'IP type' = 'properties.ipAddress.type'; 'Ports' = '@pick:properties.ipAddress.ports|port'
            'Containers' = 'len:properties.containers'; 'Images' = '@pick:properties.containers|properties.image'
            'CPU' = '@sum:properties.containers|properties.resources.requests.cpu'; 'Memory (GB)' = '@sum:properties.containers|properties.resources.requests.memoryInGB'
            'Subnet' = '@subnets:properties.subnetIds'
        }
        Key = @('OS', 'State', 'IP type', 'Containers', 'Images')
    }
    & $add @{
        Category = 'Containers'; Sheet = 'Container registries'; Type = 'microsoft.containerregistry/registries'
        Columns = [ordered]@{
            'SKU' = 'sku.name'; 'Login server' = 'properties.loginServer'; 'Admin user' = 'properties.adminUserEnabled'; 'Anonymous pull' = 'properties.anonymousPullEnabled'
            'Public network access' = 'properties.publicNetworkAccess'; 'Default action' = 'properties.networkRuleSet.defaultAction'; 'Private endpoints' = 'len:properties.privateEndpointConnections'
            'Zone redundancy' = 'properties.zoneRedundancy'; 'Encryption' = 'properties.encryption.status'; 'Retention policy' = 'properties.policies.retentionPolicy.status'
            'Dedicated data endpoints' = 'properties.dataEndpointEnabled'; 'Created' = 'date:properties.creationDate'
        }
        Key = @('SKU', 'Admin user', 'Public network access', 'Private endpoints', 'Zone redundancy')
    }

    # --- Databases ----------------------------------------------------------------------------------------------
    & $add @{
        Category = 'Databases'; Sheet = 'Cosmos DB'; Type = 'microsoft.documentdb/databaseaccounts'
        Columns = [ordered]@{
            'Kind' = 'kind'; 'APIs' = 'kql:coalesce(tostring(properties.EnabledApiTypes), tostring(properties.enabledApiTypes))'; 'Consistency' = 'properties.consistencyPolicy.defaultConsistencyLevel'
            'Regions' = '@pick:properties.locations|locationName'; 'Multi-region writes' = 'properties.enableMultipleWriteLocations'; 'Automatic failover' = 'properties.enableAutomaticFailover'
            'Serverless' = 'kql:iff(tostring(properties.capabilities) has "EnableServerless", "Yes", "No")'; 'Free tier' = 'properties.enableFreeTier'
            'Backup' = 'properties.backupPolicy.type'; 'Backup redundancy' = 'properties.backupPolicy.periodicModeProperties.backupStorageRedundancy'
            'Public network access' = 'properties.publicNetworkAccess'; 'VNet filter' = 'properties.isVirtualNetworkFilterEnabled'; 'IP rules' = 'len:properties.ipRules'
            'Private endpoints' = 'len:properties.privateEndpointConnections'; 'Local auth disabled' = 'properties.disableLocalAuth'; 'Minimum TLS' = 'properties.minimalTlsVersion'
            'Endpoint' = 'properties.documentEndpoint'
        }
        Key = @('APIs', 'Consistency', 'Regions', 'Backup', 'Public network access')
    }
    foreach ($single in @(@('MySQL servers (single)', 'microsoft.dbformysql/servers'), @('PostgreSQL servers (single)', 'microsoft.dbforpostgresql/servers'), @('MariaDB servers', 'microsoft.dbformariadb/servers'))) {
        & $add @{
            Category = 'Databases'; Sheet = $single[0]; Type = $single[1]
            Columns = [ordered]@{
                'SKU' = 'sku.name'; 'Tier' = 'sku.tier'; 'vCores' = 'int:sku.capacity'; 'Version' = 'properties.version'; 'State' = 'properties.userVisibleState'
                'Storage (GB)' = 'kql:round(todouble(properties.storageProfile.storageMB) / 1024, 1)'; 'Auto grow' = 'properties.storageProfile.storageAutogrow'
                'Backup days' = 'int:properties.storageProfile.backupRetentionDays'; 'Geo-redundant backup' = 'properties.storageProfile.geoRedundantBackup'
                'SSL enforced' = 'properties.sslEnforcement'; 'Minimum TLS' = 'properties.minimalTlsVersion'; 'Public network access' = 'properties.publicNetworkAccess'
                'Private endpoints' = 'len:properties.privateEndpointConnections'; 'Replication role' = 'properties.replicationRole'; 'Admin' = 'properties.administratorLogin'
                'FQDN' = 'properties.fullyQualifiedDomainName'
            }
            Key = @('SKU', 'Version', 'State', 'Storage (GB)', 'Public network access')
        }
    }
    & $add @{
        Category = 'Databases'; Sheet = 'MySQL flexible servers'; Type = 'microsoft.dbformysql/flexibleservers'
        Columns = [ordered]@{
            'SKU' = 'sku.name'; 'Tier' = 'sku.tier'; 'Version' = 'properties.version'; 'State' = 'properties.state'; 'Zone' = 'properties.availabilityZone'
            'High availability' = 'properties.highAvailability.mode'; 'Standby zone' = 'properties.highAvailability.standbyAvailabilityZone'
            'Storage (GB)' = 'int:properties.storage.storageSizeGB'; 'IOPS' = 'int:properties.storage.iops'; 'Auto grow' = 'properties.storage.autoGrow'
            'Backup days' = 'int:properties.backup.backupRetentionDays'; 'Geo-redundant backup' = 'properties.backup.geoRedundantBackup'
            'Public network access' = 'properties.network.publicNetworkAccess'; 'Delegated subnet' = 'subnet:properties.network.delegatedSubnetResourceId'
            'Replication role' = 'properties.replicationRole'; 'Admin' = 'properties.administratorLogin'; 'FQDN' = 'properties.fullyQualifiedDomainName'
        }
        Key = @('SKU', 'Version', 'State', 'High availability', 'Public network access')
    }
    & $add @{
        Category = 'Databases'; Sheet = 'PostgreSQL flexible servers'; Type = 'microsoft.dbforpostgresql/flexibleservers'
        Columns = [ordered]@{
            'SKU' = 'sku.name'; 'Tier' = 'sku.tier'; 'Version' = 'kql:strcat(tostring(properties.version), iff(isnotempty(tostring(properties.minorVersion)), strcat(".", tostring(properties.minorVersion)), ""))'
            'State' = 'properties.state'; 'Zone' = 'properties.availabilityZone'; 'High availability' = 'properties.highAvailability.mode'
            'Storage (GB)' = 'int:properties.storage.storageSizeGB'; 'Storage tier' = 'properties.storage.tier'; 'Auto grow' = 'properties.storage.autoGrow'
            'Backup days' = 'int:properties.backup.backupRetentionDays'; 'Geo-redundant backup' = 'properties.backup.geoRedundantBackup'
            'Public network access' = 'properties.network.publicNetworkAccess'; 'Delegated subnet' = 'subnet:properties.network.delegatedSubnetResourceId'
            'Private DNS zone' = 'leaf:properties.network.privateDnsZoneArmResourceId'; 'Entra ID auth' = 'properties.authConfig.activeDirectoryAuth'
            'Password auth' = 'properties.authConfig.passwordAuth'; 'Encryption' = 'properties.dataEncryption.type'; 'Replication role' = 'properties.replicationRole'
            'FQDN' = 'properties.fullyQualifiedDomainName'
        }
        Key = @('SKU', 'Version', 'State', 'High availability', 'Public network access')
    }
    & $add @{
        Category = 'Databases'; Sheet = 'Azure Cache for Redis'; Type = 'microsoft.cache/redis'
        Columns = [ordered]@{
            'SKU' = 'kql:strcat(tostring(properties.sku.name), " ", tostring(properties.sku.family), tostring(properties.sku.capacity))'; 'Version' = 'properties.redisVersion'
            'Shards' = 'int:properties.shardCount'; 'Replicas' = 'int:properties.replicasPerMaster'; 'Zones' = 'join:zones'
            'Non-SSL port' = 'properties.enableNonSslPort'; 'Minimum TLS' = 'properties.minimumTlsVersion'; 'Public network access' = 'properties.publicNetworkAccess'
            'Access keys disabled' = 'properties.disableAccessKeyAuthentication'; 'Subnet' = 'subnet:properties.subnetId'; 'Private endpoints' = 'len:properties.privateEndpointConnections'
            'Host' = 'properties.hostName'
        }
        Key = @('SKU', 'Version', 'Non-SSL port', 'Minimum TLS', 'Public network access')
    }
    & $add @{
        Category = 'Databases'; Sheet = 'Redis Enterprise'; Type = 'microsoft.cache/redisenterprise'
        Columns = [ordered]@{ 'SKU' = 'sku.name'; 'Capacity' = 'int:sku.capacity'; 'Zones' = 'join:zones'; 'Version' = 'properties.redisVersion'; 'Minimum TLS' = 'properties.minimumTlsVersion'; 'Host' = 'properties.hostName'; 'Private endpoints' = 'len:properties.privateEndpointConnections' }
        Key = @('SKU', 'Capacity', 'Zones', 'Minimum TLS')
    }
    & $add @{
        Category = 'Databases'; Sheet = 'SQL servers'; Type = 'microsoft.sql/servers'; Where = "| where kind !contains 'analytics'"
        Columns = [ordered]@{
            'Version' = 'properties.version'; 'State' = 'properties.state'; 'Admin' = 'properties.administratorLogin'; 'Entra admin' = 'properties.administrators.login'
            'Entra-only auth' = 'properties.administrators.azureADOnlyAuthentication'; 'Public network access' = 'properties.publicNetworkAccess'; 'Minimum TLS' = 'properties.minimalTlsVersion'
            'Private endpoints' = 'len:properties.privateEndpointConnections'; 'Outbound restricted' = 'properties.restrictOutboundNetworkAccess'; 'FQDN' = 'properties.fullyQualifiedDomainName'
        }
        Key = @('Version', 'Entra-only auth', 'Public network access', 'Minimum TLS', 'Private endpoints')
    }
    & $add @{
        Category = 'Databases'; Sheet = 'SQL databases'; Type = 'microsoft.sql/servers/databases'; Where = "| where name != 'master'"
        Columns = [ordered]@{
            'Server' = "kql:tostring(split(id, '/')[8])"; 'SKU' = 'sku.name'; 'Tier' = 'sku.tier'; 'Capacity' = 'int:sku.capacity'; 'Status' = 'properties.status'
            'Max size (GB)' = 'gb:properties.maxSizeBytes'; 'Elastic pool' = 'leaf:properties.elasticPoolId'; 'Zone redundant' = 'properties.zoneRedundant'
            'Backup redundancy' = 'kql:coalesce(tostring(properties.currentBackupStorageRedundancy), tostring(properties.requestedBackupStorageRedundancy))'
            'License' = 'properties.licenseType'; 'Read scale' = 'properties.readScale'; 'HA replicas' = 'int:properties.highAvailabilityReplicaCount'
            'Auto-pause (min)' = 'int:properties.autoPauseDelay'; 'Min capacity' = 'num:properties.minCapacity'; 'Collation' = 'properties.collation'
            'Ledger' = 'properties.isLedgerOn'; 'Created' = 'date:properties.creationDate'
        }
        Key = @('Server', 'SKU', 'Tier', 'Max size (GB)', 'Elastic pool', 'Backup redundancy')
    }
    & $add @{
        Category = 'Databases'; Sheet = 'SQL elastic pools'; Type = 'microsoft.sql/servers/elasticpools'
        Columns = [ordered]@{
            'Server' = "kql:tostring(split(id, '/')[8])"; 'SKU' = 'sku.name'; 'Tier' = 'sku.tier'; 'Capacity' = 'int:sku.capacity'; 'State' = 'properties.state'
            'Max size (GB)' = 'gb:properties.maxSizeBytes'; 'Per-database min' = 'num:properties.perDatabaseSettings.minCapacity'; 'Per-database max' = 'num:properties.perDatabaseSettings.maxCapacity'
            'Zone redundant' = 'properties.zoneRedundant'; 'License' = 'properties.licenseType'
        }
        Key = @('Server', 'SKU', 'Capacity', 'Max size (GB)', 'Zone redundant')
    }
    & $add @{
        Category = 'Databases'; Sheet = 'SQL managed instances'; Type = 'microsoft.sql/managedinstances'
        Columns = [ordered]@{
            'SKU' = 'sku.name'; 'Tier' = 'sku.tier'; 'vCores' = 'int:properties.vCores'; 'Storage (GB)' = 'int:properties.storageSizeInGB'; 'State' = 'properties.state'
            'License' = 'properties.licenseType'; 'Public endpoint' = 'properties.publicDataEndpointEnabled'; 'Connection type' = 'properties.proxyOverride'
            'Zone redundant' = 'properties.zoneRedundant'; 'Virtual network' = 'vnet:properties.subnetId'; 'Subnet' = 'subnet:properties.subnetId'
            'Minimum TLS' = 'properties.minimalTlsVersion'; 'Entra-only auth' = 'properties.administrators.azureADOnlyAuthentication'
            'Backup redundancy' = 'properties.requestedBackupStorageRedundancy'; 'FQDN' = 'properties.fullyQualifiedDomainName'
        }
        Key = @('SKU', 'vCores', 'Storage (GB)', 'Public endpoint', 'Zone redundant')
    }
    & $add @{
        Category = 'Databases'; Sheet = 'SQL managed instance databases'; Type = 'microsoft.sql/managedinstances/databases'
        Columns = [ordered]@{ 'Instance' = "kql:tostring(split(id, '/')[8])"; 'Status' = 'properties.status'; 'Collation' = 'properties.collation'; 'Secondary location' = 'properties.defaultSecondaryLocation'; 'Created' = 'date:properties.creationDate' }
        Key = @('Instance', 'Status', 'Collation', 'Created')
    }
    & $add @{
        Category = 'Databases'; Sheet = 'SQL virtual machines'; Type = 'microsoft.sqlvirtualmachine/sqlvirtualmachines'
        Columns = [ordered]@{
            'Virtual machine' = 'leaf:properties.virtualMachineResourceId'; 'License' = 'properties.sqlServerLicenseType'; 'Image' = 'properties.sqlImageOffer'; 'Edition' = 'properties.sqlImageSku'
            'Management' = 'properties.sqlManagement'; 'Auto patching' = 'properties.autoPatchingSettings.enable'; 'Auto backup' = 'properties.autoBackupSettings.enable'
        }
        Key = @('Virtual machine', 'License', 'Image', 'Edition')
    }

    # --- Analytics ----------------------------------------------------------------------------------------------
    & $add @{
        Category = 'Analytics'; Sheet = 'Databricks'; Type = 'microsoft.databricks/workspaces'
        Columns = [ordered]@{
            'Tier' = 'sku.name'; 'Managed resource group' = "kql:tostring(split(tostring(properties.managedResourceGroupId), '/')[4])"; 'No public IP' = 'properties.parameters.enableNoPublicIp.value'
            'Custom virtual network' = 'leaf:properties.parameters.customVirtualNetworkId.value'; 'Public network access' = 'properties.publicNetworkAccess'
            'Infrastructure encryption' = 'properties.parameters.requireInfrastructureEncryption.value'; 'URL' = 'properties.workspaceUrl'; 'Created' = 'date:properties.createdDateTime'
        }
        Key = @('Tier', 'No public IP', 'Custom virtual network', 'Public network access')
    }
    & $add @{
        Category = 'Analytics'; Sheet = 'Data Explorer clusters'; Type = 'microsoft.kusto/clusters'
        Columns = [ordered]@{
            'SKU' = 'sku.name'; 'Instances' = 'int:sku.capacity'; 'State' = 'properties.state'; 'Optimized autoscale' = 'properties.optimizedAutoscale.isEnabled'
            'Min' = 'int:properties.optimizedAutoscale.minimum'; 'Max' = 'int:properties.optimizedAutoscale.maximum'; 'Disk encryption' = 'properties.enableDiskEncryption'
            'Double encryption' = 'properties.enableDoubleEncryption'; 'Streaming ingestion' = 'properties.enableStreamingIngest'; 'Public network access' = 'properties.publicNetworkAccess'
            'Zones' = 'join:zones'; 'URI' = 'properties.uri'
        }
        Key = @('SKU', 'Instances', 'State', 'Optimized autoscale', 'Public network access')
    }
    & $add @{
        Category = 'Analytics'; Sheet = 'Event Hubs namespaces'; Type = 'microsoft.eventhub/namespaces'
        Columns = [ordered]@{
            'SKU' = 'sku.name'; 'Throughput units' = 'int:sku.capacity'; 'Status' = 'properties.status'; 'Zone redundant' = 'properties.zoneRedundant'
            'Auto-inflate' = 'properties.isAutoInflateEnabled'; 'Max throughput units' = 'int:properties.maximumThroughputUnits'; 'Kafka' = 'properties.kafkaEnabled'
            'Local auth disabled' = 'properties.disableLocalAuth'; 'Minimum TLS' = 'properties.minimumTlsVersion'; 'Public network access' = 'properties.publicNetworkAccess'
            'Private endpoints' = 'len:properties.privateEndpointConnections'; 'Created' = 'date:properties.createdAt'
        }
        Key = @('SKU', 'Throughput units', 'Auto-inflate', 'Local auth disabled', 'Public network access')
    }
    & $add @{
        Category = 'Analytics'; Sheet = 'Purview'; Type = 'microsoft.purview/accounts'
        Columns = [ordered]@{ 'SKU' = 'sku.name'; 'Capacity' = 'int:sku.capacity'; 'Public network access' = 'properties.publicNetworkAccess'; 'Managed resource group' = 'properties.managedResourceGroupName'; 'Private endpoints' = 'len:properties.privateEndpointConnections'; 'Created by' = 'properties.createdBy'; 'Created' = 'date:properties.createdAt' }
        Key = @('SKU', 'Capacity', 'Public network access', 'Private endpoints')
    }
    & $add @{
        Category = 'Analytics'; Sheet = 'Stream Analytics jobs'; Type = 'microsoft.streamanalytics/streamingjobs'
        Columns = [ordered]@{ 'SKU' = 'properties.sku.name'; 'State' = 'properties.jobState'; 'Type' = 'properties.jobType'; 'Compatibility level' = 'properties.compatibilityLevel'; 'Cluster' = 'leaf:properties.cluster.id'; 'Last output' = 'date:properties.lastOutputEventTime'; 'Created' = 'date:properties.createdDate' }
        Key = @('SKU', 'State', 'Type', 'Cluster', 'Last output')
    }
    & $add @{
        Category = 'Analytics'; Sheet = 'Stream Analytics clusters'; Type = 'microsoft.streamanalytics/clusters'
        Columns = [ordered]@{ 'SKU' = 'sku.name'; 'Capacity' = 'int:sku.capacity'; 'Allocated' = 'int:properties.capacityAllocated'; 'Assigned' = 'int:properties.capacityAssigned'; 'Created' = 'date:properties.createdDate' }
        Key = @('SKU', 'Capacity', 'Allocated', 'Assigned')
    }
    & $add @{
        Category = 'Analytics'; Sheet = 'Synapse workspaces'; Type = 'microsoft.synapse/workspaces'
        Columns = [ordered]@{
            'Public network access' = 'properties.publicNetworkAccess'; 'Managed virtual network' = 'properties.managedVirtualNetwork'; 'Data exfiltration protection' = 'properties.managedVirtualNetworkSettings.preventDataExfiltration'
            'Entra-only auth' = 'properties.azureADOnlyAuthentication'; 'SQL admin' = 'properties.sqlAdministratorLogin'; 'Double encryption' = 'properties.encryption.doubleEncryptionEnabled'
            'Private endpoints' = 'len:properties.privateEndpointConnections'; 'Managed resource group' = 'properties.managedResourceGroupName'; 'Web' = 'properties.connectivityEndpoints.web'
        }
        Key = @('Public network access', 'Managed virtual network', 'Entra-only auth', 'Private endpoints')
    }
    & $add @{
        Category = 'Analytics'; Sheet = 'Data factories'; Type = 'microsoft.datafactory/factories'
        Columns = [ordered]@{ 'Public network access' = 'properties.publicNetworkAccess'; 'Git' = 'properties.repoConfiguration.type'; 'Repository' = 'properties.repoConfiguration.repositoryName'; 'Encryption' = 'kql:iff(isnotempty(tostring(properties.encryption.keyName)), "Customer-managed", "Microsoft-managed")'; 'Identity' = 'identity.type'; 'Created' = 'date:properties.createTime' }
        Key = @('Public network access', 'Git', 'Encryption')
    }

    # --- AI -----------------------------------------------------------------------------------------------------
    & $add @{
        Category = 'AI'; Sheet = 'Azure AI services'; Type = 'microsoft.cognitiveservices/accounts'
        Columns = [ordered]@{
            'Kind' = 'kind'; 'SKU' = 'sku.name'; 'Endpoint' = 'properties.endpoint'; 'Custom domain' = 'properties.customSubDomainName'
            'Public network access' = 'properties.publicNetworkAccess'; 'Default action' = 'properties.networkAcls.defaultAction'; 'IP rules' = 'len:properties.networkAcls.ipRules'
            'VNet rules' = 'len:properties.networkAcls.virtualNetworkRules'; 'Private endpoints' = 'len:properties.privateEndpointConnections'
            'Local auth disabled' = 'properties.disableLocalAuth'; 'Outbound restricted' = 'properties.restrictOutboundNetworkAccess'; 'Encryption' = 'properties.encryption.keySource'
            'Identity' = 'identity.type'; 'Created' = 'date:properties.dateCreated'
        }
        Key = @('Kind', 'SKU', 'Public network access', 'Local auth disabled', 'Private endpoints')
    }
    & $add @{
        Category = 'AI'; Sheet = 'Machine Learning workspaces'; Type = 'microsoft.machinelearningservices/workspaces'
        Columns = [ordered]@{
            'Kind' = 'kind'; 'SKU' = 'sku.name'; 'Friendly name' = 'properties.friendlyName'; 'High business impact' = 'properties.hbiWorkspace'; 'Public network access' = 'properties.publicNetworkAccess'
            'Managed network' = 'properties.managedNetwork.isolationMode'; 'Storage account' = 'leaf:properties.storageAccount'; 'Key vault' = 'leaf:properties.keyVault'
            'Application Insights' = 'leaf:properties.applicationInsights'; 'Container registry' = 'leaf:properties.containerRegistry'; 'Private endpoints' = 'len:properties.privateEndpointConnections'
        }
        Key = @('Kind', 'Public network access', 'Managed network', 'Storage account')
    }
    & $add @{
        Category = 'AI'; Sheet = 'AI Search'; Type = 'microsoft.search/searchservices'
        Columns = [ordered]@{
            'SKU' = 'sku.name'; 'Replicas' = 'int:properties.replicaCount'; 'Partitions' = 'int:properties.partitionCount'; 'Hosting mode' = 'properties.hostingMode'; 'Status' = 'properties.status'
            'Public network access' = 'properties.publicNetworkAccess'; 'Local auth disabled' = 'properties.disableLocalAuth'; 'Semantic ranker' = 'properties.semanticSearch'
            'CMK enforcement' = 'properties.encryptionWithCmk.enforcement'; 'IP rules' = 'len:properties.networkRuleSet.ipRules'; 'Private endpoints' = 'len:properties.privateEndpointConnections'
        }
        Key = @('SKU', 'Replicas', 'Partitions', 'Public network access', 'Local auth disabled')
    }

    # --- Integration and IoT ------------------------------------------------------------------------------------
    & $add @{
        Category = 'Integration'; Sheet = 'API Management'; Type = 'microsoft.apimanagement/service'
        Columns = [ordered]@{
            'SKU' = 'sku.name'; 'Units' = 'int:sku.capacity'; 'Platform version' = 'properties.platformVersion'; 'VNet type' = 'properties.virtualNetworkType'
            'Virtual network' = 'vnet:properties.virtualNetworkConfiguration.subnetResourceId'; 'Subnet' = 'subnet:properties.virtualNetworkConfiguration.subnetResourceId'
            'Public IPs' = 'join:properties.publicIPAddresses'; 'Private IPs' = 'join:properties.privateIPAddresses'; 'Public network access' = 'properties.publicNetworkAccess'; 'Zones' = 'join:zones'
            'Client TLS 1.0' = "kql:tostring(properties.customProperties['Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10'])"
            'Backend TLS 1.0' = "kql:tostring(properties.customProperties['Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10'])"
            'Triple DES' = "kql:tostring(properties.customProperties['Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TripleDes168'])"
            'Gateway URL' = 'properties.gatewayUrl'
        }
        Key = @('SKU', 'Units', 'Platform version', 'VNet type', 'Public network access')
    }
    & $add @{
        Category = 'Integration'; Sheet = 'Service Bus namespaces'; Type = 'microsoft.servicebus/namespaces'
        Columns = [ordered]@{
            'SKU' = 'sku.name'; 'Capacity' = 'int:sku.capacity'; 'Status' = 'properties.status'; 'Zone redundant' = 'properties.zoneRedundant'; 'Local auth disabled' = 'properties.disableLocalAuth'
            'Minimum TLS' = 'properties.minimumTlsVersion'; 'Public network access' = 'properties.publicNetworkAccess'; 'Private endpoints' = 'len:properties.privateEndpointConnections'
            'Endpoint' = 'properties.serviceBusEndpoint'; 'Created' = 'date:properties.createdAt'
        }
        Key = @('SKU', 'Status', 'Local auth disabled', 'Minimum TLS', 'Public network access')
    }
    & $add @{
        Category = 'Integration'; Sheet = 'Event Grid'; Type = @('microsoft.eventgrid/topics', 'microsoft.eventgrid/domains', 'microsoft.eventgrid/namespaces')
        Columns = [ordered]@{ 'Type' = 'type'; 'Public network access' = 'properties.publicNetworkAccess'; 'Local auth disabled' = 'properties.disableLocalAuth'; 'Input schema' = 'properties.inputSchema'; 'Minimum TLS' = 'properties.minimumTlsVersionAllowed'; 'Private endpoints' = 'len:properties.privateEndpointConnections'; 'Endpoint' = 'properties.endpoint' }
        Key = @('Type', 'Public network access', 'Local auth disabled')
    }
    & $add @{
        Category = 'IoT'; Sheet = 'IoT hubs'; Type = 'microsoft.devices/iothubs'
        Columns = [ordered]@{
            'SKU' = 'sku.name'; 'Units' = 'int:sku.capacity'; 'State' = 'properties.state'; 'Public network access' = 'properties.publicNetworkAccess'; 'Local auth disabled' = 'properties.disableLocalAuth'
            'Minimum TLS' = 'properties.minTlsVersion'; 'IP filter rules' = 'len:properties.ipFilterRules'; 'Retention (days)' = 'int:properties.eventHubEndpoints.events.retentionTimeInDays'
            'Partitions' = 'int:properties.eventHubEndpoints.events.partitionCount'; 'Host' = 'properties.hostName'
        }
        Key = @('SKU', 'Units', 'State', 'Public network access', 'Local auth disabled')
    }

    # --- Management ---------------------------------------------------------------------------------------------
    & $add @{
        Category = 'Management'; Sheet = 'Automation accounts'; Type = 'microsoft.automation/automationaccounts'
        Columns = [ordered]@{ 'SKU' = 'properties.sku.name'; 'State' = 'properties.state'; 'Public network access' = 'properties.publicNetworkAccess'; 'Local auth disabled' = 'properties.disableLocalAuth'; 'Identity' = 'identity.type'; 'Created' = 'date:properties.creationTime'; 'Last modified' = 'date:properties.lastModifiedTime' }
        Key = @('SKU', 'State', 'Identity', 'Public network access')
    }
    & $add @{
        Category = 'Management'; Sheet = 'Runbooks'; Type = 'microsoft.automation/automationaccounts/runbooks'; NameLabel = 'Runbook'
        Columns = [ordered]@{ 'Automation account' = "kql:tostring(split(id, '/')[8])"; 'Type' = 'properties.runbookType'; 'Runtime' = 'properties.runtimeEnvironment'; 'State' = 'properties.state'; 'Last modified' = 'date:properties.lastModifiedTime'; 'Description' = 'properties.description' }
        Key = @('Automation account', 'Type', 'State', 'Last modified')
    }
    & $add @{
        Category = 'Management'; Sheet = 'Recovery Services vaults'; Type = 'microsoft.recoveryservices/vaults'
        Columns = [ordered]@{
            'SKU' = 'sku.name'; 'Storage redundancy' = 'properties.redundancySettings.standardTierStorageRedundancy'; 'Cross-region restore' = 'properties.redundancySettings.crossRegionRestore'
            'Immutability' = 'properties.securitySettings.immutabilitySettings.state'; 'Soft delete' = 'properties.securitySettings.softDeleteSettings.softDeleteState'
            'Public network access' = 'properties.publicNetworkAccess'; 'Private endpoints (backup)' = 'properties.privateEndpointStateForBackup'
            'Private endpoints (site recovery)' = 'properties.privateEndpointStateForSiteRecovery'; 'Identity' = 'identity.type'
        }
        Key = @('SKU', 'Storage redundancy', 'Immutability', 'Soft delete', 'Public network access')
    }
    & $add @{
        Category = 'Management'; Sheet = 'Backup items'; Type = 'microsoft.recoveryservices/vaults/backupfabrics/protectioncontainers/protecteditems'; Table = 'recoveryservicesresources'; NameLabel = 'Item'
        Columns = [ordered]@{
            'Vault' = "kql:tostring(split(id, '/')[8])"; 'Protected item' = 'properties.friendlyName'; 'Workload' = 'properties.workloadType'; 'Management type' = 'properties.backupManagementType'
            'Policy' = 'properties.policyName'; 'Protection state' = 'properties.protectionState'; 'Health' = 'properties.healthStatus'; 'Last backup status' = 'properties.lastBackupStatus'
            'Last backup' = 'date:properties.lastBackupTime'; 'Last recovery point' = 'date:properties.lastRecoveryPoint'; 'Source resource' = 'leaf:properties.sourceResourceId'
            'Archive' = 'properties.isArchiveEnabled'
        }
        Key = @('Vault', 'Protected item', 'Workload', 'Policy', 'Last backup status', 'Last backup')
    }
    & $add @{
        Category = 'Management'; Sheet = 'Backup policies'; Type = 'microsoft.recoveryservices/vaults/backuppolicies'; Table = 'recoveryservicesresources'; NameLabel = 'Policy'
        Columns = [ordered]@{
            'Vault' = "kql:tostring(split(id, '/')[8])"; 'Management type' = 'properties.backupManagementType'; 'Workload' = 'properties.workLoadType'; 'Policy type' = 'properties.policyType'
            'Protected items' = 'int:properties.protectedItemsCount'; 'Frequency' = 'properties.schedulePolicy.scheduleRunFrequency'
            'Daily retention' = 'int:properties.retentionPolicy.dailySchedule.retentionDuration.count'; 'Instant restore (days)' = 'int:properties.instantRpRetentionRangeInDays'; 'Time zone' = 'properties.timeZone'
        }
        Key = @('Vault', 'Management type', 'Protected items', 'Frequency', 'Daily retention')
    }
    & $add @{
        Category = 'Management'; Sheet = 'Managed identities'; Type = 'microsoft.managedidentity/userassignedidentities'
        Columns = [ordered]@{ 'Client ID' = 'properties.clientId'; 'Principal ID' = 'properties.principalId'; 'Tenant' = 'properties.tenantId' }
        Key = @('Client ID', 'Principal ID')
    }

    # --- Monitoring ---------------------------------------------------------------------------------------------
    & $add @{
        Category = 'Monitoring'; Sheet = 'Application Insights'; Type = 'microsoft.insights/components'
        Columns = [ordered]@{
            'Type' = 'properties.Application_Type'; 'Ingestion mode' = 'properties.IngestionMode'; 'Workspace' = 'leaf:properties.WorkspaceResourceId'; 'Retention (days)' = 'int:properties.RetentionInDays'
            'Sampling (%)' = 'num:properties.SamplingPercentage'; 'Public ingestion' = 'properties.publicNetworkAccessForIngestion'; 'Public query' = 'properties.publicNetworkAccessForQuery'
            'Local auth disabled' = 'properties.DisableLocalAuth'; 'Created' = 'date:properties.CreationDate'
        }
        Key = @('Type', 'Ingestion mode', 'Workspace', 'Retention (days)')
    }
    & $add @{
        Category = 'Monitoring'; Sheet = 'Log Analytics workspaces'; Type = 'microsoft.operationalinsights/workspaces'
        Columns = [ordered]@{
            'SKU' = 'properties.sku.name'; 'Retention (days)' = 'int:properties.retentionInDays'; 'Daily cap (GB)' = 'num:properties.workspaceCapping.dailyQuotaGb'
            'Public ingestion' = 'properties.publicNetworkAccessForIngestion'; 'Public query' = 'properties.publicNetworkAccessForQuery'
            'Local auth disabled' = 'properties.features.disableLocalAuth'; 'Resource permissions' = 'properties.features.enableLogAccessUsingOnlyResourcePermissions'
            'Workspace ID' = 'properties.customerId'; 'Created' = 'date:properties.createdDate'
        }
        Key = @('SKU', 'Retention (days)', 'Daily cap (GB)', 'Public ingestion')
    }
    & $add @{
        Category = 'Monitoring'; Sheet = 'Data collection rules'; Type = 'microsoft.insights/datacollectionrules'
        Columns = [ordered]@{ 'Kind' = 'kind'; 'Data sources' = '@keys:properties.dataSources'; 'Destinations' = '@keys:properties.destinations'; 'Data flows' = 'len:properties.dataFlows'; 'Endpoint' = 'leaf:properties.dataCollectionEndpointId' }
        Key = @('Kind', 'Data sources', 'Destinations', 'Data flows')
    }

    # --- Networking ---------------------------------------------------------------------------------------------
    & $add @{
        Category = 'Networking'; Sheet = 'Virtual networks'; Type = 'microsoft.network/virtualnetworks'
        Columns = [ordered]@{
            'Address space' = 'join:properties.addressSpace.addressPrefixes'; 'Subnets' = 'len:properties.subnets'; 'Subnet names' = '@names:properties.subnets'
            'Peerings' = 'len:properties.virtualNetworkPeerings'; 'DNS servers' = 'join:properties.dhcpOptions.dnsServers'; 'DDoS protection' = 'properties.enableDdosProtection'
            'DDoS plan' = 'leaf:properties.ddosProtectionPlan.id'; 'Encryption' = 'properties.encryption.enabled'; 'Flow timeout (min)' = 'int:properties.flowTimeoutInMinutes'
        }
        Key = @('Address space', 'Subnets', 'Peerings', 'DNS servers')
    }
    & $add @{
        Category = 'Networking'; Sheet = 'Subnets'; Type = 'microsoft.network/virtualnetworks'; NameLabel = 'Virtual network'; Pre = '| mv-expand subnet = properties.subnets'
        Columns = [ordered]@{
            'Subnet' = 'subnet.name'; 'Prefix' = 'kql:coalesce(tostring(subnet.properties.addressPrefix), strcat_array(subnet.properties.addressPrefixes, ", "))'
            'IP configurations' = 'len:subnet.properties.ipConfigurations'; 'Usable IPs' = 'x:subnetUsable'; 'Available IPs' = 'x:subnetFree'
            'NSG' = 'leaf:subnet.properties.networkSecurityGroup.id'; 'Route table' = 'leaf:subnet.properties.routeTable.id'; 'NAT gateway' = 'leaf:subnet.properties.natGateway.id'
            'Private endpoints' = 'len:subnet.properties.privateEndpoints'; 'Service endpoints' = '@pick:subnet.properties.serviceEndpoints|service'
            'Delegations' = '@pick:subnet.properties.delegations|properties.serviceName'
            'Private subnet' = 'kql:iff(tostring(subnet.properties.defaultOutboundAccess) =~ "false", "Yes", "No")'; 'PE network policies' = 'subnet.properties.privateEndpointNetworkPolicies'
        }
        Key = @('Subnet', 'Prefix', 'Available IPs', 'NSG', 'Route table', 'Delegations')
    }
    & $add @{
        Category = 'Networking'; Sheet = 'Peerings'; Type = 'microsoft.network/virtualnetworks'; NameLabel = 'Virtual network'; Pre = '| mv-expand peer = properties.virtualNetworkPeerings'
        Columns = [ordered]@{
            'Peering' = 'peer.name'; 'Remote network' = 'leaf:peer.properties.remoteVirtualNetwork.id'; 'Remote subscription' = "kql:tostring(split(tostring(peer.properties.remoteVirtualNetwork.id), '/')[2])"
            'State' = 'peer.properties.peeringState'; 'Sync' = 'peer.properties.peeringSyncLevel'; 'Network access' = 'peer.properties.allowVirtualNetworkAccess'
            'Forwarded traffic' = 'peer.properties.allowForwardedTraffic'; 'Gateway transit' = 'peer.properties.allowGatewayTransit'; 'Uses remote gateways' = 'peer.properties.useRemoteGateways'
            'Remote address space' = 'join:peer.properties.remoteAddressSpace.addressPrefixes'
        }
        Key = @('Peering', 'Remote network', 'State', 'Sync', 'Gateway transit', 'Uses remote gateways')
    }
    & $add @{
        Category = 'Networking'; Sheet = 'Network interfaces'; Type = 'microsoft.network/networkinterfaces'
        Columns = [ordered]@{
            'Virtual machine' = 'leaf:properties.virtualMachine.id'; 'Private endpoint' = 'leaf:properties.privateEndpoint.id'
            'Private IP' = "$nic0.privateIPAddress"; 'Allocation' = "$nic0.privateIPAllocationMethod"; 'Virtual network' = "vnet:$nic0.subnet.id"; 'Subnet' = "subnet:$nic0.subnet.id"
            'Public IP' = "leaf:$nic0.publicIPAddress.id"; 'NSG' = 'leaf:properties.networkSecurityGroup.id'; 'Accelerated networking' = 'properties.enableAcceleratedNetworking'
            'IP forwarding' = 'properties.enableIPForwarding'; 'IP configurations' = 'len:properties.ipConfigurations'; 'DNS servers' = 'join:properties.dnsSettings.dnsServers'; 'MAC' = 'properties.macAddress'
            'Orphaned' = 'kql:iff(isempty(tostring(properties.virtualMachine.id)) and isempty(tostring(properties.privateEndpoint.id)) and isempty(tostring(properties.privateLinkService.id)), "Yes", "No")'
        }
        Key = @('Virtual machine', 'Private IP', 'Virtual network', 'Subnet', 'Public IP', 'Orphaned')
    }
    & $add @{
        Category = 'Networking'; Sheet = 'Network security groups'; Type = 'microsoft.network/networksecuritygroups'
        Columns = [ordered]@{
            'Rules' = 'len:properties.securityRules'; 'Subnets' = '@subnets:properties.subnets'; 'NICs' = 'len:properties.networkInterfaces'
            'Flow logs' = 'len:properties.flowLogs'
            'Orphaned' = 'kql:iff(coalesce(array_length(properties.subnets), 0) == 0 and coalesce(array_length(properties.networkInterfaces), 0) == 0, "Yes", "No")'
        }
        Key = @('Rules', 'Subnets', 'NICs', 'Orphaned')
    }
    & $add @{
        Category = 'Networking'; Sheet = 'NSG rules'; Type = 'microsoft.network/networksecuritygroups'; NameLabel = 'NSG'; Pre = '| mv-expand rule = properties.securityRules'
        Columns = [ordered]@{
            'Rule' = 'rule.name'; 'Priority' = 'int:rule.properties.priority'; 'Direction' = 'rule.properties.direction'; 'Access' = 'rule.properties.access'; 'Protocol' = 'rule.properties.protocol'
            'Source' = 'kql:coalesce(tostring(rule.properties.sourceAddressPrefix), strcat_array(rule.properties.sourceAddressPrefixes, ", "), iff(isnotnull(rule.properties.sourceApplicationSecurityGroups), "ASG", ""))'
            'Source ports' = 'kql:coalesce(tostring(rule.properties.sourcePortRange), strcat_array(rule.properties.sourcePortRanges, ", "))'
            'Destination' = 'kql:coalesce(tostring(rule.properties.destinationAddressPrefix), strcat_array(rule.properties.destinationAddressPrefixes, ", "), iff(isnotnull(rule.properties.destinationApplicationSecurityGroups), "ASG", ""))'
            'Destination ports' = 'kql:coalesce(tostring(rule.properties.destinationPortRange), strcat_array(rule.properties.destinationPortRanges, ", "))'
            'Description' = 'rule.properties.description'
        }
        Key = @('Rule', 'Priority', 'Direction', 'Access', 'Source', 'Destination ports')
    }
    & $add @{
        Category = 'Networking'; Sheet = 'Application security groups'; Type = 'microsoft.network/applicationsecuritygroups'
        Columns = [ordered]@{ 'State' = 'properties.provisioningState' }
        Key = @('State')
    }
    & $add @{
        Category = 'Networking'; Sheet = 'Public IP addresses'; Type = 'microsoft.network/publicipaddresses'
        Columns = [ordered]@{
            'IP address' = 'properties.ipAddress'; 'SKU' = 'sku.name'; 'Tier' = 'sku.tier'; 'Allocation' = 'properties.publicIPAllocationMethod'; 'Version' = 'properties.publicIPAddressVersion'
            'DNS name' = 'properties.dnsSettings.fqdn'; 'Zones' = 'join:zones'
            'Associated with' = "kql:extract(@'(?i)/providers/[^/]+/[^/]+/([^/]+)', 1, tostring(properties.ipConfiguration.id))"
            'Associated type' = "kql:extract(@'(?i)/providers/([^/]+/[^/]+)/', 1, tostring(properties.ipConfiguration.id))"
            'NAT gateway' = 'leaf:properties.natGateway.id'; 'DDoS' = 'properties.ddosSettings.protectionMode'; 'Idle timeout (min)' = 'int:properties.idleTimeoutInMinutes'
            'Orphaned' = 'kql:iff(isempty(tostring(properties.ipConfiguration.id)) and isempty(tostring(properties.natGateway.id)), "Yes", "No")'
        }
        Key = @('IP address', 'SKU', 'Allocation', 'Associated with', 'Orphaned')
    }
    & $add @{
        Category = 'Networking'; Sheet = 'Load balancers'; Type = 'microsoft.network/loadbalancers'
        Columns = [ordered]@{
            'SKU' = 'sku.name'; 'Tier' = 'sku.tier'; 'Frontends' = 'len:properties.frontendIPConfigurations'
            'Frontend private IPs' = '@pick:properties.frontendIPConfigurations|properties.privateIPAddress'; 'Frontend public IPs' = '@pickleaf:properties.frontendIPConfigurations|properties.publicIPAddress.id'
            'Backend pools' = 'len:properties.backendAddressPools'; 'Rules' = 'len:properties.loadBalancingRules'; 'Probes' = 'len:properties.probes'
            'Inbound NAT rules' = 'len:properties.inboundNatRules'; 'Outbound rules' = 'len:properties.outboundRules'
        }
        Key = @('SKU', 'Frontends', 'Backend pools', 'Rules', 'Probes')
    }
    & $add @{
        Category = 'Networking'; Sheet = 'Application gateways'; Type = 'microsoft.network/applicationgateways'
        Columns = [ordered]@{
            'SKU' = 'properties.sku.name'; 'Tier' = 'properties.sku.tier'; 'Capacity' = 'int:properties.sku.capacity'; 'Autoscale min' = 'int:properties.autoscaleConfiguration.minCapacity'
            'Autoscale max' = 'int:properties.autoscaleConfiguration.maxCapacity'; 'State' = 'properties.operationalState'
            'WAF' = 'kql:iff(isnotempty(tostring(properties.firewallPolicy.id)) or tostring(properties.webApplicationFirewallConfiguration.enabled) =~ "true", "Yes", "No")'
            'WAF policy' = 'leaf:properties.firewallPolicy.id'; 'WAF mode' = 'properties.webApplicationFirewallConfiguration.firewallMode'
            'TLS policy' = 'kql:coalesce(tostring(properties.sslPolicy.policyName), tostring(properties.sslPolicy.minProtocolVersion), tostring(properties.sslPolicy.policyType))'
            'HTTP/2' = 'properties.enableHttp2'; 'Zones' = 'join:zones'; 'Listeners' = 'len:properties.httpListeners'; 'Backend pools' = 'len:properties.backendAddressPools'
            'Rules' = 'len:properties.requestRoutingRules'; 'Virtual network' = 'vnet:properties.gatewayIPConfigurations[0].properties.subnet.id'
            'Subnet' = 'subnet:properties.gatewayIPConfigurations[0].properties.subnet.id'
        }
        Key = @('SKU', 'Tier', 'WAF', 'TLS policy', 'Listeners', 'Zones')
    }
    & $add @{
        Category = 'Networking'; Sheet = 'WAF policies'; Type = @('microsoft.network/applicationgatewaywebapplicationfirewallpolicies', 'microsoft.network/frontdoorwebapplicationfirewallpolicies')
        Columns = [ordered]@{
            'Type' = 'type'; 'Mode' = 'properties.policySettings.mode'; 'State' = 'properties.policySettings.enabledState'
            'Managed rule set' = 'kql:strcat(tostring(properties.managedRules.managedRuleSets[0].ruleSetType), " ", tostring(properties.managedRules.managedRuleSets[0].ruleSetVersion))'
            'Custom rules' = 'kql:coalesce(array_length(properties.customRules), array_length(properties.customRules.rules))'; 'Application gateways' = 'len:properties.applicationGateways'
        }
        Key = @('Type', 'Mode', 'State', 'Managed rule set', 'Custom rules')
    }
    & $add @{
        Category = 'Networking'; Sheet = 'Front Door and CDN'; Type = @('microsoft.cdn/profiles', 'microsoft.network/frontdoors')
        Columns = [ordered]@{
            'Type' = 'type'; 'SKU' = 'sku.name'; 'State' = 'kql:coalesce(tostring(properties.resourceState), tostring(properties.enabledState))'
            'Frontends' = 'len:properties.frontendEndpoints'; 'Backend pools' = 'len:properties.backendPools'; 'Routing rules' = 'len:properties.routingRules'
            'Response timeout (s)' = 'int:properties.originResponseTimeoutSeconds'; 'Front Door ID' = 'properties.frontDoorId'
        }
        Key = @('Type', 'SKU', 'State')
    }
    & $add @{
        Category = 'Networking'; Sheet = 'Azure Firewalls'; Type = 'microsoft.network/azurefirewalls'
        Columns = [ordered]@{
            'Tier' = 'properties.sku.tier'; 'SKU' = 'properties.sku.name'; 'Threat intelligence' = 'properties.threatIntelMode'; 'Policy' = 'leaf:properties.firewallPolicy.id'; 'Zones' = 'join:zones'
            'Private IP' = 'kql:coalesce(tostring(properties.ipConfigurations[0].properties.privateIPAddress), tostring(properties.hubIPAddresses.privateIPAddress))'
            'Virtual network' = "vnet:$nic0.subnet.id"; 'Public IPs' = '@pickleaf:properties.ipConfigurations|properties.publicIPAddress.id'
            'Virtual hub' = 'leaf:properties.virtualHub.id'; 'Hub public IPs' = 'int:properties.hubIPAddresses.publicIPs.count'
        }
        Key = @('Tier', 'Threat intelligence', 'Policy', 'Private IP', 'Zones')
    }
    & $add @{
        Category = 'Networking'; Sheet = 'Firewall policies'; Type = 'microsoft.network/firewallpolicies'
        Columns = [ordered]@{
            'Tier' = 'properties.sku.tier'; 'Threat intelligence' = 'properties.threatIntelMode'; 'IDPS' = 'properties.intrusionDetection.mode'; 'DNS proxy' = 'properties.dnsSettings.enableProxy'
            'TLS inspection' = 'kql:iff(isnotempty(tostring(properties.transportSecurity)), "Yes", "No")'; 'Parent policy' = 'leaf:properties.basePolicy.id'
            'Firewalls' = 'len:properties.firewalls'; 'Rule collection groups' = 'len:properties.ruleCollectionGroups'
        }
        Key = @('Tier', 'Threat intelligence', 'IDPS', 'Firewalls')
    }
    & $add @{
        Category = 'Networking'; Sheet = 'Virtual network gateways'; Type = 'microsoft.network/virtualnetworkgateways'
        Columns = [ordered]@{
            'Gateway type' = 'properties.gatewayType'; 'VPN type' = 'properties.vpnType'; 'SKU' = 'properties.sku.name'; 'Generation' = 'properties.vpnGatewayGeneration'
            'Active-active' = 'properties.activeActive'; 'BGP' = 'properties.enableBgp'; 'ASN' = 'int:properties.bgpSettings.asn'; 'BGP address' = 'properties.bgpSettings.bgpPeeringAddress'
            'Virtual network' = "vnet:$nic0.subnet.id"; 'Public IPs' = '@pickleaf:properties.ipConfigurations|properties.publicIPAddress.id'
            'Point-to-site' = 'kql:iff(isnotempty(tostring(properties.vpnClientConfiguration)), "Yes", "No")'
            'P2S address pool' = 'join:properties.vpnClientConfiguration.vpnClientAddressPool.addressPrefixes'; 'Private IP' = 'properties.enablePrivateIpAddress'
        }
        Key = @('Gateway type', 'SKU', 'Active-active', 'BGP', 'Virtual network')
    }
    & $add @{
        Category = 'Networking'; Sheet = 'Local network gateways'; Type = 'microsoft.network/localnetworkgateways'
        Columns = [ordered]@{ 'IP address' = 'properties.gatewayIpAddress'; 'FQDN' = 'properties.fqdn'; 'Address space' = 'join:properties.localNetworkAddressSpace.addressPrefixes'; 'BGP ASN' = 'int:properties.bgpSettings.asn'; 'BGP address' = 'properties.bgpSettings.bgpPeeringAddress' }
        Key = @('IP address', 'Address space', 'BGP ASN')
    }
    & $add @{
        Category = 'Networking'; Sheet = 'Connections'; Type = 'microsoft.network/connections'
        Columns = [ordered]@{
            'Type' = 'properties.connectionType'; 'Status' = 'properties.connectionStatus'; 'Protocol' = 'properties.connectionProtocol'; 'Gateway' = 'leaf:properties.virtualNetworkGateway1.id'
            'Peer' = "kql:coalesce($(& $idName 'properties.localNetworkGateway2.id'), $(& $idName 'properties.peer.id'), $(& $idName 'properties.virtualNetworkGateway2.id'))"
            'BGP' = 'properties.enableBgp'; 'Routing weight' = 'int:properties.routingWeight'; 'Custom IPsec policies' = 'len:properties.ipsecPolicies'; 'Mode' = 'properties.connectionMode'
        }
        Key = @('Type', 'Status', 'Gateway', 'Peer', 'BGP')
    }
    & $add @{
        Category = 'Networking'; Sheet = 'ExpressRoute circuits'; Type = 'microsoft.network/expressroutecircuits'
        Columns = [ordered]@{
            'Tier' = 'sku.tier'; 'Billing' = 'sku.family'; 'Provider' = 'properties.serviceProviderProperties.serviceProviderName'; 'Peering location' = 'properties.serviceProviderProperties.peeringLocation'
            'Bandwidth (Mbps)' = 'int:properties.serviceProviderProperties.bandwidthInMbps'; 'Circuit state' = 'properties.circuitProvisioningState'
            'Provider state' = 'properties.serviceProviderProvisioningState'; 'Global Reach' = 'properties.globalReachEnabled'; 'Peerings' = '@names:properties.peerings'
            'ExpressRoute Direct port' = 'leaf:properties.expressRoutePort.id'
        }
        Key = @('Tier', 'Provider', 'Peering location', 'Bandwidth (Mbps)', 'Provider state')
    }
    & $add @{
        Category = 'Networking'; Sheet = 'NAT gateways'; Type = 'microsoft.network/natgateways'
        Columns = [ordered]@{
            'SKU' = 'sku.name'; 'Idle timeout (min)' = 'int:properties.idleTimeoutInMinutes'; 'Public IPs' = '@leafs:properties.publicIpAddresses'; 'IP prefixes' = '@leafs:properties.publicIpPrefixes'
            'Subnets' = '@subnets:properties.subnets'; 'Zones' = 'join:zones'; 'Orphaned' = 'kql:iff(coalesce(array_length(properties.subnets), 0) == 0, "Yes", "No")'
        }
        Key = @('Public IPs', 'Subnets', 'Zones', 'Orphaned')
    }
    & $add @{
        Category = 'Networking'; Sheet = 'Route tables'; Type = 'microsoft.network/routetables'
        Columns = [ordered]@{
            'Routes' = 'len:properties.routes'; 'BGP propagation disabled' = 'properties.disableBgpRoutePropagation'; 'Subnets' = '@subnets:properties.subnets'
            'Orphaned' = 'kql:iff(coalesce(array_length(properties.subnets), 0) == 0, "Yes", "No")'
        }
        Key = @('Routes', 'BGP propagation disabled', 'Subnets', 'Orphaned')
    }
    & $add @{
        Category = 'Networking'; Sheet = 'Routes'; Type = 'microsoft.network/routetables'; NameLabel = 'Route table'; Pre = '| mv-expand route = properties.routes'
        Columns = [ordered]@{ 'Route' = 'route.name'; 'Prefix' = 'route.properties.addressPrefix'; 'Next hop type' = 'route.properties.nextHopType'; 'Next hop IP' = 'route.properties.nextHopIpAddress'; 'BGP override' = 'route.properties.hasBgpOverride' }
        Key = @('Route', 'Prefix', 'Next hop type', 'Next hop IP')
    }
    & $add @{
        Category = 'Networking'; Sheet = 'Private endpoints'; Type = 'microsoft.network/privateendpoints'
        Columns = [ordered]@{
            'Virtual network' = 'vnet:properties.subnet.id'; 'Subnet' = 'subnet:properties.subnet.id'; 'Target' = "kql:extract(@'[^/]+`$', 0, $peConnection)"
            'Target type' = "kql:extract(@'(?i)/providers/([^/]+/[^/]+)/', 1, $peConnection)"
            'Sub-resource' = 'kql:coalesce(strcat_array(properties.privateLinkServiceConnections[0].properties.groupIds, ", "), strcat_array(properties.manualPrivateLinkServiceConnections[0].properties.groupIds, ", "))'
            'Connection' = 'kql:coalesce(tostring(properties.privateLinkServiceConnections[0].properties.privateLinkServiceConnectionState.status), tostring(properties.manualPrivateLinkServiceConnections[0].properties.privateLinkServiceConnectionState.status))'
            'Manual approval' = 'kql:iff(coalesce(array_length(properties.manualPrivateLinkServiceConnections), 0) > 0, "Yes", "No")'
            'NIC' = 'leaf:properties.networkInterfaces[0].id'; 'Custom DNS entries' = 'len:properties.customDnsConfigs'
        }
        Key = @('Virtual network', 'Subnet', 'Target', 'Sub-resource', 'Connection')
    }
    & $add @{
        Category = 'Networking'; Sheet = 'Private link services'; Type = 'microsoft.network/privatelinkservices'
        Columns = [ordered]@{ 'Alias' = 'properties.alias'; 'Connections' = 'len:properties.privateEndpointConnections'; 'Auto-approved subscriptions' = 'len:properties.autoApproval.subscriptions'; 'Visible to' = 'len:properties.visibility.subscriptions'; 'Load balancer frontends' = 'len:properties.loadBalancerFrontendIpConfigurations' }
        Key = @('Alias', 'Connections', 'Visible to')
    }
    & $add @{
        Category = 'Networking'; Sheet = 'Private DNS zones'; Type = 'microsoft.network/privatednszones'
        Columns = [ordered]@{ 'Records' = 'int:properties.numberOfRecordSets'; 'VNet links' = 'int:properties.numberOfVirtualNetworkLinks'; 'Links with registration' = 'int:properties.numberOfVirtualNetworkLinksWithRegistration' }
        Key = @('Records', 'VNet links', 'Links with registration')
    }
    & $add @{
        Category = 'Networking'; Sheet = 'Private DNS links'; Type = 'microsoft.network/privatednszones/virtualnetworklinks'; NameLabel = 'Link'
        Columns = [ordered]@{
            'Zone' = "kql:tostring(split(id, '/')[8])"; 'Virtual network' = 'leaf:properties.virtualNetwork.id'; 'Network subscription' = "kql:tostring(split(tostring(properties.virtualNetwork.id), '/')[2])"
            'Auto-registration' = 'properties.registrationEnabled'; 'State' = 'properties.virtualNetworkLinkState'; 'Fallback to internet' = 'properties.resolutionPolicy'
        }
        Key = @('Zone', 'Virtual network', 'Auto-registration', 'State')
    }
    & $add @{
        Category = 'Networking'; Sheet = 'Public DNS zones'; Type = 'microsoft.network/dnszones'
        Columns = [ordered]@{ 'Zone type' = 'properties.zoneType'; 'Records' = 'int:properties.numberOfRecordSets'; 'Max records' = 'int:properties.maxNumberOfRecordSets'; 'Name servers' = 'join:properties.nameServers' }
        Key = @('Zone type', 'Records', 'Name servers')
    }
    & $add @{
        Category = 'Networking'; Sheet = 'DNS private resolvers'; Type = 'microsoft.network/dnsresolvers'
        Columns = [ordered]@{ 'Virtual network' = 'leaf:properties.virtualNetwork.id'; 'State' = 'properties.dnsResolverState' }
        Key = @('Virtual network', 'State')
    }
    & $add @{
        Category = 'Networking'; Sheet = 'Traffic Manager'; Type = 'microsoft.network/trafficmanagerprofiles'
        Columns = [ordered]@{
            'Status' = 'properties.profileStatus'; 'Routing' = 'properties.trafficRoutingMethod'; 'DNS name' = 'properties.dnsConfig.fqdn'; 'TTL' = 'int:properties.dnsConfig.ttl'
            'Monitor status' = 'properties.monitorConfig.profileMonitorStatus'; 'Monitor protocol' = 'properties.monitorConfig.protocol'; 'Endpoints' = 'len:properties.endpoints'
        }
        Key = @('Status', 'Routing', 'DNS name', 'Monitor status', 'Endpoints')
    }
    & $add @{
        Category = 'Networking'; Sheet = 'Bastion hosts'; Type = 'microsoft.network/bastionhosts'
        Columns = [ordered]@{
            'SKU' = 'sku.name'; 'Scale units' = 'int:properties.scaleUnits'; 'Virtual network' = "vnet:$nic0.subnet.id"; 'Public IP' = "leaf:$nic0.publicIPAddress.id"
            'Native client' = 'properties.enableTunneling'; 'IP connect' = 'properties.enableIpConnect'; 'Shareable link' = 'properties.enableShareableLink'
            'Copy and paste disabled' = 'properties.disableCopyPaste'; 'Kerberos' = 'properties.enableKerberos'; 'Zones' = 'join:zones'; 'DNS name' = 'properties.dnsName'
        }
        Key = @('SKU', 'Scale units', 'Virtual network', 'Native client', 'Shareable link')
    }
    & $add @{
        Category = 'Networking'; Sheet = 'Virtual WANs'; Type = 'microsoft.network/virtualwans'
        Columns = [ordered]@{ 'Type' = 'properties.type'; 'Branch to branch' = 'properties.allowBranchToBranchTraffic'; 'VPN encryption disabled' = 'properties.disableVpnEncryption'; 'Hubs' = 'len:properties.virtualHubs'; 'VPN sites' = 'len:properties.vpnSites' }
        Key = @('Type', 'Hubs', 'VPN sites', 'Branch to branch')
    }
    & $add @{
        Category = 'Networking'; Sheet = 'Virtual hubs'; Type = 'microsoft.network/virtualhubs'
        Columns = [ordered]@{
            'Virtual WAN' = 'leaf:properties.virtualWan.id'; 'Address prefix' = 'properties.addressPrefix'; 'SKU' = 'properties.sku'; 'Routing state' = 'properties.routingState'
            'Router ASN' = 'int:properties.virtualRouterAsn'; 'Router IPs' = 'join:properties.virtualRouterIps'; 'Routing preference' = 'properties.hubRoutingPreference'
            'Firewall' = 'leaf:properties.azureFirewall.id'; 'VPN gateway' = 'leaf:properties.vpnGateway.id'; 'ExpressRoute gateway' = 'leaf:properties.expressRouteGateway.id'
        }
        Key = @('Virtual WAN', 'Address prefix', 'SKU', 'Firewall', 'VPN gateway')
    }
    & $add @{
        Category = 'Networking'; Sheet = 'VPN sites'; Type = 'microsoft.network/vpnsites'
        Columns = [ordered]@{ 'Virtual WAN' = 'leaf:properties.virtualWan.id'; 'Vendor' = 'properties.deviceProperties.deviceVendor'; 'Links' = 'len:properties.vpnSiteLinks'; 'Link IPs' = '@pick:properties.vpnSiteLinks|properties.ipAddress'; 'Address space' = 'join:properties.addressSpace.addressPrefixes' }
        Key = @('Virtual WAN', 'Vendor', 'Links', 'Address space')
    }
    & $add @{
        Category = 'Networking'; Sheet = 'DDoS protection plans'; Type = 'microsoft.network/ddosprotectionplans'
        Columns = [ordered]@{ 'Virtual networks' = 'len:properties.virtualNetworks'; 'Public IPs' = 'len:properties.publicIPAddresses' }
        Key = @('Virtual networks', 'Public IPs')
    }
    & $add @{
        Category = 'Networking'; Sheet = 'Flow logs'; Type = 'microsoft.network/networkwatchers/flowlogs'; NameLabel = 'Flow log'
        Columns = [ordered]@{
            'Target' = 'leaf:properties.targetResourceId'; 'Target type' = "kql:extract(@'(?i)/providers/([^/]+/[^/]+)/', 1, tostring(properties.targetResourceId))"
            'Enabled' = 'properties.enabled'; 'Version' = 'int:properties.format.version'; 'Retention (days)' = 'int:properties.retentionPolicy.days'; 'Retention on' = 'properties.retentionPolicy.enabled'
            'Storage account' = 'leaf:properties.storageId'; 'Traffic Analytics' = 'properties.flowAnalyticsConfiguration.networkWatcherFlowAnalyticsConfiguration.enabled'
            'Workspace' = 'leaf:properties.flowAnalyticsConfiguration.networkWatcherFlowAnalyticsConfiguration.workspaceResourceId'
        }
        Key = @('Target', 'Target type', 'Enabled', 'Retention (days)', 'Traffic Analytics')
    }

    # --- Security -----------------------------------------------------------------------------------------------
    & $add @{
        Category = 'Security'; Sheet = 'Key vaults'; Type = 'microsoft.keyvault/vaults'
        Columns = [ordered]@{
            'SKU' = 'properties.sku.name'; 'RBAC' = 'properties.enableRbacAuthorization'; 'Soft delete' = 'properties.enableSoftDelete'; 'Retention (days)' = 'int:properties.softDeleteRetentionInDays'
            'Purge protection' = 'properties.enablePurgeProtection'; 'Public network access' = 'properties.publicNetworkAccess'; 'Default action' = 'properties.networkAcls.defaultAction'
            'Bypass' = 'properties.networkAcls.bypass'; 'IP rules' = 'len:properties.networkAcls.ipRules'; 'VNet rules' = 'len:properties.networkAcls.virtualNetworkRules'
            'Private endpoints' = 'len:properties.privateEndpointConnections'; 'Access policies' = 'len:properties.accessPolicies'
            'Disk encryption' = 'properties.enabledForDiskEncryption'; 'Deployment' = 'properties.enabledForDeployment'; 'Template deployment' = 'properties.enabledForTemplateDeployment'
            'URI' = 'properties.vaultUri'
        }
        Key = @('SKU', 'RBAC', 'Purge protection', 'Public network access', 'Default action', 'Private endpoints')
    }

    # --- Storage ------------------------------------------------------------------------------------------------
    & $add @{
        Category = 'Storage'; Sheet = 'Storage accounts'; Type = 'microsoft.storage/storageaccounts'
        Columns = [ordered]@{
            'Kind' = 'kind'; 'SKU' = 'sku.name'; 'Access tier' = 'properties.accessTier'; 'HTTPS only' = 'properties.supportsHttpsTrafficOnly'; 'Minimum TLS' = 'properties.minimumTlsVersion'
            'Public blob access' = 'properties.allowBlobPublicAccess'; 'Shared key access' = 'properties.allowSharedKeyAccess'; 'Entra ID by default' = 'properties.defaultToOAuthAuthentication'
            'Public network access' = 'properties.publicNetworkAccess'; 'Default action' = 'properties.networkAcls.defaultAction'; 'Bypass' = 'properties.networkAcls.bypass'
            'IP rules' = 'len:properties.networkAcls.ipRules'; 'VNet rules' = 'len:properties.networkAcls.virtualNetworkRules'; 'Private endpoints' = 'len:properties.privateEndpointConnections'
            'Hierarchical namespace' = 'properties.isHnsEnabled'; 'SFTP' = 'properties.isSftpEnabled'; 'NFS v3' = 'properties.isNfsV3Enabled'; 'Large file shares' = 'properties.largeFileSharesState'
            'Cross-tenant replication' = 'properties.allowCrossTenantReplication'; 'Infrastructure encryption' = 'properties.encryption.requireInfrastructureEncryption'
            'Key source' = 'properties.encryption.keySource'; 'Files identity auth' = 'properties.azureFilesIdentityBasedAuthentication.directoryServiceOptions'
            'Primary location' = 'properties.primaryLocation'; 'Secondary location' = 'properties.secondaryLocation'; 'Primary status' = 'properties.statusOfPrimary'
            'Created' = 'date:properties.creationTime'
        }
        Key = @('Kind', 'SKU', 'Minimum TLS', 'Public blob access', 'Shared key access', 'Default action')
    }
    & $add @{
        Category = 'Storage'; Sheet = 'NetApp volumes'; Type = 'microsoft.netapp/netappaccounts/capacitypools/volumes'; NameLabel = 'Volume'
        Columns = [ordered]@{
            'Account' = "kql:tostring(split(id, '/')[8])"; 'Capacity pool' = "kql:tostring(split(id, '/')[10])"; 'Service level' = 'properties.serviceLevel'; 'Quota (GB)' = 'gb:properties.usageThreshold'
            'Protocols' = 'join:properties.protocolTypes'; 'Throughput (MiB/s)' = 'num:properties.throughputMibps'; 'Network features' = 'properties.networkFeatures'
            'Virtual network' = 'vnet:properties.subnetId'; 'Subnet' = 'subnet:properties.subnetId'; 'Security style' = 'properties.securityStyle'; 'SMB encryption' = 'properties.smbEncryption'
            'Cool access' = 'properties.coolAccess'
        }
        Key = @('Account', 'Capacity pool', 'Service level', 'Quota (GB)', 'Protocols')
    }
    & $add @{
        Category = 'Storage'; Sheet = 'HPC caches'; Type = 'microsoft.storagecache/caches'
        Columns = [ordered]@{ 'SKU' = 'sku.name'; 'Size (GB)' = 'int:properties.cacheSizeGB'; 'Health' = 'properties.health.state'; 'Subnet' = 'subnet:properties.subnet'; 'Mount addresses' = 'join:properties.mountAddresses' }
        Key = @('SKU', 'Size (GB)', 'Health', 'Subnet')
    }

    # --- Web ----------------------------------------------------------------------------------------------------
    & $add @{
        Category = 'Web'; Sheet = 'App Service plans'; Type = 'microsoft.web/serverfarms'
        Columns = [ordered]@{
            'SKU' = 'sku.name'; 'Tier' = 'sku.tier'; 'Instances' = 'int:sku.capacity'; 'Max instances' = 'int:properties.maximumNumberOfWorkers'
            'OS' = 'kql:iff(tostring(properties.reserved) =~ "true", "Linux", "Windows")'; 'Kind' = 'kind'; 'Apps' = 'int:properties.numberOfSites'
            'Zone redundant' = 'properties.zoneRedundant'; 'Per-app scaling' = 'properties.perSiteScaling'; 'Elastic scale' = 'properties.elasticScaleEnabled'
            'App Service environment' = 'leaf:properties.hostingEnvironmentProfile.id'; 'Status' = 'properties.status'
            'Empty' = 'kql:iff(toint(properties.numberOfSites) == 0, "Yes", "No")'
        }
        Key = @('SKU', 'Instances', 'OS', 'Apps', 'Zone redundant', 'Empty')
    }
    & $add @{
        Category = 'Web'; Sheet = 'App Services'; Type = 'microsoft.web/sites'
        Columns = [ordered]@{
            'Kind' = 'kind'; 'State' = 'properties.state'; 'Plan' = 'leaf:properties.serverFarmId'; 'Default host' = 'properties.defaultHostName'; 'Host names' = 'join:properties.hostNames'
            'HTTPS only' = 'properties.httpsOnly'; 'Minimum TLS' = 'properties.siteConfig.minTlsVersion'; 'FTPS' = 'properties.siteConfig.ftpsState'
            'Runtime' = 'kql:coalesce(tostring(properties.siteConfig.linuxFxVersion), tostring(properties.siteConfig.windowsFxVersion))'
            'Client certificates' = 'properties.clientCertEnabled'; 'Public network access' = 'properties.publicNetworkAccess'
            'VNet integration' = 'vnet:properties.virtualNetworkSubnetId'; 'Integration subnet' = 'subnet:properties.virtualNetworkSubnetId'
            'Private endpoints' = 'len:properties.privateEndpointConnections'; 'Identity' = 'identity.type'; 'Availability' = 'properties.availabilityState'
        }
        Key = @('Kind', 'State', 'Plan', 'HTTPS only', 'Public network access', 'VNet integration')
    }
    & $add @{
        Category = 'Web'; Sheet = 'Deployment slots'; Type = 'microsoft.web/sites/slots'; NameLabel = 'Slot'
        Columns = [ordered]@{ 'App' = "kql:tostring(split(id, '/')[8])"; 'State' = 'properties.state'; 'Default host' = 'properties.defaultHostName'; 'HTTPS only' = 'properties.httpsOnly'; 'Plan' = 'leaf:properties.serverFarmId' }
        Key = @('App', 'State', 'Default host', 'HTTPS only')
    }
    & $add @{
        Category = 'Web'; Sheet = 'Static web apps'; Type = 'microsoft.web/staticsites'
        Columns = [ordered]@{ 'SKU' = 'sku.name'; 'Default host' = 'properties.defaultHostname'; 'Repository' = 'properties.repositoryUrl'; 'Branch' = 'properties.branch'; 'Custom domains' = 'join:properties.customDomains'; 'Provider' = 'properties.provider' }
        Key = @('SKU', 'Default host', 'Repository', 'Custom domains')
    }
    & $add @{
        Category = 'Web'; Sheet = 'App Service environments'; Type = 'microsoft.web/hostingenvironments'
        Columns = [ordered]@{ 'Kind' = 'kind'; 'Status' = 'properties.status'; 'Zone redundant' = 'properties.zoneRedundant'; 'Internal load balancing' = 'properties.internalLoadBalancingMode'; 'Virtual network' = 'vnet:properties.virtualNetwork.id'; 'Subnet' = 'subnet:properties.virtualNetwork.id'; 'Upgrade preference' = 'properties.upgradePreference' }
        Key = @('Kind', 'Status', 'Zone redundant', 'Internal load balancing')
    }

    $sheets.ToArray()
}
