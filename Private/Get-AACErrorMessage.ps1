function Get-AACErrorMessage {
    <#
    .SYNOPSIS
        Azure's own reason from an error response body - error.message, the
        nested innererror detail the query APIs give and the details list
        Resource Graph gives (where its real reason is: the top message is
        only "Please provide below info when asking for support"), or a
        top-level message; Azure Storage's XML error as 'Code: message' -
        else -Fallback.
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
                $support = [System.Collections.Generic.List[string]]::new()
                # The error, its innererror chain, and its details - each of
                # which can have its own - depth first.
                $pending = [System.Collections.Generic.Stack[object]]::new()
                $pending.Push($parsed['error'])
                while ($pending.Count) {
                    $level = $pending.Pop()
                    if ($level -isnot [System.Collections.IDictionary]) { continue }
                    $text = ([string]$level['message']).Trim()
                    # Resource Graph's "Please provide below info..." is for a
                    # support call, not the reason: last.
                    if ($text -match '^Please provide below info') { if (-not $support.Contains($text)) { $support.Add($text) } }
                    elseif ($text -and -not $messages.Contains($text)) { $messages.Add($text) }
                    $children = @(@($level['details']) + @($level['innererror']) | Where-Object { $_ -is [System.Collections.IDictionary] })
                    for ($i = $children.Count - 1; $i -ge 0; $i--) { $pending.Push($children[$i]) }
                }
                return (@($messages) + @($support)) -join ' '
            }
            if ($parsed -is [System.Collections.IDictionary] -and $parsed['message']) {
                return [string]$parsed['message']
            }
        }
        catch { Write-Debug "The error body is not JSON: $Content" }
    }
    $Fallback
}
