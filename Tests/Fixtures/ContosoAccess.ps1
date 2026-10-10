<#
    Made-up Contoso access for AccessReview.Tests.ps1 - ConvertTo-AACAccessReview's
    inputs, as Resource Graph, Resource Manager and Microsoft Graph return
    them (9 Oct 2026; sub-prod in scope, under mg-prod):

      Azure RBAC
        ada   Owner, sub-prod, permanent - last sign-in 200 days ago
        bob   Contributor, mg-prod, permanent - no changes made
        ops   (group) Reader, sub-prod
        sp-deploy  Owner, sub-prod
        gus   (guest) Owner, rg-app
        a deleted principal, Contributor, rg-app
        eve   Contributor, sub-prod - activated in PIM
        dan   (disabled) Contributor, rg-app
        mi-app (managed identity) 'Ops Admin' (custom, '*'), rg-app
        ivy   Contributor, sub-prod - no changes made
        zed   Owner, another subscription (out of scope)
        ada   eligible Owner, sub-prod
      Classic: old@contoso.example, co-administrator
      Entra ID: ada Global Administrator (permanent), gus User Administrator
        (permanent), eve Global Administrator (activated), bob Global
        Administrator (eligible)
      Graph application permissions: app-sync RoleManagement.ReadWrite.Directory,
        app-mail Mail.Read, app-ok User.ReadBasic.All
