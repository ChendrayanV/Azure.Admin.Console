---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Show-AACResourceMap.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Show-AACResourceMap
---

# Show-AACResourceMap

## SYNOPSIS

Draws a map of the resources in one or more resource groups - with their connections, dependencies and network paths - and opens it in your browser, ready to save as a PNG or JPEG image.

## SYNTAX

### __AllParameterSets

```
Show-AACResourceMap [[-SubscriptionId] <string[]>] [[-ResourceGroupName] <string[]>]
 [[-Direction] <string>] [[-Theme] <string>] [[-NsgView] <string>] [[-ExcludeType] <string[]>]
 [[-HtmlPath] <string>] [[-Title] <string>] [-NoBrowser] [-PassThru]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Reads the resources with Azure Resource Graph (Reader access is
enough; no Az modules) and draws them with their official Azure icons,
laid out by the Eclipse Layout Kernel (ELK), in boxes:

```text
  subscription > resource group > virtual network > subnet
```

A network interface, private endpoint, firewall, gateway, Bastion,
internal load balancer, AKS cluster or API Management service is drawn
in the subnet it has an IP in, and a virtual machine in the subnet of
its first network interface. Each resource shows its name, its
product, and a detail worth seeing: a VM's size, an IP address, a
disk's size.

The lines between them come from the resource IDs in each resource's
properties, typed by what they are:

```text
  Network association   NICs, IPs, subnets, NSGs, route tables, NAT,
                        gateways, VNet integration
  Resource dependency   an app on its plan, a VM on its disks, a
                        database on its server, a diagnostic target
  VNet peering          with its state
  Private link          a private endpoint to the resource it serves
  Route (next hop)      a route table to the firewall or appliance
                        its routes send traffic to
  Private DNS link      a private DNS zone linked to a network
```

NSGs and route tables are drawn the way a network engineer reads them:
as chips on the subnets and NICs they are applied to (-NsgView Cards
draws them as resources with lines instead). Click one for its rules
or routes. A chip is red when it opens a management or database port
(SSH, RDP, WinRM, SMB, SQL, ...) or every port to the internet, or
when a route's next hop is an IP no resource you can see has; amber
for a wide port range open to the internet, or 0.0.0.0/0 straight to
the internet. A subnet's routes are drawn from the subnet ("0.0.0.0/0
via rt-spoke") to the firewall or appliance they go through - looked
up across every subscription you can see, so a spoke's map reaches
the hub's firewall. Each subnet's box also shows how many of its
addresses are used and what it's delegated to, and each peering what
it lets through (forwarded traffic, gateway transit, remote gateway).

A resource outside the chosen resource groups that a chosen one uses
- a VNet in the hub's resource group, say - is drawn too, in its own
resource group's box, marked as outside the selection. Resources
attached to nothing (a network interface without a VM, a public IP
without a configuration, an unattached disk, an NSG or route table on
nothing) are flagged.

The map is one self-contained HTML file, written to -HtmlPath (a file
in your temp folder by default) and opened in your default browser.
In the browser you can:

```text
  - pan and zoom, and fit the map to the window
  - click a resource or box: its connections light up and the rest
    fades, with its details, connections and an Azure portal link
  - find a resource by name, type, IP or resource group
  - switch between left to right and top to bottom, and the Dark,
    Light and Blueprint themes
  - show or hide each kind of connection
  - save the map as a PNG or JPEG image (or SVG), as drawn
```

The Azure icons are Microsoft's Azure architecture icons, used under
Microsoft's terms for architecture diagrams (lib\azure-icons\SOURCES.md).

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Show-AACResourceMap -SubscriptionId '00000000-0000-0000-0000-000000000000' -ResourceGroupName 'rg-app'
```

One resource group's map, opened in the browser.

### Example 2

```powershell
Show-AACResourceMap -SubscriptionId $hub, $spoke -ResourceGroupName 'rg-hub', 'rg-spoke-app', 'rg-spoke-data' -Direction TopToBottom
A hub-and-spoke network across two subscriptions, top to bottom.
```

### Example 3

```powershell
Show-AACResourceMap -ResourceGroupName 'rg-app' -Theme Light -HtmlPath .\out\rg-app-map.html -NoBrowser
A light-themed map written to a file, not opened.
```

### Example 4

```powershell
(Show-AACResourceMap -ResourceGroupName 'rg-app' -NoBrowser -PassThru).Nodes | Where-Object Orphan
```

The resources attached to nothing.

## PARAMETERS

### -Direction

How the map flows: LeftToRight (the default) or TopToBottom. The page
can switch it too.

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

### -ExcludeType

Resource types to leave out, e.g. 'microsoft.insights/\*' for alerts
and action groups; wildcards work.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: true
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

### -HtmlPath

Where to write the map. By default a file in your temp folder.

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

### -NsgView

Chips (the default): NSGs and route tables as chips on the subnets
and NICs they're applied to. Cards: as resources, with lines to them.
The page can switch it too.

```yaml
Type: System.String
DefaultValue: "'Chips'"
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

### -PassThru

Also return the map: its boxes, resources and connections, and the
file's path.

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

### -ResourceGroupName

The resource groups to map. Without -SubscriptionId they are looked
for in every subscription you can see.

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

### -SubscriptionId

The subscriptions to map. With -ResourceGroupName, the resource groups
are looked for in these subscriptions; alone, every resource group in
them is mapped.

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

### -Theme

Dark (the default), Light or Blueprint. The page can switch it too.

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

The map's title. By default, the resource groups (or subscriptions).

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.ResourceMap, with -PassThru

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Show-AACResourceMap.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
