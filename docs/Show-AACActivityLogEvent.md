---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Show-AACActivityLogEvent.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Show-AACActivityLogEvent
---

# Show-AACActivityLogEvent

## SYNOPSIS

Shows Activity Log events the way an admin reads them - when, what, the result and why it failed, who (decoded from the token), where - from the JSON the portal shows, a correlation ID, a Log Analytics workspace or the pipeline; as a console view, CSV, HTML and PDF.

## SYNTAX

### Query (Default)

```
Show-AACActivityLogEvent [-InputObject <Object[]>] [-CorrelationId <string[]>]
 [-SubscriptionId <string[]>] [-WorkspaceId <string>] [-Days <int>] [-Status <string[]>]
 [-ResolveIdentity] [-IncludeClaims] [-View <string>] [-CsvPath <string>] [-HtmlPath <string>]
 [-PdfPath <string>] [-Title <string>] [-PassThru] [-NoDisplay] [-NoPaging]
```

### Path

```
Show-AACActivityLogEvent -Path <string[]> [-SubscriptionId <string[]>] [-WorkspaceId <string>]
 [-Days <int>] [-Status <string[]>] [-ResolveIdentity] [-IncludeClaims] [-View <string>]
 [-CsvPath <string>] [-HtmlPath <string>] [-PdfPath <string>] [-Title <string>] [-PassThru]
 [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Read-only. An Activity Log event holds about sixty values, six levels
deep; the useful ones are hard to read as stored. Each event becomes
one flat row (AAC.ActivityLogEvent, ConvertTo-AACActivityLogEvent):

```text
  When    time, phase (begin or end request), ingestion delay
  What    operation, the authorised action and scope, category,
          channel, level
  Result  status, HTTP status and sub-status, and for a failure the
          innermost error code, message and target from the
          statusMessage (JSON inside a string), what kind of failure
          it is and what to do - as Get-AACResourceError reads it
  Who     user, guest, service principal, managed identity or Azure;
          app and object ID; how it signed in (public client, client
          secret, certificate or federated credential, or a user's
          authentication methods); home or external tenant;
          directory roles; when the token was issued and expires;
          caller IP. -ResolveIdentity names the service principal
          and the roles from Microsoft Graph
  Where   subscription, resource group, type, name, location, tags,
          a portal link
  Trace   correlation, operation and event IDs, tenant, hierarchy
```

The token's opaque values (aio, rh, uti, xms_\*) are left out:
-IncludeClaims adds every claim (Claim:\<name\> columns, and a Claims
view).

Where the events come from:

```text
  -Path            a JSON file: one event as the portal's JSON tab
                   shows it, an array of them, or a REST response
                   ({ value: [...] })
  -CorrelationId   every event of the operation, from the Activity
                   Log (90 days; -SubscriptionId, else every
                   subscription you can see) or, with -WorkspaceId,
                   the Log Analytics workspace it is sent to (as far
                   back as -Days and its retention)
  the pipeline     event objects or JSON text (ConvertFrom-Json,
                   Get-Content -Raw), or rows with a CorrelationId -
                   Invoke-AACActivityLogAssessment -View Activity and
                   Get-AACResourceError rows, for instance
```

Signed in, the events are enriched with subscription names and the
resource's location and tags; a file needs no sign-in.

## EXAMPLES

### Example 1

```powershell
Show-AACActivityLogEvent -Path .\event.json
```

An event copied from the portal's JSON tab, readable: who, what, the error and what to do.

### Example 2

```powershell
Connect-AAC
Show-AACActivityLogEvent -CorrelationId $correlationId -SubscriptionId $sub -PdfPath .\incident.pdf
```

Every event of one operation, as a PDF to attach to the incident.

### Example 3

```powershell
Invoke-AACActivityLogAssessment -SubscriptionId $sub -View Activity -NoDisplay | Where-Object Status -EQ 'Failed' | Show-AACActivityLogEvent -HtmlPath .\failures.html
```

The full events behind the failed operations an assessment found.

### Example 4

```powershell
Show-AACActivityLogEvent -CorrelationId $correlationId -WorkspaceId $workspaceId -Days 365 -ResolveIdentity -IncludeClaims -CsvPath .\event.csv
```

From the workspace the Activity Log is sent to, with names from Microsoft Graph and every claim.

## PARAMETERS

### -CorrelationId

Show every event of these operations.

```yaml
Type: System.String[]
DefaultValue: None
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

### -CsvPath

Write the -View rows to this CSV file.

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

How far back to look for -CorrelationId (90 by default; the Activity
Log keeps 90, a workspace its retention).

```yaml
Type: System.Int32
DefaultValue: 90
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

Write an interactive HTML report.

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

### -IncludeClaims

Add every token claim, the opaque ones too.

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

### -InputObject

Event objects, JSON text, or rows with a CorrelationId (and
SubscriptionId or ResourceId), from the pipeline.

```yaml
Type: System.Object[]
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Query
  Position: Named
  IsRequired: false
  ValueFromPipeline: true
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

### -Path

JSON files of Activity Log events.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Path
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -PdfPath

Write a PDF report - a card per event, for an incident or change.

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

### -ResolveIdentity

Name service principals and directory roles from Microsoft Graph.

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

### -Status

Only events with these statuses (Failed, Succeeded, Started...).

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

Where to look for -CorrelationId (every subscription you can see by
default).

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

The reports' title.

```yaml
Type: System.String
DefaultValue: "'Activity Log events'"
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

### -View

Event, Detail, Error, Caller or Claim: what is returned and written to
-CsvPath.

```yaml
Type: System.String
DefaultValue: "'Event'"
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

Read -CorrelationId's events from this Log Analytics workspace
(its workspace ID) instead of the Activity Log.

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.ActivityLogEvent, AAC.ActivityLogEventDetail, AAC.ActivityLogEventError, AAC.ActivityLogEventCaller or AAC.ActivityLogEventClaim, by -View (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Show-AACActivityLogEvent.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
