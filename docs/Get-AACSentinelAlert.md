---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACSentinelAlert.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Get-AACSentinelAlert
---

# Get-AACSentinelAlert

## SYNOPSIS

Lists the security alerts in a Microsoft Sentinel workspace - from its analytics rules and every connected product (Defender XDR, Defender for Cloud, Entra ID Protection...) - with their MITRE ATT&CK tactics, the hosts, accounts and IP addresses involved, and the incident each is in.

## SYNTAX

### __AllParameterSets

```
Get-AACSentinelAlert [-WorkspaceId] <string> [-SubscriptionId <string[]>]
 [-ResourceGroupName <string>] [-Days <int>] [-Severity <string[]>] [-Status <string[]>]
 [-Name <string[]>] [-Product <string[]>] [-Tactic <string[]>] [-Entity <string[]>]
 [-IncidentNumber <int[]>] [-NoIncident] [-Limit <int>] [-CsvPath <string>] [-HtmlPath <string>]
 [-PdfPath <string>] [-Title <string>] [-PassThru] [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Queries the workspace's SecurityAlert table with KQL - read-only,
nothing is changed - taking the latest record of each alert (an alert
is written again when its status changes), and SecurityIncident for the
incident each alert was grouped into.

Each alert: Alert, Severity, Status, Open, Product, Provider,
Component, Tactics, Techniques, CompromisedEntity, Hosts, Accounts,
IpAddresses, Entities (the other kinds), TimeGenerated, AgeDays,
StartTime, EndTime, IncidentNumber, IncidentTitle, IncidentStatus,
Occurrences (alerts in the list with the same name and compromised
entity), Description, Remediation, ExtendedProperties (a dictionary),
AlertType, AlertId and AlertUrl.

The last 7 days by default (-Days), newest first, at most -Limit
alerts (10,000). -Severity is applied in the query; the other filters
in PowerShell.

At the prompt: tiles, the alerts by severity, product, tactic and day,
the alerts, and the ones raised again and again. Alerts in no incident
come from rules that don't create incidents, or products whose
incidents aren't synced: -NoIncident lists them.

Needs Log Analytics Reader (or Microsoft Sentinel Reader) on the
workspace. Get-AACSecurityAlert lists Defender for Cloud's alerts
across subscriptions instead.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Get-AACSentinelAlert -WorkspaceId 'law-contoso-sentinel'
```

The last 7 days of alerts, newest first.

### Example 2

```powershell
Get-AACSentinelAlert -WorkspaceId 'law-contoso-sentinel' -Days 30 -Severity High, Medium -HtmlPath .\out\SentinelAlerts.html
A month of High and Medium alerts, as an interactive HTML report.
```

### Example 3

```powershell
Get-AACSentinelAlert -WorkspaceId 'law-contoso-sentinel' -IncidentNumber 4211 -NoDisplay | Select-Object Alert, Accounts, Hosts, IpAddresses
```

Who and what is in one incident's alerts.

### Example 4

```powershell
Get-AACSentinelAlert -WorkspaceId 'law-contoso-sentinel' -Entity '*alice*' -Days 90 -NoDisplay | Sort-Object TimeGenerated
```

Every alert about one user over 90 days, oldest first.

### Example 5

```powershell
Get-AACSentinelAlert -WorkspaceId 'law-contoso-sentinel' -NoIncident -NoDisplay | Group-Object Alert | Sort-Object Count -Descending
```

The alerts no incident was created for, by name.

## PARAMETERS

### -CsvPath

Write the alerts to this CSV file.

```yaml
Type: System.String
DefaultValue: None
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

### -Days

How far back to look: 1 to 3650 days, 7 by default.

```yaml
Type: System.Int32
DefaultValue: 7
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

### -Entity

Only alerts whose compromised entity, hosts, accounts, IP addresses or
other entities match; wildcards work (for example '\*alice\*').

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: true
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

Write an interactive HTML report to this file.

```yaml
Type: System.String
DefaultValue: None
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

### -IncidentNumber

Only the alerts in these incidents.

```yaml
Type: System.Int32[]
DefaultValue: None
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

### -Limit

Read at most this many alerts, newest first: 10,000 by default.

```yaml
Type: System.Int32
DefaultValue: 10000
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

Only alerts whose name matches; wildcards work.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: true
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

Return the alerts without showing the view.

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

### -NoIncident

Only the alerts that are in no incident.

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

Show the view and also return the alerts.

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
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Product

Only alerts from products whose name matches (for example 'Azure
Sentinel', 'Microsoft Defender\*'); wildcards work.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: true
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

Narrows a workspace given by name, when the name is in more than one
resource group.

```yaml
Type: System.String
DefaultValue: None
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

### -Severity

Only alerts of these severities (High, Medium, Low, Informational).

```yaml
Type: System.String[]
DefaultValue: None
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

### -Status

Only alerts in these states (New, InProgress, Resolved, Dismissed).

```yaml
Type: System.String[]
DefaultValue: None
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

Where to look for a workspace given by ID (GUID) or name. Every
subscription the account can see by default.

```yaml
Type: System.String[]
DefaultValue: None
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

### -Tactic

Only alerts with one of these MITRE ATT&CK tactics (for example
InitialAccess, 'Lateral\*'); wildcards work.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: true
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

### -Title

The HTML and PDF reports' title.

```yaml
Type: System.String
DefaultValue: "'Microsoft Sentinel alerts'"
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

### -WorkspaceId

The workspace: its workspace ID (GUID), resource ID or name.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases:
- Workspace
- WorkspaceName
- ResourceId
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: true
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

### AAC.SentinelAlert (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACSentinelAlert.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
