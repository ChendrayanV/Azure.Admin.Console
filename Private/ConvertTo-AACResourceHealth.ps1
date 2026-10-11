function ConvertTo-AACResourceHealth {
    <#
    .SYNOPSIS
        Builds Get-AACResourceHealth's model from the Resource Graph rows of
        Get-AACResourceHealthQuery (and, with -History, each resource's
        Resource Health history): every resource's availability, why and
        since when, its latest health event and the Service Health events
        that hit it - and the Service Health events themselves.
    .DESCRIPTION
        No Azure calls. -Read is Invoke-AACGraphBatch's result; -History maps
        a resource ID (lower case) to the availabilityStatuses Resource
        Health returned for it (newest first), from which its availability
        over the last -Days and its state changes are worked out. Rows of
        subscriptions not in -SubscriptionName are left out.

        Resources (AAC.ResourceHealth): Unavailable, then Degraded, Unknown
        and Available, the longest-down first. Service Health events
        (AAC.ServiceHealthEvent): active first, then outages, maintenance,
        advisories - with the regions and services they name and the
        resources in scope they hit.

        Returns @{ Resources; Events; Notices; Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Read,

        [hashtable] $SubscriptionName = @{},

        [hashtable] $History = @{},

        [ValidateRange(1, 90)]
        [int] $Days = 7,

        [datetime] $Now = [datetime]::UtcNow
    )

    $get = ${function:Get-AACMember}
    $text = { param($Object, [string] $Key) $v = & $get $Object $Key; if ($null -eq $v) { '' } else { [string]$v } }
    $rowsOf = { param([string] $Name) @(if ($Read.Rows -and $Read.Rows.Contains($Name)) { $Read.Rows[$Name] | Where-Object { $null -ne $_ } }) }
    $subscriptionOf = { param([string] $Id) if ($Id -match '^/subscriptions/([^/]+)') { $Matches[1].ToLowerInvariant() } else { '' } }
    $label = { param([string] $Id) $s = ([string]$Id).ToLowerInvariant(); if ($SubscriptionName.Contains($s)) { $SubscriptionName[$s] } else { $Id } }
    $date = {
        param([string] $Value)
        $d = [datetime]::MinValue
        if ($Value -and [datetime]::TryParse($Value, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$d)) { $d } else { $null }
    }
    $plain = {
        param([string] $Html)
        if (-not $Html) { return '' }
        $t = $Html -replace '(?i)<br\s*/?>|</p>|</li>', "`n" -replace '(?i)<li[^>]*>', '- ' -replace '<[^>]+>', ''
        ([System.Net.WebUtility]::HtmlDecode($t).Replace([char]0x00A0, ' ') -replace '[ \t]+\n', "`n" -replace '\n{3,}', "`n`n").Trim()
    }
    $parse = {
        param([string] $Id)
        $r = @{ Name = ''; Type = ''; Group = '' }
        if (-not $Id) { return $r }
        $parts = $Id.Trim('/').Split('/')
        $lower = @($parts | ForEach-Object { $_.ToLowerInvariant() })
        $g = [array]::IndexOf($lower, 'resourcegroups')
        if ($g -ge 0 -and $g + 1 -lt $parts.Count) { $r.Group = $parts[$g + 1] }
        $p = [array]::LastIndexOf($lower, 'providers')
        if ($p -ge 0 -and $p + 2 -lt $parts.Count) { $r.Type = ($lower[$p + 1] + '/' + (@(for ($j = $p + 2; $j -lt $parts.Count; $j += 2) { $lower[$j] }) -join '/')) }
        $r.Name = $parts[-1]
        $r
    }
    $notices = [System.Collections.Generic.List[string]]::new()
    foreach ($key in @($Read.Errors.Keys | Sort-Object)) { $notices.Add("The $(@{ statuses = 'Resource Health statuses'; events = 'resource health events'; service = 'Service Health events'; impacted = 'resources impacted by Service Health events' }[$key]) couldn't be read: $($Read.Errors[$key] -replace '\s+', ' ')") }

    # --- Service Health events, and what they hit -----------------------------------------------------------------
    $hits = @{}       # resource ID -> tracking IDs
    $hitCount = @{}   # tracking ID -> resources in scope
    foreach ($row in (& $rowsOf 'impacted')) {
        $id = & $text $row 'resourceId'; $tracking = & $text $row 'trackingId'
        if (-not $id -or -not $tracking -or -not $SubscriptionName.Contains((& $subscriptionOf $id))) { continue }
        if (-not $hits.Contains($id)) { $hits[$id] = [System.Collections.Generic.List[string]]::new() }
        if (-not $hits[$id].Contains($tracking)) { $hits[$id].Add($tracking); $hitCount[$tracking] = 1 + [int]$hitCount[$tracking] }
    }
    $typeOrder = @{ ServiceIssue = 0; PlannedMaintenance = 1; SecurityAdvisory = 2; HealthAdvisory = 3 }
    $typeName = @{ ServiceIssue = 'Service issue'; PlannedMaintenance = 'Planned maintenance'; HealthAdvisory = 'Health advisory'; SecurityAdvisory = 'Security advisory'; Billing = 'Billing' }
    $events = @(foreach ($group in @(& $rowsOf 'service' | Where-Object { $SubscriptionName.Contains((& $text $_ 'subscriptionId').ToLowerInvariant()) } | Group-Object { & $text $_ 'trackingId' })) {
            $row = $group.Group[0]
            $kind = & $text $row 'eventType'
            $impact = @(@(& $get $row 'impact') | Where-Object { $_ -is [System.Collections.IDictionary] })
            [pscustomobject][ordered]@{
                PSTypeName        = 'AAC.ServiceHealthEvent'
                TrackingId        = $group.Name
                EventType         = $(if ($typeName.Contains($kind)) { $typeName[$kind] } else { $kind })
                Status            = & $text $row 'status'
                Level             = & $text $row 'level'
                Title             = & $text $row 'heading'
                Services          = (@($impact | ForEach-Object { & $text $_ 'ImpactedService' } | Where-Object { $_ } | Select-Object -Unique) -join ', ')
                Regions           = (@($impact | ForEach-Object { @(& $get $_ 'ImpactedRegions') } | ForEach-Object { & $text $_ 'ImpactedRegion' } | Where-Object { $_ } | Select-Object -Unique) -join ', ')
                Subscriptions     = (@($group.Group | ForEach-Object { & $label (& $text $_ 'subscriptionId') } | Select-Object -Unique) -join ', ')
                ImpactedResources = [int]$hitCount[$group.Name]
                Started           = & $date (& $text $row 'started')
                Mitigated         = & $date (& $text $row 'mitigated')
                LastUpdate        = & $date (& $text $row 'updated')
                Summary           = & $plain (& $text $row 'summary')
                Link              = "https://app.azure.com/h/$($group.Name)"
                Order             = $(if ($typeOrder.Contains($kind)) { $typeOrder[$kind] } else { 9 })
            }
        })
    $events = @($events | Sort-Object -Property @{ Expression = { if ($_.Status -eq 'Active') { 0 } else { 1 } } }, Order, @{ Expression = 'LastUpdate'; Descending = $true } | Select-Object -Property * -ExcludeProperty Order)
    foreach ($e in $events) { $e.PSObject.TypeNames.Insert(0, 'AAC.ServiceHealthEvent') }

    # --- Latest health event per resource -------------------------------------------------------------------------
    $latest = @{}
    foreach ($row in (& $rowsOf 'events')) {
        $when = & $date (& $text $row 'occurred')
        if (-not $when -or $when -lt $Now.AddDays(-$Days)) { continue }
        $latest[(& $text $row 'resourceId')] = @{ When = $when; Name = (& $text $row 'annotation'); Summary = (& $plain (& $text $row 'summary')); Context = (& $text $row 'context') }
    }

    # --- Availability over the window, from the history -----------------------------------------------------------
    $windowStart = $Now.AddDays(-$Days)
    $availabilityOf = {
        param([object[]] $Statuses)
        $points = @($Statuses | ForEach-Object { @{ When = (& $date ([string](@((& $text $_ 'properties.occuredTime'), (& $text $_ 'properties.occurredTime')) | Where-Object { $_ } | Select-Object -First 1))); State = (& $text $_ 'properties.availabilityState') } } | Where-Object { $_.When } | Sort-Object { $_.When })
        if (-not $points.Count) { return $null }
        $up = 0.0; $known = 0.0; $changes = 0
        for ($i = 0; $i -lt $points.Count; $i++) {
            $from = if ($points[$i].When -lt $windowStart) { $windowStart } else { $points[$i].When }
            $to = if ($i + 1 -lt $points.Count) { $points[$i + 1].When } else { $Now }
            if ($to -le $windowStart) { continue }
            if ($points[$i].When -ge $windowStart -and $i -gt 0 -and $points[$i].State -ne $points[$i - 1].State) { $changes++ }
            $span = ($to - $from).TotalSeconds
            if ($points[$i].State -eq 'Unknown') { continue }
            $known += $span
            if ($points[$i].State -eq 'Available') { $up += $span }
        }
        @{ Percent = $(if ($known -gt 0) { [Math]::Round(100 * $up / $known, 2) } else { $null }); Changes = $changes }
    }

    # --- Resources ---------------------------------------------------------------------------------------------------
    $stateOrder = @{ Unavailable = 0; Degraded = 1; Unknown = 2; Available = 3 }
    $resources = @(foreach ($row in (& $rowsOf 'statuses')) {
            $id = & $text $row 'resourceId'
            $subscription = & $subscriptionOf $id
            if (-not $subscription) { $subscription = (& $text $row 'subscriptionId').ToLowerInvariant() }
            if (-not $SubscriptionName.Contains($subscription)) { continue }
            $where = & $parse $id
            $state = & $text $row 'state'
            $since = & $date (& $text $row 'since')
            $annotation = if ($latest.Contains($id)) { $latest[$id] } else { $null }
            $measured = if ($History.Contains($id)) { & $availabilityOf @($History[$id]) } else { $null }
            [pscustomobject][ordered]@{
                PSTypeName       = 'AAC.ResourceHealth'
                State            = $(if ($state) { $state } else { 'Unknown' })
                Resource         = $where.Name
                ResourceType     = $where.Type
                ResourceGroup    = $where.Group
                Subscription     = & $label $subscription
                Reason           = & $text $row 'reason'
                Title            = & $text $row 'heading'
                Summary          = & $plain (& $text $row 'summary')
                Since            = $since
                Hours            = $(if ($since -and $state -ne 'Available') { [Math]::Round(($Now - $since).TotalHours, 1) } else { $null })
                Chronicity       = & $text $row 'chronicity'
                ResolutionEta    = & $date (& $text $row 'eta')
                LastEvent        = $(if ($annotation) { $annotation.Name } else { '' })
                LastEventTime    = $(if ($annotation) { $annotation.When } else { $null })
                LastEventSummary = $(if ($annotation) { $annotation.Summary } else { '' })
                LastEventContext = $(if ($annotation) { $annotation.Context } else { '' })
                ServiceIssues    = $(if ($hits.Contains($id)) { $hits[$id] -join ', ' } else { '' })
                Availability     = $(if ($measured) { $measured.Percent } else { $null })
                StateChanges     = $(if ($measured) { $measured.Changes } else { $null })
                Location         = & $text $row 'location'
                SubscriptionId   = $subscription
                ResourceId       = $id
            }
        })
    $resources = @($resources | Sort-Object -Property @{ Expression = { if ($stateOrder.Contains($_.State)) { $stateOrder[$_.State] } else { 2 } } }, @{ Expression = { if ($null -ne $_.Hours) { $_.Hours } else { 0 } }; Descending = $true }, Resource)

    $activeIssues = @($events | Where-Object { $_.Status -eq 'Active' -and $_.EventType -eq 'Service issue' })
    @{
        Resources = $resources
        Events    = $events
        Notices   = @($notices)
        Stats     = @{
            Resources    = $resources.Count
            Unavailable  = @($resources | Where-Object State -EQ 'Unavailable').Count
            Degraded     = @($resources | Where-Object State -EQ 'Degraded').Count
            Unknown      = @($resources | Where-Object State -EQ 'Unknown').Count
            Available    = @($resources | Where-Object State -EQ 'Available').Count
            ActiveIssues = $activeIssues.Count
            Maintenance  = @($events | Where-Object { $_.Status -eq 'Active' -and $_.EventType -eq 'Planned maintenance' }).Count
            Events       = $events.Count
            Recent       = @($resources | Where-Object LastEvent).Count
        }
    }
}
