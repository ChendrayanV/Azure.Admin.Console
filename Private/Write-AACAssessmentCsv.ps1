function Write-AACAssessmentCsv {
    <#
    .SYNOPSIS
        Writes each Invoke-AACAssessment sheet with rows to its own CSV file
        in -Path (a folder), and returns the files.
    .DESCRIPTION
        One file per sheet, named after it ("Virtual machines.csv"), with
        the sheet's columns in order and the resource ID last - UTF-8, no
        type header, as Export-Csv writes it. Sheets with no rows are left
        out.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Assessment,

        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
    $invalid = [regex]::Escape(-join [System.IO.Path]::GetInvalidFileNameChars())
    foreach ($sheet in $Assessment.Sheets) {
        if (-not @($sheet.Rows).Count) { continue }
        $file = Join-Path -Path $Path -ChildPath "$($sheet.Sheet -replace "[$invalid]", '-').csv"
        $columns = @($sheet.Columns) + @('ResourceId' | Where-Object { $sheet.Columns -notcontains $_ })
        $sheet.Rows | Select-Object -Property $columns | Export-Csv -LiteralPath $file -NoTypeInformation -Encoding utf8
        Get-Item -LiteralPath $file
    }
}
