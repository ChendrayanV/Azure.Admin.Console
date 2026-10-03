function Get-AACWorkspaceAssessmentQuery {
    <#
    .SYNOPSIS
        The KQL and Azure Resource Graph queries behind
        Invoke-AACLogAnalyticsWorkspaceAssessment, by section.
    .DESCRIPTION
        -Kind Kql returns the queries run in the workspace (Invoke-AACLogQueryBatch),
        for the sections asked for:

          tables          Tables, Overview   Usage per table over -Days:
                                             billable and not, last record
          daily           Usage, Overview    billable and free GB per day
          solutions       Usage              billable GB per solution
          resources       Usage              billable GB per Azure resource,
                                             last 24 hours (find)
          computers       Usage              billable GB per computer, last
                                             24 hours (find)
          operations      Health             _LogOperation: errors, warnings
                                             and information, grouped
          latency         Health             heartbeat ingestion latency,
                                             last 24 hours
          agents          Agents             each computer's last heartbeat
          auditUsers      QueryAudit         LAQueryLogs per user and app
          auditSlowest    QueryAudit         the slowest queries
          auditFailed     QueryAudit         failed queries, by code

        Usage's Quantity is in MB (10^6 bytes) and _BilledSize in bytes;
        both are turned into GB (10^9 bytes), as Azure bills them.

        -Kind Graph returns the Resource Graph queries for -WorkspaceResourceId:
        rules (DCRs sending to it), solutions and advisor (its Azure Advisor
        recommendations); -Kind Association the DCR associations of
        -RuleId.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Kql', 'Graph', 'Association')]
        [string] $Kind,

        [string[]] $Section = @('Tables', 'Overview', 'Usage', 'Health', 'Agents', 'QueryAudit', 'DataCollectionRules', 'Recommendations'),

        [ValidateRange(1, 90)]
        [int] $Days = 30,

        [string] $WorkspaceResourceId,

        [string[]] $RuleId
    )

    $quote = { param([string] $Text) "'" + ($Text.ToLowerInvariant() -replace '\\', '\\' -replace "'", "\'") + "'" }
    $queries = [ordered]@{}
    $want = { param([string[]] $Name) @($Name | Where-Object { $Section -contains $_ }).Count -gt 0 }
    $billable = "tostring(IsBillable) =~ 'true'"

    if ($Kind -eq 'Kql') {
        if (& $want 'Tables', 'Overview', 'Recommendations') {
            $queries['tables'] = @"
Usage
| where TimeGenerated > ago($($Days)d)
| summarize BillableGB = sumif(Quantity, $billable) / 1000., NonBillableGB = sumif(Quantity, not($billable)) / 1000., LastRecord = max(TimeGenerated), Solution = take_any(Solution) by Table = DataType
"@
        }
        if (& $want 'Usage', 'Overview', 'Recommendations') {
            $queries['daily'] = @"
Usage
| where TimeGenerated > ago($($Days)d)
| summarize BillableGB = sumif(Quantity, $billable) / 1000., NonBillableGB = sumif(Quantity, not($billable)) / 1000. by Day = startofday(TimeGenerated)
| order by Day asc
"@
        }
        if (& $want 'Usage') {
            $queries['solutions'] = @"
Usage
| where TimeGenerated > ago($($Days)d)
| summarize BillableGB = sumif(Quantity, $billable) / 1000., NonBillableGB = sumif(Quantity, not($billable)) / 1000. by Solution
| order by BillableGB desc
"@
            $queries['resources'] = @{ Timespan = 'P1D'; Query = @'
find where TimeGenerated > ago(24h) project _ResourceId, _BilledSize, _IsBillable
| where _IsBillable == true
| summarize BillableGB = sum(_BilledSize) / 1e9 by ResourceId = tolower(_ResourceId)
| top 25 by BillableGB desc
'@
            }
            $queries['computers'] = @{ Timespan = 'P1D'; Query = @'
find where TimeGenerated > ago(24h) project _BilledSize, _IsBillable, Computer, Type
| where _IsBillable == true and isnotempty(Computer) and Type != 'Usage'
| summarize BillableGB = sum(_BilledSize) / 1e9 by Computer
| top 25 by BillableGB desc
'@
            }
        }
        if (& $want 'Health', 'Overview', 'Recommendations') {
            $queries['operations'] = @"
_LogOperation
| where TimeGenerated > ago($($Days)d)
| summarize Count = count(), FirstSeen = min(TimeGenerated), LastSeen = max(TimeGenerated) by Category, Level, Operation, Detail = substring(Detail, 0, 500)
| order by case(Level == 'Error', 0, Level == 'Warning', 1, 2) asc, Count desc
| take 250
"@
        }
        if (& $want 'Health') {
            $queries['latency'] = @{ Timespan = 'P1D'; Query = @'
Heartbeat
| where TimeGenerated > ago(24h)
| extend LatencySeconds = (ingestion_time() - TimeGenerated) / 1s
| summarize Records = count(), P50Seconds = round(percentile(LatencySeconds, 50), 1), P95Seconds = round(percentile(LatencySeconds, 95), 1), MaxSeconds = round(max(LatencySeconds), 1) by Category
'@
            }
        }
        if (& $want 'Agents', 'Overview', 'Recommendations') {
            $queries['agents'] = @"
Heartbeat
| where TimeGenerated > ago($($Days)d)
| extend OSName = column_ifexists('OSName', ''), ResourceId = column_ifexists('ResourceId', ''), ComputerEnvironment = column_ifexists('ComputerEnvironment', ''), Version = column_ifexists('Version', '')
| summarize arg_max(TimeGenerated, Category, OSType, OSName, Version, ComputerEnvironment, ResourceId) by Computer
| project Computer, LastHeartbeat = TimeGenerated, Category, OSType, OSName, Version, ComputerEnvironment, ResourceId
| order by Computer asc
"@
        }
        if (& $want 'QueryAudit', 'Recommendations') {
            $queries['auditUsers'] = @"
LAQueryLogs
| where TimeGenerated > ago($($Days)d)
| summarize Queries = count(), Failed = countif(ResponseCode != 200), AvgDurationMs = round(avg(ResponseDurationMs), 0), MaxDurationMs = max(ResponseDurationMs), CpuSeconds = round(sum(StatsCPUTimeMs) / 1000., 1), RowsReturned = sum(ResponseRowCount) by User = AADEmail, ClientApp = RequestClientApp
| order by Queries desc
| take 100
"@
        }
        if (& $want 'QueryAudit') {
            $queries['auditSlowest'] = @"
LAQueryLogs
| where TimeGenerated > ago($($Days)d)
| top 25 by ResponseDurationMs desc
| project TimeGenerated, User = AADEmail, ClientApp = RequestClientApp, ResponseCode, DurationMs = ResponseDurationMs, CpuMs = StatsCPUTimeMs, Query = substring(QueryText, 0, 1000)
"@
            $queries['auditFailed'] = @"
LAQueryLogs
| where TimeGenerated > ago($($Days)d) and ResponseCode != 200
| summarize Count = count(), LastSeen = max(TimeGenerated) by ResponseCode, User = AADEmail, ClientApp = RequestClientApp
| order by Count desc
| take 50
"@
        }
    }
    elseif ($Kind -eq 'Graph') {
        $workspace = & $quote $WorkspaceResourceId
        if (& $want 'DataCollectionRules', 'Overview', 'Recommendations') {
            # A DCR sends to the workspace when its destinations name it; the
            # workspace transformation DCR is one of them.
            $queries['rules'] = @{ Tenant = $true; Query = "resources | where type =~ 'microsoft.insights/datacollectionrules' | where tolower(tostring(properties.destinations)) contains $workspace | project id, name, resourceGroup, subscriptionId, location, kind, properties" }
        }
        $queries['solutions'] = @{ Tenant = $true; Query = "resources | where type =~ 'microsoft.operationsmanagement/solutions' | where tolower(tostring(properties.workspaceResourceId)) == $workspace | project name, product = tostring(plan.product), publisher = tostring(plan.publisher)" }
        if (& $want 'Recommendations') {
            $queries['advisor'] = @{ Tenant = $true; Query = "advisorresources | where type =~ 'microsoft.advisor/recommendations' | where tolower(tostring(properties.resourceMetadata.resourceId)) == $workspace | project id, category = tostring(properties.category), impact = tostring(properties.impact), problem = tostring(properties.shortDescription.problem), solution = tostring(properties.shortDescription.solution), learnMore = tostring(properties.learnMoreLink), extended = properties.extendedProperties" }
        }
    }
    else {
        $ids = @($RuleId | Where-Object { $_ } | ForEach-Object { & $quote $_ })
        if ($ids.Count) {
            $queries['associations'] = @{ Tenant = $true; Query = "insightsresources | where type =~ 'microsoft.insights/datacollectionruleassociations' | extend rule = tolower(tostring(properties.dataCollectionRuleId)) | where rule in ($($ids -join ', ')) | project id, name, rule, resource = tostring(split(tolower(id), '/providers/microsoft.insights/datacollectionruleassociations/')[0])" }
        }
    }
    $queries
}
