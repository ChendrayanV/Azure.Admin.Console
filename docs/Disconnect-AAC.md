# Disconnect-AAC

[Azure.Admin.Console](Azure.Admin.Console.md) · [about_Azure.Admin.Console](about_Azure.Admin.Console.md)

## Synopsis

Clears the current Azure sign-in from memory.

## Syntax

```powershell
Disconnect-AAC [<CommonParameters>]
```

## Description

Discards the cached access token, refresh token and account/tenant info
that Connect-AAC stored. Nothing was ever written to disk, so this simply
forgets the in-memory session; commands that need Azure access (like
Invoke-AACPester) will require Connect-AAC again afterwards.

## Examples

### Example 1

```powershell
Disconnect-AAC
```
