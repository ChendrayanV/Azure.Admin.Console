function Invoke-AACProgress {
    <#
    .SYNOPSIS
        Runs a script block behind a Spectre.Console progress display, and
        returns whatever the script block returns.
    .DESCRIPTION
        Each task is one line:

          ⣾ Reading the estate from Azure      ━━━━━━━━━━━━━━━━━━━━━╸━━━━━━━━  66%  00:00:04
          ✓ Evaluated 64 rules: 1,204 checks   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  100%  00:00:31

        a spinner (a green tick once done), the description, a bar (blue
        while running, green when finished, a sweeping bar while its size is
        unknown), the percentage and the elapsed time.

        Tasks are added and moved on from inside the script block - or from
        anything it calls, test files included - with Update-AACProgress. When
        the script block ends, every task still running is marked finished, so
        the display always ends complete; it stays on screen above whatever
        is written next.

        Spectre.Console allows one live display at a time. A call made while
        a display is running (a command calling another, an export step)
        simply adds its lines to that display. PowerShell's own progress bars (Write-Progress, web requests) are
        switched off while it runs, as they would draw over this one.

        An error thrown by the script block is re-thrown as-is once the
        display has closed, not wrapped in a .NET "Exception calling Start".
        The steps that were still running stay unfinished, their text red
        with "- failed", and the last of them is kept on the exception
        (Data['AACStep']) for the error panel of Show-AACError.

        Spectre.Console draws the spinner, tick and bars with Unicode only
        when the console's output encoding is UTF-8; otherwise it falls back
        to '+' and '-'. The first time that happens in a session, a grey tip
        says how to switch the console to UTF-8. The module doesn't switch it
        itself: the encoding also decides how every other program's output
        is read.

        When output is not an interactive terminal (CI logs, redirected
        output), there is no live display: each task is written as one plain
        line when it finishes, e.g. "Read 1,204 resources in 12 subscriptions".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock] $ScriptBlock
    )

    $ProgressPreference = 'SilentlyContinue'

    # Already inside a display (one command calling another, or an export
    # step): join it - Spectre.Console allows only one live display.
    if ($script:AACProgressContext -or $script:AACProgressPlain) {
        return & $ScriptBlock
    }

    if (-not [Spectre.Console.AnsiConsole]::Profile.Capabilities.Interactive) {
        $script:AACProgressPlain = $true
        try {
            return & $ScriptBlock
        }
        finally {
            $script:AACProgressPlain = $false
        }
    }

    if (-not [Spectre.Console.AnsiConsole]::Profile.Capabilities.Unicode -and -not $script:AACUnicodeHintShown) {
        $script:AACUnicodeHintShown = $true
        Write-AACMarkup '[grey42]Tip: this console is not UTF-8, so symbols are drawn in plain ASCII. For the full display, run [/][grey62][[Console]]::OutputEncoding = [[Text.Encoding]]::UTF8[/][grey42] (or add it to your $PROFILE) and import the module again.[/]'
    }

    $resultHolder = [ref]$null
    $errorHolder = [ref]$null

    $action = [Action[Spectre.Console.ProgressContext]] {
        param($context)
        $script:AACProgressContext = $context
        $script:AACProgressTasks = @{}
        try {
            $resultHolder.Value = & $ScriptBlock
        }
        catch {
            $errorHolder.Value = $_
            # The steps still running are the ones that failed: they stay
            # unfinished, in red, and the error remembers the step for the
            # panel Show-AACError draws.
            $failed = @($script:AACProgressTasks.Values | Where-Object { -not $_.IsFinished } | Sort-Object -Property Id)
            if ($failed.Count -and -not $_.Exception.Data.Contains('AACStep')) {
                $_.Exception.Data['AACStep'] = [Spectre.Console.Markup]::Remove($failed[-1].Description)
            }
            foreach ($task in $failed) {
                $task.IsIndeterminate = $false
                $task.Description = "[red1]$($task.Description) - failed[/]"
            }
        }
        finally {
            foreach ($task in $script:AACProgressTasks.Values) {
                if (-not $task.IsFinished -and -not $errorHolder.Value) {
                    $task.IsIndeterminate = $false
                    $task.Value = $task.MaxValue
                    $task.StopTask()
                }
            }
            $script:AACProgressContext = $null
            $script:AACProgressTasks = @{}
        }
    }

    $spinner = [Spectre.Console.SpinnerColumn]::new([Spectre.Console.Spinner+Known]::Dots)
    $spinner.Style = [Spectre.Console.Style]::Parse('deepskyblue3_1')
    $spinner.CompletedText = (Get-AACGlyph).Tick
    $spinner.CompletedStyle = [Spectre.Console.Style]::Parse('green3')

    $description = [Spectre.Console.TaskDescriptionColumn]::new()
    $description.Alignment = [Spectre.Console.Justify]::Left

    $bar = [Spectre.Console.ProgressBarColumn]::new()
    $bar.Width = 36
    $bar.CompletedStyle = [Spectre.Console.Style]::Parse('deepskyblue3_1')
    $bar.FinishedStyle = [Spectre.Console.Style]::Parse('green3')
    $bar.RemainingStyle = [Spectre.Console.Style]::Parse('grey23')
    $bar.IndeterminateStyle = [Spectre.Console.Style]::Parse('deepskyblue3_1')

    $percentage = [Spectre.Console.PercentageColumn]::new()
    $percentage.Style = [Spectre.Console.Style]::Parse('grey70')
    $percentage.CompletedStyle = [Spectre.Console.Style]::Parse('green3')

    $elapsed = [Spectre.Console.ElapsedTimeColumn]::new()
    $elapsed.Style = [Spectre.Console.Style]::Parse('grey50')

    $progress = [Spectre.Console.AnsiConsole]::Progress()
    $progress.AutoClear = $false
    $progress.HideCompleted = $false
    [Spectre.Console.ProgressExtensions]::Columns($progress, [Spectre.Console.ProgressColumn[]]@($spinner, $description, $bar, $percentage, $elapsed)) | Out-Null
    $progress.Start($action)

    if ($errorHolder.Value) {
        throw $errorHolder.Value
    }
    $resultHolder.Value
}
