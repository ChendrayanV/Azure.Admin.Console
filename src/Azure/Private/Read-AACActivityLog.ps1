function Read-AACActivityLog {
    <#
    .SYNOPSIS
        Reads the Activity Log of some subscriptions over a window - the
        fastest way each subscription allows - as distinct rows: one per
        resource, caller, operation and status, with how many times, first
        and last. For Invoke-AACActivityLogAssessment.
    .DESCRIPTION
        Where each subscription's Activity Log is, decides how it is read:

          Log Analytics   the subscription's diagnostic setting sends its
                          Activity Log to a workspace (found here, or given
                          with -WorkspaceId): one query per workspace and
                          month (Get-AACActivityLogQuery), five at a time,
                          summarised in the workspace - seconds for 90, 180
                          or 365 days, and the only way past 90. What the
                          workspace keeps is its retention: CoveredFrom says
                          from when.
          Activity Log    no export (or -Source ActivityLog, or the workspace
                          couldn't be read): the REST API, which keeps 90
                          days. A slice's pages come one after another, so
                          the window is cut into about 1,500 slices
                          (-SliceHours to choose) read side by side,
                          -ThrottleLimit at a time; each operation counted
                          once, at its last status.

        Returns @{ Rows (ResourceId, Caller, Mirid, AppId, TokenType, Upn,
        Operation, OperationName, Status, Category, Count, First, Last,
        CallerIp, Source, and the latest operation's CorrelationId,
        StatusMessage, StatusCode and SubStatus); Coverage (one per subscription: Subscription,
        SubscriptionId, Source, Workspace, WorkspaceId, RetentionDays,
        CoveredFrom, CoveredTo, Note); Notices; Events (read from the REST
        API) }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string[]] $SubscriptionId,

        [System.Collections.IDictionary] $SubscriptionName = @{},

        [Parameter(Mandatory)]
        [datetime] $Start,

        [Parameter(Mandatory)]
        [datetime] $End,

        [string[]] $Category = @('Administrative'),

        [string[]] $ResourceGroupName = @(),

        [ValidateSet('Auto', 'Workspace', 'ActivityLog')]
        [string] $Source = 'Auto',

        [string] $WorkspaceId,

        [ValidateRange(1, 64)]
        [int] $ThrottleLimit = 32,

        [ValidateRange(0, 24)]
        [int] $SliceHours = 0
    )

    $iso = { param([datetime] $When) $When.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture) }
    $nameOf = { param([string] $Id) $n = $SubscriptionName[$Id.ToLowerInvariant()]; if ($n) { [string]$n } else { $Id } }
    $notices = [System.Collections.Generic.List[string]]::new()
    $rows = [System.Collections.Generic.List[object]]::new()
    $coverage = @{}
    foreach ($id in $SubscriptionId) {
        $coverage[$id.ToLowerInvariant()] = [ordered]@{ Subscription = (& $nameOf $id); SubscriptionId = $id; Source = 'Activity Log'; Workspace = ''; WorkspaceId = ''; RetentionDays = $null; CoveredFrom = $null; CoveredTo = $End; Note = '' }
    }

    # --- 1. Where each subscription sends its Activity Log ----------------------------------------------------------------
    $plan = @{}
    if ($Source -ne 'ActivityLog') {
        if ($WorkspaceId) {
            $plan[$WorkspaceId.ToLowerInvariant()] = @{ Name = $WorkspaceId; CustomerId = $WorkspaceId; Retention = $null; Subscriptions = [System.Collections.Generic.List[string]]::new() }
            foreach ($id in $SubscriptionId) { $plan[$WorkspaceId.ToLowerInvariant()].Subscriptions.Add($id) }
        }
        else {
            $settingUris = @{}
            foreach ($id in $SubscriptionId) { $settingUris[$id] = "/subscriptions/$id/providers/Microsoft.Insights/diagnosticSettings?api-version=2021-05-01-preview" }
            Update-AACProgress -Id 'activity-sources' -Total $settingUris.Count -Description "Finding where $($settingUris.Count) subscription(s) send their Activity Log"
            $settings = Invoke-AACArmParallel -Uri @($settingUris.Values) -ThrottleLimit $ThrottleLimit -OnProgress { param($SourceDone, $SourceTotal) Update-AACProgress -Id 'activity-sources' -Increment 1 }
            $targets = @{}
            foreach ($id in $SubscriptionId) {
                $answer = $settings[$settingUris[$id]]
                if (-not $answer -or $answer.Error) { $coverage[$id.ToLowerInvariant()].Note = "The diagnostic settings couldn't be read: $(if ($answer) { $answer.Error } else { 'no answer' })"; continue }
                foreach ($setting in @($answer.Items | Where-Object { $_ -is [System.Collections.IDictionary] })) {
                    $p = $setting['properties']
                    if ($p -isnot [System.Collections.IDictionary] -or -not $p['workspaceId']) { continue }
                    if (-not @($p['logs'] | Where-Object { $_ -is [System.Collections.IDictionary] -and $_['enabled'] }).Count) { continue }
                    $targets[$id] = ([string]$p['workspaceId']).TrimEnd('/')
                    break
                }
            }
            Update-AACProgress -Id 'activity-sources' -Complete -Description "$($targets.Count) of $($SubscriptionId.Count) subscription(s) send their Activity Log to a Log Analytics workspace"
            $workspaceIds = @($targets.Values | Sort-Object -Unique)
            if ($workspaceIds.Count) {
                $workspaceUris = @{}
                foreach ($w in $workspaceIds) { $workspaceUris[$w] = "$($w)?api-version=2022-10-01" }
                $workspaces = Invoke-AACArmParallel -Uri @($workspaceUris.Values) -ThrottleLimit $ThrottleLimit
                foreach ($w in $workspaceIds) {
                    $answer = $workspaces[$workspaceUris[$w]]
                    $users = @($targets.Keys | Where-Object { $targets[$_] -eq $w })
                    $body = if ($answer -and -not $answer.Error) { $answer.Body }
                    $p = if ($body -is [System.Collections.IDictionary]) { $body['properties'] }
                    if ($p -isnot [System.Collections.IDictionary] -or -not $p['customerId']) {
                        foreach ($id in $users) { $coverage[$id.ToLowerInvariant()].Note = "Sent to workspace $(($w -split '/')[-1]), which couldn't be read ($(if ($answer) { $answer.Error } else { 'no answer' })): needs Reader on it." }
                        continue
                    }
                    $key = ([string]$p['customerId']).ToLowerInvariant()
                    if (-not $plan.Contains($key)) { $plan[$key] = @{ Name = ($w -split '/')[-1]; CustomerId = [string]$p['customerId']; Retention = $(if ($p['retentionInDays']) { [int]$p['retentionInDays'] }); Subscriptions = [System.Collections.Generic.List[string]]::new() } }
                    foreach ($id in $users) { $plan[$key].Subscriptions.Add($id) }
                }
            }
        }
    }

    # --- 2. The workspaces: one query per month, five at a time ------------------------------------------------------------
    $viaWorkspace = @{}
    if ($plan.Count) {
        $days = ($End - $Start).TotalDays
        $pieces = [Math]::Max(1, [Math]::Ceiling($days / 30))
        $step = [timespan]::FromTicks([long][Math]::Ceiling(($End - $Start).Ticks / $pieces))
        $total = $plan.Count * $pieces
        Update-AACProgress -Id 'activity-query' -Total $total -Description ('Querying {0} Log Analytics workspace(s): {1:N0} day(s) in {2} part(s) each, summarised in the workspace' -f $plan.Count, [Math]::Ceiling($days), $pieces)
        foreach ($w in $plan.Values) {
            $queries = [ordered]@{}
            for ($i = 0; $i -lt $pieces; $i++) {
                $from = $Start.Add([timespan]::FromTicks($step.Ticks * $i))
                $to = if ($i -eq $pieces - 1) { $End } else { $Start.Add([timespan]::FromTicks($step.Ticks * ($i + 1))) }
                $queries["part$i"] = @{ Query = (Get-AACActivityLogQuery -SubscriptionId @($w.Subscriptions) -Start $from -End $to -Category $Category -ResourceGroupName $ResourceGroupName); Timespan = "$(& $iso $from)/$(& $iso $to)" }
            }
            $answer = Invoke-AACLogQueryBatch -WorkspaceId $w.CustomerId -Query $queries -OnProgress { param($QueryName, $QueryDone, $QueryTotal) Update-AACProgress -Id 'activity-query' -Increment 1 }
            $failed = @($answer.Errors.Keys | Where-Object { $answer.Errors[$_] })
            if ($failed.Count -eq $queries.Count) {
                $notices.Add("Workspace $($w.Name) couldn't be queried ($($answer.Errors[$failed[0]])): its subscriptions are read from the Activity Log instead (90 days at most).")
                continue
            }
            if ($failed.Count) { $notices.Add("$($failed.Count) of $($queries.Count) part(s) of the window couldn't be read from workspace $($w.Name): $($answer.Errors[$failed[0]])") }
            foreach ($name in $queries.Keys) {
                foreach ($r in @($answer.Rows[$name])) {
                    if ($r -isnot [System.Collections.IDictionary]) { continue }
                    $rows.Add(@{
                            ResourceId = [string]$r['ResourceId']; Caller = [string]$r['Caller']; Mirid = [string]$r['Mirid']; AppId = [string]$r['AppId']; TokenType = [string]$r['TokenType']; Upn = [string]$r['Upn']
                            Operation = [string]$r['Operation']; OperationName = [string]$r['OperationName']; Status = [string]$r['Status']; Category = [string]$r['Category']
                            Count = [long]$r['Count']; First = $r['First']; Last = $r['Last']; CallerIp = [string]$r['CallerIp']; Source = 'Log Analytics'
                            CorrelationId = [string]$r['CorrelationId']; StatusMessage = [string]$r['StatusMessage']; StatusCode = [string]$r['StatusCode']; SubStatus = [string]$r['SubStatus']
                        })
                }
            }
            foreach ($id in $w.Subscriptions) {
                $viaWorkspace[$id.ToLowerInvariant()] = $true
                $c = $coverage[$id.ToLowerInvariant()]
                $c.Source = 'Log Analytics'; $c.Workspace = $w.Name; $c.WorkspaceId = $w.CustomerId; $c.RetentionDays = $w.Retention
                $c.CoveredFrom = if ($w.Retention -and $End.AddDays(-$w.Retention) -gt $Start) { $End.AddDays(-$w.Retention) } else { $Start }
                $c.Note = if ($w.Retention -and $End.AddDays(-$w.Retention) -gt $Start) { "The workspace keeps $($w.Retention) day(s): nothing before $($c.CoveredFrom.ToString('yyyy-MM-dd'))." } else { '' }
            }
        }
        Update-AACProgress -Id 'activity-query' -Complete -Description ('Log Analytics: {0:N0} distinct activity row(s)' -f $rows.Count)
    }

    # --- 3. The rest from the REST API: 90 days, many slices side by side --------------------------------------------------
    $viaApi = @($SubscriptionId | Where-Object { -not $viaWorkspace.Contains($_.ToLowerInvariant()) })
    $events = 0
    if ($viaApi.Count) {
        $apiStart = if ($Start -lt $End.AddDays(-89.9)) { $End.AddDays(-89.9) } else { $Start }
        $groups = @($ResourceGroupName | Where-Object { $_ })
        $hours = if ($SliceHours) { $SliceHours } else { [int][Math]::Min(24, [Math]::Max(1, [Math]::Ceiling(($End - $apiStart).TotalHours * $viaApi.Count * [Math]::Max(1, $groups.Count) / 1500))) }
        $select = 'eventTimestamp,caller,claims,operationName,status,subStatus,properties,resourceId,correlationId,operationId,category,httpRequest'
        $uris = [System.Collections.Generic.List[string]]::new()
        foreach ($id in $viaApi) {
            for ($from = $apiStart; $from -lt $End; $from = $from.AddHours($hours)) {
                $to = if ($from.AddHours($hours) -lt $End) { $from.AddHours($hours) } else { $End }
                $filter = "eventTimestamp ge '$(& $iso $from)' and eventTimestamp lt '$(& $iso $to)'"
                foreach ($f in $(if ($groups.Count) { $groups | ForEach-Object { "$filter and resourceGroupName eq '$_'" } } else { , $filter })) {
                    $uris.Add("/subscriptions/$id/providers/Microsoft.Insights/eventtypes/management/values?api-version=2015-04-01&`$filter=$([System.Uri]::EscapeDataString($f))&`$select=$select")
                }
            }
            $c = $coverage[$id.ToLowerInvariant()]
            $c.Source = 'Activity Log'; $c.CoveredFrom = $apiStart
            $why = if ($c.Note) { "$($c.Note) " } else { '' }
            # The API's limit is kept a little under 90 days: only a real shortfall is noted.
            $c.Note = if ($Start -lt $apiStart.AddDays(-1)) { "$($why)No Activity Log export to a workspace: Azure keeps 90 days, so nothing before $($apiStart.ToString('yyyy-MM-dd'))." } else { $why.Trim() }
        }
        Update-AACProgress -Id 'activity-api' -Total $uris.Count -Description ('Reading the Activity Log of {0} subscription(s): {1:N0} slices of {2} h, {3} at a time' -f $viaApi.Count, $uris.Count, $hours, $ThrottleLimit)
        $answers = Invoke-AACArmParallel -Uri $uris.ToArray() -ThrottleLimit $ThrottleLimit -OnProgress { param($SliceDone, $SliceTotal) Update-AACProgress -Id 'activity-api' -Increment 1 }
        Update-AACProgress -Id 'activity-api' -Complete

        # Hashtables, read inline: a year of a busy subscription is a lot of events.
        $keep = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Category), [StringComparer]::OrdinalIgnoreCase)
        $all = $Category -contains 'All'
        $upn = 'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn'
        $operations = [System.Collections.Generic.Dictionary[string, hashtable]]::new([StringComparer]::OrdinalIgnoreCase)
        $failedSlices = 0
        foreach ($uri in $uris) {
            $answer = $answers[$uri]
            if (-not $answer -or $answer.Error) { $failedSlices++; continue }
            if (-not $answer.Items) { continue }
            foreach ($e in $answer.Items) {
                if ($e -isnot [System.Collections.IDictionary]) { continue }
                $events++
                $c = $e['category']
                $categoryName = if ($c -is [System.Collections.IDictionary]) { [string]$c['value'] } else { '' }
                if (-not $all -and -not $keep.Contains($categoryName)) { continue }
                $o = $e['operationName']
                $operation = if ($o -is [System.Collections.IDictionary]) { [string]$o['value'] } else { '' }
                $time = $e['eventTimestamp']
                $time = if ($time -is [datetime]) { $time.ToUniversalTime() } else { [datetime]::Parse([string]$time, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]'AdjustToUniversal, AssumeUniversal') }
                $resourceId = ([string]$e['resourceId']).ToLowerInvariant()
                $key = "$($e['correlationId'])|$($e['operationId'])|$operation|$resourceId"
                $seen = $null
                if ($operations.TryGetValue($key, [ref]$seen) -and $seen.Time -ge $time) { continue }
                $claims = $e['claims']
                if ($claims -isnot [System.Collections.IDictionary]) { $claims = @{} }
                $st = $e['status']
                $http = $e['httpRequest']
                $status = if ($st -is [System.Collections.IDictionary]) { [string]$st['value'] } else { '' }
                # Why it failed: kept for failures only, the rest don't need it.
                $props = if ($status -eq 'Failed' -and $e['properties'] -is [System.Collections.IDictionary]) { $e['properties'] } else { @{} }
                $sub = $e['subStatus']
                $operations[$key] = @{
                    CorrelationId = [string]$e['correlationId']; StatusMessage = [string]$props['statusMessage']; StatusCode = [string]$props['statusCode']
                    SubStatus = $(if ($status -eq 'Failed' -and $sub -is [System.Collections.IDictionary]) { [string]$sub['value'] } else { '' })
                    Time = $time; ResourceId = $resourceId; Caller = [string]$e['caller']; Mirid = [string]$claims['xms_mirid']; AppId = [string]$claims['appid']; TokenType = [string]$claims['idtyp']; Upn = [string]$claims[$upn]
                    Operation = $operation; OperationName = $(if ($o -is [System.Collections.IDictionary]) { [string]$o['localizedValue'] } else { '' }); Status = $status
                    Category = $categoryName; CallerIp = $(if ($http -is [System.Collections.IDictionary]) { [string]$http['clientIpAddress'] } else { '' })
                }
            }
        }
        if ($failedSlices) { $notices.Add("$failedSlices of $($uris.Count) Activity Log slice(s) couldn't be read (Reader or Monitoring Reader on the subscription, or throttling): the counts are low.") }

        # The same shape the workspace returns: one row per resource, caller, operation and status.
        $distinct = [System.Collections.Generic.Dictionary[string, hashtable]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($op in $operations.Values) {
            $key = "$($op.ResourceId)|$($op.Caller)|$($op.Mirid)|$($op.AppId)|$($op.Operation)|$($op.Status)"
            $row = $null
            if (-not $distinct.TryGetValue($key, [ref]$row)) {
                $row = @{ ResourceId = $op.ResourceId; Caller = $op.Caller; Mirid = $op.Mirid; AppId = $op.AppId; TokenType = $op.TokenType; Upn = $op.Upn; Operation = $op.Operation; OperationName = $op.OperationName; Status = $op.Status; Category = $op.Category; Count = [long]0; First = $op.Time; Last = $op.Time; CallerIp = $op.CallerIp; Source = 'Activity Log'
                    CorrelationId = $op.CorrelationId; StatusMessage = $op.StatusMessage; StatusCode = $op.StatusCode; SubStatus = $op.SubStatus }
                $distinct[$key] = $row
            }
            $row.Count++
            if ($op.Time -lt $row.First) { $row.First = $op.Time }
            if ($op.Time -gt $row.Last) {
                $row.Last = $op.Time; $row.CorrelationId = $op.CorrelationId; $row.StatusMessage = $op.StatusMessage; $row.StatusCode = $op.StatusCode; $row.SubStatus = $op.SubStatus
                if ($op.CallerIp) { $row.CallerIp = $op.CallerIp }
            }
        }
        foreach ($row in $distinct.Values) { $rows.Add($row) }
        Update-AACProgress -Id 'activity-events' -Complete -Description ('Activity Log: {0:N0} event(s), {1:N0} operation(s), {2:N0} distinct row(s)' -f $events, $operations.Count, $distinct.Count)
    }

    @{
        Rows     = $rows.ToArray()
        Coverage = @($coverage.Values | ForEach-Object { [pscustomobject]$_ } | Sort-Object Subscription)
        Notices  = $notices.ToArray()
        Events   = $events
    }
}
