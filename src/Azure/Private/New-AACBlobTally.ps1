function New-AACBlobTally {
    <#
    .SYNOPSIS
        An empty running total for one blob container
        (AzureAdminConsole.BlobTally), which ConvertFrom-AACBlobList adds each
        page of its blob list to.
    .DESCRIPTION
        Blobs and Bytes count the current blobs; snapshots, previous
        versions and soft-deleted blobs (listed only when asked for) are
        counted on their own, as are Data Lake Storage directories. Tiers
        maps an access tier ('Hot', 'Cool', 'Cold', 'Archive', or 'None' for
        page, append and premium blobs) to @(count, bytes). Largest holds the
        -Top largest current blobs. With -KeepBlob, Rows keeps every blob
        listed as an AzureAdminConsole.StorageBlob. See
        Import-AACBlobListParser.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Returns a new object; nothing outside it changes.')]
    [OutputType('AzureAdminConsole.BlobTally')]
    param(
        [switch] $KeepBlob
    )

    Import-AACBlobListParser
    [AzureAdminConsole.BlobTally]::new([bool]$KeepBlob)
}
