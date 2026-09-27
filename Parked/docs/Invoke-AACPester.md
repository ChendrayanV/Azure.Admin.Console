---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACPester.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Invoke-AACPester
---

# Invoke-AACPester

## SYNOPSIS

Runs any Pester v5 tests and renders the results with Spectre.Console: a table of every test, a tree grouped by file and block with the failures called out, a pass/fail chart, a summary and a banner.

## SYNTAX

### __AllParameterSets

```
Invoke-AACPester [[-Path] <string[]>] [-PSRule] [-SubscriptionId <string[]>] [-Tag <string[]>]
 [-ExcludeTag <string[]>] [-TestName <string[]>] [-Data <hashtable>] [-CI] [-OutputPath <string>]
 [-NoSpinner] [-NoPaging] [-FailedOnly] [-PdfPath <string>] [-HtmlPath <string>] [-PassThru]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

A generic front end to Invoke-Pester. Point it at any test file or
folder - this module's bundled Checks folder (the Azure estate
check) is only the default. You
get back a normal Pester result object (with -PassThru) that CI
already understands, and a readable report for whoever is watching
the console.

-Data passes values to the test files' own param() blocks, e.g. the
subscriptions to check in AzureEstate.Tests.ps1. Each file is given only
the values its param() block declares, so -Data works on a whole
folder: files that don't take a value simply don't get it.

While Pester runs, a Spectre.Console progress display shows what is
happening: a line for the Pester run, and lines of their own for test
files that report progress - the bundled estate check shows reading
the estate and evaluating its rules, rule by rule, with a percentage
and elapsed time. PowerShell's own progress bars and the REST calls'
verbose output are kept out of the way. Spectre.Console allows only
one live display at a time, so if the tests themselves draw a Spectre
spinner, progress bar or live display, run with -NoSpinner.

Tests that talk to Azure use the Connect-AAC sign-in from this session.
Run Connect-AAC first; the bundled Azure test reports Skipped without it.

A report longer than the terminal is shown one screen at a time:
press any key for the next page, or A to show the rest. Paging is
skipped automatically when output is redirected or with -CI, and can
be turned off with -NoPaging.

-PSRule runs PSRule for Azure (the PSRule.Rules.Azure module, 500+
rules following the Azure Well-Architected Framework) against the
live estate, with each result as a test: grouped by pillar, then
rule, then resource. The data it needs is read with the Connect-AAC
sign-in - no Az modules. See PSRuleChecks\PSRuleForAzure.Tests.ps1
for its -Data settings (Rule, ExcludeRule, Baseline, Configuration).

-PdfPath also saves the results as an A4 PDF report - a summary
with the verdict, pass/fail counts per check, and every test with
its failure message - honouring -FailedOnly.

-HtmlPath saves them as a single, self-contained HTML page to open
in any browser: the verdict and totals, the checks that fail most,
and every result - searchable, filterable by outcome, grouped by
check or by resource, with links to each resource in the Azure
portal and to each PSRule rule's documentation. It works offline
and can be attached to a ticket or published as a pipeline artifact.

With -PdfPath or -HtmlPath the console report isn't shown: the
console keeps the progress (with the pass/fail counts) and the files
written, and the report is in the files.

## EXAMPLES

### Example 1

```powershell
Invoke-AACPester -Path .\Tests
```

Runs every \*.Tests.ps1 file under .\Tests and shows the report.

### Example 2

```powershell
Connect-AAC
Invoke-AACPester -Tag 'Governance' -Data @{ AllowedLocation = 'uksouth', 'global' }
```

Runs the bundled estate check's governance rules, accepting resources in UK South or the "global" location.

### Example 3

```powershell
Connect-AAC
Invoke-AACPester -SubscriptionId '00000000-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111111'
```

Runs the bundled estate check against those two subscriptions only.

### Example 4

```powershell
Invoke-AACPester -PSRule -SubscriptionId '00000000-0000-0000-0000-000000000000' -HtmlPath .\out\Prod.html
```

Runs PSRule for Azure against one subscription, with an HTML report.

### Example 5

```powershell
Invoke-AACPester -Path .\Tests -Tag 'Smoke' -ExcludeTag 'Slow'
```

Runs only the tests tagged Smoke, leaving out any tagged Slow.

### Example 6

```powershell
Invoke-AACPester -Path .\Tests -CI -OutputPath .\out\results.xml
```

Runs the tests, shows the report and writes JUnit results for the pipeline.

### Example 7

```powershell
Connect-AAC
Invoke-AACPester -FailedOnly -Data @{ ResourceType = 'microsoft.network/*' }
```

Checks only networking resources and lists only what failed.

### Example 8

```powershell
Invoke-AACPester -PdfPath .\out\AzureEstate.pdf
```

Shows the report and saves it as a PDF as well.

### Example 9

```powershell
Connect-AAC
Invoke-AACPester -PSRule -HtmlPath .\out\PSRule.html
```

Runs every PSRule for Azure rule against the estate and saves a clickable HTML report.

### Example 10

```powershell
Invoke-AACPester -PSRule -Tag Security -FailedOnly -Data @{ Configuration = @{ AZURE_RESOURCE_ALLOWED_LOCATIONS = @('uksouth', 'ukwest') } }
```

Runs PSRule for Azure's security rules, with the regions resources may use, listing only failures.

### Example 11

```powershell
$result = Invoke-AACPester -Path .\Tests -PassThru
if ($result.FailedCount -gt 0) { exit 1 }
```

Fails a build script when any test fails.

## PARAMETERS

### -CI

Also write a JUnit XML result file for CI pipelines.

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

### -Data

Values for the test files' param() blocks.

```yaml
Type: System.Collections.Hashtable
DefaultValue: None
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

