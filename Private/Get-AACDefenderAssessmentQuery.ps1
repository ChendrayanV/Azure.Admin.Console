function Get-AACDefenderAssessmentQuery {
    <#
    .SYNOPSIS
        What Invoke-AACDefenderAssessment reads: the Azure Resource Graph
        queries (securityresources) and the Defender for Cloud REST API
        calls for the settings Resource Graph doesn't hold.
    .DESCRIPTION
        -Section picks what is read (Recommendations, AttackPaths, Alerts,
        Inventory, Vulnerabilities, Posture, Compliance, Settings); the
        subscriptions and the Defender plans are always read.

        Returns @{ Graph (an ordered hashtable for Invoke-AACGraphBatch);
        Rest (a hashtable: name -> the URI under a subscription, with
        {0} for its ID) }.

        Resource Graph:
          subscriptions             names
          Plans                     the Defender plans (pricings) with their
                                    sub-plan, extensions and since when
          Scores, Controls,
          ControlAssessments        secure scores and their controls
                                    (Get-AACDefenderQuery)
          RecommendationSummary     per recommendation: its unhealthy,
                                    healthy and not applicable resources and
                                    its metadata
          Unhealthy                 every unhealthy recommendation on a
                                    resource, with its risk level, risk
                                    factors and attack paths (Defender CSPM)
          InventorySummary          per resource: its assessments by status
                                    and unhealthy ones by severity
          AttackPaths               attack paths (Defender CSPM)
          Alerts                    security alerts generated within
                                    -AlertDays, every status
          Vulnerabilities           unhealthy sub-assessments: CVEs on
                                    machines, SQL and container images
          Standards, ComplianceControls,
          ComplianceAssessments     regulatory compliance
                                    (Get-AACDefenderQuery)
        REST (per subscription):
          Contacts                  security contacts and notifications
          Settings                  integrations (MDE, Defender for Cloud
                                    Apps, Sentinel)
          Jit                       just-in-time VM access policies
          Connectors                AWS, GCP, GitHub, Azure DevOps and
                                    GitLab connectors
          Suppression               alert suppression rules
        Every Resource Graph query keeps an id column, so it is paged.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [ValidateSet('Recommendations', 'AttackPaths', 'Alerts', 'Inventory', 'Vulnerabilities', 'Posture', 'Compliance', 'Settings')]
        [string[]] $Section = @('Recommendations', 'AttackPaths', 'Alerts', 'Inventory', 'Vulnerabilities', 'Posture', 'Compliance', 'Settings'),

        [ValidateRange(1, 365)]
        [int] $AlertDays = 30
    )

    $resourceId = 'tolower(coalesce(tostring(properties.resourceDetails.Id), tostring(properties.resourceDetails.ResourceId), tostring(properties.resourceDetails.AzureResourceId), tostring(properties.resourceDetails.NativeResourceId)))'
    $assessments = "securityresources | where type =~ 'microsoft.security/assessments' | extend resourceId = $resourceId, status = tostring(properties.status.code), severity = tostring(properties.metadata.severity)"
    $defender = Get-AACDefenderQuery -Name 'Scores', 'Controls', 'ControlAssessments', 'Standards', 'ComplianceControls', 'ComplianceAssessments'
    $graph = [ordered]@{}
    $graph['subscriptions'] = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions' | project id, subscriptionId, name"
    $graph['Plans'] = "securityresources | where type =~ 'microsoft.security/pricings' | where properties.deprecated != true | project id, subscriptionId, plan = name, tier = tostring(properties.pricingTier), subPlan = tostring(properties.subPlan), since = tostring(properties.enablementTime), extensions = properties.extensions"
    if ($Section -contains 'Recommendations' -or $Section -contains 'Posture') {
        $graph['Scores'] = $defender['Scores'] + ' | extend id = subscriptionId'
        $graph['Controls'] = $defender['Controls'] + ", id = strcat(subscriptionId, '|', tostring(properties.displayName))"
        $graph['ControlAssessments'] = $defender['ControlAssessments'] + " | extend id = strcat(control, '|', key)"
    }
    if ($Section -contains 'Recommendations') {
        $graph['RecommendationSummary'] = "$assessments | summarize unhealthy = countif(status == 'Unhealthy'), healthy = countif(status == 'Healthy'), notApplicable = countif(status == 'NotApplicable'), subscriptions = dcountif(subscriptionId, status == 'Unhealthy'), name = take_any(tostring(properties.displayName)), severity = take_any(severity), impact = take_any(tostring(properties.metadata.userImpact)), effort = take_any(tostring(properties.metadata.implementationEffort)), categories = take_any(strcat_array(properties.metadata.categories, ', ')), threats = take_any(strcat_array(properties.metadata.threats, ', ')), description = take_any(tostring(properties.metadata.description)), remediation = take_any(tostring(properties.metadata.remediationDescription)), assessmentType = take_any(tostring(properties.metadata.assessmentType)), preview = take_any(tostring(properties.metadata.preview)), policyDefinitionId = take_any(tostring(properties.metadata.policyDefinitionId)) by key = tolower(name) | extend id = key"
    }
    if ($Section -contains 'Recommendations' -or $Section -contains 'Inventory') {
        $graph['Unhealthy'] = "$assessments | where status == 'Unhealthy' | project id = tolower(id), key = tolower(name), resourceId, subscriptionId, name = tostring(properties.displayName), severity, cause = tostring(properties.status.cause), statusDescription = tostring(properties.status.description), link = tostring(properties.links.azurePortal), since = tostring(properties.status.statusChangeDate), firstEvaluated = tostring(properties.status.firstEvaluationDate), riskLevel = tostring(properties.risk.level), riskFactors = properties.risk.riskFactors, attackPaths = array_length(properties.risk.attackPathsReferences), source = tostring(properties.resourceDetails.Source)"
    }
    if ($Section -contains 'Inventory') {
        $graph['InventorySummary'] = "$assessments | where isnotempty(resourceId) and status in ('Healthy', 'Unhealthy', 'NotApplicable') | summarize healthy = countif(status == 'Healthy'), unhealthy = countif(status == 'Unhealthy'), notApplicable = countif(status == 'NotApplicable'), high = countif(status == 'Unhealthy' and severity == 'High'), medium = countif(status == 'Unhealthy' and severity == 'Medium'), low = countif(status == 'Unhealthy' and severity == 'Low'), source = take_any(tostring(properties.resourceDetails.Source)) by resourceId, subscriptionId | extend id = resourceId"
    }
    if ($Section -contains 'AttackPaths' -or $Section -contains 'Inventory') {
        # The whole properties: their shape varies, and there are few of them.
        $graph['AttackPaths'] = "securityresources | where type =~ 'microsoft.security/attackpaths' | project id, name, subscriptionId, properties"
    }
    if ($Section -contains 'Alerts' -or $Section -contains 'Inventory') {
        $graph['Alerts'] = "securityresources | where type =~ 'microsoft.security/locations/alerts' | extend p = properties | extend time = todatetime(coalesce(p.TimeGeneratedUtc, p.timeGeneratedUtc)) | where time > ago($($AlertDays)d) | project id, subscriptionId, status = tostring(coalesce(p.Status, p.status)), name = tostring(coalesce(p.AlertDisplayName, p.alertDisplayName)), severity = tostring(coalesce(p.Severity, p.severity)), intent = tostring(coalesce(p.Intent, p.intent)), techniques = coalesce(p.Techniques, p.techniques), subTechniques = coalesce(p.SubTechniques, p.subTechniques), alertType = tostring(coalesce(p.AlertType, p.alertType)), time, start = tostring(coalesce(p.StartTimeUtc, p.startTimeUtc)), end = tostring(coalesce(p.EndTimeUtc, p.endTimeUtc)), description = tostring(coalesce(p.Description, p.description)), remediation = coalesce(p.RemediationSteps, p.remediationSteps), link = tostring(coalesce(p.AlertUri, p.alertUri)), entity = tostring(coalesce(p.CompromisedEntity, p.compromisedEntity)), resources = coalesce(p.ResourceIdentifiers, p.resourceIdentifiers), product = tostring(coalesce(p.ProductName, p.productName)), isIncident = tostring(coalesce(p.IsIncident, p.isIncident))"
    }
    if ($Section -contains 'Vulnerabilities' -or $Section -contains 'Inventory') {
        $graph['Vulnerabilities'] = "securityresources | where type =~ 'microsoft.security/assessments/subassessments' | where tostring(properties.status.code) == 'Unhealthy' | project id, subscriptionId, assessmentKey = tolower(extract('(?i)/assessments/([^/]+)/subassessments/', 1, id)), resourceId = tolower(coalesce(tostring(properties.resourceDetails.id), tostring(properties.resourceDetails.Id), extract('(?i)^(.+)/providers/Microsoft\\.Security/assessments/', 1, id))), name = tostring(properties.displayName), severity = tostring(properties.status.severity), category = tostring(properties.category), impact = tostring(properties.impact), remediation = tostring(properties.remediation), vulnerabilityId = tostring(properties.id), cve = properties.additionalData.cve, cveId = tostring(properties.additionalData.vulnerabilityDetails.cveId), patchable = tostring(properties.additionalData.patchable), image = tostring(coalesce(properties.additionalData.artifactDetails.repositoryName, properties.additionalData.repositoryName)), generated = tostring(properties.timeGenerated)"
    }
    if ($Section -contains 'Compliance') {
        $graph['Standards'] = $defender['Standards'] + " | extend id = strcat(subscriptionId, '|', standard)"
        $graph['ComplianceControls'] = $defender['ComplianceControls'] + " | extend id = strcat(subscriptionId, '|', standard, '|', control)"
        $graph['ComplianceAssessments'] = $defender['ComplianceAssessments'] + " | extend id = strcat(subscriptionId, '|', standard, '|', control, '|', key)"
    }

    $rest = @{}
    if ($Section -contains 'Settings' -or $Section -contains 'Posture') {
        $rest['Contacts'] = '/subscriptions/{0}/providers/Microsoft.Security/securityContacts?api-version=2023-12-01-preview'
        $rest['Settings'] = '/subscriptions/{0}/providers/Microsoft.Security/settings?api-version=2022-05-01'
        $rest['Connectors'] = '/subscriptions/{0}/providers/Microsoft.Security/securityConnectors?api-version=2023-10-01-preview'
        $rest['Jit'] = '/subscriptions/{0}/providers/Microsoft.Security/jitNetworkAccessPolicies?api-version=2020-01-01'
    }
    if ($Section -contains 'Alerts' -or $Section -contains 'Settings') {
        $rest['Suppression'] = '/subscriptions/{0}/providers/Microsoft.Security/alertsSuppressionRules?api-version=2019-01-01-preview'
    }
    @{ Graph = $graph; Rest = $rest }
}
