---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Show-AACNetworkTopology.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Show-AACNetworkTopology
---

# Show-AACNetworkTopology

## SYNOPSIS

Draws the network topology of the tenant - or of management groups, subscriptions or regions - as an interactive diagram: hubs with their spokes around them, or every network inside its tenant, management group, subscription, region and resource group; with the peerings, private endpoints and the firewalls and appliances traffic is routed through. Opens it in your browser, ready to save as PNG, JPEG or SVG.

## SYNTAX

### __AllParameterSets

```
Show-AACNetworkTopology [[-ManagementGroupId] <string[]>] [[-SubscriptionId] <string[]>]
 [[-Location] <string[]>] [[-GroupBy] <string>] [[-Layout] <string>] [[-ExcludeType] <string[]>]
 [[-Direction] <string>] [[-Theme] <string>] [[-NsgView] <string>] [[-HtmlPath] <string>]
 [[-Title] <string>] [-NetworkOnly] [-NoBrowser] [-PassThru]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Reads with Azure Resource Graph - read-only, Reader is enough, no Az
modules - across every subscription in scope, every region:

```text
  the management groups and subscriptions above the networks
  virtual networks and subnets, and their peerings - also across
    subscriptions, and to networks you can't see
  VPN and ExpressRoute gateways, connections, circuits, local
    gateways; Virtual WAN and its hubs and gateways
  Azure Firewalls, network virtual appliances (VMs whose NIC forwards
    IP traffic), NSGs, route tables, NAT gateways, Bastion, load
    balancers, Application Gateways, private link services, DNS
    resolvers
  virtual machines, scale sets and private endpoints in their
    subnets, and the PaaS resources the private endpoints serve
    (-NetworkOnly leaves these out)
```

A peering outside the scope is followed to the network at its other
end, and a route's next hop to the firewall or appliance that has the
IP, so a spoke's map reaches its hub.

The boxes (-GroupBy):

```text
  ManagementGroup  tenant > management group > subscription > region
                   > resource group > virtual network > subnet
  Subscription     subscription > region > resource group > ...
  Region           region > virtual network > subnet
```

Subnets are drawn in rows inside their network, as wide as their
prefix is big. VMs, scale sets, Bastion, gateways, firewalls and
private endpoints sit in the subnet they have an IP in; a VM shows
its NIC's IPs and NSG, and an appliance is outlined in the route
colour.

The lines:

```text
  VNet peering   between networks, both ways, with its state and what
                 it lets through (forwarded traffic, gateway transit,
                 remote gateway); red and dashed when not Connected
  Private link   from a private endpoint to the PaaS resource it serves
  Route          from a subnet to the firewall or appliance its routes
                 send traffic to ("0.0.0.0/0 via rt-spoke")
  Network        a gateway's connections and circuits, and the rest
```

Within a network, subnets reach each other through Azure's system
routes: no lines are drawn between them.

Each network gets a role: hub (gateway transit, or a gateway,
firewall or appliance and peerings, or 3+ peerings), spoke (peered
with a hub), peered or standalone. The layout (-Layout):

```text
  HubSpoke   each hub at the centre, its spokes in rings around it,
             hubs side by side, the rest below; each network's box
             says its subscription, region and resource group
  Hierarchy  the nested boxes, laid out in layers
  Auto       HubSpoke when there are hubs with spokes (the default)
```

The page switches between them, and between left to right and top to
bottom; pan, zoom, search, click for details and connections, and
save as PNG, JPEG or SVG.

At the prompt: tiles, the hubs and their spokes, and findings - a
peering that isn't connected, a route to an IP nothing has, a spoke
subnet whose internet traffic isn't sent through a firewall or
appliance, a peering to a network you can't see, standalone networks.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Show-AACNetworkTopology
```

Every network you can see, hubs at the centre of their spokes.

### Example 2

```powershell
Show-AACNetworkTopology -ManagementGroupId 'mg-landingzones' -GroupBy Subscription -Layout Hierarchy
A management group's networks inside their subscriptions, regions and resource groups.
```

### Example 3

```powershell
Show-AACNetworkTopology -NetworkOnly -Location 'uksouth', 'ukwest' -Theme Light -HtmlPath .\out\Network.html -NoBrowser
```

The network fabric of two regions, written to a file.

### Example 4

```powershell
(Show-AACNetworkTopology -NoBrowser -PassThru).Findings | Where-Object Severity -EQ 'High'
```

Peerings that aren't connected and routes to IPs nothing has.

## PARAMETERS

### -Direction

LeftToRight (the default) or TopToBottom, inside each box. The page
can switch it too.

```yaml
Type: System.String
DefaultValue: "'LeftToRight'"
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

### -ExcludeType

Resource types to leave out; wildcards work.

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

### -GroupBy

The boxes around the networks: ManagementGroup (the default),
Subscription or Region.

```yaml
Type: System.String
DefaultValue: "'ManagementGroup'"
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

Where to write the diagram. By default a file in your temp folder.

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

### -Layout

Auto (the default), HubSpoke or Hierarchy. The page can switch too.

```yaml
Type: System.String
DefaultValue: "'Auto'"
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

### -Location

Only these regions (e.g. 'uksouth', 'westeurope').

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

### -NetworkOnly

Leave out virtual machines, scale sets, private endpoints and the
PaaS resources behind them: only the network fabric - networks,
subnets, peerings, gateways, firewalls, appliances, Bastion. For a
large estate.

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

### -NoBrowser

Write the diagram without opening it.

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
and VMs they're applied to. Cards: as resources, with lines.

```yaml
Type: System.String
DefaultValue: "'Chips'"
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

### -PassThru

Also return the topology: networks with their roles, findings,
resources, connections and the file's path.

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

### -Theme

Dark (the default), Light or Blueprint.

```yaml
Type: System.String
DefaultValue: "'Dark'"
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

The diagram's title.

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.NetworkTopology, with -PassThru

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Show-AACNetworkTopology.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
