function Invoke-AACCostBatch {
    <#
    .SYNOPSIS
        Runs one Cost Management query over several scopes at once - up to
        -ThrottleLimit in flight - and returns each scope's rows as objects.
    .DESCRIPTION
        The parallel counterpart of Invoke-AACCostQuery: the same body for
        each -Scope (a subscription, '/subscriptions/<id>', or a management
        group, '/providers/Microsoft.Management/managementGroups/<id>'),
        following nextLink paging, with the column/row arrays turned into
        objects - @{ Cost = 12.3; ResourceId = '...'; Currency = 'USD' }.
        Months arrive as [datetime], as ConvertFrom-Json reads ISO dates.

        Cost Management allows only a few queries a minute per scope and
        tenant, so 3 at a time; throttled requests wait as long as its
        x-ms-ratelimit-microsoft.costmanagement-*-retry-after headers ask
        (Invoke-AACHttpBatch).

        Returns a hashtable: scope -> @{ Rows; Status ('OK', or why that
        scope couldn't be read) }. -OnProgress is called with (scope, status,
        done, total) as each finishes.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Scope,

        [Parameter(Mandatory)]
        [hashtable] $Body,

        [scriptblock] $OnProgress,

        [ValidateRange(1, 8)]
        [int] $ThrottleLimit = 3
    )

    $json = $Body | ConvertTo-Json -Depth 10
    $rows = @{}
    $requests = @(foreach ($item in @($Scope | Where-Object { $_ } | Select-Object -Unique)) {
            $rows[$item] = [System.Collections.Generic.List[object]]::new()
            @{ Key = $item; Uri = "$($item.TrimEnd('/'))/providers/Microsoft.CostManagement/query?api-version=2023-11-01"; Body = $json }
        })
    $onResponse = {
        param($Key, [string] $Content)
        $page = ConvertFrom-Json -InputObject $Content -Depth 100
        $properties = Get-AACPropertyValue -InputObject $page -Name 'properties'
        $columns = @(Get-AACPropertyValue -InputObject $properties -Name 'columns' | ForEach-Object { $_.name })
        foreach ($row in @(Get-AACPropertyValue -InputObject $properties -Name 'rows')) {
            if ($null -eq $row) { continue }
            $item = [ordered]@{}
            for ($i = 0; $i -lt $columns.Count; $i++) { $item[$columns[$i]] = $row[$i] }
            $rows[$Key].Add([pscustomobject]$item)
        }
        $next = Get-AACPropertyValue -InputObject $properties -Name 'nextLink'
        if ($next) { @{ Uri = [string]$next; Body = $json } }
    }
    $onDone = {
        param($Key, $Failure, $Done, $Total)
        if ($OnProgress) { & $OnProgress $Key $(if ($Failure) { $Failure } else { 'OK' }) $Done $Total }
    }
    $failures = Invoke-AACHttpBatch -Request $requests -OnResponse $onResponse -OnDone $onDone -ThrottleLimit $ThrottleLimit

    $result = @{}
    foreach ($key in @($rows.Keys)) {
        $result[$key] = if ($failures[$key]) { @{ Rows = @(); Status = [string]$failures[$key] } } else { @{ Rows = $rows[$key].ToArray(); Status = 'OK' } }
    }
    $result
}
