function Invoke-AACReportOutput {
    <#
    .SYNOPSIS
        The end of every expert command: the exports (CSV, HTML, PDF) as
        progress steps, then the console view, then the objects - one way,
        so all of them behave alike.
    .DESCRIPTION
        -Report is the model Show-AACReportView, Write-AACHtmlReport and
        Write-AACReportPdf take; -CsvObject the rows the CSV gets (usually
        the findings). Paths must be full paths.
          at the prompt     the view (paged; -NoPaging turns it off)
          with an export    the files, and no view
          -ReturnObject     the -Object rows are returned (the caller works
                            out -PassThru, -NoDisplay and piping)
        The HTML report is tabbed when the report has Tabs; its first tab is
        'Summary'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Report,

        [Parameter(Mandatory)]
        [string] $Title,

        [AllowEmptyCollection()]
        [object[]] $CsvObject = @(),

        [string] $Noun = 'row',

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [switch] $ShowView,

        [switch] $NoPaging,

        [AllowEmptyCollection()]
        [object[]] $Object = @(),

        [switch] $ReturnObject
    )

    if ($CsvPath -or $HtmlPath -or $PdfPath) {
        $null = Invoke-AACProgress -ScriptBlock {
            $null = Invoke-AACExport -CsvPath $CsvPath -CsvObject $CsvObject -Noun $Noun -PdfPath $PdfPath -WritePdf {
                Write-AACReportPdf -Report $Report -Path $PdfPath -Title $Title
            } -HtmlPath $HtmlPath -WriteHtml {
                $html = @{
                    Path = $HtmlPath; Title = $Title; Fact = $(if ($Report.Contains('Facts')) { $Report.Facts } else { [ordered]@{} })
                    Subtitle = $(if ($Report.Contains('Subtitle')) { [string]$Report.Subtitle } else { '' })
                    Tile = @(if ($Report.Contains('Tiles')) { $Report.Tiles }); Chart = @(if ($Report.Contains('Charts')) { $Report.Charts | Where-Object { -not ($_.Contains('NoHtml') -and $_.NoHtml) -and @($_.Items).Count } | ForEach-Object { $c = @{}; foreach ($k in $_.Keys) { if ($k -notin 'Console', 'NoHtml') { $c[$k] = $_[$k] } }; $c } })
                    Table = @(if ($Report.Contains('Tables')) { $Report.Tables | Where-Object { @($_.Rows).Count } | ForEach-Object { $t = @{}; foreach ($k in $_.Keys) { if ($k -notin 'ConsoleLimit', 'Empty', 'EmptyStatus', 'NoConsole') { $t[$k] = $_[$k] } }; $t } })
                    Notice = @(if ($Report.Contains('Notices')) { $Report.Notices | ForEach-Object { @{ Tone = @{ Success = 'good'; Warning = 'warn'; Failed = 'bad'; Info = 'info'; InProgress = 'info' }[$(if ($_.Contains('Status')) { [string]$_.Status } else { 'Warning' })]; Text = [string]$_.Text } } })
                }
                if ($Report.Contains('Headline') -and $Report.Headline) { $html.Notice = @(@{ Tone = @{ Success = 'good'; Warning = 'warn'; Failed = 'bad'; Info = 'info' }[$(if ($Report.Contains('Status')) { [string]$Report.Status } else { 'Info' })]; Text = [string]$Report.Headline }) + @($html.Notice) }
                if ($Report.Contains('Tabs') -and $Report.Tabs) { $html.Tab = @($Report.Tabs); $html.OverviewTab = 'Summary' }
                if ($Report.Contains('Tree') -and $Report.Tree) { $html.Tree = $Report.Tree }
                Write-AACHtmlReport @html
            }
        }
    }
    elseif ($ShowView) {
        Invoke-AACPagedOutput -NoPaging:$NoPaging -ScriptBlock { Show-AACReportView -Report $Report }
    }
    if ($ReturnObject) { $Object }
}
