function ConvertTo-AACArchitectureBrief {
    <#
    .SYNOPSIS
        Turns answers to the probe questions into an architecture brief:
        every question asked or defaulted, in catalog order, with what is
        still open.
    .DESCRIPTION
        For each question, in order (a question's Ask decides whether it
        applies, given the answers so far):
          - an answer given in -Answer is checked (a choice must be one of
            the question's, in any case; a number must be a number) - "?",
            "unknown" or "don't know" uses the default and marks it open
          - otherwise -Ask (a script block: param($Question, $Default) ->
            @{ Value; Unknown }) asks it, when given (interactive)
          - otherwise the default is used and recorded as an assumption
        Returns @{ Name; CatalogVersion; Created; Answers (ordered); Open
        (IDs answered "don't know"); Assumed (IDs defaulted without being
        asked); Rows (one per question, for the view) }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Catalog,

        [System.Collections.IDictionary] $Answer = @{},

        [scriptblock] $Ask,

        [string] $Name = 'workload'
    )

    $answers = [ordered]@{}
    $open = [System.Collections.Generic.List[string]]::new()
    $assumed = [System.Collections.Generic.List[string]]::new()
    $rows = [System.Collections.Generic.List[object]]::new()
    $given = @{}
    foreach ($key in $Answer.Keys) { $given[([string]$key).ToUpperInvariant()] = $Answer[$key] }
    $unknownWords = @('?', 'unknown', "don't know", 'dont know')

    foreach ($q in $Catalog.Questions) {
        if ($q.Contains('Ask') -and $q.Ask -and -not (& $q.Ask $answers)) { continue }
        $default = if ($q.Default -is [scriptblock]) { & $q.Default $answers } else { $q.Default }
        $source = 'Answered'
        $value = $null
        if ($given.Contains($q.Id)) {
            $raw = $given[$q.Id]
            if (@($raw | Where-Object { $unknownWords -contains ([string]$_).ToLowerInvariant() }).Count) { $value = $default; $source = 'Unknown - default used'; $open.Add($q.Id) }
            else {
                $value = switch ($q.Type) {
                    'Number' {
                        $n = 0.0
                        if (-not [double]::TryParse([string]$raw, [System.Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref]$n)) { throw "Azure Admin Console can't use '$raw' for $($q.Id) ($($q.Text)): give a number." }
                        $n
                    }
                    'Text' { [string]$raw }
                    default {
                        $picked = @(foreach ($item in @($raw)) {
                                $match = @($q.Choices | Where-Object { $_ -eq [string]$item }) | Select-Object -First 1
                                if (-not $match) { throw "Azure Admin Console can't use '$item' for $($q.Id) ($($q.Text)): choose $(@($q.Choices | ForEach-Object { "'$_'" }) -join ', ')." }
                                $match
                            })
                        if ($q.Type -eq 'MultiChoice') { , $picked } elseif ($picked.Count -gt 1) { throw "Azure Admin Console can't use several answers for $($q.Id) ($($q.Text)): choose one." } else { $picked[0] }
                    }
                }
            }
        }
        elseif ($Ask) {
            $reply = & $Ask $q $default
            $value = $reply.Value
            if ($reply.Unknown) { $source = 'Unknown - default used'; $open.Add($q.Id) }
        }
        else { $value = $default; $source = 'Default (assumed)'; $assumed.Add($q.Id) }
        if ($q.Type -eq 'MultiChoice') { $value = @($value | Where-Object { $_ }) }
        $answers[$q.Id] = $value
        $rows.Add([pscustomobject][ordered]@{
                PSTypeName = 'AAC.ArchitectureAnswer'; Id = $q.Id; Category = $q.Category; Question = $q.Text; Answer = $(if ($value -is [array]) { $value -join ', ' } else { [string]$value }); Source = $source; Pillar = $q.Pillar
            })
    }
    foreach ($key in $given.Keys) { if (-not @($Catalog.Questions | Where-Object { $_.Id -eq $key }).Count) { throw "Azure Admin Console doesn't know the question '$key'. The questions are $(@($Catalog.Questions | ForEach-Object Id) -join ', ')." } }
    @{ Name = $Name; CatalogVersion = $Catalog.Version; Created = [datetime]::UtcNow.ToString('o'); Answers = $answers; Open = $open.ToArray(); Assumed = $assumed.ToArray(); Rows = $rows.ToArray() }
}
