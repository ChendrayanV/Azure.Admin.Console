function Get-AACSentinelDataConnector {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Shows the health of a Microsoft Sentinel workspace's data connectors -
        state, the tables each writes, when data last arrived, how late it
        arrives, and the failures health monitoring reported - and, with
        -View Table, ingestion and delay per table.
    .DESCRIPTION
        Reads the workspace - read-only, nothing is changed - from:
          Azure Resource Manager   the data connectors and the tables
          the workspace itself     KQL: Usage over -Days (volume and last
                                   record per table), _SentinelHealth
                                   (connector failures), and, for the tables
                                   with data in the last day, the delay
                                   between each record's TimeGenerated and
                                   when it was ingested, over the last 6 hours

        -View Connector (the default), one row per connector
        (AAC.SentinelConnectorHealth): Name, Status, Kind, State, Tables,
        TablesWithData, LastRecord, HoursSinceLastRecord, DelayP95Minutes,
        BillableGB, HealthFailures, LastFailure, Findings, DataTypes and
        ConnectorId. Status, worst first: Failing, Disconnected, NoData,
        Silent (nothing for -SilentAfterHours), Delayed (95th percentile over
        -DelayThresholdMinutes), Unknown (no table known for it), Healthy.

        -View Table, one row per table with data (AAC.SentinelTableIngestion):
        Table, Status, Connectors, LastRecord, HoursSinceLastRecord,
        DelayP50Minutes, DelayP95Minutes, DelayMaxMinutes, RecentRecords,
        BillableGB, DailyAverageGB, Plan and Type. Sources fed by the Azure
        Monitor Agent or data collection rules (Windows events, Syslog, CEF)
        aren't data connectors to the API, so they show here and not in the
        connector view.

        A connector's tables are the ones Microsoft's connectors are known to
        write, plus any data type that names a table. Several products write
        SecurityAlert, so its freshness proves the table, not each product.
        -SkipLatency leaves out the delay query, which reads 6 hours of every
        busy table.

        Needs Microsoft Sentinel Reader and Log Analytics Reader on the
        workspace.
    .PARAMETER WorkspaceId
        The workspace: its workspace ID (GUID), resource ID or name.
    .PARAMETER SubscriptionId
        Where to look for a workspace given by ID (GUID) or name. Every
        subscription the account can see by default.
    .PARAMETER ResourceGroupName
        Narrows a workspace given by name, when the name is in more than one
        resource group.
    .PARAMETER View
        Connector (the default) or Table.
    .PARAMETER Name
        Only connectors (or tables) whose name matches; wildcards work.
    .PARAMETER Days
        How far back to read volume and health: 1 to 90 days, 7 by default.
    .PARAMETER SilentAfterHours
        Call a connector or table silent after this many hours without data:
        24 by default.
    .PARAMETER DelayThresholdMinutes
        Call ingestion delayed when the 95th percentile delay is over this:
        30 minutes by default.
    .PARAMETER SkipLatency
        Don't measure ingestion delay.
    .PARAMETER CsvPath
        Write the rows to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report to this file.
    .PARAMETER PdfPath
        Write a PDF report to this file.
    .PARAMETER Title
        The HTML and PDF reports' title.
    .PARAMETER PassThru
        Show the view and also return the rows.
    .PARAMETER NoDisplay
        Return the rows without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once instead of a page at a time.
    .EXAMPLE
        Connect-AAC
        Get-AACSentinelDataConnector -WorkspaceId 'law-contoso-sentinel'
        Every data connector's health, the unhealthy ones first.
    .EXAMPLE
        Get-AACSentinelDataConnector -WorkspaceId 'law-contoso-sentinel' -View Table -NoDisplay | Where-Object DelayP95Minutes -GT 15
        The tables whose records arrive more than 15 minutes late.
    .EXAMPLE
        Get-AACSentinelDataConnector -WorkspaceId 'law-contoso-sentinel' -SilentAfterHours 6 -HtmlPath .\out\Connectors.html
        Connector health with a tighter silence threshold, as an HTML report.
    .OUTPUTS
        AAC.SentinelConnectorHealth, or AAC.SentinelTableIngestion with -View Table (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.SentinelConnectorHealth', 'AAC.SentinelTableIngestion')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [Alias('Workspace', 'WorkspaceName', 'ResourceId')]
        [ValidateNotNullOrEmpty()]
        [string] $WorkspaceId,

        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string] $ResourceGroupName,

        [ValidateSet('Connector', 'Table')]
        [string] $View = 'Connector',

        [SupportsWildcards()]
        [string[]] $Name,

        [ValidateRange(1, 90)]
        [int] $Days = 7,

        [ValidateRange(1, 720)]
        [int] $SilentAfterHours = 24,

        [ValidateRange(1, 1440)]
        [int] $DelayThresholdMinutes = 30,

        [switch] $SkipLatency,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Microsoft Sentinel data connectors',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    # A failure anywhere below ends as a Spectre.Console error panel and this
    # command's own terminating error, not a line inside the module. A stopped
    # pipeline (Select-Object -First, Ctrl+C) is no failure: just return - a
    # rethrow would stop the caller's whole script, not only this command.
    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Target) if ($Target) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Target) } }
    $insights = 'providers/Microsoft.SecurityInsights'
    $arm = [ordered]@{
        dataConnectors = "$insights/dataConnectors?api-version=2025-09-01"
        tables         = 'tables?api-version=2022-10-01'
    }
    # Usage per table and health, as the assessment reads them.
    $kql = Get-AACSentinelAssessmentQuery -Section Tables, Health -Days $Days
    # The delay query names each table: past this many, it would be too long to run.
    $maxLatencyTables = 150
    # Read here, not inside the progress block (it runs in Invoke-AACProgress's scope).
    $request = @{ Target = $WorkspaceId.Trim(); SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ResourceGroupName = $ResourceGroupName; Arm = $arm; Kql = $kql; Days = $Days; SkipLatency = [bool]$SkipLatency; MaxTables = $maxLatencyTables }

    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Microsoft Sentinel data connectors' -Color 'deepskyblue3_1' }
    $outcome = Invoke-AACProgress -ScriptBlock {
        $null = Get-AACAccessToken
        Update-AACProgress -Id 'read' -Indeterminate -Description "Reading the data connectors and ingestion of $($request.Target)"
        $read = Read-AACSentinelWorkspace -Target $request.Target -SubscriptionId $request.SubscriptionId -ResourceGroupName $request.ResourceGroupName -Arm $request.Arm -Kql $request.Kql -Timespan "P$($request.Days)D"
        $sentinel = ConvertTo-AACSentinelAssessment -Workspace $read.Workspace -Arm $read.Arm -Kql $read.Kql -Days $request.Days
        Update-AACProgress -Id 'read' -Complete -Description "Workspace $($read.Name): $(@($sentinel.DataConnectors).Count) connector(s), $(@($sentinel.Tables | Where-Object { $_.BillableGB -gt 0 -or $_.NonBillableGB -gt 0 }).Count) table(s) with data"

        $latency = $null
        $latencyError = ''
        $recent = @($sentinel.Tables | Where-Object { $_.LastRecord -and $_.LastRecord -gt [datetime]::UtcNow.AddDays(-1) } | Sort-Object BillableGB -Descending | Select-AACFirst $request.MaxTables)
        if (-not $request.SkipLatency -and $recent.Count) {
            Update-AACProgress -Id 'delay' -Indeterminate -Description "Measuring ingestion delay in $($recent.Count) table(s)"
            $names = @($recent | ForEach-Object { "['$($_.Table -replace "'", "\'")']" }) -join ', '
            $query = @"
union isfuzzy=true withsource=TableName $names
| where ingestion_time() > ago(6h)
| extend DelayMinutes = datetime_diff('second', ingestion_time(), TimeGenerated) / 60.0
| summarize Records = count(), P50 = percentile(DelayMinutes, 50), P95 = percentile(DelayMinutes, 95), MaxDelay = max(DelayMinutes), LastRecord = max(TimeGenerated), LastIngested = max(ingestion_time()) by TableName
"@
            # Two days of TimeGenerated, so records that arrived very late are still in.
            $delayRead = Invoke-AACLogQueryBatch -WorkspaceId $read.WorkspaceId -Query @{ delay = $query } -Timespan 'P2D'
            if ($delayRead.Errors.Contains('delay')) { $latencyError = [string]$delayRead.Errors['delay'] } else { $latency = @($delayRead.Rows['delay']) }
            Update-AACProgress -Id 'delay' -Complete -Description "Measured ingestion delay$(if ($latencyError) { ': failed' })"
        }
        $health = ConvertTo-AACSentinelConnectorHealth -Connector @($sentinel.DataConnectors) -Table @($sentinel.Tables) -Latency $latency -HealthFailure @($sentinel.HealthFailures)
        @{ Read = $read; Sentinel = $sentinel; Health = $health; LatencyError = $latencyError; Measured = $recent.Count }
    }
    $read = $outcome.Read
    if ($read.Arm['dataConnectors'].Error -and $View -eq 'Connector') {
        $problem = [System.InvalidOperationException]::new("Azure Admin Console couldn't read the data connectors of $($read.Name): $($read.Arm['dataConnectors'].Error)")
        $problem.Data['AACHint'] = 'Your account needs Microsoft Sentinel Reader on the workspace. -View Table shows ingestion without the connectors.'
        throw $problem
    }
    $notices = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($k in $outcome.Sentinel.Errors.Keys) { if ($k -ne 'Data connectors') { $notices.Add(@{ Status = 'Warning'; Text = "$k couldn't be read: $($outcome.Sentinel.Errors[$k])" }) } }
    if ($outcome.Sentinel.HealthState -in 'Off', 'NoRecords') { $notices.Add(@{ Status = 'Info'; Text = 'Sentinel health monitoring has no records, so connector failures aren''t reported: turn it on under Sentinel''s Settings.' }) }
    if ($outcome.LatencyError) { $notices.Add(@{ Status = 'Warning'; Text = "Ingestion delay couldn't be measured: $($outcome.LatencyError)" }) }
    if ($SkipLatency) { $notices.Add(@{ Status = 'Info'; Text = 'Ingestion delay wasn''t measured (-SkipLatency).' }) }

    $connectors = @($outcome.Health.Connectors)
    $tables = @($outcome.Health.Tables)
    if ($Name) {
        $connectors = @($connectors | Where-Object { $c = $_; @($Name | Where-Object { $c.Name -like $_ -or $c.ConnectorId -like $_ }).Count })
        $tables = @($tables | Where-Object { $t = $_; @($Name | Where-Object { $t.Table -like $_ }).Count })
    }

    # --- The report -------------------------------------------------------------------------------------------
    $connectorTones = @{ Failing = 'bad'; Disconnected = 'bad'; NoData = 'warn'; Silent = 'warn'; Delayed = 'warn'; Unknown = 'neutral'; Healthy = 'good' }
    $tableTones = @{ Silent = 'warn'; Delayed = 'warn'; Healthy = 'good' }
    $count = { param($Rows, [string] $Status) @($Rows | Where-Object Status -EQ $Status).Count }
    $unhealthy = @($connectors | Where-Object { $_.Status -in 'Failing', 'Disconnected', 'NoData', 'Silent', 'Delayed' }).Count
    $worst = @($tables | ForEach-Object { $_.DelayP95Minutes } | Where-Object { $null -ne $_ } | Measure-Object -Maximum).Maximum
    $headline = if ($View -eq 'Table') {
        "$($tables.Count) table(s) with data: $(& $count $tables 'Silent') silent, $(& $count $tables 'Delayed') delayed$(if ($null -ne $worst) { "; worst delay $([Math]::Round([double]$worst, 1)) minutes (95th percentile)" })"
    }
    elseif (-not $connectors.Count) { "No data connectors on $($read.Name). Sources fed by agents show with -View Table." }
    else { "$($connectors.Count) connector(s): $unhealthy unhealthy - $(& $count $connectors 'Failing') failing, $(& $count $connectors 'Disconnected') disconnected, $(& $count $connectors 'NoData') with no data, $(& $count $connectors 'Silent') silent, $(& $count $connectors 'Delayed') delayed" }
    $connectorTable = @{ Id = 'connectors'; Title = 'Data connectors'; Section = 'Connectors'; Rows = $connectors; Noun = 'connectors'; File = 'sentinel-connector-health'; GroupBy = @('Status', 'Kind'); ConsoleLimit = 30; NoConsole = ($View -eq 'Table')
        Empty = 'No data connectors are listed for this workspace.'; EmptyStatus = 'Info'; Hover = @('Findings', 'Tables'); HoverTitle = 'Name'
        Columns = @(
            @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = $connectorTones; Facet = $true; Console = $true; Pdf = $true }
            @{ Key = 'Name'; Label = 'Connector'; Type = 'wide'; Console = $true; Pdf = $true }
            @{ Key = 'State'; Label = 'State'; Facet = $true; Console = $true }
            @{ Key = 'HoursSinceLastRecord'; Label = 'Hours since data'; Type = 'number'; Console = $true; Pdf = $true }
            @{ Key = 'DelayP95Minutes'; Label = 'Delay P95 (min)'; Type = 'number'; Console = $true; Pdf = $true }
            @{ Key = 'HealthFailures'; Label = 'Failures'; Type = 'number'; Console = $true }
            @{ Key = 'Findings'; Label = 'Findings'; Type = 'wide'; Console = $true; Pdf = $true }
            @{ Key = 'Tables'; Label = 'Tables'; Type = 'wide' }
            @{ Key = 'BillableGB'; Label = 'Billable GB'; Type = 'number' }
            @{ Key = 'Kind'; Label = 'Kind'; Type = 'mono'; Facet = $true }
            @{ Key = 'LastRecord'; Label = 'Last record'; Type = 'datetime' }
            @{ Key = 'ConnectorId'; Label = 'Connector ID'; Type = 'mono'; Hidden = $true }
        ) }
    $tableTable = @{ Id = 'tables'; Title = 'Table ingestion'; Section = 'Tables'; Rows = $tables; Noun = 'tables'; File = 'sentinel-table-ingestion'; GroupBy = @('Status'); ConsoleLimit = 30; NoConsole = ($View -eq 'Connector')
        Empty = "No table received data in the last $Days day(s)."; EmptyStatus = 'Warning'
        Columns = @(
            @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = $tableTones; Facet = $true; Console = $true; Pdf = $true }
            @{ Key = 'Table'; Label = 'Table'; Type = 'mono'; Console = $true; Pdf = $true }
            @{ Key = 'HoursSinceLastRecord'; Label = 'Hours since data'; Type = 'number'; Console = $true; Pdf = $true }
            @{ Key = 'DelayP50Minutes'; Label = 'Delay P50 (min)'; Type = 'number'; Console = $true }
            @{ Key = 'DelayP95Minutes'; Label = 'Delay P95 (min)'; Type = 'number'; Console = $true; Pdf = $true }
            @{ Key = 'DelayMaxMinutes'; Label = 'Delay max (min)'; Type = 'number' }
            @{ Key = 'BillableGB'; Label = 'Billable GB'; Type = 'number'; Console = $true; Pdf = $true }
            @{ Key = 'Connectors'; Label = 'Connectors'; Type = 'wide'; Console = $true }
            @{ Key = 'RecentRecords'; Label = 'Records (6 h)'; Type = 'number' }
            @{ Key = 'Plan'; Label = 'Plan'; Facet = $true }
            @{ Key = 'Type'; Label = 'Type'; Facet = $true }
            @{ Key = 'LastRecord'; Label = 'Last record'; Type = 'datetime' }
        ) }
    $report = @{
        Subtitle = 'Microsoft Sentinel data connectors: what arrives, how late, and what fails'
        Facts    = [ordered]@{ Workspace = "$($read.Name) ($($read.ResourceGroup))"; Period = "last $Days day(s)"; Silent = "after $SilentAfterHours hour(s)" }
        Status   = $(if (& $count $connectors 'Failing') { 'Failed' } elseif ($unhealthy -or (& $count $tables 'Silent')) { 'Warning' } else { 'Success' })
        Headline = $headline
        Tiles    = @(
            @{ Value = '{0:N0}' -f $connectors.Count; Label = 'connectors'; Tone = 'info'; Table = 'connectors' }
            @{ Value = '{0:N0}' -f $unhealthy; Label = 'unhealthy'; Tone = $(if ($unhealthy) { 'bad' } else { 'good' }) }
            @{ Value = '{0:N0}' -f $tables.Count; Label = 'tables with data'; Tone = 'neutral'; Table = 'tables' }
            @{ Value = '{0:N0}' -f (& $count $tables 'Silent'); Label = 'silent tables'; Tone = $(if (& $count $tables 'Silent') { 'warn' } else { 'good' }); Table = 'tables'; Filters = @{ Status = 'Silent' } }
            @{ Value = $(if ($null -ne $worst) { '{0:N1}' -f [double]$worst } else { '-' }); Label = 'worst delay P95 (min)'; Tone = $(if ($null -ne $worst -and $worst -gt $DelayThresholdMinutes) { 'warn' } else { 'info' }) }
        )
        Notices  = @($notices)
        Charts   = @(
            @{ Title = 'Connectors by status'; Kind = 'donut'; CenterLabel = 'connectors'; Items = @($connectors | Group-Object Status | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Tone = $connectorTones[$_.Name]; Filter = $_.Name } }); Table = 'connectors'; Column = 'Status' }
            @{ Title = 'Worst ingestion delay (P95 minutes)'; Items = @($tables | Where-Object { $null -ne $_.DelayP95Minutes } | Sort-Object DelayP95Minutes -Descending | Select-AACFirst 10 | ForEach-Object { @{ Label = $_.Table; Value = $_.DelayP95Minutes; Filter = $_.Table } }); Table = 'tables'; Column = 'Table'; Tone = 'warn'; Console = $true }
        )
        Tables   = @($connectorTable, $tableTable)
        Hint     = '-View Table for ingestion per table; -SilentAfterHours and -DelayThresholdMinutes change the thresholds; -SkipLatency for a quicker read.'
    }
    # Assigned in the branches: an empty list coming out of an if would be $null.
    $returned = $connectors
    if ($View -eq 'Table') { $returned = $tables }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $returned -Noun $(if ($View -eq 'Table') { 'table' } else { 'connector' }) -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $returned -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
