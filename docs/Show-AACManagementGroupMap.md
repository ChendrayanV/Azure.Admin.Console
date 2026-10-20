---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Show-AACManagementGroupMap.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Show-AACManagementGroupMap
---

# Show-AACManagementGroupMap

## SYNOPSIS

Draws the management group hierarchy as an interactive map - the tenant root and management groups as nested boxes, each subscription inside its group - with the subscriptions, policy assignments and role assignments at each level.

## SYNTAX

### __AllParameterSets

```
Show-AACManagementGroupMap [[-ManagementGroupId] <string[]>] [[-SubscriptionId] <string[]>]
 [[-Direction] <string>] [[-Theme] <string>] [[-HtmlPath] <string>] [[-Title] <string>] [-NoBrowser]
 [-PassThru]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Reads, read-only and tenant-wide in Azure Resource Graph, the
management groups and their parents, the subscriptions, the policy
and role assignments per scope and the resources per subscription,
and writes the map as one self-contained HTML page (the same page as
Show-AACResourceMap: pan, zoom, search, click for details, save PNG,
JPEG, SVG or draw.io). At the prompt: the hierarchy as a tree with
the counts.

Unscoped, every management group appears, empty ones too; with
-ManagementGroupId or -SubscriptionId, only the subscriptions in
scope and the groups above them. For an editable diagram, use
Export-AACDiagram -View Governance. Reader is enough.

## EXAMPLES

### Example 1

```powershell
Show-AACManagementGroupMap
```

The whole hierarchy, opened in the browser.

### Example 2

```powershell
Show-AACManagementGroupMap -ManagementGroupId 'mg-landingzones' -Theme Light -HtmlPath .\Hierarchy.html -NoBrowser
```

The landing zones' part of the hierarchy, written to a file.

### Example 3

```powershell
Show-AACManagementGroupMap -NoBrowser -PassThru | Sort-Object PolicyAssignments -Descending | Select-Object -First 5
```

The management groups with the most policy assignments.

## PARAMETERS

### -Direction

LeftToRight (the default) or TopToBottom.

```yaml
Type: System.String
DefaultValue: "'LeftToRight'"
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

### -HtmlPath

Where to write the map (by default a file in the temp folder).

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

Only the subscriptions under these management groups (at any depth).

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

### -NoBrowser

Write the map without opening it.

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

Return the hierarchy: a row per management group (AAC.ManagementGroup).

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

Only these subscriptions (and the groups above them).

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

### -Theme

Dark (the default), Light or Blueprint.

```yaml
Type: System.String
DefaultValue: "'Dark'"
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

### -Title

The map's title.

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.ManagementGroup, with -PassThru

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Show-AACManagementGroupMap.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
