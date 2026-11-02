function ConvertTo-AACSentinelReport {
    <#
    .SYNOPSIS
        Turns Invoke-AACSentinelAssessment's result into the report model
        Invoke-AACReportOutput writes - a tabbed HTML report and a PDF, a
        section each.
    .DESCRIPTION
        The Summary tab: the headline, tiles and charts. Then a tab per
        section asked for (-Section on the command): Recommendations,
        Analytics rules, Rule templates, Data connectors, Tables, Health,
        Incidents and Automation rules - each table searchable, filterable
        and downloadable as CSV in the HTML report; in the PDF, each section
        a bookmarked heading with its tables' key columns (marked Pdf).
        Without Sentinel on the workspace, only the recommendation has
        anything to show. Returns the report hashtable.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Assessment,

        [System.Collections.IDictionary] $Detail = [ordered]@{}
    )

    $stats = $Assessment.Stats
    $workspace = $Assessment.Workspace
    $enabled = $workspace.SentinelEnabled
    $section = @(if ($Assessment.Contains('Section')) { $Assessment.Section })
    $want = { param([string] $Name) (-not $section.Count -or $section -contains $Name) -and ($enabled -or $Name -eq 'Recommendations') }
    $severityTones = @{ High = 'bad'; Medium = 'warn'; Low = 'info'; Informational = 'neutral' }
    $connectorTones = @{ Connected = 'good'; Disconnected = 'warn'; Unknown = 'neutral' }
    $incidentTones = @{ New = 'warn'; Active = 'info'; Closed = 'good' }
    $automationTones = @{ Enabled = 'good'; Disabled = 'neutral'; Expired = 'warn' }

    $tiles = @(
        if (& $want 'AnalyticsRules') { @{ Value = "$($stats.EnabledRules) / $($stats.AnalyticsRules)"; Label = 'analytics rules enabled'; Tone = 'violet'; Table = 'rules' } }
        if (& $want 'AnalyticsRules') { @{ Value = "$($stats.TacticsCovered) / $($stats.TacticsTotal)"; Label = 'MITRE tactics covered'; Tone = $(if ($stats.TacticsCovered -lt $stats.TacticsTotal) { 'warn' } else { 'good' }); Table = 'tactics' } }
        if (& $want 'RuleTemplates') { @{ Value = '{0:N0}' -f $stats.TemplateCandidates; Label = 'templates to consider'; Tone = 'info'; Table = 'templates'; Filters = @{ Candidate = 'True' } } }
        if (& $want 'DataConnectors') { @{ Value = "$($stats.ConnectedConnectors) / $($stats.DataConnectors)"; Label = 'connectors connected'; Tone = 'info'; Table = 'connectors' } }
        if (& $want 'Tables') { @{ Value = '{0:N2} GB' -f $stats.BillableGB; Label = "billable, $($workspace.Days) days"; Tone = 'info'; Table = 'tables' } }
        if (& $want 'Health') { @{ Value = '{0:N0}' -f $stats.HealthFailures; Label = 'health failures'; Tone = $(if ($stats.HealthFailures) { 'bad' } else { 'good' }); Table = 'health' } }
        if (& $want 'Incidents') { @{ Value = '{0:N0}' -f $stats.OpenIncidents; Label = 'open incidents'; Tone = $(if ($stats.OpenIncidents) { 'warn' } else { 'good' }); Table = 'incidents' } }
        if (& $want 'AutomationRules') { @{ Value = "$($stats.EnabledAutomation) / $($stats.AutomationRules)"; Label = 'automation rules enabled'; Tone = 'violet'; Table = 'automation' } }
        if (& $want 'Recommendations') { @{ Value = '{0:N0}' -f $stats.High; Label = 'high recommendations'; Tone = $(if ($stats.High) { 'bad' } else { 'good' }); Table = 'recommendations'; Filters = @{ Severity = 'High' } } }
        if (& $want 'Recommendations') { @{ Value = '{0:N0}' -f ($stats.Medium + $stats.Low); Label = 'medium and low'; Tone = $(if ($stats.Medium) { 'warn' } else { 'neutral' }); Table = 'recommendations' } }
    )
    $charts = @(
        if (& $want 'Recommendations') { @{ Title = 'Recommendations'; Kind = 'donut'; CenterLabel = 'recommendations'; Table = 'recommendations'; Column = 'Severity'; Items = @($Assessment.Recommendations | Group-Object Severity | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Tone = $severityTones[$_.Name] } }) } }
        if (& $want 'AnalyticsRules') { @{ Title = 'Enabled rules per MITRE ATT&CK tactic'; Wide = $true; Tone = 'violet'; Format = 'N0'; Table = 'tactics'; Column = 'Tactic'; Items = @($Assessment.TacticCoverage | ForEach-Object { @{ Label = $_.Tactic; Value = $_.EnabledRules } }) } }
        if (& $want 'Incidents') { @{ Title = 'Incidents by severity'; Kind = 'donut'; CenterLabel = 'incidents'; Table = 'incidents'; Column = 'Severity'; Items = @($Assessment.Incidents | Group-Object Severity | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Tone = $severityTones[$_.Name] } }) } }
        if (& $want 'Tables') { @{ Title = 'Billable GB by table'; Wide = $true; Tone = 'info'; Format = 'N2'; Suffix = ' GB'; Table = 'tables'; Column = 'Table'; Items = @($Assessment.Tables | Where-Object BillableGB -GT 0 | Select-AACFirst 15 | ForEach-Object { @{ Label = $_.Table; Value = $_.BillableGB } }) } }
    )

    # Each table under its tab (Section); Pdf marks the columns the PDF prints.
    $tables = [System.Collections.Generic.List[object]]::new()
    $add = { param([string] $Name, [string] $Tab, [hashtable] $Table) if (& $want $Name) { $Table.Section = $Tab; $tables.Add($Table) } }
    & $add 'Recommendations' 'Recommendations' @{
        Id = 'recommendations'; Title = 'Recommendations'; Noun = 'recommendations'; File = 'sentinel-recommendations'; Rows = @($Assessment.Recommendations); GroupBy = @('Severity', 'Category')
        Hover = @('Detail', 'Action'); HoverTitle = 'Recommendation'
        Columns = @(
            @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $severityTones; Facet = $true; Pdf = $true }
            @{ Key = 'Category'; Label = 'Category'; Facet = $true; Pdf = $true }
            @{ Key = 'Recommendation'; Label = 'Recommendation'; Type = 'wide'; Pdf = $true }
            @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide' }
            @{ Key = 'Action'; Label = 'What to do'; Type = 'wide'; Pdf = $true }
            @{ Key = 'LearnMore'; Label = 'Learn more'; Type = 'link' }
        )
    }
    & $add 'AnalyticsRules' 'Analytics rules' @{
        Id = 'rules'; Title = 'Analytics rules'; Noun = 'rules'; File = 'sentinel-analytics-rules'; Rows = @($Assessment.AnalyticsRules); GroupBy = @('Kind', 'Severity', 'Enabled')
        Hover = @('Tactics', 'Techniques', 'Query'); HoverTitle = 'Name'
        Columns = @(
            @{ Key = 'Name'; Label = 'Rule'; Type = 'wide'; Pdf = $true }
            @{ Key = 'Kind'; Label = 'Kind'; Facet = $true; Pdf = $true }
            @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $severityTones; Facet = $true; Pdf = $true }
            @{ Key = 'Enabled'; Label = 'Enabled'; Facet = $true; Pdf = $true }
            @{ Key = 'Tactics'; Label = 'Tactics'; Type = 'wide'; Pdf = $true }
            @{ Key = 'Techniques'; Label = 'Techniques'; Hidden = $true }
            @{ Key = 'Frequency'; Label = 'Every'; Pdf = $true }
            @{ Key = 'Period'; Label = 'Looks back'; Hidden = $true }
            @{ Key = 'Failures'; Label = 'Failures'; Type = 'number'; Format = 'N0'; Sum = $true; Pdf = $true }
            @{ Key = 'LastFailure'; Label = 'Last failure'; Type = 'datetime'; Hidden = $true }
            @{ Key = 'Incidents'; Label = 'Incidents'; Type = 'number'; Format = 'N0'; Pdf = $true }
            @{ Key = 'FalsePositives'; Label = 'False positives'; Type = 'number'; Format = 'N0'; Pdf = $true }
            @{ Key = 'TemplateUpdate'; Label = 'Newer template'; Facet = $true }
            @{ Key = 'TemplateVersion'; Label = 'Template version'; Hidden = $true }
            @{ Key = 'LatestTemplate'; Label = 'Latest template'; Hidden = $true }
            @{ Key = 'LastModified'; Label = 'Last modified'; Type = 'datetime'; Hidden = $true }
            @{ Key = 'Query'; Label = 'Query'; Type = 'wide'; Hidden = $true }
        )
    }
    & $add 'AnalyticsRules' 'Analytics rules' @{
        Id = 'tactics'; Title = 'MITRE ATT&CK coverage'; Note = 'Counts only the tactics each rule declares.'; Noun = 'tactics'; File = 'sentinel-tactic-coverage'; Rows = @($Assessment.TacticCoverage)
        Columns = @(@{ Key = 'Tactic'; Label = 'Tactic'; Pdf = $true }, @{ Key = 'EnabledRules'; Label = 'Enabled rules'; Type = 'number'; Format = 'N0'; Pdf = $true }, @{ Key = 'DisabledRules'; Label = 'Disabled rules'; Type = 'number'; Format = 'N0'; Pdf = $true })
    }
    & $add 'RuleTemplates' 'Rule templates' @{
        Id = 'templates'; Title = 'Rule templates'; Note = 'Candidate: the data it needs is arriving and no rule uses it. Covers built-in templates and installed solutions.'; Noun = 'templates'; File = 'sentinel-rule-templates'; Rows = @($Assessment.RuleTemplates); GroupBy = @('Candidate', 'Kind', 'Severity')
        Hover = @('DataTypes', 'MissingData', 'Tactics'); HoverTitle = 'Name'
        Columns = @(
            @{ Key = 'Name'; Label = 'Template'; Type = 'wide'; Pdf = $true }
            @{ Key = 'Candidate'; Label = 'Candidate'; Facet = $true; Pdf = $true }
            @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $severityTones; Facet = $true; Pdf = $true }
            @{ Key = 'Kind'; Label = 'Kind'; Facet = $true; Pdf = $true }
            @{ Key = 'InUse'; Label = 'In use'; Facet = $true; Pdf = $true }
            @{ Key = 'DataAvailable'; Label = 'Data arriving'; Facet = $true }
            @{ Key = 'DataTypes'; Label = 'Needs'; Type = 'wide'; Pdf = $true }
            @{ Key = 'MissingData'; Label = 'Missing'; Type = 'wide' }
            @{ Key = 'Tactics'; Label = 'Tactics'; Type = 'wide'; Hidden = $true }
            @{ Key = 'Status'; Label = 'Status'; Facet = $true; Hidden = $true }
            @{ Key = 'Version'; Label = 'Version'; Hidden = $true }
        )
    }
    & $add 'DataConnectors' 'Data connectors' @{
        Id = 'connectors'; Title = 'Data connectors'; Note = 'Some sources send data without being listed here: the Tables tab shows what really arrives.'; Noun = 'connectors'; File = 'sentinel-data-connectors'; Rows = @($Assessment.DataConnectors); GroupBy = @('State', 'Kind')
        Columns = @(
            @{ Key = 'Name'; Label = 'Connector'; Pdf = $true }
            @{ Key = 'Kind'; Label = 'Kind'; Facet = $true; Pdf = $true }
            @{ Key = 'State'; Label = 'State'; Type = 'badge'; Tones = $connectorTones; Facet = $true; Pdf = $true }
            @{ Key = 'DataTypes'; Label = 'Data types'; Type = 'wide'; Pdf = $true }
            @{ Key = 'ConnectorId'; Label = 'Connector ID'; Type = 'mono'; Hidden = $true }
        )
    }
    & $add 'Tables' 'Tables' @{
        Id = 'tables'; Title = 'Tables and ingestion'; Note = 'Size from the Usage table over the period (GB = 10^9 bytes). Share is of billable data. Used by rules counts enabled rules that name the table.'; Noun = 'tables'; File = 'sentinel-tables'; Rows = @($Assessment.Tables); GroupBy = @('Plan', 'Type', 'Solution', 'Silent')
        Columns = @(
            @{ Key = 'Table'; Label = 'Table'; Type = 'mono'; Pdf = $true }
            @{ Key = 'BillableGB'; Label = 'Billable GB'; Type = 'number'; Format = 'N3'; Sum = $true; Pdf = $true }
            @{ Key = 'NonBillableGB'; Label = 'Free GB'; Type = 'number'; Format = 'N3'; Sum = $true; Pdf = $true }
            @{ Key = 'SharePercent'; Label = 'Share %'; Type = 'number'; Format = 'N1'; Pdf = $true }
            @{ Key = 'DailyAverageGB'; Label = 'GB per day'; Type = 'number'; Format = 'N3'; Sum = $true }
            @{ Key = 'UsedByRules'; Label = 'Used by rules'; Type = 'number'; Format = 'N0'; Pdf = $true }
            @{ Key = 'Plan'; Label = 'Plan'; Facet = $true; Pdf = $true }
            @{ Key = 'RetentionDays'; Label = 'Retention (days)'; Type = 'number'; Format = 'N0'; Pdf = $true }
            @{ Key = 'TotalRetentionDays'; Label = 'Total retention (days)'; Type = 'number'; Format = 'N0'; Hidden = $true }
            @{ Key = 'LastRecord'; Label = 'Last record'; Type = 'datetime'; Pdf = $true }
            @{ Key = 'Silent'; Label = 'Stopped'; Facet = $true }
            @{ Key = 'Type'; Label = 'Type'; Facet = $true }
            @{ Key = 'Solution'; Label = 'Solution'; Facet = $true; Hidden = $true }
        )
    }
    & $add 'Health' 'Health' @{
        Id = 'health'; Title = 'Health failures (_SentinelHealth)'; Note = 'Connector health is logged only for some connectors.'; Noun = 'failures'; File = 'sentinel-health-failures'; Rows = @($Assessment.HealthFailures); GroupBy = @('ResourceType', 'Operation')
        Hover = @('Reason'); HoverTitle = 'Resource'
        Columns = @(
            @{ Key = 'Resource'; Label = 'Resource'; Pdf = $true }
            @{ Key = 'ResourceType'; Label = 'Type'; Facet = $true; Pdf = $true }
            @{ Key = 'Operation'; Label = 'Operation'; Facet = $true; Pdf = $true }
            @{ Key = 'Failures'; Label = 'Failures'; Type = 'number'; Format = 'N0'; Sum = $true; Pdf = $true }
            @{ Key = 'Records'; Label = 'Records'; Type = 'number'; Format = 'N0'; Hidden = $true }
            @{ Key = 'LastFailure'; Label = 'Last failure'; Type = 'datetime'; Pdf = $true }
            @{ Key = 'Reason'; Label = 'Reason'; Type = 'wide'; Pdf = $true }
        )
    }
    & $add 'Incidents' 'Incidents' @{
        Id = 'incidents'; Title = 'Incidents'; Note = 'Created in the period. Hours to close needs the SecurityIncident table.'; Noun = 'incidents'; File = 'sentinel-incidents'; Rows = @($Assessment.Incidents); GroupBy = @('Severity', 'Status', 'Owner', 'Classification', 'Provider')
        Columns = @(
            @{ Key = 'Number'; Label = 'Number'; Pdf = $true }
            @{ Key = 'Title'; Label = 'Title'; Type = 'wide'; Pdf = $true }
            @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $severityTones; Facet = $true; Pdf = $true }
            @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = $incidentTones; Facet = $true; Pdf = $true }
            @{ Key = 'Owner'; Label = 'Owner'; Facet = $true; Pdf = $true }
            @{ Key = 'Classification'; Label = 'Classification'; Facet = $true; Pdf = $true }
            @{ Key = 'ClassificationReason'; Label = 'Reason'; Facet = $true; Hidden = $true }
            @{ Key = 'Created'; Label = 'Created'; Type = 'datetime'; Pdf = $true }
            @{ Key = 'Closed'; Label = 'Closed'; Type = 'datetime'; Hidden = $true }
            @{ Key = 'HoursToClose'; Label = 'Hours to close'; Type = 'number'; Format = 'N1'; Pdf = $true }
            @{ Key = 'HoursOpen'; Label = 'Hours open'; Type = 'number'; Format = 'N1' }
            @{ Key = 'Alerts'; Label = 'Alerts'; Type = 'number'; Format = 'N0'; Hidden = $true }
            @{ Key = 'Provider'; Label = 'Provider'; Facet = $true; Hidden = $true }
            @{ Key = 'Tactics'; Label = 'Tactics'; Hidden = $true }
            @{ Key = 'Url'; Label = 'Open'; Type = 'link' }
        )
    }
    & $add 'AutomationRules' 'Automation rules' @{
        Id = 'automation'; Title = 'Automation rules'; Noun = 'rules'; File = 'sentinel-automation-rules'; Rows = @($Assessment.AutomationRules); GroupBy = @('State', 'TriggersOn', 'TriggersWhen')
        Columns = @(
            @{ Key = 'Order'; Label = 'Order'; Type = 'number'; Format = 'N0'; Pdf = $true }
            @{ Key = 'Name'; Label = 'Rule'; Type = 'wide'; Pdf = $true }
            @{ Key = 'State'; Label = 'State'; Type = 'badge'; Tones = $automationTones; Facet = $true; Pdf = $true }
            @{ Key = 'TriggersOn'; Label = 'Triggers on'; Facet = $true; Pdf = $true }
            @{ Key = 'TriggersWhen'; Label = 'When'; Facet = $true; Pdf = $true }
            @{ Key = 'Conditions'; Label = 'Conditions'; Type = 'number'; Format = 'N0' }
            @{ Key = 'Actions'; Label = 'Actions'; Type = 'wide'; Pdf = $true }
            @{ Key = 'Expires'; Label = 'Expires'; Type = 'datetime'; Pdf = $true }
            @{ Key = 'LastModified'; Label = 'Last modified'; Type = 'datetime'; Hidden = $true }
            @{ Key = 'ModifiedBy'; Label = 'Modified by'; Hidden = $true }
        )
    }

    # The tabs, in reading order: what to fix first, then detections, then the data behind them, then operations.
    $tabs = @(
        if (& $want 'Recommendations') { @{ Name = 'Recommendations'; Badge = $stats.High; Tone = $(if ($stats.High) { 'bad' } elseif ($stats.Medium) { 'warn' } else { 'good' }); Note = 'What to change - reliability, coverage, operations - most severe first, with what to do and a link to learn more.' } }
        if (& $want 'AnalyticsRules') { @{ Name = 'Analytics rules'; Badge = $stats.AnalyticsRules; Tone = 'violet'; Note = 'Every analytics rule, failing rules first, and how the enabled ones cover the MITRE ATT&CK tactics.' } }
        if (& $want 'RuleTemplates') { @{ Name = 'Rule templates'; Badge = $stats.TemplateCandidates; Tone = 'info'; Note = 'The rule templates, with the ones worth enabling first: their data is arriving and no rule uses them.' } }
        if (& $want 'DataConnectors') { @{ Name = 'Data connectors'; Badge = $stats.DataConnectors; Tone = 'info'; Note = 'The data connectors the API lists, and whether each is connected.' } }
        if (& $want 'Tables') { @{ Name = 'Tables'; Badge = $stats.TablesWithData; Tone = 'info'; Note = 'Every table with data in the period: size, share of the bill, how many rules use it, plan, retention and last record.' } }
        if (& $want 'Health') { @{ Name = 'Health'; Badge = @($Assessment.HealthFailures).Count; Tone = $(if (@($Assessment.HealthFailures).Count) { 'warn' } else { 'good' }); Note = 'What _SentinelHealth reports as failed: rules, connectors and automation.' } }
        if (& $want 'Incidents') { @{ Name = 'Incidents'; Badge = $stats.OpenIncidents; Tone = $(if ($stats.OpenIncidents) { 'warn' } else { 'good' }); Note = "Incidents created in the last $($workspace.Days) day(s), newest first, with owner, classification and time to close." } }
        if (& $want 'AutomationRules') { @{ Name = 'Automation rules'; Badge = $stats.AutomationRules; Tone = 'violet'; Note = 'The automation rules in the order they run, with what starts them and what they do.' } }
    )

    $notices = @(
        foreach ($key in @($Assessment.Errors.Keys)) { @{ Status = 'Warning'; Text = "$key couldn't be read: $($Assessment.Errors[$key])" } }
        if ($enabled -and $Assessment.HealthState -in 'Off', 'NoRecords' -and (& $want 'Health')) { @{ Status = 'Info'; Text = 'No health records: health monitoring appears to be off.' } }
    )
    $facts = [ordered]@{}
    foreach ($key in $Detail.Keys) { $facts[$key] = $Detail[$key] }
    $facts['Generated'] = "$([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture)) UTC"
    $recommendationCounts = '{0:N0} high, {1:N0} medium and {2:N0} low recommendation(s)' -f $stats.High, $stats.Medium, $stats.Low
    @{
        Subtitle = "$($workspace.Name) - last $($workspace.Days) day(s)"
        Facts    = $facts
        Status   = $(if ($stats.High) { 'Failed' } elseif ($stats.Medium) { 'Warning' } else { 'Success' })
        Headline = $(if ($enabled) { "$($workspace.Name): $($stats.EnabledRules) of $($stats.AnalyticsRules) analytics rule(s) enabled; $($stats.OpenIncidents) open incident(s); $('{0:N2}' -f $stats.BillableGB) GB billable over $($workspace.Days) day(s); $recommendationCounts" } else { "$($workspace.Name): Microsoft Sentinel is not enabled on this workspace" })
        Tiles    = $tiles
        Charts   = $charts
        Tabs     = $tabs
        Tables   = $tables.ToArray()
        Notices  = $notices
    }
}
