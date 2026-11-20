function Get-AACSentinelThreatIntelligence {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Summarises the threat intelligence in a Microsoft Sentinel workspace -
        indicators by source and type: how many, active, expired or about to
        expire, confidence, when each feed last updated - and whether any
        analytics rule matches on them. -Indicator lists the indicators
        themselves.
    .DESCRIPTION
        Reads the workspace - read-only, nothing is changed - from:
          the workspace itself     KQL: ThreatIntelIndicators (STIX, current)
                                   and ThreatIntelligenceIndicator (legacy),
                                   each indicator's latest record in -Days
          Azure Resource Manager   the data connectors and analytics rules

        By default, a row per source and indicator type (AAC.SentinelThreat
        IntelSource): Source, IndicatorType, Indicators, Active, Expired,
        ExpiringSoon (within 7 days), AverageConfidence, LowConfidence (below
        50), LastUpdated, DaysSinceUpdate, Findings and Table. Findings: no
        update for longer than -StaleAfterDays (a feed that stopped), none
        active, mostly low confidence.

        With -Indicator, the indicators (AAC.SentinelThreatIndicator), newest
        first, at most -Limit from each table: Value, IndicatorType, Source,
        Confidence, Active, ValidFrom, ValidUntil, LastUpdated, Name, Tags,
        Description, Table and Id. Expired ones are left out unless
        -IncludeExpired.

        The view also says when no indicators arrive, when no enabled rule
        reads the threat intelligence tables, when rules still read the
        legacy table that has no data, and when a threat intelligence
        connector is disconnected.

        Needs Log Analytics Reader and Microsoft Sentinel Reader on the
        workspace.
    .PARAMETER WorkspaceId
        The workspace: its workspace ID (GUID), resource ID or name.
    .PARAMETER SubscriptionId
        Where to look for a workspace given by ID (GUID) or name. Every
        subscription the account can see by default.
    .PARAMETER ResourceGroupName
        Narrows a workspace given by name, when the name is in more than one
        resource group.
    .PARAMETER Days
        How far back to look for indicator records: 1 to 365 days, 30 by
        default. Feeds refresh their indicators, so 30 days holds the current
        ones.
    .PARAMETER Indicator
        List the indicators rather than the summary.
    .PARAMETER Source
        Only these sources; wildcards work.
    .PARAMETER IndicatorType
        Only these indicator types (ipv4-addr, ipv6-addr, domain-name, url,
        file, email-addr...); wildcards work.
    .PARAMETER Value
        With -Indicator: only indicators whose value matches; wildcards work.
    .PARAMETER IncludeExpired
        With -Indicator: also list expired and inactive indicators.
    .PARAMETER Limit
        With -Indicator: read at most this many from each table, newest first:
        5,000 by default.
    .PARAMETER StaleAfterDays
        Call a source stale when it hasn't updated an indicator for longer
        than this: 7 days by default.
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
        Get-AACSentinelThreatIntelligence -WorkspaceId 'law-contoso-sentinel'
        Indicators by source and type, stale feeds first.
    .EXAMPLE
        Get-AACSentinelThreatIntelligence -WorkspaceId 'law-contoso-sentinel' -Indicator -IndicatorType ipv4-addr -Value '203.0.113.*'
        The active IP indicators in a range.
    .EXAMPLE
        Get-AACSentinelThreatIntelligence -WorkspaceId 'law-contoso-sentinel' -Indicator -Source 'Microsoft Defender*' -CsvPath .\out\Indicators.csv
        One feed's active indicators, to CSV.
    .OUTPUTS
        AAC.SentinelThreatIntelSource, or AAC.SentinelThreatIndicator with -Indicator (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.SentinelThreatIntelSource', 'AAC.SentinelThreatIndicator')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [Alias('Workspace', 'WorkspaceName', 'ResourceId')]
        [ValidateNotNullOrEmpty()]
        [string] $WorkspaceId,

        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string] $ResourceGroupName,

        [ValidateRange(1, 365)]
        [int] $Days = 30,

        [switch] $Indicator,

        [SupportsWildcards()]
        [string[]] $Source,

        [SupportsWildcards()]
        [string[]] $IndicatorType,

        [SupportsWildcards()]
        [string[]] $Value,

        [switch] $IncludeExpired,

        [ValidateRange(1, 500000)]
        [int] $Limit = 5000,

        [ValidateRange(1, 365)]
        [int] $StaleAfterDays = 7,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Microsoft Sentinel threat intelligence',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    # A failure anywhere below ends as a Spectre.Console error panel and this
    # command's own terminating error, not a line inside the module. A stopped
    # pipeline (Select-Object -First, Ctrl+C) is no failure: just return - a
    # rethrow would stop the caller's whole script, not only this command.
    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    if (($Value -or $IncludeExpired) -and -not $Indicator) {
        throw [System.ArgumentException]::new('Azure Admin Console uses -Value and -IncludeExpired only with -Indicator. Add -Indicator to list the indicators.')
    }
    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Target) if ($Target) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Target) } }
    $insights = 'providers/Microsoft.SecurityInsights'
    $arm = [ordered]@{
        dataConnectors = "$insights/dataConnectors?api-version=2025-09-01"
        alertRules     = "$insights/alertRules?api-version=2025-09-01"
    }
    # Read here, not inside the progress block (it runs in Invoke-AACProgress's scope).
    $request = @{ Target = $WorkspaceId.Trim(); SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ResourceGroupName = $ResourceGroupName; Arm = $arm; Kql = (Get-AACSentinelThreatIntelQuery -Days $Days -Indicator:$Indicator -Limit $Limit); Days = $Days; StaleAfterDays = $StaleAfterDays }

    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Microsoft Sentinel threat intelligence' -Color 'red3' }
    $outcome = Invoke-AACProgress -ScriptBlock {
        $null = Get-AACAccessToken
        Update-AACProgress -Id 'read' -Indeterminate -Description "Reading the threat intelligence of $($request.Target)"
        $read = Read-AACSentinelWorkspace -Target $request.Target -SubscriptionId $request.SubscriptionId -ResourceGroupName $request.ResourceGroupName -Arm $request.Arm -Kql $request.Kql -Timespan "P$($request.Days)D"
        $sentinel = ConvertTo-AACSentinelAssessment -Workspace $read.Workspace -Arm $read.Arm
        $intel = ConvertTo-AACSentinelThreatIntel -Kql $read.Kql -Connector @($sentinel.DataConnectors) -Rule @($sentinel.AnalyticsRules) -StaleAfterDays $request.StaleAfterDays
        Update-AACProgress -Id 'read' -Complete -Description "Workspace $($read.Name): $(@($intel.Sources).Count) source and type row(s)"
        @{ Read = $read; Intel = $intel; Sentinel = $sentinel }
    }
    $read = $outcome.Read
    $intel = $outcome.Intel
    # Both tables failing for a reason other than not existing: nothing to show.
    if ($intel.Errors.Count -ge 2) {
        $problem = [System.InvalidOperationException]::new("Azure Admin Console couldn't query the threat intelligence of $($read.Name): $(@($intel.Errors.Values) -join '; ')")
        $problem.Data['AACHint'] = 'Your account needs Log Analytics Reader (or Microsoft Sentinel Reader) on the workspace.'
        throw $problem
    }
    $notices = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($n in @($intel.Notices)) { $notices.Add($n) }
    foreach ($k in $intel.Errors.Keys) { $notices.Add(@{ Status = 'Warning'; Text = "$k couldn't be queried: $($intel.Errors[$k])" }) }
    foreach ($k in $outcome.Sentinel.Errors.Keys) { $notices.Add(@{ Status = 'Warning'; Text = "$k couldn't be read: $($outcome.Sentinel.Errors[$k])" }) }

    $matchesAny = { param([string[]] $Text, [string[]] $Pattern) foreach ($t in $Text) { foreach ($p in $Pattern) { if ($t -and $t -like $p) { return $true } } }; $false }
    $sources = @($intel.Sources)
    $indicators = @($intel.Indicators)
    if ($Source) { $sources = @($sources | Where-Object { & $matchesAny @($_.Source) $Source }); $indicators = @($indicators | Where-Object { & $matchesAny @($_.Source) $Source }) }
    if ($IndicatorType) { $sources = @($sources | Where-Object { & $matchesAny @($_.IndicatorType) $IndicatorType }); $indicators = @($indicators | Where-Object { & $matchesAny @($_.IndicatorType) $IndicatorType }) }
    if ($Value) { $indicators = @($indicators | Where-Object { & $matchesAny @($_.Value) $Value }) }
    if ($Indicator -and -not $IncludeExpired) { $indicators = @($indicators | Where-Object Active) }
    if ($Indicator -and @($read.Kql.Rows['stixList']).Count + @($read.Kql.Rows['legacyList']).Count -ge $Limit) {
        $notices.Add(@{ Status = 'Warning'; Text = "Only the newest $Limit indicators of a table were read. Narrow with -Days, or raise -Limit." })
    }

    # --- The report -------------------------------------------------------------------------------------------
    $sum = { param([string] $Property) [int](@($sources | ForEach-Object { $_.$Property } | Measure-Object -Sum).Sum) }
    $total = & $sum 'Indicators'
    $active = & $sum 'Active'
    $expiring = & $sum 'ExpiringSoon'
    $stale = @($sources | Where-Object { $_.Findings -match 'No update' } | ForEach-Object Source | Select-Object -Unique).Count
    $feeds = @($sources | ForEach-Object Source | Select-Object -Unique).Count
    $headline = if (-not $total) { "No threat indicators arrived in the last $Days day(s) on $($read.Name)." }
    else { "$('{0:N0}' -f $total) indicator(s) from $feeds source(s): $('{0:N0}' -f $active) active, $('{0:N0}' -f $expiring) expiring within 7 days$(if ($stale) { "; $stale source(s) stopped updating" })" }
    $sourceColumns = @(
        @{ Key = 'Source'; Label = 'Source'; Type = 'wide'; Facet = $true; Console = $true; Pdf = $true }
        @{ Key = 'IndicatorType'; Label = 'Type'; Facet = $true; Console = $true; Pdf = $true }
        @{ Key = 'Indicators'; Label = 'Indicators'; Type = 'number'; Console = $true; Pdf = $true }
        @{ Key = 'Active'; Label = 'Active'; Type = 'number'; Console = $true; Pdf = $true }
        @{ Key = 'ExpiringSoon'; Label = 'Expiring'; Type = 'number'; Console = $true }
        @{ Key = 'AverageConfidence'; Label = 'Avg confidence'; Type = 'number'; Console = $true }
        @{ Key = 'DaysSinceUpdate'; Label = 'Days since update'; Type = 'number'; Console = $true; Pdf = $true }
        @{ Key = 'Findings'; Label = 'Findings'; Type = 'wide'; Console = $true; Pdf = $true }
        @{ Key = 'Expired'; Label = 'Expired'; Type = 'number' }
        @{ Key = 'LowConfidence'; Label = 'Low confidence'; Type = 'number' }
        @{ Key = 'LastUpdated'; Label = 'Last updated'; Type = 'datetime' }
        @{ Key = 'Table'; Label = 'Table'; Facet = $true }
    )
    $indicatorColumns = @(
        @{ Key = 'Value'; Label = 'Indicator'; Type = 'mono'; Console = $true; Pdf = $true }
        @{ Key = 'IndicatorType'; Label = 'Type'; Facet = $true; Console = $true; Pdf = $true }
        @{ Key = 'Source'; Label = 'Source'; Facet = $true; Console = $true; Pdf = $true }
        @{ Key = 'Confidence'; Label = 'Confidence'; Type = 'number'; Console = $true; Pdf = $true }
        @{ Key = 'ValidUntil'; Label = 'Valid until'; Type = 'datetime'; Console = $true; Pdf = $true }
        @{ Key = 'Active'; Label = 'Active'; Facet = $true }
        @{ Key = 'Name'; Label = 'Name'; Type = 'wide' }
        @{ Key = 'Tags'; Label = 'Tags' }
        @{ Key = 'LastUpdated'; Label = 'Last updated'; Type = 'datetime' }
        @{ Key = 'Description'; Label = 'Description'; Type = 'wide'; Hidden = $true }
        @{ Key = 'Table'; Label = 'Table'; Facet = $true; Hidden = $true }
    )
    $tables = @(
        @{ Id = 'sources'; Title = 'Indicators by source and type'; Section = 'Sources'; Rows = $sources; Noun = 'rows'; File = 'sentinel-ti-sources'; ConsoleLimit = 30; NoConsole = [bool]$Indicator
            Empty = "No threat indicators in the last $Days day(s)."; EmptyStatus = 'Warning'; Columns = $sourceColumns }
    )
    if ($Indicator) {
        $tables += @{ Id = 'indicators'; Title = 'Indicators'; Section = 'Indicators'; Rows = $indicators; Noun = 'indicators'; File = 'sentinel-ti-indicators'; GroupBy = @('IndicatorType', 'Source'); ConsoleLimit = 40
            Empty = 'No indicators match.'; EmptyStatus = 'Info'; Hover = @('Description', 'Tags'); HoverTitle = 'Value'; Columns = $indicatorColumns }
    }
    $report = @{
        Subtitle = 'Microsoft Sentinel threat intelligence: what arrives, from where, how fresh, and whether rules use it'
        Facts    = [ordered]@{ Workspace = "$($read.Name) ($($read.ResourceGroup))"; Window = "last $Days day(s)" }
        Status   = $(if (-not $total -or @($notices | Where-Object Status -EQ 'Warning').Count) { 'Warning' } else { 'Success' })
        Headline = $headline
        Tiles    = @(
            @{ Value = '{0:N0}' -f $total; Label = 'indicators'; Tone = 'info'; Table = 'sources' }
            @{ Value = '{0:N0}' -f $active; Label = 'active'; Tone = $(if ($active) { 'good' } else { 'warn' }) }
            @{ Value = '{0:N0}' -f $expiring; Label = 'expiring in 7 days'; Tone = 'neutral' }
            @{ Value = '{0:N0}' -f $feeds; Label = 'sources'; Tone = 'violet' }
            @{ Value = '{0:N0}' -f $stale; Label = 'stopped updating'; Tone = $(if ($stale) { 'warn' } else { 'good' }) }
        )
        Notices  = @($notices)
        Charts   = @(
            @{ Title = 'Active indicators by type'; Kind = 'donut'; CenterLabel = 'active'; Items = @($sources | Group-Object IndicatorType | ForEach-Object { @{ Label = $_.Name; Value = [int](@($_.Group | ForEach-Object { $_.Active } | Measure-Object -Sum).Sum); Filter = $_.Name } } | Where-Object { $_.Value }); Table = 'sources'; Column = 'IndicatorType' }
            @{ Title = 'Indicators by source'; Items = @($sources | Group-Object Source | ForEach-Object { @{ Label = $_.Name; Value = [int](@($_.Group | ForEach-Object { $_.Indicators } | Measure-Object -Sum).Sum); Filter = $_.Name } } | Sort-Object { $_.Value } -Descending | Select-AACFirst 10); Table = 'sources'; Column = 'Source'; Tone = 'violet'; Console = $true }
        )
        Tables   = $tables
        Hint     = '-Indicator lists the indicators (-IndicatorType, -Source, -Value narrow them); -StaleAfterDays changes when a source counts as stopped.'
    }
    # Assigned in the branches: an empty list coming out of an if would be $null.
    $returned = $sources
    if ($Indicator) { $returned = $indicators }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $returned -Noun $(if ($Indicator) { 'indicator' } else { 'source' }) -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $returned -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
