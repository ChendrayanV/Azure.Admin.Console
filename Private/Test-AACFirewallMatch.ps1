function ConvertTo-AACIpRange {
    <#
    .SYNOPSIS
        Turns an address as Azure Firewall writes it - '10.1.2.3',
        '10.0.0.0/16', '10.0.0.1-10.0.0.9', an IPv6 address or prefix, or
        '*' - into a numeric range @{ Any; Family; Start; End }.
    .DESCRIPTION
        Returns nothing for anything that isn't an address: service tags
        ('AzureCloud', 'Internet'), FQDNs and the like, which can't be
        compared numerically. '*' and 'Any' become @{ Any = $true }, which
        covers every address.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([string] $Text)

    $value = "$Text".Trim()
    if (-not $value) { return }
    if ($value -in '*', 'Any') { return @{ Any = $true } }

    $toNumber = {
        param([System.Net.IPAddress] $Address)
        $bytes = $Address.GetAddressBytes()
        [array]::Reverse($bytes)
        [System.Numerics.BigInteger]::new([byte[]]($bytes + [byte]0))
    }
    $parse = {
        param([string] $Part)
        $address = $null
        if ([System.Net.IPAddress]::TryParse($Part, [ref]$address)) { $address }
    }

    if ($value -match '^(?<a>[^-/]+)-(?<b>[^-/]+)$') {
        $a = & $parse $Matches.a
        $b = & $parse $Matches.b
        if (-not $a -or -not $b -or $a.AddressFamily -ne $b.AddressFamily) { return }
        return @{ Any = $false; Family = $a.AddressFamily; Start = (& $toNumber $a); End = (& $toNumber $b) }
    }

    $prefix = $null
    if ($value -match '^(?<ip>[^/]+)/(?<bits>\d{1,3})$') {
        $value = $Matches.ip
        $prefix = [int]$Matches.bits
    }
    $address = & $parse $value
    if (-not $address) { return }
    $width = $address.GetAddressBytes().Length * 8
    $number = & $toNumber $address
    if ($null -eq $prefix -or $prefix -ge $width) {
        return @{ Any = $false; Family = $address.AddressFamily; Start = $number; End = $number }
    }
    $hostBits = $width - $prefix
    $size = [System.Numerics.BigInteger]::Pow(2, $hostBits)
    $start = [System.Numerics.BigInteger]::Divide($number, $size) * $size
    @{ Any = $false; Family = $address.AddressFamily; Start = $start; End = $start + $size - 1 }
}

function Test-AACAddressMatch {
    <#
    .SYNOPSIS
        True when any address a rule lists covers or overlaps any address
        searched for - '10.1.2.3' is inside '10.1.0.0/16', '10.1.0.0/24'
        overlaps it, and '*' covers everything.
    .DESCRIPTION
        Both sides take IPs, CIDR prefixes, 'a-b' ranges and '*'. Rule
        entries that aren't addresses (service tags, FQDNs) never match,
        because what they cover isn't known here.
    #>
    [CmdletBinding()]
    param(
        [string[]] $Search,
        [string[]] $RuleAddress
    )

    $ruleRanges = @($RuleAddress | ForEach-Object { ConvertTo-AACIpRange $_ } | Where-Object { $_ })
    if ($ruleRanges | Where-Object { $_.Any }) { return $true }
    foreach ($text in $Search) {
        $query = ConvertTo-AACIpRange $text
        if (-not $query) { continue }
        if ($query.Any) { return $ruleRanges.Count -gt 0 }
        foreach ($range in $ruleRanges) {
            if ($range.Family -eq $query.Family -and $range.Start -le $query.End -and $query.Start -le $range.End) {
                return $true
            }
        }
    }
    $false
}

