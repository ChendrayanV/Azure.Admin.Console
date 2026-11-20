---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACSentinelThreatIntelligence.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Get-AACSentinelThreatIntelligence
---

# Get-AACSentinelThreatIntelligence

## SYNOPSIS

Summarises the threat intelligence in a Microsoft Sentinel workspace - indicators by source and type: how many, active, expired or about to expire, confidence, when each feed last updated - and whether any analytics rule matches on them. -Indicator lists the indicators themselves.

## SYNTAX

### __AllParameterSets

```
Get-AACSentinelThreatIntelligence [-WorkspaceId] <string> [-SubscriptionId <string[]>]
 [-ResourceGroupName <string>] [-Days <int>] [-Indicator] [-Source <string[]>]
 [-IndicatorType <string[]>] [-Value <string[]>] [-IncludeExpired] [-Limit <int>]
 [-StaleAfterDays <int>] [-CsvPath <string>] [-HtmlPath <string>] [-PdfPath <string>]
 [-Title <string>] [-PassThru] [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Reads the workspace - read-only, nothing is changed - from:

```text
  the workspace itself     KQL: ThreatIntelIndicators (STIX, current)
                           and ThreatIntelligenceIndicator (legacy),
                           each indicator's latest record in -Days
  Azure Resource Manager   the data connectors and analytics rules
```

By default, a row per source and indicator type (AAC.SentinelThreat
IntelSource): Source, IndicatorType, Indicators, Active, Expired,
ExpiringSoon (within 7 days), AverageConfidence, LowConfidence (below
50), LastUpdated, DaysSinceUpdate, Findings and Table. Findings: no
update for longer than -StaleAfterDays (a feed that stopped), none
active, mostly low confidence.

With -Indicator, the indicators (AAC.SentinelThreatIndicator), newest
first, at most -Limit from each table: Value, IndicatorType, Source,
Confidence, Active, ValidFrom, ValidUntil, LastUpdated, Name, Tags,
Description, Table and Id. Expired ones are left out unless
-IncludeExpired.

The view also says when no indicators arrive, when no enabled rule
reads the threat intelligence tables, when rules still read the
legacy table that has no data, and when a threat intelligence
connector is disconnected.

Needs Log Analytics Reader and Microsoft Sentinel Reader on the
workspace.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Get-AACSentinelThreatIntelligence -WorkspaceId 'law-contoso-sentinel'
```

Indicators by source and type, stale feeds first.

### Example 2

```powershell
Get-AACSentinelThreatIntelligence -WorkspaceId 'law-contoso-sentinel' -Indicator -IndicatorType ipv4-addr -Value '203.0.113.*'
```

The active IP indicators in a range.

### Example 3

```powershell
Get-AACSentinelThreatIntelligence -WorkspaceId 'law-contoso-sentinel' -Indicator -Source 'Microsoft Defender*' -CsvPath .\out\Indicators.csv
```

One feed's active indicators, to CSV.

## PARAMETERS

### -CsvPath

Write the rows to this CSV file.

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

How far back to look for indicator records: 1 to 365 days, 30 by
default. Feeds refresh their indicators, so 30 days holds the current
ones.

```yaml
Type: System.Int32
DefaultValue: 30
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

### -IncludeExpired

With -Indicator: also list expired and inactive indicators.

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

### -Indicator

List the indicators rather than the summary.

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

### -IndicatorType

Only these indicator types (ipv4-addr, ipv6-addr, domain-name, url,
file, email-addr...); wildcards work.

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

### -Limit

With -Indicator: read at most this many from each table, newest first:
5,000 by default.

```yaml
Type: System.Int32
DefaultValue: 5000
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

### -Source

Only these sources; wildcards work.

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

### -StaleAfterDays

Call a source stale when it hasn't updated an indicator for longer
than this: 7 days by default.

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

### -Title

The HTML and PDF reports' title.

```yaml
Type: System.String
DefaultValue: "'Microsoft Sentinel threat intelligence'"
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

### -Value

With -Indicator: only indicators whose value matches; wildcards work.

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

### AAC.SentinelThreatIntelSource, or AAC.SentinelThreatIndicator with -Indicator (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACSentinelThreatIntelligence.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
