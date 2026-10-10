function ConvertTo-AACAttackPath {
    <#
    .SYNOPSIS
        Builds the attack paths through an Azure estate - from what the
        Internet can reach, through the identities it runs as, to what those
        identities control or can read - with each path's risk, blast radius
        and what to do; and adds Defender for Cloud's own attack paths.
    .DESCRIPTION
        Entry points:
          VM          a public IP whose NSGs (NIC and subnet, rules in
                      priority order, then Azure's defaults) let the
                      Internet in - a management port (22, 3389, 5985/6),
                      a database port, or any port; a Basic IP with no NSG
                      is open, a Standard one closed
          App         an App Service or Function app open to the public
          Cluster     an AKS cluster with a public API server and no
                      authorized IP ranges
          Data store  a storage account, key vault or database open to the
                      Internet (its own path: data exposure)
        Pivot: the entry's managed identities (system- and user-assigned;
        AKS's kubelet identity too). Reach: their role assignments -
          control  Owner, Contributor, User Access Administrator, Role Based
                   Access Control Administrator, or a custom role with '*'
                   or Microsoft.Authorization write - over a scope
          data     a role with data actions (Storage Blob Data, Key Vault
                   Secrets...), or a key vault access policy with secret,
                   key or certificate permissions
        Blast radius: the resources under each scope controlled (a
        management group: every subscription under it), the data stores
        readable, and - for a VM - the other VMs in its virtual network.

        Risk:
          Critical  an Internet-open entry whose identity controls a
                    subscription, a management group or the tenant
          High      control of a resource group or data access from an open
                    entry; a management port open to the Internet; a
                    storage account allowing anonymous access
          Medium    another port open to the Internet; a data store open to
                    every network; a public AKS API server
          Low       a storage account that accepts every network (keys or
                    tokens still needed)
        Returns @{ Paths (AAC.AttackPath); Stats; Notices }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        # Invoke-AACGraphBatch's result for Get-AACAttackPathQuery: @{ Rows; Errors }.
        [Parameter(Mandatory)]
        [hashtable] $Read,

        # Subscription ID (lower case) -> name.
        [System.Collections.IDictionary] $SubscriptionName = @{},

        # Subscription ID (lower case) -> its management group names (lower case).
        [System.Collections.IDictionary] $SubscriptionChain = @{}
    )

    $rows = { param([string] $Name) @(if ($Read.Rows.Contains($Name)) { $Read.Rows[$Name] | Where-Object { $null -ne $_ } }) }
    $get = { param($Row, [string] $Name) if ($Row -is [System.Collections.IDictionary]) { $Row[$Name] } elseif ($null -ne $Row) { $p = $Row.PSObject.Properties[$Name]; if ($p) { $p.Value } } }
    $lower = { param($Text) ([string]$Text).ToLowerInvariant() }
    $leaf = { param($Id) ([string]$Id).TrimEnd('/') -replace '^.*/', '' }
    $subOf = { param($Id) if ([string]$Id -match '(?i)^/subscriptions/([^/]+)') { $Matches[1].ToLowerInvariant() } else { '' } }
    $subLabel = { param($Id) $s = & $subOf $Id; if ($SubscriptionName.Contains($s)) { [string]$SubscriptionName[$s] } else { $s } }
    $severity = Get-AACSeverityRank

    # --- Ports the Internet can reach -------------------------------------------------------------------------
    # (A plain list and a lookup: an ordered dictionary would read an integer key as a position.)
    $watched = @(22, 3389, 5985, 5986, 1433, 3306, 5432, 6379, 27017, 445, 80, 443)
    $portName = @{ 22 = 'SSH'; 3389 = 'RDP'; 5985 = 'WinRM'; 5986 = 'WinRM'; 1433 = 'SQL Server'; 3306 = 'MySQL'; 5432 = 'PostgreSQL'; 6379 = 'Redis'; 27017 = 'MongoDB'; 445 = 'SMB'; 80 = 'HTTP'; 443 = 'HTTPS' }
    $management = @(22, 3389, 5985, 5986)
    $nsgRules = @{}
    foreach ($nsg in (& $rows 'nsgs')) { $nsgRules[(& $lower (& $get $nsg 'id'))] = @(& $get $nsg 'rules') }
    $fromInternet = {
        param($Rule)
        $p = & $get $Rule 'properties'
        $sources = @(@(& $get $p 'sourceAddressPrefix') + @(& $get $p 'sourceAddressPrefixes') | Where-Object { $_ })
        @($sources | Where-Object { [string]$_ -in '*', 'Internet', '0.0.0.0/0', 'Any', '::/0' }).Count -gt 0
    }
    $coversPort = {
        param($Rule, [int] $Port)
        $p = & $get $Rule 'properties'
        foreach ($range in @(@(& $get $p 'destinationPortRange') + @(& $get $p 'destinationPortRanges') | Where-Object { $_ })) {
            $r = [string]$range
            if ($r -eq '*') { return $true }
            if ($r -match '^(\d+)-(\d+)$' -and $Port -ge [int]$Matches[1] -and $Port -le [int]$Matches[2]) { return $true }
            if ($r -match '^\d+$' -and [int]$r -eq $Port) { return $true }
        }
        $false
    }
    # Is $Port open from the Internet through one NSG? Its inbound rules by priority; the first that matches decides; none: denied (DenyAllInBound).
    $nsgAllows = {
        param([string] $NsgId, [int] $Port)
        $inbound = @($nsgRules[$NsgId] | Where-Object { [string](& $get (& $get $_ 'properties') 'direction') -eq 'Inbound' -and [string](& $get (& $get $_ 'properties') 'protocol') -in '*', 'Tcp', 'TCP' } |
                Sort-Object -Property { [int](& $get (& $get $_ 'properties') 'priority') })
        foreach ($rule in $inbound) {
            if ((& $fromInternet $rule) -and (& $coversPort $rule $Port)) { return [string](& $get (& $get $rule 'properties') 'access') -eq 'Allow' }
        }
        $false
    }
    $subnetNsg = @{}; $subnetVnet = @{}
    foreach ($s in (& $rows 'subnets')) { $id = & $lower (& $get $s 'id'); $subnetNsg[$id] = & $lower (& $get $s 'nsg'); $subnetVnet[$id] = & $lower (& $get $s 'vnet') }
    $publicIpOf = @{}   # ip configuration id -> public IP row
    foreach ($ip in (& $rows 'publicIps')) { $to = & $lower (& $get $ip 'attachedTo'); if ($to) { $publicIpOf[$to] = $ip } }

    # VM -> what the Internet reaches on it, and its virtual network.
    $exposure = @{}
    $vnetOfVm = @{}
    foreach ($nic in (& $rows 'nics')) {
        $vm = & $lower (& $get $nic 'vm')
        if (-not $vm) { continue }
        $nicNsg = & $lower (& $get $nic 'nsg')
        foreach ($config in @(& $get $nic 'ipConfigs')) {
            $configId = & $lower (& $get $config 'id')
            $p = & $get $config 'properties'
            $subnet = & $lower (& $get (& $get $p 'subnet') 'id')
            if ($subnet -and $subnetVnet.Contains($subnet)) { $vnetOfVm[$vm] = $subnetVnet[$subnet] }
            $ip = if ($publicIpOf.Contains($configId)) { $publicIpOf[$configId] } else { $null }
            if (-not $ip) { continue }
            $nsgs = @(@($nicNsg, $(if ($subnetNsg.Contains($subnet)) { $subnetNsg[$subnet] } else { '' })) | Where-Object { $_ })
            $open = [System.Collections.Generic.List[string]]::new()
            if (-not $nsgs.Count) {
                # No NSG: a Basic public IP lets everything in; a Standard one, nothing.
                if ([string](& $get $ip 'sku') -ne 'Standard') { $open.Add('every port (no NSG, Basic public IP)') }
            }
            else {
                foreach ($port in $watched) {
                    if (@($nsgs | Where-Object { & $nsgAllows $_ $port }).Count -eq $nsgs.Count) { $open.Add("$($portName[$port]) $port") }
                }
            }
            if ($open.Count) {
                $exposure[$vm] = @{
                    Ip = [string](& $get $ip 'ip'); Open = $open.ToArray()
                    Management = @($open | Where-Object { $_ -match '\d+$' -and [int]($_ -replace '^.* ', '') -in $management -or $_ -like 'every port*' }).Count -gt 0
                }
            }
        }
    }

    # --- Who can do what: roles and identities ---------------------------------------------------------------------
    $roles = @{}   # role GUID -> @{ Name; Control; Data }
    foreach ($d in (& $rows 'roleDefinitions')) {
        $actions = @(@(& $get $d 'permissions') | ForEach-Object { @(& $get $_ 'actions') } | Where-Object { $_ })
        $dataActions = @(@(& $get $d 'permissions') | ForEach-Object { @(& $get $_ 'dataActions') } | Where-Object { $_ })
        $name = [string](& $get $d 'roleName')
        $roles[(& $leaf (& $get $d 'id')).ToLowerInvariant()] = @{
            Name    = $name
            Control = $name -in 'Owner', 'Contributor', 'User Access Administrator', 'Role Based Access Control Administrator' -or @($actions | Where-Object { $_ -eq '*' -or $_ -like 'Microsoft.Authorization/*' -or $_ -like 'Microsoft.Authorization/roleAssignments/write' }).Count -gt 0
            Data    = $dataActions.Count -gt 0
        }
    }
    $assignmentsOf = @{}
    foreach ($a in (& $rows 'roleAssignments')) {
        $principal = & $lower (& $get $a 'principalId')
        if (-not $assignmentsOf.Contains($principal)) { $assignmentsOf[$principal] = [System.Collections.Generic.List[object]]::new() }
        $role = $roles[(& $leaf (& $get $a 'roleId')).ToLowerInvariant()]
        $assignmentsOf[$principal].Add(@{ Scope = & $lower (& $get $a 'scope'); Role = $(if ($role) { $role.Name } else { & $leaf (& $get $a 'roleId') }); Control = [bool]($role -and $role.Control); Data = [bool]($role -and $role.Data) })
    }
    $identityPrincipal = @{}
    foreach ($i in (& $rows 'identities')) { $identityPrincipal[(& $lower (& $get $i 'id'))] = @{ Name = [string](& $get $i 'name'); PrincipalId = & $lower (& $get $i 'principalId') } }
    $principalsOf = {
        # A resource's identities: @{ Label; PrincipalId }.
        param($Identity, [string] $Extra)
        $list = [System.Collections.Generic.List[object]]::new()
        $system = & $lower (& $get $Identity 'principalId')
        if ($system) { $list.Add(@{ Label = 'system-assigned identity'; PrincipalId = $system }) }
        $user = & $get $Identity 'userAssignedIdentities'
        if ($user -is [System.Collections.IDictionary]) {
            foreach ($key in $user.Keys) {
                $principal = & $lower (& $get $user[$key] 'principalId')
                if (-not $principal -and $identityPrincipal.Contains((& $lower $key))) { $principal = $identityPrincipal[(& $lower $key)].PrincipalId }
                if ($principal) { $list.Add(@{ Label = "user-assigned identity $(& $leaf $key)"; PrincipalId = $principal }) }
            }
        }
        if ($Extra) { $list.Add(@{ Label = 'kubelet identity'; PrincipalId = (& $lower $Extra) }) }
        , $list.ToArray()
    }

    # --- The blast radius of a scope --------------------------------------------------------------------------------------
    $countBySub = @{}; $countByGroup = @{}; $all = 0
    foreach ($c in (& $rows 'counts')) {
        $s = & $lower (& $get $c 'subscriptionId'); $n = [int](& $get $c 'resources'); $all += $n
        $countBySub[$s] = [int]$countBySub[$s] + $n
        $countByGroup["$s/$(& $lower (& $get $c 'resourceGroup'))"] = $n
    }
    $scopeInfo = {
        param([string] $Scope)
        if ($Scope -eq '/' -or $Scope -eq '') { return @{ Kind = 'tenant'; Label = 'the whole tenant (root)'; Count = $all; Broad = $true } }
        if ($Scope -match '^/providers/microsoft.management/managementgroups/([^/]+)$') {
            $mg = $Matches[1]
            $count = 0; foreach ($s in $SubscriptionChain.Keys) { if (@($SubscriptionChain[$s]) -contains $mg) { $count += [int]$countBySub[$s] } }
            return @{ Kind = 'management group'; Label = "management group $mg"; Count = $count; Broad = $true }
        }
        if ($Scope -match '^/subscriptions/([^/]+)$') { $s = $Matches[1]; return @{ Kind = 'subscription'; Label = "subscription $(& $subLabel $Scope)"; Count = [int]$countBySub[$s]; Broad = $true } }
        if ($Scope -match '^/subscriptions/([^/]+)/resourcegroups/([^/]+)$') { return @{ Kind = 'resource group'; Label = "resource group $($Matches[2])"; Count = [int]$countByGroup["$($Matches[1])/$($Matches[2])"]; Broad = $false } }
        @{ Kind = 'resource'; Label = (& $leaf $Scope); Count = 1; Broad = $false }
    }

    # Key vault access policies: object ID -> vaults it can read secrets, keys or certificates of.
    $storeById = @{}
    $vaultReaders = @{}
    foreach ($store in (& $rows 'stores')) {
        $storeById[(& $lower (& $get $store 'id'))] = $store
        foreach ($policy in @(& $get $store 'accessPolicies')) {
            $permissions = & $get $policy 'permissions'
            $reads = @(@(& $get $permissions 'secrets') + @(& $get $permissions 'keys') + @(& $get $permissions 'certificates') | Where-Object { [string]$_ -in 'get', 'list', 'Get', 'List', 'all', 'All', 'decrypt', 'unwrapKey' })
            if ($reads.Count) {
                $object = & $lower (& $get $policy 'objectId')
                if (-not $vaultReaders.Contains($object)) { $vaultReaders[$object] = [System.Collections.Generic.List[string]]::new() }
                $vaultReaders[$object].Add([string](& $get $store 'name'))
            }
        }
    }

    # --- The paths -----------------------------------------------------------------------------------------------------
    $paths = [System.Collections.Generic.List[object]]::new()
    $vmCountByVnet = @{}
    foreach ($vm in $vnetOfVm.Keys) { $vmCountByVnet[$vnetOfVm[$vm]] = [int]$vmCountByVnet[$vnetOfVm[$vm]] + 1 }
    $addPath = {
        param($Entry, [string] $EntryKind, [string] $Exposure, [bool] $Management, $Principals, [int] $Lateral)
        $entryId = & $lower (& $get $Entry 'id')
        $reach = [System.Collections.Generic.List[object]]::new()
        foreach ($principal in @($Principals)) {
            foreach ($a in @(if ($assignmentsOf.Contains($principal.PrincipalId)) { $assignmentsOf[$principal.PrincipalId] })) {
                if (-not ($a.Control -or $a.Data)) { continue }
                $info = & $scopeInfo $a.Scope
                $reach.Add(@{ Identity = $principal.Label; Role = $a.Role; Control = $a.Control; Info = $info })
            }
            foreach ($vault in @(if ($vaultReaders.Contains($principal.PrincipalId)) { $vaultReaders[$principal.PrincipalId] })) {
                $reach.Add(@{ Identity = $principal.Label; Role = 'Key Vault access policy (secrets, keys or certificates)'; Control = $false; Info = @{ Kind = 'resource'; Label = "key vault $vault"; Count = 1; Broad = $false } })
            }
        }
        $controlBroad = @($reach | Where-Object { $_.Control -and $_.Info.Broad })
        $controlNarrow = @($reach | Where-Object { $_.Control -and -not $_.Info.Broad })
        $data = @($reach | Where-Object { -not $_.Control })
        if (-not $reach.Count -and $EntryKind -ne 'VM') { return }   # a public app with no reach beyond itself is its own business
        $risk = if ($controlBroad.Count) { 'Critical' }
        elseif ($controlNarrow.Count -or $data.Count) { 'High' }
        elseif ($Management) { 'High' }
        else { 'Medium' }
        $radius = [int](@($reach | ForEach-Object { $_.Info.Count }) | Measure-Object -Sum).Sum + $Lateral + 1
        $steps = [System.Collections.Generic.List[string]]::new()
        $steps.Add('Internet')
        $steps.Add("$(& $get $Entry 'name') ($Exposure)")
        $top = @($reach | Sort-Object -Property @{ Expression = { if ($_.Control -and $_.Info.Broad) { 0 } elseif ($_.Control) { 1 } else { 2 } } }, @{ Expression = { $_.Info.Count }; Descending = $true } | Select-Object -First 1)
        if ($top.Count) { $steps.Add($top[0].Identity); $steps.Add("$($top[0].Role) on $($top[0].Info.Label)") }
        $targets = @($reach | ForEach-Object { "$($_.Role) on $($_.Info.Label) ($($_.Identity))" } | Select-Object -Unique)
        $category = if ($controlBroad.Count) { 'Internet to subscription control' } elseif ($controlNarrow.Count) { 'Internet to resource group control' } elseif ($data.Count) { 'Internet to data' } elseif ($Management) { 'Management port open to the Internet' } else { 'Port open to the Internet' }
        $remedy = [System.Collections.Generic.List[string]]::new()
        if ($EntryKind -eq 'VM') { $remedy.Add($(if ($Management) { 'Close the management ports to the Internet: Azure Bastion or just-in-time access instead, and no public IP on the VM.' } else { 'Allow only the sources that need it in the NSG, or put the VM behind a load balancer, Application Gateway or Front Door with a WAF.' })) }
        if ($EntryKind -eq 'App') { $remedy.Add('Restrict who can reach the app (access restrictions, a private endpoint, or Front Door with a WAF).') }
        if ($EntryKind -eq 'Cluster') { $remedy.Add('Make the API server private, or set authorized IP ranges.') }
        if ($controlBroad.Count -or $controlNarrow.Count) { $remedy.Add("Least privilege: replace $(@(($controlBroad + $controlNarrow) | ForEach-Object { $_.Role } | Select-Object -Unique) -join ', ') with a role scoped to the resources the workload actually manages.") }
        if ($data.Count) { $remedy.Add('Grant data roles on the one store (or container) the workload needs, read-only where it only reads.') }
        $paths.Add((New-AACFinding -TypeName 'AAC.AttackPath' -Severity $risk -Category $category -Finding "$(& $get $Entry 'name'): $(if ($reach.Count) { "Internet access reaches $($top[0].Role) on $($top[0].Info.Label)" } else { "open to the Internet - $Exposure" })" `
                    -ResourceId $entryId -Subscription (& $subLabel $entryId) -Detail ((@("Open: $Exposure", $(if ($Lateral) { "Lateral: $Lateral other VM(s) in the same virtual network" }), $(if ($targets.Count) { "Reach: $($targets -join '; ')" })) | Where-Object { $_ }) -join '. ') `
                    -Impact "An attacker who compromises it can reach $radius resource(s)$(if ($controlBroad.Count) { ' - and take over the subscription' } elseif ($data.Count) { ' - and read their data' })." `
                    -Remediation ($remedy -join ' ') -Effort $(if ($EntryKind -eq 'VM' -and -not $reach.Count) { 'Low' } elseif ($controlBroad.Count -or $controlNarrow.Count) { 'Medium' } else { 'Low' }) `
                    -Link 'https://learn.microsoft.com/azure/defender-for-cloud/concept-attack-path' -Property ([ordered]@{
                        Source = 'Derived'; EntryKind = $EntryKind; Exposure = $Exposure; Path = ($steps -join ' > '); BlastRadius = $radius; Targets = ($targets -join '; ')
                        Identities = (@($Principals | ForEach-Object { $_.Label }) -join ', ')
                    })))
    }
    foreach ($vm in (& $rows 'vms')) {
        $id = & $lower (& $get $vm 'id')
        if (-not $exposure.Contains($id)) { continue }
        $e = $exposure[$id]
        $lateral = if ($vnetOfVm.Contains($id)) { [Math]::Max(0, [int]$vmCountByVnet[$vnetOfVm[$id]] - 1) } else { 0 }
        & $addPath $vm 'VM' "public IP $($e.Ip): $($e.Open -join ', ')" $e.Management (& $principalsOf (& $get $vm 'identity') '') $lateral
    }
    foreach ($app in (& $rows 'apps')) {
        if ([string](& $get $app 'publicAccess') -eq 'Disabled') { continue }
        & $addPath $app 'App' "public endpoint $(& $get $app 'hostname')" $false (& $principalsOf (& $get $app 'identity') '') 0
    }
    foreach ($cluster in (& $rows 'clusters')) {
        if ((& $get $cluster 'private') -eq $true -or @(& $get $cluster 'ranges' | Where-Object { $_ }).Count) { continue }
        $principals = & $principalsOf (& $get $cluster 'identity') (& $get $cluster 'kubelet')
        $before = $paths.Count
        & $addPath $cluster 'Cluster' 'a public API server with no authorized IP ranges' $false $principals 0
        if ($paths.Count -eq $before) {
            $id = & $lower (& $get $cluster 'id')
            $paths.Add((New-AACFinding -TypeName 'AAC.AttackPath' -Severity 'Medium' -Category 'Public API server' -Finding "$(& $get $cluster 'name'): the Kubernetes API server is open to the Internet" -ResourceId $id -Subscription (& $subLabel $id) `
                        -Detail 'No private cluster, no authorized IP ranges.' -Impact 'Anyone can try credentials or exploits against the cluster''s control plane.' -Remediation 'Make the API server private, or set authorized IP ranges.' -Effort 'Medium' `
                        -Link 'https://learn.microsoft.com/azure/aks/api-server-authorized-ip-ranges' -Property ([ordered]@{ Source = 'Derived'; EntryKind = 'Cluster'; Exposure = 'public API server'; Path = "Internet > $(& $get $cluster 'name') API server"; BlastRadius = 1; Targets = ''; Identities = '' })))
        }
    }
    # Data stores the Internet reaches directly.
    $storeKind = @{ 'microsoft.storage/storageaccounts' = 'storage account'; 'microsoft.keyvault/vaults' = 'key vault'; 'microsoft.sql/servers' = 'SQL server'; 'microsoft.documentdb/databaseaccounts' = 'Cosmos DB account'; 'microsoft.dbforpostgresql/flexibleservers' = 'PostgreSQL server'; 'microsoft.dbformysql/flexibleservers' = 'MySQL server' }
    foreach ($store in (& $rows 'stores')) {
        $id = & $lower (& $get $store 'id'); $type = & $lower (& $get $store 'type'); $kind = $storeKind[$type]
        $public = [string](& $get $store 'publicAccess') -ne 'Disabled'
        $allNetworks = [string](& $get $store 'defaultAction') -ne 'Deny'
        $anonymous = $type -eq 'microsoft.storage/storageaccounts' -and [string](& $get $store 'blobPublic') -ne 'false' -and [string](& $get $store 'blobPublic') -ne 'False'
        if (-not $public) { continue }
        $risk = $null; $why = ''
        if ($anonymous -and $allNetworks) { $risk = 'High'; $why = 'accepts every network and allows anonymous blob access' }
        elseif ($type -eq 'microsoft.storage/storageaccounts' -and $allNetworks) { $risk = 'Low'; $why = 'accepts every network (a key, SAS or token is still needed)' }
        elseif ($type -eq 'microsoft.keyvault/vaults' -and $allNetworks) { $risk = 'Medium'; $why = 'accepts every network' }
        elseif ($type -notin 'microsoft.storage/storageaccounts', 'microsoft.keyvault/vaults') { $risk = 'Medium'; $why = 'has public network access enabled (only its firewall rules stand in the way)' }
        if (-not $risk) { continue }
        $paths.Add((New-AACFinding -TypeName 'AAC.AttackPath' -Severity $risk -Category 'Data store open to the Internet' -Finding "$(& $get $store 'name'): the $kind $why" -ResourceId $id -ResourceType $type -Subscription (& $subLabel $id) `
                    -Detail "Public network access: $(if (& $get $store 'publicAccess') { & $get $store 'publicAccess' } else { 'Enabled' }); default network action: $(if (& $get $store 'defaultAction') { & $get $store 'defaultAction' } else { 'n/a' })" `
                    -Impact "Its data is one stolen credential (or none, with anonymous access) away from anyone on the Internet." `
                    -Remediation "Turn off public network access and use a private endpoint; or allow only the networks that need it$(if ($anonymous) { ', and disallow anonymous blob access' })." -Effort $(if ($anonymous) { 'Low' } else { 'High' }) `
                    -Link 'https://learn.microsoft.com/azure/private-link/private-endpoint-overview' -Property ([ordered]@{ Source = 'Derived'; EntryKind = 'Data store'; Exposure = $why; Path = "Internet > $(& $get $store 'name')"; BlastRadius = 1; Targets = ''; Identities = '' })))
    }

    # --- Defender for Cloud's attack paths ----------------------------------------------------------------------------------
    foreach ($d in (& $rows 'defender')) {
        $p = & $get $d 'properties'
        $level = [string](& $get $p 'riskLevel')
        $risk = if ($level -in 'Critical', 'High', 'Medium', 'Low') { $level } else { 'High' }
        $entities = @(& $get (& $get $p 'graphComponent') 'entities')
        $names = @($entities | ForEach-Object { [string](& $get $_ 'entityName') } | Where-Object { $_ })
        # The resource it starts from: the first entity that is one.
        $target = @($entities | Where-Object { [string](& $get $_ 'entityId') -like '/subscriptions/*/providers/*' } | Select-Object -First 1)
        $paths.Add((New-AACFinding -TypeName 'AAC.AttackPath' -Severity $risk -Category 'Defender for Cloud attack path' -Finding ([string](& $get $p 'displayName')) `
                    -ResourceId $(if ($target.Count) { [string](& $get $target[0] 'entityId') } else { '' }) -Subscription (& $subLabel ("/subscriptions/$(& $get $d 'subscriptionId')")) `
                    -Detail ([string](& $get $p 'description')) -Impact $((@(& $get $p 'riskCategories') | Where-Object { $_ }) -join ', ') `
                    -Remediation $(if (& $get $p 'remediation') { [string](& $get $p 'remediation') } else { 'Fix the recommendations on the path in Defender for Cloud > Attack path analysis.' }) -Effort 'Medium' `
                    -Link 'https://portal.azure.com/#view/Microsoft_Azure_Security/SecurityMenuBlade/~/AttackPathAnalysis' -Property ([ordered]@{
                        Source = 'Defender for Cloud'; EntryKind = ''; Exposure = ''; Path = ($names -join ' > '); BlastRadius = [Math]::Max(1, $entities.Count); Targets = ''; Identities = ''
                    })))
    }

    $notices = [System.Collections.Generic.List[string]]::new()
    foreach ($key in @($Read.Errors.Keys | Sort-Object)) {
        if (-not $Read.Errors[$key]) { continue }
        if ($key -eq 'defender') { $notices.Add("Defender for Cloud's attack paths couldn't be read (they need Defender CSPM): $($Read.Errors[$key]) The paths below are derived from the estate.") }
        else { $notices.Add("The $key couldn't be read: $($Read.Errors[$key]) - paths through them may be missing.") }
    }
    $sorted = @($paths | Sort-Object -Property @{ Expression = { $severity.Rank[$_.Severity] } }, @{ Expression = 'BlastRadius'; Descending = $true }, Resource)
    @{
        Paths   = $sorted
        Notices = $notices.ToArray()
        Stats   = @{
            Paths        = $sorted.Count
            Critical     = @($sorted | Where-Object Severity -EQ 'Critical').Count
            High         = @($sorted | Where-Object Severity -EQ 'High').Count
            ExposedVms   = $exposure.Count
            Management   = @($exposure.Values | Where-Object Management).Count
            ExposedData  = @($sorted | Where-Object Category -EQ 'Data store open to the Internet').Count
            Defender     = @($sorted | Where-Object Source -EQ 'Defender for Cloud').Count
            MaxRadius    = $(if ($sorted.Count) { [int](@($sorted.BlastRadius) | Measure-Object -Maximum).Maximum } else { 0 })
        }
    }
}
