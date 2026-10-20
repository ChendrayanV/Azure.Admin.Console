---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACGovernanceAssessment.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Invoke-AACGovernanceAssessment
---

# Invoke-AACGovernanceAssessment

## SYNOPSIS

Assesses governance across the tenant in one run - the management group hierarchy, access, workload identities, policy remediation, Azure limits, tenant settings, tags, locks and recent changes - as a tabbed workbook, and as a Markdown page for a wiki.

## SYNTAX

### __AllParameterSets

```
Invoke-AACGovernanceAssessment [[-SubscriptionId] <string[]>] [[-ManagementGroupId] <string[]>]
 [[-Area] <string[]>] [[-Days] <int>] [[-RequiredTag] <string[]>] [[-CsvPath] <string>]
 [[-HtmlPath] <string>] [[-PdfPath] <string>] [[-MarkdownPath] <string>]
 [[-MarkdownFlavor] <string>] [[-Title] <string>] [-SkipEntra] [-SkipPim] [-PassThru] [-NoDisplay]
 [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Runs, read-only, the governance commands and puts their results
together (in the spirit of the Azure Governance Visualizer):

```text
  Hierarchy    Show-AACManagementGroupMap's model: each management
               group, its subscriptions, policy and role assignments
  Access       Get-AACRoleAssignment: every role assignment, and the
               custom roles
  Identities   Get-AACServicePrincipalInsight
  Policy       Get-AACPolicyRemediation
  Limits       Test-AACAzureLimit
  Settings     Get-AACGovernanceSetting
  Tags         Get-AACTagUsage
  Locks        Get-AACResourceLock
  Changes      Get-AACGovernanceChange (the last -Days)
```

-Area runs only some. An area that fails is reported and the others
still run.

At the prompt: the totals and the findings that matter most (High
and Medium, every area). -HtmlPath writes the workbook - Summary,
Findings and a tab per area, the hierarchy as a tree; -PdfPath the
same as a PDF; -CsvPath the findings; -MarkdownPath one Markdown
page with the hierarchy as a Mermaid diagram and a table per area -
for a GitHub or Azure DevOps wiki (-MarkdownFlavor), refreshed from a
pipeline. -PassThru returns everything (AAC.GovernanceAssessment).

Needs what the areas need: Reader on the scope (Reader on the tenant
root group for its settings), and in Entra ID Directory.Read.All and
Application.Read.All. -SkipEntra reads Azure only.

## EXAMPLES

### Example 1

```powershell
Invoke-AACGovernanceAssessment -HtmlPath .\Governance.html
```

The whole governance workbook for every subscription the account can see.

### Example 2

```powershell
Invoke-AACGovernanceAssessment -ManagementGroupId 'mg-landingzones' -MarkdownPath .\wiki\Governance.md -MarkdownFlavor AzureDevOps -NoDisplay
```

The landing zones' governance as an Azure DevOps wiki page - from a pipeline.

### Example 3

```powershell
Invoke-AACGovernanceAssessment -Area Access, Limits, Settings -PdfPath .\Governance.pdf
```

Three areas, as a PDF.

## PARAMETERS

### -Area

Only these areas: Hierarchy, Access, Identities, Policy, Limits,
Settings, Tags, Locks, Changes.

```yaml
Type: System.String[]
DefaultValue: "@('Hierarchy', 'Access', 'Identities', 'Policy', 'Limits', 'Settings', 'Tags', 'Locks', 'Changes')"
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

Write the findings to this CSV file.

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

### -Days

How far back the Changes area looks. Default 30.

```yaml
Type: System.Int32
DefaultValue: 30
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

### -HtmlPath

Write the workbook as an interactive HTML report.

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

### -MarkdownFlavor

GitHub (the default: ```mermaid blocks) or AzureDevOps (::: mermaid
blocks).

```yaml
Type: System.String
DefaultValue: "'GitHub'"
SupportsWildcards: false
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

### -MarkdownPath

Write the assessment as a Markdown page.

```yaml
Type: System.String
DefaultValue: None
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

### -NoDisplay

Return the assessment without showing the view.

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

Show the view and also return the assessment.

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

Write the workbook as a PDF report.

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

### -RequiredTag

Tags every resource should carry (the Tags area checks their
coverage).

```yaml
Type: System.String[]
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

### -SkipEntra

Don't read Entra ID (Access, Identities and Changes show principals
by ID; Identities is skipped).

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

### -SkipPim

Don't read PIM in the Access area.

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

Only these subscriptions (and the management groups above them).

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
DefaultValue: "'Azure governance assessment'"
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.GovernanceAssessment, with -PassThru or -NoDisplay

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACGovernanceAssessment.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
