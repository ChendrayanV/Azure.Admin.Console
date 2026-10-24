function Show-AACTileRow {
    <#
    .SYNOPSIS
        Renders a row of Spectre.Console tiles - one rounded panel per
        number, with a caption under it.
    .DESCRIPTION
        Each tile is @{ Value = '42'; Caption = 'rules'; Color = 'green3' }.
        The border and the number take the tile's colour; a tile whose value
        is '0' or '-' is drawn grey instead, so empty counts don't stand out.
        The tiles share the full width, and wrap onto more lines in a narrow
        terminal. Used by the Get-AACAdvisorRecommendation and
        Get-AACFirewallRule console views.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary[]] $Tile
    )

    $panels = foreach ($item in $Tile) {
        $value = [string]$item.Value
        $color = if ($value -in '0', '-') { 'grey42' } else { $item.Color }
        $text = [Spectre.Console.Markup]::new("[bold $color]$([Spectre.Console.Markup]::Escape($value))[/]`n[grey58]$([Spectre.Console.Markup]::Escape([string]$item.Caption))[/]")
        $text.Justification = [Spectre.Console.Justify]::Center
        $panel = [Spectre.Console.Panel]::new($text)
        $panel.Border = [Spectre.Console.BoxBorder]::Rounded
        $panel.BorderStyle = [Spectre.Console.Style]::Parse($color)
        $panel.Padding = [Spectre.Console.Padding]::new(2, 0, 2, 0)
        $panel.Expand = $true
        $panel
    }
    $columns = [Spectre.Console.Columns]::new([Spectre.Console.Rendering.IRenderable[]]@($panels))
    $columns.Expand = $true
    [Spectre.Console.AnsiConsole]::Write($columns)
}
