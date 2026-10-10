---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACFailoverReadiness.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Get-AACFailoverReadiness
---

# Get-AACFailoverReadiness

## SYNOPSIS

How ready you are to recover: each workload's backups (fresh, succeeding, ever restored) and Site Recovery replication (healthy, within its RPO, failover tested and possible), the vaults' settings, and the recovery plans and their runbooks - with a recovery confidence score and RPO on track or at risk.

## SYNTAX

### __AllParameterSets

```
Get-AACFailoverReadiness [[-SubscriptionId] <string[]>] [[-ManagementGroupId] <string[]>]
 [[-ResourceGroupName] <string[]>] [[-RpoMinutes] <int>] [[-BackupRpoHours] <int>]
 [[-TestFailoverDays] <int>] [[-RestoreTestDays] <int>] [[-CsvPath] <string>] [[-HtmlPath] <string>]
 [[-PdfPath] <string>] [[-Title] <string>] [-PassThru] [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Reads, read-only:

```text
  Resource Graph     the VMs, the Recovery Services vaults (redundancy,
                     cross-region restore, soft delete, immutability),
                     every backed-up item (last backup, its status,
                     protection state) and the restore jobs
  Resource Manager   each vault's Site Recovery replicated items
                     (replication health, RPO, last test failover,
                     what operations are allowed now) and recovery
                     plans; each runbook a plan runs (does it exist,
                     is it published?)
```

Each workload (AAC.FailoverReadiness) - every VM, and every other
backed-up item - gets its protection (Backup, Site Recovery, both or
none), its findings, a confidence score (0-100), and its RPO against
the target: -RpoMinutes for replication, -BackupRpoHours for backup.
The vaults and recovery plans add their own findings.

Nothing is failed over, test or otherwise: a recovery plan's
runbooks are checked to exist and be published - the part that
breaks silently - and the last test failover's date is reported. The
measured RTO comes from a test failover; run one with the plan.

## EXAMPLES

### Example 1

```powershell
Get-AACFailoverReadiness
```

Every workload's recovery readiness, least ready first.

### Example 2

```powershell
Get-AACFailoverReadiness -ResourceGroupName 'rg-erp-prod' -RpoMinutes 5 -BackupRpoHours 12 -HtmlPath .\out\DR.html
```

The ERP workloads against tighter targets, as a report.

### Example 3

```powershell
Get-AACFailoverReadiness -NoDisplay | Where-Object Rpo -EQ 'At risk'
```

The workloads that would lose more data than the target allows.

## PARAMETERS

### -BackupRpoHours

The backup RPO target: the oldest a last backup may be, in hours (24
by default).

```yaml
Type: System.Int32
DefaultValue: 24
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

### -CsvPath

Write the workloads to this CSV file.

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

Return the workloads without showing the view.

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

Show the view and also return the workloads.

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

Only the VMs and vaults in these resource groups.

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

### -RestoreTestDays

No successful restore in this many days is a finding (180 by
default).

```yaml
Type: System.Int32
DefaultValue: 180
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

### -RpoMinutes

The replication RPO target, in minutes (15 by default).

```yaml
Type: System.Int32
DefaultValue: 15
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

### -TestFailoverDays

A test failover older than this (or none) is a finding (180 by
default).

```yaml
Type: System.Int32
DefaultValue: 180
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

The reports' title.

```yaml
Type: System.String
DefaultValue: "'Failover readiness'"
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

### AAC.FailoverReadiness

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACFailoverReadiness.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
