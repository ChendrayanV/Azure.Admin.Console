function Show-AACPanel {
    <#
    .SYNOPSIS
        Renders a Spectre.Console panel, written directly to the console.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Content,

        [string] $Header,

        [string] $BorderColor = 'grey50',

        [switch] $AllowMarkup
    )

    $renderable = if ($AllowMarkup) {
        [Spectre.Console.Markup]::new($Content)
    }
    else {
        [Spectre.Console.Text]::new($Content)
    }

    $panel = [Spectre.Console.Panel]::new($renderable)
    $panel.Border = [Spectre.Console.BoxBorder]::Rounded
    $panel.BorderStyle = [Spectre.Console.Style]::Parse($BorderColor)
    if ($Header) {
        $panel.Header = [Spectre.Console.PanelHeader]::new($Header)
    }

    [Spectre.Console.AnsiConsole]::Write($panel)
}
