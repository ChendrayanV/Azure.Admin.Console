function Show-AACSentinelAssessmentView {
    <#
    .SYNOPSIS
        Renders Invoke-AACSentinelAssessment's result as a Spectre.Console view.
    .DESCRIPTION
        The workspace, tiles, what couldn't be read, then - for the sections
        asked for - the recommendations (by severity), the analytics rules and
        MITRE ATT&CK coverage, the rule templates worth enabling, the data
        connectors, the tables (size, share, plan, retention, last record),
        the health failures, the open incidents and the automation rules.
        Long lists stop at -MaxRow rows with how many more; -PassThru or
        -HtmlPath has them all. Wrap the call in Invoke-AACPagedOutput to page
        it.
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

    # --- The workspace and tiles ------------------------------------------------------------------------------
    $facts = @("[white]$(& $escape $workspace.Name)[/]", "workspace ID $(& $escape $workspace.WorkspaceId)", (& $escape $workspace.ResourceGroup), (& $escape $workspace.Location), "last $($workspace.Days) day(s)")
    Write-AACMarkup "[grey58]$($facts -join " $($glyph.Dot) ")[/]"
    [Spectre.Console.AnsiConsole]::WriteLine()
    $enabled = $workspace.SentinelEnabled
    Show-AACTileRow -Tile @(
        if (-not $enabled) { @{ Value = 'Not enabled'; Caption = 'Microsoft Sentinel'; Color = 'red1' } }
        if ($enabled -and (& $want 'AnalyticsRules')) { @{ Value = "$($stats.EnabledRules) / $($stats.AnalyticsRules)"; Caption = 'analytics rules enabled'; Color = 'mediumpurple2' } }
        if ($enabled -and (& $want 'AnalyticsRules')) { @{ Value = "$($stats.TacticsCovered) / $($stats.TacticsTotal)"; Caption = 'MITRE tactics covered'; Color = $(if ($stats.TacticsCovered -lt $stats.TacticsTotal) { 'orange1' } else { 'green3' }) } }
        if ($enabled -and (& $want 'DataConnectors')) { @{ Value = "$($stats.ConnectedConnectors) / $($stats.DataConnectors)"; Caption = 'connectors connected'; Color = 'turquoise2' } }
        if ($enabled -and (& $want 'Tables')) { @{ Value = '{0:N2} GB' -f $stats.BillableGB; Caption = "billable, $($workspace.Days) days"; Color = 'deepskyblue1' } }
        if ($enabled -and (& $want 'Health')) { @{ Value = '{0:N0}' -f $stats.HealthFailures; Caption = 'health failures'; Color = $(if ($stats.HealthFailures) { 'orange1' } else { 'green3' }) } }
        if ($enabled -and (& $want 'Incidents')) { @{ Value = '{0:N0}' -f $stats.OpenIncidents; Caption = 'open incidents'; Color = $(if ($stats.OpenIncidents) { 'orange1' } else { 'green3' }) } }
        if ($enabled -and (& $want 'RuleTemplates')) { @{ Value = '{0:N0}' -f $stats.TemplateCandidates; Caption = 'templates to consider'; Color = 'deepskyblue1' } }
        if ($enabled -and (& $want 'AutomationRules')) { @{ Value = "$($stats.EnabledAutomation) / $($stats.AutomationRules)"; Caption = 'automation rules enabled'; Color = 'mediumpurple2' } }
        if (& $want 'Recommendations') { @{ Value = "$($stats.High) / $($stats.Medium) / $($stats.Low)"; Caption = 'recommendations H / M / L'; Color = $(if ($stats.High) { 'red1' } elseif ($stats.Medium) { 'orange1' } else { 'green3' }) } }
    )
    [Spectre.Console.AnsiConsole]::WriteLine()
    foreach ($key in @($Assessment.Errors.Keys)) { Write-AACMarkup "[orange1]![/] [grey70]$(& $escape $key) couldn't be read: $(& $escape $Assessment.Errors[$key])[/]" }
    if ($Assessment.Errors.Count) { [Spectre.Console.AnsiConsole]::WriteLine() }

    # --- Recommendations ------------------------------------------------------------------------------------------
    if (& $want 'Recommendations') {
        $items = @($Assessment.Recommendations)
        if ($items.Count) {
            $table = & $newTable "[bold]$($glyph.Bullet) Recommendations[/] [grey58]$($glyph.Dot) $($items.Count)[/]" 'grey42' @(@('Severity', $false), @('Recommendation', $false), @('What to do', $false))
            foreach ($item in $items) {
                $color = $severityColor[$item.Severity] ?? 'grey70'
                & $addRow $table @(
                    "[bold $color]$($item.Severity)[/]`n[grey58]$(& $escape $item.Category)[/]"
                    "[bold]$(& $escape $item.Recommendation)[/]$(if ($item.Detail) { "`n[grey70]$(& $escape $item.Detail)[/]" })"
                    "$(& $escape $item.Action)$(if ($item.LearnMore) { "`n[grey50 link]$(& $escape $item.LearnMore)[/]" })"
                )
            }
            & $write $table
        }
        else {
            Show-AACCallout Success -Message '[bold green3]No recommendations[/] [grey58]for this workspace.[/]'
            [Spectre.Console.AnsiConsole]::WriteLine()
        }
    }
    # Without Sentinel there is nothing below to show.
    if (-not $enabled) { return }

    # --- Analytics rules ----------------------------------------------------------------------------------------
    if (& $want 'AnalyticsRules') {
        $rows = @($Assessment.AnalyticsRules)
        if ($rows.Count) {
            $table = & $newTable "[bold mediumpurple2]$($glyph.Bullet) Analytics rules[/] [grey58]$($glyph.Dot) $($stats.EnabledRules) of $($rows.Count) enabled $($glyph.Dot) failing first[/]" 'mediumpurple2' @(@('Rule', $false), @('Kind', $false), @('Severity', $false), @('State', $false), @('Tactics', $false), @('Every', $false), @('Failures', $true))
            foreach ($row in $rows | Select-AACFirst $MaxRow) {
                & $addRow $table @(
                    "[bold]$(& $escape $row.Name)[/]"
                    "[grey70]$(& $escape $row.Kind)[/]"
                    "[$($severityColor[$row.Severity] ?? 'grey70')]$(& $escape $(if ($row.Severity) { $row.Severity } else { '-' }))[/]"
                    $(if ($row.Enabled) { '[green3]Enabled[/]' } else { '[grey50]Disabled[/]' })
                    "[grey70]$(& $escape $row.Tactics)[/]"
                    "[grey70]$(& $escape $(if ($row.Frequency) { $row.Frequency } else { '-' }))[/]"
                    $(if ($row.Failures) { "[red1]$($row.Failures)[/]" } else { '[grey42]0[/]' })
                )
            }
            & $write $table
            & $more $MaxRow $rows.Count
        }
        elseif (-not $Assessment.Errors.Contains('Analytics rules')) { Write-AACMarkup '[grey58]No analytics rules on this workspace.[/]'; [Spectre.Console.AnsiConsole]::WriteLine() }
        $coverage = @($Assessment.TacticCoverage)
        if ($coverage.Count) {
            Show-AACBarChart -Title 'Enabled rules per MITRE ATT&CK tactic' -Format 'N0' -Item @($coverage | ForEach-Object { @{ Label = $_.Tactic; Value = [double]$_.EnabledRules; Color = $(if ($_.EnabledRules) { 'mediumpurple2' } else { 'grey42' }) } })
            [Spectre.Console.AnsiConsole]::WriteLine()
        }
    }

    # --- Rule templates -----------------------------------------------------------------------------------------
    if (& $want 'RuleTemplates') {
        $rows = @($Assessment.RuleTemplates | Where-Object Candidate)
        if ($rows.Count) {
            $table = & $newTable "[bold deepskyblue1]$($glyph.Bullet) Rule templates to consider[/] [grey58]$($glyph.Dot) $($rows.Count) of $($stats.RuleTemplates) $($glyph.Dot) data arriving, no rule yet[/]" 'deepskyblue1' @(@('Template', $false), @('Kind', $false), @('Severity', $false), @('Tactics', $false), @('Needs', $false))
            foreach ($row in $rows | Select-AACFirst $MaxRow) { & $addRow $table @("[bold]$(& $escape $row.Name)[/]", "[grey70]$(& $escape $row.Kind)[/]", "[$($severityColor[$row.Severity] ?? 'grey70')]$(& $escape $row.Severity)[/]", "[grey70]$(& $escape $row.Tactics)[/]", "[grey70]$(& $escape $row.DataTypes)[/]") }
            & $write $table
            & $more $MaxRow $rows.Count
        }
        elseif (-not $Assessment.Errors.Contains('Rule templates')) { Write-AACMarkup "[grey58]No template to suggest, of the $($stats.RuleTemplates) listed: each has a rule already, or its data isn't arriving.[/]"; [Spectre.Console.AnsiConsole]::WriteLine() }
    }

    # --- Data connectors ----------------------------------------------------------------------------------------
    if (& $want 'DataConnectors') {
        $rows = @($Assessment.DataConnectors)
        if ($rows.Count) {
            $stateColor = @{ Connected = 'green3'; Disconnected = 'orange1'; Unknown = 'grey58' }
            $table = & $newTable "[bold turquoise2]$($glyph.Bullet) Data connectors[/] [grey58]$($glyph.Dot) $($rows.Count)[/]" 'turquoise2' @(@('Connector', $false), @('Kind', $false), @('State', $false), @('Data types', $false))
            foreach ($row in $rows | Select-AACFirst $MaxRow) { & $addRow $table @("[bold]$(& $escape $row.Name)[/]", "[grey70]$(& $escape $row.Kind)[/]", "[$($stateColor[$row.State])]$($row.State)[/]", "[grey70]$(& $escape $row.DataTypes)[/]") }
            & $write $table
            & $more $MaxRow $rows.Count
        }
        elseif (-not $Assessment.Errors.Contains('Data connectors')) { Write-AACMarkup '[grey58]No data connectors listed. Check the tables: some sources send data without appearing here.[/]'; [Spectre.Console.AnsiConsole]::WriteLine() }
    }

    # --- Tables -------------------------------------------------------------------------------------------------
    if (& $want 'Tables') {
        $rows = @($Assessment.Tables)
        if ($rows.Count) {
            $table = & $newTable "[bold deepskyblue3]$($glyph.Bullet) Tables and ingestion[/] [grey58]$($glyph.Dot) $($rows.Count) $($glyph.Dot) largest first[/]" 'deepskyblue3' @(@('Table', $false), @('Billable', $true), @('Free', $true), @('Share', $true), @('Per day', $true), @('Plan', $false), @('Retention', $true), @('Last record', $false))
            foreach ($row in $rows | Select-AACFirst ($MaxRow * 2)) {
                $retention = if ($null -ne $row.RetentionDays) { "$($row.RetentionDays) d$(if ($row.TotalRetentionDays -gt $row.RetentionDays) { " / $($row.TotalRetentionDays) d total" })" } else { '-' }
                & $addRow $table @(
                    "[bold]$(& $escape $row.Table)[/]$(if ($row.Type -ne 'Azure') { " [grey50]$(& $escape $row.Type.ToLowerInvariant())[/]" })"
                    (& $gb $row.BillableGB); (& $gb $row.NonBillableGB)
                    $(if ($row.SharePercent) { "$($row.SharePercent)%" } else { '[grey42]-[/]' })
                    (& $gb $row.DailyAverageGB)
                    "[grey70]$(& $escape $(if ($row.Plan) { $row.Plan } else { '-' }))[/]"
                    $retention
                    $(if ($row.Silent) { "[red1]$(& $when $row.LastRecord)[/]" } else { "[grey70]$(& $when $row.LastRecord)[/]" })
                )
            }
            & $write $table
            & $more ($MaxRow * 2) $rows.Count
        }
        elseif (-not $Assessment.Errors.Contains('Ingestion (Usage)')) { Write-AACMarkup "[grey58]No table received data in the last $($workspace.Days) day(s).[/]"; [Spectre.Console.AnsiConsole]::WriteLine() }
    }

    # --- Health ---------------------------------------------------------------------------------------------------
    if (& $want 'Health') {
        $rows = @($Assessment.HealthFailures)
        if ($rows.Count) {
            $table = & $newTable "[bold orange1]$($glyph.Bullet) Health failures[/] [grey58]$($glyph.Dot) _SentinelHealth $($glyph.Dot) most failures first[/]" 'orange1' @(@('Resource', $false), @('Operation', $false), @('Failures', $true), @('Last failure', $false), @('Reason', $false))
            foreach ($row in $rows | Select-AACFirst $MaxRow) { & $addRow $table @("[bold]$(& $escape $row.Resource)[/]`n[grey50]$(& $escape $row.ResourceType)[/]", (& $escape $row.Operation), "[red1]$($row.Failures)[/]", "[grey70]$(& $when $row.LastFailure)[/]", "[grey70]$(& $escape $row.Reason)[/]") }
            & $write $table
            & $more $MaxRow $rows.Count
        }
        elseif ($Assessment.HealthState -eq 'On') { Write-AACMarkup '[green3]No failures reported in _SentinelHealth for the period.[/] [grey58]Only some connectors report health.[/]'; [Spectre.Console.AnsiConsole]::WriteLine() }
        elseif ($Assessment.HealthState -in 'Off', 'NoRecords') { Write-AACMarkup '[grey58]No health records: health monitoring appears to be off.[/]'; [Spectre.Console.AnsiConsole]::WriteLine() }
    }

    # --- Incidents ------------------------------------------------------------------------------------------------
    if (& $want 'Incidents') {
        $all = @($Assessment.Incidents)
        if ($all.Count) {
            $median = if ($null -ne $stats.MedianHoursToClose) { "$($stats.MedianHoursToClose) hours median to close" } else { 'no close times' }
            Write-AACMarkup "[grey70]$($all.Count) incident(s) in the last $($workspace.Days) day(s) $($glyph.Dot) $($stats.OpenIncidents) open $($glyph.Dot) $median $($glyph.Dot) $($stats.FalsePositivePercent)% of closed were false positives[/]"
            [Spectre.Console.AnsiConsole]::WriteLine()
            $rows = @($all | Where-Object Status -NE 'Closed' | Sort-Object -Property HoursOpen -Descending)
            if ($rows.Count) {
                $table = & $newTable "[bold orange1]$($glyph.Bullet) Open incidents[/] [grey58]$($glyph.Dot) $($rows.Count) $($glyph.Dot) oldest first[/]" 'orange1' @(@('Number', $true), @('Title', $false), @('Severity', $false), @('Status', $false), @('Owner', $false), @('Hours open', $true))
                foreach ($row in $rows | Select-AACFirst $MaxRow) { & $addRow $table @("$($row.Number)", "[bold]$(& $escape $row.Title)[/]", "[$($severityColor[$row.Severity] ?? 'grey70')]$(& $escape $row.Severity)[/]", (& $escape $row.Status), $(if ($row.Owner) { & $escape $row.Owner } else { '[orange1]none[/]' }), "$($row.HoursOpen)") }
                & $write $table
                & $more $MaxRow $rows.Count
            }
        }
        elseif (-not $Assessment.Errors.Contains('Incidents')) { Write-AACMarkup "[grey58]No incidents created in the last $($workspace.Days) day(s).[/]"; [Spectre.Console.AnsiConsole]::WriteLine() }
    }

    # --- Automation rules ---------------------------------------------------------------------------------------
    if (& $want 'AutomationRules') {
        $rows = @($Assessment.AutomationRules)
        if ($rows.Count) {
            $automationColor = @{ Enabled = 'green3'; Disabled = 'grey50'; Expired = 'orange1' }
            $table = & $newTable "[bold mediumpurple2]$($glyph.Bullet) Automation rules[/] [grey58]$($glyph.Dot) $($rows.Count) $($glyph.Dot) in the order they run[/]" 'mediumpurple2' @(@('Order', $true), @('Rule', $false), @('State', $false), @('Triggers on', $false), @('Actions', $false), @('Expires', $false))
            foreach ($row in $rows | Select-AACFirst $MaxRow) { & $addRow $table @("$($row.Order)", "[bold]$(& $escape $row.Name)[/]", "[$($automationColor[$row.State])]$($row.State)[/]", "[grey70]$(& $escape "$($row.TriggersOn) $($row.TriggersWhen)")[/]", "[grey70]$(& $escape $row.Actions)[/]", "[grey70]$(& $when $row.Expires)[/]") }
            & $write $table
            & $more $MaxRow $rows.Count
        }
        elseif (-not $Assessment.Errors.Contains('Automation rules')) { Write-AACMarkup '[grey58]No automation rules on this workspace.[/]'; [Spectre.Console.AnsiConsole]::WriteLine() }
    }
    Write-AACMarkup '[grey42]Add -PassThru (or pipe the command) for the assessment object - .AnalyticsRules, .RuleTemplates, .Incidents, .AutomationRules, .Tables, .Recommendations; -CsvPath for the analytics rules, -HtmlPath for every section.[/]'
}
