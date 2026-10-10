# Azure.Admin.Console

[![CI](https://github.com/ChendrayanV/Azure.Admin.Console/actions/workflows/ci.yml/badge.svg)](https://github.com/ChendrayanV/Azure.Admin.Console/actions/workflows/ci.yml)
[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/Azure.Admin.Console?label=PowerShell%20Gallery)](https://www.powershellgallery.com/packages/Azure.Admin.Console)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Azure admin reports and checks from PowerShell, over plain REST. No Az or
Microsoft.Graph modules, and no app registration.

<p align="center">
  <a href="https://youtu.be/bI-_g2D0urk">
    <img src="https://img.youtube.com/vi/odHW8du6dUk/maxresdefault.jpg" alt="Azure.Admin.Console video walkthrough" width="500">
  </a>
</p>

- **Azure Advisor report.** Every Advisor recommendation (Cost, Security,
  Reliability, Operational excellence, Performance) flattened to one row per
  resource, with estimated savings, retirement dates and postponed/dismissed
  status, shown as a colour-coded console view.
- **Azure Firewall rules.** Every Firewall Policy rule (DNAT, network,
  application) with IP Groups resolved to names and addresses, shown one
  colour-coded table per rule collection.
- **Tenant inventory.** Management groups, subscriptions, resource groups
  and resources as one tree, with counts, the Defender for Cloud secure score
  and findings, and - with `-Cost` - what everything costs, at every level.
- **Security posture.** Microsoft Defender for Cloud and Azure Policy in
  one report: secure scores, recommendations by control with remediation
  links, active alerts, Defender plans, regulatory compliance traced to the
  failing resources, and policy compliance.
- **Network security groups.** Every NSG assessed: where it's applied, every
  rule in evaluation order, flow logs and diagnostic settings, and findings
  by severity with what to do.
- **Azure Policy compliance.** Every resource's policy states, with their
  initiative, assignment and effect - by management group, subscription or
  resource group - and compliance per assignment, policy and scope.
- **Entra ID group membership.** Who is in your groups - direct members and
  everyone in nested groups - flattened to one row per group and member,
  with guests and disabled accounts flagged. Read from Microsoft Graph.
- **Resource map.** A diagram of one or more resource groups in your
  browser, with Azure icons, VNets and subnets, network paths, NSGs and
  route tables. Saves as PNG or JPEG.
- **PSRule for Azure.** Its 500+ Well-Architected rules, the module's own
  naming and tag rules, and your custom rules, run on the live estate. You
  can leave rules out by name or wildcard.
- **Fast.** One pooled HTTPS connection for every call, and independent
  reads in parallel within each Azure API's limits.
- **Application Insights.** Your application's exceptions, flattened, or any
  KQL query, from a Log Analytics workspace or an Application Insights
  resource.
- **Resource and cost charts.** Colourful console charts of what you run (by
  type, region, resource group or subscription) and what it costs (month to
  date by subscription and service, and the monthly trend), plus a full
  resource inventory.
- **Output your way.** A console view, PowerShell objects, CSV, PDF or an
  interactive HTML report, from the same command.

Every command reads; only `Deploy-AACStorageAccount` writes, and it plans,
checks Azure Policy and PSRule, and asks first (`-WhatIf` changes nothing).
Each command's help lists the permissions it needs.

## Install

```powershell
Install-PSResource -Name Azure.Admin.Console     # PSResourceGet
# or
Install-Module -Name Azure.Admin.Console -Scope CurrentUser
```

One module is installed with it: PSRule for Azure (PSRule.Rules.Azure 1.47
or later, with PSRule), for `Invoke-AACPSRule`. There are no Az or
Microsoft.Graph modules.

|                                   | Windows         | Linux / macOS                       |
| --------------------------------- | --------------- | ----------------------------------- |
| Console views, objects, CSV, HTML | PowerShell 7.2+ | PowerShell 7.2+                     |
| PDF reports                       | PowerShell 7.4+ | not supported (needs Windows fonts) |

## Quick start

```powershell
Import-Module Azure.Admin.Console
Connect-AAC                                  # opens your browser to sign in

# Azure Advisor: the console view, or CSV, PDF and interactive HTML reports
Get-AACAdvisorRecommendation
Get-AACAdvisorRecommendation -CsvPath .\Advisor.csv -PdfPath .\Advisor.pdf -HtmlPath .\Advisor.html

# Azure Firewall Policy rules, as an interactive HTML report
Get-AACFirewallRule -HtmlPath .\FirewallRules.html

# Which firewall rules let 10.1.2.3 reach 10.0.0.4 on UDP 53?
Get-AACFirewallRule -SourceAddress 10.1.2.3 -DestinationAddress 10.0.0.4 -Port 53 -Protocol UDP

# What you run, and what it costs
Show-AACResource
Show-AACResource -HtmlPath .\Inventory.html     # every resource, with portal links
Show-AACCost

# The tenant as a tree, with secure scores and costs
Get-AACInventory -Cost -HtmlPath .\Inventory.html

# The whole environment, ARI-style: inventory, Advisor, retirements, policy, outages - CSV, HTML, PDF, diagrams
Invoke-AACAssessment -SecurityCenter -IncludeCost

# Defender for Cloud and Azure Policy: scores, recommendations, alerts, plans, compliance
Get-AACSecurityPosture -HtmlPath .\Security.html

# Every network security group, assessed
Get-AACNetworkSecurityGroup

# Azure Policy: every resource's compliance, for one management group
Get-AACPolicyState -ManagementGroupId 'mg-landingzones' -HtmlPath .\Policy.html

# What is assigned: every policy assignment, its parameter values and resource types
Get-AACAssignedPolicy -SubscriptionId '00000000-0000-0000-0000-000000000000' -CsvPath .\AssignedPolicy.csv

# Which VM sizes a new three-zone AKS node pool can use, and why not
Get-AACSkuAvailability -ClusterName 'aks-contoso' -Zone 1, 2, 3 -Series D, E -NodeCount 3

# How much is in every blob container, by access tier, with the largest blobs
Get-AACStorageAccountContainerSize -AuthMode Auto -HtmlPath .\Storage.html

# What a Terraform plan changes, down to each attribute (offline, no sign-in)
Get-AACTerraformPlan -Path .\plan.json

# Who is in your Entra ID groups, nested groups included
Get-AACEntraGroupMembership -GroupNameStartsWith 'grp-' -HtmlPath .\Groups.html

# A diagram of a resource group, in your browser
Show-AACResourceMap -ResourceGroupName 'rg-app'

# PSRule for Azure on the live estate, as a clickable HTML report
Invoke-AACPSRule -HtmlPath .\PSRule.html

# Just the module's naming and tag rules - quick: names, types and tags only
Invoke-AACPSRule -Rule 'AAC.*'

# A storage account, idempotently: plan, Azure Policy and PSRule gates, then apply (no template)
Deploy-AACStorageAccount -SubscriptionId <subscription> -ResourceGroupName rg-data -ConfigurationPath .\Examples\storage-account.psd1 -WhatIf

# Which resources' logs don't reach Log Analytics - and what is misconfigured
Get-AACDiagnosticSetting -ExpectedWorkspace 'law-central' -HtmlPath .\Diagnostics.html

# A Log Analytics workspace: table sizes, settings, recommendations, insights
Invoke-AACLogAnalyticsWorkspaceAssessment -WorkspaceId 'law-contoso-prod' -HtmlPath .\Workspace.html

# Virtual networks: available IPs, subnets, peerings, NSGs, ASGs, DNS and security
Invoke-AACVirtualNetworkAssessment -HtmlPath .\VNet.html

# The last 2 hours of exceptions from Application Insights
Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-contoso-prod'
```

### Console view or reports

Every command works the same way:

- **Console view:** at the prompt, a command draws its view. A view longer
  than the terminal is shown a page at a time: press any key for the next
  page, or A for the rest. `-NoPaging` turns paging off, and it's skipped
  automatically when output is redirected.
- **Reports:** with `-CsvPath`, `-PdfPath` or `-HtmlPath`, the report is in
  the files. The console shows only the progress and the files written, not
  the view. Add `-PassThru` to get the objects as well.
- **Objects:** piped onward, or with `-NoDisplay`, a command returns its
  objects and draws no view. Stopping early is fine:
  `Get-AACSkuAvailability -Location uksouth | Select-Object -First 5` ends the
  command quietly and the rest of your script carries on.
- **Progress:** every command shows the same progress display: the title,
  then one line per step with a bar, a percentage and the elapsed time, each
  finishing with what it did.
- **Status:** every command shows a state the same way, as a symbol, a
  colour and a word, so nothing depends on colour alone:

  | State       | Symbol | Colour | Used for                                        |
  | ----------- | ------ | ------ | ----------------------------------------------- |
  | Success     | ✓ (+)  | green  | done, verified, healthy, nothing to fix         |
  | Warning     | ⚠ (!)  | orange | partly read, degraded, needs attention          |
  | Failed      | ✗ (x)  | red    | failed, blocked, unavailable                    |
  | In progress | ↻ (~)  | blue   | running, ready to apply                         |
  | Info        | ℹ (i)  | grey   | nothing found, notes                            |

  Outcomes that matter (verified, blocked, no changes, nothing found, what
  couldn't be read) are callouts: a rounded panel in the state's colour,
  headed by its symbol. Notices are status lines. The symbols in brackets
  are what a console that isn't UTF-8 (code page 437 or 850) shows instead.

**Nothing is cut off.** Console views wrap long text - reasons,
recommendations, messages - rather than truncating it, and list every
finding; the PSRule view lists up to 50 resources per rule and says how many
more there are. The objects' default tables at the prompt wrap too
(`Azure.Admin.Console.Format.ps1xml`), and `Format-List *` or
`Select-Object *` shows every property.

The HTML reports are single, self-contained files with no external scripts,
styles or fonts, so they open offline and work as email attachments or
pipeline artifacts. Each one has:

- tables that start collapsed: click a table's title (or press Enter on it)
  to show or hide it, or use _Expand all_ / _Collapse all_; a tile, chart or
  tree link opens the table it filters, and printing shows every table;
- clickable tiles and bar charts that filter the table;
- search, filter drop-downs, sortable columns, and grouping with subtotals;
- Azure portal links and _Copy ID_ for every resource;
- a CSV download of exactly the rows shown;
- light and dark themes, and a layout that works on a phone.

The PDF reports open with the bookmarks panel showing: one bookmark per
section and table, nested, and collapsed so the panel starts as a short list
of sections. A PDF can't hide its tables the way a web page can, so the
bookmarks are how you jump to the one you want.

## Commands

| Command                                                                                          | What it does                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`Deploy-AACStorageAccount`](docs/Deploy-AACStorageAccount.md)                                   | Creates or updates a storage account - containers, file shares, queues, tables, lifecycle rules, private endpoints, diagnostic settings, role assignments, a lock and blobs - idempotently with the Azure REST APIs, no ARM, Bicep or Terraform template. AVM's parameter names and defaults; a plan (create, update, can't change in place, drift); gates: the name, Azure Policy (`checkPolicyRestrictions` on every write's exact body) and PSRule for Azure; then apply and verify. The only command that writes.                                                                                                                             |
| [`Connect-AAC`](docs/Connect-AAC.md)                                                             | Signs in with a browser (OAuth 2.0 + PKCE, localhost redirect) - or a device code (`-DeviceCode`), a service principal's secret or certificate (`-ClientSecret`, `-CertificatePath`, `-CertificateThumbprint`), or a managed identity (`-Identity`, e.g. in Azure Automation). Uses the Azure CLI's pre-consented public client ID unless you pass `-ClientId`.                                                                                                                                                                                                                                                                                   |
| [`Disconnect-AAC`](docs/Disconnect-AAC.md)                                                       | Forgets the sign-in. It was only ever in memory.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| [`Get-AACAdvisorRecommendation`](docs/Get-AACAdvisorRecommendation.md)                           | A consolidated, flattened view of Azure Advisor: a console view at the prompt, objects down a pipeline, CSV and/or PDF exports.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| [`Get-AACFirewallRule`](docs/Get-AACFirewallRule.md)                                             | Every Azure Firewall Policy rule: a console view at the prompt (Allow in green, Deny in red), objects down a pipeline, CSV and/or PDF exports.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| [`Show-AACResource`](docs/Show-AACResource.md)                                                   | A colourful bar chart of your resources by type, location, resource group or subscription.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| [`Invoke-AACAksAssessment`](docs/Invoke-AACAksAssessment.md)                                     | AKS clusters through every lens: current settings, about 35 Well-Architected checks scored per pillar, PSRule for Azure, Azure Policy for Kubernetes consolidated by namespace, workload, policy and cluster (the AKS Policy Compliance Toolkit's view) with Gatekeeper's complete counts, versions and upgrades, subnet capacity, Advisor and Defender. A console view, objects, and CSV, PDF and interactive HTML reports.                                                                                                                                                                                                                      |
| [`Invoke-AACAssessment`](docs/Invoke-AACAssessment.md)                                           | An Azure environment assessed end to end, in the spirit of Azure Resource Inventory: a sheet per resource type (~95) with its key settings, the organization, Advisor and retirements, Defender, Policy, outages, quotas, reservations and cost - CSV, an interactive HTML report, a PDF and interactive network and organization diagrams, with a live progress display. Runs in Azure Automation with a managed identity and uploads to blob storage.                                                                                                                                                                                           |
| [`Get-AACInventory`](docs/Get-AACInventory.md)                                                   | The tenant as a tree: management groups, subscriptions, resource groups and resources, with counts, the Defender for Cloud secure score and - with `-Cost` - the cost at every level. A console tree, objects, and CSV, PDF and interactive HTML reports.                                                                                                                                                                                                                                                                                                                                                                                         |
| [`Get-AACSecurityPosture`](docs/Get-AACSecurityPosture.md)                                       | Microsoft Defender for Cloud and Azure Policy in one report: secure scores, recommendations grouped by control with remediation links, active alerts, Defender plans, regulatory compliance traced to the failing resources, and policy compliance per assignment - one list of findings. A console view, objects, and CSV, PDF and interactive HTML reports.                                                                                                                                                                                                                                                                                     |
| [`Get-AACSkuAvailability`](docs/Get-AACSkuAvailability.md)                                       | Which VM sizes you can use for virtual machines or AKS node pools in a region and its availability zones - the subscription's restrictions, vCPU quota and AKS's rules - and why a size can't be used; an AKS cluster's node pools. Read-only REST, nothing deployed. A console view, objects, and CSV, PDF and interactive HTML reports.                                                                                                                                                                                                                                                                                                         |
| [`Get-AACAssignedPolicy`](docs/Get-AACAssignedPolicy.md)                                         | Every Azure Policy assignment and its parameters - the default, assigned and effective value of each - with the resource types the policy applies to (its rule's type conditions, parameters resolved), one row per assignment and parameter. Assignments inherited from management groups included. A console view, objects, and CSV and interactive HTML reports.                                                                                                                                                                                                                                                                               |
| [`Invoke-AACPolicyAssessment`](docs/Invoke-AACPolicyAssessment.md)                               | Azure Policy assessed as a whole, in the spirit of AzPolicyLens: compliance (each resource counted at its worst state) overall and by subscription, management group, assignment, policy and category; exemptions and their expiry; initiatives and definitions; the managed identities' roles; what to improve (direct assignments, DoNotEnforce, remediation without an identity or role, deprecated policies, overlapping assignments, stale exemptions, unassigned custom definitions, unused groups). Platform and Application audiences. A console view, objects, and CSV, PDF and interactive HTML reports with the management group tree. |
| [`Invoke-AACDefenderAssessment`](docs/Invoke-AACDefenderAssessment.md)                           | Microsoft Defender for Cloud assessed across subscriptions: every recommendation (unhealthy, healthy and not applicable resources, risk level), attack paths step by step, security alerts with MITRE tactics and remediation, the inventory with each resource's plan coverage, vulnerabilities (CVEs), secure score controls, Defender plans with extensions, regulatory compliance, and environment settings (contacts, notifications, integrations, connectors, just-in-time) - with findings on how Defender is set up. A console view, an object, CSV and a tabbed HTML report in the portal's order. |
| [`Invoke-AACM365Assessment`](docs/Invoke-AACM365Assessment.md)                                   | Microsoft 365 tenant discovery and security posture from the Microsoft Graph REST API with one token: Entra ID (settings, Conditional Access, admin roles, MFA registration, authentication methods), Microsoft 365 (domains, Secure Score, SharePoint and OneDrive sharing, audit logging) and Intune (enrollment restrictions, compliance, endpoint security, stale and unmanaged devices) - with zero-trust findings. A console view, an object, CSV and a tabbed HTML report. |
| [`Get-AACPolicyState`](docs/Get-AACPolicyState.md)                                               | Azure Policy compliance for every resource - one row per resource and policy, with initiative, assignment, effect and when it was evaluated - by management group, subscription or resource group, with compliance per assignment, policy, subscription and resource group. A console view, objects, and CSV, PDF and interactive HTML reports.                                                                                                                                                                                                                                                                                                   |
| [`Get-AACNetworkSecurityGroup`](docs/Get-AACNetworkSecurityGroup.md)                             | A detailed assessment of network security groups: associations, every rule, flow logs and diagnostic settings, and findings by severity (open to the internet, shadowed rules, subnet and NIC conflicts, logging gaps). A console view, objects, and CSV, PDF and interactive HTML reports.                                                                                                                                                                                                                                                                                                                                                       |
| [`Get-AACStorageAccountContainerSize`](docs/Get-AACStorageAccountContainerSize.md)               | How much is stored in every blob container of your storage accounts: blobs, bytes, access tiers (Hot, Cool, Cold, Archive), snapshots, versions and deleted blobs, the newest change and the largest blobs - read in parallel, a page of 5,000 blobs at a time. Entra ID or a short-lived account SAS. A console view with every account and container as a tree, objects, and CSV and interactive HTML reports.                                                                                                                                                                                                                                  |
| [`Get-AACTerraformPlan`](docs/Get-AACTerraformPlan.md)                                           | A Terraform plan in JSON (`terraform show -json`), flattened: what will be created, updated, replaced, deleted, read, imported and moved - and why - down to each attribute's before and after value, with the outputs and what changed outside Terraform. Sensitive values are never shown. Offline: no sign-in. A console view, objects, and CSV and interactive HTML reports.                                                                                                                                                                                                                                                                  |
| [`Get-AACDiagnosticSetting`](docs/Get-AACDiagnosticSetting.md)                                   | Every resource's diagnostic settings, flattened, and the resources whose logs don't reach a Log Analytics workspace: each one's status (exported, partial, not to a workspace, no setting), what's missing and why, and misconfigurations (deleted workspaces, nothing enabled, logs sent twice, another region, unexpected workspace, retired retention). Storage services and subscription activity logs included. A console view, objects, and CSV, PDF and interactive HTML reports.                                                                                                                                                          |
| [`Get-AACEntraGroupMembership`](docs/Get-AACEntraGroupMembership.md)                             | Entra ID groups and everyone in them - direct and through nested groups - one row per group and member, with type, source, guests and disabled accounts. A console view with each group's members as a tree, objects, and CSV, PDF and interactive HTML reports.                                                                                                                                                                                                                                                                                                                                                                                  |
| [`Show-AACResourceMap`](docs/Show-AACResourceMap.md)                                             | A map of one or more resource groups, opened in your browser: the resources with their Azure icons, in subscription, resource group, VNet and subnet boxes, with their connections, dependencies and network paths. Saves as PNG or JPEG.                                                                                                                                                                                                                                                                                                                                                                                                         |
| [`Show-AACCost`](docs/Show-AACCost.md)                                                           | Subscription costs: month to date by subscription and by service, and a monthly trend, as charts and a table.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| [`Show-AACDashboard`](docs/Show-AACDashboard.md)                                                 | A one-screen dashboard: one status at the top (healthy, needs attention, action needed), the session, subscriptions, resources by region, Resource Health, active Azure Service Health events, Advisor and the latest resource changes - from one Resource Graph batch. `-Select` picks the subscriptions from a list.                                                                                                                                                                                                                                                                                                                           |
| [`Show-AACJson`](docs/Show-AACJson.md)                                                           | JSON - or any object, as JSON - indented and syntax-coloured in a panel: ARM templates, REST responses, resources, this module's objects.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| [`Get-AACCostAnomaly`](docs/Get-AACCostAnomaly.md)                                               | Spend anomalies before the invoice: spikes, drops, new spend, level shifts and steady rises by service, resource group, region or meter (robust median/MAD statistics), the resources behind each, a month-end forecast and a subscription benchmark.                                                                                                                                                                                                                                                                                                                                                                                             |
| [`Get-AACAttackPath`](docs/Get-AACAttackPath.md)                                                 | Attack paths from the Internet, through managed identities, to what an attacker could control or read - with blast radius, risk and the fix; plus Defender for Clouds own paths.                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| [`Get-AACAccessReview`](docs/Get-AACAccessReview.md)                                             | A least-privilege access review of Azure RBAC (permanent, PIM-activated, eligible), classic admins, Entra ID roles and Graph application permissions - unused, standing, guest, orphaned and over-broad access, with an attestation CSV.                                                                                                                                                                                                                                                                                                                                                                                                          |
| [`Get-AACChangeHistory`](docs/Get-AACChangeHistory.md)                                           | Who changed what, when and from where - properties before and after, how to undo it, and the alerts and health events that followed - a timeline for incidents and change control.                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| [`Invoke-AACHealthCheck`](docs/Invoke-AACHealthCheck.md)                                         | Endpoints (synthetic requests, latency, TLS expiry), databases, Service Bus queues, Resource Health, Service Health and alerts - by tier, with an SLA report and a live -Watch board.                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| [`Get-AACComplianceGap`](docs/Get-AACComplianceGap.md)                                           | Compliance gaps per framework (CIS, PCI-DSS, HIPAA, SOC 2, GDPR, ISO 27001, NIST, MCSB) from Defender and Azure Policy, prioritised by risk and effort as a roadmap, with progress against a baseline.                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| [`Get-AACFailoverReadiness`](docs/Get-AACFailoverReadiness.md)                                   | Disaster recovery readiness: backups (fresh, succeeding, restore-tested), Site Recovery (health, RPO, test failover), vault settings and recovery plan runbooks, with a confidence score.                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| [`Get-AACDependencyGraph`](docs/Get-AACDependencyGraph.md)                                       | Which resources depend on which (network, pools, Front Door, plans, private endpoints, identities, Application Insights calls): blast radius, single points of failure, cycles and critical services; Graphviz export.                                                                                                                                                                                                                                                                                                                                                                                                                            |
| [`Get-AACResourceUtilization`](docs/Get-AACResourceUtilization.md)                               | Idle, under-used, hot and right-sized resources from their actual CPU, memory and activity, with trends, VM right-sizing priced from Azure retail prices, and an unused-cost chargeback.                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| [`Get-AACConfigurationDrift`](docs/Get-AACConfigurationDrift.md)                                 | Configuration drift against a saved baseline, desired-state rules (or a built-in security baseline) or Terraform - who changed it, the strategy to fix it, and the trend over time.                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| [`Invoke-AACPSRule`](docs/Invoke-AACPSRule.md)                                                   | PSRule for Azure, the module's own naming and tag rules and your custom rules on the live estate: include or exclude rules by name or wildcard, with a baseline or settings. Runs of only the module's rules read just names, types and tags.                                                                                                                                                                                                                                                                                                                                                                                                     |
| [`Invoke-AACVirtualNetworkAssessment`](docs/Invoke-AACVirtualNetworkAssessment.md)               | Virtual networks assessed: address space with total, used and available IPs and the free CIDR ranges; every subnet (capacity, NSG, routes, NAT gateway, outbound path, endpoints, delegations); peerings; NSGs and ASGs; DNS, DDoS, encryption, flow logs, gateways, firewalls and Bastion - with findings by severity. A console view, objects, and CSV, PDF and interactive HTML reports.                                                                                                                                                                                                                                                       |
| [`Invoke-AACLogAnalyticsWorkspaceAssessment`](docs/Invoke-AACLogAnalyticsWorkspaceAssessment.md) | A Log Analytics workspace assessed: billable and not billable tables with their size, plan and retention; every workspace setting; recommendations (Azure Advisor's and its own: cost, reliability, security); data collection rules; and the Workspace Insights views - Overview, Usage, Health, Agents, Query Audit, Data Collection Rules, Change Log. Read-only. A console view, an object, and CSV and interactive HTML reports.                                                                                                                                                                                                             |
| [`Invoke-AACApplicationInsightQuery`](docs/Invoke-AACApplicationInsightQuery.md)                 | Application Insights exceptions, flattened, from a Log Analytics workspace or Application Insights resource, or any KQL query.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |

Full help:

- **In PowerShell:** run `Get-Help <command> -Full`, or `Get-Help about_Azure.Admin.Console` for the module overview.
- **On the web:** see [docs/](docs/Azure.Admin.Console.md).

## Azure Advisor recommendations

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

## Azure Firewall rules

`Get-AACFirewallRule` reads every Firewall Policy rule from Azure Resource
Graph. It returns output the same way as `Get-AACAdvisorRecommendation`:

- **At the prompt:** a console view.
- **Piped onward:** the objects, with no view.
- **`-PassThru`:** both. **`-NoDisplay`:** the objects only.
- **`-CsvPath`, `-PdfPath` and `-HtmlPath`:** the report is in the files,
  and the console shows only the progress.

The HTML report groups the rules by rule collection and flags Allow rules open
to any source or destination (`*`, `0.0.0.0/0`). Click the tile to list just
those rules.

```powershell
Get-AACFirewallRule                                          # the console view
Get-AACFirewallRule -CsvPath .\rules.csv -PdfPath .\rules.pdf -HtmlPath .\rules.html
Get-AACFirewallRule -FirewallPolicyName 'fwpol-hub-*' |
    Where-Object { $_.Action -eq 'Allow' -and $_.SourceAddresses -match '(^|, )\*($|,)' }
```

The view follows the policy hierarchy:

1. **Tiles** for the rules, allow, deny and DNAT counts, policies and rule collections.
2. **A policies table** with each policy's base policy, attached firewalls and rule counts.
3. **One section per policy**, with one table per rule collection in priority order:

```text
╭──── rcg-platform · 100 › Allow-Web · 200 · Filter · 2 rules   ALLOW ────╮   (green border)
│ Rule          │ Source             │ Destination        │ Protocols · ports │ Translation · TLS  │
│ web-out       │ 10.0.0.0/16        │ fqdn *.contoso.com │ Https:443         │ TLS inspection off │
│ application   │ ipg-spokes (IP     │                    │                   │                    │
│ rule          │ group)             │                    │                   │                    │
│               │ 10.1.0.0/16, …     │                    │                   │                    │
╰───────────────────────────────────────────────────────────────────────────────────────────────╯
╭──── rcg-platform · 100 › Block-Legacy · 300 · Filter · 1 rule   DENY ────╮   (red border)
```

In each table:

- The border and badge carry the collection's action: **Allow** in green, **Deny** in red, **DNAT** in orange.
- IP Groups show their addresses underneath.
- A `*` source or destination on an Allow rule is highlighted in yellow as `* (any)`.
- The last column shows the DNAT translation, or whether TLS inspection is on for application rules.
- Long output is paged; `-NoPaging` turns paging off.

### Searching rules

Search parameters narrow the rules. You can combine them, and each takes several values:

- **All given filters must match.** A rule appears only if it satisfies every search parameter you pass.
- **Any value of one filter will do.** `-Port 22, 3389` matches a rule for either port.

Addresses and ports match by containment, so a search answers "which rules
let this source reach that destination?":

| Parameter                               | Matches                                                                                                                                                |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `-SourceAddress`, `-DestinationAddress` | An IP, CIDR or `a-b` range (IPv4 or IPv6). It matches rules that cover or overlap it, including through IP Groups, and a `*` rule matches any address. |
| `-Port`                                 | A port or range (`443`, `8000-8080`), overlapping the rule's ports. For application rules, each protocol's port counts.                                |
| `-Protocol`                             | `TCP`, `UDP` or `ICMP`, where a rule for `Any` matches all; or `Http`, `Https` or `Mssql` for application rules.                                       |
| `-Fqdn`                                 | A host name covered by the rule's FQDNs (`*.contoso.com` covers `www.contoso.com`), or a wildcard pattern.                                             |
| `-Action`, `-RuleName`                  | `Allow`, `Deny` or `DNAT`; a rule-name wildcard.                                                                                                       |

```powershell
Get-AACFirewallRule -SourceAddress 10.1.2.3 -DestinationAddress 10.0.0.4 -Port 53 -Protocol UDP
Get-AACFirewallRule -Action Allow -SourceAddress 0.0.0.0/0 -Port 3389, 22     # RDP/SSH open to any source
Get-AACFirewallRule -Fqdn www.contoso.com -Protocol Https -CsvPath .\contoso.csv
```

The results come back in priority order, allow and deny alike, so the first
match is the one Azure Firewall applies. Service tags (such as `AzureCloud`)
aren't expanded, so an address search doesn't match them.

The rules are listed in the order the Azure portal shows them. The CSV has one
row per rule, with the base policy and attached firewalls on every row. The
PDF groups rules by policy, rule collection group and collection, with the
same colours.

## Dashboard

`Show-AACDashboard` puts the state of your estate on one screen, from one
Azure Resource Graph batch:

```powershell
Show-AACDashboard                                # every subscription you can see
Show-AACDashboard -Select -Hours 72              # tick the subscriptions in a list; changes of the last 3 days
(Show-AACDashboard -NoDisplay).Status            # Success, Warning or Failed - for a script or a pipeline
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

Then the subscriptions and their state, resources by region, the active
Azure Service Health events (service issues, planned maintenance,
advisories, once each however many subscriptions they touch), the unhealthy
resources, Advisor recommendations by category and impact, and the latest
resource changes: what was created, updated or deleted, where and by whom.

The status at the top is **Action needed** when resources are unavailable or
a service issue is active; **Needs attention** when resources are degraded,
Advisor has High-impact recommendations, maintenance or an advisory is
active, or something couldn't be read; and **Healthy** otherwise. Anything
the account can't read is listed at the end, and the rest is still shown.
`-Select` asks at the console (arrow keys, space, Enter); in a script, use
`-SubscriptionId`.

`Show-AACJson` shows JSON, or any object as JSON, indented and coloured
(names, strings, numbers, booleans and null each in their own colour):

```powershell
Get-Content .\azuredeploy.json -Raw | Show-AACJson -Title 'ARM template'
Invoke-RestMethod -Uri $uri -Headers $headers | Show-AACJson -Title 'Response'
```

## Cost, security, operations, compliance and resilience

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

## Resources and costs

`Show-AACResource` counts every resource you can see with two Resource Graph
queries, and draws one bar per type, each in its own colour:

```text
Resources by type (top 20 of 57)
  compute/virtualmachines  ███████████████████████████████████████████ 412
network/networkinterfaces  █████████████████████████████████████████ 398
  storage/storageaccounts  █████████████████ 164
           37 other types  ██████ 61
```

```powershell
Show-AACResource                                  # by type, top 20
Show-AACResource -By Location                     # or ResourceGroup, Subscription
Show-AACResource -ResourceType 'microsoft.network/*' -Top 10
Show-AACResource -By Subscription -PassThru | Export-Csv .\PerSubscription.csv
Show-AACResource -HtmlPath .\Inventory.html        # an interactive inventory
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

## Azure environment assessment

`Invoke-AACAssessment` assesses a whole Azure environment in one run - the
module's take on [Azure Resource Inventory (ARI)](https://github.com/microsoft/ARI):
an inventory of every resource type with the settings that matter for it, the
organization, Advisor and retirements, Defender for Cloud, Azure Policy
compliance and inventory, PSRule for Azure, one list of recommendations,
outages, quotas and cost - as CSV files, a tabbed HTML workbook, a PDF and
interactive diagrams. Read-only, Resource Graph and REST only: no Az modules,
no Excel.

```powershell
Connect-AAC
Invoke-AACAssessment                                                    # everything the account can see
Invoke-AACAssessment -TenantId 'contoso.onmicrosoft.com' -SecurityCenter -IncludeTag -IncludeCost
Invoke-AACAssessment -ManagementGroupId 'mg-landingzones' -ReportDir C:\Reports -Output Html, Diagram
Invoke-AACAssessment -SubscriptionId $sub -TagKey 'Environment' -TagValue 'Production' -Category Compute, Networking
Invoke-AACAssessment -SubscriptionId $sub -PSRule -PSRuleBaseline 'Azure.Pillar.Security'   # PSRule for Azure too
(Invoke-AACAssessment -Output Csv -NoDisplay).Sheets['Resource recommendations'] | Where-Object Severity -In 'Critical', 'High'
(Invoke-AACAssessment -Output Csv -NoDisplay).Sheets['Virtual machines'] | Where-Object 'Power state' -NE 'VM running'
```

**How a run goes.** A live Spectre.Console progress display shows each phase as it
happens, and the run ends with a summary - what was found, what needs attention,
where the reports are and how long each phase took:

| Phase      | What it reads                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Scope      | The subscriptions in scope (by `-SubscriptionId`, `-ManagementGroupId` at any depth, or everything the account can see) and the tenant's management groups                                                                                                                                                                                                                                                                                                                                                                                       |
| Estate     | Every resource and resource group (`-ResourceGroupName`, `-TagKey`/`-TagValue` filter them), the resource types present, Advisor recommendations and retirements, Defender for Cloud (`-SecurityCenter`), Azure Policy compliance (unless `-SkipPolicy`), support tickets                                                                                                                                                                                                                                                                        |
| Inventory  | A sheet per resource type present - about 95 types in 14 categories (`-Category` picks some): VMs, scale sets, disks, AKS and its node pools, container apps, SQL, Cosmos DB, PostgreSQL and MySQL, Redis, storage accounts, key vaults, virtual networks, subnets, peerings, NSG rules, firewalls, gateways, private endpoints, App Services, Log Analytics, Recovery Services and backup items, Arc servers, AI services and more - each with the settings that matter for it, as Resource Graph projections (only the types present are read) |
| Azure APIs | Per subscription: the Advisor score, reservation recommendations, the last 6 months' outages (Resource Health service issues), compute quotas (`-QuotaUsage`) and VM sizes' vCPUs and memory (unless `-SkipVMDetail`); `-SkipApi` skips them                                                                                                                                                                                                                                                                                                     |
| Cost       | Each resource's actual cost, this month and last (`-IncludeCost`)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| Governance | The policy assignments in force and every policy they apply (unless `-SkipPolicy`); PSRule for Azure's rules on the resources (`-PSRule`); then the governance sheets and one list of recommendations |
| Reports    | The reports in `-Output` (all by default), then an upload to blob storage (`-StorageAccount`, `-StorageContainer`)                                                                                                                                                                                                                                                                                                                                                                                                                               |

Every inventory sheet adds, after its own columns, the resource's **Retirement**
notice (from Advisor), its **Advisor** recommendation count, its **cost** with
`-IncludeCost` and its **tags** with `-IncludeTag`. Overview sheets come first:
Subscriptions (management groups, counts, secure score, cost), Resource groups
(the empty ones flagged), Resource types, All resources; then Advisor
recommendations, Advisor score, Retirements, Security recommendations, Secure
score, Policy compliance, Outages, Quotas, Support tickets and Reservation
recommendations.

**Governance.** Every run also reads the policy assignments in force and adds:

| Sheet                        | What's in it                                                                                                                                                                                         |
| ---------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Compliance by initiative     | Each assignment: its policies by status, and the compliance of its resource states                                                                                                                   |
| Compliance by resource group | Each resource group's resources: non-compliant with any policy, compliant or exempt                                                                                                                  |
| Compliance by standard       | The controls of the initiatives that map their policies to a standard (CIS, NIST, ISO 27001, the Microsoft cloud security benchmark ...), with the policies behind each                              |
| Non-compliant resources      | Each resource and the policy it fails: why, and how to fix it (a remediation task, a configuration change or an attestation), with a docs link                                                       |
| Policy assignments           | Every assignment in force on the scope, inherited ones too: definition, enforcement, policies, resource types, compliance                                                                           |
| Policies                     | Every policy in force, per assignment: effect, resource types, controls, and status (Failed, Passed, Manual review, Exempt, Not evaluated, Disabled)                                                 |
| PSRule rules, PSRule results | With `-PSRule` (and `-PSRuleBaseline`): each PSRule for Azure rule run on the resources (checked, passed, failed, its documentation), and each failure with its reason. Needs `PSRule.Rules.Azure` |
| Resource recommendations     | Everything to act on in one list, most severe first: Advisor, Defender, retirements, unattached and empty resources, policy non-compliance and PSRule, each with a category and what to do          |

**The reports**, in `<-ReportDir>\<-ReportName>-<date>\`:

| Report                     | What's in it                                                                                                                                                                                                                                                                                                                               |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `<name>.html`              | A tabbed workbook. Executive summary: tiles (each opening its table), charts that filter the table behind them (policies by status, non-compliant resources by resource group, recommendations by severity and category, PSRule rules, resources by category, location, subscription and type, Advisor, Defender) and the tenant tree. Then Policy compliance, Policy inventory, PSRule results, Resource recommendations, Resources, Inventory, Advisor, Security, Health and Cost, each table with row details and a CSV download - searchable, filterable, groupable, each downloadable as CSV |
| `csv\`                     | A CSV file per sheet                                                                                                                                                                                                                                                                                                                       |
| `<name>.pdf`               | The summary, then each category with its sheets' key columns, bookmarked                                                                                                                                                                                                                                                                   |
| `<name>-Network.html`      | An interactive network diagram: virtual networks and subnets, peerings, gateways and connections, firewalls, Bastion, load balancers, application gateways, private endpoints and DNS zones, with NSGs and route tables (rules and routes) on what they apply to. `-DiagramFullEnvironment` draws every resource and how they connect      |
| `<name>-Organization.html` | An interactive diagram of management groups > subscriptions > resource groups, with resource counts                                                                                                                                                                                                                                        |
| `<name>-Resources.html`    | Each subscription with a node per resource type (its Azure icon and count) - ARI's resources view, readable at any tenant size                                                                                                                                                                                                             |

**Automation.** In an Azure Automation runbook (PowerShell 7.4 runtime, this
module imported), `Invoke-AACAssessment -Automation -StorageAccount <account>
-StorageContainer <container>` signs in with the account's managed identity,
writes plain progress lines to the job log and uploads the reports to blob
storage. The identity needs Reader on the management group or subscriptions
and Storage Blob Data Contributor on the storage account. The same works in a
pipeline with `Connect-AAC -ClientSecret` or `-CertificatePath` first.

**Tenants.** `-TenantId` takes the tenant's ID or one of its domains; the run
signs in to it first (in the browser) only when the current session is for
another tenant.

**Permissions.** Reader is enough for the inventory, Advisor, Policy, outages
and quotas; Security Reader for Defender (`-SecurityCenter`); Cost Management
Reader for `-IncludeCost`. What can't be read is listed in the summary and the
report, and the rest carries on.

## Tenant inventory

`Get-AACInventory` reads the tenant with Azure Resource Graph and shows it as a
tree:

```text
TENANT Contoso · 5 management groups · 3 subscriptions · 5 resource groups · 17 resources
├── MG Tenant Root Group
│   ├── MG Landing Zones · 1 subscription · 10 resources
│   │   └── MG Corp
│   │       └── SUB sub-corp-apps  Enabled · 3 resource groups · 10 resources
│   │           ├── RG rg-app  uksouth · 7 resources · disks 2, virtualmachines 2, ...
│   │           └── RG rg-empty  uksouth  empty
│   └── MG Platform ...
└── SUB sub-legacy  Warned · 1 resource group · 1 resource
```

```powershell
Get-AACInventory                                              # the whole tenant, down to resource groups
Get-AACInventory -ManagementGroupId 'mg-landingzones' -Depth Resource
Get-AACInventory -SubscriptionId $sub1, $sub2 -ResourceGroupName 'rg-app', 'rg-data'
Get-AACInventory -HtmlPath .\Inventory.html -PdfPath .\Inventory.pdf -CsvPath .\Inventory.csv
Get-AACInventory -NoDisplay | Where-Object { $_.Level -eq 'ResourceGroup' -and $_.Resources -eq 0 }   # empty resource groups
Get-AACInventory -Cost -HtmlPath .\Inventory.html                # with what everything costs
Get-AACInventory -Insight -Cost -HtmlPath .\Inventory.html       # plus the estate's mix and what needs attention
```

**How the tree is built**

- **Counts:** every node shows the subscriptions, resource groups and
  resources below it, and each resource group shows its most common types.
- **Management groups** are nested as in Azure. A group with no subscriptions
  in the result is left out, unless you ask for it with `-ManagementGroupId`.
- **A subscription whose management group you can't read** is shown under
  the tenant.
- **Empty resource groups** are flagged.
- **Scope:** `-ManagementGroupId`, `-SubscriptionId` and `-ResourceGroupName`
  each take several values. `-Depth` (ManagementGroup, Subscription,
  ResourceGroup or Resource) sets how deep the console tree goes. The objects
  and exports always have everything.

**Security posture** comes from Microsoft Defender for Cloud, through
Resource Graph's `securityresources`, so Reader access is enough:

| Level                    | Secure score                                            |
| ------------------------ | ------------------------------------------------------- |
| Subscription             | Defender's own secure score (points out of the maximum) |
| Management group, tenant | The subscriptions' scores added up, as Defender does    |
| Resource, resource group | The share of assessed recommendations that are healthy  |

- **Colours:** **Good** is 70% or more (green), **Fair** 40–69% (amber),
  **Poor** under 40% (red). Findings are counted by severity on every node:
  **H** red, **M** amber, **L** blue.
- **Controls:** the **security controls** are listed with the **potential
  score increase** of fixing each (their impact). The console shows the ones
  with the most to gain.
- **Recommendations:** every unhealthy **recommendation**, with its severity,
  user impact, effort, category and resource.
- **Without Defender data** (not enabled, or no access), the inventory is
  shown without it. `-NoSecurity` skips reading it.

**Cost** (`-Cost`) comes from Azure Cost Management, so it needs Cost
Management Reader (or Reader) on the subscriptions. Every node shows its
actual cost month to date and last month:

```text
└── SUB sub-corp-apps  3 resource groups · 10 resources  212.00 USD MTD · last month 150.00 USD
    ├── RG rg-app  7 resources  150.00 USD MTD · last month 150.00 USD
    └── DEL Deleted resources  costs of resources no longer in Azure (2), and charges not tied to a resource  32.00 USD MTD
```

- **Queries:** one for the whole tenant root group (or `-ManagementGroupId`)
  when the billing account allows it (Enterprise Agreement, Microsoft
  Customer Agreement); otherwise one per subscription, 3 at a time, retried
  as Cost Management's throttling headers ask.
- **Every charge placed:** a child resource's cost goes to the closest
  resource above it; costs of deleted resources, and charges not tied to a
  resource, go under their subscription as **Deleted resources**.
- **Never converted:** amounts stay in each subscription's billing
  currency. A level whose subscriptions are billed in different currencies
  says so instead of adding them up.
- **Unreadable subscriptions** (some offer types, or no permission) say why
  in `CostStatus`; the rest of the inventory is unaffected.

**Output**

- **Objects:** one `AAC.InventoryItem` per node, with Level, Path, the
  management group, subscription and resource group it's in, type, location,
  SKU, state, counts, most common types, secure score, rating, findings by
  severity, top findings, cost (`CostMonthToDate`, `CostLastMonth`,
  `Currency`, `CostStatus`), tags and ID.
- **`-CsvPath`:** every node, one row each.
- **`-HtmlPath`:** secure score and finding tiles; charts, including
  findings by severity and the controls with the most to gain; the hierarchy
  as a collapsible, searchable tree, with each node's score and findings as
  coloured pills, where clicking a node shows it in the tables; and tables of
  management groups, subscriptions, resource groups, resources, security
  controls and recommendations, each with its own CSV download.
- **`-PdfPath`:** the summary, the hierarchy with coloured scores, the
  security posture (subscription scores, controls, recommendations),
  subscriptions, resource groups, resources by type, and the resources.

## Security posture

`Get-AACSecurityPosture` reads Microsoft Defender for Cloud and Azure Policy
with Azure Resource Graph (`securityresources`, `policyresources`), every
query at once. Reader or Security Reader is enough.

```powershell
Get-AACSecurityPosture                                                 # every section, every subscription
Get-AACSecurityPosture -Tag @{ Environment = 'Prod' } -HtmlPath .\Security.html
Get-AACSecurityPosture -Section Alerts, Plans                          # just the alerts and the Defender plans
Get-AACSecurityPosture -Section Compliance -Standard '*ISO*' -PdfPath .\ISO.pdf
Get-AACSecurityPosture -NoDisplay | Where-Object { $_.Section -eq 'Recommendation' -and $_.Severity -eq 'High' } | Group-Object Title
```

| Section           | What it shows                                                                                                                                                      |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `Score`           | Each subscription's secure score - Defender's points, added up across subscriptions as Defender does - and the controls with the potential increase of fixing each |
| `Recommendations` | Every unhealthy recommendation on each resource: severity, the secure score control it belongs to, category, description, remediation steps and its portal page    |
| `Alerts`          | Active and in-progress security alerts: severity, intent, resource, age and the alert's page                                                                       |
| `Plans`           | Which Defender plans are on or off in each subscription                                                                                                            |
| `Compliance`      | Each regulatory standard's passed and failed controls; a failed control is traced to the resources failing the recommendations behind it                           |
| `Policy`          | Azure Policy compliance per assignment (display names, even for management group assignments), and every non-compliant resource with the policy and its effect     |

**One list of findings** (`AAC.SecurityFinding`), the same in the objects,
CSV, HTML and PDF: Section, Severity, Title, Category, Control, the
resource, State, Detail, the portal link and since when - most severe first.
`-ResourceGroupName` and `-Tag` narrow the findings to those resources (tag
values match exactly, not as substrings); scores, plans and standards are
per subscription. It tells you when Defender plans are off, because then an
empty alert list doesn't mean nothing happened.

For every policy state in detail - compliant ones too - use
`Get-AACPolicyState`; both commands read the same query.

`Get-AACInventory` and `Get-AACSecurityPosture` share their Defender queries
and objects: the inventory puts each node's score and findings in the tree,
and this command is the posture itself.

## Microsoft Defender for Cloud assessment

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

## Microsoft 365 security posture

`Invoke-AACM365Assessment` discovers a Microsoft 365 tenant and assesses its
security posture with the Microsoft Graph REST API. It uses no AzureAD,
MSOnline, AzureADPreview or Microsoft.Graph modules, and one Graph token for
every call.

A Graph token only carries the permissions consented to the app you sign in
with. `Connect-AAC`'s default (the Azure CLI) can read the directory, but not
Conditional Access, Intune or Secure Score. Sign in once with the read-only
permissions the report needs, for example with Microsoft Graph Command Line
Tools after an admin has consented:

```powershell
Connect-AAC -ClientId 14d82eec-204b-4c2f-b7e8-296a70dab67e `
    -Scope ((Invoke-AACM365Assessment -ListPermission) + 'offline_access', 'openid', 'profile')

Invoke-AACM365Assessment -HtmlPath .\M365.html -CsvPath .\m365      # every section
Invoke-AACM365Assessment -Section Entra                               # Entra ID only
(Invoke-AACM365Assessment -NoDisplay).Registration | Where-Object { $_.Admin -eq 'Yes' -and $_.MfaRegistered -eq 'No' }
```

Your account also needs a directory role that can read them, for example
Global Reader. A service principal works too, with the same permissions as
application permissions (`Connect-AAC -ClientId ... -CertificatePath ...`).
Whatever Graph refuses is listed in the Permissions tab with the permission it
needs; the rest of the report is still made.

| Area          | What it reads                                                                                                                                                                 |
| ------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Entra ID      | Tenant and directory sync, licences, security defaults, user and guest settings, cross-tenant access, Conditional Access and named locations, admin roles (active and PIM eligible), MFA registration, authentication methods, identity providers; MFA coverage (registered and phishing-resistant), emergency access accounts, dangling admins, role overlap, legacy authentication sign-ins, user consent settings, PIM role settings, the members of excluded and role-holding groups, access reviews, password hash sync |
| Threat protection | Risky users, risk detections (Identity Protection) and Microsoft Defender XDR incidents |
| Microsoft 365 | Domains, Microsoft Secure Score and its controls, SharePoint and OneDrive sharing, audit logging (Purview audit log search and the Entra audit log)                            |
| Applications  | App registrations and enterprise apps: expired, expiring and long-lived secrets and certificates; over-privileged permissions (Microsoft Graph application permissions and delegated consents, rated Critical, High, Medium); dangling redirect URIs (hosts looked up in DNS), wildcard and non-HTTPS URIs |
| Coverage      | Every lens, assessed or not and why (permission, licence, role); and what Microsoft Graph doesn't reach (Exchange Online, Defender for Office 365, Purview, Teams, Defender for Cloud Apps, Sentinel), with what would cover it |
| Intune        | Tenant settings, enrollment restrictions, compliance policies, endpoint security policies, managed devices (compliance, encryption, stale), Entra ID devices no MDM manages     |

The findings follow zero trust. Identity: MFA for everyone and for admins,
legacy authentication blocked, risk-based policies, privileged access.
Data: sharing, audit logging and Secure Score. Devices: compliance,
encryption, endpoint security and unmanaged devices. Each finding says what
to do and links to Microsoft's guidance.

## Azure Policy compliance

`Get-AACPolicyState` reads the Azure Policy states with one Azure Resource
Graph KQL query (`policyresources`), with the policies' and initiatives'
display names. The assignments' names, scopes and enforcement are read
tenant-wide, because many are assigned at a management group. Reader is
enough.

```powershell
Get-AACPolicyState                                                           # every subscription you can see
Get-AACPolicyState -ManagementGroupId 'mg-landingzones'                      # every subscription under a management group
Get-AACPolicyState -SubscriptionId $sub -ResourceGroupName 'rg-app', 'rg-data'
Get-AACPolicyState -ComplianceState NonCompliant -HtmlPath .\Policy.html -PdfPath .\Policy.pdf -CsvPath .\Policy.csv
Get-AACPolicyState -ComplianceState NonCompliant -NoDisplay | Group-Object Policy | Sort-Object Count -Descending
```

| Scope                |                                                                                                 |
| -------------------- | ----------------------------------------------------------------------------------------------- |
| `-ManagementGroupId` | Every subscription under these management groups                                                |
| `-SubscriptionId`    | These subscriptions                                                                             |
| `-ResourceGroupName` | Only these resource groups, with either of the above or on its own                              |
| `-ComplianceState`   | Only NonCompliant, Compliant, Exempt, Unknown, Conflict or Error states - filtered in the query |

**One row per resource and policy** (`AAC.PolicyState`): compliance state,
resource, type, resource group, subscription, location, policy, initiative,
assignment, where it is assigned (management group, subscription or resource
group, by name), enforcement, effect and when it was evaluated.

From those rows:

- each **resource** takes the state that ranks first across its policies,
  as the Azure portal does: Non-compliant, Compliant, Error, Conflicting,
  Protected, Exempt, Unknown;
- **compliance (%)** is the portal's: (compliant + exempt + unknown +
  protected resources) / every resource evaluated; _Not started_ states
  aren't counted;
- compliance **per assignment** (least compliant first, with enforcement),
  **per subscription**, **per resource group** and **per policy**.

The console shows tiles, compliance by subscription and by resource group,
the assignments, and every non-compliant resource grouped by policy. The
HTML report has a donut of the states and charts that filter tables of
resources, states, assignments, policies, subscriptions and resource groups.
The PDF has the summary, the scopes, the assignments and the non-compliant
resources by policy. `-CsvPath` writes every state.

### Policy assessment

`Invoke-AACPolicyAssessment` assesses Azure Policy as a whole: what is
assigned, how compliant it is, the exemptions, and what to improve. It follows
the analysis of [AzPolicyLens](https://github.com/Azure/AzPolicyLens): Reader
only, Azure Resource Graph only, no Az modules.

```powershell
Invoke-AACPolicyAssessment                                                     # everything you can see
Invoke-AACPolicyAssessment -ManagementGroupId 'mg-landingzones' -HtmlPath .\Policy.html -PdfPath .\Policy.pdf -CsvPath .\policy
Invoke-AACPolicyAssessment -SubscriptionId '00000000-0000-0000-0000-000000000000' -Audience Application -HtmlPath .\Policy.html
Invoke-AACPolicyAssessment -NoDisplay | Where-Object Rating -NE 'Good'          # assignments under the threshold
```

| What                 | How it works                                                                                                                                                                                                                                                                                                                                                 |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Compliance           | Each resource is counted once, at its worst state (NonCompliant, then Compliant, Conflict, Exempt). Compliance = (compliant + exempt) / all. It is reported overall and by subscription, management group, assignment (and subscription), policy and category. A value under `-ComplianceWarningPercent` (default 80) is a Warning; under half of it is Poor |
| Scope                | No scope: everything. `-ManagementGroupId`: the management group and everything under it. `-SubscriptionId`: those subscriptions and every assignment that reaches them, including assignments made on their management groups (excluded scopes are honoured)                                                                                                |
| Assignments findings | A definition assigned directly instead of in an initiative; DoNotEnforce; a definition that can't be found; compliance under the threshold; deprecated or preview policies assigned; excluded scopes that don't exist; the same definition assigned twice on one scope path; Deny without a non-compliance message                                           |
| Identity findings    | DeployIfNotExists and Modify assignments with no managed identity, or with an identity missing the roles their policies list (`roleDefinitionIds`)                                                                                                                                                                                                           |
| Exemptions findings  | Expired; expiring within `-ExemptionWarningDays` (default 30); no expiry; for an assignment that no longer exists                                                                                                                                                                                                                                            |
| Definitions findings | Unassigned custom definitions and initiatives; unused policy definition groups; one control under different group names; no category in the metadata                                                                                                                                                                                                         |
| Audience             | `Platform` (default, like AzPolicyLens's detailed wiki): everything, including `hidden-` metadata and tags. `Application` (its basic wiki): an application team's assignments, compliance and exemptions, without the unassigned definitions or metadata hygiene                                                                                             |

**Outputs**

- **Console view:** tiles, compliance by subscription and category, the
  assignments (least compliant first), the exemptions that need attention,
  and the High and Medium findings.
- **Objects:** `AAC.PolicyAssignmentReport`. Each has its `Compliance` (by
  subscription), `PolicyStates` and `Findings`.
- **`-CsvPath`:** one CSV per table.
- **`-HtmlPath`:** the management group hierarchy as a tree, with each
  level's compliance. The tables are grouped under Overview, Compliance,
  Exemptions and Definitions.
- **`-PdfPath`:** a PDF of the same content.

`Get-AACPolicyState` (every resource's state) and `Get-AACAssignedPolicy`
(every assignment's parameters) stay as they are.

### Assigned policies and their parameters

`Get-AACPolicyState` is about compliance; `Get-AACAssignedPolicy` is about
what is assigned. It reads the assignments, the definitions and initiatives
they assign and the initiatives' member policies with Azure Resource Graph -
a handful of queries however many assignments there are (Reader, no Az
modules) - and flattens them to one row per assignment and parameter:

```powershell
Get-AACAssignedPolicy                                                          # everything you can see
Get-AACAssignedPolicy -SubscriptionId '00000000-0000-0000-0000-000000000000'    # what applies to one subscription
Get-AACAssignedPolicy -ManagementGroupId 'mg-landingzones' -HtmlPath .\AssignedPolicy.html
Get-AACAssignedPolicy -NoDisplay | Where-Object ValueSource -EQ 'Assigned'      # the parameters set on the assignment
```

| Column                                                                     | What it is                                                                                                                                                                                                                                                                                                                                                                                                           |
| -------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `DefaultValue`, `AssignedValue`, `EffectiveValue`                          | The definition's default, the assignment's value, and the one that applies (assigned, else default). Lists are joined with `, `, objects written as compact JSON                                                                                                                                                                                                                                                     |
| `ValueSource`                                                              | `Assigned`, `Default` or `Not set`                                                                                                                                                                                                                                                                                                                                                                                   |
| `ResourceType`                                                             | What the policy targets: the types in its rule's `"field": "type"` conditions, with `[parameters()]` resolved to the effective values; else the types of the aliases it reads; else `All except ...` (a rule that only leaves types out, such as _Allowed resource types_) or `All`. For an initiative, the types of the member policies that use the row's parameter (`All` when one of them applies to every type) |
| `ScopeType`, `ScopeName`, `Inherited`                                      | Where it is assigned. With `-SubscriptionId` or `-ManagementGroupId`, assignments inherited from the management groups above are included and marked `Inherited`                                                                                                                                                                                                                                                     |
| `DefinitionType`, `PolicyType`, `Category`, `EnforcementMode`, `NotScopes` | Policy or initiative, built-in or custom, its category, whether it is enforced, and the scopes left out                                                                                                                                                                                                                                                                                                              |

A policy without parameters is one row with no parameter, so every
assignment is listed. The console view shows the assignments by scope, the
resource types with the most assignments, and each assignment's parameters
as a tree (assigned values in green, defaults in grey).

## VM size availability (virtual machines and AKS)

`Get-AACSkuAvailability` answers "can I use this VM size here?" before you
deploy: for virtual machines, or for AKS node pools. It only reads - Reader
is enough, and nothing is created - over REST:

| Read                                                                                                                                     | From                                          |
| ---------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| The sizes offered in the region, their zones and capabilities, and what's restricted for your subscription (the region, or single zones) | `Microsoft.Compute/skus`                      |
| Each family's and the region's vCPU quota                                                                                                | `Microsoft.Compute/locations/{region}/usages` |
| Which physical zone each logical zone is (it differs between subscriptions)                                                              | the subscription's locations                  |
| An AKS cluster's region and node pools (`-ClusterName`)                                                                                  | Azure Resource Graph                          |

```powershell
Get-AACSkuAvailability -Location uksouth -Zone 1, 2, 3 -Series D, E               # D and E series usable in all three zones
Get-AACSkuAvailability -ClusterName 'aks-contoso' -Zone 1, 2, 3 -NodeCount 3      # a new 3-node, 3-zone pool on a cluster
Get-AACSkuAvailability -Service Aks -Location uksouth, ukwest -Architecture Arm64 -HtmlPath .\Skus.html
Get-AACSkuAvailability -Location westeurope -Zone 1, 2, 3 -NoDisplay |
    Where-Object { $_.Status -eq 'Available' -and $_.vCPUs -eq 4 -and $_.MemoryGB -ge 16 }
```

Each size gets a **status**, the first that applies, with the reason:

| Status            | Why                                                                              |
| ----------------- | -------------------------------------------------------------------------------- |
| `Restricted`      | Not offered to your subscription in the region (`NotAvailableForSubscription`)   |
| `NotSupported`    | `-Service Aks` (or `-ClusterName`): fewer than 2 vCPUs, which AKS can't use      |
| `ZoneUnavailable` | None of the `-Zone` zones can host it (not offered there, or restricted for you) |
| `Partial`         | Some of the `-Zone` zones can't                                                  |
| `NoQuota`         | The family's or the region's free vCPUs are fewer than vCPUs x `-NodeCount`      |
| `Available`       | Nothing stops it                                                                 |

For AKS it also notes sizes with less than 4 GB (user node pools only) and
burstable B-series sizes (not recommended for system node pools). With
`-ClusterName` the region and subscription are the cluster's, the sizes its
node pools use are marked, and each pool is shown with its size's status now
and the family's free vCPUs - whether it can scale out.

Narrow the sizes with `-Series` (the letters of the name: `D`, `E`, `NC`,
`DC`; wildcards allowed), `-Sku` (`Standard_D4s_v5`, `D4s_v5` or `*s_v5`) and
`-Architecture x64|Arm64`. Each row (`AAC.SkuAvailability`) has the size's
vCPUs, memory, zones (and the ones missing), family and regional free vCPUs,
architecture, ephemeral OS disk, accelerated networking, premium storage,
Spot, GPUs, data disks and Hyper-V generations.

The console shows tiles, the zone mapping, the vCPU quota (most used first),
the cluster's node pools and each size, usable first. The HTML report has a
donut of the statuses and charts that filter tables of sizes, quota, zones and
node pools; the PDF has the same. `-CsvPath` writes every size.

What no read can tell you is whether there's capacity at the moment you
deploy (`ZonalAllocationFailed` and similar); nothing here deploys to find
out. More services (disks, storage, SQL, PostgreSQL and MySQL flexible
server, App Service) will follow the same pattern.

## Entra ID group membership

`Get-AACEntraGroupMembership` reads Entra ID groups and their members from
Microsoft Graph and follows nested groups to the end:

```powershell
Get-AACEntraGroupMembership -GroupName 'grp-finance', 'grp-hr'            # these groups, by exact name
Get-AACEntraGroupMembership -GroupNameStartsWith 'grp-azure-'             # every group whose name starts with this
Get-AACEntraGroupMembership                                                # every group in the tenant
Get-AACEntraGroupMembership -GroupNameStartsWith 'grp-' -HtmlPath .\Groups.html -CsvPath .\Groups.csv -PdfPath .\Groups.pdf
Get-AACEntraGroupMembership -GroupNameStartsWith 'grp-' -NoDisplay | Where-Object UserType -EQ 'Guest'   # the guests, and through which group
```

```text
grp-finance  Security - Cloud - 3 direct - 3 users
|-- Ada Lovelace  ada@contoso.example
|-- Gus Guest  gus_fabrikam.example#EXT#@contoso.example   GUEST
`-- GROUP grp-finance-emea
    |-- Grace Hopper  grace@contoso.example   DISABLED
    `-- Service principal app-payroll
```

**One row per group and member** (`AAC.EntraGroupMember`), the same in the
objects, HTML, PDF and `-CsvLayout Member` CSV: the group (name, type - Microsoft 365, Security,
Mail-enabled security, Distribution, dynamic, role-assignable - and whether
it's cloud or synced from on-premises AD), the member (name, type - user,
group, device, service principal, contact - user principal name, mail,
member or guest, enabled or disabled, job title, department), and how it's
in the group: **Direct**, **Nested** (with **Via**, the path of nested
groups, and the depth), or **Empty** for a group with no members, so every
group appears. A group met again on its own path (a loop) is listed but not
followed twice. The console and reports also show each group's totals:
direct members, nested groups, and unique users, guests and disabled
accounts at every level.

**The CSV** is one row per group by default - the same file
[Export-EntraGroupMemberShip.ps1](https://www.powershellgallery.com/packages/Export-EntraGroupMemberShip)
writes, with the same columns and labels: GroupName, GroupSource (Cloud or
Windows Server AD), GroupType (`Security`, `Microsoft 365 / Dynamic`,
`Mail-Enabled Security / Role-Assignable` ...), Members (the direct members,
groups marked `(Group)`, or `(No members)`) and NestedGroupMembers (each
nested group's own members: `grp-finance-emea: Grace Hopper, Ada Lovelace`).
A group whose members can't be read is left out of it, with a warning.
`-CsvLayout Member` writes the one-row-per-member rows instead.

**Sign-in.** It uses your `Connect-AAC` sign-in - no second prompt: a
Microsoft Graph token is taken from it silently, the way Application
Insights gets its Log Analytics token.

- Your account needs to be allowed to read groups in Entra ID, which members
  of the tenant are by default (guests, or tenants that restrict it, may
  not be).
- With an App Registration of your own (`Connect-AAC -ClientId`), give it
  Microsoft Graph's delegated **Group.Read.All** and **User.Read.All**
  permissions.
- Reads run 8 at a time, a level of nesting at a time, each group read
  once however many groups it's nested in; throttling waits as Graph asks.
  A group whose members can't be read is reported, and the rest carry on.

`-CsvPath` (alias `-OutputPath`) writes the rows; with no export parameter
the command shows the console view, as every command does.

## Network security groups

`Get-AACNetworkSecurityGroup` assesses network security groups the way an
auditor would. Without parameters it covers every NSG you can see.

```powershell
Get-AACNetworkSecurityGroup                                                  # every NSG
Get-AACNetworkSecurityGroup -SubscriptionId $sub -ResourceGroupName 'rg-network' -Name 'nsg-web', 'nsg-app'
Get-AACNetworkSecurityGroup -HtmlPath .\NSG.html -PdfPath .\NSG.pdf -CsvPath .\NSG-rules.csv
(Get-AACNetworkSecurityGroup -NoDisplay).Findings | Where-Object Severity -EQ 'High'
```

**What each NSG records**

| Area         | What's captured                                                                                                                                                                                                                        |
| ------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Metadata     | Name, resource ID, subscription, resource group, location, tags                                                                                                                                                                        |
| Associations | The subnets (VNet, prefix) and network interfaces (VM, private IP) it's applied to, and how many VMs it protects through either - charted as "VMs protected per NSG" to show how standard the perimeter is                             |
| Rules        | Every rule, custom and default, in the order Azure evaluates them: priority, direction, protocol, source, source port, destination, destination port and action. Application security groups are shown by name.                        |
| Telemetry    | Diagnostic settings (Log Analytics workspace, storage account, event hub; log categories), and flow logs with retention and Traffic Analytics. Either an NSG flow log or a virtual network flow log on its VNet, subnet or NIC counts. |

**Findings**, each with what to do:

| Severity | Finding                                                                                                                                                                                                                                         |
| -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| High     | An inbound Allow from `*`, `Internet` or `0.0.0.0/0` to every port, or to a management or database port (SSH, RDP, WinRM, SMB, SQL, Redis, …)                                                                                                   |
| Medium   | A wide port range open to the internet. An NSG on no subnet and no NIC. **A NIC NSG and its subnet's NSG that disagree:** Azure evaluates both, so if one allows what the other denies, the traffic is blocked. No flow log, or a disabled one. |
| Low      | ICMP from the internet. Everything allowed from the virtual network. **A shadowed rule:** an earlier rule covers it, so it never applies. Flow logs kept under 90 days. No diagnostic settings.                                                 |
| Info     | Flow logs without Traffic Analytics. Only an NSG flow log (NSG flow logs retire on 30 September 2027). Over 800 of the 1,000 rules an NSG can hold.                                                                                             |

**Output**

- **At the prompt:** tiles, the NSGs ordered by risk, the High and Medium
  findings, and, for up to three NSGs, each one in detail with its rules.
- **Objects:** `AAC.NetworkSecurityGroup`, carrying their rules, findings,
  associations and logging.
- **`-CsvPath`:** every rule, with its risk and finding.
- **`-HtmlPath`:** tables of NSGs, findings, rules, associations and logging,
  each with a CSV download.
- **`-PdfPath`:** a summary, the findings, and a page per NSG with its rules.
- **`-NoDiagnosticSetting`:** skips the diagnostic-settings calls (one per
  NSG).

## Virtual network assessment

`Invoke-AACVirtualNetworkAssessment` assesses virtual networks - every one you
can see, or those you name - from Azure Resource Graph, read-only:

```powershell
Invoke-AACVirtualNetworkAssessment                                                          # every network
Invoke-AACVirtualNetworkAssessment -SubscriptionId $sub -Name 'vnet-hub-*', 'vnet-spoke-app'  # some, in detail
Invoke-AACVirtualNetworkAssessment -ManagementGroupId 'mg-landingzones' -HtmlPath .\VNet.html -PdfPath .\VNet.pdf -CsvPath .\Subnets.csv
(Invoke-AACVirtualNetworkAssessment -NoDisplay).Subnets | Where-Object UsedPercent -GE 80    # running out of IPs
Invoke-AACVirtualNetworkAssessment -Name 'vnet-spoke-app' -NoDisplay | Select-Object -ExpandProperty FreeRangeList  # where a subnet fits
```

| Area                  | What's captured                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Metadata              | Name, role (hub, spoke, peered, standalone), location, resource group, subscription, tags, flow timeout, BGP community                                                                                                                                                                                                                                                                                                                                                                    |
| Address space and IPs | The prefixes; total IPs, IPs in subnets and unallocated; usable (Azure keeps 5 per subnet), used and available; **the free CIDR blocks a new subnet can take**; overlaps with any other network you can see                                                                                                                                                                                                                                                                               |
| Subnets               | Prefix, usable / used / available IPs and % used, purpose (gateway, firewall, Bastion, Route Server, delegated, private endpoints), NSG, route table and its default route, BGP propagation, NAT gateway, **the outbound path** (NAT gateway, firewall or NVA, forced tunnelling, public IPs, private subnet, default outbound access), service endpoints and policies, delegations, private endpoints and their network policies, NICs, VMs, public-IP and IP-forwarding NICs, flow logs |
| Peerings              | State, sync, remote network / subscription / region, global, the allow flags, gateway transit, remote address space, subnet peering, whether the remote side peers back                                                                                                                                                                                                                                                                                                                   |
| Security              | DNS servers and linked private DNS zones, DNS resolvers, DDoS protection, virtual network encryption, flow logs, gateways, Azure Firewall, Bastion, private endpoints (connection, DNS zone), application security groups (members, the NSG rules naming them), and the NSGs on the subnets, assessed rule by rule as `Get-AACNetworkSecurityGroup` does                                                                                                                                  |

**Findings**, each with what to do:

| Severity | Finding                                                                                                                                                                                                                                                                                                                                                                                                                       |
| -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| High     | A full subnet (or 95% used). A peering not Connected. An NSG, or a 0.0.0.0/0 route, on GatewaySubnet. AzureBastionSubnet, AzureFirewallSubnet or RouteServerSubnet too small. An NSG rule open to the internet on a management or database port.                                                                                                                                                                              |
| Medium   | A subnet 80% used. A peering out of sync. Workloads in a subnet with no NSG. VMs with public IPs. **Default outbound access** (being retired - use a NAT gateway or a firewall). Public IPs without DDoS Network Protection. No virtual network flow logs. Private endpoints whose privatelink zone isn't linked (with Azure DNS). Private endpoint connections not approved. A Basic VPN gateway. A GatewaySubnet under /27. |
| Low      | Oversized or empty subnets. No free address space. Overlapping address spaces. Encryption off. A single DNS server. Private endpoint network policies off. IP forwarding with no route to it. Empty or unused ASGs. Gateways that aren't zone-redundant.                                                                                                                                                                      |
| Info     | Global peering (charged per GB). A remote network you can't read. No Bastion where VMs have public IPs.                                                                                                                                                                                                                                                                                                                       |

**Output**

- **At the prompt:** tiles, the networks with their IP capacity and risk, the
  fullest subnets, the High and Medium findings, and, for up to three networks,
  each in detail with its subnets, peerings and free ranges.
- **Objects:** `AAC.VirtualNetwork`, each with its `Subnets`, `Peerings`,
  `FreeRangeList`, `PrivateEndpointList` and `Findings`.
- **`-CsvPath`:** every subnet.
- **`-HtmlPath`:** tables of networks, findings, subnets, peerings, free ranges,
  private endpoints, ASGs and NSG rules, each collapsible and downloadable as CSV.
- **`-PdfPath`:** a summary, the findings, and a section (and bookmark) per network.

The networks' NICs, NSGs, route tables, endpoints and gateways are read in
their subscriptions; every network and private DNS zone link you can see is
read too, for remote peerings, overlaps and zones linked from a hub. Used IPs
are the IP configurations in a subnet; a delegated service may hold more than
it shows.

## AKS cluster assessment

`Invoke-AACAksAssessment` assesses AKS clusters through every lens - every
cluster you can see, or those you name - read-only, with no Az modules and no
kubectl:

```powershell
Invoke-AACAksAssessment                                                  # every cluster
Invoke-AACAksAssessment -Name 'aks-prod-*' -HtmlPath .\AKS.html -PdfPath .\AKS.pdf -CsvPath .\aks
Invoke-AACAksAssessment -ManagementGroupId 'mg-landingzones' -IncludeConstraint   # with Gatekeeper's complete counts
(Invoke-AACAksAssessment -NoDisplay).Checks | Where-Object { $_.Status -eq 'Fail' -and $_.Pillar -eq 'Security' }
```

| Lens              | What it covers                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| ----------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Current settings  | Every setting that matters, by area - general (version, tier, support plan, power state), upgrades (channels, maintenance windows), identity and access (Entra ID, Azure RBAC, local accounts, workload identity), networking (plugin, dataplane, network policy, outbound, CIDRs, private cluster, authorized ranges), security (Defender, Azure Policy, KMS, image cleaner, Key Vault provider, node resource group lockdown), monitoring (Container insights, Prometheus, cost analysis, diagnostic settings), add-ons and the autoscaler profile - and every node pool: size, mode, OS, nodes, autoscale, zones, max pods, versions, node image and its age, disks, Spot, subnet, taints                                                                                |
| Well-Architected  | About 35 checks across the five pillars, Pass or Fail, with a score per pillar: Reliability (SLA tier, zones, system pool, Spot, version support, maintenance window, surge), Security (local accounts, Entra ID, Azure RBAC, API server exposure, network policy, Azure Policy, Defender, workload identity, pod identity, image cleaner, KMS, node public IPs, encryption at host, managed identity, node image age, lockdown), Operational Excellence (upgrade channels, Container insights, Prometheus, kube-audit logs, version drift, retired add-ons), Cost Optimization (autoscaler, cost analysis), Performance Efficiency (ephemeral OS disks, kubenet, load balancer SKU, **subnet IPs at full scale** - max nodes and surge, a pod IP each with flat Azure CNI) |
| PSRule for Azure  | The `Azure.AKS.*` rules on each cluster as `Export-AzRuleData` reads it (`-Baseline`, `-ExcludeRule`; `-SkipPSRule` to leave out)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| Azure Policy      | The [AKS Policy Compliance Toolkit](https://github.com/sam-cogan/aks-policy-compliance-toolkit)'s consolidated view: every non-compliant pod, service or network policy with its **namespace, workload** (inferred from the pod's name: Deployment, CronJob, StatefulSet, DaemonSet / Job), **policy, effect** (audit when the assignment doesn't enforce) and **cluster** - and rolled up by each of them; the policies evaluated on each cluster resource; the assignments. System namespaces are left out unless `-IncludeSystemNamespace`                                                                                                                                                                                                                               |
| Gatekeeper        | With `-IncludeConstraint`: each constraint's complete violation count from inside the cluster - Azure Policy keeps 500 records per policy and cluster - through AKS run command (needs the `runCommand/action` permission; it starts a short-lived pod in `aks-command`)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| Versions          | The control plane's version and its support in the region (supported, long-term support, out of support), the upgrades available, how far behind the newest it is; each pool's version, node image and the newest node image                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| Advisor, Defender | The clusters' Advisor recommendations and retirements, and Defender for Cloud's unhealthy assessments                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |

Every failed check and rule, recommendation and policy finding is a finding,
with its severity, pillar, source and what to do.

**Output**

- **At the prompt:** tiles, the clusters with their WAF score per pillar, the
  pillars, the High and Medium findings, policy violations by namespace, and -
  for up to three clusters - their node pools and failed checks.
- **Objects:** `AAC.AksCluster`, each with its `NodePools`, `Settings`, `Checks`,
  `Findings`, `Upgrades`, `PolicyViolations` and `PSRule`.
- **`-CsvPath`** (a folder): a CSV per table, and `policy-namespaces\<namespace>.csv` -
  each namespace's non-compliant workloads, to hand to the team that owns it.
- **`-HtmlPath`:** every table under its lens (Overview, Current settings,
  Well-Architected, PSRule for Azure, Azure Policy), collapsible, each with a CSV download.
- **`-PdfPath`:** the summary, the findings, Azure Policy, and a section per cluster.

## Storage container sizes

`Get-AACStorageAccountContainerSize` adds up every blob in every container
of your storage accounts. It finds the accounts with Azure Resource Graph,
lists their containers through Azure Resource Manager (Reader is enough),
then lists the blobs from the blob service itself:

```powershell
Get-AACStorageAccountContainerSize                                                  # every account you can see
Get-AACStorageAccountContainerSize -StorageAccountName 'stlogs*' -ContainerName 'insights-*'
Get-AACStorageAccountContainerSize -AuthMode Auto -IncludeSnapshot -IncludeVersion -HtmlPath .\Storage.html
Get-AACStorageAccountContainerSize -StorageAccountName 'stbackup01' -BlobCsvPath .\Blobs.csv  # every blob, to CSV
Get-AACStorageAccountContainerSize -NoDisplay | Sort-Object Size -Descending | Select-Object -First 10
```

**Built for large estates.** The containers are read side by side, 16 at a
time by default (`-ThrottleLimit`, up to 64), over the module's pooled HTTPS
connections; each container's pages of 5,000 blobs follow each other. Each
page is read by a small parser compiled on first use (C#, through Add-Type:
about 275,000 blobs a second, no XML document) and added up as it arrives,
so memory stays flat however many blobs there are - unless `-IncludeBlob`
or `-BlobCsvPath` keep every one (a few hundred bytes a blob). Throttling is
retried as Azure Storage asks. The view ends with how many blobs were read a
second.

**Reading blobs needs data access**, which Reader alone doesn't give:

| `-AuthMode`         | Reads with                                                                                                                          | You need                                                                                                                       |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `EntraId` (default) | your `Connect-AAC` sign-in, with a token for Azure Storage                                                                          | Storage Blob Data Reader (or Contributor or Owner) on the account, resource group or subscription                              |
| `AccountSas`        | a read-and-list account SAS for the blob service, valid for 4 hours, from `listAccountSas` - kept in memory, never shown or written | permission to list the account's keys (Contributor, Storage Account Contributor), and shared key access allowed on the account |
| `Auto`              | Entra ID, then an account SAS for the accounts that refuse Entra ID for want of a data role                                         | either                                                                                                                         |

Accounts behind a firewall or private endpoint can be read only from a
network they allow. Whatever can't be read is listed with Azure Storage's
reason and what to do about it.

One row per container (`AAC.StorageContainerSize`): blobs, size and size per
tier (Hot, Cool, Cold, Archive, and no tier for page, append and premium
blobs), snapshots, previous versions and soft-deleted blobs with their
sizes (`-IncludeSnapshot`, `-IncludeVersion`, `-IncludeDeleted`), Data Lake
directories, the newest change, public access, status and error, and the
`-Top` largest blobs (10). The console view: tiles, the size by access tier,
the largest containers, every subscription, account and container as a tree
with a size bar coloured by its main tier, the largest blobs, and what
couldn't be read. `-HtmlPath` writes tables of the accounts, containers and
largest blobs with charts that filter them; `-CsvPath` the containers,
`-BlobCsvPath` every blob.

## Terraform plans

`Get-AACTerraformPlan` reads a whole Terraform plan - every resource
change, the outputs and the drift - and flattens it so you can see what
changes before you apply it. It works offline: no Azure sign-in, and no
Terraform on the machine that reads it.

```powershell
terraform plan -out tfplan
terraform show -json tfplan > plan.json

Get-AACTerraformPlan -Path .\plan.json                                    # the view
Get-AACTerraformPlan -Path .\plan.json -Action Delete, Replace -NoDisplay # what is destroyed, and why
Get-AACTerraformPlan -Path .\plan.json -ExpandAttribute -NoDisplay | Where-Object ForcesReplacement
Get-AACTerraformPlan -Path .\plan.json -HtmlPath .\Plan.html -CsvPath .\Plan.csv -ExpandAttribute
```

One row per resource (`AAC.TerraformChange`): the action (Create, Update,
Replace, Delete, Read, Import, Move, Forget), the address and module, the
Azure name, resource group, location and ID, why it's replaced or deleted,
the attributes that force a replacement, and the attributes that change.
`-ExpandAttribute` gives one row per attribute instead
(`AAC.TerraformAttributeChange`), with its before and after value. Nested
values are flattened to a path - `tags["cost.centre"]`,
`site_config[0].always_on`, `security_rule[name=ssh].access`, and
`policy_rule{json}.then.effect` inside a JSON-encoded string. Blocks in a
list are matched by content, then by name, so a rule added to an NSG
doesn't show every rule after it as changed.

The plan JSON holds sensitive values in clear text. They are never shown,
returned or written: they read `(sensitive)`. The view opens with
Terraform's own summary line (`Plan: 2 to add, 5 to change, 2 to destroy.`),
then a table per action - deletes and replacements first - with each
resource's attribute changes as `+`, `-` and `~` lines, the outputs, and what
changed outside Terraform. `-HtmlPath` writes tables of the resources, every
attribute change, the outputs and the drift, with tiles and charts that
filter them.

## Resource map

`Show-AACResourceMap` draws the resources in one or more resource groups, in
one or more subscriptions, and opens the map in your browser:

```powershell
Show-AACResourceMap -SubscriptionId '00000000-0000-0000-0000-000000000000' -ResourceGroupName 'rg-app'
Show-AACResourceMap -SubscriptionId $hub, $spoke -ResourceGroupName 'rg-hub', 'rg-spoke-app' -Direction TopToBottom
Show-AACResourceMap -ResourceGroupName 'rg-app' -Theme Light -HtmlPath .\rg-app-map.html -NoBrowser
```

**What's drawn.** Each resource appears with its official Azure icon, its
name, its product, and a useful detail such as a VM's size, an IP address or
a disk's size.

- **Boxes.** Resources sit in boxes: subscription, then resource group, then
  virtual network, then subnet.
- **Subnet placement.** A resource with an IP in a subnet is drawn in that
  subnet: a NIC, private endpoint, firewall, gateway, Bastion, internal load
  balancer, AKS or API Management. A VM is drawn in the subnet of its NIC.
- **Subnet labels.** Each subnet's box shows its address prefix, how many of
  its addresses are in use (`3 of 251 IPs used`; Azure keeps 5 in every
  subnet) and what it's delegated to.

**The connections** come from the resource IDs in each resource's properties,
each drawn in its own style:

| Connection          | For example                                                                                          |
| ------------------- | ---------------------------------------------------------------------------------------------------- |
| Network association | A VM and its NIC, a NIC and its public IP, a subnet and its NSG, VNet integration                    |
| Resource dependency | An app on its plan, a VM on its disks, a database on its server                                      |
| VNet peering        | Two networks, with the peering state                                                                 |
| Private link        | A private endpoint and the resource it serves                                                        |
| Route (next hop)    | A route table and the firewall or appliance its routes send traffic to, e.g. `0.0.0.0/0 -> 10.0.1.4` |
| Private DNS link    | A private DNS zone and the networks it's linked to                                                   |

**NSGs and route tables** are drawn the way a network engineer reads them:
as **chips** on the subnets and NICs they're applied to, not as boxes with
long lines. An NSG shared by three subnets shows on all three.

- **Click a chip** for its rules or routes.
  - **An NSG** shows its inbound and outbound rules by priority, with
    application security groups by name and the default rules folded away.
  - **A route table** shows each route with its next hop resolved to the
    resource that owns the IP, e.g. `10.0.1.4 -> afw-hub`, and whether
    gateway route propagation is off.
- **Routes from the subnet:** a subnet's routes are drawn from the subnet
  itself to the firewall or appliance they go through, e.g. `0.0.0.0/0 via
rt-spoke`. The next hop is looked up in every subscription you can see, so
  a spoke's map reaches the hub's firewall.
- **Chip colours** flag what deserves a look:

| Colour                | NSG                                                                                                                                                                                                      | Route table                                                                |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| Red: high risk        | Allows every port, or a management or database port (SSH, RDP, WinRM, SMB, Telnet, FTP, SQL, MySQL, PostgreSQL, Oracle, MongoDB, Redis, Elasticsearch), from the internet (`*`, `Internet`, `0.0.0.0/0`) | A next-hop IP that no resource you can see has: the traffic may be dropped |
| Amber: worth a review | Allows a wide port range (over 100 ports) from the internet                                                                                                                                              | `0.0.0.0/0` straight to the internet, around any firewall                  |

A legend switch shows only what's flagged, and another draws NSGs and route
tables as **cards** with lines instead (`-NsgView Cards` starts that way).
Each peering says what it lets through: forwarded traffic, gateway transit,
remote gateway.

**Beyond the selection.**

- **Outside the selection:** a resource outside the chosen resource groups
  that a chosen one uses is drawn too, in its own resource group's box, marked
  as outside the selection. A typical case is the hub's VNet for a spoke.
- **Unattached:** resources attached to nothing are flagged in amber. That
  covers a NIC without a VM, a public IP without a configuration, an
  unattached disk, or an NSG or route table on nothing.

**In the browser:**

- pan and zoom;
- click a resource to light up its connections and see its details, with a
  link to the Azure portal;
- search;
- switch left-to-right or top-to-bottom, and the Dark, Light and Blueprint
  themes;
- hide a kind of connection;
- **Save PNG** or **Save JPEG**, at twice the screen's resolution, or SVG.

The page is one self-contained file that opens offline. Its layout comes from
the [Eclipse Layout Kernel](https://eclipse.dev/elk/) (`elkjs`, EPL-2.0), and
it uses Microsoft's
[Azure architecture icons](https://learn.microsoft.com/azure/architecture/icons/),
under Microsoft's terms for architecture diagrams. `-PassThru` also returns
the map's resources and connections as objects, e.g. `(... -PassThru).Nodes |
Where-Object Orphan`.

## PSRule for Azure

`Invoke-AACPSRule` checks your live estate with
[PSRule for Azure](https://azure.github.io/PSRule.Rules.Azure/): its 500+
rules, following the Azure Well-Architected Framework, on every resource,
resource group and subscription you can see. The module's own rules and your
custom rules run alongside them.

```powershell
Connect-AAC
Invoke-AACPSRule                                                  # the console view
Invoke-AACPSRule -SubscriptionId '00000000-0000-0000-0000-000000000000' -HtmlPath .\PSRule.html
Invoke-AACPSRule -CsvPath .\PSRule.csv -PdfPath .\PSRule.pdf -FailedOnly
Invoke-AACPSRule -Rule 'Azure.Storage.*', 'Azure.KeyVault.*'      # only these rules
Invoke-AACPSRule -ExcludeRule 'Azure.Resource.UseTags', 'AAC.*'    # leave these out
Invoke-AACPSRule -Baseline 'Azure.Pillar.Security'                 # a PSRule for Azure baseline
Invoke-AACPSRule -FailedOnly | Group-Object RuleName | Sort-Object Count -Descending
```

The console view has tiles for objects checked, rules, passed, failed,
"could not evaluate" and pass rate. A bar chart shows the failures by pillar.
Then each pillar gets a table of its failing rules, most severe first, with
the resources each one failed on and why. The HTML report opens on the
failures, grouped by rule, with portal and rule documentation links. The PDF
lists every failing resource under its rule, with the rule's recommendation.

### The rules

| Source              | Rules                                                                                          |                                                                                                                                                                                                                       |
| ------------------- | ---------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| PSRule for Azure    | Every rule of the installed PSRule.Rules.Azure                                                 | `-Baseline` picks one of its baselines                                                                                                                                                                                |
| Azure.Admin.Console | `AAC.Resource.RequiredTags`, `AAC.ResourceGroup.RequiredTags`, `AAC.Resource.AllowedTagValues` | Check the tags named in `Get-AACTagDefault` (`PSRule\Rules\AAC.Tags.Rule.ps1`, empty as shipped) or in `AAC_REQUIRED_TAGS` / `AAC_ALLOWED_TAG_VALUES`; with no tags named they check nothing, and the command says so |
| Azure.Admin.Console | `AAC.Resource.Naming`                                                                          | On by default: the Cloud Adoption Framework abbreviations (`rg-`, `vnet-`, `kv-`, `st...`), or your own with `AAC_NAMING_PATTERNS`                                                                                    |
| Custom              | Your own rule files, from `-RulePath`                                                          | `*.Rule.ps1`, `*.Rule.yaml` or `*.Rule.jsonc`                                                                                                                                                                         |

`-Rule` runs only the rules named, and `-ExcludeRule` leaves rules out. Both
take names or wildcards. `-Configuration` passes settings to every rule:
PSRule for Azure's
[options](https://azure.github.io/PSRule.Rules.Azure/setup/configuring-options/),
the module's `AAC_*` settings, or your rules' own.

```powershell
Invoke-AACPSRule -Configuration @{
    AAC_REQUIRED_TAGS                = @('Owner', 'CostCenter', 'Environment')
    AAC_ALLOWED_TAG_VALUES           = @{ Environment = @('prod', 'test', 'dev') }
    AZURE_RESOURCE_ALLOWED_LOCATIONS = @('uksouth', 'ukwest')
}
```

**Insights** (`-Insight`) add what the estate is made of and what needs
attention, from the same parallel Resource Graph read (about 11 more
queries):

|                     |                                                                                                                                                                                                                                                                                                                                                |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Mix**             | VM sizes, operating systems (Windows Server 2022, Ubuntu 22.04, ... - from the VM's instance view, or its image), VM power states, Azure VMs and Azure Arc servers, storage account replication, database tiers (Azure SQL DTU / vCore / serverless, Cosmos DB, PostgreSQL, MySQL), tag coverage                                               |
| **Needs attention** | Unattached disks (with their size), unused public IPs and NICs, VMs **stopped but still billed** (stopped in the OS, not deallocated), disconnected Arc servers, classic resources (retired), subnets 80% full or more, VPN and ExpressRoute connections down, empty resource groups - each with its cost this month when `-Cost` is given too |
| **Network**         | Every subnet's used and usable IPs (Azure keeps 5 per subnet), and the VPN and ExpressRoute connections with their status                                                                                                                                                                                                                      |

The console shows them as proportion charts and a table; the HTML report as
donut charts that filter a machines table, and tables of what needs
attention, subnets and connections; the PDF as a page of its own.

**Tags.** The tag rules check the tags you name. Name them for one run with
`-Configuration`, or for every run in `Get-AACTagDefault` in
`PSRule\Rules\AAC.Tags.Rule.ps1`:

```powershell
function global:Get-AACTagDefault {
    @{
        RequiredTags  = @('Owner', 'CostCenter', 'Environment')
        AllowedValues = @{ Environment = @('prod', 'test', 'dev') }
    }
}
```

`-Configuration` wins over the defaults. When a tag rule you asked for has
no tags to check, the view (and `-HtmlPath`, or a warning with `-NoDisplay`)
says so instead of leaving it out silently.

**Naming conventions.** `AAC.Resource.Naming` checks the names of resource
groups and about 30 common resource types against Microsoft's
[Cloud Adoption Framework abbreviations](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations),
with no setting needed. Run on its own, it reads only the types it checks and
no child settings: a few Resource Graph queries, however large the estate.
Names Azure creates and manages (`MC_*`, `NetworkWatcherRG`, ...) are skipped.

```powershell
Invoke-AACPSRule -Rule 'AAC.Resource.Naming'                       # the defaults
Invoke-AACPSRule -Rule 'AAC.Resource.Naming' -Configuration @{
    AAC_NAMING_PATTERNS = @{ 'Microsoft.Compute/virtualMachines' = '^vm-(prod|test|dev)-'; 'Microsoft.Web/sites' = '' }   # '' = don't check
    AAC_NAMING_IGNORE   = @('^legacy-')
}
```

To change the defaults for everyone who uses your copy of the module, edit
the table in `PSRule\Rules\AAC.Naming.Rule.ps1` (`Get-AACNamingDefault`), one
line per type. To keep your own convention without editing the module, set
it once in your profile:
`$PSDefaultParameterValues['Invoke-AACPSRule:Configuration'] = @{ AAC_NAMING_PATTERNS = @{ ... } }`.

`-Rule` takes rule names, not files: the module's rules always load, and
`-RulePath` adds rule files of your own. A `-Rule` that matches no rule is an
error rather than an empty result.

### Your own rules

Write rules the way PSRule does:
[PowerShell, YAML or JSON](https://microsoft.github.io/PSRule/v2/authoring/writing-rules/).
Then pass the file or folder to `-RulePath`. PSRule for Azure's binding
applies to them too, so `-Type 'Microsoft.Storage/storageAccounts'` works. A
`# Synopsis:` comment names the rule, and an `Azure.WAF/pillar` tag places it
in a pillar. A help file in `en\<rule name>.md` next to it adds the severity,
recommendation and documentation link. See `PSRule\Rules` for examples.

```powershell
# .\MyRules\Contoso.Storage.Rule.ps1
# Synopsis: Storage accounts use the Contoso naming convention.
Rule 'Contoso.Storage.Name' -Type 'Microsoft.Storage/storageAccounts' -Tag @{ 'Azure.WAF/pillar' = 'Operational Excellence' } {
    $Assert.Match($TargetObject, 'name', '^stcontoso')
}
```

```powershell
Invoke-AACPSRule -RulePath .\MyRules -Rule 'Contoso.*'
```

### How it reads the estate

PSRule for Azure normally reads its data from `Export-AzRuleData`, which
needs the Az modules. This reads the same data with the `Connect-AAC`
sign-in instead:

- Resource Graph returns every resource with its properties, plus the
  resource groups and subscriptions.
- Azure Resource Manager provides the child settings PSRule's rules look at,
  such as storage blob services and containers, SQL auditing and firewall
  rules, Key Vault diagnostic settings, App Service config, and API
  Management APIs, products and policies. It reads the same children, with
  the same API versions, as `Export-AzRuleData` (PSRule.Rules.Azure v1.47).

When only the module's `AAC.*` rules run, the child settings aren't read:
those rules look only at names, types and tags. `-NoExpand` does the same for
your own rules that need nothing more.

Reader access is enough. When a setting can't be read, the command warns and
names it, because the rules using it may be wrong for that resource. VPN
connection shared keys are masked before PSRule sees them. A rule that can't
evaluate a resource is reported as "could not evaluate" for that resource,
and every other rule still runs. PSRule runs in a `pwsh` process of its own,
so its `YamlDotNet.dll` never clashes with the different versions that
platyPS, powershell-yaml or Az.Aks may have loaded into your session.

## Application Insights

`Invoke-AACApplicationInsightQuery` reads your application's exceptions, or
runs any KQL query. It works against a Log Analytics workspace
(`-LogWorkspaceName`, for workspace-based Application Insights, table
`AppExceptions`) or an Application Insights resource
(`-ApplicationInsightsName`, classic tables such as `exceptions`). The
resource is found by name with Resource Graph. The query runs through the Log
Analytics or Application Insights query API (`api.loganalytics.azure.com`,
`api.applicationinsights.io`). The token for that API comes from the
`Connect-AAC` sign-in, so there's no second sign-in and no Az module. It needs
Log Analytics Reader (or Reader). With an App Registration of your own
(`Connect-AAC -ClientId`), give it the delegated **Data.Read** permission of
the Log Analytics API and the Application Insights API.

A workspace only holds the exceptions of the Application Insights resources
that send to it. When a workspace has no exceptions, a warning says which
resources send there. If none do, it lists the ones you can see, where each
sends its data, and the `-ApplicationInsightsName` command to query one
directly. The portal's `exceptions | limit 5` runs in an Application Insights
resource, so it can show data that isn't in the workspace you queried.

```powershell
Invoke-AACApplicationInsightQuery -SubscriptionId '00000000-0000-0000-0000-000000000000' -LogWorkspaceName 'law-contoso-prod'
Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-contoso-prod' -Last 1d -MinimumSeverity Error -AppRoleName 'orders-api'
Invoke-AACApplicationInsightQuery -ApplicationInsightsName 'appi-contoso-portal' -ExceptionType '*SqlException' -Search 'timeout'
Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-contoso-prod' -Last 7d -HtmlPath .\Exceptions.html
Invoke-AACApplicationInsightQuery -ApplicationInsightsName 'appi-contoso-portal' -TableName requests -Last 15d
Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-contoso-prod' -TableName traces -MinimumSeverity Warning
Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-contoso-prod' -Query 'AppRequests | where Success == false | summarize count() by Name'
```

| Parameter          | Default      |                                                                                                                                                                                                                                                                 |
| ------------------ | ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-TableName`       | `exceptions` | The table to read: `requests`, `dependencies`, `traces`, `customEvents`, `pageViews`, `availabilityResults` and so on. Either schema's name works for either source (`requests` or `AppRequests`), and Tab completes them. A workspace's other tables work too. |
| `-Last`            | `2h`         | How far back: `30m`, `2h`, `7d` and so on. It also bounds `-Query`.                                                                                                                                                                                             |
| `-MinimumSeverity` | all          | `Verbose`, `Information`, `Warning`, `Error` or `Critical`, and worse. For exceptions and traces.                                                                                                                                                               |
| `-ExceptionType`   | all          | Exception types; wildcards work (`'*SqlException'`). For exceptions.                                                                                                                                                                                            |
| `-AppRoleName`     | all          | Apps or cloud roles.                                                                                                                                                                                                                                            |
| `-Search`          | none         | Text in the type or messages; with `-TableName`, in any column.                                                                                                                                                                                                 |
| `-Top`             | all          | The newest this many. By default every row in the period is read, up to the query API's limit of 500,000, and the view pages through them all.                                                                                                                  |
| `-Query`           |              | Any KQL instead of the exceptions query; its columns become the objects' properties.                                                                                                                                                                            |

The values you give are escaped before they go into the KQL.

Each exception is flattened into one object, the same from either table:

- **When and how bad:** time (UTC) and severity.
- **What:** type and message, plus the outer and innermost exception.
- **The `details` array:** the first entry's type, message and severity
  level, the number of entries, and the top stack frame (method, file and
  line).
- **Where it came from:** method, assembly, problem ID, operation name and
  ID, app/role, role instance, app version, client country and city.
- **Sampling and extras:** item count (for sampled telemetry) and custom
  properties.

The console view has tiles, a timeline of exceptions, a severity breakdown,
the top exception types, the top problems (a type thrown from one place) and
every exception, newest first. `-CsvPath` and `-HtmlPath` export them. With
`-TableName`, the view is a table of every row, with the table's most useful
columns first, for example time, name, result code, success and duration for
`requests`. The objects have all the columns.

If the table doesn't exist, the error panel says so and names the tables the
source does have. The closest names come first, then how many rows each has
in the period:

```text
There is no table 'request' in appi-contoso-portal.
Fix  Did you mean 'requests'? Tables in appi-contoso-portal with data in the
     last 15d: dependencies (40,211), requests (18,204), traces (9,120),
     exceptions (57). No data: availabilityResults, customEvents, ...
```

## Deploying a storage account

`Deploy-AACStorageAccount` creates or updates a storage account and what's in
it - idempotently, like a Bicep or Terraform deployment, but with the Azure REST
APIs directly: no ARM, Bicep or Terraform template. It is the module's only
command that writes; everything else reads.

```powershell
# The plan and the gates - nothing is written
Deploy-AACStorageAccount -SubscriptionId <subscription> -ResourceGroupName rg-data -ConfigurationPath .\Examples\storage-account.psd1 -WhatIf

# Plan, gates, ask, apply, verify. Run it again: "No changes", nothing written.
Deploy-AACStorageAccount -SubscriptionId <subscription> -ResourceGroupName rg-data -ConfigurationPath .\Examples\storage-account.psd1

# Quick: a name, two containers and a file - AVM's defaults for the rest
Deploy-AACStorageAccount -SubscriptionId <subscription> -ResourceGroupName rg-data -Name stcontosoweb -Container web, logs -Blob @{ container = 'web'; path = '.\index.html'; contentType = 'text/html' } -Setting @{ networkAcls = @{ ipRules = @('203.0.113.10') } }

# A failing PSRule rule blocks: deploy with the suggested fixes instead (checked again)
Deploy-AACStorageAccount -SubscriptionId <subscription> -ResourceGroupName rg-data -Name stcontosoweb -Container web -UseSuggestedFix -WhatIf

# In a pipeline: apply without asking unless a gate blocks, keep the plan
Deploy-AACStorageAccount -SubscriptionId <subscription> -ResourceGroupName rg-data -ConfigurationPath .\Examples\storage-account.parameters.json -Force -PlanPath .\plan.json
```

**The configuration** uses the [Azure Verified Module](https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/storage/storage-account)'s
parameter names, in a `.psd1` or `.json` file - an AVM parameters file works as
it is - and/or as parameters (`-Name`, `-Container`, `-FileShare`, `-Queue`,
`-Table`, `-Blob`, `-Tag`, `-Setting` for the rest). AVM's defaults apply, and,
as with Bicep, are enforced on every run: StorageV2, Standard_GRS, Hot, TLS 1.2,
HTTPS only, no public blob access, infrastructure encryption, network rules
that deny by default (with the AzureServices bypass), blob and container soft
delete. AVM parameters it doesn't support yet (customer-managed keys,
identities, local users, object replication...) are refused by name rather
than ignored. See `Examples\`.

**How it stays idempotent without a template:**

| Step   | What happens                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Plan   | Everything that should exist is read (GET) and compared property by property, only on what the configuration manages. Azure's own fields (a rule's state, a category's retention policy) and what it leaves out (false values) aren't changes. Each resource is Create, Update, No change, **Replace** (a property Azure can't change in place: location, kind, hierarchical namespace, infrastructure encryption, zonal or Premium redundancy) or **Drift** (containers, shares, queues, tables that exist but aren't configured - left alone, or deleted with `-Prune`) |
| Gates  | **Name** (`checkNameAvailability`); **Azure Policy**: the assignments that apply to storage in the resource group, and Azure Policy's verdict on the exact body of every write (`checkPolicyRestrictions`) - Deny blocks, Audit is reported, Modify and Append changes are shown; **PSRule for Azure** - and the module's naming and tag rules - on the account as it will be, with its services and containers (shift left)                                                                                                                                              |
| Decide | Blocked stops before anything is written: a name taken, an immutable change, a policy Deny, **a PSRule rule that fails** (or PSRule not running), `-FailOn Audit`/`Drift`. Otherwise it asks (`-Force` or `-Confirm:$false` in a pipeline); `-WhatIf` stops after the plan                                                                                                                                                                                                                                                                                                |
| Apply  | In dependency order - account, services, containers and the rest, private endpoints, diagnostic settings, role assignments, the lock last, blobs. PUT to create; PATCH with only what changed; long-running operations followed. Role assignments are named from scope, principal and role (like Bicep's `guid()`), and an existing one is adopted, so none is duplicated. Blobs upload only when their MD5 differs                                                                                                                                                       |
| Verify | Everything read and compared again: it must now plan no changes. What Azure changed by itself (a Modify policy) is reported                                                                                                                                                                                                                                                                                                                                                                                                                                               |

**A failing PSRule rule blocks the deployment, and says how to fix it.** Each
failing rule comes with its fix: the setting and value in the configuration
(`allowSharedKeyAccess = $false`, `networkAcls.defaultAction = 'Deny'`, a GRS or
GZRS SKU, soft delete, a container's `publicAccess = 'None'`...) - or, when no
setting can fix it, what to do (Defender for Storage on the subscription, tags
only you can give, a name that can't change). The view gathers every setting
into a configuration snippet to paste; `-UseSuggestedFix` deploys with them -
the plan and every gate are checked again on the fixed configuration. A rule
that doesn't apply to an account is excluded on purpose with `-ExcludeRule`;
`-SkipPSRule` deploys without checking. With AVM's defaults alone, two rules
fail - `Azure.Storage.LocalAuth` (AVM leaves shared key access on) and
`Azure.Resource.UseTags` - so a first deployment needs `allowSharedKeyAccess = $false`
and tags.

It isn't a transaction: the first failure stops the run, what came before
stays, and running again carries on from there. Needs Contributor (or Storage
Account Contributor) on the resource group, which must exist; User Access
Administrator for role assignments; Storage Blob Data Contributor and network
access to the account for blob uploads.

## Diagnostic settings

`Get-AACDiagnosticSetting` finds the resources whose logs don't reach Log
Analytics. Read-only, in three steps:

1. **Every resource in scope**, with one KQL query (Azure Resource Graph), and
   the subscriptions for their activity log. A storage account's logs are set
   on its blob, file, queue and table services, which Resource Graph doesn't
   list: they are added.
2. **Which resources have logs**: Azure's own list of a resource's diagnostic
   categories (`diagnosticSettingsCategories`), read once per resource type and
   kind - not per resource.
3. **The diagnostic settings** of every resource that has logs (the
   [Diagnostic Settings - List](https://learn.microsoft.com/rest/api/monitor/diagnostic-settings/list)
   API, 2021-05-01-preview), 12 at a time (`-ThrottleLimit`).

```powershell
Get-AACDiagnosticSetting -SubscriptionId 00000000-0000-0000-0000-000000000000
Get-AACDiagnosticSetting -ManagementGroupId 'mg-landingzones' -ExpectedWorkspace 'law-central' -HtmlPath .\Diagnostics.html -PdfPath .\Diagnostics.pdf
Get-AACDiagnosticSetting -NotExportedOnly -NoDisplay | Group-Object ResourceType | Sort-Object Count -Descending
Get-AACDiagnosticSetting -ResourceType 'microsoft.keyvault/vaults' -ExpandSetting -CsvPath .\KeyVaultSettings.csv
```

Each resource with logs gets a status, and a reason when its logs don't all
arrive:

| Status           | Meaning                                                                                                                                         |
| ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| Exported         | Every log category reaches a Log Analytics workspace - by name, or through a category group (`allLogs`, `audit`) it belongs to                  |
| Partial          | Some categories do; the missing ones are listed                                                                                                 |
| Not to workspace | Diagnostic settings exist, but none sends logs to a workspace that exists - storage or Event Hubs only, a deleted workspace, or nothing enabled |
| No setting       | No diagnostic setting at all                                                                                                                    |
| Unknown          | It couldn't be read (the error says why)                                                                                                        |

Misconfigurations, by severity: **High** - no diagnostic setting, activity log
not exported, no workspace destination, a workspace that doesn't exist;
**Medium** - log categories missing, a setting with nothing enabled, the same
category sent to a workspace twice (billed twice), a workspace other than
`-ExpectedWorkspace`; **Low** - a workspace in another region, the retired
retention policy still set.

The view shows coverage by resource type (least covered first), the
workspaces receiving logs, the misconfigurations with the resources they
affect, and every resource whose logs don't reach a workspace.
`-ExpandSetting` returns one row per diagnostic setting, flattened:
destinations, workspace (found, region), destination table (resource-specific
or AzureDiagnostics), storage account, event hub, log categories and groups
enabled and disabled, metrics, retention. A large estate means a call per
resource with logs: narrow it with `-SubscriptionId`, `-ManagementGroupId`,
`-ResourceGroupName` or `-ResourceType`.

## Log Analytics workspace assessment

`Invoke-AACLogAnalyticsWorkspaceAssessment` assesses one workspace - by its
workspace ID (GUID), resource ID or name - without changing anything:

```powershell
Invoke-AACLogAnalyticsWorkspaceAssessment -WorkspaceId 00000000-0000-0000-0000-000000000000
Invoke-AACLogAnalyticsWorkspaceAssessment -WorkspaceId 'law-contoso-prod' -Days 7 -HtmlPath .\Workspace.html -CsvPath .\Tables.csv
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

## Troubleshooting

**When a command fails.** At the console, the progress line of the step that
was running turns red, and a red panel says what failed, that step, and what
to do:

```text
╭─ ✗ Invoke-AACApplicationInsightQuery failed ─────────────────────────────╮
│ Azure refused the request (403): The client ... does not have            │
│ authorization to perform action 'Microsoft.OperationalInsights/...'      │
│                                                                          │
│ Step  Running the exceptions query over the last 2h                      │
│ Fix   Your account needs a role that allows this: ... Log Analytics      │
│       Reader for Invoke-AACApplicationInsightQuery.                      │
╰──────────────────────────────────────────────────────────────────────────╯
```

Then the command stops with a normal PowerShell error of its own, so
`try`/`catch`, `$Error` and `-ErrorVariable` work as usual. Scripts can check
its `FullyQualifiedErrorId`: `AzureRequestFailed<status>` (for example
`AzureRequestFailed403,Show-AACCost`), `CommandFailed` or `InternalError`.
Output that isn't an interactive console (CI, redirected) and
`-ErrorAction SilentlyContinue` get no panel. An `InternalError` is a bug in
the module: its message gives the module file and line. Please
[report it](https://github.com/ChendrayanV/Azure.Admin.Console/issues) with
that message.

**"The pipeline has been stopped."** Before v0.13.0, piping a command to
`Select-Object -First` (or anything else that stops a pipeline early) ended
it with this error and a red panel. It isn't a failure: update to v0.13.0 or
later, where the command just stops. Ctrl+C still stops everything.

**`?` instead of symbols, or `+` and `-` in the progress.** Windows consoles
often default to a legacy code page (437 or 850), which has no `●`, `→` or
`✓`. The module detects this: in such a console it draws its symbols in plain
ASCII (`*`, `->`, `+`, `-`), so nothing is printed as `?`. The tests check
every view against code pages 437 and 850. For the full Unicode display,
switch the session to UTF-8 and import the module again:

```powershell
[Console]::OutputEncoding = [Text.Encoding]::UTF8   # add to your $PROFILE to keep it
Import-Module Azure.Admin.Console -Force
```

Windows Terminal and the VS Code terminal display the full Unicode output once
the encoding is UTF-8.

**"requires a minimum Windows PowerShell version of '7.2'".** The module runs
on PowerShell 7.2 or later (7.4+ for PDF export), on Windows, Linux and macOS,
not on Windows PowerShell 5.1. Install PowerShell 7 (`winget install
Microsoft.PowerShell`) and run it as `pwsh`.

## Design and security

- **No Az / Microsoft.Graph modules.** Every Azure call is a plain REST call
  to Azure Resource Manager, Resource Graph and Cost Management, through one
  pooled `HttpClient`. Independent calls run in parallel, within each API's
  limits: Resource Manager 12 at a time, Resource Graph 4, Cost Management 3.
  Throttled calls wait as long as Azure's retry headers ask.
- **No app registration and no secrets.** The sign-in uses the authorization
  code flow with PKCE (RFC 7636) and a one-shot localhost listener. Tokens stay
  in memory for the session and are never written to disk.
- **Read-only.** No command or check changes anything in Azure. Key Vault keys
  and secrets are listed as metadata only, never their values.
- **Pinned bundled libraries.** [Spectre.Console](https://spectreconsole.net)
  (console UI) and PDFsharp + MigraDoc (PDF) ship in `lib\`, all MIT-licensed.
  Each DLL is checked against a pinned SHA-256 hash before it loads. See
  `lib\pdf\SOURCES.md`.

## Development

```text
Azure.Admin.Console/
  Azure.Admin.Console.psd1   Module manifest
  Azure.Admin.Console.psm1   Loads lib\Spectre.Console.dll, then Private\ and Public\
  Public/                    Exported commands, one per file, with comment-based help
  Private/                   Internal helpers (REST, Resource Graph, PKCE, PDF, console views, progress)
  PSRule/                    PSRuleRunner.ps1 (runs PSRule in its own pwsh) and Rules\ (the AAC.* rules and their help)
  Parked/                    Invoke-AACPester and its estate check, set aside (not loaded or packaged)
  lib/                       Vendored Spectre.Console and PDFsharp/MigraDoc (MIT)
  en-US/                     about_ help topic and the MAML help Get-Help shows (built by PlatyPS)
  docs/                      Markdown help, one page per command (built by PlatyPS)
  tools/                     Build-Help.ps1: builds docs\ and the MAML with PlatyPS (not packaged)
  Tests/                     Unit tests, no Azure needed (not packaged)
  .github/workflows/         CI and release pipelines
  build.ps1                  Docs, tests, packaging and publishing
  CHANGELOG.md, LICENSE
```

### Testing

The unit tests in `Tests\` cover every command, with no Azure account needed.
Each one mocks the point where the module leaves the machine and runs
everything on this side for real:

| Command                                                                           | Mocked                                                                                                                                                                                                                                                                              | Tested for real                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| --------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Connect-AAC`                                                                     | The browser (`Start-Process`) and the token endpoint (`Invoke-RestMethod`)                                                                                                                                                                                                          | The PKCE code, the localhost listener receiving the redirect, state (CSRF) validation, the token exchange and the stored session; app-only sign-in: a client secret, a certificate's signed client assertion (checked with its public key), a managed identity endpoint, and a new token when one runs out                                                                                                                                                                                                                                          |
| `Invoke-AACPolicyAssessment`                                                      | Resource Graph and Resource Manager, with a made-up Contoso tenant                                                                                                                                                                                                                  | The queries (tenant-wide discovery, worst-state compliance, by-ID chunks), compliance overall and by subscription, management group, assignment, policy and category, thresholds, every finding, identities and roles, exemption expiry, Platform and Application audiences, management group and subscription scopes, excluded scopes, the tree, the built-in definitions Resource Graph lacks read from Resource Manager, the reports and the view                                                                                                |
| `Invoke-AACAksAssessment`                                                         | Resource Graph, the PSRule exporter and engine, Resource Manager and AKS run command, with made-up Contoso clusters                                                                                                                                                                 | Workloads inferred from pod names, system namespaces, effects and DoNotEnforce, the roll-ups and the 500-record cap, cluster policy states and assignments, version support (supported, LTS, out of support) and upgrades, every Well-Architected check on a well-run and a neglected cluster, subnet capacity, the other lenses as findings, settings, Gatekeeper through run command (Entra ID token, no Gatekeeper, failures), scope and names, PSRule options, the reports and the view                                                         |
| `Invoke-AACAssessment`                                                            | Resource Graph, Resource Manager and Cost Management, with a made-up Contoso tenant                                                                                                                                                                                                 | The catalog (every sheet, column spec and key column) and its queries, resource group and tag filters, every sheet by label, VM sizes and subnet IPs filled in afterwards, retirements, Advisor, cost and tags on each row, the overview sheets, Advisor, Defender, Policy, outages across subscriptions, quotas, reservations, the tenant tree and organization diagram, scope and `-Category`, which Azure APIs are asked, the governance sheets (policy status, controls, why a resource fails, PSRule, recommendations ranked) and `-PSRule`, a sheet that fails, the upload, Automation sign-in, the reports and the view                                           |
| The transport (`Invoke-AACHttp`, `Invoke-AACArmParallel`, `Invoke-AACGraphBatch`) | The single HTTP send (`Send-AACHttpRequest`), or nothing (a local test server)                                                                                                                                                                                                      | Retries as Azure's retry headers ask (`Retry-After`, Cost Management's and Resource Graph's own), paging (`nextLink`, `$skipToken`), the throttle limit, Azure's error messages, failures allowed per query                                                                                                                                                                                                                                                                                                                                         |
| `Get-AACAdvisorRecommendation`, `Get-AACFirewallRule`, `Show-AACResource`         | Resource Graph, with hand-built rows (through a shim that runs each batched query one by one)                                                                                                                                                                                       | Flattening, filters and search, output modes, CSV, PDF and HTML, and the console view                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `Get-AACInventory`                                                                | Resource Graph and Cost Management, with a made-up Contoso tenant                                                                                                                                                                                                                   | The tree and its rolled-up counts, secure scores, cost (management group scope and the per-subscription fallback, deleted resources, currencies), insights (the mix, what needs attention, subnets), the views and the exports                                                                                                                                                                                                                                                                                                                      |
| `Get-AACPolicyState`                                                              | Resource Graph, with made-up policy states                                                                                                                                                                                                                                          | The KQL and its filters, management group, subscription and resource group scope, each resource's verdict, compliance per assignment, scope and policy, the view and the exports                                                                                                                                                                                                                                                                                                                                                                    |
| `Get-AACSkuAvailability`                                                          | The parallel ARM reads and Resource Graph, with made-up Compute SKUs, usage and zones                                                                                                                                                                                               | Region and zone restrictions, zones asked for, family and regional quota, AKS's rules, series, size and architecture filters, a cluster's node pools, errors, the view and the exports                                                                                                                                                                                                                                                                                                                                                              |
| `Get-AACSecurityPosture`                                                          | Resource Graph, with made-up Defender for Cloud and Azure Policy rows                                                                                                                                                                                                               | Findings across sections, scores, compliance traced to resources, plans, policy compliance, resource group and tag narrowing, the queries per section, the view and the exports                                                                                                                                                                                                                                                                                                                                                                     |
| `Get-AACNetworkSecurityGroup`                                                     | Resource Graph and the parallel ARM reads                                                                                                                                                                                                                                           | Rule evaluation, associations and VMs protected, NIC-and-subnet conflicts, flow logs, findings, the view and the exports                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `Show-AACResourceMap`                                                             | Resource Graph, with a made-up hub-and-spoke estate                                                                                                                                                                                                                                 | Boxes, placement, connections, network paths, NSGs and route tables, the page                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `Get-AACAssignedPolicy`                                                           | Resource Graph and the parallel ARM reads, with a made-up tenant (management groups, an initiative, a missing definition)                                                                                                                                                           | Default, assigned and effective values, resource types from rules (parameters resolved, negated and alias-only rules, initiatives), inherited assignments for a subscription or management group, name filters, the view and the exports                                                                                                                                                                                                                                                                                                            |
| `Get-AACStorageAccountContainerSize`                                              | Resource Graph, the container listing and the blob service (`Send-AACHttpRequest`, with List Blobs XML pages)                                                                                                                                                                       | The page parser (tiers, snapshots, versions, deleted blobs, Data Lake directories, encoded names, the largest blobs), paging, Entra ID and account SAS, `-AuthMode Auto`, Azure Storage's errors and what to do, filters, the view and the exports                                                                                                                                                                                                                                                                                                  |
| `Get-AACTerraformPlan`                                                            | Nothing: it reads a made-up Contoso plan file                                                                                                                                                                                                                                       | Actions and reasons, attribute paths, blocks paired by name, JSON-encoded strings, forced replacements, sensitive values kept out of every output, drift, filters, UTF-16 files, the files it refuses, the view and the exports                                                                                                                                                                                                                                                                                                                     |
| `Deploy-AACStorageAccount`                                                        | An in-memory fake of Azure: Resource Manager reads and writes, checkNameAvailability, checkPolicyRestrictions, the policy assignments, PSRule and blob uploads all go to one store, which answers as Azure does (false values left out, its own fields added, bodies taken as JSON) | Idempotency (the second run writes nothing), PATCH of only what changed, merged service updates, immutable properties and redundancy, the name, policy Deny and Modify, a failing PSRule rule blocking with its fix, `-UseSuggestedFix` - and, against the real PSRule for Azure rules, that every automatic fix makes its rule pass, drift and `-Prune` under a lock, role assignments found again or adopted, blob MD5, one-item lists sent as lists, a failure part-way and the re-run, AVM parameters files and unsupported settings, `-WhatIf` |
| `Get-AACDiagnosticSetting`                                                        | Resource Graph and the parallel ARM reads, with a made-up Contoso estate (storage services, activity logs, a deleted workspace)                                                                                                                                                     | Which types have logs, every status and its reason, category groups, every misconfiguration, `-ExpectedWorkspace`, the flattened settings, the filters, how many calls are made, the view and the CSV, HTML and PDF reports                                                                                                                                                                                                                                                                                                                         |
| `Get-AACEntraGroupMembership`                                                     | Microsoft Graph (`Send-AACHttpRequest`), with made-up groups                                                                                                                                                                                                                        | Name filters and OData quoting, paging, nested groups and loops, a group that can't be read, the Connect-AAC Graph token, the view and the exports                                                                                                                                                                                                                                                                                                                                                                                                  |
| Cost anomalies, attack paths, access review, change history, health check, compliance gaps, failover readiness, dependency graph, utilization, drift | Made-up Contoso data per command (`Tests/Fixtures/Contoso*.ps1`), with Resource Graph, Resource Manager, Cost Management, Microsoft Graph, Log Analytics, the probes and the prices faked | Each command's rules and numbers (anomalies and forecasts, NSG evaluation and blast radius, RBAC findings and attestation, change grouping and incidents, probes and SLA, control mapping and baseline progress, recovery scores and runbooks, graph analysis and cycles, metrics classification and right-sizing, snapshot diff and rules), its queries, the view in any code page and the reports |
| `Show-AACDashboard`, `Show-AACJson`                                                | Resource Graph (`Invoke-AACGraphBatch`), with a made-up estate                                                                                                                                                                                                                      | The status (Failed, Warning, Healthy) and its headline, health counts, service events once per tracking ID, Advisor by category, changes, what couldn't be read, `-SubscriptionId` and `-Select` (and no console to ask), the view in any code page; JSON colouring and escaping, objects, JSON text, arrays and invalid JSON; the status vocabulary and callouts in Unicode and ASCII |
| `Show-AACCost`                                                                    | Cost Management (`Invoke-AACCostBatch`, through a shim)                                                                                                                                                                                                                             | Month and service totals, failed subscriptions, the charts, PDF and HTML; also the query's paging                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| `Invoke-AACPSRule`                                                                | The engine (`Invoke-AACPSRuleEngine`)                                                                                                                                                                                                                                               | Output modes, `-FailedOnly`, settings passed on, CSV and HTML; what is read for the rules asked for; `-Rule` checks; the view listing every resource                                                                                                                                                                                                                                                                                                                                                                                                |
| PSRule for Azure data (`Get-AACRuleData`)                                         | Azure Resource Manager (`Invoke-AACArmRequest`, `Invoke-AACArmParallel`)                                                                                                                                                                                                            | The Export-AzRuleData shape, child settings, 403/404 handling, masked shared keys, type filters in the query, `-NoExpand`                                                                                                                                                                                                                                                                                                                                                                                                                           |
| PSRule runner                                                                     | Nothing                                                                                                                                                                                                                                                                             | Real PSRule for Azure in a child `pwsh`: the AAC.\* rules (naming with its defaults, tags), `-Type` binding for custom rules, wildcard include/exclude, a rule error not stopping the run                                                                                                                                                                                                                                                                                                                                                           |
| `Invoke-AACLogAnalyticsWorkspaceAssessment`                                       | Resource Manager, Resource Graph and the KQL batch, with a made-up Contoso workspace; the HTTP batch for the query helper                                                                                                                                                           | Table sizes and billing, settings (anything new under Other), every recommendation rule and what it leaves out, agents' states, DCRs and associations, the change log, missing LAQueryLogs and Heartbeat, `-Section`, `-Days`, the view and the exports                                                                                                                                                                                                                                                                                             |
| `Invoke-AACVirtualNetworkAssessment`                                              | Resource Graph, with a made-up Contoso hub and spokes                                                                                                                                                                                                                               | The CIDR arithmetic and free ranges, IPs per network and subnet, outbound paths, roles, peerings (reverse, remote not visible), ASGs, private endpoints and DNS zones, every finding and no others, the NSG engine's findings, scope and `-Name`, a query that fails, the view and the exports                                                                                                                                                                                                                                                      |
| `Invoke-AACApplicationInsightQuery`                                               | Resource Graph and the query API (`Invoke-AACArmRequest`)                                                                                                                                                                                                                           | The KQL built from the parameters (with escaping), both table schemas flattened, `-Query`, errors, the view and the exports                                                                                                                                                                                                                                                                                                                                                                                                                         |

The console views are checked by swapping the Spectre console for one that
writes to a text buffer, then looking for what should be drawn. For a new
command, copy the nearest test file and change its mocks.

The comment-based help in each `Public\*.ps1` file is the single source of
command help. The Docs task builds two things from it with
[Microsoft.PowerShell.PlatyPS](https://github.com/PowerShell/platyPS) 1.0:

- `docs\<Command>.md`, the PlatyPS Markdown pages;
- `en-US\Azure.Admin.Console-help.xml`, the MAML help that `Get-Help` shows.
  Each command points at it with `.EXTERNALHELP`.

PlatyPS is needed only on the build machine, not by the installed module.
It runs in a `pwsh` process of its own, because PlatyPS and PSRule each load a
different `YamlDotNet.dll`. CI fails when `docs\` or `en-US\` is out of date.

```powershell
Install-PSResource Microsoft.PowerShell.PlatyPS -Scope CurrentUser   # once, to build the help
./build.ps1                   # Docs + Test + Build: a validated package in out\Azure.Admin.Console
./build.ps1 -Task Docs        # rebuild docs\ and the MAML help after editing help
./build.ps1 -Task Test        # unit tests only
```

The Build task copies only the runtime files into `out\Azure.Admin.Console`.
It then checks the staged copy: the manifest is valid, the exports match
`Public\`, a clean import succeeds, and PSScriptAnalyzer reports no errors.

### CI

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on every push to
`main` and every pull request:

- **Unit tests** on Windows, Ubuntu and macOS, with JUnit results kept as artifacts.
- **On Windows:** checks that `docs\` is up to date with the help, then builds and validates the package and keeps it as an artifact.

### Releasing to the PowerShell Gallery

1. Bump `ModuleVersion` in `Azure.Admin.Console.psd1` and add the release to
   `CHANGELOG.md`. A published version can never be replaced.
2. Commit, then push a tag that matches the version:

   ```powershell
   git tag -a v0.14.2 -m "Azure.Admin.Console v0.14.2"
   git push origin v0.14.2
   ```

Only a version tag publishes. Pushes and pull requests run CI only.
[`.github/workflows/release.yml`](.github/workflows/release.yml) first runs a
gate with no secrets and no approval. It stops the release unless all of
these hold:

- the tag matches `ModuleVersion`;
- the tagged commit is on `main`;
- `CHANGELOG.md` has a `## v<version>` entry;
- the version is higher than the one on the PowerShell Gallery.

The run summary shows each check. Only after the gate passes, the workflow:

1. waits for approval in the `psgallery` environment,
2. runs the tests and builds the package,
3. publishes to the PowerShell Gallery,
4. creates a GitHub release with the changelog entry and the package zip.

Setup, once:

- Create a `psgallery` environment in the repository settings. Add yourself as a required reviewer, and limit its deployment tags to `v*`.
- Add a `PSGALLERY_API_KEY` secret to that environment.

To publish by hand instead:

```powershell
./build.ps1
$env:PSGALLERY_API_KEY = '<API key from powershellgallery.com>'
./build.ps1 -Task Publish -WhatIf     # dry run
./build.ps1 -Task Publish
```

## License

[MIT](LICENSE). The bundled libraries keep their own MIT licenses in `lib\`.
