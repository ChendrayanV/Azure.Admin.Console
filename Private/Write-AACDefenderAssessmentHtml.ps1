function Write-AACDefenderAssessmentHtml {
    <#
    .SYNOPSIS
        Writes Invoke-AACDefenderAssessment's report as one interactive HTML
        page with a tab per area, in the Defender for Cloud portal's order.
    .DESCRIPTION
        Overview      tiles and charts (each opens its tab, filtered)
        Findings      what to improve in how Defender for Cloud is set up
        Recommendations, Attack path analysis, Security alerts, Inventory,
        Vulnerabilities, Security posture (subscriptions, secure score
        controls, plans, connectors), Regulatory compliance, Environment
        settings (notifications, integrations, just-in-time policies)
        Every table can be searched, filtered, grouped and downloaded as CSV,
        and a row opens every field of it - more than its column - in a
        details panel. Tabs with nothing to show are left out.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Assessment,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Title,

        [System.Collections.IDictionary] $Detail
    )

    $a = $Assessment; $stats = $a.Stats
    $severity = @{ Critical = 'bad'; High = 'bad'; Medium = 'warn'; Low = 'info'; Informational = 'neutral' }
    $onOff = @{ On = 'good'; Off = 'warn' }
    $statusTones = @{ Unhealthy = 'bad'; Healthy = 'good'; 'Not applicable' = 'neutral' }
    $settingTones = @{ Good = 'good'; Warning = 'bad'; Review = 'warn'; Unknown = 'neutral' }
    $col = { param([string] $Key, [string] $Label, [hashtable] $More = @{}) $c = @{ Key = $Key; Label = $Label }; foreach ($k in $More.Keys) { $c[$k] = $More[$k] }; $c }
    $facet = @{ Facet = $true }; $num = @{ Type = 'number' }; $wide = @{ Type = 'wide' }; $hiddenWide = @{ Type = 'wide'; Hidden = $true }
    $sev = @{ Type = 'badge'; Tones = $severity; Facet = $true }
    $tone = { param([int] $Bad, [int] $Warn = 0) if ($Bad) { 'bad' } elseif ($Warn) { 'warn' } else { 'good' } }

    $tiles = @(
        @{ Value = $(if ($null -ne $stats.SecureScore) { "$($stats.SecureScore)%" } else { '-' }); Label = "secure score ($($stats.Subscriptions) subscription(s))"; Tone = $(if ($null -eq $stats.SecureScore) { 'neutral' } elseif ($stats.SecureScore -ge 70) { 'good' } elseif ($stats.SecureScore -ge 40) { 'warn' } else { 'bad' }); Table = 'def-controls' }
        @{ Value = '{0:N0}' -f $stats.Recommendations; Label = "recommendations on $('{0:N0}' -f $stats.UnhealthyResources) resource(s) ($($stats.HighRecommendations) High)"; Tone = & $tone $stats.HighRecommendations $stats.Recommendations; Table = 'def-recommendations'; Filters = @{ Status = 'Unhealthy' } }
        @{ Value = '{0:N0}' -f $stats.AttackPaths; Label = "attack paths ($($stats.CriticalAttackPaths) Critical or High)"; Tone = & $tone $stats.CriticalAttackPaths $stats.AttackPaths; Table = 'def-attack-paths' }
        @{ Value = '{0:N0}' -f $stats.ActiveAlerts; Label = "active alerts ($($stats.HighAlerts) High; $($stats.Alerts) in the period)"; Tone = & $tone $stats.HighAlerts $stats.ActiveAlerts; Table = 'def-alerts'; Filters = @{ Active = 'Yes' } }
        @{ Value = '{0:N0}' -f $stats.Vulnerabilities; Label = "vulnerabilities ($($stats.HighVulnerabilities) Critical or High)"; Tone = & $tone $stats.HighVulnerabilities $stats.Vulnerabilities; Table = 'def-vulnerabilities' }
        @{ Value = "$($stats.PlansOn) / $($stats.PlansOn + $stats.PlansOff)"; Label = 'Defender plans on'; Tone = $(if ($stats.PlansOff) { 'warn' } else { 'good' }); Table = 'def-plans' }
        @{ Value = '{0:N0}' -f $stats.FailedControls; Label = "failed compliance controls ($($stats.Standards) standard(s))"; Tone = & $tone 0 $stats.FailedControls; Table = 'def-compliance-controls'; Filters = @{ State = 'Failed' } }
        @{ Value = '{0:N0}' -f ($stats.Critical + $stats.High); Label = "Critical and High findings ($($stats.Findings) in all)"; Tone = & $tone ($stats.Critical + $stats.High) $stats.Findings; Table = 'def-findings' }
    )
    $bySeverity = { param($Rows, [string] $Table, [string] $Center) @{ Kind = 'donut'; CenterLabel = $Center; Table = $Table; Column = 'Severity'; Items = @($Rows | Group-Object Severity | Sort-Object { @{ Critical = 0; High = 1; Medium = 2; Low = 3 }[$_.Name] } | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Tone = $severity[$_.Name] } }) } }
    $charts = @(
        if (@($a.UnhealthyResources).Count) { (& $bySeverity $a.UnhealthyResources 'def-unhealthy' 'unhealthy') + @{ Title = 'Unhealthy resources by severity' } }
        if (@($a.Alerts).Count) { (& $bySeverity @($a.Alerts | Where-Object Active -EQ 'Yes') 'def-alerts' 'active') + @{ Title = 'Active alerts by severity'; BaseFilters = @{ Active = 'Yes' } } }
        if (@($a.Subscriptions | Where-Object { $null -ne $_.SecureScore }).Count) { @{ Title = 'Secure score by subscription (%)'; Table = 'def-subscriptions'; Column = 'Subscription'; Items = @($a.Subscriptions | Where-Object { $null -ne $_.SecureScore } | Select-Object -First 15 | ForEach-Object { @{ Label = $_.Subscription; Value = $_.SecureScore; Display = "$($_.SecureScore)%"; Tone = $(if ($_.SecureScore -ge 70) { 'good' } elseif ($_.SecureScore -ge 40) { 'warn' } else { 'bad' }) } }) } }
        if (@($a.Controls).Count) { @{ Title = 'Secure score controls: potential increase (%)'; Table = 'def-controls'; Column = 'Control'; Tone = 'info'; Items = @($a.Controls | Group-Object Control | ForEach-Object { @{ Label = $_.Name; Value = [Math]::Round(($_.Group | Measure-Object PotentialIncrease -Maximum).Maximum, 1) } } | Sort-Object { $_.Value } -Descending | Select-Object -First 10) } }
        if (@($a.Recommendations | Where-Object UnhealthyResources).Count) { @{ Title = 'Recommendations with the most unhealthy resources'; Wide = $true; Table = 'def-unhealthy'; Column = 'Recommendation'; Tone = 'warn'; Items = @($a.Recommendations | Where-Object UnhealthyResources | Sort-Object UnhealthyResources -Descending | Select-Object -First 12 | ForEach-Object { @{ Label = $_.Recommendation; Value = $_.UnhealthyResources; Tone = $severity[$_.Severity] } }) } }
        if (@($a.Inventory | Where-Object Unhealthy).Count) { @{ Title = 'Unhealthy resources by type'; Table = 'def-inventory'; Column = 'Type'; BaseFilters = @{ Status = 'Unhealthy' }; Tone = 'warn'; Items = @($a.Inventory | Where-Object Unhealthy | Group-Object Type | Sort-Object Count -Descending | Select-Object -First 12 | ForEach-Object { @{ Label = $_.Name; Value = $_.Count } }) } }
        if (@($a.Findings).Count) { @{ Title = 'Findings by area'; Table = 'def-findings'; Column = 'Area'; Tone = 'warn'; Items = @($a.Findings | Group-Object Area | Sort-Object Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count } }) } }
    )

    $tables = [System.Collections.Generic.List[hashtable]]::new()
    $add = { param([hashtable] $Table) if (@($Table.Rows).Count) { $tables.Add($Table) } }
    & $add @{
        Id = 'def-findings'; Section = 'Findings'; Title = 'Findings'; Note = 'What to improve in how Defender for Cloud is set up and used - most severe first.'; Noun = 'findings'; File = 'defender-findings'; Rows = @($a.Findings); GroupBy = @('Area', 'Severity', 'SubscriptionName', 'Finding')
        Columns = @((& $col 'Severity' 'Severity' $sev), (& $col 'Area' 'Area' $facet), (& $col 'Finding' 'Finding' $facet), (& $col 'Item' 'Item'), (& $col 'SubscriptionName' 'Subscription' $facet), (& $col 'Detail' 'What was found' $wide), (& $col 'Recommendation' 'What to do' $wide), (& $col 'Link' 'Docs' @{ Type = 'link'; Text = 'Docs ↗' }), (& $col 'ResourceId' 'ID' @{ Type = 'mono'; Hidden = $true }))
    }
    & $add @{
        Id = 'def-recommendations'; Section = 'Recommendations'; Title = 'Recommendations'; Note = 'Every recommendation assessed: its unhealthy, healthy and not applicable resources. Risk level and attack paths need Defender CSPM. A row opens the description and the remediation steps.'; Noun = 'recommendations'; File = 'defender-recommendations'; Rows = @($a.Recommendations); GroupBy = @('Control', 'Severity', 'Status', 'Categories')
        Filters = @{ Status = 'Unhealthy' }
        Columns = @((& $col 'Recommendation' 'Recommendation' $wide), (& $col 'Severity' 'Severity' $sev), (& $col 'RiskLevel' 'Risk level' @{ Type = 'badge'; Tones = $severity; Facet = $true }), (& $col 'Status' 'Status' @{ Type = 'badge'; Tones = $statusTones; Facet = $true }), (& $col 'UnhealthyResources' 'Unhealthy' @{ Type = 'number'; Tone = 'bad'; Sum = $true }), (& $col 'HealthyResources' 'Healthy' @{ Type = 'number'; Sum = $true }), (& $col 'NotApplicableResources' 'Not applicable' $num), (& $col 'HealthyPercent' 'Healthy %' @{ Type = 'score' }), (& $col 'AttackPaths' 'Attack paths' $num), (& $col 'Control' 'Control' $facet), (& $col 'Categories' 'Categories' $facet), (& $col 'Subscriptions' 'Subscriptions' $num),
            (& $col 'Impact' 'Impact' @{ Facet = $true; Hidden = $true }), (& $col 'Effort' 'Effort' @{ Facet = $true; Hidden = $true }), (& $col 'Threats' 'Threats' $hiddenWide), (& $col 'Type' 'Built-in or custom' @{ Facet = $true; Hidden = $true }), (& $col 'Preview' 'Preview' @{ Facet = $true; Hidden = $true }), (& $col 'Description' 'Description' $hiddenWide), (& $col 'Remediation' 'Remediation steps' $hiddenWide), (& $col 'Link' 'Portal' @{ Type = 'link'; Text = 'Open ↗' }), (& $col 'Key' 'Assessment key' @{ Type = 'mono'; Hidden = $true }), (& $col 'PolicyDefinitionId' 'Policy definition' @{ Type = 'mono'; Hidden = $true }))
    }
    & $add @{
        Id = 'def-unhealthy'; Section = 'Recommendations'; Title = 'Unhealthy resources'; Note = 'Each unhealthy recommendation on each resource, highest risk first.'; Noun = 'unhealthy resources'; File = 'defender-unhealthy-resources'; Rows = @($a.UnhealthyResources); GroupBy = @('Recommendation', 'Resource', 'Severity', 'Control', 'SubscriptionName', 'Type')
        Columns = @((& $col 'Resource' 'Resource' @{ Type = 'resource' }), (& $col 'Recommendation' 'Recommendation' @{ Type = 'wide'; Facet = $true }), (& $col 'Severity' 'Severity' $sev), (& $col 'RiskLevel' 'Risk level' @{ Type = 'badge'; Tones = $severity; Facet = $true }), (& $col 'RiskFactors' 'Risk factors' $wide), (& $col 'AttackPaths' 'Attack paths' $num), (& $col 'Type' 'Type' $facet), (& $col 'ResourceGroup' 'Resource group' $facet), (& $col 'SubscriptionName' 'Subscription' $facet), (& $col 'Since' 'Unhealthy since' @{ Type = 'date' }), (& $col 'Control' 'Control' @{ Facet = $true; Hidden = $true }), (& $col 'Source' 'Cloud' @{ Facet = $true; Hidden = $true }), (& $col 'Cause' 'Cause' $hiddenWide), (& $col 'Link' 'Portal' @{ Type = 'link'; Text = 'Open ↗' }))
    }
    & $add @{
        Id = 'def-attack-paths'; Section = 'Attack path analysis'; Title = 'Attack paths'; Note = 'How an attacker could move from an exposed entry point to a sensitive target (Defender CSPM). A row opens the path step by step, the attack story and how to fix it.'; Noun = 'attack paths'; File = 'defender-attack-paths'; Rows = @($a.AttackPaths); GroupBy = @('RiskLevel', 'AttackPath', 'SubscriptionName')
        Columns = @((& $col 'AttackPath' 'Attack path' $wide), (& $col 'RiskLevel' 'Risk level' $sev), (& $col 'Path' 'Path' @{ Type = 'path' }), (& $col 'RiskFactors' 'Risk factors' $wide), (& $col 'Steps' 'Steps' $num), (& $col 'Tactics' 'MITRE tactics' $wide), (& $col 'SubscriptionName' 'Subscription' $facet), (& $col 'EntryPoint' 'Entry point' @{ Hidden = $true }), (& $col 'Target' 'Target' @{ Hidden = $true }), (& $col 'Techniques' 'MITRE techniques' $hiddenWide), (& $col 'Description' 'Description' $hiddenWide), (& $col 'Story' 'Attack story' $hiddenWide), (& $col 'Remediation' 'Remediation' $hiddenWide), (& $col 'Id' 'ID' @{ Type = 'mono'; Hidden = $true }))
    }
    & $add @{
        Id = 'def-alerts'; Section = 'Security alerts'; Title = 'Security alerts'; Note = 'Alerts generated in the period, every status - active ones first. A row opens the description, the MITRE techniques and the remediation steps.'; Noun = 'alerts'; File = 'defender-alerts'; Rows = @($a.Alerts); GroupBy = @('Alert', 'Severity', 'Status', 'Resource', 'Tactics', 'SubscriptionName')
        Columns = @((& $col 'Alert' 'Alert' $wide), (& $col 'Severity' 'Severity' $sev), (& $col 'Status' 'Status' $facet), (& $col 'Active' 'Active' @{ Type = 'badge'; Tones = @{ Yes = 'warn'; No = 'neutral' }; Facet = $true }), (& $col 'Resource' 'Resource' @{ Type = 'resource' }), (& $col 'Tactics' 'MITRE tactics' $facet), (& $col 'TimeGenerated' 'Generated' @{ Type = 'datetime' }), (& $col 'AgeDays' 'Age (days)' $num), (& $col 'SubscriptionName' 'Subscription' $facet), (& $col 'Product' 'Detected by' @{ Facet = $true; Hidden = $true }),
            (& $col 'Incident' 'Incident' @{ Facet = $true; Hidden = $true }), (& $col 'Techniques' 'MITRE techniques' $hiddenWide), (& $col 'Entity' 'Compromised entity' @{ Hidden = $true }), (& $col 'StartTime' 'Activity start' @{ Type = 'datetime'; Hidden = $true }), (& $col 'EndTime' 'Activity end' @{ Type = 'datetime'; Hidden = $true }), (& $col 'AlertType' 'Alert type' @{ Type = 'mono'; Hidden = $true }), (& $col 'Description' 'Description' $hiddenWide), (& $col 'Remediation' 'Remediation steps' $hiddenWide), (& $col 'Link' 'Portal' @{ Type = 'link'; Text = 'Open ↗' }))
    }
    & $add @{
        Id = 'def-suppression'; Section = 'Security alerts'; Title = 'Alert suppression rules'; Noun = 'rules'; File = 'defender-suppression-rules'; Rows = @($a.SuppressionRules)
        Columns = @((& $col 'Rule' 'Rule'), (& $col 'AlertType' 'Alert type' @{ Type = 'mono' }), (& $col 'Status' 'Status' @{ Type = 'badge'; Tones = @{ Active = 'good'; 'No expiry' = 'warn'; Expired = 'neutral'; Disabled = 'neutral' }; Facet = $true }), (& $col 'Expires' 'Expires' @{ Type = 'date' }), (& $col 'Reason' 'Reason' $facet), (& $col 'Comment' 'Comment' $wide), (& $col 'SubscriptionName' 'Subscription' $facet))
    }
    & $add @{
        Id = 'def-inventory'; Section = 'Inventory'; Title = 'Inventory'; Note = 'Every resource Defender for Cloud assesses: the plan that protects it, its recommendations by severity, vulnerabilities, active alerts and attack paths.'; Noun = 'resources'; File = 'defender-inventory'; Rows = @($a.Inventory); GroupBy = @('Type', 'SubscriptionName', 'ResourceGroup', 'Plan', 'Status')
        Columns = @((& $col 'Resource' 'Resource' @{ Type = 'resource' }), (& $col 'Type' 'Type' $facet), (& $col 'Status' 'Status' @{ Type = 'badge'; Tones = $statusTones; Facet = $true }), (& $col 'Plan' 'Defender plan' $facet), (& $col 'PlanState' 'Plan' @{ Type = 'badge'; Tones = $onOff; Facet = $true }), (& $col 'Unhealthy' 'Unhealthy' @{ Type = 'number'; Sum = $true }), (& $col 'High' 'High' @{ Type = 'number'; Tone = 'bad'; Sum = $true }), (& $col 'Medium' 'Medium' @{ Type = 'number'; Tone = 'warn'; Sum = $true }), (& $col 'Low' 'Low' @{ Type = 'number'; Sum = $true }), (& $col 'Healthy' 'Healthy' @{ Type = 'number'; Sum = $true }), (& $col 'Vulnerabilities' 'Vulnerabilities' @{ Type = 'number'; Sum = $true }), (& $col 'Alerts' 'Alerts' @{ Type = 'number'; Sum = $true }), (& $col 'AttackPaths' 'Attack paths' @{ Type = 'number'; Sum = $true }), (& $col 'ResourceGroup' 'Resource group' $facet), (& $col 'SubscriptionName' 'Subscription' $facet), (& $col 'Source' 'Cloud' @{ Facet = $true; Hidden = $true }), (& $col 'NotApplicable' 'Not applicable' @{ Type = 'number'; Hidden = $true }))
    }
    & $add @{
        Id = 'def-vulnerabilities'; Section = 'Vulnerabilities'; Title = 'Vulnerabilities'; Note = 'Findings of Defender''s vulnerability assessments (machines, SQL, container images), most severe first.'; Noun = 'vulnerabilities'; File = 'defender-vulnerabilities'; Rows = @($a.Vulnerabilities); GroupBy = @('Vulnerability', 'Resource', 'Severity', 'Category', 'Recommendation')
        Columns = @((& $col 'Vulnerability' 'Vulnerability' $wide), (& $col 'Severity' 'Severity' $sev), (& $col 'CVEs' 'CVEs' @{ Type = 'mono' }), (& $col 'Patchable' 'Patchable' @{ Type = 'badge'; Tones = @{ Yes = 'good'; No = 'warn' }; Facet = $true }), (& $col 'Resource' 'Resource' @{ Type = 'resource' }), (& $col 'Image' 'Image'), (& $col 'Category' 'Category' $facet), (& $col 'Type' 'Type' $facet), (& $col 'SubscriptionName' 'Subscription' $facet), (& $col 'Recommendation' 'Recommendation' @{ Facet = $true; Hidden = $true }), (& $col 'Impact' 'Impact' $hiddenWide), (& $col 'Remediation' 'Remediation' $hiddenWide), (& $col 'Generated' 'Found' @{ Type = 'date'; Hidden = $true }), (& $col 'VulnerabilityId' 'ID' @{ Type = 'mono'; Hidden = $true }))
    }
    & $add @{
        Id = 'def-subscriptions'; Section = 'Security posture'; Title = 'Subscriptions'; Noun = 'subscriptions'; File = 'defender-subscriptions'; Rows = @($a.Subscriptions)
        Columns = @((& $col 'Subscription' 'Subscription' @{ Type = 'resource' }), (& $col 'SecureScore' 'Secure score' @{ Type = 'score' }), (& $col 'PlansOn' 'Plans on' $num), (& $col 'Plans' 'Plans' $num), (& $col 'UnhealthyResources' 'Unhealthy resources' @{ Type = 'number'; Sum = $true }), (& $col 'HighRecommendations' 'High recommendations' @{ Type = 'number'; Tone = 'bad'; Sum = $true }), (& $col 'AttackPaths' 'Attack paths' @{ Type = 'number'; Sum = $true }), (& $col 'ActiveAlerts' 'Active alerts' @{ Type = 'number'; Sum = $true }), (& $col 'Vulnerabilities' 'Vulnerabilities' @{ Type = 'number'; Sum = $true }), (& $col 'Findings' 'Findings' @{ Type = 'number'; Sum = $true }), (& $col 'SubscriptionId' 'ID' @{ Type = 'mono'; Hidden = $true }))
    }
    & $add @{
        Id = 'def-controls'; Section = 'Security posture'; Title = 'Secure score controls'; Note = 'Potential increase: how much the subscription''s secure score rises when the control is fully healthy - biggest first.'; Noun = 'controls'; File = 'defender-secure-score-controls'; Rows = @($a.Controls); GroupBy = @('Control', 'SubscriptionName')
        Columns = @((& $col 'Control' 'Control' $facet), (& $col 'SubscriptionName' 'Subscription' $facet), (& $col 'Score' 'Score' @{ Type = 'score' }), (& $col 'PotentialIncrease' 'Potential increase (%)' @{ Type = 'number'; Format = 'N1'; Tone = 'warn' }), (& $col 'Current' 'Points' @{ Type = 'number'; Format = 'N2' }), (& $col 'Max' 'Max points' @{ Type = 'number'; Format = 'N2' }), (& $col 'UnhealthyResources' 'Unhealthy resources' $num), (& $col 'HealthyResources' 'Healthy resources' $num))
    }
    & $add @{
        Id = 'def-plans'; Section = 'Security posture'; Title = 'Defender plans'; Note = 'Resources: those Defender assesses that the plan covers.'; Noun = 'plans'; File = 'defender-plans'; Rows = @($a.Plans); GroupBy = @('SubscriptionName', 'Plan', 'State')
        Columns = @((& $col 'Plan' 'Plan' $facet), (& $col 'State' 'State' @{ Type = 'badge'; Tones = $onOff; Facet = $true }), (& $col 'SubPlan' 'Sub-plan' $facet), (& $col 'Extensions' 'Extensions on' $wide), (& $col 'Resources' 'Resources' @{ Type = 'number'; Sum = $true }), (& $col 'Since' 'On since' @{ Type = 'date' }), (& $col 'SubscriptionName' 'Subscription' $facet), (& $col 'Tier' 'Tier' @{ Hidden = $true }), (& $col 'Name' 'API name' @{ Type = 'mono'; Hidden = $true }))
    }
    & $add @{
        Id = 'def-connectors'; Section = 'Security posture'; Title = 'Multicloud and DevOps connectors'; Noun = 'connectors'; File = 'defender-connectors'; Rows = @($a.Connectors)
        Columns = @((& $col 'Connector' 'Connector' @{ Type = 'resource' }), (& $col 'Environment' 'Environment' $facet), (& $col 'Account' 'Account / organization'), (& $col 'Offerings' 'Plans and features' $wide), (& $col 'Location' 'Location'), (& $col 'SubscriptionName' 'Subscription' $facet))
    }
    & $add @{
        Id = 'def-standards'; Section = 'Regulatory compliance'; Title = 'Compliance standards'; Noun = 'standards'; File = 'defender-compliance-standards'; Rows = @($a.Standards); GroupBy = @('Standard', 'SubscriptionName')
        Columns = @((& $col 'Standard' 'Standard' $facet), (& $col 'SubscriptionName' 'Subscription' $facet), (& $col 'PassRate' 'Controls passed' @{ Type = 'score' }), (& $col 'PassedControls' 'Passed' $num), (& $col 'FailedControls' 'Failed' @{ Type = 'number'; Tone = 'bad' }), (& $col 'SkippedControls' 'Skipped' $num), (& $col 'UnsupportedControls' 'Unsupported' $num), (& $col 'State' 'State' $facet))
    }
    & $add @{
        Id = 'def-compliance-controls'; Section = 'Regulatory compliance'; Title = 'Compliance controls'; Noun = 'controls'; File = 'defender-compliance-controls'; Rows = @($a.ComplianceControls); GroupBy = @('Standard', 'State', 'SubscriptionName'); Filters = @{ State = 'Failed' }
        Columns = @((& $col 'Standard' 'Standard' $facet), (& $col 'Control' 'Control' @{ Type = 'mono' }), (& $col 'Description' 'Description' $wide), (& $col 'State' 'State' @{ Type = 'badge'; Tones = @{ Passed = 'good'; Failed = 'bad'; Skipped = 'neutral'; Unsupported = 'neutral' }; Facet = $true }), (& $col 'FailedAssessments' 'Failed assessments' @{ Type = 'number'; Tone = 'bad' }), (& $col 'PassedAssessments' 'Passed' $num), (& $col 'SkippedAssessments' 'Skipped' $num), (& $col 'SubscriptionName' 'Subscription' $facet))
    }
    & $add @{
        Id = 'def-compliance-assessments'; Section = 'Regulatory compliance'; Title = 'Failed assessments'; Note = 'The assessments behind the failed controls, and the recommendation to fix.'; Noun = 'assessments'; File = 'defender-compliance-assessments'; Rows = @($a.ComplianceAssessments); GroupBy = @('Standard', 'Control', 'Recommendation', 'SubscriptionName')
        Columns = @((& $col 'Standard' 'Standard' $facet), (& $col 'Control' 'Control' @{ Type = 'mono'; Facet = $true }), (& $col 'Assessment' 'Assessment' $wide), (& $col 'Severity' 'Severity' $sev), (& $col 'FailedResources' 'Failed resources' @{ Type = 'number'; Tone = 'bad'; Sum = $true }), (& $col 'Recommendation' 'Recommendation' $wide), (& $col 'SubscriptionName' 'Subscription' $facet))
    }
    & $add @{
        Id = 'def-settings'; Section = 'Environment settings'; Title = 'Notifications and integrations'; Noun = 'settings'; File = 'defender-settings'; Rows = @($a.Settings); GroupBy = @('SubscriptionName', 'Area', 'Setting', 'Status')
        Columns = @((& $col 'Setting' 'Setting' $facet), (& $col 'Value' 'Value' $wide), (& $col 'Status' 'Status' @{ Type = 'badge'; Tones = $settingTones; Facet = $true }), (& $col 'Area' 'Area' $facet), (& $col 'SubscriptionName' 'Subscription' $facet), (& $col 'Detail' 'About' $wide))
    }
    & $add @{
        Id = 'def-jit'; Section = 'Environment settings'; Title = 'Just-in-time VM access'; Noun = 'ports'; File = 'defender-jit'; Rows = @($a.JitPolicies)
        Columns = @((& $col 'VirtualMachine' 'Virtual machine' @{ Type = 'resource' }), (& $col 'Port' 'Port'), (& $col 'Protocol' 'Protocol' $facet), (& $col 'AllowedSource' 'Allowed source'), (& $col 'MaxDuration' 'Max duration'), (& $col 'Policy' 'Policy' $facet), (& $col 'SubscriptionName' 'Subscription' $facet))
    }

    $badge = { param([int] $Count, [string] $Tone) @{ Badge = $(if ($Count) { $Count.ToString('N0') } else { '' }); Tone = $Tone } }
    $tabs = @(
        @{ Name = 'Findings' } + (& $badge ($stats.Critical + $stats.High) 'bad')
        @{ Name = 'Recommendations' } + (& $badge $stats.Recommendations $(if ($stats.HighRecommendations) { 'bad' } else { 'warn' }))
        @{ Name = 'Attack path analysis'; Note = $(if (-not @($a.AttackPaths).Count) { 'No attack paths: either none were found, or Defender CSPM is off (attack path analysis needs it).' }) } + (& $badge $stats.AttackPaths 'bad')
        @{ Name = 'Security alerts' } + (& $badge $stats.ActiveAlerts $(if ($stats.HighAlerts) { 'bad' } else { 'warn' }))
        @{ Name = 'Inventory' } + (& $badge $stats.Resources '')
        @{ Name = 'Vulnerabilities' } + (& $badge $stats.Vulnerabilities $(if ($stats.HighVulnerabilities) { 'bad' } else { 'warn' }))
        @{ Name = 'Security posture' } + @{ Badge = $(if ($null -ne $stats.SecureScore) { "$($stats.SecureScore)%" } else { '' }); Tone = $(if ($stats.SecureScore -ge 70) { 'good' } elseif ($stats.SecureScore -ge 40) { 'warn' } else { 'bad' }) }
        @{ Name = 'Regulatory compliance' } + (& $badge $stats.FailedControls 'warn')
        @{ Name = 'Environment settings' }
    )
    $notices = @(foreach ($line in @($a.Notices)) { @{ Tone = 'warn'; Text = $line } })
    $notices += @{ Tone = 'info'; Text = 'Read-only, from Azure Resource Graph (securityresources) and the Defender for Cloud REST API. Click a tile or a bar to open its tab, and any table row for all its details.' }
    Write-AACHtmlReport -Path $Path -Title $Title -Subtitle 'Microsoft Defender for Cloud: recommendations, attack paths, alerts, inventory, posture and compliance' -Fact $Detail -Tile $tiles -Chart $charts -Table $tables.ToArray() -Notice $notices -Tab $tabs
}
