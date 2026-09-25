function ConvertTo-AACColor {
    <#
    .SYNOPSIS
        Converts a Spectre color name (e.g. "green1", "deepskyblue3_1") to a
        [Spectre.Console.Color] object.
    .DESCRIPTION
        Spectre.Console.Color has no direct Parse(string) method, but
        [Spectre.Console.Style]::Parse(name).Foreground resolves the same
        named-color table Spectre markup itself uses, so that is used here
        rather than hand-maintaining a name-to-Color lookup.
    #>
    [CmdletBinding()]
    [OutputType([Spectre.Console.Color])]
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    return [Spectre.Console.Style]::Parse($Name).Foreground
}
