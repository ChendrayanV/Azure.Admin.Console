function Test-AACGoLiveReadiness {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        A go-live gate: runs the Well-Architected assessment on a workload and
        says Ready or Not ready - each pillar's score against a minimum, no
        high-severity findings, the checks that must pass - with the blockers,
        a Spectre.Console view, and CSV, PDF and HTML reports. -FailOnGap
        fails a pipeline stage when it isn't ready.
    .DESCRIPTION
        The same read and scores as Invoke-AACWafAssessment (one Resource
        Graph batch, Advisor, Defender for Cloud, the questionnaire's answers
        with -AttestationPath). Then the gates, each Pass, Fail or Warning:
          Pillar score       each pillar at -MinimumScore (70) or more; a
                             pillar can have its own with -PillarMinimum
                             @{ Security = 80 }
          High findings      no failed high-severity catalogue check (Advisor
                             and Defender count through the pillar scores);
                             -AllowHighFinding turns this into a warning
          Required checks    every check matching -RequiredCheck (IDs,
                             wildcards) tested and passed everywhere
          Principles covered every design principle assessed, by a check or
                             the questionnaire; a warning unless
                             -RequireAttestation
        Ready when no gate fails.

        What you get:
          at the prompt    the verdict, the gates and blockers, the heat maps
                           and the findings
          piped onward     the AAC.GoLiveReadiness object (Ready, Verdict,
                           Overall, Pillars, Gates, Blockers, Warnings)
          -PassThru        the view and the object
          -NoDisplay       the object only
        -FailOnGap throws when not ready, after the view and any reports, so
        `pwsh -File` exits non-zero. -CsvPath writes the gates; -HtmlPath and
        -PdfPath the full report with a Go-live tab.
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups.
    .PARAMETER ResourceGroupName
        The workload's resource groups.
    .PARAMETER Pillar
        The pillars to gate on (all five by default).
    .PARAMETER MinimumScore
        The lowest pillar score that passes (0 to 100; 70 by default).
    .PARAMETER PillarMinimum
        A minimum per pillar, e.g. @{ Security = 80; 'Cost Optimization' = 50 }.
    .PARAMETER RequiredCheck
        Check IDs that must pass everywhere they apply; wildcards work
        (Get-AACWafCheck lists them).
    .PARAMETER AllowHighFinding
        High-severity findings warn instead of blocking.
    .PARAMETER RequireAttestation
        Every design principle must be assessed - by a check or the
        questionnaire.
    .PARAMETER AttestationPath
        An answered questionnaire (Export-AACWafQuestionnaire).
    .PARAMETER HeatMapBy
        The heat maps' columns: Subscription, ResourceGroup (the default here)
        or ResourceType.
    .PARAMETER ExcludeCheck
        Check IDs to leave out; wildcards work.
    .PARAMETER NoAdvisor
        Leave out Azure Advisor.
    .PARAMETER NoDefender
        Leave out Defender for Cloud.
    .PARAMETER FailOnGap
        Throw a terminating error when not ready (for pipelines).
    .PARAMETER CsvPath
        Write the gates to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report.
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the readiness.
    .PARAMETER NoDisplay
        Return the readiness without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Test-AACGoLiveReadiness -ResourceGroupName 'rg-app-prod'
        Is the workload ready to go live, and if not, what blocks it.
    .EXAMPLE
        Test-AACGoLiveReadiness -ResourceGroupName 'rg-app-prod' -PillarMinimum @{ Security = 85 } -RequiredCheck 'RE-02', 'SE-1*' -AttestationPath .\waf-answers.csv -RequireAttestation -PdfPath .\GoLive.pdf
        A strict gate with the team's answers, as a PDF for sign-off.
    .EXAMPLE
        Test-AACGoLiveReadiness -ResourceGroupName $env:WORKLOAD_RG -NoDisplay -FailOnGap -HtmlPath "$env:BUILD_ARTIFACTSTAGINGDIRECTORY/golive.html"
        In a pipeline: the stage fails when the workload isn't ready, and the report is kept as an artifact.
    .OUTPUTS
        AAC.GoLiveReadiness (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.GoLiveReadiness')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [ValidateNotNullOrEmpty()]
        [string[]] $ManagementGroupId,

        [ValidateNotNullOrEmpty()]
        [string[]] $ResourceGroupName,

        [ValidateSet('Reliability', 'Security', 'Cost Optimization', 'Operational Excellence', 'Performance Efficiency')]
        [string[]] $Pillar = @('Reliability', 'Security', 'Cost Optimization', 'Operational Excellence', 'Performance Efficiency'),

        [ValidateRange(0, 100)]
        [int] $MinimumScore = 70,

        [hashtable] $PillarMinimum = @{},

        [SupportsWildcards()]
        [string[]] $RequiredCheck,

        [switch] $AllowHighFinding,

        [switch] $RequireAttestation,

        [string] $AttestationPath,

        [ValidateSet('Subscription', 'ResourceGroup', 'ResourceType')]
        [string] $HeatMapBy = 'ResourceGroup',

        [SupportsWildcards()]
        [string[]] $ExcludeCheck,

        [switch] $NoAdvisor,

        [switch] $NoDefender,

        [switch] $FailOnGap,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Go-live readiness',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    foreach ($key in @($PillarMinimum.Keys)) {
        if ($key -notin $Pillar -and $key -notin 'Reliability', 'Security', 'Cost Optimization', 'Operational Excellence', 'Performance Efficiency') { throw "Azure Admin Console doesn't know the pillar '$key' in -PillarMinimum: use Reliability, Security, 'Cost Optimization', 'Operational Excellence' or 'Performance Efficiency'." }
    }
    $request = @{
        SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }); ResourceGroupName = @($ResourceGroupName | Where-Object { $_ })
        Pillar = @($Pillar | Select-Object -Unique); HeatMapBy = $HeatMapBy; ExcludeCheck = @($ExcludeCheck | Where-Object { $_ }); NoAdvisor = [bool]$NoAdvisor; NoDefender = [bool]$NoDefender
        AttestationPath = & $resolve $AttestationPath; HistoryPath = ''; CostTag = @('CostCenter', 'CostCentre', 'Cost Center', 'Project', 'Application', 'BillingCode'); OwnerTag = @('Owner', 'Contact', 'TechnicalOwner', 'BusinessOwner'); KeepDuplicates = $false
    }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Go-live readiness' -Color 'mediumpurple2' }
    $state = Get-AACWafAssessment -Request $request
    $result = $state.Result

    # --- The gates ---------------------------------------------------------------------------------------------
    $gates = [System.Collections.Generic.List[object]]::new()
    $gate = { param([string] $Name, [string] $Requirement, [string] $Actual, [string] $Status, [string] $Pillar = '') $gates.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.GoLiveGate'; Gate = $Name; Pillar = $Pillar; Requirement = $Requirement; Actual = $Actual; Status = $Status }) }
    foreach ($p in $result.Pillars) {
        $minimum = if ($PillarMinimum.Contains($p.Pillar)) { [double]$PillarMinimum[$p.Pillar] } else { [double]$MinimumScore }
        if ($null -eq $p.Score) { & $gate 'Pillar score' "$minimum or more" 'not assessed' 'Warning' $p.Pillar }
        else { & $gate 'Pillar score' "$minimum or more" ('{0:N0} ({1})' -f $p.Score, $p.Maturity) $(if ($p.Score -ge $minimum) { 'Pass' } else { 'Fail' }) $p.Pillar }
    }
    $high = @($result.Results | Where-Object { $_.Status -eq 'Fail' -and $_.Severity -eq 'High' -and $_.Source -eq 'Catalogue' })
    $highChecks = @($high | ForEach-Object { $_.CheckId } | Select-Object -Unique)
    & $gate 'High-severity findings' 'none' $(if ($high.Count) { "$($high.Count) on $($highChecks.Count) check(s): $(($highChecks | Select-Object -First 6) -join ', ')" } else { 'none' }) $(if (-not $high.Count) { 'Pass' } elseif ($AllowHighFinding) { 'Warning' } else { 'Fail' })
    foreach ($pattern in @($RequiredCheck | Where-Object { $_ })) {
        $matched = @($result.Checks | Where-Object { $_.CheckId -like $pattern })
        if (-not @($matched | Where-Object Evaluated).Count) { & $gate 'Required check' "$pattern passes" 'not assessed: nothing in scope to test' 'Warning'; continue }
        $failing = @($matched | Where-Object Failed)
        & $gate 'Required check' "$pattern passes" $(if ($failing.Count) { (@($failing | ForEach-Object { "$($_.CheckId) $($_.Failed) failed" }) -join '; ') } else { 'passed' }) $(if ($failing.Count) { 'Fail' } else { 'Pass' })
    }
    $uncovered = @($result.Principles | Where-Object { $null -eq $_.Score })
    & $gate 'Principles covered' 'every design principle assessed (a check or the questionnaire)' $(if ($uncovered.Count) { "$($uncovered.Count) not assessed: $(($uncovered | ForEach-Object { $_.Principle } | Select-Object -First 5) -join '; ')$(if ($uncovered.Count -gt 5) { '; ...' })" } else { 'all assessed' }) $(if (-not $uncovered.Count) { 'Pass' } elseif ($RequireAttestation) { 'Fail' } else { 'Warning' })

    $blockers = @($gates | Where-Object Status -EQ 'Fail' | ForEach-Object { "$($_.Gate)$(if ($_.Pillar) { " ($($_.Pillar))" }): $($_.Actual)" })
    $warnings = @($gates | Where-Object Status -EQ 'Warning' | ForEach-Object { "$($_.Gate)$(if ($_.Pillar) { " ($($_.Pillar))" }): $($_.Actual)" })
    $ready = -not $blockers.Count
    $readiness = [pscustomobject][ordered]@{
        PSTypeName = 'AAC.GoLiveReadiness'
        Ready      = $ready
        Verdict    = $(if ($ready) { 'Ready' } else { 'Not ready' })
        Scope      = $state.Scope.Label
        Overall    = $result.Overall
        Pillars    = @($result.Pillars)
        Gates      = $gates.ToArray()
        Blockers   = $blockers
        Warnings   = $warnings
        Findings   = @($result.Results | Where-Object Status -In 'Fail', 'Partly')
    }

    # --- The report: the assessment's, with the verdict and a Go-live tab first ----------------------------------
    $report = ConvertTo-AACWafReport -State $state -Request $request
    $report.Subtitle = "Go-live readiness: $($request.Pillar -join ', ')"
    $report.Status = $(if ($ready -and -not $warnings.Count) { 'Success' } elseif ($ready) { 'Warning' } else { 'Failed' })
    $report.Headline = $(if ($ready) { "Ready to go live$(if ($warnings.Count) { " - $($warnings.Count) warning(s)" }). $($report.Headline)" } else { "Not ready: $($blockers.Count) blocker(s) - $($blockers[0])$(if ($blockers.Count -gt 1) { '; ...' })" })
    $report.Facts['Minimum score'] = "$MinimumScore$(if ($PillarMinimum.Count) { " ($(@($PillarMinimum.Keys | ForEach-Object { "$_ $($PillarMinimum[$_])" }) -join ', '))" })"
    $report.Tiles = @(@{ Value = $readiness.Verdict; Label = 'go-live verdict'; Tone = $(if ($ready) { 'good' } else { 'bad' }); Table = 'gates' }) + @($report.Tiles)
    $report.Tabs = @(@{ Name = 'Go-live'; Badge = $blockers.Count; Tone = $(if ($ready) { 'good' } else { 'bad' }); Note = 'Each gate: what it requires, what was found, and whether it passes. Ready when no gate fails.' }) + @($report.Tabs)
    $statusTones = @{ Pass = 'good'; Fail = 'bad'; Warning = 'warn' }
    $report.Tables = @(@{ Id = 'gates'; Title = 'Go-live gates'; Section = 'Go-live'; Rows = $gates.ToArray(); Noun = 'gates'; GroupBy = @('Status', 'Gate'); ConsoleLimit = 20
            Columns = @(
                @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = $statusTones; Facet = $true; Console = $true; Pdf = $true }
                @{ Key = 'Gate'; Label = 'Gate'; Facet = $true; Console = $true; Pdf = $true }
                @{ Key = 'Pillar'; Label = 'Pillar'; Facet = $true; Console = $true; Pdf = $true }
                @{ Key = 'Requirement'; Label = 'Requires'; Console = $true; Pdf = $true }
                @{ Key = 'Actual'; Label = 'Found'; Type = 'wide'; Console = $true; Pdf = $true }
            ) }) + @($report.Tables)
    $report.Hint = '-MinimumScore, -PillarMinimum and -RequiredCheck set the bar; -AttestationPath adds the team''s answers; -FailOnGap fails a pipeline; -HtmlPath, -PdfPath or -CsvPath for a report.'
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $gates.ToArray() -Noun 'gate' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object @($readiness) -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
    if ($FailOnGap -and -not $ready) {
        $problem = [System.InvalidOperationException]::new("Azure Admin Console: the workload isn't ready to go live - $($blockers.Count) blocker(s): $($blockers -join ' | ')")
        $problem.Data['AACHint'] = 'Fix the blockers (the Go-live gates in the report list them), or adjust -MinimumScore, -PillarMinimum or -RequiredCheck if the bar is wrong for this workload.'
        throw $problem
    }
}