function Test-AACPortMatch {
    <#
    .SYNOPSIS
        True when any port or port range a rule lists ('443', '8000-8080',
        '*') overlaps any port or range searched for.
    #>
    [CmdletBinding()]
    param(
        [string[]] $Search,
        [string[]] $RulePort
    )

    $toRange = {
        param([string] $Text)
        $value = "$Text".Trim()
        if ($value -in '*', 'Any') { return @(0, 65535) }
        if ($value -match '^(\d+)\s*-\s*(\d+)$') { return @([int]$Matches[1], [int]$Matches[2]) }
        if ($value -match '^\d+$') { return @([int]$value, [int]$value) }
    }
    $ruleRanges = @($RulePort | ForEach-Object { , (& $toRange $_) } | Where-Object { $_ })
    foreach ($text in $Search) {
        $query = & $toRange $text
        if (-not $query) { continue }
        foreach ($range in $ruleRanges) {
            if ($range[0] -le $query[1] -and $query[0] -le $range[1]) { return $true }
        }
    }
    $false
}

function Test-AACFirewallRuleMatch {
    <#
    .SYNOPSIS
        True when an AAC.FirewallRule matches every search filter given to
        Get-AACFirewallRule - filters combine with AND, and the values of
        one filter with OR.
    .DESCRIPTION
        -SourceAddress / -DestinationAddress   containment or overlap, counting
                                               the rule's addresses and the
                                               addresses of its IP Groups
        -Port                                  overlap with the destination
                                               ports (for application rules,
                                               the port of each protocol)
        -Protocol                              the rule's IP protocols (a rule
                                               with 'Any' matches all) or its
                                               application protocols (Http,
                                               Https, Mssql)
        -Fqdn                                  a host name covered by the
                                               rule's FQDNs ('*.contoso.com'
                                               covers 'www.contoso.com'), or
                                               a wildcard over them
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Rule,

        [string[]] $SourceAddress,
        [string[]] $DestinationAddress,
        [string[]] $Port,
        [string[]] $Protocol,
        [string[]] $Fqdn
    )

    $list = { param([string] $Text) @("$Text" -split ',\s*' | Where-Object { $_ }) }
    # "name: a, b | name2: c" -> a, b, c
    $groupAddresses = {
        param([string] $Described)
        foreach ($entry in @("$Described" -split ' \| ' | Where-Object { $_ })) {
            $null, $addresses = $entry -split ': ', 2
            & $list $addresses
        }
    }

    if ($SourceAddress) {
        $addresses = @((& $list $Rule.SourceAddresses) + @(& $groupAddresses $Rule.SourceIpGroupAddresses))
        if (-not (Test-AACAddressMatch -Search $SourceAddress -RuleAddress $addresses)) { return $false }
    }
    if ($DestinationAddress) {
        $addresses = @((& $list $Rule.DestinationAddresses) + @(& $groupAddresses $Rule.DestinationIpGroupAddresses))
        if (-not (Test-AACAddressMatch -Search $DestinationAddress -RuleAddress $addresses)) { return $false }
    }

    # Application rules carry protocol:port pairs ('Https:443'); the others
    # IP protocols and a separate port list.
    $isApplication = $Rule.RuleType -eq 'ApplicationRule'
    $pairs = @(& $list $Rule.Protocols)
    if ($Port) {
        $ports = if ($isApplication) { @($pairs | ForEach-Object { ($_ -split ':')[-1] }) } else { @(& $list $Rule.DestinationPorts) }
        if (-not (Test-AACPortMatch -Search $Port -RulePort $ports)) { return $false }
    }
    if ($Protocol) {
        $protocols = if ($isApplication) { @($pairs | ForEach-Object { ($_ -split ':')[0] }) } else { $pairs }
        if (-not ('Any' -in $protocols -or @($Protocol | Where-Object { $_ -in $protocols }).Count -gt 0)) { return $false }
    }
    if ($Fqdn) {
        $ruleFqdns = @((& $list $Rule.DestinationFqdns) + (& $list $Rule.TargetFqdns) + (& $list $Rule.TranslatedFqdn))
        $covered = @(foreach ($name in $Fqdn) {
                foreach ($ruleFqdn in $ruleFqdns) {
                    if ($name -like $ruleFqdn -or $ruleFqdn -like $name) { $true }
                }
            })
        if ($covered.Count -eq 0) { return $false }
    }
    $true
}
