function Get-AACResourceHealthQuery {
    <#
    .SYNOPSIS
        The Azure Resource Graph queries behind Get-AACResourceHealth: each
        resource's Resource Health status, its latest health event, and the
        Azure Service Health events (outages, maintenance, advisories) with
        the resources they hit.
    .DESCRIPTION
          statuses   every resource's current availability (Available,
                     Unavailable, Degraded, Unknown), why, and since when
          events     each resource's latest health annotation (a reboot, a
                     live migration, a platform or customer action)
          service    Service Health events active, or updated in the last
                     -Days
          impacted   the resources Service Health names as impacted
        -ResourceGroupName narrows the statuses and annotations.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [string[]] $ResourceGroupName,

        [ValidateRange(1, 90)]
        [int] $Days = 7
    )

    $quote = { param([string] $Text) ConvertTo-AACKqlLiteral -Text $Text -Lower }
    $groups = @($ResourceGroupName | Where-Object { $_ })
    $in = if ($groups.Count) { " | where tolower(tostring(split(resourceId, '/')[4])) in ($((@($groups | ForEach-Object { & $quote $_ })) -join ', '))" } else { '' }
    $target = "extend resourceId = tolower(tostring(properties.targetResourceId)) | extend resourceId = iff(isempty(resourceId), tolower(tostring(split(id, '/providers/Microsoft.ResourceHealth/', 0)[0])), resourceId)"

    [ordered]@{
        statuses = "healthresources | where type =~ 'microsoft.resourcehealth/availabilitystatuses' | $target$in | project id, resourceId, subscriptionId, location, state = tostring(properties.availabilityState), reason = tostring(properties.reasonType), heading = tostring(properties['title']), summary = tostring(properties.summary), since = tostring(properties.occuredTime), chronicity = tostring(properties.reasonChronicity), eta = tostring(properties.resolutionETA), category = tostring(properties.category), context = tostring(properties.context)"
        events   = "healthresources | where type =~ 'microsoft.resourcehealth/resourceannotations' | $target$in | project id, resourceId, annotation = tostring(properties.annotationName), summary = tostring(properties.summary), reason = tostring(properties.reason), occurred = tostring(properties.occurredTime), context = tostring(properties.context), category = tostring(properties.category), impact = tostring(properties.impactType)"
        service  = "servicehealthresources | where type =~ 'microsoft.resourcehealth/events' | extend p = properties | where tostring(p.Status) =~ 'Active' or todatetime(p.LastUpdateTime) > ago($($Days)d) | project id, subscriptionId, trackingId = name, eventType = tostring(p.EventType), status = tostring(p.Status), level = coalesce(tostring(p.EventLevel), tostring(p.Level)), heading = tostring(p.Title), summary = tostring(p.Summary), started = tostring(p.ImpactStartTime), mitigated = tostring(p.ImpactMitigationTime), updated = tostring(p.LastUpdateTime), impact = p.Impact"
        impacted = "servicehealthresources | where type =~ 'microsoft.resourcehealth/events/impactedresources' | project id, trackingId = tostring(split(id, '/')[6]), resourceId = tolower(tostring(properties.targetResourceId)), region = tostring(properties.targetRegion)"
    }
}
