function Invoke-AACArmWrite {
    <#
    .SYNOPSIS
        Creates, updates or deletes one Azure Resource Manager resource with
        PUT, PATCH or DELETE - or runs an action with POST - and waits for
        Azure to finish: the write path of Deploy-AACStorageAccount, and the
        long-running actions such as Export-AACTerraform's export.
    .DESCRIPTION
        Sends the request through Invoke-AACHttp (retries, Azure's reasons).
        A long-running operation - 201 or 202, with an Azure-AsyncOperation
        or Location header - is followed until Azure says it is done:
          Azure-AsyncOperation   polled until status is Succeeded, Failed
                                 or Canceled; Failed and Canceled throw
                                 with Azure's error
          Location               polled until it stops answering 202
        honouring Retry-After (5 seconds otherwise), for at most
        -TimeoutMinutes. -OnProgress is called with each poll's
        percentComplete (when Azure gives one) and status.

        What comes back:
          PUT, PATCH  the resource read again (hashtables), so the caller
                      sees what Azure made of it
          DELETE      nothing
          POST        the action's result (hashtables): the body of a 200,
                      or the final operation status - for an action, the
                      result is in the operation status (its properties),
                      not in a resource to read again

        A failure throws with Azure's message, and Data['Code']
        (RequestDisallowedByPolicy when a policy denied it) and
        Data['StatusCode'].
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Put', 'Patch', 'Delete', 'Post')]
        [string] $Method,

        # The resource's path with its api-version, as for Invoke-AACArmRequest.
        [Parameter(Mandatory)]
        [string] $Uri,

        [System.Collections.IDictionary] $Body,

        [ValidateRange(1, 120)]
        [int] $TimeoutMinutes = 30,

        # Called with (percentComplete or $null, status) after each poll.
        [scriptblock] $OnProgress
    )

    $request = @{ Method = $Method; Uri = $Uri }
    if ($Body) { $request.Body = ConvertTo-Json -InputObject $Body -Depth 50 -Compress }
    elseif ($Method -eq 'Post') { $request.Body = '{}' }
    $response = Invoke-AACHttp @request
    $deadline = [datetime]::UtcNow.AddMinutes($TimeoutMinutes)
    $wait = {
        param($Headers)
        $seconds = 5
        if ($Headers -and $Headers.ContainsKey('Retry-After')) { $parsed = 0; if ([int]::TryParse([string]$Headers['Retry-After'], [ref]$parsed)) { $seconds = [Math]::Min([Math]::Max($parsed, 1), 60) } }
        if ([datetime]::UtcNow.AddSeconds($seconds) -gt $deadline) { throw "Azure didn't finish $($Method.ToUpperInvariant()) $Uri within $TimeoutMinutes minute(s)." }
        Start-Sleep -Seconds $seconds
    }
    $parse = { param([string] $Text) if ([string]::IsNullOrWhiteSpace($Text)) { @{} } else { ConvertFrom-Json -InputObject $Text -AsHashtable -Depth 100 } }
    $final = $null

    if ($response.Status -in 201, 202 -and $response.Headers) {
        if ($response.Headers.ContainsKey('Azure-AsyncOperation')) {
            $operation = [string]$response.Headers['Azure-AsyncOperation']
            $headers = $response.Headers
            while ($true) {
                & $wait $headers
                $poll = Invoke-AACHttp -Uri $operation
                $headers = $poll.Headers
                $state = & $parse $poll.Content
                $status = [string]$state['status']
                if ($OnProgress) { & $OnProgress $(if ($null -ne $state['percentComplete']) { [double]$state['percentComplete'] }) $status }
                if ($status -eq 'Succeeded') { $final = $state; break }
                if ($status -in 'Failed', 'Canceled') {
                    $reason = if ($state['error'] -is [System.Collections.IDictionary]) { "$($state['error']['code']): $($state['error']['message'])" } else { $status }
                    $verb = if ($Method -eq 'Post') { 'finish' } else { $Method.ToLowerInvariant() }
                    $exception = [System.Exception]::new("Azure couldn't $verb $Uri - $reason")
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
                if ($OnProgress) { & $OnProgress $null $(if ($poll.Status -eq 202) { 'InProgress' } else { 'Succeeded' }) }
                if ($poll.Status -ne 202) { $final = & $parse $poll.Content; break }
            }
        }
    }

    if ($Method -eq 'Delete') { return }
    if ($Method -eq 'Post') {
        if ($null -ne $final) { return $final }
        return (& $parse $response.Content)
    }
    Invoke-AACArmRequest -Uri $Uri
}
