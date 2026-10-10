function ConvertTo-AACHealthCheck {
    <#
    .SYNOPSIS
        Turns Invoke-AACHealthCheck's probes and reads - endpoints, TLS
        certificates, database connections, Service Bus queues, Resource
        Health, Service Health and fired alerts - into one list of checks,
        each Success, Warning or Failed, and an SLA table for the endpoints.
    .DESCRIPTION
        Endpoints (HTTP): availability = the attempts that answered as
        expected; Failed when the last attempt failed or availability is
        under -SlaTarget, or the certificate has expired or expires within 7
        days; Warning when the 95th percentile latency is over
        -LatencyThresholdMs or the certificate expires within
        -CertificateDays.
        Databases (TCP): Failed when they can't be reached - Warning when
        they only allow private access (not reachable from here is expected).
        Queues: Warning for dead-lettered messages or a backlog over
        -QueueBacklog; Failed when the queue is disabled.
        Resource Health: Failed for unavailable resources, Warning for
        degraded; Service Health: Failed for an active service issue;
        alerts: Failed for Sev0 and Sev1, Warning for Sev2.
        Returns @{ Checks (AAC.HealthCheck); Sla (AAC.HealthSla); Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        # @{ Key; Name; Kind ('Http'/'Tcp'); Uri; Host; Port; Tier; ResourceId; Private }
        [AllowEmptyCollection()] [object[]] $Endpoint = @(),
        # Invoke-AACEndpointProbe's result.
        [hashtable] $ProbeResult = @{},
        # Key -> Get-AACTlsCertificate's result.
        [hashtable] $Certificate = @{},
        # @{ Namespace; Queue; Status; Active; DeadLetter; ResourceId }
        [AllowEmptyCollection()] [object[]] $Queue = @(),
        # Resource Graph availability statuses (resourceId, state, summary, since).
        [AllowEmptyCollection()] [object[]] $HealthStatus = @(),
        [AllowEmptyCollection()] [object[]] $ServiceEvent = @(),
        [AllowEmptyCollection()] [object[]] $Alert = @(),
        [double] $SlaTarget = 99.9,
        [int] $LatencyThresholdMs = 2000,
        [int] $CertificateDays = 30,
        [int] $QueueBacklog = 1000,
        [datetime] $Now = [datetime]::UtcNow
    )

    $Now = $Now.ToUniversalTime()
    $get = { param($Row, [string] $Name) if ($Row -is [System.Collections.IDictionary]) { $Row[$Name] } elseif ($null -ne $Row) { $p = $Row.PSObject.Properties[$Name]; if ($p) { $p.Value } } }
    $leaf = { param($Id) ([string]$Id).TrimEnd('/') -replace '^.*/', '' }
    $severityOf = @{ Failed = 'High'; Warning = 'Medium'; Success = 'Info'; Info = 'Info' }
    $checks = [System.Collections.Generic.List[object]]::new()
    $sla = [System.Collections.Generic.List[object]]::new()
    $add = {
        param([string] $Status, [string] $Tier, [string] $Category, [string] $Check, [string] $Target, [string] $Detail, [string] $Remediation, [string] $ResourceId, [hashtable] $More = @{})
        $row = [ordered]@{
            PSTypeName = 'AAC.HealthCheck'; Status = $Status; Severity = $(if ($Status -eq 'Failed' -and $Tier -eq 'Critical') { 'Critical' } else { $severityOf[$Status] }); Tier = $Tier; Category = $Category; Check = $Check; Target = $Target
            Detail = $Detail; Availability = $null; LatencyP50 = $null; LatencyP95 = $null; Attempts = $null; CertificateDays = $null; Remediation = $Remediation; ResourceId = $ResourceId
        }
        foreach ($k in $More.Keys) { $row[$k] = $More[$k] }
        $checks.Add([pscustomobject]$row)
    }
    $percentile = { param([double[]] $Values, [double] $P) if (-not $Values.Count) { return $null } $sorted = [double[]]($Values | Sort-Object); $sorted[[Math]::Max(0, [int][Math]::Ceiling($P * $sorted.Count) - 1)] }

    # --- Endpoints -------------------------------------------------------------------------------------------
    foreach ($e in $Endpoint) {
        $attempts = @(if ($ProbeResult.Contains([string]$e.Key)) { $ProbeResult[[string]$e.Key] })
        $tier = if ($e.Contains('Tier') -and $e.Tier) { [string]$e.Tier } else { 'Default' }
        $target = if ($e.Kind -eq 'Tcp') { "$($e.Host):$($e.Port)" } else { [string]$e.Uri }
        $resourceId = if ($e.Contains('ResourceId')) { [string]$e.ResourceId } else { '' }
        if (-not $attempts.Count) { & $add 'Failed' $tier $(if ($e.Kind -eq 'Tcp') { 'Database' } else { 'Endpoint' }) ([string]$e.Name) $target 'Not probed.' 'Check the endpoint is valid.' $resourceId; continue }
        $up = @($attempts | Where-Object { $_.Ok })
        $availability = [Math]::Round($up.Count / $attempts.Count * 100, 2)
        $latencies = [double[]]@($up | ForEach-Object { [double]$_.LatencyMs })
        $p50 = & $percentile $latencies 0.5
        $p95 = & $percentile $latencies 0.95
        $last = $attempts[-1]
        $more = @{ Availability = $availability; LatencyP50 = $p50; LatencyP95 = $p95; Attempts = $attempts.Count }
        if ($e.Kind -eq 'Tcp') {
            $private = $e.Contains('Private') -and $e.Private
            $status = if ($last.Ok) { 'Success' } elseif ($private) { 'Warning' } else { 'Failed' }
            $detail = if ($last.Ok) { "Connected in $($last.LatencyMs) ms" } elseif ($private) { "Not reachable from here: $($last.Error) - it allows private access only, so that's expected outside its network." } else { "Not reachable: $($last.Error)" }
            & $add $status $tier 'Database' ([string]$e.Name) $target $detail $(if ($status -eq 'Failed') { 'Check the server is running, its firewall allows this network, and DNS resolves its name.' } else { '' }) $resourceId $more
            continue
        }
        $reasons = [System.Collections.Generic.List[string]]::new()
        $status = 'Success'
        if (-not $last.Ok) { $status = 'Failed'; $reasons.Add("the last attempt failed: $($last.Error)") }
        if ($availability -lt $SlaTarget) { $status = 'Failed'; $reasons.Add("$availability% available ($($up.Count) of $($attempts.Count)), under the $SlaTarget% target") }
        if ($null -ne $p95 -and $p95 -gt $LatencyThresholdMs) { if ($status -ne 'Failed') { $status = 'Warning' }; $reasons.Add("slow: 95% of answers within $p95 ms (over $LatencyThresholdMs ms)") }
        $cert = if ($Certificate.Contains([string]$e.Key)) { $Certificate[[string]$e.Key] } else { $null }
        if ($cert -and $cert.NotAfter -is [datetime]) {
            $days = [int][Math]::Floor(($cert.NotAfter - $Now).TotalDays)
            $more.CertificateDays = $days
            if ($days -lt 0) { $status = 'Failed'; $reasons.Add("the TLS certificate expired $(-$days) day(s) ago") }
            elseif ($days -lt 7) { $status = 'Failed'; $reasons.Add("the TLS certificate expires in $days day(s)") }
            elseif ($days -lt $CertificateDays) { if ($status -ne 'Failed') { $status = 'Warning' }; $reasons.Add("the TLS certificate expires in $days day(s)") }
        }
        $detail = if ($reasons.Count) { ($reasons -join '; ').Substring(0, 1).ToUpperInvariant() + ($reasons -join '; ').Substring(1) } else { "HTTP $($last.Status) in $($last.LatencyMs) ms; $availability% available" }
        $remedy = @(
            if (-not $last.Ok -or $availability -lt $SlaTarget) { 'Check the app is running and healthy (its logs, Application Insights failures, Resource Health), and what changed recently (Get-AACChangeHistory).' }
            if ($null -ne $p95 -and $p95 -gt $LatencyThresholdMs) { 'Look at what is slow: dependencies, CPU and memory (Get-AACResourceUtilization), cold starts.' }
            if ($more.CertificateDays -is [int] -and $more.CertificateDays -lt $CertificateDays) { 'Renew the certificate, or use a managed certificate that renews itself.' }
        ) -join ' '
        & $add $status $tier 'Endpoint' ([string]$e.Name) $target $detail $remedy $resourceId $more
        $sla.Add([pscustomobject][ordered]@{
                PSTypeName = 'AAC.HealthSla'; Endpoint = [string]$e.Name; Tier = $tier; Attempts = $attempts.Count; Up = $up.Count; Availability = $availability; Target = $SlaTarget
                Met = $(if ($availability -ge $SlaTarget) { 'Yes' } else { 'No' }); LatencyP50 = $p50; LatencyP95 = $p95; Uri = $target
            })
    }

    # --- Queues ------------------------------------------------------------------------------------------------
    foreach ($q in $Queue) {
        $issues = @(
            if ($q.Status -and $q.Status -ne 'Active') { "the queue is $($q.Status)" }
            if ([long]$q.DeadLetter -gt 0) { "$($q.DeadLetter) dead-lettered message(s)" }
            if ([long]$q.Active -gt $QueueBacklog) { "$($q.Active) message(s) waiting (over $QueueBacklog)" }
        )
        $status = if ($q.Status -and $q.Status -ne 'Active') { 'Failed' } elseif ($issues.Count) { 'Warning' } else { 'Success' }
        & $add $status 'Messaging' 'Queue' "$($q.Namespace)/$($q.Queue)" ([string]$q.Namespace) $(if ($issues.Count) { ($issues -join '; ') } else { "$($q.Active) message(s) waiting, none dead-lettered" }) `
            $(if ($issues.Count) { 'Check the consumers are running and keeping up; read the dead-lettered messages for why they failed (DeadLetterReason), fix, and resubmit them.' } else { '' }) ([string]$q.ResourceId)
    }

    # --- The platform: Resource Health, Service Health, alerts --------------------------------------------------------------
    $states = @{}
    foreach ($h in $HealthStatus) {
        $state = [string](& $get $h 'state')
        $states[$state] = [int]$states[$state] + 1
        if ($state -notin 'Unavailable', 'Degraded') { continue }
        $id = [string](& $get $h 'resourceId')
        & $add $(if ($state -eq 'Unavailable') { 'Failed' } else { 'Warning' }) 'Platform' 'Resource Health' (& $leaf $id) $state ([string](& $get $h 'summary')) 'Open the resource''s Resource Health blade for the cause and what Azure recommends; check recent changes (Get-AACChangeHistory).' $id
    }
    if ($HealthStatus.Count) {
        $available = [int]$states['Available']
        & $add $(if ($available -eq $HealthStatus.Count) { 'Success' } else { 'Info' }) 'Platform' 'Resource Health' 'All resources' "$available of $($HealthStatus.Count) available" ("Available $available, unavailable $([int]$states['Unavailable']), degraded $([int]$states['Degraded']), unknown $([int]$states['Unknown'])") '' ''
    }
    foreach ($s in $ServiceEvent) {
        $type = [string](& $get $s 'eventType')
        & $add $(if ($type -eq 'ServiceIssue') { 'Failed' } elseif ($type -eq 'SecurityAdvisory') { 'Warning' } else { 'Info' }) 'Platform' 'Service Health' ([string](& $get $s 'title')) ([string](& $get $s 'trackingId')) ($type -creplace '([a-z])([A-Z])', '$1 $2') 'Follow the event in Service Health; fail over or scale elsewhere if it''s long.' ''
    }
    foreach ($a in $Alert) {
        $sev = [string](& $get $a 'severity')
        & $add $(if ($sev -in 'Sev0', 'Sev1') { 'Failed' } elseif ($sev -eq 'Sev2') { 'Warning' } else { 'Info' }) 'Platform' 'Alert' ([string](& $get $a 'name')) (& $leaf (& $get $a 'target')) "$sev, fired $(([datetime](& $get $a 'fired')).ToString('d MMM HH:mm'))$(if (& $get $a 'description') { ": $(& $get $a 'description')" })" 'Work the alert: see its rule''s runbook, and the resource''s recent changes.' ([string](& $get $a 'target'))
    }

    $order = @{ Failed = 0; Warning = 1; Info = 2; Success = 3 }
    $sorted = @($checks | Sort-Object -Property @{ Expression = { $order[$_.Status] } }, Tier, Category, Check)
    $attemptsAll = [int](@($sla | ForEach-Object { $_.Attempts }) | Measure-Object -Sum).Sum
    $upAll = [int](@($sla | ForEach-Object { $_.Up }) | Measure-Object -Sum).Sum
    @{
        Checks = $sorted
        Sla    = $sla.ToArray()
        Stats  = @{
            Checks       = $sorted.Count
            Failed       = @($sorted | Where-Object Status -EQ 'Failed').Count
            Warnings     = @($sorted | Where-Object Status -EQ 'Warning').Count
            Passed       = @($sorted | Where-Object Status -EQ 'Success').Count
            Endpoints    = $sla.Count
            SlaMet       = @($sla | Where-Object Met -EQ 'Yes').Count
            Availability = $(if ($attemptsAll) { [Math]::Round($upAll / $attemptsAll * 100, 2) } else { $null })
        }
    }
}
