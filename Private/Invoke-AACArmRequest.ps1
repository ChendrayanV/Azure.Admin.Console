function Invoke-AACArmRequest {
    <#
    .SYNOPSIS
        Calls Azure Resource Manager with the Connect-AAC sign-in and returns
        the JSON response as hashtables.
    .DESCRIPTION
        Invoke-RestMethod can't be used for resource data: it silently returns
        the raw text when the JSON has keys differing only by case - which
        tags often do ('Owner' and 'owner' on one resource) - while
        ConvertFrom-Json -AsHashtable accepts them.

        Retries throttled (429) and transient 5xx responses up to four times,
        honouring Retry-After. Other failures throw, with the HTTP status in
        the exception's Data['StatusCode'] so callers can tell "not found"
        from "forbidden". -Uri may be a full URL or a path starting with '/'
        (https://management.azure.com is added).
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Get', 'Post')]
        [string] $Method = 'Get',

        [Parameter(Mandatory)]
        [string] $Uri,

        [string] $Body
    )

    if ($Uri.StartsWith('/')) {
        $Uri = "https://management.azure.com$Uri"
    }
    # No web-request progress bar or verbose line per call: they would draw
    # over the Spectre progress display.
    $ProgressPreference = 'SilentlyContinue'
    for ($attempt = 1; ; $attempt++) {
        try {
            $request = @{
                Method      = $Method
                Uri         = $Uri
                Headers     = @{ Authorization = "Bearer $(Get-AACAccessToken)" }
                ErrorAction = 'Stop'
                Verbose     = $false
            }
            if ($Body) {
                $request.Body = $Body
                $request.ContentType = 'application/json'
            }
            $content = (Invoke-WebRequest @request).Content
            if ($content -is [byte[]]) {
                $content = [System.Text.Encoding]::UTF8.GetString($content)
            }
            if ([string]::IsNullOrWhiteSpace($content)) {
                return $null
            }
            return ConvertFrom-Json -InputObject $content -AsHashtable -Depth 100
        }
        catch {
            # Network failures (DNS, TLS, ...) have no Response at all.
            $response = Get-AACPropertyValue -InputObject $_.Exception -Name 'Response'
            $status = if ($response) { [int](Get-AACPropertyValue -InputObject $response -Name 'StatusCode') } else { 0 }
            if ($attempt -ge 4 -or ($status -ne 429 -and $status -lt 500)) {
                $details = if ($_.ErrorDetails) { $_.ErrorDetails.Message } else { $null }
                $message = if ($details) { $details } else { $_.Exception.Message }
                # A readable reason from ARM's error body when there is one.
                try {
                    $parsed = ConvertFrom-Json -InputObject $details -AsHashtable -ErrorAction Stop
                    if ($parsed -is [System.Collections.IDictionary] -and $parsed['error'] -is [System.Collections.IDictionary] -and $parsed['error']['message']) {
                        $message = [string]$parsed['error']['message']
                    }
                }
                catch {
                    Write-Debug "The error body is not ARM JSON: $details"
                }
                $exception = [System.Exception]::new($message)
                $exception.Data['StatusCode'] = $status
                throw $exception
            }
            $retryAfter = $null
            if ($response) {
                $headers = Get-AACPropertyValue -InputObject $response -Name 'Headers'
                $retry = if ($headers) { Get-AACPropertyValue -InputObject $headers -Name 'RetryAfter' } else { $null }
                if ($retry) { $retryAfter = Get-AACPropertyValue -InputObject $retry -Name 'Delta' }
            }
            Start-Sleep -Seconds $(if ($retryAfter) { [math]::Min(60, $retryAfter.TotalSeconds) } else { 5 * $attempt })
        }
    }
}
