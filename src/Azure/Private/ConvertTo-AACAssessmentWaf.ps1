function ConvertTo-AACAssessmentWaf {
    <#
    .SYNOPSIS
        Builds Invoke-AACTenantAssessment's Well-Architected sheets from
        ConvertTo-AACWafAssessment's result - the same checks and scores as
        Invoke-AACWafAssessment, across the tenant.
    .DESCRIPTION
        Sheets, in ConvertTo-AACAssessment's shape (Kind and Category
        'Well-Architected'):
          WAF pillars            each pillar's score (0-100) and maturity
          WAF design principles  each principle's score, or 'Not assessed'
                                 where no check covers it
          WAF checks             each check: evaluated, passed, failed, score
          WAF findings           each failed check on each resource, with
                                 what to do - most severe first
        -ResourceId (lower case), when given, keeps only the findings on
        those resources (and on subscriptions and resource groups): the
        tag filter of the assessment, which the WAF read can't apply.
        Returns @{ Sheets; Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Waf,

        [System.Collections.Generic.HashSet[string]] $ResourceId
    )

    $slug = { param([string] $Name) ($Name.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-') }
    $newSheet = {
        param([string] $Name, [System.Collections.IDictionary] $Types, [object[]] $Rows, [string[]] $Key, [string] $Note)
        @{ Id = & $slug $Name; Kind = 'Well-Architected'; Category = 'Well-Architected'; Sheet = $Name; Columns = @($Types.Keys); Types = $Types; Rows = @($Rows); Key = @($Key); Error = ''; Note = $Note }
    }
    $severityRank = @{ High = 0; Medium = 1; Low = 2 }
    $kept = {
        param([string] $Id)
        -not $ResourceId -or -not $ResourceId.Count -or $ResourceId.Contains($Id.ToLowerInvariant()) -or $Id -notmatch '(?i)/providers/'
    }

    $pillarRows = @(foreach ($p in @($Waf.Pillars)) {
            [pscustomobject][ordered]@{
                'Pillar' = $p.Pillar; 'Score' = $p.Score; 'Maturity' = $p.Maturity; 'Principles' = $p.Principles
                'Checks' = $p.Checks; 'Evaluated' = $p.Evaluated; 'Failed' = $p.Failed; 'ResourceId' = ''
            }
        })
    $principleRows = @(foreach ($p in @($Waf.Principles)) {
            [pscustomobject][ordered]@{
                'Pillar' = $p.Pillar; 'Design principle' = $p.Principle; 'Score' = $p.Score; 'Checks' = $p.Checks
                'Evaluated' = $p.Evaluated; 'Failed' = $p.Failed; 'Coverage' = $p.Coverage; 'Link' = $p.Link; 'ResourceId' = ''
            }
        })
    $checkRows = @(foreach ($c in @($Waf.Checks) | Sort-Object Pillar, CheckId) {
            [pscustomobject][ordered]@{
                'Pillar' = $c.Pillar; 'Design principle' = $c.Principle; 'Check ID' = $c.CheckId; 'Check' = $c.Check; 'Severity' = $c.Severity
                'Source' = $c.Source; 'Evaluated' = $c.Evaluated; 'Passed' = $c.Passed; 'Failed' = $c.Failed; 'Score' = $c.Score
                'Status' = $c.Status; 'Recommendation' = $c.Recommendation; 'Link' = $c.Link; 'ResourceId' = ''
            }
        })
    $failed = @(@($Waf.Results) | Where-Object { $_.Status -in 'Fail', 'Partly' -and (& $kept ([string]$_.ResourceId)) })
    $findingRows = @(foreach ($r in $failed | Sort-Object { if ($severityRank.Contains([string]$_.Severity)) { $severityRank[[string]$_.Severity] } else { 3 } }, Pillar, CheckId, Resource) {
            [pscustomobject][ordered]@{
                'Severity' = $r.Severity; 'Pillar' = $r.Pillar; 'Design principle' = $r.Principle; 'Check ID' = $r.CheckId; 'Check' = $r.Check
                'Status' = $r.Status; 'Resource' = $r.Resource; 'Resource type' = $r.ResourceType; 'Resource group' = $r.ResourceGroup
                'Subscription' = $r.Subscription; 'Detail' = $r.Detail; 'Recommendation' = $r.Recommendation; 'Link' = $r.Link; 'ResourceId' = $r.ResourceId
            }
        })

    $sheets = @(
        & $newSheet 'WAF pillars' ([ordered]@{ 'Pillar' = 'text'; 'Score' = 'score'; 'Maturity' = 'badge'; 'Principles' = 'text'; 'Checks' = 'number'; 'Evaluated' = 'number'; 'Failed' = 'number' }) $pillarRows `
            @('Pillar', 'Score', 'Maturity', 'Failed') 'The five pillars of the Azure Well-Architected Framework, scored out of 100: each check''s share of resources that pass, weighted by severity (High 3, Medium 2, Low 1). Maturity: Initial (under 50), Developing, Established (75+), Optimised (90+).'
        & $newSheet 'WAF design principles' ([ordered]@{ 'Pillar' = 'text'; 'Design principle' = 'text'; 'Score' = 'score'; 'Checks' = 'number'; 'Evaluated' = 'number'; 'Failed' = 'number'; 'Coverage' = 'text'; 'Link' = 'link' }) $principleRows `
            @('Pillar', 'Design principle', 'Score', 'Coverage') 'A principle no automated check covers needs a review: Export-AACWafQuestionnaire and Invoke-AACWafAssessment -AttestationPath score the team''s answers.'
        & $newSheet 'WAF checks' ([ordered]@{ 'Pillar' = 'text'; 'Design principle' = 'text'; 'Check ID' = 'mono'; 'Check' = 'wide'; 'Severity' = 'badge'; 'Source' = 'text'; 'Evaluated' = 'number'; 'Passed' = 'number'; 'Failed' = 'number'; 'Score' = 'score'; 'Status' = 'badge'; 'Recommendation' = 'wide'; 'Link' = 'link' }) $checkRows `
            @('Check ID', 'Check', 'Severity', 'Failed', 'Score') ''
        & $newSheet 'WAF findings' ([ordered]@{ 'Severity' = 'badge'; 'Pillar' = 'text'; 'Design principle' = 'text'; 'Check ID' = 'mono'; 'Check' = 'wide'; 'Status' = 'badge'; 'Resource' = 'resource'; 'Resource type' = 'mono'; 'Resource group' = 'text'; 'Subscription' = 'text'; 'Detail' = 'wide'; 'Recommendation' = 'wide'; 'Link' = 'link' }) $findingRows `
            @('Severity', 'Pillar', 'Check', 'Resource', 'Subscription') 'Each Well-Architected check a resource fails, most severe first, with what to do.'
    )
    $byPillar = [ordered]@{}
    foreach ($p in $pillarRows) { $byPillar[$p.Pillar] = $p.Score }
    @{
        Sheets = $sheets
        Stats  = [ordered]@{
            WafScore    = $Waf.Overall
            WafPillars  = $byPillar
            WafFindings = $findingRows.Count
            WafHigh     = @($findingRows | Where-Object Severity -EQ 'High').Count
        }
    }
}
