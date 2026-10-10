function Get-AACTlsCertificate {
    <#
    .SYNOPSIS
        Reads the TLS certificate a host presents - its expiry, subject and
        issuer - with a TLS handshake of its own (no HTTP request, no
        credentials).
    .DESCRIPTION
        The certificate is taken whether or not it's trusted, so an expired
        or self-signed one is still reported. Returns @{ NotAfter; Subject;
        Issuer; Error }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $HostName,

        [int] $Port = 443,

        [int] $TimeoutSeconds = 10
    )

    $tcp = [System.Net.Sockets.TcpClient]::new()
    try {
        if (-not $tcp.ConnectAsync($HostName, $Port).Wait([TimeSpan]::FromSeconds($TimeoutSeconds))) { return @{ NotAfter = $null; Subject = ''; Issuer = ''; Error = "no answer within $TimeoutSeconds seconds" } }
        # Accept any certificate: it's read, not trusted. (Synchronous, so the
        # callback runs on this thread - a script block can't run on another.)
        $ssl = [System.Net.Security.SslStream]::new($tcp.GetStream(), $false, { param($TlsSender, $TlsCertificate, $TlsChain, $TlsErrors) $true })
        try {
            $ssl.ReadTimeout = $TimeoutSeconds * 1000
            $ssl.AuthenticateAsClient($HostName)
            $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($ssl.RemoteCertificate)
            @{ NotAfter = $certificate.NotAfter.ToUniversalTime(); Subject = $certificate.Subject; Issuer = $certificate.Issuer; Error = '' }
        }
        finally { $ssl.Dispose() }
    }
    catch { @{ NotAfter = $null; Subject = ''; Issuer = ''; Error = $_.Exception.GetBaseException().Message } }
    finally { $tcp.Dispose() }
}
