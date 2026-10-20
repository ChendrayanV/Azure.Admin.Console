function Get-AACPolicyRemediationQuery {
    <#
    .SYNOPSIS
        The Azure Resource Graph queries behind Get-AACPolicyRemediation:
        the resources DeployIfNotExists and Modify policies find
        non-compliant (counted in the query, per assignment and policy),
        and the assignments.
    .DESCRIPTION
        Returns an ordered hashtable for Invoke-AACGraphBatch:
          fixable      per assignment, policy (reference) and effect: the
                       non-compliant resources and their subscriptions
          assignments  every assignment: name, scope, definition, identity
                       (tenant-wide, so management group assignments are
                       there)
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()

    [ordered]@{
        fixable     = "policyresources | where type =~ 'microsoft.policyinsights/policystates' | where tostring(properties.complianceState) == 'NonCompliant' | extend effect = tolower(tostring(properties.policyDefinitionAction)) | where effect in ('deployifnotexists', 'modify') | extend assignmentId = tolower(tostring(properties.policyAssignmentId)), definitionId = tolower(tostring(properties.policyDefinitionId)), referenceId = tostring(properties.policyDefinitionReferenceId), resourceId = tolower(tostring(properties.resourceId)) | summarize nonCompliant = dcount(resourceId), subscriptions = dcount(subscriptionId) by assignmentId, definitionId, referenceId, effect | extend id = strcat(assignmentId, '|', referenceId, '|', definitionId)"
        assignments = @{ Tenant = $true; Query = "policyresources | where type =~ 'microsoft.authorization/policyassignments' | project id = tolower(id), displayName = tostring(properties.displayName), scope = tolower(tostring(properties.scope)), definitionId = tolower(tostring(properties.policyDefinitionId)), identityType = tostring(identity.type), enforcement = tostring(properties.enforcementMode)" }
    }
}
