function Get-AACActivityLogQuery {
    <#
    .SYNOPSIS
        The KQL that reads the Activity Log from a Log Analytics workspace
        (AzureActivity) already summarised: one row per resource, caller,
        operation and status - how many times, first and last.
    .DESCRIPTION
        For Invoke-AACActivityLogAssessment. The workspace does the work, so
        a year comes back as a few thousand rows, not millions of events:
          1. the window, the subscriptions, the categories (and resource
             groups), with the token's claims read from Claims_d (or the
             older string column Claims)
          2. one row per operation - its last status (an operation writes
             Started, Accepted, Succeeded)
          3. one row per resource, caller, operation and status
        Each row: ResourceId (lower case), Caller, Mirid (a managed
        identity's resource), AppId, TokenType (idtyp), Upn, Operation,
        OperationName, Status, Category, Count, First, Last, CallerIp, and
        the latest operation's CorrelationId, StatusMessage, StatusCode and
        SubStatus (why it failed, for Read-AACActivityLogError).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string[]] $SubscriptionId,

        [Parameter(Mandatory)]
        [datetime] $Start,

        [Parameter(Mandatory)]
        [datetime] $End,

        [string[]] $Category = @('Administrative'),

        [string[]] $ResourceGroupName = @()
    )

    $quote = { param([string] $Text) ConvertTo-AACKqlLiteral -Text $Text }
    $iso = { param([datetime] $When) $When.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture) }
    $categories = @($Category | Where-Object { $_ -and $_ -ne 'All' })
    $groups = @($ResourceGroupName | Where-Object { $_ })
    $upn = 'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn'
    @(
        'AzureActivity'
        "| where TimeGenerated >= datetime($(& $iso $Start)) and TimeGenerated < datetime($(& $iso $End))"
        "| where SubscriptionId in~ ($((@($SubscriptionId | ForEach-Object { & $quote $_ })) -join ', '))"
        $(if ($categories.Count -and $Category -notcontains 'All') { "| where CategoryValue in~ ($((@($categories | ForEach-Object { & $quote $_ })) -join ', '))" })
        $(if ($groups.Count) { "| where ResourceGroup in~ ($((@($groups | ForEach-Object { & $quote $_ })) -join ', '))" })
        "| extend Claims = coalesce(column_ifexists('Claims_d', dynamic(null)), parse_json(tostring(column_ifexists('Claims', ''))))"
        "| extend Mirid = tostring(Claims['xms_mirid']), AppId = tostring(Claims['appid']), TokenType = tostring(Claims['idtyp']), Upn = tostring(Claims['$upn'])"
        "| extend Props = coalesce(column_ifexists('Properties_d', dynamic(null)), parse_json(tostring(column_ifexists('Properties', ''))))"
        "| extend StatusMessage = tostring(Props.statusMessage), StatusCode = tostring(Props.statusCode), SubStatus = tostring(column_ifexists('ActivitySubstatusValue', ''))"
        '| summarize arg_max(TimeGenerated, ActivityStatusValue, Caller, CallerIpAddress, OperationName, CategoryValue, Mirid, AppId, TokenType, Upn, StatusMessage, StatusCode, SubStatus) by CorrelationId, OperationNameValue, ResourceId = tolower(_ResourceId)'
        '| summarize Count = count(), First = min(TimeGenerated), CallerIp = take_any(CallerIpAddress), OperationName = take_any(OperationName), Category = take_any(CategoryValue), arg_max(TimeGenerated, CorrelationId, StatusMessage, StatusCode, SubStatus) by ResourceId, Caller, Mirid, AppId, TokenType, Upn, Operation = OperationNameValue, Status = ActivityStatusValue'
        '| project-rename Last = TimeGenerated'
        # AzureActivity says Failure, Success, Start; the REST API Failed, Succeeded, Started.
        "| extend Status = case(Status =~ 'Failure', 'Failed', Status =~ 'Success', 'Succeeded', Status =~ 'Start', 'Started', Status =~ 'Accept', 'Accepted', Status)"
    ) -join "`n"
}
