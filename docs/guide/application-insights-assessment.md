# Application Insights assessment

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Invoke-AACApplicationInsightAssessment`](../Invoke-AACApplicationInsightAssessment.md)

`Invoke-AACApplicationInsightAssessment` looks at every Application Insights
component in scope, and the workspace, tests, alerts and access around it:

```powershell
Invoke-AACApplicationInsightAssessment                                             # every component, the last week
Invoke-AACApplicationInsightAssessment -IncludeIngestion -View Ingestion -NoDisplay | Sort-Object GB -Descending | Select-Object -First 10
Invoke-AACApplicationInsightAssessment -View Finding -NoDisplay | Where-Object Signal -EQ 'Security'
Invoke-AACApplicationInsightAssessment -ResourceGroupName 'rg-app-prod' -TimeRange 30d -IncludeIngestion -IncludeActivityLog -HtmlPath .\AppInsights.html -PdfPath .\AppInsights.pdf
```

Findings come under five signals, and the heat map scores each component
0-100 on every one (100, less 40 for a High finding, 20 for a Medium, 10 for
a Low):

- **Ingestion & cost:** the daily cap (reached, close to the normal volume,
  missing, warnings off) - on the component and its workspace, the lower one
  wins. With `-IncludeIngestion`: billed GB by table and day, no sampling on
  a busy app, spikes, Verbose and Information traces, dependency noise,
  health probe requests. A diagnostic setting that sends the telemetry to a
  workspace again is found too: it is billed twice.
- **Workspace & architecture:** classic components (retired in February
  2024), a workspace that is missing or in another region, no availability
  test, URL ping tests (retired 30 September 2026) and multi-step tests, too
  few test locations, no alert rule, alerts with no action group, Failure
  Anomalies smart detection off.
- **Security:** local authentication (the instrumentation key alone is
  enough to send telemetry), IP masking off (client IPs are personal data),
  a private link scope with public ingestion or queries left open, API keys
  (worse if they can write).
- **Identity & access:** local authentication off with no Monitoring Metrics
  Publisher (telemetry is rejected), components ready to turn local
  authentication off, Owner or an access administrator role on the
  component, users instead of groups, many identities with write, and
  workspaces that need workspace-wide read.
- **Audit & lifecycle:** no delete lock (a new component has a new
  connection string), no owner tag, no telemetry in the period. With
  `-IncludeActivityLog`: purges, API keys created, changes by people rather
  than pipelines, and failed changes.

`-View` returns Component (default), Ingestion, Access, Change or Finding
rows, and is what `-CsvPath` writes.

It needs Reader. `-IncludeIngestion` also needs Log Analytics Reader on the
workspaces (or Reader on the components, with resource-context access). It
never reads a key or the telemetry itself, only billed sizes and counts. For
the workspace's own pricing tier, commitment tiers and table plans, run
[`Invoke-AACLogAnalyticsWorkspaceAssessment`](../Invoke-AACLogAnalyticsWorkspaceAssessment.md).
