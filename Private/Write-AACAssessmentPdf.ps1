function Write-AACAssessmentPdf {
    <#
    .SYNOPSIS
        Writes the Invoke-AACAssessment report as a landscape A4 PDF.
    .DESCRIPTION
        1. Summary: the scope, tiles, the subscriptions, the resources by
           category and the most common resource types.
        2. A section per category (Overview, Compute, Networking, ...,
           Advisor, Security, Policy, Health, Cost) - each sheet with its key
           columns (a PDF page can't hold them all; the HTML and CSV have
           every column) and up to -RowLimit rows (most severe or most
           relevant first, as the sheet is sorted).
        Every category and sheet is a bookmark (Set-AACPdfOutline).
        -Path must be a full path; see Save-AACPdfDocument.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Assessment,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Title,

        [System.Collections.IDictionary] $Detail,

        [ValidateRange(10, 5000)]
        [int] $RowLimit = 300
    )

    $stats = $Assessment.Stats
    $pdf = New-AACPdfDocument -Title $Title -Subject "$($stats.Resources) resources in $($stats.Subscriptions) subscriptions" -Landscape
    $section = $pdf.Section
    $colors = $pdf.Colors
    $pt = $pdf.Pt
    $small = { param($Paragraph) $Paragraph.Format.Font.Size = 7; $Paragraph }
    $right = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Right
    $severity = @{ High = $pdf.Tone.Bad.Solid; Critical = $pdf.Tone.Bad.Solid; Medium = $pdf.Tone.Warn.Solid; Yes = $pdf.Tone.Warn.Solid }
    $cellText = {
        param($Value)
        if ($null -eq $Value) { return '' }
        if ($Value -is [double] -or $Value -is [decimal]) { return ('{0:N2}' -f $Value) }
        if ($Value -is [int] -or $Value -is [long]) { return ('{0:N0}' -f $Value) }
        $text = [string]$Value
        if ($text.Length -gt 240) { $text = $text.Substring(0, 237) + '...' }
        $text
    }
    $writeTable = {
        param($Sheet, [string[]] $Columns)
        $shown = @($Columns | Where-Object { $Sheet.Columns -contains $_ } | Select-Object -First 8)
        if (-not $shown.Count) { $shown = @($Sheet.Columns | Select-Object -First 7) }
        $numeric = @(for ($i = 0; $i -lt $shown.Count; $i++) { if ([string]$Sheet.Types[$shown[$i]] -in 'number', 'money', 'score') { $i } })
        $widths = @($shown | ForEach-Object { $pdf.PageWidth / $shown.Count })
        $table = & $pdf.NewTable $widths
        & $pdf.AddHeaderRow $table $shown $numeric
        $rows = @($Sheet.Rows)
        foreach ($item in $rows | Select-Object -First $RowLimit) {
            $row = & $pdf.AddBodyRow $table
            for ($i = 0; $i -lt $shown.Count; $i++) {
                $value = $item.($shown[$i])
                $p = & $small ($row.Cells[$i].AddParagraph((& $cellText $value)))
                if ($i -in $numeric) { $p.Format.Alignment = $right }
                if ($shown[$i] -in 'Impact', 'Severity', 'Orphaned', 'Empty' -and $severity.Contains([string]$value)) { $p.Format.Font.Color = $severity[[string]$value]; $p.Format.Font.Bold = $true }
            }
        }
        if ($rows.Count -gt $RowLimit) {
            $more = & $small ($section.AddParagraph("The first $RowLimit of $('{0:N0}' -f $rows.Count) rows - the HTML report and the CSV files have them all."))
            $more.Format.Font.Color = $colors.Muted
        }
    }

    # --- 1. Summary --------------------------------------------------------------------------------------------
    & $pdf.AddTitle "Azure environment assessment · generated $($pdf.Generated.ToString('dddd d MMMM yyyy, HH:mm'))"
    $facts = [ordered]@{}
    if ($script:AACSession) { $facts['Azure account'] = [string]$script:AACSession.Account; $facts['Tenant'] = [string]$script:AACSession.TenantId }
    if ($Detail) { foreach ($key in $Detail.Keys) { $facts[[string]$key] = [string]$Detail[$key] } }
    $factTable = & $pdf.NewTable @(4.5, ($pdf.PageWidth - 4.5))
    foreach ($key in $facts.Keys) {
        $row = & $pdf.AddBodyRow $factTable
        $row.Cells[0].AddParagraph($key).Format.Font.Color = $colors.Muted
        $row.Cells[1].AddParagraph($facts[$key]) | Out-Null
    }
    $section.AddParagraph().Format.SpaceAfter = & $pt 6
    $tileData = @(
        @{ Value = '{0:N0}' -f $stats.Subscriptions; Label = 'subscriptions' }
        @{ Value = '{0:N0}' -f $stats.ResourceGroups; Label = 'resource groups' }
        @{ Value = '{0:N0}' -f $stats.Resources; Label = 'resources' }
        @{ Value = '{0:N0}' -f $stats.ResourceTypes; Label = 'resource types' }
        @{ Value = '{0:N0}' -f $stats.Retirements; Label = 'retiring features'; Color = $(if ($stats.Retirements) { $pdf.Tone.Warn.Solid }) }
        if ($null -ne $stats.Advisor) { @{ Value = '{0:N0}' -f $stats.AdvisorHigh; Label = 'Advisor High'; Color = $(if ($stats.AdvisorHigh) { $pdf.Tone.Bad.Solid }) } }
        if ($null -ne $stats.Security) { @{ Value = '{0:N0}' -f $stats.SecurityHigh; Label = 'Defender High'; Color = $(if ($stats.SecurityHigh) { $pdf.Tone.Bad.Solid }) } }
        @{ Value = '{0:N0}' -f $stats.Orphans; Label = 'unattached / empty'; Color = $(if ($stats.Orphans) { $pdf.Tone.Warn.Solid }) }
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
        $value.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Center
        $value.Format.Font.Size = 16
        $value.Format.Font.Name = 'Segoe UI Semibold'
        if ($tileData[$i].Contains('Color') -and $tileData[$i].Color) { $value.Format.Font.Color = $tileData[$i].Color }
        $caption = $cell.AddParagraph($tileData[$i].Label)
        $caption.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Center
        $caption.Format.Font.Size = 8
        $caption.Format.Font.Color = $colors.Muted
    }

    # --- 2. Each category, each sheet -----------------------------------------------------------------------------
    $categories = [System.Collections.Generic.List[string]]::new()
    foreach ($sheet in $Assessment.Sheets) { if (-not $categories.Contains($sheet.Category)) { $categories.Add($sheet.Category) } }
    foreach ($category in $categories) {
        $members = @($Assessment.Sheets | Where-Object { $_.Category -eq $category -and (@($_.Rows).Count -or $_.Error) })
        if (-not $members.Count) { continue }
        $section.AddPageBreak()
        $section.AddParagraph($category, 'Heading1') | Out-Null
        foreach ($sheet in $members) {
            $section.AddParagraph("$($sheet.Sheet) ($('{0:N0}' -f @($sheet.Rows).Count))", 'Heading2') | Out-Null
            if ($sheet.Note) { (& $small ($section.AddParagraph($sheet.Note))).Format.Font.Color = $colors.Muted }
            if ($sheet.Error) { (& $small ($section.AddParagraph("Couldn't be read: $($sheet.Error)"))).Format.Font.Color = $pdf.Tone.Bad.Solid; continue }
            & $writeTable $sheet @($sheet.Key)
        }
    }

    Save-AACPdfDocument -Pdf $pdf -Path $Path
}
