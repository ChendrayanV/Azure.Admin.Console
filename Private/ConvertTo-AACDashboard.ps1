function ConvertTo-AACDashboard {
    <#
    .SYNOPSIS
        Turns Show-AACDashboard's Resource Graph reads into one AAC.Dashboard
        object: the session, the scope, the estate, its health, Advisor and
        the recent changes - with an overall status.
    .DESCRIPTION
        Status, the dashboard's headline:
          Failed   resources are unavailable, or an Azure service issue is
                   active in these subscriptions
          Warning  resources are degraded, Advisor has High-impact
                   recommendations, planned maintenance or an advisory is
                   active, or something couldn't be read
          Success  none of these
        Unread names what couldn't be read, and why.
    #>
    [CmdletBinding()]
    [OutputType('AAC.Dashboard')]
    param(
        # Invoke-AACGraphBatch's result: @{ Rows; Errors }.
        [Parameter(Mandatory)]
        [hashtable] $Read,

        # The subscriptions in scope (Resource Graph rows: subscriptionId, name, state).
        [object[]] $Subscription = @(),

        [int] $Hours = 24,

        $Session,

        [datetime] $Now = [datetime]::Now
    )

    $value = { param($Row, [string] $Name) if ($Row -is [System.Collections.IDictionary]) { $Row[$Name] } elseif ($null -ne $Row -and $Row.PSObject.Properties[$Name]) { $Row.PSObject.Properties[$Name].Value } }
    $rows = { param([string] $Name) @(if ($Read.Rows -and $Read.Rows.Contains($Name)) { $Read.Rows[$Name] | Where-Object { $null -ne $_ } }) }
    $leaf = { param($Id) ([string]$Id).TrimEnd('/') -replace '^.*/', '' }
    $groupOf = { param($Id) if ([string]$Id -match '(?i)/resourceGroups/([^/]+)') { $Matches[1] } else { '' } }
    $nameOf = @{}
    foreach ($s in $Subscription) { $nameOf[([string](& $value $s 'subscriptionId')).ToLowerInvariant()] = [string](& $value $s 'name') }
    $subscriptionLabel = { param($Id) $key = ([string]$Id).ToLowerInvariant(); if ($nameOf.Contains($key)) { $nameOf[$key] } else { [string]$Id } }
    $time = {
        # Resource Graph dates come as ISO text, or (Service Health) as Unix seconds.
        param($Text)
        $t = [string]$Text
        $parsed = [datetime]::MinValue
        if ($t -match '^\d{9,11}$') { [DateTimeOffset]::FromUnixTimeSeconds([long]$t).LocalDateTime }
        elseif ($t -and [datetime]::TryParse($t, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)) { $parsed.ToLocalTime() }
        else { $null }
    }

    $totals = @(& $rows 'totals') | Select-Object -First 1
    $health = [ordered]@{ Available = 0; Unavailable = 0; Degraded = 0; Unknown = 0 }
    foreach ($row in (& $rows 'health')) {
        $state = [string](& $value $row 'state')
        $key = @($health.Keys | Where-Object { $_ -eq $state })[0]
        if (-not $key) { $key = 'Unknown' }
        $health[$key] += [int](& $value $row 'resources')
    }
    $eventTypes = @{ ServiceIssue = 'Service issue'; PlannedMaintenance = 'Planned maintenance'; HealthAdvisory = 'Health advisory'; SecurityAdvisory = 'Security advisory' }
    $issues = @(foreach ($row in (& $rows 'serviceIssues')) {
            $type = [string](& $value $row 'eventType')
            [pscustomobject][ordered]@{
                PSTypeName   = 'AAC.DashboardServiceEvent'
                Type         = $(if ($eventTypes.Contains($type)) { $eventTypes[$type] } else { $type })
                Title        = [string](& $value $row 'title')
                TrackingId   = [string](& $value $row 'trackingId')
                Level        = [string](& $value $row 'level')
                Started      = & $time (& $value $row 'started')
                Subscription = & $subscriptionLabel (& $value $row 'subscriptionId')
            }
        })
    # The same event in several subscriptions: once, with each subscription.
    $issues = @($issues | Group-Object -Property TrackingId | ForEach-Object {
            $first = $_.Group[0]
            $first.Subscription = (@($_.Group.Subscription) | Select-Object -Unique) -join ', '
            $first
        } | Sort-Object -Property @{ Expression = { @{ 'Service issue' = 0; 'Security advisory' = 1; 'Planned maintenance' = 2 }[$_.Type] } }, Started)
    $unhealthy = @(@(foreach ($row in (& $rows 'unhealthy')) {
            $id = [string](& $value $row 'resourceId')
            [pscustomobject][ordered]@{
                PSTypeName    = 'AAC.DashboardUnhealthyResource'
                Resource      = & $leaf $id
                State         = [string](& $value $row 'state')
                Summary       = [string](& $value $row 'summary')
                Reason        = [string](& $value $row 'reason')
                Since         = & $time (& $value $row 'since')
                ResourceGroup = & $groupOf $id
                ResourceId    = $id
            }
        }) | Sort-Object -Property @{ Expression = { if ($_.State -eq 'Unavailable') { 0 } else { 1 } } }, Resource)
    $advisor = @(@(foreach ($group in @(& $rows 'advisor') | Group-Object -Property { [string](& $value $_ 'category') }) {
            $count = { param([string] $Impact) [int](@($group.Group | Where-Object { [string](& $value $_ 'impact') -eq $Impact } | ForEach-Object { [int](& $value $_ 'recommendations') }) | Measure-Object -Sum).Sum }
            [pscustomobject][ordered]@{
                PSTypeName = 'AAC.DashboardAdvisor'
                Category   = @{ HighAvailability = 'Reliability'; OperationalExcellence = 'Operational excellence' }[$group.Name] ?? $group.Name
                High       = & $count 'High'
                Medium     = & $count 'Medium'
                Low        = & $count 'Low'
            }
        }) | Sort-Object -Property @{ Expression = 'High'; Descending = $true }, Category)
    $changeCount = @{ Create = 0; Update = 0; Delete = 0 }
    foreach ($row in (& $rows 'changes')) { $kind = [string](& $value $row 'changeType'); if ($changeCount.Contains($kind)) { $changeCount[$kind] += [int](& $value $row 'changes') } }
    $recent = @(foreach ($row in (& $rows 'recentChanges')) {
            $id = [string](& $value $row 'resourceId')
            [pscustomobject][ordered]@{
                PSTypeName    = 'AAC.DashboardChange'
                Time          = & $time (& $value $row 'at')
                Change        = [string](& $value $row 'changeType')
                Resource      = & $leaf $id
                ResourceType  = ([string](& $value $row 'resourceType')).ToLowerInvariant()
                ResourceGroup = & $groupOf $id
                ChangedBy     = [string](& $value $row 'changedBy')
                Operation     = [string](& $value $row 'operation')
                ResourceId    = $id
            }
        })
    $labels = @{ totals = 'the resource totals'; regions = 'the regions'; health = 'Resource Health'; unhealthy = 'the unhealthy resources'; serviceIssues = 'Service Health'; advisor = 'Azure Advisor'; changes = 'the resource changes'; recentChanges = 'the recent changes' }
    $unread = [ordered]@{}
    foreach ($key in @($Read.Errors.Keys | Sort-Object)) { if ($Read.Errors[$key]) { $unread[$(if ($labels.Contains($key)) { $labels[$key] } else { $key })] = [string]$Read.Errors[$key] } }

    # The headline.
    $activeIssues = @($issues | Where-Object Type -EQ 'Service issue').Count
    $advisorHigh = [int](@($advisor | ForEach-Object { $_.High }) | Measure-Object -Sum).Sum
    $reasons = [System.Collections.Generic.List[string]]::new()
    if ($health.Unavailable) { $reasons.Add("$($health.Unavailable) resource(s) unavailable") }
    if ($activeIssues) { $reasons.Add("$activeIssues active Azure service issue(s)") }
    if ($health.Degraded) { $reasons.Add("$($health.Degraded) resource(s) degraded") }
    $otherEvents = @($issues | Where-Object Type -NE 'Service issue').Count
    if ($otherEvents) { $reasons.Add("$otherEvents planned maintenance or advisory event(s)") }
    if ($advisorHigh) { $reasons.Add("$advisorHigh High-impact Advisor recommendation(s)") }
    if ($unread.Count) { $reasons.Add("$($unread.Count) source(s) not read") }
    $status = if ($health.Unavailable -or $activeIssues) { 'Failed' } elseif ($reasons.Count) { 'Warning' } else { 'Success' }

    $subscriptions = @(foreach ($s in $Subscription | Sort-Object -Property { [string](& $value $_ 'name') }) {
            [pscustomobject][ordered]@{ PSTypeName = 'AAC.DashboardSubscription'; Name = [string](& $value $s 'name'); State = [string](& $value $s 'state'); SubscriptionId = [string](& $value $s 'subscriptionId') }
        })
    [pscustomobject][ordered]@{
        PSTypeName         = 'AAC.Dashboard'
        Status             = $status
        Headline           = $(if ($reasons.Count) { $reasons -join '; ' } else { 'Every resource Resource Health reports on is available, and no Azure service issue is active.' })
        Account            = $(if ($Session) { [string]$Session.Account } else { '' })
        TenantId           = $(if ($Session) { [string]$Session.TenantId } else { '' })
        SignIn             = $(if ($Session -and $Session.PSObject.Properties['Flow']) { [string]$Session.Flow } else { '' })
        TokenExpiresOn     = $(if ($Session -and $Session.PSObject.Properties['ExpiresOn']) { $Session.ExpiresOn } else { $null })
        Subscriptions      = $subscriptions
        Resources          = [int](& $value $totals 'resources')
        ResourceTypes      = [int](& $value $totals 'types')
        ResourceGroups     = [int](& $value $totals 'groups')
        Regions            = [int](& $value $totals 'regions')
        TopRegions         = @(& $rows 'regions' | ForEach-Object { [pscustomobject]@{ Region = $(if ((& $value $_ 'location')) { [string](& $value $_ 'location') } else { '(global)' }); Resources = [int](& $value $_ 'resources') } })
        Health             = [pscustomobject]$health
        UnhealthyResources = $unhealthy
        ServiceEvents      = $issues
        Advisor            = $advisor
        AdvisorHigh        = $advisorHigh
        Hours              = $Hours
        Changes            = [pscustomobject][ordered]@{ Created = $changeCount.Create; Updated = $changeCount.Update; Deleted = $changeCount.Delete }
        RecentChanges      = $recent
        Unread             = [pscustomobject]$unread
        GeneratedAt        = $Now
    }
}
