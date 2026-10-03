function Show-AACWorkspaceAssessmentView {
    <#
    .SYNOPSIS
        Renders Invoke-AACLogAnalyticsWorkspaceAssessment's result as a
        Spectre.Console view.
    .DESCRIPTION
        The workspace, tiles, what couldn't be read, then - for the sections
        asked for - the recommendations (by severity), the billable and the
        not billable tables (size, share, daily average, plan, retention),
        the settings by category, and the Workspace Insights tabs: Usage
        (ingestion per day, per solution, the top resources and computers),
        Health (operations, latency), Agents, Query Audit, Data Collection
        Rules and Change Log. Long lists stop at -MaxRow rows with how many
        more; -PassThru or -HtmlPath has them all. Wrap the call in
        Invoke-AACPagedOutput to page it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Assessment,

        [int] $MaxRow = 25
    )

    $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
    $glyph = Get-AACGlyph
    $stats = $Assessment.Stats
    $workspace = $Assessment.Workspace
    $insights = $Assessment.Insights
    $section = @(if ($Assessment.Contains('Section')) { $Assessment.Section })
    $want = { param([string] $Name) -not $section.Count -or $section -contains $Name }
    $gb = { param($Value) $v = [double]$Value; if ($v -eq 0) { '[grey42]0[/]' } elseif ($v -ge 100) { '{0:N0} GB' -f $v } elseif ($v -ge 1) { '{0:N2} GB' -f $v } else { '{0:N3} GB' -f $v } }
    $when = { param($Value) if ($Value -is [datetime]) { $Value.ToString('yyyy-MM-dd HH:mm') } elseif ($Value) { [string]$Value } else { '-' } }
    $severityColor = @{ High = 'red1'; Medium = 'orange1'; Low = 'deepskyblue1' }
    $newTable = {
        param([string] $Title, [string] $Color, [object[]] $Columns)
        $table = [Spectre.Console.Table]::new()
        $table.Border = [Spectre.Console.TableBorder]::Rounded
        $table.BorderStyle = [Spectre.Console.Style]::Parse($Color)
        $table.Expand = $true
        $table.Title = [Spectre.Console.TableTitle]::new($Title)
        foreach ($column in $Columns) {
            $spectre = [Spectre.Console.TableColumn]::new("[grey62]$($column[0])[/]")
            if ($column[1]) { $spectre.Alignment = [Spectre.Console.Justify]::Right; $spectre.NoWrap = $true }
            $table.AddColumn($spectre) | Out-Null
        }
        $table
    }
    $addRow = { param($Table, [string[]] $Cells) [Spectre.Console.TableExtensions]::AddRow($Table, [Spectre.Console.Rendering.IRenderable[]]@($Cells | ForEach-Object { [Spectre.Console.Markup]::new($_) })) | Out-Null }
    $write = { param($Table) [Spectre.Console.AnsiConsole]::Write($Table); [Spectre.Console.AnsiConsole]::WriteLine() }
    $more = { param([int] $Shown, [int] $Total) if ($Total -gt $Shown) { Write-AACMarkup "[grey50]... and $($Total - $Shown) more: -PassThru or -HtmlPath lists them all.[/]"; [Spectre.Console.AnsiConsole]::WriteLine() } }
    $heading = { param([string] $Text) Write-AACMarkup "[bold deepskyblue1]$($glyph.Bullet) $(& $escape $Text)[/]"; [Spectre.Console.AnsiConsole]::WriteLine() }

    # --- The workspace and tiles ------------------------------------------------------------------------------
    $facts = @("[white]$(& $escape $workspace.Name)[/]", "workspace ID $(& $escape $workspace.WorkspaceId)", (& $escape $workspace.ResourceGroup), (& $escape $workspace.Location), "last $($workspace.Days) day(s)")
    Write-AACMarkup "[grey58]$($facts -join " $($glyph.Dot) ")[/]"
    [Spectre.Console.AnsiConsole]::WriteLine()
    Show-AACTileRow -Tile @(
        @{ Value = $(if ($workspace.CommitmentTierGB) { "$($workspace.PricingTier) $($workspace.CommitmentTierGB)" } else { [string]$workspace.PricingTier }); Caption = 'pricing tier'; Color = 'mediumpurple2' }
        @{ Value = '{0:N2} GB' -f $stats.BillableGB; Caption = "billable, $($workspace.Days) days"; Color = 'deepskyblue1' }
        @{ Value = '{0:N2} GB' -f $stats.AverageDailyGB; Caption = 'billable per day'; Color = 'deepskyblue1' }
        @{ Value = '{0:N0}' -f $stats.TablesWithData; Caption = 'tables with data'; Color = 'grey85' }
        @{ Value = "$($stats.HealthyAgents) / $($stats.Agents)"; Caption = 'agents healthy'; Color = $(if ($stats.UnhealthyAgents) { 'orange1' } else { 'green3' }) }
        @{ Value = '{0:N0}' -f $stats.DataCollectionRules; Caption = 'data collection rules'; Color = 'turquoise2' }
        @{ Value = "$($stats.High) / $($stats.Medium) / $($stats.Low)"; Caption = 'recommendations H / M / L'; Color = $(if ($stats.High) { 'red1' } elseif ($stats.Medium) { 'orange1' } else { 'green3' }) }
    )
    [Spectre.Console.AnsiConsole]::WriteLine()
    foreach ($notice in @($Assessment.Notices)) { Write-AACMarkup "[deepskyblue1]i[/] [grey70]$(& $escape $notice)[/]" }
    foreach ($key in @($Assessment.Errors.Keys)) { Write-AACMarkup "[orange1]![/] [grey70]$(& $escape ($key -replace '^\w+:', '')) couldn't be read: $(& $escape $Assessment.Errors[$key])[/]" }
    if (@($Assessment.Notices).Count -or $Assessment.Errors.Count) { [Spectre.Console.AnsiConsole]::WriteLine() }

    # --- Recommendations ------------------------------------------------------------------------------------------
    if (& $want 'Recommendations') {
        $items = @($Assessment.Recommendations)
        if ($items.Count) {
            $table = & $newTable "[bold]$($glyph.Bullet) Recommendations[/] [grey58]$($glyph.Dot) $($items.Count)[/]" 'grey42' @(@('Severity', $false), @('Recommendation', $false), @('What to do', $false))
            foreach ($item in $items) {
                $color = $severityColor[$item.Severity] ?? 'grey70'
                & $addRow $table @(
                    "[bold $color]$($item.Severity)[/]`n[grey58]$(& $escape $item.Category)[/]"
                    "[bold]$(& $escape $item.Recommendation)[/]$(if ($item.Detail) { "`n[grey70]$(& $escape $item.Detail)[/]" })$(if ($item.Source -ne 'Assessment') { "`n[grey50]$(& $escape $item.Source)[/]" })"
                    "$(& $escape $item.Action)$(if ($item.LearnMore) { "`n[grey50 link]$(& $escape $item.LearnMore)[/]" })"
                )
            }
            & $write $table
        }
        else {
            Show-AACPanel -Content '[bold green3]No recommendations[/] [grey58]for this workspace.[/]' -BorderColor 'green3' -AllowMarkup
            [Spectre.Console.AnsiConsole]::WriteLine()
        }
    }

    # --- Tables: billable, not billable ----------------------------------------------------------------------------
    if (& $want 'Tables') {
        foreach ($kind in 'Billable', 'Not billable') {
            $rows = @($Assessment.Tables | Where-Object { if ($kind -eq 'Billable') { $_.Billing -in 'Billable', 'Both' } else { $_.Billing -eq 'Not billable' } })
            if (-not $rows.Count) { continue }
            $color = if ($kind -eq 'Billable') { 'deepskyblue3' } else { 'green3' }
            $columns = @(@('Table', $false), @('Billable', $true), @('Free', $true), @('Share', $true), @('Per day', $true), @('Plan', $false), @('Retention', $true), @('Last record', $false))
            $table = & $newTable "[bold $color]$($glyph.Bullet) $kind tables[/] [grey58]$($glyph.Dot) $($rows.Count) $($glyph.Dot) largest first[/]" $color $columns
            foreach ($row in $rows | Select-AACFirst ($MaxRow * 2)) {
                $retention = if ($null -ne $row.RetentionDays) { "$($row.RetentionDays) d$(if ($row.LongTermDays) { " + $($row.LongTermDays) d long-term" })" } else { '-' }
                & $addRow $table @(
                    "[bold]$(& $escape $row.Table)[/]$(if ($row.Type -ne 'Azure') { " [grey50]$(& $escape $row.Type.ToLowerInvariant())[/]" })"
                    (& $gb $row.BillableGB); (& $gb $row.NonBillableGB)
                    $(if ($row.SharePercent) { "$($row.SharePercent)%" } else { '[grey42]-[/]' })
                    (& $gb $row.DailyAverageGB)
                    $(if ($row.Plan -and $row.Plan -ne 'Analytics') { "[orchid]$(& $escape $row.Plan)[/]" } else { "[grey70]$(& $escape $(if ($row.Plan) { $row.Plan } else { '-' }))[/]" })
                    $retention
                    "[grey70]$(& $when $row.LastRecord)[/]"
                )
            }
            & $write $table
            & $more ($MaxRow * 2) $rows.Count
        }
        $empty = @($Assessment.Tables | Where-Object Billing -EQ 'No data')
        if ($empty.Count) { Write-AACMarkup "[grey50]$($empty.Count) table(s) listed with no data in the period (custom, or on a non-default plan or retention): $(& $escape (@($empty | Select-AACFirst 12 | ForEach-Object Table) -join ', '))$(if ($empty.Count -gt 12) { ', ...' })[/]"; [Spectre.Console.AnsiConsole]::WriteLine() }
    }

    # --- Settings ------------------------------------------------------------------------------------------------------
    if (& $want 'Settings') {
        $table = & $newTable "[bold mediumpurple2]$($glyph.Bullet) Workspace settings[/]" 'mediumpurple2' @(@('Category', $false), @('Setting', $false), @('Value', $false))
        $last = ''
        foreach ($row in $Assessment.Settings) {
            & $addRow $table @($(if ($row.Category -ne $last) { "[bold]$(& $escape $row.Category)[/]" } else { '' }), (& $escape $row.Setting), "[white]$(& $escape $row.Value)[/]")
            $last = $row.Category
        }
        & $write $table
    }

    # --- Usage -----------------------------------------------------------------------------------------------------------
    if (& $want 'Usage') {
        $usage = $insights.Usage
        & $heading 'Usage'
        if (@($usage.Daily).Count) {
            Show-AACBarChart -Title "Billable GB per day (last $($workspace.Days) days)" -Format 'N2' -Suffix ' GB' -Item @($usage.Daily | ForEach-Object { @{ Label = $_.Day.ToString('MM-dd'); Value = [double]$_.BillableGB; Color = 'deepskyblue1' } })
            [Spectre.Console.AnsiConsole]::WriteLine()
        }
        foreach ($set in @(@('Solutions', 'Solution', 'By solution'), @('Resources', 'Resource', 'By Azure resource, last 24 hours'), @('Computers', 'Computer', 'By computer, last 24 hours'))) {
            $rows = @($usage[$set[0]])
            if (-not $rows.Count) { continue }
            $table = & $newTable "[bold]$($set[2])[/]" 'grey42' @(@($set[1], $false), @('Billable', $true))
            foreach ($row in $rows | Select-AACFirst $MaxRow) { & $addRow $table @("[white]$(& $escape $row.($set[1]))[/]", (& $gb $row.BillableGB)) }
            & $write $table
        }
    }

    # --- Health --------------------------------------------------------------------------------------------------------
    if (& $want 'Health') {
        & $heading 'Health'
        $operations = @($insights.Health.Operations)
        if ($operations.Count) {
            $levelColor = @{ Error = 'red1'; Warning = 'orange1'; Info = 'grey70'; Informational = 'grey70' }
            $table = & $newTable "[bold]Operations (_LogOperation)[/] [grey58]$($glyph.Dot) errors and warnings first[/]" 'grey42' @(@('Level', $false), @('Operation', $false), @('Count', $true), @('Last seen', $false), @('Detail', $false))
            foreach ($row in $operations | Select-AACFirst $MaxRow) {
                & $addRow $table @("[$($levelColor[$row.Level] ?? 'grey70')]$(& $escape $row.Level)[/]", "$(& $escape $row.Operation)`n[grey50]$(& $escape $row.Category)[/]", "$($row.Count)", "[grey70]$(& $when $row.LastSeen)[/]", "[grey70]$(& $escape $row.Detail)[/]")
            }
            & $write $table
            & $more $MaxRow $operations.Count
        }
        else { Write-AACMarkup '[green3]No operations reported in _LogOperation for the period.[/]'; [Spectre.Console.AnsiConsole]::WriteLine() }
        $latency = @($insights.Health.Latency)
        if ($latency.Count) {
            $table = & $newTable '[bold]Ingestion latency of heartbeats, last 24 hours[/]' 'grey42' @(@('Agent', $false), @('Records', $true), @('Median', $true), @('95th percentile', $true), @('Max', $true))
            foreach ($row in $latency) { & $addRow $table @((& $escape $row.AgentType), "$($row.Records)", "$($row.P50Seconds) s", "$($row.P95Seconds) s", "$($row.MaxSeconds) s") }
            & $write $table
        }
    }

    # --- Agents ----------------------------------------------------------------------------------------------------------
    if (& $want 'Agents') {
        & $heading 'Agents'
        $byType = @($insights.Agents.ByType)
        if ($byType.Count) {
            $table = & $newTable '[bold]Agents by type[/]' 'grey42' @(@('Agent', $false), @('Computers', $true), @('Healthy', $true), @('Unhealthy', $true), @('Not reporting', $true))
            foreach ($row in $byType) { & $addRow $table @("$(if ($row.AgentType -like '*MMA*') { '[red1]' } else { '[white]' })$(& $escape $row.AgentType)[/]", "$($row.Computers)", "[green3]$($row.Healthy)[/]", "$(if ($row.Unhealthy) { "[orange1]$($row.Unhealthy)[/]" } else { '[grey42]0[/]' })", "$(if ($row.NotReporting) { "[red1]$($row.NotReporting)[/]" } else { '[grey42]0[/]' })") }
            & $write $table
            $silent = @($insights.Agents.Computers | Where-Object State -NE 'Healthy' | Sort-Object MinutesSince)
            if ($silent.Count) {
                $table = & $newTable '[bold orange1]Agents without a recent heartbeat[/]' 'orange1' @(@('Computer', $false), @('State', $false), @('Last heartbeat', $false), @('Agent', $false), @('OS', $false))
                foreach ($row in $silent | Select-AACFirst $MaxRow) { & $addRow $table @("[bold]$(& $escape $row.Computer)[/]", "$(if ($row.State -eq 'Not reporting') { '[red1]' } else { '[orange1]' })$($row.State)[/]", (& $when $row.LastHeartbeat), (& $escape $row.AgentType), (& $escape (@($row.OSType, $row.OSName) | Where-Object { $_ }) -join ' ')) }
                & $write $table
                & $more $MaxRow $silent.Count
            }
        }
        else { Write-AACMarkup "[grey58]No agent sent a heartbeat to this workspace in the period.[/]"; [Spectre.Console.AnsiConsole]::WriteLine() }
    }

    # --- Query audit ---------------------------------------------------------------------------------------------------
    if (& $want 'QueryAudit') {
        & $heading 'Query audit'
        $audit = $insights.QueryAudit
        if (@($audit.Users).Count) {
            $table = & $newTable '[bold]Queries by user and app[/]' 'grey42' @(@('User', $false), @('App', $false), @('Queries', $true), @('Failed', $true), @('Avg ms', $true), @('Max ms', $true), @('CPU s', $true))
            foreach ($row in $audit.Users | Select-AACFirst $MaxRow) { & $addRow $table @("[white]$(& $escape $row.User)[/]", "[grey70]$(& $escape $row.ClientApp)[/]", "$($row.Queries)", "$(if ($row.Failed) { "[red1]$($row.Failed)[/]" } else { '[grey42]0[/]' })", "$($row.AvgDurationMs)", "$($row.MaxDurationMs)", "$($row.CpuSeconds)") }
            & $write $table
            if (@($audit.Slowest).Count) {
                $table = & $newTable '[bold]Slowest queries[/]' 'grey42' @(@('When', $false), @('User', $false), @('ms', $true), @('Query', $false))
                foreach ($row in $audit.Slowest | Select-AACFirst 10) { & $addRow $table @((& $when $row.Time), (& $escape $row.User), "$($row.DurationMs)", "[grey70]$(& $escape ($row.Query -replace '\s+', ' '))[/]") }
                & $write $table
            }
            if (@($audit.Failed).Count) {
                $table = & $newTable '[bold red1]Failed queries[/]' 'red3' @(@('Code', $true), @('User', $false), @('App', $false), @('Count', $true), @('Last seen', $false))
                foreach ($row in $audit.Failed | Select-AACFirst $MaxRow) { & $addRow $table @("$($row.ResponseCode)", (& $escape $row.User), (& $escape $row.ClientApp), "$($row.Count)", (& $when $row.LastSeen)) }
                & $write $table
            }
        }
        else { Write-AACMarkup '[grey58]No query audit records (LAQueryLogs) in the period.[/]'; [Spectre.Console.AnsiConsole]::WriteLine() }
    }

    # --- Data collection rules -------------------------------------------------------------------------------------------
    if (& $want 'DataCollectionRules') {
        $rules = @($Assessment.DataCollectionRules)
        if ($rules.Count) {
            $table = & $newTable "[bold turquoise2]$($glyph.Bullet) Data collection rules[/] [grey58]$($glyph.Dot) sending to this workspace[/]" 'turquoise2' @(@('Rule', $false), @('Collects', $false), @('Into', $false), @('Associated with', $false))
            foreach ($rule in $rules) {
                & $addRow $table @(
                    "[bold]$(& $escape $rule.Name)[/]`n[grey50]$(& $escape $rule.Kind) $($glyph.Dot) $(& $escape $rule.ResourceGroup)$(if ($rule.WorkspaceTransform) { " $($glyph.Dot) workspace transformation" })[/]"
                    "$(& $escape $(if ($rule.DataSources) { $rule.DataSources } else { $rule.Streams }))$(if ($rule.Transformations) { "`n[grey58]$($rule.Transformations) transformation(s)[/]" })"
                    "[grey70]$(& $escape $(if ($rule.OutputTables) { $rule.OutputTables } else { $rule.Streams }))[/]"
                    $(if ($rule.Associations) { "$($rule.Associations): $(& $escape $rule.AssociatedResources)" } elseif ($rule.WorkspaceTransform -or $rule.Kind -in 'Direct', 'AgentDirectToStore') { '[grey50]-[/]' } else { '[orange1]none[/]' })
                )
            }
            & $write $table
        }
        else { Write-AACMarkup '[grey58]No data collection rule sends to this workspace.[/]'; [Spectre.Console.AnsiConsole]::WriteLine() }
    }

    # --- Change log --------------------------------------------------------------------------------------------------------
    if (& $want 'ChangeLog') {
        $changes = @($Assessment.ChangeLog)
        if ($changes.Count) {
            $table = & $newTable "[bold]$($glyph.Bullet) Change log[/] [grey58]$($glyph.Dot) activity log, newest first[/]" 'grey42' @(@('When', $false), @('Operation', $false), @('On', $false), @('Status', $false), @('By', $false))
            foreach ($row in $changes | Select-AACFirst $MaxRow) { & $addRow $table @((& $when $row.Time), (& $escape $row.Operation), "[grey70]$(& $escape $row.Resource)[/]", "$(if ($row.Status -eq 'Failed') { '[red1]' } else { '[green3]' })$(& $escape $row.Status)[/]", (& $escape $row.Caller)) }
            & $write $table
            & $more $MaxRow $changes.Count
        }
        else { Write-AACMarkup "[grey58]No changes to the workspace in the activity log for the period.[/]"; [Spectre.Console.AnsiConsole]::WriteLine() }
    }
    Write-AACMarkup '[grey42]Add -PassThru (or pipe the command) for the assessment object - .Tables, .Settings, .Recommendations, .Insights; -CsvPath for the tables, -HtmlPath for every section.[/]'
}
