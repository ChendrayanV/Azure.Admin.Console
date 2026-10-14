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
        it comes from (Cloud, or synced from on-premises AD), its membership
        type, when it was created, its owners (and how many), its direct
        members, nested groups, and the unique users in it - all, guests and
        disabled accounts - counted through every nested group.

        Summary (AAC.EntraGroupMembershipSummary), one per group, in
        Export-EntraGroupMemberShip.ps1's CSV layout and labels: GroupName,
        GroupSource (Cloud, Windows Server AD), GroupType ('Security',
        'Microsoft 365 / Dynamic', 'Mail-Enabled Security / Role-Assignable'
        ...), Members (everyone in the group, flattened: direct members and
        the members of every nested group at any depth, each once, nested
        groups themselves left out; '(No members)' when there are none),
        NestedGroupMembers (every nested group at any depth, by its path,
        with its own direct members: 'Group: a, b; Group > Inner: c'), then
        Owners ('Name (UPN); ...', '(No owners)'), CreatedDateTime (UTC) and
        MembershipType (Assigned, Dynamic, Dynamic (paused)).
        -Owner maps a group ID to its owners, -OwnerError to why they
        couldn't be read; every row and group carries the same three.
        A group whose members couldn't be read has no summary row; Unread
        lists them (@{ GroupName; Error }).

        Sections maps each group's ID to its own members and then each
        nested group's, in the order met: @{ Path ('' for the group, else
        'nested > deeper'); Depth; Error; Members (its rows); Loops (IDs of
        groups already above on that path, not followed again) }.

        People (AAC.EntraGroupPerson): everyone in each group once - not
        nested groups - with Membership (Direct, Nested, or Direct and
        nested) and Through (the nested groups they come through).

        Returns @{ Rows; Groups; Sections; People; Summary; Unread; Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyCollection()]
        [object[]] $Group = @(),

        # Group ID -> its direct members.
        [hashtable] $Member = @{},

        # Group ID -> why its members couldn't be read.
        [hashtable] $MemberError = @{},

        # Group ID -> its owners (users, service principals).
        [hashtable] $Owner = @{},

        # Group ID -> why its owners couldn't be read.
        [hashtable] $OwnerError = @{}
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
    # Assigned (members added by hand) or Dynamic (by a rule); a paused rule is said.
    $membershipType = {
        param($G)
        if (@(& $value $G 'groupTypes') -contains 'DynamicMembership') {
            if ((& $text $G 'membershipRuleProcessingState') -eq 'Paused') { 'Dynamic (paused)' } else { 'Dynamic' }
        }
        else { 'Assigned' }
    }
    $created = {
        param($G)
        $v = & $value $G 'createdDateTime'
        if ($v -is [datetime]) { $v.ToUniversalTime() }
        elseif ($v) { try { [datetime]::Parse([string]$v, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]'AdjustToUniversal, AssumeUniversal') } catch { $null } }
    }
    # 'Name (user principal name)' per owner; '(No owners)' or why they couldn't be read.
    $ownersOf = {
        param([string] $Id)
        if ($OwnerError.Contains($Id)) { return "(Not read: $([string]$OwnerError[$Id]))" }
        $list = @(if ($Owner.Contains($Id)) { $Owner[$Id] | Where-Object { $null -ne $_ } })
        if (-not $list.Count) { return '(No owners)' }
        @(foreach ($o in $list) {
                $name = foreach ($key in 'displayName', 'userPrincipalName', 'id') { $v = & $text $o $key; if ($v) { $v; break } }
                $upn = & $text $o 'userPrincipalName'
                if ((& $memberType $o) -eq 'Service principal') { "$name (Service principal)" }
                elseif ($upn -and $upn -ne $name) { "$name ($upn)" } else { [string]$name }
            }) -join '; '
    }
    $kindOf = @{
        '#microsoft.graph.user'             = 'User'
        '#microsoft.graph.group'            = 'Group'
        '#microsoft.graph.device'           = 'Device'
        '#microsoft.graph.servicePrincipal' = 'Service principal'
        '#microsoft.graph.orgContact'       = 'Contact'
    }
    $memberType = { param($M) $odata = & $text $M '@odata.type'; if ($kindOf.Contains($odata)) { $kindOf[$odata] } elseif ($odata) { $odata -replace '^#microsoft\.graph\.', '' } else { 'Unknown' } }

    # Export-EntraGroupMemberShip.ps1's labels, for the summary rows.
    $summaryType = {
        param($G)
        $types = @(& $value $G 'groupTypes')
        @(
            if ($types -contains 'Unified') { 'Microsoft 365' }
            elseif ((& $value $G 'securityEnabled') -eq $true -and (& $value $G 'mailEnabled') -eq $true) { 'Mail-Enabled Security' }
            elseif ((& $value $G 'securityEnabled') -eq $true) { 'Security' }
            elseif ((& $value $G 'mailEnabled') -eq $true) { 'Distribution' }
            else { 'Unknown' }
            if ($types -contains 'DynamicMembership') { 'Dynamic' }
            if ((& $value $G 'isAssignableToRole') -eq $true) { 'Role-Assignable' }
        ) -join ' / '
    }
    $summaryName = {
        param($M)
        $name = foreach ($key in 'displayName', 'userPrincipalName', 'id') { $v = & $text $M $key; if ($v) { $v; break } }
        if ((& $memberType $M) -eq 'Group') { "$name (Group)" } else { [string]$name }
    }
    # Every group nested under -Id, at any depth, as 'Path: its own members'
    # - each group once, however many paths lead to it; $Seen guards loops.
    $nestedParts = {
        param([string] $Id, [string] $Label, [System.Collections.Generic.HashSet[string]] $Seen)
        foreach ($child in @(if ($Member.Contains($Id) -and -not $MemberError.Contains($Id)) { $Member[$Id] | Where-Object { $null -ne $_ -and (& $memberType $_) -eq 'Group' } })) {
            $childId = & $text $child 'id'
            if (-not $Seen.Add($childId)) { continue }
            $name = foreach ($key in 'displayName', 'userPrincipalName', 'id') { $v = & $text $child $key; if ($v) { $v; break } }
            $path = if ($Label) { "$Label > $name" } else { [string]$name }
            $own = @(if ($Member.Contains($childId) -and -not $MemberError.Contains($childId)) { $Member[$childId] | Where-Object { $null -ne $_ } })
            "$($path): $(if ($own.Count) { @($own | ForEach-Object { & $summaryName $_ }) -join ', ' } else { '(No members)' })"
            & $nestedParts $childId $path $Seen
        }
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    $groups = [System.Collections.Generic.List[object]]::new()
    $summary = [System.Collections.Generic.List[object]]::new()
    $unread = [System.Collections.Generic.List[object]]::new()
    $sectionsOf = @{}
    $people = [System.Collections.Generic.List[object]]::new()
    foreach ($g in @($Group | Sort-Object -Property { & $text $_ 'displayName' })) {
        $gid = & $text $g 'id'
        $gName = & $text $g 'displayName'
        $gType = & $groupType $g
        $gSource = & $source $g
        $gMembershipType = & $membershipType $g
        $gCreated = & $created $g
        $gOwners = & $ownersOf $gid
        $gOwnerCount = @(if ($Owner.Contains($gid) -and -not $OwnerError.Contains($gid)) { $Owner[$gid] | Where-Object { $null -ne $_ } }).Count
        $users = @{}
        $everyone = [ordered]@{}   # every member that isn't a group, at any depth, once
        $nestedGroups = [System.Collections.Generic.HashSet[string]]::new()
        $errors = [System.Collections.Generic.List[string]]::new()
        # The group's own members, then each nested group's, in the order met.
        $sections = [System.Collections.Generic.List[object]]::new()
        $row = {
            param($M, [string] $Membership, [string] $Via, [int] $Depth)
            $kind = if ($M) { & $memberType $M } else { '' }
            $enabled = if ($M) { & $value $M 'accountEnabled' } else { $null }
            $rows.Add([pscustomobject][ordered]@{
                    PSTypeName        = 'AAC.EntraGroupMember'
                    GroupName         = $gName
                    GroupType         = $gType
                    GroupSource       = $gSource
                    MembershipType    = $gMembershipType
                    GroupCreated      = $gCreated
                    GroupOwners       = $gOwners
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
            if ($M -and $kind -ne 'Group') { $mid = & $text $M 'id'; if (-not $everyone.Contains($mid)) { $everyone[$mid] = & $summaryName $M } }
        }
        # Depth-first through nested groups; $path guards against loops.
        $walk = {
            param([string] $Id, [string] $Via, [int] $Depth, [string[]] $Path)
            if ($MemberError.Contains($Id)) { $errors.Add("$(if ($Via) { $Via } else { $gName }): $($MemberError[$Id])") }
            $section = [pscustomobject]@{
                Path    = $(if ($Via) { $Via.Substring($gName.Length + 3) } else { '' })   # 'nested > deeper', '' for the group itself
                Depth   = $Depth
                Error   = $(if ($MemberError.Contains($Id)) { [string]$MemberError[$Id] } else { '' })
                Members = [System.Collections.Generic.List[object]]::new()
                Loops   = [System.Collections.Generic.HashSet[string]]::new()   # groups already above on this path
            }
            $sections.Add($section)
            foreach ($m in @(if ($Member.Contains($Id)) { $Member[$Id] })) {
                if ($null -eq $m) { continue }
                & $row $m $(if ($Depth -eq 0) { 'Direct' } else { 'Nested' }) $Via $Depth
                $section.Members.Add($rows[$rows.Count - 1])
                if ((& $memberType $m) -eq 'Group') {
                    $childId = & $text $m 'id'
                    if ($childId -ne $gid) { [void]$nestedGroups.Add($childId) }
                    if ($Path -contains $childId) { [void]$section.Loops.Add($childId) }
                    else {
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
        $sectionsOf[$gid] = $sections.ToArray()

        # Everyone in the group once - users, service principals, devices,
        # contacts - with how: Direct, Nested (through which groups) or both.
        $mine = @(for ($i = $before; $i -lt $rows.Count; $i++) { $rows[$i] })
        foreach ($person in @($mine | Where-Object { $_.MemberType -and $_.MemberType -ne 'Group' } | Group-Object -Property MemberId | Sort-Object -Property { $_.Group[0].MemberName })) {
            $first = $person.Group[0]
            $isDirect = @($person.Group | Where-Object Membership -EQ 'Direct').Count -gt 0
            $through = @($person.Group | Where-Object Membership -EQ 'Nested' | ForEach-Object { $_.Via.Substring($gName.Length + 3) } | Select-Object -Unique)
            $people.Add([pscustomobject][ordered]@{
                    PSTypeName        = 'AAC.EntraGroupPerson'
                    GroupName         = $gName
                    MemberName        = $(if ($first.MemberName) { $first.MemberName } elseif ($first.UserPrincipalName) { $first.UserPrincipalName } else { $first.MemberId })
                    MemberType        = $first.MemberType
                    UserPrincipalName = $first.UserPrincipalName
                    Mail              = $first.Mail
                    UserType          = $first.UserType
                    AccountEnabled    = $first.AccountEnabled
                    JobTitle          = $first.JobTitle
                    Department        = $first.Department
                    Membership        = $(if ($isDirect -and $through.Count) { 'Direct and nested' } elseif ($isDirect) { 'Direct' } else { 'Nested' })
                    Through           = $through -join '; '
                    GroupId           = $gid
                    MemberId          = $first.MemberId
                })
        }

        if ($MemberError.Contains($gid)) { $unread.Add(@{ GroupName = $gName; Error = [string]$MemberError[$gid] }) }
        else {
            $summary.Add([pscustomobject][ordered]@{
                    PSTypeName         = 'AAC.EntraGroupMembershipSummary'
                    GroupName          = $gName
                    GroupSource        = $(if ((& $value $g 'onPremisesSyncEnabled') -eq $true) { 'Windows Server AD' } else { 'Cloud' })
                    GroupType          = & $summaryType $g
                    Members            = $(if ($everyone.Count) { @($everyone.Values) -join ', ' } else { '(No members)' })
                    NestedGroupMembers = @(& $nestedParts $gid '' ([System.Collections.Generic.HashSet[string]]::new([string[]]@($gid)))) -join '; '
                    Owners             = $gOwners
                    CreatedDateTime    = $(if ($gCreated) { $gCreated.ToString('yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture) + ' UTC' } else { '' })
                    MembershipType     = $gMembershipType
                })
        }

        $userList = @($users.Values)
        $groups.Add([pscustomobject][ordered]@{
                PSTypeName     = 'AAC.EntraGroup'
                GroupName      = $gName
                GroupType      = $gType
                GroupSource    = $gSource
                MembershipType = $gMembershipType
                Created        = $gCreated
                Owners         = $gOwners
                OwnerCount     = $gOwnerCount
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
    $users = @($all | Where-Object { $_.MemberType -eq 'User' } | Group-Object -Property MemberId)
    @{
        Rows     = $all
        Groups   = $groups.ToArray()
        Sections = $sectionsOf
        People   = $people.ToArray()
        Summary = $summary.ToArray()
        Unread  = $unread.ToArray()
        Stats  = @{
            Groups       = $groups.Count
            Rows         = $all.Count
            Users        = $users.Count
            Guests       = @($users | Where-Object { $_.Group[0].UserType -eq 'Guest' }).Count
            Disabled     = @($users | Where-Object { $_.Group[0].AccountEnabled -eq $false }).Count
            NestedGroups = @($all | Where-Object MemberType -EQ 'Group' | Select-Object -ExpandProperty MemberId -Unique).Count
            EmptyGroups  = @($groups | Where-Object { $_.DirectMembers -eq 0 -and -not $_.Error }).Count
            Unreadable   = @($groups | Where-Object Error).Count
        }
    }
}
