---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACOrphanedIdentity.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Get-AACOrphanedIdentity
---

# Get-AACOrphanedIdentity

## SYNOPSIS

Finds the identities nobody uses any more - role assignments to deleted principals, user-assigned identities attached to nothing, managed identities of deleted resources, service principals that haven't signed in for months, app registrations with only expired credentials or no owners - and the access each still holds.

## SYNTAX

### __AllParameterSets

```
Get-AACOrphanedIdentity [[-SubscriptionId] <string[]>] [[-ManagementGroupId] <string[]>]
 [[-Kind] <string[]>] [[-Severity] <string[]>] [[-InactiveDays] <int>] [[-CsvPath] <string>]
 [[-HtmlPath] <string>] [[-PdfPath] <string>] [[-Title] <string>] [-SkipEntra] [-PassThru]
 [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Reads, read-only:

```text
  Resource Graph     user-assigned identities and the resources (and
                     AKS clusters' kubelets) that use them; every
                     resource's system-assigned identity; the role
                     assignments and definitions, tenant-wide
  Resource Manager   the federated credentials of each user-assigned
                     identity nothing uses (a workload identity
                     federation counts as use)
  Microsoft Graph    the role assignments' principals (which still
                     exist), the tenant's application service
                     principals and managed identities, the app
                     registrations (credentials, owners) and the
                     service principals' last sign-in
```

Each identity (AAC.OrphanedIdentity) has its kind, why it looks
unused, its last sign-in, its role assignments (how many, which),
credentials and owners, and what to do. Severity follows the access
left behind: High with a privileged role (Owner, Contributor, User
Access Administrator, RBAC Administrator), Medium with other roles
or only expired credentials, Low with none.

"Unused" is an inference: a quarterly job, a disaster-recovery
pipeline or a break-glass app can be quiet for months. Confirm with
the owner, disable before deleting. Reader in Azure; for Entra ID
Directory.Read.All and Application.Read.All, and AuditLog.Read.All
with Entra ID P1 for sign-in activity. -SkipEntra checks the
user-assigned identities only.

## EXAMPLES

### Example 1

```powershell
Get-AACOrphanedIdentity
```

Every identity that looks unused, the ones with the most access first.

### Example 2

```powershell
Get-AACOrphanedIdentity -Kind DeletedPrincipal -NoDisplay | Select-Object PrincipalId, Roles
```

The role assignments left behind by deleted principals.

### Example 3

```powershell
Get-AACOrphanedIdentity -Kind Application -InactiveDays 180 -CsvPath .\out\StaleApps.csv
```

Applications not signed in for six months, for review.

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
  Position: 5
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
  Position: 6
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -InactiveDays

A service principal not signed in for this many days is inactive.
Default 90.

```yaml
Type: System.Int32
DefaultValue: 90
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

### -Kind

Only these kinds: DeletedPrincipal, UserAssignedIdentity,
ManagedIdentity, Application.

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
  Position: 7
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Severity

Only these severities (High, Medium, Low).

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
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

### -SkipEntra

Don't read Entra ID (Microsoft Graph): user-assigned identities
only.

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

Only these subscriptions (role assignments at management group and
root scope always count).

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
DefaultValue: "'Orphaned identities'"
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.OrphanedIdentity

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACOrphanedIdentity.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
