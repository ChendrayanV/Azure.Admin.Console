---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACAccessReview.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Get-AACAccessReview
---

# Get-AACAccessReview

## SYNOPSIS

A least-privilege access review of Azure and Entra ID: every Azure RBAC assignment (permanent, PIM-activated and eligible), classic administrator, Entra ID directory role and Microsoft Graph application permission - with who uses their access, what's too broad or standing, and a recommendation for each - ready to attest.

## SYNTAX

### __AllParameterSets

```
Get-AACAccessReview [[-SubscriptionId] <string[]>] [[-ManagementGroupId] <string[]>]
 [[-ActivityDays] <int>] [[-Severity] <string[]>] [[-CsvPath] <string>] [[-HtmlPath] <string>]
 [[-PdfPath] <string>] [[-Title] <string>] [-SkipEntra] [-PrivilegedOnly] [-PassThru] [-NoDisplay]
 [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Reads, read-only:

```text
  Azure RBAC         every role assignment and definition (Resource
                     Graph, tenant-wide - so management group and
                     root assignments that reach the scope count)
  PIM                each subscription's eligible assignments and
                     which active ones were activated just in time
  Classic admins     each subscription's (co-)administrators
  Activity           each subscription's Activity Log for the last
                     -ActivityDays (30): who made changes, so unused
                     write access shows
  Entra ID           the principals (users, guests, groups, service
                     principals, managed identities - and the deleted
                     ones), privileged users' last sign-in, the
                     directory roles (active, activated, eligible),
                     and the application permissions granted on
                     Microsoft Graph
```

One row per assignment (AAC.AccessAssignment), each with its
findings - standing privileged access that should be just-in-time,
privileged guests, applications that can grant access or take over
the tenant, disabled and dormant accounts, orphaned assignments,
unused write access, wildcard custom roles, classic co-admins, too
many Global Administrators, roles given to users directly - the
worst finding's severity, a recommendation - Remove, Make eligible
(PIM), Narrow the scope or role, Review usage, Use a group, or
Keep - and the Action: what to do, in so many words.

Service principals and managed identities are judged as the
workloads they are: their elevated access is as much a risk as a
person's (a leaked secret or a compromised workload acts with it,
no MFA asked), but PIM needs a person to activate a role, so they
are never told to be made eligible. They are told how to narrow
the role and scope - Role Based Access Control Administrator with a
condition in place of Owner, resource groups in place of the
subscription - and how to protect the credential. Write access they
haven't used in -ActivityDays is "Review usage", not "Remove": a
monthly job or a disaster-recovery pipeline is quiet for weeks.

For an attestation: -CsvPath writes every row with empty Decision
and Reviewer columns to fill in and sign off; -HtmlPath and -PdfPath
write the review as a report.

Needs Reader on the scope; Microsoft Graph Directory.Read.All,
RoleManagement.Read.Directory, Application.Read.All and (for last
sign-ins) AuditLog.Read.All - what Graph refuses is left out, and
said. -SkipEntra reads Azure only.

## EXAMPLES

### Example 1

```powershell
Get-AACAccessReview -PrivilegedOnly
```

Who holds privileged access, how, and what to change.

### Example 2

```powershell
Get-AACAccessReview -ManagementGroupId 'mg-corp' -CsvPath .\out\AccessReview.csv -HtmlPath .\out\AccessReview.html
```

An attestation file and report for a management group.

### Example 3

```powershell
Get-AACAccessReview -NoDisplay | Where-Object Recommendation -EQ 'Make eligible (PIM)' | Select-Object Principal, Role, Scope
```

The standing access to move into PIM.

## PARAMETERS

### -ActivityDays

How many days of Activity Log to read for unused access (0 to 90; 30
by default; 0 skips it).

```yaml
Type: System.Int32
DefaultValue: 30
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

### -CsvPath

Write every row to this CSV file - with Decision and Reviewer
columns for the sign-off.

```yaml
Type: System.String
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

### -HtmlPath

Write an interactive HTML report.

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

Return the rows without showing the view.

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

Show the view and also return the rows.

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
  Position: 6
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -PrivilegedOnly

Only privileged access (Owner, Contributor, User Access
Administrator, RBAC Administrator, equivalent custom roles,
privileged Entra roles and Graph permissions).

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

### -Severity

Only rows of these severities.

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

Don't read Entra ID roles and Graph application permissions (Azure
RBAC is still reviewed; principals are still looked up).

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

### -Title

The reports' title.

```yaml
Type: System.String
DefaultValue: "'Azure access review'"
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.AccessAssignment

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACAccessReview.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
