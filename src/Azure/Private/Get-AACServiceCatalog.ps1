function Get-AACServiceCatalog {
    <#
    .SYNOPSIS
        The Azure services Azure itself lists, each with its resource types
        (GET /providers/Microsoft.Support/services).
    .DESCRIPTION
        The list behind the portal's New support request page, so the names are
        the ones people see there. It is read once per session: it is the same
        for everyone and hardly changes, and tab completion uses it.

        Classic types are left out, because nothing new is planned on them. A
        service may have no types at all (Billing, say): it stays in the list,
        so it can be told apart from a name Azure doesn't know.

        Returns @{ Id; Name; ResourceTypes } for each service, by name. The types
        are as Azure sends them, in upper case.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    if ($null -ne $script:AACServiceCatalog) { return $script:AACServiceCatalog }

    $uri = '/providers/Microsoft.Support/services?api-version=2024-04-01'
    $answer = (Invoke-AACArmParallel -Uri @($uri))[$uri]
    if ($answer['Error']) {
        $problem = [System.InvalidOperationException]::new("Azure Admin Console couldn't read Azure's list of services: $($answer['Error'])")
        $problem.Data['AACHint'] = 'Run Connect-AAC again. FunctionApp, StorageAccount, EventHub and EventGrid can be planned without the list.'
        throw $problem
    }
    $services = @(foreach ($item in @($answer['Items'] | Where-Object { $_ })) {
            $properties = $item['properties']
            if (-not $properties -or -not $properties['displayName']) { continue }
            @{
                Id            = [string]$item['name']
                Name          = [string]$properties['displayName']
                ResourceTypes = @($properties['resourceTypes'] | Where-Object { $_ -and $_ -notmatch '(?i)^microsoft\.classic' } | ForEach-Object { [string]$_ })
            }
        })
    $script:AACServiceCatalog = @($services | Sort-Object -Property { $_.Name })
    $script:AACServiceCatalog
}
