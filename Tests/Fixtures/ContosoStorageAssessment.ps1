<#
    Made-up Contoso storage accounts for StorageAccountAssessment.Tests.ps1,
    as Resource Graph, Azure Monitor metrics and the storage services'
    settings return them.

      stprod     (Contoso Prod, rg-data)  StorageV2, GZRS, hot; HTTPS, TLS 1.2,
                                          no anonymous access, shared keys off,
                                          private (1 endpoint); blob logs to
                                          law-prod; soft delete 14 / 7 days,
                                          versioning, change feed, shares 7
                                          days; 2 lifecycle rules.
                                          10,000 transactions: 9,700 OK, 150
                                          throttled, 20 server timeouts, 30
                                          authorization errors, 100 client
                                          (404); availability 99.97%; latency
                                          end to end 50 ms, server 15 ms;
                                          500 GB used: 400 GB blob (1,000,000
                                          blobs, 12 containers), 100 GB file
                                          (3 shares)
      stlegacy   (Contoso Dev, rg-dev)    general-purpose v1, LRS; HTTP and TLS
                                          1.0 allowed, anonymous access on,
                                          shared keys on (keys 200 days old, no
                                          key or SAS policy), open to every
                                          network, cross-tenant replication;
                                          no soft delete, no lifecycle rules,
                                          no logs; idle; 50 GB of blobs
      starchive  (Contoso Prod, rg-data)  StorageV2, ZRS, hot, firewall; 2 TB of
                                          blobs but only 500 transactions a
                                          day; blob soft delete 3 days; no
                                          lifecycle rules
    Defender for Storage: on in Prod, off in Dev.
