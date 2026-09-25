# Connect-AAC

[Azure.Admin.Console](Azure.Admin.Console.md) · [about_Azure.Admin.Console](about_Azure.Admin.Console.md)

## Synopsis

Signs in to Azure interactively using the OAuth 2.0 Authorization Code flow with PKCE and a loopback redirect - no Az or Microsoft.Graph module, and no app registration required by default.

## Syntax

```powershell
Connect-AAC [[-TenantId] <string>] [[-ClientId] <string>] [[-Scope] <string[]>] [[-TimeoutSeconds] <int>] [-PassThru] [<CommonParameters>]
```

## Description

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
PowerShell session and used automatically by commands like
Invoke-AACPester. It is not written to disk.

## Examples

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

## Parameters

### -TenantId

The tenant to sign in to: a tenant ID (GUID), a verified domain name, or
one of Microsoft's multi-tenant aliases 'organizations' (default, any
Entra ID tenant), 'common' (also allows personal Microsoft accounts) or
'consumers'.

| | |
|---|---|
| Type | `String` |
| Required | No |
| Position | 0 |
| Default value | `'organizations'` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -ClientId

The Entra ID application (client) ID to sign in as. Defaults to the
well-known Azure CLI public client ID so this works without an app
registration; see the Description for when to supply your own.

| | |
|---|---|
| Type | `String` |
| Required | No |
| Position | 1 |
| Default value | `'04b07795-8ddb-461a-bbee-02f9e1bf7b46'` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -Scope

The OAuth scopes to request. Defaults to Azure Resource Manager's
default scope (https://management.azure.com/.default) plus
offline_access (so a refresh token is issued) and openid/profile (so
the signed-in account's name can be shown).

| | |
|---|---|
| Type | `String[]` |
| Required | No |
| Position | 2 |
| Default value | `@('https://management.azure.com/.default', 'offline_access', 'openid', 'profile')` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -TimeoutSeconds

How long to wait for you to complete sign-in in the browser before giving
up. Defaults to 180 seconds.

| | |
|---|---|
| Type | `Int32` |
| Required | No |
| Position | 3 |
| Default value | `180` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -PassThru

Also returns the session summary object, in addition to rendering it.

| | |
|---|---|
| Type | `SwitchParameter` |
| Required | No |
| Position | Named |
| Default value | `False` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### CommonParameters

This command supports the common parameters (`-Verbose`, `-ErrorAction`, `-WarningAction` and so on). See [about_CommonParameters](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters).
