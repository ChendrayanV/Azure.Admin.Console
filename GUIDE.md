# Azure.Admin.Console - the full guide

Every command in detail. The short version is the [README](README.md); each command's reference is in [docs/](docs/).

[![CI](https://github.com/ChendrayanV/Azure.Admin.Console/actions/workflows/ci.yml/badge.svg)](https://github.com/ChendrayanV/Azure.Admin.Console/actions/workflows/ci.yml)
[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/Azure.Admin.Console?label=PowerShell%20Gallery)](https://www.powershellgallery.com/packages/Azure.Admin.Console)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Sponsor](https://img.shields.io/github/sponsors/ChendrayanV?label=Sponsor&logo=githubsponsors&color=EA4AAA)](https://github.com/sponsors/ChendrayanV)

Azure admin reports and checks from PowerShell, over plain REST. No Az or
Microsoft.Graph modules, and no app registration.

<p align="center">
  <a href="https://www.youtube.com/watch?v=xBkStQ1H2OU">
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
Invoke-AACTenantAssessment -SecurityCenter -IncludeCost

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

# The whole network: hubs at the centre of their spokes, peerings, firewalls, private endpoints
Show-AACNetworkTopology

# PSRule for Azure on the live estate, as a clickable HTML report
Invoke-AACPSRule -HtmlPath .\PSRule.html

# Just the module's naming and tag rules - quick: names, types and tags only
Invoke-AACPSRule -Rule 'AAC.*'

# A storage account, idempotently: plan, Azure Policy and PSRule gates, then apply (no template)
Deploy-AACStorageAccount -SubscriptionId <subscription> -ResourceGroupName rg-data -ConfigurationPath .\Examples\storage-account.psd1 -WhatIf

# Which resources' logs don't reach Log Analytics - and what is misconfigured
Get-AACDiagnosticSetting -ExpectedWorkspace 'law-central' -HtmlPath .\Diagnostics.html

# A Log Analytics workspace: table sizes, settings, recommendations, insights
Invoke-AACLogAnalyticsWorkspaceAssessment -WorkspaceId 'law-contoso-prod' -HtmlPath .\Workspace.html -PdfPath .\Workspace.pdf

# Virtual networks: available IPs, subnets, peerings, NSGs, ASGs, DNS and security
Invoke-AACVirtualNetworkAssessment -HtmlPath .\VNet.html

# IP address management: your address plan, every IP address, overlaps and the next free ranges
Get-AACIPAMReport -AddressPlan .\ipam-plan.psd1 -Open

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

The commands are grouped by the module's areas - one module, one install, a child area for each platform (see [Development](#development)):

### Core: sign-in, REST and reports

Signing in to Azure, the REST helpers every command uses (Resource Manager, Resource Graph, Microsoft Graph), the console views and the CSV, HTML and PDF reports.

| Command                                                                                          | What it does                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`Connect-AAC`](docs/Connect-AAC.md)                                                             | Signs in with a browser (OAuth 2.0 + PKCE, localhost redirect) - or a device code (`-DeviceCode`), a service principal's secret or certificate (`-ClientSecret`, `-CertificatePath`, `-CertificateThumbprint`), or a managed identity (`-Identity`, e.g. in Azure Automation). Uses the Azure CLI's pre-consented public client ID unless you pass `-ClientId`.                                                                                                                                                                                                                                                                                   |
| [`Disconnect-AAC`](docs/Disconnect-AAC.md)                                                       | Forgets the sign-in. It was only ever in memory.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| [`Show-AACJson`](docs/Show-AACJson.md)                                                           | JSON - or any object, as JSON - indented and syntax-coloured in a panel: ARM templates, REST responses, resources, this module's objects.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |

### Azure

Commands for an Azure estate - subscriptions and management groups: inventory, cost, policy, governance, networking, security, identity in Azure (RBAC, managed identities), health, assessments, Terraform and deployment.

| Command                                                                                          | What it does                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`Deploy-AACStorageAccount`](docs/Deploy-AACStorageAccount.md)                                   | Creates or updates a storage account - containers, file shares, queues, tables, lifecycle rules, private endpoints, diagnostic settings, role assignments, a lock and blobs - idempotently with the Azure REST APIs, no ARM, Bicep or Terraform template. AVM's parameter names and defaults; a plan (create, update, can't change in place, drift); gates: the name, Azure Policy (`checkPolicyRestrictions` on every write's exact body) and PSRule for Azure; then apply and verify. The only command that writes.                                                                                                                             |
| [`Get-AACAdvisorRecommendation`](docs/Get-AACAdvisorRecommendation.md)                           | A consolidated, flattened view of Azure Advisor: a console view at the prompt, objects down a pipeline, CSV and/or PDF exports.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| [`Get-AACFirewallRule`](docs/Get-AACFirewallRule.md)                                             | Every Azure Firewall Policy rule: a console view at the prompt (Allow in green, Deny in red), objects down a pipeline, CSV and/or PDF exports.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| [`Show-AACResource`](docs/Show-AACResource.md)                                                   | A colourful bar chart of your resources by type, location, resource group or subscription.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| [`Invoke-AACAksAssessment`](docs/Invoke-AACAksAssessment.md)                                     | AKS clusters through every lens: current settings, about 35 Well-Architected checks scored per pillar, PSRule for Azure, Azure Policy for Kubernetes consolidated by namespace, workload, policy and cluster (the AKS Policy Compliance Toolkit's view) with Gatekeeper's complete counts, versions and upgrades, subnet capacity, Advisor and Defender. A console view, objects, and CSV, PDF and interactive HTML reports.                                                                                                                                                                                                                      |
| [`Invoke-AACFunctionAppAssessment`](docs/Invoke-AACFunctionAppAssessment.md) | Function Apps end to end: hosting and plan, usage (executions, GB-seconds, errors, response time, estimated Consumption cost), every function and trigger, runtime support, configuration and app settings (names only), networking, deployment center and slots, backups, Service Connector and named services, the last week's Activity Log, about 30 Well-Architected checks, PSRule for Azure, Advisor and Defender. A console view, objects, and CSV, PDF and a tabbed HTML report with a tab per audience. |
| [`Invoke-AACTenantAssessment`](docs/Invoke-AACTenantAssessment.md)                                     | An Azure tenant assessed end to end, in the spirit of Azure Resource Inventory: a sheet per resource type (~95) with its key settings and policy compliance, the organization, Advisor and retirements, Defender, Policy, the Well-Architected Framework, PSRule, FinOps (savings, cost allocation, budgets), outages, quotas, reservations and cost - CSV, an interactive HTML report, a PDF and interactive network and organization diagrams, with a live progress display. Runs in Azure Automation with a managed identity and uploads to blob storage.                                                                                                                                                                                           |
| [`Get-AACInventory`](docs/Get-AACInventory.md)                                                   | The tenant as a tree: management groups, subscriptions, resource groups and resources, with counts, the Defender for Cloud secure score and - with `-Cost` - the cost at every level. A console tree, objects, and CSV, PDF and interactive HTML reports.                                                                                                                                                                                                                                                                                                                                                                                         |
| [`Export-AACDiagram`](docs/Export-AACDiagram.md)                                                 | Your existing resources as an editable draw.io diagram - the resources, the network topology or Application Gateways - with real containers (move a box and what's in it moves too), Azure icons, attached connections, each shape's data and portal link, and a page per subscription or resource group. `-Update` refreshes it from Azure and keeps your changes: new resources added and marked, removed ones faded. |
| [`Export-AACResource`](docs/Export-AACResource.md)                                               | Every resource - for the tenant, a management group, subscriptions, resource groups or types - with its subscription and management group by name, resource group tags, tags as columns and each type's key settings, to CSV, HTML and PDF. Filters in Resource Graph (type, group, name, location, tag, missing tag, KQL) and free-text search.                                                                                                                                                                                                                                                                                                  |
| [`Get-AACSecurityPosture`](docs/Get-AACSecurityPosture.md)                                       | Microsoft Defender for Cloud and Azure Policy in one report: secure scores, recommendations grouped by control with remediation links, active alerts, Defender plans, regulatory compliance traced to the failing resources, and policy compliance per assignment - one list of findings. A console view, objects, and CSV, PDF and interactive HTML reports.                                                                                                                                                                                                                                                                                     |
| [`Get-AACSecurityAlert`](docs/Get-AACSecurityAlert.md)                                           | Microsoft Defender for Cloud security alerts across every subscription in one query - the Get-AzSecurityAlert equivalent, with more in each alert: MITRE ATT&CK tactics and techniques, the hosts, accounts and IP addresses involved, extended properties, remediation steps, incidents and recurring alerts. Filters by status, severity, age, name, type, tactic and resource, and takes resources from the pipeline.                                                                                                                                                                                                                          |
| [`Get-AACSkuAvailability`](docs/Get-AACSkuAvailability.md)                                       | Which VM sizes you can use for virtual machines or AKS node pools in a region and its availability zones - the subscription's restrictions, vCPU quota and AKS's rules - and why a size can't be used; an AKS cluster's node pools. Read-only REST, nothing deployed. A console view, objects, and CSV, PDF and interactive HTML reports.                                                                                                                                                                                                                                                                                                         |
| [`Get-AACAssignedPolicy`](docs/Get-AACAssignedPolicy.md)                                         | Every Azure Policy assignment and its parameters - the default, assigned and effective value of each - with the resource types the policy applies to (its rule's type conditions, parameters resolved), one row per assignment and parameter. Assignments inherited from management groups included. A console view, objects, and CSV and interactive HTML reports.                                                                                                                                                                                                                                                                               |
| [`Invoke-AACPolicyAssessment`](docs/Invoke-AACPolicyAssessment.md)                               | Azure Policy assessed as a whole, in the spirit of AzPolicyLens: compliance (each resource counted at its worst state) overall and by subscription, management group, assignment, policy and category; exemptions and their expiry; initiatives and definitions; the managed identities' roles; what to improve (direct assignments, DoNotEnforce, remediation without an identity or role, deprecated policies, overlapping assignments, stale exemptions, unassigned custom definitions, unused groups). Platform and Application audiences. A console view, objects, and CSV, PDF and interactive HTML reports with the management group tree. |
| [`Invoke-AACDefenderAssessment`](docs/Invoke-AACDefenderAssessment.md)                           | Microsoft Defender for Cloud assessed across subscriptions: every recommendation (unhealthy, healthy and not applicable resources, risk level), attack paths step by step, security alerts with MITRE tactics and remediation, the inventory with each resource's plan coverage, vulnerabilities (CVEs), secure score controls, Defender plans with extensions, regulatory compliance, and environment settings (contacts, notifications, integrations, connectors, just-in-time) - with findings on how Defender is set up. A console view, an object, CSV and a tabbed HTML report in the portal's order. |
| [`Get-AACPolicyState`](docs/Get-AACPolicyState.md)                                               | Azure Policy compliance for every resource - one row per resource and policy, with initiative, assignment, effect and when it was evaluated - by management group, subscription or resource group, with compliance per assignment, policy, subscription and resource group. A console view, objects, and CSV, PDF and interactive HTML reports.                                                                                                                                                                                                                                                                                                   |
| [`Get-AACNetworkSecurityGroup`](docs/Get-AACNetworkSecurityGroup.md)                             | A detailed assessment of network security groups: associations, every rule, flow logs and diagnostic settings, and findings by severity (open to the internet, shadowed rules, subnet and NIC conflicts, logging gaps). A console view, objects, and CSV, PDF and interactive HTML reports.                                                                                                                                                                                                                                                                                                                                                       |
| [`Get-AACStorageAccountContainerSize`](docs/Get-AACStorageAccountContainerSize.md)               | How much is stored in every blob container of your storage accounts: blobs, bytes, access tiers (Hot, Cool, Cold, Archive), snapshots, versions and deleted blobs, the newest change and the largest blobs - read in parallel, a page of 5,000 blobs at a time. Entra ID or a short-lived account SAS. A console view with every account and container as a tree, objects, and CSV and interactive HTML reports.                                                                                                                                                                                                                                  |
| [`Get-AACTerraformPlan`](docs/Get-AACTerraformPlan.md)                                           | A Terraform plan in JSON (`terraform show -json`), flattened: what will be created, updated, replaced, deleted, read, imported and moved - and why - down to each attribute's before and after value, with the outputs and what changed outside Terraform. Sensitive values are never shown. Offline: no sign-in. A console view, objects, and CSV and interactive HTML reports.                                                                                                                                                                                                                                                                  |
| [`Export-AACTerraform`](docs/Export-AACTerraform.md)                                             | Existing resources as Terraform - a resource group, resources by ID or piped, or a Resource Graph query - through the Azure Export for Terraform API (a long-running operation, polled with progress): a folder ready for terraform init and plan, with import blocks. What azurerm can't export is listed, and `-FallbackToAzApi` exports it with azapi; `-Plan` runs terraform plan to prove the export. A console view, objects, and CSV, HTML and PDF reports.                                                                                                                                                                                |
| [`Get-AACDiagnosticSetting`](docs/Get-AACDiagnosticSetting.md)                                   | Every resource's diagnostic settings, flattened, and the resources whose logs don't reach a Log Analytics workspace: each one's status (exported, partial, not to a workspace, no setting), what's missing and why, and misconfigurations (deleted workspaces, nothing enabled, logs sent twice, another region, unexpected workspace, retired retention). Storage services and subscription activity logs included. A console view, objects, and CSV, PDF and interactive HTML reports.                                                                                                                                                          |
| [`Show-AACNetworkTopology`](docs/Show-AACNetworkTopology.md)                                     | The network topology of the tenant, management groups, subscriptions or regions, opened in your browser: hubs at the centre of their spokes, or every network inside its tenant, management group, subscription, region and resource group; peerings, gateways, Virtual WAN, firewalls and appliances, private endpoints to their PaaS, routes to their next hop; roles and findings. Saves as PNG, JPEG or SVG.                                                                                                                                                                                                                                  |
| [`Show-AACResourceMap`](docs/Show-AACResourceMap.md)                                             | A map of one or more resource groups, opened in your browser: the resources with their Azure icons, in subscription, resource group, VNet and subnet boxes, with their connections, dependencies and network paths. Saves as PNG or JPEG.                                                                                                                                                                                                                                                                                                                                                                                                         |
| [`Show-AACCost`](docs/Show-AACCost.md)                                                           | Subscription costs: month to date by subscription and by service, and a monthly trend, as charts and a table.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| [`Show-AACDashboard`](docs/Show-AACDashboard.md)                                                 | The estate on one screen: one status and an Estate score at the top; health, security, policy, governance (limits, privileged access, unused resources, tags), Advisor and savings, resources by region and type, 14 days of changes and who made them, and with `-IncludeCost` the spend; then what to do next, ranked, with the command that goes deeper. `-HtmlPath`/`-PdfPath` for a report with a tab per section, `-Watch` for a screen on the wall. |
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
| [`Get-AACResourceHealth`](docs/Get-AACResourceHealth.md)                                         | Resource Health of every resource (Available, Unavailable, Degraded), why and since when, its latest platform event, the Azure outages and maintenance that hit it, and with -IncludeHistory its availability over the last days.                                                                                                                                                                                                                                                                                                                                                                                                                 |
| [`Get-AACUnusedResource`](docs/Get-AACUnusedResource.md)                                         | Unused resources: unattached disks, NICs and public IPs, empty App Service plans, pools and gateways, stopped VMs still billed, old snapshots, empty resource groups and more - billed or not, since when, and last month's cost with -IncludeCost.                                                                                                                                                                                                                                                                                                                                                                                               |
| [`Get-AACResourceError`](docs/Get-AACResourceError.md)                                           | What failed, from the Activity Log: access denied (the refused action and scope), Azure Policy denies, quota and capacity, throttling, locks, invalid deployments - one per correlation ID, with who and the fix.                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| [`Get-AACPrivateEndpoint`](docs/Get-AACPrivateEndpoint.md)                                       | Private endpoints audited: connection state, target, IPs and names, the DNS zone group and whether the endpoint's network is linked to it, orphaned endpoints, targets still public, duplicated privatelink zones.                                                                                                                                                                                                                                                                                                                                                                                                                                |
| [`Get-AACLoadBalancerHealth`](docs/Get-AACLoadBalancerHealth.md)                                 | Load balancers, Application Gateways and Traffic Manager right now: every backend's health probe, healthy and unhealthy hosts, data path, empty pools, rules without probes, retired SKUs, no redundancy.                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| [`Get-AACLegacyAuthentication`](docs/Get-AACLegacyAuthentication.md)                             | Legacy and high-risk authentication in Azure (keys, SAS, local accounts, passwords, old TLS) and Entra ID (legacy-protocol sign-ins, legacy auth not blocked, implicit grant, ROPC, client secrets, SMS).                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| [`Get-AACOrphanedIdentity`](docs/Get-AACOrphanedIdentity.md)                                     | Identities nobody uses: role assignments to deleted principals, unattached user-assigned identities, managed identities of deleted resources, service principals not signed in for months, abandoned app registrations - and the access each holds.                                                                                                                                                                                                                                                                                                                                                                                               |
| [`Export-AACDiagnosticBundle`](docs/Export-AACDiagnosticBundle.md)                               | A zip for a support case: each resource's configuration, health and history, Activity Log, diagnostic settings, locks, recommendations, compliance, alerts, changes and role assignments - secrets redacted, with a README and summary.                                                                                                                                                                                                                                                                                                                                                                                                           |
| [`Invoke-AACPSRule`](docs/Invoke-AACPSRule.md)                                                   | PSRule for Azure, the module's own naming and tag rules and your custom rules on the live estate: include or exclude rules by name or wildcard, with a baseline or settings. Runs of only the module's rules read just names, types and tags.                                                                                                                                                                                                                                                                                                                                                                                                     |
| [`Invoke-AACVirtualNetworkAssessment`](docs/Invoke-AACVirtualNetworkAssessment.md)               | Virtual networks assessed: address space with total, used and available IPs and the free CIDR ranges; every subnet (capacity, NSG, routes, NAT gateway, outbound path, endpoints, delegations); peerings; NSGs and ASGs; DNS, DDoS, encryption, flow logs, gateways, firewalls and Bastion - with findings by severity. A console view, objects, and CSV, PDF and interactive HTML reports.                                                                                                                                                                                                                                                       |
| [`Get-AACIPAMReport`](docs/Get-AACIPAMReport.md) | IP address management with no server to run: Azure's address space measured against your address plan (spaces and blocks, or the private ranges) - each block's allocation, free space and next free ranges, every network (in the plan or not), subnet and private IP address (unattached interfaces included), overlaps (peered, with on-premises ranges), CIDR checks and findings. A console view, objects, and CSV, PDF and a tabbed HTML report with a tree of the plan and hover cards. |
| [`Invoke-AACLogAnalyticsWorkspaceAssessment`](docs/Invoke-AACLogAnalyticsWorkspaceAssessment.md) | A Log Analytics workspace assessed: billable and not billable tables with their size, plan and retention; every workspace setting; recommendations (Azure Advisor's and its own: cost, reliability, security); data collection rules; and the Workspace Insights views - Overview, Usage, Health, Agents, Query Audit, Data Collection Rules, Change Log. Read-only. A console view, an object, CSV, a tabbed HTML report (a tab per section) and a PDF.                                                                                                                                                                                                             |
| [`Invoke-AACApplicationInsightQuery`](docs/Invoke-AACApplicationInsightQuery.md)                 | Application Insights exceptions, flattened, from a Log Analytics workspace or Application Insights resource, or any KQL query.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| [`Invoke-AACWafAssessment`](docs/Invoke-AACWafAssessment.md)                                     | The estate against the Azure Well-Architected Framework's five pillars: about 60 checks plus Advisor and Defender for Cloud, scored 0-100 by pillar, design principle and check, with each pillar's maturity, workbook-style heat maps by subscription, resource group or resource type, team questionnaire answers (`-AttestationPath`) and the trend (`-HistoryPath`). A console view, objects, and CSV, PDF and interactive HTML reports. |
| [`Test-AACGoLiveReadiness`](docs/Test-AACGoLiveReadiness.md)                                     | A go-live gate: the Well-Architected assessment on a workload, Ready or Not ready - pillar scores against a minimum, no high-severity findings, the checks that must pass - with the blockers. `-FailOnGap` fails a pipeline stage. |
| [`Export-AACWafQuestionnaire`](docs/Export-AACWafQuestionnaire.md)                               | The Well-Architected questionnaire - one question per design principle, for what no API can test - as a CSV the team answers and `Invoke-AACWafAssessment -AttestationPath` scores. |
| [`Get-AACWafCheck`](docs/Get-AACWafCheck.md)                                                     | The checks the Well-Architected assessment runs, by pillar and design principle, with the resource type, severity, fix and link for each. |
| [`Get-AACKeyVaultInsight`](docs/Get-AACKeyVaultInsight.md)                                       | Key Vaults: what Azure Monitor's Key Vault workbook shows (availability, transactions, latency, failures by status, operations from the audit logs) plus saturation, posture, callers denied or throttled, and secrets, keys and certificates near expiry (`-IncludeObjects`) - as a heat map and findings. |
| [`Invoke-AACStorageAccountAssessment`](docs/Invoke-AACStorageAccountAssessment.md)               | Storage accounts: what Azure Monitor's Storage accounts workbook shows (transactions, latency, errors by response type, capacity by service) plus availability, throttling, security posture, data protection (soft delete, versioning, redundancy) and cost (lifecycle rules, legacy kinds, idle and hot-but-quiet accounts) - as a heat map and findings. |
| [`Invoke-AACServiceBusAssessment`](docs/Invoke-AACServiceBusAssessment.md)                       | Service Bus namespaces assessed: requests, errors and throttling, Premium CPU and memory, every queue, topic and subscription's messages (active, dead-lettered, scheduled) and how full it is, security (TLS, SAS keys, network, logs), resilience (zones, geo-disaster recovery) and cost, as a heat map and findings. A console view, objects, and CSV, HTML and PDF reports.|
| [`Invoke-AACCosmosDBAssessment`](docs/Invoke-AACCosmosDBAssessment.md)                           | Cosmos DB accounts assessed in every API: availability, requests by status and rate limiting (429), throughput and the busiest partition, storage, every database and container with its throughput, security (network, keys, TLS, logs, Defender), resilience (regions, failover, zones, backup) and cost, as a heat map and findings. A console view, objects, and CSV, HTML and PDF reports.|
| [`Show-AACApplicationGatewayMap`](docs/Show-AACApplicationGatewayMap.md)                         | Application Gateways drawn as their traffic flow - frontend IPs, listeners, rules, path rules and redirects, backend settings and probes, pools and targets, WAF policies - with health (`-IncludeHealth` for the live backend health) and findings, opened in your browser. |
| [`Get-AACNetworkHealth`](docs/Get-AACNetworkHealth.md)                                           | The hybrid and edge network's health - ExpressRoute circuits and gateways, VPN gateways, connections and tunnels, Azure Firewalls and NAT gateways - from metrics, configuration and Resource Health: % of capacity, thresholds and findings, each with when it happened. |
| [`Invoke-AACGovernanceAssessment`](docs/Invoke-AACGovernanceAssessment.md)                       | Governance across the tenant in one run, in the spirit of the Azure Governance Visualizer: the management group hierarchy, access, workload identities, policy remediation, Azure limits, settings, tags, locks and recent changes - a tabbed workbook, and a Markdown page with the hierarchy as a Mermaid diagram for a GitHub or Azure DevOps wiki. |
| [`Show-AACManagementGroupMap`](docs/Show-AACManagementGroupMap.md)                               | The management group hierarchy as an interactive map: nested boxes, each subscription inside its group, and the policy and role assignments at each level. `Export-AACDiagram -View Governance` draws it for draw.io. |
| [`Get-AACRoleAssignment`](docs/Get-AACRoleAssignment.md)                                         | Every Azure role assignment at every scope - who holds it and what they are (user, guest, group, application or another tenant's, system- or user-assigned identity, deleted), what the role can do, how far it reaches, standing or PIM, group members, who created it - with orphaned assignments, risky grants and unused or Owner-equivalent custom roles flagged. |
| [`Get-AACServicePrincipalInsight`](docs/Get-AACServicePrincipalInsight.md)                       | Every application and managed identity with Azure roles: its kind, privileged roles, the resources a user-assigned identity is attached to, secrets and certificates about to expire, and other tenants' applications with access. |
| [`Test-AACAzureLimit`](docs/Test-AACAzureLimit.md)                                               | Which scopes are close to an Azure limit - role assignments, custom roles, policy assignments, definitions, initiatives and exemptions, resource groups, tags, management group depth - with what to do, and a gate for pipelines (`-FailOnLimit`). |
| [`Get-AACGovernanceSetting`](docs/Get-AACGovernanceSetting.md)                                   | The settings governance depends on: who can create management groups, where new subscriptions land, management group activity logs, Defender security contacts, classic administrators, preview features, resource providers registered unevenly, each subscription's offer and state. |
| [`Get-AACPolicyRemediation`](docs/Get-AACPolicyRemediation.md)                                   | DeployIfNotExists and Modify policies with resources they could fix, and what their remediation tasks did: never run, failed, drifted again, still running, or no identity to run with. |
| [`Get-AACTagUsage`](docs/Get-AACTagUsage.md)                                                     | How tags are really used: each tag name's coverage and values, names that clash in casing, near-duplicates, values in mixed casing, and how far your required tags reach. |
| [`Get-AACResourceLock`](docs/Get-AACResourceLock.md)                                             | Every resource lock, and the critical resources (key vaults, storage, databases, vaults, networks, DNS zones...) no lock protects - with ReadOnly locks that break more than they protect flagged. |
| [`Get-AACGovernanceChange`](docs/Get-AACGovernanceChange.md)                                     | Who changed policy and access in the last days: policy definitions, initiatives and assignments, custom roles and role assignments created or updated, with the author resolved and privileged grants flagged. |
| [`Test-AACAlzPolicy`](docs/Test-AACAlzPolicy.md)                                                 | Your management groups' policy assignments against the Azure Landing Zones reference (a local copy of the ALZ Library): what each archetype assigns that is missing, different or present - and the library file to deploy the missing ones from. |

### Microsoft 365 and Entra ID

Commands for the Microsoft 365 and Entra ID tenant: the Microsoft 365 assessment, group membership, and what applications and managed identities may do.

| Command                                                                                          | What it does                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`Invoke-AACM365Assessment`](docs/Invoke-AACM365Assessment.md)                                   | Microsoft 365 tenant discovery and security posture from the Microsoft Graph REST API with one token: Entra ID (settings, Conditional Access, admin roles, MFA registration, authentication methods), Microsoft 365 (domains, Secure Score, SharePoint and OneDrive sharing, audit logging) and Intune (enrollment restrictions, compliance, endpoint security, stale and unmanaged devices) - with zero-trust findings. A console view, an object, CSV and a tabbed HTML report. |
| [`Get-AACEntraGroupMembership`](docs/Get-AACEntraGroupMembership.md)                             | Entra ID groups and everyone in them - direct and through nested groups - one row per group and member, with type, source, guests and disabled accounts. A console view with each group's members flattened, objects, and CSV, PDF and interactive HTML reports.                                                                                                                                                                                                                                                                                                                                                                                  |
| [`Get-AACApplicationPermission`](docs/Get-AACApplicationPermission.md)                             | Every permission an enterprise application or managed identity holds - API (application) permissions, delegated consents, Entra directory roles with their scope (tenant, administrative unit, object; direct, through groups, PIM-eligible), Azure roles, owned objects and groups, and permissions requested but not granted - with findings for the privileged ones. By object ID, app ID, app registration ID, name or managed identity resource ID. A console view, objects, and CSV, HTML and PDF reports.|
| [`New-AACApplicationPermission`](docs/New-AACApplicationPermission.md)                             | Lets an enterprise application or managed identity manage specific Entra groups only - not every group, as GroupMember.ReadWrite.All would: an administrative unit with the groups, a custom (or built-in) role with just the group actions, assigned on the unit. Plan, confirm, apply, verify; flags (and with `-RemoveTenantWidePermission` removes) tenant-wide Graph permissions that would override the scope.|

### Azure DevOps

Commands for Azure DevOps organizations: projects, pipelines and the tools they run, repositories, security posture and delivery metrics.

| Command                                                                                          | What it does                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`Invoke-AACADOAssessment`](docs/Invoke-AACADOAssessment.md)                                         | One or more Azure DevOps organizations inventoried: projects, pipelines (YAML, or classic - flagged) with their last run and delivery metrics (success rate, duration, queue time, DORA deployment frequency and change failure rate), every task and CLI tool they use with versions - YAML, nested and cross-repository templates, and classic pipelines - and the security posture of service connections, variable groups, environments, branch policies and GitHub Advanced Security, with findings; branching strategy, a DORA assessment and everything a move to GitHub needs (variables, artifacts, test plans, agent pools, extensions). A PAT or your Azure sign-in; `-IncludeAzure` links service connections to Azure roles. A console view, objects, and CSV, HTML and PDF reports.|
| [`New-AACArchitectureBrief`](docs/New-AACArchitectureBrief.md) | A workload's requirements captured as an architecture brief: about 20 probe questions on the business, reliability, security, performance, cost and operations - asked at the prompt or taken from a file - with open decisions and assumptions. Offline. |
| [`Get-AACArchitecturePattern`](docs/Get-AACArchitecturePattern.md) | The Azure Architecture Center's cloud design patterns ranked against a brief: which fit, why, and their Well-Architected trade-offs. |
| [`New-AACArchitectureDesign`](docs/New-AACArchitectureDesign.md) | A design model from a brief and the chosen patterns: components, zones, settings and connections; the landing zone's inherited Azure Policy and allowed locations read live. |
| [`Test-AACArchitectureDesign`](docs/Test-AACArchitectureDesign.md) | A design validated before deployment against the Well-Architected Framework, inherited Azure Policy, your guardrails and PSRule for Azure: findings with remediation, a score per pillar, accepted risks, `-FailOnGap`. Tabbed HTML and PDF. |
| [`New-AACArchitectureDiagram`](docs/New-AACArchitectureDiagram.md) | A design drawn as Mermaid (and Markdown that renders it) and editable draw.io, with layers for WAF findings, Azure Policy, guardrails, PSRule and Azure Recommendations. |
| [`Export-AACArchitectureDecision`](docs/Export-AACArchitectureDecision.md) | Architecture decision records for a design - topology, each pattern, each accepted risk - with the open decisions and assumptions, as Markdown. |

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

## Operations and troubleshooting

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
| `Get-AACRoleAssignment` - RBAC assignments and effective access | `Get-AACAccessReview` (every assignment, PIM, classic admins, Entra roles and Graph app permissions, with a recommendation each) |
| `Get-AACServicePrincipalAccess` - permissions and recent use | `Get-AACAccessReview -PrivilegedOnly` for the access, `Get-AACOrphanedIdentity -Kind Application` for the unused ones |
| `Get-AACActivityLog` - administrative changes | `Get-AACChangeHistory` (what changed, who, before and after); failed actions and permission issues: `Get-AACResourceError` |
| `Get-AACBackupStatus` - backup health and recovery readiness | `Get-AACFailoverReadiness` (backups, restores, Site Recovery, vaults, recovery plans) |
| `Get-AACResourceDependencies` - upstream and downstream dependencies | `Get-AACDependencyGraph` (blast radius, single points of failure, a Graphviz export) |

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

## Azure tenant assessment

`Invoke-AACTenantAssessment` (`Invoke-AACAssessment` in 0.14 and earlier) assesses
a whole Azure tenant in one run - the command to run first in a tenant you
need to understand, and the module's take on
[Azure Resource Inventory (ARI)](https://github.com/microsoft/ARI): an inventory
of every resource type with the settings that matter for it and its policy
compliance, the organization, Advisor and retirements, Defender for Cloud,
Azure Policy compliance and inventory, the Well-Architected Framework, PSRule
for Azure, FinOps (savings, cost allocation, budgets), one list of
recommendations, outages, quotas and cost - as CSV files, a tabbed HTML
workbook, a PDF and interactive diagrams. Read-only, Resource Graph and REST
only: no Az modules, no Excel.

```powershell
Connect-AAC
Invoke-AACTenantAssessment -HtmlPath .\Tenant.html -PdfPath .\Tenant.pdf     # everything the account can see
Invoke-AACTenantAssessment -TenantId 'contoso.onmicrosoft.com' -Full -HtmlPath .\Contoso.html   # Defender, cost, tags, PSRule and quotas too
Invoke-AACTenantAssessment -ManagementGroupId 'mg-landingzones' -HtmlPath C:\Reports\LandingZones.html -CsvPath C:\Reports\csv -DiagramPath C:\Reports\diagrams
Invoke-AACTenantAssessment -SubscriptionId $sub -TagKey 'Environment' -TagValue 'Production' -Category Compute, Networking
Invoke-AACTenantAssessment -IncludeCost -CostTag 'CostCenter', 'Department'   # FinOps with your own cost-allocation tags
(Invoke-AACTenantAssessment -NoDisplay).Sheets['Resource recommendations'] | Where-Object Severity -In 'Critical', 'High'
(Invoke-AACTenantAssessment -NoDisplay).Sheets['All resources'] | Where-Object Policy -EQ 'Non-compliant'
```

The focused assessments go deeper into one discipline or service:
`Invoke-AACWafAssessment` reviews one workload against the Well-Architected
Framework with the team's answers (`-AttestationPath`), heat maps and the trend
from run to run; `Invoke-AACPolicyAssessment`, `Invoke-AACDefenderAssessment`
and `Invoke-AACGovernanceAssessment` go deeper into policy, security and
governance; the service assessments (AKS, Cosmos DB, Function Apps, Log
Analytics, Service Bus, storage accounts, virtual networks) into one service.

**How a run goes.** A live Spectre.Console progress display shows each phase as it
happens, and the run ends with a summary - what was found, what needs attention,
where the reports are and how long each phase took:

| Phase      | What it reads                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Scope      | The subscriptions in scope (by `-SubscriptionId`, `-ManagementGroupId` at any depth, or everything the account can see) and the tenant's management groups                                                                                                                                                                                                                                                                                                                                                                                       |
| Estate     | Every resource and resource group (`-ResourceGroupName`, `-TagKey`/`-TagValue` filter them), the resource types present, Advisor recommendations and retirements, Defender for Cloud (`-SecurityCenter`), Azure Policy compliance - by policy, resource group and resource (unless `-SkipPolicy`), support tickets                                                                                                                                                                                                                                 |
| Inventory  | A sheet per resource type present - about 95 types in 14 categories (`-Category` picks some): VMs, scale sets, disks, AKS and its node pools, container apps, SQL, Cosmos DB, PostgreSQL and MySQL, Redis, storage accounts, key vaults, virtual networks, subnets, peerings, NSG rules, firewalls, gateways, private endpoints, App Services, Log Analytics, Recovery Services and backup items, Arc servers, AI services and more - each with the settings that matter for it, as Resource Graph projections (only the types present are read) |
| Azure APIs | Per subscription: the Advisor score, reservation recommendations, the budgets, the last 6 months' outages (Resource Health service issues), compute quotas (`-QuotaUsage`) and VM sizes' vCPUs and memory (unless `-SkipVMDetail`); `-SkipApi` skips them                                                                                                                                                                                                                                                                                       |
| Well-Architected | `Invoke-AACWafAssessment`'s checks across the scope - the five pillars, scored by pillar, design principle and check - in one Resource Graph batch (unless `-SkipWaf`) |
| Cost       | Each resource's actual cost, this month and last (`-IncludeCost`)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| PSRule     | PSRule for Azure's rules on the resources (`-PSRule`) |
| Governance | The policy assignments in force and every policy they apply (unless `-SkipPolicy`); then the Well-Architected, FinOps and governance sheets and one list of recommendations |
| Reports    | The reports in `-Output` (all by default), then an upload to blob storage (`-StorageAccount`, `-StorageContainer`)                                                                                                                                                                                                                                                                                                                                                                                                                               |

Every inventory sheet (and All resources) adds, after its own columns, the
resource's **Retirement** notice (from Advisor), its **Advisor** recommendation
count, its **policy compliance** (Policy - Non-compliant, Compliant, Exempt or
Not evaluated; the number of policies it fails, and their names), its **WAF
gaps** (the Well-Architected checks it fails), its **PSRule failures** with
`-PSRule`, its **cost** with `-IncludeCost` and its **tags** with `-IncludeTag`.
`-Full` turns on `-SecurityCenter`, `-IncludeCost`, `-IncludeTag`, `-PSRule`
and `-QuotaUsage` at once. Overview sheets come first:
Subscriptions (management groups, counts, secure score, cost), Resource groups
(the empty ones flagged), Resource types, All resources; then Advisor
recommendations, Advisor score, Retirements, Security recommendations, Secure
score, Policy compliance, Outages, Quotas, Support tickets and Reservation
recommendations.

**Well-Architected.** Unless `-SkipWaf`, the same checks as
`Invoke-AACWafAssessment`, across the tenant:

| Sheet                 | What's in it                                                                                                   |
| --------------------- | -------------------------------------------------------------------------------------------------------------- |
| WAF pillars           | Each pillar's score out of 100 (checks weighted by severity) and its maturity: Initial, Developing, Established, Optimised |
| WAF design principles | Each design principle's score - or Not assessed, where only a review can tell                                   |
| WAF checks            | Each check: resources evaluated, passed and failed, its score and what to do                                    |
| WAF findings          | Each check a resource fails, most severe first, with the detail and what to do                                  |

**FinOps.** Every run adds (the cost sheets with `-IncludeCost`):

| Sheet                  | What's in it                                                                                                                                                                                                                                       |
| ---------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Savings opportunities  | One list by FinOps lever - Waste (unattached disks, unused public IPs, VMs stopped but still billed, empty App Service plans, old snapshots), Rightsizing and Rate (Advisor's cost recommendations, reservations, savings plans), Licensing (Azure Hybrid Benefit), Modernise (old VM generations) - with the resource's cost last month and an estimated annual saving |
| Cost allocation        | Per subscription: the resources with a cost-allocation tag (`-CostTag`; CostCenter, Project, Application ... by default), and the cost of those without                                                                                           |
| Budgets                | Each subscription's budgets - spent and forecast against the amount, the alerts - and the subscriptions with none                                                                                                                                |
| Cost by service        | Cost by resource type: this month so far, projected to the month's end, last month and the change                                                                                                                                                 |
| Cost by resource group | The same, by resource group                                                                                                                                                                                                                        |
| Top cost resources     | The 50 resources that cost the most                                                                                                                                                                                                                |

**A tab for each audience.** Every run also adds four tabs, each gap a
recommendation:

| Tab | Sheets |
| --- | --- |
| Identity and access (IT security) | **Privileged access** - Owner, User Access Administrator, Role Based Access Control Administrator and custom roles allowing `*`, at the root, management groups and subscriptions: who (user, group, service principal, managed identity, guest), and how - permanent, time-bound, activated or eligible in Privileged Identity Management; **Custom roles** and their wildcards; **Classic administrators**; **Defender plans** against the resources each subscription runs; **Expiring credentials** - Key Vault secrets, keys and certificates and app registration secrets and certificates expired or expiring within `-ExpiryDays` (30), values never read; **Management ports open** (SSH, RDP, WinRM from the internet); **Public network access** of PaaS services |
| Architecture | **Landing zone** - each management group's depth, subscriptions, and the policy and role assignments at each level; subscriptions directly under the root; **Regions** with availability zones and paired regions; **Resilience** of the critical resources - zones, Azure Backup, Site Recovery; **Network topology** - hub and spoke or Virtual WAN, each network's role, DNS, private DNS links and address overlaps; **Private DNS zones** (unlinked and duplicated zones) |
| Operations | **Diagnostic settings** coverage by type (a sample of up to 500 resources) and **Log Analytics workspaces**; **Monitoring** - Service Health alerts per subscription and **alert rules without an action group**; **Patch compliance** (Update Manager) and **Arc servers**; **Production locks**; the **Activity** Log over `-ActivityDays` (30) and **Failed deployments**; **Deprecated SKUs** (Basic public IPs and load balancers, unmanaged disks, Av1 VMs, classic resources, Application Gateway v1, single server databases...); **Naming and tags** - the Cloud Adoption Framework's abbreviations and owner tags (`-OwnerTag`) |
| Service delivery | **Subscription offers** and support plans; **Reservations** and **Savings plans** with how much of each is used; **Quota headroom** (with `-QuotaUsage`); the month-on-month **Cost trend** (with `-IncludeCost`); the **Ownership map** - subscription, resource group, owner tags and the subscription's Owners |

Production - a subscription or resource group name, or an Environment tag,
matching `-ProductionPattern` (prod, prd, production, live) - is judged more
strictly: backup, zones, locks, Dev/Test offers. `-SkipIdentity` leaves out
access and Microsoft Graph (principals and app registrations, which need
Application.Read.All); `-SkipKeyVault` the vaults' data plane (Key Vault
Reader and a network path); `-ActivityDays 0` the Activity Log. The API
versions templates use can't be seen from Azure: check them in your
infrastructure code.

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
| Resource recommendations     | Everything to act on in one list, most severe first: Advisor, Defender, retirements, unattached and empty resources, policy non-compliance, PSRule, the Well-Architected gaps and FinOps (budgets over or missing, untagged cost), each with a category and what to do |

**The reports** - each written only where its own parameter says (none by default; the sheets are always in the returned object's `Sheets`):

| Report                     | What's in it                                                                                                                                                                                                                                                                                                                               |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `-HtmlPath`                 | A tabbed workbook. Executive summary: tiles (each opening its table), charts that filter the table behind them (policies by status, non-compliant resources by resource group, recommendations by severity and category, the Well-Architected pillars, savings by FinOps lever, PSRule rules, resources by category, location, subscription and type, Advisor, Defender) and the tenant tree. Then Policy compliance, Policy inventory, Well-Architected, PSRule results, Resource recommendations, FinOps, Resources, Inventory, Advisor, Security and Health, each table with row details and a CSV download - searchable, filterable, groupable, each downloadable as CSV |
| `-PdfPath`                 | The summary, then each category with its sheets' key columns, bookmarked                                                                                                                                                                                                                                                                   |
| `-CsvPath` (a folder)      | A CSV file per sheet                                                                                                                                                                                                                                                                                                                       |
| `-DiagramPath` (a folder): `TenantAssessment-Network.html` | An interactive network diagram: virtual networks and subnets, peerings, gateways and connections, firewalls, Bastion, load balancers, application gateways, private endpoints and DNS zones, with NSGs and route tables (rules and routes) on what they apply to. `-DiagramFullEnvironment` draws every resource and how they connect      |
| `TenantAssessment-Organization.html` | An interactive diagram of management groups > subscriptions > resource groups, with resource counts                                                                                                                                                                                                                                        |
| `TenantAssessment-Resources.html` | Each subscription with a node per resource type (its Azure icon and count) - ARI's resources view, readable at any tenant size                                                                                                                                                                                                             |

**Automation.** In an Azure Automation runbook (PowerShell 7.4 runtime, this
module imported), `Invoke-AACTenantAssessment -Automation -StorageAccount <account>
-StorageContainer <container>` signs in with the account's managed identity,
writes plain progress lines to the job log and uploads the reports to blob
storage, under `TenantAssessment/<date>/` (every report, written to a
temporary folder, when no report path is given). The identity needs Reader on the management group or subscriptions
and Storage Blob Data Contributor on the storage account. The same works in a
pipeline with `Connect-AAC -ClientSecret` or `-CertificatePath` first.

**Tenants.** `-TenantId` takes the tenant's ID or one of its domains; the run
signs in to it first (in the browser) only when the current session is for
another tenant.

**Permissions.** Reader is enough for the inventory, Advisor, Policy, outages
and quotas; Security Reader for Defender (`-SecurityCenter`); Cost Management
Reader for `-IncludeCost`. What can't be read is listed in the summary and the
report, and the rest carries on.

## Resource export

`Export-AACResource` is the resource list you hand to someone else - a
spreadsheet for the owners, a PDF for an audit, an HTML report to filter in
the browser. One Azure Resource Graph query joins `resources` to
`resourcecontainers`, so every row has its subscription and management group
by name, not just an ID.

```powershell
Export-AACResource -CsvPath .\Resources.csv                                     # everything you can see
Export-AACResource -ManagementGroupId mg-landingzones -HtmlPath .\LZ.html -PdfPath .\LZ.pdf
Export-AACResource -SubscriptionId $sub -ResourceGroupName 'rg-app-*' -CsvPath .\App.csv
Export-AACResource -ResourceType 'microsoft.compute/virtualmachines' -NoDisplay | Select-Object Name, Location, Details
Export-AACResource -MissingTag CostCenter, Owner -CsvPath .\Untagged.csv        # tag governance
Export-AACResource -Tag @{ Environment = 'prod' } -Search sql
Export-AACResource -Filter "tostring(properties.provisioningState) != 'Succeeded'"
Export-AACResource -ResourceType 'microsoft.storage/storageaccounts' -Flatten -CsvPath .\Storage.csv
```

| Column | What it holds |
| --- | --- |
| `Name`, `ResourceType`, `Kind`, `Parent` | What it is; `Parent` names the server of a database, the vault of a secret |
| `ResourceGroup`, `Subscription`, `SubscriptionState` | Where it is, by name |
| `ManagementGroup`, `ManagementGroupPath` | The subscription's management group, and the path from the root (`Tenant Root Group > Contoso > Landing zones`) |
| `Location`, `Zones`, `Sku`, `Capacity` | Where it runs and how big it is |
| `Identity`, `ProvisioningState`, `PublicNetworkAccess`, `ManagedBy`, `Created` | How it is set up (`Created` when the type records it) |
| `Details` | The settings people look up, for about 25 types: a VM's size, OS, image and power state; a disk's size and state; a storage account's TLS, public access, shared key and network rules; a NIC's IP, VM and NSG; an App Service's plan, runtime and host; a SQL database's status and size; an AKS cluster's version and nodes; a key vault's soft delete, purge protection and RBAC... |
| `Tags`, `Tag: <key>` | All the tags on one line, and one column per tag key (`-TagColumn` picks them); keys that differ only in case are one tag |
| `ResourceGroupTags` | The resource group's tags, to see what a resource could inherit |
| `properties.*` | With `-Flatten`: every property, flattened (`properties.networkAcls.defaultAction`); lists of objects keep their first three items and a count |

Filters run in Resource Graph when they can, so only what you asked for
comes back: `-ResourceType`, `-ResourceGroupName` and `-Name` (exact; with
wildcards they run afterwards), `-Location`, `-Tag` (a value, or `'*'` for any)
and `-MissingTag`, and `-Filter` for a KQL condition of your own. `-Search`
then finds text anywhere in the name, type, group, subscription, location,
details, tags or ID. The subscriptions are read by up to four queries side by
side, each paged to the end.

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

## Security alerts

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
-- grp-finance ---------------------------------------------------------------
  Type        Security  Created  2024-01-15 09:30 UTC
  Source      Cloud     Owners   Ada Lovelace (ada@contoso.example); app-payroll (Service principal)
  Membership  Assigned  Members  3 direct - 1 nested group - 4 in all (1 guest, 1 disabled)

  DIRECT MEMBERS (3)
    Member             Type           Account
    Ada Lovelace       User           ada@contoso.example
    Gus Guest          User           gus_fabrikam.example#EXT#@contoso.example   GUEST
    grp-finance-emea   Nested group   its members are listed below

  NESTED GROUP grp-finance-emea (3 members)
    Member             Type                Account
    Ada Lovelace       User                ada@contoso.example
    app-payroll        Service principal
    Grace Hopper       User                grace@contoso.example   DISABLED
```

The **HTML report** opens on the same structure as a tree: every group with
its details and counts, opening to its owners, its direct members and its
nested groups, each nested group opening to its own members (a report of a
few groups opens all the way). Its tabs hold the groups, **Members** -
everyone in each group once, marked Direct, Nested or Direct and nested,
with the nested groups they come through - and every membership row. The
**PDF** gives each group a page: its details, then its direct members, then
each nested group's members.

**One row per group and member** (`AAC.EntraGroupMember`), the same in the
objects, HTML, PDF and `-CsvLayout Member` CSV: the group (name, type - Microsoft 365, Security,
Mail-enabled security, Distribution, dynamic, role-assignable - whether
it's cloud or synced from on-premises AD, its membership type - Assigned or
Dynamic - when it was created, and its owners), the member (name, type - user,
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
`Mail-Enabled Security / Role-Assignable` ...), Members (everyone in the
group, flattened: direct members and the members of every nested group at
any depth, each once, or `(No members)`) and NestedGroupMembers (every
nested group at any depth, by its path, with its own members:
`grp-finance-emea: Grace Hopper, Ada Lovelace; grp-finance-emea > grp-emea-audit: Linus Torvalds`),
then Owners (`Ada Lovelace (ada@contoso.example); app-payroll (Service principal)`
or `(No owners)`), CreatedDateTime (UTC) and MembershipType (Assigned,
Dynamic).
Service principals are listed with the other members.
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

## IP address management

`Get-AACIPAMReport` is IP address management without a server: no app to
deploy, no database to drift. Every run measures Azure's address space, read
from Azure Resource Graph, against your address plan.

```powershell
Get-AACIPAMReport -Open                                              # every network vs the private ranges, in your browser
Get-AACIPAMReport -AddressPlan .\ipam-plan.psd1 -HtmlPath .\IPAM.html -PdfPath .\IPAM.pdf
Get-AACIPAMReport -AddressPlan .\ipam-plan.psd1 -NextAvailable 24, 22 -View NextAvailable -NoDisplay
Get-AACIPAMReport -TestCidr 10.20.8.0/22                             # free? if not, who has it
Get-AACIPAMReport -ManagementGroupId mg-landingzones -View IpAddress -CsvPath .\ips.csv
```

The address plan is a `.psd1`, `.json` or `.csv` file (or a hashtable): spaces
holding blocks, plus external ranges (on-premises, partners) Azure must not
overlap. Without one, the private ranges (RFC 1918 and RFC 6598) are the plan.

```powershell
@{ Spaces = @(
    @{ Name = 'Corp'; Blocks = @(
        @{ Name = 'Azure-EU'; Cidr = '10.20.0.0/14' }
        @{ Name = 'Azure-US'; Cidr = '10.24.0.0/14' } ) } )
   External = @( @{ Name = 'London DC'; Cidr = '10.0.0.0/16' } ) }
```

- **Blocks:** the networks in each, the address space they take (overlaps
  counted once), free space, the largest free range, the next free range of
  the first `-NextAvailable` size and how many still fit; Warning at
  `-WarningPercent` (80), Critical at `-CriticalPercent` (90), Full.
- **Networks:** virtual networks, Virtual WAN hubs and external ranges -
  Managed, Partly managed or Unmanaged - with subnets, addresses used, address
  space in no subnet, DNS servers, peerings, overlaps and the Azure IPAM
  reservation tag (`X-IPAM-RES-ID`).
- **Subnets and IP addresses:** every address Azure counts in a subnet -
  virtual machines, scale set instances, private endpoints, load balancers,
  firewalls, gateways, Bastion, application gateways and unattached network
  interfaces - so a subnet's count and its list always agree.
- **Overlaps:** High when the networks are peered, Medium with an external
  range or a hub, Low when isolated.
- **Free space:** the best fit (the smallest free range a size fits, keeping
  larger ranges whole) and the lowest free address, and every free range.
- **HTML report:** a tab for each, the plan as a tree (space > block > network
  > subnet), a Space selector that filters every tab, and a card that follows
  the pointer over a row with its details.

It reads; it doesn't hand out reservations. For that, Azure IPAM keeps the
shared state; this report checks Azure against any plan, Azure IPAM's
included.

## Function App assessment

`Invoke-AACFunctionAppAssessment` assesses Azure Function Apps - Windows,
Linux, containers and Flex Consumption - read-only, REST only:

```powershell
Invoke-AACFunctionAppAssessment -HtmlPath .\Functions.html                       # every app you can see
Invoke-AACFunctionAppAssessment -Name 'func-orders-*' -TimeRange 30d -PdfPath .\Orders.pdf
Invoke-AACFunctionAppAssessment -View Finding -NoDisplay | Where-Object Pillar -EQ 'Security'
Invoke-AACFunctionAppAssessment -View Activity -ActivityDays 30 -NoDisplay | Where-Object Kind -EQ 'Configuration change'
```

- **App and plan:** hosting (Consumption, Flex Consumption, Elastic Premium,
  Dedicated, App Service Environment, Container Apps), SKU, instances, burst,
  zone redundancy, the plan's CPU and memory.
- **Usage over `-TimeRange` (7d):** executions, GB-seconds, requests, 5xx and
  4xx, error rate, response time, memory; an estimated monthly cost on
  Consumption (before the free grant); idle apps.
- **Functions:** every function with its trigger (HTTP and its auth level,
  timer and its schedule, queue, Service Bus, Event Hubs...) and bindings.
- **Runtime:** the Functions runtime, the language version against its end
  of support, and the .NET in-process model (support ends 10 November 2026).
- **Configuration:** every setting that matters, by area, and the app
  settings by name and kind (Key Vault reference, identity-based, key or
  connection string, plain) - values are never read into the report. Listing
  app settings needs Website Contributor (or a custom role with
  `Microsoft.Web/sites/config/list/action`); without it they are left out and
  said so. `-SkipSettings` doesn't ask.
- **Networking, deployment, backups, connections:** inbound access, the SCM
  site, VNet integration, CORS; the deployment center, recent deployments and
  slots; backups where the plan supports them; Service Connector connections
  and the Key Vaults, storage accounts, Service Bus and Cosmos DB accounts
  named in settings, with how each authenticates.
- **Activity Log (`-ActivityDays`, 7):** restarts, stops, configuration
  changes, deployments, slot swaps, settings and keys read - who, when, and
  whether it worked.
- **Well-Architected, PSRule, Advisor, Defender:** about 30 checks across the
  five pillars, PSRule for Azure on the apps and plans (`-SkipPSRule`), and
  Advisor and Defender recommendations - every failure a finding.

The HTML report has a tab per audience: a service summary for service
delivery managers, apps and plans for architects, configuration and
networking for administrators, findings for IT security - an App selector
that filters every tab, and hover cards.

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

## Storage account assessment

`Invoke-AACStorageAccountAssessment` brings Azure Monitor's **Storage
accounts** workbook to the prompt and the reports, and adds what the
workbook doesn't check:

```powershell
Invoke-AACStorageAccountAssessment                                              # every account, the last day
Invoke-AACStorageAccountAssessment -TimeRange 4h                                # the workbook's default period
Invoke-AACStorageAccountAssessment -ResourceGroupName 'rg-data' -HtmlPath .\Storage.html -PdfPath .\Storage.pdf
Invoke-AACStorageAccountAssessment -View Finding -NoDisplay | Where-Object Signal -EQ 'Security'
Invoke-AACStorageAccountAssessment -NoDisplay | Sort-Object UsedGB -Descending | Select-Object -First 10 Account, UsedGB, AccessTier, LifecycleRules
```

- **Overview** (the workbook's first tab): transactions, end-to-end and
  server latency, and errors by response type, plus availability, ingress
  and egress. Response types are grouped as Success, Throttling, Server,
  Authorization, Network and Client. Client errors (404, 409) are often
  normal, so they aren't counted as errors.
- **Capacity** (the workbook's second tab): used capacity and blob, file,
  queue and table capacity, with blob, container and file share counts. It
  shows the latest value, read over at least two days, because Azure reports
  capacity hourly or daily.
- **Security & protection:**
  - HTTPS, TLS, anonymous blob access, network access and private endpoints;
  - shared keys, key age, and key and SAS expiry policies;
  - cross-tenant replication, encryption, blob logs and Defender for
    Storage;
  - redundancy, blob, container and file share soft delete, versioning,
    change feed, point-in-time restore and lifecycle rules.
- **Findings**, worst first, under seven signals: availability, errors,
  throttling, latency, security, protection and cost. The heat map scores
  each account 0-100 on every signal, and clicking a cell in the HTML report
  lists its findings.

It reads Resource Graph, Azure Monitor metrics and each account's service
settings: Reader is enough. It reads no data and no keys.

## Service Bus assessment

`Invoke-AACServiceBusAssessment` looks at every Service Bus namespace - and
every queue, topic and subscription in it:

```powershell
Invoke-AACServiceBusAssessment                                                  # every namespace, the last day
Invoke-AACServiceBusAssessment -View Entity -NoDisplay | Where-Object DeadLetters | Sort-Object DeadLetters -Descending
Invoke-AACServiceBusAssessment -ResourceGroupName 'rg-integration' -TimeRange 7d -HtmlPath .\ServiceBus.html -PdfPath .\ServiceBus.pdf
Invoke-AACServiceBusAssessment -View Finding -NoDisplay | Where-Object Signal -EQ 'Security'
```

- **Overview:** requests, server and client errors and throttled requests
  over the period, messages in and out, and for Premium the CPU and memory
  of the messaging units.
- **Entities:** every queue, topic and subscription as it is now - active,
  dead-lettered, transfer dead-lettered and scheduled messages, size against
  its maximum, delivery and lock settings, and when it was last used.
- **Security & resilience:** TLS, SAS keys (and namespace-wide Manage
  keys), network access and private endpoints, encryption, logs, zone
  redundancy and geo-disaster recovery.
- **Findings**, worst first, under six signals: health, capacity, messages,
  security, resilience and cost - dead letters, entities filling up (sends
  fail at 100%), backlogs, topics with no subscription, expired messages
  dropped, throttling, CPU and memory, SAS keys, open networks, no logs, no
  zones or Geo-DR, idle entities and too many messaging units. The heat map
  scores each namespace 0-100 on every signal.

It reads Resource Graph, Resource Manager and Azure Monitor metrics: Reader
is enough. It reads no messages and no keys.

## Cosmos DB assessment

`Invoke-AACCosmosDBAssessment` looks at every Azure Cosmos DB account, in
every API (NoSQL, MongoDB, Cassandra, Gremlin, Table):

```powershell
Invoke-AACCosmosDBAssessment                                                    # every account, the last day
Invoke-AACCosmosDBAssessment -NoDisplay | Where-Object Throttled | Select-Object Account, Throttled, ThrottleRate, NormalizedRuMax, ProvisionedRU, AutoscaleMaxRU
Invoke-AACCosmosDBAssessment -View Container -NoDisplay | Where-Object ThroughputMode -EQ 'Manual' | Sort-Object RU -Descending
Invoke-AACCosmosDBAssessment -ResourceGroupName 'rg-data' -TimeRange 7d -HtmlPath .\CosmosDB.html -PdfPath .\CosmosDB.pdf
```

- **Overview:** service availability, requests by status code - rate
  limited (429), server errors (5xx), client errors (404, 409 and 412 are
  counted apart: they are often normal) - request units, the busiest
  partition's share of its throughput, server-side latency, and the latest
  data, index and document counts.
- **Containers:** every database and container with its partition key, its
  throughput (autoscale, manual, shared database or serverless) and RU/s,
  default TTL, analytical store and indexing.
- **Security & resilience:** network access and private endpoints, account
  keys, TLS, encryption, logs and Defender for Azure Cosmos DB; regions,
  automatic failover, availability zones, consistency and backup.
- **Findings**, worst first, under six signals: availability, throttling,
  errors, security, resilience and cost - rate limiting, running close to
  the throughput, single regions, no failover, periodic backup only, open
  networks, keys, throughput higher than needed and many small containers
  with their own throughput. The heat map scores each account 0-100 on
  every signal.

It reads Resource Graph, Resource Manager and Azure Monitor metrics: Reader
is enough. It reads no documents and no keys.

## Application permission

`Get-AACApplicationPermission` lists **everything an enterprise application or
managed identity can do** - in one place, where the portal spreads it over the
application's API permissions, Roles & admins, administrative units and each
Azure scope's Access control:

```powershell
Get-AACApplicationPermission -Identity 'My-Enterprise-App'
Get-AACApplicationPermission -Identity <app-id or object-id> -NoDisplay | Where-Object Kind -EQ 'Directory role'
Get-AACApplicationPermission -Identity '/subscriptions/<id>/resourceGroups/rg-app/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-app'
'app-one', 'app-two' | Get-AACApplicationPermission -HtmlPath .\AppPermissions.html -CsvPath .\AppPermissions.csv
```

- **Rows, by kind:** application permissions (each API's app roles -
  tenant-wide), delegated permissions (consented for everyone, or one user),
  directory roles with their scope (tenant, administrative unit with the
  objects it covers, or one object; direct or through a role-assignable group),
  PIM-eligible roles, Azure roles (direct or through a group; `-SkipAzure`
  leaves them out), owned applications and groups, group memberships, and API
  permissions the app registration asks for that were never granted.
- **Findings:** privileged application permissions (`Directory.ReadWrite.All`,
  `RoleManagement.ReadWrite.Directory`, `AppRoleAssignment.ReadWrite.All`,
  `Mail.Send`...), privileged directory roles at tenant scope, Azure Owner or
  User Access Administrator, Contributor on a subscription, privileged
  delegated scopes consented for everyone, owning another application.
- **Identity:** service principal object ID, application (client) ID, app
  registration object ID, display name, or the Azure resource ID of a
  user-assigned identity (or of a resource with a system-assigned one).
  `-View Permission|Finding|Summary`.

### Scoped group rights: New-AACApplicationPermission

`New-AACApplicationPermission` lets an enterprise application (or managed
identity) add and remove members in **specific groups only**. Microsoft Graph
application permissions are tenant-wide - `GroupMember.ReadWrite.All` covers
every group, and there is no "selected groups" version of it - so the same
rights are given with Entra's own scoping instead:

1. an **administrative unit** holding exactly the groups,
2. a **directory role** with just the group actions (a custom role, created
   or updated; or a built-in one, used as it is),
3. that role **assigned to the application on the unit** - not the tenant.

```powershell
Connect-AAC
New-AACApplicationPermission -ServicePrincipal 'My-Enterprise-App' -Group 'SG-Group-One', 'SG-Group-Two' -WhatIf   # the plan
New-AACApplicationPermission -ServicePrincipal 'My-Enterprise-App' -Group 'SG-Group-One', 'SG-Group-Two' -RemoveTenantWidePermission
New-AACApplicationPermission -ServicePrincipal 'func-myapp-prod' -Group 'SG-Group-One' -Access MemberRead
New-AACApplicationPermission -ServicePrincipal 'My-Enterprise-App' -Group 'SG-Group-One' -AllowedResourceAction 'microsoft.directory/groups/standard/read', 'microsoft.directory/groups/members/read', 'microsoft.directory/groups/members/update' -RoleName 'Group Member ReadWrite (Scoped)'
```

- **Idempotent:** what exists is read and only what is missing is written;
  the plan is shown and you are asked first (`-Force` or `-Confirm:$false`
  for pipelines, `-WhatIf` for the plan only). After the apply everything is
  read again; running the command again plans no changes.
- **Access:** `-Access MemberReadWrite` (default - the rights of
  `GroupMember.ReadWrite.All`), `MemberRead`, `MemberAndOwnerReadWrite`, or
  your own group actions with `-AllowedResourceAction`. `-RoleName` names the
  custom role, or picks a built-in one (`Groups Administrator`).
- **Findings** - what would undo the scope or not work: a tenant-wide Graph
  permission (`GroupMember.ReadWrite.All`, `Group.ReadWrite.All`,
  `Directory.ReadWrite.All` - `-RemoveTenantWidePermission` removes it), the
  same role at tenant scope, other objects in the unit, dynamic groups,
  role-assignable groups.
- `-RestrictedManagement` creates the unit with restricted management, so
  tenant-wide group administrators can't change its groups either.
- **Needs** Privileged Role Administrator (or Global Administrator) for the
  sign-in, and Microsoft Entra ID P1. The application's code doesn't change;
  its token may be cached for up to an hour (24 hours for a managed
  identity) before the change takes effect.

## Architecture design

Six commands take a workload from requirements to a validated, drawn and
recorded design - offline (only the landing zone's policy is read from
Azure, and `-Offline` skips that):

```powershell
$brief = New-AACArchitectureBrief -Name 'orders-api' -OutPath .\orders-api.brief.json      # the probe questions, at the prompt
Get-AACArchitecturePattern -Brief $brief                                                    # the patterns that fit, and why
$design = Get-AACArchitecturePattern -Brief $brief -RecommendedOnly -NoDisplay |
    New-AACArchitectureDesign -Brief $brief -Region westeurope, northeurope -LandingZone 'mg-landingzones' -OutPath .\orders-api.design.json
Test-AACArchitectureDesign -Design $design -GuardrailPath .\guardrails.psd1 -HtmlPath .\orders-api.validation.html
New-AACArchitectureDiagram -Design $design -Path .\docs\architecture                        # .mmd, .md and .drawio
Export-AACArchitectureDecision -Design $design -Path .\docs\adr -Owner 'Platform architecture'
```

| Step | What it does |
| --- | --- |
| Brief | About 20 probe questions, each tied to a Well-Architected pillar: workload kind and criticality; RTO, RPO, SLA, degraded running; data classification, frameworks, exposure, identity; read/write mix, response target, load, geographies, data store; budget and baseline; deployment, observability, landing zone. `-Answer` or `-AnswerPath` gives answers; `?` means "don't know" - the default is used and the question stays open; unanswered questions are recorded as assumptions. |
| Patterns | Fifteen cloud design patterns from the Azure Architecture Center, each with fit rules over the answers (and the reason), its effect on each pillar, and a score weighted by what the brief values. |
| Design | Components from the answers and the patterns (compute for the workload kind, the data store, Front Door or Application Gateway with the WAF, hub and spoke with private DNS and Azure Firewall where the data and exposure call for them, Key Vault, monitoring, a budget, the pipeline with its PSRule gate), their settings (zones, private endpoints, identity, TLS, purge protection), a second region when the RTO or SLA needs one, and the landing zone's inherited policy and allowed locations. `-Override` changes any component. |
| Validate | Rules with a pillar, severity, the built-in Azure Policy and PSRule for Azure rule they correspond to, the Advisor category and the fix. Blocking: what an inherited Deny policy or your guardrails would refuse. `-Accept` records an accepted risk; `-FailOnGap` fails a pipeline on open Blocking or High findings. |
| Diagram | Mermaid, Markdown (renders in Azure DevOps wikis, GitHub, VS Code) and draw.io - components coloured by their worst finding, with layers for WAF, Azure Policy, guardrails, the PSRule gate and Azure Recommendations. The draw.io has five pages: Cover, Architecture (Azure icons in landing zone, region, virtual network and data boxes), Policy and compliance, Findings and Legend. |
| Decisions | ADRs: hosting and topology, each pattern, each accepted risk (reason, owner, review date), with an index of open decisions and assumptions. |

Guardrails are a .psd1 or .json file of the organisation's own rules:
`@{ AllowedRegions = @('westeurope', 'northeurope'); DenyPublicEndpoint = $true;
DeniedSkus = @('Basic*'); RequiredTags = @('CostCenter', 'Owner') }`. Every
brief, design and decision record carries the catalog version it was made with,
and Test-AACArchitectureDesign says when a design was made with an older one.
The policy display names and PSRule rule names in the catalog are references to
verify against current Microsoft data.

## Azure DevOps assessment

`Invoke-AACADOAssessment` (`Get-AACADOInventory` in 0.14 and earlier) assesses
one or more Azure DevOps organizations - read-only, through the Azure DevOps
REST API:

```powershell
$pat = Read-Host -Prompt 'Azure DevOps PAT' -AsSecureString
Invoke-AACADOAssessment -Organization contoso -PersonalAccessToken $pat                       # every project
Invoke-AACADOAssessment -Organization contoso -PersonalAccessToken $pat -HtmlPath .\ADO.html -PdfPath .\ADO.pdf -CsvPath .\ADO.csv
Invoke-AACADOAssessment -Organization contoso -PersonalAccessToken $pat -View Task -NoDisplay | Where-Object Kind -EQ 'CLI'
Invoke-AACADOAssessment -Organization contoso -PersonalAccessToken $pat -View ServiceConnection -NoDisplay | Where-Object OpenToAllPipelines
Invoke-AACADOAssessment -Organization contoso -Project Payments -PersonalAccessToken $pat -YamlPath .\pipelines -Skip Security, Metrics
Invoke-AACADOAssessment -DiscoverOrganization -UseAzureSignIn -IncludeAzure -HtmlPath .\ADO.html   # with Connect-AAC: every organization, no PAT
Invoke-AACADOAssessment -Organization contoso -PersonalAccessToken $pat -View SbomComponent -NoDisplay | Where-Object Component -EQ 'log4j-core'   # who ships it
```

- **SBOM:** which build pipelines produce a software bill of materials - the
  [Microsoft SBOM Tool](https://github.com/microsoft/sbom-tool) (`sbom-tool
  generate`, the Manifest Generator task, `GenerateSBOM=true` in a .NET
  project), 1ES Pipeline Templates, Syft, CycloneDX, Trivy or Docker - and
  which validate one (`sbom-tool validate`). From each one's **latest
  successful run**, the SBOM it published - the `_manifest/spdx_2.2` (or
  `spdx_3.0`) `manifest.spdx.json`, or any SPDX or CycloneDX JSON file in its
  artifacts: its format, the tool that made it, components and files,
  completeness against the NTIA minimum elements (name, version, supplier,
  package URL), licences by kind (permissive, weak or strong copyleft,
  unknown), and every component with its version, ecosystem, supplier and
  licence - so when a vulnerable package is announced, one filter says which
  pipelines ship it. Findings: pipelines that deploy or publish with no SBOM,
  an SBOM generated but not published, incomplete SBOMs, strong copyleft
  licences, SBOMs never validated. `-Skip Sbom` leaves the artifacts unread;
  reading them needs the token's Build (Read) scope.

- **Pipelines:** every build pipeline - **YAML**, or **classic** (built in
  the designer, with no YAML file: flagged) - and every classic release
  pipeline, with its last run, the repository's last push, the service
  connections, variable groups and environments it uses, and the Azure
  subscriptions it reaches.
- **How tools are found:** one catalogue of about 150 tools - each with its
  category, what it does and the regular expression that finds it - is matched
  against **every file a pipeline runs**:
  - its YAML and the templates it includes - local, or from another Azure
    Repos repository (`template@repo` through `resources: repositories`),
    nested to `-TemplateDepth` (3) - with comments, `displayName:` and
    `template:` lines left out;
  - the **script files** it calls (`filePath:` / `scriptPath:` inputs,
    `./deploy.sh`, `pwsh -File build.ps1`...) and the scripts those call, from
    the pipeline's repository (`-MaxScriptFiles`, 25 a pipeline);
  - the **package.json scripts** `npm run` / `yarn` / `pnpm` run (with their
    `pre`/`post` scripts) and the **Makefile targets** `make` runs;
  - a classic pipeline's tasks (mapped from task IDs to names);
  - **container images** (`ghcr.io/fluxcd/flux-cli:v2.3.0` is Flux, version
    v2.3.0).
- **Categories:** Lint, Build, Test, Security, Deploy, Publish, **GitOps**
  (Flux, Argo CD, Kustomize) and Tooling (az, git, jq, Node.js...). The
  findings - no linting, no tests, no security scanning - read them, for YAML
  and classic pipelines alike.
- **Report tabs for tools:**
  - **Tools** - one row per tool: category, pipelines, projects, the versions
    seen (an installer task such as `UseNode@1`, an image tag, or "agent
    default") and how it was found;
  - **Coverage** - per pipeline, Yes / No for each stage;
  - **Evidence** - every match: pipeline, tool, version, how it was found
    (task, inline script, script file, package.json, Makefile, image, classic
    task), file, line and the line itself, with credentials masked;
  - **Unrecognised** - commands scripts run that no rule knows, most-run
    first (a tool missing from the catalogue shows here), and the templates
    and script files that couldn't be read, with the reason (a path built from
    a variable, a GitHub repository...);
  - **Tasks** (`-View Task`) - every task with its major version and what it
    does, packages installed at a version (`npm install -g x@1.2`,
    `Install-Module -RequiredVersion`...), shells, containers, hosted images
    and pools.
- **Tools of your own:** `-ToolRule @(@{ Category = 'Deploy'; Tool = 'Acme
  Deployer'; Pattern = 'acme-deployer\s+push'; Purpose = 'Pushes a release' })`,
  or a team file with `-ToolRulePath .\rules.psd1`
  (`@{ Rules = @( @{ ... }, ... ) }`, or a JSON list).
- **Security posture:** service connections open to every pipeline, signing
  in with a client secret instead of workload identity federation, or
  unused; variable groups with secrets kept outside Key Vault, secret-looking
  variables not marked secret (names only - never values), or open to every
  pipeline; production environments with no approval, environments with no
  checks or open to every pipeline; default branches with no required
  reviewers or build validation; **GitHub Advanced Security for Azure
  DevOps** per repository (on, off) with its active alerts by type and
  severity.
- **Delivery metrics** over `-MetricDays` (30): each pipeline's runs, success
  rate (cancelled runs left out), average duration and queue time, runs a
  week; each environment's deployments, deployments a week and **change
  failure rate** (DORA).
- **Who to contact** (`-View Member`, the People tab): each project's
  **Project Administrators** (people, or groups in that group), its **team
  admins** and **team members** - one row per person with their roles and
  teams - and on each project row the first contacts (administrators, then
  team admins) with their e-mail. `-Skip Members` leaves them out.
- **Branching** (`-View Branch`, `-View BranchPolicy`): every branch with its
  role from its name (default, develop, release/\*, hotfix/\*, feature/\*,
  personal), last commit, ahead and behind the default branch, stale after
  `-StaleBranchDays` (90) and the policies on it; each repository's
  **branching strategy** - GitFlow, trunk-based with release branches,
  trunk-based / GitHub flow, feature branching or single branch - with its
  tags, open pull requests and Git LFS. Every **branch policy**, on or off,
  with its settings in words and its GitHub equivalent (rulesets, CODEOWNERS).
  `-Skip Branches` leaves the branches out.
- **DORA** (`-View Dora`, the DORA tab): per project and for the
  organization, the four keys over `-MetricDays` - deployment frequency, lead
  time (run queued to deployed), change failure rate and time to restore (a
  failed deployment to the next success) - from production environments and
  classic release stages (every environment when a project has none), each
  banded **Elite, High, Medium or Low**; overall is the weakest.
- **Moving to GitHub** (the Variables, Artifacts, Test plans, Agents and
  extensions and Migration tabs): every **variable** by name - pipeline
  settings, YAML and variable groups, secret or not, never values - with where
  it goes on GitHub; **Azure Artifacts** feeds and their packages, and whether
  GitHub Packages can hold them (npm, NuGet, Maven - not PyPI, Universal
  Packages or Cargo); **test plans** (no GitHub equivalent); agent pools and
  their agents; marketplace **extensions** and the pipelines whose tasks come
  from them; **Advanced Security settings** per repository and project;
  wikis and service hooks. `-View Migration` sums it up per project with rough
  effort points (classic pipelines, marketplace tasks, secrets, feeds, test
  plans, large or LFS repositories weigh most) and a complexity; `-View
  MigrationMap` says where each kind of thing lands on GitHub and the tool
  that moves it (GitHub Enterprise Importer, GitHub Actions Importer...).
  `-Skip Migration` leaves this data out; the PAT needs Packaging, Test
  Management, Wiki, Agent Pools and Extensions (Read).
- **One project at a time, in the HTML report:** a **Project** selector at the
  top filters every tab to the project chosen - its pipelines, tasks, tools'
  evidence, coverage, repositories, service connections, variable groups,
  environments and findings - and shows a card with the project's facts, who
  to contact, and how many rows each table has for it, each a link. Tiles and
  charts stay organization-wide; the tool matrix and the unrecognised list
  say they aren't by project.
- **Several organizations:** `-Organization contoso, fabrikam`, or
  `-DiscoverOrganization` for every organization your sign-in belongs to.
  Rows carry an Organization column.
- **Disabled repositories** are left out, with the pipelines that build
  them (the report says how many); their YAML is never read.
  `-IncludeDisabledRepository` lists them, each pipeline with a finding.
- **Progress:** each stage of the read, and the analysis, shows the
  projects done, the time left and the project being read.
- **Offline review:** `-YamlPath .\pipelines` saves every pipeline's YAML,
  the templates it includes, and each classic pipeline's steps (as JSON) -
  ready to review or diff.
- **Azure link:** `-IncludeAzure` (after `Connect-AAC`) follows each Azure
  service connection to its service principal and the Azure roles it holds,
  and flags pipeline identities that are Owner (or can grant access) or
  Contributor on a whole subscription.
- **Findings** also cover classic, stale, failing and disabled pipelines,
  deprecated or older task versions, unpinned container images, retired
  hosted images, a value that looks like a secret written into the YAML (its
  key and line - never the value), unreliable pipelines and long queues, and
  idle repositories.
- **Signing in:** `-PersonalAccessToken` (a SecureString; read scopes:
  Build, Code, Project and Team, Release, Service Connections, Variable
  Groups, Environment, Advanced Security, Identity), the `AZURE_DEVOPS_EXT_PAT`
  environment variable, or `-UseAzureSignIn` - your `Connect-AAC` sign-in,
  for organizations connected to your tenant. The token goes only to Azure
  DevOps and is never written anywhere.
- YAML in GitHub or another non-Azure Repos repository can't be read through
  Azure DevOps: the pipeline says so. `-Skip Yaml, Security, Metrics,
  AdvancedSecurity, Members` leaves parts out, to read faster.

`-View` returns (and writes to `-CsvPath`) Pipeline, Project, Repository,
Task, Tool, Evidence, Coverage, Unrecognised, ServiceConnection, VariableGroup,
Environment, Member or Finding rows;
`-HtmlPath` and `-PdfPath` write a report with a tab for each.

## Terraform export

`Export-AACTerraform` turns resources you already have into Terraform,
through Azure's own [Export for Terraform API](https://learn.microsoft.com/rest/api/terraform/terraform/export-terraform).
The export is a long-running operation: the command submits it, polls it as
Azure asks (`Retry-After`), shows its progress, and writes a folder you can
run straight away.

```powershell
Export-AACTerraform -ResourceGroupName rg-app -Path .\terraform\rg-app
Export-AACTerraform -ResourceGroupName rg-platform -BatchSize 50 -Path .\terraform\platform   # a large one, in batches at once
Export-AACTerraform -Resume -Path .\terraform\platform                                       # collect one still running
Export-AACTerraform -ResourceGroupName rg-hub, rg-spoke -FallbackToAzApi -Plan -Path .\terraform\network
Export-AACTerraform -Query 'type =~ "microsoft.keyvault/vaults"' -Include RoleAssignment, Lock -Path .\terraform\vaults
Get-AACUnusedResource -NoDisplay | Export-AACTerraform -Path .\terraform\unused   # piped by ID
```

The folder:

| File | What |
|---|---|
| `terraform.tf` | The providers the configuration needs |
| `providers.tf` | The provider blocks, with the subscription ID |
| `main.tf` | The resources |
| `azapi.tf` | With `-FallbackToAzApi`: what azurerm couldn't export, as azapi resources |
| `import.tf` | Import blocks: `terraform plan` brings the existing resources under Terraform, with no `terraform import` to run |
| `export.json` | What was asked, what was skipped and why |
| `plan.json` | With `-Plan`: the plan, for `Get-AACTerraformPlan` |

- **Large exports, faster.** The export runs on Azure's side and its time
  grows with the number of resources - a large resource group takes
  minutes. The command counts the resources first and says when an export
  is large (and which types are often left out with `-ExcludeType`).
  `-BatchSize 50` splits it into exports of 50 resources that run at the
  same time (`-ThrottleLimit`, 8 at once by default) and merges them into
  one folder: each batch has names of its own (`res-b1-0`), and a resource
  two batches both return is kept once. Several subscriptions are exported
  at the same time too.
- **Progress you can read.** Each export shows its status, how long it has
  run and how many batches are done - Azure gives no percentage.
- **Stop and come back.** The operations are saved in `export.json` as soon
  as Azure accepts them. After Ctrl+C, or when `-TimeoutMinutes` (30) runs
  out, the export goes on in Azure: `-Resume -Path <folder>` collects it
  without exporting again.
- **Three ways to choose.** Resource groups (several in one subscription
  are exported together, with their child resources, so their names can't
  clash), resource IDs (or anything piped with an `Id` or `ResourceId`), or
  a Resource Graph where-clause. Several subscriptions get a folder each.
- **Nothing silently dropped.** A type the azurerm provider doesn't support
  yet is listed as Skipped; `-FallbackToAzApi` exports those again with the
  azapi provider, which covers every Azure resource type, and merges both
  into one module.
- **Proved with `-Plan`.** It runs `terraform init`, `validate` and `plan`
  in the folder and reads the plan as `Get-AACTerraformPlan` does. A
  faithful export plans only imports; anything else is what the export
  didn't capture, listed by address. Terraform signs in on its own (`az
  login`, or `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET` and `ARM_TENANT_ID`).
- **Safe.** The export reads Azure and changes nothing there. Sensitive
  values are masked unless `-IncludeSensitive`; Terraform files already in
  the folder aren't overwritten without `-Force`.
- **The resource provider.** The API needs `Microsoft.AzureTerraform`
  registered on the subscription. When it isn't, the command says so;
  `-RegisterProvider` registers it (it asks first, and honours `-WhatIf`).
- `-Provider azapi`, `-Include` (the resource group, role assignments,
  locks, diagnostic settings, Azure-managed resources), `-Recurse`,
  `-Exclude`, `-ExcludeType`, `-NamePrefix` and `-Compact` map to the API's
  options. The API is in preview (`2026-09-01-preview`); `-ApiVersion`
  picks another.

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

## Network topology

`Show-AACNetworkTopology` draws the networks of the whole tenant - or of
management groups, subscriptions or regions - and opens the diagram in your
browser. Read-only, with Resource Graph; Reader is enough.

```powershell
Show-AACNetworkTopology                                                     # every network you can see
Show-AACNetworkTopology -ManagementGroupId 'mg-landingzones' -GroupBy Subscription -Layout Hierarchy
Show-AACNetworkTopology -NetworkOnly -Location 'uksouth', 'ukwest' -Theme Light -HtmlPath .\Network.html -NoBrowser
(Show-AACNetworkTopology -NoBrowser -PassThru).Findings | Where-Object Severity -EQ 'High'
```

**What it reads**, in every region:

- virtual networks, subnets and peerings, across subscriptions and to
  networks you can't see
- VPN and ExpressRoute gateways, connections, circuits and local gateways;
  Virtual WAN and its hubs
- Azure Firewalls, network virtual appliances (VMs whose NIC forwards IP
  traffic), NSGs, route tables, NAT gateways, Bastion, load balancers,
  Application Gateways, private link services and DNS resolvers
- VMs, scale sets and private endpoints in their subnets, and the PaaS
  resources the endpoints serve (`-NetworkOnly` leaves these out)

A peering outside the scope is followed to the network at its other end, and
a route's next hop to the firewall or appliance that owns the IP, so a
spoke's diagram reaches its hub.

**Roles.** Each network is a **hub** (gateway transit, or a gateway, firewall
or appliance and peerings, or three or more peerings), a **spoke** of a hub,
**peered** or **standalone**.

**Two layouts**, switched at the top of the page:

| Layout                  | What you see                                                                                                                                                                                                                 |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Hub & spoke (`-Layout HubSpoke`) | Each hub at the centre, its spokes in rings around it, hubs side by side, other networks below. Each network's box names its subscription, region and resource group. The default when there are hubs with spokes. |
| Hierarchy (`-Layout Hierarchy`)  | Boxes inside boxes, packed in a grid: tenant, management group, subscription, region, resource group, network, subnet (`-GroupBy Subscription` or `Region` for fewer levels).                                     |

In both, subnets are drawn in rows inside their network, as wide as their
prefix is big, and resources in a grid inside their subnet. A VM shows its
NIC's IPs and NSG; an appliance is outlined in the route colour.

**The lines.** Peerings between networks, with their state and what they let
through (red and dashed when not Connected); private endpoints to the PaaS
they serve; routes from a subnet to the firewall or appliance that inspects
its traffic (one line per spoke in the hub & spoke view); a gateway's
connections and circuits. Subnets in a network reach each other through
Azure's system routes, so no lines are drawn between them.

**At the prompt**, tiles, the hubs with their transit (firewall, gateway,
appliance) and spokes, and findings:

| Severity | Finding                                                                                                   |
| -------- | --------------------------------------------------------------------------------------------------------- |
| High     | A peering that isn't Connected; a route to an IP no resource you can see has                              |
| Medium   | A spoke subnet with VMs whose internet traffic isn't sent through a firewall or appliance (no `0.0.0.0/0`) |
| Info     | A peering to a network you can't see (another tenant, or no Reader); a standalone network                 |

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
- **draw.io**: the map as you see it, as an editable draw.io diagram (see
  [Editable diagrams](#editable-diagrams-drawio)).

The page is one self-contained file that opens offline. Its layout comes from
the [Eclipse Layout Kernel](https://eclipse.dev/elk/) (`elkjs`, EPL-2.0), and
it uses Microsoft's
[Azure architecture icons](https://learn.microsoft.com/azure/architecture/icons/),
under Microsoft's terms for architecture diagrams. `-PassThru` also returns
the map's resources and connections as objects, e.g. `(... -PassThru).Nodes |
Where-Object Orphan`.

## Editable diagrams (draw.io)

`Export-AACDiagram` draws your existing resources as a diagram you can
**edit** - not a picture. It writes a `.drawio` file. You open it in
draw.io: the desktop app, [app.diagrams.net](https://app.diagrams.net), the
*Draw.io Integration* extension for VS Code, or Confluence. From there you
can export to Visio (`.vsdx`), PNG, SVG or PDF.

```powershell
Export-AACDiagram -ResourceGroupName 'rg-hub', 'rg-spoke-app' -Path .\estate.drawio -Open
Export-AACDiagram -SubscriptionId $sub -SplitBy ResourceGroup -Path .\estate.drawio        # a page per resource group
Export-AACDiagram -View Network -ManagementGroupId 'mg-landingzones' -Path .\network.drawio
Export-AACDiagram -View ApplicationGateway -ResourceGroupName 'rg-edge' -IncludeHealth -Path .\gateways.drawio
Export-AACDiagram -ResourceGroupName 'rg-hub', 'rg-spoke-app' -Path .\estate.drawio -Update # refresh, keep your edits
```

**What's drawn.** `-View` chooses the picture: the same model as the
browser maps.

| `-View` | What it draws | Like |
|---|---|---|
| `Resources` (default) | The resources in resource groups or subscriptions, with network links, peerings, private endpoints, routes, DNS links and dependencies | `Show-AACResourceMap` |
| `Network` | The topology of a tenant, management groups, subscriptions or regions: hubs and spokes, peerings, gateways, firewalls, appliances | `Show-AACNetworkTopology` |
| `ApplicationGateway` | Each gateway's flow, a column per stage: frontends, listeners, rules, path rules, backend settings, pools and targets, with probes, WAF policies and health | `Show-AACApplicationGatewayMap` |
| `Governance` | The management group hierarchy: the tenant root and management groups as nested boxes, each subscription inside its group, with the policy and role assignments at each level | `Show-AACManagementGroupMap` |

**Made to edit.**
- **Boxes are draw.io containers:** subscription, resource group, virtual
  network, subnet, and so on. Move a box and everything in it moves too;
  drag a resource into another box and it belongs there.
- **Resources** carry the official Azure icons (vector, sharp at any zoom),
  their name and type. Unattached resources are red, and those outside the
  selection are faded.
- **Connections are attached at both ends**, so they follow what you move,
  and draw.io re-routes them.
- **Every shape keeps its data:** resource ID, type, location, resource group
  and subscription. See it with *Edit > Edit Data* or by hovering;
  Ctrl+click opens the resource in the Azure portal.
- **A Legend page** shows the kinds of box and connection used, what was
  read and when (`-NoLegend` leaves it out).
- **`-SplitBy`** puts each subscription, resource group, management group,
  region or gateway on a page of its own, for large estates.

**Refresh without losing your edits.** Move things, restyle them, rename
them, and add notes, users or on-premises shapes. Then run the same command
with `-Update`. It reads Azure again and merges into your file:
- what you moved, restyled or renamed stays as you left it;
- new resources are added into their box (which grows to fit) and marked
  green until the next refresh;
- resources no longer in Azure are faded red, with the date they went.
  `-Prune` deletes them instead;
- shapes and connections you drew yourself are left alone.

The merge works because every shape's ID comes from its Azure resource ID,
so a refresh finds it again. Without `-Update`, an existing file isn't
overwritten unless you add `-Force`.

**A clean copy to view or share.** Add `-HtmlPath`, `-PdfPath` or both to
write the same diagram in light colours, with a legend of its connections,
boxes and flags:
- **HTML**: an interactive page that works offline, to pan, zoom, search and
  click a resource for its details.
- **PDF**: one page with the title, what was read and when, the whole diagram
  and its legend. It is vector, so it stays sharp when you zoom in or print
  it. Microsoft Edge or Google Chrome draws it, headless.

Both show what was read from Azure this time, on one page whatever
`-SplitBy` says. They don't include the changes you made in draw.io.

```powershell
Export-AACDiagram -SubscriptionId $sub -Path .\estate.drawio -HtmlPath .\estate.html -PdfPath .\estate.pdf
```

**From the browser maps.** `Show-AACResourceMap`, `Show-AACNetworkTopology`
and `Show-AACApplicationGatewayMap` have a **draw.io** button at the top of
the page. It saves the map exactly as laid out there, bends included, with
the same shape IDs, so `Export-AACDiagram -Update` can refresh it later.

**What it needs.** Reader on what you draw, and nothing to install: the
diagram is written by PowerShell, with no Graphviz, Python or Visio.
`-PdfPath` uses Microsoft Edge or Google Chrome if either is installed.

## Governance

Governance questions across the whole tenant, in the spirit of the
[Azure Governance Visualizer](https://github.com/Azure/Azure-Governance-Visualizer) -
each one a command of its own, and all of them together in one workbook.

```powershell
Invoke-AACGovernanceAssessment -HtmlPath .\Governance.html                     # everything, as a tabbed workbook
Invoke-AACGovernanceAssessment -MarkdownPath .\wiki\Governance.md -MarkdownFlavor AzureDevOps -NoDisplay   # a wiki page, from a pipeline
Show-AACManagementGroupMap                                                     # the hierarchy, in the browser
Get-AACRoleAssignment -ExpandGroup -HtmlPath .\Rbac.html                       # every role assignment, groups expanded
Test-AACAzureLimit -FailOnLimit Warning                                        # fail a pipeline at 80% of any limit
Test-AACAlzPolicy -LibraryPath C:\alz-library -ManagementGroupMap @{ alz = 'contoso' }
```

| Area | Command | What it answers |
|---|---|---|
| Hierarchy | `Show-AACManagementGroupMap` | Each management group, its subscriptions, policy and role assignments - a map, a tree, or `Export-AACDiagram -View Governance` for draw.io |
| Access | `Get-AACRoleAssignment` | Every role assignment at every scope; orphaned ones, privileged guests, applications as Owner, custom roles unused or as powerful as Owner |
| Identities | `Get-AACServicePrincipalInsight` | Applications and managed identities with Azure roles; credentials about to expire; other tenants' apps |
| Policy | `Get-AACPolicyRemediation` | Policies that could fix what they find, and whether remediation ran (`Invoke-AACPolicyAssessment` covers assignments, compliance, exemptions and identities' roles) |
| Limits | `Test-AACAzureLimit` | Scopes close to an Azure limit, with what to do |
| Settings | `Get-AACGovernanceSetting` | Hierarchy settings, management group activity logs, security contacts, classic administrators, preview features, providers |
| Tags | `Get-AACTagUsage` | Tag coverage and consistency |
| Locks | `Get-AACResourceLock` | Locks, and critical resources left unlocked |
| Changes | `Get-AACGovernanceChange` | Policy and access changes, and who made them |
| Reference | `Test-AACAlzPolicy` | Policy assignments against the Azure Landing Zones archetypes |

**The workbook.** `Invoke-AACGovernanceAssessment` runs the areas (or those in
`-Area`), keeps going when one fails (it says which, and why), and writes a
Summary with the hierarchy as a tree, a Findings tab with the high and medium
findings of every area, and a tab per area. `-MarkdownPath` writes the same as
one Markdown page - the hierarchy as a Mermaid diagram, a table per area -
for a GitHub or Azure DevOps wiki (`-MarkdownFlavor`).

**The Azure Landing Zones check.** `Test-AACAlzPolicy` reads a copy of the
[Azure Landing Zones Library](https://github.com/Azure/Azure-Landing-Zones-Library)
you clone yourself, at the release you want - nothing is downloaded. If your
management groups are named differently from the reference, map them:
`-ManagementGroupMap @{ alz = 'contoso'; landingzones = 'contoso-lz' }`.

**What it needs.** Reader on the scope (Reader on the tenant root group for
its settings), and in Entra ID Directory.Read.All and Application.Read.All for
names and credentials (GroupMember.Read.All for `-ExpandGroup`). What can't
be read is left out, and said.

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
Get-AACDiagnosticSetting -Status 'No setting' -CsvPath .\NoDiagnosticSetting.csv   # support logs, nothing configured
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
  Azure.Admin.Console.psd1   Module manifest (every exported command, from every area)
  Azure.Admin.Console.psm1   The parent: loads lib\Spectre.Console.dll, then each area of src\ - Core first
  src/                       The child areas, each with area.psd1 (what it is), Public\ and Private\
    Core/                    Connect-AAC and what every area builds on: HTTP, tokens, Resource Manager,
                             Resource Graph and Microsoft Graph helpers, progress, console views, CSV/HTML/PDF reports
    Azure/                   Commands for subscriptions and management groups
    M365/                    Commands for the Microsoft 365 and Entra ID tenant
    DevOps/                  Commands for Azure DevOps organizations
  PSRule/                    PSRuleRunner.ps1 (runs PSRule in its own pwsh) and Rules\ (the AAC.* rules and their help)
  Parked/                    Invoke-AACPester and its estate check, set aside (not loaded or packaged)
  lib/                       Vendored Spectre.Console and PDFsharp/MigraDoc (MIT)
  en-US/                     about_ help topic and the MAML help Get-Help shows (built by PlatyPS)
  docs/                      Markdown help, one page per command; the index groups them by area (built by PlatyPS)
  tools/                     Build-Help.ps1: builds docs\ and the MAML with PlatyPS (not packaged)
  Tests/                     Unit tests by area - Core\, Azure\, M365\, DevOps\ - and Fixtures\ (no Azure needed, not packaged)
  .github/workflows/         CI and release pipelines
  build.ps1                  Docs, tests, packaging and publishing (the package merges every area into one file, for a faster import)
  CHANGELOG.md, LICENSE
```

### Areas

The module is one parent with child areas. Each area is a folder under `src\`
with an `area.psd1` (its name, title, description and load order), its
commands in `Public\` - one per file, named after the command - and its
helpers in `Private\`. A helper two areas need lives in `src\Core`; a test
(`Tests\Core\Module.Tests.ps1`) fails if one area calls another area's
functions, or Core calls into an area. Adding a command is a file in its
area's `Public\` and its name in the manifest's `FunctionsToExport`;
adding an area is a folder with its `area.psd1`. Every command is still in
the one module: `Import-Module Azure.Admin.Console` loads all of them, and
their names don't depend on the area.

### Testing

The tests run on **Pester 6.2 or later** (below 7), which needs PowerShell
7.4 or later to run them - the module itself still runs on 7.2:

```powershell
Install-PSResource -Name Pester -Version '[6.2.0,7.0)' -Scope CurrentUser
./build.ps1 -Task Test                                         # every test
Invoke-Pester -Path ./Tests/Azure/Cost.Tests.ps1 -Output Detailed    # one file
```

The unit tests in `Tests\<Area>\` cover every command, with no Azure account needed.
Each one mocks the point where the module leaves the machine and runs
everything on this side for real:

| Command                                                                           | Mocked                                                                                                                                                                                                                                                                              | Tested for real                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| --------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Connect-AAC`                                                                     | The browser (`Start-Process`) and the token endpoint (`Invoke-RestMethod`)                                                                                                                                                                                                          | The PKCE code, the localhost listener receiving the redirect, state (CSRF) validation, the token exchange and the stored session; app-only sign-in: a client secret, a certificate's signed client assertion (checked with its public key), a managed identity endpoint, and a new token when one runs out                                                                                                                                                                                                                                          |
| `Invoke-AACPolicyAssessment`                                                      | Resource Graph and Resource Manager, with a made-up Contoso tenant                                                                                                                                                                                                                  | The queries (tenant-wide discovery, worst-state compliance, by-ID chunks), compliance overall and by subscription, management group, assignment, policy and category, thresholds, every finding, identities and roles, exemption expiry, Platform and Application audiences, management group and subscription scopes, excluded scopes, the tree, the built-in definitions Resource Graph lacks read from Resource Manager, the reports and the view                                                                                                |
| `Invoke-AACAksAssessment`                                                         | Resource Graph, the PSRule exporter and engine, Resource Manager and AKS run command, with made-up Contoso clusters                                                                                                                                                                 | Workloads inferred from pod names, system namespaces, effects and DoNotEnforce, the roll-ups and the 500-record cap, cluster policy states and assignments, version support (supported, LTS, out of support) and upgrades, every Well-Architected check on a well-run and a neglected cluster, subnet capacity, the other lenses as findings, settings, Gatekeeper through run command (Entra ID token, no Gatekeeper, failures), scope and names, PSRule options, the reports and the view                                                         |
| `Invoke-AACTenantAssessment`                                                      | Resource Graph, Resource Manager and Cost Management, with a made-up Contoso tenant                                                                                                                                                                                                 | The catalog (every sheet, column spec and key column) and its queries, resource group and tag filters, every sheet by label, VM sizes and subnet IPs filled in afterwards, retirements, Advisor, cost and tags on each row, the overview sheets, Advisor, Defender, Policy, outages across subscriptions, quotas, reservations, the tenant tree and organization diagram, scope and `-Category`, which Azure APIs are asked, the governance sheets (policy status, controls, why a resource fails, PSRule, recommendations ranked) and `-PSRule`, a sheet that fails, the upload, Automation sign-in, the reports and the view                                           |
| The transport (`Invoke-AACHttp`, `Invoke-AACArmParallel`, `Invoke-AACGraphBatch`) | The single HTTP send (`Send-AACHttpRequest`), or nothing (a local test server)                                                                                                                                                                                                      | Retries as Azure's retry headers ask (`Retry-After`, Cost Management's and Resource Graph's own), paging (`nextLink`, `$skipToken`), the throttle limit, Azure's error messages, failures allowed per query                                                                                                                                                                                                                                                                                                                                         |
| `Get-AACAdvisorRecommendation`, `Get-AACFirewallRule`, `Show-AACResource`         | Resource Graph, with hand-built rows (through a shim that runs each batched query one by one)                                                                                                                                                                                       | Flattening, filters and search, output modes, CSV, PDF and HTML, and the console view                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `Get-AACInventory`                                                                | Resource Graph and Cost Management, with a made-up Contoso tenant                                                                                                                                                                                                                   | The tree and its rolled-up counts, secure scores, cost (management group scope and the per-subscription fallback, deleted resources, currencies), insights (the mix, what needs attention, subnets), the views and the exports                                                                                                                                                                                                                                                                                                                      |
| `Get-AACPolicyState`                                                              | Resource Graph, with made-up policy states                                                                                                                                                                                                                                          | The KQL and its filters, management group, subscription and resource group scope, each resource's verdict, compliance per assignment, scope and policy, the view and the exports                                                                                                                                                                                                                                                                                                                                                                    |
| `Get-AACSkuAvailability`                                                          | The parallel ARM reads and Resource Graph, with made-up Compute SKUs, usage and zones                                                                                                                                                                                               | Region and zone restrictions, zones asked for, family and regional quota, AKS's rules, series, size and architecture filters, a cluster's node pools, errors, the view and the exports                                                                                                                                                                                                                                                                                                                                                              |
| `Get-AACSecurityPosture`                                                          | Resource Graph, with made-up Defender for Cloud and Azure Policy rows                                                                                                                                                                                                               | Findings across sections, scores, compliance traced to resources, plans, policy compliance, resource group and tag narrowing, the queries per section, the view and the exports                                                                                                                                                                                                                                                                                                                                                                     |
| `Get-AACSecurityAlert`                                                            | Resource Graph, with made-up Defender for Cloud alerts and plans                                                                                                                                                                                                                    | Order, resources and the compromised-entity fallback, MITRE tactics and techniques, entities, extended properties, recurring alerts, plans off, the query's filters, name/type/tactic/incident/resource group filters, pipeline input, the view and the exports                                                                                                                                                                                                                                                                                     |
| `Export-AACResource`                                                              | Resource Graph, with made-up resources and their subscriptions and resource groups                                                                                                                                                                                                  | The query and its filters, Details per type, management group paths, tags (case-insensitive) and -Flatten, the parallel queries, wildcards, -Search, the CSV's columns, the view and the HTML report                                                                                                                                                                                                                                                                                                                                                |
| `Get-AACResourceHealth`                                                           | Resource Graph and the Resource Health history calls, with made-up statuses, events and Service Health                                                                                                                                                                              | Order, reasons, latest event in the window, service issues per resource, availability and state changes from the history, filters, pipeline input, -ServiceHealth, the view and the exports                                                                                                                                                                                                                                                                                                                                                         |
| `Get-AACUnusedResource`                                                           | Resource Graph and Cost Management, with a made-up estate                                                                                                                                                                                                                           | Each kind found and rated, busy resources left alone, since when and how large, last month's cost and its order, filters, the view and the exports                                                                                                                                                                                                                                                                                                                                                                                                  |
| `Get-AACResourceError`                                                            | The Activity Log, with made-up events                                                                                                                                                                                                                                               | One error per correlation ID, the innermost deployment error, the refused action and scope, each category and its fix, filters, the view and the exports                                                                                                                                                                                                                                                                                                                                                                                            |
| `Get-AACPrivateEndpoint`                                                          | Resource Graph and the zone group calls, with made-up endpoints, zones, networks and targets                                                                                                                                                                                        | Connection states, orphans, zone groups linked, peered, custom DNS, wrong and duplicated zones, public targets, filters, -SkipDnsZoneGroup, the view and the exports                                                                                                                                                                                                                                                                                                                                                                                |
| `Get-AACLoadBalancerHealth`                                                       | Resource Graph and Azure Monitor, with made-up balancers and metrics                                                                                                                                                                                                                | Backend health from probes, host counts and monitor status, balancer health, findings, Basic and v1 retirements, filters, -SkipMetrics, the view and the exports                                                                                                                                                                                                                                                                                                                                                                                    |
| `Get-AACLegacyAuthentication`                                                     | Resource Graph, Resource Manager and Microsoft Graph, with made-up resources and tenant answers                                                                                                                                                                                     | Every Azure and Entra ID pattern and its order, sign-ins per protocol, legacy authentication blocked or not, what couldn't be read, filters, the view and the exports                                                                                                                                                                                                                                                                                                                                                                               |
| `Get-AACOrphanedIdentity`                                                         | Resource Graph, Resource Manager, the directory lookup and Microsoft Graph, with made-up identities                                                                                                                                                                                 | Deleted principals, unattached and federated identities, managed identities of deleted resources, stale, disabled and abandoned applications, severity by access, -SkipEntra, the view and the exports                                                                                                                                                                                                                                                                                                                                              |
| `Export-AACDiagnosticBundle`                                                      | Resource Graph and Resource Manager, with made-up resources                                                                                                                                                                                                                         | Redaction by name and value, sections per resource, the zip and its files, -Force, -WhatIf, resource groups, pipeline input and the summary                                                                                                                                                                                                                                                                                                                                                                                                         |
| `Get-AACNetworkSecurityGroup`                                                     | Resource Graph and the parallel ARM reads                                                                                                                                                                                                                                           | Rule evaluation, associations and VMs protected, NIC-and-subnet conflicts, flow logs, findings, the view and the exports                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `Show-AACResourceMap`                                                             | Resource Graph, with a made-up hub-and-spoke estate                                                                                                                                                                                                                                 | Boxes, placement, connections, network paths, NSGs and route tables, the page                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `Show-AACNetworkTopology`                                                         | Resource Graph, with a made-up hub and spokes across two management groups                                                                                                                                                                                                          | Roles, peerings (and what isn't one), NICs as part of their VMs, appliances, the boxes by management group, subscription or region, networks you can't see, findings, scope, -NetworkOnly, the page                                                                                                                                                                                                                                                                                                                                                 |
| `Get-AACAssignedPolicy`                                                           | Resource Graph and the parallel ARM reads, with a made-up tenant (management groups, an initiative, a missing definition)                                                                                                                                                           | Default, assigned and effective values, resource types from rules (parameters resolved, negated and alias-only rules, initiatives), inherited assignments for a subscription or management group, name filters, the view and the exports                                                                                                                                                                                                                                                                                                            |
| `Get-AACStorageAccountContainerSize`                                              | Resource Graph, the container listing and the blob service (`Send-AACHttpRequest`, with List Blobs XML pages)                                                                                                                                                                       | The page parser (tiers, snapshots, versions, deleted blobs, Data Lake directories, encoded names, the largest blobs), paging, Entra ID and account SAS, `-AuthMode Auto`, Azure Storage's errors and what to do, filters, the view and the exports                                                                                                                                                                                                                                                                                                  |
| `Get-AACTerraformPlan`                                                            | Nothing: it reads a made-up Contoso plan file                                                                                                                                                                                                                                       | Actions and reasons, attribute paths, blocks paired by name, JSON-encoded strings, forced replacements, sensitive values kept out of every output, drift, filters, UTF-16 files, the files it refuses, the view and the exports                                                                                                                                                                                                                                                                                                                     |
| `Export-AACTerraform`                                                             | The Export for Terraform API (submitted, answered 202, polled to Succeeded or Failed), Resource Graph, and the terraform CLI                                                                                                                                                        | The HCL splitter (braces in strings, comments and heredocs), azurerm and azapi exports merged into one module, the request each switch makes, folders per subscription, the resource provider unregistered and registered (never under -WhatIf), failures, no overwrite without -Force, terraform plan read, a failed terraform step, the view and the exports                                                                                                                                                                                      |
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
| `Invoke-AACWafAssessment`, `Get-AACKeyVaultInsight`, `Invoke-AACStorageAccountAssessment`, `Show-AACApplicationGatewayMap`, `Get-AACNetworkHealth`, `Show-AACNetworkTopology` | Resource Graph, Azure Monitor metrics, Resource Health, Log Analytics and the services' settings and data planes, each with a made-up Contoso fixture | Every check, signal and finding, the heat maps, scores, timestamps, scope and `-Name`, the views, and the console, CSV, PDF and HTML outputs |
| `Invoke-AACApplicationInsightQuery`                                               | Resource Graph and the query API (`Invoke-AACArmRequest`)                                                                                                                                                                                                                           | The KQL built from the parameters (with escaping), both table schemas flattened, `-Query`, errors, the view and the exports                                                                                                                                                                                                                                                                                                                                                                                                                         |

The console views are checked by swapping the Spectre console for one that
writes to a text buffer, then looking for what should be drawn. For a new
command, copy the nearest test file and change its mocks.

The comment-based help in each `src\<Area>\Public\*.ps1` file is the single source of
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
the areas' `Public\` folders, a clean import succeeds, and PSScriptAnalyzer
reports no errors. The package merges every area's functions into one file, area by
area (Core first), for a faster import.

### CI

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on every push to
`main` and every pull request:

- **Unit tests** on Windows, Ubuntu and macOS, with JUnit results kept as artifacts.
- **On Windows:** checks that `docs\` is up to date with the help, then builds and validates the package and keeps it as an artifact.

### Releasing to the PowerShell Gallery

1. Bump `ModuleVersion` in `Azure.Admin.Console.psd1` and add the release to
   `CHANGELOG.md`. A published version can never be replaced.
   `./tools/Step-ModuleVersion.ps1 -Version 0.14.6 -Prerelease preview1` does
   the manifest, the release notes, this tag example and the docs.
2. Commit, then push a tag that matches the version:

   ```powershell
   git tag -a v0.14.8 -m "Azure.Admin.Console v0.14.8"
   git push origin v0.14.8
   ```

**Pre-releases.** A `Prerelease` value in the manifest's `PSData` (for
example `preview1` or `rc1`) publishes the version as a pre-release -
`0.14.6-preview1`, tagged `v0.14.6-preview1`, marked as a pre-release on
GitHub. The Gallery installs it only when asked:

```powershell
Install-Module -Name Azure.Admin.Console -AllowPrerelease
Install-PSResource -Name Azure.Admin.Console -Prerelease
```

Each pre-release uses the same `## v0.14.6` changelog entry. When it's
ready, `./tools/Step-ModuleVersion.ps1 -Version 0.14.6 -Prerelease ''`
removes the label, and the tag `v0.14.6` publishes the stable release.

Only a version tag publishes. Pushes and pull requests run CI only.
[`.github/workflows/release.yml`](.github/workflows/release.yml) first runs a
gate with no secrets and no approval. It stops the release unless all of
these hold:

- the tag matches `ModuleVersion` (and `Prerelease`, when there is one);
- the tagged commit is on `main`;
- `CHANGELOG.md` has a `## v<version>` entry;
- the version is higher than the one on the PowerShell Gallery, and that
  exact version (with its pre-release label) isn't published yet.

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

## Sponsor

Azure.Admin.Console is free and open source, built and maintained in spare
time. If it saves you time, please consider sponsoring its development - it
keeps new commands, fixes and the docs coming.

<p>
  <a href="https://github.com/sponsors/ChendrayanV">
    <img src="https://img.shields.io/badge/Sponsor-ChendrayanV-EA4AAA?style=for-the-badge&logo=githubsponsors&logoColor=white" alt="Sponsor ChendrayanV on GitHub">
  </a>
</p>

Not able to sponsor? A star on the repository, an issue or an idea helps
just as much.

## License

[MIT](LICENSE). The bundled libraries keep their own MIT licenses in `lib\`.
