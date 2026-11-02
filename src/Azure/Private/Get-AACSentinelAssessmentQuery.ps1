function Get-AACSentinelAssessmentQuery {
    <#
    .SYNOPSIS
        The KQL queries behind Invoke-AACSentinelAssessment, by section.
    .DESCRIPTION
        Returns the queries run in the workspace (Invoke-AACLogQueryBatch) for
        the sections asked for:

          tables         Tables, RuleTemplates,   Usage per table over -Days:
                         Recommendations          billable and not, last record
          health         Health, Recommendations  _SentinelHealth per resource
                                                  and operation: records and
                                                  failures
          incidentTimes  Incidents,               SecurityIncident: when each
                         Recommendations          incident was closed and first
                                                  changed, which the incidents
                                                  API doesn't return

        Usage's Quantity is in MB (10^6 bytes); it is turned into GB (10^9
        bytes), as Azure bills it. Health goes through the _SentinelHealth()
        function rather than the table, as Microsoft recommends: the function
        keeps working if the table's schema changes. Every record is counted,
        not only failures, so that "no failures" and "no health records at
        all" can be told apart.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [string[]] $Section = @('Tables', 'Health', 'Incidents', 'RuleTemplates', 'Recommendations'),

        [ValidateRange(1, 90)]
        [int] $Days = 30
    )

    $queries = [ordered]@{}
    $want = { param([string[]] $Name) @($Name | Where-Object { $Section -contains $_ }).Count -gt 0 }
    $billable = "tostring(IsBillable) =~ 'true'"

    if (& $want 'Tables', 'RuleTemplates', 'Recommendations') {
        $queries['tables'] = @"
Usage
| where TimeGenerated > ago($($Days)d)
| summarize BillableGB = sumif(Quantity, $billable) / 1000., NonBillableGB = sumif(Quantity, not($billable)) / 1000., LastRecord = max(TimeGenerated), Solution = take_any(Solution) by Table = DataType
"@
    }
    if (& $want 'Health', 'Recommendations') {
        $queries['health'] = @"
_SentinelHealth()
| where TimeGenerated > ago($($Days)d)
| summarize Records = count(), Failures = countif(Status == 'Failure'), LastFailure = maxif(TimeGenerated, Status == 'Failure'), Reason = take_anyif(Description, Status == 'Failure') by SentinelResourceType, SentinelResourceName, SentinelResourceId, OperationName
"@
    }
    if (& $want 'Incidents', 'Recommendations') {
        # A record per change to an incident: the latest one has its current state.
        $queries['incidentTimes'] = @"
SecurityIncident
| where TimeGenerated > ago($($Days)d)
| summarize arg_max(TimeGenerated, ClosedTime, FirstModifiedTime) by IncidentNumber
| project IncidentNumber, ClosedTime, FirstModifiedTime
"@
    }
    $queries
}
