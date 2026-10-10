function Get-AACDirectoryObject {
    <#
    .SYNOPSIS
        Looks up Entra ID objects - users, groups, service principals - by
        ID with Microsoft Graph's directoryObjects/getByIds, 1,000 at a
        time, several requests at once.
    .DESCRIPTION
        Returns @{ Objects (ID, lower case -> the object, as Graph returns
        it: @odata.type, displayName, userPrincipalName, userType,
        accountEnabled, appId, servicePrincipalType...); Error (why Graph
        refused, or '') }. An ID Graph doesn't return is a deleted object.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyCollection()]
        [string[]] $Id = @()
    )

    $ids = @($Id | Where-Object { $_ -match '^[0-9a-fA-F-]{36}$' } | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique)
    # Script blocks below run inside Invoke-AACHttpBatch: their names are prefixed 'directory'.
    $directoryFound = @{}
    if (-not $ids.Count) { return @{ Objects = $directoryFound; Error = '' } }
    $requests = @(for ($i = 0; $i -lt $ids.Count; $i += 1000) {
            $chunk = @($ids[$i..([Math]::Min($i + 999, $ids.Count - 1))])
            @{ Key = "ids$i"; Uri = 'https://graph.microsoft.com/v1.0/directoryObjects/getByIds?$select=id,displayName,userPrincipalName,userType,accountEnabled,appId,servicePrincipalType,mail'; Body = (ConvertTo-Json -InputObject @{ ids = $chunk; types = @('user', 'group', 'servicePrincipal') } -Depth 4 -Compress) }
        })
    $failures = Invoke-AACHttpBatch -Request $requests -Resource 'https://graph.microsoft.com' -ThrottleLimit 4 -OnResponse {
        param($DirectoryKey, [string] $DirectoryContent)
        $directoryPage = ConvertFrom-Json -InputObject $DirectoryContent -AsHashtable -Depth 20
        foreach ($directoryItem in @($directoryPage['value'])) { if ($directoryItem) { $directoryFound[([string]$directoryItem['id']).ToLowerInvariant()] = $directoryItem } }
    }
    $why = @($failures.Values | Where-Object { $_ }) | Select-Object -First 1
    @{ Objects = $directoryFound; Error = $(if ($why) { [string]$why } else { '' }) }
}
