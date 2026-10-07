function Get-AACM365AssessmentQuery {
    <#
    .SYNOPSIS
        The Microsoft Graph calls of Invoke-AACM365Assessment: each one's
        URI, the section it belongs to and the permission it needs.
    .DESCRIPTION
        -Section picks Entra, Microsoft365 and Intune (all by default).
        Returns an ordered hashtable: name -> @{ Uri; Section; Data (what
        it reads, for the Permissions table); Permission (the least
        Microsoft Graph permission, delegated or application); Note }, and
        for a few:
          Fallback   the URI to read instead when Uri is refused (Users:
                     without the last sign-in, which needs Entra ID P1)
          Lookup     Users: not listed but looked up - the principals of the
                     role assignments, the users Conditional Access
                     excludes, and break-glass-like names - {0} a $filter
          DependsOn  read in a second round, Uri's {0} filled from that
                     query's id (GraphAppRoleGrants: Microsoft Graph's
                     service principal)
          MaxItems   read no more than this many (LegacySignIns: Uri is a
                     template - {0} the start date, {1} a protocol - read
                     once per legacy protocol)
        Everything is read-only and v1.0, except Intune's endpoint security
        profiles (configurationPolicies, intents and templates), which
        exist only in the beta API.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [ValidateSet('Entra', 'Microsoft365', 'Intune')]
        [string[]] $Section = @('Entra', 'Microsoft365', 'Intune')
    )

    $v1 = 'https://graph.microsoft.com/v1.0'
    $beta = 'https://graph.microsoft.com/beta'
    $all = [ordered]@{
        # --- Entra ID ---------------------------------------------------------------------------------------------
        Organization          = @{ Section = 'Entra'; Data = 'Tenant details'; Permission = 'Organization.Read.All'; Uri = "$v1/organization?`$select=id,displayName,verifiedDomains,createdDateTime,tenantType,onPremisesSyncEnabled,onPremisesLastSyncDateTime,technicalNotificationMails,securityComplianceNotificationMails,countryLetterCode,preferredDataLocation" }
        Licenses              = @{ Section = 'Entra'; Data = 'Licences (subscribed SKUs)'; Permission = 'Organization.Read.All'; Uri = "$v1/subscribedSkus" }
        SecurityDefaults      = @{ Section = 'Entra'; Data = 'Security defaults'; Permission = 'Policy.Read.All'; Uri = "$v1/policies/identitySecurityDefaultsEnforcementPolicy" }
        AuthorizationPolicy   = @{ Section = 'Entra'; Data = 'User and guest settings (authorization policy)'; Permission = 'Policy.Read.All'; Uri = "$v1/policies/authorizationPolicy" }
        AuthenticationMethods = @{ Section = 'Entra'; Data = 'Authentication methods policy'; Permission = 'Policy.Read.All'; Uri = "$v1/policies/authenticationMethodsPolicy" }
        CrossTenantAccess     = @{ Section = 'Entra'; Data = 'Cross-tenant access defaults'; Permission = 'Policy.Read.All'; Uri = "$v1/policies/crossTenantAccessPolicy/default" }
        ConditionalAccess     = @{ Section = 'Entra'; Data = 'Conditional Access policies'; Permission = 'Policy.Read.All'; Uri = "$v1/identity/conditionalAccess/policies" }
        NamedLocations        = @{ Section = 'Entra'; Data = 'Named locations'; Permission = 'Policy.Read.All'; Uri = "$v1/identity/conditionalAccess/namedLocations" }
        RoleDefinitions       = @{ Section = 'Entra'; Data = 'Directory role definitions'; Permission = 'RoleManagement.Read.Directory'; Uri = "$v1/roleManagement/directory/roleDefinitions?`$select=id,displayName,isBuiltIn,isPrivileged,templateId" }
        RoleAssignments       = @{ Section = 'Entra'; Data = 'Active admin role assignments'; Permission = 'RoleManagement.Read.Directory'; Uri = "$v1/roleManagement/directory/roleAssignments?`$expand=principal" }
        RoleEligibility       = @{ Section = 'Entra'; Data = 'Eligible admin role assignments (PIM)'; Permission = 'RoleManagement.Read.Directory'; Note = 'Needs Entra ID P2 (Privileged Identity Management).'; Uri = "$v1/roleManagement/directory/roleEligibilityScheduleInstances" }
        Registration          = @{ Section = 'Entra'; Data = 'MFA registration of every user'; Permission = 'AuditLog.Read.All'; Note = 'Needs Entra ID P1 or P2.'; Uri = "$v1/reports/authenticationMethods/userRegistrationDetails" }
        IdentityProviders     = @{ Section = 'Entra'; Data = 'External identity providers'; Permission = 'IdentityProvider.Read.All'; Uri = "$v1/identity/identityProviders" }
        # Not every user: the admins, the accounts Conditional Access excludes
        # and break-glass-like names - looked up by ID ({0}: a $filter).
        Users                 = @{ Section = 'Entra'; Data = 'Admins'' and excluded accounts'' last sign-in'; Permission = 'User.Read.All'; Note = 'The last sign-in needs AuditLog.Read.All and Entra ID P1; without them they are read without it.'; Uri = "$v1/users?`$filter={0}&`$select=id,displayName,userPrincipalName,accountEnabled,userType,onPremisesSyncEnabled,createdDateTime,signInActivity&`$top=999"; Fallback = "$v1/users?`$filter={0}&`$select=id,displayName,userPrincipalName,accountEnabled,userType,onPremisesSyncEnabled,createdDateTime&`$top=999"; DependsOn = 'RoleAssignments'; Lookup = $true }
        AdminConsentPolicy    = @{ Section = 'Entra'; Data = 'Admin consent workflow'; Permission = 'Policy.Read.All'; Uri = "$v1/policies/adminConsentRequestPolicy" }
        LegacySignIns         = @{ Section = 'Entra'; Data = 'Sign-ins with legacy authentication protocols'; Permission = 'AuditLog.Read.All'; Note = 'Needs Entra ID P1; one query per protocol, up to 200 sign-ins each.'; Uri = "$v1/auditLogs/signIns?`$filter=createdDateTime ge {0} and clientAppUsed eq '{1}'&`$top=200"; MaxItems = 200 }
        Applications          = @{ Section = 'Entra'; Data = 'App registrations: credentials and redirect URIs'; Permission = 'Application.Read.All'; Uri = "$v1/applications?`$select=id,appId,displayName,passwordCredentials,keyCredentials,web,spa,publicClient,signInAudience,createdDateTime,publisherDomain&`$top=999" }
        ServicePrincipals     = @{ Section = 'Entra'; Data = 'Enterprise applications: credentials and publishers'; Permission = 'Application.Read.All'; Uri = "$v1/servicePrincipals?`$select=id,appId,displayName,servicePrincipalType,accountEnabled,appOwnerOrganizationId,passwordCredentials,keyCredentials,verifiedPublisher,publisherName&`$top=999" }
        GraphServicePrincipal = @{ Section = 'Entra'; Data = 'Microsoft Graph''s permissions (app roles)'; Permission = 'Application.Read.All'; Uri = "$v1/servicePrincipals(appId='00000003-0000-0000-c000-000000000000')?`$select=id,appId,appRoles,oauth2PermissionScopes" }
        GraphAppRoleGrants    = @{ Section = 'Entra'; Data = 'Application permissions granted on Microsoft Graph'; Permission = 'Application.Read.All'; Uri = "$v1/servicePrincipals/{0}/appRoleAssignedTo?`$top=999"; DependsOn = 'GraphServicePrincipal' }
        DelegatedGrants       = @{ Section = 'Entra'; Data = 'Delegated permission grants (consents)'; Permission = 'DelegatedPermissionGrant.Read.All'; Uri = "$v1/oauth2PermissionGrants?`$top=999" }
        DirectorySync         = @{ Section = 'Entra'; Data = 'Directory sync settings (Entra Connect)'; Permission = 'OnPremDirectorySynchronization.Read.All'; Uri = "$v1/directory/onPremisesSynchronization" }
        PimPolicies           = @{ Section = 'Entra'; Data = 'PIM role settings (activation rules)'; Permission = 'RoleManagementPolicy.Read.Directory'; Note = 'Needs Entra ID P2.'; Uri = "$v1/policies/roleManagementPolicyAssignments?`$filter=scopeId eq '/' and scopeType eq 'DirectoryRole'&`$expand=policy(`$expand=rules)" }
        AccessReviews         = @{ Section = 'Entra'; Data = 'Access reviews'; Permission = 'AccessReview.Read.All'; Note = 'Needs Entra ID P2 or Entra ID Governance.'; Uri = "$v1/identityGovernance/accessReviews/definitions?`$top=100" }
        # The groups Conditional Access excludes and the groups holding roles ({0}: a $filter), then their members.
        Groups                = @{ Section = 'Entra'; Data = 'Groups excluded from Conditional Access or holding admin roles'; Permission = 'GroupMember.Read.All'; Uri = "$v1/groups?`$filter={0}&`$select=id,displayName,isAssignableToRole,groupTypes,membershipRule,securityEnabled"; DependsOn = 'ConditionalAccess'; Lookup = $true }
        GroupMembers          = @{ Section = 'Entra'; Data = 'Members of those groups (nested included)'; Permission = 'GroupMember.Read.All'; Uri = "$v1/groups/{0}/transitiveMembers?`$select=id,displayName,userPrincipalName,userType,accountEnabled&`$top=999"; DependsOn = 'Groups'; MaxItems = 1000 }
        RiskyUsers            = @{ Section = 'Entra'; Data = 'Risky users (Identity Protection)'; Permission = 'IdentityRiskyUser.Read.All'; Note = 'Needs Entra ID P2 for the full list.'; Uri = "$v1/identityProtection/riskyUsers?`$top=500"; MaxItems = 2000 }
        RiskDetections        = @{ Section = 'Entra'; Data = 'Risk detections (Identity Protection)'; Permission = 'IdentityRiskEvent.Read.All'; Note = 'Needs Entra ID P2 for the full detail.'; Uri = "$v1/identityProtection/riskDetections?`$filter=detectedDateTime ge {since}&`$top=500"; MaxItems = 1000 }
        # --- Microsoft 365 ------------------------------------------------------------------------------------------
        Domains               = @{ Section = 'Microsoft365'; Data = 'Domains'; Permission = 'Domain.Read.All'; Uri = "$v1/domains" }
        SecureScore           = @{ Section = 'Microsoft365'; Data = 'Microsoft Secure Score'; Permission = 'SecurityEvents.Read.All'; Uri = "$v1/security/secureScores?`$top=1"; MaxItems = 1 }
        SecureScoreProfiles   = @{ Section = 'Microsoft365'; Data = 'Secure Score control profiles'; Permission = 'SecurityEvents.Read.All'; Uri = "$v1/security/secureScoreControlProfiles" }
        SharePoint            = @{ Section = 'Microsoft365'; Data = 'SharePoint and OneDrive sharing settings'; Permission = 'SharePointTenantSettings.Read.All'; Uri = "$v1/admin/sharepoint/settings" }
        DirectoryAudits       = @{ Section = 'Microsoft365'; Data = 'Entra audit log (latest event)'; Permission = 'AuditLog.Read.All'; Uri = "$v1/auditLogs/directoryAudits?`$top=1"; MaxItems = 1 }
        Incidents             = @{ Section = 'Microsoft365'; Data = 'Microsoft Defender XDR incidents'; Permission = 'SecurityIncident.Read.All'; Uri = "$v1/security/incidents?`$top=50&`$orderby=lastUpdateDateTime desc"; MaxItems = 200 }
        UsageReport           = @{ Section = 'Microsoft365'; Data = 'Microsoft 365 activity per user, last 30 days (beta)'; Permission = 'Reports.Read.All'; Note = 'User names are hidden when the tenant conceals them in reports (Microsoft 365 admin center > Reports).'; Uri = "$beta/reports/getOffice365ActiveUserDetail(period='D30')?`$format=application/json" }
        # --- Intune --------------------------------------------------------------------------------------------------
        DeviceManagement      = @{ Section = 'Intune'; Data = 'Intune tenant settings'; Permission = 'DeviceManagementConfiguration.Read.All'; Uri = "$v1/deviceManagement?`$select=settings" }
        EnrollmentRestrictions = @{ Section = 'Intune'; Data = 'Enrollment restrictions'; Permission = 'DeviceManagementServiceConfig.Read.All'; Uri = "$v1/deviceManagement/deviceEnrollmentConfigurations" }
        ComplianceSummary     = @{ Section = 'Intune'; Data = 'Device compliance summary'; Permission = 'DeviceManagementConfiguration.Read.All'; Uri = "$v1/deviceManagement/deviceCompliancePolicyDeviceStateSummary" }
        CompliancePolicies    = @{ Section = 'Intune'; Data = 'Compliance policies'; Permission = 'DeviceManagementConfiguration.Read.All'; Uri = "$v1/deviceManagement/deviceCompliancePolicies?`$expand=assignments" }
        ConfigurationPolicies = @{ Section = 'Intune'; Data = 'Endpoint security and settings catalog policies (beta)'; Permission = 'DeviceManagementConfiguration.Read.All'; Uri = "$beta/deviceManagement/configurationPolicies?`$select=id,name,platforms,technologies,templateReference,lastModifiedDateTime,isAssigned" }
        Intents               = @{ Section = 'Intune'; Data = 'Endpoint security profiles from templates (beta)'; Permission = 'DeviceManagementConfiguration.Read.All'; Uri = "$beta/deviceManagement/intents?`$select=id,displayName,templateId,isAssigned,lastModifiedDateTime" }
        Templates             = @{ Section = 'Intune'; Data = 'Endpoint security templates (beta)'; Permission = 'DeviceManagementConfiguration.Read.All'; Uri = "$beta/deviceManagement/templates?`$select=id,displayName,templateType,templateSubtype" }
        ManagedDevices        = @{ Section = 'Intune'; Data = 'Intune managed devices'; Permission = 'DeviceManagementManagedDevices.Read.All'; Uri = "$v1/deviceManagement/managedDevices?`$select=id,deviceName,operatingSystem,osVersion,complianceState,managementAgent,managedDeviceOwnerType,lastSyncDateTime,enrolledDateTime,userPrincipalName,isEncrypted,jailBroken,model,manufacturer,azureADDeviceId,deviceEnrollmentType&`$top=999" }
        AppProtectionIos      = @{ Section = 'Intune'; Data = 'App protection policies: iOS/iPadOS'; Permission = 'DeviceManagementApps.Read.All'; Uri = "$v1/deviceAppManagement/iosManagedAppProtections?`$expand=assignments" }
        AppProtectionAndroid  = @{ Section = 'Intune'; Data = 'App protection policies: Android'; Permission = 'DeviceManagementApps.Read.All'; Uri = "$v1/deviceAppManagement/androidManagedAppProtections?`$expand=assignments" }
        EntraDevices          = @{ Section = 'Intune'; Data = 'Entra ID devices (managed or not)'; Permission = 'Device.Read.All'; Uri = "$v1/devices?`$select=id,deviceId,displayName,operatingSystem,operatingSystemVersion,isManaged,isCompliant,trustType,approximateLastSignInDateTime,accountEnabled,registrationDateTime&`$top=999" }
    }
    $picked = [ordered]@{}
    foreach ($key in $all.Keys) { if ($Section -contains $all[$key].Section) { $picked[$key] = $all[$key] } }
    $picked
}
