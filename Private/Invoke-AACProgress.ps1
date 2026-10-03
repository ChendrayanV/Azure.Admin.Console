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

    # Every local from here on is prefixed 'aac': the caller's script block
    # runs inside this function's scope, so a plain $action or $description
    # here would hide the caller's own -Action or $description from it.
    $aacResultHolder = [ref]$null
    $aacErrorHolder = [ref]$null

    $aacAction = [Action[Spectre.Console.ProgressContext]] {
        param($aacContext)
        $script:AACProgressContext = $aacContext
        $script:AACProgressTasks = @{}
        try {
            $aacResultHolder.Value = & $ScriptBlock
        }
        catch {
            $aacErrorHolder.Value = $_
            # The steps still running are the ones that failed: they stay
            # unfinished, in red, and the error remembers the step for the
            # panel Show-AACError draws.
            $aacFailed = @($script:AACProgressTasks.Values | Where-Object { -not $_.IsFinished } | Sort-Object -Property Id)
            if ($aacFailed.Count -and -not $_.Exception.Data.Contains('AACStep')) {
                $_.Exception.Data['AACStep'] = [Spectre.Console.Markup]::Remove($aacFailed[-1].Description)
            }
            foreach ($aacTask in $aacFailed) {
                $aacTask.IsIndeterminate = $false
                $aacTask.Description = "[red1]$($aacTask.Description) - failed[/]"
            }
        }
        finally {
            foreach ($aacTask in $script:AACProgressTasks.Values) {
                if (-not $aacTask.IsFinished -and -not $aacErrorHolder.Value) {
                    $aacTask.IsIndeterminate = $false
                    $aacTask.Value = $aacTask.MaxValue
                    $aacTask.StopTask()
                }
            }
            $script:AACProgressContext = $null
            $script:AACProgressTasks = @{}
        }
    }

    $aacSpinner = [Spectre.Console.SpinnerColumn]::new([Spectre.Console.Spinner+Known]::Dots)
    $aacSpinner.Style = [Spectre.Console.Style]::Parse('deepskyblue3_1')
    $aacSpinner.CompletedText = (Get-AACGlyph).Tick
    $aacSpinner.CompletedStyle = [Spectre.Console.Style]::Parse('green3')

    $aacDescription = [Spectre.Console.TaskDescriptionColumn]::new()
    $aacDescription.Alignment = [Spectre.Console.Justify]::Left

    $aacBar = [Spectre.Console.ProgressBarColumn]::new()
    $aacBar.Width = 36
    $aacBar.CompletedStyle = [Spectre.Console.Style]::Parse('deepskyblue3_1')
    $aacBar.FinishedStyle = [Spectre.Console.Style]::Parse('green3')
    $aacBar.RemainingStyle = [Spectre.Console.Style]::Parse('grey23')
    $aacBar.IndeterminateStyle = [Spectre.Console.Style]::Parse('deepskyblue3_1')

    $aacPercentage = [Spectre.Console.PercentageColumn]::new()
    $aacPercentage.Style = [Spectre.Console.Style]::Parse('grey70')
    $aacPercentage.CompletedStyle = [Spectre.Console.Style]::Parse('green3')

    $aacElapsed = [Spectre.Console.ElapsedTimeColumn]::new()
    $aacElapsed.Style = [Spectre.Console.Style]::Parse('grey50')

    $aacProgress = [Spectre.Console.AnsiConsole]::Progress()
    $aacProgress.AutoClear = $false
    $aacProgress.HideCompleted = $false
    [Spectre.Console.ProgressExtensions]::Columns($aacProgress, [Spectre.Console.ProgressColumn[]]@($aacSpinner, $aacDescription, $aacBar, $aacPercentage, $aacElapsed)) | Out-Null
    $aacProgress.Start($aacAction)

    if ($aacErrorHolder.Value) {
        throw $aacErrorHolder.Value
    }
    $aacResultHolder.Value
}
