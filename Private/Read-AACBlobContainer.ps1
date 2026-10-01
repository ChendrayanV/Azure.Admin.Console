function Read-AACBlobContainer {
    <#
    .SYNOPSIS
        Lists the blobs of many containers at once - up to -ThrottleLimit
        containers in flight, each read a page of 5,000 blobs at a time - and
        adds up each container's blobs as its pages arrive.
    .DESCRIPTION
        -Container is a list of @{ Key; Url; Sas }: Url is the container's
        URL (the account's blob endpoint and the container's name); Sas is an
        account SAS to read it with, or empty to use an Entra ID token for
        Azure Storage from the Connect-AAC sign-in.

        The pages of one container follow each other (each needs the marker
        the last one returned); the containers run side by side over the
        module's pooled HTTPS connections (Invoke-AACHttpBatch), so a large
        estate takes about as long as its largest container. Each page is
        tallied and dropped as it arrives (ConvertFrom-AACBlobList), so
        memory stays flat unless -KeepBlob keeps every blob.

        -Include lists snapshots, versions and/or deleted blobs as well.
        -OnPage is called with (key, blobs added, bytes added) after each
        page, -OnDone with (key, error, done, total) as each container
        finishes. Throttling (503 ServerBusy, 429) and dropped connections
        are retried as Azure asks.

        Returns key -> @{ Tally (New-AACBlobTally); Error ('' when every page
        was read) }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Container,

        [ValidateSet('snapshots', 'versions', 'deleted')]
        [string[]] $Include,

        [int] $Top = 10,

        [switch] $KeepBlob,

        [ValidateRange(1, 64)]
        [int] $ThrottleLimit = 16,

        [scriptblock] $OnPage,

        [scriptblock] $OnDone
    )

    $result = @{}
    if (-not $Container.Count) { return $result }

    $includeQuery = if ($Include) { '&include=' + (($Include | Select-Object -Unique) -join ',') } else { '' }
    $pageUri = {
        param($Item, [string] $Marker)
        $uri = "$($Item.Url)?restype=container&comp=list&maxresults=5000$includeQuery"
        if ($Marker) { $uri += '&marker=' + [uri]::EscapeDataString($Marker) }
        if ($Item.Sas) { $uri += '&' + ([string]$Item.Sas).TrimStart('?') }
        $uri
    }

    $byKey = @{}
    $requests = @(foreach ($item in $Container) {
            $byKey[$item.Key] = $item
            $result[$item.Key] = @{ Tally = (New-AACBlobTally -KeepBlob:$KeepBlob); Error = '' }
            @{ Key = $item.Key; Uri = (& $pageUri $item ''); Anonymous = [bool]$item.Sas }
        })

    $onResponse = {
        param($Key, [System.Net.Http.HttpResponseMessage] $Response)
        $item = $byKey[$Key]
        $tally = $result[$Key].Tally
        $blobs = $tally.Blobs
        $bytes = $tally.Bytes
        $marker = ConvertFrom-AACBlobList -Response $Response -State $tally -Top $Top -StorageAccount $item.StorageAccount -Container $item.Container
        if ($OnPage) { & $OnPage $Key ($tally.Blobs - $blobs) ($tally.Bytes - $bytes) }
        if ($marker) { @{ Uri = (& $pageUri $item $marker) } }
    }
    # x-ms-version 2021-12-02 or later lists the Cold tier; later versions
    # change nothing this reads.
    $errors = Invoke-AACHttpBatch -Request $requests -OnResponse $onResponse -AsResponse -OnDone $OnDone -ThrottleLimit $ThrottleLimit `
        -Resource 'https://storage.azure.com' -Header @{ 'x-ms-version' = '2023-11-03' }
    foreach ($key in @($errors.Keys)) { $result[$key].Error = [string]$errors[$key] }
    $result
}
