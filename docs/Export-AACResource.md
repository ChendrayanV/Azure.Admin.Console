---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Export-AACResource.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Export-AACResource
---

# Export-AACResource

## SYNOPSIS

Exports your Azure resources - for the whole tenant, a management group, subscriptions, resource groups or resource types - to CSV, HTML and PDF, with the subscription and management group by name, the tags as columns and each resource's key settings flattened into plain values.

## SYNTAX

### __AllParameterSets

```
Export-AACResource [[-SubscriptionId] <string[]>] [[-ManagementGroupId] <string[]>]
 [[-ResourceGroupName] <string[]>] [[-ResourceType] <string[]>] [[-Name] <string[]>]
 [[-Location] <string[]>] [[-Tag] <hashtable>] [[-MissingTag] <string[]>] [[-Search] <string>]
 [[-Filter] <string>] [[-TagColumn] <string[]>] [[-First] <int>] [[-CsvPath] <string>]
 [[-HtmlPath] <string>] [[-PdfPath] <string>] [[-Title] <string>] [-Flatten] [-PassThru]
 [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

What Resource Graph Explorer's "Download as CSV" doesn't give you:

```text
  Where       subscription name and state, the management group and its
              path up to the root, resource group and its tags, location
              and zones - one Resource Graph query, joined to
              resourcecontainers
  What        type, kind, SKU and capacity, the parent of a child
              resource, identity, provisioning state, public network
              access, managed by, created (when Azure records it)
  Details     the settings people look up, per type: a VM's size, OS,
              image and power state; a disk's size, state and VM; a
              storage account's TLS, public access and network rules; a
              NIC's IP, VM and NSG; an App Service's plan, runtime and
              host; an AKS cluster's version and nodes; a key vault's
              soft delete, purge protection and RBAC... about 25 types
  Tags        one column per tag key ('Tag: Environment'), so the CSV
              sorts and filters in a spreadsheet - and the tags as one
              'key=value; ...' column too
  -Flatten    every property as a column of its own
              ('properties.networkAcls.defaultAction'), for the deep
              dives; best with -ResourceType
```

Filters run in Resource Graph where they can (so only what you asked
for comes back): -ResourceType, -ResourceGroupName, -Name (exact, or
with wildcards), -Location, -Tag (a value, or '\*' for any), -MissingTag
(resources without a tag - for tag governance) and -Filter, a KQL
condition of your own. -Search then looks for text anywhere in the name,
type, group, subscription, location, details, tags and ID.

Large estates are read in parallel: the subscriptions are split across
up to four Resource Graph queries, each paged to the end. Read-only;
Reader is enough.

## EXAMPLES

### Example 1

```powershell
Export-AACResource -CsvPath .\out\Resources.csv
```

Every resource you can see, with names, management groups, tags as columns and details.

### Example 2

```powershell
Export-AACResource -ManagementGroupId mg-landingzones -HtmlPath .\out\LandingZones.html -PdfPath .\out\LandingZones.pdf
```

One management group's resources as an interactive report and a PDF.

### Example 3

```powershell
Export-AACResource -ResourceType 'microsoft.compute/virtualmachines' -NoDisplay | Select-Object Name, Subscription, Location, Details
```

Every VM with its size, OS, image and power state.

### Example 4

```powershell
Export-AACResource -MissingTag CostCenter, Owner -CsvPath .\out\Untagged.csv
```

The resources without a CostCenter or Owner tag, for the owners to fix.

### Example 5

```powershell
Export-AACResource -ResourceType 'microsoft.storage/storageaccounts' -Flatten -CsvPath .\out\Storage.csv
```

Every storage account with every property as a column.

### Example 6

```powershell
Export-AACResource -Tag @{ Environment = 'prod' } -Search 'sql'
```

Production resources with 'sql' anywhere in them.

## PARAMETERS

### -CsvPath

Write the resources to this CSV file.

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

### -Filter

A Kusto (KQL) condition Resource Graph applies, as '| where \<Filter\>' -
for example "tostring(properties.provisioningState) != 'Succeeded'".

```yaml
Type: System.String
DefaultValue: None
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

### -First

Stop after this many resources (after the filters).

```yaml
Type: System.Int32
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

### -Flatten

Add every property, flattened, as a column of its own.

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

Write an interactive HTML report.

```yaml
Type: System.String
DefaultValue: None
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

### -Location

Only resources in these regions (for example uksouth, 'West Europe').

```yaml
Type: System.String[]
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

### -MissingTag

Only resources without these tags.

```yaml
Type: System.String[]
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

### -Name

Only resources with these names; wildcards work.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: true
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

### -NoDisplay

Return the resources without showing the view.

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

Show the view and also return the resources.

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
  Position: 14
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ResourceGroupName

Only these resource groups; wildcards work.

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

### -ResourceType

Only these types (for example 'microsoft.compute/virtualmachines', or
'microsoft.network/\*'); wildcards work.

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

### -Search

Only resources with this text in their name, type, resource group,
subscription, location, details, tags or ID.

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

### -Tag

Only resources with these tags: @{ Environment = 'prod' }, or
@{ Owner = '\*' } for any value.

```yaml
Type: System.Collections.Hashtable
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

### -TagColumn

The tag keys that get a column of their own. Default: every tag key
found, the most used first.

```yaml
Type: System.String[]
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

### -Title

The reports' title.

```yaml
Type: System.String
DefaultValue: "'Azure resources'"
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 15
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

### AAC.Resource

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Export-AACResource.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
