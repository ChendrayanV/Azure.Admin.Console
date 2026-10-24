<#
    A made-up Contoso tenant for ApplicationPermission.Tests.ps1, answering
    Microsoft Graph as Invoke-AACHttp would - and keeping what is written,
    so a plan after an apply sees it (as Graph would).

      My-Enterprise-App      an enterprise application holding the
                             tenant-wide GroupMember.ReadWrite.All
      func-twins             two service principals with this name
      SG-Group-One, SG-Group-Two   security groups
      SG-Dynamic             a dynamic group
      Groups Administrator   a built-in role
#>
function Get-AACContosoApplicationPermission {
    $sp = 'aaaaaaaa-0000-0000-0000-0000000000a1'
    @{
        Writes                = [System.Collections.Generic.List[object]]::new()
        Next                  = 100
        ServicePrincipals     = @(
            @{ id = $sp; appId = 'bbbbbbbb-0000-0000-0000-0000000000b1'; displayName = 'My-Enterprise-App'; servicePrincipalType = 'Application' }
            @{ id = 'aaaaaaaa-0000-0000-0000-0000000000a2'; appId = 'bbbbbbbb-0000-0000-0000-0000000000b2'; displayName = 'func-twins'; servicePrincipalType = 'ManagedIdentity' }
            @{ id = 'aaaaaaaa-0000-0000-0000-0000000000a3'; appId = 'bbbbbbbb-0000-0000-0000-0000000000b3'; displayName = 'func-twins'; servicePrincipalType = 'ManagedIdentity' }
        )
        Graph                 = @{ id = 'gggggggg-0000-0000-0000-000000000001'; appRoles = @(@{ id = 'rrrrrrrr-0000-0000-0000-000000000001'; value = 'GroupMember.ReadWrite.All' }, @{ id = 'rrrrrrrr-0000-0000-0000-000000000002'; value = 'User.Read.All' }) }
        AppRoleAssignments    = [System.Collections.Generic.List[object]]@(
            @{ id = 'assignment-1'; principalId = $sp; resourceId = 'gggggggg-0000-0000-0000-000000000001'; appRoleId = 'rrrrrrrr-0000-0000-0000-000000000001' }
            @{ id = 'assignment-2'; principalId = $sp; resourceId = 'gggggggg-0000-0000-0000-000000000001'; appRoleId = 'rrrrrrrr-0000-0000-0000-000000000002' }
        )
        Groups                = @(
            @{ id = 'cccccccc-0000-0000-0000-000000000001'; displayName = 'SG-Group-One'; securityEnabled = $true; mailEnabled = $false; groupTypes = @(); isAssignableToRole = $false }
            @{ id = 'cccccccc-0000-0000-0000-000000000002'; displayName = 'SG-Group-Two'; securityEnabled = $true; mailEnabled = $false; groupTypes = @(); isAssignableToRole = $false }
            @{ id = 'cccccccc-0000-0000-0000-000000000003'; displayName = 'SG-Dynamic'; securityEnabled = $true; mailEnabled = $false; groupTypes = @('DynamicMembership'); isAssignableToRole = $false }
        )
        AdministrativeUnits   = [System.Collections.Generic.List[object]]::new()
        UnitMembers           = @{}
        RoleDefinitions       = [System.Collections.Generic.List[object]]@(
            @{ id = 'fdd7a751-b60b-444a-984c-02652fe8fa1c'; displayName = 'Groups Administrator'; isBuiltIn = $true; rolePermissions = @(@{ allowedResourceActions = @('microsoft.directory/groups/allProperties/allTasks') }) }
        )
        RoleAssignments       = [System.Collections.Generic.List[object]]::new()
    }
}

