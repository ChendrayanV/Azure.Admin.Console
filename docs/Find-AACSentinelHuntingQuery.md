---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Find-AACSentinelHuntingQuery.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Find-AACSentinelHuntingQuery
---

# Find-AACSentinelHuntingQuery

## SYNOPSIS

Lists the hunting queries you could deploy to Microsoft Sentinel - for Entra ID sign-ins and audit, Microsoft 365 and Intune - and, for a workspace, whether each is ready and how it stands there.

## SYNTAX

### Pack (Default)

```
Find-AACSentinelHuntingQuery [-Pack <string[]>] [-Name <string[]>] [-Tactic <string[]>]
 [-WorkspaceId <string>] [-SubscriptionId <string[]>] [-ResourceGroupName <string>] [-Days <int>]
 [-Ref <string>] [-Path <string>] [-CsvPath <string>] [-HtmlPath <string>] [-PdfPath <string>]
 [-Title <string>] [-PassThru] [-NoDisplay] [-NoPaging]
```

### YamlSource

```
Find-AACSentinelHuntingQuery -YamlSource <string[]> [-Name <string[]>] [-Tactic <string[]>]
 [-WorkspaceId <string>] [-SubscriptionId <string[]>] [-ResourceGroupName <string>] [-Days <int>]
 [-CsvPath <string>] [-HtmlPath <string>] [-PdfPath <string>] [-Title <string>] [-PassThru]
 [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

The shopping list: Get-AACSentinelHuntingQuery is the inventory of what
a workspace already has. Pipe this command to
Deploy-AACSentinelHuntingQuery. Read-only.

The packs:

```text
  SignIn       Entra ID sign-ins (SigninLogs and non-interactive)
  M365         Microsoft 365 (OfficeActivity, CloudAppEvents)
  EntraAudit   Entra ID directory changes (AuditLogs)
  Intune       Intune, written for this module: the Azure-Sentinel
               repository has none
```

The first three come from the Azure-Sentinel repository on GitHub, at a
commit pinned in the module, including the queries that repository
moved into its solutions. These queries are community content: read
one before relying on it. -Ref picks another commit, and -Path reads a
local clone instead of GitHub.

-YamlSource looks at files you name instead of the packs: links to
GitHub, or files on this computer. A link to a branch reads whatever is
on it now, not the pinned commit.

With -WorkspaceId, each query also says:

```text
  Readiness    Ready; Missing data (a table it needs had nothing in the
               last -Days); Missing watchlist; Unknown
  Deployment   New; Current; Update available; Changed (edited in the
               workspace, or not deployed by this module); Other copy
               (this name under another ID, say from Content hub)
```

Without it, it lists the catalog and needs no Azure sign-in.

Intune's tables fill only when Intune's diagnostic settings send logs
to the workspace (Intune admin center, Reports, Diagnostics settings).

What you get depends on where the command runs:

```text
  at the prompt    a summary, then the queries
  piped onward     the queries, with no view
  -PassThru        the view and the queries
  -NoDisplay       the queries only
```

-CsvPath, -HtmlPath and -PdfPath write reports instead of the view.

## EXAMPLES

### Example 1

```powershell
Find-AACSentinelHuntingQuery -Pack Intune
```

The Intune queries, with no Azure sign-in.

### Example 2

```powershell
Connect-AAC
Find-AACSentinelHuntingQuery -Pack SignIn, M365, Intune -WorkspaceId 'law-contoso-sentinel' -HtmlPath .\out\Hunting.html
```

What each pack offers, what this workspace is ready for, as a report.

### Example 3

```powershell
Find-AACSentinelHuntingQuery -Pack SignIn -Tactic InitialAccess -WorkspaceId 'law-contoso-sentinel' | Where-Object Ready | Deploy-AACSentinelHuntingQuery -WorkspaceId 'law-contoso-sentinel' -WhatIf
```

What deploying the ready sign-in queries for initial access would do.

### Example 4

```powershell
(Find-AACSentinelHuntingQuery -Name '*break-glass*' -NoDisplay).Query
```

Read a query before deploying it.

### Example 5

```powershell
Find-AACSentinelHuntingQuery -YamlSource 'https://github.com/Azure/Azure-Sentinel/blob/master/Hunting%20Queries/OfficeActivity/AnomolousUserAccessingOtherUsersMailbox.yaml' -WorkspaceId 'law-contoso-sentinel'
```

Look at one file, and whether this workspace is ready for it.

## PARAMETERS

### -CsvPath

Write the queries to this CSV file.

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

### -HtmlPath

Write an interactive HTML report to this file.

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

Return the queries without showing the view.

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

Show the whole view at once instead of a page at a time.

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

SignIn, M365, EntraAudit, Intune. All of them by default.

```yaml
Type: System.String[]
DefaultValue: "@('SignIn', 'M365', 'EntraAudit', 'Intune')"
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

### -PassThru

Show the view and also return the queries.

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

### -PdfPath

Write a PDF report to this file.

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

### -Title

The HTML and PDF reports' title.

```yaml
Type: System.String
DefaultValue: "'Microsoft Sentinel hunting queries'"
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

### -WorkspaceId

The workspace to check against: its workspace ID (GUID), resource ID or
name. Without it, only the catalog is listed.

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
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -YamlSource

Hunting query YAML files, instead of the packs: github.com/.../blob/...
or raw.githubusercontent.com links, or local paths. A stub in
Azure/Azure-Sentinel is followed to where the query moved. Stops if one
can't be read.

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

### AAC.SentinelHuntingQuery (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Find-AACSentinelHuntingQuery.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
