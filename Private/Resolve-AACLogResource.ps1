function Resolve-AACLogResource {
    <#
    .SYNOPSIS
        Finds a Log Analytics workspace or an Application Insights resource
        by name with Azure Resource Graph, and returns its ID.
    .DESCRIPTION
        -Kind Workspace looks for microsoft.operationalinsights/workspaces,
        -Kind Component for microsoft.insights/components. A name found in
        more than one place must be narrowed with -SubscriptionId or
        -ResourceGroupName; the error lists where it was found.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Workspace', 'Component')]
        [string] $Kind,

        [Parameter(Mandatory)]
        [string] $Name,

        [string[]] $SubscriptionId,

        [string] $ResourceGroupName
    )

    $type = @{ Workspace = 'microsoft.operationalinsights/workspaces'; Component = 'microsoft.insights/components' }[$Kind]
    $noun = @{ Workspace = 'Log Analytics workspace'; Component = 'Application Insights resource' }[$Kind]
    $quote = { param([string] $Text) "'" + ($Text -replace '\\', '\\' -replace "'", "\'") + "'" }
    $query = "resources | where type =~ '$type' and name =~ $(& $quote $Name)"
    if ($ResourceGroupName) { $query += " and resourceGroup =~ $(& $quote $ResourceGroupName)" }
    $query += ' | project id, name, resourceGroup, subscriptionId, location, customerId = tostring(properties.customerId), appId = tostring(properties.AppId), workspaceId = tostring(properties.WorkspaceResourceId)'

    $headers = @{ Authorization = "Bearer $(Get-AACAccessToken)" }
    $rows = @(Invoke-AACResourceGraphQuery -SubscriptionId $SubscriptionId -Headers $headers -Query $query)
    if ($rows.Count -eq 0) {
        $where = if ($SubscriptionId) { " in subscription $($SubscriptionId -join ', ')" } else { ' in any subscription the signed-in account can see' }
        throw "No $noun named '$Name' was found$where$(if ($ResourceGroupName) { " (resource group $ResourceGroupName)" })."
    }
    if ($rows.Count -gt 1) {
        $places = ($rows | ForEach-Object { "$($_.subscriptionId)/$($_.resourceGroup)" }) -join '; '
        throw "More than one $noun is named '$Name' ($places). Add -SubscriptionId or -ResourceGroupName."
    }
    $row = $rows[0]
    [pscustomobject]@{
        Kind           = $Kind
        Id             = [string]$row.id
        Name           = [string]$row.name
        ResourceGroup  = [string]$row.resourceGroup
        SubscriptionId = [string]$row.subscriptionId
        Location       = [string]$row.location
        # What the query APIs address it by: the workspace ID (customerId)
        # or the Application Insights app ID.
        QueryId        = [string](Get-AACPropertyValue -InputObject $row -Name $(if ($Kind -eq 'Workspace') { 'customerId' } else { 'appId' }))
    }
}
