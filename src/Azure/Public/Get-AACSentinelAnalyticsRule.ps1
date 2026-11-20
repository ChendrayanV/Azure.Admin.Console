function Get-AACSentinelAnalyticsRule {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Lists the analytics rules in place on a Microsoft Sentinel workspace -
        kind, severity, enabled or not, MITRE ATT&CK tactics and techniques,
        schedule, the failures health reported, the incidents each raised and
        how many were false positives, and whether its template has a newer
        version - with the MITRE ATT&CK coverage of the enabled rules.
    .DESCRIPTION
        Reads the workspace - read-only, nothing is changed - from:
          Azure Resource Manager   the analytics rules, the rule templates
                                   (for newer versions) and the incidents
                                   created in the last -Days
          the workspace itself     KQL: _SentinelHealth (each rule's failed
                                   runs over -Days)

        Each rule: Name, RuleId, Kind, Enabled, Severity, Tactics, Techniques,
        Frequency, Period, CreatesIncident, TemplateId, TemplateVersion,
        LatestTemplate, TemplateUpdate, LastModified, Failures, LastFailure,
        Incidents, ClosedIncidents, FalsePositives and Query. Failing rules
        first, then enabled, by severity.

        Without health monitoring on (Sentinel's Settings), Failures stays 0:
        the view says so. Invoke-AACSentinelAssessment goes further, with rule
        templates worth enabling, data the rules don't read, and
        recommendations.

        Needs Microsoft Sentinel Reader on the workspace (and Log Analytics
        Reader for the failures).
    .PARAMETER WorkspaceId
        The workspace: its workspace ID (GUID), resource ID or name.
    .PARAMETER SubscriptionId
        Where to look for a workspace given by ID (GUID) or name. Every
        subscription the account can see by default.
    .PARAMETER ResourceGroupName
        Narrows a workspace given by name, when the name is in more than one
        resource group.
    .PARAMETER Name
        Only rules whose display name or rule ID matches; wildcards work.
    .PARAMETER Kind
        Only rules of these kinds (Scheduled, NRT, Fusion,
        MicrosoftSecurityIncidentCreation, MLBehaviorAnalytics,
        ThreatIntelligence).
    .PARAMETER Severity
        Only rules of these severities (High, Medium, Low, Informational).
    .PARAMETER State
        Only Enabled or only Disabled rules.
    .PARAMETER Tactic
        Only rules with one of these MITRE ATT&CK tactics (for example
        InitialAccess, 'Lateral*'); wildcards work.
    .PARAMETER Failing
        Only rules health reported failed runs for in the last -Days.
    .PARAMETER TemplateUpdate
        Only rules whose template has a newer version.
    .PARAMETER Days
        How far back health failures and incidents look: 1 to 90 days, 30 by
        default.
    .PARAMETER CsvPath
        Write the rules to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report to this file.
    .PARAMETER PdfPath
        Write a PDF report to this file.
    .PARAMETER Title
        The HTML and PDF reports' title.
    .PARAMETER PassThru
        Show the view and also return the rules.
    .PARAMETER NoDisplay
        Return the rules without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once instead of a page at a time.
    .EXAMPLE
        Connect-AAC
        Get-AACSentinelAnalyticsRule -WorkspaceId 'law-contoso-sentinel'
        Every analytics rule, failing ones first, with MITRE ATT&CK coverage.
    .EXAMPLE
        Get-AACSentinelAnalyticsRule -WorkspaceId 'law-contoso-sentinel' -State Enabled -Failing
        The enabled rules that failed to run in the last 30 days.
    .EXAMPLE
        Get-AACSentinelAnalyticsRule -WorkspaceId 'law-contoso-sentinel' -NoDisplay | Where-Object { $_.ClosedIncidents -ge 5 -and $_.FalsePositives / $_.ClosedIncidents -ge 0.5 }
        The noisy rules: half or more of their closed incidents were false positives.
    .EXAMPLE
        Get-AACSentinelAnalyticsRule -WorkspaceId 'law-contoso-sentinel' -TemplateUpdate -CsvPath .\out\RulesToUpdate.csv
        The rules whose template has moved on, to CSV.
    .EXAMPLE
        Get-AACSentinelAnalyticsRule -WorkspaceId 'law-contoso-sentinel' -HtmlPath .\out\AnalyticsRules.html -PdfPath .\out\AnalyticsRules.pdf
        The rules and MITRE ATT&CK coverage as an HTML report and a PDF.
    .OUTPUTS
        AAC.SentinelAnalyticsRule (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.SentinelAnalyticsRule')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [Alias('Workspace', 'WorkspaceName', 'ResourceId')]
        [ValidateNotNullOrEmpty()]
        [string] $WorkspaceId,

        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string] $ResourceGroupName,

        [SupportsWildcards()]
        [string[]] $Name,

        [ValidateSet('Scheduled', 'NRT', 'Fusion', 'MicrosoftSecurityIncidentCreation', 'MLBehaviorAnalytics', 'ThreatIntelligence')]
        [string[]] $Kind,

        [ValidateSet('High', 'Medium', 'Low', 'Informational')]
        [string[]] $Severity,

        [ValidateSet('Enabled', 'Disabled')]
        [string] $State,

        [SupportsWildcards()]
        [string[]] $Tactic,

        [switch] $Failing,

        [switch] $TemplateUpdate,

        [ValidateRange(1, 90)]
        [int] $Days = 30,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Microsoft Sentinel analytics rules',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    # A failure anywhere below ends as a Spectre.Console error panel and this
    # command's own terminating error, not a line inside the module. A stopped
    # pipeline (Select-Object -First, Ctrl+C) is no failure: just return - a
    # rethrow would stop the caller's whole script, not only this command.
    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Target) if ($Target) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Target) } }
    $insights = 'providers/Microsoft.SecurityInsights'
    $since = [datetime]::UtcNow.AddDays(-$Days).ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture)
    $arm = [ordered]@{
        alertRules         = "$insights/alertRules?api-version=2025-09-01"
        alertRuleTemplates = "$insights/alertRuleTemplates?api-version=2025-09-01"
        # Bounded by date, as in the assessment: every page is read.
        incidents          = "$insights/incidents?api-version=2025-09-01&`$top=1000&`$filter=$([uri]::EscapeDataString("properties/createdTimeUtc ge $since"))"
    }
    # Read here, not inside the progress block (it runs in Invoke-AACProgress's scope).
    $request = @{ Target = $WorkspaceId.Trim(); SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ResourceGroupName = $ResourceGroupName; Arm = $arm; Kql = (Get-AACSentinelAssessmentQuery -Section Health -Days $Days); Days = $Days }

    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Microsoft Sentinel analytics rules' -Color 'deepskyblue3_1' }
    $outcome = Invoke-AACProgress -ScriptBlock {
        $null = Get-AACAccessToken
        Update-AACProgress -Id 'read' -Indeterminate -Description "Reading the analytics rules of $($request.Target)"
        $read = Read-AACSentinelWorkspace -Target $request.Target -SubscriptionId $request.SubscriptionId -ResourceGroupName $request.ResourceGroupName -Arm $request.Arm -Kql $request.Kql -Timespan "P$($request.Days)D"
        $converted = ConvertTo-AACSentinelAssessment -Workspace $read.Workspace -Arm $read.Arm -Kql $read.Kql -Days $request.Days
        Update-AACProgress -Id 'read' -Complete -Description "Workspace $($read.Name): $(@($converted.AnalyticsRules).Count) analytics rule(s)"
        @{ Read = $read; Converted = $converted }
    }
    $read = $outcome.Read
    $converted = $outcome.Converted
    # Without the list there's nothing to show, and an empty one would mislead.
    if ($read.Arm['alertRules'].Error) {
        $problem = [System.InvalidOperationException]::new("Azure Admin Console couldn't read the analytics rules of $($read.Name): $($read.Arm['alertRules'].Error)")
        $problem.Data['AACHint'] = 'Your account needs Microsoft Sentinel Reader on the workspace.'
        throw $problem
    }

    # --- The filters ------------------------------------------------------------------------------------------
    $rules = @($converted.AnalyticsRules)
    $matchesAny = { param([string[]] $Value, [string[]] $Pattern) foreach ($v in $Value) { foreach ($p in $Pattern) { if ($v -and $v -like $p) { return $true } } }; $false }
    if ($Name) { $rules = @($rules | Where-Object { & $matchesAny @($_.Name, $_.RuleId) $Name }) }
    if ($Kind) { $rules = @($rules | Where-Object { $Kind -contains $_.Kind }) }
    if ($Severity) { $rules = @($rules | Where-Object { $Severity -contains $_.Severity }) }
    if ($State) { $rules = @($rules | Where-Object { $_.Enabled -eq ($State -eq 'Enabled') }) }
    if ($Tactic) { $rules = @($rules | Where-Object { & $matchesAny @($_.Tactics -split ', ') $Tactic }) }
    if ($Failing) { $rules = @($rules | Where-Object Failures -GT 0) }
    if ($TemplateUpdate) { $rules = @($rules | Where-Object TemplateUpdate) }

    # --- The report -------------------------------------------------------------------------------------------
    $severityTones = @{ High = 'bad'; Medium = 'warn'; Low = 'info'; Informational = 'neutral' }
    $enabled = @($rules | Where-Object Enabled)
    $failingRules = @($enabled | Where-Object Failures -GT 0)
    $outdated = @($rules | Where-Object TemplateUpdate)
    $noisy = @($rules | Where-Object { $_.ClosedIncidents -ge 5 -and 100 * $_.FalsePositives / $_.ClosedIncidents -ge 50 })
    $coverage = @($converted.TacticCoverage)
    $covered = @($coverage | Where-Object EnabledRules -GT 0).Count
    $rows = @($rules | ForEach-Object {
            [pscustomobject][ordered]@{
                Name            = $_.Name
                State           = $(if ($_.Enabled) { 'Enabled' } else { 'Disabled' })
                Kind            = $_.Kind
                Severity        = $_.Severity
                Tactics         = $_.Tactics
                Techniques      = $_.Techniques
                Frequency       = $_.Frequency
                Period          = $_.Period
                CreatesIncident = $(if ($null -eq $_.CreatesIncident) { '' } elseif ($_.CreatesIncident) { 'Yes' } else { 'No' })
                Failures        = $_.Failures
                LastFailure     = $_.LastFailure
                Incidents       = $_.Incidents
                FalsePositives  = $_.FalsePositives
                TemplateUpdate  = $(if ($_.TemplateUpdate) { "$($_.TemplateVersion) to $($_.LatestTemplate)" } else { '' })
                LastModified    = $_.LastModified
                TemplateId      = $_.TemplateId
                RuleId          = $_.RuleId
                Query           = $_.Query
            }
        })
    $notices = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($key in $converted.Errors.Keys) { $notices.Add(@{ Status = 'Warning'; Text = "$key couldn't be read: $($converted.Errors[$key])" }) }
    if ($converted.HealthState -in 'Off', 'NoRecords') { $notices.Add(@{ Status = 'Warning'; Text = "Sentinel health monitoring has no records for the last $Days day(s), so failed runs aren't counted. Turn it on under Sentinel's Settings." }) }
    $headline = if (-not $rules.Count) { "No analytics rules match on $($read.Name)." }
    else { "$($rules.Count) analytics rule(s), $($enabled.Count) enabled$(if ($failingRules.Count) { ", $($failingRules.Count) failing" }); the enabled rules cover $covered of $($coverage.Count) MITRE ATT&CK tactics" }
    $report = @{
        Subtitle = 'Microsoft Sentinel analytics rules: what detects what, what fails, and what is noisy'
        Facts    = [ordered]@{ Workspace = "$($read.Name) ($($read.ResourceGroup))"; Period = "last $Days day(s)" }
        Status   = $(if ($failingRules.Count) { 'Failed' } elseif ($outdated.Count -or $noisy.Count) { 'Warning' } else { 'Success' })
        Headline = $headline
        Tiles    = @(
            @{ Value = '{0:N0}' -f $rules.Count; Label = 'rules'; Tone = 'info'; Table = 'rules' }
            @{ Value = '{0:N0}' -f $enabled.Count; Label = 'enabled'; Tone = 'good'; Table = 'rules'; Filters = @{ State = 'Enabled' } }
            @{ Value = '{0:N0}' -f ($rules.Count - $enabled.Count); Label = 'disabled'; Tone = 'neutral'; Table = 'rules'; Filters = @{ State = 'Disabled' } }
            @{ Value = '{0:N0}' -f $failingRules.Count; Label = 'enabled, failing'; Tone = $(if ($failingRules.Count) { 'bad' } else { 'good' }) }
            @{ Value = '{0:N0}' -f $outdated.Count; Label = 'newer template'; Tone = $(if ($outdated.Count) { 'warn' } else { 'good' }) }
            @{ Value = "$covered/$($coverage.Count)"; Label = 'MITRE tactics covered'; Tone = $(if ($coverage.Count -and $covered -lt $coverage.Count) { 'warn' } else { 'good' }); Table = 'coverage' }
        )
        Notices  = @($notices)
        Charts   = @(
            @{ Title = 'Enabled rules by MITRE ATT&CK tactic'; Items = @($coverage | ForEach-Object { @{ Label = $_.Tactic; Value = $_.EnabledRules } }); Tone = 'info'; Console = $true }
            @{ Title = 'Rules by kind'; Kind = 'donut'; CenterLabel = 'rules'; Items = @($rules | Group-Object Kind | Sort-Object Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'rules'; Column = 'Kind' }
            @{ Title = 'Rules by severity'; Kind = 'donut'; CenterLabel = 'rules'; Items = @(foreach ($s in 'High', 'Medium', 'Low', 'Informational') { $n = @($rules | Where-Object Severity -EQ $s).Count; if ($n) { @{ Label = $s; Value = $n; Tone = $severityTones[$s]; Filter = $s } } }); Table = 'rules'; Column = 'Severity' }
            @{ Title = "Most incidents (last $Days days)"; Items = @($rules | Where-Object Incidents -GT 0 | Sort-Object Incidents -Descending | Select-AACFirst 10 | ForEach-Object { @{ Label = $_.Name; Value = $_.Incidents; Filter = $_.Name } }); Table = 'rules'; Column = 'Name'; Tone = 'warn'; Console = $true }
        )
        Tables   = @(
            @{ Id = 'rules'; Title = 'Analytics rules'; Section = 'Rules'; Rows = $rows; Noun = 'rules'; File = 'sentinel-analytics-rules'; GroupBy = @('State', 'Kind', 'Severity', 'Tactics'); ConsoleLimit = 30
                Empty = 'No analytics rules match.'; EmptyStatus = 'Info'; Hover = @('Query'); HoverTitle = 'Name'
                Columns = @(
                    @{ Key = 'Name'; Label = 'Rule'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'State'; Label = 'State'; Type = 'badge'; Tones = @{ Enabled = 'good'; Disabled = 'neutral' }; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Kind'; Label = 'Kind'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $severityTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Failures'; Label = 'Failures'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'Incidents'; Label = 'Incidents'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'FalsePositives'; Label = 'False positives'; Type = 'number' }
                    @{ Key = 'Tactics'; Label = 'Tactics'; Facet = $true }
                    @{ Key = 'Techniques'; Label = 'Techniques'; Type = 'mono' }
                    @{ Key = 'Frequency'; Label = 'Every'; Type = 'mono' }
                    @{ Key = 'Period'; Label = 'Looks back'; Type = 'mono' }
                    @{ Key = 'CreatesIncident'; Label = 'Creates incidents'; Facet = $true }
                    @{ Key = 'TemplateUpdate'; Label = 'Template update'; Pdf = $true }
                    @{ Key = 'LastFailure'; Label = 'Last failure'; Type = 'datetime' }
                    @{ Key = 'LastModified'; Label = 'Last modified'; Type = 'datetime'; Hidden = $true }
                    @{ Key = 'TemplateId'; Label = 'Template'; Type = 'mono'; Hidden = $true }
                    @{ Key = 'RuleId'; Label = 'Rule ID'; Type = 'mono'; Hidden = $true }
                    @{ Key = 'Query'; Label = 'KQL'; Type = 'wide'; Hidden = $true }
                ) }
            @{ Id = 'coverage'; Title = 'MITRE ATT&CK coverage'; Section = 'Coverage'; Rows = $coverage; Noun = 'tactics'; ConsoleLimit = 14; NoConsole = $true
                Note = 'Only the tactics each rule declares are counted.'
                Columns = @(
                    @{ Key = 'Tactic'; Label = 'Tactic'; Pdf = $true }
                    @{ Key = 'EnabledRules'; Label = 'Enabled rules'; Type = 'number'; Pdf = $true }
                    @{ Key = 'DisabledRules'; Label = 'Disabled rules'; Type = 'number'; Pdf = $true }
                ) }
        )
        Hint     = '-State, -Kind, -Severity, -Tactic, -Failing and -TemplateUpdate narrow the list; Export-AACSentinelAnalyticsRule backs the rules up as ARM templates.'
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $rows -Noun 'analytics rule' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $rules -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
