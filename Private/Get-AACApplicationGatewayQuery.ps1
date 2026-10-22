function Get-AACApplicationGatewayQuery {
    <#
    .SYNOPSIS
        The Resource Graph queries Show-AACApplicationGatewayMap reads: the
        gateways, then what their configuration refers to.
    .DESCRIPTION
        -Stage Gateway: gateways (every setting is in properties) and the
        subscriptions' names.
        -Stage Related: by ID (-Id, 200 a query, any subscription): public
        IPs, WAF policies, virtual networks, network interfaces; and App
        Services whose host name is a pool target (-HostName).
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [ValidateSet('Gateway', 'Related')]
        [string] $Stage = 'Gateway',

        [string[]] $ResourceGroupName,

        [string[]] $Id = @(),

        [string[]] $HostName = @()
    )

    $quote = { param([string] $Text) ConvertTo-AACKqlLiteral -Text $Text }
    $list = { param([string[]] $Items) (@($Items | ForEach-Object { & $quote $_ })) -join ', ' }
    $queries = [ordered]@{}
    if ($Stage -eq 'Gateway') {
        $groups = @($ResourceGroupName | Where-Object { $_ })
        $in = if ($groups.Count) { " | where resourceGroup in~ ($(& $list $groups))" } else { '' }
        $queries['gateways'] = "resources | where type =~ 'microsoft.network/applicationgateways'$in | project id = tolower(id), name, location, resourceGroup, subscriptionId = tolower(subscriptionId), zones, tags, properties"
        $queries['subscriptions'] = @{ Tenant = $true; Query = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions' | project subscriptionId = tolower(subscriptionId), name" }
        return $queries
    }
    $ids = @($Id | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique)
    for ($i = 0; $i -lt $ids.Count; $i += 200) {
        $chunk = $ids[$i..([Math]::Min($i + 199, $ids.Count - 1))]
        $queries["ids$i"] = @{ Tenant = $true; Query = "resources | where id in~ ($(& $list $chunk)) | project id = tolower(id), name, type = tolower(type), resourceGroup, subscriptionId = tolower(subscriptionId), sku, properties" }
    }
    $hosts = @($HostName | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique)
    if ($hosts.Count) {
        $queries['sites'] = @{ Tenant = $true; Query = "resources | where type =~ 'microsoft.web/sites' | mv-expand host = properties.hostNames | where tolower(tostring(host)) in~ ($(& $list $hosts)) | project id = tolower(id), name, type = tolower(type), resourceGroup, subscriptionId = tolower(subscriptionId), host = tolower(tostring(host)), kind" }
    }
    $queries
}
