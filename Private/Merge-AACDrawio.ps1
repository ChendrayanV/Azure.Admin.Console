function Merge-AACDrawio {
    <#
    .SYNOPSIS
        Refreshes a draw.io diagram you have edited with a newly generated one
        (ConvertTo-AACDrawio), keeping your changes.
    .DESCRIPTION
        Shapes are matched by ID (ConvertTo-AACDrawio derives them from the
        resource IDs), page by page (by page ID, else by name):
          kept     a resource in both: where you put it, the box you moved
                   it into, your styling - and your label if you changed it
                   (the label it was generated with is kept in aacLabel, to
                   tell); its data (type, location, tooltip, portal link) is
                   refreshed
          added    a resource new in Azure: placed in its box under what is
                   there (the box grows to fit), or beside the page's drawing,
                   and marked new (green) until the next refresh
          removed  a resource no longer in Azure: faded and red, with a
                   tooltip saying when it went - or, with -Prune, deleted
          yours    shapes, notes and connections you added (IDs not starting
                   aac-) are left as they are
        Connections are matched the same way: kept with your waypoints and
        style, added, or faded (deleted with -Prune, or when an end is gone).
        Pages only in the old file stay; pages only in the new one are added;
        the Legend page is replaced. A page draw.io saved compressed is read
        and written back uncompressed (draw.io reads both).
        Returns @{ Xml; Kept; Added; Removed; Pruned; Pages }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        # The diagram as it is now (the file's text).
        [Parameter(Mandatory)]
        [string] $Existing,

        # ConvertTo-AACDrawio's newly generated Xml.
        [Parameter(Mandatory)]
        [string] $Generated,

        [switch] $Prune,

        [datetime] $Now = [datetime]::UtcNow
    )

    $newMark = 'aacNew=1;fontColor=#008A6E;'
    $newBoxMark = 'aacNew=1;strokeColor=#008A6E;strokeWidth=2;'
    $removedMark = 'aacRemoved=1;opacity=35;fontColor=#D13447;'
    $removedEdgeMark = 'aacRemoved=1;opacity=35;dashed=1;'
    $pad, $gap, $header = 18, 24, 34

    try { $old = [xml]$Existing } catch { throw "Azure Admin Console can't read the diagram to update - it isn't draw.io XML ($($_.Exception.Message)). Save it from draw.io as .drawio (uncompressed or compressed), or write a new one without -Update." }
    $new = [xml]$Generated
    if ($old.DocumentElement.LocalName -ne 'mxfile') { throw "Azure Admin Console can't update that file: it isn't a draw.io diagram (no <mxfile>). Write a new one without -Update." }

    # A page's model: its <mxGraphModel>, inflating a compressed page (base64, raw deflate, URL-encoded) first.
    $modelOf = {
        param([System.Xml.XmlElement] $Diagram)
        $model = $Diagram.SelectSingleNode('mxGraphModel')
        if ($model) { return $model }
        $text = $Diagram.InnerText.Trim()
        if (-not $text) { return $null }
        $bytes = [Convert]::FromBase64String($text)
        $deflate = [System.IO.Compression.DeflateStream]::new([System.IO.MemoryStream]::new($bytes), [System.IO.Compression.CompressionMode]::Decompress)
        $reader = [System.IO.StreamReader]::new($deflate, [Text.Encoding]::UTF8)
        $inner = [Uri]::UnescapeDataString($reader.ReadToEnd())
        $reader.Dispose()
        $part = [xml]$inner
        $imported = $Diagram.OwnerDocument.ImportNode($part.DocumentElement, $true)
        $Diagram.InnerText = ''
        [void]$Diagram.AppendChild($imported)
        $imported
    }
    # The cells on a page by ID: the element under <root> (an <mxCell>, or an <object> / <UserObject> holding one).
    $cellsOf = {
        param($Root)
        $map = [ordered]@{}
        foreach ($el in @($Root.ChildNodes | Where-Object { $_ -is [System.Xml.XmlElement] })) { $id = $el.GetAttribute('id'); if ($id) { $map[$id] = $el } }
        $map
    }
    $mxOf = { param([System.Xml.XmlElement] $El) if ($El.LocalName -eq 'mxCell') { $El } else { $El.SelectSingleNode('mxCell') } }
    $geoOf = { param([System.Xml.XmlElement] $El) $mx = & $mxOf $El; if ($mx) { $mx.SelectSingleNode('mxGeometry') } }
    $num = { param($Geo, [string] $Name) if ($Geo -and $Geo.GetAttribute($Name)) { [double]$Geo.GetAttribute($Name) } else { 0.0 } }
    $styleAdd = { param([System.Xml.XmlElement] $Mx, [string] $Mark) $s = $Mx.GetAttribute('style'); if (-not $s.Contains($Mark)) { $Mx.SetAttribute('style', ($s.TrimEnd(';') + ';' + $Mark)) } }
    $styleDrop = { param([System.Xml.XmlElement] $Mx, [string] $Mark) $s = $Mx.GetAttribute('style'); if ($s.Contains($Mark)) { $Mx.SetAttribute('style', $s.Replace(';' + $Mark, ';').Replace($Mark, '').Replace(';;', ';')) } }
    $isOurs = { param([string] $Id) $Id -like 'aac-*' -and $Id -notlike 'aac-legend-*' }
    $isEdge = { param([System.Xml.XmlElement] $El) $mx = & $mxOf $El; $mx -and $mx.GetAttribute('edge') -eq '1' }
    $isBox = { param([System.Xml.XmlElement] $El) $mx = & $mxOf $El; $mx -and $mx.GetAttribute('style') -like 'swimlane*' }

    $kept = 0; $added = 0; $removed = 0; $pruned = 0
    $pageNames = [System.Collections.Generic.List[string]]::new()
    $oldDiagrams = @($old.DocumentElement.SelectNodes('diagram'))
    foreach ($nd in @($new.DocumentElement.SelectNodes('diagram'))) {
        $name = $nd.GetAttribute('name'); $pageId = $nd.GetAttribute('id')
        $pageNames.Add($name)
        $od = @($oldDiagrams | Where-Object { $_.GetAttribute('id') -eq $pageId })[0]
        if (-not $od) { $od = @($oldDiagrams | Where-Object { $_.GetAttribute('name') -eq $name })[0] }
        if (-not $od -or $pageId -eq 'aac-page-legend') {
            # A new page, or the legend: as generated.
            $imported = $old.ImportNode($nd, $true)
            if ($od) { [void]$old.DocumentElement.ReplaceChild($imported, $od) } else { [void]$old.DocumentElement.AppendChild($imported); $added += @($nd.SelectNodes('.//object')).Count }
            continue
        }
        $oldModel = & $modelOf $od
        $newModel = & $modelOf $nd
        $oldRoot = $oldModel.SelectSingleNode('root'); $newRoot = $newModel.SelectSingleNode('root')
        $oldCells = & $cellsOf $oldRoot; $newCells = & $cellsOf $newRoot
        # Where new things go in a box: under its children, in rows.
        $cursor = @{}
        $childrenOf = { param([string] $Parent) @($oldRoot.ChildNodes | Where-Object { $_ -is [System.Xml.XmlElement] -and (& $mxOf $_) -and (& $mxOf $_).GetAttribute('parent') -eq $Parent -and -not (& $isEdge $_) }) }
        $grow = $null
        $grow = {
            # A box grows to hold its children, and the box holding it to hold it.
            param([string] $Id)
            if (-not $oldCells.Contains($Id)) { return }
            $geo = & $geoOf $oldCells[$Id]
            if (-not $geo) { return }
            $right = 0.0; $bottom = 0.0
            foreach ($child in & $childrenOf $Id) { $g = & $geoOf $child; $right = [Math]::Max($right, (& $num $g 'x') + (& $num $g 'width')); $bottom = [Math]::Max($bottom, (& $num $g 'y') + (& $num $g 'height')) }
            $changed = $false
            if ($right + $pad -gt (& $num $geo 'width')) { $geo.SetAttribute('width', [string]($right + $pad)); $changed = $true }
            if ($bottom + $pad -gt (& $num $geo 'height')) { $geo.SetAttribute('height', [string]($bottom + $pad)); $changed = $true }
            if ($changed) { $parent = (& $mxOf $oldCells[$Id]).GetAttribute('parent'); if ($parent -and $parent -ne '1') { & $grow $parent } }
        }

        foreach ($id in @($newCells.Keys)) {
            if (-not (& $isOurs $id)) { continue }
            $gen = $newCells[$id]
            if (& $isEdge $gen) {
                $genMx = & $mxOf $gen
                if ($oldCells.Contains($id)) {
                    $mx = & $mxOf $oldCells[$id]
                    & $styleDrop $mx $removedEdgeMark
                    $mx.SetAttribute('value', $genMx.GetAttribute('value'))
                    $kept++
                }
                else { [void]$oldRoot.AppendChild($old.ImportNode($gen, $true)); $oldCells[$id] = $oldRoot.LastChild }
                continue
            }
            if ($oldCells.Contains($id)) {
                # Kept: the user's geometry, box and style; Azure's data; the user's label if they changed it.
                $el = $oldCells[$id]
                $mx = & $mxOf $el
                & $styleDrop $mx $newMark; & $styleDrop $mx $newBoxMark; & $styleDrop $mx $removedMark
                if ($el.LocalName -eq 'object' -and $gen.LocalName -eq 'object') {
                    $edited = $el.GetAttribute('aacLabel') -and $el.GetAttribute('label') -ne $el.GetAttribute('aacLabel')
                    foreach ($attr in @($gen.Attributes)) {
                        if ($attr.Name -in 'id') { continue }
                        if ($attr.Name -eq 'label' -and $edited) { continue }
                        $el.SetAttribute($attr.Name, $attr.Value)
                    }
                    $el.RemoveAttribute('aacStatus')
                }
                # Its box was deleted (pruned, or by the user): back in the box Azure says.
                $parent = $mx.GetAttribute('parent')
                if ($parent -ne '1' -and -not $oldCells.Contains($parent)) { $mx.SetAttribute('parent', (& $mxOf $gen).GetAttribute('parent')) }
                $kept++
                continue
            }
            # Added: under what is in its box, or beside the drawing.
            $el = $old.ImportNode($gen, $true)
            $mx = & $mxOf $el
            $geo = & $geoOf $el
            $parent = $mx.GetAttribute('parent')
            $parentIsNew = $parent -ne '1' -and $newCells.Contains($parent) -and -not $oldCells.Contains($parent)
            if (-not $parentIsNew) {
                $w = & $num $geo 'width'; $h = & $num $geo 'height'
                if (-not $cursor.Contains($parent)) {
                    $bottom = if ($parent -eq '1') { 40.0 } else { $header + $pad - $gap }
                    $right = 40.0
                    foreach ($child in & $childrenOf $parent) { $g = & $geoOf $child; $bottom = [Math]::Max($bottom, (& $num $g 'y') + (& $num $g 'height')); $right = [Math]::Max($right, (& $num $g 'x') + (& $num $g 'width')) }
                    $cursor[$parent] = if ($parent -eq '1') { @{ x = $right + 80; y = 40.0; rowH = 0.0; left = $right + 80; limit = $right + 2400 } }
                    else { $pgeo = & $geoOf $oldCells[$parent]; @{ x = [double]$pad; y = $bottom + $gap; rowH = 0.0; left = [double]$pad; limit = [Math]::Max(400, (& $num $pgeo 'width') - $pad) } }
                }
                $c = $cursor[$parent]
                if ($c.x -gt $c.left -and $c.x + $w -gt $c.limit) { $c.x = $c.left; $c.y += $c.rowH + $gap; $c.rowH = 0 }
                # An icon's label hangs below it: leave room.
                $geo.SetAttribute('x', [string]$c.x); $geo.SetAttribute('y', [string]$c.y)
                $c.x += [Math]::Max($w, 140) + $gap; $c.rowH = [Math]::Max($c.rowH, $(if (& $isBox $el) { $h } else { $h + 52 }))
            }
            & $styleAdd $mx $(if (& $isBox $el) { $newBoxMark } else { $newMark })
            if ($el.LocalName -eq 'object') { $el.SetAttribute('aacStatus', "new $($Now.ToString('yyyy-MM-dd'))") }
            [void]$oldRoot.AppendChild($el)
            $oldCells[$id] = $el
            if (-not $parentIsNew -and $parent -ne '1') { & $grow $parent }
            $added++
        }

        # Removed from Azure: faded (or deleted with -Prune); their connections too.
        $gone = @($oldCells.Keys | Where-Object { (& $isOurs $_) -and -not $newCells.Contains($_) })
        $goneShapes = @($gone | Where-Object { -not (& $isEdge $oldCells[$_]) })
        $goneSet = [System.Collections.Generic.HashSet[string]]@($goneShapes)
        foreach ($id in $goneShapes) {
            $el = $oldCells[$id]
            if ($Prune) {
                # Its children that stay in Azure move to where Azure has them; the rest go with it.
                foreach ($child in & $childrenOf $id) { $cid = $child.GetAttribute('id'); if (-not $goneSet.Contains($cid) -and $newCells.Contains($cid)) { (& $mxOf $child).SetAttribute('parent', (& $mxOf $newCells[$cid]).GetAttribute('parent')) } }
                [void]$oldRoot.RemoveChild($el); $pruned++
                continue
            }
            if ($el.LocalName -eq 'object' -and $el.GetAttribute('aacStatus') -notlike 'removed*') {
                & $styleDrop (& $mxOf $el) $newMark; & $styleDrop (& $mxOf $el) $newBoxMark
                & $styleAdd (& $mxOf $el) $removedMark
                $el.SetAttribute('aacStatus', "removed $($Now.ToString('yyyy-MM-dd'))")
                $el.SetAttribute('tooltip', "Not found in Azure on $($Now.ToString('yyyy-MM-dd')) - deleted or moved. $($el.GetAttribute('tooltip'))")
                $removed++
            }
        }
        foreach ($id in @($gone | Where-Object { & $isEdge $oldCells[$_] })) {
            $el = $oldCells[$id]
            $mx = & $mxOf $el
            $endGone = -not $el.ParentNode -or @($mx.GetAttribute('source'), $mx.GetAttribute('target') | Where-Object { $_ -and -not ($oldRoot.SelectSingleNode("*[@id='$_']")) }).Count
            if ($Prune -or $endGone) { if ($el.ParentNode) { [void]$oldRoot.RemoveChild($el) } }
            else { & $styleAdd $mx $removedEdgeMark }
        }
    }

    $old.DocumentElement.SetAttribute('modified', $Now.ToString('o'))
    $writer = [System.IO.StringWriter]::new()
    $settings = [System.Xml.XmlWriterSettings]::new()
    $settings.Indent = $true
    $settings.OmitXmlDeclaration = $true
    $xw = [System.Xml.XmlWriter]::Create($writer, $settings)
    $old.Save($xw)
    $xw.Dispose()
    @{ Xml = $writer.ToString() + "`n"; Kept = $kept; Added = $added; Removed = $removed; Pruned = $pruned; Pages = $pageNames.ToArray() }
}
