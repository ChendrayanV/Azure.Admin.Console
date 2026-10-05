---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Connect-AAC.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Connect-AAC
---

# Connect-AAC

## SYNOPSIS

Signs in to Azure - in the browser (OAuth 2.0 Authorization Code flow with PKCE and a loopback redirect), with a device code, as a service principal (client secret or certificate) or with a managed identity - no Az or Microsoft.Graph module, and no app registration required by default.

## SYNTAX

### Browser (Default)

```
Connect-AAC [-TenantId <string>] [-ClientId <string>] [-Scope <string[]>] [-TimeoutSeconds <int>]
 [-PassThru]
```

### CertificateStore

```
Connect-AAC -TenantId <string> -ClientId <string> -CertificateThumbprint <string> [-PassThru]
```

### CertificateFile

```
Connect-AAC -TenantId <string> -ClientId <string> -CertificatePath <string>
 [-CertificatePassword <securestring>] [-PassThru]
```

### ClientSecret

```
Connect-AAC -TenantId <string> -ClientId <string> -ClientSecret <securestring> [-PassThru]
```

### DeviceCode

```
Connect-AAC -DeviceCode [-TenantId <string>] [-ClientId <string>] [-Scope <string[]>]
 [-TimeoutSeconds <int>] [-PassThru]
```

### Identity

```
Connect-AAC -Identity [-ClientId <string>] [-PassThru]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Without a sign-in option, the browser (below). -DeviceCode shows a
code to enter at https://microsoft.com/devicelogin on any device.
-ClientSecret, -CertificatePath and -CertificateThumbprint sign in
as a service principal (-ClientId, -TenantId), and -Identity with
the managed identity of where this runs (Azure Automation, a VM, App
Service): no user, no refresh token - a new token is asked for when
one runs out.

The browser sign-in:
Opens your default browser to Microsoft's sign-in page, receives the
redirect on a one-shot local HTTP listener (http://localhost:\<port\>/),
and exchanges the resulting authorization code for tokens directly
against the v2.0 token endpoint over REST - using a PKCE code_verifier /
code_challenge pair (RFC 7636) instead of a client secret, which is what
makes this safe for a public desktop tool with no back-end to keep a
secret in.

By default this uses Azure's well-known public client ID for the Azure
CLI (04b07795-8ddb-461a-bbee-02f9e1bf7b46), which is pre-consented in
every Entra ID tenant, so sign-in works immediately with no app
registration of your own. Pass -ClientId to use your own App Registration
instead (create it with the "Mobile and desktop applications" platform
and a http://localhost redirect URI).

The resulting session (access token, refresh token, expiry, signed-in
account and tenant) is kept in this module's memory for the rest of the
PowerShell session and used automatically by every command, such as
Invoke-AACPSRule. It is not written to disk.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
```

Signs in interactively using the well-known Azure CLI client ID.

### Example 2

```powershell
Connect-AAC -TenantId 'contoso.onmicrosoft.com' -ClientId '11111111-1111-1111-1111-111111111111'
```

Signs in to a specific tenant using your own App Registration.

### Example 3

```powershell
Connect-AAC -DeviceCode
```

Signs in with a code entered at https://microsoft.com/devicelogin.

### Example 4

```powershell
Connect-AAC -TenantId 'contoso.onmicrosoft.com' -ClientId '11111111-1111-1111-1111-111111111111' -ClientSecret (Read-Host -AsSecureString 'Secret')
```

Signs in as a service principal with its client secret.

### Example 5

```powershell
Connect-AAC -TenantId 'contoso.onmicrosoft.com' -ClientId '11111111-1111-1111-1111-111111111111' -CertificatePath .\sp-reader.pfx -CertificatePassword $password
```

Signs in as a service principal with a certificate.

### Example 6

```powershell
Connect-AAC -Identity
```

In an Azure Automation runbook: signs in with the account's system-assigned managed identity.

## PARAMETERS

### -CertificatePassword

The .pfx file's password.

```yaml
Type: System.Security.SecureString
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: CertificateFile
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -CertificatePath

Sign in as a service principal (-ClientId, -TenantId) with a
certificate: a .pfx file with the private key (-CertificatePassword
if it has one). The token request is signed with the key; the key
isn't sent anywhere.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: CertificateFile
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -CertificateThumbprint

Sign in as a service principal with a certificate from the current
user's (or the machine's) certificate store, by its thumbprint.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: CertificateStore
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ClientId

The Entra ID application (client) ID to sign in as. Defaults to the
well-known Azure CLI public client ID so this works without an app
registration; see the Description for when to supply your own. An
App Registration of your own needs delegated permissions for Azure
Service Management (user_impersonation) and, for
Invoke-AACApplicationInsightQuery, the Log Analytics API and the
Application Insights API (Data.Read).

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Identity
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: CertificateStore
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: CertificateFile
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: ClientSecret
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: DeviceCode
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: Browser
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ClientSecret

Sign in as a service principal (-ClientId, -TenantId) with its client
secret - for pipelines and schedules. No user, no browser; the
service principal needs Reader on what is read.

```yaml
Type: System.Security.SecureString
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: ClientSecret
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -DeviceCode

Sign in with a code instead of a browser on this machine: the code
is shown with the address to enter it at
(https://microsoft.com/devicelogin), on any device. For SSH,
containers and Cloud Shell.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: DeviceCode
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Identity

Sign in with the managed identity of where this runs - an Azure
Automation account (as a runbook), a VM, App Service or Functions.
-ClientId picks a user-assigned identity; without it, the
system-assigned one.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Identity
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

Also returns the session summary object, in addition to rendering it.

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

### -Scope

The OAuth scopes to request. Defaults to Azure Resource Manager's
default scope (https://management.azure.com/.default) plus
offline_access (so a refresh token is issued) and openid/profile (so
the signed-in account's name can be shown).

```yaml
Type: System.String[]
DefaultValue: "@('https://management.azure.com/.default', 'offline_access', 'openid', 'profile')"
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: DeviceCode
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: Browser
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -TenantId

The tenant to sign in to: a tenant ID (GUID), a verified domain name, or
one of Microsoft's multi-tenant aliases 'organizations' (default, any
Entra ID tenant), 'common' (also allows personal Microsoft accounts) or
'consumers'.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: CertificateStore
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: CertificateFile
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: ClientSecret
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: DeviceCode
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: Browser
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -TimeoutSeconds

How long to wait for you to complete sign-in in the browser before giving
up. Defaults to 180 seconds.

```yaml
Type: System.Int32
DefaultValue: 180
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: DeviceCode
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: Browser
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

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Connect-AAC.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
