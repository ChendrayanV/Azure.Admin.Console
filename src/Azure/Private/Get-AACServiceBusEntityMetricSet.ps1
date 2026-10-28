function Get-AACServiceBusEntityMetricSet {
    <#
    .SYNOPSIS
        The Azure Monitor metrics Show-AACServiceBusEntity reads for each
        queue or topic, in groups that fail on their own.
    .DESCRIPTION
        Service Bus publishes its metrics on the namespace only, split by
        the EntityName dimension (a topic's are the total of its
        subscriptions; there are none per subscription). A request naming a
        metric the tier doesn't publish fails whole, so the metrics are
        grouped - bytes, settlement and latency apart from the rest - and
        the namespace's Premium CPU and memory come separately, with no
        EntityName.

        Returns @{ Entity = @(@{ Key; Metric; Aggregation }); Premium =
        @{ Key; Metric; Aggregation }; Label = @{ metric = 'friendly name' };
        Kind = @{ metric = 'Total' | 'Backlog' | 'Peak' } }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    @{
        Entity  = @(
            @{ Key = 'Traffic'; Metric = @('IncomingMessages', 'OutgoingMessages'); Aggregation = @('Total') }
            @{ Key = 'Requests'; Metric = @('IncomingRequests', 'SuccessfulRequests', 'ServerErrors', 'UserErrors', 'ThrottledRequests'); Aggregation = @('Total') }
            @{ Key = 'Backlog'; Metric = @('ActiveMessages', 'DeadletteredMessages', 'ScheduledMessages', 'Size'); Aggregation = @('Average', 'Maximum') }
            @{ Key = 'Settlement'; Metric = @('CompleteMessage', 'AbandonMessage'); Aggregation = @('Total') }
            @{ Key = 'Bytes'; Metric = @('IncomingBytes', 'OutgoingBytes'); Aggregation = @('Total') }
            @{ Key = 'Latency'; Metric = @('ServerSendLatency'); Aggregation = @('Average', 'Maximum') }
        )
        Premium = @{ Key = 'Premium'; Metric = @('NamespaceCpuUsage', 'NamespaceMemoryUsage'); Aggregation = @('Maximum') }
        Label   = [ordered]@{
            IncomingMessages = 'Incoming messages'; OutgoingMessages = 'Outgoing messages'; CompleteMessage = 'Completed messages'; AbandonMessage = 'Abandoned messages'
            ActiveMessages = 'Active messages'; DeadletteredMessages = 'Dead-lettered messages'; ScheduledMessages = 'Scheduled messages'; Size = 'Size (bytes)'
            IncomingRequests = 'Incoming requests'; SuccessfulRequests = 'Successful requests'; ServerErrors = 'Server errors'; UserErrors = 'User errors'; ThrottledRequests = 'Throttled requests'
            IncomingBytes = 'Incoming bytes'; OutgoingBytes = 'Outgoing bytes'; ServerSendLatency = 'Server send latency (ms)'
            NamespaceCpuUsage = 'Namespace CPU %'; NamespaceMemoryUsage = 'Namespace memory %'
        }
        # Total: counts per interval, summed; Backlog: a level, averaged with its peak; Average: a level.
        Kind    = @{
            IncomingMessages = 'Total'; OutgoingMessages = 'Total'; CompleteMessage = 'Total'; AbandonMessage = 'Total'; IncomingRequests = 'Total'; SuccessfulRequests = 'Total'
            ServerErrors = 'Total'; UserErrors = 'Total'; ThrottledRequests = 'Total'; IncomingBytes = 'Total'; OutgoingBytes = 'Total'
            ActiveMessages = 'Backlog'; DeadletteredMessages = 'Backlog'; ScheduledMessages = 'Backlog'; Size = 'Backlog'; ServerSendLatency = 'Backlog'
            NamespaceCpuUsage = 'Peak'; NamespaceMemoryUsage = 'Peak'
        }
    }
}
