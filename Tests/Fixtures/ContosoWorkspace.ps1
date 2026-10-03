<#
    A made-up Log Analytics workspace for the Invoke-AACLogAnalyticsWorkspaceAssessment
    tests, in the shapes Azure returns: the workspace and its child
    resources (Resource Manager), Resource Graph rows and KQL rows. Built so
    every rule has something to find: the daily cap hit, a retired MMA agent,
    a silent agent, tables for the Basic plan, an unused custom table, a DCR
    with no associations, query auditing off, no diagnostic settings, shared
    keys enabled and a spike.

    Returns @{ Now; WorkspaceId; ResourceId; Workspace; Arm; Graph; Kql }.
#>
$now = [datetime]::new(2026, 10, 2, 12, 0, 0, [DateTimeKind]::Utc)
$sub = '11111111-1111-1111-1111-111111111111'
$rg = 'rg-contoso-ops'
$ws = "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.OperationalInsights/workspaces/law-contoso"
$customerId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
$iso = { param([datetime] $When) $When.ToString('yyyy-MM-ddTHH:mm:ss.fffZ') }
$dcr = { param([string] $Name) "/subscriptions/$sub/resourceGroups/rg-contoso-monitor/providers/Microsoft.Insights/dataCollectionRules/$Name" }
$vm = { param([string] $Name) "/subscriptions/$sub/resourceGroups/rg-contoso-app/providers/Microsoft.Compute/virtualMachines/$Name" }

$workspace = @{
    id = $ws; name = 'law-contoso'; location = 'uksouth'; tags = @{ env = 'prod'; owner = 'platform' }
    properties = @{
        customerId = $customerId; provisioningState = 'Succeeded'; createdDate = '2024-01-15T09:00:00Z'; modifiedDate = '2026-09-20T10:00:00Z'
        sku = @{ name = 'PerGB2018'; lastSkuUpdate = '2024-01-15T09:00:00Z' }
        retentionInDays = 90
        workspaceCapping = @{ dailyQuotaGb = 5; quotaNextResetTime = '2026-10-03T07:00:00Z'; dataIngestionStatus = 'RespectQuota' }
        features = @{ enableLogAccessUsingOnlyResourcePermissions = $true; disableLocalAuth = $false; legacy = 0 }
        publicNetworkAccessForIngestion = 'Enabled'; publicNetworkAccessForQuery = 'Enabled'
        defaultDataCollectionRuleResourceId = (& $dcr 'dcr-workspace-transform')
        someNewSetting = 'preview-value'
    }
}
$table = { param([string] $Name, [string] $Type = 'Microsoft', [int] $Retention = 90, [bool] $Default = $true, [string] $Plan = 'Analytics', [string] $SubType = 'Any')
    @{ name = $Name; properties = @{ plan = $Plan; retentionInDays = $Retention; totalRetentionInDays = $Retention; retentionInDaysAsDefault = $Default; schema = @{ name = $Name; tableType = $Type; tableSubType = $SubType; solutions = @('LogManagement') } } }
}
$arm = @{
    tables                = @{ Status = 200; Error = ''; Body = $null; Items = @(
            (& $table 'Perf'), (& $table 'ContainerLogV2'), (& $table 'Heartbeat'), (& $table 'AzureActivity'), (& $table 'Syslog')
            (& $table 'App_CL' -Type 'CustomLog' -SubType 'DataCollectionRuleBased')
            (& $table 'Old_CL' -Type 'CustomLog' -SubType 'Classic')
            (& $table 'SecurityEvent' -Retention 180 -Default $false)
            (& $table 'W3CIISLog')
        )
    }
    dataExports           = @{ Status = 200; Error = ''; Body = $null; Items = @(@{ name = 'export-to-adx'; properties = @{ enable = $true; tableNames = @('Perf', 'Syslog'); destination = @{ resourceId = "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Storage/storageAccounts/stcontosoexport" } } }) }
    linkedServices        = @{ Status = 404; Error = 'Not found'; Body = $null; Items = $null }
    linkedStorageAccounts = @{ Status = 200; Error = ''; Body = $null; Items = @() }
    diagnosticSettings    = @{ Status = 200; Error = ''; Body = $null; Items = @() }
    savedSearches         = @{ Status = 200; Error = ''; Body = $null; Items = @(@{ name = 's1' }, @{ name = 's2' }) }
    activityLog           = @{ Status = 200; Error = ''; Body = $null; Items = @(
            @{ eventTimestamp = (& $iso $now.AddDays(-2)); operationName = @{ value = 'Microsoft.OperationalInsights/workspaces/write'; localizedValue = 'Create Workspace' }; status = @{ value = 'Succeeded' }; caller = 'admin@contoso.com'; resourceId = $ws; level = 'Informational'; subStatus = @{ localizedValue = '' } }
            @{ eventTimestamp = (& $iso $now.AddDays(-2).AddSeconds(-5)); operationName = @{ value = 'Microsoft.OperationalInsights/workspaces/write'; localizedValue = 'Create Workspace' }; status = @{ value = 'Started' }; caller = 'admin@contoso.com'; resourceId = $ws; level = 'Informational' }
            @{ eventTimestamp = (& $iso $now.AddDays(-5)); operationName = @{ value = 'Microsoft.OperationalInsights/workspaces/tables/write'; localizedValue = 'Update table' }; status = @{ value = 'Failed' }; caller = 'ops@contoso.com'; resourceId = "$ws/tables/SecurityEvent"; level = 'Error'; subStatus = @{ localizedValue = 'Bad Request' } }
            @{ eventTimestamp = (& $iso $now.AddDays(-1)); operationName = @{ value = 'Microsoft.Storage/storageAccounts/write'; localizedValue = 'Create storage account' }; status = @{ value = 'Succeeded' }; caller = 'dev@contoso.com'; resourceId = "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Storage/storageAccounts/stother"; level = 'Informational' }
        )
    }
}

