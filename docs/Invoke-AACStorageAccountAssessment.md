---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACStorageAccountAssessment.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Invoke-AACStorageAccountAssessment
---

# Invoke-AACStorageAccountAssessment

## SYNOPSIS

Assesses storage accounts across subscriptions - what Azure Monitor's Storage accounts workbook shows (transactions, latency, errors by response type, capacity by service) plus availability, throttling, security posture, data protection and cost - as a heat map, findings, a Spectre.Console view, objects, and CSV, PDF and interactive HTML reports.

## SYNTAX

### __AllParameterSets

```
Invoke-AACStorageAccountAssessment [[-SubscriptionId] <string[]>] [[-ManagementGroupId] <string[]>]
 [[-ResourceGroupName] <string[]>] [[-Name] <string[]>] [[-TimeRange] <string>] [[-View] <string>]
 [[-ThrottleLimit] <int>] [[-CsvPath] <string>] [[-HtmlPath] <string>] [[-PdfPath] <string>]
 [[-Title] <string>] [-PassThru] [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Read-only (Reader is enough):

```text
  Resource Graph   the accounts, the Defender for Storage plan and its
                   alerts
  metrics          per account over -TimeRange - the workbook's
                   Overview tab: Transactions, SuccessE2ELatency,
                   SuccessServerLatency, Transactions by ResponseType,
                   plus Availability, Ingress and Egress
  capacity         the workbook's Capacity tab, the latest value:
                   UsedCapacity, BlobCapacity (with BlobCount and
                   ContainerCount), FileCapacity (and FileShareCount),
                   QueueCapacity and TableCapacity - capacity is
                   reported hourly to daily, so it is always read over
                   at least the last two days
  settings         blob and container soft delete, versioning, change
                   feed, point-in-time restore, file share soft
                   delete, lifecycle rules and where the blob logs go
```

Response types are grouped: Success, Throttling (ClientThrottling\*,
ServerBusy\*), Server (ServerTimeout, ServerOther), Authorization
(Authorization, Authentication), Network (Network, ClientTimeout) and
Client (ClientOther - mostly 404 and 409, often normal: they don't
count as errors).

Findings (High, Medium, Low):

```text
  health      availability under 99.9%, throttling, server errors,
              authorization failures, network errors, slow server
              responses, time lost between client and service
  security    HTTP allowed, TLS below 1.2, anonymous blob access, open
              to every network, shared key access, keys not rotated
              in 90 days, no key or SAS expiration policy, cross-
              tenant replication, no blob logs, Defender off or
              alerting
  protection  LRS only, blob, container and file share soft delete
              off (or under 7 days), versioning off
  cost        general-purpose v1 or legacy Blob storage accounts, no
              lifecycle rules, idle accounts, hot tier with little
              activity
```

The heat map scores each account 0-100 for availability, errors,
throttling, latency, security, protection and cost - the 40 worst at
the prompt and in the reports; clicking a cell in the HTML lists its
findings. The reports' tabs follow the workbook - Overview and
Capacity - then Security & protection and Findings.

-View sets what is returned (piped onward, -PassThru, -NoDisplay) and
written to -CsvPath: Account (default) or Finding.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Invoke-AACStorageAccountAssessment
```

Every storage account's health, capacity, posture and findings over the last day.

### Example 2

```powershell
Invoke-AACStorageAccountAssessment -ResourceGroupName 'rg-data' -TimeRange 7d -HtmlPath .\out\Storage.html -PdfPath .\out\Storage.pdf
A week of a workload's storage accounts, as reports.
```

### Example 3

```powershell
Invoke-AACStorageAccountAssessment -View Finding -NoDisplay | Where-Object Signal -EQ 'Security'
```

The security findings, to fix.

### Example 4

```powershell
Invoke-AACStorageAccountAssessment -NoDisplay | Sort-Object -Property UsedGB -Descending | Select-Object -First 10 -Property Account, UsedGB, BlobGB, FileGB, AccessTier, LifecycleRules
```

The ten biggest accounts, and whether lifecycle rules keep their cost down.

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
  Position: 7
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
  Position: 8
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

Only accounts with these names; wildcards work.

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
  Position: 9
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
  Position: 6
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -TimeRange

How far back the metrics go: 1h, 4h (the workbook's default), 12h, 1d
(default), 3d, 7d, 14d or 30d.

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
DefaultValue: "'Storage account assessment'"
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

### -View

Account or Finding: what is returned and written to -CsvPath.

```yaml
Type: System.String
DefaultValue: "'Account'"
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.StorageAccountAssessment or AAC.StorageAccountFinding, by -View (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACStorageAccountAssessment.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
