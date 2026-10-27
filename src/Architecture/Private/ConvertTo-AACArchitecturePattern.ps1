function ConvertTo-AACArchitecturePattern {
    <#
    .SYNOPSIS
        Ranks the catalog's cloud design patterns against a brief's answers:
        how well each fits, why, and what it costs in the other pillars.
    .DESCRIPTION
        Fit: the points each pattern's own Fit rules give for these answers
        (a reason each). Alignment: the pattern's effect on each pillar
        (-2 to +2) weighted by what the brief values - Reliability counts
        double for mission- and business-critical workloads, Security for
        confidential and regulated data, Cost Optimization when there is a
        budget and the workload isn't mission-critical, Performance
        Efficiency for a response target under 100 ms or 10,000 users.
        Score = Fit x 10 + Alignment. Recommended: Fit of 3 or more.
        Returns AAC.ArchitecturePattern rows, best first.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Catalog,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Answers
    )

    $num = { param($Value) $n = 0.0; if ([double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref]$n)) { $n } else { 0 } }
    $weight = @{
        Reliability              = $(if ($Answers['BUS-02'] -in 'Mission-critical', 'Business-critical') { 2 } else { 1 })
        Security                 = $(if ($Answers['SEC-01'] -in 'Confidential', 'Regulated') { 2 } else { 1 })
        'Cost Optimization'      = $(if ((& $num $Answers['COST-01']) -gt 0 -and $Answers['BUS-02'] -ne 'Mission-critical') { 2 } else { 1 })
        'Performance Efficiency' = $(if ((& $num $Answers['PERF-02']) -lt 100 -or (& $num $Answers['BUS-03']) -ge 10000) { 2 } else { 1 })
        'Operational Excellence' = 1
    }
    $short = @{ Reliability = 'Reliability'; Security = 'Security'; 'Cost Optimization' = 'Cost'; 'Performance Efficiency' = 'Performance'; 'Operational Excellence' = 'Operations' }
    $rows = foreach ($p in $Catalog.Patterns) {
        $reasons = @(& $p.Fit $Answers | Where-Object { $_ })
        $fit = [int](@($reasons | ForEach-Object { $_.Points }) + 0 | Measure-Object -Sum).Sum
        $alignment = [int](@($Catalog.Pillars | ForEach-Object { [int]$p.Effect[$_] * $weight[$_] }) | Measure-Object -Sum).Sum
        $tradeoffs = @($Catalog.Pillars | Where-Object { [int]$p.Effect[$_] -ne 0 } | ForEach-Object { '{0} {1}{2}' -f $short[$_], $(if ($p.Effect[$_] -gt 0) { '+' } else { '' }), $p.Effect[$_] })
        [pscustomobject][ordered]@{
            PSTypeName  = 'AAC.ArchitecturePattern'
            Name        = $p.Name
            Recommended = $(if ($fit -ge 3) { 'Yes' } else { 'No' })
            Score       = $fit * 10 + $alignment
            Fit         = $fit
            Why         = $(if ($reasons.Count) { (@($reasons | ForEach-Object Reason)) -join '; ' } else { 'Nothing in the answers calls for it' })
            TradeOffs   = $tradeoffs -join ', '
            Problem     = $p.Problem
            Adds        = (@($p.Adds) -join ', ')
            Link        = $p.Link
            Id          = $p.Id
        }
    }
    @($rows | Sort-Object -Property @{ Expression = 'Score'; Descending = $true }, Name)
}
