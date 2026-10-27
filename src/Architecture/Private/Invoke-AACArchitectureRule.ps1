function Invoke-AACArchitectureRule {
    <#
    .SYNOPSIS
        Runs the catalog's rules over a design: every breach as a finding,
        and a score per Well-Architected pillar.
    .DESCRIPTION
        A rule scoped to Design runs once; one scoped to component kinds (or
        '*') runs on each matching component. The context the rules read:
        AllowedLocations (the landing zone's Allowed locations policy and the
        guardrails' AllowedRegions, together) and Guardrail (the guardrails:
        AllowedRegions, DenyPublicEndpoint, DeniedSkus, RequiredTags).
        -Accept takes rule IDs (SEC-TLS-01) or rule and component
        (SEC-TLS-01:data): those findings are Accepted, not Open - kept in
        the list, left out of -FailOnGap and the scores. A rule that fails
        to run is a notice, not a finding.
        Each pillar's score: the share of its checks that pass, weighted by
        severity (Blocking 4, High 3, Medium 2, Low 1).
        Returns @{ Findings; Pillars; Checks; Notices }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Design,

        [Parameter(Mandatory)]
        [hashtable] $Catalog,

        [System.Collections.IDictionary] $Guardrail = @{},

        [string[]] $Accept = @()
    )

    $allowed = @(@($Design.AllowedLocations) + @(if ($Guardrail.Contains('AllowedRegions')) { $Guardrail['AllowedRegions'] }) | Where-Object { $_ } | ForEach-Object { ([string]$_).ToLowerInvariant() } | Select-Object -Unique)
    $context = @{ AllowedLocations = $allowed; Guardrail = $Guardrail }
    $weight = @{ Blocking = 4; High = 3; Medium = 2; Low = 1 }
    $findings = [System.Collections.Generic.List[object]]::new()
    $notices = [System.Collections.Generic.List[string]]::new()
    $tally = @{}
    foreach ($pillar in $Catalog.Pillars) { $tally[$pillar] = @{ Total = 0; Passed = 0; Checks = 0; Failed = 0 } }

    foreach ($rule in $Catalog.Rules) {
        # A design rule runs once, with no component ($null - assigned directly, as an if would unroll it away).
        if (@($rule.Scope) -contains 'Design') { $targets = @($null) }
        else { $targets = @($Design.Nodes | Where-Object { @($rule.Scope) -contains '*' -or @($rule.Scope) -contains $_.Kind }) }
        foreach ($node in $targets) {
            try { $broken = [bool](& $rule.Test $Design $node $Design.Answers $context) }
            catch { $notices.Add("Rule $($rule.Id) couldn't be checked$(if ($node) { " on $($node.Name)" }): $($_.Exception.Message)"); continue }
            $accepted = $broken -and ($Accept -contains $rule.Id -or ($node -and $Accept -contains "$($rule.Id):$($node.Id)"))
            $t = $tally[$rule.Pillar]
            $t.Checks++
            if (-not $accepted) { $t.Total += $weight[$rule.Severity]; if (-not $broken) { $t.Passed += $weight[$rule.Severity] } else { $t.Failed++ } }
            if (-not $broken) { continue }
            $findings.Add([pscustomobject][ordered]@{
                    PSTypeName  = 'AAC.ArchitectureFinding'
                    Severity    = $rule.Severity
                    Status      = $(if ($accepted) { 'Accepted' } else { 'Open' })
                    Rule        = $rule.Id
                    Finding     = $rule.Title
                    Pillar      = $rule.Pillar
                    Component   = $(if ($node) { $node.Name } else { 'Design' })
                    Region      = $(if ($node) { $node.Region } else { '' })
                    Policy      = $rule.Policy
                    PSRule      = $rule.PSRule
                    Advisor     = $rule.Advisor
                    Remediation = $rule.Remediation
                    Link        = $rule.Link
                    NodeId      = $(if ($node) { $node.Id } else { '' })
                })
        }
    }
    $rank = @{ Blocking = 0; High = 1; Medium = 2; Low = 3 }
    $sorted = @($findings | Sort-Object -Property @{ Expression = { $_.Status -ne 'Open' } }, @{ Expression = { $rank[$_.Severity] } }, Pillar, Rule, Component)
    $pillars = @(foreach ($pillar in $Catalog.Pillars) {
            $t = $tally[$pillar]
            $open = @($sorted | Where-Object { $_.Pillar -eq $pillar -and $_.Status -eq 'Open' })
            [pscustomobject][ordered]@{
                PSTypeName = 'AAC.ArchitecturePillar'; Pillar = $pillar; Score = $(if ($t.Total) { [Math]::Round(100.0 * $t.Passed / $t.Total) } else { $null }); Checks = $t.Checks
                Open = $open.Count; Blocking = @($open | Where-Object Severity -EQ 'Blocking').Count; High = @($open | Where-Object Severity -EQ 'High').Count
            }
        })
    @{ Findings = $sorted; Pillars = $pillars; Checks = [int](@($tally.Values | ForEach-Object { $_.Checks }) | Measure-Object -Sum).Sum; Notices = $notices.ToArray() }
}
