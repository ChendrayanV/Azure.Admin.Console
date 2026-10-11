function Get-AACSecurityAlertQuery {
    <#
    .SYNOPSIS
        The Azure Resource Graph queries behind Get-AACSecurityAlert: the
        Microsoft Defender for Cloud security alerts, filtered by status,
        severity and age in the query, and the Defender plans (so an empty
        list can be told apart from a subscription that can't have alerts).
    .DESCRIPTION
        -Status, -Severity and -Days narrow the alerts in Resource Graph;
        none of them, every alert Defender for Cloud still holds. Alert
        properties are read in both cases (Resource Graph has returned
        AlertDisplayName and alertDisplayName). Plans may fail; the alerts
        are still read.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [ValidateSet('Active', 'InProgress', 'Resolved', 'Dismissed')]
        [string[]] $Status,

        [ValidateSet('High', 'Medium', 'Low', 'Informational')]
        [string[]] $Severity,

        [ValidateRange(0, 3650)]
        [int] $Days = 0
    )

    $list = { param([string[]] $Value) (@($Value | Select-Object -Unique | ForEach-Object { "'$_'" }) -join ', ') }
    $where = @(
        if ($Status) { "| where status in~ ($(& $list $Status))" }
        if ($Severity) { "| where severity in~ ($(& $list $Severity))" }
        if ($Days -gt 0) { "| where generated > ago($($Days)d)" }
    ) -join ' '
    $alerts = "securityresources | where type =~ 'microsoft.security/locations/alerts' | extend p = properties | extend status = tostring(coalesce(p.Status, p.status)), severity = tostring(coalesce(p.Severity, p.severity)), generated = todatetime(coalesce(p.TimeGeneratedUtc, p.timeGeneratedUtc)) $where" +
    ' | project id, alertName = name, subscriptionId, location, status, severity, generated' +
    ', name = tostring(coalesce(p.AlertDisplayName, p.alertDisplayName)), alertType = tostring(coalesce(p.AlertType, p.alertType))' +
    ', intent = tostring(coalesce(p.Intent, p.intent)), techniques = coalesce(p.Techniques, p.techniques), subTechniques = coalesce(p.SubTechniques, p.subTechniques)' +
    ', start = tostring(coalesce(p.StartTimeUtc, p.startTimeUtc)), end = tostring(coalesce(p.EndTimeUtc, p.endTimeUtc))' +
    ', description = tostring(coalesce(p.Description, p.description)), remediation = coalesce(p.RemediationSteps, p.remediationSteps)' +
    ', link = tostring(coalesce(p.AlertUri, p.alertUri)), entity = tostring(coalesce(p.CompromisedEntity, p.compromisedEntity))' +
    ', resources = coalesce(p.ResourceIdentifiers, p.resourceIdentifiers), entities = coalesce(p.Entities, p.entities), extended = coalesce(p.ExtendedProperties, p.extendedProperties)' +
    ', product = tostring(coalesce(p.ProductName, p.productName)), vendor = tostring(coalesce(p.VendorName, p.vendorName)), isIncident = tostring(coalesce(p.IsIncident, p.isIncident))'

    [ordered]@{
        alerts = $alerts
        plans  = (Get-AACDefenderQuery -Name 'Plans')['Plans']
    }
}
