# Security alerts

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Get-AACSecurityAlert`](../Get-AACSecurityAlert.md)

`Get-AACSecurityAlert` is the equivalent of `Get-AzSecurityAlert` (Az.Security).
It reads Microsoft Defender for Cloud's alerts for every subscription in one
Azure Resource Graph query, not one subscription and location at a time.
By default you get the open alerts (Active and In progress); `-Status` picks
others. Reader or Security Reader is enough.

```powershell
Get-AACSecurityAlert                                                   # the open alerts, most severe first
Get-AACSecurityAlert -Severity High -Days 7 -HtmlPath .\Alerts.html    # this week's High alerts, as a report
Get-AACSecurityAlert -Status Active, InProgress, Resolved, Dismissed -Days 90 -CsvPath .\Alerts.csv
Get-AACSecurityAlert -Tactic CredentialAccess, LateralMovement -NoDisplay | Select-Object Alert, Resource, Accounts, IpAddresses
Get-AACInventory -NoDisplay | Where-Object ResourceGroup -EQ 'rg-prod' | Get-AACSecurityAlert   # alerts on the resources piped in
Get-AACSecurityAlert -Name '2517*' -NoDisplay | Select-Object -ExpandProperty ExtendedProperties  # one alert, any status
```

| Compared with `Get-AzSecurityAlert` | `Get-AACSecurityAlert`                                                                                                   |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Scope                               | Every subscription, or a management group's, in one query                                                                |
| Filters                             | `-Status`, `-Severity`, `-Days` (in the query); `-Name`, `-AlertType`, `-Tactic`, `-Incident`, `-ResourceGroupName`, `-ResourceId` (wildcards) |
| Pipeline                            | Takes `ResourceId` or `Id` from the pipeline, and matches the resource and anything under it                             |
| In each alert                       | MITRE tactics and techniques; `Hosts`, `Accounts` and `IpAddresses` from the entities; extended properties as a dictionary; remediation as plain text; age; incident |
| Noise                               | `Occurrences` per alert, and a list of recurring ones (three or more of a type on one resource): to fix or suppress    |
| Blind spots                         | Points out subscriptions with no Defender plan on - they raise no alerts                                                 |
| Output                              | A console view (by severity, MITRE tactic in kill-chain order, day and resource), objects, CSV, HTML and PDF             |

It doesn't change an alert's state. Do that in Defender for Cloud.
