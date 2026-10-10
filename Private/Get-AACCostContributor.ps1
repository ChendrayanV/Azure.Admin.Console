function Get-AACCostContributor {
    <#
    .SYNOPSIS
        The resources behind a cost anomaly: from daily cost rows grouped by
        resource, each one's average a day during the anomaly against the
        days before it - the biggest rises first.
    .DESCRIPTION
        -Rows are Cost Management rows (Cost, UsageDate, ResourceId) from
        the days before -Start to -End. Returns up to -Top objects:
        @{ Resource; ResourceId; Before (a day); During (a day); Change }.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowEmptyCollection()]
        [object[]] $Rows = @(),

        [Parameter(Mandatory)]
        [datetime] $Start,

        [Parameter(Mandatory)]
        [datetime] $End,

        [int] $Top = 3
    )

    $value = { param($Row, [string] $Name) if ($Row -is [System.Collections.IDictionary]) { $Row[$Name] } else { $p = $Row.PSObject.Properties[$Name]; if ($p) { $p.Value } } }
    $toDay = { param($Raw) if ($Raw -is [datetime]) { $Raw.Date } elseif ([string]$Raw -match '^\d{8}$') { [datetime]::ParseExact([string]$Raw, 'yyyyMMdd', [cultureinfo]::InvariantCulture) } else { ([datetime]$Raw).Date } }
    $from = $Start.Date
    $to = $End.Date
    $beforeDays = [Math]::Max(1, @($Rows | ForEach-Object { & $toDay (& $value $_ 'UsageDate') } | Where-Object { $_ -lt $from } | Select-Object -Unique).Count)
    $duringDays = [int]($to - $from).TotalDays + 1
    $byResource = @{}
    foreach ($row in $Rows) {
        $id = [string](& $value $row 'ResourceId')
        if (-not $id) { continue }
        $day = & $toDay (& $value $row 'UsageDate')
        if (-not $byResource.Contains($id)) { $byResource[$id] = @{ Before = 0.0; During = 0.0 } }
        if ($day -lt $from) { $byResource[$id].Before += [double](& $value $row 'Cost') }
        elseif ($day -le $to) { $byResource[$id].During += [double](& $value $row 'Cost') }
    }
    @(foreach ($id in $byResource.Keys) {
            $before = $byResource[$id].Before / $beforeDays
            $during = $byResource[$id].During / $duringDays
            [pscustomobject]@{ Resource = ($id.TrimEnd('/') -replace '^.*/', ''); ResourceId = $id; Before = [Math]::Round($before, 2); During = [Math]::Round($during, 2); Change = [Math]::Round($during - $before, 2) }
        }) | Where-Object { $_.Change -gt 0 } | Sort-Object -Property Change -Descending | Select-Object -First $Top
}
