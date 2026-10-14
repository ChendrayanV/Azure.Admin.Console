---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACEntraGroupMembership.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Get-AACEntraGroupMembership
---

# Get-AACEntraGroupMembership

## SYNOPSIS

Who is in your Entra ID groups - direct members and everyone in the groups nested in them - flattened to one row per group and member, with a Spectre.Console view, objects, and CSV, PDF and interactive HTML reports.

## SYNTAX

### __AllParameterSets

```
Get-AACEntraGroupMembership [[-GroupName] <string[]>] [[-GroupNameStartsWith] <string>]
 [[-CsvPath] <string>] [[-CsvLayout] <string>] [[-PdfPath] <string>] [[-HtmlPath] <string>]
 [[-Title] <string>] [-PassThru] [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Reads the groups and their members from Microsoft Graph, following
nested groups to the end (a loop is followed once):

```text
  -GroupName            these groups, by exact display name
  -GroupNameStartsWith  every group whose name starts with this
  neither               every group in the tenant
```

Both can be given together.

It uses the Connect-AAC sign-in - no second prompt: a Microsoft Graph
token is taken from it silently, as other APIs' tokens are. Your
account needs to be allowed to read groups in Entra ID, which members
of the tenant are by default. With an App Registration of your own
(Connect-AAC -ClientId), give it Microsoft Graph's delegated
Group.Read.All and User.Read.All permissions. Nothing is written to
Entra ID.

One row per member of each group (AAC.EntraGroupMember): GroupName,
GroupType (Microsoft 365, Security, Mail-enabled security,
Distribution - dynamic, role-assignable), GroupSource (Cloud, or
synced from on-premises AD), MembershipType (Assigned, Dynamic,
Dynamic (paused)), GroupCreated (UTC), GroupOwners ('Name (UPN);
...' - users and service principals - or '(No owners)'),
MemberName, MemberType (User, Group,
Device, Service principal, Contact), UserPrincipalName, Mail,
UserType (Member or Guest), AccountEnabled, JobTitle, Department,
Membership (Direct, Nested, or Empty for a group with no members),
Via (the nested path, 'Group \> Nested group'), Depth, GroupId and
MemberId. The same rows go to CSV, HTML and PDF.

What you get depends on where the command runs:

```text
  at the prompt    tiles and a table of the groups, then each
                   group in turn: its details (type, source,
                   membership type, created, owners, counts), its
                   direct members, and each nested group's members
                   under its path - a page at a time
  piped onward     the rows, with no view
  -PassThru        the view and the rows
  -NoDisplay       the rows only
```

-CsvPath writes the CSV - by default in Export-EntraGroupMemberShip.ps1's
layout: one row per group with GroupName, GroupSource (Cloud or
Windows Server AD), GroupType ('Security', 'Microsoft 365 / Dynamic',
'Mail-Enabled Security / Role-Assignable' ...), Members (everyone in
the group, flattened: direct members and the members of every nested
group at any depth - users, service principals, devices, contacts -
each once, or '(No members)') and NestedGroupMembers
(every nested group at any depth, by its path, with its own members:
'Group: a, b; Group \> Inner: c'), then Owners, CreatedDateTime (UTC)
and MembershipType. -CsvLayout Member writes the rows above instead, one per
group and member. -HtmlPath writes an interactive report: tiles, the
groups as a tree (each group's details, owners and direct members,
nested groups opening to their own members - searchable), charts,
and tabs with the groups, everyone in each group once (Direct,
Nested or both, and through which nested group) and every
membership row - filterable and downloadable as CSV. -PdfPath
writes a PDF: the summary, the groups, then a page per group with
its details, direct members and each nested group's members.
With any of them, the console shows only the progress and the files
written.

## EXAMPLES

### Example 1

```powershell
Get-AACEntraGroupMembership -GroupName 'grp-finance', 'grp-hr'
```

Two groups, with everyone in them, direct or nested.

### Example 2

```powershell
Get-AACEntraGroupMembership -GroupNameStartsWith 'grp-azure-' -HtmlPath .\out\Groups.html -CsvPath .\out\Groups.csv
```

Every group whose name starts with 'grp-azure-', as an interactive HTML report and a CSV file - one row per group, as Export-EntraGroupMemberShip.ps1 writes it.

### Example 3

```powershell
Get-AACEntraGroupMembership -GroupNameStartsWith 'grp-' -CsvPath .\out\Members.csv -CsvLayout Member
```

One CSV row per group and member instead, nested members at every depth, with the path they came through.

### Example 4

```powershell
Get-AACEntraGroupMembership -GroupNameStartsWith 'grp-' -NoDisplay | Where-Object { $_.UserType -eq 'Guest' }
```

The guests in those groups, and through which group.

### Example 5

```powershell
Connect-AAC
Get-AACEntraGroupMembership -PdfPath .\out\Groups.pdf
```

Every group in the tenant you signed in to, as a PDF report.

## PARAMETERS

### -CsvLayout

Group (the default): one row per group, as Export-EntraGroupMemberShip.ps1
writes it - a group whose members can't be read is left out, with a
warning. Member: one row per group and member (the rows the command
returns), nested members at every depth.

```yaml
Type: System.String
DefaultValue: "'Group'"
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

### -CsvPath

Write the CSV to this file (see -CsvLayout). Alias: OutputPath.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases:
- OutputPath
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

### -GroupName

The display names of the groups to report on (exact matches). Alias:
GroupNames.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
Aliases:
- GroupNames
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

### -GroupNameStartsWith

Report on every group whose display name starts with this.

```yaml
Type: System.String
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

Write an interactive HTML report to this file.

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

Write a PDF report to this file.

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

### -Title

The PDF and HTML reports' title.

```yaml
Type: System.String
DefaultValue: "'Entra ID group membership'"
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

### AAC.EntraGroupMember (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACEntraGroupMembership.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
