---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Show-AACServiceBusEntity.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Show-AACServiceBusEntity
---

# Show-AACServiceBusEntity

## SYNOPSIS

Shows Service Bus queues and topics as you can see them - live message counts, dead-letters, subscriptions, configuration and, with access to the namespace, their metrics - whether your role is on the namespace or only on the entities.

## SYNTAX

### __AllParameterSets

```
Show-AACServiceBusEntity [-NamespaceId] <string> [[-EntityName] <string[]>] [[-EntityKind] <string>]
 [[-TimeRange] <string>] [[-Sample] <int>] [[-SampleInterval] <timespan>] [[-View] <string>]
 [[-ThrottleLimit] <int>] [[-CsvPath] <string>] [[-HtmlPath] <string>] [[-PdfPath] <string>]
 [[-Title] <string>] [-SkipMetrics] [-PassThru] [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Read-only. Works out what your sign-in can read, entity by entity:

```text
  namespace role   Reader, Monitoring Reader or Data Owner on the
                   namespace: names can use wildcards (or be left out
                   to list every queue and topic), and each entity's
                   Azure Monitor metrics are read over -TimeRange
  entity role      Azure Service Bus Data Sender or Receiver on a
                   queue or topic: exact names only, live state only -
                   Service Bus publishes metrics on the namespace, so
                   an entity role can't read them. -Sample reads the
                   live counts a few times instead, for a short trend.
```

Live state (Resource Manager): active, dead-lettered, scheduled,
transfer and transfer dead-lettered messages, size against the
maximum, status, when last used, each topic subscription's counts,
and every setting (lock duration, max delivery count, TTL, sessions,
duplicate detection, forwarding, partitioning, auto-delete).

Metrics (namespace access): incoming, outgoing, completed and
abandoned messages, requests, server and user errors, throttling,
active, dead-lettered and scheduled messages over time, size, bytes,
send latency - per queue or topic (Azure has none per subscription) -
and a Premium namespace's CPU and memory.

Findings: dead-letters, transfer dead-letters, entities filling up
or not active, throttling, server errors, messages arriving with none
received, a growing backlog, entities unused for 30 days, expired
messages dropped - and entities you have no role on or that don't
exist.

-View sets what is returned (piped onward, -PassThru, -NoDisplay) and
written to -CsvPath: Entity (default), Subscription, Metric, Sample,
Finding or Access.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Show-AACServiceBusEntity -NamespaceId $namespaceId -EntityName 'orders'
```

One queue or topic: its live state, and its metrics if you can read the namespace.

### Example 2

```powershell
Show-AACServiceBusEntity -NamespaceId $namespaceId -EntityName 'orders-*' -TimeRange 7d -HtmlPath .\sb.html
```

Every queue and topic starting orders-, with a week of metrics, as a tabbed report (namespace access).

### Example 3

```powershell
Show-AACServiceBusEntity -NamespaceId $namespaceId -EntityName 'orders' -Sample 10 -SampleInterval 00:00:30
```

With an entity role only: ten reads, 30 seconds apart, show whether the backlog is growing.

### Example 4

```powershell
Show-AACServiceBusEntity -NamespaceId $namespaceId -EntityName 'events' -View Subscription -NoDisplay | Where-Object DeadLettered
A topic's subscriptions with dead-lettered messages.
```

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

### -EntityKind

Queue, Topic or Auto (default): Auto tries a queue, then a topic.

```yaml
Type: System.String
DefaultValue: "'Auto'"
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

### -EntityName

The queues or topics, by exact name. Wildcards - and leaving it out,
to show them all - need read access on the namespace.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: true
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

### -NamespaceId

The namespace's full resource ID:
/subscriptions/\<id\>/resourceGroups/\<group\>/providers/Microsoft.ServiceBus/namespaces/\<name\>.
With only an entity role you can't look it up, so ask the platform
team for it.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
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

### -Sample

Read the live counts this many times (2 to 120), -SampleInterval
apart, for a backlog trend without metrics.

```yaml
Type: System.Int32
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

### -SampleInterval

The time between samples (30 seconds by default; 5 seconds to 10
minutes).

```yaml
Type: System.TimeSpan
DefaultValue: '[timespan]::FromSeconds(30)'
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

### -SkipMetrics

Don't read metrics.

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

How far back the metrics go: 1h, 4h, 12h, 1d (default), 3d, 7d, 14d
or 30d. Message counts are always as they are now.

```yaml
Type: System.String
DefaultValue: "'1d'"
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

### -Title

The reports' title.

```yaml
Type: System.String
DefaultValue: "'Service Bus entities'"
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

Entity, Subscription, Metric, Sample, Finding or Access: what is
returned and written to -CsvPath.

```yaml
Type: System.String
DefaultValue: "'Entity'"
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

### AAC.ServiceBusLookup, AAC.ServiceBusLookupSubscription, AAC.ServiceBusLookupMetric, AAC.ServiceBusLookupSample, AAC.ServiceBusLookupFinding or AAC.ServiceBusLookupAccess, by -View (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Show-AACServiceBusEntity.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
