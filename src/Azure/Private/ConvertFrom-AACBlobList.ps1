function ConvertFrom-AACBlobList {
    <#
    .SYNOPSIS
        Adds one page of an Azure Storage List Blobs response (XML) to a
        container's running total (New-AACBlobTally), and returns the marker
        of the next page - empty on the last.
    .DESCRIPTION
        A page holds up to 5,000 blobs; it is read by the compiled parser
        (Import-AACBlobListParser), which tallies each blob as it goes
        without building an XML document, so a container of millions of
        blobs takes no more memory than one page. A blob is counted as one
        of:
          deleted     <Deleted>true</Deleted> (soft delete, -IncludeDeleted)
          snapshot    it has a <Snapshot> time
          version     it has a <VersionId> but isn't the current version
          directory   <ResourceType>directory</ResourceType> (Data Lake
                      Storage Gen2: a folder, not data)
          blob        everything else - the current blobs
        -StorageAccount and -Container are written on the blobs kept (the
        -Top largest, and every one with New-AACBlobTally -KeepBlob).

        -Response is the page as Azure Storage answered it: the parser reads
        the body itself, so the text never passes through PowerShell into a
        .NET call (which hands its arguments to AMSI - a few hundred
        milliseconds for a page of 5,000 blobs). -Content is the page's text.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Response')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Response')]
        [System.Net.Http.HttpResponseMessage] $Response,

        [Parameter(Mandatory, ParameterSetName = 'Content')]
        [AllowEmptyString()]
        [string] $Content,

        # An AzureAdminConsole.BlobTally - not typed here: that type is
        # compiled on first use, after this file is loaded.
        [Parameter(Mandatory)]
        [object] $State,

        # How many of the largest blobs to keep.
        [int] $Top = 10,

        [string] $StorageAccount,

        [string] $Container
    )

    if ($PSCmdlet.ParameterSetName -eq 'Response') {
        return [AzureAdminConsole.BlobListParser]::ParseBody($Response.Content.ReadAsStringAsync(), $State, $Top, $StorageAccount, $Container)
    }
    [AzureAdminConsole.BlobListParser]::Parse($Content, $State, $Top, $StorageAccount, $Container)
}
