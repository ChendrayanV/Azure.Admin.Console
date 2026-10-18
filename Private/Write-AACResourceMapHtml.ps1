function Write-AACResourceMapHtml {
    <#
    .SYNOPSIS
        Writes the resource map as one self-contained HTML page: the map
        (ConvertTo-AACResourceMap), the Azure icons it uses and the ELK
        layout library, all inline - it opens without a network connection.
    .DESCRIPTION
        The page lays the map out in the browser with ELK's layered layout
        (left to right or top to bottom), draws it as SVG with the Azure
        icons, and lets you pan, zoom, search, highlight a resource's
        connections, switch the theme and direction, and save the map as a
        PNG, JPEG or SVG image. See Private\ResourceMap.html.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Map,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Title,

        [string[]] $Fact = @(),

        [ValidateSet('RIGHT', 'DOWN')]
        [string] $Direction = 'RIGHT',

        [ValidateSet('dark', 'light', 'blueprint')]
        [string] $Theme = 'dark',

        # NSGs and route tables as chips on what they're applied to, or as cards.
        [ValidateSet('chips', 'cards')]
        [string] $NsgView = 'chips',

        # layered: ELK's layered layout of the nested boxes. hubspoke: each
        # hub with its spokes around it (Show-AACNetworkTopology), the page
        # able to switch to layered.
        [ValidateSet('layered', 'hubspoke', 'packed')]
        [string] $Layout = 'layered',

        # What the page's Hierarchy button draws: layered (ELK's layers), or
        # packed - boxes inside boxes in a grid, the lines drawn straight.
        [ValidateSet('layered', 'packed')]
        [string] $Hierarchy = 'layered',

        # The print page, for a PDF: no toolbar or panels, the whole map at
        # full size with its legend below, on a page that fits it.
        [switch] $Print
    )

    $asset = Get-AACResourceMapAsset

    # Only the icons the map uses, plus the boxes' and the fallback.
    $used = [System.Collections.Generic.HashSet[string]]::new([string[]]@('resource', 'subscription', 'resourcegroup', 'vnet', 'subnet', 'nsg', 'routetable'))
    foreach ($node in $Map.Nodes) { [void]$used.Add([string]$node.icon) }
    foreach ($cluster in $Map.Clusters) { [void]$used.Add([string]$cluster.icon) }
    $icons = [ordered]@{}
    foreach ($key in $used) {
        if ($asset.Icons.icons.Contains($key)) { $icons[$key] = $asset.Icons.icons[$key] }
    }

    $model = [ordered]@{
        title    = $Title
        facts    = @($Fact)
        options  = @{ direction = $Direction; theme = $Theme; nsgView = $NsgView; layout = $Layout; hierarchy = $Hierarchy; print = [bool]$Print; hubSpoke = [bool]@($Map.Clusters | Where-Object { $_.Contains('role') -and $_['role'] -eq 'hub' }).Count }
        clusters = @($Map.Clusters)
        nodes    = @($Map.Nodes)
        edges    = @($Map.Edges)
        icons    = $icons
    }
    # '</' can't appear inside a <script> element; '<\/' is the same JSON.
    $json = (ConvertTo-Json -InputObject $model -Depth 12 -Compress).Replace('</', '<\/')
    $titleHtml = [System.Net.WebUtility]::HtmlEncode($Title)
    $html = $asset.Template.Replace('/*AAC:TITLE*/', $titleHtml).Replace('/*AAC:DATA*/', $json).Replace('/*AAC:ELK*/', $asset.Elk.Replace('</script', '<\/script'))

    $folder = Split-Path -Path $Path -Parent
    if ($folder -and -not (Test-Path -LiteralPath $folder)) {
        $null = New-Item -ItemType Directory -Path $folder -Force
    }
    [System.IO.File]::WriteAllText($Path, $html, [System.Text.UTF8Encoding]::new($false))
}
