<#
    Made-up Contoso Service Bus namespaces for ServiceBusAssessment.Tests.ps1
    (and demo mode), as Resource Graph, Resource Manager and Azure Monitor
    return them.

      sb-orders  (Contoso Prod, rg-integration)  Premium, 2 messaging units,
                 zone redundant, Geo-DR alias; TLS 1.2, SAS keys off, private
                 (1 endpoint), logs to law-prod.
                 queue orders: 120 active, 1,500 dead-lettered, 800 of 1,024 MB
                 queue payments: empty, used yesterday
                 topic events: subscriptions billing (50 active, 3 dead-
                 lettered) and audit (12,000 active - a backlog)
                 100,000 requests: 2,000 throttled, 50 server errors, 1,000
                 client errors; CPU peaked at 85%, memory at 40%
      sb-legacy  (Contoso Dev, rg-dev)  Standard; TLS 1.0, SAS keys on (2
                 namespace-wide Manage keys), open to every network, no logs.
                 queue old-jobs: never used, messages expire after a day and
                 are dropped; topic orphan: no subscription. No requests.
      sb-basic   (Contoso Dev, rg-dev)  Basic; its metrics can't be read.
#>
function Get-AACContosoServiceBus {
    $prod = '11111111-1111-1111-1111-111111111111'
    $dev = '22222222-2222-2222-2222-222222222222'
    $workspace = "/subscriptions/$prod/resourcegroups/rg-monitor/providers/microsoft.operationalinsights/workspaces/law-prod"
    $namespace = { param($Sub, $Group, $Name, $Tier, $Capacity, $Properties) @{ id = "/subscriptions/$Sub/resourcegroups/$Group/providers/microsoft.servicebus/namespaces/$Name"; name = $Name; location = 'uksouth'; resourceGroup = $Group; subscriptionId = $Sub; tier = $Tier; capacity = $Capacity; properties = $Properties; identity = $null; tags = $null } }
    $orders = & $namespace $prod 'rg-integration' 'sb-orders' 'Premium' 2 @{ minimumTlsVersion = '1.2'; disableLocalAuth = $true; publicNetworkAccess = 'Disabled'; zoneRedundant = $true; privateEndpointConnections = @(@{ properties = @{ privateLinkServiceConnectionState = @{ status = 'Approved' } } }); encryption = @{ keySource = 'Microsoft.KeyVault' } }
    $legacy = & $namespace $dev 'rg-dev' 'sb-legacy' 'Standard' 1 @{ minimumTlsVersion = '1.0'; disableLocalAuth = $false; publicNetworkAccess = 'Enabled'; zoneRedundant = $false }
    $basic = & $namespace $dev 'rg-dev' 'sb-basic' 'Basic' 1 @{ minimumTlsVersion = '1.2'; disableLocalAuth = $false; publicNetworkAccess = 'Enabled' }

    $recently = [datetime]::UtcNow.AddDays(-1).ToString('o')
    $counts = { param($Active, $Dead, $Scheduled = 0, $Transfer = 0) @{ activeMessageCount = $Active; deadLetterMessageCount = $Dead; scheduledMessageCount = $Scheduled; transferMessageCount = 0; transferDeadLetterMessageCount = $Transfer } }
    $queue = { param($Ns, $Name, $Properties) @{ id = "$($Ns.id)/queues/$Name"; name = $Name; properties = $Properties } }
    $topic = { param($Ns, $Name, $Properties) @{ id = "$($Ns.id)/topics/$Name"; name = $Name; properties = $Properties } }
    $forever = 'P10675199DT2H48M5.4775807S'
    $point = { param($Value, [string] $Field = 'total') @{ timeStamp = '2026-10-15T10:00:00Z'; $Field = $Value } }
    $metric = { param($Name, $Value, [string] $Field = 'total') @{ name = @{ value = $Name }; timeseries = @(@{ metadatavalues = @(); data = @((& $point ($Value * 0.4) $Field), (& $point ($Value * 0.6) $Field)) }) } }
    $peak = { param($Name, $Value) @{ name = @{ value = $Name }; timeseries = @(@{ metadatavalues = @(); data = @((& $point ($Value / 2) 'maximum'), (& $point $Value 'maximum')) }) } }
    $list = { param([object[]] $Items) @{ Status = 200; Body = @{}; Items = @($Items); Error = '' } }
    $one = { param($Body) @{ Status = 200; Body = $Body; Items = $null; Error = '' } }
    $manage = { param($Name) @{ name = $Name; properties = @{ rights = @('Listen', 'Manage', 'Send') } } }
    @{
        Graph   = @{
            namespaces = @($orders, $legacy, $basic)
            workspaces = @(@{ id = $workspace; name = 'law-prod' })
        }
        # Resource Manager answers by path.
        Arm     = @{
            "$($orders.id)/queues"                          = & $list @(
                (& $queue $orders 'orders' @{ countDetails = (& $counts 120 1500); sizeInBytes = 800MB; maxSizeInMegabytes = 1024; status = 'Active'; maxDeliveryCount = 10; lockDuration = 'PT1M'; deadLetteringOnMessageExpiration = $true; defaultMessageTimeToLive = $forever; accessedAt = $recently })
                (& $queue $orders 'payments' @{ countDetails = (& $counts 0 0); sizeInBytes = 0; maxSizeInMegabytes = 1024; status = 'Active'; maxDeliveryCount = 10; deadLetteringOnMessageExpiration = $true; defaultMessageTimeToLive = 'P14D'; accessedAt = $recently })
            )
            "$($orders.id)/topics"                          = & $list @(& $topic $orders 'events' @{ sizeInBytes = 10MB; maxSizeInMegabytes = 5120; subscriptionCount = 2; status = 'Active'; defaultMessageTimeToLive = $forever; accessedAt = $recently })
            "$($orders.id)/topics/events/subscriptions"     = & $list @(
                @{ id = "$($orders.id)/topics/events/subscriptions/billing"; name = 'billing'; properties = @{ countDetails = (& $counts 50 3); status = 'Active'; maxDeliveryCount = 10; deadLetteringOnMessageExpiration = $true; defaultMessageTimeToLive = $forever; accessedAt = $recently } }
                @{ id = "$($orders.id)/topics/events/subscriptions/audit"; name = 'audit'; properties = @{ countDetails = (& $counts 12000 0); status = 'Active'; maxDeliveryCount = 10; deadLetteringOnMessageExpiration = $true; defaultMessageTimeToLive = $forever; accessedAt = $recently } }
            )
            "$($orders.id)/networkRuleSets/default"         = & $one @{ properties = @{ publicNetworkAccess = 'Disabled'; defaultAction = 'Deny' } }
            "$($orders.id)/authorizationRules"              = & $list @(& $manage 'RootManageSharedAccessKey')
            "$($orders.id)/disasterRecoveryConfigs"         = & $list @(@{ name = 'sb-orders-alias' })
            "$($orders.id)/providers/Microsoft.Insights/diagnosticSettings" = & $list @(@{ name = 'to-law'; properties = @{ workspaceId = $workspace; logs = @(@{ categoryGroup = 'audit'; enabled = $true }) } })
            "$($legacy.id)/queues"                          = & $list @(& $queue $legacy 'old-jobs' @{ countDetails = (& $counts 0 0); sizeInBytes = 0; maxSizeInMegabytes = 1024; status = 'Active'; maxDeliveryCount = 10; deadLetteringOnMessageExpiration = $false; defaultMessageTimeToLive = 'P1D'; accessedAt = '0001-01-01T00:00:00' })
            "$($legacy.id)/topics"                          = & $list @(& $topic $legacy 'orphan' @{ sizeInBytes = 0; maxSizeInMegabytes = 1024; subscriptionCount = 0; status = 'Active'; accessedAt = $recently })
            "$($legacy.id)/topics/orphan/subscriptions"     = & $list @()
            "$($legacy.id)/networkRuleSets/default"         = & $one @{ properties = @{ publicNetworkAccess = 'Enabled'; defaultAction = 'Allow'; ipRules = @(); virtualNetworkRules = @() } }
            "$($legacy.id)/authorizationRules"              = & $list @((& $manage 'RootManageSharedAccessKey'), (& $manage 'app-admin'))
            "$($legacy.id)/disasterRecoveryConfigs"         = & $list @()
            "$($legacy.id)/providers/Microsoft.Insights/diagnosticSettings" = & $list @()
            "$($basic.id)/queues"                           = & $list @()
            "$($basic.id)/topics"                           = @{ Status = 400; Body = $null; Items = $null; Error = 'Topics are not supported in the Basic tier.' }
        }
        # "<namespace>|<call>" -> the metrics API's body.
        Metrics = @{
            "$($orders.id)|Core"    = @{ value = @((& $metric 'IncomingRequests' 100000), (& $metric 'SuccessfulRequests' 96950), (& $metric 'ServerErrors' 50), (& $metric 'UserErrors' 1000), (& $metric 'ThrottledRequests' 2000), (& $metric 'IncomingMessages' 60000), (& $metric 'OutgoingMessages' 58000)) }
            "$($orders.id)|Premium" = @{ value = @((& $peak 'NamespaceCpuUsage' 85), (& $peak 'NamespaceMemoryUsage' 40)) }
            "$($legacy.id)|Core"    = @{ value = @((& $metric 'IncomingRequests' 0), (& $metric 'ThrottledRequests' 0)) }
        }
        Scope   = @{
            Subscriptions = @(@{ subscriptionId = $prod; name = 'Contoso Prod' }, @{ subscriptionId = $dev; name = 'Contoso Dev' })
            Ids = @($prod, $dev); GraphScope = @(); Label = 'all 2 subscription(s)'
            Names = @{ $prod = 'Contoso Prod'; $dev = 'Contoso Dev' }
        }
    }
}
