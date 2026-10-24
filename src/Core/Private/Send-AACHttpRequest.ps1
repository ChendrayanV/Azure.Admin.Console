function Send-AACHttpRequest {
    <#
    .SYNOPSIS
        Sends one HTTP request through the module's pooled HttpClient and
        returns the running Task[HttpResponseMessage] - so several can be in
        flight at once. Invoke-AACHttp and Invoke-AACArmParallel build on it.
    .DESCRIPTION
        -Token is sent as a Bearer token; -Body (JSON) with -Method Post, Put
        or Patch, or -BodyBytes (a file's bytes, with -ContentType) for a
        blob upload; -Header adds headers of its own (Azure Storage's
        x-ms-version, say) - Content-* headers (Content-MD5) go on the body,
        where .NET wants them. A path starting with '/' goes to
        https://management.azure.com.
    #>
    [CmdletBinding()]
    [OutputType([System.Threading.Tasks.Task])]
    param(
        [ValidateSet('Get', 'Post', 'Put', 'Patch', 'Delete', 'Head')]
        [string] $Method = 'Get',

        [Parameter(Mandatory)]
        [string] $Uri,

        [string] $Body,

        [byte[]] $BodyBytes,

        [string] $ContentType = 'application/octet-stream',

        [string] $Token,

        [System.Collections.IDictionary] $Header
    )

    if ($Uri.StartsWith('/')) { $Uri = "https://management.azure.com$Uri" }
    $message = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($Method.ToUpperInvariant()), $Uri)
    if ($Token) { $message.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $Token) }
    if ($PSBoundParameters.ContainsKey('BodyBytes')) {
        $message.Content = [System.Net.Http.ByteArrayContent]::new($BodyBytes)
        $message.Content.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse($ContentType)
    }
    elseif ($PSBoundParameters.ContainsKey('Body')) {
        $message.Content = [System.Net.Http.StringContent]::new($Body, [System.Text.Encoding]::UTF8, 'application/json')
    }
    if ($Header) {
        foreach ($name in $Header.Keys) {
            if ([string]$name -like 'Content-*' -and $message.Content) { $null = $message.Content.Headers.TryAddWithoutValidation([string]$name, [string]$Header[$name]) }
            else { $null = $message.Headers.TryAddWithoutValidation([string]$name, [string]$Header[$name]) }
        }
    }
    (Get-AACHttpClient).SendAsync($message)
}
