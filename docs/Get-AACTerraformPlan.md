---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACTerraformPlan.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Get-AACTerraformPlan
---

# Get-AACTerraformPlan

## SYNOPSIS

Reads a Terraform plan in JSON (terraform show -json) and flattens it into what will be created, updated, replaced, deleted, read, imported and moved - down to each attribute's before and after value - with a Spectre.Console view, objects, and CSV and interactive HTML reports.

## SYNTAX

### __AllParameterSets

```
Get-AACTerraformPlan [-Path] <string> [-Action <string[]>] [-Address <string[]>]
 [-ResourceType <string[]>] [-ExpandAttribute] [-IncludeDrift] [-CsvPath <string>]
 [-HtmlPath <string>] [-Title <string>] [-PassThru] [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Reads the whole plan file - every resource change, the outputs, and
what changed outside Terraform since the last run (resource_drift) -
and flattens it so it reads at a glance. Offline: no Azure sign-in,
no Terraform needed, nothing changed.

Make the JSON from a saved plan:

```text
  terraform plan -out tfplan
  terraform show -json tfplan > plan.json
```

A binary plan (tfplan), Terraform state or any other JSON is refused,
with what to run instead. UTF-16 files (Windows PowerShell's \>) are
read as well.

One row per resource (AAC.TerraformChange): Action, Address, Module,
Type, Name, Index, Provider, the Azure name, resource group,
location and ID where the resource has them, Reason (why it is
replaced or deleted), ReplaceOrder, ReplacePaths (the attributes
that force the replacement), PreviousAddress (moved), Importing,
Deposed (the old copy a failed create_before_destroy left behind),
ChangedAttributes and Attributes. Actions: Create, Update, Replace,
Delete, Read (data sources), Import, Move, Forget and NoOp. Outputs
are rows too, with Mode 'output' and Address 'output.\<name\>'.

-ExpandAttribute returns one row per changed attribute instead
(AAC.TerraformAttributeChange): Address, Attribute, Change (Added,
Removed, Modified, Known after apply, Reordered, Reformatted),
Before, After, ForcesReplacement and Sensitive. Nested values are flattened to a
path:

```text
  tags["cost.centre"]                       a map key
  site_config[0].always_on                  a nested block
  security_rule[name=ssh].destination_port_range
                                            a block in a list,
                                            by its name
  policy_rule{json}.then.effect             inside a JSON string
```

Updates and replacements list only what changes. Blocks in a list
are matched by content, then by name, then in order - a rule added
to an NSG doesn't show every rule after it as changed.

Checks (check blocks, preconditions, postconditions) that fail, or
can't be known until apply, are listed with their messages.

Sensitive values are never shown or returned: the plan JSON holds
them in clear text, and they come back as '(sensitive)'. Values
Terraform knows only after apply read '(known after apply)'.

What you get depends on where the command runs:

```text
  at the prompt    Terraform's summary (to add, change, destroy),
                   tiles, then the deletes, replacements, updates,
                   creates and the rest - each with its attribute
                   changes - the outputs and the drift, a page at
                   a time
  piped onward     the rows, with no view
  -PassThru        the view and the rows
  -NoDisplay       the rows only
```

-CsvPath writes the rows returned (resources, or attributes with
-ExpandAttribute). -HtmlPath writes an interactive report: tiles and
charts that filter tables of the resources, every attribute change,
the outputs and the drift - each searchable and downloadable as CSV.

## EXAMPLES

### Example 1

```powershell
terraform plan -out tfplan
terraform show -json tfplan > plan.json
Get-AACTerraformPlan -Path .\plan.json
```

What the plan changes, at the prompt.

### Example 2

```powershell
Get-AACTerraformPlan -Path .\plan.json -Action Delete, Replace -NoDisplay | Select-Object Address, ResourceName, Reason, ReplacePaths
```

Everything the plan destroys, and why.

### Example 3

```powershell
Get-AACTerraformPlan -Path .\plan.json -ExpandAttribute -NoDisplay | Where-Object ForcesReplacement
```

The attribute changes that force a replacement.

### Example 4

```powershell
Get-AACTerraformPlan -Path .\plan.json -HtmlPath .\out\Plan.html -CsvPath .\out\Plan.csv -ExpandAttribute
```

An HTML report, and every attribute change as CSV - for a pull request or a pipeline artifact.

## PARAMETERS

### -Action

Only these actions: Create, Update, Replace, Delete, Read, Import,
Move, Forget, NoOp. Every action but NoOp by default.

```yaml
Type: System.String[]
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

### -Address

Only resources whose address matches one of these (wildcards):
'module.network.\*', '\*azurerm_key_vault\*'.

```yaml
Type: System.String[]
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

### -CsvPath

Write the rows to this CSV file.

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

### -ExpandAttribute

Return (and write to -CsvPath) one row per changed attribute, not
per resource.

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

Write an interactive HTML report to this file.

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

### -IncludeDrift

Also return the changes made outside Terraform (Source 'Drift').
The view always shows them.

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

### -Path

The plan in JSON: terraform show -json tfplan \> plan.json.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases:
- FullName
- PlanFile
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ResourceType

Only these resource types (wildcards): 'azurerm_storage_account',
'azurerm_network_\*'.

```yaml
Type: System.String[]
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

### -Title

The HTML report's title.

```yaml
Type: System.String
DefaultValue: "'Terraform plan'"
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

### AAC.TerraformChange, or AAC.TerraformAttributeChange with -ExpandAttribute (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACTerraformPlan.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
