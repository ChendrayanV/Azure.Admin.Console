function ConvertTo-AACSentinelThreatIntel {
    <#
    .SYNOPSIS
        Turns Get-AACSentinelThreatIntelQuery's results, the threat
        intelligence connectors and the analytics rules into the threat
        intelligence summary: a row per source and indicator type, the
        indicators themselves, and what is wrong.
    .DESCRIPTION
        No Azure calls, so it can be tested with made-up rows.

          -Kql         Invoke-AACLogQueryBatch's @{ Rows; Errors } for stix,
                       legacy and (optionally) stixList, legacyList
          -Connector   AAC.SentinelDataConnector objects
          -Rule        AAC.SentinelAnalyticsRule objects

        A query that failed because its table doesn't exist means the
        workspace has no indicators there; any other failure is in Errors.

        Returns @{ Sources (AAC.SentinelThreatIntelSource, those with
        findings first); Indicators (AAC.SentinelThreatIndicator); Notices
        (@{ Status; Text }); HasStix; HasLegacy; Errors }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [System.Collections.IDictionary] $Kql = @{ Rows = @{}; Errors = @{} },

        [AllowEmptyCollection()]
        [object[]] $Connector = @(),

        [AllowEmptyCollection()]
        [object[]] $Rule = @(),

        [ValidateRange(1, 365)]
        [int] $StaleAfterDays = 7,

        [datetime] $Now = [datetime]::UtcNow
    )

    $inv = [cultureinfo]::InvariantCulture
    $date = {
        param($Value)
        if ($Value -is [datetime]) { return $Value.ToUniversalTime() }
        $parsed = [datetime]::MinValue
        if ($Value -and [datetime]::TryParse([string]$Value, $inv, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) { return $parsed }
        $null
    }
    $number = { param($Value) if ($null -eq $Value -or "$Value" -eq '') { 0.0 } else { [double]$Value } }
    $errors = [ordered]@{}
    $tableName = @{ stix = 'ThreatIntelIndicators'; legacy = 'ThreatIntelligenceIndicator'; stixList = 'ThreatIntelIndicators'; legacyList = 'ThreatIntelligenceIndicator' }
    # Present: the query ran. A missing table is an answer (no indicators there), not an error.
    $present = @{}
    foreach ($name in 'stix', 'legacy', 'stixList', 'legacyList') {
        if ($Kql.Errors.Contains($name)) {
            $reason = [string]$Kql.Errors[$name]
            if ($reason -notmatch "(?i)failed to resolve.*$($tableName[$name])") { $errors[$tableName[$name]] = $reason }
        }
        elseif ($Kql.Rows.Contains($name)) { $present[$name] = $true }
    }
    $rows = { param([string] $Name) @($Kql.Rows[$Name] | Where-Object { $null -ne $_ }) }
    $hasStix = $present.Contains('stix') -and (& $rows 'stix').Count -gt 0
    $hasLegacy = $present.Contains('legacy') -and (& $rows 'legacy').Count -gt 0

    $sources = @(foreach ($name in 'stix', 'legacy') {
            foreach ($row in & $rows $name) {
                $count = [int](& $number $row['Indicators'])
                $active = [int](& $number $row['Active'])
                $low = [int](& $number $row['LowConfidence'])
                $updated = & $date $row['LastUpdated']
                $daysSince = if ($updated) { [int][Math]::Floor(($Now - $updated).TotalDays) }
                $findings = [System.Collections.Generic.List[string]]::new()
                if ($null -ne $daysSince -and $daysSince -gt $StaleAfterDays) { $findings.Add("No update for $daysSince days") }
                if ($count -and -not $active) { $findings.Add('None active') }
                if ($count -and $low * 2 -gt $count) { $findings.Add('Mostly low confidence') }
                [pscustomobject][ordered]@{
                    PSTypeName        = 'AAC.SentinelThreatIntelSource'
                    Source            = [string]$row['Source']
                    IndicatorType     = [string]$row['IndicatorType']
                    Indicators        = $count
                    Active            = $active
                    Expired           = [int](& $number $row['Expired'])
                    ExpiringSoon      = [int](& $number $row['ExpiringSoon'])
                    AverageConfidence = $(if ($null -ne $row['AverageConfidence'] -and "$($row['AverageConfidence'])" -ne '') { [Math]::Round([double]$row['AverageConfidence'], 1) })
                    LowConfidence     = $low
                    LastUpdated       = $updated
                    DaysSinceUpdate   = $daysSince
                    Findings          = $findings -join '; '
                    Table             = $tableName[$name]
                }
            }
        })
    $sources = @($sources | Sort-Object -Property @{ Expression = { [bool]$_.Findings }; Descending = $true }, @{ Expression = 'Indicators'; Descending = $true }, 'Source')

    $indicators = @(foreach ($name in 'stixList', 'legacyList') {
            foreach ($row in & $rows $name) {
                $until = & $date $row['ValidUntil']
                $isActive = ($row['IsActive'] -eq $true -or [string]$row['IsActive'] -eq 'true') -and -not ($until -and $until -le $Now)
                $tags = $row['Tags']
                [pscustomobject][ordered]@{
                    PSTypeName    = 'AAC.SentinelThreatIndicator'
                    Value         = [string]$row['Value']
                    IndicatorType = [string]$row['IndicatorType']
                    Source        = [string]$row['Source']
                    Confidence    = $(if ("$($row['Confidence'])" -ne '') { [int](& $number $row['Confidence']) })
                    Active        = [bool]$isActive
                    ValidFrom     = & $date $row['ValidFrom']
                    ValidUntil    = $until
                    LastUpdated   = & $date $row['LastUpdated']
                    Name          = [string]$row['Name']
                    # Tags come as a list, or as its JSON text.
                    Tags          = $(if ($tags -is [System.Collections.IEnumerable] -and $tags -isnot [string]) { @($tags) -join ', ' } else { @((([string]$tags).Trim('[', ']') -replace '"', '') -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join ', ' })
                    Description   = [string]$row['Description']
                    Table         = $tableName[$name]
                    Id            = [string]$row['Id']
                }
            }
        })
    $indicators = @($indicators | Sort-Object -Property @{ Expression = { $_.LastUpdated }; Descending = $true })

    # --- What is wrong overall --------------------------------------------------------------------------------
    $notices = [System.Collections.Generic.List[hashtable]]::new()
    $tiConnectors = @($Connector | Where-Object { [string]$_.Kind -match 'ThreatIntelligence' })
    foreach ($c in @($tiConnectors | Where-Object State -EQ 'Disconnected')) { $notices.Add(@{ Status = 'Warning'; Text = "The threat intelligence connector $($c.Name) is disconnected." }) }
    if (-not $hasStix -and -not $hasLegacy -and -not $errors.Count) {
        $notices.Add(@{ Status = 'Warning'; Text = 'No threat indicators arrived in the period: rules that match on threat intelligence have nothing to match. Connect a feed (Microsoft Defender Threat Intelligence, TAXII or the upload API).' })
    }
    $enabledQueries = @($Rule | Where-Object { $_.Enabled -and $_.Query })
    $readsStix = @($enabledQueries | Where-Object { $_.Query -match '(?i)\bThreatIntelIndicators\b' })
    $readsLegacy = @($enabledQueries | Where-Object { $_.Query -match '(?i)\bThreatIntelligenceIndicator\b' })
    if (($hasStix -or $hasLegacy) -and $Rule.Count -and -not $readsStix.Count -and -not $readsLegacy.Count) {
        $notices.Add(@{ Status = 'Warning'; Text = 'No enabled analytics rule reads the threat intelligence tables: the indicators are collected but never matched. Enable the "TI map" rule templates for the data you collect.' })
    }
    if ($readsLegacy.Count -and -not $hasLegacy) {
        $notices.Add(@{ Status = 'Warning'; Text = "$($readsLegacy.Count) enabled rule(s) read ThreatIntelligenceIndicator, which has no indicators: move them to ThreatIntelIndicators ($(@($readsLegacy | Select-AACFirst 3 | ForEach-Object Name) -join ', '))." })
    }
    elseif ($hasLegacy -and -not $hasStix) {
        $notices.Add(@{ Status = 'Info'; Text = 'Indicators only arrive in the legacy ThreatIntelligenceIndicator table, which Microsoft is retiring: plan the move to ThreatIntelIndicators.' })
    }

    @{
        Sources    = $sources
        Indicators = $indicators
        Notices    = @($notices)
        HasStix    = $hasStix
        HasLegacy  = $hasLegacy
        Errors     = $errors
    }
}
