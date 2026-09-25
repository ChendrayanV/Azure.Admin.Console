# Get-AACAdvisorRecommendation

[Azure.Admin.Console](Azure.Admin.Console.md) · [about_Azure.Admin.Console](about_Azure.Admin.Console.md)

## Synopsis

Gets a consolidated, flattened view of Azure Advisor recommendations (Resource Graph's advisorresources table): a Spectre.Console summary at the prompt, PowerShell objects down a pipeline, and optional CSV and PDF exports.

## Syntax

```powershell
Get-AACAdvisorRecommendation [[-SubscriptionId] <string[]>] [[-Category] <string[]>] [[-Impact] <string[]>] [[-CsvPath] <string>] [[-PdfPath] <string>] [[-Title] <string>] [-IncludeSuppressed] [-ExpandExtendedProperty] [-PassThru] [-NoDisplay] [-NoPaging] [<CommonParameters>]
```

## Description

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

Exports, in any of those modes:
```text
  -CsvPath    a CSV file written with Export-Csv (UTF-8, one row per
              recommendation per resource)
  -PdfPath    a landscape A4 PDF: a summary (totals, category by
              impact, subscriptions, estimated savings), every
              recommendation type consolidated with its affected
              resource count, then one section per category listing
              the affected resources under each recommendation
```

Savings are Advisor's own estimates. Two recommendations can overlap
(e.g. a reservation and a right-size for the same VM), so a total is
an upper bound; totals are kept per currency, never converted.

PDF export needs Windows and PowerShell 7.4 or later (see
Export-AACPesterReport); objects and CSV work everywhere.

## Examples

### Example 1

```powershell
Connect-AAC
Get-AACAdvisorRecommendation
```

Shows the summary of every Advisor recommendation you can see.

### Example 2

```powershell
Get-AACAdvisorRecommendation -CsvPath .\out\Advisor.csv -PdfPath .\out\Advisor.pdf
```

Shows the summary and writes every recommendation to a CSV file and a PDF report.

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

## Parameters

### -SubscriptionId

Only get recommendations in these subscriptions. Defaults to every
subscription the signed-in account can see.

| | |
|---|---|
| Type | `String[]` |
| Required | No |
| Position | 0 |
| Default value | `None` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -Category

Only get these categories: Cost, Security, Reliability,
OperationalExcellence, Performance.

| | |
|---|---|
| Type | `String[]` |
| Accepted values | `Cost`, `Security`, `Reliability`, `OperationalExcellence`, `Performance` |
| Required | No |
| Position | 1 |
| Default value | `None` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -Impact

Only get recommendations with these impacts: High, Medium, Low.

| | |
|---|---|
| Type | `String[]` |
| Accepted values | `High`, `Medium`, `Low` |
| Required | No |
| Position | 2 |
| Default value | `None` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -IncludeSuppressed

Also get recommendations that were postponed or dismissed in
Advisor, with Status set to 'Postponed' or 'Dismissed'.

| | |
|---|---|
| Type | `SwitchParameter` |
| Required | No |
| Position | Named |
| Default value | `False` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -ExpandExtendedProperty

Add one Ext_\<key\> column per key of Advisor's extendedProperties bag
(the union of keys over every recommendation returned), next to the
combined ExtendedProperties column.

| | |
|---|---|
| Type | `SwitchParameter` |
| Required | No |
| Position | Named |
| Default value | `False` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -CsvPath

Also write the recommendations to this CSV file. An existing file is
overwritten; missing folders are created.

| | |
|---|---|
| Type | `String` |
| Required | No |
| Position | 3 |
| Default value | `None` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -PdfPath

Also write the report to this PDF file. An existing file is
overwritten; missing folders are created.

| | |
|---|---|
| Type | `String` |
| Required | No |
| Position | 4 |
| Default value | `None` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -Title

The PDF's title. Defaults to 'Azure Advisor recommendations'.

| | |
|---|---|
| Type | `String` |
| Required | No |
| Position | 5 |
| Default value | `'Azure Advisor recommendations'` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -PassThru

Show the summary and also return the recommendation objects.

| | |
|---|---|
| Type | `SwitchParameter` |
| Required | No |
| Position | Named |
| Default value | `False` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -NoDisplay

Return the recommendation objects without showing the summary.

| | |
|---|---|
| Type | `SwitchParameter` |
| Required | No |
| Position | Named |
| Default value | `False` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -NoPaging

Show the whole view at once instead of a screen at a time.

| | |
|---|---|
| Type | `SwitchParameter` |
| Required | No |
| Position | Named |
| Default value | `False` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### CommonParameters

This command supports the common parameters (`-Verbose`, `-ErrorAction`, `-WarningAction` and so on). See [about_CommonParameters](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters).

## Outputs

AAC.AdvisorRecommendation (piped onward, or with -PassThru or -NoDisplay)
