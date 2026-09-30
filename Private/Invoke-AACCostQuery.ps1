function Invoke-AACCostQuery {
    <#
    .SYNOPSIS
        Runs a Cost Management query for one subscription and returns its
        rows as objects with one property per column.
    .DESCRIPTION
        POST https://management.azure.com/subscriptions/<id>/providers/
        Microsoft.CostManagement/query (api-version 2023-11-01), following
        nextLink paging. The response's column/row arrays become objects, so
        a query grouped by ServiceName returns rows like
        @{ Cost = 12.3; ServiceName = 'Storage'; Currency = 'USD' }.

        Cost Management allows only a few queries per minute per scope, so a
        throttled (429) or transient (5xx) response is retried up to five
        times, waiting as long as the response's
        x-ms-ratelimit-microsoft.costmanagement-*-retry-after or Retry-After
        header asks (5-60 seconds otherwise). Any other error is thrown with
        Azure's own message.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $SubscriptionId,

        [Parameter(Mandatory)]
        [hashtable] $Body
    )

    # No web-request progress bar over the caller's Spectre display.
    $ProgressPreference = 'SilentlyContinue'
    $uri = "https://management.azure.com/subscriptions/$SubscriptionId/providers/Microsoft.CostManagement/query?api-version=2023-11-01"
    $json = $Body | ConvertTo-Json -Depth 10

    while ($uri) {
        # Through the pooled HttpClient: Invoke-AACHttp retries throttling as
        # long as Cost Management's retry-after headers ask, and gives its
        # own error message. Months arrive as [datetime], as they did from
        # Invoke-RestMethod.
        try {
            $content = (Invoke-AACHttp -Method Post -Uri $uri -Body $json).Content
        }
        catch {
            throw $_.Exception.Message
        }
        $response = ConvertFrom-Json -InputObject $content -Depth 100

        $properties = Get-AACPropertyValue -InputObject $response -Name 'properties'
        $columns = @(Get-AACPropertyValue -InputObject $properties -Name 'columns' | ForEach-Object { $_.name })
        foreach ($row in @(Get-AACPropertyValue -InputObject $properties -Name 'rows')) {
            $item = [ordered]@{}
            for ($i = 0; $i -lt $columns.Count; $i++) {
                $item[$columns[$i]] = $row[$i]
            }
            [pscustomobject]$item
        }
        $uri = Get-AACPropertyValue -InputObject $properties -Name 'nextLink'
    }
}
