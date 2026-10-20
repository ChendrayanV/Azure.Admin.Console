---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Show-AACDashboard.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Show-AACDashboard
---

# Show-AACDashboard

## SYNOPSIS

A dashboard of your Azure estate: health, security, policy, governance, Advisor, the estate itself, the latest changes and (with -IncludeCost) the spend - one status and an Estate score at the top, and what to do next at the bottom.

## SYNTAX

### All (Default)

```
Show-AACDashboard [-Hours <int>] [-Section <string[]>] [-IncludeCost] [-HtmlPath <string>]
 [-PdfPath <string>] [-CsvPath <string>] [-Title <string>] [-Watch <int>] [-PassThru] [-NoDisplay]
 [-NoPaging]
```

### Subscription

```
Show-AACDashboard [-SubscriptionId <string[]>] [-Hours <int>] [-Section <string[]>] [-IncludeCost]
 [-HtmlPath <string>] [-PdfPath <string>] [-CsvPath <string>] [-Title <string>] [-Watch <int>]
 [-PassThru] [-NoDisplay] [-NoPaging]
```

### Select

```
Show-AACDashboard [-Select] [-Hours <int>] [-Section <string[]>] [-IncludeCost] [-HtmlPath <string>]
 [-PdfPath <string>] [-CsvPath <string>] [-Title <string>] [-Watch <int>] [-PassThru] [-NoDisplay]
 [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Reads it all in one Azure Resource Graph batch (no Az modules), with
the Connect-AAC sign-in:

```text
  ── Azure Admin Console :: Dashboard ─────────────────────────────
  admin@contoso.com · tenant ... · all subscriptions · 9 Oct 2026 10:42
  ✗ Action needed  2 resource(s) unavailable; 1 active Azure service issue(s)

  [ subscriptions ] [ resources ] [ resource groups ] [ regions ]
  [ unhealthy ] [ Advisor High ] [ changes in 24h ]

  ╭─ Session ─────────────────╮ ╭─ Resource Health ──────────╮
  │ Account   admin@...       │ │ ✓ Available    1,204       │
  │ Tenant    ...             │ │ ✗ Unavailable  2           │
  │ Token     ✓ valid until … │ │ ⚠ Degraded     1           │
  ╰───────────────────────────╯ ╰────────────────────────────╯
  Subscriptions (state) · Resources by region · Azure Service
  Health - active events · Unhealthy resources · Azure Advisor
  recommendations · Recent changes (create, update, delete - what,
  where, who)
```

The status at the top:

```text
  ✗ Action needed     resources are unavailable, or an Azure
                      service issue is active in these subscriptions
  ⚠ Needs attention   resources are degraded, Advisor has
                      High-impact recommendations, planned
                      maintenance or an advisory is active, or
                      something couldn't be read
  ✓ Healthy           none of these
```

Beyond that one screen, from the same Resource Graph batch:

```text
  Scores       the Estate score (0-100: the average of the share of
               resources available, the secure score, the policy
               compliance and the Advisor score that could be read,
               less a little when a subscription nears the role
               assignment limit or spend jumps)
  Security     secure score, active alerts and unresolved
               recommendations by severity, Defender plans on
  Governance   policy compliance and the assignments with the most
               non-compliant resources, the closest role assignment
               limit, privileged role assignments at subscription or
               above, unused disks, public IPs and NICs, tag coverage
  Advisor      the Advisor score and the potential annual savings
  Estate       resources by type and by subscription
  Changes      the last 14 days, day by day, and who made the most
  Cost         with -IncludeCost (Cost Management, one query per
               subscription): month to date against the same days
               last month, a forecast, the last 30 days, the services
               that cost most
  Next         what to do, ranked across every section, with the
               command that goes deeper
```

-Section shows only some sections. -HtmlPath and -PdfPath write it
as a report - an Overview, then a tab per section; -CsvPath writes
what to do next. -Watch refreshes it every so many seconds, for a
screen on the wall (Ctrl+C stops it).

Symbols and colours are the module's (Unicode, or ASCII in a console
that isn't UTF-8), so the state never depends on colour alone. What
couldn't be read (Resource Health, Service Health, Advisor or the
change history need Reader on the subscriptions) is listed at the
end, and the rest is still shown.

Scope: every subscription the account can see, those in
-SubscriptionId, or - with -Select - those you tick in a list at the
console.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Show-AACDashboard
```

The dashboard for every subscription you can see.

### Example 2

```powershell
Show-AACDashboard -Select -Hours 72
```

Pick the subscriptions from a list, with the changes of the last three days.

### Example 3

```powershell
Show-AACDashboard -IncludeCost -HtmlPath .\Dashboard.html
```

Everything, with the spend, as a report with a tab per section.

### Example 4

```powershell
Show-AACDashboard -Section Health, Security -Watch 300
```

Health and security, refreshed every five minutes.

### Example 5

```powershell
(Show-AACDashboard -NoDisplay).Actions | Format-Table
```

What to do next, as objects.

### Example 6

```powershell
(Show-AACDashboard -NoDisplay).UnhealthyResources | Format-Table
```

The unavailable and degraded resources, as objects.

### Example 7

```powershell
if ((Show-AACDashboard -SubscriptionId $prod -NoDisplay).Status -eq 'Failed') { Send-MyAlert }
```

Act on the dashboard's status in a script.

## PARAMETERS

### -CsvPath

Write what to do next to this CSV file.

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

### -Hours

How far back the recent changes go, in hours (1 to 336 - Resource
Graph keeps 14 days). Defaults to 24.

```yaml
Type: System.Int32
DefaultValue: 24
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

Write the dashboard as an interactive HTML report.

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

### -IncludeCost

Read the spend from Cost Management (slower: Cost Management allows
a few queries a minute).

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

Return the AAC.Dashboard object without showing the dashboard.

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

Show the whole dashboard at once instead of a page at a time.

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

Show the dashboard and also return it as an AAC.Dashboard object.

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

Write the dashboard as a PDF report.

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

Only these sections: Health, Security, Policy, Governance, Advisor,
Estate, Changes, Cost. The status, scores and what to do next always
show.

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

### -Select

Pick the subscriptions from a list at the console (arrow keys, space
to tick, Enter to accept). Needs an interactive console; in a script
use -SubscriptionId.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Select
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

Only these subscriptions.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Subscription
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
DefaultValue: "'Azure dashboard'"
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

### -Watch

Refresh the dashboard every this many seconds (30 or more) until
Ctrl+C.

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

### AAC.Dashboard (with -PassThru or -NoDisplay, or piped onward)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Show-AACDashboard.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
