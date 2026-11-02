function Resolve-AACWorkspaceResourceId {
    <#
    .SYNOPSIS
        Turns a Log Analytics workspace's workspace ID (GUID), resource ID or
        name into its resource ID.
    .DESCRIPTION
        A resource ID is used as it is, with no Azure call. A workspace ID is
        looked up with Azure Resource Graph, and a name with
        Resolve-AACLogResource. A workspace ID nothing matches is an error
        that says where to find the right one.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Target,

        [string[]] $SubscriptionId,

        # Narrows a workspace given by name.
        [string] $ResourceGroupName
    )

    $resourceId = if ($Target -match '^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.OperationalInsights/workspaces/[^/]+$') {
        $Target
    }
    elseif ($Target -match '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$') {
        $found = Invoke-AACGraphBatch -SubscriptionId $SubscriptionId -Query @{ workspace = "resources | where type =~ 'microsoft.operationalinsights/workspaces' and tostring(properties.customerId) =~ '$($Target.ToLowerInvariant())' | project id" }
        $ids = @($found.Rows['workspace'] | ForEach-Object { [string]$_['id'] })
        if (-not $ids.Count) {
            $problem = [System.InvalidOperationException]::new("No Log Analytics workspace with workspace ID $Target was found$(if ($SubscriptionId) { " in subscription $($SubscriptionId -join ', ')" } else { ' in the subscriptions the account can see' }).")
            $problem.Data['AACHint'] = 'The workspace ID is on the workspace''s Overview page in the portal. You can also pass its resource ID or name.'
            throw $problem
        }
        $ids[0]
    }
    else {
        (Resolve-AACLogResource -Kind Workspace -Name $Target -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName).Id
    }
    $resourceId.TrimEnd('/')
}
