function Get-AACErrorMessage {
    <#
    .SYNOPSIS
        Azure's own reason from an error response body - error.message and
        the nested innererror detail the query APIs give, or a top-level
        message - else -Fallback.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()]
        [string] $Content,

        [string] $Fallback
    )

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
