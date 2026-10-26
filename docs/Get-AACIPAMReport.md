---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACIPAMReport.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Get-AACIPAMReport
---

# Get-AACIPAMReport

## SYNOPSIS

IP address management without a server: Azure's address space measured against your address plan - spaces and blocks, every network, subnet and private IP address, overlaps, free space and the next ranges to hand out - as a Spectre.Console view, objects, and CSV, PDF and a tabbed, interactive HTML report.

## SYNTAX

### __AllParameterSets

```
Get-AACIPAMReport [[-AddressPlan] <Object>] [[-SubscriptionId] <string[]>]
 [[-ManagementGroupId] <string[]>] [[-NextAvailable] <int[]>] [[-TestCidr] <string[]>]
 [[-WarningPercent] <int>] [[-CriticalPercent] <int>] [[-View] <string>] [[-CsvPath] <string>]
 [[-HtmlPath] <string>] [[-PdfPath] <string>] [[-Title] <string>] [-Open] [-PassThru] [-NoDisplay]
 [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Read-only, from Azure Resource Graph (Reader is enough, no Az
modules, nothing to deploy): virtual networks with their subnets,
peerings and DNS servers, Virtual WAN hubs, network interfaces, scale
set instances, load balancers, firewalls, Bastion, gateways,
application gateways, Private Link services, private endpoints and
public IPs. Nothing is stored: every run is worked out afresh from
Azure, so it can't drift from what is deployed.

The address plan (-AddressPlan) is what Azure is measured against:
spaces (an organisation, a region, an environment) holding blocks
(the ranges handed out to Azure), plus external ranges - on-premises
or partner networks - that Azure must not overlap. Without one, the
private ranges are the plan: RFC 1918 (10/8, 172.16/12, 192.168/16)
and RFC 6598 shared space (100.64/10).

The report:

```text
  Spaces          each space's blocks, size, allocated and free
                  addresses, networks, subnets, addresses in use
  Blocks          each block's networks, address space allocated (the
                  union of the network and external prefixes in it),
                  free space, its largest free range, the next free
                  range of the first -NextAvailable size and how many
                  still fit, and its status: Warning at
                  -WarningPercent, Critical at -CriticalPercent, Full
  Networks        virtual networks, Virtual WAN hubs and external
                  ranges: Managed (every IPv4 prefix in a block),
                  Partly managed or Unmanaged; prefixes, subnets,
                  addresses used and free, address space in no subnet,
                  DNS servers (or Azure-provided), peerings, overlaps,
                  the Azure IPAM reservation tag (X-IPAM-RES-ID)
  Subnets         prefix, address range and usable range (Azure keeps
                  the first four addresses and the last), usable /
                  used / available, purpose (gateway, firewall,
                  Bastion, delegated, private endpoints, workloads)
                  and what takes the addresses
  IP addresses    every address Azure lists in a subnet - virtual
                  machines, scale set instances, private endpoints,
                  load balancer frontends, firewalls, gateways,
                  Bastion, application gateways, unattached network
                  interfaces - with its allocation (static, dynamic),
                  public IP and what it belongs to; a subnet's count
                  and its list always agree
  Overlaps        every pair of address spaces that overlap: High when
                  the networks are peered (traffic can't route),
                  Medium with an external range or a hub, Low otherwise
  Free space      every free range of every block; the next ranges of
                  each -NextAvailable size: the best fit (the smallest
                  free range it fits, so larger ranges stay whole) and
                  the lowest free address
  CIDR check      each -TestCidr: free, taken or partly taken, and by
                  what
  Findings        full and filling blocks and subnets, overlaps,
                  networks outside (or straddling) the plan, networks
                  spanning blocks, a reservation tag on an unplanned
                  network, unattached interfaces holding addresses,
                  unused blocks
```

The HTML report has a tab for each, a tree of the plan (space \>
block \> network \> subnet) on its Summary tab, a Space selector that
filters every tab, and a card that follows the pointer over a row
with its details (click the row for every field).

What you get depends on where the command runs:

```text
  at the prompt    tiles and the main tables, a page at a time
  piped onward     the -View rows, with no view
  -PassThru        the view and the rows
  -NoDisplay       the rows only
```

-CsvPath writes the -View rows; -HtmlPath and -PdfPath the reports;
-Open opens the HTML report (in a temporary file without -HtmlPath).

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Get-AACIPAMReport -Open
```

Every network you can see against the private ranges, in your browser.

### Example 2

```powershell
Get-AACIPAMReport -AddressPlan .\ipam-plan.psd1 -HtmlPath .\IPAM.html -PdfPath .\IPAM.pdf
```

Your plan's spaces and blocks: what is allocated, free, overlapping, and what to hand out next.

### Example 3

```powershell
Get-AACIPAMReport -AddressPlan .\ipam-plan.psd1 -NextAvailable 24, 22 -View NextAvailable -NoDisplay | Where-Object Fit -EQ 'Best fit'
```

The next /24 and /22 of every block, for a new network.

### Example 4

```powershell
Get-AACIPAMReport -TestCidr 10.20.8.0/22, 10.21.0.0/16
```

Are these ranges free? If not, which networks have them.

### Example 5

```powershell
Get-AACIPAMReport -ManagementGroupId 'mg-landingzones' -View IpAddress -CsvPath .\ips.csv
```

Every private IP address of a landing zone, to feed another IPAM or CMDB.

## PARAMETERS

### -AddressPlan

The address plan: the path of a .psd1, .json or .csv file, or a
hashtable.

As a .psd1 or .json file, or a hashtable:

```text
  @{ Spaces = @(
         @{ Name = 'Corp'; Description = '...'; Blocks = @(
             @{ Name = 'Azure-EU'; Cidr = '10.20.0.0/14' }
             @{ Name = 'Azure-US'; Cidr = '10.24.0.0/14' } ) } )
     External = @( @{ Name = 'London DC'; Cidr = '10.0.0.0/16' } ) }
```

As a .csv file: one row per range - Space, Block, Cidr, Kind (Block, or
External: then Block is its name), Description.

Blocks of one space must not overlap; blocks of different spaces
may (a network then counts in both).

```yaml
Type: System.Object
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

### -CriticalPercent

A block or subnet this full (in %) is flagged Critical (90 if not
given).

```yaml
Type: System.Int32
DefaultValue: 90
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

Write the tabbed, interactive HTML report.

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

Only the networks in the subscriptions under these management
groups.

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

### -NextAvailable

The prefix lengths to find free ranges for (24 if not given; 8 to
29): -NextAvailable 24, 22 lists the next /24 and /22 of every block.
The first is the one the Blocks tab shows.

```yaml
Type: System.Int32[]
DefaultValue: '@(24)'
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

### -Open

Open the HTML report when it is written - in a temporary file when
-HtmlPath isn't given.

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

### -SubscriptionId

Only the networks in these subscriptions.

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

### -TestCidr

Ranges to check: free, taken or partly taken, and by what. The
objects returned are then these checks (unless -View says else).

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

### -Title

The reports' title.

```yaml
Type: System.String
DefaultValue: "'IP address management report'"
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

What is returned and written to -CsvPath: Block (default), Space,
Network, Subnet, IpAddress, Overlap, FreeRange, NextAvailable,
CidrCheck or Finding.

```yaml
Type: System.String
DefaultValue: "'Block'"
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

### -WarningPercent

A block or subnet this full (in %) is flagged Warning (80 if not
given).

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

### AAC.IpamBlock, AAC.IpamSpace, AAC.IpamNetwork, AAC.IpamSubnet, AAC.IpamIpAddress, AAC.IpamOverlap, AAC.IpamFreeRange, AAC.IpamNextAvailable, AAC.IpamCidrCheck or AAC.IpamFinding, by -View (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACIPAMReport.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
