function Show-AACManagementGroupMap {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Draws the management group hierarchy as an interactive map - the
        tenant root and management groups as nested boxes, each
        subscription inside its group - with the subscriptions, policy
        assignments and role assignments at each level.
    .DESCRIPTION
        Reads, read-only and tenant-wide in Azure Resource Graph, the
        management groups and their parents, the subscriptions, the policy
        and role assignments per scope and the resources per subscription,
        and writes the map as one self-contained HTML page (the same page as
        Show-AACResourceMap: pan, zoom, search, click for details, save PNG,
        JPEG, SVG or draw.io). At the prompt: the hierarchy as a tree with
        the counts.

        Unscoped, every management group appears, empty ones too; with
        -ManagementGroupId or -SubscriptionId, only the subscriptions in
        scope and the groups above them. For an editable diagram, use
        Export-AACDiagram -View Governance. Reader is enough.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups (at any depth).
    .PARAMETER SubscriptionId
        Only these subscriptions (and the groups above them).
    .PARAMETER Direction
        LeftToRight (the default) or TopToBottom.
    .PARAMETER Theme
        Dark (the default), Light or Blueprint.
    .PARAMETER HtmlPath
        Where to write the map (by default a file in the temp folder).
    .PARAMETER Title
        The map's title.
    .PARAMETER NoBrowser
        Write the map without opening it.
    .PARAMETER PassThru
        Return the hierarchy: a row per management group (AAC.ManagementGroup).
    .EXAMPLE
        Show-AACManagementGroupMap
        The whole hierarchy, opened in the browser.
    .EXAMPLE
        Show-AACManagementGroupMap -ManagementGroupId 'mg-landingzones' -Theme Light -HtmlPath .\Hierarchy.html -NoBrowser
        The landing zones' part of the hierarchy, written to a file.
    .EXAMPLE
        Show-AACManagementGroupMap -NoBrowser -PassThru | Sort-Object PolicyAssignments -Descending | Select-Object -First 5
        The management groups with the most policy assignments.
    .OUTPUTS
        AAC.ManagementGroup, with -PassThru
    #>
    [CmdletBinding()]
    [OutputType('AAC.ManagementGroup')]
    param(
        [ValidateNotNullOrEmpty()]
        [string[]] $ManagementGroupId,

        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [ValidateSet('LeftToRight', 'TopToBottom')]
        [string] $Direction = 'LeftToRight',

        [ValidateSet('Dark', 'Light', 'Blueprint')]
        [string] $Theme = 'Dark',

        [string] $HtmlPath,

        [string] $Title,

        [switch] $NoBrowser,

        [switch] $PassThru
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $htmlFullPath = if ($HtmlPath) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($HtmlPath) }
    else { Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('AAC-ManagementGroups-{0:yyyyMMdd-HHmmss}.html' -f (Get-Date)) }
    $request = @{ ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }); SubscriptionId = @($SubscriptionId | Where-Object { $_ }); Title = $Title; Direction = $(if ($Direction -eq 'TopToBottom') { 'DOWN' } else { 'RIGHT' }); Theme = $Theme.ToLowerInvariant() }

    Write-AACRule -Title 'Azure Admin Console :: Management groups' -Color 'deepskyblue3_1'
    $state = Invoke-AACProgress -ScriptBlock {
        $null = Get-AACAccessToken
        $built = Read-AACManagementGroupMap -ManagementGroupId $request.ManagementGroupId -SubscriptionId $request.SubscriptionId -Title $request.Title
        Update-AACProgress -Id 'html' -Indeterminate -Description 'Writing the map'
        Write-AACResourceMapHtml -Map $built.Map -Path $htmlFullPath -Title $built.Title -Fact $built.Facts -Direction $request.Direction -Theme $request.Theme -Layout packed -Hierarchy packed
        Update-AACProgress -Id 'html' -Complete -Description "Map: $htmlFullPath"
        $built
    }

    # At the prompt: the hierarchy as a tree.
    $map = $state.Map
    $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
    $rows = @($map.Hierarchy)
    if (-not $rows.Count) { Write-AACMarkup '[grey58]No management groups were found.[/]' }
    else {
        Show-AACTileRow -Tile @(
            @{ Value = '{0:N0}' -f $map.Stats.ManagementGroups; Caption = 'management groups'; Color = 'deepskyblue1' }
            @{ Value = '{0:N0}' -f $map.Stats.Subscriptions; Caption = 'subscriptions'; Color = 'gold1' }
            @{ Value = '{0:N0}' -f $map.Stats.Depth; Caption = 'levels below the root'; Color = $(if ($map.Stats.Depth -ge 6) { 'red1' } elseif ($map.Stats.Depth -ge 5) { 'orange1' } else { 'mediumpurple2' }) }
            @{ Value = '{0:N0}' -f $map.Stats.PolicyAssignments; Caption = 'policy assignments on groups'; Color = 'deepskyblue1' }
        )
        [Spectre.Console.AnsiConsole]::WriteLine()
        $byParent = @{}
        foreach ($r in $rows) { $p = [string]$r.Parent; if (-not $byParent.Contains($p)) { $byParent[$p] = [System.Collections.Generic.List[object]]::new() }; $byParent[$p].Add($r) }
        $label = { param($Row) "[bold]$(& $escape $Row.ManagementGroup)[/] [grey58]$($Row.SubscriptionsBelow) sub(s)$(if ($Row.PolicyAssignments) { " · $($Row.PolicyAssignments) polic(ies)" })$(if ($Row.RoleAssignments) { " · $($Row.RoleAssignments) role(s)" })[/]" }
        $top = @($rows | Where-Object { -not $_.Parent -or -not @($rows | Where-Object ManagementGroup -EQ $_.Parent).Count })
        $tree = [Spectre.Console.Tree]::new([Spectre.Console.Markup]::new('[grey62]Hierarchy[/]'))
        $tree.Style = [Spectre.Console.Style]::Parse('grey42')
        if (-not [Spectre.Console.AnsiConsole]::Profile.Capabilities.Unicode) { $tree.Guide = [Spectre.Console.TreeGuide]::Ascii }
        $grow = $null
        $grow = {
            param($Node, $Row, [int] $Depth)
            $child = [Spectre.Console.TreeNode]::new([Spectre.Console.Markup]::new((& $label $Row)))
            $Node.Nodes.Add($child)
            if ($Depth -lt 12 -and $byParent.Contains($Row.ManagementGroup)) { foreach ($c in @($byParent[$Row.ManagementGroup] | Sort-Object ManagementGroup)) { & $grow $child $c ($Depth + 1) } }
        }
        foreach ($t in $top) { & $grow $tree $t 0 }
        [Spectre.Console.AnsiConsole]::Write($tree)
        [Spectre.Console.AnsiConsole]::WriteLine()
    }
    if (-not $NoBrowser) {
        Open-AACFile -Path $htmlFullPath
        Write-AACMarkup '[grey58]Opened in your browser: click a box or subscription for its details; Save PNG, JPEG, SVG or draw.io at the top.[/]'
    }
    else { Write-AACMarkup "[grey58]Map: $(& $escape $htmlFullPath)[/]" }
    if ($PassThru) { $rows }
}
