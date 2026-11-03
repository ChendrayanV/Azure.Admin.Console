# Contributing to Azure.Admin.Console

For anyone changing this repository, people and AI coding agents alike. New commands, fixes, ideas and bug reports are all welcome: [open an issue](https://github.com/ChendrayanV/Azure.Admin.Console/issues) to say what you'd like to work on.

Azure.Admin.Console is a PowerShell 7.2+ module (Core only) for Azure, Microsoft 365 and Azure DevOps administration over **plain REST**. Every public command gives a Spectre.Console view, typed `AAC.*` objects, and CSV, HTML and PDF reports.

## Rules

- **No `Az.*` or `Microsoft.Graph.*` modules, ever.** Azure access goes through the private REST helpers in `src\Core\Private` (`Invoke-AACArmRequest`, `Invoke-AACArmParallel`, `Invoke-AACArmWrite`, `Invoke-AACArmOperationBatch`, `Get-AACAccessToken`). Don't call `Invoke-RestMethod` directly in a new command.
- **One module dependency:** `PSRule.Rules.Azure`, run in a child `pwsh` by `PSRule\PSRuleRunner.ps1`. Ask before adding another `RequiredModules` entry.
- **Read-only by default.** Anything that writes to Azure or Entra ID uses `SupportsShouldProcess`, so `-WhatIf` works.
- **`Set-StrictMode -Version Latest` is on:** initialise every variable before reading it.
- **Areas stay apart.** An area may call Core and itself only, never another area, and Core never calls into an area (`Tests\Core\Module.Tests.ps1` enforces it). A helper two areas need moves to `src\Core\Private\`.
- **Don't touch `lib\`.** Its DLLs (Spectre.Console, PDFsharp, MigraDoc) are SHA-256 pinned in the `.psm1` and the PDF loader, so changing one means updating its hash.
- **Don't edit generated files by hand:** `docs\<Command>.md`, `docs\Azure.Admin.Console.md`, `docs\about_*.md`, `en-US\Azure.Admin.Console-help.xml`, `llms.txt` and `llms-full.txt`. Change the source, then run `./build.ps1 -Task Docs`.
- **`Parked\` is not loaded, packaged or tested.** Ignore it unless the task is about it.
- **Maintainer's decisions:** don't bump `ModuleVersion`, edit `CHANGELOG.md`, tag, push or run `./build.ps1 -Task Publish` unless asked.
- **Commits:** no AI co-author or attribution lines.

## Layout

```text
Azure.Admin.Console.psd1 / .psm1   the module: loads each area of src\, Core first
src\
  Core\          sign-in, REST helpers, console views, CSV / HTML / PDF reports
  Azure\         commands scoped to subscriptions and management groups
  M365\          commands for the Entra ID / Microsoft 365 tenant
  DevOps\        commands for Azure DevOps
  Architecture\  architecture design: brief, patterns, design, rules, diagrams, decisions
    <Area>\area.psd1  the area's name, title, description and load order
    <Area>\Public\    one exported command per file, file name = function name
    <Area>\Private\   its helpers
Tests\<Area>\    Pester tests, fully mocked - no Azure sign-in needed
Tests\Fixtures\  fake API answers the tests read
PSRule\          the runner for Invoke-AACPSRule, and the module's own rules
GUIDE.md         the guide's index
docs\guide\      the guide, one hand-written page per topic
docs\            generated reference, one page per command
tools\           build and maintenance scripts (not packaged)
out\             build output - never edit
```

Helpers are named by what they do: `ConvertTo-AAC*` shapes API rows into objects, `Show-AAC*` draws a console view, `Write-AAC*Csv/Html/Pdf` writes a report, `Get-AAC*Query` holds Resource Graph KQL.

Module-scoped state lives in `$script:AAC*` variables declared at the top of the `.psm1`. Inside dot-sourced files use `$script:AACModuleRoot`, not `$PSScriptRoot`.

## Adding a command

Copy a sibling rather than inventing a pattern. A command goes in `Azure` if it takes a subscription or management group scope, in `M365` if it works on the Entra ID / Microsoft 365 tenant, and in `DevOps` for Azure DevOps.

1. `src\<Area>\Public\Verb-AACThing.ps1`: the command, with `-CsvPath`, `-HtmlPath`, `-PdfPath` and `-PassThru` where its siblings have them, and comment-based help with `.EXTERNALHELP Azure.Admin.Console-help.xml`.
2. `src\<Area>\Private\`: `ConvertTo-AACThing.ps1`, then `Show-AACThing*.ps1`, then `Write-AACThingCsv/Html/Pdf.ps1`.
3. Add it to `FunctionsToExport` in `Azure.Admin.Console.psd1`, to the list in `Tests\Core\Module.Tests.ps1`, and to the command tables in `GUIDE.md`.
4. `Tests\<Area>\Thing.Tests.ps1` with a fixture in `Tests\Fixtures\ContosoThing.ps1`. `Tests\Azure\Cost.Tests.ps1` shows the structure: import in `BeforeDiscovery`, capture the Spectre console, mock the REST calls. PDF tests skip off Windows and below PowerShell 7.4; keep that guard.

## Build and test

The tests need PowerShell 7.4+ and Pester 6.2+. The module itself runs on 7.2.

```powershell
Invoke-Pester -Path ./Tests/Azure/Cost.Tests.ps1 -Output Detailed   # one test file while you work
Invoke-Pester -Path ./Tests/DevOps -Output Detailed                 # one area
./build.ps1 -Task Test                                              # every test
./build.ps1 -Task Docs                                              # after changing help or docs\guide
./build.ps1                                                         # docs, every test, analyzer, package
```

The build allows no PSScriptAnalyzer errors or warnings, and CI fails if the generated docs are stale.

## Style

- Full cmdlet and parameter names (`Get-ChildItem -Path`, not `gci` or positional).
- 4-space indent, OTBS braces, `-LiteralPath` for file paths.
- User-facing errors start with "Azure Admin Console ..." and say what to do next.
- Comments explain *why*, in plain English.

## Finding your way

More detail is in [the guide's Development page](docs/guide/development.md). `CHANGELOG.md`, `docs\`, `en-US\`, `lib\`, `out\`, `Parked\`, `llms-full.txt` and `Tests\Fixtures\TerraformPlans\*.json` are large, so search them rather than reading them whole.
