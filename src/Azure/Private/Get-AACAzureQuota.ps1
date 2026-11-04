function Get-AACAzureQuota {
    <#
    .SYNOPSIS
        Reads the compute, network and storage quota of each region a subscription
        has resources in, for Test-AACAzureLimit -IncludeQuota.
    .DESCRIPTION
        Quota is per subscription and region, and an API's answer lists everything
        whether it is used or not, so only regions with resources are asked. A
        provider a subscription hasn't registered answers 404 or 409, which means
        it has no quota in use: only other failures are reported.

        Returns @{ Rows (@{ SubscriptionId; Location; Service; Name; Used; Maximum });
        Notices }. -OnProgress is passed to Invoke-AACArmParallel.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Location,

        [scriptblock] $OnProgress
    )

    $services = @(
        @{ Service = 'Compute'; Provider = 'Microsoft.Compute'; Version = '2023-09-01' }
        @{ Service = 'Network'; Provider = 'Microsoft.Network'; Version = '2023-09-01' }
        @{ Service = 'Storage'; Provider = 'Microsoft.Storage'; Version = '2023-05-01' }
    )
    $asked = [ordered]@{}
    foreach ($row in $Location) {
        foreach ($entry in $services) {
            $uri = "/subscriptions/$($row['subscriptionId'])/providers/$($entry.Provider)/locations/$($row['location'])/usages?api-version=$($entry.Version)"
            $asked[$uri] = @{ SubscriptionId = ([string]$row['subscriptionId']).ToLowerInvariant(); Location = [string]$row['location']; Service = $entry.Service }
        }
    }
    $rows = [System.Collections.Generic.List[object]]::new()
    $notices = [System.Collections.Generic.List[string]]::new()
    if (-not $asked.Count) { return @{ Rows = @(); Notices = @() } }

    $parallel = @{ Uri = @($asked.Keys) }
    if ($OnProgress) { $parallel.OnProgress = $OnProgress }
    $answers = Invoke-AACArmParallel @parallel
    $refused = 0
    $firstError = ''
    foreach ($uri in $asked.Keys) {
        $answer = $answers[$uri]
        if (-not $answer -or $answer.Error) {
            if ($answer -and $answer.Status -in 404, 409) { continue }
            $refused++
            if (-not $firstError -and $answer) { $firstError = [string]$answer.Error }
            continue
        }
        $where = $asked[$uri]
        foreach ($item in @($answer.Items)) {
            if ($null -eq $item) { continue }
            $rows.Add(@{ SubscriptionId = $where.SubscriptionId; Location = $where.Location; Service = $where.Service; Name = $(if ($item['name']['localizedValue']) { [string]$item['name']['localizedValue'] } else { [string]$item['name']['value'] }); Used = [int64]$item['currentValue']; Maximum = [int64]$item['limit'] })
        }
    }
    if ($refused) { $notices.Add("$refused of $($asked.Count) quota answer(s) couldn't be read, so their quotas aren't shown$(if ($firstError) { ": $($firstError -replace '\s+', ' ')" })") }
    @{ Rows = $rows.ToArray(); Notices = $notices.ToArray() }
}
