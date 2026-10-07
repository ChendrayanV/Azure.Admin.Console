---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACDefenderAssessment.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Invoke-AACDefenderAssessment
---

# Invoke-AACDefenderAssessment

## SYNOPSIS

Microsoft Defender for Cloud assessed across subscriptions - recommendations, attack paths, security alerts, inventory, vulnerabilities, secure score, Defender plans, regulatory compliance and environment settings - with what to improve, as a Spectre.Console view, an object, CSV files and a tabbed, interactive HTML report.

## SYNTAX

### __AllParameterSets

```
Invoke-AACDefenderAssessment [[-SubscriptionId] <string[]>] [[-Section] <string[]>]
 [[-AlertDays] <int>] [[-ScoreWarningPercent] <int>] [[-CsvPath] <string>] [[-HtmlPath] <string>]
 [[-Title] <string>] [-PassThru] [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Read-only (Reader or Security Reader is enough), no Az modules: Azure
Resource Graph (securityresources) for what it holds, and the
Defender for Cloud REST API for the settings it doesn't (security
contacts, integrations, connectors, just-in-time policies, alert
suppression rules) - one call per subscription and setting, in
parallel.

-Section picks what is read (everything by default):

```text
  Recommendations  every recommendation assessed - unhealthy, healthy
                   and not applicable resources, severity, risk level
                   and attack paths (Defender CSPM), secure score
                   control, description and remediation steps - and
                   every unhealthy resource
  AttackPaths      attack paths (Defender CSPM): each step from the
                   entry point to the target, risk factors, MITRE
                   tactics and techniques, story and remediation
  Alerts           security alerts generated in the last -AlertDays,
                   every status, with MITRE tactics and techniques,
                   compromised entity and remediation steps; alert
                   suppression rules
  Inventory        every resource Defender assesses: the plan that
                   covers it (on or off), recommendations by
                   severity, vulnerabilities, active alerts and
                   attack paths
  Vulnerabilities  vulnerability assessment findings (machines, SQL,
                   container images): CVEs, patchable, remediation
  Posture          secure score per subscription and its controls
                   with the potential increase, Defender plans with
                   their sub-plan and extensions, multicloud and
                   DevOps connectors, just-in-time policies
  Compliance       regulatory compliance standards, their controls
                   and the failed assessments
  Settings         security contacts and e-mail notifications,
                   Defender for Endpoint and Defender for Cloud Apps
                   integration
```

Findings, each with its severity and what to do: a plan off for
resources the subscription has; Defender CSPM or Resource Manager
off; Servers on Plan 1; no security contact, alert e-mails off or
only for High alerts, owners not notified; Defender for Endpoint
integration off; a secure score under -ScoreWarningPercent (70);
Critical and High attack paths; High alerts still active, Medium
alerts open over a week; suppression rules with no expiry;
just-in-time ports open to any source.

What you get depends on where the command runs:

```text
  at the prompt    tiles, the subscriptions, the top
                   recommendations, attack paths, active alerts, the
                   plans that are off and the findings, a page at a
                   time
  piped onward     the AAC.DefenderAssessment object, with every
                   table as a property
  -PassThru        the view and the object
  -NoDisplay       the object only
```

-CsvPath (a folder) writes a CSV per table. -HtmlPath writes a tabbed
report in the portal's order - Overview, Findings, Recommendations,
Attack path analysis, Security alerts, Inventory, Vulnerabilities,
Security posture, Regulatory compliance, Environment settings -
where every table is searchable, filterable, groupable and
downloadable, and a row opens all its details (descriptions,
remediation steps, the attack path step by step).

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Invoke-AACDefenderAssessment -HtmlPath .\out\Defender.html
```

Defender for Cloud across every subscription you can see, as a tabbed HTML report.

### Example 2

```powershell
Invoke-AACDefenderAssessment -SubscriptionId '00000000-0000-0000-0000-000000000000' -CsvPath .\out\defender
```

One subscription, a CSV per table.

### Example 3

```powershell
Invoke-AACDefenderAssessment -Section AttackPaths, Alerts -AlertDays 7
```

Only the attack paths and the last week's alerts.

### Example 4

```powershell
(Invoke-AACDefenderAssessment -NoDisplay).Recommendations | Where-Object { $_.Severity -eq 'High' -and $_.UnhealthyResources } | Select-Object Recommendation, UnhealthyResources, Control
```

The High recommendations and how many resources each is on.

### Example 5

```powershell
(Invoke-AACDefenderAssessment -NoDisplay -Section Inventory).Inventory | Where-Object PlanState -EQ 'Off'
```

The resources no Defender plan protects.

## PARAMETERS

### -AlertDays

Security alerts generated in the last this many days (30 by
default).

```yaml
Type: System.Int32
DefaultValue: 30
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

### -CsvPath

A folder to write a CSV per table to.

```yaml
Type: System.String
DefaultValue: None
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

### -HtmlPath

Write the tabbed, interactive HTML report to this file.

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

### -NoDisplay

Return the object without showing the view.

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

Show the view and also return the object.

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

### -ScoreWarningPercent

A subscription's secure score under this percentage (70 by default)
is a finding - High under half of it.

```yaml
Type: System.Int32
DefaultValue: 70
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

### -Section

What to read: Recommendations, AttackPaths, Alerts, Inventory,
Vulnerabilities, Posture, Compliance, Settings. All by default.

```yaml
Type: System.String[]
DefaultValue: "@('Recommendations', 'AttackPaths', 'Alerts', 'Inventory', 'Vulnerabilities', 'Posture', 'Compliance', 'Settings')"
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

### -SubscriptionId

Only these subscriptions. Defaults to every subscription the account
can see.

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

### -Title

The HTML report's title.

```yaml
Type: System.String
DefaultValue: "'Microsoft Defender for Cloud assessment'"
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.DefenderAssessment (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACDefenderAssessment.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
