function ConvertFrom-AACQueryString {
    <#
    .SYNOPSIS
        Parses a URL query string into a hashtable, without any System.Web dependency.
    .DESCRIPTION
        System.Web.HttpUtility isn't part of the default PowerShell 7 / .NET
        runtime, so the OAuth redirect's query string (e.g. "?code=...&state=...")
        is parsed by hand here using only System.Uri, which is always available.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyString()]
        [string] $Query
    )

    $result = @{}
    $trimmed = $Query.TrimStart('?')
    if ([string]::IsNullOrEmpty($trimmed)) {
        return $result
    }

    foreach ($pair in $trimmed -split '&') {
        if ([string]::IsNullOrEmpty($pair)) {
            continue
        }
        $parts = $pair -split '=', 2
        $key = [System.Uri]::UnescapeDataString($parts[0])
        $value = if ($parts.Count -gt 1) { [System.Uri]::UnescapeDataString($parts[1]) } else { '' }
        $result[$key] = $value
    }

    return $result
}
