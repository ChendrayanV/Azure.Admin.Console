function Resolve-AACHostName {
    <#
    .SYNOPSIS
        Looks up many host names in DNS at once, and says which exist.
    .DESCRIPTION
        For dangling redirect URIs: a host that no longer resolves (NXDOMAIN)
        - an app service, storage account or Front Door deleted while an app
        still sends tokens to it - can be claimed by anyone.

        Returns a hashtable: host -> $true (it resolves), $false (no such
        host), $null (unknown: the lookup timed out or failed otherwise).
        All lookups run together, -TimeoutSeconds in all.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyCollection()]
        [string[]] $HostName = @(),

        [ValidateRange(1, 120)]
        [int] $TimeoutSeconds = 10
    )

    $result = @{}
    $names = @($HostName | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique)
    if (-not $names.Count) { return $result }
    $tasks = @{}
    foreach ($name in $names) {
        try { $tasks[$name] = [System.Net.Dns]::GetHostAddressesAsync($name) } catch { $result[$name] = $null }
    }
    try { $null = [System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]@($tasks.Values), [TimeSpan]::FromSeconds($TimeoutSeconds)) } catch { Write-Verbose "Some DNS lookups failed: $($_.Exception.Message)" }
    foreach ($name in $tasks.Keys) {
        $task = $tasks[$name]
        $result[$name] = if ($task.IsCompletedSuccessfully) { [bool]@($task.Result).Count }
        elseif ($task.IsFaulted -and @($task.Exception.InnerExceptions | Where-Object { $_ -is [System.Net.Sockets.SocketException] -and $_.SocketErrorCode -in 'HostNotFound', 'NoData' }).Count) { $false }
        else { $null }
    }
    $result
}
