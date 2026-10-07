<#
    A made-up Contoso Microsoft 365 tenant as Microsoft Graph returns it
    (Read-AACGraphQuery's Data: a list per collection, an object per
    singleton), for the Invoke-AACM365Assessment tests. Built so that each
    finding has a reason to fire:
      Entra ID   directory sync stopped 10 days ago, no technical contact,
                 E5 (Entra ID P2), security defaults off, users can register
                 apps, anyone can invite guests, SMS on and FIDO2 off, MFA
                 for everyone and for admins but legacy authentication only
                 in report-only, no risk-based policy, two Global
                 Administrators both standing, an admin and most users
                 without MFA registered
      M365       an unverified and a federated domain, Secure Score 40%,
                 audit log search off, Anyone links, guests can reshare, no
                 domain restriction
      Intune     devices with no compliance policy are compliant, personal
                 Windows enrollment, a device limit of 15, an unassigned
                 compliance policy, firewall/EDR/ASR not covered, two of
                 four devices non-compliant, one stale, one unencrypted, one
                 rooted, an unmanaged laptop in use and a stale PC
#>
function Get-AACContosoM365 {
    $now = [datetime]::new(2026, 10, 7, 12, 0, 0, [System.DateTimeKind]::Utc)
    $ago = { param([int] $Days) $now.AddDays(-$Days).ToString('o') }
    $ga = '62e90394-69f5-4237-9190-012177145e10'
    $reader = 'f2ef992c-3afb-46b9-b7cf-a126ee74c451'
    $userAdmin = 'fe930be7-5e62-47db-91af-98c3a49a38b1'; $securityAdmin = '194ae4cb-b126-40b2-bd5b-6091b380977d'; $exchangeAdmin = '29232cdf-9323-42fd-ade2-1d097af3e4de'
    $person = { param([string] $Id, [string] $Name, [string] $Upn, [bool] $Enabled, [bool] $Synced, [string] $Type, [int] $SignedIn) @{ id = $Id; displayName = $Name; userPrincipalName = $Upn; accountEnabled = $Enabled; onPremisesSyncEnabled = $(if ($Synced) { $true } else { $null }); userType = $Type; createdDateTime = (& $ago 900); signInActivity = @{ lastSignInDateTime = (& $ago $SignedIn); lastNonInteractiveSignInDateTime = (& $ago ($SignedIn + 1)) } } }
    $signIn = { param([string] $Protocol, [string] $Upn, [int] $ErrorCode, [int] $Days) @{ id = [guid]::NewGuid().ToString(); createdDateTime = (& $ago $Days); clientAppUsed = $Protocol; userPrincipalName = $Upn; appDisplayName = 'Office 365 Exchange Online'; status = @{ errorCode = $ErrorCode } } }
    $pim = {
        param([string] $Role, [string[]] $Enabled, [bool] $Approval, [string] $MaxDuration, [bool] $ActiveExpires)
        @{ id = "pa-$Role"; roleDefinitionId = $Role; scopeId = '/'; scopeType = 'DirectoryRole'; policy = @{ id = "p-$Role"; rules = @(
                    @{ '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyEnablementRule'; id = 'Enablement_EndUser_Assignment'; enabledRules = $Enabled }
                    @{ '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyApprovalRule'; id = 'Approval_EndUser_Assignment'; setting = @{ isApprovalRequired = $Approval } }
                    @{ '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyExpirationRule'; id = 'Expiration_EndUser_Assignment'; maximumDuration = $MaxDuration }
                    @{ '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyExpirationRule'; id = 'Expiration_Admin_Assignment'; isExpirationRequired = $ActiveExpires }
                    @{ '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyExpirationRule'; id = 'Expiration_Admin_Eligibility'; isExpirationRequired = $true }
                ) } }
    }
    $member = { param([string] $Group, [string] $Id, [string] $Upn, [string] $Type, [bool] $Enabled) @{ '@odata.type' = '#microsoft.graph.user'; id = $Id; displayName = $Id; userPrincipalName = $Upn; userType = $Type; accountEnabled = $Enabled; _groupId = $Group } }
    $risky = { param([string] $Id, [string] $Upn, [string] $Level, [string] $State) @{ id = $Id; userDisplayName = $Upn.Split('@')[0]; userPrincipalName = $Upn; riskLevel = $Level; riskState = $State; riskDetail = 'none'; riskLastUpdatedDateTime = (& $ago 2) } }
    $detection = { param([string] $Type, [string] $Level, [string] $Upn, [int] $Days) @{ id = [guid]::NewGuid().ToString(); riskEventType = $Type; riskLevel = $Level; userPrincipalName = $Upn; detectedDateTime = (& $ago $Days) } }
    $credential = { param([string] $Name, [int] $Start, [int] $End) @{ keyId = [guid]::NewGuid().ToString(); displayName = $Name; startDateTime = $now.AddDays($Start).ToString('o'); endDateTime = $now.AddDays($End).ToString('o') } }
    $user = { param([string] $Id, [string] $Name, [string] $Upn) @{ '@odata.type' = '#microsoft.graph.user'; id = $Id; displayName = $Name; userPrincipalName = $Upn } }
    $reg = { param([string] $Id, [string] $Name, [string] $Type, [bool] $Admin, [bool] $Mfa) @{ id = $Id; userDisplayName = $Name; userPrincipalName = "$($Name.ToLowerInvariant())@contoso.com"; userType = $Type; isAdmin = $Admin; isMfaRegistered = $Mfa; isMfaCapable = $Mfa; isPasswordlessCapable = $false; isSsprRegistered = $Mfa; defaultMfaMethod = $(if ($Mfa) { 'microsoftAuthenticatorPush' } else { 'none' }); methodsRegistered = $(if ($Mfa) { @('microsoftAuthenticatorPush') } else { @() }); lastUpdatedDateTime = (& $ago 1) } }
    $ca = {
        param([string] $Name, [string] $State, [hashtable] $Users, [string[]] $Apps, [string[]] $Clients, [hashtable] $Grant)
        @{ id = [guid]::NewGuid().ToString(); displayName = $Name; state = $State; createdDateTime = (& $ago 100); modifiedDateTime = (& $ago 10)
            conditions = @{ users = $Users; applications = @{ includeApplications = $Apps; includeUserActions = @() }; clientAppTypes = $Clients; signInRiskLevels = @(); userRiskLevels = @(); platforms = $null; locations = $null }
            grantControls = $Grant; sessionControls = $null }
    }
    $device = { param([string] $Name, [string] $Os, [string] $State, [bool] $Encrypted, [string] $Jail, [int] $Days, [string] $EntraId) @{ id = [guid]::NewGuid().ToString(); deviceName = $Name; operatingSystem = $Os; osVersion = '10.0'; complianceState = $State; managementAgent = 'mdm'; managedDeviceOwnerType = 'company'; lastSyncDateTime = (& $ago $Days); enrolledDateTime = (& $ago 300); userPrincipalName = 'alice@contoso.com'; isEncrypted = $Encrypted; jailBroken = $Jail; model = 'Model'; manufacturer = 'Contoso'; azureADDeviceId = $EntraId; deviceEnrollmentType = 'windowsAzureADJoin' } }
    $entra = { param([string] $Name, [string] $DeviceId, [bool] $Managed, [int] $Days, [string] $Trust) @{ id = [guid]::NewGuid().ToString(); deviceId = $DeviceId; displayName = $Name; operatingSystem = 'Windows'; operatingSystemVersion = '10.0'; isManaged = $Managed; isCompliant = $Managed; trustType = $Trust; approximateLastSignInDateTime = (& $ago $Days); accountEnabled = $true; registrationDateTime = (& $ago 400) } }

    $data = @{
        Organization           = @(@{ id = '00000000-0000-0000-0000-00000000c0de'; displayName = 'Contoso'; createdDateTime = '2019-01-01T00:00:00Z'; tenantType = 'AAD'; onPremisesSyncEnabled = $true; onPremisesLastSyncDateTime = (& $ago 10); technicalNotificationMails = @(); securityComplianceNotificationMails = @(); countryLetterCode = 'GB'; preferredDataLocation = $null; verifiedDomains = @() })
        Licenses               = @(@{ skuId = 'e5'; skuPartNumber = 'SPE_E5'; capabilityStatus = 'Enabled'; consumedUnits = 40; prepaidUnits = @{ enabled = 50; suspended = 0; warning = 0 }; servicePlans = @(@{ servicePlanName = 'AAD_PREMIUM_P2'; provisioningStatus = 'Success' }, @{ servicePlanName = 'INTUNE_A'; provisioningStatus = 'Success' }) })
        SecurityDefaults       = @{ id = '00000000-0000-0000-0000-000000000005'; isEnabled = $false }
        AuthorizationPolicy    = @{ id = 'authorizationPolicy'; allowInvitesFrom = 'everyone'; allowEmailVerifiedUsersToJoinOrganization = $false; allowedToSignUpEmailBasedSubscriptions = $true; guestUserRoleId = '10dae51f-b6af-4016-8d66-8c2a99b929b3'; defaultUserRolePermissions = @{ allowedToCreateApps = $true; allowedToCreateSecurityGroups = $true; allowedToCreateTenants = $false; allowedToReadOtherUsers = $true; permissionGrantPoliciesAssigned = @('ManagePermissionGrantsForSelf.microsoft-user-default-legacy', 'ManagePermissionGrantsForOwnedResource.microsoft-dynamically-managed-permissions-for-team') } }
        AuthenticationMethods  = @{ id = 'authenticationMethodsPolicy'; policyMigrationState = 'migrationInProgress'; authenticationMethodConfigurations = @(
                @{ id = 'Sms'; state = 'enabled'; includeTargets = @(@{ id = 'all_users' }) }
                @{ id = 'MicrosoftAuthenticator'; state = 'enabled'; includeTargets = @(@{ id = 'all_users' }) }
                @{ id = 'Fido2'; state = 'disabled' }
            ) }
        CrossTenantAccess      = @{ inboundTrust = @{ isMfaAccepted = $false; isCompliantDeviceAccepted = $false } }
        ConditionalAccess      = @(
            (& $ca 'Require MFA for all users' 'enabled' @{ includeUsers = @('All'); excludeUsers = @('u-bg1'); excludeGroups = @('g-travel') } @('All') @('all') @{ operator = 'OR'; builtInControls = @('mfa') })
            (& $ca 'Block legacy authentication' 'enabledForReportingButNotEnforced' @{ includeUsers = @('All') } @('All') @('exchangeActiveSync', 'other') @{ operator = 'OR'; builtInControls = @('block') })
            (& $ca 'Admins: phishing-resistant MFA' 'enabled' @{ includeRoles = @($ga); excludeUsers = @('u-bg1') } @('All') @('all') @{ operator = 'OR'; builtInControls = @(); authenticationStrength = @{ displayName = 'Phishing-resistant MFA' } })
        )
        NamedLocations         = @(@{ '@odata.type' = '#microsoft.graph.ipNamedLocation'; displayName = 'Head office'; isTrusted = $true; ipRanges = @(@{ cidrAddress = '203.0.113.0/24' }); modifiedDateTime = (& $ago 30) })
        RoleDefinitions        = @(
            @{ id = $ga; templateId = $ga; displayName = 'Global Administrator'; isBuiltIn = $true; isPrivileged = $true }
            @{ id = $reader; templateId = $reader; displayName = 'Global Reader'; isBuiltIn = $true; isPrivileged = $false }
            @{ id = $userAdmin; templateId = $userAdmin; displayName = 'User Administrator'; isBuiltIn = $true; isPrivileged = $true }
            @{ id = $securityAdmin; templateId = $securityAdmin; displayName = 'Security Administrator'; isBuiltIn = $true; isPrivileged = $true }
            @{ id = $exchangeAdmin; templateId = $exchangeAdmin; displayName = 'Exchange Administrator'; isBuiltIn = $true; isPrivileged = $true }
        )
        RoleAssignments        = @(
            @{ roleDefinitionId = $ga; principalId = 'u-alice'; directoryScopeId = '/'; principal = (& $user 'u-alice' 'Alice' 'alice@contoso.com') }
            @{ roleDefinitionId = $exchangeAdmin; principalId = 'u-alice'; directoryScopeId = '/'; principal = (& $user 'u-alice' 'Alice' 'alice@contoso.com') }
            @{ roleDefinitionId = $ga; principalId = 'u-bob'; directoryScopeId = '/'; principal = (& $user 'u-bob' 'Bob' 'bob@contoso.com') }
            @{ roleDefinitionId = $reader; principalId = 'u-carol'; directoryScopeId = '/'; principal = (& $user 'u-carol' 'Carol' 'carol@contoso.com') }
            @{ roleDefinitionId = $ga; principalId = 'u-bg1'; directoryScopeId = '/'; principal = (& $user 'u-bg1' 'BG Admin 1' 'bg-admin1@contoso.onmicrosoft.com') }
            @{ roleDefinitionId = $userAdmin; principalId = 'u-zoe'; directoryScopeId = '/'; principal = (& $user 'u-zoe' 'Zoe' 'zoe@contoso.com') }
            @{ roleDefinitionId = $securityAdmin; principalId = 'u-gary'; directoryScopeId = '/'; principal = (& $user 'u-gary' 'Gary (guest)' 'gary_fabrikam.com#EXT#@contoso.onmicrosoft.com') }
            @{ roleDefinitionId = $userAdmin; principalId = 'u-ghost'; directoryScopeId = '/'; principal = $null }
            @{ roleDefinitionId = $ga; principalId = 'sp-automation'; directoryScopeId = '/'; principal = @{ '@odata.type' = '#microsoft.graph.servicePrincipal'; id = 'sp-automation'; displayName = 'Automation runbook' } }
            @{ roleDefinitionId = $userAdmin; principalId = 'g-helpdesk'; directoryScopeId = '/'; principal = @{ '@odata.type' = '#microsoft.graph.group'; id = 'g-helpdesk'; displayName = 'Helpdesk' } }
        )
        DirectorySync          = @(@{ id = 'sync'; features = @{ passwordSyncEnabled = $false; passwordWritebackEnabled = $true }; configuration = @{ accidentalDeletionPrevention = @{ synchronizationPreventionType = 'disabled'; alertThreshold = 500 } } })
        PimPolicies            = @(
            (& $pim $ga @('Justification') $false 'PT10H' $false)
            (& $pim $userAdmin @('MultiFactorAuthentication', 'Justification') $false 'PT8H' $true)
            (& $pim $securityAdmin @('Justification') $true 'PT4H' $true)
            (& $pim $reader @('Justification') $false 'PT8H' $true)
        )
        AccessReviews          = @(@{ id = 'ar1'; displayName = 'Finance group members'; status = 'InProgress'; scope = @{ query = '/groups/g-finance/transitiveMembers'; queryType = 'MicrosoftGraph' }; settings = @{ recurrence = @{ pattern = @{ type = 'absoluteMonthly' } } }; reviewers = @(@{ query = './manager' }); createdDateTime = (& $ago 60) })
        Groups                 = @(
            @{ id = 'g-travel'; displayName = 'Travelling staff'; membershipRule = "user.department -eq 'Sales'"; isAssignableToRole = $false; securityEnabled = $true }
            @{ id = 'g-helpdesk'; displayName = 'Helpdesk'; membershipRule = $null; isAssignableToRole = $true; securityEnabled = $true }
        )
        GroupMembers           = @(1..7 | ForEach-Object { & $member 'g-travel' "u-sales$_" "sales$_@contoso.com" 'Member' $true }) + @(
            (& $member 'g-helpdesk' 'u-carol' 'carol@contoso.com' 'Member' $true)
            (& $member 'g-helpdesk' 'u-gary' 'gary_fabrikam.com#EXT#@contoso.onmicrosoft.com' 'Guest' $true)
        )
        RiskyUsers             = @(
            (& $risky 'u-dave' 'dave@contoso.com' 'high' 'atRisk'); (& $risky 'u-erin' 'erin@contoso.com' 'medium' 'atRisk')
            (& $risky 'u-frank' 'frank_partner.com#EXT#@contoso.onmicrosoft.com' 'none' 'remediated'); (& $risky 'u-zoe' 'zoe@contoso.com' 'high' 'confirmedCompromised')
        )
        RiskDetections         = @(
            (& $detection 'unfamiliarFeatures' 'medium' 'dave@contoso.com' 1); (& $detection 'unfamiliarFeatures' 'medium' 'dave@contoso.com' 2); (& $detection 'unfamiliarFeatures' 'medium' 'erin@contoso.com' 3)
            (& $detection 'leakedCredentials' 'high' 'zoe@contoso.com' 1); (& $detection 'leakedCredentials' 'high' 'zoe@contoso.com' 4)
        )
        Incidents              = @(
            @{ id = '101'; displayName = 'Multi-stage incident involving credential access'; severity = 'high'; status = 'active'; assignedTo = $null; classification = 'unknown'; createdDateTime = (& $ago 10); lastUpdateDateTime = (& $ago 1); incidentWebUrl = 'https://security.microsoft.com/incidents/101' }
            @{ id = '102'; displayName = 'Suspicious inbox rule'; severity = 'low'; status = 'resolved'; assignedTo = 'secops@contoso.com'; classification = 'truePositive'; createdDateTime = (& $ago 30); lastUpdateDateTime = (& $ago 20); incidentWebUrl = 'https://security.microsoft.com/incidents/102' }
        )
        UsageReport            = @(
            @{ userPrincipalName = 'dave@contoso.com'; displayName = 'Dave'; isDeleted = $false; hasExchangeLicense = $true; hasTeamsLicense = $true; exchangeLastActivityDate = $now.AddDays(-2).ToString('yyyy-MM-dd'); assignedProducts = @('MICROSOFT 365 E5') }
            @{ userPrincipalName = 'erin@contoso.com'; displayName = 'Erin'; isDeleted = $false; hasExchangeLicense = $true; hasTeamsLicense = $true; exchangeLastActivityDate = $null; teamsLastActivityDate = $now.AddDays(-45).ToString('yyyy-MM-dd'); assignedProducts = @('MICROSOFT 365 E5') }
            @{ userPrincipalName = 'old@contoso.com'; displayName = 'Old'; isDeleted = $true; hasExchangeLicense = $true; assignedProducts = @() }
            @{ userPrincipalName = 'frank_partner.com#EXT#@contoso.onmicrosoft.com'; displayName = 'Frank'; isDeleted = $false; hasExchangeLicense = $false; assignedProducts = @() }
        )
        AppProtectionIos       = @(@{ id = 'mam1'; displayName = 'iOS: corporate data'; assignments = @(@{ id = 'a1' }); pinRequired = $false; allowedOutboundDataTransferDestinations = 'allApps'; allowedOutboundClipboardSharingLevel = 'allApps'; dataBackupBlocked = $true; saveAsBlocked = $false; minimumRequiredOsVersion = '17.0'; lastModifiedDateTime = (& $ago 40) })
        AppProtectionAndroid   = @()
        RoleEligibility        = @(@{ roleDefinitionId = $ga; principalId = 'u-carol'; directoryScopeId = '/' })
        Registration           = @((& $reg 'u-alice' 'Alice' 'member' $true $true), (& $reg 'u-bob' 'Bob' 'member' $true $false), (& $reg 'u-carol' 'Carol' 'member' $false $true), (& $reg 'u-dave' 'Dave' 'member' $false $false), (& $reg 'u-erin' 'Erin' 'member' $false $false), (& $reg 'u-frank' 'Frank' 'guest' $false $false), (& $reg 'u-bg1' 'BG-Admin1' 'member' $true $true))
        Users                  = @(
            (& $person 'u-alice' 'Alice' 'alice@contoso.com' $true $false 'Member' 2)
            (& $person 'u-bob' 'Bob' 'bob@contoso.com' $true $true 'Member' 200)
            (& $person 'u-carol' 'Carol' 'carol@contoso.com' $true $false 'Member' 5)
            (& $person 'u-dave' 'Dave' 'dave@contoso.com' $true $false 'Member' 1)
            (& $person 'u-erin' 'Erin' 'erin@contoso.com' $true $false 'Member' 1)
            (& $person 'u-frank' 'Frank' 'frank_partner.com#EXT#@contoso.onmicrosoft.com' $true $false 'Guest' 30)
            (& $person 'u-bg1' 'BG Admin 1' 'bg-admin1@contoso.onmicrosoft.com' $true $false 'Member' 150)
            (& $person 'u-zoe' 'Zoe' 'zoe@contoso.com' $false $false 'Member' 300)
            (& $person 'u-gary' 'Gary (guest)' 'gary_fabrikam.com#EXT#@contoso.onmicrosoft.com' $true $false 'Guest' 3)
        )
        AdminConsentPolicy     = @{ isEnabled = $false; reviewers = @() }
        LegacySignIns          = @(
            (& $signIn 'IMAP4' 'dave@contoso.com' 0 1); (& $signIn 'IMAP4' 'dave@contoso.com' 0 2); (& $signIn 'IMAP4' 'dave@contoso.com' 0 3)
            (& $signIn 'POP3' 'erin@contoso.com' 50126 1)
            (& $signIn 'Authenticated SMTP' 'printer@contoso.com' 0 1)
        )
        Applications           = @(
            @{ id = 'app-payroll'; appId = 'appid-payroll'; displayName = 'Payroll'; signInAudience = 'AzureADMyOrg'
                passwordCredentials = @((& $credential 'old secret' -800 20), (& $credential 'two-year+ secret' -10 1000)); keyCredentials = @((& $credential 'signing cert' -100 2000))
                web = @{ redirectUris = @('https://payroll-old.azurewebsites.net/signin', 'http://intranet.contoso.com/cb', 'https://*.contoso.com/cb') }; spa = @{ redirectUris = @('https://app.contoso.com') }; publicClient = @{ redirectUris = @() } }
            @{ id = 'app-portal'; appId = 'appid-portal'; displayName = 'Partner portal'; signInAudience = 'AzureADMultipleOrgs'
                passwordCredentials = @((& $credential 'expired' -400 -5)); keyCredentials = @()
                web = @{ redirectUris = @('https://gone.fabrikam-old.com/auth') }; spa = @{ redirectUris = @() }; publicClient = @{ redirectUris = @('http://localhost:8080') } }
        )
        ServicePrincipals      = @(
            @{ id = 'sp-payroll'; appId = 'appid-payroll'; displayName = 'Payroll'; appOwnerOrganizationId = '00000000-0000-0000-0000-00000000c0de'; passwordCredentials = @(); keyCredentials = @() }
            @{ id = 'sp-mail'; appId = 'appid-mail'; displayName = 'MailSync Pro'; appOwnerOrganizationId = 'aaaaaaaa-0000-0000-0000-000000000001'; publisherName = 'MailSync Ltd'; verifiedPublisher = @{ displayName = $null; verifiedPublisherId = $null }; passwordCredentials = @(); keyCredentials = @() }
            @{ id = 'sp-automation'; appId = 'appid-automation'; displayName = 'Automation runbook'; appOwnerOrganizationId = '00000000-0000-0000-0000-00000000c0de'; passwordCredentials = @(); keyCredentials = @() }
            @{ id = 'sp-teams'; appId = 'appid-teams'; displayName = 'Microsoft Teams'; appOwnerOrganizationId = 'f8cdef31-a31e-4b4a-93e4-5f571e91255a'; passwordCredentials = @((& $credential 'first-party' -10 9000)); keyCredentials = @() }
            @{ id = 'sp-graph'; appId = '00000003-0000-0000-c000-000000000000'; displayName = 'Microsoft Graph'; appOwnerOrganizationId = 'f8cdef31-a31e-4b4a-93e4-5f571e91255a'; passwordCredentials = @(); keyCredentials = @() }
        )
        GraphServicePrincipal  = @{ id = 'sp-graph'; appId = '00000003-0000-0000-c000-000000000000'; appRoles = @(@{ id = 'r-rw-dir'; value = 'RoleManagement.ReadWrite.Directory' }, @{ id = 'r-mail'; value = 'Mail.Read' }, @{ id = 'r-users'; value = 'User.Read.All' }) }
        GraphAppRoleGrants     = @(
            @{ principalId = 'sp-payroll'; principalDisplayName = 'Payroll'; appRoleId = 'r-users'; createdDateTime = (& $ago 100) }
            @{ principalId = 'sp-mail'; principalDisplayName = 'MailSync Pro'; appRoleId = 'r-mail'; createdDateTime = (& $ago 50) }
            @{ principalId = 'sp-automation'; principalDisplayName = 'Automation runbook'; appRoleId = 'r-rw-dir'; createdDateTime = (& $ago 20) }
            @{ principalId = 'sp-teams'; principalDisplayName = 'Microsoft Teams'; appRoleId = 'r-mail'; createdDateTime = (& $ago 900) }
        )
        DelegatedGrants        = @(
            @{ clientId = 'sp-mail'; consentType = 'AllPrincipals'; resourceId = 'sp-graph'; scope = 'Mail.ReadWrite offline_access' }
            @{ clientId = 'sp-payroll'; consentType = 'Principal'; principalId = 'u-dave'; resourceId = 'sp-graph'; scope = 'User.Read' }
            @{ clientId = 'sp-payroll'; consentType = 'Principal'; principalId = 'u-erin'; resourceId = 'sp-graph'; scope = 'User.Read' }
        )
        IdentityProviders      = @(@{ '@odata.type' = '#microsoft.graph.socialIdentityProvider'; id = 'Google-OAUTH'; displayName = 'Google' })
        Domains                = @(
            @{ id = 'contoso.com'; isDefault = $true; isVerified = $true; isInitial = $false; authenticationType = 'Managed'; supportedServices = @('Email', 'OfficeCommunicationsOnline'); passwordValidityPeriodInDays = 2147483647 }
            @{ id = 'contoso.onmicrosoft.com'; isDefault = $false; isVerified = $true; isInitial = $true; authenticationType = 'Managed'; supportedServices = @('Email') }
            @{ id = 'fabrikam.com'; isDefault = $false; isVerified = $false; isInitial = $false; authenticationType = 'Managed'; supportedServices = @() }
            @{ id = 'legacy.contoso.com'; isDefault = $false; isVerified = $true; isInitial = $false; authenticationType = 'Federated'; supportedServices = @('Email') }
        )
        SecureScore            = @(@{ createdDateTime = (& $ago 1); currentScore = 40; maxScore = 100; averageComparativeScores = @(@{ basis = 'AllTenants'; averageScore = 45.5 }); controlScores = @(
                    @{ controlName = 'AuditLogSearch'; controlCategory = 'Data'; score = 0; description = 'Audit is <b>off</b>.' }
                    @{ controlName = 'MFARegistrationV2'; controlCategory = 'Identity'; score = 5; description = '' }
                    @{ controlName = 'OldControl'; controlCategory = 'Apps'; score = 0; description = '' }
                ) })
        SecureScoreProfiles    = @(
            @{ id = 'AuditLogSearch'; title = 'Turn on audit log search'; maxScore = 10; service = 'EXO'; controlCategory = 'Data'; userImpact = 'Low'; implementationCost = 'Low'; remediation = '<p>Turn it on.</p>'; actionUrl = 'https://purview.microsoft.com'; deprecated = $false }
            @{ id = 'MFARegistrationV2'; title = 'Ensure all users can complete MFA'; maxScore = 10; service = 'AzureAD'; controlCategory = 'Identity'; userImpact = 'Moderate'; implementationCost = 'Low'; remediation = 'Register.'; actionUrl = 'https://entra.microsoft.com'; deprecated = $false }
            @{ id = 'OldControl'; title = 'Retired control'; maxScore = 5; deprecated = $true }
        )
        SharePoint             = @{ sharingCapability = 'externalUserAndGuestSharing'; oneDriveLoopSharingCapability = 'externalUserSharingOnly'; sharingDomainRestrictionMode = 'none'; sharingAllowedDomainList = @(); sharingBlockedDomainList = @(); isResharingByExternalUsersEnabled = $true; isRequireAcceptingUserToMatchInvitedUserEnabled = $true; isLegacyAuthProtocolsEnabled = $false; isUnmanagedSyncAppForTenantRestricted = $false; idleSessionSignOut = @{ isEnabled = $false }; isSiteCreationEnabled = $true; deletedUserPersonalSiteRetentionPeriodInDays = 30 }
        DirectoryAudits        = @(@{ activityDateTime = (& $ago 0); activityDisplayName = 'Update user' })
        DeviceManagement       = @{ settings = @{ deviceComplianceCheckinThresholdDays = 30; isScheduledActionEnabled = $true; secureByDefault = $false } }
        EnrollmentRestrictions = @(
            @{ '@odata.type' = '#microsoft.graph.deviceEnrollmentPlatformRestrictionsConfiguration'; displayName = 'All users and all devices'; priority = 0; lastModifiedDateTime = (& $ago 50)
                windowsRestriction = @{ platformBlocked = $false; personalDeviceEnrollmentBlocked = $false; osMinimumVersion = ''; osMaximumVersion = '' }
                iosRestriction = @{ platformBlocked = $false; personalDeviceEnrollmentBlocked = $true; osMinimumVersion = '17.0'; osMaximumVersion = '' } }
            @{ '@odata.type' = '#microsoft.graph.deviceEnrollmentLimitConfiguration'; displayName = 'All users and all devices'; priority = 0; limit = 15; lastModifiedDateTime = (& $ago 50) }
            @{ '@odata.type' = '#microsoft.graph.windowsHelloForBusinessConfiguration'; displayName = 'Windows Hello for Business'; priority = 0 }
        )
        ComplianceSummary      = @{ compliantDeviceCount = 2; nonCompliantDeviceCount = 2; inGracePeriodCount = 0; errorDeviceCount = 0 }
        CompliancePolicies     = @(
            @{ '@odata.type' = '#microsoft.graph.windows10CompliancePolicy'; id = 'cp1'; displayName = 'Windows baseline'; lastModifiedDateTime = (& $ago 20); assignments = @(@{ id = 'a1' }) }
            @{ '@odata.type' = '#microsoft.graph.iosCompliancePolicy'; id = 'cp2'; displayName = 'iOS draft'; lastModifiedDateTime = (& $ago 20); assignments = @() }
        )
        ConfigurationPolicies  = @(
            @{ id = 'p1'; name = 'Defender Antivirus'; platforms = 'windows10'; templateReference = @{ templateFamily = 'endpointSecurityAntivirus'; templateDisplayName = 'Microsoft Defender Antivirus' }; isAssigned = $true; lastModifiedDateTime = (& $ago 5) }
            @{ id = 'p2'; name = 'Firewall draft'; platforms = 'windows10'; templateReference = @{ templateFamily = 'endpointSecurityFirewall'; templateDisplayName = 'Windows Firewall' }; isAssigned = $false; lastModifiedDateTime = (& $ago 5) }
            @{ id = 'p3'; name = 'Wi-Fi'; platforms = 'windows10'; templateReference = @{ templateFamily = 'none' }; isAssigned = $true }
        )
        Intents                = @(@{ id = 'i1'; displayName = 'BitLocker'; templateId = 't1'; isAssigned = $true; lastModifiedDateTime = (& $ago 5) })
        Templates              = @(@{ id = 't1'; displayName = 'BitLocker'; templateType = 'securityTemplate'; templateSubtype = 'diskEncryption' })
        ManagedDevices         = @(
            (& $device 'PC1' 'Windows' 'compliant' $true 'False' 2 'd-pc1')
            (& $device 'PC2' 'Windows' 'noncompliant' $false 'False' 100 'd-pc2')
            (& $device 'iPhone' 'iOS' 'compliant' $true 'False' 3 'd-iphone')
            (& $device 'Pixel' 'Android' 'noncompliant' $true 'True' 4 'd-pixel')
        )
        EntraDevices           = @((& $entra 'PC1' 'd-pc1' $true 2 'AzureAd'), (& $entra 'LAPTOP-HOME' 'd-home' $false 5 'Workplace'), (& $entra 'OLD-PC' 'd-old' $false 200 'ServerAd'))
    }
    # The redirect URI hosts as DNS answers them (Resolve-AACHostName).
    $resolved = @{ 'payroll-old.azurewebsites.net' = $false; 'intranet.contoso.com' = $true; 'app.contoso.com' = $true; 'gone.fabrikam-old.com' = $false }
    @{ Data = $data; Now = $now; Resolved = $resolved }
}
