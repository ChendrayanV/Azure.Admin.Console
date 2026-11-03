# Azure.Admin.Console - the guide

The index of the guide: find a topic, or a command in the tables below. The short version is the [README](README.md).

[![CI](https://github.com/ChendrayanV/Azure.Admin.Console/actions/workflows/ci.yml/badge.svg)](https://github.com/ChendrayanV/Azure.Admin.Console/actions/workflows/ci.yml)
[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/Azure.Admin.Console?label=PowerShell%20Gallery)](https://www.powershellgallery.com/packages/Azure.Admin.Console)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Sponsor](https://img.shields.io/github/sponsors/ChendrayanV?label=Sponsor&logo=githubsponsors&color=EA4AAA)](https://github.com/sponsors/ChendrayanV)

## Topics

### Start here

- [Overview](docs/guide/overview.md)
- [Install](docs/guide/install.md)
- [Quick start](docs/guide/quick-start.md)
- [Troubleshooting](docs/guide/troubleshooting.md)

### The estate and what it costs

- [Dashboard](docs/guide/dashboard.md)
- [Resources and costs](docs/guide/resources-and-costs.md)
- [Azure tenant assessment](docs/guide/azure-tenant-assessment.md)
- [Tenant inventory](docs/guide/tenant-inventory.md)
- [Resource export](docs/guide/resource-export.md)
- [Azure Advisor recommendations](docs/guide/azure-advisor-recommendations.md)
- [Cost, security, operations, compliance and resilience](docs/guide/cost-security-operations-compliance-and-resilience.md)

### Security, policy and governance

- [Security posture](docs/guide/security-posture.md)
- [Security alerts](docs/guide/security-alerts.md)
- [Microsoft Defender for Cloud assessment](docs/guide/microsoft-defender-for-cloud-assessment.md)
- [Azure Policy compliance](docs/guide/azure-policy-compliance.md)
- [Governance](docs/guide/governance.md)
- [PSRule for Azure](docs/guide/psrule-for-azure.md)

### Operations and monitoring

- [Operations and troubleshooting](docs/guide/operations-and-troubleshooting.md)
- [Activity Log assessment](docs/guide/activity-log-assessment.md)
- [Diagnostic settings](docs/guide/diagnostic-settings.md)
- [Log Analytics workspace assessment](docs/guide/log-analytics-workspace-assessment.md)
- [Application Insights](docs/guide/application-insights.md)

### Networks and diagrams

- [Azure Firewall rules](docs/guide/azure-firewall-rules.md)
- [Network security groups](docs/guide/network-security-groups.md)
- [Virtual network assessment](docs/guide/virtual-network-assessment.md)
- [IP address management](docs/guide/ip-address-management.md)
- [Network topology](docs/guide/network-topology.md)
- [Resource map](docs/guide/resource-map.md)
- [Editable diagrams (draw.io)](docs/guide/editable-diagrams-draw-io.md)

### Services

- [VM size availability (virtual machines and AKS)](docs/guide/vm-size-availability-virtual-machines-and-aks.md)
- [Function App assessment](docs/guide/function-app-assessment.md)
- [AKS cluster assessment](docs/guide/aks-cluster-assessment.md)
- [Storage container sizes](docs/guide/storage-container-sizes.md)
- [Storage account assessment](docs/guide/storage-account-assessment.md)
- [Deploying a storage account](docs/guide/deploying-a-storage-account.md)
- [Service Bus assessment](docs/guide/service-bus-assessment.md)
- [Cosmos DB assessment](docs/guide/cosmos-db-assessment.md)

### Microsoft 365 and Entra ID

- [Microsoft 365 security posture](docs/guide/microsoft-365-security-posture.md)
- [Entra ID group membership](docs/guide/entra-id-group-membership.md)
- [Application permission](docs/guide/application-permission.md)

### Azure DevOps

- [Azure DevOps assessment](docs/guide/azure-devops-assessment.md)

### Design and infrastructure as code

- [Architecture design](docs/guide/architecture-design.md)
- [Terraform export](docs/guide/terraform-export.md)
- [Terraform plans](docs/guide/terraform-plans.md)

### The project

- [Design and security](docs/guide/design-and-security.md)
- [Development](docs/guide/development.md)

## Commands

The commands are grouped by the module's areas - one module, one install, a child area for each platform (see [Development](docs/guide/development.md)):

### Core: sign-in, REST and reports

Signing in to Azure, the REST helpers every command uses (Resource Manager, Resource Graph, Microsoft Graph), the console views and the CSV, HTML and PDF reports.

| Command | What it does | Guide |
|---|---|---|
| [`Connect-AAC`](docs/Connect-AAC.md) | Signs in with a browser (OAuth 2.0 + PKCE, localhost redirect) - or a device code (`-DeviceCode`), a service principal's secret or certificate (`-ClientSecret`, `-CertificatePath`, `-CertificateThumbprint`), or a managed identity (`-Identity`, e.g. in Azure Automation). Uses the Azure CLI's pre-consented public client ID unless you pass `-ClientId`. | [Quick start](docs/guide/quick-start.md) |
| [`Disconnect-AAC`](docs/Disconnect-AAC.md) | Forgets the sign-in. It was only ever in memory. | - |
| [`Show-AACJson`](docs/Show-AACJson.md) | JSON - or any object, as JSON - indented and syntax-coloured in a panel: ARM templates, REST responses, resources, this module's objects. | [Dashboard](docs/guide/dashboard.md) |

### Azure

Commands for an Azure estate - subscriptions and management groups: inventory, cost, policy, governance, networking, security, identity in Azure (RBAC, managed identities), health, assessments, Terraform and deployment.

| Command | What it does | Guide |
|---|---|---|
| [`Deploy-AACStorageAccount`](docs/Deploy-AACStorageAccount.md) | Creates or updates a storage account - containers, file shares, queues, tables, lifecycle rules, private endpoints, diagnostic settings, role assignments, a lock and blobs - idempotently with the Azure REST APIs, no ARM, Bicep or Terraform template. AVM's parameter names and defaults; a plan (create, update, can't change in place, drift); gates: the name, Azure Policy (`checkPolicyRestrictions` on every write's exact body) and PSRule for Azure; then apply and verify. The only command that writes. | [Deploying a storage account](docs/guide/deploying-a-storage-account.md) |
| [`Get-AACAdvisorRecommendation`](docs/Get-AACAdvisorRecommendation.md) | A consolidated, flattened view of Azure Advisor: a console view at the prompt, objects down a pipeline, CSV and/or PDF exports. | [Azure Advisor recommendations](docs/guide/azure-advisor-recommendations.md) |
| [`Get-AACFirewallRule`](docs/Get-AACFirewallRule.md) | Every Azure Firewall Policy rule: a console view at the prompt (Allow in green, Deny in red), objects down a pipeline, CSV and/or PDF exports. | [Azure Firewall rules](docs/guide/azure-firewall-rules.md) |
| [`Show-AACResource`](docs/Show-AACResource.md) | A colourful bar chart of your resources by type, location, resource group or subscription. | [Resources and costs](docs/guide/resources-and-costs.md) |
| [`Invoke-AACAksAssessment`](docs/Invoke-AACAksAssessment.md) | AKS clusters through every lens: current settings, about 35 Well-Architected checks scored per pillar, PSRule for Azure, Azure Policy for Kubernetes consolidated by namespace, workload, policy and cluster (the AKS Policy Compliance Toolkit's view) with Gatekeeper's complete counts, versions and upgrades, subnet capacity, Advisor and Defender. A console view, objects, and CSV, PDF and interactive HTML reports. | [AKS cluster assessment](docs/guide/aks-cluster-assessment.md) |
| [`Invoke-AACFunctionAppAssessment`](docs/Invoke-AACFunctionAppAssessment.md) | Function Apps end to end: hosting and plan, usage (executions, GB-seconds, errors, response time, estimated Consumption cost), every function and trigger, runtime support, configuration and app settings (names only), networking, deployment center and slots, backups, Service Connector and named services, the last week's Activity Log, about 30 Well-Architected checks, PSRule for Azure, Advisor and Defender. A console view, objects, and CSV, PDF and a tabbed HTML report with a tab per audience. | [Function App assessment](docs/guide/function-app-assessment.md) |
| [`Invoke-AACTenantAssessment`](docs/Invoke-AACTenantAssessment.md) | An Azure tenant assessed end to end, in the spirit of Azure Resource Inventory: a sheet per resource type (~95) with its key settings and policy compliance, the organization, Advisor and retirements, Defender, Policy, the Well-Architected Framework, PSRule, FinOps (savings, cost allocation, budgets), outages, quotas, reservations and cost - CSV, an interactive HTML report, a PDF and interactive network and organization diagrams, with a live progress display. Runs in Azure Automation with a managed identity and uploads to blob storage. | [Azure tenant assessment](docs/guide/azure-tenant-assessment.md) |
| [`Get-AACInventory`](docs/Get-AACInventory.md) | The tenant as a tree: management groups, subscriptions, resource groups and resources, with counts, the Defender for Cloud secure score and - with `-Cost` - the cost at every level. A console tree, objects, and CSV, PDF and interactive HTML reports. | [Tenant inventory](docs/guide/tenant-inventory.md) |
| [`Export-AACDiagram`](docs/Export-AACDiagram.md) | Your existing resources as an editable draw.io diagram - the resources, the network topology or Application Gateways - with real containers (move a box and what's in it moves too), Azure icons, attached connections, each shape's data and portal link, and a page per subscription or resource group. `-Update` refreshes it from Azure and keeps your changes: new resources added and marked, removed ones faded. | [Editable diagrams (draw.io)](docs/guide/editable-diagrams-draw-io.md) |
| [`Export-AACResource`](docs/Export-AACResource.md) | Every resource - for the tenant, a management group, subscriptions, resource groups or types - with its subscription and management group by name, resource group tags, tags as columns and each type's key settings, to CSV, HTML and PDF. Filters in Resource Graph (type, group, name, location, tag, missing tag, KQL) and free-text search. | [Resource export](docs/guide/resource-export.md) |
| [`Get-AACSecurityPosture`](docs/Get-AACSecurityPosture.md) | Microsoft Defender for Cloud and Azure Policy in one report: secure scores, recommendations grouped by control with remediation links, active alerts, Defender plans, regulatory compliance traced to the failing resources, and policy compliance per assignment - one list of findings. A console view, objects, and CSV, PDF and interactive HTML reports. | [Security posture](docs/guide/security-posture.md) |
| [`Get-AACSecurityAlert`](docs/Get-AACSecurityAlert.md) | Microsoft Defender for Cloud security alerts across every subscription in one query - the Get-AzSecurityAlert equivalent, with more in each alert: MITRE ATT&CK tactics and techniques, the hosts, accounts and IP addresses involved, extended properties, remediation steps, incidents and recurring alerts. Filters by status, severity, age, name, type, tactic and resource, and takes resources from the pipeline. | [Security alerts](docs/guide/security-alerts.md) |
| [`Get-AACSkuAvailability`](docs/Get-AACSkuAvailability.md) | Which VM sizes you can use for virtual machines or AKS node pools in a region and its availability zones - the subscription's restrictions, vCPU quota and AKS's rules - and why a size can't be used; an AKS cluster's node pools. Read-only REST, nothing deployed. A console view, objects, and CSV, PDF and interactive HTML reports. | [VM size availability (virtual machines and AKS)](docs/guide/vm-size-availability-virtual-machines-and-aks.md) |
| [`Get-AACAssignedPolicy`](docs/Get-AACAssignedPolicy.md) | Every Azure Policy assignment and its parameters - the default, assigned and effective value of each - with the resource types the policy applies to (its rule's type conditions, parameters resolved), one row per assignment and parameter. Assignments inherited from management groups included. A console view, objects, and CSV and tabbed HTML and PDF reports. | [Azure Policy compliance](docs/guide/azure-policy-compliance.md) |
| [`Show-AACEffectivePolicy`](docs/Show-AACEffectivePolicy.md) | The Azure Policy that applies to a resource - existing, or one you are about to deploy - and what each policy does to it (blocks, audits, changes, deploys), where it is assigned, its compliance and why (field, expected, found), the exemption covering it, what notScopes, resource selectors or the rule leave out, and the assignment chain. | [Azure Policy compliance](docs/guide/azure-policy-compliance.md) |
| [`Test-AACPolicyDeployment`](docs/Test-AACPolicyDeployment.md) | An ARM template or Bicep file checked against Azure Policy before it is deployed: what would be refused, audited or changed, resource by resource, why, and the values allowed - a pull-request check or pipeline gate (`-FailOn Deny`). | [Azure Policy compliance](docs/guide/azure-policy-compliance.md) |
| [`Invoke-AACPolicyAssessment`](docs/Invoke-AACPolicyAssessment.md) | Azure Policy assessed as a whole, in the spirit of AzPolicyLens: compliance (each resource counted at its worst state) overall and by subscription, management group, assignment, policy and category; exemptions and their expiry; initiatives and definitions; the managed identities' roles; what to improve (direct assignments, DoNotEnforce, remediation without an identity or role, deprecated policies, overlapping assignments, stale exemptions, unassigned custom definitions, unused groups). Platform and Application audiences. A console view, objects, and CSV, PDF and interactive HTML reports with the management group tree. | [Azure Policy compliance](docs/guide/azure-policy-compliance.md) |
| [`Invoke-AACDefenderAssessment`](docs/Invoke-AACDefenderAssessment.md) | Microsoft Defender for Cloud assessed across subscriptions: every recommendation (unhealthy, healthy and not applicable resources, risk level), attack paths step by step, security alerts with MITRE tactics and remediation, the inventory with each resource's plan coverage, vulnerabilities (CVEs), secure score controls, Defender plans with extensions, regulatory compliance, and environment settings (contacts, notifications, integrations, connectors, just-in-time) - with findings on how Defender is set up. A console view, an object, CSV and a tabbed HTML report in the portal's order. | [Microsoft Defender for Cloud assessment](docs/guide/microsoft-defender-for-cloud-assessment.md) |
| [`Get-AACPolicyState`](docs/Get-AACPolicyState.md) | Azure Policy compliance for every resource - one row per resource and policy, with initiative, assignment, effect and when it was evaluated - by management group, subscription or resource group, with compliance per assignment, policy, subscription and resource group. A console view, objects, and CSV, PDF and interactive HTML reports. | [Azure Policy compliance](docs/guide/azure-policy-compliance.md) |
| [`Get-AACNetworkSecurityGroup`](docs/Get-AACNetworkSecurityGroup.md) | A detailed assessment of network security groups: associations, every rule, flow logs and diagnostic settings, and findings by severity (open to the internet, shadowed rules, subnet and NIC conflicts, logging gaps). A console view, objects, and CSV, PDF and interactive HTML reports. | [Network security groups](docs/guide/network-security-groups.md) |
| [`Get-AACStorageAccountContainerSize`](docs/Get-AACStorageAccountContainerSize.md) | How much is stored in every blob container of your storage accounts: blobs, bytes, access tiers (Hot, Cool, Cold, Archive), snapshots, versions and deleted blobs, the newest change and the largest blobs - read in parallel, a page of 5,000 blobs at a time. Entra ID or a short-lived account SAS. A console view with every account and container as a tree, objects, and CSV and interactive HTML reports. | [Storage container sizes](docs/guide/storage-container-sizes.md) |
| [`Get-AACTerraformPlan`](docs/Get-AACTerraformPlan.md) | A Terraform plan in JSON (`terraform show -json`), flattened: what will be created, updated, replaced, deleted, read, imported and moved - and why - down to each attribute's before and after value, with the outputs and what changed outside Terraform. Sensitive values are never shown. Offline: no sign-in. A console view, objects, and CSV and interactive HTML reports. | [Terraform plans](docs/guide/terraform-plans.md) |
| [`Export-AACTerraform`](docs/Export-AACTerraform.md) | Existing resources as Terraform - a resource group, resources by ID or piped, or a Resource Graph query - through the Azure Export for Terraform API (a long-running operation, polled with progress): a folder ready for terraform init and plan, with import blocks. What azurerm can't export is listed, and `-FallbackToAzApi` exports it with azapi; `-Plan` runs terraform plan to prove the export. A console view, objects, and CSV, HTML and PDF reports. | [Terraform export](docs/guide/terraform-export.md) |
| [`Get-AACDiagnosticSetting`](docs/Get-AACDiagnosticSetting.md) | Every resource's diagnostic settings, flattened, and the resources whose logs don't reach a Log Analytics workspace: each one's status (exported, partial, not to a workspace, no setting), what's missing and why, and misconfigurations (deleted workspaces, nothing enabled, logs sent twice, another region, unexpected workspace, retired retention). Storage services and subscription activity logs included. A console view, objects, and CSV, PDF and interactive HTML reports. | [Diagnostic settings](docs/guide/diagnostic-settings.md) |
| [`Show-AACNetworkTopology`](docs/Show-AACNetworkTopology.md) | The network topology of the tenant, management groups, subscriptions or regions, opened in your browser: hubs at the centre of their spokes, or every network inside its tenant, management group, subscription, region and resource group; peerings, gateways, Virtual WAN, firewalls and appliances, private endpoints to their PaaS, routes to their next hop; roles and findings. Saves as PNG, JPEG or SVG. | [Network topology](docs/guide/network-topology.md) |
| [`Show-AACResourceMap`](docs/Show-AACResourceMap.md) | A map of one or more resource groups, opened in your browser: the resources with their Azure icons, in subscription, resource group, VNet and subnet boxes, with their connections, dependencies and network paths. Saves as PNG or JPEG. | [Resource map](docs/guide/resource-map.md) |
| [`Show-AACCost`](docs/Show-AACCost.md) | Subscription costs: month to date by subscription and by service, and a monthly trend, as charts and a table. | [Resources and costs](docs/guide/resources-and-costs.md) |
| [`Show-AACDashboard`](docs/Show-AACDashboard.md) | The estate on one screen: one status and an Estate score at the top; health, security, policy, governance (limits, privileged access, unused resources, tags), Advisor and savings, resources by region and type, 14 days of changes and who made them, and with `-IncludeCost` the spend; then what to do next, ranked, with the command that goes deeper. `-HtmlPath`/`-PdfPath` for a report with a tab per section, `-Watch` for a screen on the wall. | [Dashboard](docs/guide/dashboard.md) |
| [`Get-AACCostAnomaly`](docs/Get-AACCostAnomaly.md) | Spend anomalies before the invoice: spikes, drops, new spend, level shifts and steady rises by service, resource group, region or meter (robust median/MAD statistics), the resources behind each, a month-end forecast and a subscription benchmark. | [Cost, security, operations, compliance and resilience](docs/guide/cost-security-operations-compliance-and-resilience.md) |
| [`Get-AACAttackPath`](docs/Get-AACAttackPath.md) | Attack paths from the Internet, through managed identities, to what an attacker could control or read - with blast radius, risk and the fix; plus Defender for Clouds own paths. | [Cost, security, operations, compliance and resilience](docs/guide/cost-security-operations-compliance-and-resilience.md) |
| [`Get-AACAccessReview`](docs/Get-AACAccessReview.md) | A least-privilege access review of Azure RBAC (permanent, PIM-activated, eligible), classic admins, Entra ID roles and Graph application permissions - unused, standing, guest, orphaned and over-broad access, with an attestation CSV. | [Cost, security, operations, compliance and resilience](docs/guide/cost-security-operations-compliance-and-resilience.md) |
| [`Get-AACChangeHistory`](docs/Get-AACChangeHistory.md) | Who changed what, when and from where - properties before and after, how to undo it, and the alerts and health events that followed - a timeline for incidents and change control. | [Cost, security, operations, compliance and resilience](docs/guide/cost-security-operations-compliance-and-resilience.md) |
| [`Invoke-AACActivityLogAssessment`](docs/Invoke-AACActivityLogAssessment.md) | The Activity Log of every resource over 90, 180 or 365 days - subscription, resource group, resource and tags on every row: who changed what and when, when each resource was last used, idle and deleted resources, changes by hand, guests, access and secrets touched by people. Read from the Log Analytics workspace each subscription exports to (found automatically) - seconds for a year - else the REST API (90 days). | [Activity Log assessment](docs/guide/activity-log-assessment.md) |
| [`Show-AACActivityLogEvent`](docs/Show-AACActivityLogEvent.md) | Activity Log events the way an admin reads them: when, what, the result and why it failed (the innermost error and what to do), who (decoded from the token: kind, app, sign-in method, tenant, roles), where, and the IDs to trace it. From a JSON file saved from the portal (no sign-in needed), a correlation ID (Activity Log or Log Analytics), or the pipeline. A card per event in the console and PDF, plus CSV and HTML. | [Activity Log assessment](docs/guide/activity-log-assessment.md) |
| [`Invoke-AACHealthCheck`](docs/Invoke-AACHealthCheck.md) | Endpoints (synthetic requests, latency, TLS expiry), databases, Service Bus queues, Resource Health, Service Health and alerts - by tier, with an SLA report and a live -Watch board. | [Cost, security, operations, compliance and resilience](docs/guide/cost-security-operations-compliance-and-resilience.md) |
| [`Get-AACComplianceGap`](docs/Get-AACComplianceGap.md) | Compliance gaps per framework (CIS, PCI-DSS, HIPAA, SOC 2, GDPR, ISO 27001, NIST, MCSB) from Defender and Azure Policy, prioritised by risk and effort as a roadmap, with progress against a baseline. | [Cost, security, operations, compliance and resilience](docs/guide/cost-security-operations-compliance-and-resilience.md) |
| [`Get-AACFailoverReadiness`](docs/Get-AACFailoverReadiness.md) | Disaster recovery readiness: backups (fresh, succeeding, restore-tested), Site Recovery (health, RPO, test failover), vault settings and recovery plan runbooks, with a confidence score. | [Cost, security, operations, compliance and resilience](docs/guide/cost-security-operations-compliance-and-resilience.md) |
| [`Get-AACDependencyGraph`](docs/Get-AACDependencyGraph.md) | Which resources depend on which (network, pools, Front Door, plans, private endpoints, identities, Application Insights calls): blast radius, single points of failure, cycles and critical services; Graphviz export. | [Cost, security, operations, compliance and resilience](docs/guide/cost-security-operations-compliance-and-resilience.md) |
| [`Get-AACResourceUtilization`](docs/Get-AACResourceUtilization.md) | Idle, under-used, hot and right-sized resources from their actual CPU, memory and activity, with trends, VM right-sizing priced from Azure retail prices, and an unused-cost chargeback. | [Cost, security, operations, compliance and resilience](docs/guide/cost-security-operations-compliance-and-resilience.md) |
| [`Get-AACConfigurationDrift`](docs/Get-AACConfigurationDrift.md) | Configuration drift against a saved baseline, desired-state rules (or a built-in security baseline) or Terraform - who changed it, the strategy to fix it, and the trend over time. | [Cost, security, operations, compliance and resilience](docs/guide/cost-security-operations-compliance-and-resilience.md) |
| [`Get-AACResourceHealth`](docs/Get-AACResourceHealth.md) | Resource Health of every resource (Available, Unavailable, Degraded), why and since when, its latest platform event, the Azure outages and maintenance that hit it, and with -IncludeHistory its availability over the last days. | [Operations and troubleshooting](docs/guide/operations-and-troubleshooting.md) |
| [`Get-AACUnusedResource`](docs/Get-AACUnusedResource.md) | Unused resources: unattached disks, NICs and public IPs, empty App Service plans, pools and gateways, stopped VMs still billed, old snapshots, empty resource groups and more - billed or not, since when, and last month's cost with -IncludeCost. | [Operations and troubleshooting](docs/guide/operations-and-troubleshooting.md) |
| [`Get-AACResourceError`](docs/Get-AACResourceError.md) | What failed, from the Activity Log: access denied (the refused action and scope), Azure Policy denies, quota and capacity, throttling, locks, invalid deployments - one per correlation ID, with who and the fix. | [Operations and troubleshooting](docs/guide/operations-and-troubleshooting.md) |
| [`Get-AACPrivateEndpoint`](docs/Get-AACPrivateEndpoint.md) | Private endpoints audited: connection state, target, IPs and names, the DNS zone group and whether the endpoint's network is linked to it, orphaned endpoints, targets still public, duplicated privatelink zones. | [Operations and troubleshooting](docs/guide/operations-and-troubleshooting.md) |
| [`Get-AACLoadBalancerHealth`](docs/Get-AACLoadBalancerHealth.md) | Load balancers, Application Gateways and Traffic Manager right now: every backend's health probe, healthy and unhealthy hosts, data path, empty pools, rules without probes, retired SKUs, no redundancy. | [Operations and troubleshooting](docs/guide/operations-and-troubleshooting.md) |
| [`Get-AACLegacyAuthentication`](docs/Get-AACLegacyAuthentication.md) | Legacy and high-risk authentication in Azure (keys, SAS, local accounts, passwords, old TLS) and Entra ID (legacy-protocol sign-ins, legacy auth not blocked, implicit grant, ROPC, client secrets, SMS). | [Operations and troubleshooting](docs/guide/operations-and-troubleshooting.md) |
| [`Get-AACOrphanedIdentity`](docs/Get-AACOrphanedIdentity.md) | Identities nobody uses: role assignments to deleted principals, unattached user-assigned identities, managed identities of deleted resources, service principals not signed in for months, abandoned app registrations - and the access each holds. | [Operations and troubleshooting](docs/guide/operations-and-troubleshooting.md) |
| [`Export-AACDiagnosticBundle`](docs/Export-AACDiagnosticBundle.md) | A zip for a support case: each resource's configuration, health and history, Activity Log, diagnostic settings, locks, recommendations, compliance, alerts, changes and role assignments - secrets redacted, with a README and summary. | [Operations and troubleshooting](docs/guide/operations-and-troubleshooting.md) |
| [`Invoke-AACPSRule`](docs/Invoke-AACPSRule.md) | PSRule for Azure, the module's own naming and tag rules and your custom rules on the live estate: include or exclude rules by name or wildcard, with a baseline or settings. Runs of only the module's rules read just names, types and tags. | [PSRule for Azure](docs/guide/psrule-for-azure.md) |
| [`Invoke-AACVirtualNetworkAssessment`](docs/Invoke-AACVirtualNetworkAssessment.md) | Virtual networks assessed: address space with total, used and available IPs and the free CIDR ranges; every subnet (capacity, NSG, routes, NAT gateway, outbound path, endpoints, delegations); peerings; NSGs and ASGs; DNS, DDoS, encryption, flow logs, gateways, firewalls and Bastion - with findings by severity. A console view, objects, and CSV, PDF and interactive HTML reports. | [Virtual network assessment](docs/guide/virtual-network-assessment.md) |
| [`Get-AACIPAMReport`](docs/Get-AACIPAMReport.md) | IP address management with no server to run: Azure's address space measured against your address plan (spaces and blocks, or the private ranges) - each block's allocation, free space and next free ranges, every network (in the plan or not), subnet and private IP address (unattached interfaces included), overlaps (peered, with on-premises ranges), CIDR checks and findings. A console view, objects, and CSV, PDF and a tabbed HTML report with a tree of the plan and hover cards. | [IP address management](docs/guide/ip-address-management.md) |
| [`Invoke-AACLogAnalyticsWorkspaceAssessment`](docs/Invoke-AACLogAnalyticsWorkspaceAssessment.md) | A Log Analytics workspace assessed: billable and not billable tables with their size, plan and retention; every workspace setting; recommendations (Azure Advisor's and its own: cost, reliability, security); data collection rules; and the Workspace Insights views - Overview, Usage, Health, Agents, Query Audit, Data Collection Rules, Change Log. Read-only. A console view, an object, CSV, a tabbed HTML report (a tab per section) and a PDF. | [Log Analytics workspace assessment](docs/guide/log-analytics-workspace-assessment.md) |
| [`Invoke-AACApplicationInsightQuery`](docs/Invoke-AACApplicationInsightQuery.md) | Application Insights exceptions, flattened, from a Log Analytics workspace or Application Insights resource, or any KQL query. | [Application Insights](docs/guide/application-insights.md) |
| [`Invoke-AACWafAssessment`](docs/Invoke-AACWafAssessment.md) | The estate against the Azure Well-Architected Framework's five pillars: about 60 checks plus Advisor and Defender for Cloud, scored 0-100 by pillar, design principle and check, with each pillar's maturity, workbook-style heat maps by subscription, resource group or resource type, team questionnaire answers (`-AttestationPath`) and the trend (`-HistoryPath`). A console view, objects, and CSV, PDF and interactive HTML reports. | - |
| [`Test-AACGoLiveReadiness`](docs/Test-AACGoLiveReadiness.md) | A go-live gate: the Well-Architected assessment on a workload, Ready or Not ready - pillar scores against a minimum, no high-severity findings, the checks that must pass - with the blockers. `-FailOnGap` fails a pipeline stage. | - |
| [`Export-AACWafQuestionnaire`](docs/Export-AACWafQuestionnaire.md) | The Well-Architected questionnaire - one question per design principle, for what no API can test - as a CSV the team answers and `Invoke-AACWafAssessment -AttestationPath` scores. | - |
| [`Get-AACWafCheck`](docs/Get-AACWafCheck.md) | The checks the Well-Architected assessment runs, by pillar and design principle, with the resource type, severity, fix and link for each. | - |
| [`Invoke-AACKeyVaultAssessment`](docs/Invoke-AACKeyVaultAssessment.md) | Key Vaults: what Azure Monitor's Key Vault workbook shows (availability, transactions, latency, failures by status, operations from the audit logs) plus saturation, posture, callers denied or throttled, and secrets, keys and certificates near expiry (`-IncludeObjects`) - as a heat map and findings. | - |
| [`Invoke-AACStorageAccountAssessment`](docs/Invoke-AACStorageAccountAssessment.md) | Storage accounts: what Azure Monitor's Storage accounts workbook shows (transactions, latency, errors by response type, capacity by service) plus availability, throttling, security posture, data protection (soft delete, versioning, redundancy) and cost (lifecycle rules, legacy kinds, idle and hot-but-quiet accounts) - as a heat map and findings. | [Storage account assessment](docs/guide/storage-account-assessment.md) |
| [`Invoke-AACServiceBusAssessment`](docs/Invoke-AACServiceBusAssessment.md) | Service Bus namespaces assessed: requests, errors and throttling, Premium CPU and memory, every queue, topic and subscription's messages (active, dead-lettered, scheduled) and how full it is, security (TLS, SAS keys, network, logs), resilience (zones, geo-disaster recovery) and cost, as a heat map and findings. A console view, objects, and CSV, HTML and PDF reports. | [Service Bus assessment](docs/guide/service-bus-assessment.md) |
| [`Show-AACServiceBusEntity`](docs/Show-AACServiceBusEntity.md) | Queues and topics as you can see them - with a role on the namespace or only on the entities: live counts, dead-letters, subscriptions, configuration, and (with namespace access) Azure Monitor metrics with trends; `-Sample` for a backlog trend without metrics. | [Service Bus assessment](docs/guide/service-bus-assessment.md) |
| [`Invoke-AACCosmosDBAssessment`](docs/Invoke-AACCosmosDBAssessment.md) | Cosmos DB accounts assessed in every API: availability, requests by status and rate limiting (429), throughput and the busiest partition, storage, every database and container with its throughput, security (network, keys, TLS, logs, Defender), resilience (regions, failover, zones, backup) and cost, as a heat map and findings. A console view, objects, and CSV, HTML and PDF reports. | [Cosmos DB assessment](docs/guide/cosmos-db-assessment.md) |
| [`Show-AACApplicationGatewayMap`](docs/Show-AACApplicationGatewayMap.md) | Application Gateways drawn as their traffic flow - frontend IPs, listeners, rules, path rules and redirects, backend settings and probes, pools and targets, WAF policies - with health (`-IncludeHealth` for the live backend health) and findings, opened in your browser. | [Editable diagrams (draw.io)](docs/guide/editable-diagrams-draw-io.md) |
| [`Get-AACNetworkHealth`](docs/Get-AACNetworkHealth.md) | The hybrid and edge network's health - ExpressRoute circuits and gateways, VPN gateways, connections and tunnels, Azure Firewalls and NAT gateways - from metrics, configuration and Resource Health: % of capacity, thresholds and findings, each with when it happened. | - |
| [`Invoke-AACGovernanceAssessment`](docs/Invoke-AACGovernanceAssessment.md) | Governance across the tenant in one run, in the spirit of the Azure Governance Visualizer: the management group hierarchy, access, workload identities, policy remediation, Azure limits, settings, tags, locks and recent changes - a tabbed workbook, and a Markdown page with the hierarchy as a Mermaid diagram for a GitHub or Azure DevOps wiki. | [Governance](docs/guide/governance.md) |
| [`Show-AACManagementGroupMap`](docs/Show-AACManagementGroupMap.md) | The management group hierarchy as an interactive map: nested boxes, each subscription inside its group, and the policy and role assignments at each level. `Export-AACDiagram -View Governance` draws it for draw.io. | [Governance](docs/guide/governance.md) |
| [`Get-AACRoleAssignment`](docs/Get-AACRoleAssignment.md) | Every Azure role assignment at every scope - who holds it and what they are (user, guest, group, application or another tenant's, system- or user-assigned identity, deleted), what the role can do, how far it reaches, standing or PIM, group members, who created it - with orphaned assignments, risky grants and unused or Owner-equivalent custom roles flagged. | [Governance](docs/guide/governance.md) |
| [`Get-AACServicePrincipalInsight`](docs/Get-AACServicePrincipalInsight.md) | Every application and managed identity with Azure roles: its kind, privileged roles, the resources a user-assigned identity is attached to, secrets and certificates about to expire, and other tenants' applications with access. | [Governance](docs/guide/governance.md) |
| [`Test-AACAzureLimit`](docs/Test-AACAzureLimit.md) | Which scopes are close to an Azure limit - role assignments, custom roles, policy assignments, definitions, initiatives and exemptions, resource groups, tags, management group depth - with what to do, and a gate for pipelines (`-FailOnLimit`). | [Governance](docs/guide/governance.md) |
| [`Get-AACGovernanceSetting`](docs/Get-AACGovernanceSetting.md) | The settings governance depends on: who can create management groups, where new subscriptions land, management group activity logs, Defender security contacts, classic administrators, preview features, resource providers registered unevenly, each subscription's offer and state. | [Governance](docs/guide/governance.md) |
| [`Get-AACPolicyRemediation`](docs/Get-AACPolicyRemediation.md) | DeployIfNotExists and Modify policies with resources they could fix, and what their remediation tasks did: never run, failed, drifted again, still running, or no identity to run with. | [Azure Policy compliance](docs/guide/azure-policy-compliance.md) |
| [`Get-AACTagUsage`](docs/Get-AACTagUsage.md) | How tags are really used: each tag name's coverage and values, names that clash in casing, near-duplicates, values in mixed casing, and how far your required tags reach. | [Governance](docs/guide/governance.md) |
| [`Get-AACResourceLock`](docs/Get-AACResourceLock.md) | Every resource lock, and the critical resources (key vaults, storage, databases, vaults, networks, DNS zones...) no lock protects - with ReadOnly locks that break more than they protect flagged. | [Governance](docs/guide/governance.md) |
| [`Get-AACGovernanceChange`](docs/Get-AACGovernanceChange.md) | Who changed policy and access in the last days: policy definitions, initiatives and assignments, custom roles and role assignments created or updated, with the author resolved and privileged grants flagged. | [Governance](docs/guide/governance.md) |
| [`Test-AACAlzPolicy`](docs/Test-AACAlzPolicy.md) | Your management groups' policy assignments against the Azure Landing Zones reference (a local copy of the ALZ Library): what each archetype assigns that is missing, different or present - and the library file to deploy the missing ones from. | [Governance](docs/guide/governance.md) |
| [`Deploy-AACSentinelHuntingQuery`](docs/Deploy-AACSentinelHuntingQuery.md) | Adds hunting queries to a Microsoft Sentinel workspace, from the packs, from YAML files you name or from Find-AACSentinelHuntingQuery, and keeps them up to date. | - |
| [`Find-AACSentinelHuntingQuery`](docs/Find-AACSentinelHuntingQuery.md) | Lists the hunting queries you could deploy to Microsoft Sentinel - for Entra ID sign-ins and audit, Microsoft 365 and Intune - and, for a workspace, whether each is ready and how it stands there. | - |
| [`Get-AACSentinelHuntingQuery`](docs/Get-AACSentinelHuntingQuery.md) | Lists the hunting queries on a Microsoft Sentinel workspace: whatever put them there. | - |
| [`Invoke-AACSentinelAssessment`](docs/Invoke-AACSentinelAssessment.md) | Assesses Microsoft Sentinel on a Log Analytics workspace: analytics rules and MITRE ATT&CK coverage, rule templates, data connectors, tables and ingestion, health failures, incidents, automation rules and recommendations - with a Spectre.Console view, an object, and CSV and interactive HTML and PDF reports. | - |

### Microsoft 365 and Entra ID

Commands for the Microsoft 365 and Entra ID tenant: the Microsoft 365 assessment, group membership, and what applications and managed identities may do.

| Command | What it does | Guide |
|---|---|---|
| [`Invoke-AACM365Assessment`](docs/Invoke-AACM365Assessment.md) | Microsoft 365 tenant discovery and security posture from the Microsoft Graph REST API with one token: Entra ID (settings, Conditional Access, admin roles, MFA registration, authentication methods), Microsoft 365 (domains, Secure Score, SharePoint and OneDrive sharing, audit logging) and Intune (enrollment restrictions, compliance, endpoint security, stale and unmanaged devices) - with zero-trust findings. A console view, an object, CSV and a tabbed HTML report. | [Microsoft 365 security posture](docs/guide/microsoft-365-security-posture.md) |
| [`Get-AACEntraGroupMembership`](docs/Get-AACEntraGroupMembership.md) | Entra ID groups and everyone in them - direct and through nested groups - one row per group and member, with type, source, guests and disabled accounts. A console view with each group's members flattened, objects, and CSV, PDF and interactive HTML reports. | [Entra ID group membership](docs/guide/entra-id-group-membership.md) |
| [`Get-AACApplicationPermission`](docs/Get-AACApplicationPermission.md) | Every permission an enterprise application or managed identity holds - API (application) permissions, delegated consents, Entra directory roles with their scope (tenant, administrative unit, object; direct, through groups, PIM-eligible), Azure roles, owned objects and groups, and permissions requested but not granted - with findings for the privileged ones. By object ID, app ID, app registration ID, name or managed identity resource ID. A console view, objects, and CSV, HTML and PDF reports. | [Application permission](docs/guide/application-permission.md) |
| [`New-AACApplicationPermission`](docs/New-AACApplicationPermission.md) | Lets an enterprise application or managed identity manage specific Entra groups only - not every group, as GroupMember.ReadWrite.All would: an administrative unit with the groups, a custom (or built-in) role with just the group actions, assigned on the unit. Plan, confirm, apply, verify; flags (and with `-RemoveTenantWidePermission` removes) tenant-wide Graph permissions that would override the scope. | [Application permission](docs/guide/application-permission.md) |

### Azure DevOps

Commands for Azure DevOps organizations: projects, pipelines and the tools they run, repositories, security posture and delivery metrics.

| Command | What it does | Guide |
|---|---|---|
| [`Invoke-AACADOAssessment`](docs/Invoke-AACADOAssessment.md) | One or more Azure DevOps organizations inventoried: projects, pipelines (YAML, or classic - flagged) with their last run and delivery metrics (success rate, duration, queue time, DORA deployment frequency and change failure rate), every task and CLI tool they use with versions - YAML, nested and cross-repository templates, and classic pipelines - and the security posture of service connections, variable groups, environments, branch policies and GitHub Advanced Security, with findings; branching strategy, a DORA assessment and everything a move to GitHub needs (variables, artifacts, test plans, agent pools, extensions). A PAT or your Azure sign-in; `-IncludeAzure` links service connections to Azure roles. A console view, objects, and CSV, HTML and PDF reports. | [Azure DevOps assessment](docs/guide/azure-devops-assessment.md) |

### Architecture design

Designing and planning a workload before anything is deployed: the brief, patterns, design, diagrams and decisions, and a blueprint of the services it needs.

| Command | What it does | Guide |
|---|---|---|
| [`New-AACArchitectureBrief`](docs/New-AACArchitectureBrief.md) | A workload's requirements captured as an architecture brief: about 20 probe questions on the business, reliability, security, performance, cost and operations - asked at the prompt or taken from a file - with open decisions and assumptions. Offline. | [Architecture design](docs/guide/architecture-design.md) |
| [`Get-AACArchitecturePattern`](docs/Get-AACArchitecturePattern.md) | The Azure Architecture Center's cloud design patterns ranked against a brief: which fit, why, and their Well-Architected trade-offs. | [Architecture design](docs/guide/architecture-design.md) |
| [`New-AACArchitectureDesign`](docs/New-AACArchitectureDesign.md) | A design model from a brief and the chosen patterns: components, zones, settings and connections; the landing zone's inherited Azure Policy and allowed locations read live. | [Architecture design](docs/guide/architecture-design.md) |
| [`Test-AACArchitectureDesign`](docs/Test-AACArchitectureDesign.md) | A design validated before deployment against the Well-Architected Framework, inherited Azure Policy, your guardrails and PSRule for Azure: findings with remediation, a score per pillar, accepted risks, `-FailOnGap`. Tabbed HTML and PDF. | [Architecture design](docs/guide/architecture-design.md) |
| [`New-AACServiceBlueprint`](docs/New-AACServiceBlueprint.md) | Any service in Azure's list, planned before anything is deployed: the policies in force and your guardrails, the alerts AMBA suggests and APRL's recommendations. Function App, storage account, Event Hubs and Event Grid also get a secure configuration checked against your naming convention, Azure's own policy verdict and PSRule for Azure. A console view, objects, an editable draw.io diagram, HTML and PDF. | - |
| [`Get-AACAlertBaseline`](docs/Get-AACAlertBaseline.md) | The alerts Azure Monitor Baseline Alerts suggests for a resource type, with their thresholds. Offline, no sign-in. | - |
| [`Get-AACResiliencyRecommendation`](docs/Get-AACResiliencyRecommendation.md) | The Azure Proactive Resiliency Library's recommendations for a resource type, with their impact. Offline, no sign-in. | - |
| [`New-AACArchitectureDiagram`](docs/New-AACArchitectureDiagram.md) | A design drawn as Mermaid (and Markdown that renders it) and editable draw.io, with layers for WAF findings, Azure Policy, guardrails, PSRule and Azure Recommendations. | [Architecture design](docs/guide/architecture-design.md) |
| [`Export-AACArchitectureDecision`](docs/Export-AACArchitectureDecision.md) | Architecture decision records for a design - topology, each pattern, each accepted risk - with the open decisions and assumptions, as Markdown. | [Architecture design](docs/guide/architecture-design.md) |

Full help:

- **In PowerShell:** run `Get-Help <command> -Full`, or `Get-Help about_Azure.Admin.Console` for the module overview.
- **On the web:** see [docs/](docs/Azure.Admin.Console.md).

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

[MIT](LICENSE). What ships from other projects is listed in the [third-party notices](THIRD-PARTY-NOTICES.md).
