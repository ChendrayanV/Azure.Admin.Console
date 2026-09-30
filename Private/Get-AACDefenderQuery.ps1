function Get-AACDefenderQuery {
    <#
    .SYNOPSIS
        The Azure Resource Graph queries for Microsoft Defender for Cloud
        (securityresources) - one set, shared by Get-AACInventory and
        Get-AACSecurityPosture, so both read the same data the same way.
    .DESCRIPTION
        -Name picks the queries, by name, into an ordered hashtable for
        Invoke-AACGraphBatch:
          Scores                 each subscription's secure score (ascScore)
          Controls               the secure score controls, with points
          ControlAssessments     which recommendation (assessment key) is in
                                 which control
          Summary                per resource: healthy and unhealthy
                                 assessments, unhealthy ones by severity
          Recommendations        every unhealthy assessment: resource,
                                 recommendation, severity, impact, effort,
                                 categories, cause, description, remediation
                                 steps, portal link, since when
          Alerts                 active and in-progress security alerts
          Plans                  the Defender plans (pricings), on or off
          Standards              regulatory compliance standards
          ComplianceControls     their controls
          ComplianceAssessments  the assessments in each control
          PolicyStates           every policy state (Get-AACPolicyStateQuery),
                                 rolled up as the portal does by
                                 ConvertTo-AACPolicyState
          PolicyAssignments      the assignments' display names and scopes
                                 (read tenant-wide: many are at management
                                 group scope)
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Scores', 'Controls', 'ControlAssessments', 'Summary', 'Recommendations', 'Alerts', 'Plans', 'Standards', 'ComplianceControls', 'ComplianceAssessments', 'PolicyStates', 'PolicyAssignments')]
        [string[]] $Name
    )

    $assessments = "securityresources | where type =~ 'microsoft.security/assessments' | extend resourceId = tolower(coalesce(tostring(properties.resourceDetails.Id), tostring(properties.resourceDetails.ResourceId))), status = tostring(properties.status.code), severity = tostring(properties.metadata.severity)"
    $all = [ordered]@{
        Scores                = "securityresources | where type =~ 'microsoft.security/securescores' and name == 'ascScore' | project subscriptionId, current = todouble(properties.score.current), max = todouble(properties.score.max)"
        Controls              = "securityresources | where type =~ 'microsoft.security/securescores/securescorecontrols' | project subscriptionId, control = tostring(properties.displayName), current = todouble(properties.score.current), max = todouble(properties.score.max), healthy = toint(properties.healthyResourceCount), unhealthy = toint(properties.unhealthyResourceCount)"
        ControlAssessments    = "securityresources | where type =~ 'microsoft.security/securescores/securescorecontrols' | mv-expand definition = properties.definition.properties.assessmentDefinitions | project control = tostring(properties.displayName), key = tolower(tostring(split(tostring(definition.id), '/')[-1])) | where isnotempty(key) | distinct control, key"
        Summary               = "$assessments | where status in ('Healthy', 'Unhealthy') | summarize healthy = countif(status == 'Healthy'), unhealthy = countif(status == 'Unhealthy'), high = countif(status == 'Unhealthy' and severity == 'High'), medium = countif(status == 'Unhealthy' and severity == 'Medium'), low = countif(status == 'Unhealthy' and severity == 'Low') by resourceId"
        Recommendations       = "$assessments | where status == 'Unhealthy' | project key = tolower(name), resourceId, subscriptionId, name = tostring(properties.displayName), severity, impact = tostring(properties.metadata.userImpact), effort = tostring(properties.metadata.implementationEffort), categories = strcat_array(properties.metadata.categories, ', '), cause = tostring(properties.status.cause), description = tostring(properties.metadata.description), remediation = tostring(properties.metadata.remediationDescription), link = tostring(properties.links.azurePortal), since = tostring(properties.status.statusChangeDate)"
        Alerts                = "securityresources | where type =~ 'microsoft.security/locations/alerts' | extend status = tostring(coalesce(properties.Status, properties.status)) | where status in~ ('Active', 'InProgress') | project id, subscriptionId, status, name = tostring(coalesce(properties.AlertDisplayName, properties.alertDisplayName)), severity = tostring(coalesce(properties.Severity, properties.severity)), intent = tostring(coalesce(properties.Intent, properties.intent)), alertType = tostring(coalesce(properties.AlertType, properties.alertType)), time = tostring(coalesce(properties.TimeGeneratedUtc, properties.timeGeneratedUtc)), description = tostring(coalesce(properties.Description, properties.description)), link = tostring(coalesce(properties.AlertUri, properties.alertUri)), entity = tostring(coalesce(properties.CompromisedEntity, properties.compromisedEntity)), resources = coalesce(properties.ResourceIdentifiers, properties.resourceIdentifiers)"
        Plans                 = "securityresources | where type =~ 'microsoft.security/pricings' | where properties.deprecated != true | project subscriptionId, plan = name, tier = tostring(properties.pricingTier), subPlan = tostring(properties.subPlan)"
        Standards             = "securityresources | where type =~ 'microsoft.security/regulatorycompliancestandards' | project subscriptionId, standard = name, state = tostring(properties.state), passed = toint(properties.passedControls), failed = toint(properties.failedControls), skipped = toint(properties.skippedControls), unsupported = toint(properties.unsupportedControls)"
        ComplianceControls    = "securityresources | where type =~ 'microsoft.security/regulatorycompliancestandards/regulatorycompliancecontrols' | extend standard = extract('(?i)/regulatoryComplianceStandards/([^/]+)', 1, id) | project subscriptionId, standard, control = name, description = tostring(properties.description), state = tostring(properties.state), passed = toint(properties.passedAssessments), failed = toint(properties.failedAssessments), skipped = toint(properties.skippedAssessments)"
        ComplianceAssessments = "securityresources | where type =~ 'microsoft.security/regulatorycompliancestandards/regulatorycompliancecontrols/regulatorycomplianceassessments' | extend standard = extract('(?i)/regulatoryComplianceStandards/([^/]+)', 1, id), control = extract('(?i)/regulatoryComplianceControls/([^/]+)', 1, id) | project subscriptionId, standard, control, key = tolower(name), description = tostring(properties.description), state = tostring(properties.state), failedResources = toint(properties.failedResources)"
        PolicyStates          = Get-AACPolicyStateQuery
        PolicyAssignments     = "policyresources | where type =~ 'microsoft.authorization/policyassignments' | project assignmentId = tolower(id), name, displayName = tostring(properties.displayName), scope = tostring(properties.scope), enforcement = tostring(properties.enforcementMode)"
    }
    $picked = [ordered]@{}
    foreach ($key in $Name) { $picked[$key] = $all[$key] }
    $picked
}
