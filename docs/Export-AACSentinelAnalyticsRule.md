---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Export-AACSentinelAnalyticsRule.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Export-AACSentinelAnalyticsRule
---

# Export-AACSentinelAnalyticsRule

## SYNOPSIS

Backs up the analytics rules of a Microsoft Sentinel workspace - and, with -IncludeAutomationRule, its automation rules - as one JSON file per rule: ARM deployment templates ready for source control, Sentinel Repositories or another workspace.

## SYNTAX

### __AllParameterSets

```
Export-AACSentinelAnalyticsRule [-WorkspaceId] <string> [-Path] <string>
 [-SubscriptionId <string[]>] [-ResourceGroupName <string>] [-Name <string[]>] [-Kind <string[]>]
 [-State <string>] [-IncludeAutomationRule] [-Format <string>] [-Force] [-PassThru] [-NoDisplay]
 [-NoPaging] [-WhatIf] [-Confirm]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Reads the rules from Azure Resource Manager - read-only in Azure,
nothing there is changed - and writes a file per rule into -Path
(automation rules into -Path\AutomationRules):

```text
  -Format ArmTemplate   (the default) the template the Sentinel portal
                        exports: deploy it to any workspace with
                        New-AzResourceGroupDeployment, the Azure CLI or
                        Sentinel Repositories, giving the workspace's
                        name as the 'workspace' parameter
  -Format Json          the rule as the API returns it
```

Properties Azure sets itself (last modified, created by) are left out,
and keys are sorted, so exporting an unchanged rule again gives the
same file: commit the folder and the diff shows what changed. A file
name is the rule's display name; two rules with one name get the rule
ID added. Files already there are left alone unless -Force; -WhatIf
shows what would be written.

Needs Microsoft Sentinel Reader on the workspace.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Export-AACSentinelAnalyticsRule -WorkspaceId 'law-contoso-sentinel' -Path .\sentinel\rules
```

Every analytics rule as an ARM template, one file each.

### Example 2

```powershell
Export-AACSentinelAnalyticsRule -WorkspaceId 'law-contoso-sentinel' -Path .\sentinel -IncludeAutomationRule -Force
```

Analytics and automation rules, overwriting the last backup - commit the folder to see what changed.

### Example 3

```powershell
Export-AACSentinelAnalyticsRule -WorkspaceId 'law-contoso-sentinel' -Path .\out\custom -Kind Scheduled, NRT -State Enabled -WhatIf
```

Which files the enabled scheduled and NRT rules would be written to, writing nothing.

### Example 4

```powershell
Export-AACSentinelAnalyticsRule -WorkspaceId 'law-contoso-sentinel' -Path .\out\rules -NoDisplay | ForEach-Object { New-AzResourceGroupDeployment -ResourceGroupName rg-contoso-sec-dr -TemplateFile $_.File -workspace law-contoso-sentinel-dr }
```

Copy every rule to a second workspace (Az.Resources does the deploying).

## PARAMETERS

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

### -Force

Overwrite files that are already there.

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

### -Format

ArmTemplate (deployable; the default) or Json (the rule as read).

```yaml
Type: System.String
DefaultValue: "'ArmTemplate'"
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

### -IncludeAutomationRule

Also export the automation rules, into an AutomationRules folder.

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

### -Kind

Only analytics rules of these kinds (Scheduled, NRT, Fusion,
MicrosoftSecurityIncidentCreation, MLBehaviorAnalytics,
ThreatIntelligence).

```yaml
Type: System.String[]
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

### -Name

Only rules whose display name or rule ID matches; wildcards work.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: true
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

Return what was written without showing the view.

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

Show the view and also return what was written.

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

The folder to write the files into. It is created if missing.

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

### -ResourceGroupName

Narrows a workspace given by name, when the name is in more than one
resource group.

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

### -State

Only Enabled or only Disabled analytics rules.

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

Where to look for a workspace given by ID (GUID) or name. Every
subscription the account can see by default.

```yaml
Type: System.String[]
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

### -WorkspaceId

The workspace: its workspace ID (GUID), resource ID or name.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases:
- Workspace
- WorkspaceName
- ResourceId
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.SentinelRuleExport (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Export-AACSentinelAnalyticsRule.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
