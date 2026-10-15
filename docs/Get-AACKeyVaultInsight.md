---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACKeyVaultInsight.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Get-AACKeyVaultInsight
---

# Get-AACKeyVaultInsight

## SYNOPSIS

Key Vault insights across subscriptions - what Azure Monitor's Key Vault workbook shows (availability, transactions, latency, failures by status, operations from the audit logs) plus saturation, posture, callers that are denied or throttled, and secrets, keys and certificates near expiry - as a heat map, findings, a Spectre.Console view, objects, and CSV, PDF and interactive HTML reports.

## SYNTAX

### __AllParameterSets

```
Get-AACKeyVaultInsight [[-SubscriptionId] <string[]>] [[-ManagementGroupId] <string[]>]
 [[-ResourceGroupName] <string[]>] [[-Name] <string[]>] [[-TimeRange] <string>]
 [[-ExpiryDays] <int>] [[-View] <string>] [[-ThrottleLimit] <int>] [[-CsvPath] <string>]
 [[-HtmlPath] <string>] [[-PdfPath] <string>] [[-Title] <string>] [-IncludeOperations]
 [-IncludeObjects] [-PassThru] [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Read-only. Always (Reader is enough):

```text
  Resource Graph   the vaults, their private endpoints, the Defender
                   for Key Vault plan and its alerts
  metrics          per vault over -TimeRange: Availability,
                   ServiceApiHit (transactions, and by request type),
                   ServiceApiLatency, ServiceApiResult by status code
                   (2xx, 401, 403, 429, other) and SaturationShoebox
                   (Overall Vault Saturation)
  settings         whether AuditEvent reaches a Log Analytics
                   workspace, and in which table
```

-IncludeOperations (Log Analytics Reader): the audit logs - both
AzureDiagnostics and AZKVAuditLogs - by vault, operation and caller,
with failures, denials (401/403), throttling (429) and p99 duration;
the SDK's normal Authentication challenge (401) is left out, as in the
workbook.
-IncludeObjects (Key Vault Reader, or a List access policy): secrets,
keys and certificates - metadata only, never a value - with expired,
expiring within -ExpiryDays and no-expiry. A vault whose firewall
blocks this machine, or that denies the account, is reported as such.

Findings (High, Medium, Low): soft delete or purge protection off,
open to every network, access policies instead of RBAC, no audit logs,
Defender off or alerting, availability under 99.9%, throttling,
saturation at 50%+ (High at 75%), 403s, other failures, idle vaults,
callers denied 10+ times, expired, expiring and never-expiring objects.

The heat map scores each vault 0-100 for availability, failures,
throttling, saturation, posture and objects - the 40 worst at the
prompt and in the reports; clicking a cell in the HTML lists its
findings.

-View sets what is returned (piped onward, -PassThru, -NoDisplay) and
written to -CsvPath: Vault (default), Operation, Object or Finding.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Get-AACKeyVaultInsight
```

Every vault's health, posture and findings over the last day.

### Example 2

```powershell
Get-AACKeyVaultInsight -ResourceGroupName 'rg-app-prod' -TimeRange 7d -IncludeOperations -IncludeObjects -HtmlPath .\out\KeyVault.html -PdfPath .\out\KeyVault.pdf
A week of a workload's vaults: operations, callers, objects near expiry, as reports.
```

### Example 3

```powershell
Get-AACKeyVaultInsight -IncludeObjects -View Object -NoDisplay | Where-Object Status -In 'Expired', 'Expiring'
```

Secrets, keys and certificates to rotate.

### Example 4

```powershell
Get-AACKeyVaultInsight -IncludeOperations -View Operation -NoDisplay | Where-Object AuthDenied | Sort-Object AuthDenied -Descending | Select-Object -First 10
```

The callers denied most often.

## PARAMETERS

### -CsvPath

Write the -View rows to this CSV file.

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

### -ExpiryDays

An object expiring within this many days is Expiring (30 by default).

```yaml
Type: System.Int32
DefaultValue: 30
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

Write an interactive HTML report.

```yaml
Type: System.String
DefaultValue: None
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

### -IncludeObjects

Read secrets, keys and certificates (metadata only) for their expiry.

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

### -IncludeOperations

Read the audit logs: operations and callers.

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

### -Name

Only vaults with these names; wildcards work.

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

Write a PDF report.

```yaml
Type: System.String
DefaultValue: None
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

### -ResourceGroupName

Only these resource groups.

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

How many requests run at once (1 to 32; 12 by default).

```yaml
Type: System.Int32
DefaultValue: 12
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

### -TimeRange

How far back the metrics and logs go: 1h, 4h, 12h, 1d (default), 3d,
7d, 14d or 30d.

```yaml
Type: System.String
DefaultValue: "'1d'"
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

### -Title

The reports' title.

```yaml
Type: System.String
DefaultValue: "'Key Vault insights'"
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 11
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -View

Vault, Operation, Object or Finding: what is returned and written to
-CsvPath.

```yaml
Type: System.String
DefaultValue: "'Vault'"
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.KeyVaultInsight, AAC.KeyVaultOperation, AAC.KeyVaultObject or AAC.KeyVaultFinding, by -View (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACKeyVaultInsight.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
