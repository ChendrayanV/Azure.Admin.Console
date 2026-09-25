function Save-AACPdfDocument {
    <#
    .SYNOPSIS
        Renders a document from New-AACPdfDocument to a PDF file and returns
        the file.
    .DESCRIPTION
        -Path must already be a full file-system path (resolve it in the
        calling cmdlet with GetUnresolvedProviderPathFromPSPath). Missing
        folders are created and an existing file is overwritten.
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
    $renderer = [MigraDoc.Rendering.PdfDocumentRenderer]::new()
    $renderer.Document = $Pdf.Document
    $renderer.RenderDocument()
    $renderer.PdfDocument.Save($Path)
    Get-Item -LiteralPath $Path
}
