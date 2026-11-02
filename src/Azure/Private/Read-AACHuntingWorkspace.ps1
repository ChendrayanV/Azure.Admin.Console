function Read-AACHuntingWorkspace {
    <#
    .SYNOPSIS
        Reads what the hunting query commands need to know about a workspace.
    .DESCRIPTION
        Azure Resource Manager: the workspace, whether Sentinel is enabled, its
        saved searches in the Hunting Queries category and its watchlists. KQL:
        the tables that received data in the last -Days. With
        -SavedSearchesOnly, only the workspace and its saved searches.

        Returns @{ ResourceId; Name; WorkspaceId; ResourceGroup; SentinelEnabled;
        SavedSearches (the items); Tables and Watchlists (lower-case names ->
        $true, or $null when they couldn't be read); Errors (what -> why) }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $Target,

        [string[]] $SubscriptionId,

        [string] $ResourceGroupName,

        [ValidateRange(1, 90)]
        [int] $Days = 30,

        [switch] $SavedSearchesOnly
    )

    $resourceId = Resolve-AACWorkspaceResourceId -Target $Target -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName
    $insights = "$resourceId/providers/Microsoft.SecurityInsights"
    $uris = [ordered]@{
        workspace     = "$resourceId`?api-version=2023-09-01"
        # The version Microsoft's own solutions deploy hunting queries with.
        savedSearches = "$resourceId/savedSearches?api-version=2025-07-01"
    }
    if (-not $SavedSearchesOnly) {
        $uris['onboarding'] = "$insights/onboardingStates?api-version=2025-09-01"
        $uris['watchlists'] = "$insights/watchlists?api-version=2025-09-01"
    }
    $read = Invoke-AACArmParallel -Uri @($uris.Values)
    $found = $read[$uris['workspace']]
    if ($found.Error -or $found.Body -isnot [System.Collections.IDictionary]) {
        $problem = [System.InvalidOperationException]::new("Azure Admin Console couldn't read the workspace $resourceId`: $($found.Error)")
        if ($found.Status -in 401, 403) { $problem.Data['AACHint'] = 'Your account needs Reader (or Microsoft Sentinel Reader) on the workspace.' }
        throw $problem
    }
    $errors = [ordered]@{}
    $items = {
        param([string] $Key, [string] $Label)
        $result = $read[$uris[$Key]]
        if ($result.Error) { $errors[$Label] = "$($result.Error)$(if ($result.Status -in 401, 403) { ' (needs Microsoft Sentinel Reader or Log Analytics Reader on the workspace)' })"; return }
        @($result.Items | Where-Object { $null -ne $_ })
    }
    $savedRows = @(& $items 'savedSearches' 'Saved searches')
    $hunting = @($savedRows | Where-Object { $properties = $_['properties']; $properties -is [System.Collections.IDictionary] -and [string]$properties['category'] -eq 'Hunting Queries' })
    $customerId = [string]$found.Body['properties']['customerId']

    $sentinelEnabled = $true
    $tables = $null
    $watchlists = $null
    if (-not $SavedSearchesOnly) {
        # As in the assessment: a list that couldn't be read says nothing, so carry on.
        $onboarding = $read[$uris['onboarding']]
        $sentinelEnabled = -not ($onboarding.Status -eq 404 -or (-not $onboarding.Error -and -not @($onboarding.Items | Where-Object { $_ }).Count))
        if ($onboarding.Error -and $onboarding.Status -ne 404) { $errors['Onboarding state'] = [string]$onboarding.Error }
        if ($sentinelEnabled) {
            if (-not $read[$uris['watchlists']].Error) {
                $watchlists = @{}
                foreach ($row in @(& $items 'watchlists' 'Watchlists')) {
                    $alias = [string]$row['properties']['watchlistAlias']
                    if ($alias) { $watchlists[$alias.ToLowerInvariant()] = $true }
                }
            }
            else { $null = & $items 'watchlists' 'Watchlists' }
            $kql = Invoke-AACLogQueryBatch -WorkspaceId $customerId -Timespan "P$($Days)D" -Query ([ordered]@{ tables = "Usage | where TimeGenerated > ago($($Days)d) | distinct DataType" })
            if ($kql.Errors.Contains('tables')) { $errors['Tables with data (Usage)'] = [string]$kql.Errors['tables'] }
            else {
                $tables = @{}
                foreach ($row in @($kql.Rows['tables'] | Where-Object { $null -ne $_ })) { $tables[([string]$row['DataType']).ToLowerInvariant()] = $true }
            }
        }
    }
    $segments = $resourceId -split '/'
    @{
        ResourceId = $resourceId; Name = [string]$found.Body['name']; WorkspaceId = $customerId; ResourceGroup = $segments[4]
        SentinelEnabled = $sentinelEnabled; SavedSearches = $hunting; Tables = $tables; Watchlists = $watchlists; Errors = $errors
    }
}
