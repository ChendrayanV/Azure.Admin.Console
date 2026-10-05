---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACPolicyAssessment.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Invoke-AACPolicyAssessment
---

# Invoke-AACPolicyAssessment

## SYNOPSIS

Assesses Azure Policy across a tenant, management group or set of subscriptions - what is assigned, how compliant it is (overall, by subscription, assignment, policy and category), the exemptions and the managed identities' roles - and what to improve, with a Spectre.Console view, objects, and CSV, PDF and interactive HTML reports. In the spirit of AzPolicyLens (github.com/Azure/AzPolicyLens).

## SYNTAX

### Tenant (Default)

```
Invoke-AACPolicyAssessment [-Audience <string>] [-ComplianceWarningPercent <int>]
 [-ExemptionWarningDays <int>] [-CsvPath <string>] [-PdfPath <string>] [-HtmlPath <string>]
 [-Title <string>] [-PassThru] [-NoDisplay] [-NoPaging]
```

### ManagementGroup

```
Invoke-AACPolicyAssessment -ManagementGroupId <string> [-Audience <string>]
 [-ComplianceWarningPercent <int>] [-ExemptionWarningDays <int>] [-CsvPath <string>]
 [-PdfPath <string>] [-HtmlPath <string>] [-Title <string>] [-PassThru] [-NoDisplay] [-NoPaging]
```

### Subscription

```
Invoke-AACPolicyAssessment -SubscriptionId <string[]> [-Audience <string>]
 [-ComplianceWarningPercent <int>] [-ExemptionWarningDays <int>] [-CsvPath <string>]
 [-PdfPath <string>] [-HtmlPath <string>] [-Title <string>] [-PassThru] [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Read-only (Reader is enough), Azure Resource Graph only - no Az
modules. Every assignment, exemption, custom definition and
initiative, and the management group hierarchy are read tenant-wide,
so what a management group assigns to a subscription is there; the
built-in definitions that are assigned are read by ID; compliance is
read in the subscriptions in scope.

Compliance is counted as AzPolicyLens counts it: each resource once,
at its worst state (NonCompliant, then Compliant, Conflict, Exempt),
and compliance = (compliant + exempt) / all - overall, by
subscription, by management group, by assignment (and subscription),
by policy and by category. Under -ComplianceWarningPercent (80) is
Warning, under half of it Poor.

The findings (each with its severity, what was found and what to do):

```text
  Assignments  definitions assigned directly (not in an initiative),
               DoNotEnforce, a definition that can't be found,
               below the compliance threshold, deprecated or preview
               policies assigned, excluded scopes that don't exist,
               the same definition assigned twice on a scope path,
               Deny with no non-compliance message
  Identity     DeployIfNotExists and Modify assignments with no
               managed identity, or one missing the roles their
               policies list
  Exemptions   expired, expiring within -ExemptionWarningDays (30),
               never expiring, for an assignment that is gone
  Definitions  unassigned custom definitions and initiatives, unused
               policy definition groups, the same control under
               different group names, no category in the metadata
  Compliance   subscriptions below the threshold
```

-Audience Platform (the default; AzPolicyLens's detailed wiki) is for
the team that runs Azure Policy: everything, with hidden- metadata and
tags. Application (its basic wiki) is for an application team: their
assignments, compliance and exemptions, without the unassigned
definitions, metadata hygiene or hidden- metadata.

What you get depends on where the command runs:

```text
  at the prompt    tiles, compliance by subscription and category,
                   the assignments least compliant first, the
                   exemptions that need attention and the High and
                   Medium findings, a page at a time
  piped onward     the AAC.PolicyAssignmentReport objects, each with
                   its Compliance, PolicyStates and Findings
  -PassThru        the view and the objects
  -NoDisplay       the objects only
```

-CsvPath (a folder) writes a CSV per table. -HtmlPath writes an
interactive report - the management group hierarchy as a tree with
each level's compliance, then every table; -PdfPath a PDF.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Invoke-AACPolicyAssessment
```

Azure Policy across every subscription and management group the account can see.

### Example 2

```powershell
Invoke-AACPolicyAssessment -ManagementGroupId 'mg-landingzones' -HtmlPath .\out\Policy.html -PdfPath .\out\Policy.pdf -CsvPath .\out\policy
A landing zone's policy, with every report.
```

### Example 3

```powershell
Invoke-AACPolicyAssessment -SubscriptionId 00000000-0000-0000-0000-000000000000 -Audience Application -HtmlPath .\Policy.html
```

An application team's report: the policies on their subscription, how compliant it is, and their exemptions.

### Example 4

```powershell
Invoke-AACPolicyAssessment -NoDisplay | Where-Object { $_.Rating -ne 'Good' } | Select-Object Assignment, Scope, CompliancePercent, NonCompliant
```

The assignments under the compliance threshold.

## PARAMETERS

### -Audience

Platform (the default): everything. Application: what an application
team needs - no unassigned definitions, metadata hygiene or hidden-
metadata.

```yaml
Type: System.String
DefaultValue: "'Platform'"
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

### -ComplianceWarningPercent

Compliance under this percentage (80 by default) is a Warning, under
half of it Poor - and an assignment or subscription under it is a
finding.

```yaml
Type: System.Int32
DefaultValue: 80
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

### -CsvPath

A folder to write a CSV per table to.

```yaml
Type: System.String
DefaultValue: None
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

### -ExemptionWarningDays

Exemptions expiring within this many days (30 by default) are
flagged.

```yaml
Type: System.Int32
DefaultValue: 30
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

### -HtmlPath

Write an interactive HTML report to this file.

```yaml
Type: System.String
DefaultValue: None
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

### -ManagementGroupId

Assess this management group and everything under it.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: ManagementGroup
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -NoDisplay

Return the objects without showing the view.

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

Show the view and also return the objects.

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

Assess these subscriptions, and every assignment that reaches them -
from their management groups too.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Subscription
  Position: Named
  IsRequired: true
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
DefaultValue: "'Azure Policy assessment'"
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.PolicyAssignmentReport (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACPolicyAssessment.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
