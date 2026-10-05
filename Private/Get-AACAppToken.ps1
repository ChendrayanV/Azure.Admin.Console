function Get-AACAppToken {
    <#
    .SYNOPSIS
        Gets an app-only access token - for a service principal (a client
        secret or a certificate) or a managed identity - for one Azure API.
    .DESCRIPTION
        The sign-ins with no user and no refresh token (Connect-AAC
        -ClientSecret, -CertificatePath / -CertificateThumbprint, -Identity)
        ask for a new token each time one is needed; Get-AACAccessToken
        keeps it until it nears expiry.

          ClientSecret     the client credentials grant with the secret
          Certificate      the client credentials grant with a signed
                           client assertion (RS256, the certificate's SHA-1
                           thumbprint as x5t) - the private key never
                           leaves the machine
          ManagedIdentity  the identity endpoint of where this runs:
                           Azure Automation, App Service and Functions
                           (IDENTITY_ENDPOINT + IDENTITY_HEADER), Cloud Shell
                           (MSI_ENDPOINT), or a VM's instance metadata service
                           (169.254.169.254); -ClientId picks a user-assigned
                           identity

        -Resource is the API's audience, e.g. https://management.azure.com.
        Returns @{ AccessToken; ExpiresOn; Claims }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('ClientSecret', 'Certificate', 'ManagedIdentity')]
        [string] $Flow,

        [string] $TenantId,

        [string] $ClientId,

        [securestring] $ClientSecret,

        [System.Security.Cryptography.X509Certificates.X509Certificate2] $Certificate,

        [string] $Resource = 'https://management.azure.com'
    )

    $ProgressPreference = 'SilentlyContinue'
    $audience = $Resource.TrimEnd('/')
    $reasonOf = {
        param($ErrorRecord)
        $reason = $ErrorRecord.Exception.Message
        if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
            $details = $ErrorRecord.ErrorDetails.Message | ConvertFrom-Json -ErrorAction Ignore
            $text = if ($details) { @((Get-AACPropertyValue -InputObject $details -Name 'error_description'), (Get-AACPropertyValue -InputObject $details -Name 'message'), (Get-AACPropertyValue -InputObject $details -Name 'error')) | Where-Object { $_ } | Select-Object -First 1 } else { $null }
            if ($text) { $reason = ([string]$text -split '\r?\n')[0] }
        }
        $reason.TrimEnd('.')
    }

    if ($Flow -eq 'ManagedIdentity') {
        $query = "resource=$([uri]::EscapeDataString($audience))$(if ($ClientId) { "&client_id=$([uri]::EscapeDataString($ClientId))" })"
        $attempts = [System.Collections.Generic.List[hashtable]]::new()
        if ($env:IDENTITY_ENDPOINT -and $env:IDENTITY_HEADER) {
            # App Service and Functions want an api-version; Azure Automation's
            # endpoint is asked the way its documentation shows, without one.
            $headers = @{ 'X-IDENTITY-HEADER' = $env:IDENTITY_HEADER; Metadata = 'true' }
            $attempts.Add(@{ Uri = "$($env:IDENTITY_ENDPOINT)?$query&api-version=2019-08-01"; Headers = $headers; Where = 'the managed identity endpoint (IDENTITY_ENDPOINT)' })
            $attempts.Add(@{ Uri = "$($env:IDENTITY_ENDPOINT)?$query"; Headers = $headers; Where = 'the managed identity endpoint (IDENTITY_ENDPOINT)' })
        }
        elseif ($env:MSI_ENDPOINT) {
            $attempts.Add(@{ Uri = "$($env:MSI_ENDPOINT)?$query"; Headers = @{ Metadata = 'true' }; Where = 'the managed identity endpoint (MSI_ENDPOINT)' })
        }
        else {
            $attempts.Add(@{ Uri = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&$query"; Headers = @{ Metadata = 'true' }; Where = 'the instance metadata service (169.254.169.254)' })
        }
        $response = $null
        $failure = ''
        foreach ($attempt in $attempts) {
            try {
                $response = Invoke-RestMethod -Uri $attempt.Uri -Headers $attempt.Headers -Method Get -TimeoutSec 30 -ErrorAction Stop -Verbose:$false
                break
            }
            catch { $failure = "$($attempt.Where): $(& $reasonOf $_)" }
        }
        if (-not $response) {
            $problem = [System.InvalidOperationException]::new("Could not get a managed identity token for ${audience} from $failure.")
            $problem.Data['AACHint'] = 'Run this where a managed identity is available - an Azure Automation account, a VM, App Service or Functions with an identity turned on - and, for a user-assigned identity, pass its client ID with -ClientId.'
            throw $problem
        }
    }
    else {
        if (-not $TenantId -or $TenantId -in 'organizations', 'common', 'consumers') {
            throw 'A service principal signs in to one tenant: pass -TenantId (its ID or domain).'
        }
        $endpoint = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
        $body = @{ grant_type = 'client_credentials'; client_id = $ClientId; scope = "$audience/.default" }
        if ($Flow -eq 'ClientSecret') {
            $body.client_secret = [System.Net.NetworkCredential]::new('', $ClientSecret).Password
        }
        else {
            # A client assertion: a JWT signed with the certificate's private key.
            $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            $header = @{ alg = 'RS256'; typ = 'JWT'; x5t = (ConvertTo-AACBase64Url -Bytes $Certificate.GetCertHash()) } | ConvertTo-Json -Compress
            $claims = [ordered]@{ aud = $endpoint; iss = $ClientId; sub = $ClientId; jti = [guid]::NewGuid().ToString(); nbf = $now - 60; iat = $now - 60; exp = $now + 600 } | ConvertTo-Json -Compress
            $unsigned = "$(ConvertTo-AACBase64Url -Bytes ([System.Text.Encoding]::UTF8.GetBytes($header))).$(ConvertTo-AACBase64Url -Bytes ([System.Text.Encoding]::UTF8.GetBytes($claims)))"
            $key = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($Certificate)
            if (-not $key) { throw "The certificate $($Certificate.Subject) has no RSA private key this process can use." }
            $signature = $key.SignData([System.Text.Encoding]::UTF8.GetBytes($unsigned), [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
            $body.client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
            $body.client_assertion = "$unsigned.$(ConvertTo-AACBase64Url -Bytes $signature)"
        }
        try {
            $response = Invoke-RestMethod -Uri $endpoint -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop -Verbose:$false
        }
        catch {
            $problem = [System.InvalidOperationException]::new("The service principal $ClientId could not get a token for ${audience}: $(& $reasonOf $_).")
            $problem.Data['AACHint'] = 'Check the tenant, the application (client) ID and its secret or certificate in Entra ID > App registrations, and that the service principal has Reader on what you assess.'
            throw $problem
        }
    }

    $token = [string](Get-AACPropertyValue -InputObject $response -Name 'access_token')
    $expiresIn = Get-AACPropertyValue -InputObject $response -Name 'expires_in'
    $expiresOn = Get-AACPropertyValue -InputObject $response -Name 'expires_on'
    $expiry = if ($expiresIn) { (Get-Date).AddSeconds([int]$expiresIn) }
    elseif ($expiresOn -as [long]) { [DateTimeOffset]::FromUnixTimeSeconds([long]$expiresOn).LocalDateTime }
    else { (Get-Date).AddMinutes(30) }
    @{ AccessToken = $token; ExpiresOn = $expiry; Claims = (ConvertFrom-AACJwt -Token $token) }
}
