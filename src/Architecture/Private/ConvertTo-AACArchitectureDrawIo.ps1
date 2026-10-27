function ConvertTo-AACArchitectureDrawIo {
    <#
    .SYNOPSIS
        Draws a design as an editable, multi-page draw.io file with Azure
        icons: a cover, the architecture, policy and compliance, findings and
        a legend.
    .DESCRIPTION
        Pages (tabs at the bottom of draw.io):
          Cover                 the design's facts, open findings by severity,
                                pillar scores and links to the other pages.
          Architecture          the landing zone (or subscription) holding the
                                global edge, a box per region - hub virtual
                                network, spoke (workload) and data - and
                                operations; the delivery pipeline below. Each
                                component is its Azure icon with a dot for its
                                worst open finding, and carries its details as
                                shape data (Edit > Edit Data). The compliance
                                layers - WAF, Azure Policy, Guardrails, PSRule
                                and Recommendations - are draw.io layers
                                (View > Layers) so they can be hidden.
          Policy and compliance the inherited Azure Policy assignments, the
                                allowed locations, and every design rule that
                                applies to each component with its Azure Policy,
                                PSRule for Azure rule and result.
          Findings              every finding with what to do, then the open
                                decisions and assumptions.
          Legend                the icons used, the colours, the lines, the
                                boxes and the layers.
        Icons come from lib\azure-icons (Get-AACAzureIconSet) and are embedded,
        so the file opens offline. Returns the .drawio XML.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Design,

        [AllowEmptyCollection()]
        [object[]] $Finding = @(),

        # The pillar scores (Invoke-AACArchitectureRule .Pillars), for the cover.
        [AllowEmptyCollection()]
        [object[]] $Pillar = @(),

        [hashtable] $Catalog = (Get-AACArchitectureCatalog),

        [string[]] $Layer = @('Waf', 'Policy', 'Guardrail', 'PSRule', 'Recommendations'),

        [string] $PSRuleBaseline = 'Azure.Default',

        # The icon set (Get-AACAzureIconSet): types and icons.
        [hashtable] $Icons = (Get-AACAzureIconSet)
    )

    # --- Look ------------------------------------------------------------------------------------------------------
    $slotW, $slotH, $iconSize, $pad, $head, $gap = 160, 136, 48, 20, 36, 28
    $box = 'swimlane;html=1;whiteSpace=wrap;startSize=36;rounded=1;arcSize=2;fontStyle=1;align=left;spacingLeft=12;'
    $boxStyle = @{
        landingzone = $box + 'fillColor=#E3E7ED;swimlaneFillColor=#FAFBFC;strokeColor=#6B7A90;fontSize=15;fontColor=#1B2A41;'
        edge        = $box + 'fillColor=#FCEBDC;swimlaneFillColor=#FFFBF7;strokeColor=#D9730D;fontSize=13;fontColor=#5C2E05;'
        region      = $box + 'fillColor=#E6F3EF;swimlaneFillColor=#F8FCFA;strokeColor=#008A6E;dashed=1;fontSize=14;fontColor=#0B4A3C;'
        vnet        = $box + 'fillColor=#DCEBFA;swimlaneFillColor=#F2F8FE;strokeColor=#0078D4;fontSize=13;fontColor=#0B3B66;'
        workload    = $box + 'fillColor=#E7ECF3;swimlaneFillColor=#F7F9FC;strokeColor=#8C9BB0;fontSize=13;fontColor=#1B2A41;'
        data        = $box + 'fillColor=#F3EAFB;swimlaneFillColor=#FCF9FE;strokeColor=#8661C5;fontSize=13;fontColor=#3B2266;'
        operations  = $box + 'fillColor=#F1F3F6;swimlaneFillColor=#FFFFFF;strokeColor=#A3AEBE;fontSize=13;fontColor=#1B2A41;'
        pipeline    = $box + 'fillColor=#EEF2F6;swimlaneFillColor=#FFFFFF;strokeColor=#5F6B7A;dashed=1;fontSize=13;fontColor=#1B2A41;'
    }
    $boxName = [ordered]@{ landingzone = 'Landing zone or subscription'; edge = 'Global edge'; region = 'Azure region'; vnet = 'Virtual network (hub or spoke)'; workload = 'Workload (no virtual network)'; data = 'Data tier'; operations = 'Operations'; pipeline = 'Delivery pipeline' }
    $guardStyle = 'rounded=1;arcSize=3;dashed=1;dashPattern=8 4;fillColor=none;strokeColor=#7C3AED;strokeWidth=2;verticalAlign=bottom;align=right;spacingRight=8;fontSize=10;fontColor=#7C3AED;pointerEvents=0;html=1;'
    $tone = @{ ok = '#1E8E3E'; warn = '#F9AB00'; bad = '#D93025'; neutral = '#80868B' }
    $toneName = [ordered]@{ ok = 'No open finding'; warn = 'Medium or low finding open'; bad = 'Blocking or high finding open'; neutral = 'Platform or delivery component (not scored)' }
    $severityFill = @{ Blocking = '#FCE8E6'; High = '#FCE8E6'; Medium = '#FEF7E0'; Low = '#FEF7E0' }
    $lineStyle = [ordered]@{ data = 'strokeColor=#0078D4;strokeWidth=2;'; private = 'strokeColor=#1E8E3E;strokeWidth=2;dashed=1;'; control = 'strokeColor=#80868B;dashed=1;dashPattern=1 3;'; pipeline = 'strokeColor=#5F6368;strokeWidth=2;' }
    $lineName = @{ data = 'Request or data flow'; private = 'Private endpoint or private link'; control = 'Control or management'; pipeline = 'Delivery pipeline' }
    $common = 'edgeStyle=orthogonalEdgeStyle;rounded=1;orthogonalLoop=1;jettySize=auto;html=1;endArrow=block;endFill=1;fontSize=10;fontColor=#475569;labelBackgroundColor=#FFFFFF;'
    $text = 'text;html=1;whiteSpace=wrap;align=left;verticalAlign=top;strokeColor=none;fillColor=none'
    $short = @{ Reliability = 'R'; Security = 'S'; 'Cost Optimization' = 'C'; 'Operational Excellence' = 'O'; 'Performance Efficiency' = 'P' }
    $infraKinds = @('pipeline', 'gate', 'network', 'dns', 'budget', 'monitor')
    $iconOfKind = @{
        app = 'appservice'; functions = 'functionapp'; container = 'aci'; datafactory = 'datafactory'; cosmos = 'cosmos'; database = 'sqldb'; storage = 'storage'
        openai = 'openai'; search = 'search'; apim = 'apim'; cache = 'redis'; queue = 'servicebus'; events = 'eventgridtopic'; keyvault = 'keyvault'
        network = 'vnet'; dns = 'dnszone'; firewall = 'firewall'; budget = 'alert'; monitor = 'loganalytics'; gateway = 'appgw'
    }
    $layerId = [ordered]@{ Waf = 'architecture-waf'; Policy = 'architecture-policy'; Guardrail = 'architecture-guard'; PSRule = 'architecture-psrule'; Recommendations = 'architecture-rec' }
    $layerName = @{ Waf = 'WAF'; Policy = 'Azure Policy'; Guardrail = 'Guardrails'; PSRule = 'PSRule'; Recommendations = 'Recommendations' }
    $layerHelp = [ordered]@{
        Architecture    = 'The components, their boxes and connections; the dot is the worst open finding.'
        Waf             = 'Open findings by Well-Architected pillar under each component (R S C O P; !! blocking or high, ! other).'
        Policy          = 'How many Azure Policy definitions the design rules map to each component; the chip links to the Policy and compliance page.'
        Guardrail       = 'A dashed purple boundary round each tier your guardrails and the design rules check.'
        PSRule          = 'The PSRule for Azure baseline and rule count on the pipeline gate.'
        Recommendations = 'Azure Advisor and Defender for Cloud feeding the backlog.'
    }

    # --- Helpers ---------------------------------------------------------------------------------------------------
    $esc = { param([string] $Value) [System.Security.SecurityElement]::Escape($Value) }
    $html = { param([string] $Value) [System.Net.WebUtility]::HtmlEncode($Value) }
    $num = { param([double] $Value) $Value.ToString('0.##', [cultureinfo]::InvariantCulture) }
    $want = { param([string] $Name) $Layer -contains $Name }
    $answer = { param([string] $Id) if ($Design['Answers'] -is [System.Collections.IDictionary] -and $Design.Answers.Contains($Id)) { [string]$Design.Answers[$Id] } else { '' } }
    $today = [datetime]::UtcNow.ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture)
    $open = @($Finding | Where-Object { $_.Status -eq 'Open' })
    $iconCache = @{}
    $usedIcons = [ordered]@{}
    $iconKey = {
        param([hashtable] $Node)
        $kind = [string]$Node.Kind
        if ($kind -eq 'app' -and $Node.Name -like 'Logic*') { return 'logicapp' }
        if ($kind -eq 'gateway' -and $Node.Name -like 'Front Door*') { return 'frontdoor' }
        if ($kind -eq 'monitor' -and $Node.Name -like '*Insights*') { return 'appinsights' }
        if ($iconOfKind.Contains($kind)) { return $iconOfKind[$kind] }
        # Anything newer: its ARM type, as the resource map maps it.
        $type = ([string]$Node.Service -replace ' .*$', '').ToLowerInvariant()
        if ($type -and $Icons.types.Contains($type)) { return [string]$Icons.types[$type] }
        'resource'
    }
    $iconUri = {
        param([string] $Key)
        if (-not $Icons.icons.Contains($Key)) { $Key = 'resource' }
        if (-not $iconCache.Contains($Key)) {
            $iconCache[$Key] = 'data:image/svg+xml,' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([string]$Icons.icons[$Key].svg))
            $usedIcons[$Key] = [string]$Icons.icons[$Key].label
        }
        $iconCache[$Key]
    }
    $iconStyle = { param([string] $Key, [int] $LabelWidth = ($slotW - 12)) "image;html=1;aspect=fixed;image=$(& $iconUri $Key);verticalLabelPosition=bottom;verticalAlign=top;labelPosition=center;align=center;fontSize=11;whiteSpace=wrap;labelWidth=$LabelWidth;" }

    # A page collects its cells; ids are prefixed with the page's so they're unique in the file.
    $newPage = { param([string] $Id, [string] $Name) @{ Id = $Id; Name = $Name; Cells = [System.Text.StringBuilder]::new(); N = 0 } }
    $vertex = {
        param([hashtable] $Page, [string] $Value, [string] $Style, [double] $X, [double] $Y, [double] $W, [double] $H, [string] $Parent = '', [string] $CellId = '', [System.Collections.IDictionary] $Data = $null)
        if (-not $Parent) { $Parent = "$($Page.Id)-1" }
        if (-not $CellId) { $Page.N++; $CellId = "$($Page.Id)-c$($Page.N)" }
        $geometry = "<mxGeometry x=`"$(& $num $X)`" y=`"$(& $num $Y)`" width=`"$(& $num $W)`" height=`"$(& $num $H)`" as=`"geometry`" />"
        if ($Data -and $Data.Count) {
            # Shape data (Edit > Edit Data): only the keys with a value.
            $attrs = (@($Data.Keys | Where-Object { [string]$Data[$_] } | ForEach-Object { "$_=`"$(& $esc ([string]$Data[$_]))`"" })) -join ' '
            $null = $Page.Cells.AppendLine("        <object id=`"$CellId`" label=`"$(& $esc $Value)`" $attrs><mxCell style=`"$Style`" vertex=`"1`" parent=`"$Parent`">$geometry</mxCell></object>")
        }
        else {
            $null = $Page.Cells.AppendLine("        <mxCell id=`"$CellId`" value=`"$(& $esc $Value)`" style=`"$Style`" vertex=`"1`" parent=`"$Parent`">$geometry</mxCell>")
        }
    }
    $connect = {
        param([hashtable] $Page, [string] $Value, [string] $Style, [string] $Source, [string] $Target, [string] $Parent = '')
        if (-not $Parent) { $Parent = "$($Page.Id)-1" }
        $Page.N++
        $null = $Page.Cells.AppendLine("        <mxCell id=`"$($Page.Id)-e$($Page.N)`" value=`"$(& $esc $Value)`" style=`"$common$Style`" edge=`"1`" parent=`"$Parent`" source=`"$Source`" target=`"$Target`"><mxGeometry relative=`"1`" as=`"geometry`" /></mxCell>")
    }
    # A free line between two points (the legend's samples).
    $line = {
        param([hashtable] $Page, [string] $Style, [double] $X1, [double] $Y1, [double] $X2, [double] $Y2)
        $Page.N++
        $null = $Page.Cells.AppendLine("        <mxCell id=`"$($Page.Id)-e$($Page.N)`" value=`"`" style=`"$common$Style`" edge=`"1`" parent=`"$($Page.Id)-1`"><mxGeometry relative=`"1`" as=`"geometry`"><mxPoint x=`"$(& $num $X1)`" y=`"$(& $num $Y1)`" as=`"sourcePoint`" /><mxPoint x=`"$(& $num $X2)`" y=`"$(& $num $Y2)`" as=`"targetPoint`" /></mxGeometry></mxCell>")
    }
    # The band across the top of every page after the cover.
    $banner = {
        param([hashtable] $Page, [string] $Title, [double] $Width)
        & $vertex $Page '' 'rounded=0;fillColor=#0B3B66;strokeColor=none;' 0 0 $Width 64
        & $vertex $Page "<b>$(& $html $Title)</b>&nbsp;&nbsp;<span style='font-size:13px;color:#C7D7EA'>$(& $html $Design.Name)</span>" "$text;fontSize=20;fontColor=#FFFFFF;verticalAlign=middle;" 32 8 ($Width - 64) 48
    }
    $heading = { param([hashtable] $Page, [string] $Title, [double] $X, [double] $Y, [double] $W = 900) & $vertex $Page "<b>$(& $html $Title)</b>" "$text;fontSize=15;fontColor=#0B3B66;" $X $Y $W 24 }
    # A table of plain cells; a row is an array of strings or @{ Text; Fill; Link }. Returns the y under it.
    $table = {
        param([hashtable] $Page, [double] $X, [double] $Y, [object[]] $Columns, [object[]] $Rows)
        $cx = $X
        foreach ($c in $Columns) {
            & $vertex $Page "<b>$(& $html $c.Title)</b>" 'rounded=0;whiteSpace=wrap;html=1;fillColor=#0B3B66;strokeColor=#FFFFFF;fontColor=#FFFFFF;fontSize=11;align=left;spacingLeft=6;' $cx $Y $c.Width 28
            $cx += $c.Width
        }
        $Y += 28
        $i = 0
        foreach ($row in $Rows) {
            $items = @(foreach ($r in @($row)) { if ($r -is [System.Collections.IDictionary]) { $r } else { @{ Text = [string]$r } } })
            # Rows grow with their longest text: about 6 px a character at 10 pt.
            $lines = 1
            for ($k = 0; $k -lt $Columns.Count; $k++) {
                $perLine = [Math]::Max(8, [Math]::Floor(($Columns[$k].Width - 12) / 6.0))
                $lines = [Math]::Max($lines, [Math]::Ceiling([Math]::Max(1, ([string]$items[$k].Text).Length) / $perLine))
            }
            $h = [Math]::Max(26, 10 + 14 * $lines)
            $cx = $X
            for ($k = 0; $k -lt $Columns.Count; $k++) {
                $item = $items[$k]
                $fill = if ($item.Contains('Fill') -and $item.Fill) { $item.Fill } elseif ($i % 2) { '#F7F9FC' } else { '#FFFFFF' }
                $data = if ($item.Contains('Link') -and $item.Link) { @{ link = $item.Link } } else { $null }
                & $vertex $Page (& $html ([string]$item.Text)) "rounded=0;whiteSpace=wrap;html=1;fillColor=$fill;strokeColor=#D0D7E2;fontSize=10;fontColor=#1B2A41;align=left;verticalAlign=middle;spacingLeft=6;spacingRight=4;" $cx $Y $Columns[$k].Width $h '' '' $data
                $cx += $Columns[$k].Width
            }
            $Y += $h
            $i++
        }
        $Y
    }
    $pageXml = {
        param([hashtable] $Page, [double] $Width, [double] $Height, [string] $Layers = '')
        if (-not $Layers) { $Layers = "        <mxCell id=`"$($Page.Id)-1`" parent=`"0`" />" }
        @"
  <diagram id="$($Page.Id)" name="$(& $esc $Page.Name)">
    <mxGraphModel dx="1600" dy="900" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="$([int]$Width)" pageHeight="$([int]$Height)" math="0" shadow="0">
      <root>
        <mxCell id="0" />
$Layers
$($Page.Cells.ToString().TrimEnd())
      </root>
    </mxGraphModel>
  </diagram>
"@
    }
    $pageLink = { param([string] $Id) "data:page/id,$Id" }
    $isInfra = { param([hashtable] $Node) $Node.Kind -in $infraKinds }
    $toneOf = {
        param([hashtable] $Node)
        if (& $isInfra $Node) { return 'neutral' }
        $f = @($open | Where-Object NodeId -EQ $Node.Id)
        if (@($f | Where-Object Severity -In 'Blocking', 'High').Count) { 'bad' } elseif ($f.Count) { 'warn' } else { 'ok' }
    }
    $rulesOf = { param([hashtable] $Node) @($Catalog.Rules | Where-Object { @($_.Scope) -contains $Node.Kind }) }
    $policiesOf = { param([hashtable] $Node) @(& $rulesOf $Node | Where-Object { $_.Policy } | ForEach-Object Policy | Select-Object -Unique) }
    $patternName = { param([string] $Id) $p = $Catalog.Patterns | Where-Object Id -EQ $Id | Select-Object -First 1; if ($p) { $p.Name } else { $Id } }
    $landing = if ($Design.LandingZone) { "Landing zone: $($Design.LandingZone)" } else { 'Subscription (no landing zone read)' }
    $regions = @($Design.Regions)

    # --- Architecture: boxes sized bottom up, then drawn top down ---------------------------------------------------
    $arch = & $newPage 'architecture' 'Architecture'
    $nodesIn = { param([string[]] $Zone, [string] $Region) @($Design.Nodes | Where-Object { $_.Zone -in $Zone -and ($Region -eq '*' -or $_.Region -eq $Region) }) }
    $makeBox = {
        param([string] $Title, [string] $Kind, [object[]] $Nodes, [int] $PerRow, [string] $NodeId = '', [bool] $Guard = $false, [int] $Extra = 0)
        $count = [Math]::Max(1, @($Nodes).Count + $Extra)
        $cols = [Math]::Min($count, $PerRow)
        $rows = [Math]::Ceiling($count / $cols)
        @{ Title = $Title; Kind = $Kind; Nodes = @($Nodes); PerRow = $cols; NodeId = $NodeId; Guard = $Guard; Extra = $Extra; Children = @(); W = $cols * $slotW + 2 * $pad; H = $rows * $slotH + $head + $pad }
    }
    $wrap = {
        # A box of boxes, side by side, all as tall as the tallest.
        param([string] $Title, [string] $Kind, [object[]] $Children)
        $tallest = [double](@($Children | ForEach-Object { $_.H }) | Measure-Object -Maximum).Maximum
        foreach ($c in $Children) { $c.H = $tallest }
        @{ Title = $Title; Kind = $Kind; Nodes = @(); PerRow = 1; NodeId = ''; Guard = $false; Extra = 0; Children = @($Children)
            W = [double](@($Children | ForEach-Object { $_.W }) | Measure-Object -Sum).Sum + $gap * ($Children.Count - 1) + 2 * $pad; H = $tallest + $head + $pad }
    }
    $top = [System.Collections.Generic.List[hashtable]]::new()
    $edgeNodes = @(& $nodesIn 'Edge' '*')
    if ($edgeNodes.Count) { $top.Add((& $makeBox 'Global edge' 'edge' $edgeNodes 1)) }
    foreach ($region in $regions) {
        $children = [System.Collections.Generic.List[hashtable]]::new()
        $hubNodes = @(& $nodesIn 'Hub' $region)
        if ($hubNodes.Count) {
            $hubNet = $hubNodes | Where-Object Kind -EQ 'network' | Select-Object -First 1
            $children.Add((& $makeBox $(if ($hubNet) { "$($hubNet.Name)" } else { 'Hub' }) 'vnet' @($hubNodes | Where-Object Kind -NE 'network') 1 $(if ($hubNet) { $hubNet.Id } else { '' })))
        }
        $spokeNodes = @(& $nodesIn 'Spoke', 'Integration' $region)
        $spokeNet = $spokeNodes | Where-Object Kind -EQ 'network' | Select-Object -First 1
        $children.Add((& $makeBox $(if ($spokeNet) { "$($spokeNet.Name) - workload" } else { 'Workload' }) $(if ($spokeNet) { 'vnet' } else { 'workload' }) @($spokeNodes | Where-Object Kind -NE 'network') 2 $(if ($spokeNet) { $spokeNet.Id } else { '' }) $true))
        $dataNodes = @(& $nodesIn 'Data' $region)
        if ($dataNodes.Count) { $children.Add((& $makeBox $(if (@($dataNodes | Where-Object { $_.PrivateEndpoint }).Count) { 'Data - private endpoints' } else { 'Data' }) 'data' $dataNodes 2 '' $true)) }
        $top.Add((& $wrap "Region - $region$(if ($region -eq $regions[0] -and $regions.Count -gt 1) { ' (primary)' } elseif ($regions.Count -gt 1) { ' (secondary)' })" 'region' $children.ToArray()))
    }
    $opsNodes = @(& $nodesIn 'Operations' '*')
    $top.Add((& $makeBox 'Operations' 'operations' $opsNodes 1 '' $false $(if (& $want 'Recommendations') { 1 } else { 0 })))
    $groups = @($Design['ManagementGroups'] | Where-Object { $_ } | ForEach-Object { if ($_ -is [System.Collections.IDictionary]) { [string]$_['Name'] } else { [string]$_ } })
    $lz = & $wrap "$landing$(if ($groups.Count) { "  ·  $($groups -join ' > ')" })" 'landingzone' $top.ToArray()

    $placed = @{}
    $nodeData = {
        param([hashtable] $Node)
        $f = @($Finding | Where-Object NodeId -EQ $Node.Id)
        [ordered]@{
            tooltip           = "$($Node.Name)$(if ($Node.Sku) { " ($($Node.Sku))" })`n$($Node.Service)$(if ($f.Count) { "`n" + ((@($f | ForEach-Object { "$($_.Status) $($_.Severity): $($_.Finding)" })) -join "`n") })"
            aacComponent      = $Node.Id
            aacService        = $Node.Service
            aacSku            = $Node.Sku
            aacRegion         = $Node.Region
            aacZone           = $Node.Zone
            aacZoneRedundant  = $(if (& $isInfra $Node) { '' } else { [string][bool]$Node.ZoneRedundant })
            aacPrivateEndpoint = $(if (& $isInfra $Node) { '' } else { [string][bool]$Node.PrivateEndpoint })
            aacPublicAccess   = $(if (& $isInfra $Node) { '' } else { [string][bool]$Node.PublicAccess })
            aacIdentity       = $Node.Identity
            aacPattern        = $(if ($Node.Contains('Pattern')) { [string]$Node.Pattern } else { '' })
            aacOpenFindings   = [string]@($f | Where-Object Status -EQ 'Open').Count
        }
    }
    $emitNode = {
        param([hashtable] $Node, [string] $Parent, [double] $X, [double] $Y, [double] $AbsX, [double] $AbsY)
        $cid = "n-$($Node.Id)"
        $placed[$Node.Id] = $cid
        $state = & $toneOf $Node
        $sub = @(if ($Node.Sku) { $Node.Sku }; if (-not (& $isInfra $Node) -and $Node.ZoneRedundant) { 'zone redundant' }; if ($Node.PrivateEndpoint) { 'private endpoint' })
        $label = "<b>$(& $html $Node.Name)</b>$(if ($sub.Count) { "<br><span style='font-size:10px;color:#5B6B80'>$(& $html ($sub -join ' · '))</span>" })"
        & $vertex $arch $label (& $iconStyle (& $iconKey $Node)) $X $Y $iconSize $iconSize $Parent $cid (& $nodeData $Node)
        # The dot is a child of the icon, so it moves with it.
        if ($state -ne 'neutral') { & $vertex $arch '' "ellipse;html=1;fillColor=$($tone[$state]);strokeColor=#FFFFFF;strokeWidth=2;" ($iconSize - 6) -6 14 14 $cid }
        if (& $isInfra $Node) { return }
        $f = @($open | Where-Object NodeId -EQ $Node.Id)
        if (& $want 'Waf') {
            $badges = @(foreach ($p in $Catalog.Pillars) {
                    $pf = @($f | Where-Object Pillar -EQ $p)
                    if ($pf.Count) {
                        $high = @($pf | Where-Object Severity -In 'Blocking', 'High').Count
                        "<span style='color:$(if ($high) { $tone.bad } else { '#B06000' })'>$($short[$p])$(if ($high) { '!!' } else { '!' })</span>"
                    }
                })
            $value = if ($badges.Count) { "<b>WAF</b> $($badges -join ' ')" } else { "<b>WAF</b> <span style='color:$($tone.ok)'>ok</span>" }
            & $vertex $arch $value "$text;align=center;fontSize=10;fontColor=#3C4043;" ($AbsX - 50) ($AbsY + 92) 148 16 $layerId.Waf
        }
        $policies = @(& $policiesOf $Node)
        if ((& $want 'Policy') -and $policies.Count) {
            & $vertex $arch "Policy $($policies.Count)" 'rounded=1;arcSize=40;html=1;fillColor=#E8F0FE;strokeColor=#1A73E8;fontColor=#1A73E8;fontSize=9;fontStyle=1;' ($AbsX - 50) ($AbsY + 4) 44 18 $layerId.Policy '' ([ordered]@{ tooltip = ($policies -join "`n"); link = (& $pageLink 'policy') })
        }
    }
    $emitBox = $null
    $emitBox = {
        param([hashtable] $Box, [string] $Parent, [double] $X, [double] $Y, [double] $AbsX, [double] $AbsY)
        $data = $null
        if ($Box.NodeId) {
            $cid = "n-$($Box.NodeId)"
            $placed[$Box.NodeId] = $cid
            $node = $Design.Nodes | Where-Object Id -EQ $Box.NodeId | Select-Object -First 1
            if ($node) { $data = & $nodeData $node }
        }
        else { $arch.N++; $cid = "architecture-b$($arch.N)" }
        & $vertex $arch (& $html $Box.Title) $boxStyle[$Box.Kind] $X $Y $Box.W $Box.H $Parent $cid $data
        if ($Box.NodeId -and $node) {
            # A virtual network's icon sits in its title bar.
            & $vertex $arch '' "image;html=1;aspect=fixed;image=$(& $iconUri (& $iconKey $node));" ($Box.W - 34) 6 24 24 $cid
        }
        if ($Box.Guard -and (& $want 'Guardrail')) { & $vertex $arch 'guardrail zone' $guardStyle ($AbsX - 6) ($AbsY - 6) ($Box.W + 12) ($Box.H + 12) $layerId.Guardrail }
        $cx = $pad
        foreach ($child in $Box.Children) {
            & $emitBox $child $cid $cx $head ($AbsX + $cx) ($AbsY + $head)
            $cx += $child.W + $gap
        }
        $i = 0
        foreach ($n in $Box.Nodes) {
            $rx = $pad + ($i % $Box.PerRow) * $slotW + ($slotW - $iconSize) / 2
            $ry = $head + 14 + [Math]::Floor($i / $Box.PerRow) * $slotH
            & $emitNode $n $cid $rx $ry ($AbsX + $rx) ($AbsY + $ry)
            $i++
        }
        if ($Box.Extra -and (& $want 'Recommendations')) {
            $rx = $AbsX + $pad + ($i % $Box.PerRow) * $slotW + ($slotW - $iconSize) / 2
            $ry = $AbsY + $head + 14 + [Math]::Floor($i / $Box.PerRow) * $slotH
            & $vertex $arch '<b>Azure Advisor and Defender for Cloud</b><br><span style=''font-size:10px;color:#5B6B80''>recommendations to the backlog</span>' (& $iconStyle 'alert') $rx $ry $iconSize $iconSize $layerId.Recommendations 'n-recommendations'
            $placed['recommendations'] = 'n-recommendations'
        }
    }

    $lzX, $lzY = 40, 110
    & $vertex $arch "<b>$(& $html $Design.Name)</b> - architecture" "$text;fontSize=22;fontColor=#1B2A41;" $lzX 20 1200 36
    & $vertex $arch (& $html "Regions: $($regions -join ', ')  ·  $landing  ·  patterns: $(if (@($Design.Patterns).Count) { (@($Design.Patterns | ForEach-Object { & $patternName $_ })) -join ', ' } else { 'none' })  ·  catalog $($Design.CatalogVersion)  ·  $today") "$text;fontSize=12;fontColor=#5B6B80;" $lzX 58 1600 22
    & $emitBox $lz '' $lzX $lzY $lzX $lzY
    & $vertex $arch 'Every component sends its logs and metrics to the Log Analytics workspace (not drawn, to keep the lines readable). Policy details: see the Policy and compliance page.' "$text;fontSize=11;fontColor=#5B6B80;" $lzX ($lzY + $lz.H + 8) ($lz.W) 20

    # The delivery pipeline, under the landing zone.
    $pipeNodes = @(& $nodesIn 'Pipeline' '*')
    $pipeY = $lzY + $lz.H + 48
    $pipeH = 0
    if ($pipeNodes.Count) {
        $pipeW = $pipeNodes.Count * ($slotW + 20) + 2 * $pad
        $pipeH = $head + 130
        & $vertex $arch (& $html "Delivery pipeline - $(& $answer 'OPS-01')") $boxStyle.pipeline $lzX $pipeY $pipeW $pipeH '' 'architecture-pipeline'
        $px = $pad
        foreach ($n in $pipeNodes) {
            $shape = if ($n.Kind -eq 'gate') { 'shape=hexagon;perimeter=hexagonPerimeter2;size=0.15;fillColor=#E8F0FE;strokeColor=#1A73E8;' } else { 'rounded=1;fillColor=#F1F3F4;strokeColor=#80868B;' }
            & $vertex $arch "<b>$(& $html $n.Name)</b>" "whiteSpace=wrap;html=1;fontSize=11;$shape" $px ($head + 20) $slotW 56 'architecture-pipeline' "n-$($n.Id)" (& $nodeData $n)
            $placed[$n.Id] = "n-$($n.Id)"
            if ($n.Kind -eq 'gate' -and (& $want 'PSRule')) {
                & $vertex $arch (& $html "PSRule for Azure: baseline $PSRuleBaseline, $(@($Catalog.Rules | Where-Object { $_.PSRule } | ForEach-Object PSRule | Select-Object -Unique).Count) rules mapped to the design") "$text;align=center;fontSize=10;fontColor=#1A73E8;" ($lzX + $px - 10) ($pipeY + $head + 80) ($slotW + 20) 30 $layerId.PSRule
            }
            $px += $slotW + 20
        }
    }
    # The connections (not the diagnostics).
    foreach ($c in @($Design.Connections | Where-Object { $_.Label -ne 'diagnostics' })) {
        if (-not $placed.Contains($c.From) -or -not $placed.Contains($c.To)) { continue }
        $style = if ($lineStyle.Contains([string]$c.Kind)) { $lineStyle[[string]$c.Kind] } else { $lineStyle.data }
        & $connect $arch $c.Label $style $placed[$c.From] $placed[$c.To]
    }
    if ((& $want 'Recommendations') -and $placed.Contains('recommendations') -and $placed.Contains('repo')) {
        & $connect $arch 'to the backlog' $lineStyle.control 'n-recommendations' 'n-repo' $layerId.Recommendations
    }
    $archLayers = (@("        <mxCell id=`"architecture-1`" value=`"Architecture`" parent=`"0`" />") + @($layerId.Keys | Where-Object { & $want $_ } | ForEach-Object { "        <mxCell id=`"$($layerId[$_])`" value=`"$($layerName[$_])`" parent=`"0`" />" })) -join "`n"
    $archW = [Math]::Max(1169, $lz.W + 2 * $lzX)
    $archH = [Math]::Max(827, $pipeY + $pipeH + 60)

    # --- Policy and compliance ---------------------------------------------------------------------------------------
    $policy = & $newPage 'policy' 'Policy and compliance'
    $policyColumns = @(@{ Title = 'Component'; Width = 190 }, @{ Title = 'Rule'; Width = 100 }, @{ Title = 'Check'; Width = 300 }, @{ Title = 'Pillar'; Width = 150 }, @{ Title = 'Azure Policy'; Width = 320 }, @{ Title = 'PSRule for Azure'; Width = 200 }, @{ Title = 'Result'; Width = 110 })
    $policyW = [double](@($policyColumns | ForEach-Object { $_.Width }) | Measure-Object -Sum).Sum + 80
    & $banner $policy 'Policy and compliance' $policyW
    $y = 84
    & $heading $policy "Inherited Azure Policy - $landing" 40 $y
    $y += 30
    $assignments = @($Design['Policies'] | Where-Object { $_ })
    if ($assignments.Count) {
        $rows = @(foreach ($a in $assignments) {
                $enforced = [string]$a['Enforcement']
                , @([string]$a['Name'], [string]$a['Scope'], @{ Text = $enforced; Fill = $(if ($enforced -eq 'Enforced') { '#E6F4EA' } else { '#FEF7E0' }) }, ([string]$a['DefinitionId'] -replace '^.*/', ''))
            })
        $y = & $table $policy 40 $y @(@{ Title = 'Assignment'; Width = 520 }, @{ Title = 'Scope'; Width = 300 }, @{ Title = 'Enforcement'; Width = 140 }, @{ Title = 'Definition'; Width = 410 }) $rows
    }
    else {
        & $vertex $policy (& $html 'No landing zone was read, so no inherited assignments are shown. Name one (OPS-03) and run New-AACArchitectureDesign while signed in to draw them.') "$text;fontSize=11;fontColor=#5B6B80;" 40 $y 1200 20
        $y += 24
    }
    $allowed = @($Design['AllowedLocations'] | Where-Object { $_ })
    $y += 10
    & $vertex $policy (& $html "Allowed locations: $(if ($allowed.Count) { $allowed -join ', ' } else { 'not restricted by an inherited assignment' })  ·  design regions: $($regions -join ', ')") "$text;fontSize=11;fontColor=#1B2A41;" 40 $y 1300 20
    $y += 44
    & $heading $policy 'Design rules by component - Azure Policy and PSRule for Azure' 40 $y 1300
    $y += 30
    $resultOf = {
        param([string] $Rule, [string] $NodeId)
        $f = $Finding | Where-Object { $_.Rule -eq $Rule -and $_.NodeId -eq $NodeId } | Select-Object -First 1
        if (-not $f) { return @{ Text = 'Pass'; Fill = '#E6F4EA' } }
        if ($f.Status -eq 'Accepted') { return @{ Text = 'Accepted risk'; Fill = '#F1F3F4' } }
        @{ Text = "Open - $($f.Severity)"; Fill = $severityFill[[string]$f.Severity] }
    }
    $ruleRows = [System.Collections.Generic.List[object]]::new()
    foreach ($n in @($Design.Nodes | Where-Object { -not (& $isInfra $_) })) {
        foreach ($r in (& $rulesOf $n)) {
            $ruleRows.Add(@("$($n.Name)$(if ($regions.Count -gt 1 -and $n.Region -and $n.Zone -ne 'Edge') { " ($($n.Region))" })", @{ Text = $r.Id; Link = [string]$r.Link }, $r.Title, $r.Pillar, [string]$r.Policy, [string]$r.PSRule, (& $resultOf $r.Id $n.Id)))
        }
    }
    # Rules on the design as a whole.
    foreach ($f in @($Finding | Where-Object { -not $_.NodeId })) {
        $ruleRows.Add(@('Design', @{ Text = $f.Rule; Link = [string]$f.Link }, $f.Finding, $f.Pillar, [string]$f.Policy, [string]$f.PSRule, (& $resultOf $f.Rule '')))
    }
    if ($ruleRows.Count) { $y = & $table $policy 40 $y $policyColumns $ruleRows.ToArray() }
    else { & $vertex $policy 'No design rule applies to these components.' "$text;fontSize=11;fontColor=#5B6B80;" 40 $y 900 20; $y += 24 }
    $y += 16
    & $vertex $policy (& $html "Rule IDs link to the guidance. Pass means the design meets the rule as drawn; it is enforced at deployment by the Azure Policy definitions above and by the PSRule for Azure gate (baseline $PSRuleBaseline). Catalog $($Design.CatalogVersion).") "$text;fontSize=11;fontColor=#5B6B80;" 40 $y ($policyW - 80) 32
    $policyH = [Math]::Max(827, $y + 70)

    # --- Findings ------------------------------------------------------------------------------------------------------
    $findings = & $newPage 'findings' 'Findings'
    $findingColumns = @(@{ Title = 'Severity'; Width = 90 }, @{ Title = 'Status'; Width = 90 }, @{ Title = 'Rule'; Width = 100 }, @{ Title = 'Finding'; Width = 300 }, @{ Title = 'Component'; Width = 180 }, @{ Title = 'Pillar'; Width = 150 }, @{ Title = 'What to do'; Width = 460 })
    $findingW = [double](@($findingColumns | ForEach-Object { $_.Width }) | Measure-Object -Sum).Sum + 80
    & $banner $findings 'Findings' $findingW
    $y = 84
    & $heading $findings "Findings - $($open.Count) open, $(@($Finding | Where-Object Status -EQ 'Accepted').Count) accepted" 40 $y
    $y += 30
    if (@($Finding).Count) {
        $rows = @(foreach ($f in $Finding) {
                , @(@{ Text = $f.Severity; Fill = $(if ($f.Status -eq 'Open') { $severityFill[[string]$f.Severity] } else { '#F1F3F4' }) }, $f.Status, @{ Text = $f.Rule; Link = [string]$f.Link }, $f.Finding, $f.Component, $f.Pillar, $f.Remediation)
            })
        $y = & $table $findings 40 $y $findingColumns $rows
    }
    else { & $vertex $findings 'None: the design passes every rule.' "$text;fontSize=11;fontColor=#1E8E3E;" 40 $y 900 20; $y += 24 }
    $y += 24
    & $heading $findings 'Open decisions' 40 $y
    $y += 28
    $decisions = @(foreach ($id in @($Design['Open'] | Where-Object { $_ })) { $q = $Catalog.Questions | Where-Object Id -EQ $id | Select-Object -First 1; , @($id, $(if ($q) { $q.Text } else { '' }), (& $answer $id)) })
    if ($decisions.Count) { $y = & $table $findings 40 $y @(@{ Title = 'Question'; Width = 100 }, @{ Title = 'Decision'; Width = 700 }, @{ Title = 'Default used until decided'; Width = 300 }) $decisions }
    else { & $vertex $findings 'None.' "$text;fontSize=11;" 40 $y 400 20; $y += 24 }
    $y += 24
    & $heading $findings 'Assumptions (defaults no one answered)' 40 $y
    $y += 28
    $assumed = @(foreach ($q in @($Catalog.Questions | Where-Object { @($Design['Assumed']) -contains $_.Id })) { , @($q.Id, $q.Text, (& $answer $q.Id)) })
    if ($assumed.Count) { $y = & $table $findings 40 $y @(@{ Title = 'Question'; Width = 100 }, @{ Title = 'Assumption'; Width = 700 }, @{ Title = 'Value'; Width = 300 }) $assumed }
    else { & $vertex $findings 'None.' "$text;fontSize=11;" 40 $y 400 20; $y += 24 }
    $findingH = [Math]::Max(827, $y + 60)

    # --- Legend (after the architecture, so it lists only the icons used) ----------------------------------------------
    $legend = & $newPage 'legend' 'Legend'
    & $banner $legend 'Legend' 1169
    & $heading $legend 'Azure services in this design' 40 84
    $i = 0
    foreach ($key in @($usedIcons.Keys)) {
        $lx = 40 + ($i % 6) * 180
        $ly = 124 + [Math]::Floor($i / 6) * 96
        & $vertex $legend (& $html $usedIcons[$key]) (& $iconStyle $key 168) ($lx + 60) $ly 40 40
        $i++
    }
    $y = 124 + [Math]::Ceiling([Math]::Max(1, $i) / 6) * 96 + 10
    & $heading $legend 'Component status (the dot on each icon)' 40 $y 500
    & $heading $legend 'Connections' 620 $y 500
    $sy = $y + 34
    foreach ($k in $toneName.Keys) {
        & $vertex $legend '' "ellipse;html=1;fillColor=$($tone[$k]);strokeColor=#FFFFFF;strokeWidth=2;" 44 $sy 14 14
        & $vertex $legend (& $html $toneName[$k]) "$text;fontSize=11;verticalAlign=middle;" 68 ($sy - 4) 460 22
        $sy += 28
    }
    $ly = $y + 40
    foreach ($k in $lineStyle.Keys) {
        & $line $legend $lineStyle[$k] 624 $ly 724 $ly
        & $vertex $legend (& $html $lineName[$k]) "$text;fontSize=11;verticalAlign=middle;" 740 ($ly - 11) 380 22
        $ly += 28
    }
    $y = [Math]::Max($sy, $ly) + 20
    & $heading $legend 'Boxes' 40 $y 500
    & $heading $legend 'Layers (View > Layers on the Architecture page)' 620 $y 520
    $by = $y + 34
    foreach ($k in $boxName.Keys) {
        & $vertex $legend '' ($boxStyle[$k] + 'startSize=10;') 44 $by 60 24
        & $vertex $legend (& $html $boxName[$k]) "$text;fontSize=11;verticalAlign=middle;" 116 $by 420 24
        $by += 32
    }
    & $vertex $legend 'guardrail zone' $guardStyle 44 $by 60 24
    & $vertex $legend 'Guardrail zone (Guardrails layer)' "$text;fontSize=11;verticalAlign=middle;" 116 $by 420 24
    $by += 32
    $ly = $y + 34
    foreach ($k in $layerHelp.Keys) {
        $name = if ($layerName.Contains($k)) { $layerName[$k] } else { $k }
        & $vertex $legend "<b>$(& $html $name)</b> - $(& $html $layerHelp[$k])" "$text;fontSize=11;" 624 $ly 520 40
        $ly += 44
    }
    $legendH = [Math]::Max(827, [Math]::Max($by, $ly) + 60)

    # --- Cover -----------------------------------------------------------------------------------------------------------
    $cover = & $newPage 'cover' 'Cover'
    & $vertex $cover '' 'rounded=0;fillColor=#0B3B66;strokeColor=none;' 0 0 1169 190
    & $vertex $cover '' "image;html=1;aspect=fixed;image=$(& $iconUri 'subscription');" 48 58 72 72
    & $vertex $cover "<b>$(& $html $Design.Name)</b>" "$text;fontSize=32;fontColor=#FFFFFF;verticalAlign=middle;" 140 44 980 56
    & $vertex $cover (& $html "Azure architecture design  ·  $today") "$text;fontSize=16;fontColor=#C7D7EA;" 142 104 980 28
    $sla = & $answer 'REL-03'
    $facts = @(
        , @('Workload', "$(& $answer 'BUS-01') ($(& $answer 'BUS-02'))")
        , @('Data classification', (& $answer 'SEC-01'))
        , @('Availability', "$(if ($sla) { "$sla% SLA" }), RTO $(& $answer 'REL-01') min, RPO $(& $answer 'REL-02') min")
        , @('Exposure', (& $answer 'SEC-03'))
        , @('Regions', ($regions -join ', '))
        , @('Landing zone', $(if ($Design.LandingZone) { $Design.LandingZone } else { 'none' }))
        , @('Patterns', $(if (@($Design.Patterns).Count) { (@($Design.Patterns | ForEach-Object { & $patternName $_ })) -join ', ' } else { 'none' }))
        , @('Components', [string]@($Design.Nodes).Count)
        , @('Catalog', [string]$Design.CatalogVersion)
        , @('Delivery', "$(& $answer 'OPS-01'), PSRule baseline $PSRuleBaseline")
    )
    & $heading $cover 'Design' 48 220 560
    $null = & $table $cover 48 250 @(@{ Title = 'Item'; Width = 170 }, @{ Title = 'Value'; Width = 410 }) $facts
    & $heading $cover 'Open findings' 680 220 440
    $tx = 680
    foreach ($s in 'Blocking', 'High', 'Medium', 'Low') {
        $count = @($open | Where-Object Severity -EQ $s).Count
        $fill = if (-not $count) { '#E6F4EA' } elseif ($s -in 'Blocking', 'High') { '#FCE8E6' } else { '#FEF7E0' }
        & $vertex $cover "<span style='font-size:26px'><b>$count</b></span><br>$s" "rounded=1;arcSize=8;html=1;whiteSpace=wrap;fillColor=$fill;strokeColor=none;fontSize=12;fontColor=#1B2A41;" $tx 252 102 72 '' '' @{ link = (& $pageLink 'findings') }
        $tx += 110
    }
    & $heading $cover 'Well-Architected pillars' 680 344 440
    $py = 374
    foreach ($p in @($Pillar)) {
        $score = if ($null -ne $p.Score) { [int]$p.Score } else { $null }
        $color = if ($null -eq $score) { $tone.neutral } elseif ($score -ge 90) { $tone.ok } elseif ($score -ge 70) { $tone.warn } else { $tone.bad }
        & $vertex $cover (& $html $p.Pillar) "$text;fontSize=11;verticalAlign=middle;" 680 $py 190 22
        & $vertex $cover '' 'rounded=1;arcSize=50;fillColor=#E8EAED;strokeColor=none;' 872 ($py + 6) 200 10
        if ($score) { & $vertex $cover '' "rounded=1;arcSize=50;fillColor=$color;strokeColor=none;" 872 ($py + 6) (2 * $score) 10 }
        & $vertex $cover $(if ($null -eq $score) { 'n/a' } else { "$score%" }) "$text;fontSize=11;fontStyle=1;verticalAlign=middle;" 1080 $py 60 22
        $py += 28
    }
    & $heading $cover 'Contents' 680 ([Math]::Max($py + 12, 540)) 440
    $cy = [Math]::Max($py + 12, 540) + 30
    foreach ($entry in @(@('architecture', 'Architecture - components, regions and layers'), @('policy', 'Policy and compliance - inherited policy and design rules'), @('findings', 'Findings, open decisions and assumptions'), @('legend', 'Legend - icons, colours, lines and layers'))) {
        & $vertex $cover "<u>$(& $html $entry[1])</u>" "$text;fontSize=12;fontColor=#1A73E8;" 680 $cy 440 20 '' '' @{ link = (& $pageLink $entry[0]) }
        $cy += 24
    }
    & $vertex $cover (& $html 'Generated offline by Azure.Admin.Console from the design brief. Validate with Test-AACArchitectureDesign before deployment; PSRule for Azure and Azure Policy enforce it in the pipeline and the landing zone.') "$text;fontSize=10;fontColor=#80868B;" 48 772 1070 32

    # --- The file --------------------------------------------------------------------------------------------------------
    @"
<mxfile host="Azure.Admin.Console" type="device" pages="5">
$(& $pageXml $cover 1169 827)
$(& $pageXml $arch $archW $archH $archLayers)
$(& $pageXml $policy $policyW $policyH)
$(& $pageXml $findings $findingW $findingH)
$(& $pageXml $legend 1169 $legendH)
</mxfile>
"@
}
