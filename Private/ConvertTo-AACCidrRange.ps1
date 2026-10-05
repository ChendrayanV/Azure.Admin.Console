function ConvertTo-AACCidrRange {
    <#
    .SYNOPSIS
        IPv4 CIDR arithmetic for the virtual network assessment: a prefix's
        range and size, and the free blocks left in an address space.
    .DESCRIPTION
        -Prefix '10.0.0.0/16' returns @{ Prefix; Version = 4; Start; End;
        Size; Length; Valid } - Start and End as integers (so ranges can be
        compared), Size the number of addresses (65,536). An IPv6 prefix
        returns Version 6 with no range (Azure's IPv6 subnets are /64: their
        size isn't a useful number), and anything else Valid = $false.

        -Space with -Used returns the free blocks of the -Space prefixes
        that no -Used prefix covers, each as the largest aligned CIDR blocks
        that fit ('10.0.4.0/22', '10.0.8.0/21'...), largest first per gap -
        the subnets that could still be added.

        -Format turns a start and length back into 'a.b.c.d/n'.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Prefix')]
    [OutputType([hashtable], [object[]], [string])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Prefix', Position = 0)]
        [AllowEmptyString()]
        [string] $Prefix,

        [Parameter(Mandatory, ParameterSetName = 'Free')]
        [AllowEmptyCollection()]
        [string[]] $Space,

        [Parameter(ParameterSetName = 'Free')]
        [AllowEmptyCollection()]
        [string[]] $Used = @(),

        [Parameter(Mandatory, ParameterSetName = 'Format')]
        [long] $Start,

        [Parameter(Mandatory, ParameterSetName = 'Format')]
        [int] $Length
    )

    $toText = { param([long] $Value) '{0}.{1}.{2}.{3}' -f (($Value -shr 24) -band 255), (($Value -shr 16) -band 255), (($Value -shr 8) -band 255), ($Value -band 255) }
    if ($PSCmdlet.ParameterSetName -eq 'Format') { return "$(& $toText $Start)/$Length" }

    $parse = {
        param([string] $Text)
        $text = $Text.Trim()
        if ($text -match '^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(/(\d{1,2}))?$') {
            $octets = @([int]$Matches[1], [int]$Matches[2], [int]$Matches[3], [int]$Matches[4])
            $bits = if ($Matches[6]) { [int]$Matches[6] } else { 32 }
            if (@($octets | Where-Object { $_ -gt 255 }).Count -or $bits -gt 32) { return @{ Prefix = $text; Version = 4; Valid = $false } }
            $value = ([long]$octets[0] -shl 24) + ([long]$octets[1] -shl 16) + ([long]$octets[2] -shl 8) + [long]$octets[3]
            $size = [long][Math]::Pow(2, 32 - $bits)
            $first = $value - ($value % $size)
            return @{ Prefix = $text; Version = 4; Start = $first; End = $first + $size - 1; Size = $size; Length = $bits; Valid = $true }
        }
        if ($text -match ':') { return @{ Prefix = $text; Version = 6; Start = $null; End = $null; Size = $null; Length = $(if ($text -match '/(\d+)$') { [int]$Matches[1] } else { 128 }); Valid = $true } }
        @{ Prefix = $text; Version = 0; Valid = $false }
    }
    if ($PSCmdlet.ParameterSetName -eq 'Prefix') { return & $parse $Prefix }

    # --- Free blocks: each space minus what is used, as aligned CIDRs ------------------------------------------
    $taken = @($Used | ForEach-Object { & $parse $_ } | Where-Object { $_.Valid -and $_.Version -eq 4 } | Sort-Object { $_.Start })
    $free = [System.Collections.Generic.List[object]]::new()
    foreach ($range in @($Space | ForEach-Object { & $parse $_ } | Where-Object { $_.Valid -and $_.Version -eq 4 })) {
        $cursor = $range.Start
        $gaps = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $taken) {
            if ($item.End -lt $range.Start -or $item.Start -gt $range.End) { continue }
            if ($item.Start -gt $cursor) { $gaps.Add(@($cursor, [Math]::Min($item.Start - 1, $range.End))) }
            $cursor = [Math]::Max($cursor, $item.End + 1)
        }
        if ($cursor -le $range.End) { $gaps.Add(@($cursor, $range.End)) }
        foreach ($gap in $gaps) {
            # The largest aligned block at the gap's start, again and again.
            $at = [long]$gap[0]
            $blocks = [System.Collections.Generic.List[object]]::new()
            while ($at -le $gap[1]) {
                $bits = 32
                while ($bits -gt 0) {
                    $size = [long][Math]::Pow(2, 32 - ($bits - 1))
                    if (($at % $size) -ne 0 -or ($at + $size - 1) -gt $gap[1]) { break }
                    $bits--
                }
                $size = [long][Math]::Pow(2, 32 - $bits)
                $blocks.Add([pscustomobject]@{ Space = $range.Prefix; Prefix = "$(& $toText $at)/$bits"; Length = $bits; Size = $size; Start = $at })
                $at += $size
            }
            foreach ($block in $blocks | Sort-Object Size -Descending) { $free.Add($block) }
        }
    }
    $free.ToArray()
}
