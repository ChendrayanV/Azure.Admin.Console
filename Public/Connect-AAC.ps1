function Connect-AAC {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
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

    # A failure anywhere below ends as a Spectre.Console error panel and this
    # command's own terminating error, not a line inside the module. A stopped
    # pipeline (Select-Object -First, Ctrl+C) is no failure: just return - a
    # rethrow would stop the caller's whole script, not only this command.
    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    Write-AACRule -Title 'Azure Admin Console :: Sign in' -Color 'deepskyblue3_1'

    $signIn = Invoke-AACBrowserSignIn -TenantId $TenantId -ClientId $ClientId -Scope $Scope -TimeoutSeconds $TimeoutSeconds
    $tokenResponse = $signIn.Response
    $account = $signIn.Account
    $signedInTenantId = $signIn.TenantId

    $script:AACSession = [pscustomobject]@{
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

    $summary = "[grey58]Account:[/]  $($script:AACSession.Account)`n[grey58]Tenant:[/]   $($script:AACSession.TenantId)`n[grey58]Expires:[/]  $($script:AACSession.ExpiresOn.ToString('u'))"
    Show-AACPanel -Content $summary -Header 'Connected' -BorderColor 'green1' -AllowMarkup

    if ($PassThru) {
        return $script:AACSession
    }
}
