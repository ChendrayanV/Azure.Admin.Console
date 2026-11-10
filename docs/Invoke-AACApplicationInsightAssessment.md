---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACApplicationInsightAssessment.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Invoke-AACApplicationInsightAssessment
---

# Invoke-AACApplicationInsightAssessment

## SYNOPSIS

Assesses Application Insights components across subscriptions - ingestion and cost, workspace and architecture, security, identity and access, audit and lifecycle - as a heat map, findings, a Spectre.Console view, objects, and CSV, PDF and interactive HTML reports.

## SYNTAX

### __AllParameterSets

```
Invoke-AACApplicationInsightAssessment [[-SubscriptionId] <string[]>]
 [[-ManagementGroupId] <string[]>] [[-ResourceGroupName] <string[]>] [[-Name] <string[]>]
 [[-TimeRange] <string>] [[-View] <string>] [[-ThrottleLimit] <int>] [[-CsvPath] <string>]
 [[-HtmlPath] <string>] [[-PdfPath] <string>] [[-Title] <string>] [-IncludeIngestion]
 [-IncludeActivityLog] [-PassThru] [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Read-only. Always (Reader is enough):

```text
  Resource Graph    the components, their workspaces, availability
                    tests, alert rules and locks
  Resource Manager  each component's daily cap, API keys (never the
                    key), diagnostic settings and role assignments
  metrics           requests, dependencies, exceptions and traces
                    over -TimeRange
```

-IncludeIngestion (Log Analytics Reader): what each workspace-based
component ingested - billed GB by table and day, sampling, trace
severity and health probe requests.
-IncludeActivityLog: the Activity Log over -TimeRange - who changed
each component, purges, API keys created, failed changes.

Findings (High, Medium, Low), under five signals:

```text
  Ingestion & cost     daily cap reached or close to normal volume,
                       no effective cap, no cap warning, no sampling
                       on a busy app, spikes, chatty traces,
                       dependencies or health probes, telemetry sent
                       twice by a diagnostic setting
  Architecture         classic (not workspace-based), workspace
                       missing or in another region, no
                       availability test, retired URL ping and
                       multi-step tests, too few test locations, no
                       alert rule, alerts with no action group,
                       Failure Anomalies off
  Security             local authentication (instrumentation key)
                       allowed, client IPs stored, private link scope
                       with public access left open, API keys
  Identity & access    local authentication off with no Monitoring
                       Metrics Publisher, ready for Entra ID-only
                       ingestion, Owner or access administrators on
                       the component, users instead of groups, many
                       writers, workspace-only permissions
  Audit & lifecycle    no delete lock, no owner tag, no telemetry in
                       the period; with -IncludeActivityLog, purges,
                       API keys created, changes by hand, failures
```

The heat map scores each component 0-100 per signal - the 40 worst at
the prompt and in the reports; clicking a cell in the HTML lists its
findings.

-View sets what is returned (piped onward, -PassThru, -NoDisplay) and
written to -CsvPath: Component (default), Ingestion, Access, Change or
Finding.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Invoke-AACApplicationInsightAssessment
```

Every component's configuration, security, access and findings over the last week.

### Example 2

```powershell
Invoke-AACApplicationInsightAssessment -ResourceGroupName 'rg-app-prod' -TimeRange 30d -IncludeIngestion -IncludeActivityLog -HtmlPath .\out\AppInsights.html -PdfPath .\out\AppInsights.pdf
A month of a workload's components - ingestion and changes included - as reports.
```

### Example 3

```powershell
Invoke-AACApplicationInsightAssessment -IncludeIngestion -View Ingestion -NoDisplay | Sort-Object -Property GB -Descending | Select-Object -First 10
```

The tables that cost the most.

### Example 4

```powershell
Invoke-AACApplicationInsightAssessment -View Finding -NoDisplay | Where-Object Signal -EQ 'Security'
```

The security findings, to hand to the app teams.

## PARAMETERS

### -CsvPath

Write the -View rows to this CSV file.

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
  Position: 8
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -IncludeActivityLog

Read the Activity Log: changes, purges, API keys created and who made
them.

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

### -IncludeIngestion

Read what each workspace-based component ingested, from its
workspace (Log Analytics Reader).

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

### -Name

Only components with these names; wildcards work.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: true
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

### -NoDisplay

Return the rows without showing the view.

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

### -PassThru

Show the view and also return the rows.

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
  Position: 9
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

### -ThrottleLimit

How many requests run at once (1 to 32; 12 by default).

```yaml
Type: System.Int32
DefaultValue: 12
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

### -TimeRange

How far back the metrics, ingestion and Activity Log go: 1d, 3d, 7d
(default), 14d or 30d.

```yaml
Type: System.String
DefaultValue: "'7d'"
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

### -Title

The reports' title.

```yaml
Type: System.String
DefaultValue: "'Application Insights assessment'"
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

### -View

Component, Ingestion, Access, Change or Finding: what is returned and
written to -CsvPath.

```yaml
Type: System.String
DefaultValue: "'Component'"
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.ApplicationInsightAssessment, AAC.ApplicationInsightIngestion, AAC.ApplicationInsightAccess, AAC.ApplicationInsightChange or AAC.ApplicationInsightFinding, by -View (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACApplicationInsightAssessment.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
