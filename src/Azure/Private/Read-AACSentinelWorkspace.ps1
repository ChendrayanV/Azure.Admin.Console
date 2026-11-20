function Read-AACSentinelWorkspace {
    <#
    .SYNOPSIS
        Finds a Microsoft Sentinel workspace and reads what one of the
        Get-AACSentinel* commands asks for: Resource Manager lists and KQL.
    .DESCRIPTION
        -Target is the workspace ID (GUID), resource ID or name
        (Resolve-AACWorkspaceResourceId). The workspace and its Sentinel
        onboarding state are read first; a workspace without Sentinel is an
        error that says what to do, because every list would be empty.

        -Arm maps a name to a path under the workspace's resource ID, such as
        'providers/Microsoft.SecurityInsights/incidents?api-version=...'. Every
        page is read (Invoke-AACArmParallel). -Kql maps a name to a query, or
        to @{ Query; Timespan }, run in the workspace (Invoke-AACLogQueryBatch).

        Returns @{ ResourceId; Name; WorkspaceId (customerId); ResourceGroup;
        SubscriptionId; Workspace (the GET body); Arm (name -> the
        Invoke-AACArmParallel result); Kql (@{ Rows; Errors }) }. A list or
        query that fails is in Arm/Kql with its error: the caller decides
        whether that stops it.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $Target,

        [string[]] $SubscriptionId,

        [string] $ResourceGroupName,

        [System.Collections.IDictionary] $Arm = [ordered]@{},

        [System.Collections.IDictionary] $Kql = [ordered]@{},

        # The ISO 8601 duration the KQL queries are bounded by, such as P30D.
        [string] $Timespan
    )

    $resourceId = Resolve-AACWorkspaceResourceId -Target $Target -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName
    $workspaceUri = "$resourceId`?api-version=2023-09-01"
    $onboardingUri = "$resourceId/providers/Microsoft.SecurityInsights/onboardingStates?api-version=2025-09-01"
    $first = Invoke-AACArmParallel -Uri @($workspaceUri, $onboardingUri)
    $found = $first[$workspaceUri]
    if ($found.Error -or $found.Body -isnot [System.Collections.IDictionary]) {
        $problem = [System.InvalidOperationException]::new("Azure Admin Console couldn't read the workspace $resourceId`: $($found.Error)")
        if ($found.Status -in 401, 403) { $problem.Data['AACHint'] = 'Your account needs Reader (or Microsoft Sentinel Reader) on the workspace.' }
        throw $problem
    }
    $workspace = $found.Body
    $name = [string]$workspace['name']
    # A 404 or an empty list means Sentinel isn't on. An onboarding state that
    # can't be read (no permission) isn't proof either way, so carry on.
    $onboarding = $first[$onboardingUri]
    if ($onboarding.Status -eq 404 -or (-not $onboarding.Error -and -not @($onboarding.Items | Where-Object { $_ }).Count)) {
        $problem = [System.InvalidOperationException]::new("Azure Admin Console found no Microsoft Sentinel on the workspace $name.")
        $problem.Data['AACHint'] = 'Point -WorkspaceId at the workspace Sentinel is enabled on, or enable Sentinel on this one. Invoke-AACSentinelAssessment checks a workspace either way.'
        throw $problem
    }

    $armRead = @{}
    if ($Arm.Count) {
        $uris = [ordered]@{}
        foreach ($key in $Arm.Keys) { $uris[$key] = "$resourceId/$(([string]$Arm[$key]).TrimStart('/'))" }
        $read = Invoke-AACArmParallel -Uri @($uris.Values)
        foreach ($key in $uris.Keys) { $armRead[$key] = $read[$uris[$key]] }
    }
    $customerId = [string]$workspace['properties']['customerId']
    $kqlRead = @{ Rows = @{}; Errors = @{} }
    if ($Kql.Count) {
        $batch = @{ WorkspaceId = $customerId; Query = $Kql }
        if ($Timespan) { $batch.Timespan = $Timespan }
        $kqlRead = Invoke-AACLogQueryBatch @batch
    }

    $segments = $resourceId -split '/'
    @{
        ResourceId     = $resourceId
        Name           = $name
        WorkspaceId    = $customerId
        ResourceGroup  = $(if ($segments.Count -gt 4) { $segments[4] } else { '' })
        SubscriptionId = $(if ($segments.Count -gt 2) { $segments[2] } else { '' })
        Workspace      = $workspace
        Arm            = $armRead
        Kql            = $kqlRead
    }
}
