---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACCostAnomaly.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Get-AACCostAnomaly
---

# Get-AACCostAnomaly

## SYNOPSIS

Finds unusual Azure spend before it reaches the invoice - spikes, drops, new spend, level shifts and steady rises by service, resource group, region or meter - with the resources behind each, a month-end forecast and how each subscription compares with the others.

## SYNTAX

### __AllParameterSets

```
Get-AACCostAnomaly [[-SubscriptionId] <string[]>] [[-ManagementGroupId] <string[]>]
 [[-ResourceGroupName] <string[]>] [[-By] <string>] [[-Days] <int>] [[-EvaluateDays] <int>]
 [[-SettleDays] <int>] [[-Sensitivity] <string>] [[-MinimumImpact] <double>] [[-RootCause] <int>]
 [[-CsvPath] <string>] [[-HtmlPath] <string>] [[-PdfPath] <string>] [[-Title] <string>] [-PassThru]
 [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Reads each subscription's daily cost (Cost Management, actual cost)
for the last -Days, split by -By, and looks at each series with
robust statistics - a median and median absolute deviation baseline
of the 28 days before each day, so one past spike doesn't hide the
next:

```text
  Spike     a day well above its baseline (robust z-score at or over
            the -Sensitivity threshold, and at least -MinimumImpact
            and 25% more)
  Drop      a day well below - spend that stopped: an outage, a
            deletion, something switched off
  New       spend where there was none
  Shift     the last 7 days at a new, higher level
  Trend     a steady rise projected 50% higher over 30 days
  Forecast  a subscription on track to cost 20% or more than last
            month
```

Consecutive days are one anomaly. Each has a severity - from its
cost impact against the subscription's average month - the actual
and expected cost, and what to do. For the largest (-RootCause, 5 by
default) the resources behind it are read and named: the ones whose
daily cost rose most.

The subscriptions table compares each one's last 7 days with the 7
before, against the median of all of them (a team or subscription
benchmark).

Cost data lags: today is never assessed, and -SettleDays (1)
complete days more can be left out while Cost Management catches
up. Cost Management allows a few queries a minute, so subscriptions
are read three at a time.

Needs Cost Management Reader (or Reader) on the subscriptions.
Read-only.

## EXAMPLES

### Example 1

```powershell
Get-AACCostAnomaly
```

Anomalies by service in every subscription, over the last 60 days.

### Example 2

```powershell
Get-AACCostAnomaly -ManagementGroupId 'mg-landingzones' -By ResourceGroup -Sensitivity High -HtmlPath .\out\CostAnomalies.html
```

Every resource group under a management group, sensitive, as an HTML report.

### Example 3

```powershell
Get-AACCostAnomaly -NoDisplay | Where-Object Severity -In 'Critical', 'High' | Select-Object Finding, CostImpact, TopResources
```

The serious ones, with the resources behind them - e.g. for a daily alert.

## PARAMETERS

### -By

What each series is: ServiceName (the default), ResourceGroup,
Location, Meter (meter category) or Subscription (its total).

```yaml
Type: System.String
DefaultValue: "'ServiceName'"
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

Write the anomalies to this CSV file.

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

### -Days

How many days of history to read (21 to 365, 60 by default).

```yaml
Type: System.Int32
DefaultValue: 60
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

### -EvaluateDays

How many of the latest days to look for spikes, drops and new spend
in (1 to 30, 7 by default). Shifts, trends and forecasts use the
whole window.

```yaml
Type: System.Int32
DefaultValue: 7
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

### -HtmlPath

Write an interactive HTML report: tiles, the daily cost, anomalies by
kind, the anomalies and the subscriptions - searchable, filterable,
downloadable as CSV.

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

### -ManagementGroupId

Only the subscriptions under these management groups (at any depth).

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

### -MinimumImpact

The least cost difference, in the billing currency, an anomaly must
make (10 by default) - so cents don't count.

```yaml
Type: System.Double
DefaultValue: 10
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

### -NoDisplay

Return the anomalies without showing the view.

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

Show the view and also return the anomalies.

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
  Position: 12
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ResourceGroupName

Only the cost of these resource groups.

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

### -RootCause

How many of the largest anomalies to find the resources behind (0 to
20, 5 by default; each is one more Cost Management query).

```yaml
Type: System.Int32
DefaultValue: 5
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

### -Sensitivity

Low (fewer, bigger anomalies), Medium (the default) or High.

```yaml
Type: System.String
DefaultValue: "'Medium'"
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

### -SettleDays

Complete days at the end to leave out while Cost Management catches
up (0 to 3, 1 by default).

```yaml
Type: System.Int32
DefaultValue: 1
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

The reports' title.

```yaml
Type: System.String
DefaultValue: "'Azure cost anomalies'"
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.CostAnomaly

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACCostAnomaly.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
