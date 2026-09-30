---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACPSRule.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Invoke-AACPSRule
---

# Invoke-AACPSRule

## SYNOPSIS

Checks your live Azure estate with PSRule for Azure - its Azure Well-Architected Framework rules, the module's own rules and your custom rules - with a console view, objects, and CSV, PDF and interactive HTML reports.

## SYNTAX

### __AllParameterSets

```
Invoke-AACPSRule [[-SubscriptionId] <string[]>] [[-ResourceType] <string[]>] [[-Rule] <string[]>]
 [[-ExcludeRule] <string[]>] [[-Baseline] <string>] [[-Configuration] <hashtable>]
 [[-RulePath] <string[]>] [[-CsvPath] <string>] [[-PdfPath] <string>] [[-HtmlPath] <string>]
 [[-Title] <string>] [-NoExpand] [-FailedOnly] [-PassThru] [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Runs PSRule for Azure (the PSRule.Rules.Azure module, 500+ rules)
against every resource, resource group and subscription the
signed-in account can see, or those in -SubscriptionId. No Az modules:
the data PSRule needs - what Export-AzRuleData would export - is read
with the Connect-AAC sign-in, from Azure Resource Graph plus the child
settings PSRule's rules look at (storage blob services, SQL auditing,
Key Vault diagnostic settings, App Service config, API Management
APIs and policies, ...). Reader on the subscriptions is enough.

The rules that run:

```text
  PSRule for Azure    every rule of the installed PSRule.Rules.Azure
                      (-Baseline picks one of its baselines)
  Azure.Admin.Console the module's own AAC.* rules (PSRule\Rules):
                      required tags on resources and resource
                      groups and allowed tag values - the tags
                      named in -Configuration or in
                      Get-AACTagDefault (PSRule\Rules\AAC.Tags.Rule.ps1);
                      with none named they check nothing, and the
                      view says so - and naming conventions (on by default: the
                      Cloud Adoption Framework abbreviations, or
                      AAC_NAMING_PATTERNS)
  custom              your own PSRule rule files (*.Rule.ps1,
                      *.Rule.yaml, *.Rule.jsonc) from -RulePath
```

-Rule runs only the rules named, and -ExcludeRule leaves rules out;
both take names or wildcards ('Azure.Storage.\*', 'AAC.\*').
-Configuration passes settings to all of them: PSRule for Azure's
AZURE_\* options and the AAC_\* settings.

What you get depends on where the command runs:

```text
  at the prompt    a Spectre.Console view: tiles (objects, rules,
                   passed, failed, pass rate), failures by pillar,
                   then a table per pillar with each failing rule,
                   the resources it failed on and why - a page at a
                   time (-NoPaging turns that off)
  piped onward     the AAC.PSRuleResult objects, with no view
  -PassThru        the view and the objects
  -NoDisplay       the objects only
```

Exports:

```text
  -CsvPath    one row per rule and resource (-FailedOnly: failures
              only)
  -PdfPath    a landscape A4 report: summary and verdict, results
              by pillar, the failed rules, then every failing
              resource per rule with the rule's recommendation and
              documentation link
  -HtmlPath   a self-contained, interactive HTML report: clickable
              tiles and charts, and every result in one table that
              opens on the failures, grouped by rule, with search,
              filters, portal and documentation links and a CSV
              download
```

When any of them is given, the console shows only the progress and
the files written; add -PassThru for the objects too.

PSRule runs in a pwsh process of its own, so its YamlDotNet.dll
never meets the different versions platyPS, powershell-yaml or Az.Aks
may have loaded in this session. A rule that can't evaluate a
resource is reported for that resource ("could not evaluate");
every other rule still runs. Settings Reader can't read are listed
as warnings, as rules using them may be wrong for those resources.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Invoke-AACPSRule
```

Checks every resource you can see and shows what failed.

### Example 2

```powershell
Invoke-AACPSRule -SubscriptionId '00000000-0000-0000-0000-000000000000' -HtmlPath .\out\PSRule.html
```

One subscription, as an interactive HTML report.

### Example 3

```powershell
Invoke-AACPSRule -CsvPath .\out\PSRule.csv -PdfPath .\out\PSRule.pdf -FailedOnly
```

