function Get-AACUtilizationMetric {
    <#
    .SYNOPSIS
        Which Azure Monitor metrics measure how much of each resource type is
        used - its compute, its memory, its activity - for
        Get-AACResourceUtilization.
    .DESCRIPTION
        Returns a hashtable: resource type -> @{ Label; Cpu; Memory; MemoryKind
        ('Percent', or 'AvailableBytes' for a VM's free memory); Activity
        (a count summed over the window: transactions, requests);
        Down (what scaling down means for it) }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    @{
        'microsoft.compute/virtualmachines'          = @{ Label = 'VM'; Cpu = 'Percentage CPU'; Memory = 'Available Memory Bytes'; MemoryKind = 'AvailableBytes'; Activity = 'Network In Total'; Down = 'a smaller size (or deallocate it when idle: a stopped but allocated VM is still billed)' }
        'microsoft.compute/virtualmachinescalesets'  = @{ Label = 'Scale set'; Cpu = 'Percentage CPU'; Memory = ''; MemoryKind = ''; Activity = 'Network In Total'; Down = 'fewer instances (autoscale with a lower minimum) or a smaller size' }
        'microsoft.web/serverfarms'                  = @{ Label = 'App Service plan'; Cpu = 'CpuPercentage'; Memory = 'MemoryPercentage'; MemoryKind = 'Percent'; Activity = ''; Down = 'fewer instances or a smaller tier - or move its apps to a shared plan' }
        'microsoft.sql/servers/databases'            = @{ Label = 'SQL database'; Cpu = 'cpu_percent'; Memory = ''; MemoryKind = ''; Activity = 'connection_successful'; Down = 'fewer vCores or DTUs, or serverless (it pauses when idle)' }
        'microsoft.dbforpostgresql/flexibleservers'  = @{ Label = 'PostgreSQL'; Cpu = 'cpu_percent'; Memory = 'memory_percent'; MemoryKind = 'Percent'; Activity = 'active_connections'; Down = 'a smaller compute size, or Burstable' }
        'microsoft.dbformysql/flexibleservers'       = @{ Label = 'MySQL'; Cpu = 'cpu_percent'; Memory = 'memory_percent'; MemoryKind = 'Percent'; Activity = 'active_connections'; Down = 'a smaller compute size, or Burstable' }
        'microsoft.cache/redis'                      = @{ Label = 'Redis'; Cpu = 'percentProcessorTime'; Memory = 'usedmemorypercentage'; MemoryKind = 'Percent'; Activity = 'totalcommandsprocessed'; Down = 'a smaller cache size' }
        'microsoft.containerservice/managedclusters' = @{ Label = 'AKS'; Cpu = 'node_cpu_usage_percentage'; Memory = 'node_memory_working_set_percentage'; MemoryKind = 'Percent'; Activity = ''; Down = 'fewer or smaller nodes (the cluster autoscaler with a lower minimum)' }
        'microsoft.storage/storageaccounts'          = @{ Label = 'Storage'; Cpu = ''; Memory = ''; MemoryKind = ''; Activity = 'Transactions'; Down = 'a cooler access tier, or deleting it if nothing uses it' }
        'microsoft.documentdb/databaseaccounts'      = @{ Label = 'Cosmos DB'; Cpu = 'NormalizedRUConsumption'; Memory = ''; MemoryKind = ''; Activity = 'TotalRequests'; Down = 'less provisioned throughput, autoscale, or serverless' }
    }
}
