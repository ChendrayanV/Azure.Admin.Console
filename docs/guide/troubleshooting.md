# Troubleshooting

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**When a command fails.** At the console, the progress line of the step that
was running turns red, and a red panel says what failed, that step, and what
to do:

```text
╭─ ✗ Invoke-AACApplicationInsightQuery failed ─────────────────────────────╮
│ Azure refused the request (403): The client ... does not have            │
│ authorization to perform action 'Microsoft.OperationalInsights/...'      │
│                                                                          │
│ Step  Running the exceptions query over the last 2h                      │
│ Fix   Your account needs a role that allows this: ... Log Analytics      │
│       Reader for Invoke-AACApplicationInsightQuery.                      │
╰──────────────────────────────────────────────────────────────────────────╯
```

Then the command stops with a normal PowerShell error of its own, so
`try`/`catch`, `$Error` and `-ErrorVariable` work as usual. Scripts can check
its `FullyQualifiedErrorId`: `AzureRequestFailed<status>` (for example
`AzureRequestFailed403,Show-AACCost`), `CommandFailed` or `InternalError`.
Output that isn't an interactive console (CI, redirected) and
`-ErrorAction SilentlyContinue` get no panel. An `InternalError` is a bug in
the module: its message gives the module file and line. Please
[report it](https://github.com/ChendrayanV/Azure.Admin.Console/issues) with
that message.

**"The pipeline has been stopped."** Before v0.13.0, piping a command to
`Select-Object -First` (or anything else that stops a pipeline early) ended
it with this error and a red panel. It isn't a failure: update to v0.13.0 or
later, where the command just stops. Ctrl+C still stops everything.

**`?` instead of symbols, or `+` and `-` in the progress.** Windows consoles
often default to a legacy code page (437 or 850), which has no `●`, `→` or
`✓`. The module detects this: in such a console it draws its symbols in plain
ASCII (`*`, `->`, `+`, `-`), so nothing is printed as `?`. The tests check
every view against code pages 437 and 850. For the full Unicode display,
switch the session to UTF-8 and import the module again:

```powershell
[Console]::OutputEncoding = [Text.Encoding]::UTF8   # add to your $PROFILE to keep it
Import-Module Azure.Admin.Console -Force
```

Windows Terminal and the VS Code terminal display the full Unicode output once
the encoding is UTF-8.

**"requires a minimum Windows PowerShell version of '7.2'".** The module runs
on PowerShell 7.2 or later (7.4+ for PDF export), on Windows, Linux and macOS,
not on Windows PowerShell 5.1. Install PowerShell 7 (`winget install
Microsoft.PowerShell`) and run it as `pwsh`.
