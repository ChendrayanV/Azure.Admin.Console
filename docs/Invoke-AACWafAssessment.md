---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACWafAssessment.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Invoke-AACWafAssessment
---

# Invoke-AACWafAssessment

## SYNOPSIS

Assesses the estate against the Azure Well-Architected Framework's five pillars - Reliability, Security, Cost Optimization, Operational Excellence and Performance Efficiency - scored by pillar, design principle and check, with workbook-style heat maps by subscription, resource group or resource type, findings and what to do, a Spectre.Console view, objects, and CSV, PDF and interactive HTML reports.

## SYNTAX

### __AllParameterSets

```
Invoke-AACWafAssessment [[-SubscriptionId] <string[]>] [[-ManagementGroupId] <string[]>]
 [[-ResourceGroupName] <string[]>] [[-Pillar] <string[]>] [[-HeatMapBy] <string>]
 [[-ExcludeCheck] <string[]>] [[-AttestationPath] <string>] [[-HistoryPath] <string>]
 [[-CostTag] <string[]>] [[-OwnerTag] <string[]>] [[-CsvPath] <string>] [[-HtmlPath] <string>]
 [[-PdfPath] <string>] [[-Title] <string>] [-NoAdvisor] [-NoDefender] [-KeepDuplicates] [-PassThru]
 [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Read-only, with one batch of Azure Resource Graph queries - Reader is
enough, no Az modules. Every check is evaluated against that one read:

```text
  the resources the checks test (VMs, scale sets, disks, snapshots,
  storage, SQL, App Service, Key Vault, AKS, load balancers,
  Application Gateways, public IPs, NSGs, NICs, Cosmos DB, Redis,
  container registries, Recovery Services vaults, virtual networks,
  resource groups), VM extensions, autoscale settings, deployment
  slots, what Azure Backup protects, how many alert rules and action
  groups each subscription has, Azure Advisor's recommendations in
  the pillars' categories, and Defender for Cloud's plans, secure
  scores and high-severity assessments.
```

Each pillar is scored against its design principles (Microsoft
Learn):

```text
  Reliability  business requirements, resilience, recovery,
               operations, simplicity - zones, backups, redundancy,
               instance counts, retired Basic SKUs, health probes, SLA
               tiers
  Security     security readiness, confidentiality, integrity,
               availability, sustained posture - Defender plans and
               secure score, TLS, HTTPS, public access, network
               restrictions, keys and local accounts, management ports
               open to the internet, WAF, DDoS
  Cost         cost-management discipline, cost-efficiency, usage and
               rate optimization, monitoring - cost-allocation tags
               (-CostTag), unattached disks, unused public IPs, VMs
               stopped but billed, empty plans, old snapshots, Azure
               Hybrid Benefit, old VM generations
  Operational  DevOps culture, standards, observability, deployment,
  Excellence   automation - owner and environment tags (-OwnerTag),
               the Azure Monitor agent, boot diagnostics, Application
               Insights, alert rules and action groups, deployment
               slots, platform patching, AKS auto-upgrade
  Performance  targets, capacity, sustained performance, optimization
  Efficiency   - autoscale on plans, scale sets, AKS and Application
               Gateway, accelerated networking, SSD OS disks, SQL and
               Redis tiers
```

Advisor and Defender are checks too, one per pillar (AD-HA, AD-SEC,
AD-COST, AD-OPS, AD-PERF, DF-HIGH): a resource with an open
recommendation fails. An item that is the same finding as a catalogue
check on the same resource is counted once, by the catalogue check,
whose result says 'Also flagged by Advisor' (or Defender);
-KeepDuplicates counts both.

What no API can test - business requirements, threat models, budgets,
performance targets, team practices - comes from the questionnaire:
Export-AACWafQuestionnaire writes one question per principle, the team
answers Yes, Partly or No, and -AttestationPath scores the answers
(checks AT-..., heat-map column 'Attested'). -HistoryPath keeps a line
per run and shows the change since the last one.

Scores are out of 100: a check's is the share of resources that pass;
a principle's and a pillar's weigh their checks by severity (High 3,
Medium 2, Low 1). A principle no check covers is shown as not
assessed: it needs a review or attestation. Each pillar gets a
maturity: Initial (under 50), Developing, Established (75+),
Optimised (90+).

The heat maps - pillars, and design principles, by -HeatMapBy - show
each cell's score in colour: at the prompt (the first eight columns),
in the PDF (ten columns a table) and in the HTML report, where
clicking a cell lists its findings.

What you get depends on where the command runs:

```text
  at the prompt    tiles, the heat maps, the principles, and the top
                   findings - a page at a time
  piped onward     one AAC.WafCheckResult per check and resource
  -PassThru        the view and the results
  -NoDisplay       the results only
