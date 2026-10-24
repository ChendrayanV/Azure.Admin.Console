function Get-AACSkuAvailability {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Which VM sizes you can use - for virtual machines or AKS node pools -
        in a region and its availability zones, with your subscription's
        restrictions and vCPU quota, and why a size can't be used.
    .DESCRIPTION
        Read-only, over REST (Reader is enough, no Az modules or Azure CLI,
        nothing created). For each subscription and region, read at once:
          Microsoft.Compute/skus      the sizes offered, their zones, the
                                      subscription's restrictions (region or
                                      zone) and capabilities
          Microsoft.Compute/usages    each family's and the region's vCPU
                                      quota
          subscription locations      which physical zone each logical zone
                                      is (they differ between subscriptions)
        and, with -ClusterName, the AKS cluster and its node pools (Azure
        Resource Graph).

        Each size's status, the first that applies:
          Restricted       not offered to the subscription in the region
          NotSupported     -Service Aks: fewer than 2 vCPUs
          ZoneUnavailable  -Zone: none of those zones can host it
          Partial          -Zone: some of them can't
          NoQuota          fewer free vCPUs (family or region) than
                           vCPUs x -NodeCount
          Available        usable
        with the reason, and the size's vCPUs, memory, zones, architecture,
        ephemeral OS disk, accelerated networking, premium storage, Spot,
        GPUs and data disks. -Service Aks adds AKS's rules: at least 2 vCPUs;
        4 GB for system node pools, and burstable (B) sizes noted as unfit
        for them.

        What only a real deployment proves is that capacity is there at that
        moment; nothing here creates anything to find out.

        What you get depends on where the command runs:
          at the prompt    tiles, the zones, the quota, the cluster's node
                           pools (-ClusterName) and each size with its status
                           and reason - a page at a time
          piped onward     the sizes (AAC.SkuAvailability), with no view
          -PassThru        the view and the sizes
          -NoDisplay       the sizes only
        -CsvPath writes the sizes. -HtmlPath writes an interactive report
        (sizes, quota, zones, node pools; charts that filter them). -PdfPath
        writes a PDF.
    .PARAMETER Location
        The regions to check (for example uksouth, westeurope). With
        -ClusterName, the cluster's region by default.
    .PARAMETER Service
        VirtualMachine (the default) or Aks: AKS's node pool rules as well.
    .PARAMETER Zone
        The availability zones the size must be in (for example 1, 2, 3).
        Without it, zones are shown but not required.
    .PARAMETER SubscriptionId
        The subscriptions to check - restrictions and quota are per
        subscription. The cluster's with -ClusterName; the only one you can
        see otherwise.
    .PARAMETER ClusterName
        An AKS cluster: checks its region, marks the sizes its node pools use
        and shows each pool's size status and free quota. Implies -Service
        Aks.
    .PARAMETER ResourceGroupName
        The cluster's resource group, when the name alone isn't unique.
    .PARAMETER Series
        Only these VM series - the letters of the size name, for example D,
        E, F, NC, DC (Standard_D4s_v5 is D); wildcards allowed.
    .PARAMETER Sku
        Only these sizes, for example Standard_D4s_v5 or D4s_v5; wildcards
        allowed (*s_v5).
    .PARAMETER Architecture
        Only x64 or Arm64 sizes.
    .PARAMETER NodeCount
        The number of VMs or nodes the quota must fit (vCPUs x NodeCount).
        1 by default.
    .PARAMETER CsvPath
        Write every size to this CSV file.
    .PARAMETER PdfPath
        Write a PDF report to this file.
    .PARAMETER HtmlPath
        Write an interactive HTML report to this file.
    .PARAMETER Title
        The PDF and HTML reports' title.
    .PARAMETER PassThru
        Show the view and also return the sizes.
    .PARAMETER NoDisplay
        Return the sizes without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once instead of a page at a time.
    .EXAMPLE
        Connect-AAC
        Get-AACSkuAvailability -Location uksouth -Zone 1, 2, 3 -Series D, E
        The D and E series sizes that can run in all three zones of UK South.
    .EXAMPLE
        Get-AACSkuAvailability -ClusterName 'aks-contoso' -Zone 1, 2, 3 -Sku '*s_v5' -NodeCount 3
        Sizes for a new three-node, three-zone pool on a cluster, in its region, with its current pools.
    .EXAMPLE
        Get-AACSkuAvailability -Service Aks -Location uksouth, ukwest -SubscriptionId '00000000-0000-0000-0000-000000000000' -Architecture Arm64 -HtmlPath .\out\Skus.html
        Arm64 sizes for AKS in two regions, as an HTML report.
    .EXAMPLE
        Get-AACSkuAvailability -Location westeurope -Zone 1, 2, 3 -NoDisplay | Where-Object Status -EQ 'Available' | Where-Object { $_.vCPUs -eq 4 -and $_.MemoryGB -ge 16 }
        Every 4 vCPU, 16 GB+ size usable in all three zones.
    .OUTPUTS
        AAC.SkuAvailability (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.SkuAvailability')]
    param(
        [ValidateNotNullOrEmpty()]
        [string[]] $Location,

        [ValidateSet('VirtualMachine', 'Aks')]
        [string] $Service = 'VirtualMachine',

        [ValidatePattern('^\d$')]
        [string[]] $Zone,

        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [ValidateNotNullOrEmpty()]
        [string] $ClusterName,

        [ValidateNotNullOrEmpty()]
        [string] $ResourceGroupName,

        [ValidateNotNullOrEmpty()]
        [string[]] $Series,

        [ValidateNotNullOrEmpty()]
        [string[]] $Sku,

        [ValidateSet('x64', 'Arm64')]
        [string] $Architecture,

        [ValidateRange(1, 5000)]
        [int] $NodeCount = 1,

        [string] $CsvPath,

        [string] $PdfPath,

        [string] $HtmlPath,

        [string] $Title = 'VM size availability',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    # A failure anywhere below ends as a Spectre.Console error panel and this
    # command's own terminating error, not a line inside the module. A stopped
    # pipeline (Select-Object -First, Ctrl+C) is no failure: just return - a
    # rethrow would stop the caller's whole script, not only this command.
    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    if (-not $Location -and -not $ClusterName) { throw 'Say where to look: -Location (for example uksouth), or -ClusterName for an AKS cluster''s region.' }
    if ($ResourceGroupName -and -not $ClusterName) { throw '-ResourceGroupName is the AKS cluster''s resource group: use it with -ClusterName.' }
    if ($ClusterName) { $Service = 'Aks' }
    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $showView = $interactive -and -not ($CsvPath -or $PdfPath -or $HtmlPath)
    $returnObjects = $PassThru -or $NoDisplay -or $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $csvFullPath = & $resolve $CsvPath
    $pdfFullPath = & $resolve $PdfPath
    $htmlFullPath = & $resolve $HtmlPath
    $label = if ($Service -eq 'Aks') { 'AKS node pool' } else { 'VM' }

    if ($interactive) {
        Write-AACRule -Title "Azure Admin Console :: $label size availability" -Color 'deepskyblue3_1'
    }
    $state = Invoke-AACProgress -ScriptBlock {
        $null = Get-AACAccessToken
        $escape = { param([string] $Text) $Text -replace "'", "\'" }

        # --- The AKS cluster, when asked: its region, subscription and node pools ------------------------------
        $cluster = $null
        $pools = @()
        if ($ClusterName) {
            Update-AACProgress -Id 'cluster' -Total 1 -Description "Finding the AKS cluster '$ClusterName'"
            $query = "resources | where type =~ 'microsoft.containerservice/managedclusters' and name =~ '$(& $escape $ClusterName)'$(if ($ResourceGroupName) { " and resourceGroup =~ '$(& $escape $ResourceGroupName)'" }) | project id, name, resourceGroup, subscriptionId, location, pools = properties.agentPoolProfiles"
            $found = @((Invoke-AACGraphBatch -Query @{ cluster = $query } -SubscriptionId $SubscriptionId).Rows['cluster'])
            if (-not $found.Count) { throw "No AKS cluster named '$ClusterName'$(if ($ResourceGroupName) { " in resource group '$ResourceGroupName'" }) was found in the subscriptions the account can see." }
            if ($found.Count -gt 1) { throw "$($found.Count) AKS clusters are named '$ClusterName' (in $(@($found | ForEach-Object { "$($_['resourceGroup'])" }) -join ', ')): add -ResourceGroupName." }
            $cluster = $found[0]
            $pools = @(foreach ($pool in @($cluster['pools'])) {
                    if ($null -eq $pool) { continue }
                    @{ Name = [string]$pool['name']; Mode = [string]$pool['mode']; VmSize = [string]$pool['vmSize']; Count = $pool['count']; Zones = @($pool['availabilityZones']); OsType = [string]$pool['osType'] }
                })
            if (-not $Location) { $Location = @([string]$cluster['location']) }
            if (-not $SubscriptionId) { $SubscriptionId = @([string]$cluster['subscriptionId']) }
            Update-AACProgress -Id 'cluster' -Complete -Description "Found $ClusterName in $($cluster['location']): $($pools.Count) node pool(s)"
        }
        $locations = @($Location | ForEach-Object { ($_ -replace '\s', '').ToLowerInvariant() } | Select-Object -Unique)

        # --- Subscriptions: their names, and which to check ------------------------------------------------------
        Update-AACProgress -Id 'subs' -Total 1 -Description 'Reading the subscriptions'
        $all = @((Invoke-AACArmParallel -Uri @('/subscriptions?api-version=2022-12-01'))['/subscriptions?api-version=2022-12-01'].Items)
        $names = @{}
        foreach ($item in $all) { $names[([string]$item['subscriptionId']).ToLowerInvariant()] = [string]$item['displayName'] }
        if (-not $SubscriptionId) {
            $enabled = @($all | Where-Object { $_['state'] -eq 'Enabled' })
            if ($enabled.Count -ne 1) { throw "Restrictions and quota are per subscription: pass -SubscriptionId ($(if ($enabled.Count) { "the account can see $($enabled.Count)" } else { 'the account can see none' }))." }
            $SubscriptionId = @([string]$enabled[0]['subscriptionId'])
        }
        $subscriptions = @($SubscriptionId | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique)
        Update-AACProgress -Id 'subs' -Complete -Description "Checking $($subscriptions.Count) subscription(s) in $($locations -join ', ')"

        # --- Sizes, quota and zones: every subscription and region at once ---------------------------------------
        $uris = [ordered]@{}
        foreach ($subscription in $subscriptions) {
            $uris["$subscription|zones"] = "/subscriptions/$subscription/locations?api-version=2022-12-01"
            foreach ($region in $locations) {
                $uris["$subscription|$region|skus"] = "/subscriptions/$subscription/providers/Microsoft.Compute/skus?api-version=2021-07-01&`$filter=$([uri]::EscapeDataString("location eq '$region'"))"
                $uris["$subscription|$region|usages"] = "/subscriptions/$subscription/providers/Microsoft.Compute/locations/$region/usages?api-version=2023-09-01"
            }
        }
        Update-AACProgress -Id 'read' -Total $uris.Count -Description 'Reading VM sizes, quota and zones'
        $read = Invoke-AACArmParallel -Uri @($uris.Values) -OnProgress { param($Done, $Total) Update-AACProgress -Id 'read' -Increment 1 -Description "Read $Done of $Total (sizes, quota, zones)" }

        $notices = [System.Collections.Generic.List[string]]::new()
        $entries = @(foreach ($subscription in $subscriptions) {
                $zoneResult = $read[$uris["$subscription|zones"]]
                if ($zoneResult.Error) { $notices.Add("The zone mapping of $(if ($names.Contains($subscription)) { $names[$subscription] } else { $subscription }) couldn't be read: $($zoneResult.Error)") }
                foreach ($region in $locations) {
                    $skuResult = $read[$uris["$subscription|$region|skus"]]
                    if ($skuResult.Error) { throw "The VM sizes in $region couldn't be read for subscription $subscription`: $($skuResult.Error)" }
                    $usageResult = $read[$uris["$subscription|$region|usages"]]
                    $mapping = @(foreach ($place in @($zoneResult.Items)) { if ($place -and [string]$place['name'] -eq $region) { @($place['availabilityZoneMappings']) } })
                    @{
                        SubscriptionId   = $subscription
                        SubscriptionName = $(if ($names.Contains($subscription)) { $names[$subscription] } else { $subscription })
                        Location         = $region
                        Skus             = @($skuResult.Items)
                        Usages           = $(if ($usageResult.Error) { @() } else { @($usageResult.Items) })
                        ZoneMappings     = @($mapping | Where-Object { $_ })
                    }
                }
            })
        $availability = ConvertTo-AACSkuAvailability -Read $entries -Service $Service -Zone @($Zone | Where-Object { $_ }) -Series @($Series | Where-Object { $_ }) -Sku @($Sku | Where-Object { $_ }) -Architecture $Architecture -NodeCount $NodeCount -Pool $pools -PoolLocation $(if ($cluster) { [string]$cluster['location'] } else { '' })
        $stats = $availability.Stats
        Update-AACProgress -Id 'read' -Complete -Description ('{0:N0} size(s): {1:N0} available, {2:N0} in some zones, {3:N0} short of quota, {4:N0} restricted' -f $stats.Sizes, $stats.Available, $stats.Partial, $stats.NoQuota, $stats.Restricted)

        foreach ($notice in $availability.Notice) { $notices.Add($notice) }
        if ($Zone -and -not @($availability.Zones).Count) { $notices.Add('No zone mapping was returned: the region may have no availability zones.') }
        if (($Series -or $Sku -or $Architecture) -and -not $stats.Sizes) { $notices.Add('No size matches -Series, -Sku or -Architecture in this region.') }
        $availability.Notice = $notices.ToArray()

        $scope = [ordered]@{
            Service       = $(if ($Service -eq 'Aks') { 'AKS node pools' } else { 'Virtual machines' })
            Regions       = $locations -join ', '
            Subscriptions = (@($subscriptions | ForEach-Object { if ($names.Contains($_)) { $names[$_] } else { $_ } }) -join ', ')
        }
        if ($cluster) { $scope['Cluster'] = "$($cluster['name']) ($($cluster['resourceGroup']))" }
        if ($Zone) { $scope['Zones'] = ($Zone | Sort-Object -Unique) -join ', ' }
        if ($Series) { $scope['Series'] = $Series -join ', ' }
        if ($Sku) { $scope['Sizes'] = $Sku -join ', ' }
        if ($Architecture) { $scope['Architecture'] = $Architecture }
        $scope['Quota for'] = "$NodeCount $(if ($Service -eq 'Aks') { 'node(s)' } else { 'VM(s)' })"
        $null = Invoke-AACExport -CsvPath $csvFullPath -CsvObject @($availability.Skus) -Noun 'VM size' -PdfPath $pdfFullPath -WritePdf {
            Write-AACSkuAvailabilityPdf -Availability $availability -Path $pdfFullPath -Title $Title -Detail $scope
        } -HtmlPath $htmlFullPath -WriteHtml {
            Write-AACSkuAvailabilityHtml -Availability $availability -Path $htmlFullPath -Title $Title -Detail $scope
        }
        @{ Availability = $availability; Scope = $scope }
    }

    if ($showView) {
        Invoke-AACPagedOutput -NoPaging:$NoPaging -ScriptBlock {
            Show-AACSkuAvailabilityView -Availability $state.Availability -Scope $state.Scope
        }
    }
    elseif ($interactive) {
        foreach ($notice in @($state.Availability.Notice)) { Write-AACMarkup "[grey58]$([Spectre.Console.Markup]::Escape($notice))[/]" }
    }
    if ($returnObjects) {
        $state.Availability.Skus
    }
}
