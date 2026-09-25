function Invoke-AACPagedRestMethod {
    <#
    .SYNOPSIS
        Calls an Azure Resource Manager REST endpoint and follows nextLink
        pagination, returning every item from every page's "value" array.
    .DESCRIPTION
        Centralizes the GET-then-follow-nextLink loop that every ARM list
        endpoint (subscriptions, resource groups, resources, ...) shares. See
        Get-AACPropertyValue for why nextLink is read the way it is - ARM
        omits it entirely on the last page rather than sending it as null.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [string] $Uri,

        [Parameter(Mandatory)]
        [hashtable] $Headers
    )

    # No web-request progress bar: callers show their own Spectre progress.
    $ProgressPreference = 'SilentlyContinue'
    $collected = [System.Collections.Generic.List[object]]::new()
    $nextUri = $Uri
    while ($nextUri) {
        $response = Invoke-RestMethod -Uri $nextUri -Headers $Headers -Method Get -ErrorAction Stop -Verbose:$false
        foreach ($item in $response.value) {
            $collected.Add($item)
        }
        $nextUri = Get-AACPropertyValue -InputObject $response -Name 'nextLink'
    }

    return $collected.ToArray()
}