# Microsoft Graph, as Invoke-AACHttp returns it: @{ Status; Content; Headers } - or throws as it does.
function Invoke-AACContosoEntraGraph {
    param([hashtable] $State, [string] $Method = 'Get', [string] $Uri, [string] $Body)
    if (-not $Method) { $Method = 'Get' }
    $graph = 'https://graph.microsoft.com/v1.0'
    $answer = { param($Object, [int] $Status = 200) @{ Status = $Status; Content = $(if ($null -ne $Object) { ConvertTo-Json -InputObject $Object -Depth 20 -Compress } else { '' }); Headers = @{} } }
    $list = { param([object[]] $Items) & $answer @{ value = @($Items | Where-Object { $_ }) } }
    $missing = { $e = [System.Exception]::new('Resource does not exist.'); $e.Data['StatusCode'] = 404; throw $e }
    $path = [System.Uri]::UnescapeDataString(($Uri -split '\?', 2)[0]).Replace($graph, '')
    $query = if ($Uri.Contains('?')) { [System.Uri]::UnescapeDataString(($Uri -split '\?', 2)[1]) } else { '' }
    $named = if ($query -match "displayName eq '((?:[^']|'')*)'") { $Matches[1].Replace("''", "'") } else { $null }
    $data = if ($Body) { ConvertFrom-Json -InputObject $Body -AsHashtable } else { $null }
    if ($Method -ne 'Get') { $State.Writes.Add([pscustomobject]@{ Method = $Method; Path = $path; Body = $data }) }
    $newId = { $State.Next++; "eeeeeeee-0000-0000-0000-$('{0:D12}' -f $State.Next)" }

    switch -Regex ($path) {
        "^/servicePrincipals\(appId='00000003-0000-0000-c000-000000000000'\)$" { return & $answer $State.Graph }
        "^/servicePrincipals\(appId='([^']+)'\)$" { $sp = @($State.ServicePrincipals | Where-Object { $_.appId -eq $Matches[1] }) | Select-Object -First 1; if ($sp) { return & $answer $sp }; & $missing }
        '^/servicePrincipals$' { return & $list @($State.ServicePrincipals | Where-Object { $_.displayName -eq $named }) }
        '^/servicePrincipals/([^/]+)/appRoleAssignments$' { $id = $Matches[1]; return & $list @($State.AppRoleAssignments | Where-Object { $_.principalId -eq $id }) }
        '^/servicePrincipals/([^/]+)/appRoleAssignments/([^/]+)$' { $id = $Matches[2]; $a = @($State.AppRoleAssignments | Where-Object { $_.id -eq $id }) | Select-Object -First 1; if (-not $a) { & $missing }; $null = $State.AppRoleAssignments.Remove($a); return & $answer $null 204 }
        '^/servicePrincipals/([^/]+)$' { $id = $Matches[1]; $sp = @($State.ServicePrincipals | Where-Object { $_.id -eq $id }) | Select-Object -First 1; if ($sp) { return & $answer $sp }; & $missing }
        '^/groups$' { return & $list @($State.Groups | Where-Object { $_.displayName -eq $named }) }
        '^/groups/([^/]+)$' { $id = $Matches[1]; $g = @($State.Groups | Where-Object { $_.id -eq $id }) | Select-Object -First 1; if ($g) { return & $answer $g }; & $missing }
        '^/directory/administrativeUnits$' {
            if ($Method -eq 'Post') { $unit = @{ id = (& $newId); displayName = $data.displayName; description = $data.description; isMemberManagementRestricted = [bool]$data['isMemberManagementRestricted'] }; $State.AdministrativeUnits.Add($unit); $State.UnitMembers[$unit.id] = [System.Collections.Generic.List[object]]::new(); return & $answer $unit 201 }
            return & $list @($State.AdministrativeUnits | Where-Object { $_.displayName -eq $named })
        }
        '^/directory/administrativeUnits/([^/]+)/members/\$ref$' {
            $id = $Matches[1]; if (-not $State.UnitMembers.Contains($id)) { & $missing }
            $member = ([string]$data['@odata.id']).Split('/')[-1]
            $State.UnitMembers[$id].Add(@(@($State.Groups) | Where-Object { $_.id -eq $member })[0]); return & $answer $null 204
        }
        '^/directory/administrativeUnits/([^/]+)/members$' { $id = $Matches[1]; return & $list @($State.UnitMembers[$id]) }
        '^/roleManagement/directory/roleDefinitions$' {
            if ($Method -eq 'Post') { $role = @{ id = (& $newId); displayName = $data.displayName; description = $data.description; isBuiltIn = $false; isEnabled = $true; rolePermissions = $data.rolePermissions }; $State.RoleDefinitions.Add($role); return & $answer $role 201 }
            return & $list @($State.RoleDefinitions | Where-Object { $_.displayName -eq $named })
        }
        '^/roleManagement/directory/roleDefinitions/([^/]+)$' { $id = $Matches[1]; $role = @($State.RoleDefinitions | Where-Object { $_.id -eq $id })[0]; $role.rolePermissions = $data.rolePermissions; return & $answer $null 204 }
        '^/roleManagement/directory/roleAssignments$' {
            if ($Method -eq 'Post') { $a = @{ id = (& $newId); principalId = $data.principalId; roleDefinitionId = $data.roleDefinitionId; directoryScopeId = $data.directoryScopeId }; $State.RoleAssignments.Add($a); return & $answer $a 201 }
            $principal = if ($query -match "principalId eq '([^']+)'") { $Matches[1] } else { '' }
            return & $list @($State.RoleAssignments | Where-Object { $_.principalId -eq $principal })
        }
    }
    throw "The Contoso Graph fake has no answer for $Method $Uri"
}
