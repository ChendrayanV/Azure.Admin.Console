function Invoke-AACHttpBatch {
    <#
    .SYNOPSIS
        Sends many Azure requests at once - up to -ThrottleLimit in flight -
        each followed through its pages, and says which failed.
    .DESCRIPTION
        The engine under Invoke-AACGraphBatch (Resource Graph) and
        Invoke-AACCostBatch (Cost Management). -Request is a list of
        @{ Key; Uri; Body } (POST with a JSON body, or GET without one); a
        path starting with '/' goes to https://management.azure.com.

        For every successful response -OnResponse is called with (key,
        response text) and returns the next page's request - @{ Uri; Body } -
        or nothing when that key is done. -OnDone is called with (key, error
        message; empty when it succeeded, done, total) as each key finishes.

        Throttling (429), server errors (5xx) and dropped connections are
        retried up to four times per page, waiting as long as Azure's retry
        headers ask (Get-AACRetryDelay); anything else fails that key with
        Azure's own reason (Get-AACErrorMessage), and the others carry on.

        Returns a hashtable: key -> error message ('' when it succeeded).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Request,

        [Parameter(Mandatory)]
        [scriptblock] $OnResponse,

        [scriptblock] $OnDone,

        [ValidateRange(1, 64)]
        [int] $ThrottleLimit = 4,

        # The token audience (Get-AACAccessToken -Resource), e.g.
        # https://graph.microsoft.com for Microsoft Graph.
        [string] $Resource = 'https://management.azure.com'
    )

    $errors = @{}
    $queue = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $Request) {
        $errors[$item.Key] = ''
        $queue.Add(@{ Key = $item.Key; Uri = [string]$item.Uri; Body = $item.Body; Attempt = 1; NotBefore = [datetime]::MinValue; Task = $null })
    }
    $total = $queue.Count
    $done = 0
    $inflight = [System.Collections.Generic.List[object]]::new()

    while ($queue.Count -or $inflight.Count) {
        $now = [datetime]::UtcNow
        for ($i = 0; $i -lt $queue.Count -and $inflight.Count -lt $ThrottleLimit; ) {
            $job = $queue[$i]
            if ($job.NotBefore -gt $now) { $i++; continue }
            $queue.RemoveAt($i)
            # A request that can't even be sent (no token, a bad URL) is a
            # failed task like any other - retried, then reported.
            try {
                $send = @{ Method = $(if ($null -ne $job.Body) { 'Post' } else { 'Get' }); Uri = $job.Uri; Token = (Get-AACAccessToken -Resource $Resource) }
                if ($null -ne $job.Body) { $send.Body = [string]$job.Body }
                $job.Task = Send-AACHttpRequest @send
                if ($null -eq $job.Task) { throw 'The request could not be sent.' }
            }
            catch {
                $source = [System.Threading.Tasks.TaskCompletionSource[System.Net.Http.HttpResponseMessage]]::new()
                $source.SetException([System.InvalidOperationException]::new([string]$_.Exception.Message))
                $job.Task = $source.Task
            }
            $inflight.Add($job)
        }
        if (-not $inflight.Count) {
            # Everything left is waiting out a retry.
            $wait = ($queue | ForEach-Object { $_.NotBefore } | Measure-Object -Minimum).Minimum - [datetime]::UtcNow
            if ($wait.TotalMilliseconds -gt 0) { Start-Sleep -Milliseconds ([Math]::Min(60000, [int]$wait.TotalMilliseconds + 50)) }
            continue
        }
        $index = [System.Threading.Tasks.Task]::WaitAny([System.Threading.Tasks.Task[]]@($inflight | ForEach-Object { $_.Task }), 1000)
        if ($index -lt 0) { continue }
        $job = $inflight[$index]
        $inflight.RemoveAt($index)

        $response = $null
        $status = 0
        $content = ''
        $failure = ''
        if ($job.Task.IsFaulted -or $job.Task.IsCanceled) {
            $failure = if ($job.Task.Exception) { $job.Task.Exception.GetBaseException().Message } else { 'the request was cancelled' }
        }
        else {
            $response = $job.Task.Result
            $status = [int]$response.StatusCode
            $content = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        }
        try {
            if (($status -eq 0 -or $status -eq 429 -or $status -ge 500) -and $job.Attempt -lt 5) {
                $job.NotBefore = [datetime]::UtcNow.AddSeconds((Get-AACRetryDelay -Response $response -Status $status -Attempt $job.Attempt))
                $job.Attempt++
                $queue.Add($job)
                continue
            }
            $message = ''
            if ($status -ge 200 -and $status -lt 300) {
                try {
                    $next = & $OnResponse $job.Key $content
                }
                catch {
                    $next = $null
                    $message = "The response couldn't be read: $($_.Exception.Message)"
                }
                if ($next -is [System.Collections.IDictionary] -and $next['Uri']) {
                    $job.Uri = [string]$next['Uri']
                    $job.Body = $next['Body']
                    $job.Attempt = 1
                    $queue.Add($job)
                    continue
                }
            }
            else {
                $message = Get-AACErrorMessage -Content $content -Fallback $(if ($failure) { $failure } else { "Response status code does not indicate success: $status ($($response.ReasonPhrase))." })
            }
            $errors[$job.Key] = $message
            $done++
            if ($OnDone) { & $OnDone $job.Key $message $done $total }
        }
        finally {
            if ($response) { $response.Dispose() }
        }
    }
    $errors
}