### -ExcludeTag

Skip tests (or blocks) with any of these tags.

```yaml
Type: System.String[]
DefaultValue: None
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

### -FailedOnly

List only failed tests in the report (and the -PdfPath PDF). The
counts, summary and verdict still cover every test, and the -PassThru
result and -CI file are unchanged.

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

Also write the results to this self-contained HTML file (honouring
-FailedOnly).

```yaml
Type: System.String
DefaultValue: None
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

Show the whole report at once instead of a page at a time.

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

### -NoSpinner

Run Pester without the spinner, for tests that draw their own
Spectre.Console live output.

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

### -OutputPath

Where -CI writes the JUnit file. Defaults to TestResults.xml in the
current directory.

```yaml
Type: System.String
DefaultValue: (Join-Path -Path (Get-Location) -ChildPath 'TestResults.xml')
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

Also return the Pester result object, in addition to rendering the report.

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

### -Path

One or more test files or folders. Folders are searched recursively
for \*.Tests.ps1 files. Defaults to this module's bundled Checks
folder (AzureEstate.Tests.ps1), or to PSRuleChecks with -PSRule.

```yaml
Type: System.String[]
DefaultValue: (Join-Path -Path $script:AACModuleRoot -ChildPath 'Checks')
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

### -PdfPath

Also write the results to this PDF file. Needs Windows and PowerShell
7.4 or later.

```yaml
Type: System.String
DefaultValue: None
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

### -PSRule

Run PSRule for Azure against the live estate. Needs a Connect-AAC
sign-in; the PSRule.Rules.Azure module is installed with this one. Without -Path it replaces the bundled estate
check; with -Path it runs as well as those tests.

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

Only check these subscriptions (IDs). Defaults to every subscription
the signed-in account can see. It is passed to every test file that
declares a SubscriptionId parameter - the bundled estate check and
the PSRule for Azure check both do - the same as
-Data @{ SubscriptionId = ... }.

```yaml
Type: System.String[]
DefaultValue: None
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

### -Tag

Only run tests (or blocks) with at least one of these tags.

```yaml
Type: System.String[]
DefaultValue: None
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

### -TestName

Only run tests whose full name (Describe, Context and It joined with
dots) matches one of these wildcard patterns. For data-driven tests
(-ForEach), Pester matches the name template, e.g. "\<Name\>", not the
expanded value, so filter those with -Tag instead.

```yaml
Type: System.String[]
DefaultValue: None
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

### Pester.Run (with -PassThru)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Invoke-AACPester.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
