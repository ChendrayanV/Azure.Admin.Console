<#
    What a made-up Contoso enterprise application holds, as Microsoft Graph
    returns it, for the Get-AACApplicationPermission tests.

      My-Enterprise-App   Graph application permissions User.Read.All and
                          GroupMember.ReadWrite.All; delegated User.Read and
                          Mail.Send consented for everyone; a custom role on
                          the administrative unit AU-Apps (SG-Group-One),
                          Groups Administrator and Directory Readers at tenant
                          scope; in the role-assignable group GRP-Role
                          (Application Administrator) and GRP-Plain; owns the
                          application Other-App; its app registration also asks
                          for Sites.Read.All and Files.Read, never granted.
                          PIM eligibility can't be read (no Graph scope for it).
      func-twins          two service principals with this name
#>
function Get-AACContosoApplicationGrant {
    $sp = 'a1a1a1a1-0000-0000-0000-000000000001'
    $graph = 'b2b2b2b2-0000-0000-0000-000000000002'
    $graphSp = @{
        id = $graph; appId = '00000003-0000-0000-c000-000000000000'; displayName = 'Microsoft Graph'
        appRoles = @(
            @{ id = 'c1c1c1c1-0000-0000-0000-000000000001'; value = 'GroupMember.ReadWrite.All'; displayName = 'Read and write all group memberships' }
            @{ id = 'c1c1c1c1-0000-0000-0000-000000000002'; value = 'User.Read.All'; displayName = 'Read all users'' full profiles' }
            @{ id = 'c1c1c1c1-0000-0000-0000-000000000003'; value = 'Sites.Read.All'; displayName = 'Read items in all site collections' }
        )
        oauth2PermissionScopes = @(
            @{ id = 'd1d1d1d1-0000-0000-0000-000000000001'; value = 'User.Read' }
            @{ id = 'd1d1d1d1-0000-0000-0000-000000000002'; value = 'Files.Read' }
            @{ id = 'd1d1d1d1-0000-0000-0000-000000000003'; value = 'Mail.Send' }
        )
    }
    $role = { param($Name, $Scope, [bool] $BuiltIn = $true, [string[]] $Actions = @()) @{ id = [guid]::NewGuid().ToString(); roleDefinitionId = [guid]::NewGuid().ToString(); directoryScopeId = $Scope; roleDefinition = @{ displayName = $Name; isBuiltIn = $BuiltIn; rolePermissions = @(@{ allowedResourceActions = $Actions }) } } }
    @{
        PrincipalId = $sp
        Answers     = @{
            "servicePrincipals/$sp"                                         = @{ id = $sp; appId = 'e1e1e1e1-0000-0000-0000-000000000001'; displayName = 'My-Enterprise-App'; servicePrincipalType = 'Application'; appOwnerOrganizationId = 'f1f1f1f1-0000-0000-0000-000000000001'; accountEnabled = $true }
            "servicePrincipals(appId='e1e1e1e1-0000-0000-0000-000000000001')" = @{ id = $sp; appId = 'e1e1e1e1-0000-0000-0000-000000000001'; displayName = 'My-Enterprise-App'; servicePrincipalType = 'Application'; accountEnabled = $true }
            "servicePrincipals(appId='00000003-0000-0000-c000-000000000000')" = $graphSp
            "servicePrincipals/$graph"                                      = $graphSp
            'applications/a9a9a9a9-0000-0000-0000-000000000009'             = @{ appId = 'e1e1e1e1-0000-0000-0000-000000000001' }
            "applications(appId='e1e1e1e1-0000-0000-0000-000000000001')"     = @{ id = 'a9a9a9a9-0000-0000-0000-000000000009'; displayName = 'My-Enterprise-App'; requiredResourceAccess = @(@{ resourceAppId = '00000003-0000-0000-c000-000000000000'; resourceAccess = @(
                            @{ id = 'c1c1c1c1-0000-0000-0000-000000000001'; type = 'Role' }, @{ id = 'c1c1c1c1-0000-0000-0000-000000000003'; type = 'Role' }
                            @{ id = 'd1d1d1d1-0000-0000-0000-000000000001'; type = 'Scope' }, @{ id = 'd1d1d1d1-0000-0000-0000-000000000002'; type = 'Scope' }
                        )
                    })
            }
            "filter|My-Enterprise-App"                                      = @(@{ id = $sp; appId = 'e1e1e1e1-0000-0000-0000-000000000001'; displayName = 'My-Enterprise-App'; servicePrincipalType = 'Application' })
            "filter|func-twins"                                             = @(@{ id = 'a1a1a1a1-0000-0000-0000-000000000002'; displayName = 'func-twins'; servicePrincipalType = 'ManagedIdentity' }, @{ id = 'a1a1a1a1-0000-0000-0000-000000000003'; displayName = 'func-twins'; servicePrincipalType = 'ManagedIdentity' })
            "servicePrincipals/$sp/appRoleAssignments"                      = @(
                @{ id = 'ara-1'; resourceId = $graph; resourceDisplayName = 'Microsoft Graph'; appRoleId = 'c1c1c1c1-0000-0000-0000-000000000001'; createdDateTime = '2025-01-10T00:00:00Z' }
                @{ id = 'ara-2'; resourceId = $graph; resourceDisplayName = 'Microsoft Graph'; appRoleId = 'c1c1c1c1-0000-0000-0000-000000000002'; createdDateTime = '2025-01-10T00:00:00Z' }
            )
            "grants|$sp"                                                    = @(@{ id = 'grant-1'; clientId = $sp; resourceId = $graph; consentType = 'AllPrincipals'; scope = 'User.Read Mail.Send' })
            "roles|$sp"                                                     = @(
                (& $role 'Group access (scoped) - My-Enterprise-App' '/administrativeUnits/a7a7a7a7-0000-0000-0000-000000000007' $false @('microsoft.directory/groups/members/update'))
                (& $role 'Groups Administrator' '/')
                (& $role 'Directory Readers' '/')
            )
            'roles|a5a5a5a5-0000-0000-0000-000000000005'                     = @((& $role 'Application Administrator' '/'))
            "servicePrincipals/$sp/transitiveMemberOf"                      = @(
                @{ '@odata.type' = '#microsoft.graph.group'; id = 'a5a5a5a5-0000-0000-0000-000000000005'; displayName = 'GRP-Role'; isAssignableToRole = $true }
                @{ '@odata.type' = '#microsoft.graph.group'; id = 'a6a6a6a6-0000-0000-0000-000000000006'; displayName = 'GRP-Plain'; isAssignableToRole = $false }
            )
            "servicePrincipals/$sp/ownedObjects"                            = @(@{ id = 'a8a8a8a8-0000-0000-0000-000000000008'; displayName = 'Other-App' })
            'directory/administrativeUnits/a7a7a7a7-0000-0000-0000-000000000007' = @{ id = 'a7a7a7a7-0000-0000-0000-000000000007'; displayName = 'AU-Apps' }
            'directory/administrativeUnits/a7a7a7a7-0000-0000-0000-000000000007/members' = @(@{ id = 'g1'; displayName = 'SG-Group-One' })
        }
        Objects     = @{ 'a8a8a8a8-0000-0000-0000-000000000008' = @{ '@odata.type' = '#microsoft.graph.application'; id = 'a8a8a8a8-0000-0000-0000-000000000008'; displayName = 'Other-App' } }
        Azure       = @{
            $sp                                    = @(@{ Role = 'Contributor'; Scope = 'subscription Contoso Production'; Level = 'Subscription'; ScopeId = '/subscriptions/s-1'; Id = 'ra-1' })
            'a6a6a6a6-0000-0000-0000-000000000006' = @(@{ Role = 'Reader'; Scope = 'resource group rg-app (Contoso Production)'; Level = 'Resource group'; ScopeId = '/subscriptions/s-1/resourceGroups/rg-app'; Id = 'ra-2' })
        }
    }
}

