---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Test-AACSentinelRuleQuery.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Test-AACSentinelRuleQuery
---

# Test-AACSentinelRuleQuery

## SYNOPSIS

Replays Microsoft Sentinel analytics rule queries - or a query you are writing - over their last run windows, to see how many results each run returns, whether it would alert and how often, and whether the columns the rule maps exist, before enabling or changing a rule.

## SYNTAX

### Rule (Default)

```
Test-AACSentinelRuleQuery [-WorkspaceId] <string> [-SubscriptionId <string[]>]
 [-ResourceGroupName <string>] [-Name <string[]>] [-RuleId <string[]>] [-Runs <int>]
 [-CsvPath <string>] [-HtmlPath <string>] [-PdfPath <string>] [-Title <string>] [-PassThru]
 [-NoDisplay] [-NoPaging]
```

### Query

```
Test-AACSentinelRuleQuery [-WorkspaceId] <string> -Query <string> [-SubscriptionId <string[]>]
 [-ResourceGroupName <string>] [-Frequency <string>] [-Period <string>] [-TriggerOperator <string>]
 [-TriggerThreshold <int>] [-Runs <int>] [-CsvPath <string>] [-HtmlPath <string>]
 [-PdfPath <string>] [-Title <string>] [-PassThru] [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

For each scheduled or NRT rule, runs its KQL in the workspace over the
last -Runs windows as Sentinel would schedule them: each window ends
one query frequency before the next and looks back the query period.
Read-only: the rule isn't changed and no alert is raised.

Each rule (AAC.SentinelRuleQueryTest): Name, Status (Error, Warning,
Alerting or Quiet), Kind, Enabled, Frequency, Period, Trigger,
Grouping, Runs, RunsAlerting, LatestResults, AverageResults,
MaxResults, EstimatedAlerts (over the runs tested), Findings,
MissingColumns, Columns, Error, Note, RuleId, Sample (up to 5 rows of
the latest window), RunDetail (each window: start, end, results,
whether it would alert) and Query.

Findings: the query fails; columns the rule maps for entities, custom
details or alert overrides aren't in its results; a look-back over 14
days; a frequency longer than the look-back; alerting in every run
tested; reaching 150 alerts in a run; over 10,000 characters;
searching every table.

A query that calls ago() or now() counts from when it runs, so only
its latest window is tested. NRT rules are tested in 1-hour windows.
Each window is a query against the workspace and its cost: test a few
rules at a time.

Rules come from -Name, from the pipeline (Get-AACSentinelAnalyticsRule
output), or, with neither, every enabled scheduled and NRT rule.
-Query tests a query that isn't a rule yet.

Needs Microsoft Sentinel Reader and Log Analytics Reader on the
workspace.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Test-AACSentinelRuleQuery -WorkspaceId 'law-contoso-sentinel' -Name 'Rare admin sign-in'
```

One rule's last 6 runs replayed: results, alerts and findings.

### Example 2

```powershell
Get-AACSentinelAnalyticsRule -WorkspaceId 'law-contoso-sentinel' -State Disabled -Kind Scheduled -NoDisplay | Test-AACSentinelRuleQuery -WorkspaceId 'law-contoso-sentinel' -Runs 24
```

What the disabled scheduled rules would have done over their last 24 runs.

### Example 3

```powershell
Test-AACSentinelRuleQuery -WorkspaceId 'law-contoso-sentinel' -Query 'SigninLogs | where ResultType == "50126"' -Frequency PT5M -Period PT1H -TriggerThreshold 10 -Runs 12
A query you are writing, as a rule that runs every 5 minutes.
```

### Example 4

```powershell
(Test-AACSentinelRuleQuery -WorkspaceId 'law-contoso-sentinel' -Name 'Brute force*' -NoDisplay).RunDetail
```

Each replayed window of a rule: when, how many results, alert or not.

## PARAMETERS

### -CsvPath

Write the results to this CSV file.

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

### -Frequency

With -Query: how often it would run, as an ISO 8601 duration (PT1H by
default).

```yaml
Type: System.String
DefaultValue: "'PT1H'"
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Query
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

### -Name

The rules to test, by display name or rule ID; wildcards work.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: true
Aliases: []
ParameterSets:
- Name: Rule
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

### -Period

With -Query: how far back each run would look (PT1H by default).

```yaml
Type: System.String
DefaultValue: "'PT1H'"
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Query
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Query

A KQL query to test instead of a rule.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Query
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ResourceGroupName

Narrows a workspace given by name, when the name is in more than one
resource group.

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

### -RuleId

The rules to test, by rule ID. Takes RuleId from the pipeline, so
Get-AACSentinelAnalyticsRule's output can be piped in.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Rule
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: true
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Runs

How many of the latest run windows to replay: 1 to 48, 6 by default.

```yaml
Type: System.Int32
DefaultValue: 6
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
DefaultValue: "'Microsoft Sentinel rule query test'"
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

### -TriggerOperator

With -Query: GreaterThan (the default), LessThan, Equal or NotEqual.

```yaml
Type: System.String
DefaultValue: "'GreaterThan'"
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Query
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -TriggerThreshold

With -Query: the result count the operator compares with (0 by
default).

```yaml
Type: System.Int32
DefaultValue: 0
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Query
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
- WorkspaceName
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

### AAC.SentinelRuleQueryTest (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Test-AACSentinelRuleQuery.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
