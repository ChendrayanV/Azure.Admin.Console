function ConvertTo-AACNsgAssessment {
    <#
    .SYNOPSIS
        Assesses network security groups: their metadata and associations,
        every rule, their logging, and the risks in them - the model behind
        Get-AACNetworkSecurityGroup.
    .DESCRIPTION
        For each NSG:
          - where it is and what it's applied to: subnets (with their VNet and
            prefix) and network interfaces (with their VM, IP and application
            security groups)
          - every rule, custom and default, in priority order: priority,
            direction, access, protocol, sources, source ports, destinations,
            destination ports - application security groups by name
          - its telemetry: diagnostic settings (Log Analytics, storage, event
            hub; which log categories) and flow logs - its own NSG flow log,
            or a virtual network flow log on its VNet, subnet or NIC -
            with retention and Traffic Analytics

        Findings, each with a severity (High, Medium, Low, Info), the check,
        the rule it is about, what was found and what to do:
          Open to the internet    an inbound Allow from *, Internet or
                                  0.0.0.0/0 to every port or to a management
                                  or database port (High), to a wide range
                                  (Medium), or ICMP (Low)
          Open inside the network a custom inbound Allow of everything from
                                  the virtual network (Low: lateral movement)
          Unassociated            on no subnet and no NIC (Medium)
          Subnet and NIC conflict a NIC with its own NSG in a subnet with an
                                  NSG: both are evaluated, and where one
                                  allows what the other denies the traffic is
                                  blocked (Medium). Probed with the ports the
                                  two NSGs' Allow rules open, from the
                                  internet and from the virtual network,
                                  first matching rule by priority - as Azure
                                  evaluates them
          Shadowed rule           a rule an earlier (higher-priority) rule
                                  fully covers, so it never applies (Low)
          No flow logs            applied to something, but no flow log on it
                                  - neither an NSG flow log nor a virtual
                                  network flow log on its VNet, subnet or
                                  NIC (Medium), or a disabled one
          Flow log retention      kept for fewer than 90 days (Low)
          Traffic Analytics off   flow logs without Traffic Analytics (Info)
          NSG flow log retiring   covered only by an NSG flow log, which
                                  retires on 30 September 2027 (Info)
          No diagnostic settings  no diagnostic setting (Low)
          Rule limit              more than 800 of the 1,000 rules an NSG can
                                  hold (Info)

        Returns a hashtable: Groups (AAC.NetworkSecurityGroup), Rules
        (AAC.NsgRule), Findings (AAC.NsgFinding) and Stats.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        # Resource Graph rows: id, name, resourceGroup, subscriptionId, location, tags, properties.
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $NetworkSecurityGroup,

        # NICs: id, name, resourceGroup, nsg, vm, subnet, ips, asgs.
        [AllowEmptyCollection()]
        [object[]] $NetworkInterface = @(),

        # Subnets: subnetId, name, vnetId, vnetName, prefix, nsg.
        [AllowEmptyCollection()]
        [object[]] $Subnet = @(),

        # Flow logs: id, name, target, enabled, retentionEnabled, retentionDays,
        # storageId, analytics, workspace, interval, version.
        [AllowEmptyCollection()]
        [object[]] $FlowLog = @(),

        # NSG ID (lower case) -> @{ Status = 'Enabled'|'Disabled'|'Unknown'; Settings = @(...) };
        # $null when diagnostic settings weren't read.
        [hashtable] $Diagnostic,

        [hashtable] $SubscriptionName = @{}
    )

    function Get-Value($Row, [string] $Key) {
        if ($Row -isnot [System.Collections.IDictionary]) { return $null }
        if ($Row.Contains($Key)) { return $Row[$Key] }
        foreach ($name in $Row.Keys) { if ($name -eq $Key) { return $Row[$name] } }
        $null
    }
    function Get-Path($Row, [string[]] $Keys) { $value = $Row; foreach ($key in $Keys) { $value = Get-Value $value $key; if ($null -eq $value) { return $null } }; $value }
    $text = { param($Row, [string] $Key) $value = Get-Value $Row $Key; if ($null -eq $value) { '' } else { [string]$value } }
    $lower = { param($Value) ([string]$Value).ToLowerInvariant() }
    $last = { param([string] $Id) ($Id -split '/')[-1] }

    # --- Ports, addresses, matching ---------------------------------------------------------------
    $range = {
        param([string] $Spec)
        $Spec = $Spec.Trim()
        if ($Spec -in '*', 'Any', '') { return , @(0, 65535) }
        if ($Spec -match '^(\d+)-(\d+)$') { return , @([int]$Matches[1], [int]$Matches[2]) }
        if ($Spec -match '^\d+$') { return , @([int]$Spec, [int]$Spec) }
        , @(0, -1)
    }
    $covers = {
        # Every range of B lies inside some range of A.
        param([string[]] $A, [string[]] $B)
        foreach ($b in $B) {
            $rb = & $range $b
            if (-not @($A | Where-Object { $ra = & $range $_; $ra[0] -le $rb[0] -and $ra[1] -ge $rb[1] }).Count) { return $false }
        }
        $true
    }
    $toNumber = {
        param([string] $Ip)
        if ($Ip -notmatch '^(\d+)\.(\d+)\.(\d+)\.(\d+)$') { return $null }
        [uint32]([uint64]$Matches[1] * 16777216 + [uint64]$Matches[2] * 65536 + [uint64]$Matches[3] * 256 + [uint64]$Matches[4])
    }
    $inCidr = {
        param([string] $Cidr, [string] $Ip)
        $address, $bits = $Cidr -split '/'
        if (-not $bits) { $bits = 32 }
        $net = & $toNumber $address; $point = & $toNumber $Ip
        if ($null -eq $net -or $null -eq $point) { return $false }
        $size = [uint64][Math]::Pow(2, 32 - [int]$bits)
        $start = [uint64]$net - ([uint64]$net % $size)
        ([uint64]$point -ge $start) -and ([uint64]$point -lt $start + $size)
    }
    $anywhere = '^(\*|any|internet|0\.0\.0\.0/0|::/0)$'
    $isPrivate = { param([string] $Prefix) $Prefix -match '^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)' }
    $sensitive = @{ 21 = 'FTP'; 22 = 'SSH'; 23 = 'Telnet'; 135 = 'RPC'; 139 = 'NetBIOS'; 445 = 'SMB'; 1433 = 'SQL Server'; 1434 = 'SQL Browser'; 1521 = 'Oracle'; 2375 = 'Docker'; 2376 = 'Docker'; 3306 = 'MySQL'; 3389 = 'RDP'; 5432 = 'PostgreSQL'; 5900 = 'VNC'; 5985 = 'WinRM'; 5986 = 'WinRM'; 6379 = 'Redis'; 9200 = 'Elasticsearch'; 27017 = 'MongoDB' }

    # --- Lookups ------------------------------------------------------------------------------------
    $nics = @{}
    foreach ($row in $NetworkInterface) { $nics[(& $lower (& $text $row 'id'))] = $row }
    $subnets = @{}
    foreach ($row in $Subnet) { $subnets[(& $lower (& $text $row 'subnetId'))] = $row }
    $flowLogs = @(foreach ($row in $FlowLog) {
            [pscustomobject]@{
                Name = & $text $row 'name'; Id = & $text $row 'id'; Target = & $lower (& $text $row 'target')
                Kind = $(if ((& $lower (& $text $row 'target')) -like '*/networksecuritygroups/*') { 'NSG flow log' } else { 'Virtual network flow log' })
                Enabled = [string](Get-Value $row 'enabled') -eq 'True'; RetentionEnabled = [string](Get-Value $row 'retentionEnabled') -eq 'True'
                RetentionDays = [int](Get-Value $row 'retentionDays'); Storage = & $last (& $text $row 'storageId'); StorageId = & $text $row 'storageId'
                Analytics = [string](Get-Value $row 'analytics') -eq 'True'; Workspace = & $last (& $text $row 'workspace'); Interval = [int](Get-Value $row 'interval')
            }
        })
    $subscriptionLabel = { param([string] $Id) if ($SubscriptionName.Contains($Id)) { $SubscriptionName[$Id] } elseif ($SubscriptionName.Contains((& $lower $Id))) { $SubscriptionName[(& $lower $Id)] } else { $Id } }

    # --- Each NSG: rules first ------------------------------------------------------------------------
    $groups = [System.Collections.Generic.List[object]]::new()
    $allRules = [System.Collections.Generic.List[object]]::new()
    $byId = @{}
    foreach ($row in $NetworkSecurityGroup) {
        $id = & $text $row 'id'
        $key = & $lower $id
        $properties = Get-Value $row 'properties'
        $subscriptionId = & $text $row 'subscriptionId'
        $nsg = [ordered]@{
            PSTypeName = 'AAC.NetworkSecurityGroup'
            Name = & $text $row 'name'; ResourceGroup = & $text $row 'resourceGroup'; SubscriptionName = & $subscriptionLabel $subscriptionId; SubscriptionId = $subscriptionId
            Location = & $text $row 'location'; Id = $id
            Tags = $(if ((Get-Value $row 'tags') -is [System.Collections.IDictionary]) { (@((Get-Value $row 'tags').Keys | Sort-Object | ForEach-Object { "$_=$((Get-Value $row 'tags')[$_])" })) -join '; ' } else { '' })
        }
        $rules = foreach ($set in @(@('securityRules', $false), @('defaultSecurityRules', $true))) {
            foreach ($rule in @(Get-Value $properties $set[0])) {
                if ($null -eq $rule) { continue }
                $r = Get-Value $rule 'properties'
                $list = { param([string] $One, [string] $Many) @(@(Get-Value $r $One) + @(Get-Value $r $Many) | Where-Object { $null -ne $_ -and [string]$_ -ne '' } | ForEach-Object { [string]$_ }) }
                $asgs = { param([string] $Key) @(@(Get-Value $r $Key) | ForEach-Object { & $lower (Get-Value $_ 'id') } | Where-Object { $_ }) }
                $sourceAsgs = & $asgs 'sourceApplicationSecurityGroups'
                $destinationAsgs = & $asgs 'destinationApplicationSecurityGroups'
                $sources = @(& $list 'sourceAddressPrefix' 'sourceAddressPrefixes') + @($sourceAsgs | ForEach-Object { "asg:$(& $last $_)" })
                $destinations = @(& $list 'destinationAddressPrefix' 'destinationAddressPrefixes') + @($destinationAsgs | ForEach-Object { "asg:$(& $last $_)" })
                $ports = @(& $list 'destinationPortRange' 'destinationPortRanges')
                $sourcePorts = @(& $list 'sourcePortRange' 'sourcePortRanges')
                [pscustomobject][ordered]@{
                    PSTypeName = 'AAC.NsgRule'
                    Nsg = $nsg.Name; Name = [string](Get-Value $rule 'name'); Priority = [int](Get-Value $r 'priority')
                    Direction = [string](Get-Value $r 'direction'); Access = [string](Get-Value $r 'access'); Protocol = [string](Get-Value $r 'protocol')
                    Source = $sources -join ', '; SourcePorts = $(if ($sourcePorts) { $sourcePorts -join ', ' } else { '*' })
                    Destination = $destinations -join ', '; DestinationPorts = $(if ($ports) { $ports -join ', ' } else { '*' })
                    IsDefault = [bool]$set[1]; Description = [string](Get-Value $r 'description')
                    Risk = ''; Finding = ''
                    ResourceGroup = $nsg.ResourceGroup; SubscriptionName = $nsg.SubscriptionName; NsgId = $id
                    Sources = $sources; Destinations = $destinations; Ports = $(if ($ports) { $ports } else { @('*') }); SourcePortList = $(if ($sourcePorts) { $sourcePorts } else { @('*') })
                    DestinationAsgIds = $destinationAsgs
                }
            }
        }
        # Custom rules by priority, then the defaults - the order Azure evaluates them.
        $nsg.Rules = @(@($rules) | Sort-Object -Property @{ Expression = { $_.Direction } }, @{ Expression = { $_.IsDefault } }, Priority)
        $nsg.SubnetIds = @(@(Get-Value $properties 'subnets') | ForEach-Object { & $lower (Get-Value $_ 'id') } | Where-Object { $_ })
        $nsg.NicIds = @(@(Get-Value $properties 'networkInterfaces') | ForEach-Object { & $lower (Get-Value $_ 'id') } | Where-Object { $_ })
        $nsg.Findings = [System.Collections.Generic.List[object]]::new()
        $byId[$key] = $nsg
        $groups.Add($nsg)
        foreach ($rule in $nsg.Rules) { $allRules.Add($rule) }
    }

    $addFinding = {
        param($Nsg, [string] $Severity, [string] $Check, [string] $Rule, [string] $Detail, [string] $Advice)
        $Nsg.Findings.Add([pscustomobject][ordered]@{
                PSTypeName = 'AAC.NsgFinding'
                Severity = $Severity; Check = $Check; Nsg = $Nsg.Name; Rule = $Rule; Detail = $Detail; Recommendation = $Advice
                ResourceGroup = $Nsg.ResourceGroup; SubscriptionName = $Nsg.SubscriptionName; NsgId = $Nsg.Id
            })
    }
    $verb = { param([string] $Access) if ($Access -eq 'Deny') { 'denies' } else { 'allows' } }
    $flag = { param($Rule, [string] $Risk, [string] $Finding) if (-not $Rule.Risk -or @{ High = 3; Medium = 2; Low = 1; Info = 0 }[$Risk] -gt @{ High = 3; Medium = 2; Low = 1; Info = 0; '' = -1 }[$Rule.Risk]) { $Rule.Risk = $Risk }; $Rule.Finding = (@($Rule.Finding, $Finding) | Where-Object { $_ }) -join ' ' }

    # Does a rule match a flow? (Azure: the first match by priority decides.)
    $ruleMatches = {
        param($Rule, [string] $Protocol, [string] $From, [int] $Port, [string] $Ip, [string[]] $Asgs)
        if ($Rule.Protocol -notin '*', 'Any' -and $Rule.Protocol -ne $Protocol) { return $false }
        if (-not @($Rule.Ports | Where-Object { $p = & $range $_; $Port -ge $p[0] -and $Port -le $p[1] }).Count) { return $false }
        $fromOk = @($Rule.Sources | Where-Object {
                if ($From -eq 'Internet') { $_ -match $anywhere }
                else { $_ -match '^(\*|any|virtualnetwork)$' -or (& $isPrivate $_) }
            }).Count -gt 0
        if (-not $fromOk) { return $false }
        @($Rule.Destinations | Where-Object {
                $_ -match '^(\*|any|virtualnetwork)$' -or ($_ -like 'asg:*' -and $Asgs -contains ($_ -replace '^asg:', '')) -or ($Ip -and $_ -match '^\d+\.\d+\.\d+\.\d+(/\d+)?$' -and (& $inCidr $_ $Ip))
            }).Count -gt 0
    }
    $decide = {
        param($Nsg, [string] $Protocol, [string] $From, [int] $Port, [string] $Ip, [string[]] $Asgs)
        foreach ($rule in @($Nsg.Rules | Where-Object Direction -EQ 'Inbound')) {
            if (& $ruleMatches $rule $Protocol $From $Port $Ip $Asgs) { return $rule }
        }
        $null
    }

    foreach ($nsg in $groups) {
        $custom = @($nsg.Rules | Where-Object { -not $_.IsDefault })

        # --- Open to the internet / inside the network ----------------------------------------------
        foreach ($rule in @($custom | Where-Object { $_.Direction -eq 'Inbound' -and $_.Access -eq 'Allow' })) {
            $fromInternet = @($rule.Sources | Where-Object { $_ -match $anywhere }).Count -gt 0
            if ($fromInternet) {
                $open = [System.Collections.Generic.List[string]]::new()
                $width = 0
                foreach ($spec in $rule.Ports) {
                    $p = & $range $spec
                    $width += [Math]::Max(0, $p[1] - $p[0] + 1)
                    foreach ($port in @($sensitive.Keys | Sort-Object)) { if ($port -ge $p[0] -and $port -le $p[1] -and -not $open.Contains("$($sensitive[$port]) ($port)")) { $open.Add("$($sensitive[$port]) ($port)") } }
                }
                $source = ($rule.Sources | Where-Object { $_ -match $anywhere } | Select-Object -First 1)
                if ($width -ge 65536) {
                    & $flag $rule 'High' 'Every port is open to the internet.'
                    & $addFinding $nsg 'High' 'Open to the internet' $rule.Name "Allows $($rule.Protocol) on every port from '$source'." 'Allow only the ports the workload serves, from the addresses that need them; reach VMs through Azure Bastion or just-in-time access.'
                }
                elseif ($open.Count) {
                    & $flag $rule 'High' "$($open -join ', ') open to the internet."
                    & $addFinding $nsg 'High' 'Open to the internet' $rule.Name "Allows $($open -join ', ') from '$source'." 'Remove the rule, or limit its source to known addresses; use Azure Bastion or just-in-time VM access for management ports, and private endpoints for databases.'
                }
                elseif ($width -gt 100) {
                    & $flag $rule 'Medium' "$('{0:N0}' -f $width) ports are open to the internet."
                    & $addFinding $nsg 'Medium' 'Open to the internet' $rule.Name "Allows $('{0:N0}' -f $width) ports ($($rule.DestinationPorts)) from '$source'." 'Narrow the port range to what the workload serves.'
                }
                elseif ($rule.Protocol -eq 'Icmp') {
                    & $flag $rule 'Low' 'ICMP (ping) is allowed from the internet.'
                    & $addFinding $nsg 'Low' 'Open to the internet' $rule.Name "Allows ICMP from '$source'." 'Allow ICMP only from the networks that monitor the workload.'
                }
            }
            elseif (@($rule.Sources | Where-Object { $_ -match '^virtualnetwork$' }).Count -and $rule.Protocol -in '*', 'Any' -and @($rule.Ports | Where-Object { $_ -in '*', 'Any', '0-65535' }).Count) {
                & $flag $rule 'Low' 'Allows everything from the whole virtual network.'
                & $addFinding $nsg 'Low' 'Open inside the network' $rule.Name 'Allows every protocol and port from VirtualNetwork, which includes peered and on-premises networks.' 'Allow only the tiers and ports that need to talk to each other (application security groups make this easier), to limit lateral movement.'
            }
        }

        # --- Shadowed rules ---------------------------------------------------------------------------
        foreach ($direction in 'Inbound', 'Outbound') {
            $ordered = @($custom | Where-Object Direction -EQ $direction | Sort-Object Priority)
            for ($j = 1; $j -lt $ordered.Count; $j++) {
                $b = $ordered[$j]
                foreach ($a in @($ordered[0..($j - 1)])) {
                    $protocolOk = $a.Protocol -in '*', 'Any' -or $a.Protocol -eq $b.Protocol
                    $sourceOk = @($a.Sources | Where-Object { $_ -in '*', 'Any' }).Count -or -not @($b.Sources | Where-Object { $_ -notin $a.Sources }).Count
                    $destinationOk = @($a.Destinations | Where-Object { $_ -in '*', 'Any' }).Count -or -not @($b.Destinations | Where-Object { $_ -notin $a.Destinations }).Count
                    if ($protocolOk -and $sourceOk -and $destinationOk -and (& $covers $a.Ports $b.Ports) -and (& $covers $a.SourcePortList $b.SourcePortList)) {
                        $outcome = if ($a.Access -ne $b.Access) { "$(& $verb $a.Access) it" } else { 'already does the same' }
                        & $flag $b 'Low' "Never applies: $($a.Name) ($($a.Priority)) matches it first."
                        & $addFinding $nsg 'Low' 'Shadowed rule' $b.Name "Rule $($b.Name) (priority $($b.Priority)) never applies: $($a.Name) (priority $($a.Priority)) matches the same traffic first and $outcome." 'Remove the rule, or give it a lower priority number than the rule that covers it if it should apply.'
                        break
                    }
                }
            }
        }

        # --- Associations ---------------------------------------------------------------------------------
        $nsg.Subnets = @(foreach ($subnetId in $nsg.SubnetIds) {
                $s = $subnets[$subnetId]
                [pscustomobject]@{ Name = & $last $subnetId; VirtualNetwork = $(if ($s) { & $text $s 'vnetName' } else { ($subnetId -split '/')[-3] }); Prefix = $(if ($s) { & $text $s 'prefix' } else { '' }); Id = $subnetId }
            })
        $nsg.NetworkInterfaces = @(foreach ($nicId in $nsg.NicIds) {
                $n = $nics[$nicId]
                [pscustomobject]@{
                    Name = & $last $nicId; VirtualMachine = $(if ($n) { & $last (& $text $n 'vm') } else { '' })
                    PrivateIp = $(if ($n) { (@(Get-Value $n 'ips') | Where-Object { $_ }) -join ', ' } else { '' })
                    Subnet = $(if ($n) { & $last (& $text $n 'subnet') } else { '' }); Id = $nicId
                }
            })
        $nsg.Associated = ($nsg.Subnets.Count + $nsg.NetworkInterfaces.Count) -gt 0
        # The VMs it protects: through their own NIC, or the subnet their NIC is in.
        $protected = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($nic in $nsg.NetworkInterfaces) { if ($nic.VirtualMachine) { [void]$protected.Add($nic.VirtualMachine) } }
        if ($nsg.SubnetIds.Count) {
            foreach ($n in $nics.Values) {
                $vm = & $text $n 'vm'
                if ($vm -and $nsg.SubnetIds -contains (& $lower (& $text $n 'subnet'))) { [void]$protected.Add((& $last $vm)) }
            }
        }
        $nsg.VirtualMachines = $protected.Count
        if (-not $nsg.Associated) {
            & $addFinding $nsg 'Medium' 'Unassociated' '' 'On no subnet and no network interface: it protects nothing.' 'Associate it with the subnet or NIC it was made for, or delete it.'
        }
        if ($custom.Count -gt 800) {
            & $addFinding $nsg 'Info' 'Rule limit' '' "$($custom.Count) custom rules, of the 1,000 an NSG can hold." 'Consolidate rules with service tags, application security groups and augmented rules (several prefixes and ports per rule).'
        }

        # --- Flow logs ------------------------------------------------------------------------------------
        $vnets = @($nsg.Subnets | ForEach-Object { if ($subnets[$_.Id]) { & $lower (& $text $subnets[$_.Id] 'vnetId') } }) + @($nsg.NetworkInterfaces | ForEach-Object { if ($nics[$_.Id]) { $sid = & $lower (& $text $nics[$_.Id] 'subnet'); if ($subnets[$sid]) { & $lower (& $text $subnets[$sid] 'vnetId') } } })
        $targets = @(@((& $lower $nsg.Id)) + $nsg.SubnetIds + $nsg.NicIds + $vnets | Where-Object { $_ } | Select-Object -Unique)
        $covering = @($flowLogs | Where-Object { $_.Target -in $targets })
        $enabled = @($covering | Where-Object Enabled)
        $nsg.FlowLogs = $covering
        $nsg.FlowLogStatus = if ($enabled | Where-Object Kind -EQ 'Virtual network flow log') { 'Enabled (VNet flow log)' } elseif ($enabled) { 'Enabled (NSG flow log)' } elseif ($covering) { 'Disabled' } else { 'None' }
        $nsg.TrafficAnalytics = [bool]@($enabled | Where-Object Analytics).Count
        $nsg.FlowLogRetention = if ($enabled) { $first = $enabled[0]; if ($first.RetentionEnabled -and $first.RetentionDays -gt 0) { "$($first.RetentionDays) days" } else { 'kept (no retention limit)' } } else { '' }
        if ($nsg.Associated) {
            if (-not $enabled) {
                & $addFinding $nsg 'Medium' 'No flow logs' '' $(if ($covering) { "Its flow log ($($covering[0].Name)) is disabled." } else { 'No flow log covers it: neither an NSG flow log nor a virtual network flow log on its VNet, subnet or NIC.' }) 'Enable a virtual network flow log (Network Watcher) on its virtual network, sent to a storage account and Traffic Analytics: most security baselines require flow logs.'
            }
            else {
                $short = @($enabled | Where-Object { $_.RetentionEnabled -and $_.RetentionDays -gt 0 -and $_.RetentionDays -lt 90 })
                if ($short) { & $addFinding $nsg 'Low' 'Flow log retention' '' "Flow logs are kept for $($short[0].RetentionDays) days ($($short[0].Name))." 'Keep flow logs for at least 90 days, or as long as your policy requires, to investigate incidents.' }
                if (-not $nsg.TrafficAnalytics) { & $addFinding $nsg 'Info' 'Traffic Analytics off' '' 'Flow logs are collected but Traffic Analytics is off.' 'Enable Traffic Analytics on the flow log, with a Log Analytics workspace, for traffic maps, top talkers and malicious IPs.' }
                if (-not @($enabled | Where-Object Kind -EQ 'Virtual network flow log').Count) {
                    & $addFinding $nsg 'Info' 'NSG flow log retiring' '' "Only an NSG flow log covers it ($($enabled[0].Name)); NSG flow logs retire on 30 September 2027." 'Migrate to virtual network flow logs.'
                }
            }
        }

        # --- Diagnostic settings --------------------------------------------------------------------------
        $diag = if ($null -ne $Diagnostic -and $Diagnostic.Contains((& $lower $nsg.Id))) { $Diagnostic[(& $lower $nsg.Id)] } else { $null }
        $nsg.Diagnostics = if ($null -eq $Diagnostic) { 'Not checked' } elseif ($diag) { [string]$diag.Status } else { 'Unknown' }
        $nsg.DiagnosticSettings = @(if ($diag) { $diag.Settings })
        $nsg.LogDestinations = (@($nsg.DiagnosticSettings | ForEach-Object {
                    @($(if ($_.Workspace) { "Log Analytics: $($_.Workspace)" }), $(if ($_.Storage) { "Storage: $($_.Storage)" }), $(if ($_.EventHub) { "Event Hub: $($_.EventHub)" })) | Where-Object { $_ }
                }) | Select-Object -Unique) -join '; '
        if ($nsg.Diagnostics -eq 'Disabled') {
            & $addFinding $nsg 'Low' 'No diagnostic settings' '' 'No diagnostic setting: its events and rule counters aren''t collected.' 'Add a diagnostic setting with the allLogs category group, sent to a Log Analytics workspace (and storage for retention).'
        }
    }

    # --- Subnet and NIC conflicts -------------------------------------------------------------------------
    $conflicts = 0
    foreach ($nicId in @($nics.Keys)) {
        $n = $nics[$nicId]
        $nicNsg = $byId[(& $lower (& $text $n 'nsg'))]
        $subnetRow = $subnets[(& $lower (& $text $n 'subnet'))]
        $subnetNsg = if ($subnetRow) { $byId[(& $lower (& $text $subnetRow 'nsg'))] } else { $null }
        if (-not $nicNsg -or -not $subnetNsg -or $nicNsg -eq $subnetNsg) { continue }
        $ip = @(Get-Value $n 'ips') | Where-Object { $_ } | Select-Object -First 1
        $asgNames = @(@(Get-Value $n 'asgs') | ForEach-Object { & $last $_ })
        # Probe with what either NSG's Allow rules open, from where they open it.
        $probes = @{}
        foreach ($rule in @(@($subnetNsg.Rules) + @($nicNsg.Rules) | Where-Object { -not $_.IsDefault -and $_.Direction -eq 'Inbound' -and $_.Access -eq 'Allow' })) {
            $from = if (@($rule.Sources | Where-Object { $_ -match $anywhere }).Count) { 'Internet' } elseif (@($rule.Sources | Where-Object { $_ -match '^virtualnetwork$' -or (& $isPrivate $_) }).Count) { 'VirtualNetwork' } else { $null }
            if (-not $from) { continue }
            $protocol = if ($rule.Protocol -in 'Tcp', 'Udp') { $rule.Protocol } else { 'Tcp' }
            foreach ($spec in $rule.Ports) {
                $p = & $range $spec
                if ($p[1] -lt $p[0]) { continue }
                # Every port: probe with HTTPS, the port most likely to matter.
                $port = if ($p[0] -eq 0 -and $p[1] -eq 65535) { 443 } else { $p[0] }
                $probes["$from|$protocol|$port"] = @($from, $protocol, $port)
            }
        }
        foreach ($probe in $probes.Values) {
            $atSubnet = & $decide $subnetNsg $probe[1] $probe[0] $probe[2] $ip $asgNames
            $atNic = & $decide $nicNsg $probe[1] $probe[0] $probe[2] $ip $asgNames
            if (-not $atSubnet -or -not $atNic -or $atSubnet.Access -eq $atNic.Access) { continue }
            $flow = "$($probe[0]) -> $($probe[1]) $($probe[2]) to $(& $last $nicId)$(if ($ip) { " ($ip)" })"
            $detail = "$($flow): the subnet NSG $($subnetNsg.Name) $(& $verb $atSubnet.Access) it ($($atSubnet.Name)), the NIC NSG $($nicNsg.Name) $(& $verb $atNic.Access) it ($($atNic.Name)) - so it is blocked."
            $advice = 'Both NSGs must allow the traffic. Keep the rules in one place (the subnet NSG usually), or make the two agree.'
            foreach ($pair in @(@($subnetNsg, $atSubnet), @($nicNsg, $atNic))) {
                & $addFinding $pair[0] 'Medium' 'Subnet and NIC conflict' $pair[1].Name $detail $advice
            }
            $conflicts++
        }
    }

    # --- Roll-up -------------------------------------------------------------------------------------------
    $rank = @{ High = 3; Medium = 2; Low = 1; Info = 0 }
    $objects = foreach ($nsg in $groups) {
        $findings = @($nsg.Findings | Sort-Object -Property @{ Expression = { $rank[$_.Severity] }; Descending = $true }, Check)
        $worst = if ($findings) { $findings[0].Severity } else { '' }
        [pscustomobject][ordered]@{
            PSTypeName        = 'AAC.NetworkSecurityGroup'
            Name              = $nsg.Name
            ResourceGroup     = $nsg.ResourceGroup
            SubscriptionName  = $nsg.SubscriptionName
            SubscriptionId    = $nsg.SubscriptionId
            Location          = $nsg.Location
            Associated        = $nsg.Associated
            SubnetCount       = $nsg.Subnets.Count
            NicCount          = $nsg.NetworkInterfaces.Count
            VirtualMachines   = $nsg.VirtualMachines
            AppliedTo         = (@($nsg.Subnets | ForEach-Object { "$($_.VirtualNetwork)/$($_.Name)" }) + @($nsg.NetworkInterfaces | ForEach-Object { "NIC $($_.Name)$(if ($_.VirtualMachine) { " ($($_.VirtualMachine))" })" })) -join '; '
            InboundRules      = @($nsg.Rules | Where-Object { -not $_.IsDefault -and $_.Direction -eq 'Inbound' }).Count
            OutboundRules     = @($nsg.Rules | Where-Object { -not $_.IsDefault -and $_.Direction -eq 'Outbound' }).Count
            FlowLogs          = $nsg.FlowLogStatus
            FlowLogRetention  = $nsg.FlowLogRetention
            TrafficAnalytics  = $nsg.TrafficAnalytics
            Diagnostics       = $nsg.Diagnostics
            LogDestinations   = $nsg.LogDestinations
            Risk              = $worst
            High              = @($findings | Where-Object Severity -EQ 'High').Count
            Medium            = @($findings | Where-Object Severity -EQ 'Medium').Count
            Low               = @($findings | Where-Object Severity -EQ 'Low').Count
            Info              = @($findings | Where-Object Severity -EQ 'Info').Count
            Findings          = $findings
            Rules             = @($nsg.Rules)
            Subnets           = @($nsg.Subnets)
            NetworkInterfaces = @($nsg.NetworkInterfaces)
            FlowLogDetail     = @($nsg.FlowLogs)
            DiagnosticSettings = @($nsg.DiagnosticSettings)
            Tags              = $nsg.Tags
            Id                = $nsg.Id
        }
    }
    $objects = @($objects | Sort-Object -Property @{ Expression = { if ($_.Risk) { $rank[$_.Risk] } else { -1 } }; Descending = $true }, SubscriptionName, ResourceGroup, Name)
    $findingsAll = @($objects | ForEach-Object { $_.Findings } | Sort-Object -Property @{ Expression = { $rank[$_.Severity] }; Descending = $true }, Nsg, Check)
    @{
        Groups   = $objects
        Rules    = @($allRules)
        Findings = $findingsAll
        Stats    = @{
            Groups           = $objects.Count
            Rules            = @($allRules | Where-Object { -not $_.IsDefault }).Count
            High             = @($findingsAll | Where-Object Severity -EQ 'High').Count
            Medium           = @($findingsAll | Where-Object Severity -EQ 'Medium').Count
            Low              = @($findingsAll | Where-Object Severity -EQ 'Low').Count
            Info             = @($findingsAll | Where-Object Severity -EQ 'Info').Count
            Unassociated     = @($objects | Where-Object { -not $_.Associated }).Count
            WithoutFlowLogs  = @($objects | Where-Object { $_.Associated -and $_.FlowLogs -notlike 'Enabled*' }).Count
            WithoutDiagnostics = @($objects | Where-Object Diagnostics -EQ 'Disabled').Count
            Conflicts        = $conflicts
        }
    }
}
