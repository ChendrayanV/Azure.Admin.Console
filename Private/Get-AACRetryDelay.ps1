function Get-AACRetryDelay {
    <#
    .SYNOPSIS
        How many seconds to wait before retrying a throttled (429), failed
        (5xx) or dropped (no response) Azure call.
    .DESCRIPTION
        The longest wait any header asks for: Retry-After (seconds or a
        date), Cost Management's x-ms-ratelimit-...-retry-after, Resource
        Graph's x-ms-user-quota-resets-after (hh:mm:ss). Without one: a
        dropped connection waits -Attempt seconds, anything else 5 x
        -Attempt. Never more than 60 seconds.
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [System.Net.Http.HttpResponseMessage] $Response,

        [int] $Status,

        [int] $Attempt = 1
    )

    $wait = 0.0
    if ($Response) {
        $retryAfter = $Response.Headers.RetryAfter
        # (PowerShell unwraps the nullable Delta and Date.)
        if ($retryAfter -and $null -ne $retryAfter.Delta) { $wait = ([TimeSpan]$retryAfter.Delta).TotalSeconds }
        elseif ($retryAfter -and $null -ne $retryAfter.Date) { $wait = (([datetimeoffset]$retryAfter.Date).UtcDateTime - [datetime]::UtcNow).TotalSeconds }
        foreach ($header in $Response.Headers) {
            foreach ($value in $header.Value) {
                $seconds = 0
                $span = [TimeSpan]::Zero
                if ($header.Key -match 'retry-after$' -and [int]::TryParse($value, [ref]$seconds)) { $wait = [Math]::Max($wait, $seconds) }
                elseif ($header.Key -match 'resets-after$' -and [TimeSpan]::TryParse($value, [cultureinfo]::InvariantCulture, [ref]$span)) { $wait = [Math]::Max($wait, $span.TotalSeconds) }
            }
        }
    }
    if ($wait -le 0) { $wait = if ($Status -eq 0) { $Attempt } else { 5 * $Attempt } }
    [Math]::Min(60, [Math]::Max(1, $wait))
}
