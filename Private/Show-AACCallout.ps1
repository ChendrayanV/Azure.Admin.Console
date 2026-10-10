function Show-AACCallout {
    <#
    .SYNOPSIS
        Draws a callout - a rounded panel in a state's colour, headed by its
        symbol and a title - for what an operator mustn't miss: an outcome,
        a warning, a block, a security notice.
    .DESCRIPTION
          ╭─ ✓ Verified ────────────────────────────────────────╮
          │ Read again, stcontoso matches the configuration.    │
          ╰─────────────────────────────────────────────────────╯

        The colour and symbol come from Get-AACStatus (Success, Warning,
        Failed, InProgress, Info), so every command's callouts agree. The
        title defaults to the state's word. -Message is Spectre.Console
        markup (escape any value in it); -Line adds plain-text lines under
        it, each escaped.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateSet('Success', 'Warning', 'Failed', 'InProgress', 'Info')]
        [string] $Status,

        [Parameter(Mandatory, Position = 1)]
        [string] $Message,

        [string] $Title,

        [string[]] $Line = @()
    )

    $state = Get-AACStatus $Status
    $content = @($Message) + @($Line | Where-Object { $_ } | ForEach-Object { "[grey70]$([Spectre.Console.Markup]::Escape($_))[/]" })
    $panel = [Spectre.Console.Panel]::new([Spectre.Console.Markup]::new($content -join "`n"))
    $panel.Border = [Spectre.Console.BoxBorder]::Rounded
    $panel.BorderStyle = [Spectre.Console.Style]::Parse($(if ($Status -eq 'Info') { 'grey50' } else { $state.Color }))
    $heading = if ($Title) { $Title } else { $state.Label }
    $panel.Header = [Spectre.Console.PanelHeader]::new(" $($state.Markup) [$($state.Color)]$([Spectre.Console.Markup]::Escape($heading))[/] ")
    [Spectre.Console.AnsiConsole]::Write($panel)
}
