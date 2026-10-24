function Show-AACApplicationGatewayMap {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Draws Application Gateways as their connection flow - frontend IPs,
        listeners, rules, path rules and redirects, backend settings and
        probes, pools and targets, WAF policies - inside their network and
        subnet, with health and findings; shows each gateway's flows at the
        prompt and opens the map in your browser.
    .DESCRIPTION
        Read-only, with Azure Resource Graph (Reader is enough): every setting
        of each gateway, and what it refers to - public IPs, WAF policies,
        the network and subnet (with its NSG and route table), the NICs and
        VMs in the pools, and App Services whose host name is a target.

        The map, left to right: frontend IPs > listeners (protocol, port,
        host names, certificate and its expiry, WAF policy) > rules
        (priority, basic or path-based) > path rules and redirects > backend
        settings (protocol, port, timeout, host name, affinity, draining) and
        their probes > pools > targets. WAF policies sit on the left with a
        line to what they protect (the gateway, a site or a path). Pools and
        targets are outlined green, amber or red by health. Click a card for
        all its settings, its findings and its connections.

        Health: metrics always (healthy and unhealthy host counts per pool,
        last 30 minutes, v2 gateways); -IncludeHealth runs each gateway's live
        backend health check - every target's state and, when it fails, the
        probe's reason. That check takes 30-90 seconds and needs the
        Microsoft.Network/applicationGateways/backendhealth/action permission;
        a gateway that refuses is reported, not fatal.

        Findings (High, Medium, Low): v1 SKU, WAF tier without a WAF, WAF in
        Detection or disabled, old rule sets, old TLS policy, no zones or
        under 2 instances, HTTP not redirected to HTTPS, certificates
        expired, expiring (-CertificateDays) or uploaded instead of from Key
        Vault, backend settings without a custom probe, probe host mismatch,
        connection draining off, empty or unhealthy pools, and listeners,
        settings, probes and pools nothing uses.

        At the prompt: tiles, each gateway's flows (listener > rule > path >
        settings > pool, with health) and the findings. -CsvPath writes the
        flows; -PdfPath the gateways, flows and findings; -HtmlPath the map
        (a file in your temp folder by default).
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ResourceGroupName
        Only these resource groups.
    .PARAMETER Name
        Only gateways with these names; wildcards work.
    .PARAMETER IncludeHealth
        Run each gateway's live backend health check: every target's state
        and the probe's reason.
    .PARAMETER CertificateDays
        A certificate expiring within this many days is a finding (30 by
        default).
    .PARAMETER Direction
        LeftToRight (the default) or TopToBottom.
    .PARAMETER Theme
        Dark (the default), Light or Blueprint.
    .PARAMETER HtmlPath
        Where to write the map. By default a file in your temp folder.
    .PARAMETER CsvPath
        Write the flows to this CSV file.
    .PARAMETER PdfPath
        Write a PDF report: gateways, flows and findings.
    .PARAMETER Title
        The map's title.
    .PARAMETER NoBrowser
        Write the map without opening it.
    .PARAMETER PassThru
        Also return the map: gateways, flows, findings, cards and lines.
    .EXAMPLE
        Connect-AAC
        Show-AACApplicationGatewayMap
        Every Application Gateway you can see, as a map in the browser.
    .EXAMPLE
        Show-AACApplicationGatewayMap -ResourceGroupName 'rg-edge' -Name 'appgw-prod' -IncludeHealth
        One gateway with live backend health and the probes' reasons.
    .EXAMPLE
        (Show-AACApplicationGatewayMap -NoBrowser -PassThru).Flows | Where-Object Health -In 'unhealthy', 'degraded'
        The routes that reach unhealthy backends.
    .OUTPUTS
        AAC.ApplicationGatewayMap, with -PassThru
    #>
    [CmdletBinding()]
    [OutputType('AAC.ApplicationGatewayMap')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [ValidateNotNullOrEmpty()]
        [string[]] $ResourceGroupName,

        [SupportsWildcards()]
        [string[]] $Name,

        [switch] $IncludeHealth,

        [ValidateRange(1, 365)]
        [int] $CertificateDays = 30,

        [ValidateSet('LeftToRight', 'TopToBottom')]
        [string] $Direction = 'LeftToRight',

        [ValidateSet('Dark', 'Light', 'Blueprint')]
        [string] $Theme = 'Dark',

        [string] $HtmlPath,

        [string] $CsvPath,

        [string] $PdfPath,

        [string] $Title,

        [switch] $NoBrowser,

        [switch] $PassThru
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $htmlFullPath = if ($HtmlPath) { & $resolve $HtmlPath } else { Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('AAC-ApplicationGatewayMap-{0:yyyyMMdd-HHmmss}.html' -f (Get-Date)) }
    $request = @{ SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ResourceGroupName = @($ResourceGroupName | Where-Object { $_ }); Name = @($Name | Where-Object { $_ }); IncludeHealth = [bool]$IncludeHealth; CertificateDays = $CertificateDays; Title = $Title }

    Write-AACRule -Title 'Azure Admin Console :: Application Gateway map' -Color 'darkorange'
    $state = Invoke-AACProgress -ScriptBlock {
        $null = Get-AACAccessToken
        # The read and the model: Read-AACApplicationGatewayMap (shared with Export-AACDiagram).
        $built = Read-AACApplicationGatewayMap -SubscriptionId $request.SubscriptionId -ResourceGroupName $request.ResourceGroupName -Name $request.Name -IncludeHealth:$request.IncludeHealth -CertificateDays $request.CertificateDays -Title $request.Title
        $map = $built.Map
        $mapTitle = $built.Title
        $facts = $built.Facts
        $gateways = @($built.Gateways)
        if ($gateways.Count) {
            Update-AACProgress -Id 'html' -Indeterminate -Description 'Writing the map'
            Write-AACResourceMapHtml -Map $map -Path $htmlFullPath -Title $mapTitle -Fact $facts -Direction $(if ($Direction -eq 'TopToBottom') { 'DOWN' } else { 'RIGHT' }) -Theme $Theme.ToLowerInvariant()
            Update-AACProgress -Id 'html' -Complete -Description "Map: $htmlFullPath"
        }
        @{ Map = $map; Title = $mapTitle }
    }

    $map = $state.Map
    if (-not $map.Stats.Gateways) { Write-AACMarkup '[grey58]No Application Gateway in that scope.[/]'; return }
    $rank = Get-AACSeverityRank
    $healthTones = @{ healthy = 'good'; degraded = 'warn'; unhealthy = 'bad'; unknown = 'neutral'; redirect = 'info' }
    $stats = $map.Stats
    $report = @{
        Subtitle = 'Application Gateways: connection flow, health and findings'
        Facts    = [ordered]@{ Gateways = $stats.Gateways; Health = $(if ($IncludeHealth) { 'live backend health check' } else { 'metrics, last 30 minutes (-IncludeHealth for the live check)' }); Map = $htmlFullPath }
        Status   = $(if ($stats.High) { 'Failed' } elseif ($stats.Findings) { 'Warning' } else { 'Success' })
        Headline = "$($stats.Gateways) gateway(s), $($stats.Listeners) listener(s), $($stats.Targets) target(s)$(if ($stats.Unhealthy) { ", $($stats.Unhealthy) unhealthy" }): $($stats.High) high finding(s) of $($stats.Findings)"
        Tiles    = @(
            @{ Value = '{0:N0}' -f $stats.Gateways; Label = 'gateways'; Tone = 'info' }
            @{ Value = '{0:N0}' -f $stats.Listeners; Label = 'listeners'; Tone = 'info' }
            @{ Value = '{0:N0}' -f $stats.Rules; Label = 'rules'; Tone = 'info' }
            @{ Value = '{0:N0}' -f $stats.Targets; Label = 'backend targets'; Tone = 'info' }
            @{ Value = '{0:N0}' -f $stats.Unhealthy; Label = 'unhealthy targets'; Tone = $(if ($stats.Unhealthy) { 'bad' } else { 'good' }) }
            @{ Value = '{0:N0}' -f $stats.High; Label = 'high findings'; Tone = $(if ($stats.High) { 'bad' } else { 'good' }) }
        )
        Tables   = @(
            @{ Id = 'gateways'; Title = 'Gateways'; Section = 'Gateways'; Rows = @($map.Gateways); Noun = 'gateways'; NoConsole = $true
                Columns = @(
                    @{ Key = 'Gateway'; Label = 'Gateway'; Pdf = $true }, @{ Key = 'Sku'; Label = 'SKU'; Pdf = $true }, @{ Key = 'Capacity'; Label = 'Capacity'; Pdf = $true }, @{ Key = 'Zones'; Label = 'Zones'; Pdf = $true }
                    @{ Key = 'TlsPolicy'; Label = 'TLS policy'; Pdf = $true }, @{ Key = 'WafPolicy'; Label = 'WAF policy'; Pdf = $true }, @{ Key = 'Listeners'; Label = 'Listeners'; Type = 'number'; Pdf = $true }
                    @{ Key = 'Targets'; Label = 'Targets'; Type = 'number'; Pdf = $true }, @{ Key = 'Unhealthy'; Label = 'Unhealthy'; Type = 'number'; Pdf = $true }, @{ Key = 'Findings'; Label = 'Findings'; Type = 'number'; Pdf = $true }
                ) }
            @{ Id = 'flows'; Title = 'Flows: listener > rule > path > backend settings > pool'; Section = 'Flows'; Rows = @($map.Flows); Noun = 'flows'; ConsoleLimit = 30
                Columns = @(
                    @{ Key = 'Gateway'; Label = 'Gateway'; Console = $true; Pdf = $true }
                    @{ Key = 'Listener'; Label = 'Listener'; Console = $true; Pdf = $true }
                    @{ Key = 'Port'; Label = 'Port'; Console = $true; Pdf = $true }
                    @{ Key = 'HostNames'; Label = 'Host names'; Console = $true; Pdf = $true }
                    @{ Key = 'Rule'; Label = 'Rule'; Console = $true; Pdf = $true }
                    @{ Key = 'Path'; Label = 'Path'; Console = $true; Pdf = $true }
                    @{ Key = 'Redirect'; Label = 'Redirect'; Pdf = $true }
                    @{ Key = 'BackendSettings'; Label = 'Backend settings'; Console = $true; Pdf = $true }
                    @{ Key = 'Pool'; Label = 'Pool'; Console = $true; Pdf = $true }
                    @{ Key = 'Health'; Label = 'Health'; Type = 'badge'; Tones = $healthTones; Console = $true; Pdf = $true }
                    @{ Key = 'WafPolicy'; Label = 'WAF policy' }
                ) }
            @{ Id = 'findings'; Title = 'Findings'; Section = 'Findings'; Rows = @($map.Findings); Noun = 'findings'; ConsoleLimit = 20; Empty = 'Nothing to fix.'; EmptyStatus = 'Success'
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Console = $true; Pdf = $true }
                    @{ Key = 'Gateway'; Label = 'Gateway'; Console = $true; Pdf = $true }
                    @{ Key = 'Component'; Label = 'Component'; Console = $true; Pdf = $true }
                    @{ Key = 'Name'; Label = 'Name'; Console = $true; Pdf = $true }
                    @{ Key = 'Finding'; Label = 'Finding'; Console = $true; Pdf = $true }
                    @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Recommendation'; Label = 'What to do'; Type = 'wide'; Pdf = $true }
                ) }
        )
        Hint     = 'Click a card on the map for all its settings; -IncludeHealth runs the live backend health check; -CsvPath writes the flows; -PassThru returns the map.'
    }
    if ($CsvPath -or $PdfPath) { Invoke-AACReportOutput -Report $report -Title $state.Title -CsvObject @($map.Flows) -Noun 'flow' -CsvPath (& $resolve $CsvPath) -PdfPath (& $resolve $PdfPath) }
    Show-AACReportView -Report $report
    if (-not $NoBrowser) {
        Open-AACFile -Path $htmlFullPath
        Write-AACMarkup '[grey58]Opened in your browser: click a card for its settings; Save PNG, JPEG or SVG at the top.[/]'
    }
    if ($PassThru) {
        [pscustomobject]@{
            PSTypeName = 'AAC.ApplicationGatewayMap'
            Title      = $state.Title
            Path       = $htmlFullPath
            Gateways   = @($map.Gateways)
            Flows      = @($map.Flows)
            Findings   = @($map.Findings)
            Nodes      = @($map.Nodes | ForEach-Object { [pscustomobject]@{ Name = $_.name; Type = $_.type; Label = $_.typeLabel; Health = $_.health; Risk = $_.risk; Details = ($_.facts -join ' · '); Id = $_.id } })
            Edges      = @($map.Edges | ForEach-Object { [pscustomobject]@{ Kind = $_.kind; Source = $_.source; Target = $_.target; Label = $_.label } })
            Stats      = [pscustomobject]$map.Stats
        }
    }
}
