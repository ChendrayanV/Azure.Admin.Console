function ConvertTo-AACArchitectureMermaid {
    <#
    .SYNOPSIS
        Draws a design as a Mermaid flowchart, with the compliance layers on
        it: WAF, Azure Policy, guardrails, PSRule and Azure Recommendations.
    .DESCRIPTION
        Boxes: the edge (global entry), the landing zone (or subscription)
        holding the hub, a spoke per region with its data tier and its
        integration tier, operations; the pipeline below. The layers
        (-Layer, all by default):
          Waf              each component's open findings by pillar (R S C O
                           P with !! for blocking or high, ! otherwise), and
                           its colour by the worst; WAF ok when none
          Policy           the inherited assignments on the landing zone
                           box, and on each component the built-in policies
                           its rules refer to
          Guardrail        the spokes drawn dashed: the guardrail zone, with
                           the allowed regions
          PSRule           the gate in the pipeline, with its baseline and how
                           many PSRule for Azure rules the design maps to
          Recommendations  Azure Advisor and Defender for Cloud, feeding the
                           backlog (the repository)
        Diagnostics edges are left out (every component sends to the
        workspace - the operations box says so). Returns the Mermaid text.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Design,

        [AllowEmptyCollection()]
        [object[]] $Finding = @(),

        [hashtable] $Catalog = (Get-AACArchitectureCatalog),

        [ValidateSet('Waf', 'Policy', 'Guardrail', 'PSRule', 'Recommendations')]
        [string[]] $Layer = @('Waf', 'Policy', 'Guardrail', 'PSRule', 'Recommendations'),

        [string] $PSRuleBaseline = 'Azure.Default'
    )

    $id = { param([string] $Value) 'n_' + ($Value -replace '[^A-Za-z0-9]', '_') }
    $text = { param([string] $Value) ($Value -replace '"', '#quot;' -replace '[<>]', '') }
    $want = { param([string] $Name) $Layer -contains $Name }
    $short = @{ Reliability = 'R'; Security = 'S'; 'Cost Optimization' = 'C'; 'Operational Excellence' = 'O'; 'Performance Efficiency' = 'P' }
    $open = @($Finding | Where-Object { $_.Status -eq 'Open' })
    $worst = { param([string] $NodeId) $f = @($open | Where-Object NodeId -EQ $NodeId); if (@($f | Where-Object Severity -In 'Blocking', 'High').Count) { 'bad' } elseif ($f.Count) { 'warn' } else { 'ok' } }
    $policiesFor = { param($Node) @($Catalog.Rules | Where-Object { $_.Policy -and (@($_.Scope) -contains $Node.Kind -or @($_.Scope) -contains '*') } | ForEach-Object Policy | Select-Object -Unique) }
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('flowchart LR')
    $nodeLine = {
        param($Node, [string] $Indent)
        $label = [System.Collections.Generic.List[string]]::new()
        $label.Add("<b>$(& $text $Node.Name)</b>")
        if ($Node.Sku) { $label.Add((& $text $Node.Sku)) }
        if ($Node.PrivateEndpoint) { $label.Add('private endpoint') }
        $infra = $Node.Kind -in 'pipeline', 'gate', 'network', 'dns', 'budget', 'monitor'
        if ((& $want 'Waf') -and -not $infra) {
            $badges = @(foreach ($pillar in $Catalog.Pillars) {
                    $f = @($open | Where-Object { $_.NodeId -eq $Node.Id -and $_.Pillar -eq $pillar })
                    if ($f.Count) { "$($short[$pillar])$(if (@($f | Where-Object Severity -In 'Blocking', 'High').Count) { '!!' } else { '!' })" }
                })
            $label.Add($(if ($badges.Count) { "WAF $($badges -join ' ')" } else { 'WAF ok' }))
        }
        $policyCount = @(& $policiesFor $Node).Count
        if ((& $want 'Policy') -and $policyCount -and -not $infra) { $label.Add("policy: $policyCount") }
        $shape = switch ($Node.Kind) { { $_ -in 'database', 'cosmos', 'storage', 'cache' } { '[(', ')]' } { $_ -in 'queue', 'events' } { '[[', ']]' } 'gate' { '{{', '}}' } default { '[', ']' } }
        $lines.Add("$Indent$(& $id $Node.Id)$($shape[0])`"$($label -join '<br/>')`"$($shape[1]):::$(if ($Node.Kind -in 'pipeline', 'gate', 'network', 'dns', 'budget', 'monitor') { 'neutral' } else { & $worst $Node.Id })")
    }
    $nodesIn = { param([string[]] $Zone, [string] $Region) @($Design.Nodes | Where-Object { $_.Zone -in $Zone -and (-not $Region -or $_.Region -eq $Region) }) }

    # The edge: global entry points.
    $edge = @(& $nodesIn 'Edge' '')
    if ($edge.Count) {
        $lines.Add('  subgraph EDGE["Edge (global)"]')
        foreach ($n in $edge) { & $nodeLine $n '    ' }
        $lines.Add('  end')
    }
    # The landing zone or the subscription, with the hub, a spoke per region and operations.
    $boxLabel = if ($Design.LandingZone) {
        $policyText = if ((& $want 'Policy') -and @($Design.Policies).Count) { $names = @($Design.Policies | Where-Object { $_.Enforcement -ne 'Not enforced' } | ForEach-Object Name | Select-Object -Unique); "<br/>policy: $(& $text (($names | Select-Object -First 4) -join ' · '))$(if ($names.Count -gt 4) { " and $($names.Count - 4) more" })" } else { '' }
        "Landing zone: $(& $text $Design.LandingZone)$policyText"
    }
    else { 'Subscription' }
    $lines.Add("  subgraph LZ[`"$boxLabel`"]")
    $regionIndex = 0
    foreach ($region in @($Design.Regions)) {
        $regionIndex++
        $hub = @(& $nodesIn 'Hub' $region)
        if ($hub.Count) {
            $lines.Add("    subgraph HUB$regionIndex[`"Hub - $(& $text $region)`"]")
            foreach ($n in $hub) { & $nodeLine $n '      ' }
            $lines.Add('    end')
        }
        $allowedText = if ((& $want 'Guardrail') -and @($Design.AllowedLocations).Count) { "<br/>guardrail zone · allowed: $(& $text (@($Design.AllowedLocations) -join ', '))" } elseif (& $want 'Guardrail') { '<br/>guardrail zone' } else { '' }
        $lines.Add("    subgraph SPOKE$regionIndex[`"Spoke - $(& $text $Design.Name) - $(& $text $region)$allowedText`"]")
        foreach ($n in & $nodesIn 'Spoke' $region) { & $nodeLine $n '      ' }
        $integration = @(& $nodesIn 'Integration' $region)
        if ($integration.Count) {
            $lines.Add("      subgraph INT$regionIndex[`"Integration`"]")
            foreach ($n in $integration) { & $nodeLine $n '        ' }
            $lines.Add('      end')
        }
        $data = @(& $nodesIn 'Data' $region)
        if ($data.Count) {
            $lines.Add("      subgraph DATA$regionIndex[`"Data`"]")
            foreach ($n in $data) { & $nodeLine $n '        ' }
            $lines.Add('      end')
        }
        $lines.Add('    end')
    }
    $ops = @(& $nodesIn 'Operations' '')
    $lines.Add('    subgraph OPS["Operations - every component sends diagnostics here"]')
    foreach ($n in $ops) { & $nodeLine $n '      ' }
    if (& $want 'Recommendations') { $lines.Add('      n_recommendations["<b>Azure Advisor and Defender for Cloud</b><br/>recommendations"]:::neutral') }
    $lines.Add('    end')
    $lines.Add('  end')
    # The pipeline.
    $pipe = @(& $nodesIn 'Pipeline' '')
    if ($pipe.Count) {
        $lines.Add('  subgraph PIPE["Pipeline"]')
        foreach ($n in $pipe) {
            if ($n.Kind -eq 'gate' -and (& $want 'PSRule')) {
                $mapped = @($Catalog.Rules | Where-Object PSRule | ForEach-Object PSRule | Select-Object -Unique).Count
                $lines.Add("    $(& $id $n.Id){{`"<b>PSRule for Azure gate</b><br/>baseline $(& $text $PSRuleBaseline)<br/>$mapped design rules mapped`"}}:::neutral")
            }
            else { & $nodeLine $n '    ' }
        }
        $lines.Add('  end')
    }
    # The connections (not the diagnostics).
    foreach ($c in @($Design.Connections | Where-Object { $_.Label -ne 'diagnostics' })) {
        if (-not @($Design.Nodes | Where-Object Id -EQ $c.From).Count -or -not @($Design.Nodes | Where-Object Id -EQ $c.To).Count) { continue }
        $arrow = switch ($c.Kind) { 'private' { '==>' } 'control' { '-.->' } 'pipeline' { '==>' } default { '-->' } }
        # Quoted: a bare label with brackets, such as 'egress (route table)', is a Mermaid syntax error.
        $lines.Add("  $(& $id $c.From) $arrow|`"$(& $text $c.Label)`"| $(& $id $c.To)")
    }
    if ((& $want 'Recommendations') -and @($Design.Nodes | Where-Object Id -EQ 'repo').Count) { $lines.Add('  n_recommendations -.->|"to the backlog"| n_repo') }
    if (& $want 'Guardrail') { for ($i = 1; $i -le $regionIndex; $i++) { $lines.Add("  style SPOKE$i stroke-dasharray: 6 4,stroke:#7c3aed") } }
    $lines.Add('  classDef ok fill:#e6f4ea,stroke:#1e8e3e,color:#0b3d1a')
    $lines.Add('  classDef warn fill:#fef7e0,stroke:#f9ab00,color:#4a3500')
    $lines.Add('  classDef bad fill:#fce8e6,stroke:#d93025,color:#5c0f0a')
    $lines.Add('  classDef neutral fill:#f1f3f4,stroke:#80868b,color:#202124')
    $lines -join "`n"
}
