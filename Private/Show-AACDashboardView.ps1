function Show-AACDashboardView {
    <#
    .SYNOPSIS
        Draws Show-AACDashboard's view: the headline status, tiles, the
        session and health side by side, the subscriptions, regions, Advisor,
        Service Health events, unhealthy resources and recent changes.
    .DESCRIPTION
        Every state is drawn with Get-AACStatus's symbols and colours (with
        an ASCII fallback), so it reads the same as the rest of the module
        and in any console.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Dashboard,

        [System.Collections.IDictionary] $Scope = @{}
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
    $columns = [Spectre.Console.Columns]::new([Spectre.Console.Rendering.IRenderable[]]@((& $panel 'Session' $sessionLines.ToArray() 'grey50'), (& $panel 'Resource Health' $healthLines.ToArray() $healthBorder)))
    $columns.Expand = $true
    [Spectre.Console.AnsiConsole]::Write($columns)
    [Spectre.Console.AnsiConsole]::WriteLine()

    # --- Subscriptions -------------------------------------------------------------------------------------------
    if (@($d.Subscriptions).Count) {
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
    if ($regions.Count) {
        $bars = @($regions | Select-Object -First 8 | ForEach-Object { @{ Label = $_.Region; Value = $_.Resources } })
        $rest = @($regions | Select-Object -Skip 8)
        if ($rest.Count) { $bars += @{ Label = "$($rest.Count) other region(s)"; Value = [int](@($rest.Resources) | Measure-Object -Sum).Sum; Color = 'grey50' } }
        Show-AACBarChart -Item $bars -Title 'Resources by region'
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    # --- Service Health, unhealthy resources ------------------------------------------------------------------------
    if (@($d.ServiceEvents).Count) {
        $table = & $newTable 'Azure Service Health - active events' @('', 'Type', 'Title', 'Tracking ID', 'Since', 'Subscriptions')
        foreach ($e in @($d.ServiceEvents)) {
            $state = if ($e.Type -eq 'Service issue') { 'Failed' } elseif ($e.Type -eq 'Security advisory') { 'Warning' } else { 'Info' }
            & $addRow $table @((& $mark $state), (& $escape $e.Type), "[white]$(& $escape $e.Title)[/]", "[grey58]$(& $escape $e.TrackingId)[/]", (& $when $e.Started), "[grey58]$(& $escape $e.Subscription)[/]")
        }
        [Spectre.Console.AnsiConsole]::Write($table)
        [Spectre.Console.AnsiConsole]::WriteLine()
    }
    if (@($d.UnhealthyResources).Count) {
        $table = & $newTable 'Unhealthy resources (Resource Health)' @('', 'Resource', 'Resource group', 'State', 'Why', 'Since')
        foreach ($r in @($d.UnhealthyResources)) {
            & $addRow $table @((& $mark $(if ($r.State -eq 'Unavailable') { 'Failed' } else { 'Warning' })), "[white]$(& $escape $r.Resource)[/]", (& $escape $r.ResourceGroup), (& $escape $r.State), "[grey70]$(& $escape $r.Summary)[/]", (& $when $r.Since))
        }
        [Spectre.Console.AnsiConsole]::Write($table)
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    # --- Advisor ----------------------------------------------------------------------------------------------------
    if (@($d.Advisor).Count) {
        $table = & $newTable 'Azure Advisor recommendations' @('Category', 'High', 'Medium', 'Low')
        $count = { param([int] $N, [string] $Color) if ($N) { "[$Color]$N[/]" } else { '[grey42]0[/]' } }
        foreach ($a in @($d.Advisor)) { & $addRow $table @((& $escape $a.Category), (& $count $a.High 'red1'), (& $count $a.Medium 'orange1'), (& $count $a.Low 'deepskyblue1')) }
        [Spectre.Console.AnsiConsole]::Write($table)
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    # --- Recent changes --------------------------------------------------------------------------------------------
    $changeTitle = "Recent changes - last $($d.Hours)h: $($d.Changes.Created) created, $($d.Changes.Updated) updated, $($d.Changes.Deleted) deleted"
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

    # --- What couldn't be read ----------------------------------------------------------------------------------------
    foreach ($property in @($d.Unread.PSObject.Properties)) { Write-AACStatusLine Warning "Couldn't read $($property.Name)" -Detail $property.Value }
    Write-AACMarkup '[grey42]-SubscriptionId or -Select narrows the scope; -Hours sets the change window; -PassThru returns the dashboard object.[/]'
}
