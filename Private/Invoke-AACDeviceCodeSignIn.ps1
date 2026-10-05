function Invoke-AACDeviceCodeSignIn {
    <#
    .SYNOPSIS
        Signs in with the OAuth 2.0 device code flow: shows a code to enter
        at https://microsoft.com/devicelogin on any device, and waits.
    .DESCRIPTION
        For a console with no browser - SSH, a container, Cloud Shell. The
        code and the address are shown in a Spectre.Console panel; the token
        endpoint is asked at the interval Entra ID gives until the sign-in is
        done, declined or the code expires.

        Returns @{ Response (the token response); Account; TenantId } - the
        same shape as Invoke-AACBrowserSignIn.
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

        [int] $TimeoutSeconds = 900
    )

    $ProgressPreference = 'SilentlyContinue'
    $base = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0"
    try {
        $code = Invoke-RestMethod -Uri "$base/devicecode" -Method Post -Body @{ client_id = $ClientId; scope = ($Scope -join ' ') } -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop -Verbose:$false
    }
    catch {
        throw "Could not start the device code sign-in: $($_.Exception.Message)"
    }

    $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
    Show-AACPanel -Content "Open [link]$(& $escape $code.verification_uri)[/] on any device and enter the code`n`n    [bold yellow]$(& $escape $code.user_code)[/]`n`n[grey58]Waiting for you to finish signing in (the code expires in $([int]([int]$code.expires_in / 60)) minutes).[/]" -Header 'Sign in with a code' -BorderColor 'deepskyblue1' -AllowMarkup

    $interval = [Math]::Max(2, [int]$code.interval)
    $deadline = (Get-Date).AddSeconds([Math]::Min([int]$code.expires_in, $TimeoutSeconds))
    $body = @{ grant_type = 'urn:ietf:params:oauth:grant-type:device_code'; client_id = $ClientId; device_code = $code.device_code }
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds $interval
        try {
            $response = Invoke-RestMethod -Uri "$base/token" -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop -Verbose:$false
        }
        catch {
            $details = if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction Ignore }
            $reasonCode = if ($details) { [string](Get-AACPropertyValue -InputObject $details -Name 'error') } else { '' }
            if ($reasonCode -eq 'authorization_pending') { continue }
            if ($reasonCode -eq 'slow_down') { $interval += 5; continue }
            $description = if ($details) { [string](Get-AACPropertyValue -InputObject $details -Name 'error_description') } else { $_.Exception.Message }
            throw "The sign-in didn't complete: $(($description -split '\r?\n')[0])"
        }
        $idToken = Get-AACPropertyValue -InputObject $response -Name 'id_token'
        $claims = if ($idToken) { ConvertFrom-AACJwt -Token $idToken } else { ConvertFrom-AACJwt -Token $response.access_token }
        $account = @((Get-AACPropertyValue -InputObject $claims -Name 'preferred_username'), (Get-AACPropertyValue -InputObject $claims -Name 'upn'), (Get-AACPropertyValue -InputObject $claims -Name 'name')) | Where-Object { $_ } | Select-Object -First 1
        $tenant = Get-AACPropertyValue -InputObject $claims -Name 'tid'
        return @{ Response = $response; Account = [string]$account; TenantId = $(if ($tenant) { [string]$tenant } else { $TenantId }) }
    }
    throw 'The sign-in code expired before the sign-in was finished. Run Connect-AAC -DeviceCode again.'
}
