function ConvertTo-AACSentinelRuleQueryTest {
    <#
    .SYNOPSIS
        Turns Get-AACSentinelRuleTestQuery's plan and the query results into
        AAC.SentinelRuleQueryTest objects: per rule, what each replayed run
        returned, whether it would have alerted, and what is wrong.
    .DESCRIPTION
        No Azure calls, so it can be tested with made-up results.

        A run alerts when its result count passes the rule's trigger
        (GreaterThan 0 unless the rule says otherwise). Alerts per run: one,
        or one per result up to Sentinel's 150 when the rule groups
        AlertPerResult.

        Findings: the query fails; columns the rule maps (entities, custom
        details, alert overrides) are missing from its results; a look-back
        over Sentinel's 14 days; a frequency longer than the look-back (events
        between runs are never seen); alerting in every run tested (three or
        more); reaching 150 alerts in a run; over 10,000 characters; searching
        every table.
    #>
    [CmdletBinding()]
    [OutputType('AAC.SentinelRuleQueryTest')]
    param(
        [AllowEmptyCollection()]
        [object[]] $Spec = @(),

        [System.Collections.IDictionary] $Kql = @{ Rows = @{}; Errors = @{} }
    )

    $iso = { param([timespan] $Span) [System.Xml.XmlConvert]::ToString($Span) }
    $compare = {
        param([string] $Operator, [double] $Count, [double] $Threshold)
        switch ($Operator) { 'LessThan' { $Count -lt $Threshold } 'Equal' { $Count -eq $Threshold } 'NotEqual' { $Count -ne $Threshold } default { $Count -gt $Threshold } }
    }
    $alertCap = 150

    foreach ($s in @($Spec | Where-Object { $_ -is [System.Collections.IDictionary] })) {
        $error1 = ''
        foreach ($k in @($s.QueryNames.Schema) + @($s.QueryNames.Runs)) { if (-not $error1 -and $Kql.Errors.Contains($k)) { $error1 = [string]$Kql.Errors[$k] } }
        if (-not $s.Query) { $error1 = 'The rule has no query (only scheduled and NRT rules can be tested).' }
        $detail = @(foreach ($w in @($s.Windows)) {
                $failed = $Kql.Errors.Contains($w.Key)
                $rows = @($Kql.Rows[$w.Key] | Where-Object { $null -ne $_ })
                $count = if (-not $failed -and $rows.Count) { [long]$rows[0]['Count'] } elseif (-not $failed) { 0 } else { $null }
                $alerts = $null -ne $count -and (& $compare $s.Operator $count $s.Threshold)
                [pscustomobject][ordered]@{
                    PSTypeName  = 'AAC.SentinelRuleQueryRun'
                    Rule        = $s.Name
                    WindowStart = $w.Start
                    WindowEnd   = $w.End
                    Results     = $count
                    WouldAlert  = [bool]$alerts
                    Alerts      = $(if (-not $alerts) { 0 } elseif ($s.Grouping -eq 'AlertPerResult') { [Math]::Min([long]$count, [long]$alertCap) } else { 1 })
                    Error       = $(if ($failed) { [string]$Kql.Errors[$w.Key] } else { '' })
                }
            })
        $ok = @($detail | Where-Object { $null -ne $_.Results })
        $schemaRead = $Kql.Rows.Contains($s.QueryNames.Schema) -and -not $Kql.Errors.Contains($s.QueryNames.Schema)
        $columns = @(if ($schemaRead) { $Kql.Rows[$s.QueryNames.Schema] | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_['ColumnName'] } })
        # Column names are case-sensitive in KQL, and so in Sentinel's mappings.
        $missing = @(if ($schemaRead) { $s.Columns | Where-Object { $columns -cnotcontains $_ } })
        $alerting = @($ok | Where-Object WouldAlert)

        $findings = [System.Collections.Generic.List[string]]::new()
        if ($error1) { $findings.Add("Query fails: $error1") }
        if ($missing.Count) { $findings.Add("Columns the rule maps aren't in its results: $($missing -join ', ')") }
        if ($s.Period -gt [timespan]::FromDays(14)) { $findings.Add('Looks back over 14 days: Sentinel allows at most 14') }
        if ($s.Kind -ne 'NRT' -and $s.Frequency -gt $s.Period) { $findings.Add("Runs every $(& $iso $s.Frequency) but looks back $(& $iso $s.Period): events between runs are never seen") }
        if ($ok.Count -ge 3 -and $alerting.Count -eq $ok.Count) { $findings.Add("Would alert in every one of the $($ok.Count) runs tested: likely noisy") }
        if (@($ok | Where-Object { $_.Alerts -ge $alertCap }).Count) { $findings.Add("Reaches Sentinel's $alertCap alerts in a run: the rest are dropped") }
        if ($s.Query.Length -gt 10000) { $findings.Add('Over 10,000 characters: Sentinel refuses longer queries') }
        if ($s.Query -match '(?i)\b(search\s+\*|union\s+\*)') { $findings.Add('Searches every table (search * or union *): slow and costly') }

        $sample = @(if ($Kql.Rows.Contains($s.QueryNames.Sample)) { $Kql.Rows[$s.QueryNames.Sample] | Where-Object { $null -ne $_ } })
        $latest = @($detail | Select-AACFirst 1)
        [pscustomobject][ordered]@{
            PSTypeName      = 'AAC.SentinelRuleQueryTest'
            Name            = $s.Name
            Status          = $(if ($error1) { 'Error' } elseif ($findings.Count) { 'Warning' } elseif ($alerting.Count) { 'Alerting' } else { 'Quiet' })
            Kind            = $s.Kind
            Enabled         = $s.Enabled
            Frequency       = & $iso $s.Frequency
            Period          = & $iso $s.Period
            Trigger         = "$($s.Operator) $($s.Threshold)"
            Grouping        = $s.Grouping
            Runs            = $ok.Count
            RunsAlerting    = $alerting.Count
            LatestResults   = $(if ($latest.Count) { $latest[0].Results })
            AverageResults  = $(if ($ok.Count) { [Math]::Round((@($ok | Measure-Object -Property Results -Average).Average), 1) })
            MaxResults      = $(if ($ok.Count) { [long](@($ok | Measure-Object -Property Results -Maximum).Maximum) })
            EstimatedAlerts = [int](@($ok | ForEach-Object { $_.Alerts } | Measure-Object -Sum).Sum)
            Findings        = $findings -join '; '
            MissingColumns  = $missing -join ', '
            Columns         = $columns -join ', '
            Error           = $error1
            Note            = $s.Note
            RuleId          = $s.RuleId
            Sample          = $sample
            RunDetail       = $detail
            Query           = $s.Query
        }
    }
}
