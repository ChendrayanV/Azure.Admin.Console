---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACAttackPath.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Get-AACAttackPath
---

# Get-AACAttackPath

## SYNOPSIS

Maps the attack paths through your Azure estate - from what the Internet can reach, through the identities it runs as, to what an attacker could then control or read - with each path's risk, blast radius and the fix, most dangerous first.

## SYNTAX

### __AllParameterSets

```
Get-AACAttackPath [[-SubscriptionId] <string[]>] [[-ManagementGroupId] <string[]>]
 [[-ResourceGroupName] <string[]>] [[-Severity] <string[]>] [[-CsvPath] <string>]
 [[-HtmlPath] <string>] [[-PdfPath] <string>] [[-Title] <string>] [-PassThru] [-NoDisplay]
 [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Reads the estate in one Azure Resource Graph batch and builds the
paths an attacker with a foothold would take:

```text
  Internet > vm-web-01 (public IP: RDP 3389) > system-assigned identity
           > Contributor on subscription sub-prod  (412 resources)
```

Entry points: VMs whose public IP the NSGs (NIC and subnet, rule by
rule in priority order) open to the Internet - management, database
or any port; App Service and Function apps open to the public; AKS
clusters with a public API server and no authorized IP ranges; and
data stores (storage, key vaults, SQL, Cosmos DB, PostgreSQL, MySQL)
open to every network.

From each entry: its managed identities and their role assignments
(read tenant-wide, so management group roles count) - control roles
(Owner, Contributor, User Access Administrator, RBAC Administrator,
custom roles with '\*' or Microsoft.Authorization writes) and data
access (data roles, key vault access policies). The blast radius is
what that reaches: every resource under a controlled scope, the data
stores readable, and a VM's neighbours in its virtual network.

Risk: Critical - an open entry whose identity controls a
subscription, management group or the tenant; High - control of a
resource group, data access, an open management port, anonymous
storage; Medium - other open ports, open data stores, a public API
server; Low - storage that accepts every network. Each path says what
to do and how much effort it is, so quick wins come first.

With Defender CSPM, Defender for Cloud's own attack paths are added
(Source 'Defender for Cloud'); without it, a notice says so.

What it doesn't see: network routes through firewalls or NVAs,
application-level flaws, and identities outside Azure RBAC. It shows
where to look first, not proof of compromise. Read-only; Reader is
enough.

## EXAMPLES

### Example 1

```powershell
Get-AACAttackPath
```

Every attack path in the subscriptions you can see, most dangerous first.

### Example 2

```powershell
Get-AACAttackPath -SubscriptionId $prod -Severity Critical, High -HtmlPath .\out\AttackPaths.html
```

The critical and high paths in production, as an HTML report.

### Example 3

```powershell
Get-AACAttackPath -NoDisplay | Where-Object Category -EQ 'Internet to subscription control' | Select-Object Resource, Path, BlastRadius
```

The footholds that lead to a whole subscription.

## PARAMETERS

### -CsvPath

Write the paths to this CSV file.

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

Return the paths without showing the view.

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

Show the view and also return the paths.

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

### -ResourceGroupName

Only paths that start in these resource groups.

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

### -Severity

Only paths of these risks (Critical, High, Medium, Low).

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
DefaultValue: "'Azure attack paths'"
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

### AAC.AttackPath

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACAttackPath.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
