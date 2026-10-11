---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACLegacyAuthentication.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Get-AACLegacyAuthentication
---

# Get-AACLegacyAuthentication

## SYNOPSIS

Finds legacy and high-risk authentication across Azure and Entra ID - resources that still accept keys, SAS, local accounts, passwords or old TLS, legacy-protocol sign-ins, legacy authentication left unblocked, implicit grant and password flows, client secrets and SMS - with the risk and what to move to.

## SYNTAX

### __AllParameterSets

```
Get-AACLegacyAuthentication [[-SubscriptionId] <string[]>] [[-ManagementGroupId] <string[]>]
 [[-ResourceGroupName] <string[]>] [[-ResourceType] <string[]>] [[-Area] <string[]>]
 [[-Severity] <string[]>] [[-SignInDays] <int>] [[-CsvPath] <string>] [[-HtmlPath] <string>]
 [[-PdfPath] <string>] [[-Title] <string>] [-SkipEntra] [-SkipAppService] [-PassThru] [-NoDisplay]
 [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Azure (Resource Graph, and Resource Manager for App Service):

```text
  Keys and SAS      storage shared keys; local authentication on
                    Cosmos DB, Service Bus, Event Hubs, Relay, Event
                    Grid, SignalR, Web PubSub, App Configuration,
                    Azure AI services, AI Search, Automation, IoT
                    Hub, Batch, Log Analytics and Application
                    Insights; Redis access keys
  Passwords         SQL authentication, PostgreSQL passwords, the
                    container registry admin user, Linux password
                    login, App Service basic authentication (SCM and
                    FTP publishing credentials)
  Local accounts    AKS local accounts, AKS without Entra ID
  Old TLS           TLS 1.0/1.1 on storage, SQL and Redis; Redis's
                    non-TLS port
  Legacy authorization  Key Vault access policies
```

Entra ID (Microsoft Graph, unless -SkipEntra):

```text
  Legacy protocols  sign-ins over Exchange ActiveSync, IMAP, POP,
                    SMTP AUTH, EWS, MAPI, Outlook Anywhere,
                    Autodiscover and other clients in the last
                    -SignInDays - successful (High) or failed
                    (password spraying); whether Conditional Access
                    or security defaults block legacy authentication
  Legacy flows      app registrations with the implicit grant or
                    public client flows (ROPC, device code)
  Client secrets    app registrations with secrets and no
                    certificate
  Weak MFA          SMS and voice enabled
```

Each finding (AAC.LegacyAuthentication) has its Area (Azure or Entra
ID), severity, the resource or protocol, the detail and the fix.
Read-only; Reader in Azure, and for Entra ID AuditLog.Read.All (with
Entra ID P1 for sign-ins), Policy.Read.All and Application.Read.All.

## EXAMPLES

### Example 1

```powershell
Get-AACLegacyAuthentication
```

Legacy authentication in Azure and Entra ID, the riskiest first.

### Example 2

```powershell
Get-AACLegacyAuthentication -Area EntraID -SignInDays 30 -HtmlPath .\out\LegacyAuth.html
A month of legacy-protocol sign-ins and the tenant's settings, as an HTML report.
```

### Example 3

```powershell
Get-AACLegacyAuthentication -SkipEntra -NoDisplay | Group-Object Finding | Sort-Object Count -Descending
```

Which key- and password-based patterns are most common in Azure.

## PARAMETERS

### -Area

Only Azure or only EntraID.

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

### -CsvPath

Write the findings to this CSV file.

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

Return the findings without showing the view.

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

Show the view and also return the findings.

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

Only Azure resources in these resource groups.

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

### -ResourceType

Only Azure resources of these types; wildcards work.

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

### -Severity

Only these severities (High, Medium, Low).

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

### -SignInDays

How many days of sign-ins to read for legacy protocols. Default 7.

```yaml
Type: System.Int32
DefaultValue: 7
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

### -SkipAppService

Don't read the App Service publishing credential policies (one call
per app).

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

### -SkipEntra

Don't read Entra ID (Microsoft Graph): Azure resources only.

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
DefaultValue: "'Legacy authentication'"
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.LegacyAuthentication

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACLegacyAuthentication.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
