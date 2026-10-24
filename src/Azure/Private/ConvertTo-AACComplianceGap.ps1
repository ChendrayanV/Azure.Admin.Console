function ConvertTo-AACComplianceGap {
    <#
    .SYNOPSIS
        Maps the estate to compliance frameworks - from Defender for Cloud's
        regulatory compliance and Azure Policy's regulatory initiatives - and
        lists the gaps: failing controls, controls left to manual
        attestation, frameworks not assessed at all, and resources nothing
        evaluates - each with a priority, the effort to fix it, a roadmap
        phase and, against a previous run, whether it's new, still open or
        closed.
    .DESCRIPTION
        Frameworks: CIS, PCI-DSS, HIPAA (HITRUST), SOC 2, GDPR, ISO 27001,
        NIST and the Microsoft cloud security benchmark (MCSB), recognised by
        the Defender standard's or Policy initiative's name.

        A control (aggregated over subscriptions: its worst state, its
        failing resources summed):
          Failed   High with 10 or more failing resources, Medium otherwise;
                   effort Low when its policies can be remediated
                   (DeployIfNotExists, Modify), High for manual ones, Medium
                   otherwise
          Manual   (Defender 'Skipped') Low: it needs an attestation
        A framework asked for (-Framework) that nothing assesses is a High
        gap: assign its initiative, or add the standard in Defender for
        Cloud.

        Roadmap phase: Quick win (High or Medium, Low effort), Plan (High,
        more effort), Backlog (the rest).
        With -Baseline (a previous run's gaps): New, Open, or Closed (in the
        baseline, gone now).
        Returns @{ Gaps (AAC.ComplianceGap); Frameworks
        (AAC.ComplianceFramework); Unscanned; Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyCollection()] [object[]] $Standard = @(),
        [AllowEmptyCollection()] [object[]] $Control = @(),
        [AllowEmptyCollection()] [object[]] $Assessment = @(),
        [AllowEmptyCollection()] [object[]] $PolicyControl = @(),
        [AllowEmptyCollection()] [object[]] $Unscanned = @(),
        # Framework keys asked for: CIS, PCI-DSS, HIPAA, SOC2, GDPR, ISO27001, NIST, MCSB; none - every one found.
        [string[]] $Framework = @(),
        # A previous run's gaps (Source, Standard, ControlId, Status).
        [AllowEmptyCollection()] [object[]] $Baseline = @(),
        [System.Collections.IDictionary] $SubscriptionName = @{}
    )

    $get = { param($Row, [string] $Name) if ($Row -is [System.Collections.IDictionary]) { $Row[$Name] } elseif ($null -ne $Row) { $p = $Row.PSObject.Properties[$Name]; if ($p) { $p.Value } } }
    $frameworks = [ordered]@{
        'CIS'      = @{ Label = 'CIS'; Pattern = '(?i)\bCIS\b' }
        'PCI-DSS'  = @{ Label = 'PCI-DSS'; Pattern = '(?i)PCI' }
        'HIPAA'    = @{ Label = 'HIPAA'; Pattern = '(?i)HIPAA|HITRUST' }
        'SOC2'     = @{ Label = 'SOC 2'; Pattern = '(?i)SOC[ -]?2' }
        'GDPR'     = @{ Label = 'GDPR'; Pattern = '(?i)GDPR' }
        'ISO27001' = @{ Label = 'ISO 27001'; Pattern = '(?i)ISO[ -]?(IEC[ -]?)?27001' }
        'NIST'     = @{ Label = 'NIST'; Pattern = '(?i)NIST' }
        'MCSB'     = @{ Label = 'Microsoft cloud security benchmark'; Pattern = '(?i)Microsoft[ -]cloud[ -]security[ -]benchmark|Azure[ -]Security[ -]Benchmark|\bMCSB\b' }
    }
    $frameworkOf = { param([string] $Name) foreach ($k in $frameworks.Keys) { if ($Name -match $frameworks[$k].Pattern) { return $k } }; 'Other' }
    $wanted = @($Framework | Where-Object { $_ })
    $keep = { param([string] $Key) -not $wanted.Count -or $wanted -contains $Key }
    $pretty = { param([string] $Name) $Name -replace '-', ' ' }

    $gaps = [System.Collections.Generic.List[object]]::new()
    $summary = [ordered]@{}
    $addSummary = {
        param([string] $Key, [string] $StandardName, [string] $Source, [int] $Passed, [int] $Failed, [int] $Manual)
        $id = "$Source|$StandardName"
        $summary[$id] = [pscustomobject][ordered]@{
            PSTypeName = 'AAC.ComplianceFramework'; Framework = $(if ($frameworks.Contains($Key)) { $frameworks[$Key].Label } else { 'Other' }); Standard = $StandardName; Source = $Source
            Controls = $Passed + $Failed + $Manual; Passed = $Passed; Failed = $Failed; Manual = $Manual; Compliance = $(if ($Passed + $Failed) { [Math]::Round($Passed / ($Passed + $Failed) * 100, 1) } else { $null })
            Status = $(if ($Failed) { 'Failed' } elseif ($Passed) { 'Passed' } else { 'Manual review' })
        }
    }

    # --- Defender for Cloud: controls, worst state over the subscriptions -----------------------------------------
    $failing = @{}
    foreach ($a in $Assessment) {
        $k = "$([string](& $get $a 'standard'))|$([string](& $get $a 'control'))".ToLowerInvariant()
        if (-not $failing.Contains($k)) { $failing[$k] = [System.Collections.Generic.List[object]]::new() }
        $failing[$k].Add($a)
    }
    $rank = @{ Failed = 0; Skipped = 1; Passed = 2; Unsupported = 3 }
    $controls = [ordered]@{}
    foreach ($c in $Control) {
        $standardName = [string](& $get $c 'standard')
        $key = "$standardName|$([string](& $get $c 'control'))".ToLowerInvariant()
        $state = [string](& $get $c 'state')
        if (-not $controls.Contains($key)) { $controls[$key] = @{ Standard = $standardName; Control = [string](& $get $c 'control'); Description = [string](& $get $c 'description'); State = $state; Subscriptions = [System.Collections.Generic.List[string]]::new() } }
        $entry = $controls[$key]
        if ($rank[$state] -lt $rank[$entry.State]) { $entry.State = $state }
        if ($state -eq 'Failed') { $sub = ([string](& $get $c 'subscriptionId')).ToLowerInvariant(); $entry.Subscriptions.Add($(if ($SubscriptionName.Contains($sub)) { [string]$SubscriptionName[$sub] } else { $sub })) }
    }
    foreach ($standardName in @($controls.Values | ForEach-Object { $_.Standard } | Select-Object -Unique)) {
        $key = & $frameworkOf (& $pretty $standardName)
        if (-not (& $keep $key)) { continue }
        $mine = @($controls.Values | Where-Object Standard -EQ $standardName)
        & $addSummary $key (& $pretty $standardName) 'Defender for Cloud' @($mine | Where-Object State -EQ 'Passed').Count @($mine | Where-Object State -EQ 'Failed').Count @($mine | Where-Object State -EQ 'Skipped').Count
        foreach ($c in @($mine | Where-Object { $_.State -in 'Failed', 'Skipped' })) {
            $checks = @(if ($failing.Contains("$($c.Standard)|$($c.Control)".ToLowerInvariant())) { $failing["$($c.Standard)|$($c.Control)".ToLowerInvariant()] })
            $resources = [int](@($checks | ForEach-Object { [int](& $get $_ 'failedResources') }) | Measure-Object -Sum).Sum
            $manual = $c.State -eq 'Skipped'
            $severity = if ($manual) { 'Low' } elseif ($resources -ge 10) { 'High' } else { 'Medium' }
            $gaps.Add(@{
                    Severity = $severity; Framework = $(if ($frameworks.Contains($key)) { $frameworks[$key].Label } else { 'Other' }); Standard = (& $pretty $c.Standard); Source = 'Defender for Cloud'; ControlId = $c.Control
                    Control = $(if ($c.Description) { "$($c.Control) $($c.Description)" } else { $c.Control }); State = $(if ($manual) { 'Manual' } else { 'Failed' })
                    FailingChecks = (@($checks | Select-Object -First 4 | ForEach-Object { [string](& $get $_ 'assessment') }) -join '; ') + $(if ($checks.Count -gt 4) { " (+$($checks.Count - 4) more)" })
                    FailingResources = $resources; Effort = $(if ($manual) { 'Low' } else { 'Medium' }); Subscriptions = (@($c.Subscriptions | Select-Object -Unique) -join ', ')
                    Remediation = $(if ($manual) { 'Attest the control manually in Defender for Cloud > Regulatory compliance, with the evidence.' } else { 'Fix the failing recommendations under this control (Defender for Cloud > Regulatory compliance), most resources first.' })
                    Link = [string](@($checks | ForEach-Object { [string](& $get $_ 'link') } | Where-Object { $_ -like 'https://*' }) | Select-Object -First 1)
                })
        }
    }

    # --- Azure Policy: regulatory initiatives, by policy definition group (control) ----------------------------------
    foreach ($group in @($PolicyControl | Group-Object -Property { [string](& $get $_ 'initiative') })) {
        $initiative = $group.Name
        $key = & $frameworkOf $initiative
        if (-not (& $keep $key)) { continue }
        $rows = @($group.Group)
        & $addSummary $key $initiative 'Azure Policy' @($rows | Where-Object { [int](& $get $_ 'nonCompliant') -eq 0 -and [int](& $get $_ 'compliant') -gt 0 }).Count @($rows | Where-Object { [int](& $get $_ 'nonCompliant') -gt 0 }).Count @($rows | Where-Object { [int](& $get $_ 'nonCompliant') -eq 0 -and [int](& $get $_ 'compliant') -eq 0 }).Count
        foreach ($r in @($rows | Where-Object { [int](& $get $_ 'nonCompliant') -gt 0 })) {
            $resources = [int](& $get $r 'nonCompliant')
            $effects = @(& $get $r 'effects' | ForEach-Object { ([string]$_).ToLowerInvariant() })
            $effort = if ($effects -contains 'manual') { 'High' } elseif (@($effects | Where-Object { $_ -in 'deployifnotexists', 'modify' }).Count -and -not @($effects | Where-Object { $_ -in 'audit', 'auditifnotexists', 'deny' }).Count) { 'Low' } else { 'Medium' }
            $gaps.Add(@{
                    Severity = $(if ($resources -ge 10) { 'High' } else { 'Medium' }); Framework = $(if ($frameworks.Contains($key)) { $frameworks[$key].Label } else { 'Other' }); Standard = $initiative; Source = 'Azure Policy'
                    ControlId = [string](& $get $r 'groupName'); Control = [string](& $get $r 'groupName'); State = 'Failed'; FailingChecks = "$([int](& $get $r 'policies')) polic(ies): $($effects -join ', ')"
                    FailingResources = $resources; Effort = $effort; Subscriptions = ''
                    Remediation = $(if ($effort -eq 'Low') { 'Create remediation tasks for its policies (Azure Policy > Remediation): they fix the existing resources.' } else { 'Fix the non-compliant resources under this control (Azure Policy > Compliance, filtered to the initiative and control), or exempt them with a reason.' })
                    Link = 'https://learn.microsoft.com/azure/governance/policy/samples/#regulatory-compliance'
                })
        }
    }

    # --- Frameworks asked for that nothing assesses --------------------------------------------------------------------
    foreach ($k in $wanted) {
        $label = $frameworks[$k].Label
        if (@($summary.Values | Where-Object Framework -EQ $label).Count) { continue }
        $gaps.Add(@{
                Severity = 'High'; Framework = $label; Standard = '(none)'; Source = 'Not assessed'; ControlId = ''; Control = "No $label assessment"; State = 'Not assessed'
                FailingChecks = ''; FailingResources = 0; Effort = 'Low'; Subscriptions = ''
                Remediation = $(if ($k -eq 'GDPR') { 'Azure has no built-in GDPR initiative or standard: map GDPR to the controls of ISO 27001 or the Microsoft cloud security benchmark, which are, and assess those.' } else { "Add the $label standard in Defender for Cloud (Environment settings > Security policies), or assign its built-in regulatory compliance initiative in Azure Policy." })
                Link = 'https://learn.microsoft.com/azure/defender-for-cloud/concept-regulatory-compliance-standards'
            })
    }

    # --- Priority, phase, progress -------------------------------------------------------------------------------------------
    $sevRank = (Get-AACSeverityRank).Rank
    $effortRank = @{ Low = 0; Medium = 1; High = 2 }
    $keyOf = { param($G) "$($G.Source)|$($G.Standard)|$($G.ControlId)".ToLowerInvariant() }
    $before = @{}
    foreach ($b in $Baseline) { if ([string](& $get $b 'Status') -ne 'Closed') { $before["$(& $get $b 'Source')|$(& $get $b 'Standard')|$(& $get $b 'ControlId')".ToLowerInvariant()] = $b } }
    $now = @{}
    $out = foreach ($g in $gaps) {
        $k = & $keyOf $g; $now[$k] = $true
        $phase = if ($g.Severity -in 'Critical', 'High', 'Medium' -and $g.Effort -eq 'Low') { 'Quick win' } elseif ($g.Severity -in 'Critical', 'High') { 'Plan' } else { 'Backlog' }
        New-AACFinding -TypeName 'AAC.ComplianceGap' -Severity $g.Severity -Category $g.Framework -Finding "$($g.Standard): $($g.Control)" -Resource $g.ControlId -ResourceType 'control' -Detail $g.FailingChecks `
            -Impact $(if ($g.FailingResources) { "$($g.FailingResources) resource(s) fail it" } else { '' }) -Remediation $g.Remediation -Effort $g.Effort -Link $g.Link -Property ([ordered]@{
                Framework = $g.Framework; Standard = $g.Standard; Source = $g.Source; ControlId = $g.ControlId; Control = $g.Control; State = $g.State; FailingResources = $g.FailingResources
                Phase = $phase; Progress = $(if (-not $Baseline.Count) { '' } elseif ($before.Contains($k)) { 'Open' } else { 'New' }); FailingSubscriptions = $g.Subscriptions
            })
    }
    $closed = foreach ($k in $before.Keys) {
        if ($now.Contains($k)) { continue }
        $b = $before[$k]
        New-AACFinding -TypeName 'AAC.ComplianceGap' -Severity 'Info' -Category ([string](& $get $b 'Framework')) -Finding "$(& $get $b 'Standard'): $(& $get $b 'Control')" -Resource ([string](& $get $b 'ControlId')) -ResourceType 'control' `
            -Detail 'Closed since the baseline.' -Remediation '' -Effort '' -Property ([ordered]@{
                Framework = [string](& $get $b 'Framework'); Standard = [string](& $get $b 'Standard'); Source = [string](& $get $b 'Source'); ControlId = [string](& $get $b 'ControlId'); Control = [string](& $get $b 'Control'); State = 'Closed'
                FailingResources = 0; Phase = 'Done'; Progress = 'Closed'; FailingSubscriptions = ''
            })
    }
    $sorted = @(@($out) + @($closed) | Where-Object { $_ } | Sort-Object -Property @{ Expression = { if ($_.Progress -eq 'Closed') { 9 } else { $sevRank[$_.Severity] } } }, @{ Expression = { if ($effortRank.Contains($_.Effort)) { $effortRank[$_.Effort] } else { 3 } } }, @{ Expression = 'FailingResources'; Descending = $true }, Framework, ControlId)
    $unscannedRows = @(foreach ($u in $Unscanned) { [pscustomobject]@{ PSTypeName = 'AAC.ComplianceUnscanned'; ResourceType = [string](& $get $u 'type'); Resources = [int](& $get $u 'resources') } })
    $open = @($sorted | Where-Object Progress -NE 'Closed')
    @{
        Gaps       = $sorted
        Frameworks = @($summary.Values | Sort-Object Framework, Source, Standard)
        Unscanned  = $unscannedRows
        Stats      = @{
            Gaps           = $open.Count
            High           = @($open | Where-Object Severity -In 'Critical', 'High').Count
            QuickWins      = @($open | Where-Object Phase -EQ 'Quick win').Count
            Manual         = @($open | Where-Object State -EQ 'Manual').Count
            NotAssessed    = @($open | Where-Object State -EQ 'Not assessed').Count
            Frameworks     = @($summary.Values | ForEach-Object Framework | Select-Object -Unique).Count
            Closed         = @($sorted | Where-Object Progress -EQ 'Closed').Count
            New            = @($sorted | Where-Object Progress -EQ 'New').Count
            UnscannedTotal = [int](@($unscannedRows | ForEach-Object { $_.Resources }) | Measure-Object -Sum).Sum
        }
    }
}
