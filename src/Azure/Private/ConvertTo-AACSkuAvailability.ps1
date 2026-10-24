function ConvertTo-AACSkuAvailability {
    <#
    .SYNOPSIS
        Builds Get-AACSkuAvailability's result: one row per VM size, region
        and subscription - whether it can be used there, and why not - with
        the quota and zone tables behind it.
    .DESCRIPTION
        -Read is one entry per subscription and region: @{ SubscriptionId;
        SubscriptionName; Location; Skus (Microsoft.Compute/skus items);
        Usages (Microsoft.Compute/locations/usages items); ZoneMappings
        (availabilityZoneMappings of the subscription's locations) }.

        Each size's status, the first that applies:
          Restricted       not offered to this subscription in the region
                           (a Location restriction: NotAvailableForSubscription)
          NotSupported     -Service Aks: fewer than 2 vCPUs - AKS can't use it
          ZoneUnavailable  -Zone asked: none of those zones can host it
          Partial          -Zone asked: some of them can't
          NoQuota          the family's or the region's free vCPUs are fewer
                           than vCPUs x -NodeCount
          Available        none of the above
        Zones a size is offered in, less any Zone restriction for the
        subscription, are where it can run. Quota is judged only where
        Azure reports it.

        -Pool (AKS: @{ Name; Mode; VmSize; Count; Zones; OsType }) marks the
        sizes a cluster uses and returns its node pools with their size's
        status and free quota.

        Returns @{ Skus (AAC.SkuAvailability); Quotas (AAC.SkuQuota); Zones
        (AAC.SkuZone); Pools (AAC.AksNodePool); Notice; Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyCollection()]
        [object[]] $Read = @(),

        [ValidateSet('VirtualMachine', 'Aks')]
        [string] $Service = 'VirtualMachine',

        [string[]] $Zone = @(),

        [string[]] $Series = @(),

        [string[]] $Sku = @(),

        [string] $Architecture,

        [ValidateRange(1, 5000)]
        [int] $NodeCount = 1,

        [AllowEmptyCollection()]
        [object[]] $Pool = @(),

        [string] $PoolLocation
    )

    $value = { param($Object, [string] $Key) if ($Object -is [System.Collections.IDictionary]) { if ($Object.Contains($Key)) { $Object[$Key] } } else { Get-AACPropertyValue -InputObject $Object -Name $Key } }
    $text = { param($Object, [string] $Key) $v = & $value $Object $Key; if ($null -eq $v) { '' } else { [string]$v } }
    $flag = { param($Caps, [string] $Key) $Caps.Contains($Key) -and $Caps[$Key] -eq 'True' }
    $statusRank = @{ Available = 0; Partial = 1; NoQuota = 2; ZoneUnavailable = 3; NotSupported = 4; Restricted = 5 }
    $zones = @($Zone | Where-Object { $_ } | ForEach-Object { ([string]$_).Trim() } | Sort-Object -Unique)
    # A size asked for by name: as given (wildcards allowed), or without its tier prefix.
    $skuPatterns = @(foreach ($pattern in @($Sku | Where-Object { $_ })) { $pattern; if ($pattern -notmatch '^(?i)(Standard|Basic)_') { "Standard_$pattern" } })
    $poolsBySize = @{}
    foreach ($entry in $Pool) {
        $size = (& $text $entry 'VmSize').ToLowerInvariant()
        if (-not $poolsBySize.Contains($size)) { $poolsBySize[$size] = [System.Collections.Generic.List[string]]::new() }
        $poolsBySize[$size].Add((& $text $entry 'Name'))
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    $quotas = [System.Collections.Generic.List[object]]::new()
    $zoneRows = [System.Collections.Generic.List[object]]::new()
    $notices = [System.Collections.Generic.List[string]]::new()
    $usageBy = @{}
    foreach ($region in $Read) {
        $location = ([string]$region.Location).ToLowerInvariant()
        $subscription = [string]$region.SubscriptionId
        $subscriptionName = if ($region.SubscriptionName) { [string]$region.SubscriptionName } else { $subscription }

        # --- Quota: each family's, and the region's, vCPUs --------------------------------------------------------
        $usage = @{}
        foreach ($item in @($region.Usages)) {
            $name = & $value $item 'name'
            $key = (& $text $name 'value').ToLowerInvariant()
            if (-not $key) { continue }
            $usage[$key] = @{ Name = $(if (& $text $name 'localizedValue') { & $text $name 'localizedValue' } else { $key }); Current = [long](& $value $item 'currentValue'); Limit = [long](& $value $item 'limit') }
        }
        $usageBy["$subscription|$location"] = $usage
        $regional = if ($usage.Contains('cores')) { $usage['cores'] } else { $null }
        if (-not $usage.Count) { $notices.Add("The vCPU quota in $location ($subscriptionName) couldn't be read, so it isn't checked.") }

        # --- Zones: logical to physical ---------------------------------------------------------------------------
        foreach ($mapping in @($region.ZoneMappings)) {
            $zoneRows.Add([pscustomobject][ordered]@{
                    PSTypeName       = 'AAC.SkuZone'
                    SubscriptionName = $subscriptionName
                    Location         = $location
                    LogicalZone      = & $text $mapping 'logicalZone'
                    PhysicalZone     = & $text $mapping 'physicalZone'
                    SubscriptionId   = $subscription
                })
        }

        # --- VM sizes ----------------------------------------------------------------------------------------
        $vmSkus = @($region.Skus | Where-Object { (& $text $_ 'resourceType') -eq 'virtualMachines' })
        if (-not $vmSkus.Count) { $notices.Add("No VM sizes were returned for '$location' in $subscriptionName - check the region's name (for example uksouth, not UK South).") }
        foreach ($item in $vmSkus) {
            $name = & $text $item 'name'
            $seriesName = if ($name -match '^(?i)(?:Standard|Basic)_([A-Za-z]+)') { $Matches[1].ToUpperInvariant() } else { '' }
            if ($Series.Count -and -not @($Series | Where-Object { $seriesName -like $_ }).Count) { continue }
            if ($skuPatterns.Count -and -not @($skuPatterns | Where-Object { $name -like $_ }).Count) { continue }
            $caps = @{}
            foreach ($capability in @(& $value $item 'capabilities')) { $caps[(& $text $capability 'name')] = & $text $capability 'value' }
            $arch = if ($caps.Contains('CpuArchitectureType')) { $caps['CpuArchitectureType'] } else { 'x64' }
            if ($Architecture -and $arch -ne $Architecture) { continue }
            $vCpus = if ($caps.Contains('vCPUs')) { [int]$caps['vCPUs'] } else { 0 }
            $memory = if ($caps.Contains('MemoryGB')) { [double]$caps['MemoryGB'] } else { 0 }
            $family = & $text $item 'family'

            # Offered zones, less the ones restricted for this subscription.
            $info = @(& $value $item 'locationInfo' | Where-Object { (& $text $_ 'location') -eq $location })
            $offered = @(foreach ($entry in $info) { @(& $value $entry 'zones') }) | Where-Object { $_ } | ForEach-Object { [string]$_ } | Sort-Object -Unique
            $offered = @($offered)
            $locationRestriction = $null
            $restrictedZones = [System.Collections.Generic.List[string]]::new()
            foreach ($restriction in @(& $value $item 'restrictions')) {
                $reasonCode = & $text $restriction 'reasonCode'
                if ((& $text $restriction 'type') -eq 'Location') {
                    if (@(& $value $restriction 'values' | Where-Object { ([string]$_).ToLowerInvariant() -eq $location }).Count -or -not @(& $value $restriction 'values').Count) { $locationRestriction = $(if ($reasonCode) { $reasonCode } else { 'restricted' }) }
                }
                elseif ((& $text $restriction 'type') -eq 'Zone') {
                    foreach ($z in @(& $value (& $value $restriction 'restrictionInfo') 'zones')) { if ($z) { $restrictedZones.Add([string]$z) } }
                }
            }
            $available = @($offered | Where-Object { $restrictedZones -notcontains $_ })
            $missing = @($zones | Where-Object { $available -notcontains $_ })

            # Quota for vCPUs x -NodeCount: the family's and the region's.
            $needed = $vCpus * $NodeCount
            $familyUsage = if ($family -and $usage.Contains($family.ToLowerInvariant())) { $usage[$family.ToLowerInvariant()] } else { $null }
            $familyFree = if ($familyUsage) { $familyUsage.Limit - $familyUsage.Current } else { $null }
            $regionalFree = if ($regional) { $regional.Limit - $regional.Current } else { $null }

            $reasons = [System.Collections.Generic.List[string]]::new()
            $status = 'Available'
            $isRestricted = $null -ne $locationRestriction
            if ($isRestricted) { $status = 'Restricted'; $reasons.Add("not offered to this subscription in $location ($locationRestriction)") }
            if ($Service -eq 'Aks' -and $vCpus -lt 2) {
                if ($status -eq 'Available') { $status = 'NotSupported' }
                $reasons.Add('AKS needs at least 2 vCPUs per node')
            }
            if (-not $isRestricted -and $zones.Count -and $missing.Count) {
                if ($status -eq 'Available') { $status = $(if ($missing.Count -eq $zones.Count) { 'ZoneUnavailable' } else { 'Partial' }) }
                $why = if (-not $offered.Count) { 'offered in no availability zone here' } else { "not in zone(s) $($missing -join ', ')$(if (@($missing | Where-Object { $restrictedZones -contains $_ }).Count) { ' (restricted for this subscription)' })" }
                $reasons.Add($why)
            }
            if (-not $isRestricted -and $needed) {
                $short = @(
                    if ($null -ne $familyFree -and $familyFree -lt $needed) { "family quota: $familyFree of $($familyUsage.Limit) vCPUs free, $needed needed" }
                    if ($null -ne $regionalFree -and $regionalFree -lt $needed) { "regional quota: $regionalFree of $($regional.Limit) vCPUs free, $needed needed" }
                )
                if ($short.Count) {
                    if ($status -eq 'Available') { $status = 'NoQuota' }
                    foreach ($line in $short) { $reasons.Add($line) }
                }
            }
            $notes = [System.Collections.Generic.List[string]]::new()
            if ($Service -eq 'Aks' -and $vCpus -ge 2) {
                if ($memory -lt 4) { $notes.Add('user node pools only: system node pools need 4 GB of memory') }
                if ($seriesName -eq 'B') { $notes.Add('burstable: not recommended for system node pools') }
            }
            $inUse = if ($poolsBySize.Contains($name.ToLowerInvariant())) { $poolsBySize[$name.ToLowerInvariant()] -join ', ' } else { '' }
            $rows.Add([pscustomobject][ordered]@{
                    PSTypeName            = 'AAC.SkuAvailability'
                    Service               = $Service
                    Location              = $location
                    Sku                   = $name
                    Status                = $status
                    Reason                = ($reasons -join '; ')
                    Series                = $seriesName
                    Version               = $(if ($name -match '(?i)_(v\d+)$') { $Matches[1].ToLowerInvariant() } else { '' })
                    Family                = $family
                    vCPUs                 = $vCpus
                    MemoryGB              = $memory
                    Zones                 = ($available -join ',')
                    ZonesMissing          = ($missing -join ',')
                    RestrictedZones       = (@($restrictedZones | Sort-Object -Unique) -join ',')
                    VCpuNeeded            = $needed
                    FamilyVCpuFree        = $familyFree
                    FamilyVCpuLimit       = $(if ($familyUsage) { $familyUsage.Limit } else { $null })
                    RegionalVCpuFree      = $regionalFree
                    Architecture          = $arch
                    EphemeralOSDisk       = (& $flag $caps 'EphemeralOSDiskSupported')
                    AcceleratedNetworking = (& $flag $caps 'AcceleratedNetworkingEnabled')
                    PremiumStorage        = (& $flag $caps 'PremiumIO')
                    Spot                  = (& $flag $caps 'LowPriorityCapable')
                    GPUs                  = $(if ($caps.Contains('GPUs')) { [int]$caps['GPUs'] } else { 0 })
                    MaxDataDisks          = $(if ($caps.Contains('MaxDataDiskCount')) { [int]$caps['MaxDataDiskCount'] } else { 0 })
                    HyperVGenerations     = $(if ($caps.Contains('HyperVGenerations')) { $caps['HyperVGenerations'] } else { '' })
                    Note                  = ($notes -join '; ')
                    InUse                 = $inUse
                    SubscriptionName      = $subscriptionName
                    SubscriptionId        = $subscription
                })
        }

        # --- Quota rows: the region's total and each family these sizes use ---------------------------------------
        $families = @($rows | Where-Object { $_.SubscriptionId -eq $subscription -and $_.Location -eq $location -and $_.Family } | ForEach-Object { $_.Family.ToLowerInvariant() } | Sort-Object -Unique)
        foreach ($key in @(@('cores') + $families)) {
            if (-not $usage.Contains($key)) { continue }
            $entry = $usage[$key]
            $quotas.Add([pscustomobject][ordered]@{
                    PSTypeName       = 'AAC.SkuQuota'
                    SubscriptionName = $subscriptionName
                    Location         = $location
                    Quota            = $(if ($key -eq 'cores') { 'Total Regional vCPUs' } else { $entry.Name })
                    Used             = $entry.Current
                    Limit            = $entry.Limit
                    Free             = $entry.Limit - $entry.Current
                    UsedPercent      = $(if ($entry.Limit -gt 0) { [Math]::Round(100 * $entry.Current / $entry.Limit) } else { $null })
                    Family           = $(if ($key -eq 'cores') { '' } else { $key })
                    SubscriptionId   = $subscription
                })
        }
    }

    $skus = @($rows | Sort-Object -Property @{ Expression = { $statusRank[$_.Status] } }, Location, SubscriptionName, Series, vCPUs, Sku)
    $quotaRows = @($quotas | Sort-Object -Property SubscriptionName, Location, @{ Expression = { if ($_.Family) { 1 } else { 0 } } }, @{ Expression = { if ($null -eq $_.UsedPercent) { -1 } else { $_.UsedPercent } }; Descending = $true }, Quota)

    # --- AKS node pools: their size's status, and room to add a node --------------------------------------
    $pools = @(foreach ($entry in $Pool) {
            $size = & $text $entry 'VmSize'
            $match = @($skus | Where-Object { $_.Sku -eq $size -and (-not $PoolLocation -or $_.Location -eq $PoolLocation.ToLowerInvariant()) } | Select-Object -First 1)
            [pscustomobject][ordered]@{
                PSTypeName     = 'AAC.AksNodePool'
                Pool           = & $text $entry 'Name'
                Mode           = & $text $entry 'Mode'
                VmSize         = $size
                Nodes          = [int](& $value $entry 'Count')
                Zones          = (@(& $value $entry 'Zones' | Where-Object { $_ }) -join ',')
                OsType         = & $text $entry 'OsType'
                SizeStatus     = $(if ($match.Count) { $match[0].Status } else { 'NotChecked' })
                FamilyVCpuFree = $(if ($match.Count) { $match[0].FamilyVCpuFree } else { $null })
                Reason         = $(if ($match.Count) { $match[0].Reason } else { 'this size isn''t in the sizes checked (-Series or -Sku leave it out)' })
            }
        })

    $byStatus = @{}
    foreach ($name in $statusRank.Keys) { $byStatus[$name] = @($skus | Where-Object Status -EQ $name).Count }
    @{
        Skus   = $skus
        Quotas = $quotaRows
        Zones  = @($zoneRows)
        Pools  = $pools
        Notice = $notices.ToArray()
        Stats  = @{
            Sizes           = $skus.Count
            Available       = $byStatus.Available
            Partial         = $byStatus.Partial
            NoQuota         = $byStatus.NoQuota
            ZoneUnavailable = $byStatus.ZoneUnavailable
            NotSupported    = $byStatus.NotSupported
            Restricted      = $byStatus.Restricted
            Usable          = $byStatus.Available + $byStatus.Partial
            Series          = @($skus | Where-Object Series | ForEach-Object Series | Select-Object -Unique).Count
            Locations       = @($Read | ForEach-Object { ([string]$_.Location).ToLowerInvariant() } | Select-Object -Unique).Count
            Subscriptions   = @($Read | ForEach-Object { [string]$_.SubscriptionId } | Select-Object -Unique).Count
            QuotaNearLimit  = @($quotaRows | Where-Object { $null -ne $_.UsedPercent -and $_.UsedPercent -ge 80 }).Count
            ByStatus        = @(foreach ($name in 'Available', 'Partial', 'NoQuota', 'ZoneUnavailable', 'NotSupported', 'Restricted') { if ($byStatus[$name]) { [pscustomobject]@{ Label = $name; Value = $byStatus[$name] } } })
        }
    }
}
