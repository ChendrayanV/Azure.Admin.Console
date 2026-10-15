function Export-AACWafQuestionnaire {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Writes the Well-Architected questionnaire - one question per design
        principle, for what no API can test - as a CSV the team answers and
        Invoke-AACWafAssessment -AttestationPath scores.
    .DESCRIPTION
        One row per design principle of each pillar (-Pillar, all five by
        default): Pillar, Principle, Question, Answer, Evidence, Owner,
        AnsweredOn, and Learn (the principle on Microsoft Learn). Open it in
        Excel or any editor and fill in:
          Answer      Yes, Partly, No or NotApplicable (empty: not answered
                      yet - the principle stays not assessed unless a check
                      covers it)
          Evidence    where to find the proof: a wiki page, a test report, a
                      ticket
          Owner       who answered, or who owns the gap
        Yes scores 100, Partly 50, No 0; NotApplicable leaves it out.

        Nothing in Azure is read or changed. An existing file is only
        replaced with -Force (its answers would be lost).
    .PARAMETER Path
        Where to write the CSV.
    .PARAMETER Pillar
        Only these pillars' principles.
    .PARAMETER Force
        Replace the file if it exists.
    .EXAMPLE
        Export-AACWafQuestionnaire -Path .\waf-answers.csv
        All 24 design principles' questions, ready to answer.
    .EXAMPLE
        Export-AACWafQuestionnaire -Path .\reliability.csv -Pillar Reliability
        Then: Invoke-AACWafAssessment -Pillar Reliability -AttestationPath .\reliability.csv
    .OUTPUTS
        System.IO.FileInfo
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [ValidateSet('Reliability', 'Security', 'Cost Optimization', 'Operational Excellence', 'Performance Efficiency')]
        [string[]] $Pillar = @('Reliability', 'Security', 'Cost Optimization', 'Operational Excellence', 'Performance Efficiency'),

        [switch] $Force
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $fullPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    if ((Test-Path -LiteralPath $fullPath) -and -not $Force) {
        $problem = [System.IO.IOException]::new("Azure Admin Console didn't replace '$fullPath': it exists, and its answers would be lost.")
        $problem.Data['AACHint'] = 'Add -Force to replace it, or choose another -Path.'
        throw $problem
    }
    $catalog = Get-AACWafCatalog
    $rows = foreach ($p in @($catalog.Principles.Keys | Where-Object { $_ -in $Pillar })) {
        foreach ($principle in $catalog.Principles[$p]) {
            [pscustomobject][ordered]@{ Pillar = $p; Principle = $principle.Name; Question = $principle.Question; Answer = ''; Evidence = ''; Owner = ''; AnsweredOn = ''; Learn = $principle.Link }
        }
    }
    $folder = Split-Path -Path $fullPath -Parent
    if ($folder -and -not (Test-Path -LiteralPath $folder)) { $null = New-Item -ItemType Directory -Path $folder -Force }
    @($rows) | Export-Csv -LiteralPath $fullPath -NoTypeInformation -Encoding utf8
    Write-AACMarkup "[grey58]Wrote $(@($rows).Count) question(s) to $([Spectre.Console.Markup]::Escape($fullPath)). Answer Yes, Partly, No or NotApplicable, then pass it to Invoke-AACWafAssessment -AttestationPath.[/]"
    Get-Item -LiteralPath $fullPath
}
