function Get-AACResourceHealth {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Checks the health of your Azure resources - Resource Health's
        availability of each (Available, Unavailable, Degraded), why and
        since when, its latest platform event, the Azure outages and
        maintenance that hit it, and with -IncludeHistory its availability
        over the last days.
    .DESCRIPTION
        Reads, in one Azure Resource Graph batch:
          Resource Health   every resource's current availability, the
                            reason (platform or user initiated, planned or
                            not), its summary and since when - and its
                            latest health event (a reboot, a live migration,
                            a host repair) in the last -Days
          Service Health    Azure outages, planned maintenance and
                            advisories active or updated in the last -Days,
                            with the regions and services they name and the
                            resources in scope they hit

        -IncludeHistory reads Resource Health's history of the resources
        that aren't available, had an event in the window, or were given
        with -ResourceId (up to 200), and works out each one's availability
        over the last -Days (time Available out of the time known) and how
        often its state changed.

        Resources come worst first: Unavailable, Degraded, Unknown,
        Available, the longest down first. -ServiceHealth returns the Service
        Health events instead of the resources. Read-only; Reader is enough.
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups (at any depth).
    .PARAMETER ResourceGroupName
        Only resources in these resource groups.
    .PARAMETER ResourceType
        Only resources of these types (for example
        'microsoft.compute/virtualmachines', or '*sql*'); wildcards work.
    .PARAMETER ResourceId
        Only these resources. Takes ResourceId or Id from the pipeline.
    .PARAMETER State
        Only resources in these states (Available, Unavailable, Degraded,
        Unknown).
    .PARAMETER Days
        The window for health events, Service Health and the history.
        Default 7; up to 30.
    .PARAMETER IncludeHistory
        Read the Resource Health history of the resources that aren't
        available, had an event, or were given, for their availability.
    .PARAMETER ServiceHealth
        Return the Service Health events (AAC.ServiceHealthEvent) instead of
        the resources.
    .PARAMETER CsvPath
        Write the resources to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report.
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the objects.
    .PARAMETER NoDisplay
        Return the objects without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Get-AACResourceHealth
        Every resource's health, worst first, and the Azure events of the last week.
    .EXAMPLE
        Get-AACResourceHealth -State Unavailable, Degraded -IncludeHistory -Days 30
        What is down now, and how available each was over the last 30 days.
    .EXAMPLE
        Get-AACResourceHealth -ResourceType 'microsoft.compute/virtualmachines' -NoDisplay | Where-Object LastEvent | Select-Object Resource, LastEvent, LastEventTime, LastEventContext
        The VMs Azure rebooted, migrated or repaired this week.
    .EXAMPLE
        Get-AACResourceHealth -ServiceHealth -NoDisplay | Where-Object Status -EQ 'Active'
        The Azure outages and maintenance active now.
    .OUTPUTS
        AAC.ResourceHealth
    .OUTPUTS
        AAC.ServiceHealthEvent
    #>
    [CmdletBinding()]
    [OutputType('AAC.ResourceHealth', 'AAC.ServiceHealthEvent')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string[]] $ManagementGroupId,

        [string[]] $ResourceGroupName,

        [SupportsWildcards()]
        [string[]] $ResourceType,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Id')]
        [string[]] $ResourceId,

        [ValidateSet('Available', 'Unavailable', 'Degraded', 'Unknown')]
        [string[]] $State,

        [ValidateRange(1, 30)]
        [int] $Days = 7,

        [switch] $IncludeHistory,

        [switch] $ServiceHealth,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Azure resource health',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    begin {
        $wanted = [System.Collections.Generic.List[string]]::new()
    }

    process {
        foreach ($id in @($ResourceId | Where-Object { $_ })) { $wanted.Add($id.TrimEnd('/').ToLowerInvariant()) }
    }

    end {
        trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

        $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
        $interactive = -not $NoDisplay -and -not $pipedOnward
        $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
        $request = @{ SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }); ResourceGroupName = @($ResourceGroupName | Where-Object { $_ }); Days = $Days; IncludeHistory = [bool]$IncludeHistory; Wanted = $wanted.ToArray() }
        $isWanted = { param([string] $Id) foreach ($w in $request.Wanted) { if ($Id -eq $w -or $Id.StartsWith("$w/")) { return $true } }; $false }

        $null = Get-AACAccessToken
        if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Resource health' -Color 'springgreen3' }
        $outcome = Invoke-AACProgress -ScriptBlock {
            Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
            $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
            Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"
            $queries = Get-AACResourceHealthQuery -ResourceGroupName $request.ResourceGroupName -Days $request.Days
            Update-AACProgress -Id 'read' -Total $queries.Count -Description 'Reading Resource Health and Service Health'
            $read = Invoke-AACGraphBatch -Query $queries -SubscriptionId $scope.GraphScope -AllowFailure @('events', 'service', 'impacted') -OnProgress {
                param($QueryName, $Done, $Total)
                Update-AACProgress -Id 'read' -Increment 1 -Description "Read the $QueryName ($Done of $Total)"
            }
            Update-AACProgress -Id 'read' -Complete -Description ('Read the health of {0:N0} resource(s) and {1:N0} Service Health event(s)' -f @($read.Rows['statuses']).Count, @($read.Rows['service']).Count)

            $history = @{}
            $historyNotices = [System.Collections.Generic.List[string]]::new()
            if ($request.IncludeHistory) {
                $recent = @{}
                foreach ($e in @($read.Rows['events'] | Where-Object { $_ })) { $recent[[string]$e['resourceId']] = $true }
                $ids = @(foreach ($row in @($read.Rows['statuses'] | Where-Object { $_ })) {
                        $id = [string]$row['resourceId']
                        if ($id -notmatch '^/subscriptions/([^/]+)' -or -not $scope.Names.Contains($Matches[1].ToLowerInvariant())) { continue }
                        if ($(if ($request.Wanted.Count) { & $isWanted $id } else { $recent.Contains($id) -or [string]$row['state'] -ne 'Available' })) { $id }
                    }) | Select-Object -Unique
                if ($ids.Count -gt 200) { $historyNotices.Add("The history of $($ids.Count) resources was asked for; the first 200 were read."); $ids = @($ids | Select-Object -First 200) }
                if ($ids.Count) {
                    $uris = [ordered]@{}
                    foreach ($id in $ids) { $uris[$id] = "$id/providers/Microsoft.ResourceHealth/availabilityStatuses?api-version=2022-10-01" }
                    Update-AACProgress -Id 'history' -Total $uris.Count -Description "Reading the Resource Health history of $($uris.Count) resource(s)"
                    $answers = Invoke-AACArmParallel -Uri @($uris.Values) -OnProgress { param($HistoryDone, $HistoryTotal) Update-AACProgress -Id 'history' -Increment 1 }
                    $failed = 0
                    foreach ($id in $uris.Keys) {
                        $answer = $answers[$uris[$id]]
                        if (-not $answer -or $answer.Error) { $failed++; continue }
                        $history[$id] = @($answer.Items | Where-Object { $_ })
                    }
                    if ($failed) { $historyNotices.Add("The Resource Health history of $failed resource(s) couldn't be read.") }
                    Update-AACProgress -Id 'history' -Complete -Description ('Read the history of {0:N0} resource(s)' -f $history.Count)
                }
            }
            $result = ConvertTo-AACResourceHealth -Read $read -SubscriptionName $scope.Names -History $history -Days $request.Days
            @{ Result = $result; Scope = $scope; Notices = @($result.Notices) + $historyNotices.ToArray() }
        }

        $resources = @($outcome.Result.Resources)
        if ($request.Wanted.Count) { $resources = @($resources | Where-Object { & $isWanted $_.ResourceId }) }
        if ($ResourceType) { $resources = @($resources | Where-Object { $t = $_.ResourceType; @($ResourceType | Where-Object { $t -like $_ }).Count }) }
        if ($State) { $resources = @($resources | Where-Object { $State -contains $_.State }) }
        $events = @($outcome.Result.Events)

        $unavailable = @($resources | Where-Object State -EQ 'Unavailable').Count
        $degraded = @($resources | Where-Object State -EQ 'Degraded').Count
        $available = @($resources | Where-Object State -EQ 'Available').Count
        $unknown = @($resources | Where-Object State -EQ 'Unknown').Count
        $issues = @($events | Where-Object { $_.Status -eq 'Active' -and $_.EventType -eq 'Service issue' }).Count
        $maintenance = @($events | Where-Object { $_.Status -eq 'Active' -and $_.EventType -eq 'Planned maintenance' }).Count
        $withEvents = @($resources | Where-Object LastEvent).Count
        $measured = @($resources | Where-Object { $null -ne $_.Availability })
        $stateTones = @{ Available = 'good'; Unavailable = 'bad'; Degraded = 'warn'; Unknown = 'neutral' }
        $eventTones = @{ 'Service issue' = 'bad'; 'Planned maintenance' = 'warn'; 'Health advisory' = 'info'; 'Security advisory' = 'violet' }
        $report = @{
            Subtitle = 'Resource Health and Azure Service Health'
            Facts    = [ordered]@{ Scope = $outcome.Scope.Label; Window = "the last $Days day(s)"; History = $(if ($IncludeHistory) { "$($measured.Count) resource(s)" } else { 'not read (-IncludeHistory)' }) }
            Status   = $(if ($unavailable -or $issues) { 'Failed' } elseif ($degraded -or $maintenance) { 'Warning' } else { 'Success' })
            Headline = $(if ($resources.Count) { "$unavailable unavailable, $degraded degraded, $available available of $($resources.Count) resource(s); $issues active Azure service issue(s)$(if ($maintenance) { ", $maintenance planned maintenance" })" } else { 'No Resource Health statuses in scope.' })
            Tiles    = @(
                @{ Value = '{0:N0}' -f $unavailable; Label = 'unavailable'; Tone = $(if ($unavailable) { 'bad' } else { 'good' }); Table = 'health'; Filters = @{ State = 'Unavailable' } }
                @{ Value = '{0:N0}' -f $degraded; Label = 'degraded'; Tone = $(if ($degraded) { 'warn' } else { 'good' }); Table = 'health'; Filters = @{ State = 'Degraded' } }
                @{ Value = '{0:N0}' -f $available; Label = 'available'; Tone = 'good'; Table = 'health'; Filters = @{ State = 'Available' } }
                @{ Value = '{0:N0}' -f $unknown; Label = 'unknown'; Tone = 'neutral'; Table = 'health'; Filters = @{ State = 'Unknown' } }
                @{ Value = '{0:N0}' -f $issues; Label = 'active service issues'; Tone = $(if ($issues) { 'bad' } else { 'good' }); Table = 'events' }
                @{ Value = '{0:N0}' -f $withEvents; Label = "with a health event ($Days d)"; Tone = $(if ($withEvents) { 'info' } else { 'good' }) }
            )
            Notices  = @($outcome.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
            Charts   = @(
                @{ Title = 'By state'; Kind = 'donut'; CenterLabel = 'resources'; Items = @(foreach ($s in 'Unavailable', 'Degraded', 'Unknown', 'Available') { $n = @($resources | Where-Object State -EQ $s).Count; if ($n) { @{ Label = $s; Value = $n; Tone = $stateTones[$s]; Filter = $s } } }); Table = 'health'; Column = 'State' }
                @{ Title = 'Not available, by type'; Items = @($resources | Where-Object { $_.State -in 'Unavailable', 'Degraded' } | Group-Object ResourceType | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'health'; Column = 'ResourceType'; Tone = 'bad'; Console = $true }
                @{ Title = 'Health events, by kind'; Items = @($resources | Where-Object LastEvent | Group-Object LastEvent | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'health'; Column = 'LastEvent'; Tone = 'info'; Console = $true }
                @{ Title = 'Least available'; Items = @($measured | Sort-Object Availability | Select-Object -First 10 | ForEach-Object { @{ Label = $_.Resource; Value = $_.Availability; Filter = $_.Resource } }); Table = 'health'; Column = 'Resource'; Tone = 'warn' }
            )
            Tables   = @(
                @{ Id = 'health'; Title = 'Resource health'; Section = 'Resources'; Rows = $resources; Noun = 'resources'; GroupBy = @('State', 'ResourceType', 'Subscription', 'ResourceGroup'); ConsoleLimit = 25
                    Empty = 'No Resource Health statuses in scope.'
                    Columns = @(
                        @{ Key = 'State'; Label = 'State'; Type = 'badge'; Tones = $stateTones; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Resource'; Label = 'Resource'; Type = 'resource'; Console = $true; Pdf = $true }
                        @{ Key = 'ResourceType'; Label = 'Type'; Type = 'type'; Facet = $true; Console = $true }
                        @{ Key = 'Summary'; Label = 'Summary'; Type = 'wide'; Console = $true; Pdf = $true }
                        @{ Key = 'Hours'; Label = 'Hours'; Type = 'number'; Console = $true; Pdf = $true }
                        @{ Key = 'Availability'; Label = 'Availability %'; Type = 'number'; Console = [bool]$IncludeHistory; Pdf = [bool]$IncludeHistory }
                        @{ Key = 'Reason'; Label = 'Reason'; Facet = $true }
                        @{ Key = 'Since'; Label = 'Since'; Type = 'datetime' }
                        @{ Key = 'LastEvent'; Label = 'Last event'; Facet = $true }
                        @{ Key = 'LastEventTime'; Label = 'Event time'; Type = 'datetime' }
                        @{ Key = 'LastEventContext'; Label = 'Initiated'; Facet = $true }
                        @{ Key = 'ServiceIssues'; Label = 'Service issues'; Type = 'mono' }
                        @{ Key = 'StateChanges'; Label = 'State changes'; Type = 'number' }
                        @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                        @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                    ) }
                @{ Id = 'events'; Title = 'Azure Service Health'; Section = 'Service Health'; Rows = $events; Noun = 'events'; ConsoleLimit = 10
                    Empty = "No Service Health events in the last $Days day(s)."; EmptyStatus = 'Success'
                    Columns = @(
                        @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = @{ Active = 'bad'; Resolved = 'good' }; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'EventType'; Label = 'Kind'; Type = 'badge'; Tones = $eventTones; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Title'; Label = 'Event'; Type = 'wide'; Console = $true; Pdf = $true }
                        @{ Key = 'Regions'; Label = 'Regions'; Console = $true }
                        @{ Key = 'ImpactedResources'; Label = 'Your resources'; Type = 'number'; Console = $true; Pdf = $true }
                        @{ Key = 'Services'; Label = 'Services'; Type = 'wide' }
                        @{ Key = 'Started'; Label = 'Started'; Type = 'datetime'; Pdf = $true }
                        @{ Key = 'Mitigated'; Label = 'Mitigated'; Type = 'datetime' }
                        @{ Key = 'LastUpdate'; Label = 'Last update'; Type = 'datetime' }
                        @{ Key = 'TrackingId'; Label = 'Tracking ID'; Type = 'mono' }
                        @{ Key = 'Subscriptions'; Label = 'Subscriptions' }
                        @{ Key = 'Summary'; Label = 'Summary'; Type = 'wide' }
                        @{ Key = 'Link'; Label = 'Details'; Type = 'link'; Text = 'Open' }
                    ) }
            )
            Hint     = '-State Unavailable, Degraded narrows the list; -IncludeHistory adds availability over -Days; -ServiceHealth returns the Azure events; -HtmlPath, -PdfPath or -CsvPath for a report.'
        }
        $objects = if ($ServiceHealth) { $events } else { $resources }
        Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $objects -Noun $(if ($ServiceHealth) { 'event' } else { 'resource' }) -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
            -ShowView:$interactive -NoPaging:$NoPaging -Object $objects -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
    }
}
