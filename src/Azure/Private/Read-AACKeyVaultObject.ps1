function Read-AACKeyVaultObject {
    <#
    .SYNOPSIS
        Lists each Key Vault's secrets, keys and certificates - their
        metadata only, never a value - from the vault's data plane.
    .DESCRIPTION
        GET {vaultUri}secrets, keys and certificates (api-version 7.5),
        following nextLink, with a token for https://vault.azure.net from the
        Connect-AAC sign-in, through Invoke-AACHttpBatch. Secrets that back a
        certificate (managed) are left out: the certificate is listed.

        Needs Key Vault Reader (RBAC vaults) or a List permission in an access
        policy. A vault that refuses is reported, not fatal:
          Not reachable  the vault's firewall or private endpoint blocks this
                         machine (ForbiddenByFirewall)
          Denied         no data-plane permission
        -Vault: @(@{ Id; Name; Uri }). Returns @{ Items = @(@{ VaultId; Kind;
        Name; Enabled; Expires (UTC or $null) }); Access = @{ vault id =
        'Read' | 'Not reachable' | 'Denied' | 'Failed: ...' } }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Vault,

        [ValidateRange(1, 32)]
        [int] $ThrottleLimit = 8
    )

    $items = [System.Collections.Generic.List[object]]::new()
    $byKey = @{}
    $requests = @(foreach ($v in $Vault) {
            $base = ([string]$v.Uri).TrimEnd('/')
            foreach ($kind in 'secrets', 'keys', 'certificates') {
                $key = "$($v.Id)|$kind"
                $byKey[$key] = $v
                @{ Key = $key; Body = $null; Uri = "$base/$($kind)?api-version=7.5&maxresults=25" }
            }
        })
    $label = @{ secrets = 'Secret'; keys = 'Key'; certificates = 'Certificate' }
    $onResponse = {
        param($Key, [string] $Content)
        $page = ConvertFrom-Json -InputObject $Content -AsHashtable -Depth 20
        $vaultId, $kind = $Key -split '\|'
        foreach ($o in @($page['value'])) {
            if ($null -eq $o -or ($kind -eq 'secrets' -and $o['managed'] -eq $true)) { continue }
            $attributes = $o['attributes']
            $expires = if ($attributes -and $attributes['exp']) { [DateTimeOffset]::FromUnixTimeSeconds([long]$attributes['exp']).UtcDateTime } else { $null }
            $items.Add(@{ VaultId = $vaultId; Kind = $label[$kind]; Name = (([string]$(if ($o['id']) { $o['id'] } else { $o['kid'] })) -split '/')[-1]; Enabled = -not ($attributes -and $attributes['enabled'] -eq $false); Expires = $expires })
        }
        if ($page['nextLink']) { @{ Uri = [string]$page['nextLink'] } }
    }
    $failures = if ($requests.Count) { Invoke-AACHttpBatch -Request $requests -OnResponse $onResponse -Resource 'https://vault.azure.net' -ThrottleLimit $ThrottleLimit } else { @{} }
    $access = @{}
    foreach ($v in $Vault) {
        $reasons = @(foreach ($kind in 'secrets', 'keys', 'certificates') { $f = $failures["$($v.Id)|$kind"]; if ($f) { [string]$f } })
        $access[$v.Id] = if (-not $reasons.Count) { 'Read' }
        elseif (@($reasons | Where-Object { $_ -match '(?i)firewall|client address|private (link|endpoint)' }).Count) { 'Not reachable' }
        elseif (@($reasons | Where-Object { $_ -match '(?i)forbidden|403|401|does not have|not authorized|unauthorized' }).Count) { 'Denied' }
        else { "Failed: $($reasons[0])" }
    }
    @{ Items = $items.ToArray(); Access = $access }
}
