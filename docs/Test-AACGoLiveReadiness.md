---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Test-AACGoLiveReadiness.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Test-AACGoLiveReadiness
---

# Test-AACGoLiveReadiness

## SYNOPSIS

A go-live gate: runs the Well-Architected assessment on a workload and says Ready or Not ready - each pillar's score against a minimum, no high-severity findings, the checks that must pass - with the blockers, a Spectre.Console view, and CSV, PDF and HTML reports. -FailOnGap fails a pipeline stage when it isn't ready.

## SYNTAX

### __AllParameterSets

```
Test-AACGoLiveReadiness [[-SubscriptionId] <string[]>] [[-ManagementGroupId] <string[]>]
 [[-ResourceGroupName] <string[]>] [[-Pillar] <string[]>] [[-MinimumScore] <int>]
 [[-PillarMinimum] <hashtable>] [[-RequiredCheck] <string[]>] [[-AttestationPath] <string>]
 [[-HeatMapBy] <string>] [[-ExcludeCheck] <string[]>] [[-CsvPath] <string>] [[-HtmlPath] <string>]
 [[-PdfPath] <string>] [[-Title] <string>] [-AllowHighFinding] [-RequireAttestation] [-NoAdvisor]
 [-NoDefender] [-FailOnGap] [-PassThru] [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

The same read and scores as Invoke-AACWafAssessment (one Resource
Graph batch, Advisor, Defender for Cloud, the questionnaire's answers
with -AttestationPath). Then the gates, each Pass, Fail or Warning:

```text
  Pillar score       each pillar at -MinimumScore (70) or more; a
                     pillar can have its own with -PillarMinimum
                     @{ Security = 80 }
  High findings      no failed high-severity catalogue check (Advisor
                     and Defender count through the pillar scores);
                     -AllowHighFinding turns this into a warning
  Required checks    every check matching -RequiredCheck (IDs,
                     wildcards) tested and passed everywhere
  Principles covered every design principle assessed, by a check or
                     the questionnaire; a warning unless
                     -RequireAttestation
```

Ready when no gate fails.

What you get:

```text
  at the prompt    the verdict, the gates and blockers, the heat maps
                   and the findings
  piped onward     the AAC.GoLiveReadiness object (Ready, Verdict,
                   Overall, Pillars, Gates, Blockers, Warnings)
  -PassThru        the view and the object
  -NoDisplay       the object only
```

-FailOnGap throws when not ready, after the view and any reports, so
`pwsh -File` exits non-zero. -CsvPath writes the gates; -HtmlPath and
-PdfPath the full report with a Go-live tab.

## EXAMPLES

### Example 1

```powershell
Test-AACGoLiveReadiness -ResourceGroupName 'rg-app-prod'
```

Is the workload ready to go live, and if not, what blocks it.

### Example 2

```powershell
Test-AACGoLiveReadiness -ResourceGroupName 'rg-app-prod' -PillarMinimum @{ Security = 85 } -RequiredCheck 'RE-02', 'SE-1*' -AttestationPath .\waf-answers.csv -RequireAttestation -PdfPath .\GoLive.pdf
A strict gate with the team's answers, as a PDF for sign-off.
```

### Example 3

```powershell
Test-AACGoLiveReadiness -ResourceGroupName $env:WORKLOAD_RG -NoDisplay -FailOnGap -HtmlPath "$env:BUILD_ARTIFACTSTAGINGDIRECTORY/golive.html"
```

In a pipeline: the stage fails when the workload isn't ready, and the report is kept as an artifact.

## PARAMETERS

### -AllowHighFinding

High-severity findings warn instead of blocking.

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

### -AttestationPath

An answered questionnaire (Export-AACWafQuestionnaire).

```yaml
Type: System.String
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

### -CsvPath

Write the gates to this CSV file.

```yaml
Type: System.String
DefaultValue: None
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

### -ExcludeCheck

Check IDs to leave out; wildcards work.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: true
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

### -FailOnGap

Throw a terminating error when not ready (for pipelines).

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

### -HeatMapBy

The heat maps' columns: Subscription, ResourceGroup (the default here)
or ResourceType.

```yaml
Type: System.String
DefaultValue: "'ResourceGroup'"
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

### -HtmlPath

Write an interactive HTML report.

```yaml
Type: System.String
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

### -ManagementGroupId

Only the subscriptions under these management groups.

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

### -MinimumScore

The lowest pillar score that passes (0 to 100; 70 by default).

```yaml
Type: System.Int32
DefaultValue: 70
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

### -NoAdvisor

Leave out Azure Advisor.

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

### -NoDefender

Leave out Defender for Cloud.

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

Return the readiness without showing the view.

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

Show the view and also return the readiness.

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
  Position: 12
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Pillar

The pillars to gate on (all five by default).

```yaml
Type: System.String[]
DefaultValue: "@('Reliability', 'Security', 'Cost Optimization', 'Operational Excellence', 'Performance Efficiency')"
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

### -PillarMinimum

A minimum per pillar, e.g. @{ Security = 80; 'Cost Optimization' = 50 }.

```yaml
Type: System.Collections.Hashtable
DefaultValue: '@{}'
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

### -RequireAttestation

Every design principle must be assessed - by a check or the
questionnaire.

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

### -RequiredCheck

Check IDs that must pass everywhere they apply; wildcards work
(Get-AACWafCheck lists them).

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: true
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

### -ResourceGroupName

The workload's resource groups.

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

### -Title

The reports' title.

```yaml
Type: System.String
DefaultValue: "'Go-live readiness'"
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.GoLiveReadiness (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Test-AACGoLiveReadiness.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
