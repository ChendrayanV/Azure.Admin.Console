---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Export-AACDiagnosticBundle.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Export-AACDiagnosticBundle
---

# Export-AACDiagnosticBundle

## SYNOPSIS

Packages everything needed to troubleshoot Azure resources into one zip for a support case or a colleague - each resource's configuration, health and its history, Activity Log, diagnostic settings, locks, recommendations, compliance, alerts, recent changes and role assignments - with secrets redacted and a summary on top.

## SYNTAX

### Resource (Default)

```
Export-AACDiagnosticBundle -ResourceId <string[]> -Path <string> [-Hours <int>]
 [-MaxResources <int>] [-Force] [-PassThru] [-NoDisplay] [-NoPaging] [-WhatIf] [-Confirm]
```

### ResourceGroup

```
Export-AACDiagnosticBundle -ResourceGroupName <string> -Path <string> [-SubscriptionId <string>]
 [-Hours <int>] [-MaxResources <int>] [-Force] [-PassThru] [-NoDisplay] [-NoPaging] [-WhatIf]
 [-Confirm]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

For each resource (-ResourceId, piped in, or every resource of
-ResourceGroupName, up to -MaxResources):

```text
  config.json               the resource as Resource Graph has it
  health.json               Resource Health now, its history and the
                            latest health event
  activity-log.json         the Activity Log for the resource, the
                            last -Hours
  diagnostic-settings.json  where its logs and metrics go
  locks.json                management locks on it
  advisor.json              Azure Advisor recommendations
  defender.json             unhealthy Defender for Cloud assessments
  policy.json               non-compliant Azure Policy states
  alerts.json               alerts fired in the last -Hours
  changes.json              property changes (Resource Graph keeps
                            14 days)
  role-assignments.json     role assignments scoped to it
```

and at the top of the zip: README.md (what is where, when, the
window), summary.json (the manifest: resources, files, what couldn't
be read) and summary.html (the summary as an interactive report).

Secrets are redacted before anything is written: values whose name
says password, secret, token, connection string, SAS, credentials
or an access, account or shared access key - and values that look
like a connection string, a SAS signature, a JWT or a private key.
Read the bundle before you send it anyway: the account and tenant ID
it was made with, names, IPs and tags stay in.

Read-only in Azure; Reader is enough. Writes one zip file (-Force to
overwrite it); -WhatIf shows where.

## EXAMPLES

### Example 1

```powershell
Export-AACDiagnosticBundle -ResourceId $vm.Id -Path .\out\vm-case.zip
```

One VM's configuration, health, activity and more, for a support case.

### Example 2

```powershell
Export-AACDiagnosticBundle -ResourceGroupName rg-app -SubscriptionId $sub -Hours 72 -Path .\out\rg-app.zip
```

Every resource in rg-app with three days of activity.

### Example 3

```powershell
Get-AACResourceHealth -State Unavailable -NoDisplay | Export-AACDiagnosticBundle -Path .\out\down.zip
A bundle of everything that is down right now.
```

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

Overwrite the zip file if it exists.

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

### -Hours

How far back the Activity Log and alerts go. Default 24; up to 720.

```yaml
Type: System.Int32
DefaultValue: 24
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

### -MaxResources

The most resources to bundle. Default 50.

```yaml
Type: System.Int32
DefaultValue: 50
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

### -NoDisplay

Return the bundle without showing the summary.

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

Show the whole summary at once.

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

Show the summary and also return the bundle.

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

The zip file to write.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ResourceGroupName

Bundle every resource in this resource group (up to -MaxResources).

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: ResourceGroup
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ResourceId

The resources to bundle. Takes ResourceId or Id from the pipeline.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
Aliases:
- Id
ParameterSets:
- Name: Resource
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: true
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SubscriptionId

The subscription of -ResourceGroupName (otherwise every subscription
with a resource group of that name).

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: ResourceGroup
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.DiagnosticBundle

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Export-AACDiagnosticBundle.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
