---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACVirtualNetworkAssessment.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Invoke-AACVirtualNetworkAssessment
---

# Invoke-AACVirtualNetworkAssessment

## SYNOPSIS

Assesses virtual networks: address space and available IPs, every subnet, peerings, NSGs and application security groups, DNS, DDoS, flow logs, outbound access and gateways - with findings and what to do, a Spectre.Console view, objects, and CSV, PDF and interactive HTML reports.

## SYNTAX

### __AllParameterSets

```
Invoke-AACVirtualNetworkAssessment [[-SubscriptionId] <string[]>] [[-ManagementGroupId] <string[]>]
 [[-ResourceGroupName] <string[]>] [[-Name] <string[]>] [[-CsvPath] <string>] [[-PdfPath] <string>]
 [[-HtmlPath] <string>] [[-Title] <string>] [-PassThru] [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Reads, with Azure Resource Graph - read-only, Reader is enough, no Az
modules - the virtual networks and everything in or around them:
network interfaces, route tables, NAT gateways, network security
groups, application security groups, public IPs, private endpoints,
private DNS zone links, DNS resolvers, VPN and ExpressRoute gateways,
Azure Firewalls, Bastion hosts and Network Watcher flow logs.
Without parameters it assesses every virtual network the account can
see; -SubscriptionId, -ManagementGroupId, -ResourceGroupName and
-Name narrow it.

For each virtual network:

```text
  Metadata      name, role (hub, spoke, peered, standalone), location,
                resource group, subscription, tags, provisioning
                state, flow timeout, BGP community
  Address space its prefixes; total IPs, IPs in subnets, unallocated
                IPs; usable (Azure keeps 5 per subnet), used and
                available IPs; the free CIDR blocks a new subnet can
                take; overlaps with any other network you can see
  Subnets       prefix, usable / used / available IPs and % used,
                purpose (gateway, firewall, Bastion, Route Server,
                delegated, private endpoints, workloads), NSG, route
                table and its default route, BGP propagation, NAT
                gateway, the outbound path (NAT gateway, firewall or
                NVA, forced tunnelling, public IPs, private subnet,
                default outbound access), service endpoints and
                policies, delegations, private endpoints and their
                network policies, NICs, VMs, NICs with public IPs or
                IP forwarding, flow logs
  Peerings      state, sync, remote network / subscription / region,
                global, the allow* flags, gateway transit, remote
                address space, subnet peering, reverse peering
  Security      DNS servers and private DNS zone links, DDoS
                protection, virtual network encryption, flow logs,
                Firewall and Bastion, private endpoints, ASGs (who
                is in each, which rules name it) - and the NSGs on
                its subnets, assessed rule by rule as
                Get-AACNetworkSecurityGroup does
```

Findings, each with a severity, the network and item, and what to do:

```text
  High    a full subnet (or 95% used); a peering not Connected; an NSG
          or a 0.0.0.0/0 route on GatewaySubnet; Bastion, Firewall or
          Route Server subnets too small; an NSG rule open to the
          internet on a management or database port
  Medium  a subnet 80% used; a peering out of sync; a subnet with
          workloads and no NSG; VMs with public IPs; default outbound
          access (being retired); public IPs without DDoS Network
          Protection; no virtual network flow logs; private endpoints
          whose privatelink zone isn't linked; private endpoint
          connections not approved; a Basic VPN gateway; a
          GatewaySubnet under /27
  Low     oversized or empty subnets; no free address space;
          overlapping address spaces; encryption off; a single DNS
          server; private endpoint network policies off; IP
          forwarding with no route to it; empty or unused ASGs;
          gateways that aren't zone-redundant
  Info    global peering (charged per GB); a remote network you
          can't read; no Bastion where VMs have public IPs
```

What you get depends on where the command runs:

```text
  at the prompt    tiles, the networks with their IP capacity and
                   risk, the High and Medium findings, and - for up
                   to three networks - each in detail with its
                   subnets, peerings and free ranges, a page at a time
  piped onward     the AAC.VirtualNetwork objects (each with its
                   Subnets, Peerings, FreeRangeList,
                   PrivateEndpointList and Findings), with no view
  -PassThru        the view and the objects
  -NoDisplay       the objects only
```

-CsvPath writes every subnet to CSV. -HtmlPath writes an interactive
report - tiles, charts and tables of networks, subnets, peerings,
free ranges, findings, private endpoints, ASGs and NSG rules, each
collapsible and downloadable as CSV. -PdfPath writes a PDF with a
section per network. With any of them, the console shows only the
progress and the files written.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Invoke-AACVirtualNetworkAssessment
```

Every virtual network the account can see, assessed.

### Example 2

```powershell
Invoke-AACVirtualNetworkAssessment -SubscriptionId 00000000-0000-0000-0000-000000000000 -Name 'vnet-hub-*', 'vnet-spoke-app'
```

Some networks in detail: subnets, peerings, free ranges and findings.

### Example 3

```powershell
Invoke-AACVirtualNetworkAssessment -ManagementGroupId 'mg-landingzones' -HtmlPath .\out\VNet.html -PdfPath .\out\VNet.pdf -CsvPath .\out\Subnets.csv
A landing zone's networks as an interactive HTML report, a PDF and a CSV of every subnet.
```

### Example 4

```powershell
(Invoke-AACVirtualNetworkAssessment -NoDisplay).Subnets | Where-Object UsedPercent -GE 80 | Sort-Object UsedPercent -Descending
```

The subnets running out of IPs.

### Example 5

```powershell
Invoke-AACVirtualNetworkAssessment -Name 'vnet-spoke-app' -NoDisplay | Select-Object -ExpandProperty FreeRangeList
```

Where a new subnet fits.

## PARAMETERS

### -CsvPath

Write every subnet to this CSV file.

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

Only the virtual networks under these management groups.

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

### -Name

Only these virtual networks; wildcards work, e.g. 'vnet-hub-\*'.

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

Only the virtual networks in these resource groups.

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

Only the virtual networks in these subscriptions.

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

### -Title

The PDF and HTML reports' title.

```yaml
Type: System.String
DefaultValue: "'Virtual network assessment'"
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

### AAC.VirtualNetwork (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACVirtualNetworkAssessment.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
