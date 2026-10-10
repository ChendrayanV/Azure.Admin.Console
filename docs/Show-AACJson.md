---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Show-AACJson.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Show-AACJson
---

# Show-AACJson

## SYNOPSIS

Shows JSON - or any PowerShell object, as JSON - at the console, indented and syntax-coloured in a panel, so an ARM template, a REST response or a resource's properties are easy to read.

## SYNTAX

### __AllParameterSets

```
Show-AACJson [-InputObject] <Object> [-Title <string>] [-Depth <int>] [-PassThru] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Pipe in JSON text (an API response, a template file's content) or
objects (Resource Graph rows, Invoke-RestMethod results, this
module's output): it's shown indented, with property names, strings,
numbers, true/false and null each in their own colour:

```text
  ╭─ storage account ───────────────────────────────╮
  │ {                                               │
  │   "name": "stcontoso",                          │
  │   "location": "westeurope",                     │
  │   "properties": {                               │
  │     "minimumTlsVersion": "TLS1_2",              │
  │     "allowBlobPublicAccess": false              │
  │   }                                             │
  │ }                                               │
  ╰─────────────────────────────────────────────────╯
```

Several objects piped in are shown as one JSON array. JSON text that
isn't valid is shown as it is, with a warning. Long JSON is paged
(any key for the next page, A for the rest; -NoPaging turns it off).
Nothing is sent anywhere: it only formats what it's given.

## EXAMPLES

### Example 1

```powershell
Get-Content .\azuredeploy.json -Raw | Show-AACJson -Title 'ARM template'
```

An ARM template, coloured.

### Example 2

```powershell
Invoke-RestMethod -Uri $uri -Headers $headers | Show-AACJson -Title 'Response'
A REST response, as JSON.
```

### Example 3

```powershell
Show-AACDashboard -NoDisplay | Select-Object Status, Headline, Health | Show-AACJson
```

Part of the dashboard object, as JSON.

## PARAMETERS

### -Depth

How deep objects are converted to JSON (default 10). Ignored for JSON
text.

```yaml
Type: System.Int32
DefaultValue: 10
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

### -InputObject

JSON text, or objects to show as JSON.

```yaml
Type: System.Object
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: true
  ValueFromPipeline: true
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -NoPaging

Show it all at once instead of a page at a time.

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

Also pass the input on, unchanged.

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

The panel's title. Defaults to 'JSON'.

```yaml
Type: System.String
DefaultValue: "'JSON'"
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### The input, with -PassThru.

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Show-AACJson.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
