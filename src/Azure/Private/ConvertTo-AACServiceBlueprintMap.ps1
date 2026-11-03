function ConvertTo-AACServiceBlueprintMap {
    <#
    .SYNOPSIS
        A blueprint as a map model - a region holding its resource group and
        the planned resources - for ConvertTo-AACDrawio and the map page.
    .DESCRIPTION
        Only connections that are facts are drawn: a Function App runs on its
        plan, and keeps its runtime state in a storage account when the
        blueprint has one. How the services talk to each other is the design's
        to decide, so it is left for you to draw. IDs don't start with
        /subscriptions: nothing here exists yet, so nothing links to the portal.

        Returns @{ Clusters; Nodes; Edges }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Component,

        [AllowEmptyCollection()]
        [object[]] $Finding = @(),

        [Parameter(Mandatory)]
        [string] $Region,

        [Parameter(Mandatory)]
        [string] $ResourceGroupName
    )

    $regionId = "blueprint/region/$Region"
    $groupId = "blueprint/resourcegroup/$ResourceGroupName"
    $statusColor = @{ Blocked = '#D13447'; 'Needs attention' = '#B8730A'; Ready = '#008A6E'; 'Not fully checked' = '#5B6B80' }
    $nodes = @(foreach ($item in $Component) {
            $policyText = if (-not $item.PolicyChecked) { "$($item.PoliciesAssigned) assigned, verdict not checked" } else { "$($item.Blocks) block, $($item.Audits) audit" }
            $psruleText = if ($item.PSRuleChecked) { "$($item.PSRuleFailed) fail, $($item.PSRulePassed) pass" } else { 'not checked' }
            [ordered]@{
                id = "blueprint/$($item.Id)"; name = $item.Name; type = $item.ResourceType; icon = $item.Icon; parent = $groupId; typeLabel = $item.Label; location = $item.Region; resourceGroup = $ResourceGroupName
                caption = $item.Status; captionColor = $statusColor[$item.Status]; risk = @{ Blocked = 'high'; 'Needs attention' = 'medium' }[$item.Status]
                # The card shows one line of these, cut short: the status comes first.
                facts = @($item.Status, "Policy: $policyText", "PSRule: $psruleText", "AMBA: $($item.BaselineAlerts) alerts", "APRL: $($item.ResiliencyTotal) ($($item.ResiliencyHigh) high)", "SKU $($item.Sku)")
                findings = @($Finding | Where-Object { $_.ComponentId -eq $item.Id -and $_.Severity -in 'Blocking', 'High' } | ForEach-Object { "$($_.Severity): $($_.Item)" })
            }
        })
    $has = { param([string] $Id) @($Component | Where-Object Id -EQ $Id).Count -gt 0 }
    $edges = @(
        if ((& $has 'functionapp') -and (& $has 'plan')) { [ordered]@{ source = 'blueprint/functionapp'; target = 'blueprint/plan'; kind = 'dependency'; label = 'runs on' } }
        if ((& $has 'functionapp') -and (& $has 'storage')) { [ordered]@{ source = 'blueprint/functionapp'; target = 'blueprint/storage'; kind = 'dependency'; label = 'runtime state' } }
    )
    @{
        Clusters = @(
            [ordered]@{ id = $regionId; name = $Region; kind = 'region'; icon = 'resource'; parent = '' }
            [ordered]@{ id = $groupId; name = $ResourceGroupName; kind = 'resourcegroup'; icon = 'resourcegroup'; parent = $regionId; detail = @('planned, not deployed') }
        )
        Nodes    = $nodes
        Edges    = $edges
    }
}
