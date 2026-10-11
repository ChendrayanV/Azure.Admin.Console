function ConvertTo-AACResourceExport {
    <#
    .SYNOPSIS
        Turns Export-AACResource's Resource Graph rows into resources an admin can
        read: the subscription and management group by name, the tags as a
        dictionary, and the settings that matter for each type in one Details
        line.
    .DESCRIPTION
        No Azure calls. -Row is the rows of Get-AACResourceExportQuery.

        Each resource (AAC.Resource) has where it is (subscription, its
        management group and the path up to the root, resource group, location,
        zones), what it is (type, kind, SKU, parent for child resources), how it
        is set up (identity, provisioning state, public network access, created
        when Azure records it) and Details: a dozen common types get the
        settings people look up most - a VM's size, OS, image and power state, a
        storage account's TLS, public access and network rules, an App Service's
        plan and runtime, an AKS cluster's version and nodes, and so on.

        -Flatten adds Properties: every property, flattened by
        ConvertTo-AACFlatObject.

        Returns @{ Resources; TagKeys (the tag keys, most used first); Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyCollection()]
        [object[]] $Row = @(),

        [switch] $Flatten
    )

    # The settings shown in Details, per type: label, path, and how to show it
    # (leaf: the last part of an ID; count: how many; join: a list on one line;
    # gb: bytes as GB; sum.<field>: a field added up across a list).
    $details = @{
        'microsoft.compute/virtualmachines'           = @(@('Size', 'properties.hardwareProfile.vmSize'), @('OS', 'properties.storageProfile.osDisk.osType'), @('OS name', 'properties.extended.instanceView.osName'), @('Image', 'properties.storageProfile.imageReference.offer'), @('Image SKU', 'properties.storageProfile.imageReference.sku'), @('Power', 'properties.extended.instanceView.powerState.displayStatus'), @('Data disks', 'properties.storageProfile.dataDisks', 'count'), @('Priority', 'properties.priority'), @('License', 'properties.licenseType'), @('Availability set', 'properties.availabilitySet.id', 'leaf'))
        'microsoft.compute/virtualmachinescalesets'   = @(@('Size', 'sku.name'), @('Instances', 'sku.capacity'), @('Orchestration', 'properties.orchestrationMode'), @('Upgrade policy', 'properties.upgradePolicy.mode'))
        'microsoft.compute/disks'                     = @(@('Size (GiB)', 'properties.diskSizeGB'), @('State', 'properties.diskState'), @('Attached to', 'managedBy', 'leaf'), @('OS', 'properties.osType'), @('Encryption', 'properties.encryption.type'), @('Network access', 'properties.networkAccessPolicy'))
        'microsoft.storage/storageaccounts'           = @(@('Access tier', 'properties.accessTier'), @('HTTPS only', 'properties.supportsHttpsTrafficOnly'), @('Minimum TLS', 'properties.minimumTlsVersion'), @('Blob public access', 'properties.allowBlobPublicAccess'), @('Shared key', 'properties.allowSharedKeyAccess'), @('Default network action', 'properties.networkAcls.defaultAction'), @('Data Lake', 'properties.isHnsEnabled'))
        'microsoft.network/publicipaddresses'         = @(@('IP', 'properties.ipAddress'), @('Allocation', 'properties.publicIPAllocationMethod'), @('Attached to', 'properties.ipConfiguration.id', 'owner'))
        'microsoft.network/networkinterfaces'         = @(@('Private IP', 'properties.ipConfigurations.0.properties.privateIPAddress'), @('VM', 'properties.virtualMachine.id', 'leaf'), @('NSG', 'properties.networkSecurityGroup.id', 'leaf'), @('Subnet', 'properties.ipConfigurations.0.properties.subnet.id', 'leaf'), @('Accelerated networking', 'properties.enableAcceleratedNetworking'), @('IP forwarding', 'properties.enableIPForwarding'))
        'microsoft.network/virtualnetworks'           = @(@('Address space', 'properties.addressSpace.addressPrefixes', 'join'), @('Subnets', 'properties.subnets', 'count'), @('DNS servers', 'properties.dhcpOptions.dnsServers', 'join'), @('Peerings', 'properties.virtualNetworkPeerings', 'count'), @('DDoS protection', 'properties.enableDdosProtection'))
        'microsoft.network/networksecuritygroups'     = @(@('Rules', 'properties.securityRules', 'count'), @('Subnets', 'properties.subnets', 'count'), @('NICs', 'properties.networkInterfaces', 'count'))
        'microsoft.network/loadbalancers'             = @(@('Frontends', 'properties.frontendIPConfigurations', 'count'), @('Backend pools', 'properties.backendAddressPools', 'count'), @('Rules', 'properties.loadBalancingRules', 'count'), @('Probes', 'properties.probes', 'count'))
        'microsoft.network/applicationgateways'       = @(@('SKU', 'properties.sku.name'), @('Capacity', 'properties.sku.capacity'), @('Minimum instances', 'properties.autoscaleConfiguration.minCapacity'), @('State', 'properties.operationalState'), @('WAF', 'properties.webApplicationFirewallConfiguration.enabled'))
        'microsoft.network/privateendpoints'          = @(@('Target', 'properties.privateLinkServiceConnections.0.properties.privateLinkServiceId', 'leaf'), @('Sub-resource', 'properties.privateLinkServiceConnections.0.properties.groupIds', 'join'), @('Connection', 'properties.privateLinkServiceConnections.0.properties.privateLinkServiceConnectionState.status'), @('Subnet', 'properties.subnet.id', 'leaf'))
        'microsoft.web/sites'                         = @(@('State', 'properties.state'), @('Host', 'properties.defaultHostName'), @('Plan', 'properties.serverFarmId', 'leaf'), @('Runtime', 'properties.siteConfig.linuxFxVersion'), @('HTTPS only', 'properties.httpsOnly'), @('Public access', 'properties.publicNetworkAccess'))
        'microsoft.web/serverfarms'                   = @(@('Apps', 'properties.numberOfSites'), @('Instances', 'sku.capacity'), @('Linux', 'properties.reserved'), @('Zone redundant', 'properties.zoneRedundant'))
        'microsoft.sql/servers'                       = @(@('Version', 'properties.version'), @('Public access', 'properties.publicNetworkAccess'), @('Minimum TLS', 'properties.minimalTlsVersion'), @('Entra-only auth', 'properties.administrators.azureADOnlyAuthentication'))
        'microsoft.sql/servers/databases'             = @(@('Status', 'properties.status'), @('Max size (GB)', 'properties.maxSizeBytes', 'gb'), @('Zone redundant', 'properties.zoneRedundant'), @('Backup redundancy', 'properties.currentBackupStorageRedundancy'), @('Elastic pool', 'properties.elasticPoolId', 'leaf'))
        'microsoft.keyvault/vaults'                   = @(@('Soft delete', 'properties.enableSoftDelete'), @('Purge protection', 'properties.enablePurgeProtection'), @('RBAC', 'properties.enableRbacAuthorization'), @('Public access', 'properties.publicNetworkAccess'), @('Retention (days)', 'properties.softDeleteRetentionInDays'))
        'microsoft.containerservice/managedclusters'  = @(@('Kubernetes', 'properties.kubernetesVersion'), @('Node pools', 'properties.agentPoolProfiles', 'count'), @('Nodes', 'properties.agentPoolProfiles', 'sum.count'), @('Network plugin', 'properties.networkProfile.networkPlugin'), @('Private', 'properties.apiServerAccessProfile.enablePrivateCluster'))
        'microsoft.documentdb/databaseaccounts'       = @(@('Consistency', 'properties.consistencyPolicy.defaultConsistencyLevel'), @('Regions', 'properties.locations', 'count'), @('Public access', 'properties.publicNetworkAccess'), @('Free tier', 'properties.enableFreeTier'))
        'microsoft.operationalinsights/workspaces'    = @(@('SKU', 'properties.sku.name'), @('Retention (days)', 'properties.retentionInDays'), @('Daily cap (GB)', 'properties.workspaceCapping.dailyQuotaGb'))
        'microsoft.recoveryservices/vaults'           = @(@('Redundancy', 'properties.redundancySettings.standardTierStorageRedundancy'), @('Soft delete', 'properties.securitySettings.softDeleteSettings.softDeleteState'), @('Immutability', 'properties.securitySettings.immutabilitySettings.state'))
        'microsoft.cache/redis'                       = @(@('SKU', 'properties.sku.name'), @('Capacity', 'properties.sku.capacity'), @('Version', 'properties.redisVersion'), @('Non-TLS port', 'properties.enableNonSslPort'))
        'microsoft.containerregistry/registries'      = @(@('Admin user', 'properties.adminUserEnabled'), @('Public access', 'properties.publicNetworkAccess'), @('Zone redundancy', 'properties.zoneRedundancy'))
        'microsoft.hybridcompute/machines'            = @(@('OS', 'properties.osName'), @('Version', 'properties.osVersion'), @('Status', 'properties.status'), @('Agent', 'properties.agentVersion'))
    }

    # A dotted path into parsed JSON; a number indexes a list. Exact keys first,
    # then case-insensitively (Azure's casing isn't consistent).
    $resolve = {
        param($Object, [string] $Path)
        foreach ($part in $Path.Split('.')) {
            if ($null -eq $Object) { return $null }
            if ($Object -is [System.Collections.IList] -and $part -match '^\d+$') { $Object = if ([int]$part -lt $Object.Count) { $Object[[int]$part] } else { $null }; continue }
            if ($Object -isnot [System.Collections.IDictionary]) { return $null }
            if ($Object.Contains($part)) { $Object = $Object[$part]; continue }
            $found = $null
            foreach ($key in $Object.Keys) { if ($key -eq $part) { $found = $Object[$key]; break } }
            $Object = $found
        }
        , $Object
    }
    $leaf = { param([string] $Id) if ($Id) { ($Id.TrimEnd('/') -split '/')[-1] } else { '' } }
    $show = {
        param($Value, [string] $How)
        switch -Wildcard ($How) {
            'leaf' { return (& $leaf ([string]$Value)) }
            'owner' { return (& $leaf ([string]$Value -replace '/(ipConfigurations|frontendIPConfigurations)/[^/]+$', '')) }
            'count' { return $(if ($null -eq $Value) { '' } else { @($Value).Count }) }
            'join' { return (@($Value | Where-Object { $null -ne $_ -and '' -ne $_ }) -join ', ') }
            'gb' { return $(if ($Value) { [Math]::Round([double]$Value / 1GB, 1) } else { '' }) }
            'sum.*' { $field = $How.Substring(4); $total = 0; foreach ($item in @($Value)) { $n = & $resolve $item $field; if ($n) { $total += [double]$n } }; return $total }
        }
        if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string] -and $Value -isnot [System.Collections.IDictionary]) { return (@($Value) -join ', ') }
        $Value
    }
    $date = {
        param($Value)
        if ($Value -is [datetime]) { return $Value }
        $d = [datetime]::MinValue
        if ($Value -and [datetime]::TryParse([string]$Value, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$d)) { $d } else { $null }
    }
    $tagsOf = {
        param($Bag)
        $tags = [ordered]@{}
        if ($Bag -is [System.Collections.IDictionary]) { foreach ($key in @($Bag.Keys | Sort-Object)) { $tags[[string]$key] = [string]$Bag[$key] } }
        $tags
    }

    $tagUse = @{}       # tag key (lower case) -> resources with it
    $tagName = @{}      # tag key (lower case) -> the spelling seen first
    $resources = foreach ($entry in $Row) {
        if ($entry -isnot [System.Collections.IDictionary]) { continue }
        $id = [string]$entry['id']
        $type = ([string]$entry['type']).ToLowerInvariant()
        $properties = $entry['properties']
        $chain = @($entry['managementGroupChain'] | Where-Object { $_ -is [System.Collections.IDictionary] })
        $tags = & $tagsOf $entry['tags']
        foreach ($key in $tags.Keys) {
            $lower = $key.ToLowerInvariant()
            $tagUse[$lower] = 1 + [int]$tagUse[$lower]
            if (-not $tagName.Contains($lower)) { $tagName[$lower] = $key }
        }
        $groupTags = & $tagsOf $entry['groupTags']
        # The chain runs from the subscription's own group up to the root; the path reads root first.
        $names = [string[]]@($chain | ForEach-Object { [string]$_['displayName'] })
        [array]::Reverse($names)
        $groupPath = $names -join ' > '
        $sku = $entry['sku']
        # Most types have no entry in $details: their Details stay empty.
        $line = if ($details.Contains($type)) {
            @(foreach ($d in $details[$type]) {
                    $value = & $show (& $resolve $entry $d[1]) $(if ($d.Count -gt 2) { $d[2] } else { '' })
                    if ($null -ne $value -and '' -ne "$value") { "$($d[0]): $value" }
                }) -join '; '
        }
        else { '' }
        $created = @(foreach ($field in 'creationTime', 'timeCreated', 'createdTime', 'createdAt', 'creationDate', 'createdDate') { & $date (& $resolve $properties $field) }) | Where-Object { $_ } | Select-Object -First 1
        # A child resource (servers/databases) is named after its parent too.
        $segments = ($id -split '/providers/', 2)[-1] -split '/'
        $item = [pscustomobject][ordered]@{
            Name                = [string]$entry['name']
            ResourceType        = $type
            Kind                = [string]$entry['kind']
            ResourceGroup       = [string]$entry['resourceGroup']
            Subscription        = $(if ($entry['subscriptionName']) { [string]$entry['subscriptionName'] } else { [string]$entry['subscriptionId'] })
            ManagementGroup     = $(if ($chain.Count) { [string]$chain[0]['displayName'] } else { '' })
            ManagementGroupPath = $groupPath
            Location            = [string]$entry['location']
            Zones               = (@($entry['zones'] | Where-Object { $_ }) -join ', ')
            Sku                 = $(if ($sku -is [System.Collections.IDictionary]) { (@($sku['name'], $sku['tier'] | Where-Object { $_ } | Select-Object -Unique) -join ' / ') } else { '' })
            Capacity            = $(if ($sku -is [System.Collections.IDictionary] -and $null -ne $sku['capacity']) { $sku['capacity'] } else { $null })
            Identity            = $(if ($entry['identity'] -is [System.Collections.IDictionary] -and $entry['identity']['type']) { [string]$entry['identity']['type'] } else { 'None' })
            ProvisioningState   = [string](& $resolve $properties 'provisioningState')
            PublicNetworkAccess = [string](& $resolve $properties 'publicNetworkAccess')
            Parent              = $(if ($segments.Count -gt 4) { $segments[-3] } else { '' })
            ManagedBy           = & $leaf ([string]$entry['managedBy'])
            Created             = $created
            Details             = $line
            Tags                = $tags
            TagText             = (@($tags.Keys | ForEach-Object { "$_=$($tags[$_])" }) -join '; ')
            TagCount            = $tags.Count
            ResourceGroupTags   = (@($groupTags.Keys | ForEach-Object { "$_=$($groupTags[$_])" }) -join '; ')
            SubscriptionId      = [string]$entry['subscriptionId']
            SubscriptionState   = [string]$entry['subscriptionState']
            ManagementGroupId   = $(if ($chain.Count) { [string]$chain[0]['name'] } else { '' })
            ResourceGroupId     = "/subscriptions/$($entry['subscriptionId'])/resourceGroups/$($entry['resourceGroup'])"
            ResourceId          = $id
        }
        if ($Flatten) { $item | Add-Member -NotePropertyName Properties -NotePropertyValue (ConvertTo-AACFlatObject -InputObject $properties) }
        $item.PSObject.TypeNames.Insert(0, 'AAC.Resource')
        $item
    }
    $resources = @($resources | Sort-Object -Property Subscription, ResourceGroup, ResourceType, Name)
    $tagKeys = @($tagUse.Keys | Sort-Object -Property @{ Expression = { $tagUse[$_] }; Descending = $true }, @{ Expression = { $_ } } | ForEach-Object { $tagName[$_] })

    $distinct = { param([string[]] $Values) $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase); foreach ($v in $Values) { if ($v) { $null = $set.Add($v) } }; $set.Count }
    @{
        Resources = $resources
        TagKeys   = $tagKeys
        Stats     = @{
            Resources      = $resources.Count
            Types          = & $distinct $resources.ResourceType
            Subscriptions  = & $distinct $resources.SubscriptionId
            ResourceGroups = & $distinct $resources.ResourceGroupId
            Locations      = & $distinct $resources.Location
            Untagged       = @($resources | Where-Object { -not $_.TagCount }).Count
        }
    }
}