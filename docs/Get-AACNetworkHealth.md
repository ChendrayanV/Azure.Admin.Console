---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACNetworkHealth.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Get-AACNetworkHealth
---

# Get-AACNetworkHealth

## SYNOPSIS

Health of the hybrid and edge network - ExpressRoute circuits and gateways, VPN gateways, connections and tunnels, Azure Firewalls and NAT gateways - from their metrics, configuration and Resource Health: what the Azure Network Monitoring workbook charts, with % of capacity, thresholds and findings, as a heat map, a Spectre.Console view, objects, and CSV, PDF and interactive HTML reports.

## SYNTAX

### __AllParameterSets

```
Get-AACNetworkHealth [[-SubscriptionId] <string[]>] [[-ManagementGroupId] <string[]>]
 [[-ResourceGroupName] <string[]>] [[-Component] <string[]>] [[-TimeRange] <string>]
 [[-WarnPercent] <int>] [[-View] <string>] [[-ThrottleLimit] <int>] [[-CsvPath] <string>]
 [[-HtmlPath] <string>] [[-PdfPath] <string>] [[-Title] <string>] [-PassThru] [-NoDisplay]
 [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Read-only (Reader is enough): one Resource Graph batch (the
resources), Azure Monitor metrics over -TimeRange and each component's
current Resource Health, several calls at once.

```text
  ExpressRoute circuits  BGP and ARP availability per peering and
                         link, each link's peak against the circuit's
                         bandwidth, traffic pinned to one link, QoS
                         drops, provisioning state, idle circuits
  ExpressRoute gateways  CPU, packets per second against the SKU,
  (VNet and Virtual WAN) routes advertised (1,000) and learned
                         (4,000), zone-redundant SKU
  VPN and point-to-site  bandwidth against the SKU, BGP peers up or
  gateways               flapping, point-to-site users against the
                         SKU, active-active, legacy SKUs
  connections            Connected or not, the tunnel's peak and
                         packet drops, static routing
  Azure Firewalls        health, SNAT ports, throughput against the
                         tier, latency, zones
  NAT gateways           data path availability, dropped packets,
                         SNAT connections against the public IPs'
                         ports, gateways on no subnet
```

Limits are Microsoft's published figures per SKU (approximate);
-WarnPercent (80) is where utilisation and capacity become findings
(95% is High). The heat map scores each component 0-100 for
availability, utilisation, drops, capacity and health.

Every finding says when: the time of the peak, the first and last time
it was seen in the period, or - for Resource Health - since when, in
UTC. Each component has the time of its peak and of its Resource
Health state; the report's header gives the period covered and when
it was made.

-View sets what is returned (piped onward, -PassThru, -NoDisplay) and
written to -CsvPath: Component (default) or Finding.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Get-AACNetworkHealth
```

The hybrid and edge network's health over the last day.

### Example 2

```powershell
Get-AACNetworkHealth -Component ExpressRoute, Gateway -TimeRange 7d -HtmlPath .\out\Network.html -PdfPath .\out\Network.pdf
A week of ExpressRoute circuits and gateways, as reports.
```

### Example 3

```powershell
Get-AACNetworkHealth -View Finding -NoDisplay | Where-Object Severity -EQ 'High'
```

What is down or near its limit.

## PARAMETERS

### -Component

ExpressRoute, Gateway (ExpressRoute gateways), Vpn (VPN and
point-to-site gateways), Firewall, NatGateway - all by default.
Connections come with Gateway or Vpn.

```yaml
Type: System.String[]
DefaultValue: "@('ExpressRoute', 'Gateway', 'Vpn', 'Firewall', 'NatGateway')"
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

### -CsvPath

Write the -View rows to this CSV file.

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

### -HtmlPath

Write an interactive HTML report.

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

### -ManagementGroupId

Only the subscriptions under these management groups.

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

### -NoDisplay

Return the rows without showing the view.

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

Show the view and also return the rows.

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
  Position: 10
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ResourceGroupName

Only these resource groups.

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
  Position: 0
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ThrottleLimit

How many metric calls run at once (1 to 32; 12 by default).

```yaml
Type: System.Int32
DefaultValue: 12
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

### -TimeRange

How far back the metrics go: 1h, 4h, 12h, 1d (default), 3d, 7d, 14d or 30d.

```yaml
Type: System.String
DefaultValue: "'1d'"
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

### -Title

The reports' title.

```yaml
Type: System.String
DefaultValue: "'Network health'"
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

### -View

Component or Finding: what is returned and written to -CsvPath.

```yaml
Type: System.String
DefaultValue: "'Component'"
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

### -WarnPercent

The % of capacity or of a limit at which a finding is raised (50 to
99; 80 by default).

```yaml
Type: System.Int32
DefaultValue: 80
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

### AAC.NetworkHealth or AAC.NetworkHealthFinding, by -View (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACNetworkHealth.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
