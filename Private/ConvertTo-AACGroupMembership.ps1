function ConvertTo-AACGroupMembership {
    <#
    .SYNOPSIS
        Flattens Entra ID groups and their members - nested groups followed
        to the end - into one row per group and member, with a summary per
        group.
    .DESCRIPTION
        -Group are the groups asked for (Microsoft Graph group objects);
        -Member maps a group ID to its direct members (directory objects:
        users, groups, devices, service principals, contacts), for those
        groups and every group nested in them.

        Rows (AAC.EntraGroupMember), one per member of each group asked for:
          Membership  Direct, Nested (through a nested group - Via names the
                      path, Depth how deep), or Empty (a group with no
                      members, so every group is in the report)
          a nested group is a row of its own (MemberType Group) and its
          members follow it; a group met again on the same path (a loop) is
          not followed twice
        Groups (AAC.EntraGroup): its type (Microsoft 365, Security,
        Mail-enabled security, Distribution; dynamic, role-assignable), where
        it comes from (Cloud, or synced from on-premises AD), its direct
        members, nested groups, and the unique users in it - all, guests and
        disabled accounts - counted through every nested group.

        Returns @{ Rows; Groups; Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyCollection()]
        [object[]] $Group = @(),

        # Group ID -> its direct members.
        [hashtable] $Member = @{},

        # Group ID -> why its members couldn't be read.
        [hashtable] $MemberError = @{}
    )

    $value = {
        param($Object, [string] $Key)
        if ($Object -is [System.Collections.IDictionary]) { if ($Object.Contains($Key)) { $Object[$Key] } }
        else { Get-AACPropertyValue -InputObject $Object -Name $Key }
    }
    $text = { param($Object, [string] $Key) $v = & $value $Object $Key; if ($null -eq $v) { '' } else { [string]$v } }
    $groupType = {
        param($G)
        $types = @(& $value $G 'groupTypes')
        $kind = if ($types -contains 'Unified') { 'Microsoft 365' }
        elseif ((& $value $G 'securityEnabled') -eq $true -and (& $value $G 'mailEnabled') -eq $true) { 'Mail-enabled security' }
        elseif ((& $value $G 'securityEnabled') -eq $true) { 'Security' }
        elseif ((& $value $G 'mailEnabled') -eq $true) { 'Distribution' }
        else { 'Other' }
        $extra = @(
            if ($types -contains 'DynamicMembership') { 'dynamic' }
            if ((& $value $G 'isAssignableToRole') -eq $true) { 'role-assignable' }
        )
        if ($extra.Count) { "$kind ($($extra -join ', '))" } else { $kind }
    }
    $source = { param($G) if ((& $value $G 'onPremisesSyncEnabled') -eq $true) { 'Synced from on-premises AD' } else { 'Cloud' } }
    $kindOf = @{
        '#microsoft.graph.user'             = 'User'
        '#microsoft.graph.group'            = 'Group'
        '#microsoft.graph.device'           = 'Device'
        '#microsoft.graph.servicePrincipal' = 'Service principal'
        '#microsoft.graph.orgContact'       = 'Contact'
    }
    $memberType = { param($M) $odata = & $text $M '@odata.type'; if ($kindOf.Contains($odata)) { $kindOf[$odata] } elseif ($odata) { $odata -replace '^#microsoft\.graph\.', '' } else { 'Unknown' } }

    $rows = [System.Collections.Generic.List[object]]::new()
    $groups = [System.Collections.Generic.List[object]]::new()
    foreach ($g in @($Group | Sort-Object -Property { & $text $_ 'displayName' })) {
        $gid = & $text $g 'id'
        $gName = & $text $g 'displayName'
        $gType = & $groupType $g
        $gSource = & $source $g
        $users = @{}
        $nestedGroups = [System.Collections.Generic.HashSet[string]]::new()
        $errors = [System.Collections.Generic.List[string]]::new()
        $row = {
            param($M, [string] $Membership, [string] $Via, [int] $Depth)
            $kind = if ($M) { & $memberType $M } else { '' }
            $enabled = if ($M) { & $value $M 'accountEnabled' } else { $null }
            $rows.Add([pscustomobject][ordered]@{
                    PSTypeName        = 'AAC.EntraGroupMember'
                    GroupName         = $gName
                    GroupType         = $gType
                    GroupSource       = $gSource
                    MemberName        = $(if ($M) { & $text $M 'displayName' } else { '' })
                    MemberType        = $kind
                    UserPrincipalName = $(if ($M) { & $text $M 'userPrincipalName' } else { '' })
                    Mail              = $(if ($M) { & $text $M 'mail' } else { '' })
                    UserType          = $(if ($kind -eq 'User') { & $text $M 'userType' } else { '' })
                    AccountEnabled    = $(if ($kind -eq 'User' -and $null -ne $enabled) { [bool]$enabled } else { $null })
                    JobTitle          = $(if ($M) { & $text $M 'jobTitle' } else { '' })
                    Department        = $(if ($M) { & $text $M 'department' } else { '' })
                    Membership        = $Membership
                    Via               = $Via
                    Depth             = $Depth
                    GroupId           = $gid
                    MemberId          = $(if ($M) { & $text $M 'id' } else { '' })
                })
            if ($kind -eq 'User') { $users[(& $text $M 'id')] = $M }
        }
        # Depth-first through nested groups; $path guards against loops.
        $walk = {
            param([string] $Id, [string] $Via, [int] $Depth, [string[]] $Path)
            if ($MemberError.Contains($Id)) { $errors.Add("$(if ($Via) { $Via } else { $gName }): $($MemberError[$Id])") }
            foreach ($m in @(if ($Member.Contains($Id)) { $Member[$Id] })) {
                if ($null -eq $m) { continue }
                & $row $m $(if ($Depth -eq 0) { 'Direct' } else { 'Nested' }) $Via $Depth
                if ((& $memberType $m) -eq 'Group') {
                    $childId = & $text $m 'id'
                    if ($childId -ne $gid) { [void]$nestedGroups.Add($childId) }
                    if ($Path -notcontains $childId) {
                        $childVia = if ($Via) { "$Via > $(& $text $m 'displayName')" } else { "$gName > $(& $text $m 'displayName')" }
                        & $walk $childId $childVia ($Depth + 1) (@($Path) + $childId)
                    }
                }
            }
        }
        $before = $rows.Count
        & $walk $gid '' 0 @($gid)
        $direct = @(if ($Member.Contains($gid)) { $Member[$gid] | Where-Object { $null -ne $_ } }).Count
        if ($rows.Count -eq $before) { & $row $null $(if ($MemberError.Contains($gid)) { 'Not read' } else { 'Empty' }) '' 0 }

        $userList = @($users.Values)
        $groups.Add([pscustomobject][ordered]@{
                PSTypeName     = 'AAC.EntraGroup'
                GroupName      = $gName
                GroupType      = $gType
                GroupSource    = $gSource
                DirectMembers  = $direct
                NestedGroups   = $nestedGroups.Count
                Users          = $userList.Count
                Guests         = @($userList | Where-Object { (& $text $_ 'userType') -eq 'Guest' }).Count
                DisabledUsers  = @($userList | Where-Object { (& $value $_ 'accountEnabled') -eq $false }).Count
                Description    = & $text $g 'description'
                MembershipRule = & $text $g 'membershipRule'
                Mail           = & $text $g 'mail'
                GroupId        = $gid
                Error          = $errors -join '; '
            })
    }

    $all = $rows.ToArray()
    $people = @($all | Where-Object { $_.MemberType -eq 'User' } | Group-Object -Property MemberId)
    @{
        Rows   = $all
        Groups = $groups.ToArray()
        Stats  = @{
            Groups       = $groups.Count
            Rows         = $all.Count
            Users        = $people.Count
            Guests       = @($people | Where-Object { $_.Group[0].UserType -eq 'Guest' }).Count
            Disabled     = @($people | Where-Object { $_.Group[0].AccountEnabled -eq $false }).Count
            NestedGroups = @($all | Where-Object MemberType -EQ 'Group' | Select-Object -ExpandProperty MemberId -Unique).Count
            EmptyGroups  = @($groups | Where-Object { $_.DirectMembers -eq 0 -and -not $_.Error }).Count
            Unreadable   = @($groups | Where-Object Error).Count
        }
    }
}
