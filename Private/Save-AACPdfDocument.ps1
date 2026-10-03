function Save-AACPdfDocument {
    <#
    .SYNOPSIS
        Renders a document from New-AACPdfDocument to a PDF file and returns
        the file.
    .DESCRIPTION
        -Path must already be a full file-system path (resolve it in the
        calling cmdlet with GetUnresolvedProviderPathFromPSPath). Missing
        folders are created and an existing file is overwritten.

        Every heading (Heading1-3) becomes a bookmark, nested by level and
        collapsed (Set-AACPdfOutline), and the file opens with the bookmarks
        panel showing.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        $Pdf,

        [Parameter(Mandatory)]
        [string] $Path
    )

    $folder = Split-Path -Path $Path -Parent
    if ($folder -and -not (Test-Path -LiteralPath $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }
    Set-AACPdfOutline -Document $Pdf.Document
    $renderer = [MigraDoc.Rendering.PdfDocumentRenderer]::new()
    $renderer.Document = $Pdf.Document
    $renderer.RenderDocument()
    $document = $renderer.PdfDocument
    Set-AACPdfOutline -Outline $document.Outlines
    # Open with the bookmarks panel showing: a PDF can't fold its tables
    # away, so its bookmarks - one per heading, collapsed - are how a reader
    # finds the table they want.
    $document.PageMode = [PdfSharp.Pdf.PdfPageMode]::UseOutlines
    $document.Save($Path)
    Get-Item -LiteralPath $Path
}
