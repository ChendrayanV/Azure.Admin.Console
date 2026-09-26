function Show-AACBarChart {
    <#
    .SYNOPSIS
        Renders a colourful Spectre.Console bar chart: one horizontal bar per
        item, each in its own colour, with its value at the end.
    .DESCRIPTION
        -Item is a list of @{ Label = 'compute/virtualmachines'; Value = 42 },
        drawn in the order given. An item may carry its own Color; the rest
        take the next colour of a bright palette in turn. -Format is the
        .NET number format for the values ('N0' by default, 'N2' for money),
        and -Suffix is written after each value (e.g. ' USD').
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.IDictionary[]] $Item,

        [string] $Title,

        [string] $Format = 'N0',

        [string] $Suffix = '',

        [int] $Width = 0
    )

    if ($Item.Count -eq 0) {
        return
    }
    $palette = @('deepskyblue1', 'mediumpurple2', 'springgreen2', 'gold1', 'hotpink', 'darkorange', 'turquoise2', 'orchid', 'chartreuse2', 'salmon1', 'dodgerblue2', 'yellow2')

    $chart = [Spectre.Console.BarChart]::new()
    $chart.Width = if ($Width -gt 0) { $Width } else { [Math]::Min(120, [Spectre.Console.AnsiConsole]::Profile.Width) }
    $chart.ValueFormatter = [Func[double, System.Globalization.CultureInfo, string]] {
        param($Value, $Culture)
        $Value.ToString($Format, $Culture) + $Suffix
    }.GetNewClosure()

    # The title as its own line, flush left like the breakdown charts' titles
    # (a chart label would be centred over the bars).
    if ($Title) {
        Write-AACMarkup "[bold]$([Spectre.Console.Markup]::Escape($Title))[/]"
    }

    $index = 0
    foreach ($entry in $Item) {
        $color = if ($entry.Contains('Color') -and $entry['Color']) { $entry['Color'] } else { $palette[$index % $palette.Count] }
        $index++
        [Spectre.Console.BarChartExtensions]::AddItem($chart, [Spectre.Console.Markup]::Escape([string]$entry['Label']), [double]$entry['Value'], (ConvertTo-AACColor -Name $color)) | Out-Null
    }
    [Spectre.Console.AnsiConsole]::Write($chart)
}
