function Write-AACReportPdf {
    <#
    .SYNOPSIS
        Writes a report model - the one Show-AACReportView draws and the HTML
        report is written from - as a landscape A4 PDF.
    .DESCRIPTION
        1. The title, the facts (account, tenant, scope), the headline, the
           tiles and the notices.
        2. Each table with rows, under its section: the columns marked Pdf
           (else the first eight shown), sized by type - long text widest -
           with badges in their tone's colour. Up to -MaxRows rows each; the
           CSV and HTML report have every row.
        Each section and table is a bookmark (Save-AACPdfDocument). -Path
        must be a full path.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Report,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Title,

        [int] $MaxRows = 2000
    )

    $pdf = New-AACPdfDocument -Title $Title -Subject $(if ($Report.Contains('Subtitle')) { [string]$Report.Subtitle } else { $Title }) -Landscape
    $section = $pdf.Section
    $colors = $pdf.Colors
    $pt = $pdf.Pt
    $toneColor = @{ good = $pdf.Tone.Good.Solid; bad = $pdf.Tone.Bad.Solid; warn = $pdf.Tone.Warn.Solid; info = $colors.Accent; neutral = $colors.Muted; violet = $colors.Accent }
    $severity = Get-AACSeverityRank
    $note = { param([string] $Text, $Color) $p = $section.AddParagraph($Text); $p.Format.Font.Size = 8; $p.Format.Font.Color = $(if ($Color) { $Color } else { $colors.Muted }); $p.Format.SpaceBefore = & $pt 3 }

    # --- 1. Summary ---------------------------------------------------------------------------------------------
    & $pdf.AddTitle "$(if ($Report.Contains('Subtitle')) { $Report.Subtitle } else { $Title }) · generated $($pdf.Generated.ToString('dddd d MMMM yyyy, HH:mm'))"
    $facts = [ordered]@{}
    if ($script:AACSession) { $facts['Azure account'] = [string]$script:AACSession.Account; $facts['Tenant'] = [string]$script:AACSession.TenantId }
    if ($Report.Contains('Facts') -and $Report.Facts) { foreach ($key in $Report.Facts.Keys) { $facts[[string]$key] = [string]$Report.Facts[$key] } }
    $factTable = & $pdf.NewTable @(4.0, ($pdf.PageWidth - 4.0))
    foreach ($key in $facts.Keys) {
        $row = & $pdf.AddBodyRow $factTable
        $row.Cells[0].AddParagraph($key).Format.Font.Color = $colors.Muted
        $row.Cells[1].AddParagraph($facts[$key]) | Out-Null
    }
    if ($Report.Contains('Headline') -and $Report.Headline) {
        $statusTone = @{ Success = $pdf.Tone.Good.Solid; Warning = $pdf.Tone.Warn.Solid; Failed = $pdf.Tone.Bad.Solid }
        $p = $section.AddParagraph([string]$Report.Headline)
        $p.Format.SpaceBefore = & $pt 8
        $p.Format.Font.Name = 'Segoe UI Semibold'
        $p.Format.Font.Size = 11
        if ($Report.Contains('Status') -and $statusTone.Contains([string]$Report.Status)) { $p.Format.Font.Color = $statusTone[[string]$Report.Status] }
    }
    $section.AddParagraph().Format.SpaceAfter = & $pt 4
    $tileData = @(if ($Report.Contains('Tiles')) { $Report.Tiles })
    if ($tileData.Count) {
        $perRow = [Math]::Min(7, $tileData.Count)
        for ($start = 0; $start -lt $tileData.Count; $start += $perRow) {
            $chunk = @($tileData[$start..([Math]::Min($start + $perRow, $tileData.Count) - 1)])
            $tiles = & $pdf.NewTable @(1..$chunk.Count | ForEach-Object { $pdf.PageWidth / $chunk.Count })
            $tiles.TopPadding = & $pt 7
            $tiles.BottomPadding = & $pt 7
            $tileRow = $tiles.AddRow()
            for ($i = 0; $i -lt $chunk.Count; $i++) {
                $cell = $tileRow.Cells[$i]
                $cell.Shading.Color = $colors.Panel
                $cell.Borders.Left.Width = $(if ($i -gt 0) { 2 } else { 0 })
                $cell.Borders.Left.Color = $colors.White
                $value = $cell.AddParagraph([string]$chunk[$i].Value)
                if ($chunk[$i].Contains('Tone') -and $toneColor.Contains([string]$chunk[$i].Tone)) { $value.Format.Font.Color = $toneColor[[string]$chunk[$i].Tone] }
                $value.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Center
                $value.Format.Font.Size = 16
                $value.Format.Font.Name = 'Segoe UI Semibold'
                $caption = $cell.AddParagraph([string]$chunk[$i].Label)
                $caption.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Center
                $caption.Format.Font.Size = 7.5
                $caption.Format.Font.Color = $colors.Muted
            }
            $section.AddParagraph().Format.SpaceAfter = & $pt 2
        }
    }
    foreach ($n in @(if ($Report.Contains('Notices')) { $Report.Notices })) {
        & $note ([string]$n.Text) $(if ($n.Contains('Status') -and $n.Status -eq 'Failed') { $pdf.Tone.Bad.Solid } elseif ($n.Contains('Status') -and $n.Status -eq 'Warning') { $pdf.Tone.Warn.Solid })
    }

    # --- 2. The tables -------------------------------------------------------------------------------------------
    $lastSection = ''
    foreach ($t in @(if ($Report.Contains('Tables')) { $Report.Tables })) {
        $rows = @($t.Rows | Where-Object { $null -ne $_ })
        if (-not $rows.Count) { continue }
        $sectionName = if ($t.Contains('Section') -and $t.Section) { [string]$t.Section } else { '' }
        if ($sectionName -and $sectionName -ne $lastSection) { $section.AddParagraph($sectionName, 'Heading1') | Out-Null; $lastSection = $sectionName }
        $section.AddParagraph("$($t.Title) ($('{0:N0}' -f $rows.Count))", 'Heading2') | Out-Null
        if ($t.Contains('Note') -and $t.Note) { & $note ([string]$t.Note) }
        $columns = @($t.Columns | Where-Object { -not ($_.Contains('Hidden') -and $_.Hidden) })
        $chosen = @($columns | Where-Object { $_.Contains('Pdf') -and $_.Pdf })
        if (-not $chosen.Count) { $chosen = @($columns | Select-Object -First 8) }
        $weight = @(foreach ($c in $chosen) { switch ($(if ($c.Contains('Type')) { $c.Type } else { 'text' })) { 'wide' { 3.2 } { $_ -in 'mono', 'resource', 'path' } { 2.2 } { $_ -in 'number', 'money', 'score' } { 1.0 } 'badge' { 1.3 } default { 1.7 } } })
        $total = [double](@($weight) | Measure-Object -Sum).Sum
        $table = & $pdf.NewTable @($weight | ForEach-Object { $pdf.PageWidth * $_ / $total })
        $right = @(for ($i = 0; $i -lt $chosen.Count; $i++) { if ($chosen[$i].Contains('Type') -and $chosen[$i].Type -in 'number', 'money', 'score') { $i } })
        & $pdf.AddHeaderRow $table @($chosen | ForEach-Object { [string]$_.Label }) $right
        foreach ($row in @($rows | Select-Object -First $MaxRows)) {
            $pdfRow = & $pdf.AddBodyRow $table
            for ($i = 0; $i -lt $chosen.Count; $i++) {
                $c = $chosen[$i]
                $value = if ($row -is [System.Collections.IDictionary]) { $row[$c.Key] } else { $property = $row.PSObject.Properties[[string]$c.Key]; if ($property) { $property.Value } }
                $text = if ($value -is [datetime]) { $value.ToString('yyyy-MM-dd HH:mm') } elseif ($value -is [double] -or $value -is [decimal]) { '{0:N2}' -f $value } elseif ($value -is [int] -or $value -is [long]) { '{0:N0}' -f $value } else { [string]$value }
                $p = $pdfRow.Cells[$i].AddParagraph($text)
                $p.Format.Font.Size = 7.5
                if ($right -contains $i) { $p.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Right }
                $tone = if ($c.Key -eq 'Severity' -and $severity.Tone.Contains($text)) { $severity.Tone[$text] } elseif ($c.Contains('Tones') -and $c.Tones -and $c.Tones.Contains($text)) { [string]$c.Tones[$text] } else { '' }
                if ($tone -and $toneColor.Contains($tone)) { $p.Format.Font.Color = $toneColor[$tone]; $p.Format.Font.Name = 'Segoe UI Semibold' }
            }
        }
        if ($rows.Count -gt $MaxRows) { & $note "... and $($rows.Count - $MaxRows) more: the CSV and HTML reports list them all." }
    }

    Save-AACPdfDocument -Pdf $pdf -Path $Path
}
