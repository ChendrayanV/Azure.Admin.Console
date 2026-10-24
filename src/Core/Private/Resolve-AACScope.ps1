function Resolve-AACScope {
    <#
    .SYNOPSIS
        Finds the subscriptions a command covers: every one the account can
        see, those in -SubscriptionId, or those under -ManagementGroupId (at
        any depth) - from one Azure Resource Graph query.
    .DESCRIPTION
        A subscription asked for that the account can't see is left out with
        a warning; when none is left, it stops with what to do.

        Returns @{
          Subscriptions  the Resource Graph rows (subscriptionId, name,
                         state, chain - its management groups)
          Ids            their IDs
          GraphScope     the IDs to pass Invoke-AACGraphBatch -SubscriptionId:
                         none when unscoped (every query then covers
                         everything the account can see)
          Names          ID (lower case) -> name
          Label          'all subscriptions', '2 subscription(s)', 'management
                         group mg-corp'
        }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string[]] $SubscriptionId = @(),

        [string[]] $ManagementGroupId = @()
    )

    $wantedSubscriptions = @($SubscriptionId | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() })
    $wantedGroups = @($ManagementGroupId | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() })
    $read = Invoke-AACGraphBatch -Query ([ordered]@{ subscriptions = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions' | project id, subscriptionId, name, state = tostring(properties.state), chain = properties.managementGroupAncestorsChain" })
    $all = @($read.Rows['subscriptions'] | Where-Object { $null -ne $_ })
    $subscriptions = $all
    if ($wantedGroups.Count) {
        $subscriptions = @($subscriptions | Where-Object {
                $names = @(@($_['chain']) | Where-Object { $_ -is [System.Collections.IDictionary] } | ForEach-Object { ([string]$_['name']).ToLowerInvariant() })
                @($wantedGroups | Where-Object { $names -contains $_ }).Count
            })
        if (-not $subscriptions.Count) {
            $problem = [System.InvalidOperationException]::new("No subscription the account can see is under management group $($ManagementGroupId -join ', ').")
            $problem.Data['AACHint'] = 'Use the management group''s ID (its name), not its display name - and check the account has Reader on it.'
            throw $problem
        }
    }
    if ($wantedSubscriptions.Count) {
        foreach ($id in $wantedSubscriptions) { if (-not @($subscriptions | Where-Object { ([string]$_['subscriptionId']).ToLowerInvariant() -eq $id }).Count) { Write-Warning "Subscription $id isn't one the account can see$(if ($wantedGroups.Count) { ' under that management group' }); it's left out." } }
        $subscriptions = @($subscriptions | Where-Object { $wantedSubscriptions -contains ([string]$_['subscriptionId']).ToLowerInvariant() })
        if (-not $subscriptions.Count) { throw "None of the subscriptions $($SubscriptionId -join ', ') is one the account can see." }
    }
    if (-not $subscriptions.Count) {
        $problem = [System.InvalidOperationException]::new('The account can see no subscription.')
        $problem.Data['AACHint'] = 'Give the account Reader on the subscriptions (or a management group above them), or sign in to the right tenant with Connect-AAC -TenantId.'
        throw $problem
    }
    $names = @{}
    foreach ($row in $all) { $names[([string]$row['subscriptionId']).ToLowerInvariant()] = [string]$row['name'] }
    $ids = @($subscriptions | ForEach-Object { [string]$_['subscriptionId'] })
    $scoped = $wantedSubscriptions.Count -or $wantedGroups.Count
    @{
        Subscriptions = $subscriptions
        Ids           = $ids
        GraphScope    = $(if ($scoped) { $ids } else { @() })
        Names         = $names
        Label         = $(if ($wantedGroups.Count) { "management group $($ManagementGroupId -join ', ')" } elseif ($wantedSubscriptions.Count) { "$($ids.Count) subscription(s)" } else { "all $($ids.Count) subscription(s)" })
    }
}
