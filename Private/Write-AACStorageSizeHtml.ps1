function Write-AACStorageSizeHtml {
    <#
    .SYNOPSIS
        Writes Get-AACStorageAccountContainerSize's report as an interactive
        HTML report: tiles and charts that filter tables of the storage
        accounts, the containers and the largest blobs.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Report,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Title,

        [System.Collections.IDictionary] $Detail
    )

    $stats = $Report.Stats
    $gib = [Math]::Pow(1024, 3)
    $toGib = { param([double] $Bytes) [Math]::Round($Bytes / $gib, 3) }
    $statusTones = @{ OK = 'good'; Partial = 'warn'; Failed = 'bad'; Empty = 'neutral'; 'No blob service' = 'neutral' }
    $tierTones = @{ Hot = 'bad'; Cool = 'info'; Cold = 'violet'; Archive = 'neutral'; None = 'neutral' }

    $containers = @($Report.Rows | Where-Object { $null -ne $_.Container } | ForEach-Object {
            [ordered]@{
                StorageAccount = $_.StorageAccount; Container = $_.Container; Status = $_.Status; BlobCount = $_.BlobCount
                SizeGiB = & $toGib $_.Size; SizeText = $_.SizeText
                HotGiB = & $toGib $_.SizeHot; CoolGiB = & $toGib $_.SizeCool; ColdGiB = & $toGib $_.SizeCold; ArchiveGiB = & $toGib $_.SizeArchive; NoTierGiB = & $toGib $_.SizeNoTier
                Snapshots = $_.Snapshots; Versions = $_.Versions; DeletedBlobs = $_.DeletedBlobs; TotalGiB = & $toGib $_.TotalSize
                LastModified = $(if ($_.LastModified) { ([datetime]$_.LastModified).ToString('o') } else { '' })
                PublicAccess = $_.PublicAccess; AuthMode = $_.AuthMode; Error = $_.Error
                ResourceGroup = $_.ResourceGroup; SubscriptionName = $_.SubscriptionName; Location = $_.Location; Kind = $_.Kind; Sku = $_.Sku
                ResourceId = $_.StorageAccountId; Bytes = $_.Size
            }
        })
    $accounts = @($Report.Accounts | ForEach-Object {
            [ordered]@{
                StorageAccount = $_.StorageAccount; Status = $_.Status; Containers = $_.Containers; Failed = $_.Failed; BlobCount = $_.BlobCount
                SizeGiB = & $toGib $_.Size; SizeText = $_.SizeText; Reason = $_.Reason
                Kind = $_.Kind; Sku = $_.Sku; Location = $_.Location; NetworkAccess = $_.NetworkAccess; DataLake = $(if ($_.HierarchicalNamespace) { 'Yes' } else { 'No' })
                ResourceGroup = $_.ResourceGroup; SubscriptionName = $_.SubscriptionName; ResourceId = $_.StorageAccountId
            }
        })
    $blobs = @($Report.Largest | ForEach-Object {
            [ordered]@{
                Name = $_.Name; StorageAccount = $_.StorageAccount; Container = $_.Container; SizeGiB = & $toGib $_.Size; SizeText = (Format-AACByteSize -Bytes $_.Size)
                AccessTier = $_.AccessTier; BlobType = $_.BlobType; LastModified = $(if ($_.LastModified) { ([datetime]$_.LastModified).ToString('o') } else { '' })
            }
        })

    $notRead = $stats.Failed + $stats.Partial
    $tiles = @(
        @{ Value = '{0:N0}' -f $stats.Accounts; Label = 'storage accounts'; Tone = 'info'; Table = 'accounts' }
        @{ Value = '{0:N0}' -f $stats.Containers; Label = 'containers'; Tone = 'violet'; Table = 'containers' }
        @{ Value = '{0:N0}' -f $stats.Blobs; Label = 'blobs'; Tone = 'info'; Table = 'containers' }
        @{ Value = (Format-AACByteSize -Bytes $stats.Bytes); Label = 'stored'; Tone = 'good'; Table = 'containers' }
        @{ Value = '{0:N0}' -f $stats.Empty; Label = 'empty containers'; Tone = 'neutral'; Table = 'containers' }
        @{ Value = '{0:N0}' -f $notRead; Label = 'not read in full'; Tone = $(if ($notRead) { 'bad' } else { 'good' }); Table = 'containers'; Filters = @{ Status = 'Failed' } }
    )
    $charts = @(
        @{ Title = 'Size by access tier (GiB)'; Kind = 'donut'; CenterLabel = 'GiB'; Format = 'N2'; Items = @($Report.Tiers.Keys | Where-Object { $Report.Tiers[$_] -gt 0 } | ForEach-Object { @{ Label = $_; Value = (& $toGib $Report.Tiers[$_]); Display = (Format-AACByteSize -Bytes $Report.Tiers[$_]); Tone = $tierTones[$_] } }) }
        @{ Title = 'Largest storage accounts (GiB)'; Format = 'N2'; Table = 'containers'; Column = 'StorageAccount'; Items = @($Report.Accounts | Where-Object Size | Select-Object -First 12 | ForEach-Object { @{ Label = $_.StorageAccount; Value = (& $toGib $_.Size); Display = $_.SizeText; Tone = 'info' } }) }
        @{ Title = 'Largest containers (GiB)'; Format = 'N2'; Table = 'containers'; Column = 'Container'; Wide = $true; Items = @($Report.Rows | Where-Object { $null -ne $_.Container -and $_.Size } | Sort-Object Size -Descending | Select-Object -First 15 | ForEach-Object { @{ Label = "$($_.StorageAccount)/$($_.Container)"; Filter = $_.Container; Value = (& $toGib $_.Size); Display = $_.SizeText; Tone = 'good' } }) }
    )
    $tables = @(
        @{
            Id = 'containers'; Title = 'Containers'; Note = 'Size: the current blobs. Total: with the snapshots, versions and deleted blobs listed.'; Noun = 'containers'; File = 'storage-containers'
            Rows = $containers; Sort = @{ Key = 'SizeGiB'; Desc = $true }; GroupBy = @('StorageAccount', 'SubscriptionName', 'Status')
            Columns = @(
                @{ Key = 'StorageAccount'; Label = 'Storage account'; Type = 'resource'; IdKey = 'ResourceId'; Facet = $true }
                @{ Key = 'Container'; Label = 'Container'; Type = 'mono' }
                @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = $statusTones; Facet = $true }
                @{ Key = 'BlobCount'; Label = 'Blobs'; Type = 'number'; Format = 'N0'; Sum = $true }
                @{ Key = 'SizeGiB'; Label = 'Size (GiB)'; Type = 'number'; Format = 'N2'; Sum = $true }
                @{ Key = 'SizeText'; Label = 'Size' }
                @{ Key = 'HotGiB'; Label = 'Hot GiB'; Type = 'number'; Format = 'N2'; Sum = $true }
                @{ Key = 'CoolGiB'; Label = 'Cool GiB'; Type = 'number'; Format = 'N2'; Sum = $true }
                @{ Key = 'ColdGiB'; Label = 'Cold GiB'; Type = 'number'; Format = 'N2'; Sum = $true }
                @{ Key = 'ArchiveGiB'; Label = 'Archive GiB'; Type = 'number'; Format = 'N2'; Sum = $true }
                @{ Key = 'NoTierGiB'; Label = 'No tier GiB'; Type = 'number'; Format = 'N2'; Sum = $true; Hidden = $true }
                @{ Key = 'LastModified'; Label = 'Last changed'; Type = 'datetime' }
                @{ Key = 'PublicAccess'; Label = 'Public access'; Facet = $true }
                @{ Key = 'Error'; Label = 'Why not read'; Type = 'wide' }
                @{ Key = 'TotalGiB'; Label = 'Total GiB'; Type = 'number'; Format = 'N2'; Sum = $true; Hidden = $true }
                @{ Key = 'Snapshots'; Label = 'Snapshots'; Type = 'number'; Format = 'N0'; Sum = $true; Hidden = $true }
                @{ Key = 'Versions'; Label = 'Versions'; Type = 'number'; Format = 'N0'; Sum = $true; Hidden = $true }
                @{ Key = 'DeletedBlobs'; Label = 'Deleted'; Type = 'number'; Format = 'N0'; Sum = $true; Hidden = $true }
                @{ Key = 'AuthMode'; Label = 'Read with'; Facet = $true; Hidden = $true }
                @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true; Hidden = $true }
                @{ Key = 'SubscriptionName'; Label = 'Subscription'; Facet = $true }
                @{ Key = 'Location'; Label = 'Region'; Facet = $true; Hidden = $true }
                @{ Key = 'Kind'; Label = 'Kind'; Facet = $true; Hidden = $true }
                @{ Key = 'Sku'; Label = 'SKU'; Facet = $true; Hidden = $true }
                @{ Key = 'Bytes'; Label = 'Bytes'; Type = 'number'; Format = 'N0'; Hidden = $true }
            )
        }
        @{
            Id = 'accounts'; Title = 'Storage accounts'; Noun = 'storage accounts'; File = 'storage-accounts'; Rows = $accounts; Sort = @{ Key = 'SizeGiB'; Desc = $true }
            Columns = @(
                @{ Key = 'StorageAccount'; Label = 'Storage account'; Type = 'resource'; IdKey = 'ResourceId' }
                @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = $statusTones; Facet = $true }
                @{ Key = 'Containers'; Label = 'Containers'; Type = 'number'; Format = 'N0'; Sum = $true }
                @{ Key = 'Failed'; Label = 'Not read'; Type = 'number'; Format = 'N0'; Sum = $true }
                @{ Key = 'BlobCount'; Label = 'Blobs'; Type = 'number'; Format = 'N0'; Sum = $true }
                @{ Key = 'SizeGiB'; Label = 'Size (GiB)'; Type = 'number'; Format = 'N2'; Sum = $true }
                @{ Key = 'SizeText'; Label = 'Size' }
                @{ Key = 'Kind'; Label = 'Kind'; Facet = $true }
                @{ Key = 'Sku'; Label = 'SKU'; Facet = $true }
                @{ Key = 'DataLake'; Label = 'Data Lake'; Facet = $true }
                @{ Key = 'NetworkAccess'; Label = 'Network access'; Facet = $true }
                @{ Key = 'Location'; Label = 'Region'; Facet = $true }
                @{ Key = 'SubscriptionName'; Label = 'Subscription'; Facet = $true }
                @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true; Hidden = $true }
                @{ Key = 'Reason'; Label = 'Why not read'; Type = 'wide' }
            )
        }
        if ($blobs.Count) {
            @{
                Id = 'blobs'; Title = 'Largest blobs'; Note = "The $($blobs.Count) largest blobs across every container read."; Noun = 'blobs'; File = 'largest-blobs'; Rows = $blobs; Sort = @{ Key = 'SizeGiB'; Desc = $true }
                Columns = @(
                    @{ Key = 'Name'; Label = 'Blob'; Type = 'wide' }
                    @{ Key = 'StorageAccount'; Label = 'Storage account'; Facet = $true }
                    @{ Key = 'Container'; Label = 'Container'; Facet = $true }
                    @{ Key = 'SizeGiB'; Label = 'Size (GiB)'; Type = 'number'; Format = 'N2' }
                    @{ Key = 'SizeText'; Label = 'Size' }
                    @{ Key = 'AccessTier'; Label = 'Tier'; Type = 'badge'; Tones = $tierTones; Facet = $true }
                    @{ Key = 'BlobType'; Label = 'Type'; Facet = $true }
                    @{ Key = 'LastModified'; Label = 'Last changed'; Type = 'datetime' }
                )
            }
        }
    )
    $notices = @(
        @{ Tone = 'info'; Text = ('Read {0:N0} blob(s) in {1:N1} seconds ({2:N0} a second). Sizes are the blobs'' content length, in powers of 1,024; what Azure bills can differ (metadata, minimum sizes, early deletion).' -f $stats.Blobs, $stats.Elapsed.TotalSeconds, $stats.BlobsPerSecond) }
        if ($notRead) { @{ Tone = 'bad'; Text = "$notRead container(s) or account(s) couldn't be read in full - see Why not read." } }
    )

    Write-AACHtmlReport -Path $Path -Title $Title -Subtitle 'Blob containers by size - access tiers, largest blobs, what couldn''t be read' -Fact $Detail -Tile $tiles -Chart $charts -Table $tables -Notice $notices
}
