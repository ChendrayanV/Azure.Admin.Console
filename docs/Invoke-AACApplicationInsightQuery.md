---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACApplicationInsightQuery.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Invoke-AACApplicationInsightQuery
---

# Invoke-AACApplicationInsightQuery

## SYNOPSIS

Queries Application Insights - the exceptions of the last few hours by default, or any KQL query - from a Log Analytics workspace or an Application Insights resource, with a Spectre.Console view, flattened objects, and CSV and interactive HTML exports.

## SYNTAX

### Workspace (Default)

```
Invoke-AACApplicationInsightQuery -LogWorkspaceName <string> [-SubscriptionId <string[]>]
 [-ResourceGroupName <string>] [-Last <string>] [-TableName <string>] [-MinimumSeverity <string>]
 [-ExceptionType <string[]>] [-AppRoleName <string[]>] [-Search <string>] [-Top <int>]
 [-Query <string>] [-CsvPath <string>] [-HtmlPath <string>] [-Title <string>] [-PassThru]
 [-NoDisplay] [-NoPaging]
```

### Component

```
Invoke-AACApplicationInsightQuery -ApplicationInsightsName <string> [-SubscriptionId <string[]>]
 [-ResourceGroupName <string>] [-Last <string>] [-TableName <string>] [-MinimumSeverity <string>]
 [-ExceptionType <string[]>] [-AppRoleName <string[]>] [-Search <string>] [-Top <int>]
 [-Query <string>] [-CsvPath <string>] [-HtmlPath <string>] [-Title <string>] [-PassThru]
 [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Finds the Log Analytics workspace (-LogWorkspaceName) or Application
Insights resource (-ApplicationInsightsName) by name with Azure
Resource Graph, then runs the query through the Log Analytics or
Application Insights query API. Their tokens come from the
Connect-AAC sign-in, with no second sign-in and no Az modules. Needs
Log Analytics Reader (or Reader) on it.

Without -Query it reads exceptions: the AppExceptions table of a
workspace (workspace-based Application Insights) or the exceptions
table of an Application Insights resource - newest first, from the
last -Last (default 2 hours), narrowed by -MinimumSeverity,
-ExceptionType (wildcards), -AppRoleName and -Search. A workspace
only holds the exceptions of the Application Insights resources that
send to it; when it has none, a warning names those resources, or -
if none send there - the ones you can see and where each sends, with
the -ApplicationInsightsName command to query one directly. Each row is
flattened to one AAC.ApplicationInsightsException, the same for both
tables:

```text
  when and how bad    TimeGenerated (UTC), Severity, SeverityLevel
  what                ExceptionType, Message, OuterType, OuterMessage,
                      InnermostType, InnermostMessage
  details             DetailType, DetailMessage, DetailSeverityLevel
                      (the outermost entry of the details array),
                      DetailCount, StackTop (method, file and line)
  where               Method, Assembly, ProblemId, HandledAt,
                      OperationName, OperationId, AppRoleName,
                      AppRoleInstance, AppVersion, SdkVersion
  who                 ClientType, ClientCountryOrRegion, ClientCity
  plus                ItemCount (sampling), CustomProperties
                      ("key=value; ..."), Source, ResourceId
```

With -TableName it reads another table the same way - requests,
dependencies, traces, customEvents, pageViews, availabilityResults,
... - newest first from the last -Last, narrowed by -AppRoleName,
-Search (any column) and -MinimumSeverity (traces), each row an
object with the table's columns. Either schema's name works for
either source: 'requests' on a workspace reads AppRequests, and
'AppTraces' on an Application Insights resource reads traces. A
workspace's other tables (e.g. ContainerLog) work too.

With -Query it runs any KQL you give - against the workspace's
tables (AppExceptions, AppRequests, AppTraces, ...) or the
resource's (exceptions, requests, traces, ...) - bounded by -Last,
and returns each row as an object with the query's columns.

What you get depends on where the command runs:

```text
  at the prompt    a Spectre.Console view: tiles, exceptions over
                   time, by severity, top exception types, top
                   problems and the latest exceptions (for -Query:
                   a table of the rows) - a page at a time
  piped onward     the objects, with no view
  -PassThru        the view and the objects
  -NoDisplay       the objects only
