function Get-AACPolicyAssessmentQuery {
    <#
    .SYNOPSIS
        The Azure Resource Graph queries of Invoke-AACPolicyAssessment.
    .DESCRIPTION
        -Stage Discovery (tenant-wide, so what management groups assign to a
        subscription is there):
          subscriptions, managementGroups   the hierarchy
          assignments        every assignment: scope, definition, effect
                             parameters, enforcement, excluded scopes,
                             overrides, resource selectors, non-compliance
                             messages, identity, metadata, version
          exemptions         every exemption: assignment, policies, category,
                             expiry, metadata
          customDefinitions, customInitiatives   every custom definition and
                             initiative - assigned or not - with their
                             metadata, rule, members and groups
          roleDefinitions    every role definition's name
        -Stage Roles with -Id: the role assignments of these principal IDs
        (the policy assignments' managed identities).
        -Stage Compliance (in the subscriptions in scope): Azure Policy's
        compliance, counted as AzPolicyLens counts it - each resource once,
        at its worst state (NonCompliant, then Compliant, Conflict, Exempt):
          complianceBySubscription  per subscription
          complianceByAssignment    per assignment and subscription
          complianceByPolicy        per assignment, policy (reference) and
                                    subscription
        -Stage Definitions with -Id: the definitions and initiatives with
        those IDs (built-in ones the custom queries don't have).
        Every query keeps an id column, so Resource Graph pages it.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Discovery', 'Compliance', 'Definitions', 'Roles')]
        [string] $Stage,

        # Definition IDs (-Stage Definitions) or managed identities' principal IDs (-Stage Roles).
        [string[]] $Id = @()
    )

    $definitionColumns = 'id, name, type, displayName = tostring(properties.displayName), description = tostring(properties.description), policyType = tostring(properties.policyType), mode = tostring(properties.mode), version = tostring(properties.version), metadata = properties.metadata, parameters = properties.parameters, rule = properties.policyRule, members = properties.policyDefinitions, groups = properties.policyDefinitionGroups'
    # A resource's worst state: NonCompliant 300, Compliant 200, Conflict 100, Exempt 50.
    $weight = "extend complianceState = tostring(properties.complianceState), resourceId = tolower(tostring(properties.resourceId)) | extend stateWeight = case(complianceState == 'NonCompliant', 300, complianceState == 'Compliant', 200, complianceState == 'Conflict', 100, complianceState == 'Exempt', 50, 0)"
    $count = "nonCompliant = sumif(resources, worst == 300), compliant = sumif(resources, worst == 200), conflict = sumif(resources, worst == 100), exempt = sumif(resources, worst == 50)"
    $queries = [ordered]@{}
    switch ($Stage) {
        'Discovery' {
            $queries['subscriptions'] = @{ Tenant = $true; Query = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions' | project id, subscriptionId, name, state = tostring(properties.state), chain = properties.managementGroupAncestorsChain, tags" }
            $queries['managementGroups'] = @{ Tenant = $true; Query = "resourcecontainers | where type =~ 'microsoft.management/managementgroups' | project id, name, displayName = tostring(properties.displayName), parent = tostring(properties.details.parent.name), chain = properties.details.managementGroupAncestorsChain" }
            $queries['assignments'] = @{ Tenant = $true; Query = "policyresources | where type =~ 'microsoft.authorization/policyassignments' | project id, name, displayName = tostring(properties.displayName), description = tostring(properties.description), scope = tostring(properties.scope), definitionId = tostring(properties.policyDefinitionId), definitionVersion = tostring(properties.definitionVersion), parameters = properties.parameters, enforcement = tostring(properties.enforcementMode), notScopes = properties.notScopes, overrides = properties.overrides, resourceSelectors = properties.resourceSelectors, messages = properties.nonComplianceMessages, metadata = properties.metadata, identity, location" }
            $queries['exemptions'] = @{ Tenant = $true; Query = "policyresources | where type =~ 'microsoft.authorization/policyexemptions' | project id, name, displayName = tostring(properties.displayName), description = tostring(properties.description), assignmentId = tostring(properties.policyAssignmentId), referenceIds = properties.policyDefinitionReferenceIds, category = tostring(properties.exemptionCategory), expiresOn = tostring(properties.expiresOn), metadata = properties.metadata, resourceSelectors = properties.resourceSelectors, subscriptionId, resourceGroup" }
            $queries['customDefinitions'] = @{ Tenant = $true; Query = "policyresources | where type =~ 'microsoft.authorization/policydefinitions' | where tostring(properties.policyType) =~ 'Custom' | project $definitionColumns" }
            $queries['customInitiatives'] = @{ Tenant = $true; Query = "policyresources | where type =~ 'microsoft.authorization/policysetdefinitions' | where tostring(properties.policyType) =~ 'Custom' | project $definitionColumns" }
            $queries['roleDefinitions'] = @{ Tenant = $true; Query = "authorizationresources | where type =~ 'microsoft.authorization/roledefinitions' | project id, name, roleName = tostring(properties.roleName)" }
        }
        'Compliance' {
            $states = "policyresources | where type =~ 'microsoft.policyinsights/policystates' | $weight"
            $queries['complianceBySubscription'] = "$states | summarize worst = max(stateWeight) by resourceId, subscriptionId | summarize resources = count() by subscriptionId, worst | summarize $count by subscriptionId | extend id = subscriptionId"
            $queries['complianceByAssignment'] = "$states | extend assignmentId = tolower(tostring(properties.policyAssignmentId)) | summarize worst = max(stateWeight) by resourceId, assignmentId, subscriptionId | summarize resources = count() by assignmentId, subscriptionId, worst | summarize $count by assignmentId, subscriptionId | extend id = strcat(assignmentId, '|', subscriptionId)"
            $queries['complianceByPolicy'] = "$states | extend assignmentId = tolower(tostring(properties.policyAssignmentId)), definitionId = tolower(tostring(properties.policyDefinitionId)), referenceId = tostring(properties.policyDefinitionReferenceId), effect = tolower(tostring(properties.policyDefinitionAction)) | summarize worst = max(stateWeight), effect = take_any(effect) by resourceId, assignmentId, definitionId, referenceId, subscriptionId | summarize resources = count(), effect = take_any(effect) by assignmentId, definitionId, referenceId, subscriptionId, worst | summarize $count, effect = take_any(effect) by assignmentId, definitionId, referenceId, subscriptionId | extend id = strcat(assignmentId, '|', referenceId, '|', definitionId, '|', subscriptionId)"
        }
        { $_ -in 'Definitions', 'Roles' } {
            $quote = { param([string] $Text) "'" + ($Text -replace '\\', '\\' -replace "'", "\'") + "'" }
            $ids = @($Id | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object -Unique)
            for ($i = 0; $i -lt $ids.Count; $i += 100) {
                $chunk = @($ids[$i..([Math]::Min($i + 99, $ids.Count - 1))] | ForEach-Object { & $quote $_ }) -join ', '
                if ($Stage -eq 'Definitions') {
                    $queries["definitions$i"] = @{ Tenant = $true; Query = "policyresources | where type in~ ('microsoft.authorization/policydefinitions', 'microsoft.authorization/policysetdefinitions') | where tolower(id) in ($chunk) | project $definitionColumns" }
                }
                else {
                    # The role assignments of the policy assignments' managed identities.
                    $queries["roles$i"] = @{ Tenant = $true; Query = "authorizationresources | where type =~ 'microsoft.authorization/roleassignments' | extend principalId = tolower(tostring(properties.principalId)) | where principalId in ($chunk) | project id, principalId, roleDefinitionId = tolower(tostring(properties.roleDefinitionId)), scope = tostring(properties.scope)" }
                }
            }
        }
    }
    $queries
}
