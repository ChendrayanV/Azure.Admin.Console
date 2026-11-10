---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/New-AACDesignDiagram.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: New-AACDesignDiagram
---

# New-AACDesignDiagram

## SYNOPSIS

Draws a hub and spoke design from a few parameters - the firewall, the spokes and the resources in them - as an editable draw.io diagram, with every subscription, resource group, virtual network and subnet named and each address range worked out.

## SYNTAX

### __AllParameterSets

```
New-AACDesignDiagram [[-Name] <string>] [[-Spoke] <Object[]>] [[-Design] <Object>]
 [[-Resource] <string[]>] [[-HubAddressSpace] <string>] [[-HubSubscription] <string>]
 [[-HubResourceGroup] <string>] [[-Region] <string>] [[-Environment] <string>] [[-Path] <string>]
 [[-HtmlPath] <string>] [[-PdfPath] <string>] [[-CsvPath] <string>] [[-Title] <string>] [-Firewall]
 [-Bastion] [-VpnGateway] [-Update] [-Force] [-Open] [-PassThru] [-NoDisplay] [-NoPaging] [-WhatIf]
 [-Confirm]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Offline: nothing is read from Azure and nothing needs to exist, so a design
can be drawn before there is a subscription for it. Export-AACDiagram draws
what is already deployed; this draws what you are about to build.

From the hub's address space, the spokes and the resources you name, it
plans:

```text
  Subnets      each network's subnets at the size Microsoft recommends for
               what is in them (AzureFirewallSubnet /26, a delegated App
               Service integration subnet, a private endpoint subnet...),
               from the smallest it supports when the space is tight, with
               their ranges, usable addresses and network security group
  Routing      with -Firewall, a route table per spoke sending 0.0.0.0/0
               to the firewall's private IP
  Peering      every spoke to the hub, with gateway transit when there is
               a VPN gateway
  Resources    named as {type}-{spoke}-{env}-{region} (storage accounts and
               registries without hyphens): Web and Function Apps outside
               the network with VNet integration and an App Service plan;
               storage, Key Vault, SQL, Cosmos DB, Redis, Service Bus, Event
               Hubs and registries behind private endpoints, with their
               private DNS zones in the hub; VMs, AKS, Application Gateway
               and API Management in subnets of their own
```

Networks that overlap, or a network too small for its subnets, stop the
command: a diagram of addresses that can't exist would mislead.

A spoke is a name - it gets the next free /16 (10.1.0.0/16, 10.2.0.0/16...)
and -Resource - or a hashtable for full control:

```text
  @{ Name = 'orders'; AddressSpace = '10.10.0.0/20'; Resources = 'FunctionApp', 'StorageAccount'
     Subscription = 'sub-orders-prod'; ResourceGroup = 'rg-orders-prod'
     Subnets = @( @{ Name = 'snet-app'; AddressPrefix = '10.10.0.0/24'; Resources = 'FunctionApp' }
                  @{ Name = 'snet-pe'; AddressPrefix = '10.10.1.0/26'; Resources = 'StorageAccount' } ) }
