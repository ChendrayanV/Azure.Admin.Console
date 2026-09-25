function Connect-AAC {
    <#
    .SYNOPSIS
        Signs in to Azure interactively using the OAuth 2.0 Authorization Code
        flow with PKCE and a loopback redirect - no Az or Microsoft.Graph module,
        and no app registration required by default.
    .DESCRIPTION
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
        PowerShell session and used automatically by commands like
        Invoke-AACPester. It is not written to disk.
    .PARAMETER TenantId
        The tenant to sign in to: a tenant ID (GUID), a verified domain name, or
        one of Microsoft's multi-tenant aliases 'organizations' (default, any
        Entra ID tenant), 'common' (also allows personal Microsoft accounts) or
        'consumers'.
    .PARAMETER ClientId
        The Entra ID application (client) ID to sign in as. Defaults to the
        well-known Azure CLI public client ID so this works without an app
        registration; see the Description for when to supply your own.
    .PARAMETER Scope
        The OAuth scopes to request. Defaults to Azure Resource Manager's
        default scope (https://management.azure.com/.default) plus
        offline_access (so a refresh token is issued) and openid/profile (so
        the signed-in account's name can be shown).
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
    #>
    [CmdletBinding()]
    [OutputType('AAC.Session')]
    param(
        [string] $TenantId = 'organizations',

        [string] $ClientId = '04b07795-8ddb-461a-bbee-02f9e1bf7b46',

        [string[]] $Scope = @('https://management.azure.com/.default', 'offline_access', 'openid', 'profile'),

        [ValidateRange(30, 900)]
        [int] $TimeoutSeconds = 180,

        [switch] $PassThru
    )

    Write-AACRule -Title 'Azure Admin Console :: Sign in' -Color 'deepskyblue3_1'

    $pkce = New-AACPkceCode

    $stateBytes = [byte[]]::new(24)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($stateBytes)
    $state = ConvertTo-AACBase64Url -Bytes $stateBytes

    $port = Get-AACFreeLoopbackPort
    $redirectUri = "http://localhost:$port/"

    $httpListener = [System.Net.HttpListener]::new()
    $httpListener.Prefixes.Add($redirectUri)

    try {
        $httpListener.Start()
    }
    catch {
        throw "Could not start the local sign-in listener on $redirectUri : $($_.Exception.Message)"
    }

    try {
        $authorizeParameters = [ordered]@{
            client_id             = $ClientId
            response_type         = 'code'
            redirect_uri          = $redirectUri
            response_mode         = 'query'
            scope                 = ($Scope -join ' ')
            state                 = $state
            code_challenge        = $pkce.Challenge
            code_challenge_method = $pkce.Method
            prompt                = 'select_account'
        }
        $queryString = ($authorizeParameters.GetEnumerator() | ForEach-Object {
                "$($_.Key)=$([System.Uri]::EscapeDataString($_.Value))"
            }) -join '&'
        $authorizeUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/authorize?$queryString"

        Write-AACMarkup "[grey58]Opening your browser to sign in. If it doesn't open, go to:[/]"
        Write-AACMarkup "[deepskyblue3_1]$authorizeUrl[/]"

        try {
            Start-Process -FilePath $authorizeUrl | Out-Null
        }
        catch {
            Write-AACMarkup "[gold1]Could not open a browser automatically: $($_.Exception.Message)[/]"
        }

        $authorizationResult = Invoke-AACStatus -Title 'Waiting for you to finish signing in...' -Spinner 'Dots' -ScriptBlock {
            $contextTask = $httpListener.GetContextAsync()
            $timeoutTask = [System.Threading.Tasks.Task]::Delay([TimeSpan]::FromSeconds($TimeoutSeconds))
            $completedIndex = [System.Threading.Tasks.Task]::WaitAny(@($contextTask, $timeoutTask))

            if ($completedIndex -eq 1) {
                return [pscustomobject]@{ TimedOut = $true }
            }

            $context = $contextTask.GetAwaiter().GetResult()
            $queryParameters = ConvertFrom-AACQueryString -Query $context.Request.Url.Query

            $responseHtml = if ($queryParameters.ContainsKey('code')) {
                '<html><body style="font-family:sans-serif"><h2>Signed in</h2><p>You can close this window and return to the console.</p></body></html>'
            }
            else {
                '<html><body style="font-family:sans-serif"><h2>Sign-in was not completed</h2><p>You can close this window and return to the console.</p></body></html>'
            }
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($responseHtml)
            $context.Response.ContentType = 'text/html'
            $context.Response.ContentLength64 = $buffer.Length
            $context.Response.OutputStream.Write($buffer, 0, $buffer.Length)
            $context.Response.OutputStream.Close()

            return [pscustomobject]@{
                TimedOut = $false
                Query    = $queryParameters
            }
        }
    }
    finally {
        $httpListener.Stop()
        $httpListener.Close()
    }

    if ($authorizationResult.TimedOut) {
        throw "Timed out after $TimeoutSeconds seconds waiting for sign-in to complete."
    }

    $query = $authorizationResult.Query
    if ($query.ContainsKey('error')) {
        $description = if ($query.ContainsKey('error_description')) { $query['error_description'] } else { $query['error'] }
        throw "Sign-in failed: $description"
    }
    if (-not $query.ContainsKey('code')) {
        throw 'Sign-in did not return an authorization code.'
    }
    if ($query['state'] -cne $state) {
        throw 'Sign-in response failed state validation (possible cross-site request forgery). Try again.'
    }

    $tokenEndpoint = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $tokenBody = @{
        grant_type    = 'authorization_code'
        code          = $query['code']
        redirect_uri  = $redirectUri
        client_id     = $ClientId
        code_verifier = $pkce.Verifier
        scope         = ($Scope -join ' ')
    }

    $tokenResponse = Invoke-AACStatus -Title 'Exchanging the authorization code for a token...' -Spinner 'Dots' -ScriptBlock {
        try {
            Invoke-RestMethod -Uri $tokenEndpoint -Method Post -Body $tokenBody -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
        }
        catch {
            $details = $_.ErrorDetails.Message
            throw "Token exchange failed: $(if ($details) { $details } else { $_.Exception.Message })"
        }
    }

    $idToken = Get-AACPropertyValue -InputObject $tokenResponse -Name 'id_token'
    $claims = if ($idToken) { ConvertFrom-AACJwt -Token $idToken } else { $null }
    $account = if ($claims) {
        (
            (Get-AACPropertyValue -InputObject $claims -Name 'preferred_username'),
            (Get-AACPropertyValue -InputObject $claims -Name 'name'),
            (Get-AACPropertyValue -InputObject $claims -Name 'oid')
        ) | Where-Object { $_ } | Select-Object -First 1
    }
    else {
        'unknown'
    }
    $claimsTenantId = if ($claims) { Get-AACPropertyValue -InputObject $claims -Name 'tid' } else { $null }
    $signedInTenantId = if ($claimsTenantId) { $claimsTenantId } else { $TenantId }

    $global:AACSession = [pscustomobject]@{
        PSTypeName = 'AAC.Session'
        Account    = $account
        TenantId   = $signedInTenantId
        ClientId   = $ClientId
        Scope      = $Scope
        AccessToken  = $tokenResponse.access_token
        RefreshToken = Get-AACPropertyValue -InputObject $tokenResponse -Name 'refresh_token'
        ExpiresOn    = (Get-Date).AddSeconds([int]$tokenResponse.expires_in)
        ConnectedAt  = Get-Date
    }

    $summary = "[grey58]Account:[/]  $($global:AACSession.Account)`n[grey58]Tenant:[/]   $($global:AACSession.TenantId)`n[grey58]Expires:[/]  $($global:AACSession.ExpiresOn.ToString('u'))"
    Show-AACPanel -Content $summary -Header 'Connected' -BorderColor 'green1' -AllowMarkup

    if ($PassThru) {
        return $global:AACSession
    }
}
