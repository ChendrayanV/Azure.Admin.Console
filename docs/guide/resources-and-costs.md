# Resources and costs

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Show-AACCost`](../Show-AACCost.md) · [`Get-AACInventory`](../Get-AACInventory.md) (`-View Chart`)

(This was `Show-AACResource`, which still works but warns, and will be removed in a later release.)

`Get-AACInventory -View Chart` counts every resource you can see with two Resource Graph
queries, and draws one bar per type, each in its own colour:

```text
Resources by type (top 20 of 57)
  compute/virtualmachines  ███████████████████████████████████████████ 412
network/networkinterfaces  █████████████████████████████████████████ 398
  storage/storageaccounts  █████████████████ 164
           37 other types  ██████ 61
```

```powershell
Get-AACInventory -View Chart                                  # by type, top 20
Get-AACInventory -View Chart -By Location                     # or ResourceGroup, Subscription
Get-AACInventory -View Chart -ResourceType 'microsoft.network/*' -Top 10
Get-AACInventory -View Chart -By Subscription -PassThru | Export-Csv .\PerSubscription.csv
Get-AACInventory -View Chart -HtmlPath .\Inventory.html        # an interactive inventory
```

`-HtmlPath` writes an interactive inventory of every resource: name, type,
resource group, location, subscription, kind, SKU and tags, with portal links.
Charts by type, location, subscription and resource group filter it. This
needs one more Resource Graph query, for the resources themselves.

`Show-AACCost` reads each subscription's actual cost from the Cost Management
Query API, broken down by month, service and resource group, with one query
per subscription. It shows:

- tiles for month to date, last month, the period total and the top service;
- month to date by subscription (with several subscriptions), by service and by resource group;
- a bar chart of the last months, with this month marked "to date";
- a subscription-by-month table with a total column and a total row, and each subscription's highest month in gold.

When Cost Management reports no cost for the whole period, the view says so
instead of drawing empty charts.

```powershell
Show-AACCost                                      # month to date + last 6 months
Show-AACCost -Months 12 -SubscriptionId '00000000-0000-0000-0000-000000000000'
Show-AACCost -Months 12 -CsvPath .\Cost.csv -PdfPath .\Cost.pdf   # the detail and a report
Show-AACCost -Months 12 -HtmlPath .\Cost.html                     # an interactive report
Show-AACCost -PassThru | Export-Csv .\CostSummary.csv                  # one row per subscription
```

| Export      | Contents                                                                                                                                                                                                   |
| ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-CsvPath`  | The detail: one row per subscription, month, resource group and service (`SubscriptionName`, `SubscriptionId`, `Month`, `ResourceGroup`, `Service`, `Cost`, `Currency`), ready for an Excel pivot table    |
| `-PdfPath`  | Landscape A4. A summary with totals, the subscription-by-month table, and this month's top services and resource groups; then a page per subscription with its services and resource groups month by month |
| `-HtmlPath` | Tiles and charts by month, subscription, service and resource group, which filter the detail table; a subscription-by-month table; and every detail row, with the total of whatever is shown               |
| `-PassThru` | One object per subscription, with `MonthToDate`, one property per month (`2026-07`, ...), `Total`, `TopServices` and `Status`                                                                              |

Costs stay in each subscription's billing currency, and each currency gets its
own charts. Cost Management allows only a few queries a minute, so a progress
display shows each subscription as it is read, and throttled calls are
retried. A subscription that Cost Management can't report on, such as some
offer types or one you lack permission for, is listed with the reason.

A subscription with no cost in the period isn't an error either: a new or
empty subscription, or one whose usage is billed elsewhere. It's left out of
the charts and totals. Its `Status` is `No cost`, and every output says so:
the console, the HTML report (a tile and a note) and the PDF (its own
table).
