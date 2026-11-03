# Microsoft Defender for Cloud assessment

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Invoke-AACDefenderAssessment`](../Invoke-AACDefenderAssessment.md)

`Invoke-AACDefenderAssessment` goes further than the posture: everything
Defender for Cloud knows, across subscriptions, in one tabbed report. It reads
Azure Resource Graph (`securityresources`) and, for the settings Resource Graph
doesn't hold, the Defender for Cloud REST API - one call per subscription and
setting, in parallel. Reader or Security Reader is enough.

```powershell
Invoke-AACDefenderAssessment -HtmlPath .\Defender.html                 # every section, every subscription
Invoke-AACDefenderAssessment -SubscriptionId $id -CsvPath .\defender    # one subscription, a CSV per table
Invoke-AACDefenderAssessment -Section AttackPaths, Alerts -AlertDays 7  # attack paths and the last week's alerts
(Invoke-AACDefenderAssessment -NoDisplay).Inventory | Where-Object PlanState -EQ 'Off'   # resources no plan protects
```

| Tab                   | What it shows                                                                                                                              |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| Overview              | Secure score, recommendations, attack paths, alerts, vulnerabilities, plans and compliance as tiles and charts - each opens its tab, filtered |
| Findings              | How Defender is set up: plans off for resources you have, Defender CSPM off, no security contact, alert e-mails off, MDE integration off, Critical attack paths, High alerts still open, suppression rules with no expiry, just-in-time ports open to any source |
| Recommendations       | Every recommendation with its unhealthy, healthy and not applicable resources, risk level and attack paths (Defender CSPM), control, description and remediation steps; every unhealthy resource |
| Attack path analysis  | Each path from entry point to target, step by step, with risk factors, MITRE tactics and techniques, the attack story and remediation      |
| Security alerts       | Alerts of the last `-AlertDays`, every status, with MITRE tactics and techniques, compromised entity and remediation steps; suppression rules |
| Inventory             | Every resource Defender assesses: the plan that protects it (on or off), recommendations by severity, vulnerabilities, alerts, attack paths |
| Vulnerabilities       | Vulnerability assessment findings on machines, SQL and container images: CVEs, patchable, remediation                                      |
| Security posture      | Secure score per subscription, controls with the potential increase, Defender plans with sub-plan and extensions, multicloud connectors   |
| Regulatory compliance | Standards, failed controls and the failed assessments with the recommendation to fix                                                       |
| Environment settings  | Security contacts and e-mail notifications, Defender for Endpoint and Defender for Cloud Apps integration, just-in-time VM access         |

Every table can be searched, filtered, grouped and downloaded as CSV, and a
row opens all its details - the fields the table leaves out too - in a panel
on the right.
