function Invoke-AACApplicationPermissionPlan {
    <#
    .SYNOPSIS
        Applies the changes Get-AACApplicationPermissionPlan planned, in
        order, with Microsoft Graph - and returns what happened to each.
    .DESCRIPTION
        The administrative unit and the custom role are created first; their
        new IDs take the place of '{au}' and '{role}' in the changes after
        them. Entra replicates a new object for a few seconds: a write that
        refers to one created moments ago and is refused as not found (404,
        or 400 "does not exist") is tried again, up to 6 times,
        -RetrySeconds apart.

        Not a transaction: the first failure stops; running the command
        again plans only what is still missing. Returns one row per change:
        Order, Action, Resource, Status (Applied, Failed, Skipped), Detail.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Change,

        [ValidateRange(0, 60)]
        [int] $RetrySeconds = 5
    )

    $ids = @{}
    $failed = $false
    $rows = [System.Collections.Generic.List[object]]::new()
    $writes = @($Change | Where-Object { $_.Action -ne 'NoChange' })
    foreach ($c in $Change) {
        if ($c.Action -eq 'NoChange') { continue }
        $row = [pscustomobject][ordered]@{ PSTypeName = 'AAC.ApplicationPermissionApplied'; Order = $c.Order; Action = $c.Action; Resource = $c.Resource; Status = 'Skipped'; Detail = '' }
        $rows.Add($row)
        if ($failed) { $row.Detail = 'Not tried: an earlier change failed.'; continue }
        Update-AACProgress -Id 'apply' -Description "$($c.Action): $($c.Resource)" -Total $writes.Count -Increment 1

        # The IDs created so far, in place of their placeholders.
        $uri = [string]$c.Uri
        $json = if ($null -ne $c.Body) { ConvertTo-Json -InputObject $c.Body -Depth 20 -Compress } else { $null }
        foreach ($key in $ids.Keys) { $uri = $uri.Replace($key, $ids[$key]); if ($json) { $json = $json.Replace($key, $ids[$key]) } }

        for ($attempt = 1; ; $attempt++) {
            try {
                $request = @{ Method = $c.Method; Uri = $uri; Resource = 'https://graph.microsoft.com' }
                if ($json) { $request.Body = $json }
                $response = Invoke-AACHttp @request
                $created = if ($response.Content) { ConvertFrom-Json -InputObject $response.Content -AsHashtable -Depth 20 } else { $null }
                if ($c.Action -eq 'Create' -and $created -and $created['id']) {
                    if ($c.Resource -like 'Administrative unit *') { $ids['{au}'] = [string]$created['id'] }
                    elseif ($c.Resource -like 'Role *') { $ids['{role}'] = [string]$created['id'] }
                }
                $row.Status = 'Applied'
                $row.Detail = $(if ($created -and $created['id']) { "ID $($created['id'])" } else { '' })
                break
            }
            catch {
                $status = $_.Exception.Data['StatusCode']
                $notYet = $ids.Count -and ($status -eq 404 -or ($status -eq 400 -and $_.Exception.Message -match 'does not exist|not found'))
                if ($notYet -and $attempt -lt 6) { if ($RetrySeconds) { Start-Sleep -Seconds $RetrySeconds }; continue }
                $row.Status = 'Failed'
                $row.Detail = $_.Exception.Message
                $failed = $true
                break
            }
        }
    }
    Update-AACProgress -Id 'apply' -Complete -Description "$(@($rows | Where-Object Status -EQ 'Applied').Count) of $($writes.Count) change(s) applied"
    , $rows.ToArray()
}
