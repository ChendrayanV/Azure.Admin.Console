---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACAdvisorRecommendation.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Get-AACAdvisorRecommendation
---

# Get-AACAdvisorRecommendation

## SYNOPSIS

Gets a consolidated, flattened view of Azure Advisor recommendations (Resource Graph's advisorresources table): a Spectre.Console summary at the prompt, PowerShell objects down a pipeline, and optional CSV PDF and interactive HTML exports.

## SYNTAX

### __AllParameterSets

```
Get-AACAdvisorRecommendation [[-SubscriptionId] <string[]>] [[-Category] <string[]>]
 [[-Impact] <string[]>] [[-CsvPath] <string>] [[-PdfPath] <string>] [[-HtmlPath] <string>]
 [[-Title] <string>] [-IncludeSuppressed] [-ExpandExtendedProperty] [-PassThru] [-NoDisplay]
 [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Reads every Azure Advisor recommendation the signed-in account can
see (or only those in -SubscriptionId) from the advisorresources table
in Azure Resource Graph, over REST with the Connect-AAC sign-in - no
Az modules needed. Every Advisor category is covered: Cost, Security,
Reliability (HighAvailability in the API), Operational excellence and
Performance.

Each recommendation's nested JSON is flattened to one flat row:
subscription name, resource group, impacted resource name and type,
category, impact, problem and solution, estimated monthly and annual
savings with currency, retirement date and feature (for service
retirement recommendations), last updated time and links. Advisor's
free-form extendedProperties bag, whose keys differ per recommendation
type, is always included as one "key=value; key=value" column; with
-ExpandExtendedProperty each key also gets its own Ext_\<key\> column.

Every object carries exactly the same properties (including every
Ext_ column found in the whole result), because Export-Csv takes its
header row from the first object only - ragged objects would silently
lose columns.

Postponed and dismissed recommendations (Advisor suppressions) are
left out, as in the Azure portal; -IncludeSuppressed brings them back
with Status 'Postponed' or 'Dismissed'.

What you get depends on where the command runs:

```text
  at the prompt    a Spectre.Console view: the account and scope,
                   tiles with the number of recommendations, high /
                   medium / low impact, resources affected and
                   estimated monthly savings, then one colour-coded
                   table per category listing every affected
                   resource, shown a screen at a time
  piped onward     the AAC.AdvisorRecommendation objects, with no
                   summary (e.g. | Where-Object, | Export-Csv)
  -PassThru        the summary and the objects, e.g. to keep them
                   in a variable
  -NoDisplay       the objects only, never the summary (scripts,
                   scheduled tasks)
```

PowerShell can't tell "$r = Get-AACAdvisorRecommendation" from a
plain call, so to capture the objects in a variable add -PassThru
or -NoDisplay.

In the tables, rows are grouped by recommendation under an impact
badge (HIGH red, MEDIUM orange, LOW grey), savings are green, and a
retirement date is red within 90 days, orange within 180 and gold
after that. When the view is longer than the terminal it is paged:
press any key for the next page, or A to show the rest. -NoPaging
turns that off; paging is also skipped automatically when output is
redirected.

Exports:

```text
  -CsvPath    a CSV file written with Export-Csv (UTF-8, one row per
              recommendation per resource)
  -PdfPath    a landscape A4 PDF: a summary (totals, category by
              impact, subscriptions, estimated savings), every
              recommendation type consolidated with its affected
              resource count, then one section per category listing
              the affected resources under each recommendation
  -HtmlPath   a self-contained, interactive HTML report: clickable
              tiles and charts (by category, impact, subscription,
              recommendation) that filter a table of every
              recommendation, grouped by recommendation, with
              search, filters, sorting, subtotals of savings, Azure
              portal links and a CSV download of what is shown
```

When any of -CsvPath, -PdfPath or -HtmlPath is given, the console
shows only the progress and the files written - the report is in
the files. Add -PassThru to get the objects as well.

Savings are Advisor's own estimates. Two recommendations can overlap
(e.g. a reservation and a right-size for the same VM), so a total is
an upper bound; totals are kept per currency, never converted.

PDF export needs Windows and PowerShell 7.4 or later; objects and
CSV work everywhere.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Get-AACAdvisorRecommendation
```

Shows the summary of every Advisor recommendation you can see.

### Example 2

```powershell
Get-AACAdvisorRecommendation -CsvPath .\out\Advisor.csv -PdfPath .\out\Advisor.pdf -HtmlPath .\out\Advisor.html
```

Writes every recommendation to a CSV file, a PDF report and an interactive HTML report.

### Example 3

```powershell
Get-AACAdvisorRecommendation -Category Cost |
    Group-Object SavingsCurrency |
    ForEach-Object { '{0} {1:N2} per month' -f $_.Name, ($_.Group | Measure-Object MonthlySavings -Sum).Sum }
```

Totals Advisor's estimated monthly savings, per currency.

### Example 4

```powershell
$high = Get-AACAdvisorRecommendation -Impact High -PassThru
```

Shows the summary of high-impact recommendations and keeps the objects in $high.

### Example 5

```powershell
Get-AACAdvisorRecommendation -Category Reliability |
    Where-Object RetirementDate |
    Sort-Object RetirementDate |
    Format-Table RetirementDate, RetiringFeature, ResourceName, SubscriptionName
```

Lists resources affected by upcoming Azure service retirements, soonest first.

### Example 6

```powershell
Get-AACAdvisorRecommendation -NoDisplay -ExpandExtendedProperty -CsvPath .\Advisor.csv
```

In a scheduled script: writes the CSV, with every extendedProperties key as its own column, and shows nothing.

### Example 7

```powershell
Get-AACAdvisorRecommendation | Export-Csv -Path .\advisor.csv -NoTypeInformation -Delimiter ';'
```

Uses Export-Csv directly, for control over its options.

## PARAMETERS

### -Category

Only get these categories: Cost, Security, Reliability,
OperationalExcellence, Performance.

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

### -CsvPath

Also write the recommendations to this CSV file. An existing file is
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

### -ExpandExtendedProperty

Add one Ext_\<key\> column per key of Advisor's extendedProperties bag
(the union of keys over every recommendation returned), next to the
combined ExtendedProperties column.

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

### -Impact

Only get recommendations with these impacts: High, Medium, Low.

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

### -IncludeSuppressed

Also get recommendations that were postponed or dismissed in
Advisor, with Status set to 'Postponed' or 'Dismissed'.

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

Return the recommendation objects without showing the summary.

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

Show the summary and also return the recommendation objects.

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

Also write the report to this PDF file. An existing file is
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

Only get recommendations in these subscriptions. Defaults to every
subscription the signed-in account can see.

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

The PDF and HTML report's title. Defaults to 'Azure Advisor
recommendations'.

```yaml
Type: System.String
DefaultValue: "'Azure Advisor recommendations'"
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

### AAC.AdvisorRecommendation (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACAdvisorRecommendation.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
