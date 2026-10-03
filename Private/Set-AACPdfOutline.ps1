function Set-AACPdfOutline {
    <#
    .SYNOPSIS
        Shapes a report's PDF bookmarks: one per heading, no untitled
        entries, every entry with children collapsed.
    .DESCRIPTION
        MigraDoc makes a bookmark of every Heading1-3 paragraph, nested by
        level. Where a report skips a level - a Heading2 with no Heading1
        above it, a Heading3 straight under a Heading1 - it puts an untitled
        bookmark in between, a blank line in the viewer's bookmarks panel.

        -Document (before rendering): each heading's outline level is
        clamped to at most one below the heading before it, so no level is
        skipped and no untitled bookmark is made. Only the bookmark level
        changes; the heading looks the same.

        -Outline (after rendering, PdfDocument.Outlines): every bookmark
        with children is closed, so the panel opens as a short list of
        sections the reader unfolds.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Changes a PDF document in memory, before it is saved.')]
    param(
        # A MigraDoc.DocumentObjectModel.Document. Untyped: the PDF libraries
        # load only on the first export, after this module is parsed.
        [Parameter(Mandatory, ParameterSetName = 'Document')]
        $Document,

        [Parameter(Mandatory, ParameterSetName = 'Outline')]
        [AllowEmptyCollection()]
        $Outline
    )

    if ($PSCmdlet.ParameterSetName -eq 'Document') {
        # The headings still open above this one, by their style's level: a
        # heading nests under those with a smaller level, and is a sibling of
        # one with the same level - whatever levels were skipped in between.
        $open = [System.Collections.Generic.Stack[int]]::new()
        foreach ($section in $Document.Sections) {
            foreach ($element in $section.Elements) {
                if ($element -isnot [MigraDoc.DocumentObjectModel.Paragraph] -or [string]$element.Style -notmatch '^Heading([1-9])$') { continue }
                $level = [int]$Matches[1]
                while ($open.Count -and $open.Peek() -ge $level) { $null = $open.Pop() }
                $element.Format.OutlineLevel = [MigraDoc.DocumentObjectModel.OutlineLevel]"Level$($open.Count + 1)"
                $open.Push($level)
            }
        }
        return
    }

    foreach ($item in $Outline) {
        if ($item.Outlines.Count) {
            Set-AACPdfOutline -Outline $item.Outlines
            $item.Opened = $false
        }
    }
}
