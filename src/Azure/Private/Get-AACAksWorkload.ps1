function Get-AACAksWorkload {
    <#
    .SYNOPSIS
        Reads what is running inside one AKS cluster - pods, workloads, nodes,
        namespaces, services, storage and RBAC - with AKS's run command, for
        ConvertTo-AACAksWorkload.
    .DESCRIPTION
        Two commands, each `kubectl get` piped through jq, so only the fields
        named here ever leave the cluster. Secrets and ConfigMaps are never read,
        and of a container's environment only the number of variables that come
        from a secret is: no value is in the output. Nothing is changed in the
        cluster, beyond the short-lived pod AKS starts for each command.

        Run command's output stops at 512 kB. To fit, pods of one workload come
        back as one row (a large cluster has far fewer workloads than pods), each
        record is a line of its own, and the two commands have a budget each. A
        command's last line is AAC_END, so a cut-off answer shows: its kinds are
        listed in Unread, as are those kubectl was refused or couldn't list, and
        nothing may be called fine on the strength of them.

        Returns @{ Rows; Unread (kinds not fully read); Status ('OK', or why
        nothing could be read) }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $ClusterId,

        [switch] $EntraId,

        [ValidateRange(1, 30)]
        [int] $TimeoutMinutes = 5,

        [ValidateRange(1, 60)]
        [int] $PollSeconds = 5
    )

    $rows = [System.Collections.Generic.List[object]]::new()
    $unread = [System.Collections.Generic.HashSet[string]]::new()
    $problems = [System.Collections.Generic.List[string]]::new()
    $commands = @(Get-AACAksWorkloadCommand)
    foreach ($entry in $commands) {
        $run = Invoke-AACAksRunCommand -ClusterId $ClusterId -Command $entry.Command -EntraId:$EntraId -TimeoutMinutes $TimeoutMinutes -PollSeconds $PollSeconds
        if ($run.Status -ne 'OK') {
            $problems.Add($run.Status)
            foreach ($kind in $entry.Kinds) { [void]$unread.Add($kind) }
            continue
        }
        $finished = $false
        $damaged = $false
        foreach ($line in $run.Logs -split '\r?\n') {
            if (-not $line.Trim()) { continue }
            if ($line.Trim() -eq 'AAC_END') { $finished = $true; continue }
            $row = try { ConvertFrom-Json -InputObject $line -AsHashtable -ErrorAction Stop } catch { $null }
            if ($row -isnot [System.Collections.IDictionary]) { $damaged = $true; continue }
            if ($row['t'] -eq 'error') { [void]$unread.Add([string]$row['k']) }
            else { $rows.Add($row) }
        }
        if (-not $finished -or $damaged) { foreach ($kind in $entry.Kinds) { [void]$unread.Add($kind) } }
    }
    @{
        Rows   = $rows.ToArray()
        Unread = @($unread | Sort-Object)
        # Nothing read at all is a failed read. Something read, with gaps, still has answers to give.
        Status = $(if ($problems.Count -eq $commands.Count) { $problems[0] } else { 'OK' })
    }
}
