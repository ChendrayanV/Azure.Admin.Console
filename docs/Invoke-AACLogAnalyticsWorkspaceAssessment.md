---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACLogAnalyticsWorkspaceAssessment.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Invoke-AACLogAnalyticsWorkspaceAssessment
---

# Invoke-AACLogAnalyticsWorkspaceAssessment

## SYNOPSIS

Assesses a Log Analytics workspace: billable and free tables and their size, every workspace setting, recommendations, data collection rules and the Workspace Insights views (Overview, Usage, Health, Agents, Query Audit, Data Collection Rules, Change Log) - with a Spectre.Console view, an object, and CSV and interactive HTML reports.

## SYNTAX

### __AllParameterSets

```
Invoke-AACLogAnalyticsWorkspaceAssessment [-WorkspaceId] <string> [-SubscriptionId <string[]>]
 [-Days <int>] [-Section <string[]>] [-IncludeEmptyTable] [-CsvPath <string>] [-HtmlPath <string>]
 [-Title <string>] [-PassThru] [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Reads one workspace - read-only, nothing is changed - from:

```text
  Azure Resource Manager   the workspace's settings, its tables
                           (plan, retention), data exports, linked
                           services and storage, diagnostic
                           settings, saved searches, and the
                           activity log (Change Log)
  Azure Resource Graph     the data collection rules sending to it
                           and their associations, its solutions,
                           its Azure Advisor recommendations
  the workspace itself     KQL: Usage (size per table, per day, per
                           solution; per resource and computer for
                           the last 24 hours), _LogOperation
                           (Health), Heartbeat (Agents, latency),
                           LAQueryLogs (Query Audit) - up to 5
                           queries at a time
```

-WorkspaceId is the workspace ID (its customerId GUID, as the portal
shows it), the full resource ID, or the workspace's name.

What comes back:

```text
  Tables            billable and not billable: billable and free GB
                    over -Days, share of billable data, daily
                    average, last record, plan (Analytics, Basic,
                    Auxiliary), interactive and total retention,
                    Azure or custom. Tables with no data are left
                    out unless custom, on another plan or retention,
                    or -IncludeEmptyTable.
  Settings          every workspace setting: general, pricing tier
                    and daily cap, retention, access (local
                    authentication, network access, private link),
                    data collection (workspace transformation DCR,
                    solutions), data exports, linked services and
                    storage, diagnostic settings - and anything else
                    the workspace has, under Other
  Recommendations   Azure Advisor's for the workspace, and the
                    assessment's own: legacy tier, commitment tiers,
                    daily cap hit or near, spikes, retention, tables
                    for the Basic plan, ContainerLog and
                    AzureDiagnostics, unused custom tables, retired
                    MMA agents, silent agents, operation errors,
                    unassociated DCRs, shared keys, network access,
                    access control mode, query auditing, diagnostic
                    settings - by severity, with what to do
  Insights          the Workspace Insights tabs, as row sets:
                    Overview, Usage, Health, Agents, QueryAudit,
                    DataCollectionRules, ChangeLog
```

-Section limits the reading to some of: Overview, Tables, Settings,
Recommendations, Usage, Health, Agents, QueryAudit,
DataCollectionRules, ChangeLog.

Needs Reader on the workspace (Log Analytics Reader to query it) and
on its resource group for the activity log. A query that can't run
(no LAQueryLogs because query auditing is off, no Heartbeat because
no agent reports there) is reported, and the rest carries on.

What you get depends on where the command runs:

```text
  at the prompt    tiles, then each section - a page at a time
  piped onward     the assessment object, with no view
  -PassThru        the view and the object
  -NoDisplay       the object only
```

-CsvPath writes the tables (one row each). -HtmlPath writes an
interactive report with every section, searchable and downloadable
as CSV.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Invoke-AACLogAnalyticsWorkspaceAssessment -WorkspaceId 00000000-0000-0000-0000-000000000000
```

The whole assessment of one workspace, by its workspace ID.

### Example 2

```powershell
Invoke-AACLogAnalyticsWorkspaceAssessment -WorkspaceId 'law-contoso-prod' -Days 7 -HtmlPath .\out\Workspace.html -CsvPath .\out\Tables.csv
```

The last 7 days, as an HTML report and the tables as CSV.

### Example 3

```powershell
(Invoke-AACLogAnalyticsWorkspaceAssessment -WorkspaceId 'law-contoso-prod' -Section Tables -NoDisplay).Tables | Where-Object Billing -EQ 'Billable' | Sort-Object BillableGB -Descending | Select-Object -First 10
```

The ten largest billable tables.

### Example 4

```powershell
(Invoke-AACLogAnalyticsWorkspaceAssessment -WorkspaceId 'law-contoso-prod' -NoDisplay).Recommendations | Where-Object Severity -EQ 'High'
```

The high-severity recommendations.

## PARAMETERS

### -CsvPath

Write the tables to this CSV file.

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

How far back the usage, health, agents, query audit and change log
look: 1 to 90 days, 30 by default.

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

Write an interactive HTML report to this file.

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

### -Section

Only these sections: Overview, Tables, Settings, Recommendations,
Usage, Health, Agents, QueryAudit, DataCollectionRules, ChangeLog.
All of them by default.

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

The HTML report's title.

```yaml
Type: System.String
DefaultValue: "'Log Analytics workspace assessment'"
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

### AAC.LogAnalyticsWorkspaceAssessment (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACLogAnalyticsWorkspaceAssessment.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
