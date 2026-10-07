function Invoke-AACPagedOutput {
    <#
    .SYNOPSIS
        Runs a script block that draws Spectre.Console output, then shows that
        output one screen at a time: "press any key for the next page".
    .DESCRIPTION
        While the script block runs, the global Spectre console is swapped for
        one that writes into a buffer, with the same width, color support and
        Unicode support as the real terminal. The buffered text (ANSI color
        codes included) is then written a page at a time, where a page is the
        terminal's height minus one line for the prompt. The real console is
        always put back, even if the script block throws.

        At the prompt, any key shows the next page, and A shows everything
        that's left without stopping again.

        Paging only makes sense when someone is at the keyboard. The output is
        written straight through, unpaged, when -NoPaging is given, when input
        or output is redirected (pipelines, CI, scheduled tasks), or when it
        all fits on one screen.

        -ReadKey exists for tests: it replaces the real key press.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock] $ScriptBlock,

        [switch] $NoPaging,

        [int] $PageSize = 0,

        [scriptblock] $ReadKey = { [Console]::ReadKey($true) }
    )

    # A terminal at both ends - and Spectre still drawing to it (a console
    # swapped for a buffer, as tests and other captures do, isn't paged).
    $isInteractive = -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected -and [Spectre.Console.AnsiConsole]::Console.Profile.Out.IsTerminal
    if ($NoPaging -or (-not $isInteractive -and $PageSize -le 0)) {
        & $ScriptBlock
        return
    }

    $realConsole = [Spectre.Console.AnsiConsole]::Console
    $buffer = [System.IO.StringWriter]::new()

    $settings = [Spectre.Console.AnsiConsoleSettings]::new()
    $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer)
    $settings.Ansi = [Spectre.Console.AnsiSupport]::Yes
    $settings.ColorSystem = [Spectre.Console.ColorSystemSupport]([string]$realConsole.Profile.Capabilities.ColorSystem)
    $settings.Interactive = [Spectre.Console.InteractionSupport]::No

    $capture = [Spectre.Console.AnsiConsole]::Create($settings)
    $capture.Profile.Width = $realConsole.Profile.Width
    $capture.Profile.Capabilities.Unicode = $realConsole.Profile.Capabilities.Unicode
    $capture.Profile.Capabilities.Ansi = $realConsole.Profile.Capabilities.Ansi

    try {
        [Spectre.Console.AnsiConsole]::Console = $capture
        & $ScriptBlock
    }
    finally {
        [Spectre.Console.AnsiConsole]::Console = $realConsole
    }

    $lines = @($buffer.ToString() -split '\r?\n')
    # The last line is the empty remainder after the final newline.
    if ($lines.Count -gt 0 -and $lines[-1] -eq '') {
        $lines = @($lines | Select-Object -SkipLast 1)
    }

    if ($PageSize -le 0) {
        $height = try { [Console]::WindowHeight } catch { 0 }
        $PageSize = [Math]::Max(10, $height - 1)
    }

    $out = [Console]::Out
    if ($lines.Count -le $PageSize) {
        foreach ($line in $lines) { $out.WriteLine($line) }
        return
    }

    $pageCount = [Math]::Ceiling($lines.Count / $PageSize)
    $esc = [char]27
    for ($page = 0; $page -lt $pageCount; $page++) {
        $start = $page * $PageSize
        $end = [Math]::Min($start + $PageSize, $lines.Count) - 1
        foreach ($index in $start..$end) { $out.WriteLine($lines[$index]) }

        if ($page -eq $pageCount - 1) {
            break
        }

        $prompt = " Page $($page + 1) of $pageCount  -  press any key for the next page, A to show the rest "
        $out.Write("$esc[7m$prompt$esc[0m")
        $key = & $ReadKey
        # Erase the prompt line so it doesn't stay in the scrollback.
        $out.Write("`r$(' ' * $prompt.Length)`r")

        if ($key -and [string]$key.KeyChar -eq 'a') {
            foreach ($index in ($end + 1)..($lines.Count - 1)) { $out.WriteLine($lines[$index]) }
            break
        }
    }
}
