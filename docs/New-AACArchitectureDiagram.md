---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/New-AACArchitectureDiagram.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: New-AACArchitectureDiagram
---

# New-AACArchitectureDiagram

## SYNOPSIS

Step 5: draws the design as Mermaid, Markdown and draw.io files, coloured by its findings, with compliance layers.

## SYNTAX

### __AllParameterSets

```
New-AACArchitectureDiagram [-Design] <Object> [-Path] <string> [[-Format] <string[]>]
 [[-Layer] <string[]>] [[-GuardrailPath] <string>] [[-Accept] <string[]>]
 [[-PSRuleBaseline] <string>] [-WhatIf] [-Confirm]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Writes \<name\>.mmd, \<name\>.md (renders in Azure DevOps wikis, GitHub
and VS Code) and \<name\>.drawio into -Path. Green, amber and red show
each component's worst open finding; the layers add WAF badges,
policy, guardrail zones, the PSRule gate and Advisor. Offline.

The .drawio has five pages: Cover, Architecture (Azure icons in
landing zone, region, virtual network and data boxes, each layer
on a draw.io layer), Policy and compliance (inherited assignments
and the Azure Policy and PSRule rule for each component), Findings,
and Legend.

## EXAMPLES

### Example 1

```powershell
New-AACArchitectureDiagram -Design $design -Path .\diagrams
```

All three files, every layer.

## PARAMETERS

### -Accept

Accepted risks, drawn as resolved.

```yaml
Type: System.String[]
DefaultValue: '@()'
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

### -Confirm



```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases:
- cf
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

### -Format

Mermaid, Markdown, DrawIo (all by default).

```yaml
Type: System.String[]
DefaultValue: "@('Mermaid', 'Markdown', 'DrawIo')"
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

### -GuardrailPath

Your guardrails, so their findings are drawn too.

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

### -Layer

Waf, Policy, Guardrail, PSRule, Recommendations (all by default).

```yaml
Type: System.String[]
DefaultValue: "@('Waf', 'Policy', 'Guardrail', 'PSRule', 'Recommendations')"
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

### -PSRuleBaseline

The PSRule baseline shown on the gate (Azure.Default).

```yaml
Type: System.String
DefaultValue: "'Azure.Default'"
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

### -WhatIf



```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases:
- wi
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

### System.IO.FileInfo

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/New-AACArchitectureDiagram.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
