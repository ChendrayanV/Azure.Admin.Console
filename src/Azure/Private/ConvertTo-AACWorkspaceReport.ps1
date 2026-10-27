function ConvertTo-AACWorkspaceReport {
    <#
    .SYNOPSIS
        Turns Invoke-AACLogAnalyticsWorkspaceAssessment's result into the
        report model Invoke-AACReportOutput writes - a tabbed HTML report and
        a PDF, a section each.
    .DESCRIPTION
        The Summary tab: the headline, tiles and charts. Then a tab per
        section asked for (-Section on the command): Recommendations,
        Tables, Settings, Usage, Health, Agents, Query audit, Data
        collection rules and Change log - each table searchable, filterable
        and downloadable as CSV in the HTML report; in the PDF, each section
        a bookmarked heading with its tables' key columns (marked Pdf).
        Returns the report hashtable.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Assessment,

        [System.Collections.IDictionary] $Detail = [ordered]@{}
    )

    $stats = $Assessment.Stats
    $insights = $Assessment.Insights
    $section = @(if ($Assessment.Contains('Section')) { $Assessment.Section })
    $want = { param([string] $Name) -not $section.Count -or $section -contains $Name }
    $severityTones = @{ High = 'bad'; Medium = 'warn'; Low = 'info' }
    $billingTones = @{ Billable = 'warn'; Both = 'warn'; 'Not billable' = 'good'; 'No data' = 'neutral' }
    $stateTones = @{ Healthy = 'good'; Unhealthy = 'warn'; 'Not reporting' = 'bad'; Unknown = 'neutral' }
    $levelTones = @{ Error = 'bad'; Warning = 'warn'; Info = 'info'; Informational = 'info' }
    $workspace = $Assessment.Workspace

    $tiles = @(
        @{ Value = '{0:N2} GB' -f $stats.BillableGB; Label = "billable, $($workspace.Days) days"; Tone = 'info'; Table = 'tables'; Filters = @{ Billing = 'Billable' } }
        @{ Value = '{0:N2} GB' -f $stats.AverageDailyGB; Label = 'billable per day'; Tone = 'info'; Table = 'daily' }
        @{ Value = '{0:N0}' -f $stats.BillableTables; Label = 'billable tables'; Tone = 'warn'; Table = 'tables'; Filters = @{ Billing = 'Billable' } }
        @{ Value = '{0:N0}' -f $stats.NonBillableTables; Label = 'not billable tables'; Tone = 'good'; Table = 'tables'; Filters = @{ Billing = 'Not billable' } }
        @{ Value = "$($stats.HealthyAgents) / $($stats.Agents)"; Label = 'agents healthy'; Tone = $(if ($stats.UnhealthyAgents) { 'warn' } else { 'good' }); Table = 'agents' }
        @{ Value = '{0:N0}' -f $stats.DataCollectionRules; Label = 'data collection rules'; Tone = 'violet'; Table = 'rules' }
        @{ Value = '{0:N0}' -f $stats.High; Label = 'high recommendations'; Tone = $(if ($stats.High) { 'bad' } else { 'good' }); Table = 'recommendations'; Filters = @{ Severity = 'High' } }
        @{ Value = '{0:N0}' -f ($stats.Medium + $stats.Low); Label = 'medium and low'; Tone = $(if ($stats.Medium) { 'warn' } else { 'neutral' }); Table = 'recommendations' }
    )
    $charts = @(
        @{ Title = 'Billable GB by table'; Wide = $true; Tone = 'info'; Format = 'N2'; Suffix = ' GB'; Table = 'tables'; Column = 'Table'; Items = @($Assessment.Tables | Where-Object BillableGB -GT 0 | Sort-Object BillableGB -Descending | Select-AACFirst 15 | ForEach-Object { @{ Label = $_.Table; Value = $_.BillableGB } }) }
        @{ Title = 'Recommendations'; Kind = 'donut'; CenterLabel = 'recommendations'; Table = 'recommendations'; Column = 'Severity'; Items = @($Assessment.Recommendations | Group-Object Severity | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Tone = $severityTones[$_.Name] } }) }
        @{ Title = 'Billable GB per day'; Wide = $true; Tone = 'info'; Format = 'N2'; Suffix = ' GB'; Items = @($insights.Usage.Daily | ForEach-Object { @{ Label = $_.Day.ToString('yyyy-MM-dd'); Value = $_.BillableGB } }) }
    )
    if (@($Assessment.Agents).Count) {
        $charts += @{ Title = 'Agents'; Kind = 'donut'; CenterLabel = 'computers'; Table = 'agents'; Column = 'State'; Items = @($Assessment.Agents | Group-Object State | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Tone = $stateTones[$_.Name] } }) }
    }

    # Each table under its tab (Section); Pdf marks the columns the PDF prints.
    $tables = [System.Collections.Generic.List[object]]::new()
    $add = { param([string] $Name, [string] $Tab, [hashtable] $Table) if (& $want $Name) { $Table.Section = $Tab; $tables.Add($Table) } }
    & $add 'Recommendations' 'Recommendations' @{
        Id = 'recommendations'; Title = 'Recommendations'; Noun = 'recommendations'; File = 'workspace-recommendations'; Rows = @($Assessment.Recommendations); GroupBy = @('Severity', 'Category', 'Source')
        Hover = @('Detail', 'Action', 'Source'); HoverTitle = 'Recommendation'
        Columns = @(
            @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $severityTones; Facet = $true; Pdf = $true }
            @{ Key = 'Category'; Label = 'Category'; Facet = $true; Pdf = $true }
            @{ Key = 'Recommendation'; Label = 'Recommendation'; Type = 'wide'; Pdf = $true }
            @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide' }
            @{ Key = 'Action'; Label = 'What to do'; Type = 'wide'; Pdf = $true }
            @{ Key = 'Source'; Label = 'Source'; Facet = $true }
            @{ Key = 'LearnMore'; Label = 'Learn more'; Type = 'link' }
        )
    }
    & $add 'Tables' 'Tables' @{
        Id = 'tables'; Title = 'Tables'; Note = 'Size from the Usage table over the period (GB = 10^9 bytes). Share is of billable data.'; Noun = 'tables'; File = 'workspace-tables'; Rows = @($Assessment.Tables); GroupBy = @('Billing', 'Plan', 'Type', 'Solution')
        Sort = @{ Key = 'TotalGB'; Desc = $true }
        Columns = @(
            @{ Key = 'Table'; Label = 'Table'; Type = 'mono'; Pdf = $true }
            @{ Key = 'Billing'; Label = 'Billing'; Type = 'badge'; Tones = $billingTones; Facet = $true; Pdf = $true }
            @{ Key = 'BillableGB'; Label = 'Billable GB'; Type = 'number'; Format = 'N3'; Sum = $true; Pdf = $true }
            @{ Key = 'NonBillableGB'; Label = 'Free GB'; Type = 'number'; Format = 'N3'; Sum = $true; Pdf = $true }
            @{ Key = 'SharePercent'; Label = 'Share %'; Type = 'number'; Format = 'N1'; Pdf = $true }
            @{ Key = 'DailyAverageGB'; Label = 'GB per day'; Type = 'number'; Format = 'N3'; Sum = $true; Pdf = $true }
            @{ Key = 'Plan'; Label = 'Plan'; Facet = $true; Pdf = $true }
            @{ Key = 'RetentionDays'; Label = 'Retention (days)'; Type = 'number'; Format = 'N0'; Pdf = $true }
            @{ Key = 'TotalRetentionDays'; Label = 'Total retention (days)'; Type = 'number'; Format = 'N0' }
            @{ Key = 'LastRecord'; Label = 'Last record'; Type = 'datetime' }
            @{ Key = 'Type'; Label = 'Type'; Facet = $true }
            @{ Key = 'Solution'; Label = 'Solution'; Facet = $true; Hidden = $true }
            @{ Key = 'SubType'; Label = 'Subtype'; Facet = $true; Hidden = $true }
        )
    }
    & $add 'Settings' 'Settings' @{
        Id = 'settings'; Title = 'Workspace settings'; Noun = 'settings'; File = 'workspace-settings'; Rows = @($Assessment.Settings); GroupBy = @('Category'); Group = 'Category'; PageSize = 500
        Columns = @(@{ Key = 'Category'; Label = 'Category'; Facet = $true; Pdf = $true }, @{ Key = 'Setting'; Label = 'Setting'; Pdf = $true }, @{ Key = 'Value'; Label = 'Value'; Type = 'wide'; Pdf = $true })
    }
    & $add 'Usage' 'Usage' @{
        Id = 'daily'; Title = 'Ingestion per day'; Noun = 'days'; File = 'workspace-daily-ingestion'; Rows = @($insights.Usage.Daily)
        Columns = @(@{ Key = 'Day'; Label = 'Day'; Type = 'date'; Pdf = $true }, @{ Key = 'BillableGB'; Label = 'Billable GB'; Type = 'number'; Format = 'N3'; Sum = $true; Pdf = $true }, @{ Key = 'NonBillableGB'; Label = 'Free GB'; Type = 'number'; Format = 'N3'; Sum = $true; Pdf = $true })
    }
    & $add 'Usage' 'Usage' @{
        Id = 'solutions'; Title = 'By solution'; Noun = 'solutions'; File = 'workspace-solutions'; Rows = @($insights.Usage.Solutions)
        Columns = @(@{ Key = 'Solution'; Label = 'Solution'; Pdf = $true }, @{ Key = 'BillableGB'; Label = 'Billable GB'; Type = 'number'; Format = 'N3'; Sum = $true; Pdf = $true }, @{ Key = 'NonBillableGB'; Label = 'Free GB'; Type = 'number'; Format = 'N3'; Sum = $true; Pdf = $true })
    }
    & $add 'Usage' 'Usage' @{
        Id = 'resources'; Title = 'By Azure resource, last 24 hours'; Noun = 'resources'; File = 'workspace-resources'; Rows = @($insights.Usage.Resources)
        Columns = @(@{ Key = 'Resource'; Label = 'Resource'; Type = 'resource'; IdKey = 'ResourceId'; Pdf = $true }, @{ Key = 'BillableGB'; Label = 'Billable GB'; Type = 'number'; Format = 'N3'; Sum = $true; Pdf = $true })
    }
    & $add 'Usage' 'Usage' @{
        Id = 'computers'; Title = 'By computer, last 24 hours'; Noun = 'computers'; File = 'workspace-computers'; Rows = @($insights.Usage.Computers)
        Columns = @(@{ Key = 'Computer'; Label = 'Computer'; Pdf = $true }, @{ Key = 'BillableGB'; Label = 'Billable GB'; Type = 'number'; Format = 'N3'; Sum = $true; Pdf = $true })
    }
    & $add 'Health' 'Health' @{
        Id = 'operations'; Title = 'Operations (_LogOperation)'; Noun = 'operations'; File = 'workspace-operations'; Rows = @($insights.Health.Operations); GroupBy = @('Level', 'Category', 'Operation')
        Hover = @('Detail', 'FirstSeen', 'LastSeen'); HoverTitle = 'Operation'
        Columns = @(
            @{ Key = 'Level'; Label = 'Level'; Type = 'badge'; Tones = $levelTones; Facet = $true; Pdf = $true }
            @{ Key = 'Category'; Label = 'Category'; Facet = $true; Pdf = $true }
            @{ Key = 'Operation'; Label = 'Operation'; Facet = $true; Pdf = $true }
            @{ Key = 'Count'; Label = 'Count'; Type = 'number'; Format = 'N0'; Sum = $true; Pdf = $true }
            @{ Key = 'FirstSeen'; Label = 'First seen'; Type = 'datetime' }
            @{ Key = 'LastSeen'; Label = 'Last seen'; Type = 'datetime'; Pdf = $true }
            @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide'; Pdf = $true }
        )
    }
    & $add 'Health' 'Health' @{
        Id = 'latency'; Title = 'Heartbeat ingestion latency, last 24 hours'; Noun = 'agent types'; File = 'workspace-latency'; Rows = @($insights.Health.Latency)
        Columns = @(@{ Key = 'AgentType'; Label = 'Agent'; Pdf = $true }, @{ Key = 'Records'; Label = 'Records'; Type = 'number'; Format = 'N0'; Pdf = $true }, @{ Key = 'P50Seconds'; Label = 'Median (s)'; Type = 'number'; Format = 'N1'; Pdf = $true }, @{ Key = 'P95Seconds'; Label = '95th percentile (s)'; Type = 'number'; Format = 'N1'; Pdf = $true }, @{ Key = 'MaxSeconds'; Label = 'Max (s)'; Type = 'number'; Format = 'N1'; Pdf = $true })
    }
    & $add 'Agents' 'Agents' @{
        Id = 'agents'; Title = 'Agents'; Noun = 'computers'; File = 'workspace-agents'; Rows = @($Assessment.Agents); GroupBy = @('State', 'AgentType', 'OSType', 'Environment')
        Columns = @(
            @{ Key = 'Computer'; Label = 'Computer'; Pdf = $true }
            @{ Key = 'State'; Label = 'State'; Type = 'badge'; Tones = $stateTones; Facet = $true; Pdf = $true }
            @{ Key = 'LastHeartbeat'; Label = 'Last heartbeat'; Type = 'datetime'; Pdf = $true }
            @{ Key = 'AgentType'; Label = 'Agent'; Facet = $true; Pdf = $true }
            @{ Key = 'Version'; Label = 'Version'; Facet = $true; Pdf = $true }
            @{ Key = 'OSType'; Label = 'OS'; Facet = $true; Pdf = $true }
            @{ Key = 'OSName'; Label = 'OS name'; Hidden = $true }
            @{ Key = 'Environment'; Label = 'Environment'; Facet = $true; Pdf = $true }
            @{ Key = 'ResourceId'; Label = 'Resource ID'; Type = 'mono'; Hidden = $true }
        )
    }
    & $add 'QueryAudit' 'Query audit' @{
        Id = 'auditUsers'; Title = 'By user and app'; Noun = 'users'; File = 'workspace-query-users'; Rows = @($insights.QueryAudit.Users); GroupBy = @('User', 'ClientApp')
        Columns = @(@{ Key = 'User'; Label = 'User'; Pdf = $true }, @{ Key = 'ClientApp'; Label = 'App'; Facet = $true; Pdf = $true }, @{ Key = 'Queries'; Label = 'Queries'; Type = 'number'; Format = 'N0'; Sum = $true; Pdf = $true }, @{ Key = 'Failed'; Label = 'Failed'; Type = 'number'; Format = 'N0'; Sum = $true; Pdf = $true }, @{ Key = 'AvgDurationMs'; Label = 'Avg ms'; Type = 'number'; Format = 'N0'; Pdf = $true }, @{ Key = 'MaxDurationMs'; Label = 'Max ms'; Type = 'number'; Format = 'N0'; Pdf = $true }, @{ Key = 'CpuSeconds'; Label = 'CPU s'; Type = 'number'; Format = 'N1'; Sum = $true; Pdf = $true }, @{ Key = 'RowsReturned'; Label = 'Rows'; Type = 'number'; Format = 'N0'; Hidden = $true })
    }
    & $add 'QueryAudit' 'Query audit' @{
        Id = 'auditSlowest'; Title = 'Slowest queries'; Noun = 'queries'; File = 'workspace-slowest-queries'; Rows = @($insights.QueryAudit.Slowest)
        Hover = @('Query'); HoverTitle = 'User'
        Columns = @(@{ Key = 'Time'; Label = 'When'; Type = 'datetime'; Pdf = $true }, @{ Key = 'User'; Label = 'User'; Facet = $true; Pdf = $true }, @{ Key = 'ClientApp'; Label = 'App'; Facet = $true; Pdf = $true }, @{ Key = 'ResponseCode'; Label = 'Code'; Pdf = $true }, @{ Key = 'DurationMs'; Label = 'ms'; Type = 'number'; Format = 'N0'; Pdf = $true }, @{ Key = 'CpuMs'; Label = 'CPU ms'; Type = 'number'; Format = 'N0' }, @{ Key = 'Query'; Label = 'Query'; Type = 'wide'; Pdf = $true })
    }
    & $add 'QueryAudit' 'Query audit' @{
        Id = 'auditFailed'; Title = 'Failed queries'; Noun = 'failures'; File = 'workspace-failed-queries'; Rows = @($insights.QueryAudit.Failed)
        Columns = @(@{ Key = 'ResponseCode'; Label = 'Code'; Facet = $true; Pdf = $true }, @{ Key = 'User'; Label = 'User'; Facet = $true; Pdf = $true }, @{ Key = 'ClientApp'; Label = 'App'; Facet = $true; Pdf = $true }, @{ Key = 'Count'; Label = 'Count'; Type = 'number'; Format = 'N0'; Sum = $true; Pdf = $true }, @{ Key = 'LastSeen'; Label = 'Last seen'; Type = 'datetime'; Pdf = $true })
    }
    & $add 'DataCollectionRules' 'Data collection rules' @{
        Id = 'rules'; Title = 'Data collection rules sending to this workspace'; Noun = 'rules'; File = 'workspace-data-collection-rules'; Rows = @($Assessment.DataCollectionRules); GroupBy = @('Kind', 'ResourceGroup')
        Hover = @('DataSources', 'Streams', 'OutputTables', 'AssociatedResources', 'Description'); HoverTitle = 'Name'
        Columns = @(
            @{ Key = 'Name'; Label = 'Rule'; Type = 'resource'; IdKey = 'ResourceId'; Pdf = $true }
            @{ Key = 'Kind'; Label = 'Kind'; Facet = $true; Pdf = $true }
            @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true; Pdf = $true }
            @{ Key = 'WorkspaceTransform'; Label = 'Workspace transformation'; Facet = $true; Pdf = $true }
            @{ Key = 'DataSources'; Label = 'Data sources'; Type = 'wide'; Pdf = $true }
            @{ Key = 'Streams'; Label = 'Streams'; Type = 'wide' }
            @{ Key = 'OutputTables'; Label = 'Output tables'; Type = 'wide'; Pdf = $true }
            @{ Key = 'Transformations'; Label = 'Transformations'; Type = 'number'; Format = 'N0' }
            @{ Key = 'Associations'; Label = 'Associations'; Type = 'number'; Format = 'N0'; Sum = $true; Pdf = $true }
            @{ Key = 'AssociatedResources'; Label = 'Associated with'; Type = 'wide' }
            @{ Key = 'Endpoint'; Label = 'Endpoint'; Hidden = $true }
            @{ Key = 'Description'; Label = 'Description'; Type = 'wide'; Hidden = $true }
        )
    }
    & $add 'ChangeLog' 'Change log' @{
        Id = 'changes'; Title = 'Change log (activity log)'; Noun = 'changes'; File = 'workspace-change-log'; Rows = @($Assessment.ChangeLog); GroupBy = @('Operation', 'Caller', 'Status')
        Sort = @{ Key = 'Time'; Desc = $true }
        Columns = @(
            @{ Key = 'Time'; Label = 'When'; Type = 'datetime'; Pdf = $true }
            @{ Key = 'Operation'; Label = 'Operation'; Facet = $true; Pdf = $true }
            @{ Key = 'Resource'; Label = 'On'; Type = 'mono'; Pdf = $true }
            @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = @{ Succeeded = 'good'; Failed = 'bad' }; Facet = $true; Pdf = $true }
            @{ Key = 'Caller'; Label = 'By'; Facet = $true; Pdf = $true }
            @{ Key = 'Detail'; Label = 'Detail'; Hidden = $true }
            @{ Key = 'Action'; Label = 'Action'; Type = 'mono'; Hidden = $true }
        )
    }

    # The tabs, in reading order: what to fix first, then where the data and money go, then how the workspace runs.
    $count = { param([string] $Id) $t = @($tables | Where-Object { $_.Id -eq $Id }) | Select-Object -First 1; if ($t) { @($t.Rows).Count } else { $null } }
    $tabs = @(
        if (& $want 'Recommendations') { @{ Name = 'Recommendations'; Badge = $stats.High; Tone = $(if ($stats.High) { 'bad' } elseif ($stats.Medium) { 'warn' } else { 'good' }); Note = 'What to change in the workspace - cost, retention, security, reliability - most severe first, with what to do and a link to learn more.' } }
        if (& $want 'Tables') { @{ Name = 'Tables'; Badge = & $count 'tables'; Tone = 'info'; Note = 'Every table with data in the period - billable and not - with its size, share of the bill, plan and retention.' } }
        if (& $want 'Settings') { @{ Name = 'Settings'; Badge = & $count 'settings'; Tone = 'neutral'; Note = 'The workspace''s configuration by area: pricing, retention, access, network, data exports, linked services and storage, diagnostics.' } }
        if (& $want 'Usage') { @{ Name = 'Usage'; Badge = $null; Tone = 'info'; Note = 'Where the data comes from: ingestion per day, by solution, and the Azure resources and computers that sent the most in the last 24 hours.' } }
        if (& $want 'Health') { @{ Name = 'Health'; Badge = @($insights.Health.Operations | Where-Object { $_.Level -in 'Error', 'Warning' }).Count; Tone = 'warn'; Note = 'The workspace''s own operational issues (_LogOperation) and how long heartbeats take to arrive.' } }
        if (& $want 'Agents') { @{ Name = 'Agents'; Badge = $stats.UnhealthyAgents; Tone = $(if ($stats.UnhealthyAgents) { 'warn' } else { 'good' }); Note = 'Each computer that reports to the workspace: its state from its last heartbeat, agent type and version, OS and environment.' } }
        if (& $want 'QueryAudit') { @{ Name = 'Query audit'; Badge = & $count 'auditFailed'; Tone = 'warn'; Note = 'Who queries the workspace and with what (LAQueryLogs, when query auditing is on): the slowest and the failed queries.' } }
        if (& $want 'DataCollectionRules') { @{ Name = 'Data collection rules'; Badge = $stats.DataCollectionRules; Tone = 'violet'; Note = 'The data collection rules that send to the workspace: their data sources, streams, transformations and what they are associated with.' } }
        if (& $want 'ChangeLog') { @{ Name = 'Change log'; Badge = & $count 'changes'; Tone = 'neutral'; Note = "Changes to the workspace from the activity log, last $($workspace.Days) day(s): what, by whom, and whether it worked." } }
    )

    $notices = @(
        foreach ($text in @($Assessment.Notices)) { @{ Status = 'Info'; Text = $text } }
        foreach ($key in @($Assessment.Errors.Keys)) { @{ Status = 'Warning'; Text = "$($key -replace '^\w+:', '') couldn't be read: $($Assessment.Errors[$key])" } }
    )
    $facts = [ordered]@{}
    foreach ($key in $Detail.Keys) { $facts[$key] = $Detail[$key] }
    $facts['Pricing tier'] = "$($workspace.PricingTier)$(if ($workspace.CommitmentTierGB) { " ($($workspace.CommitmentTierGB) GB/day)" })"
    $facts['Retention'] = "$($workspace.RetentionDays) days"
    $facts['Generated'] = "$([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture)) UTC"
    @{
        Subtitle = "$($workspace.Name) - $($workspace.PricingTier)$(if ($workspace.CommitmentTierGB) { " $($workspace.CommitmentTierGB) GB/day" }), $($workspace.RetentionDays)-day retention, last $($workspace.Days) day(s)"
        Facts    = $facts
        Status   = $(if ($stats.High) { 'Failed' } elseif ($stats.Medium) { 'Warning' } else { 'Success' })
        Headline = ('{0}: {1:N2} GB billable over {2} day(s) ({3:N2} GB a day) in {4:N0} billable table(s); {5} of {6} agent(s) healthy; {7:N0} high, {8:N0} medium and {9:N0} low recommendation(s)' -f $workspace.Name, $stats.BillableGB, $workspace.Days, $stats.AverageDailyGB, $stats.BillableTables, $stats.HealthyAgents, $stats.Agents, $stats.High, $stats.Medium, $stats.Low)
        Tiles    = $tiles
        Charts   = $charts
        Tabs     = $tabs
        Tables   = $tables.ToArray()
        Notices  = $notices
    }
}
