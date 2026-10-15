---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACWafCheck.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Get-AACWafCheck
---

# Get-AACWafCheck

## SYNOPSIS

Lists the checks Invoke-AACWafAssessment runs - by pillar and design principle, with the resource type each tests, its severity, what to do and where to read more - so you can review the catalogue or pick checks for -ExcludeCheck and Test-AACGoLiveReadiness -RequiredCheck.

## SYNTAX

### __AllParameterSets

```
Get-AACWafCheck [[-Pillar] <string[]>] [[-Id] <string[]>] [[-Severity] <string[]>] [-Principle]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Nothing in Azure is read. One AAC.WafCatalogCheck per check:

```text
  catalogue checks   RE-, SE-, CO-, OE-, PE-: tested on each resource
                     of their type (or each subscription or resource
                     group) against the shared Resource Graph read
  Advisor            AD-HA, AD-SEC, AD-COST, AD-OPS, AD-PERF: a
                     resource with an open recommendation fails
  Defender           DF-HIGH: a resource with an open high-severity
                     recommendation fails
  attestation        AT-<pillar>-<n>: the questionnaire's answer for
                     the principle (-AttestationPath)
```

-Principle shows each principle with how it's covered.

## EXAMPLES

### Example 1

```powershell
Get-AACWafCheck -Pillar Reliability
```

The reliability checks.

### Example 2

```powershell
Get-AACWafCheck -Principle | Where-Object Checks -EQ 0
```

The principles only the questionnaire covers.

## PARAMETERS

### -Id

Only these check IDs; wildcards work.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: true
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

### -Pillar

Only these pillars.

```yaml
Type: System.String[]
DefaultValue: "@('Reliability', 'Security', 'Cost Optimization', 'Operational Excellence', 'Performance Efficiency')"
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

### -Principle

List the design principles instead, with how many checks cover each.

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

### -Severity

Only these severities.

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.WafCatalogCheck, or AAC.WafPrinciple with -Principle

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACWafCheck.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
