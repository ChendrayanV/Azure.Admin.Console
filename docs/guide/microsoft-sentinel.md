# Microsoft Sentinel

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Invoke-AACSentinelAssessment`](../Invoke-AACSentinelAssessment.md) ·
[`Get-AACSentinelIncident`](../Get-AACSentinelIncident.md) ·
[`Get-AACSentinelAlert`](../Get-AACSentinelAlert.md) ·
[`Get-AACSentinelAnalyticsRule`](../Get-AACSentinelAnalyticsRule.md) ·
[`Get-AACSentinelWatchlist`](../Get-AACSentinelWatchlist.md) ·
[`Get-AACSentinelContentHub`](../Get-AACSentinelContentHub.md) ·
[`Export-AACSentinelAnalyticsRule`](../Export-AACSentinelAnalyticsRule.md) ·
[`Test-AACSentinelRuleQuery`](../Test-AACSentinelRuleQuery.md) ·
[`Get-AACSentinelDataConnector`](../Get-AACSentinelDataConnector.md) ·
[`Get-AACSentinelPlaybook`](../Get-AACSentinelPlaybook.md) ·
[`Get-AACSentinelThreatIntelligence`](../Get-AACSentinelThreatIntelligence.md) ·
[`Get-AACSentinelHuntingQuery`](../Get-AACSentinelHuntingQuery.md) ·
[`Find-AACSentinelHuntingQuery`](../Find-AACSentinelHuntingQuery.md) ·
[`Deploy-AACSentinelHuntingQuery`](../Deploy-AACSentinelHuntingQuery.md)

Every command takes one workspace through `-WorkspaceId`. That can be the
workspace ID (the GUID on its Overview page), its resource ID or its name.
They all read only. `Export-AACSentinelAnalyticsRule` writes files on your
machine, and `Deploy-AACSentinelHuntingQuery` is the only command here that
changes Azure. Microsoft Sentinel Reader on the workspace is enough, with Log
Analytics Reader for the parts that run KQL.

`Invoke-AACSentinelAssessment` is the whole picture, with recommendations. The
`Get-` commands are for day-to-day questions about one thing, each with its
own filters, and the objects they return pipe on.

```powershell
$ws = 'law-contoso-sentinel'
Invoke-AACSentinelAssessment -WorkspaceId $ws -HtmlPath .\Sentinel.html        # everything, with recommendations

Get-AACSentinelIncident -WorkspaceId $ws -Severity High -Unassigned             # open High incidents nobody owns
Get-AACSentinelIncident -WorkspaceId $ws -Status Closed -Days 90 -Classification FalsePositive -NoDisplay | Group-Object RuleIds

Get-AACSentinelAlert -WorkspaceId $ws -Days 30 -Severity High, Medium           # alerts from every connected product
Get-AACSentinelAlert -WorkspaceId $ws -IncidentNumber 4211 -NoDisplay | Select-Object Alert, Accounts, Hosts, IpAddresses
Get-AACSentinelAlert -WorkspaceId $ws -NoIncident                               # alerts no incident was created for

Get-AACSentinelAnalyticsRule -WorkspaceId $ws -State Enabled -Failing           # rules that failed to run
Get-AACSentinelAnalyticsRule -WorkspaceId $ws -TemplateUpdate -CsvPath .\RulesToUpdate.csv

Get-AACSentinelWatchlist -WorkspaceId $ws                                       # empty, unused and stale watchlists
Get-AACSentinelContentHub -WorkspaceId $ws -UpdateAvailable                     # solutions with an update waiting

Export-AACSentinelAnalyticsRule -WorkspaceId $ws -Path .\sentinel -IncludeAutomationRule -Force   # rules as code

Test-AACSentinelRuleQuery -WorkspaceId $ws -Name 'Rare admin sign-in' -Runs 24             # what a rule would have done
Test-AACSentinelRuleQuery -WorkspaceId $ws -Query 'SigninLogs | where ResultType == "50126"' -Frequency PT5M -Period PT1H

Get-AACSentinelDataConnector -WorkspaceId $ws                                   # connectors failing, silent or late
Get-AACSentinelDataConnector -WorkspaceId $ws -View Table                       # ingestion delay per table
Get-AACSentinelPlaybook -WorkspaceId $ws -Days 30                               # playbooks, runs and permissions
Get-AACSentinelThreatIntelligence -WorkspaceId $ws                              # indicators by source; stale feeds
Get-AACSentinelThreatIntelligence -WorkspaceId $ws -Indicator -IndicatorType ipv4-addr -Value '203.0.113.*'
```

| Command                             | What it answers                                                                                                                      |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `Get-AACSentinelIncident`           | What is open, who owns it, how long it has waited. Open incidents of any age by default. Closed ones go back 30 days unless `-Days` says otherwise |
| `Get-AACSentinelAlert`              | What was detected, about which hosts, accounts and IP addresses, and which incident holds it. Reads `SecurityAlert`, so every connected product is included. The last 7 days by default |
| `Get-AACSentinelAnalyticsRule`      | Which rules are in place, which fail (from `_SentinelHealth`), which raise the most incidents or false positives, which have a newer template, and the MITRE ATT&CK coverage |
| `Get-AACSentinelWatchlist`          | How many items each watchlist holds, which rules and hunting queries call `_GetWatchlist` with its alias, and which are empty, unused, stale or failed |
| `Get-AACSentinelContentHub`         | Which solutions are installed, which have an update or are deprecated, and which have no enabled rule from their analytics templates |
| `Export-AACSentinelAnalyticsRule`   | One ARM template per rule, with stable file contents, so a commit shows what changed. Deploy them to another workspace with its name as the `workspace` parameter |
| `Test-AACSentinelRuleQuery`         | What a rule's query returns in each of its last run windows, whether each run would alert, and whether the columns it maps exist. A query using `ago()` or `now()` can only be tested in its latest window. Each window is a query, so test a few rules at a time |
| `Get-AACSentinelDataConnector`      | Which connectors are failing, disconnected, silent or delayed, and, with `-View Table`, how late records arrive in each table. Agent-fed sources (Windows events, Syslog, CEF) show in the table view |
| `Get-AACSentinelPlaybook`           | The Logic Apps with a Sentinel trigger, the automation rules that run them, failed runs, and whether Sentinel holds Automation Contributor on their resource group |
| `Get-AACSentinelThreatIntelligence` | Indicators by source and type from `ThreatIntelIndicators` and the legacy table: active, expiring, confidence, feeds that stopped, and whether any rule matches on them |

Incidents and alerts hold people's names and email addresses, and so do the
reports made from them.
