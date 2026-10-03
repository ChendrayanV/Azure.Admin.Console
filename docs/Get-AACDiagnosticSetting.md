---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACDiagnosticSetting.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Get-AACDiagnosticSetting
---

# Get-AACDiagnosticSetting

## SYNOPSIS

Lists every resource's diagnostic settings, flattened, and finds the resources whose logs don't reach a Log Analytics workspace - and the settings that are misconfigured - with a Spectre.Console view, objects, and CSV, PDF and interactive HTML reports.

## SYNTAX

### __AllParameterSets

```
Get-AACDiagnosticSetting [[-SubscriptionId] <string[]>] [[-ManagementGroupId] <string[]>]
 [[-ResourceGroupName] <string[]>] [[-ResourceType] <string[]>] [[-ExpectedWorkspace] <string[]>]
 [[-ThrottleLimit] <int>] [[-CsvPath] <string>] [[-PdfPath] <string>] [[-HtmlPath] <string>]
 [[-Title] <string>] [-NotExportedOnly] [-IncludeUnsupported] [-ExpandSetting] [-PassThru]
 [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Read-only, in three steps:

```text
  1. Every resource in scope, with a KQL query (Azure Resource Graph),
     and the subscriptions (for their activity log). A storage
     account's logs are set on its blob, file, queue and table
     services, which Resource Graph doesn't list: they are added.
  2. Which of them have resource logs: Azure's own list of a
     resource's diagnostic categories
     ({id}/providers/Microsoft.Insights/diagnosticSettingsCategories),
     read once per resource type and kind - the log categories, their
     category groups (allLogs, audit), and the metrics.
  3. The diagnostic settings of every resource that has logs
     ({id}/providers/Microsoft.Insights/diagnosticSettings,
     2021-05-01-preview), -ThrottleLimit at a time.
```

Each resource with logs gets a Status (AAC.DiagnosticCoverage):

```text
  Exported           every log category reaches a Log Analytics
                     workspace
  Partial            some categories do, others don't
  Not to workspace   diagnostic settings exist, but none sends logs
                     to a workspace that exists (storage, Event Hubs
                     or a partner only)
  No setting         no diagnostic setting at all
  Unknown            couldn't be read (the reason is in Error)
```

A category reaches the workspace when a setting enables it by name
or through a category group (allLogs, audit) it belongs to. Types
with no log categories are left out (-IncludeUnsupported lists them
as No logs).

Misconfigurations found (AAC.DiagnosticFinding, by severity):

```text
  High     no diagnostic setting; activity log not exported; settings
           with no workspace destination; a workspace that doesn't
           exist (deleted, or out of your sight)
  Medium   log categories missing; a setting with nothing enabled; the
           same category sent to a workspace twice (billed twice); a
           workspace other than -ExpectedWorkspace
  Low      workspace in another region; the retired retention policy
           still set on a setting
```

-ExpandSetting returns one row per diagnostic setting instead
(AAC.DiagnosticSettingDetail): destinations, workspace (found or
not, region), destination table (resource-specific or
AzureDiagnostics), storage account, event hub, partner, log
categories and groups enabled and disabled, metrics, retention.

What you get depends on where the command runs:

```text
  at the prompt    tiles, coverage by resource type, the workspaces
                   used, the findings, and the resources whose logs
                   don't reach a workspace - a page at a time
  piped onward     the rows, with no view
  -PassThru        the view and the rows
  -NoDisplay       the rows only
```

-CsvPath writes the rows returned; -HtmlPath an interactive report
(coverage, findings, every setting, by type, workspaces); -PdfPath a
PDF.

A large estate means many calls: one per resource with logs. Narrow
it with -SubscriptionId, -ManagementGroupId, -ResourceGroupName or
-ResourceType.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Get-AACDiagnosticSetting -SubscriptionId 00000000-0000-0000-0000-000000000000
```

Every resource with logs in one subscription, and whether they reach Log Analytics.

### Example 2

```powershell
Get-AACDiagnosticSetting -ManagementGroupId 'mg-landingzones' -ExpectedWorkspace 'law-central' -HtmlPath .\out\Diagnostics.html -PdfPath .\out\Diagnostics.pdf
A management group against the central workspace, as HTML and PDF reports.
```

### Example 3

```powershell
Get-AACDiagnosticSetting -NotExportedOnly -NoDisplay | Group-Object ResourceType | Sort-Object Count -Descending
```

The resource types with the most resources whose logs don't reach a workspace.

### Example 4

```powershell
Get-AACDiagnosticSetting -ResourceType 'microsoft.keyvault/vaults' -ExpandSetting -CsvPath .\out\KeyVaultSettings.csv
```

Every Key Vault diagnostic setting, one row each, as CSV.

## PARAMETERS

### -CsvPath

Write the rows to this CSV file.

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

### -ExpandSetting

Return (and write to -CsvPath) one row per diagnostic setting.

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

### -ExpectedWorkspace

The workspace (or workspaces) logs should go to - names or resource
IDs. A setting sending to any other is a finding.

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

### -HtmlPath

Write an interactive HTML report to this file.

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

### -IncludeUnsupported

Also list the resources whose type has no log categories (No logs).

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

### -NoDisplay

Return the rows without showing the view.

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

### -NotExportedOnly

Only the resources whose logs don't all reach a workspace: No
setting, Not to workspace and Partial.

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

Show the view and also return the rows.

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
  Position: 7
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ResourceGroupName

Only these resource groups (subscriptions' activity logs are then
left out).

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

### -ResourceType

Only these resource types, wildcards allowed: 'microsoft.keyvault/vaults',
'microsoft.web/\*'. 'microsoft.resources/subscriptions' is the
activity log.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: true
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

### -ThrottleLimit

How many Azure Resource Manager calls run at once: 1 to 32, 12 by
default.

```yaml
Type: System.Int32
DefaultValue: 12
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

### -Title

The PDF and HTML reports' title.

```yaml
Type: System.String
DefaultValue: "'Diagnostic settings'"
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.DiagnosticCoverage, or AAC.DiagnosticSettingDetail with -ExpandSetting (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACDiagnosticSetting.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
