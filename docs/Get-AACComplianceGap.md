---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACComplianceGap.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Get-AACComplianceGap
---

# Get-AACComplianceGap

## SYNOPSIS

Maps your Azure estate to compliance frameworks - CIS, PCI-DSS, HIPAA, SOC 2, GDPR, ISO 27001, NIST and the Microsoft cloud security benchmark - and lists the gaps by priority and effort, as a remediation roadmap, with what changed since the last run.

## SYNTAX

### __AllParameterSets

```
Get-AACComplianceGap [[-SubscriptionId] <string[]>] [[-ManagementGroupId] <string[]>]
 [[-Framework] <string[]>] [[-BaselinePath] <string>] [[-CsvPath] <string>] [[-HtmlPath] <string>]
 [[-PdfPath] <string>] [[-Title] <string>] [-SkipUnscanned] [-PassThru] [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Reads, from Azure Resource Graph:

```text
  Defender for Cloud  each regulatory compliance standard's controls
                      and the failing assessments under them
  Azure Policy        the regulatory compliance initiatives assigned,
                      control by control (their policy definition
                      groups), and the non-compliant resources
  Coverage            the resource types no policy evaluates
```

Gaps (AAC.ComplianceGap): failing controls (High with 10 or more
failing resources, else Medium), controls waiting for a manual
attestation (Low), and frameworks asked for with -Framework that
nothing assesses (High). Each has an effort - Low when remediation
tasks fix it - and a roadmap phase: Quick win, Plan or Backlog.

Progress: -BaselinePath reads a previous run's CSV (-CsvPath) and
marks each gap New, Open or Closed - so a run a month later shows what
was fixed.

The report: a summary per framework (controls passed, failed,
manual; compliance %), the gaps, the roadmap and the unscanned
resource types. Read-only; Reader (and Security Reader for
Defender) is enough. Certifications themselves (audit reports,
expiry dates) aren't in Azure: see the Service Trust Portal.

## EXAMPLES

### Example 1

```powershell
Get-AACComplianceGap -Framework PCI-DSS, ISO27001 -CsvPath .\out\gaps-2026-10.csv
```

The PCI-DSS and ISO 27001 gaps, saved as next month's baseline.

### Example 2

```powershell
Get-AACComplianceGap -BaselinePath .\out\gaps-2026-10.csv -HtmlPath .\out\Compliance.html
```

What's new, still open and closed since last month, as a report.

### Example 3

```powershell
Get-AACComplianceGap -NoDisplay | Where-Object Phase -EQ 'Quick win'
```

The gaps to close first.

## PARAMETERS

### -BaselinePath

A previous run's CSV (-CsvPath): each gap is then New, Open or
Closed.

```yaml
Type: System.String
DefaultValue: None
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

### -CsvPath

Write the gaps to this CSV file - next time's -BaselinePath.

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

### -Framework

Only these frameworks; a framework asked for that nothing assesses
is a gap. CIS, PCI-DSS, HIPAA, SOC2, GDPR, ISO27001, NIST or MCSB.

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

### -HtmlPath

Write an interactive HTML report.

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

Return the gaps without showing the view.

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

Show the view and also return the gaps.

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
  Position: 6
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SkipUnscanned

Don't look for resources no policy evaluates (one heavier query).

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
DefaultValue: "'Compliance gaps'"
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.ComplianceGap

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACComplianceGap.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
