---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACHealthCheck.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Invoke-AACHealthCheck
---

# Invoke-AACHealthCheck

## SYNOPSIS

Checks that your applications and their Azure platform are healthy right now - endpoints answering (synthetic requests, latency, TLS certificates), databases reachable, queues flowing, Resource Health, Service Health and fired alerts - by tier, with an SLA report.

## SYNTAX

### __AllParameterSets

```
Invoke-AACHealthCheck [[-Uri] <string[]>] [[-Endpoint] <hashtable[]>] [[-TcpEndpoint] <string[]>]
 [[-SubscriptionId] <string[]>] [[-ManagementGroupId] <string[]>] [[-ResourceGroupName] <string[]>]
 [[-Count] <int>] [[-IntervalSeconds] <int>] [[-TimeoutSeconds] <int>] [[-SlaTarget] <double>]
 [[-LatencyThresholdMs] <int>] [[-CertificateDays] <int>] [[-QueueBacklog] <long>]
 [[-MaxEndpoints] <int>] [[-CsvPath] <string>] [[-HtmlPath] <string>] [[-PdfPath] <string>]
 [[-Title] <string>] [-Discover] [-IncludeDatabase] [-SkipAzure] [-Watch] [-PassThru] [-NoDisplay]
 [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Endpoints - synthetic transactions, -Count rounds -IntervalSeconds
apart, all at once:

```text
  -Uri          URLs; up when they answer 200-399
  -Endpoint     @{ Name; Uri; Tier; ExpectedStatus; Contains; Method;
                TimeoutSeconds } - Contains is text the response must
                have, for an end-to-end check (a /health page that
                reports its dependencies)
  -Discover     the public endpoints of the App Service and Function
                apps, Container Apps, Static Web Apps, Front Door
                endpoints and API Management gateways (its status
                endpoint) in scope; up unless the server errs (5xx)
```

Each: availability, 50th and 95th percentile latency, and its TLS
certificate's expiry. The requests carry no Azure credential.
-TcpEndpoint 'host:port', and with -IncludeDatabase the SQL,
PostgreSQL, MySQL and Redis servers in scope, are connected to (TCP)
from where the command runs.

The platform (unless -SkipAzure): Service Bus queues (backlog and
dead letters), Resource Health (unavailable and degraded resources),
active Service Health events and alerts fired in the last 24 hours.

Each check is Success, Warning or Failed, with what was found and
what to do; the SLA table compares each endpoint's availability with
-SlaTarget. -Watch repeats the whole check until Ctrl+C, redrawing
it each time - a live board to keep open during an incident.

Read-only: GET requests and TCP connections only. -SkipAzure needs
no sign-in at all.

## EXAMPLES

### Example 1

```powershell
Invoke-AACHealthCheck -Discover -ResourceGroupName 'rg-app-prod'
```

The production app's endpoints, queues and platform health.

### Example 2

```powershell
Invoke-AACHealthCheck -SkipAzure -Endpoint @{ Name = 'Checkout'; Uri = 'https://shop.contoso.com/health'; Tier = 'Critical'; Contains = '"status":"Healthy"' } -Count 10 -IntervalSeconds 30 -HtmlPath .\out\Sla.html
```

Ten checks of the checkout's health page, five minutes apart, as an SLA report.

### Example 3

```powershell
Invoke-AACHealthCheck -Discover -Watch -IntervalSeconds 60
A live board, refreshed every minute, until Ctrl+C.
```

## PARAMETERS

### -CertificateDays

A certificate expiring sooner is a warning (30 days by default).

```yaml
Type: System.Int32
DefaultValue: 30
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

### -Count

How many rounds of requests (1 to 100; 3 by default).

```yaml
Type: System.Int32
DefaultValue: 3
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

### -CsvPath

Write the checks to this CSV file.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 14
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Discover

Also check the public endpoints of the web apps, container apps,
static web apps, Front Door and API Management in scope.

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

### -Endpoint

Endpoints to check, with what to expect (see the description).

```yaml
Type: System.Collections.Hashtable[]
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

### -HtmlPath

Write an interactive HTML report, with the SLA table.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 15
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -IncludeDatabase

Also connect to the SQL, PostgreSQL, MySQL and Redis servers in scope.

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

### -IntervalSeconds

Seconds between rounds (0 to 3600; 5 by default).

```yaml
Type: System.Int32
DefaultValue: 5
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

### -LatencyThresholdMs

Slower 95th percentile latency is a warning (2000 ms by default).

```yaml
Type: System.Int32
DefaultValue: 2000
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

### -ManagementGroupId

Only the subscriptions under these management groups.

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

### -MaxEndpoints

At most this many discovered endpoints are checked (100 by default).

```yaml
Type: System.Int32
DefaultValue: 100
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 13
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -NoDisplay

Return the checks without showing the view.

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

Show the view and also return the checks.

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
  Position: 16
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -QueueBacklog

More messages waiting is a warning (1000 by default).

```yaml
Type: System.Int64
DefaultValue: 1000
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 12
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ResourceGroupName

Only these resource groups (discovery, queues and Resource Health).

```yaml
Type: System.String[]
DefaultValue: None
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

### -SkipAzure

Check only the endpoints given - no Azure reads, no sign-in.

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

### -SlaTarget

The availability target, in percent (99.9 by default).

```yaml
Type: System.Double
DefaultValue: 99.9
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

### -SubscriptionId

Only these subscriptions.

```yaml
Type: System.String[]
DefaultValue: None
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

### -TcpEndpoint

host:port pairs to connect to.

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

### -TimeoutSeconds

How long to wait for each request (1 to 120; 10 by default).

```yaml
Type: System.Int32
DefaultValue: 10
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

### -Title

The reports' title.

```yaml
Type: System.String
DefaultValue: "'Health check'"
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 17
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Uri

URLs to check.

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

### -Watch

Repeat the check until Ctrl+C, redrawing the view each time.

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.HealthCheck

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACHealthCheck.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
