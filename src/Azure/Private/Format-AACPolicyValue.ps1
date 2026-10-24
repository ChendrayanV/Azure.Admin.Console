function Format-AACPolicyValue {
    <#
    .SYNOPSIS
        A policy parameter's value as text: a list's items joined with ', ',
        an object as compact JSON, a boolean as true or false, nothing as ''.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value) { return '' }
    if ($Value -is [string]) { return $Value }
    if ($Value -is [bool]) { return $Value.ToString().ToLowerInvariant() }
    if ($Value -is [System.Collections.IDictionary]) { return (ConvertTo-Json -InputObject $Value -Compress -Depth 20) }
    if ($Value -is [System.Collections.IList]) {
        return (@(foreach ($item in $Value) { if ($item -is [System.Collections.IDictionary] -or $item -is [System.Collections.IList]) { ConvertTo-Json -InputObject $item -Compress -Depth 20 } else { Format-AACPolicyValue -Value $item } }) -join ', ')
    }
    [string]::Format([cultureinfo]::InvariantCulture, '{0}', $Value)
}
