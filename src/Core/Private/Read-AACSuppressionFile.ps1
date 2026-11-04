function Read-AACSuppressionFile {
    <#
    .SYNOPSIS
        Reads a -SuppressionFile: the findings you have reviewed and accepted, each
        with its reason.
    .DESCRIPTION
        A JSON array. An entry names a finding by its FindingKey, or by source and
        rule (and a subject, which may use wildcards):

          [
            { "key": "a1b2c3d4e5f60718", "reason": "Accepted by the security board, 2026-09" },
            { "source": "Aks", "rule": "Private API server", "subject": "aks-dev*",
              "reason": "Dev clusters stay public", "expires": "2027-01-01" }
          ]

        Every entry needs a reason, and expires is optional. An expired entry is
        reported and does nothing. A file that can't be understood stops the run: a
        report that quietly suppressed nothing, or too much, would mislead.

        Returns @{ Active (@{ Key; Source; Rule; Subject; Reason; Expires }); Expired }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [datetime] $Now = (Get-Date)
    )

    $problem = { param([string] $Text) [System.InvalidOperationException]::new("Azure Admin Console couldn't use the suppression file ${Path}: $Text Fix the file, or leave out -SuppressionFile.") }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw (& $problem "the file doesn't exist.") }
    try { $entries = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($Path)) -AsHashtable -NoEnumerate -ErrorAction Stop }
    catch { throw (& $problem "it isn't valid JSON ($($_.Exception.Message -replace '\s+', ' ')).") }
    if ($entries -isnot [System.Collections.IList]) { throw (& $problem 'it has to be a JSON array of entries.') }

    $active = [System.Collections.Generic.List[object]]::new()
    $expired = [System.Collections.Generic.List[object]]::new()
    $number = 0
    foreach ($entry in $entries) {
        $number++
        if ($entry -isnot [System.Collections.IDictionary]) { throw (& $problem "entry $number isn't an object.") }
        $reason = [string]$entry['reason']
        if (-not $reason.Trim()) { throw (& $problem "entry $number has no reason, and every suppression needs one.") }
        $key = [string]$entry['key']
        $source = [string]$entry['source']
        $rule = [string]$entry['rule']
        if (-not $key -and -not ($source -and $rule)) { throw (& $problem "entry $number needs a key, or a source and a rule.") }
        $expires = $null
        if ($entry['expires']) {
            $parsed = [datetime]::MinValue
            if ($entry['expires'] -is [datetime]) { $parsed = $entry['expires'] }
            elseif (-not [datetime]::TryParse([string]$entry['expires'], [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) { throw (& $problem "entry $number has an expiry date that can't be read: $($entry['expires']).") }
            $expires = $parsed
        }
        $row = @{ Key = $key; Source = $source; Rule = $rule; Subject = [string]$entry['subject']; Reason = $reason.Trim(); Expires = $expires }
        if ($expires -and $expires -lt $Now) { $expired.Add($row) } else { $active.Add($row) }
    }
    @{ Active = $active.ToArray(); Expired = $expired.ToArray() }
}
