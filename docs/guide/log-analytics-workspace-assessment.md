# Log Analytics workspace assessment

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Invoke-AACLogAnalyticsWorkspaceAssessment`](../Invoke-AACLogAnalyticsWorkspaceAssessment.md)

`Invoke-AACLogAnalyticsWorkspaceAssessment` assesses one workspace - by its
workspace ID (GUID), resource ID or name - without changing anything:

```powershell
Invoke-AACLogAnalyticsWorkspaceAssessment -WorkspaceId 00000000-0000-0000-0000-000000000000
Invoke-AACLogAnalyticsWorkspaceAssessment -WorkspaceId 'law-contoso-prod' -Days 7 -HtmlPath .\Workspace.html -PdfPath .\Workspace.pdf -CsvPath .\Tables.csv
(Invoke-AACLogAnalyticsWorkspaceAssessment -WorkspaceId 'law-contoso-prod' -Section Tables -NoDisplay).Tables | Where-Object Billing -EQ 'Billable'
(Invoke-AACLogAnalyticsWorkspaceAssessment -WorkspaceId 'law-contoso-prod' -NoDisplay).Recommendations | Where-Object Severity -EQ 'High'
```

| Section               | What it shows                                                                                                                                                                                                                                                                                             | Read from                                                   |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| Tables                | Billable and not billable tables: billable and free GB over `-Days`, share, daily average, last record, plan (Analytics, Basic, Auxiliary), interactive and total retention, Azure or custom                                                                                                              | `Usage` (KQL) and the workspace's tables (Resource Manager) |
| Settings              | Every setting: pricing tier and daily cap, retention, access control mode, local authentication, network access, private link, workspace transformation DCR, solutions, data exports, linked services and storage, diagnostic settings, saved searches - and anything else the workspace has, under Other | Resource Manager, Resource Graph                            |
| Recommendations       | Azure Advisor's, and the assessment's own (below), by severity with what to do and a link                                                                                                                                                                                                                 | Everything above                                            |
| Overview              | Tier, billable and free data, the daily average and busiest day, tables, agents, rules, operation errors                                                                                                                                                                                                  | All of the below                                            |
| Usage                 | Billable GB per day, per solution, and - for the last 24 hours - per Azure resource and per computer                                                                                                                                                                                                      | `Usage`, `find` (KQL)                                       |
| Health                | `_LogOperation`: errors, warnings and information, grouped; heartbeat ingestion latency                                                                                                                                                                                                                   | KQL                                                         |
| Agents                | Each computer's last heartbeat, agent type (Azure Monitor Agent, the retired MMA, SCOM), state                                                                                                                                                                                                            | `Heartbeat` (KQL)                                           |
| Query Audit           | Queries per user and app, the slowest, the failed                                                                                                                                                                                                                                                         | `LAQueryLogs` (KQL)                                         |
| Data Collection Rules | The DCRs sending to the workspace: data sources, streams, output tables, transformations, associations                                                                                                                                                                                                    | Resource Graph                                              |
| Change Log            | Changes to the workspace and its tables, from the activity log                                                                                                                                                                                                                                            | Resource Manager                                            |

`-HtmlPath` writes a tabbed report like the other assessments: a Summary tab
(headline, tiles and charts), then a tab per section - Recommendations,
Tables, Settings, Usage, Health, Agents, Query audit, Data collection rules
and Change log - with every table searchable, filterable and downloadable as
CSV. `-PdfPath` writes the same as a PDF, each section a bookmarked heading
with its tables' key columns.

The assessment's own recommendations: a legacy pricing tier; a commitment tier
when billable ingestion averages 100 GB a day or more, or one above what is
ingested; the daily cap stopping collection, ingestion close to it, or no cap;
ingestion spikes; interactive retention beyond the free 31 days (90 with
Microsoft Sentinel); large tables that could use the Basic or Auxiliary plan;
the legacy ContainerLog table; AzureDiagnostics as a large share; custom tables
with no data; computers on the retired Log Analytics agent (MMA); agents that
stopped sending heartbeats; operation errors; data collection rules with no
associations; shared keys (local authentication) enabled; open network access;
workspace-only access control; query auditing off; no diagnostic settings.

The KQL runs in the workspace, up to 5 queries at a time (the query API's limit
per user), each on its own - one that can't run doesn't stop the rest. A
workspace with no `LAQueryLogs` (query auditing off) or no `Heartbeat` (no
agents) says so instead. It needs Reader (or Log Analytics Reader) on the
workspace and Reader on its resource group for the activity log. `-Section`
reads only what you ask for; `-CsvPath` writes the tables, `-HtmlPath` every
section, each searchable and downloadable as CSV.
