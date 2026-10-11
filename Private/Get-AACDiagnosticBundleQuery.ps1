function Get-AACDiagnosticBundleQuery {
    <#
    .SYNOPSIS
        The Azure Resource Graph queries behind Export-AACDiagnosticBundle:
        everything Resource Graph knows about the given resources - their
        configuration, health, Advisor and Defender for Cloud
        recommendations, policy compliance, fired alerts, recent changes and
        role assignments.
    .DESCRIPTION
        -ResourceId is the resources' IDs; -Hours the window for alerts and
        health events (changes go back as far as Resource Graph keeps them,
        14 days). Every query keeps a 'target' column: the resource (lower
        case) the row is about.

          config           the resource as Resource Graph has it (properties,
                           SKU, identity, tags, zones...)
          health           Resource Health's current status
          healthEvents     the latest health annotation
          advisor          Advisor recommendations on it
          defender         unhealthy Defender for Cloud assessments
          policy           non-compliant Azure Policy states
          alerts           alerts fired on it in the window
          changes          property-level changes (14 days)
          roleAssignments  role assignments scoped to it
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [string[]] $ResourceId,

        [ValidateRange(1, 720)]
        [int] $Hours = 24
    )

    $ids = (@($ResourceId | ForEach-Object { "'" + ($_.TrimEnd('/').ToLowerInvariant() -replace "'", "\'") + "'" } | Select-Object -Unique) -join ', ')
    [ordered]@{
        config          = "resources | extend target = tolower(id) | where target in ($ids) | project id, target, name, type = tolower(type), kind, location, resourceGroup, subscriptionId, sku, plan, identity, zones, tags, managedBy, properties"
        health          = "healthresources | where type =~ 'microsoft.resourcehealth/availabilitystatuses' | extend target = tolower(tostring(properties.targetResourceId)) | where target in ($ids) | project id, target, state = tostring(properties.availabilityState), reason = tostring(properties.reasonType), summary = tostring(properties.summary), since = tostring(properties.occuredTime), details = properties"
        healthEvents    = "healthresources | where type =~ 'microsoft.resourcehealth/resourceannotations' | extend target = tolower(tostring(properties.targetResourceId)) | where target in ($ids) | project id, target, annotation = tostring(properties.annotationName), summary = tostring(properties.summary), occurred = tostring(properties.occurredTime), context = tostring(properties.context), details = properties"
        advisor         = "advisorresources | where type =~ 'microsoft.advisor/recommendations' | extend target = tolower(tostring(properties.resourceMetadata.resourceId)) | where target in ($ids) | project id, target, category = tostring(properties.category), impact = tostring(properties.impact), problem = tostring(properties.shortDescription.problem), solution = tostring(properties.shortDescription.solution), updated = tostring(properties.lastUpdated)"
        defender        = "securityresources | where type =~ 'microsoft.security/assessments' | extend target = tolower(coalesce(tostring(properties.resourceDetails.Id), tostring(properties.resourceDetails.ResourceId))) | where target in ($ids) and tostring(properties.status.code) == 'Unhealthy' | project id, target, recommendation = tostring(properties.displayName), severity = tostring(properties.metadata.severity), cause = tostring(properties.status.cause), remediation = tostring(properties.metadata.remediationDescription), link = tostring(properties.links.azurePortal)"
        policy          = "policyresources | where type =~ 'microsoft.policyinsights/policystates' | extend target = tolower(tostring(properties.resourceId)) | where target in ($ids) and tostring(properties.complianceState) =~ 'NonCompliant' | project id, target, assignment = tostring(properties.policyAssignmentName), definition = tostring(properties.policyDefinitionName), effect = tostring(properties.policyDefinitionAction), evaluated = tostring(properties.timestamp)"
        alerts          = "alertsmanagementresources | where type =~ 'microsoft.alertsmanagement/alerts' | extend target = tolower(tostring(properties.essentials.targetResource)) | where target in ($ids) and todatetime(properties.essentials.startDateTime) > ago($($Hours)h) | project id, target, name, severity = tostring(properties.essentials.severity), alertState = tostring(properties.essentials.alertState), condition = tostring(properties.essentials.monitorCondition), fired = tostring(properties.essentials.startDateTime), rule = tostring(properties.essentials.alertRule), description = tostring(properties.essentials.description)"
        changes         = "resourcechanges | extend target = tolower(tostring(properties.targetResourceId)) | where target in ($ids) | project id, target, changeType = tostring(properties.changeType), changedAt = tostring(properties.changeAttributes.timestamp), changedBy = tostring(properties.changeAttributes.changedBy), clientType = tostring(properties.changeAttributes.clientType), operation = tostring(properties.changeAttributes.operation), changes = properties.changes"
        roleAssignments = "authorizationresources | where type =~ 'microsoft.authorization/roleassignments' | extend target = tolower(tostring(properties.scope)) | where target in ($ids) | project id, target, principalId = tostring(properties.principalId), principalType = tostring(properties.principalType), roleId = tostring(properties.roleDefinitionId), createdOn = tostring(properties.createdOn)"
    }
}
