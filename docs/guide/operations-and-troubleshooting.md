# Operations and troubleshooting

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Export-AACDiagnosticBundle`](../Export-AACDiagnosticBundle.md) · [`Get-AACLegacyAuthentication`](../Get-AACLegacyAuthentication.md) · [`Get-AACLoadBalancerHealth`](../Get-AACLoadBalancerHealth.md) · [`Get-AACOrphanedIdentity`](../Get-AACOrphanedIdentity.md) · [`Get-AACPrivateEndpoint`](../Get-AACPrivateEndpoint.md) · [`Get-AACResourceError`](../Get-AACResourceError.md) · [`Get-AACResourceHealth`](../Get-AACResourceHealth.md) · [`Get-AACUnusedResource`](../Get-AACUnusedResource.md)

Eight commands for the questions an Azure administrator answers every day
([#8](https://github.com/ChendrayanV/Azure.Admin.Console/issues/8)). They work
like the rest: `-SubscriptionId` and `-ManagementGroupId` (most with
`-ResourceGroupName`, `-ResourceType` or `-Name`), a console view, objects with
`-NoDisplay`, and `-CsvPath`, `-HtmlPath` and `-PdfPath` reports. All read
only; `Export-AACDiagnosticBundle` writes a zip on your machine.

```powershell
Get-AACResourceHealth -State Unavailable, Degraded -IncludeHistory -Days 30  # what is down, and how available it was
Get-AACUnusedResource -IncludeCost -HtmlPath .\Unused.html                    # what to delete, and what it costs
Get-AACResourceError -Category Authorization -Hours 168                       # who was denied what this week
Get-AACPrivateEndpoint -Status Failed, Warning                                # broken private connectivity and DNS
Get-AACLoadBalancerHealth -Health Unhealthy, Partial                          # backends failing their health probe
Get-AACLegacyAuthentication -SignInDays 30                                    # keys, passwords, legacy protocols, old TLS
Get-AACOrphanedIdentity -Kind DeletedPrincipal, Application                   # identities nobody uses, and their access
Get-AACResourceHealth -State Unavailable -NoDisplay | Export-AACDiagnosticBundle -Path .\down.zip
```

| Command | Reads | Needs |
| --- | --- | --- |
| `Get-AACResourceHealth` | Resource Graph: Resource Health statuses and events, Service Health events and impacted resources; each resource's Resource Health history (`-IncludeHistory`) | Reader |
| `Get-AACUnusedResource` | Resource Graph: disks, NICs, public IPs, NSGs, route tables, NAT gateways, load balancers, gateways, plans, VMs, snapshots, DNS zones, pools, resource groups; Cost Management (`-IncludeCost`) | Reader (Cost Management Reader) |
| `Get-AACResourceError` | Every subscription's Activity Log for the window | Reader or Monitoring Reader |
| `Get-AACPrivateEndpoint` | Resource Graph: private endpoints, private DNS zones and links, virtual networks, targets; each endpoint's DNS zone groups | Reader |
| `Get-AACLoadBalancerHealth` | Resource Graph: load balancers, Application Gateways, Traffic Manager, backend NICs; Azure Monitor health metrics | Reader or Monitoring Reader |
| `Get-AACLegacyAuthentication` | Resource Graph: authentication settings of storage, SQL, PostgreSQL, Cosmos DB, messaging, AI, Redis, AKS, VMs, Key Vault, App Service; App Service publishing credentials; Microsoft Graph sign-ins and policies | Reader; AuditLog.Read.All (Entra ID P1), Policy.Read.All, Application.Read.All |
| `Get-AACOrphanedIdentity` | Resource Graph: identities, role assignments (tenant-wide); federated credentials; Microsoft Graph principals, apps and sign-in activity | Reader; Directory.Read.All, Application.Read.All, AuditLog.Read.All (Entra ID P1) |
| `Export-AACDiagnosticBundle` | Resource Graph (configuration, health, Advisor, Defender, policy, alerts, changes, role assignments); Activity Log, diagnostic settings, locks and health history per resource | Reader |

The rest of #8 is answered by commands the module already has:

| Asked for | Use |
| --- | --- |
| `Get-AACRoleAssignment` - RBAC assignments and effective access | `Get-AACAccessReview -View Assignment` (every assignment as it is), `Get-AACAccessReview` (every assignment, PIM, classic admins, Entra roles and Graph app permissions, with a recommendation each) |
| `Get-AACServicePrincipalAccess` - permissions and recent use | `Get-AACAccessReview -PrivilegedOnly` for the access, `Get-AACOrphanedIdentity -Kind Application` for the unused ones |
| `Get-AACActivityLog` - administrative changes | `Get-AACChangeHistory` (what changed, who, before and after); failed actions and permission issues: `Get-AACResourceError` |
| `Get-AACBackupStatus` - backup health and recovery readiness | `Get-AACFailoverReadiness` (backups, restores, Site Recovery, vaults, recovery plans) |
| `Get-AACResourceDependencies` - upstream and downstream dependencies | `Get-AACDependencyGraph` (blast radius, single points of failure, a Graphviz export) |
