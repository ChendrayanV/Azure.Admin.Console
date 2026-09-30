function Invoke-AACGraphBatch {
    <#
    .SYNOPSIS
        Runs several Azure Resource Graph queries at once - up to
        -ThrottleLimit in flight - and returns each one's rows by name.
    .DESCRIPTION
        A command that needs its subscriptions, resources, NICs and subnets
        asks for them all together instead of one after the other, so the
        read takes about as long as the slowest query. Each query still
        follows its own $skipToken pages in order.

        -Query maps a name to a query: a string, or a hashtable
        @{ Query; SubscriptionId; ManagementGroupId; Tenant } to scope that
        one query differently. -SubscriptionId / -ManagementGroupId scope
        the rest; Tenant = $true runs a query across everything the account
        can see, whatever the default.

        Rows are hashtables (ConvertFrom-Json -AsHashtable: tags whose keys
        differ only by case are fine), or objects with -AsObject, as
        Invoke-AACResourceGraphQuery returns them.

        Resource Graph allows about 15 queries per 5 seconds per user, so 4
        at a time (Invoke-AACHttpBatch); a throttled (429) or failed (5xx)
        query is retried as its x-ms-user-quota-resets-after or Retry-After
        header asks. A query that fails otherwise throws with
        Azure's reason - unless its name is in -AllowFailure: then its rows
        are empty and the reason is in Errors.

        -OnProgress is called with (name, done, total) as each query
        finishes. Returns @{ Rows = @{ name = rows[] }; Errors = @{ name =
        reason } }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Query,

        [string[]] $SubscriptionId,

        [string[]] $ManagementGroupId,

        [switch] $AsObject,

        [string[]] $AllowFailure,

        [scriptblock] $OnProgress,

        [ValidateRange(1, 16)]
        [int] $ThrottleLimit = 4
    )

    $graphUri = '/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01'
    $rows = @{}
    $bodies = @{}
    $requests = @(foreach ($name in @($Query.Keys)) {
            $spec = $Query[$name]
            if ($spec -isnot [System.Collections.IDictionary]) { $spec = @{ Query = [string]$spec } }
            $body = @{ query = [string]$spec['Query']; options = @{ resultFormat = 'objectArray'; '$top' = 1000 } }
            if (-not $spec['Tenant']) {
                $subscriptions = if ($spec.Contains('SubscriptionId')) { $spec['SubscriptionId'] } else { $SubscriptionId }
                $groups = if ($spec.Contains('ManagementGroupId')) { $spec['ManagementGroupId'] } else { $ManagementGroupId }
                if ($subscriptions) { $body.subscriptions = @($subscriptions) }
                elseif ($groups) { $body.managementGroups = @($groups) }
            }
            $rows[$name] = [System.Collections.Generic.List[object]]::new()
            $bodies[$name] = $body
            @{ Key = $name; Uri = $graphUri; Body = ($body | ConvertTo-Json -Depth 10) }
        })

    # Each page: its rows; a $skipToken means the same query again for the next.
    $onResponse = {
        param($Name, [string] $Content)
        if ($AsObject) {
            $page = ConvertFrom-Json -InputObject $Content -Depth 100
            $data = Get-AACPropertyValue -InputObject $page -Name 'data'
            $skipToken = Get-AACPropertyValue -InputObject $page -Name '$skipToken'
            $truncated = Get-AACPropertyValue -InputObject $page -Name 'resultTruncated'
        }
        else {
            $page = ConvertFrom-Json -InputObject $Content -AsHashtable -Depth 100
            $data = $page['data']
            $skipToken = $page['$skipToken']
            $truncated = $page['resultTruncated']
        }
        foreach ($row in @($data)) { if ($null -ne $row) { $rows[$Name].Add($row) } }
        # Truncated with no next page: the query can't be paged (it has no id
        # column) - say so rather than return part of the answer as all of it.
        if (-not $skipToken -and "$truncated" -eq 'true') {
            Write-Warning "Azure Resource Graph returned only part of the '$Name' results ($($rows[$Name].Count) rows) and no next page."
        }
        if ($skipToken) {
            $bodies[$Name].options['$skipToken'] = $skipToken
            @{ Uri = $graphUri; Body = ($bodies[$Name] | ConvertTo-Json -Depth 10) }
        }
    }
    $onDone = { param($Name, $Failure, $Done, $Total) if ($OnProgress) { & $OnProgress $Name $Done $Total } }
    $failures = Invoke-AACHttpBatch -Request $requests -OnResponse $onResponse -OnDone $onDone -ThrottleLimit $ThrottleLimit

    $result = @{}
    $errors = @{}
    foreach ($name in @($Query.Keys)) {
        $failure = $failures[$name]
        if ($failure) {
            if ($AllowFailure -notcontains $name) { throw $failure }
            $errors[$name] = $failure
            $result[$name] = @()
        }
        else {
            $result[$name] = $rows[$name].ToArray()
        }
    }
    @{ Rows = $result; Errors = $errors }
}
