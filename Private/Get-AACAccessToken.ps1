function Get-AACAccessToken {
    <#
    .SYNOPSIS
        Returns a valid access token for the current session - for Azure
        Resource Manager, or with -Resource for another Azure API - silently
        refreshing it first if it is expired or about to expire.
    .DESCRIPTION
        Every command that calls an Azure REST API goes through this function
        rather than reading $script:AACSession.AccessToken directly, so the
        refresh-on-expiry behavior is guaranteed to be applied consistently.

        -Resource names another API by its token audience, e.g.
        https://api.loganalytics.io (Log Analytics queries) or
        https://api.applicationinsights.io (Application Insights queries).
        Its token comes from the sign-in's refresh token - no second browser
        sign-in - and is kept in the session per API until it nears expiry.
        With the default client (the Azure CLI's) these APIs are already
        consented; an App Registration of your own (Connect-AAC -ClientId)
        needs their delegated Data.Read permission.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string] $Resource = 'https://management.azure.com'
    )

    # No web-request progress bar over a Spectre display on a token refresh.
    $ProgressPreference = 'SilentlyContinue'

    if (-not $script:AACSession) {
        throw 'Not connected to Azure. Run Connect-AAC first.'
    }
    $session = $script:AACSession
    $isArm = $Resource.TrimEnd('/') -eq 'https://management.azure.com'

    # Refresh a little early (2 minutes of slack) so a token that is valid right
    # now doesn't expire mid-flight during a slow REST call.
    if ($isArm) {
        if ((Get-Date) -lt $session.ExpiresOn.AddSeconds(-120)) {
            return $session.AccessToken
        }
    }
    else {
        $tokens = Get-AACPropertyValue -InputObject $session -Name 'Tokens'
        if ($null -eq $tokens) {
            $tokens = @{}
            $session | Add-Member -NotePropertyName 'Tokens' -NotePropertyValue $tokens -Force
        }
        $cached = $tokens[$Resource]
        if ($cached -and (Get-Date) -lt $cached.ExpiresOn.AddSeconds(-120)) {
            return $cached.AccessToken
        }
    }

    if (-not $session.RefreshToken) {
        throw 'The Azure sign-in has expired and no refresh token is available. Run Connect-AAC again.'
    }

    $tokenEndpoint = "https://login.microsoftonline.com/$($session.TenantId)/oauth2/v2.0/token"
    $scope = if ($isArm) { $session.Scope -join ' ' } else { "$($Resource.TrimEnd('/'))/.default offline_access" }
    $body = @{
        grant_type    = 'refresh_token'
        refresh_token = $session.RefreshToken
        client_id     = $session.ClientId
        scope         = $scope
    }

    try {
        $response = Invoke-RestMethod -Uri $tokenEndpoint -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop -Verbose:$false
    }
    catch {
        # Entra ID's own reason (AADSTS...) says more than "400 Bad Request".
        $reason = $_.Exception.Message
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $details = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction Ignore
            $description = if ($details) { Get-AACPropertyValue -InputObject $details -Name 'error_description' }
            if ($description) { $reason = ([string]$description -split '\r?\n')[0] }
        }
        if ($isArm) {
            throw "Failed to refresh the Azure access token: $($reason.TrimEnd('.')). Run Connect-AAC again."
        }
        $permission = if ($Resource -like 'https://graph.microsoft.com*') { "Microsoft Graph's delegated Group.Read.All and User.Read.All permissions" } else { "this API's delegated Data.Read permission" }
        throw "Could not get a token for $Resource from the Azure sign-in: $($reason.TrimEnd('.')). Run Connect-AAC again; with an App Registration of your own (-ClientId), give it $permission."
    }

    $refreshToken = Get-AACPropertyValue -InputObject $response -Name 'refresh_token'
    if ($refreshToken) {
        $session.RefreshToken = $refreshToken
    }
    $expiresOn = (Get-Date).AddSeconds([int]$response.expires_in)
    if ($isArm) {
        $session.AccessToken = $response.access_token
        $session.ExpiresOn = $expiresOn
    }
    else {
        $tokens[$Resource] = @{ AccessToken = $response.access_token; ExpiresOn = $expiresOn }
    }

    return $response.access_token
}
