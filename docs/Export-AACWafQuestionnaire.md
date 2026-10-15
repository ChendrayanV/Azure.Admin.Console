---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Export-AACWafQuestionnaire.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Export-AACWafQuestionnaire
---

# Export-AACWafQuestionnaire

## SYNOPSIS

Writes the Well-Architected questionnaire - one question per design principle, for what no API can test - as a CSV the team answers and Invoke-AACWafAssessment -AttestationPath scores.

## SYNTAX

### __AllParameterSets

```
Export-AACWafQuestionnaire [-Path] <string> [[-Pillar] <string[]>] [-Force]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

One row per design principle of each pillar (-Pillar, all five by
default): Pillar, Principle, Question, Answer, Evidence, Owner,
AnsweredOn, and Learn (the principle on Microsoft Learn). Open it in
Excel or any editor and fill in:

```text
  Answer      Yes, Partly, No or NotApplicable (empty: not answered
              yet - the principle stays not assessed unless a check
              covers it)
  Evidence    where to find the proof: a wiki page, a test report, a
              ticket
  Owner       who answered, or who owns the gap
```

Yes scores 100, Partly 50, No 0; NotApplicable leaves it out.

Nothing in Azure is read or changed. An existing file is only
replaced with -Force (its answers would be lost).

## EXAMPLES

### Example 1

```powershell
Export-AACWafQuestionnaire -Path .\waf-answers.csv
```

All 24 design principles' questions, ready to answer.

### Example 2

```powershell
Export-AACWafQuestionnaire -Path .\reliability.csv -Pillar Reliability
```

Then: Invoke-AACWafAssessment -Pillar Reliability -AttestationPath .\reliability.csv

## PARAMETERS

### -Force

Replace the file if it exists.

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

Where to write the CSV.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
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

### -Pillar

Only these pillars' principles.

```yaml
Type: System.String[]
DefaultValue: "@('Reliability', 'Security', 'Cost Optimization', 'Operational Excellence', 'Performance Efficiency')"
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### System.IO.FileInfo

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Export-AACWafQuestionnaire.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
