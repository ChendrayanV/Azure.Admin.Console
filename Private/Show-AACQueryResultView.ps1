function Show-AACQueryResultView {
    <#
    .SYNOPSIS
        Renders the rows of any KQL query as a Spectre.Console table - the
        view of Invoke-AACApplicationInsightQuery -Query.
    .DESCRIPTION
        The source and query, a row and column count, then a table of the
        rows: the first -MaxColumns columns (the rest are in the objects and
        the exports), long values shortened, numbers right-aligned. Output
        goes straight to the Spectre console; wrap the call in
        Invoke-AACPagedOutput to page it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Row,

        [System.Collections.IDictionary] $Scope,

        [ValidateRange(1, 20)]
        [int] $MaxColumns = 8,

        [ValidateRange(1, 1000)]
        [int] $MaxRows = 200
    )

    $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
    $glyph = Get-AACGlyph
    $facts = [System.Collections.Generic.List[string]]::new()
    if ($script:AACSession) { $facts.Add("[white]$(& $escape $script:AACSession.Account)[/]") }
    if ($Scope) { foreach ($key in $Scope.Keys) { $facts.Add("$(& $escape $key): $(& $escape $Scope[$key])") } }
    Write-AACMarkup "[grey58]$($facts -join " $($glyph.Dot) ")[/]"
    [Spectre.Console.AnsiConsole]::WriteLine()

    if ($Row.Count -eq 0) {
        Show-AACPanel -Content '[bold]The query returned no rows.[/]' -BorderColor 'grey50' -AllowMarkup
        return
    }
    $columns = @($Row[0].PSObject.Properties.Name)
    Show-AACTileRow -Tile @(
        @{ Value = '{0:N0}' -f $Row.Count; Caption = 'rows'; Color = 'deepskyblue1' }
        @{ Value = '{0:N0}' -f $columns.Count; Caption = 'columns'; Color = 'mediumpurple2' }
    )
    [Spectre.Console.AnsiConsole]::WriteLine()

    $shownColumns = @($columns | Select-Object -First $MaxColumns)
    $numeric = @{}
    foreach ($name in $shownColumns) {
        $numeric[$name] = @($Row | Select-Object -First 50 | Where-Object { $null -ne $_.$name -and [string]$_.$name -ne '' } | Where-Object { $_.$name -isnot [ValueType] -or $_.$name -is [bool] -or $_.$name -is [datetime] }).Count -eq 0
    }
    $table = [Spectre.Console.Table]::new()
    $table.Border = [Spectre.Console.TableBorder]::Rounded
    $table.BorderStyle = [Spectre.Console.Style]::Parse('deepskyblue3_1')
    $table.Expand = $true
    $note = if ($columns.Count -gt $shownColumns.Count) { " $($glyph.Dot) first $($shownColumns.Count) of $($columns.Count) columns" } else { '' }
    $table.Title = [Spectre.Console.TableTitle]::new("[bold deepskyblue1]$($glyph.Bullet) Query results[/] [grey58]$([Math]::Min($MaxRows, $Row.Count)) of $('{0:N0}' -f $Row.Count) rows$note[/]")
    foreach ($name in $shownColumns) {
        $column = [Spectre.Console.TableColumn]::new("[grey62]$(& $escape $name)[/]")
        if ($numeric[$name]) { $column.Alignment = [Spectre.Console.Justify]::Right }
        $table.AddColumn($column) | Out-Null
    }
    foreach ($item in @($Row | Select-Object -First $MaxRows)) {
        $cells = foreach ($name in $shownColumns) {
            $value = $item.$name
            $text = if ($value -is [datetime]) { $value.ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss') } elseif ($null -eq $value) { '' } else { [string]$value }
            if ($text.Length -gt 120) { $text = $text.Substring(0, 117) + '...' }
            [Spectre.Console.Markup]::new("$(if ($numeric[$name]) { '[bold]' } else { '[white]' })$(& $escape $text)[/]")
        }
        [Spectre.Console.TableExtensions]::AddRow($table, [Spectre.Console.Rendering.IRenderable[]]@($cells)) | Out-Null
    }
    [Spectre.Console.AnsiConsole]::Write($table)
}
