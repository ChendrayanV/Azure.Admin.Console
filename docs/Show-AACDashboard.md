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

A one-screen dashboard of your Azure estate: who you're signed in as, the subscriptions in scope, resources by region, Resource Health, active Azure Service Health events, Advisor and the latest changes - with one status at the top.

## SYNTAX

### All (Default)

```
Show-AACDashboard [-Hours <int>] [-PassThru] [-NoDisplay] [-NoPaging]
```

### Subscription

```
Show-AACDashboard [-SubscriptionId <string[]>] [-Hours <int>] [-PassThru] [-NoDisplay] [-NoPaging]
```

### Select

```
Show-AACDashboard [-Select] [-Hours <int>] [-PassThru] [-NoDisplay] [-NoPaging]
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
(Show-AACDashboard -NoDisplay).UnhealthyResources | Format-Table
```

The unavailable and degraded resources, as objects.

### Example 4

```powershell
if ((Show-AACDashboard -SubscriptionId $prod -NoDisplay).Status -eq 'Failed') { Send-MyAlert }
```

Act on the dashboard's status in a script.

## PARAMETERS

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