#>
function Get-AACContosoStorageAssessment {
    $prod = '11111111-1111-1111-1111-111111111111'
    $dev = '22222222-2222-2222-2222-222222222222'
    $account = { param($Sub, $Group, $Name, $Kind, $Sku, $Tier, $Properties) @{ id = "/subscriptions/$Sub/resourcegroups/$Group/providers/microsoft.storage/storageaccounts/$Name"; name = $Name; location = 'uksouth'; resourceGroup = $Group; subscriptionId = $Sub; kind = $Kind; sku = $Sku; accessTier = $Tier; properties = $Properties; tags = $null } }
    $secure = { param([hashtable] $Extra) $p = @{ supportsHttpsTrafficOnly = $true; minimumTlsVersion = 'TLS1_2'; allowBlobPublicAccess = $false; allowSharedKeyAccess = $false; allowCrossTenantReplication = $false; encryption = @{ keySource = 'Microsoft.Storage' } }; foreach ($k in $Extra.Keys) { $p[$k] = $Extra[$k] }; $p }
    $stProd = & $account $prod 'rg-data' 'stprod' 'StorageV2' 'Standard_GZRS' 'Hot' (& $secure @{ publicNetworkAccess = 'Disabled'; privateEndpointConnections = @(@{ properties = @{ privateLinkServiceConnectionState = @{ status = 'Approved' } } }) })
    $stLegacy = & $account $dev 'rg-dev' 'stlegacy' 'Storage' 'Standard_LRS' '' @{ supportsHttpsTrafficOnly = $false; minimumTlsVersion = 'TLS1_0'; allowBlobPublicAccess = $true; allowCrossTenantReplication = $true; networkAcls = @{ defaultAction = 'Allow' }; keyCreationTime = @{ key1 = [datetime]::UtcNow.AddDays(-200).ToString('o'); key2 = [datetime]::UtcNow.AddDays(-30).ToString('o') } }
    $stArchive = & $account $prod 'rg-data' 'starchive' 'StorageV2' 'Standard_ZRS' 'Hot' (& $secure @{ networkAcls = @{ defaultAction = 'Deny' } })
    $workspace = "/subscriptions/$prod/resourcegroups/rg-monitor/providers/microsoft.operationalinsights/workspaces/law-prod"

    $point = { param($Total, $Average) @{ timeStamp = '2026-10-15T10:00:00Z'; total = $Total; average = $Average } }
    $metric = { param($Name, [object[]] $Series) @{ name = @{ value = $Name }; timeseries = $Series } }
    $plain = { param([object[]] $Data) @{ metadatavalues = @(); data = $Data } }
    $byType = { param($Type, $Total) @{ metadatavalues = @(@{ name = @{ value = 'responsetype' }; value = $Type }); data = @(& $point $Total $null) } }
    $latest = { param($Name, $Value) & $metric $Name @(& $plain @((& $point $null ($Value * 0.9)), (& $point $null $Value))) }
    $gb = [double]1GB
    @{
        Graph    = @{
            accounts   = @($stProd, $stLegacy, $stArchive)
            pricing    = @(@{ subscriptionId = $prod; tier = 'Standard' }, @{ subscriptionId = $dev; tier = 'Free' })
            alerts     = @()
            workspaces = @(@{ id = $workspace; name = 'law-prod' })
        }
        # "<resource>|<call>" -> the metrics API's body.
        Metrics  = @{
            "$($stProd.id)|Core"                                 = @{ value = @(
                    & $metric 'Transactions' @(& $plain @((& $point 6000 $null), (& $point 4000 $null)))
                    & $metric 'Availability' @(& $plain @((& $point $null 99.99), (& $point $null 99.95)))
                    & $metric 'SuccessE2ELatency' @(& $plain @((& $point $null 40), (& $point $null 60)))
                    & $metric 'SuccessServerLatency' @(& $plain @((& $point $null 10), (& $point $null 20)))
                    & $metric 'Ingress' @(& $plain @(& $point (2 * $gb) $null))
                    & $metric 'Egress' @(& $plain @(& $point (5 * $gb) $null))
                ) }
            "$($stProd.id)|Responses"                            = @{ value = @(& $metric 'Transactions' @((& $byType 'Success' 9700), (& $byType 'ClientThrottlingError' 150), (& $byType 'ServerTimeoutError' 20), (& $byType 'AuthorizationError' 30), (& $byType 'ClientOtherError' 100))) }
            "$($stProd.id)|Capacity"                             = @{ value = @(& $latest 'UsedCapacity' (500 * $gb)) }
            "$($stProd.id)/blobServices/default|Capacity"        = @{ value = @((& $latest 'BlobCapacity' (400 * $gb)), (& $latest 'BlobCount' 1000000), (& $latest 'ContainerCount' 12)) }
            "$($stProd.id)/fileServices/default|Capacity"        = @{ value = @((& $latest 'FileCapacity' (100 * $gb)), (& $latest 'FileShareCount' 3)) }
            "$($stProd.id)/queueServices/default|Capacity"       = @{ value = @(& $latest 'QueueCapacity' 1MB) }
            "$($stProd.id)/tableServices/default|Capacity"       = @{ value = @(& $latest 'TableCapacity' 2MB) }
            "$($stLegacy.id)|Core"                               = @{ value = @(& $metric 'Transactions' @(& $plain @(& $point 0 $null))) }
            "$($stLegacy.id)|Responses"                          = @{ value = @() }
            "$($stLegacy.id)|Capacity"                           = @{ value = @(& $latest 'UsedCapacity' (50 * $gb)) }
            "$($stLegacy.id)/blobServices/default|Capacity"      = @{ value = @(& $latest 'BlobCapacity' (50 * $gb)) }
            "$($stArchive.id)|Core"                              = @{ value = @((& $metric 'Transactions' @(& $plain @(& $point 500 $null))), (& $metric 'Availability' @(& $plain @(& $point $null 100))), (& $metric 'SuccessE2ELatency' @(& $plain @(& $point $null 30))), (& $metric 'SuccessServerLatency' @(& $plain @(& $point $null 12)))) }
            "$($stArchive.id)|Responses"                         = @{ value = @(& $metric 'Transactions' @(& $byType 'Success' 500)) }
            "$($stArchive.id)|Capacity"                          = @{ value = @(& $latest 'UsedCapacity' (2000 * $gb)) }
            "$($stArchive.id)/blobServices/default|Capacity"     = @{ value = @(& $latest 'BlobCapacity' (2000 * $gb)) }
        }
        # "<account>|<part>" -> the settings API's answer.
        Settings = @{
            "$($stProd.id)|Blob"         = @{ deleteRetentionPolicy = @{ enabled = $true; days = 14 }; containerDeleteRetentionPolicy = @{ enabled = $true; days = 7 }; isVersioningEnabled = $true; changeFeed = @{ enabled = $true }; restorePolicy = @{ enabled = $false } }
            "$($stProd.id)|File"         = @{ shareDeleteRetentionPolicy = @{ enabled = $true; days = 7 } }
            "$($stProd.id)|Lifecycle"    = @{ policy = @{ rules = @(@{ name = 'to-cool' }, @{ name = 'delete-old-versions' }) } }
            "$($stProd.id)|Logs"         = @(@{ name = 'to-law'; properties = @{ workspaceId = $workspace; logs = @(@{ categoryGroup = 'audit'; enabled = $true }) } })
            "$($stLegacy.id)|Blob"       = @{ deleteRetentionPolicy = @{ enabled = $false }; containerDeleteRetentionPolicy = @{ enabled = $false } }
            "$($stLegacy.id)|File"       = @{ shareDeleteRetentionPolicy = @{ enabled = $false } }
            "$($stLegacy.id)|Logs"       = @()
            "$($stArchive.id)|Blob"      = @{ deleteRetentionPolicy = @{ enabled = $true; days = 3 }; containerDeleteRetentionPolicy = @{ enabled = $true; days = 7 }; isVersioningEnabled = $true }
            "$($stArchive.id)|File"      = @{ shareDeleteRetentionPolicy = @{ enabled = $true; days = 7 } }
            "$($stArchive.id)|Logs"      = @(@{ name = 'to-law'; properties = @{ workspaceId = $workspace; logs = @(@{ category = 'StorageWrite'; enabled = $true }) } })
        }
        Scope    = @{
            Subscriptions = @(@{ subscriptionId = $prod; name = 'Contoso Prod' }, @{ subscriptionId = $dev; name = 'Contoso Dev' })
            Ids = @($prod, $dev); GraphScope = @(); Label = 'all 2 subscription(s)'
            Names = @{ $prod = 'Contoso Prod'; $dev = 'Contoso Dev' }
        }
    }
}
