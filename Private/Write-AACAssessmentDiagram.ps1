function Write-AACAssessmentDiagram {
    <#
    .SYNOPSIS
        Writes Invoke-AACAssessment's interactive diagrams - self-contained
        HTML pages laid out with ELK, with the Azure icons, pan, zoom,
        search, details on click and PNG / SVG export - and returns them.
    .DESCRIPTION
        <name>-Network.html       the network topology: virtual networks and
                                  their subnets, peerings, gateways and
                                  connections, firewalls, Bastion, load
                                  balancers, application gateways, NAT
                                  gateways, private endpoints, DNS zones -
                                  with NSGs and route tables (and their
                                  rules and routes) on what they apply to
                                  (every resource with -DiagramFullEnvironment)
        <name>-Organization.html  management groups > subscriptions >
                                  resource groups, with resource counts
        <name>-Resources.html     each subscription with a node per resource
                                  type and its count (-Inventory)
        Resource rows come from Get-AACAssessmentExtraQuery -Stage Diagram;
        the organization from ConvertTo-AACAssessment's Organization.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [string] $Folder,

        [Parameter(Mandatory)]
        [string] $ReportName,

        [AllowEmptyCollection()]
        [object[]] $Resource = @(),

        # Every resource (type, subscriptionId, location, resourceGroup), for the resources view.
        [AllowEmptyCollection()]
        [object[]] $Inventory = @(),

        [Parameter(Mandatory)]
        [hashtable] $Organization,

        [hashtable] $SubscriptionName = @{},

        [string] $Scope = '',

        [switch] $FullEnvironment
    )

    $asset = Get-AACResourceMapAsset
    $labels = @{}
    foreach ($key in $asset.Icons.icons.Keys) { $labels[$key] = [string]$asset.Icons.icons[$key].label }
    $drawn = (Get-Date).ToString('d MMM yyyy HH:mm')

    if (@($Resource).Count) {
        $map = ConvertTo-AACResourceMap -Resource @($Resource) -SubscriptionName $SubscriptionName -IconType $asset.Icons.types -IconLabel $labels
        $path = Join-Path -Path $Folder -ChildPath "$ReportName-Network.html"
        $facts = @(
            '{0:N0} resources' -f $map.Stats.Resources
            '{0:N0} virtual network(s)' -f $map.Stats.Networks
            '{0:N0} connections' -f $map.Stats.Connections
            if ($map.Stats.Orphans) { '{0:N0} unattached' -f $map.Stats.Orphans }
            if ($map.Stats.Flagged) { '{0:N0} NSG / route table(s) flagged' -f $map.Stats.Flagged }
            if ($Scope) { $Scope }
            "drawn $drawn"
        )
        Write-AACResourceMapHtml -Map $map -Path $path -Title $(if ($FullEnvironment) { 'Azure environment: resources and network' } else { 'Azure network topology' }) -Fact $facts
        Get-Item -LiteralPath $path
    }

    $org = ConvertTo-AACOrganizationMap -ManagementGroup $Organization.ManagementGroup -Subscription $Organization.Subscription -ResourceGroup $Organization.ResourceGroup -ResourceCount $Organization.ResourceCount
    if ($org.Nodes.Count -or $org.Clusters.Count) {
        $path = Join-Path -Path $Folder -ChildPath "$ReportName-Organization.html"
        $facts = @(
            '{0:N0} management group(s)' -f $org.Stats.ManagementGroups
            '{0:N0} subscription(s)' -f $org.Stats.Subscriptions
            '{0:N0} resource group(s){1}' -f $org.Stats.Groups, $(if (-not $org.Stats.GroupsDrawn) { ' (too many to draw: subscriptions only)' })
            if ($Scope) { $Scope }
            "drawn $drawn"
        )
        Write-AACResourceMapHtml -Map $org -Path $path -Title 'Azure organization' -Fact $facts -Direction 'DOWN'
        Get-Item -LiteralPath $path
    }

    if (@($Inventory).Count) {
        $summary = ConvertTo-AACResourceSummaryMap -Resource @($Inventory) -SubscriptionName $SubscriptionName -IconType $asset.Icons.types -IconLabel $labels
        $path = Join-Path -Path $Folder -ChildPath "$ReportName-Resources.html"
        $facts = @(
            '{0:N0} resources' -f $summary.Stats.Resources
            '{0:N0} subscription(s)' -f $summary.Stats.Subscriptions
            'a node per subscription and resource type'
            if ($Scope) { $Scope }
            "drawn $drawn"
        )
        Write-AACResourceMapHtml -Map $summary -Path $path -Title 'Azure resources by subscription' -Fact $facts -Direction 'DOWN'
        Get-Item -LiteralPath $path
    }
}
