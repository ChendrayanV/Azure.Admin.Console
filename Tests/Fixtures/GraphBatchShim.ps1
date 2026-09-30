<#
    Invoke-AACGraphBatch for the command tests: the same queries, scopes and
    result, but one query after another, through the calls those tests
    already fake - Invoke-AACArmRequest (rows as hashtables) or, with
    -AsObject, Invoke-AACResourceGraphQuery. The parallel transport itself
    is tested in ArmParallel.Tests.ps1.

    In a BeforeEach:
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            & $script:graphBatchShim $Query $SubscriptionId $ManagementGroupId $AsObject $AllowFailure
        }
#>

$script:graphBatchShim = {
    param($Query, $SubscriptionId, $ManagementGroupId, $AsObject, $AllowFailure)
    & (Get-Module -Name 'Azure.Admin.Console') {
        param($Query, $SubscriptionId, $ManagementGroupId, $AsObject, $AllowFailure)
        $rows = @{}
        $errors = @{}
        foreach ($name in @($Query.Keys)) {
            $spec = $Query[$name]
            if ($spec -isnot [System.Collections.IDictionary]) { $spec = @{ Query = [string]$spec } }
            $subscriptions = $null
            $groups = $null
            if (-not $spec['Tenant']) {
                $subscriptions = if ($spec.Contains('SubscriptionId')) { $spec['SubscriptionId'] } else { $SubscriptionId }
                $groups = if ($spec.Contains('ManagementGroupId')) { $spec['ManagementGroupId'] } else { $ManagementGroupId }
            }
            try {
                if ($AsObject) {
                    $call = @{ Query = [string]$spec['Query']; Headers = @{} }
                    if ($subscriptions) { $call.SubscriptionId = @($subscriptions) }
                    $rows[$name] = @(Invoke-AACResourceGraphQuery @call)
                }
                else {
                    $body = @{ query = [string]$spec['Query']; options = @{ resultFormat = 'objectArray' } }
                    if ($subscriptions) { $body.subscriptions = @($subscriptions) }
                    elseif ($groups) { $body.managementGroups = @($groups) }
                    $list = [System.Collections.Generic.List[object]]::new()
                    do {
                        $response = Invoke-AACArmRequest -Method Post -Uri '/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01' -Body ($body | ConvertTo-Json -Depth 10)
                        foreach ($row in @($response['data'])) { if ($null -ne $row) { $list.Add($row) } }
                        $skipToken = if ($response -is [System.Collections.IDictionary]) { $response['$skipToken'] }
                        $body.options['$skipToken'] = $skipToken
                    } while ($skipToken)
                    $rows[$name] = $list.ToArray()
                }
            }
            catch {
                if (@($AllowFailure) -notcontains $name) { throw }
                $errors[$name] = $_.Exception.Message
                $rows[$name] = @()
            }
        }
        @{ Rows = $rows; Errors = $errors }
    } $Query $SubscriptionId $ManagementGroupId $AsObject $AllowFailure
}

# Invoke-AACCostBatch the same way: one subscription after another, through
# Invoke-AACCostQuery (which the cost tests fake). A management-group scope
# is refused, as Cost Management refuses it for pay-as-you-go billing -
# unless $script:costGroupRows has rows for it.
#     Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACCostBatch -MockWith {
#         & $script:costBatchShim $Scope $Body
#     }
$script:costBatchShim = {
    param($Scope, $Body)
    $groupRows = Get-Variable -Name 'costGroupRows' -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    & (Get-Module -Name 'Azure.Admin.Console') {
        param($Scope, $Body, $GroupRows)
        $result = @{}
        foreach ($item in @($Scope)) {
            try {
                if ($item -match '^/providers/Microsoft.Management/managementGroups/(.+)$') {
                    if (-not $GroupRows -or -not $GroupRows.Contains($Matches[1])) { throw 'Management group scope is not supported for this billing account.' }
                    $result[$item] = @{ Rows = @($GroupRows[$Matches[1]]); Status = 'OK' }
                    continue
                }
                $result[$item] = @{ Rows = @(Invoke-AACCostQuery -SubscriptionId ($item -replace '^/subscriptions/', '') -Body $Body); Status = 'OK' }
            }
            catch { $result[$item] = @{ Rows = @(); Status = [string]$_.Exception.Message } }
        }
        $result
    } $Scope $Body $groupRows
}
