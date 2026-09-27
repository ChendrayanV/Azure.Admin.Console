---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Show-AACResource.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Show-AACResource
---

# Show-AACResource

## SYNOPSIS

Shows how many Azure resources you have - by type, location, resource group or subscription - as a colourful Spectre.Console bar chart.

## SYNTAX

### __AllParameterSets

```
Show-AACResource [[-SubscriptionId] <string[]>] [[-By] <string>] [[-ResourceType] <string[]>]
 [[-Top] <int>] [[-HtmlPath] <string>] [[-Title] <string>] [-NoPaging] [-PassThru]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Counts every resource the signed-in account can see (or only those in
-SubscriptionId, of -ResourceType) with Azure Resource Graph, over
REST with the Connect-AAC sign-in - two queries however many
resources there are, and no Az modules.

The view:

```text
  ── Azure Admin Console :: Azure resources ─────────────────────
  account · tenant · scope · when
  [ resources ] [ types ] [ subscriptions ] [ resource groups ] [ locations ]

  Resources by type (top 20)
  compute/virtualmachines       ████████████████████████ 412
  network/networkinterfaces     ███████████████████ 398
  storage/storageaccounts       ██████████ 164
  ...
  37 other types                ████ 61
```

Each bar has its own colour. -By picks what is counted: resource
Type (the default), Location, ResourceGroup or Subscription. -Top
sets how many bars are drawn; the rest are summed in a final grey
bar.

When the view is longer than the terminal it is paged: press any key
for the next page, or A for the rest. -NoPaging turns that off.

With -PassThru the counts are also returned as AAC.ResourceCount
objects (Name, Count, Share), every one of them, not only the top.

-HtmlPath writes a self-contained, interactive inventory instead of
the view: every resource (name, type, resource group, location,
subscription, kind, SKU, tags) with Azure portal links, tiles and
charts by type, location, subscription and resource group that
filter it, search, filters, grouping and a CSV download. It needs one
more Resource Graph query, for the resources themselves. With
-HtmlPath the console shows only the progress and the file written.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Show-AACResource
```

The top 20 resource types across every subscription you can see.

### Example 2

```powershell
Show-AACResource -By Location
```

How many resources are in each Azure region.

### Example 3

```powershell
Show-AACResource -ResourceType 'microsoft.network/*' -Top 10
```

The ten most common networking resource types.

### Example 4

```powershell
Show-AACResource -By Subscription -PassThru | Export-Csv .\ResourcesPerSubscription.csv -NoTypeInformation
```

Shows resources per subscription and saves the counts as a CSV file.

### Example 5

```powershell
Show-AACResource -HtmlPath .\out\Inventory.html
```

Every resource in an interactive HTML inventory, with portal links.

## PARAMETERS

### -By

What to count by: Type (default), Location, ResourceGroup or
Subscription.

```yaml
Type: System.String
DefaultValue: "'Type'"
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

### -HtmlPath

Write an interactive HTML inventory of the resources to this file
instead of showing the view. An existing file is overwritten;
missing folders are created.

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

### -NoPaging

Show the whole view at once instead of a screen at a time.

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

Also return the counts as AAC.ResourceCount objects.

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

### -ResourceType

Only count resources of these types. Case-insensitive; wildcards
work, e.g. 'microsoft.network/\*'.

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

### -SubscriptionId

Only count resources in these subscriptions. Defaults to every
subscription the signed-in account can see.

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

The HTML report's title. Defaults to 'Azure resources'.

```yaml
Type: System.String
DefaultValue: "'Azure resources'"
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

### -Top

How many bars to draw (default 20); the rest are summed in one bar.

```yaml
Type: System.Int32
DefaultValue: 20
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.ResourceCount (with -PassThru)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Show-AACResource.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
