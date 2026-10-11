function Get-AACLoadBalancerHealth {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Checks the health of your load balancers, Application Gateways and
        Traffic Manager profiles right now - every backend's health probe,
        each pool's healthy and unhealthy hosts, the data path, endpoints'
        monitor status - and finds what breaks routing: backends down, empty
        pools, rules without probes, retired SKUs and no redundancy.
    .DESCRIPTION
        Reads, read-only:
          Resource Graph   the load balancers (pools, probes, rules), the
                           Application Gateways (pools, HTTP settings,
                           capacity, state), the Traffic Manager profiles
                           (endpoints and their monitor status) and the
                           backend NICs (to name each probed IP after its VM)
          Azure Monitor    the last -Minutes (30) of each Standard load
                           balancer's health probe status per backend IP
                           (DipAvailability) and data path availability
                           (VipAvailability), and each v2 Application
                           Gateway's healthy and unhealthy host count per
                           pool and HTTP settings

        Backends (AAC.LoadBalancerBackend) - Unhealthy, Partial (the probe
        flapped), Unknown, Not measured, Disabled or Healthy - with the
        probe and its availability; the balancers (Unhealthy, Degraded,
        Healthy, Stopped) and findings with what to do: every backend of a
        pool down, backends failing their probe, data path below 100%, an
        empty pool, a rule without a probe, a single backend or gateway
        instance, Basic load balancers and Application Gateway v1 (both
        retired), Traffic Manager endpoints degraded or profiles disabled.

        Basic load balancers and v1 gateways publish no health metrics:
        their backends are Not measured. -SkipMetrics checks the
        configuration only. Read-only; Reader (or Monitoring Reader).
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups (at any depth).
    .PARAMETER ResourceGroupName
        Only balancers in these resource groups.
    .PARAMETER Name
        Only balancers whose name matches; wildcards work.
    .PARAMETER Kind
        Only these kinds: LoadBalancer, ApplicationGateway, TrafficManager.
    .PARAMETER Health
        Only backends in these states (Unhealthy, Partial, Unknown,
        NotMeasured, Disabled, Healthy).
    .PARAMETER Minutes
        How far back the metrics are read. Default 30.
    .PARAMETER SkipMetrics
        Don't read Azure Monitor: the configuration only.
    .PARAMETER CsvPath
        Write the backends to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report.
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the backends.
    .PARAMETER NoDisplay
        Return the backends without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Get-AACLoadBalancerHealth
        Every balancer's backends, the unhealthy first, and the findings.
    .EXAMPLE
        Get-AACLoadBalancerHealth -Health Unhealthy, Partial -NoDisplay | Format-Table Balancer, Pool, Backend, Address, Availability
        The backends failing their health probe.
    .EXAMPLE
        Get-AACLoadBalancerHealth -Kind ApplicationGateway -Minutes 60 -HtmlPath .\out\Gateways.html
        The Application Gateways over the last hour, as an HTML report.
    .OUTPUTS
        AAC.LoadBalancerBackend
    #>
    [CmdletBinding()]
    [OutputType('AAC.LoadBalancerBackend')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string[]] $ManagementGroupId,

        [string[]] $ResourceGroupName,

        [SupportsWildcards()]
        [string[]] $Name,

        [ValidateSet('LoadBalancer', 'ApplicationGateway', 'TrafficManager')]
        [string[]] $Kind,

        [ValidateSet('Unhealthy', 'Partial', 'Unknown', 'NotMeasured', 'Disabled', 'Healthy')]
        [string[]] $Health,

        [ValidateRange(5, 1440)]
        [int] $Minutes = 30,

        [switch] $SkipMetrics,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Azure load balancer health',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $request = @{ SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }); ResourceGroupName = @($ResourceGroupName | Where-Object { $_ }); Name = @($Name | Where-Object { $_ }); Kind = @($Kind | Where-Object { $_ }); Minutes = $Minutes; SkipMetrics = [bool]$SkipMetrics }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Load balancer health' -Color 'steelblue1' }
    $outcome = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
        $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
        Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"
        $queries = Get-AACLoadBalancerQuery -ResourceGroupName $request.ResourceGroupName
        $wantedKinds = @{ LoadBalancer = 'loadBalancers'; ApplicationGateway = 'appGateways'; TrafficManager = 'trafficManager' }
        if ($request.Kind.Count) { foreach ($k in $wantedKinds.Keys) { if ($request.Kind -notcontains $k) { $queries.Remove($wantedKinds[$k]) } } }
        if (-not $queries.Contains('loadBalancers')) { $queries.Remove('backendNics') }
        Update-AACProgress -Id 'read' -Total $queries.Count -Description 'Reading load balancers, Application Gateways and Traffic Manager'
        $read = Invoke-AACGraphBatch -Query $queries -SubscriptionId $scope.GraphScope -AllowFailure @('backendNics') -OnProgress {
            param($QueryName, $Done, $Total)
            Update-AACProgress -Id 'read' -Increment 1 -Description "Read the $QueryName ($Done of $Total)"
        }
        foreach ($key in 'loadBalancers', 'appGateways', 'trafficManager') {
            if (-not $read.Rows.Contains($key)) { $read.Rows[$key] = @() ; continue }
            if ($request.Name.Count) { $read.Rows[$key] = @($read.Rows[$key] | Where-Object { $n = [string]$_['name']; @($request.Name | Where-Object { $n -like $_ }).Count }) }
            $read.Rows[$key] = @($read.Rows[$key] | Where-Object { $_ -and $scope.Names.Contains(([string]$_['subscriptionId']).ToLowerInvariant()) })
        }
        Update-AACProgress -Id 'read' -Complete -Description ('Read {0:N0} load balancer(s), {1:N0} Application Gateway(s), {2:N0} Traffic Manager profile(s)' -f $read.Rows['loadBalancers'].Count, $read.Rows['appGateways'].Count, $read.Rows['trafficManager'].Count)

        $metrics = @{}
        $notices = [System.Collections.Generic.List[string]]::new()
        if (-not $request.SkipMetrics) {
            $end = [datetime]::UtcNow
            $span = '{0}/{1}' -f $end.AddMinutes(-$request.Minutes).ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture), $end.ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture)
            $interval = if ($request.Minutes -le 60) { 'PT1M' } else { 'PT5M' }
            $uriFor = { param([string] $Id, [string] $Names, [string] $Filter) "$Id/providers/Microsoft.Insights/metrics?api-version=2023-10-01&metricnames=$([System.Uri]::EscapeDataString($Names))&aggregation=Average&interval=$interval&timespan=$([System.Uri]::EscapeDataString($span))$(if ($Filter) { "&`$filter=$([System.Uri]::EscapeDataString($Filter))" })" }
            $uris = [ordered]@{}
            foreach ($row in @($read.Rows['loadBalancers'] | Where-Object { [string]$_['sku'] -ne 'Basic' })) {
                $uris["$($row['id'])|Dip"] = & $uriFor $row['id'] 'DipAvailability' "BackendIPAddress eq '*'"
                $uris["$($row['id'])|Vip"] = & $uriFor $row['id'] 'VipAvailability' ''
            }
            foreach ($row in @($read.Rows['appGateways'] | Where-Object { [string]$_['tier'] -notin 'Standard', 'WAF' -and [string]$_['state'] -ne 'Stopped' })) {
                $uris["$($row['id'])|Hosts"] = & $uriFor $row['id'] 'HealthyHostCount,UnhealthyHostCount' "BackendSettingsPool eq '*'"
            }
            if ($uris.Count) {
                Update-AACProgress -Id 'metrics' -Total $uris.Count -Description "Reading the last $($request.Minutes) minutes of health metrics"
                $answers = Invoke-AACArmParallel -Uri @($uris.Values) -OnProgress { param($MetricDone, $MetricTotal) Update-AACProgress -Id 'metrics' -Increment 1 }
                $failed = 0
                foreach ($key in $uris.Keys) {
                    $id, $part = $key.Split('|')
                    if (-not $metrics.Contains($id)) { $metrics[$id] = @{ Dip = $null; Vip = $null; Hosts = $null; Error = '' } }
                    $answer = $answers[$uris[$key]]
                    if (-not $answer -or $answer.Error) { $metrics[$id].Error = $(if ($answer) { [string]$answer.Error } else { 'no answer' }); $failed++; continue }
                    $metrics[$id][$part] = $answer.Body
                }
                if ($failed) { $notices.Add("$failed health metric read(s) failed: those balancers' backends are Unknown.") }
                Update-AACProgress -Id 'metrics' -Complete -Description ('Read the health metrics of {0:N0} balancer(s)' -f $metrics.Count)
            }
        }
        $result = ConvertTo-AACLoadBalancerHealth -Read $read -Metric $metrics -SubscriptionName $scope.Names
        @{ Result = $result; Scope = $scope; Notices = @($result.Notices) + $notices.ToArray() }
    }

    $backends = @($outcome.Result.Backends)
    if ($Health) { $wanted = @($Health | ForEach-Object { if ($_ -eq 'NotMeasured') { 'Not measured' } else { $_ } }); $backends = @($backends | Where-Object { $wanted -contains $_.Health }) }
    $balancers = @($outcome.Result.Balancers)
    $findings = @($outcome.Result.Findings)

    $rank = Get-AACSeverityRank
    $healthTones = @{ Healthy = 'good'; Unhealthy = 'bad'; Partial = 'warn'; Unknown = 'neutral'; 'Not measured' = 'neutral'; Disabled = 'neutral' }
    $balancerTones = @{ Healthy = 'good'; Unhealthy = 'bad'; Degraded = 'warn'; Unknown = 'neutral'; Stopped = 'neutral' }
    $unhealthy = @($balancers | Where-Object Health -EQ 'Unhealthy').Count
    $degraded = @($balancers | Where-Object Health -EQ 'Degraded').Count
    $down = @($backends | Where-Object { $_.Health -in 'Unhealthy', 'Partial' }).Count
    $retired = @($findings | Where-Object Category -EQ 'Retirement').Count
    $report = @{
        Subtitle = 'Load balancers, Application Gateways and Traffic Manager: backend health and routing'
        Facts    = [ordered]@{ Scope = $outcome.Scope.Label; Metrics = $(if ($SkipMetrics) { 'not read (-SkipMetrics)' } else { "the last $Minutes minutes" }) }
        Status   = $(if ($unhealthy -or @($findings | Where-Object Severity -EQ 'High').Count) { 'Failed' } elseif ($degraded -or $findings.Count) { 'Warning' } else { 'Success' })
        Headline = $(if ($balancers.Count) { "$($balancers.Count) balancer(s): $unhealthy unhealthy, $degraded degraded; $down backend(s) failing their health check" } else { 'No load balancers, Application Gateways or Traffic Manager profiles in scope.' })
        Tiles    = @(
            @{ Value = '{0:N0}' -f $balancers.Count; Label = 'balancers'; Tone = 'info'; Table = 'balancers' }
            @{ Value = '{0:N0}' -f $unhealthy; Label = 'unhealthy'; Tone = $(if ($unhealthy) { 'bad' } else { 'good' }); Table = 'balancers'; Filters = @{ Health = 'Unhealthy' } }
            @{ Value = '{0:N0}' -f $degraded; Label = 'degraded'; Tone = $(if ($degraded) { 'warn' } else { 'good' }); Table = 'balancers'; Filters = @{ Health = 'Degraded' } }
            @{ Value = '{0:N0}' -f $down; Label = 'backends failing'; Tone = $(if ($down) { 'bad' } else { 'good' }); Table = 'backends'; Filters = @{ Health = 'Unhealthy' } }
            @{ Value = '{0:N0}' -f $backends.Count; Label = 'backends'; Tone = 'info'; Table = 'backends' }
            @{ Value = '{0:N0}' -f $retired; Label = 'retired SKUs'; Tone = $(if ($retired) { 'bad' } else { 'good' }); Table = 'findings'; Filters = @{ Category = 'Retirement' } }
        )
        Notices  = @($outcome.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
        Charts   = @(
            @{ Title = 'Backends by health'; Kind = 'donut'; CenterLabel = 'backends'; Items = @(foreach ($s in 'Unhealthy', 'Partial', 'Unknown', 'Not measured', 'Disabled', 'Healthy') { $n = @($backends | Where-Object Health -EQ $s).Count; if ($n) { @{ Label = $s; Value = $n; Tone = $healthTones[$s]; Filter = $s } } }); Table = 'backends'; Column = 'Health' }
            @{ Title = 'Findings by kind'; Items = @($findings | Group-Object Finding | Sort-Object Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'findings'; Column = 'Finding'; Tone = 'warn'; Console = $true }
            @{ Title = 'Balancers by kind'; Items = @($balancers | Group-Object Kind | Sort-Object Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'balancers'; Column = 'Kind'; Tone = 'info' }
        )
        Tables   = @(
            @{ Id = 'balancers'; Title = 'Balancers'; Section = 'Balancers'; Rows = $balancers; Noun = 'balancers'; GroupBy = @('Health', 'Kind', 'Subscription'); ConsoleLimit = 20
                Empty = 'No load balancers, Application Gateways or Traffic Manager profiles in scope.'
                Columns = @(
                    @{ Key = 'Health'; Label = 'Health'; Type = 'badge'; Tones = $balancerTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Balancer'; Label = 'Balancer'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Kind'; Label = 'Kind'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Sku'; Label = 'SKU / routing'; Facet = $true; Console = $true }
                    @{ Key = 'Backends'; Label = 'Backends'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'Unhealthy'; Label = 'Failing'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'DataPath'; Label = 'Data path %'; Type = 'number'; Console = $true }
                    @{ Key = 'Issues'; Label = 'Issues'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'State'; Label = 'State'; Facet = $true }
                    @{ Key = 'Pools'; Label = 'Pools'; Type = 'number' }
                    @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                ) }
            @{ Id = 'findings'; Title = 'Findings'; Section = 'Findings'; Rows = $findings; Noun = 'findings'; GroupBy = @('Severity', 'Category'); ConsoleLimit = 20
                Empty = 'No findings.'; EmptyStatus = 'Success'
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Finding'; Label = 'Finding'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Resource'; Label = 'Balancer'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'Category'; Label = 'Area'; Facet = $true }
                    @{ Key = 'Impact'; Label = 'Impact'; Type = 'wide' }
                    @{ Key = 'Remediation'; Label = 'What to do'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                    @{ Key = 'Link'; Label = 'Docs'; Type = 'link'; Text = 'Docs' }
                ) }
            @{ Id = 'backends'; Title = 'Backends'; Section = 'Backends'; Rows = $backends; Noun = 'backends'; GroupBy = @('Health', 'Balancer', 'Kind'); ConsoleLimit = 25
                Empty = 'No backends.'
                Columns = @(
                    @{ Key = 'Health'; Label = 'Health'; Type = 'badge'; Tones = $healthTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Balancer'; Label = 'Balancer'; Type = 'resource'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Pool'; Label = 'Pool'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Backend'; Label = 'Backend'; Console = $true; Pdf = $true }
                    @{ Key = 'Address'; Label = 'Address'; Type = 'mono'; Console = $true }
                    @{ Key = 'Availability'; Label = 'Probe %'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'Probe'; Label = 'Probe'; Type = 'mono' }
                    @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide' }
                    @{ Key = 'Kind'; Label = 'Kind'; Facet = $true }
                    @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                ) }
        )
        Hint     = '-Health Unhealthy, Partial narrows the backends; -Kind picks a kind of balancer; -Minutes sets the window; -NoDisplay returns the backends; -HtmlPath, -PdfPath or -CsvPath for a report.'
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $backends -Noun 'backend' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $backends -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
