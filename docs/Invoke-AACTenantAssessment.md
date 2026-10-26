---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACTenantAssessment.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Invoke-AACTenantAssessment
---

# Invoke-AACTenantAssessment

## SYNOPSIS

Assesses an Azure tenant end to end - the organization, an inventory of every resource type with its key settings and policy compliance, Azure Policy, the Well-Architected Framework, PSRule for Azure, Advisor, retirements, Defender for Cloud, FinOps and cost, outages and quotas - as CSV files, an interactive HTML report, a PDF and interactive diagrams, with a live Spectre.Console progress display.

## SYNTAX

### __AllParameterSets

```
Invoke-AACTenantAssessment [[-TenantId] <string>] [[-ManagementGroupId] <string[]>]
 [[-SubscriptionId] <string[]>] [[-ResourceGroupName] <string[]>] [[-TagKey] <string>]
 [[-TagValue] <string>] [[-Category] <string[]>] [[-PSRuleBaseline] <string>]
 [[-CostTag] <string[]>] [[-ActivityDays] <int>] [[-ExpiryDays] <int>] [[-OwnerTag] <string[]>]
 [[-ProductionPattern] <string>] [[-HtmlPath] <string>] [[-PdfPath] <string>] [[-CsvPath] <string>]
 [[-DiagramPath] <string>] [[-StorageAccount] <string>] [[-StorageContainer] <string>]
 [[-Title] <string>] [-IncludeTag] [-SecurityCenter] [-SkipAdvisor] [-SkipPolicy] [-PSRule]
 [-SkipWaf] [-IncludeCost] [-QuotaUsage] [-Full] [-SkipIdentity] [-SkipKeyVault] [-SkipApi]
 [-SkipVMDetail] [-DiagramFullEnvironment] [-Automation] [-PassThru] [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

The module's take on Azure Resource Inventory (ARI), and the one
command to run first in a tenant you need to understand: it reads
the tenant (or the subscriptions, management groups, resource
groups or tag you name) and writes the reports you choose.
Read-only; Reader is enough (Security Reader for Defender, Cost
Management Reader for cost); no Az modules, no Excel. -Full turns on
everything that is off by default.

The focused assessments go deeper into one service or discipline -
Invoke-AACWafAssessment (a workload's review, with the team's
answers and the trend), Invoke-AACPolicyAssessment,
Invoke-AACDefenderAssessment, Invoke-AACGovernanceAssessment and the
service ones (AKS, Cosmos DB, Function Apps, Log Analytics, Service
Bus, storage, virtual networks).

What it reads, in phases - each a line of the progress display:

```text
  1. Scope        the subscriptions (with their management groups) in
                  scope, and the tenant's management groups
  2. Estate       every resource and resource group, the resource
                  types present; Advisor recommendations (and
                  retirements, always); Defender for Cloud
                  (-SecurityCenter); Azure Policy compliance - by
                  policy, resource group and resource (unless
                  -SkipPolicy); support tickets
  3. Inventory    a sheet per resource type present - ~95 types, in
                  the categories Compute, Hybrid, Containers,
                  Databases, Analytics, AI, Integration, IoT,
                  Management, Monitoring, Networking, Security,
                  Storage and Web - each with the settings that
                  matter for it (a VM's size, power state, OS, disks,
                  IP, network and security settings; a storage
                  account's TLS, public access, shared keys and
                  firewall; ...), as Resource Graph projections
  4. Azure APIs   per subscription: the Advisor score, reservation
                  recommendations, the budgets, the last 6 months'
                  outages (Resource Health service issues), compute
                  quotas (-QuotaUsage), and VM sizes' vCPUs and
                  memory (unless -SkipVMDetail); -SkipApi skips them
                  all
  5. Well-Architected  the checks of Invoke-AACWafAssessment across
                  the five pillars - Reliability, Security, Cost
                  Optimization, Operational Excellence, Performance
                  Efficiency - scored by pillar, design principle
                  and check (unless -SkipWaf)
  6. Cost         each resource's cost, this month and last
                  (-IncludeCost, Cost Management)
  7. PSRule       PSRule for Azure's rules on the resources (-PSRule)
  8. Governance   the policy assignments in force and every policy
                  they apply (unless -SkipPolicy), FinOps, and one
                  list of recommendations
  9. Reports      the reports asked for (-HtmlPath, -PdfPath,
                  -CsvPath, -DiagramPath), then an upload to a blob
                  container (-StorageAccount)
