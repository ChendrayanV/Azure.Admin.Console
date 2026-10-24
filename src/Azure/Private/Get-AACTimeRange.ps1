function Get-AACTimeRange {
    <#
    .SYNOPSIS
        A -TimeRange (1h, 4h, 12h, 1d, 3d, 7d, 14d, 30d) as the hours it
        covers and the metric grain to read it at - an interval Azure
        Monitor accepts, coarse enough to keep the points few.
    .DESCRIPTION
        Returns @(hours, interval), so callers keep reading $range[0] and
        $range[1].
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('1h', '4h', '12h', '1d', '3d', '7d', '14d', '30d')]
        [string] $TimeRange
    )

    @{ '1h' = @(1, 'PT5M'); '4h' = @(4, 'PT15M'); '12h' = @(12, 'PT30M'); '1d' = @(24, 'PT1H'); '3d' = @(72, 'PT6H'); '7d' = @(168, 'PT6H'); '14d' = @(336, 'PT12H'); '30d' = @(720, 'P1D') }[$TimeRange]
}
