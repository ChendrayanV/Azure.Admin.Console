function ConvertTo-AACResourceUtilization {
    <#
    .SYNOPSIS
        Rates how much of each resource is used - from its Azure Monitor
        metrics, hour by hour - and says which are idle, under-used, right
        sized or running hot, which way they're trending, and what to
        resize them to, with the money it would save.
    .DESCRIPTION
        From each resource's hourly metrics: CPU (or its equivalent: RU
        consumption for Cosmos DB) average, 95th percentile and maximum;
        memory 95th percentile (a VM's from its free memory and size); its
        activity summed over the window (transactions, connections, network).
          Idle        CPU 95th percentile under -IdlePercent (5) - or, with
                      no CPU metric, no activity at all
          Under-used  CPU 95th percentile under -LowPercent (30), and memory
                      (when known) under 60%
          Hot         CPU or memory 95th percentile over -HighPercent (80)
          Right sized otherwise; No data when the metrics are empty
        Trend: the second half of the window against the first - Growing
        (over +20%), Shrinking (under -20%) or Stable.
        A VM under-used is offered the size of its family with half the
        vCPUs (if it has the memory used, with 20% to spare), priced from the
        Azure retail prices for its region and OS: the saving a month.
        With -Cost (each resource's monthly cost), every row has its cost,
        the share of it that pays for unused capacity (cost x (1 - average
        use)) - the chargeback - and an estimated saving for the idle (all
        of it) and the under-used (half).
        Returns @{ Rows (AAC.ResourceUtilization); Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        # Resource Graph rows: id, name, type, resourceGroup, subscriptionId, location, size, os, sku.
        [AllowEmptyCollection()] [object[]] $Resource = @(),
        # Resource ID (lower case) -> the metrics response's 'value' (hashtables).
        [hashtable] $Metric = @{},
        # 'location|size' (lower case) -> @{ Cores; MemoryMB }.
        [hashtable] $Size = @{},
        # 'location|size|os' (lower case) -> the price an hour.
        [hashtable] $Price = @{},
        # Resource ID (lower case) -> @{ Cost (a month); Currency }.
        [hashtable] $Cost = @{},
        [System.Collections.IDictionary] $SubscriptionName = @{},
        [int] $IdlePercent = 5,
        [int] $LowPercent = 30,
        [int] $HighPercent = 80
    )

    $get = { param($Row, [string] $Name) if ($Row -is [System.Collections.IDictionary]) { $Row[$Name] } elseif ($null -ne $Row) { $p = $Row.PSObject.Properties[$Name]; if ($p) { $p.Value } } }
    $lower = { param($Text) ([string]$Text).ToLowerInvariant() }
    $round = { param($N) if ($null -eq $N) { $null } else { [Math]::Round([double]$N, 1) } }
    $percentile = { param([double[]] $Values, [double] $P) if (-not $Values.Count) { return $null } $sorted = [double[]]($Values | Sort-Object); $sorted[[Math]::Max(0, [int][Math]::Ceiling($P * $sorted.Count) - 1)] }
    $mean = { param([double[]] $Values) if (-not $Values.Count) { return $null } $t = 0.0; foreach ($v in $Values) { $t += $v }; $t / $Values.Count }
    $subOf = { param($Id) $s = & $lower $Id; if ($s -match '^/subscriptions/([^/]+)') { $s = $Matches[1]; if ($SubscriptionName.Contains($s)) { [string]$SubscriptionName[$s] } else { $s } } else { '' } }
    $definitions = Get-AACUtilizationMetric
    $series = {
        # One metric's hourly points: @{ Average; Maximum; Total } arrays, oldest first.
        param($Values, [string] $Name)
        $m = @($Values | Where-Object { [string](& $get (& $get $_ 'name') 'value') -eq $Name }) | Select-Object -First 1
        $points = @(if ($m) { foreach ($ts in @(& $get $m 'timeseries')) { @(& $get $ts 'data') } })
        @{
            Average = [double[]]@($points | Where-Object { $null -ne (& $get $_ 'average') } | ForEach-Object { [double](& $get $_ 'average') })
            Maximum = [double[]]@($points | Where-Object { $null -ne (& $get $_ 'maximum') } | ForEach-Object { [double](& $get $_ 'maximum') })
            Minimum = [double[]]@($points | Where-Object { $null -ne (& $get $_ 'minimum') } | ForEach-Object { [double](& $get $_ 'minimum') })
            Total   = [double[]]@($points | Where-Object { $null -ne (& $get $_ 'total') } | ForEach-Object { [double](& $get $_ 'total') })
        }
    }
    # The same family with half the vCPUs: Standard_D8s_v5 -> Standard_D4s_v5.
    $smaller = {
        param([string] $SizeName, [string] $Location, $UsedMemoryMB)
        if ($SizeName -notmatch '^(?<prefix>[A-Za-z]+_[A-Za-z]+)(?<cores>\d+)(?<rest>.*)$') { return $null }
        $cores = [int]$Matches['cores']
        if ($cores -lt 2) { return $null }
        $candidate = "$($Matches['prefix'])$([int]($cores / 2))$($Matches['rest'])"
        $spec = $Size["$(& $lower $Location)|$(& $lower $candidate)"]
        if (-not $spec) { return $null }
        if ($null -ne $UsedMemoryMB -and [double]$spec.MemoryMB -lt [double]$UsedMemoryMB * 1.2) { return $null }
        $candidate
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($r in $Resource) {
        $id = & $lower (& $get $r 'id'); $type = & $lower (& $get $r 'type')
        $def = $definitions[$type]
        if (-not $def) { continue }
        $values = if ($Metric.Contains($id)) { $Metric[$id] } else { $null }
        $cpu = if ($def.Cpu -and $values) { & $series $values $def.Cpu } else { $null }
        $cpuAvg = if ($cpu) { & $mean $cpu.Average } else { $null }
        $cpuP95 = if ($cpu) { & $percentile $cpu.Average 0.95 } else { $null }
        $cpuMax = if ($cpu -and $cpu.Maximum.Count) { [double]($cpu.Maximum | Measure-Object -Maximum).Maximum } else { $null }
        $location = & $lower (& $get $r 'location'); $sizeName = [string](& $get $r 'size')
        $memoryMB = $null; $memoryP95 = $null
        if ($def.Memory -and $values) {
            $mem = & $series $values $def.Memory
            if ($def.MemoryKind -eq 'Percent') { $memoryP95 = & $percentile $mem.Average 0.95 }
            elseif ($mem.Average.Count -or $mem.Minimum.Count) {
                $spec = $Size["$location|$(& $lower $sizeName)"]
                if ($spec) {
                    $total = [double]$spec.MemoryMB * 1MB
                    $freeLow = & $percentile $(if ($mem.Minimum.Count) { $mem.Minimum } else { $mem.Average }) 0.05
                    if ($null -ne $freeLow -and $total) { $memoryP95 = [Math]::Max(0, [Math]::Min(100, (1 - $freeLow / $total) * 100)); $memoryMB = $spec.MemoryMB * $memoryP95 / 100 }
                }
            }
        }
        $activity = if ($def.Activity -and $values) { $a = & $series $values $def.Activity; if ($a.Total.Count) { [double]($a.Total | Measure-Object -Sum).Sum } elseif ($a.Average.Count) { [double]($a.Average | Measure-Object -Sum).Sum } else { $null } } else { $null }
        # Trend: the window's second half against its first.
        $trend = 'Stable'; $growth = $null
        $basis = if ($cpu -and $cpu.Average.Count -ge 4) { $cpu.Average } elseif ($def.Activity -and $values) { (& $series $values $def.Activity).Total } else { @() }
        if (@($basis).Count -ge 4) {
            $half = [int][Math]::Floor($basis.Count / 2)
            $first = & $mean ([double[]]$basis[0..($half - 1)]); $second = & $mean ([double[]]$basis[$half..($basis.Count - 1)])
            if ($first -gt 0) { $growth = ($second - $first) / $first * 100; $trend = if ($growth -gt 20) { 'Growing' } elseif ($growth -lt -20) { 'Shrinking' } else { 'Stable' } }
        }
        $status = if (-not $values -or ($null -eq $cpuP95 -and $null -eq $activity)) { 'No data' }
        elseif ($null -ne $cpuP95) {
            if ($cpuP95 -gt $HighPercent -or ($null -ne $memoryP95 -and $memoryP95 -gt $HighPercent)) { 'Hot' }
            elseif ($cpuP95 -lt $IdlePercent -and ($null -eq $activity -or $type -ne 'microsoft.compute/virtualmachines' -or $activity -lt 100MB)) { 'Idle' }
            elseif ($cpuP95 -lt $LowPercent -and ($null -eq $memoryP95 -or $memoryP95 -lt 60)) { 'Under-used' }
            else { 'Right sized' }
        }
        elseif ($activity -eq 0) { 'Idle' }
        else { 'Right sized' }
        # Right-sizing and savings.
        $suggested = $null; $saving = $null; $currency = ''
        $monthly = $null
        if ($Cost.Contains($id)) { $monthly = [double]$Cost[$id].Cost; $currency = [string]$Cost[$id].Currency }
        if ($type -eq 'microsoft.compute/virtualmachines' -and $status -eq 'Under-used' -and $sizeName) {
            $suggested = & $smaller $sizeName $location $memoryMB
            if ($suggested) {
                $os = & $lower (& $get $r 'os')
                $now = $Price["$location|$(& $lower $sizeName)|$os"]; $then = $Price["$location|$(& $lower $suggested)|$os"]
                if ($null -ne $now -and $null -ne $then) { $saving = [Math]::Round(([double]$now - [double]$then) * 730, 2); $currency = 'USD' }
            }
        }
        if ($null -eq $saving -and $null -ne $monthly) { $saving = switch ($status) { 'Idle' { [Math]::Round($monthly, 2) } 'Under-used' { [Math]::Round($monthly / 2, 2) } default { $null } } }
        $unused = if ($null -ne $monthly -and $null -ne $cpuAvg) { [Math]::Round($monthly * (1 - [Math]::Min([double]100, [double]$cpuAvg) / 100), 2) } else { $null }
        $label = $def.Label
        $recommend = switch ($status) {
            'Idle' { "Nothing uses it: delete it, or stop or scale it to zero while it's not needed$(if ($type -eq 'microsoft.compute/virtualmachines') { ' (deallocate it: a VM only stopped is still billed)' })." }
            'Under-used' { "Scale down: $(if ($suggested) { "resize to $suggested" } else { $def.Down })." }
            'Hot' { "Scale up or out before it becomes a bottleneck$(if ($trend -eq 'Growing') { ' - and it''s growing' }): look at what drives the load first." }
            'Right sized' { $(if ($trend -eq 'Growing') { 'Right sized now, but growing: plan for more capacity.' } else { 'Keep: it''s sized for what it does.' }) }
            default { 'No metrics: check it is running, and that its platform metrics are available.' }
        }
        $severity = switch ($status) { 'Idle' { 'Medium' } 'Under-used' { 'Low' } 'Hot' { if ($trend -eq 'Growing') { 'High' } else { 'Medium' } } default { 'Info' } }
        $rows.Add((New-AACFinding -TypeName 'AAC.ResourceUtilization' -Severity $severity -Category $status -Finding "$($label) $(& $get $r 'name'): $($status.ToLowerInvariant())" -ResourceId $id -Resource ([string](& $get $r 'name')) -ResourceType $type `
                    -Subscription (& $subOf $id) -Detail ((@($(if ($null -ne $cpuP95) { 'CPU {0:N0}% (average {1:N0}%, max {2:N0}%)' -f $cpuP95, $cpuAvg, $cpuMax }), $(if ($null -ne $memoryP95) { 'memory {0:N0}%' -f $memoryP95 }), $(if ($null -ne $activity) { "activity $('{0:N0}' -f $activity)" })) | Where-Object { $_ }) -join '; ') `
                    -Impact $(if ($null -ne $saving -and $saving -gt 0) { '{0:N2} {1} a month' -f $saving, $currency } else { '' }) -Remediation $recommend -Effort $(if ($status -in 'Idle', 'Under-used') { 'Low' } elseif ($status -eq 'Hot') { 'Medium' } else { '' }) `
                    -Link 'https://learn.microsoft.com/azure/advisor/advisor-cost-recommendations' -Property ([ordered]@{
                        Kind = $label; Size = $(if ($sizeName) { $sizeName } else { [string](& $get $r 'sku') }); CpuAverage = & $round $cpuAvg; CpuP95 = & $round $cpuP95; CpuMax = & $round $cpuMax; MemoryP95 = & $round $memoryP95
                        Activity = $activity; Trend = $trend; GrowthPercent = & $round $growth; SuggestedSize = $suggested; MonthlyCost = $monthly; UnusedCost = $unused; EstimatedSaving = $saving; Currency = $currency
                    })))
    }
    $order = @{ Idle = 0; 'Under-used' = 1; Hot = 2; 'Right sized' = 3; 'No data' = 4 }
    $sorted = @($rows | Sort-Object -Property @{ Expression = { $order[$_.Category] } }, @{ Expression = { if ($null -ne $_.EstimatedSaving) { [double]$_.EstimatedSaving } else { 0 } }; Descending = $true }, Resource)
    @{
        Rows  = $sorted
        Stats = @{
            Resources  = $sorted.Count
            Idle       = @($sorted | Where-Object Category -EQ 'Idle').Count
            Underused  = @($sorted | Where-Object Category -EQ 'Under-used').Count
            Hot        = @($sorted | Where-Object Category -EQ 'Hot').Count
            Right      = @($sorted | Where-Object Category -EQ 'Right sized').Count
            NoData     = @($sorted | Where-Object Category -EQ 'No data').Count
            Growing    = @($sorted | Where-Object Trend -EQ 'Growing').Count
            Saving     = [Math]::Round([double](@($sorted | ForEach-Object { if ($null -ne $_.EstimatedSaving) { [double]$_.EstimatedSaving } else { 0 } }) | Measure-Object -Sum).Sum, 2)
            UnusedCost = [Math]::Round([double](@($sorted | ForEach-Object { if ($null -ne $_.UnusedCost) { [double]$_.UnusedCost } else { 0 } }) | Measure-Object -Sum).Sum, 2)
            Currencies = @($sorted | ForEach-Object Currency | Where-Object { $_ } | Select-Object -Unique)
            # Savings by currency (retail prices are in USD, billed cost in the billing currency): '146 USD; 100 EUR'.
            SavingText = (@($sorted | Where-Object { $_.EstimatedSaving -gt 0 } | Group-Object Currency | Sort-Object Name | ForEach-Object { '{0:N0} {1}' -f ([double](@($_.Group | ForEach-Object { [double]$_.EstimatedSaving }) | Measure-Object -Sum).Sum), $_.Name }) -join '; ')
        }
    }
}