$daily = @(for ($i = 29; $i -ge 0; $i--) {
        $billable = if ($i -eq 3) { 9.0 } else { 3.0 }
        [ordered]@{ Day = (& $iso $now.Date.AddDays(-$i)); BillableGB = $billable; NonBillableGB = 0.05 }
    })
$kql = @{
    Rows   = @{
        tables     = @(
            [ordered]@{ Table = 'ContainerLogV2'; BillableGB = 45.0; NonBillableGB = 0.0; LastRecord = (& $iso $now.AddMinutes(-3)); Solution = 'ContainerInsights' }
            [ordered]@{ Table = 'Perf'; BillableGB = 30.0; NonBillableGB = 0.0; LastRecord = (& $iso $now.AddMinutes(-2)); Solution = 'LogManagement' }
            [ordered]@{ Table = 'Syslog'; BillableGB = 12.0; NonBillableGB = 0.0; LastRecord = (& $iso $now.AddMinutes(-4)); Solution = 'LogManagement' }
            [ordered]@{ Table = 'App_CL'; BillableGB = 10.0; NonBillableGB = 0.0; LastRecord = (& $iso $now.AddHours(-1)); Solution = 'LogManagement' }
            [ordered]@{ Table = 'Heartbeat'; BillableGB = 2.0; NonBillableGB = 0.0; LastRecord = (& $iso $now.AddMinutes(-1)); Solution = 'LogManagement' }
            [ordered]@{ Table = 'AzureActivity'; BillableGB = 0.0; NonBillableGB = 1.5; LastRecord = (& $iso $now.AddMinutes(-30)); Solution = 'LogManagement' }
        )
        daily      = $daily
        solutions  = @([ordered]@{ Solution = 'ContainerInsights'; BillableGB = 45.0; NonBillableGB = 0.0 }, [ordered]@{ Solution = 'LogManagement'; BillableGB = 54.0; NonBillableGB = 1.5 })
        resources  = @([ordered]@{ ResourceId = (& $vm 'vm-web01').ToLowerInvariant(); BillableGB = 1.2 }, [ordered]@{ ResourceId = ''; BillableGB = 0.3 })
        computers  = @([ordered]@{ Computer = 'vm-web01'; BillableGB = 1.1 }, [ordered]@{ Computer = 'vm-sql01'; BillableGB = 0.4 })
        operations = @(
            [ordered]@{ Category = 'Ingestion'; Level = 'Error'; Operation = 'Data collection Stopped'; Detail = 'Data collection stopped due to daily limit of free data reached. Ingestion status = OverQuota'; Count = 2; FirstSeen = (& $iso $now.AddDays(-3)); LastSeen = (& $iso $now.AddDays(-3).AddHours(5)) }
            [ordered]@{ Category = 'Ingestion'; Level = 'Warning'; Operation = 'Ingestion rate'; Detail = 'The data ingestion volume rate crossed 80% of the threshold.'; Count = 4; FirstSeen = (& $iso $now.AddDays(-6)); LastSeen = (& $iso $now.AddDays(-1)) }
        )
        latency    = @([ordered]@{ Category = 'Azure Monitor Agent'; Records = 2880; P50Seconds = 42.5; P95Seconds = 95.0; MaxSeconds = 300.2 })
        agents     = @(
            [ordered]@{ Computer = 'vm-web01'; LastHeartbeat = (& $iso $now.AddMinutes(-1)); Category = 'Azure Monitor Agent'; OSType = 'Windows'; OSName = 'Windows Server 2022'; Version = '1.30'; ComputerEnvironment = 'Azure'; ResourceId = (& $vm 'vm-web01') }
            [ordered]@{ Computer = 'vm-sql01'; LastHeartbeat = (& $iso $now.AddHours(-3)); Category = 'Direct Agent'; OSType = 'Windows'; OSName = 'Windows Server 2016'; Version = '10.20'; ComputerEnvironment = 'Azure'; ResourceId = (& $vm 'vm-sql01') }
            [ordered]@{ Computer = 'onprem-app01'; LastHeartbeat = (& $iso $now.AddDays(-3)); Category = 'Azure Monitor Agent'; OSType = 'Linux'; OSName = 'Ubuntu'; Version = '1.29'; ComputerEnvironment = 'Non-Azure'; ResourceId = '' }
        )
        auditUsers = @(); auditSlowest = @(); auditFailed = @()
    }
    Errors = @{
        auditUsers   = "Failed to resolve table or column expression named 'LAQueryLogs'"
        auditSlowest = "Failed to resolve table or column expression named 'LAQueryLogs'"
        auditFailed  = "Failed to resolve table or column expression named 'LAQueryLogs'"
    }
}

