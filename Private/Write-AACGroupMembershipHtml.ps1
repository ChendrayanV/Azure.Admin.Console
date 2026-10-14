function Write-AACGroupMembershipHtml {
    <#
    .SYNOPSIS
        Writes Get-AACEntraGroupMembership's result as an interactive HTML
        report: an overview with tiles, charts and every group as a tree
        (details, owners, direct members, nested groups opening to their
        members), then tabs with the groups, everyone in each group once,
        and every membership row - searchable, filterable and downloadable
        as CSV.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Membership,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Title,

        [System.Collections.IDictionary] $Detail
    )

    $stats = $Membership.Stats
    $count = { param([int] $Value, [string] $One, [string] $Many) , @($Value, $(if ($Value -eq 1) { $One } else { $Many })) }
    $account = { param($Item) if ($Item.MemberType -ne 'User') { '' } elseif ($Item.AccountEnabled -eq $false) { 'Disabled' } else { 'Enabled' } }
    $rows = @($Membership.Rows | Select-Object -Property *, @{ Name = 'Account'; Expression = { & $account $_ } })
    $people = @($Membership.People | Select-Object -Property *, @{ Name = 'Account'; Expression = { & $account $_ } })
    $top = {
        param([object[]] $Items, [string] $Property, [int] $First = 12)
        @($Items | Group-Object -Property $Property | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, Name | Select-Object -First $First | ForEach-Object {
                @{ Label = $(if ($_.Name) { $_.Name } else { '(none)' }); Value = $_.Count; Filter = $_.Name }
            })
    }

    $tiles = @(
        @{ Value = '{0:N0}' -f $stats.Groups; Label = 'groups'; Tone = 'violet'; Table = 'groups' }
        @{ Value = '{0:N0}' -f $stats.Users; Label = 'unique users'; Tone = 'info'; Table = 'people'; Filters = @{ MemberType = 'User' } }
        @{ Value = '{0:N0}' -f $stats.Guests; Label = 'guests'; Tone = $(if ($stats.Guests) { 'warn' } else { 'good' }); Table = 'people'; Filters = @{ UserType = 'Guest' } }
        @{ Value = '{0:N0}' -f $stats.Disabled; Label = 'disabled accounts'; Tone = $(if ($stats.Disabled) { 'bad' } else { 'good' }); Table = 'people'; Filters = @{ Account = 'Disabled' } }
        @{ Value = '{0:N0}' -f $stats.NestedGroups; Label = 'nested groups'; Tone = 'warn'; Table = 'members'; Filters = @{ MemberType = 'Group' } }
        @{ Value = '{0:N0}' -f $stats.Rows; Label = 'membership rows'; Tone = 'neutral'; Table = 'members' }
    )
    if ($stats.EmptyGroups) { $tiles += @{ Value = '{0:N0}' -f $stats.EmptyGroups; Label = 'empty groups'; Tone = 'bad'; Table = 'members'; Filters = @{ Membership = 'Empty' } } }
    $ownerless = @($Membership.Groups | Where-Object { -not $_.OwnerCount }).Count
    if ($ownerless) { $tiles += @{ Value = '{0:N0}' -f $ownerless; Label = 'groups without owners'; Tone = 'warn'; Table = 'groups'; Filters = @{ OwnerCount = '0' } } }

    $charts = @(
        @{ Title = 'Members by group (everyone, once)'; Items = @(& $top $people 'GroupName'); Table = 'people'; Column = 'GroupName'; Tone = 'info'; Wide = $true }
        @{ Title = 'Direct or through a nested group'; Items = @(& $top $people 'Membership'); Table = 'people'; Column = 'Membership' }
        @{ Title = 'Members by type'; Items = @(& $top $people 'MemberType'); Table = 'people'; Column = 'MemberType' }
        @{ Title = 'Users: members and guests'; Items = @(& $top @($people | Where-Object MemberType -EQ 'User') 'UserType'); Table = 'people'; Column = 'UserType'; Tone = 'warn' }
    )

    # --- The tree: each group, its owners, its members, nested groups opening to theirs ------------------
    $memberNode = {
        param($Row, [hashtable] $ByPath, [string] $Here, $Section)
        $name = if ($Row.MemberName) { $Row.MemberName } elseif ($Row.UserPrincipalName) { $Row.UserPrincipalName } else { $Row.MemberId }
        if ($Row.MemberType -eq 'Group') {
            $nestedPath = if ($Here) { "$Here > $name" } else { $name }
            if ($Section.Loops.Contains($Row.MemberId) -or -not $ByPath.Contains($nestedPath)) { return [ordered]@{ l = 'N'; n = $name; d = 'already listed above (a loop)' } }
            $inner = $ByPath[$nestedPath]
            $node = [ordered]@{ l = 'N'; n = $name; d = 'nested group'; c = @(& $count $inner.Members.Count 'member' 'members') }
            if ($inner.Error) { $node.d = "members could not be read: $($inner.Error)"; $node.x = $true }
            elseif (-not $inner.Members.Count) { $node.d = 'no members'; $node.x = $true }
            else { $node.k = @(& $children $inner $ByPath) }
            return $node
        }
        $level = switch ($Row.MemberType) { 'User' { 'U' } 'Service principal' { 'P' } 'Device' { 'D' } default { 'X' } }
        $node = [ordered]@{ l = $level; n = $name; d = $(if ($Row.UserPrincipalName) { $Row.UserPrincipalName } elseif ($Row.MemberType -ne 'User') { $Row.MemberType } else { $Row.Mail }) }
        $pills = @(
            if ($Row.UserType -eq 'Guest') { , @('GUEST', 'warn', 'A guest from another tenant') }
            if ($Row.AccountEnabled -eq $false) { , @('DISABLED', 'bad', 'The account is disabled') }
        )
        if ($pills.Count) { $node.pl = $pills }
        $node
    }
    # People first, by name; nested groups after them.
    $children = {
        param($Section, [hashtable] $ByPath)
        foreach ($r in @($Section.Members | Sort-Object -Property @{ Expression = { $_.MemberType -eq 'Group' } }, MemberName)) { & $memberNode $r $ByPath $Section.Path $Section }
    }
    $groupNodes = foreach ($group in $Membership.Groups) {
        $sections = @($Membership.Sections[$group.GroupId])
        $byPath = @{}
        foreach ($s in $sections) { if (-not $byPath.Contains($s.Path)) { $byPath[$s.Path] = $s } }
        $mine = @($people | Where-Object GroupId -EQ $group.GroupId)
        $guests = @($mine | Where-Object UserType -EQ 'Guest').Count
        $disabled = @($mine | Where-Object Account -EQ 'Disabled').Count
        $ownerNode = [ordered]@{ l = 'O'; n = 'Owners'; d = $(if (-not $group.OwnerCount) { $group.Owners }); c = @(& $count $group.OwnerCount 'owner' 'owners') }
        if ($group.OwnerCount) {
            $ownerNode.k = @(foreach ($o in ($group.Owners -split '; ')) { [ordered]@{ l = 'W'; n = $o } })
        }
        else { $ownerNode.x = $true }
        $node = [ordered]@{
            l = 'G'
            n = $group.GroupName
            d = (@($group.GroupType, $group.GroupSource, $group.MembershipType, $(if ($group.Created) { 'created ' + $group.Created.ToString('yyyy-MM-dd') })) | Where-Object { $_ }) -join ' · '
            c = @(@($mine.Count, 'in all'), @($group.DirectMembers, 'direct'), (& $count $group.NestedGroups 'nested group' 'nested groups'))
            f = @{ table = 'people'; filters = @{ GroupName = $group.GroupName } }
            k = @(, $ownerNode) + @(if ($byPath.Contains('')) { & $children $byPath[''] $byPath })
        }
        $pills = @(
            if ($guests) { , @("$guests guest$(if ($guests -ne 1) { 's' })", 'warn', 'Guests in the group, direct or nested') }
            if ($disabled) { , @("$disabled disabled", 'bad', 'Disabled accounts in the group, direct or nested') }
            if ($group.Error) { , @('not all read', 'bad', $group.Error) }
        )
        if ($pills.Count) { $node.pl = $pills }
        if (-not $mine.Count) { $node.x = $true }
        $node
    }
    $tree = @{
        Title       = 'Groups: owners, direct members and nested groups'
        # A few groups open all the way down; many open to the groups.
        OpenTo      = $(if ($rows.Count -le 300) { 'X' } else { 'G' })
        Top         = $true
        Root        = [ordered]@{ l = 'A'; n = "$($stats.Groups) group$(if ($stats.Groups -ne 1) { 's' })"; d = 'open a group for its owners and members; a nested group opens to its own'; k = @($groupNodes) }
        Levels      = @{ A = @('ALL', 'neutral'); G = @('GROUP', 'violet'); O = @('OWNERS', 'neutral'); W = @('OWNER', 'neutral'); N = @('NESTED', 'warn'); U = @('USER', 'info'); P = @('APP', 'good'); D = @('DEVICE', 'neutral'); X = @('OTHER', 'neutral') }
        Order       = @('A', 'G', 'O', 'W', 'N', 'U', 'P', 'D', 'X')
        Buttons     = @(@('Groups', 'G'), @('Everyone', 'X'))
        Placeholder = 'Find a group, person, app or owner...'
    }

    $tables = @(
        @{
            Id = 'groups'; Title = 'Groups'; Section = 'Groups'; Noun = 'groups'; File = 'groups'; GroupBy = @('GroupType', 'GroupSource', 'MembershipType')
            Note = 'One row per group: its details, owners and counts. Click a group in the tree on the overview for its members.'
            Rows = @($Membership.Groups | Select-Object -Property @{ Name = 'Created'; Expression = { if ($_.Created) { $_.Created.ToString('yyyy-MM-dd HH:mm') } } }, * -ExcludeProperty Created)
            Sort = @{ Key = 'Users'; Desc = $true }
            Columns = @(
                @{ Key = 'GroupName'; Label = 'Group' }
                @{ Key = 'GroupType'; Label = 'Type'; Facet = $true }
                @{ Key = 'GroupSource'; Label = 'Source'; Facet = $true }
                @{ Key = 'MembershipType'; Label = 'Membership type'; Type = 'badge'; Tones = @{ Assigned = 'neutral'; Dynamic = 'info'; 'Dynamic (paused)' = 'warn' }; Facet = $true }
                @{ Key = 'Created'; Label = 'Created (UTC)' }
                @{ Key = 'Owners'; Label = 'Owners'; Type = 'wide' }
                @{ Key = 'OwnerCount'; Label = 'Owner count'; Type = 'number'; Sum = $true; Format = 'N0' }
                @{ Key = 'DirectMembers'; Label = 'Direct members'; Type = 'number'; Sum = $true; Format = 'N0' }
                @{ Key = 'NestedGroups'; Label = 'Nested groups'; Type = 'number'; Sum = $true; Format = 'N0' }
                @{ Key = 'Users'; Label = 'Users (all levels)'; Type = 'number'; Sum = $true; Format = 'N0' }
                @{ Key = 'Guests'; Label = 'Guests'; Type = 'number'; Sum = $true; Format = 'N0'; Tone = 'warn' }
                @{ Key = 'DisabledUsers'; Label = 'Disabled'; Type = 'number'; Sum = $true; Format = 'N0'; Tone = 'bad' }
                @{ Key = 'Description'; Label = 'Description'; Type = 'wide' }
                @{ Key = 'MembershipRule'; Label = 'Membership rule'; Type = 'wide' }
                @{ Key = 'Mail'; Label = 'Mail' }
                @{ Key = 'Error'; Label = 'Could not read'; Type = 'wide' }
                @{ Key = 'GroupId'; Label = 'Group ID'; Type = 'mono'; Hidden = $true }
            )
        }
        @{
            Id = 'people'; Title = 'Members'; Section = 'Members'; Noun = 'members'; File = 'group-members'; GroupBy = @('GroupName', 'Membership', 'MemberType', 'UserType')
            Note = 'Everyone in each group once - users, apps, devices, contacts - Direct, Nested (Through names the nested groups) or both.'
            Rows = $people; Group = 'GroupName'
            Columns = @(
                @{ Key = 'GroupName'; Label = 'Group'; Facet = $true }
                @{ Key = 'MemberName'; Label = 'Member' }
                @{ Key = 'MemberType'; Label = 'Type'; Type = 'badge'; Tones = @{ User = 'info'; 'Service principal' = 'good'; Device = 'neutral'; Contact = 'neutral' }; Facet = $true }
                @{ Key = 'UserPrincipalName'; Label = 'User principal name' }
                @{ Key = 'Membership'; Label = 'Membership'; Type = 'badge'; Tones = @{ Direct = 'good'; Nested = 'info'; 'Direct and nested' = 'violet' }; Facet = $true }
                @{ Key = 'Through'; Label = 'Through nested group'; Type = 'wide' }
                @{ Key = 'UserType'; Label = 'Member or guest'; Type = 'badge'; Tones = @{ Guest = 'warn'; Member = 'good' }; Facet = $true }
                @{ Key = 'Account'; Label = 'Account'; Type = 'badge'; Tones = @{ Disabled = 'bad'; Enabled = 'good' }; Facet = $true }
                @{ Key = 'Mail'; Label = 'Mail' }
                @{ Key = 'JobTitle'; Label = 'Job title' }
                @{ Key = 'Department'; Label = 'Department'; Facet = $true }
                @{ Key = 'MemberId'; Label = 'Member ID'; Type = 'mono'; Hidden = $true }
                @{ Key = 'GroupId'; Label = 'Group ID'; Type = 'mono'; Hidden = $true }
            )
        }
        @{
            Id = 'members'; Title = 'All membership rows'; Section = 'All rows'; Note = 'One row per group and member at every level, nested groups included. Nested: through a group nested in it - Via shows the path.'
            Noun = 'rows'; File = 'group-membership'; Rows = $rows; GroupBy = @('GroupName', 'MemberType', 'UserType', 'Membership')
            Columns = @(
                @{ Key = 'GroupName'; Label = 'Group'; Facet = $true }
                @{ Key = 'MemberName'; Label = 'Member' }
                @{ Key = 'MemberType'; Label = 'Type'; Type = 'badge'; Tones = @{ User = 'info'; Group = 'warn'; 'Service principal' = 'violet'; Device = 'neutral' }; Facet = $true }
                @{ Key = 'UserPrincipalName'; Label = 'User principal name' }
                @{ Key = 'UserType'; Label = 'Member or guest'; Type = 'badge'; Tones = @{ Guest = 'warn'; Member = 'good' }; Facet = $true }
                @{ Key = 'Account'; Label = 'Account'; Type = 'badge'; Tones = @{ Disabled = 'bad'; Enabled = 'good' }; Facet = $true }
                @{ Key = 'Membership'; Label = 'Membership'; Type = 'badge'; Tones = @{ Direct = 'good'; Nested = 'info'; Empty = 'warn'; 'Not read' = 'bad' }; Facet = $true }
                @{ Key = 'Via'; Label = 'Via'; Type = 'wide' }
                @{ Key = 'Mail'; Label = 'Mail' }
                @{ Key = 'JobTitle'; Label = 'Job title' }
                @{ Key = 'Department'; Label = 'Department'; Facet = $true }
                @{ Key = 'GroupType'; Label = 'Group type'; Facet = $true }
                @{ Key = 'GroupSource'; Label = 'Group source'; Facet = $true }
                @{ Key = 'MemberId'; Label = 'Member ID'; Type = 'mono'; Hidden = $true }
                @{ Key = 'GroupId'; Label = 'Group ID'; Type = 'mono'; Hidden = $true }
            )
        }
    )
    $tabs = @(
        @{ Name = 'Groups'; Badge = $stats.Groups; Tone = 'violet'; Note = 'Each group''s type, source, membership type, created date, owners and counts.' }
        @{ Name = 'Members'; Badge = $people.Count; Tone = 'info'; Note = 'Everyone in each group once, direct and nested together - filter by group, or by Direct / Nested.' }
        @{ Name = 'All rows'; Badge = $rows.Count; Tone = 'neutral'; Note = 'Every membership row at every level, nested groups included, as -CsvLayout Member writes them.' }
    )
    $notices = @()
    if ($stats.Unreadable) { $notices += @{ Tone = 'warn'; Text = "The members of $($stats.Unreadable) group(s) couldn't be read; the Groups tab says why." } }
    $notices += @{ Tone = 'info'; Text = 'Open a group in the tree for its owners, direct members and nested groups - each nested group opens to its own members. People are counted once per group however many ways they are in it. Microsoft Graph, read with delegated Group.Read.All and User.Read.All.' }

    Write-AACHtmlReport -Path $Path -Title $Title -Subtitle 'Entra ID groups: details, owners, direct members and nested groups' -Fact $Detail -Tile $tiles -Chart $charts -Table $tables -Notice $notices -Tree $tree -Tab $tabs
}
