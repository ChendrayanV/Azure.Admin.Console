function ConvertTo-AACWorkspaceAssessment {
    <#
    .SYNOPSIS
        Turns what Invoke-AACLogAnalyticsWorkspaceAssessment read - the
        workspace from Resource Manager, its child resources, Resource Graph
        rows and KQL results - into the assessment.
    .DESCRIPTION
        No Azure calls: everything comes in as it was read, so the rules can
        be tested with made-up data.

          -Workspace   the workspace (GET .../workspaces/{name}), hashtables
          -Arm         Invoke-AACArmParallel results by name: tables,
                       dataExports, linkedServices, linkedStorageAccounts,
                       diagnosticSettings, savedSearches, activityLog
          -Kql         Invoke-AACLogQueryBatch's @{ Rows; Errors }
          -Graph       Invoke-AACGraphBatch's @{ Rows; Errors }: rules,
                       solutions, advisor, associations

        Returns a hashtable:
          Workspace         the summary (name, IDs, tier, retention, cap)
          Tables            AAC.LogAnalyticsTable, one per table with data
                            (all with -IncludeEmptyTable): billable and free
                            GB, share, daily average, plan, retention
          Settings          AAC.LogAnalyticsSetting: Category, Setting, Value
          Recommendations   AAC.LogAnalyticsRecommendation: Azure Advisor's,
                            and the assessment's own rules
          Agents            AAC.LogAnalyticsAgent: each computer's last
                            heartbeat, agent type and state
          DataCollectionRules  AAC.LogAnalyticsDataCollectionRule
          ChangeLog         AAC.LogAnalyticsChange: the activity log
          Insights          the Workspace Insights tabs: Overview, Usage,
                            Health, Agents, QueryAudit, DataCollectionRules,
                            ChangeLog - each a set of named row lists
          Notices, Errors, Stats
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Workspace,

        [System.Collections.IDictionary] $Arm = @{},

        [System.Collections.IDictionary] $Kql = @{ Rows = @{}; Errors = @{} },

        [System.Collections.IDictionary] $Graph = @{ Rows = @{}; Errors = @{} },

        [ValidateRange(1, 90)]
        [int] $Days = 30,

        [switch] $IncludeEmptyTable,

        # "Now", for the agents' state and the change log window (tests).
        [datetime] $Now = [datetime]::UtcNow
    )

    $inv = [cultureinfo]::InvariantCulture
    # A value deep in hashtables: & $get $object 'properties', 'sku', 'name'.
    $get = {
        param($Object, [string[]] $Path)
        $value = $Object
        foreach ($key in $Path) {
            if ($value -isnot [System.Collections.IDictionary] -or -not $value.Contains($key)) { return $null }
            $value = $value[$key]
        }
        $value
    }
    $number = { param($Value) if ($null -eq $Value -or "$Value" -eq '') { 0.0 } else { [double]$Value } }
    $round = { param([double] $Value, [int] $Digits = 3) [Math]::Round($Value, $Digits) }
    $date = {
        param($Value)
        if ($Value -is [datetime]) { return $Value.ToUniversalTime() }
        $parsed = [datetime]::MinValue
        if ($Value -and [datetime]::TryParse([string]$Value, $inv, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) { return $parsed }
        $null
    }
    $object = {
        param([string] $TypeName, [System.Collections.IDictionary] $Property)
        $item = [pscustomobject]$Property
        $item.PSObject.TypeNames.Insert(0, $TypeName)
        $item
    }
    $leaf = { param([string] $Id) if ($Id) { ($Id.TrimEnd('/') -split '/')[-1] } }
    $kqlRows = { param([string] $Name) @($Kql.Rows[$Name] | Where-Object { $null -ne $_ }) }
    $graphRows = { param([string] $Name) @($Graph.Rows[$Name] | Where-Object { $null -ne $_ }) }
    $armItems = {
        param([string] $Name)
        $read = $Arm[$Name]
        if (-not $read -or $read.Error) { return @() }
        if ($null -ne $read.Items) { return @($read.Items) }
        @(& $get $read.Body 'value')
    }
    $sum = { param($Items, [string] $Name) $total = 0.0; foreach ($item in @($Items)) { if ($null -ne $item) { $total += & $number $item.$Name } }; $total }
    $notices = [System.Collections.Generic.List[string]]::new()
    $errors = [ordered]@{}

    # --- The workspace -----------------------------------------------------------------------------------------
    $properties = & $get $Workspace 'properties'
    $workspaceId = [string]$Workspace['id']
    $workspaceKey = $workspaceId.ToLowerInvariant()
    $segments = $workspaceId -split '/'
    $subscriptionId = if ($segments.Count -gt 2) { $segments[2] } else { '' }
    $resourceGroup = if ($segments.Count -gt 4) { $segments[4] } else { '' }
    $skuName = [string](& $get $properties 'sku', 'name')
    $capacity = & $get $properties 'sku', 'capacityReservationLevel'
    $dailyCap = & $get $properties 'workspaceCapping', 'dailyQuotaGb'
    $hasCap = $null -ne $dailyCap -and [double]$dailyCap -ge 0
    $retention = & $get $properties 'retentionInDays'
    $features = & $get $properties 'features'
    $solutions = @(& $graphRows 'solutions')
    $hasSentinel = @($solutions | Where-Object { [string]$_['name'] -like 'SecurityInsights*' -or [string]$_['product'] -like '*SecurityInsights*' }).Count -gt 0

    $summary = [ordered]@{
        Name               = [string]$Workspace['name']
        ResourceId         = $workspaceId
        WorkspaceId        = [string](& $get $properties 'customerId')
        SubscriptionId     = $subscriptionId
        ResourceGroup      = $resourceGroup
        Location           = [string]$Workspace['location']
        PricingTier        = $skuName
        CommitmentTierGB   = $capacity
        RetentionDays      = $retention
        DailyCapGB         = $(if ($hasCap) { [double]$dailyCap })
        Sentinel           = $hasSentinel
        Days               = $Days
    }

    # --- Tables: Usage per table, merged with the table list (plan, retention) ---------------------------------
    $tableTypes = @{ Microsoft = 'Azure'; CustomLog = 'Custom'; RestoredLogs = 'Restored'; SearchResults = 'Search job' }
    $byName = [ordered]@{}
    foreach ($item in & $armItems 'tables') {
        $name = [string]$item['name']
        if ($name) { $byName[$name.ToLowerInvariant()] = @{ Name = $name; Arm = $item; Usage = $null } }
    }
    foreach ($row in & $kqlRows 'tables') {
        $name = [string]$row['Table']
        if (-not $name) { continue }
        $key = $name.ToLowerInvariant()
        if (-not $byName.Contains($key)) { $byName[$key] = @{ Name = $name; Arm = $null; Usage = $null } }
        $byName[$key].Usage = $row
    }
    $totalBillable = 0.0
    foreach ($entry in $byName.Values) { if ($entry.Usage) { $totalBillable += & $number $entry.Usage['BillableGB'] } }
    $tables = foreach ($entry in $byName.Values) {
        $tableProperties = & $get $entry.Arm 'properties'
        $billableGB = & $number (& $get $entry.Usage 'BillableGB')
        $freeGB = & $number (& $get $entry.Usage 'NonBillableGB')
        $schemaType = [string](& $get $tableProperties 'schema', 'tableType')
        $type = if ($tableTypes.Contains($schemaType)) { $tableTypes[$schemaType] } elseif ($entry.Name -like '*_CL') { 'Custom' } elseif ($entry.Name -like '*_SRCH') { 'Search job' } elseif ($entry.Name -like '*_RST') { 'Restored' } else { 'Azure' }
        $plan = [string](& $get $tableProperties 'plan')
        $interactive = & $get $tableProperties 'retentionInDays'
        $total = & $get $tableProperties 'totalRetentionInDays'
        $defaultRetention = & $get $tableProperties 'retentionInDaysAsDefault'
        $hasData = $billableGB -gt 0 -or $freeGB -gt 0
        $notDefault = ($plan -and $plan -ne 'Analytics') -or $false -eq $defaultRetention
        if (-not ($hasData -or $IncludeEmptyTable -or $type -eq 'Custom' -or $notDefault)) { continue }
        & $object 'AAC.LogAnalyticsTable' ([ordered]@{
                Table              = $entry.Name
                Billing            = $(if ($billableGB -gt 0 -and $freeGB -gt 0) { 'Both' } elseif ($billableGB -gt 0) { 'Billable' } elseif ($freeGB -gt 0) { 'Not billable' } else { 'No data' })
                BillableGB         = & $round $billableGB
                NonBillableGB      = & $round $freeGB
                TotalGB            = & $round ($billableGB + $freeGB)
                SharePercent       = $(if ($totalBillable -gt 0) { & $round ($billableGB / $totalBillable * 100) 1 } else { 0 })
                DailyAverageGB     = & $round ($billableGB / $Days)
                LastRecord         = & $date (& $get $entry.Usage 'LastRecord')
                Plan               = $(if ($plan) { $plan } else { $null })
                RetentionDays      = $interactive
                TotalRetentionDays = $total
                LongTermDays       = $(if ($null -ne $interactive -and $null -ne $total) { [int]$total - [int]$interactive })
                RetentionDefault   = $defaultRetention
                Type               = $type
                SubType            = [string](& $get $tableProperties 'schema', 'tableSubType')
                Solution           = $(if ($entry.Usage -and $entry.Usage['Solution']) { [string]$entry.Usage['Solution'] } else { @(& $get $tableProperties 'schema', 'solutions') -join ', ' })
            })
    }
    $tables = @($tables | Sort-Object -Property @{ Expression = 'TotalGB'; Descending = $true }, Table)

    # --- Daily ingestion -----------------------------------------------------------------------------------------
    $daily = @(foreach ($row in & $kqlRows 'daily') {
            & $object 'AAC.LogAnalyticsDailyIngestion' ([ordered]@{ Day = & $date $row['Day']; BillableGB = & $round (& $number $row['BillableGB']); NonBillableGB = & $round (& $number $row['NonBillableGB']) })
        })
    $dailyBillable = @($daily | ForEach-Object { $_.BillableGB })
    $averageDaily = if ($daily.Count) { & $round ((& $sum $daily 'BillableGB') / $Days) } else { & $round ($totalBillable / $Days) }
    $peak = $daily | Sort-Object -Property BillableGB -Descending | Select-AACFirst 1
    $median = if ($dailyBillable.Count) { @($dailyBillable | Sort-Object)[[int][Math]::Floor($dailyBillable.Count / 2)] } else { 0 }

    # --- Agents ----------------------------------------------------------------------------------------------------
    $agentTypes = @{ 'Azure Monitor Agent' = 'Azure Monitor Agent'; 'Direct Agent' = 'Log Analytics agent (MMA)'; 'SCOM Agent' = 'SCOM agent'; 'SCOM Management Server' = 'SCOM management server' }
    $agents = @(foreach ($row in & $kqlRows 'agents') {
            $last = & $date $row['LastHeartbeat']
            $minutes = if ($last) { [int][Math]::Round(($Now - $last).TotalMinutes) } else { $null }
            $category = [string]$row['Category']
            & $object 'AAC.LogAnalyticsAgent' ([ordered]@{
                    Computer        = [string]$row['Computer']
                    State           = $(if ($null -eq $minutes) { 'Unknown' } elseif ($minutes -le 15) { 'Healthy' } elseif ($minutes -le 1440) { 'Unhealthy' } else { 'Not reporting' })
                    LastHeartbeat   = $last
                    MinutesSince    = $minutes
                    AgentType       = $(if ($agentTypes.Contains($category)) { $agentTypes[$category] } else { $category })
                    Version         = [string]$row['Version']
                    OSType          = [string]$row['OSType']
                    OSName          = [string]$row['OSName']
                    Environment     = [string]$row['ComputerEnvironment']
                    ResourceId      = [string]$row['ResourceId']
                })
        })

    # --- Data collection rules -----------------------------------------------------------------------------------
    $associations = @(& $graphRows 'associations')
    $transformRule = [string](& $get $properties 'defaultDataCollectionRuleResourceId')
    $rules = @(foreach ($row in & $graphRows 'rules') {
            $ruleProperties = $row['properties']
            $ruleId = ([string]$row['id']).ToLowerInvariant()
            $sources = & $get $ruleProperties 'dataSources'
            $sourceText = @(if ($sources -is [System.Collections.IDictionary]) {
                    foreach ($key in @($sources.Keys | Sort-Object)) { $count = @($sources[$key]).Count; if ($count) { "$key ($count)" } }
                })
            $flows = @(& $get $ruleProperties 'dataFlows')
            $streams = @($flows | ForEach-Object { @($_['streams']) } | Where-Object { $_ } | Select-Object -Unique)
            $outputs = @($flows | ForEach-Object { $_['outputStream'] } | Where-Object { $_ } | Select-Object -Unique)
            $transformed = @($flows | Where-Object { $_['transformKql'] -and $_['transformKql'] -ne 'source' }).Count
            $destinations = @(& $get $ruleProperties 'destinations', 'logAnalytics' | Where-Object { $null -ne $_ } | Where-Object { ([string]$_['workspaceResourceId']).ToLowerInvariant() -eq $workspaceKey } | ForEach-Object { $_['name'] })
            $linked = @($associations | Where-Object { [string]$_['rule'] -eq $ruleId })
            & $object 'AAC.LogAnalyticsDataCollectionRule' ([ordered]@{
                    Name                = [string]$row['name']
                    Kind                = $(if ($row['kind']) { [string]$row['kind'] } else { '(any)' })
                    ResourceGroup       = [string]$row['resourceGroup']
                    Location            = [string]$row['location']
                    WorkspaceTransform  = $ruleId -eq $transformRule.ToLowerInvariant() -or [string]$row['kind'] -eq 'WorkspaceTransforms'
                    DataSources         = $sourceText -join ', '
                    Streams             = $streams -join ', '
                    OutputTables        = $outputs -join ', '
                    Transformations     = $transformed
                    Destinations        = $destinations -join ', '
                    Endpoint            = & $leaf ([string](& $get $ruleProperties 'dataCollectionEndpointId'))
                    Associations        = $linked.Count
                    AssociatedResources = @($linked | ForEach-Object { & $leaf ([string]$_['resource']) } | Sort-Object -Unique) -join ', '
                    Description         = [string](& $get $ruleProperties 'description')
                    ResourceId          = [string]$row['id']
                })
        })

    # --- Change log (activity log) -------------------------------------------------------------------------------
    $changes = @(foreach ($event in & $armItems 'activityLog') {
            $resource = [string](& $get $event 'resourceId')
            if (-not $resource.ToLowerInvariant().StartsWith($workspaceKey)) { continue }
            $status = [string](& $get $event 'status', 'value')
            if ($status -in 'Started', 'Accepted') { continue }
            $relative = $resource.Substring([Math]::Min($workspaceId.Length, $resource.Length)).TrimStart('/')
            & $object 'AAC.LogAnalyticsChange' ([ordered]@{
                    Time      = & $date (& $get $event 'eventTimestamp')
                    Operation = $(if (& $get $event 'operationName', 'localizedValue') { [string](& $get $event 'operationName', 'localizedValue') } else { [string](& $get $event 'operationName', 'value') })
                    Status    = $status
                    Caller    = [string](& $get $event 'caller')
                    Resource  = $(if ($relative) { $relative } else { '(workspace)' })
                    Level     = [string](& $get $event 'level')
                    Detail    = [string](& $get $event 'subStatus', 'localizedValue')
                    Action    = [string](& $get $event 'operationName', 'value')
                })
        })
    $changes = @($changes | Sort-Object -Property Time -Descending)

    # --- Settings ------------------------------------------------------------------------------------------------
    $settings = [System.Collections.Generic.List[object]]::new()
    $covered = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $setting = {
        param([string] $Category, [string] $Name, $Value, [string] $Source)
        if ($Source) { $null = $covered.Add($Source) }
        $text = if ($null -eq $Value -or "$Value" -eq '') { '-' } elseif ($Value -is [bool]) { $(if ($Value) { 'Yes' } else { 'No' }) } elseif ($Value -is [System.Collections.IDictionary] -or ($Value -is [System.Collections.IList] -and $Value -isnot [string])) { ConvertTo-Json -InputObject $Value -Depth 6 -Compress } else { [string]$Value }
        $settings.Add((& $object 'AAC.LogAnalyticsSetting' ([ordered]@{ Category = $Category; Setting = $Name; Value = $text })))
    }
    & $setting 'General' 'Name' $summary.Name
    & $setting 'General' 'Resource ID' $workspaceId
    & $setting 'General' 'Workspace ID' $summary.WorkspaceId 'customerId'
    & $setting 'General' 'Location' $summary.Location
    & $setting 'General' 'Resource group' $resourceGroup
    & $setting 'General' 'Subscription' $subscriptionId
    & $setting 'General' 'Created' (& $get $properties 'createdDate') 'createdDate'
    & $setting 'General' 'Modified' (& $get $properties 'modifiedDate') 'modifiedDate'
    & $setting 'General' 'Provisioning state' (& $get $properties 'provisioningState') 'provisioningState'
    $tags = & $get $Workspace 'tags'
    & $setting 'General' 'Tags' $(if ($tags -is [System.Collections.IDictionary] -and $tags.Count) { @($tags.Keys | Sort-Object | ForEach-Object { "$_=$($tags[$_])" }) -join '; ' })
    & $setting 'Pricing' 'Pricing tier' $skuName 'sku'
    & $setting 'Pricing' 'Commitment tier (GB/day)' $capacity
    & $setting 'Pricing' 'Pricing tier changed' (& $get $properties 'sku', 'lastSkuUpdate')
    & $setting 'Pricing' 'Daily cap (GB)' $(if ($hasCap) { $dailyCap } else { 'None' }) 'workspaceCapping'
    & $setting 'Pricing' 'Daily cap resets at (UTC)' (& $get $properties 'workspaceCapping', 'quotaNextResetTime')
    & $setting 'Pricing' 'Data ingestion status' (& $get $properties 'workspaceCapping', 'dataIngestionStatus')
    & $setting 'Pricing' 'Dedicated cluster' (& $leaf ([string](& $get $features 'clusterResourceId')))
    & $setting 'Retention' 'Retention (days)' $retention 'retentionInDays'
    & $setting 'Retention' 'Purge data after 30 days (Free tier)' (& $get $features 'immediatePurgeDataOn30Days')
    & $setting 'Access' 'Access control mode' $(if (& $get $features 'enableLogAccessUsingOnlyResourcePermissions') { 'Resource or workspace permissions' } else { 'Workspace permissions only' })
    & $setting 'Access' 'Local authentication (shared keys)' $(if (& $get $features 'disableLocalAuth') { 'Disabled' } else { 'Enabled' })
    & $setting 'Access' 'Public network access for ingestion' (& $get $properties 'publicNetworkAccessForIngestion') 'publicNetworkAccessForIngestion'
    & $setting 'Access' 'Public network access for queries' (& $get $properties 'publicNetworkAccessForQuery') 'publicNetworkAccessForQuery'
    & $setting 'Access' 'Customer-managed key required for queries' (& $get $properties 'forceCmkForQuery') 'forceCmkForQuery'
    & $setting 'Access' 'Private link scopes' (@(& $get $properties 'privateLinkScopedResources' | Where-Object { $null -ne $_ } | ForEach-Object { & $leaf ([string]$_['scopeId']) }) -join ', ') 'privateLinkScopedResources'
    & $setting 'Data collection' 'Workspace transformation DCR' (& $leaf $transformRule) 'defaultDataCollectionRuleResourceId'
    & $setting 'Data collection' 'Data collection rules sending here' $rules.Count
    & $setting 'Data collection' 'Solutions' (@($solutions | ForEach-Object { [string]$_['name'] } | Sort-Object) -join ', ')
    $saved = $Arm['savedSearches']
    if ($saved -and -not $saved.Error) { & $setting 'Data collection' 'Saved searches and functions' (& $armItems 'savedSearches').Count }
    foreach ($export in & $armItems 'dataExports') {
        $exportProperties = $export['properties']
        & $setting 'Data export' ([string]$export['name']) ("$(if ($exportProperties['enable']) { 'Enabled' } else { 'Disabled' }) - $(@($exportProperties['tableNames']).Count) table(s) to $(& $leaf ([string](& $get $exportProperties 'destination', 'resourceId')))")
    }
    foreach ($service in & $armItems 'linkedServices') {
        $serviceProperties = $service['properties']
        & $setting 'Linked services' ([string]$service['name']) (& $leaf ([string]$(if ($serviceProperties['resourceId']) { $serviceProperties['resourceId'] } else { $serviceProperties['writeAccessResourceId'] })))
    }
    foreach ($storage in & $armItems 'linkedStorageAccounts') {
        & $setting 'Linked storage' ([string]$storage['name']) (@(& $get $storage 'properties', 'storageAccountIds' | Where-Object { $null -ne $_ } | ForEach-Object { & $leaf ([string]$_) }) -join ', ')
    }
    $diagnostics = @(& $armItems 'diagnosticSettings')
    foreach ($diagnostic in $diagnostics) {
        $diagnosticProperties = $diagnostic['properties']
        $where = @(foreach ($pair in @(@('workspaceId', 'workspace'), @('storageAccountId', 'storage'), @('eventHubAuthorizationRuleId', 'event hub'), @('marketplacePartnerId', 'partner'))) { $target = [string]$diagnosticProperties[$pair[0]]; if ($target) { "$($pair[1]) $(& $leaf $(if ($pair[0] -eq 'eventHubAuthorizationRuleId') { $target -replace '/authorizationrules/.*$', '' } else { $target }))" } })
        $categories = @(@($diagnosticProperties['logs']) | Where-Object { $_ -and $_['enabled'] } | ForEach-Object { if ($_['category']) { $_['category'] } else { $_['categoryGroup'] } })
        & $setting 'Diagnostic settings' ([string]$diagnostic['name']) ("$($categories -join ', ') to $($where -join ', ')")
    }
    if (-not $diagnostics.Count -and $Arm.Contains('diagnosticSettings') -and -not $Arm['diagnosticSettings'].Error) { & $setting 'Diagnostic settings' '(none)' 'No diagnostic settings: the workspace''s own audit and health logs aren''t kept.' }
    # Whatever else the workspace has: nothing left out.
    foreach ($key in @(if ($properties -is [System.Collections.IDictionary]) { $properties.Keys | Sort-Object })) {
        if ($covered.Contains($key)) { continue }
        $value = $properties[$key]
        if ($value -is [System.Collections.IDictionary]) {
            foreach ($inner in @($value.Keys | Sort-Object)) {
                if ($key -eq 'features' -and $inner -in 'enableLogAccessUsingOnlyResourcePermissions', 'disableLocalAuth', 'immediatePurgeDataOn30Days', 'clusterResourceId') { continue }
                & $setting 'Other' "$key.$inner" $value[$inner]
            }
        }
        elseif ($key -notin 'sku', 'retentionInDays', 'features', 'defaultDataCollectionRuleResourceId') { & $setting 'Other' $key $value }
    }

    # --- Errors and notices from what couldn't be read ------------------------------------------------------------
    $missingTable = { param([string] $Message, [string] $Table) $Message -match "(?i)(resolve|could not be found|semantic).*$Table|$Table.*(resolve|could not be found|semantic)" }
    foreach ($name in @($Kql.Errors.Keys)) {
        $message = [string]$Kql.Errors[$name]
        if ($name -like 'audit*' -and (& $missingTable $message 'LAQueryLogs')) { continue }
        if ($name -in 'agents', 'latency' -and (& $missingTable $message 'Heartbeat')) { continue }
        $errors["kql:$name"] = $message
    }
    foreach ($name in @($Graph.Errors.Keys)) { $errors["graph:$name"] = [string]$Graph.Errors[$name] }
    foreach ($name in @($Arm.Keys)) { if ($Arm[$name].Error -and $Arm[$name].Status -ne 404) { $errors["arm:$name"] = [string]$Arm[$name].Error } }
    $auditOff = $Kql.Errors.Contains('auditUsers') -and (& $missingTable ([string]$Kql.Errors['auditUsers']) 'LAQueryLogs')
    if ($auditOff) { $notices.Add('Query auditing is off: the workspace has no LAQueryLogs table. A diagnostic setting on the workspace that sends the Audit category to a workspace turns it on.') }
    if ($Kql.Rows.Contains('agents') -and -not $agents.Count) { $notices.Add("No agent sent a heartbeat to this workspace in the last $Days day(s).") }

    # --- Health: _LogOperation ------------------------------------------------------------------------------------
    $operations = @(foreach ($row in & $kqlRows 'operations') {
            & $object 'AAC.LogAnalyticsOperation' ([ordered]@{
                    Level = [string]$row['Level']; Category = [string]$row['Category']; Operation = [string]$row['Operation']; Count = [int](& $number $row['Count'])
                    FirstSeen = & $date $row['FirstSeen']; LastSeen = & $date $row['LastSeen']; Detail = [string]$row['Detail']
                })
        })
    $operationErrors = @($operations | Where-Object Level -EQ 'Error')
    $operationWarnings = @($operations | Where-Object Level -EQ 'Warning')

    # --- Recommendations --------------------------------------------------------------------------------------------
    $recommendations = [System.Collections.Generic.List[object]]::new()
    $recommend = {
        param([string] $Severity, [string] $Category, [string] $Title, [string] $Detail, [string] $Action, [string] $LearnMore, [string] $Source = 'Assessment')
        $recommendations.Add((& $object 'AAC.LogAnalyticsRecommendation' ([ordered]@{ Severity = $Severity; Category = $Category; Recommendation = $Title; Detail = $Detail; Action = $Action; Source = $Source; LearnMore = $LearnMore })))
    }
    $severityOf = @{ High = 'High'; Medium = 'Medium'; Low = 'Low' }
    $advisorCategory = @{ Cost = 'Cost'; Security = 'Security'; HighAvailability = 'Reliability'; OperationalExcellence = 'Operational excellence'; Performance = 'Performance' }
    foreach ($row in & $graphRows 'advisor') {
        $category = [string]$row['category']
        & $recommend $(if ($severityOf.Contains([string]$row['impact'])) { $severityOf[[string]$row['impact']] } else { 'Low' }) $(if ($advisorCategory.Contains($category)) { $advisorCategory[$category] } else { $category }) ([string]$row['problem']) '' ([string]$row['solution']) ([string]$row['learnMore']) 'Azure Advisor'
    }
    $gb = { param([double] $Value) if ($Value -ge 100) { '{0:N0} GB' -f $Value } elseif ($Value -ge 1) { '{0:N1} GB' -f $Value } else { '{0:N2} GB' -f $Value } }
    $docs = 'https://learn.microsoft.com/azure/azure-monitor/logs'

    # Pricing
    $legacyTiers = 'Free', 'Standalone', 'PerNode', 'Standard', 'Premium'
    if ($skuName -in $legacyTiers) {
        & $recommend 'Medium' 'Cost' "Legacy pricing tier ($skuName)" "The $skuName tier is a legacy tier$(if ($skuName -eq 'Free') { ' with a 500 MB daily limit and 7-day retention' })." 'Move to Pay-As-You-Go (PerGB2018) or a commitment tier.' "$docs/cost-logs#legacy-pricing-tiers"
    }
    if ($skuName -eq 'PerGB2018' -and $averageDaily -ge 100) {
        & $recommend 'Medium' 'Cost' 'A commitment tier would cost less' "Billable ingestion averages $(& $gb $averageDaily) a day over $Days day(s), at Pay-As-You-Go prices." "Compare the 100 GB/day (or higher) commitment tier on the workspace's Usage and estimated costs page." "$docs/cost-logs#commitment-tiers"
    }
    if ($skuName -eq 'CapacityReservation' -and $capacity -and $averageDaily -gt 0 -and $averageDaily -lt 0.8 * [double]$capacity) {
        & $recommend 'Medium' 'Cost' 'Commitment tier above what is ingested' "The $capacity GB/day commitment tier is billed in full, but billable ingestion averages $(& $gb $averageDaily) a day." 'Move to a lower commitment tier or Pay-As-You-Go (a tier can be lowered 31 days after it was last changed).' "$docs/cost-logs#commitment-tiers"
    }
    # Daily cap
    $capHit = @($operations | Where-Object { "$($_.Operation) $($_.Detail)" -match '(?i)daily (cap|quota|limit)|OverQuota|data collection stopped' })
    if ($capHit.Count) {
        & $recommend 'High' 'Reliability' 'The daily cap stopped data collection' "_LogOperation reports the daily cap $($capHit[0].Count) time(s), last at $(if ($capHit[0].LastSeen) { $capHit[0].LastSeen.ToString('yyyy-MM-dd HH:mm', $inv) + ' UTC' } else { 'an unknown time' }): data sent after it was dropped." 'Raise the daily cap, or cut the ingestion that reaches it (see the largest tables).' "$docs/daily-cap"
    }
    elseif ($hasCap -and $averageDaily -gt 0.8 * [double]$dailyCap) {
        & $recommend 'Medium' 'Reliability' 'Ingestion is close to the daily cap' "Billable ingestion averages $(& $gb $averageDaily) a day against a $dailyCap GB cap$(if ($peak) { "; the busiest day was $(& $gb $peak.BillableGB)" })." 'Raise the cap or reduce ingestion before data is dropped.' "$docs/daily-cap"
    }
    elseif (-not $hasCap -and $skuName -notin $legacyTiers) {
        & $recommend 'Low' 'Cost' 'No daily cap' 'Nothing limits how much the workspace ingests (and costs) in a day.' 'A daily cap is a safety net for unexpected spikes, not a way to cut costs: data over it is dropped. Set an alert on ingestion instead, or a cap well above the normal daily volume.' "$docs/daily-cap"
    }
    # Spikes
    if ($peak -and $median -gt 0 -and $peak.BillableGB -gt 2 * $median -and $peak.BillableGB -ge 1) {
        & $recommend 'Low' 'Cost' 'Ingestion spike' ("{0:yyyy-MM-dd} ingested {1}, more than twice the median day ({2})." -f $peak.Day, (& $gb $peak.BillableGB), (& $gb $median)) 'Find what grew that day in the Usage tab (tables, resources, computers).' "$docs/analyze-usage"
    }
    # Retention
    $freeRetention = if ($hasSentinel) { 90 } else { 31 }
    if ($retention -and [int]$retention -gt $freeRetention) {
        & $recommend 'Low' 'Cost' "Interactive retention of $retention days" "Interactive retention beyond $freeRetention days is billed for every table on it$(if ($hasSentinel) { ' (90 days are free with Microsoft Sentinel)' })." 'Keep the default short and set longer interactive retention only on the tables that need it; use long-term retention for data kept only for compliance.' "$docs/data-retention-configure"
    }
    # Tables: plans, legacy tables, AzureDiagnostics, unused custom tables
    $basicCandidates = 'ContainerLogV2', 'AppTraces', 'StorageBlobLogs', 'StorageFileLogs', 'StorageQueueLogs', 'StorageTableLogs', 'AACAudit', 'AACHttpRequest'
    $big = @($tables | Where-Object { $_.Plan -in $null, '', 'Analytics' -and $_.BillableGB -gt 0 -and $_.SharePercent -ge 5 -and ($_.Table -in $basicCandidates -or ($_.Type -eq 'Custom' -and $_.SubType -eq 'DataCollectionRuleBased')) })
    foreach ($table in $big) {
        & $recommend 'Medium' 'Cost' "$($table.Table) could use the Basic or Auxiliary plan" "$($table.Table) is $($table.SharePercent)% of billable ingestion ($(& $gb $table.BillableGB) in $Days day(s)) on the Analytics plan." 'If it is used for troubleshooting rather than alerts and dashboards, switch it to the Basic (or Auxiliary) plan: ingestion costs much less, queries are charged.' "$docs/logs-table-plans"
    }
    $legacyContainer = $tables | Where-Object { $_.Table -eq 'ContainerLog' -and $_.TotalGB -gt 0 } | Select-AACFirst 1
    if ($legacyContainer) {
        & $recommend 'Medium' 'Cost' 'ContainerLog is still in use' "Container insights sent $(& $gb $legacyContainer.TotalGB) to the legacy ContainerLog table." 'Move to ContainerLogV2: a smaller schema, and it supports the Basic plan.' 'https://learn.microsoft.com/azure/azure-monitor/containers/container-insights-logs-schema'
    }
    $diagnosticsTable = $tables | Where-Object { $_.Table -eq 'AzureDiagnostics' -and $_.SharePercent -ge 10 } | Select-AACFirst 1
    if ($diagnosticsTable) {
        & $recommend 'Low' 'Operational excellence' 'AzureDiagnostics is a large share of ingestion' "AzureDiagnostics is $($diagnosticsTable.SharePercent)% of billable ingestion." 'Switch diagnostic settings to resource-specific mode where the service supports it: smaller rows, separate tables, per-table plans and retention.' 'https://learn.microsoft.com/azure/azure-monitor/essentials/resource-logs#resource-specific'
    }
    $unused = @($tables | Where-Object { $_.Type -eq 'Custom' -and $_.TotalGB -eq 0 })
    if ($unused.Count) {
        & $recommend 'Low' 'Operational excellence' "$($unused.Count) custom table(s) with no data" "No data in $Days day(s): $(@($unused | Select-AACFirst 15 | ForEach-Object Table) -join ', ')$(if ($unused.Count -gt 15) { ', ...' })." 'Delete the custom tables nothing sends to any more.' "$docs/create-custom-table"
    }
    # Agents
    $mma = @($agents | Where-Object AgentType -EQ 'Log Analytics agent (MMA)')
    if ($mma.Count) {
        & $recommend 'High' 'Reliability' "$($mma.Count) computer(s) still use the retired Log Analytics agent" "The Log Analytics agent (MMA/OMS) was retired on 31 August 2024 and is no longer supported: $(@($mma | Select-AACFirst 10 | ForEach-Object Computer) -join ', ')$(if ($mma.Count -gt 10) { ', ...' })." 'Migrate them to the Azure Monitor Agent with data collection rules.' 'https://learn.microsoft.com/azure/azure-monitor/agents/azure-monitor-agent-migration'
    }
    $silent = @($agents | Where-Object State -In 'Unhealthy', 'Not reporting')
    if ($silent.Count) {
        & $recommend 'Medium' 'Reliability' "$($silent.Count) agent(s) stopped sending heartbeats" "No heartbeat for over 15 minutes: $(@($silent | Sort-Object MinutesSince | Select-AACFirst 10 | ForEach-Object { "$($_.Computer) ($($_.State.ToLowerInvariant()))" }) -join ', ')$(if ($silent.Count -gt 10) { ', ...' })." 'Check that the computers are running and the agent is healthy; remove the ones that are gone.' 'https://learn.microsoft.com/azure/azure-monitor/agents/azure-monitor-agent-troubleshoot-windows-vm'
    }
    # Health
    if ($operationErrors.Count -and -not $capHit.Count) {
        $top = $operationErrors | Select-AACFirst 3
        & $recommend 'Medium' 'Reliability' "$(& $sum $operationErrors 'Count') error(s) in the workspace's operations" "Recent errors: $(@($top | ForEach-Object { "$($_.Operation) ($($_.Count)x)" }) -join '; ')." 'See the Health tab for the details of each.' "$docs/monitor-workspace"
    }
    # Data collection rules
    $orphans = @($rules | Where-Object { -not $_.WorkspaceTransform -and $_.Associations -eq 0 -and $_.Kind -notin 'Direct', 'AgentDirectToStore', 'WorkspaceTransforms' -and $_.DataSources })
    if ($orphans.Count -and $Graph.Rows.Contains('associations')) {
        & $recommend 'Low' 'Operational excellence' "$($orphans.Count) data collection rule(s) with no associations" "They collect from no computer: $(@($orphans | ForEach-Object Name) -join ', ')." 'Associate them with the computers they are for, or delete them.' 'https://learn.microsoft.com/azure/azure-monitor/essentials/data-collection-rule-overview'
    }
    # Security and access
    if (-not (& $get $features 'disableLocalAuth')) {
        & $recommend 'Medium' 'Security' 'Shared keys (local authentication) are enabled' 'Anyone with the workspace key can send data to it; the key never expires on its own.' 'Move ingestion to the Azure Monitor Agent and the Logs Ingestion API (Microsoft Entra ID), then disable local authentication.' "$docs/azure-ad-authentication-logs"
    }
    if ([string](& $get $properties 'publicNetworkAccessForIngestion') -eq 'Enabled' -and [string](& $get $properties 'publicNetworkAccessForQuery') -eq 'Enabled' -and -not @(& $get $properties 'privateLinkScopedResources' | Where-Object { $null -ne $_ }).Count) {
        & $recommend 'Low' 'Security' 'Open to ingestion and queries from any network' 'The workspace has no Azure Monitor Private Link Scope and accepts public ingestion and queries.' 'Where the data is sensitive, connect it to an Azure Monitor Private Link Scope and limit public access.' 'https://learn.microsoft.com/azure/azure-monitor/logs/private-link-security'
    }
    if (-not (& $get $features 'enableLogAccessUsingOnlyResourcePermissions')) {
        & $recommend 'Low' 'Security' 'Access needs workspace permissions' 'Users can''t read the logs of resources they have access to without a role on the whole workspace.' 'Set the access control mode to "Use resource or workspace permissions".' "$docs/manage-access#access-control-mode"
    }
    if ($auditOff) {
        & $recommend 'Low' 'Security' 'Query auditing is off' 'There is no record of who queried the workspace, what, or how heavily.' 'Add a diagnostic setting on the workspace that sends the Audit category to a workspace (LAQueryLogs).' "$docs/query-audit"
    }
    if ($Arm.Contains('diagnosticSettings') -and -not $Arm['diagnosticSettings'].Error -and -not $diagnostics.Count) {
        & $recommend 'Low' 'Operational excellence' 'No diagnostic settings on the workspace' 'The workspace''s audit (LAQueryLogs) and summary logs aren''t collected.' 'Add a diagnostic setting for the Audit and SummaryLogs categories.' "$docs/monitor-workspace"
    }
    $order = @{ High = 0; Medium = 1; Low = 2 }
    $sortedRecommendations = @($recommendations | Sort-Object -Property @{ Expression = { $order[$_.Severity] ?? 3 } }, Category, Recommendation)

    # --- Insights: the Workspace Insights tabs ---------------------------------------------------------------------------
    $agentTypeRows = @($agents | Group-Object AgentType | Sort-Object Count -Descending | ForEach-Object {
            [pscustomobject][ordered]@{ AgentType = $_.Name; Computers = $_.Count; Healthy = @($_.Group | Where-Object State -EQ 'Healthy').Count; Unhealthy = @($_.Group | Where-Object State -EQ 'Unhealthy').Count; NotReporting = @($_.Group | Where-Object State -EQ 'Not reporting').Count }
        })
    $stats = [ordered]@{
        BillableGB          = & $round $totalBillable
        NonBillableGB       = & $round (& $sum $tables 'NonBillableGB')
        AverageDailyGB      = $averageDaily
        PeakDay             = $(if ($peak) { $peak.Day })
        PeakDayGB           = $(if ($peak) { $peak.BillableGB })
        TablesWithData      = @($tables | Where-Object TotalGB -GT 0).Count
        BillableTables      = @($tables | Where-Object Billing -In 'Billable', 'Both').Count
        NonBillableTables   = @($tables | Where-Object Billing -EQ 'Not billable').Count
        Agents              = $agents.Count
        HealthyAgents       = @($agents | Where-Object State -EQ 'Healthy').Count
        UnhealthyAgents     = $silent.Count
        DataCollectionRules = $rules.Count
        OperationErrors     = [int](& $sum $operationErrors 'Count')
        OperationWarnings   = [int](& $sum $operationWarnings 'Count')
        Changes             = $changes.Count
        High                = @($sortedRecommendations | Where-Object Severity -EQ 'High').Count
        Medium              = @($sortedRecommendations | Where-Object Severity -EQ 'Medium').Count
        Low                 = @($sortedRecommendations | Where-Object Severity -EQ 'Low').Count
    }
    $metric = { param([string] $Name, $Value) [pscustomobject][ordered]@{ Metric = $Name; Value = $Value } }
    $insights = [ordered]@{
        Overview            = [ordered]@{
            Summary = @(
                & $metric 'Pricing tier' $(if ($capacity) { "$skuName ($capacity GB/day)" } else { $skuName })
                & $metric "Billable data ($Days days)" (& $gb $stats.BillableGB)
                & $metric "Free data ($Days days)" (& $gb $stats.NonBillableGB)
                & $metric 'Billable per day (average)' (& $gb $averageDaily)
                & $metric 'Busiest day' $(if ($peak) { '{0:yyyy-MM-dd}: {1}' -f $peak.Day, (& $gb $peak.BillableGB) } else { '-' })
                & $metric 'Retention' $(if ($retention) { "$retention days" } else { '-' })
                & $metric 'Daily cap' $(if ($hasCap) { "$dailyCap GB" } else { 'None' })
                & $metric 'Tables with data' $stats.TablesWithData
                & $metric 'Agents (healthy)' "$($stats.Agents) ($($stats.HealthyAgents))"
                & $metric 'Data collection rules' $stats.DataCollectionRules
                & $metric "Operation errors / warnings ($Days days)" "$($stats.OperationErrors) / $($stats.OperationWarnings)"
                & $metric 'Recommendations (high / medium / low)' "$($stats.High) / $($stats.Medium) / $($stats.Low)"
            )
            TopTables = @($tables | Where-Object BillableGB -GT 0 | Sort-Object BillableGB -Descending | Select-AACFirst 10)
        }
        Usage               = [ordered]@{
            Daily     = $daily
            Tables    = @($tables | Where-Object TotalGB -GT 0)
            Solutions = @(foreach ($row in & $kqlRows 'solutions') { [pscustomobject][ordered]@{ Solution = [string]$row['Solution']; BillableGB = & $round (& $number $row['BillableGB']); NonBillableGB = & $round (& $number $row['NonBillableGB']) } })
            Resources = @(foreach ($row in & $kqlRows 'resources') { $id = [string]$row['ResourceId']; [pscustomobject][ordered]@{ Resource = $(if ($id) { & $leaf $id } else { '(no resource)' }); BillableGB = & $round (& $number $row['BillableGB']); ResourceId = $id } })
            Computers = @(foreach ($row in & $kqlRows 'computers') { [pscustomobject][ordered]@{ Computer = [string]$row['Computer']; BillableGB = & $round (& $number $row['BillableGB']) } })
        }
        Health              = [ordered]@{
            Operations = $operations
            Latency    = @(foreach ($row in & $kqlRows 'latency') { [pscustomobject][ordered]@{ AgentType = $(if ($agentTypes.Contains([string]$row['Category'])) { $agentTypes[[string]$row['Category']] } else { [string]$row['Category'] }); Records = [int](& $number $row['Records']); P50Seconds = & $number $row['P50Seconds']; P95Seconds = & $number $row['P95Seconds']; MaxSeconds = & $number $row['MaxSeconds'] } })
        }
        Agents              = [ordered]@{ ByType = $agentTypeRows; Computers = $agents }
        QueryAudit          = [ordered]@{
            Users   = @(foreach ($row in & $kqlRows 'auditUsers') { [pscustomobject][ordered]@{ User = [string]$row['User']; ClientApp = [string]$row['ClientApp']; Queries = [int](& $number $row['Queries']); Failed = [int](& $number $row['Failed']); AvgDurationMs = & $number $row['AvgDurationMs']; MaxDurationMs = & $number $row['MaxDurationMs']; CpuSeconds = & $number $row['CpuSeconds']; RowsReturned = & $number $row['RowsReturned'] } })
            Slowest = @(foreach ($row in & $kqlRows 'auditSlowest') { [pscustomobject][ordered]@{ Time = & $date $row['TimeGenerated']; User = [string]$row['User']; ClientApp = [string]$row['ClientApp']; ResponseCode = $row['ResponseCode']; DurationMs = & $number $row['DurationMs']; CpuMs = & $number $row['CpuMs']; Query = [string]$row['Query'] } })
            Failed  = @(foreach ($row in & $kqlRows 'auditFailed') { [pscustomobject][ordered]@{ ResponseCode = $row['ResponseCode']; User = [string]$row['User']; ClientApp = [string]$row['ClientApp']; Count = [int](& $number $row['Count']); LastSeen = & $date $row['LastSeen'] } })
        }
        DataCollectionRules = [ordered]@{ Rules = $rules; Associations = @(foreach ($row in $associations) { [pscustomobject][ordered]@{ Rule = & $leaf ([string]$row['rule']); Resource = & $leaf ([string]$row['resource']); ResourceId = [string]$row['resource'] } }) }
        ChangeLog           = [ordered]@{ Changes = $changes }
    }

    @{
        Workspace           = [pscustomobject]$summary
        Tables              = $tables
        Settings            = $settings.ToArray()
        Recommendations     = $sortedRecommendations
        Agents              = $agents
        DataCollectionRules = $rules
        ChangeLog           = $changes
        Insights            = $insights
        Notices             = $notices.ToArray()
        Errors              = $errors
        Stats               = $stats
    }
}
