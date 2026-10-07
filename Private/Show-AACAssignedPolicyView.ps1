function Show-AACAssignedPolicyView {
    <#
    .SYNOPSIS
        Renders Get-AACAssignedPolicy's inventory (ConvertTo-AACAssignedPolicy)
        as a Spectre.Console view.
    .DESCRIPTION
        The scope; tiles (assignments, initiatives, policies, parameters and
        how many are assigned, assignments not enforced, inherited, custom);
        a table of the assignments by scope - definition, enforcement,
        parameters assigned and the resource types; a bar chart of the
        resource types with the most assignments; and each assignment's
        parameters as a tree: assigned values in green, defaults in grey,
        parameters with no value in orange. An assignment with more than
        -ShowDefault parameters lists the assigned ones and counts the rest,
        which keep their defaults (-NoDisplay or -HtmlPath has every one).
        With -ExpandPolicySet, an initiative's node lists its member
        policies, each with its effect and its other parameters' effective
        values.
        Output goes straight to the Spectre console; wrap the call in
        Invoke-AACPagedOutput to page it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Inventory,

        [System.Collections.IDictionary] $Scope,

        # Up to this many parameters, defaults are listed too.
        [int] $ShowDefault = 12,

        # List each initiative's member policies, up to -ShowMember of them.
        [switch] $ExpandPolicySet,

        [int] $ShowMember = 40
    )

    $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
    $glyph = Get-AACGlyph
    $unicode = [Spectre.Console.AnsiConsole]::Profile.Capabilities.Unicode
    $stats = $Inventory.Stats
    $assignments = @($Inventory.Assignments)
    $shorten = { param([string] $Text, [int] $Max) if ($Text.Length -le $Max) { $Text } else { $Text.Substring(0, $Max - 3) + '...' } }
    $types = {
        param([string] $Text, [int] $Show = 2)
        if (-not $Text) { return '[grey50]-[/]' }
        if ($Text -eq 'All' -or $Text.StartsWith('All except')) { return "[grey62]$(& $escape (& $shorten $Text 60))[/]" }
        $list = @($Text -split ', ')
        $shown = ($list | Select-Object -First $Show | ForEach-Object { "[turquoise2]$(& $escape ($_ -replace '^Microsoft\.', ''))[/]" }) -join "`n"
        if ($list.Count -gt $Show) { $shown += "`n[grey50]+$($list.Count - $Show) more[/]" }
        $shown
    }
    $scopeColor = @{ 'Management group' = 'mediumpurple2'; Subscription = 'deepskyblue1'; 'Resource group' = 'springgreen2'; Resource = 'gold1'; Other = 'grey62' }

    $facts = [System.Collections.Generic.List[string]]::new()
    if ($script:AACSession) { $facts.Add("[white]$(& $escape $script:AACSession.Account)[/]") }
    if ($Scope) { foreach ($key in $Scope.Keys) { $facts.Add("$(& $escape $key): $(& $escape $Scope[$key])") } }
    $facts.Add((Get-Date).ToString('d MMM yyyy HH:mm'))
    Write-AACMarkup "[grey58]$($facts -join " $($glyph.Dot) ")[/]"
    [Spectre.Console.AnsiConsole]::WriteLine()

    if (-not $assignments.Count) {
        Show-AACPanel -Content '[bold]No policy assignments[/] [grey58]were found in this scope.[/]' -BorderColor 'grey50' -AllowMarkup
        return
    }

    # --- Tiles ------------------------------------------------------------------------------------------
    Show-AACTileRow -Tile @(
        @{ Value = '{0:N0}' -f $stats.Assignments; Caption = 'assignments'; Color = 'deepskyblue1' }
        @{ Value = '{0:N0}' -f $stats.Initiatives; Caption = 'initiatives'; Color = 'mediumpurple2' }
        @{ Value = '{0:N0}' -f $stats.Policies; Caption = 'single policies'; Color = 'turquoise2' }
        @{ Value = "$('{0:N0}' -f $stats.Assigned) / $('{0:N0}' -f $stats.Parameters)"; Caption = 'parameters assigned'; Color = 'springgreen2' }
        @{ Value = '{0:N0}' -f $stats.DoNotEnforce; Caption = 'not enforced'; Color = $(if ($stats.DoNotEnforce) { 'orange1' } else { 'green3' }) }
        if ($stats.Inherited) { @{ Value = '{0:N0}' -f $stats.Inherited; Caption = 'inherited'; Color = 'gold1' } }
        @{ Value = '{0:N0}' -f $stats.Custom; Caption = 'custom definitions'; Color = 'grey70' }
    )
    [Spectre.Console.AnsiConsole]::WriteLine()

    # --- The assignments ----------------------------------------------------------------------------------
    $table = [Spectre.Console.Table]::new()
    $table.Border = [Spectre.Console.TableBorder]::Rounded
    $table.BorderStyle = [Spectre.Console.Style]::Parse('deepskyblue3_1')
    $table.Expand = $true
    $table.Title = [Spectre.Console.TableTitle]::new("[bold]$($glyph.Bullet) Policy assignments[/] [grey58]$($glyph.Dot) by scope[/]")
    foreach ($header in 'Assignment', 'Assigned at', 'Definition', 'Enforced', 'Params', 'Resource types') {
        $column = [Spectre.Console.TableColumn]::new("[grey62]$header[/]")
        if ($header -eq 'Params') { $column.Alignment = [Spectre.Console.Justify]::Right }
        if ($header -in 'Enforced', 'Params') { $column.NoWrap = $true }
        $table.AddColumn($column) | Out-Null
    }
    foreach ($a in $assignments) {
        $kind = if ($a.DefinitionType -eq 'PolicySet') { "[mediumpurple2]Initiative[/][grey50] $($glyph.Dot) $($a.Members) policies[/]" } else { '[turquoise2]Policy[/]' }
        $cells = @(
            "[bold]$(& $escape $a.AssignmentDisplayName)[/]$(if ($a.AssignmentDisplayName -ne $a.AssignmentName) { "`n[grey50]$(& $escape $a.AssignmentName)[/]" })"
            "[$($scopeColor[$a.ScopeType])]$(& $escape $a.ScopeType)[/]`n[grey85]$(& $escape $a.ScopeName)[/]$(if ($a.Inherited) { "`n[gold1]inherited[/]" })"
            "$(& $escape (& $shorten $a.DefinitionDisplayName 60))`n$kind$(if ($a.PolicyType) { "[grey50] $($glyph.Dot) $(& $escape $a.PolicyType)[/]" })$(if ($a.Category) { "[grey50] $($glyph.Dot) $(& $escape $a.Category)[/]" })"
            $(if ($a.EnforcementMode -eq 'DoNotEnforce') { '[orange1]Off[/]' } else { '[green3]On[/]' })
            $(if ($a.Parameters) { "[springgreen2]$($a.Assigned)[/][grey50] / $($a.Parameters)[/]" } else { '[grey50]-[/]' })
            (& $types $a.ResourceType)
        )
        [Spectre.Console.TableExtensions]::AddRow($table, [Spectre.Console.Rendering.IRenderable[]]@($cells | ForEach-Object { [Spectre.Console.Markup]::new($_) })) | Out-Null
    }
    [Spectre.Console.AnsiConsole]::Write($table)
    [Spectre.Console.AnsiConsole]::WriteLine()

    # --- Resource types ------------------------------------------------------------------------------------
    $bars = @($stats.ResourceTypes | Select-Object -First 12 | ForEach-Object { @{ Label = ($_.Label -replace '^Microsoft\.', ''); Value = $_.Value } })
    if ($bars.Count) {
        Show-AACBarChart -Item $bars -Title 'Resource types with the most assignments'
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    # --- Each assignment's parameters ------------------------------------------------------------------------
    $byAssignment = @{}
    foreach ($row in $Inventory.Rows) {
        if (-not $row.ParameterName) { continue }
        if (-not $byAssignment.ContainsKey($row.AssignmentId)) { $byAssignment[$row.AssignmentId] = [System.Collections.Generic.List[object]]::new() }
        $byAssignment[$row.AssignmentId].Add($row)
    }
    $byMember = @{}
    foreach ($row in @($Inventory.Members)) {
        if ($row.DefinitionType -ne 'PolicySet') { continue }
        if (-not $byMember.ContainsKey($row.AssignmentId)) { $byMember[$row.AssignmentId] = [System.Collections.Generic.List[object]]::new() }
        $byMember[$row.AssignmentId].Add($row)
    }
    $tree = [Spectre.Console.Tree]::new([Spectre.Console.Markup]::new("[bold deepskyblue1]$($glyph.Bullet) Parameters[/] [grey58]$($glyph.Dot) [/][springgreen2]assigned[/][grey58], [/][grey62]default[/][grey58], [/][orange1]not set[/]"))
    $tree.Style = [Spectre.Console.Style]::Parse('grey42')
    if (-not $unicode) { $tree.Guide = [Spectre.Console.TreeGuide]::Ascii }
    foreach ($a in $assignments) {
        $rows = @(if ($byAssignment.ContainsKey($a.AssignmentId)) { $byAssignment[$a.AssignmentId] })
        $node = [Spectre.Console.TreeNode]::new([Spectre.Console.Markup]::new("[bold]$(& $escape $a.AssignmentDisplayName)[/] [grey50]$(& $escape $a.ScopeName)$(if (-not $rows.Count) { " $($glyph.Dot) no parameters" })[/]"))
        $tree.Nodes.Add($node)
        $shown = if ($rows.Count -le $ShowDefault) { $rows } else { @($rows | Where-Object ValueSource -NE 'Default') }
        $width = [Math]::Min(40, [Math]::Max(10, (@($shown | ForEach-Object { $_.ParameterName.Length }) + 0 | Measure-Object -Maximum).Maximum))
        foreach ($row in $shown) {
            $color = switch ($row.ValueSource) { 'Assigned' { 'springgreen2' } 'Default' { 'grey62' } default { 'orange1' } }
            $value = if ($row.ValueSource -eq 'Not set') { '(not set)' } elseif ($row.EffectiveValue -eq '') { '(empty)' } elseif ($row.EffectiveValue -match '^/subscriptions/[^,]+/providers/[^,]+/([^/,]+)$') { ".../$($Matches[1])" } else { & $shorten $row.EffectiveValue 140 }
            $default = if ($row.ValueSource -eq 'Assigned' -and $row.DefaultValue -ne '' -and $row.DefaultValue -ne $row.EffectiveValue) { " [grey42](default $(& $escape (& $shorten $row.DefaultValue 40)))[/]" } else { '' }
            $node.Nodes.Add([Spectre.Console.TreeNode]::new([Spectre.Console.Markup]::new("[white]$(& $escape $row.ParameterName.PadRight($width))[/] [$color]$(& $escape $value)[/]$default"))) | Out-Null
        }
        $hidden = $rows.Count - @($shown).Count
        if ($hidden -gt 0) {
            $node.Nodes.Add([Spectre.Console.TreeNode]::new([Spectre.Console.Markup]::new("[grey50]$($glyph.Chevron) $hidden more at their default value[/]"))) | Out-Null
        }
        if ($a.DefinitionType -ne 'PolicySet' -or -not $a.Members) { continue }
        if (-not $ExpandPolicySet) {
            $node.Nodes.Add([Spectre.Console.TreeNode]::new([Spectre.Console.Markup]::new("[grey50]$($glyph.Chevron) $($a.Members) member policies (-ExpandPolicySet lists them)[/]"))) | Out-Null
            continue
        }
        # The initiative's policies: effect, and the parameters other than the effect.
        $policies = [Spectre.Console.TreeNode]::new([Spectre.Console.Markup]::new("[mediumpurple2]Policies[/] [grey50]$($a.Members)[/]"))
        $node.Nodes.Add($policies) | Out-Null
        $members = @(@(if ($byMember.ContainsKey($a.AssignmentId)) { $byMember[$a.AssignmentId] }) | Group-Object ReferenceId, PolicyId)
        foreach ($group in $members | Select-Object -First $ShowMember) {
            $first = $group.Group[0]
            $effect = if ($first.Effect) { " [$(if ($first.Effect -eq 'deny') { 'orange1' } elseif ($first.Effect -eq 'disabled') { 'grey50' } else { 'deepskyblue1' })]$(& $escape $first.Effect)[/]" } else { '' }
            $policy = [Spectre.Console.TreeNode]::new([Spectre.Console.Markup]::new("[white]$(& $escape (& $shorten $first.PolicyDisplayName 90))[/]$effect"))
            $policies.Nodes.Add($policy) | Out-Null
            $parameterRows = @($group.Group | Where-Object { $_.ParameterName -and $_.ParameterName -ne 'effect' })
            $width = [Math]::Min(40, [Math]::Max(10, (@($parameterRows | ForEach-Object { $_.ParameterName.Length }) + 0 | Measure-Object -Maximum).Maximum))
            foreach ($row in $parameterRows) {
                $color = switch ($row.ValueSource) { 'Assigned' { 'springgreen2' } { $_ -in 'Initiative', 'Initiative default', 'Policy default', 'Expression' } { 'grey62' } default { 'orange1' } }
                $value = if ($row.ValueSource -eq 'Not set') { '(not set)' } elseif ($row.EffectiveValue -eq '') { '(empty)' } else { & $shorten $row.EffectiveValue 120 }
                $policy.Nodes.Add([Spectre.Console.TreeNode]::new([Spectre.Console.Markup]::new("[white]$(& $escape $row.ParameterName.PadRight($width))[/] [$color]$(& $escape $value)[/] [grey42]$(& $escape $row.ValueSource.ToLowerInvariant())[/]"))) | Out-Null
            }
        }
        if ($members.Count -gt $ShowMember) {
            $policies.Nodes.Add([Spectre.Console.TreeNode]::new([Spectre.Console.Markup]::new("[grey50]$($glyph.Chevron) $($members.Count - $ShowMember) more (-NoDisplay or -HtmlPath has every one)[/]"))) | Out-Null
        }
    }
    [Spectre.Console.AnsiConsole]::Write($tree)
    [Spectre.Console.AnsiConsole]::WriteLine()

    foreach ($notice in @($Inventory.Notice)) { Write-AACMarkup "[orange1]$(& $escape $notice)[/]" }
    Write-AACMarkup "[grey42]Add -PassThru (or pipe the command) for one row per assignment and parameter$(if ($ExpandPolicySet) { ' (here: per policy in force and parameter)' }); -CsvPath and -HtmlPath write every one.[/]"
}