```

-CsvPath writes every result; -HtmlPath an interactive report
(summary with heat maps, principles, checks, findings); -PdfPath a PDF.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Invoke-AACWafAssessment
```

All five pillars across every subscription, with heat maps by subscription.

### Example 2

```powershell
Export-AACWafQuestionnaire -Path .\waf-answers.csv
Invoke-AACWafAssessment -ResourceGroupName 'rg-app-prod' -AttestationPath .\waf-answers.csv -HistoryPath .\waf-history.csv -HtmlPath .\out\WAF.html
A workload's review with the team's answers, and its trend from run to run.
```

### Example 3

```powershell
Invoke-AACWafAssessment -ResourceGroupName 'rg-app-prod' -HeatMapBy ResourceType -HtmlPath .\out\WAF.html -PdfPath .\out\WAF.pdf
```

One workload's go-live review, as HTML and PDF reports.

### Example 4

```powershell
Invoke-AACWafAssessment -ManagementGroupId 'mg-landingzones' -Pillar Reliability -HeatMapBy ResourceGroup
```

The landing zones' reliability, resource group by resource group.

### Example 5

```powershell
Invoke-AACWafAssessment -NoDisplay | Where-Object { $_.Status -eq 'Fail' -and $_.Severity -eq 'High' } | Group-Object Check
```

The high-severity gaps, by check.

## PARAMETERS

### -AttestationPath

An answered questionnaire (Export-AACWafQuestionnaire) to score with
the automated checks.

```yaml
Type: System.String
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

The tag names that allocate cost (any one counts).

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

Write every result to this CSV file.

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

### -ExcludeCheck

Check IDs to leave out; wildcards work: 'SE-24', 'AD-\*', 'DF-\*'.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: true
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

### -HeatMapBy

The heat maps' columns: Subscription (the default), ResourceGroup or
ResourceType.

```yaml
Type: System.String
DefaultValue: "'Subscription'"
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

### -HistoryPath

A CSV file that keeps a line per run - overall and pillar scores - for
the trend.

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

### -HtmlPath

Write an interactive HTML report.

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

### -KeepDuplicates

Count an Advisor or Defender item even when a catalogue check already
tested the same thing on the same resource.

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

Only the subscriptions under these management groups.

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

### -NoAdvisor

Leave out Azure Advisor's recommendations.

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

### -NoDefender

Leave out Defender for Cloud: plans, secure score and assessments.

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

### -NoDisplay

Return the results without showing the view.

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

Show the whole view at once.

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

The tag names that name an owner (any one counts).

```yaml
Type: System.String[]
DefaultValue: "@('Owner', 'Contact', 'TechnicalOwner', 'BusinessOwner')"
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

### -PassThru

Show the view and also return the results.

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

Write a PDF report.

```yaml
Type: System.String
DefaultValue: None
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

### -Pillar

The pillars to assess (all five by default): Reliability, Security,
'Cost Optimization', 'Operational Excellence', 'Performance
Efficiency'.

```yaml
Type: System.String[]
DefaultValue: "@('Reliability', 'Security', 'Cost Optimization', 'Operational Excellence', 'Performance Efficiency')"
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

### -ResourceGroupName

Only these resource groups (a workload).

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

### -SubscriptionId

Only these subscriptions.

```yaml
Type: System.String[]
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

The reports' title.

```yaml
Type: System.String
DefaultValue: "'Well-Architected assessment'"
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.WafCheckResult (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACWafAssessment.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
