function Invoke-AACStoragePlan {
    <#
    .SYNOPSIS
        Applies a storage plan's changes in order - the apply step of
        Deploy-AACStorageAccount.
    .DESCRIPTION
        Create, Update and Delete changes, in the plan's order (the account,
        its services, containers and the rest, private endpoints, diagnostic
        settings, role assignments, the lock, then blobs):
          Resource Manager   PUT, PATCH or DELETE (Invoke-AACArmWrite, which
                             waits for long-running operations)
          blobs              Put Blob with the file and its Content-MD5,
                             with the Connect-AAC sign-in (Entra ID) -
                             Storage Blob Data Contributor needed

        Not a transaction: the first failure stops the run - what came
        before stays applied (running again carries on from there, as every
        step is idempotent), what comes after is Skipped. A write a policy
        denies says so (RequestDisallowedByPolicy).

        Returns AAC.StorageApplyResult rows: Order, Resource, Action, Status
        (Applied, Failed, Skipped), Detail, Seconds.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Change
    )

    $writes = @($Change | Where-Object Action -In 'Create', 'Update', 'Delete')
    $results = [System.Collections.Generic.List[object]]::new()
    $failed = $false
    Update-AACProgress -Id 'apply' -Total ([Math]::Max($writes.Count, 1)) -Description "Applying $($writes.Count) change(s)"
    foreach ($item in $writes) {
        if ($failed) {
            $results.Add([pscustomobject]@{ PSTypeName = 'AAC.StorageApplyResult'; Order = $item.Order; Resource = $item.Resource; Action = $item.Action; Status = 'Skipped'; Detail = 'An earlier change failed.'; Seconds = 0 })
            continue
        }
        Update-AACProgress -Id 'apply' -Description "$($item.Action): $($item.Resource)"
        $clock = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            if ($item.Kind -eq 'blob') {
                $bytes = [System.IO.File]::ReadAllBytes($item.Source)
                $null = Invoke-AACHttp -Method Put -Uri $item.Id -Resource 'https://storage.azure.com' -BodyBytes $bytes -ContentType $item.ContentType -Header @{ 'x-ms-version' = '2023-11-03'; 'x-ms-blob-type' = 'BlockBlob'; 'Content-MD5' = $item.ContentMD5 }
            }
            else {
                $null = Invoke-AACArmWrite -Method $(if ($item.Action -eq 'Delete') { 'Delete' } else { $item.Method }) -Uri $item.Uri -Body $item.Body
            }
            $results.Add([pscustomobject]@{ PSTypeName = 'AAC.StorageApplyResult'; Order = $item.Order; Resource = $item.Resource; Action = $item.Action; Status = 'Applied'; Detail = ''; Seconds = [Math]::Round($clock.Elapsed.TotalSeconds, 1) })
        }
        catch {
            $failed = $true
            $code = [string]$_.Exception.Data['Code']
            $detail = if ($code -eq 'RequestDisallowedByPolicy') { "Denied by Azure Policy: $($_.Exception.Message)" } else { $_.Exception.Message }
            $results.Add([pscustomobject]@{ PSTypeName = 'AAC.StorageApplyResult'; Order = $item.Order; Resource = $item.Resource; Action = $item.Action; Status = 'Failed'; Detail = $detail; Seconds = [Math]::Round($clock.Elapsed.TotalSeconds, 1) })
        }
        Update-AACProgress -Id 'apply' -Increment 1
    }
    $applied = @($results | Where-Object Status -EQ 'Applied').Count
    Update-AACProgress -Id 'apply' -Complete -Description "Applied $applied of $($writes.Count) change(s)$(if ($failed) { ' - stopped at a failure' })"
    $results.ToArray()
}
