function Invoke-AACActivityLogAssessment {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Assesses the Activity Log of every resource over 90, 180 or 365 days:
        who changed what and when, when each resource was last used, which
        are idle or were deleted, changes made by hand, access and secrets
        touched by people - with subscription, resource group, resource and
        tags on every row.
    .DESCRIPTION
        Read-only. Reads each subscription's Activity Log the fastest way it
        allows (Read-AACActivityLog):
          Log Analytics   when the subscription's diagnostic setting sends the
                          Activity Log to a workspace - found automatically,
                          or given with -WorkspaceId: a few queries per
                          workspace, summarised in the workspace, five at a
                          time. Seconds for 90, 180 or 365 days, and the only
                          way past 90.
          Activity Log    otherwise: the REST API - Azure keeps 90 days - cut
                          into about 1,500 slices read side by side.
        The Coverage view says which each subscription used, and from when its
        data goes back (the workspace's retention, or 90 days).

        Then every resource (Resource Manager, with created and last-changed
        times), joined to its activity - an event on a child counts for the
        top-level resource:
          Resources  subscription, resource group, type, name, tags; state
                     (Active, New, Idle, Quiet, Deleted, Gone); last used -
                     the latest of its last Activity Log event, last change
                     and creation - and idle days; operations, writes,
                     deletes, actions, failures, changes made by people, the
                     callers, the last operation and by whom, who wrote to it
                     first, who deleted it
          Activity   one row per resource, caller, operation and status - how
                     many times, first and last, caller kind (user, guest,
                     service principal, managed identity, Azure), caller IP
          Callers    each caller: operations, writes, deletes, failures,
                     resources touched, last seen, top operations
          Findings   guests changing resources and people changing access
                     (High); keys and secrets read by people, failure
                     hotspots, Activity Log not exported or kept less than the
                     window (Medium); changed by hand, idle, missing
                     -RequiredTag (Low); deleted in the window (Info)

        Last used is control-plane: data-plane use (reads, requests,
        sign-ins) never reaches the Activity Log - check an idle resource's
        metrics before removing it.

        Needs Reader (or Monitoring Reader) on the subscriptions; Log Analytics
        Reader on the workspaces for the fast path.
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups (at any depth).
    .PARAMETER ResourceGroupName
        Only these resource groups.
    .PARAMETER Days
        How far back to look (90 by default; 180 or 365 need the Activity Log
        sent to a Log Analytics workspace).
    .PARAMETER Source
        Auto (the default: the workspace where there is one, else the REST
        API), Workspace or ActivityLog.
    .PARAMETER WorkspaceId
        The workspace ID (customer ID) of the Log Analytics workspace holding
        the Activity Log, instead of finding it from the diagnostic settings.
    .PARAMETER Category
        Activity Log categories: Administrative (the default - changes by
        users, applications and identities), Policy, Security, ServiceHealth,
        ResourceHealth, Alert, Recommendation, Autoscale, or All.
    .PARAMETER TagName
        Tags to show as columns of their own.
    .PARAMETER RequiredTag
        Tags every resource should have: a resource missing one is a finding.
    .PARAMETER IdleDays
        Days with no change before a resource counts as idle (90 by default).
    .PARAMETER ResolveIdentity
        Look up service principals' names in Microsoft Graph.
    .PARAMETER ThrottleLimit
        Requests in flight at once for the REST API (1 to 64; 32 by default).
    .PARAMETER SliceHours
        Hours each Activity Log REST request covers (1 to 24). Automatic by
        default: about 1,500 slices in all.
    .PARAMETER View
        Resource, Activity, Caller, Finding or Coverage: what is returned and
        written to -CsvPath.
    .PARAMETER CsvPath
        Write the -View rows to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report.
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the rows.
    .PARAMETER NoDisplay
        Return the rows without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Connect-AAC
        Invoke-AACActivityLogAssessment -SubscriptionId $sub -HtmlPath .\activity.html
        The last 90 days: every resource, its activity and when it was last used, as a tabbed report.
    .EXAMPLE
        Invoke-AACActivityLogAssessment -ManagementGroupId 'mg-landingzones' -Days 365 -TagName CostCenter, Owner -RequiredTag CostCenter -HtmlPath .\activity-year.html -PdfPath .\activity-year.pdf
        A year, from the Log Analytics workspaces the subscriptions send their Activity Log to.
    .EXAMPLE
        Invoke-AACActivityLogAssessment -SubscriptionId $sub -Days 180 -NoDisplay | Where-Object State -EQ 'Idle' | Sort-Object IdleDays -Descending
        Resources nobody changed for 90 days or more, longest idle first.
    .EXAMPLE
        Invoke-AACActivityLogAssessment -SubscriptionId $sub -View Coverage -NoDisplay
        Where each subscription's Activity Log was read from, and how far back it goes.
    .OUTPUTS
        AAC.ActivityLogResource, AAC.ActivityLogActivity, AAC.ActivityLogCaller, AAC.ActivityLogFinding or AAC.ActivityLogCoverage, by -View (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.ActivityLogResource', 'AAC.ActivityLogActivity', 'AAC.ActivityLogCaller', 'AAC.ActivityLogFinding', 'AAC.ActivityLogCoverage')]
    param(
        [ValidatePattern('^[0-9a-fA-F-]{36}$')]
        [string[]] $SubscriptionId,

        [ValidateNotNullOrEmpty()]
        [string[]] $ManagementGroupId,

        [ValidateNotNullOrEmpty()]
        [string[]] $ResourceGroupName,

        [ValidateRange(1, 3650)]
        [int] $Days = 90,

        [ValidateSet('Auto', 'Workspace', 'ActivityLog')]
        [string] $Source = 'Auto',

        [ValidatePattern('^[0-9a-fA-F-]{36}$')]
        [string] $WorkspaceId,

        [ValidateSet('Administrative', 'Policy', 'Security', 'ServiceHealth', 'ResourceHealth', 'Alert', 'Recommendation', 'Autoscale', 'All')]
        [string[]] $Category = @('Administrative'),

        [ValidateNotNullOrEmpty()]
        [string[]] $TagName,

        [ValidateNotNullOrEmpty()]
        [string[]] $RequiredTag,

        [ValidateRange(1, 3650)]
        [int] $IdleDays = 90,

        [switch] $ResolveIdentity,

        [ValidateRange(1, 64)]
        [int] $ThrottleLimit = 32,

        [ValidateRange(1, 24)]
        [int] $SliceHours,

        [ValidateSet('Resource', 'Activity', 'Caller', 'Finding', 'Coverage')]
        [string] $View = 'Resource',

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Activity Log assessment',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $end = [datetime]::UtcNow
    $request = @{
        SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }); ResourceGroupName = @($ResourceGroupName | Where-Object { $_ })
        Start = $end.AddDays(-$Days); End = $end; Source = $Source; WorkspaceId = $WorkspaceId; Category = @($Category); TagName = @($TagName | Where-Object { $_ }); RequiredTag = @($RequiredTag | Where-Object { $_ })
        IdleDays = $IdleDays; ResolveIdentity = [bool]$ResolveIdentity; ThrottleLimit = $ThrottleLimit; SliceHours = $SliceHours
    }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Activity Log assessment' -Color 'deepskyblue3_1' }
    $state = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
        $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
        Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"

        $log = Read-AACActivityLog -SubscriptionId $scope.Ids -SubscriptionName $scope.Names -Start $request.Start -End $request.End -Category $request.Category -ResourceGroupName $request.ResourceGroupName `
            -Source $request.Source -WorkspaceId $request.WorkspaceId -ThrottleLimit $request.ThrottleLimit -SliceHours $request.SliceHours

        # --- The resources, with created and last-changed times -------------------------------------------------------------
        $uris = @{}
        foreach ($id in $scope.Ids) { $uris["/subscriptions/$id/resources?`$expand=createdTime,changedTime&api-version=2021-04-01"] = $id }
        Update-AACProgress -Id 'resources' -Total ([Math]::Max(1, $uris.Count)) -Description "Reading the resources of $($uris.Count) subscription(s)"
        $answers = Invoke-AACArmParallel -Uri @($uris.Keys) -ThrottleLimit $request.ThrottleLimit -OnProgress { param($ResourceDone, $ResourceTotal) Update-AACProgress -Id 'resources' -Increment 1 }
        $notices = [System.Collections.Generic.List[string]]::new()
        foreach ($n in $log.Notices) { $notices.Add($n) }
        $resources = [System.Collections.Generic.List[object]]::new()
        foreach ($uri in $uris.Keys) {
            $answer = $answers[$uri]
            if (-not $answer -or $answer.Error) { $notices.Add("The resources of $($scope.Names[$uris[$uri].ToLowerInvariant()]) couldn't be read: $(if ($answer) { $answer.Error } else { 'no answer' })"); continue }
            foreach ($r in @($answer.Items)) {
                if ($r -isnot [System.Collections.IDictionary]) { continue }
                if ($request.ResourceGroupName.Count -and ([string]$r['id'] -split '/')[4] -notin $request.ResourceGroupName) { continue }
                $r['SubscriptionId'] = $uris[$uri]
                $resources.Add($r)
            }
        }
        Update-AACProgress -Id 'resources' -Complete -Description ('Read {0:N0} resource(s)' -f $resources.Count)

        $names = @{}
        if ($request.ResolveIdentity) {
            $guids = @($log.Rows | Where-Object { $_.Caller -match '^[0-9a-fA-F-]{36}$' -and -not $_.Mirid } | ForEach-Object { ([string]$_.Caller).ToLowerInvariant() } | Sort-Object -Unique)
            if ($guids.Count) {
                Update-AACProgress -Id 'identity' -Indeterminate -Description "Looking up $($guids.Count) service principal(s) in Microsoft Graph"
                $directory = Get-AACDirectoryObject -Id $guids
                foreach ($key in @($directory.Objects.Keys)) { if ($directory.Objects[$key]['displayName']) { $names[$key] = [string]$directory.Objects[$key]['displayName'] } }
                if ($directory.Error) { $notices.Add("Service principal names couldn't all be read from Microsoft Graph: $($directory.Error)") }
                Update-AACProgress -Id 'identity' -Complete -Description "Named $($names.Count) of $($guids.Count) service principal(s)"
            }
        }

        Update-AACProgress -Id 'assess' -Indeterminate -Description 'Joining the activity to the resources'
        $result = ConvertTo-AACActivityLogAssessment -Row $log.Rows -Resource $resources.ToArray() -SubscriptionName $scope.Names -Start $request.Start -End $request.End -Coverage $log.Coverage `
            -TagName $request.TagName -RequiredTag $request.RequiredTag -IdleDays $request.IdleDays -DirectoryName $names
        Update-AACProgress -Id 'assess' -Complete -Description ('{0:N0} resource(s): {1:N0} active, {2:N0} idle, {3:N0} deleted; {4:N0} operation(s) by {5:N0} caller(s)' -f $result.Stats.Resources, $result.Stats.Active, $result.Stats.Idle, $result.Stats.Deleted, $result.Stats.Operations, $result.Stats.Callers)
        @{ Result = $result; Scope = $scope; Coverage = @($log.Coverage | ForEach-Object { $_.PSObject.TypeNames.Insert(0, 'AAC.ActivityLogCoverage'); $_ }); Notices = $notices.ToArray() }
    }

    # --- Report ------------------------------------------------------------------------------------------------
    $r = $state.Result
    $stats = $r.Stats
    $rank = Get-AACSeverityRank
    $coverage = @($state.Coverage)
    $viaWorkspace = @($coverage | Where-Object Source -EQ 'Log Analytics').Count
    $window = "$($request.Start.ToString('yyyy-MM-dd')) to $($request.End.ToString('yyyy-MM-dd'))"
    $idle = @($r.Resources | Where-Object State -EQ 'Idle' | Sort-Object -Property IdleDays -Descending)
    $deleted = @($r.Resources | Where-Object State -EQ 'Deleted')
    $byLastUsed = @($r.Resources | Where-Object State -NE 'Deleted' | Sort-Object -Property LastUsed)
    $kindTones = @{ User = 'info'; 'Guest user' = 'warn'; 'Service principal' = 'violet'; 'Managed identity' = 'good'; 'Azure platform' = 'neutral'; Other = 'neutral' }
    $stateTones = @{ Active = 'good'; New = 'info'; Idle = 'warn'; Quiet = 'neutral'; Deleted = 'bad'; Gone = 'neutral' }
    $statusTones = @{ Succeeded = 'good'; Failed = 'bad'; Started = 'neutral'; Accepted = 'neutral' }
    $tagColumns = @($request.TagName | ForEach-Object { @{ Key = "Tag:$_"; Label = $_; Facet = $true } })
    $where = @(
        @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true; Console = ($state.Scope.Ids.Count -gt 1); Pdf = $true }
        @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true; Console = $true; Pdf = $true }
        @{ Key = 'ResourceType'; Label = 'Type'; Facet = $true }
        @{ Key = 'Resource'; Label = 'Resource'; Type = 'resource'; Console = $true; Pdf = $true }
    )
    $report = @{
        Subtitle    = "Activity Log - $($state.Scope.Label) - $window"
        Facts       = [ordered]@{
            Scope = $state.Scope.Label; Window = "$window ($Days days)"; Source = "$viaWorkspace of $($coverage.Count) subscription(s) from Log Analytics"
            Categories = ($request.Category -join ', '); Generated = "$([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture)) UTC"
        }
        Status      = $(if ($stats.High) { 'Failed' } elseif ($stats.Medium) { 'Warning' } else { 'Success' })
        Headline    = "$('{0:N0}' -f $stats.Operations) operation(s) by $($stats.Callers) caller(s) on $($stats.Active + $stats.New) resource(s); $($stats.Idle) idle and $($stats.Deleted) deleted of $($stats.Resources); $($stats.High) high finding(s)"
        OverviewTab = 'Summary'
        Tiles       = @(
            @{ Value = '{0:N0}' -f $stats.Resources; Label = 'resources'; Tone = 'info'; Table = 'resources' }
            @{ Value = '{0:N0}' -f ($stats.Active + $stats.New); Label = 'changed in the window'; Tone = 'good'; Table = 'resources'; Filters = @{ State = 'Active' } }
            @{ Value = '{0:N0}' -f $stats.Idle; Label = "idle $IdleDays+ days"; Tone = $(if ($stats.Idle) { 'warn' } else { 'good' }); Table = 'idle' }
            @{ Value = '{0:N0}' -f $stats.Deleted; Label = 'deleted'; Tone = 'neutral'; Table = 'deleted' }
            @{ Value = '{0:N0}' -f $stats.Operations; Label = 'operations'; Tone = 'info'; Table = 'activity' }
            @{ Value = '{0:N0}' -f $stats.ByPeople; Label = 'changes by hand'; Tone = $(if ($stats.ByPeople) { 'warn' } else { 'good' }); Table = 'activity'; Filters = @{ CallerKind = 'User' } }
            @{ Value = '{0:N0}' -f $stats.High; Label = 'high findings'; Tone = $(if ($stats.High) { 'bad' } else { 'good' }); Table = 'findings'; Filters = @{ Severity = 'High' } }
        )
        Notices     = @(
            @{ Status = 'Info'; Text = 'Last used is control-plane: the latest of the resource''s last Activity Log event, last change and creation. Data-plane use - reads, requests, sign-ins - never reaches the Activity Log: check an idle resource''s metrics before removing it.' }
            $(if ($viaWorkspace -lt $coverage.Count -and $Days -gt 90) { @{ Status = 'Warning'; Text = "$($coverage.Count - $viaWorkspace) subscription(s) don't send their Activity Log to a Log Analytics workspace: Azure keeps 90 days, so the $Days-day window is only 90 there. See the Coverage tab." } })
            $state.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } }
        )
        Charts      = @(
            @{ Title = 'Resources by state'; Kind = 'donut'; CenterLabel = 'resources'; Items = @('Active', 'New', 'Quiet', 'Idle', 'Deleted', 'Gone' | Where-Object { $stats[$_] } | ForEach-Object { @{ Label = $_; Value = $stats[$_]; Tone = $stateTones[$_] } }) }
            @{ Title = 'Operations by caller kind'; Kind = 'donut'; CenterLabel = 'operations'; Items = @(@($r.Callers | Group-Object -Property CallerKind) | ForEach-Object { @{ Label = $_.Name; Value = ($_.Group | Measure-Object -Property Operations -Sum).Sum; Tone = $kindTones[$_.Name] } } | Sort-Object -Property { $_.Value } -Descending) }
            @{ Title = 'Busiest resources'; Items = @(@($r.Resources | Where-Object Operations | Sort-Object -Property Operations -Descending) | Select-Object -First 10 -Property Resource, Operations | ForEach-Object { @{ Label = $_.Resource; Value = $_.Operations; Filter = $_.Resource } }); Table = 'resources'; Column = 'Resource'; Tone = 'info'; Console = $true }
            @{ Title = 'Busiest callers'; Items = @($r.Callers | Select-Object -First 10 -Property Caller, Operations | ForEach-Object { @{ Label = $_.Caller; Value = $_.Operations; Filter = $_.Caller } }); Table = 'activity'; Column = 'Caller'; Tone = 'violet' }
        )
        Tabs        = @(
            @{ Name = 'Resources'; Badge = $stats.Resources; Tone = 'info'; Note = 'Every resource with its activity in the window and when it was last used. State: Active (changed in the window), New (created in it), Quiet (no activity, changed less than the idle threshold ago), Idle, Deleted (in the window), Gone (has activity but isn''t there now - another scope, or moved).' }
            @{ Name = 'Last used'; Badge = $byLastUsed.Count; Tone = 'neutral'; Note = 'Every resource that exists, least recently used first.' }
            @{ Name = 'Idle'; Badge = $idle.Count; Tone = $(if ($idle.Count) { 'warn' } else { 'good' }); Note = "Resources with no change for $IdleDays day(s) or more - candidates to review. Not proof of disuse: data-plane traffic isn't in the Activity Log." }
            @{ Name = 'Deleted'; Badge = $deleted.Count; Tone = 'neutral'; Note = 'Resources deleted in the window: when, and by whom.' }
            @{ Name = 'Activity'; Badge = @($r.Activity).Count; Tone = 'info'; Note = 'Who did what to which resource: one row per resource, caller, operation and status - how many times, first and last - with the resource''s tags. Exists is False when it was deleted since, or is outside the scope.' }
            @{ Name = 'Callers'; Badge = $stats.Callers; Tone = 'violet'; Note = 'Each caller - users, guests, service principals, managed identities, Azure - with how much it did, how many failures, and on how many resources.' }
            @{ Name = 'Findings'; Badge = @($r.Findings).Count; Tone = $(if ($stats.High) { 'bad' } else { 'warn' }); Note = 'What to look at, worst first.' }
            @{ Name = 'Coverage'; Badge = $coverage.Count; Tone = $(if ($viaWorkspace -lt $coverage.Count) { 'warn' } else { 'good' }); Note = 'Where each subscription''s Activity Log was read from, and from when its data goes back: a Log Analytics workspace keeps as long as its retention; the Activity Log itself, 90 days.' }
        )
        Tables      = @(
            @{ Id = 'resources'; Title = 'Resources'; Section = 'Resources'; Rows = @($r.Resources); Noun = 'resources'; GroupBy = @('State', 'ResourceType', 'Subscription'); ConsoleLimit = 15
                Columns = $where + @(
                    @{ Key = 'State'; Label = 'State'; Type = 'badge'; Tones = $stateTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'LastUsed'; Label = 'Last used'; Type = 'datetime'; Console = $true; Pdf = $true }
                    @{ Key = 'LastUsedSource'; Label = 'From'; Facet = $true }
                    @{ Key = 'IdleDays'; Label = 'Idle days'; Type = 'number' }
                    @{ Key = 'Operations'; Label = 'Operations'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Writes'; Label = 'Writes'; Type = 'number'; Sum = $true }
                    @{ Key = 'Deletes'; Label = 'Deletes'; Type = 'number'; Sum = $true }
                    @{ Key = 'Actions'; Label = 'Actions'; Type = 'number'; Sum = $true }
                    @{ Key = 'Failed'; Label = 'Failed'; Type = 'number'; Sum = $true }
                    @{ Key = 'ByPeople'; Label = 'By hand'; Type = 'number'; Sum = $true; Console = $true }
                    @{ Key = 'LastCaller'; Label = 'Last by'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'LastOperation'; Label = 'Last operation' }
                    @{ Key = 'FirstWriteBy'; Label = 'Earliest write by'; Facet = $true }
                    @{ Key = 'Callers'; Label = 'Callers'; Type = 'wide' }
                    @{ Key = 'Tags'; Label = 'Tags'; Type = 'wide' }
                ) + $tagColumns + @(
                    @{ Key = 'Location'; Label = 'Location'; Facet = $true }
                    @{ Key = 'Created'; Label = 'Created'; Type = 'datetime' }
                    @{ Key = 'LastChanged'; Label = 'Last changed'; Type = 'datetime' }
                ) }
            @{ Id = 'lastused'; Title = 'Last used'; Section = 'Last used'; Rows = $byLastUsed; Noun = 'resources'; GroupBy = @('LastUsedSource', 'ResourceType'); NoConsole = $true
                Columns = $where + @(
                    @{ Key = 'LastUsed'; Label = 'Last used'; Type = 'datetime'; Pdf = $true }
                    @{ Key = 'LastUsedSource'; Label = 'From'; Facet = $true; Pdf = $true }
                    @{ Key = 'IdleDays'; Label = 'Idle days'; Type = 'number'; Pdf = $true }
                    @{ Key = 'LastCaller'; Label = 'Last by'; Facet = $true }
                    @{ Key = 'State'; Label = 'State'; Type = 'badge'; Tones = $stateTones; Facet = $true }
                    @{ Key = 'Tags'; Label = 'Tags'; Type = 'wide' }
                ) + $tagColumns }
            @{ Id = 'idle'; Title = "Idle $IdleDays+ days"; Section = 'Idle'; Rows = $idle; Noun = 'resources'; GroupBy = @('ResourceType', 'Subscription'); NoConsole = $true; Empty = "No resource has been idle for $IdleDays days."; EmptyStatus = 'Success'
                Columns = $where + @(
                    @{ Key = 'IdleDays'; Label = 'Idle days'; Type = 'number'; Pdf = $true }
                    @{ Key = 'LastUsed'; Label = 'Last used'; Type = 'datetime'; Pdf = $true }
                    @{ Key = 'LastUsedSource'; Label = 'From'; Facet = $true }
                    @{ Key = 'Tags'; Label = 'Tags'; Type = 'wide' }
                ) + $tagColumns + @(@{ Key = 'Created'; Label = 'Created'; Type = 'datetime' }) }
            @{ Id = 'deleted'; Title = 'Deleted in the window'; Section = 'Deleted'; Rows = $deleted; Noun = 'resources'; GroupBy = @('ResourceType', 'DeletedBy'); NoConsole = $true; Empty = 'Nothing was deleted in the window.'; EmptyStatus = 'Success'
                Columns = $where + @(
                    @{ Key = 'LastActivity'; Label = 'Deleted'; Type = 'datetime'; Pdf = $true }
                    @{ Key = 'DeletedBy'; Label = 'By'; Facet = $true; Pdf = $true }
                    @{ Key = 'Operations'; Label = 'Operations'; Type = 'number' }
                    @{ Key = 'Callers'; Label = 'Callers'; Type = 'wide' }
                ) }
            @{ Id = 'activity'; Title = 'Activity'; Section = 'Activity'; Rows = @($r.Activity); Noun = 'rows'; GroupBy = @('CallerKind', 'Kind', 'Status'); NoConsole = $true
                Columns = $where + @(
                    @{ Key = 'Exists'; Label = 'Exists'; Facet = $true }
                    @{ Key = 'CallerKind'; Label = 'Caller kind'; Type = 'badge'; Tones = $kindTones; Facet = $true; Pdf = $true }
                    @{ Key = 'Caller'; Label = 'Caller'; Facet = $true; Pdf = $true }
                    @{ Key = 'Operation'; Label = 'Operation'; Facet = $true; Pdf = $true }
                    @{ Key = 'Kind'; Label = 'Kind'; Facet = $true }
                    @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = $statusTones; Facet = $true }
                    @{ Key = 'Count'; Label = 'Times'; Type = 'number'; Sum = $true; Pdf = $true }
                    @{ Key = 'First'; Label = 'First'; Type = 'datetime' }
                    @{ Key = 'Last'; Label = 'Last'; Type = 'datetime'; Pdf = $true }
                    @{ Key = 'Tags'; Label = 'Tags'; Type = 'wide' }
                ) + $tagColumns + @(
                    @{ Key = 'CallerIp'; Label = 'Caller IP' }
                    @{ Key = 'Source'; Label = 'Source'; Facet = $true }
                    @{ Key = 'ResourceId'; Label = 'Resource ID'; Type = 'wide' }
                ) }
            @{ Id = 'callers'; Title = 'Callers'; Section = 'Callers'; Rows = @($r.Callers); Noun = 'callers'; GroupBy = @('CallerKind'); ConsoleLimit = 10
                Columns = @(
                    @{ Key = 'Caller'; Label = 'Caller'; Console = $true; Pdf = $true }
                    @{ Key = 'CallerKind'; Label = 'Kind'; Type = 'badge'; Tones = $kindTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Operations'; Label = 'Operations'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Writes'; Label = 'Writes'; Type = 'number'; Sum = $true }
                    @{ Key = 'Deletes'; Label = 'Deletes'; Type = 'number'; Sum = $true; Console = $true }
                    @{ Key = 'Failed'; Label = 'Failed'; Type = 'number'; Sum = $true; Console = $true }
                    @{ Key = 'Resources'; Label = 'Resources'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'LastSeen'; Label = 'Last seen'; Type = 'datetime'; Console = $true; Pdf = $true }
                    @{ Key = 'TopOperations'; Label = 'Top operations'; Type = 'wide' }
                ) }
            @{ Id = 'findings'; Title = 'Findings'; Section = 'Findings'; Rows = @($r.Findings); Noun = 'findings'; GroupBy = @('Severity', 'Area'); ConsoleLimit = 20; Empty = 'Nothing to look at.'; EmptyStatus = 'Success'
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Area'; Label = 'Area'; Facet = $true; Console = $true }
                    @{ Key = 'Resource'; Label = 'Resource or caller'; Console = $true; Pdf = $true }
                    @{ Key = 'Finding'; Label = 'Finding'; Console = $true; Pdf = $true }
                    @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Recommendation'; Label = 'What to do'; Type = 'wide'; Pdf = $true }
                ) }
            @{ Id = 'coverage'; Title = 'Coverage'; Section = 'Coverage'; Rows = $coverage; Noun = 'subscriptions'; GroupBy = @('Source'); ConsoleLimit = 15
                Columns = @(
                    @{ Key = 'Subscription'; Label = 'Subscription'; Console = $true; Pdf = $true }
                    @{ Key = 'Source'; Label = 'Read from'; Type = 'badge'; Tones = @{ 'Log Analytics' = 'good'; 'Activity Log' = 'warn' }; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Workspace'; Label = 'Workspace'; Console = $true; Pdf = $true }
                    @{ Key = 'RetentionDays'; Label = 'Retention days'; Type = 'number'; Console = $true }
                    @{ Key = 'CoveredFrom'; Label = 'Covered from'; Type = 'datetime'; Console = $true; Pdf = $true }
                    @{ Key = 'Note'; Label = 'Note'; Type = 'wide'; Console = $true; Pdf = $true }
                ) }
        )
        Hint        = '-Days 180 or 365 read the Log Analytics workspace the Activity Log is sent to; -TagName shows tags as columns and -RequiredTag flags missing ones; -IdleDays sets when a resource counts as idle; -View Activity, Caller, Finding or Coverage returns those rows; -HtmlPath, -PdfPath or -CsvPath for a report.'
    }
    $rows = @(switch ($View) { 'Activity' { $r.Activity } 'Caller' { $r.Callers } 'Finding' { $r.Findings } 'Coverage' { $coverage } default { $r.Resources } })
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $rows -Noun $View.ToLowerInvariant() -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $rows -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
