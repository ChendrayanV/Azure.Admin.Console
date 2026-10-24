function Get-AACByteUnit {
    <#
    .SYNOPSIS
        The unit (B, KiB, MiB, GiB, TiB, PiB) that shows -Bytes as a number
        from 1 to 1,023 - or, with -AsPower, its power of 1,024 (0-5).
    #>
    [CmdletBinding()]
    [OutputType([string], [int])]
    param(
        [Parameter(Mandatory)]
        [double] $Bytes,

        [switch] $AsPower
    )

    $power = 0
    $value = [Math]::Abs($Bytes)
    while ($value -ge 1024 -and $power -lt 5) { $value /= 1024; $power++ }
    if ($AsPower) { return $power }
    @('B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB')[$power]
}
