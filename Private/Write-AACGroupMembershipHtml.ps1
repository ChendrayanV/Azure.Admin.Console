function Write-AACGroupMembershipHtml {
    <#
    .SYNOPSIS
        Writes Get-AACEntraGroupMembership's result as an interactive HTML
        report: tiles and charts that filter the tables, a table of groups
        and one of every membership - searchable, filterable and
        downloadable as CSV.
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
    $rows = @($Membership.Rows | ForEach-Object {
            $_ | Select-Object -Property *, @{ Name = 'Account'; Expression = { if ($_.MemberType -ne 'User') { '' } elseif ($_.AccountEnabled -eq $false) { 'Disabled' } else { 'Enabled' } } }
        })
    $users = @($rows | Where-Object MemberType -EQ 'User')
    $top = {
        param([object[]] $Items, [string] $Property, [int] $First = 12)
        @($Items | Group-Object -Property $Property | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, Name | Select-Object -First $First | ForEach-Object {
                @{ Label = $(if ($_.Name) { $_.Name } else { '(none)' }); Value = $_.Count; Filter = $_.Name }
            })
    }

    $tiles = @(
        @{ Value = '{0:N0}' -f $stats.Groups; Label = 'groups'; Tone = 'violet'; Table = 'groups' }
        @{ Value = '{0:N0}' -f $stats.Rows; Label = 'membership rows'; Tone = 'neutral'; Table = 'members' }
        @{ Value = '{0:N0}' -f $stats.Users; Label = 'unique users'; Tone = 'info'; Table = 'members'; Filters = @{ MemberType = 'User' } }
        @{ Value = '{0:N0}' -f $stats.Guests; Label = 'guests'; Tone = $(if ($stats.Guests) { 'warn' } else { 'good' }); Table = 'members'; Filters = @{ UserType = 'Guest' } }
        @{ Value = '{0:N0}' -f $stats.Disabled; Label = 'disabled accounts'; Tone = $(if ($stats.Disabled) { 'bad' } else { 'good' }); Table = 'members'; Filters = @{ Account = 'Disabled' } }
        @{ Value = '{0:N0}' -f $stats.NestedGroups; Label = 'nested groups'; Tone = 'warn'; Table = 'members'; Filters = @{ MemberType = 'Group' } }
    )
    if ($stats.EmptyGroups) { $tiles += @{ Value = '{0:N0}' -f $stats.EmptyGroups; Label = 'empty groups'; Tone = 'bad'; Table = 'members'; Filters = @{ Membership = 'Empty' } } }

    $charts = @(
        @{ Title = 'Users by group'; Items = @(& $top $users 'GroupName'); Table = 'members'; Column = 'GroupName'; Tone = 'info'; Wide = $true }
        @{ Title = 'Members by type'; Items = @(& $top @($rows | Where-Object MemberType) 'MemberType'); Table = 'members'; Column = 'MemberType' }
        @{ Title = 'Users: members and guests'; Items = @(& $top $users 'UserType'); Table = 'members'; Column = 'UserType'; Tone = 'warn' }
        @{ Title = 'Direct or through a nested group'; Items = @(& $top @($rows | Where-Object MemberType) 'Membership'); Table = 'members'; Column = 'Membership' }
    )

    $tables = @(
        @{
            Id = 'groups'; Title = 'Groups'; Noun = 'groups'; File = 'groups'; Rows = @($Membership.Groups); GroupBy = @('GroupType', 'GroupSource')
            Sort = @{ Key = 'Users'; Desc = $true }
            Columns = @(
                @{ Key = 'GroupName'; Label = 'Group' }
                @{ Key = 'GroupType'; Label = 'Type'; Facet = $true }
                @{ Key = 'GroupSource'; Label = 'Source'; Facet = $true }
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
            Id = 'members'; Title = 'Memberships'; Note = 'One row per group and member. Nested: through a group nested in it - Via shows the path.'
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
    $notices = @()
    if ($stats.Unreadable) { $notices += @{ Tone = 'warn'; Text = "The members of $($stats.Unreadable) group(s) couldn't be read; the Groups table says why." } }
    $notices += @{ Tone = 'info'; Text = 'Users are counted once per group however many nested groups they are in. Microsoft Graph, read with delegated Group.Read.All and User.Read.All.' }

    Write-AACHtmlReport -Path $Path -Title $Title -Subtitle 'Entra ID groups and everyone in them - direct and nested' -Fact $Detail -Tile $tiles -Chart $charts -Table $tables -Notice $notices
}
