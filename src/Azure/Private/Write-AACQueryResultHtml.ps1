function Write-AACQueryResultHtml {
    <#
    .SYNOPSIS
        Writes the rows of any KQL query as an interactive HTML table - the
        -HtmlPath report of Invoke-AACApplicationInsightQuery -Query.
    .DESCRIPTION
        Every column of the result, in its order: numbers right-aligned and
        totalled, dates shown in local time, text columns with a handful of
        distinct values as filters.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Row,

        [Parameter(Mandatory)]
        [string] $Path,

        [string] $Title = 'Query results',

        [System.Collections.IDictionary] $Detail
    )

    $names = if ($Row.Count) { @($Row[0].PSObject.Properties.Name) } else { @() }
    $sample = @($Row | Select-Object -First 200)
    $columns = @(foreach ($name in $names) {
            $values = @($sample | ForEach-Object { $_.$name } | Where-Object { $null -ne $_ -and [string]$_ -ne '' })
            $numeric = $values.Count -gt 0 -and @($values | Where-Object { $_ -isnot [ValueType] -or $_ -is [bool] -or $_ -is [datetime] }).Count -eq 0
            $dates = $values.Count -gt 0 -and @($values | Where-Object { $_ -isnot [datetime] }).Count -eq 0
            $distinct = @($values | ForEach-Object { [string]$_ } | Select-Object -Unique).Count
            $column = @{ Key = $name; Label = $name }
            if ($numeric) { $column.Type = 'number'; $column.Format = 'N0'; $column.Sum = $true }
            elseif ($dates) { $column.Type = 'datetime' }
            elseif (@($values | Where-Object { ([string]$_).Length -gt 80 }).Count) { $column.Type = 'wide' }
            elseif ($distinct -gt 1 -and $distinct -le 30) { $column.Facet = $true }
            $column
        })
    $table = @{
        Id      = 'rows'
        Title   = 'Query results'
        Noun    = 'rows'
        File    = 'QueryResults'
        Rows    = $Row
        GroupBy = @($columns | Where-Object { $_['Facet'] } | ForEach-Object { $_['Key'] })
        Columns = $columns
    }
    $tiles = @(
        @{ Value = '{0:N0}' -f $Row.Count; Label = 'rows'; Tone = 'info'; Table = 'rows' }
        @{ Value = '{0:N0}' -f $names.Count; Label = 'columns'; Tone = 'violet' }
    )
    Write-AACHtmlReport -Path $Path -Title $Title -Subtitle "$('{0:N0}' -f $Row.Count) rows" -Fact $Detail -Tile $tiles -Table @($table)
}
