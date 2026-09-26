function Invoke-AACExport {
    <#
    .SYNOPSIS
        Writes a command's CSV and/or PDF export as steps of the progress
        display, and returns the PDF file (if one was written).
    .DESCRIPTION
        Every command that exports uses this, so exports look the same
        everywhere: a line per file that finishes as, for example,

          ✓ CSV: 412 recommendation(s) written to C:\out\Advisor.csv
          ✓ PDF: C:\out\Advisor.pdf

        -CsvPath and -PdfPath must be full paths. The CSV is written with
        Export-Csv (UTF-8, no type header) from -CsvObject; missing folders
        are created. -WritePdf is a script block that writes the PDF and
        returns its file. Inside another command's progress display the
        lines join that display; otherwise they get one of their own.
    #>
    [CmdletBinding()]
    param(
        [string] $CsvPath,

        [AllowEmptyCollection()]
        [object[]] $CsvObject = @(),

        # What one CSV row is, for the finished line: 'rule', 'recommendation'...
        [string] $Noun = 'row',

        [string] $PdfPath,

        [scriptblock] $WritePdf
    )

    if (-not $CsvPath -and -not $PdfPath) {
        return
    }

    Invoke-AACProgress -ScriptBlock {
        if ($CsvPath) {
            Update-AACProgress -Id 'export-csv' -Description 'Writing the CSV file' -Indeterminate
            $folder = Split-Path -Path $CsvPath -Parent
            if ($folder -and -not (Test-Path -LiteralPath $folder)) {
                New-Item -ItemType Directory -Path $folder -Force | Out-Null
            }
            $CsvObject | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding utf8 -Force
            Update-AACProgress -Id 'export-csv' -Complete -Description ('CSV: {0:N0} {1}(s) written to {2}' -f $CsvObject.Count, $Noun, $CsvPath)
        }
        if ($PdfPath) {
            Update-AACProgress -Id 'export-pdf' -Description 'Writing the PDF report' -Indeterminate
            $file = & $WritePdf
            Update-AACProgress -Id 'export-pdf' -Complete -Description "PDF: $(if ($file) { $file.FullName } else { $PdfPath })"
            $file
        }
    }
}
