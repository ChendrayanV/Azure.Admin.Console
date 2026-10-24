function Read-AACApplicationPermission {
    <#
    .SYNOPSIS
        Reads everything that gives one service principal (an enterprise
        application, or a system- or user-assigned managed identity) rights:
        API permissions, consented delegated permissions, directory roles
        (active and eligible, direct and through groups), objects it owns,
        and - unless -SkipAzure - its Azure role assignments.
    .DESCRIPTION
        -Identity is any of:
          - the service principal's object ID
          - the application (client) ID
          - an app registration's object ID
          - a display name (two with that name stop with both IDs)
          - an Azure resource ID: a user-assigned identity
            (.../userAssignedIdentities/<name>), or a resource with a
            system-assigned identity (a Function App, a VM...)

        Microsoft Graph, a few requests at a time (Read-AACGraphQuery):
          1. the service principal (and its app registration, when it is
             in this tenant: the API permissions it asks for)
          2. its app role assignments (application permissions), its
             delegated permission grants, its directory role assignments
             and eligibilities (with the role definitions), the groups it
             is in (transitively) and the objects it owns
          3. the APIs those permissions belong to (their role and scope
             names), the roles of the role-assignable groups it is in, and
             the administrative units and other objects the roles are
             scoped to
        Then Get-AACAzureRoleAssignment for the principal and its groups.

        A part that can't be read (no permission, no PIM licence) is in
        Errors; the rest carries on. Returns @{ Principal; Application;
        AppRoleAssignments; Grants; RoleAssignments; Eligible;
        GroupRoleAssignments; MemberOf; Owned; Resources (by service
        principal ID and by app ID); ScopeNames; UnitMembers; Azure;
        Errors }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $Identity,

        [switch] $SkipAzure
    )

    $graph = 'https://graph.microsoft.com/v1.0'
    $isGuid = { param([string] $Text) $Text -match '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$' }
    $quote = { param([string] $Text) [System.Uri]::EscapeDataString($Text.Replace("'", "''")) }
    $spSelect = '$select=id,appId,displayName,servicePrincipalType,appOwnerOrganizationId,accountEnabled,alternativeNames'
    $errors = [System.Collections.Generic.List[string]]::new()
    $stop = {
        param([string] $Message, [string] $Hint)
        $problem = [System.InvalidOperationException]::new($Message)
        if ($Hint) { $problem.Data['AACHint'] = $Hint }
        throw $problem
    }
    $listOf = { param($Value) @(if ($Value -is [System.Collections.IList]) { $Value | Where-Object { $_ } } elseif ($Value) { $Value }) }

    # --- 1. The principal ------------------------------------------------------------------------------------------------
    $principal = $null
    if ($Identity -match '^/subscriptions/') {
        # An Azure resource: a user-assigned identity's principal ID, or a resource's system-assigned one.
        # Through Resource Graph: one query whatever the resource type (each has its own api-version).
        $found = Invoke-AACGraphBatch -Query ([ordered]@{ identity = @{ Tenant = $true; Query = "resources | where id =~ $(ConvertTo-AACKqlLiteral -Text $Identity.TrimEnd('/')) | project principalId = iff(isnotempty(tostring(properties.principalId)), tostring(properties.principalId), tostring(identity.principalId))" } })
        $objectId = [string](@($found.Rows['identity'] | Where-Object { $_ }) | Select-Object -First 1 | ForEach-Object { $_['principalId'] })
        if (-not $objectId) { & $stop "Azure Admin Console found no managed identity on $Identity." 'Give a user-assigned identity, or a resource with its system-assigned identity turned on.' }
        $Identity = $objectId
    }
    if (& $isGuid $Identity) {
        $first = Read-AACGraphQuery -Query ([ordered]@{
                sp          = "$graph/servicePrincipals/$Identity`?$spSelect"
                byAppId     = "$graph/servicePrincipals(appId='$Identity')?$spSelect"
                application = "$graph/applications/$Identity`?`$select=appId"
            })
        $principal = if ($first.Data.Contains('sp')) { $first.Data['sp'] } elseif ($first.Data.Contains('byAppId')) { $first.Data['byAppId'] } else { $null }
        if (-not $principal -and $first.Data.Contains('application')) {
            $appId = [string]$first.Data['application']['appId']
            $again = Read-AACGraphQuery -Query ([ordered]@{ sp = "$graph/servicePrincipals(appId='$appId')?$spSelect" })
            if ($again.Data.Contains('sp')) { $principal = $again.Data['sp'] }
            else { & $stop "Azure Admin Console found the app registration $Identity, but no service principal for it in this tenant." 'An app registration has no permissions of its own until it has an enterprise application (service principal): grant admin consent, or create it in Enterprise applications.' }
        }
        if (-not $principal) { & $stop "Azure Admin Console found no service principal, application or app registration with the ID $Identity." "Check the ID - Microsoft Graph said: $(@($first.Errors.Values) | Select-Object -First 1)" }
    }
    else {
        $byName = Read-AACGraphQuery -Query ([ordered]@{ sp = "$graph/servicePrincipals?`$filter=displayName eq '$(& $quote $Identity)'&$spSelect" })
        if ($byName.Errors.Count) { & $stop "Azure Admin Console couldn't look up '$Identity' in Microsoft Graph: $(@($byName.Errors.Values)[0])" 'Sign in with Connect-AAC as someone who can read applications (Directory Readers is enough).' }
        $found = @(& $listOf $byName.Data['sp'])
        if (-not $found.Count) { & $stop "Azure Admin Console found no enterprise application or managed identity named '$Identity'." 'Check the name under Enterprise applications - for a system-assigned managed identity it is the Azure resource''s name - or give its ID.' }
        if ($found.Count -gt 1) { & $stop "Azure Admin Console found $($found.Count) service principals named '$Identity': $(@($found | ForEach-Object { "$($_['id']) ($($_['servicePrincipalType']))" }) -join ', ')." 'Give the object ID of the one you mean.' }
        $principal = $found[0]
    }
    $id = [string]$principal['id']

    # --- 2. What it holds ------------------------------------------------------------------------------------------------
    $second = Read-AACGraphQuery -Query ([ordered]@{
            appRoles    = "$graph/servicePrincipals/$id/appRoleAssignments"
            grants      = "$graph/oauth2PermissionGrants?`$filter=clientId eq '$id'"
            roles       = "$graph/roleManagement/directory/roleAssignments?`$filter=principalId eq '$id'&`$expand=roleDefinition"
            eligible    = "$graph/roleManagement/directory/roleEligibilitySchedules?`$filter=principalId eq '$id'&`$expand=roleDefinition"
            memberOf    = "$graph/servicePrincipals/$id/transitiveMemberOf?`$select=id,displayName,isAssignableToRole"
            owned       = "$graph/servicePrincipals/$id/ownedObjects?`$select=id,displayName"
            application = "$graph/applications(appId='$($principal['appId'])')?`$select=id,displayName,requiredResourceAccess"
        })
    foreach ($name in $second.Errors.Keys) {
        # An application from another tenant (or a managed identity) has no app registration here: no error.
        if ($name -eq 'application') { continue }
        $reason = [string]$second.Errors[$name]
        if ($name -eq 'eligible' -and $reason -match 'PermissionScopeNotGranted|missing permission scope|RoleEligibilitySchedule') {
            # The Azure CLI client Connect-AAC signs in with by default can't get this Graph scope: say how, not the raw error.
            $errors.Add("PIM-eligible directory roles weren't read: the sign-in's Microsoft Graph token has no RoleManagement.Read.Directory (or RoleEligibilitySchedule.Read.Directory) - the client Connect-AAC uses by default can't get it. Active role assignments are listed. To include eligible ones, Connect-AAC -ClientId <an app registration with that delegated permission, admin-consented>, or sign in as a service principal holding it.")
        }
        elseif ($name -eq 'eligible' -and $reason -match 'P2|license|licence|AadPremiumLicenseRequired') {
            $errors.Add("PIM-eligible directory roles weren't read: the tenant has no Microsoft Entra ID P2 (or Governance) licence for PIM - so there are none to list.")
        }
        else { $errors.Add("couldn't read $(@{ appRoles = 'its application permissions'; grants = 'its delegated permission grants'; roles = 'its directory role assignments'; eligible = 'its PIM-eligible directory roles'; memberOf = 'its group memberships'; owned = 'the objects it owns' }[$name]) - $reason") }
    }
    $data = $second.Data
    $appRoleAssignments = @(& $listOf $data['appRoles'])
    $grants = @(& $listOf $data['grants'])
    $roleAssignments = @(& $listOf $data['roles'])
    $eligible = @(& $listOf $data['eligible'])
    $memberOf = @(& $listOf $data['memberOf'] | Where-Object { [string]$_['@odata.type'] -eq '#microsoft.graph.group' })
    $owned = @(& $listOf $data['owned'])
    $application = if ($data.Contains('application')) { $data['application'] } else { $null }

    # --- 3. Names: the APIs, the groups' roles, the scopes --------------------------------------------------------------
    $third = [ordered]@{}
    $resourceIds = @(@($appRoleAssignments | ForEach-Object { [string]$_['resourceId'] }) + @($grants | ForEach-Object { [string]$_['resourceId'] }) | Where-Object { $_ } | Select-Object -Unique)
    foreach ($rid in $resourceIds) { $third["rsp|$rid"] = "$graph/servicePrincipals/$rid`?`$select=id,appId,displayName,appRoles,oauth2PermissionScopes" }
    $requestedApps = @(if ($application) { & $listOf $application['requiredResourceAccess'] | ForEach-Object { [string]$_['resourceAppId'] } | Where-Object { $_ } | Select-Object -Unique })
    foreach ($appId in $requestedApps) { $third["rapp|$appId"] = "$graph/servicePrincipals(appId='$appId')?`$select=id,appId,displayName,appRoles,oauth2PermissionScopes" }
    foreach ($g in @($memberOf | Where-Object { [string]$_['isAssignableToRole'] -eq 'True' })) { $third["grole|$($g['id'])"] = "$graph/roleManagement/directory/roleAssignments?`$filter=principalId eq '$($g['id'])'&`$expand=roleDefinition" }
    $units = @(@($roleAssignments) + @($eligible) | ForEach-Object { [string]$_['directoryScopeId'] } | Where-Object { $_ -match '^/administrativeUnits/(.+)$' } | ForEach-Object { $_.Substring(21) } | Select-Object -Unique)
    foreach ($unit in $units) { $third["au|$unit"] = "$graph/directory/administrativeUnits/$unit`?`$select=id,displayName"; $third["aum|$unit"] = "$graph/directory/administrativeUnits/$unit/members?`$select=id,displayName" }
    $answers = if ($third.Count) { Read-AACGraphQuery -Query $third } else { @{ Data = @{}; Errors = @{} } }
    foreach ($name in $answers.Errors.Keys) { if ($name -notlike 'rapp|*') { $errors.Add("couldn't read $(switch -Wildcard ($name) { 'rsp|*' { "the API $($name.Substring(4))" } 'grole|*' { "the roles of group $($name.Substring(6))" } 'aum|*' { "the members of administrative unit $($name.Substring(4))" } default { "administrative unit $($name.Substring(3))" } }) - $($answers.Errors[$name])") } }
    $resources = @{}
    foreach ($key in @($answers.Data.Keys | Where-Object { $_ -like 'rsp|*' -or $_ -like 'rapp|*' })) {
        $r = $answers.Data[$key]
        if ($r) { $resources[([string]$r['id']).ToLowerInvariant()] = $r; $resources["app|$(([string]$r['appId']).ToLowerInvariant())"] = $r }
    }
    $groupRoles = @{}
    foreach ($key in @($answers.Data.Keys | Where-Object { $_ -like 'grole|*' })) { $groupRoles[$key.Substring(6)] = @(& $listOf $answers.Data[$key]) }
    $scopeNames = @{}
    $unitMembers = @{}
    foreach ($unit in $units) {
        if ($answers.Data.Contains("au|$unit")) { $scopeNames["/administrativeUnits/$unit"] = "administrative unit $($answers.Data["au|$unit"]['displayName'])" }
        $unitMembers["/administrativeUnits/$unit"] = @(& $listOf $(if ($answers.Data.Contains("aum|$unit")) { $answers.Data["aum|$unit"] }) | ForEach-Object { [string]$_['displayName'] })
    }
    # A role scoped to one object (an application, a group): its name and type.
    $objectScopes = @(@($roleAssignments) + @($eligible) + @($groupRoles.Values | ForEach-Object { $_ }) | ForEach-Object { [string]$_['directoryScopeId'] } | Where-Object { $_ -match '^/[0-9a-fA-F-]{36}$' } | ForEach-Object { $_.Substring(1) } | Select-Object -Unique)
    $ownedIds = @($owned | ForEach-Object { [string]$_['id'] })
    $objects = if (@($objectScopes + $ownedIds).Count) { Get-AACDirectoryObject -Id @($objectScopes + $ownedIds) } else { @{ Objects = @{}; Error = '' } }
    foreach ($objectId in $objectScopes) {
        $o = $objects.Objects[$objectId.ToLowerInvariant()]
        $scopeNames["/$objectId"] = if ($o) { "$(([string]$o['@odata.type']) -replace '^#microsoft\.graph\.', '') $($o['displayName'])" } else { "object $objectId" }
    }

    # --- 4. Azure ----------------------------------------------------------------------------------------------------------
    $azure = @{ Assignments = @{}; Errors = @() }
    if (-not $SkipAzure) {
        try { $azure = Get-AACAzureRoleAssignment -PrincipalId (@($id) + @($memberOf | ForEach-Object { [string]$_['id'] })) }
        catch { $azure = @{ Assignments = @{}; Errors = @("Azure role assignments - $($_.Exception.Message)") } }
        foreach ($problem in $azure.Errors) { $errors.Add("couldn't read $problem (use -SkipAzure to leave Azure out)") }
    }

    @{
        Principal            = $principal
        Application          = $application
        AppRoleAssignments   = $appRoleAssignments
        Grants               = $grants
        RoleAssignments      = $roleAssignments
        Eligible             = $eligible
        GroupRoleAssignments = $groupRoles
        MemberOf             = $memberOf
        Owned                = @($owned | ForEach-Object { $o = $objects.Objects[([string]$_['id']).ToLowerInvariant()]; if ($o) { $o } else { $_ } })
        Resources            = $resources
        ScopeNames           = $scopeNames
        UnitMembers          = $unitMembers
        Azure                = $azure.Assignments
        Errors               = $errors.ToArray()
    }
}
