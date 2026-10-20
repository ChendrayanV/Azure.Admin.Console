---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACRoleAssignment.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Get-AACRoleAssignment
---

# Get-AACRoleAssignment

## SYNOPSIS

Lists every Azure role assignment - root, management groups, subscriptions, resource groups and resources - with who holds it and what they are, what the role can do, how far it reaches, whether it is standing or PIM, the groups' members, who created it - and flags orphaned assignments, risky grants and custom roles that are unused or as powerful as Owner.

## SYNTAX

### __AllParameterSets

```
Get-AACRoleAssignment [[-SubscriptionId] <string[]>] [[-ManagementGroupId] <string[]>]
 [[-PrincipalType] <string[]>] [[-RoleName] <string[]>] [[-ScopeType] <string[]>]
 [[-CsvPath] <string>] [[-HtmlPath] <string>] [[-PdfPath] <string>] [[-Title] <string>]
 [-Privileged] [-WithFinding] [-ExpandGroup] [-IncludeCustomRole] [-SkipPim] [-SkipEntra]
 [-PassThru] [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

The inventory under the access review: where Get-AACAccessReview
says what to fix, this lists everything as it is. Reads, read-only:

```text
  Resource Graph   every role assignment and definition (tenant-
                   wide, so management group and root assignments
                   that reach the scope count), the management
                   groups, the user-assigned identities and the
                   roles policies use
  PIM              each subscription's eligible assignments and
                   which active ones were activated just in time
  Microsoft Graph  the principals and the assignments' creators;
                   with -ExpandGroup, each group's members
                   (transitive)
```

Each assignment (AAC.RoleAssignment):

```text
  Principal        name, sign-in name, and its type: User, Guest,
                   Group, Application, Application (external - another
                   tenant's), Managed identity (system- or
                   user-assigned), or Deleted
  Role             name; Built-in or Custom; Privileged (Owner,
                   Contributor, User Access Administrator, RBAC
                   Administrator, or a custom role with every action
                   or able to grant access); CanWriteRoleAssignments
  Scope            type (Root, Management group, Subscription,
                   Resource group, Resource), name, and Reach - Direct,
                   or "Inherited by N subscription(s)"
  Assignment       Permanent, Activated (PIM) or Eligible (PIM)
  More             Members and MemberNames (groups, with
                   -ExpandGroup), Condition (ABAC), CreatedOn,
                   CreatedBy, EndsOn (eligible)
  Findings         and the worst one's Severity: High for a deleted
                   principal with a privileged role, a guest with
                   one, an application as Owner on a subscription or
                   above, a custom role equivalent to Owner; Medium for
                   orphaned assignments and Owner or User Access
                   Administrator given to a user directly; Low for
                   standing privileged access a person could hold
                   eligible
```

The report also lists the custom roles (AAC.CustomRole): their
assignments, whether a policy uses them, unused, equivalent to
Owner, able to grant access.

Reader on the scope; for Entra ID Directory.Read.All (GroupMember.
Read.All for -ExpandGroup). What Graph or PIM refuses is left out,
and said. -SkipEntra reads Azure only.

## EXAMPLES

### Example 1

```powershell
Get-AACRoleAssignment
```

Every role assignment the account can see, those with findings first.

### Example 2

```powershell
Get-AACRoleAssignment -SubscriptionId $sub -ExpandGroup -HtmlPath .\Rbac.html
```

One subscription's assignments - including those inherited from management groups - with each group's members.

### Example 3

```powershell
Get-AACRoleAssignment -PrincipalType Guest, Deleted -Privileged -NoDisplay | Select-Object Principal, Role, Scope
```

Privileged guests and orphaned privileged assignments.

### Example 4

```powershell
Get-AACRoleAssignment -RoleName 'Owner' -ScopeType ManagementGroup, Subscription -CsvPath .\Owners.csv
```

Who is Owner at the top of the hierarchy, for review.

## PARAMETERS

### -CsvPath

Write the assignments to this CSV file.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 5
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ExpandGroup

Read each group's members (transitive, up to 200 groups).

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

### -HtmlPath

Write an interactive HTML report (assignments and custom roles).

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 6
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -IncludeCustomRole

Also return the custom roles (AAC.CustomRole), after the
assignments.

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

### -ManagementGroupId

Only the subscriptions under these management groups (at any depth).

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 1
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -NoDisplay

Return the assignments without showing the view.

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

### -NoPaging

Show the whole view at once.

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

Show the view and also return the assignments.

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

### -PdfPath

Write a PDF report.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 7
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -PrincipalType

Only these principals: User, Guest, Group, Application,
ManagedIdentity, Deleted.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 2
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Privileged

Only privileged roles.

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

Only these roles; wildcards work ('\*Owner\*').

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: true
Aliases: []
ParameterSets:
- Name: (All)
  Position: 3
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ScopeType

Only assignments at these scopes: Root, ManagementGroup,
Subscription, ResourceGroup, Resource.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 4
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SkipEntra

Don't read Entra ID: principals are shown by ID and type.

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

### -SkipPim

Don't read PIM (eligible and activated assignments).

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

### -SubscriptionId

Only these subscriptions (and the management group and root
assignments that reach them).

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Title

The reports' title.

```yaml
Type: System.String
DefaultValue: "'Azure role assignments'"
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 8
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -WithFinding

Only assignments with a finding.

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.RoleAssignment (and AAC.CustomRole, with -IncludeCustomRole)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACRoleAssignment.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
