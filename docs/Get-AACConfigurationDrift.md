---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACConfigurationDrift.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Get-AACConfigurationDrift
---

# Get-AACConfigurationDrift

## SYNOPSIS

Finds configuration drift: what's deployed against what it should be - a baseline you saved, desired-state rules (yours, or a built-in security baseline), or your Terraform code - with who or what changed it, how to put it right, and whether drift is trending better or worse.

## SYNTAX

### __AllParameterSets

```
Get-AACConfigurationDrift [[-SubscriptionId] <string[]>] [[-ManagementGroupId] <string[]>]
 [[-ResourceGroupName] <string[]>] [[-ResourceType] <string[]>] [[-BaselinePath] <string>]
 [[-SaveBaseline] <string>] [[-DesiredStatePath] <string>] [[-TerraformPlanPath] <string>]
 [[-HistoryPath] <string>] [[-MaxResources] <int>] [[-CsvPath] <string>] [[-HtmlPath] <string>]
 [[-PdfPath] <string>] [[-Title] <string>] [-UseDefaultRules] [-PassThru] [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Desired state, one or more of:

```text
  -BaselinePath      a snapshot saved earlier with -SaveBaseline:
                     every setting of every resource (SKU, tags,
                     properties - not provisioning states, timestamps
                     or counters) compared; resources created or
                     deleted since
  -DesiredStatePath  your rules (.psd1 or .json): a resource type, a
                     setting, what it must be (Equals, NotEquals, In,
                     Match, Exists), a severity and the fix
  -UseDefaultRules   a built-in security baseline: TLS 1.2, HTTPS
                     only, no anonymous blob access, soft delete and
                     purge protection, RBAC, no local or shared-key
                     authentication, no admin users...
  -TerraformPlanPath a plan's JSON (terraform show -json plan.out):
                     its resource_drift - what changed outside
                     Terraform
```

-SaveBaseline writes today's snapshot, for the next run's
-BaselinePath (it can be the same file: compare, then save).

Why it drifted: Resource Graph's change history (14 days) - who
changed the setting, when, and whether a person (Manual), an
application or pipeline (Automation) or Azure (a platform update).
The strategy follows: Fix (a rule), Revert or Re-deploy (a manual
change), Update the baseline (an intended or platform change),
Review (unknown).

-HistoryPath keeps a CSV line per run - resources checked, drifted,
high - and the report shows whether drift is better or worse than
last time.

Read-only: nothing is changed or remediated; the fixes are the
operator's to apply (through infrastructure as code, ideally).
Reader is enough.

## EXAMPLES

### Example 1

```powershell
Get-AACConfigurationDrift -ResourceGroupName 'rg-app-prod' -SaveBaseline .\baseline\app-prod.json
```

Save the production app's configuration as its baseline.

### Example 2

```powershell
Get-AACConfigurationDrift -ResourceGroupName 'rg-app-prod' -BaselinePath .\baseline\app-prod.json -HistoryPath .\baseline\history.csv
```

What changed since, who changed it, and the trend.

### Example 3

```powershell
Get-AACConfigurationDrift -UseDefaultRules -DesiredStatePath .\desired.psd1 -HtmlPath .\out\Drift.html
```

The built-in security baseline and your own rules, as a report.

### Example 4

```powershell
terraform show -json plan.out > plan.json; Get-AACConfigurationDrift -TerraformPlanPath .\plan.json
```

What changed outside Terraform, and who changed it.

## PARAMETERS

### -BaselinePath

A snapshot saved earlier with -SaveBaseline, to compare with.

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

### -CsvPath

Write the drift to this CSV file.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 10
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -DesiredStatePath

Desired-state rules (.psd1 or .json).

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

### -HistoryPath

A CSV file that keeps a line per run, for the trend.

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

### -HtmlPath

Write an interactive HTML report.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 11
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

### -MaxResources

At most this many resources (1 to 20000; 5000 by default).

```yaml
Type: System.Int32
DefaultValue: 5000
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

### -NoDisplay

Return the drift without showing the view.

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

Show the view and also return the drift.

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
  Position: 12
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

### -ResourceType

Only these resource types (wildcards work).

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

### -SaveBaseline

Save today's snapshot to this file.

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

### -TerraformPlanPath

A Terraform plan in JSON: its resource_drift.

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

### -Title

The reports' title.

```yaml
Type: System.String
DefaultValue: "'Configuration drift'"
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 13
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -UseDefaultRules

Check the built-in security baseline too.

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

### AAC.ConfigurationDrift

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACConfigurationDrift.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
