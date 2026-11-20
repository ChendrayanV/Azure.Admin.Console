function Get-AACSentinelAlertQuery {
    <#
    .SYNOPSIS
        The KQL queries behind Get-AACSentinelAlert.
    .DESCRIPTION
        Two queries for the workspace (Invoke-AACLogQueryBatch):

          alerts     SecurityAlert over -Days: the latest record of each alert
                     (an alert is written again when its status changes),
                     newest first, at most -Limit rows. -Severity is applied
                     here.
          incidents  SecurityIncident over -Days: which incident each alert
                     ended up in, from the latest record of each incident

        Every product that writes to SecurityAlert is included: Sentinel's
        analytics rules, Defender XDR, Defender for Cloud, Entra ID
        Protection and the rest.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [ValidateRange(1, 3650)]
        [int] $Days = 7,

        [ValidateSet('High', 'Medium', 'Low', 'Informational')]
        [string[]] $Severity,

        [ValidateRange(1, 500000)]
        [int] $Limit = 10000
    )

    $severityFilter = if ($Severity) { "`n| where AlertSeverity in~ ($(@($Severity | ForEach-Object { "'$_'" }) -join ', '))" } else { '' }
    $queries = [ordered]@{}
    $queries['alerts'] = @"
SecurityAlert
| where TimeGenerated > ago($($Days)d)$severityFilter
| summarize arg_max(TimeGenerated, *) by SystemAlertId
| top $Limit by TimeGenerated desc
| project TimeGenerated, SystemAlertId, AlertName, AlertSeverity, Status, AlertType, ProviderName, ProductName, ProductComponentName, VendorName, CompromisedEntity, Tactics, Techniques, Description, RemediationSteps, Entities, ExtendedProperties, StartTime, EndTime, AlertLink
"@
    # One row per alert in an incident: AlertIds holds the SystemAlertIds.
    $queries['incidents'] = @"
SecurityIncident
| where TimeGenerated > ago($($Days)d)
| summarize arg_max(TimeGenerated, IncidentNumber, Title, Status, AlertIds) by IncidentName
| mv-expand AlertId = AlertIds to typeof(string)
| project AlertId, IncidentNumber, IncidentTitle = Title, IncidentStatus = Status
"@
    $queries
}
