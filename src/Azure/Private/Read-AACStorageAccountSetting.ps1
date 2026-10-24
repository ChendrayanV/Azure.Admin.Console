function Read-AACStorageAccountSetting {
    <#
    .SYNOPSIS
        Reads each storage account's data protection, lifecycle and logging
        settings - what Resource Graph doesn't carry - several accounts at
        once.
    .DESCRIPTION
        Per account, through Invoke-AACArmParallel (Reader is enough):
          Blob       {id}/blobServices/default: blob and container soft
                     delete, versioning, change feed, point-in-time restore
          File       {id}/fileServices/default: file share soft delete
          Lifecycle  {id}/managementPolicies/default: lifecycle rules (404
                     when there are none)
          Logs       {id}/blobServices/default/providers/Microsoft.Insights/
                     diagnosticSettings: where the blob logs go
        -Account: @(@{ Id; Blob (bool); File (bool) }) - Blob and File say
        whether the account's kind has that service, so a FileStorage
        account isn't asked for blob settings and the other way round.
        Returns @{ account id = @{ Blob; File; Lifecycle; Logs (each
        Invoke-AACArmParallel's result, or $null when not asked) } }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Account,

        [ValidateRange(1, 32)]
        [int] $ThrottleLimit = 12,

        [scriptblock] $OnProgress
    )

    $api = 'api-version=2023-05-01'
    $uris = [ordered]@{}
    foreach ($a in $Account) {
        if ($a.Blob) {
            $uris["$($a.Id)|Blob"] = "$($a.Id)/blobServices/default?$api"
            $uris["$($a.Id)|Lifecycle"] = "$($a.Id)/managementPolicies/default?$api"
            $uris["$($a.Id)|Logs"] = "$($a.Id)/blobServices/default/providers/Microsoft.Insights/diagnosticSettings?api-version=2021-05-01-preview"
        }
        if ($a.File) { $uris["$($a.Id)|File"] = "$($a.Id)/fileServices/default?$api" }
    }
    $answers = if ($uris.Count) { Invoke-AACArmParallel -Uri @($uris.Values) -ThrottleLimit $ThrottleLimit -OnProgress $OnProgress } else { @{} }
    $out = @{}
    foreach ($a in $Account) { $out[$a.Id] = @{ Blob = $null; File = $null; Lifecycle = $null; Logs = $null } }
    foreach ($key in $uris.Keys) {
        $id, $part = $key -split '\|', 2
        $out[$id][$part] = $answers[$uris[$key]]
    }
    $out
}
