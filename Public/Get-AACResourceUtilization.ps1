function Get-AACResourceUtilization {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        How much of what you pay for is used: each VM, scale set, App Service
        plan, database, cache, AKS cluster, storage account and Cosmos DB
        account rated idle, under-used, right sized or hot from its actual
        CPU, memory and activity - with the trend, what to resize it to and
        what that saves.
    .DESCRIPTION
        For each resource of those types in scope, reads its Azure Monitor
        metrics hour by hour over the last -Days (14): CPU (or RU
        consumption), memory (a VM's from its free memory and its size) and
        activity (transactions, connections, network). Each resource
        (AAC.ResourceUtilization) is then:
          Idle         CPU 95th percentile under -IdlePercent (5%), or no
                       activity at all
          Under-used   CPU 95th percentile under -LowPercent (30%), memory
                       under 60%
          Hot          CPU or memory 95th percentile over -HighPercent (80%)
          Right sized  in between - and its trend: Growing, Shrinking or
                       Stable (the window's second half against its first)
        An under-used VM is offered the size of its family with half the
        vCPUs, if the memory it uses fits - priced from the public Azure
        Retail Prices API for its region and OS (pay-as-you-go, USD): the
        saving a month.

        -IncludeCost reads each resource's cost (Cost Management, last
        month): every row then shows its monthly cost and the share of it
        paying for unused capacity (cost x (1 - average CPU)) - a chargeback
        of the waste - and idle and under-used resources an estimated
        saving.

        Deallocated VMs are left out: they aren't billed for compute. A VM
        that's stopped but not deallocated is still billed - and idle.
        Read-only; Reader (or Monitoring Reader) is enough, and Cost
        Management Reader for -IncludeCost.
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups (at any depth).
    .PARAMETER ResourceGroupName
        Only these resource groups.
    .PARAMETER ResourceType
        Only these types (wildcards work), e.g. 'microsoft.compute/*'.
    .PARAMETER Days
        How many days of metrics (1 to 30; 14 by default).
    .PARAMETER IncludeCost
        Read each resource's cost too: monthly cost, unused cost, savings.
    .PARAMETER IdlePercent
        CPU 95th percentile under this is idle (5 by default).
    .PARAMETER LowPercent
        CPU 95th percentile under this is under-used (30 by default).
    .PARAMETER HighPercent
        CPU or memory 95th percentile over this is hot (80 by default).
    .PARAMETER MaxResources
        At most this many resources are read (1 to 5000; 500 by default).
    .PARAMETER CsvPath
        Write the resources to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report.
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the resources.
    .PARAMETER NoDisplay
        Return the resources without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Get-AACResourceUtilization -IncludeCost
        Every resource's use against its cost, the idle and under-used first.
    .EXAMPLE
        Get-AACResourceUtilization -ResourceType 'microsoft.compute/virtualmachines' -Days 30 -HtmlPath .\out\RightSizing.html
        A month of VM use, with the sizes to move to, as a report.
    .EXAMPLE
        Get-AACResourceUtilization -NoDisplay | Where-Object Category -EQ 'Hot' | Where-Object Trend -EQ 'Growing'
        What's running hot and still growing.
    .OUTPUTS
        AAC.ResourceUtilization
    #>
    [CmdletBinding()]
    [OutputType('AAC.ResourceUtilization')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string[]] $ManagementGroupId,

        [string[]] $ResourceGroupName,

        [SupportsWildcards()]
        [string[]] $ResourceType,

        [ValidateRange(1, 30)]
        [int] $Days = 14,

        [switch] $IncludeCost,

        [ValidateRange(1, 50)]
        [int] $IdlePercent = 5,

        [ValidateRange(2, 90)]
        [int] $LowPercent = 30,

        [ValidateRange(10, 100)]
        [int] $HighPercent = 80,

        [ValidateRange(1, 5000)]
        [int] $MaxResources = 500,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Resource utilization',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $request = @{
        SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }); ResourceGroupName = @($ResourceGroupName | Where-Object { $_ })
        ResourceType = @($ResourceType | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() }); Days = $Days; IncludeCost = [bool]$IncludeCost; MaxResources = $MaxResources
    }
    $thresholds = @{ IdlePercent = $IdlePercent; LowPercent = $LowPercent; HighPercent = $HighPercent }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Resource utilization' -Color 'deepskyblue3_1' }
    $state = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
        $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
        Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"
        $definitions = Get-AACUtilizationMetric
        $types = @($definitions.Keys | Where-Object { $t = $_; -not $request.ResourceType.Count -or @($request.ResourceType | Where-Object { $t -like $_ }).Count } | Sort-Object)
        if (-not $types.Count) { throw "None of the types $($request.ResourceType -join ', ') is one this command measures: $(@($definitions.Keys | Sort-Object) -join ', ')." }
        $quote = { param([string] $Text) "'" + ($Text -replace "'", "\'") + "'" }
        $groupFilter = if ($request.ResourceGroupName.Count) { " | where resourceGroup in~ ($((@($request.ResourceGroupName | ForEach-Object { & $quote $_ })) -join ', '))" } else { '' }
        Update-AACProgress -Id 'resources' -Indeterminate -Description 'Finding the resources to measure'
        $read = Invoke-AACGraphBatch -SubscriptionId $scope.GraphScope -Query ([ordered]@{
                resources = "resources | where type in~ ($((@($types | ForEach-Object { & $quote $_ })) -join ', '))$groupFilter | project id = tolower(id), name, type = tolower(type), resourceGroup, subscriptionId, location = tolower(location), size = tostring(properties.hardwareProfile.vmSize), os = tolower(tostring(properties.storageProfile.osDisk.osType)), sku = tostring(sku.name), power = tostring(properties.extended.instanceView.powerState.code)"
            })
        $all = @($read.Rows['resources'] | Where-Object { $_ })
        $notices = [System.Collections.Generic.List[string]]::new()
        $deallocated = @($all | Where-Object { [string]$_['power'] -eq 'PowerState/deallocated' })
        if ($deallocated.Count) { $notices.Add("$($deallocated.Count) deallocated VM(s) left out: they aren't billed for compute.") }
        $resources = @($all | Where-Object { [string]$_['power'] -ne 'PowerState/deallocated' } | Select-Object -First $request.MaxResources)
        if (@($all).Count - $deallocated.Count -gt $request.MaxResources) { $notices.Add("Only the first $($request.MaxResources) of $(@($all).Count - $deallocated.Count) resources were measured (-MaxResources).") }
        Update-AACProgress -Id 'resources' -Complete -Description ('Found {0:N0} resource(s) to measure' -f $resources.Count)

        # --- Their metrics, hour by hour ------------------------------------------------------------------------------
        $end = [datetime]::UtcNow; $start = $end.AddDays(-$request.Days)
        $span = "$($start.ToString('yyyy-MM-ddTHH:mm:ssZ'))/$($end.ToString('yyyy-MM-ddTHH:mm:ssZ'))"
        $uriFor = { param($Row, [string[]] $Names) "$($Row['id'])/providers/Microsoft.Insights/metrics?api-version=2023-10-01&metricnames=$([System.Uri]::EscapeDataString(($Names -join ',')))&timespan=$span&interval=PT1H&aggregation=Average,Maximum,Minimum,Total" }
        $wanted = @{}
        foreach ($r in $resources) { $d = $definitions[[string]$r['type']]; $wanted[[string]$r['id']] = @(@($d.Cpu, $d.Memory, $d.Activity) | Where-Object { $_ }) }
        $uris = @{}
        foreach ($r in $resources) { if ($wanted[[string]$r['id']].Count) { $uris[[string]$r['id']] = & $uriFor $r $wanted[[string]$r['id']] } }
        Update-AACProgress -Id 'metrics' -Total ([Math]::Max(1, $uris.Count)) -Description "Reading $($request.Days) days of metrics for $($uris.Count) resource(s)"
        $answers = Invoke-AACArmParallel -Uri @($uris.Values) -OnProgress { param($MetricDone, $MetricTotal) Update-AACProgress -Id 'metrics' -Increment 1 }
        $metrics = @{}
        $retry = @{}
        foreach ($id in $uris.Keys) {
            $answer = $answers[$uris[$id]]
            if ($answer -and -not $answer.Error) { $metrics[$id] = @($answer.Body['value']) }
            elseif ($wanted[$id].Count -gt 1) { $row = @($resources | Where-Object { $_['id'] -eq $id }) | Select-Object -First 1; $retry[$id] = & $uriFor $row @($wanted[$id][0]) }
        }
        # A metric the resource doesn't have fails the whole request: those again, with the first metric only.
        if ($retry.Count) {
            $again = Invoke-AACArmParallel -Uri @($retry.Values)
            foreach ($id in $retry.Keys) { $answer = $again[$retry[$id]]; if ($answer -and -not $answer.Error) { $metrics[$id] = @($answer.Body['value']) } }
        }
        $unread = $uris.Count - $metrics.Count
        if ($unread) { $notices.Add("$unread resource(s)' metrics couldn't be read.") }
        Update-AACProgress -Id 'metrics' -Complete -Description ('Read the metrics of {0:N0} resource(s)' -f $metrics.Count)

        # --- VM sizes, per subscription and region -------------------------------------------------------------------
        $sizes = @{}
        $vms = @($resources | Where-Object { [string]$_['type'] -eq 'microsoft.compute/virtualmachines' })
        if ($vms.Count) {
            $sizeUris = @{}
            foreach ($v in $vms) { $sizeUris["$([string]$v['location'])"] = "/subscriptions/$($v['subscriptionId'])/providers/Microsoft.Compute/locations/$($v['location'])/vmSizes?api-version=2024-03-01" }
            $sizeAnswers = Invoke-AACArmParallel -Uri @($sizeUris.Values)
            foreach ($location in $sizeUris.Keys) {
                foreach ($s in @($sizeAnswers[$sizeUris[$location]].Items | Where-Object { $_ })) { $sizes["$location|$(([string]$s['name']).ToLowerInvariant())"] = @{ Cores = [int]$s['numberOfCores']; MemoryMB = [double]$s['memoryInMB'] } }
            }
        }

        # --- Cost ---------------------------------------------------------------------------------------------------------
        $costs = @{}
        if ($request.IncludeCost) {
            Update-AACProgress -Id 'cost' -Indeterminate -Description 'Reading each resource''s cost (Cost Management)'
            $costRead = Read-AACInventoryCost -TenantId ([string]$script:AACSession.TenantId) -Subscription @($scope.Subscriptions | ForEach-Object { @{ subscriptionId = [string]$_['subscriptionId']; name = [string]$_['name']; state = [string]$_['state'] } }) -ManagementGroupId $request.ManagementGroupId -PerSubscription:([bool]$request.SubscriptionId.Count)
            $months = @{}
            foreach ($row in @($costRead.Rows)) {
                $id = ([string](Get-AACPropertyValue -InputObject $row -Name 'ResourceId')).ToLowerInvariant()
                if (-not $id) { continue }
                $monthRaw = @('BillingMonth', 'UsageDate' | ForEach-Object { Get-AACPropertyValue -InputObject $row -Name $_ } | Where-Object { $_ }) | Select-Object -First 1
                $month = if ($monthRaw -is [datetime]) { $monthRaw.ToString('yyyy-MM') } else { ([string]$monthRaw).Substring(0, [Math]::Min(7, ([string]$monthRaw).Length)) -replace '^(\d{4})(\d{2}).*$', '$1-$2' }
                if (-not $months.Contains($id)) { $months[$id] = @{} }
                $months[$id][$month] = [double]$months[$id][$month] + [double](Get-AACPropertyValue -InputObject $row -Name 'Cost')
                $costs[$id] = @{ Cost = 0; Currency = [string](Get-AACPropertyValue -InputObject $row -Name 'Currency') }
            }
            $dayOfMonth = [datetime]::UtcNow.Day
            foreach ($id in $months.Keys) {
                $costs[$id].Cost = if ($months[$id].Contains($costRead.LastMonth)) { $months[$id][$costRead.LastMonth] } else { [double]$months[$id][$costRead.ThisMonth] / $dayOfMonth * 30 }
            }
            foreach ($line in @($costRead.Notice)) { if ($line) { $notices.Add($line) } }
            Update-AACProgress -Id 'cost' -Complete -Description ('Read the cost of {0:N0} resource(s)' -f $costs.Count)
        }

        # --- Rate them; price the VM sizes suggested; rate again with the prices --------------------------------------------
        $rate = { param([hashtable] $Prices) ConvertTo-AACResourceUtilization -Resource $resources -Metric $metrics -Size $sizes -Price $Prices -Cost $costs -SubscriptionName $scope.Names @thresholds }
        $result = & $rate @{}
        $priced = @{}
        $toPrice = @($result.Rows | Where-Object { $_.SuggestedSize } | ForEach-Object {
                $rated = $_
                $row = @($resources | Where-Object { $_['id'] -eq $rated.ResourceId }) | Select-Object -First 1
                $os = if ($row) { [string]$row['os'] } else { 'linux' }
                $location = if ($row) { [string]$row['location'] } else { '' }
                foreach ($size in $rated.Size, $rated.SuggestedSize) { "$location|$($size.ToLowerInvariant())|$os|$size" }
            } | Select-Object -Unique)
        if ($toPrice.Count) {
            Update-AACProgress -Id 'prices' -Total $toPrice.Count -Description 'Pricing the suggested VM sizes (Azure Retail Prices)'
            foreach ($key in $toPrice) {
                $location, $lowerSize, $os, $size = $key.Split('|')
                $price = Get-AACRetailPrice -Location $location -Size $size -Os $os
                if ($null -ne $price) { $priced["$location|$lowerSize|$os"] = $price }
                Update-AACProgress -Id 'prices' -Increment 1
            }
            Update-AACProgress -Id 'prices' -Complete -Description "Priced $($priced.Count) VM size(s)"
            $result = & $rate $priced
        }
        @{ Result = $result; Scope = $scope; Notices = $notices.ToArray() }
    }

    $result = $state.Result
    $rows = @($result.Rows)
    $s = $result.Stats
    $money = $(if (@($s.Currencies).Count -eq 1) { @($s.Currencies)[0] } else { '' })
    $statusTones = @{ Idle = 'bad'; 'Under-used' = 'warn'; Hot = 'violet'; 'Right sized' = 'good'; 'No data' = 'neutral' }
    $report = @{
        Subtitle = "Resource utilization: the last $Days days"
        Facts    = [ordered]@{ Scope = $state.Scope.Label; Window = "$Days days, hourly"; Thresholds = "idle under $IdlePercent%, under-used under $LowPercent%, hot over $HighPercent% (95th percentile)" }
        Status   = $(if ($s.Idle -or $s.Hot) { 'Warning' } elseif ($s.Underused) { 'Warning' } else { 'Success' })
        Headline = "$($s.Resources) resource(s): $($s.Idle) idle, $($s.Underused) under-used, $($s.Hot) hot, $($s.Right) right sized$(if ($s.SavingText) { " - about $($s.SavingText) a month to save" })"
        Tiles    = @(
            @{ Value = '{0:N0}' -f $s.Idle; Label = 'idle'; Tone = $(if ($s.Idle) { 'bad' } else { 'good' }); Table = 'utilization'; Filters = @{ Category = 'Idle' } }
            @{ Value = '{0:N0}' -f $s.Underused; Label = 'under-used'; Tone = $(if ($s.Underused) { 'warn' } else { 'good' }); Table = 'utilization'; Filters = @{ Category = 'Under-used' } }
            @{ Value = '{0:N0}' -f $s.Hot; Label = 'running hot'; Tone = $(if ($s.Hot) { 'violet' } else { 'good' }); Table = 'utilization'; Filters = @{ Category = 'Hot' } }
            @{ Value = '{0:N0}' -f $s.Right; Label = 'right sized'; Tone = 'good'; Table = 'utilization'; Filters = @{ Category = 'Right sized' } }
            @{ Value = '{0:N0}' -f $s.Growing; Label = 'growing'; Tone = 'info'; Table = 'utilization'; Filters = @{ Trend = 'Growing' } }
            @{ Value = $(if ($s.SavingText) { $s.SavingText } else { '-' }); Label = 'a month to save'; Tone = 'good' }
            @{ Value = $(if ($s.UnusedCost) { '{0:N0}' -f $s.UnusedCost } else { '-' }); Label = "a month on unused capacity $money".TrimEnd(); Tone = $(if ($s.UnusedCost) { 'warn' } else { 'neutral' }) }
        )
        Notices  = @($state.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
        Charts   = @(
            @{ Title = 'Resources by use'; Kind = 'donut'; CenterLabel = 'resources'; Items = @(foreach ($c in 'Idle', 'Under-used', 'Hot', 'Right sized', 'No data') { $n = @($rows | Where-Object Category -EQ $c).Count; if ($n) { @{ Label = $c; Value = $n; Tone = $statusTones[$c]; Filter = $c } } }); Table = 'utilization'; Column = 'Category'; Console = $true }
            @{ Title = 'Largest savings'; Items = @($rows | Where-Object { $_.EstimatedSaving -gt 0 } | Sort-Object EstimatedSaving -Descending | Select-Object -First 10 | ForEach-Object { @{ Label = $_.Resource; Value = $_.EstimatedSaving; Filter = $_.Resource } }); Table = 'utilization'; Column = 'Resource'; Tone = 'good' }
            @{ Title = 'CPU, 95th percentile (%)'; Items = @($rows | Where-Object { $null -ne $_.CpuP95 } | Sort-Object CpuP95 -Descending | Select-Object -First 12 | ForEach-Object { @{ Label = $_.Resource; Value = $_.CpuP95; Filter = $_.Resource } }); Table = 'utilization'; Column = 'Resource'; Tone = 'violet' }
        )
        Tables   = @(
            @{ Id = 'utilization'; Title = 'Resources'; Section = 'Utilization'; Rows = $rows; Noun = 'resources'; GroupBy = @('Category', 'Kind', 'Trend', 'ResourceGroup', 'Subscription'); ConsoleLimit = 30
                Empty = 'No resources of the types measured in scope.'; EmptyStatus = 'Info'
                Columns = @(
                    @{ Key = 'Category'; Label = 'Use'; Type = 'badge'; Tones = $statusTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Resource'; Label = 'Resource'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Kind'; Label = 'Kind'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Size'; Label = 'Size'; Type = 'mono'; Console = $true; Pdf = $true }
                    @{ Key = 'CpuP95'; Label = 'CPU p95 (%)'; Type = 'number'; Format = 'N0'; Console = $true; Pdf = $true }
                    @{ Key = 'MemoryP95'; Label = 'Memory p95 (%)'; Type = 'number'; Format = 'N0'; Console = $true; Pdf = $true }
                    @{ Key = 'Trend'; Label = 'Trend'; Type = 'badge'; Tones = @{ Growing = 'info'; Shrinking = 'neutral'; Stable = 'good' }; Facet = $true; Console = $true }
                    @{ Key = 'SuggestedSize'; Label = 'Resize to'; Type = 'mono'; Console = $true; Pdf = $true }
                    @{ Key = 'EstimatedSaving'; Label = 'Saving a month'; Type = 'money'; CurrencyKey = 'Currency'; Console = $true; Pdf = $true }
                    @{ Key = 'MonthlyCost'; Label = 'Cost a month'; Type = 'money'; CurrencyKey = 'Currency' }
                    @{ Key = 'UnusedCost'; Label = 'Unused (chargeback)'; Type = 'money'; CurrencyKey = 'Currency' }
                    @{ Key = 'CpuAverage'; Label = 'CPU average (%)'; Type = 'number'; Format = 'N1' }
                    @{ Key = 'CpuMax'; Label = 'CPU max (%)'; Type = 'number'; Format = 'N0' }
                    @{ Key = 'GrowthPercent'; Label = 'Growth (%)'; Type = 'number'; Format = 'N0' }
                    @{ Key = 'Remediation'; Label = 'What to do'; Type = 'wide' }
                    @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                    @{ Key = 'Currency'; Label = 'Currency'; Hidden = $true }
                ) }
        )
        Hint     = '-IncludeCost adds the cost and the chargeback; -Days sets the window; -NoDisplay returns the resources.'
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $rows -Noun 'resource' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $rows -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
