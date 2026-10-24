function Invoke-AACBrowserSignIn {
    <#
    .SYNOPSIS
        Signs in with the browser - OAuth 2.0 authorization code flow with
        PKCE and a one-shot localhost listener - and returns the tokens.
    .DESCRIPTION
        The sign-in behind Connect-AAC (Azure Resource Manager) and
        Get-AACEntraGroupMembership (Microsoft Graph):
          1. a PKCE verifier and challenge (RFC 7636, S256) and a random state
          2. a listener on a free localhost port, the redirect URI
          3. the browser opened at the authorize endpoint (the URL is also
             printed, for when it can't be opened)
          4. the code from the redirect - within -TimeoutSeconds, with the
             state checked against cross-site request forgery
          5. the code exchanged for tokens, with the verifier
        No secret, no device code. Progress shows on the Invoke-AACProgress
        display: -Purpose names what the sign-in is for.

        Returns @{ Response (the token response); Account; TenantId (from
        the ID token, else -TenantId); ExpiresOn }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $TenantId,

        [Parameter(Mandatory)]
        [string] $ClientId,

        [Parameter(Mandatory)]
        [string[]] $Scope,

        [int] $TimeoutSeconds = 180,

        [string] $Purpose = 'sign in'
    )

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

        Write-AACMarkup "[grey58]Opening your browser to $([Spectre.Console.Markup]::Escape($Purpose)). If it doesn't open, go to:[/]"
        Write-AACMarkup "[deepskyblue3_1]$([Spectre.Console.Markup]::Escape($authorizeUrl))[/]"

        try {
            Start-Process -FilePath $authorizeUrl | Out-Null
        }
        catch {
            Write-AACMarkup "[gold1]Could not open a browser automatically: $([Spectre.Console.Markup]::Escape($_.Exception.Message))[/]"
        }

        $authorizationResult = Invoke-AACProgress -ScriptBlock {
            Update-AACProgress -Id 'signin' -Indeterminate -Description "Waiting for you to $Purpose in your browser (up to $TimeoutSeconds s)"
            $result = & {
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
            Update-AACProgress -Id 'signin' -Complete -Description $(if ($result.TimedOut) { 'Sign-in timed out' } else { 'Signed in in the browser' })
            $result
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

    $tokenResponse = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'token' -Indeterminate -Description 'Exchanging the sign-in code for a token'
        try {
            $response = Invoke-RestMethod -Uri $tokenEndpoint -Method Post -Body $tokenBody -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop -Verbose:$false
        }
        catch {
            $details = $_.ErrorDetails.Message
            throw "Token exchange failed: $(if ($details) { $details } else { $_.Exception.Message })"
        }
        Update-AACProgress -Id 'token' -Complete -Description 'Token received'
        $response
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

    @{
        Response  = $tokenResponse
        Account   = $account
        TenantId  = $(if ($claimsTenantId) { $claimsTenantId } else { $TenantId })
        ExpiresOn = (Get-Date).AddSeconds([int]$tokenResponse.expires_in)
    }
}
