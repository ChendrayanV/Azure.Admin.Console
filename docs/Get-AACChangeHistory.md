---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACChangeHistory.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Get-AACChangeHistory
---

# Get-AACChangeHistory

## SYNOPSIS

What changed in Azure, who changed it, when and from where - with the properties before and after, how to undo it, and the alerts and health events that followed - a timeline for incident response, change control and audits.

## SYNTAX

### Hours (Default)

```
Get-AACChangeHistory [-SubscriptionId <string[]>] [-ManagementGroupId <string[]>]
 [-ResourceGroupName <string[]>] [-ResourceType <string[]>] [-Caller <string[]>] [-Hours <int>]
 [-CorrelationMinutes <int>] [-IncludeFailed] [-CsvPath <string>] [-HtmlPath <string>]
 [-PdfPath <string>] [-Title <string>] [-PassThru] [-NoDisplay] [-NoPaging]
```

### Window

```
Get-AACChangeHistory -StartTime <datetime> [-SubscriptionId <string[]>]
 [-ManagementGroupId <string[]>] [-ResourceGroupName <string[]>] [-ResourceType <string[]>]
 [-Caller <string[]>] [-EndTime <datetime>] [-CorrelationMinutes <int>] [-IncludeFailed]
 [-CsvPath <string>] [-HtmlPath <string>] [-PdfPath <string>] [-Title <string>] [-PassThru]
 [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Reads, for the window (-Hours, or -StartTime and -EndTime):

```text
  Activity Log      every subscription's administrative operations
                    (writes, deletes, actions), one change per
                    correlation ID: the caller, client IP, operation
                    and how it ended
  Resource changes  Resource Graph's property-level changes (up to 14
                    days back): each property's value before and
                    after
  Incidents         alerts fired and resources Resource Health
                    reports unavailable or degraded
```

Each change (AAC.ChangeRecord) has:

```text
  a risk     High for deletes, access (role assignments, locks, key
             vault access policies), network security, Azure Policy,
             keys read and diagnostic settings removed; Medium for
             other network changes, SKU or size changes and
             restarts; Low otherwise - and at least High when an
             incident followed it
  an origin  Manual (a person), Automation (an app, identity or
             pipeline) or Azure - manual changes are the ones made
             outside infrastructure as code
  a revert   how to undo it: set the properties back (their before
             values), delete what was created, recreate what was
             deleted - and how much effort that is
  incidents  alerts on the resource or its resource group, and
             Resource Health events on it, within
             -CorrelationMinutes (120) after it: possibly caused by it
```

The view is a timeline, newest first; the HTML report adds charts by
hour, caller and kind, and the incidents.

Read-only; Reader (or Monitoring Reader) on the subscriptions. The
Activity Log keeps 90 days; Resource Graph's changes, 14.

## EXAMPLES

### Example 1

```powershell
Get-AACChangeHistory
```

Everything changed in the last 24 hours, newest first.

### Example 2

```powershell
Get-AACChangeHistory -ResourceGroupName 'rg-app-prod' -StartTime '2026-10-08 22:00' -EndTime '2026-10-09 02:00'
```

What changed around an outage last night.

### Example 3

```powershell
Get-AACChangeHistory -Hours 168 -NoDisplay | Where-Object Origin -EQ 'Manual' | Export-Csv .\ManualChanges.csv -NoTypeInformation
A week of changes made by hand - for the change advisory board.
```

## PARAMETERS

### -Caller

Only changes made by these callers - a UPN or an application ID
(wildcards work).

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

### -CorrelationMinutes

How long after a change an incident counts as possibly caused by it
(5 to 1440; 120 by default).

```yaml
Type: System.Int32
DefaultValue: 120
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

Write the changes to this CSV file.

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

### -EndTime

The end of the window (now by default).

```yaml
Type: System.DateTime
DefaultValue: '[datetime]::Now'
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Window
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Hours

How far back to look, in hours (1 to 2160 - 90 days; 24 by default).

```yaml
Type: System.Int32
DefaultValue: 24
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Hours
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

### -IncludeFailed

Keep the operations that failed (left out by default: they changed
nothing).

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

Return the changes without showing the view.

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

Show the view and also return the changes.

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

Only changes in these resource groups (wildcards work).

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

### -ResourceType

Only changes to these resource types, e.g. 'microsoft.network/\*'.

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

### -StartTime

The start of the window, instead of -Hours.

```yaml
Type: System.DateTime
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Window
  Position: Named
  IsRequired: true
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
DefaultValue: "'Azure change history'"
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

### AAC.ChangeRecord

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACChangeHistory.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
