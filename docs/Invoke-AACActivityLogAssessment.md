---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACActivityLogAssessment.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Invoke-AACActivityLogAssessment
---

# Invoke-AACActivityLogAssessment

## SYNOPSIS

Assesses the Activity Log of every resource over 90, 180 or 365 days: who changed what and when, when each resource was last used, which are idle or were deleted, changes made by hand, access and secrets touched by people - with subscription, resource group, resource and tags on every row.

## SYNTAX

### __AllParameterSets

```
Invoke-AACActivityLogAssessment [[-SubscriptionId] <string[]>] [[-ManagementGroupId] <string[]>]
 [[-ResourceGroupName] <string[]>] [[-Days] <int>] [[-Source] <string>] [[-WorkspaceId] <string>]
 [[-Category] <string[]>] [[-TagName] <string[]>] [[-RequiredTag] <string[]>] [[-IdleDays] <int>]
 [[-ThrottleLimit] <int>] [[-SliceHours] <int>] [[-View] <string>] [[-CsvPath] <string>]
 [[-HtmlPath] <string>] [[-PdfPath] <string>] [[-Title] <string>] [-ResolveIdentity] [-PassThru]
 [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Read-only. Reads each subscription's Activity Log the fastest way it
allows (Read-AACActivityLog):

```text
  Log Analytics   when the subscription's diagnostic setting sends the
                  Activity Log to a workspace - found automatically,
                  or given with -WorkspaceId: a few queries per
                  workspace, summarised in the workspace, five at a
                  time. Seconds for 90, 180 or 365 days, and the only
                  way past 90.
  Activity Log    otherwise: the REST API - Azure keeps 90 days - cut
                  into about 1,500 slices read side by side.
```

The Coverage view says which each subscription used, and from when its
data goes back (the workspace's retention, or 90 days).

Then every resource (Resource Manager, with created and last-changed
times), joined to its activity - an event on a child counts for the
top-level resource:

```text
  Resources  subscription, resource group, type, name, tags; state
             (Active, New, Idle, Quiet, Deleted, Gone); last used -
             the latest of its last Activity Log event, last change
             and creation - and idle days; operations, writes,
             deletes, actions, failures, changes made by people, the
             callers, the last operation and by whom, who wrote to it
             first, who deleted it
  Activity   one row per resource, caller, operation and status - how
             many times, first and last, caller kind (user, guest,
             service principal, managed identity, Azure), caller IP
  Callers    each caller: operations, writes, deletes, failures,
             resources touched, last seen, top operations
  Findings   guests changing resources and people changing access
             (High); keys and secrets read by people, failure
             hotspots, Activity Log not exported or kept less than the
             window (Medium); changed by hand, idle, missing
             -RequiredTag (Low); deleted in the window (Info)
```

Last used is control-plane: data-plane use (reads, requests,
sign-ins) never reaches the Activity Log - check an idle resource's
metrics before removing it.

Needs Reader (or Monitoring Reader) on the subscriptions; Log Analytics
Reader on the workspaces for the fast path.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Invoke-AACActivityLogAssessment -SubscriptionId $sub -HtmlPath .\activity.html
```

The last 90 days: every resource, its activity and when it was last used, as a tabbed report.

### Example 2

```powershell
Invoke-AACActivityLogAssessment -ManagementGroupId 'mg-landingzones' -Days 365 -TagName CostCenter, Owner -RequiredTag CostCenter -HtmlPath .\activity-year.html -PdfPath .\activity-year.pdf
A year, from the Log Analytics workspaces the subscriptions send their Activity Log to.
```

### Example 3

```powershell
Invoke-AACActivityLogAssessment -SubscriptionId $sub -Days 180 -NoDisplay | Where-Object State -EQ 'Idle' | Sort-Object IdleDays -Descending
```

Resources nobody changed for 90 days or more, longest idle first.

### Example 4

```powershell
Invoke-AACActivityLogAssessment -SubscriptionId $sub -View Coverage -NoDisplay
```

Where each subscription's Activity Log was read from, and how far back it goes.

## PARAMETERS

### -Category

Activity Log categories: Administrative (the default - changes by
users, applications and identities), Policy, Security, ServiceHealth,
ResourceHealth, Alert, Recommendation, Autoscale, or All.

```yaml
Type: System.String[]
DefaultValue: "@('Administrative')"
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

### -CsvPath

Write the -View rows to this CSV file.

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

### -Days

How far back to look (90 by default; 180 or 365 need the Activity Log
sent to a Log Analytics workspace).

```yaml
Type: System.Int32
DefaultValue: 90
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

### -HtmlPath

Write an interactive HTML report.

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

### -IdleDays

Days with no change before a resource counts as idle (90 by default).

```yaml
Type: System.Int32
DefaultValue: 90
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
  Position: 15
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -RequiredTag

Tags every resource should have: a resource missing one is a finding.

```yaml
Type: System.String[]
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

### -ResolveIdentity

Look up service principals' names in Microsoft Graph.

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
  Position: 2
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SliceHours

Hours each Activity Log REST request covers (1 to 24). Automatic by
default: about 1,500 slices in all.

```yaml
Type: System.Int32
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

### -Source

Auto (the default: the workspace where there is one, else the REST
API), Workspace or ActivityLog.

```yaml
Type: System.String
DefaultValue: "'Auto'"
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

### -TagName

Tags to show as columns of their own.

```yaml
Type: System.String[]
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

### -ThrottleLimit

Requests in flight at once for the REST API (1 to 64; 32 by default).

```yaml
Type: System.Int32
DefaultValue: 32
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

### -Title

The reports' title.

```yaml
Type: System.String
DefaultValue: "'Activity Log assessment'"
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

### -View

Resource, Activity, Caller, Finding or Coverage: what is returned and
written to -CsvPath.

```yaml
Type: System.String
DefaultValue: "'Resource'"
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

### -WorkspaceId

The workspace ID (customer ID) of the Log Analytics workspace holding
the Activity Log, instead of finding it from the diagnostic settings.

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.ActivityLogResource, AAC.ActivityLogActivity, AAC.ActivityLogCaller, AAC.ActivityLogFinding or AAC.ActivityLogCoverage, by -View (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACActivityLogAssessment.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
