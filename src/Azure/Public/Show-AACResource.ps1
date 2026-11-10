function Show-AACResource {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Deprecated: use Get-AACInventory -View Chart. Shows how many Azure resources you have - by type, location, resource
        group or subscription - as a colourful Spectre.Console bar chart.
    .DESCRIPTION
        Deprecated, and to be removed in a later release: Get-AACInventory -View Chart
        draws the same chart, with the same parameters. This command still works, and
        warns.

        Counts every resource the signed-in account can see (or only those in
        -SubscriptionId, of -ResourceType) with Azure Resource Graph, over
        REST with the Connect-AAC sign-in - two queries however many
        resources there are, and no Az modules.

        The view:
          ── Azure Admin Console :: Azure resources ─────────────────────
          account · tenant · scope · when
          [ resources ] [ types ] [ subscriptions ] [ resource groups ] [ locations ]

          Resources by type (top 20)
          compute/virtualmachines       ████████████████████████ 412
          network/networkinterfaces     ███████████████████ 398
          storage/storageaccounts       ██████████ 164
          ...
          37 other types                ████ 61

        Each bar has its own colour. -By picks what is counted: resource
        Type (the default), Location, ResourceGroup or Subscription. -Top
        sets how many bars are drawn; the rest are summed in a final grey
        bar.

        When the view is longer than the terminal it is paged: press any key
        for the next page, or A for the rest. -NoPaging turns that off.

        With -PassThru the counts are also returned as AAC.ResourceCount
        objects (Name, Count, Share), every one of them, not only the top.

        -HtmlPath writes a self-contained, interactive inventory instead of
        the view: every resource (name, type, resource group, location,
        subscription, kind, SKU, tags) with Azure portal links, tiles and
        charts by type, location, subscription and resource group that
        filter it, search, filters, grouping and a CSV download. It needs one
        more Resource Graph query, for the resources themselves. With
        -HtmlPath the console shows only the progress and the file written.
    .PARAMETER SubscriptionId
        Only count resources in these subscriptions. Defaults to every
        subscription the signed-in account can see.
    .PARAMETER By
        What to count by: Type (default), Location, ResourceGroup or
        Subscription.
    .PARAMETER ResourceType
        Only count resources of these types. Case-insensitive; wildcards
        work, e.g. 'microsoft.network/*'.
    .PARAMETER Top
        How many bars to draw (default 20); the rest are summed in one bar.
    .PARAMETER HtmlPath
        Write an interactive HTML inventory of the resources to this file
        instead of showing the view. An existing file is overwritten;
        missing folders are created.
    .PARAMETER Title
        The HTML report's title. Defaults to 'Azure resources'.
    .PARAMETER NoPaging
        Show the whole view at once instead of a screen at a time.
    .PARAMETER PassThru
        Also return the counts as AAC.ResourceCount objects.
    .EXAMPLE
        Connect-AAC
        Show-AACResource
        The top 20 resource types across every subscription you can see.
    .EXAMPLE
        Show-AACResource -By Location
        How many resources are in each Azure region.
    .EXAMPLE
        Show-AACResource -ResourceType 'microsoft.network/*' -Top 10
        The ten most common networking resource types.
    .EXAMPLE
        Show-AACResource -By Subscription -PassThru | Export-Csv .\ResourcesPerSubscription.csv -NoTypeInformation
        Shows resources per subscription and saves the counts as a CSV file.
    .EXAMPLE
        Show-AACResource -HtmlPath .\out\Inventory.html
        Every resource in an interactive HTML inventory, with portal links.
    .OUTPUTS
        AAC.ResourceCount (with -PassThru)
    #>
    [CmdletBinding()]
    [OutputType('AAC.ResourceCount')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [ValidateSet('Type', 'Location', 'ResourceGroup', 'Subscription')]
        [string] $By = 'Type',

        # Letters, digits, '.', '/', '-', '_' and '*' only: the patterns go
        # into a Resource Graph query.
        [ValidatePattern('^[\w.*/-]+$')]
        [SupportsWildcards()]
        [string[]] $ResourceType,

        [ValidateRange(1, 100)]
        [int] $Top = 20,

        [string] $HtmlPath,

        [string] $Title = 'Azure resources',

        [switch] $NoPaging,

        [switch] $PassThru
    )

    # A failure anywhere below ends as a Spectre.Console error panel and this
    # command's own terminating error, not a line inside the module. A stopped
    # pipeline (Select-Object -First, Ctrl+C) is no failure: just return - a
    # rethrow would stop the caller's whole script, not only this command.
    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    # Resolve the path now, relative to the caller's location, so a bad path
    # fails before any Azure call.
    $htmlFullPath = if ($HtmlPath) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($HtmlPath) }

    Write-Warning 'Show-AACResource is deprecated and will be removed in a later release. Use Get-AACInventory -View Chart, with the same -By, -ResourceType, -Top and -HtmlPath.'
    Show-AACResourceChart -SubscriptionId $SubscriptionId -By $By -ResourceType $ResourceType -Top $Top -HtmlFullPath $htmlFullPath -Title $Title -NoPaging:$NoPaging -PassThru:$PassThru
}