function Show-AACAssessmentView {
    <#
    .SYNOPSIS
        Renders the end of an Invoke-AACAssessment run as a Spectre.Console
        view: what was found, what needs attention, and where the reports are.
    .DESCRIPTION
        The scope; tiles (subscriptions, resource groups, resources, types,
        Advisor High, retirements, Defender High, outages, unattached);
        the inventory by category (resources, sheets, the commonest types);
        the most common resource types as a bar chart; what needs attention
        (the next retirements, High-impact Advisor and Defender
        recommendations, recent outages, sheets that couldn't be read); and
        the files written, with how long each phase took. Output goes
        straight to the Spectre console; wrap the call in
        Invoke-AACPagedOutput to page it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Assessment,

        [System.Collections.IDictionary] $Scope,

        [object[]] $File = @(),

        [System.Collections.IDictionary] $Timing
    )

    $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
    $glyph = Get-AACGlyph
    $stats = $Assessment.Stats
    $find = { param([string] $Name) @($Assessment.Sheets | Where-Object { $_.Sheet -eq $Name }) | Select-Object -First 1 }

    $facts = [System.Collections.Generic.List[string]]::new()
    if ($script:AACSession) { $facts.Add("[white]$(& $escape $script:AACSession.Account)[/]") }
    if ($Scope) { foreach ($key in $Scope.Keys) { $facts.Add("$(& $escape $key): $(& $escape $Scope[$key])") } }
    $facts.Add((Get-Date).ToString('d MMM yyyy HH:mm'))
    Write-AACMarkup "[grey58]$($facts -join " $($glyph.Dot) ")[/]"
    [Spectre.Console.AnsiConsole]::WriteLine()

    Show-AACTileRow -Tile @(
        @{ Value = '{0:N0}' -f $stats.Subscriptions; Caption = 'subscriptions'; Color = 'deepskyblue1' }
        @{ Value = '{0:N0}' -f $stats.ResourceGroups; Caption = 'resource groups'; Color = 'grey70' }
        @{ Value = '{0:N0}' -f $stats.Resources; Caption = 'resources'; Color = 'deepskyblue1' }
        @{ Value = '{0:N0}' -f $stats.ResourceTypes; Caption = 'resource types'; Color = 'mediumpurple2' }
        if ($null -ne $stats.Advisor) { @{ Value = '{0:N0}' -f $stats.AdvisorHigh; Caption = 'Advisor High'; Color = $(if ($stats.AdvisorHigh) { 'red1' } else { 'green3' }) } }
        @{ Value = '{0:N0}' -f $stats.Retirements; Caption = 'retiring features'; Color = $(if ($stats.Retirements) { 'orange1' } else { 'green3' }) }
        if ($null -ne $stats.Security) { @{ Value = '{0:N0}' -f $stats.SecurityHigh; Caption = 'Defender High'; Color = $(if ($stats.SecurityHigh) { 'red1' } else { 'green3' }) } }
        @{ Value = '{0:N0}' -f $stats.Orphans; Caption = 'unattached / empty'; Color = $(if ($stats.Orphans) { 'orange1' } else { 'green3' }) }
        if ($null -ne $stats.CostMonthToDate) { @{ Value = '{0:N0} {1}' -f $stats.CostMonthToDate, $stats.Currency; Caption = 'cost this month'; Color = 'green3' } }
    )
    [Spectre.Console.AnsiConsole]::WriteLine()

    # --- The inventory by category ----------------------------------------------------------------------------
    $all = & $find 'All resources'
    $rows = @(if ($all) { $all.Rows })
    if ($rows.Count) {
        $table = [Spectre.Console.Table]::new()
        $table.Border = [Spectre.Console.TableBorder]::Rounded
        $table.BorderStyle = [Spectre.Console.Style]::Parse('deepskyblue3_1')
        $table.Expand = $true
        $table.Title = [Spectre.Console.TableTitle]::new("[bold]$($glyph.Bullet) Inventory by category[/]")
        foreach ($header in 'Category', 'Resources', 'Sheets', 'Most common types') {
            $column = [Spectre.Console.TableColumn]::new("[grey62]$header[/]")
            if ($header -eq 'Resources') { $column.Alignment = [Spectre.Console.Justify]::Right }
            $table.AddColumn($column) | Out-Null
        }
        foreach ($group in $rows | Group-Object Category | Sort-Object Count -Descending) {
            $sheets = @($Assessment.Sheets | Where-Object { $_.Kind -eq 'Inventory' -and $_.Category -eq $group.Name -and @($_.Rows).Count })
            $types = @($group.Group | Group-Object Type | Sort-Object Count -Descending | Select-Object -First 3 | ForEach-Object { "$(($_.Name -split '/')[-1]) ($($_.Count))" })
            [Spectre.Console.TableExtensions]::AddRow($table, [Spectre.Console.Rendering.IRenderable[]]@(
                    [Spectre.Console.Markup]::new("[white]$(& $escape $group.Name)[/]")
                    [Spectre.Console.Markup]::new(('{0:N0}' -f $group.Count))
                    [Spectre.Console.Markup]::new("[grey70]$(& $escape ((@($sheets | ForEach-Object { $_.Sheet })) -join ', '))[/]")
                    [Spectre.Console.Markup]::new("[grey58]$(& $escape ($types -join ', '))[/]")
                )) | Out-Null
        }
        [Spectre.Console.AnsiConsole]::Write($table)
        [Spectre.Console.AnsiConsole]::WriteLine()
        $top = @($rows | Group-Object Type | Sort-Object Count -Descending | Select-Object -First 12 | ForEach-Object { @{ Label = $_.Name; Value = $_.Count } })
        Show-AACBarChart -Item $top -Title 'Most common resource types'
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    # --- What needs attention ---------------------------------------------------------------------------------
    $lines = [System.Collections.Generic.List[string]]::new()
    $retirements = & $find 'Retirements'
    foreach ($item in @(if ($retirements) { $retirements.Rows }) | Select-Object -First 5) {
        $lines.Add("  [orange1]RETIRING[/] [white]$(& $escape $item.Resource)[/] [grey50]$(& $escape $item.'Retirement date')[/] [grey70]$(& $escape $item.Retiring)[/]")
    }
    $advisor = & $find 'Advisor recommendations'
    foreach ($item in @(if ($advisor) { $advisor.Rows | Where-Object Impact -EQ 'High' }) | Select-Object -First 5) {
        $lines.Add("  [red1]ADVISOR [/] [white]$(& $escape $item.Resource)[/] [grey50]$(& $escape $item.Category)[/] [grey70]$(& $escape $item.Problem)[/]")
    }
    $security = & $find 'Security recommendations'
    foreach ($item in @(if ($security) { $security.Rows | Where-Object Severity -EQ 'High' }) | Select-Object -First 5) {
        $lines.Add("  [red1]DEFENDER[/] [white]$(& $escape $item.Resource)[/] [grey70]$(& $escape $item.Recommendation)[/]")
    }
    $outages = & $find 'Outages'
    foreach ($item in @(if ($outages) { $outages.Rows }) | Select-Object -First 3) {
        $lines.Add("  [orange1]OUTAGE  [/] [white]$(& $escape $item.'Tracking ID')[/] [grey50]$(& $escape $item.Started)[/] [grey70]$(& $escape $item.Title)[/]")
    }
    foreach ($notice in @($Assessment.Notices)) { $lines.Add("  [orange1]NOT READ[/] [grey70]$(& $escape $notice)[/]") }
    if ($lines.Count) {
        Write-AACMarkup "[bold]$($glyph.Bullet) Needs attention[/] [grey58]$($glyph.Dot) the first few of each - the reports have them all[/]"
        foreach ($line in $lines) { Write-AACMarkup $line }
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    # --- The reports ----------------------------------------------------------------------------------------
    $content = [System.Collections.Generic.List[string]]::new()
    $byKind = @($File | Where-Object { $_ } | Group-Object { switch -Wildcard ($_.Name) { '*.csv' { 'CSV'; break } '*-Network.html' { 'Diagram'; break } '*-Organization.html' { 'Diagram'; break } '*-Resources.html' { 'Diagram'; break } '*.html' { 'HTML'; break } '*.pdf' { 'PDF'; break } default { 'File' } } })
    foreach ($group in $byKind) {
        if ($group.Name -eq 'CSV') { $content.Add("[grey58]CSV[/]      $($group.Count) file(s) in [link]$(& $escape $group.Group[0].DirectoryName)[/]") }
        else { foreach ($item in $group.Group) { $content.Add("[grey58]$($group.Name.PadRight(8))[/] [link]$(& $escape $item.FullName)[/]") } }
    }
    if ($Timing -and $Timing.Count) { $content.Add("[grey58]Took[/]     $((@($Timing.Keys | ForEach-Object { "$_ $('{0:mm\:ss}' -f $Timing[$_])" })) -join ' · ')") }
    if ($content.Count) { Show-AACCallout Success -Message ($content -join "`n") -Title 'Reports' }
}
