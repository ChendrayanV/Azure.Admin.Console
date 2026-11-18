---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACManagedIdentity.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Get-AACManagedIdentity
---

# Get-AACManagedIdentity

## SYNOPSIS

Lists every managed identity - system-assigned (on a resource or a policy assignment) and user-assigned - with what it belongs to, what it is attached to, its Azure roles, its API permissions (Microsoft Graph and other APIs) and federated credentials, and findings for the access that matters.

## SYNTAX

### __AllParameterSets

```
Get-AACManagedIdentity [[-SubscriptionId] <string[]>] [[-ManagementGroupId] <string[]>]
 [[-Name] <string[]>] [[-ResourceGroupName] <string[]>] [[-SharedLimit] <int>]
 [[-MaxIdentity] <int>] [[-CsvPath] <string>] [[-HtmlPath] <string>] [[-PdfPath] <string>]
 [[-Title] <string>] [-SystemAssigned] [-UserAssigned] [-SkipEntra] [-PassThru] [-NoDisplay]
 [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Read-only. Reads:

```text
  Resource Graph     the user-assigned identities, every resource's
                     system-assigned identity, the resources (and AKS
                     kubelets) and policy assignments using each
                     user-assigned identity, and the role assignments
                     and definitions (tenant-wide, so management group
                     and root assignments count)
  Resource Manager   each user-assigned identity's federated
                     credentials (workload identity federation)
  Microsoft Graph    each identity's API permissions (app role
                     assignments) and their names - the Azure portal
                     doesn't show these anywhere for a managed
                     identity (-SkipEntra leaves them out)
```

Each identity (AAC.ManagedIdentity) has its kind, resource type,
subscription, resource group, location and tags; for a user-assigned
one, the resources it is attached to and its federated credentials;
its Azure roles and API permissions, the privileged ones apart; and
findings:

```text
  High    an API permission that can take over the tenant
          (RoleManagement.ReadWrite.Directory,
          AppRoleAssignment.ReadWrite.All, Application.ReadWrite.All);
          Owner, User Access Administrator or Role Based Access
          Control Administrator on a subscription or above
  Medium  another privileged API permission (Directory.ReadWrite.All,
          Mail.Send, Sites.FullControl.All...); Contributor on a
          subscription or above; a user-assigned identity shared by
          more than -SharedLimit resources with privileged access, or
          attached to nothing yet still holding access; a federated
          credential on an identity with privileged access
  Low     a user-assigned identity attached to nothing, without
          access; a resource with both a system-assigned and
          user-assigned identities
```

The objects pipe into Get-AACApplicationPermission (by PrincipalId)
for everything else an identity holds: directory roles, PIM,
ownership, group membership.

Reader in Azure; Application.Read.All (or Directory Readers) in Entra
ID for the API permissions. Part of it that can't be read is a
notice, not an error.

## EXAMPLES

### Example 1

```powershell
Get-AACManagedIdentity
```

Every managed identity, the riskiest first, with an overview.

### Example 2

```powershell
Get-AACManagedIdentity -UserAssigned -ResourceGroupName 'rg-app-*' -NoDisplay | Select-Object Name, AttachedTo, AzureRoles, ApiPermissions
```

The user-assigned identities of the application resource groups.

### Example 3

```powershell
Get-AACManagedIdentity -NoDisplay | Where-Object ApiPermissions | Select-Object Name, Kind, Permissions
```

The managed identities with Microsoft Graph (or other API) permissions.

### Example 4

```powershell
Get-AACManagedIdentity -Name 'func-orders' -NoDisplay | Get-AACApplicationPermission
```

Everything one identity holds, directory roles included.

### Example 5

```powershell
Get-AACManagedIdentity -ManagementGroupId mg-landingzones -HtmlPath .\ManagedIdentities.html
A report for one management group.
```

## PARAMETERS

### -CsvPath

Write the identities to this CSV file.

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

### -HtmlPath

Write an interactive HTML report.

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

### -MaxIdentity

Read the API permissions of at most this many identities (one
Microsoft Graph call each). Default 1000.

```yaml
Type: System.Int32
DefaultValue: 1000
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

### -Name

Only identities with these names (wildcards allowed). A
system-assigned identity has its resource's name.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: true
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

### -NoDisplay

Return the identities without showing the view.

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

Show the view and also return the identities.

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
  Position: 8
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ResourceGroupName

Only identities in these resource groups (wildcards allowed).

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

### -SharedLimit

A user-assigned identity with privileged access attached to more
resources than this is a finding. Default 10.

```yaml
Type: System.Int32
DefaultValue: 10
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

Don't read the API permissions from Microsoft Graph - faster, and
needs no Entra ID access.

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

Only these subscriptions.

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

### -SystemAssigned

Only system-assigned identities (of resources and policy assignments).

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

### -Title

The reports' title.

```yaml
Type: System.String
DefaultValue: "'Managed identities'"
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 9
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -UserAssigned

Only user-assigned identities.

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

### AAC.ManagedIdentity

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACManagedIdentity.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
