---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Deploy-AACSentinelHuntingQuery.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Deploy-AACSentinelHuntingQuery
---

# Deploy-AACSentinelHuntingQuery

## SYNOPSIS

Adds hunting queries to a Microsoft Sentinel workspace, from the packs, from YAML files you name or from Find-AACSentinelHuntingQuery, and keeps them up to date.

## SYNTAX

### Pack (Default)

```
Deploy-AACSentinelHuntingQuery [-WorkspaceId] <string> -Pack <string[]> [-Name <string[]>]
 [-Tactic <string[]>] [-SubscriptionId <string[]>] [-ResourceGroupName <string>] [-Days <int>]
 [-Ref <string>] [-Path <string>] [-IncludeNotReady] [-OverwriteChanged] [-Force] [-PassThru]
 [-NoDisplay] [-WhatIf] [-Confirm]
```

### InputObject

```
Deploy-AACSentinelHuntingQuery [-WorkspaceId] <string> -InputObject <Object[]> [-Name <string[]>]
 [-Tactic <string[]>] [-SubscriptionId <string[]>] [-ResourceGroupName <string>] [-Days <int>]
 [-IncludeNotReady] [-OverwriteChanged] [-Force] [-PassThru] [-NoDisplay] [-WhatIf] [-Confirm]
```

### YamlSource

```
Deploy-AACSentinelHuntingQuery [-WorkspaceId] <string> -YamlSource <string[]> [-Name <string[]>]
 [-Tactic <string[]>] [-SubscriptionId <string[]>] [-ResourceGroupName <string>] [-Days <int>]
 [-IncludeNotReady] [-OverwriteChanged] [-Force] [-PassThru] [-NoDisplay] [-WhatIf] [-Confirm]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Plans, shows the plan, asks, applies. Each query is a saved search in
the Hunting Queries category, which is how Sentinel stores them, with
the query's ID from its source file: running this again updates it
rather than adding another.

What happens to each query:

```text
  Create   not on the workspace, and ready
  Update   deployed by this module, unedited, and the catalog has moved on
  Skip     already current; not ready (a table with no data, a missing
           watchlist - -IncludeNotReady deploys it anyway); edited in the
           workspace or not deployed by this module (-OverwriteChanged
           replaces it); or this name is already there under another ID,
           say from Content hub (always skipped: a second copy would
           only confuse)
```

Entity mappings in the source files aren't deployed: a saved search has
nowhere to put them, and Microsoft's own solutions leave them out too.

These queries are community content, and only read data: read one before
relying on it. -WhatIf shows the plan and writes nothing. -Force skips
the question, for pipelines; it doesn't overwrite an edited query.

-YamlSource deploys files you name instead of a pack: links to GitHub, or
files on this computer. They go through the same plan and rules, so a
file whose tables have no data is skipped unless -IncludeNotReady says
otherwise. A link to a branch reads whatever is on it now, not the
pinned commit: link to a commit to deploy exactly what you read.

Needs Microsoft Sentinel Contributor or Log Analytics Contributor on the
workspace.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Deploy-AACSentinelHuntingQuery -WorkspaceId 'law-contoso-sentinel' -Pack SignIn, M365, Intune -WhatIf
```

The plan: what would be created, updated and skipped, and why. Nothing is written.

### Example 2

```powershell
Deploy-AACSentinelHuntingQuery -WorkspaceId 'law-contoso-sentinel' -Pack Intune -IncludeNotReady
```

Add the Intune queries, even before Intune's logs reach the workspace.

### Example 3

```powershell
Find-AACSentinelHuntingQuery -Pack SignIn -Tactic InitialAccess | Deploy-AACSentinelHuntingQuery -WorkspaceId 'law-contoso-sentinel'
```

Add the sign-in queries for one tactic.

### Example 4

```powershell
Deploy-AACSentinelHuntingQuery -SubscriptionId 00000000-0000-0000-0000-000000000000 -ResourceGroupName 'rg-sentinel' -WorkspaceName 'law-sentinel' -YamlSource 'https://github.com/Azure/Azure-Sentinel/blob/master/Hunting%20Queries/OfficeActivity/AnomolousUserAccessingOtherUsersMailbox.yaml'
```

Add one query from a link. This file has moved, so the query is read from where it says it went.

### Example 5

```powershell
Deploy-AACSentinelHuntingQuery -WorkspaceId 'law-sentinel' -YamlSource .\queries\OurOwnQuery.yaml, .\queries\AnotherOne.yaml -WhatIf
```

The plan for your own query files.

## PARAMETERS

### -Confirm



```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases:
- cf
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

### -Days

How far back a table must have data to count: 1 to 90 days, 30 by
default.

```yaml
Type: System.Int32
DefaultValue: 30
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

### -Force

Apply without asking (for pipelines).

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

### -IncludeNotReady

Also create queries whose tables have no data or whose watchlists are
missing.

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

### -InputObject

Queries from Find-AACSentinelHuntingQuery, instead of -Pack.

```yaml
Type: System.Object[]
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: InputObject
  Position: Named
  IsRequired: true
  ValueFromPipeline: true
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Name

Only queries with these names (wildcards work).

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: true
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

### -NoDisplay

Return the deployment without showing the plan.

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

### -OverwriteChanged

Replace queries that were edited in the workspace, or that this module
didn't deploy.

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

### -Pack

SignIn, M365, EntraAudit, Intune.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Pack
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -PassThru

Show the plan and also return the deployment.

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

### -Path

The top folder of a local clone of Azure/Azure-Sentinel, instead of
GitHub.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Pack
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Ref

The commit, branch or tag of Azure/Azure-Sentinel to read. A commit
pinned in the module by default.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Pack
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ResourceGroupName

Narrows a workspace given by name, when the name is in more than one
resource group.

```yaml
Type: System.String
DefaultValue: None
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

### -SubscriptionId

Where to look for a workspace given by ID (GUID) or name. Every
subscription the account can see by default.

```yaml
Type: System.String[]
DefaultValue: None
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

### -Tactic

Only queries for these MITRE ATT&CK tactics, such as InitialAccess.

```yaml
Type: System.String[]
DefaultValue: None
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

### -WhatIf



```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases:
- wi
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

### -WorkspaceId

The workspace: its workspace ID (GUID), resource ID or name.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases:
- Workspace
- WorkspaceName
- ResourceId
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

### -YamlSource

Hunting query YAML files, instead of a pack: github.com/.../blob/... or
raw.githubusercontent.com links, or local paths. A stub in
Azure/Azure-Sentinel is followed to where the query moved. If one can't
be read, nothing is deployed.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: YamlSource
  Position: Named
  IsRequired: true
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

### AAC.SentinelHuntingDeployment (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Deploy-AACSentinelHuntingQuery.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
