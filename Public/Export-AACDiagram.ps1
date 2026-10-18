function Export-AACDiagram {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Draws your existing Azure resources as an editable draw.io diagram -
        resources, the network topology or Application Gateways - with real
        containers, Azure icons and attached connections; -Update refreshes it
        from Azure and keeps the changes you made.
    .DESCRIPTION
        Reads Azure (read-only, Reader is enough) the way the map commands do
        and writes a .drawio file you open and edit in draw.io - the desktop
        app, app.diagrams.net, the Draw.io Integration for VS Code,
        Confluence - and export from there to Visio (.vsdx), PNG, SVG or PDF.

        -View chooses what is drawn:
          Resources           the resources in resource groups or
                              subscriptions, in subscription > resource group
                              > virtual network > subnet boxes, with their
                              connections: network links, peerings, private
                              endpoints, routes, DNS links and dependencies
                              (as Show-AACResourceMap)
          Network             the network topology of a tenant, management
                              groups, subscriptions or regions: hubs and
                              spokes, peerings, gateways, firewalls and
                              appliances (as Show-AACNetworkTopology)
          ApplicationGateway  each gateway's flow - listeners > rules >
                              backend settings > pools and targets - with
                              probes, WAF policies and health (as
                              Show-AACApplicationGatewayMap)

        In the diagram:
          - boxes are draw.io containers: move a box and what is in it moves
            with it; drag a resource into another box and it belongs there
          - resources carry the Azure icons (vector), their name and type;
            unattached ones are red, those outside the selection faded
          - connections are attached at both ends and follow what you move
          - each shape keeps its resource ID, type, location, resource group
            and subscription (Edit > Edit Data, or hover), and Ctrl+click
            opens it in the Azure portal
          - a Legend page shows the kinds of box and connection, what was
            read and when (-NoLegend leaves it out)
        -SplitBy puts each subscription, resource group, management group,
        region or gateway on a page of its own, for large estates.

        Edit it as you like - move, restyle, add notes, users, on-premises
        shapes - then refresh it with -Update: it reads Azure again and
        merges into the file:
          - what you moved, restyled or relabelled stays as you left it
          - new resources are added into their box (which grows to fit) and
            marked green until the next refresh
          - resources no longer in Azure are faded and red - or deleted, with
            -Prune
          - shapes and connections you added are left alone
        Without -Update an existing file is not overwritten unless you add
        -Force.

        To look at rather than edit - or to send to someone without draw.io -
        add a clean copy alongside:
          -HtmlPath  an interactive page, self-contained (opens offline): the
                     diagram laid out with a legend of its connections and
                     boxes, to pan, zoom, search and click for details
          -PdfPath   one page: the title and what was read, the whole diagram
                     and its legend, in vector so it stays sharp when zoomed
                     or printed (drawn by Microsoft Edge or Google Chrome,
                     headless)
        Both show what was read from Azure this time, on one page whatever
        -SplitBy says - not the changes you made in draw.io.
    .PARAMETER View
        Resources (the default), Network or ApplicationGateway.
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ResourceGroupName
        Only these resource groups (Resources and ApplicationGateway views).
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups (Network view).
    .PARAMETER Location
        Only these regions (Network view).
    .PARAMETER Name
        Only the gateways with these names; wildcards work (ApplicationGateway view).
    .PARAMETER GroupBy
        Network view: the boxes around the networks - ManagementGroup (the
        default), Subscription or Region.
    .PARAMETER NetworkOnly
        Network view: only the network fabric, without NICs, VMs, scale sets
        and private endpoints.
    .PARAMETER IncludeHealth
        ApplicationGateway view: run the live backend health check (30-90
        seconds per gateway) instead of reading health metrics.
    .PARAMETER ExcludeType
        Leave out these resource types (Resources and Network views); wildcards
        work, for example 'microsoft.compute/disks'.
    .PARAMETER Path
        The .drawio file to write - or, with -Update, to refresh.
    .PARAMETER SplitBy
        A page per Subscription, ResourceGroup, ManagementGroup, Region or
        Gateway; None (the default) for one page.
    .PARAMETER Update
        Refresh the diagram at -Path from Azure, keeping your changes.
    .PARAMETER Prune
        With -Update: delete the resources no longer in Azure instead of
        fading them.
    .PARAMETER NoLegend
        Leave out the Legend page.
    .PARAMETER Title
        The diagram's title (the page name, without -SplitBy).
    .PARAMETER Force
        Overwrite an existing file without -Update.
    .PARAMETER HtmlPath
        Also write the diagram as an interactive HTML page here, with its
        legend - a clean copy to view or share.
    .PARAMETER PdfPath
        Also write the diagram as a one-page PDF here, with its title, what
        was read and its legend. Needs Microsoft Edge or Google Chrome
        installed.
    .PARAMETER Open
        Open what was written: the diagram (in the app .drawio files open
        with), and the HTML page and PDF when you asked for them.
    .PARAMETER PassThru
        Return what was written: the paths, pages, shapes and connections
        (and, with -Update, what was kept, added and removed).
    .EXAMPLE
        Connect-AAC
        Export-AACDiagram -ResourceGroupName 'rg-hub', 'rg-spoke-app' -Path .\estate.drawio -Open
        Two resource groups as an editable diagram, opened in draw.io.
    .EXAMPLE
        Export-AACDiagram -View Network -ManagementGroupId 'mg-landingzones' -SplitBy Subscription -Path .\network.drawio
        The landing zones' network topology, a page per subscription.
    .EXAMPLE
        Export-AACDiagram -ResourceGroupName 'rg-hub', 'rg-spoke-app' -Path .\estate.drawio -Update
        Refreshes the diagram you edited: new resources added and marked, removed ones faded, your changes kept.
    .EXAMPLE
        Export-AACDiagram -View ApplicationGateway -ResourceGroupName 'rg-edge' -IncludeHealth -Path .\gateways.drawio
        The gateways' flows with live backend health.
    .EXAMPLE
        Export-AACDiagram -SubscriptionId $sub -Path .\estate.drawio -HtmlPath .\estate.html -PdfPath .\estate.pdf
        The editable diagram, plus a clean interactive page and a one-page PDF, each with a legend, to share.
    .OUTPUTS
        AAC.Diagram, with -PassThru
    #>
    [CmdletBinding()]
    [OutputType('AAC.Diagram')]
    param(
        [ValidateSet('Resources', 'Network', 'ApplicationGateway')]
        [string] $View = 'Resources',

        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [ValidateNotNullOrEmpty()]
        [string[]] $ResourceGroupName,

        [ValidateNotNullOrEmpty()]
        [string[]] $ManagementGroupId,

        [ValidateNotNullOrEmpty()]
        [string[]] $Location,

        [SupportsWildcards()]
        [string[]] $Name,

        [ValidateSet('ManagementGroup', 'Subscription', 'Region')]
        [string] $GroupBy = 'ManagementGroup',

        [switch] $NetworkOnly,

        [switch] $IncludeHealth,

        [SupportsWildcards()]
        [string[]] $ExcludeType,

        [Parameter(Mandatory)]
        [string] $Path,

        [ValidateSet('None', 'Subscription', 'ResourceGroup', 'ManagementGroup', 'Region', 'Gateway')]
        [string] $SplitBy = 'None',

        [switch] $Update,

        [switch] $Prune,

        [switch] $NoLegend,

        [string] $Title,

        [string] $HtmlPath,

        [string] $PdfPath,

        [switch] $Force,

        [switch] $Open,

        [switch] $PassThru
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    # What each view takes: a parameter it doesn't is a mistake worth saying.
    $takes = @{
        Resources          = @('SubscriptionId', 'ResourceGroupName', 'ExcludeType')
        Network            = @('SubscriptionId', 'ManagementGroupId', 'Location', 'GroupBy', 'NetworkOnly', 'ExcludeType')
        ApplicationGateway = @('SubscriptionId', 'ResourceGroupName', 'Name', 'IncludeHealth')
    }
    foreach ($parameter in 'ResourceGroupName', 'ManagementGroupId', 'Location', 'Name', 'GroupBy', 'NetworkOnly', 'IncludeHealth', 'ExcludeType') {
        if ($PSBoundParameters.ContainsKey($parameter) -and $parameter -notin $takes[$View]) {
            throw "Azure Admin Console: -$parameter doesn't apply to -View $View. It takes $(($takes[$View] | ForEach-Object { "-$_" }) -join ', ')."
        }
    }
    if ($View -eq 'Resources' -and -not $SubscriptionId -and -not $ResourceGroupName) { throw 'Azure Admin Console: say what to draw - -SubscriptionId, -ResourceGroupName, or both.' }
    if ($Prune -and -not $Update) { throw 'Azure Admin Console: -Prune works with -Update (it deletes what is no longer in Azure from the diagram you are refreshing).' }
    $splitKind = @{ None = ''; Subscription = 'subscription'; ResourceGroup = 'resourcegroup'; ManagementGroup = 'managementgroup'; Region = 'region'; Gateway = 'appgw' }[$SplitBy]
    $fullPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $exists = Test-Path -LiteralPath $fullPath
    $htmlFullPath = if ($HtmlPath) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($HtmlPath) } else { '' }
    $pdfFullPath = if ($PdfPath) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($PdfPath) } else { '' }
    if ($exists -and -not $Update -and -not $Force) {
        throw "Azure Admin Console won't overwrite $fullPath - it may hold your edits. Add -Update to refresh it and keep them, or -Force to replace it."
    }
    $request = @{
        View = $View; SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ResourceGroupName = @($ResourceGroupName | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ })
        Location = @($Location | Where-Object { $_ }); Name = @($Name | Where-Object { $_ }); GroupBy = $GroupBy; NetworkOnly = [bool]$NetworkOnly; IncludeHealth = [bool]$IncludeHealth
        ExcludeType = @($ExcludeType | Where-Object { $_ }); Title = $Title; SplitKind = $splitKind; Legend = -not $NoLegend; Merge = [bool]($Update -and $exists); Prune = [bool]$Prune
    }

    Write-AACRule -Title 'Azure Admin Console :: Diagram' -Color 'deepskyblue3_1'
    $state = Invoke-AACProgress -ScriptBlock {
        $null = Get-AACAccessToken
        $built = switch ($request.View) {
            'Network' { Read-AACNetworkTopology -ManagementGroupId $request.ManagementGroupId -SubscriptionId $request.SubscriptionId -Location $request.Location -GroupBy $request.GroupBy -NetworkOnly:$request.NetworkOnly -ExcludeType $request.ExcludeType -Title $request.Title }
            'ApplicationGateway' { Read-AACApplicationGatewayMap -SubscriptionId $request.SubscriptionId -ResourceGroupName $request.ResourceGroupName -Name $request.Name -IncludeHealth:$request.IncludeHealth -Title $request.Title }
            default { Read-AACResourceMap -SubscriptionId $request.SubscriptionId -ResourceGroupName $request.ResourceGroupName -ExcludeType $request.ExcludeType -Title $request.Title }
        }
        Update-AACProgress -Id 'drawio' -Indeterminate -Description 'Drawing the diagram'
        $asset = Get-AACResourceMapAsset
        $drawn = ConvertTo-AACDrawio -Map $built.Map -Icons $asset.Icons -Title $built.Title -SplitBy $request.SplitKind -Fact $built.Facts -Legend:$request.Legend
        $xml = $drawn.Xml
        $merge = $null
        if ($request.Merge) {
            Update-AACProgress -Id 'drawio' -Indeterminate -Description 'Merging into your diagram, keeping your changes'
            $merge = Merge-AACDrawio -Existing ([System.IO.File]::ReadAllText($fullPath)) -Generated $xml -Prune:$request.Prune
            $xml = $merge.Xml
        }
        $folder = Split-Path -Parent $fullPath
        if ($folder -and -not (Test-Path -LiteralPath $folder)) { $null = New-Item -ItemType Directory -Path $folder -Force }
        [System.IO.File]::WriteAllText($fullPath, $xml, [System.Text.UTF8Encoding]::new($false))
        Update-AACProgress -Id 'drawio' -Complete -Description ('Diagram: {0:N0} shape(s), {1:N0} connection(s) on {2:N0} page(s){3}' -f $drawn.Shapes, $drawn.Connections, @($drawn.Pages).Count, $(if ($merge) { "; kept $($merge.Kept), added $($merge.Added), removed $($merge.Removed + $merge.Pruned)" }))
        if ($htmlFullPath -or $pdfFullPath) {
            # Laid out as the view's own map command lays it out: the network as hub and spoke when there are hubs.
            $look = @{ Map = $built.Map; Title = $built.Title; Fact = $built.Facts; Theme = 'light'; Layout = 'layered'; Hierarchy = 'layered' }
            if ($request.View -eq 'Network') {
                $look.Layout = if ($built.Map['Layout'] -eq 'hubspoke') { 'hubspoke' } else { 'packed' }
                $look.Hierarchy = 'packed'
            }
            if ($htmlFullPath) {
                Update-AACProgress -Id 'html' -Indeterminate -Description 'Writing the HTML page'
                Write-AACResourceMapHtml @look -Path $htmlFullPath
                Update-AACProgress -Id 'html' -Complete -Description 'HTML page written'
            }
            if ($pdfFullPath) {
                Update-AACProgress -Id 'pdf' -Indeterminate -Description 'Drawing the PDF in a headless browser'
                Write-AACResourceMapPdf @look -Path $pdfFullPath
                Update-AACProgress -Id 'pdf' -Complete -Description 'PDF written'
            }
        }
        @{ Built = $built; Drawn = $drawn; Merge = $merge }
    }

    $drawn = $state.Drawn
    $merge = $state.Merge
    $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
    if (-not $drawn.Shapes) { Write-AACMarkup '[grey58]Nothing was found in that scope; the diagram is empty.[/]' }
    foreach ($page in @($drawn.Pages)) { Write-AACMarkup ("  [white]{0}[/] [grey58]{1:N0} shape(s), {2:N0} connection(s)[/]" -f (& $escape $page.Name), $page.Shapes, $page.Connections) }
    if ($merge) {
        Write-AACMarkup ("[grey58]Refreshed: [white]{0}[/] kept, [green3]{1}[/] added (marked green), [red1]{2}[/] {3}; your own shapes left as they were.[/]" -f $merge.Kept, $merge.Added, ($merge.Removed + $merge.Pruned), $(if ($Prune) { 'deleted' } else { 'removed (faded)' }))
    }
    elseif ($Update) { Write-AACMarkup '[grey58]There was no diagram to update at that path, so a new one was written.[/]' }
    Write-AACMarkup "[grey58]Diagram: $(& $escape $fullPath) - open it in draw.io (desktop, app.diagrams.net or the VS Code extension) to edit; -Update refreshes it later.[/]"
    if ($htmlFullPath) { Write-AACMarkup "[grey58]HTML page: $(& $escape $htmlFullPath)[/]" }
    if ($pdfFullPath) { Write-AACMarkup "[grey58]PDF: $(& $escape $pdfFullPath)[/]" }
    if ($Open) {
        foreach ($written in @($fullPath, $htmlFullPath, $pdfFullPath) | Where-Object { $_ }) { Open-AACFile -Path $written }
    }

    if ($PassThru) {
        [pscustomobject]@{
            PSTypeName  = 'AAC.Diagram'
            Path        = $fullPath
            HtmlPath    = $htmlFullPath
            PdfPath     = $pdfFullPath
            View        = $View
            Title       = $state.Built.Title
            Pages       = @($drawn.Pages | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Shapes = $_.Shapes; Connections = $_.Connections } })
            Shapes      = $drawn.Shapes
            Connections = $drawn.Connections
            Kept        = $(if ($merge) { $merge.Kept } else { 0 })
            Added       = $(if ($merge) { $merge.Added } else { $drawn.Shapes })
            Removed     = $(if ($merge) { $merge.Removed } else { 0 })
            Pruned      = $(if ($merge) { $merge.Pruned } else { 0 })
        }
    }
}
