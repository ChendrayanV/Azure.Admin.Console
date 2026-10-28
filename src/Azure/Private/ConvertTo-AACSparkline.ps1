function ConvertTo-AACSparkline {
    <#
    .SYNOPSIS
        Draws numbers as a one-line trend of block characters (▁▂▃▄▅▆▇█) -
        a chart that fits in a table cell, a CSV and the console.
    .DESCRIPTION
        The lowest value is ▁, the highest █; all equal (or one value) is a
        flat ▁ line. Nulls are left out; the last -Width values are drawn.
        Returns '' for no values.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyCollection()]
        [AllowNull()]
        [object[]] $Value = @(),

        [ValidateRange(2, 200)]
        [int] $Width = 48
    )

    $numbers = @($Value | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ })
    if (-not $numbers.Count) { return '' }
    if ($numbers.Count -gt $Width) { $numbers = @($numbers[($numbers.Count - $Width)..($numbers.Count - 1)]) }
    $low = ($numbers | Measure-Object -Minimum).Minimum
    $high = ($numbers | Measure-Object -Maximum).Maximum
    $blocks = @(0x2581..0x2588 | ForEach-Object { [char]$_ })
    if ($high -le $low) { return [string]::new($blocks[0], $numbers.Count) }
    -join @($numbers | ForEach-Object { $blocks[[Math]::Min(7, [int][Math]::Floor(($_ - $low) / ($high - $low) * 8))] })
}
