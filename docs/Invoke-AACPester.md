# Invoke-AACPester

[Azure.Admin.Console](Azure.Admin.Console.md) · [about_Azure.Admin.Console](about_Azure.Admin.Console.md)

## Synopsis

Runs any Pester v5 tests and renders the results with Spectre.Console: a table of every test, a tree grouped by file and block with the failures called out, a pass/fail chart, a summary and a banner.

## Syntax

```powershell
Invoke-AACPester [[-Path] <string[]>] [-Tag <string[]>] [-ExcludeTag <string[]>] [-TestName <string[]>] [-Data <hashtable>] [-CI] [-OutputPath <string>] [-NoSpinner] [-NoPaging] [-FailedOnly] [-PdfPath <string>] [-PassThru] [<CommonParameters>]
```

## Description

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

-PdfPath also saves the results as an A4 PDF report - a summary
with the verdict, pass/fail counts per check, and every test with
its failure message - honouring -FailedOnly.

## Examples

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
Invoke-AACPester -Data @{ SubscriptionId = '00000000-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111111' }
```

Runs the bundled estate check against those two subscriptions only.

### Example 4

```powershell
Invoke-AACPester -Path .\Tests -Tag 'Smoke' -ExcludeTag 'Slow'
```

Runs only the tests tagged Smoke, leaving out any tagged Slow.

### Example 5

```powershell
Invoke-AACPester -Path .\Tests -CI -OutputPath .\out\results.xml
```

Runs the tests, shows the report and writes JUnit results for the pipeline.

### Example 6

```powershell
Connect-AAC
Invoke-AACPester -FailedOnly -Data @{ ResourceType = 'microsoft.network/*' }
```

Checks only networking resources and lists only what failed.

### Example 7

```powershell
Invoke-AACPester -PdfPath .\out\AzureEstate.pdf
```

Shows the report and saves it as a PDF as well.

### Example 8

```powershell
$result = Invoke-AACPester -Path .\Tests -PassThru
if ($result.FailedCount -gt 0) { exit 1 }
```

Fails a build script when any test fails.

## Parameters

### -Path

One or more test files or folders. Folders are searched recursively
for \*.Tests.ps1 files. Defaults to this module's bundled Checks
folder (AzureEstate.Tests.ps1).

| | |
|---|---|
| Type | `String[]` |
| Required | No |
| Position | 0 |
| Default value | `(Join-Path -Path $script:AACModuleRoot -ChildPath 'Checks')` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -Tag

Only run tests (or blocks) with at least one of these tags.

| | |
|---|---|
| Type | `String[]` |
| Required | No |
| Position | Named |
| Default value | `None` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -ExcludeTag

Skip tests (or blocks) with any of these tags.

| | |
|---|---|
| Type | `String[]` |
| Required | No |
| Position | Named |
| Default value | `None` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -TestName

Only run tests whose full name (Describe, Context and It joined with
dots) matches one of these wildcard patterns. For data-driven tests
(-ForEach), Pester matches the name template, e.g. "\<Name\>", not the
expanded value, so filter those with -Tag instead.

| | |
|---|---|
| Type | `String[]` |
| Required | No |
| Position | Named |
| Default value | `None` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -Data

Values for the test files' param() blocks.

| | |
|---|---|
| Type | `Hashtable` |
| Required | No |
| Position | Named |
| Default value | `None` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -CI

Also write a JUnit XML result file for CI pipelines.

| | |
|---|---|
| Type | `SwitchParameter` |
| Required | No |
| Position | Named |
| Default value | `False` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -OutputPath

Where -CI writes the JUnit file. Defaults to TestResults.xml in the
current directory.

| | |
|---|---|
| Type | `String` |
| Required | No |
| Position | Named |
| Default value | `(Join-Path -Path (Get-Location) -ChildPath 'TestResults.xml')` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -NoSpinner

Run Pester without the spinner, for tests that draw their own
Spectre.Console live output.

| | |
|---|---|
| Type | `SwitchParameter` |
| Required | No |
| Position | Named |
| Default value | `False` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -NoPaging

Show the whole report at once instead of a page at a time.

| | |
|---|---|
| Type | `SwitchParameter` |
| Required | No |
| Position | Named |
| Default value | `False` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -FailedOnly

List only failed tests in the report (and the -PdfPath PDF). The
counts, summary and verdict still cover every test, and the -PassThru
result and -CI file are unchanged.

| | |
|---|---|
| Type | `SwitchParameter` |
| Required | No |
| Position | Named |
| Default value | `False` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -PdfPath

Also write the results to this PDF file. Needs Windows and PowerShell
7.4 or later.

| | |
|---|---|
| Type | `String` |
| Required | No |
| Position | Named |
| Default value | `None` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -PassThru

Also return the Pester result object, in addition to rendering the report.

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

## Outputs

Pester.Run (with -PassThru)
