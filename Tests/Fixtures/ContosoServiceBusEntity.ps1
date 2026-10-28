<#
    Made-up Contoso Service Bus namespaces for ServiceBusEntity.Tests.ps1, as
    Resource Manager and Azure Monitor answer a user with different roles.

      sb-shared  (Premium)  the user can read the namespace and its metrics.
                 queue orders: 120 active, 1,500 dead-lettered, 850 of 1,024
                 MB; 600 in, 400 out, 5 throttled; active messages climbing
                 50 -> 90 -> 120.
                 queue payments: empty, no metrics.
                 topic events: subscriptions billing (50 active, 3 dead-
                 lettered) and audit (12,000 active).
                 Completed/abandoned metrics answer 400 (not published);
                 CPU peaked at 85%.
      sb-team    (Standard)  the user holds Data Receiver on queue team-orders
                 only: the namespace and its metrics answer 403, so do the
                 other entities (secret). team-orders' active count grows by
                 10 on every read (for -Sample).
#>
function Get-AACContosoServiceBusEntity {
    $sub = '11111111-1111-1111-1111-111111111111'
    $shared = "/subscriptions/$sub/resourceGroups/rg-integration/providers/Microsoft.ServiceBus/namespaces/sb-shared"
    $team = "/subscriptions/$sub/resourceGroups/rg-integration/providers/Microsoft.ServiceBus/namespaces/sb-team"
    $recently = [datetime]::UtcNow.AddDays(-1).ToString('o')
    $forever = 'P10675199DT2H48M5.4775807S'
    $counts = { param($Active, $Dead, $Scheduled = 0) @{ activeMessageCount = $Active; deadLetterMessageCount = $Dead; scheduledMessageCount = $Scheduled; transferMessageCount = 0; transferDeadLetterMessageCount = 0 } }
    $one = { param($Body) @{ Status = 200; Body = $Body; Items = $null; Error = '' } }
    $list = { param([object[]] $Items) @{ Status = 200; Body = @{}; Items = @($Items); Error = '' } }
    $forbidden = @{ Status = 403; Body = $null; Items = $null; Error = "The client does not have authorization to perform action 'Microsoft.ServiceBus/namespaces/read'." }

    $orders = @{ id = "$shared/queues/orders"; name = 'orders'; properties = @{ countDetails = (& $counts 120 1500); messageCount = 1620; sizeInBytes = 850MB; maxSizeInMegabytes = 1024; status = 'Active'; maxDeliveryCount = 10; lockDuration = 'PT1M'; deadLetteringOnMessageExpiration = $true; defaultMessageTimeToLive = $forever; requiresSession = $false; accessedAt = $recently; createdAt = '2025-01-10T08:00:00Z' } }
    $payments = @{ id = "$shared/queues/payments"; name = 'payments'; properties = @{ countDetails = (& $counts 0 0); messageCount = 0; sizeInBytes = 0; maxSizeInMegabytes = 1024; status = 'Active'; maxDeliveryCount = 10; lockDuration = 'PT30S'; deadLetteringOnMessageExpiration = $false; defaultMessageTimeToLive = 'P14D'; accessedAt = $recently } }
    $events = @{ id = "$shared/topics/events"; name = 'events'; properties = @{ countDetails = (& $counts 0 0 4); subscriptionCount = 2; sizeInBytes = 2MB; maxSizeInMegabytes = 1024; status = 'Active'; defaultMessageTimeToLive = $forever; supportOrdering = $true; accessedAt = $recently } }
    $billing = @{ id = "$shared/topics/events/subscriptions/billing"; name = 'billing'; properties = @{ countDetails = (& $counts 50 3); messageCount = 53; status = 'Active'; maxDeliveryCount = 10; lockDuration = 'PT1M'; deadLetteringOnMessageExpiration = $true; deadLetteringOnFilterEvaluationExceptions = $true; accessedAt = $recently } }
    $audit = @{ id = "$shared/topics/events/subscriptions/audit"; name = 'audit'; properties = @{ countDetails = (& $counts 12000 0); messageCount = 12000; status = 'Active'; maxDeliveryCount = 5; lockDuration = 'PT1M'; deadLetteringOnMessageExpiration = $true; accessedAt = $recently } }
    $teamOrders = { param([long] $Active) @{ id = "$team/queues/team-orders"; name = 'team-orders'; properties = @{ countDetails = (& $counts $Active 0); messageCount = $Active; sizeInBytes = 1MB; maxSizeInMegabytes = 1024; status = 'Active'; maxDeliveryCount = 10; lockDuration = 'PT1M'; deadLetteringOnMessageExpiration = $true; defaultMessageTimeToLive = $forever; accessedAt = $recently } } }.GetNewClosure()

    # Metrics: one series per entity, split by EntityName, three hourly points.
    $times = @('2026-10-15T10:00:00Z', '2026-10-15T11:00:00Z', '2026-10-15T12:00:00Z')
    $series = {
        param([string] $Metric, [string] $Entity, [double[]] $Values, [double[]] $Peaks = @())
        $data = for ($i = 0; $i -lt $Values.Count; $i++) {
            $p = @{ timeStamp = $times[$i]; total = $Values[$i]; average = $Values[$i] }
            if ($Peaks.Count) { $p['maximum'] = $Peaks[$i] }
            $p
        }
        $dims = if ($Entity) { @(@{ name = @{ value = 'EntityName' }; value = $Entity }) } else { @() }
        @{ name = @{ value = $Metric }; timeseries = @(@{ metadatavalues = $dims; data = @($data) }) }
    }
    $answer = { param([object[]] $Value) @{ Status = 200; Body = @{ value = @($Value) }; Items = $null; Error = '' } }

    @{
        Shared  = $shared
        Team    = $team
        Arm     = @{
            $shared                                  = & $one @{ id = $shared; name = 'sb-shared'; sku = @{ name = 'Premium'; tier = 'Premium'; capacity = 1 } }
            "$shared/queues"                         = & $list @($orders, $payments)
            "$shared/topics"                         = & $list @($events)
            "$shared/queues/orders"                  = & $one $orders
            "$shared/queues/payments"                = & $one $payments
            "$shared/topics/events"                  = & $one $events
            "$shared/topics/events/subscriptions"    = & $list @($billing, $audit)
            $team                                    = $forbidden
            "$team/topics/team-orders"               = $forbidden
            "$team/queues/secret"                    = $forbidden
            "$team/topics/secret"                    = $forbidden
        }
        # team-orders is answered by the mock, so its count can grow between reads.
        TeamOrders = $teamOrders
        Metrics = @{
            "$shared|Traffic"    = & $answer @((& $series 'IncomingMessages' 'orders' @(100, 200, 300)), (& $series 'OutgoingMessages' 'orders' @(100, 150, 150)), (& $series 'IncomingMessages' 'events' @(10, 10, 10)), (& $series 'OutgoingMessages' 'events' @(10, 10, 10)))
            "$shared|Requests"   = & $answer @((& $series 'IncomingRequests' 'orders' @(300, 300, 400)), (& $series 'ThrottledRequests' 'orders' @(0, 0, 5)), (& $series 'ServerErrors' 'orders' @(0, 0, 0)), (& $series 'UserErrors' 'orders' @(1, 1, 0)))
            "$shared|Backlog"    = & $answer @((& $series 'ActiveMessages' 'orders' @(50, 90, 120) @(60, 100, 130)), (& $series 'DeadletteredMessages' 'orders' @(1500, 1500, 1500) @(1500, 1500, 1500)), (& $series 'ActiveMessages' 'events' @(12050, 12050, 12050) @(12050, 12050, 12050)))
            "$shared|Settlement" = @{ Status = 400; Body = $null; Items = $null; Error = 'Failed to find metric configuration for provider.' }
            "$shared|Bytes"      = & $answer @()
            "$shared|Latency"    = & $answer @((& $series 'ServerSendLatency' 'orders' @(8, 10, 12) @(20, 25, 30)))
            "$shared|Premium"    = & $answer @((& $series 'NamespaceCpuUsage' '' @(40, 60, 85) @(40, 60, 85)), (& $series 'NamespaceMemoryUsage' '' @(30, 30, 35) @(30, 30, 35)))
        }
        Forbidden = $forbidden
    }
}
