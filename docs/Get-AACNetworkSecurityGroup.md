---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACNetworkSecurityGroup.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Get-AACNetworkSecurityGroup
---

# Get-AACNetworkSecurityGroup

## SYNOPSIS

A detailed assessment of network security groups: what each is applied to, every rule, its flow logs and diagnostic settings, and the risks in them - with a Spectre.Console view, objects, and CSV, PDF and interactive HTML reports.

## SYNTAX

### __AllParameterSets

```
Get-AACNetworkSecurityGroup [[-SubscriptionId] <string[]>] [[-ResourceGroupName] <string[]>]
 [[-Name] <string[]>] [[-CsvPath] <string>] [[-PdfPath] <string>] [[-HtmlPath] <string>]
 [[-Title] <string>] [-NoDiagnosticSetting] [-PassThru] [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Reads the NSGs, the network interfaces and subnets they are applied
to and the Network Watcher flow logs with Azure Resource Graph, and
each NSG's diagnostic settings through Azure Resource Manager - with
the Connect-AAC sign-in; Reader access is enough, no Az modules.
Without parameters it assesses every NSG the account can see.

For each NSG:

```text
  Metadata      name, resource ID, subscription, resource group,
                location, tags
  Associations  the subnets (VNet, prefix) and network interfaces
                (VM, private IP) it is applied to
  Rules         every rule, custom and default, in the order Azure
                evaluates them: priority, direction, protocol,
                source, source port, destination, destination port
                (application security groups by name), action
  Telemetry     diagnostic settings (enabled or not; Log Analytics
                workspace, storage account, event hub; log
                categories), flow logs (an NSG flow log, or a virtual
                network flow log on its VNet, subnet or NIC; enabled,
                retention, storage) and Traffic Analytics
```

Findings, each with a severity, the rule it is about and what to do:

```text
  High    an inbound Allow from *, Internet or 0.0.0.0/0 to every
          port or to a management or database port (SSH, RDP, WinRM,
          SMB, Telnet, FTP, SQL, MySQL, PostgreSQL, Oracle, MongoDB,
          Redis, VNC, Docker, ...)
  Medium  a wide port range (over 100 ports) open to the internet; an
          NSG on no subnet and no NIC; a NIC NSG and its subnet's NSG
          that disagree - one allows what the other denies, so the
          traffic is blocked (both are evaluated, first matching rule
          by priority, as Azure does); applied to something with no
          flow log, or a disabled one
  Low     ICMP from the internet; everything allowed from the whole
          virtual network; a shadowed rule - one an earlier rule
          fully covers, so it never applies; flow logs kept under 90
          days; no diagnostic settings
  Info    flow logs without Traffic Analytics; only an NSG flow log
          (they retire on 30 September 2027: migrate to virtual
          network flow logs); over 800 of the 1,000 rules an NSG can
          hold
```

What you get depends on where the command runs:

```text
  at the prompt    tiles, a table of the NSGs with their risk, the
                   High and Medium findings, and - for up to three
                   NSGs - each one in detail with its rules, a page
                   at a time
  piped onward     the AAC.NetworkSecurityGroup objects, with no view
  -PassThru        the view and the objects
  -NoDisplay       the objects only
```

-CsvPath writes every rule (with its NSG, risk and finding) to CSV.
-HtmlPath writes an interactive report - tiles, charts, and tables of
the NSGs, rules, findings, associations and logging, each with its
own CSV download. -PdfPath writes a PDF: the summary, the findings,
and a section per NSG with its associations, telemetry and rules.
With any of them, the console shows only the progress and the files
written.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Get-AACNetworkSecurityGroup
```

Every NSG the account can see, assessed.

### Example 2

```powershell
Get-AACNetworkSecurityGroup -SubscriptionId '00000000-0000-0000-0000-000000000000' -ResourceGroupName 'rg-network' -Name 'nsg-web', 'nsg-app'
```

Two NSGs in detail, with their rules.

### Example 3

```powershell
Get-AACNetworkSecurityGroup -HtmlPath .\out\NSG.html -PdfPath .\out\NSG.pdf -CsvPath .\out\NSG-rules.csv
```

The full assessment as an interactive HTML report, a PDF and a CSV of every rule.

### Example 4

```powershell
(Get-AACNetworkSecurityGroup -NoDisplay).Findings | Where-Object Severity -EQ 'High'
```

The High-severity findings.

## PARAMETERS

### -CsvPath

Write every rule, with its NSG, risk and finding, to this CSV file.

```yaml
Type: System.String
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

### -HtmlPath

Write an interactive HTML report to this file.

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

### -Name

Only these NSGs; wildcards work, e.g. 'nsg-web-\*'.

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

### -NoDiagnosticSetting

Don't read the NSGs' diagnostic settings (one Azure Resource Manager
call per NSG); their status is then "Not checked".

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
  Position: 4
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ResourceGroupName

Only NSGs in these resource groups.

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

### -Title

The PDF and HTML reports' title.

```yaml
Type: System.String
DefaultValue: "'Network security group assessment'"
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.NetworkSecurityGroup (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACNetworkSecurityGroup.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
