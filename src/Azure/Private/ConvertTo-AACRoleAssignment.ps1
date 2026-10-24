function ConvertTo-AACRoleAssignment {
    <#
    .SYNOPSIS
        Builds Get-AACRoleAssignment's inventory (AAC.RoleAssignment and
        AAC.CustomRole) from the Resource Graph rows of
        Get-AACRoleAssignmentQuery, the PIM schedule instances, the Entra ID
        principals and the groups' members.
    .DESCRIPTION
        No Azure calls.
          -Read       Invoke-AACGraphBatch's result
          -Scope      Resolve-AACScope's (an empty GraphScope means
                      everything the account can see)
          -Pim        @{ Eligible; Instances; Read (bool); Errors } - the
                      subscriptions' roleEligibilityScheduleInstances and
                      roleAssignmentScheduleInstances
          -Directory  Get-AACDirectoryObject's result for the principals
                      and creators ($null: Entra ID not read)
          -Members    group ID -> @{ Count; Names } (transitive), or
                      @{ Error }; $null: not expanded
        An assignment is in scope when it is on a subscription in scope (or
        below it), on a management group above one, or at the root.

        Each assignment (AAC.RoleAssignment) has the principal and what it
        is - user, guest, group, application (or another tenant's), system-
        or user-assigned managed identity, or deleted - the role, whether
        it is built-in or custom, privileged, and able to write role
        assignments; the scope, its type and how many subscriptions it
        reaches; whether it is permanent, activated or eligible in PIM; the
        group's members; who created it and when; and its findings:
          High    a deleted principal with a privileged role; a guest with
                  a privileged role; an application or managed identity as
                  Owner on a subscription or above; a custom role
                  equivalent to Owner
          Medium  a deleted principal or role; Owner or User Access
                  Administrator given to a user directly (not a group); an
                  application as Owner on a resource group or resource
          Low     standing privileged access a person could hold eligible
                  in PIM
        Custom roles (AAC.CustomRole): their assignments, whether a policy
        uses them, unused, equivalent to Owner, able to write role
        assignments, assignable scopes.
        Returns @{ Assignments; CustomRoles; Notices; Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Read,

        [Parameter(Mandatory)]
        [hashtable] $Scope,

        [hashtable] $Pim,

        [hashtable] $Directory,

        [hashtable] $Members,

        [string] $TenantId = ''
    )

    $get = ${function:Get-AACMember}
    $text = { param($Object, [string] $Path) $v = & $get $Object $Path; if ($null -eq $v) { '' } else { [string]$v } }
    $list = { param($Item) @(if ($Item -is [System.Collections.IEnumerable] -and $Item -isnot [string] -and $Item -isnot [System.Collections.IDictionary]) { $Item } elseif ($null -ne $Item) { , $Item }) | Where-Object { $null -ne $_ -and '' -ne $_ } }
    $rowsOf = { param([string] $Name) @(if ($Read.Rows -and $Read.Rows.Contains($Name)) { $Read.Rows[$Name] | Where-Object { $null -ne $_ } }) }
    $leaf = { param([string] $Id) ($Id -split '/')[-1].ToLowerInvariant() }
    $date = {
        param([string] $Value)
        $d = [datetime]::MinValue
        if ($Value -and [datetime]::TryParse($Value, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$d)) { $d } else { $null }
    }
    $notices = [System.Collections.Generic.List[string]]::new()
    $what = @{ roleAssignments = 'role assignments'; roleDefinitions = 'role definitions'; managementGroups = 'management groups'; userIdentities = 'user-assigned identities'; policyRoles = 'roles policies use' }
    foreach ($key in @($Read.Errors.Keys | Sort-Object)) { $notices.Add("The $(if ($what.Contains($key)) { $what[$key] } else { $key }) couldn't be read: $($Read.Errors[$key] -replace '\s+', ' ')") }

    # --- Roles: what each can do ------------------------------------------------------------------------------------------------
    $builtInPrivileged = @{ '8e3af657-a8ff-443c-a75c-2fe8c4bcb635' = 'Owner'; 'b24988ac-6180-42a0-ab88-20f7382dd24c' = 'Contributor'; '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9' = 'User Access Administrator'; 'f58310d9-a9f6-439a-9e8d-f62e7b41a168' = 'Role Based Access Control Administrator' }
    $grantsAccess = @('18d7d88d-d35e-4fb5-a5c3-7773c20a72d9', '8e3af657-a8ff-443c-a75c-2fe8c4bcb635')
    $allows = {
        param($Permissions, [string] $Action)
        foreach ($block in @(& $list $Permissions)) {
            $yes = @(@(& $list (& $get $block 'actions')) | Where-Object { $Action -like [string]$_ }).Count
            $no = @(@(& $list (& $get $block 'notActions')) | Where-Object { $Action -like [string]$_ }).Count
            if ($yes -and -not $no) { return $true }
        }
        $false
    }
    $roles = @{}
    foreach ($row in (& $rowsOf 'roleDefinitions')) {
        $guid = & $text $row 'name'
        if (-not $guid) { $guid = & $leaf (& $text $row 'id') }
        $permissions = & $get $row 'permissions'
        $wildcard = @(@(& $list $permissions) | ForEach-Object { @(& $list (& $get $_ 'actions')) } | Where-Object { [string]$_ -eq '*' }).Count -gt 0
        $canWrite = & $allows $permissions 'Microsoft.Authorization/roleAssignments/write'
        $custom = (& $text $row 'roleType') -eq 'CustomRole'
        $roles[$guid] = @{
            Name            = & $text $row 'roleName'
            Custom          = $custom
            CanWrite        = $canWrite
            OwnerEquivalent = $custom -and $wildcard -and $canWrite
            Privileged      = $builtInPrivileged.Contains($guid) -or $canWrite -or ($custom -and $wildcard)
            Scopes          = @(& $list (& $get $row 'assignableScopes'))
            Actions         = @(@(& $list $permissions) | ForEach-Object { @(& $list (& $get $_ 'actions')) }).Count
            Id              = & $text $row 'id'
        }
    }

    # --- Scope: subscriptions, management groups ---------------------------------------------------------------------------------
    $inScope = @{}
    $groupSubs = @{}
    foreach ($s in @($Scope.Subscriptions)) {
        $id = ([string]$s['subscriptionId']).ToLowerInvariant()
        $inScope[$id] = $true
        foreach ($m in @($s['chain'])) {
            if ($m -isnot [System.Collections.IDictionary]) { continue }
            $g = ([string]$m['name']).ToLowerInvariant()
            if (-not $groupSubs.Contains($g)) { $groupSubs[$g] = 0 }
            $groupSubs[$g]++
        }
    }
    $unscoped = -not @($Scope['GraphScope'] | Where-Object { $_ }).Count
    $groupName = @{}
    foreach ($row in (& $rowsOf 'managementGroups')) { $groupName[(& $text $row 'name')] = $(if (& $text $row 'displayName') { & $text $row 'displayName' } else { & $text $row 'name' }) }
    $subName = { param([string] $Id) if ($Scope.Names -and $Scope.Names.Contains($Id)) { $Scope.Names[$Id] } else { $Id } }
    $describe = {
        param([string] $ScopeId)
        $s = $ScopeId.ToLowerInvariant()
        if ($s -eq '/') { return @{ Type = 'Root'; Name = 'Root (/)'; In = $true; Subscription = ''; Reach = "Inherited by $(@($Scope.Subscriptions).Count) subscription(s)" } }
        if ($s -match '^/providers/microsoft\.management/managementgroups/([^/]+)$') {
            $g = $Matches[1]
            $n = if ($groupSubs.Contains($g)) { $groupSubs[$g] } else { 0 }
            return @{ Type = 'Management group'; Name = $(if ($groupName.Contains($g)) { $groupName[$g] } else { $g }); In = ($unscoped -or $n -gt 0); Subscription = ''; Reach = "Inherited by $n subscription(s)" }
        }
        if ($s -match '^/subscriptions/([^/]+)(/resourcegroups/([^/]+))?(/providers/.+/([^/]+))?$') {
            $sub = $Matches[1]
            $type = if ($Matches[5]) { 'Resource' } elseif ($Matches[3]) { 'Resource group' } else { 'Subscription' }
            $name = switch ($type) { 'Resource' { "$($Matches[5]) ($($Matches[3]))" } 'Resource group' { "$($Matches[3]) ($(& $subName $sub))" } default { & $subName $sub } }
            return @{ Type = $type; Name = $name; In = $inScope.Contains($sub); Subscription = (& $subName $sub); Reach = 'Direct' }
        }
        @{ Type = 'Other'; Name = $ScopeId; In = $false; Subscription = ''; Reach = '' }
    }

    # --- Principals -------------------------------------------------------------------------------------------------------------
    $userAssigned = @{}
    foreach ($row in (& $rowsOf 'userIdentities')) { $p = & $text $row 'principalId'; if ($p) { $userAssigned[$p] = $true } }
    $entraRead = $null -ne $Directory -and -not $Directory.Error
    if ($null -ne $Directory -and $Directory.Error) { $notices.Add("The principals couldn't be looked up in Entra ID ($($Directory.Error)): they are shown by ID, and deleted ones can't be told apart.") }
    $principal = {
        param([string] $Id, [string] $ArmType)
        $o = if ($entraRead -and $Directory.Objects.Contains($Id)) { $Directory.Objects[$Id] } else { $null }
        if ($o) {
            # '@odata.type' has a dot in its name: read it directly, not as a path.
            $odata = [string]$(if ($o -is [System.Collections.IDictionary] -and $o.Contains('@odata.type')) { $o['@odata.type'] })
            $name = if (& $text $o 'displayName') { & $text $o 'displayName' } else { $Id }
            $upn = & $text $o 'userPrincipalName'
            if ($odata -like '*user') { return @{ Type = $(if ((& $text $o 'userType') -eq 'Guest') { 'Guest' } else { 'User' }); Name = $name; Upn = $upn; Kind = 'User' } }
            if ($odata -like '*group') { return @{ Type = 'Group'; Name = $name; Upn = ''; Kind = 'Group' } }
            if ((& $text $o 'servicePrincipalType') -eq 'ManagedIdentity') { return @{ Type = $(if ($userAssigned.Contains($Id)) { 'Managed identity (user-assigned)' } else { 'Managed identity (system-assigned)' }); Name = $name; Upn = ''; Kind = 'Workload' } }
            $owner = & $text $o 'appOwnerOrganizationId'
            return @{ Type = $(if ($TenantId -and $owner -and $owner -ne $TenantId) { 'Application (external)' } else { 'Application' }); Name = $name; Upn = ''; Kind = 'Workload' }
        }
        if ($entraRead) { return @{ Type = 'Deleted'; Name = "Identity not found ($(if ($ArmType) { $ArmType } else { 'unknown type' }))"; Upn = ''; Kind = 'Deleted' } }
        $kind = switch ($ArmType) { 'User' { 'User' } 'Group' { 'Group' } 'ForeignGroup' { 'Group' } 'ServicePrincipal' { 'Workload' } default { 'Unknown' } }
        @{ Type = $(switch ($ArmType) { 'ServicePrincipal' { 'Service principal' } 'ForeignGroup' { 'Group (foreign)' } '' { 'Unknown' } default { $ArmType } }); Name = $Id; Upn = ''; Kind = $kind }
    }
    $nameOf = { param([string] $Id) if (-not $Id) { '' } elseif ($entraRead -and $Directory.Objects.Contains($Id)) { $o = $Directory.Objects[$Id]; $(if (& $text $o 'userPrincipalName') { & $text $o 'userPrincipalName' } else { & $text $o 'displayName' }) } else { $Id } }

    # --- PIM: activated and eligible ------------------------------------------------------------------------------------------------
    $pimRead = $null -ne $Pim -and $Pim['Read']
    $activated = @{}
    foreach ($i in @(if ($Pim) { & $list $Pim['Instances'] })) {
        $p = & $get $i 'properties'
        if ((& $text $p 'assignmentType') -eq 'Activated') { $origin = & $text $p 'originRoleAssignmentId'; if ($origin) { $activated[$origin.ToLowerInvariant()] = $true; $activated[(& $leaf $origin)] = $true } }
    }
    if ($Pim -and $Pim['Errors']) { foreach ($e in @(& $list $Pim['Errors'])) { $notices.Add("PIM couldn't be read for $e") } }

    # --- The assignments ----------------------------------------------------------------------------------------------------------
    $usage = @{}
    $rank = (Get-AACSeverityRank).Rank
    $assignments = [System.Collections.Generic.List[object]]::new()
    $build = {
        param([string] $AssignmentKind, [string] $PrincipalId, [string] $ArmType, [string] $RoleId, [string] $ScopeId, [hashtable] $More)
        $d = & $describe $ScopeId
        if (-not $d.In) { return }
        $guid = & $leaf $RoleId
        $role = if ($roles.Contains($guid)) { $roles[$guid] } else { $null }
        $who = & $principal $PrincipalId $ArmType
        $findings = [System.Collections.Generic.List[object]]::new()
        $privileged = $role -and $role.Privileged
        $ownerLike = $role -and ($guid -eq '8e3af657-a8ff-443c-a75c-2fe8c4bcb635' -or $role.OwnerEquivalent)
        $high = $d.Type -in 'Root', 'Management group', 'Subscription'
        if ($who.Kind -eq 'Deleted') { $findings.Add(@{ S = $(if ($privileged) { 'High' } else { 'Medium' }); T = 'Orphaned: the principal no longer exists in Entra ID - remove the assignment.' }) }
        if (-not $role -and (& $rowsOf 'roleDefinitions').Count) { $findings.Add(@{ S = 'Medium'; T = 'Orphaned: the role definition no longer exists - remove the assignment.' }) }
        if ($who.Type -eq 'Guest' -and $privileged) { $findings.Add(@{ S = 'High'; T = "A guest holds $($role.Name) - external accounts with privileged access are a common way in." }) }
        if ($who.Kind -eq 'Workload' -and $ownerLike) { $findings.Add(@{ S = $(if ($high) { 'High' } else { 'Medium' }); T = "An application or managed identity is $($role.Name) on a $($d.Type.ToLowerInvariant()) - it can give itself and others any access; use a narrower role." }) }
        if ($role -and $role.OwnerEquivalent) { $findings.Add(@{ S = 'High'; T = "The custom role $($role.Name) is equivalent to Owner (every action, including writing role assignments)." }) }
        if ($who.Kind -eq 'User' -and $grantsAccess -contains $guid -and $AssignmentKind -ne 'Eligible (PIM)') { $findings.Add(@{ S = 'Medium'; T = "$($role.Name) given to a user directly - give it to a group, so access is reviewed in one place." }) }
        if ($pimRead -and $who.Kind -eq 'User' -and $privileged -and $AssignmentKind -eq 'Permanent') { $findings.Add(@{ S = 'Low'; T = 'Standing privileged access: make it eligible in PIM, activated when needed.' }) }
        $worst = @($findings | Sort-Object { $rank[$_.S] } | Select-Object -First 1)
        $member = if ($null -ne $Members -and $who.Kind -eq 'Group' -and $Members.Contains($PrincipalId)) { $Members[$PrincipalId] } else { $null }
        $item = [pscustomobject][ordered]@{
            Severity                = $(if ($worst.Count) { $worst[0].S } else { 'Info' })
            Principal               = $who.Name
            PrincipalType           = $who.Type
            SignInName              = $who.Upn
            Role                    = $(if ($role) { $role.Name } else { "Deleted role ($guid)" })
            RoleType                = $(if (-not $role) { 'Unknown' } elseif ($role.Custom) { 'Custom' } else { 'Built-in' })
            Privileged              = [bool]$privileged
            CanWriteRoleAssignments = [bool]($role -and $role.CanWrite)
            Assignment              = $AssignmentKind
            ScopeType               = $d.Type
            Scope                   = $d.Name
            Reach                   = $d.Reach
            Subscription            = $d.Subscription
            Members                 = $(if ($member -and -not $member.Contains('Error')) { $member.Count } else { $null })
            MemberNames             = $(if ($member -and -not $member.Contains('Error')) { $member.Names } else { '' })
            Condition               = [bool]$More['Condition']
            Findings                = (@($findings | ForEach-Object { $_.T }) -join ' ')
            CreatedOn               = $More['CreatedOn']
            CreatedBy               = [string]$More['CreatedBy']
            EndsOn                  = $More['EndsOn']
            PrincipalId             = $PrincipalId
            RoleDefinitionId        = $RoleId
            ScopeId                 = $ScopeId
            Id                      = [string]$More['Id']
        }
        $item.PSObject.TypeNames.Insert(0, 'AAC.RoleAssignment')
        $assignments.Add($item)
    }
    foreach ($row in (& $rowsOf 'roleAssignments')) {
        $guid = & $leaf (& $text $row 'roleId')
        if (-not $usage.Contains($guid)) { $usage[$guid] = 0 }
        $usage[$guid]++
        $id = & $text $row 'id'
        $kind = if ($activated.Contains($id) -or $activated.Contains((& $leaf $id))) { 'Activated (PIM)' } else { 'Permanent' }
        & $build $kind (& $text $row 'principalId') (& $text $row 'principalType') (& $text $row 'roleId') (& $text $row 'scope') @{
            Condition = [bool](& $text $row 'condition'); CreatedOn = (& $date (& $text $row 'createdOn')); CreatedBy = (& $nameOf (& $text $row 'createdBy')); Id = $id
        }
    }
    $seen = @{}
    foreach ($e in @(if ($Pim) { & $list $Pim['Eligible'] })) {
        $p = & $get $e 'properties'
        if ((& $text $p 'memberType') -and (& $text $p 'memberType') -ne 'Direct') { continue }
        $key = "$((& $text $p 'principalId').ToLowerInvariant())|$((& $text $p 'roleDefinitionId').ToLowerInvariant())|$((& $text $p 'scope').ToLowerInvariant())"
        if ($seen.Contains($key)) { continue }
        $seen[$key] = $true
        & $build 'Eligible (PIM)' (& $text $p 'principalId').ToLowerInvariant() (& $text $p 'principalType') (& $text $p 'roleDefinitionId').ToLowerInvariant() (& $text $p 'scope').ToLowerInvariant() @{
            Condition = [bool](& $text $p 'condition'); CreatedOn = (& $date (& $text $p 'createdOn')); EndsOn = (& $date (& $text $p 'endDateTime')); Id = (& $text $e 'id')
        }
    }
    if ($null -ne $Members) { foreach ($g in @($Members.Keys | Where-Object { $Members[$_].Contains('Error') })) { $notices.Add("The members of group $g couldn't be read: $($Members[$g].Error)"); break } }

    # --- Custom roles ------------------------------------------------------------------------------------------------------------------
    $byPolicy = @{}
    foreach ($row in (& $rowsOf 'policyRoles')) { $byPolicy[(& $leaf (& $text $row 'role'))] = $true }
    $customRoles = @(foreach ($guid in @($roles.Keys | Where-Object { $roles[$_].Custom })) {
            $r = $roles[$guid]
            $count = if ($usage.Contains($guid)) { $usage[$guid] } else { 0 }
            $eligibleCount = @($assignments | Where-Object { $_.Assignment -eq 'Eligible (PIM)' -and (& $leaf $_.RoleDefinitionId) -eq $guid }).Count
            $o = [pscustomobject][ordered]@{
                Role                    = $r.Name
                Assignments             = $count + $eligibleCount
                UsedByPolicy            = $byPolicy.Contains($guid)
                Unused                  = ($count + $eligibleCount) -eq 0 -and -not $byPolicy.Contains($guid)
                OwnerEquivalent         = $r.OwnerEquivalent
                CanWriteRoleAssignments = $r.CanWrite
                Actions                 = $r.Actions
                AssignableScopes        = ($r.Scopes -join ', ')
                Id                      = $r.Id
            }
            $o.PSObject.TypeNames.Insert(0, 'AAC.CustomRole')
            $o
        })
    $customRoles = @($customRoles | Sort-Object -Property @{ Expression = 'OwnerEquivalent'; Descending = $true }, @{ Expression = 'Unused'; Descending = $true }, Role)

    $order = @{ Root = 0; 'Management group' = 1; Subscription = 2; 'Resource group' = 3; Resource = 4; Other = 5 }
    $sorted = @($assignments | Sort-Object -Property @{ Expression = { $rank[$_.Severity] } }, @{ Expression = { $order[$_.ScopeType] } }, Scope, Role, Principal)
    @{
        Assignments = $sorted
        CustomRoles = $customRoles
        Notices     = @($notices)
        Stats       = @{
            Assignments = $sorted.Count
            Privileged  = @($sorted | Where-Object Privileged).Count
            Eligible    = @($sorted | Where-Object Assignment -EQ 'Eligible (PIM)').Count
            Orphaned    = @($sorted | Where-Object { $_.PrincipalType -eq 'Deleted' -or $_.RoleType -eq 'Unknown' }).Count
            Findings    = @($sorted | Where-Object Findings).Count
            High        = @($sorted | Where-Object Severity -EQ 'High').Count
            UnusedRoles = @($customRoles | Where-Object Unused).Count
            OwnerRoles  = @($customRoles | Where-Object OwnerEquivalent).Count
        }
    }
}
