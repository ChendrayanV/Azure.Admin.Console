function Get-AACResourceInventory {
    <#
    .SYNOPSIS
        Lists every Azure resource (name, type, location, resource group) in
        the subscriptions the signed-in account can see, without rendering
        anything.
    .DESCRIPTION
        Subscriptions come from the ARM subscriptions endpoint (only Enabled
        ones are queried); resources come from one Azure Resource Graph query
        per subscription, rather than a REST call per resource group.

        Resource groups themselves are not included - Resource Graph keeps
        them in a separate table (ResourceContainers) - only the resources
        inside them.

        Nothing is written to the console on purpose: this runs during Pester
        discovery inside Invoke-AACPester's spinner, and Spectre
        allows only one live display at a time.

        Location is returned as Azure stores it on the resource ("uksouth",
        "global", ...); NormalizedLocation is the same value lower-cased with
        spaces removed, so "UK South" and "uksouth" compare equal.
    .PARAMETER SubscriptionId
        Limit the inventory to these subscriptions. Defaults to every Enabled
        subscription the signed-in account can see.
    #>
    [CmdletBinding()]
    [OutputType('AAC.Resource')]
    param(
        [string[]] $SubscriptionId
    )

    $accessToken = Get-AACAccessToken
    $headers = @{ Authorization = "Bearer $accessToken" }

    $subscriptions = @(Invoke-AACPagedRestMethod -Uri 'https://management.azure.com/subscriptions?api-version=2020-01-01' -Headers $headers)
    $subscriptions = @($subscriptions | Where-Object { (Get-AACPropertyValue -InputObject $_ -Name 'state') -eq 'Enabled' })
    if ($SubscriptionId) {
        $subscriptions = @($subscriptions | Where-Object { (Get-AACPropertyValue -InputObject $_ -Name 'subscriptionId') -in $SubscriptionId })
        $unknown = @($SubscriptionId | Where-Object { $_ -notin @($subscriptions | ForEach-Object { Get-AACPropertyValue -InputObject $_ -Name 'subscriptionId' }) })
        if ($unknown.Count -gt 0) {
            throw "These subscription(s) are not visible to the signed-in account, or not Enabled: $($unknown -join ', ')"
        }
    }

    foreach ($subscription in $subscriptions) {
        $id = Get-AACPropertyValue -InputObject $subscription -Name 'subscriptionId'
        $subscriptionName = Get-AACPropertyValue -InputObject $subscription -Name 'displayName'

        $resources = Invoke-AACResourceGraphQuery -SubscriptionId $id -Headers $headers -Query 'Resources | project id, name, type, location, resourceGroup | order by type asc, name asc'
        foreach ($resource in $resources) {
            $location = [string](Get-AACPropertyValue -InputObject $resource -Name 'location')
            [pscustomobject]@{
                PSTypeName         = 'AAC.Resource'
                SubscriptionId     = $id
                SubscriptionName   = $subscriptionName
                ResourceGroup      = Get-AACPropertyValue -InputObject $resource -Name 'resourceGroup'
                Type               = Get-AACPropertyValue -InputObject $resource -Name 'type'
                Name               = Get-AACPropertyValue -InputObject $resource -Name 'name'
                Location           = $location
                NormalizedLocation = ($location -replace '\s', '').ToLowerInvariant()
                Id                 = Get-AACPropertyValue -InputObject $resource -Name 'id'
            }
        }
    }
}
