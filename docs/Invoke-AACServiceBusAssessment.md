---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACServiceBusAssessment.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Invoke-AACServiceBusAssessment
---

# Invoke-AACServiceBusAssessment

## SYNOPSIS

Assesses Azure Service Bus namespaces across subscriptions - health, capacity, every queue, topic and subscription's messages (active, dead-lettered, scheduled), security, resilience and cost - as a heat map, findings, a Spectre.Console view, objects, and CSV, PDF and interactive HTML reports.

## SYNTAX

### __AllParameterSets

```
Invoke-AACServiceBusAssessment [[-SubscriptionId] <string[]>] [[-ManagementGroupId] <string[]>]
 [[-ResourceGroupName] <string[]>] [[-Name] <string[]>] [[-TimeRange] <string>] [[-View] <string>]
 [[-ThrottleLimit] <int>] [[-CsvPath] <string>] [[-HtmlPath] <string>] [[-PdfPath] <string>]
 [[-Title] <string>] [-PassThru] [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Read-only (Reader is enough):

```text
  Resource Graph    the namespaces: tier, messaging units, TLS, local
                    (SAS) authentication, public network access, zone
                    redundancy, private endpoints, encryption
  Resource Manager  each namespace's queues, topics and their
                    subscriptions (message counts and sizes as they
                    are now), network rules, SAS rules, geo-disaster
                    recovery alias, and where its logs go
  metrics           over -TimeRange: IncomingRequests,
                    SuccessfulRequests, ServerErrors, UserErrors,
                    ThrottledRequests, IncomingMessages,
                    OutgoingMessages - and for Premium,
                    NamespaceCpuUsage and NamespaceMemoryUsage
```

Findings (High, Medium, Low):

```text
  health      throttled requests, server errors, many client errors
              (lost locks, missing entities)
  capacity    Premium CPU or memory close to the messaging units'
              limit
  messages    dead-lettered and transfer dead-lettered messages,
              entities filling up (sends fail at 100%), entities not
              active, active backlogs, topics with no subscription,
              expired messages dropped instead of dead-lettered
  security    TLS below 1.2, SAS keys allowed, more than one
              namespace-wide Manage key, open to every network, no
              logs to Log Analytics
  resilience  Premium not zone redundant, no geo-disaster recovery,
              Basic tier
  cost        more messaging units than needed, no requests in the
              period, queues and topics unused for 30 days
```

The heat map scores each namespace 0-100 for health, capacity,
messages, security, resilience and cost - the 40 worst at the prompt
and in the reports; clicking a cell in the HTML lists its findings.

-View sets what is returned (piped onward, -PassThru, -NoDisplay) and
written to -CsvPath: Namespace (default), Entity or Finding.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Invoke-AACServiceBusAssessment
```

Every namespace's health, messages, posture and findings over the last day.

### Example 2

```powershell
Invoke-AACServiceBusAssessment -View Entity -NoDisplay | Where-Object DeadLetters | Sort-Object -Property DeadLetters -Descending
```

The queues and subscriptions with dead-lettered messages, the most first.

### Example 3

```powershell
Invoke-AACServiceBusAssessment -ResourceGroupName 'rg-integration' -TimeRange 7d -HtmlPath .\out\ServiceBus.html -PdfPath .\out\ServiceBus.pdf
A week of a workload's namespaces, as reports.
```

### Example 4

```powershell
Invoke-AACServiceBusAssessment -View Finding -NoDisplay | Where-Object Signal -EQ 'Security'
```

The security findings, to fix.

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

Only namespaces with these names; wildcards work.

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

How far back the metrics go: 1h, 4h, 12h, 1d (default), 3d, 7d, 14d
or 30d. Message counts are always as they are now.

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
DefaultValue: "'Service Bus assessment'"
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

Namespace, Entity or Finding: what is returned and written to -CsvPath.

```yaml
Type: System.String
DefaultValue: "'Namespace'"
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

### AAC.ServiceBusAssessment, AAC.ServiceBusEntity or AAC.ServiceBusFinding, by -View (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACServiceBusAssessment.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
