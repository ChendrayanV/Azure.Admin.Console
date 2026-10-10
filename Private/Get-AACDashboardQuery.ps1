function Get-AACDashboardQuery {
    <#
    .SYNOPSIS
        The Azure Resource Graph queries behind Show-AACDashboard - one batch
        for the whole picture.
    .DESCRIPTION
          totals         resources, types, resource groups, regions
          regions        resources per region
          health         Resource Health: resources per availability state
          unhealthy      the unavailable and degraded resources (10)
          serviceIssues  active Service Health events: service issues,
                         planned maintenance, health and security advisories
          advisor        Advisor recommendations per category and impact
          changes        resource changes in the last -Hours, per kind
          recentChanges  the latest 15 of them: what, who, when
        Every query but totals may fail (no access, a table the account
        can't read): the dashboard then says what it couldn't read.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [ValidateRange(1, 336)]
        [int] $Hours = 24
    )

    $since = "| extend p = properties | extend at = todatetime(p.changeAttributes.timestamp) | where at > ago($($Hours)h)"
    [ordered]@{
        totals        = "resources | summarize resources = count(), types = dcount(tolower(type)), groups = dcount(strcat(subscriptionId, '/', tolower(resourceGroup))), regions = dcount(tolower(location))"
        regions       = 'resources | summarize resources = count() by location = tolower(location) | order by resources desc'
        health        = "healthresources | where type =~ 'microsoft.resourcehealth/availabilitystatuses' | summarize resources = count() by state = tostring(properties.availabilityState)"
        unhealthy     = "healthresources | where type =~ 'microsoft.resourcehealth/availabilitystatuses' | where tostring(properties.availabilityState) in~ ('Unavailable', 'Degraded') | project id, resourceId = tostring(properties.targetResourceId), state = tostring(properties.availabilityState), summary = tostring(properties.summary), reason = tostring(properties.reasonType), since = tostring(properties.occuredTime) | take 10"
        serviceIssues = "servicehealthresources | where type =~ 'microsoft.resourcehealth/events' | extend p = properties | where tostring(p.Status) =~ 'Active' | project id, subscriptionId, trackingId = name, title = tostring(p.Title), eventType = tostring(p.EventType), level = tostring(p.EventLevel), started = tostring(p.ImpactStartTime)"
        advisor       = "advisorresources | where type =~ 'microsoft.advisor/recommendations' | summarize recommendations = count() by category = tostring(properties.category), impact = tostring(properties.impact)"
        changes       = "resourcechanges $since | summarize changes = count() by changeType = tostring(p.changeType)"
        recentChanges = "resourcechanges $since | order by at desc | take 15 | project id, at, changeType = tostring(p.changeType), resourceId = tostring(p.targetResourceId), resourceType = tostring(p.targetResourceType), changedBy = tostring(p.changeAttributes.changedBy), operation = tostring(p.changeAttributes.operation)"
    }
}
