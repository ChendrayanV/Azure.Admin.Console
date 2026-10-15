function Get-AACWafCheck {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Lists the checks Invoke-AACWafAssessment runs - by pillar and design
        principle, with the resource type each tests, its severity, what to
        do and where to read more - so you can review the catalogue or pick
        checks for -ExcludeCheck and Test-AACGoLiveReadiness -RequiredCheck.
    .DESCRIPTION
        Nothing in Azure is read. One AAC.WafCatalogCheck per check:
          catalogue checks   RE-, SE-, CO-, OE-, PE-: tested on each resource
                             of their type (or each subscription or resource
                             group) against the shared Resource Graph read
          Advisor            AD-HA, AD-SEC, AD-COST, AD-OPS, AD-PERF: a
                             resource with an open recommendation fails
          Defender           DF-HIGH: a resource with an open high-severity
                             recommendation fails
          attestation        AT-<pillar>-<n>: the questionnaire's answer for
                             the principle (-AttestationPath)
        -Principle shows each principle with how it's covered.
    .PARAMETER Pillar
        Only these pillars.
    .PARAMETER Id
        Only these check IDs; wildcards work.
    .PARAMETER Severity
        Only these severities.
    .PARAMETER Principle
        List the design principles instead, with how many checks cover each.
    .EXAMPLE
        Get-AACWafCheck -Pillar Reliability
        The reliability checks.
    .EXAMPLE
        Get-AACWafCheck -Principle | Where-Object Checks -EQ 0
        The principles only the questionnaire covers.
    .OUTPUTS
        AAC.WafCatalogCheck, or AAC.WafPrinciple with -Principle
    #>
    [CmdletBinding()]
    [OutputType('AAC.WafCatalogCheck', 'AAC.WafPrinciple')]
    param(
        [ValidateSet('Reliability', 'Security', 'Cost Optimization', 'Operational Excellence', 'Performance Efficiency')]
        [string[]] $Pillar = @('Reliability', 'Security', 'Cost Optimization', 'Operational Excellence', 'Performance Efficiency'),

        [SupportsWildcards()]
        [string[]] $Id,

        [ValidateSet('High', 'Medium', 'Low')]
        [string[]] $Severity,

        [switch] $Principle
    )

    $catalog = Get-AACWafCatalog
    $folded = @(
        @{ Id = 'AD-HA'; Pillar = 'Reliability'; Principle = 'Design for resilience'; Title = 'No open Advisor reliability recommendations'; Severity = 'High'; Type = '(Advisor: any type)'; Source = 'Advisor' }
        @{ Id = 'AD-SEC'; Pillar = 'Security'; Principle = 'Sustain and evolve your security posture'; Title = 'No open Advisor security recommendations'; Severity = 'High'; Type = '(Advisor: any type)'; Source = 'Advisor' }
        @{ Id = 'DF-HIGH'; Pillar = 'Security'; Principle = 'Sustain and evolve your security posture'; Title = 'No open high-severity Defender for Cloud recommendations'; Severity = 'High'; Type = '(Defender: any type)'; Source = 'Defender' }
        @{ Id = 'AD-COST'; Pillar = 'Cost Optimization'; Principle = 'Monitor and optimize over time'; Title = 'No open Advisor cost recommendations'; Severity = 'High'; Type = '(Advisor: any type)'; Source = 'Advisor' }
        @{ Id = 'AD-OPS'; Pillar = 'Operational Excellence'; Principle = 'Establish development standards'; Title = 'No open Advisor operational excellence recommendations'; Severity = 'High'; Type = '(Advisor: any type)'; Source = 'Advisor' }
        @{ Id = 'AD-PERF'; Pillar = 'Performance Efficiency'; Principle = 'Improve efficiency through optimization'; Title = 'No open Advisor performance recommendations'; Severity = 'High'; Type = '(Advisor: any type)'; Source = 'Advisor' }
    )
    $abbreviation = @{ Reliability = 'RE'; Security = 'SE'; 'Cost Optimization' = 'CO'; 'Operational Excellence' = 'OE'; 'Performance Efficiency' = 'PE' }
    $all = @(
        foreach ($c in $catalog.Checks) { [pscustomobject][ordered]@{ PSTypeName = 'AAC.WafCatalogCheck'; Id = $c.Id; Pillar = $c.Pillar; Principle = $c.Principle; Check = $c.Title; Severity = $c.Severity; ResourceType = $c.Type; Source = 'Catalogue'; Recommendation = $c.Recommendation; Link = $c.Link } }
        foreach ($c in $folded) { [pscustomobject][ordered]@{ PSTypeName = 'AAC.WafCatalogCheck'; Id = $c.Id; Pillar = $c.Pillar; Principle = $c.Principle; Check = $c.Title; Severity = $c.Severity; ResourceType = $c.Type; Source = $c.Source; Recommendation = 'Work through the open recommendations, highest impact first.'; Link = '' } }
        foreach ($p in @($catalog.Principles.Keys)) {
            $i = 0
            foreach ($pr in $catalog.Principles[$p]) { $i++; [pscustomobject][ordered]@{ PSTypeName = 'AAC.WafCatalogCheck'; Id = "AT-$($abbreviation[$p])-$i"; Pillar = $p; Principle = $pr.Name; Check = $pr.Question; Severity = 'Medium'; ResourceType = '(questionnaire)'; Source = 'Attestation'; Recommendation = 'Answer it in the questionnaire (Export-AACWafQuestionnaire).'; Link = $pr.Link } }
        }
    ) | Where-Object { $_.Pillar -in $Pillar }

    if ($Principle) {
        foreach ($p in @($catalog.Principles.Keys | Where-Object { $_ -in $Pillar })) {
            foreach ($pr in $catalog.Principles[$p]) {
                $covering = @($all | Where-Object { $_.Pillar -eq $p -and $_.Principle -eq $pr.Name -and $_.Source -ne 'Attestation' })
                [pscustomobject][ordered]@{ PSTypeName = 'AAC.WafPrinciple'; Pillar = $p; Principle = $pr.Name; Checks = $covering.Count; CheckIds = (@($covering | ForEach-Object { $_.Id }) -join ', '); Question = $pr.Question; Link = $pr.Link }
            }
        }
        return
    }
    $all | Where-Object { $checkId = $_.Id; (-not $Id -or @($Id | Where-Object { $checkId -like $_ }).Count) -and (-not $Severity -or $Severity -contains $_.Severity) }
}