```

Every inventory sheet (and All resources) adds, after its own
columns: Retirement (an Advisor retirement notice for the
resource), Advisor (its number of recommendations), its policy
compliance (Policy - Non-compliant, Compliant, Exempt or Not
evaluated; Non-compliant policies; Failing policies, by name), WAF
gaps (the Well-Architected checks it fails), PSRule failures (with
-PSRule), its cost with -IncludeCost, and its tags with -IncludeTag.
The overview sheets: Subscriptions, Resource groups, Resource types,
All resources; then Advisor recommendations, Advisor score,
Retirements, Security recommendations, Secure score, Policy
compliance, Outages, Quotas, Support tickets and Reservation
recommendations. Then:

```text
  Well-Architected   WAF pillars (score and maturity), WAF design
                     principles, WAF checks and WAF findings (each
                     failed check on each resource, with what to do)
  FinOps             Savings opportunities (by lever: Waste -
                     unattached disks, unused public IPs, VMs
                     stopped but billed, empty plans, old snapshots;
                     Rightsizing and Rate - Advisor's cost
                     recommendations, reservations, savings plans;
                     Licensing - Azure Hybrid Benefit; Modernise -
                     old VM generations - each with its estimated
                     annual saving), Cost allocation (the resources
                     with a cost-allocation tag, -CostTag, and the
                     cost of those without), Budgets (spent and
                     forecast against each budget, the alerts, the
                     subscriptions with none) and, with
                     -IncludeCost, Cost by service, Cost by
                     resource group and Top cost resources (this
                     month projected against last month)
```

and the governance sheets:

```text
  Policy compliance  Compliance by initiative, by resource group and
                     by standard (the controls of CIS, NIST, ISO
                     27001, the Microsoft cloud security benchmark
                     ... initiatives), and each non-compliant
                     resource with why and how to fix it
  Policy inventory   Policy assignments, and every policy in force
                     with its effect, resource types, controls and
                     status (Failed, Passed, Manual review, Exempt,
                     Not evaluated, Disabled)
  PSRule results     PSRule rules (checked, passed, failed, with
                     their documentation) and the failed resources
                     (-PSRule)
  Recommendations    Resource recommendations: Advisor, Defender,
                     retirements, unattached and empty resources,
                     policy non-compliance, PSRule, the
                     Well-Architected findings and FinOps (budgets,
                     cost allocation) in one list, each with a
                     severity, category and what to do
```

The reports - each written only where its own parameter says, none
by default:

```text
  -HtmlPath     a tabbed workbook: an Executive summary (tiles - the
            Well-Architected score, the estimated savings, cost-tag
            coverage ... - charts - a click filters the table behind
            them - and the tenant tree), then Policy compliance,
            Policy inventory, Well-Architected, PSRule results,
            Resource recommendations, FinOps, Resources, Inventory,
            Advisor, Security and Health; every table
            searchable, filterable, groupable, with each row's
            details a click away, and downloadable as CSV
  -PdfPath      the summary, then each category with its sheets' key
                columns (bookmarked)
  -CsvPath      a folder: a CSV file per sheet
  -DiagramPath  a folder: TenantAssessment-Network.html, the network
                topology - virtual networks, subnets, peerings,
                gateways, firewalls, load balancers, private
                endpoints, NSGs and routes (-DiagramFullEnvironment:
                every resource and how they connect);
                TenantAssessment-Organization.html, management
                groups > subscriptions > resource groups;
                TenantAssessment-Resources.html, each subscription
                with its resource types and counts. Interactive:
                pan, zoom, search, details on click, PNG and SVG
                export.
