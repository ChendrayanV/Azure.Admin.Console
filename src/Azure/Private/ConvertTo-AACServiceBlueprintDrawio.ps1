function ConvertTo-AACServiceBlueprintDrawio {
    <#
    .SYNOPSIS
        A blueprint as an editable draw.io file: the diagram, then a Legend
        page saying what each planned resource means for policy and PSRule, and
        the alerts and resiliency recommendations that go with it.
    .DESCRIPTION
        The diagram is ConvertTo-AACDrawio's. Its own legend isn't used: that
        one is about refreshing a diagram of real resources from Azure. Returns
        the same hashtable as ConvertTo-AACDrawio, with the Legend in its Xml.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Map,

        [Parameter(Mandatory)]
        $Icons,

        [Parameter(Mandatory)]
        [string] $Title,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Component,

        [string[]] $Fact = @()
    )

    $drawn = ConvertTo-AACDrawio -Map $Map -Icons $Icons -Title $Title
    $esc = { param([string] $Text) [System.Security.SecurityElement]::Escape($Text) }
    $cells = [System.Text.StringBuilder]::new()
    # A hashtable: a counter's ++ inside the script block would only change its own copy.
    $counter = @{ N = 0 }
    $cell = {
        param([string] $Value, [string] $Style, [double] $X, [double] $Y, [double] $W, [double] $H)
        $counter.N++
        [void]$cells.AppendLine("        <mxCell id=`"aac-blueprint-$($counter.N)`" value=`"$(& $esc $Value)`" style=`"$Style`" vertex=`"1`" parent=`"1`"><mxGeometry x=`"$X`" y=`"$Y`" width=`"$W`" height=`"$H`" as=`"geometry`"/></mxCell>")
    }
    $text = 'text;html=1;align=left;verticalAlign=top;whiteSpace=wrap;'
    $head = 'rounded=0;html=1;whiteSpace=wrap;align=left;spacingLeft=6;fillColor=#0B3B66;strokeColor=#FFFFFF;fontColor=#FFFFFF;fontSize=11;fontStyle=1;'
    $body = 'rounded=0;html=1;whiteSpace=wrap;align=left;spacingLeft=6;fillColor=#FFFFFF;strokeColor=#D0D7E2;fontColor=#1B2A41;fontSize=11;'
    $fills = @{ Blocked = '#FCE8E6'; 'Needs attention' = '#FEF7E0'; Ready = '#E6F4EA'; 'Not fully checked' = '#F1F3F4' }

    & $cell "<b style='font-size:20px'>$(& $esc $Title)</b>" $text 40 30 1000 36
    $y = 74
    if ($Fact.Count) {
        & $cell (($Fact | ForEach-Object { & $esc $_ }) -join '<br>') ($text + 'fontColor=#475569;fontSize=12;') 40 $y 1000 (18 * $Fact.Count + 8)
        $y += 18 * $Fact.Count + 20
    }
    $columns = @(@{ T = 'Planned resource'; W = 230 }, @{ T = 'Type'; W = 240 }, @{ T = 'SKU'; W = 100 }, @{ T = 'Status'; W = 120 }, @{ T = 'Azure Policy'; W = 190 }, @{ T = 'PSRule for Azure'; W = 130 }, @{ T = 'AMBA alerts'; W = 90 }, @{ T = 'APRL'; W = 100 })
    $x = 40
    foreach ($c in $columns) { & $cell $c.T $head $x $y $c.W 28; $x += $c.W }
    $y += 28
    foreach ($item in $Component) {
        $policy = if ($item.PolicyChecked) { "$($item.Blocks) block, $($item.Audits) audit" } else { "$($item.PoliciesAssigned) assigned, not checked" }
        $psrule = if ($item.PSRuleChecked) { "$($item.PSRuleFailed) fail, $($item.PSRulePassed) pass" } else { 'Not checked' }
        $values = @($item.Name, $item.ResourceType, $item.Sku, $item.Status, $policy, $psrule, [string]$item.BaselineAlerts, "$($item.ResiliencyTotal) ($($item.ResiliencyHigh) high)")
        $x = 40
        for ($i = 0; $i -lt $columns.Count; $i++) {
            $style = if ($i -eq 3) { $body + "fillColor=$($fills[$item.Status]);fontStyle=1;" } else { $body }
            & $cell (& $esc $values[$i]) $style $x $y $columns[$i].W 28
            $x += $columns[$i].W
        }
        $y += 28
    }
    $y += 20
    $notes = @(
        '<b>Planned, not deployed.</b> Nothing here exists in Azure yet; this is what the blueprint would ask for and what policy and PSRule say about it.'
        '<b>Blocked</b>: Azure would refuse it (a Deny, a guardrail or an invalid name). <b>Needs attention</b>: a high or medium finding. <b>Not fully checked</b>: a policy verdict or PSRule is missing, so it can''t be called ready. <b>Ready</b>: checked, with only low findings.'
        '<b>AMBA alerts</b> and <b>APRL</b> recommendations are suggestions for each type from Azure Monitor Baseline Alerts and the Azure Proactive Resiliency Library. They aren''t checks of this plan and don''t change a status: review them, and add the alerts you want.'
        '<b>Connections</b>: only facts are drawn - a Function App runs on its plan and keeps its runtime state in storage. Add how your services talk to each other, and the private endpoints the private configuration needs.'
    )
    & $cell ($notes -join '<br><br>') ($text + 'fontSize=12;fontColor=#1B2A41;') 40 $y 1200 170

    $page = @"
  <diagram id="aac-page-blueprint-legend" name="Legend">
    <mxGraphModel grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="0" pageScale="1" math="0" shadow="0">
      <root>
        <mxCell id="0"/>
        <mxCell id="1" parent="0"/>
$($cells.ToString().TrimEnd())
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
"@
    $drawn.Xml = $drawn.Xml.Replace('</mxfile>', $page)
    $drawn
}
