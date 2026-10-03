function Invoke-AACArmWrite {
    <#
    .SYNOPSIS
        Creates, updates or deletes one Azure Resource Manager resource with
        PUT, PATCH or DELETE, and waits for Azure to finish - the write path
        of Deploy-AACStorageAccount.
    .DESCRIPTION
        Sends the request through Invoke-AACHttp (retries, Azure's reasons).
        A long-running operation - 201 or 202, with an Azure-AsyncOperation
        or Location header - is followed until Azure says it is done:
          Azure-AsyncOperation   polled until status is Succeeded, Failed
                                 or Canceled; Failed and Canceled throw
                                 with Azure's error
          Location               polled until it stops answering 202
        honouring Retry-After (5 seconds otherwise), for at most
        -TimeoutMinutes. Then, for PUT and PATCH, the resource is read
        again and returned (hashtables), so the caller sees what Azure made
        of it; DELETE returns nothing.

        A failure throws with Azure's message, and Data['Code']
        (RequestDisallowedByPolicy when a policy denied it) and
        Data['StatusCode'].
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Put', 'Patch', 'Delete')]
        [string] $Method,

        # The resource's path with its api-version, as for Invoke-AACArmRequest.
        [Parameter(Mandatory)]
        [string] $Uri,

        [System.Collections.IDictionary] $Body,

        [ValidateRange(1, 120)]
        [int] $TimeoutMinutes = 30
    )

    $request = @{ Method = $Method; Uri = $Uri }
    if ($Body) { $request.Body = ConvertTo-Json -InputObject $Body -Depth 50 -Compress }
    $response = Invoke-AACHttp @request
    $deadline = [datetime]::UtcNow.AddMinutes($TimeoutMinutes)
    $wait = {
        param($Headers)
        $seconds = 5
        if ($Headers -and $Headers.ContainsKey('Retry-After')) { $parsed = 0; if ([int]::TryParse([string]$Headers['Retry-After'], [ref]$parsed)) { $seconds = [Math]::Min([Math]::Max($parsed, 1), 60) } }
        if ([datetime]::UtcNow.AddSeconds($seconds) -gt $deadline) { throw "Azure didn't finish $($Method.ToUpperInvariant()) $Uri within $TimeoutMinutes minute(s)." }
        Start-Sleep -Seconds $seconds
    }

    if ($response.Status -in 201, 202 -and $response.Headers) {
        if ($response.Headers.ContainsKey('Azure-AsyncOperation')) {
            $operation = [string]$response.Headers['Azure-AsyncOperation']
            $headers = $response.Headers
            while ($true) {
                & $wait $headers
                $poll = Invoke-AACHttp -Uri $operation
                $headers = $poll.Headers
                $state = if ($poll.Content) { ConvertFrom-Json -InputObject $poll.Content -AsHashtable -Depth 50 } else { @{} }
                $status = [string]$state['status']
                if ($status -eq 'Succeeded') { break }
                if ($status -in 'Failed', 'Canceled') {
                    $reason = if ($state['error'] -is [System.Collections.IDictionary]) { "$($state['error']['code']): $($state['error']['message'])" } else { $status }
                    $exception = [System.Exception]::new("Azure couldn't $($Method.ToLowerInvariant()) $Uri - $reason")
                    $exception.Data['Code'] = $(if ($state['error'] -is [System.Collections.IDictionary]) { [string]$state['error']['code'] } else { $status })
                    throw $exception
                }
            }
        }
        elseif ($response.Headers.ContainsKey('Location') -and $response.Status -eq 202) {
            $location = [string]$response.Headers['Location']
            $headers = $response.Headers
            while ($true) {
                & $wait $headers
                $poll = Invoke-AACHttp -Uri $location
                $headers = $poll.Headers
                if ($poll.Status -ne 202) { break }
            }
        }
    }

    if ($Method -eq 'Delete') { return }
    Invoke-AACArmRequest -Uri $Uri
}
