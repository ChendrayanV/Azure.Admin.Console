---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACPrivateEndpoint.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Get-AACPrivateEndpoint
---

# Get-AACPrivateEndpoint

## SYNOPSIS

Audits your private endpoints - each connection's state, the resource behind it, its IP addresses and names, the private DNS zone that resolves it and whether its network can see that zone - and finds what breaks private connectivity: pending or disconnected connections, orphaned endpoints, missing or unlinked DNS zones, and targets still open to the Internet.

## SYNTAX

### __AllParameterSets

```
Get-AACPrivateEndpoint [[-SubscriptionId] <string[]>] [[-ManagementGroupId] <string[]>]
 [[-ResourceGroupName] <string[]>] [[-Name] <string[]>] [[-TargetType] <string[]>]
 [[-Status] <string[]>] [[-CsvPath] <string>] [[-HtmlPath] <string>] [[-PdfPath] <string>]
 [[-Title] <string>] [-SkipDnsZoneGroup] [-PassThru] [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Reads, read-only:

```text
  Resource Graph     the private endpoints and their connections
                     (automatic and manual approval), the private
                     DNS zones and their virtual network links, the
                     virtual networks (DNS servers, peerings) and
                     every resource that takes private endpoint
                     connections (does it exist, is it still public?)
  Resource Manager   each endpoint's private DNS zone groups (which
                     zone holds its record)
```

One row per endpoint connection (AAC.PrivateEndpoint), Healthy,
Review, Warning or Failed, with its issues; and the findings
(AAC.PrivateEndpointFinding), each with what to do:

```text
  a connection Pending, Rejected or Disconnected; an endpoint whose
  target was deleted; provisioning failed; the zone not linked to
  the endpoint's network or one peered with it; no zone group; the
  wrong zone for the service (blob in the file zone, say); the
  target still open to public networks; the same privatelink zone
  defined in several places.
```

The zone each service needs is known for storage, Key Vault, SQL,
Cosmos DB, PostgreSQL, MySQL, Container Registry, App Service,
Service Bus and Event Hubs, App Configuration, AI Search, Redis,
Azure AI services, Data Factory, Event Grid, SignalR, Automation,
Azure Monitor and more. A network with custom DNS servers can't be
checked from Azure alone: it is flagged for review.

Read-only; Reader is enough.

## EXAMPLES

### Example 1

```powershell
Get-AACPrivateEndpoint
```

Every private endpoint you can see, the broken ones first, and the findings.

### Example 2

```powershell
Get-AACPrivateEndpoint -Status Failed, Warning -HtmlPath .\out\PrivateEndpoints.html
```

What needs fixing, as an interactive HTML report.

### Example 3

```powershell
Get-AACPrivateEndpoint -TargetType 'microsoft.storage/storageaccounts' -NoDisplay | Select-Object Endpoint, Target, GroupId, IpAddresses, DnsZones, ZoneLinked
```

The storage endpoints, their IPs and DNS.

## PARAMETERS

### -CsvPath

Write the endpoint connections to this CSV file.

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

### -HtmlPath

Write an interactive HTML report.

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

### -Name

Only endpoints whose name matches; wildcards work.

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

Return the endpoint connections without showing the view.

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

Show the view and also return the endpoint connections.

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
  Position: 8
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ResourceGroupName

Only endpoints in these resource groups (their zones, networks and
targets can be anywhere).

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

### -SkipDnsZoneGroup

Don't read the DNS zone groups (one call per endpoint): faster, but
DNS isn't checked.

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

### -Status

Only connections in these states (Failed, Warning, Review, Healthy).

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

### -TargetType

Only endpoints to resources of these types (for example
'microsoft.storage/storageaccounts', or '\*sql\*'); wildcards work.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: true
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
DefaultValue: "'Azure private endpoints'"
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

### AAC.PrivateEndpoint

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACPrivateEndpoint.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
