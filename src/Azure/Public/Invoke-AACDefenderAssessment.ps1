function Invoke-AACDefenderAssessment {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Microsoft Defender for Cloud assessed across subscriptions -
        recommendations, attack paths, security alerts, inventory,
        vulnerabilities, secure score, Defender plans, regulatory compliance
        and environment settings - with what to improve, as a Spectre.Console
        view, an object, CSV files and a tabbed, interactive HTML report.
    .DESCRIPTION
        Read-only (Reader or Security Reader is enough), no Az modules: Azure
        Resource Graph (securityresources) for what it holds, and the
        Defender for Cloud REST API for the settings it doesn't (security
        contacts, integrations, connectors, just-in-time policies, alert
        suppression rules) - one call per subscription and setting, in
        parallel.

        -Section picks what is read (everything by default):
          Recommendations  every recommendation assessed - unhealthy, healthy
                           and not applicable resources, severity, risk level
                           and attack paths (Defender CSPM), secure score
                           control, description and remediation steps - and
                           every unhealthy resource
          AttackPaths      attack paths (Defender CSPM): each step from the
                           entry point to the target, risk factors, MITRE
                           tactics and techniques, story and remediation
          Alerts           security alerts generated in the last -AlertDays,
                           every status, with MITRE tactics and techniques,
                           compromised entity and remediation steps; alert
                           suppression rules
          Inventory        every resource Defender assesses: the plan that
                           covers it (on or off), recommendations by
                           severity, vulnerabilities, active alerts and
                           attack paths
          Vulnerabilities  vulnerability assessment findings (machines, SQL,
                           container images): CVEs, patchable, remediation
          Posture          secure score per subscription and its controls
                           with the potential increase, Defender plans with
                           their sub-plan and extensions, multicloud and
                           DevOps connectors, just-in-time policies
          Compliance       regulatory compliance standards, their controls
                           and the failed assessments
          Settings         security contacts and e-mail notifications,
                           Defender for Endpoint and Defender for Cloud Apps
                           integration

        Findings, each with its severity and what to do: a plan off for
        resources the subscription has; Defender CSPM or Resource Manager
        off; Servers on Plan 1; no security contact, alert e-mails off or
        only for High alerts, owners not notified; Defender for Endpoint
        integration off; a secure score under -ScoreWarningPercent (70);
        Critical and High attack paths; High alerts still active, Medium
        alerts open over a week; suppression rules with no expiry;
        just-in-time ports open to any source.

        What you get depends on where the command runs:
          at the prompt    tiles, the subscriptions, the top
                           recommendations, attack paths, active alerts, the
                           plans that are off and the findings, a page at a
                           time
          piped onward     the AAC.DefenderAssessment object, with every
                           table as a property
          -PassThru        the view and the object
          -NoDisplay       the object only
        -CsvPath (a folder) writes a CSV per table. -HtmlPath writes a tabbed
        report in the portal's order - Overview, Findings, Recommendations,
        Attack path analysis, Security alerts, Inventory, Vulnerabilities,
        Security posture, Regulatory compliance, Environment settings -
        where every table is searchable, filterable, groupable and
        downloadable, and a row opens all its details (descriptions,
        remediation steps, the attack path step by step).
    .PARAMETER SubscriptionId
        Only these subscriptions. Defaults to every subscription the account
        can see.
    .PARAMETER Section
        What to read: Recommendations, AttackPaths, Alerts, Inventory,
        Vulnerabilities, Posture, Compliance, Settings. All by default.
    .PARAMETER AlertDays
        Security alerts generated in the last this many days (30 by
        default).
    .PARAMETER ScoreWarningPercent
        A subscription's secure score under this percentage (70 by default)
        is a finding - High under half of it.
    .PARAMETER CsvPath
        A folder to write a CSV per table to.
    .PARAMETER HtmlPath
        Write the tabbed, interactive HTML report to this file.
    .PARAMETER Title
        The HTML report's title.
    .PARAMETER PassThru
        Show the view and also return the object.
    .PARAMETER NoDisplay
        Return the object without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once instead of a page at a time.
    .EXAMPLE
        Connect-AAC
        Invoke-AACDefenderAssessment -HtmlPath .\out\Defender.html
        Defender for Cloud across every subscription you can see, as a tabbed HTML report.
    .EXAMPLE
        Invoke-AACDefenderAssessment -SubscriptionId '00000000-0000-0000-0000-000000000000' -CsvPath .\out\defender
        One subscription, a CSV per table.
    .EXAMPLE
        Invoke-AACDefenderAssessment -Section AttackPaths, Alerts -AlertDays 7
        Only the attack paths and the last week's alerts.
    .EXAMPLE
        (Invoke-AACDefenderAssessment -NoDisplay).Recommendations | Where-Object { $_.Severity -eq 'High' -and $_.UnhealthyResources } | Select-Object Recommendation, UnhealthyResources, Control
        The High recommendations and how many resources each is on.
    .EXAMPLE
        (Invoke-AACDefenderAssessment -NoDisplay -Section Inventory).Inventory | Where-Object PlanState -EQ 'Off'
        The resources no Defender plan protects.
    .OUTPUTS
        AAC.DefenderAssessment (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.DefenderAssessment')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [ValidateSet('Recommendations', 'AttackPaths', 'Alerts', 'Inventory', 'Vulnerabilities', 'Posture', 'Compliance', 'Settings')]
        [string[]] $Section = @('Recommendations', 'AttackPaths', 'Alerts', 'Inventory', 'Vulnerabilities', 'Posture', 'Compliance', 'Settings'),

        [ValidateRange(1, 365)]
        [int] $AlertDays = 30,

        [ValidateRange(1, 99)]
        [int] $ScoreWarningPercent = 70,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $Title = 'Microsoft Defender for Cloud assessment',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    # A failure anywhere below ends as a Spectre.Console error panel and this
    # command's own terminating error; a stopped pipeline just returns.
    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $showView = $interactive -and -not ($CsvPath -or $HtmlPath)
    $returnObjects = $PassThru -or $NoDisplay -or $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    # Read here, not inside the progress block (it runs in Invoke-AACProgress's scope).
    $request = @{
        SubscriptionId = @($SubscriptionId | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() })
        Section = @($Section); AlertDays = $AlertDays; ScoreWarningPercent = $ScoreWarningPercent
        CsvPath = & $resolve $CsvPath; HtmlPath = & $resolve $HtmlPath; Title = $Title
    }

    if ($interactive) {
        Write-AACRule -Title 'Azure Admin Console :: Microsoft Defender for Cloud' -Color 'deepskyblue3_1'
    }
    $state = Invoke-AACProgress -ScriptBlock {
        $null = Get-AACAccessToken
        $plan = Get-AACDefenderAssessmentQuery -Section $request.Section -AlertDays $request.AlertDays
        $notices = [System.Collections.Generic.List[string]]::new()

        # --- Resource Graph ------------------------------------------------------------------------------------
        $labels = @{
            subscriptions = 'subscriptions'; Plans = 'Defender plans'; Scores = 'secure scores'; Controls = 'secure score controls'; ControlAssessments = 'control membership'
            RecommendationSummary = 'recommendations'; Unhealthy = 'unhealthy resources'; InventorySummary = 'inventory'; AttackPaths = 'attack paths'; Alerts = 'security alerts'
            Vulnerabilities = 'vulnerabilities'; Standards = 'compliance standards'; ComplianceControls = 'compliance controls'; ComplianceAssessments = 'compliance assessments'
        }
        Update-AACProgress -Id 'graph' -Total $plan.Graph.Count -Description 'Reading Microsoft Defender for Cloud from Azure Resource Graph'
        $graph = @{ Query = $plan.Graph; AllowFailure = @($plan.Graph.Keys | Where-Object { $_ -ne 'subscriptions' }) }
        if ($request.SubscriptionId.Count) { $graph.SubscriptionId = $request.SubscriptionId }
        $batch = Invoke-AACGraphBatch @graph -OnProgress {
            param($Name, $Done, $Total)
            Update-AACProgress -Id 'graph' -Increment 1 -Description "Read the $($labels[$Name]) ($Done of $Total)"
        }
        foreach ($name in @($batch.Errors.Keys | Sort-Object)) { $notices.Add("The $($labels[$name]) couldn't be read: $($batch.Errors[$name] -replace '\s+', ' ')") }
        $subscriptionNames = @{}
        foreach ($row in @($batch.Rows['subscriptions'])) { if ($row) { $subscriptionNames[([string]$row['subscriptionId']).ToLowerInvariant()] = [string]$row['name'] } }
        if ($request.SubscriptionId.Count) {
            $missing = @($request.SubscriptionId | Where-Object { -not $subscriptionNames.Contains($_) })
            foreach ($id in $missing) { Write-Warning "Subscription $id wasn't found, or your account can't read it; it's left out." }
            if ($missing.Count -eq $request.SubscriptionId.Count) {
                $problem = [System.InvalidOperationException]::new('None of those subscriptions was found.')
                $problem.Data['AACHint'] = 'Check the subscription IDs, and that your account has Reader (or Security Reader) on them.'
                throw $problem
            }
            foreach ($key in @($subscriptionNames.Keys)) { if ($request.SubscriptionId -notcontains $key) { $subscriptionNames.Remove($key) } }
        }
        $rows = @{}
        foreach ($name in $plan.Graph.Keys) { if ($name -ne 'subscriptions' -and -not $batch.Errors.Contains($name)) { $rows[$name] = @($batch.Rows[$name]) } }
        Update-AACProgress -Id 'graph' -Complete -Description ('Read Defender for Cloud in {0:N0} subscription(s)' -f $subscriptionNames.Count)

        # --- REST: the settings Resource Graph doesn't have --------------------------------------------------------
        $rest = @{}
        if ($plan.Rest.Count -and $subscriptionNames.Count) {
            $uris = [System.Collections.Generic.List[string]]::new()
            foreach ($name in $plan.Rest.Keys) { foreach ($sub in $subscriptionNames.Keys) { $uris.Add(($plan.Rest[$name] -f $sub)) } }
            Update-AACProgress -Id 'rest' -Total $uris.Count -Description 'Reading the environment settings from the Defender for Cloud REST API'
            $answers = Invoke-AACArmParallel -Uri $uris.ToArray() -OnProgress { param($Done, $Total) Update-AACProgress -Id 'rest' -Increment 1 -Description "Read $Done of $Total settings" }
            foreach ($name in $plan.Rest.Keys) {
                $rest[$name] = @{}
                foreach ($sub in $subscriptionNames.Keys) { $rest[$name][$sub] = $answers[($plan.Rest[$name] -f $sub)] }
            }
            Update-AACProgress -Id 'rest' -Complete -Description ('Read {0:N0} setting(s) in {1:N0} subscription(s)' -f $uris.Count, $subscriptionNames.Count)
        }

        # --- The assessment ---------------------------------------------------------------------------------------
        Update-AACProgress -Id 'assess' -Indeterminate -Description 'Assessing recommendations, attack paths, alerts, inventory, posture and compliance'
        $assessment = ConvertTo-AACDefenderAssessment -Rows $rows -Rest $rest -SubscriptionName $subscriptionNames -ScoreWarningPercent $request.ScoreWarningPercent
        foreach ($line in $assessment.Notices) { $notices.Add($line) }
        $stats = $assessment.Stats
        if (-not @($assessment.Plans).Count -and $rows.Contains('Plans')) { $notices.Add('No Defender plans were found: Defender for Cloud may not be set up on these subscriptions.') }
        if ($request.Section -contains 'AttackPaths' -and -not $stats.AttackPaths -and -not @($assessment.Plans | Where-Object { $_.Name -eq 'CloudPosture' -and $_.State -eq 'On' }).Count) { $notices.Add('No attack paths: Defender CSPM is off, and attack path analysis needs it.') }
        if ($request.Section -contains 'Alerts' -and -not $stats.PlansOn) { $notices.Add('No Defender plan is on, so there can be no security alerts - an empty alert list is not a clean bill of health.') }
        $assessment.Notices = $notices.ToArray()
        Update-AACProgress -Id 'assess' -Complete -Description ('Secure score {0}; {1:N0} recommendation(s), {2:N0} attack path(s), {3:N0} active alert(s), {4:N0} vulnerabilit(ies); {5} critical/high, {6} medium finding(s)' -f $(if ($null -ne $stats.SecureScore) { "$($stats.SecureScore)%" } else { 'n/a' }), $stats.Recommendations, $stats.AttackPaths, $stats.ActiveAlerts, $stats.Vulnerabilities, ($stats.Critical + $stats.High), $stats.Medium)

        $detail = [ordered]@{
            Subscriptions = if ($request.SubscriptionId.Count) { ($request.SubscriptionId | ForEach-Object { if ($subscriptionNames.Contains($_)) { $subscriptionNames[$_] } else { $_ } }) -join ', ' } else { "every subscription the account can see ($($subscriptionNames.Count))" }
            Sections      = $request.Section -join ', '
            Alerts        = "generated in the last $($request.AlertDays) day(s)"
        }
        if ($request.CsvPath) {
            Update-AACProgress -Id 'csv' -Indeterminate -Description 'Writing the CSV files'
            $files = @(Write-AACDefenderAssessmentCsv -Assessment $assessment -Path $request.CsvPath)
            Update-AACProgress -Id 'csv' -Complete -Description "CSV: $($files.Count) file(s) in $($request.CsvPath)"
        }
        $null = Invoke-AACExport -HtmlPath $request.HtmlPath -WriteHtml {
            Write-AACDefenderAssessmentHtml -Assessment $assessment -Path $request.HtmlPath -Title $request.Title -Detail $detail
        }
        @{ Assessment = $assessment; Scope = $detail }
    }

    $assessment = $state.Assessment
    if ($showView) {
        Invoke-AACPagedOutput -NoPaging:$NoPaging -ScriptBlock {
            Show-AACDefenderAssessmentView -Assessment $assessment -Scope $state.Scope
        }
    }
    elseif ($interactive) {
        foreach ($notice in @($assessment.Notices)) { Write-AACMarkup "[grey58]$([Spectre.Console.Markup]::Escape($notice))[/]" }
    }
    if ($returnObjects) {
        $result = [ordered]@{ PSTypeName = 'AAC.DefenderAssessment'; SecureScore = $assessment.Stats.SecureScore; Subscriptions = @($assessment.Subscriptions) }
        foreach ($key in 'Findings', 'Recommendations', 'UnhealthyResources', 'AttackPaths', 'Alerts', 'Inventory', 'Vulnerabilities', 'Controls', 'Plans', 'Connectors', 'Standards', 'ComplianceControls', 'ComplianceAssessments', 'Settings', 'JitPolicies', 'SuppressionRules', 'Notices') { $result[$key] = @($assessment[$key]) }
        $result['Stats'] = [pscustomobject]$assessment.Stats
        [pscustomobject]$result
    }
}
