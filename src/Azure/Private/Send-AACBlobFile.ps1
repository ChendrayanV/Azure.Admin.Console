function Send-AACBlobFile {
    <#
    .SYNOPSIS
        Uploads files to a blob container with the Azure Storage REST API
        (Put Blob) and an Entra ID token - no Az.Storage, no account key.
    .DESCRIPTION
        For Invoke-AACAssessment -StorageAccount/-StorageContainer (a
        scheduled run's reports): each file becomes a block blob named
        <-Prefix>/<its path under -Root>, replacing one of the same name.
        The signed-in identity needs Storage Blob Data Contributor on the
        account or container; the token is for https://storage.azure.com
        (Get-AACAccessToken -Resource), the managed identity's or service
        principal's in Azure Automation.

        Returns a line per file: @{ File; Blob; Url; Status; Error }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $StorageAccount,

        [Parameter(Mandatory)]
        [string] $Container,

        [Parameter(Mandatory)]
        [string[]] $Path,

        [Parameter(Mandatory)]
        [string] $Root,

        [string] $Prefix = ''
    )

    $ProgressPreference = 'SilentlyContinue'
    $token = Get-AACAccessToken -Resource 'https://storage.azure.com'
    $types = @{ '.html' = 'text/html; charset=utf-8'; '.csv' = 'text/csv; charset=utf-8'; '.pdf' = 'application/pdf'; '.json' = 'application/json' }
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    foreach ($file in $Path) {
        $full = [System.IO.Path]::GetFullPath($file)
        $relative = if ($full.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) { $full.Substring($rootFull.Length).TrimStart('\', '/') } else { [System.IO.Path]::GetFileName($full) }
        $blob = (@($Prefix.Trim('/'), ($relative -replace '\\', '/')) | Where-Object { $_ }) -join '/'
        $url = "https://$StorageAccount.blob.core.windows.net/$Container/$(($blob -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/')"
        $extension = [System.IO.Path]::GetExtension($full).ToLowerInvariant()
        $headers = @{ Authorization = "Bearer $token"; 'x-ms-version' = '2023-11-03'; 'x-ms-blob-type' = 'BlockBlob'; 'x-ms-blob-content-type' = $(if ($types.Contains($extension)) { $types[$extension] } else { 'application/octet-stream' }) }
        try {
            $null = Invoke-WebRequest -Uri $url -Method Put -Headers $headers -InFile $full -ContentType 'application/octet-stream' -ErrorAction Stop -Verbose:$false
            @{ File = $full; Blob = $blob; Url = $url; Status = 'Uploaded'; Error = '' }
        }
        catch {
            $reason = $_.Exception.Message
            if ($_.ErrorDetails -and $_.ErrorDetails.Message -match '<Message>([^<]+)') { $reason = ($Matches[1] -split '\r?\n')[0] }
            @{ File = $full; Blob = $blob; Url = $url; Status = 'Failed'; Error = $reason }
        }
    }
}
