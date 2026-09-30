function Invoke-AACHttp {
    <#
    .SYNOPSIS
        Calls an Azure API once, through the pooled HttpClient, retrying what
        is worth retrying - and returns the response's status and text, or
        throws with Azure's own reason.
    .DESCRIPTION
        Every Azure call of the module goes through here (Invoke-AACArmRequest
        for Resource Manager, Invoke-AACResourceGraphQuery, Invoke-AACCostQuery)
        or through Invoke-AACArmParallel, with the same rules:
          - throttling (429) and server errors (5xx) are retried up to four
            times, waiting as long as the longest retry header asks
            (Get-AACRetryDelay), else 5, 10, 15, 20 seconds; never more than
            60 at a time
          - a dropped connection is retried after a second or two
          - any other failure throws, with the HTTP status in the
            exception's Data['StatusCode'] and Azure's message - with the
            query APIs' nested innererror detail - as its message
            (Get-AACErrorMessage)

        Returns @{ Status; Content (the response text) }. -Resource picks the
        token's audience (Get-AACAccessToken -Resource).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [ValidateSet('Get', 'Post', 'Put', 'Delete')]
        [string] $Method = 'Get',

        [Parameter(Mandatory)]
        [string] $Uri,

        [string] $Body,

        [string] $Resource = 'https://management.azure.com',

        [ValidateRange(1, 10)]
        [int] $MaxAttempts = 5
    )

    for ($attempt = 1; ; $attempt++) {
        $send = @{ Method = $Method; Uri = $Uri; Token = (Get-AACAccessToken -Resource $Resource) }
        if ($PSBoundParameters.ContainsKey('Body')) { $send.Body = $Body }
        $response = $null
        $status = 0
        $content = ''
        $failure = ''
        try {
            $response = (Send-AACHttpRequest @send).GetAwaiter().GetResult()
            $status = [int]$response.StatusCode
            $content = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        }
        catch {
            $failure = $_.Exception.GetBaseException().Message
        }
        try {
            if ($status -ge 200 -and $status -lt 300) {
                return @{ Status = $status; Content = $content }
            }
            if ($attempt -lt $MaxAttempts -and ($status -eq 0 -or $status -eq 429 -or $status -ge 500)) {
                $wait = Get-AACRetryDelay -Response $response -Status $status -Attempt $attempt
                Start-Sleep -Milliseconds ([int](1000 * $wait))
                continue
            }
            # Azure's own reason, with the nested detail the query APIs give.
            $message = Get-AACErrorMessage -Content $content -Fallback $(if ($failure) { $failure } else { "Response status code does not indicate success: $status ($($response.ReasonPhrase))." })
            $exception = [System.Exception]::new($message)
            $exception.Data['StatusCode'] = $status
            throw $exception
        }
        finally {
            if ($response) { $response.Dispose() }
        }
    }
}
