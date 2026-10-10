function Invoke-AACEndpointProbe {
    <#
    .SYNOPSIS
        Probes endpoints - HTTP(S) requests and TCP connections - all at
        once, -Round times, and returns each attempt's outcome and latency.
    .DESCRIPTION
        -Probe: @{ Key; Kind = 'Http' or 'Tcp'; Uri (Http); Host and Port
        (Tcp); Method ('GET'); ExpectedStatus (an int[], or 'Below500' - up
        unless the server errs); Contains (text the body must have);
        TimeoutSeconds (10) }.

        HTTP requests go through an HttpClient of their own - never the one
        that carries the Azure token, so no credential reaches the endpoint -
        with a user agent of Azure.Admin.Console-HealthCheck. Each attempt
        is timed from the start of its round to when it completes. Rounds
        are -IntervalSeconds apart.

        Returns a hashtable: Key -> @( @{ Ok; Status (the HTTP status, or 0);
        LatencyMs; Error } per round ).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Probe,

        [ValidateRange(1, 100)]
        [int] $Round = 1,

        [ValidateRange(0, 3600)]
        [int] $IntervalSeconds = 5,

        [scriptblock] $OnRound
    )

    $results = @{}
    foreach ($p in $Probe) { $results[[string]$p.Key] = [System.Collections.Generic.List[object]]::new() }
    if (-not $Probe.Count) { return $results }
    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $true
    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [System.Threading.Timeout]::InfiniteTimeSpan
    $client.DefaultRequestHeaders.UserAgent.ParseAdd('Azure.Admin.Console-HealthCheck/1.0')
    try {
        for ($r = 1; $r -le $Round; $r++) {
            if ($r -gt 1 -and $IntervalSeconds) { Start-Sleep -Seconds $IntervalSeconds }
            $clock = [System.Diagnostics.Stopwatch]::StartNew()
            $pending = [System.Collections.Generic.List[object]]::new()
            foreach ($p in $Probe) {
                $timeout = if ($p.Contains('TimeoutSeconds') -and $p.TimeoutSeconds) { [int]$p.TimeoutSeconds } else { 10 }
                $cancel = [System.Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds($timeout))
                try {
                    if ($p.Kind -eq 'Tcp') {
                        $tcp = [System.Net.Sockets.TcpClient]::new()
                        $task = $tcp.ConnectAsync([string]$p.Host, [int]$p.Port, $cancel.Token).AsTask()
                        $pending.Add(@{ Probe = $p; Task = $task; Tcp = $tcp; Cancel = $cancel })
                    }
                    else {
                        $message = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($(if ($p.Contains('Method') -and $p.Method) { [string]$p.Method } else { 'GET' })), [string]$p.Uri)
                        $task = $client.SendAsync($message, [System.Net.Http.HttpCompletionOption]::ResponseContentRead, $cancel.Token)
                        $pending.Add(@{ Probe = $p; Task = $task; Cancel = $cancel })
                    }
                }
                catch { $results[[string]$p.Key].Add(@{ Ok = $false; Status = 0; LatencyMs = 0; Error = $_.Exception.Message }) ; $cancel.Dispose() }
            }
            while ($pending.Count) {
                $index = [System.Threading.Tasks.Task]::WaitAny([System.Threading.Tasks.Task[]]@($pending | ForEach-Object { $_.Task }), 1000)
                if ($index -lt 0) { continue }
                $done = $pending[$index]
                $pending.RemoveAt($index)
                $elapsed = [Math]::Round($clock.Elapsed.TotalMilliseconds)
                $p = $done.Probe
                $outcome = @{ Ok = $false; Status = 0; LatencyMs = $elapsed; Error = '' }
                if ($done.Task.IsFaulted -or $done.Task.IsCanceled) {
                    $outcome.Error = if ($done.Task.IsCanceled) { "no answer within $(if ($p.Contains('TimeoutSeconds') -and $p.TimeoutSeconds) { $p.TimeoutSeconds } else { 10 }) seconds" } else { $done.Task.Exception.GetBaseException().Message }
                }
                elseif ($p.Kind -eq 'Tcp') { $outcome.Ok = $true }
                else {
                    $response = $done.Task.Result
                    $outcome.Status = [int]$response.StatusCode
                    $expected = if ($p.Contains('ExpectedStatus') -and $p.ExpectedStatus) { $p.ExpectedStatus } else { @(200..399) }
                    $statusOk = if ($expected -eq 'Below500') { $outcome.Status -lt 500 } else { @($expected) -contains $outcome.Status }
                    $contentOk = $true
                    if ($p.Contains('Contains') -and $p.Contains) {
                        $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                        $contentOk = $body.Contains([string]$p.Contains)
                        if (-not $contentOk) { $outcome.Error = "the response doesn't contain '$($p.Contains)'" }
                    }
                    if (-not $statusOk) { $outcome.Error = "HTTP $($outcome.Status) $($response.ReasonPhrase)" }
                    $outcome.Ok = $statusOk -and $contentOk
                    $response.Dispose()
                }
                if ($done.Contains('Tcp')) { $done.Tcp.Dispose() }
                $done.Cancel.Dispose()
                $results[[string]$p.Key].Add($outcome)
            }
            if ($OnRound) { & $OnRound $r $Round }
        }
    }
    finally { $client.Dispose() }
    $results
}
