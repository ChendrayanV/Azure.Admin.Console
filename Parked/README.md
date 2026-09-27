# Parked: Invoke-AACPester

`Invoke-AACPester` is set aside for now. It isn't exported, loaded or packaged,
and its tests don't run. PSRule for Azure checks moved to their own command,
`Invoke-AACPSRule`.

What's here, in the folders it came from:

| Path | What it is |
|---|---|
| `Public/Invoke-AACPester.ps1` | The command: runs Pester v5 tests with a progress display, a console report, and PDF and HTML reports |
| `Private/Write-AACPesterReport.ps1` | The console report |
| `Private/Write-AACPesterReportPdf.ps1` | The `-PdfPath` report |
| `Private/Write-AACPesterReportHtml.ps1`, `Private/PesterReport.html` | The `-HtmlPath` report and its template |
| `Private/Get-AACPesterOutcomeCount.ps1` | Counts outcomes for the reports |
| `Checks/AzureEstate.Tests.ps1` | The bundled estate check: 85 read-only checks, 75 following PSRule for Azure |
| `PSRuleChecks/PSRuleForAzure.Tests.ps1` | The old `Invoke-AACPester -PSRule` check: PSRule for Azure results as Pester tests |
| `Tests/InvokePester.Tests.ps1` | Its unit tests |
| `docs/Invoke-AACPester.md` | Its help page |
| `Stale/` | Obsolete files from before the parking (see below) |

## To bring it back

1. Move each file back to the same path at the repository root. For example,
   `Parked/Public/Invoke-AACPester.ps1` goes to `Public/Invoke-AACPester.ps1`.
2. Add `'Invoke-AACPester'` to `FunctionsToExport` in `Azure.Admin.Console.psd1`,
   and Pester (`@{ ModuleName = 'Pester'; ModuleVersion = '5.7.1' }`) to
   `RequiredModules`.
3. Add `'Checks'` to `$packageItems` in `build.ps1`.
4. For `-PSRule`, point it at `PSRule\PSRuleRunner.ps1`. The runner moved
   there from `PSRuleChecks\`, and now also takes `RulePath` and
   wildcard `Rule`/`ExcludeRule` settings. Or drop `-PSRule` in favour of
   `Invoke-AACPSRule`.
5. The sign-in is no longer a global variable: it moved to the module's own
   scope (`$script:AACSession`), so other code can't read its tokens. The
   estate check (`Checks/AzureEstate.Tests.ps1`) runs outside the module and
   checks `$global:AACSession`. Have it ask the module instead, e.g.
   `& (Get-Module Azure.Admin.Console) { [bool]$script:AACSession }`.
6. Run `./build.ps1`.

`Stale/` holds files that were obsolete before the parking: the old
resource-location check and inventory helper, and an older copy of the
estate check. They can be deleted.
