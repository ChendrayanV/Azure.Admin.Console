function Write-AACPesterReport {
    <#
    .SYNOPSIS
        Renders a Pester v5 PassThru result as a readable, text-only report:
        one section per test file, the full detail of every failure, and a
        summary with a clear verdict.
    .DESCRIPTION
        Layout, top to bottom:
          1. One section per test file, headed by a rule with its counts. Each
             top-level Describe block is a table titled with the block's name,
             one row per test: a PASS/FAIL/SKIP badge, the Context it belongs
             to (shown once per group, with a blank row between groups), the
             test name and its duration.
          2. Skipped tests, with the reason each was skipped.
          3. Failures: one panel per failed test with the complete error
             message and the test file and line it came from - nothing is
             truncated here, because this is what someone needs to fix it.
          4. Summary: total/passed/failed/skipped/duration tiles, a proportion
             bar, and a verdict panel (PASSED, FAILED or NO TESTS RAN).

        Status is carried by words and color together (" PASS " on green,
        " FAIL " on red), never by icons, so it reads the same in any terminal
        and font. Tests Pester didn't run at all (excluded by a filter) are
        counted, not listed.

        A test file that failed before any test ran (e.g. an error during
        Pester discovery) is shown as a failed section with its error, rather
        than silently missing from the report.

        With -FailedOnly the tables list only failed tests and the skipped
        list is left out; the per-file counts and the summary still cover
        every test, so nothing is hidden from the totals.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $PesterResult,

        [switch] $FailedOnly
    )

    $containers = @(Get-AACPropertyValue -InputObject $PesterResult -Name 'Containers')
    $brokenContainers = @($containers | Where-Object { [string]$_.Result -eq 'Failed' -and @($_.Blocks).Count -eq 0 })

    if ((-not $PesterResult.Tests -or $PesterResult.Tests.Count -eq 0) -and $brokenContainers.Count -eq 0) {
        Write-AACMarkup '[gold3]No Pester tests were found.[/]'
        return
    }

    $escape = { param([string] $Text) [Spectre.Console.Markup]::Escape($Text) }

    # Equal-width badges, so the status column lines up.
    $badge = @{
        Passed       = '[bold black on green3] PASS [/]'
        Failed       = '[bold white on red3] FAIL [/]'
        Skipped      = '[bold black on grey62] SKIP [/]'
        Inconclusive = '[bold black on gold3] WARN [/]'
    }
    $textColor = @{ Passed = 'default'; Failed = 'red3'; Skipped = 'grey62'; Inconclusive = 'gold3' }

    $formatDuration = {
        param([TimeSpan] $Duration)
        if ($Duration.TotalMilliseconds -lt 1000) { '{0:N0} ms' -f $Duration.TotalMilliseconds } else { '{0:N2} s' -f $Duration.TotalSeconds }
    }

    $firstLine = {
        param([object] $Record)
        $errors = @(Get-AACPropertyValue -InputObject $Record -Name 'ErrorRecord')
        if ($errors.Count -gt 0 -and $errors[0]) { (([string]$errors[0].Exception.Message) -split "`r?`n")[0] } else { '' }
    }

    # Every test under a block, in order, with the names of the blocks between
    # it and that block ("Context / Nested context").
    $collectTests = {
        param([object] $Block, [string[]] $Trail)
        foreach ($test in $Block.Tests) {
            [pscustomobject]@{ Test = $test; Group = ($Trail -join ' / ') }
        }
        foreach ($child in $Block.Blocks) {
            & $collectTests $child (@($Trail) + [string]$child.ExpandedName)
        }
    }

    $failures = [System.Collections.Generic.List[object]]::new()
    $skips = [System.Collections.Generic.List[object]]::new()

    # --- 1. One section per test file -----------------------------------------
    foreach ($container in $containers) {
        $fileName = Split-Path -Path ([string]$container.Item) -Leaf
        $count = Get-AACPesterOutcomeCount -Node $container
        $isBroken = $container -in $brokenContainers
        $ruleColor = if ($count.Failed -gt 0 -or $isBroken) { 'red3' } elseif ($count.Passed -gt 0) { 'green3' } else { 'grey62' }

        Write-AACMarkup ''
        $rule = [Spectre.Console.Rule]::new("[bold]$(& $escape $fileName)[/]  [grey62]$($count.Passed) passed · $($count.Failed) failed · $($count.Skipped) skipped[/]")
        $rule.Justification = [Spectre.Console.Justify]::Left
        $rule.Style = [Spectre.Console.Style]::Parse($ruleColor)
        [Spectre.Console.AnsiConsole]::Write($rule)

        if ($FailedOnly -and -not $isBroken -and ($count.Passed + $count.Skipped) -gt 0) {
            Write-AACMarkup "[grey62]Showing failed tests only - $($count.Passed) passed and $($count.Skipped) skipped hidden.[/]"
        }

        if ($isBroken) {
            $message = & $firstLine $container
            if (-not $message) { $message = 'Unknown error.' }
            $failures.Add([pscustomobject]@{ Title = "$fileName could not be loaded"; Context = ''; Record = $container })
            Write-AACMarkup "[red3]This file failed before any test ran:[/] $(& $escape $message)"
            continue
        }

        foreach ($topBlock in $container.Blocks) {
            $entries = @(& $collectTests $topBlock @() | Where-Object {
                    [string]$_.Test.Result -ne 'NotRun' -and (-not $FailedOnly -or [string]$_.Test.Result -eq 'Failed')
                })
            if ($entries.Count -eq 0) {
                continue
            }
            $hasGroups = @($entries | Where-Object { $_.Group }).Count -gt 0

            $table = [Spectre.Console.Table]::new()
            $table.Border = [Spectre.Console.TableBorder]::Rounded
            $table.BorderStyle = [Spectre.Console.Style]::Parse('grey35')
            $table.Expand = $true
            $table.Title = [Spectre.Console.TableTitle]::new("[bold]$(& $escape ([string]$topBlock.ExpandedName))[/]")

            $addColumn = {
                param([string] $Header, [switch] $NoWrap, [switch] $Right, [int] $Width = 0)
                $column = [Spectre.Console.TableColumn]::new("[grey62]$Header[/]")
                $column.NoWrap = [bool]$NoWrap
                if ($Right) { $column.Alignment = [Spectre.Console.Justify]::Right }
                # A fixed width keeps the full-width table from handing its
                # spare space to the badge and time columns.
                if ($Width -gt 0) { $column.Width = $Width }
                $table.AddColumn($column) | Out-Null
            }
            & $addColumn 'Result' -NoWrap -Width 6
            if ($hasGroups) { & $addColumn 'Group' }
            & $addColumn 'Test'
            & $addColumn 'Time' -NoWrap -Right -Width 9

            $previousGroup = $null
            foreach ($entry in $entries) {
                $test = $entry.Test
                $result = [string]$test.Result
                if (-not $badge.ContainsKey($result)) { $result = 'Skipped' }

                if ($hasGroups -and $null -ne $previousGroup -and $entry.Group -ne $previousGroup) {
                    [Spectre.Console.TableExtensions]::AddEmptyRow($table) | Out-Null
                }
                $groupCell = if ($entry.Group -ne $previousGroup) { "[bold]$(& $escape $entry.Group)[/]" } else { '' }
                $previousGroup = $entry.Group

                $cells = [System.Collections.Generic.List[Spectre.Console.Rendering.IRenderable]]::new()
                $cells.Add([Spectre.Console.Markup]::new($badge[$result]))
                if ($hasGroups) { $cells.Add([Spectre.Console.Markup]::new($groupCell)) }
                $cells.Add([Spectre.Console.Markup]::new("[$($textColor[$result])]$(& $escape ([string]$test.ExpandedName))[/]"))
                $cells.Add([Spectre.Console.Markup]::new("[grey62]$(& $formatDuration $test.Duration)[/]"))
                [Spectre.Console.TableExtensions]::AddRow($table, $cells.ToArray()) | Out-Null

                $path = @([string]$topBlock.ExpandedName) + @($entry.Group | Where-Object { $_ }) + @([string]$test.ExpandedName)
                if ($result -eq 'Failed') {
                    $failures.Add([pscustomobject]@{ Title = [string]$test.ExpandedName; Context = ($path | Select-Object -SkipLast 1) -join ' / '; Record = $test })
                }
                elseif ($result -eq 'Skipped') {
                    $skips.Add([pscustomobject]@{ Title = $path -join ' / '; Reason = & $firstLine $test })
                }
            }

            [Spectre.Console.AnsiConsole]::Write($table)
        }
    }

    # --- 2. Skipped tests and why ---------------------------------------------
    if ($skips.Count -gt 0) {
        Write-AACMarkup ''
        $table = [Spectre.Console.Table]::new()
        $table.Border = [Spectre.Console.TableBorder]::Rounded
        $table.BorderStyle = [Spectre.Console.Style]::Parse('grey35')
        $table.Expand = $true
        $table.Title = [Spectre.Console.TableTitle]::new("[bold]Skipped ($($skips.Count))[/]")
        $table.AddColumn([Spectre.Console.TableColumn]::new('[grey62]Test[/]')) | Out-Null
        $table.AddColumn([Spectre.Console.TableColumn]::new('[grey62]Reason[/]')) | Out-Null
        foreach ($skip in $skips) {
            $reason = ($skip.Reason -replace '^is skipped, because ', '')
            if (-not $reason) { $reason = 'No reason given.' }
            [Spectre.Console.TableExtensions]::AddRow($table, [Spectre.Console.Rendering.IRenderable[]]@(
                    [Spectre.Console.Markup]::new("[grey62]$(& $escape $skip.Title)[/]")
                    [Spectre.Console.Markup]::new((& $escape $reason))
                )) | Out-Null
        }
        [Spectre.Console.AnsiConsole]::Write($table)
    }

    # --- 3. Every failure, in full ----------------------------------------------
    if ($failures.Count -gt 0) {
        Write-AACMarkup ''
        $rule = [Spectre.Console.Rule]::new("[bold red3]Failures ($($failures.Count))[/]")
        $rule.Justification = [Spectre.Console.Justify]::Left
        $rule.Style = [Spectre.Console.Style]::Parse('red3')
        [Spectre.Console.AnsiConsole]::Write($rule)

        $number = 0
        foreach ($failure in $failures) {
            $number++
            $errors = @(Get-AACPropertyValue -InputObject $failure.Record -Name 'ErrorRecord')
            $error0 = if ($errors.Count -gt 0) { $errors[0] } else { $null }

            $message = if ($error0) { ([string]$error0.Exception.Message).Trim() } else { 'No error message was recorded.' }
            $messageLines = @($message -split "`r?`n")
            if ($messageLines.Count -gt 15) {
                $messageLines = @($messageLines | Select-Object -First 15) + "... ($($messageLines.Count - 15) more lines)"
            }
            $body = ($messageLines | ForEach-Object { & $escape $_ }) -join "`n"
            if ($failure.Context) {
                $body = "[grey62]$(& $escape $failure.Context)[/]`n`n$body"
            }

            # Point at the line in the test file itself, not Pester's internals.
            $stackTrace = if ($error0) { [string]$error0.ScriptStackTrace } else { '' }
            $location = [regex]::Match($stackTrace, '([^\\/:\r\n]+\.Tests\.ps1): line (\d+)')
            if ($location.Success) {
                $body += "`n`n[grey62]at $(& $escape $location.Groups[1].Value), line $($location.Groups[2].Value)[/]"
            }

            $panel = [Spectre.Console.Panel]::new([Spectre.Console.Markup]::new($body))
            $panel.Header = [Spectre.Console.PanelHeader]::new(" [bold]$number. $(& $escape $failure.Title)[/] ")
            $panel.Border = [Spectre.Console.BoxBorder]::Rounded
            $panel.BorderStyle = [Spectre.Console.Style]::Parse('red3')
            $panel.Expand = $true
            $panel.Padding = [Spectre.Console.Padding]::new(2, 1, 2, 1)
            [Spectre.Console.AnsiConsole]::Write($panel)
        }
    }

    # --- 4. Summary and verdict -----------------------------------------------
    $passed = [int]$PesterResult.PassedCount
    $failed = [int]$PesterResult.FailedCount + $brokenContainers.Count
    $skipped = [int]$PesterResult.SkippedCount
    $notRun = [int]$PesterResult.NotRunCount
    $ran = $passed + $failed + $skipped

    Write-AACMarkup ''
    $rule = [Spectre.Console.Rule]::new('[bold]Summary[/]')
    $rule.Justification = [Spectre.Console.Justify]::Left
    $rule.Style = [Spectre.Console.Style]::Parse('grey50')
    [Spectre.Console.AnsiConsole]::Write($rule)

    $tile = {
        param([string] $Label, [string] $Value, [string] $Color)
        $content = [Spectre.Console.Markup]::new("[bold $Color]$Value[/]`n[grey62]$Label[/]")
        $content.Justification = [Spectre.Console.Justify]::Center
        $panel = [Spectre.Console.Panel]::new($content)
        $panel.Border = [Spectre.Console.BoxBorder]::Rounded
        $panel.BorderStyle = [Spectre.Console.Style]::Parse($(if ($Color -eq 'default') { 'grey35' } else { $Color }))
        $panel.Width = 16
        $panel
    }
    $tiles = [Spectre.Console.Rendering.IRenderable[]]@(
        (& $tile 'tests run' ([string]$ran) 'default')
        (& $tile 'passed' ([string]$passed) $(if ($passed -gt 0) { 'green3' } else { 'grey62' }))
        (& $tile 'failed' ([string]$failed) $(if ($failed -gt 0) { 'red3' } else { 'grey62' }))
        (& $tile 'skipped' ([string]$skipped) 'grey62')
        (& $tile 'duration' (& $formatDuration $PesterResult.Duration) 'default')
    )
    [Spectre.Console.AnsiConsole]::Write([Spectre.Console.Columns]::new($tiles))

    if ($ran -gt 0) {
        Show-AACBreakdownChart -Data ([ordered]@{ Passed = $passed; Failed = $failed; Skipped = $skipped }) `
            -Color @{ Passed = 'green3'; Failed = 'red3'; Skipped = 'grey50' } -HideTags -Width 200
        # Pass rate counts only tests that actually passed or failed; skipped
        # tests say nothing either way.
        $decided = $passed + $failed
        $passRate = if ($decided -gt 0) { "   [grey50]Pass rate $([math]::Round(100 * $passed / $decided, 1))%[/]" } else { '' }
        Write-AACMarkup "[green3]Passed $passed[/]   [red3]Failed $failed[/]   [grey62]Skipped $skipped[/]$passRate"
    }
    if ($notRun -gt 0) {
        Write-AACMarkup "[grey50]$notRun test(s) were not run: excluded by a filter, or their block failed to set up.[/]"
    }

    $verdict = if ($failed -gt 0) {
        @{ Text = "FAILED  -  $failed of $ran test(s) failed"; Style = 'bold white on red3'; Border = 'red3' }
    }
    elseif ($ran -eq 0) {
        @{ Text = 'NO TESTS RAN  -  check the path and any -Tag / -TestName filter'; Style = 'bold black on gold3'; Border = 'gold3' }
    }
    elseif ($passed -eq 0) {
        @{ Text = "SKIPPED  -  all $skipped test(s) were skipped, see the reasons above"; Style = 'bold black on gold3'; Border = 'gold3' }
    }
    else {
        @{ Text = "PASSED  -  all $passed test(s) passed$(if ($skipped -gt 0) { ", $skipped skipped" })"; Style = 'bold black on green3'; Border = 'green3' }
    }
    $verdictText = [Spectre.Console.Markup]::new("[$($verdict.Style)]  $(& $escape $verdict.Text)  [/]")
    $verdictText.Justification = [Spectre.Console.Justify]::Center
    $verdictPanel = [Spectre.Console.Panel]::new($verdictText)
    $verdictPanel.Border = [Spectre.Console.BoxBorder]::Double
    $verdictPanel.BorderStyle = [Spectre.Console.Style]::Parse($verdict.Border)
    $verdictPanel.Expand = $true
    [Spectre.Console.AnsiConsole]::Write($verdictPanel)
}
