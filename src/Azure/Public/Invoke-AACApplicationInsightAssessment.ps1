function Invoke-AACApplicationInsightAssessment {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Assesses Application Insights components across subscriptions -
        ingestion and cost, workspace and architecture, security, identity
        and access, audit and lifecycle - as a heat map, findings, a
        Spectre.Console view, objects, and CSV, PDF and interactive HTML
        reports.
    .DESCRIPTION
        Read-only. Always (Reader is enough):
          Resource Graph    the components, their workspaces, availability
                            tests, alert rules and locks
          Resource Manager  each component's daily cap, API keys (never the
                            key), diagnostic settings and role assignments
          metrics           requests, dependencies, exceptions and traces
                            over -TimeRange
        -IncludeIngestion (Log Analytics Reader): what each workspace-based
        component ingested - billed GB by table and day, sampling, trace
        severity and health probe requests.
        -IncludeActivityLog: the Activity Log over -TimeRange - who changed
        each component, purges, API keys created, failed changes.

        Findings (High, Medium, Low), under five signals:
          Ingestion & cost     daily cap reached or close to normal volume,
                               no effective cap, no cap warning, no sampling
                               on a busy app, spikes, chatty traces,
                               dependencies or health probes, telemetry sent
                               twice by a diagnostic setting
          Architecture         classic (not workspace-based), workspace
                               missing or in another region, no
                               availability test, retired URL ping and
                               multi-step tests, too few test locations, no
                               alert rule, alerts with no action group,
                               Failure Anomalies off
          Security             local authentication (instrumentation key)
                               allowed, client IPs stored, private link scope
                               with public access left open, API keys
          Identity & access    local authentication off with no Monitoring
                               Metrics Publisher, ready for Entra ID-only
                               ingestion, Owner or access administrators on
                               the component, users instead of groups, many
                               writers, workspace-only permissions
          Audit & lifecycle    no delete lock, no owner tag, no telemetry in
                               the period; with -IncludeActivityLog, purges,
                               API keys created, changes by hand, failures

        The heat map scores each component 0-100 per signal - the 40 worst at
        the prompt and in the reports; clicking a cell in the HTML lists its
        findings.

        -View sets what is returned (piped onward, -PassThru, -NoDisplay) and
        written to -CsvPath: Component (default), Ingestion, Access, Change or
        Finding.
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups.
    .PARAMETER ResourceGroupName
        Only these resource groups.
    .PARAMETER Name
        Only components with these names; wildcards work.
    .PARAMETER TimeRange
        How far back the metrics, ingestion and Activity Log go: 1d, 3d, 7d
        (default), 14d or 30d.
    .PARAMETER IncludeIngestion
        Read what each workspace-based component ingested, from its
        workspace (Log Analytics Reader).
    .PARAMETER IncludeActivityLog
        Read the Activity Log: changes, purges, API keys created and who made
        them.
    .PARAMETER View
        Component, Ingestion, Access, Change or Finding: what is returned and
        written to -CsvPath.
    .PARAMETER ThrottleLimit
        How many requests run at once (1 to 32; 12 by default).
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
        Invoke-AACApplicationInsightAssessment
        Every component's configuration, security, access and findings over the last week.
    .EXAMPLE
        Invoke-AACApplicationInsightAssessment -ResourceGroupName 'rg-app-prod' -TimeRange 30d -IncludeIngestion -IncludeActivityLog -HtmlPath .\out\AppInsights.html -PdfPath .\out\AppInsights.pdf
        A month of a workload's components - ingestion and changes included - as reports.
    .EXAMPLE
        Invoke-AACApplicationInsightAssessment -IncludeIngestion -View Ingestion -NoDisplay | Sort-Object -Property GB -Descending | Select-Object -First 10
        The tables that cost the most.
    .EXAMPLE
        Invoke-AACApplicationInsightAssessment -View Finding -NoDisplay | Where-Object Signal -EQ 'Security'
        The security findings, to hand to the app teams.
    .OUTPUTS
        AAC.ApplicationInsightAssessment, AAC.ApplicationInsightIngestion, AAC.ApplicationInsightAccess, AAC.ApplicationInsightChange or AAC.ApplicationInsightFinding, by -View (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.ApplicationInsightAssessment', 'AAC.ApplicationInsightIngestion', 'AAC.ApplicationInsightAccess', 'AAC.ApplicationInsightChange', 'AAC.ApplicationInsightFinding')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [ValidateNotNullOrEmpty()]
        [string[]] $ManagementGroupId,

        [ValidateNotNullOrEmpty()]
        [string[]] $ResourceGroupName,

        [SupportsWildcards()]
        [string[]] $Name,

        [ValidateSet('1d', '3d', '7d', '14d', '30d')]
        [string] $TimeRange = '7d',

        [switch] $IncludeIngestion,

        [switch] $IncludeActivityLog,

        [ValidateSet('Component', 'Ingestion', 'Access', 'Change', 'Finding')]
        [string] $View = 'Component',

        [ValidateRange(1, 32)]
        [int] $ThrottleLimit = 12,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Application Insights assessment',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $range = Get-AACTimeRange -TimeRange $TimeRange
    $end = [datetime]::UtcNow
    $start = $end.AddHours(-$range[0])
    $request = @{
        SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }); ResourceGroupName = @($ResourceGroupName | Where-Object { $_ }); Name = @($Name | Where-Object { $_ })
        Start = $start; End = $end; Days = [int]($range[0] / 24); Interval = $range[1]
        Timespan = "$($start.ToString('yyyy-MM-ddTHH:mm:ssZ'))/$($end.ToString('yyyy-MM-ddTHH:mm:ssZ'))"
        IncludeIngestion = [bool]$IncludeIngestion; IncludeActivityLog = [bool]$IncludeActivityLog; ThrottleLimit = $ThrottleLimit
    }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Application Insights assessment' -Color 'mediumpurple' }
    $state = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
        $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
        Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"

        Update-AACProgress -Id 'read' -Indeterminate -Description 'Reading the components, workspaces, tests, alerts and locks (Resource Graph)'
        $read = Invoke-AACGraphBatch -Query (Get-AACApplicationInsightAssessmentQuery -ResourceGroupName $request.ResourceGroupName) -SubscriptionId $scope.GraphScope -AllowFailure @('workspaces', 'webtests', 'alerts', 'locks')
        $components = @($read.Rows['components'] | Where-Object { $n = [string]$_['name']; $null -ne $_ -and (-not $request.Name.Count -or @($request.Name | Where-Object { $n -like $_ }).Count) })
        Update-AACProgress -Id 'read' -Complete -Description ('Found {0:N0} component(s)' -f $components.Count)
        $notices = [System.Collections.Generic.List[string]]::new()
        foreach ($key in @($read.Errors.Keys | Sort-Object)) { $notices.Add("The $key couldn't be read: $($read.Errors[$key] -replace '\s+', ' ')") }
        $ids = @($components | ForEach-Object { [string]$_['id'] })

        Update-AACProgress -Id 'detail' -Total ([Math]::Max(1, $ids.Count * 5)) -Description 'Reading daily caps, API keys, diagnostic settings, role assignments and metrics'
        $tick = { param($Done, $Total) Update-AACProgress -Id 'detail' -Increment 1 }
        $detail = Read-AACApplicationInsightDetail -ComponentId $ids -ThrottleLimit $request.ThrottleLimit -OnProgress $tick
        $calls = @(foreach ($id in $ids) { @{ Id = $id; Key = 'Telemetry'; Metric = @('requests/count', 'dependencies/count', 'exceptions/count', 'traces/count'); Aggregation = @('Count'); Filter = '' } })
        $metrics = Read-AACMetric -Call $calls -Timespan $request.Timespan -Interval $request.Interval -ThrottleLimit $request.ThrottleLimit -OnProgress $tick
        Update-AACProgress -Id 'detail' -Complete -Description ('Read the settings and metrics of {0:N0} component(s)' -f $ids.Count)
        $unreadRoles = @($ids | Where-Object { $a = $detail[$_]['Roles']; -not $a -or $a['Error'] }).Count
        if ($unreadRoles) { $notices.Add("Role assignments couldn't be read for $unreadRoles component(s) - their access checks are left out.") }

        $workspaces = @($read.Rows['workspaces'] | Where-Object { $_ })
        $ingestion = $null
        if ($request.IncludeIngestion) {
            $customerId = @{}
            foreach ($w in $workspaces) { $customerId[[string]$w['id']] = [string]$w['customerId'] }
            $targets = @{}
            foreach ($c in $components) {
                $wid = ([string](Get-AACMember -InputObject $c['properties'] -Key 'WorkspaceResourceId')).ToLowerInvariant()
                if (-not $wid) { continue }
                $cid = $customerId[$wid]
                if (-not $cid) { $notices.Add("$($c['name']) writes to a workspace your account can't see ($(($wid -split '/')[-1])); its ingestion is left out."); continue }
                if (-not $targets.Contains($cid)) { $targets[$cid] = [System.Collections.Generic.List[string]]::new() }
                $targets[$cid].Add([string]$c['id'])
            }
            Update-AACProgress -Id 'ingestion' -Indeterminate -Description ('Reading ingestion from {0:N0} workspace(s)' -f $targets.Count)
            $logs = Read-AACApplicationInsightIngestion -Workspace $targets -Duration "P$($request.Days)D"
            foreach ($cid in @($logs.Errors.Keys)) { $notices.Add("Ingestion couldn't be read from workspace $($cid): $($logs.Errors[$cid] -replace '\s+', ' ')") }
            $ingestion = $logs.Rows
            Update-AACProgress -Id 'ingestion' -Complete -Description ('Read ingestion for {0:N0} table row(s)' -f @($ingestion['tables']).Count)
        }

        $activity = $null
        if ($request.IncludeActivityLog -and $ids.Count) {
            $subscriptions = @($components | ForEach-Object { [string]$_['subscriptionId'] } | Select-Object -Unique)
            $log = Read-AACActivityLog -SubscriptionId $subscriptions -SubscriptionName $scope.Names -Start $request.Start -End $request.End -Category @('Administrative') -ResourceGroupName $request.ResourceGroupName -ThrottleLimit $request.ThrottleLimit
            foreach ($n in @($log.Notices)) { if ($n) { $notices.Add([string]$n) } }
            $activity = @($log.Rows)
        }

        $result = ConvertTo-AACApplicationInsightAssessment -Component $components -Workspace $workspaces -WebTest @($read.Rows['webtests'] | Where-Object { $_ }) -Alert @($read.Rows['alerts'] | Where-Object { $_ }) -Lock @($read.Rows['locks'] | Where-Object { $_ }) `
            -Detail $detail -Metric $metrics -Ingestion $ingestion -Activity $activity -PeriodDays $request.Days -PeriodStart $request.Start -SubscriptionName $scope.Names
        @{ Result = $result; Scope = $scope; Notices = $notices.ToArray() }
    }

    # --- Report ------------------------------------------------------------------------------------------------
    $r = $state.Result
    $stats = $r.Stats
    $rank = Get-AACSeverityRank
    $componentRows = @($r.Components | Sort-Object -Property Score, Component)
    $yesNo = @{ True = 'warn'; False = 'good' }
    $report = @{
        Subtitle = "Application Insights - last $TimeRange"
        Facts    = [ordered]@{ Scope = $state.Scope.Label; 'Time range' = $TimeRange; Ingestion = $(if ($IncludeIngestion) { 'read from the workspaces' } else { 'not read (-IncludeIngestion)' }); 'Activity Log' = $(if ($IncludeActivityLog) { 'read' } else { 'not read (-IncludeActivityLog)' }); Generated = "$([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture)) UTC" }
        Status   = $(if ($stats.High) { 'Failed' } elseif (@($r.Findings).Count) { 'Warning' } else { 'Success' })
        Headline = $(if (-not $stats.Components) { 'No Application Insights component in scope.' } else { "$($stats.Components) component(s): $($stats.High) high finding(s); $($stats.Classic) classic, $($stats.LocalAuth) accepting the instrumentation key alone, $($stats.NoAlerts) with no alert rule$(if ($IncludeIngestion) { "; $('{0:N2}' -f $stats.GBPerDay) GB ingested a day" })" })
        Tiles    = @(
            @{ Value = '{0:N0}' -f $stats.Components; Label = 'components'; Tone = 'info'; Table = 'components' }
            if ($IncludeIngestion) { @{ Value = '{0:N2}' -f $stats.GBPerDay; Label = 'GB a day'; Tone = 'info'; Table = 'ingestion' } }
            @{ Value = '{0:N0}' -f $stats.Classic; Label = 'classic'; Tone = $(if ($stats.Classic) { 'bad' } else { 'good' }); Table = 'components'; Filters = @{ Mode = 'Classic' } }
            @{ Value = '{0:N0}' -f $stats.LocalAuth; Label = 'local auth allowed'; Tone = $(if ($stats.LocalAuth) { 'warn' } else { 'good' }); Table = 'components'; Filters = @{ LocalAuth = 'Allowed' } }
            @{ Value = '{0:N0}' -f $stats.NoAlerts; Label = 'without alert rules'; Tone = $(if ($stats.NoAlerts) { 'warn' } else { 'good' }); Table = 'findings'; Filters = @{ Finding = 'No alert rule' } }
            @{ Value = '{0:N0}' -f $stats.High; Label = 'high findings'; Tone = $(if ($stats.High) { 'bad' } else { 'good' }); Table = 'findings'; Filters = @{ Severity = 'High' } }
        )
        Notices  = @($state.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
        HeatMaps = @($(if (@($r.HeatMap.Rows).Count) { $r.HeatMap }))
        Charts   = @(
            @{ Title = 'Findings by signal'; Items = @($r.Findings | Group-Object -Property Signal | Sort-Object -Property Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'findings'; Column = 'Signal'; Tone = 'warn'; Console = $true }
            @{ Title = 'Ingested GB by table'; Items = @($r.Ingestion | Group-Object -Property Table | ForEach-Object { @{ Label = $_.Name; Value = [Math]::Round(($_.Group | Measure-Object -Property GB -Sum).Sum, 2); Filter = $_.Name } } | Sort-Object -Property { $_.Value } -Descending | Select-Object -First 10); Table = 'ingestion'; Column = 'Table'; Tone = 'info'; Console = [bool]@($r.Ingestion).Count }
        )
        Tabs     = @(
            @{ Name = 'Components'; Badge = $stats.Components; Tone = 'info'; Note = 'Each component: workspace, telemetry, daily cap, security settings, tests, alerts, access and lock.' }
            @{ Name = 'Findings'; Badge = @($r.Findings).Count; Tone = $(if ($stats.High) { 'bad' } else { 'warn' }); Note = 'What to fix, worst first, under the five signals.' }
            @{ Name = 'Ingestion'; Badge = @($r.Ingestion).Count; Tone = 'violet'; Note = 'Billed GB by component and table, and how much the SDK kept (100% = no sampling).' }
            @{ Name = 'Access'; Badge = @($r.Access).Count; Tone = 'neutral'; Note = 'Role assignments on each component and above, inherited ones included.' }
            @{ Name = 'Changes'; Badge = @($r.Changes).Count; Tone = 'neutral'; Note = 'The Activity Log: who changed each component, and what.' }
        )
        Tables   = @(
            @{ Id = 'components'; Title = 'Components'; Section = 'Components'; Rows = $componentRows; Noun = 'components'; GroupBy = @('Subscription', 'ResourceGroup', 'Mode', 'Workspace'); ConsoleLimit = 15
                Columns = @(
                    @{ Key = 'Component'; Label = 'Component'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Score'; Label = 'Score'; Type = 'score'; Format = 'N0'; Console = $true; Pdf = $true }
                    @{ Key = 'Mode'; Label = 'Mode'; Type = 'badge'; Tones = @{ 'Workspace-based' = 'good'; Classic = 'bad' }; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Workspace'; Label = 'Workspace'; Facet = $true; Console = $true }
                    @{ Key = 'Requests'; Label = 'Requests'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Exceptions'; Label = 'Exceptions'; Type = 'number'; Sum = $true }
                    @{ Key = 'GBPerDay'; Label = 'GB a day'; Type = 'number'; Format = 'N3'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'RetainedPct'; Label = 'Retained %'; Type = 'number'; Format = 'N1' }
                    @{ Key = 'DailyCapGB'; Label = 'Daily cap GB'; Type = 'number'; Format = 'N1'; Console = $true }
                    @{ Key = 'LocalAuth'; Label = 'Local auth'; Type = 'badge'; Tones = @{ Disabled = 'good'; Allowed = 'warn' }; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'IpMasking'; Label = 'IP masking'; Facet = $true }
                    @{ Key = 'PublicIngestion'; Label = 'Public ingestion'; Type = 'badge'; Tones = $yesNo; Facet = $true }
                    @{ Key = 'PrivateLinkScope'; Label = 'Private link scope'; Facet = $true }
                    @{ Key = 'ApiKeys'; Label = 'API keys'; Type = 'number'; Sum = $true }
                    @{ Key = 'AvailabilityTests'; Label = 'Tests'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'AlertRules'; Label = 'Alert rules'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'Publishers'; Label = 'Publishers'; Type = 'number' }
                    @{ Key = 'Writers'; Label = 'Writers'; Type = 'number' }
                    @{ Key = 'Lock'; Label = 'Locked'; Facet = $true }
                    @{ Key = 'Changes'; Label = 'Changes'; Type = 'number'; Sum = $true }
                    @{ Key = 'Findings'; Label = 'Findings'; Type = 'number'; Sum = $true; Console = $true }
                    @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                ) }
            @{ Id = 'findings'; Title = 'Findings'; Section = 'Findings'; Rows = @($r.Findings); Noun = 'findings'; GroupBy = @('Signal', 'Finding', 'Severity', 'Component'); ConsoleLimit = 20
                Empty = 'Nothing to fix.'; EmptyStatus = 'Success'
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Component'; Label = 'Component'; Type = 'resource'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Signal'; Label = 'Signal'; Facet = $true; Console = $true }
                    @{ Key = 'Finding'; Label = 'Finding'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Recommendation'; Label = 'What to do'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                ) }
            @{ Id = 'ingestion'; Title = 'Ingestion by table'; Section = 'Ingestion'; Rows = @($r.Ingestion); Noun = 'rows'; GroupBy = @('Component', 'Table'); ConsoleLimit = 15
                Empty = $(if ($IncludeIngestion) { 'No ingestion read.' } else { 'Not read: add -IncludeIngestion.' }); EmptyStatus = 'Info'
                Columns = @(
                    @{ Key = 'Component'; Label = 'Component'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Table'; Label = 'Table'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'GB'; Label = 'GB'; Type = 'number'; Format = 'N3'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'GBPerDay'; Label = 'GB a day'; Type = 'number'; Format = 'N3'; Sum = $true; Console = $true }
                    @{ Key = 'Share'; Label = 'Share %'; Type = 'number'; Format = 'N1'; Console = $true; Pdf = $true }
                    @{ Key = 'Rows'; Label = 'Rows'; Type = 'number'; Sum = $true }
                    @{ Key = 'RetainedPct'; Label = 'Retained %'; Type = 'number'; Format = 'N1'; Console = $true }
                ) }
            @{ Id = 'access'; Title = 'Role assignments'; Section = 'Access'; Rows = @($r.Access); Noun = 'assignments'; GroupBy = @('Component', 'Role', 'Level', 'PrincipalType'); ConsoleLimit = 15
                Empty = 'No role assignment read.'; EmptyStatus = 'Info'
                Columns = @(
                    @{ Key = 'Component'; Label = 'Component'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Role'; Label = 'Role'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'PrincipalType'; Label = 'Principal type'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'PrincipalId'; Label = 'Principal ID'; Type = 'mono'; Console = $true }
                    @{ Key = 'Level'; Label = 'Granted at'; Facet = $true; Console = $true; Pdf = $true }
                ) }
            @{ Id = 'changes'; Title = 'Changes (Activity Log)'; Section = 'Changes'; Rows = @($r.Changes); Noun = 'rows'; GroupBy = @('Component', 'Operation', 'CallerType', 'Status'); ConsoleLimit = 15
                Empty = $(if ($IncludeActivityLog) { 'No change in the period.' } else { 'Not read: add -IncludeActivityLog.' }); EmptyStatus = 'Info'
                Columns = @(
                    @{ Key = 'Component'; Label = 'Component'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Operation'; Label = 'Operation'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Status'; Label = 'Status'; Facet = $true; Console = $true }
                    @{ Key = 'Caller'; Label = 'Caller'; Type = 'mono'; Console = $true; Pdf = $true }
                    @{ Key = 'CallerType'; Label = 'Caller type'; Facet = $true }
                    @{ Key = 'Count'; Label = 'Count'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Last'; Label = 'Last'; Type = 'date'; Console = $true }
                ) }
        )
        Hint     = '-IncludeIngestion reads billed GB by table; -IncludeActivityLog reads who changed what; -TimeRange 30d looks further back; -View Ingestion, Access, Change or Finding returns those rows; -HtmlPath, -PdfPath or -CsvPath for a report.'
    }
    $rows = @(switch ($View) { 'Ingestion' { $r.Ingestion } 'Access' { $r.Access } 'Change' { $r.Changes } 'Finding' { $r.Findings } default { $componentRows } })
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $rows -Noun $View.ToLowerInvariant() -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $rows -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
