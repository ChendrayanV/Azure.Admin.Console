---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACAssessment.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Invoke-AACAssessment
---

# Invoke-AACAssessment

## SYNOPSIS

Assesses an Azure environment end to end - an inventory of every resource type with its key settings, the organization, Advisor, retirements, Defender for Cloud, Azure Policy, outages, quotas and cost - as CSV files, an interactive HTML report, a PDF and interactive diagrams, with a live Spectre.Console progress display.

## SYNTAX

### __AllParameterSets

```
Invoke-AACAssessment [[-TenantId] <string>] [[-ManagementGroupId] <string[]>]
 [[-SubscriptionId] <string[]>] [[-ResourceGroupName] <string[]>] [[-TagKey] <string>]
 [[-TagValue] <string>] [[-Category] <string[]>] [[-Output] <string[]>] [[-ReportName] <string>]
 [[-ReportDir] <string>] [[-StorageAccount] <string>] [[-StorageContainer] <string>]
 [[-Title] <string>] [-IncludeTag] [-SecurityCenter] [-SkipAdvisor] [-SkipPolicy] [-IncludeCost]
 [-QuotaUsage] [-SkipApi] [-SkipVMDetail] [-SkipDiagram] [-DiagramFullEnvironment] [-Automation]
 [-PassThru] [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

The module's take on Azure Resource Inventory (ARI): one command
reads the tenant (or the subscriptions, management groups, resource
groups or tag you name) and writes the reports you choose. Read-only;
Reader is enough (Security Reader for Defender, Cost Management
Reader for cost); no Az modules, no Excel.

What it reads, in phases - each a line of the progress display:

```text
  1. Scope        the subscriptions (with their management groups) in
                  scope, and the tenant's management groups
  2. Estate       every resource and resource group, the resource
                  types present; Advisor recommendations (and
                  retirements, always); Defender for Cloud
                  (-SecurityCenter); Azure Policy compliance (unless
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
                  recommendations, the last 6 months' outages
                  (Resource Health service issues), compute quotas
                  (-QuotaUsage), and VM sizes' vCPUs and memory
                  (unless -SkipVMDetail); -SkipApi skips them all
  5. Cost         each resource's cost, this month and last
                  (-IncludeCost, Cost Management)
  6. Reports      CSV, HTML, PDF and diagrams (-Output), then an
                  upload to a blob container (-StorageAccount)
```

Every inventory sheet adds, after its own columns: Retirement (an
Advisor retirement notice for the resource), Advisor (its number of
recommendations), its cost with -IncludeCost, and its tags with
-IncludeTag. The overview sheets: Subscriptions, Resource groups,
Resource types, All resources; then Advisor recommendations,
Advisor score, Retirements, Security recommendations, Secure score,
Policy compliance, Outages, Quotas, Support tickets and Reservation
recommendations.

The reports, in -ReportDir (a folder named after -ReportName and
the time):

```text
  HTML      one page: tiles, charts, the tenant tree, and every sheet
            as a table under its category, listed in the contents -
            searchable, filterable, groupable, each downloadable as CSV
  CSV       a file per sheet
  PDF       the summary, then each category with its sheets' key
            columns (bookmarked)
  Diagram   <name>-Network.html: the network topology - virtual
            networks, subnets, peerings, gateways, firewalls, load
            balancers, private endpoints, NSGs and routes
            (-DiagramFullEnvironment: every resource and how they
            connect); <name>-Organization.html: management groups >
            subscriptions > resource groups; <name>-Resources.html:
            each subscription with its resource types and counts.
            Interactive: pan, zoom, search, details on click, PNG and
            SVG export.
```

Sign-in: the Connect-AAC session. -TenantId signs in to that tenant
first (in the browser) when the session is for another one. In
Azure Automation, -Automation signs in with the account's managed
identity (Connect-AAC -Identity) if no session is there yet,
writes plain progress lines for the job log, and with
-StorageAccount and -StorageContainer uploads the reports to blob
storage (Storage Blob Data Contributor needed).

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Invoke-AACAssessment
```

The whole tenant (everything the account can see): every report, in .\AzureAssessment-\<date\>.

### Example 2

```powershell
Invoke-AACAssessment -TenantId 'contoso.onmicrosoft.com' -SecurityCenter -IncludeTag -IncludeCost
```

Another tenant, with Defender for Cloud, tags and cost.

### Example 3

```powershell
Invoke-AACAssessment -ManagementGroupId 'mg-landingzones' -ReportDir C:\Reports -Output Html, Diagram
A management group's subscriptions: the HTML report and the diagrams.
```

### Example 4

```powershell
Invoke-AACAssessment -SubscriptionId 00000000-0000-0000-0000-000000000000 -TagKey 'Environment' -TagValue 'Production' -Category Compute, Networking
```

Production's compute and network resources in one subscription.

### Example 5

```powershell
Invoke-AACAssessment -Automation -StorageAccount 'stcontosoreports' -StorageContainer 'assessments'
```

In an Azure Automation runbook: managed identity sign-in, and the reports uploaded to blob storage.

### Example 6

```powershell
(Invoke-AACAssessment -Output Csv -NoDisplay).Sheets['Virtual machines'] | Where-Object 'Power state' -NE 'VM running'
```

The VMs that aren't running.

## PARAMETERS

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

### -IncludeCost

Read each resource's actual cost, this month and last (Cost
Management Reader).

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

### -Output

The reports to write: Html, Pdf, Csv, Diagram. All of them by default.

```yaml
Type: System.String[]
DefaultValue: "@('Html', 'Pdf', 'Csv', 'Diagram')"
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

### -ReportDir

Where the reports go: a folder named \<ReportName\>-\<date\> is made in
it. The current folder by default (the temporary folder with
-Automation).

```yaml
Type: System.String
DefaultValue: None
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

### -ReportName

The reports' name: AzureAssessment by default.

```yaml
Type: System.String
DefaultValue: "'AzureAssessment'"
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
reservations, outages, quotas, VM sizes) - Resource Graph only.

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

### -SkipDiagram

Don't draw the diagrams (same as leaving Diagram out of -Output).

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

Don't read Azure Policy compliance.

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

### -StorageAccount

Upload the reports to this storage account (with -StorageContainer).

```yaml
Type: System.String
DefaultValue: None
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

### -StorageContainer

The blob container to upload to.

```yaml
Type: System.String
DefaultValue: None
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
DefaultValue: "'Azure environment assessment'"
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.Assessment (with -PassThru or -NoDisplay, or piped onward)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACAssessment.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
