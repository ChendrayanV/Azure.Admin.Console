function ConvertTo-AACDashboard {
    <#
    .SYNOPSIS
        Turns Show-AACDashboard's Resource Graph reads into one AAC.Dashboard
        object: the session, the scope, the estate, its health, security,
        policy, governance, Advisor, the recent changes and (with -Cost) the
        spend - with an overall status, an Estate score and what to do next.
    .DESCRIPTION
        Status, the dashboard's headline:
          Failed   resources are unavailable, or an Azure service issue is
                   active in these subscriptions
          Warning  resources are degraded, Advisor has High-impact
                   recommendations, planned maintenance or an advisory is
                   active, or something couldn't be read
          Success  none of these
        Warning also when there are high-severity security alerts, policy
        compliance is below 80%, a subscription is at 80% of the role
        assignment limit, or spend is more than 10% above last month.

        Score (0-100, or none when nothing it is made of was read): the
        average of the parts that were read - Health (the share of
        resources available), Security (the secure score), Policy (the share
        of resources compliant) and Advisor (the Advisor score) - less 5
        when a subscription is at 95% of the role assignment limit (2 at
        80%), and less 3 when spend is more than 20% above last month.

        Actions: what to do, ranked High, Medium, Low across every section,
        each with the command that goes deeper.
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

        # Read-AACDashboardCost's result (-IncludeCost), or $null.
        [hashtable] $Cost,

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
    $labels = @{ totals = 'the resource totals'; regions = 'the regions'; health = 'Resource Health'; unhealthy = 'the unhealthy resources'; serviceIssues = 'Service Health'; advisor = 'Azure Advisor'; changes = 'the resource changes'; recentChanges = 'the recent changes'
        types = 'the resource types'; bySubscription = 'the resources per subscription'; tagged = 'the tags'; secureScore = 'the secure score'; alerts = 'the security alerts'; recommendations = 'the security recommendations'; defenderPlans = 'the Defender plans'
        policy = 'Azure Policy compliance'; policyTop = 'the non-compliant assignments'; advisorScore = 'the Advisor score'; advisorSavings = 'the Advisor savings'; unused = 'the unused resources'; roleAssignments = 'the role assignments'; privileged = 'the privileged role assignments'; changeDays = 'the change timeline'; changers = 'who made the changes' }
    $unread = [ordered]@{}
    foreach ($key in @($Read.Errors.Keys | Sort-Object)) { if ($Read.Errors[$key]) { $unread[$(if ($labels.Contains($key)) { $labels[$key] } else { $key })] = [string]$Read.Errors[$key] } }

    # --- Estate: types, subscriptions, tags ----------------------------------------------------------------------
    $readOk = { param([string] $Name) $Read.Rows -and $Read.Rows.Contains($Name) -and -not ($Read.Errors -and $Read.Errors.Contains($Name) -and $Read.Errors[$Name]) }
    # NaN or infinity (Resource Graph's avg() over no rows is NaN) counts as nothing, never as a number.
    $finite = { param($Row, [string] $Name) $v = & $value $Row $Name; $d = 0.0; if ($null -ne $v -and '' -ne $v -and [double]::TryParse([string]$v, [System.Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref]$d) -and -not [double]::IsNaN($d) -and -not [double]::IsInfinity($d)) { $d } else { $null } }
    $number = { param($Row, [string] $Name) $n = & $finite $Row $Name; if ($null -eq $n) { 0 } else { $n } }
    $typeLabel = { param([string] $Type) (($Type -split '/')[-1] -creplace '([a-z])([A-Z])', '$1 $2') }
    $topTypes = @(& $rows 'types' | ForEach-Object { [pscustomobject]@{ Type = [string](& $value $_ 'type'); Name = (& $typeLabel ([string](& $value $_ 'type'))); Resources = [int](& $number $_ 'resources') } })
    $bySubscription = @(& $rows 'bySubscription' | ForEach-Object { [pscustomobject]@{ Subscription = (& $subscriptionLabel (& $value $_ 'subscriptionId')); Resources = [int](& $number $_ 'resources') } } | Sort-Object Resources -Descending)
    $taggedRow = @(& $rows 'tagged') | Select-Object -First 1
    $tagCoverage = if ($taggedRow -and (& $number $taggedRow 'total') -gt 0) { [Math]::Round(100.0 * (& $number $taggedRow 'tagged') / (& $number $taggedRow 'total'), 1) } else { $null }

    # --- Security --------------------------------------------------------------------------------------------------
    $scoreRow = @(& $rows 'secureScore') | Select-Object -First 1
    $secureScore = if ($scoreRow -and (& $number $scoreRow 'max') -gt 0) { [Math]::Round(100.0 * (& $number $scoreRow 'current') / (& $number $scoreRow 'max'), 0) } else { $null }
    $bySeverity = {
        param([string] $Name, [string] $Column)
        $o = [ordered]@{ High = 0; Medium = 0; Low = 0 }
        foreach ($row in (& $rows $Name)) { $sev = [string](& $value $row 'severity'); $key = @($o.Keys | Where-Object { $_ -eq $sev })[0]; if ($key) { $o[$key] += [int](& $number $row $Column) } }
        [pscustomobject]$o
    }
    $plansRow = @(& $rows 'defenderPlans') | Select-Object -First 1
    $security = [pscustomobject][ordered]@{
        SecureScore     = $secureScore
        Alerts          = (& $bySeverity 'alerts' 'alerts')
        Recommendations = (& $bySeverity 'recommendations' 'recommendations')
        DefenderPlans   = $(if ($plansRow -and (& $number $plansRow 'total') -gt 0) { "$([int](& $number $plansRow 'on')) of $([int](& $number $plansRow 'total'))" } else { '' })
        Read            = (& $readOk 'secureScore') -or (& $readOk 'alerts')
    }

    # --- Policy ------------------------------------------------------------------------------------------------------
    $policyRow = @(& $rows 'policy') | Select-Object -First 1
    $nonCompliant = [int](& $number $policyRow 'nonCompliant')
    $compliant = [int](& $number $policyRow 'compliant')
    $policy = [pscustomobject][ordered]@{
        Compliance   = $(if ($policyRow -and ($nonCompliant + $compliant) -gt 0) { [Math]::Round(100.0 * $compliant / ($nonCompliant + $compliant), 1) } else { $null })
        NonCompliant = $nonCompliant
        Compliant    = $compliant
        Top          = @(& $rows 'policyTop' | ForEach-Object { [pscustomobject]@{ Assignment = [string](& $value $_ 'assignment'); Scope = ([string](& $value $_ 'scope') -split '/')[-1]; Resources = [int](& $number $_ 'resources') } })
    }

    # --- Governance: limits, privileged access, unused resources --------------------------------------------------------
    $inScope = @{}; foreach ($s in $Subscription) { $inScope[([string](& $value $s 'subscriptionId')).ToLowerInvariant()] = $true }
    $closest = @(& $rows 'roleAssignments' | Where-Object { $inScope.Contains(([string](& $value $_ 'subscriptionId')).ToLowerInvariant()) } | Sort-Object { & $number $_ 'used' } -Descending) | Select-Object -First 1
    $limit = if ($closest) { $used = [int](& $number $closest 'used'); [pscustomobject][ordered]@{ Limit = 'Role assignments'; Scope = (& $subscriptionLabel (& $value $closest 'subscriptionId')); Used = $used; Maximum = 4000; Percent = [Math]::Round(100.0 * $used / 4000, 1) } } else { $null }
    $privilegedRows = @(& $rows 'privileged' | Where-Object { $sub = ([string](& $value $_ 'subscriptionId')).ToLowerInvariant(); -not $sub -or $inScope.Contains($sub) })
    $privilegedBy = [ordered]@{}
    foreach ($row in $privilegedRows) { $t = [string](& $value $row 'principalType'); if (-not $t) { $t = 'Unknown' }; $privilegedBy[$t] = [int]$(if ($privilegedBy.Contains($t)) { $privilegedBy[$t] } else { 0 }) + [int](& $number $row 'assignments') }
    $privilegedTotal = 0; foreach ($k in $privilegedBy.Keys) { $privilegedTotal += $privilegedBy[$k] }
    $unusedRows = @(& $rows 'unused')
    $unusedTotal = 0; foreach ($row in $unusedRows) { $unusedTotal += [int](& $number $row 'resources') }
    $governance = [pscustomobject][ordered]@{
        ClosestLimit          = $limit
        PrivilegedAssignments = $privilegedTotal
        PrivilegedByType      = [pscustomobject]$privilegedBy
        Unused                = $unusedTotal
        UnusedByType          = @($unusedRows | ForEach-Object { [pscustomobject]@{ Type = (& $typeLabel ([string](& $value $_ 'type'))); Resources = [int](& $number $_ 'resources') } })
        TagCoverage           = $tagCoverage
    }

    # --- Advisor score and savings --------------------------------------------------------------------------------------
    $advisorScoreRow = @(& $rows 'advisorScore') | Select-Object -First 1
    $advisorScoreValue = if ($advisorScoreRow) { & $finite $advisorScoreRow 'score' } else { $null }
    $advisorScore = if ($null -ne $advisorScoreValue) { [Math]::Round($advisorScoreValue, 0) } else { $null }
    $savingsRow = @(& $rows 'advisorSavings' | Sort-Object { & $number $_ 'savings' } -Descending) | Select-Object -First 1
    $advisorSavings = if ($savingsRow -and (& $number $savingsRow 'savings') -gt 0) { [pscustomobject]@{ Annual = [Math]::Round((& $number $savingsRow 'savings'), 0); Currency = [string](& $value $savingsRow 'currency'); Recommendations = [int](& $number $savingsRow 'recommendations') } } else { $null }

    # --- The change timeline and who made the changes ---------------------------------------------------------------------
    $timelineDays = [ordered]@{}
    for ($i = 13; $i -ge 0; $i--) { $timelineDays[$Now.Date.AddDays(-$i).ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture)] = @{ Create = 0; Update = 0; Delete = 0 } }
    foreach ($row in (& $rows 'changeDays')) {
        $day = [string](& $value $row 'day'); $kind = [string](& $value $row 'changeType')
        if ($timelineDays.Contains($day) -and $timelineDays[$day].Contains($kind)) { $timelineDays[$day][$kind] += [int](& $number $row 'changes') }
    }
    $timeline = @(foreach ($day in $timelineDays.Keys) { [pscustomobject][ordered]@{ Day = [datetime]::ParseExact($day, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture); Created = $timelineDays[$day].Create; Updated = $timelineDays[$day].Update; Deleted = $timelineDays[$day].Delete } })
    $changers = @(& $rows 'changers' | ForEach-Object { [pscustomobject]@{ ChangedBy = $(if ((& $value $_ 'changedBy')) { [string](& $value $_ 'changedBy') } else { '(unknown)' }); Changes = [int](& $number $_ 'changes'); Deletes = [int](& $number $_ 'deletes') } })

    # --- Cost (-IncludeCost) ------------------------------------------------------------------------------------------------
    $costCard = $null
    if ($Cost) {
        $costCard = [pscustomobject][ordered]@{
            MonthToDate     = $Cost.MonthToDate
            LastMonthToDate = $Cost.LastMonthToDate
            LastMonth       = $Cost.LastMonth
            Forecast        = $Cost.Forecast
            ChangePercent   = $Cost.ChangePercent
            Currency        = $Cost.Currency
            Daily           = @($Cost.Daily)
            TopServices     = @($Cost.TopServices)
        }
        foreach ($k in @($Cost.Unread.Keys)) { $unread["the cost of $k"] = [string]$Cost.Unread[$k] }
    }

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
    if ($security.Alerts.High) { $reasons.Add("$($security.Alerts.High) high-severity security alert(s)") }
    if ($null -ne $policy.Compliance -and $policy.Compliance -lt 80) { $reasons.Add("policy compliance $($policy.Compliance)%") }
    if ($limit -and $limit.Percent -ge 80) { $reasons.Add("$($limit.Scope) at $($limit.Percent)% of the role assignment limit") }
    if ($costCard -and $null -ne $costCard.ChangePercent -and $costCard.ChangePercent -gt 10) { $reasons.Add("spend $($costCard.ChangePercent)% above last month") }
    if ($unread.Count) { $reasons.Add("$($unread.Count) source(s) not read") }
    $status = if ($health.Unavailable -or $activeIssues) { 'Failed' } elseif ($reasons.Count) { 'Warning' } else { 'Success' }

    # --- The Estate score ---------------------------------------------------------------------------------------------------
    $healthTotal = $health.Available + $health.Unavailable + $health.Degraded
    $parts = [ordered]@{
        Health   = $(if ($healthTotal) { [Math]::Round(100.0 * $health.Available / $healthTotal, 1) } else { $null })
        Security = $secureScore
        Policy   = $policy.Compliance
        Advisor  = $advisorScore
    }
    $known = @($parts.Values | Where-Object { $null -ne $_ -and -not [double]::IsNaN([double]$_) })
    $penalty = 0
    if ($limit) { if ($limit.Percent -ge 95) { $penalty += 5 } elseif ($limit.Percent -ge 80) { $penalty += 2 } }
    if ($costCard -and $null -ne $costCard.ChangePercent -and $costCard.ChangePercent -gt 20) { $penalty += 3 }
    $average = 0.0; foreach ($k in $known) { $average += [double]$k }
    $score = [pscustomobject][ordered]@{
        Value    = $(if ($known.Count) { [int][Math]::Max([double]0, [Math]::Min([double]100, [Math]::Round($average / $known.Count) - $penalty)) } else { $null })
        Health   = $parts.Health
        Security = $parts.Security
        Policy   = $parts.Policy
        Advisor  = $parts.Advisor
        Penalty  = $penalty
    }

    # --- What to do next ---------------------------------------------------------------------------------------------------
    $actions = [System.Collections.Generic.List[object]]::new()
    $act = { param([string] $Severity, [string] $Area, [string] $Text, [string] $Command) $actions.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.DashboardAction'; Severity = $Severity; Area = $Area; Action = $Text; Command = $Command }) }
    if ($health.Unavailable) { & $act 'High' 'Health' "$($health.Unavailable) resource(s) unavailable$(if (@($unhealthy).Count) { ': ' + ((@($unhealthy | Where-Object State -EQ 'Unavailable' | Select-Object -First 3).Resource) -join ', ') })" 'Get-AACResourceHealth' }
    if ($activeIssues) { & $act 'High' 'Health' "$activeIssues active Azure service issue(s) in these subscriptions" 'Get-AACResourceHealth -IncludeHistory' }
    if ($security.Alerts.High) { & $act 'High' 'Security' "$($security.Alerts.High) high-severity security alert(s) active" 'Get-AACSecurityAlert' }
    if ($limit -and $limit.Percent -ge 95) { & $act 'High' 'Limits' "$($limit.Scope) at $($limit.Used) of $($limit.Maximum) role assignments" 'Test-AACAzureLimit' }
    elseif ($limit -and $limit.Percent -ge 80) { & $act 'Medium' 'Limits' "$($limit.Scope) at $($limit.Percent)% of the role assignment limit" 'Test-AACAzureLimit' }
    if ($health.Degraded) { & $act 'Medium' 'Health' "$($health.Degraded) resource(s) degraded" 'Get-AACResourceHealth' }
    if ($security.Recommendations.High) { & $act 'Medium' 'Security' "$($security.Recommendations.High) high-severity security recommendation(s) unresolved" 'Invoke-AACDefenderAssessment' }
    if ($null -ne $secureScore -and $secureScore -lt 60) { & $act 'Medium' 'Security' "Secure score $secureScore% - below 60%" 'Get-AACSecurityPosture' }
    if ($null -ne $policy.Compliance -and $policy.Compliance -lt 80) { & $act 'Medium' 'Policy' "Policy compliance $($policy.Compliance)% ($($policy.NonCompliant) non-compliant resource(s))" 'Invoke-AACPolicyAssessment' }
    if ($costCard -and $null -ne $costCard.ChangePercent -and $costCard.ChangePercent -gt 10) { & $act 'Medium' 'Cost' "Spend $($costCard.ChangePercent)% above the same days last month" 'Get-AACCostAnomaly' }
    if ($advisorHigh) { & $act 'Medium' 'Advisor' "$advisorHigh High-impact Advisor recommendation(s)$(if ($advisorSavings) { " - $('{0:N0}' -f $advisorSavings.Annual) $($advisorSavings.Currency) a year to save" })" 'Get-AACAdvisorRecommendation' }
    if ($unusedTotal) { & $act 'Medium' 'Governance' "$unusedTotal unused disk(s), public IP(s) and network interface(s)" 'Get-AACUnusedResource -IncludeCost' }
    $bigDeleter = @($changers | Where-Object { $_.Deletes -ge 10 }) | Select-Object -First 1
    if ($bigDeleter) { & $act 'Medium' 'Changes' "$($bigDeleter.Deletes) deletes by $($bigDeleter.ChangedBy) in $($Hours)h" 'Get-AACChangeHistory' }
    if ($privilegedTotal) { & $act 'Low' 'Access' "$privilegedTotal privileged role assignment(s) at subscription or above - review who needs them" 'Get-AACRoleAssignment -Privileged' }
    if ($null -ne $tagCoverage -and $tagCoverage -lt 50) { & $act 'Low' 'Governance' "Only $tagCoverage% of resources are tagged" 'Get-AACTagUsage' }
    $order = @{ High = 0; Medium = 1; Low = 2 }
    $actions = @($actions | Sort-Object { $order[$_.Severity] })

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
        Score              = $score
        Security           = $security
        Policy             = $policy
        Governance         = $governance
        AdvisorScore       = $advisorScore
        AdvisorSavings     = $advisorSavings
        TopTypes           = $topTypes
        BySubscription     = $bySubscription
        ChangeTimeline     = $timeline
        TopChangers        = $changers
        Cost               = $costCard
        Actions            = $actions
    }
}
