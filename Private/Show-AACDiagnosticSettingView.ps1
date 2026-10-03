function Show-AACDiagnosticSettingView {
    <#
    .SYNOPSIS
        Renders Get-AACDiagnosticSetting's result as a Spectre.Console view.
    .DESCRIPTION
        The scope, tiles, then:
          Coverage by resource type   least covered first
          Workspaces receiving logs   found or not, expected or not
          Misconfigurations           each finding, with how many resources
                                      and which (up to -MaxRow)
          Not exported                the resources whose logs don't all
                                      reach a workspace (up to -MaxRow)
        Wrap the call in Invoke-AACPagedOutput to page it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Diagnostic,

        [int] $MaxRow = 50
    )

    $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
    $glyph = Get-AACGlyph
    $stats = $Diagnostic.Stats
    $severityColor = @{ High = 'red1'; Medium = 'orange1'; Low = 'deepskyblue1' }
    $statusColor = @{ Exported = 'green3'; Partial = 'orange1'; 'Not to workspace' = 'red1'; 'No setting' = 'red1'; Unknown = 'grey58'; 'No logs' = 'grey50' }
    $rateColor = { param($Rate) if ($null -eq $Rate) { 'grey50' } elseif ($Rate -ge 90) { 'green3' } elseif ($Rate -ge 60) { 'orange1' } else { 'red1' } }
    $count = { param([int] $Value, [string] $Color) if ($Value -eq 0) { '[grey42]0[/]' } else { "[$Color]$('{0:N0}' -f $Value)[/]" } }
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

    $facts = [System.Collections.Generic.List[string]]::new()
    if ($script:AACSession) { $facts.Add("[white]$(& $escape $script:AACSession.Account)[/]") }
    if ($Diagnostic.Scope) { foreach ($key in $Diagnostic.Scope.Keys) { $facts.Add("$(& $escape $key): $(& $escape $Diagnostic.Scope[$key])") } }
    $facts.Add((Get-Date).ToString('d MMM yyyy HH:mm'))
    Write-AACMarkup "[grey58]$($facts -join " $($glyph.Dot) ")[/]"
    [Spectre.Console.AnsiConsole]::WriteLine()
    Show-AACTileRow -Tile @(
        @{ Value = $(if ($null -ne $stats.CoveragePercent) { "$($stats.CoveragePercent)%" } else { '-' }); Caption = ('exported to Log Analytics ({0:N0} of {1:N0})' -f $stats.Exported, ($stats.WithLogs - $stats.Unknown)); Color = (& $rateColor $stats.CoveragePercent) }
        @{ Value = '{0:N0}' -f $stats.Partial; Caption = 'partly exported'; Color = 'orange1' }
        @{ Value = '{0:N0}' -f $stats.NotToWorkspace; Caption = 'settings, no workspace'; Color = 'red1' }
        @{ Value = '{0:N0}' -f $stats.NoSetting; Caption = 'no diagnostic setting'; Color = 'red1' }
        @{ Value = '{0:N0}' -f $stats.Settings; Caption = 'diagnostic settings'; Color = 'grey85' }
        @{ Value = '{0:N0}' -f $stats.Workspaces; Caption = 'workspaces receiving logs'; Color = 'mediumpurple2' }
        @{ Value = "$($stats.High) / $($stats.Medium) / $($stats.Low)"; Caption = 'findings H / M / L'; Color = $(if ($stats.High) { 'red1' } elseif ($stats.Medium) { 'orange1' } else { 'green3' }) }
    )
    [Spectre.Console.AnsiConsole]::WriteLine()
    foreach ($notice in @($Diagnostic.Notice | Where-Object { $_ })) { Write-AACMarkup "[deepskyblue1]i[/] [grey70]$(& $escape $notice)[/]" }
    if (@($Diagnostic.Notice).Count) { [Spectre.Console.AnsiConsole]::WriteLine() }
    if (-not $stats.WithLogs) { return }

    # --- Coverage by resource type -------------------------------------------------------------------------
    $table = & $newTable "[bold]$($glyph.Bullet) Coverage by resource type[/] [grey58]$($glyph.Dot) least covered first[/]" 'grey42' @(@('Resource type', $false), @('Coverage', $true), @('Exported', $true), @('Partial', $true), @('No workspace', $true), @('No setting', $true), @('Resources', $true))
    foreach ($row in $Diagnostic.ByType) {
        & $addRow $table @(
            "[bold]$(& $escape $row.ResourceType)[/]"
            $(if ($null -ne $row.CoveragePercent) { "[bold $(& $rateColor $row.CoveragePercent)]$($row.CoveragePercent)%[/]" } else { '[grey50]-[/]' })
            (& $count $row.Exported 'green3'); (& $count $row.Partial 'orange1'); (& $count $row.NotToWorkspace 'red1'); (& $count $row.NoSetting 'red1'); (& $count $row.Resources 'grey85')
        )
    }
    & $write $table

    # --- Workspaces --------------------------------------------------------------------------------------------
    if (@($Diagnostic.Workspaces).Count) {
        $table = & $newTable "[bold mediumpurple2]$($glyph.Bullet) Workspaces receiving logs[/]" 'mediumpurple2' @(@('Workspace', $false), @('Location', $false), @('Resources', $true), @('Settings', $true), @('', $false))
        foreach ($row in $Diagnostic.Workspaces) {
            $note = if (-not $row.Found) { '[red1]not found: deleted, or not visible to you[/]' } elseif ($false -eq $row.Expected) { '[orange1]not an expected workspace[/]' } elseif ($true -eq $row.Expected) { '[green3]expected[/]' } else { '' }
            & $addRow $table @("[bold]$(& $escape $row.Workspace)[/]", "[grey70]$(& $escape $row.Location)[/]", "$($row.Resources)", "$($row.Settings)", $note)
        }
        & $write $table
    }

    # --- Misconfigurations ----------------------------------------------------------------------------------------
    $rank = @{ High = 0; Medium = 1; Low = 2 }
    $groups = @($Diagnostic.Findings | Group-Object Severity, Finding | Sort-Object { $rank[$_.Group[0].Severity] }, { $_.Group[0].Finding })
    if ($groups.Count) {
        $table = & $newTable "[bold]$($glyph.Bullet) Misconfigurations[/] [grey58]$($glyph.Dot) $(@($Diagnostic.Findings).Count) finding(s)[/]" 'grey42' @(@('Severity', $false), @('Finding', $false), @('Resources', $true), @('Which', $false))
        foreach ($group in $groups) {
            $first = $group.Group[0]
            $names = @($group.Group | ForEach-Object Resource | Select-Object -Unique)
            $shown = @($names | Select-AACFirst 8)
            $which = ($shown | ForEach-Object { & $escape $_ }) -join ', '
            if ($names.Count -gt $shown.Count) { $which += " [grey50]+$($names.Count - $shown.Count) more[/]" }
            & $addRow $table @("[bold $($severityColor[$first.Severity])]$($first.Severity)[/]", "[bold]$(& $escape $first.Finding)[/]`n[grey58]$(& $escape $first.Action)[/]", "$($names.Count)", $which)
        }
        & $write $table
    }

    # --- Not exported ------------------------------------------------------------------------------------------
    $missing = @($Diagnostic.Shown | Where-Object Status -In 'No setting', 'Not to workspace', 'Partial')
    if ($missing.Count) {
        $table = & $newTable "[bold red1]$($glyph.Bullet) Logs not (all) reaching Log Analytics[/] [grey58]$($glyph.Dot) $($missing.Count) resource(s)[/]" 'red3' @(@('Resource', $false), @('Status', $false), @('What''s missing', $false))
        foreach ($row in $missing | Select-AACFirst $MaxRow) {
            $where = (@($row.ResourceGroup, $row.SubscriptionName) | Where-Object { $_ }) -join ' / '
            & $addRow $table @("[bold]$(& $escape $row.Resource)[/]`n[grey50]$(& $escape $row.ResourceType) $($glyph.Dot) $(& $escape $where)[/]", "[$($statusColor[$row.Status])]$(& $escape $row.Status)[/]", "[grey70]$(& $escape $row.Reason)[/]")
        }
        & $write $table
        if ($missing.Count -gt $MaxRow) { Write-AACMarkup "[grey50]... and $($missing.Count - $MaxRow) more: -PassThru, -CsvPath, -HtmlPath or -PdfPath lists them all.[/]"; [Spectre.Console.AnsiConsole]::WriteLine() }
    }
    elseif ($stats.WithLogs -and -not $stats.Unknown) {
        Show-AACPanel -Content '[bold green3]Every resource''s logs reach Log Analytics.[/]' -BorderColor 'green3' -AllowMarkup
        [Spectre.Console.AnsiConsole]::WriteLine()
    }
    Write-AACMarkup '[grey42]Add -PassThru (or pipe the command) for one row per resource, -ExpandSetting for one per diagnostic setting; -CsvPath, -PdfPath or -HtmlPath for a report.[/]'
}
