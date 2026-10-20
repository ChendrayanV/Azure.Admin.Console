function Invoke-AACArmOperationBatch {
    <#
    .SYNOPSIS
        Runs several Azure Resource Manager long-running actions at once:
        each POST submitted, then every operation polled until it succeeds
        or fails - Export-AACTerraform's exports, split in batches and run
        side by side.
    .DESCRIPTION
        Invoke-AACArmWrite follows one operation at a time; a wait of minutes
        per export adds up. Here at most -ThrottleLimit operations run at
        once: as one finishes, the next is submitted. Each is polled when its
        own Retry-After says (5 seconds otherwise, never more than 60), so a
        slow one doesn't hold the others back.

        -Request takes @{ Key; Uri; Body } - or @{ Key; OperationUrl } to
        pick up an operation submitted earlier (Export-AACTerraform -Resume):
        it is polled, not submitted again.

        Callbacks, so the caller can show progress and save what it needs:
          -OnSubmitted  (Key, OperationUrl)   as soon as Azure accepted it
          -OnPoll       (Key, Status, Percent) after each poll still running
          -OnDone       (Key, Succeeded, Error) when it ends

        Returns an ordered dictionary, Key -> @{ Succeeded; Result (the
        final operation status, hashtables); Error; OperationUrl; TimedOut
        (still running at -TimeoutMinutes: it can be polled again later) }. A failure
        - submitted or polled - is that request's Error, never a throw, so
        one failed batch doesn't lose the others. An operation Azure no
        longer knows (404: it expired) says so.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Request,

        [ValidateRange(1, 50)]
        [int] $ThrottleLimit = 8,

        [ValidateRange(1, 240)]
        [int] $TimeoutMinutes = 30,

        [scriptblock] $OnSubmitted,

        [scriptblock] $OnPoll,

        [scriptblock] $OnDone
    )

    $results = [ordered]@{}
    $queue = [System.Collections.Generic.Queue[object]]::new()
    foreach ($item in $Request) { $queue.Enqueue($item) }
    $active = [System.Collections.Generic.List[hashtable]]::new()
    $parse = { param([string] $Text) if ([string]::IsNullOrWhiteSpace($Text)) { @{} } else { ConvertFrom-Json -InputObject $Text -AsHashtable -Depth 100 } }
    $retryAfter = {
        param($Headers)
        $seconds = 5
        if ($Headers -and $Headers.ContainsKey('Retry-After')) { $parsed = 0; if ([int]::TryParse([string]$Headers['Retry-After'], [ref]$parsed)) { $seconds = [Math]::Min([Math]::Max($parsed, 1), 60) } }
        $seconds
    }
    $finish = {
        param([string] $Key, [bool] $Succeeded, $Result, [string] $ErrorText, [string] $OperationUrl, [bool] $TimedOut = $false)
        $results[$Key] = @{ Succeeded = $Succeeded; Result = $Result; Error = $ErrorText; OperationUrl = $OperationUrl; TimedOut = $TimedOut }
        if ($OnDone) { & $OnDone $Key $Succeeded $ErrorText }
    }
    # Succeeded, Failed or Canceled ends it; anything else (InProgress, Running, Accepted...) is still going.
    $judge = {
        param([string] $Key, [System.Collections.IDictionary] $State, [string] $OperationUrl)
        $status = [string]$State['status']
        if ($status -in 'Failed', 'Canceled') {
            $reason = if ($State['error'] -is [System.Collections.IDictionary]) { "$($State['error']['code']): $($State['error']['message'])" } else { $status }
            & $finish $Key $false $State "Azure couldn't finish the operation - $reason" $OperationUrl
            return $true
        }
        if (-not $status -or $status -eq 'Succeeded') { & $finish $Key $true $State '' $OperationUrl; return $true }
        $false
    }

    while ($queue.Count -or $active.Count) {
        # Submit while there is room.
        while ($queue.Count -and $active.Count -lt $ThrottleLimit) {
            $item = $queue.Dequeue()
            $key = [string]$item.Key
            $now = [datetime]::UtcNow
            if ($item.Contains('OperationUrl') -and $item.OperationUrl) {
                $active.Add(@{ Key = $key; Url = [string]$item.OperationUrl; Location = $false; Next = $now; Deadline = $now.AddMinutes($TimeoutMinutes) })
                continue
            }
            try {
                $response = Invoke-AACHttp -Method Post -Uri $item.Uri -Body (ConvertTo-Json -InputObject $item.Body -Depth 50 -Compress)
                $headers = $response.Headers
                $url = ''; $location = $false
                if ($response.Status -in 201, 202 -and $headers -and $headers.ContainsKey('Azure-AsyncOperation')) { $url = [string]$headers['Azure-AsyncOperation'] }
                elseif ($response.Status -eq 202 -and $headers -and $headers.ContainsKey('Location')) { $url = [string]$headers['Location']; $location = $true }
                if (-not $url) { $null = & $judge $key (& $parse $response.Content) ''; continue }
                if ($OnSubmitted) { & $OnSubmitted $key $url }
                $active.Add(@{ Key = $key; Url = $url; Location = $location; Next = $now.AddSeconds((& $retryAfter $headers)); Deadline = $now.AddMinutes($TimeoutMinutes) })
            }
            catch { & $finish $key $false $null $_.Exception.Message '' }
        }
        if (-not $active.Count) { continue }

        # Wait for the operation due first, then poll every one that is due.
        $soonest = ($active | ForEach-Object { $_.Next } | Measure-Object -Minimum).Minimum
        $wait = [int][Math]::Ceiling(($soonest - [datetime]::UtcNow).TotalMilliseconds)
        if ($wait -gt 0) { Start-Sleep -Milliseconds ([Math]::Min($wait, 60000)) }
        $ended = [System.Collections.Generic.List[hashtable]]::new()
        foreach ($operation in @($active)) {
            $now = [datetime]::UtcNow
            # Due: everything whose time had come by the end of the wait.
            if ($operation.Next -gt $soonest) { continue }
            if ($now -gt $operation.Deadline) { & $finish $operation.Key $false $null "Azure didn't finish within $TimeoutMinutes minute(s). It may still be running." $operation.Url $true; $ended.Add($operation); continue }
            try {
                $poll = Invoke-AACHttp -Uri $operation.Url
                if ($operation.Location) {
                    if ($poll.Status -ne 202) { & $finish $operation.Key $true (& $parse $poll.Content) '' $operation.Url; $ended.Add($operation); continue }
                    if ($OnPoll) { & $OnPoll $operation.Key 'InProgress' $null }
                }
                else {
                    $state = & $parse $poll.Content
                    if (& $judge $operation.Key $state $operation.Url) { $ended.Add($operation); continue }
                    if ($OnPoll) { & $OnPoll $operation.Key ([string]$state['status']) $(if ($null -ne $state['percentComplete']) { [double]$state['percentComplete'] }) }
                }
                $operation.Next = [datetime]::UtcNow.AddSeconds((& $retryAfter $poll.Headers))
            }
            catch {
                $message = if ([int]$_.Exception.Data['StatusCode'] -eq 404) { 'Azure no longer has this operation (it expired, or was never accepted). Run the export again.' } else { $_.Exception.Message }
                & $finish $operation.Key $false $null $message $operation.Url
                $ended.Add($operation)
            }
        }
        foreach ($operation in $ended) { $null = $active.Remove($operation) }
    }
    $results
}
