function Get-AACRoleAssignmentQuery {
    <#
    .SYNOPSIS
        The Azure Resource Graph queries behind Get-AACRoleAssignment: every
        role assignment and definition (tenant-wide, so management group
        and root assignments count), the management groups, the
        user-assigned identities and the roles policy definitions use.
    .DESCRIPTION
        Returns an ordered hashtable for Invoke-AACGraphBatch.

          roleAssignments  each assignment: principal, role, scope,
                           condition, created on and by
          roleDefinitions  each role: name, type, permissions, assignable
                           scopes
          managementGroups names and display names
          userIdentities   the user-assigned identities' principal IDs
                           (tells user-assigned from system-assigned)
          policyRoles      the roles DeployIfNotExists and Modify policies
                           give their identity (a custom role used only
                           there is not unused)
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()

    [ordered]@{
        roleAssignments  = @{ Tenant = $true; Query = "authorizationresources | where type =~ 'microsoft.authorization/roleassignments' | project id = tolower(id), principalId = tolower(tostring(properties.principalId)), principalType = tostring(properties.principalType), roleId = tolower(tostring(properties.roleDefinitionId)), scope = tolower(tostring(properties.scope)), condition = tostring(properties.condition), createdOn = tostring(properties.createdOn), createdBy = tolower(tostring(properties.createdBy)), description = tostring(properties.description)" }
        roleDefinitions  = @{ Tenant = $true; Query = "authorizationresources | where type =~ 'microsoft.authorization/roledefinitions' | project id = tolower(id), name = tolower(name), roleName = tostring(properties.roleName), roleType = tostring(properties.type), permissions = properties.permissions, assignableScopes = properties.assignableScopes" }
        managementGroups = @{ Tenant = $true; Query = "resourcecontainers | where type =~ 'microsoft.management/managementgroups' | project name = tolower(name), displayName = tostring(properties.displayName)" }
        userIdentities   = @{ Tenant = $true; Query = "resources | where type =~ 'microsoft.managedidentity/userassignedidentities' | project principalId = tolower(tostring(properties.principalId))" }
        policyRoles      = @{ Tenant = $true; Query = "policyresources | where type =~ 'microsoft.authorization/policydefinitions' | extend roles = properties.policyRule.then.details.roleDefinitionIds | where array_length(roles) > 0 | mv-expand role = roles | project role = tolower(tostring(role))" }
    }
}
