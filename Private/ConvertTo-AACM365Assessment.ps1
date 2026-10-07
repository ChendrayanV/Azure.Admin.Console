function ConvertTo-AACM365Assessment {
    <#
    .SYNOPSIS
        Builds Invoke-AACM365Assessment's model from what Microsoft Graph
        returned (Get-AACM365AssessmentQuery, Read-AACGraphQuery): Entra ID,
        Microsoft 365 and Intune - and the zero-trust findings.
    .DESCRIPTION
        No Graph calls. -Data maps a query name to its items (a list) or
        object; -Errors maps the queries that failed to Graph's reason;
        -Query gives each query's section, what it reads and the permission
        it needs (for the Permissions table). A query missing from -Data
        leaves its tables empty and its findings out - nothing is guessed.

        Findings (AAC.M365Finding), each with its severity and what to do:
          Entra ID      no MFA (neither security defaults nor a Conditional
                        Access policy requiring it of everyone), admins
                        without an MFA policy, legacy authentication not
                        blocked, no risk-based policy, policies left in
                        report-only, too many or too few Global
                        Administrators, standing privileged access,
                        admins and users without MFA registered, SMS and
                        voice, Authenticator and FIDO2, users creating apps
                        and tenants, guest invitations and access, stale
                        directory sync, no technical contact
          Microsoft 365 Secure Score, Anyone links, external resharing,
                        sharing open to every domain, legacy authentication
                        to SharePoint, audit log search off, unverified
                        domains
          Intune        devices with no compliance policy marked compliant,
                        non-compliant, stale, unencrypted and jailbroken
                        devices, no endpoint security policy for antivirus,
                        firewall, disk encryption, EDR or attack surface
                        reduction, personal devices allowed to enroll, high
                        device limits, active unmanaged Entra devices

        Returns a hashtable of tables (Settings, Licenses, ConditionalAccess,
        NamedLocations, RoleAssignments, Registration,
        AuthenticationMethods, IdentityProviders, Domains, SecureScoreControls,
        EnrollmentRestrictions, CompliancePolicies, EndpointSecurity,
        ManagedDevices, EntraDevices, Permissions, Findings), Notices and
        Stats.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [hashtable] $Data = @{},

        [hashtable] $Errors = @{},

        [System.Collections.IDictionary] $Query = [ordered]@{},

        [ValidateRange(1, 3650)]
        [int] $StaleDays = 90,

        # The days of sign-ins LegacySignIns covers.
        [ValidateRange(1, 30)]
        [int] $SignInDays = 7,

        # Redirect URI host -> $true (resolves), $false (no such host) or
        # $null (unknown): Resolve-AACHostName.
        [hashtable] $Resolved = @{},

        # The queries answered by their Fallback (Users without sign-ins).
        [string[]] $Fallback = @(),

        [datetime] $Now = [datetime]::UtcNow
    )

    # --- Helpers ---------------------------------------------------------------------------------------------
    $get = {
        param($Object, [string] $Path)
        # A key with a dot in it ('@odata.type') first, then a path.
        if ($Object -is [System.Collections.IDictionary]) { foreach ($k in $Object.Keys) { if ($k -eq $Path) { return $Object[$k] } } }
        foreach ($part in $Path.Split('.')) {
            if ($Object -isnot [System.Collections.IDictionary]) { return $null }
            $found = $null
            foreach ($k in $Object.Keys) { if ($k -eq $part) { $found = $Object[$k]; break } }
            $Object = $found
        }
        $Object
    }
    $text = { param($Object, [string] $Path) $v = & $get $Object $Path; if ($null -eq $v) { '' } else { [string]$v } }
    $list = { param($Item) @(if ($Item -is [System.Collections.IEnumerable] -and $Item -isnot [string] -and $Item -isnot [System.Collections.IDictionary]) { $Item } elseif ($null -ne $Item) { , $Item }) | Where-Object { $null -ne $_ -and '' -ne $_ } }
    $has = { param([string] $Name) $Data.Contains($Name) }
    $items = { param([string] $Name) @(if ($Data.Contains($Name)) { & $list $Data[$Name] }) }
    $one = { param([string] $Name) if ($Data.Contains($Name)) { $v = $Data[$Name]; if ($v -is [System.Collections.IDictionary]) { $v } else { @(& $list $v) | Select-Object -First 1 } } }
    $isTrue = { param($Value) [string]$Value -eq 'True' }
    $object = { param([string] $TypeName, [System.Collections.IDictionary] $Property) $item = [pscustomobject]$Property; $item.PSObject.TypeNames.Insert(0, $TypeName); $item }
    $date = {
        param($Value)
        if ($Value -is [datetime]) { return $Value.ToUniversalTime() }
        $d = [datetime]::MinValue
        if ($Value -and [datetime]::TryParse([string]$Value, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$d) -and $d.Year -gt 1601) { $d } else { $null }
    }
    $daysSince = { param($When) if ($When) { [int][Math]::Floor(($Now - $When).TotalDays) } else { $null } }
    $plain = {
        param([string] $Html)
        if (-not $Html) { return '' }
        $t = $Html -replace '(?i)<br\s*/?>|</p>|</li>', "`n" -replace '(?i)<li[^>]*>', '- ' -replace '<[^>]+>', ''
        ([System.Net.WebUtility]::HtmlDecode($t).Replace([char]0x00A0, ' ') -replace '[ \t]+\n', "`n" -replace '\n{3,}', "`n`n").Trim()
    }
    $words = { param([string] $Name) if (-not $Name) { '' } else { (($Name -creplace '([a-z0-9])([A-Z])', '$1 $2').Substring(0, 1).ToUpperInvariant() + ($Name -creplace '([a-z0-9])([A-Z])', '$1 $2').Substring(1)) } }
    $rank = @{ Critical = 0; High = 1; Medium = 2; Low = 3; Info = 4 }
    $learn = 'https://learn.microsoft.com'
    $notices = [System.Collections.Generic.List[string]]::new()
    $findings = [System.Collections.Generic.List[object]]::new()
    $finding = {
        param([string] $Severity, [string] $Area, [string] $Title, [string] $Item, [string] $Detail, [string] $Action, [string] $Link)
        $findings.Add((& $object 'AAC.M365Finding' ([ordered]@{ Severity = $Severity; Area = $Area; Finding = $Title; Item = $Item; Detail = $Detail; Recommendation = $Action; Link = $Link })))
    }
    $settings = [System.Collections.Generic.List[object]]::new()
    $setting = {
        param([string] $Area, [string] $Name, [string] $Value, [string] $Status, [string] $Detail)
        $settings.Add((& $object 'AAC.M365Setting' ([ordered]@{ Area = $Area; Setting = $Name; Value = $Value; Status = $Status; Detail = $Detail })))
    }
    $yesNo = { param($Value) if (& $isTrue $Value) { 'Yes' } else { 'No' } }
    # Registered methods that resist phishing: passkeys (FIDO2), Windows Hello, certificates.
    $phishingResistant = '(?i)fido2|passKey|windowsHelloForBusiness|x509'

    # --- Tenant --------------------------------------------------------------------------------------------------------
    $org = & $one 'Organization'
    if ($org) {
        & $setting 'Tenant' 'Name' (& $text $org 'displayName') 'Info' ''
        & $setting 'Tenant' 'Tenant ID' (& $text $org 'id') 'Info' ''
        & $setting 'Tenant' 'Created' (& $text $org 'createdDateTime') 'Info' ''
        & $setting 'Tenant' 'Country / data location' ((@((& $text $org 'countryLetterCode'), (& $text $org 'preferredDataLocation')) | Where-Object { $_ }) -join ' / ') 'Info' ''
        $sync = & $isTrue (& $get $org 'onPremisesSyncEnabled')
        $lastSync = & $date (& $get $org 'onPremisesLastSyncDateTime')
        & $setting 'Tenant' 'Directory sync (Entra Connect)' $(if ($sync) { "On, last sync $(if ($lastSync) { $lastSync.ToString('yyyy-MM-dd HH:mm') + ' UTC' } else { 'unknown' })" } else { 'Off (cloud only)' }) $(if ($sync -and $lastSync -and (& $daysSince $lastSync) -gt 3) { 'Warning' } else { 'Info' }) ''
        if ($sync -and $lastSync -and (& $daysSince $lastSync) -gt 3) { & $finding 'Medium' 'Entra ID' 'Directory sync has stopped' (& $text $org 'displayName') "The last sync from on-premises was $(& $daysSince $lastSync) days ago: changes (leavers, disabled accounts) aren't reaching Entra ID." 'Check the Entra Connect (or Cloud Sync) server and its health in Entra ID > Hybrid management.' "$learn/entra/identity/hybrid/connect/how-to-connect-health-sync" }
        $contacts = @(& $list (& $get $org 'technicalNotificationMails'))
        & $setting 'Tenant' 'Technical notification e-mails' $(if ($contacts.Count) { $contacts -join '; ' } else { '(none)' }) $(if ($contacts.Count) { 'Good' } else { 'Warning' }) 'Who Microsoft e-mails about the tenant (service and security notices).'
        if (-not $contacts.Count) { & $finding 'Low' 'Entra ID' 'No technical contact' (& $text $org 'displayName') 'Nobody gets Microsoft''s tenant-wide technical and security notifications.' 'Set a monitored mailbox as the technical contact (Entra ID > Overview > Properties).' "$learn/entra/fundamentals/properties-area" }
    }

    # --- Licences -------------------------------------------------------------------------------------------------------
    $licenses = @(@(foreach ($sku in (& $items 'Licenses')) {
            $enabled = [int](& $get $sku 'prepaidUnits.enabled'); $consumed = [int](& $get $sku 'consumedUnits')
            & $object 'AAC.M365License' ([ordered]@{
                    License = & $text $sku 'skuPartNumber'; Enabled = $enabled; Consumed = $consumed; Available = $enabled - $consumed
                    Suspended = [int](& $get $sku 'prepaidUnits.suspended'); Warning = [int](& $get $sku 'prepaidUnits.warning'); Status = & $text $sku 'capabilityStatus'; SkuId = & $text $sku 'skuId'
                })
        }) | Sort-Object -Property @{ Expression = 'Consumed'; Descending = $true }, License)
    $plans = @((& $items 'Licenses') | ForEach-Object { @(& $list (& $get $_ 'servicePlans')) | Where-Object { (& $text $_ 'provisioningStatus') -eq 'Success' } | ForEach-Object { & $text $_ 'servicePlanName' } })
    $hasP2 = [bool]@($plans | Where-Object { $_ -eq 'AAD_PREMIUM_P2' }).Count
    $hasP1 = $hasP2 -or [bool]@($plans | Where-Object { $_ -eq 'AAD_PREMIUM' }).Count

    # --- Security defaults and user / guest settings -----------------------------------------------------------------------
    $defaults = & $one 'SecurityDefaults'
    $defaultsOn = $defaults -and (& $isTrue (& $get $defaults 'isEnabled'))
    if ($defaults) { & $setting 'Entra ID' 'Security defaults' $(if ($defaultsOn) { 'On' } else { 'Off' }) 'Info' 'Microsoft''s baseline: MFA for everyone, legacy authentication blocked. Replace it with Conditional Access when you have Entra ID P1.' }
    $auth = & $one 'AuthorizationPolicy'
    if ($auth) {
        $perm = & $get $auth 'defaultUserRolePermissions'
        $invites = & $text $auth 'allowInvitesFrom'
        $guestRole = (& $text $auth 'guestUserRoleId').ToLowerInvariant()
        $guestAccess = switch ($guestRole) { 'a0b1b346-4d3e-4e8b-98f8-753987be4970' { 'Same as members' } '10dae51f-b6af-4016-8d66-8c2a99b929b3' { 'Limited (default)' } '2af84b1e-32c8-42b7-82bc-daa82404023b' { 'Restricted (most)' } default { $guestRole } }
        $rows = [ordered]@{
            'Users can register applications'       = @((& $yesNo (& $get $perm 'allowedToCreateApps')), $(if (& $isTrue (& $get $perm 'allowedToCreateApps')) { 'Warning' } else { 'Good' }))
            'Users can create security groups'      = @((& $yesNo (& $get $perm 'allowedToCreateSecurityGroups')), 'Info')
            'Users can create tenants'              = @((& $yesNo (& $get $perm 'allowedToCreateTenants')), $(if (& $isTrue (& $get $perm 'allowedToCreateTenants')) { 'Review' } else { 'Good' }))
            'Users can read other users'            = @((& $yesNo (& $get $perm 'allowedToReadOtherUsers')), 'Info')
            'Guest invitations from'                = @((& $words $invites), $(if ($invites -eq 'everyone') { 'Warning' } else { 'Good' }))
            'Guest user access'                     = @($guestAccess, $(if ($guestRole -eq 'a0b1b346-4d3e-4e8b-98f8-753987be4970') { 'Warning' } else { 'Good' }))
            'E-mail verified users can join'        = @((& $yesNo (& $get $auth 'allowEmailVerifiedUsersToJoinOrganization')), $(if (& $isTrue (& $get $auth 'allowEmailVerifiedUsersToJoinOrganization')) { 'Review' } else { 'Good' }))
            'Self-service sign-up for subscriptions' = @((& $yesNo (& $get $auth 'allowedToSignUpEmailBasedSubscriptions')), 'Info')
        }
        foreach ($key in $rows.Keys) { & $setting 'Entra ID' $key $rows[$key][0] $rows[$key][1] '' }
        $userSettings = "$learn/entra/fundamentals/users-default-permissions"
        if (& $isTrue (& $get $perm 'allowedToCreateApps')) { & $finding 'Medium' 'Entra ID' 'Every user can register applications' 'Authorization policy' 'An app any user registers can ask other users for consent to their data - a common phishing route.' 'Set "Users can register applications" to No, and grant the Application Developer role to those who need it.' $userSettings }
        if (& $isTrue (& $get $perm 'allowedToCreateTenants')) { & $finding 'Low' 'Entra ID' 'Every user can create tenants' 'Authorization policy' 'New tenants made by users sit outside your governance.' 'Restrict non-admin users from creating tenants.' $userSettings }
        if ($invites -eq 'everyone') { & $finding 'Medium' 'Entra ID' 'Anyone, guests included, can invite guests' 'Authorization policy' 'Guest invitations are not limited to admins or members.' 'Limit invitations to admins and users in the Guest Inviter role (External collaboration settings).' "$learn/entra/external-id/external-collaboration-settings-configure" }
        if ($guestRole -eq 'a0b1b346-4d3e-4e8b-98f8-753987be4970') { & $finding 'Medium' 'Entra ID' 'Guests have the same access as members' 'Authorization policy' 'Guests can enumerate users, groups and the directory like an employee.' 'Set guest user access to "limited" or "restricted".' "$learn/entra/external-id/external-collaboration-settings-configure" }
        if (& $isTrue (& $get $auth 'allowEmailVerifiedUsersToJoinOrganization')) { & $finding 'Low' 'Entra ID' 'E-mail verified users can join the tenant' 'Authorization policy' 'Anyone with an address in your domains can create a viral (unmanaged) account.' 'Turn off self-service sign-up by e-mail verified users.' $userSettings }
    }
    $crossTenant = & $one 'CrossTenantAccess'
    if ($crossTenant) {
        $inbound = & $get $crossTenant 'inboundTrust'
        & $setting 'Entra ID' 'Cross-tenant: trust MFA from other tenants' (& $yesNo (& $get $inbound 'isMfaAccepted')) 'Info' 'Inbound default for B2B collaboration.'
        & $setting 'Entra ID' 'Cross-tenant: trust compliant devices from other tenants' (& $yesNo (& $get $inbound 'isCompliantDeviceAccepted')) 'Info' ''
    }

    # --- Authentication methods -------------------------------------------------------------------------------------------------
    $methodPolicy = & $one 'AuthenticationMethods'
    $methods = @(foreach ($m in @(& $list (& $get $methodPolicy 'authenticationMethodConfigurations'))) {
            & $object 'AAC.M365AuthenticationMethod' ([ordered]@{
                    Method = & $text $m 'id'; State = & $text $m 'state'
                    Targets = (@(& $list (& $get $m 'includeTargets')) | ForEach-Object { $t = & $text $_ 'id'; if ($t -eq 'all_users') { 'All users' } else { $t } }) -join ', '
                    PhishingResistant = $(if ((& $text $m 'id') -in 'Fido2', 'X509Certificate', 'WindowsHelloForBusiness') { 'Yes' } else { 'No' })
                })
        })
    if ($methodPolicy) {
        & $setting 'Entra ID' 'Authentication methods migration' (& $words (& $text $methodPolicy 'policyMigrationState')) 'Info' 'Whether the legacy MFA and SSPR policies still apply.'
        $state = @{}; foreach ($m in $methods) { $state[$m.Method] = $m.State }
        $methodsLink = "$learn/entra/identity/authentication/concept-authentication-methods-manage"
        $weak = @('Sms', 'Voice' | Where-Object { $state[$_] -eq 'enabled' })
        if ($weak.Count) { & $finding 'Low' 'Entra ID' 'Phishable methods are on' ($weak -join ', ') 'SMS and voice codes can be phished or SIM-swapped.' 'Move users to Microsoft Authenticator or passkeys, then turn SMS and voice off.' $methodsLink }
        if ($state['MicrosoftAuthenticator'] -ne 'enabled') { & $finding 'Medium' 'Entra ID' 'Microsoft Authenticator is off' 'Authentication methods' 'The strongest widely deployable method (push with number matching, passwordless) isn''t available.' 'Turn Microsoft Authenticator on for all users.' $methodsLink }
        if ($state['Fido2'] -ne 'enabled') { & $finding 'Low' 'Entra ID' 'No phishing-resistant method (FIDO2 passkeys) is on' 'Authentication methods' 'Admins can''t use passkeys or security keys.' 'Turn on passkeys (FIDO2), at least for administrators.' $methodsLink }
    }

    # --- Admin roles -------------------------------------------------------------------------------------------------------------
    $privilegedTemplates = @('62e90394-69f5-4237-9190-012177145e10', 'e8611ab8-c189-46e8-94e1-60213ab1f814', '194ae4cb-b126-40b2-bd5b-6091b380977d', '29232cdf-9323-42fd-ade2-1d097af3e4de', 'f28a1f50-f6e7-4571-818b-6a12f2af6b6c', 'fe930be7-5e62-47db-91af-98c3a49a38b1', '9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3', '158c047a-c907-4556-b7ef-446551a6b5f7', 'b1be1c3e-b65d-4f19-8427-f6fa0d97feb9', 'c4e39bd9-1100-46d3-8c65-fb160da0071f', '7be44c8a-adaf-4e2a-84d6-ab2649e08a13', '3a2c62db-5318-420d-8d74-23affee5d9d5', '729827e3-9c14-49f7-bb1b-9608f156bbb8', '8ac3fc64-6eca-42ea-9e69-59f4c7b60eb2')
    $globalAdmin = '62e90394-69f5-4237-9190-012177145e10'
    $roles = @{}
    foreach ($d in (& $items 'RoleDefinitions')) {
        $template = (& $text $d 'templateId').ToLowerInvariant(); $id = (& $text $d 'id').ToLowerInvariant()
        $info = @{ Name = & $text $d 'displayName'; Privileged = (& $isTrue (& $get $d 'isPrivileged')) -or $privilegedTemplates -contains $template -or $privilegedTemplates -contains $id; Global = $template -eq $globalAdmin -or $id -eq $globalAdmin }
        $roles[$id] = $info; if ($template) { $roles[$template] = $info }
    }
    $registration = @{}   # user ID -> registration
    foreach ($r in (& $items 'Registration')) { $registration[(& $text $r 'id').ToLowerInvariant()] = $r }
    $principalNames = @{}
    $roleRows = [System.Collections.Generic.List[object]]::new()
    $addRole = {
        param($Row, [string] $Kind)
        $roleId = (& $text $Row 'roleDefinitionId').ToLowerInvariant()
        $role = if ($roles.Contains($roleId)) { $roles[$roleId] } else { @{ Name = $roleId; Privileged = $privilegedTemplates -contains $roleId; Global = $roleId -eq $globalAdmin } }
        $principal = & $get $Row 'principal'; $principalId = (& $text $Row 'principalId').ToLowerInvariant()
        $type = ([string](& $text $principal '@odata.type')) -replace '^#microsoft\.graph\.', ''
        $name = & $text $principal 'displayName'; if ($name) { $principalNames[$principalId] = $name } elseif ($principalNames.Contains($principalId)) { $name = $principalNames[$principalId] } else { $name = $principalId }
        $reg = $registration[$principalId]
        $roleRows.Add((& $object 'AAC.M365RoleAssignment' ([ordered]@{
                        Role = $role.Name; Principal = $name; PrincipalType = $(if ($type) { & $words $type } else { '' }); UserPrincipalName = & $text $principal 'userPrincipalName'
                        Assignment = $Kind; Privileged = $(if ($role.Privileged) { 'Yes' } else { 'No' }); GlobalAdministrator = $(if ($role.Global) { 'Yes' } else { 'No' })
                        MfaRegistered = $(if ($reg) { & $yesNo (& $get $reg 'isMfaRegistered') } elseif ($type -eq 'user' -or -not $type) { '' } else { 'n/a' })
                        Scope = & $text $Row 'directoryScopeId'; PrincipalId = $principalId; RoleDefinitionId = $roleId
                    })))
    }
    foreach ($row in (& $items 'RoleAssignments')) { & $addRole $row 'Active' }
    foreach ($row in (& $items 'RoleEligibility')) { & $addRole $row 'Eligible' }
    $roleAssignments = @($roleRows | Sort-Object -Property @{ Expression = { if ($_.GlobalAdministrator -eq 'Yes') { 0 } elseif ($_.Privileged -eq 'Yes') { 1 } else { 2 } } }, Role, Principal)
    $rolesLink = "$learn/entra/identity/role-based-access-control/best-practices"
    if (& $has 'RoleAssignments') {
        $globals = @($roleAssignments | Where-Object { $_.GlobalAdministrator -eq 'Yes' } | Select-Object -ExpandProperty PrincipalId -Unique)
        & $setting 'Entra ID' 'Global Administrators' "$($globals.Count)" $(if ($globals.Count -gt 5 -or $globals.Count -lt 2) { 'Warning' } else { 'Good' }) 'Microsoft recommends fewer than five, and at least two (one a break-glass account).'
        if ($globals.Count -gt 5) { & $finding 'Medium' 'Entra ID' 'More than five Global Administrators' "$($globals.Count) accounts" 'Every Global Administrator is a target that can take over the tenant.' 'Move people to least-privileged roles; keep Global Administrator for two to four accounts.' $rolesLink }
        elseif ($globals.Count -lt 2) { & $finding 'Medium' 'Entra ID' 'Fewer than two Global Administrators' "$($globals.Count) account(s)" 'If that account is locked out, nobody can administer the tenant.' 'Add an emergency-access (break-glass) account, excluded from Conditional Access and monitored.' "$learn/entra/identity/role-based-access-control/security-emergency-access" }
        $standing = @($roleAssignments | Where-Object { $_.Assignment -eq 'Active' -and $_.Privileged -eq 'Yes' -and $_.PrincipalType -eq 'User' })
        if ($standing.Count -and $hasP2) { & $finding 'Medium' 'Entra ID' 'Standing privileged access' "$(@($standing | Select-Object -ExpandProperty PrincipalId -Unique).Count) user(s)" "$($standing.Count) privileged role assignment(s) are permanently active, though Entra ID P2 (PIM) is licensed." 'Make privileged roles eligible in Privileged Identity Management, activated just in time with MFA and approval.' "$learn/entra/id-governance/privileged-identity-management/pim-configure" }
    }

    # --- MFA registration ------------------------------------------------------------------------------------------------------------
    $registrationRows = @(@(foreach ($r in (& $items 'Registration')) {
            & $object 'AAC.M365UserRegistration' ([ordered]@{
                    User = & $text $r 'userDisplayName'; UserPrincipalName = & $text $r 'userPrincipalName'; UserType = & $text $r 'userType'; Admin = & $yesNo (& $get $r 'isAdmin')
                    MfaRegistered = & $yesNo (& $get $r 'isMfaRegistered'); MfaCapable = & $yesNo (& $get $r 'isMfaCapable'); Passwordless = & $yesNo (& $get $r 'isPasswordlessCapable')
                    PhishingResistant = $(if (@(& $list (& $get $r 'methodsRegistered')) -match $phishingResistant) { 'Yes' } else { 'No' }); SsprRegistered = & $yesNo (& $get $r 'isSsprRegistered')
                    DefaultMethod = & $text $r 'defaultMfaMethod'; Methods = (@(& $list (& $get $r 'methodsRegistered')) -join ', '); Updated = & $date (& $get $r 'lastUpdatedDateTime'); Id = & $text $r 'id'
                })
        }) | Sort-Object -Property @{ Expression = { if ($_.Admin -eq 'Yes' -and $_.MfaRegistered -eq 'No') { 0 } elseif ($_.MfaRegistered -eq 'No') { 1 } else { 2 } } }, User)
    $members = @($registrationRows | Where-Object UserType -NE 'guest')
    $mfaPercent = if ($members.Count) { [Math]::Round(100 * @($members | Where-Object MfaRegistered -EQ 'Yes').Count / $members.Count) } else { $null }
    if (& $has 'Registration') {
        $mfaLink = "$learn/entra/identity/authentication/howto-registration-mfa-sspr-combined"
        $bareAdmins = @($registrationRows | Where-Object { $_.Admin -eq 'Yes' -and $_.MfaRegistered -eq 'No' })
        if ($bareAdmins.Count) { & $finding 'High' 'Entra ID' 'Administrators without MFA registered' "$($bareAdmins.Count) admin(s)" "$(@($bareAdmins | Select-Object -First 5 -ExpandProperty UserPrincipalName) -join ', ')$(if ($bareAdmins.Count -gt 5) { ', ...' }) can sign in with a password alone." 'Require them to register (a registration campaign, or a Conditional Access policy requiring MFA for admin roles).' $mfaLink }
        if ($null -ne $mfaPercent -and $mfaPercent -lt 90) { & $finding $(if ($mfaPercent -lt 50) { 'High' } else { 'Medium' }) 'Entra ID' 'Users without MFA registered' "$mfaPercent% registered" "$(@($members | Where-Object MfaRegistered -EQ 'No').Count) of $($members.Count) member accounts have no MFA method." 'Run a registration campaign (Authentication methods > Registration campaign) and require MFA with Conditional Access.' $mfaLink }
    }

    # --- Conditional Access ---------------------------------------------------------------------------------------------------------------
    $privilegedRoleIds = @($roles.Keys | Where-Object { $roles[$_].Privileged }) + $privilegedTemplates
    $caRows = @(foreach ($p in (& $items 'ConditionalAccess')) {
            $c = & $get $p 'conditions'; $g = & $get $p 'grantControls'
            $includeUsers = @(& $list (& $get $c 'users.includeUsers')); $includeRoles = @(& $list (& $get $c 'users.includeRoles')); $includeGroups = @(& $list (& $get $c 'users.includeGroups'))
            $excluded = @(& $list (& $get $c 'users.excludeUsers')).Count + @(& $list (& $get $c 'users.excludeGroups')).Count + @(& $list (& $get $c 'users.excludeRoles')).Count
            $apps = @(& $list (& $get $c 'applications.includeApplications')); $actions = @(& $list (& $get $c 'applications.includeUserActions'))
            $clients = @(& $list (& $get $c 'clientAppTypes'))
            $controls = @(& $list (& $get $g 'builtInControls'))
            $strength = & $text $g 'authenticationStrength.displayName'
            $requiresMfa = $controls -contains 'mfa' -or [bool]$strength
            $blocks = $controls -contains 'block'
            $state = & $text $p 'state'
            $risk = @(& $list (& $get $c 'signInRiskLevels')).Count -or @(& $list (& $get $c 'userRiskLevels')).Count
            & $object 'AAC.M365ConditionalAccessPolicy' ([ordered]@{
                    Policy = & $text $p 'displayName'; State = $(switch ($state) { 'enabled' { 'On' } 'disabled' { 'Off' } 'enabledForReportingButNotEnforced' { 'Report-only' } default { $state } })
                    Users = (@($(if ($includeUsers -contains 'All') { 'All users' } elseif ($includeUsers -contains 'GuestsOrExternalUsers') { 'Guests' } elseif ($includeUsers.Count) { "$($includeUsers.Count) user(s)" }), $(if ($includeGroups.Count) { "$($includeGroups.Count) group(s)" }), $(if ($includeRoles.Count) { "$($includeRoles.Count) role(s)" })) | Where-Object { $_ }) -join ', '
                    Excluded = $excluded
                    Applications = $(if ($apps -contains 'All') { 'All cloud apps' } elseif ($actions.Count) { ($actions | ForEach-Object { & $words ($_ -replace '^urn:user:', '') }) -join ', ' } elseif ($apps.Count) { ($apps | ForEach-Object { if ($_ -eq 'Office365') { 'Office 365' } elseif ($_ -eq 'MicrosoftAdminPortals') { 'Admin portals' } else { $_ } }) -join ', ' } else { '' })
                    ClientApps = ($clients | Where-Object { $_ -ne 'all' } | ForEach-Object { & $words $_ }) -join ', '
                    Conditions = (@(
                            $(if (@(& $list (& $get $c 'platforms.includePlatforms')).Count) { "platforms: $(@(& $list (& $get $c 'platforms.includePlatforms')) -join ', ')" })
                            $(if (@(& $list (& $get $c 'locations.includeLocations')).Count) { "locations: $(@(& $list (& $get $c 'locations.includeLocations')).Count) incl., $(@(& $list (& $get $c 'locations.excludeLocations')).Count) excl." })
                            $(if (@(& $list (& $get $c 'signInRiskLevels')).Count) { "sign-in risk: $(@(& $list (& $get $c 'signInRiskLevels')) -join ', ')" })
                            $(if (@(& $list (& $get $c 'userRiskLevels')).Count) { "user risk: $(@(& $list (& $get $c 'userRiskLevels')) -join ', ')" })
                        ) | Where-Object { $_ }) -join '; '
                    Grant = (@($controls | ForEach-Object { & $words $_ }) + @($(if ($strength) { "Strength: $strength" })) | Where-Object { $_ }) -join " $(if ((& $text $g 'operator') -eq 'AND') { 'and' } else { 'or' }) "
                    Session = (@(& $get $p 'sessionControls') | Where-Object { $_ -is [System.Collections.IDictionary] } | ForEach-Object { foreach ($k in $_.Keys) { if ($null -ne $_[$k] -and $_[$k] -isnot [bool] -and (& $text $_[$k] 'isEnabled') -ne 'False') { & $words $k } } }) -join ', '
                    RequiresMfa = $(if ($requiresMfa) { 'Yes' } else { 'No' }); Blocks = $(if ($blocks) { 'Yes' } else { 'No' })
                    Created = & $date (& $get $p 'createdDateTime'); Modified = & $date (& $get $p 'modifiedDateTime'); Id = & $text $p 'id'
                    _AllUsers = $includeUsers -contains 'All'; _AllApps = $apps -contains 'All'; _Admins = [bool]@($includeRoles | Where-Object { $privilegedRoleIds -contains $_.ToLowerInvariant() }).Count
                    _Legacy = [bool]@($clients | Where-Object { $_ -in 'exchangeActiveSync', 'other' }).Count; _Risk = [bool]$risk; _On = $state -eq 'enabled'
                })
        })
    if (& $has 'ConditionalAccess') {
        $on = @($caRows | Where-Object _On)
        $caLink = "$learn/entra/identity/conditional-access/plan-conditional-access"
        $mfaEveryone = @($on | Where-Object { $_._AllUsers -and $_._AllApps -and $_.RequiresMfa -eq 'Yes' }).Count
        $mfaAdmins = @($on | Where-Object { ($_._Admins -or $_._AllUsers) -and $_.RequiresMfa -eq 'Yes' }).Count
        $legacyBlocked = @($on | Where-Object { $_._Legacy -and $_.Blocks -eq 'Yes' }).Count
        & $setting 'Entra ID' 'Conditional Access policies' "$($on.Count) on, $(@($caRows | Where-Object State -EQ 'Report-only').Count) report-only, $(@($caRows | Where-Object State -EQ 'Off').Count) off" 'Info' ''
        if (-not $defaultsOn -and -not $mfaEveryone) { & $finding 'High' 'Entra ID' 'MFA is not required of everyone' 'Conditional Access' 'Neither security defaults nor an enabled Conditional Access policy requires MFA for all users and all cloud apps.' 'Create a policy: all users (excluding break-glass accounts), all cloud apps, grant: require MFA (or an authentication strength).' "$learn/entra/identity/conditional-access/policy-all-users-mfa-strength" }
        if (-not $defaultsOn -and -not $mfaAdmins) { & $finding 'High' 'Entra ID' 'MFA is not required of administrators' 'Conditional Access' 'No enabled policy requires MFA for the privileged directory roles.' 'Create a policy for the admin roles requiring phishing-resistant MFA.' "$learn/entra/identity/conditional-access/policy-old-require-mfa-admin" }
        if (-not $defaultsOn -and -not $legacyBlocked) { & $finding 'High' 'Entra ID' 'Legacy authentication is not blocked' 'Conditional Access' 'Basic authentication (IMAP, POP, SMTP AUTH, older Office clients) bypasses MFA - the source of most password-spray compromises.' 'Create a policy: all users, client apps Exchange ActiveSync and other clients, grant: block.' "$learn/entra/identity/conditional-access/policy-block-legacy-authentication" }
        if ($hasP2 -and -not @($on | Where-Object _Risk).Count) { & $finding 'Medium' 'Entra ID' 'No risk-based Conditional Access' 'Conditional Access' 'Entra ID P2 is licensed, but no enabled policy acts on sign-in or user risk (Identity Protection).' 'Require MFA for medium and high sign-in risk, and a secure password change for high user risk.' "$learn/entra/id-protection/howto-identity-protection-configure-risk-policies" }
        $reportOnly = @($caRows | Where-Object State -EQ 'Report-only')
        if ($reportOnly.Count) { & $finding 'Low' 'Entra ID' 'Conditional Access policies left in report-only' "$($reportOnly.Count) policy(ies)" "$(@($reportOnly | Select-Object -First 4 -ExpandProperty Policy) -join '; ')$(if ($reportOnly.Count -gt 4) { '; ...' }) are evaluated but not enforced." 'Review their sign-in impact (Insights and reporting workbook), then turn them on.' $caLink }
        $noExclusion = @($on | Where-Object { $_._AllUsers -and $_.Blocks -eq 'Yes' -and -not $_.Excluded })
        if ($noExclusion.Count) { & $finding 'Medium' 'Entra ID' 'Blocking policy with no exclusion' "$($noExclusion.Count) policy(ies)" "$(@($noExclusion | Select-Object -ExpandProperty Policy) -join '; ') block all users with nobody excluded - a mistake can lock everyone out." 'Exclude your emergency-access (break-glass) accounts from every Conditional Access policy.' "$learn/entra/identity/role-based-access-control/security-emergency-access" }
    }
    elseif ($defaults -and -not $defaultsOn -and -not $hasP1 -and (& $has 'Licenses')) {
        & $finding 'High' 'Entra ID' 'MFA is not enforced' 'Security defaults' 'Security defaults are off and Conditional Access isn''t licensed (no Entra ID P1).' 'Turn security defaults on (Entra ID > Overview > Properties).' "$learn/entra/fundamentals/security-defaults"
    }
    # The analysis' flags (_AllUsers...) go; the objects keep their type.
    foreach ($row in $caRows) { foreach ($flag in @($row.PSObject.Properties.Name | Where-Object { $_ -like '_*' })) { $row.PSObject.Properties.Remove($flag) } }
    $caPolicies = @($caRows | Sort-Object -Property @{ Expression = { @{ On = 0; 'Report-only' = 1; Off = 2 }[$_.State] } }, Policy)
    $namedLocations = @(foreach ($n in (& $items 'NamedLocations')) {
            $type = ([string](& $text $n '@odata.type')) -replace '^#microsoft\.graph\.', '' -replace 'NamedLocation$', ''
            & $object 'AAC.M365NamedLocation' ([ordered]@{
                    Location = & $text $n 'displayName'; Type = & $words $type; Trusted = & $yesNo (& $get $n 'isTrusted')
                    Ranges = (@(& $list (& $get $n 'ipRanges')) | ForEach-Object { & $text $_ 'cidrAddress' }) -join ', '
                    Countries = (@(& $list (& $get $n 'countriesAndRegions')) -join ', '); Modified = & $date (& $get $n 'modifiedDateTime')
                })
        })
    $identityProviders = @(foreach ($i in (& $items 'IdentityProviders')) {
            & $object 'AAC.M365IdentityProvider' ([ordered]@{ Provider = & $text $i 'displayName'; Type = (([string](& $text $i '@odata.type')) -replace '^#microsoft\.graph\.', '' | ForEach-Object { & $words $_ }); Id = & $text $i 'id' })
        })

    # --- Microsoft 365: domains ------------------------------------------------------------------------------------------------------------
    $domains = @(@(foreach ($d in (& $items 'Domains')) {
            & $object 'AAC.M365Domain' ([ordered]@{
                    Domain = & $text $d 'id'; Default = & $yesNo (& $get $d 'isDefault'); Verified = & $yesNo (& $get $d 'isVerified'); Authentication = & $text $d 'authenticationType'
                    Services = (@(& $list (& $get $d 'supportedServices')) -join ', '); PasswordValidityDays = & $text $d 'passwordValidityPeriodInDays'; Initial = & $yesNo (& $get $d 'isInitial')
                })
        }) | Sort-Object -Property @{ Expression = { if ($_.Default -eq 'Yes') { 0 } else { 1 } } }, Domain)
    $unverified = @($domains | Where-Object Verified -EQ 'No')
    if ($unverified.Count) { & $finding 'Low' 'Microsoft 365' 'Unverified domains' ($unverified.Domain -join ', ') 'Domains added but never verified can''t be used, and clutter the tenant.' 'Verify them (add the TXT record) or remove them.' "$learn/microsoft-365/admin/setup/add-domain" }
    $federated = @($domains | Where-Object Authentication -EQ 'Federated')
    if ($federated.Count) { & $finding 'Info' 'Microsoft 365' 'Federated domains' ($federated.Domain -join ', ') 'Sign-in for these domains depends on an external identity provider (AD FS or another): its security is the tenant''s.' 'Consider moving to cloud authentication (password hash sync or pass-through) and retiring AD FS.' "$learn/entra/identity/hybrid/connect/migrate-from-federation-to-cloud-authentication" }

    # --- Secure Score -----------------------------------------------------------------------------------------------------------------------
    $score = & $one 'SecureScore'
    $profiles = @{}
    foreach ($p in (& $items 'SecureScoreProfiles')) { $profiles[(& $text $p 'id').ToLowerInvariant()] = $p }
    $scorePercent = $null
    $controlRows = @(@(foreach ($cs in @(& $list (& $get $score 'controlScores'))) {
            $name = & $text $cs 'controlName'; $p = $profiles[$name.ToLowerInvariant()]
            $max = [double](& $get $p 'maxScore'); $got = [double](& $get $cs 'score')
            if ($p -and (& $isTrue (& $get $p 'deprecated'))) { continue }
            & $object 'AAC.M365SecureScoreControl' ([ordered]@{
                    Control = $(if (& $text $p 'title') { & $text $p 'title' } else { $name }); Category = $(if (& $text $cs 'controlCategory') { & $text $cs 'controlCategory' } else { & $text $p 'controlCategory' }); Service = & $text $p 'service'
                    Score = [Math]::Round($got, 2); MaxScore = [Math]::Round($max, 2); Percent = $(if ($max -gt 0) { [Math]::Round(100 * $got / $max) } else { $null }); Gap = [Math]::Round([Math]::Max(0, $max - $got), 2)
                    Status = $(if ($max -gt 0 -and $got -ge $max) { 'Done' } elseif ($got -gt 0) { 'Partly' } else { 'To do' }); UserImpact = & $text $p 'userImpact'; Cost = & $text $p 'implementationCost'
                    Description = & $plain (& $text $cs 'description'); Remediation = & $plain (& $text $p 'remediation'); ActionUrl = & $text $p 'actionUrl'; Id = $name
                })
        }) | Sort-Object -Property @{ Expression = 'Gap'; Descending = $true }, Control)
    if ($score) {
        $current = [double](& $get $score 'currentScore'); $max = [double](& $get $score 'maxScore')
        $scorePercent = if ($max -gt 0) { [Math]::Round(100 * $current / $max) } else { $null }
        $peers = @(& $list (& $get $score 'averageComparativeScores')) | Where-Object { (& $text $_ 'basis') -eq 'AllTenants' } | Select-Object -First 1
        & $setting 'Microsoft 365' 'Microsoft Secure Score' "$([Math]::Round($current, 1)) of $([Math]::Round($max, 1)) ($scorePercent%)$(if ($peers) { "; all tenants' average $([Math]::Round([double](& $get $peers 'averageScore'), 1))" })" $(if ($scorePercent -ge 70) { 'Good' } elseif ($scorePercent -ge 40) { 'Review' } else { 'Warning' }) "As of $(& $text $score 'createdDateTime')."
        if ($null -ne $scorePercent -and $scorePercent -lt 50) { & $finding 'Medium' 'Microsoft 365' 'Secure Score under 50%' "$scorePercent%" "$([Math]::Round($current, 1)) of $([Math]::Round($max, 1)) points." 'Work through the controls with the biggest gap first (Secure Score tab).' "$learn/defender-xdr/microsoft-secure-score" }
    }

    # --- SharePoint and OneDrive sharing -----------------------------------------------------------------------------------------------------
    $sp = & $one 'SharePoint'
    $sharingLabel = @{ disabled = 'Only people in the organization'; existingExternalUserSharingOnly = 'Existing guests'; externalUserSharingOnly = 'New and existing guests'; externalUserAndGuestSharing = 'Anyone (anonymous links)' }
    $sharing = ''
    if ($sp) {
        $sharing = & $text $sp 'sharingCapability'
        $spLink = "$learn/sharepoint/turn-external-sharing-on-or-off"
        & $setting 'SharePoint and OneDrive' 'External sharing' $(if ($sharingLabel.Contains($sharing)) { $sharingLabel[$sharing] } else { $sharing }) $(if ($sharing -eq 'externalUserAndGuestSharing') { 'Warning' } elseif ($sharing -eq 'disabled') { 'Good' } else { 'Review' }) 'The most permissive sharing any site can have.'
        & $setting 'SharePoint and OneDrive' 'OneDrive / Loop sharing' (& $words (& $text $sp 'oneDriveLoopSharingCapability')) 'Info' ''
        $mode = & $text $sp 'sharingDomainRestrictionMode'
        & $setting 'SharePoint and OneDrive' 'Domain restriction' $(switch ($mode) { 'allowList' { "Only: $(@(& $list (& $get $sp 'sharingAllowedDomainList')) -join ', ')" } 'blockList' { "All but: $(@(& $list (& $get $sp 'sharingBlockedDomainList')) -join ', ')" } default { 'None (any domain)' } }) $(if ($mode -in 'allowList', 'blockList') { 'Good' } else { 'Review' }) ''
        & $setting 'SharePoint and OneDrive' 'Guests can reshare' (& $yesNo (& $get $sp 'isResharingByExternalUsersEnabled')) $(if (& $isTrue (& $get $sp 'isResharingByExternalUsersEnabled')) { 'Warning' } else { 'Good' }) ''
        & $setting 'SharePoint and OneDrive' 'Guest must match the invited address' (& $yesNo (& $get $sp 'isRequireAcceptingUserToMatchInvitedUserEnabled')) $(if (& $isTrue (& $get $sp 'isRequireAcceptingUserToMatchInvitedUserEnabled')) { 'Good' } else { 'Review' }) ''
        & $setting 'SharePoint and OneDrive' 'Legacy authentication protocols' (& $yesNo (& $get $sp 'isLegacyAuthProtocolsEnabled')) $(if (& $isTrue (& $get $sp 'isLegacyAuthProtocolsEnabled')) { 'Warning' } else { 'Good' }) ''
        & $setting 'SharePoint and OneDrive' 'Sync limited to domain-joined PCs' (& $yesNo (& $get $sp 'isUnmanagedSyncAppForTenantRestricted')) $(if (& $isTrue (& $get $sp 'isUnmanagedSyncAppForTenantRestricted')) { 'Good' } else { 'Review' }) ''
        & $setting 'SharePoint and OneDrive' 'Idle session sign-out' (& $yesNo (& $get $sp 'idleSessionSignOut.isEnabled')) 'Info' ''
        & $setting 'SharePoint and OneDrive' 'Users can create sites' (& $yesNo (& $get $sp 'isSiteCreationEnabled')) 'Info' ''
        & $setting 'SharePoint and OneDrive' 'Deleted users'' OneDrive kept (days)' (& $text $sp 'deletedUserPersonalSiteRetentionPeriodInDays') 'Info' ''
        if ($sharing -eq 'externalUserAndGuestSharing') { & $finding 'High' 'Microsoft 365' 'Anyone links are allowed' 'SharePoint and OneDrive' 'Files can be shared with anonymous links: whoever has the link can open them, with no sign-in or audit of who.' 'Limit sharing to new and existing guests, or give Anyone links an expiry and view-only permission.' $spLink }
        if (& $isTrue (& $get $sp 'isResharingByExternalUsersEnabled')) { & $finding 'Medium' 'Microsoft 365' 'Guests can reshare' 'SharePoint and OneDrive' 'Guests can share items they don''t own with people you never invited.' 'Turn off "Allow guests to share items they don''t own".' $spLink }
        if ($sharing -in 'externalUserSharingOnly', 'externalUserAndGuestSharing' -and $mode -notin 'allowList', 'blockList') { & $finding 'Low' 'Microsoft 365' 'Sharing open to every domain' 'SharePoint and OneDrive' 'Guests can come from any organization.' 'Limit external sharing by domain (an allow list of partners, or a block list).' "$learn/sharepoint/restricted-domains-sharing" }
        if (& $isTrue (& $get $sp 'isLegacyAuthProtocolsEnabled')) { & $finding 'Medium' 'Microsoft 365' 'Legacy authentication to SharePoint' 'SharePoint and OneDrive' 'Apps that don''t use modern authentication can sign in to SharePoint, around Conditional Access.' 'Turn off legacy authentication protocols (Access control in the SharePoint admin center).' "$learn/sharepoint/control-access-based-on-network-location" }
    }

    # --- Audit logging ---------------------------------------------------------------------------------------------------------------------------
    $auditControl = @($controlRows | Where-Object { $_.Id -eq 'AuditLogSearch' }) | Select-Object -First 1
    $auditState = if ($auditControl) { if ($auditControl.Status -eq 'Done') { 'On' } else { 'Off' } } else { 'Unknown' }
    if ((& $has 'SecureScore') -or (& $has 'DirectoryAudits')) {
        & $setting 'Microsoft 365' 'Unified audit log search (Purview)' $auditState $(switch ($auditState) { 'On' { 'Good' } 'Off' { 'Warning' } default { 'Unknown' } }) 'From the Secure Score control "Turn on audit log search". Graph has no switch of its own; confirm with Exchange Online: Get-AdminAuditLogConfig | Select UnifiedAuditLogIngestionEnabled.'
        if ($auditState -eq 'Off') { & $finding 'High' 'Microsoft 365' 'Audit log search is off' 'Microsoft Purview' 'User and admin activity across Microsoft 365 isn''t recorded: an incident can''t be investigated.' 'Turn on auditing in the Microsoft Purview portal (Audit > Start recording user and admin activity).' "$learn/purview/audit-log-enable-disable" }
    }
    if (& $has 'DirectoryAudits') {
        $last = @(& $items 'DirectoryAudits') | Select-Object -First 1
        $when = & $date (& $get $last 'activityDateTime')
        & $setting 'Microsoft 365' 'Entra audit log' $(if ($when) { "Latest event $($when.ToString('yyyy-MM-dd HH:mm')) UTC: $(& $text $last 'activityDisplayName')" } else { 'No events' }) $(if ($when) { 'Good' } else { 'Review' }) 'Entra ID keeps directory audit events 7 days (free) or 30 days (P1/P2).'
    }

    # --- Intune: settings and enrollment restrictions -------------------------------------------------------------------------------------------
    $intuneLink = "$learn/mem/intune"
    $dm = & $get (& $one 'DeviceManagement') 'settings'
    if ($dm) {
        $secure = & $isTrue (& $get $dm 'secureByDefault')
        & $setting 'Intune' 'Devices with no compliance policy are' $(if ($secure) { 'Not compliant' } else { 'Compliant' }) $(if ($secure) { 'Good' } else { 'Warning' }) 'Conditional Access trusts "compliant": a device without a policy shouldn''t count.'
        & $setting 'Intune' 'Compliance validity period (days)' (& $text $dm 'deviceComplianceCheckinThresholdDays') 'Info' 'A device that doesn''t check in for this long is not compliant.'
        if (-not $secure) { & $finding 'Medium' 'Intune' 'Devices with no compliance policy are marked compliant' 'Compliance policy settings' 'A device no policy targets passes "require compliant device" in Conditional Access.' 'Set "Mark devices with no compliance policy assigned as" to Not compliant.' "$intuneLink/protect/device-compliance-get-started#compliance-policy-settings" }
    }
    $platformNames = [ordered]@{ windowsRestriction = 'Windows'; iosRestriction = 'iOS/iPadOS'; androidRestriction = 'Android device administrator'; androidForWorkRestriction = 'Android Enterprise'; macOSRestriction = 'macOS'; windowsMobileRestriction = 'Windows Mobile' }
    $restrictions = [System.Collections.Generic.List[object]]::new()
    foreach ($e in (& $items 'EnrollmentRestrictions')) {
        $type = ([string](& $text $e '@odata.type')) -replace '^#microsoft\.graph\.', ''
        $base = [ordered]@{ Restriction = & $text $e 'displayName'; Type = ''; Priority = [int](& $get $e 'priority'); Platform = ''; Blocked = ''; PersonalBlocked = ''; MinimumOS = ''; MaximumOS = ''; Limit = $null; Modified = & $date (& $get $e 'lastModifiedDateTime') }
        if ($type -match 'PlatformRestrictions?Configuration$') {
            $single = & $get $e 'platformRestriction'
            $pairs = if ($single) { @(@{ Name = (& $words (& $text $e 'platformType')); Value = $single }) } else { @(foreach ($k in $platformNames.Keys) { $v = & $get $e $k; if ($v) { @{ Name = $platformNames[$k]; Value = $v } } }) }
            foreach ($pair in $pairs) {
                $row = [ordered]@{}; foreach ($k in $base.Keys) { $row[$k] = $base[$k] }
                $row.Type = 'Platform restrictions'; $row.Platform = $pair.Name
                $row.Blocked = & $yesNo (& $get $pair.Value 'platformBlocked'); $row.PersonalBlocked = & $yesNo (& $get $pair.Value 'personalDeviceEnrollmentBlocked')
                $row.MinimumOS = & $text $pair.Value 'osMinimumVersion'; $row.MaximumOS = & $text $pair.Value 'osMaximumVersion'
                $restrictions.Add((& $object 'AAC.M365EnrollmentRestriction' $row))
            }
        }
        elseif ($type -match 'LimitConfiguration$') {
            $base.Type = 'Device limit'; $base.Limit = [int](& $get $e 'limit')
            $restrictions.Add((& $object 'AAC.M365EnrollmentRestriction' $base))
            if ($base.Limit -gt 10) { & $finding 'Low' 'Intune' 'High device enrollment limit' "$($base.Restriction): $($base.Limit)" 'Each user can enroll many devices: a stolen account can add devices that look corporate.' 'Lower the limit to what people need (often 5).' "$intuneLink/enrollment/enrollment-restrictions-set" }
        }
        else {
            $base.Type = & $words ($type -replace 'Configuration$', '' -replace '^deviceEnrollment', '')
            $restrictions.Add((& $object 'AAC.M365EnrollmentRestriction' $base))
        }
    }
    $enrollmentRestrictions = @($restrictions | Sort-Object -Property Type, Priority, Platform)
    $personal = @($enrollmentRestrictions | Where-Object { $_.Type -eq 'Platform restrictions' -and $_.Blocked -eq 'No' -and $_.PersonalBlocked -eq 'No' -and $_.Platform -in 'Windows', 'macOS' })
    if ($personal.Count) { & $finding 'Low' 'Intune' 'Personal devices can enroll' (@($personal | ForEach-Object { "$($_.Platform) ($($_.Restriction))" }) -join ', ') 'Personally owned Windows and macOS devices can enroll and become "managed" - and count as compliant.' 'Block personal enrollment of Windows and macOS unless BYOD is intended; use app protection policies for personal devices.' "$intuneLink/enrollment/enrollment-restrictions-set" }

    # --- Intune: compliance and endpoint security -------------------------------------------------------------------------------------------------
    $summary = & $one 'ComplianceSummary'
    $compliancePolicies = @(@(foreach ($p in (& $items 'CompliancePolicies')) {
            $type = ([string](& $text $p '@odata.type')) -replace '^#microsoft\.graph\.', '' -replace 'CompliancePolicy$', ''
            & $object 'AAC.M365CompliancePolicy' ([ordered]@{ Policy = & $text $p 'displayName'; Platform = & $words $type; Assignments = @(& $list (& $get $p 'assignments')).Count; Modified = & $date (& $get $p 'lastModifiedDateTime'); Id = & $text $p 'id' })
        }) | Sort-Object Platform, Policy)
    $unassigned = @($compliancePolicies | Where-Object { -not $_.Assignments })
    if ($unassigned.Count) { & $finding 'Low' 'Intune' 'Compliance policies not assigned' "$($unassigned.Count) policy(ies)" "$(@($unassigned.Policy) -join '; ') apply to nobody." 'Assign them, or delete them.' "$intuneLink/protect/create-compliance-policy" }
    $familyNames = [ordered]@{ Antivirus = 'Antivirus'; Firewall = 'Firewall'; DiskEncryption = 'Disk encryption'; EndpointDetectionAndResponse = 'Endpoint detection and response'; AttackSurfaceReduction = 'Attack surface reduction'; AccountProtection = 'Account protection' }
    $familyOf = {
        param([string] $Text)
        foreach ($k in $familyNames.Keys) { if ($Text -match "(?i)$k|$($familyNames[$k] -replace ' ', '')") { return $familyNames[$k] } }
        if ($Text -match '(?i)endpointDetectionReponse|edr') { return $familyNames['EndpointDetectionAndResponse'] }
        ''
    }
    $templates = @{}
    foreach ($t in (& $items 'Templates')) { $templates[(& $text $t 'id').ToLowerInvariant()] = $t }
    $endpoint = [System.Collections.Generic.List[object]]::new()
    foreach ($p in (& $items 'ConfigurationPolicies')) {
        $family = & $familyOf (& $text $p 'templateReference.templateFamily')
        if (-not $family) { continue }   # settings catalog profiles that aren't endpoint security
        $endpoint.Add((& $object 'AAC.M365EndpointSecurityPolicy' ([ordered]@{ Policy = & $text $p 'name'; Family = $family; Platforms = & $words (& $text $p 'platforms'); Assigned = & $yesNo (& $get $p 'isAssigned'); Source = 'Settings catalog'; Template = & $text $p 'templateReference.templateDisplayName'; Modified = & $date (& $get $p 'lastModifiedDateTime'); Id = & $text $p 'id' })))
    }
    foreach ($p in (& $items 'Intents')) {
        $template = $templates[(& $text $p 'templateId').ToLowerInvariant()]
        $family = & $familyOf "$(& $text $template 'templateSubtype') $(& $text $template 'displayName')"
        if (-not $family) { continue }
        $endpoint.Add((& $object 'AAC.M365EndpointSecurityPolicy' ([ordered]@{ Policy = & $text $p 'displayName'; Family = $family; Platforms = ''; Assigned = & $yesNo (& $get $p 'isAssigned'); Source = 'Template (intent)'; Template = & $text $template 'displayName'; Modified = & $date (& $get $p 'lastModifiedDateTime'); Id = & $text $p 'id' })))
    }
    $endpointSecurity = @($endpoint | Sort-Object Family, Policy)
    if ((& $has 'ConfigurationPolicies') -or (& $has 'Intents')) {
        foreach ($k in 'Antivirus', 'Firewall', 'DiskEncryption', 'EndpointDetectionAndResponse', 'AttackSurfaceReduction') {
            $name = $familyNames[$k]
            $assigned = @($endpointSecurity | Where-Object { $_.Family -eq $name -and $_.Assigned -eq 'Yes' }).Count
            & $setting 'Intune' "Endpoint security: $name" $(if ($assigned) { "$assigned assigned polic$(if ($assigned -eq 1) { 'y' } else { 'ies' })" } else { 'None assigned' }) $(if ($assigned) { 'Good' } else { 'Warning' }) ''
            if (-not $assigned) { & $finding 'Medium' 'Intune' "No $($name.ToLowerInvariant()) policy" 'Endpoint security' "No assigned endpoint security policy manages $($name.ToLowerInvariant()) - devices keep whatever they were built with." "Create and assign an endpoint security $($name.ToLowerInvariant()) policy (Intune > Endpoint security)." "$intuneLink/protect/endpoint-security" }
        }
    }

    # --- Intune: devices ---------------------------------------------------------------------------------------------------------------------------------
    $managedDevices = @(@(foreach ($d in (& $items 'ManagedDevices')) {
            $sync = & $date (& $get $d 'lastSyncDateTime'); $days = & $daysSince $sync
            & $object 'AAC.M365ManagedDevice' ([ordered]@{
                    Device = & $text $d 'deviceName'; User = & $text $d 'userPrincipalName'; OS = & $text $d 'operatingSystem'; OSVersion = & $text $d 'osVersion'
                    Compliance = & $words (& $text $d 'complianceState'); Ownership = & $words (& $text $d 'managedDeviceOwnerType'); Encrypted = & $yesNo (& $get $d 'isEncrypted')
                    Jailbroken = $(switch (& $text $d 'jailBroken') { 'True' { 'Yes' } 'False' { 'No' } default { '' } }); LastSync = $sync; DaysSinceSync = $days; Stale = $(if ($null -ne $days -and $days -gt $StaleDays) { 'Yes' } else { 'No' })
                    Enrolled = & $date (& $get $d 'enrolledDateTime'); Management = & $words (& $text $d 'managementAgent'); Model = & $text $d 'model'; Manufacturer = & $text $d 'manufacturer'; EntraDeviceId = & $text $d 'azureADDeviceId'; Id = & $text $d 'id'
                })
        }) | Sort-Object -Property @{ Expression = { if ($_.Compliance -eq 'Noncompliant') { 0 } elseif ($_.Stale -eq 'Yes') { 1 } else { 2 } } }, Device)
    if (& $has 'ManagedDevices') {
        $nonCompliant = @($managedDevices | Where-Object Compliance -EQ 'Noncompliant')
        $stale = @($managedDevices | Where-Object Stale -EQ 'Yes')
        $unencrypted = @($managedDevices | Where-Object { $_.Encrypted -eq 'No' -and $_.OS -in 'Windows', 'macOS' })
        $jail = @($managedDevices | Where-Object Jailbroken -EQ 'Yes')
        if ($nonCompliant.Count) { & $finding $(if ($managedDevices.Count -and $nonCompliant.Count / $managedDevices.Count -gt 0.2) { 'High' } else { 'Medium' }) 'Intune' 'Non-compliant devices' "$($nonCompliant.Count) of $($managedDevices.Count)" 'They fail a compliance policy; with Conditional Access requiring compliance, their users are blocked - without it, they still get in.' 'Work through the failing settings (Devices > Monitor > Noncompliant devices) and require compliant devices in Conditional Access.' "$intuneLink/protect/compliance-policy-monitor" }
        if ($stale.Count) { & $finding 'Medium' 'Intune' 'Stale managed devices' "$($stale.Count) device(s)" "No check-in for more than $StaleDays days: lost, retired or rebuilt devices still counted as managed." 'Set up device clean-up rules (Devices > Device clean-up rules) and retire what''s gone.' "$intuneLink/fundamentals/device-cleanup-rules" }
        if ($unencrypted.Count) { & $finding 'Medium' 'Intune' 'Unencrypted computers' "$($unencrypted.Count) device(s)" 'Windows and macOS devices without BitLocker or FileVault: a lost laptop is a data breach.' 'Assign a disk encryption policy, and require encryption in the compliance policy.' "$intuneLink/protect/encrypt-devices" }
        if ($jail.Count) { & $finding 'High' 'Intune' 'Jailbroken or rooted devices' "$($jail.Count) device(s)" 'Their security model is broken: data on them can''t be protected.' 'Block jailbroken devices in the compliance policy, and retire these.' "$intuneLink/protect/compliance-policy-create-ios" }
    }
    $managedIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($m in $managedDevices) { if ($m.EntraDeviceId) { [void]$managedIds.Add($m.EntraDeviceId) } }
    $trustNames = @{ AzureAd = 'Entra joined'; ServerAd = 'Hybrid joined'; Workplace = 'Registered' }
    $entraDevices = @(@(foreach ($d in (& $items 'EntraDevices')) {
            $seen = & $date (& $get $d 'approximateLastSignInDateTime'); $days = & $daysSince $seen
            $managed = (& $isTrue (& $get $d 'isManaged')) -or $managedIds.Contains((& $text $d 'deviceId'))
            & $object 'AAC.M365EntraDevice' ([ordered]@{
                    Device = & $text $d 'displayName'; OS = & $text $d 'operatingSystem'; OSVersion = & $text $d 'operatingSystemVersion'
                    Join = $(if ($trustNames.Contains((& $text $d 'trustType'))) { $trustNames[(& $text $d 'trustType')] } else { & $text $d 'trustType' }); Managed = $(if ($managed) { 'Yes' } else { 'No' }); Compliant = & $yesNo (& $get $d 'isCompliant')
                    Enabled = & $yesNo (& $get $d 'accountEnabled'); LastSignIn = $seen; DaysSinceSignIn = $days; Stale = $(if ($null -eq $days -or $days -gt $StaleDays) { 'Yes' } else { 'No' })
                    Registered = & $date (& $get $d 'registrationDateTime'); DeviceId = & $text $d 'deviceId'; Id = & $text $d 'id'
                })
        }) | Sort-Object -Property @{ Expression = { if ($_.Managed -eq 'No' -and $_.Stale -eq 'No') { 0 } elseif ($_.Stale -eq 'Yes') { 1 } else { 2 } } }, Device)
    if (& $has 'EntraDevices') {
        $activeUnmanaged = @($entraDevices | Where-Object { $_.Managed -eq 'No' -and $_.Stale -eq 'No' -and $_.Enabled -eq 'Yes' })
        $staleEntra = @($entraDevices | Where-Object { $_.Stale -eq 'Yes' -and $_.Enabled -eq 'Yes' })
        if ($activeUnmanaged.Count) { & $finding 'Medium' 'Intune' 'Unmanaged devices in use' "$($activeUnmanaged.Count) device(s)" "Signed in within $StaleDays days, but not managed by Intune (or another MDM): no compliance, configuration or wipe." 'Require compliant or hybrid-joined devices in Conditional Access, and enroll or app-protect the rest.' "$learn/entra/identity/conditional-access/policy-all-users-device-compliance" }
        if ($staleEntra.Count) { & $finding 'Low' 'Intune' 'Stale Entra ID devices' "$($staleEntra.Count) device(s)" "Enabled device objects with no sign-in for $StaleDays days." 'Disable, then delete them (Entra ID > Devices, or a clean-up script).' "$learn/entra/identity/devices/manage-stale-devices" }
    }

    # --- Users, and their last sign-in ---------------------------------------------------------------------------------------------------------------------
    $users = @{}
    foreach ($u in (& $items 'Users')) { $users[(& $text $u 'id').ToLowerInvariant()] = $u }
    $signInsKnown = (& $has 'Users') -and $Fallback -notcontains 'Users'
    $lastSignIn = {
        param($User)
        @(@((& $get $User 'signInActivity.lastSignInDateTime'), (& $get $User 'signInActivity.lastNonInteractiveSignInDateTime'), (& $get $User 'signInActivity.lastSuccessfulSignInDateTime')) | ForEach-Object { & $date $_ } | Where-Object { $_ } | Sort-Object -Descending) | Select-Object -First 1
    }
    $tenantId = (& $text $org 'id').ToLowerInvariant()
    $microsoftTenants = @('f8cdef31-a31e-4b4a-93e4-5f571e91255a', '72f988bf-86f1-41af-91ab-2d7cd011db47')

    # --- MFA coverage ----------------------------------------------------------------------------------------------------------------------------------------
    $mfaCoverage = [System.Collections.Generic.List[object]]::new()
    if (& $has 'Registration') {
        foreach ($scope in @(@{ Name = 'Members'; Rows = @($registrationRows | Where-Object UserType -NE 'guest') }, @{ Name = 'Administrators'; Rows = @($registrationRows | Where-Object Admin -EQ 'Yes') }, @{ Name = 'Guests'; Rows = @($registrationRows | Where-Object UserType -EQ 'guest') })) {
            $n = $scope.Rows.Count
            $reg = @($scope.Rows | Where-Object MfaRegistered -EQ 'Yes').Count; $strong = @($scope.Rows | Where-Object PhishingResistant -EQ 'Yes').Count
            $mfaCoverage.Add((& $object 'AAC.M365MfaCoverage' ([ordered]@{
                            Scope = $scope.Name; Users = $n; MfaRegistered = $reg; MfaPercent = $(if ($n) { [Math]::Round(100 * $reg / $n) } else { $null })
                            PhishingResistant = $strong; PhishingResistantPercent = $(if ($n) { [Math]::Round(100 * $strong / $n) } else { $null })
                            Passwordless = @($scope.Rows | Where-Object Passwordless -EQ 'Yes').Count; NoMethod = $n - $reg
                        })))
        }
        $weakAdmins = @($registrationRows | Where-Object { $_.Admin -eq 'Yes' -and $_.MfaRegistered -eq 'Yes' -and $_.PhishingResistant -eq 'No' })
        if ($weakAdmins.Count) { & $finding 'Medium' 'Entra ID' 'Administrators without phishing-resistant MFA' "$($weakAdmins.Count) admin(s)" "$(@($weakAdmins | Select-Object -First 5 -ExpandProperty UserPrincipalName) -join ', ')$(if ($weakAdmins.Count -gt 5) { ', ...' }) use push, OTP or phone methods that adversary-in-the-middle phishing can relay." 'Register passkeys (FIDO2) or Windows Hello for admins, and require the Phishing-resistant MFA authentication strength for admin roles.' "$learn/entra/identity/authentication/concept-authentication-strengths" }
    }
    if (& $has 'ConditionalAccess') {
        $mfaAll = @((& $items 'ConditionalAccess') | Where-Object { (& $text $_ 'state') -eq 'enabled' -and @(& $list (& $get $_ 'conditions.users.includeUsers')) -contains 'All' -and (@(& $list (& $get $_ 'grantControls.builtInControls')) -contains 'mfa' -or (& $get $_ 'grantControls.authenticationStrength')) })
        $excludedUsers = @($mfaAll | ForEach-Object { @(& $list (& $get $_ 'conditions.users.excludeUsers')) } | Select-Object -Unique)
        $excludedGroups = @($mfaAll | ForEach-Object { @(& $list (& $get $_ 'conditions.users.excludeGroups')) } | Select-Object -Unique)
        & $setting 'Entra ID' 'MFA required by Conditional Access for' $(if ($mfaAll.Count) { "All users - $($excludedUsers.Count) user(s) and $($excludedGroups.Count) group(s) excluded" } elseif ($defaultsOn) { 'All users (security defaults)' } else { 'Not all users' }) $(if ($mfaAll.Count -or $defaultsOn) { 'Good' } else { 'Warning' }) 'Exclusions should be only the emergency access accounts.'
        if ($mfaAll.Count -and ($excludedUsers.Count -gt 2 -or $excludedGroups.Count)) { & $finding 'Medium' 'Entra ID' 'Exclusions from the MFA policy' "$($excludedUsers.Count) user(s), $($excludedGroups.Count) group(s)" 'Every exclusion is an account that signs in with a password alone. Groups can grow without anyone noticing.' 'Keep exclusions to the two emergency access accounts; review the rest, and use access reviews for excluded groups.' "$learn/entra/identity/conditional-access/policy-all-users-mfa-strength" }
    }

    # --- Emergency access (break-glass) accounts ----------------------------------------------------------------------------------------------------------------
    $enabledCa = @((& $items 'ConditionalAccess') | Where-Object { (& $text $_ 'state') -eq 'enabled' })
    $excludedFromAll = $null
    foreach ($p in $enabledCa) {
        $ex = @(@(& $list (& $get $p 'conditions.users.excludeUsers')) | ForEach-Object { ([string]$_).ToLowerInvariant() })
        $excludedFromAll = if ($null -eq $excludedFromAll) { $ex } else { @($excludedFromAll | Where-Object { $ex -contains $_ }) }
    }
    $excludedFromAll = @($excludedFromAll | Where-Object { $_ })
    $exclusionCount = { param([string] $Id) @($enabledCa | Where-Object { @(@(& $list (& $get $_ 'conditions.users.excludeUsers')) | ForEach-Object { ([string]$_).ToLowerInvariant() }) -contains $Id }).Count }
    $breakGlassName = '(?i)break.?glass|emergency|\bbg[-_.]?admin|^bga?[-_.0-9]|^ea[-_.]?admin|emergency.?access'
    $globalHolders = @($roleAssignments | Where-Object { $_.GlobalAdministrator -eq 'Yes' } | ForEach-Object PrincipalId)
    $candidates = [ordered]@{}
    foreach ($id in $excludedFromAll) { $candidates[$id] = 'Excluded from every enabled Conditional Access policy' }
    $people = if ($users.Count) { $users.Values } else { @((& $items 'Registration')) }
    foreach ($u in $people) {
        $id = (& $text $u 'id').ToLowerInvariant()
        $label = "$(& $text $u 'userPrincipalName') $(& $text $u 'displayName') $(& $text $u 'userDisplayName')"
        if ($label -match $breakGlassName) { $candidates[$id] = $(if ($candidates.Contains($id)) { "$($candidates[$id]); name" } else { 'Name' }) }
    }
    $emergencyAccess = @(foreach ($id in $candidates.Keys) {
            $u = $users[$id]; $r = $registration[$id]
            $seen = if ($u) { & $lastSignIn $u } else { $null }
            & $object 'AAC.M365EmergencyAccount' ([ordered]@{
                    Account = $(if ($u) { & $text $u 'displayName' } elseif ($r) { & $text $r 'userDisplayName' } else { $id }); UserPrincipalName = $(if ($u) { & $text $u 'userPrincipalName' } elseif ($r) { & $text $r 'userPrincipalName' } else { '' })
                    DetectedBy = $candidates[$id]; GlobalAdministrator = $(if ($globalHolders -contains $id) { 'Yes' } else { 'No' })
                    CloudOnly = $(if ($u) { if (& $isTrue (& $get $u 'onPremisesSyncEnabled')) { 'No' } else { 'Yes' } } else { '' }); Enabled = $(if ($u) { & $yesNo (& $get $u 'accountEnabled') } else { '' })
                    ExcludedFromPolicies = "$(& $exclusionCount $id) of $($enabledCa.Count)"; PhishingResistant = $(if ($r) { if (@(& $list (& $get $r 'methodsRegistered')) -match $phishingResistant) { 'Yes' } else { 'No' } } else { '' })
                    LastSignIn = $seen; Id = $id
                })
        })
    if ((& $has 'ConditionalAccess') -or (& $has 'Users')) {
        $eaLink = "$learn/entra/identity/role-based-access-control/security-emergency-access"
        $ea = @($emergencyAccess | Where-Object GlobalAdministrator -EQ 'Yes')
        & $setting 'Entra ID' 'Emergency access accounts' $(if ($emergencyAccess.Count) { "$($emergencyAccess.Count) found ($($ea.Count) Global Administrator)" } else { 'None found' }) $(if ($ea.Count -ge 2) { 'Good' } else { 'Warning' }) 'Found by being excluded from every enabled Conditional Access policy, or by name (break-glass, emergency...).'
        if (-not $emergencyAccess.Count) { & $finding 'Medium' 'Entra ID' 'No emergency access account found' 'Break-glass accounts' 'No account is excluded from every Conditional Access policy or named as an emergency account: a Conditional Access mistake or an MFA outage can lock every administrator out.' 'Create two cloud-only Global Administrator accounts on the .onmicrosoft.com domain, with passkeys (FIDO2), excluded from Conditional Access and monitored for sign-ins.' $eaLink }
        elseif ($ea.Count -eq 1) { & $finding 'Low' 'Entra ID' 'Only one emergency access account' $ea[0].UserPrincipalName 'One break-glass account is one lost key away from a lockout.' 'Keep two emergency access accounts, with credentials stored separately.' $eaLink }
        foreach ($e in $emergencyAccess) {
            if ($e.CloudOnly -eq 'No') { & $finding 'Medium' 'Entra ID' 'Emergency access account is synced from on-premises' $e.UserPrincipalName 'An on-premises outage or compromise takes the break-glass account with it.' 'Use a cloud-only account (on the .onmicrosoft.com domain).' $eaLink }
            if ($e.Enabled -eq 'No') { & $finding 'Medium' 'Entra ID' 'Emergency access account is disabled' $e.UserPrincipalName 'It can''t be used when it''s needed.' 'Enable it, test it, and keep monitoring its sign-ins.' $eaLink }
            if ($e.GlobalAdministrator -eq 'Yes' -and $e.PhishingResistant -eq 'No') { & $finding 'Medium' 'Entra ID' 'Emergency access account without a passkey' $e.UserPrincipalName 'Microsoft now enforces MFA on the admin portals for every account, break-glass included: without a strong method it may not get in.' 'Register two FIDO2 security keys for each emergency access account, stored apart.' "$learn/entra/identity/authentication/concept-mandatory-multifactor-authentication" }
        }
    }

    # --- Privileged accounts: dangling admins and role overlap ------------------------------------------------------------------------------------------------
    $spById = @{}
    foreach ($sp in (& $items 'ServicePrincipals')) { $spById[(& $text $sp 'id').ToLowerInvariant()] = $sp }
    $privilegedAccounts = @(foreach ($group in @($roleAssignments | Where-Object Privileged -EQ 'Yes' | Group-Object PrincipalId)) {
            $first = $group.Group[0]; $id = $group.Name
            $u = $users[$id]; $sp = $spById[$id]; $r = $registration[$id]
            $type = if ($first.PrincipalType) { $first.PrincipalType } elseif ($u) { 'User' } elseif ($sp) { 'Service Principal' } else { '' }
            $roleNames = @($group.Group | Select-Object -ExpandProperty Role -Unique)
            $both = @($group.Group | Group-Object Role | Where-Object { @($_.Group.Assignment | Select-Object -Unique).Count -gt 1 } | ForEach-Object Name)
            $seen = if ($u) { & $lastSignIn $u } else { $null }; $days = & $daysSince $seen
            $issues = [System.Collections.Generic.List[string]]::new()
            # Deleted: an active assignment whose principal Graph couldn't expand (an
            # eligible one is never expanded - a group there is no sign of anything).
            $unexpanded = @($group.Group | Where-Object { $_.Assignment -eq 'Active' -and -not $_.PrincipalType }).Count
            if ($unexpanded -and -not ($u -or $sp)) { $issues.Add('Deleted or unknown') }
            if ($u -and -not (& $isTrue (& $get $u 'accountEnabled'))) { $issues.Add('Disabled') }
            if (($u -and (& $text $u 'userType') -eq 'Guest') -or ($r -and (& $text $r 'userType') -eq 'guest')) { $issues.Add('Guest') }
            # Emergency access accounts are meant to sit unused.
            if ($u -and $signInsKnown -and ($null -eq $days -or $days -gt $StaleDays) -and -not $candidates.Contains($id)) { $issues.Add('No recent sign-in') }
            if ($u -and (& $isTrue (& $get $u 'onPremisesSyncEnabled'))) { $issues.Add('Synced from on-premises') }
            if ($type -eq 'Service Principal') { $issues.Add('Application') }
            $overlap = [System.Collections.Generic.List[string]]::new()
            if ($first.GlobalAdministrator -eq 'Yes' -or @($group.Group | Where-Object GlobalAdministrator -EQ 'Yes').Count) { if ($roleNames.Count -gt 1) { $overlap.Add('Global Administrator plus other roles') } }
            elseif ($roleNames.Count -ge 3) { $overlap.Add("$($roleNames.Count) privileged roles") }
            if ($both.Count) { $overlap.Add("Active and eligible: $($both -join ', ')") }
            & $object 'AAC.M365PrivilegedAccount' ([ordered]@{
                    Principal = $first.Principal; UserPrincipalName = $(if ($first.UserPrincipalName) { $first.UserPrincipalName } elseif ($u) { & $text $u 'userPrincipalName' } else { '' }); Type = $type
                    Roles = $roleNames -join ', '; RoleCount = $roleNames.Count; GlobalAdministrator = $(if (@($group.Group | Where-Object GlobalAdministrator -EQ 'Yes').Count) { 'Yes' } else { 'No' })
                    Assignment = (@($group.Group.Assignment | Select-Object -Unique) -join ', '); Enabled = $(if ($u) { & $yesNo (& $get $u 'accountEnabled') } else { '' })
                    LastSignIn = $seen; DaysSinceSignIn = $days; MfaRegistered = $(if ($r) { & $yesNo (& $get $r 'isMfaRegistered') } else { '' })
                    Dangling = $(if ($issues.Count) { 'Yes' } else { 'No' }); Issues = $issues -join ', '; Overlap = $(if ($overlap.Count) { 'Yes' } else { 'No' }); OverlapDetail = $overlap -join '; '; PrincipalId = $id
                })
        }) | Sort-Object -Property @{ Expression = { if ($_.Dangling -eq 'Yes') { 0 } elseif ($_.Overlap -eq 'Yes') { 1 } else { 2 } } }, @{ Expression = 'RoleCount'; Descending = $true }, Principal
    $privilegedAccounts = @($privilegedAccounts)
    $byIssue = { param([string] $Issue) @($privilegedAccounts | Where-Object { ", $($_.Issues), " -like "*, $Issue, *" }) }
    $names = { param($Rows) "$(@($Rows | Select-Object -First 5 | ForEach-Object { if ($_.UserPrincipalName) { $_.UserPrincipalName } else { $_.Principal } }) -join ', ')$(if (@($Rows).Count -gt 5) { ', ...' })" }
    if (& $has 'RoleAssignments') {
        $rows = @(& $byIssue 'Guest'); if ($rows.Count) { & $finding 'High' 'Entra ID' 'Guests hold admin roles' "$($rows.Count) guest(s)" "$(& $names $rows): their account - and its security - belongs to another organization." 'Give admin roles to accounts of your own tenant only.' $rolesLink }
        $rows = @(& $byIssue 'Disabled'); if ($rows.Count) { & $finding 'Medium' 'Entra ID' 'Disabled accounts still hold admin roles' "$($rows.Count) account(s)" "$(& $names $rows): dangling assignments that come back if the account is re-enabled." 'Remove the role assignments of accounts that are disabled (leavers).' $rolesLink }
        $rows = @(& $byIssue 'Deleted or unknown'); if ($rows.Count) { & $finding 'Medium' 'Entra ID' 'Admin roles assigned to deleted or unknown principals' "$($rows.Count) assignment(s)" "Principal IDs $(@($rows | Select-Object -First 5 -ExpandProperty PrincipalId) -join ', ') can't be resolved." 'Remove the assignments in Entra ID > Roles and administrators.' $rolesLink }
        $rows = @(& $byIssue 'No recent sign-in'); if ($rows.Count) { & $finding 'Medium' 'Entra ID' 'Admins who don''t sign in' "$($rows.Count) account(s)" "$(& $names $rows) haven't signed in for over $StaleDays days but keep their privileges." 'Remove roles nobody uses; make the rest eligible (PIM) rather than active.' $rolesLink }
        $rows = @(& $byIssue 'Synced from on-premises'); if ($rows.Count) { & $finding 'Medium' 'Entra ID' 'Admin accounts synced from on-premises' "$($rows.Count) account(s)" "$(& $names $rows): a compromised on-premises Active Directory compromises the cloud." 'Use cloud-only accounts for Entra ID and Microsoft 365 admin roles.' "$learn/entra/architecture/protect-m365-from-on-premises-attacks" }
        $rows = @(& $byIssue 'Application' | Where-Object GlobalAdministrator -EQ 'Yes'); if ($rows.Count) { & $finding 'High' 'Entra ID' 'Applications are Global Administrators' "$($rows.Count) app(s)" "$(& $names $rows): a leaked secret of theirs is a tenant takeover." 'Give apps the least-privileged role or Graph permission they need, not Global Administrator.' $rolesLink }
        $gaPlus = @($privilegedAccounts | Where-Object { $_.OverlapDetail -like '*Global Administrator plus*' }); if ($gaPlus.Count) { & $finding 'Low' 'Entra ID' 'Global Administrators with other admin roles' "$($gaPlus.Count) account(s)" "$(& $names $gaPlus): the extra roles add nothing but more assignments to review." 'Remove the roles Global Administrator already includes.' $rolesLink }
        $many = @($privilegedAccounts | Where-Object { $_.OverlapDetail -match '\d+ privileged roles' }); if ($many.Count) { & $finding 'Medium' 'Entra ID' 'Accounts with many admin roles' "$($many.Count) account(s)" "$(& $names $many) hold three or more privileged roles: one compromised account opens many doors." 'Split duties across accounts, and make roles eligible (PIM) for the time they''re needed.' $rolesLink }
        $dual = @($privilegedAccounts | Where-Object { $_.OverlapDetail -like '*Active and eligible*' }); if ($dual.Count) { & $finding 'Low' 'Entra ID' 'Roles both active and eligible' "$($dual.Count) account(s)" "$(& $names $dual): the active assignment makes the eligible one (and its MFA and approval) pointless." 'Remove the active assignment and keep the eligible one.' "$learn/entra/id-governance/privileged-identity-management/pim-configure" }
    }

    # --- App credentials: expiring and long-lived secrets ----------------------------------------------------------------------------------------------------------
    $credentialRows = [System.Collections.Generic.List[object]]::new()
    $addCredentials = {
        param($Owner, [string] $Kind)
        foreach ($set in @(@{ Type = 'Secret'; Items = (& $get $Owner 'passwordCredentials'); Long = 730 }, @{ Type = 'Certificate'; Items = (& $get $Owner 'keyCredentials'); Long = 1095 })) {
            foreach ($c in @(& $list $set.Items)) {
                $start = & $date (& $get $c 'startDateTime'); $end = & $date (& $get $c 'endDateTime')
                $left = if ($end) { [int][Math]::Floor(($end - $Now).TotalDays) } else { $null }
                $validity = if ($start -and $end) { [int][Math]::Round(($end - $start).TotalDays) } else { $null }
                $status = if ($null -ne $left -and $left -lt 0) { 'Expired' } elseif ($null -ne $left -and $left -le 30) { 'Expiring' } elseif ($null -ne $validity -and $validity -gt $set.Long) { 'Long-lived' } else { 'OK' }
                $credentialRows.Add((& $object 'AAC.M365AppCredential' ([ordered]@{
                                App = & $text $Owner 'displayName'; AppId = & $text $Owner 'appId'; Object = $Kind; Type = $set.Type; Description = & $text $c 'displayName'
                                Start = $start; End = $end; DaysLeft = $left; ValidityDays = $validity; Status = $status; KeyId = & $text $c 'keyId'
                            })))
            }
        }
    }
    foreach ($app in (& $items 'Applications')) { & $addCredentials $app 'App registration' }
    foreach ($sp in (& $items 'ServicePrincipals')) { if ((& $text $sp 'appOwnerOrganizationId').ToLowerInvariant() -notin $microsoftTenants) { & $addCredentials $sp 'Enterprise app' } }
    $appCredentials = @($credentialRows | Sort-Object -Property @{ Expression = { @{ Expiring = 0; Expired = 1; 'Long-lived' = 2; OK = 3 }[$_.Status] } }, DaysLeft, App)
    if ((& $has 'Applications') -or (& $has 'ServicePrincipals')) {
        $credLink = "$learn/entra/identity-platform/howto-create-service-principal-portal"
        $appList = { param($Rows) "$(@($Rows | Select-Object -ExpandProperty App -Unique | Select-Object -First 5) -join ', ')$(if (@($Rows | Select-Object -ExpandProperty App -Unique).Count -gt 5) { ', ...' })" }
        $rows = @($appCredentials | Where-Object Status -EQ 'Expiring'); if ($rows.Count) { & $finding 'Medium' 'Applications' 'App credentials expiring within 30 days' "$($rows.Count) credential(s)" "$(& $appList $rows): when they expire, the apps stop working." 'Add a new credential (a certificate, or better a managed identity or federated credential), deploy it, then remove the old one.' $credLink }
        $rows = @($appCredentials | Where-Object { $_.Status -eq 'Long-lived' -and $_.Type -eq 'Secret' }); if ($rows.Count) { & $finding 'Medium' 'Applications' 'Long-lived client secrets' "$($rows.Count) secret(s)" "$(& $appList $rows) have secrets valid for more than two years: a leaked one works for years." 'Use certificates, managed identities or workload identity federation; if a secret is needed, keep it under six months and rotate it.' "$learn/entra/workload-id/workload-identity-federation" }
        $rows = @($appCredentials | Where-Object { $_.Status -eq 'Long-lived' -and $_.Type -eq 'Certificate' }); if ($rows.Count) { & $finding 'Low' 'Applications' 'Long-lived certificates' "$($rows.Count) certificate(s)" "$(& $appList $rows) have certificates valid for more than three years." 'Issue certificates for a year or two, and rotate them.' $credLink }
        $rows = @($appCredentials | Where-Object Status -EQ 'Expired'); if ($rows.Count) { & $finding 'Low' 'Applications' 'Expired credentials left on apps' "$($rows.Count) credential(s)" "$(& $appList $rows) still carry expired secrets or certificates." 'Remove them: they clutter reviews and hide the ones that matter.' $credLink }
    }

    # --- App permissions: over-privileged applications --------------------------------------------------------------------------------------------------------------------
    $critical = @('RoleManagement.ReadWrite.Directory', 'AppRoleAssignment.ReadWrite.All', 'Application.ReadWrite.All', 'Directory.ReadWrite.All', 'UserAuthenticationMethod.ReadWrite.All', 'PrivilegedAccess.ReadWrite.AzureAD', 'Policy.ReadWrite.PermissionGrant')
    $high = @('Mail.ReadWrite', 'Mail.Send', 'Mail.Read', 'MailboxSettings.ReadWrite', 'Files.ReadWrite.All', 'Files.Read.All', 'Sites.FullControl.All', 'Sites.ReadWrite.All', 'Sites.Read.All', 'Sites.Manage.All', 'User.ReadWrite.All', 'Group.ReadWrite.All', 'GroupMember.ReadWrite.All', 'Policy.ReadWrite.ConditionalAccess', 'Domain.ReadWrite.All', 'Chat.Read.All', 'Chat.ReadWrite.All', 'ChannelMessage.Read.All', 'Calendars.ReadWrite', 'Contacts.ReadWrite', 'Notes.ReadWrite.All', 'DeviceManagementConfiguration.ReadWrite.All', 'DeviceManagementManagedDevices.ReadWrite.All', 'User.ManageIdentities.All')
    $riskOf = { param([string] $Permission) if ($critical -contains $Permission) { 'Critical' } elseif ($high -contains $Permission) { 'High' } elseif ($Permission -match 'ReadWrite|\.Send|FullControl|Manage') { 'Medium' } elseif ($Permission -match '\.All$') { 'Low' } else { 'Info' } }
    $graphSp = & $one 'GraphServicePrincipal'
    $graphId = (& $text $graphSp 'id').ToLowerInvariant()
    $roleValue = @{}
    foreach ($role in @(& $list (& $get $graphSp 'appRoles'))) { $roleValue[(& $text $role 'id').ToLowerInvariant()] = & $text $role 'value' }
    $ownerOf = {
        param($Sp)
        $owner = (& $text $Sp 'appOwnerOrganizationId').ToLowerInvariant()
        if ($owner -in $microsoftTenants) { 'Microsoft' } elseif ($owner -and $owner -eq $tenantId) { 'This tenant' } elseif ($owner) { 'Third party' } else { '' }
    }
    $permissionRows = [System.Collections.Generic.List[object]]::new()
    $addPermission = {
        param($Sp, [string] $ClientName, [string] $Permission, [string] $Kind, [string] $Resource, $Granted)
        $permissionRows.Add((& $object 'AAC.M365AppPermission' ([ordered]@{
                        App = $(if ($Sp) { & $text $Sp 'displayName' } else { $ClientName }); Owner = $(if ($Sp) { & $ownerOf $Sp } else { '' })
                        Publisher = $(if ($Sp) { if (& $text $Sp 'verifiedPublisher.displayName') { & $text $Sp 'verifiedPublisher.displayName' } else { & $text $Sp 'publisherName' } } else { '' })
                        Verified = $(if ($Sp -and (& $text $Sp 'verifiedPublisher.verifiedPublisherId')) { 'Yes' } else { 'No' })
                        Permission = $Permission; Kind = $Kind; Risk = & $riskOf $Permission; Resource = $Resource; Granted = $Granted; AppId = $(if ($Sp) { & $text $Sp 'appId' } else { '' })
                    })))
    }
    foreach ($g in (& $items 'GraphAppRoleGrants')) {
        $sp = $spById[(& $text $g 'principalId').ToLowerInvariant()]
        $value = $roleValue[(& $text $g 'appRoleId').ToLowerInvariant()]; if (-not $value) { $value = & $text $g 'appRoleId' }
        & $addPermission $sp (& $text $g 'principalDisplayName') $value 'Application' 'Microsoft Graph' (& $date (& $get $g 'createdDateTime'))
    }
    $delegated = @{}
    foreach ($g in (& $items 'DelegatedGrants')) {
        $resourceId = (& $text $g 'resourceId').ToLowerInvariant()
        $resource = if ($resourceId -eq $graphId) { 'Microsoft Graph' } elseif ($spById.Contains($resourceId)) { & $text $spById[$resourceId] 'displayName' } else { $resourceId }
        foreach ($scope in @(([string](& $text $g 'scope')).Split(' ') | Where-Object { $_ })) {
            $key = "$((& $text $g 'clientId').ToLowerInvariant())|$resource|$scope|$(& $text $g 'consentType')"
            if (-not $delegated.Contains($key)) { $delegated[$key] = @{ Grant = $g; Resource = $resource; Scope = $scope; Users = 0 } }
            $delegated[$key].Users++
        }
    }
    foreach ($entry in $delegated.Values) {
        $sp = $spById[(& $text $entry.Grant 'clientId').ToLowerInvariant()]
        $kind = if ((& $text $entry.Grant 'consentType') -eq 'AllPrincipals') { 'Delegated (all users)' } else { "Delegated ($($entry.Users) user$(if ($entry.Users -ne 1) { 's' }))" }
        & $addPermission $sp (& $text $entry.Grant 'clientId') $entry.Scope $kind $entry.Resource $null
    }
    $appPermissions = @($permissionRows | Sort-Object -Property @{ Expression = { $rank[$(if ($_.Risk -eq 'Info') { 'Info' } else { $_.Risk })] } }, @{ Expression = { if ($_.Owner -eq 'Microsoft') { 1 } else { 0 } } }, App, Permission)
    if ((& $has 'GraphAppRoleGrants') -or (& $has 'DelegatedGrants')) {
        $permLink = "$learn/entra/identity/enterprise-apps/manage-application-permissions"
        $notMicrosoft = @($appPermissions | Where-Object Owner -NE 'Microsoft')
        foreach ($group in @($notMicrosoft | Where-Object { $_.Kind -eq 'Application' -and $_.Risk -eq 'Critical' } | Group-Object App)) {
            & $finding 'Critical' 'Applications' 'App can take over the tenant' $group.Name "Application permissions $(@($group.Group.Permission) -join ', ') let it grant itself any role or permission - no user needed." 'Remove the permission unless it''s essential; protect the app''s credentials (certificate, no secrets) and its owners like a Global Administrator.' $permLink
        }
        $highApps = @($notMicrosoft | Where-Object { $_.Kind -eq 'Application' -and $_.Risk -eq 'High' } | Group-Object App)
        if ($highApps.Count) { & $finding 'High' 'Applications' 'Apps with tenant-wide access to data' "$($highApps.Count) app(s)" "$(@($highApps | Select-Object -First 5 | ForEach-Object { "$($_.Name) ($(@($_.Group.Permission) -join ', '))" }) -join '; ')$(if ($highApps.Count -gt 5) { '; ...' }): application permissions read or change every mailbox, file or chat." 'Scope them down (Exchange application RBAC, Sites.Selected), or remove what isn''t used.' $permLink }
        $wide = @($notMicrosoft | Where-Object { $_.Kind -eq 'Delegated (all users)' -and $_.Risk -in 'Critical', 'High' } | Group-Object App)
        if ($wide.Count) { & $finding 'High' 'Applications' 'Tenant-wide consent to high-risk delegated permissions' "$($wide.Count) app(s)" "$(@($wide | Select-Object -First 5 | ForEach-Object { "$($_.Name) ($(@($_.Group.Permission) -join ', '))" }) -join '; '): granted on behalf of every user." 'Review the consents; revoke what isn''t needed.' $permLink }
        $unverified = @($notMicrosoft | Where-Object { $_.Owner -eq 'Third party' -and $_.Verified -eq 'No' -and $_.Risk -in 'Critical', 'High' } | Select-Object -ExpandProperty App -Unique)
        if ($unverified.Count) { & $finding 'High' 'Applications' 'Unverified publishers with high-risk permissions' "$($unverified.Count) app(s)" "$(@($unverified | Select-Object -First 5) -join ', '): third-party apps whose publisher Microsoft hasn't verified." 'Confirm who publishes them and why they need that access; remove them if nobody knows.' "$learn/entra/identity-platform/publisher-verification-overview" }
    }

    # --- Redirect URIs: dangling, insecure, wildcard ---------------------------------------------------------------------------------------------------------------------------
    $takeover = '(?i)\.(azurewebsites\.net|cloudapp\.net|cloudapp\.azure\.com|trafficmanager\.net|blob\.core\.windows\.net|azureedge\.net|azurefd\.net|azure-api\.net|azurecontainer\.io|azurestaticapps\.net|azurehdinsight\.net|search\.windows\.net|azurecr\.io|servicebus\.windows\.net)$'
    $uriRows = [System.Collections.Generic.List[object]]::new()
    foreach ($app in (& $items 'Applications')) {
        $multi = (& $text $app 'signInAudience') -match 'Multiple|Personal'
        foreach ($kind in @(@{ Key = 'web'; Name = 'Web' }, @{ Key = 'spa'; Name = 'Single-page app' }, @{ Key = 'publicClient'; Name = 'Public client' })) {
            foreach ($uri in @(& $list (& $get $app "$($kind.Key).redirectUris"))) {
                $parsed = $null; $hostName = ''
                if ([System.Uri]::TryCreate([string]$uri, [System.UriKind]::Absolute, [ref]$parsed)) { $hostName = $parsed.Host.ToLowerInvariant() }
                $isLocal = $hostName -match '^(localhost|127\.|\[::1\])'
                $issue = ''; $severity = ''
                if ([string]$uri -match '\*') { $issue = 'Wildcard'; $severity = 'High' }
                elseif ($hostName -and -not $isLocal -and $Resolved.Contains($hostName) -and $Resolved[$hostName] -eq $false) { $issue = $(if ($hostName -match $takeover) { 'Dangling: the Azure host no longer exists' } else { 'Dangling: the host doesn''t resolve' }); $severity = $(if ($hostName -match $takeover) { 'High' } else { 'Medium' }) }
                elseif ($parsed -and $parsed.Scheme -eq 'http' -and -not $isLocal) { $issue = 'Not HTTPS'; $severity = 'Medium' }
                elseif ($isLocal -and $multi) { $issue = 'Localhost on a multi-tenant app'; $severity = 'Low' }
                $uriRows.Add((& $object 'AAC.M365RedirectUri' ([ordered]@{
                                App = & $text $app 'displayName'; AppId = & $text $app 'appId'; Platform = $kind.Name; Uri = [string]$uri; Host = $hostName
                                Resolves = $(if (-not $hostName -or $isLocal) { '' } elseif ($Resolved.Contains($hostName)) { switch ($Resolved[$hostName]) { $true { 'Yes' } $false { 'No' } default { 'Unknown' } } } else { '' })
                                Issue = $issue; Severity = $severity; Status = $(if ($issue) { 'Issue' } else { 'OK' })
                            })))
            }
        }
    }
    $redirectUris = @($uriRows | Sort-Object -Property @{ Expression = { if ($_.Severity) { $rank[$_.Severity] } else { 9 } } }, App, Uri)
    if (& $has 'Applications') {
        $uriLink = "$learn/entra/identity-platform/reply-url"
        $listUris = { param($Rows) "$(@($Rows | Select-Object -First 4 | ForEach-Object { "$($_.App): $($_.Uri)" }) -join '; ')$(if (@($Rows).Count -gt 4) { '; ...' })" }
        $rows = @($redirectUris | Where-Object { $_.Issue -like 'Dangling*' -and $_.Severity -eq 'High' }); if ($rows.Count) { & $finding 'High' 'Applications' 'Dangling redirect URIs on Azure hosts' "$($rows.Count) URI(s)" "$(& $listUris $rows) - the Azure resource is gone: whoever creates one with that name receives the app's sign-in tokens." 'Remove the redirect URIs now, then check DNS for other dangling records.' "$learn/azure/security/fundamentals/subdomain-takeover" }
        $rows = @($redirectUris | Where-Object { $_.Issue -like 'Dangling*' -and $_.Severity -eq 'Medium' }); if ($rows.Count) { & $finding 'Medium' 'Applications' 'Redirect URIs to hosts that don''t resolve' "$($rows.Count) URI(s)" "$(& $listUris $rows) - if the domain lapses, whoever registers it receives the app's tokens." 'Remove the redirect URIs that are no longer used.' $uriLink }
        $rows = @($redirectUris | Where-Object Issue -EQ 'Wildcard'); if ($rows.Count) { & $finding 'High' 'Applications' 'Wildcard redirect URIs' "$($rows.Count) URI(s)" "$(& $listUris $rows) - tokens can be sent to any matching host." 'Replace wildcards with the exact URIs.' $uriLink }
        $rows = @($redirectUris | Where-Object Issue -EQ 'Not HTTPS'); if ($rows.Count) { & $finding 'Medium' 'Applications' 'Redirect URIs without HTTPS' "$($rows.Count) URI(s)" "$(& $listUris $rows) - tokens and codes travel in clear text." 'Use https:// (http:// only for localhost).' $uriLink }
        $rows = @($redirectUris | Where-Object Issue -EQ 'Localhost on a multi-tenant app'); if ($rows.Count) { & $finding 'Low' 'Applications' 'Localhost redirect URIs on multi-tenant apps' "$($rows.Count) URI(s)" "$(& $listUris $rows) - left from development." 'Keep localhost in a separate development app registration.' $uriLink }
    }

    # --- Legacy authentication: actual sign-ins -------------------------------------------------------------------------------------------------------------------------------------
    $legacyRows = @(foreach ($group in @((& $items 'LegacySignIns') | Group-Object { & $text $_ 'clientAppUsed' })) {
            $ok = @($group.Group | Where-Object { [int](& $get $_ 'status.errorCode') -eq 0 })
            $latest = @($group.Group | ForEach-Object { & $date (& $get $_ 'createdDateTime') } | Sort-Object -Descending) | Select-Object -First 1
            $topUsers = @($group.Group | Group-Object { & $text $_ 'userPrincipalName' } | Sort-Object Count -Descending | Select-Object -First 5 | ForEach-Object { "$($_.Name) ($($_.Count))" })
            & $object 'AAC.M365LegacySignIn' ([ordered]@{
                    Protocol = $group.Name; SignIns = $group.Count; Successful = $ok.Count; Failed = $group.Count - $ok.Count
                    Users = @($group.Group | ForEach-Object { & $text $_ 'userPrincipalName' } | Select-Object -Unique).Count; TopUsers = $topUsers -join ', '
                    Apps = (@($group.Group | ForEach-Object { & $text $_ 'appDisplayName' } | Where-Object { $_ } | Select-Object -Unique | Select-Object -First 5) -join ', '); Latest = $latest
                    Capped = $(if ($group.Count -ge 200) { 'Yes (200 read)' } else { 'No' })
                })
        }) | Sort-Object -Property @{ Expression = 'Successful'; Descending = $true }, @{ Expression = 'SignIns'; Descending = $true }
    $legacyRows = @($legacyRows)
    if (& $has 'LegacySignIns') {
        $legacyLink = "$learn/entra/identity/conditional-access/policy-block-legacy-authentication"
        $succeeded = @($legacyRows | Where-Object Successful)
        & $setting 'Entra ID' "Legacy authentication sign-ins (last $SignInDays days)" $(if ($legacyRows.Count) { (@($legacyRows | ForEach-Object { "$($_.Protocol): $($_.Successful) ok, $($_.Failed) failed" }) -join '; ') } else { 'None' }) $(if ($succeeded.Count) { 'Warning' } elseif ($legacyRows.Count) { 'Review' } else { 'Good' }) 'From the Entra sign-in logs, one query per legacy protocol.'
        if ($succeeded.Count) { & $finding 'High' 'Entra ID' 'Legacy authentication is in use' "$(@($succeeded.Protocol) -join ', ')" "$(($succeeded | Measure-Object Successful -Sum).Sum) successful sign-in(s) in $SignInDays days by $(@($succeeded | ForEach-Object TopUsers) -join '; '): these protocols send passwords and skip MFA." 'Move those users and apps to modern authentication (OAuth), then block legacy authentication with Conditional Access.' $legacyLink }
        elseif ($legacyRows.Count) { & $finding 'Medium' 'Entra ID' 'Legacy authentication attempts' "$(@($legacyRows.Protocol) -join ', ')" "$(($legacyRows | Measure-Object SignIns -Sum).Sum) failed sign-in(s) in $SignInDays days: often password spraying, which legacy protocols make easy." 'Block legacy authentication with Conditional Access, and check the users for compromise.' $legacyLink }
    }

    # --- User consent ----------------------------------------------------------------------------------------------------------------------------------------------------------------------
    if ($auth) {
        $grants = @(@(& $list (& $get $auth 'defaultUserRolePermissions.permissionGrantPoliciesAssigned')) | ForEach-Object { [string]$_ })
        $self = @($grants | Where-Object { $_ -like 'ManagePermissionGrantsForSelf.*' } | ForEach-Object { $_ -replace '^ManagePermissionGrantsForSelf\.', '' })
        $owned = @($grants | Where-Object { $_ -like 'ManagePermissionGrantsForOwnedResource.*' })
        $consent = if (-not $self.Count) { 'Not allowed' } elseif ($self -contains 'microsoft-user-default-legacy') { 'Any app, any permission (legacy)' } elseif ($self -contains 'microsoft-user-default-low') { 'Verified publishers, low-impact permissions' } elseif ($self -contains 'microsoft-user-default-recommended') { 'Microsoft''s recommended (managed by Microsoft)' } else { "Custom: $($self -join ', ')" }
        & $setting 'Entra ID' 'User consent to apps' $consent $(if ($self -contains 'microsoft-user-default-legacy') { 'Warning' } elseif (-not $self.Count) { 'Good' } else { 'Good' }) 'What users can grant apps on their own.'
        & $setting 'Entra ID' 'Group owner consent' $(if ($owned.Count) { ($owned -replace '^ManagePermissionGrantsForOwnedResource\.', '') -join ', ' } else { 'Not allowed' }) 'Info' 'Owners consenting to apps reading their groups and teams.'
        $consentLink = "$learn/entra/identity/enterprise-apps/configure-user-consent"
        if ($self -contains 'microsoft-user-default-legacy') { & $finding 'High' 'Entra ID' 'Users can consent to any app' 'User consent settings' 'Any user can give any app access to their mail, files and data - illicit consent grants are a common way in.' 'Allow consent only to verified publishers for low-impact permissions (or Microsoft''s recommended setting), and turn on admin consent requests.' $consentLink }
        $workflow = & $one 'AdminConsentPolicy'
        if ($workflow) {
            $on = & $isTrue (& $get $workflow 'isEnabled')
            & $setting 'Entra ID' 'Admin consent requests' $(if ($on) { "On, $(@(& $list (& $get $workflow 'reviewers')).Count) reviewer rule(s)" } else { 'Off' }) $(if ($on) { 'Good' } else { 'Review' }) 'Lets users ask an admin for an app they can''t consent to.'
            if (-not $on -and $self -notcontains 'microsoft-user-default-legacy') { & $finding 'Low' 'Entra ID' 'Admin consent requests are off' 'Admin consent workflow' 'Users who can''t consent to an app have no way to ask - they look for workarounds.' 'Turn on admin consent requests, with reviewers.' "$learn/entra/identity/enterprise-apps/configure-admin-consent-workflow" }
        }
    }

    # --- Security defaults with Conditional Access licensed ----------------------------------------------------------------------------------------------------------------------------------
    if ($defaultsOn -and $hasP1) { & $finding 'Low' 'Entra ID' 'Security defaults instead of Conditional Access' 'Security defaults' 'Entra ID P1 is licensed, but the tenant relies on security defaults: all-or-nothing, with no exclusions for emergency access accounts and no device or risk conditions.' 'Build the equivalent Conditional Access policies (MFA for all, admins, legacy authentication blocked), then turn security defaults off.' "$learn/entra/fundamentals/security-defaults" }

    # --- Directory sync settings --------------------------------------------------------------------------------------------------------------------------
    $syncInfo = @(& $items 'DirectorySync') | Select-Object -First 1
    if ($syncInfo) {
        $features = & $get $syncInfo 'features'
        $hybrid = $org -and (& $isTrue (& $get $org 'onPremisesSyncEnabled'))
        $phs = & $isTrue (& $get $features 'passwordSyncEnabled')
        $prevention = & $text $syncInfo 'configuration.accidentalDeletionPrevention.synchronizationPreventionType'
        & $setting 'Entra ID' 'Password hash sync' $(if ($phs) { 'On' } else { 'Off' }) $(if ($phs -or -not $hybrid) { 'Good' } else { 'Review' }) 'Lets Identity Protection detect leaked credentials, and is the fallback if federation or pass-through fails.'
        & $setting 'Entra ID' 'Password writeback' (& $yesNo (& $get $features 'passwordWritebackEnabled')) 'Info' ''
        & $setting 'Entra ID' 'Accidental deletion prevention' $(if ($prevention -and $prevention -ne 'disabled') { "$(& $words $prevention), threshold $(& $text $syncInfo 'configuration.accidentalDeletionPrevention.alertThreshold')" } else { 'Off' }) $(if ($prevention -and $prevention -ne 'disabled') { 'Good' } else { 'Review' }) ''
        if ($hybrid -and -not $phs) { & $finding 'Low' 'Entra ID' 'Password hash sync is off' 'Directory sync' 'Without it, leaked-credential detection doesn''t work and there is no fallback when federation or pass-through authentication fails.' 'Turn on password hash sync in Entra Connect (it can run alongside federation).' "$learn/entra/identity/hybrid/connect/whatis-phs" }
        if ($hybrid -and (-not $prevention -or $prevention -eq 'disabled')) { & $finding 'Low' 'Entra ID' 'Accidental deletion prevention is off' 'Directory sync' 'A sync mistake on-premises can delete many cloud accounts at once.' 'Turn on accidental deletion prevention, with a threshold.' "$learn/entra/identity/hybrid/connect/how-to-connect-sync-feature-prevent-accidental-deletes" }
    }

    # --- PIM role settings: what activating a role takes ----------------------------------------------------------------------------------------------------
    $toHours = { param([string] $Iso) if (-not $Iso) { return $null }; try { [Math]::Round([System.Xml.XmlConvert]::ToTimeSpan($Iso).TotalHours, 1) } catch { $null } }
    $pimRows = @(foreach ($assignment in (& $items 'PimPolicies')) {
            $roleId = (& $text $assignment 'roleDefinitionId').ToLowerInvariant()
            $role = if ($roles.Contains($roleId)) { $roles[$roleId] } else { @{ Name = $roleId; Privileged = $privilegedTemplates -contains $roleId; Global = $roleId -eq $globalAdmin } }
            if (-not $role.Privileged) { continue }
            $rule = @{}; foreach ($r in @(& $list (& $get $assignment 'policy.rules'))) { $rule[(& $text $r 'id')] = $r }
            $enabled = @(& $list (& $get $rule['Enablement_EndUser_Assignment'] 'enabledRules'))
            $context = & $isTrue (& $get $rule['AuthenticationContext_EndUser_Assignment'] 'isEnabled')
            & $object 'AAC.M365PimRoleSetting' ([ordered]@{
                    Role = $role.Name; GlobalAdministrator = $(if ($role.Global) { 'Yes' } else { 'No' })
                    MfaOnActivation = $(if ($enabled -contains 'MultiFactorAuthentication' -or $context) { 'Yes' } else { 'No' }); Justification = $(if ($enabled -contains 'Justification') { 'Yes' } else { 'No' })
                    Approval = & $yesNo (& $get $rule['Approval_EndUser_Assignment'] 'setting.isApprovalRequired'); MaxActivationHours = & $toHours (& $text $rule['Expiration_EndUser_Assignment'] 'maximumDuration')
                    PermanentEligible = $(if ($rule['Expiration_Admin_Eligibility'] -and -not (& $isTrue (& $get $rule['Expiration_Admin_Eligibility'] 'isExpirationRequired'))) { 'Allowed' } else { 'No' })
                    PermanentActive = $(if ($rule['Expiration_Admin_Assignment'] -and -not (& $isTrue (& $get $rule['Expiration_Admin_Assignment'] 'isExpirationRequired'))) { 'Allowed' } else { 'No' })
                    RoleDefinitionId = $roleId
                })
        }) | Sort-Object -Property @{ Expression = { if ($_.GlobalAdministrator -eq 'Yes') { 0 } else { 1 } } }, Role
    $pimRows = @($pimRows)
    if (& $has 'PimPolicies') {
        $pimLink = "$learn/entra/id-governance/privileged-identity-management/pim-how-to-change-default-settings"
        $ga = @($pimRows | Where-Object GlobalAdministrator -EQ 'Yes') | Select-Object -First 1
        if ($ga -and $ga.MfaOnActivation -eq 'No') { & $finding 'High' 'Entra ID' 'Global Administrator activates without MFA' 'PIM role settings' 'Anyone with an eligible Global Administrator assignment and a password can activate it.' 'Require Azure MFA (or an authentication context with phishing-resistant MFA) on activation.' $pimLink }
        if ($ga -and $ga.Approval -eq 'No') { & $finding 'Medium' 'Entra ID' 'Global Administrator activates without approval' 'PIM role settings' 'Activating the most powerful role needs nobody else''s say-so.' 'Require approval to activate Global Administrator, with at least two approvers.' $pimLink }
        $noMfa = @($pimRows | Where-Object { $_.GlobalAdministrator -eq 'No' -and $_.MfaOnActivation -eq 'No' })
        if ($noMfa.Count) { & $finding 'Medium' 'Entra ID' 'Privileged roles activate without MFA' "$($noMfa.Count) role(s)" "$(@($noMfa.Role | Select-Object -First 6) -join ', ')$(if ($noMfa.Count -gt 6) { ', ...' })." 'Require MFA on activation for every privileged role.' $pimLink }
        $long = @($pimRows | Where-Object { $_.MaxActivationHours -gt 8 })
        if ($long.Count) { & $finding 'Low' 'Entra ID' 'Long role activations' "$($long.Count) role(s)" "$(@($long | Select-Object -First 6 | ForEach-Object { "$($_.Role) ($($_.MaxActivationHours) h)" }) -join ', ') can stay active for more than 8 hours." 'Keep activations to what a task needs (one to four hours for the most powerful roles).' $pimLink }
        $permanent = @($pimRows | Where-Object { $_.GlobalAdministrator -eq 'Yes' -and $_.PermanentActive -eq 'Allowed' })
        if ($permanent.Count) { & $finding 'Low' 'Entra ID' 'Permanent Global Administrator assignments are allowed' 'PIM role settings' 'Active Global Administrator assignments can be made with no end date.' 'Require an expiry on active assignments; keep only the emergency access accounts permanent.' $pimLink }
    }

    # --- Groups behind exclusions and roles -------------------------------------------------------------------------------------------------------------------
    $groupInfo = @{}; foreach ($g in (& $items 'Groups')) { $groupInfo[(& $text $g 'id').ToLowerInvariant()] = $g }
    $groupMembers = @{}
    foreach ($m in (& $items 'GroupMembers')) { $gid = ([string](& $get $m '_groupId')).ToLowerInvariant(); if (-not $groupMembers.Contains($gid)) { $groupMembers[$gid] = [System.Collections.Generic.List[object]]::new() }; $groupMembers[$gid].Add($m) }
    $groupWhy = @{}
    $addWhy = { param([string] $Id, [string] $Why) $k = $Id.ToLowerInvariant(); if (-not $groupWhy.Contains($k)) { $groupWhy[$k] = [System.Collections.Generic.List[string]]::new() }; if (-not $groupWhy[$k].Contains($Why)) { $groupWhy[$k].Add($Why) } }
    foreach ($p in (& $items 'ConditionalAccess')) { foreach ($gid in @(& $list (& $get $p 'conditions.users.excludeGroups'))) { & $addWhy ([string]$gid) "Excluded from: $(& $text $p 'displayName')$(if ((& $text $p 'state') -ne 'enabled') { ' (not on)' })" } }
    foreach ($row in $roleAssignments) { if ($groupInfo.Contains($row.PrincipalId) -or $row.PrincipalType -eq 'Group') { & $addWhy $row.PrincipalId "Holds: $($row.Role) ($($row.Assignment.ToLowerInvariant()))" } }
    $groupRows = @(foreach ($gid in $groupWhy.Keys) {
            $g = $groupInfo[$gid]; $list2 = @(if ($groupMembers.Contains($gid)) { $groupMembers[$gid] })
            $people = @($list2 | Where-Object { ([string](& $text $_ '@odata.type')) -match 'user' })
            & $object 'AAC.M365GroupExposure' ([ordered]@{
                    Group = $(if ($g) { & $text $g 'displayName' } else { $gid }); Why = ($groupWhy[$gid] -join '; ')
                    ExcludedFromPolicies = @($groupWhy[$gid] | Where-Object { $_ -like 'Excluded from:*' }).Count; HoldsRoles = @($groupWhy[$gid] | Where-Object { $_ -like 'Holds:*' }).Count
                    Members = $list2.Count; Users = $people.Count; Guests = @($people | Where-Object { (& $text $_ 'userType') -eq 'Guest' }).Count; Disabled = @($people | Where-Object { -not (& $isTrue (& $get $_ 'accountEnabled')) }).Count
                    Dynamic = $(if ($g -and (& $text $g 'membershipRule')) { 'Yes' } else { 'No' }); RoleAssignable = $(if ($g) { & $yesNo (& $get $g 'isAssignableToRole') } else { '' })
                    MemberList = (@($people | Select-Object -First 15 | ForEach-Object { if (& $text $_ 'userPrincipalName') { & $text $_ 'userPrincipalName' } else { & $text $_ 'displayName' } }) -join ', '); Id = $gid
                })
        }) | Sort-Object -Property @{ Expression = 'Guests'; Descending = $true }, @{ Expression = 'Members'; Descending = $true }, Group
    $groupRows = @($groupRows)
    if (& $has 'GroupMembers') {
        $big = @($groupRows | Where-Object { $_.ExcludedFromPolicies -and $_.Members -gt 5 })
        if ($big.Count) { & $finding 'Medium' 'Entra ID' 'Large groups excluded from Conditional Access' "$($big.Count) group(s)" "$(@($big | Select-Object -First 4 | ForEach-Object { "$($_.Group) ($($_.Members) members)" }) -join ', '): everyone in them skips the policies that exclude the group." 'Exclude individual emergency access accounts, not groups; review who is in these groups and why.' "$learn/entra/identity/conditional-access/plan-conditional-access" }
        $dyn = @($groupRows | Where-Object { $_.ExcludedFromPolicies -and $_.Dynamic -eq 'Yes' })
        if ($dyn.Count) { & $finding 'Medium' 'Entra ID' 'Dynamic groups excluded from Conditional Access' (@($dyn.Group) -join ', ') 'Anyone whose attributes match the rule is excluded automatically - and attributes can often be changed.' 'Use an assigned group (or individual accounts) for exclusions.' "$learn/entra/identity/users/groups-dynamic-membership" }
        $guestAdmins = @($groupRows | Where-Object { $_.HoldsRoles -and $_.Guests })
        if ($guestAdmins.Count) { & $finding 'High' 'Entra ID' 'Guests get admin roles through groups' "$($guestAdmins.Count) group(s)" "$(@($guestAdmins | ForEach-Object { "$($_.Group) ($($_.Guests) guest(s))" }) -join ', ')." 'Remove guests from role-holding groups.' $rolesLink }
    }

    # --- Access reviews ------------------------------------------------------------------------------------------------------------------------------------------
    $reviewRows = @(foreach ($r in (& $items 'AccessReviews')) {
            $scopeText = "$(ConvertTo-Json -InputObject (& $get $r 'scope') -Compress -Depth 10) $(ConvertTo-Json -InputObject (& $get $r 'instanceEnumerationScope') -Compress -Depth 10)"
            $kind = if ($scopeText -match '(?i)roleManagement|roleDefinition|principalResourceMemberships') { 'Directory roles' } elseif ($scopeText -match "(?i)userType eq 'Guest'") { 'Guests' } elseif ($scopeText -match '(?i)/groups') { 'Groups' } elseif ($scopeText -match '(?i)servicePrincipals') { 'Applications' } else { 'Other' }
            & $object 'AAC.M365AccessReview' ([ordered]@{
                    Review = & $text $r 'displayName'; Covers = $kind; Status = & $text $r 'status'; Recurrence = & $words (& $text $r 'settings.recurrence.pattern.type')
                    Reviewers = @(& $list (& $get $r 'reviewers')).Count; Created = & $date (& $get $r 'createdDateTime'); Id = & $text $r 'id'
                })
        }) | Sort-Object Covers, Review
    $reviewRows = @($reviewRows)
    if (& $has 'AccessReviews') {
        $reviewLink = "$learn/entra/id-governance/access-reviews-overview"
        $hasGuests = @($registrationRows | Where-Object UserType -EQ 'guest').Count -or @($users.Values | Where-Object { (& $text $_ 'userType') -eq 'Guest' }).Count
        if ($hasGuests -and -not @($reviewRows | Where-Object { $_.Covers -eq 'Guests' -and $_.Status -ne 'Completed' }).Count) { & $finding 'Low' 'Entra ID' 'Guest access isn''t reviewed' 'Access reviews' 'Guests keep their access after the collaboration ends.' 'Set up a recurring access review of guests in groups and teams (or of all guests).' $reviewLink }
        if ($hasP2 -and -not @($reviewRows | Where-Object { $_.Covers -eq 'Directory roles' -and $_.Status -ne 'Completed' }).Count) { & $finding 'Medium' 'Entra ID' 'Admin roles aren''t reviewed' 'Access reviews' 'Nobody periodically confirms that admins still need their roles.' 'Set up a recurring access review of privileged roles in PIM.' "$learn/entra/id-governance/privileged-identity-management/pim-create-roles-and-resource-roles-review" }
    }

    # --- Threat protection: risky users, risk detections, incidents --------------------------------------------------------------------------------------------------
    $riskyRows = @(foreach ($r in (& $items 'RiskyUsers')) {
            $state = & $text $r 'riskState'
            if ($state -notin 'atRisk', 'confirmedCompromised') { continue }
            & $object 'AAC.M365RiskyUser' ([ordered]@{
                    User = & $text $r 'userDisplayName'; UserPrincipalName = & $text $r 'userPrincipalName'; RiskLevel = & $words (& $text $r 'riskLevel'); RiskState = & $words $state
                    RiskDetail = & $words (& $text $r 'riskDetail'); Updated = & $date (& $get $r 'riskLastUpdatedDateTime'); Id = & $text $r 'id'
                })
        }) | Sort-Object -Property @{ Expression = { if ($_.RiskState -eq 'Confirmed Compromised') { 0 } else { @{ High = 1; Medium = 2; Low = 3 }[$_.RiskLevel] } } }, User
    $riskyRows = @($riskyRows)
    $detectionRows = @(foreach ($group in @((& $items 'RiskDetections') | Group-Object { & $text $_ 'riskEventType' })) {
            & $object 'AAC.M365RiskDetection' ([ordered]@{
                    Detection = & $words $group.Name; Detections = $group.Count; High = @($group.Group | Where-Object { (& $text $_ 'riskLevel') -eq 'high' }).Count
                    Users = @($group.Group | ForEach-Object { & $text $_ 'userPrincipalName' } | Select-Object -Unique).Count
                    TopUsers = (@($group.Group | Group-Object { & $text $_ 'userPrincipalName' } | Sort-Object Count -Descending | Select-Object -First 5 | ForEach-Object { "$($_.Name) ($($_.Count))" }) -join ', ')
                    Latest = @($group.Group | ForEach-Object { & $date (& $get $_ 'detectedDateTime') } | Sort-Object -Descending) | Select-Object -First 1
                })
        }) | Sort-Object -Property @{ Expression = 'High'; Descending = $true }, @{ Expression = 'Detections'; Descending = $true }
    $detectionRows = @($detectionRows)
    $incidentRows = @(foreach ($i in (& $items 'Incidents')) {
            $status = & $text $i 'status'; $created = & $date (& $get $i 'createdDateTime')
            & $object 'AAC.M365Incident' ([ordered]@{
                    Incident = & $text $i 'displayName'; Severity = & $words (& $text $i 'severity'); Status = & $words $status; Active = $(if ($status -in 'active', 'inProgress') { 'Yes' } else { 'No' })
                    AssignedTo = & $text $i 'assignedTo'; Classification = & $words (& $text $i 'classification'); Created = $created; Updated = & $date (& $get $i 'lastUpdateDateTime')
                    AgeDays = & $daysSince $created; Link = & $text $i 'incidentWebUrl'; Id = & $text $i 'id'
                })
        }) | Sort-Object -Property @{ Expression = { if ($_.Active -eq 'Yes') { 0 } else { 1 } } }, @{ Expression = { @{ High = 0; Medium = 1; Low = 2; Informational = 3 }[$_.Severity] } }, @{ Expression = 'Updated'; Descending = $true }
    $incidentRows = @($incidentRows)
    $threatLink = "$learn/entra/id-protection/howto-identity-protection-investigate-risk"
    if (& $has 'RiskyUsers') {
        $owned = @($riskyRows | Where-Object RiskState -EQ 'Confirmed Compromised')
        if ($owned.Count) { & $finding 'High' 'Threat protection' 'Users confirmed compromised' "$($owned.Count) user(s)" "$(@($owned.UserPrincipalName | Select-Object -First 5) -join ', ') - confirmed compromised and still flagged." 'Reset their passwords, revoke their sessions, review their activity, then dismiss the risk.' $threatLink }
        $highRisk = @($riskyRows | Where-Object { $_.RiskState -eq 'At Risk' -and $_.RiskLevel -eq 'High' })
        if ($highRisk.Count) { & $finding 'High' 'Threat protection' 'High-risk users not remediated' "$($highRisk.Count) user(s)" "$(@($highRisk.UserPrincipalName | Select-Object -First 5) -join ', ')$(if ($highRisk.Count -gt 5) { ', ...' })." 'Investigate them; require a secure password change for high user risk with a risk-based Conditional Access policy.' $threatLink }
        $other = @($riskyRows | Where-Object { $_.RiskState -eq 'At Risk' -and $_.RiskLevel -ne 'High' })
        if ($other.Count) { & $finding 'Medium' 'Threat protection' 'Users at risk' "$($other.Count) user(s)" 'Medium- and low-risk users that nobody has remediated or dismissed.' 'Review them in Identity Protection > Risky users.' $threatLink }
    }
    if (& $has 'RiskDetections') {
        $hot = @($detectionRows | Where-Object High)
        if ($hot.Count) { & $finding 'Medium' 'Threat protection' 'High-risk detections' "$(($hot | Measure-Object High -Sum).Sum) detection(s)" "$(@($hot | ForEach-Object { "$($_.Detection) ($($_.High))" }) -join ', ') in the last $SignInDays days." 'Investigate the users and sign-ins behind them.' "$learn/entra/id-protection/concept-identity-protection-risks" }
    }
    if (& $has 'Incidents') {
        $incidentLink = "$learn/defender-xdr/incidents-overview"
        $hi = @($incidentRows | Where-Object { $_.Active -eq 'Yes' -and $_.Severity -eq 'High' })
        if ($hi.Count) { & $finding 'High' 'Threat protection' 'High-severity incidents open' "$($hi.Count) incident(s)" "$(@($hi.Incident | Select-Object -First 4) -join '; ')$(if ($hi.Count -gt 4) { '; ...' })." 'Triage them in the Microsoft Defender portal.' $incidentLink }
        $orphan = @($incidentRows | Where-Object { $_.Active -eq 'Yes' -and -not $_.AssignedTo -and $_.AgeDays -gt 7 })
        if ($orphan.Count) { & $finding 'Medium' 'Threat protection' 'Incidents open for over a week with no owner' "$($orphan.Count) incident(s)" 'Nobody is assigned to them.' 'Assign an owner to every incident, and set up automatic assignment or playbooks.' $incidentLink }
    }

    # --- Usage: licensed users with no activity ----------------------------------------------------------------------------------------------------------------------
    $inactiveRows = @(foreach ($u in (& $items 'UsageReport')) {
            if (& $isTrue (& $get $u 'isDeleted')) { continue }
            $licensed = @('hasExchangeLicense', 'hasOneDriveLicense', 'hasSharePointLicense', 'hasTeamsLicense', 'hasYammerLicense', 'hasSkypeForBusinessLicense' | Where-Object { & $isTrue (& $get $u $_) }).Count
            if (-not $licensed) { continue }
            $last = @('exchangeLastActivityDate', 'oneDriveLastActivityDate', 'sharePointLastActivityDate', 'teamsLastActivityDate', 'yammerLastActivityDate', 'skypeForBusinessLastActivityDate' | ForEach-Object { & $date (& $get $u $_) } | Where-Object { $_ } | Sort-Object -Descending) | Select-Object -First 1
            if ($last -and (& $daysSince $last) -le 30) { continue }
            & $object 'AAC.M365InactiveUser' ([ordered]@{ User = & $text $u 'displayName'; UserPrincipalName = & $text $u 'userPrincipalName'; Products = (@(& $list (& $get $u 'assignedProducts')) -join ', '); LastActivity = $last })
        }) | Sort-Object LastActivity, UserPrincipalName
    $inactiveRows = @($inactiveRows)
    if (& $has 'UsageReport') {
        $usage = @(& $items 'UsageReport')
        & $setting 'Microsoft 365' 'Licensed users with no activity in 30 days' "$($inactiveRows.Count) of $(@($usage | Where-Object { -not (& $isTrue (& $get $_ 'isDeleted')) }).Count)" $(if ($inactiveRows.Count) { 'Review' } else { 'Good' }) 'From the Microsoft 365 active user report (Exchange, OneDrive, SharePoint, Teams).'
        if ($inactiveRows.Count) { & $finding 'Low' 'Microsoft 365' 'Licensed users with no activity in 30 days' "$($inactiveRows.Count) user(s)" 'Dormant accounts keep their access - and cost licences.' 'Confirm they''re still needed; disable leavers and reclaim the licences.' "$learn/microsoft-365/admin/activity-reports/microsoft365-apps-usage-ww" }
        if (@($usage | Where-Object { (& $text $_ 'userPrincipalName') -and (& $text $_ 'userPrincipalName') -notmatch '@' }).Count) { $notices.Add('User names are concealed in the Microsoft 365 usage reports (a tenant privacy setting), so the inactive users are shown by an ID. To see names: Microsoft 365 admin center > Settings > Org settings > Reports.') }
    }

    # --- Intune app protection (MAM) ---------------------------------------------------------------------------------------------------------------------------------
    $mamRows = @(foreach ($pair in @(@{ Key = 'AppProtectionIos'; Platform = 'iOS/iPadOS' }, @{ Key = 'AppProtectionAndroid'; Platform = 'Android' })) {
            foreach ($p in (& $items $pair.Key)) {
                $assigned = @(& $list (& $get $p 'assignments')).Count -or (& $isTrue (& $get $p 'isAssigned'))
                & $object 'AAC.M365AppProtectionPolicy' ([ordered]@{
                        Policy = & $text $p 'displayName'; Platform = $pair.Platform; Assigned = $(if ($assigned) { 'Yes' } else { 'No' }); PinRequired = & $yesNo (& $get $p 'pinRequired')
                        SendDataTo = & $words (& $text $p 'allowedOutboundDataTransferDestinations'); Clipboard = & $words (& $text $p 'allowedOutboundClipboardSharingLevel')
                        BackupBlocked = & $yesNo (& $get $p 'dataBackupBlocked'); SaveAsBlocked = & $yesNo (& $get $p 'saveAsBlocked'); MinimumOS = & $text $p 'minimumRequiredOsVersion'
                        Modified = & $date (& $get $p 'lastModifiedDateTime'); Id = & $text $p 'id'
                    })
            }
        })
    if ((& $has 'AppProtectionIos') -or (& $has 'AppProtectionAndroid')) {
        $mamLink = "$intuneLink/apps/app-protection-policy"
        foreach ($platform in @(@{ Key = 'AppProtectionIos'; Name = 'iOS/iPadOS' }, @{ Key = 'AppProtectionAndroid'; Name = 'Android' })) {
            if (-not (& $has $platform.Key)) { continue }
            $assignedHere = @($mamRows | Where-Object { $_.Platform -eq $platform.Name -and $_.Assigned -eq 'Yes' })
            & $setting 'Intune' "App protection: $($platform.Name)" $(if ($assignedHere.Count) { "$($assignedHere.Count) assigned polic$(if ($assignedHere.Count -eq 1) { 'y' } else { 'ies' })" } else { 'None assigned' }) $(if ($assignedHere.Count) { 'Good' } else { 'Warning' }) 'Protects corporate data in apps on personal (unenrolled) phones and tablets.'
            if (-not $assignedHere.Count) { & $finding 'Medium' 'Intune' "No app protection for $($platform.Name)" 'App protection policies' "On personal $($platform.Name) devices, corporate mail and files can be copied, backed up or opened in any app." "Assign an app protection policy for $($platform.Name), and require it with Conditional Access (Require app protection policy)." $mamLink }
        }
        $leaky = @($mamRows | Where-Object { $_.Assigned -eq 'Yes' -and $_.SendDataTo -eq 'All Apps' })
        if ($leaky.Count) { & $finding 'Medium' 'Intune' 'App protection lets data leave managed apps' (@($leaky.Policy) -join ', ') 'Corporate data can be sent to any app, personal ones included.' 'Allow sending data to policy-managed apps only.' $mamLink }
        $noPin = @($mamRows | Where-Object { $_.Assigned -eq 'Yes' -and $_.PinRequired -eq 'No' })
        if ($noPin.Count) { & $finding 'Low' 'Intune' 'App protection without a PIN' (@($noPin.Policy) -join ', ') 'Anyone holding the unlocked phone opens corporate data.' 'Require a PIN (or biometrics) for app access.' $mamLink }
    }

    # --- What was read: permissions ----------------------------------------------------------------------------------------------------------------------
    $permissions = @(foreach ($name in $Query.Keys) {
            $q = $Query[$name]; $why = [string]$Errors[$name]
            & $object 'AAC.M365Permission' ([ordered]@{
                    Area = @{ Entra = 'Entra ID'; Microsoft365 = 'Microsoft 365'; Intune = 'Intune' }[$q.Section]; Data = $q.Data; Status = $(if ($Data.Contains($name)) { 'Read' } elseif ($why) { 'Not read' } else { 'Not asked' })
                    Permission = $q.Permission; Reason = $(if ($why) { $why } else { '' }); Note = [string]$q['Note']; Query = $name
                })
        })
    $missing = @($permissions | Where-Object Status -EQ 'Not read')
    if ($missing.Count) { $notices.Add("$($missing.Count) of $($permissions.Count) Graph read(s) were refused or failed; the Permissions tab lists each with the permission it needs ($(@($missing.Permission | Select-Object -Unique) -join ', ')).") }

    # --- Coverage: every lens, assessed or not, and why ----------------------------------------------------------------------------------------------------------------
    $lenses = @(
        @('Entra ID', 'Tenant and directory sync', 'Organization', 'DirectorySync'), @('Entra ID', 'Licences', 'Licenses'), @('Entra ID', 'Security defaults', 'SecurityDefaults')
        @('Entra ID', 'User and guest settings', 'AuthorizationPolicy'), @('Entra ID', 'Cross-tenant access', 'CrossTenantAccess'), @('Entra ID', 'Conditional Access', 'ConditionalAccess', 'NamedLocations')
        @('Entra ID', 'Authentication methods', 'AuthenticationMethods'), @('Entra ID', 'MFA coverage', 'Registration', 'ConditionalAccess'), @('Entra ID', 'Admin roles (active and eligible)', 'RoleDefinitions', 'RoleAssignments', 'RoleEligibility')
        @('Entra ID', 'PIM role settings', 'PimPolicies'), @('Entra ID', 'Emergency access accounts', 'ConditionalAccess', 'Users', 'RoleAssignments'), @('Entra ID', 'Dangling admins and role overlap', 'RoleAssignments', 'Users')
        @('Entra ID', 'Groups behind exclusions and roles', 'Groups', 'GroupMembers'), @('Entra ID', 'Access reviews', 'AccessReviews'), @('Entra ID', 'Legacy authentication', 'LegacySignIns', 'ConditionalAccess')
        @('Entra ID', 'User consent and admin consent workflow', 'AuthorizationPolicy', 'AdminConsentPolicy'), @('Entra ID', 'Identity providers', 'IdentityProviders')
        @('Threat protection', 'Risky users', 'RiskyUsers'), @('Threat protection', 'Risk detections', 'RiskDetections'), @('Threat protection', 'Microsoft Defender XDR incidents', 'Incidents')
        @('Applications', 'App secrets and certificates', 'Applications', 'ServicePrincipals'), @('Applications', 'App permissions', 'GraphServicePrincipal', 'GraphAppRoleGrants', 'DelegatedGrants', 'ServicePrincipals'), @('Applications', 'Redirect URIs', 'Applications')
        @('Microsoft 365', 'Domains', 'Domains'), @('Microsoft 365', 'Microsoft Secure Score', 'SecureScore', 'SecureScoreProfiles'), @('Microsoft 365', 'SharePoint and OneDrive sharing', 'SharePoint')
        @('Microsoft 365', 'Audit logging', 'SecureScore', 'DirectoryAudits'), @('Microsoft 365', 'Inactive licensed users', 'UsageReport')
        @('Intune', 'Settings and enrollment restrictions', 'DeviceManagement', 'EnrollmentRestrictions'), @('Intune', 'Compliance', 'ComplianceSummary', 'CompliancePolicies'), @('Intune', 'Endpoint security', 'ConfigurationPolicies', 'Intents', 'Templates')
        @('Intune', 'App protection (personal devices)', 'AppProtectionIos', 'AppProtectionAndroid'), @('Intune', 'Managed devices', 'ManagedDevices'), @('Intune', 'Unmanaged Entra ID devices', 'EntraDevices')
    )
    $licenceHint = '(?i)licen[cs]e|premium|P2|P1|not.*subscription|AadPremium'
    $coverage = [System.Collections.Generic.List[object]]::new()
    foreach ($lens in $lenses) {
        $lensQueries = @($lens | Select-Object -Skip 2)
        $asked = @($lensQueries | Where-Object { $Query.Contains($_) })
        $read = @($asked | Where-Object { $Data.Contains($_) })
        $failed = @($asked | Where-Object { -not $Data.Contains($_) })
        $status = if (-not $asked.Count) { 'Not in this run' } elseif (-not $failed.Count) { 'Assessed' } elseif ($read.Count) { 'Partly assessed' } else { 'Not assessed' }
        $why = @($failed | ForEach-Object { [string]$Errors[$_] } | Where-Object { $_ } | Select-Object -Unique)
        $coverage.Add((& $object 'AAC.M365Coverage' ([ordered]@{
                        Area = $lens[0]; Lens = $lens[1]; Status = $status; Reads = "$($read.Count) of $($asked.Count)"
                        Reason = $(if ($status -eq 'Not in this run') { 'Its section wasn''t asked for (-Section).' } elseif ($why.Count) { ($why | Select-Object -First 2) -join ' | ' } else { '' })
                        ToCover = $(if ($status -eq 'Not in this run') { "Run with -Section $(@($lensQueries | ForEach-Object { (Get-AACM365AssessmentQuery)[$_].Section } | Select-Object -Unique) -join ', ')" } elseif ($failed.Count) { $perms = @($failed | ForEach-Object { $Query[$_].Permission } | Select-Object -Unique); "Consent $($perms -join ', ')$(if (@($why | Where-Object { $_ -match $licenceHint }).Count) { '; it also needs a licence (Entra ID P1/P2 or the product)' }); your account needs a role that can read it (Global Reader covers most)" } else { '' })
                        Source = 'Microsoft Graph'
                    })))
    }
    # What Microsoft Graph doesn't reach: said, with what would.
    foreach ($gap in @(
            @('Exchange Online', 'Mail forwarding to external addresses, SMTP AUTH, mailbox auditing, anti-phishing and anti-spam policies, DKIM and DMARC', 'The Exchange Online admin API or ExchangeOnlineManagement PowerShell, with the Exchange Administrator (or View-Only Organization Management) role')
            @('Microsoft 365', 'Whether unified audit logging is actually on', 'Graph has no switch for it: taken from the Secure Score control here. Exchange Online: Get-AdminAuditLogConfig | Select UnifiedAuditLogIngestionEnabled')
            @('Microsoft Defender for Office 365', 'Safe Links, Safe Attachments and preset security policies', 'Exchange Online PowerShell (Get-SafeLinksPolicy, Get-SafeAttachmentPolicy) or the Microsoft Defender portal')
            @('Microsoft Purview', 'Data loss prevention, sensitivity labels, retention and insider risk', 'Security & Compliance PowerShell (Connect-IPPSSession) or the Microsoft Purview portal')
            @('Microsoft Teams', 'External access, guest access and meeting policies', 'MicrosoftTeams PowerShell (Get-CsTenantFederationConfiguration, Get-CsTeamsMeetingPolicy)')
            @('Microsoft Defender for Cloud Apps', 'Session and app governance policies, discovered apps', 'The Defender for Cloud Apps API, with its own token')
            @('Microsoft Sentinel', 'Data connectors, analytics rules, automation and incidents', 'Azure Resource Manager (Microsoft.SecurityInsights) with the Microsoft Sentinel Reader role: not Microsoft Graph. Invoke-AACLogAnalyticsWorkspaceAssessment covers the workspace')
            @('Entra Connect servers', 'Sync server health and version', 'Microsoft Entra Connect Health, on the servers themselves')
        )) {
        $coverage.Add((& $object 'AAC.M365Coverage' ([ordered]@{ Area = $gap[0]; Lens = $gap[1]; Status = 'Not covered'; Reads = ''; Reason = 'Not in Microsoft Graph.'; ToCover = $gap[2]; Source = 'Outside Microsoft Graph' })))
    }
    $coverageRows = @($coverage | Sort-Object -Property @{ Expression = { @{ 'Not assessed' = 0; 'Partly assessed' = 1; 'Not covered' = 2; 'Not in this run' = 3; Assessed = 4 }[$_.Status] } }, Area, Lens)

    $sorted = @($findings | Sort-Object -Property @{ Expression = { $rank[$_.Severity] } }, Area, Finding)
    $onPolicies = @($caPolicies | Where-Object State -EQ 'On')
    @{
        Settings               = $settings.ToArray()
        Licenses               = $licenses
        ConditionalAccess      = $caPolicies
        NamedLocations         = $namedLocations
        RoleAssignments        = $roleAssignments
        Registration           = $registrationRows
        AuthenticationMethods  = $methods
        IdentityProviders      = $identityProviders
        Domains                = $domains
        SecureScoreControls    = $controlRows
        EnrollmentRestrictions = $enrollmentRestrictions
        CompliancePolicies     = $compliancePolicies
        EndpointSecurity       = $endpointSecurity
        ManagedDevices         = $managedDevices
        EntraDevices           = $entraDevices
        MfaCoverage            = $mfaCoverage.ToArray()
        EmergencyAccess        = @($emergencyAccess)
        PrivilegedAccounts     = $privilegedAccounts
        AppCredentials         = $appCredentials
        AppPermissions         = $appPermissions
        RedirectUris           = $redirectUris
        LegacyAuthentication   = $legacyRows
        PimRoleSettings        = $pimRows
        GroupExposure          = $groupRows
        AccessReviews          = $reviewRows
        RiskyUsers             = $riskyRows
        RiskDetections         = $detectionRows
        Incidents              = $incidentRows
        InactiveUsers          = $inactiveRows
        AppProtection          = @($mamRows)
        Coverage               = $coverageRows
        Permissions            = $permissions
        Findings               = $sorted
        Notices                = $notices.ToArray()
        Stats                  = [ordered]@{
            Tenant              = & $text $org 'displayName'
            TenantId            = & $text $org 'id'
            SecureScore         = $scorePercent
            SecurityDefaults    = $(if ($defaults) { if ($defaultsOn) { 'On' } else { 'Off' } } else { '' })
            ConditionalAccessOn = $onPolicies.Count
            ConditionalAccess   = $caPolicies.Count
            MfaRegistered       = $mfaPercent
            Users               = $registrationRows.Count
            AdminsWithoutMfa    = @($registrationRows | Where-Object { $_.Admin -eq 'Yes' -and $_.MfaRegistered -eq 'No' }).Count
            GlobalAdmins        = @($roleAssignments | Where-Object GlobalAdministrator -EQ 'Yes' | Select-Object -ExpandProperty PrincipalId -Unique).Count
            PrivilegedUsers     = @($roleAssignments | Where-Object Privileged -EQ 'Yes' | Select-Object -ExpandProperty PrincipalId -Unique).Count
            Domains             = $domains.Count
            ExternalSharing     = $(if ($sharingLabel.Contains($sharing)) { $sharingLabel[$sharing] } else { $sharing })
            AuditLog            = $auditState
            ManagedDevices      = $managedDevices.Count
            NonCompliant        = @($managedDevices | Where-Object Compliance -EQ 'Noncompliant').Count
            StaleDevices        = @($managedDevices | Where-Object Stale -EQ 'Yes').Count
            UnmanagedDevices    = @($entraDevices | Where-Object { $_.Managed -eq 'No' -and $_.Stale -eq 'No' -and $_.Enabled -eq 'Yes' }).Count
            Compliant           = [int](& $get $summary 'compliantDeviceCount')
            RiskyUsers          = $riskyRows.Count
            ActiveIncidents     = @($incidentRows | Where-Object Active -EQ 'Yes').Count
            InactiveUsers       = $inactiveRows.Count
            LensesAssessed      = @($coverageRows | Where-Object Status -EQ 'Assessed').Count
            LensesPartly        = @($coverageRows | Where-Object Status -EQ 'Partly assessed').Count
            LensesNotAssessed   = @($coverageRows | Where-Object Status -EQ 'Not assessed').Count
            LensesNotCovered    = @($coverageRows | Where-Object Status -EQ 'Not covered').Count
            EmergencyAccounts   = @($emergencyAccess).Count
            DanglingAdmins      = @($privilegedAccounts | Where-Object Dangling -EQ 'Yes').Count
            RoleOverlap         = @($privilegedAccounts | Where-Object Overlap -EQ 'Yes').Count
            ExpiringCredentials = @($appCredentials | Where-Object Status -EQ 'Expiring').Count
            LongLivedSecrets    = @($appCredentials | Where-Object { $_.Status -eq 'Long-lived' -and $_.Type -eq 'Secret' }).Count
            RiskyAppPermissions = @($appPermissions | Where-Object { $_.Owner -ne 'Microsoft' -and $_.Risk -in 'Critical', 'High' } | Select-Object -ExpandProperty App -Unique).Count
            RedirectUriIssues   = @($redirectUris | Where-Object Status -EQ 'Issue').Count
            LegacySignIns       = $($legacyOk = 0; foreach ($l in $legacyRows) { $legacyOk += $l.Successful }; $legacyOk)
            UserConsent         = $(if ($auth) { @(@(& $list (& $get $auth 'defaultUserRolePermissions.permissionGrantPoliciesAssigned')) | Where-Object { [string]$_ -like 'ManagePermissionGrantsForSelf.*' }).Count -gt 0 } else { $null })
            Read                = @($permissions | Where-Object Status -EQ 'Read').Count
            NotRead             = $missing.Count
            Findings            = $sorted.Count
            Critical            = @($sorted | Where-Object Severity -EQ 'Critical').Count
            High                = @($sorted | Where-Object Severity -EQ 'High').Count
            Medium              = @($sorted | Where-Object Severity -EQ 'Medium').Count
            Low                 = @($sorted | Where-Object Severity -EQ 'Low').Count
        }
    }
}
