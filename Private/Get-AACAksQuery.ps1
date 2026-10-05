function Get-AACAksQuery {
    <#
    .SYNOPSIS
        The Azure Resource Graph queries of Invoke-AACAksAssessment.
    .DESCRIPTION
        -Stage Clusters: the AKS clusters (with every property), and the
        subscriptions' names.
        -Stage Assess: what is read about them, all at once:
          clusterStates   the policy states of the cluster resources
                          (policyresources policystates) - one per cluster,
                          assignment and policy, with the effect
          components      the non-compliant Kubernetes components
                          (componentpolicystates: pods, services, network
                          policies...) - Azure Policy keeps up to 500 per
                          policy and cluster
          assignments     every policy assignment the account can see (the
                          management group ones too), with its enforcement
                          mode and effect parameter
          advisor         Azure Advisor's recommendations for clusters
          defender        Defender for Cloud's unhealthy assessments for
                          clusters (and their sub-assessments' counts)
        These follow the AKS Policy Compliance Toolkit's queries, without
        its table of built-in policy names: the names are read from Azure
        afterwards. Each keeps an id column, so Resource Graph pages it.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Clusters', 'Assess')]
        [string] $Stage,

        [string[]] $ResourceGroupName
    )

    $quote = { param([string] $Text) "'" + ($Text -replace '\\', '\\' -replace "'", "\'") + "'" }
    $groups = @($ResourceGroupName | Where-Object { $_ })
    $queries = [ordered]@{}
    if ($Stage -eq 'Clusters') {
        $groupFilter = if ($groups.Count) { " | where resourceGroup in~ ($((@($groups | ForEach-Object { & $quote $_ })) -join ', '))" } else { '' }
        $queries['clusters'] = "resources | where type =~ 'microsoft.containerservice/managedclusters'$groupFilter | project id, name, resourceGroup, subscriptionId, location, sku, identity, zones, tags, properties"
        $queries['subscriptions'] = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions' | project id, subscriptionId, name"
        return $queries
    }
    $clusterType = "'microsoft.containerservice/managedclusters'"
    $queries['clusterStates'] = "policyresources | where type =~ 'microsoft.policyinsights/policystates' | where tolower(tostring(properties.resourceType)) == $clusterType | project id, clusterId = tolower(tostring(properties.resourceId)), assignmentId = tolower(tostring(properties.policyAssignmentId)), definitionId = tolower(tostring(properties.policyDefinitionId)), setId = tolower(tostring(properties.policySetDefinitionId)), refId = tostring(properties.policyDefinitionReferenceId), effect = tostring(properties.policyDefinitionAction), state = tostring(properties.complianceState), evaluated = tostring(properties.timestamp)"
    $queries['components'] = "policyresources | where type =~ 'microsoft.policyinsights/componentpolicystates' | where tostring(properties.complianceState) =~ 'NonCompliant' | where tostring(properties.resourceId) contains '/providers/Microsoft.ContainerService/managedClusters/' | project id, clusterId = tolower(tostring(properties.resourceId)), assignmentId = tolower(tostring(properties.policyAssignmentId)), definitionId = tolower(tostring(properties.policyDefinitionId)), setId = tolower(tostring(properties.policySetDefinitionId)), refId = tostring(properties.policyDefinitionReferenceId), componentType = tostring(properties.componentType), componentId = tostring(properties.componentId), evaluated = tostring(properties.timestamp)"
    $queries['assignments'] = @{ Tenant = $true; Query = "policyresources | where type =~ 'microsoft.authorization/policyassignments' | project id, assignmentId = tolower(id), name, displayName = tostring(properties.displayName), scope = tostring(properties.scope), enforcementMode = tostring(properties.enforcementMode), effect = tostring(properties.parameters.effect.value), definitionId = tolower(tostring(properties.policyDefinitionId))" }
    $queries['advisor'] = "advisorresources | where type =~ 'microsoft.advisor/recommendations' | where tostring(properties.impactedField) =~ 'Microsoft.ContainerService/managedClusters' | project id, resourceId = tolower(tostring(properties.resourceMetadata.resourceId)), category = tostring(properties.category), impact = tostring(properties.impact), problem = tostring(properties.shortDescription.problem), solution = tostring(properties.shortDescription.solution), subCategory = tostring(properties.extendedProperties.recommendationSubCategory), retirementDate = tostring(properties.extendedProperties.retirementDate), learnMore = tostring(properties.learnMoreLink)"
    $queries['defender'] = "securityresources | where type =~ 'microsoft.security/assessments' | where tostring(properties.status.code) =~ 'Unhealthy' | extend resourceId = tolower(coalesce(tostring(properties.resourceDetails.Id), tostring(properties.resourceDetails.ResourceId))) | where resourceId contains '/providers/microsoft.containerservice/managedclusters/' | project id, resourceId, recommendation = tostring(properties.displayName), severity = tostring(properties.metadata.severity), categories = strcat_array(properties.metadata.categories, ', '), remediation = tostring(properties.metadata.remediationDescription), cause = tostring(properties.status.cause), link = tostring(properties.links.azurePortal)"
    $queries
}
