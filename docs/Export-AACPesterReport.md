# Export-AACPesterReport

[Azure.Admin.Console](Azure.Admin.Console.md) · [about_Azure.Admin.Console](about_Azure.Admin.Console.md)

## Synopsis

Writes a Pester v5 result as a PDF report: a summary page, pass/fail counts per check, and every test result with the reason for each failure.

## Syntax

```powershell
Export-AACPesterReport [-PesterResult] <Object> [-Path] <string> [[-Title] <string>] [[-Detail] <IDictionary>] [-FailedOnly] [<CommonParameters>]
```

## Description

Takes the result object that Invoke-AACPester -PassThru (or
Invoke-Pester -PassThru) returns and renders an A4 PDF:

```text
  1. Summary: title, when and where it ran (with the Azure account
     and tenant when Connect-AAC is signed in), a PASSED/FAILED
     verdict, total/passed/failed/skipped/pass-rate tiles and a
     proportion bar.
  2. Results by check: one row per Describe/Context with its test,
     passed, failed and skipped counts - the quickest way to see
     which rules fail most.
  3. Test results: one table per test file and Describe block, each
     test marked PASS, FAIL or SKIP, with the failure message or skip
     reason directly under the test it belongs to.
```

With -FailedOnly the results tables list only failed tests; the
summary and per-check counts still cover every test.

The PDF is drawn with PDFsharp + MigraDoc (MIT), vendored in
lib\pdf and loaded only when a report is exported, after every DLL
has been checked against a pinned SHA-256 hash. Needs Windows (for
its fonts) and PowerShell 7.4 or later.

## Examples

### Example 1

```powershell
$result = Invoke-AACPester -PassThru
Export-AACPesterReport -PesterResult $result -Path .\out\TestReport.pdf
```

Runs the bundled Azure estate check, then writes the full report as a PDF.

### Example 2

```powershell
$result | Export-AACPesterReport -Path .\EstateFailures.pdf -FailedOnly -Title 'Azure estate - failures'
A shorter PDF listing only what failed.
```

## Parameters

### -PesterResult

The Pester.Run object from Invoke-AACPester -PassThru or
Invoke-Pester -PassThru.

| | |
|---|---|
| Type | `Object` |
| Required | Yes |
| Position | 0 |
| Default value | `None` |
| Accepts pipeline input | ByValue |
| Accepts wildcards | No |

### -Path

Where to write the PDF. An existing file is overwritten; missing
folders are created.

| | |
|---|---|
| Type | `String` |
| Required | Yes |
| Position | 1 |
| Default value | `None` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -Title

The report's title. Defaults to 'Azure Admin Console test report'.

| | |
|---|---|
| Type | `String` |
| Required | No |
| Position | 2 |
| Default value | `'Azure Admin Console test report'` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -Detail

Extra name/value lines for the summary page, such as the test path
and filters used. Invoke-AACPester -PdfPath fills this in.

| | |
|---|---|
| Type | `IDictionary` |
| Required | No |
| Position | 3 |
| Default value | `None` |
| Accepts pipeline input | No |
| Accepts wildcards | No |

### -FailedOnly

List only failed tests in the results tables.

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

System.IO.FileInfo - the PDF written.