The failures as a CSV file and a PDF report.

### Example 4

```powershell
Invoke-AACPSRule -Rule 'Azure.Storage.*', 'Azure.KeyVault.*' -ExcludeRule 'Azure.Storage.Name'
```

Only the storage and Key Vault rules, without the storage naming rule.

### Example 5

```powershell
Invoke-AACPSRule -Baseline 'Azure.Pillar.Security'
```

Only PSRule for Azure's security pillar baseline.

### Example 6

```powershell
Invoke-AACPSRule -Configuration @{ AAC_REQUIRED_TAGS = @('Owner', 'CostCenter'); AAC_ALLOWED_TAG_VALUES = @{ Environment = @('prod', 'test', 'dev') }; AZURE_RESOURCE_ALLOWED_LOCATIONS = @('uksouth', 'ukwest') }
```

Adds the module's tag rules and PSRule for Azure's allowed regions.

### Example 7

```powershell
Invoke-AACPSRule -Rule 'AAC.Resource.Naming'
```

Checks names against the Cloud Adoption Framework abbreviations, reading only the types it checks.

### Example 8

```powershell
Invoke-AACPSRule -RulePath .\MyRules -ExcludeRule 'AAC.*'
```

Runs your own rules from .\MyRules with PSRule for Azure's, without the module's.

### Example 9

```powershell
Invoke-AACPSRule -FailedOnly | Group-Object RuleName | Sort-Object Count -Descending | Select-Object -First 10 Count, Name
```

The ten rules that fail most.

## PARAMETERS

### -Baseline

A PSRule for Azure baseline, e.g. 'Azure.Pillar.Security' or
'Azure.GA_2024_12'. Defaults to the module's default baseline.

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

### -Configuration

Settings for the rules: PSRule for Azure's options (e.g.
AZURE_RESOURCE_ALLOWED_LOCATIONS) and the AAC_\* settings of the
module's rules (AAC_REQUIRED_TAGS, AAC_ALLOWED_TAG_VALUES), or your
custom rules' own.

```yaml
Type: System.Collections.Hashtable
DefaultValue: '@{}'
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

### -CsvPath

Also write the results to this CSV file. An existing file is
overwritten; missing folders are created.

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

### -ExcludeRule

Leave out these rules: names or wildcards, e.g. 'Azure.Resource.UseTags'
or 'AAC.\*'.

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

### -FailedOnly

Return and export only the failures (and rules that couldn't be
evaluated). The counts still cover every result.

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

### -HtmlPath

Also write an interactive HTML report to this file.

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

### -NoDisplay

Return the objects without showing the view.

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

### -NoExpand

Read only what Resource Graph returns - names, types, tags and
properties - not the child settings PSRule for Azure's rules need
(diagnostic settings, blob services, API Management APIs, ...: one
to hundreds of calls per resource). For your own -RulePath rules
that look only at those fields. Runs of only the module's AAC.\*
rules do this without asking.

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

Show the view and also return the AAC.PSRuleResult objects.

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

Also write a PDF report to this file. Needs Windows and PowerShell
7.4 or later.

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

### -ResourceType

Only check resources of these types, e.g. 'microsoft.storage/\*'.
Case-insensitive; wildcards work. Resource groups and subscriptions
are checked only when no type is given.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: true
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

### -Rule

Only run these rules: names or wildcards, e.g. 'Azure.KeyVault.\*' or
'AAC.Resource.Naming' - not file paths (use -RulePath for rule
files). A -Rule that matches no rule is an error. With only the
module's AAC.\* rules, just names, types and tags are read - and for
AAC.Resource.Naming alone, just the types it checks.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: true
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

### -RulePath

Custom PSRule rule files, or folders of them (\*.Rule.ps1,
\*.Rule.yaml, \*.Rule.jsonc), to run with the others. The module's own
AAC.\* rules always load; don't pass them here.

```yaml
Type: System.String[]
DefaultValue: None
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

### -SubscriptionId

Only check these subscriptions. Defaults to every subscription the
signed-in account can see.

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

The PDF and HTML report's title. Defaults to 'PSRule for Azure'.

```yaml
Type: System.String
DefaultValue: "'PSRule for Azure'"
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

### AAC.PSRuleResult (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACPSRule.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
