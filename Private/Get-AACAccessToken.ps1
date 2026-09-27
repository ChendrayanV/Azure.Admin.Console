function Get-AACAccessToken {
    <#
    .SYNOPSIS
        Returns a valid Azure Resource Manager access token for the current
        session, silently refreshing it first if it is expired or about to expire.
    .DESCRIPTION
        Every command that calls an Azure REST API goes through this function
        rather than reading $script:AACSession.AccessToken directly, so the
        refresh-on-expiry behavior is guaranteed to be applied consistently.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # No web-request progress bar over a Spectre display on a token refresh.
    $ProgressPreference = 'SilentlyContinue'

    if (-not $script:AACSession) {
        throw 'Not connected to Azure. Run Connect-AAC first.'
    }

    # Refresh a little early (2 minutes of slack) so a token that is valid right
    # now doesn't expire mid-flight during a slow REST call.
    if ((Get-Date) -lt $script:AACSession.ExpiresOn.AddSeconds(-120)) {
        return $script:AACSession.AccessToken
    }

    if (-not $script:AACSession.RefreshToken) {
        throw 'The Azure sign-in has expired and no refresh token is available. Run Connect-AAC again.'
    }

    $tokenEndpoint = "https://login.microsoftonline.com/$($script:AACSession.TenantId)/oauth2/v2.0/token"
    $body = @{
        grant_type    = 'refresh_token'
        refresh_token = $script:AACSession.RefreshToken
        client_id     = $script:AACSession.ClientId
        scope         = ($script:AACSession.Scope -join ' ')
    }

    try {
        $response = Invoke-RestMethod -Uri $tokenEndpoint -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop -Verbose:$false
    }
    catch {
        throw "Failed to refresh the Azure access token: $($_.Exception.Message). Run Connect-AAC again."
    }

    $script:AACSession.AccessToken = $response.access_token
    $refreshToken = Get-AACPropertyValue -InputObject $response -Name 'refresh_token'
    if ($refreshToken) {
        $script:AACSession.RefreshToken = $refreshToken
    }
    $script:AACSession.ExpiresOn = (Get-Date).AddSeconds([int]$response.expires_in)

    return $script:AACSession.AccessToken
}
