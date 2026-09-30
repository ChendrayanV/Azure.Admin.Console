function Show-AACResourceMap {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Draws a map of the resources in one or more resource groups - with
        their connections, dependencies and network paths - and opens it in
        your browser, ready to save as a PNG or JPEG image.
    .DESCRIPTION
        Reads the resources with Azure Resource Graph (Reader access is
        enough; no Az modules) and draws them with their official Azure icons,
        laid out by the Eclipse Layout Kernel (ELK), in boxes:

          subscription > resource group > virtual network > subnet

        A network interface, private endpoint, firewall, gateway, Bastion,
        internal load balancer, AKS cluster or API Management service is drawn
        in the subnet it has an IP in, and a virtual machine in the subnet of
        its first network interface. Each resource shows its name, its
        product, and a detail worth seeing: a VM's size, an IP address, a
        disk's size.

        The lines between them come from the resource IDs in each resource's
        properties, typed by what they are:
          Network association   NICs, IPs, subnets, NSGs, route tables, NAT,
                                gateways, VNet integration
          Resource dependency   an app on its plan, a VM on its disks, a
                                database on its server, a diagnostic target
          VNet peering          with its state
          Private link          a private endpoint to the resource it serves
          Route (next hop)      a route table to the firewall or appliance
                                its routes send traffic to
          Private DNS link      a private DNS zone linked to a network
        NSGs and route tables are drawn the way a network engineer reads them:
        as chips on the subnets and NICs they are applied to (-NsgView Cards
        draws them as resources with lines instead). Click one for its rules
        or routes. A chip is red when it opens a management or database port
        (SSH, RDP, WinRM, SMB, SQL, ...) or every port to the internet, or
        when a route's next hop is an IP no resource you can see has; amber
        for a wide port range open to the internet, or 0.0.0.0/0 straight to
        the internet. A subnet's routes are drawn from the subnet ("0.0.0.0/0
        via rt-spoke") to the firewall or appliance they go through - looked
        up across every subscription you can see, so a spoke's map reaches
        the hub's firewall. Each subnet's box also shows how many of its
        addresses are used and what it's delegated to, and each peering what
        it lets through (forwarded traffic, gateway transit, remote gateway).

        A resource outside the chosen resource groups that a chosen one uses
        - a VNet in the hub's resource group, say - is drawn too, in its own
        resource group's box, marked as outside the selection. Resources
        attached to nothing (a network interface without a VM, a public IP
        without a configuration, an unattached disk, an NSG or route table on
        nothing) are flagged.

        The map is one self-contained HTML file, written to -HtmlPath (a file
        in your temp folder by default) and opened in your default browser.
        In the browser you can:
          - pan and zoom, and fit the map to the window
          - click a resource or box: its connections light up and the rest
            fades, with its details, connections and an Azure portal link
          - find a resource by name, type, IP or resource group
          - switch between left to right and top to bottom, and the Dark,
            Light and Blueprint themes
          - show or hide each kind of connection
          - save the map as a PNG or JPEG image (or SVG), as drawn

        The Azure icons are Microsoft's Azure architecture icons, used under
        Microsoft's terms for architecture diagrams (lib\azure-icons\SOURCES.md).
    .PARAMETER SubscriptionId
        The subscriptions to map. With -ResourceGroupName, the resource groups
        are looked for in these subscriptions; alone, every resource group in
        them is mapped.
    .PARAMETER ResourceGroupName
        The resource groups to map. Without -SubscriptionId they are looked
        for in every subscription you can see.
    .PARAMETER Direction
        How the map flows: LeftToRight (the default) or TopToBottom. The page
        can switch it too.
    .PARAMETER Theme
        Dark (the default), Light or Blueprint. The page can switch it too.
    .PARAMETER NsgView
        Chips (the default): NSGs and route tables as chips on the subnets
        and NICs they're applied to. Cards: as resources, with lines to them.
        The page can switch it too.
    .PARAMETER ExcludeType
        Resource types to leave out, e.g. 'microsoft.insights/*' for alerts
        and action groups; wildcards work.
    .PARAMETER HtmlPath
        Where to write the map. By default a file in your temp folder.
    .PARAMETER Title
        The map's title. By default, the resource groups (or subscriptions).
    .PARAMETER NoBrowser
        Write the map without opening it.
    .PARAMETER PassThru
        Also return the map: its boxes, resources and connections, and the
        file's path.
    .EXAMPLE
        Connect-AAC
        Show-AACResourceMap -SubscriptionId '00000000-0000-0000-0000-000000000000' -ResourceGroupName 'rg-app'
        One resource group's map, opened in the browser.
    .EXAMPLE
        Show-AACResourceMap -SubscriptionId $hub, $spoke -ResourceGroupName 'rg-hub', 'rg-spoke-app', 'rg-spoke-data' -Direction TopToBottom
        A hub-and-spoke network across two subscriptions, top to bottom.
    .EXAMPLE
        Show-AACResourceMap -ResourceGroupName 'rg-app' -Theme Light -HtmlPath .\out\rg-app-map.html -NoBrowser
        A light-themed map written to a file, not opened.
    .EXAMPLE
        (Show-AACResourceMap -ResourceGroupName 'rg-app' -NoBrowser -PassThru).Nodes | Where-Object Orphan
        The resources attached to nothing.
    .OUTPUTS
        AAC.ResourceMap, with -PassThru
    #>
    [CmdletBinding()]
    [OutputType('AAC.ResourceMap')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [ValidateNotNullOrEmpty()]
        [string[]] $ResourceGroupName,

        [ValidateSet('LeftToRight', 'TopToBottom')]
        [string] $Direction = 'LeftToRight',

        [ValidateSet('Dark', 'Light', 'Blueprint')]
        [string] $Theme = 'Dark',

        [ValidateSet('Chips', 'Cards')]
        [string] $NsgView = 'Chips',

        [SupportsWildcards()]
        [string[]] $ExcludeType,

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

    if (-not $SubscriptionId -and -not $ResourceGroupName) {
        throw 'Say what to map: -SubscriptionId, -ResourceGroupName, or both.'
    }
    $htmlFullPath = if ($HtmlPath) {
        $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($HtmlPath)
    }
    else {
        Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('AAC-ResourceMap-{0:yyyyMMdd-HHmmss}.html' -f (Get-Date))
    }
    $quote = { param([string] $Text) "'" + ($Text -replace '\\', '\\' -replace "'", "\'") + "'" }

    # Resource Graph queries, several at once (Invoke-AACGraphBatch): rows
    # as hashtables (tags whose keys differ only by case are fine).
    $graph = {
        param([System.Collections.IDictionary] $Query, [string[]] $Subscriptions)
        (Invoke-AACGraphBatch -Query $Query -SubscriptionId $Subscriptions).Rows
    }
    $columns = '| project id, name, type, kind, location, resourceGroup, subscriptionId, sku, properties, tags'

    Write-AACRule -Title 'Azure Admin Console :: Resource map' -Color 'deepskyblue3_1'
    $state = Invoke-AACProgress -ScriptBlock {
        $null = Get-AACAccessToken
        $asset = Get-AACResourceMapAsset

        # --- What to map ------------------------------------------------------------------------
        Update-AACProgress -Id 'scope' -Description 'Finding the subscriptions and resource groups' -Indeterminate
        # The subscriptions, resource groups and resources together.
        $groupFilter = if ($ResourceGroupName) { " and resourceGroup in~ ($((@($ResourceGroupName | ForEach-Object { & $quote $_ })) -join ', '))" } else { '' }
        $read = & $graph ([ordered]@{
                subscriptions = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions' | project subscriptionId, name"
                groups        = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions/resourcegroups'$($groupFilter -replace 'resourceGroup', 'name') | project name, subscriptionId"
                resources     = "resources | where isnotempty(resourceGroup)$groupFilter $columns"
            }) $SubscriptionId
        $subscriptionNames = @{}
        foreach ($row in @($read['subscriptions'])) {
            $subscriptionNames[([string]$row['subscriptionId']).ToLowerInvariant()] = [string]$row['name']
        }
        $groups = @($read['groups'])
        if ($ResourceGroupName) {
            $missing = @($ResourceGroupName | Where-Object { $name = $_; -not @($groups | Where-Object { [string]$_['name'] -eq $name }).Count })
            if ($missing.Count -eq $ResourceGroupName.Count) {
                throw "No resource group named $(($missing | ForEach-Object { "'$_'" }) -join ', ') was found$(if ($SubscriptionId) { " in subscription $($SubscriptionId -join ', ')" } else { ' in any subscription you can see' })."
            }
            foreach ($name in $missing) { Write-Warning "No resource group named '$name' was found; the map leaves it out." }
        }
        Update-AACProgress -Id 'scope' -Complete -Description ('Found {0} resource group(s) in {1} subscription(s)' -f $groups.Count, @($groups | ForEach-Object { $_['subscriptionId'] } | Sort-Object -Unique).Count)

        # --- The resources, and those outside the selection they use ----------------------------
        Update-AACProgress -Id 'read' -Description 'Reading the resources from Azure Resource Graph' -Indeterminate
        $resources = @($read['resources'])
        $known = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($row in $resources) { [void]$known.Add([string]$row['id']) }
        $referenced = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($row in $resources) {
            $text = ConvertTo-Json -InputObject $row['properties'] -Depth 30 -Compress
            foreach ($match in [regex]::Matches($text, '(?i)/subscriptions/[^/"]+/resourcegroups/[^/"]+/providers/[^/"]+/[^/"]+/[^/"]+')) {
                if (-not $known.Contains($match.Value)) { [void]$referenced.Add($match.Value) }
            }
        }
        # Those outside it, 200 IDs a query, the queries at once.
        $external = [System.Collections.Generic.List[object]]::new()
        $ids = @($referenced)
        $chunks = [ordered]@{}
        for ($i = 0; $i -lt $ids.Count; $i += 200) {
            $chunk = $ids[$i..([Math]::Min($i + 199, $ids.Count - 1))]
            $chunks["chunk$i"] = "resources | where id in~ ($((@($chunk | ForEach-Object { & $quote $_ })) -join ', ')) $columns"
        }
        if ($chunks.Count) {
            $read = & $graph $chunks @()
            foreach ($name in @($chunks.Keys)) { foreach ($row in @($read[$name])) { $external.Add($row) } }
        }
        # Route next hops (a firewall or appliance IP) that nothing read so far
        # has: look for their owner in every subscription, so a spoke's routes
        # reach the hub's firewall.
        $owned = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($row in @($resources) + @($external)) {
            foreach ($match in [regex]::Matches((ConvertTo-Json -InputObject $row['properties'] -Depth 30 -Compress), '"privateIPAddress":"([^"]+)"')) { [void]$owned.Add($match.Groups[1].Value) }
        }
        $hops = @(foreach ($row in $resources) {
                if ([string]$row['type'] -ne 'microsoft.network/routetables' -and [string]$row['type'] -ne 'Microsoft.Network/routeTables') { continue }
                foreach ($match in [regex]::Matches((ConvertTo-Json -InputObject $row['properties'] -Depth 30 -Compress), '"nextHopIpAddress":"([^"]+)"')) { $match.Groups[1].Value }
            }) | Where-Object { $_ -and -not $owned.Contains($_) } | Select-Object -Unique
        if ($hops) {
            $types = "'microsoft.network/azurefirewalls', 'microsoft.network/networkinterfaces', 'microsoft.network/loadbalancers', 'microsoft.network/applicationgateways'"
            $filter = (@($hops | ForEach-Object { "properties contains $(& $quote $_)" })) -join ' or '
            foreach ($row in @((& $graph @{ hops = "resources | where type in~ ($types) | where $filter $columns" } @())['hops'])) {
                if (-not $known.Contains([string]$row['id']) -and -not @($external | Where-Object { [string]$_['id'] -eq [string]$row['id'] }).Count) { $external.Add($row) }
            }
        }
        Update-AACProgress -Id 'read' -Complete -Description ('Read {0:N0} resource(s), and {1:N0} outside the selection they use' -f $resources.Count, $external.Count)

        # --- The map ------------------------------------------------------------------------------
        Update-AACProgress -Id 'map' -Description 'Working out the connections and network paths' -Indeterminate
        $labels = @{}
        foreach ($key in $asset.Icons.icons.Keys) { $labels[$key] = [string]$asset.Icons.icons[$key].label }
        $map = ConvertTo-AACResourceMap -Resource $resources -External $external.ToArray() -SubscriptionName $subscriptionNames -IconType $asset.Icons.types -IconLabel $labels -ExcludeType @($ExcludeType | Where-Object { $_ })
        Update-AACProgress -Id 'map' -Complete -Description ('Mapped {0:N0} resource(s) and {1:N0} connection(s)' -f $map.Stats.Resources, $map.Stats.Connections)

        $scopeText = if ($ResourceGroupName) { $ResourceGroupName -join ', ' } else { @($SubscriptionId | ForEach-Object { if ($subscriptionNames.Contains($_.ToLowerInvariant())) { $subscriptionNames[$_.ToLowerInvariant()] } else { $_ } }) -join ', ' }
        $mapTitle = if ($Title) { $Title } else { "Resource map: $scopeText" }
        $facts = @(
            '{0:N0} resources' -f $map.Stats.Resources
            '{0:N0} resource group(s)' -f $map.Stats.Groups
            '{0:N0} virtual network(s)' -f $map.Stats.Networks
            '{0:N0} connections' -f $map.Stats.Connections
            if ($map.Stats.Outside) { '{0:N0} outside the selection' -f $map.Stats.Outside }
            if ($map.Stats.Orphans) { '{0:N0} unattached' -f $map.Stats.Orphans }
            if ($map.Stats.Flagged) { '{0:N0} NSG / route table(s) flagged' -f $map.Stats.Flagged }
            "drawn $((Get-Date).ToString('d MMM yyyy HH:mm'))"
        )
        Update-AACProgress -Id 'html' -Description 'Writing the map' -Indeterminate
        Write-AACResourceMapHtml -Map $map -Path $htmlFullPath -Title $mapTitle -Fact $facts -Direction $(if ($Direction -eq 'TopToBottom') { 'DOWN' } else { 'RIGHT' }) -Theme $Theme.ToLowerInvariant() -NsgView $NsgView.ToLowerInvariant()
        Update-AACProgress -Id 'html' -Complete -Description "Map: $htmlFullPath"
        @{ Map = $map; Title = $mapTitle }
    }

    $map = $state.Map
    if ($map.Stats.Resources -eq 0) {
        Write-AACMarkup '[grey58]No resources were found in that selection; the map is empty.[/]'
    }
    else {
        $glyph = Get-AACGlyph
        $parts = @("[white]$($map.Stats.Resources)[/] resources", "[white]$($map.Stats.Connections)[/] connections")
        if ($map.Stats.Outside) { $parts += "[white]$($map.Stats.Outside)[/] outside the selection" }
        if ($map.Stats.Orphans) { $parts += "[orange1]$($map.Stats.Orphans) unattached[/]" }
        if ($map.Stats.Flagged) { $parts += "[red1]$($map.Stats.Flagged) NSG / route table(s) flagged[/]" }
        Write-AACMarkup "[grey58]$($parts -join " $($glyph.Dot) ")[/]"
    }
    if (-not $NoBrowser) {
        Open-AACFile -Path $htmlFullPath
        Write-AACMarkup '[grey58]Opened in your browser. Save PNG and Save JPEG are at the top of the page.[/]'
    }

    if ($PassThru) {
        [pscustomobject]@{
            PSTypeName = 'AAC.ResourceMap'
            Title      = $state.Title
            Path       = $htmlFullPath
            Clusters   = @($map.Clusters | ForEach-Object { [pscustomobject]$_ })
            Nodes      = @($map.Nodes | ForEach-Object {
                    [pscustomobject]@{
                        Name = $_.name; Type = $_.type; Product = $_.typeLabel; ResourceGroup = $_.resourceGroup; Subscription = $_.subscription
                        Location = $_.location; Parent = $_.parent; Details = ($_.facts -join ' · '); Orphan = $_.orphan; Outside = $_.external; Id = $_.id
                        Risk = $_.risk; AppliedTo = @($_.appliedTo); Rules = @($_.rules | ForEach-Object { [pscustomobject]$_ }); Routes = @($_.routes | ForEach-Object { [pscustomobject]$_ })
                    }
                })
            Edges      = @($map.Edges | ForEach-Object { [pscustomobject]@{ Kind = $_.kind; Source = $_.source; Target = $_.target; Label = $_.label } })
            Stats      = [pscustomobject]$map.Stats
        }
    }
}
