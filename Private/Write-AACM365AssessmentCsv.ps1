function Write-AACM365AssessmentCsv {
    <#
    .SYNOPSIS
        Writes Invoke-AACM365Assessment's tables to CSV files in a folder,
        and returns the files.
    .DESCRIPTION
        findings, settings, conditional-access, named-locations, admin-roles,
        mfa-registration, authentication-methods, licenses,
        identity-providers, domains, secure-score, enrollment-restrictions,
        compliance-policies, endpoint-security, managed-devices,
        entra-devices and permissions - each prefixed m365-. Empty tables are
        left out.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Assessment,

        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
    $files = [ordered]@{
        findings = 'Findings'; settings = 'Settings'; 'conditional-access' = 'ConditionalAccess'; 'named-locations' = 'NamedLocations'; 'admin-roles' = 'RoleAssignments'
        'mfa-registration' = 'Registration'; 'authentication-methods' = 'AuthenticationMethods'; licenses = 'Licenses'; 'identity-providers' = 'IdentityProviders'; domains = 'Domains'
        'secure-score' = 'SecureScoreControls'; 'enrollment-restrictions' = 'EnrollmentRestrictions'; 'compliance-policies' = 'CompliancePolicies'; 'endpoint-security' = 'EndpointSecurity'
        'managed-devices' = 'ManagedDevices'; 'entra-devices' = 'EntraDevices'; permissions = 'Permissions'
        'mfa-coverage' = 'MfaCoverage'; 'emergency-access' = 'EmergencyAccess'; 'privileged-accounts' = 'PrivilegedAccounts'; 'app-credentials' = 'AppCredentials'
        'app-permissions' = 'AppPermissions'; 'redirect-uris' = 'RedirectUris'; 'legacy-authentication' = 'LegacyAuthentication'
        'pim-role-settings' = 'PimRoleSettings'; 'group-exposure' = 'GroupExposure'; 'access-reviews' = 'AccessReviews'; 'risky-users' = 'RiskyUsers'
        'risk-detections' = 'RiskDetections'; incidents = 'Incidents'; 'inactive-users' = 'InactiveUsers'; 'app-protection' = 'AppProtection'; coverage = 'Coverage'
    }
    foreach ($file in $files.Keys) {
        $rows = @($Assessment[$files[$file]])
        if (-not $rows.Count) { continue }
        $target = Join-Path -Path $Path -ChildPath "m365-$file.csv"
        $rows | Export-Csv -LiteralPath $target -NoTypeInformation -Encoding utf8
        Get-Item -LiteralPath $target
    }
}
