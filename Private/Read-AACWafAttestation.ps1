function Read-AACWafAttestation {
    <#
    .SYNOPSIS
        Reads an answered Well-Architected questionnaire (the CSV
        Export-AACWafQuestionnaire writes) into the answers
        ConvertTo-AACWafAssessment scores.
    .DESCRIPTION
        Each row: Pillar, Principle, Question, Answer (Yes, Partly, No,
        NotApplicable, or empty for not answered yet), Evidence, Owner,
        AnsweredOn. Rows whose principle isn't in the catalogue, or whose
        answer is something else, are left out with a warning. Returns
        @(@{ Pillar; Principle; Question; Answer; Evidence; Owner }) - the
        answered rows only - and -Path must be a full path.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [hashtable] $Catalog
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $problem = [System.IO.FileNotFoundException]::new("Azure Admin Console can't find the questionnaire '$Path'.")
        $problem.Data['AACHint'] = 'Write one with Export-AACWafQuestionnaire, answer it, then pass its path to -AttestationPath.'
        throw $problem
    }
    $text = { param($Row, [string] $Name) $p = $Row.PSObject.Properties[$Name]; if ($p -and $null -ne $p.Value) { ([string]$p.Value).Trim() } else { '' } }
    $answers = @{ yes = 'Yes'; y = 'Yes'; partly = 'Partly'; partial = 'Partly'; no = 'No'; n = 'No'; notapplicable = 'NotApplicable'; na = 'NotApplicable'; 'n/a' = 'NotApplicable' }
    $line = 1
    foreach ($row in @(Import-Csv -LiteralPath $Path)) {
        $line++
        $pillar = & $text $row 'Pillar'
        $principle = & $text $row 'Principle'
        $raw = (& $text $row 'Answer').ToLowerInvariant() -replace '\s', ''
        if (-not $raw) { continue }
        $known = $Catalog.Principles.Contains($pillar) -and @($Catalog.Principles[$pillar] | Where-Object { $_.Name -eq $principle }).Count
        if (-not $known) { Write-Warning "Line $($line) of the questionnaire names '$pillar' / '$principle', which isn't a pillar and design principle the assessment knows; it's left out."; continue }
        if (-not $answers.Contains($raw)) { Write-Warning "Line $($line) of the questionnaire answers '$(& $text $row 'Answer')' for '$principle': use Yes, Partly, No or NotApplicable. It's left out."; continue }
        @{
            Pillar    = $pillar
            Principle = $principle
            Question  = $(if (& $text $row 'Question') { & $text $row 'Question' } else { $principle })
            Answer    = $answers[$raw]
            Evidence  = & $text $row 'Evidence'
            Owner     = & $text $row 'Owner'
        }
    }
}
