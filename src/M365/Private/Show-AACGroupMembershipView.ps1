function Show-AACGroupMembershipView {
    <#
    .SYNOPSIS
        Renders Get-AACEntraGroupMembership's result as a Spectre.Console
        view: the scope, tiles, a table of the groups, then each group in
        turn - its details and owners, its direct members, and each nested
        group's members under its path.
    .DESCRIPTION
          [ 4 groups ] [ 57 users ] [ 6 guests ] [ 2 disabled ] [ 3 nested groups ]

          Groups: name, type, source, membership type, created, owners,
          direct members, nested groups, users, guests, disabled

          -- grp-finance ---------------------------------------------
            Type        Security     Created  2024-01-15 09:30 UTC
            Source      Cloud        Owners   Ada Lovelace (ada@contoso.com); app-payroll (Service principal)
            Membership  Assigned     Members  3 direct · 1 nested group · 4 in all (1 guest, 1 disabled)

            DIRECT MEMBERS (3)
              Ada Lovelace       User          ada@contoso.com
              Gus Guest          User          gus@fabrikam.com     GUEST
              grp-finance-emea   Nested group  its members are listed below
            NESTED GROUP grp-finance-emea (3 members)
              Grace Hopper       User          grace@contoso.com    DISABLED
              ...

        Everything is listed - wrap the call in Invoke-AACPagedOutput to page
        it. Guests are amber, disabled accounts red.
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
    foreach ($header in 'Group', 'Type', 'Source', 'Membership', 'Created', 'Owners', 'Direct', 'Nested groups', 'Users', 'Guests', 'Disabled') {
        $column = [Spectre.Console.TableColumn]::new("[grey62]$header[/]")
        if ($header -in 'Owners', 'Direct', 'Nested groups', 'Users', 'Guests', 'Disabled') { $column.Alignment = [Spectre.Console.Justify]::Right; $column.NoWrap = $true }
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
            $(if ($group.MembershipType -like 'Dynamic*') { "[gold1]$(& $escape $group.MembershipType)[/]" } else { "[grey70]$(& $escape $group.MembershipType)[/]" })
            "[grey70]$(if ($group.Created) { $group.Created.ToString('yyyy-MM-dd') })[/]"
            $(if ($group.OwnerCount) { & $number $group.OwnerCount } else { '[orange1]0[/]' })
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

    # --- Each group: its details, its direct members, then each nested group's members -----------------
    $memberTable = {
        param($Section)
        $list = [Spectre.Console.Table]::new()
        $list.Border = [Spectre.Console.TableBorder]::Simple
        $list.BorderStyle = [Spectre.Console.Style]::Parse('grey35')
        foreach ($heading in 'Member', 'Type', 'Account', '') {
            $column = [Spectre.Console.TableColumn]::new("[grey62]$heading[/]")
            $column.Padding = [Spectre.Console.Padding]::new(0, 0, 3, 0)
            $null = $list.AddColumn($column)
        }
        # People first, by name; the nested groups after them.
        foreach ($r in @($Section.Members | Sort-Object -Property @{ Expression = { $_.MemberType -eq 'Group' } }, MemberName)) {
            $name = if ($r.MemberName) { $r.MemberName } elseif ($r.UserPrincipalName) { $r.UserPrincipalName } else { $r.MemberId }
            $cells = if ($r.MemberType -eq 'Group') {
                @(
                    "[bold gold1]$(& $escape $name)[/]"
                    '[gold1]Nested group[/]'
                    $(if ($Section.Loops.Contains($r.MemberId)) { '[grey50]already listed above (a loop)[/]' } else { '[grey50]its members are listed below[/]' })
                    ''
                )
            }
            else {
                $flags = @(
                    if ($r.UserType -eq 'Guest') { '[black on orange1] GUEST [/]' }
                    if ($r.AccountEnabled -eq $false) { '[white on red3] DISABLED [/]' }
                )
                @(
                    "[white]$(& $escape $name)[/]"
                    "[grey70]$(& $escape $r.MemberType)[/]"
                    "[grey50]$(& $escape $(if ($r.UserPrincipalName) { $r.UserPrincipalName } else { $r.Mail }))[/]"
                    ($flags -join ' ')
                )
            }
            [Spectre.Console.TableExtensions]::AddRow($list, [Spectre.Console.Rendering.IRenderable[]]@($cells | ForEach-Object { [Spectre.Console.Markup]::new($_) })) | Out-Null
        }
        [Spectre.Console.AnsiConsole]::Write([Spectre.Console.Padder]::new($list, [Spectre.Console.Padding]::new(2, 0, 0, 0)))
    }
    $label = { param($Text) [Spectre.Console.Markup]::new("[grey62]$Text[/]") }
    $cell = { param($Text) [Spectre.Console.Markup]::new([string]$Text) }
    foreach ($group in $Membership.Groups) {
        $people = @($Membership.People | Where-Object GroupId -EQ $group.GroupId)
        $rule = [Spectre.Console.Rule]::new("[bold mediumpurple2]$(& $escape $group.GroupName)[/]")
        $rule.Justification = [Spectre.Console.Justify]::Left
        $rule.Style = [Spectre.Console.Style]::Parse('mediumpurple2')
        [Spectre.Console.AnsiConsole]::Write($rule)

        # The details: two columns of label and value.
        $guests = @($people | Where-Object UserType -EQ 'Guest').Count
        $disabled = @($people | Where-Object { $_.AccountEnabled -eq $false }).Count
        $flagged = @(
            if ($guests) { "[orange1]$guests guest$(if ($guests -ne 1) { 's' })[/]" }
            if ($disabled) { "[red1]$disabled disabled[/]" }
        )
        $inAll = "$($group.DirectMembers) direct $($glyph.Dot) $($group.NestedGroups) nested group$(if ($group.NestedGroups -ne 1) { 's' }) $($glyph.Dot) [bold]$($people.Count)[/] in all$(if ($flagged.Count) { " ($($flagged -join ', '))" })"
        $created = if ($group.Created) { $group.Created.ToString('yyyy-MM-dd HH:mm') + ' UTC' } else { '[grey50]unknown[/]' }
        $owners = if ($group.OwnerCount) { & $escape $group.Owners } else { "[orange1]$(& $escape $group.Owners)[/]" }
        $kind = if ($group.MembershipType -like 'Dynamic*') { "[gold1]$(& $escape $group.MembershipType)[/]" } else { & $escape $group.MembershipType }
        $grid = [Spectre.Console.Grid]::new()
        foreach ($i in 1..4) { $null = $grid.AddColumn() }
        $null = $grid.AddRow([Spectre.Console.Rendering.IRenderable[]]@((& $label 'Type'), (& $cell (& $escape $group.GroupType)), (& $label 'Created'), (& $cell $created)))
        $null = $grid.AddRow([Spectre.Console.Rendering.IRenderable[]]@((& $label 'Source'), (& $cell (& $escape $group.GroupSource)), (& $label 'Owners'), (& $cell $owners)))
        $null = $grid.AddRow([Spectre.Console.Rendering.IRenderable[]]@((& $label 'Membership'), (& $cell $kind), (& $label 'Members'), (& $cell $inAll)))
        if ($group.MembershipRule) { $null = $grid.AddRow([Spectre.Console.Rendering.IRenderable[]]@((& $label 'Rule'), (& $cell "[grey70]$(& $escape $group.MembershipRule)[/]"), (& $cell ''), (& $cell ''))) }
        [Spectre.Console.AnsiConsole]::Write([Spectre.Console.Padder]::new($grid, [Spectre.Console.Padding]::new(2, 0, 0, 0)))
        [Spectre.Console.AnsiConsole]::WriteLine()

        foreach ($section in @($Membership.Sections[$group.GroupId])) {
            $count = $section.Members.Count
            $title = if ($section.Depth -eq 0) { "[bold deepskyblue1]DIRECT MEMBERS[/] [grey58]($count)[/]" } else { "[bold gold1]NESTED GROUP[/] [bold]$(& $escape $section.Path)[/] [grey58]($count member$(if ($count -ne 1) { 's' }))[/]" }
            Write-AACMarkup "  $title"
            if ($section.Error) { Write-AACMarkup "    [orange1]members could not be read: $(& $escape $section.Error)[/]" }
            elseif (-not $count) { Write-AACMarkup '    [orange1]no members[/]' }
            else { & $memberTable $section }
            [Spectre.Console.AnsiConsole]::WriteLine()
        }
    }

    if ($stats.Unreadable) {
        Write-AACMarkup "[orange1]![/] [grey58]The members of $($stats.Unreadable) group(s) couldn't be read - the reason is under each group.[/]"
    }
    Write-AACMarkup "[grey42]Add -PassThru (or pipe the command) for the rows - one per group and member; -CsvPath, -PdfPath or -HtmlPath for a report.[/]"
}
