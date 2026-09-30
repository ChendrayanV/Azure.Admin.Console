---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACSkuAvailability.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Get-AACSkuAvailability
---

# Get-AACSkuAvailability

## SYNOPSIS

Which VM sizes you can use - for virtual machines or AKS node pools - in a region and its availability zones, with your subscription's restrictions and vCPU quota, and why a size can't be used.

## SYNTAX

### __AllParameterSets

```
Get-AACSkuAvailability [[-Location] <string[]>] [[-Service] <string>] [[-Zone] <string[]>]
 [[-SubscriptionId] <string[]>] [[-ClusterName] <string>] [[-ResourceGroupName] <string>]
 [[-Series] <string[]>] [[-Sku] <string[]>] [[-Architecture] <string>] [[-NodeCount] <int>]
 [[-CsvPath] <string>] [[-PdfPath] <string>] [[-HtmlPath] <string>] [[-Title] <string>] [-PassThru]
 [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Read-only, over REST (Reader is enough, no Az modules or Azure CLI,
nothing created). For each subscription and region, read at once:

```text
  Microsoft.Compute/skus      the sizes offered, their zones, the
                              subscription's restrictions (region or
                              zone) and capabilities
  Microsoft.Compute/usages    each family's and the region's vCPU
                              quota
  subscription locations      which physical zone each logical zone
                              is (they differ between subscriptions)
```

and, with -ClusterName, the AKS cluster and its node pools (Azure
Resource Graph).

Each size's status, the first that applies:

```text
  Restricted       not offered to the subscription in the region
  NotSupported     -Service Aks: fewer than 2 vCPUs
  ZoneUnavailable  -Zone: none of those zones can host it
  Partial          -Zone: some of them can't
  NoQuota          fewer free vCPUs (family or region) than
                   vCPUs x -NodeCount
  Available        usable
```

with the reason, and the size's vCPUs, memory, zones, architecture,
ephemeral OS disk, accelerated networking, premium storage, Spot,
GPUs and data disks. -Service Aks adds AKS's rules: at least 2 vCPUs;
4 GB for system node pools, and burstable (B) sizes noted as unfit
for them.

What only a real deployment proves is that capacity is there at that
moment; nothing here creates anything to find out.

What you get depends on where the command runs:

```text
  at the prompt    tiles, the zones, the quota, the cluster's node
                   pools (-ClusterName) and each size with its status
                   and reason - a page at a time
  piped onward     the sizes (AAC.SkuAvailability), with no view
  -PassThru        the view and the sizes
  -NoDisplay       the sizes only
```

-CsvPath writes the sizes. -HtmlPath writes an interactive report
(sizes, quota, zones, node pools; charts that filter them). -PdfPath
writes a PDF.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Get-AACSkuAvailability -Location uksouth -Zone 1, 2, 3 -Series D, E
```

The D and E series sizes that can run in all three zones of UK South.

### Example 2

```powershell
Get-AACSkuAvailability -ClusterName 'aks-contoso' -Zone 1, 2, 3 -Sku '*s_v5' -NodeCount 3
```

Sizes for a new three-node, three-zone pool on a cluster, in its region, with its current pools.

### Example 3

```powershell
Get-AACSkuAvailability -Service Aks -Location uksouth, ukwest -SubscriptionId '00000000-0000-0000-0000-000000000000' -Architecture Arm64 -HtmlPath .\out\Skus.html
```

Arm64 sizes for AKS in two regions, as an HTML report.

### Example 4

```powershell
Get-AACSkuAvailability -Location westeurope -Zone 1, 2, 3 -NoDisplay | Where-Object Status -EQ 'Available' | Where-Object { $_.vCPUs -eq 4 -and $_.MemoryGB -ge 16 }
```

Every 4 vCPU, 16 GB+ size usable in all three zones.

## PARAMETERS

### -Architecture

Only x64 or Arm64 sizes.

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

### -ClusterName

An AKS cluster: checks its region, marks the sizes its node pools use
and shows each pool's size status and free quota. Implies -Service
Aks.

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

Write every size to this CSV file.

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

### -HtmlPath

Write an interactive HTML report to this file.

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

### -Location

The regions to check (for example uksouth, westeurope). With
-ClusterName, the cluster's region by default.

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

### -NodeCount

The number of VMs or nodes the quota must fit (vCPUs x NodeCount).
1 by default.

```yaml
Type: System.Int32
DefaultValue: 1
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

Return the sizes without showing the view.

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

Show the view and also return the sizes.

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
  Position: 11
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ResourceGroupName

The cluster's resource group, when the name alone isn't unique.

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

### -Series

Only these VM series - the letters of the size name, for example D,
E, F, NC, DC (Standard_D4s_v5 is D); wildcards allowed.

```yaml
Type: System.String[]
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

### -Service

VirtualMachine (the default) or Aks: AKS's node pool rules as well.

```yaml
Type: System.String
DefaultValue: "'VirtualMachine'"
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

### -Sku

Only these sizes, for example Standard_D4s_v5 or D4s_v5; wildcards
allowed (\*s_v5).

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

### -SubscriptionId

The subscriptions to check - restrictions and quota are per
subscription. The cluster's with -ClusterName; the only one you can
see otherwise.

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

### -Title

The PDF and HTML reports' title.

```yaml
Type: System.String
DefaultValue: "'VM size availability'"
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

### -Zone

The availability zones the size must be in (for example 1, 2, 3).
Without it, zones are shown but not required.

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.SkuAvailability (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACSkuAvailability.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
