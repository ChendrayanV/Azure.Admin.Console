# Azure Advisor recommendations

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Get-AACAdvisorRecommendation`](../Get-AACAdvisorRecommendation.md)

`Get-AACAdvisorRecommendation` reads the `advisorresources` table in Azure
Resource Graph (one query for every subscription, paged). What it returns
depends on where it runs:

| Where                                             | You get                                                                                                                       |
| ------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| At the prompt                                     | A Spectre.Console view: account and scope, tiles for the totals, then one colour-coded table per category, a screen at a time |
| Piped onward (`\| Where-Object`, `\| Export-Csv`) | The objects, with no view                                                                                                     |
| `-PassThru`                                       | The view and the objects                                                                                                      |
| `-NoDisplay`                                      | The objects only, for scripts and scheduled tasks                                                                             |

```text
──────────────────── Azure Admin Console :: Azure Advisor ────────────────────
admin@contoso.com · tenant 72f988bf-… · all subscriptions · 25 Sept 2026 12:47

╭─────────────────╮ ╭─────────────╮ ╭───────────────╮ ╭────────────╮ ╭──────────────────────╮ ╭────────────────────────╮
│       60        │ │     20      │ │      20       │ │     20     │ │          45          │ │       USD 6,738        │
│ recommendations │ │ high impact │ │ medium impact │ │ low impact │ │  resources affected  │ │  est. savings / month  │
╰─────────────────╯ ╰─────────────╯ ╰───────────────╯ ╰────────────╯ ╰──────────────────────╯ ╰────────────────────────╯

                         ● Cost · 4 recommendations · 4 resources · USD 525 / month
╭──────────┬──────────────────────────────────────┬─────────────────┬─────────────────────────┬────────────────────╮
│ Impact   │ Recommendation                       │ Resource        │ Subscription · RG       │ Savings / retire…  │
├──────────┼──────────────────────────────────────┼─────────────────┼─────────────────────────┼────────────────────┤
│  HIGH    │ Right-size or shutdown underutilized │ vm-app-06       │ sub-prod · rg-app-0     │ USD 105.00 / mo    │
│          │ virtual machines                     │ virtualMachines │                         │                    │
│          │                                      │ vm-app-12       │ sub-prod · rg-app-0     │ USD 210.00 / mo    │
╰──────────┴──────────────────────────────────────┴─────────────────┴─────────────────────────┴────────────────────╯
```

In the view:

- **Rows** are grouped by recommendation under an impact badge: HIGH red, MEDIUM orange, LOW grey.
- **Savings** are green.
- **Retirement dates** are red within 90 days, orange within 180 and gold after that.
- **Paging:** a view longer than the terminal is shown a screen at a time. Press any key for the next page, or A for the rest. `-NoPaging` turns this off, and it's skipped automatically when output is redirected.

`-HtmlPath` writes the interactive report. It has tiles for impact, resources,
savings and retirements, and charts by category, impact, subscription and
recommendation. Every recommendation is in one table, grouped by
recommendation, with the savings subtotalled per group.

PowerShell can't tell `$r = Get-AACAdvisorRecommendation` apart from a plain
call. To keep the objects in a variable, add `-PassThru` or `-NoDisplay`.

Each recommendation's nested JSON is flattened into one row:

| Column                                                                                           |                                                                    |
| ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------ |
| `Category`, `Impact`, `Status`                                                                   | Portal category names. `Status` is Active, Postponed or Dismissed. |
| `SubscriptionName`, `SubscriptionId`, `ResourceGroup`                                            | Where the resource lives.                                          |
| `ResourceName`, `ResourceType`, `ResourceId`                                                     | The affected resource.                                             |
| `Problem`, `Solution`, `PotentialBenefits`, `SubCategory`                                        | What Advisor recommends.                                           |
| `MonthlySavings`, `AnnualSavings`, `SavingsCurrency`                                             | Advisor's estimates, as numbers.                                   |
| `RetirementDate`, `RetiringFeature`                                                              | Service retirement recommendations.                                |
| `LastUpdated`, `SuppressionExpires`, `RecommendationTypeId`, `LearnMoreLink`, `RecommendationId` | Tracking.                                                          |
| `ExtendedProperties`                                                                             | Advisor's free-form details as `key=value; key=value`.             |
| `Ext_<key>`                                                                                      | With `-ExpandExtendedProperty`: one column per key.                |

Every row has the same columns. `Export-Csv` takes its header row from the
first object, so rows with different columns would silently drop data.

```powershell
# The high-impact view, keeping the objects
$high = Get-AACAdvisorRecommendation -Impact High -Category Cost, Security, Reliability -PassThru

# Estimated monthly savings, per currency
Get-AACAdvisorRecommendation -Category Cost |
    Group-Object SavingsCurrency |
    ForEach-Object { '{0} {1:N2}' -f $_.Name, ($_.Group | Measure-Object MonthlySavings -Sum).Sum }

# Upcoming service retirements, soonest first
Get-AACAdvisorRecommendation -Category Reliability |
    Where-Object RetirementDate | Sort-Object RetirementDate |
    Format-Table RetirementDate, RetiringFeature, ResourceName, SubscriptionName

# A scheduled export: no view, postponed/dismissed included, one column per extended property
Get-AACAdvisorRecommendation -NoDisplay -IncludeSuppressed -ExpandExtendedProperty -CsvPath .\Advisor-full.csv
```

The PDF report is landscape A4 and has three parts:

1. **Summary:** totals, category by impact, subscriptions, and estimated savings.
2. **Recommendations by type:** each distinct recommendation once, with how many resources and subscriptions it affects.
3. **One section per category:** the affected resources under each recommendation.

Savings are Advisor's estimates, totalled per currency. Recommendations can
overlap (for example, a reservation and a right-size for the same VM), so a
total is an upper bound.
