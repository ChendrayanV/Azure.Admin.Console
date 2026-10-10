function Invoke-AACHealthCheck {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Checks that your applications and their Azure platform are healthy
        right now - endpoints answering (synthetic requests, latency, TLS
        certificates), databases reachable, queues flowing, Resource Health,
        Service Health and fired alerts - by tier, with an SLA report.
    .DESCRIPTION
        Endpoints - synthetic transactions, -Count rounds -IntervalSeconds
        apart, all at once:
          -Uri          URLs; up when they answer 200-399
          -Endpoint     @{ Name; Uri; Tier; ExpectedStatus; Contains; Method;
                        TimeoutSeconds } - Contains is text the response must
                        have, for an end-to-end check (a /health page that
                        reports its dependencies)
          -Discover     the public endpoints of the App Service and Function
                        apps, Container Apps, Static Web Apps, Front Door
                        endpoints and API Management gateways (its status
                        endpoint) in scope; up unless the server errs (5xx)
        Each: availability, 50th and 95th percentile latency, and its TLS
        certificate's expiry. The requests carry no Azure credential.
        -TcpEndpoint 'host:port', and with -IncludeDatabase the SQL,
        PostgreSQL, MySQL and Redis servers in scope, are connected to (TCP)
        from where the command runs.

        The platform (unless -SkipAzure): Service Bus queues (backlog and
        dead letters), Resource Health (unavailable and degraded resources),
        active Service Health events and alerts fired in the last 24 hours.

        Each check is Success, Warning or Failed, with what was found and
        what to do; the SLA table compares each endpoint's availability with
        -SlaTarget. -Watch repeats the whole check until Ctrl+C, redrawing
        it each time - a live board to keep open during an incident.

        Read-only: GET requests and TCP connections only. -SkipAzure needs
        no sign-in at all.
    .PARAMETER Uri
        URLs to check.
    .PARAMETER Endpoint
        Endpoints to check, with what to expect (see the description).
    .PARAMETER TcpEndpoint
        host:port pairs to connect to.
    .PARAMETER Discover
        Also check the public endpoints of the web apps, container apps,
        static web apps, Front Door and API Management in scope.
    .PARAMETER IncludeDatabase
        Also connect to the SQL, PostgreSQL, MySQL and Redis servers in scope.
    .PARAMETER SkipAzure
        Check only the endpoints given - no Azure reads, no sign-in.
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups.
    .PARAMETER ResourceGroupName
        Only these resource groups (discovery, queues and Resource Health).
    .PARAMETER Count
        How many rounds of requests (1 to 100; 3 by default).
    .PARAMETER IntervalSeconds
        Seconds between rounds (0 to 3600; 5 by default).
    .PARAMETER TimeoutSeconds
        How long to wait for each request (1 to 120; 10 by default).
    .PARAMETER SlaTarget
        The availability target, in percent (99.9 by default).
    .PARAMETER LatencyThresholdMs
        Slower 95th percentile latency is a warning (2000 ms by default).
    .PARAMETER CertificateDays
        A certificate expiring sooner is a warning (30 days by default).
    .PARAMETER QueueBacklog
        More messages waiting is a warning (1000 by default).
    .PARAMETER MaxEndpoints
        At most this many discovered endpoints are checked (100 by default).
    .PARAMETER Watch
        Repeat the check until Ctrl+C, redrawing the view each time.
    .PARAMETER CsvPath
        Write the checks to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report, with the SLA table.
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the checks.
    .PARAMETER NoDisplay
        Return the checks without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Invoke-AACHealthCheck -Discover -ResourceGroupName 'rg-app-prod'
        The production app's endpoints, queues and platform health.
    .EXAMPLE
        Invoke-AACHealthCheck -SkipAzure -Endpoint @{ Name = 'Checkout'; Uri = 'https://shop.contoso.com/health'; Tier = 'Critical'; Contains = '"status":"Healthy"' } -Count 10 -IntervalSeconds 30 -HtmlPath .\out\Sla.html
        Ten checks of the checkout's health page, five minutes apart, as an SLA report.
    .EXAMPLE
        Invoke-AACHealthCheck -Discover -Watch -IntervalSeconds 60
        A live board, refreshed every minute, until Ctrl+C.
    .OUTPUTS
        AAC.HealthCheck
    #>
    [CmdletBinding()]
    [OutputType('AAC.HealthCheck')]
    param(
        [string[]] $Uri,

        [hashtable[]] $Endpoint,

        [ValidatePattern('^[^:\s]+:\d{1,5}$')]
        [string[]] $TcpEndpoint,

        [switch] $Discover,

        [switch] $IncludeDatabase,

        [switch] $SkipAzure,

        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string[]] $ManagementGroupId,

        [string[]] $ResourceGroupName,

        [ValidateRange(1, 100)]
        [int] $Count = 3,

        [ValidateRange(0, 3600)]
        [int] $IntervalSeconds = 5,

        [ValidateRange(1, 120)]
        [int] $TimeoutSeconds = 10,

        [ValidateRange(0, 100)]
        [double] $SlaTarget = 99.9,

        [ValidateRange(1, 600000)]
        [int] $LatencyThresholdMs = 2000,

        [ValidateRange(1, 365)]
        [int] $CertificateDays = 30,

        [ValidateRange(1, [long]::MaxValue)]
        [long] $QueueBacklog = 1000,

        [ValidateRange(1, 1000)]
        [int] $MaxEndpoints = 100,

        [switch] $Watch,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Health check',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    if ($SkipAzure -and ($Discover -or $IncludeDatabase)) { throw '-Discover and -IncludeDatabase read Azure: leave out -SkipAzure.' }
    if ($SkipAzure -and -not ($Uri -or $Endpoint -or $TcpEndpoint)) { throw 'Nothing to check: give -Uri, -Endpoint or -TcpEndpoint with -SkipAzure.' }

    # The endpoints given.
    $given = [System.Collections.Generic.List[object]]::new()
    $n = 0
    foreach ($u in @($Uri | Where-Object { $_ })) { $n++; $given.Add(@{ Key = "uri$n"; Name = ([uri]$u).Host + ([uri]$u).AbsolutePath.TrimEnd('/'); Kind = 'Http'; Uri = $u; Tier = 'Default'; TimeoutSeconds = $TimeoutSeconds }) }
    foreach ($e in @($Endpoint | Where-Object { $_ })) {
        if (-not $e.Contains('Uri')) { throw "An -Endpoint has no Uri: @{ $(@($e.Keys) -join '; ') }." }
        $n++
        $spec = @{ Key = "endpoint$n"; Name = $(if ($e.Contains('Name')) { [string]$e.Name } else { ([uri]$e.Uri).Host }); Kind = 'Http'; Uri = [string]$e.Uri; Tier = $(if ($e.Contains('Tier')) { [string]$e.Tier } else { 'Default' }); TimeoutSeconds = $(if ($e.Contains('TimeoutSeconds')) { [int]$e.TimeoutSeconds } else { $TimeoutSeconds }) }
        foreach ($k in 'ExpectedStatus', 'Contains', 'Method') { if ($e.Contains($k)) { $spec[$k] = $e[$k] } }
        $given.Add($spec)
    }
    foreach ($t in @($TcpEndpoint | Where-Object { $_ })) { $n++; $hostName, $port = $t.Split(':'); $given.Add(@{ Key = "tcp$n"; Name = $t; Kind = 'Tcp'; Host = $hostName; Port = [int]$port; Tier = 'Data'; TimeoutSeconds = $TimeoutSeconds }) }

    $request = @{
        SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }); ResourceGroupName = @($ResourceGroupName | Where-Object { $_ })
        Discover = [bool]$Discover; IncludeDatabase = [bool]$IncludeDatabase; SkipAzure = [bool]$SkipAzure; Given = $given.ToArray(); Count = $Count; IntervalSeconds = $IntervalSeconds; TimeoutSeconds = $TimeoutSeconds; MaxEndpoints = $MaxEndpoints
    }
    $settings = @{ SlaTarget = $SlaTarget; LatencyThresholdMs = $LatencyThresholdMs; CertificateDays = $CertificateDays; QueueBacklog = $QueueBacklog }
    if (-not $SkipAzure) { $null = Get-AACAccessToken }

    $run = {
        if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Health check' -Color 'deepskyblue3_1' }
        Invoke-AACProgress -ScriptBlock {
            $notices = [System.Collections.Generic.List[string]]::new()
            $endpoints = [System.Collections.Generic.List[object]]::new()
            foreach ($g in $request.Given) { $endpoints.Add($g) }
            $platform = @{ Health = @(); Events = @(); Alerts = @(); Queues = @() }
            $scopeLabel = 'the endpoints given'
            if (-not $request.SkipAzure) {
                Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
                $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
                $scopeLabel = $scope.Label
                Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"
                $quote = { param([string] $Text) "'" + ($Text -replace "'", "\'") + "'" }
                $groupFilter = if ($request.ResourceGroupName.Count) { " | where resourceGroup in~ ($((@($request.ResourceGroupName | ForEach-Object { & $quote $_ })) -join ', '))" } else { '' }
                $queries = [ordered]@{
                    health   = "healthresources | where type =~ 'microsoft.resourcehealth/availabilitystatuses' | extend resourceId = tolower(tostring(properties.targetResourceId)), resourceGroup = tostring(split(tostring(properties.targetResourceId), '/')[4]) $groupFilter | project id, resourceId, state = tostring(properties.availabilityState), summary = tostring(properties.summary), since = tostring(properties.occuredTime)"
                    events   = "servicehealthresources | where type =~ 'microsoft.resourcehealth/events' | extend p = properties | where tostring(p.Status) =~ 'Active' | project id, trackingId = name, title = tostring(p.Title), eventType = tostring(p.EventType)"
                    alerts   = "alertsmanagementresources | where type =~ 'microsoft.alertsmanagement/alerts' | extend e = properties.essentials | where tostring(e.monitorCondition) =~ 'Fired' and todatetime(e.startDateTime) > ago(24h) | extend resourceGroup = tostring(e.targetResourceGroup) $groupFilter | project id, name, severity = tostring(e.severity), fired = tostring(e.startDateTime), target = tolower(tostring(e.targetResource)), description = tostring(e.description)"
                    services = "resources | where type =~ 'microsoft.servicebus/namespaces'$groupFilter | project id, name"
                }
                if ($request.Discover) {
                    $queries['web'] = "resources | where type in~ ('microsoft.web/sites', 'microsoft.web/staticsites', 'microsoft.app/containerapps', 'microsoft.cdn/profiles/afdendpoints', 'microsoft.apimanagement/service')$groupFilter | extend host = case(type =~ 'microsoft.web/sites', tostring(properties.defaultHostName), type =~ 'microsoft.web/staticsites', tostring(properties.defaultHostname), type =~ 'microsoft.app/containerapps', iff(tobool(properties.configuration.ingress.external), tostring(properties.configuration.ingress.fqdn), ''), type =~ 'microsoft.cdn/profiles/afdendpoints', tostring(properties.hostName), type =~ 'microsoft.apimanagement/service', tostring(parse_url(tostring(properties.gatewayUrl)).Host), '') | where isnotempty(host) and tostring(properties.publicNetworkAccess) !~ 'Disabled' and tostring(properties.state) !~ 'Stopped' | project id, name, type = tolower(type), host"
                }
                if ($request.IncludeDatabase) {
                    $queries['databases'] = "resources | where type in~ ('microsoft.sql/servers', 'microsoft.dbforpostgresql/flexibleservers', 'microsoft.dbformysql/flexibleservers', 'microsoft.cache/redis')$groupFilter | project id, name, type = tolower(type), host = coalesce(tostring(properties.fullyQualifiedDomainName), tostring(properties.hostName)), publicAccess = coalesce(tostring(properties.publicNetworkAccess), tostring(properties.network.publicNetworkAccess))"
                }
                Update-AACProgress -Id 'read' -Total $queries.Count -Description 'Reading Resource Health, Service Health, alerts and what to probe'
                $read = Invoke-AACGraphBatch -Query $queries -SubscriptionId $scope.GraphScope -AllowFailure @($queries.Keys) -OnProgress { param($Name, $Done, $Total) Update-AACProgress -Id 'read' -Increment 1 -Description "Read the $Name ($Done of $Total)" }
                foreach ($key in $read.Errors.Keys) { if ($read.Errors[$key]) { $notices.Add("The $key couldn't be read: $($read.Errors[$key])") } }
                $platform.Health = @($read.Rows['health'] | Where-Object { $_ })
                $platform.Events = @($read.Rows['events'] | Where-Object { $_ })
                $platform.Alerts = @($read.Rows['alerts'] | Where-Object { $_ })
                Update-AACProgress -Id 'read' -Complete -Description ('Read {0:N0} resource health status(es), {1:N0} service event(s), {2:N0} alert(s)' -f $platform.Health.Count, $platform.Events.Count, $platform.Alerts.Count)
                $tierOf = @{ 'microsoft.web/sites' = 'Web'; 'microsoft.web/staticsites' = 'Web'; 'microsoft.app/containerapps' = 'Web'; 'microsoft.cdn/profiles/afdendpoints' = 'Edge'; 'microsoft.apimanagement/service' = 'API' }
                $discovered = @(if ($request.Discover) { $read.Rows['web'] | Where-Object { $_ } | Select-Object -First $request.MaxEndpoints })
                if ($request.Discover -and @($read.Rows['web']).Count -gt $request.MaxEndpoints) { $notices.Add("Only the first $($request.MaxEndpoints) of $(@($read.Rows['web']).Count) discovered endpoints were checked (-MaxEndpoints).") }
                foreach ($w in $discovered) {
                    $path = if ([string]$w['type'] -eq 'microsoft.apimanagement/service') { '/status-0123456789abcdef' } else { '/' }
                    $endpoints.Add(@{ Key = "web|$($w['id'])"; Name = [string]$w['name']; Kind = 'Http'; Uri = "https://$($w['host'])$path"; Tier = $tierOf[[string]$w['type']]; ExpectedStatus = $(if ($path -eq '/') { 'Below500' } else { @(200) }); TimeoutSeconds = $request.TimeoutSeconds; ResourceId = [string]$w['id'] })
                }
                $ports = @{ 'microsoft.sql/servers' = 1433; 'microsoft.dbforpostgresql/flexibleservers' = 5432; 'microsoft.dbformysql/flexibleservers' = 3306; 'microsoft.cache/redis' = 6380 }
                foreach ($d in @(if ($request.IncludeDatabase) { $read.Rows['databases'] | Where-Object { $_ -and $_['host'] } })) {
                    $endpoints.Add(@{ Key = "db|$($d['id'])"; Name = [string]$d['name']; Kind = 'Tcp'; Host = [string]$d['host']; Port = $ports[[string]$d['type']]; Tier = 'Data'; TimeoutSeconds = $request.TimeoutSeconds; ResourceId = [string]$d['id']; Private = ([string]$d['publicAccess'] -eq 'Disabled') })
                }
                # Service Bus queues: their counts, from Resource Manager.
                $namespaces = @($read.Rows['services'] | Where-Object { $_ })
                if ($namespaces.Count) {
                    Update-AACProgress -Id 'queues' -Indeterminate -Description "Reading the queues of $($namespaces.Count) Service Bus namespace(s)"
                    $queueUris = @{}
                    foreach ($ns in $namespaces) { $queueUris["$($ns['id'])/queues?api-version=2021-11-01"] = [string]$ns['name'] }
                    $answers = Invoke-AACArmParallel -Uri @($queueUris.Keys)
                    $platform.Queues = @(foreach ($queueUri in $queueUris.Keys) {
                            $answer = $answers[$queueUri]
                            if (-not $answer -or $answer.Error) { $notices.Add("The queues of $($queueUris[$queueUri]) couldn't be read: $(if ($answer) { $answer.Error })"); continue }
                            foreach ($q in @($answer.Items | Where-Object { $_ })) {
                                $counts = $q['properties']['countDetails']
                                @{ Namespace = $queueUris[$queueUri]; Queue = [string]$q['name']; Status = [string]$q['properties']['status']; Active = [long]$counts['activeMessageCount']; DeadLetter = [long]$counts['deadLetterMessageCount']; ResourceId = [string]$q['id'] }
                            }
                        })
                    Update-AACProgress -Id 'queues' -Complete -Description ('Read {0:N0} queue(s)' -f $platform.Queues.Count)
                }
            }

            # --- Probe the endpoints, then their certificates --------------------------------------------------------------
            $probes = $endpoints.ToArray()
            $probeResult = @{}
            $certificates = @{}
            if ($probes.Count) {
                Update-AACProgress -Id 'probe' -Total $request.Count -Description "Checking $($probes.Count) endpoint(s), $($request.Count) round(s)"
                $probeResult = Invoke-AACEndpointProbe -Probe $probes -Round $request.Count -IntervalSeconds $request.IntervalSeconds -OnRound { param($ProbeRound, $ProbeRounds) Update-AACProgress -Id 'probe' -Increment 1 -Description "Checked $($probes.Count) endpoint(s): round $ProbeRound of $ProbeRounds" }
                Update-AACProgress -Id 'probe' -Complete -Description "Checked $($probes.Count) endpoint(s), $($request.Count) round(s)"
                $https = @($probes | Where-Object { $_.Kind -eq 'Http' -and ([string]$_.Uri) -like 'https://*' })
                if ($https.Count) {
                    Update-AACProgress -Id 'tls' -Total $https.Count -Description 'Reading the TLS certificates'
                    foreach ($p in $https) { $u = [uri]$p.Uri; $certificates[[string]$p.Key] = Get-AACTlsCertificate -HostName $u.Host -Port $u.Port -TimeoutSeconds $request.TimeoutSeconds; Update-AACProgress -Id 'tls' -Increment 1 }
                    Update-AACProgress -Id 'tls' -Complete -Description "Read $($https.Count) TLS certificate(s)"
                }
            }
            $result = ConvertTo-AACHealthCheck -Endpoint $probes -ProbeResult $probeResult -Certificate $certificates -Queue $platform.Queues -HealthStatus $platform.Health -ServiceEvent $platform.Events -Alert $platform.Alerts @settings
            @{ Result = $result; Scope = $scopeLabel; Notices = $notices.ToArray() }
        }
    }

    $view = {
        param($State)
        $result = $State.Result
        $s = $result.Stats
        $statusTones = @{ Failed = 'bad'; Warning = 'warn'; Success = 'good'; Info = 'info' }
        @{
            Subtitle = 'Health check: endpoints, databases, queues and the Azure platform'
            Facts    = [ordered]@{ Scope = $State.Scope; Rounds = "$Count, $IntervalSeconds s apart"; 'SLA target' = "$SlaTarget%" }
            Status   = $(if ($s.Failed) { 'Failed' } elseif ($s.Warnings) { 'Warning' } else { 'Success' })
            Headline = "$($s.Checks) check(s): $($s.Failed) failed, $($s.Warnings) warning(s), $($s.Passed) healthy$(if ($s.Endpoints) { " - $($s.SlaMet) of $($s.Endpoints) endpoint(s) met the $SlaTarget% target" })"
            Tiles    = @(
                @{ Value = '{0:N0}' -f $s.Failed; Label = 'failed'; Tone = $(if ($s.Failed) { 'bad' } else { 'good' }); Table = 'checks'; Filters = @{ Status = 'Failed' } }
                @{ Value = '{0:N0}' -f $s.Warnings; Label = 'warnings'; Tone = $(if ($s.Warnings) { 'warn' } else { 'good' }); Table = 'checks'; Filters = @{ Status = 'Warning' } }
                @{ Value = '{0:N0}' -f $s.Passed; Label = 'healthy'; Tone = 'good'; Table = 'checks'; Filters = @{ Status = 'Success' } }
                @{ Value = $(if ($null -ne $s.Availability) { "$($s.Availability)%" } else { '-' }); Label = 'endpoint availability'; Tone = $(if ($null -eq $s.Availability) { 'neutral' } elseif ($s.Availability -ge $SlaTarget) { 'good' } else { 'bad' }); Table = 'sla' }
                @{ Value = "$($s.SlaMet)/$($s.Endpoints)"; Label = 'met the SLA'; Tone = $(if ($s.SlaMet -eq $s.Endpoints) { 'good' } else { 'bad' }); Table = 'sla' }
            )
            Notices  = @($State.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
            Charts   = @(
                @{ Title = 'Checks by status'; Kind = 'donut'; CenterLabel = 'checks'; Items = @(foreach ($st in 'Failed', 'Warning', 'Info', 'Success') { $c = @($result.Checks | Where-Object Status -EQ $st).Count; if ($c) { @{ Label = $st; Value = $c; Tone = $statusTones[$st]; Filter = $st } } }); Table = 'checks'; Column = 'Status' }
                @{ Title = 'Problems by tier'; Items = @($result.Checks | Where-Object { $_.Status -in 'Failed', 'Warning' } | Group-Object Tier | Sort-Object Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'checks'; Column = 'Tier'; Tone = 'warn' }
                @{ Title = '95th percentile latency (ms)'; Items = @($result.Sla | Where-Object { $null -ne $_.LatencyP95 } | Sort-Object LatencyP95 -Descending | Select-Object -First 12 | ForEach-Object { @{ Label = $_.Endpoint; Value = $_.LatencyP95 } }); Tone = 'info'; Console = $true }
            )
            Tables   = @(
                @{ Id = 'checks'; Title = 'Checks'; Section = 'Checks'; Rows = $result.Checks; Noun = 'checks'; GroupBy = @('Tier', 'Category', 'Status'); ConsoleLimit = 40
                    Empty = 'Nothing to check.'; EmptyStatus = 'Info'
                    Columns = @(
                        @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = $statusTones; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Tier'; Label = 'Tier'; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Category'; Label = 'Check'; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Check'; Label = 'Name'; Console = $true; Pdf = $true }
                        @{ Key = 'Detail'; Label = 'Found'; Type = 'wide'; Console = $true; Pdf = $true }
                        @{ Key = 'Availability'; Label = 'Availability (%)'; Type = 'number'; Format = 'N2' }
                        @{ Key = 'LatencyP95'; Label = 'p95 (ms)'; Type = 'number'; Format = 'N0'; Console = $true }
                        @{ Key = 'CertificateDays'; Label = 'Certificate (days)'; Type = 'number' }
                        @{ Key = 'Target'; Label = 'Target'; Type = 'mono' }
                        @{ Key = 'Remediation'; Label = 'What to do'; Type = 'wide'; Pdf = $true }
                    ) }
                @{ Id = 'sla'; Title = 'SLA'; Section = 'SLA'; Rows = $result.Sla; Noun = 'endpoints'
                    Columns = @(
                        @{ Key = 'Endpoint'; Label = 'Endpoint'; Console = $true }
                        @{ Key = 'Tier'; Label = 'Tier'; Facet = $true; Console = $true }
                        @{ Key = 'Met'; Label = 'Met'; Type = 'badge'; Tones = @{ Yes = 'good'; No = 'bad' }; Facet = $true; Console = $true }
                        @{ Key = 'Availability'; Label = 'Availability (%)'; Type = 'number'; Format = 'N2'; Console = $true }
                        @{ Key = 'Target'; Label = 'Target (%)'; Type = 'number'; Format = 'N2' }
                        @{ Key = 'Up'; Label = 'Answered'; Type = 'number' }
                        @{ Key = 'Attempts'; Label = 'Attempts'; Type = 'number'; Console = $true }
                        @{ Key = 'LatencyP50'; Label = 'p50 (ms)'; Type = 'number'; Format = 'N0' }
                        @{ Key = 'LatencyP95'; Label = 'p95 (ms)'; Type = 'number'; Format = 'N0'; Console = $true }
                        @{ Key = 'Uri'; Label = 'URL'; Type = 'mono' }
                    ) }
            )
            Hint     = $(if ($Watch) { "Refreshing every $IntervalSeconds s - Ctrl+C to stop." } else { '-Discover finds the endpoints; -Count and -IntervalSeconds for an SLA; -Watch keeps it live; -NoDisplay returns the checks.' })
        }
    }

    do {
        $state = & $run
        $report = & $view $state
        if ($Watch -and $interactive) { [Spectre.Console.AnsiConsole]::Clear(); Write-AACRule -Title 'Azure Admin Console :: Health check' -Color 'deepskyblue3_1'; Show-AACReportView -Report $report; Start-Sleep -Seconds ([Math]::Max(5, $IntervalSeconds)); continue }
        Invoke-AACReportOutput -Report $report -Title $Title -CsvObject @($state.Result.Checks) -Noun 'check' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
            -ShowView:$interactive -NoPaging:$NoPaging -Object @($state.Result.Checks) -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
    } while ($Watch -and $interactive)
}
