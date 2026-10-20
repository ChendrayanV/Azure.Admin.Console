<#
    Made-up Contoso Azure Cosmos DB accounts for CosmosDBAssessment.Tests.ps1
    (and demo mode), as Resource Graph, Resource Manager and Azure Monitor
    return them.

      cosmos-orders  (Contoso Prod, rg-data)  NoSQL; UK South (zone
                     redundant) and UK West, automatic failover, Session,
                     continuous backup (7 days); private (1 endpoint), keys
                     off, TLS 1.2, customer-managed key, logs to law-prod.
                     Database shop (autoscale 4,000 RU/s shared): orders
                     (autoscale 10,000 of its own, /customerId), carts
                     (shared). 93,520 requests: 3,000 rate limited (429), 20
                     service unavailable (503), 500 not found; busiest
                     partition 100%; availability 99.995%; 4 ms; 50 GB data,
                     5 GB index, 2,000,000 documents.
      cosmos-legacy  (Contoso Dev, rg-dev)  NoSQL; UK South only, no zones,
                     periodic backup every 4 hours to local storage; open to
                     every network, keys on (and able to change databases),
                     TLS 1.0, no logs. Database legacydb: four containers of
                     400 RU/s and one of 2,000 (manual), the busiest
                     partition at 5%; 1,000 requests; availability 99.95%.
      mongo-catalog  (Contoso Prod, rg-data)  MongoDB, serverless; its metrics
                     can't be read.
    Defender for Azure Cosmos DB: on in Prod, off in Dev.
