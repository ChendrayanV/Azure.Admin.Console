function New-AACDesignDiagram {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Draws a hub and spoke design from a few parameters - the firewall, the
        spokes and the resources in them - as an editable draw.io diagram, with
        every subscription, resource group, virtual network and subnet named and
        each address range worked out.
    .DESCRIPTION
        Offline: nothing is read from Azure and nothing needs to exist, so a design
        can be drawn before there is a subscription for it. Export-AACDiagram draws
        what is already deployed; this draws what you are about to build.

        From the hub's address space, the spokes and the resources you name, it
        plans:
          Subnets      each network's subnets at the size Microsoft recommends for
                       what is in them (AzureFirewallSubnet /26, a delegated App
                       Service integration subnet, a private endpoint subnet...),
                       from the smallest it supports when the space is tight, with
                       their ranges, usable addresses and network security group
          Routing      with -Firewall, a route table per spoke sending 0.0.0.0/0
                       to the firewall's private IP
          Peering      every spoke to the hub, with gateway transit when there is
                       a VPN gateway
          Resources    named as {type}-{spoke}-{env}-{region} (storage accounts and
                       registries without hyphens): Web and Function Apps outside
                       the network with VNet integration and an App Service plan;
                       storage, Key Vault, SQL, Cosmos DB, Redis, Service Bus, Event
                       Hubs and registries behind private endpoints, with their
                       private DNS zones in the hub; VMs, AKS, Application Gateway
                       and API Management in subnets of their own
        Networks that overlap, or a network too small for its subnets, stop the
        command: a diagram of addresses that can't exist would mislead.

        A spoke is a name - it gets the next free /16 (10.1.0.0/16, 10.2.0.0/16...)
        and -Resource - or a hashtable for full control:
          @{ Name = 'orders'; AddressSpace = '10.10.0.0/20'; Resources = 'FunctionApp', 'StorageAccount'
             Subscription = 'sub-orders-prod'; ResourceGroup = 'rg-orders-prod'
             Subnets = @( @{ Name = 'snet-app'; AddressPrefix = '10.10.0.0/24'; Resources = 'FunctionApp' }
                          @{ Name = 'snet-pe'; AddressPrefix = '10.10.1.0/26'; Resources = 'StorageAccount' } ) }
        Subnets you give are kept as they are, and checked.

        The draw.io file has native containers (subscription > region > resource
        group > virtual network > subnet), Azure icons, attached connections and a
        Legend page: open it in draw.io (desktop, app.diagrams.net or the VS Code
        extension) and keep editing. Run it again with -Update after changing the
        parameters: your own changes to the diagram are kept. At the prompt you get
        the address plan; -CsvPath writes it, -PassThru returns it (AAC.DesignSubnet).

        -Design draws the network for a design from New-AACArchitectureDesign (the
        object, piped or given, or the JSON file its -OutPath saved): its region,
        its firewall, and the components this diagram has an icon and a subnet
        for go into one spoke (or each spoke you name). Components without one
        here - Front Door, monitoring, Azure OpenAI, AI Search... - are listed in
        a warning; New-AACArchitectureDiagram draws the whole design.
    .PARAMETER Name
        The design's name, for the title and the file name. With -Design, the
        design's own name when left out.
    .PARAMETER Spoke
        The spokes: names, or hashtables with Name and any of AddressSpace,
        Resources, Subscription, ResourceGroup and Subnets (see the description).
        With -Design, one spoke named workload when left out.
    .PARAMETER Design
        A design from New-AACArchitectureDesign - the object, or the JSON file
        it saved with -OutPath. Its components become the spoke's resources (in
        place of -Resource), its first region the -Region, and its firewall
        -Firewall. Pipe it: New-AACArchitectureDesign ... | New-AACDesignDiagram.
    .PARAMETER Resource
        The resources in a spoke given as a name: FunctionApp, WebApp,
        StorageAccount, KeyVault, SqlDatabase, CosmosDb, Redis, ServiceBus, EventHub,
        ContainerRegistry, VirtualMachine, Aks, ApplicationGateway, ApiManagement.
        Name one twice for two of it.
    .PARAMETER Firewall
        Put Azure Firewall in the hub, and route each spoke's traffic through it.
    .PARAMETER Bastion
        Put Azure Bastion in the hub.
    .PARAMETER VpnGateway
        Put a VPN gateway in the hub, connected to your on-premises network, and let
        the spokes use it through the peering.
    .PARAMETER HubAddressSpace
        The hub's address space. Default 10.0.0.0/22.
    .PARAMETER HubSubscription
        The hub's subscription name. Default sub-connectivity.
    .PARAMETER HubResourceGroup
        The hub's resource group. Default rg-hub-network-{env}-{region}.
    .PARAMETER Region
        The region. Default westeurope.
    .PARAMETER Environment
        The environment in the names: prod, dev... Default prod.
    .PARAMETER Path
        The draw.io file. Default .\<Name>-design.drawio.
    .PARAMETER Update
        Redraw the diagram at -Path and keep the changes you made to it: what is new
        is added and marked, what is gone is faded.
    .PARAMETER Force
        Replace an existing file at -Path.
    .PARAMETER Open
        Open the diagram when it is written, in the app your computer uses for
        draw.io files.
    .PARAMETER HtmlPath
        Also write the design as an interactive page.
    .PARAMETER PdfPath
        Also write the design as a one-page PDF (needs Microsoft Edge or Chrome).
    .PARAMETER CsvPath
        Write the address plan to this CSV file.
    .PARAMETER Title
        The diagram's title.
    .PARAMETER PassThru
        Show the plan and also return the subnets.
    .PARAMETER NoDisplay
        Return the subnets without showing the plan.
    .PARAMETER NoPaging
        Show the whole plan at once.
    .EXAMPLE
        New-AACDesignDiagram -Name contoso -Firewall -Bastion -Spoke orders, payments -Resource FunctionApp, WebApp, StorageAccount, KeyVault -Open
        A hub with a firewall and Bastion, two spokes with the same four resources, opened in draw.io.
    .EXAMPLE
        New-AACDesignDiagram -Name contoso -Firewall -VpnGateway -HubAddressSpace 10.100.0.0/22 -Spoke @(
            @{ Name = 'orders'; AddressSpace = '10.110.0.0/20'; Resources = 'FunctionApp', 'StorageAccount', 'ServiceBus'; Subscription = 'sub-orders-prod' }
            @{ Name = 'web'; AddressSpace = '10.120.0.0/20'; Resources = 'ApplicationGateway', 'WebApp', 'SqlDatabase' }
        ) -Path .\contoso.drawio -CsvPath .\contoso-ip-plan.csv
        Spokes with their own ranges, resources and subscription, and the address plan as CSV.
    .EXAMPLE
        New-AACDesignDiagram -Name contoso -Firewall -Spoke orders -Resource FunctionApp, StorageAccount -Path .\contoso.drawio -Update
        Redraws the diagram you edited, keeping your changes.
    .EXAMPLE
        New-AACArchitectureDesign -BriefPath .\brief.json -Offline | New-AACDesignDiagram -Bastion -Open
        The network for an architecture design: its components in a spoke, its firewall in the hub.
    .OUTPUTS
        AAC.DesignSubnet (with -PassThru or -NoDisplay, or piped onward)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('AAC.DesignSubnet')]
    param(
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9-]{0,30}$')]
        [string] $Name,

        [ValidateNotNullOrEmpty()]
        [object[]] $Spoke,

        [Parameter(ValueFromPipeline)]
        [ValidateNotNull()]
        [object] $Design,

        [ValidateSet('FunctionApp', 'WebApp', 'StorageAccount', 'KeyVault', 'SqlDatabase', 'CosmosDb', 'Redis', 'ServiceBus', 'EventHub', 'ContainerRegistry', 'VirtualMachine', 'Aks', 'ApplicationGateway', 'ApiManagement')]
        [string[]] $Resource = @(),

        [switch] $Firewall,

        [switch] $Bastion,

        [switch] $VpnGateway,

        [string] $HubAddressSpace = '10.0.0.0/22',

        [string] $HubSubscription = 'sub-connectivity',

        [string] $HubResourceGroup,

        [ValidatePattern('^[a-z0-9]+$')]
        [string] $Region = 'westeurope',

        [ValidatePattern('^[A-Za-z0-9]{1,8}$')]
        [string] $Environment = 'prod',

        [string] $Path,

        [switch] $Update,

        [switch] $Force,

        [switch] $Open,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $CsvPath,

        [string] $Title,

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    # One design (or one set of parameters) per run; piped designs each draw their own.
    process {

        trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

        $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
        $interactive = -not $NoDisplay -and -not $pipedOnward
        $resolve = { param([string] $Target) if ($Target) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Target) } }
        # A design from New-AACArchitectureDesign: its components, region and firewall
        # stand in for -Resource, -Region and -Firewall.
        $useFirewall = [bool]$Firewall
        if ($PSBoundParameters.ContainsKey('Design')) {
            $source = $Design
            if ($source -is [string]) {
                $file = & $resolve $source
                if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Azure Admin Console can't find the design file $file. Give -Design the JSON file New-AACArchitectureDesign -OutPath saved, or the design itself." }
                $source = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
            }
            if (-not $source.PSObject.Properties['Nodes']) { throw 'Azure Admin Console needs -Design to be a design from New-AACArchitectureDesign (with its Nodes), or the JSON file it saved.' }
            $designRegions = @(if ($source.PSObject.Properties['Regions']) { @($source.Regions | Where-Object { $_ }) })
            if ($designRegions.Count -and -not $PSBoundParameters.ContainsKey('Region')) {
                $Region = ([string]$designRegions[0]).ToLowerInvariant() -replace '[^a-z0-9]', ''
            }
            if (-not $Name) {
                $designName = if ($source.PSObject.Properties['Name']) { ([string]$source.Name).ToLowerInvariant() -replace '[^a-z0-9]+', '-' } else { '' }
                $designName = $designName.Trim('-')
                if ($designName.Length -gt 31) { $designName = $designName.Substring(0, 31).TrimEnd('-') }
                $Name = if ($designName) { $designName } else { 'design' }
            }
            # By resource type: the most specific first (a function app is also Microsoft.Web/sites).
            $byType = [ordered]@{
                '^microsoft\.web/sites \(functionapp\)' = 'FunctionApp'; '^microsoft\.web/sites$' = 'WebApp'; '^microsoft\.storage/storageaccounts' = 'StorageAccount'
                '^microsoft\.keyvault/vaults' = 'KeyVault'; '^microsoft\.sql/servers' = 'SqlDatabase'; '^microsoft\.documentdb/' = 'CosmosDb'; '^microsoft\.cache/redis' = 'Redis'
                '^microsoft\.servicebus/' = 'ServiceBus'; '^microsoft\.eventhub/' = 'EventHub'; '^microsoft\.containerregistry/' = 'ContainerRegistry'
                '^microsoft\.compute/virtualmachines' = 'VirtualMachine'; '^microsoft\.containerservice/' = 'Aks'; '^microsoft\.network/applicationgateways' = 'ApplicationGateway'
                '^microsoft\.apimanagement/' = 'ApiManagement'
            }
            $mapped = [System.Collections.Generic.List[string]]::new()
            $skipped = [System.Collections.Generic.List[string]]::new()
            $firstRegion = if ($designRegions.Count) { [string]$designRegions[0] } else { '' }
            foreach ($node in @($source.Nodes | Where-Object { $_ })) {
                # One region only: a second region's copies would be the same spoke again.
                if ($firstRegion -and $node.PSObject.Properties['Region'] -and $node.Region -and [string]$node.Region -ne $firstRegion) { continue }
                $type = ([string]$node.Service).ToLowerInvariant()
                if ($type -match '^microsoft\.network/azurefirewalls') { $useFirewall = $true; continue }
                # The networks and DNS zones are what this diagram draws anyway.
                if ($type -match '^microsoft\.network/(virtualnetworks|privatednszones)') { continue }
                $key = @($byType.Keys | Where-Object { $type -match $_ } | ForEach-Object { $byType[$_] })
                if ($key.Count) { $mapped.Add($key[0]) } else { $skipped.Add([string]$node.Name) }
            }
            if ($skipped.Count) { Write-Warning "The design's $(@($skipped | Select-Object -Unique) -join ', ') aren't part of a hub-and-spoke network diagram, so they aren't drawn. New-AACArchitectureDiagram draws the whole design." }
            if (-not $PSBoundParameters.ContainsKey('Resource')) { $Resource = $mapped.ToArray() }
            if (-not $Spoke) { $Spoke = @('workload') }
        }
        if (-not $Name) { throw 'Azure Admin Console needs -Name (or -Design, which brings its own).' }
        if (-not $Spoke) { throw 'Azure Admin Console needs -Spoke: the names of the spokes, or hashtables (see Get-Help New-AACDesignDiagram -Full). Or give -Design.' }

        $code = Get-AACRegionCode -Region $Region
        $stage = $Environment.ToLowerInvariant()
        $known = @((Get-AACDesignResource).Keys)
        $checkResources = {
            param([object[]] $Names, [string] $Where)
            foreach ($item in @($Names | Where-Object { $_ })) {
                if ([string]$item -notin $known) { throw "Azure Admin Console doesn't know the resource '$item' in $Where. Use one of: $($known -join ', ')." }
            }
            # As the catalogue spells them, whatever case they were typed in.
            @($Names | Where-Object { $_ } | ForEach-Object { $text = [string]$_; @($known | Where-Object { $_ -ieq $text })[0] })
        }

        # The spokes: a name takes the next free /16 and -Resource; a hashtable says what it wants.
        $next = 1
        $spokes = @(foreach ($entry in $Spoke) {
                if ($entry -is [string]) { $entry = @{ Name = $entry } }
                if ($entry -isnot [System.Collections.IDictionary]) { throw "Azure Admin Console needs each spoke to be a name or a hashtable, not $($entry.GetType().Name). See Get-Help New-AACDesignDiagram -Full." }
                $unknown = @($entry.Keys | Where-Object { $_ -notin 'Name', 'AddressSpace', 'Resources', 'Resource', 'Subscription', 'ResourceGroup', 'Subnets' })
                if ($unknown.Count) { throw "Azure Admin Console doesn't know the spoke setting(s) $($unknown -join ', '). Use Name, AddressSpace, Resources, Subscription, ResourceGroup and Subnets." }
                $spokeName = [string]$entry['Name']
                if ($spokeName -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{0,20}$') { throw "Azure Admin Console needs each spoke to have a Name of letters, digits and hyphens (up to 21), not '$spokeName'." }
                $given = if ($entry.Contains('Resources')) { $entry['Resources'] } elseif ($entry.Contains('Resource')) { $entry['Resource'] } elseif (@($entry['Subnets'] | Where-Object { $_ }).Count) { @($entry['Subnets'] | Where-Object { $_ } | ForEach-Object { $_['Resources'] }) } else { $Resource }
                $subnets = @(foreach ($subnet in @($entry['Subnets'] | Where-Object { $_ })) {
                        if ($subnet -isnot [System.Collections.IDictionary] -or -not $subnet['Name'] -or -not $subnet['AddressPrefix']) { throw "Azure Admin Console needs each subnet of spoke '$spokeName' to be a hashtable with Name and AddressPrefix (and Resources)." }
                        @{ Name = [string]$subnet['Name']; AddressPrefix = [string]$subnet['AddressPrefix']; Resources = @(& $checkResources @($subnet['Resources']) "subnet '$($subnet['Name'])' of spoke '$spokeName'") }
                    })
                $space = if ($entry['AddressSpace']) { [string]$entry['AddressSpace'] } else { "10.$next.0.0/16" }
                $next++
                @{
                    Name          = $spokeName
                    AddressSpace  = $space
                    Resources     = @(& $checkResources @($given) "spoke '$spokeName'")
                    Subscription  = $(if ($entry['Subscription']) { [string]$entry['Subscription'] } else { "sub-$($spokeName.ToLowerInvariant())-$stage" })
                    ResourceGroup = $(if ($entry['ResourceGroup']) { [string]$entry['ResourceGroup'] } else { "rg-$($spokeName.ToLowerInvariant())-$stage-$code" })
                    Subnets       = $subnets
                }
            })
        if (@($spokes.Name | Group-Object | Where-Object Count -GT 1).Count) { throw 'Azure Admin Console needs each spoke to have a name of its own.' }
        $hub = @{
            AddressSpace = $HubAddressSpace; Subscription = $HubSubscription; Firewall = $useFirewall; Bastion = [bool]$Bastion; VpnGateway = [bool]$VpnGateway
            ResourceGroup = $(if ($HubResourceGroup) { $HubResourceGroup } else { "rg-hub-network-$stage-$code" })
        }
        $fullPath = & $resolve $(if ($Path) { $Path } else { ".\$Name-design.drawio" })
        if ($fullPath -notmatch '\.drawio$') { throw "Azure Admin Console writes draw.io files: give -Path a name ending in .drawio, not $fullPath." }
        $exists = Test-Path -LiteralPath $fullPath
        if ($exists -and -not $Update -and -not $Force) { throw "Azure Admin Console didn't replace $fullPath, which already exists. Use -Update to redraw it and keep your changes, -Force to replace it, or another -Path." }

        $plan = ConvertTo-AACDesignNetwork -Name $Name -Region $Region -Environment $Environment -Hub $hub -Spoke $spokes
        $diagramTitle = if ($Title) { $Title } else { "$Name - hub and spoke design" }
        $asset = Get-AACResourceMapAsset
        $drawn = ConvertTo-AACDrawio -Map $plan.Map -Icons $asset.Icons -Title $diagramTitle -Fact $plan.Facts -Legend
        $xml = $drawn.Xml
        $merge = $null
        if ($Update -and $exists) {
            $merge = Merge-AACDrawio -Existing ([System.IO.File]::ReadAllText($fullPath)) -Generated $xml
            $xml = $merge.Xml
        }
        # -WhatIf plans and shows the design, and writes nothing.
        $written = $PSCmdlet.ShouldProcess($fullPath, 'Write the design diagram')
        if ($written) {
            $folder = Split-Path -Parent $fullPath
            if ($folder -and -not (Test-Path -LiteralPath $folder)) { $null = New-Item -ItemType Directory -Path $folder -Force }
            [System.IO.File]::WriteAllText($fullPath, $xml, [System.Text.UTF8Encoding]::new($false))
            $look = @{ Map = $plan.Map; Title = $diagramTitle; Fact = $plan.Facts; Theme = 'light'; Layout = 'packed'; Hierarchy = 'packed' }
            if ($HtmlPath) { Write-AACResourceMapHtml @look -Path (& $resolve $HtmlPath) }
            if ($PdfPath) { Write-AACResourceMapPdf @look -Path (& $resolve $PdfPath) }
        }

        $subnets = @($plan.Subnets)
        $report = @{
            Subtitle = 'A hub and spoke design, planned: the networks, their subnets and address ranges, and the resources in them'
            Facts    = [ordered]@{ Design = "$Name ($stage, $Region)"; Diagram = $fullPath; Hub = "$($HubAddressSpace)$(if ($Firewall) { ', Azure Firewall' })$(if ($Bastion) { ', Bastion' })$(if ($VpnGateway) { ', VPN gateway' })"; Spokes = (@($spokes | ForEach-Object { "$($_.Name) $($_.AddressSpace)" }) -join '; ') }
            Status   = 'Success'
            Headline = "$(@($subnets.VirtualNetwork | Select-Object -Unique).Count) network(s), $($subnets.Count) subnet(s) and $(@($plan.Resources).Count) resource(s) drawn in $(Split-Path -Leaf $fullPath)$(if ($merge) { ", keeping your changes ($($merge.Added) added, $($merge.Removed) gone)" })."
            Tiles    = @(
                @{ Value = '{0:N0}' -f @($subnets.VirtualNetwork | Select-Object -Unique).Count; Label = 'virtual networks'; Tone = 'info'; Table = 'subnets' }
                @{ Value = '{0:N0}' -f $subnets.Count; Label = 'subnets'; Tone = 'info'; Table = 'subnets' }
                @{ Value = '{0:N0}' -f @($plan.Resources).Count; Label = 'resources'; Tone = 'info'; Table = 'resources' }
                @{ Value = '{0:N0}' -f (($subnets | Measure-Object -Property Usable -Sum).Sum); Label = 'usable addresses in subnets'; Tone = 'good'; Table = 'subnets' }
            )
            Tables   = @(
                @{ Id = 'subnets'; Title = 'Address plan'; Section = 'Plan'; Rows = $subnets; Noun = 'subnets'; GroupBy = @('VirtualNetwork', 'Subscription'); ConsoleLimit = 40
                    Columns = @(
                        @{ Key = 'VirtualNetwork'; Label = 'Virtual network'; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Subnet'; Label = 'Subnet'; Console = $true; Pdf = $true }
                        @{ Key = 'AddressPrefix'; Label = 'Range'; Type = 'mono'; Console = $true; Pdf = $true }
                        @{ Key = 'Usable'; Label = 'Usable'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                        @{ Key = 'RouteTable'; Label = 'Route table'; Console = $true }
                        @{ Key = 'NextHop'; Label = 'Next hop'; Type = 'mono' }
                        @{ Key = 'NetworkSecurityGroup'; Label = 'NSG' }
                        @{ Key = 'Purpose'; Label = 'For'; Type = 'wide' }
                        @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                        @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                    ) }
                @{ Id = 'resources'; Title = 'Resources'; Section = 'Plan'; Rows = @($plan.Resources); Noun = 'resources'; GroupBy = @('Network', 'Kind'); ConsoleLimit = 40
                    Columns = @(
                        @{ Key = 'Name'; Label = 'Name'; Console = $true; Pdf = $true }
                        @{ Key = 'Kind'; Label = 'Kind'; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Access'; Label = 'Reached through'; Console = $true; Pdf = $true }
                        @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                        @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                    ) }
            )
            Hint     = 'Open the .drawio file in draw.io to edit it; -Update redraws it after a change and keeps your edits; -CsvPath writes the address plan.'
        }
        Invoke-AACReportOutput -Report $report -Title $diagramTitle -CsvObject $subnets -Noun 'subnet' -CsvPath (& $resolve $CsvPath) -ShowView:$interactive -NoPaging:$NoPaging -Object $subnets -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
        if ($Open -and $written) { Invoke-Item -LiteralPath $fullPath }
    }
}
