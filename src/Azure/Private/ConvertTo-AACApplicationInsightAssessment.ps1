function ConvertTo-AACApplicationInsightAssessment {
    <#
    .SYNOPSIS
        Turns what Invoke-AACApplicationInsightAssessment read into
        per-component rows, ingestion by table, role assignments, changes,
        findings and a heat map.
    .DESCRIPTION
        No Azure calls. Per component (AAC.ApplicationInsightAssessment):
          architecture  Mode (Workspace-based, Classic), Workspace, its
                        region, retention and daily cap, AvailabilityTests,
                        AlertRules, SmartDetection
          ingestion     telemetry counts (metrics); with -Ingestion, billed
                        GB, GB a day, the peak day, RetainedPct (100 = no
                        sampling), DailyCapGB
          security      LocalAuth, IpMasking, PublicIngestion, PublicQuery,
                        PrivateLinkScope, ApiKeys
          access        Publishers (Monitoring Metrics Publisher), Writers,
                        DirectAssignments
          lifecycle     Lock, Created, Changes (with -Activity)
        Findings (AAC.ApplicationInsightFinding: Severity, Component, Signal,
        Finding, Detail, Recommendation) - Signal is the heat map's column:
        Ingestion & cost, Architecture, Security, Identity & access, Audit &
        lifecycle. Each signal scores 100, less 40 for a High finding, 20 for
        a Medium and 10 for a Low.
        Returns @{ Components; Ingestion; Access; Changes; Findings; HeatMap;
        Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Component,

        [AllowEmptyCollection()]
        [object[]] $Workspace = @(),

        [AllowEmptyCollection()]
        [object[]] $WebTest = @(),

        [AllowEmptyCollection()]
        [object[]] $Alert = @(),

        [AllowEmptyCollection()]
        [object[]] $Lock = @(),

        # Read-AACApplicationInsightDetail's result, by component ID.
        [hashtable] $Detail = @{},

        # Read-AACMetric's result (call Telemetry), by component ID.
        [hashtable] $Metric = @{},

        # Read-AACApplicationInsightIngestion's Rows, or $null when not read.
        [hashtable] $Ingestion,

        # Read-AACActivityLog's Rows, or $null when not read.
        [object[]] $Activity,

        [ValidateRange(1, 400)]
        [int] $PeriodDays = 7,

        [datetime] $PeriodStart = [datetime]::UtcNow.AddDays(-7),

        [hashtable] $SubscriptionName = @{}
    )

    $at = { param($Row, [string[]] $Keys) Get-AACMember -InputObject $Row -Key $Keys }
    $isTrue = { param($Value) [string]$Value -eq 'True' }
    $subName = { param([string] $Id) if ($SubscriptionName.Contains($Id)) { $SubscriptionName[$Id] } else { $Id } }
    $round = { param($Value, [int] $Digits = 2) if ($null -eq $Value) { $null } else { [Math]::Round([double]$Value, $Digits) } }
    $itemsOf = { param($Answer) @(if ($Answer -and -not $Answer['Error']) { $Answer['Items'] | Where-Object { $_ } }) }
    $readOk = { param($Answer) [bool]($Answer -and -not $Answer['Error']) }
    $sumOf = { param([object[]] $Rows, [string] $Property) $t = 0.0; foreach ($row in $Rows) { $v = & $at $row $Property; if ($null -ne $v) { $t += [double]$v } }; $t }

    # Built-in role definition IDs (the same in every tenant).
    $roleName = @{
        '8e3af657-a8ff-443c-a75c-2fe8c4bcb635' = 'Owner'; 'b24988ac-6180-42a0-ab4d-20738f5b8fd5' = 'Contributor'; 'acdd72a7-3385-48ef-bd42-f606fba81ae7' = 'Reader'
        '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9' = 'User Access Administrator'; 'f58310d9-a9f6-439a-9e8d-f62e7b41a168' = 'Role Based Access Control Administrator'
        '3913510d-42f4-4e42-8a64-420c390055eb' = 'Monitoring Metrics Publisher'; '749f88d5-cbae-40b8-bcfc-e573ddc772fa' = 'Monitoring Contributor'; '43d0d8ad-25c7-4714-9337-8ba259a9fe05' = 'Monitoring Reader'
        'ae349356-3a1b-4a5e-921d-050484c6347e' = 'Application Insights Component Contributor'; '08954f03-6346-4c2e-81c0-ec3a5cfae23b' = 'Application Insights Snapshot Debugger'
        '73c42c96-874c-492b-b04d-ab87d138a893' = 'Log Analytics Reader'; '92aaf0da-9dab-42b6-94a3-d43ce8d16293' = 'Log Analytics Contributor'
    }
    $writerRoles = @('Owner', 'Contributor', 'Monitoring Contributor', 'Application Insights Component Contributor', 'Log Analytics Contributor')
    $grantRoles = @('Owner', 'User Access Administrator', 'Role Based Access Control Administrator')

    $workspaces = @{}
    foreach ($w in $Workspace) { if ($w) { $workspaces[[string]$w['id']] = $w } }
    $lockScopes = @(foreach ($l in $Lock) { if ($l) { @{ Scope = ([string]$l['id'] -replace '/providers/microsoft\.authorization/locks/[^/]+$', ''); Level = [string]$l['level'] } } })

    # Availability tests point at their component with a 'hidden-link:<component id>' tag.
    $testsOf = @{}
    foreach ($t in $WebTest) {
        if (-not $t) { continue }
        $tags = $t['tags']
        if ($tags -isnot [System.Collections.IDictionary]) { continue }
        foreach ($key in @($tags.Keys)) {
            if ([string]$key -notlike 'hidden-link:*') { continue }
            $target = ([string]$key).Substring(12).ToLowerInvariant()
            if (-not $testsOf.Contains($target)) { $testsOf[$target] = [System.Collections.Generic.List[object]]::new() }
            $testsOf[$target].Add($t)
        }
    }

    $findings = [System.Collections.Generic.List[object]]::new()
    $componentRows = [System.Collections.Generic.List[object]]::new()
    $ingestionRows = [System.Collections.Generic.List[object]]::new()
    $accessRows = [System.Collections.Generic.List[object]]::new()
    $changeRows = [System.Collections.Generic.List[object]]::new()
    $heatRows = [System.Collections.Generic.List[object]]::new()
    $signals = @('Ingestion & cost', 'Architecture', 'Security', 'Identity & access', 'Audit & lifecycle')

    foreach ($c in @($Component | Where-Object { $_ } | Sort-Object -Property { [string]$_['name'] })) {
        $id = [string]$c['id']
        $name = [string]$c['name']
        $p = $c['properties']
        $subscription = & $subName ([string]$c['subscriptionId'])
        $find = {
            param([string] $Severity, [string] $Signal, [string] $Title, [string] $Text, [string] $Fix)
            $findings.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.ApplicationInsightFinding'; Severity = $Severity; Component = $name; Signal = $Signal; Finding = $Title; Detail = $Text; Recommendation = $Fix; ResourceGroup = [string]$c['resourceGroup']; Subscription = $subscription; ResourceId = $id })
        }
        $detailOf = if ($Detail.Contains($id)) { $Detail[$id] } else { @{} }
        $answer = { param([string] $Key) if ($detailOf.Contains($Key)) { $detailOf[$Key] } else { $null } }

        # --- Workspace and architecture -----------------------------------------------------------------------------
        $workspaceId = ([string](& $at $p 'WorkspaceResourceId')).ToLowerInvariant()
        $classic = [string](& $at $p 'IngestionMode') -ne 'LogAnalytics' -or -not $workspaceId
        $ws = if ($workspaceId -and $workspaces.Contains($workspaceId)) { $workspaces[$workspaceId] } else { $null }
        $workspaceCap = if ($ws -and $null -ne $ws['dailyQuotaGb'] -and [double]$ws['dailyQuotaGb'] -gt 0) { [double]$ws['dailyQuotaGb'] } else { $null }
        $appType = [string](& $at $p 'Application_Type')
        $tests = @(if ($testsOf.Contains($id)) { $testsOf[$id] })
        $enabledTests = @($tests | Where-Object { & $isTrue $_['enabled'] })
        $quoted = '"' + $id + '"'
        $rules = @($Alert | Where-Object { $_ -and ([string]$_['scopes']).Contains($quoted) })
        $enabledRules = @($rules | Where-Object { [string]$_['enabled'] -in 'True', 'Enabled' })
        $notifying = @($enabledRules | Where-Object { ([string]$_['actions']).Contains('actiongroups/') })
        $smartDetection = @($enabledRules | Where-Object { [string]$_['detector'] -eq 'FailureAnomaliesDetector' }).Count -gt 0

        # --- Telemetry (metrics) ------------------------------------------------------------------------------------
        $telemetry = if ($Metric.Contains($id) -and $Metric[$id].Contains('Telemetry')) { $Metric[$id]['Telemetry'] } else { $null }
        $metricsRead = [bool]($telemetry -and -not $telemetry.Error)
        $count = @{}
        foreach ($s in @(if ($metricsRead) { $telemetry.Series })) { $count[$s.Name] = (& $sumOf $s.Points 'count') + $(if ($count.Contains($s.Name)) { $count[$s.Name] } else { 0 }) }
        $countOf = { param([string] $Name) if ($metricsRead) { [long]$(if ($count.Contains($Name)) { $count[$Name] } else { 0 }) } else { $null } }
        $requests = & $countOf 'requests/count'
        $dependencies = & $countOf 'dependencies/count'
        $exceptions = & $countOf 'exceptions/count'
        $traces = & $countOf 'traces/count'

        # --- Ingestion (workspace) ----------------------------------------------------------------------------------
        $ingested = $null; $perDay = $null; $peakDay = $null; $retained = $null
        if ($null -ne $Ingestion -and -not $classic) {
            $tableRows = @($Ingestion['tables'] | Where-Object { $_ -and [string]$_['ResourceId'] -eq $id })
            $ingested = & $sumOf $tableRows 'GB'
            $rowCount = & $sumOf $tableRows 'Rows'
            $itemCount = & $sumOf $tableRows 'Items'
            $retained = if ($itemCount -gt 0) { & $round (100.0 * $rowCount / $itemCount) 1 } else { $null }
            $perDay = $ingested / $PeriodDays
            foreach ($t in @($tableRows | Sort-Object -Property { [double]$_['GB'] } -Descending)) {
                $ingestionRows.Add([pscustomobject][ordered]@{
                        PSTypeName    = 'AAC.ApplicationInsightIngestion'
                        Component     = $name
                        Table         = [string]$t['Table']
                        GB            = & $round $t['GB'] 3
                        GBPerDay      = & $round ([double]$t['GB'] / $PeriodDays) 3
                        Share         = $(if ($ingested) { & $round (100.0 * [double]$t['GB'] / $ingested) 1 } else { $null })
                        Rows          = [long]$t['Rows']
                        RetainedPct   = $(if ([double]$t['Items'] -gt 0) { & $round (100.0 * [double]$t['Rows'] / [double]$t['Items']) 1 } else { $null })
                        ResourceGroup = [string]$c['resourceGroup']
                        Subscription  = $subscription
                    })
            }
            $days = @($Ingestion['daily'] | Where-Object { $_ -and [string]$_['ResourceId'] -eq $id } | ForEach-Object { [double]$_['GB'] } | Sort-Object)
            if ($days.Count) { $peakDay = $days[-1] }
            $median = if ($days.Count) { $days[[int][Math]::Floor(($days.Count - 1) / 2)] } else { 0 }
            $shareOf = { param([string] $Table) $g = & $sumOf @($tableRows | Where-Object { [string]$_['Table'] -eq $Table }) 'GB'; if ($ingested) { 100.0 * $g / $ingested } else { 0 } }
            $traceRows = @($Ingestion['traces'] | Where-Object { $_ -and [string]$_['ResourceId'] -eq $id })
            $traceGb = & $sumOf $traceRows 'GB'
            $chattyGb = & $sumOf @($traceRows | Where-Object { [int]$_['SeverityLevel'] -le 1 }) 'GB'
            $requestRow = @($Ingestion['requests'] | Where-Object { $_ -and [string]$_['ResourceId'] -eq $id }) | Select-Object -First 1
            $sampling = & $at $p 'SamplingPercentage'

            if ($perDay -ge 1 -and $null -ne $retained -and $retained -ge 99 -and ($null -eq $sampling -or [double]$sampling -ge 100)) { & $find 'Medium' 'Ingestion & cost' 'No sampling on a busy app' ('{0:N2} GB a day, and every item is kept ({1}% retained).' -f $perDay, $retained) 'Turn on adaptive sampling in the SDK (the default in ASP.NET Core and the Azure Monitor OpenTelemetry Distro; set a target rate): failures and their related items are kept together, and costs fall with traffic.' }
            if ($peakDay -ge 0.5 -and $median -gt 0 -and $peakDay -gt 3 * $median) { & $find 'Medium' 'Ingestion & cost' 'Ingestion spike' ('The busiest day ingested {0:N2} GB, more than three times the usual {1:N2} GB.' -f $peakDay, $median) 'Find what spiked (the Ingestion view, by table), usually a retry loop, a chatty dependency or a log level left on Verbose after an incident; put a daily cap above the normal peak as a safety net.' }
            if ($ingested -gt 0 -and (& $shareOf 'AppTraces') -ge 40 -and $traceGb -gt 0 -and (100.0 * $chattyGb / $traceGb) -ge 70) { & $find 'Low' 'Ingestion & cost' 'Verbose and information traces dominate' ('Traces are {0:N0}% of the data, {1:N0}% of them Verbose or Information.' -f (& $shareOf 'AppTraces'), (100.0 * $chattyGb / $traceGb)) 'Raise the logging level the SDK collects to Warning in production (ILogger filter or the OpenTelemetry log level); keep Information for the categories you actually query.' }
            if ($ingested -gt 0 -and (& $shareOf 'AppDependencies') -ge 50) { & $find 'Low' 'Ingestion & cost' 'Dependencies dominate' ('Dependency calls are {0:N0}% of the data.' -f (& $shareOf 'AppDependencies')) 'Filter the noisy ones with a telemetry processor (fast successful calls, storage queue polling, health checks of downstream services), or let sampling cover them.' }
            if ($requestRow -and [double]$requestRow['Rows'] -ge 10000 -and (100.0 * [double]$requestRow['Health'] / [double]$requestRow['Rows']) -ge 20) { & $find 'Low' 'Ingestion & cost' 'Health probes fill the requests' ('{0:N0}% of {1:N0} requests look like health or readiness probes.' -f (100.0 * [double]$requestRow['Health'] / [double]$requestRow['Rows']), [double]$requestRow['Rows']) 'Drop successful probe requests with a telemetry processor (or an OpenTelemetry filter): they say nothing the availability test and platform health don''t.' }
        }

        # --- Daily cap ----------------------------------------------------------------------------------------------
        $billing = & $answer 'Billing'
        $cap = if (& $readOk $billing) { & $at $billing['Body'] 'DataVolumeCap', 'Cap' } else { $null }
        $capGb = if ($null -ne $cap) { [double]$cap } else { $null }
        $noWarning = (& $readOk $billing) -and (& $isTrue (& $at $billing['Body'] 'DataVolumeCap', 'StopSendNotificationWhenHitThreshold'))
        $effectiveCap = @($capGb, $workspaceCap | Where-Object { $null -ne $_ } | Sort-Object) | Select-Object -First 1
        if ($null -ne $peakDay -and $null -ne $effectiveCap -and $peakDay -ge 0.95 * $effectiveCap) { & $find 'High' 'Ingestion & cost' 'Daily cap reached: telemetry dropped' ('The busiest day ingested {0:N2} GB against a cap of {1:N2} GB a day{2}.' -f $peakDay, $effectiveCap, $(if ($workspaceCap -and $workspaceCap -eq $effectiveCap) { ' (the workspace''s)' } else { '' })) 'Bring the volume down (sampling, log levels, filters) and set the cap above the normal peak: once it is hit, nothing more is kept until the reset - including the failures you would want to see.' }
        elseif ($null -ne $perDay -and $perDay -gt 0 -and $null -ne $effectiveCap -and $effectiveCap -lt 1.5 * $perDay) { & $find 'Medium' 'Ingestion & cost' 'Daily cap close to the normal volume' ('{0:N2} GB a day on average against a cap of {1:N2} GB.' -f $perDay, $effectiveCap) 'A busy day will hit the cap and drop telemetry: raise it to two or three times the normal day, and control cost with sampling instead.' }
        if ((& $readOk $billing) -and ($null -eq $capGb -or $capGb -ge 100) -and $null -eq $workspaceCap) { & $find 'Low' 'Ingestion & cost' 'No effective daily cap' $(if ($null -eq $capGb) { 'No daily cap on the component or its workspace.' } else { "The component's cap is $capGb GB a day (the default) and the workspace has none." }) 'Set a cap two or three times above the normal peak day as a safety net against a runaway logger, with its warning on - not as a way to control cost.' }
        if ($noWarning) { & $find 'Low' 'Ingestion & cost' 'No warning before the daily cap' 'The daily cap''s warning e-mails are turned off.' 'Turn the warning back on (and alert on the workspace''s Operation table, "Data collection stopped"), so a hit cap is noticed the same day.' }

        # --- Diagnostic settings: the telemetry sent again --------------------------------------------------------------
        $diagnostics = & $answer 'Diagnostics'
        foreach ($setting in (& $itemsOf $diagnostics)) {
            $dp = & $at $setting 'properties'
            $target = ([string](& $at $dp 'workspaceId')).ToLowerInvariant()
            if (-not $target) { continue }
            $logs = @(@(& $at $dp 'logs') | Where-Object { $_ -and (& $at $_ 'enabled') -eq $true -and ([string](& $at $_ 'category') -like 'App*' -or [string](& $at $_ 'categoryGroup') -eq 'allLogs') })
            if (-not $logs.Count) { continue }
            $same = $target -eq $workspaceId
            & $find 'Medium' 'Ingestion & cost' 'Telemetry sent twice by a diagnostic setting' ("Diagnostic setting '$([string](& $at $setting 'name'))' sends the telemetry to $(if ($same) { 'the workspace the component already writes to: every item is stored and billed twice' } else { "another workspace ($(($target -split '/')[-1])): the telemetry is billed in both" })." ) 'Remove the setting: a workspace-based component already writes to its workspace. For a copy elsewhere, use a storage account or a data export rule.'
        }

        if ($classic) { & $find 'High' 'Architecture' 'Classic resource (not workspace-based)' 'Classic Application Insights was retired on 29 February 2024: its data, retention and security features are frozen, and Microsoft may migrate it automatically.' 'Migrate it to workspace-based (Properties > Migrate to Workspace-based): the connection string and instrumentation key stay the same, and the data goes to the workspace you pick.' }
        elseif (-not $ws) { & $find 'Medium' 'Architecture' 'Workspace not found' "The component writes to $(($workspaceId -split '/')[-1]), which isn't there (deleted, or your account can't see it)." 'Check the workspace still exists: a deleted workspace means telemetry has nowhere to go. Point the component at a live workspace.' }
        elseif ([string]$ws['location'] -and [string]$ws['location'] -ne [string]$c['location']) { & $find 'Low' 'Architecture' 'Workspace in another region' "The component is in $([string]$c['location']), its workspace in $([string]$ws['location'])." 'Keep telemetry in the region of the app and the component (data residency, and less to go wrong in a regional outage); one workspace per region is a common pattern.' }
        if ($null -ne $requests -and $requests -gt 0 -and -not $enabledTests.Count) { & $find 'Medium' 'Architecture' 'No availability test' 'The app serves requests, but nothing checks it from outside.' 'Add a standard availability test (from at least five locations) for its public endpoint and health page, with an alert.' }
        foreach ($t in $tests) {
            $kind = ([string]$t['kind']).ToLowerInvariant()
            if ($kind -eq 'ping') { & $find 'High' 'Architecture' 'URL ping test retired' "Availability test '$([string]$t['name'])' is a URL ping test: they were retired on 30 September 2026." 'Recreate it as a standard test (same URL; adds TLS certificate checks, HTTP verbs and headers), then delete the ping test.' }
            elseif ($kind -eq 'multistep') { & $find 'Medium' 'Architecture' 'Multi-step web test retired' "Availability test '$([string]$t['name'])' is a multi-step web test, retired in August 2024." 'Replace it with standard tests, or a custom TrackAvailability test from an Azure Function for multi-step journeys.' }
            if ((& $isTrue $t['enabled']) -and $null -ne $t['locations'] -and [int]$t['locations'] -lt 3) { & $find 'Low' 'Architecture' 'Availability test in too few locations' "Availability test '$([string]$t['name'])' runs from $([int]$t['locations']) location(s)." 'Run it from at least five locations, and alert when two or more fail: one location''s network glitch then raises no false alarm.' }
        }
        if (-not $enabledRules.Count) { & $find 'Medium' 'Architecture' 'No alert rule' 'No enabled metric, log search or smart detection alert watches this component.' 'Alert on failed requests, server response time, exceptions and availability (Azure Monitor baseline alerts list sensible thresholds), each with an action group.' }
        elseif (-not $notifying.Count) { & $find 'Low' 'Architecture' 'Alert rules tell no one' "$($enabledRules.Count) enabled rule(s), none with an action group." 'Give the rules an action group (e-mail, Teams, ITSM): an alert nobody receives only shows in the portal.' }
        if ($enabledRules.Count -and -not $smartDetection) { & $find 'Low' 'Architecture' 'Failure Anomalies smart detection off' 'There is no Failure Anomalies alert rule for this component.' 'Create the Failure Anomalies smart detector rule: it learns the normal failure rate and alerts on unusual rises, with no threshold to tune.' }

        # --- Security ---------------------------------------------------------------------------------------------
        $localAuth = -not (& $isTrue (& $at $p 'DisableLocalAuth'))
        $ipMaskingOff = & $isTrue (& $at $p 'DisableIpMasking')
        $publicIngestion = [string](& $at $p 'publicNetworkAccessForIngestion') -ne 'Disabled'
        $publicQuery = [string](& $at $p 'publicNetworkAccessForQuery') -ne 'Disabled'
        $scoped = @(@(& $at $p 'PrivateLinkScopedResources') | Where-Object { $_ }).Count -gt 0
        $apiKeys = & $answer 'ApiKeys'
        $keys = @(& $itemsOf $apiKeys)
        $writeKeys = @($keys | Where-Object { @(& $at $_ 'LinkedWriteProperties' | Where-Object { $_ }).Count })
        if ($localAuth) { & $find 'Medium' 'Security' 'Local authentication allowed' 'Telemetry is accepted with the instrumentation key alone: anyone holding the connection string can send fake telemetry, and it can''t be traced to an identity.' 'Use Microsoft Entra ID authentication (managed identity with Monitoring Metrics Publisher) for server apps, then turn off local authentication. Browser (JavaScript) telemetry can''t use Entra ID: give it its own component.' }
        if ($ipMaskingOff) { & $find 'Medium' 'Security' 'Client IP addresses stored' 'IP masking is off: every client''s full IP address is kept with the telemetry - personal data under GDPR.' 'Set DisableIpMasking to false unless you have a documented reason (fraud, geo analysis) and the retention and access to match.' }
        if ($scoped -and $publicIngestion) { & $find 'Low' 'Security' 'Private link scope, but public ingestion still open' 'The component is in an Azure Monitor Private Link Scope, yet still accepts telemetry from the internet.' 'Once every sender uses the private endpoint, set public network access for ingestion to Disabled (keep it on for browser telemetry).' }
        if ($scoped -and $publicQuery) { & $find 'Low' 'Security' 'Private link scope, but public queries still open' 'The component is in an Azure Monitor Private Link Scope, yet its telemetry can be queried from any network.' 'Set public network access for queries to Disabled, so the data is read only through the private link.' }
        if ($writeKeys.Count) { & $find 'High' 'Security' 'API key that can write' "$($writeKeys.Count) API key(s) can write (annotations) - a shared secret with no owner or expiry." 'Delete them; use Microsoft Entra ID (Application Insights Component Contributor) for release annotations.' }
        elseif ($keys.Count) { & $find 'Medium' 'Security' 'API keys' "$($keys.Count) API key(s) can read the telemetry - shared secrets with no owner, no expiry and no audit of who used them." 'Move the callers (dashboards, scripts, Grafana) to Microsoft Entra ID - API key access is being retired - then delete the keys.' }

        # --- Identity and access ---------------------------------------------------------------------------------------
        $roles = & $answer 'Roles'
        $rolesRead = & $readOk $roles
        $assignments = @(foreach ($ra in (& $itemsOf $roles)) {
                $rp = & $at $ra 'properties'
                $guid = (([string](& $at $rp 'roleDefinitionId')) -split '/')[-1].ToLowerInvariant()
                $scopeText = ([string](& $at $rp 'scope')).ToLowerInvariant()
                $level = if ($scopeText -eq $id) { 'This component' } elseif ($scopeText -match '^/subscriptions/[^/]+/resourcegroups/[^/]+$') { 'Resource group' } elseif ($scopeText -match '^/subscriptions/[^/]+$') { 'Subscription' } elseif ($scopeText -like '/providers/microsoft.management/managementgroups/*') { 'Management group' } elseif ($scopeText -eq '/') { 'Root' } else { 'Other' }
                [pscustomobject][ordered]@{
                    PSTypeName    = 'AAC.ApplicationInsightAccess'
                    Component     = $name
                    Role          = $(if ($roleName.Contains($guid)) { $roleName[$guid] } else { "Custom or other ($guid)" })
                    PrincipalId   = [string](& $at $rp 'principalId')
                    PrincipalType = [string](& $at $rp 'principalType')
                    Level         = $level
                    Scope         = $scopeText
                    ResourceGroup = [string]$c['resourceGroup']
                    Subscription  = $subscription
                }
            })
        foreach ($a in $assignments) { $accessRows.Add($a) }
        $publishers = @($assignments | Where-Object Role -EQ 'Monitoring Metrics Publisher' | Select-Object -ExpandProperty PrincipalId -Unique).Count
        $writers = @($assignments | Where-Object { $_.Role -in $writerRoles } | Select-Object -ExpandProperty PrincipalId -Unique).Count
        $direct = @($assignments | Where-Object Level -EQ 'This component')
        $resourcePermissions = if ($ws) { & $isTrue $ws['resourcePermissions'] } else { $null }
        if ($rolesRead -and -not $localAuth -and -not $publishers) { & $find 'High' 'Identity & access' 'Local authentication off, but nothing may publish' 'Local authentication is off, so telemetry needs a Microsoft Entra ID identity with Monitoring Metrics Publisher - and none has it here or above.' 'Give the apps'' managed identities Monitoring Metrics Publisher on the component (and set the SDK''s credential), or telemetry is rejected.' }
        if ($rolesRead -and $localAuth -and $publishers) { & $find 'Low' 'Identity & access' 'Ready for Entra ID-only ingestion' "$publishers identity(ies) already have Monitoring Metrics Publisher, yet the instrumentation key alone still works." 'Check every sender uses its identity, then turn off local authentication.' }
        foreach ($a in @($direct | Where-Object { $_.Role -in $grantRoles })) { & $find 'Medium' 'Identity & access' "$($a.Role) granted on the component" "$($a.PrincipalType) $($a.PrincipalId) is $($a.Role) of this component: it can grant anyone access to the telemetry." 'Use Application Insights Component Contributor or Monitoring Contributor to manage it, and Monitoring Reader to read it; keep access-granting roles at the subscription, under PIM.' }
        $users = @($direct | Where-Object PrincipalType -EQ 'User')
        if ($users.Count) { & $find 'Low' 'Identity & access' 'Access granted to individual users' "$($users.Count) role assignment(s) on the component go to users, not groups." 'Grant roles to Entra ID groups (or PIM-eligible groups), so joiners and leavers are handled in one place.' }
        if ($writers -ge 15) { & $find 'Low' 'Identity & access' 'Many identities can change it' "$writers identities can change the component (Owner, Contributor or a monitoring contributor role, here or above)." 'Trim inherited write access, or use PIM: anyone with write can turn off sampling, the cap or local-auth protection, or delete it.' }
        if ($false -eq $resourcePermissions) { & $find 'Low' 'Identity & access' 'Workspace needs workspace-wide read' "Workspace $([string]$ws['name']) uses workspace permissions only: to read this app's telemetry, people need read on every table of the workspace." 'Set the workspace''s access control mode to "Use resource or workspace permissions", then grant Reader on the component (resource-context access).' }

        # --- Audit and lifecycle ------------------------------------------------------------------------------------
        $locked = @($lockScopes | Where-Object { $id -eq $_.Scope -or $id.StartsWith($_.Scope + '/') }).Count -gt 0
        $created = & $at $p 'CreationDate'
        $createdAt = if ($created) { try { ([datetime]$created).ToUniversalTime() } catch { $null } } else { $null }
        $tags = $c['tags']
        $hasOwner = $tags -is [System.Collections.IDictionary] -and @($tags.Keys | Where-Object { [string]$_ -match '^(owner|team|contact|costcent(er|re)|businessowner|technicalowner)$' }).Count -gt 0
        if (-not $locked) { & $find 'Low' 'Audit & lifecycle' 'No delete lock' 'No CanNotDelete or ReadOnly lock on the component, its resource group or subscription.' 'Add a CanNotDelete lock in production: a deleted component takes its availability tests and alert targets with it, and a new one has a new connection string every app must be redeployed with.' }
        if (-not $hasOwner) { & $find 'Low' 'Audit & lifecycle' 'No owner tag' 'Nothing on the component says who owns it.' 'Tag it with an owner or team, so alerts, access reviews and clean-up reach someone.' }
        $total = 0
        foreach ($n in @($requests, $dependencies, $exceptions, $traces)) { if ($null -ne $n) { $total += $n } }
        if ($metricsRead -and -not $total -and (-not $createdAt -or $createdAt -lt $PeriodStart)) { & $find 'Low' 'Audit & lifecycle' 'No telemetry in the period' "No request, dependency, exception or trace in the last $PeriodDays day(s)." 'Confirm an app still sends to it (a connection string left on an old slot or pipeline?); delete it if not - its tests and alerts cost money and attention.' }

        $mine = @(if ($null -ne $Activity) { $Activity | Where-Object { $_ } | Where-Object { $rid = ([string]$_['ResourceId']).ToLowerInvariant(); $rid -eq $id -or $rid.StartsWith("$id/") } })
        foreach ($op in $mine) {
            $person = [bool][string]$op['Upn']
            $changeRows.Add([pscustomobject][ordered]@{
                    PSTypeName    = 'AAC.ApplicationInsightChange'
                    Component     = $name
                    Operation     = [string]$op['Operation']
                    OperationName = [string]$op['OperationName']
                    Status        = [string]$op['Status']
                    Caller        = $(if ($person) { [string]$op['Upn'] } elseif ([string]$op['AppId']) { [string]$op['AppId'] } else { [string]$op['Caller'] })
                    CallerType    = $(if ($person) { 'Person' } else { 'App' })
                    Count         = [long]$op['Count']
                    First         = $op['First']
                    Last          = $op['Last']
                    ResourceGroup = [string]$c['resourceGroup']
                    Subscription  = $subscription
                })
        }
        $ofOperation = { param([string] $Pattern) @($mine | Where-Object { ([string]$_['Operation']) -match $Pattern -and [string]$_['Status'] -ne 'Failed' }) }
        $purges = @(& $ofOperation '(?i)/components/purge/action$')
        if ($purges.Count) { & $find 'Medium' 'Audit & lifecycle' 'Telemetry purged' "$(& $sumOf $purges 'Count') purge request(s), by $((@($purges | ForEach-Object { if ([string]$_['Upn']) { [string]$_['Upn'] } else { [string]$_['Caller'] } } | Select-Object -Unique)) -join ', ')." 'Confirm each purge was an approved data-subject (GDPR) request: purging deletes telemetry for good.' }
        $newKeys = @(& $ofOperation '(?i)/components/apikeys/write$')
        if ($newKeys.Count) { & $find 'Medium' 'Audit & lifecycle' 'API key created' "$(& $sumOf $newKeys 'Count') API key(s) created in the period." 'Find out who needs it and move them to Microsoft Entra ID; delete the key.' }
        $byHand = @($mine | Where-Object { [string]$_['Upn'] -and ([string]$_['Operation']) -match '(?i)/(write|delete)$' -and [string]$_['Status'] -ne 'Failed' })
        if ($byHand.Count) { & $find 'Low' 'Audit & lifecycle' 'Changed by hand' "$(& $sumOf $byHand 'Count') change(s) by people: $((@($byHand | ForEach-Object { [string]$_['Upn'] } | Select-Object -Unique)) -join ', ')." 'Make changes through infrastructure as code, so the sampling, cap and security settings don''t drift from what was reviewed.' }
        $failed = @($mine | Where-Object { [string]$_['Status'] -eq 'Failed' })
        if ($failed.Count) { & $find 'Low' 'Audit & lifecycle' 'Failed changes' "$(& $sumOf $failed 'Count') operation(s) failed: $((@($failed | ForEach-Object { [string]$_['Operation'] } | Select-Object -Unique)) -join ', ')." 'Look at the failures (Show-AACActivityLogEvent decodes them): a pipeline that keeps failing leaves the component out of step with its code.' }

        # --- Heat map ---------------------------------------------------------------------------------------------
        $penalty = @{ High = 40; Medium = 20; Low = 10 }
        $mineFindings = @($findings | Where-Object { $_.ResourceId -eq $id })
        $cells = @(foreach ($signal in $signals) {
                $lost = 0; foreach ($f in @($mineFindings | Where-Object Signal -EQ $signal)) { $lost += $penalty[$f.Severity] }
                @{ Score = [double][Math]::Max(0, 100 - $lost) }
            })
        $overall = [Math]::Round((@($cells | ForEach-Object { $_.Score }) | Measure-Object -Average).Average, 1)
        $heatRows.Add(@{ Label = $name; Filter = $name; Cells = $cells; Total = @{ Score = $overall }; Overall = $overall })

        $componentRows.Add([pscustomobject][ordered]@{
                PSTypeName         = 'AAC.ApplicationInsightAssessment'
                Component          = $name
                Score              = $overall
                AppType            = $appType
                Mode               = $(if ($classic) { 'Classic' } else { 'Workspace-based' })
                Workspace          = $(if ($ws) { [string]$ws['name'] } elseif ($workspaceId) { ($workspaceId -split '/')[-1] } else { '' })
                WorkspaceRegion    = $(if ($ws) { [string]$ws['location'] } else { '' })
                WorkspaceRetention = $(if ($ws -and $null -ne $ws['retentionInDays']) { [int]$ws['retentionInDays'] } else { $null })
                Requests           = $requests
                Dependencies       = $dependencies
                Exceptions         = $exceptions
                Traces             = $traces
                IngestedGB         = & $round $ingested 3
                GBPerDay           = & $round $perDay 3
                PeakDayGB          = & $round $peakDay 3
                RetainedPct        = $retained
                DailyCapGB         = $capGb
                WorkspaceCapGB     = $workspaceCap
                LocalAuth          = $(if ($localAuth) { 'Allowed' } else { 'Disabled' })
                IpMasking          = $(if ($ipMaskingOff) { 'Off' } else { 'On' })
                PublicIngestion    = $publicIngestion
                PublicQuery        = $publicQuery
                PrivateLinkScope   = $scoped
                ApiKeys            = $(if (& $readOk $apiKeys) { $keys.Count } else { $null })
                AvailabilityTests  = $enabledTests.Count
                AlertRules         = $enabledRules.Count
                SmartDetection     = $smartDetection
                Publishers         = $(if ($rolesRead) { $publishers } else { $null })
                Writers            = $(if ($rolesRead) { $writers } else { $null })
                DirectAssignments  = $(if ($rolesRead) { $direct.Count } else { $null })
                Lock               = $locked
                Changes            = $(if ($null -ne $Activity) { [long](& $sumOf $mine 'Count') } else { $null })
                Findings           = $mineFindings.Count
                Created            = $createdAt
                Location           = [string]$c['location']
                ResourceGroup      = [string]$c['resourceGroup']
                Subscription       = $subscription
                MetricsError       = $(if ($telemetry -and $telemetry.Error) { [string]$telemetry.Error } else { '' })
                ResourceId         = $id
            })
    }

    $rank = @{ High = 0; Medium = 1; Low = 2; Info = 3 }
    $worst = @($heatRows | Sort-Object -Property @{ Expression = { $_.Overall } }, Label | Select-Object -First 40)
    $rows = $componentRows.ToArray()
    @{
        Components = $rows
        Ingestion  = $ingestionRows.ToArray()
        Access     = @($accessRows | Sort-Object -Property Component, @{ Expression = { @{ 'This component' = 0; 'Resource group' = 1; Subscription = 2; 'Management group' = 3; Root = 4; Other = 5 }[$_.Level] } }, Role)
        Changes    = @($changeRows | Sort-Object -Property @{ Expression = 'Last'; Descending = $true }, Component)
        Findings   = @($findings | Sort-Object -Property @{ Expression = { $rank[$_.Severity] } }, Component, Signal, Finding)
        HeatMap    = @{ Title = 'Application Insights by signal'; RowHeader = 'Component'; Columns = $signals; Rows = $worst; Table = 'findings'; RowKey = 'Component'; ColumnKey = 'Signal'; ConsoleColumns = 5
            Note = "0-100 per signal, worst components first$(if ($heatRows.Count -gt 40) { " (40 of $($heatRows.Count))" }): ingestion and cost, workspace and architecture, security, identity and access, audit and lifecycle. Click a cell for its findings." }
        Stats      = @{
            Components = $rows.Count
            Classic    = @($rows | Where-Object Mode -EQ 'Classic').Count
            LocalAuth  = @($rows | Where-Object LocalAuth -EQ 'Allowed').Count
            NoAlerts   = @($rows | Where-Object { -not $_.AlertRules }).Count
            GBPerDay   = [Math]::Round((& $sumOf $rows 'GBPerDay'), 2)
            High       = @($findings | Where-Object Severity -EQ 'High').Count
        }
    }
}