#>
function Get-AACContosoCosmosDB {
    $prod = '11111111-1111-1111-1111-111111111111'
    $dev = '22222222-2222-2222-2222-222222222222'
    $workspace = "/subscriptions/$prod/resourcegroups/rg-monitor/providers/microsoft.operationalinsights/workspaces/law-prod"
    $account = { param($Sub, $Group, $Name, $Kind, $Properties) @{ id = "/subscriptions/$Sub/resourcegroups/$Group/providers/microsoft.documentdb/databaseaccounts/$Name"; name = $Name; location = 'uksouth'; resourceGroup = $Group; subscriptionId = $Sub; kind = $Kind; properties = $Properties; identity = $null; tags = $null } }
    $region = { param($Name, $Priority, $Zonal) @{ locationName = $Name; failoverPriority = $Priority; isZoneRedundant = $Zonal } }
    $orders = & $account $prod 'rg-data' 'cosmos-orders' 'GlobalDocumentDB' @{
        locations = @((& $region 'UK South' 0 $true), (& $region 'UK West' 1 $false)); enableAutomaticFailover = $true; enableMultipleWriteLocations = $false
        consistencyPolicy = @{ defaultConsistencyLevel = 'Session' }; backupPolicy = @{ type = 'Continuous'; continuousModeProperties = @{ tier = 'Continuous7Days' } }
        publicNetworkAccess = 'Disabled'; privateEndpointConnections = @(@{ properties = @{ privateLinkServiceConnectionState = @{ status = 'Approved' } } })
        disableLocalAuth = $true; disableKeyBasedMetadataWriteAccess = $true; minimalTlsVersion = 'Tls12'; keyVaultKeyUri = 'https://kv-contoso.vault.azure.net/keys/cosmos'; capabilities = @()
    }
    $legacy = & $account $dev 'rg-dev' 'cosmos-legacy' 'GlobalDocumentDB' @{
        locations = @(& $region 'UK South' 0 $false); enableAutomaticFailover = $false; consistencyPolicy = @{ defaultConsistencyLevel = 'Eventual' }
        backupPolicy = @{ type = 'Periodic'; periodicModeProperties = @{ backupIntervalInMinutes = 240; backupRetentionIntervalInHours = 8; backupStorageRedundancy = 'Local' } }
        publicNetworkAccess = 'Enabled'; ipRules = @(); isVirtualNetworkFilterEnabled = $false; disableLocalAuth = $false; minimalTlsVersion = 'Tls'; capabilities = @()
    }
    $mongo = & $account $prod 'rg-data' 'mongo-catalog' 'MongoDB' @{
        locations = @(& $region 'UK South' 0 $true); consistencyPolicy = @{ defaultConsistencyLevel = 'Session' }; backupPolicy = @{ type = 'Continuous'; continuousModeProperties = @{ tier = 'Continuous30Days' } }
        publicNetworkAccess = 'Disabled'; disableLocalAuth = $true; disableKeyBasedMetadataWriteAccess = $true; minimalTlsVersion = 'Tls12'; capabilities = @(@{ name = 'EnableMongo' }, @{ name = 'EnableServerless' })
    }

    $list = { param([object[]] $Items) @{ Status = 200; Body = @{}; Items = @($Items); Error = '' } }
    $one = { param($Body) @{ Status = 200; Body = $Body; Items = $null; Error = '' } }
    $autoscale = { param($Max) & $one @{ properties = @{ resource = @{ throughput = [int]($Max / 10); autoscaleSettings = @{ maxThroughput = $Max } } } } }
    $manual = { param($RU) & $one @{ properties = @{ resource = @{ throughput = $RU } } } }
    $child = { param($Parent, $Kind, $Name, $Resource) @{ id = "$Parent/$Kind/$Name"; name = $Name; properties = @{ resource = $Resource } } }
    $shop = "$($orders.id)/sqlDatabases/shop"
    $legacyDb = "$($legacy.id)/sqlDatabases/legacydb"
    $catalog = "$($mongo.id)/mongodbDatabases/catalog"
    $arm = @{
        "$($orders.id)/sqlDatabases"                                        = & $list @(@{ id = $shop; name = 'shop'; properties = @{ resource = @{ id = 'shop' } } })
        "$shop/containers"                                                  = & $list @((& $child $shop 'containers' 'orders' @{ partitionKey = @{ paths = @('/customerId') }; defaultTtl = -1; indexingPolicy = @{ indexingMode = 'consistent' } }), (& $child $shop 'containers' 'carts' @{ partitionKey = @{ paths = @('/cartId') }; defaultTtl = 86400; indexingPolicy = @{ indexingMode = 'consistent' } }))
        "$shop/throughputSettings/default"                                  = & $autoscale 4000
        "$shop/containers/orders/throughputSettings/default"                = & $autoscale 10000
        "$($orders.id)/providers/Microsoft.Insights/diagnosticSettings"     = & $list @(@{ name = 'to-law'; properties = @{ workspaceId = $workspace; logs = @(@{ category = 'DataPlaneRequests'; enabled = $true }) } })
        "$($legacy.id)/sqlDatabases"                                        = & $list @(@{ id = $legacyDb; name = 'legacydb'; properties = @{ resource = @{ id = 'legacydb' } } })
        "$($legacy.id)/providers/Microsoft.Insights/diagnosticSettings"     = & $list @()
        "$($mongo.id)/mongodbDatabases"                                     = & $list @(@{ id = $catalog; name = 'catalog'; properties = @{ resource = @{ id = 'catalog' } } })
        "$catalog/collections"                                              = & $list @(& $child $catalog 'collections' 'products' @{ shardKey = @{ sku = 'Hash' } })
        "$($mongo.id)/providers/Microsoft.Insights/diagnosticSettings"      = & $list @()
    }
    $legacyContainers = foreach ($n in 'audit', 'sessions', 'flags', 'jobs', 'reports') { & $child $legacyDb 'containers' $n @{ partitionKey = @{ paths = @('/id') }; indexingPolicy = @{ indexingMode = 'consistent' } } }
    $arm["$legacyDb/containers"] = & $list @($legacyContainers)
    foreach ($n in 'audit', 'sessions', 'flags', 'jobs') { $arm["$legacyDb/containers/$n/throughputSettings/default"] = & $manual 400 }
    $arm["$legacyDb/containers/reports/throughputSettings/default"] = & $manual 2000
    # No shared throughput on legacydb, nor on orders' carts container: 404.

    $point = { param([string] $Field, $Value) @{ timeStamp = '2026-10-15T10:00:00Z'; $Field = $Value } }
    $metric = { param($Name, [string] $Field, [object[]] $Values) @{ name = @{ value = $Name }; timeseries = @(@{ metadatavalues = @(); data = @($Values | ForEach-Object { & $point $Field $_ }) }) } }
    $byCode = { param([hashtable] $Codes) @{ name = @{ value = 'TotalRequests' }; timeseries = @(foreach ($code in $Codes.Keys) { @{ metadatavalues = @(@{ name = @{ value = 'statuscode' }; value = $code }); data = @(& $point 'count' $Codes[$code]) } }) } }
    @{
        Graph   = @{
            accounts   = @($orders, $legacy, $mongo)
            pricing    = @(@{ subscriptionId = $prod; tier = 'Standard' }, @{ subscriptionId = $dev; tier = 'Free' })
            alerts     = @()
            workspaces = @(@{ id = $workspace; name = 'law-prod' })
        }
        Arm     = $arm
        # "<account>|<call>" -> the metrics API's body.
        Metrics = @{
            "$($orders.id)|Requests"     = @{ value = @(& $byCode @{ '200' = 90000; '429' = 3000; '503' = 20; '404' = 500 }) }
            "$($orders.id)|Usage"        = @{ value = @((& $metric 'TotalRequestUnits' 'total' @(2000000, 3000000)), (& $metric 'NormalizedRUConsumption' 'maximum' @(60, 100))) }
            "$($orders.id)|Availability" = @{ value = @(& $metric 'ServiceAvailability' 'average' @(99.99, 100)) }
            "$($orders.id)|Latency"      = @{ value = @(& $metric 'ServerSideLatency' 'average' @(3, 5)) }
            "$($orders.id)|Storage"      = @{ value = @((& $metric 'DataUsage' 'total' @(40GB, 50GB)), (& $metric 'IndexUsage' 'total' @(4GB, 5GB)), (& $metric 'DocumentCount' 'total' @(1900000, 2000000))) }
            "$($legacy.id)|Requests"     = @{ value = @(& $byCode @{ '200' = 1000 }) }
            "$($legacy.id)|Usage"        = @{ value = @((& $metric 'TotalRequestUnits' 'total' @(5000)), (& $metric 'NormalizedRUConsumption' 'maximum' @(2, 5))) }
            "$($legacy.id)|Availability" = @{ value = @(& $metric 'ServiceAvailability' 'average' @(99.9, 100)) }
        }
        Scope   = @{
            Subscriptions = @(@{ subscriptionId = $prod; name = 'Contoso Prod' }, @{ subscriptionId = $dev; name = 'Contoso Dev' })
            Ids = @($prod, $dev); GraphScope = @(); Label = 'all 2 subscription(s)'
            Names = @{ $prod = 'Contoso Prod'; $dev = 'Contoso Dev' }
        }
    }
}
