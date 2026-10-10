function Get-AACChangeHistory {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        What changed in Azure, who changed it, when and from where - with
        the properties before and after, how to undo it, and the alerts and
        health events that followed - a timeline for incident response,
        change control and audits.
    .DESCRIPTION
        Reads, for the window (-Hours, or -StartTime and -EndTime):
          Activity Log      every subscription's administrative operations
                            (writes, deletes, actions), one change per
                            correlation ID: the caller, client IP, operation
                            and how it ended
          Resource changes  Resource Graph's property-level changes (up to 14
                            days back): each property's value before and
                            after
          Incidents         alerts fired and resources Resource Health
                            reports unavailable or degraded
        Each change (AAC.ChangeRecord) has:
          a risk     High for deletes, access (role assignments, locks, key
                     vault access policies), network security, Azure Policy,
                     keys read and diagnostic settings removed; Medium for
                     other network changes, SKU or size changes and
                     restarts; Low otherwise - and at least High when an
                     incident followed it
          an origin  Manual (a person), Automation (an app, identity or
                     pipeline) or Azure - manual changes are the ones made
                     outside infrastructure as code
          a revert   how to undo it: set the properties back (their before
                     values), delete what was created, recreate what was
                     deleted - and how much effort that is
          incidents  alerts on the resource or its resource group, and
                     Resource Health events on it, within
                     -CorrelationMinutes (120) after it: possibly caused by it
        The view is a timeline, newest first; the HTML report adds charts by
        hour, caller and kind, and the incidents.

        Read-only; Reader (or Monitoring Reader) on the subscriptions. The
        Activity Log keeps 90 days; Resource Graph's changes, 14.
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups (at any depth).
    .PARAMETER ResourceGroupName
        Only changes in these resource groups (wildcards work).
    .PARAMETER ResourceType
        Only changes to these resource types, e.g. 'microsoft.network/*'.
    .PARAMETER Caller
        Only changes made by these callers - a UPN or an application ID
        (wildcards work).
    .PARAMETER Hours
        How far back to look, in hours (1 to 2160 - 90 days; 24 by default).
    .PARAMETER StartTime
        The start of the window, instead of -Hours.
    .PARAMETER EndTime
        The end of the window (now by default).
    .PARAMETER CorrelationMinutes
        How long after a change an incident counts as possibly caused by it
        (5 to 1440; 120 by default).
    .PARAMETER IncludeFailed
        Keep the operations that failed (left out by default: they changed
        nothing).
    .PARAMETER CsvPath
        Write the changes to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report.
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the changes.
    .PARAMETER NoDisplay
        Return the changes without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Get-AACChangeHistory
        Everything changed in the last 24 hours, newest first.
    .EXAMPLE
        Get-AACChangeHistory -ResourceGroupName 'rg-app-prod' -StartTime '2026-10-08 22:00' -EndTime '2026-10-09 02:00'
        What changed around an outage last night.
    .EXAMPLE
        Get-AACChangeHistory -Hours 168 -NoDisplay | Where-Object Origin -EQ 'Manual' | Export-Csv .\ManualChanges.csv -NoTypeInformation
        A week of changes made by hand - for the change advisory board.
    .OUTPUTS
        AAC.ChangeRecord
    #>
    [CmdletBinding(DefaultParameterSetName = 'Hours')]
    [OutputType('AAC.ChangeRecord')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string[]] $ManagementGroupId,

        [SupportsWildcards()]
        [string[]] $ResourceGroupName,

        [SupportsWildcards()]
        [string[]] $ResourceType,

        [SupportsWildcards()]
        [string[]] $Caller,

        [Parameter(ParameterSetName = 'Hours')]
        [ValidateRange(1, 2160)]
        [int] $Hours = 24,

        [Parameter(Mandatory, ParameterSetName = 'Window')]
        [datetime] $StartTime,

        [Parameter(ParameterSetName = 'Window')]
        [datetime] $EndTime = [datetime]::Now,

        [ValidateRange(5, 1440)]
        [int] $CorrelationMinutes = 120,

        [switch] $IncludeFailed,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Azure change history',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $to = if ($PSCmdlet.ParameterSetName -eq 'Window') { $EndTime.ToUniversalTime() } else { [datetime]::UtcNow }
    $from = if ($PSCmdlet.ParameterSetName -eq 'Window') { $StartTime.ToUniversalTime() } else { $to.AddHours(-$Hours) }
    if ($from -ge $to) { throw "-StartTime ($StartTime) must be before -EndTime ($EndTime)." }
    if ($from -lt [datetime]::UtcNow.AddDays(-90)) { Write-Warning 'The Activity Log keeps 90 days: changes before that are gone.' }
    $request = @{
        SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }); From = $from; To = $to
        ResourceGroupName = @($ResourceGroupName | Where-Object { $_ }); ResourceType = @($ResourceType | Where-Object { $_ }); Caller = @($Caller | Where-Object { $_ })
        CorrelationMinutes = $CorrelationMinutes; IncludeFailed = [bool]$IncludeFailed
    }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Change history' -Color 'deepskyblue3_1' }
    $state = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
        $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
        Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"
        $iso = { param([datetime] $When) $When.ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture) }

        # --- The Activity Log, per subscription ------------------------------------------------------------------------
        $select = 'caller,eventTimestamp,status,operationName,resourceId,resourceGroupName,correlationId,category,authorization,httpRequest,eventDataId,resourceType'
        $uris = @{}
        foreach ($id in $scope.Ids) {
            $filter = "eventTimestamp ge '$(& $iso $request.From)' and eventTimestamp le '$(& $iso $request.To)'"
            if ($request.ResourceGroupName.Count -eq 1 -and $request.ResourceGroupName[0] -notmatch '[*?]') { $filter += " and resourceGroupName eq '$($request.ResourceGroupName[0])'" }
            $uris[$id] = "/subscriptions/$id/providers/Microsoft.Insights/eventtypes/management/values?api-version=2015-04-01&`$filter=$([System.Uri]::EscapeDataString($filter))&`$select=$select"
        }
        Update-AACProgress -Id 'activity' -Total ([Math]::Max(1, $uris.Count)) -Description "Reading the Activity Log of $($uris.Count) subscription(s)"
        $answers = Invoke-AACArmParallel -Uri @($uris.Values) -OnProgress { param($LogDone, $LogTotal) Update-AACProgress -Id 'activity' -Increment 1 }
        $events = [System.Collections.Generic.List[object]]::new()
        $notices = [System.Collections.Generic.List[string]]::new()
        foreach ($id in $uris.Keys) {
            $answer = $answers[$uris[$id]]
            if (-not $answer -or $answer.Error) { $notices.Add("The Activity Log of $($scope.Names[$id.ToLowerInvariant()]) couldn't be read: $(if ($answer) { $answer.Error } else { 'no answer' })"); continue }
            foreach ($e in @($answer.Items)) { if ($e) { $events.Add($e) } }
        }
        Update-AACProgress -Id 'activity' -Complete -Description ('Read {0:N0} Activity Log event(s)' -f $events.Count)

        # --- Property changes and incidents, from Resource Graph ------------------------------------------------------------
        $changeFrom = if ($request.From -lt [datetime]::UtcNow.AddDays(-14)) { [datetime]::UtcNow.AddDays(-14) } else { $request.From }
        $between = "between (datetime($(& $iso $changeFrom)) .. datetime($(& $iso $request.To.AddMinutes($request.CorrelationMinutes))))"
        $queries = [ordered]@{
            changes = "resourcechanges | extend p = properties | extend at = todatetime(p.changeAttributes.timestamp) | where at between (datetime($(& $iso $changeFrom)) .. datetime($(& $iso $request.To))) | project id, at, changeType = tostring(p.changeType), resourceId = tolower(tostring(p.targetResourceId)), resourceType = tostring(p.targetResourceType), changedBy = tostring(p.changeAttributes.changedBy), clientType = tostring(p.changeAttributes.clientType), correlationId = tostring(p.changeAttributes.correlationId), changes = p.changes"
            alerts  = "alertsmanagementresources | where type =~ 'microsoft.alertsmanagement/alerts' | extend e = properties.essentials | extend fired = todatetime(e.startDateTime) | where fired $between | project id, fired, name, severity = tostring(e.severity), state = tostring(e.monitorCondition), target = tolower(tostring(e.targetResource)), targetGroup = tolower(tostring(e.targetResourceGroup)), signal = tostring(e.signalType), description = tostring(e.description)"
            health  = "healthresources | where type =~ 'microsoft.resourcehealth/availabilitystatuses' | where tostring(properties.availabilityState) in~ ('Unavailable', 'Degraded') | project id, resourceId = tolower(tostring(properties.targetResourceId)), state = tostring(properties.availabilityState), summary = tostring(properties.summary), since = tostring(properties.occuredTime)"
        }
        Update-AACProgress -Id 'graph' -Total $queries.Count -Description 'Reading the property changes, alerts and Resource Health'
        $read = Invoke-AACGraphBatch -Query $queries -SubscriptionId $scope.GraphScope -AllowFailure @($queries.Keys) -OnProgress { param($Name, $Done, $Total) Update-AACProgress -Id 'graph' -Increment 1 -Description "Read the $Name ($Done of $Total)" }
        foreach ($key in $read.Errors.Keys) { if ($read.Errors[$key]) { $notices.Add("The $(@{ changes = 'property changes'; alerts = 'alerts'; health = 'Resource Health statuses' }[$key]) couldn't be read: $($read.Errors[$key])") } }
        Update-AACProgress -Id 'graph' -Complete -Description ('Read {0:N0} property change(s), {1:N0} alert(s), {2:N0} unhealthy resource(s)' -f @($read.Rows['changes']).Count, @($read.Rows['alerts']).Count, @($read.Rows['health']).Count)

        Update-AACProgress -Id 'history' -Indeterminate -Description 'Building the timeline'
        $result = ConvertTo-AACChangeHistory -ActivityEvent $events.ToArray() -Change @($read.Rows['changes'] | Where-Object { $_ }) -Alert @($read.Rows['alerts'] | Where-Object { $_ }) -Health @($read.Rows['health'] | Where-Object { $_ }) `
            -SubscriptionName $scope.Names -CorrelationMinutes $request.CorrelationMinutes -ResourceGroupName $request.ResourceGroupName -ResourceType $request.ResourceType -Caller $request.Caller -IncludeFailed:$request.IncludeFailed
        Update-AACProgress -Id 'history' -Complete -Description ('{0:N0} change(s) by {1:N0} caller(s): {2:N0} high risk, {3:N0} manual, {4:N0} followed by an incident' -f $result.Stats.Changes, $result.Stats.Callers, $result.Stats.High, $result.Stats.Manual, $result.Stats.Linked)
        @{ Result = $result; Scope = $scope; Notices = $notices.ToArray() }
    }

    $result = $state.Result
    $changes = @($result.Changes)
    $s = $result.Stats
    $rank = Get-AACSeverityRank
    $kindTones = @{ Create = 'good'; Update = 'info'; Delete = 'bad'; Action = 'violet' }
    $local = { param([datetime] $When) $When.ToLocalTime() }
    $hourly = @($changes | Group-Object -Property { (& $local $_.Time).ToString('yyyy-MM-dd HH:00') } | Sort-Object Name | ForEach-Object { @{ Label = $_.Name.Substring(5); Value = $_.Count } })
    $report = @{
        Subtitle = "Change history, $((& $local $from).ToString('d MMM HH:mm')) to $((& $local $to).ToString('d MMM yyyy HH:mm'))"
        Facts    = [ordered]@{ Scope = $state.Scope.Label; Window = "$((& $local $from).ToString('d MMM HH:mm')) - $((& $local $to).ToString('d MMM yyyy HH:mm'))"; 'Incidents within' = "$CorrelationMinutes minutes of a change" }
        Status   = $(if ($s.Linked) { 'Failed' } elseif ($s.High -or $s.Deletes) { 'Warning' } else { 'Success' })
        Headline = $(if ($s.Changes) { "$($s.Changes) change(s) by $($s.Callers) caller(s): $($s.Deletes) delete(s), $($s.High) high risk, $($s.Manual) made by hand$(if ($s.Linked) { " - $($s.Linked) followed by an alert or health event" })" } else { 'No changes in this window.' })
        Tiles    = @(
            @{ Value = '{0:N0}' -f $s.Changes; Label = 'changes'; Tone = 'info'; Table = 'changes' }
            @{ Value = '{0:N0}' -f $s.High; Label = 'high risk'; Tone = $(if ($s.High) { 'bad' } else { 'good' }); Table = 'changes'; Filters = @{ Severity = 'High' } }
            @{ Value = '{0:N0}' -f $s.Deletes; Label = 'deletes'; Tone = $(if ($s.Deletes) { 'warn' } else { 'good' }); Table = 'changes'; Filters = @{ Category = 'Delete' } }
            @{ Value = '{0:N0}' -f $s.Manual; Label = 'made by hand'; Tone = $(if ($s.Manual) { 'warn' } else { 'good' }); Table = 'changes'; Filters = @{ Origin = 'Manual' } }
            @{ Value = '{0:N0}' -f $s.Linked; Label = 'followed by an incident'; Tone = $(if ($s.Linked) { 'bad' } else { 'good' }) }
            @{ Value = '{0:N0}' -f $s.Callers; Label = 'callers'; Tone = 'violet' }
        )
        Notices  = @($state.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
        Charts   = @(
            @{ Title = 'Changes by hour'; Items = $hourly; Wide = $true; Tone = 'info' }
            @{ Title = 'Changes by kind'; Kind = 'donut'; CenterLabel = 'changes'; Items = @($changes | Group-Object Category | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Tone = $kindTones[$_.Name]; Filter = $_.Name } }); Table = 'changes'; Column = 'Category' }
            @{ Title = 'Changes by caller'; Items = @($changes | Group-Object Caller | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object { @{ Label = $(if ($_.Name) { $_.Name } else { '(Azure)' }); Value = $_.Count; Filter = $_.Name } }); Table = 'changes'; Column = 'Caller'; Tone = 'violet'; Console = $true }
        )
        Tables   = @(
            @{ Id = 'changes'; Title = 'Timeline'; Section = 'Changes'; Rows = $changes; Noun = 'changes'; GroupBy = @('Category', 'Caller', 'ResourceGroup', 'Severity', 'Origin'); ConsoleLimit = 30
                Empty = 'No changes in this window.'; EmptyStatus = 'Info'
                Columns = @(
                    @{ Key = 'Time'; Label = 'When'; Type = 'datetime'; Console = $true; Pdf = $true }
                    @{ Key = 'Severity'; Label = 'Risk'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Category'; Label = 'Change'; Type = 'badge'; Tones = $kindTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Resource'; Label = 'Resource'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true; Console = $true }
                    @{ Key = 'Caller'; Label = 'Caller'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Origin'; Label = 'Origin'; Type = 'badge'; Tones = @{ Manual = 'warn'; Automation = 'good'; Azure = 'neutral' }; Facet = $true }
                    @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = @{ Succeeded = 'good'; Failed = 'bad'; Accepted = 'info'; Started = 'info' }; Facet = $true }
                    @{ Key = 'Detail'; Label = 'Before -> after'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'Impact'; Label = 'Followed by'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Revert'; Label = 'How to undo it'; Type = 'wide' }
                    @{ Key = 'Effort'; Label = 'Undo effort'; Type = 'badge'; Tones = @{ Low = 'good'; Medium = 'warn'; High = 'bad' }; Facet = $true }
                    @{ Key = 'Operation'; Label = 'Operation'; Type = 'mono' }
                    @{ Key = 'ResourceType'; Label = 'Resource type'; Type = 'mono'; Facet = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                    @{ Key = 'ClientIp'; Label = 'Client IP'; Type = 'mono' }
                    @{ Key = 'CorrelationId'; Label = 'Correlation ID'; Type = 'mono' }
                ) }
            @{ Id = 'incidents'; Title = 'Alerts and health events'; Section = 'Incidents'; Rows = $result.Incidents; Noun = 'incidents'; ConsoleLimit = 10
                Columns = @(
                    @{ Key = 'Time'; Label = 'When'; Type = 'datetime'; Console = $true }
                    @{ Key = 'Kind'; Label = 'Kind'; Facet = $true; Console = $true }
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = @{ Sev0 = 'bad'; Sev1 = 'bad'; Sev2 = 'warn'; Sev3 = 'info'; Sev4 = 'neutral' }; Facet = $true; Console = $true }
                    @{ Key = 'Name'; Label = 'Name'; Console = $true }
                    @{ Key = 'Resource'; Label = 'Resource'; Console = $true }
                    @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                    @{ Key = 'State'; Label = 'State'; Facet = $true }
                    @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide' }
                ) }
        )
        Hint     = '-Hours, or -StartTime and -EndTime; -ResourceGroupName, -ResourceType, -Caller narrow it; -NoDisplay returns the changes.'
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $changes -Noun 'change' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $changes -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
