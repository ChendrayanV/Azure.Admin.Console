function ConvertTo-AACStorageSizeReport {
    <#
    .SYNOPSIS
        Rolls Get-AACStorageAccountContainerSize's container rows up to the
        storage accounts, the access tiers and the estate - what its console
        view and HTML report show.
    .DESCRIPTION
        Returns @{
          Rows      the AAC.StorageContainerSize rows, as given
          Accounts  one object per storage account: containers read and
                    failed, blobs, size, status (OK, Partial, Failed, Empty,
                    No blob service), largest first
          Tiers     Hot, Cool, Cold, Archive, None -> @{ Blobs; Bytes }
          Largest   the 25 largest blobs across every container
          Failures  the rows not read in full
          Stats     the totals, how long the read took and blobs per second
        }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Row,

        [AllowEmptyCollection()]
        [object[]] $Account = @(),

        [TimeSpan] $Elapsed = [TimeSpan]::Zero
    )

    $containers = @($Row | Where-Object { $null -ne $_.Container })
    $sum = { param([object[]] $Items, [string] $Property) $total = [long]0; foreach ($item in $Items) { $total += [long]$item.$Property }; $total }

    $tiers = [ordered]@{}
    foreach ($name in 'Hot', 'Cool', 'Cold', 'Archive', 'None') {
        $property = if ($name -eq 'None') { 'SizeNoTier' } else { "Size$name" }
        $tiers[$name] = & $sum $containers $property
    }

    $byAccount = @{}
    foreach ($item in $Row) {
        $key = [string]$item.StorageAccountId
        if (-not $byAccount.ContainsKey($key)) { $byAccount[$key] = [System.Collections.Generic.List[object]]::new() }
        $byAccount[$key].Add($item)
    }
    $accounts = @(foreach ($a in $Account) {
            $items = @(if ($byAccount.ContainsKey($a.Id)) { $byAccount[$a.Id] })
            $listed = @($items | Where-Object { $null -ne $_.Container })
            $failed = @($listed | Where-Object Status -EQ 'Failed').Count
            $partial = @($listed | Where-Object Status -EQ 'Partial').Count
            $size = & $sum $listed 'Size'
            $status = if (-not $a.BlobEndpoint) { 'No blob service' }
            elseif ($a.Error) { 'Failed' }
            elseif (-not $listed.Count) { 'Empty' }
            elseif ($failed -eq $listed.Count) { 'Failed' }
            elseif ($failed -or $partial) { 'Partial' }
            else { 'OK' }
            $reasons = @(@($items | Where-Object Error | ForEach-Object { ($_.Error -split ':')[0] }) | Select-Object -Unique)
            [pscustomobject]@{
                PSTypeName            = 'AAC.StorageAccountSize'
                StorageAccount        = $a.Name
                Status                = $status
                Containers            = $listed.Count
                Failed                = $failed + $partial
                BlobCount             = & $sum $listed 'BlobCount'
                Size                  = $size
                SizeText              = Format-AACByteSize -Bytes $size
                TotalSize             = & $sum $listed 'TotalSize'
                Reason                = $(if ($a.Note) { $a.Note } elseif ($a.Error) { $a.Error } else { $reasons -join ', ' })
                ResourceGroup         = $a.ResourceGroup
                SubscriptionName      = $a.SubscriptionName
                Location              = $a.Location
                Kind                  = $a.Kind
                Sku                   = $a.Sku
                NetworkAccess         = $a.Firewall
                HierarchicalNamespace = [bool]$a.Hns
                StorageAccountId      = $a.Id
            }
        })
    $accounts = @($accounts | Sort-Object -Property @{ Expression = 'Size'; Descending = $true }, StorageAccount)

    $largest = @($containers | ForEach-Object { $_.LargestBlobs } | Where-Object { $_ } | Sort-Object -Property Size -Descending | Select-Object -First 25)
    $failures = @($Row | Where-Object Status -NE 'OK')
    $blobs = & $sum $containers 'BlobCount'
    $seconds = [Math]::Max(0.001, $Elapsed.TotalSeconds)
    $biggest = $containers | Sort-Object -Property Size -Descending | Select-Object -First 1

    @{
        Rows     = $Row
        Accounts = $accounts
        Tiers    = $tiers
        Largest  = $largest
        Failures = $failures
        Stats    = @{
            Accounts         = @($accounts | Where-Object Status -NE 'No blob service').Count
            Subscriptions    = @($accounts.SubscriptionName | Select-Object -Unique).Count
            Containers       = $containers.Count
            Read             = @($containers | Where-Object Status -EQ 'OK').Count
            Failed           = @($containers | Where-Object Status -EQ 'Failed').Count + @($Row | Where-Object { $null -eq $_.Container }).Count
            Partial          = @($containers | Where-Object Status -EQ 'Partial').Count
            Empty            = @($containers | Where-Object { $_.Status -eq 'OK' -and $_.BlobCount -eq 0 }).Count
            Blobs            = $blobs
            Bytes            = & $sum $containers 'Size'
            TotalBytes       = & $sum $containers 'TotalSize'
            Snapshots        = & $sum $containers 'Snapshots'
            SnapshotBytes    = & $sum $containers 'SnapshotSize'
            Versions         = & $sum $containers 'Versions'
            VersionBytes     = & $sum $containers 'VersionSize'
            Deleted          = & $sum $containers 'DeletedBlobs'
            DeletedBytes     = & $sum $containers 'DeletedSize'
            Directories      = & $sum $containers 'Directories'
            LargestContainer = $biggest
            Elapsed          = $Elapsed
            BlobsPerSecond   = [long]($blobs / $seconds)
        }
    }
}