#>
function Get-AACContosoAccess {
    $sub = '11111111-1111-1111-1111-111111111111'
    $other = '99999999-9999-9999-9999-999999999999'
    $now = [datetime]'2026-10-09T12:00:00Z'
    $role = @{ Owner = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'; Contributor = 'b24988ac-6180-42a0-ab88-20f7382dd24c'; Reader = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'; OpsAdmin = 'c0ffee00-0000-0000-0000-000000000001' }
    $def = { param([string] $Name, [string] $Guid, [string] $Type, [string[]] $Actions) @{ id = "/providers/microsoft.authorization/roledefinitions/$Guid"; roleName = $Name; roleType = $Type; permissions = @(@{ actions = $Actions }) } }
    $id = { param([string] $Name) '{0}-0000-0000-0000-000000000000' -f ('{0:x8}' -f [Math]::Abs($Name.GetHashCode() % 99999999)) }
    $p = @{}
    foreach ($n in 'ada', 'bob', 'ops', 'sp-deploy', 'gus', 'gone', 'eve', 'dan', 'mi-app', 'ivy', 'zed', 'app-sync', 'app-mail', 'app-ok') { $p[$n] = ('{0:D8}-0000-0000-0000-000000000000' -f ([array]::IndexOf(@('ada', 'bob', 'ops', 'sp-deploy', 'gus', 'gone', 'eve', 'dan', 'mi-app', 'ivy', 'zed', 'app-sync', 'app-mail', 'app-ok'), $n) + 1)) }
    $assign = { param([string] $Key, [string] $Who, [string] $Type, [string] $Role, [string] $Scope) @{ id = "/providers/microsoft.authorization/roleassignments/$Key"; principalId = $p[$Who]; principalType = $Type; roleId = "/subscriptions/$sub/providers/microsoft.authorization/roledefinitions/$Role"; scope = $Scope; createdOn = '2025-01-01T00:00:00Z' } }
    $rg = "/subscriptions/$sub/resourcegroups/rg-app"
    $user = { param([string] $Who, [string] $Name, [string] $Type = 'Member', $Enabled = $true) @{ '@odata.type' = '#microsoft.graph.user'; id = $p[$Who]; displayName = $Name; userPrincipalName = "$Who@contoso.example"; userType = $Type; accountEnabled = $Enabled } }
    $app = { param([string] $Who, [string] $Name, [string] $Kind = 'Application') @{ '@odata.type' = '#microsoft.graph.servicePrincipal'; id = $p[$Who]; displayName = $Name; appId = "app-$Who"; servicePrincipalType = $Kind } }
    $directory = @{}
    foreach ($o in @(
            (& $user 'ada' 'Ada Lovelace'), (& $user 'bob' 'Bob Builder'), @{ '@odata.type' = '#microsoft.graph.group'; id = $p['ops']; displayName = 'grp-ops' }
            (& $app 'sp-deploy' 'sp-deploy'), (& $user 'gus' 'Gus Guest' 'Guest'), (& $user 'eve' 'Eve Online'), (& $user 'dan' 'Dan Dormant' 'Member' $false)
            (& $app 'mi-app' 'mi-app' 'ManagedIdentity'), (& $user 'ivy' 'Ivy Idle'), (& $app 'app-sync' 'app-sync'), (& $app 'app-mail' 'app-mail'), (& $app 'app-ok' 'app-ok')
        )) { $directory[$o.id] = $o }
    @{
        Now       = $now
        Sub       = $sub
        Principal = $p
        Input     = @{
            Assignment        = @(
                (& $assign 'a1' 'ada' 'User' $role.Owner "/subscriptions/$sub")
                (& $assign 'a2' 'bob' 'User' $role.Contributor '/providers/microsoft.management/managementgroups/mg-prod')
                (& $assign 'a3' 'ops' 'Group' $role.Reader "/subscriptions/$sub")
                (& $assign 'a4' 'sp-deploy' 'ServicePrincipal' $role.Owner "/subscriptions/$sub")
                (& $assign 'a5' 'gus' 'User' $role.Owner $rg)
                (& $assign 'a6' 'gone' 'User' $role.Contributor $rg)
                (& $assign 'a7' 'eve' 'User' $role.Contributor "/subscriptions/$sub")
                (& $assign 'a8' 'dan' 'User' $role.Contributor $rg)
                (& $assign 'a9' 'mi-app' 'ServicePrincipal' $role.OpsAdmin $rg)
                (& $assign 'a10' 'ivy' 'User' $role.Contributor "/subscriptions/$sub")
                (& $assign 'a11' 'zed' 'User' $role.Owner "/subscriptions/$other")
            )
            Definition        = @((& $def 'Owner' $role.Owner 'BuiltInRole' @('*')), (& $def 'Contributor' $role.Contributor 'BuiltInRole' @('*')), (& $def 'Reader' $role.Reader 'BuiltInRole' @('*/read')), (& $def 'Ops Admin' $role.OpsAdmin 'CustomRole' @('*')))
            Eligibility       = @(@{ id = 'e1'; properties = @{ principalId = $p['ada']; principalType = 'User'; roleDefinitionId = "/subscriptions/$sub/providers/Microsoft.Authorization/roleDefinitions/$($role.Owner)"; scope = "/subscriptions/$sub"; startDateTime = '2026-01-01T00:00:00Z' } })
            ScheduleInstance  = @(@{ id = 'i7'; properties = @{ assignmentType = 'Activated'; originRoleAssignmentId = '/providers/microsoft.authorization/roleassignments/a7' } }, @{ id = 'i1'; properties = @{ assignmentType = 'Assigned'; originRoleAssignmentId = '/providers/microsoft.authorization/roleassignments/a1' } })
            ClassicAdmin      = @(@{ SubscriptionId = $sub; Items = @(@{ id = 'c1'; properties = @{ emailAddress = 'old@contoso.example'; role = 'CoAdministrator' } }) })
            Directory         = $directory
            SignIn            = @{ $p['ada'] = $now.AddDays(-200); $p['ivy'] = $now.AddDays(-2); $p['bob'] = $now.AddDays(-1) }
            Activity          = @{ 'ada@contoso.example' = $now.AddDays(-3); 'app-sp-deploy' = $now.AddDays(-1); 'eve@contoso.example' = $now.AddDays(-5); 'dan@contoso.example' = $now.AddDays(-4); 'gus@contoso.example' = $now.AddDays(-6); 'app-mi-app' = $now.AddDays(-1) }
            ActivityDays      = 30
            EntraDefinition   = @(@{ id = 'ga'; displayName = 'Global Administrator'; templateId = '62e90394-69f5-4237-9190-012177145e10' }, @{ id = 'ua'; displayName = 'User Administrator'; templateId = 'fe930be7-5e62-47db-91af-98c3a49a38b1' })
            EntraAssignment   = @(@{ id = 'r1'; principalId = $p['ada']; roleDefinitionId = 'ga' }, @{ id = 'r2'; principalId = $p['gus']; roleDefinitionId = 'ua' }, @{ id = 'r3'; principalId = $p['eve']; roleDefinitionId = 'ga' })
            EntraEligibility  = @(@{ id = 'r4'; principalId = $p['bob']; roleDefinitionId = 'ga' })
            EntraActivated    = @("$($p['eve'])|ga")
            AppGrant          = @(@{ id = 'g1'; principalId = $p['app-sync']; appRoleId = 'role-rm' }, @{ id = 'g2'; principalId = $p['app-mail']; appRoleId = 'role-mail' }, @{ id = 'g3'; principalId = $p['app-ok']; appRoleId = 'role-basic' })
            GraphAppRole      = @{ 'role-rm' = 'RoleManagement.ReadWrite.Directory'; 'role-mail' = 'Mail.Read'; 'role-basic' = 'User.ReadBasic.All' }
            SubscriptionName  = @{ $sub = 'sub-prod'; $other = 'sub-other' }
            SubscriptionChain = @{ $sub = @('mg-prod', 'contoso') }
            InScope           = @($sub)
            Now               = $now
        }
    }
}
