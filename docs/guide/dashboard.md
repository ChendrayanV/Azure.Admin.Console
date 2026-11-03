# Dashboard

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Show-AACDashboard`](../Show-AACDashboard.md) · [`Show-AACJson`](../Show-AACJson.md)

`Show-AACDashboard` puts the state of your estate on one screen, from one
Azure Resource Graph batch - health, security, policy, governance, Advisor,
the estate, the latest changes and, with `-IncludeCost`, the spend - with an
Estate score at the top and what to do next at the bottom:

```powershell
Show-AACDashboard                                # every subscription you can see
Show-AACDashboard -Select -Hours 72              # tick the subscriptions in a list; changes of the last 3 days
Show-AACDashboard -IncludeCost -HtmlPath .\Dashboard.html   # with the spend, as a report with a tab per section
Show-AACDashboard -Section Health, Security -Watch 300      # a screen on the wall: refreshed every 5 minutes
(Show-AACDashboard -NoDisplay).Status            # Success, Warning or Failed - for a script or a pipeline
(Show-AACDashboard -NoDisplay).Actions           # what to do next, as objects
```

```text
── Azure Admin Console :: Dashboard ─────────────────────────────────────────
admin@contoso.com · tenant ... · Scope: all subscriptions · 9 Oct 2026 10:42

✗ Action needed  1 resource(s) unavailable; 1 active Azure service issue(s)

╭─ Session ─────────────────────────────╮ ╭─ Resource Health ──────────────╮
│ Account   admin@contoso.com           │ │ ✓ Available    1,204           │
│ Tenant    ...                         │ │ ✗ Unavailable  1               │
│ Token     ✓ valid until 11:37         │ │ ⚠ Degraded     2               │
╰───────────────────────────────────────╯ ╰────────────────────────────────╯
```

Then the scores (Estate score, secure score, policy compliance, Advisor
score, the closest Azure limit, spend month to date), Security (alerts and
recommendations by severity, Defender plans), Governance (policy, the
closest role assignment limit, privileged role assignments, unused disks,
public IPs and NICs, tag coverage), Cost (month to date against the same
days last month, a forecast, 30 days as a sparkline, what costs most), the
subscriptions and their state, resources by region and by type, the active
Azure Service Health events (service issues, planned maintenance,
advisories, once each however many subscriptions they touch), the unhealthy
resources, Advisor recommendations by category and impact, the last 14 days of
changes as a sparkline and who made the most, the latest resource changes -
what was created, updated or deleted, where and by whom - and **What to do
next**: the actions that matter most, ranked across every section, each with
the command that goes deeper (`Get-AACSecurityAlert`, `Test-AACAzureLimit`,
`Invoke-AACPolicyAssessment`...).

The **Estate score** (0-100) is the average of the parts that could be read -
the share of resources available, the secure score, the share of resources
compliant with policy and the Advisor score - less 5 when a subscription is
at 95% of the role assignment limit (2 at 80%), and less 3 when spend is more
than 20% above last month. `-Section` shows only some sections;
`-HtmlPath`/`-PdfPath` write the dashboard as a report (an Overview, then a
tab per section) and `-CsvPath` what to do next; `-Watch` refreshes it until
Ctrl+C.

The status at the top is **Action needed** when resources are unavailable or
a service issue is active; **Needs attention** when resources are degraded,
Advisor has High-impact recommendations, maintenance or an advisory is
active, there are high-severity security alerts, policy compliance is
below 80%, a subscription is at 80% of the role assignment limit, spend is
more than 10% above last month, or something couldn't be read; and
**Healthy** otherwise. Anything
the account can't read is listed at the end, and the rest is still shown.
`-Select` asks at the console (arrow keys, space, Enter); in a script, use
`-SubscriptionId`.

`Show-AACJson` shows JSON, or any object as JSON, indented and coloured
(names, strings, numbers, booleans and null each in their own colour):

```powershell
Get-Content .\azuredeploy.json -Raw | Show-AACJson -Title 'ARM template'
Invoke-RestMethod -Uri $uri -Headers $headers | Show-AACJson -Title 'Response'
```
