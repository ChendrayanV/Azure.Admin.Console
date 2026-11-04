function Invoke-AACFindingReview {
    <#
    .SYNOPSIS
        Takes the findings of an assessment through what has already been decided
        and seen: the accepted ones set aside, and each of the others marked new or
        open against an earlier run.
    .DESCRIPTION
        Every finding gets a FindingKey, the same from run to run: 16 hex characters
        of a SHA-256 over its source, rule and subject. Those come from the finding's
        own fields, whatever its type (see Get-AACFindingIdentity).

        -Suppression is Read-AACSuppressionFile's result. A suppressed finding leaves
        Findings, so it is in no count, and goes to Suppressed with its reason, where
        the report still shows it. Nothing is deleted.

        -PreviousPath is a findings CSV written by an earlier run with -CsvPath, or
        the folder holding its findings.csv. Each finding's Change is then New or Open,
        and what has gone is in Resolved. A finding suppressed since isn't resolved.
        A CSV with no FindingKey column stops the run: calling everything New would
        be wrong, and nothing would say so.

        -Stats, an assessment's counts, is corrected in place: Findings, and each
        severity it has a count for.

        Returns @{ Findings; Suppressed; Resolved; Notices; Summary (@{ New; Open;
        Resolved; Suppressed; Expired; Compared }) }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyCollection()]
        [object[]] $Finding = @(),

        [hashtable] $Suppression,

        [string] $PreviousPath,

        [System.Collections.IDictionary] $Stats
    )

    $notices = [System.Collections.Generic.List[string]]::new()
    $kept = [System.Collections.Generic.List[object]]::new()
    $suppressed = [System.Collections.Generic.List[object]]::new()
    $active = @(if ($Suppression) { $Suppression.Active })
    $used = [System.Collections.Generic.HashSet[int]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    $setAside = [System.Collections.Generic.HashSet[string]]::new()

    # Read first: if this fails, nothing has been changed.
    $earlier = $null
    if ($PreviousPath) {
        $file = $PreviousPath
        if (Test-Path -LiteralPath $PreviousPath -PathType Container) {
            $file = Join-Path -Path $PreviousPath -ChildPath 'findings.csv'
            # The Microsoft 365 assessment's files start with its name.
            $named = Join-Path -Path $PreviousPath -ChildPath 'm365-findings.csv'
            if (-not (Test-Path -LiteralPath $file) -and (Test-Path -LiteralPath $named)) { $file = $named }
        }
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw [System.InvalidOperationException]::new("Azure Admin Console couldn't find an earlier run's findings at $file. Point -PreviousPath at a findings CSV written with -CsvPath.") }
        $earlier = @(Import-Csv -LiteralPath $file)
        if ($earlier.Count -and -not $earlier[0].PSObject.Properties['FindingKey']) { throw [System.InvalidOperationException]::new("Azure Admin Console can't compare with $file`: it has no FindingKey column, so it came from an older version or another command. Run once with -CsvPath, then compare with that file.") }
    }

    foreach ($row in $Finding) {
        if ($null -eq $row) { continue }
        $identity = Get-AACFindingIdentity -Finding $row
        $row | Add-Member -NotePropertyName 'FindingKey' -NotePropertyValue $identity.Key -Force
        $match = $null
        for ($i = 0; $i -lt $active.Count; $i++) {
            $entry = $active[$i]
            $fits = if ($entry.Key) { $entry.Key -ieq $identity.Key } else { $entry.Source -ieq $identity.Source -and $identity.Rule -like $entry.Rule -and (-not $entry.Subject -or $identity.Subject -like $entry.Subject) }
            if ($fits) { $match = $entry; [void]$used.Add($i); break }
        }
        if ($match) {
            $row | Add-Member -NotePropertyMembers ([ordered]@{ SuppressionReason = $match.Reason; SuppressedUntil = $(if ($match.Expires) { $match.Expires.ToString('yyyy-MM-dd') } else { '' }) }) -Force
            $suppressed.Add($row)
            [void]$setAside.Add($identity.Key)
            continue
        }
        [void]$seen.Add($identity.Key)
        if ($null -ne $earlier) { $row | Add-Member -NotePropertyName 'Change' -NotePropertyValue '' -Force }
        $kept.Add($row)
    }

    $resolved = [System.Collections.Generic.List[object]]::new()
    $counts = @{ New = 0; Open = 0 }
    if ($null -ne $earlier) {
        $before = [System.Collections.Generic.HashSet[string]]::new([string[]]@($earlier | ForEach-Object { [string]$_.FindingKey }), [System.StringComparer]::OrdinalIgnoreCase)
        foreach ($row in $kept) {
            $row.Change = if ($before.Contains($row.FindingKey)) { 'Open' } else { 'New' }
            $counts[$row.Change]++
        }
        foreach ($old in $earlier) {
            if ($seen.Contains([string]$old.FindingKey) -or $setAside.Contains([string]$old.FindingKey)) { continue }
            $identity = Get-AACFindingIdentity -Finding $old
            $resolved.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.ResolvedFinding'; Severity = [string]$old.Severity; Finding = $identity.Rule; Subject = $identity.Subject; FindingKey = [string]$old.FindingKey })
        }
    }

    $expired = @(if ($Suppression) { $Suppression.Expired })
    if ($expired.Count) { $notices.Add("$($expired.Count) suppression(s) have expired and were ignored: $(@($expired | Select-Object -First 3 | ForEach-Object { if ($_.Key) { $_.Key } else { "$($_.Source): $($_.Rule)" } }) -join '; ')$(if ($expired.Count -gt 3) { '; ...' }). Review them, then renew or remove them.") }
    $unused = $active.Count - $used.Count
    if ($unused -gt 0) { $notices.Add("$unused suppression(s) matched no finding: the finding is gone, or the entry is mistyped.") }
    if ($suppressed.Count) { $notices.Add("$($suppressed.Count) finding(s) suppressed, and left out of the counts. The report lists them with their reasons.") }
    if ($null -ne $earlier) { $notices.Add("Compared with the earlier run: $($counts.New) new, $($counts.Open) still open, $($resolved.Count) resolved.") }

    if ($Stats) {
        if ($Stats.Contains('Findings')) { $Stats['Findings'] = $kept.Count }
        foreach ($level in 'Critical', 'High', 'Medium', 'Low', 'Info') {
            if ($Stats.Contains($level)) { $Stats[$level] = @($kept | Where-Object Severity -EQ $level).Count }
        }
    }

    @{
        Findings   = $kept.ToArray()
        Suppressed = $suppressed.ToArray()
        Resolved   = $resolved.ToArray()
        Notices    = $notices.ToArray()
        Summary    = @{ New = $counts.New; Open = $counts.Open; Resolved = $resolved.Count; Suppressed = $suppressed.Count; Expired = $expired.Count; Compared = $null -ne $earlier }
    }
}
