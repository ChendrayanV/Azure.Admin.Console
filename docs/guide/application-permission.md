# Application permission

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Get-AACApplicationPermission`](../Get-AACApplicationPermission.md) · [`New-AACApplicationPermission`](../New-AACApplicationPermission.md)

`Get-AACApplicationPermission` lists **everything an enterprise application or
managed identity can do** - in one place, where the portal spreads it over the
application's API permissions, Roles & admins, administrative units and each
Azure scope's Access control:

```powershell
Get-AACApplicationPermission -Identity 'My-Enterprise-App'
Get-AACApplicationPermission -Identity <app-id or object-id> -NoDisplay | Where-Object Kind -EQ 'Directory role'
Get-AACApplicationPermission -Identity '/subscriptions/<id>/resourceGroups/rg-app/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-app'
'app-one', 'app-two' | Get-AACApplicationPermission -HtmlPath .\AppPermissions.html -CsvPath .\AppPermissions.csv
```

- **Rows, by kind:** application permissions (each API's app roles -
  tenant-wide), delegated permissions (consented for everyone, or one user),
  directory roles with their scope (tenant, administrative unit with the
  objects it covers, or one object; direct or through a role-assignable group),
  PIM-eligible roles, Azure roles (direct or through a group; `-SkipAzure`
  leaves them out), owned applications and groups, group memberships, and API
  permissions the app registration asks for that were never granted.
- **Findings:** privileged application permissions (`Directory.ReadWrite.All`,
  `RoleManagement.ReadWrite.Directory`, `AppRoleAssignment.ReadWrite.All`,
  `Mail.Send`...), privileged directory roles at tenant scope, Azure Owner or
  User Access Administrator, Contributor on a subscription, privileged
  delegated scopes consented for everyone, owning another application.
- **Identity:** service principal object ID, application (client) ID, app
  registration object ID, display name, or the Azure resource ID of a
  user-assigned identity (or of a resource with a system-assigned one).
  `-View Permission|Finding|Summary`.

## Scoped group rights: New-AACApplicationPermission

`New-AACApplicationPermission` lets an enterprise application (or managed
identity) add and remove members in **specific groups only**. Microsoft Graph
application permissions are tenant-wide - `GroupMember.ReadWrite.All` covers
every group, and there is no "selected groups" version of it - so the same
rights are given with Entra's own scoping instead:

1. an **administrative unit** holding exactly the groups,
2. a **directory role** with just the group actions (a custom role, created
   or updated; or a built-in one, used as it is),
3. that role **assigned to the application on the unit** - not the tenant.

```powershell
Connect-AAC
New-AACApplicationPermission -ServicePrincipal 'My-Enterprise-App' -Group 'SG-Group-One', 'SG-Group-Two' -WhatIf   # the plan
New-AACApplicationPermission -ServicePrincipal 'My-Enterprise-App' -Group 'SG-Group-One', 'SG-Group-Two' -RemoveTenantWidePermission
New-AACApplicationPermission -ServicePrincipal 'func-myapp-prod' -Group 'SG-Group-One' -Access MemberRead
New-AACApplicationPermission -ServicePrincipal 'My-Enterprise-App' -Group 'SG-Group-One' -AllowedResourceAction 'microsoft.directory/groups/standard/read', 'microsoft.directory/groups/members/read', 'microsoft.directory/groups/members/update' -RoleName 'Group Member ReadWrite (Scoped)'
```

- **Idempotent:** what exists is read and only what is missing is written;
  the plan is shown and you are asked first (`-Force` or `-Confirm:$false`
  for pipelines, `-WhatIf` for the plan only). After the apply everything is
  read again; running the command again plans no changes.
- **Access:** `-Access MemberReadWrite` (default - the rights of
  `GroupMember.ReadWrite.All`), `MemberRead`, `MemberAndOwnerReadWrite`, or
  your own group actions with `-AllowedResourceAction`. `-RoleName` names the
  custom role, or picks a built-in one (`Groups Administrator`).
- **Findings** - what would undo the scope or not work: a tenant-wide Graph
  permission (`GroupMember.ReadWrite.All`, `Group.ReadWrite.All`,
  `Directory.ReadWrite.All` - `-RemoveTenantWidePermission` removes it), the
  same role at tenant scope, other objects in the unit, dynamic groups,
  role-assignable groups.
- `-RestrictedManagement` creates the unit with restricted management, so
  tenant-wide group administrators can't change its groups either.
- **Needs** Privileged Role Administrator (or Global Administrator) for the
  sign-in, and Microsoft Entra ID P1. The application's code doesn't change;
  its token may be cached for up to an hour (24 hours for a managed
  identity) before the change takes effect.
