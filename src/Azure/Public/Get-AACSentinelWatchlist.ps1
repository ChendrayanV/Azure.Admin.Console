function Get-AACSentinelWatchlist {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Lists the watchlists on a Microsoft Sentinel workspace - how many items
        each holds, which analytics rules and hunting queries use it, when it
        was last updated and by whom - with the empty, unused, stale and
        failed ones called out.
    .DESCRIPTION
        Reads the workspace - read-only, nothing is changed - from:
          Azure Resource Manager   the watchlists, the analytics rules and the
                                   saved searches (hunting queries)
          the workspace itself     KQL: the Watchlist table, for the items in
                                   each watchlist now (deleted items left out)

        Each watchlist: Name, Alias, Items, SearchKey, Rules and
        HuntingQueries (how many enabled rules and hunting queries call
        _GetWatchlist with its alias), UsedBy (their names), Findings,
        Provider, Source, SourceType, Labels, ItemExpiry, Created, CreatedBy,
        Updated, UpdatedBy, DaysSinceUpdate, Description and WatchlistId.

        Findings:
          Upload failed            the watchlist didn't finish provisioning
          No items                 nothing to match against
          Unused                   no enabled rule or hunting query calls
                                   _GetWatchlist with its alias (one reading
                                   the Watchlist table directly isn't counted)
          Not updated for N days   over -StaleAfterDays (180): a list of VIPs,
                                   service accounts or IP ranges goes out of
                                   date

        Needs Microsoft Sentinel Reader on the workspace (and Log Analytics
        Reader for the item counts).
    .PARAMETER WorkspaceId
        The workspace: its workspace ID (GUID), resource ID or name.
    .PARAMETER SubscriptionId
        Where to look for a workspace given by ID (GUID) or name. Every
        subscription the account can see by default.
    .PARAMETER ResourceGroupName
        Narrows a workspace given by name, when the name is in more than one
        resource group.
    .PARAMETER Name
        Only watchlists whose name or alias matches; wildcards work.
    .PARAMETER StaleAfterDays
        Call a watchlist stale when nothing in it changed for longer than
        this: 180 days by default.
    .PARAMETER CsvPath
        Write the watchlists to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report to this file.
    .PARAMETER PdfPath
        Write a PDF report to this file.
    .PARAMETER Title
        The HTML and PDF reports' title.
    .PARAMETER PassThru
        Show the view and also return the watchlists.
    .PARAMETER NoDisplay
        Return the watchlists without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once instead of a page at a time.
    .EXAMPLE
        Connect-AAC
        Get-AACSentinelWatchlist -WorkspaceId 'law-contoso-sentinel'
        Every watchlist, the ones with findings first.
    .EXAMPLE
        Get-AACSentinelWatchlist -WorkspaceId 'law-contoso-sentinel' -NoDisplay | Where-Object Findings -Match 'Unused'
        The watchlists nothing uses.
    .EXAMPLE
        Get-AACSentinelWatchlist -WorkspaceId 'law-contoso-sentinel' -StaleAfterDays 90 -HtmlPath .\out\Watchlists.html
        The watchlists, calling stale any not updated for 90 days, as an HTML report.
    .OUTPUTS
        AAC.SentinelWatchlist (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.SentinelWatchlist')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [Alias('Workspace', 'WorkspaceName', 'ResourceId')]
        [ValidateNotNullOrEmpty()]
        [string] $WorkspaceId,

        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string] $ResourceGroupName,

        [SupportsWildcards()]
        [string[]] $Name,

        [ValidateRange(1, 3650)]
        [int] $StaleAfterDays = 180,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Microsoft Sentinel watchlists',

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
        watchlists    = "$insights/watchlists?api-version=2025-09-01"
        alertRules    = "$insights/alertRules?api-version=2025-09-01"
        savedSearches = 'savedSearches?api-version=2025-07-01'
    }
    # Sentinel writes every item again every 12 days to keep it within
    # retention, so 30 days holds each item's latest state.
    $kql = [ordered]@{
        items = @'
Watchlist
| where TimeGenerated > ago(30d)
| summarize arg_max(TimeGenerated, _DTItemStatus, LastUpdatedTimeUTC) by WatchlistAlias, _DTItemId
| where _DTItemStatus != 'Delete'
| summarize Items = count(), LastItemUpdate = max(LastUpdatedTimeUTC) by WatchlistAlias
'@
    }
    # Read here, not inside the progress block (it runs in Invoke-AACProgress's scope).
    $request = @{ Target = $WorkspaceId.Trim(); SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ResourceGroupName = $ResourceGroupName; Arm = $arm; Kql = $kql; StaleAfterDays = $StaleAfterDays }

    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Microsoft Sentinel watchlists' -Color 'deepskyblue3_1' }
    $state = Invoke-AACProgress -ScriptBlock {
        $null = Get-AACAccessToken
        Update-AACProgress -Id 'read' -Indeterminate -Description "Reading the watchlists of $($request.Target)"
        $read = Read-AACSentinelWorkspace -Target $request.Target -SubscriptionId $request.SubscriptionId -ResourceGroupName $request.ResourceGroupName -Arm $request.Arm -Kql $request.Kql -Timespan 'P30D'
        $listed = { param([string] $Key) if ($read.Arm[$Key].Error) { @() } else { @($read.Arm[$Key].Items | Where-Object { $null -ne $_ }) } }
        $rules = @(& $listed 'alertRules' | Where-Object { $_['properties'] -is [System.Collections.IDictionary] -and $_['properties']['enabled'] } | ForEach-Object { @{ Name = [string]$_['properties']['displayName']; Query = [string]$_['properties']['query'] } })
        $hunting = @(& $listed 'savedSearches' | Where-Object { $_['properties'] -is [System.Collections.IDictionary] -and [string]$_['properties']['category'] -eq 'Hunting Queries' } | ForEach-Object { @{ Name = [string]$_['properties']['displayName']; Query = [string]$_['properties']['query'] } })
        # No Watchlist table means no watchlist has items yet: zero, not unknown.
        $itemError = [string]$read.Kql.Errors['items']
        $itemRows = $null
        if (-not $itemError -or $itemError -match '(?i)failed to resolve.*Watchlist') { $itemRows = @($read.Kql.Rows['items'] | Where-Object { $null -ne $_ }) }
        $watchlists = @(ConvertTo-AACSentinelWatchlist -Watchlist @(& $listed 'watchlists') -ItemRow $itemRows -RuleQuery $rules -HuntingQuery $hunting -StaleAfterDays $request.StaleAfterDays)
        Update-AACProgress -Id 'read' -Complete -Description "Workspace $($read.Name): $($watchlists.Count) watchlist(s)"
        @{ Read = $read; Watchlists = $watchlists; ItemError = $(if ($null -eq $itemRows) { $itemError } else { '' }) }
    }
    $read = $state.Read
    # Without the list there's nothing to show, and an empty one would mislead.
    if ($read.Arm['watchlists'].Error) {
        $problem = [System.InvalidOperationException]::new("Azure Admin Console couldn't read the watchlists of $($read.Name): $($read.Arm['watchlists'].Error)")
        $problem.Data['AACHint'] = 'Your account needs Microsoft Sentinel Reader on the workspace.'
        throw $problem
    }
    $notices = [System.Collections.Generic.List[hashtable]]::new()
    if ($state.ItemError) { $notices.Add(@{ Status = 'Warning'; Text = "The items couldn't be counted, so Items is blank: $($state.ItemError)" }) }
    foreach ($pair in @(@('alertRules', 'analytics rules'), @('savedSearches', 'hunting queries'))) {
        if ($read.Arm[$pair[0]].Error) { $notices.Add(@{ Status = 'Warning'; Text = "The $($pair[1]) couldn't be read, so a watchlist they use may show as unused: $($read.Arm[$pair[0]].Error)" }) }
    }

    $watchlists = @($state.Watchlists)
    if ($Name) { $watchlists = @($watchlists | Where-Object { $w = $_; @($Name | Where-Object { $w.Name -like $_ -or $w.Alias -like $_ }).Count }) }

    # --- The report -------------------------------------------------------------------------------------------
    $withFindings = @($watchlists | Where-Object Findings)
    $count = { param([string] $Pattern) @($watchlists | Where-Object { $_.Findings -match $Pattern }).Count }
    $unused = & $count 'Unused'
    $empty = & $count 'No items'
    $stale = & $count 'Not updated'
    $failed = & $count 'Upload failed'
    $totalItems = [int](@($watchlists | ForEach-Object { $_.Items } | Where-Object { $null -ne $_ } | Measure-Object -Sum).Sum)
    $headline = if (-not $watchlists.Count) { "No watchlists on $($read.Name)." }
    elseif ($withFindings.Count) { "$($watchlists.Count) watchlist(s) holding $('{0:N0}' -f $totalItems) item(s); $($withFindings.Count) need a look: $unused unused, $empty empty, $stale stale$(if ($failed) { ", $failed failed" })" }
    else { "$($watchlists.Count) watchlist(s) holding $('{0:N0}' -f $totalItems) item(s), all in use and up to date." }
    $report = @{
        Subtitle = 'Microsoft Sentinel watchlists: what they hold, what uses them, and how fresh they are'
        Facts    = [ordered]@{ Workspace = "$($read.Name) ($($read.ResourceGroup))"; 'Stale after' = "$StaleAfterDays day(s)" }
        Status   = $(if ($failed) { 'Failed' } elseif ($withFindings.Count) { 'Warning' } else { 'Success' })
        Headline = $headline
        Tiles    = @(
            @{ Value = '{0:N0}' -f $watchlists.Count; Label = 'watchlists'; Tone = 'info'; Table = 'watchlists' }
            @{ Value = '{0:N0}' -f $totalItems; Label = 'items'; Tone = 'neutral' }
            @{ Value = '{0:N0}' -f $unused; Label = 'unused'; Tone = $(if ($unused) { 'warn' } else { 'good' }) }
            @{ Value = '{0:N0}' -f $empty; Label = 'empty'; Tone = $(if ($empty) { 'warn' } else { 'good' }) }
            @{ Value = '{0:N0}' -f $stale; Label = 'stale'; Tone = $(if ($stale) { 'warn' } else { 'good' }) }
            @{ Value = '{0:N0}' -f $failed; Label = 'upload failed'; Tone = $(if ($failed) { 'bad' } else { 'good' }) }
        )
        Notices  = @($notices)
        Charts   = @(
            @{ Title = 'Largest watchlists (items)'; Items = @($watchlists | Where-Object Items -GT 0 | Sort-Object Items -Descending | Select-AACFirst 10 | ForEach-Object { @{ Label = $_.Name; Value = $_.Items; Filter = $_.Name } }); Table = 'watchlists'; Column = 'Name'; Tone = 'info'; Console = $true }
            @{ Title = 'Most used (rules and hunting queries)'; Items = @($watchlists | Where-Object { $_.Rules + $_.HuntingQueries } | Sort-Object { $_.Rules + $_.HuntingQueries } -Descending | Select-AACFirst 10 | ForEach-Object { @{ Label = $_.Name; Value = $_.Rules + $_.HuntingQueries; Filter = $_.Name } }); Table = 'watchlists'; Column = 'Name'; Tone = 'violet' }
        )
        Tables   = @(
            @{ Id = 'watchlists'; Title = 'Watchlists'; Section = 'Watchlists'; Rows = $watchlists; Noun = 'watchlists'; File = 'sentinel-watchlists'; ConsoleLimit = 30
                Empty = 'This workspace has no watchlists.'; EmptyStatus = 'Info'; Hover = @('Description', 'UsedBy'); HoverTitle = 'Name'
                Columns = @(
                    @{ Key = 'Name'; Label = 'Watchlist'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'Alias'; Label = 'Alias'; Type = 'mono'; Console = $true; Pdf = $true }
                    @{ Key = 'Items'; Label = 'Items'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'Rules'; Label = 'Rules'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'HuntingQueries'; Label = 'Hunting'; Type = 'number'; Console = $true }
                    @{ Key = 'DaysSinceUpdate'; Label = 'Days since update'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'Findings'; Label = 'Findings'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'SearchKey'; Label = 'Search key'; Type = 'mono' }
                    @{ Key = 'Source'; Label = 'Source' }
                    @{ Key = 'SourceType'; Label = 'Source type'; Facet = $true }
                    @{ Key = 'Provider'; Label = 'Provider'; Facet = $true }
                    @{ Key = 'Labels'; Label = 'Labels'; Facet = $true }
                    @{ Key = 'ItemExpiry'; Label = 'Item expiry'; Type = 'mono'; Hidden = $true }
                    @{ Key = 'Updated'; Label = 'Updated'; Type = 'datetime' }
                    @{ Key = 'UpdatedBy'; Label = 'Updated by' }
                    @{ Key = 'Created'; Label = 'Created'; Type = 'datetime'; Hidden = $true }
                    @{ Key = 'CreatedBy'; Label = 'Created by'; Hidden = $true }
                    @{ Key = 'UsedBy'; Label = 'Used by'; Type = 'wide'; Hidden = $true }
                    @{ Key = 'Description'; Label = 'Description'; Type = 'wide'; Hidden = $true }
                ) }
        )
        Hint     = '-Name narrows the list; -StaleAfterDays changes when a watchlist counts as stale; -NoDisplay returns the watchlists with who uses each.'
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $watchlists -Noun 'watchlist' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $watchlists -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
