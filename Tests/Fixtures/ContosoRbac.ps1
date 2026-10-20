<#
    Made-up role assignments for RoleAssignment.Tests.ps1, as Resource
    Graph, PIM, Get-AACDirectoryObject and Microsoft Graph return them.
    sub-prod sits under mg-platform; sub-out under mg-other.

      a1   root            Owner               Platform Admins (group)     -> Info
      a2   mg-platform     Owner               Alice (user, permanent)     -> Medium (direct Owner; standing)
      a3   mg-other        Reader              Bob                         -> out of scope when scoped
      a4   sub-prod        Owner               app-orders (application)    -> High (workload as Owner)
      a5   sub-prod        Contributor         Carol (guest)               -> High (privileged guest)
      a6   rg-app          Reader              vm-web-01 (system MI)       -> Info
      a7   rg-app          Contoso Access Granter  uai-deploy (user MI)    -> Info, privileged (can grant access)
      a8   sub-prod        Reader              deleted user                -> Medium (orphaned)
      a9   sub-prod        a deleted role      Alice                       -> Medium (orphaned)
      a10  vm1             Contoso Super Admin Dave                        -> High (custom role = Owner)
      a11  sub-prod        Reader              Vendor Monitoring (another tenant's app) -> Info
      a12  sub-out         Owner               Alice                       -> out of scope when scoped
      a13  sub-prod        Owner               Erin, activated in PIM      -> Medium (direct Owner), not standing
      e1   sub-prod        Owner               Frank, eligible in PIM      -> Info (and a duplicate, and an inherited copy, ignored)
    Custom roles: Contoso Super Admin (every action), Contoso Access Granter
    (writes role assignments), Contoso Unused, Contoso Policy Role (used by a
    DeployIfNotExists policy only).
#>
function Get-AACContosoRbac {
    $prod = '11111111-1111-1111-1111-111111111111'
    $out = '99999999-9999-9999-9999-999999999999'
    $def = { param([string] $Guid) "/providers/microsoft.authorization/roledefinitions/$Guid" }
    $owner = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'; $contributor = 'b24988ac-6180-42a0-ab88-20f7382dd24c'; $reader = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'; $uaa = '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9'
    $super = 'c0000000-0000-0000-0000-000000000001'; $granter = 'c0000000-0000-0000-0000-000000000002'; $unused = 'c0000000-0000-0000-0000-000000000003'; $policyRole = 'c0000000-0000-0000-0000-000000000004'
    $mg = { param([string] $Name) "/providers/microsoft.management/managementgroups/$Name" }
    $rg = "/subscriptions/$prod/resourcegroups/rg-app"
    $a = { param([string] $Id, [string] $Principal, [string] $Type, [string] $Role, [string] $Scope) @{ id = "/ra/$Id"; principalId = $Principal; principalType = $Type; roleId = "/subscriptions/$prod/providers/microsoft.authorization/roledefinitions/$Role"; scope = $Scope; condition = ''; createdOn = '2026-03-01T10:00:00Z'; createdBy = 'u-admin'; description = '' } }
    $role = { param([string] $Guid, [string] $Name, [string] $Type, [object[]] $Actions, [object[]] $NotActions = @()) @{ id = (& $def $Guid); name = $Guid; roleName = $Name; roleType = $Type; permissions = @(@{ actions = $Actions; notActions = $NotActions }); assignableScopes = @("/subscriptions/$prod") } }
    $user = { param([string] $Name, [string] $UserType = 'Member') @{ '@odata.type' = '#microsoft.graph.user'; displayName = $Name; userPrincipalName = "$($Name.ToLowerInvariant())@contoso.example"; userType = $UserType } }
    $sp = { param([string] $Name, [string] $Kind, [string] $Tenant = 't-1') @{ '@odata.type' = '#microsoft.graph.servicePrincipal'; displayName = $Name; servicePrincipalType = $Kind; appOwnerOrganizationId = $Tenant } }
    @{
        TenantId      = 't-1'
        Prod          = $prod
        Subscriptions = @(
            @{ subscriptionId = $prod; name = 'sub-prod'; state = 'Enabled'; chain = @(@{ name = 'mg-platform' }, @{ name = 'mg-root' }) }
            @{ subscriptionId = $out; name = 'sub-out'; state = 'Enabled'; chain = @(@{ name = 'mg-other' }, @{ name = 'mg-root' }) }
        )
        Read          = @{
            Errors = @{}
            Rows   = @{
                roleAssignments  = @(
                    (& $a 'a1' 'g-admins' 'Group' $owner '/')
                    (& $a 'a2' 'u-alice' 'User' $owner (& $mg 'mg-platform'))
                    (& $a 'a3' 'u-bob' 'User' $reader (& $mg 'mg-other'))
                    (& $a 'a4' 'sp-app' 'ServicePrincipal' $owner "/subscriptions/$prod")
                    (& $a 'a5' 'guest-carol' 'User' $contributor "/subscriptions/$prod")
                    (& $a 'a6' 'mi-sys' 'ServicePrincipal' $reader $rg)
                    (& $a 'a7' 'mi-user' 'ServicePrincipal' $granter $rg)
                    (& $a 'a8' 'p-deleted' 'User' $reader "/subscriptions/$prod")
                    (& $a 'a9' 'u-alice' 'User' 'dddddddd-0000-0000-0000-000000000000' "/subscriptions/$prod")
                    (& $a 'a10' 'u-dave' 'User' $super "$rg/providers/microsoft.compute/virtualmachines/vm1")
                    (& $a 'a11' 'sp-ext' 'ServicePrincipal' $reader "/subscriptions/$prod")
                    (& $a 'a12' 'u-alice' 'User' $owner "/subscriptions/$out")
                    (& $a 'a13' 'u-erin' 'User' $owner "/subscriptions/$prod")
                )
                roleDefinitions  = @(
                    (& $role $owner 'Owner' 'BuiltInRole' @('*'))
                    (& $role $contributor 'Contributor' 'BuiltInRole' @('*') @('Microsoft.Authorization/*/Delete', 'Microsoft.Authorization/*/Write', 'Microsoft.Authorization/elevateAccess/Action'))
                    (& $role $reader 'Reader' 'BuiltInRole' @('*/read'))
                    (& $role $uaa 'User Access Administrator' 'BuiltInRole' @('*/read', 'Microsoft.Authorization/*'))
                    (& $role $super 'Contoso Super Admin' 'CustomRole' @('*'))
                    (& $role $granter 'Contoso Access Granter' 'CustomRole' @('Microsoft.Authorization/roleAssignments/*', '*/read'))
                    (& $role $unused 'Contoso Unused' 'CustomRole' @('Microsoft.Compute/*/read'))
                    (& $role $policyRole 'Contoso Policy Role' 'CustomRole' @('Microsoft.Insights/diagnosticSettings/*'))
                )
                managementGroups = @(@{ name = 'mg-platform'; displayName = 'Platform' }, @{ name = 'mg-other'; displayName = 'Other' }, @{ name = 'mg-root'; displayName = 'Tenant Root Group' })
                userIdentities   = @(@{ principalId = 'mi-user' })
                policyRoles      = @(@{ role = (& $def $policyRole) })
            }
        }
        Pim           = @{
            Read      = $true
            Errors    = @()
            Instances = @(@{ id = 'i1'; properties = @{ assignmentType = 'Activated'; originRoleAssignmentId = '/ra/a13'; principalId = 'u-erin' } })
            Eligible  = @(
                @{ id = 'e1'; properties = @{ principalId = 'u-frank'; principalType = 'User'; roleDefinitionId = "/subscriptions/$prod/providers/Microsoft.Authorization/roleDefinitions/$owner"; scope = "/subscriptions/$prod"; memberType = 'Direct'; endDateTime = '2027-01-01T00:00:00Z' } }
                @{ id = 'e1-again'; properties = @{ principalId = 'u-frank'; principalType = 'User'; roleDefinitionId = "/subscriptions/$prod/providers/Microsoft.Authorization/roleDefinitions/$owner"; scope = "/subscriptions/$prod"; memberType = 'Direct'; endDateTime = '2027-01-01T00:00:00Z' } }
                @{ id = 'e2'; properties = @{ principalId = 'u-frank'; principalType = 'User'; roleDefinitionId = "/subscriptions/$prod/providers/Microsoft.Authorization/roleDefinitions/$reader"; scope = "/subscriptions/$prod"; memberType = 'Inherited' } }
            )
        }
        Directory     = @{ Error = ''; Objects = @{
                'g-admins'    = @{ '@odata.type' = '#microsoft.graph.group'; displayName = 'Platform Admins' }
                'u-alice'     = (& $user 'Alice'); 'u-bob' = (& $user 'Bob'); 'u-dave' = (& $user 'Dave'); 'u-erin' = (& $user 'Erin'); 'u-frank' = (& $user 'Frank'); 'u-admin' = (& $user 'Admin')
                'guest-carol' = (& $user 'Carol' 'Guest')
                'sp-app'      = (& $sp 'app-orders' 'Application'); 'sp-ext' = (& $sp 'Vendor Monitoring' 'Application' 't-vendor')
                'mi-sys'      = (& $sp 'vm-web-01' 'ManagedIdentity'); 'mi-user' = (& $sp 'uai-deploy' 'ManagedIdentity')
            } }
        Members       = @{ 'g-admins' = @{ Count = 3; Names = 'alice@contoso.example, bob@contoso.example, ops-bot' } }
    }
}
