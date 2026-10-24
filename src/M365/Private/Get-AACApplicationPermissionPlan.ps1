function Get-AACApplicationPermissionPlan {
    <#
    .SYNOPSIS
        Plans giving an enterprise application (or managed identity) rights
        over specific Entra groups only: an administrative unit holding the
        groups, a directory role with just the group actions, and that role
        assigned to the application on the administrative unit - not the
        tenant. Reads only.
    .DESCRIPTION
        Microsoft Graph application permissions are tenant-wide:
        GroupMember.ReadWrite.All lets an application change the members of
        every group, and there is no "selected groups" version of it. A
        directory role assigned at an administrative unit's scope gives the
        same rights over the groups in that unit, and nowhere else.

        Reads, with Microsoft Graph (the Connect-AAC sign-in):
          - the service principal: by object ID, application ID or display
            name (two with the same name stop the plan)
          - each group, by object ID or display name
          - the administrative unit (by name) and its members
          - the role (by name): built-in, or a custom one whose actions are
            compared with the ones asked for
          - the principal's role assignments, and its Microsoft Graph
            application permissions - a tenant-wide one (GroupMember.ReadWrite.All,
            Group.ReadWrite.All, Directory.ReadWrite.All) overrides the scope

        Returns @{ Principal; Groups; AdministrativeUnit; Role; Actions;
        Changes (ordered: Order, Action - Create, Add, Update, Assign,
        Remove or NoChange - Resource, Detail, Method, Uri, Body; '{au}' and
        '{role}' in Uri and Body stand for IDs created during the apply);
        Findings (Severity, Item, Finding, Detail, Recommendation); Writes }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $ServicePrincipal,

        [Parameter(Mandatory)]
        [string[]] $Group,

        [Parameter(Mandatory)]
        [string[]] $AllowedResourceAction,

        # Empty: named after the principal.
        [string] $RoleName,

        [string] $AdministrativeUnitName,

        [string] $RoleDescription = 'Group rights, assigned at an administrative unit''s scope only.',

        [switch] $RestrictedManagement,

        [switch] $RemoveTenantWidePermission
    )

    $graph = 'https://graph.microsoft.com/v1.0'
    $isGuid = { param([string] $Text) $Text -match '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$' }
    $quote = { param([string] $Text) [System.Uri]::EscapeDataString($Text.Replace("'", "''")) }
    # One Graph read; a 404 is $null rather than an error.
    $get = {
        param([string] $Path, [switch] $AllowMissing)
        try { ConvertFrom-Json -InputObject (Invoke-AACHttp -Uri "$graph$Path" -Resource 'https://graph.microsoft.com').Content -AsHashtable -Depth 30 }
        catch { if ($AllowMissing -and $_.Exception.Data['StatusCode'] -eq 404) { return $null }; throw }
    }
    # A list, read to the end.
    $getAll = {
        param([string] $Path)
        $items = [System.Collections.Generic.List[object]]::new()
        $page = & $get $Path
        while ($true) {
            foreach ($item in @($page['value'])) { if ($null -ne $item) { $items.Add($item) } }
            $next = [string]$page['@odata.nextLink']
            if (-not $next) { break }
            $page = ConvertFrom-Json -InputObject (Invoke-AACHttp -Uri $next -Resource 'https://graph.microsoft.com').Content -AsHashtable -Depth 30
        }
        $items.ToArray()
    }
    $stop = {
        param([string] $Message, [string] $Hint)
        $problem = [System.InvalidOperationException]::new($Message)
        if ($Hint) { $problem.Data['AACHint'] = $Hint }
        throw $problem
    }

    # --- The principal --------------------------------------------------------------------------------------------
    $spSelect = '$select=id,appId,displayName,servicePrincipalType'
    $principal = $null
    if (& $isGuid $ServicePrincipal) {
        $principal = & $get "/servicePrincipals/$ServicePrincipal`?$spSelect" -AllowMissing
        if (-not $principal) { $principal = & $get "/servicePrincipals(appId='$ServicePrincipal')?$spSelect" -AllowMissing }
        if (-not $principal) { & $stop "Azure Admin Console found no service principal with the object or application ID $ServicePrincipal." 'Check the ID under Enterprise applications (for a managed identity, filter Application type = Managed Identities).' }
    }
    else {
        $found = @(& $getAll "/servicePrincipals?`$filter=displayName eq '$(& $quote $ServicePrincipal)'&$spSelect")
        if (-not $found.Count) { & $stop "Azure Admin Console found no enterprise application or managed identity named '$ServicePrincipal'." 'Check the name under Enterprise applications - for a system-assigned managed identity it is the Azure resource''s name.' }
        if ($found.Count -gt 1) { & $stop "Azure Admin Console found $($found.Count) service principals named '$ServicePrincipal': $(@($found | ForEach-Object { "$($_['id']) ($($_['servicePrincipalType']))" }) -join ', ')." 'Give -ServicePrincipal the object ID of the one you mean.' }
        $principal = $found[0]
    }
    $principalName = [string]$principal['displayName']
    $principalId = [string]$principal['id']

    # --- The groups -------------------------------------------------------------------------------------------------
    $groupSelect = '$select=id,displayName,securityEnabled,mailEnabled,groupTypes,isAssignableToRole'
    $groups = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($wanted in @($Group | Where-Object { $_ } | Select-Object -Unique)) {
        $g = if (& $isGuid $wanted) { & $get "/groups/$wanted`?$groupSelect" -AllowMissing } else {
            $byName = @(& $getAll "/groups?`$filter=displayName eq '$(& $quote $wanted)'&$groupSelect")
            if ($byName.Count -gt 1) { & $stop "Azure Admin Console found $($byName.Count) groups named '$wanted': $(@($byName | ForEach-Object { $_['id'] }) -join ', ')." 'Give -Group the object ID of the one you mean.' }
            @($byName) | Select-Object -First 1
        }
        if (-not $g) { & $stop "Azure Admin Console found no group '$wanted'." 'Check the name or object ID under Groups in the Entra admin center.' }
        if (-not @($groups | Where-Object { $_['id'] -eq $g['id'] }).Count) { $groups.Add($g) }
    }

    # --- Names --------------------------------------------------------------------------------------------------------
    if (-not $AdministrativeUnitName) { $AdministrativeUnitName = "AU-$principalName-Managed-Groups" }
    if (-not $RoleName) { $RoleName = "Group access (scoped) - $principalName" }

    # --- The administrative unit and its members -------------------------------------------------------------------
    $units = @(& $getAll "/directory/administrativeUnits?`$filter=displayName eq '$(& $quote $AdministrativeUnitName)'&`$select=id,displayName,description,isMemberManagementRestricted")
    if ($units.Count -gt 1) { & $stop "Azure Admin Console found $($units.Count) administrative units named '$AdministrativeUnitName'." 'Give -AdministrativeUnitName a name only one unit has.' }
    $unit = @($units) | Select-Object -First 1
    $unitMembers = @(if ($unit) { & $getAll "/directory/administrativeUnits/$($unit['id'])/members?`$select=id,displayName" })

    # --- The role ---------------------------------------------------------------------------------------------------
    $roles = @(& $getAll "/roleManagement/directory/roleDefinitions?`$filter=displayName eq '$(& $quote $RoleName)'")
    $role = @($roles) | Select-Object -First 1
    $wantedActions = @($AllowedResourceAction | Where-Object { $_ } | ForEach-Object { $_.Trim() } | Select-Object -Unique)
    # Two lists of actions are the same when they hold the same actions, in any order and case.
    $sameActions = { param([object[]] $First, [object[]] $Second) (@($First | ForEach-Object { ([string]$_).ToLowerInvariant() } | Sort-Object -Unique) -join '|') -eq (@($Second | ForEach-Object { ([string]$_).ToLowerInvariant() } | Sort-Object -Unique) -join '|') }
    $roleActions = @(if ($role) { @(Get-AACMember -InputObject $role -Path 'rolePermissions') | ForEach-Object { @(Get-AACMember -InputObject $_ -Path 'allowedResourceActions') } | Where-Object { $_ } })

    # --- The principal's role assignments and Graph application permissions -----------------------------------------
    $assignments = @(& $getAll "/roleManagement/directory/roleAssignments?`$filter=principalId eq '$principalId'")
    $graphApp = & $get "/servicePrincipals(appId='00000003-0000-0000-c000-000000000000')?`$select=id,appRoles"
    $graphRoles = @{}
    foreach ($r in @($graphApp['appRoles'])) { if ($r) { $graphRoles[[string]$r['id']] = [string]$r['value'] } }
    $tenantWide = @(& $getAll "/servicePrincipals/$principalId/appRoleAssignments" | Where-Object { [string]$_['resourceId'] -eq [string]$graphApp['id'] -and $graphRoles[[string]$_['appRoleId']] -in 'GroupMember.ReadWrite.All', 'Group.ReadWrite.All', 'Directory.ReadWrite.All' })

    # --- Changes ------------------------------------------------------------------------------------------------------
    $changes = [System.Collections.Generic.List[object]]::new()
    $findings = [System.Collections.Generic.List[object]]::new()
    $change = {
        param([string] $Action, [string] $Resource, [string] $Detail, [string] $Method = '', [string] $Uri = '', $Body = $null)
        $changes.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.ApplicationPermissionChange'; Order = $changes.Count + 1; Action = $Action; Resource = $Resource; Detail = $Detail; Method = $Method; Uri = $Uri; Body = $Body })
    }
    $finding = {
        param([string] $Severity, [string] $Item, [string] $Title, [string] $Detail, [string] $Fix)
        $findings.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.ApplicationPermissionFinding'; Severity = $Severity; Item = $Item; Finding = $Title; Detail = $Detail; Recommendation = $Fix })
    }

    $unitRef = if ($unit) { [string]$unit['id'] } else { '{au}' }
    if ($unit) {
        & $change 'NoChange' "Administrative unit $AdministrativeUnitName" 'Exists.'
        if ($RestrictedManagement -and [string]$unit['isMemberManagementRestricted'] -ne 'True') { & $finding 'Info' $AdministrativeUnitName 'Restricted management not set' 'The unit exists without restricted management, and it can only be chosen when a unit is created.' 'Create a new unit with -RestrictedManagement (a new -AdministrativeUnitName) if tenant-wide group administrators must not change these groups.' }
    }
    else {
        $unitBody = [ordered]@{ displayName = $AdministrativeUnitName; description = "Groups whose members $principalName may manage. Don't add other groups." }
        if ($RestrictedManagement) { $unitBody.isMemberManagementRestricted = $true }
        & $change 'Create' "Administrative unit $AdministrativeUnitName" $(if ($RestrictedManagement) { 'With restricted management: tenant-wide group administrators can''t change its groups.' } else { 'A boundary: a role assigned on it covers only the objects in it.' }) 'Post' "$graph/directory/administrativeUnits" $unitBody
    }
    foreach ($g in $groups) {
        $gid = [string]$g['id']
        $gname = [string]$g['displayName']
        if (@($unitMembers | Where-Object { [string]$_['id'] -eq $gid }).Count) { & $change 'NoChange' "Group $gname in the unit" 'Already a member.' }
        else { & $change 'Add' "Group $gname to the unit" $gid 'Post' "$graph/directory/administrativeUnits/$unitRef/members/`$ref" ([ordered]@{ '@odata.id' = "$graph/groups/$gid" }) }
        if (@($g['groupTypes']) -contains 'DynamicMembership') { & $finding 'Medium' $gname 'Dynamic group' 'Its members come from a rule: no one - the application included - can add or remove them.' 'Leave it out, or manage its membership rule instead.' }
        if ([string]$g['isAssignableToRole'] -eq 'True') { & $finding 'Medium' $gname 'Role-assignable group' 'Only Privileged Role Administrators (and Global Administrators) can change the members of a group that can hold Entra roles - a role on the unit doesn''t.' 'Use a group that is not role-assignable, or manage it with privileged access.' }
    }
    $others = @($unitMembers | Where-Object { $id = [string]$_['id']; -not @($groups | Where-Object { [string]$_['id'] -eq $id }).Count })
    if ($others.Count) { & $finding 'Medium' $AdministrativeUnitName 'Other objects in the unit' "$($others.Count) other object(s) are in the unit - the role covers them too: $(@($others | Select-Object -First 10 | ForEach-Object { $_['displayName'] }) -join ', ')." 'Remove them from the unit, or use a unit of its own for this application.' }

    $roleRef = '{role}'
    if ($role -and [string]$role['isBuiltIn'] -eq 'True') {
        if ($PSBoundParameters.ContainsKey('AllowedResourceAction') -and $wantedActions.Count -and -not (& $sameActions $roleActions $wantedActions)) {
            # A built-in role's actions are what they are; the wanted actions only steer a custom role.
            & $finding 'Info' $RoleName 'Built-in role' 'A built-in role is used as it is - the actions asked for are ignored.' 'Give -RoleName a custom role''s name to choose the actions.'
        }
        $roleRef = [string]$role['id']
        & $change 'NoChange' "Role $RoleName" 'Built-in role.'
    }
    elseif ($role) {
        $roleRef = [string]$role['id']
        if (-not (& $sameActions $roleActions $wantedActions)) { & $change 'Update' "Role $RoleName" "Actions: $($wantedActions -join ', ') (was: $($roleActions -join ', '))." 'Patch' "$graph/roleManagement/directory/roleDefinitions/$roleRef" ([ordered]@{ rolePermissions = @([ordered]@{ allowedResourceActions = $wantedActions }) }) }
        else { & $change 'NoChange' "Role $RoleName" "Actions: $($wantedActions -join ', ')." }
    }
    else {
        & $change 'Create' "Role $RoleName" "Custom role with: $($wantedActions -join ', ')." 'Post' "$graph/roleManagement/directory/roleDefinitions" ([ordered]@{ displayName = $RoleName; description = $RoleDescription; isEnabled = $true; version = '1.0'; rolePermissions = @([ordered]@{ allowedResourceActions = $wantedActions }) })
    }

    $scope = "/administrativeUnits/$unitRef"
    $assigned = if ($unit -and $roleRef -ne '{role}') { @($assignments | Where-Object { [string]$_['roleDefinitionId'] -eq $roleRef -and [string]$_['directoryScopeId'] -eq $scope }).Count -gt 0 } else { $false }
    if ($assigned) { & $change 'NoChange' "Role assignment on $AdministrativeUnitName" "$principalName holds $RoleName on the unit." }
    else { & $change 'Assign' "Role assignment on $AdministrativeUnitName" "$RoleName to $principalName, scoped to the unit (not the tenant)." 'Post' "$graph/roleManagement/directory/roleAssignments" ([ordered]@{ principalId = $principalId; roleDefinitionId = $roleRef; directoryScopeId = $scope }) }
    if ($roleRef -ne '{role}' -and @($assignments | Where-Object { [string]$_['roleDefinitionId'] -eq $roleRef -and [string]$_['directoryScopeId'] -eq '/' }).Count) {
        & $finding 'High' $principalName 'The same role on the whole tenant' "$principalName also holds $RoleName at tenant scope (/) - it covers every group, not only the unit's." 'Remove the tenant-wide assignment (Roles and administrators > the role > Assignments).'
    }

    foreach ($assignment in $tenantWide) {
        $permission = $graphRoles[[string]$assignment['appRoleId']]
        if ($RemoveTenantWidePermission) { & $change 'Remove' "Graph permission $permission" "Tenant-wide - it would override the unit's scope." 'Delete' "$graph/servicePrincipals/$principalId/appRoleAssignments/$($assignment['id'])" }
        else { & $finding 'High' $principalName "Tenant-wide Graph permission $permission" "With $permission the application can change every group's members, whatever the unit - the scoped role adds nothing until it is removed." 'Run again with -RemoveTenantWidePermission, or remove it under the application''s API permissions.' }
    }

    @{
        Principal          = @{ Id = $principalId; AppId = [string]$principal['appId']; DisplayName = $principalName; Type = [string]$principal['servicePrincipalType'] }
        Groups             = @($groups | ForEach-Object { @{ Id = [string]$_['id']; DisplayName = [string]$_['displayName'] } })
        AdministrativeUnit = @{ Id = $(if ($unit) { [string]$unit['id'] } else { '' }); DisplayName = $AdministrativeUnitName }
        Role               = @{ Id = $(if ($roleRef -ne '{role}') { $roleRef } else { '' }); DisplayName = $RoleName; BuiltIn = [bool]($role -and [string]$role['isBuiltIn'] -eq 'True') }
        Actions            = $wantedActions
        Changes            = $changes.ToArray()
        Findings           = $findings.ToArray()
        Writes             = @($changes | Where-Object { $_.Action -ne 'NoChange' }).Count
    }
}
