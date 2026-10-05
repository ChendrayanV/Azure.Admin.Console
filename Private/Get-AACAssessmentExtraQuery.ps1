function Get-AACAssessmentExtraQuery {
    <#
    .SYNOPSIS
        The Resource Graph queries of Invoke-AACAssessment besides its
        inventory sheets: the scope, every resource, the organization,
        Advisor (and retirements), Defender for Cloud, Azure Policy,
        support tickets and the diagrams' resources.
    .DESCRIPTION
        -Stage picks the set:
          Scope       subscriptions (with their management group chain) and
                      every management group (across the tenant)
          Estate      the resource types present, every resource, the
                      resource groups; Advisor unless -SkipAdvisor (only
                      the retirements then), Defender with -SecurityCenter,
                      Policy unless -SkipPolicy, support tickets
          Diagram     the resources the network diagram draws, with their
                      properties (every resource with -FullEnvironment)
        -Filter is Get-AACAssessmentQuery -Filter's resource group and tag
        filter; -ResourceGroupName also filters the containers, Advisor and
        Defender rows. Returns an ordered hashtable: name -> query (or
        @{ Query; Tenant = $true } for one that spans the tenant).
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Scope', 'Estate', 'Diagram')]
        [string] $Stage,

        [string] $Filter = '',

        [string[]] $ResourceGroupName,

        [switch] $SkipAdvisor,

        [switch] $SecurityCenter,

        [switch] $SkipPolicy,

        [switch] $FullEnvironment
    )

    $quote = { param([string] $Text) "'" + ($Text -replace '\\', '\\' -replace "'", "\'") + "'" }
    $groups = @($ResourceGroupName | Where-Object { $_ })
    $groupFilter = if ($groups.Count) { " | where resourceGroup in~ ($((@($groups | ForEach-Object { & $quote $_ })) -join ', '))" } else { '' }
    $queries = [ordered]@{}

    switch ($Stage) {
        'Scope' {
            $queries['subscriptions'] = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions' | project id, subscriptionId, name, state = tostring(properties.state), quotaId = tostring(properties.subscriptionPolicies.quotaId), chain = properties.managementGroupAncestorsChain, tags"
            $queries['managementGroups'] = @{ Tenant = $true; Query = "resourcecontainers | where type =~ 'microsoft.management/managementgroups' | project id, name, displayName = tostring(properties.displayName), parent = tostring(properties.details.parent.name)" }
        }
        'Estate' {
            $queries['types'] = "resources$Filter | summarize resources = count() by type = tolower(type), subscriptionId, location | extend id = strcat(type, '|', subscriptionId, '|', location)"
            $queries['resources'] = "resources$Filter | project id, name, type, kind, location, resourceGroup, subscriptionId, sku = tostring(sku.name), state = tostring(properties.provisioningState), tags"
            $queries['groups'] = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions/resourcegroups'$($groupFilter -replace 'resourceGroup', 'name') | project id, name, subscriptionId, location, tags"
            $advisor = "advisorresources | where type =~ 'microsoft.advisor/recommendations'$groupFilter | extend p = properties, subCategory = tostring(properties.extendedProperties.recommendationSubCategory)"
            if ($SkipAdvisor) { $advisor += " | where subCategory == 'ServiceUpgradeAndRetirement'" }
            $queries['advisor'] = "$advisor | project id, subscriptionId, resourceGroup, category = tostring(p.category), impact = tostring(p.impact), problem = tostring(p.shortDescription.problem), solution = tostring(p.shortDescription.solution), resourceId = tolower(tostring(p.resourceMetadata.resourceId)), impactedType = tostring(p.impactedField), impactedValue = tostring(p.impactedValue), savings = todouble(p.extendedProperties.annualSavingsAmount), savingsCurrency = tostring(p.extendedProperties.savingsCurrency), subCategory, retirementDate = tostring(p.extendedProperties.retirementDate), retirementFeature = tostring(p.extendedProperties.retirementFeatureName), lastUpdated = tostring(p.lastUpdated)"
            if ($SecurityCenter) {
                $queries['security'] = "securityresources | where type =~ 'microsoft.security/assessments' | where tostring(properties.status.code) =~ 'Unhealthy'$groupFilter | project id, subscriptionId, resourceGroup, resourceId = tolower(coalesce(tostring(properties.resourceDetails.Id), tostring(properties.resourceDetails.ResourceId))), recommendation = tostring(properties.displayName), severity = tostring(properties.metadata.severity), categories = strcat_array(properties.metadata.categories, ', '), remediation = tostring(properties.metadata.remediationDescription), since = tostring(properties.status.statusChangeDate)"
                $queries['secureScores'] = "securityresources | where type =~ 'microsoft.security/securescores' and name == 'ascScore' | project id, subscriptionId, current = todouble(properties.score.current), max = todouble(properties.score.max)"
            }
            if (-not $SkipPolicy) {
                # Summed per assignment and policy: a tenant can have millions of
                # states. The id column lets Resource Graph page the result.
                $stateGroups = if ($groups.Count) { " | where tostring(properties.resourceGroup) in~ ($((@($groups | ForEach-Object { & $quote $_ })) -join ', '))" } else { '' }
                $queries['policy'] = @(
                    "policyresources | where type =~ 'microsoft.policyinsights/policystates'$stateGroups"
                    '| extend state = tostring(properties.complianceState), assignmentId = tolower(tostring(properties.policyAssignmentId)), assignmentName = tostring(properties.policyAssignmentName), assignmentScope = tostring(properties.policyAssignmentScope), definitionId = tolower(tostring(properties.policyDefinitionId)), setId = tolower(tostring(properties.policySetDefinitionId)), effect = tostring(properties.policyDefinitionAction)'
                    "| summarize nonCompliant = countif(state =~ 'NonCompliant'), compliant = countif(state =~ 'Compliant'), exempt = countif(state =~ 'Exempt'), other = countif(state !in~ ('NonCompliant', 'Compliant', 'Exempt')), subscriptions = dcount(subscriptionId) by assignmentId, assignmentName, assignmentScope, definitionId, setId, effect"
                    "| join kind=leftouter (policyresources | where type =~ 'microsoft.authorization/policyassignments' | project assignmentId = tolower(id), assignment = tostring(properties.displayName)) on assignmentId"
                    "| join kind=leftouter (policyresources | where type =~ 'microsoft.authorization/policydefinitions' | project definitionId = tolower(id), policy = tostring(properties.displayName)) on definitionId"
                    "| join kind=leftouter (policyresources | where type =~ 'microsoft.authorization/policysetdefinitions' | project setId = tolower(id), policySet = tostring(properties.displayName)) on setId"
                    "| extend id = strcat(assignmentId, '|', definitionId) | project-away assignmentId1, definitionId1, setId1"
                ) -join ' '
            }
            $queries['supportTickets'] = "supportresources | where type =~ 'microsoft.support/supporttickets' | project id, subscriptionId, ticketId = tostring(properties.supportTicketId), ticketTitle = tostring(properties['title']), service = tostring(properties.serviceDisplayName), severity = tostring(properties.severity), status = tostring(properties.status), plan = tostring(properties.supportPlanType), created = tostring(properties.createdDate), modified = tostring(properties.modifiedDate)"
        }
        'Diagram' {
            $columns = '| project id, name, type, kind, location, resourceGroup, subscriptionId, sku, properties, tags'
            if ($FullEnvironment) {
                $queries['diagram'] = "resources$Filter | where isnotempty(resourceGroup) $columns"
            }
            else {
                $types = @(
                    'virtualnetworks', 'virtualnetworkgateways', 'localnetworkgateways', 'connections', 'expressroutecircuits', 'azurefirewalls', 'firewallpolicies', 'bastionhosts'
                    'applicationgateways', 'loadbalancers', 'natgateways', 'networksecuritygroups', 'routetables', 'privateendpoints', 'privatednszones', 'dnsresolvers'
                    'virtualwans', 'virtualhubs', 'vpngateways', 'expressroutegateways', 'vpnsites', 'ddosprotectionplans', 'publicipaddresses', 'frontdoors', 'trafficmanagerprofiles'
                ) | ForEach-Object { "'microsoft.network/$_'" }
                $queries['diagram'] = "resources$Filter | where type in~ ($($types -join ', ')) $columns"
            }
        }
    }
    $queries
}
