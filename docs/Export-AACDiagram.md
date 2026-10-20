---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Export-AACDiagram.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Export-AACDiagram
---

# Export-AACDiagram

## SYNOPSIS

Draws your existing Azure resources as an editable draw.io diagram - resources, the network topology or Application Gateways - with real containers, Azure icons and attached connections; -Update refreshes it from Azure and keeps the changes you made.

## SYNTAX

### __AllParameterSets

```
Export-AACDiagram [[-View] <string>] [[-SubscriptionId] <string[]>]
 [[-ResourceGroupName] <string[]>] [[-ManagementGroupId] <string[]>] [[-Location] <string[]>]
 [[-Name] <string[]>] [[-GroupBy] <string>] [[-ExcludeType] <string[]>] [-Path] <string>
 [[-SplitBy] <string>] [[-Title] <string>] [[-HtmlPath] <string>] [[-PdfPath] <string>]
 [-NetworkOnly] [-IncludeHealth] [-Update] [-Prune] [-NoLegend] [-Force] [-Open] [-PassThru]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Reads Azure (read-only, Reader is enough) the way the map commands do
and writes a .drawio file you open and edit in draw.io - the desktop
app, app.diagrams.net, the Draw.io Integration for VS Code,
Confluence - and export from there to Visio (.vsdx), PNG, SVG or PDF.

-View chooses what is drawn:

```text
  Resources           the resources in resource groups or
                      subscriptions, in subscription > resource group
                      > virtual network > subnet boxes, with their
                      connections: network links, peerings, private
                      endpoints, routes, DNS links and dependencies
                      (as Show-AACResourceMap)
  Network             the network topology of a tenant, management
                      groups, subscriptions or regions: hubs and
                      spokes, peerings, gateways, firewalls and
                      appliances (as Show-AACNetworkTopology)
  ApplicationGateway  each gateway's flow - listeners > rules >
                      backend settings > pools and targets - with
                      probes, WAF policies and health (as
                      Show-AACApplicationGatewayMap)
  Governance          the management group hierarchy: the tenant
                      root and management groups as nested boxes,
                      each subscription inside its group, with the
                      policy and role assignments at each level (as
                      Show-AACManagementGroupMap)
```

In the diagram:

```text
  - boxes are draw.io containers: move a box and what is in it moves
    with it; drag a resource into another box and it belongs there
  - resources carry the Azure icons (vector), their name and type;
    unattached ones are red, those outside the selection faded
  - connections are attached at both ends and follow what you move
  - each shape keeps its resource ID, type, location, resource group
    and subscription (Edit > Edit Data, or hover), and Ctrl+click
    opens it in the Azure portal
  - a Legend page shows the kinds of box and connection, what was
    read and when (-NoLegend leaves it out)
```

-SplitBy puts each subscription, resource group, management group,
region or gateway on a page of its own, for large estates.

Edit it as you like - move, restyle, add notes, users, on-premises
shapes - then refresh it with -Update: it reads Azure again and
merges into the file:

```text
  - what you moved, restyled or relabelled stays as you left it
  - new resources are added into their box (which grows to fit) and
    marked green until the next refresh
  - resources no longer in Azure are faded and red - or deleted, with
    -Prune
  - shapes and connections you added are left alone
```

Without -Update an existing file is not overwritten unless you add
-Force.

To look at rather than edit - or to send to someone without draw.io -
add a clean copy alongside:

```text
  -HtmlPath  an interactive page, self-contained (opens offline): the
             diagram laid out with a legend of its connections and
             boxes, to pan, zoom, search and click for details
  -PdfPath   one page: the title and what was read, the whole diagram
             and its legend, in vector so it stays sharp when zoomed
             or printed (drawn by Microsoft Edge or Google Chrome,
             headless)
```

Both show what was read from Azure this time, on one page whatever
-SplitBy says - not the changes you made in draw.io.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Export-AACDiagram -ResourceGroupName 'rg-hub', 'rg-spoke-app' -Path .\estate.drawio -Open
```

Two resource groups as an editable diagram, opened in draw.io.

### Example 2

```powershell
Export-AACDiagram -View Network -ManagementGroupId 'mg-landingzones' -SplitBy Subscription -Path .\network.drawio
```

The landing zones' network topology, a page per subscription.

### Example 3

```powershell
Export-AACDiagram -ResourceGroupName 'rg-hub', 'rg-spoke-app' -Path .\estate.drawio -Update
```

Refreshes the diagram you edited: new resources added and marked, removed ones faded, your changes kept.

### Example 4

```powershell
Export-AACDiagram -View ApplicationGateway -ResourceGroupName 'rg-edge' -IncludeHealth -Path .\gateways.drawio
```

The gateways' flows with live backend health.

### Example 5

```powershell
Export-AACDiagram -View Governance -Path .\hierarchy.drawio -PdfPath .\hierarchy.pdf
```

The management group hierarchy as an editable diagram, and a one-page PDF.

### Example 6

```powershell
Export-AACDiagram -SubscriptionId $sub -Path .\estate.drawio -HtmlPath .\estate.html -PdfPath .\estate.pdf
```

The editable diagram, plus a clean interactive page and a one-page PDF, each with a legend, to share.

## PARAMETERS

### -ExcludeType

Leave out these resource types (Resources and Network views); wildcards
work, for example 'microsoft.compute/disks'.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: true
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

### -Force

Overwrite an existing file without -Update.

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

### -GroupBy

Network view: the boxes around the networks - ManagementGroup (the
default), Subscription or Region.

```yaml
Type: System.String
DefaultValue: "'ManagementGroup'"
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

### -HtmlPath

Also write the diagram as an interactive HTML page here, with its
legend - a clean copy to view or share.

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

### -IncludeHealth

ApplicationGateway view: run the live backend health check (30-90
seconds per gateway) instead of reading health metrics.

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

### -Location

Only these regions (Network view).

```yaml
Type: System.String[]
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

Only the subscriptions under these management groups (Network and
Governance views).

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

### -Name

Only the gateways with these names; wildcards work (ApplicationGateway view).

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

### -NetworkOnly

Network view: only the network fabric, without NICs, VMs, scale sets
and private endpoints.

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

### -NoLegend

Leave out the Legend page.

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

### -Open

Open what was written: the diagram (in the app .drawio files open
with), and the HTML page and PDF when you asked for them.

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

Return what was written: the paths, pages, shapes and connections
(and, with -Update, what was kept, added and removed).

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

The .drawio file to write - or, with -Update, to refresh.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 8
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -PdfPath

Also write the diagram as a one-page PDF here, with its title, what
was read and its legend. Needs Microsoft Edge or Google Chrome
installed.

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

### -Prune

With -Update: delete the resources no longer in Azure instead of
fading them.

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

Only these resource groups (Resources and ApplicationGateway views).

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

### -SplitBy

A page per Subscription, ResourceGroup, ManagementGroup, Region or
Gateway; None (the default) for one page.

```yaml
Type: System.String
DefaultValue: "'None'"
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

The diagram's title (the page name, without -SplitBy).

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

### -Update

Refresh the diagram at -Path from Azure, keeping your changes.

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

### -View

Resources (the default), Network, ApplicationGateway or Governance.

```yaml
Type: System.String
DefaultValue: "'Resources'"
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.Diagram, with -PassThru

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Export-AACDiagram.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
