---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACApplicationPermission.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Get-AACApplicationPermission
---

# Get-AACApplicationPermission

## SYNOPSIS

Lists every permission an enterprise application or managed identity holds - API permissions, delegated consents, Entra directory roles (and their scope), Azure roles, owned objects and groups - with findings for the privileged ones, as a Spectre.Console view, objects, and CSV, HTML and PDF reports.

## SYNTAX

### __AllParameterSets

```
Get-AACApplicationPermission [-Identity] <string[]> [[-View] <string>] [[-CsvPath] <string>]
 [[-HtmlPath] <string>] [[-PdfPath] <string>] [[-Title] <string>] [-SkipAzure] [-PassThru]
 [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Read-only. For each -Identity it finds the service principal - by
object ID, application (client) ID, app registration object ID,
display name, or an Azure resource ID of a user-assigned identity
(or of a resource with a system-assigned one) - and reads, with
Microsoft Graph and Azure Resource Graph:

```text
  Application permission    each API's app roles granted to it
                            (Microsoft Graph User.Read.All...) -
                            tenant-wide, no user signed in
  Delegated permission      scopes consented for all users, or for
                            one user
  Directory role            Entra roles: at tenant scope, on an
                            administrative unit (with what the unit
                            holds - New-AACApplicationPermission's
                            scoped roles show here) or on one object;
                            direct, or through a role-assignable group
  Directory role (eligible) the same through PIM
  Azure role                Azure RBAC, direct or through a group,
                            with the scope in words (-SkipAzure
                            leaves it out)
  Owner                     applications, service principals and
                            groups it owns
  Group membership          the groups it is in
  Requested (not granted)   API permissions its app registration
                            asks for without consent
```

Findings: privileged application permissions (Directory.ReadWrite.All,
RoleManagement.ReadWrite.Directory, AppRoleAssignment.ReadWrite.All,
Mail.Send, Sites.FullControl.All...); privileged directory roles at
tenant scope (Global Administrator, Privileged Role Administrator,
Application Administrator...), any other role at tenant scope;
Azure Owner and User Access Administrator, Contributor on a
subscription or above; privileged delegated scopes consented for
everyone; owning another application.

The Entra admin center shows these in different places - API
permissions only under the application's Permissions; directory
roles under Roles & admins (and the administrative unit); Azure
roles under each scope's Access control - this lists them together.

Needs the Connect-AAC sign-in with read access to the directory
(Directory Readers is enough). A part that can't be read is a
notice, not an error. PIM-eligible roles need a Microsoft Graph
token with RoleManagement.Read.Directory, which the client
Connect-AAC uses by default can't get: sign in with
Connect-AAC -ClientId \<your app registration\> (that delegated
permission, admin-consented) to include them; everything else is
listed either way.

## EXAMPLES

### Example 1

```powershell
Get-AACApplicationPermission -Identity 'My-Enterprise-App'
```

Everything the enterprise application can do, and what is privileged.

### Example 2

```powershell
Get-AACApplicationPermission -Identity 11111111-2222-3333-4444-555555555555 -NoDisplay | Where-Object Kind -EQ 'Directory role'
```

By application (client) ID or object ID: its directory roles and their scope.

### Example 3

```powershell
Get-AACApplicationPermission -Identity '/subscriptions/<id>/resourceGroups/rg-app/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-app'
A user-assigned managed identity, by its Azure resource ID.
```

### Example 4

```powershell
'app-one', 'app-two', 'func-myapp-prod' | Get-AACApplicationPermission -HtmlPath .\AppPermissions.html -CsvPath .\AppPermissions.csv
```

Several at once, as reports.

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
  Position: 2
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
  Position: 3
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Identity

One or more: service principal object ID, application (client) ID,
app registration object ID, display name, or the Azure resource ID
of a managed identity (or of a resource with a system-assigned one).

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
Aliases:
- ServicePrincipal
- AppId
- ObjectId
- ServicePrincipalId
- PrincipalId
- ResourceId
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: true
  ValueFromPipeline: true
  ValueFromPipelineByPropertyName: true
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
  Position: 4
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SkipAzure

Leave out Azure role assignments (no Resource Graph query).

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

### -Title

The reports' title.

```yaml
Type: System.String
DefaultValue: "'Application permissions'"
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

### -View

Permission (default), Finding or Summary: what is returned and
written to -CsvPath.

```yaml
Type: System.String
DefaultValue: "'Permission'"
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.ApplicationPermissionEntry, AAC.ApplicationPermissionFinding or AAC.ApplicationPermissionSummary, by -View (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACApplicationPermission.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
