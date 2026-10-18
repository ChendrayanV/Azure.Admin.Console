function ConvertTo-AACDrawio {
    <#
    .SYNOPSIS
        Turns a map model (ConvertTo-AACResourceMap, ConvertTo-AACNetworkTopology
        or ConvertTo-AACApplicationGatewayMap: Clusters, Nodes, Edges) into an
        editable draw.io diagram.
    .DESCRIPTION
        Native draw.io, not a picture of one:
          - boxes are draw.io containers (tenant > management group >
            subscription > region > resource group > virtual network > subnet
            > gateway): move a box and what is in it moves with it; drag a
            resource into another box and it belongs there
          - resources carry the module's Azure icons as embedded SVG (sharp at
            any zoom), the name and the type; unattached ones are red, those
            outside the selection faded; a gateway's parts show their health
          - connections are attached at both ends, so they follow what you
            move, and draw.io routes them (orthogonal)
          - every shape keeps its data - resource ID, type, location, resource
            group, subscription - and links to the Azure portal (Edit Data,
            hover, or Ctrl+click)
          - cell IDs come from the resource IDs (connections from both ends and
            the kind), so Merge-AACDrawio finds them again on the next run
        Layout: each box's resources in a grid (a gateway's in columns, one
        per stage of its flow: listeners > rules > settings > pools), its
        child boxes in rows under them, packed to a width per kind of box.
        -SplitBy puts each box of that kind on a page of its own (what isn't
        in one goes on a page 'Other'); a connection between pages is left out.
        -Legend adds a page with the kinds of box and connection used, the
        facts and how to refresh the diagram.
        Returns @{ Xml; Pages = @(@{ Name; Shapes; Connections }); Shapes;
        Connections }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Map,

        # The icon set (Get-AACResourceMapAsset).Icons: types and icons.
        [Parameter(Mandatory)]
        $Icons,

        [string] $Title = 'Azure resources',

        # A cluster kind: subscription, resourcegroup, managementgroup, region or appgw; empty for one page.
        [string] $SplitBy = '',

        # The lines for the legend page: what was read, when.
        [string[]] $Fact = @(),

        [switch] $Legend
    )

    # --- Look ----------------------------------------------------------------------------------------------------
    $nodeW, $nodeH, $iconSize = 140, 100, 48
    $pad, $gap, $header = 18, 24, 34
    $maxWidth = @{ tenant = 3600; managementgroup = 3200; subscription = 2800; region = 2600; resourcegroup = 2300; vnet = 1800; subnet = 860; appgw = 2400; '' = 3600 }
    $perRowOf = @{ tenant = 8; managementgroup = 8; subscription = 7; region = 7; resourcegroup = 7; vnet = 6; subnet = 4; appgw = 6; '' = 8 }
    $box = 'swimlane;html=1;whiteSpace=wrap;startSize=34;rounded=1;arcSize=2;fontStyle=1;align=left;spacingLeft=12;'
    $styleOf = @{
        tenant          = $box + 'fillColor=#E3E7ED;swimlaneFillColor=#FAFBFC;strokeColor=#6B7A90;fontSize=15;fontColor=#1B2A41;'
        managementgroup = $box + 'fillColor=#E7E3F4;swimlaneFillColor=#FBFAFE;strokeColor=#7A5CC7;fontSize=14;fontColor=#33236B;'
        subscription    = $box + 'fillColor=#E7ECF3;swimlaneFillColor=#F7F9FC;strokeColor=#8C9BB0;fontSize=14;fontColor=#1B2A41;'
        region          = $box + 'fillColor=#E6F3EF;swimlaneFillColor=#F8FCFA;strokeColor=#008A6E;dashed=1;fontSize=13;fontColor=#0B4A3C;'
        resourcegroup   = $box + 'fillColor=#F1F3F6;swimlaneFillColor=#FFFFFF;strokeColor=#A3AEBE;dashed=1;fontSize=13;fontColor=#1B2A41;'
        vnet            = $box + 'fillColor=#DCEBFA;swimlaneFillColor=#F2F8FE;strokeColor=#0078D4;fontSize=13;fontColor=#0B3B66;'
        subnet          = $box + 'fillColor=#EAF3FD;swimlaneFillColor=#FFFFFF;strokeColor=#5EA0EF;dashed=1;fontSize=12;fontColor=#0B3B66;'
        appgw           = $box + 'fillColor=#FCEBDC;swimlaneFillColor=#FFFBF7;strokeColor=#D9730D;fontSize=13;fontColor=#5C2E05;'
    }
    $boxLabel = @{ tenant = 'Tenant'; managementgroup = 'Management group'; subscription = 'Subscription'; region = 'Region'; resourcegroup = 'Resource group'; vnet = 'Virtual network'; subnet = 'Subnet'; appgw = 'Application Gateway' }
    $edgeStyle = [ordered]@{
        network     = 'strokeColor=#0078D4;endArrow=block;endFill=1;'
        peering     = 'strokeColor=#7A5CC7;strokeWidth=2;dashed=1;startArrow=block;startFill=1;endArrow=block;endFill=1;'
        privatelink = 'strokeColor=#00809C;dashed=1;endArrow=block;endFill=1;'
        route       = 'strokeColor=#B8730A;strokeWidth=2;endArrow=block;endFill=1;'
        dns         = 'strokeColor=#8C9BB0;dashed=1;dashPattern=1 3;endArrow=open;'
        flow        = 'strokeColor=#0078D4;strokeWidth=2;endArrow=block;endFill=1;'
        probe       = 'strokeColor=#008A6E;dashed=1;endArrow=open;'
        waf         = 'strokeColor=#D13447;dashed=1;endArrow=block;endFill=1;'
        redirect    = 'strokeColor=#B8730A;dashed=1;endArrow=block;endFill=1;'
        dependency  = 'strokeColor=#8C9BB0;endArrow=open;'
    }
    $edgeName = @{ network = 'Network link'; peering = 'Peering'; privatelink = 'Private endpoint to its resource'; route = 'Route (next hop)'; dns = 'Private DNS zone link'; flow = 'Traffic flow'; probe = 'Health probe'; waf = 'WAF policy'; redirect = 'Redirect'; dependency = 'Uses' }
    $common = 'edgeStyle=orthogonalEdgeStyle;rounded=1;orthogonalLoop=1;jettySize=auto;html=1;fontSize=10;fontColor=#475569;labelBackgroundColor=#FFFFFF;'
    $healthColor = @{ healthy = '#008A6E'; degraded = '#B8730A'; unhealthy = '#D13447'; unknown = '#8C9BB0'; redirect = '#0078D4' }

    # --- Helpers ---------------------------------------------------------------------------------------------------
    $esc = { param([string] $Text) [System.Security.SecurityElement]::Escape($Text) }
    # A key of a model row, or nothing (the models differ in what they carry).
    $get = { param($Table, [string] $Key) if ($Table -is [System.Collections.IDictionary] -and $Table.Contains($Key)) { $Table[$Key] } }
    $sha = [System.Security.Cryptography.SHA1]::Create()
    $hash = { param([string] $Text) [Convert]::ToHexString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text.ToLowerInvariant()))).Substring(0, 16).ToLowerInvariant() }
    $iconCache = @{}
    $iconUri = {
        param([string] $Key)
        if (-not $Key -or -not $Icons.icons.Contains($Key)) { $Key = 'resource' }
        if (-not $Icons.icons.Contains($Key)) { return '' }
        if (-not $iconCache.Contains($Key)) { $iconCache[$Key] = 'data:image/svg+xml,' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([string]$Icons.icons[$Key].svg)) }
        $iconCache[$Key]
    }
    # The portal opens a resource from its ID; a gateway's part opens its gateway.
    $portal = {
        param($Item)
        $target = if (& $get $Item 'portal') { [string]$Item.portal } else { [string]$Item.id }
        if ($target -match '^/subscriptions/') { "https://portal.azure.com/#resource$target" } else { '' }
    }

    $clusters = [ordered]@{}
    foreach ($c in @($Map.Clusters)) { $clusters[[string]$c.id] = $c }
    $nodeById = @{}
    foreach ($n in @($Map.Nodes)) { $nodeById[[string]$n.id] = $n }
    $parentOf = { param([string] $Id) $p = if ($clusters.Contains($Id)) { [string](& $get $clusters[$Id] 'parent') } elseif ($nodeById.Contains($Id)) { [string](& $get $nodeById[$Id] 'parent') } else { '' }; if ($p -and $clusters.Contains($p)) { $p } else { '' } }

    # --- Pages: everything, or a page per box of -SplitBy -------------------------------------------------------
    $pages = [System.Collections.Generic.List[object]]::new()
    $splitRoots = @(if ($SplitBy) { $clusters.Values | Where-Object { [string]$_.kind -eq $SplitBy } | Sort-Object -Property { [string]$_.name } })
    if ($splitRoots.Count) {
        $rootOf = @{}
        $findRoot = { param([string] $Id) $at = $Id; while ($at) { if ($clusters.Contains($at) -and [string]$clusters[$at].kind -eq $SplitBy) { return $at }; $at = & $parentOf $at }; '' }
        foreach ($id in @($clusters.Keys) + @($nodeById.Keys)) { $rootOf[$id] = & $findRoot $id }
        foreach ($r in $splitRoots) {
            # A box's page is named after it and what holds it.
            $holder = & $parentOf ([string]$r.id)
            $name = [string]$r.name + $(if ($holder) { " ($([string]$clusters[$holder].name))" } else { '' })
            $pages.Add(@{ Name = $name; Root = [string]$r.id; Members = [System.Collections.Generic.HashSet[string]]@(@($rootOf.Keys | Where-Object { $rootOf[$_] -eq [string]$r.id })) })
        }
        $rest = @($rootOf.Keys | Where-Object { -not $rootOf[$_] })
        # What isn't in a box of that kind: the boxes above them only hold them, so only resources make an 'Other' page.
        $restNodes = @($rest | Where-Object { $nodeById.Contains($_) })
        if ($restNodes.Count) {
            $members = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($id in $restNodes) { [void]$members.Add($id); $p = & $parentOf $id; while ($p) { [void]$members.Add($p); $p = & $parentOf $p } }
            $pages.Add(@{ Name = 'Other'; Root = ''; Members = $members })
        }
    }
    else {
        $pages.Add(@{ Name = $Title; Root = ''; Members = $null })
    }

    $pageXml = [System.Text.StringBuilder]::new()
    $pageStats = [System.Collections.Generic.List[object]]::new()
    $usedBoxKinds = [System.Collections.Generic.HashSet[string]]::new()
    $usedEdgeKinds = [System.Collections.Generic.HashSet[string]]::new()
    $totalShapes = 0; $totalEdges = 0

    foreach ($page in $pages) {
        $inPage = { param([string] $Id) $null -eq $page.Members -or $page.Members.Contains($Id) }
        # The tree on this page: the root box (or none), each box's resources and child boxes.
        $childBoxes = @{}; $childNodes = @{}
        foreach ($c in $clusters.Values) {
            $id = [string]$c.id
            if (-not (& $inPage $id)) { continue }
            $p = if ($page.Root -and $id -eq $page.Root) { '' } else { & $parentOf $id }
            if (-not $childBoxes.Contains($p)) { $childBoxes[$p] = [System.Collections.Generic.List[object]]::new() }
            $childBoxes[$p].Add($c)
        }
        foreach ($n in $nodeById.Values) {
            $id = [string]$n.id
            if (-not (& $inPage $id)) { continue }
            $p = & $parentOf $id
            if (-not $childNodes.Contains($p)) { $childNodes[$p] = [System.Collections.Generic.List[object]]::new() }
            $childNodes[$p].Add($n)
        }

        # Sizes, bottom up; positions are relative to each box's content area.
        $size = @{}; $place = @{}
        $measure = $null
        $measure = {
            param([string] $Id, [string] $Kind)
            $nodes = @(if ($childNodes.Contains($Id)) { $childNodes[$Id] })
            $boxes = @(if ($childBoxes.Contains($Id)) { $childBoxes[$Id] | Sort-Object -Property @{ Expression = { @{ managementgroup = 0; subscription = 1; region = 2; resourcegroup = 3; vnet = 4; subnet = 5; appgw = 6 }[[string]$_.kind] } }, @{ Expression = { [string]$_.name } } })
            foreach ($b in $boxes) { & $measure ([string]$b.id) ([string]$b.kind) }
            $stageOf = { param($N) $e = & $get $N 'elk'; if ($e -is [System.Collections.IDictionary] -and $e.Contains('elk.partitioning.partition')) { [int]$e['elk.partitioning.partition'] } else { $null } }
            $staged = $nodes.Count -and -not @($nodes | Where-Object { $null -eq (& $stageOf $_) }).Count
            $placedNodes = [System.Collections.Generic.List[object]]::new()
            $gridW = 0; $gridH = 0
            if ($staged) {
                # A flow: a column per stage, left to right.
                $col = 0
                foreach ($group in @($nodes | Group-Object -Property { & $stageOf $_ } | Sort-Object -Property { [int]$_.Name })) {
                    $row = 0
                    foreach ($n in @($group.Group | Sort-Object -Property { [string]$_.name })) { $placedNodes.Add(@{ n = $n; x = $col * ($nodeW + $gap * 2); y = $row * ($nodeH + $gap) }); $row++ }
                    $gridH = [Math]::Max($gridH, $row * ($nodeH + $gap) - $gap); $col++
                }
                $gridW = $col * ($nodeW + $gap * 2) - $gap * 2
            }
            elseif ($nodes.Count) {
                $perRow = [Math]::Max(1, [Math]::Min($nodes.Count, $(if ($perRowOf.Contains($Kind)) { $perRowOf[$Kind] } else { 6 })))
                $sorted = @($nodes | Sort-Object -Property @{ Expression = { [string]$_.type } }, @{ Expression = { [string]$_.name } })
                for ($i = 0; $i -lt $sorted.Count; $i++) { $placedNodes.Add(@{ n = $sorted[$i]; x = ($i % $perRow) * ($nodeW + $gap); y = [Math]::Floor($i / $perRow) * ($nodeH + $gap) }) }
                $gridW = $perRow * $nodeW + ($perRow - 1) * $gap
                $gridH = [Math]::Ceiling($sorted.Count / $perRow) * ($nodeH + $gap) - $gap
            }
            # Child boxes in rows under the resources: a new row when the next would pass the width.
            $limit = [Math]::Max($gridW, $(if ($maxWidth.Contains($Kind)) { $maxWidth[$Kind] } else { 2400 }))
            $x = 0; $y = if ($nodes.Count) { $gridH + $gap } else { 0 }; $rowH = 0; $usedW = $gridW
            $placedBoxes = foreach ($b in $boxes) {
                $bw, $bh = $size[[string]$b.id]
                if ($x -gt 0 -and $x + $bw -gt $limit) { $x = 0; $y += $rowH + $gap; $rowH = 0 }
                @{ c = $b; x = $x; y = $y }
                $x += $bw + $gap; $rowH = [Math]::Max($rowH, $bh); $usedW = [Math]::Max($usedW, $x - $gap)
            }
            $contentH = if ($boxes.Count) { $y + $rowH } else { $gridH }
            $place[$Id] = @{ nodes = $placedNodes.ToArray(); boxes = @($placedBoxes) }
            $minW = if ($Kind -eq 'subnet') { 380 } else { 280 }
            if ($Id) { $size[$Id] = @([Math]::Max($minW, $usedW + 2 * $pad), ([Math]::Max(60, $contentH) + $header + 2 * $pad)) } else { $size[''] = @($usedW, $contentH) }
        }
        & $measure '' ''

        $cells = [System.Text.StringBuilder]::new()
        $ids = @{}
        $shapes = 0
        $emit = $null
        $emit = {
            param([string] $Id, [string] $ParentCell, [double] $OffsetX, [double] $OffsetY)
            foreach ($pb in $place[$Id].boxes) {
                $c = $pb.c
                $kind = [string]$c.kind
                [void]$usedBoxKinds.Add($kind)
                $cid = 'aac-' + (& $hash ([string]$c.id)); $ids[[string]$c.id] = $cid
                $w, $h = $size[[string]$c.id]
                $extra = @(
                    @(& $get $c 'detail')
                    if ($kind -eq 'subnet' -and (& $get $c 'usable')) { "$(& $get $c 'used') of $(& $get $c 'usable') IPs used" }
                    @(& $get $c 'badges')
                    if (& $get $c 'role') { [string]$c.role }
                ) | Where-Object { $_ }
                $label = "<b>$(& $esc ([string]$c.name))</b>"
                if ($extra) { $label += "&nbsp;&nbsp;<span style='font-weight:normal;font-size:11px;color:#5B6B80'>$(& $esc ((@($extra) | Select-Object -Unique) -join '  ·  '))</span>" }
                $style = $(if ($styleOf.Contains($kind)) { $styleOf[$kind] } else { $box + 'fillColor=#F1F3F6;swimlaneFillColor=#FFFFFF;strokeColor=#A3AEBE;fontSize=13;' }) + $(if (& $get $c 'external') { 'opacity=60;' } else { '' })
                $link = & $portal $c
                $attrs = 'aacKind="' + (& $esc $kind) + '" resourceId="' + (& $esc ([string]$c.id)) + '" aacLabel="' + (& $esc $label) + '"'
                if ($link) { $attrs += ' link="' + (& $esc $link) + '"' }
                [void]$cells.AppendLine("        <object id=`"$cid`" label=`"$(& $esc $label)`" $attrs><mxCell style=`"$style`" vertex=`"1`" parent=`"$ParentCell`"><mxGeometry x=`"$($OffsetX + $pb.x)`" y=`"$($OffsetY + $pb.y)`" width=`"$w`" height=`"$h`" as=`"geometry`"/></mxCell></object>")
                $counter.Shapes++
                & $emit ([string]$c.id) $cid $pad ($header + $pad)
            }
            foreach ($pn in $place[$Id].nodes) {
                $n = $pn.n
                $cid = 'aac-' + (& $hash ([string]$n.id)); $ids[[string]$n.id] = $cid
                $typeLabel = if (& $get $n 'typeLabel') { [string]$n.typeLabel } else { ([string]$n.type -split '/')[-1] }
                $health = [string](& $get $n 'health')
                $label = "<b>$(& $esc ([string]$n.name))</b><br><span style='font-size:9px;color:#5B6B80'>$(& $esc $typeLabel)</span>"
                if ($health -and $healthColor.Contains($health)) { $label += "<br><span style='font-size:9px;color:$($healthColor[$health])'>&#9679; $(& $esc $health)</span>" }
                $uri = & $iconUri ([string](& $get $n 'icon'))
                $style = if ($uri) { "image;html=1;aspect=fixed;image=$uri;verticalLabelPosition=bottom;verticalAlign=top;labelPosition=center;align=center;fontSize=11;whiteSpace=wrap;labelWidth=136;" }
                else { 'rounded=1;html=1;whiteSpace=wrap;fillColor=#FFFFFF;strokeColor=#8C9BB0;fontSize=10;verticalLabelPosition=bottom;verticalAlign=top;labelWidth=136;' }
                if (& $get $n 'orphan') { $style += 'fontColor=#D13447;' }
                if ((& $get $n 'risk') -eq 'high') { $style += 'imageBorder=#D13447;' }
                if (& $get $n 'external') { $style += 'opacity=55;' }
                $tip = (@([string]$n.type, [string]$n.id, $(if (& $get $n 'orphan') { "Unattached: $($n.orphan)" }), $(if (@(& $get $n 'facts').Count) { @(& $get $n 'facts') -join ' · ' }), @(& $get $n 'findings')) | Where-Object { $_ }) -join "`n"
                $link = & $portal $n
                $attrs = @(
                    "tooltip=`"$(& $esc $tip)`""
                    "resourceType=`"$(& $esc ([string]$n.type))`""
                    "resourceId=`"$(& $esc ([string]$n.id))`""
                    "location=`"$(& $esc ([string](& $get $n 'location')))`""
                    "resourceGroup=`"$(& $esc ([string](& $get $n 'resourceGroup')))`""
                    "subscription=`"$(& $esc ([string](& $get $n 'subscription')))`""
                    "aacLabel=`"$(& $esc $label)`""
                    if ($link) { "link=`"$(& $esc $link)`"" }
                ) -join ' '
                $x = $OffsetX + $pn.x + ($nodeW - $iconSize) / 2
                [void]$cells.AppendLine("        <object id=`"$cid`" label=`"$(& $esc $label)`" $attrs><mxCell style=`"$style`" vertex=`"1`" parent=`"$ParentCell`"><mxGeometry x=`"$x`" y=`"$($OffsetY + $pn.y)`" width=`"$iconSize`" height=`"$iconSize`" as=`"geometry`"/></mxCell></object>")
                $counter.Shapes++
            }
        }
        $counter = @{ Shapes = 0 }
        & $emit '' '1' 40 40
        $shapes = $counter.Shapes
        $connections = 0
        $seen = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($e in @($Map.Edges)) {
            # The map page's alternative view (NSGs as cards) isn't the default one.
            if ((& $get $e 'view') -eq 'cards') { continue }
            $source = [string]$e.source; $target = [string]$e.target
            if (-not $ids.Contains($source) -or -not $ids.Contains($target)) { continue }
            $kind = [string]$e.kind
            $eid = 'aac-e-' + (& $hash "$source|$target|$kind")
            if (-not $seen.Add($eid)) { continue }
            [void]$usedEdgeKinds.Add($(if ($edgeStyle.Contains($kind)) { $kind } else { 'dependency' }))
            $style = $common + $(if ($edgeStyle.Contains($kind)) { $edgeStyle[$kind] } else { $edgeStyle.dependency }) + $(if (& $get $e 'warn') { 'strokeColor=#D13447;' } else { '' })
            [void]$cells.AppendLine("        <mxCell id=`"$eid`" value=`"$(& $esc ([string](& $get $e 'label')))`" style=`"$style`" edge=`"1`" parent=`"1`" source=`"$($ids[$source])`" target=`"$($ids[$target])`"><mxGeometry relative=`"1`" as=`"geometry`"/></mxCell>")
            $connections++
        }
        $pageId = 'aac-page-' + (& $hash ([string]$(if ($page.Root) { $page.Root } else { $page.Name })))
        [void]$pageXml.AppendLine("  <diagram id=`"$pageId`" name=`"$(& $esc $page.Name)`">")
        [void]$pageXml.AppendLine('    <mxGraphModel grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="0" pageScale="1" math="0" shadow="0">')
        [void]$pageXml.AppendLine("      <root>`n        <mxCell id=`"0`"/>`n        <mxCell id=`"1`" parent=`"0`"/>")
        [void]$pageXml.Append($cells.ToString())
        [void]$pageXml.AppendLine("      </root>`n    </mxGraphModel>`n  </diagram>")
        $pageStats.Add(@{ Name = $page.Name; Shapes = $shapes; Connections = $connections })
        $totalShapes += $shapes; $totalEdges += $connections
    }

    # --- Legend: the kinds used, the facts, how to refresh ------------------------------------------------------------
    if ($Legend) {
        $cells = [System.Text.StringBuilder]::new()
        $y = 40
        [void]$cells.AppendLine("        <mxCell id=`"aac-legend-title`" value=`"$(& $esc "<b style='font-size:20px'>$(& $esc $Title)</b>")`" style=`"text;html=1;align=left;verticalAlign=top;whiteSpace=wrap;`" vertex=`"1`" parent=`"1`"><mxGeometry x=`"40`" y=`"$y`" width=`"900`" height=`"36`" as=`"geometry`"/></mxCell>")
        $y += 44
        if ($Fact.Count) {
            [void]$cells.AppendLine("        <mxCell id=`"aac-legend-facts`" value=`"$(& $esc (($Fact | ForEach-Object { [System.Security.SecurityElement]::Escape($_) }) -join '<br>'))`" style=`"text;html=1;align=left;verticalAlign=top;whiteSpace=wrap;fontColor=#475569;fontSize=12;`" vertex=`"1`" parent=`"1`"><mxGeometry x=`"40`" y=`"$y`" width=`"900`" height=`"$(18 * $Fact.Count + 10)`" as=`"geometry`"/></mxCell>")
            $y += 18 * $Fact.Count + 24
        }
        $i = 0
        foreach ($kind in @('tenant', 'managementgroup', 'subscription', 'region', 'resourcegroup', 'vnet', 'subnet', 'appgw') | Where-Object { $usedBoxKinds.Contains($_) }) {
            $x = 40 + ($i % 4) * 230; $yy = $y + [Math]::Floor($i / 4) * 90
            [void]$cells.AppendLine("        <mxCell id=`"aac-legend-box-$kind`" value=`"$(& $esc "<b>$($boxLabel[$kind])</b>")`" style=`"$($styleOf[$kind])`" vertex=`"1`" parent=`"1`"><mxGeometry x=`"$x`" y=`"$yy`" width=`"210`" height=`"70`" as=`"geometry`"/></mxCell>")
            $i++
        }
        $y += [Math]::Ceiling([Math]::Max(1, $i) / 4) * 90 + 20
        $i = 0
        foreach ($kind in @($edgeStyle.Keys | Where-Object { $usedEdgeKinds.Contains($_) })) {
            $x = 40 + ($i % 2) * 460; $yy = $y + [Math]::Floor($i / 2) * 36
            [void]$cells.AppendLine("        <mxCell id=`"aac-legend-edge-$kind`" value=`"`" style=`"$('endArrow=none;html=1;' + $edgeStyle[$kind])`" edge=`"1`" parent=`"1`"><mxGeometry relative=`"1`" as=`"geometry`"><mxPoint x=`"$x`" y=`"$($yy + 10)`" as=`"sourcePoint`"/><mxPoint x=`"$($x + 120)`" y=`"$($yy + 10)`" as=`"targetPoint`"/></mxGeometry></mxCell>")
            [void]$cells.AppendLine("        <mxCell id=`"aac-legend-edge-$kind-text`" value=`"$(& $esc $edgeName[$kind])`" style=`"text;html=1;align=left;verticalAlign=middle;fontSize=12;`" vertex=`"1`" parent=`"1`"><mxGeometry x=`"$($x + 136)`" y=`"$yy`" width=`"300`" height=`"20`" as=`"geometry`"/></mxCell>")
            $i++
        }
        $y += [Math]::Ceiling([Math]::Max(1, $i) / 2) * 36 + 24
        $notes = @(
            '<b>Red name</b>: attached to nothing (an unattached disk, NIC, public IP...). <b>Faded</b>: outside what you asked for, shown because something inside uses it.'
            'Every shape keeps its resource ID, type, location, resource group and subscription (Edit &gt; Edit Data, or hover); Ctrl+click opens it in the Azure portal.'
            'Edit freely: move, restyle, add notes and shapes. <b>Export-AACDiagram -Update</b> refreshes the diagram from Azure and keeps your changes - new resources are added and marked, removed ones greyed out (-Prune deletes them).'
        )
        [void]$cells.AppendLine("        <mxCell id=`"aac-legend-notes`" value=`"$(& $esc ($notes -join '<br><br>'))`" style=`"text;html=1;align=left;verticalAlign=top;whiteSpace=wrap;fontSize=12;fontColor=#1B2A41;`" vertex=`"1`" parent=`"1`"><mxGeometry x=`"40`" y=`"$y`" width=`"900`" height=`"150`" as=`"geometry`"/></mxCell>")
        [void]$pageXml.AppendLine('  <diagram id="aac-page-legend" name="Legend">')
        [void]$pageXml.AppendLine('    <mxGraphModel grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="0" pageScale="1" math="0" shadow="0">')
        [void]$pageXml.AppendLine("      <root>`n        <mxCell id=`"0`"/>`n        <mxCell id=`"1`" parent=`"0`"/>")
        [void]$pageXml.Append($cells.ToString())
        [void]$pageXml.AppendLine("      </root>`n    </mxGraphModel>`n  </diagram>")
    }

    $version = if ($script:AACModuleRoot -and (Test-Path -LiteralPath (Join-Path $script:AACModuleRoot 'Azure.Admin.Console.psd1'))) { [string](Import-PowerShellDataFile -LiteralPath (Join-Path $script:AACModuleRoot 'Azure.Admin.Console.psd1')).ModuleVersion } else { '' }
    $xml = "<mxfile host=`"Azure.Admin.Console`" agent=`"Azure.Admin.Console $version`" modified=`"$([datetime]::UtcNow.ToString('o'))`" version=`"24.7.0`">`n$($pageXml.ToString().TrimEnd())`n</mxfile>`n"
    @{ Xml = $xml; Pages = $pageStats.ToArray(); Shapes = $totalShapes; Connections = $totalEdges }
}
