# Azure tenant assessment

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Invoke-AACTenantAssessment`](../Invoke-AACTenantAssessment.md)

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
