function Invoke-AACArmParallel {
    <#
    .SYNOPSIS
        Sends many Azure Resource Manager GET requests at once - up to
        -ThrottleLimit in flight - over one pooled HTTPS connection, and
        returns each one's result by its URI.
    .DESCRIPTION
        One call per URI, in parallel: reading hundreds of child resources
        (an API Management service's APIs, operations and policies, say)
        takes seconds instead of minutes. For each URI:
          - a list ('value') is read to the end, following nextLink
          - throttling (429) and server errors (5xx) are retried up to four
            times, waiting as long as Retry-After asks (5-60 seconds
            otherwise); dropped connections are retried after a second or two
          - any other failure is kept with its HTTP status and ARM's own
            error message, as Invoke-AACArmRequest reports it

        Returns a hashtable: URI -> @{ Status (the HTTP status, 0 without a
        response); Body (the first response, as hashtables); Items (every
        'value' item across the pages, or $null when it isn't a list);
        Error (the message, when it failed) }.

        The requests share one HttpClient for the session (connections are
        reused rather than a TLS handshake per call) and each carries a
        current Connect-AAC token (Get-AACAccessToken). -OnProgress is called
        with (done, total) as requests finish. -Send replaces the HTTP call,
        for tests: it takes (URI, token) and returns a
        Task[HttpResponseMessage].
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Uri,

        [ValidateRange(1, 64)]
        [int] $ThrottleLimit = 12,

        [scriptblock] $OnProgress,

        [scriptblock] $Send
    )

    $results = @{}
    $unique = @($Uri | Where-Object { $_ } | Select-Object -Unique)
    if (-not $unique.Count) { return $results }

    if (-not $Send) {
        $Send = { param([string] $Target, [string] $Token) Send-AACHttpRequest -Uri $Target -Token $Token }
    }
    $absolute = { param([string] $Target) if ($Target.StartsWith('/')) { "https://management.azure.com$Target" } else { $Target } }
    # A job is one request: the URI it answers for, the URL to send (a
    # nextLink for later pages), its attempt and when it may be sent.
    $queue = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $unique) {
        $results[$item] = @{ Status = 0; Body = $null; Items = $null; Error = '' }
        $queue.Add(@{ Key = $item; Target = (& $absolute $item); Attempt = 1; NotBefore = [datetime]::MinValue })
    }
    $total = $queue.Count
    $done = 0
    $inflight = [System.Collections.Generic.List[object]]::new()

    while ($queue.Count -or $inflight.Count) {
        # Fill up to the limit with the jobs that may go now.
        $now = [datetime]::UtcNow
        for ($i = 0; $i -lt $queue.Count -and $inflight.Count -lt $ThrottleLimit; ) {
            $job = $queue[$i]
            if ($job.NotBefore -gt $now) { $i++; continue }
            $queue.RemoveAt($i)
            # A request that can't even be sent (no token, a bad URL) is a
            # failed task like any other - retried, then reported.
            try {
                $job.Task = & $Send $job.Target (Get-AACAccessToken)
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
            # Everything left is waiting out a Retry-After.
            $wait = ($queue | ForEach-Object { $_.NotBefore } | Measure-Object -Minimum).Minimum - [datetime]::UtcNow
            if ($wait.TotalMilliseconds -gt 0) { Start-Sleep -Milliseconds ([Math]::Min(60000, [int]$wait.TotalMilliseconds + 50)) }
            continue
        }
        $index = [System.Threading.Tasks.Task]::WaitAny([System.Threading.Tasks.Task[]]@($inflight | ForEach-Object { $_.Task }), 1000)
        if ($index -lt 0) { continue }
        $job = $inflight[$index]
        $inflight.RemoveAt($index)
        $result = $results[$job.Key]

        $response = $null
        $content = ''
        $status = 0
        if ($job.Task.IsFaulted -or $job.Task.IsCanceled) {
            $failure = if ($job.Task.Exception) { $job.Task.Exception.GetBaseException().Message } else { 'the request was cancelled' }
        }
        else {
            $response = $job.Task.Result
            $status = [int]$response.StatusCode
            $content = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $failure = ''
        }

        # Retry throttling, server errors and dropped connections.
        if (($status -eq 429 -or $status -ge 500 -or $status -eq 0) -and $job.Attempt -lt 5) {
            # A dropped connection (no response) is retried soon; throttling
            # and server errors wait longer, or as long as Azure asks.
            $delay = Get-AACRetryDelay -Response $response -Status $status -Attempt $job.Attempt
            if ($response) { $response.Dispose() }
            $job.Attempt++
            $job.NotBefore = [datetime]::UtcNow.AddSeconds($delay)
            $job.Task = $null
            $queue.Add($job)
            continue
        }
        if ($response) { $response.Dispose() }

        if ($status -ge 200 -and $status -lt 300) {
            $body = if ([string]::IsNullOrWhiteSpace($content)) { $null } else { ConvertFrom-Json -InputObject $content -AsHashtable -Depth 100 }
            if ($null -eq $result.Body) { $result.Body = $body; $result.Status = $status }
            if ($body -is [System.Collections.IDictionary] -and $body.Contains('value')) {
                if ($null -eq $result.Items) { $result.Items = [System.Collections.Generic.List[object]]::new() }
                foreach ($item in @($body['value'])) { if ($null -ne $item) { $result.Items.Add($item) } }
                $next = [string]$body['nextLink']
                if ($next) {
                    $queue.Add(@{ Key = $job.Key; Target = $next; Attempt = 1; NotBefore = [datetime]::MinValue })
                    $total++
                }
            }
        }
        else {
            $result.Status = $status
            $result.Error = if ($failure) { $failure } else { Get-AACErrorMessage -Content $content -Fallback "HTTP $status" }
        }
        $done++
        if ($OnProgress) { & $OnProgress $done $total }
    }
    $results
}
