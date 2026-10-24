function Read-AACKeyVaultLog {
    <#
    .SYNOPSIS
        Reads Key Vault audit logs (AuditEvent) from the workspaces the vaults
        send them to - the workbook's Operations tab - by vault, operation
        and caller.
    .DESCRIPTION
        One query per workspace (Invoke-AACLogQueryBatch), over both tables a
        vault can write to: AzureDiagnostics (Category AuditEvent) and the
        resource-specific AZKVAuditLogs. column_ifexists keeps it working when
        a workspace lacks a column; union isfuzzy when it lacks a table.
        As in the workbook, an Authentication call answered 401 is left out:
        it is the SDK's normal challenge before it authenticates.

        -Workspace: @{ workspace query ID (customerId) = @(vault IDs) }.
        Returns @{ Rows = @(@{ VaultId; Operation; Caller; CallerIp; Count;
        Failed; AuthDenied; Throttled; P99Ms }); Errors = @{ customerId =
        reason } }. Needs Log Analytics Reader on the workspaces.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Workspace,

        # ISO 8601 duration, e.g. P1D.
        [Parameter(Mandatory)]
        [string] $Duration
    )

    $rows = [System.Collections.Generic.List[object]]::new()
    $errors = @{}
    foreach ($customerId in @($Workspace.Keys)) {
        $ids = (@($Workspace[$customerId] | ForEach-Object { "'$($_.ToLowerInvariant())'" }) -join ', ')
        $kql = @"
union isfuzzy=true
  (AzureDiagnostics | where Category == 'AuditEvent'
     | project TimeGenerated, VaultId = tolower(ResourceId), Operation = OperationName, Status = toint(column_ifexists('httpStatusCode_d', real(null))),
               DurationMs = todouble(column_ifexists('DurationMs', real(null))),
               Caller = coalesce(tostring(column_ifexists('identity_claim_appid_g', '')), tostring(column_ifexists('identity_claim_oid_g', '')), tostring(column_ifexists('identity_claim_upn_s', ''))),
               CallerIp = tostring(column_ifexists('CallerIPAddress', ''))),
  (AZKVAuditLogs
     | project TimeGenerated, VaultId = tolower(_ResourceId), Operation = OperationName, Status = toint(column_ifexists('HttpStatusCode', int(null))),
               DurationMs = todouble(column_ifexists('DurationMs', real(null))),
               Caller = coalesce(tostring(column_ifexists('Identity', dynamic(null)).claim.appid), tostring(column_ifexists('Identity', dynamic(null)).claim.oid)),
               CallerIp = tostring(column_ifexists('CallerIpAddress', '')))
| where VaultId in ($ids)
| where not (Operation == 'Authentication' and Status == 401)
| summarize Count = count(), Failed = countif(Status >= 400), AuthDenied = countif(Status in (401, 403)), Throttled = countif(Status == 429), P99Ms = percentile(DurationMs, 99)
          by VaultId, Operation, Caller, CallerIp
| top 2000 by Count
"@
        $answer = Invoke-AACLogQueryBatch -WorkspaceId $customerId -Query @{ audit = $kql } -Timespan $Duration
        if ($answer.Errors.Contains('audit')) { $errors[$customerId] = [string]$answer.Errors['audit']; continue }
        foreach ($r in @($answer.Rows['audit'])) { if ($null -ne $r) { $rows.Add($r) } }
    }
    @{ Rows = $rows.ToArray(); Errors = $errors }
}
