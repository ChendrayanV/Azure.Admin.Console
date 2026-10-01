---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACAssignedPolicy.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Get-AACAssignedPolicy
---

# Get-AACAssignedPolicy

## SYNOPSIS

Every Azure Policy assignment with its parameters - the default, assigned and effective value of each - and the resource types the policy applies to, with a Spectre.Console view, objects, and CSV and interactive HTML reports.

## SYNTAX

### __AllParameterSets

```
Get-AACAssignedPolicy [[-ManagementGroupId] <string[]>] [[-SubscriptionId] <string[]>]
 [[-AssignmentName] <string[]>] [[-CsvPath] <string>] [[-HtmlPath] <string>] [[-Title] <string>]
 [-PassThru] [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

An inventory of what is assigned, not of compliance (for that, see
Get-AACPolicyState). Reads the assignments, the policy definitions
and initiatives they assign and the initiatives' member policies
with Azure Resource Graph - a handful of queries however many
assignments there are, with the Connect-AAC sign-in; Reader is
enough, no Az modules. A definition Resource Graph doesn't return is
read from Azure Resource Manager.

Without parameters: every assignment the account can see. With
-SubscriptionId or -ManagementGroupId: the assignments that apply
there - at that scope or below it (its resource groups, subscriptions,
child management groups) and those inherited from the management
groups above it (Inherited = True), as the Azure portal lists them.
-AssignmentName keeps the assignments whose name or display name
matches (wildcards).

One row per assignment and parameter (AAC.AssignedPolicy):

```text
  AssignmentName, AssignmentDisplayName, ScopeType (Management
  group, Subscription, Resource group, Resource), ScopeName,
  Inherited, EnforcementMode, DefinitionType (Policy or PolicySet),
  DefinitionName, DefinitionDisplayName, PolicyType (BuiltIn,
  Custom, Static), Category, ResourceType, ParameterName,
  ParameterDisplayName, ParameterType, DefaultValue, AssignedValue,
  EffectiveValue, ValueSource (Assigned, Default, Not set),
  AllowedValues, NotScopes, AssignmentScope, AssignmentId and
  DefinitionId
```

A list is written as its items joined with ', ', an object as
compact JSON. A policy without parameters is one row with no
parameter, so every assignment is listed.

ResourceType is what the policy's rule targets: the types in its
"field": "type" conditions, with [parameters()] resolved to the
effective values (so "Not allowed resource types" lists the types
it denies), else the types of the property aliases it reads, else
'All except ...' for a rule that only leaves types out ("Allowed
resource types": every type except those allowed), or 'All'.
For an initiative, a row shows the types of the member policies that
use its parameter - 'All' when one of them applies to every type.

What you get depends on where the command runs:

```text
  at the prompt    tiles, the assignments by scope with their
                   enforcement and resource types, the resource
                   types assigned most, and each assignment's
                   parameters as a tree - assigned values in green,
                   defaults in grey - a page at a time
  piped onward     the rows, with no view
  -PassThru        the view and the rows
  -NoDisplay       the rows only
```

-CsvPath writes the rows. -HtmlPath writes an interactive report:
tiles, charts, a table of the assignments and one of every
parameter, searchable, filterable and downloadable as CSV. With
either, the console shows only the progress and the files written.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Get-AACAssignedPolicy
```

Every policy assignment you can see, with its parameters and resource types.

### Example 2

```powershell
Get-AACAssignedPolicy -SubscriptionId '00000000-0000-0000-0000-000000000000' -CsvPath .\assignedPolicyInventory.csv
```

What applies to one subscription - its own assignments and those inherited from management groups - to CSV.

### Example 3

```powershell
Get-AACAssignedPolicy -ManagementGroupId 'mg-landingzones' -HtmlPath .\out\AssignedPolicy.html
```

Everything assigned at, above or below a management group, as an interactive HTML report.

### Example 4

```powershell
Get-AACAssignedPolicy -NoDisplay | Where-Object { $_.ValueSource -eq 'Assigned' -and $_.AssignedValue -ne $_.DefaultValue }
```

The parameters set to something other than their default.

### Example 5

```powershell
Get-AACAssignedPolicy -NoDisplay | Where-Object ResourceType -Like '*Microsoft.Storage/storageAccounts*' | Select-Object AssignmentDisplayName, DefinitionDisplayName -Unique
```

The assignments with a policy for storage accounts.

## PARAMETERS

### -AssignmentName

Only the assignments whose name or display name matches; wildcards
work, e.g. '\*ISO\*'.

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

### -CsvPath

Write every row to this CSV file. Alias: OutputPath.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases:
- OutputPath
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

### -HtmlPath

Write an interactive HTML report to this file.

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

### -ManagementGroupId

Only the assignments that apply to these management groups (their
ID, the name in the portal's URL).

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

### -SubscriptionId

Only the assignments that apply to these subscriptions.

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

The HTML report's title.

```yaml
Type: System.String
DefaultValue: "'Assigned Azure Policy'"
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.AssignedPolicy (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACAssignedPolicy.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
