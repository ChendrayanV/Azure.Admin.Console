function Show-AACDashboardView {
    <#
    .SYNOPSIS
        Draws Show-AACDashboard's view: the headline status, tiles and
        scores, the session and health side by side, security and
        governance, cost, the subscriptions, regions and resource types,
        Advisor, Service Health events, unhealthy resources, the change
        timeline and recent changes - and what to do next. -Section draws
        only those sections; a section whose data wasn't read is left out.
    .DESCRIPTION
        Every state is drawn with Get-AACStatus's symbols and colours (with
        an ASCII fallback), so it reads the same as the rest of the module
        and in any console.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Dashboard,

        [System.Collections.IDictionary] $Scope = @{},

        [string[]] $Section = @('Health', 'Security', 'Policy', 'Governance', 'Advisor', 'Estate', 'Changes', 'Cost')
    )

    $d = $Dashboard
    $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
    $glyph = Get-AACGlyph
    $mark = { param([string] $Status) (Get-AACStatus $Status).Markup }
    $when = { param($Time) if ($Time -is [datetime]) { if ($Time.Date -eq [datetime]::Today) { $Time.ToString('HH:mm') } else { $Time.ToString('d MMM HH:mm') } } else { '' } }
    $newTable = {
        param([string] $Title, [string[]] $Column)
        $table = [Spectre.Console.Table]::new()
        $table.Border = [Spectre.Console.TableBorder]::Rounded
        $table.BorderStyle = [Spectre.Console.Style]::Parse('grey35')
        $table.Title = [Spectre.Console.TableTitle]::new("[bold]$(& $escape $Title)[/]")
        foreach ($name in $Column) { $null = $table.AddColumn([Spectre.Console.TableColumn]::new("[grey70]$(& $escape $name)[/]")) }
        $table
    }
    $addRow = { param($Table, [string[]] $Cell) $null = [Spectre.Console.TableExtensions]::AddRow($Table, [Spectre.Console.Rendering.IRenderable[]]@($Cell | ForEach-Object { [Spectre.Console.Markup]::new($_) })) }
    $want = { param([string] $Name) $Section -contains $Name }
    $has = { param($Object, [string] $Name) $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name] -and $null -ne $Object.$Name }
    # A sparkline: block characters in a Unicode console, ASCII steps otherwise.
    $spark = {
        param([double[]] $Values)
        $steps = if ([Spectre.Console.AnsiConsole]::Profile.Capabilities.Unicode) { @([char]0x2581, [char]0x2582, [char]0x2583, [char]0x2584, [char]0x2585, [char]0x2586, [char]0x2587, [char]0x2588) } else { @('.', ':', '-', '=', '+', '*', '#', '@') }
        $clean = @($Values | ForEach-Object { if ([double]::IsNaN($_) -or [double]::IsInfinity($_) -or $_ -lt 0) { 0.0 } else { [double]$_ } })
        $max = 0.0; foreach ($v in $clean) { if ($v -gt $max) { $max = $v } }
        -join @(foreach ($v in $clean) { if ($max -le 0) { $steps[0] } else { $steps[[int][Math]::Min([double]7, [Math]::Floor($v / $max * 7.999))] } })
    }
    $scoreColor = { param($Value, [double] $Good = 80, [double] $Warn = 60) if ($null -eq $Value) { 'grey50' } elseif ($Value -ge $Good) { 'green3' } elseif ($Value -ge $Warn) { 'orange1' } else { 'red1' } }

    # --- Who, what, when -------------------------------------------------------------------------------------
    $facts = [System.Collections.Generic.List[string]]::new()
    if ($d.Account) { $facts.Add("[white]$(& $escape $d.Account)[/]") }
    if ($d.TenantId) { $facts.Add("tenant $(& $escape $d.TenantId)") }
    foreach ($key in $Scope.Keys) { $facts.Add("$(& $escape $key): $(& $escape $Scope[$key])") }
    $facts.Add($d.GeneratedAt.ToString('d MMM yyyy HH:mm'))
    Write-AACMarkup "[grey58]$($facts -join " $($glyph.Dot) ")[/]"
    [Spectre.Console.AnsiConsole]::WriteLine()
    $headline = @{ Success = 'Healthy'; Warning = 'Needs attention'; Failed = 'Action needed' }[$d.Status]
    Write-AACStatusLine $d.Status "[bold]$headline[/] [grey70]$(& $escape $d.Headline)[/]" -Markup
    [Spectre.Console.AnsiConsole]::WriteLine()

    $changes = $d.Changes.Created + $d.Changes.Updated + $d.Changes.Deleted
    Show-AACTileRow -Tile @(
        @{ Value = '{0:N0}' -f @($d.Subscriptions).Count; Caption = 'subscriptions'; Color = 'springgreen2' }
        @{ Value = '{0:N0}' -f $d.Resources; Caption = 'resources'; Color = 'deepskyblue1' }
        @{ Value = '{0:N0}' -f $d.ResourceGroups; Caption = 'resource groups'; Color = 'gold1' }
        @{ Value = '{0:N0}' -f $d.Regions; Caption = 'regions'; Color = 'hotpink' }
        @{ Value = '{0:N0}' -f ($d.Health.Unavailable + $d.Health.Degraded); Caption = 'unhealthy'; Color = $(if ($d.Health.Unavailable) { 'red1' } else { 'orange1' }) }
        @{ Value = '{0:N0}' -f $d.AdvisorHigh; Caption = 'Advisor High'; Color = 'orange1' }
        @{ Value = '{0:N0}' -f $changes; Caption = "changes in $($d.Hours)h"; Color = 'mediumpurple2' }
    )
    [Spectre.Console.AnsiConsole]::WriteLine()
    $scoreTiles = [System.Collections.Generic.List[object]]::new()
    if ((& $has $d 'Score') -and $null -ne $d.Score.Value) { $scoreTiles.Add(@{ Value = "$($d.Score.Value)"; Caption = 'estate score (of 100)'; Color = (& $scoreColor $d.Score.Value) }) }
    if ((& $want 'Security') -and (& $has $d 'Security') -and $null -ne $d.Security.SecureScore) { $scoreTiles.Add(@{ Value = "$($d.Security.SecureScore)%"; Caption = 'secure score'; Color = (& $scoreColor $d.Security.SecureScore) }) }
    if ((& $want 'Policy') -and (& $has $d 'Policy') -and $null -ne $d.Policy.Compliance) { $scoreTiles.Add(@{ Value = "$($d.Policy.Compliance)%"; Caption = 'policy compliance'; Color = (& $scoreColor $d.Policy.Compliance) }) }
    if ((& $want 'Advisor') -and (& $has $d 'AdvisorScore')) { $scoreTiles.Add(@{ Value = "$($d.AdvisorScore)"; Caption = 'Advisor score'; Color = (& $scoreColor $d.AdvisorScore) }) }
    if ((& $want 'Governance') -and (& $has $d 'Governance') -and $d.Governance.ClosestLimit) { $scoreTiles.Add(@{ Value = "$($d.Governance.ClosestLimit.Percent)%"; Caption = 'closest limit'; Color = $(if ($d.Governance.ClosestLimit.Percent -ge 95) { 'red1' } elseif ($d.Governance.ClosestLimit.Percent -ge 80) { 'orange1' } else { 'green3' }) }) }
    if ((& $want 'Cost') -and (& $has $d 'Cost')) { $scoreTiles.Add(@{ Value = ('{0:N0}' -f $d.Cost.MonthToDate); Caption = "$($d.Cost.Currency) month to date"; Color = $(if ($null -ne $d.Cost.ChangePercent -and $d.Cost.ChangePercent -gt 10) { 'orange1' } else { 'deepskyblue1' }) }) }
    if ($scoreTiles.Count) {
        Show-AACTileRow -Tile $scoreTiles.ToArray()
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    # --- Session and health, side by side ------------------------------------------------------------------------
    $sessionLines = [System.Collections.Generic.List[string]]::new()
    $sessionLines.Add("[grey58]Account[/]   $(& $escape $(if ($d.Account) { $d.Account } else { '-' }))")
    $sessionLines.Add("[grey58]Tenant[/]    $(& $escape $(if ($d.TenantId) { $d.TenantId } else { '-' }))")
    if ($d.SignIn) { $sessionLines.Add("[grey58]Sign-in[/]   $(& $escape $d.SignIn)") }
    if ($d.TokenExpiresOn -is [datetime]) {
        $minutes = [int]($d.TokenExpiresOn - $d.GeneratedAt).TotalMinutes
        $sessionLines.Add("[grey58]Token[/]     $(& $mark $(if ($minutes -gt 5) { 'Success' } else { 'Warning' })) valid until $($d.TokenExpiresOn.ToString('HH:mm')) [grey58](renewed when needed)[/]")
    }
    $healthLines = [System.Collections.Generic.List[string]]::new()
    $healthLines.Add("$(& $mark 'Success') Available    [white]$('{0:N0}' -f $d.Health.Available)[/]")
    $healthLines.Add("$(& $mark $(if ($d.Health.Unavailable) { 'Failed' } else { 'Success' })) Unavailable  [white]$('{0:N0}' -f $d.Health.Unavailable)[/]")
    $healthLines.Add("$(& $mark $(if ($d.Health.Degraded) { 'Warning' } else { 'Success' })) Degraded     [white]$('{0:N0}' -f $d.Health.Degraded)[/]")
    $healthLines.Add("$(& $mark 'Info') Unknown      [white]$('{0:N0}' -f $d.Health.Unknown)[/]")
    $serviceIssues = @($d.ServiceEvents | Where-Object Type -EQ 'Service issue').Count
    $healthLines.Add("$(& $mark $(if ($serviceIssues) { 'Failed' } else { 'Success' })) Service issues [white]$serviceIssues[/] [grey58]active[/]")
    $panel = {
        param([string] $Header, [string[]] $Lines, [string] $Border)
        $p = [Spectre.Console.Panel]::new([Spectre.Console.Markup]::new($Lines -join "`n"))
        $p.Border = [Spectre.Console.BoxBorder]::Rounded
        $p.BorderStyle = [Spectre.Console.Style]::Parse($Border)
        $p.Header = [Spectre.Console.PanelHeader]::new(" [bold]$(& $escape $Header)[/] ")
        $p.Expand = $true
        $p
    }
    $healthBorder = (Get-AACStatus $(if ($d.Health.Unavailable -or $serviceIssues) { 'Failed' } elseif ($d.Health.Degraded) { 'Warning' } else { 'Success' })).Color
    $columns = [Spectre.Console.Columns]::new([Spectre.Console.Rendering.IRenderable[]]@(@((& $panel 'Session' $sessionLines.ToArray() 'grey50')) + @(if (& $want 'Health') { & $panel 'Resource Health' $healthLines.ToArray() $healthBorder })))
    $columns.Expand = $true
    [Spectre.Console.AnsiConsole]::Write($columns)
    [Spectre.Console.AnsiConsole]::WriteLine()

    # --- Security, governance and cost ----------------------------------------------------------------------------
    $more = [System.Collections.Generic.List[object]]::new()
    if ((& $want 'Security') -and (& $has $d 'Security') -and $d.Security.Read) {
        $sec = $d.Security
        $lines = @(
            "[grey58]Secure score[/]   $(if ($null -ne $sec.SecureScore) { "[$(& $scoreColor $sec.SecureScore)]$($sec.SecureScore)%[/]" } else { '[grey50]-[/]' })"
            "[grey58]Active alerts[/]  [red1]$($sec.Alerts.High) high[/] [grey58]$($glyph.Dot)[/] [orange1]$($sec.Alerts.Medium) medium[/] [grey58]$($glyph.Dot)[/] [deepskyblue1]$($sec.Alerts.Low) low[/]"
            "[grey58]Recommendations[/] [red1]$($sec.Recommendations.High) high[/] [grey58]$($glyph.Dot)[/] [orange1]$($sec.Recommendations.Medium) medium[/] [grey58]unresolved[/]"
            $(if ($sec.DefenderPlans) { "[grey58]Defender plans[/] $(& $escape $sec.DefenderPlans) on" })
        ) | Where-Object { $_ }
        $more.Add((& $panel 'Security' @($lines) $(if ($sec.Alerts.High) { 'red1' } elseif ($null -ne $sec.SecureScore -and $sec.SecureScore -lt 60) { 'orange1' } else { 'grey50' })))
    }
    if ((& $want 'Governance') -and (& $has $d 'Governance')) {
        $g = $d.Governance
        $lines = @(
            $(if ((& $want 'Policy') -and (& $has $d 'Policy') -and $null -ne $d.Policy.Compliance) { "[grey58]Policy[/]        [$(& $scoreColor $d.Policy.Compliance)]$($d.Policy.Compliance)%[/] compliant [grey58]($($d.Policy.NonCompliant) non-compliant)[/]" })
            $(if ($g.ClosestLimit) { "[grey58]Closest limit[/] [$(if ($g.ClosestLimit.Percent -ge 95) { 'red1' } elseif ($g.ClosestLimit.Percent -ge 80) { 'orange1' } else { 'green3' })]$($g.ClosestLimit.Percent)%[/] $(& $escape "$($g.ClosestLimit.Limit) on $($g.ClosestLimit.Scope)")" })
            "[grey58]Privileged[/]    $($g.PrivilegedAssignments) [grey58]role assignment(s) at subscription or above[/]"
            "[grey58]Unused[/]        $(if ($g.Unused) { "[orange1]$($g.Unused)[/]" } else { '0' }) [grey58]disk(s), public IP(s), NIC(s)[/]"
            $(if ($null -ne $g.TagCoverage) { "[grey58]Tagged[/]        $($g.TagCoverage)% [grey58]of resources[/]" })
        ) | Where-Object { $_ }
        $more.Add((& $panel 'Governance' @($lines) 'grey50'))
    }
    if ((& $want 'Cost') -and (& $has $d 'Cost')) {
        $c = $d.Cost
        $lines = @(
            "[white]$('{0:N0}' -f $c.MonthToDate) $(& $escape $c.Currency)[/] [grey58]month to date $($glyph.Dot) forecast $('{0:N0}' -f $c.Forecast)[/]$(if ($null -ne $c.ChangePercent) { " [$(if ($c.ChangePercent -gt 10) { 'orange1' } else { 'green3' })]$('{0:+0.#;-0.#;0}' -f $c.ChangePercent)%[/] [grey58]vs last month[/]" })"
            "[deepskyblue1]$(& $escape (& $spark @($c.Daily | ForEach-Object { [double]$_.Cost })))[/] [grey58]30 days[/]"
            "[grey58]$(& $escape ((@($c.TopServices | Select-Object -First 3 | ForEach-Object { "$($_.Service) $('{0:N0}' -f $_.Cost)" })) -join ' · '))[/]"
        )
        $more.Add((& $panel 'Cost' @($lines) $(if ($null -ne $c.ChangePercent -and $c.ChangePercent -gt 10) { 'orange1' } else { 'grey50' })))
    }
    if ($more.Count) {
        $columns = [Spectre.Console.Columns]::new([Spectre.Console.Rendering.IRenderable[]]$more.ToArray())
        $columns.Expand = $true
        [Spectre.Console.AnsiConsole]::Write($columns)
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    # --- Subscriptions -------------------------------------------------------------------------------------------
    if ((& $want 'Estate') -and @($d.Subscriptions).Count) {
        $table = & $newTable 'Subscriptions' @('Subscription', 'State', 'ID')
        foreach ($s in @($d.Subscriptions)) {
            $state = switch ($s.State) { 'Enabled' { 'Success' } { $_ -in 'Warned', 'PastDue' } { 'Warning' } default { if ($s.State) { 'Failed' } else { 'Info' } } }
            & $addRow $table @("[white]$(& $escape $s.Name)[/]", "$(& $mark $state) $(& $escape $s.State)", "[grey50]$(& $escape $s.SubscriptionId)[/]")
        }
        [Spectre.Console.AnsiConsole]::Write($table)
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    # --- Where the resources are ---------------------------------------------------------------------------------
    $regions = @($d.TopRegions)
    if ((& $want 'Estate') -and $regions.Count) {
        $bars = @($regions | Select-Object -First 8 | ForEach-Object { @{ Label = $_.Region; Value = $_.Resources } })
        $rest = @($regions | Select-Object -Skip 8)
        if ($rest.Count) { $bars += @{ Label = "$($rest.Count) other region(s)"; Value = [int](@($rest.Resources) | Measure-Object -Sum).Sum; Color = 'grey50' } }
        Show-AACBarChart -Item $bars -Title 'Resources by region'
        [Spectre.Console.AnsiConsole]::WriteLine()
    }
    if ((& $want 'Estate') -and (& $has $d 'TopTypes') -and @($d.TopTypes).Count) {
        Show-AACBarChart -Item @($d.TopTypes | Select-Object -First 10 | ForEach-Object { @{ Label = $_.Name; Value = $_.Resources } }) -Title 'Resources by type'
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    # --- Service Health, unhealthy resources ------------------------------------------------------------------------
    if ((& $want 'Health') -and @($d.ServiceEvents).Count) {
        $table = & $newTable 'Azure Service Health - active events' @('', 'Type', 'Title', 'Tracking ID', 'Since', 'Subscriptions')
        foreach ($e in @($d.ServiceEvents)) {
            $state = if ($e.Type -eq 'Service issue') { 'Failed' } elseif ($e.Type -eq 'Security advisory') { 'Warning' } else { 'Info' }
            & $addRow $table @((& $mark $state), (& $escape $e.Type), "[white]$(& $escape $e.Title)[/]", "[grey58]$(& $escape $e.TrackingId)[/]", (& $when $e.Started), "[grey58]$(& $escape $e.Subscription)[/]")
        }
        [Spectre.Console.AnsiConsole]::Write($table)
        [Spectre.Console.AnsiConsole]::WriteLine()
    }
    if ((& $want 'Health') -and @($d.UnhealthyResources).Count) {
        $table = & $newTable 'Unhealthy resources (Resource Health)' @('', 'Resource', 'Resource group', 'State', 'Why', 'Since')
        foreach ($r in @($d.UnhealthyResources)) {
            & $addRow $table @((& $mark $(if ($r.State -eq 'Unavailable') { 'Failed' } else { 'Warning' })), "[white]$(& $escape $r.Resource)[/]", (& $escape $r.ResourceGroup), (& $escape $r.State), "[grey70]$(& $escape $r.Summary)[/]", (& $when $r.Since))
        }
        [Spectre.Console.AnsiConsole]::Write($table)
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    # --- Advisor ----------------------------------------------------------------------------------------------------
    if ((& $want 'Advisor') -and @($d.Advisor).Count) {
        $table = & $newTable 'Azure Advisor recommendations' @('Category', 'High', 'Medium', 'Low')
        $count = { param([int] $N, [string] $Color) if ($N) { "[$Color]$N[/]" } else { '[grey42]0[/]' } }
        foreach ($a in @($d.Advisor)) { & $addRow $table @((& $escape $a.Category), (& $count $a.High 'red1'), (& $count $a.Medium 'orange1'), (& $count $a.Low 'deepskyblue1')) }
        [Spectre.Console.AnsiConsole]::Write($table)
        if ((& $has $d 'AdvisorSavings')) { Write-AACMarkup "[grey58]Potential savings: [green3]$('{0:N0}' -f $d.AdvisorSavings.Annual) $(& $escape $d.AdvisorSavings.Currency)[/] a year in $($d.AdvisorSavings.Recommendations) cost recommendation(s)$(if (& $has $d 'AdvisorScore') { " $($glyph.Dot) Advisor score $($d.AdvisorScore)" })[/]" }
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    # --- Recent changes --------------------------------------------------------------------------------------------
    $changeTitle = "Recent changes - last $($d.Hours)h: $($d.Changes.Created) created, $($d.Changes.Updated) updated, $($d.Changes.Deleted) deleted"
    $timeline = @(if (& $has $d 'ChangeTimeline') { $d.ChangeTimeline })
    if ((& $want 'Changes') -and @($timeline | Where-Object { $_.Created + $_.Updated + $_.Deleted }).Count) {
        $created = 0; $updated = 0; $deleted = 0; foreach ($t in $timeline) { $created += $t.Created; $updated += $t.Updated; $deleted += $t.Deleted }
        Write-AACMarkup "[bold]Changes, 14 days[/] [mediumpurple2]$(& $escape (& $spark @($timeline | ForEach-Object { [double]($_.Created + $_.Updated + $_.Deleted) })))[/] [green3]+$created created[/] [deepskyblue1]~$updated updated[/] [red1]-$deleted deleted[/]"
        if ((& $has $d 'TopChangers') -and @($d.TopChangers).Count) { Write-AACMarkup "[grey58]Most changes in $($d.Hours)h: $(& $escape ((@($d.TopChangers | Select-Object -First 3 | ForEach-Object { "$($_.ChangedBy) $($_.Changes)$(if ($_.Deletes) { " ($($_.Deletes) deletes)" })" })) -join ' · '))[/]" }
        [Spectre.Console.AnsiConsole]::WriteLine()
    }
    if (& $want 'Changes') {
        if (@($d.RecentChanges).Count) {
            $table = & $newTable $changeTitle @('When', 'Change', 'Resource', 'Type', 'Resource group', 'By')
            $kinds = @{ Create = @('green3', '+'); Update = @('deepskyblue1', '~'); Delete = @('red1', '-') }
            foreach ($c in @($d.RecentChanges)) {
                $kind = if ($kinds.Contains($c.Change)) { $kinds[$c.Change] } else { @('grey70', ' ') }
                & $addRow $table @((& $when $c.Time), "[$($kind[0])]$($kind[1]) $(& $escape $c.Change)[/]", "[white]$(& $escape $c.Resource)[/]", "[grey58]$(& $escape ($c.ResourceType -replace '^microsoft\.', ''))[/]", (& $escape $c.ResourceGroup), "[grey70]$(& $escape $c.ChangedBy)[/]")
            }
            [Spectre.Console.AnsiConsole]::Write($table)
        }
        else { Write-AACStatusLine Info "No resource changes in the last $($d.Hours)h." }
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    # --- What to do next ---------------------------------------------------------------------------------------------
    $actions = @(if (& $has $d 'Actions') { $d.Actions })
    if ($actions.Count) {
        $table = & $newTable 'What to do next' @('', 'Area', 'What', 'Go deeper')
        $sev = @{ High = 'Failed'; Medium = 'Warning'; Low = 'Info' }
        foreach ($a in $actions) { & $addRow $table @((& $mark $sev[$a.Severity]), (& $escape $a.Area), "[white]$(& $escape $a.Action)[/]", "[deepskyblue1]$(& $escape $a.Command)[/]") }
        [Spectre.Console.AnsiConsole]::Write($table)
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    # --- What couldn't be read ----------------------------------------------------------------------------------------
    foreach ($property in @($d.Unread.PSObject.Properties)) { Write-AACStatusLine Warning "Couldn't read $($property.Name)" -Detail $property.Value }
    Write-AACMarkup '[grey42]-SubscriptionId or -Select narrows the scope; -Section picks what to show; -IncludeCost adds the spend; -HtmlPath or -PdfPath for a report; -Watch refreshes; -PassThru returns the dashboard object.[/]'
}
