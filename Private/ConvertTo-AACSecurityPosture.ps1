function ConvertTo-AACSecurityPosture {
    <#
    .SYNOPSIS
        Builds Get-AACSecurityPosture's result from the Defender for Cloud
        rows (Get-AACDefenderQuery): secure scores, recommendations, alerts,
        Defender plans and regulatory compliance - and one flat list of
        findings across them.
    .DESCRIPTION
        -Rows maps a query name to its rows (Scores, Controls,
        ControlAssessments, Recommendations, Alerts, Plans, Standards,
        ComplianceControls, ComplianceAssessments); a missing name is a
        section not read (ComplianceRecommendations: the recommendations,
        read only for the compliance failures). -SubscriptionName names the subscriptions in scope
        (others are left out). -ResourceId, when given, keeps only the
        recommendations, alerts and compliance failures on those resources
        (a resource group or tag selection); scores, plans and standards are
        per subscription and stay whole.

        Findings (AAC.SecurityFinding), one per:
          Recommendation  an unhealthy recommendation on a resource
          Alert           an active security alert
          Compliance      a failed regulatory compliance assessment, on each
                          resource failing the recommendation behind it (or
                          once, when no resource is named)
          Plan            a Defender plan that is off
          Policy          a resource that doesn't comply with an Azure Policy
                          assignment (no severity: Azure Policy has none);
                          compliance rolled up as the Azure portal does
                          (ConvertTo-AACPolicyState)
        with Severity, Title, Category (the recommendation's category, the
        alert's intent, the standard, 'Defender plan'), Control (secure score
        or compliance control), the resource, State, Detail, Link (the portal
        page), Since and ResourceId - most severe first.

        Returns @{ Findings; Subscriptions; Controls; Recommendations; Alerts;
        Plans; Standards; ComplianceControls; PolicyAssignments; Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [hashtable] $Rows = @{},

        [hashtable] $SubscriptionName = @{},

        [System.Collections.Generic.HashSet[string]] $ResourceId
    )

    $value = { param($Object, [string] $Key) if ($Object -is [System.Collections.IDictionary]) { if ($Object.Contains($Key)) { $Object[$Key] } } else { Get-AACPropertyValue -InputObject $Object -Name $Key } }
    $text = { param($Object, [string] $Key) $v = & $value $Object $Key; if ($null -eq $v) { '' } else { [string]$v } }
    $rowsOf = { param([string] $Name) @(if ($Rows.Contains($Name)) { $Rows[$Name] | Where-Object { $null -ne $_ } }) }
    $inScope = { param([string] $Subscription) $SubscriptionName.Contains($Subscription.ToLowerInvariant()) }
    $onResource = { param([string] $Id) $null -eq $ResourceId -or ($Id -and $ResourceId.Contains($Id.ToLowerInvariant())) }
    $subscriptionLabel = { param([string] $Id) $key = $Id.ToLowerInvariant(); if ($SubscriptionName.Contains($key)) { $SubscriptionName[$key] } else { $Id } }
    $severityRank = @{ High = 0; Medium = 1; Low = 2; Informational = 3 }
    $findings = [System.Collections.Generic.List[object]]::new()
    $finding = {
        param([string] $Section, [string] $Severity, [string] $Title, [string] $Category, [string] $Control, [string] $Resource, [string] $Type, [string] $Group, [string] $Subscription, [string] $State, [string] $Detail, [string] $Link, $Since, [string] $Id)
        $findings.Add([pscustomobject][ordered]@{
                PSTypeName       = 'AAC.SecurityFinding'
                Section          = $Section
                Severity         = $Severity
                Title            = $Title
                Category         = $Category
                Control          = $Control
                Resource         = $Resource
                Type             = $Type
                ResourceGroup    = $Group
                SubscriptionName = (& $subscriptionLabel $Subscription)
                State            = $State
                Detail           = $Detail
                Link             = $Link
                Since            = $Since
                SubscriptionId   = $Subscription.ToLowerInvariant()
                ResourceId       = $Id
            })
    }

    # --- Secure scores and controls ----------------------------------------------------------------
    $scores = @{}
    foreach ($row in (& $rowsOf 'Scores')) {
        $id = (& $text $row 'subscriptionId').ToLowerInvariant()
        if (& $inScope $id) { $scores[$id] = @{ Current = [double](& $value $row 'current'); Max = [double](& $value $row 'max') } }
    }
    $maxima = @{}
    foreach ($key in $scores.Keys) { $maxima[$key] = $scores[$key].Max }
    $controls = @(ConvertTo-AACSecurityControl -Row (& $rowsOf 'Controls') -ScoreMax $maxima -SubscriptionName $SubscriptionName)
    $controlOf = @{}
    foreach ($row in (& $rowsOf 'ControlAssessments')) { $controlOf[(& $text $row 'key').ToLowerInvariant()] = & $text $row 'control' }

    # --- Recommendations ------------------------------------------------------------------------------
    # ComplianceRecommendations: read only to name a failed compliance
    # control's resources, when the Recommendations section wasn't asked for.
    $source = if ($Rows.Contains('Recommendations')) { 'Recommendations' } else { 'ComplianceRecommendations' }
    $allRecommendations = @(ConvertTo-AACSecurityRecommendation -Row @(& $rowsOf $source | Where-Object { & $inScope (& $text $_ 'subscriptionId') }) -SubscriptionName $SubscriptionName -ControlOf $controlOf)
    $recommendations = @(if ($Rows.Contains('Recommendations')) { $allRecommendations | Where-Object { & $onResource $_.ResourceId } })
    if ($Rows.Contains('Recommendations')) {
        foreach ($item in $recommendations) {
            & $finding 'Recommendation' $item.Severity $item.Recommendation $item.Category $item.Control $item.Resource $item.Type $item.ResourceGroup $item.SubscriptionId 'Unhealthy' $(if ($item.Description) { $item.Description } else { $item.Cause }) $item.RemediationUrl $item.Since $item.ResourceId
        }
    }

    # --- Alerts ----------------------------------------------------------------------------------------
    $alerts = @(foreach ($row in (& $rowsOf 'Alerts')) {
            $subscription = & $text $row 'subscriptionId'
            if (-not (& $inScope $subscription)) { continue }
            # The Azure resource it is about, else the compromised entity.
            $target = @(@(& $value $row 'resources') | ForEach-Object { [string](& $value $_ 'AzureResourceId'); [string](& $value $_ 'azureResourceId') } | Where-Object { $_ }) | Select-Object -First 1
            if (-not (& $onResource $target)) { continue }
            $time = [datetime]::MinValue
            $when = if ([datetime]::TryParse((& $text $row 'time'), [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$time)) { $time } else { $null }
            $resource = if ($target) { ($target -split '/')[-1] } else { & $text $row 'entity' }
            [pscustomobject][ordered]@{
                PSTypeName       = 'AAC.SecurityAlert'
                Alert            = & $text $row 'name'
                Severity         = & $text $row 'severity'
                Status           = & $text $row 'status'
                Intent           = & $text $row 'intent'
                Resource         = $resource
                ResourceGroup    = $(if ($target -match '/resourcegroups/([^/]+)') { $Matches[1] } else { '' })
                SubscriptionName = & $subscriptionLabel $subscription
                TimeGenerated    = $when
                AgeDays          = $(if ($when) { [int][Math]::Floor(([datetime]::UtcNow - $when).TotalDays) } else { $null })
                AlertType        = & $text $row 'alertType'
                Description      = & $text $row 'description'
                AlertUrl         = & $text $row 'link'
                SubscriptionId   = $subscription.ToLowerInvariant()
                ResourceId       = $target
            }
        })
    $alerts = @($alerts | Sort-Object -Property @{ Expression = { if ($severityRank.Contains($_.Severity)) { $severityRank[$_.Severity] } else { 4 } } }, @{ Expression = 'TimeGenerated'; Descending = $true })
    foreach ($alert in $alerts) {
        & $finding 'Alert' $alert.Severity $alert.Alert $alert.Intent '' $alert.Resource '' $alert.ResourceGroup $alert.SubscriptionId $alert.Status $alert.Description $alert.AlertUrl $alert.TimeGenerated $alert.ResourceId
    }

    # --- Defender plans ------------------------------------------------------------------------------------
    $planNames = @{
        VirtualMachines = 'Servers'; SqlServers = 'Azure SQL databases'; AppServices = 'App Service'; StorageAccounts = 'Storage'
        SqlServerVirtualMachines = 'SQL servers on machines'; KeyVaults = 'Key Vault'; Dns = 'DNS'; Arm = 'Resource Manager'
        OpenSourceRelationalDatabases = 'Open-source relational databases'; CosmosDbs = 'Azure Cosmos DB'; Containers = 'Containers'
        CloudPosture = 'Cloud security posture management (CSPM)'; Api = 'APIs'; AI = 'AI services'
    }
    $plans = @(foreach ($row in (& $rowsOf 'Plans')) {
            $subscription = & $text $row 'subscriptionId'
            if (-not (& $inScope $subscription)) { continue }
            $name = & $text $row 'plan'
            [pscustomobject][ordered]@{
                PSTypeName       = 'AAC.DefenderPlan'
                SubscriptionName = & $subscriptionLabel $subscription
                Plan             = $(if ($planNames.Contains($name)) { $planNames[$name] } else { $name })
                Enabled          = (& $text $row 'tier') -eq 'Standard'
                Tier             = & $text $row 'tier'
                SubPlan          = & $text $row 'subPlan'
                Name             = $name
                SubscriptionId   = $subscription.ToLowerInvariant()
            }
        })
    $plans = @($plans | Sort-Object -Property SubscriptionName, @{ Expression = 'Enabled'; Descending = $true }, Plan)
    foreach ($plan in @($plans | Where-Object { -not $_.Enabled })) {
        & $finding 'Plan' 'Medium' "Microsoft Defender for $($plan.Plan) is off" 'Defender plan' '' $plan.SubscriptionName 'microsoft.resources/subscriptions' '' $plan.SubscriptionId 'Off' 'Workloads of this kind get no threat protection or alerts. Turn the plan on in Defender for Cloud > Environment settings.' '' $null "/subscriptions/$($plan.SubscriptionId)"
    }

    # --- Regulatory compliance -------------------------------------------------------------------------------
    $standards = @(foreach ($row in (& $rowsOf 'Standards')) {
            $subscription = & $text $row 'subscriptionId'
            if (-not (& $inScope $subscription)) { continue }
            $passed = [int](& $value $row 'passed'); $failed = [int](& $value $row 'failed')
            [pscustomobject][ordered]@{
                PSTypeName          = 'AAC.ComplianceStandard'
                Standard            = & $text $row 'standard'
                SubscriptionName    = & $subscriptionLabel $subscription
                State               = & $text $row 'state'
                PassedControls      = $passed
                FailedControls      = $failed
                SkippedControls     = [int](& $value $row 'skipped')
                UnsupportedControls = [int](& $value $row 'unsupported')
                PassRate            = $(if ($passed + $failed) { [Math]::Round(100 * $passed / ($passed + $failed)) } else { $null })
                SubscriptionId      = $subscription.ToLowerInvariant()
            }
        })
    $standards = @($standards | Sort-Object -Property @{ Expression = { if ($null -eq $_.PassRate) { 101 } else { $_.PassRate } } }, Standard, SubscriptionName)
    # A failed assessment's failing resources: the unhealthy recommendations with its key.
    $byKey = @{}
    foreach ($item in $allRecommendations) {
        $key = "$($item.SubscriptionId)|$($item.AssessmentKey)"
        if (-not $byKey.Contains($key)) { $byKey[$key] = [System.Collections.Generic.List[object]]::new() }
        $byKey[$key].Add($item)
    }
    $failing = @{}
    foreach ($row in (& $rowsOf 'ComplianceAssessments')) {
        $subscription = (& $text $row 'subscriptionId').ToLowerInvariant()
        if (-not (& $inScope $subscription) -or (& $text $row 'state') -ne 'Failed') { continue }
        $standard = & $text $row 'standard'; $control = & $text $row 'control'
        $controlKey = "$subscription|$standard|$control"
        if (-not $failing.Contains($controlKey)) { $failing[$controlKey] = [System.Collections.Generic.HashSet[string]]::new() }
        $hits = @(if ($byKey.Contains("$subscription|$(& $text $row 'key')")) { $byKey["$subscription|$(& $text $row 'key')"] | Where-Object { & $onResource $_.ResourceId } })
        foreach ($hit in $hits) {
            [void]$failing[$controlKey].Add($hit.Recommendation)
            & $finding 'Compliance' $hit.Severity (& $text $row 'description') $standard $control $hit.Resource $hit.Type $hit.ResourceGroup $subscription 'Failed' $hit.Recommendation $hit.RemediationUrl $hit.Since $hit.ResourceId
        }
        if (-not $hits.Count -and $null -eq $ResourceId) {
            [void]$failing[$controlKey].Add((& $text $row 'description'))
            & $finding 'Compliance' '' (& $text $row 'description') $standard $control (& $subscriptionLabel $subscription) 'microsoft.resources/subscriptions' '' $subscription 'Failed' "$([int](& $value $row 'failedResources')) resource(s) failing" '' $null "/subscriptions/$subscription"
        }
    }
    $complianceControls = @(foreach ($row in (& $rowsOf 'ComplianceControls')) {
            $subscription = (& $text $row 'subscriptionId').ToLowerInvariant()
            if (-not (& $inScope $subscription)) { continue }
            $controlKey = "$subscription|$(& $text $row 'standard')|$(& $text $row 'control')"
            [pscustomobject][ordered]@{
                PSTypeName         = 'AAC.ComplianceControl'
                Standard           = & $text $row 'standard'
                Control            = & $text $row 'control'
                Description        = & $text $row 'description'
                State              = & $text $row 'state'
                PassedAssessments  = [int](& $value $row 'passed')
                FailedAssessments  = [int](& $value $row 'failed')
                SkippedAssessments = [int](& $value $row 'skipped')
                FailingChecks      = $(if ($failing.Contains($controlKey)) { @($failing[$controlKey]) -join '; ' } else { '' })
                SubscriptionName   = & $subscriptionLabel $subscription
                SubscriptionId     = $subscription
            }
        })
    $stateRank = @{ Failed = 0; Passed = 2; Skipped = 3; Unsupported = 4 }
    $complianceControls = @($complianceControls | Sort-Object -Property Standard, @{ Expression = { if ($stateRank.Contains($_.State)) { $stateRank[$_.State] } else { 1 } } }, Control)

    # --- Azure Policy: rolled up as the portal does (ConvertTo-AACPolicyState, shared with Get-AACPolicyState) ----
    $policyStates = @(& $rowsOf 'PolicyStates' | Where-Object { & $inScope (& $text $_ 'subscriptionId') })
    $policy = ConvertTo-AACPolicyState -Row $policyStates -Assignment (& $rowsOf 'PolicyAssignments') -SubscriptionName $SubscriptionName
    $policyAssignments = @($policy.Assignments)
    $policyBySubscription = @{}
    foreach ($item in @($policy.Scopes | Where-Object Level -EQ 'Subscription')) { $policyBySubscription[$item.SubscriptionId] = $item.ComplianceRate }
    foreach ($item in @($policy.States | Where-Object { $_.ComplianceState -eq 'NonCompliant' -and (& $onResource $_.ResourceId) })) {
        & $finding 'Policy' '' $item.Policy $item.Assignment '' $item.Resource $item.ResourceType $item.ResourceGroup $item.SubscriptionId 'NonCompliant' $(if ($item.Effect) { "Effect: $($item.Effect)" } else { '' }) '' $item.EvaluatedAt $item.ResourceId
    }

    # --- Per subscription -----------------------------------------------------------------------------------
    $subscriptions = @(foreach ($key in @($SubscriptionName.Keys | Sort-Object { $SubscriptionName[$_] })) {
            $score = if ($scores.Contains($key)) { $scores[$key] } else { $null }
            $percent = if ($score -and $score.Max -gt 0) { [Math]::Round(100 * $score.Current / $score.Max) } else { $null }
            $mine = @($recommendations | Where-Object SubscriptionId -EQ $key)
            $myPlans = @($plans | Where-Object SubscriptionId -EQ $key)
            [pscustomobject][ordered]@{
                PSTypeName       = 'AAC.SecurityScore'
                SubscriptionName = $SubscriptionName[$key]
                SecureScore      = $percent
                Rating           = $(if ($null -eq $percent) { '' } elseif ($percent -ge 70) { 'Good' } elseif ($percent -ge 40) { 'Fair' } else { 'Poor' })
                Points           = $(if ($score -and $score.Max -gt 0) { '{0:N1} / {1:N1}' -f $score.Current, $score.Max } else { '' })
                High             = @($mine | Where-Object Severity -EQ 'High').Count
                Medium           = @($mine | Where-Object Severity -EQ 'Medium').Count
                Low              = @($mine | Where-Object Severity -EQ 'Low').Count
                Alerts           = @($alerts | Where-Object SubscriptionId -EQ $key).Count
                PlansOn          = @($myPlans | Where-Object Enabled).Count
                PlansOff         = @($myPlans | Where-Object { -not $_.Enabled }).Count
                FailedControls   = $(& { $sum = 0; foreach ($standard in $standards) { if ($standard.SubscriptionId -eq $key) { $sum += $standard.FailedControls } }; $sum })
                PolicyCompliance = $(if ($policyBySubscription.Contains($key)) { $policyBySubscription[$key] } else { $null })
                SubscriptionId   = $key
            }
        })

    $current = 0.0; $max = 0.0
    foreach ($score in $scores.Values) { $current += $score.Current; $max += $score.Max }
    $overall = if ($max -gt 0) { [Math]::Round(100 * $current / $max) } else { $null }
    $sectionRank = @{ Alert = 0; Recommendation = 1; Compliance = 2; Policy = 3; Plan = 4 }

    $all = @($findings | Sort-Object -Property @{ Expression = { if ($severityRank.Contains($_.Severity)) { $severityRank[$_.Severity] } else { 4 } } }, @{ Expression = { $sectionRank[$_.Section] } }, Title, Resource)
    @{
        Findings           = $all
        Subscriptions      = $subscriptions
        Controls           = $controls
        Recommendations    = $recommendations
        Alerts             = $alerts
        Plans              = $plans
        Standards          = $standards
        ComplianceControls = $complianceControls
        PolicyAssignments  = $policyAssignments
        Stats              = @{
            SecureScore     = $overall
            Rating          = $(if ($null -eq $overall) { '' } elseif ($overall -ge 70) { 'Good' } elseif ($overall -ge 40) { 'Fair' } else { 'Poor' })
            Subscriptions   = $subscriptions.Count
            Recommendations = $recommendations.Count
            High            = @($recommendations | Where-Object Severity -EQ 'High').Count
            Medium          = @($recommendations | Where-Object Severity -EQ 'Medium').Count
            Low             = @($recommendations | Where-Object Severity -EQ 'Low').Count
            Resources       = @($recommendations | ForEach-Object { ([string]$_.ResourceId).ToLowerInvariant() } | Select-Object -Unique).Count
            Alerts          = $alerts.Count
            HighAlerts      = @($alerts | Where-Object Severity -EQ 'High').Count
            PlansOn         = @($plans | Where-Object Enabled).Count
            PlansOff        = @($plans | Where-Object { -not $_.Enabled }).Count
            Standards       = @($standards | Select-Object -ExpandProperty Standard -Unique).Count
            FailedControls  = @($complianceControls | Where-Object State -EQ 'Failed').Count
            PolicyCompliance      = $policy.Stats.ComplianceRate
            PolicyAssignments     = $policyAssignments.Count
            NonCompliantResources = @($findings | Where-Object Section -EQ 'Policy' | ForEach-Object { ([string]$_.ResourceId).ToLowerInvariant() } | Select-Object -Unique).Count
            Findings        = $all.Count
        }
    }
}
