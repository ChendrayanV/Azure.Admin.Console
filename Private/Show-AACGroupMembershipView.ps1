function Show-AACGroupMembershipView {
    <#
    .SYNOPSIS
        Renders Get-AACEntraGroupMembership's result as a Spectre.Console
        view: the scope, tiles, a table of the groups, and each group's
        members as a tree.
    .DESCRIPTION
          [ 4 groups ] [ 57 users ] [ 6 guests ] [ 2 disabled ] [ 3 nested groups ]

          Groups: name, type, source, direct members, nested groups, users,
          guests, disabled

          grp-finance  Security · Cloud · 12 direct · 30 users
          ├── Ada Lovelace  ada@contoso.com
          ├── Guest User  guest@fabrikam.com  GUEST
          └── GROUP grp-finance-emea  (nested)
              └── Grace Hopper  grace@contoso.com  DISABLED

        Everything is listed - wrap the call in Invoke-AACPagedOutput to page
        it. Guests are amber, disabled accounts red; in a console that isn't
        UTF-8 the trees are drawn in ASCII.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Membership,

        [System.Collections.IDictionary] $Scope
    )

    $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
    $glyph = Get-AACGlyph
    $stats = $Membership.Stats
    $unicode = [Spectre.Console.AnsiConsole]::Profile.Capabilities.Unicode

    $facts = [System.Collections.Generic.List[string]]::new()
    if ($Scope) { foreach ($key in $Scope.Keys) { $facts.Add("$(& $escape $key): $(& $escape $Scope[$key])") } }
    $facts.Add((Get-Date).ToString('d MMM yyyy HH:mm'))
    Write-AACMarkup "[grey58]$($facts -join " $($glyph.Dot) ")[/]"
    [Spectre.Console.AnsiConsole]::WriteLine()

    Show-AACTileRow -Tile @(
        @{ Value = '{0:N0}' -f $stats.Groups; Caption = 'groups'; Color = 'mediumpurple2' }
        @{ Value = '{0:N0}' -f $stats.Users; Caption = 'unique users'; Color = 'deepskyblue1' }
        @{ Value = '{0:N0}' -f $stats.Guests; Caption = 'guests'; Color = $(if ($stats.Guests) { 'orange1' } else { 'green3' }) }
        @{ Value = '{0:N0}' -f $stats.Disabled; Caption = 'disabled accounts'; Color = $(if ($stats.Disabled) { 'red1' } else { 'green3' }) }
        @{ Value = '{0:N0}' -f $stats.NestedGroups; Caption = 'nested groups'; Color = 'gold1' }
        @{ Value = '{0:N0}' -f $stats.EmptyGroups; Caption = 'empty groups'; Color = $(if ($stats.EmptyGroups) { 'orange1' } else { 'grey50' }) }
    )
    [Spectre.Console.AnsiConsole]::WriteLine()

    # --- The groups ----------------------------------------------------------------------------------
    $table = [Spectre.Console.Table]::new()
    $table.Border = [Spectre.Console.TableBorder]::Rounded
    $table.BorderStyle = [Spectre.Console.Style]::Parse('mediumpurple2')
    $table.Expand = $true
    $table.Title = [Spectre.Console.TableTitle]::new("[bold mediumpurple2]$($glyph.Bullet) Groups[/]")
    foreach ($header in 'Group', 'Type', 'Source', 'Direct', 'Nested groups', 'Users', 'Guests', 'Disabled') {
        $column = [Spectre.Console.TableColumn]::new("[grey62]$header[/]")
        if ($header -in 'Direct', 'Nested groups', 'Users', 'Guests', 'Disabled') { $column.Alignment = [Spectre.Console.Justify]::Right; $column.NoWrap = $true }
        $table.AddColumn($column) | Out-Null
    }
    $number = { param([int] $Value, [string] $Color) if ($Value -eq 0) { '[grey42]0[/]' } elseif ($Color) { "[$Color]$('{0:N0}' -f $Value)[/]" } else { '{0:N0}' -f $Value } }
    foreach ($group in $Membership.Groups) {
        $name = "[bold]$(& $escape $group.GroupName)[/]"
        if ($group.Error) { $name += "`n[orange1]$(& $escape $group.Error)[/]" }
        elseif ($group.MembershipRule) { $name += "`n[grey50]rule: $(& $escape $group.MembershipRule)[/]" }
        $cells = @(
            $name
            "[grey70]$(& $escape $group.GroupType)[/]"
            "[grey70]$(& $escape $group.GroupSource)[/]"
            (& $number $group.DirectMembers)
            (& $number $group.NestedGroups 'gold1')
            (& $number $group.Users 'deepskyblue1')
            (& $number $group.Guests 'orange1')
            (& $number $group.DisabledUsers 'red1')
        )
        [Spectre.Console.TableExtensions]::AddRow($table, [Spectre.Console.Rendering.IRenderable[]]@($cells | ForEach-Object { [Spectre.Console.Markup]::new($_) })) | Out-Null
    }
    [Spectre.Console.AnsiConsole]::Write($table)
    [Spectre.Console.AnsiConsole]::WriteLine()

    # --- Each group's members, nested groups under their group -----------------------------------------
    $memberLine = {
        param($Row)
        switch ($Row.MemberType) {
            'Group' {
                # A group already above it on this path: a loop, not followed again.
                $loop = $Row.MemberName -eq $Row.GroupName -or @(([string]$Row.Via -split ' > ') | Select-Object -Skip 1) -contains $Row.MemberName
                "[gold1]GROUP[/] [bold]$(& $escape $Row.MemberName)[/]$(if ($loop) { ' [grey50](a loop - already listed above)[/]' })"
            }
            'User' {
                $line = "[white]$(& $escape $Row.MemberName)[/]"
                if ($Row.UserPrincipalName) { $line += "  [grey50]$(& $escape $Row.UserPrincipalName)[/]" }
                if ($Row.UserType -eq 'Guest') { $line += '  [black on orange1] GUEST [/]' }
                if ($Row.AccountEnabled -eq $false) { $line += '  [white on red3] DISABLED [/]' }
                $line
            }
            default { "[grey70]$(& $escape $Row.MemberType)[/] [white]$(& $escape $Row.MemberName)[/]" }
        }
    }
    foreach ($group in $Membership.Groups) {
        $rows = @($Membership.Rows | Where-Object GroupId -EQ $group.GroupId)
        $header = "[bold mediumpurple2]$(& $escape $group.GroupName)[/]  [grey58]$(& $escape $group.GroupType) $($glyph.Dot) $(& $escape $group.GroupSource) $($glyph.Dot) $($group.DirectMembers) direct $($glyph.Dot) $($group.Users) user$(if ($group.Users -ne 1) { 's' })[/]"
        $tree = [Spectre.Console.Tree]::new([Spectre.Console.Markup]::new($header))
        $tree.Style = [Spectre.Console.Style]::Parse('grey42')
        if (-not $unicode) { $tree.Guide = [Spectre.Console.TreeGuide]::Ascii }
        # A node per row: nested rows hang under the group row they came through.
        $nodes = @{}
        foreach ($row in $rows) {
            if ($row.Membership -in 'Empty', 'Not read') {
                $null = $tree.Nodes.Add([Spectre.Console.TreeNode]::new([Spectre.Console.Markup]::new($(if ($row.Membership -eq 'Empty') { '[orange1]no members[/]' } else { "[orange1]members could not be read: $(& $escape $group.Error)[/]" }))))
                continue
            }
            # A nested row's Via is the path of the group row it came through.
            $parent = if ($row.Depth -gt 0 -and $nodes.Contains($row.Via)) { $nodes[$row.Via] } else { $tree }
            $node = [Spectre.Console.TreeNode]::new([Spectre.Console.Markup]::new((& $memberLine $row)))
            $null = $parent.Nodes.Add($node)
            if ($row.MemberType -eq 'Group') { $nodes["$(if ($row.Via) { $row.Via } else { $group.GroupName }) > $($row.MemberName)"] = $node }
        }
        [Spectre.Console.AnsiConsole]::Write($tree)
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    if ($stats.Unreadable) {
        Write-AACMarkup "[orange1]![/] [grey58]The members of $($stats.Unreadable) group(s) couldn't be read - the reason is under each group.[/]"
    }
    Write-AACMarkup "[grey42]Add -PassThru (or pipe the command) for the rows - one per group and member; -CsvPath, -PdfPath or -HtmlPath for a report.[/]"
}
