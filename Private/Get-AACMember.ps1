function Get-AACMember {
    <#
    .SYNOPSIS
        Reads a value out of parsed JSON by a dotted path ('properties.status.code'),
        ignoring the case of the keys.
    .DESCRIPTION
        ConvertFrom-Json -AsHashtable keeps keys case-sensitive, and Azure isn't
        consistent about case (AzureResourceId and azureResourceId both turn up).
        Each step tries the exact key first and only then looks for one that
        differs in case. Anything that isn't a dictionary along the way gives
        $null.

        A plain function on purpose: converters call it for every value they read,
        and an advanced function's parameter binding costs several times more.
    #>
    param($InputObject, [string] $Path)

    foreach ($part in $Path.Split('.')) {
        if ($InputObject -isnot [System.Collections.IDictionary]) { return $null }
        if ($InputObject.Contains($part)) { $InputObject = $InputObject[$part]; continue }
        $found = $null
        foreach ($key in $InputObject.Keys) { if ($key -eq $part) { $found = $InputObject[$key]; break } }
        $InputObject = $found
    }
    $InputObject
}
