function ConvertTo-AACDependencyGraph {
    <#
    .SYNOPSIS
        Builds the dependency graph of an Azure estate - which resource
        depends on which - and finds its blast radii, single points of
        failure, circular dependencies and most critical services.
    .DESCRIPTION
        Edges (A depends on B):
          in network      a VM, AKS cluster, app (VNet integration) or private
                          endpoint on a virtual network
          disk            a VM on its managed disks
          hosted on       an app on its App Service plan; a SQL database on
                          its server
          balances        a load balancer on the VMs in its backend pools
          routes to       an Application Gateway or Front Door on its
                          backends (by host name or IP)
          private link    a private endpoint on its target
          has a role on   a resource whose managed identity has a role on
                          another (a data dependency: an app reading a
                          storage account, a cluster pulling from a registry)
          calls           Application Insights telemetry: an app calling a
                          resource, or something outside Azure (-Telemetry)
        Peered virtual networks are linked both ways, but not as a
        dependency.

        Blast radius: how many resources depend on a resource, directly or
        through others - what breaks when it goes down.
        Redundancy, from each resource's settings: zones, instance counts,
        SKUs (LRS storage, Basic Redis, a one-instance App Service plan, a
        database without zone redundancy or high availability...). A VM is
        never redundant by itself.
        Single point of failure: not redundant, and depended on - a VM alone
        in a backend pool, a plan with one instance hosting apps, a
        non-redundant data store others use. High when 3 or more resources
        depend on it.
        Circular dependencies: strongly connected components (Tarjan).
        Returns @{ Nodes (AAC.DependencyNode); Edges (AAC.DependencyEdge);
        Findings (AAC.DependencyFinding); Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        # Invoke-AACGraphBatch's result for Get-AACDependencyQuery: @{ Rows; Errors }.
        [Parameter(Mandatory)]
        [hashtable] $Read,

        # AppDependencies summarised: AppRoleName, Target, DependencyType, Calls, Failed.
        [AllowEmptyCollection()]
        [object[]] $Telemetry = @(),

        [System.Collections.IDictionary] $SubscriptionName = @{}
    )

    $rows = { param([string] $Name) @(if ($Read.Rows.Contains($Name)) { $Read.Rows[$Name] | Where-Object { $null -ne $_ } }) }
    $get = { param($Row, [string] $Name) if ($Row -is [System.Collections.IDictionary]) { $Row[$Name] } elseif ($null -ne $Row) { $p = $Row.PSObject.Properties[$Name]; if ($p) { $p.Value } } }
    $lower = { param($Text) ([string]$Text).ToLowerInvariant() }
    $leaf = { param($Id) ([string]$Id).TrimEnd('/') -replace '^.*/', '' }
    $typeOf = { param($Id) if ([string]$Id -match '(?i)/providers/(.+)/[^/]+$') { ($Matches[1] -replace '/[^/]+/(?=[^/]+$)', '/').ToLowerInvariant() } else { '' } }
    $vnetOf = { param($SubnetId) ((& $lower $SubnetId) -replace '/subnets/.*$', '') }
    $resourceOf = { param($Scope) if ((& $lower $Scope) -match '^(/subscriptions/[^/]+/resourcegroups/[^/]+/providers/[^/]+/[^/]+/[^/]+)') { $Matches[1] } else { '' } }
    $subOf = { param($Id) if ([string]$Id -match '(?i)^/subscriptions/([^/]+)') { $s = $Matches[1].ToLowerInvariant(); if ($SubscriptionName.Contains($s)) { [string]$SubscriptionName[$s] } else { $s } } else { '' } }
    $severity = Get-AACSeverityRank

    # --- Known resources, with what makes them redundant -------------------------------------------------------
    $known = @{}
    $register = {
        param($Row, $Redundant, [string] $Why)
        $id = & $lower (& $get $Row 'id')
        $known[$id] = @{ Id = $id; Name = [string](& $get $Row 'name'); Type = [string](& $get $Row 'type'); ResourceGroup = [string](& $get $Row 'resourceGroup'); Redundant = $Redundant; Why = $Why; External = $false }
    }
    $hostTo = @{}
    $ipTo = @{}
    foreach ($v in (& $rows 'vms')) { & $register $v $false 'A single VM: one instance' }
    foreach ($v in (& $rows 'vnets')) { & $register $v $true '' }
    foreach ($b in (& $rows 'balancers')) {
        $type = [string](& $get $b 'type')
        $redundant = if ($type -eq 'microsoft.network/loadbalancers') { $true } else { [int](& $get $b 'capacity') -ge 2 -or $null -ne (& $get $b 'autoscale') -or @(& $get $b 'zones').Count -ge 2 }
        & $register $b $redundant $(if ($redundant) { '' } else { 'One instance, no autoscale, no zones' })
    }
    foreach ($p in (& $rows 'profiles')) { & $register $p $true '' }
    foreach ($w in (& $rows 'web')) { & $register $w $true ''; foreach ($h in @(& $get $w 'hosts')) { if ($h) { $hostTo[(& $lower $h)] = & $lower (& $get $w 'id') } } }
    foreach ($p in (& $rows 'plans')) {
        $redundant = [int](& $get $p 'capacity') -ge 2 -or (& $get $p 'zoneRedundant') -eq $true -or [string](& $get $p 'tier') -in 'Dynamic', 'FlexConsumption'
        & $register $p $redundant $(if ($redundant) { '' } else { "One instance ($(& $get $p 'tier')), not zone redundant" })
    }
    foreach ($e in (& $rows 'endpoints')) { & $register $e $true '' }
    foreach ($c in (& $rows 'clusters')) {
        $pools = @(& $get $c 'pools')
        $redundant = @($pools | Where-Object { [int](& $get $_ 'count') -ge 2 -and @(& $get $_ 'availabilityZones').Count -ge 2 }).Count -gt 0
        & $register $c $redundant $(if ($redundant) { '' } else { 'No node pool with 2 or more nodes across zones' })
    }
    foreach ($d in (& $rows 'data')) {
        $type = [string](& $get $d 'type'); $sku = [string](& $get $d 'sku'); $why = ''
        $redundant = switch ($type) {
            'microsoft.storage/storageaccounts' { $sku -notmatch 'LRS$' -or $sku -match 'ZRS$'; if ($sku -match '_LRS$') { $why = "$($sku): one datacenter" } }
            'microsoft.sql/servers/databases' { (& $get $d 'zoneRedundant') -eq $true; if ((& $get $d 'zoneRedundant') -ne $true) { $why = 'Not zone redundant' } }
            'microsoft.cache/redis' { $sku -ne 'Basic'; if ($sku -eq 'Basic') { $why = 'Basic: one node, no replica' } }
            'microsoft.documentdb/databaseaccounts' { @(& $get $d 'locations').Count -ge 2 -or @(@(& $get $d 'locations') | Where-Object { (& $get $_ 'isZoneRedundant') -eq $true }).Count; if (-not (@(& $get $d 'locations').Count -ge 2)) { $why = 'One region' } }
            { $_ -in 'microsoft.dbforpostgresql/flexibleservers', 'microsoft.dbformysql/flexibleservers' } { [string](& $get $d 'ha') -in 'ZoneRedundant', 'SameZone'; if ([string](& $get $d 'ha') -notin 'ZoneRedundant', 'SameZone') { $why = 'No high availability' } }
            default { $true }
        }
        & $register $d ([bool]@($redundant)[-1]) $why
        $h = [string](& $get $d 'host')
        if ($h) { $hostTo[$h] = & $lower (& $get $d 'id') }
    }
    $nodeFor = {
        # A resource referenced but not read (a disk, a resource out of scope): a node from its ID.
        param([string] $Id, [string] $ExternalName)
        if ($ExternalName) { $key = "external:$ExternalName"; if (-not $known.Contains($key)) { $known[$key] = @{ Id = $key; Name = $ExternalName; Type = 'external'; ResourceGroup = ''; Redundant = $null; Why = ''; External = $true } }; return $key }
        $key = & $lower $Id
        if (-not $known.Contains($key)) { $known[$key] = @{ Id = $key; Name = (& $leaf $key); Type = (& $typeOf $key); ResourceGroup = $(if ($key -match '/resourcegroups/([^/]+)') { $Matches[1] } else { '' }); Redundant = $null; Why = ''; External = $false } }
        $key
    }

    # --- Edges ------------------------------------------------------------------------------------------------
    $edges = [System.Collections.Generic.List[object]]::new()
    $edgeSeen = [System.Collections.Generic.HashSet[string]]::new()
    $link = {
        param([string] $From, [string] $To, [string] $Relation, [string] $Detail = '', [bool] $Depends = $true)
        if (-not $From -or -not $To -or $From -eq $To) { return }
        $f = & $nodeFor $From ''; $t = if ($To.StartsWith('external:')) { $To } else { & $nodeFor $To '' }
        if ($edgeSeen.Add("$f|$t|$Relation")) { $edges.Add(@{ From = $f; To = $t; Relation = $Relation; Detail = $Detail; Depends = $Depends }) }
    }
    $vmOfNic = @{}
    foreach ($n in (& $rows 'nics')) {
        $vm = & $lower (& $get $n 'vm'); $nic = & $lower (& $get $n 'id')
        if ($vm) { $vmOfNic[$nic] = $vm }
        foreach ($config in @(& $get $n 'ipConfigs')) {
            $p = & $get $config 'properties'
            $subnet = & $lower (& $get (& $get $p 'subnet') 'id')
            if ($vm -and $subnet) { & $link $vm (& $vnetOf $subnet) 'in network' }
            $ip = [string](& $get $p 'privateIPAddress')
            if ($vm -and $ip) { $ipTo[$ip] = $vm }
        }
    }
    foreach ($v in (& $rows 'vms')) {
        $id = & $lower (& $get $v 'id')
        & $link $id (& $get $v 'osDisk') 'disk'
        foreach ($d in @(& $get $v 'dataDisks')) { & $link $id (& $get (& $get $d 'managedDisk') 'id') 'disk' }
    }
    foreach ($v in (& $rows 'vnets')) {
        foreach ($peer in @(& $get $v 'peerings')) { $remote = & $get (& $get (& $get $peer 'properties') 'remoteVirtualNetwork') 'id'; if ($remote) { & $link (& $get $v 'id') $remote 'peered' '' $false } }
    }
    $poolSize = @{}   # member -> the smallest pool it's in
    foreach ($b in (& $rows 'balancers')) {
        $id = & $lower (& $get $b 'id')
        foreach ($pool in @(& $get $b 'pools')) {
            $pp = & $get $pool 'properties'
            $members = @(@(
                foreach ($c in @(& $get $pp 'backendIPConfigurations')) { $nic = (& $lower (& $get $c 'id')) -replace '/ipconfigurations/.*$', ''; if ($vmOfNic.Contains($nic)) { $vmOfNic[$nic] } }
                foreach ($a in @(& $get $pp 'backendAddresses')) {
                    $fqdn = & $lower (& $get $a 'fqdn'); $ip = [string](& $get $a 'ipAddress')
                    if ($fqdn -and $hostTo.Contains($fqdn)) { $hostTo[$fqdn] } elseif ($ip -and $ipTo.Contains($ip)) { $ipTo[$ip] } elseif ($fqdn) { "external:$fqdn" }
                }
            ) | Select-Object -Unique)
            foreach ($m in $members) {
                if ($m.StartsWith('external:')) { $null = & $nodeFor '' ($m -replace '^external:', '') }
                & $link $id $m $(if ([string](& $get $b 'type') -eq 'microsoft.network/loadbalancers') { 'balances' } else { 'routes to' }) "pool $(& $get $pool 'name')"
                if (-not $poolSize.Contains($m) -or $poolSize[$m] -gt $members.Count) { $poolSize[$m] = $members.Count }
            }
        }
    }
    foreach ($group in @(& $rows 'origins' | Group-Object -Property { & $lower (& $get $_ 'profile') })) {
        $targets = @(@(foreach ($o in $group.Group) { $h = & $lower (& $get $o 'host'); if ($hostTo.Contains($h)) { $hostTo[$h] } elseif ($h) { $null = & $nodeFor '' $h; "external:$h" } }) | Select-Object -Unique)
        foreach ($t in $targets) { & $link $group.Name $t 'routes to' 'Front Door origin'; if (-not $poolSize.Contains($t) -or $poolSize[$t] -gt $targets.Count) { $poolSize[$t] = $targets.Count } }
    }
    foreach ($w in (& $rows 'web')) {
        $id = & $lower (& $get $w 'id')
        & $link $id (& $get $w 'plan') 'hosted on'
        if (& $get $w 'subnet') { & $link $id (& $vnetOf (& $get $w 'subnet')) 'in network' 'VNet integration' }
    }
    foreach ($e in (& $rows 'endpoints')) {
        $id = & $lower (& $get $e 'id')
        if (& $get $e 'subnet') { & $link $id (& $vnetOf (& $get $e 'subnet')) 'in network' }
        foreach ($l in @(& $get $e 'links')) { $target = & $get (& $get $l 'properties') 'privateLinkServiceId'; if ($target) { & $link $id $target 'private link' } }
    }
    foreach ($c in (& $rows 'clusters')) {
        foreach ($subnet in @(@(& $get $c 'pools') | ForEach-Object { & $get $_ 'vnetSubnetID' } | Where-Object { $_ } | Select-Object -Unique)) { & $link (& $get $c 'id') (& $vnetOf $subnet) 'in network' 'node pools' }
    }
    foreach ($d in (& $rows 'data')) { if ([string](& $get $d 'type') -eq 'microsoft.sql/servers/databases') { & $link (& $get $d 'id') ((& $lower (& $get $d 'id')) -replace '/databases/[^/]+$', '') 'hosted on' } }

    # Managed identities: their holders depend on what their roles reach.
    $principalHolder = @{}
    $userIdentity = @{}
    foreach ($i in (& $rows 'identities')) { $userIdentity[(& $lower (& $get $i 'id'))] = & $lower (& $get $i 'principalId') }
    foreach ($holder in @(& $rows 'vms') + @(& $rows 'web') + @(& $rows 'clusters')) {
        $id = & $lower (& $get $holder 'id')
        $identity = & $get $holder 'identity'
        $system = & $lower (& $get $identity 'principalId'); if ($system) { $principalHolder[$system] = $id }
        $user = & $get $identity 'userAssignedIdentities'
        if ($user -is [System.Collections.IDictionary]) { foreach ($k in $user.Keys) { $principal = & $lower (& $get $user[$k] 'principalId'); if (-not $principal -and $userIdentity.Contains((& $lower $k))) { $principal = $userIdentity[(& $lower $k)] }; if ($principal) { $principalHolder[$principal] = $id } } }
        $kubelet = & $lower (& $get $holder 'kubelet'); if ($kubelet) { $principalHolder[$kubelet] = $id }
    }
    foreach ($r in (& $rows 'roles')) {
        $principal = & $lower (& $get $r 'principalId')
        if (-not $principalHolder.Contains($principal)) { continue }
        # The resource the role is on: the scope itself when it's a resource read, else the nearest one above it.
        $target = & $lower (& $get $r 'scope')
        while ($target -and -not $known.Contains($target) -and $target -match '/providers/[^/]+/[^/]+/[^/]+/.+') { $target = $target -replace '/[^/]+/[^/]+$', '' }
        if (-not $known.Contains($target)) { $target = & $resourceOf (& $get $r 'scope') }
        if ($target) { & $link $principalHolder[$principal] $target 'has a role on' }
    }
    # Telemetry: who calls whom.
    $appByName = @{}
    foreach ($w in (& $rows 'web')) { $appByName[(& $lower (& $get $w 'name'))] = & $lower (& $get $w 'id') }
    foreach ($t in $Telemetry) {
        $from = $appByName[(& $lower (& $get $t 'AppRoleName'))]
        if (-not $from) { $from = & $nodeFor '' "app $(& $get $t 'AppRoleName')" }
        $target = (& $lower (& $get $t 'Target')) -replace '\s*\|.*$', '' -replace ':\d+$', ''
        if (-not $target) { continue }
        $to = if ($hostTo.Contains($target)) { $hostTo[$target] } else { $match = @($hostTo.Keys | Where-Object { $target.EndsWith($_) -or $_.EndsWith($target) } | Select-Object -First 1); if ($match.Count) { $hostTo[$match[0]] } else { & $nodeFor '' $target } }
        $calls = [long](& $get $t 'Calls'); $failed = [long](& $get $t 'Failed')
        & $link $from $to 'calls' ('{0:N0} call(s), {1:N0}% failed ({2})' -f $calls, $(if ($calls) { $failed / $calls * 100 } else { 0 }), (& $get $t 'DependencyType'))
    }

    # --- Analysis -------------------------------------------------------------------------------------------------
    $out = @{}; $in = @{}
    foreach ($id in $known.Keys) { $out[$id] = [System.Collections.Generic.List[string]]::new(); $in[$id] = [System.Collections.Generic.List[string]]::new() }
    foreach ($e in @($edges | Where-Object Depends)) { $out[$e.From].Add($e.To); $in[$e.To].Add($e.From) }
    $used = [System.Collections.Generic.HashSet[string]]::new([string[]]@(@($edges | ForEach-Object { $_.From; $_.To }) | Select-Object -Unique))
    $radius = @{}
    foreach ($id in $used) {
        $seen = [System.Collections.Generic.HashSet[string]]::new()
        $queue = [System.Collections.Generic.Queue[string]]::new(); $queue.Enqueue($id)
        while ($queue.Count) { $current = $queue.Dequeue(); foreach ($dependent in $in[$current]) { if ($dependent -ne $id -and $seen.Add($dependent)) { $queue.Enqueue($dependent) } } }
        $radius[$id] = $seen.Count
    }
    # Circular dependencies: Tarjan's strongly connected components.
    $index = @{}; $low = @{}; $onStack = [System.Collections.Generic.HashSet[string]]::new(); $stack = [System.Collections.Generic.Stack[string]]::new(); $counter = 0
    $cycles = [System.Collections.Generic.List[object]]::new()
    $connect = {
        param([string] $V)
        $index[$V] = $counter; $low[$V] = $counter; Set-Variable -Name counter -Scope 1 -Value ($counter + 1)
        $stack.Push($V); [void]$onStack.Add($V)
        foreach ($w in $out[$V]) {
            if (-not $index.Contains($w)) { & $connect $w; $low[$V] = [Math]::Min($low[$V], $low[$w]) }
            elseif ($onStack.Contains($w)) { $low[$V] = [Math]::Min($low[$V], $index[$w]) }
        }
        if ($low[$V] -eq $index[$V]) {
            $component = [System.Collections.Generic.List[string]]::new()
            do { $w = $stack.Pop(); [void]$onStack.Remove($w); $component.Add($w) } while ($w -ne $V)
            if ($component.Count -gt 1) { $cycles.Add($component.ToArray()) }
        }
    }
    foreach ($id in $used) { if (-not $index.Contains($id)) { & $connect $id } }

    $findings = [System.Collections.Generic.List[object]]::new()
    $nameOf = { param($Id) $known[$Id].Name }
    $spof = [System.Collections.Generic.HashSet[string]]::new()
    $remedy = @{
        'microsoft.compute/virtualmachines'         = 'Run two or more instances across availability zones (a scale set, or VMs behind the load balancer), so one can fail.'
        'microsoft.web/serverfarms'                  = 'Scale the plan to 2+ instances (3 for zone redundancy) and turn on zone redundancy (Premium v3).'
        'microsoft.storage/storageaccounts'          = 'Move to zone-redundant storage (ZRS, or GZRS for a regional copy as well).'
        'microsoft.sql/servers/databases'            = 'Turn on zone redundancy, and a failover group to another region for disaster recovery.'
        'microsoft.cache/redis'                      = 'Use Standard or Premium (a replica), zone redundant.'
        'microsoft.documentdb/databaseaccounts'      = 'Add a second region (and service-managed failover), or zone redundancy.'
        'microsoft.dbforpostgresql/flexibleservers'  = 'Turn on zone-redundant high availability.'
        'microsoft.dbformysql/flexibleservers'       = 'Turn on zone-redundant high availability.'
        'microsoft.network/applicationgateways'      = 'Run 2+ instances (autoscale with a minimum of 2) across zones.'
        'microsoft.containerservice/managedclusters' = 'Use node pools of 2+ nodes spread across availability zones.'
    }
    foreach ($id in $used) {
        $node = $known[$id]
        if ($node.Redundant -ne $false -or $radius[$id] -lt 1) { continue }
        # A VM matters on its own when it's the only backend of a pool or Front Door, or something calls it directly.
        if ($node.Type -eq 'microsoft.compute/virtualmachines') {
            $alone = $poolSize.Contains($id) -and $poolSize[$id] -eq 1
            $called = @($edges | Where-Object { $_.To -eq $id -and $_.Relation -eq 'calls' }).Count -gt 0
            if (-not ($alone -or $called)) { continue }
        }
        [void]$spof.Add($id)
        $dependents = @($in[$id] | ForEach-Object { & $nameOf $_ } | Select-Object -Unique)
        $findings.Add((New-AACFinding -TypeName 'AAC.DependencyFinding' -Severity $(if ($radius[$id] -ge 3) { 'High' } else { 'Medium' }) -Category 'Single point of failure' -Finding "$($node.Name): $($radius[$id]) resource(s) depend on it, and it isn't redundant" `
                    -ResourceId $(if ($node.External) { '' } else { $id }) -Resource $node.Name -ResourceType $node.Type -Subscription (& $subOf $id) -Detail "$($node.Why). Directly depended on by: $($dependents -join ', ')" `
                    -Impact "If it fails, $($radius[$id]) resource(s) fail or degrade with it." -Remediation $(if ($remedy.Contains($node.Type)) { $remedy[$node.Type] } else { 'Make it redundant, or give its dependents a fallback.' }) -Effort 'Medium' `
                    -Link 'https://learn.microsoft.com/azure/well-architected/reliability/redundancy' -Property ([ordered]@{ BlastRadius = $radius[$id] })))
    }
    foreach ($cycle in $cycles) {
        $names = @($cycle | ForEach-Object { & $nameOf $_ })
        $findings.Add((New-AACFinding -TypeName 'AAC.DependencyFinding' -Severity 'Medium' -Category 'Circular dependency' -Finding "$($names -join ' > ') > $($names[0])" -Resource $names[0] -ResourceId $(if ($cycle[0].StartsWith('external:')) { '' } else { $cycle[0] }) `
                    -Detail "$($cycle.Count) resources depend on each other." -Impact 'None of them can start or recover before the others: an outage of one can hold all of them down.' `
                    -Remediation 'Break the loop: make one direction asynchronous (a queue), cache the call, or add a circuit breaker so each can start alone.' -Effort 'High' -Link 'https://learn.microsoft.com/azure/architecture/patterns/circuit-breaker' -Property ([ordered]@{ BlastRadius = $cycle.Count })))
    }
    foreach ($id in @($used | Where-Object { $radius[$_] -ge 2 -and -not $spof.Contains($_) } | Sort-Object -Property @{ Expression = { $radius[$_] }; Descending = $true } | Select-Object -First 5)) {
        $node = $known[$id]
        $findings.Add((New-AACFinding -TypeName 'AAC.DependencyFinding' -Severity 'Info' -Category 'Critical service' -Finding "$($node.Name): $($radius[$id]) resource(s) depend on it" -ResourceId $(if ($node.External) { '' } else { $id }) -Resource $node.Name -ResourceType $node.Type -Subscription (& $subOf $id) `
                    -Detail $(if ($node.Redundant -eq $true) { 'Redundant.' } elseif ($node.Redundant -eq $false) { "Not redundant: $($node.Why)." } else { 'Redundancy unknown.' }) -Impact 'One of the services the most others rely on.' `
                    -Remediation 'Monitor it closely (alerts on availability and latency), and check its dependents fail gracefully (timeouts, retries, circuit breakers).' -Effort 'Low' -Property ([ordered]@{ BlastRadius = $radius[$id] })))
    }

    $nodes = @(foreach ($id in $used) {
            $node = $known[$id]
            [pscustomobject][ordered]@{
                PSTypeName = 'AAC.DependencyNode'; Resource = $node.Name; Type = $node.Type; ResourceGroup = $node.ResourceGroup; Subscription = (& $subOf $id)
                DependsOn = @($out[$id]).Count; Dependents = @($in[$id]).Count; BlastRadius = $radius[$id]
                Redundant = $(if ($node.Redundant -eq $true) { 'Yes' } elseif ($node.Redundant -eq $false) { 'No' } else { '' }); SinglePointOfFailure = $(if ($spof.Contains($id)) { 'Yes' } else { 'No' })
                DependsOnList = (@($out[$id] | ForEach-Object { & $nameOf $_ }) -join ', '); DependentsList = (@($in[$id] | ForEach-Object { & $nameOf $_ }) -join ', ')
                ResourceId = $(if ($node.External) { '' } else { $id })
            }
        }) | Sort-Object -Property @{ Expression = 'BlastRadius'; Descending = $true }, Resource
    $edgeRows = @($edges | ForEach-Object { [pscustomobject][ordered]@{ PSTypeName = 'AAC.DependencyEdge'; From = (& $nameOf $_.From); Relation = $_.Relation; To = (& $nameOf $_.To); Detail = $_.Detail; FromId = $_.From; ToId = $_.To } })
    $sortedFindings = @($findings | Sort-Object -Property @{ Expression = { $severity.Rank[$_.Severity] } }, @{ Expression = 'BlastRadius'; Descending = $true }, Resource)
    @{
        Nodes    = @($nodes)
        Edges    = $edgeRows
        Findings = $sortedFindings
        Stats    = @{
            Nodes     = @($nodes).Count
            Edges     = $edgeRows.Count
            Spof      = $spof.Count
            Cycles    = $cycles.Count
            MaxRadius = $(if (@($nodes).Count) { [int](@($nodes | ForEach-Object { $_.BlastRadius }) | Measure-Object -Maximum).Maximum } else { 0 })
            External  = @($known.Values | Where-Object { $_.External -and $used.Contains($_.Id) }).Count
        }
    }
}
