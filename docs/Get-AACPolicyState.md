---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACPolicyState.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Get-AACPolicyState
---

# Get-AACPolicyState

## SYNOPSIS

Azure Policy compliance for every resource - one row per resource and policy - by management group, subscription or resource group, with a Spectre.Console view, objects, and CSV, PDF and interactive HTML reports.

## SYNTAX

### __AllParameterSets

```
Get-AACPolicyState [[-ManagementGroupId] <string[]>] [[-SubscriptionId] <string[]>]
 [[-ResourceGroupName] <string[]>] [[-ComplianceState] <string[]>] [[-CsvPath] <string>]
 [[-PdfPath] <string>] [[-HtmlPath] <string>] [[-Title] <string>] [-PassThru] [-NoDisplay]
 [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Reads the Azure Policy states with an Azure Resource Graph KQL query
(policyresources; Reader is enough, no Az modules), with the
policies' and initiatives' display names, and the assignments' names,
scopes and enforcement (read tenant-wide, as many are assigned at a
management group):

```text
  -ManagementGroupId   every subscription under these management
                       groups
  -SubscriptionId      these subscriptions
  -ResourceGroupName   only these resource groups (with either, or
                       in every subscription you can see)
  neither              every subscription you can see
```

-ComplianceState keeps only those states (NonCompliant, Compliant,
Exempt, Unknown, Conflict, Error) - in the query itself.

One row per resource and policy (AAC.PolicyState): ComplianceState,
Resource, ResourceType, ResourceGroup, SubscriptionName, Location,
Policy, PolicySet (the initiative), Assignment, AssignmentScope,
Enforcement, Effect, EvaluatedAt, and the IDs. From them: each
resource's compliance (non-compliant when any policy finds it so),
each assignment's, subscription's, resource group's and policy's.
Rolled up exactly as the Azure portal does: a resource's state
across its policies is the one that ranks first - Non-compliant,
Compliant, Error, Conflicting, Protected, Exempt, Unknown - and
compliance (%) is (Compliant + Exempt + Unknown + Protected
resources) / every resource evaluated; Not started states aren't
counted.

Get-AACSecurityPosture -Section Policy shows the policy headline
beside Defender for Cloud; this command is every state in detail.
Both read the same query.

What you get depends on where the command runs:

```text
  at the prompt    tiles, compliance per subscription and resource
                   group, the assignments (least compliant first),
                   the policies with non-compliant resources and
                   each of those resources - a page at a time
  piped onward     the rows, with no view
  -PassThru        the view and the rows
  -NoDisplay       the rows only
```

-CsvPath writes the rows. -HtmlPath writes an interactive report:
tiles and charts that filter tables of every state, the resources,
assignments, policies, subscriptions and resource groups - each
searchable and downloadable as CSV. -PdfPath writes a PDF: the
summary, the scopes, the assignments, and the non-compliant resources
by policy.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Get-AACPolicyState
```

Every policy state in every subscription you can see.

### Example 2

```powershell
Get-AACPolicyState -ManagementGroupId 'mg-landingzones' -HtmlPath .\out\Policy.html -PdfPath .\out\Policy.pdf -CsvPath .\out\Policy.csv
```

One management group, as an HTML report, a PDF and a CSV file.

### Example 3

```powershell
Get-AACPolicyState -SubscriptionId '00000000-0000-0000-0000-000000000000' -ResourceGroupName 'rg-app', 'rg-data'
```

Two resource groups of one subscription.

### Example 4

```powershell
Get-AACPolicyState -ComplianceState NonCompliant -NoDisplay | Group-Object Policy | Sort-Object Count -Descending | Select-Object Count, Name
```

The policies with the most non-compliant resources.

## PARAMETERS

### -ComplianceState

Only these compliance states: NonCompliant, Compliant, Exempt,
Unknown, Conflict, Error, Protected. Every state by default.

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

### -CsvPath

Write every row to this CSV file.

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

Write an interactive HTML report to this file.

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

### -ManagementGroupId

Only the subscriptions under these management groups (their IDs).

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

Show the whole view at once instead of a page at a time.

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

Write a PDF report to this file.

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

### -ResourceGroupName

Only these resource groups.

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

### -SubscriptionId

Only these subscriptions.

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

### -Title

The PDF and HTML reports' title.

```yaml
Type: System.String
DefaultValue: "'Azure Policy compliance'"
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

### AAC.PolicyState (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACPolicyState.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
