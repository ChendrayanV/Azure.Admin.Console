function Get-AACHttpClient {
    <#
    .SYNOPSIS
        Returns the module's one HttpClient, made on first use: every Azure
        call goes through it, so HTTPS connections are pooled and reused
        instead of a new TLS handshake per call.
    .DESCRIPTION
        Up to 64 connections per host, each kept for up to 5 minutes (so a
        DNS change is picked up); responses decompressed; 100-second timeout.
        The system proxy applies, as it does to Invoke-WebRequest.
    #>
    [CmdletBinding()]
    [OutputType([System.Net.Http.HttpClient])]
    param()

    if (-not $script:AACHttpClient) {
        $handler = [System.Net.Http.SocketsHttpHandler]::new()
        $handler.MaxConnectionsPerServer = 64
        $handler.PooledConnectionLifetime = [TimeSpan]::FromMinutes(5)
        $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::All
        $client = [System.Net.Http.HttpClient]::new($handler)
        $client.Timeout = [TimeSpan]::FromSeconds(100)
        $client.DefaultRequestHeaders.UserAgent.ParseAdd("Azure.Admin.Console/$($MyInvocation.MyCommand.Module.Version)")
        $script:AACHttpClient = $client
    }
    $script:AACHttpClient
}
