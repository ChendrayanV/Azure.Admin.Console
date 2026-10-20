---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACResourceLock.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Get-AACResourceLock
---

# Get-AACResourceLock

## SYNOPSIS

Lists every resource lock - on subscriptions, resource groups and resources - and the critical resources no lock protects, with ReadOnly locks that break more than they protect flagged.

## SYNTAX

### __AllParameterSets

```
Get-AACResourceLock [[-SubscriptionId] <string[]>] [[-ManagementGroupId] <string[]>]
 [[-CriticalType] <string[]>] [[-Status] <string[]>] [[-CsvPath] <string>] [[-HtmlPath] <string>]
 [[-PdfPath] <string>] [[-Title] <string>] [-PassThru] [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Reads, read-only: each subscription's locks (Resource Manager - a
subscription's list includes those on its resource groups and
resources), and from Resource Graph its resource groups and the
resources of the critical types.

Rows (AAC.ResourceLock):

```text
  Locked    each lock: level (CanNotDelete or ReadOnly), scope,
            notes. ReadOnly is a finding - Medium on a subscription
            or resource group, where it also blocks listing keys,
            scaling and many portal pages; Low on a resource
  Unlocked  each critical resource with no lock on it, its
            resource group or its subscription (Low)
```

A lock covers its scope and everything below it. The headline says
how many critical resources are locked directly, through a parent,
or not at all, and how many resource groups a lock covers.

The critical types (-CriticalType to choose your own): key vaults,
storage accounts, SQL servers, Cosmos DB, PostgreSQL and MySQL
flexible servers, Recovery Services and backup vaults, virtual
networks, ExpressRoute circuits, Azure Firewalls, public and private
DNS zones, Log Analytics workspaces. Reader is enough.

## EXAMPLES

### Example 1

```powershell
Get-AACResourceLock
```

Every lock, and the critical resources left unlocked.

### Example 2

```powershell
Get-AACResourceLock -Status Unlocked -NoDisplay | Select-Object Scope, ResourceType
```

The critical resources nothing protects from deletion.

### Example 3

```powershell
Get-AACResourceLock -CriticalType 'microsoft.keyvault/vaults', 'microsoft.recoveryservices/vaults' -HtmlPath .\Locks.html
```

Locks, judged against your own list of critical types.

## PARAMETERS

### -CriticalType

The resource types that should be locked (Resource Graph type names,
such as 'microsoft.keyvault/vaults'), instead of the default list.

```yaml
Type: System.String[]
DefaultValue: "@('microsoft.keyvault/vaults', 'microsoft.storage/storageaccounts', 'microsoft.sql/servers', 'microsoft.documentdb/databaseaccounts', 'microsoft.dbforpostgresql/flexibleservers', 'microsoft.dbformysql/flexibleservers', 'microsoft.recoveryservices/vaults', 'microsoft.dataprotection/backupvaults', 'microsoft.network/virtualnetworks', 'microsoft.network/expressroutecircuits', 'microsoft.network/azurefirewalls', 'microsoft.network/dnszones', 'microsoft.network/privatednszones', 'microsoft.operationalinsights/workspaces')"
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

### -CsvPath

Write the locks to this CSV file.

```yaml
Type: System.String
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

### -HtmlPath

Write an interactive HTML report.

```yaml
Type: System.String
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
  Position: 6
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Status

Only these: Locked, Unlocked.

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

### -Title

The reports' title.

```yaml
Type: System.String
DefaultValue: "'Resource locks'"
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.ResourceLock

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACResourceLock.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