```

Without any of them the run shows its summary and returns the
assessment (-PassThru, -NoDisplay): every sheet is in its Sheets.

Sign-in: the Connect-AAC session. -TenantId signs in to that tenant
first (in the browser) when the session is for another one. In
Azure Automation, -Automation signs in with the account's managed
identity (Connect-AAC -Identity) if no session is there yet, and
writes plain progress lines for the job log. -StorageAccount and
-StorageContainer upload the reports written to blob storage, under
TenantAssessment/\<date\>/ (Storage Blob Data Contributor needed);
with no report path given, every report is written to a temporary
folder for the upload.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Invoke-AACTenantAssessment -HtmlPath .\Tenant.html -PdfPath .\Tenant.pdf
```

The whole tenant (everything the account can see), as an HTML and a PDF report.

### Example 2

```powershell
Invoke-AACTenantAssessment -HtmlPath C:\Reports\Tenant.html -CsvPath C:\Reports\csv -DiagramPath C:\Reports\diagrams
```

The HTML report, a CSV file per sheet and the diagrams, each where you say.

### Example 3

```powershell
Invoke-AACTenantAssessment -TenantId 'contoso.onmicrosoft.com' -Full
```

Another tenant, with everything: Defender for Cloud, cost, tags, PSRule for Azure and quotas.

### Example 4

```powershell
Invoke-AACTenantAssessment -SecurityCenter -IncludeTag -IncludeCost -CostTag 'CostCenter', 'Department'
```

Defender for Cloud, tags and cost, with the organisation's own cost-allocation tags.

### Example 5

```powershell
(Invoke-AACTenantAssessment -IncludeCost -NoDisplay).Sheets['Savings opportunities'] | Sort-Object 'Est. annual savings' -Descending | Select-Object -First 10
```

The ten biggest savings.

### Example 6

```powershell
(Invoke-AACTenantAssessment -NoDisplay).Sheets['All resources'] | Where-Object Policy -EQ 'Non-compliant' | Select-Object Name, Type, 'Failing policies'
```

Each non-compliant resource and the policies it fails.

### Example 7

```powershell
Invoke-AACTenantAssessment -ManagementGroupId 'mg-landingzones' -HtmlPath .\LandingZones.html -DiagramPath .\diagrams
A management group's subscriptions: the HTML report and the diagrams.
```

### Example 8

```powershell
Invoke-AACTenantAssessment -SubscriptionId 00000000-0000-0000-0000-000000000000 -TagKey 'Environment' -TagValue 'Production' -Category Compute, Networking
```

Production's compute and network resources in one subscription.

### Example 9

```powershell
Invoke-AACTenantAssessment -Automation -StorageAccount 'stcontosoreports' -StorageContainer 'assessments'
```

In an Azure Automation runbook: managed identity sign-in, and every report uploaded to blob storage.

### Example 10

```powershell
(Invoke-AACTenantAssessment -NoDisplay).Sheets['Virtual machines'] | Where-Object 'Power state' -NE 'VM running'
```

The VMs that aren't running.

## PARAMETERS

### -ActivityDays

The days of Activity Log read for changes and failed deployments (30
by default; 0 reads none).

```yaml
Type: System.Int32
DefaultValue: 30
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 9
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Automation

Run in an Azure Automation runbook: sign in with the managed
identity if not signed in, and write plain progress lines.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Category

Only these inventory categories: Compute, Hybrid, Containers,
Databases, Analytics, AI, Integration, IoT, Management, Monitoring,
Networking, Security, Storage, Web. The overview sheets are always
written.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 6
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -CostTag

The tag names that allocate cost (any one counts), for the Cost
allocation sheet and the Well-Architected cost-tag checks.

```yaml
Type: System.String[]
DefaultValue: "@('CostCenter', 'CostCentre', 'Cost Center', 'Project', 'Application', 'BillingCode')"
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 8
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -CsvPath

Write a CSV file per sheet into this folder (made if missing).

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 15
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -DiagramFullEnvironment

Draw every resource in the network diagram, not only the network.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -DiagramPath

