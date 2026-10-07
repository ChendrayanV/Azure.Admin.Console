---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACM365Assessment.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Invoke-AACM365Assessment
---

# Invoke-AACM365Assessment

## SYNOPSIS

Microsoft 365 tenant discovery and security posture - Entra ID, Microsoft 365 and Intune - read from the Microsoft Graph REST API with one token, with zero-trust findings, as a Spectre.Console view, an object, CSV files and a tabbed, interactive HTML report.

## SYNTAX

### Assess (Default)

```
Invoke-AACM365Assessment [-Section <string[]>] [-StaleDays <int>] [-SignInDays <int>]
 [-CsvPath <string>] [-HtmlPath <string>] [-Title <string>] [-PassThru] [-NoDisplay] [-NoPaging]
```

### Permission

```
Invoke-AACM365Assessment -ListPermission [-Section <string[]>]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Read-only, Microsoft Graph REST only: no AzureAD, MSOnline,
AzureADPreview or Microsoft.Graph modules. Every call uses the one
Graph token of the Connect-AAC sign-in; about 25 calls run in
parallel, each followed through its pages.

-Section picks what is read (everything by default):

```text
  Entra         tenant details and directory sync, licences,
                security defaults, user and guest settings
                (authorization policy), cross-tenant access,
                Conditional Access policies and named locations,
                admin roles - active and eligible (PIM) - with each
                admin's MFA registration, every user's MFA
                registration, authentication methods, identity
                providers - and:
                  MFA coverage           registered and phishing-
                                         resistant MFA by members,
                                         admins and guests; the MFA
                                         policy's exclusions
                  emergency access       break-glass accounts (excluded
                                         from every policy, or by
                                         name): two, cloud-only,
                                         Global Admin, passkey
                  dangling admins        privileged roles held by
                                         deleted, disabled, guest,
                                         idle, synced accounts or apps
                  role overlap           Global Admin plus more, three
                                         or more roles, active and
                                         eligible at once
                  legacy authentication  actual IMAP, POP, SMTP AUTH,
                                         ActiveSync... sign-ins in
                                         the last -SignInDays
                  user consent           who can consent to apps, and
                                         the admin consent workflow
                  security defaults      off with no MFA, or on when
                                         Conditional Access is
                                         licensed
  Applications  (with Entra) app registrations and enterprise
                apps: secrets and certificates expired, expiring or
                long-lived; over-privileged permissions (application
                permissions on Microsoft Graph and delegated
                consents, rated Critical, High, Medium); redirect
                URIs that are dangling (their host looked up in DNS),
                wildcard or not HTTPS
  Microsoft365  domains, Microsoft Secure Score and its controls
                (with the gap and how to fix each), SharePoint and
                OneDrive sharing settings, audit logging (Purview
                audit log search, from its Secure Score control, and
                the Entra audit log)
  Intune        tenant settings, enrollment restrictions,
                compliance policies, endpoint security policies
                (antivirus, firewall, disk encryption, EDR, attack
                surface reduction, account protection), managed
                devices (compliance, encryption, stale) and the
                Entra ID devices no MDM manages
```

PERMISSIONS. A Graph token carries the permissions consented to the
app you sign in with. Connect-AAC's default (the Azure CLI) can read
the directory but not Conditional Access, Intune or Secure Score.
For everything in one token, sign in with an app that has the
delegated (or, for a service principal, application) permissions
-ListPermission prints - for example Microsoft Graph Command Line
Tools, once an admin has consented:

```text
    Connect-AAC -ClientId 14d82eec-204b-4c2f-b7e8-296a70dab67e `
        -Scope ((Invoke-AACM365Assessment -ListPermission) + 'offline_access', 'openid', 'profile')
```

Your account also needs a directory role that can read them (Global
Reader, Security Reader plus Intune Administrator or reader roles).
Whatever Graph refuses is listed in the Permissions tab with the
permission it needs; the rest of the report is still made.

What you get depends on where the command runs:

```text
  at the prompt    tiles, the security settings, Conditional Access,
                   the privileged role assignments, what couldn't
                   be read and the findings, a page at a time
  piped onward     the AAC.M365Assessment object, with every table
                   as a property
  -PassThru        the view and the object
  -NoDisplay       the object only
```

-CsvPath (a folder) writes a CSV per table. -HtmlPath writes a
tabbed report - Overview, Findings, Entra ID, Microsoft 365, Intune,
Permissions - where every table can be searched, filtered, grouped
and downloaded, and a row opens all its details.

## EXAMPLES

### Example 1

```powershell
Connect-AAC -ClientId 14d82eec-204b-4c2f-b7e8-296a70dab67e -Scope ((Invoke-AACM365Assessment -ListPermission) + 'offline_access', 'openid', 'profile')
Invoke-AACM365Assessment -HtmlPath .\out\M365.html -CsvPath .\out\m365
```

Signs in once with every permission the report needs, then writes the HTML report and a CSV per table.

### Example 2

```powershell
Invoke-AACM365Assessment -Section Entra
```

Only Entra ID: settings, Conditional Access, admin roles and MFA registration.

### Example 3

```powershell
(Invoke-AACM365Assessment -NoDisplay -Section Entra).Registration | Where-Object { $_.Admin -eq 'Yes' -and $_.MfaRegistered -eq 'No' }
```

The administrators with no MFA method registered.

### Example 4

```powershell
(Invoke-AACM365Assessment -NoDisplay -Section Intune -StaleDays 30).ManagedDevices | Where-Object Stale -EQ 'Yes' | Export-Csv .\stale.csv
```

The Intune devices that haven't checked in for 30 days.

## PARAMETERS

### -CsvPath

A folder to write a CSV per table to.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Assess
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

Write the tabbed, interactive HTML report to this file.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Assess
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ListPermission

Return the Microsoft Graph permissions the report needs (as scopes
for Connect-AAC -Scope), and read nothing.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Permission
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -NoDisplay

Return the object without showing the view.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Assess
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
- Name: Assess
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

Show the view and also return the object.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Assess
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Section

What to read: Entra, Microsoft365, Intune. All by default.

```yaml
Type: System.String[]
DefaultValue: "@('Entra', 'Microsoft365', 'Intune')"
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Permission
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: Assess
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SignInDays

Look for sign-ins with legacy authentication protocols in the last
this many days (7 by default; Entra ID keeps sign-ins 30 days with
P1 or P2).

```yaml
Type: System.Int32
DefaultValue: 7
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Assess
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -StaleDays

A device that hasn't checked in (Intune) or signed in (Entra ID) for
more than this many days is stale. 90 by default.

```yaml
Type: System.Int32
DefaultValue: 90
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Assess
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

The HTML report's title.

```yaml
Type: System.String
DefaultValue: "'Microsoft 365 security posture'"
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Assess
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

### AAC.M365Assessment (piped onward, or with -PassThru or -NoDisplay) System.String (with -ListPermission)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACM365Assessment.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
