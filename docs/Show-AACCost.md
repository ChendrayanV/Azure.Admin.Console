# Show-AACCost

[Azure.Admin.Console](Azure.Admin.Console.md) · [about_Azure.Admin.Console](about_Azure.Admin.Console.md)

## Synopsis

Shows what your Azure subscriptions cost - month to date and the last few months - as colourful Spectre.Console charts, with optional CSV and PDF exports of the detail.

## Syntax

```powershell
Show-AACCost [[-SubscriptionId] <string[]>] [[-Months] <int>] [[-Top] <int>] [[-CsvPath] <string>] [[-PdfPath] <string>] [[-Title] <string>] [-PassThru] [<CommonParameters>]
```

## Description

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
reason under the charts rather than failing the run. Cost Management
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
  -PassThru   one AAC.SubscriptionCost object per subscription:
              MonthToDate, one property per month ('2026-07', ...),
              Total, TopServices and Status
```

Reading costs needs Cost Management Reader (or Reader) on the
subscriptions. Costs are "actual cost" as Cost Management reports
it, which can lag usage by a day or so. PDF export needs Windows and
PowerShell 7.4 or later.

## Examples

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

The last year, on screen, as a detail CSV file and as a PDF report.

### Example 3

```powershell
Show-AACCost -SubscriptionId '00000000-0000-0000-0000-000000000000' -Months 3
```

One subscription over the last three months.

### Example 4

```powershell
Show-AACCost -PassThru | Export-Csv .\CostSummary.csv -NoTypeInformation
```

One row per subscription, with a column per month.

## Parameters

### -SubscriptionId

Only these subscriptions. Defaults to every enabled subscription the
signed-in account can see.

| | |
|---|---|
| Type | `String[]` |
| Required | No |
| Position | 0 |
| Default value | `None` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -Months

How many months to cover, this month included (default 6, up to 12).

| | |
|---|---|
| Type | `Int32` |
| Required | No |
| Position | 1 |
| Default value | `6` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -Top

How many services the month-to-date breakdown shows (default 8); the
rest are summed as "other services".

| | |
|---|---|
| Type | `Int32` |
| Required | No |
| Position | 2 |
| Default value | `8` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -CsvPath

Also write the detail - one row per subscription, month, resource
group and service - to this CSV file. An existing file is
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

Also write a PDF report to this file. An existing file is
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

The PDF's title. Defaults to 'Azure cost'.

| | |
|---|---|
| Type | `String` |
| Required | No |
| Position | 5 |
| Default value | `'Azure cost'` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -PassThru

Also return the costs as AAC.SubscriptionCost objects.

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

AAC.SubscriptionCost (with -PassThru)
