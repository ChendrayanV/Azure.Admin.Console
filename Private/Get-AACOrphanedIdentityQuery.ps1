function Get-AACOrphanedIdentityQuery {
    <#
    .SYNOPSIS
        The queries behind Get-AACOrphanedIdentity: Azure Resource Graph for
        the user-assigned identities and what uses them, every resource's
        system-assigned identity, and the role assignments and definitions;
        Microsoft Graph for the service principals, managed identities, app
        registrations and their sign-in activity.
    .DESCRIPTION
        Returns @{ Graph (Resource Graph queries; the role assignments and
        definitions are read tenant-wide, so management group and root
        assignments count); Entra (Microsoft Graph URIs) }.

          userIdentities    user-assigned identities: principal and client ID
          attached          resources with user-assigned identities, and AKS
                            clusters' kubelet identity
          systemIdentities  resources with a system-assigned identity
          roleAssignments   every role assignment: principal, role, scope
          roleDefinitions   role names
          servicePrincipals the tenant's application service principals
          managedIdentities managed identities' service principals (with
                            the resource ID they belong to)
          applications      app registrations: credentials, owners
          signIns           service principals' last sign-in (beta report;
                            needs Entra ID P1)
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $graph = [ordered]@{
        userIdentities   = "resources | where type =~ 'microsoft.managedidentity/userassignedidentities' | project id = tolower(id), name, resourceGroup, subscriptionId, location, principalId = tostring(properties.principalId), clientId = tostring(properties.clientId)"
        attached         = "resources | where isnotnull(identity.userAssignedIdentities) or isnotempty(tostring(properties.identityProfile.kubeletidentity.resourceId)) | project id = tolower(id), identities = identity.userAssignedIdentities, kubelet = tolower(tostring(properties.identityProfile.kubeletidentity.resourceId))"
        systemIdentities = "resources | where isnotempty(tostring(identity.principalId)) | project id = tolower(id), principalId = tostring(identity.principalId)"
        roleAssignments  = @{ Tenant = $true; Query = "authorizationresources | where type =~ 'microsoft.authorization/roleassignments' | project id, principalId = tostring(properties.principalId), principalType = tostring(properties.principalType), roleId = tolower(tostring(properties.roleDefinitionId)), scope = tolower(tostring(properties.scope)), createdOn = tostring(properties.createdOn)" }
        roleDefinitions  = @{ Tenant = $true; Query = "authorizationresources | where type =~ 'microsoft.authorization/roledefinitions' | project id = tolower(id), roleName = tostring(properties.roleName)" }
    }
    $v1 = 'https://graph.microsoft.com/v1.0'
    $entra = [ordered]@{
        servicePrincipals = "$v1/servicePrincipals?`$filter=servicePrincipalType eq 'Application'&`$select=id,appId,displayName,accountEnabled,appOwnerOrganizationId,createdDateTime,passwordCredentials,keyCredentials&`$top=999"
        managedIdentities = "$v1/servicePrincipals?`$filter=servicePrincipalType eq 'ManagedIdentity'&`$select=id,appId,displayName,alternativeNames,accountEnabled&`$top=999"
        applications      = "$v1/applications?`$select=id,appId,displayName,createdDateTime,passwordCredentials,keyCredentials&`$expand=owners(`$select=id)&`$top=999"
        signIns           = 'https://graph.microsoft.com/beta/reports/servicePrincipalSignInActivities?$top=999'
    }
    @{ Graph = $graph; Entra = $entra }
}
