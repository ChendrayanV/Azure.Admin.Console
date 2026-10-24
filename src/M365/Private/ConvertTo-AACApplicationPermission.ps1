function ConvertTo-AACApplicationPermission {
    <#
    .SYNOPSIS
        Turns what Read-AACApplicationPermission read into one row per
        permission the service principal holds - and findings for the
        privileged ones.
    .DESCRIPTION
        No calls. Rows (AAC.ApplicationPermissionEntry), by Kind:
          Application permission    an API's app role (Microsoft Graph
                                    User.Read.All...) - tenant-wide
          Delegated permission      scopes consented for all users (admin
                                    consent) or for one user
          Directory role            an Entra role, at tenant scope, on an
                                    administrative unit (with the objects
                                    it covers) or on one object; direct or
                                    through a role-assignable group
          Directory role (eligible) the same through PIM, to be activated
          Azure role                Azure RBAC, direct or through a group
          Owner                     applications, service principals and
                                    groups it owns
          Group membership          the groups it is in
          Requested (not granted)   API permissions its app registration
                                    asks for that nobody consented to

        Findings (AAC.ApplicationPermissionFinding): privileged application
        permissions (Directory.ReadWrite.All, RoleManagement.ReadWrite.Directory,
        AppRoleAssignment.ReadWrite.All, Mail.Send...); privileged directory
        roles at tenant scope (Global Administrator, Privileged Role
        Administrator, Application Administrator...) and any other role at
        tenant scope; Azure Owner, User Access Administrator or Role Based
        Access Control Administrator, and Contributor on a subscription or
        above; privileged delegated scopes consented for everyone; owning
        another application (its credentials - and so its permissions - can
        be added to).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Read
    )

    $p = $Read.Principal
    $principalName = [string]$p['displayName']
    $principalId = [string]$p['id']
    $privilegedApi = @(
        'Directory.ReadWrite.All', 'RoleManagement.ReadWrite.Directory', 'AppRoleAssignment.ReadWrite.All', 'Application.ReadWrite.All', 'Application.ReadWrite.OwnedBy'
        'Group.ReadWrite.All', 'GroupMember.ReadWrite.All', 'User.ReadWrite.All', 'UserAuthenticationMethod.ReadWrite.All', 'Policy.ReadWrite.ConditionalAccess'
        'Domain.ReadWrite.All', 'Mail.ReadWrite', 'Mail.Send', 'MailboxSettings.ReadWrite', 'Files.ReadWrite.All', 'Sites.ReadWrite.All', 'Sites.FullControl.All'
        'Exchange.ManageAsApp', 'full_access_as_app', 'Device.ReadWrite.All', 'PrivilegedAccess.ReadWrite.AzureADGroup', 'RoleAssignmentSchedule.ReadWrite.Directory'
    )
    $privilegedRoles = @(
        'Global Administrator', 'Privileged Role Administrator', 'Privileged Authentication Administrator', 'Application Administrator', 'Cloud Application Administrator'
        'Hybrid Identity Administrator', 'Conditional Access Administrator', 'Security Administrator', 'Exchange Administrator', 'SharePoint Administrator'
        'Intune Administrator', 'User Administrator', 'Authentication Administrator', 'Groups Administrator', 'Partner Tier2 Support', 'Directory Synchronization Accounts'
    )
    $readerRoles = @('Directory Readers', 'Global Reader', 'Security Reader', 'Reports Reader', 'Message Center Reader')
    $grantRoles = @('Owner', 'User Access Administrator', 'Role Based Access Control Administrator')
    $rows = [System.Collections.Generic.List[object]]::new()
    $findings = [System.Collections.Generic.List[object]]::new()
    $row = {
        param([string] $Kind, [string] $Api, [string] $Permission, [string] $Scope, [string] $Via, [string] $Detail, [string] $Severity = '', $Since = $null, [string] $Id = '')
        $rows.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.ApplicationPermissionEntry'; Principal = $principalName; PrincipalId = $principalId; Kind = $Kind; Api = $Api; Permission = $Permission; Scope = $Scope; Via = $Via; Privileged = $Severity; Detail = $Detail; Since = $Since; Id = $Id })
    }
    $finding = {
        param([string] $Severity, [string] $Item, [string] $Title, [string] $Detail, [string] $Fix)
        $findings.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.ApplicationPermissionFinding'; Severity = $Severity; Principal = $principalName; Item = $Item; Finding = $Title; Detail = $Detail; Recommendation = $Fix })
    }
    $when = { param($Value) if ($Value -is [datetime]) { $Value.ToUniversalTime() } elseif ($Value) { try { [datetime]::Parse([string]$Value, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal) } catch { $null } } else { $null } }
    $resourceOf = { param([string] $Id) $r = $Read.Resources[$Id.ToLowerInvariant()]; if ($r) { $r } else { $null } }
    $scopeWords = {
        param([string] $ScopeId)
        if (-not $ScopeId -or $ScopeId -eq '/') { 'Tenant' } elseif ($Read.ScopeNames.ContainsKey($ScopeId)) { $Read.ScopeNames[$ScopeId] } else { $ScopeId }
    }

    # --- Application permissions (app roles) -------------------------------------------------------------------------
    $grantedRoles = @{}
    foreach ($a in @($Read.AppRoleAssignments)) {
        $api = & $resourceOf ([string]$a['resourceId'])
        $apiName = if ($api) { [string]$api['displayName'] } else { [string]$a['resourceDisplayName'] }
        $roleId = [string]$a['appRoleId']
        $role = if ($api) { @(@($api['appRoles']) | Where-Object { $_ -and [string]$_['id'] -eq $roleId }) | Select-Object -First 1 } else { $null }
        $value = if ($roleId -eq '00000000-0000-0000-0000-000000000000') { 'Default access' } elseif ($role) { [string]$role['value'] } else { $roleId }
        $grantedRoles["$(([string]$a['resourceId']).ToLowerInvariant())|$($roleId.ToLowerInvariant())"] = $true
        $severity = if ($value -in $privilegedApi) { 'High' } else { '' }
        & $row 'Application permission' $apiName $value 'Tenant' 'Direct' $(if ($role) { [string]$role['displayName'] } else { '' }) $severity (& $when $a['createdDateTime']) ([string]$a['id'])
        if ($severity) { & $finding 'High' "$apiName $value" 'Privileged application permission' "$value lets the application act across the whole tenant, with no user signed in." 'Check it is still needed; narrow it (Sites.Selected, Mail with an application access policy, a role on an administrative unit - New-AACApplicationPermission) or remove it.' }
    }

    # --- Delegated permissions --------------------------------------------------------------------------------------
    $grantedScopes = @{}
    foreach ($g in @($Read.Grants)) {
        $api = & $resourceOf ([string]$g['resourceId'])
        $apiName = if ($api) { [string]$api['displayName'] } else { [string]$g['resourceId'] }
        $everyone = [string]$g['consentType'] -eq 'AllPrincipals'
        foreach ($scope in @(([string]$g['scope']).Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries))) {
            $grantedScopes["$(([string]$g['resourceId']).ToLowerInvariant())|$($scope.ToLowerInvariant())"] = $true
            $severity = if ($everyone -and $scope -in $privilegedApi) { 'Medium' } else { '' }
            & $row 'Delegated permission' $apiName $scope $(if ($everyone) { 'All users (admin consent)' } else { "One user ($($g['principalId']))" }) 'Direct' 'Acts as the signed-in user, within what that user may do.' $severity $null ([string]$g['id'])
            if ($severity) { & $finding 'Medium' "$apiName $scope" 'Privileged delegated permission for everyone' "$scope was consented for all users: the application can use it for anyone who signs in to it." 'Check the application is trusted and still needs it; otherwise revoke the consent.' }
        }
    }

    # --- Directory roles --------------------------------------------------------------------------------------------
    $roleRow = {
        param($Assignment, [string] $Kind, [string] $Via)
        $definition = $Assignment['roleDefinition']
        $roleName = if ($definition) { [string]$definition['displayName'] } else { [string]$Assignment['roleDefinitionId'] }
        $scopeId = [string]$Assignment['directoryScopeId']
        $scope = & $scopeWords $scopeId
        $actions = @(if ($definition) { @($definition['rolePermissions']) | Where-Object { $_ } | ForEach-Object { @($_['allowedResourceActions']) } | Where-Object { $_ } })
        $builtIn = $definition -and [string]$definition['isBuiltIn'] -eq 'True'
        $covers = if ($Read.UnitMembers.ContainsKey($scopeId)) { "Covers: $(if (@($Read.UnitMembers[$scopeId]).Count) { @($Read.UnitMembers[$scopeId]) -join ', ' } else { 'nothing yet' })" } else { '' }
        $detail = (@($covers, $(if ($builtIn) { 'Built-in role' } elseif ($actions.Count) { "Custom role: $($actions -join ', ')" } else { '' })) | Where-Object { $_ }) -join ' - '
        $tenantWide = $scope -eq 'Tenant'
        $severity = if ($tenantWide -and $roleName -in $privilegedRoles) { 'High' } elseif ($tenantWide -and $roleName -notin $readerRoles) { 'Medium' } else { '' }
        & $row $Kind 'Microsoft Entra ID' $roleName $scope $Via $detail $severity (& $when $Assignment['createdDateTime']) ([string]$Assignment['id'])
        if ($severity -eq 'High') { & $finding 'High' $roleName 'Privileged directory role on the whole tenant' "$roleName at tenant scope$(if ($Via -ne 'Direct') { " ($Via)" })$(if ($Kind -like '*eligible*') { ', eligible through PIM' })." 'Scope it to an administrative unit or an application where the role allows, or use a narrower role.' }
        elseif ($severity -eq 'Medium') { & $finding 'Medium' $roleName 'Directory role on the whole tenant' "$roleName covers every object of its kind in the tenant$(if ($Via -ne 'Direct') { " ($Via)" })." 'Scope it to an administrative unit (New-AACApplicationPermission does this for group rights) if the application needs only some objects.' }
    }
    foreach ($a in @($Read.RoleAssignments)) { & $roleRow $a 'Directory role' 'Direct' }
    foreach ($a in @($Read.Eligible)) { & $roleRow $a 'Directory role (eligible)' 'Direct' }
    foreach ($groupId in $Read.GroupRoleAssignments.Keys) {
        $groupName = @(@($Read.MemberOf) | Where-Object { [string]$_['id'] -eq $groupId } | ForEach-Object { [string]$_['displayName'] }) | Select-Object -First 1
        foreach ($a in @($Read.GroupRoleAssignments[$groupId])) { & $roleRow $a 'Directory role' "group $groupName" }
    }

    # --- Azure roles ------------------------------------------------------------------------------------------------
    $groupNames = @{}
    foreach ($m in @($Read.MemberOf)) { $groupNames[([string]$m['id']).ToLowerInvariant()] = [string]$m['displayName'] }
    foreach ($holder in $Read.Azure.Keys) {
        $via = if ($holder -eq $principalId.ToLowerInvariant()) { 'Direct' } else { "group $($groupNames[$holder])" }
        foreach ($a in @($Read.Azure[$holder])) {
            $severity = if ($a.Role -in $grantRoles) { 'High' } elseif ($a.Role -eq 'Contributor' -and $a.Level -in 'Subscription', 'Management group', 'Tenant') { 'Medium' } else { '' }
            & $row 'Azure role' 'Azure Resource Manager' $a.Role $a.Scope $via $a.ScopeId $severity $null $a.Id
            if ($severity -eq 'High') { & $finding 'High' "$($a.Role) on $($a.Scope)" 'Can grant Azure access' "$($a.Role) can give anyone - itself included - any role on $($a.Scope)$(if ($via -ne 'Direct') { " ($via)" })." 'Use Contributor (or narrower) on the resource groups it needs.' }
            elseif ($severity) { & $finding 'Medium' "Contributor on $($a.Scope)" 'Contributor on a whole subscription or more' "It can change any resource in $($a.Scope)$(if ($via -ne 'Direct') { " ($via)" })." 'Narrow it to the resource groups or resources it works on.' }
        }
    }

    # --- Owned objects and groups -----------------------------------------------------------------------------------
    foreach ($o in @($Read.Owned)) {
        $type = ([string]$o['@odata.type']) -replace '^#microsoft\.graph\.', ''
        $name = [string]$o['displayName']
        $isApp = $type -in 'application', 'servicePrincipal'
        & $row 'Owner' 'Microsoft Entra ID' $name $type 'Direct' $(if ($isApp) { 'Can add credentials to it - and so use its permissions.' } elseif ($type -eq 'group') { 'Can change its members and settings.' } else { '' }) $(if ($isApp) { 'Medium' } else { '' }) $null ([string]$o['id'])
        if ($isApp) { & $finding 'Medium' $name 'Owns another application' "As owner of the $type $name it can add a secret or certificate to it, and act with that application's permissions." 'Remove the ownership unless it is needed; owners should be people (or a pipeline identity) who manage the application.' }
    }
    foreach ($m in @($Read.MemberOf)) { & $row 'Group membership' 'Microsoft Entra ID' ([string]$m['displayName']) 'group' 'Direct' $(if ([string]$m['isAssignableToRole'] -eq 'True') { 'Role-assignable group: its directory roles apply to the application.' } else { 'Its Azure roles, app role assignments and access apply to the application.' }) '' $null ([string]$m['id']) }

    # --- Requested by the app registration, not granted --------------------------------------------------------------
    if ($Read.Application) {
        foreach ($required in @($Read.Application['requiredResourceAccess'])) {
            if (-not $required) { continue }
            $api = $Read.Resources["app|$(([string]$required['resourceAppId']).ToLowerInvariant())"]
            $apiName = if ($api) { [string]$api['displayName'] } else { [string]$required['resourceAppId'] }
            $apiId = if ($api) { ([string]$api['id']).ToLowerInvariant() } else { '' }
            foreach ($access in @($required['resourceAccess'])) {
                if (-not $access) { continue }
                $accessId = ([string]$access['id']).ToLowerInvariant()
                if ([string]$access['type'] -eq 'Role') {
                    $role = if ($api) { @(@($api['appRoles']) | Where-Object { $_ -and ([string]$_['id']).ToLowerInvariant() -eq $accessId }) | Select-Object -First 1 } else { $null }
                    if (-not $grantedRoles.ContainsKey("$apiId|$accessId")) { & $row 'Requested (not granted)' $apiName $(if ($role) { [string]$role['value'] } else { $accessId }) 'Application permission' 'App registration' 'Asked for in API permissions, without admin consent.' }
                }
                else {
                    $scope = if ($api) { @(@($api['oauth2PermissionScopes']) | Where-Object { $_ -and ([string]$_['id']).ToLowerInvariant() -eq $accessId }) | Select-Object -First 1 } else { $null }
                    $value = if ($scope) { [string]$scope['value'] } else { $accessId }
                    if (-not $grantedScopes.ContainsKey("$apiId|$($value.ToLowerInvariant())")) { & $row 'Requested (not granted)' $apiName $value 'Delegated permission' 'App registration' 'Asked for in API permissions; no consent found (users may still consent one by one, if allowed).' }
                }
            }
        }
    }

    $kindOrder = @('Application permission', 'Delegated permission', 'Directory role', 'Directory role (eligible)', 'Azure role', 'Owner', 'Group membership', 'Requested (not granted)')
    $rank = @{ High = 0; Medium = 1; Low = 2; Info = 3 }
    @{
        Rows     = @($rows | Sort-Object -Property @{ Expression = { $kindOrder.IndexOf($_.Kind) } }, Api, Permission)
        Findings = @($findings | Sort-Object -Property @{ Expression = { $rank[$_.Severity] } }, Item)
        Summary  = [pscustomobject][ordered]@{
            PSTypeName             = 'AAC.ApplicationPermissionSummary'
            Principal              = $principalName
            PrincipalId            = $principalId
            AppId                  = [string]$p['appId']
            Type                   = [string]$p['servicePrincipalType']
            HomeTenant             = [string]$p['appOwnerOrganizationId']
            Enabled                = [string]$p['accountEnabled'] -ne 'False'
            ApplicationPermissions = @($rows | Where-Object Kind -EQ 'Application permission').Count
            DelegatedPermissions   = @($rows | Where-Object Kind -EQ 'Delegated permission').Count
            DirectoryRoles         = @($rows | Where-Object Kind -Like 'Directory role*').Count
            AzureRoles             = @($rows | Where-Object Kind -EQ 'Azure role').Count
            Owned                  = @($rows | Where-Object Kind -EQ 'Owner').Count
            Groups                 = @($rows | Where-Object Kind -EQ 'Group membership').Count
            NotGranted             = @($rows | Where-Object Kind -EQ 'Requested (not granted)').Count
            High                   = @($findings | Where-Object Severity -EQ 'High').Count
        }
    }
}
