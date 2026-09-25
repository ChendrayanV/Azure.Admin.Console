function Invoke-AACResourceGraphQuery {
    <#
    .SYNOPSIS
        Runs a Kusto query against Azure Resource Graph for one or more
        subscriptions (or every subscription the signed-in account can see),
        following $skipToken pagination, and returns every result row.
    .DESCRIPTION
        Wraps POST https://management.azure.com/providers/Microsoft.ResourceGraph/resources
        (api-version 2022-10-01). Resource Graph pages differently to a plain
        ARM list endpoint: instead of a nextLink URL, a response can carry a
        "$skipToken" that has to be echoed back inside the *next* request's
        "options" object (together with the same query and subscription) to
        get the next page; its absence means there is no more data.

        Resource Graph is used here (rather than one REST call per resource)
        because it can answer "every virtual network / NSG / route table in
        this subscription" in a single call each, no matter how many exist -
        the alternative is a REST call per resource, which does not scale.

        Leave -SubscriptionId out to query every subscription the signed-in
        account can see, in one request.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [string[]] $SubscriptionId,

        [Parameter(Mandatory)]
        [string] $Query,

        [Parameter(Mandatory)]
        [hashtable] $Headers
    )

    # No web-request progress bar or per-call verbose line: callers show their
    # own Spectre progress.
    $ProgressPreference = 'SilentlyContinue'
    $collected = [System.Collections.Generic.List[object]]::new()
    $skipToken = $null

    do {
        $requestBody = @{
            query = $Query
        }
        if ($SubscriptionId) {
            $requestBody.subscriptions = @($SubscriptionId)
        }
        if ($skipToken) {
            $requestBody.options = @{ '$skipToken' = $skipToken }
        }

        $response = Invoke-RestMethod -Uri 'https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01' `
            -Method Post -Headers $Headers -ContentType 'application/json' `
            -Body ($requestBody | ConvertTo-Json -Depth 10) -ErrorAction Stop -Verbose:$false

        foreach ($item in $response.data) {
            $collected.Add($item)
        }

        $skipToken = Get-AACPropertyValue -InputObject $response -Name '$skipToken'
    } while ($skipToken)

    return $collected.ToArray()
}
