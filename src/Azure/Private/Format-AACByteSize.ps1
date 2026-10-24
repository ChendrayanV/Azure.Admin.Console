function Format-AACByteSize {
    <#
    .SYNOPSIS
        A number of bytes as people read it: '512 B', '1.50 KiB', '3.27 GiB',
        '1.02 TiB' - powers of 1,024, as the Azure portal shows storage.
    .DESCRIPTION
        -Unit picks the unit instead (B, KiB, MiB, GiB, TiB, PiB), so a list
        can share one; -Decimals sets the places after the point (2).
        Get-AACByteUnit returns the unit that suits a value.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [double] $Bytes,

        [ValidateSet('', 'B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB')]
        [string] $Unit = '',

        [ValidateRange(0, 6)]
        [int] $Decimals = 2
    )

    $units = 'B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB'
    $power = if ($Unit) { [array]::IndexOf($units, $Unit) } else { Get-AACByteUnit -Bytes $Bytes -AsPower }
    if ($power -eq 0) { return ('{0:N0} B' -f $Bytes) }
    ("{0:N$Decimals} {1}" -f ($Bytes / [Math]::Pow(1024, $power)), $units[$power])
}
