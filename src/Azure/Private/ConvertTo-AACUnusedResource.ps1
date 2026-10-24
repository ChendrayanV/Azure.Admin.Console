function ConvertTo-AACUnusedResource {
    <#
    .SYNOPSIS
        Builds Get-AACUnusedResource's list (AAC.UnusedResource) from the
        Resource Graph rows of Get-AACUnusedResourceQuery: each resource
        that is attached to nothing, serves nothing or is switched off -
        whether it is still billed, since when, and what to do.
    .DESCRIPTION
        No Azure calls. -Read is Invoke-AACGraphBatch's result; -Cost maps a
        resource ID (lower case) to @{ Cost; Currency } (last month), when
        it was read. Rows of subscriptions not in -SubscriptionName are left
        out.

        Severity follows what keeping it costs: High for what is billed
        heavily while it does nothing (a stopped but not deallocated VM, an
        App Service plan, Application Gateway, SQL elastic pool or DDoS
        plan with nothing on it); Medium for what is billed by the hour or
        the GB (Premium and large disks, Standard public IPs, NAT gateways,
        Standard load balancers, Front Door WAF policies, large snapshots);
        Low for clutter that costs little or nothing but hides what matters.

        Returns @{ Items; Notices; Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Read,

        [hashtable] $SubscriptionName = @{},

        [ValidateRange(1, 3650)]
        [int] $SnapshotDays = 90,

        [hashtable] $Cost = @{},

        [datetime] $Now = [datetime]::UtcNow
    )

    $value = { param($Row, [string] $Key) if ($Row -is [System.Collections.IDictionary] -and $Row.Contains($Key)) { $Row[$Key] } }
    $text = { param($Row, [string] $Key) $v = & $value $Row $Key; if ($null -eq $v) { '' } else { [string]$v } }
    $rowsOf = { param([string] $Name) @(if ($Read.Rows -and $Read.Rows.Contains($Name)) { $Read.Rows[$Name] | Where-Object { $null -ne $_ } }) }
    $inScope = { param($Row) $s = (& $text $Row 'subscriptionId').ToLowerInvariant(); $s -and $SubscriptionName.Contains($s) }
    $date = {
        param([string] $Value)
        $d = [datetime]::MinValue
        if ($Value -and [datetime]::TryParse($Value, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$d)) { $d } else { $null }
    }
    $count = { param($Pool) @(@(& $value $Pool 'properties') | ForEach-Object { @(& $value $_ 'backendIPConfigurations') + @(& $value $_ 'loadBalancerBackendAddresses') + @(& $value $_ 'backendAddresses') } | Where-Object { $null -ne $_ }).Count }
    $docs = 'https://learn.microsoft.com/azure'
    $items = [System.Collections.Generic.List[object]]::new()
    $add = {
        param($Row, [string] $Severity, [string] $Category, [string] $Finding, [string] $Billed, [string] $Detail, [string] $Remediation, [string] $Link, $Since = $null, [string] $Sku = '')
        $id = & $text $Row 'id'
        $subscription = (& $text $Row 'subscriptionId').ToLowerInvariant()
        $spend = if ($id -and $Cost.Contains($id)) { $Cost[$id] } else { $null }
        $items.Add((New-AACFinding -TypeName 'AAC.UnusedResource' -Severity $Severity -Category $Category -Finding $Finding -ResourceId $id -Resource (& $text $Row 'name') -ResourceType (& $text $Row 'type') -ResourceGroup (& $text $Row 'resourceGroup') `
                    -Subscription $(if ($SubscriptionName.Contains($subscription)) { $SubscriptionName[$subscription] } else { $subscription }) -Detail $Detail -Remediation $Remediation -Effort 'Low' -Link $Link `
                    -Impact $(switch ($Billed) { 'Yes' { 'You pay for it while it does nothing.' } 'Partly' { 'Part of it is still billed.' } default { 'Little or no cost, but it clutters the estate and hides what matters.' } }) `
                    -Property ([ordered]@{
                        Billed         = $Billed
                        Sku            = $Sku
                        Location       = & $text $Row 'location'
                        Since          = $Since
                        AgeDays        = $(if ($Since -and $Since -le $Now) { [int][Math]::Floor(($Now - $Since).TotalDays) } else { $null })
                        MonthlyCost    = $(if ($spend) { [Math]::Round([double]$spend.Cost, 2) } else { $null })
                        Currency       = $(if ($spend) { [string]$spend.Currency } else { '' })
                        SubscriptionId = $subscription
                    })))
    }
    $days = { param($When) if ($When) { " ($([int][Math]::Floor(($Now - $When).TotalDays)) day(s))" } else { '' } }

    foreach ($row in (& $rowsOf 'disks' | Where-Object { & $inScope $_ })) {
        $sku = & $text $row 'sku'; $size = [int](& $value $row 'sizeGb')
        $since = & $date (& $text $row 'detached'); if (-not $since) { $since = & $date (& $text $row 'created') }
        & $add $row $(if ($sku -match 'Premium|Ultra' -or $size -ge 512) { 'Medium' } else { 'Low' }) 'Unattached disk' 'Managed disk attached to no VM' 'Yes' "$sku, $size GiB, unattached since $(if ($since) { $since.ToString('yyyy-MM-dd') } else { 'an unknown date' })$(& $days $since)." 'Check nobody needs it (a VM being rebuilt, a disk kept for forensics), take a snapshot if in doubt, then delete it.' "$docs/virtual-machines/disks-find-unattached-portal" $since $sku
    }
    foreach ($row in (& $rowsOf 'nics' | Where-Object { & $inScope $_ })) {
        & $add $row 'Low' 'Unattached network interface' 'NIC attached to no VM, private endpoint or private link service' 'No' 'Left behind when a VM was deleted without its NIC.' 'Delete it; it may hold a private IP address others could use.' "$docs/virtual-network/virtual-network-network-interface"
    }
    foreach ($row in (& $rowsOf 'publicIps' | Where-Object { & $inScope $_ })) {
        $sku = & $text $row 'sku'; $static = (& $text $row 'allocation') -eq 'Static'
        $billed = if ($sku -eq 'Standard' -or $static) { 'Yes' } else { 'No' }
        & $add $row $(if ($billed -eq 'Yes') { 'Medium' } else { 'Low' }) 'Unassociated public IP' 'Public IP address associated with nothing' $billed "$sku SKU, $(& $text $row 'allocation')$(if (& $text $row 'ip') { ", $(& $text $row 'ip')" })$(if ($sku -eq 'Basic') { '; Basic public IPs were retired on 30 September 2025' })." 'Delete it unless the address is reserved on purpose (an allow-list somewhere names it).' "$docs/virtual-network/ip-services/public-ip-addresses" $null $sku
    }
    foreach ($row in (& $rowsOf 'nsgs' | Where-Object { & $inScope $_ })) {
        & $add $row 'Low' 'Unassociated NSG' 'Network security group on no subnet or NIC' 'No' 'Its rules filter no traffic - and may mislead whoever reads them.' 'Delete it, or associate it with the subnet it was meant for.' "$docs/virtual-network/network-security-groups-overview"
    }
    foreach ($row in (& $rowsOf 'routeTables' | Where-Object { & $inScope $_ })) {
        & $add $row 'Low' 'Unassociated route table' 'Route table on no subnet' 'No' "$([int](& $value $row 'routes')) route(s) that route nothing." 'Delete it, or associate it with the subnet it was meant for (a forced-tunnelling table left off a subnet is a security gap).' "$docs/virtual-network/manage-route-table"
    }
    foreach ($row in (& $rowsOf 'natGateways' | Where-Object { & $inScope $_ })) {
        & $add $row 'Medium' 'Unused NAT gateway' 'NAT gateway on no subnet' 'Yes' 'Billed by the hour whether or not traffic goes through it.' 'Delete it, or associate it with the subnets that need outbound access.' "$docs/nat-gateway/nat-overview" $null (& $text $row 'sku')
    }
    foreach ($row in (& $rowsOf 'loadBalancers' | Where-Object { & $inScope $_ })) {
        $pools = @(& $value $row 'pools' | Where-Object { $_ })
        if (@($pools | Where-Object { (& $count $_) -gt 0 }).Count) { continue }
        $sku = & $text $row 'sku'
        & $add $row $(if ($sku -eq 'Standard') { 'Medium' } else { 'Low' }) 'Load balancer with no backends' $(if ($pools.Count) { 'Load balancer whose backend pools are all empty' } else { 'Load balancer with no backend pool' }) $(if ($sku -eq 'Standard') { 'Yes' } else { 'No' }) "$sku SKU, $($pools.Count) pool(s), $([int](& $value $row 'rules')) rule(s)$(if ($sku -eq 'Basic') { '; Basic load balancers were retired on 30 September 2025' })." 'Delete it, or add the backends it was meant to balance.' "$docs/load-balancer/load-balancer-overview" $null $sku
    }
    foreach ($row in (& $rowsOf 'appGateways' | Where-Object { & $inScope $_ })) {
        $pools = @(& $value $row 'pools' | Where-Object { $_ })
        $sku = & $text $row 'sku'
        if ((& $text $row 'state') -eq 'Stopped') {
            & $add $row 'Low' 'Stopped Application Gateway' 'Application Gateway stopped' 'No' "$sku; a stopped gateway isn't billed, but its public IP is." 'Delete it if it is no longer needed.' "$docs/application-gateway/overview" $null $sku
            continue
        }
        if (@($pools | Where-Object { (& $count $_) -gt 0 }).Count) { continue }
        & $add $row 'High' 'Application Gateway with no backends' 'Application Gateway whose backend pools are all empty' 'Yes' "$sku, $($pools.Count) pool(s), every one empty: billed by the hour (and capacity unit) to serve nothing." 'Delete it, or stop it (Stop-AzApplicationGateway) until it is needed.' "$docs/application-gateway/overview" $null $sku
    }
    foreach ($row in (& $rowsOf 'plans' | Where-Object { & $inScope $_ })) {
        $tier = & $text $row 'tier'; $sku = & $text $row 'sku'
        $free = $tier -in 'Free', 'Shared', 'Dynamic', 'FlexConsumption'
        & $add $row $(if ($free) { 'Low' } else { 'High' }) 'Empty App Service plan' 'App Service plan with no apps' $(if ($free) { 'No' } else { 'Yes' }) "$tier ($sku)$(if (-not $free) { ", $([Math]::Max(1, [int](& $value $row 'workers'))) instance(s), billed whether or not apps run on it" })." 'Delete it, or move an app onto it.' "$docs/app-service/overview-hosting-plans" $null $sku
    }
    foreach ($row in (& $rowsOf 'availabilitySets' | Where-Object { & $inScope $_ })) {
        & $add $row 'Low' 'Empty availability set' 'Availability set with no VMs' 'No' 'Left behind when its VMs were deleted.' 'Delete it.' "$docs/virtual-machines/availability-set-overview"
    }
    foreach ($row in (& $rowsOf 'vms' | Where-Object { & $inScope $_ })) {
        $size = & $text $row 'size'
        if ((& $text $row 'power') -match 'stopped') {
            & $add $row 'High' 'Stopped VM still billed' 'VM stopped from inside the OS, not deallocated' 'Yes' "$size is still billed for compute: stopping from the OS keeps the host reserved." 'Deallocate it (Stop in the portal, Stop-AzVM, az vm deallocate) - or delete it if it is no longer needed.' "$docs/virtual-machines/states-billing" $null $size
        }
        else {
            & $add $row 'Low' 'Deallocated VM' 'VM deallocated' 'Partly' "$size; compute isn't billed, its disks and any static public IP still are." 'Delete it (and its disks) if it is no longer needed, or start it on a schedule if it is.' "$docs/virtual-machines/states-billing" $null $size
        }
    }
    foreach ($row in (& $rowsOf 'snapshots' | Where-Object { & $inScope $_ })) {
        $created = & $date (& $text $row 'created')
        if (-not $created -or ($Now - $created).TotalDays -lt $SnapshotDays) { continue }
        $size = [int](& $value $row 'sizeGb')
        & $add $row $(if ($size -ge 512) { 'Medium' } else { 'Low' }) 'Old snapshot' "Disk snapshot older than $SnapshotDays days" 'Yes' "$(& $text $row 'sku'), $size GiB$(if ((& $text $row 'incremental') -eq 'True') { ' (incremental)' }), taken $($created.ToString('yyyy-MM-dd'))$(& $days $created)." 'Delete it unless a retention policy needs it; take snapshots with Azure Backup, which expires them for you.' "$docs/virtual-machines/snapshot-copy-managed-disk" $created (& $text $row 'sku')
    }
    foreach ($row in (& $rowsOf 'dnsZones' | Where-Object { & $inScope $_ })) {
        & $add $row 'Low' 'Unlinked private DNS zone' 'Private DNS zone linked to no virtual network' 'Yes' "$([int](& $value $row 'records')) record set(s) no network resolves." 'Link it to the networks that need it, or delete it.' "$docs/dns/private-dns-virtual-network-links"
    }
    foreach ($row in (& $rowsOf 'trafficManager' | Where-Object { & $inScope $_ })) {
        & $add $row 'Low' 'Empty Traffic Manager profile' 'Traffic Manager profile with no endpoints' 'Yes' 'Billed per profile and its DNS queries.' 'Delete it.' "$docs/traffic-manager/traffic-manager-overview"
    }
    foreach ($row in (& $rowsOf 'ipGroups' | Where-Object { & $inScope $_ })) {
        & $add $row 'Low' 'Unused IP group' 'IP group no firewall or firewall policy uses' 'No' 'Its addresses filter nothing.' 'Delete it.' "$docs/firewall/ip-groups"
    }
    foreach ($row in (& $rowsOf 'ddosPlans' | Where-Object { & $inScope $_ })) {
        & $add $row 'High' 'Unused DDoS protection plan' 'DDoS protection plan protecting no virtual network' 'Yes' 'A plan is billed monthly (about USD 2,944 a month) however many networks it protects - here none.' 'Associate it with the networks to protect, or delete it.' "$docs/ddos-protection/ddos-protection-overview"
    }
    foreach ($row in (& $rowsOf 'wafPolicies' | Where-Object { & $inScope $_ })) {
        $frontDoor = (& $text $row 'type') -match 'frontdoor'
        & $add $row $(if ($frontDoor) { 'Medium' } else { 'Low' }) 'Unattached WAF policy' "$(if ($frontDoor) { 'Front Door' } else { 'Application Gateway' }) WAF policy attached to nothing" $(if ($frontDoor) { 'Yes' } else { 'No' }) 'It protects nothing.' 'Attach it to the gateway or Front Door it was meant for, or delete it.' "$docs/web-application-firewall/overview"
    }
    foreach ($row in (& $rowsOf 'certificates' | Where-Object { & $inScope $_ })) {
        $expires = & $date (& $text $row 'expires')
        if (-not $expires -or $expires -gt $Now) { continue }
        & $add $row 'Low' 'Expired certificate' 'App Service certificate expired' 'No' "$(& $text $row 'subject'), expired $($expires.ToString('yyyy-MM-dd'))$(& $days $expires)." 'Delete it (and renew it if a site still needs it).' "$docs/app-service/configure-ssl-certificate" $expires
    }
    $pooled = @{}
    foreach ($row in (& $rowsOf 'pooledDatabases')) { $pooled[(& $text $row 'pool')] = [int](& $value $row 'databases') }
    foreach ($row in (& $rowsOf 'elasticPools' | Where-Object { & $inScope $_ })) {
        if ($pooled[(& $text $row 'id')]) { continue }
        & $add $row 'High' 'Empty SQL elastic pool' 'SQL elastic pool with no databases' 'Yes' "$(& $text $row 'tier') ($(& $text $row 'sku')), billed for its capacity with nothing in it." 'Delete it, or move databases into it.' "$docs/azure-sql/database/elastic-pool-overview" $null (& $text $row 'sku')
    }
    $occupied = @{}
    foreach ($row in (& $rowsOf 'groupCounts')) { $occupied["$(& $text $row 'subscriptionId')|$((& $text $row 'resourceGroup').ToLowerInvariant())"] = [int](& $value $row 'resources') }
    foreach ($row in (& $rowsOf 'groups' | Where-Object { & $inScope $_ })) {
        if ((& $text $row 'managedBy') -or $occupied["$((& $text $row 'subscriptionId').ToLowerInvariant())|$((& $text $row 'name').ToLowerInvariant())"]) { continue }
        & $add $row 'Low' 'Empty resource group' 'Resource group with no resources' 'No' 'Nothing in it; its role assignments, locks and policies still apply to whatever lands there next.' 'Delete it (check for locks and deployments that expect it first).' "$docs/azure-resource-manager/management/manage-resource-groups-portal"
    }

    $rank = (Get-AACSeverityRank).Rank
    $sorted = @($items | Sort-Object -Property @{ Expression = { $rank[$_.Severity] } }, @{ Expression = { if ($null -ne $_.MonthlyCost) { $_.MonthlyCost } else { 0 } }; Descending = $true }, Category, Resource)
    $billed = @($sorted | Where-Object Billed -EQ 'Yes')
    $priced = @($sorted | Where-Object { $null -ne $_.MonthlyCost })
    $monthly = 0.0; foreach ($p in $priced) { $monthly += [double]$p.MonthlyCost }
    @{
        Items   = $sorted
        Notices = @()
        Stats   = @{
            Items      = $sorted.Count
            High       = @($sorted | Where-Object Severity -EQ 'High').Count
            Billed     = $billed.Count
            Categories = @($sorted | Select-Object -ExpandProperty Category -Unique).Count
            Groups     = @($sorted | Where-Object Category -EQ 'Empty resource group').Count
            Monthly    = [Math]::Round($monthly, 2)
            Currency   = [string](@($priced | ForEach-Object { $_.Currency } | Where-Object { $_ }) | Select-Object -First 1)
            Priced     = $priced.Count
        }
    }
}
