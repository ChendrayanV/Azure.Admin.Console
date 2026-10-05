function Resolve-AACTenantId {
    <#
    .SYNOPSIS
        Returns a tenant's ID (GUID) from its ID or one of its domains
        (contoso.onmicrosoft.com, contoso.com), from Entra ID's public
        OpenID metadata - no sign-in needed.
    .DESCRIPTION
        A GUID comes back as it is (lower case). A domain is looked up at
        https://login.microsoftonline.com/<domain>/v2.0/.well-known/openid-configuration,
        whose issuer carries the tenant ID. A domain no tenant has throws.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Tenant
    )

    $ProgressPreference = 'SilentlyContinue'
    if ($Tenant -match '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$') { return $Tenant.ToLowerInvariant() }
    try {
        $configuration = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$([uri]::EscapeDataString($Tenant))/v2.0/.well-known/openid-configuration" -Method Get -TimeoutSec 30 -ErrorAction Stop -Verbose:$false
    }
    catch {
        $problem = [System.InvalidOperationException]::new("No Entra ID tenant was found for '$Tenant'.")
        $problem.Data['AACHint'] = 'Use the tenant ID (a GUID) or one of its verified domains, such as contoso.onmicrosoft.com.'
        throw $problem
    }
    $issuer = [string](Get-AACPropertyValue -InputObject $configuration -Name 'issuer')
    if ($issuer -notmatch '/([0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12})/') { throw "Entra ID didn't return a tenant ID for '$Tenant'." }
    $Matches[1].ToLowerInvariant()
}
