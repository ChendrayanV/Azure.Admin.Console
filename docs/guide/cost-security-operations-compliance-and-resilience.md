# Cost, security, operations, compliance and resilience

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Get-AACAccessReview`](../Get-AACAccessReview.md) · [`Get-AACAttackPath`](../Get-AACAttackPath.md) · [`Get-AACChangeHistory`](../Get-AACChangeHistory.md) · [`Get-AACComplianceGap`](../Get-AACComplianceGap.md) · [`Get-AACConfigurationDrift`](../Get-AACConfigurationDrift.md) · [`Get-AACCostAnomaly`](../Get-AACCostAnomaly.md) · [`Get-AACDependencyGraph`](../Get-AACDependencyGraph.md) · [`Get-AACFailoverReadiness`](../Get-AACFailoverReadiness.md) · [`Get-AACResourceUtilization`](../Get-AACResourceUtilization.md) · [`Invoke-AACHealthCheck`](../Invoke-AACHealthCheck.md)

Ten commands for the questions platform, security, operations, FinOps and
compliance teams ask every day. They all work the same way: scope with
`-SubscriptionId`, `-ManagementGroupId` (and most with `-ResourceGroupName`),
a console view, objects with `-NoDisplay`, and `-CsvPath`, `-HtmlPath` and
`-PdfPath` reports. Every finding has a severity, what was found, its impact,
what to do and how much effort it is. All are read-only.

```powershell
Get-AACCostAnomaly -By ServiceName -Sensitivity High            # FinOps: spend anomalies, the resources behind them
Get-AACAttackPath -Severity Critical, High                      # security: Internet > identity > control or data
Get-AACAccessReview -PrivilegedOnly -CsvPath .\AccessReview.csv # security and audit: least privilege, attestation
Get-AACChangeHistory -ResourceGroupName rg-app -Hours 6         # incidents: what changed, who, what followed
Invoke-AACHealthCheck -Discover -Count 5                        # operations: endpoints, queues, platform, SLA
Get-AACComplianceGap -Framework PCI-DSS, ISO27001               # compliance: gaps as a roadmap
Get-AACFailoverReadiness -RpoMinutes 15                         # BCDR: can we recover, and how sure are we
Get-AACDependencyGraph -IncludeTelemetry -DotPath .\deps.dot    # architecture: blast radius, single points of failure
Get-AACResourceUtilization -IncludeCost                         # FinOps: idle, under-used, right-sizing, chargeback
Get-AACConfigurationDrift -UseDefaultRules -BaselinePath .\baseline.json   # IaC: drift, who did it, the trend
```

| Command | Reads | Needs |
| --- | --- | --- |
| `Get-AACCostAnomaly` | Cost Management daily cost per subscription (3 at a time), then per resource for the largest anomalies | Cost Management Reader |
| `Get-AACAttackPath` | Resource Graph: public IPs, NICs, NSG rules, VMs, apps, AKS, data stores, identities, role assignments; Defender attack paths | Reader (Defender CSPM for its paths) |
| `Get-AACAccessReview` | Resource Graph RBAC; per subscription PIM, classic admins and the Activity Log; Microsoft Graph principals, sign-ins, Entra roles and Graph app permissions | Reader; Graph Directory.Read.All, RoleManagement.Read.Directory, Application.Read.All, AuditLog.Read.All |
| `Get-AACChangeHistory` | The Activity Log; Resource Graph resource changes, alerts and Resource Health | Reader |
| `Invoke-AACHealthCheck` | HTTP and TCP probes from where it runs (no credentials sent); Resource Graph; Service Bus queues | Reader (none with `-SkipAzure`) |
| `Get-AACComplianceGap` | Defender regulatory compliance; Azure Policy regulatory initiatives; resources nothing evaluates | Reader, Security Reader |
| `Get-AACFailoverReadiness` | Resource Graph: VMs, vaults, backup items, restore jobs; Site Recovery items, recovery plans and their runbooks | Reader |
| `Get-AACDependencyGraph` | Resource Graph relationships and role assignments; Application Insights dependencies (`-IncludeTelemetry`) | Reader (Log Analytics Reader for telemetry) |
| `Get-AACResourceUtilization` | Azure Monitor metrics, hourly; VM sizes; the public Azure Retail Prices API; cost (`-IncludeCost`) | Reader / Monitoring Reader (Cost Management Reader) |
| `Get-AACConfigurationDrift` | Resource Graph configuration and its 14-day change history; a baseline, rules or a Terraform plan JSON | Reader |

`Get-AACAccessReview` gives every assignment a recommendation (Remove, Make
eligible (PIM), Narrow the scope or role, Review usage, Use a group or Keep)
and an **Action**: what to do, in so many words, for the kind of principal.
People are told to make standing privileged access just-in-time in PIM.
Service principals and managed identities with elevated access are flagged
just as hard - a leaked secret or a compromised workload uses that access with
no MFA - but PIM needs a person to activate a role, so they are never told to
use it. Instead: replace Owner with Contributor at the resource groups they
deploy to, or with Role Based Access Control Administrator under a condition
if they must assign roles; use a managed identity or federated credential
rather than a client secret. Write access an application hasn't used is
"Review usage" (check its sign-in logs first), not "Remove": a monthly job or a
disaster-recovery pipeline can be quiet for weeks. Roles with data-plane access
(blobs, secrets, messages) are never called unused, because the Activity Log
doesn't record that use.

What they don't do, by design: change anything (no remediation, failover or
"bulk fix" - the fixes are yours to apply, ideally through infrastructure as
code), or claim more than Azure records - "ML" anomaly detection is robust
statistics, attack paths show where to look rather than proof of compromise,
failover readiness checks the runbooks a recovery plan runs without running
them, and audit certificates aren't in Azure (see the Service Trust Portal).
