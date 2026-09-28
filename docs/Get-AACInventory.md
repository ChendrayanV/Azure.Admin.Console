---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACInventory.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Get-AACInventory
---

# Get-AACInventory

## SYNOPSIS

Inventories the tenant as a tree - management groups, subscriptions, resource groups and resources - with a Spectre.Console tree view, objects, and CSV, PDF and interactive HTML exports.

## SYNTAX

### __AllParameterSets

```
Get-AACInventory [[-ManagementGroupId] <string[]>] [[-SubscriptionId] <string[]>]
 [[-ResourceGroupName] <string[]>] [[-Depth] <string>] [[-CsvPath] <string>] [[-PdfPath] <string>]
 [[-HtmlPath] <string>] [[-Title] <string>] [-NoSecurity] [-PassThru] [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Reads everything with Azure Resource Graph (Reader access is enough;
no Az modules): the management groups, the subscriptions and the
management group each is in, the resource groups and the resources.
The tree is:

```text
  Tenant
    Management groups (nested as in Azure)
      Subscriptions
        Resource groups (location, most common resource types)
          Resources (type, location, SKU)
```

with the number of subscriptions, resource groups and resources
below every node. Management groups with no subscription in the result
are left out, unless you asked for them with -ManagementGroupId. A
subscription in a management group you can't read is shown under the
tenant. Empty resource groups are flagged.

Security posture comes from Microsoft Defender for Cloud (Resource
Graph's securityresources; Reader or Security Reader is enough), in
colour:

```text
  - each subscription's secure score - Defender's own (current / max)
    - and management groups' and the tenant's, their subscriptions'
    scores added up as Defender does
  - each resource's score - the share of its assessed recommendations
    that are healthy - and its unhealthy findings by severity, rolled
    up to its resource group
  - Good (70% or more) green, Fair (40-69%) amber, Poor (under 40%)
    red; High findings red, Medium amber, Low blue, Healthy green
  - the security controls with the potential score increase of fixing
    each (their impact), and every unhealthy recommendation with its
    severity, user impact, effort and resource
```

Without Defender data (not enabled, or no access) the inventory is
shown without it. -NoSecurity skips reading it.

What you get depends on where the command runs:

```text
  at the prompt    tiles, the tree (down to -Depth; resource groups by
                   default) and the most common resource types - a
                   page at a time
  piped onward     the objects, with no view
  -PassThru        the view and the objects
  -NoDisplay       the objects only
```

One AAC.InventoryItem per node: Level (Tenant, ManagementGroup,
Subscription, ResourceGroup, Resource), Depth, Name, Path, the
management group, subscription and resource group it is in, Type,
Kind, Location, SKU, State, the counts below it, TopTypes,
SecureScore, Rating, Severity, High, Medium, Low, Findings,
TopFindings, Tags, Id.

-CsvPath writes every node as a CSV row. -HtmlPath writes an
interactive report: tiles, charts, the hierarchy as a collapsible,
searchable tree with each node's score and findings in colour (click
a node to see it in the tables), and tables of management groups,
subscriptions, resource groups, resources, security controls and
recommendations, each with its own CSV download. -PdfPath writes a
PDF: the summary, the hierarchy, security (scores, controls,
recommendations), subscriptions, resource groups, resources by type
and the resources. With any of them, the console shows only the progress and
the files written.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Get-AACInventory
```

The whole tenant as a tree, down to resource groups.

### Example 2

```powershell
Get-AACInventory -ManagementGroupId 'mg-landingzones' -Depth Resource
```

One management group, down to every resource.

### Example 3

```powershell
Get-AACInventory -SubscriptionId '00000000-0000-0000-0000-000000000000' -HtmlPath .\out\Inventory.html -PdfPath .\out\Inventory.pdf
```

One subscription as an interactive HTML report and a PDF.

### Example 4

```powershell
Get-AACInventory -NoDisplay | Where-Object { $_.Level -eq 'ResourceGroup' -and $_.Resources -eq 0 }
```

The empty resource groups.

## PARAMETERS

### -CsvPath

Write every node - tenant, management groups, subscriptions,
resource groups and resources - to this CSV file.

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

### -Depth

How deep the console tree goes: ManagementGroup, Subscription,
ResourceGroup (the default) or Resource. The objects and exports
always have everything.

```yaml
Type: System.String
DefaultValue: "'ResourceGroup'"
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

Only these management groups (their IDs, e.g. 'mg-corp') and
everything below them.

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

Return the objects without showing the view.

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

### -NoSecurity

Don't read Microsoft Defender for Cloud: no secure scores, findings
or recommendations.

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

Show the view and also return the objects.

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

Only these resource groups (in the subscriptions or management groups
given, or in any you can see).

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
DefaultValue: "'Azure tenant inventory'"
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

### AAC.InventoryItem (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACInventory.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