$graph = @{
    Rows   = @{
        workspace    = @(@{ id = $ws })
        rules        = @(
            @{ id = (& $dcr 'dcr-windows'); name = 'dcr-windows'; resourceGroup = 'rg-contoso-monitor'; subscriptionId = $sub; location = 'uksouth'; kind = 'Windows'
                properties = @{ description = 'Windows events and counters'; dataSources = @{ windowsEventLogs = @(@{ name = 'a' }, @{ name = 'b' }); performanceCounters = @(@{ name = 'c' }) }
                    destinations = @{ logAnalytics = @(@{ name = 'la'; workspaceResourceId = $ws }) }
                    dataFlows = @(@{ streams = @('Microsoft-Event'); destinations = @('la'); outputStream = 'Microsoft-Event'; transformKql = 'source | where EventLevel < 4' }, @{ streams = @('Microsoft-Perf'); destinations = @('la'); transformKql = 'source' }) } }
            @{ id = (& $dcr 'dcr-linux-unused'); name = 'dcr-linux-unused'; resourceGroup = 'rg-contoso-monitor'; subscriptionId = $sub; location = 'uksouth'; kind = 'Linux'
                properties = @{ dataSources = @{ syslog = @(@{ name = 's' }) }; destinations = @{ logAnalytics = @(@{ name = 'la'; workspaceResourceId = $ws }) }; dataFlows = @(@{ streams = @('Microsoft-Syslog'); destinations = @('la') }) } }
            @{ id = (& $dcr 'dcr-workspace-transform'); name = 'dcr-workspace-transform'; resourceGroup = 'rg-contoso-monitor'; subscriptionId = $sub; location = 'uksouth'; kind = 'WorkspaceTransforms'
                properties = @{ dataSources = @{}; destinations = @{ logAnalytics = @(@{ name = 'la'; workspaceResourceId = $ws }) }; dataFlows = @(@{ streams = @('Microsoft-Table-Syslog'); destinations = @('la'); transformKql = 'source | project-away RawData' }) } }
        )
        solutions    = @(@{ name = 'SecurityInsights(law-contoso)'; product = 'OMSGallery/SecurityInsights'; publisher = 'Microsoft' })
        advisor      = @(@{ id = 'adv1'; category = 'Cost'; impact = 'High'; problem = 'Consider a commitment tier'; solution = 'Change the pricing tier'; learnMore = 'https://aka.ms/advisor' })
        associations = @(@{ id = "$((& $vm 'vm-web01').ToLowerInvariant())/providers/microsoft.insights/datacollectionruleassociations/a1"; name = 'a1'; rule = (& $dcr 'dcr-windows').ToLowerInvariant(); resource = (& $vm 'vm-web01').ToLowerInvariant() })
    }
    Errors = @{}
}

@{ Now = $now; WorkspaceId = $customerId; ResourceId = $ws; Workspace = $workspace; Arm = $arm; Graph = $graph; Kql = $kql; Secret = $null }
