function Write-AACSkuAvailabilityHtml {
    <#
    .SYNOPSIS
        Writes Get-AACSkuAvailability's result as an interactive HTML report:
        tiles and charts that filter tables of the VM sizes, the vCPU quota,
        the zones and the AKS cluster's node pools.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Availability,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Title,

        [System.Collections.IDictionary] $Detail
    )

    $stats = $Availability.Stats
    $statusTones = @{ Available = 'good'; Partial = 'warn'; NoQuota = 'warn'; ZoneUnavailable = 'bad'; NotSupported = 'bad'; Restricted = 'bad'; NotChecked = 'neutral' }
    $skus = @($Availability.Skus)
    $usable = @($skus | Where-Object { $_.Status -eq 'Available' -or $_.Status -eq 'Partial' })

    $tiles = @(
        @{ Value = '{0:N0}' -f $stats.Sizes; Label = 'sizes checked'; Tone = 'info'; Table = 'sizes' }
        @{ Value = '{0:N0}' -f $stats.Available; Label = 'available'; Tone = $(if ($stats.Available) { 'good' } else { 'neutral' }); Table = 'sizes'; Filters = @{ Status = 'Available' } }
        @{ Value = '{0:N0}' -f $stats.Partial; Label = 'in some zones only'; Tone = $(if ($stats.Partial) { 'warn' } else { 'neutral' }); Table = 'sizes'; Filters = @{ Status = 'Partial' } }
        @{ Value = '{0:N0}' -f $stats.NoQuota; Label = 'short of quota'; Tone = $(if ($stats.NoQuota) { 'warn' } else { 'neutral' }); Table = 'sizes'; Filters = @{ Status = 'NoQuota' } }
        @{ Value = '{0:N0}' -f $stats.ZoneUnavailable; Label = 'not in the zones'; Tone = $(if ($stats.ZoneUnavailable) { 'bad' } else { 'neutral' }); Table = 'sizes'; Filters = @{ Status = 'ZoneUnavailable' } }
        @{ Value = '{0:N0}' -f $stats.NotSupported; Label = 'not for AKS'; Tone = $(if ($stats.NotSupported) { 'bad' } else { 'neutral' }); Table = 'sizes'; Filters = @{ Status = 'NotSupported' } }
        @{ Value = '{0:N0}' -f $stats.Restricted; Label = 'restricted for the subscription'; Tone = $(if ($stats.Restricted) { 'bad' } else { 'neutral' }); Table = 'sizes'; Filters = @{ Status = 'Restricted' } }
        @{ Value = '{0:N0}' -f $stats.QuotaNearLimit; Label = 'quotas 80%+ used'; Tone = $(if ($stats.QuotaNearLimit) { 'warn' } else { 'good' }); Table = 'quota' }
    )
    $charts = @(
        @{ Title = 'VM sizes by status'; Kind = 'donut'; CenterLabel = 'sizes'; Table = 'sizes'; Column = 'Status'; Items = @($stats.ByStatus | ForEach-Object { @{ Label = $_.Label; Value = $_.Value; Filter = $_.Label; Tone = $statusTones[$_.Label] } }) }
        @{ Title = 'Usable sizes by series'; Items = @($usable | Where-Object Series | Group-Object Series | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, Name | Select-Object -First 15 | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'sizes'; Column = 'Series'; Tone = 'good' }
        @{ Title = 'vCPU quota used (%)'; Items = @($Availability.Quotas | Where-Object { $null -ne $_.UsedPercent -and $_.Used -gt 0 } | Sort-Object UsedPercent -Descending | Select-Object -First 12 | ForEach-Object { @{ Label = $_.Quota; Value = $_.UsedPercent; Display = "$($_.UsedPercent)% ($($_.Used) of $($_.Limit))"; Tone = $(if ($_.UsedPercent -ge 90) { 'bad' } elseif ($_.UsedPercent -ge 70) { 'warn' } else { 'good' }); Filter = $_.Quota } }); Table = 'quota'; Column = 'Quota'; Wide = $true }
    )
    $tables = @(
        @{
            Id = 'sizes'; Title = 'VM sizes'; Note = 'Usable first. Zones: where the size can run for this subscription (offered, less zone restrictions). Family free: vCPUs left in the family''s quota.'
            Noun = 'sizes'; File = 'vm-sizes'; Rows = $skus; GroupBy = @('Status', 'Series', 'Location', 'SubscriptionName')
            Columns = @(
                @{ Key = 'Sku'; Label = 'Size'; Type = 'mono' }
                @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = $statusTones; Facet = $true }
                @{ Key = 'Reason'; Label = 'Why'; Type = 'wide' }
                @{ Key = 'Series'; Label = 'Series'; Facet = $true }
                @{ Key = 'vCPUs'; Label = 'vCPUs'; Type = 'number'; Format = 'N0'; Facet = $true }
                @{ Key = 'MemoryGB'; Label = 'Memory GB'; Type = 'number'; Format = 'N2' }
                @{ Key = 'Zones'; Label = 'Zones'; Facet = $true }
                @{ Key = 'ZonesMissing'; Label = 'Zones missing'; Facet = $true }
                @{ Key = 'FamilyVCpuFree'; Label = 'Family vCPUs free'; Type = 'number'; Format = 'N0' }
                @{ Key = 'Architecture'; Label = 'Architecture'; Facet = $true }
                @{ Key = 'GPUs'; Label = 'GPUs'; Type = 'number'; Format = 'N0' }
                @{ Key = 'EphemeralOSDisk'; Label = 'Ephemeral OS'; Facet = $true }
                @{ Key = 'AcceleratedNetworking'; Label = 'Accelerated networking'; Facet = $true }
                @{ Key = 'PremiumStorage'; Label = 'Premium storage'; Facet = $true }
                @{ Key = 'Note'; Label = 'Note'; Type = 'wide' }
                @{ Key = 'InUse'; Label = 'Node pools'; Facet = $true }
                @{ Key = 'Location'; Label = 'Region'; Facet = $true }
                @{ Key = 'SubscriptionName'; Label = 'Subscription'; Facet = $true }
                @{ Key = 'Family'; Label = 'Family'; Facet = $true; Hidden = $true }
                @{ Key = 'Version'; Label = 'Version'; Facet = $true; Hidden = $true }
                @{ Key = 'Spot'; Label = 'Spot'; Facet = $true; Hidden = $true }
                @{ Key = 'MaxDataDisks'; Label = 'Data disks'; Type = 'number'; Format = 'N0'; Hidden = $true }
                @{ Key = 'HyperVGenerations'; Label = 'Hyper-V generations'; Facet = $true; Hidden = $true }
                @{ Key = 'RestrictedZones'; Label = 'Restricted zones'; Hidden = $true }
                @{ Key = 'RegionalVCpuFree'; Label = 'Regional vCPUs free'; Type = 'number'; Format = 'N0'; Hidden = $true }
            )
        }
        @{
            Id = 'quota'; Title = 'vCPU quota'; Note = 'The region''s total and each family of the sizes checked.'; Noun = 'quotas'; File = 'vcpu-quota'; Rows = @($Availability.Quotas)
            Columns = @(
                @{ Key = 'Quota'; Label = 'Quota' }
                @{ Key = 'UsedPercent'; Label = 'Used %'; Type = 'number'; Format = 'N0' }
                @{ Key = 'Used'; Label = 'vCPUs used'; Type = 'number'; Format = 'N0' }
                @{ Key = 'Limit'; Label = 'Limit'; Type = 'number'; Format = 'N0' }
                @{ Key = 'Free'; Label = 'Free'; Type = 'number'; Format = 'N0' }
                @{ Key = 'Location'; Label = 'Region'; Facet = $true }
                @{ Key = 'SubscriptionName'; Label = 'Subscription'; Facet = $true }
            )
        }
        if (@($Availability.Zones).Count) {
            @{
                Id = 'zones'; Title = 'Availability zones'; Note = 'Each subscription''s logical zones map to physical zones of its own.'; Noun = 'zones'; File = 'zones'; Rows = @($Availability.Zones)
                Columns = @(
                    @{ Key = 'LogicalZone'; Label = 'Logical zone' }
                    @{ Key = 'PhysicalZone'; Label = 'Physical zone'; Type = 'mono' }
                    @{ Key = 'Location'; Label = 'Region'; Facet = $true }
                    @{ Key = 'SubscriptionName'; Label = 'Subscription'; Facet = $true }
                )
            }
        }
        if (@($Availability.Pools).Count) {
            @{
                Id = 'pools'; Title = 'AKS node pools'; Note = 'The cluster''s pools, with their size''s status in its region now.'; Noun = 'node pools'; File = 'aks-node-pools'; Rows = @($Availability.Pools)
                Columns = @(
                    @{ Key = 'Pool'; Label = 'Pool' }
                    @{ Key = 'Mode'; Label = 'Mode'; Facet = $true }
                    @{ Key = 'VmSize'; Label = 'Size'; Type = 'mono' }
                    @{ Key = 'Nodes'; Label = 'Nodes'; Type = 'number'; Format = 'N0'; Sum = $true }
                    @{ Key = 'Zones'; Label = 'Zones' }
                    @{ Key = 'SizeStatus'; Label = 'Size status'; Type = 'badge'; Tones = $statusTones; Facet = $true }
                    @{ Key = 'FamilyVCpuFree'; Label = 'Family vCPUs free'; Type = 'number'; Format = 'N0' }
                    @{ Key = 'Reason'; Label = 'Why'; Type = 'wide' }
                )
            }
        }
    )
    $notices = @(@($Availability.Notice | Where-Object { $_ }) | ForEach-Object { @{ Tone = 'info'; Text = $_ } })
    $notices += @{ Tone = 'info'; Text = 'Read-only, from Microsoft.Compute SKUs (offered zones and this subscription''s restrictions), vCPU usage and the subscription''s zone mapping. Capacity at deployment time can''t be checked without deploying.' }

    Write-AACHtmlReport -Path $Path -Title $Title -Subtitle 'Which VM sizes can be used, in which zones, within quota - and why not' -Fact $Detail -Tile $tiles -Chart $charts -Table $tables -Notice $notices
}
