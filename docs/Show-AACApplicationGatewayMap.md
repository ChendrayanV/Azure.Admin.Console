---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Show-AACApplicationGatewayMap.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Show-AACApplicationGatewayMap
---

# Show-AACApplicationGatewayMap

## SYNOPSIS

Draws Application Gateways as their connection flow - frontend IPs, listeners, rules, path rules and redirects, backend settings and probes, pools and targets, WAF policies - inside their network and subnet, with health and findings; shows each gateway's flows at the prompt and opens the map in your browser.

## SYNTAX

### __AllParameterSets

```
Show-AACApplicationGatewayMap [[-SubscriptionId] <string[]>] [[-ResourceGroupName] <string[]>]
 [[-Name] <string[]>] [[-CertificateDays] <int>] [[-Direction] <string>] [[-Theme] <string>]
 [[-HtmlPath] <string>] [[-CsvPath] <string>] [[-PdfPath] <string>] [[-Title] <string>]
 [-IncludeHealth] [-NoBrowser] [-PassThru]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Read-only, with Azure Resource Graph (Reader is enough): every setting
of each gateway, and what it refers to - public IPs, WAF policies,
the network and subnet (with its NSG and route table), the NICs and
VMs in the pools, and App Services whose host name is a target.

The map, left to right: frontend IPs \> listeners (protocol, port,
host names, certificate and its expiry, WAF policy) \> rules
(priority, basic or path-based) \> path rules and redirects \> backend
settings (protocol, port, timeout, host name, affinity, draining) and
their probes \> pools \> targets. WAF policies sit on the left with a
line to what they protect (the gateway, a site or a path). Pools and
targets are outlined green, amber or red by health. Click a card for
all its settings, its findings and its connections.

Health: metrics always (healthy and unhealthy host counts per pool,
last 30 minutes, v2 gateways); -IncludeHealth runs each gateway's live
backend health check - every target's state and, when it fails, the
probe's reason. That check takes 30-90 seconds and needs the
Microsoft.Network/applicationGateways/backendhealth/action permission;
a gateway that refuses is reported, not fatal.

Findings (High, Medium, Low): v1 SKU, WAF tier without a WAF, WAF in
Detection or disabled, old rule sets, old TLS policy, no zones or
under 2 instances, HTTP not redirected to HTTPS, certificates
expired, expiring (-CertificateDays) or uploaded instead of from Key
Vault, backend settings without a custom probe, probe host mismatch,
connection draining off, empty or unhealthy pools, and listeners,
settings, probes and pools nothing uses.

At the prompt: tiles, each gateway's flows (listener \> rule \> path \>
settings \> pool, with health) and the findings. -CsvPath writes the
flows; -PdfPath the gateways, flows and findings; -HtmlPath the map
(a file in your temp folder by default).

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Show-AACApplicationGatewayMap
```

Every Application Gateway you can see, as a map in the browser.

### Example 2

```powershell
Show-AACApplicationGatewayMap -ResourceGroupName 'rg-edge' -Name 'appgw-prod' -IncludeHealth
```

One gateway with live backend health and the probes' reasons.

### Example 3

```powershell
(Show-AACApplicationGatewayMap -NoBrowser -PassThru).Flows | Where-Object Health -In 'unhealthy', 'degraded'
```

The routes that reach unhealthy backends.

## PARAMETERS

### -CertificateDays

A certificate expiring within this many days is a finding (30 by
default).

```yaml
Type: System.Int32
DefaultValue: 30
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

Write the flows to this CSV file.

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

### -Direction

LeftToRight (the default) or TopToBottom.

```yaml
Type: System.String
DefaultValue: "'LeftToRight'"
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

### -IncludeHealth

Run each gateway's live backend health check: every target's state
and the probe's reason.

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

### -Name

Only gateways with these names; wildcards work.

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

### -PassThru

Also return the map: gateways, flows, findings, cards and lines.

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

Write a PDF report: gateways, flows and findings.

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

### -ResourceGroupName

Only these resource groups.

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

### -Theme

Dark (the default), Light or Blueprint.

```yaml
Type: System.String
DefaultValue: "'Dark'"
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

### -Title

The map's title.

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.ApplicationGatewayMap, with -PassThru

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Show-AACApplicationGatewayMap.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
