function Show-AACNetworkTopology {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Draws the network topology of the tenant - or of management groups,
        subscriptions or regions - as an interactive diagram: hubs with their
        spokes around them, or every network inside its tenant, management
        group, subscription, region and resource group; with the peerings,
        private endpoints and the firewalls and appliances traffic is routed
        through. Opens it in your browser, ready to save as PNG, JPEG or SVG.
    .DESCRIPTION
        Reads with Azure Resource Graph - read-only, Reader is enough, no Az
        modules - across every subscription in scope, every region:
          the management groups and subscriptions above the networks
          virtual networks and subnets, and their peerings - also across
            subscriptions, and to networks you can't see
          VPN and ExpressRoute gateways, connections, circuits, local
            gateways; Virtual WAN and its hubs and gateways
          Azure Firewalls, network virtual appliances (VMs whose NIC forwards
            IP traffic), NSGs, route tables, NAT gateways, Bastion, load
            balancers, Application Gateways, private link services, DNS
            resolvers
          virtual machines, scale sets and private endpoints in their
            subnets, and the PaaS resources the private endpoints serve
            (-NetworkOnly leaves these out)
        A peering outside the scope is followed to the network at its other
        end, and a route's next hop to the firewall or appliance that has the
        IP, so a spoke's map reaches its hub.

        The boxes (-GroupBy):
          ManagementGroup  tenant > management group > subscription > region
                           > resource group > virtual network > subnet
          Subscription     subscription > region > resource group > ...
          Region           region > virtual network > subnet
        Subnets are drawn in rows inside their network, as wide as their
        prefix is big. VMs, scale sets, Bastion, gateways, firewalls and
        private endpoints sit in the subnet they have an IP in; a VM shows
        its NIC's IPs and NSG, and an appliance is outlined in the route
        colour.

        The lines:
          VNet peering   between networks, both ways, with its state and what
                         it lets through (forwarded traffic, gateway transit,
                         remote gateway); red and dashed when not Connected
          Private link   from a private endpoint to the PaaS resource it serves
          Route          from a subnet to the firewall or appliance its routes
                         send traffic to ("0.0.0.0/0 via rt-spoke")
          Network        a gateway's connections and circuits, and the rest
        Within a network, subnets reach each other through Azure's system
        routes: no lines are drawn between them.

        Each network gets a role: hub (gateway transit, or a gateway,
        firewall or appliance and peerings, or 3+ peerings), spoke (peered
        with a hub), peered or standalone. The layout (-Layout):
          HubSpoke   each hub at the centre, its spokes in rings around it,
                     hubs side by side, the rest below; each network's box
                     says its subscription, region and resource group
          Hierarchy  the nested boxes, laid out in layers
          Auto       HubSpoke when there are hubs with spokes (the default)
        The page switches between them, and between left to right and top to
        bottom; pan, zoom, search, click for details and connections, and
        save as PNG, JPEG or SVG.

        At the prompt: tiles, the hubs and their spokes, and findings - a
        peering that isn't connected, a route to an IP nothing has, a spoke
        subnet whose internet traffic isn't sent through a firewall or
        appliance, a peering to a network you can't see, standalone networks.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups (at any depth).
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER Location
        Only these regions (e.g. 'uksouth', 'westeurope').
    .PARAMETER GroupBy
        The boxes around the networks: ManagementGroup (the default),
        Subscription or Region.
    .PARAMETER Layout
        Auto (the default), HubSpoke or Hierarchy. The page can switch too.
    .PARAMETER NetworkOnly
        Leave out virtual machines, scale sets, private endpoints and the
        PaaS resources behind them: only the network fabric - networks,
        subnets, peerings, gateways, firewalls, appliances, Bastion. For a
        large estate.
    .PARAMETER ExcludeType
        Resource types to leave out; wildcards work.
    .PARAMETER Direction
        LeftToRight (the default) or TopToBottom, inside each box. The page
        can switch it too.
    .PARAMETER Theme
        Dark (the default), Light or Blueprint.
    .PARAMETER NsgView
        Chips (the default): NSGs and route tables as chips on the subnets
        and VMs they're applied to. Cards: as resources, with lines.
    .PARAMETER HtmlPath
        Where to write the diagram. By default a file in your temp folder.
    .PARAMETER Title
        The diagram's title.
    .PARAMETER NoBrowser
        Write the diagram without opening it.
    .PARAMETER PassThru
        Also return the topology: networks with their roles, findings,
        resources, connections and the file's path.
    .EXAMPLE
        Connect-AAC
        Show-AACNetworkTopology
        Every network you can see, hubs at the centre of their spokes.
    .EXAMPLE
        Show-AACNetworkTopology -ManagementGroupId 'mg-landingzones' -GroupBy Subscription -Layout Hierarchy
        A management group's networks inside their subscriptions, regions and resource groups.
    .EXAMPLE
        Show-AACNetworkTopology -NetworkOnly -Location 'uksouth', 'ukwest' -Theme Light -HtmlPath .\out\Network.html -NoBrowser
        The network fabric of two regions, written to a file.
    .EXAMPLE
        (Show-AACNetworkTopology -NoBrowser -PassThru).Findings | Where-Object Severity -EQ 'High'
        Peerings that aren't connected and routes to IPs nothing has.
    .OUTPUTS
        AAC.NetworkTopology, with -PassThru
    #>
    [CmdletBinding()]
    [OutputType('AAC.NetworkTopology')]
    param(
        [ValidateNotNullOrEmpty()]
        [string[]] $ManagementGroupId,

        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [ValidateNotNullOrEmpty()]
        [string[]] $Location,

        [ValidateSet('ManagementGroup', 'Subscription', 'Region')]
        [string] $GroupBy = 'ManagementGroup',

        [ValidateSet('Auto', 'HubSpoke', 'Hierarchy')]
        [string] $Layout = 'Auto',

        [switch] $NetworkOnly,

        [SupportsWildcards()]
        [string[]] $ExcludeType,

        [ValidateSet('LeftToRight', 'TopToBottom')]
        [string] $Direction = 'LeftToRight',

        [ValidateSet('Dark', 'Light', 'Blueprint')]
        [string] $Theme = 'Dark',

        [ValidateSet('Chips', 'Cards')]
        [string] $NsgView = 'Chips',

        [string] $HtmlPath,

        [string] $Title,

        [switch] $NoBrowser,

        [switch] $PassThru
    )

    # A failure anywhere below ends as a Spectre.Console error panel and this
    # command's own terminating error, not a line inside the module. A stopped
    # pipeline (Select-Object -First, Ctrl+C) is no failure: just return - a
    # rethrow would stop the caller's whole script, not only this command.
    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $htmlFullPath = if ($HtmlPath) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($HtmlPath) }
    else { Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('AAC-NetworkTopology-{0:yyyyMMdd-HHmmss}.html' -f (Get-Date)) }
    # Everything the work below needs, read here: it runs inside
    # Invoke-AACProgress, whose variables could hide ours.
    $request = @{
        ManagementGroupId = @($ManagementGroupId | Where-Object { $_ })
        SubscriptionId    = @($SubscriptionId | Where-Object { $_ })
        Location          = @($Location | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() -replace '\s', '' })
        GroupBy           = $GroupBy
        Layout            = $Layout
        NetworkOnly       = [bool]$NetworkOnly
        ExcludeType       = @($ExcludeType | Where-Object { $_ })
        Title             = $Title
    }

    Write-AACRule -Title 'Azure Admin Console :: Network topology' -Color 'deepskyblue3_1'
    $state = Invoke-AACProgress -ScriptBlock {
        $null = Get-AACAccessToken
        # The read and the model: Read-AACNetworkTopology (shared with Export-AACDiagram).
        $built = Read-AACNetworkTopology -ManagementGroupId $request.ManagementGroupId -SubscriptionId $request.SubscriptionId -Location $request.Location -GroupBy $request.GroupBy -NetworkOnly:$request.NetworkOnly -ExcludeType $request.ExcludeType -Title $request.Title
        $map = $built.Map
        $mapTitle = $built.Title
        $facts = $built.Facts
        $layoutName = switch ($request.Layout) { 'HubSpoke' { 'hubspoke' } 'Hierarchy' { 'packed' } default { if ($map.Layout -eq 'hubspoke') { 'hubspoke' } else { 'packed' } } }
        Update-AACProgress -Id 'html' -Indeterminate -Description 'Writing the diagram'
        Write-AACResourceMapHtml -Map $map -Path $htmlFullPath -Title $mapTitle -Fact $facts -Direction $(if ($Direction -eq 'TopToBottom') { 'DOWN' } else { 'RIGHT' }) -Theme $Theme.ToLowerInvariant() -NsgView $NsgView.ToLowerInvariant() -Layout $layoutName -Hierarchy packed
        Update-AACProgress -Id 'html' -Complete -Description "Diagram: $htmlFullPath"
        @{ Map = $map; Title = $mapTitle }
    }

    # --- At the prompt: tiles, hubs and their spokes, findings --------------------------------------
    $map = $state.Map
    $stats = $map.Stats
    $glyph = Get-AACGlyph
    $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
    if (-not $stats.Networks -and -not $stats.VirtualHubs) {
        Write-AACMarkup '[grey58]No virtual networks were found in that scope; the diagram is empty.[/]'
    }
    else {
        Show-AACTileRow -Tile @(
            @{ Value = '{0:N0}' -f $stats.Networks; Caption = 'virtual networks'; Color = 'deepskyblue1' }
            @{ Value = '{0:N0}' -f $stats.Hubs; Caption = 'hubs'; Color = 'mediumpurple2' }
            @{ Value = '{0:N0}' -f $stats.Spokes; Caption = 'spokes'; Color = 'deepskyblue1' }
            @{ Value = '{0:N0}' -f $stats.Peerings; Caption = 'peerings'; Color = 'mediumpurple2' }
            @{ Value = '{0:N0}' -f ($stats.Firewalls + $stats.Appliances); Caption = 'firewalls and appliances'; Color = 'red1' }
            @{ Value = '{0:N0}' -f $stats.Gateways; Caption = 'gateways'; Color = 'gold1' }
        )
        [Spectre.Console.AnsiConsole]::WriteLine()
        $vnets = @($map.Clusters | Where-Object { $_.kind -eq 'vnet' })
        $hubs = @($vnets | Where-Object { $_.role -eq 'hub' } | Sort-Object -Property { $_.name })
        if ($hubs.Count) {
            $table = [Spectre.Console.Table]::new()
            $table.Border = [Spectre.Console.TableBorder]::Rounded
            $table.BorderStyle = [Spectre.Console.Style]::Parse('mediumpurple2')
            $table.Title = [Spectre.Console.TableTitle]::new("[bold mediumpurple2]$($glyph.Bullet) Hubs and their spokes[/]")
            foreach ($header in 'Hub', 'Where', 'Transit', 'Spokes') { $null = $table.AddColumn([Spectre.Console.TableColumn]::new("[grey62]$header[/]")) }
            foreach ($hub in $hubs) {
                $inside = @($map.Nodes | Where-Object { $_.parent -and ($_.parent -eq $hub.id -or $_.parent -like "$($hub.id)/subnets/*") -and ($_.type -in 'microsoft.network/azurefirewalls', 'microsoft.network/virtualnetworkgateways', 'microsoft.network/vpngateways', 'microsoft.network/expressroutegateways' -or $_.nva) } | ForEach-Object { "$($_.name) ($($_.typeLabel))" })
                $spokes = @($vnets | Where-Object { $_.role -eq 'spoke' -and $_.hub -eq $hub.id } | ForEach-Object { $_.name } | Sort-Object)
                $cells = @(
                    "[bold]$(& $escape $hub.name)[/]$(if ($hub.external) { ' [grey50](outside the scope)[/]' })"
                    "[grey70]$(& $escape $hub.context)[/]"
                    $(if ($inside.Count) { & $escape ($inside -join ', ') } else { '[grey50]-[/]' })
                    "[deepskyblue1]$($spokes.Count)[/] [grey58]$(& $escape (($spokes | Select-Object -First 8) -join ', '))$(if ($spokes.Count -gt 8) { ", +$($spokes.Count - 8) more" })[/]"
                )
                [Spectre.Console.TableExtensions]::AddRow($table, [Spectre.Console.Rendering.IRenderable[]]@($cells | ForEach-Object { [Spectre.Console.Markup]::new($_) })) | Out-Null
            }
            [Spectre.Console.AnsiConsole]::Write($table)
            [Spectre.Console.AnsiConsole]::WriteLine()
        }
        $findings = @($map.Findings)
        if ($findings.Count) {
            $colors = @{ High = 'red1'; Medium = 'orange1'; Info = 'grey62' }
            Write-AACMarkup "[bold]Findings[/] [grey58]($($findings.Count))[/]"
            foreach ($group in @($findings | Group-Object -Property Severity, Finding)) {
                $first = $group.Group[0]
                $names = @($group.Group | ForEach-Object { $_.Resource } | Select-Object -Unique)
                Write-AACMarkup "  [$($colors[$first.Severity])]$($first.Severity.ToUpperInvariant())[/] $(& $escape $first.Finding) [grey58]($($group.Count)): $(& $escape (($names | Select-Object -First 6) -join ', '))$(if ($names.Count -gt 6) { ", +$($names.Count - 6) more" })[/]"
            }
            [Spectre.Console.AnsiConsole]::WriteLine()
        }
    }
    if (-not $NoBrowser) {
        Open-AACFile -Path $htmlFullPath
        Write-AACMarkup '[grey58]Opened in your browser: switch between Hub & spoke and Hierarchy at the top; Save PNG, JPEG or SVG there too.[/]'
    }
    else { Write-AACMarkup "[grey58]Diagram: $(& $escape $htmlFullPath)[/]" }

    if ($PassThru) {
        [pscustomobject]@{
            PSTypeName = 'AAC.NetworkTopology'
            Title      = $state.Title
            Path       = $htmlFullPath
            Networks   = @($map.Clusters | Where-Object { $_.kind -eq 'vnet' } | ForEach-Object {
                    $hubId = $_.hub
                    [pscustomobject]@{
                        PSTypeName = 'AAC.NetworkTopologyNetwork'
                        Name = $_.name; Role = $_.role; Hub = $(if ($_.hub) { (@($map.Clusters | Where-Object { $_.id -eq $hubId } | ForEach-Object { $_.name }) | Select-Object -First 1) } else { '' }); Peerings = [int]$_.peerCount
                        Where = $_.context; AddressSpace = (@($_.detail | Where-Object { $_ -match '\d+\.\d+\.\d+\.\d+/' }) | Select-Object -First 1); Outside = [bool]$_.external; Id = $_.id
                    }
                })
            Findings   = @($map.Findings)
            Nodes      = @($map.Nodes | ForEach-Object { [pscustomobject]@{ Name = $_.name; Type = $_.type; Product = $_.typeLabel; Appliance = [bool]$_.nva; Parent = $_.parent; Details = ($_.facts -join ' · '); Outside = $_.external; Id = $_.id } })
            Edges      = @($map.Edges | ForEach-Object { [pscustomobject]@{ Kind = $_.kind; Source = $_.source; Target = $_.target; Label = $_.label; Warning = [bool]$_.warn } })
            Stats      = [pscustomobject]$stats
        }
    }
}
