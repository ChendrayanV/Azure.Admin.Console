function Show-AACReportView {
    <#
    .SYNOPSIS
        Draws a report model at the console - the same model the HTML and
        PDF reports are written from - so the expert commands' views all look
        alike.
    .DESCRIPTION
        The model (a hashtable):
          Facts      ordered: label -> value, the grey line under the title
          Status     Success, Warning or Failed - the headline's state
          Headline   one line: what matters most
          Tiles      @{ Value; Label; Tone } (tone: good, bad, warn, info,
                     neutral, violet), drawn as Show-AACTileRow tiles
          Notices    @{ Status; Text } status lines
          Charts     @{ Title; Items = @{ Label; Value }; Console = $true } -
                     those marked Console are drawn as bar charts
          Tables     @{ Title; Rows; Columns; ConsoleLimit (15) } - the
                     columns marked Console (else the first six shown) of
                     the first ConsoleLimit rows; badge columns in their
                     tone's colour, severities with their status symbol
          Hint       a grey line at the end (the parameters to go further)
        Tables with no rows are left out, unless they say Empty (a callout).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Report
    )

    $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
    $glyph = Get-AACGlyph
    $toneColor = @{ good = 'green3'; bad = 'red1'; warn = 'orange1'; info = 'deepskyblue1'; neutral = 'grey70'; violet = 'mediumpurple2' }
    $severity = Get-AACSeverityRank
    $has = { param([string] $Key) $Report.Contains($Key) -and $null -ne $Report[$Key] }

    $facts = [System.Collections.Generic.List[string]]::new()
    if ($script:AACSession) { $facts.Add("[white]$(& $escape $script:AACSession.Account)[/]") }
    if (& $has 'Facts') { foreach ($key in $Report.Facts.Keys) { $facts.Add("$(& $escape $key): $(& $escape $Report.Facts[$key])") } }
    $facts.Add((Get-Date).ToString('d MMM yyyy HH:mm'))
    Write-AACMarkup "[grey58]$($facts -join " $($glyph.Dot) ")[/]"
    [Spectre.Console.AnsiConsole]::WriteLine()
    if (& $has 'Headline') {
        Write-AACStatusLine $(if (& $has 'Status') { $Report.Status } else { 'Info' }) ([string]$Report.Headline)
        [Spectre.Console.AnsiConsole]::WriteLine()
    }
    if ((& $has 'Tiles') -and @($Report.Tiles).Count) {
        Show-AACTileRow -Tile @(foreach ($t in $Report.Tiles) { @{ Value = [string]$t.Value; Caption = [string]$t.Label; Color = $(if ($t.Contains('Tone') -and $toneColor.Contains([string]$t.Tone)) { $toneColor[[string]$t.Tone] } else { 'deepskyblue1' }) } })
        [Spectre.Console.AnsiConsole]::WriteLine()
    }
    if (& $has 'Notices') {
        foreach ($n in @($Report.Notices)) { Write-AACStatusLine $(if ($n.Contains('Status')) { $n.Status } else { 'Warning' }) ([string]$n.Text) }
        if (@($Report.Notices).Count) { [Spectre.Console.AnsiConsole]::WriteLine() }
    }
    if (& $has 'Charts') {
        foreach ($c in @($Report.Charts | Where-Object { $_.Contains('Console') -and $_.Console -and @($_.Items).Count })) {
            Show-AACBarChart -Item @(foreach ($i in @($c.Items) | Select-Object -First 12) { @{ Label = [string]$i.Label; Value = [double]$i.Value } }) -Title ([string]$c.Title)
            [Spectre.Console.AnsiConsole]::WriteLine()
        }
    }

    foreach ($t in @(if (& $has 'Tables') { $Report.Tables })) {
        $rows = @($t.Rows | Where-Object { $null -ne $_ })
        if (-not $rows.Count) {
            if ($t.Contains('Empty') -and $t.Empty) { Show-AACCallout $(if ($t.Contains('EmptyStatus')) { $t.EmptyStatus } else { 'Success' }) "[bold]$(& $escape $t.Empty)[/]" -Title ([string]$t.Title); [Spectre.Console.AnsiConsole]::WriteLine() }
            continue
        }
        if ($t.Contains('NoConsole') -and $t.NoConsole) { continue }
        $columns = @($t.Columns | Where-Object { -not ($_.Contains('Hidden') -and $_.Hidden) })
        $chosen = @($columns | Where-Object { $_.Contains('Console') -and $_.Console })
        if (-not $chosen.Count) { $chosen = @($columns | Select-Object -First 6) }
        $limit = if ($t.Contains('ConsoleLimit')) { [int]$t.ConsoleLimit } else { 15 }
        $table = [Spectre.Console.Table]::new()
        $table.Border = [Spectre.Console.TableBorder]::Rounded
        $table.BorderStyle = [Spectre.Console.Style]::Parse('grey35')
        $title = "[bold]$(& $escape $t.Title)[/]$(if ($rows.Count -gt $limit) { " [grey58](top $limit of $($rows.Count))[/]" } else { " [grey58]($($rows.Count))[/]" })"
        $table.Title = [Spectre.Console.TableTitle]::new($title)
        foreach ($c in $chosen) {
            $column = [Spectre.Console.TableColumn]::new("[grey70]$(& $escape $c.Label)[/]")
            if ($c.Contains('Type') -and $c.Type -in 'number', 'money', 'score') { $column.Alignment = [Spectre.Console.Justify]::Right }
            $null = $table.AddColumn($column)
        }
        foreach ($row in @($rows | Select-Object -First $limit)) {
            $cells = foreach ($c in $chosen) {
                $value = if ($row -is [System.Collections.IDictionary]) { $row[$c.Key] } else { $p = $row.PSObject.Properties[[string]$c.Key]; if ($p) { $p.Value } }
                $text = if ($value -is [datetime]) { $value.ToString('d MMM HH:mm') } elseif ($value -is [double] -or $value -is [decimal]) { if ($c.Contains('Format')) { $value.ToString($c.Format) } else { '{0:N2}' -f $value } } elseif ($value -is [int] -or $value -is [long]) { '{0:N0}' -f $value } else { [string]$value }
                $type = if ($c.Contains('Type')) { $c.Type } else { 'text' }
                if ($c.Key -eq 'Severity' -and $severity.Status.Contains($text)) {
                    "$((Get-AACStatus $severity.Status[$text]).Markup) [$($toneColor[$severity.Tone[$text]])]$(& $escape $text)[/]"
                }
                elseif ($c.Key -eq 'Status' -and $text -in 'Success', 'Warning', 'Failed', 'Info', 'InProgress') {
                    $state = Get-AACStatus $text
                    "$($state.Markup) [$($state.Color)]$(& $escape $text)[/]"
                }
                elseif ($type -eq 'badge' -and $c.Contains('Tones') -and $c.Tones -and $c.Tones.Contains($text) -and $toneColor.Contains([string]$c.Tones[$text])) {
                    "[$($toneColor[[string]$c.Tones[$text]])]$(& $escape $text)[/]"
                }
                elseif ($type -eq 'resource') { "[white]$(& $escape $text)[/]" }
                elseif ($type -in 'mono', 'link') { "[grey58]$(& $escape $text)[/]" }
                elseif ($type -eq 'wide') { "[grey70]$(& $escape $text)[/]" }
                else { & $escape $text }
            }
            $null = [Spectre.Console.TableExtensions]::AddRow($table, [Spectre.Console.Rendering.IRenderable[]]@($cells | ForEach-Object { [Spectre.Console.Markup]::new($_) }))
        }
        [Spectre.Console.AnsiConsole]::Write($table)
        [Spectre.Console.AnsiConsole]::WriteLine()
    }
    if (& $has 'Hint') { Write-AACMarkup "[grey42]$(& $escape $Report.Hint)[/]" }
}
