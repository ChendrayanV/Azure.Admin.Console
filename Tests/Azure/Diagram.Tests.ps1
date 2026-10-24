<#
    Unit tests for Export-AACDiagram and what it draws with: ConvertTo-AACDrawio
    (the map model as an editable draw.io diagram - containers, icons,
    attached connections, pages, the legend) and Merge-AACDrawio (-Update:
    a refresh that keeps the user's changes) - on the resource map's made-up
    Contoso estate (Fixtures\ContosoEstate.ps1), the network topology's and
    the Application Gateway map's fixtures, with Resource Graph mocked.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
    # A real PDF needs Edge or Chrome: on Windows, where they're there (as on the CI runners).
    $script:canPrintPdf = $IsWindows -and [bool](& (Get-Module -Name 'Azure.Admin.Console') { Get-AACBrowserPath })
}

BeforeAll {
    . (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Fixtures/GraphBatchShim.ps1')
    . (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Fixtures/ContosoEstate.ps1')
    . (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Fixtures/ContosoTopology.ps1')
    . (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Fixtures/ContosoApplicationGateway.ps1')
    $script:estate = @(Get-AACContosoEstate)
    $script:hubSub = '11111111-1111-1111-1111-111111111111'
    $script:appSub = '22222222-2222-2222-2222-222222222222'
    $script:names = @{ $script:hubSub = 'Contoso Connectivity'; $script:appSub = 'Contoso Apps' }
    # The estate's resource map, drawn: @{ Xml; Pages; Shapes; Connections } and the parsed XML.
    $script:draw = {
        param([hashtable] $Options = @{})
        InModuleScope 'Azure.Admin.Console' -Parameters @{ Rows = $script:estate; Names = $script:names; Options = $Options } {
            param($Rows, $Names, $Options)
            $asset = Get-AACResourceMapAsset
            $labels = @{}
            foreach ($key in $asset.Icons.icons.Keys) { $labels[$key] = $asset.Icons.icons[$key].label }
            $map = ConvertTo-AACResourceMap -Resource $Rows -SubscriptionName $Names -IconType $asset.Icons.types -IconLabel $labels
            ConvertTo-AACDrawio -Map $map -Icons $asset.Icons -Title 'Contoso' @Options
        }
    }
    $script:merge = {
        param([string] $Existing, [string] $Generated, [switch] $Prune)
        InModuleScope 'Azure.Admin.Console' -Parameters @{ Existing = $Existing; Generated = $Generated; Prune = [bool]$Prune } {
            param($Existing, $Generated, $Prune)
            Merge-AACDrawio -Existing $Existing -Generated $Generated -Prune:$Prune -Now ([datetime]'2026-10-18T09:00:00Z')
        }
    }
    # A shape by resource name on a page of a parsed diagram.
    $script:shape = { param([xml] $Doc, [string] $Name, [int] $Page = 0) @($Doc.mxfile.diagram)[$Page].mxGraphModel.root.object | Where-Object { $_.resourceId -match "/$([regex]::Escape($Name))$" } | Select-Object -First 1 }
    $script:cellOf = { param([xml] $Doc, [string] $Id, [int] $Page = 0) @(@($Doc.mxfile.diagram)[$Page].mxGraphModel.root.ChildNodes | Where-Object { $_.id -eq $Id })[0] }
}

Describe 'Azure Admin Console - ConvertTo-AACDrawio' {
    It 'draws the boxes as nested draw.io containers, each resource in its box' {
        $d = & $script:draw
        $doc = [xml]$d.Xml
        $vm = & $script:shape $doc 'vm-web-01'
        $subnet = & $script:cellOf $doc $vm.mxCell.parent
        $subnet.aacKind | Should -Be 'subnet'
        $vnet = & $script:cellOf $doc $subnet.mxCell.parent
        $vnet.aacKind | Should -Be 'vnet'
        $rg = & $script:cellOf $doc $vnet.mxCell.parent
        $rg.aacKind | Should -Be 'resourcegroup'
        (& $script:cellOf $doc $rg.mxCell.parent).aacKind | Should -Be 'subscription'
        $subnet.mxCell.style | Should -BeLike 'swimlane*' -Because 'a swimlane is a draw.io container: its children move with it'
        # The resource's place is inside its box: relative to it.
        [double]$vm.mxCell.mxGeometry.x | Should -BeLessThan ([double]$subnet.mxCell.mxGeometry.width)
    }

    It 'keeps the same IDs run after run, from the resource IDs' {
        $a = [xml](& $script:draw).Xml
        $b = [xml](& $script:draw).Xml
        (& $script:shape $a 'vm-web-01').id | Should -Be (& $script:shape $b 'vm-web-01').id
        (& $script:shape $a 'vm-web-01').id | Should -Match '^aac-[0-9a-f]{16}$'
        $ids = @($a.mxfile.diagram.mxGraphModel.root.ChildNodes | ForEach-Object { $_.id })
        $ids.Count | Should -Be @($ids | Select-Object -Unique).Count
    }

    It 'gives each resource its Azure icon, data, portal link and state' {
        $doc = [xml](& $script:draw).Xml
        $vm = & $script:shape $doc 'vm-web-01'
        $vm.mxCell.style | Should -Match 'image=data:image/svg\+xml,[A-Za-z0-9+/=]+;'
        $vm.resourceType | Should -Be 'microsoft.compute/virtualmachines'
        $vm.subscription | Should -Be 'Contoso Apps'
        $vm.link | Should -BeLike 'https://portal.azure.com/#resource/subscriptions/*/virtualmachines/vm-web-01'
        $vm.label | Should -Match '<b>vm-web-01</b>'
        $vm.aacLabel | Should -Be $vm.label
        (& $script:shape $doc 'nic-leftover').mxCell.style | Should -Match 'fontColor=#D13447' -Because 'unattached resources are red'
    }

    It 'attaches every connection at both ends, styled by kind, and leaves out the cards view' {
        $doc = [xml](& $script:draw).Xml
        $root = $doc.mxfile.diagram.mxGraphModel.root
        $ids = [System.Collections.Generic.HashSet[string]]@(@($root.object | ForEach-Object { $_.id }))
        $edges = @($root.mxCell | Where-Object { $_.edge -eq '1' })
        $edges.Count | Should -BeGreaterThan 5
        @($edges | Where-Object { -not $ids.Contains($_.source) -or -not $ids.Contains($_.target) }) | Should -BeNullOrEmpty
        $hub = (& $script:shape $doc 'vnet-hub').id; $spoke = (& $script:shape $doc 'vnet-spoke-app').id
        $peering = @($edges | Where-Object { ($_.source -eq $hub -and $_.target -eq $spoke) -or ($_.source -eq $spoke -and $_.target -eq $hub) })[0]
        $peering.style | Should -Match 'startArrow=block' -Because 'a peering goes both ways'
        $peering.style | Should -Match 'edgeStyle=orthogonalEdgeStyle'
        $edges[0].id | Should -Match '^aac-e-[0-9a-f]{16}$'
    }

    It 'puts each resource group on a page of its own with -SplitBy, and adds the legend' {
        $d = & $script:draw @{ SplitBy = 'resourcegroup'; Legend = $true; Fact = @('30 resources', 'drawn today') }
        @($d.Pages.Name) | Should -Be @('rg-hub (Contoso Connectivity)', 'rg-spoke-app (Contoso Apps)')
        $doc = [xml]$d.Xml
        @($doc.mxfile.diagram.name) | Should -Be @('rg-hub (Contoso Connectivity)', 'rg-spoke-app (Contoso Apps)', 'Legend')
        (& $script:shape $doc 'vm-web-01' 1) | Should -Not -BeNullOrEmpty
        (& $script:shape $doc 'vm-web-01' 0) | Should -BeNullOrEmpty
        # The page's root is the resource group: its box sits on the page.
        $rg = & $script:shape $doc 'rg-spoke-app' 1
        $rg.mxCell.parent | Should -Be '1'
        $legend = @($doc.mxfile.diagram)[2].mxGraphModel.root
        @($legend.mxCell.id) | Should -Contain 'aac-legend-box-subnet'
        @($legend.mxCell.id) | Should -Contain 'aac-legend-edge-privatelink'
        # The hub-spoke peering joins two pages: left out, so not in the legend either.
        @($legend.mxCell.id) | Should -Not -Contain 'aac-legend-edge-peering'
        ($legend.mxCell | Where-Object id -EQ 'aac-legend-facts').value | Should -Match '30 resources'
    }
}

Describe 'Azure Admin Console - Merge-AACDrawio' {
    BeforeAll {
        $script:base = (& $script:draw).Xml
        # The user's edits: vm-web-01 moved and relabelled, a note added.
        $doc = [xml]$script:base
        $vm = & $script:shape $doc 'vm-web-01'
        $vm.mxCell.mxGeometry.SetAttribute('x', '777'); $vm.mxCell.mxGeometry.SetAttribute('y', '555')
        $vm.SetAttribute('label', 'Web server 1 (blue team)')
        $note = $doc.CreateElement('mxCell')
        foreach ($pair in @(@('id', 'my-note'), @('value', 'Ask Ana about the firewall'), @('style', 'shape=note;'), @('vertex', '1'), @('parent', '1'))) { $note.SetAttribute($pair[0], $pair[1]) }
        $geo = $doc.CreateElement('mxGeometry'); $geo.SetAttribute('x', '10'); $geo.SetAttribute('y', '10'); $geo.SetAttribute('width', '120'); $geo.SetAttribute('height', '60'); $geo.SetAttribute('as', 'geometry')
        [void]$note.AppendChild($geo)
        [void]$doc.mxfile.diagram.mxGraphModel.root.AppendChild($note)
        $script:edited = $doc.OuterXml
    }

    It 'keeps what the user moved, relabelled and added; refreshes the data' {
        $r = & $script:merge $script:edited $script:base
        $doc = [xml]$r.Xml
        $vm = & $script:shape $doc 'vm-web-01'
        "$($vm.mxCell.mxGeometry.x),$($vm.mxCell.mxGeometry.y)" | Should -Be '777,555'
        $vm.label | Should -Be 'Web server 1 (blue team)'
        $vm.resourceType | Should -Be 'microsoft.compute/virtualmachines'
        (& $script:cellOf $doc 'my-note').value | Should -Be 'Ask Ana about the firewall'
        "$($r.Added) $($r.Removed)" | Should -Be '0 0'
        $r.Kept | Should -BeGreaterThan 30
    }

    It 'adds a new resource into its box, marked new, and fades one no longer in Azure' {
        # The estate a day later: a VM is gone, a storage account is new in rg-spoke-app.
        $rows = @($script:estate | Where-Object { $_.name -ne 'vm-web-02' })
        $new = @{ id = "/subscriptions/$script:appSub/resourceGroups/rg-spoke-app/providers/Microsoft.Storage/storageAccounts/stnewlogs"; name = 'stnewlogs'; type = 'Microsoft.Storage/storageAccounts'; kind = 'StorageV2'; location = 'uksouth'; resourceGroup = 'rg-spoke-app'; subscriptionId = $script:appSub; sku = @{ name = 'Standard_ZRS' }; properties = @{}; tags = $null }
        $later = InModuleScope 'Azure.Admin.Console' -Parameters @{ Rows = @($rows) + $new; Names = $script:names } {
            param($Rows, $Names)
            $asset = Get-AACResourceMapAsset
            $labels = @{}; foreach ($key in $asset.Icons.icons.Keys) { $labels[$key] = $asset.Icons.icons[$key].label }
            (ConvertTo-AACDrawio -Map (ConvertTo-AACResourceMap -Resource $Rows -SubscriptionName $Names -IconType $asset.Icons.types -IconLabel $labels) -Icons $asset.Icons -Title 'Contoso').Xml
        }
        $before = [xml]$script:edited
        $rgBefore = & $script:shape $before 'rg-spoke-app'
        $r = & $script:merge $script:edited $later
        $doc = [xml]$r.Xml
        $added = & $script:shape $doc 'stnewlogs'
        $added.aacStatus | Should -Be 'new 2026-10-18'
        $added.mxCell.style | Should -Match 'aacNew=1'
        $added.mxCell.parent | Should -Be $rgBefore.id
        [double]$added.mxCell.mxGeometry.y | Should -BeGreaterThan 0
        $rg = & $script:shape $doc 'rg-spoke-app'
        [double]$rg.mxCell.mxGeometry.height | Should -BeGreaterOrEqual ([double]$rgBefore.mxCell.mxGeometry.height) -Because 'the box grows to hold what was added'
        $gone = & $script:shape $doc 'vm-web-02'
        $gone.aacStatus | Should -Be 'removed 2026-10-18'
        $gone.mxCell.style | Should -Match 'aacRemoved=1;opacity=35'
        $gone.tooltip | Should -BeLike 'Not found in Azure on 2026-10-18*'
        "$($r.Added) $($r.Removed)" | Should -Be '1 1'
        # The next refresh: no longer new; and -Prune deletes what is gone.
        $again = & $script:merge $r.Xml $later -Prune
        $doc = [xml]$again.Xml
        (& $script:shape $doc 'stnewlogs').mxCell.style | Should -Not -Match 'aacNew'
        & $script:shape $doc 'vm-web-02' | Should -BeNullOrEmpty
        $again.Pruned | Should -Be 1
        (& $script:shape $doc 'vm-web-01').label | Should -Be 'Web server 1 (blue team)'
    }

    It 'reads a page draw.io saved compressed' {
        $doc = [xml]$script:edited
        $diagram = $doc.mxfile.diagram
        $model = $diagram.mxGraphModel
        $raw = [System.IO.MemoryStream]::new()
        $deflate = [System.IO.Compression.DeflateStream]::new($raw, [System.IO.Compression.CompressionLevel]::Optimal, $true)
        $bytes = [Text.Encoding]::UTF8.GetBytes([Uri]::EscapeDataString($model.OuterXml))
        $deflate.Write($bytes, 0, $bytes.Length); $deflate.Dispose()
        [void]$diagram.RemoveChild($model)
        $diagram.InnerText = [Convert]::ToBase64String($raw.ToArray())
        $r = & $script:merge $doc.OuterXml $script:base
        (& $script:shape ([xml]$r.Xml) 'vm-web-01').label | Should -Be 'Web server 1 (blue team)'
    }

    It 'refuses a file that is not a draw.io diagram' {
        { & $script:merge '<html></html>' $script:base } | Should -Throw "*isn't a draw.io diagram*"
    }
}

Describe 'Azure Admin Console - Export-AACDiagram' {
    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Open-AACFile -MockWith { }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith { & $script:graphBatchShim $Query $SubscriptionId $ManagementGroupId $AsObject $AllowFailure }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -MockWith {
            $query = ($Body | ConvertFrom-Json).query
            $data = if ($query -match 'subscriptions/resourcegroups') { @(@{ name = 'rg-hub'; subscriptionId = $script:hubSub }, @{ name = 'rg-spoke-app'; subscriptionId = $script:appSub }) | Where-Object { $query -match "'$($_.name)'" } }
            elseif ($query -match "type =~ 'microsoft.resources/subscriptions'") { @(@{ subscriptionId = $script:hubSub; name = 'Contoso Connectivity' }, @{ subscriptionId = $script:appSub; name = 'Contoso Apps' }) }
            elseif ($query -match 'properties contains') { @($script:estate | Where-Object { $row = $_; ($row.properties | ConvertTo-Json -Depth 20 -Compress) -match '"privateIPAddress":"10\.0\.1\.4"' -and $query -match '10\.0\.1\.4' -and $query -match [regex]::Escape($row.type.ToLowerInvariant()) }) }
            elseif ($query -match 'id in~') { @($script:estate | Where-Object { $query -match [regex]::Escape("'$($_.id.ToLowerInvariant())'") -or $query -match [regex]::Escape("'$($_.id)'") }) }
            else { @($script:estate | Where-Object { $query -match "'$($_.resourceGroup)'" }) }
            @{ data = @($data) }
        }
    }

    It 'writes the resources as a .drawio file and says what it holds' {
        $path = Join-Path $TestDrive 'estate.drawio'
        $d = Export-AACDiagram -ResourceGroupName 'rg-hub', 'rg-spoke-app' -Path $path -Open -PassThru
        Test-Path $path | Should -BeTrue
        $d.PSObject.TypeNames | Should -Contain 'AAC.Diagram'
        $d.Shapes | Should -BeGreaterThan 30
        $d.Connections | Should -BeGreaterThan 5
        @($d.Pages.Name) | Should -Be @('Resource map: rg-hub, rg-spoke-app')
        @(([xml](Get-Content -LiteralPath $path -Raw)).mxfile.diagram.name) | Should -Contain 'Legend'
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Open-AACFile -Times 1 -Exactly -ParameterFilter { $Path -eq $path }
    }

    It 'won''t overwrite a diagram without -Update or -Force; -Update keeps the user''s changes' {
        $path = Join-Path $TestDrive 'kept.drawio'
        $null = Export-AACDiagram -ResourceGroupName 'rg-spoke-app' -Path $path -NoLegend
        { Export-AACDiagram -ResourceGroupName 'rg-spoke-app' -Path $path } | Should -Throw "*won't overwrite*"
        $doc = [xml](Get-Content -LiteralPath $path -Raw)
        $vm = & $script:shape $doc 'vm-web-01'
        $vm.SetAttribute('label', 'Front end'); $vm.mxCell.mxGeometry.SetAttribute('x', '901')
        [IO.File]::WriteAllText($path, $doc.OuterXml)
        $r = Export-AACDiagram -ResourceGroupName 'rg-spoke-app' -Path $path -NoLegend -Update -PassThru
        $r.Kept | Should -BeGreaterThan 10
        $vm = & $script:shape ([xml](Get-Content -LiteralPath $path -Raw)) 'vm-web-01'
        "$($vm.label) $($vm.mxCell.mxGeometry.x)" | Should -Be 'Front end 901'
        $null = Export-AACDiagram -ResourceGroupName 'rg-spoke-app' -Path $path -NoLegend -Force
        (& $script:shape ([xml](Get-Content -LiteralPath $path -Raw)) 'vm-web-01').label | Should -Match '<b>vm-web-01</b>'
    }

    It 'writes a clean HTML page and a PDF alongside, each with the legend, and opens them all with -Open' {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Write-AACResourceMapPdf -MockWith { Set-Content -LiteralPath $Path -Value '%PDF-fake' }
        $html = Join-Path $TestDrive 'copy\estate.html'
        $pdf = Join-Path $TestDrive 'copy\estate.pdf'
        $d = Export-AACDiagram -ResourceGroupName 'rg-hub', 'rg-spoke-app' -Path (Join-Path $TestDrive 'copies.drawio') -HtmlPath $html -PdfPath $pdf -Open -PassThru
        "$($d.HtmlPath)|$($d.PdfPath)" | Should -Be "$html|$pdf"
        $page = Get-Content -LiteralPath $html -Raw
        $page | Should -Match '<title>Resource map: rg-hub, rg-spoke-app</title>'
        $page | Should -Match '"theme":"light"'
        $page | Should -Match '"print":false'
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Write-AACResourceMapPdf -Times 1 -Exactly -ParameterFilter { $Path -eq $pdf -and $Theme -eq 'light' -and @($Map['Nodes']).Count -gt 20 }
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Open-AACFile -Times 3 -Exactly
    }

    It 'says what to do when there is no browser to draw the PDF' {
        InModuleScope 'Azure.Admin.Console' -Parameters @{ Path = (Join-Path $TestDrive 'none.pdf') } {
            param($Path)
            Mock -CommandName Get-AACBrowserPath -MockWith { }
            Mock -CommandName Start-Process -MockWith { }
            { Write-AACResourceMapPdf -Map @{ Clusters = @(); Nodes = @(); Edges = @() } -Path $Path -Title 'x' } | Should -Throw '*needs Microsoft Edge or Google Chrome*-HtmlPath*'
            Should -Invoke -CommandName Start-Process -Times 0 -Exactly
        }
    }

    It 'prints the map to a one-page PDF in a headless browser' -Skip:(-not $script:canPrintPdf) {
        $pdf = Join-Path $TestDrive 'printed.pdf'
        $null = Export-AACDiagram -ResourceGroupName 'rg-spoke-app' -Path (Join-Path $TestDrive 'printed.drawio') -PdfPath $pdf
        $bytes = [System.IO.File]::ReadAllBytes($pdf)
        [System.Text.Encoding]::ASCII.GetString($bytes, 0, 5) | Should -Be '%PDF-'
        ([regex]::Matches([System.Text.Encoding]::ASCII.GetString($bytes), '/Type\s*/Page[^s]')).Count | Should -Be 1
    }

    It 'says when a parameter doesn''t fit the view, or what is missing' {
        { Export-AACDiagram -Name 'agw-*' -ResourceGroupName 'rg-hub' -Path (Join-Path $TestDrive 'x.drawio') } | Should -Throw "*-Name doesn't apply to -View Resources*"
        { Export-AACDiagram -Path (Join-Path $TestDrive 'x.drawio') } | Should -Throw '*-SubscriptionId, -ResourceGroupName, or both*'
        { Export-AACDiagram -ResourceGroupName 'rg-hub' -Prune -Path (Join-Path $TestDrive 'x.drawio') } | Should -Throw '*-Prune works with -Update*'
    }

    It 'draws the network topology, a page per subscription' {
        $script:topoRows = @(Get-AACContosoTopology); $script:topoSubs = @(Get-AACContosoTopologySubscription)
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $rows = @{}
            foreach ($name in @($Query.Keys)) {
                $spec = $Query[$name]
                $text = if ($spec -is [System.Collections.IDictionary]) { [string]$spec['Query'] } else { [string]$spec }
                $rows[$name] = @(
                    if ($name -eq 'subscriptions') { $script:topoSubs }
                    elseif ($text -match 'where id in~') { $script:topoRows | Where-Object { $text -match [regex]::Escape("'$($_.id)'") } }
                    elseif ($name -eq 'resources') { $script:topoRows | Where-Object { $text -match [regex]::Escape("'$($_.type.ToLowerInvariant())'") } }
                )
            }
            @{ Rows = $rows; Errors = @{} }
        }
        $d = Export-AACDiagram -View Network -SplitBy Subscription -Path (Join-Path $TestDrive 'net.drawio') -PassThru
        @($d.Pages).Count | Should -BeGreaterThan 1
        $d.Shapes | Should -BeGreaterThan 5
        $doc = [xml](Get-Content -LiteralPath (Join-Path $TestDrive 'net.drawio') -Raw)
        @($doc.mxfile.diagram.mxGraphModel.root.object | Where-Object aacKind -EQ 'vnet').Count | Should -BeGreaterThan 1
    }

    It 'draws the Application Gateways'' flows, a column per stage, with health' {
        $script:agw = Get-AACContosoApplicationGateway
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Start-Sleep -MockWith { }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $rows = @{}
            foreach ($n in @($Query.Keys)) { $rows[$n] = @(switch -Wildcard ($n) { 'gateways' { $script:agw.Gateways } 'subscriptions' { $script:agw.Subscriptions } 'sites' { $script:agw.Sites } 'ids*' { $script:agw.Related } }) }
            @{ Rows = $rows; Errors = @{} }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith { $out = @{}; foreach ($u in $Uri) { $out[$u] = @{ Status = 200; Body = $script:agw.Metrics; Items = $null; Error = '' } }; $out }
        $path = Join-Path $TestDrive 'agw.drawio'
        $d = Export-AACDiagram -View ApplicationGateway -Path $path -PassThru
        $d.Shapes | Should -BeGreaterThan 10
        $doc = [xml](Get-Content -LiteralPath $path -Raw)
        $root = $doc.mxfile.diagram[0].mxGraphModel.root
        @($root.object | Where-Object aacKind -EQ 'appgw').Count | Should -BeGreaterThan 0
        # Listeners left of pools: the flow reads left to right.
        $x = { param($Type) @($root.object | Where-Object { $_.resourceType -eq $Type } | ForEach-Object { [double]$_.mxCell.mxGeometry.x }) }
        ((& $x 'appgw/listener') | Measure-Object -Maximum).Maximum | Should -BeLessThan ((& $x 'appgw/pool') | Measure-Object -Minimum).Minimum
        @($root.mxCell | Where-Object { $_.edge -eq '1' -and $_.style -match 'strokeWidth=2' }).Count | Should -BeGreaterThan 0 -Because 'traffic flows are drawn bold'
    }
}

Describe 'Azure Admin Console - the map page''s Save .drawio' {
    It 'offers Save .drawio on the HTML maps' {
        $template = Get-Content -LiteralPath (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '..\src\Azure\Private\ResourceMap.html') -Raw
        $template | Should -Match 'id="save-drawio"'
        $template | Should -Match 'function exportDrawio'
    }

    It 'has a print mode for the PDF, and a legend of the boxes as well as the connections' {
        $template = Get-Content -LiteralPath (Join-Path (Split-Path -Path $PSScriptRoot -Parent) '..\src\Azure\Private\ResourceMap.html') -Raw
        $template | Should -Match 'function printPage'
        $template | Should -Match '@page \{ size: '
        $template | Should -Match '<h2>Boxes</h2>'
    }
}