```

Subnets you give are kept as they are, and checked.

The draw.io file has native containers (subscription \> region \> resource
group \> virtual network \> subnet), Azure icons, attached connections and a
Legend page: open it in draw.io (desktop, app.diagrams.net or the VS Code
extension) and keep editing. Run it again with -Update after changing the
parameters: your own changes to the diagram are kept. At the prompt you get
the address plan; -CsvPath writes it, -PassThru returns it (AAC.DesignSubnet).

-Design draws the network for a design from New-AACArchitectureDesign (the
object, piped or given, or the JSON file its -OutPath saved): its region,
its firewall, and the components this diagram has an icon and a subnet
for go into one spoke (or each spoke you name). Components without one
here - Front Door, monitoring, Azure OpenAI, AI Search... - are listed in
a warning; New-AACArchitectureDiagram draws the whole design.

## EXAMPLES

### Example 1

```powershell
New-AACDesignDiagram -Name contoso -Firewall -Bastion -Spoke orders, payments -Resource FunctionApp, WebApp, StorageAccount, KeyVault -Open
A hub with a firewall and Bastion, two spokes with the same four resources, opened in draw.io.
```

### Example 2

```powershell
New-AACDesignDiagram -Name contoso -Firewall -VpnGateway -HubAddressSpace 10.100.0.0/22 -Spoke @(
    @{ Name = 'orders'; AddressSpace = '10.110.0.0/20'; Resources = 'FunctionApp', 'StorageAccount', 'ServiceBus'; Subscription = 'sub-orders-prod' }
    @{ Name = 'web'; AddressSpace = '10.120.0.0/20'; Resources = 'ApplicationGateway', 'WebApp', 'SqlDatabase' }
) -Path .\contoso.drawio -CsvPath .\contoso-ip-plan.csv
```

Spokes with their own ranges, resources and subscription, and the address plan as CSV.

### Example 3

```powershell
New-AACDesignDiagram -Name contoso -Firewall -Spoke orders -Resource FunctionApp, StorageAccount -Path .\contoso.drawio -Update
```

Redraws the diagram you edited, keeping your changes.

### Example 4

```powershell
New-AACArchitectureDesign -BriefPath .\brief.json -Offline | New-AACDesignDiagram -Bastion -Open
```

The network for an architecture design: its components in a spoke, its firewall in the hub.

## PARAMETERS

### -Bastion

Put Azure Bastion in the hub.

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

### -Confirm



```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases:
- cf
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

Write the address plan to this CSV file.

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

### -Design

A design from New-AACArchitectureDesign - the object, or the JSON file
it saved with -OutPath. Its components become the spoke's resources (in
place of -Resource), its first region the -Region, and its firewall
-Firewall. Pipe it: New-AACArchitectureDesign ... | New-AACDesignDiagram.

```yaml
Type: System.Object
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 2
  IsRequired: false
  ValueFromPipeline: true
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Environment

The environment in the names: prod, dev... Default prod.

```yaml
Type: System.String
DefaultValue: "'prod'"
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

### -Firewall

Put Azure Firewall in the hub, and route each spoke's traffic through it.

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

### -Force

Replace an existing file at -Path.

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

Also write the design as an interactive page.

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

### -HubAddressSpace

The hub's address space. Default 10.0.0.0/22.

```yaml
Type: System.String
DefaultValue: "'10.0.0.0/22'"
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

### -HubResourceGroup

The hub's resource group. Default rg-hub-network-{env}-{region}.

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

### -HubSubscription

The hub's subscription name. Default sub-connectivity.

```yaml
Type: System.String
DefaultValue: "'sub-connectivity'"
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

### -Name

The design's name, for the title and the file name. With -Design, the
design's own name when left out.

```yaml
Type: System.String
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

Return the subnets without showing the plan.

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

Show the whole plan at once.

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

Open the diagram when it is written, in the app your computer uses for
draw.io files.

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

Show the plan and also return the subnets.

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

The draw.io file. Default .\\<Name\>-design.drawio.

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

### -PdfPath

Also write the design as a one-page PDF (needs Microsoft Edge or Chrome).

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

### -Region

The region. Default westeurope.

```yaml
Type: System.String
DefaultValue: "'westeurope'"
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

### -Resource

The resources in a spoke given as a name: FunctionApp, WebApp,
StorageAccount, KeyVault, SqlDatabase, CosmosDb, Redis, ServiceBus, EventHub,
ContainerRegistry, VirtualMachine, Aks, ApplicationGateway, ApiManagement.
Name one twice for two of it.

```yaml
Type: System.String[]
DefaultValue: '@()'
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

### -Spoke

The spokes: names, or hashtables with Name and any of AddressSpace,
Resources, Subscription, ResourceGroup and Subnets (see the description).
With -Design, one spoke named workload when left out.

```yaml
Type: System.Object[]
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

The diagram's title.

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

### -Update

Redraw the diagram at -Path and keep the changes you made to it: what is new
is added and marked, what is gone is faded.

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

### -VpnGateway

Put a VPN gateway in the hub, connected to your on-premises network, and let
the spokes use it through the peering.

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

### -WhatIf



```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases:
- wi
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

### AAC.DesignSubnet (with -PassThru or -NoDisplay, or piped onward)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/New-AACDesignDiagram.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
