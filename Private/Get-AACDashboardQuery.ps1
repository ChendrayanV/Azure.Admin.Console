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
          types          the 12 commonest resource types
          bySubscription resources per subscription
          tagged         resources, and how many carry a tag
          secureScore    Defender for Cloud's secure score (current, max)
          alerts         active security alerts per severity
          recommendations unhealthy security assessments per severity
          defenderPlans  Defender plans: on (Standard) and in all
          policy         Azure Policy: each resource once, at its worst
                         state - non-compliant and compliant resources
          policyTop      the 5 assignments with the most non-compliant
                         resources
          advisorScore   the Advisor score (per subscription)
          advisorSavings the potential annual savings of Advisor's cost
                         recommendations
          unused         unattached disks, public IPs and network
                         interfaces nothing uses
          roleAssignments role assignments per subscription (tenant-wide),
                         for the closest Azure limit (4,000)
          privileged     Owner, User Access Administrator and RBAC
                         Administrator assignments at a subscription or
                         above (tenant-wide), per principal type
          changeDays     the last 14 days of resource changes, per day and
                         kind
          changers       who made the most changes in the last -Hours
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
    $privileged = "'8e3af657-a8ff-443c-a75c-2fe8c4bcb635', '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9', 'f58310d9-a9f6-439a-9e8d-f62e7b41a168'"
    [ordered]@{
        totals          = "resources | summarize resources = count(), types = dcount(tolower(type)), groups = dcount(strcat(subscriptionId, '/', tolower(resourceGroup))), regions = dcount(tolower(location))"
        regions         = 'resources | summarize resources = count() by location = tolower(location) | order by resources desc'
        health          = "healthresources | where type =~ 'microsoft.resourcehealth/availabilitystatuses' | summarize resources = count() by state = tostring(properties.availabilityState)"
        unhealthy       = "healthresources | where type =~ 'microsoft.resourcehealth/availabilitystatuses' | where tostring(properties.availabilityState) in~ ('Unavailable', 'Degraded') | project id, resourceId = tostring(properties.targetResourceId), state = tostring(properties.availabilityState), summary = tostring(properties.summary), reason = tostring(properties.reasonType), since = tostring(properties.occuredTime) | take 10"
        serviceIssues   = "servicehealthresources | where type =~ 'microsoft.resourcehealth/events' | extend p = properties | where tostring(p.Status) =~ 'Active' | project id, subscriptionId, trackingId = name, title = tostring(p.Title), eventType = tostring(p.EventType), level = tostring(p.EventLevel), started = tostring(p.ImpactStartTime)"
        advisor         = "advisorresources | where type =~ 'microsoft.advisor/recommendations' | summarize recommendations = count() by category = tostring(properties.category), impact = tostring(properties.impact)"
        changes         = "resourcechanges $since | summarize changes = count() by changeType = tostring(p.changeType)"
        recentChanges   = "resourcechanges $since | order by at desc | take 15 | project id, at, changeType = tostring(p.changeType), resourceId = tostring(p.targetResourceId), resourceType = tostring(p.targetResourceType), changedBy = tostring(p.changeAttributes.changedBy), operation = tostring(p.changeAttributes.operation)"
        types           = 'resources | summarize resources = count() by type = tolower(type) | order by resources desc | take 12'
        bySubscription  = 'resources | summarize resources = count() by subscriptionId = tolower(subscriptionId)'
        tagged          = 'resources | summarize total = count(), tagged = countif(array_length(bag_keys(tags)) > 0)'
        secureScore     = "securityresources | where type =~ 'microsoft.security/securescores' | summarize current = sum(todouble(properties.score.current)), max = sum(todouble(properties.score.max))"
        alerts          = "securityresources | where type =~ 'microsoft.security/locations/alerts' | where tostring(properties.status) in~ ('Active', 'InProgress') | summarize alerts = count() by severity = tostring(properties.severity)"
        recommendations = "securityresources | where type =~ 'microsoft.security/assessments' | where tostring(properties.status.code) =~ 'Unhealthy' | summarize recommendations = count() by severity = tostring(properties.metadata.severity)"
        defenderPlans   = "securityresources | where type =~ 'microsoft.security/pricings' | summarize on = countif(tostring(properties.pricingTier) =~ 'Standard'), total = count()"
        policy          = "policyresources | where type =~ 'microsoft.policyinsights/policystates' | extend state = tostring(properties.complianceState), resourceId = tolower(tostring(properties.resourceId)) | summarize worst = max(case(state == 'NonCompliant', 2, state == 'Compliant', 1, 0)) by resourceId | summarize nonCompliant = countif(worst == 2), compliant = countif(worst == 1)"
        policyTop       = "policyresources | where type =~ 'microsoft.policyinsights/policystates' | where tostring(properties.complianceState) == 'NonCompliant' | summarize resources = dcount(tolower(tostring(properties.resourceId))) by assignment = tostring(properties.policyAssignmentName), scope = tostring(properties.policyAssignmentScope) | top 5 by resources"
        advisorScore    = "advisorresources | where type =~ 'microsoft.advisor/advisorscore' and name =~ 'Advisor' | summarize score = avg(todouble(properties.lastRefreshedScore.score))"
        advisorSavings  = "advisorresources | where type =~ 'microsoft.advisor/recommendations' and tostring(properties.category) =~ 'Cost' | extend p = properties.extendedProperties | extend annual = coalesce(todouble(p.annualSavingsAmount), todouble(p.savingsAmount) * 12) | summarize savings = sum(annual), recommendations = count() by currency = tostring(p.savingsCurrency)"
        unused          = "resources | where (type =~ 'microsoft.compute/disks' and tostring(properties.diskState) =~ 'Unattached') or (type =~ 'microsoft.network/publicipaddresses' and isnull(properties.ipConfiguration) and isnull(properties.natGateway)) or (type =~ 'microsoft.network/networkinterfaces' and isnull(properties.virtualMachine) and isnull(properties.privateEndpoint)) | summarize resources = count() by type = tolower(type)"
        roleAssignments = @{ Tenant = $true; Query = "authorizationresources | where type =~ 'microsoft.authorization/roleassignments' | extend scope = tolower(tostring(properties.scope)) | where scope startswith '/subscriptions/' | summarize used = count() by subscriptionId = tostring(split(scope, '/')[2])" }
        privileged      = @{ Tenant = $true; Query = "authorizationresources | where type =~ 'microsoft.authorization/roleassignments' | extend scope = tolower(tostring(properties.scope)), role = tolower(tostring(split(tostring(properties.roleDefinitionId), '/')[-1])) | where role in ($privileged) and (scope == '/' or scope startswith '/providers/microsoft.management/' or scope matches regex '^/subscriptions/[^/]+$') | summarize assignments = count() by principalType = tostring(properties.principalType), subscriptionId = iif(scope startswith '/subscriptions/', tostring(split(scope, '/')[2]), '')" }
        changeDays      = "resourcechanges | extend p = properties | extend at = todatetime(p.changeAttributes.timestamp) | where at > ago(14d) | summarize changes = count() by day = format_datetime(bin(at, 1d), 'yyyy-MM-dd'), changeType = tostring(p.changeType)"
        changers        = "resourcechanges $since | summarize changes = count(), deletes = countif(tostring(p.changeType) == 'Delete') by changedBy = tostring(p.changeAttributes.changedBy) | top 5 by changes"
    }
}
