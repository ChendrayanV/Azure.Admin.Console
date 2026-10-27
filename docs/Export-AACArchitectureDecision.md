---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Export-AACArchitectureDecision.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Export-AACArchitectureDecision
---

# Export-AACArchitectureDecision

## SYNOPSIS

Step 6: writes architecture decision records (Markdown) for the design - topology, each pattern, each accepted risk.

## SYNTAX

### __AllParameterSets

```
Export-AACArchitectureDecision [-Design] <Object> [-Path] <string> [[-Accept] <string[]>]
 [[-Reason] <string>] [[-Owner] <string>] [[-ReviewBy] <datetime>] [[-GuardrailPath] <string>]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

One numbered file per decision, plus README.md listing them with the
open decisions and assumptions. Files of the same name are
replaced. Offline.

## EXAMPLES

### Example 1

```powershell
Export-AACArchitectureDecision -Design $design -Path .\adr -Owner 'Platform team'
```

The records and README.md.

### Example 2

```powershell
Export-AACArchitectureDecision -Design $design -Path .\adr -Accept 'REL-MR-01' -Reason 'One region for phase 1'
```

Also records an accepted risk.

## PARAMETERS

### -Accept

Accepted risks: a rule ID or rule:component.

```yaml
Type: System.String[]
DefaultValue: '@()'
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

### -Design

The design, or the path of a saved one.

```yaml
Type: System.Object
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: true
  ValueFromPipeline: true
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -GuardrailPath

Your guardrails.

```yaml
Type: System.String
DefaultValue: None
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

### -Owner

Who owns the decisions.

```yaml
Type: System.String
DefaultValue: "''"
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

### -Path

The folder to write to.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 1
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Reason

Why the risks are accepted.

```yaml
Type: System.String
DefaultValue: "''"
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

### -ReviewBy

When accepted risks are reviewed (90 days from now by default).

```yaml
Type: System.DateTime
DefaultValue: (Get-Date).AddDays(90)
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

### System.IO.FileInfo

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Export-AACArchitectureDecision.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
