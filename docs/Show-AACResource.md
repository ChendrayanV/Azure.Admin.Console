# Show-AACResource

[Azure.Admin.Console](Azure.Admin.Console.md) · [about_Azure.Admin.Console](about_Azure.Admin.Console.md)

## Synopsis

Shows how many Azure resources you have - by type, location, resource group or subscription - as a colourful Spectre.Console bar chart.

## Syntax

```powershell
Show-AACResource [[-SubscriptionId] <string[]>] [[-By] <string>] [[-ResourceType] <string[]>] [[-Top] <int>] [-PassThru] [<CommonParameters>]
```

## Description

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

With -PassThru the counts are also returned as AAC.ResourceCount
objects (Name, Count, Share), every one of them, not only the top.

## Examples

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

## Parameters

### -SubscriptionId

Only count resources in these subscriptions. Defaults to every
subscription the signed-in account can see.

| | |
|---|---|
| Type | `String[]` |
| Required | No |
| Position | 0 |
| Default value | `None` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -By

What to count by: Type (default), Location, ResourceGroup or
Subscription.

| | |
|---|---|
| Type | `String` |
| Accepted values | `Type`, `Location`, `ResourceGroup`, `Subscription` |
| Required | No |
| Position | 1 |
| Default value | `'Type'` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -ResourceType

Only count resources of these types. Case-insensitive; wildcards
work, e.g. 'microsoft.network/\*'.

| | |
|---|---|
| Type | `String[]` |
| Required | No |
| Position | 2 |
| Default value | `None` |
| Accepts pipeline input | No |
| Accepts wildcards | Yes |

### -Top

How many bars to draw (default 20); the rest are summed in one bar.

| | |
|---|---|
| Type | `Int32` |
| Required | No |
| Position | 3 |
| Default value | `20` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -PassThru

Also return the counts as AAC.ResourceCount objects.

| | |
|---|---|
| Type | `SwitchParameter` |
| Required | No |
| Position | Named |
| Default value | `False` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### CommonParameters

This command supports the common parameters (`-Verbose`, `-ErrorAction`, `-WarningAction` and so on). See [about_CommonParameters](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters).

## Outputs

AAC.ResourceCount (with -PassThru)
