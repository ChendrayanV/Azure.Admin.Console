function ConvertTo-AACAssessmentCost {
    <#
    .SYNOPSIS
        Builds Invoke-AACTenantAssessment's FinOps sheets: where money can be
        saved, how much of the estate can be allocated to an owner, the
        budgets, and - with the cost read - where the money goes.
    .DESCRIPTION
        No Azure calls. Sheets, in ConvertTo-AACAssessment's shape (Kind
        'Cost', Category 'FinOps'):
          Savings opportunities  one list, by FinOps lever: Waste (unattached
                                 disks, unused public IPs, VMs stopped but
                                 still billed, empty App Service plans, old
                                 snapshots), Rightsizing and Rate (Advisor's
                                 cost recommendations - right-size, shut
                                 down, reservations, savings plans),
                                 Licensing (Azure Hybrid Benefit unused) and
                                 Modernise (old VM generations). Waste is
                                 estimated at the resource's last month
                                 cost a year; Advisor's own estimate
                                 otherwise
          Cost allocation        per subscription: the resources with a
                                 cost-allocation tag (-CostTag), and the
                                 cost of those without one
          Budgets                each subscription's budgets - spent and
                                 forecast against the amount, and the alerts
                                 - and the subscriptions with none (with
                                 -BudgetRead)
          Cost by service, Cost by resource group, Top cost resources
                                 month to date, last month, this month
                                 projected and the change (with -CostRead)
        The waste comes from the Well-Architected checks (CO-03 to CO-10)
        when -WafResult has them, otherwise from the inventory's unattached
        and empty resources.
        Returns @{ Sheets; Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        # ConvertTo-AACAssessment's sheets: All resources (with the cost
        # columns), Advisor recommendations, and the inventory.
        [object[]] $Sheet = @(),

        # Every resource in scope (id, type, subscriptionId, resourceGroup, tags).
        [AllowEmptyCollection()]
        [object[]] $Resource = @(),

        [AllowEmptyCollection()]
        [object[]] $Subscription = @(),

        # ConvertTo-AACWafAssessment's Results.
        [AllowEmptyCollection()]
        [object[]] $WafResult = @(),

        # Subscription ID -> its budgets (those read; a subscription that
        # couldn't be asked isn't there).
        [hashtable] $Budget = @{},

        [string[]] $CostTag = @('CostCenter', 'CostCentre', 'Cost Center', 'Project', 'Application', 'BillingCode'),

        [switch] $BudgetRead,

        [switch] $CostRead,

        [datetime] $Now = (Get-Date)
    )

    $value = { param($Row, [string] $Key) if ($Row -is [System.Collections.IDictionary]) { if ($Row.Contains($Key)) { $Row[$Key] } } elseif ($null -ne $Row) { Get-AACPropertyValue -InputObject $Row -Name $Key } }
    $at = {
        param($Item, [string] $Path)
        foreach ($part in ($Path -split '\.')) {
            if ($Item -is [System.Collections.IDictionary]) { $Item = if ($Item.Contains($part)) { $Item[$part] } else { $null } }
            elseif ($null -ne $Item -and $Item -isnot [string] -and $Item -isnot [ValueType]) { $Item = Get-AACPropertyValue -InputObject $Item -Name $part }
            else { return $null }
        }
        $Item
    }
    $lower = { param($Text) ([string]$Text).ToLowerInvariant() }
    $leaf = { param($Id) if ($Id) { ([string]$Id).TrimEnd('/') -replace '^.*/', '' } else { '' } }
    $round = { param($Number) if ($null -eq $Number -or "$Number" -eq '') { $null } else { [Math]::Round([double]$Number, 2) } }
    $slug = { param([string] $Name) ($Name.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-') }
    $findSheet = { param([string] $Name) @($Sheet | Where-Object { $_.Sheet -eq $Name }) | Select-Object -First 1 }
    $newSheet = {
        param([string] $Name, [System.Collections.IDictionary] $Types, [object[]] $Rows, [string[]] $Key, [string] $Note)
        @{ Id = & $slug $Name; Kind = 'Cost'; Category = 'FinOps'; Sheet = $Name; Columns = @($Types.Keys); Types = $Types; Rows = @($Rows); Key = @($Key); Error = ''; Note = $Note }
    }
    $subscriptionNames = @{}
    foreach ($row in $Subscription) { $subscriptionNames[(& $lower (& $value $row 'subscriptionId'))] = [string](& $value $row 'name') }
    $subscriptionName = { param($Id) $key = & $lower $Id; if ($subscriptionNames.Contains($key)) { $subscriptionNames[$key] } else { [string]$Id } }
    $sheets = [System.Collections.Generic.List[hashtable]]::new()

    # The month so far, projected to its end: the fairest comparison with last month.
    $daysInMonth = [datetime]::DaysInMonth($Now.Year, $Now.Month)
    $project = { param($MonthToDate) if ($null -eq $MonthToDate) { $null } else { [Math]::Round([double]$MonthToDate / [Math]::Max(1, $Now.Day) * $daysInMonth, 2) } }
    $change = { param($Projected, $Last) if ($null -eq $Projected -or -not $Last) { $null } else { [Math]::Round(([double]$Projected - [double]$Last) / [double]$Last * 100, 1) } }

    # Each resource's cost, from All resources (filled in with -IncludeCost).
    $all = & $findSheet 'All resources'
    $costOf = @{}
    if ($CostRead -and $all) {
        foreach ($row in @($all.Rows)) {
            $costOf[(& $lower $row.ResourceId)] = @{ ThisMonth = $row.'Cost (month to date)'; LastMonth = $row.'Cost (last month)'; Currency = [string]$row.Currency; Row = $row }
        }
    }
    $lastMonthOf = { param([string] $Id) $key = & $lower $Id; if ($costOf.Contains($key)) { $costOf[$key].LastMonth } else { $null } }
    $currencyOf = { param([string] $Id) $key = & $lower $Id; if ($costOf.Contains($key)) { $costOf[$key].Currency } else { '' } }

    # --- Savings opportunities ------------------------------------------------------------------------------------
    $savings = [System.Collections.Generic.List[object]]::new()
    $addSaving = {
        param([string] $Lever, [string] $Opportunity, [string] $Id, [string] $Type, [string] $Group, [string] $Sub, $Annual, [string] $Currency, [string] $Source, [string] $Remedy)
        $last = & $lastMonthOf $Id
        $savings.Add([pscustomobject][ordered]@{
                'Lever' = $Lever; 'Opportunity' = $Opportunity; 'Resource' = & $leaf $Id; 'Resource type' = $Type; 'Resource group' = $Group; 'Subscription' = $Sub
                'Cost (last month)' = & $round $last; 'Est. annual savings' = & $round $Annual
                'Currency' = $(if ($Currency) { $Currency } else { & $currencyOf $Id }); 'Source' = $Source; 'What to do' = $Remedy; 'ResourceId' = $Id
            })
    }
    # A resource deleted saves what it cost: last month's, a year.
    $yearOf = { param([string] $Id) $last = & $lastMonthOf $Id; if ($null -ne $last) { [double]$last * 12 } else { $null } }
    $wafLever = @{
        'CO-03' = 'Waste'; 'CO-04' = 'Waste'; 'CO-05' = 'Waste'; 'CO-06' = 'Waste'; 'CO-07' = 'Waste'
        'CO-08' = 'Licensing'; 'CO-09' = 'Licensing'; 'CO-10' = 'Modernise'
    }
    # The checks are named for what passes; the opportunity, for what was found.
    $wafFound = @{
        'CO-03' = 'Managed disk not attached to anything'; 'CO-04' = 'Public IP address not associated with anything'
        'CO-05' = 'VM stopped but still billed (not deallocated)'; 'CO-06' = 'App Service plan with no apps'; 'CO-07' = 'Snapshot older than 90 days'
        'CO-08' = 'Windows VM without Azure Hybrid Benefit'; 'CO-09' = 'SQL database without Azure Hybrid Benefit'; 'CO-10' = 'VM on an older-generation size'
    }
    $wafCost = @(@($WafResult) | Where-Object { $_.Status -eq 'Fail' -and $wafLever.Contains([string]$_.CheckId) })
    if (@($WafResult).Count) {
        foreach ($r in $wafCost) {
            $lever = $wafLever[[string]$r.CheckId]
            & $addSaving $lever $wafFound[[string]$r.CheckId] ([string]$r.ResourceId) ([string]$r.ResourceType) ([string]$r.ResourceGroup) ([string]$r.Subscription) `
                $(if ($lever -eq 'Waste') { & $yearOf ([string]$r.ResourceId) }) '' "Well-Architected $($r.CheckId)" ([string]$r.Recommendation)
        }
    }
    else {
        foreach ($s in @($Sheet | Where-Object { $_.Kind -eq 'Inventory' })) {
            foreach ($label in 'Orphaned', 'Empty') {
                if ($s.Columns -notcontains $label) { continue }
                foreach ($row in @($s.Rows | Where-Object { $_.$label -eq 'Yes' })) {
                    $id = [string]$row.ResourceId
                    & $addSaving 'Waste' "$($s.Sheet): $(if ($label -eq 'Orphaned') { 'not attached to anything' } else { 'empty' })" $id $(if ($id -match '(?i)/providers/([^/]+/[^/]+)/[^/]+$') { $Matches[1].ToLowerInvariant() } else { '' }) ([string]$row.'Resource group') ([string]$row.Subscription) (& $yearOf $id) '' 'Inventory' 'Confirm it isn''t needed, then delete it.'
                }
            }
            if ($s.Sheet -eq 'Disks' -and $s.Columns -notcontains 'Orphaned') {
                foreach ($row in @($s.Rows | Where-Object { $_.State -eq 'Unattached' })) { & $addSaving 'Waste' 'Disk not attached to any VM' ([string]$row.ResourceId) 'microsoft.compute/disks' ([string]$row.'Resource group') ([string]$row.Subscription) (& $yearOf ([string]$row.ResourceId)) '' 'Inventory' 'Snapshot it if it might be needed, then delete it.' }
            }
        }
    }
    $advisor = & $findSheet 'Advisor recommendations'
    foreach ($row in @(if ($advisor) { $advisor.Rows | Where-Object { [string]$_.Category -eq 'Cost' } })) {
        $text = "$($row.Problem) $($row.Solution)"
        $lever = switch -Regex ($text) {
            '(?i)reserv|savings plan' { 'Rate'; break }
            '(?i)hybrid benefit' { 'Licensing'; break }
            '(?i)right-?siz|resiz|underutili|idle|shut ?down|unused|delete' { 'Rightsizing'; break }
            default { 'Usage' }
        }
        & $addSaving $lever ([string]$row.Problem) ([string]$row.ResourceId) ([string]$row.'Resource type') ([string]$row.'Resource group') ([string]$row.Subscription) $row.'Annual savings' ([string]$row.Currency) 'Azure Advisor' ([string]$row.Solution)
    }
    $leverRank = @{ Waste = 0; Rightsizing = 1; Rate = 2; Licensing = 3; Usage = 4; Modernise = 5 }
    $savingRows = @($savings | Sort-Object -Property @{ Expression = { if ($null -ne $_.'Est. annual savings') { -[double]$_.'Est. annual savings' } else { 0 } } }, @{ Expression = { $leverRank[$_.Lever] } }, Opportunity, Resource)
    $sheets.Add((& $newSheet 'Savings opportunities' ([ordered]@{ 'Lever' = 'badge'; 'Opportunity' = 'wide'; 'Resource' = 'resource'; 'Resource type' = 'mono'; 'Resource group' = 'text'; 'Subscription' = 'text'; 'Cost (last month)' = 'money'; 'Est. annual savings' = 'money'; 'Currency' = 'text'; 'Source' = 'text'; 'What to do' = 'wide' }) `
                $savingRows @('Lever', 'Opportunity', 'Resource', 'Est. annual savings') `
                'Where money can be saved, by FinOps lever. Waste is estimated at the resource''s cost last month, for a year (with -IncludeCost); Advisor gives its own estimate. Reservations and savings plans come from Advisor; the Reservation recommendations sheet has Azure Consumption''s view.'))

    # --- Cost allocation: cost-allocation tags per subscription ----------------------------------------------------
    $tagged = {
        param($Tags)
        if ($Tags -isnot [System.Collections.IDictionary]) { return $false }
        foreach ($key in @($Tags.Keys)) { if (@($CostTag | Where-Object { $_ -eq [string]$key }).Count -and "$($Tags[$key])".Trim()) { return $true } }
        $false
    }
    $allocation = @{}
    foreach ($row in $Resource) {
        $sub = & $lower (& $value $row 'subscriptionId')
        if (-not $allocation.Contains($sub)) { $allocation[$sub] = @{ Resources = 0; Tagged = 0; Cost = 0.0; Untagged = 0.0; Currency = ''; Costed = $false } }
        $entry = $allocation[$sub]
        $entry.Resources++
        $hasTag = & $tagged (& $value $row 'tags')
        if ($hasTag) { $entry.Tagged++ }
        $last = & $lastMonthOf ([string](& $value $row 'id'))
        if ($null -ne $last) {
            $entry.Costed = $true; $entry.Cost += [double]$last
            if (-not $hasTag) { $entry.Untagged += [double]$last }
            $currency = & $currencyOf ([string](& $value $row 'id'))
            if ($currency) { $entry.Currency = $currency }
        }
    }
    $allocationTypes = [ordered]@{ 'Subscription' = 'text'; 'Resources' = 'number'; 'With a cost tag' = 'number'; 'Without' = 'number'; 'Coverage (%)' = 'score' }
    if ($CostRead) { $allocationTypes['Cost (last month)'] = 'money'; $allocationTypes['Untagged cost (last month)'] = 'money'; $allocationTypes['Untagged cost (%)'] = 'number'; $allocationTypes['Currency'] = 'text' }
    $allocationRows = @(foreach ($sub in $allocation.Keys) {
            $e = $allocation[$sub]
            $item = [ordered]@{
                'Subscription' = & $subscriptionName $sub; 'Resources' = $e.Resources; 'With a cost tag' = $e.Tagged; 'Without' = $e.Resources - $e.Tagged
                'Coverage (%)' = $(if ($e.Resources) { [Math]::Round($e.Tagged / $e.Resources * 100, 1) } else { $null })
            }
            if ($CostRead) {
                $item['Cost (last month)'] = $(if ($e.Costed) { & $round $e.Cost } else { $null }); $item['Untagged cost (last month)'] = $(if ($e.Costed) { & $round $e.Untagged } else { $null })
                $item['Untagged cost (%)'] = $(if ($e.Cost) { [Math]::Round($e.Untagged / $e.Cost * 100, 1) } else { $null }); $item['Currency'] = $e.Currency
            }
            $item['ResourceId'] = "/subscriptions/$sub"
            [pscustomobject]$item
        }) | Sort-Object 'Coverage (%)', Subscription
    $sheets.Add((& $newSheet 'Cost allocation' $allocationTypes @($allocationRows) @('Subscription', 'Resources', 'Without', 'Coverage (%)') `
                "The resources with a cost-allocation tag ($($CostTag -join ', ')) - showback and chargeback need one on every resource that costs. -CostTag sets the tag names."))

    # --- Budgets ---------------------------------------------------------------------------------------------
    $budgetRows = [System.Collections.Generic.List[object]]::new()
    if ($BudgetRead) {
        foreach ($row in $Subscription | Sort-Object { [string](& $value $_ 'name') }) {
            $sub = & $lower (& $value $row 'subscriptionId')
            $name = [string](& $value $row 'name')
            if ([string](& $value $row 'state') -in 'Disabled', 'Deleted', 'Expired') { continue }
            if (-not $Budget.Contains($sub)) {
                $budgetRows.Add([pscustomobject][ordered]@{ 'Subscription' = $name; 'Budget' = ''; 'Status' = 'Not read'; 'Amount' = $null; 'Time grain' = ''; 'Spent' = $null; 'Spent (%)' = $null; 'Forecast' = $null; 'Forecast (%)' = $null; 'Currency' = ''; 'Alerts' = ''; 'Ends' = ''; 'ResourceId' = "/subscriptions/$sub" })
                continue
            }
            $items = @($Budget[$sub] | Where-Object { $null -ne $_ })
            if (-not $items.Count) {
                $budgetRows.Add([pscustomobject][ordered]@{ 'Subscription' = $name; 'Budget' = ''; 'Status' = 'No budget'; 'Amount' = $null; 'Time grain' = ''; 'Spent' = $null; 'Spent (%)' = $null; 'Forecast' = $null; 'Forecast (%)' = $null; 'Currency' = ''; 'Alerts' = ''; 'Ends' = ''; 'ResourceId' = "/subscriptions/$sub" })
                continue
            }
            foreach ($b in $items) {
                $amount = [double](& $at $b 'properties.amount')
                $spent = & $at $b 'properties.currentSpend.amount'
                $forecast = & $at $b 'properties.forecastSpend.amount'
                $notifications = & $at $b 'properties.notifications'
                $alerts = @(if ($notifications -is [System.Collections.IDictionary]) {
                        foreach ($key in $notifications.Keys) {
                            $n = $notifications[$key]
                            if ((& $at $n 'enabled') -eq $false) { continue }
                            "$(& $at $n 'threshold')% $(if (& $at $n 'thresholdType') { & $at $n 'thresholdType' } else { 'Actual' })"
                        }
                    })
                $status = if ($null -ne $spent -and $amount -and [double]$spent -gt $amount) { 'Over budget' } elseif ($null -ne $forecast -and $amount -and [double]$forecast -gt $amount) { 'Forecast over' } elseif (-not $alerts.Count) { 'No alerts' } else { 'On track' }
                $budgetRows.Add([pscustomobject][ordered]@{
                        'Subscription' = $name; 'Budget' = [string](& $value $b 'name'); 'Status' = $status; 'Amount' = & $round $amount; 'Time grain' = [string](& $at $b 'properties.timeGrain')
                        'Spent' = & $round $spent; 'Spent (%)' = $(if ($amount -and $null -ne $spent) { [Math]::Round([double]$spent / $amount * 100, 1) } else { $null })
                        'Forecast' = & $round $forecast; 'Forecast (%)' = $(if ($amount -and $null -ne $forecast) { [Math]::Round([double]$forecast / $amount * 100, 1) } else { $null })
                        'Currency' = [string]$(@((& $at $b 'properties.currentSpend.unit'), (& $at $b 'properties.forecastSpend.unit')) | Where-Object { $_ } | Select-Object -First 1)
                        'Alerts' = ($alerts -join ', '); 'Ends' = ([string](& $at $b 'properties.timePeriod.endDate') -replace 'T.*$', ''); 'ResourceId' = [string](& $value $b 'id')
                    })
            }
        }
        $statusRank = @{ 'Over budget' = 0; 'Forecast over' = 1; 'No budget' = 2; 'No alerts' = 3; 'Not read' = 4; 'On track' = 5 }
        $sheets.Add((& $newSheet 'Budgets' ([ordered]@{ 'Subscription' = 'text'; 'Budget' = 'text'; 'Status' = 'badge'; 'Amount' = 'money'; 'Time grain' = 'text'; 'Spent' = 'money'; 'Spent (%)' = 'number'; 'Forecast' = 'money'; 'Forecast (%)' = 'number'; 'Currency' = 'text'; 'Alerts' = 'text'; 'Ends' = 'text' }) `
                    @($budgetRows | Sort-Object { $statusRank[$_.Status] }, Subscription) @('Subscription', 'Budget', 'Status', 'Amount', 'Spent (%)', 'Forecast (%)') `
                    'Each subscription''s Cost Management budgets, spent and forecast against the amount, and the subscriptions with none. A budget with no alert tells no one.'))
    }

    # --- Where the money goes (with the cost) ----------------------------------------------------------------
    $costRows = @($costOf.Values | Where-Object { $null -ne $_.ThisMonth -or $null -ne $_.LastMonth })
    if ($CostRead -and $costRows.Count) {
        $summed = {
            param([object[]] $Rows)
            $mtd = [double](@($Rows | ForEach-Object { [double]$_.ThisMonth }) | Measure-Object -Sum).Sum
            $last = [double](@($Rows | ForEach-Object { [double]$_.LastMonth }) | Measure-Object -Sum).Sum
            $projected = & $project $mtd
            @{ MonthToDate = [Math]::Round($mtd, 2); LastMonth = [Math]::Round($last, 2); Projected = $projected; Change = & $change $projected $last; Currency = [string](@($Rows | ForEach-Object Currency | Where-Object { $_ }) | Select-Object -First 1) }
        }
        $moneyTypes = [ordered]@{ 'Cost (month to date)' = 'money'; 'Cost (last month)' = 'money'; 'Projected (this month)' = 'money'; 'Change (%)' = 'number'; 'Currency' = 'text' }
        $withMoney = {
            param([System.Collections.IDictionary] $Item, [hashtable] $Sum)
            $Item['Cost (month to date)'] = $Sum.MonthToDate; $Item['Cost (last month)'] = $Sum.LastMonth; $Item['Projected (this month)'] = $Sum.Projected; $Item['Change (%)'] = $Sum.Change; $Item['Currency'] = $Sum.Currency
            $Item
        }

        $byType = @(foreach ($group in $costRows | Group-Object { [string]$_.Row.Type }) {
                $item = [ordered]@{ 'Category' = [string]$group.Group[0].Row.Category; 'Resource type' = $group.Name; 'Resources' = $group.Count }
                [pscustomobject](& $withMoney $item (& $summed $group.Group))
            }) | Sort-Object -Property @{ Expression = 'Cost (last month)'; Descending = $true }, @{ Expression = 'Cost (month to date)'; Descending = $true }
        $types = [ordered]@{ 'Category' = 'text'; 'Resource type' = 'mono'; 'Resources' = 'number' }
        foreach ($k in $moneyTypes.Keys) { $types[$k] = $moneyTypes[$k] }
        $sheets.Add((& $newSheet 'Cost by service' $types @($byType) @('Resource type', 'Resources', 'Cost (last month)', 'Projected (this month)', 'Change (%)') 'Actual cost by resource type: this month so far, projected to the month''s end, against last month.'))

        $byGroup = @(foreach ($group in $costRows | Group-Object { "$($_.Row.Subscription)|$($_.Row.'Resource group')" }) {
                $first = $group.Group[0].Row
                $item = [ordered]@{ 'Subscription' = [string]$first.Subscription; 'Resource group' = [string]$first.'Resource group'; 'Resources' = $group.Count }
                [pscustomobject](& $withMoney $item (& $summed $group.Group))
            }) | Sort-Object -Property @{ Expression = 'Cost (last month)'; Descending = $true }, @{ Expression = 'Cost (month to date)'; Descending = $true }
        $types = [ordered]@{ 'Subscription' = 'text'; 'Resource group' = 'text'; 'Resources' = 'number' }
        foreach ($k in $moneyTypes.Keys) { $types[$k] = $moneyTypes[$k] }
        $sheets.Add((& $newSheet 'Cost by resource group' $types @($byGroup) @('Subscription', 'Resource group', 'Cost (last month)', 'Projected (this month)', 'Change (%)') ''))

        $top = @($costRows | Sort-Object -Property @{ Expression = { [double]$_.LastMonth }; Descending = $true }, @{ Expression = { [double]$_.ThisMonth }; Descending = $true } | Select-Object -First 50 | ForEach-Object {
                $r = $_.Row
                $item = [ordered]@{ 'Name' = [string]$r.Name; 'Type' = [string]$r.Type; 'Subscription' = [string]$r.Subscription; 'Resource group' = [string]$r.'Resource group'; 'SKU' = [string]$r.SKU }
                $item = & $withMoney $item (& $summed @($_))
                $item['Tagged'] = [string]$r.Tagged
                $item['ResourceId'] = [string]$r.ResourceId
                [pscustomobject]$item
            })
        $types = [ordered]@{ 'Name' = 'resource'; 'Type' = 'mono'; 'Subscription' = 'text'; 'Resource group' = 'text'; 'SKU' = 'text' }
        foreach ($k in $moneyTypes.Keys) { $types[$k] = $moneyTypes[$k] }
        $types['Tagged'] = 'badge'
        $sheets.Add((& $newSheet 'Top cost resources' $types $top @('Name', 'Type', 'Cost (last month)', 'Projected (this month)', 'Change (%)') 'The 50 resources that cost the most last month (then this month).'))
    }

    $currencies = @($savingRows | Where-Object { $null -ne $_.'Est. annual savings' } | ForEach-Object Currency | Where-Object { $_ } | Select-Object -Unique)
    $resources = [int](@($allocationRows | ForEach-Object { $_.Resources }) | Measure-Object -Sum).Sum
    $taggedCount = [int](@($allocationRows | ForEach-Object { $_.'With a cost tag' }) | Measure-Object -Sum).Sum
    @{
        Sheets = $sheets.ToArray()
        Stats  = [ordered]@{
            SavingsOpportunities       = $savingRows.Count
            AnnualSavings              = $(if ($currencies.Count -le 1) { [Math]::Round([double](@($savingRows | ForEach-Object { if ($null -ne $_.'Est. annual savings') { [double]$_.'Est. annual savings' } }) | Measure-Object -Sum).Sum, 2) } else { $null })
            SavingsCurrency            = $(if ($currencies.Count -eq 1) { $currencies[0] } elseif ($currencies.Count -gt 1) { 'mixed' } else { '' })
            CostTagCoverage            = $(if ($resources) { [Math]::Round($taggedCount / $resources * 100, 1) } else { $null })
            SubscriptionsWithoutBudget = $(if ($BudgetRead) { @($budgetRows | Where-Object Status -EQ 'No budget').Count } else { $null })
            BudgetsOver                = $(if ($BudgetRead) { @($budgetRows | Where-Object Status -In 'Over budget', 'Forecast over').Count } else { $null })
        }
    }
}
