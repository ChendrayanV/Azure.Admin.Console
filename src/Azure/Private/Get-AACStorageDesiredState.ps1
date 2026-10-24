function Get-AACStorageDesiredState {
    <#
    .SYNOPSIS
        Turns a storage account configuration (AVM parameter names) into the
        resources to manage, each with its REST path, the body to create it
        with, and the properties to compare - the desired state
        Deploy-AACStorageAccount plans against.
    .DESCRIPTION
        Defaults are AVM's (avm/res/storage/storage-account): StorageV2,
        Standard_GRS, Hot, TLS 1.2, HTTPS only, no public blob access, shared
        key access allowed, no cross-tenant replication, infrastructure
        encryption, network rules denying by default with the AzureServices
        bypass, blob soft delete (6 days) and container soft delete (7 days)
        - and, as with a Bicep deployment, those defaults are enforced on
        every run, not only at creation.

        Returns a list of nodes, in apply order. A node:
          Kind         account, blobService, container, fileService, share,
                       queueService, queue, tableService, table,
                       managementPolicy, privateEndpoint, dnsZoneGroup,
                       diagnosticSetting, roleAssignment, lock, blob
          Label        how the plan names it
          Id           its resource ID (a blob: its URL)
          ApiVersion   for its REST calls
          Type         its resource type (policy check, PSRule)
          Name         its full resource name ('st/default/logs')
          Desired      the body to create it with
          Managed      the properties compared on every run: @{ Path; Mode =
                       'Value' | 'Set' | 'Map' | 'Object'; Absent (what Azure
                       means when the property is missing); Immutable;
                       CaseSensitive }
          UpdateMethod Patch (only what changed) or Put (the current
                       settings with the changes merged in)
          Parent       the resource it lives under (policy scope)
          Order        apply order
        Role assignments carry Role (the name or ID to resolve) and
        Principal; blobs carry Container, BlobName, Source and ContentType.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Configuration,

        [Parameter(Mandatory)]
        [string] $SubscriptionId,

        [Parameter(Mandatory)]
        [string] $ResourceGroupName,

        [Parameter(Mandatory)]
        [string] $Location
    )

    $c = $Configuration
    $has = { param($Map, [string] $Key) $Map -is [System.Collections.IDictionary] -and $Map.Contains($Key) -and $null -ne $Map[$Key] }
    $pick = { param($Map, [string] $Key, $Default) if (& $has $Map $Key) { $Map[$Key] } else { $Default } }
    $nodes = [System.Collections.Generic.List[object]]::new()
    $spec = {
        param([string] $Path, [string] $Mode = 'Value', $Absent = $null, [switch] $Immutable, [switch] $CaseSensitive, [scriptblock] $ImmutableWhen)
        @{ Path = $Path; Mode = $Mode; Absent = $Absent; Immutable = [bool]$Immutable; CaseSensitive = [bool]$CaseSensitive; ImmutableWhen = $ImmutableWhen }
    }
    $node = {
        param([hashtable] $Values)
        $base = @{ Managed = @(); UpdateMethod = 'Put'; Parent = ''; Order = 0; Desired = @{} }
        foreach ($key in $Values.Keys) { $base[$key] = $Values[$key] }
        $nodes.Add($base)
    }

    $name = [string]$c['name']
    if ($name -cnotmatch '^[a-z0-9]{3,24}$') { throw "'$name' isn't a valid storage account name: 3-24 characters, lower-case letters and digits only." }
    $group = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName"
    $account = "$group/providers/Microsoft.Storage/storageAccounts/$name"
    $storageApi = '2023-05-01'
    $kind = [string](& $pick $c 'kind' 'StorageV2')
    $sku = [string](& $pick $c 'skuName' 'Standard_GRS')
    $region = ([string](& $pick $c 'location' $Location)).ToLowerInvariant() -replace '\s', ''
    $privateEndpoints = @(& $pick $c 'privateEndpoints' @())

    # --- The account ------------------------------------------------------------------------------------------
    $properties = [ordered]@{}
    $managed = [System.Collections.Generic.List[object]]::new()
    $managed.Add((& $spec 'location' -Immutable))
    $managed.Add((& $spec 'kind' -Immutable))
    # Redundancy can change in place only within its kind: LRS, GRS and RAGRS;
    # or ZRS, GZRS and RAGZRS. Zonal and back needs a conversion; Standard and
    # Premium can't be swapped at all.
    $managed.Add((& $spec 'sku.name' -ImmutableWhen {
                param($Current, $Desired)
                $tier = { param($Sku) ([string]$Sku -split '_')[0] }
                $zonal = { param($Sku) [string]$Sku -match 'ZRS$' }
                (& $tier $Current) -ne (& $tier $Desired) -or (& $zonal $Current) -ne (& $zonal $Desired)
            }))
    $setProperty = {
        param([string] $Key, $Value, $Absent, [switch] $Immutable)
        $properties[$Key] = $Value
        $managed.Add((& $spec "properties.$Key" 'Value' $Absent -Immutable:$Immutable))
    }
    if ($kind -in 'StorageV2', 'BlobStorage') { & $setProperty 'accessTier' ([string](& $pick $c 'accessTier' 'Hot')) $null }
    & $setProperty 'allowBlobPublicAccess' ([bool](& $pick $c 'allowBlobPublicAccess' $false)) $false
    & $setProperty 'allowSharedKeyAccess' ([bool](& $pick $c 'allowSharedKeyAccess' $true)) $true
    & $setProperty 'allowCrossTenantReplication' ([bool](& $pick $c 'allowCrossTenantReplication' $false)) $true
    & $setProperty 'defaultToOAuthAuthentication' ([bool](& $pick $c 'defaultToOAuthAuthentication' $false)) $false
    & $setProperty 'minimumTlsVersion' ([string](& $pick $c 'minimumTlsVersion' 'TLS1_2')) 'TLS1_0'
    & $setProperty 'supportsHttpsTrafficOnly' ([bool](& $pick $c 'supportsHttpsTrafficOnly' $true)) $true
    & $setProperty 'isSftpEnabled' ([bool](& $pick $c 'enableSftp' $false)) $false
    & $setProperty 'isLocalUserEnabled' ([bool](& $pick $c 'isLocalUserEnabled' $false)) $false
    if ($sku -in 'Standard_LRS', 'Standard_ZRS') { & $setProperty 'largeFileSharesState' ([string](& $pick $c 'largeFileSharesState' 'Disabled')) 'Disabled' }
    if (& $has $c 'enableHierarchicalNamespace') { & $setProperty 'isHnsEnabled' ([bool]$c['enableHierarchicalNamespace']) $false -Immutable }
    if (& $has $c 'enableNfsV3') { & $setProperty 'isNfsV3Enabled' ([bool]$c['enableNfsV3']) $false -Immutable }
    if (& $has $c 'allowedCopyScope') { & $setProperty 'allowedCopyScope' ([string]$c['allowedCopyScope']) $null }
    if (& $has $c 'dnsEndpointType') { & $setProperty 'dnsEndpointType' ([string]$c['dnsEndpointType']) 'Standard' -Immutable }
    # Public network access: as given; else - as AVM does - Disabled when
    # only private endpoints reach the account.
    $networkAcls = & $pick $c 'networkAcls' $null
    $publicAccess = if (& $has $c 'publicNetworkAccess') { [string]$c['publicNetworkAccess'] } elseif ($privateEndpoints.Count -and -not $networkAcls) { 'Disabled' } else { $null }
    if ($publicAccess) { & $setProperty 'publicNetworkAccess' $publicAccess 'Enabled' }
    # Network rules: as given, else AVM's default - deny, with the AzureServices bypass.
    $acl = [ordered]@{
        bypass              = [string](& $pick $networkAcls 'bypass' 'AzureServices')
        defaultAction       = [string](& $pick $networkAcls 'defaultAction' 'Deny')
        ipRules             = @(@(& $pick $networkAcls 'ipRules' @()) | ForEach-Object { if ($_ -is [System.Collections.IDictionary]) { [ordered]@{ value = [string]$_['value']; action = 'Allow' } } else { [ordered]@{ value = [string]$_; action = 'Allow' } } })
        virtualNetworkRules = @(@(& $pick $networkAcls 'virtualNetworkRules' @()) | ForEach-Object { if ($_ -is [System.Collections.IDictionary]) { [ordered]@{ id = [string]$_['id']; action = 'Allow' } } else { [ordered]@{ id = [string]$_; action = 'Allow' } } })
        resourceAccessRules = @(@(& $pick $networkAcls 'resourceAccessRules' @()) | ForEach-Object { [ordered]@{ tenantId = [string]$_['tenantId']; resourceId = [string]$_['resourceId'] } })
    }
    $properties['networkAcls'] = $acl
    $managed.Add((& $spec 'properties.networkAcls.defaultAction' 'Value' 'Allow'))
    $managed.Add((& $spec 'properties.networkAcls.bypass' 'Set' 'AzureServices'))
    $managed.Add((& $spec 'properties.networkAcls.ipRules' 'Set' @()))
    $managed.Add((& $spec 'properties.networkAcls.virtualNetworkRules' 'Set' @()))
    $managed.Add((& $spec 'properties.networkAcls.resourceAccessRules' 'Set' @()))
    # Infrastructure encryption is fixed when the account is created.
    $properties['encryption'] = [ordered]@{
        requireInfrastructureEncryption = [bool](& $pick $c 'requireInfrastructureEncryption' $true)
        keySource                       = 'Microsoft.Storage'
        services                        = [ordered]@{ blob = [ordered]@{ enabled = $true; keyType = 'Account' }; file = [ordered]@{ enabled = $true; keyType = 'Account' } }
    }
    $managed.Add((& $spec 'properties.encryption.requireInfrastructureEncryption' 'Value' $false -Immutable))
    $body = [ordered]@{ location = $region; kind = $kind; sku = [ordered]@{ name = $sku }; properties = $properties }
    if (& $has $c 'tags') { $body['tags'] = $c['tags']; $managed.Add((& $spec 'tags' 'Map' @{} -CaseSensitive)) }
    & $node @{ Kind = 'account'; Label = "Storage account $name"; Id = $account; ApiVersion = $storageApi; Type = 'Microsoft.Storage/storageAccounts'; Name = $name; Desired = $body; Managed = $managed.ToArray(); UpdateMethod = 'Patch'; Order = 0; Parent = $group }

    # --- Services and what they hold -------------------------------------------------------------------------------
    $supportsBlob = $kind -ne 'FileStorage'
    $supportsOthers = $kind -notin 'FileStorage', 'BlockBlobStorage', 'BlobStorage'
    $supportsFiles = $kind -notin 'BlockBlobStorage', 'BlobStorage'
    $diagnostic = {
        param([System.Collections.IDictionary] $Setting, [string] $Scope, [string] $ScopeLabel, [switch] $MetricsOnly)
        $settingName = [string](& $pick $Setting 'name' "$name-diagnosticSettings")
        # @( ) around the if, not inside it: assigning an if's output unrolls a
        # one-item list to its item - and Azure wants logs as a list.
        $logs = @(if (-not $MetricsOnly) { @(& $pick $Setting 'logCategoriesAndGroups' @(@{ categoryGroup = 'allLogs' })) | ForEach-Object { if ($_['category']) { [ordered]@{ category = [string]$_['category']; enabled = [bool](& $pick $_ 'enabled' $true) } } else { [ordered]@{ categoryGroup = [string]$_['categoryGroup']; enabled = [bool](& $pick $_ 'enabled' $true) } } } })
        $metrics = @(@(& $pick $Setting 'metricCategories' @(@{ category = 'AllMetrics' })) | ForEach-Object { [ordered]@{ category = [string]$_['category']; enabled = [bool](& $pick $_ 'enabled' $true) } })
        $settingProperties = [ordered]@{ logs = $logs; metrics = $metrics }
        foreach ($pair in @(@('workspaceResourceId', 'workspaceId'), @('storageAccountResourceId', 'storageAccountId'), @('eventHubAuthorizationRuleResourceId', 'eventHubAuthorizationRuleId'), @('eventHubName', 'eventHubName'), @('marketplacePartnerResourceId', 'marketplacePartnerId'), @('logAnalyticsDestinationType', 'logAnalyticsDestinationType'))) {
            if (& $has $Setting $pair[0]) { $settingProperties[$pair[1]] = [string]$Setting[$pair[0]] }
        }
        $specs = @((& $spec 'properties.logs' 'Set' @()), (& $spec 'properties.metrics' 'Set' @()))
        foreach ($key in 'workspaceId', 'storageAccountId', 'eventHubAuthorizationRuleId', 'eventHubName', 'marketplacePartnerId') { $specs += & $spec "properties.$key" 'Value' $null }
        if ($settingProperties.Contains('logAnalyticsDestinationType')) { $specs += & $spec 'properties.logAnalyticsDestinationType' 'Value' $null }
        & $node @{ Kind = 'diagnosticSetting'; Label = "Diagnostic setting $settingName on $ScopeLabel"; Id = "$Scope/providers/Microsoft.Insights/diagnosticSettings/$settingName"; ApiVersion = '2021-05-01-preview'; Type = 'Microsoft.Insights/diagnosticSettings'; Name = $settingName; Desired = [ordered]@{ properties = $settingProperties }; Managed = $specs; Order = 6; Parent = $Scope }
    }
    $metadataSpec = { param($Item) if (& $has $Item 'metadata') { & $spec 'properties.metadata' 'Map' @{} -CaseSensitive } }

    $blobServices = & $pick $c 'blobServices' $(if ($supportsBlob) { [ordered]@{ containerDeleteRetentionPolicyEnabled = $true; containerDeleteRetentionPolicyDays = 7; deleteRetentionPolicyEnabled = $true; deleteRetentionPolicyDays = 6 } } else { $null })
    if ($blobServices -is [System.Collections.IDictionary] -and $blobServices.Count) {
        if (-not $supportsBlob) { throw "A $kind account has no blob service: remove blobServices." }
        $blobService = "$account/blobServices/default"
        $serviceProperties = [ordered]@{}
        $specs = [System.Collections.Generic.List[object]]::new()
        $retention = {
            param([string] $Property, [string] $EnabledKey, [string] $DaysKey, [string] $PermanentKey)
            if (& $has $blobServices $EnabledKey) {
                $policy = [ordered]@{ enabled = [bool]$blobServices[$EnabledKey] }
                $specs.Add((& $spec "properties.$Property.enabled" 'Value' $false))
                if ($policy.enabled -and (& $has $blobServices $DaysKey)) { $policy['days'] = [int]$blobServices[$DaysKey]; $specs.Add((& $spec "properties.$Property.days" 'Value' $null)) }
                if ($PermanentKey -and (& $has $blobServices $PermanentKey)) { $policy['allowPermanentDelete'] = [bool]$blobServices[$PermanentKey]; $specs.Add((& $spec "properties.$Property.allowPermanentDelete" 'Value' $false)) }
                $serviceProperties[$Property] = $policy
            }
        }
        & $retention 'deleteRetentionPolicy' 'deleteRetentionPolicyEnabled' 'deleteRetentionPolicyDays' 'deleteRetentionPolicyAllowPermanentDelete'
        & $retention 'containerDeleteRetentionPolicy' 'containerDeleteRetentionPolicyEnabled' 'containerDeleteRetentionPolicyDays' ''
        & $retention 'restorePolicy' 'restorePolicyEnabled' 'restorePolicyDays' ''
        if (& $has $blobServices 'isVersioningEnabled') { $serviceProperties['isVersioningEnabled'] = [bool]$blobServices['isVersioningEnabled']; $specs.Add((& $spec 'properties.isVersioningEnabled' 'Value' $false)) }
        if (& $has $blobServices 'automaticSnapshotPolicyEnabled') { $serviceProperties['automaticSnapshotPolicyEnabled'] = [bool]$blobServices['automaticSnapshotPolicyEnabled']; $specs.Add((& $spec 'properties.automaticSnapshotPolicyEnabled' 'Value' $false)) }
        if (& $has $blobServices 'changeFeedEnabled') {
            $feed = [ordered]@{ enabled = [bool]$blobServices['changeFeedEnabled'] }
            $specs.Add((& $spec 'properties.changeFeed.enabled' 'Value' $false))
            if ($feed.enabled -and (& $has $blobServices 'changeFeedRetentionInDays')) { $feed['retentionInDays'] = [int]$blobServices['changeFeedRetentionInDays']; $specs.Add((& $spec 'properties.changeFeed.retentionInDays' 'Value' $null)) }
            $serviceProperties['changeFeed'] = $feed
        }
        if (& $has $blobServices 'lastAccessTimeTrackingPolicyEnabled') { $serviceProperties['lastAccessTimeTrackingPolicy'] = [ordered]@{ enable = [bool]$blobServices['lastAccessTimeTrackingPolicyEnabled'] }; $specs.Add((& $spec 'properties.lastAccessTimeTrackingPolicy.enable' 'Value' $false)) }
        & $node @{ Kind = 'blobService'; Label = "Blob service of $name"; Id = $blobService; ApiVersion = $storageApi; Type = 'Microsoft.Storage/storageAccounts/blobServices'; Name = "$name/default"; Desired = [ordered]@{ properties = $serviceProperties }; Managed = $specs.ToArray(); Order = 1; Parent = $account }
        foreach ($container in @(& $pick $blobServices 'containers' @())) {
            $containerName = if ($container -is [System.Collections.IDictionary]) { [string]$container['name'] } else { [string]$container }
            if ($containerName -cnotmatch '^(?!.*--)[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$') { throw "'$containerName' isn't a valid container name: 3-63 lower-case letters, digits and single hyphens, starting and ending with a letter or digit." }
            $item = if ($container -is [System.Collections.IDictionary]) { $container } else { @{} }
            $containerProperties = [ordered]@{ publicAccess = [string](& $pick $item 'publicAccess' 'None') }
            $specs = @(& $spec 'properties.publicAccess' 'Value' 'None')
            if (& $has $item 'metadata') { $containerProperties['metadata'] = $item['metadata']; $specs += & $metadataSpec $item }
            if (& $has $item 'defaultEncryptionScope') { $containerProperties['defaultEncryptionScope'] = [string]$item['defaultEncryptionScope']; $specs += & $spec 'properties.defaultEncryptionScope' 'Value' '$account-encryption-key' -Immutable }
            if (& $has $item 'denyEncryptionScopeOverride') { $containerProperties['denyEncryptionScopeOverride'] = [bool]$item['denyEncryptionScopeOverride']; $specs += & $spec 'properties.denyEncryptionScopeOverride' 'Value' $false -Immutable }
            $containerId = "$blobService/containers/$containerName"
            & $node @{ Kind = 'container'; Label = "Container $containerName"; Id = $containerId; ApiVersion = $storageApi; Type = 'Microsoft.Storage/storageAccounts/blobServices/containers'; Name = "$name/default/$containerName"; Desired = [ordered]@{ properties = $containerProperties }; Managed = $specs; UpdateMethod = 'Patch'; Order = 2; Parent = $blobService }
            foreach ($assignment in @(& $pick $item 'roleAssignments' @())) {
                & $node @{ Kind = 'roleAssignment'; Label = "Role $($assignment['roleDefinitionIdOrName']) on container $containerName"; Scope = $containerId; Role = [string]$assignment['roleDefinitionIdOrName']; Assignment = $assignment; ApiVersion = '2022-04-01'; Type = 'Microsoft.Authorization/roleAssignments'; Order = 7; Parent = $containerId }
            }
        }
        foreach ($setting in @(& $pick $blobServices 'diagnosticSettings' @())) { & $diagnostic $setting $blobService "the blob service" }
    }

    $fileServices = & $pick $c 'fileServices' $null
    if ($fileServices -is [System.Collections.IDictionary] -and $fileServices.Count) {
        if (-not $supportsFiles) { throw "A $kind account has no file service: remove fileServices." }
        $fileService = "$account/fileServices/default"
        $serviceProperties = [ordered]@{}
        $specs = @()
        if (& $has $fileServices 'shareDeleteRetentionPolicy') {
            $policy = $fileServices['shareDeleteRetentionPolicy']
            $serviceProperties['shareDeleteRetentionPolicy'] = [ordered]@{ enabled = [bool](& $pick $policy 'enabled' $true); days = [int](& $pick $policy 'days' 7) }
            $specs += & $spec 'properties.shareDeleteRetentionPolicy.enabled' 'Value' $false
            $specs += & $spec 'properties.shareDeleteRetentionPolicy.days' 'Value' $null
        }
        & $node @{ Kind = 'fileService'; Label = "File service of $name"; Id = $fileService; ApiVersion = $storageApi; Type = 'Microsoft.Storage/storageAccounts/fileServices'; Name = "$name/default"; Desired = [ordered]@{ properties = $serviceProperties }; Managed = $specs; Order = 1; Parent = $account }
        foreach ($share in @(& $pick $fileServices 'shares' @())) {
            $item = if ($share -is [System.Collections.IDictionary]) { $share } else { @{ name = [string]$share } }
            $shareName = [string]$item['name']
            $shareProperties = [ordered]@{ shareQuota = [int](& $pick $item 'shareQuota' 5120) }
            $specs = @(& $spec 'properties.shareQuota' 'Value' $null)
            if (& $has $item 'accessTier') { $shareProperties['accessTier'] = [string]$item['accessTier']; $specs += & $spec 'properties.accessTier' 'Value' $null }
            if (& $has $item 'enabledProtocols') { $shareProperties['enabledProtocols'] = [string]$item['enabledProtocols']; $specs += & $spec 'properties.enabledProtocols' 'Value' 'SMB' -Immutable }
            if (& $has $item 'rootSquash') { $shareProperties['rootSquash'] = [string]$item['rootSquash']; $specs += & $spec 'properties.rootSquash' 'Value' $null }
            if (& $has $item 'metadata') { $shareProperties['metadata'] = $item['metadata']; $specs += & $metadataSpec $item }
            & $node @{ Kind = 'share'; Label = "File share $shareName"; Id = "$fileService/shares/$shareName"; ApiVersion = $storageApi; Type = 'Microsoft.Storage/storageAccounts/fileServices/shares'; Name = "$name/default/$shareName"; Desired = [ordered]@{ properties = $shareProperties }; Managed = $specs; UpdateMethod = 'Patch'; Order = 2; Parent = $fileService }
        }
        foreach ($setting in @(& $pick $fileServices 'diagnosticSettings' @())) { & $diagnostic $setting $fileService "the file service" }
    }

    foreach ($pair in @(@('queueServices', 'queues', 'queue', 'queueService', 'Queue', 'queueServices'), @('tableServices', 'tables', 'table', 'tableService', 'Table', 'tableServices'))) {
        $settings = & $pick $c $pair[0] $null
        if ($settings -isnot [System.Collections.IDictionary] -or -not $settings.Count) { continue }
        if (-not $supportsOthers) { throw "A $kind account has no $($pair[2]) service: remove $($pair[0])." }
        $service = "$account/$($pair[5])/default"
        & $node @{ Kind = $pair[3]; Label = "$($pair[4]) service of $name"; Id = $service; ApiVersion = $storageApi; Type = "Microsoft.Storage/storageAccounts/$($pair[5])"; Name = "$name/default"; Desired = [ordered]@{ properties = [ordered]@{} }; Managed = @(); Order = 1; Parent = $account }
        foreach ($entry in @(& $pick $settings $pair[1] @())) {
            $item = if ($entry -is [System.Collections.IDictionary]) { $entry } else { @{ name = [string]$entry } }
            $entryName = [string]$item['name']
            $entryProperties = [ordered]@{}
            $specs = @()
            if ($pair[2] -eq 'queue' -and (& $has $item 'metadata')) { $entryProperties['metadata'] = $item['metadata']; $specs += & $metadataSpec $item }
            $childType = if ($pair[2] -eq 'queue') { 'queues' } else { 'tables' }
            & $node @{ Kind = $pair[2]; Label = "$($pair[4]) $entryName"; Id = "$service/$childType/$entryName"; ApiVersion = $storageApi; Type = "Microsoft.Storage/storageAccounts/$($pair[5])/$childType"; Name = "$name/default/$entryName"; Desired = [ordered]@{ properties = $entryProperties }; Managed = $specs; Order = 2; Parent = $service }
        }
        foreach ($setting in @(& $pick $settings 'diagnosticSettings' @())) { & $diagnostic $setting $service "the $($pair[2]) service" }
    }

    # --- Lifecycle, private endpoints, diagnostics, access, lock -------------------------------------------------------
    if (& $has $c 'managementPolicyRules') {
        & $node @{ Kind = 'managementPolicy'; Label = "Lifecycle management policy of $name"; Id = "$account/managementPolicies/default"; ApiVersion = $storageApi; Type = 'Microsoft.Storage/storageAccounts/managementPolicies'; Name = "$name/default"; Desired = [ordered]@{ properties = [ordered]@{ policy = [ordered]@{ rules = @($c['managementPolicyRules']) } } }; Managed = @(& $spec 'properties.policy.rules' 'Set' @()); Order = 3; Parent = $account }
    }
    $index = 0
    foreach ($endpoint in $privateEndpoints) {
        $index++
        $service = [string]$endpoint['service']
        if (-not $service -or -not $endpoint['subnetResourceId']) { throw "Private endpoint $index needs a service (blob, file, queue, table, dfs, web) and a subnetResourceId." }
        $endpointName = [string](& $pick $endpoint 'name' "pep-$name-$service-$index")
        $endpointGroup = if (& $has $endpoint 'resourceGroupResourceId') { [string]$endpoint['resourceGroupResourceId'] } else { $group }
        $endpointId = "$endpointGroup/providers/Microsoft.Network/privateEndpoints/$endpointName"
        $endpointBody = [ordered]@{
            location   = ([string](& $pick $endpoint 'location' $region)).ToLowerInvariant() -replace '\s', ''
            properties = [ordered]@{
                subnet                        = [ordered]@{ id = [string]$endpoint['subnetResourceId'] }
                privateLinkServiceConnections = @([ordered]@{ name = $endpointName; properties = [ordered]@{ privateLinkServiceId = $account; groupIds = @($service) } })
            }
        }
        $specs = @((& $spec 'location' -Immutable), (& $spec 'properties.subnet.id' 'Value' $null -Immutable))
        if (& $has $endpoint 'customNetworkInterfaceName') { $endpointBody.properties['customNetworkInterfaceName'] = [string]$endpoint['customNetworkInterfaceName']; $specs += & $spec 'properties.customNetworkInterfaceName' 'Value' $null -Immutable }
        if (& $has $endpoint 'tags') { $endpointBody['tags'] = $endpoint['tags']; $specs += & $spec 'tags' 'Map' @{} -CaseSensitive }
        & $node @{ Kind = 'privateEndpoint'; Label = "Private endpoint $endpointName ($service)"; Id = $endpointId; ApiVersion = '2023-11-01'; Type = 'Microsoft.Network/privateEndpoints'; Name = $endpointName; Desired = $endpointBody; Managed = $specs; Order = 4; Parent = $endpointGroup; Service = $service }
        $zones = @(& $pick (& $pick $endpoint 'privateDnsZoneGroup' @{}) 'privateDnsZoneGroupConfigs' @())
        if ($zones.Count) {
            $zoneGroupName = [string](& $pick $endpoint['privateDnsZoneGroup'] 'name' 'default')
            $configs = @(foreach ($zone in $zones) { $zoneId = [string]$zone['privateDnsZoneResourceId']; [ordered]@{ name = [string](& $pick $zone 'name' (($zoneId -split '/')[-1] -replace '\.', '-')); properties = [ordered]@{ privateDnsZoneId = $zoneId } } })
            & $node @{ Kind = 'dnsZoneGroup'; Label = "Private DNS zone group of $endpointName"; Id = "$endpointId/privateDnsZoneGroups/$zoneGroupName"; ApiVersion = '2023-11-01'; Type = 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups'; Name = "$endpointName/$zoneGroupName"; Desired = [ordered]@{ properties = [ordered]@{ privateDnsZoneConfigs = $configs } }; Managed = @(& $spec 'properties.privateDnsZoneConfigs' 'Set' @()); Order = 5; Parent = $endpointId }
        }
    }
    foreach ($setting in @(& $pick $c 'diagnosticSettings' @())) { & $diagnostic $setting $account "the account" -MetricsOnly }
    foreach ($assignment in @(& $pick $c 'roleAssignments' @())) {
        & $node @{ Kind = 'roleAssignment'; Label = "Role $($assignment['roleDefinitionIdOrName']) on $name"; Scope = $account; Role = [string]$assignment['roleDefinitionIdOrName']; Assignment = $assignment; ApiVersion = '2022-04-01'; Type = 'Microsoft.Authorization/roleAssignments'; Order = 7; Parent = $account }
    }
    $lock = & $pick $c 'lock' $null
    if ($lock -is [System.Collections.IDictionary] -and [string](& $pick $lock 'kind' 'None') -ne 'None') {
        $lockName = [string](& $pick $lock 'name' "lock-$name")
        $lockProperties = [ordered]@{ level = [string]$lock['kind'] }
        if (& $has $lock 'notes') { $lockProperties['notes'] = [string]$lock['notes'] }
        $specs = @(& $spec 'properties.level' 'Value' $null)
        if ($lockProperties.Contains('notes')) { $specs += & $spec 'properties.notes' 'Value' $null -CaseSensitive }
        & $node @{ Kind = 'lock'; Label = "$($lock['kind']) lock $lockName"; Id = "$account/providers/Microsoft.Authorization/locks/$lockName"; ApiVersion = '2020-05-01'; Type = 'Microsoft.Authorization/locks'; Name = $lockName; Desired = [ordered]@{ properties = $lockProperties }; Managed = $specs; Order = 8; Parent = $account }
    }

    # --- Blobs: data plane, after everything else ----------------------------------------------------------------------
    $containers = @(foreach ($n in $nodes) { if ($n.Kind -eq 'container') { ($n.Id -split '/')[-1] } })
    foreach ($blob in @(& $pick $c 'blobs' @())) {
        $containerName = [string]$blob['container']
        $source = [string]$blob['path']
        $blobName = [string](& $pick $blob 'name' ([System.IO.Path]::GetFileName($source)))
        if ($containers -notcontains $containerName) { throw "Blob $blobName goes to container '$containerName', which isn't in the configuration: add it to blobServices.containers." }
        & $node @{ Kind = 'blob'; Label = "Blob $containerName/$blobName"; Id = "https://$name.blob.core.windows.net/$containerName/$(($blobName -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/')"; Container = $containerName; BlobName = $blobName; Source = $source; ContentType = [string](& $pick $blob 'contentType' ''); Order = 9; Parent = "$account/blobServices/default/containers/$containerName" }
    }
    @($nodes | Sort-Object -Property Order -Stable)
}
