---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Show-AACCost.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Show-AACCost
---

# Show-AACCost

## SYNOPSIS

Shows what your Azure subscriptions cost - month to date and the last few months - as colourful Spectre.Console charts, with optional CSV, PDF and interactive HTML exports of the detail.

## SYNTAX

### __AllParameterSets

```
Show-AACCost [[-SubscriptionId] <string[]>] [[-Months] <int>] [[-Top] <int>] [[-CsvPath] <string>]
 [[-PdfPath] <string>] [[-HtmlPath] <string>] [[-Title] <string>] [-NoPaging] [-PassThru]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Asks the Azure Cost Management Query API, over REST with the
Connect-AAC sign-in (no Az modules), for each subscription's actual
cost over the last -Months months (this month so far included),
broken down by month, service and resource group - one query per
subscription. The view:

```text
  ── Azure Admin Console :: Azure cost ──────────────────────────
  account · tenant · subscriptions · period · when
  [ month to date ] [ last month ] [ period total ] [ subscriptions ] [ top service ]

  Month to date by subscription   (when there is more than one)
  Month to date by service        (one bar split by service)
  Month to date by resource group (top 10)
  Last N months                   (one bar per month)
  Actual cost by subscription and month - with a total column and,
  for several subscriptions, a total row
```

Amounts are in each subscription's billing currency and never
converted; subscriptions billed in different currencies get charts
of their own. When Cost Management reports no cost at all for a
period, the view says so instead of drawing empty charts.

Subscriptions Cost Management can't report on (some offer types,
such as sponsorships, or missing permission) are listed with the
reason under the charts rather than failing the run. A subscription
with no cost in the period (new, empty, or billed elsewhere) is not
an error either: its Status is 'No cost', it is left out of the
charts and totals, and every output lists it as having no cost. Cost Management
allows only a few queries a minute, so a progress display shows each
subscription as it is read, and throttled requests are retried.

Exports:

```text
  -CsvPath    the detail: one row per subscription, month, resource
              group and service - SubscriptionName, SubscriptionId,
              Month, ResourceGroup, Service, Cost, Currency - ready
              for an Excel pivot table
  -PdfPath    a landscape A4 report: a summary (totals, the
              subscription-by-month table, top services and
              resource groups this month), then a page per
              subscription with its services and resource groups
              month by month
  -HtmlPath   a self-contained, interactive HTML report: tiles and
              charts (by month, subscription, service, resource
              group) that filter the detail, a subscription-by-month
              table and every detail row, with search, filters,
              grouping, totals of what is shown and a CSV download
  -PassThru   one AAC.SubscriptionCost object per subscription:
              MonthToDate, one property per month ('2026-07', ...),
              Total, TopServices and Status ('OK', 'No cost', or
              why the subscription couldn't be read)
```

When any of -CsvPath, -PdfPath or -HtmlPath is given, the console
shows only the progress and the files written - the report is in
the files. Otherwise the view is paged when it is longer than the
terminal: press any key for the next page, or A for the rest
(-NoPaging turns that off).

Reading costs needs Cost Management Reader (or Reader) on the
subscriptions. Costs are "actual cost" as Cost Management reports
it, which can lag usage by a day or so. PDF export needs Windows and
PowerShell 7.4 or later.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Show-AACCost
```

Month to date and the last 6 months for every subscription you can see.

### Example 2

```powershell
Show-AACCost -Months 12 -CsvPath .\out\Cost.csv -PdfPath .\out\Cost.pdf
```

The last year as a detail CSV file and a PDF report.

### Example 3

```powershell
Show-AACCost -Months 12 -HtmlPath .\out\Cost.html
```

The last year in an interactive HTML report.

### Example 4

```powershell
Show-AACCost -SubscriptionId '00000000-0000-0000-0000-000000000000' -Months 3
```

One subscription over the last three months.

### Example 5

```powershell
Show-AACCost -PassThru | Export-Csv .\CostSummary.csv -NoTypeInformation
```

One row per subscription, with a column per month.

## PARAMETERS

### -CsvPath

Also write the detail - one row per subscription, month, resource
group and service - to this CSV file. An existing file is
overwritten; missing folders are created.

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

Also write an interactive HTML report to this file. An existing file
is overwritten; missing folders are created.

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

### -Months

How many months to cover, this month included (default 6, up to 12).

```yaml
Type: System.Int32
DefaultValue: 6
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

### -NoPaging

Show the whole view at once instead of a screen at a time.

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

Also return the costs as AAC.SubscriptionCost objects.

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

Also write a PDF report to this file. An existing file is
overwritten; missing folders are created.

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

### -SubscriptionId

Only these subscriptions. Defaults to every enabled subscription the
signed-in account can see.

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

The PDF and HTML report's title. Defaults to 'Azure cost'.

```yaml
Type: System.String
DefaultValue: "'Azure cost'"
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

### -Top

How many services the month-to-date breakdown shows (default 8); the
rest are summed as "other services".

```yaml
Type: System.Int32
DefaultValue: 8
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.SubscriptionCost (with -PassThru)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Show-AACCost.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
