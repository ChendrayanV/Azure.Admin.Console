function Read-AACApplicationGatewayMap {
    <#
    .SYNOPSIS
        Reads the Application Gateways in a scope, what they refer to and
        their backend health, and builds the gateway map's model. Shared by
        Show-AACApplicationGatewayMap and Export-AACDiagram.
    .DESCRIPTION
        Runs inside Invoke-AACProgress (it reports its steps there). Reads
        Resource Graph: the gateways, then the public IPs, WAF policies,
        networks, NICs and App Services they refer to; then backend health
        from metrics, or the live check with -IncludeHealth.
        Returns @{ Map (ConvertTo-AACApplicationGatewayMap's result); Title;
        Facts; Gateways (the gateway rows) }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string[]] $SubscriptionId = @(),

        [string[]] $ResourceGroupName = @(),

        [string[]] $Name = @(),

        [switch] $IncludeHealth,

        [int] $CertificateDays = 30,

        [string] $Title
    )

    $SubscriptionId = @($SubscriptionId | Where-Object { $_ })
    $Name = @($Name | Where-Object { $_ })
    Update-AACProgress -Id 'read' -Indeterminate -Description 'Reading the Application Gateways (Resource Graph)'
    $read = Invoke-AACGraphBatch -Query (Get-AACApplicationGatewayQuery -ResourceGroupName @($ResourceGroupName | Where-Object { $_ })) -SubscriptionId $SubscriptionId
    $gateways = @($read.Rows['gateways'] | Where-Object { $n = [string]$_['name']; $null -ne $_ -and (-not $Name.Count -or @($Name | Where-Object { $n -like $_ }).Count) })
    $names = @{}
    foreach ($s in @($read.Rows['subscriptions'])) { if ($s) { $names[[string]$s['subscriptionId']] = [string]$s['name'] } }
    # What the gateways refer to: public IPs, WAF policies, networks, NICs, App Services.
    $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $hosts = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($g in $gateways) {
        $text = ConvertTo-Json -InputObject $g['properties'] -Depth 30 -Compress
        foreach ($m in [regex]::Matches($text, '(?i)"id":"(/subscriptions/[^"]+/providers/microsoft\.network/(publicipaddresses|applicationgatewaywebapplicationfirewallpolicies|networkinterfaces)/[^/"]+)')) { [void]$ids.Add($m.Groups[1].Value) }
        foreach ($m in [regex]::Matches($text, '(?i)"id":"(/subscriptions/[^"]+/providers/microsoft\.network/virtualnetworks/[^/"]+)/subnets/')) { [void]$ids.Add($m.Groups[1].Value) }
        foreach ($m in [regex]::Matches($text, '"fqdn":"([^"]+)"')) { [void]$hosts.Add($m.Groups[1].Value) }
    }
    $related = @()
    $sites = @()
    if ($ids.Count -or $hosts.Count) {
        $relatedRead = Invoke-AACGraphBatch -Query (Get-AACApplicationGatewayQuery -Stage Related -Id @($ids) -HostName @($hosts)) -AllowFailure @('sites')
        foreach ($key in @($relatedRead.Rows.Keys)) { if ($key -eq 'sites') { $sites = @($relatedRead.Rows[$key]) } else { $related += @($relatedRead.Rows[$key]) } }
    }
    Update-AACProgress -Id 'read' -Complete -Description ('Read {0:N0} gateway(s) and {1:N0} resource(s) they use' -f $gateways.Count, (@($related).Count + @($sites).Count))

    Update-AACProgress -Id 'health' -Indeterminate -Description $(if ($IncludeHealth) { 'Running the live backend health check (30-90 seconds per gateway, all at once)' } else { 'Reading backend health metrics' })
    $health = Read-AACApplicationGatewayHealth -GatewayId @($gateways | ForEach-Object { ([string]$_['id']).ToLowerInvariant() }) -Live:$IncludeHealth
    Update-AACProgress -Id 'health' -Complete -Description $(if ($IncludeHealth) { 'Live backend health read for {0:N0} of {1:N0} gateway(s)' -f $health.Live.Count, $gateways.Count } else { 'Read backend health metrics' })

    $map = ConvertTo-AACApplicationGatewayMap -Gateway $gateways -Related $related -Site $sites -SubscriptionName $names -Health $health -CertificateDays $CertificateDays
    $facts = @(
        '{0:N0} gateway(s)' -f $map.Stats.Gateways
        '{0:N0} listener(s)' -f $map.Stats.Listeners
        '{0:N0} rule(s)' -f $map.Stats.Rules
        '{0:N0} pool(s)' -f $map.Stats.Pools
        '{0:N0} target(s)' -f $map.Stats.Targets
        if ($map.Stats.Unhealthy) { '{0:N0} unhealthy' -f $map.Stats.Unhealthy }
        '{0:N0} finding(s)' -f $map.Stats.Findings
        "health from $(if ($IncludeHealth) { 'the live check' } else { 'metrics' })"
        "drawn $((Get-Date).ToString('d MMM yyyy HH:mm'))"
    )
    @{
        Map      = $map
        Title    = $(if ($Title) { $Title } else { "Application Gateways: $(if ($gateways.Count -le 3) { (@($gateways | ForEach-Object { $_['name'] }) -join ', ') } else { "$($gateways.Count) gateways" })" })
        Facts    = $facts
        Gateways = $gateways
    }
}
