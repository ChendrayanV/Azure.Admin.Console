function Get-AACWorkspaceComponent {
    <#
    .SYNOPSIS
        Lists the Application Insights resources in the given subscriptions
        (all visible ones by default), with the Log Analytics workspace each
        sends its data to.
    .DESCRIPTION
        A workspace's AppExceptions table only holds the exceptions of the
        workspace-based Application Insights resources that send to that
        workspace. When a workspace has none, Invoke-AACApplicationInsightQuery
        uses this to say which resources do send there - and where the
        others send - instead of an unexplained empty result.

        Returns objects with Name, ResourceGroup, SubscriptionId and
        WorkspaceId ('' for a classic resource, which keeps its own data).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]] $SubscriptionId
    )

    $query = "resources | where type =~ 'microsoft.insights/components' | project name, resourceGroup, subscriptionId, workspaceId = tostring(properties.WorkspaceResourceId) | order by name asc"
    $headers = @{ Authorization = "Bearer $(Get-AACAccessToken)" }
    foreach ($row in @(Invoke-AACResourceGraphQuery -SubscriptionId $SubscriptionId -Headers $headers -Query $query)) {
        [pscustomobject]@{
            Name           = [string](Get-AACPropertyValue -InputObject $row -Name 'name')
            ResourceGroup  = [string](Get-AACPropertyValue -InputObject $row -Name 'resourceGroup')
            SubscriptionId = [string](Get-AACPropertyValue -InputObject $row -Name 'subscriptionId')
            WorkspaceId    = [string](Get-AACPropertyValue -InputObject $row -Name 'workspaceId')
        }
    }
}
