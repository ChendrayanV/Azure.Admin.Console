function Get-AACErrorMessage {
    <#
    .SYNOPSIS
        Azure's own reason from an error response body - error.message and
        the nested innererror detail the query APIs give, or a top-level
        message; Azure Storage's XML error as 'Code: message' - else
        -Fallback.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()]
        [string] $Content,

        [string] $Fallback
    )

    # Azure Storage answers in XML: <Error><Code>..</Code><Message>..
    # RequestId:..</Message></Error>. The code goes first - it says what to
    # do (AuthorizationPermissionMismatch: a data role is missing).
    if ($Content -and $Content.TrimStart([char]0xFEFF, ' ', "`r", "`n", "`t").StartsWith('<')) {
        $code = if ($Content -match '<Code>([^<]*)</Code>') { $Matches[1].Trim() } else { '' }
        $text = if ($Content -match '(?s)<Message>([^<]*)</Message>') { ($Matches[1] -split '\r?\n')[0].Trim() } else { '' }
        $text = [System.Net.WebUtility]::HtmlDecode($text)
        if ($code -and $text) { return "${code}: $text" }
        if ($code -or $text) { return "$code$text" }
    }
    if ($Content) {
        try {
            $parsed = ConvertFrom-Json -InputObject $Content -AsHashtable -ErrorAction Stop
            if ($parsed -is [System.Collections.IDictionary] -and $parsed['error'] -is [System.Collections.IDictionary] -and $parsed['error']['message']) {
                $messages = [System.Collections.Generic.List[string]]::new()
                for ($level = $parsed['error']; $level -is [System.Collections.IDictionary]; $level = $level['innererror']) {
                    $text = ([string]$level['message']).Trim()
                    if ($text -and -not $messages.Contains($text)) { $messages.Add($text) }
                }
                return ($messages -join ' ')
            }
            if ($parsed -is [System.Collections.IDictionary] -and $parsed['message']) {
                return [string]$parsed['message']
            }
        }
        catch { Write-Debug "The error body is not JSON: $Content" }
    }
    $Fallback
}
