---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACSentinelAssessment.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Invoke-AACSentinelAssessment
---

# Invoke-AACSentinelAssessment

## SYNOPSIS

Assesses Microsoft Sentinel on a Log Analytics workspace: analytics rules and MITRE ATT&CK coverage, rule templates, data connectors, tables and ingestion, health failures, incidents, automation rules and recommendations - with a Spectre.Console view, an object, and CSV and interactive HTML and PDF reports.

## SYNTAX

### __AllParameterSets

```
Invoke-AACSentinelAssessment [-WorkspaceId] <string> [-SubscriptionId <string[]>] [-Days <int>]
 [-Section <string[]>] [-IncludeEmptyTable] [-CsvPath <string>] [-HtmlPath <string>]
 [-PdfPath <string>] [-Title <string>] [-PassThru] [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Reads one workspace - read-only, nothing is changed - from:

```text
  Azure Resource Manager   whether Sentinel is enabled, its analytics
                           rules and templates, data connectors,
                           incidents and automation rules, and the
                           workspace's tables (plan, retention)
  the workspace itself     KQL: Usage (size and last record per table),
                           _SentinelHealth (failures per resource) and
                           SecurityIncident (when incidents closed)
```

-WorkspaceId is the workspace ID (its customerId GUID, as the portal
shows it), the full resource ID, or the workspace's name.

What comes back:

```text
  AnalyticsRules    every rule: kind, severity, enabled, tactics,
                    frequency, query, its health failures and
                    incidents. Failing rules first.
  TacticCoverage    how many enabled rules declare each MITRE ATT&CK
                    Enterprise tactic
  RuleTemplates     every template the API lists (built-in and from
                    installed solutions): the data it needs, whether
                    that data is arriving and whether a rule uses it.
                    Candidates - data arriving, no rule yet - first.
  Incidents         every incident created in the last -Days: severity,
                    status, owner, classification, hours to close.
                    These hold people's names and email addresses, and
                    so do the reports.
  AutomationRules   every automation rule, in the order they run:
                    state, triggers, actions, expiry
  DataConnectors    every connector the API lists: kind, state, data
                    types. A source can send data without being listed
                    here, so Tables is what shows what really arrives.
  Tables            billable and free GB over -Days, share of billable
                    data, daily average, plan, retention, last record.
                    Tables with no data are left out unless custom, or
                    with -IncludeEmptyTable.
  HealthFailures    what _SentinelHealth reports as failed: resource,
                    operation, count, last failure and reason
  Recommendations   Sentinel not enabled, enabled rules failing, tables
                    that stopped receiving data, health monitoring off,
                    connector or automation failures, billable tables
                    no enabled rule reads, templates to enable, MITRE
                    ATT&CK gaps, incidents with no owner or slow to
                    close, noisy rules, expired or disabled automation,
                    rules with a newer template - by severity, with
                    what to do
```

-Section limits the reading to some of: AnalyticsRules, RuleTemplates,
DataConnectors, Tables, Health, Incidents, AutomationRules,
Recommendations.

Needs Microsoft Sentinel Reader and Log Analytics Reader on the
workspace. What can't be read is reported, and the rest carries on.

What you get depends on where the command runs:

```text
  at the prompt    tiles, then each section - a page at a time
  piped onward     the assessment object, with no view
  -PassThru        the view and the object
  -NoDisplay       the object only
```

-CsvPath writes the analytics rules (one row each). -HtmlPath writes a
tabbed interactive report - a Summary (headline, tiles, charts), then
a tab per section - every table searchable, filterable and
downloadable as CSV. -PdfPath writes the same as a PDF, each section a
bookmarked heading.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Invoke-AACSentinelAssessment -WorkspaceId 00000000-0000-0000-0000-000000000000
```

The whole assessment of one workspace, by its workspace ID.

### Example 2

```powershell
Invoke-AACSentinelAssessment -WorkspaceId 'law-contoso-sentinel' -Days 7 -Section Tables, Health
```

Ingestion and health failures over the last 7 days.

### Example 3

```powershell
Invoke-AACSentinelAssessment -WorkspaceId 'law-contoso-sentinel' -HtmlPath .\out\Sentinel.html -PdfPath .\out\Sentinel.pdf -CsvPath .\out\AnalyticsRules.csv
A tabbed HTML report and a PDF, and the analytics rules as CSV.
```

### Example 4

```powershell
(Invoke-AACSentinelAssessment -WorkspaceId 'law-contoso-sentinel' -Section RuleTemplates -NoDisplay).RuleTemplates | Where-Object Candidate
```

The templates worth enabling: their data is arriving and no rule uses them.

### Example 5

```powershell
(Invoke-AACSentinelAssessment -WorkspaceId 'law-contoso-sentinel' -Section AnalyticsRules -NoDisplay).AnalyticsRules | Where-Object Enabled -EQ $false
```

The analytics rules that are turned off.

### Example 6

```powershell
(Invoke-AACSentinelAssessment -WorkspaceId 'law-contoso-sentinel' -NoDisplay).Recommendations | Where-Object Severity -EQ 'High'
```

The high-severity recommendations.

## PARAMETERS

### -CsvPath

Write the analytics rules to this CSV file.

```yaml
Type: System.String
DefaultValue: None
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

### -Days

How far back ingestion, health and incidents look: 1 to 90 days, 30 by
default.

```yaml
Type: System.Int32
DefaultValue: 30
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

Write a tabbed interactive HTML report to this file.

```yaml
Type: System.String
DefaultValue: None
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

### -IncludeEmptyTable

Also list the tables with no data in the period (a workspace has
hundreds).

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

Return the assessment without showing the view.

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

Show the whole view at once instead of a page at a time.

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

Show the view and also return the assessment.

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

Write a PDF report to this file.

```yaml
Type: System.String
DefaultValue: None
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

### -Section

Only these sections: AnalyticsRules, RuleTemplates, DataConnectors,
Tables, Health, Incidents, AutomationRules, Recommendations. All of
them by default.

```yaml
Type: System.String[]
DefaultValue: None
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

### -SubscriptionId

Where to look for a workspace given by ID (GUID) or name. Every
subscription the account can see by default.

```yaml
Type: System.String[]
DefaultValue: None
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

### -Title

The HTML and PDF reports' title.

```yaml
Type: System.String
DefaultValue: "'Microsoft Sentinel assessment'"
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

### -WorkspaceId

The workspace: its workspace ID (GUID), resource ID or name.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases:
- Workspace
- ResourceId
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: true
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

### AAC.SentinelAssessment (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACSentinelAssessment.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
