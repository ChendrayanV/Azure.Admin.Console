function ConvertTo-AACAccessReview {
    <#
    .SYNOPSIS
        Turns the access read for Get-AACAccessReview - Azure RBAC (permanent,
        PIM-activated and eligible), classic administrators, Entra ID
        directory roles and Microsoft Graph application permissions - into
        one attestation row per assignment, each with its findings, a
        severity and a recommendation.
    .DESCRIPTION
        Findings (the worst sets the row's severity):
          Critical  standing privileged access (Owner, User Access
                    Administrator, RBAC Administrator, Contributor or an
                    equivalent custom role) at the tenant root or a
                    management group; a guest with Owner or User Access
                    Administrator; an app with a Graph permission that can
                    take over the tenant (RoleManagement.ReadWrite.Directory,
                    AppRoleAssignment.ReadWrite.All, Application.ReadWrite.All)
          High      standing privileged access to a subscription for a user
                    (should be just-in-time, PIM eligible); a service
                    principal with Owner or User Access Administrator; a
                    disabled account or one not signed in for 90 days with
                    privileged access; a permanent privileged Entra role; a
                    guest in an Entra role; broad Graph write or data
                    permissions (Directory/Group/User.ReadWrite.All,
                    Mail, Files, Sites...)
          Medium    an assignment to a deleted principal; write access not
                    used in the activity window (control plane only - the
                    Activity Log doesn't record data-plane use, so roles
                    with data actions aren't judged); a custom role with '*' or
                    Microsoft.Authorization writes; a classic
                    co-administrator; more than 4 Global Administrators
          Low       a role given to a user directly at a subscription or
                    above, rather than through a group
        Recommendation: Remove, Make eligible (PIM), Narrow the scope or
        role, Review usage, Use a group or Keep; Action: what to do, per
        finding, for the kind of principal; and Decision and Reviewer
        columns, empty, for the sign-off. Make eligible (PIM) is only ever recommended for users,
        guests and groups: PIM needs a person to activate the role, so
        service principals and managed identities get Remove or Narrow the
        scope or role instead.
        Returns @{ Rows (AAC.AccessAssignment); Stats; Notices }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyCollection()] [object[]] $Assignment = @(),
        [AllowEmptyCollection()] [object[]] $Definition = @(),
        [AllowEmptyCollection()] [object[]] $Eligibility = @(),
        [AllowEmptyCollection()] [object[]] $ScheduleInstance = @(),
        # @{ SubscriptionId; Items } per subscription.
        [AllowEmptyCollection()] [object[]] $ClassicAdmin = @(),
        # Object ID (lower case) -> Graph directory object; $null when Graph couldn't be read.
        [System.Collections.IDictionary] $Directory,
        # User object ID (lower case) -> last sign-in [datetime].
        [System.Collections.IDictionary] $SignIn = @{},
        # Caller (UPN, app ID or object ID, lower case) -> last write [datetime]; $null when not read.
        [System.Collections.IDictionary] $Activity,
        [int] $ActivityDays = 30,
        [AllowEmptyCollection()] [object[]] $EntraAssignment = @(),
        [AllowEmptyCollection()] [object[]] $EntraEligibility = @(),
        [AllowEmptyCollection()] [object[]] $EntraDefinition = @(),
        # 'principalId|roleDefinitionId' (lower case) of the Entra roles activated just in time.
        [AllowEmptyCollection()] [string[]] $EntraActivated = @(),
        [AllowEmptyCollection()] [object[]] $AppGrant = @(),
        # Microsoft Graph app role ID -> its value ('Mail.Read').
        [System.Collections.IDictionary] $GraphAppRole = @{},
        [System.Collections.IDictionary] $SubscriptionName = @{},
        # Subscription ID (lower case) -> its management group names (lower case).
        [System.Collections.IDictionary] $SubscriptionChain = @{},
        [string[]] $InScope = @(),
        [datetime] $Now = [datetime]::UtcNow
    )

    $Now = $Now.ToUniversalTime()
    $get = { param($Row, [string] $Name) if ($Row -is [System.Collections.IDictionary]) { $Row[$Name] } elseif ($null -ne $Row) { $p = $Row.PSObject.Properties[$Name]; if ($p) { $p.Value } } }
    $props = { param($Row) $p = & $get $Row 'properties'; if ($p) { $p } else { $Row } }
    $lower = { param($Text) ([string]$Text).ToLowerInvariant() }
    $leaf = { param($Id) ([string]$Id).TrimEnd('/') -replace '^.*/', '' }
    $date = { param($Raw) if ($Raw -is [datetime]) { $Raw } elseif ($Raw) { $d = [datetime]::MinValue; if ([datetime]::TryParse([string]$Raw, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$d)) { $d } } }
    $inScopeSet = [System.Collections.Generic.HashSet[string]]::new([string[]]@($InScope | ForEach-Object { $_.ToLowerInvariant() }), [System.StringComparer]::OrdinalIgnoreCase)
    $severity = Get-AACSeverityRank

    # --- Roles -------------------------------------------------------------------------------------------------
    $roles = @{}
    foreach ($d in $Definition) {
        $p = & $props $d
        $actions = @(@(& $get $p 'permissions') | ForEach-Object { @(& $get $_ 'actions') } | Where-Object { $_ })
        $dataActions = @(@(& $get $p 'permissions') | ForEach-Object { @(& $get $_ 'dataActions') } | Where-Object { $_ })
        $name = [string]$(if (& $get $d 'roleName') { & $get $d 'roleName' } else { & $get $p 'roleName' })
        $custom = [string]$(if (& $get $d 'roleType') { & $get $d 'roleType' } else { & $get $p 'type' }) -eq 'CustomRole'
        $wild = @($actions | Where-Object { $_ -eq '*' -or $_ -like 'Microsoft.Authorization/*' -or $_ -like 'Microsoft.Authorization/roleAssignments/write' }).Count -gt 0
        $roles[(& $leaf (& $get $d 'id')).ToLowerInvariant()] = @{
            Name       = $name; Custom = $custom; Wildcard = $custom -and $wild
            Privileged = $name -in 'Owner', 'Contributor', 'User Access Administrator', 'Role Based Access Control Administrator' -or ($custom -and $wild)
            Admin      = $name -in 'Owner', 'User Access Administrator', 'Role Based Access Control Administrator' -or ($custom -and @($actions | Where-Object { $_ -eq '*' -or $_ -like 'Microsoft.Authorization/*' }).Count)
            # Control-plane writes (the Activity Log records them) and data-plane access (it doesn't: blobs, secrets, messages...).
            Writes     = @($actions | Where-Object { $_ -eq '*' -or $_ -match '/(write|delete|action|\*)$' }).Count -gt 0
            Data       = $dataActions.Count -gt 0
        }
    }
    $roleOf = { param($Id) $key = (& $leaf $Id).ToLowerInvariant(); if ($roles.Contains($key)) { $roles[$key] } else { @{ Name = $key; Custom = $false; Wildcard = $false; Privileged = $false; Admin = $false; Writes = $true; Data = $false } } }

    # --- Scopes ------------------------------------------------------------------------------------------------
    $scopeOf = {
        param([string] $Scope)
        $s = & $lower $Scope
        if ($s -eq '/' -or $s -eq '') { return @{ Level = 'Root'; Label = 'Tenant root (/)'; Subscription = ''; In = $true } }
        if ($s -match '^/providers/microsoft.management/managementgroups/([^/]+)$') {
            $mg = $Matches[1]
            $under = @($SubscriptionChain.Keys | Where-Object { @($SubscriptionChain[$_]) -contains $mg -and $inScopeSet.Contains($_) }).Count
            return @{ Level = 'Management group'; Label = "management group $mg"; Subscription = ''; In = $under -gt 0 -or -not $inScopeSet.Count }
        }
        if ($s -match '^/subscriptions/([^/]+)') {
            $sub = $Matches[1]
            $name = if ($SubscriptionName.Contains($sub)) { [string]$SubscriptionName[$sub] } else { $sub }
            $level = if ($s -match '^/subscriptions/[^/]+$') { 'Subscription' } elseif ($s -match '^/subscriptions/[^/]+/resourcegroups/[^/]+$') { 'Resource group' } else { 'Resource' }
            $label = switch ($level) { 'Subscription' { "subscription $name" } 'Resource group' { "resource group $(& $leaf $s) ($name)" } default { "$(& $leaf $s) ($name)" } }
            return @{ Level = $level; Label = $label; Subscription = $name; In = (-not $inScopeSet.Count) -or $inScopeSet.Contains($sub) }
        }
        @{ Level = 'Other'; Label = $Scope; Subscription = ''; In = $true }
    }
    $broad = { param([string] $Level) $Level -in 'Root', 'Management group', 'Subscription' }

    # --- Principals -------------------------------------------------------------------------------------------
    $directoryRead = $null -ne $Directory
    $principalOf = {
        param([string] $Id, [string] $Type)
        $key = & $lower $Id
        $o = if ($directoryRead -and $Directory.Contains($key)) { $Directory[$key] } else { $null }
        if ($o) {
            $odata = [string](& $get $o '@odata.type')
            $kind = switch -Wildcard ($odata) {
                '*user' { if ([string](& $get $o 'userType') -eq 'Guest') { 'Guest' } else { 'User' } }
                '*group' { 'Group' }
                '*servicePrincipal' { if ([string](& $get $o 'servicePrincipalType') -eq 'ManagedIdentity') { 'Managed identity' } else { 'Service principal' } }
                default { 'Other' }
            }
            return @{ Name = [string](& $get $o 'displayName'); Kind = $kind; SignIn = [string]$(if (& $get $o 'userPrincipalName') { & $get $o 'userPrincipalName' } else { & $get $o 'appId' }); AppId = [string](& $get $o 'appId'); Enabled = (& $get $o 'accountEnabled'); Deleted = $false }
        }
        $kind = switch ($Type) { 'User' { 'User' } 'Group' { 'Group' } 'ServicePrincipal' { 'Service principal' } 'ForeignGroup' { 'Group' } default { 'Unknown' } }
        @{ Name = $(if ($directoryRead) { "$Id (deleted)" } else { $Id }); Kind = $kind; SignIn = ''; AppId = ''; Enabled = $null; Deleted = $directoryRead }
    }
    $lastActivity = {
        param($P, [string] $Id)
        if ($null -eq $Activity) { return $null }
        $times = @(foreach ($k in @($P.SignIn, $P.AppId, $Id) | Where-Object { $_ }) { $k = & $lower $k; if ($Activity.Contains($k)) { $Activity[$k] } })
        if ($times.Count) { ($times | Sort-Object -Descending)[0] } else { $null }
    }

    # --- PIM: which RBAC assignments were activated, and what's eligible ------------------------------------------------
    $activated = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($i in $ScheduleInstance) {
        $p = & $props $i
        if ([string](& $get $p 'assignmentType') -eq 'Activated') { $origin = & $lower (& $get $p 'originRoleAssignmentId'); if ($origin) { [void]$activated.Add((& $leaf $origin)) } }
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    $addRow = {
        param([string] $Source, [string] $PrincipalId, $P, [string] $RoleName, [string] $ScopeLabel, [string] $Level, [string] $Subscription, [string] $AssignmentKind, [bool] $Privileged, $Created, [object[]] $Findings, [string] $AssignmentId, $LastSeen)
        $worst = @($Findings | Sort-Object -Property { $severity.Rank[$_.Severity] } | Select-Object -First 1)
        $recommend = if (@($Findings | Where-Object Recommendation -EQ 'Remove').Count) { 'Remove' }
        elseif (@($Findings | Where-Object Recommendation -EQ 'Make eligible (PIM)').Count) { 'Make eligible (PIM)' }
        elseif (@($Findings | Where-Object Recommendation -EQ 'Narrow the scope or role').Count) { 'Narrow the scope or role' }
        elseif (@($Findings | Where-Object Recommendation -EQ 'Review usage').Count) { 'Review usage' }
        elseif (@($Findings | Where-Object Recommendation -EQ 'Use a group').Count) { 'Use a group' }
        else { 'Keep' }
        $userSignIn = if ($SignIn.Contains((& $lower $PrincipalId))) { $SignIn[(& $lower $PrincipalId)] } else { $null }
        $rows.Add([pscustomobject][ordered]@{
                PSTypeName     = 'AAC.AccessAssignment'
                Severity       = $(if ($worst.Count) { $worst[0].Severity } else { 'Info' })
                Principal      = $P.Name
                PrincipalType  = $P.Kind
                SignInName     = $P.SignIn
                Role           = $RoleName
                Privileged     = $(if ($Privileged) { 'Yes' } else { 'No' })
                Scope          = $ScopeLabel
                ScopeLevel     = $Level
                Subscription   = $Subscription
                Assignment     = $AssignmentKind
                Source         = $Source
                Enabled        = $(if ($null -eq $P.Enabled) { '' } elseif ($P.Enabled) { 'Yes' } else { 'No' })
                LastSignIn     = $userSignIn
                LastActivity   = $LastSeen
                Findings       = (@($Findings | ForEach-Object { $_.Text }) -join '; ')
                Recommendation = $recommend
                Action         = (@($Findings | Sort-Object -Property { $severity.Rank[$_.Severity] } | ForEach-Object { $_.Action } | Where-Object { $_ } | Select-Object -Unique) -join ' ')
                Decision       = ''
                Reviewer       = ''
                Created        = $Created
                PrincipalId    = $PrincipalId
                AssignmentId   = $AssignmentId
            })
    }
    $finding = { param([string] $Severity, [string] $Text, [string] $Recommendation, [string] $Action = '') [pscustomobject]@{ Severity = $Severity; Text = $Text; Recommendation = $Recommendation; Action = $Action } }
    # What to do, by who holds the access: a person can be made just-in-time; an application can't (PIM needs someone to activate the role).
    $isApp = { param($P) $P.Kind -in 'Service principal', 'Managed identity' }
    $protectApp = 'Use a managed identity or a federated credential rather than a client secret, keep its owners to a few named people, and watch its sign-ins (Conditional Access for workload identities).'
    $windowStart = $Now.AddDays(-$ActivityDays)
    $assess = {
        # The findings common to an RBAC or Entra role assignment.
        param($P, $Role, [string] $Level, [string] $Kind, $Created, $LastSeen, [bool] $EntraPrivileged)
        $list = [System.Collections.Generic.List[object]]::new()
        $privileged = if ($Role) { $Role.Privileged } else { $EntraPrivileged }
        $standing = $Kind -eq 'Permanent'
        if ($P.Deleted) { $list.Add((& $finding 'Medium' 'The principal no longer exists in Entra ID (orphaned assignment)' 'Remove' 'Remove the assignment: no one can use it, but it hides real access in every review.')) }
        if ($privileged -and $standing) {
            if ($Level -in 'Root', 'Management group' -and $P.Kind -ne 'Group') { $list.Add((& $finding 'Critical' "Standing privileged access at the $($Level.ToLowerInvariant())" $(if ($P.Kind -in 'User', 'Guest') { 'Make eligible (PIM)' } else { 'Narrow the scope or role' }) $(if (& $isApp $P) { "An application doesn't need rights over every subscription below the $($Level.ToLowerInvariant()): assign the narrowest role that works at the subscriptions or resource groups it manages. $protectApp" } else { 'Make it eligible in PIM (with MFA, a justification and a time limit on activation), at the narrowest scope that works.' }))) }
            elseif ($Level -eq 'Subscription' -and $P.Kind -in 'User', 'Guest') { $list.Add((& $finding 'High' 'Standing privileged access to a subscription - should be just-in-time' 'Make eligible (PIM)' 'Make it eligible in PIM, so the role is activated only when needed - with MFA, a justification and a time limit.')) }
            elseif ($Level -in 'Subscription', 'Directory' -and $P.Kind -in 'Service principal', 'Managed identity' -and $Role -and $Role.Admin) { $list.Add((& $finding 'High' "An application can grant access to anyone ($($Role.Name))" 'Narrow the scope or role' "Replace $($Role.Name) with Contributor, or a narrower built-in role, at the resource groups it deploys to. If it must assign roles, give it Role Based Access Control Administrator with a condition that limits which roles it can assign, and to whom. $protectApp")) }
            elseif ($Level -eq 'Subscription' -and $P.Kind -in 'Service principal', 'Managed identity') { $list.Add((& $finding 'Medium' 'An application can change everything in the subscription' 'Narrow the scope or role' "Scope it to the resource groups it deploys to, with the narrowest built-in role that works (for example Website Contributor or Storage Account Contributor). $protectApp")) }
            elseif ($Level -eq 'Directory' -and $P.Kind -in 'User', 'Guest', 'Group') { $list.Add((& $finding 'High' 'A permanent privileged Entra ID role - should be eligible (PIM)' 'Make eligible (PIM)' 'Make it eligible in PIM for Microsoft Entra roles, with approval or MFA on activation.')) }
        }
        if ($privileged -and $P.Kind -eq 'Guest') { $list.Add((& $finding $(if ($Role -and $Role.Admin -and (& $broad $Level)) { 'Critical' } else { 'High' }) 'A guest (external account) holds privileged access' 'Remove' 'Remove it; if the person works for you, give them a member account and make that eligible in PIM.')) }
        if ($privileged -and $P.Enabled -eq $false) { $list.Add((& $finding 'High' 'The account is disabled but still holds privileged access' 'Remove' $(if (& $isApp $P) { 'Remove the role: a disabled application can be enabled again with its rights intact.' } else { 'Remove the role: an account enabled again would get its rights back at once.' }))) }
        if ($privileged -and $P.Kind -in 'User', 'Guest' -and $SignIn.Contains($P.Id)) {
            $last = $SignIn[$P.Id]
            if ($last -is [datetime] -and $last -lt $Now.AddDays(-90)) { $list.Add((& $finding 'High' "No sign-in for $([int]($Now - $last).TotalDays) days" 'Remove' 'Remove the role; if the person still needs it now and then, make it eligible in PIM.')) }
        }
        # Unused write access - judged only on what the Activity Log records: a role with data-plane
        # access (blobs, secrets, messages) may be in daily use without a single entry there.
        if ($null -ne $Activity -and $standing -and $P.Kind -in 'User', 'Guest', 'Service principal', 'Managed identity' -and (-not $Role -or ($Role.Writes -and -not $Role.Data)) -and -not $LastSeen -and (-not ($Created -is [datetime]) -or $Created -lt $windowStart) -and $Level -ne 'Directory') {
            $unused = "No write operations in the last $ActivityDays day(s) (Activity Log)"
            if ($P.Kind -in 'Service principal', 'Managed identity') {
                # PIM needs a person to activate the role: an application or managed identity can't be made eligible.
                # Quiet for a while isn't unused: a monthly job or a disaster-recovery pipeline leaves nothing in the window.
                $list.Add((& $finding 'Medium' $unused 'Review usage' "Check the application's sign-in logs (Entra ID, service principal and managed identity sign-ins) and ask its owner before changing anything: a job that runs monthly, or only in a disaster, writes nothing for weeks. If it isn't used, remove the role; if it is, keep it to the resource groups it changes. An application can't be made eligible in PIM - that needs a person to activate the role."))
            }
            else { $list.Add((& $finding 'Medium' $unused $(if ($privileged) { 'Make eligible (PIM)' } else { 'Remove' }) $(if ($privileged) { 'Make it eligible in PIM, or remove it if the person no longer needs it.' } else { 'Remove it: the access goes unused.' }))) }
        }
        if ($Role -and $Role.Wildcard) { $list.Add((& $finding 'Medium' "Custom role '$($Role.Name)' allows '*' or changes to access" 'Narrow the scope or role' "List only the actions the role needs instead of '*', and leave out Microsoft.Authorization/* unless it must assign roles.")) }
        if ($P.Kind -eq 'User' -and $standing -and (& $broad $Level) -and $Level -ne 'Directory' -and -not @($list).Count) { $list.Add((& $finding 'Low' 'Given to the user directly - a group is easier to review' 'Use a group' 'Assign the role to a group and add the user to it; review the group, not each person.')) }
        , $list.ToArray()
    }

    # --- Azure RBAC: permanent and PIM-activated -------------------------------------------------------------------------
    foreach ($a in $Assignment) {
        $p = & $props $a
        $scope = & $scopeOf ([string](& $get $p 'scope'))
        if (-not $scope.In) { continue }
        $principalId = & $lower (& $get $p 'principalId')
        $principal = & $principalOf $principalId ([string](& $get $p 'principalType'))
        $principal.Id = $principalId
        $role = & $roleOf (& $get $p 'roleDefinitionId')
        if (-not $role.Name -or $role.Name -match '^[0-9a-f-]{36}$') { $role = & $roleOf (& $get $p 'roleId') }
        $id = & $leaf (& $get $a 'id')
        $kind = if ($activated.Contains($id)) { 'Activated (PIM)' } else { 'Permanent' }
        $created = & $date (& $get $p 'createdOn')
        $seen = & $lastActivity $principal $principalId
        & $addRow 'Azure RBAC' $principalId $principal $role.Name $scope.Label $scope.Level $scope.Subscription $kind $role.Privileged $created (& $assess $principal $role $scope.Level $kind $created $seen $false) ([string](& $get $a 'id')) $seen
    }
    # --- Azure RBAC: eligible (PIM) - just-in-time, as recommended --------------------------------------------------------
    $seenEligible = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($e in $Eligibility) {
        $p = & $props $e
        $key = "$(& $lower (& $get $p 'principalId'))|$(& $leaf (& $get $p 'roleDefinitionId'))|$(& $lower (& $get $p 'scope'))"
        if (-not $seenEligible.Add($key)) { continue }
        $scope = & $scopeOf ([string](& $get $p 'scope'))
        if (-not $scope.In) { continue }
        $principalId = & $lower (& $get $p 'principalId')
        $principal = & $principalOf $principalId ([string](& $get $p 'principalType'))
        $principal.Id = $principalId
        $role = & $roleOf (& $get $p 'roleDefinitionId')
        $findings = @(if ($principal.Deleted) { & $finding 'Medium' 'The principal no longer exists in Entra ID (orphaned eligibility)' 'Remove' 'Remove the eligibility: no one can activate it, but it hides real access in every review.' }; if ($role.Privileged -and $principal.Kind -eq 'Guest') { & $finding 'High' 'A guest (external account) is eligible for privileged access' 'Remove' })
        & $addRow 'Azure RBAC' $principalId $principal $role.Name $scope.Label $scope.Level $scope.Subscription 'Eligible (PIM)' $role.Privileged (& $date (& $get $p 'startDateTime')) $findings ([string](& $get $e 'id')) $null
    }
    # --- Classic administrators --------------------------------------------------------------------------------------------
    foreach ($c in $ClassicAdmin) {
        $sub = & $lower $c.SubscriptionId
        $name = if ($SubscriptionName.Contains($sub)) { [string]$SubscriptionName[$sub] } else { $sub }
        foreach ($item in @($c.Items)) {
            $p = & $props $item
            $role = [string](& $get $p 'role')
            $email = [string](& $get $p 'emailAddress')
            $findings = @(if ($role -match 'CoAdministrator') { & $finding 'Medium' 'A classic co-administrator: full access outside Azure RBAC (classic administrators are retired)' 'Remove' 'Remove the co-administrator; give the person an Azure RBAC role, eligible in PIM, if they still need access.' })
            & $addRow 'Classic administrator' '' @{ Name = $email; Kind = 'User'; SignIn = $email; AppId = ''; Enabled = $null; Deleted = $false } $role "subscription $name" 'Subscription' $name 'Permanent' $true $null $findings ([string](& $get $item 'id')) $null
        }
    }
    # --- Entra ID directory roles ---------------------------------------------------------------------------------------------
    $entraNames = @{}
    foreach ($d in $EntraDefinition) { $entraNames[(& $lower (& $get $d 'id'))] = [string](& $get $d 'displayName'); $templateId = & $lower (& $get $d 'templateId'); if ($templateId) { $entraNames[$templateId] = [string](& $get $d 'displayName') } }
    $privilegedEntra = 'Global Administrator', 'Privileged Role Administrator', 'Privileged Authentication Administrator', 'Security Administrator', 'Exchange Administrator', 'SharePoint Administrator', 'User Administrator', 'Application Administrator', 'Cloud Application Administrator', 'Conditional Access Administrator', 'Intune Administrator', 'Hybrid Identity Administrator', 'Authentication Administrator', 'Helpdesk Administrator', 'Groups Administrator', 'Billing Administrator', 'Azure AD Joined Device Local Administrator', 'Domain Name Administrator', 'External Identity Provider Administrator', 'Partner Tier2 Support'
    $globalAdmins = @($EntraAssignment + $EntraEligibility | Where-Object { $entraNames[(& $lower (& $get $_ 'roleDefinitionId'))] -eq 'Global Administrator' } | ForEach-Object { & $lower (& $get $_ 'principalId') } | Select-Object -Unique)
    foreach ($set in @(@{ Kind = 'Permanent'; Items = $EntraAssignment }, @{ Kind = 'Eligible (PIM)'; Items = $EntraEligibility })) {
        foreach ($a in @($set.Items)) {
            $principalId = & $lower (& $get $a 'principalId')
            $principal = & $principalOf $principalId ''
            $principal.Id = $principalId
            $roleName = $entraNames[(& $lower (& $get $a 'roleDefinitionId'))]
            if (-not $roleName) { $roleName = [string](& $get $a 'roleDefinitionId') }
            $isPrivileged = $roleName -in $privilegedEntra
            $kind = if ($set.Kind -eq 'Permanent' -and $EntraActivated -contains "$principalId|$(& $lower (& $get $a 'roleDefinitionId'))") { 'Activated (PIM)' } else { $set.Kind }
            $findings = [System.Collections.Generic.List[object]]::new()
            if ($kind -ne 'Eligible (PIM)') { foreach ($f in (& $assess $principal $null 'Directory' $kind $null $null $isPrivileged)) { $findings.Add($f) } }
            elseif ($principal.Deleted) { $findings.Add((& $finding 'Medium' 'The principal no longer exists in Entra ID (orphaned eligibility)' 'Remove' 'Remove the eligibility: no one can activate it, but it hides real access in every review.')) }
            if ($roleName -eq 'Global Administrator' -and $globalAdmins.Count -gt 4) { $findings.Add((& $finding 'Medium' "$($globalAdmins.Count) Global Administrators - Microsoft recommends fewer than 5" 'Remove' 'Keep two to four Global Administrators (plus break-glass accounts); give the others a narrower Entra role, eligible in PIM.')) }
            & $addRow 'Entra ID role' $principalId $principal $roleName 'Entra ID (directory)' 'Directory' '' $kind $isPrivileged $null $findings.ToArray() ([string](& $get $a 'id')) $null
        }
    }
    # --- Microsoft Graph application permissions -------------------------------------------------------------------------------
    $takeover = 'RoleManagement.ReadWrite.Directory', 'AppRoleAssignment.ReadWrite.All', 'Application.ReadWrite.All'
    $broadGraph = 'Directory.ReadWrite.All', 'Group.ReadWrite.All', 'GroupMember.ReadWrite.All', 'User.ReadWrite.All', 'Mail.ReadWrite', 'Mail.Read', 'Mail.Send', 'Files.ReadWrite.All', 'Files.Read.All', 'Sites.ReadWrite.All', 'Sites.FullControl.All', 'Sites.Read.All', 'Policy.ReadWrite.ConditionalAccess', 'PrivilegedAccess.ReadWrite.AzureAD', 'UserAuthenticationMethod.ReadWrite.All', 'Domain.ReadWrite.All'
    foreach ($g in $AppGrant) {
        $permission = [string]$GraphAppRole[(& $lower (& $get $g 'appRoleId'))]
        if (-not $permission) { continue }
        $principalId = & $lower (& $get $g 'principalId')
        $principal = & $principalOf $principalId 'ServicePrincipal'
        $principal.Id = $principalId
        if ($principal.Name -eq $principalId -and (& $get $g 'principalDisplayName')) { $principal.Name = [string](& $get $g 'principalDisplayName') }
        $findings = @(
            if ($permission -in $takeover) { & $finding 'Critical' "The application permission $permission can take over the tenant" 'Narrow the scope or role' "Replace it with the least-privileged permission the app needs, or remove it. Until then, protect the app like a Global Administrator. $protectApp" }
            elseif ($permission -in $broadGraph) { & $finding 'High' "The application permission $permission reaches the whole tenant's data or directory, with no user present" 'Narrow the scope or role' "Use a narrower permission, or limit where it applies: Sites.Selected for SharePoint, RBAC for Applications in Exchange Online for mailboxes. $protectApp" }
        )
        & $addRow 'Graph app permission' $principalId $principal $permission 'Microsoft Graph (tenant)' 'Directory' '' 'Permanent' ($permission -in $takeover + $broadGraph) (& $date (& $get $g 'createdDateTime')) $findings ([string](& $get $g 'id')) $null
    }

    $sorted = @($rows | Sort-Object -Property @{ Expression = { $severity.Rank[$_.Severity] } }, @{ Expression = { if ($_.Privileged -eq 'Yes') { 0 } else { 1 } } }, Principal, Role)
    $notices = [System.Collections.Generic.List[string]]::new()
    if (-not $directoryRead) { $notices.Add('Entra ID couldn''t be read, so principals are shown by ID and deleted ones can''t be told apart (Microsoft Graph: Directory.Read.All).') }
    if ($null -eq $Activity) { $notices.Add('The Activity Log wasn''t read, so unused access isn''t assessed (-ActivityDays).') }
    @{
        Rows    = $sorted
        Notices = $notices.ToArray()
        Stats   = @{
            Assignments  = $sorted.Count
            Privileged   = @($sorted | Where-Object Privileged -EQ 'Yes').Count
            Standing     = @($sorted | Where-Object { $_.Privileged -eq 'Yes' -and $_.Assignment -eq 'Permanent' -and $_.PrincipalType -in 'User', 'Guest' }).Count
            Eligible     = @($sorted | Where-Object Assignment -EQ 'Eligible (PIM)').Count
            Orphaned     = @($sorted | Where-Object { $_.Findings -like '*no longer exists*' }).Count
            Unused       = @($sorted | Where-Object { $_.Findings -like '*No write operations*' }).Count
            Guests       = @($sorted | Where-Object { $_.PrincipalType -eq 'Guest' -and $_.Privileged -eq 'Yes' }).Count
            Critical     = @($sorted | Where-Object Severity -EQ 'Critical').Count
            High         = @($sorted | Where-Object Severity -EQ 'High').Count
            ToRemove     = @($sorted | Where-Object Recommendation -EQ 'Remove').Count
            ToEligible   = @($sorted | Where-Object Recommendation -EQ 'Make eligible (PIM)').Count
            RiskyApps    = @($sorted | Where-Object { $_.Source -eq 'Graph app permission' -and $_.Severity -in 'Critical', 'High' } | ForEach-Object Principal | Select-Object -Unique).Count
            Principals   = @($sorted | ForEach-Object { if ($_.PrincipalId) { $_.PrincipalId } else { $_.SignInName } } | Select-Object -Unique).Count
        }
    }
}
