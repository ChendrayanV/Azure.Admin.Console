function Show-AACBreakdownChart {
    <#
    .SYNOPSIS
        Renders a Spectre.Console breakdown chart (one bar split into
        proportional segments), written directly to the console.
    .DESCRIPTION
        Used for part-of-whole data - rule types, collection actions,
        compliance states. Zero-valued items are dropped (a zero segment
        would only add a "0" tag), and nothing is drawn at all when every
        value is zero. -Color maps a label to a Spectre color name; labels
        without one take the next color from a neutral palette.

        -HideTags draws just the bar, without Spectre's built-in legend, for
        callers that write their own text legend.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Data,

        [string] $Title,

        [hashtable] $Color = @{},

        [ValidateRange(20, 200)]
        [int] $Width = 80,

        [switch] $HideTags
    )

    $items = @($Data.Keys | Where-Object { [double]$Data[$_] -gt 0 })
    if ($items.Count -eq 0) {
        return
    }

    if ($Title) {
        Write-AACMarkup "[bold]$([Spectre.Console.Markup]::Escape($Title))[/]"
    }

    $palette = @('deepskyblue3_1', 'mediumpurple2', 'cyan1', 'steelblue1', 'grey70', 'orange1')

    $chart = [Spectre.Console.BreakdownChart]::new()
    $chart.Width = [Math]::Min($Width, [Spectre.Console.AnsiConsole]::Profile.Width)
    $chart.ShowTags = -not $HideTags

    $paletteIndex = 0
    foreach ($key in $items) {
        $colorName = if ($Color.ContainsKey($key)) {
            $Color[$key]
        }
        else {
            $palette[$paletteIndex % $palette.Count]
            $paletteIndex++
        }
        [Spectre.Console.BreakdownChartExtensions]::AddItem($chart, [string]$key, [double]$Data[$key], (ConvertTo-AACColor -Name $colorName)) | Out-Null
    }

    [Spectre.Console.AnsiConsole]::Write($chart)
}
