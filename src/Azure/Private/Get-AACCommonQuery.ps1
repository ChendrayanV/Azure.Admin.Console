function Get-AACCommonQuery {
    <#
    .SYNOPSIS
        The Resource Graph queries several assessments share, written once:
        a Defender plan per subscription, Defender alerts on a resource
        type, and the Log Analytics workspaces' names.
    .DESCRIPTION
          DefenderPlan   -Plan (StorageAccounts, KeyVaults, CosmosDbs...):
                         subscriptionId, tier
          DefenderAlert  alerts of the last 30 days on -ResourceType
                         (lower case, such as
                         'microsoft.storage/storageaccounts'), narrowed by
                         -Filter (a KQL fragment such as
                         " | where resourceGroup in~ (...)"): resourceId,
                         name, severity, status
          WorkspaceName  every workspace, tenant-wide (an account's logs
                         often go to another subscription's): id, name - as
                         the @{ Tenant; Query } spec Invoke-AACGraphBatch takes
    #>
    [CmdletBinding()]
    [OutputType([string], [hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('DefenderPlan', 'DefenderAlert', 'WorkspaceName')]
        [string] $Kind,

        [string] $Plan,

        [string] $ResourceType,

        [string] $Filter = ''
    )

    switch ($Kind) {
        'DefenderPlan' { "securityresources | where type =~ 'microsoft.security/pricings' and name =~ $(ConvertTo-AACKqlLiteral -Text $Plan) | project subscriptionId = tolower(subscriptionId), tier = tostring(properties.pricingTier)" }
        'DefenderAlert' { "securityresources | where type =~ 'microsoft.security/locations/alerts' and tostring(properties.resourceIdentifiers) contains '$ResourceType'$Filter | where todatetime(properties.timeGeneratedUtc) > ago(30d) | mv-expand rid = properties.resourceIdentifiers | where tostring(rid.azureResourceId) contains '$ResourceType' | project resourceId = tolower(tostring(rid.azureResourceId)), name = tostring(properties.alertDisplayName), severity = tostring(properties.severity), status = tostring(properties.status)" }
        'WorkspaceName' { @{ Tenant = $true; Query = "resources | where type =~ 'microsoft.operationalinsights/workspaces' | project id = tolower(id), name" } }
    }
}
