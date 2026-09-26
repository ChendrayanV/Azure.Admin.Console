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
        $response = $null
        for ($attempt = 1; ; $attempt++) {
            try {
                $headers = @{ Authorization = "Bearer $(Get-AACAccessToken)" }
                $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -ContentType 'application/json' -Body $json -ErrorAction Stop -Verbose:$false
                break
            }
            catch {
                $httpResponse = Get-AACPropertyValue -InputObject $_.Exception -Name 'Response'
                $status = if ($httpResponse) { [int]$httpResponse.StatusCode } else { 0 }
                if ($attempt -ge 5 -or ($status -ne 429 -and $status -lt 500)) {
                    $message = if ($_.ErrorDetails.Message) {
                        $details = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction Ignore
                        $inner = if ($details) { Get-AACPropertyValue -InputObject $details -Name 'error' }
                        if ($inner) { Get-AACPropertyValue -InputObject $inner -Name 'message' } else { $_.ErrorDetails.Message }
                    }
                    else { $_.Exception.Message }
                    throw $message
                }
                # The longest wait any rate-limit header asks for.
                $wait = 0
                if ($httpResponse) {
                    foreach ($header in $httpResponse.Headers) {
                        if ($header.Key -match 'retry-after$') {
                            foreach ($value in $header.Value) {
                                $seconds = 0
                                if ([int]::TryParse($value, [ref]$seconds)) { $wait = [Math]::Max($wait, $seconds) }
                            }
                        }
                    }
                }
                if ($wait -le 0) { $wait = 5 * $attempt }
                Start-Sleep -Seconds ([Math]::Min(60, $wait))
            }
        }

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