Draw the network, organization and resources diagrams into this
folder (made if missing).

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 16
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ExpiryDays

Credentials expiring within this many days are flagged (30 by
default).

```yaml
Type: System.Int32
DefaultValue: 30
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 10
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Full

Everything that is off by default: -SecurityCenter, -IncludeCost,
-IncludeTag, -PSRule and -QuotaUsage.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -HtmlPath

Write the interactive HTML report to this file.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 13
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -IncludeCost

Read each resource's actual cost, this month and last (Cost
Management Reader): the cost columns, the estimated savings, and
the Cost by service, Cost by resource group and Top cost resources
sheets.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -IncludeTag

Add each resource's tags to every inventory sheet.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ManagementGroupId

Only the subscriptions under these management groups (at any depth).

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 1
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -NoDisplay

Return the assessment without showing the summary.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -NoPaging

Show the summary at once instead of a page at a time.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -OwnerTag

The tag names that name an owner (any one counts), for the owner-tag
coverage and the ownership map.

```yaml
Type: System.String[]
DefaultValue: "@('Owner', 'Contact', 'TechnicalOwner', 'BusinessOwner')"
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 11
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -PassThru

Show the summary and also return the assessment.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -PdfPath

Write the PDF report to this file.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 14
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ProductionPattern

A regular expression that recognises production in a subscription
or resource group name, or an Environment, Env, Stage or Tier tag
value: production resources are judged more strictly (backup, zones,
locks, Dev/Test offers).

```yaml
Type: System.String
DefaultValue: "'(?i)(^|[-_.\\s])(prod|prd|production|live)([-_.\\s]|$)'"
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 12
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -PSRule

Run PSRule for Azure's rules on the resources in scope too: the
PSRule results tab, and its failures among the recommendations.
Needs PSRule.Rules.Azure (Install-PSResource PSRule.Rules.Azure
-Scope CurrentUser); it reads each resource's child settings, so it
takes a while on a large estate.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -PSRuleBaseline

The PSRule for Azure baseline (Azure.Default by default), e.g.
Azure.Pillar.Security or Azure.GA_2024_12.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 7
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -QuotaUsage

Read the compute quotas in use, per subscription and region.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ResourceGroupName

Only these resource groups.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 3
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SecurityCenter

Read Defender for Cloud: the unhealthy recommendations and each
subscription's secure score.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SkipAdvisor

Don't read Advisor recommendations (retirements are still read).

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SkipApi

Don't call the per-subscription Azure APIs (Advisor score,
reservations, budgets, outages, quotas, VM sizes, PIM, classic
administrators, locks, the Activity Log, diagnostic settings,
regions, reservation and savings plan use) - Resource Graph only.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SkipIdentity

Don't read access: no privileged role assignments, Privileged
Identity Management, custom roles or Microsoft Graph (principals and
app registration credentials).

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SkipKeyVault

Don't list the Key Vaults' secrets, keys and certificates (their
expiry dates come from each vault's data plane - Key Vault Reader,
and a network path to the vault).

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SkipPolicy

Don't read Azure Policy compliance, or the policy inventory.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SkipVMDetail

Don't read VM sizes' vCPUs and memory (Compute SKUs).

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SkipWaf

Don't run the Well-Architected checks: no Well-Architected tab, WAF
gaps column or WAF findings among the recommendations, and the
FinOps waste comes from the inventory alone.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -StorageAccount

Upload the reports to this storage account (with -StorageContainer).

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 17
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -StorageContainer

The blob container to upload to.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 18
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SubscriptionId

Only these subscriptions.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 2
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -TagKey

Only resources with this tag (any case).

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 4
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -TagValue

Only resources with this tag value (with -TagKey: that tag with that
value).

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 5
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -TenantId

The tenant to assess. Signs in to it first if the current session is
for another tenant (or there is none).

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Title

The HTML and PDF reports' title.

```yaml
Type: System.String
DefaultValue: "'Azure tenant assessment'"
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 19
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.TenantAssessment (with -PassThru or -NoDisplay, or piped onward)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACTenantAssessment.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
