function Send-AACHttpRequest {
    <#
    .SYNOPSIS
        Sends one HTTP request through the module's pooled HttpClient and
        returns the running Task[HttpResponseMessage] - so several can be in
        flight at once. Invoke-AACHttp and Invoke-AACArmParallel build on it.
    .DESCRIPTION
        -Token is sent as a Bearer token; -Body (JSON) with -Method Post or
        Put; -Header adds headers of its own (Azure Storage's x-ms-version,
        say). A path starting with '/' goes to https://management.azure.com.
    #>
    [CmdletBinding()]
    [OutputType([System.Threading.Tasks.Task])]
    param(
        [ValidateSet('Get', 'Post', 'Put', 'Delete')]
        [string] $Method = 'Get',

        [Parameter(Mandatory)]
        [string] $Uri,

        [string] $Body,

        [string] $Token,

        [System.Collections.IDictionary] $Header
    )

    if ($Uri.StartsWith('/')) { $Uri = "https://management.azure.com$Uri" }
    $message = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($Method.ToUpperInvariant()), $Uri)
    if ($Token) { $message.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $Token) }
    if ($Header) { foreach ($name in $Header.Keys) { $null = $message.Headers.TryAddWithoutValidation([string]$name, [string]$Header[$name]) } }
    if ($PSBoundParameters.ContainsKey('Body')) {
        $message.Content = [System.Net.Http.StringContent]::new($Body, [System.Text.Encoding]::UTF8, 'application/json')
    }
    (Get-AACHttpClient).SendAsync($message)
}
