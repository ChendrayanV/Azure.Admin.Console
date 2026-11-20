function Get-AACSentinelRuleTestQuery {
    <#
    .SYNOPSIS
        Plans Test-AACSentinelRuleQuery: for each analytics rule, the run
        windows to replay and the KQL queries that replay them.
    .DESCRIPTION
        -Rule takes analytics rules as Resource Manager returns them (an ad
        hoc query is given the same shape). For each rule:

          the last -Runs windows, as Sentinel would run them: each ends one
          query frequency before the next and looks back the query period,
          sent as the query API's start/end timespan
          '<query> | count'          per window: how many results
          '<query> | getschema'      the columns it returns, even with no rows
          '<query> | take 5'         a sample, from the latest window

        A query that calls ago() or now() measures time from when it runs, not
        from the window's end, so an earlier window can't be replayed: only
        the latest is. NRT rules run every minute; they are tested in 1-hour
        windows, so results are an hour's worth.

        Returns @{ Specs (one hashtable per rule: Name, RuleId, Kind,
        Enabled, Query, Frequency, Period, Operator, Threshold, Grouping,
        Columns (the ones the rule maps), Windows, QueryNames, Note); Queries
        (ordered: name -> @{ Query; Timespan }) }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyCollection()]
        [object[]] $Rule = @(),

        [ValidateRange(1, 48)]
        [int] $Runs = 6,

        [datetime] $Now = [datetime]::UtcNow
    )

    $get = {
        param($Object, [string[]] $Path)
        $value = $Object
        foreach ($key in $Path) {
            if ($value -isnot [System.Collections.IDictionary] -or -not $value.Contains($key)) { return $null }
            $value = $value[$key]
        }
        $value
    }
    $span = { param([string] $Iso, [timespan] $Default) if (-not $Iso) { return $Default }; try { [System.Xml.XmlConvert]::ToTimeSpan($Iso) } catch { $Default } }
    $stamp = { param([datetime] $When) $When.ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture) }
    # Runs end on the minute, as Sentinel's do.
    $end = [datetime]::new($Now.Year, $Now.Month, $Now.Day, $Now.Hour, $Now.Minute, 0, [DateTimeKind]::Utc)

    $specs = [System.Collections.Generic.List[hashtable]]::new()
    $queries = [ordered]@{}
    $n = 0
    foreach ($item in @($Rule | Where-Object { $_ -is [System.Collections.IDictionary] })) {
        $n++
        $properties = & $get $item 'properties'
        $kind = [string]$item['kind']
        $query = [string](& $get $properties 'query')
        $note = ''
        if ($kind -eq 'NRT') {
            $frequency = [timespan]::FromHours(1); $period = [timespan]::FromHours(1)
            $note = 'NRT rules run every minute: tested in 1-hour windows, so results are an hour''s worth.'
        }
        else {
            $frequency = & $span ([string](& $get $properties 'queryFrequency')) ([timespan]::FromHours(1))
            $period = & $span ([string](& $get $properties 'queryPeriod')) $frequency
        }
        $runCount = $Runs
        if ($Runs -gt 1 -and $query -match '(?i)\b(ago|now)\s*\(') {
            $runCount = 1
            $note = (@($note, 'It calls ago() or now(), which count from when it runs, so only the latest window can be replayed.') | Where-Object { $_ }) -join ' '
        }
        # The columns the rule needs its results to have: entities, custom details, alert overrides.
        $columns = [System.Collections.Generic.List[string]]::new()
        foreach ($mapping in @(& $get $properties 'entityMappings' | Where-Object { $_ -is [System.Collections.IDictionary] })) {
            foreach ($field in @($mapping['fieldMappings'] | Where-Object { $_ -is [System.Collections.IDictionary] })) { if ($field['columnName']) { $columns.Add([string]$field['columnName']) } }
        }
        $custom = & $get $properties 'customDetails'
        if ($custom -is [System.Collections.IDictionary]) { foreach ($v in $custom.Values) { if ($v) { $columns.Add([string]$v) } } }
        $override = & $get $properties 'alertDetailsOverride'
        if ($override -is [System.Collections.IDictionary]) {
            foreach ($format in 'alertDisplayNameFormat', 'alertDescriptionFormat') { foreach ($m in [regex]::Matches([string]$override[$format], '\{\{\s*(\w+)\s*\}\}')) { $columns.Add($m.Groups[1].Value) } }
            foreach ($single in 'alertSeverityColumnName', 'alertTacticsColumnName') { if ($override[$single]) { $columns.Add([string]$override[$single]) } }
            foreach ($dynamic in @($override['alertDynamicProperties'] | Where-Object { $_ -is [System.Collections.IDictionary] })) { if ($dynamic['value']) { $columns.Add([string]$dynamic['value']) } }
        }

        $body = $query.TrimEnd()
        while ($body.EndsWith(';')) { $body = $body.Substring(0, $body.Length - 1).TrimEnd() }
        $windows = [System.Collections.Generic.List[hashtable]]::new()
        $names = @{ Schema = "q$($n)schema"; Sample = "q$($n)sample"; Runs = [System.Collections.Generic.List[string]]::new() }
        if ($body) {
            for ($i = 0; $i -lt $runCount; $i++) {
                $windowEnd = $end - [timespan]::FromTicks($frequency.Ticks * $i)
                $windowStart = $windowEnd - $period
                $timespan = "$(& $stamp $windowStart)/$(& $stamp $windowEnd)"
                $key = "q$($n)r$i"
                $windows.Add(@{ Key = $key; Start = $windowStart; End = $windowEnd })
                $names.Runs.Add($key)
                $queries[$key] = @{ Query = "$body`n| count"; Timespan = $timespan }
                if ($i -eq 0) {
                    $queries[$names.Schema] = @{ Query = "$body`n| getschema | project ColumnName"; Timespan = $timespan }
                    $queries[$names.Sample] = @{ Query = "$body`n| take 5"; Timespan = $timespan }
                }
            }
        }
        $specs.Add(@{
                Name      = $(if (& $get $properties 'displayName') { [string](& $get $properties 'displayName') } else { [string]$item['name'] })
                RuleId    = [string]$item['name']
                Kind      = $kind
                Enabled   = [bool](& $get $properties 'enabled')
                Query     = $query
                Frequency = $frequency
                Period    = $period
                Operator  = $(if ($kind -eq 'NRT' -or -not (& $get $properties 'triggerOperator')) { 'GreaterThan' } else { [string](& $get $properties 'triggerOperator') })
                Threshold = [int]$(if ($kind -eq 'NRT') { 0 } else { & $get $properties 'triggerThreshold' })
                Grouping  = $(if (& $get $properties 'eventGroupingSettings', 'aggregationKind') { [string](& $get $properties 'eventGroupingSettings', 'aggregationKind') } else { 'SingleAlert' })
                Columns   = @($columns | Select-Object -Unique)
                Windows   = @($windows)
                QueryNames = $names
                Note      = $note
            })
    }
    @{ Specs = @($specs); Queries = $queries }
}