# Read-AACGraphQuery's answer: @{ Data (name -> list or object); Errors (name -> reason) }.
function Get-AACContosoApplicationGrantAnswer {
    param([hashtable] $Data, [System.Collections.IDictionary] $Query)
    $out = @{ Data = @{}; Errors = @{} }
    foreach ($name in $Query.Keys) {
        $uri = [System.Uri]::UnescapeDataString([string]$Query[$name]).Replace('https://graph.microsoft.com/v1.0/', '')
        $path = ($uri -split '\?', 2)[0]
        $key = if ($uri -match "^servicePrincipals\?\`$filter=displayName eq '([^']+)'") { "filter|$($Matches[1])" }
        elseif ($uri -match "^oauth2PermissionGrants\?\`$filter=clientId eq '([^']+)'") { "grants|$($Matches[1])" }
        elseif ($uri -match "^roleManagement/directory/roleAssignments\?\`$filter=principalId eq '([^']+)'") { "roles|$($Matches[1])" }
        elseif ($path -like 'roleManagement/directory/roleEligibilitySchedules') { $out.Errors[$name] = '{"errorCode":"PermissionScopeNotGranted","message":"Authorization failed due to missing permission scope RoleEligibilitySchedule.Read.Directory,RoleManagement.Read.Directory."}'; continue }
        else { $path }
        if ($Data.Answers.Contains($key)) { $out.Data[$name] = $Data.Answers[$key] }
        elseif ($key -like 'filter|*') { $out.Data[$name] = @() }
        else { $out.Errors[$name] = 'Resource does not exist (404).' }
    }
    $out
}
