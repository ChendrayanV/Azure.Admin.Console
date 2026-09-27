---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Disconnect-AAC.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Disconnect-AAC
---

# Disconnect-AAC

## SYNOPSIS

Clears the current Azure sign-in from memory.

## SYNTAX

### __AllParameterSets

```
Disconnect-AAC
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Discards the cached access token, refresh token and account/tenant info
that Connect-AAC stored. Nothing was ever written to disk, so this simply
forgets the in-memory session; commands that need Azure access (like
Invoke-AACPSRule) will require Connect-AAC again afterwards.

## EXAMPLES

### Example 1

```powershell
Disconnect-AAC
```

## PARAMETERS

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Disconnect-AAC.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
