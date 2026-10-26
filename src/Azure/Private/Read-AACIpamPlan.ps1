function Read-AACIpamPlan {
    <#
    .SYNOPSIS
        The address plan Get-AACIPAMReport measures Azure against: spaces,
        their blocks, and external (on-premises or partner) ranges - from a
        file, a hashtable, or the private ranges when none is given.
    .DESCRIPTION
        -Plan is one of:
          a .psd1 or .json file   @{ Spaces = @(@{ Name; Description;
                                  Blocks = @(@{ Name; Cidr; Description }) });
                                  External = @(@{ Name; Cidr; Space; Block;
                                  Description }) }
          a .csv file             one row per range: Space, Block, Cidr,
                                  Kind (Block, the default, or External),
                                  Description - for an external range, Block
                                  is its name
          a hashtable             the .psd1 shape
          nothing                 the private ranges as blocks: RFC 1918
                                  (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)
                                  and RFC 6598 shared space (100.64.0.0/10)
        Returns @{ Source; Default; Spaces = @(@{ Name; Description });
        Blocks = @(@{ Space; Name; Cidr; Description; Start; End; Size;
        Length }); External = @(@{ Name; Cidr; Space; Block; Description;
        Start; End; Size; Length }) }. Only IPv4 is planned (Azure's IPv6
        ranges are /64s - not something to plan by address).

        Throws, saying what to fix, on a missing file, a range that isn't
        IPv4 CIDR, a block given twice, or two blocks of one space that
        overlap (they would count the same networks twice).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowNull()]
        [object] $Plan
    )

    $source = 'Private ranges (RFC 1918 and RFC 6598) - no -AddressPlan given'
    $isDefault = $false
    $data = $null
    if ($null -eq $Plan -or ($Plan -is [string] -and -not $Plan)) {
        $isDefault = $true
        $data = @{
            Spaces = @(
                @{ Name = 'Private (RFC 1918)'; Description = 'The private IPv4 ranges'; Blocks = @(
                        @{ Name = '10.0.0.0/8'; Cidr = '10.0.0.0/8' }
                        @{ Name = '172.16.0.0/12'; Cidr = '172.16.0.0/12' }
                        @{ Name = '192.168.0.0/16'; Cidr = '192.168.0.0/16' }
                    )
                }
                @{ Name = 'Shared (RFC 6598)'; Description = 'Carrier-grade NAT space, often used when private ranges run out'; Blocks = @(@{ Name = '100.64.0.0/10'; Cidr = '100.64.0.0/10' }) }
            )
            External = @()
        }
    }
    elseif ($Plan -is [System.Collections.IDictionary]) {
        $source = 'the -AddressPlan hashtable'
        $data = $Plan
    }
    else {
        $path = [string]$Plan
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Azure Admin Console can't find the address plan '$path'. Give the path of a .psd1, .json or .csv file (Get-Help Get-AACIPAMReport -Parameter AddressPlan shows the format)."
        }
        $source = [System.IO.Path]::GetFileName($path)
        $extension = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
        $data = switch ($extension) {
            '.psd1' { Import-PowerShellDataFile -LiteralPath $path }
            '.json' { ConvertFrom-Json -InputObject (Get-Content -LiteralPath $path -Raw) -AsHashtable }
            '.csv' {
                # Rows to the .psd1 shape: blocks grouped by space, the External kind apart.
                $spaces = [ordered]@{}
                $external = [System.Collections.Generic.List[object]]::new()
                foreach ($row in @(Import-Csv -LiteralPath $path)) {
                    $kind = if ($row.PSObject.Properties['Kind'] -and $row.Kind) { [string]$row.Kind } else { 'Block' }
                    $description = if ($row.PSObject.Properties['Description']) { [string]$row.Description } else { '' }
                    $spaceName = if ($row.PSObject.Properties['Space']) { [string]$row.Space } else { '' }
                    $blockName = if ($row.PSObject.Properties['Block']) { [string]$row.Block } else { '' }
                    if ($kind -match '^External$') { $external.Add(@{ Name = $blockName; Cidr = [string]$row.Cidr; Space = $spaceName; Description = $description }); continue }
                    if (-not $spaces.Contains($spaceName)) { $spaces[$spaceName] = [System.Collections.Generic.List[object]]::new() }
                    $spaces[$spaceName].Add(@{ Name = $blockName; Cidr = [string]$row.Cidr; Description = $description })
                }
                @{ Spaces = @(foreach ($name in $spaces.Keys) { @{ Name = $name; Blocks = $spaces[$name].ToArray() } }); External = $external.ToArray() }
            }
            default { throw "Azure Admin Console can't read the address plan '$path': use a .psd1, .json or .csv file." }
        }
    }

    $field = { param($Item, [string] $Name) if ($Item -is [System.Collections.IDictionary]) { if ($Item.Contains($Name)) { $Item[$Name] } else { $null } } elseif ($null -ne $Item -and $Item.PSObject.Properties[$Name]) { $Item.PSObject.Properties[$Name].Value } else { $null } }
    $range = {
        param([string] $Cidr, [string] $What)
        $parsed = ConvertTo-AACCidrRange -Prefix $Cidr
        if (-not $parsed.Valid -or $parsed.Version -ne 4 -or $Cidr -notmatch '/\d{1,2}$') {
            throw "Azure Admin Console can't use '$Cidr' for $What in the address plan: give an IPv4 CIDR range such as 10.20.0.0/14."
        }
        $parsed
    }

    $spaceRows = [System.Collections.Generic.List[object]]::new()
    $blockRows = [System.Collections.Generic.List[object]]::new()
    foreach ($space in @(& $field $data 'Spaces') | Where-Object { $_ }) {
        $spaceName = [string](& $field $space 'Name')
        if (-not $spaceName) { throw 'Azure Admin Console found a space with no Name in the address plan: give every space a Name.' }
        $spaceRows.Add(@{ Name = $spaceName; Description = [string](& $field $space 'Description') })
        foreach ($block in @(& $field $space 'Blocks') | Where-Object { $_ }) {
            $cidr = [string](& $field $block 'Cidr')
            $blockName = [string](& $field $block 'Name')
            if (-not $blockName) { $blockName = $cidr }
            $parsed = & $range $cidr "block '$blockName' of space '$spaceName'"
            if (@($blockRows | Where-Object { $_.Space -eq $spaceName -and $_.Name -eq $blockName }).Count) {
                throw "Azure Admin Console found block '$blockName' twice in space '$spaceName' of the address plan: give each block of a space its own name."
            }
            $clash = @($blockRows | Where-Object { $_.Space -eq $spaceName -and $_.Start -le $parsed.End -and $parsed.Start -le $_.End }) | Select-Object -First 1
            if ($clash) {
                throw "Azure Admin Console found blocks '$($clash.Name)' ($($clash.Cidr)) and '$blockName' ($cidr) of space '$spaceName' overlapping in the address plan: blocks of one space must not overlap. Put one of them in another space, or merge them."
            }
            # The network address, even if the plan wrote a host inside it (10.20.1.0/14 is 10.20.0.0/14).
            $network = ConvertTo-AACCidrRange -Start $parsed.Start -Length $parsed.Length
            $blockRows.Add(@{ Space = $spaceName; Name = $blockName; Cidr = $network; Description = [string](& $field $block 'Description'); Start = $parsed.Start; End = $parsed.End; Size = $parsed.Size; Length = $parsed.Length })
        }
    }
    $externalRows = [System.Collections.Generic.List[object]]::new()
    foreach ($item in @(& $field $data 'External') | Where-Object { $_ }) {
        $cidr = [string](& $field $item 'Cidr')
        $name = [string](& $field $item 'Name')
        if (-not $name) { $name = $cidr }
        $parsed = & $range $cidr "external range '$name'"
        $externalRows.Add(@{
                Name = $name; Cidr = (ConvertTo-AACCidrRange -Start $parsed.Start -Length $parsed.Length); Space = [string](& $field $item 'Space'); Block = [string](& $field $item 'Block')
                Description = [string](& $field $item 'Description'); Start = $parsed.Start; End = $parsed.End; Size = $parsed.Size; Length = $parsed.Length
            })
    }
    if (-not $blockRows.Count) {
        throw 'Azure Admin Console found no block in the address plan: give at least one space with a block (@{ Spaces = @(@{ Name = ''Corp''; Blocks = @(@{ Name = ''Azure''; Cidr = ''10.20.0.0/14'' }) }) }).'
    }
    @{ Source = $source; Default = $isDefault; Spaces = $spaceRows.ToArray(); Blocks = $blockRows.ToArray(); External = $externalRows.ToArray() }
}
