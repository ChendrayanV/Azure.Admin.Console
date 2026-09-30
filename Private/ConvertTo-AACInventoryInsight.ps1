function ConvertTo-AACInventoryInsight {
    <#
    .SYNOPSIS
        Builds Get-AACInventory -Insight's view of the estate from the
        Get-AACInsightQuery rows: what it is made of, what is wasted or at
        risk, and how full the networks are.
    .DESCRIPTION
        Breakdowns (label -> count, largest first):
          VmSizes, OsFamilies (Windows, Linux), OsVersions (Windows Server
          2022, Ubuntu 22.04, ...), PowerStates, Hybrid (Azure VMs and Azure
          Arc-enabled servers), StorageReplication (LRS, ZRS, GRS, ...),
          DatabaseTiers (Azure SQL General Purpose, serverless, Cosmos DB, ...)
          and TagCoverage (the share of resources with each required tag -
          -RequiredTag - or else with the most used tags)
        Findings (AAC.InventoryFinding), each with its cost this month when
        the inventory has cost (-Item):
          Unattached disk, Unused public IP, Unused network interface,
          Stopped VM (still billed: stopped, not deallocated), Disconnected
          Arc server, Classic resource (retired), Subnet nearly full (80% of
          its usable IPs or more), Connection down (VPN or ExpressRoute not
          connected, circuit not provisioned), Empty resource group
        Machines (AAC.InventoryMachine), Subnets (AAC.InventorySubnet: used
        and usable IPs - Azure keeps 5 per subnet) and Connections
        (AAC.InventoryConnection).

        Returns @{ Breakdowns; Findings; Machines; Subnets; Connections;
        Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [hashtable] $Rows = @{},

        # The inventory's items: subscription names, costs, empty resource groups, tags.
        [AllowEmptyCollection()]
        [object[]] $Item = @(),

        [string[]] $RequiredTag = @()
    )

    $value = { param($Object, [string] $Key) if ($Object -is [System.Collections.IDictionary]) { if ($Object.Contains($Key)) { $Object[$Key] } } else { Get-AACPropertyValue -InputObject $Object -Name $Key } }
    $text = { param($Object, [string] $Key) $v = & $value $Object $Key; if ($null -eq $v) { '' } else { [string]$v } }
    $rowsOf = { param([string] $Name) @(if ($Rows.Contains($Name)) { $Rows[$Name] | Where-Object { $null -ne $_ } }) }
    $breakdown = {
        param([object[]] $Labels)
        @($Labels | Where-Object { $_ } | Group-Object | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, Name | ForEach-Object { [pscustomobject]@{ Label = $_.Name; Value = $_.Count } })
    }
    $names = @{}
    $byId = @{}
    foreach ($entry in $Item) {
        if ($entry.Level -eq 'Subscription') { $names[[string]$entry.SubscriptionId] = [string]$entry.Name }
        if ($entry.Id) { $byId[([string]$entry.Id).ToLowerInvariant()] = $entry }
    }
    $subscriptionOf = { param($Row) $id = (& $text $Row 'subscriptionId').ToLowerInvariant(); if ($names.Contains($id)) { $names[$id] } else { $id } }
    $findings = [System.Collections.Generic.List[object]]::new()
    $finding = {
        param([string] $Kind, [string] $Severity, $Row, [string] $Type, [string] $Detail, [string] $Name)
        $id = (& $text $Row 'id')
        $known = if ($id -and $byId.Contains($id.ToLowerInvariant())) { $byId[$id.ToLowerInvariant()] } else { $null }
        $findings.Add([pscustomobject][ordered]@{
                PSTypeName       = 'AAC.InventoryFinding'
                Finding          = $Kind
                Severity         = $Severity
                Resource         = $(if ($Name) { $Name } else { & $text $Row 'name' })
                Type             = $Type
                ResourceGroup    = & $text $Row 'resourceGroup'
                SubscriptionName = & $subscriptionOf $Row
                Detail           = $Detail
                CostMonthToDate  = $(if ($known -and $null -ne $known.CostMonthToDate -and $known.CostMonthToDate -gt 0) { $known.CostMonthToDate } else { $null })
                Currency         = $(if ($known -and $known.Currency -ne 'mixed') { $known.Currency } else { '' })
                ResourceId       = $id
            })
    }

    # --- Machines: size, OS, power, Azure or Arc -----------------------------------------------------------
    $osLabel = {
        param([string] $OsType, [string] $OsName, [string] $OsVersion, [string] $Offer, [string] $Sku)
        if ($OsName -match '(?i)windows') {
            if ($OsName -match '(?i)(Windows Server \d{4}(?: R2)?|Windows 1[01])') { return $Matches[1] }
            return $OsName.Trim()
        }
        if ($OsName) {
            $distro = (Get-Culture).TextInfo.ToTitleCase($OsName.Trim().ToLowerInvariant()) -replace '^Rhel', 'RHEL' -replace '^Sles', 'SLES'
            $release = if ($OsVersion -match '^(\d+(?:\.\d+)?)') { " $($Matches[1])" } else { '' }
            return "$distro$release"
        }
        if ($Offer -match '(?i)^windows') { return $(if ($Sku -match '(\d{4})') { "Windows Server $($Matches[1])" } else { 'Windows' }) }
        if ($Offer -match '(?i)ubuntu') { return $(if ($Sku -match '(\d{2})[_.](\d{2})') { "Ubuntu $($Matches[1]).$($Matches[2])" } else { 'Ubuntu' }) }
        if ($Offer -match '(?i)^rhel') { return $(if ($Sku -match '^(\d+)') { "RHEL $($Matches[1])" } else { 'RHEL' }) }
        if ($Offer) { return "$Offer $Sku".Trim() }
        if ($OsType) { return $OsType }
        'Unknown'
    }
    $powerLabel = @{ 'powerstate/running' = 'Running'; 'powerstate/deallocated' = 'Deallocated'; 'powerstate/stopped' = 'Stopped (still billed)'; 'powerstate/starting' = 'Starting'; 'powerstate/stopping' = 'Stopping'; 'powerstate/deallocating' = 'Deallocating' }
    $machines = [System.Collections.Generic.List[object]]::new()
    foreach ($row in (& $rowsOf 'insightVms')) {
        $power = (& $text $row 'power').ToLowerInvariant()
        $os = & $osLabel (& $text $row 'osType') (& $text $row 'osName') (& $text $row 'osVersion') (& $text $row 'offer') (& $text $row 'imageSku')
        $family = if ((& $text $row 'osType')) { & $text $row 'osType' } elseif ($os -match '(?i)windows') { 'Windows' } else { 'Linux' }
        $machines.Add([pscustomobject][ordered]@{
                PSTypeName       = 'AAC.InventoryMachine'
                Name             = & $text $row 'name'
                Kind             = 'Azure VM'
                Size             = & $text $row 'size'
                OsFamily         = $family
                Os               = $os
                PowerState       = $(if ($powerLabel.Contains($power)) { $powerLabel[$power] } else { 'Unknown' })
                Location         = & $text $row 'location'
                ResourceGroup    = & $text $row 'resourceGroup'
                SubscriptionName = & $subscriptionOf $row
                ResourceId       = & $text $row 'id'
            })
        if ($power -eq 'powerstate/stopped') { & $finding 'Stopped VM (still billed)' 'Medium' $row 'microsoft.compute/virtualmachines' 'Stopped from inside the OS, not deallocated: its compute is still billed. Deallocate it (Stop in the portal) if it is not needed.' }
    }
    foreach ($row in (& $rowsOf 'insightArc')) {
        $status = & $text $row 'status'
        $machines.Add([pscustomobject][ordered]@{
                PSTypeName       = 'AAC.InventoryMachine'
                Name             = & $text $row 'name'
                Kind             = 'Azure Arc server'
                Size             = ''
                OsFamily         = $(if ((& $text $row 'osType')) { (Get-Culture).TextInfo.ToTitleCase((& $text $row 'osType').ToLowerInvariant()) } else { '' })
                Os               = & $osLabel (& $text $row 'osType') (& $text $row 'osName') (& $text $row 'osVersion') '' (& $text $row 'osSku')
                PowerState       = $(if ($status) { "Arc: $status" } else { 'Unknown' })
                Location         = & $text $row 'location'
                ResourceGroup    = & $text $row 'resourceGroup'
                SubscriptionName = & $subscriptionOf $row
                ResourceId       = & $text $row 'id'
            })
        if ($status -and $status -ne 'Connected') { & $finding 'Disconnected Arc server' 'Medium' $row 'microsoft.hybridcompute/machines' "Status '$status': Azure no longer manages, monitors or patches it. Reconnect the agent, or remove the machine from Azure Arc." }
    }
    $azureVms = @($machines | Where-Object Kind -EQ 'Azure VM')
    $arc = @($machines | Where-Object Kind -EQ 'Azure Arc server')

    # --- Storage and databases --------------------------------------------------------------------------------
    $replication = @(foreach ($row in (& $rowsOf 'insightStorage')) {
            $sku = & $text $row 'sku'
            if ($sku -match '_(.+)$') { $Matches[1] -replace 'RAGRS', 'RA-GRS' -replace 'RAGZRS', 'RA-GZRS' } elseif ($sku) { $sku } else { 'Unknown' }
        })
    $dbTier = {
        param($Row)
        $type = & $text $Row 'type'; $sku = & $text $Row 'skuName'; $tier = & $text $Row 'skuTier'
        switch -Regex ($type) {
            'microsoft\.sql/servers/databases' {
                $kind = & $text $Row 'kind'
                $serverless = $sku -match '_S_' -or $kind -match 'serverless'
                "Azure SQL - $(if ($tier) { $tier } else { 'unknown tier' })$(if ($serverless) { ' (serverless)' } elseif ($sku -match '^(Basic|S\d|P\d)') { ' (DTU)' } else { '' })"
            }
            'microsoft\.sql/managedinstances' { "SQL Managed Instance - $(if ($tier) { $tier } else { $sku })" }
            'microsoft\.documentdb/databaseaccounts' { "Cosmos DB - $(if ((& $text $Row 'capabilities') -match 'EnableServerless') { 'serverless' } else { 'provisioned throughput' })" }
            'microsoft\.dbforpostgresql/flexibleservers' { "PostgreSQL - $(if ($tier) { $tier } else { $sku })" }
            'microsoft\.dbformysql/flexibleservers' { "MySQL - $(if ($tier) { $tier } else { $sku })" }
            default { $type }
        }
    }
    $databases = @(foreach ($row in (& $rowsOf 'insightDatabases')) { & $dbTier $row })

    # --- Waste: disks, public IPs, NICs -------------------------------------------------------------------------
    $unattachedGb = 0
    foreach ($row in (& $rowsOf 'insightDisks')) {
        if ((& $text $row 'state') -eq 'Unattached' -and -not (& $text $row 'managedBy')) {
            $unattachedGb += [int](& $value $row 'sizeGb')
            & $finding 'Unattached disk' 'Low' $row 'microsoft.compute/disks' "$([int](& $value $row 'sizeGb')) GB $(& $text $row 'sku'), attached to nothing and still billed. Snapshot it if needed, then delete it."
        }
    }
    foreach ($row in (& $rowsOf 'insightPublicIps')) {
        if (-not (& $text $row 'usedBy')) { & $finding 'Unused public IP' 'Low' $row 'microsoft.network/publicipaddresses' "$(& $text $row 'sku') $((& $text $row 'allocation').ToLowerInvariant()) public IP bound to nothing$(if ((& $text $row 'sku') -eq 'Standard' -or (& $text $row 'allocation') -eq 'Static') { ' - billed while it is reserved' }). Delete it if nothing will use it." }
    }
    foreach ($row in (& $rowsOf 'insightNics')) {
        if (-not (& $text $row 'usedBy')) { & $finding 'Unused network interface' 'Low' $row 'microsoft.network/networkinterfaces' 'Attached to no VM or private endpoint - usually left behind by a deleted VM. It holds a private IP; delete it.' }
    }
    foreach ($row in (& $rowsOf 'insightClassic')) {
        & $finding 'Classic resource' 'High' $row (& $text $row 'type') 'A classic (ASM) resource: classic VMs, Cloud Services and storage accounts are retired. Migrate it to Azure Resource Manager.'
    }
    foreach ($entry in @($Item | Where-Object { $_.Level -eq 'ResourceGroup' -and $_.Resources -eq 0 })) {
        $findings.Add([pscustomobject][ordered]@{
                PSTypeName = 'AAC.InventoryFinding'; Finding = 'Empty resource group'; Severity = 'Low'; Resource = $entry.Name; Type = 'microsoft.resources/resourcegroups'
                ResourceGroup = $entry.Name; SubscriptionName = $entry.SubscriptionName; Detail = 'No resources: delete it, unless a deployment or policy is about to use it.'; CostMonthToDate = $null; Currency = ''; ResourceId = $entry.Id
            })
    }

    # --- Subnets: used and usable IPs ----------------------------------------------------------------------------
    $subnets = @(foreach ($row in (& $rowsOf 'insightSubnets')) {
            $prefix = & $text $row 'prefix'
            $usable = if ($prefix -match '^\d+\.\d+\.\d+\.\d+/(\d+)$') { [Math]::Max(0, [Math]::Pow(2, 32 - [int]$Matches[1]) - 5) } else { $null }
            $used = [int](& $value $row 'used')
            $percent = if ($usable) { [Math]::Round(100 * $used / $usable) } else { $null }
            [pscustomobject][ordered]@{
                PSTypeName       = 'AAC.InventorySubnet'
                VirtualNetwork   = & $text $row 'vnet'
                Subnet           = & $text $row 'subnet'
                Prefix           = $prefix
                Usable           = $usable
                Used             = $used
                Free             = $(if ($null -ne $usable) { [Math]::Max(0, $usable - $used) } else { $null })
                UsedPercent      = $percent
                ResourceGroup    = & $text $row 'resourceGroup'
                SubscriptionName = & $subscriptionOf $row
                VirtualNetworkId = & $text $row 'vnetId'
            }
            if ($null -ne $percent -and $percent -ge 80) {
                & $finding 'Subnet nearly full' $(if ($percent -ge 95) { 'High' } else { 'Medium' }) @{ id = (& $text $row 'vnetId'); name = (& $text $row 'vnet'); resourceGroup = (& $text $row 'resourceGroup'); subscriptionId = (& $text $row 'subscriptionId') } 'microsoft.network/virtualnetworks/subnets' "$used of $usable usable IPs in $prefix are in use ($percent%). Scale-outs and new private endpoints will fail when it is full." "$(& $text $row 'vnet') / $(& $text $row 'subnet')"
            }
        })
    $subnets = @($subnets | Sort-Object -Property @{ Expression = { if ($null -eq $_.UsedPercent) { -1 } else { $_.UsedPercent } }; Descending = $true }, VirtualNetwork, Subnet)

    # --- Hybrid connectivity -------------------------------------------------------------------------------------------
    $connections = @(
        foreach ($row in (& $rowsOf 'insightConnections')) {
            $status = & $text $row 'status'
            $kind = switch (& $text $row 'connectionType') { 'ExpressRoute' { 'ExpressRoute connection' } 'IPsec' { 'Site-to-site VPN' } 'Vnet2Vnet' { 'VNet-to-VNet VPN' } default { & $text $row 'connectionType' } }
            [pscustomobject][ordered]@{ PSTypeName = 'AAC.InventoryConnection'; Name = & $text $row 'name'; Kind = $kind; Status = $(if ($status) { $status } else { 'Unknown' }); Detail = "Provisioning: $(& $text $row 'state')"; ResourceGroup = & $text $row 'resourceGroup'; SubscriptionName = & $subscriptionOf $row; ResourceId = & $text $row 'id' }
            if ($status -and $status -ne 'Connected') { & $finding 'Connection down' 'High' $row 'microsoft.network/connections' "$kind is '$status'." }
        }
        foreach ($row in (& $rowsOf 'insightCircuits')) {
            $provider = & $text $row 'providerState'
            [pscustomobject][ordered]@{ PSTypeName = 'AAC.InventoryConnection'; Name = & $text $row 'name'; Kind = 'ExpressRoute circuit'; Status = $(if ($provider -eq 'Provisioned') { 'Provisioned' } elseif ($provider) { $provider } else { 'Unknown' }); Detail = "$(& $text $row 'provider') $([int](& $value $row 'bandwidth')) Mbps; circuit $(& $text $row 'circuitState')"; ResourceGroup = & $text $row 'resourceGroup'; SubscriptionName = & $subscriptionOf $row; ResourceId = & $text $row 'id' }
            if ($provider -and $provider -ne 'Provisioned') { & $finding 'Connection down' 'High' $row 'microsoft.network/expressroutecircuits' "The provider's side of the circuit is '$provider' - traffic can't flow until the provider provisions it." }
        }
    )

    # --- Tag coverage -------------------------------------------------------------------------------------------------
    $resources = @($Item | Where-Object Level -EQ 'Resource')
    $tagsOf = { param([string] $Tags) @(if ($Tags) { $Tags -split '; ' | ForEach-Object { ($_ -split '=', 2)[0] } }) }
    $tagNames = if ($RequiredTag.Count) { @($RequiredTag) } else {
        @($resources | ForEach-Object { & $tagsOf $_.Tags } | Group-Object | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, Name | Select-Object -First 6 | ForEach-Object Name)
    }
    $coverage = @(foreach ($tag in $tagNames) {
            $with = @($resources | Where-Object { (& $tagsOf $_.Tags) -contains $tag }).Count
            [pscustomobject]@{ Label = $tag; Value = $(if ($resources.Count) { [Math]::Round(100 * $with / $resources.Count) } else { 0 }); Resources = $with }
        })
    $tagCompliant = if ($RequiredTag.Count) { @($resources | Where-Object { $have = & $tagsOf $_.Tags; -not @($RequiredTag | Where-Object { $have -notcontains $_ }).Count }).Count } else { $null }

    $severityRank = @{ High = 0; Medium = 1; Low = 2 }
    $allFindings = @($findings | Sort-Object -Property @{ Expression = { $severityRank[$_.Severity] } }, Finding, SubscriptionName, Resource)
    $wasteCost = 0.0
    $wasteCurrencies = @{}
    foreach ($each in $allFindings) { if ($null -ne $each.CostMonthToDate) { $wasteCost += $each.CostMonthToDate; if ($each.Currency) { $wasteCurrencies[$each.Currency] = $true } } }
    @{
        Breakdowns  = [ordered]@{
            VmSizes            = & $breakdown @($azureVms | ForEach-Object Size)
            OsFamilies         = & $breakdown @($machines | ForEach-Object { if ($_.OsFamily) { $_.OsFamily } else { 'Unknown' } })
            OsVersions         = & $breakdown @($machines | ForEach-Object Os)
            PowerStates        = & $breakdown @($azureVms | ForEach-Object PowerState)
            Hybrid             = @(
                if ($azureVms.Count) { [pscustomobject]@{ Label = 'Azure VMs'; Value = $azureVms.Count } }
                $connected = @($arc | Where-Object PowerState -EQ 'Arc: Connected').Count
                if ($connected) { [pscustomobject]@{ Label = 'Arc servers (connected)'; Value = $connected } }
                if ($arc.Count - $connected) { [pscustomobject]@{ Label = 'Arc servers (not connected)'; Value = $arc.Count - $connected } }
            )
            StorageReplication = & $breakdown $replication
            DatabaseTiers      = & $breakdown $databases
            TagCoverage        = $coverage
        }
        Findings    = $allFindings
        Machines    = $machines.ToArray()
        Subnets     = $subnets
        Connections = $connections
        Stats       = @{
            AzureVms         = $azureVms.Count
            ArcServers       = $arc.Count
            Running          = @($azureVms | Where-Object PowerState -EQ 'Running').Count
            Deallocated      = @($azureVms | Where-Object PowerState -EQ 'Deallocated').Count
            StoppedBilled    = @($azureVms | Where-Object PowerState -EQ 'Stopped (still billed)').Count
            UnattachedDisks  = @($allFindings | Where-Object Finding -EQ 'Unattached disk').Count
            UnattachedDiskGb = $unattachedGb
            UnusedPublicIps  = @($allFindings | Where-Object Finding -EQ 'Unused public IP').Count
            UnusedNics       = @($allFindings | Where-Object Finding -EQ 'Unused network interface').Count
            Classic          = @($allFindings | Where-Object Finding -EQ 'Classic resource').Count
            FullSubnets      = @($allFindings | Where-Object Finding -EQ 'Subnet nearly full').Count
            ConnectionsDown  = @($allFindings | Where-Object Finding -EQ 'Connection down').Count
            Findings         = $allFindings.Count
            WasteCost        = $(if ($wasteCurrencies.Count -eq 1) { [Math]::Round($wasteCost, 2) } else { $null })
            WasteCurrency    = $(if ($wasteCurrencies.Count -eq 1) { @($wasteCurrencies.Keys)[0] } else { '' })
            RequiredTags     = @($RequiredTag)
            TagCompliant     = $tagCompliant
            Resources        = $resources.Count
        }
    }
}
