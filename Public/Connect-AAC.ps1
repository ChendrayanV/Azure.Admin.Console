function Connect-AAC {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Signs in to Azure - in the browser (OAuth 2.0 Authorization Code flow
        with PKCE and a loopback redirect), with a device code, as a service
        principal (client secret or certificate) or with a managed identity -
        no Az or Microsoft.Graph module, and no app registration required by
        default.
    .DESCRIPTION
        Without a sign-in option, the browser (below). -DeviceCode shows a
        code to enter at https://microsoft.com/devicelogin on any device.
        -ClientSecret, -CertificatePath and -CertificateThumbprint sign in
        as a service principal (-ClientId, -TenantId), and -Identity with
        the managed identity of where this runs (Azure Automation, a VM, App
        Service): no user, no refresh token - a new token is asked for when
        one runs out.

        The browser sign-in:
        Opens your default browser to Microsoft's sign-in page, receives the
        redirect on a one-shot local HTTP listener (http://localhost:<port>/),
        and exchanges the resulting authorization code for tokens directly
        against the v2.0 token endpoint over REST - using a PKCE code_verifier /
        code_challenge pair (RFC 7636) instead of a client secret, which is what
        makes this safe for a public desktop tool with no back-end to keep a
        secret in.

        By default this uses Azure's well-known public client ID for the Azure
        CLI (04b07795-8ddb-461a-bbee-02f9e1bf7b46), which is pre-consented in
        every Entra ID tenant, so sign-in works immediately with no app
        registration of your own. Pass -ClientId to use your own App Registration
        instead (create it with the "Mobile and desktop applications" platform
        and a http://localhost redirect URI).

        The resulting session (access token, refresh token, expiry, signed-in
        account and tenant) is kept in this module's memory for the rest of the
        PowerShell session and used automatically by every command, such as
        Invoke-AACPSRule. It is not written to disk.
    .PARAMETER TenantId
        The tenant to sign in to: a tenant ID (GUID), a verified domain name, or
        one of Microsoft's multi-tenant aliases 'organizations' (default, any
        Entra ID tenant), 'common' (also allows personal Microsoft accounts) or
        'consumers'.
    .PARAMETER ClientId
        The Entra ID application (client) ID to sign in as. Defaults to the
        well-known Azure CLI public client ID so this works without an app
        registration; see the Description for when to supply your own. An
        App Registration of your own needs delegated permissions for Azure
        Service Management (user_impersonation) and, for
        Invoke-AACApplicationInsightQuery, the Log Analytics API and the
        Application Insights API (Data.Read).
    .PARAMETER Scope
        The OAuth scopes to request. Defaults to Azure Resource Manager's
        default scope (https://management.azure.com/.default) plus
        offline_access (so a refresh token is issued) and openid/profile (so
        the signed-in account's name can be shown).
    .PARAMETER DeviceCode
        Sign in with a code instead of a browser on this machine: the code
        is shown with the address to enter it at
        (https://microsoft.com/devicelogin), on any device. For SSH,
        containers and Cloud Shell.
    .PARAMETER ClientSecret
        Sign in as a service principal (-ClientId, -TenantId) with its client
        secret - for pipelines and schedules. No user, no browser; the
        service principal needs Reader on what is read.
    .PARAMETER CertificatePath
        Sign in as a service principal (-ClientId, -TenantId) with a
        certificate: a .pfx file with the private key (-CertificatePassword
        if it has one). The token request is signed with the key; the key
        isn't sent anywhere.
    .PARAMETER CertificatePassword
        The .pfx file's password.
    .PARAMETER CertificateThumbprint
        Sign in as a service principal with a certificate from the current
        user's (or the machine's) certificate store, by its thumbprint.
    .PARAMETER Identity
        Sign in with the managed identity of where this runs - an Azure
        Automation account (as a runbook), a VM, App Service or Functions.
        -ClientId picks a user-assigned identity; without it, the
        system-assigned one.
    .PARAMETER TimeoutSeconds
        How long to wait for you to complete sign-in in the browser before giving
        up. Defaults to 180 seconds.
    .PARAMETER PassThru
        Also returns the session summary object, in addition to rendering it.
    .EXAMPLE
        Connect-AAC
        Signs in interactively using the well-known Azure CLI client ID.
    .EXAMPLE
        Connect-AAC -TenantId 'contoso.onmicrosoft.com' -ClientId '11111111-1111-1111-1111-111111111111'
        Signs in to a specific tenant using your own App Registration.
    .EXAMPLE
        Connect-AAC -DeviceCode
        Signs in with a code entered at https://microsoft.com/devicelogin.
    .EXAMPLE
        Connect-AAC -TenantId 'contoso.onmicrosoft.com' -ClientId '11111111-1111-1111-1111-111111111111' -ClientSecret (Read-Host -AsSecureString 'Secret')
        Signs in as a service principal with its client secret.
    .EXAMPLE
        Connect-AAC -TenantId 'contoso.onmicrosoft.com' -ClientId '11111111-1111-1111-1111-111111111111' -CertificatePath .\sp-reader.pfx -CertificatePassword $password
        Signs in as a service principal with a certificate.
    .EXAMPLE
        Connect-AAC -Identity
        In an Azure Automation runbook: signs in with the account's system-assigned managed identity.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Browser')]
    [OutputType('AAC.Session')]
    param(
        [Parameter(ParameterSetName = 'Browser')]
        [Parameter(ParameterSetName = 'DeviceCode')]
        [Parameter(Mandatory, ParameterSetName = 'ClientSecret')]
        [Parameter(Mandatory, ParameterSetName = 'CertificateFile')]
        [Parameter(Mandatory, ParameterSetName = 'CertificateStore')]
        [string] $TenantId,

        [Parameter(ParameterSetName = 'Browser')]
        [Parameter(ParameterSetName = 'DeviceCode')]
        [Parameter(Mandatory, ParameterSetName = 'ClientSecret')]
        [Parameter(Mandatory, ParameterSetName = 'CertificateFile')]
        [Parameter(Mandatory, ParameterSetName = 'CertificateStore')]
        [Parameter(ParameterSetName = 'Identity')]
        [string] $ClientId,

        [Parameter(ParameterSetName = 'Browser')]
        [Parameter(ParameterSetName = 'DeviceCode')]
        [string[]] $Scope = @('https://management.azure.com/.default', 'offline_access', 'openid', 'profile'),

        [Parameter(Mandatory, ParameterSetName = 'DeviceCode')]
        [switch] $DeviceCode,

        [Parameter(Mandatory, ParameterSetName = 'ClientSecret')]
        [securestring] $ClientSecret,

        [Parameter(Mandatory, ParameterSetName = 'CertificateFile')]
        [string] $CertificatePath,

        [Parameter(ParameterSetName = 'CertificateFile')]
        [securestring] $CertificatePassword,

        [Parameter(Mandatory, ParameterSetName = 'CertificateStore')]
        [string] $CertificateThumbprint,

        [Parameter(Mandatory, ParameterSetName = 'Identity')]
        [switch] $Identity,

        [Parameter(ParameterSetName = 'Browser')]
        [Parameter(ParameterSetName = 'DeviceCode')]

        [ValidateRange(30, 900)]
        [int] $TimeoutSeconds = 180,

        [switch] $PassThru
    )

    # A failure anywhere below ends as a Spectre.Console error panel and this
    # command's own terminating error, not a line inside the module. A stopped
    # pipeline (Select-Object -First, Ctrl+C) is no failure: just return - a
    # rethrow would stop the caller's whole script, not only this command.
    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    Write-AACRule -Title 'Azure Admin Console :: Sign in' -Color 'deepskyblue3_1'

    $flow = $PSCmdlet.ParameterSetName
    # The defaults: any Entra ID tenant, and the Azure CLI's public client (not
    # for a managed identity: no client ID there is the system-assigned one).
    if (-not $TenantId) { $TenantId = 'organizations' }
    if (-not $ClientId -and $flow -ne 'Identity') { $ClientId = '04b07795-8ddb-461a-bbee-02f9e1bf7b46' }
    if ($flow -in 'Browser', 'DeviceCode') {
        $signIn = if ($flow -eq 'DeviceCode') {
            Invoke-AACDeviceCodeSignIn -TenantId $TenantId -ClientId $ClientId -Scope $Scope
        }
        else {
            Invoke-AACBrowserSignIn -TenantId $TenantId -ClientId $ClientId -Scope $Scope -TimeoutSeconds $TimeoutSeconds
        }
        $tokenResponse = $signIn.Response
        $script:AACSession = [pscustomobject]@{
            PSTypeName   = 'AAC.Session'
            Account      = $signIn.Account
            TenantId     = $signIn.TenantId
            ClientId     = $ClientId
            Scope        = $Scope
            AccessToken  = $tokenResponse.access_token
            RefreshToken = Get-AACPropertyValue -InputObject $tokenResponse -Name 'refresh_token'
            ExpiresOn    = (Get-Date).AddSeconds([int]$tokenResponse.expires_in)
            ConnectedAt  = Get-Date
            Flow         = $flow
        }
    }
    else {
        # App-only: a service principal or a managed identity. No refresh
        # token - Get-AACAccessToken asks for a new token when one runs out.
        $credential = @{ TenantId = $TenantId; ClientId = $ClientId }
        switch ($flow) {
            'ClientSecret' { $credential.ClientSecret = $ClientSecret }
            'CertificateFile' {
                $file = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($CertificatePath)
                if (-not (Test-Path -LiteralPath $file)) { throw "The certificate file $file doesn't exist." }
                $password = if ($CertificatePassword) { [System.Net.NetworkCredential]::new('', $CertificatePassword).Password } else { $null }
                $credential.Certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($file, $password, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet)
            }
            'CertificateStore' {
                $thumbprint = $CertificateThumbprint -replace '\s', ''
                $found = foreach ($location in 'CurrentUser', 'LocalMachine') {
                    $store = [System.Security.Cryptography.X509Certificates.X509Store]::new('My', $location)
                    try {
                        $store.Open('ReadOnly')
                        $store.Certificates.Find([System.Security.Cryptography.X509Certificates.X509FindType]::FindByThumbprint, $thumbprint, $false) | Where-Object HasPrivateKey
                    }
                    finally { $store.Close() }
                }
                $certificate = @($found) | Select-Object -First 1
                if (-not $certificate) { throw "No certificate with the thumbprint $thumbprint and its private key is in the CurrentUser or LocalMachine 'My' store." }
                $credential.Certificate = $certificate
            }
            'Identity' { if (-not $PSBoundParameters.ContainsKey('ClientId')) { $credential.ClientId = '' } }
        }
        $credential.Flow = @{ ClientSecret = 'ClientSecret'; CertificateFile = 'Certificate'; CertificateStore = 'Certificate'; Identity = 'ManagedIdentity' }[$flow]
        $token = Get-AACAppToken -Flow $credential.Flow -TenantId $credential.TenantId -ClientId $credential.ClientId -ClientSecret $credential['ClientSecret'] -Certificate $credential['Certificate']
        $tenant = [string](Get-AACPropertyValue -InputObject $token.Claims -Name 'tid')
        $appId = [string](@((Get-AACPropertyValue -InputObject $token.Claims -Name 'appid'), (Get-AACPropertyValue -InputObject $token.Claims -Name 'azp'), $credential.ClientId) | Where-Object { $_ } | Select-Object -First 1)
        if ($tenant) { $credential.TenantId = $tenant }
        $script:AACSession = [pscustomobject]@{
            PSTypeName   = 'AAC.Session'
            Account      = $(if ($credential.Flow -eq 'ManagedIdentity') { "managed identity $appId" } else { "service principal $appId" })
            TenantId     = $credential.TenantId
            ClientId     = $appId
            Scope        = @('https://management.azure.com/.default')
            AccessToken  = $token.AccessToken
            RefreshToken = $null
            ExpiresOn    = $token.ExpiresOn
            ConnectedAt  = Get-Date
            Flow         = $credential.Flow
            Credential   = $credential
        }
    }

    $summary = "[grey58]Account:[/]  $($script:AACSession.Account)`n[grey58]Tenant:[/]   $($script:AACSession.TenantId)`n[grey58]Expires:[/]  $($script:AACSession.ExpiresOn.ToString('u'))"
    Show-AACCallout Success -Message $summary -Title 'Connected'

    if ($PassThru) {
        return $script:AACSession
    }
}
