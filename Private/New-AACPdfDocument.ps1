function New-AACPdfDocument {
    <#
    .SYNOPSIS
        Starts an A4 PDF document in the module's report style, and returns
        it with the helpers the report commands build their pages with.
    .DESCRIPTION
        Shared by Export-AACPesterReport and Export-AACFirewallRule so every
        PDF the module writes looks the same: Segoe UI, a blue accent,
        headings, a header line with the title and date, and a footer with
        "Page X of Y".

        Loads the PDF libraries first (Import-AACPdfLibrary checks every DLL's
        pinned SHA-256 before loading it).

        The returned object carries:
          Document, Section   the MigraDoc document and its one section
          PageWidth           usable width in cm (17.4 portrait, 26.1 landscape)
          Colors              Ink, Muted, Rule, Panel, Accent, White, Amber
          Tone                Good / Bad / Neutral / Warn, each with Text,
                              Fill (light background) and Solid colors
          Generated           when the document was started
          Cm, Pt, Color       unit and color helpers: & $pdf.Cm 2.5
          NewTable            & $pdf.NewTable @(widths in cm) - a borderless table
          AddHeaderRow        & $pdf.AddHeaderRow $table @(labels) @(right-aligned column indexes)
          AddBodyRow          & $pdf.AddBodyRow $table - a row with a thin rule under it
          AddTitle            & $pdf.AddTitle 'Subtitle text' - the big title block

        Write it with Save-AACPdfDocument.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Title,

        [string] $Subject,

        [switch] $Landscape
    )

    Import-AACPdfLibrary

    $cm = { param([double] $Value) [MigraDoc.DocumentObjectModel.Unit]::FromCentimeter($Value) }
    $pt = { param([double] $Value) [MigraDoc.DocumentObjectModel.Unit]::FromPoint($Value) }
    $color = {
        param([string] $Hex)
        [MigraDoc.DocumentObjectModel.Color]::new([Convert]::ToByte($Hex.Substring(1, 2), 16), [Convert]::ToByte($Hex.Substring(3, 2), 16), [Convert]::ToByte($Hex.Substring(5, 2), 16))
    }
    $colors = @{
        Ink    = & $color '#1F2937'
        Muted  = & $color '#6B7280'
        Rule   = & $color '#E5E7EB'
        Panel  = & $color '#F3F4F6'
        Accent = & $color '#0F4C81'
        White  = & $color '#FFFFFF'
        Amber  = & $color '#CA8A04'
    }
    $tone = @{
        Good    = @{ Text = (& $color '#166534'); Fill = (& $color '#DCFCE7'); Solid = (& $color '#16A34A') }
        Bad     = @{ Text = (& $color '#991B1B'); Fill = (& $color '#FEE2E2'); Solid = (& $color '#DC2626') }
        Neutral = @{ Text = (& $color '#374151'); Fill = (& $color '#E5E7EB'); Solid = (& $color '#9CA3AF') }
        Warn    = @{ Text = (& $color '#854D0E'); Fill = (& $color '#FEF9C3'); Solid = (& $color '#CA8A04') }
    }
    # A4 is 21 x 29.7 cm; 1.8 cm margins either side.
    $pageWidth = if ($Landscape) { 26.1 } else { 17.4 }
    $generated = Get-Date

    $doc = [MigraDoc.DocumentObjectModel.Document]::new()
    $doc.Info.Title = $Title
    $doc.Info.Author = 'Azure Admin Console'
    if ($Subject) { $doc.Info.Subject = $Subject }

    $normal = $doc.Styles['Normal']
    $normal.Font.Name = 'Segoe UI'
    $normal.Font.Size = 9
    $normal.Font.Color = $colors.Ink
    foreach ($level in @(@{ Name = 'Heading1'; Size = 15; Before = 0; After = 8 }, @{ Name = 'Heading2'; Size = 12; Before = 16; After = 4 }, @{ Name = 'Heading3'; Size = 10; Before = 10; After = 4 })) {
        $heading = $doc.Styles[$level.Name]
        $heading.Font.Name = 'Segoe UI Semibold'
        $heading.Font.Size = $level.Size
        $heading.Font.Bold = $false
        $heading.Font.Color = $colors.Accent
        $heading.ParagraphFormat.SpaceBefore = & $pt $level.Before
        $heading.ParagraphFormat.SpaceAfter = & $pt $level.After
        $heading.ParagraphFormat.KeepWithNext = $true
    }

    $section = $doc.AddSection()
    $section.PageSetup = $doc.DefaultPageSetup.Clone()
    # The page size is set explicitly: the cloned default setup carries fixed
    # portrait dimensions, which win over PageFormat/Orientation.
    $section.PageSetup.PageFormat = [MigraDoc.DocumentObjectModel.PageFormat]::A4
    $section.PageSetup.Orientation = [MigraDoc.DocumentObjectModel.Orientation]::Portrait
    $section.PageSetup.PageWidth = & $cm $(if ($Landscape) { 29.7 } else { 21.0 })
    $section.PageSetup.PageHeight = & $cm $(if ($Landscape) { 21.0 } else { 29.7 })
    $section.PageSetup.TopMargin = & $cm 2.2
    $section.PageSetup.BottomMargin = & $cm 1.8
    $section.PageSetup.LeftMargin = & $cm 1.8
    $section.PageSetup.RightMargin = & $cm 1.8
    $section.PageSetup.HeaderDistance = & $cm 1.0
    $section.PageSetup.FooterDistance = & $cm 0.8

    $header = $section.Headers.Primary.AddParagraph()
    $header.Format.Font.Size = 8
    $header.Format.Font.Color = $colors.Muted
    $header.Format.AddTabStop((& $cm $pageWidth), [MigraDoc.DocumentObjectModel.TabAlignment]::Right) | Out-Null
    $header.Format.Borders.Bottom.Width = 0.5
    $header.Format.Borders.Bottom.Color = $colors.Rule
    $header.Format.Borders.DistanceFromBottom = & $pt 3
    $header.AddText($Title) | Out-Null
    $header.AddTab() | Out-Null
    $header.AddText($generated.ToString('d MMM yyyy HH:mm')) | Out-Null

    $footer = $section.Footers.Primary.AddParagraph()
    $footer.Format.Font.Size = 8
    $footer.Format.Font.Color = $colors.Muted
    $footer.Format.AddTabStop((& $cm $pageWidth), [MigraDoc.DocumentObjectModel.TabAlignment]::Right) | Out-Null
    $footer.AddText('Generated by Azure Admin Console') | Out-Null
    $footer.AddTab() | Out-Null
    $footer.AddText('Page ') | Out-Null
    $footer.AddPageField() | Out-Null
    $footer.AddText(' of ') | Out-Null
    $footer.AddNumPagesField() | Out-Null

    # The helpers are closures, so they keep working after this function
    # returns (they capture $section, $cm, $pt and $colors).
    $newTable = {
        param([double[]] $Widths)
        $table = $section.AddTable()
        $table.Borders.Width = 0
        $table.TopPadding = & $pt 3
        $table.BottomPadding = & $pt 3
        $table.LeftPadding = & $pt 4
        $table.RightPadding = & $pt 4
        foreach ($width in $Widths) { $table.AddColumn((& $cm $width)) | Out-Null }
        $table
    }.GetNewClosure()
    $addHeaderRow = {
        param($Table, [string[]] $Labels, [int[]] $RightAligned = @())
        $row = $Table.AddRow()
        $row.HeadingFormat = $true
        $row.Shading.Color = $colors.Panel
        $row.Format.Font.Size = 8
        $row.Format.Font.Color = $colors.Muted
        $row.Borders.Bottom.Width = 0.75
        $row.Borders.Bottom.Color = $colors.Rule
        for ($i = 0; $i -lt $Labels.Count; $i++) {
            $row.Cells[$i].AddParagraph($Labels[$i]) | Out-Null
            if ($i -in $RightAligned) { $row.Cells[$i].Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Right }
        }
    }.GetNewClosure()
    $addBodyRow = {
        param($Table)
        $row = $Table.AddRow()
        $row.Borders.Bottom.Width = 0.5
        $row.Borders.Bottom.Color = $colors.Rule
        $row.VerticalAlignment = [MigraDoc.DocumentObjectModel.Tables.VerticalAlignment]::Top
        $row
    }.GetNewClosure()
    $addTitle = {
        param([string] $Subtitle)
        $titleParagraph = $section.AddParagraph($Title)
        $titleParagraph.Format.Font.Name = 'Segoe UI Semibold'
        $titleParagraph.Format.Font.Size = 22
        $titleParagraph.Format.Font.Color = $colors.Accent
        $titleParagraph.Format.SpaceAfter = & $pt 2
        if ($Subtitle) {
            $subtitleParagraph = $section.AddParagraph($Subtitle)
            $subtitleParagraph.Format.Font.Color = $colors.Muted
            $subtitleParagraph.Format.SpaceAfter = & $pt 14
        }
    }.GetNewClosure()

    [pscustomobject]@{
        Document     = $doc
        Section      = $section
        PageWidth    = $pageWidth
        Colors       = $colors
        Tone         = $tone
        Generated    = $generated
        Cm           = $cm
        Pt           = $pt
        Color        = $color
        NewTable     = $newTable
        AddHeaderRow = $addHeaderRow
        AddBodyRow   = $addBodyRow
        AddTitle     = $addTitle
    }
}
