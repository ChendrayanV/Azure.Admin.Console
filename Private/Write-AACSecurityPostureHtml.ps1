function Write-AACSecurityPostureHtml {
    <#
    .SYNOPSIS
        Writes Get-AACSecurityPosture's result as an interactive HTML report:
        tiles and charts that filter the tables - every finding, the
        subscriptions, secure score controls, compliance standards and
        controls, and Defender plans - with portal links and CSV downloads.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Posture,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Title,

        [System.Collections.IDictionary] $Detail
    )

    $stats = $Posture.Stats
    $sections = @($Posture.Sections)
    $findings = @($Posture.Findings)
    $tone = @{ Good = 'good'; Fair = 'warn'; Poor = 'bad' }
    $severityTones = @{ High = 'bad'; Medium = 'warn'; Low = 'info'; Informational = 'neutral' }
    $top = {
        param([object[]] $Items, [string] $Property, [int] $First = 12, [hashtable] $Tones = @{})
        @($Items | Where-Object { $_.$Property } | Group-Object -Property $Property | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, Name | Select-Object -First $First | ForEach-Object {
                $item = @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name }
                if ($Tones.Contains($_.Name)) { $item.Tone = $Tones[$_.Name] }
                $item
            })
    }

    $tiles = @(
        @{ Value = $(if ($null -ne $stats.SecureScore) { "$($stats.SecureScore)%" } else { '-' }); Label = $(if ($stats.Rating) { "secure score ($($stats.Rating.ToLowerInvariant()))" } else { 'secure score' }); Tone = $(if ($stats.Rating) { $tone[$stats.Rating] } else { 'neutral' }); Table = 'subscriptions' }
        @{ Value = '{0:N0}' -f $stats.Findings; Label = 'findings'; Tone = 'neutral'; Table = 'findings' }
        if ($sections -contains 'Recommendations') {
            @{ Value = '{0:N0}' -f $stats.High; Label = 'high recommendations'; Tone = $(if ($stats.High) { 'bad' } else { 'good' }); Table = 'findings'; Filters = @{ Section = 'Recommendation'; Severity = 'High' } }
            @{ Value = '{0:N0}' -f $stats.Medium; Label = 'medium recommendations'; Tone = $(if ($stats.Medium) { 'warn' } else { 'good' }); Table = 'findings'; Filters = @{ Section = 'Recommendation'; Severity = 'Medium' } }
        }
        if ($sections -contains 'Alerts') { @{ Value = '{0:N0}' -f $stats.Alerts; Label = 'active alerts'; Tone = $(if ($stats.HighAlerts) { 'bad' } elseif ($stats.Alerts) { 'warn' } else { 'good' }); Table = 'findings'; Filters = @{ Section = 'Alert' } } }
        if ($sections -contains 'Plans') { @{ Value = "$($stats.PlansOn) / $($stats.PlansOn + $stats.PlansOff)"; Label = 'Defender plans on'; Tone = $(if ($stats.PlansOff) { 'warn' } else { 'good' }); Table = 'plans' } }
        if ($sections -contains 'Compliance') { @{ Value = '{0:N0}' -f $stats.FailedControls; Label = 'failed compliance controls'; Tone = $(if ($stats.FailedControls) { 'bad' } else { 'good' }); Table = 'complianceControls'; Filters = @{ State = 'Failed' } } }
        if ($sections -contains 'Policy') { @{ Value = $(if ($null -ne $stats.PolicyCompliance) { "$($stats.PolicyCompliance)%" } else { '-' }); Label = 'Azure Policy compliance'; Tone = $(if ($null -eq $stats.PolicyCompliance) { 'neutral' } elseif ($stats.PolicyCompliance -ge 90) { 'good' } elseif ($stats.PolicyCompliance -ge 70) { 'warn' } else { 'bad' }); Table = 'policy' } }
    )

    $charts = @(
        @{ Title = 'Findings by severity'; Items = @(& $top $findings 'Severity' 5 $severityTones); Table = 'findings'; Column = 'Severity' }
        @{ Title = 'Findings by section'; Items = @(& $top $findings 'Section'); Table = 'findings'; Column = 'Section' }
        if ($sections -contains 'Recommendations') { @{ Title = 'Recommendations by secure score control'; Items = @(& $top @($findings | Where-Object Section -EQ 'Recommendation') 'Control'); Table = 'findings'; Column = 'Control'; Tone = 'bad'; Wide = $true } }
        if ($sections -contains 'Recommendations') { @{ Title = 'Most common recommendations'; Items = @(& $top @($findings | Where-Object Section -EQ 'Recommendation') 'Title'); Table = 'findings'; Column = 'Title'; Tone = 'warn'; Wide = $true } }
        if ($sections -contains 'Compliance' -and $Posture.Standards.Count) {
            @{ Title = 'Compliance: controls passed (%)'; Items = @($Posture.Standards | Where-Object { $null -ne $_.PassRate } | ForEach-Object { @{ Label = "$($_.Standard) ($($_.SubscriptionName))"; Value = $_.PassRate; Display = "$($_.PassRate)%"; Tone = $(if ($_.PassRate -ge 70) { 'good' } elseif ($_.PassRate -ge 40) { 'warn' } else { 'bad' }); Filter = $_.Standard } }); Table = 'complianceControls'; Column = 'Standard'; Wide = $true }
        }
    )

    $tables = @(
        @{
            Id = 'findings'; Title = 'Findings'; Note = 'Every finding: unhealthy recommendations, active alerts, failed compliance checks and Defender plans that are off - most severe first.'
            Noun = 'findings'; File = 'security-findings'; Rows = $findings; GroupBy = @('Section', 'Severity', 'Title', 'Control', 'SubscriptionName', 'Resource')
            Columns = @(
                @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $severityTones; Facet = $true }
                @{ Key = 'Section'; Label = 'Section'; Type = 'badge'; Tones = @{ Alert = 'bad'; Recommendation = 'warn'; Compliance = 'violet'; Policy = 'violet'; Plan = 'info' }; Facet = $true }
                @{ Key = 'Title'; Label = 'Finding'; Type = 'wide'; Facet = $true }
                @{ Key = 'Resource'; Label = 'Resource'; Type = 'resource'; IdKey = 'ResourceId' }
                @{ Key = 'Control'; Label = 'Control'; Facet = $true }
                @{ Key = 'Category'; Label = 'Category'; Facet = $true }
                @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                @{ Key = 'SubscriptionName'; Label = 'Subscription'; Facet = $true }
                @{ Key = 'State'; Label = 'State'; Facet = $true }
                @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide' }
                @{ Key = 'Link'; Label = 'Portal'; Type = 'link'; Text = 'Open' }
                @{ Key = 'Type'; Label = 'Type'; Facet = $true; Hidden = $true }
                @{ Key = 'ResourceId'; Label = 'Resource ID'; Hidden = $true }
            )
        }
        @{
            Id = 'subscriptions'; Title = 'Subscriptions'; Noun = 'subscriptions'; File = 'security-subscriptions'; Rows = @($Posture.Subscriptions)
            Columns = @(
                @{ Key = 'SubscriptionName'; Label = 'Subscription' }
                @{ Key = 'SecureScore'; Label = 'Secure score'; Type = 'score' }
                @{ Key = 'Points'; Label = 'Points' }
                @{ Key = 'High'; Label = 'High'; Type = 'number'; Sum = $true; Format = 'N0'; Tone = 'bad' }
                @{ Key = 'Medium'; Label = 'Medium'; Type = 'number'; Sum = $true; Format = 'N0'; Tone = 'warn' }
                @{ Key = 'Low'; Label = 'Low'; Type = 'number'; Sum = $true; Format = 'N0' }
                @{ Key = 'Alerts'; Label = 'Alerts'; Type = 'number'; Sum = $true; Format = 'N0'; Tone = 'bad' }
                @{ Key = 'PlansOn'; Label = 'Plans on'; Type = 'number'; Sum = $true; Format = 'N0' }
                @{ Key = 'PlansOff'; Label = 'Plans off'; Type = 'number'; Sum = $true; Format = 'N0'; Tone = 'warn' }
                @{ Key = 'FailedControls'; Label = 'Failed compliance controls'; Type = 'number'; Sum = $true; Format = 'N0'; Tone = 'bad' }
                @{ Key = 'PolicyCompliance'; Label = 'Azure Policy compliance'; Type = 'score' }
                @{ Key = 'SubscriptionId'; Label = 'Subscription ID'; Type = 'mono'; Hidden = $true }
            )
        }
    )
    if (@($Posture.Controls).Count) {
        $tables += @{
            Id = 'controls'; Title = 'Secure score controls'; Note = 'The potential increase is how much the subscription''s secure score rises when the control is healthy.'
            Noun = 'controls'; File = 'secure-score-controls'; Rows = @($Posture.Controls); Sort = @{ Key = 'PotentialIncrease'; Desc = $true }; GroupBy = @('SubscriptionName')
            Columns = @(
                @{ Key = 'Control'; Label = 'Control' }
                @{ Key = 'SubscriptionName'; Label = 'Subscription'; Facet = $true }
                @{ Key = 'Score'; Label = 'Score'; Type = 'score' }
                @{ Key = 'Current'; Label = 'Points'; Type = 'number'; Format = 'N2' }
                @{ Key = 'Max'; Label = 'Out of'; Type = 'number'; Format = 'N2' }
                @{ Key = 'PotentialIncrease'; Label = 'Potential increase (%)'; Type = 'number'; Format = 'N1'; Tone = 'bad' }
                @{ Key = 'UnhealthyResources'; Label = 'Unhealthy resources'; Type = 'number'; Sum = $true; Format = 'N0' }
            )
        }
    }
    if ($sections -contains 'Compliance' -and $Posture.Standards.Count) {
        $tables += @{
            Id = 'standards'; Title = 'Compliance standards'; Noun = 'standards'; File = 'compliance-standards'; Rows = @($Posture.Standards)
            Columns = @(
                @{ Key = 'Standard'; Label = 'Standard'; Facet = $true }
                @{ Key = 'SubscriptionName'; Label = 'Subscription'; Facet = $true }
                @{ Key = 'PassRate'; Label = 'Controls passed'; Type = 'score' }
                @{ Key = 'PassedControls'; Label = 'Passed'; Type = 'number'; Format = 'N0' }
                @{ Key = 'FailedControls'; Label = 'Failed'; Type = 'number'; Format = 'N0'; Tone = 'bad' }
                @{ Key = 'SkippedControls'; Label = 'Skipped'; Type = 'number'; Format = 'N0' }
                @{ Key = 'UnsupportedControls'; Label = 'Unsupported'; Type = 'number'; Format = 'N0' }
                @{ Key = 'State'; Label = 'State'; Type = 'badge'; Tones = @{ Passed = 'good'; Failed = 'bad' }; Facet = $true }
            )
        }
        $tables += @{
            Id = 'complianceControls'; Title = 'Compliance controls'; Noun = 'controls'; File = 'compliance-controls'; Rows = @($Posture.ComplianceControls); GroupBy = @('Standard', 'State', 'SubscriptionName')
            Columns = @(
                @{ Key = 'Standard'; Label = 'Standard'; Facet = $true }
                @{ Key = 'Control'; Label = 'Control' }
                @{ Key = 'Description'; Label = 'Description'; Type = 'wide' }
                @{ Key = 'State'; Label = 'State'; Type = 'badge'; Tones = @{ Passed = 'good'; Failed = 'bad'; Skipped = 'neutral'; Unsupported = 'neutral' }; Facet = $true }
                @{ Key = 'FailedAssessments'; Label = 'Failed checks'; Type = 'number'; Sum = $true; Format = 'N0'; Tone = 'bad' }
                @{ Key = 'PassedAssessments'; Label = 'Passed checks'; Type = 'number'; Sum = $true; Format = 'N0' }
                @{ Key = 'FailingChecks'; Label = 'Failing checks'; Type = 'wide' }
                @{ Key = 'SubscriptionName'; Label = 'Subscription'; Facet = $true }
            )
        }
    }
    if ($sections -contains 'Policy' -and $Posture.PolicyAssignments.Count) {
        $charts += @{ Title = 'Azure Policy: non-compliant resources by policy'; Items = @(& $top @($findings | Where-Object Section -EQ 'Policy') 'Title'); Table = 'findings'; Column = 'Title'; Tone = 'violet'; Wide = $true }
        $tables += @{
            Id = 'policy'; Title = 'Azure Policy assignments'; Note = 'Compliance as the Azure portal counts it: (compliant + exempt + unknown + protected resources) / every resource evaluated. Get-AACPolicyState has every state.'
            Noun = 'assignments'; File = 'policy-assignments'; Rows = @($Posture.PolicyAssignments); GroupBy = @('Scope', 'Enforcement')
            Columns = @(
                @{ Key = 'Assignment'; Label = 'Assignment' }
                @{ Key = 'Scope'; Label = 'Assigned at'; Facet = $true }
                @{ Key = 'ComplianceRate'; Label = 'Compliance'; Type = 'score' }
                @{ Key = 'NonCompliant'; Label = 'Non-compliant'; Type = 'number'; Sum = $true; Format = 'N0'; Tone = 'bad' }
                @{ Key = 'Compliant'; Label = 'Compliant'; Type = 'number'; Sum = $true; Format = 'N0' }
                @{ Key = 'Exempt'; Label = 'Exempt'; Type = 'number'; Sum = $true; Format = 'N0' }
                @{ Key = 'Enforcement'; Label = 'Enforcement'; Facet = $true }
                @{ Key = 'AssignmentId'; Label = 'Assignment ID'; Type = 'mono'; Hidden = $true }
            )
        }
    }
    if ($sections -contains 'Plans' -and $Posture.Plans.Count) {
        $tables += @{
            Id = 'plans'; Title = 'Defender plans'; Noun = 'plans'; File = 'defender-plans'; Rows = @($Posture.Plans | Select-Object -Property *, @{ Name = 'Status'; Expression = { if ($_.Enabled) { 'On' } else { 'Off' } } }); GroupBy = @('SubscriptionName', 'Status')
            Columns = @(
                @{ Key = 'Plan'; Label = 'Plan'; Facet = $true }
                @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = @{ On = 'good'; Off = 'warn' }; Facet = $true }
                @{ Key = 'SubPlan'; Label = 'Sub-plan' }
                @{ Key = 'SubscriptionName'; Label = 'Subscription'; Facet = $true }
            )
        }
    }
    $notices = @(@($Posture.Notice | Where-Object { $_ }) | ForEach-Object { @{ Tone = 'info'; Text = $_ } })
    $notices += @{ Tone = 'info'; Text = 'Microsoft Defender for Cloud, read with Azure Resource Graph. Secure score: Defender''s points, added up across subscriptions. Good 70% or more, Fair 40-69%, Poor under 40%.' }

    Write-AACHtmlReport -Path $Path -Title $Title -Subtitle 'Microsoft Defender for Cloud and Azure Policy: secure score, recommendations, alerts, plans, regulatory and policy compliance' -Fact $Detail -Tile $tiles -Chart $charts -Table $tables -Notice $notices
}
