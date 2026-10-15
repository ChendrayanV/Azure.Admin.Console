function Read-AACApplicationGatewayHealth {
    <#
    .SYNOPSIS
        Reads Application Gateway backend health: from metrics (always, v2),
        and - with -Live - from the gateways' own backend health check.
    .DESCRIPTION
        Metrics (Reader): HealthyHostCount and UnhealthyHostCount by
        BackendSettingsPool over the last 30 minutes, the latest five-minute
        average - per pool and backend setting, not per target. v1 gateways
        have no such metrics.

        -Live: POST {id}/backendhealth, a long-running operation (often 30-90
        seconds) that probes every target now - each target's state (Healthy,
        Unhealthy, Draining, Unknown) and the probe's reason. All gateways are
        started together, then polled. It needs the backendhealth/action
        permission (Reader may not have it); a gateway that refuses or times
        out is reported, not fatal.

        Returns @{ Metrics = @{ gateway id = @{ 'pool|settings' (lower-case
        names) = @{ Healthy; Unhealthy } } }; Live = @{ gateway id = @(@{ Pool;
        Settings (IDs, lower case); Address; Health; Reason }) }; Errors =
        @{ gateway id = reason } }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $GatewayId,

        [switch] $Live,

        [ValidateRange(1, 30)]
        [int] $TimeoutMinutes = 4,

        [ValidateRange(1, 32)]
        [int] $ThrottleLimit = 12
    )

    $end = [datetime]::UtcNow
    $span = "$($end.AddMinutes(-30).ToString('yyyy-MM-ddTHH:mm:ssZ'))/$($end.ToString('yyyy-MM-ddTHH:mm:ssZ'))"
    $metrics = @{}
    $uris = @{}
    foreach ($id in $GatewayId) { $uris[$id] = "$id/providers/Microsoft.Insights/metrics?api-version=2023-10-01&timespan=$span&interval=PT5M&metricnames=HealthyHostCount,UnhealthyHostCount&aggregation=Average&`$filter=$([System.Uri]::EscapeDataString("BackendSettingsPool eq '*'"))" }
    $answers = if ($uris.Count) { Invoke-AACArmParallel -Uri @($uris.Values) -ThrottleLimit $ThrottleLimit } else { @{} }
    foreach ($id in @($uris.Keys)) {
        $metrics[$id] = @{}
        $answer = $answers[$uris[$id]]
        if (-not $answer -or -not ($answer -is [System.Collections.IDictionary]) -or -not $answer.Contains('Body') -or $answer['Body'] -isnot [System.Collections.IDictionary]) { continue }
        foreach ($m in @($answer['Body']['value'])) {
            $field = if ([string]$m['name']['value'] -eq 'HealthyHostCount') { 'Healthy' } else { 'Unhealthy' }
            foreach ($ts in @($m['timeseries'])) {
                # The dimension is 'pool~settings'.
                $dimension = [string](@($ts['metadatavalues'] | ForEach-Object { $_['value'] }) | Select-Object -First 1)
                $last = @($ts['data'] | Where-Object { $null -ne $_ -and $null -ne $_['average'] }) | Select-Object -Last 1
                if (-not $dimension -or -not $last) { continue }
                $pool, $settings = $dimension.ToLowerInvariant() -split '~', 2
                $key = "$pool|$settings"
                if (-not $metrics[$id].Contains($key)) { $metrics[$id][$key] = @{ Healthy = $null; Unhealthy = $null } }
                $metrics[$id][$key][$field] = [Math]::Round([double]$last['average'], 1)
            }
        }
    }

    $liveHealth = @{}
    $errors = @{}
    if ($Live -and $GatewayId.Count) {
        # Start every check, then poll them together.
        $pending = @{}
        foreach ($id in $GatewayId) {
            try {
                $start = Invoke-AACHttp -Method Post -Uri "$id/backendhealth?api-version=2023-11-01"
                if ($start.Status -eq 200 -and $start.Content) { $liveHealth[$id] = $start.Content; continue }
                $location = if ($start.Headers -and $start.Headers.ContainsKey('Location')) { [string]$start.Headers['Location'] } else { '' }
                if ($location) { $pending[$id] = $location } else { $errors[$id] = "Azure answered $($start.Status) with nowhere to poll." }
            }
            catch { $errors[$id] = [string]$_.Exception.Message }
        }
        $deadline = [datetime]::UtcNow.AddMinutes($TimeoutMinutes)
        while ($pending.Count -and [datetime]::UtcNow -lt $deadline) {
            Start-Sleep -Seconds 5
            foreach ($id in @($pending.Keys)) {
                try {
                    $poll = Invoke-AACHttp -Uri $pending[$id]
                    if ($poll.Status -eq 202) { continue }
                    $liveHealth[$id] = $poll.Content
                }
                catch { $errors[$id] = [string]$_.Exception.Message }
                $pending.Remove($id)
            }
        }
        foreach ($id in @($pending.Keys)) { $errors[$id] = "The backend health check didn't finish within $TimeoutMinutes minute(s)." }
        foreach ($id in @($liveHealth.Keys)) {
            $body = if ($liveHealth[$id] -is [string]) { ConvertFrom-Json -InputObject $liveHealth[$id] -AsHashtable -Depth 30 } else { $liveHealth[$id] }
            $liveHealth[$id] = @(foreach ($pool in @($body['backendAddressPools'])) {
                    $poolId = ([string]$pool['backendAddressPool']['id']).ToLowerInvariant()
                    foreach ($setting in @($pool['backendHttpSettingsCollection'])) {
                        $settingsId = ([string]$setting['backendHttpSettings']['id']).ToLowerInvariant()
                        foreach ($server in @($setting['servers'])) {
                            if ($null -eq $server) { continue }
                            @{ Pool = $poolId; Settings = $settingsId; Address = [string]$server['address']; Health = [string]$server['health']; Reason = [string]$server['healthProbeLog'] }
                        }
                    }
                })
        }
    }
    @{ Metrics = $metrics; Live = $liveHealth; Errors = $errors }
}
