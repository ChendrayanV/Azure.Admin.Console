function ConvertTo-AACLegacyAuthentication {
    <#
    .SYNOPSIS
        Builds Get-AACLegacyAuthentication's findings (AAC.LegacyAuthentication)
        from the Resource Graph rows and Microsoft Graph answers of
        Get-AACLegacyAuthenticationQuery: every place that still accepts a
        key, a password, an old protocol or old TLS - and what to do.
    .DESCRIPTION
        No Azure calls. -Read is Invoke-AACGraphBatch's result; -Entra is
        Read-AACGraphQuery's (Data, Errors), or $null when Entra ID wasn't
        read; -Publishing maps an App Service app's ID (lower case) to
        @{ Ftp; Scm } (basic authentication allowed?), or $null when that
        app's policies couldn't be read. Rows of subscriptions not in
        -SubscriptionName are left out.

        Severity: High for what an attacker can use today - legacy-protocol
        sign-ins that succeed, legacy authentication not blocked, a non-TLS
        port, TLS 1.0/1.1, an AKS cluster without Entra ID; Medium for keys,
        SAS, local accounts and passwords that bypass Entra ID (no MFA, no
        Conditional Access, no per-user audit), implicit grant and public
        client flows, SMS and voice; Low for what is weaker than it should
        be (client secrets, Key Vault access policies, telemetry keys).

        Returns @{ Findings; Notices; Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Read,

        [hashtable] $Entra,

        [hashtable] $Publishing = @{},

        [string[]] $Protocols = @(),

        [int] $SignInDays = 7,

        [hashtable] $SubscriptionName = @{}
    )

    $get = ${function:Get-AACMember}
    $text = { param($Object, [string] $Path) $v = & $get $Object $Path; if ($null -eq $v) { '' } else { [string]$v } }
    $list = { param($Item) @(if ($Item -is [System.Collections.IEnumerable] -and $Item -isnot [string] -and $Item -isnot [System.Collections.IDictionary]) { $Item } elseif ($null -ne $Item) { , $Item }) | Where-Object { $null -ne $_ -and '' -ne $_ } }
    $rowsOf = { param([string] $Name) @(if ($Read.Rows -and $Read.Rows.Contains($Name)) { $Read.Rows[$Name] | Where-Object { $null -ne $_ -and $SubscriptionName.Contains(([string]$_['subscriptionId']).ToLowerInvariant()) } }) }
    $label = { param([string] $Id) $s = ([string]$Id).ToLowerInvariant(); if ($SubscriptionName.Contains($s)) { $SubscriptionName[$s] } else { $Id } }
    $isTrue = { param([string] $Value) $Value -eq 'True' }
    $oldTls = { param([string] $Value) $Value -match '^(TLS)?1[._]?[01]$|^TLS1_[01]$|^1\.[01]$' }
    $docs = 'https://learn.microsoft.com'
    $notices = [System.Collections.Generic.List[string]]::new()
    $findings = [System.Collections.Generic.List[object]]::new()
    $azure = {
        param($Row, [string] $Severity, [string] $Category, [string] $Finding, [string] $Detail, [string] $Impact, [string] $Remediation, [string] $Link, [string] $Effort = 'Medium')
        $findings.Add((New-AACFinding -TypeName 'AAC.LegacyAuthentication' -Severity $Severity -Category $Category -Finding $Finding -ResourceId (& $text $Row 'id') -Resource (& $text $Row 'name') -ResourceType (& $text $Row 'type') -ResourceGroup (& $text $Row 'resourceGroup') `
                    -Subscription (& $label (& $text $Row 'subscriptionId')) -Detail $Detail -Impact $Impact -Remediation $Remediation -Effort $Effort -Link $Link -Property ([ordered]@{ Area = 'Azure'; Count = 1 })))
    }
    $tenant = {
        param([string] $Severity, [string] $Category, [string] $Finding, [string] $Resource, [string] $Detail, [string] $Impact, [string] $Remediation, [string] $Link, [int] $Count = 1, [string] $Effort = 'Medium')
        $findings.Add((New-AACFinding -TypeName 'AAC.LegacyAuthentication' -Severity $Severity -Category $Category -Finding $Finding -Resource $Resource -ResourceType 'Entra ID' -Subscription 'Tenant' `
                    -Detail $Detail -Impact $Impact -Remediation $Remediation -Effort $Effort -Link $Link -Property ([ordered]@{ Area = 'Entra ID'; Count = $Count })))
    }
    $bypass = 'It bypasses Entra ID: no MFA, no Conditional Access, no per-user audit - and a leaked key or password works from anywhere until it is rotated.'
    foreach ($key in @($Read.Errors.Keys | Sort-Object)) { $notices.Add("The $key couldn't be read: $($Read.Errors[$key] -replace '\s+', ' ')") }

    # --- Azure resources -------------------------------------------------------------------------------------------------
    foreach ($row in (& $rowsOf 'storage')) {
        if ((& $text $row 'sharedKey') -ne 'False') { & $azure $row 'Medium' 'Keys and SAS' 'Storage account accepts shared keys' "$(& $text $row 'name') allows Shared Key authorization (account keys, and SAS signed with them)." "Anyone with an account key has full control of its data. $bypass" 'Move clients to Entra ID (data-plane RBAC roles, user delegation SAS), then set Allow storage account key access to Disabled.' "$docs/azure/storage/common/shared-key-authorization-prevent" }
        if (& $oldTls (& $text $row 'tls')) { & $azure $row 'High' 'Old TLS' 'Storage account accepts TLS 1.0/1.1' "$(& $text $row 'name') allows $(& $text $row 'tls')." 'TLS 1.0 and 1.1 have known weaknesses and are being removed across Azure: clients relying on them will break.' 'Set the minimum TLS version to TLS 1.2 (check old clients first with the storage logs).' "$docs/azure/storage/common/transport-layer-security-configure-minimum-version" 'Low' }
    }
    foreach ($row in (& $rowsOf 'sql')) {
        if (-not (& $isTrue (& $text $row 'entraOnly'))) { & $azure $row 'Medium' 'Passwords' 'SQL authentication enabled' "$(& $text $row 'name') accepts SQL logins (user name and password)." $bypass 'Create Entra ID users for the applications (managed identities) and people, then turn on Microsoft Entra-only authentication.' "$docs/azure/azure-sql/database/authentication-azure-ad-only-authentication" }
        if (& $oldTls (& $text $row 'tls')) { & $azure $row 'High' 'Old TLS' 'SQL server accepts TLS 1.0/1.1' "$(& $text $row 'name') has minimal TLS version $(& $text $row 'tls')." 'TLS 1.0 and 1.1 have known weaknesses and are retired for Azure SQL.' 'Set the minimal TLS version to 1.2.' "$docs/azure/azure-sql/database/connectivity-settings" 'Low' }
    }
    foreach ($row in (& $rowsOf 'postgres')) {
        if ((& $text $row 'password') -eq 'Enabled') { & $azure $row 'Medium' 'Passwords' 'PostgreSQL password authentication enabled' "$(& $text $row 'name') accepts PostgreSQL passwords$(if ((& $text $row 'entra') -ne 'Enabled') { ', and Entra ID authentication is off' })." $bypass 'Turn on Microsoft Entra authentication, move roles to Entra ID principals, then turn password authentication off.' "$docs/azure/postgresql/flexible-server/concepts-azure-ad-authentication" }
    }
    $localNames = @{
        'microsoft.documentdb/databaseaccounts' = 'account keys'; 'microsoft.servicebus/namespaces' = 'SAS keys'; 'microsoft.eventhub/namespaces' = 'SAS keys'; 'microsoft.relay/namespaces' = 'SAS keys'
        'microsoft.eventgrid/topics' = 'access keys and SAS'; 'microsoft.eventgrid/domains' = 'access keys and SAS'; 'microsoft.signalrservice/signalr' = 'access keys'; 'microsoft.signalrservice/webpubsub' = 'access keys'
        'microsoft.appconfiguration/configurationstores' = 'access keys'; 'microsoft.cognitiveservices/accounts' = 'API keys'; 'microsoft.search/searchservices' = 'API keys'; 'microsoft.automation/automationaccounts' = 'local (webhook and agent key) authentication'
        'microsoft.operationalinsights/workspaces' = 'workspace keys for ingestion'; 'microsoft.insights/components' = 'instrumentation keys for ingestion'; 'microsoft.devices/iothubs' = 'SAS keys'; 'microsoft.batch/batchaccounts' = 'shared keys'
    }
    foreach ($row in (& $rowsOf 'localAuth')) {
        $type = & $text $row 'type'
        $allowed = if ($type -eq 'microsoft.batch/batchaccounts') { @(& $list (& $get $row 'modes')) -contains 'SharedKey' } else { -not (& $isTrue (& $text $row 'disabled')) }
        if (-not $allowed) { continue }
        $telemetry = $type -in 'microsoft.operationalinsights/workspaces', 'microsoft.insights/components'
        & $azure $row $(if ($telemetry) { 'Low' } else { 'Medium' }) 'Keys and SAS' 'Local authentication enabled' "$(& $text $row 'name') ($($type -replace '^microsoft\.', '')) accepts $($localNames[$type])." $(if ($telemetry) { 'Anyone with the key can send data into it - spoofed telemetry or logs.' } else { $bypass }) 'Move clients to Entra ID (managed identities and RBAC data roles), then disable local authentication (disableLocalAuth).' "$docs/azure/security/fundamentals/identity-management-best-practices"
    }
    foreach ($row in (& $rowsOf 'registries')) {
        if (& $isTrue (& $text $row 'admin')) { & $azure $row 'Medium' 'Passwords' 'Container registry admin user enabled' "$(& $text $row 'name') has its admin user (a shared user name and two passwords) enabled." "Whoever has the password can push and pull every image. $bypass" 'Use Entra ID (AcrPull/AcrPush roles for managed identities, or tokens with scope maps), then disable the admin user.' "$docs/azure/container-registry/container-registry-authentication" 'Low' }
    }
    foreach ($row in (& $rowsOf 'redis')) {
        if (& $isTrue (& $text $row 'nonSsl')) { & $azure $row 'High' 'Old TLS' 'Redis non-TLS port open' "$(& $text $row 'name') listens on port 6379 without TLS." 'Its access key and data cross the network in clear text.' 'Disable the non-TLS port; clients connect to 6380 with TLS.' "$docs/azure/azure-cache-for-redis/cache-configure" 'Low' }
        if (-not (& $isTrue (& $text $row 'keysOff'))) { & $azure $row 'Medium' 'Keys and SAS' 'Redis access key authentication enabled' "$(& $text $row 'name') accepts its access keys." $bypass 'Use Microsoft Entra authentication for Redis, then disable access key authentication.' "$docs/azure/azure-cache-for-redis/cache-azure-active-directory-for-authentication" }
        if (& $oldTls (& $text $row 'tls')) { & $azure $row 'High' 'Old TLS' 'Redis accepts TLS 1.0/1.1' "$(& $text $row 'name') has minimum TLS $(& $text $row 'tls')." 'TLS 1.0 and 1.1 are retired for Azure Cache for Redis.' 'Set the minimum TLS version to 1.2.' "$docs/azure/azure-cache-for-redis/cache-remove-tls-10-11" 'Low' }
    }
    foreach ($row in (& $rowsOf 'aks')) {
        if ((& $text $row 'entra') -ne 'True') { & $azure $row 'High' 'Local accounts' 'AKS cluster without Entra ID integration' "$(& $text $row 'name') authenticates with certificates in a kubeconfig only." 'Cluster access can''t be tied to people, MFA or Conditional Access - and certificates can''t be revoked one by one.' 'Enable AKS-managed Microsoft Entra integration (and Azure RBAC for Kubernetes authorization).' "$docs/azure/aks/enable-authentication-microsoft-entra-id" 'High' }
        elseif (-not (& $isTrue (& $text $row 'localOff'))) { & $azure $row 'Medium' 'Local accounts' 'AKS local accounts enabled' "$(& $text $row 'name') still issues the local cluster-admin kubeconfig." 'Anyone allowed to list cluster admin credentials gets full control without Entra ID.' 'Disable local accounts (--disable-local-accounts) once everyone signs in with Entra ID.' "$docs/azure/aks/manage-local-accounts-managed-azure-ad" }
    }
    foreach ($row in (& $rowsOf 'vms')) {
        if ((& $text $row 'linux') -eq 'True' -and (& $text $row 'passwordOff') -eq 'False') { & $azure $row 'Medium' 'Passwords' 'Linux VM allows password login' "$(& $text $row 'name') accepts SSH passwords." 'Passwords can be guessed or sprayed; keys or Entra ID sign-in can''t.' 'Use SSH keys or Microsoft Entra login for Linux, then set PasswordAuthentication no.' "$docs/entra/identity/devices/howto-vm-sign-in-azure-ad-linux" }
    }
    foreach ($row in (& $rowsOf 'keyVaults')) {
        if (-not (& $isTrue (& $text $row 'rbac'))) { & $azure $row 'Low' 'Legacy authorization' 'Key Vault uses access policies' "$(& $text $row 'name') authorizes with vault access policies, not Azure RBAC." 'Access policies can''t be scoped to one secret, aren''t covered by PIM, and whoever can change the vault can grant themselves access.' 'Switch the vault''s permission model to Azure RBAC (assign the Key Vault data roles first).' "$docs/azure/key-vault/general/rbac-migration" }
    }
    $publishingUnread = 0
    foreach ($row in (& $rowsOf 'sites')) {
        $id = & $text $row 'id'
        if (-not $Publishing.Contains($id)) { continue }
        if ($null -eq $Publishing[$id]) { $publishingUnread++; continue }
        $p = $Publishing[$id]
        if ($p.Scm) { & $azure $row 'Medium' 'Passwords' 'Basic authentication for deployment (SCM) enabled' "$(& $text $row 'name') accepts its publishing user name and password for Kudu and Web Deploy." "The publishing profile is a password to deploy code. $bypass" 'Deploy with Entra ID (GitHub Actions or DevOps with OIDC, az webapp deploy), then turn SCM Basic Auth Publishing Credentials off.' "$docs/azure/app-service/configure-basic-auth-disable" 'Low' }
        if ($p.Ftp) { & $azure $row 'Medium' 'Passwords' 'FTP basic authentication enabled' "$(& $text $row 'name') accepts FTP with its publishing credentials." 'FTP sends the credentials and code (FTPS aside) in a protocol nobody should still need.' 'Turn FTP Basic Auth Publishing Credentials off (and set FTP state to Disabled).' "$docs/azure/app-service/configure-basic-auth-disable" 'Low' }
    }
    if ($publishingUnread) { $notices.Add("The publishing credential policies of $publishingUnread app(s) couldn't be read.") }

    # --- Entra ID ----------------------------------------------------------------------------------------------------------
    if ($null -ne $Entra) {
        $data = if ($Entra.Contains('Data')) { $Entra.Data } else { @{} }
        $failed = if ($Entra.Contains('Errors')) { $Entra.Errors } else { @{} }
        $signInErrors = @($failed.Keys | Where-Object { $_ -like 'signIns|*' })
        if ($signInErrors.Count) { $notices.Add("Sign-ins couldn't be read (they need AuditLog.Read.All and Entra ID P1): $(@($signInErrors | ForEach-Object { $failed[$_] } | Select-Object -Unique -First 1) -replace '\s+', ' ')") }
        foreach ($key in @($failed.Keys | Where-Object { $_ -notlike 'signIns|*' } | Sort-Object)) { $notices.Add("The $(@{ conditionalAccess = 'Conditional Access policies (Policy.Read.All)'; securityDefaults = 'security defaults (Policy.Read.All)'; applications = 'app registrations (Application.Read.All)'; authMethods = 'authentication methods policy (Policy.Read.All)' }[$key]) couldn't be read: $($failed[$key] -replace '\s+', ' ')") }

        foreach ($protocol in $Protocols) {
            $key = "signIns|$protocol"
            if (-not $data.Contains($key)) { continue }
            $signIns = @(& $list $data[$key])
            if (-not $signIns.Count) { continue }
            $ok = @($signIns | Where-Object { [string](& $get $_ 'status.errorCode') -eq '0' })
            $users = @($signIns | Group-Object { & $text $_ 'userPrincipalName' } | Sort-Object Count -Descending)
            $top = (@($users | Select-Object -First 5 | ForEach-Object { "$($_.Name) ($($_.Count))" }) -join ', ')
            $capped = if ($signIns.Count -ge 500) { ' (the first 500 read)' } else { '' }
            if ($ok.Count) {
                & $tenant 'High' 'Legacy protocols' "Successful sign-ins over $protocol" $protocol "$($ok.Count) successful of $($signIns.Count) sign-in(s)$capped in $SignInDays day(s), by $($users.Count) user(s): $top." "$protocol can't do MFA: a password alone gets in, and Conditional Access requirements can't apply." "Move these users and apps to modern authentication (OAuth), then block legacy authentication with Conditional Access." "$docs/entra/identity/conditional-access/policy-block-legacy-authentication" $ok.Count
            }
            else {
                & $tenant 'Medium' 'Legacy protocols' "Failed sign-ins over $protocol" $protocol "$($signIns.Count) failed sign-in(s)$capped in $SignInDays day(s), for $($users.Count) user(s): $top." 'Failed legacy sign-ins are typically password spraying - attacks that MFA can''t stop over these protocols.' 'Block legacy authentication with Conditional Access so these attempts are refused before the password is checked.' "$docs/entra/identity/conditional-access/policy-block-legacy-authentication" $signIns.Count
            }
        }

        if ($data.Contains('conditionalAccess') -or $data.Contains('securityDefaults')) {
            $policies = @(& $list $data['conditionalAccess'])
            $blocks = { param($Policy) $apps = @(& $list (& $get $Policy 'conditions.clientAppTypes')); ($apps -contains 'exchangeActiveSync' -or $apps -contains 'other') -and @(& $list (& $get $Policy 'grantControls.builtInControls')) -contains 'block' -and @(& $list (& $get $Policy 'conditions.users.includeUsers')) -contains 'All' }
            $enforced = @($policies | Where-Object { (& $text $_ 'state') -eq 'enabled' -and (& $blocks $_) })
            $reportOnly = @($policies | Where-Object { (& $text $_ 'state') -eq 'enabledForReportingButNotEnforced' -and (& $blocks $_) })
            $defaults = (& $text $data['securityDefaults'] 'isEnabled') -eq 'True'
            if (-not $enforced.Count -and -not $defaults -and $data.Contains('conditionalAccess')) {
                if ($reportOnly.Count) { & $tenant 'Medium' 'Legacy protocols' 'Legacy authentication block is report-only' (& $text $reportOnly[0] 'displayName') "Conditional Access policy '$(& $text $reportOnly[0] 'displayName')' would block legacy authentication, but only reports." 'Legacy protocols still sign in with a password alone.' 'Check its report-only results (sign-in logs), exclude what must stay, and turn it On.' "$docs/entra/identity/conditional-access/policy-block-legacy-authentication" }
                else { & $tenant 'High' 'Legacy protocols' 'Legacy authentication not blocked' 'Tenant' 'No enabled Conditional Access policy blocks legacy authentication (Exchange ActiveSync and other clients) for all users, and security defaults are off.' 'Over legacy protocols a password alone signs in - the most common way accounts are taken over.' 'Create a Conditional Access policy: all users, client apps Exchange ActiveSync and Other clients, Block access (report-only first).' "$docs/entra/identity/conditional-access/policy-block-legacy-authentication" }
            }
        }

        $apps = @(& $list $data['applications'])
        foreach ($app in $apps) {
            $name = & $text $app 'displayName'
            if ((& $text $app 'web.implicitGrantSettings.enableAccessTokenIssuance') -eq 'True') { & $tenant 'Medium' 'Legacy flows' 'Implicit grant issues access tokens' $name "App registration $name ($(& $text $app 'appId')) allows the implicit grant for access tokens." 'Tokens are returned in the URL fragment, where browser history, logs and extensions can read them.' 'Move the app to the authorization code flow with PKCE (MSAL.js 2+), then turn off access tokens under Implicit grant.' "$docs/entra/identity-platform/v2-oauth2-implicit-grant-flow" 1 'Medium' }
            if ((& $text $app 'isFallbackPublicClient') -eq 'True') { & $tenant 'Medium' 'Legacy flows' 'Public client flows allowed' $name "App registration $name ($(& $text $app 'appId')) allows public client flows (resource owner password credentials, device code)." 'ROPC sends the user''s password to the app and can''t do MFA; device code can be phished.' 'Turn off Allow public client flows unless a device-code or native scenario needs it.' "$docs/entra/identity-platform/v2-oauth-ropc" 1 'Low' }
        }
        $secretOnly = @($apps | Where-Object { @(& $list (& $get $_ 'passwordCredentials')).Count -and -not @(& $list (& $get $_ 'keyCredentials')).Count })
        if ($secretOnly.Count) {
            & $tenant 'Low' 'Client secrets' 'App registrations authenticate with client secrets' "$($secretOnly.Count) app(s)" "$($secretOnly.Count) app registration(s) have client secrets and no certificate: $(@($secretOnly | Select-Object -First 10 | ForEach-Object { & $text $_ 'displayName' }) -join ', ')$(if ($secretOnly.Count -gt 10) { ', ...' })." 'A secret is a password for the app: copied into config files and pipelines, and valid for whoever finds it.' 'Use managed identities or workload identity federation (no secret at all), or certificates; remove the secrets.' "$docs/entra/workload-id/workload-identity-federation" $secretOnly.Count
        }
        if ($data.Contains('authMethods')) {
            foreach ($method in @(& $list (& $get $data['authMethods'] 'authenticationMethodConfigurations') | Where-Object { (& $text $_ 'id') -in 'Sms', 'Voice' -and (& $text $_ 'state') -eq 'enabled' })) {
                & $tenant 'Medium' 'Weak MFA' "$(& $text $method 'id') enabled as an authentication method" (& $text $method 'id') "The authentication methods policy allows $(& $text $method 'id')." 'SMS and voice codes can be intercepted (SIM swap, phone-network attacks): the weakest form of MFA.' 'Move users to Microsoft Authenticator, passkeys or FIDO2 keys; then disable SMS and voice (or keep them for a recovery group only).' "$docs/entra/identity/authentication/concept-authentication-methods-manage" 1 'Medium'
            }
        }
    }

    $rank = (Get-AACSeverityRank).Rank
    $sorted = @($findings | Sort-Object -Property @{ Expression = { $rank[$_.Severity] } }, Area, Category, Finding, Resource)
    $successful = 0; foreach ($f in @($sorted | Where-Object { $_.Category -eq 'Legacy protocols' -and $_.Finding -like 'Successful*' })) { $successful += [int]$f.Count }
    @{
        Findings = $sorted
        Notices  = @($notices)
        Stats    = @{
            Findings  = $sorted.Count
            High      = @($sorted | Where-Object Severity -EQ 'High').Count
            Azure     = @($sorted | Where-Object Area -EQ 'Azure').Count
            Entra     = @($sorted | Where-Object Area -EQ 'Entra ID').Count
            Resources = @($sorted | Where-Object Area -EQ 'Azure' | ForEach-Object { $_.ResourceId } | Select-Object -Unique).Count
            SignIns   = $successful
        }
    }
}
