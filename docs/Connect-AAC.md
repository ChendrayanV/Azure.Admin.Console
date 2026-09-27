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

Signs in to Azure interactively using the OAuth 2.0 Authorization Code flow with PKCE and a loopback redirect - no Az or Microsoft.Graph module, and no app registration required by default.

## SYNTAX

### __AllParameterSets

```
Connect-AAC [[-TenantId] <string>] [[-ClientId] <string>] [[-Scope] <string[]>]
 [[-TimeoutSeconds] <int>] [-PassThru]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

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

## PARAMETERS

### -ClientId

The Entra ID application (client) ID to sign in as. Defaults to the
well-known Azure CLI public client ID so this works without an app
registration; see the Description for when to supply your own.

```yaml
Type: System.String
DefaultValue: "'04b07795-8ddb-461a-bbee-02f9e1bf7b46'"
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

### -TenantId

The tenant to sign in to: a tenant ID (GUID), a verified domain name, or
one of Microsoft's multi-tenant aliases 'organizations' (default, any
Entra ID tenant), 'common' (also allows personal Microsoft accounts) or
'consumers'.

```yaml
Type: System.String
DefaultValue: "'organizations'"
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

### -TimeoutSeconds

How long to wait for you to complete sign-in in the browser before giving
up. Defaults to 180 seconds.

```yaml
Type: System.Int32
DefaultValue: 180
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
