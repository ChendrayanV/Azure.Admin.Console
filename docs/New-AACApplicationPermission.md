---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/New-AACApplicationPermission.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: New-AACApplicationPermission
---

# New-AACApplicationPermission

## SYNOPSIS

Lets an enterprise application or managed identity manage specific Entra groups only - not every group in the tenant - with an administrative unit, a custom (or built-in) directory role and a role assignment scoped to the unit. Plan, confirm, apply, verify.

## SYNTAX

### Access (Default)

```
New-AACApplicationPermission -ServicePrincipal <string> -Group <string[]> [-Access <string>]
 [-RoleName <string>] [-AdministrativeUnitName <string>] [-RestrictedManagement]
 [-RemoveTenantWidePermission] [-Force] [-PassThru] [-NoDisplay] [-WhatIf] [-Confirm]
```

### Custom

```
New-AACApplicationPermission -ServicePrincipal <string> -Group <string[]>
 -AllowedResourceAction <string[]> [-RoleName <string>] [-AdministrativeUnitName <string>]
 [-RestrictedManagement] [-RemoveTenantWidePermission] [-Force] [-PassThru] [-NoDisplay] [-WhatIf]
 [-Confirm]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Microsoft Graph application permissions are tenant-wide:
GroupMember.ReadWrite.All lets an application add and remove
members in every group, and there is no "selected groups" version
of it (as Sites.Selected is for SharePoint). The same rights, over
chosen groups only:

```text
  1. Administrative unit   holds exactly the groups
                           (-AdministrativeUnitName; created when
                           missing, -RestrictedManagement on creation)
  2. Directory role        only the group actions (-Access, or your
                           own -AllowedResourceAction); a custom role
                           (-RoleName) is created, or updated when its
                           actions differ; a built-in role is used as
                           it is
  3. Role assignment       the role to the application, scoped to the
                           administrative unit - not '/'
```

The application's code doesn't change: it still asks for a
https://graph.microsoft.com/.default token and calls
POST /groups/{id}/members/$ref. Any other group answers 403.

Like Deploy-AACStorageAccount, it plans first - what exists is read
and only what is missing is written - and shows the plan. Findings
say what would undo the scope: a tenant-wide Graph permission
(GroupMember.ReadWrite.All, Group.ReadWrite.All,
Directory.ReadWrite.All - removed with -RemoveTenantWidePermission),
the same role at tenant scope, other objects in the unit, dynamic or
role-assignable groups. You are asked before anything is written
(-Force, or -Confirm:$false, for pipelines); -WhatIf stops after the
plan. After the apply everything is read again: running the same
command again plans no changes.

Needs the Connect-AAC sign-in with Privileged Role Administrator
(or Global Administrator) - a service principal needs the Graph
permissions RoleManagement.ReadWrite.Directory,
AdministrativeUnit.ReadWrite.All, Application.Read.All and
Group.Read.All, and AppRoleAssignment.ReadWrite.All for
-RemoveTenantWidePermission. Custom roles and administrative units
need Microsoft Entra ID P1. An application may cache its token for
up to an hour (a managed identity up to 24 hours) before the change
takes effect.

## EXAMPLES

### Example 1

```powershell
New-AACApplicationPermission -ServicePrincipal 'My-Enterprise-App' -Group 'SG-Group-One', 'SG-Group-Two' -WhatIf
```

The plan: what would be created, and what would undo the scope.

### Example 2

```powershell
New-AACApplicationPermission -ServicePrincipal 'func-myapp-prod' -Group 'SG-Group-One' -RemoveTenantWidePermission
A managed identity (its Function App's name) gets member read/write on one group, and loses GroupMember.ReadWrite.All.
```

### Example 3

```powershell
New-AACApplicationPermission -ServicePrincipal 11111111-2222-3333-4444-555555555555 -Group 'SG-Group-One' -AllowedResourceAction 'microsoft.directory/groups/standard/read', 'microsoft.directory/groups/members/read' -RoleName 'Group Member Reader (Scoped)'
A custom role of your own, for an application found by its ID.
```

### Example 4

```powershell
New-AACApplicationPermission -ServicePrincipal 'My-Enterprise-App' -Group 'SG-Group-One' -RoleName 'Groups Administrator' -Force -NoDisplay
A built-in role, scoped to the unit, in a pipeline.
```

## PARAMETERS

### -Access

What the application may do in the groups:

```text
  MemberReadWrite          read the groups and their members, add
                           and remove members (default - the same
                           rights as GroupMember.ReadWrite.All)
  MemberRead               read the groups and their members
  MemberAndOwnerReadWrite  members and owners
```

```yaml
Type: System.String
DefaultValue: "'MemberReadWrite'"
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Access
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -AdministrativeUnitName

The administrative unit (created when missing). By default
'AU-\<application\>-Managed-Groups'.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -AllowedResourceAction

A custom role's actions instead of -Access, e.g.
microsoft.directory/groups/members/update. Only group actions
(microsoft.directory/groups...) can be given.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Custom
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Confirm



```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases:
- cf
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Force

Apply without asking.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Group

The groups the application may manage, by display name or object ID.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
Aliases:
- GroupName
- GroupId
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -NoDisplay

Return the result without showing the plan.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -PassThru

Show the plan and also return the result.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -RemoveTenantWidePermission

Remove the application's tenant-wide Graph permissions that would
override the scope (GroupMember.ReadWrite.All, Group.ReadWrite.All,
Directory.ReadWrite.All).

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -RestrictedManagement

Create the administrative unit with restricted management, so that
tenant-wide group administrators can't change its groups either.
Can only be chosen when the unit is created.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -RoleName

The directory role: a custom role's name (created when missing), or
a built-in role's (Groups Administrator...). By default
'Group access (scoped) - \<application\>'.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ServicePrincipal

The enterprise application or managed identity: its object ID, its
application (client) ID, or its display name.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases:
- ServicePrincipalName
- ServicePrincipalId
- AppId
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -WhatIf



```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases:
- wi
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.ApplicationPermission (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/New-AACApplicationPermission.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
