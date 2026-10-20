---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACCosmosDBAssessment.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Invoke-AACCosmosDBAssessment
---

# Invoke-AACCosmosDBAssessment

## SYNOPSIS

Assesses Azure Cosmos DB accounts across subscriptions - availability, rate limiting (429), errors, throughput and its use, storage, every database and container, security, resilience and cost - as a heat map, findings, a Spectre.Console view, objects, and CSV, PDF and interactive HTML reports.

## SYNTAX

### __AllParameterSets

```
Invoke-AACCosmosDBAssessment [[-SubscriptionId] <string[]>] [[-ManagementGroupId] <string[]>]
 [[-ResourceGroupName] <string[]>] [[-Name] <string[]>] [[-TimeRange] <string>] [[-View] <string>]
 [[-ThrottleLimit] <int>] [[-CsvPath] <string>] [[-HtmlPath] <string>] [[-PdfPath] <string>]
 [[-Title] <string>] [-PassThru] [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Read-only (Reader is enough), for every API - NoSQL, MongoDB,
Cassandra, Gremlin and Table:

```text
  Resource Graph    the accounts: regions, failover, consistency,
                    backup, capabilities (API, serverless), network
                    access, local authentication, TLS, encryption -
                    and the Defender for Azure Cosmos DB plan and its
                    alerts
  Resource Manager  each account's databases and containers, their
                    throughput (manual or autoscale, at the database
                    or the container), and where its logs go
  metrics           over -TimeRange: TotalRequests by status code,
                    TotalRequestUnits, NormalizedRUConsumption (the
                    busiest partition's share of its throughput),
                    ServiceAvailability, ServerSideLatency; and the
                    latest DataUsage, IndexUsage and DocumentCount
```

Findings (High, Medium, Low):

```text
  availability  service availability below 99.99%
  throttling    requests rate limited (429), running close to the
                throughput
  errors        server errors (5xx), slow server-side latency
  security      TLS below 1.2, open to every network, account keys
                allowed, keys able to change databases and
                containers, no logs to Log Analytics, Defender off
                or alerting
  resilience    a single region, no automatic failover, no
                availability zones, periodic backup only (or stored
                in one datacentre), Strong consistency across regions
  cost          throughput higher than needed, no requests in the
                period, many small containers with their own
                throughput
```

The heat map scores each account 0-100 for availability, throttling,
errors, security, resilience and cost - the 40 worst at the prompt
and in the reports; clicking a cell in the HTML lists its findings.

-View sets what is returned (piped onward, -PassThru, -NoDisplay) and
written to -CsvPath: Account (default), Container or Finding.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Invoke-AACCosmosDBAssessment
```

Every account's availability, throttling, throughput, posture and findings over the last day.

### Example 2

```powershell
Invoke-AACCosmosDBAssessment -NoDisplay | Where-Object Throttled | Select-Object -Property Account, Throttled, ThrottleRate, NormalizedRuMax, ProvisionedRU, AutoscaleMaxRU
```

The accounts rate limiting requests, and the throughput they have.

### Example 3

```powershell
Invoke-AACCosmosDBAssessment -View Container -NoDisplay | Where-Object ThroughputMode -EQ 'Manual' | Sort-Object -Property RU -Descending
```

The containers with manual throughput, the most first - candidates for autoscale.

### Example 4

```powershell
Invoke-AACCosmosDBAssessment -ResourceGroupName 'rg-data' -TimeRange 7d -HtmlPath .\out\CosmosDB.html -PdfPath .\out\CosmosDB.pdf
A week of a workload's accounts, as reports.
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

How far back the metrics go: 1h, 4h, 12h, 1d (default), 3d, 7d, 14d
or 30d. Storage is always the latest value.

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
DefaultValue: "'Cosmos DB assessment'"
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

Account, Container or Finding: what is returned and written to -CsvPath.

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

### AAC.CosmosDBAssessment, AAC.CosmosDBContainer or AAC.CosmosDBFinding, by -View (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACCosmosDBAssessment.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
