function ConvertTo-AACSentinelConnectorHealth {
    <#
    .SYNOPSIS
        Turns a workspace's data connectors, the tables' ingestion and delay,
        and Sentinel's health records into connector health and table
        ingestion objects.
    .DESCRIPTION
        No Azure calls, so it can be tested with made-up data.

          -Connector      AAC.SentinelDataConnector objects
          -Table          AAC.SentinelTable objects (Usage over the period)
          -Latency        KQL rows: TableName, Records, P50, P95, MaxDelay,
                          LastRecord, LastIngested ($null when not measured)
          -HealthFailure  AAC.SentinelHealthFailure objects

        A connector's tables: the ones Microsoft's built-in connectors are
        known to write, plus any of its data types that names a table in the
        workspace (codeless connectors name their table). Several connectors
        write SecurityAlert, so its freshness says the table is alive, not
        that every product writing it is.

        Connector status, worst first: Failing (health reported failures),
        Disconnected, NoData (none of its tables had data in the period),
        Silent (no data for -SilentAfterHours), Delayed (95th percentile
        delay over -DelayThresholdMinutes), Healthy, Unknown (no table known).

        Returns @{ Connectors (AAC.SentinelConnectorHealth); Tables
        (AAC.SentinelTableIngestion) }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyCollection()]
        [object[]] $Connector = @(),

        [AllowEmptyCollection()]
        [object[]] $Table = @(),

        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Latency,

        [AllowEmptyCollection()]
        [object[]] $HealthFailure = @(),

        [ValidateRange(1, 720)]
        [int] $SilentAfterHours = 24,

        [ValidateRange(1, 1440)]
        [int] $DelayThresholdMinutes = 30,

        [datetime] $Now = [datetime]::UtcNow
    )

    $known = @{
        AzureActiveDirectory                       = @('SigninLogs', 'AuditLogs', 'AADNonInteractiveUserSignInLogs', 'AADServicePrincipalSignInLogs', 'AADManagedIdentitySignInLogs', 'AADProvisioningLogs')
        Office365                                  = @('OfficeActivity')
        OfficePowerBI                              = @('PowerBIActivity')
        Dynamics365                                = @('Dynamics365Activity')
        AzureSecurityCenter                        = @('SecurityAlert')
        AzureAdvancedThreatProtection              = @('SecurityAlert')
        MicrosoftDefenderAdvancedThreatProtection  = @('SecurityAlert')
        OfficeATP                                  = @('SecurityAlert')
        OfficeIRM                                  = @('SecurityAlert')
        IOT                                        = @('SecurityAlert')
        MicrosoftCloudAppSecurity                  = @('SecurityAlert', 'McasShadowItReporting')
        MicrosoftThreatProtection                  = @('SecurityIncident', 'SecurityAlert', 'DeviceEvents', 'DeviceProcessEvents', 'DeviceNetworkEvents', 'DeviceLogonEvents', 'DeviceFileEvents', 'EmailEvents', 'IdentityLogonEvents', 'CloudAppEvents')
        ThreatIntelligence                         = @('ThreatIntelIndicators', 'ThreatIntelligenceIndicator')
        ThreatIntelligenceTaxii                    = @('ThreatIntelIndicators', 'ThreatIntelligenceIndicator')
        MicrosoftThreatIntelligence                = @('ThreatIntelIndicators', 'ThreatIntelligenceIndicator')
        PremiumMicrosoftDefenderForThreatIntelligence = @('ThreatIntelIndicators', 'ThreatIntelligenceIndicator')
        AmazonWebServicesCloudTrail                = @('AWSCloudTrail')
        AmazonWebServicesS3                        = @('AWSCloudTrail', 'AWSGuardDuty', 'AWSVPCFlow', 'AWSCloudWatch')
        MicrosoftPurviewInformationProtection      = @('MicrosoftPurviewInformationProtection')
    }
    $round = { param($Value, [int] $Digits = 1) if ($null -eq $Value -or "$Value" -eq '') { $null } else { [Math]::Round([double]$Value, $Digits) } }
    $inv = [cultureinfo]::InvariantCulture
    $date = {
        param($Value)
        if ($Value -is [datetime]) { return $Value.ToUniversalTime() }
        $parsed = [datetime]::MinValue
        if ($Value -and [datetime]::TryParse([string]$Value, $inv, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) { return $parsed }
        $null
    }
    $latencyRead = $null -ne $Latency
    $delayByTable = @{}
    foreach ($row in @($Latency | Where-Object { $null -ne $_ })) { $delayByTable[([string]$row['TableName']).ToLowerInvariant()] = $row }
    $usageByTable = @{}
    foreach ($t in @($Table | Where-Object { $null -ne $_ })) { $usageByTable[([string]$t.Table).ToLowerInvariant()] = $t }

    # --- Which connectors write each table ---------------------------------------------------------------------
    $tablesOf = @{}
    $writers = @{}
    foreach ($c in @($Connector | Where-Object { $null -ne $_ })) {
        $names = [System.Collections.Generic.List[string]]::new()
        if ($known.Contains([string]$c.Kind)) { foreach ($n in $known[[string]$c.Kind]) { $names.Add($n) } }
        foreach ($dataType in @(([string]$c.DataTypes) -split ',\s*' | Where-Object { $_ })) {
            if ($usageByTable.Contains($dataType.ToLowerInvariant())) { $names.Add($usageByTable[$dataType.ToLowerInvariant()].Table) }
        }
        $unique = @($names | Select-Object -Unique)
        $tablesOf[[string]$c.ConnectorId] = $unique
        foreach ($n in $unique) {
            $k = $n.ToLowerInvariant()
            if (-not $writers.Contains($k)) { $writers[$k] = [System.Collections.Generic.List[string]]::new() }
            $writers[$k].Add([string]$c.Name)
        }
    }

    # --- Tables ------------------------------------------------------------------------------------------------
    $tableRows = @(foreach ($t in @($Table | Where-Object { $null -ne $_ -and ($_.BillableGB -gt 0 -or $_.NonBillableGB -gt 0) })) {
            $k = ([string]$t.Table).ToLowerInvariant()
            $delay = $delayByTable[$k]
            # The delay query reads records themselves; Usage is hourly. Take the newest either has.
            $last = @($t.LastRecord, $(if ($delay) { & $date $delay['LastRecord'] }) | Where-Object { $_ } | Sort-Object -Descending | Select-AACFirst 1)
            $hours = if ($last.Count) { [Math]::Round(($Now - $last[0]).TotalHours, 1) }
            $p95 = if ($delay) { & $round $delay['P95'] }
            $status = if ($null -ne $hours -and $hours -gt $SilentAfterHours) { 'Silent' } elseif ($null -ne $p95 -and $p95 -gt $DelayThresholdMinutes) { 'Delayed' } else { 'Healthy' }
            [pscustomobject][ordered]@{
                PSTypeName           = 'AAC.SentinelTableIngestion'
                Table                = [string]$t.Table
                Status               = $status
                Connectors           = $(if ($writers.Contains($k)) { @($writers[$k]) -join ', ' } else { '' })
                LastRecord           = $(if ($last.Count) { $last[0] })
                HoursSinceLastRecord = $hours
                DelayP50Minutes      = $(if ($delay) { & $round $delay['P50'] })
                DelayP95Minutes      = $p95
                DelayMaxMinutes      = $(if ($delay) { & $round $delay['MaxDelay'] })
                RecentRecords        = $(if ($delay) { [long]$delay['Records'] } elseif ($latencyRead) { 0 })
                BillableGB           = $t.BillableGB
                DailyAverageGB       = $t.DailyAverageGB
                Plan                 = $t.Plan
                Type                 = $t.Type
            }
        })
    $tableOrder = @{ Silent = 0; Delayed = 1; Healthy = 2 }
    $tableRows = @($tableRows | Sort-Object -Property @{ Expression = { $tableOrder[$_.Status] } }, @{ Expression = 'BillableGB'; Descending = $true })
    $tableByName = @{}
    foreach ($row in $tableRows) { $tableByName[$row.Table.ToLowerInvariant()] = $row }

    # --- Connectors --------------------------------------------------------------------------------------------
    $failuresFor = {
        param($C)
        @($HealthFailure | Where-Object { $_ -and [string]$_.ResourceType -match '(?i)connector' -and ($_.Resource -eq $C.Name -or ($C.ConnectorId -and ([string]$_.ResourceId -match [regex]::Escape([string]$C.ConnectorId) -or $_.Resource -eq $C.ConnectorId))) })
    }
    $connectorRows = @(foreach ($c in @($Connector | Where-Object { $null -ne $_ })) {
            $names = @($tablesOf[[string]$c.ConnectorId])
            $withData = @($names | ForEach-Object { $tableByName[$_.ToLowerInvariant()] } | Where-Object { $null -ne $_ })
            $failures = @(& $failuresFor $c)
            $newest = @($withData | Where-Object LastRecord | Sort-Object LastRecord -Descending | Select-AACFirst 1)
            $hours = if ($newest.Count) { $newest[0].HoursSinceLastRecord }
            $worstDelay = @($withData | ForEach-Object { $_.DelayP95Minutes } | Where-Object { $null -ne $_ } | Measure-Object -Maximum).Maximum
            $failureCount = [int](@($failures | ForEach-Object { $_.Failures } | Measure-Object -Sum).Sum)
            $status = if ($failureCount) { 'Failing' }
            elseif ($c.State -eq 'Disconnected') { 'Disconnected' }
            elseif (-not $names.Count) { 'Unknown' }
            elseif (-not $withData.Count) { 'NoData' }
            elseif ($null -ne $hours -and $hours -gt $SilentAfterHours) { 'Silent' }
            elseif ($null -ne $worstDelay -and $worstDelay -gt $DelayThresholdMinutes) { 'Delayed' }
            else { 'Healthy' }
            $findings = [System.Collections.Generic.List[string]]::new()
            if ($failureCount) { $findings.Add("$failureCount health failure(s): $(@($failures | Sort-Object LastFailure -Descending | Select-AACFirst 1 | ForEach-Object Reason) -join '')") }
            if ($c.State -eq 'Disconnected') { $findings.Add('Disconnected') }
            if ($names.Count -and -not $withData.Count) { $findings.Add("No data in its tables ($($names -join ', '))") }
            if ($status -eq 'Silent' -or ($null -ne $hours -and $hours -gt $SilentAfterHours)) { $findings.Add("No data for $hours hours") }
            if ($null -ne $worstDelay -and $worstDelay -gt $DelayThresholdMinutes) { $findings.Add("Records arrive up to $([Math]::Round($worstDelay, 1)) minutes late (95th percentile): rules with a short look-back can miss them") }
            [pscustomobject][ordered]@{
                PSTypeName           = 'AAC.SentinelConnectorHealth'
                Name                 = $c.Name
                Status               = $status
                Kind                 = $c.Kind
                State                = $c.State
                Tables               = $names -join ', '
                TablesWithData       = $withData.Count
                LastRecord           = $(if ($newest.Count) { $newest[0].LastRecord })
                HoursSinceLastRecord = $hours
                DelayP95Minutes      = $(if ($null -ne $worstDelay) { [Math]::Round([double]$worstDelay, 1) })
                BillableGB           = [Math]::Round([double](@($withData | ForEach-Object { $_.BillableGB } | Measure-Object -Sum).Sum), 3)
                HealthFailures       = $failureCount
                LastFailure          = $(if ($failures.Count) { @($failures | Sort-Object LastFailure -Descending)[0].LastFailure })
                Findings             = $findings -join '; '
                DataTypes            = $c.DataTypes
                ConnectorId          = $c.ConnectorId
            }
        })
    $connectorOrder = @{ Failing = 0; Disconnected = 1; NoData = 2; Silent = 3; Delayed = 4; Unknown = 5; Healthy = 6 }
    @{
        Connectors = @($connectorRows | Sort-Object -Property @{ Expression = { $connectorOrder[$_.Status] } }, 'Name')
        Tables     = $tableRows
    }
}
