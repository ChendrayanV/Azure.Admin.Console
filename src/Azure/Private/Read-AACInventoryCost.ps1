function Read-AACInventoryCost {
    <#
    .SYNOPSIS
        Reads the actual cost of every resource - month to date and last
        month - for Get-AACInventory -Cost, as few Cost Management queries as
        the billing account allows.
    .DESCRIPTION
        One query, grouped by ResourceId and SubscriptionId, monthly, from
        the first of last month to today:
          - at management-group scope first - -ManagementGroupId, or the
            tenant root group - one query for everything. Cost Management
            answers there for Enterprise Agreement and Microsoft Customer
            Agreement billing, not pay-as-you-go
          - otherwise (or with -PerSubscription: a subscription or resource
            group selection) once per subscription, three at a time
            (Invoke-AACCostBatch)
        Subscriptions that are disabled, deleted or expired aren't asked.

        Returns @{ Rows; Status (subscription ID -> 'OK' or why it couldn't
        be read); ThisMonth; LastMonth ('yyyy-MM'); Period; Notice }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string] $TenantId,

        # Rows with subscriptionId, name and state.
        [AllowEmptyCollection()]
        [object[]] $Subscription = @(),

        [string[]] $ManagementGroupId,

        [switch] $PerSubscription
    )

    $invariant = [cultureinfo]::InvariantCulture
    $today = (Get-Date).Date
    $thisMonth = [datetime]::new($today.Year, $today.Month, 1)
    $lastMonth = $thisMonth.AddMonths(-1)
    $body = @{
        type       = 'ActualCost'
        timeframe  = 'Custom'
        timePeriod = @{ from = $lastMonth.ToString('yyyy-MM-ddT00:00:00Z', $invariant); to = $today.ToString('yyyy-MM-ddT23:59:59Z', $invariant) }
        dataset    = @{
            granularity = 'Monthly'
            aggregation = @{ totalCost = @{ name = 'Cost'; function = 'Sum' } }
            grouping    = @(
                @{ type = 'Dimension'; name = 'ResourceId' }
                @{ type = 'Dimension'; name = 'SubscriptionId' }
            )
        }
    }
    $value = { param($Row, [string] $Key) if ($Row -is [System.Collections.IDictionary]) { $Row[$Key] } else { Get-AACPropertyValue -InputObject $Row -Name $Key } }
    $result = @{
        Rows      = @()
        Status    = @{}
        ThisMonth = $thisMonth.ToString('yyyy-MM', $invariant)
        LastMonth = $lastMonth.ToString('yyyy-MM', $invariant)
        Period    = "actual cost, $($thisMonth.ToString('MMM yyyy')) to date and $($lastMonth.ToString('MMM yyyy'))"
        Notice    = @()
    }
    $ids = @($Subscription | ForEach-Object { ([string](& $value $_ 'subscriptionId')).ToLowerInvariant() } | Where-Object { $_ } | Select-Object -Unique)
    if (-not $ids.Count) { return $result }

    # --- One query for the whole scope, when Cost Management allows it -----------------------------
    $groups = @(if ($ManagementGroupId) { $ManagementGroupId } elseif ($TenantId) { $TenantId })
    if (-not $PerSubscription -and $groups.Count) {
        Update-AACProgress -Id 'cost' -Total $groups.Count -Description "Reading costs for the management group$(if ($groups.Count -ne 1) { 's' })"
        $read = Invoke-AACCostBatch -Scope @($groups | ForEach-Object { "/providers/Microsoft.Management/managementGroups/$_" }) -Body $body -OnProgress {
            param($Scope, $Status, $Done, $Total)
            Update-AACProgress -Id 'cost' -Increment 1
        }
        $failed = @($read.Values | Where-Object { $_.Status -ne 'OK' })
        if (-not $failed.Count) {
            $result.Rows = @($read.Values | ForEach-Object { $_.Rows })
            foreach ($id in $ids) { $result.Status[$id] = 'OK' }
            Update-AACProgress -Id 'cost' -Complete -Description ('Cost Management: {0:N0} cost row(s) for {1:N0} subscription(s), in one query per management group' -f $result.Rows.Count, $ids.Count)
            return $result
        }
        Write-Verbose "Cost Management didn't answer for the management group ($($failed[0].Status)); reading each subscription instead."
        Update-AACProgress -Id 'cost' -Complete -Description 'Cost Management: not available for the management group - reading each subscription'
    }

    # --- Otherwise once per subscription, three at a time -------------------------------------------------
    $names = @{}
    $scopes = [System.Collections.Generic.List[string]]::new()
    foreach ($row in $Subscription) {
        $id = ([string](& $value $row 'subscriptionId')).ToLowerInvariant()
        if (-not $id -or $names.Contains($id)) { continue }
        $names[$id] = [string](& $value $row 'name')
        $state = [string](& $value $row 'state')
        if ($state -in 'Disabled', 'Deleted', 'Expired') { $result.Status[$id] = "Not read: the subscription is $state."; continue }
        $scopes.Add("/subscriptions/$id")
    }
    Update-AACProgress -Id 'cost' -Total ([Math]::Max(1, $scopes.Count)) -Description "Reading costs for $($scopes.Count) subscription(s)"
    $read = Invoke-AACCostBatch -Scope $scopes.ToArray() -Body $body -OnProgress {
        param($Scope, $Status, $Done, $Total)
        $id = $Scope -replace '^/subscriptions/', ''
        Update-AACProgress -Id 'cost' -Increment 1 -Description "Read costs: $(if ($names[$id]) { $names[$id] } else { $id }) ($Done of $Total)"
    }
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($scope in $scopes) {
        $id = $scope -replace '^/subscriptions/', ''
        $entry = if ($read.Contains($scope)) { $read[$scope] } else { @{ Rows = @(); Status = 'Not read.' } }
        $result.Status[$id] = $entry.Status
        foreach ($row in @($entry.Rows)) { $rows.Add($row) }
    }
    $result.Rows = $rows.ToArray()
    $unread = @($result.Status.Values | Where-Object { $_ -ne 'OK' }).Count
    Update-AACProgress -Id 'cost' -Complete -Description ('Cost Management: {0:N0} subscription(s) read{1}' -f ($ids.Count - $unread), $(if ($unread) { ", $unread could not be" }))
    if ($unread) {
        $result.Notice = @("The cost of $unread subscription(s) couldn't be read (the subscription's CostStatus says why); they show no cost.")
    }
    $result
}