```

-CsvPath and -HtmlPath (a self-contained, interactive report) export
them; with either, the console shows only the progress and the files
written.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Invoke-AACApplicationInsightQuery -SubscriptionId '00000000-0000-0000-0000-000000000000' -LogWorkspaceName 'law-contoso-prod'
```

The exceptions of the last 2 hours in that workspace.

### Example 2

```powershell
Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-contoso-prod' -Last 1d -MinimumSeverity Error -AppRoleName 'orders-api'
A day of errors and worse from one app.
```

### Example 3

```powershell
Invoke-AACApplicationInsightQuery -ApplicationInsightsName 'appi-contoso-portal' -ExceptionType '*SqlException' -Search 'timeout'
SQL timeouts, from the Application Insights resource.
```

### Example 4

```powershell
Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-contoso-prod' -Last 7d -HtmlPath .\out\Exceptions.html
A week of exceptions as an interactive HTML report.
```

### Example 5

```powershell
Invoke-AACApplicationInsightQuery -ApplicationInsightsName 'appi-contoso-portal' -TableName requests -Last 1d -Search '/api/orders'
A day of requests to the orders API.
```

### Example 6

```powershell
Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-contoso-prod' -TableName traces -MinimumSeverity Warning -AppRoleName 'orders-api'
```

Warnings and worse that one app traced (the workspace's AppTraces).

### Example 7

```powershell
Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-contoso-prod' -Query 'AppRequests | where Success == false | summarize Failed = count() by Name | top 10 by Failed'
```

Any KQL query: the ten most failed requests.

### Example 8

```powershell
Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-contoso-prod' -NoDisplay | Group-Object ExceptionType | Sort-Object Count -Descending
```

The exceptions as objects, grouped by type.

## PARAMETERS

### -ApplicationInsightsName

The Application Insights resource (its classic schema: exceptions,
requests, traces, ...).

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases:
- ComponentName
ParameterSets:
- Name: Component
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -AppRoleName

Only rows from these apps / cloud roles.

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

### -CsvPath

Also write the rows to this CSV file.

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

### -ExceptionType

Only these exception types; wildcards work, e.g. '\*SqlException' or
'System.Net.\*'.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: true
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

Also write an interactive HTML report to this file.

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

### -Last

How far back to look: minutes, hours or days, e.g. '30m', '2h' (the
default) or '7d'.

```yaml
Type: System.String
DefaultValue: "'2h'"
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

### -LogWorkspaceName

The Log Analytics workspace that workspace-based Application Insights
sends its data to.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases:
- WorkspaceName
ParameterSets:
- Name: Workspace
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -MinimumSeverity

Only exceptions (or, with -TableName traces, traces) of at least this
severity: Verbose, Information, Warning, Error or Critical.

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

### -NoDisplay

Return the objects without showing the view.

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

Show the view and also return the objects.

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

### -Query

Run this KQL query instead of the exceptions query. -Last still
bounds it.

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

### -ResourceGroupName

The resource group the workspace or resource is in, when the name is
used more than once.

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

### -Search

Only exceptions whose type or messages contain this text - or, with
-TableName, rows with this text in any column.

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

### -SubscriptionId

The subscription the workspace or resource is in. Needed only when
the name is used in more than one subscription.

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

### -TableName

Read this table instead of the exceptions: requests, dependencies,
traces, customEvents, pageViews, availabilityResults,
performanceCounters, customMetrics, browserTimings - or their
workspace names (AppRequests, AppTraces, ...), which work for either
source. A workspace's other tables work too. Tab completes the
names.

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

### -Title

The HTML report's title.

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

### -Top

At most this many rows, newest first. By default every row in the
period is read (up to the query API's own limit of 500,000 rows) and
the view pages through them all.

```yaml
Type: System.Int32
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.ApplicationInsightsException, or the table's or query's rows with -TableName or -Query (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACApplicationInsightQuery.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
