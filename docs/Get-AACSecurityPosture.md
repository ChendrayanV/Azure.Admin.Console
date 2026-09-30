---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACSecurityPosture.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Get-AACSecurityPosture
---

# Get-AACSecurityPosture

## SYNOPSIS

Your security posture in one place - Microsoft Defender for Cloud's secure scores, recommendations by control, active alerts, Defender plans and regulatory compliance, and Azure Policy compliance - flattened to one list of findings, with a Spectre.Console view, objects, and CSV, PDF and interactive HTML reports.

## SYNTAX

### __AllParameterSets

```
Get-AACSecurityPosture [[-SubscriptionId] <string[]>] [[-ResourceGroupName] <string[]>]
 [[-Tag] <hashtable>] [[-Section] <string[]>] [[-Standard] <string[]>] [[-CsvPath] <string>]
 [[-PdfPath] <string>] [[-HtmlPath] <string>] [[-Title] <string>] [-PassThru] [-NoDisplay]
 [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Reads Defender for Cloud with Azure Resource Graph (securityresources;
Reader or Security Reader is enough, no Az modules) - every query at
once. -Section picks what to read (all of them by default):

```text
  Score            each subscription's secure score (Defender's own
                   points, added up across subscriptions as Defender
                   does) and the secure score controls, with the
                   potential increase of fixing each
  Recommendations  every unhealthy recommendation on each resource:
                   severity, the control it belongs to, category,
                   description, remediation steps and its portal page
  Alerts           active and in-progress security alerts: severity,
                   intent, resource, how old, and the alert's page
  Plans            which Defender plans are on or off per subscription
  Compliance       each regulatory standard's passed and failed
                   controls, and for a failed control the resources
                   failing the recommendations behind it
  Policy           Azure Policy: each assignment's compliance rate
                   (compliant / compliant + non-compliant
                   resources), and every non-compliant resource with
                   the policy and its effect
```

-ResourceGroupName and -Tag narrow the recommendations, alerts and
compliance failures to those resources (tag values are matched
exactly, ignoring case); scores, plans and standards are per
subscription. -Standard picks compliance standards by name.

One row per finding (AAC.SecurityFinding), the same in the objects,
CSV, HTML and PDF: Section (Recommendation, Alert, Compliance, Policy
or Plan), Severity (none for Policy), Title, Category, Control, Resource, Type,
ResourceGroup, SubscriptionName, State, Detail, Link (the Azure
portal page), Since and ResourceId - most severe first.

The resource tree with each node's score and findings is
Get-AACInventory's; this command is the posture itself.

What you get depends on where the command runs:

```text
  at the prompt    tiles, the subscriptions (score, findings, alerts,
                   plans), the recommendations grouped by
                   recommendation with every resource, the alerts,
                   compliance by standard with the failed controls,
                   and the plans that are off - a page at a time
  piped onward     the findings, with no view
  -PassThru        the view and the findings
  -NoDisplay       the findings only
```

-CsvPath writes the findings. -HtmlPath writes an interactive report:
tiles and charts that filter the tables - findings, subscriptions,
secure score controls, compliance standards and controls, Defender
plans - each searchable, with portal links and a CSV download.
-PdfPath writes the same as a PDF.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Get-AACSecurityPosture
```

Every subscription's secure score, recommendations, alerts, plans and compliance.

### Example 2

```powershell
Get-AACSecurityPosture -Tag @{ Environment = 'Prod' } -HtmlPath .\out\Security.html
```

The production resources' findings as an interactive HTML report.

### Example 3

```powershell
Get-AACSecurityPosture -Section Alerts, Plans
```

Only the active alerts and the Defender plans.

### Example 4

```powershell
Get-AACSecurityPosture -Section Compliance -Standard '*ISO*' -PdfPath .\out\ISO.pdf
ISO 27001 compliance, with the failing resources, as a PDF.
```

### Example 5

```powershell
Get-AACSecurityPosture -Section Policy -NoDisplay | Group-Object Category | Sort-Object Count -Descending
```

The Azure Policy assignments with the most non-compliant resources.

### Example 6

```powershell
Get-AACSecurityPosture -NoDisplay | Where-Object { $_.Section -eq 'Recommendation' -and $_.Severity -eq 'High' } | Group-Object Title
```

The High recommendations, and how many resources each is on.

## PARAMETERS

### -CsvPath

Write every finding to this CSV file.

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

### -HtmlPath

Write an interactive HTML report to this file.

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

### -NoDisplay

Return the findings without showing the view.

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

Show the view and also return the findings.

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

Write a PDF report to this file.

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

### -ResourceGroupName

Only the recommendations, alerts and compliance failures on resources
in these resource groups.

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

### -Section

What to read: Score, Recommendations, Alerts, Plans, Compliance,
Policy. All of them by default.

```yaml
Type: System.String[]
DefaultValue: "@('Score', 'Recommendations', 'Alerts', 'Plans', 'Compliance', 'Policy')"
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

### -Standard

Only these regulatory compliance standards (names or wildcards, e.g.
'Microsoft-cloud-security-benchmark' or '\*ISO\*').

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: true
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

### -Tag

Only the recommendations, alerts and compliance failures on resources
with these tags, e.g. @{ Environment = 'Prod' } (all must match).

```yaml
Type: System.Collections.Hashtable
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

### -Title

The PDF and HTML reports' title.

```yaml
Type: System.String
DefaultValue: "'Security posture'"
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.SecurityFinding (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACSecurityPosture.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
