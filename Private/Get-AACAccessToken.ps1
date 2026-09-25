function Get-AACAccessToken {
    <#
    .SYNOPSIS
        Returns a valid Azure Resource Manager access token for the current
        session, silently refreshing it first if it is expired or about to expire.
    .DESCRIPTION
        Every command that calls an Azure REST API goes through this function
        rather than reading $global:AACSession.AccessToken directly, so the
        refresh-on-expiry behavior is guaranteed to be applied consistently.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # No web-request progress bar over a Spectre display on a token refresh.
    $ProgressPreference = 'SilentlyContinue'

    if (-not $global:AACSession) {
        throw 'Not connected to Azure. Run Connect-AAC first.'
    }

    # Refresh a little early (2 minutes of slack) so a token that is valid right
    # now doesn't expire mid-flight during a slow REST call.
    if ((Get-Date) -lt $global:AACSession.ExpiresOn.AddSeconds(-120)) {
        return $global:AACSession.AccessToken
    }

    if (-not $global:AACSession.RefreshToken) {
        throw 'The Azure sign-in has expired and no refresh token is available. Run Connect-AAC again.'
    }

    $tokenEndpoint = "https://login.microsoftonline.com/$($global:AACSession.TenantId)/oauth2/v2.0/token"
    $body = @{
        grant_type    = 'refresh_token'
        refresh_token = $global:AACSession.RefreshToken
        client_id     = $global:AACSession.ClientId
        scope         = ($global:AACSession.Scope -join ' ')
    }

    try {
        $response = Invoke-RestMethod -Uri $tokenEndpoint -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop -Verbose:$false
    }
    catch {
        throw "Failed to refresh the Azure access token: $($_.Exception.Message). Run Connect-AAC again."
    }

    $global:AACSession.AccessToken = $response.access_token
    $refreshToken = Get-AACPropertyValue -InputObject $response -Name 'refresh_token'
    if ($refreshToken) {
        $global:AACSession.RefreshToken = $refreshToken
    }
    $global:AACSession.ExpiresOn = (Get-Date).AddSeconds([int]$response.expires_in)

    return $global:AACSession.AccessToken
}
