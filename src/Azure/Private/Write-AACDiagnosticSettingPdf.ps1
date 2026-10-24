function Write-AACDiagnosticSettingPdf {
    <#
    .SYNOPSIS
        Writes Get-AACDiagnosticSetting's result as a landscape A4 PDF.
    .DESCRIPTION
        1. Summary: title, scope, tiles, notices.
        2. Coverage by resource type, and the workspaces receiving logs.
        3. Misconfigurations: each finding with the resources it affects.
        4. The resources whose logs don't all reach Log Analytics, by
           resource type - up to -MaxRows; the CSV and HTML report have
           every row.
        Each heading is a bookmark (Save-AACPdfDocument). -Path must be a
        full path.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Diagnostic,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Title,

        [System.Collections.IDictionary] $Detail,

        [int] $MaxRows = 5000
    )

    $stats = $Diagnostic.Stats
    $pdf = New-AACPdfDocument -Title $Title -Subject "Diagnostic settings: $($stats.WithLogs) resources with logs" -Landscape
    $section = $pdf.Section
    $colors = $pdf.Colors
    $pt = $pdf.Pt
    $right = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Right
    $rateColor = { param($Rate) if ($null -eq $Rate) { $colors.Muted } elseif ($Rate -ge 90) { $pdf.Tone.Good.Solid } elseif ($Rate -ge 60) { $pdf.Tone.Warn.Solid } else { $pdf.Tone.Bad.Solid } }
    $severityColor = @{ High = $pdf.Tone.Bad.Solid; Medium = $pdf.Tone.Warn.Solid; Low = $colors.Accent }
    $statusColor = @{ Exported = $pdf.Tone.Good.Solid; Partial = $pdf.Tone.Warn.Solid; 'Not to workspace' = $pdf.Tone.Bad.Solid; 'No setting' = $pdf.Tone.Bad.Solid }
    $number = { param($Cell, $Value, $Color) $p = $Cell.AddParagraph(('{0:N0}' -f [double]$Value)); $p.Format.Alignment = $right; if ([double]$Value -eq 0) { $p.Format.Font.Color = $colors.Muted } elseif ($Color) { $p.Format.Font.Color = $Color; $p.Format.Font.Name = 'Segoe UI Semibold' } }
    $small = { param($Cell, [string] $Text, $Color) $p = $Cell.AddParagraph($Text); $p.Format.Font.Size = 7; if ($Color) { $p.Format.Font.Color = $Color }; $p }
    $note = { param([string] $Text) $p = $section.AddParagraph($Text); $p.Format.Font.Size = 8; $p.Format.Font.Color = $colors.Muted; $p.Format.SpaceBefore = & $pt 4 }

    # --- 1. Summary ------------------------------------------------------------------------------------------------
    & $pdf.AddTitle "Diagnostic settings · generated $($pdf.Generated.ToString('dddd d MMMM yyyy, HH:mm'))"
    $facts = [ordered]@{}
    if ($script:AACSession) { $facts['Azure account'] = [string]$script:AACSession.Account; $facts['Tenant'] = [string]$script:AACSession.TenantId }
    if ($Detail) { foreach ($key in $Detail.Keys) { $facts[[string]$key] = [string]$Detail[$key] } }
    $factTable = & $pdf.NewTable @(4.0, ($pdf.PageWidth - 4.0))
    foreach ($key in $facts.Keys) {
        $row = & $pdf.AddBodyRow $factTable
        $row.Cells[0].AddParagraph($key).Format.Font.Color = $colors.Muted
        $row.Cells[1].AddParagraph($facts[$key]) | Out-Null
    }
    $section.AddParagraph().Format.SpaceAfter = & $pt 6
    $tileData = @(
        @{ Value = $(if ($null -ne $stats.CoveragePercent) { "$($stats.CoveragePercent)%" } else { '-' }); Label = ('exported to Log Analytics ({0:N0} of {1:N0})' -f $stats.Exported, ($stats.WithLogs - $stats.Unknown)); Color = (& $rateColor $stats.CoveragePercent) }
        @{ Value = '{0:N0}' -f $stats.Partial; Label = 'partly exported'; Color = $(if ($stats.Partial) { $pdf.Tone.Warn.Solid }) }
        @{ Value = '{0:N0}' -f $stats.NotToWorkspace; Label = 'settings, no workspace'; Color = $(if ($stats.NotToWorkspace) { $pdf.Tone.Bad.Solid }) }
        @{ Value = '{0:N0}' -f $stats.NoSetting; Label = 'no diagnostic setting'; Color = $(if ($stats.NoSetting) { $pdf.Tone.Bad.Solid }) }
        @{ Value = '{0:N0}' -f $stats.Settings; Label = 'diagnostic settings' }
        @{ Value = '{0:N0}' -f $stats.Workspaces; Label = 'workspaces receiving logs' }
        @{ Value = "$($stats.High) / $($stats.Medium) / $($stats.Low)"; Label = 'findings high / medium / low'; Color = $(if ($stats.High) { $pdf.Tone.Bad.Solid }) }
    )
    $tiles = & $pdf.NewTable @(1..$tileData.Count | ForEach-Object { $pdf.PageWidth / $tileData.Count })
    $tiles.TopPadding = & $pt 8
    $tiles.BottomPadding = & $pt 8
    $tileRow = $tiles.AddRow()
    for ($i = 0; $i -lt $tileData.Count; $i++) {
        $cell = $tileRow.Cells[$i]
        $cell.Shading.Color = $colors.Panel
        $cell.Borders.Left.Width = $(if ($i -gt 0) { 2 } else { 0 })
        $cell.Borders.Left.Color = $colors.White
        $value = $cell.AddParagraph([string]$tileData[$i].Value)
        if ($tileData[$i].Contains('Color') -and $tileData[$i].Color) { $value.Format.Font.Color = $tileData[$i].Color }
        $value.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Center
        $value.Format.Font.Size = 18
        $value.Format.Font.Name = 'Segoe UI Semibold'
        $caption = $cell.AddParagraph($tileData[$i].Label)
        $caption.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Center
        $caption.Format.Font.Size = 8
        $caption.Format.Font.Color = $colors.Muted
    }
    foreach ($text in @(@($Diagnostic.Notice | Where-Object { $_ }) + 'Exported: every log category of the resource reaches a Log Analytics workspace, by name or through a category group (allLogs, audit). Storage accounts are assessed per service (blob, file, queue, table); subscriptions by their activity log.')) { & $note $text }

    # --- 2. Coverage by type, workspaces ---------------------------------------------------------------------------------
    if (@($Diagnostic.ByType).Count) {
        $section.AddParagraph('Coverage by resource type', 'Heading2') | Out-Null
        $table = & $pdf.NewTable @(9.1, 2.6, 2.6, 2.6, 3.0, 3.0, 3.2)
        & $pdf.AddHeaderRow $table @('Resource type', 'Coverage', 'Exported', 'Partial', 'No workspace', 'No setting', 'Resources') @(1, 2, 3, 4, 5, 6)
        foreach ($item in $Diagnostic.ByType) {
            $row = & $pdf.AddBodyRow $table
            $row.Cells[0].AddParagraph($item.ResourceType).Format.Font.Name = 'Segoe UI Semibold'
            $p = $row.Cells[1].AddParagraph($(if ($null -ne $item.CoveragePercent) { "$($item.CoveragePercent)%" } else { '-' })); $p.Format.Alignment = $right; $p.Format.Font.Name = 'Segoe UI Semibold'; $p.Format.Font.Color = & $rateColor $item.CoveragePercent
            & $number $row.Cells[2] $item.Exported $pdf.Tone.Good.Solid
            & $number $row.Cells[3] $item.Partial $pdf.Tone.Warn.Solid
            & $number $row.Cells[4] $item.NotToWorkspace $pdf.Tone.Bad.Solid
            & $number $row.Cells[5] $item.NoSetting $pdf.Tone.Bad.Solid
            & $number $row.Cells[6] $item.Resources
        }
    }
    if (@($Diagnostic.Workspaces).Count) {
        $section.AddParagraph('Workspaces receiving logs', 'Heading2') | Out-Null
        $table = & $pdf.NewTable @(9.1, 4.0, 3.0, 3.0, 7.0)
        & $pdf.AddHeaderRow $table @('Workspace', 'Location', 'Resources', 'Settings', '') @(2, 3)
        foreach ($item in $Diagnostic.Workspaces) {
            $row = & $pdf.AddBodyRow $table
            $row.Cells[0].AddParagraph($item.Workspace).Format.Font.Name = 'Segoe UI Semibold'
            $row.Cells[1].AddParagraph($item.Location) | Out-Null
            & $number $row.Cells[2] $item.Resources
            & $number $row.Cells[3] $item.Settings
            if (-not $item.Found) { $null = & $small $row.Cells[4] 'not found: deleted, or not visible to the account' $pdf.Tone.Bad.Solid }
            elseif ($false -eq $item.Expected) { $null = & $small $row.Cells[4] 'not an expected workspace' $pdf.Tone.Warn.Solid }
        }
    }

    # --- 3. Misconfigurations ------------------------------------------------------------------------------------------------
    $rank = @{ High = 0; Medium = 1; Low = 2 }
    $groups = @($Diagnostic.Findings | Group-Object Severity, Finding | Sort-Object { $rank[$_.Group[0].Severity] }, { $_.Group[0].Finding })
    if ($groups.Count) {
        $section.AddPageBreak()
        $section.AddParagraph('Misconfigurations', 'Heading2') | Out-Null
        $shown = 0
        foreach ($group in $groups) {
            if ($shown -ge $MaxRows) { break }
            $first = $group.Group[0]
            $heading = $section.AddParagraph("$($first.Finding) ($($group.Count))", 'Heading3')
            $heading.Format.Font.Color = $severityColor[$first.Severity]
            & $note "$($first.Severity) · $($first.Action)"
            $table = & $pdf.NewTable @(7.0, 5.6, 4.0, 9.5)
            & $pdf.AddHeaderRow $table @('Resource', 'Type', 'Setting', 'Detail')
            foreach ($item in @($group.Group | Select-AACFirst ($MaxRows - $shown))) {
                $row = & $pdf.AddBodyRow $table
                $row.Cells[0].AddParagraph($item.Resource).Format.Font.Name = 'Segoe UI Semibold'
                $null = & $small $row.Cells[0] ((@($item.ResourceGroup, $item.SubscriptionName) | Where-Object { $_ }) -join ' / ') $colors.Muted
                $null = & $small $row.Cells[1] $item.ResourceType $null
                $row.Cells[2].AddParagraph([string]$item.Setting) | Out-Null
                $null = & $small $row.Cells[3] $item.Detail $null
                $shown++
            }
        }
    }

    # --- 4. Not exported, by resource type --------------------------------------------------------------------------------
    $missing = @($Diagnostic.Shown | Where-Object Status -In 'No setting', 'Not to workspace', 'Partial')
    if ($missing.Count) {
        $section.AddPageBreak()
        $section.AddParagraph("Logs not (all) reaching Log Analytics ($($missing.Count))", 'Heading2') | Out-Null
        $shown = 0
        foreach ($type in @($missing | Group-Object ResourceType | Sort-Object Count -Descending)) {
            if ($shown -ge $MaxRows) { break }
            $section.AddParagraph("$($type.Name) ($($type.Count))", 'Heading3') | Out-Null
            $table = & $pdf.NewTable @(7.0, 5.0, 5.0, 3.0, 6.1)
            & $pdf.AddHeaderRow $table @('Resource', 'Resource group', 'Subscription', 'Status', 'What''s missing')
            foreach ($item in @($type.Group | Select-AACFirst ($MaxRows - $shown))) {
                $row = & $pdf.AddBodyRow $table
                $row.Cells[0].AddParagraph($item.Resource).Format.Font.Name = 'Segoe UI Semibold'
                $row.Cells[1].AddParagraph($item.ResourceGroup) | Out-Null
                $row.Cells[2].AddParagraph($item.SubscriptionName) | Out-Null
                $status = $row.Cells[3].AddParagraph($item.Status); $status.Format.Font.Color = $statusColor[$item.Status]; $status.Format.Font.Name = 'Segoe UI Semibold'
                $null = & $small $row.Cells[4] $item.Reason $null
                $shown++
            }
        }
        if ($missing.Count -gt $MaxRows) { & $note "... and $($missing.Count - $MaxRows) more: the CSV and HTML reports list them all." }
    }

    Save-AACPdfDocument -Pdf $pdf -Path $Path
}
