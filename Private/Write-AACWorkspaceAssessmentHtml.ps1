function Write-AACWorkspaceAssessmentHtml {
    <#
    .SYNOPSIS
        Writes Invoke-AACLogAnalyticsWorkspaceAssessment's result as an
        interactive HTML report: tiles and charts over tables of the
        recommendations, the tables (billable and not), the settings and
        each Workspace Insights tab.
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

    $stats = $Assessment.Stats
    $insights = $Assessment.Insights
    $section = @(if ($Assessment.Contains('Section')) { $Assessment.Section })
    $want = { param([string] $Name) -not $section.Count -or $section -contains $Name }
    $severityTones = @{ High = 'bad'; Medium = 'warn'; Low = 'info' }
    $billingTones = @{ Billable = 'warn'; Both = 'warn'; 'Not billable' = 'good'; 'No data' = 'neutral' }
    $stateTones = @{ Healthy = 'good'; Unhealthy = 'warn'; 'Not reporting' = 'bad'; Unknown = 'neutral' }
    $levelTones = @{ Error = 'bad'; Warning = 'warn'; Info = 'info'; Informational = 'info' }

    $tiles = @(
        @{ Value = '{0:N2} GB' -f $stats.BillableGB; Label = "billable, $($Assessment.Workspace.Days) days"; Tone = 'info'; Table = 'tables'; Filters = @{ Billing = 'Billable' } }
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

    $tables = [System.Collections.Generic.List[object]]::new()
    $add = { param([string] $Name, [hashtable] $Table) if (& $want $Name) { $tables.Add($Table) } }
    & $add 'Recommendations' @{
        Id = 'recommendations'; Title = 'Recommendations'; Noun = 'recommendations'; File = 'workspace-recommendations'; Rows = @($Assessment.Recommendations); GroupBy = @('Severity', 'Category', 'Source')
        Columns = @(
            @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $severityTones; Facet = $true }
            @{ Key = 'Category'; Label = 'Category'; Facet = $true }
            @{ Key = 'Recommendation'; Label = 'Recommendation'; Type = 'wide' }
            @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide' }
            @{ Key = 'Action'; Label = 'What to do'; Type = 'wide' }
            @{ Key = 'Source'; Label = 'Source'; Facet = $true }
            @{ Key = 'LearnMore'; Label = 'Learn more'; Type = 'link' }
        )
    }
    & $add 'Tables' @{
        Id = 'tables'; Title = 'Tables'; Note = 'Size from the Usage table over the period (GB = 10^9 bytes). Share is of billable data.'; Noun = 'tables'; File = 'workspace-tables'; Rows = @($Assessment.Tables); GroupBy = @('Billing', 'Plan', 'Type', 'Solution')
        Sort = @{ Key = 'TotalGB'; Desc = $true }
        Columns = @(
            @{ Key = 'Table'; Label = 'Table'; Type = 'mono' }
            @{ Key = 'Billing'; Label = 'Billing'; Type = 'badge'; Tones = $billingTones; Facet = $true }
            @{ Key = 'BillableGB'; Label = 'Billable GB'; Type = 'number'; Format = 'N3'; Sum = $true }
            @{ Key = 'NonBillableGB'; Label = 'Free GB'; Type = 'number'; Format = 'N3'; Sum = $true }
            @{ Key = 'SharePercent'; Label = 'Share %'; Type = 'number'; Format = 'N1' }
            @{ Key = 'DailyAverageGB'; Label = 'GB per day'; Type = 'number'; Format = 'N3'; Sum = $true }
            @{ Key = 'Plan'; Label = 'Plan'; Facet = $true }
            @{ Key = 'RetentionDays'; Label = 'Retention (days)'; Type = 'number'; Format = 'N0' }
            @{ Key = 'TotalRetentionDays'; Label = 'Total retention (days)'; Type = 'number'; Format = 'N0' }
            @{ Key = 'LastRecord'; Label = 'Last record'; Type = 'datetime' }
            @{ Key = 'Type'; Label = 'Type'; Facet = $true }
            @{ Key = 'Solution'; Label = 'Solution'; Facet = $true; Hidden = $true }
            @{ Key = 'SubType'; Label = 'Subtype'; Facet = $true; Hidden = $true }
        )
    }
    & $add 'Settings' @{
        Id = 'settings'; Title = 'Workspace settings'; Noun = 'settings'; File = 'workspace-settings'; Rows = @($Assessment.Settings); GroupBy = @('Category'); Group = 'Category'; PageSize = 500
        Columns = @(@{ Key = 'Category'; Label = 'Category'; Facet = $true }, @{ Key = 'Setting'; Label = 'Setting' }, @{ Key = 'Value'; Label = 'Value'; Type = 'wide' })
    }
    & $add 'Usage' @{
        Id = 'daily'; Title = 'Usage: ingestion per day'; Noun = 'days'; File = 'workspace-daily-ingestion'; Rows = @($insights.Usage.Daily)
        Columns = @(@{ Key = 'Day'; Label = 'Day'; Type = 'date' }, @{ Key = 'BillableGB'; Label = 'Billable GB'; Type = 'number'; Format = 'N3'; Sum = $true }, @{ Key = 'NonBillableGB'; Label = 'Free GB'; Type = 'number'; Format = 'N3'; Sum = $true })
    }
    & $add 'Usage' @{
        Id = 'solutions'; Title = 'Usage: by solution'; Noun = 'solutions'; File = 'workspace-solutions'; Rows = @($insights.Usage.Solutions)
        Columns = @(@{ Key = 'Solution'; Label = 'Solution' }, @{ Key = 'BillableGB'; Label = 'Billable GB'; Type = 'number'; Format = 'N3'; Sum = $true }, @{ Key = 'NonBillableGB'; Label = 'Free GB'; Type = 'number'; Format = 'N3'; Sum = $true })
    }
    & $add 'Usage' @{
        Id = 'resources'; Title = 'Usage: by Azure resource, last 24 hours'; Noun = 'resources'; File = 'workspace-resources'; Rows = @($insights.Usage.Resources)
        Columns = @(@{ Key = 'Resource'; Label = 'Resource'; Type = 'resource'; IdKey = 'ResourceId' }, @{ Key = 'BillableGB'; Label = 'Billable GB'; Type = 'number'; Format = 'N3'; Sum = $true })
    }
    & $add 'Usage' @{
        Id = 'computers'; Title = 'Usage: by computer, last 24 hours'; Noun = 'computers'; File = 'workspace-computers'; Rows = @($insights.Usage.Computers)
        Columns = @(@{ Key = 'Computer'; Label = 'Computer' }, @{ Key = 'BillableGB'; Label = 'Billable GB'; Type = 'number'; Format = 'N3'; Sum = $true })
    }
    & $add 'Health' @{
        Id = 'operations'; Title = 'Health: operations (_LogOperation)'; Noun = 'operations'; File = 'workspace-operations'; Rows = @($insights.Health.Operations); GroupBy = @('Level', 'Category', 'Operation')
        Columns = @(
            @{ Key = 'Level'; Label = 'Level'; Type = 'badge'; Tones = $levelTones; Facet = $true }
            @{ Key = 'Category'; Label = 'Category'; Facet = $true }
            @{ Key = 'Operation'; Label = 'Operation'; Facet = $true }
            @{ Key = 'Count'; Label = 'Count'; Type = 'number'; Format = 'N0'; Sum = $true }
            @{ Key = 'FirstSeen'; Label = 'First seen'; Type = 'datetime' }
            @{ Key = 'LastSeen'; Label = 'Last seen'; Type = 'datetime' }
            @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide' }
        )
    }
    & $add 'Health' @{
        Id = 'latency'; Title = 'Health: heartbeat ingestion latency, last 24 hours'; Noun = 'agent types'; File = 'workspace-latency'; Rows = @($insights.Health.Latency)
        Columns = @(@{ Key = 'AgentType'; Label = 'Agent' }, @{ Key = 'Records'; Label = 'Records'; Type = 'number'; Format = 'N0' }, @{ Key = 'P50Seconds'; Label = 'Median (s)'; Type = 'number'; Format = 'N1' }, @{ Key = 'P95Seconds'; Label = '95th percentile (s)'; Type = 'number'; Format = 'N1' }, @{ Key = 'MaxSeconds'; Label = 'Max (s)'; Type = 'number'; Format = 'N1' })
    }
    & $add 'Agents' @{
        Id = 'agents'; Title = 'Agents'; Noun = 'computers'; File = 'workspace-agents'; Rows = @($Assessment.Agents); GroupBy = @('State', 'AgentType', 'OSType', 'Environment')
        Columns = @(
            @{ Key = 'Computer'; Label = 'Computer' }
            @{ Key = 'State'; Label = 'State'; Type = 'badge'; Tones = $stateTones; Facet = $true }
            @{ Key = 'LastHeartbeat'; Label = 'Last heartbeat'; Type = 'datetime' }
            @{ Key = 'AgentType'; Label = 'Agent'; Facet = $true }
            @{ Key = 'Version'; Label = 'Version'; Facet = $true }
            @{ Key = 'OSType'; Label = 'OS'; Facet = $true }
            @{ Key = 'OSName'; Label = 'OS name'; Hidden = $true }
            @{ Key = 'Environment'; Label = 'Environment'; Facet = $true }
            @{ Key = 'ResourceId'; Label = 'Resource ID'; Type = 'mono'; Hidden = $true }
        )
    }
    & $add 'QueryAudit' @{
        Id = 'auditUsers'; Title = 'Query audit: by user and app'; Noun = 'users'; File = 'workspace-query-users'; Rows = @($insights.QueryAudit.Users); GroupBy = @('User', 'ClientApp')
        Columns = @(@{ Key = 'User'; Label = 'User' }, @{ Key = 'ClientApp'; Label = 'App'; Facet = $true }, @{ Key = 'Queries'; Label = 'Queries'; Type = 'number'; Format = 'N0'; Sum = $true }, @{ Key = 'Failed'; Label = 'Failed'; Type = 'number'; Format = 'N0'; Sum = $true }, @{ Key = 'AvgDurationMs'; Label = 'Avg ms'; Type = 'number'; Format = 'N0' }, @{ Key = 'MaxDurationMs'; Label = 'Max ms'; Type = 'number'; Format = 'N0' }, @{ Key = 'CpuSeconds'; Label = 'CPU s'; Type = 'number'; Format = 'N1'; Sum = $true }, @{ Key = 'RowsReturned'; Label = 'Rows'; Type = 'number'; Format = 'N0'; Hidden = $true })
    }
    & $add 'QueryAudit' @{
        Id = 'auditSlowest'; Title = 'Query audit: slowest queries'; Noun = 'queries'; File = 'workspace-slowest-queries'; Rows = @($insights.QueryAudit.Slowest)
        Columns = @(@{ Key = 'Time'; Label = 'When'; Type = 'datetime' }, @{ Key = 'User'; Label = 'User'; Facet = $true }, @{ Key = 'ClientApp'; Label = 'App'; Facet = $true }, @{ Key = 'ResponseCode'; Label = 'Code' }, @{ Key = 'DurationMs'; Label = 'ms'; Type = 'number'; Format = 'N0' }, @{ Key = 'CpuMs'; Label = 'CPU ms'; Type = 'number'; Format = 'N0' }, @{ Key = 'Query'; Label = 'Query'; Type = 'wide' })
    }
    & $add 'QueryAudit' @{
        Id = 'auditFailed'; Title = 'Query audit: failed queries'; Noun = 'failures'; File = 'workspace-failed-queries'; Rows = @($insights.QueryAudit.Failed)
        Columns = @(@{ Key = 'ResponseCode'; Label = 'Code'; Facet = $true }, @{ Key = 'User'; Label = 'User'; Facet = $true }, @{ Key = 'ClientApp'; Label = 'App'; Facet = $true }, @{ Key = 'Count'; Label = 'Count'; Type = 'number'; Format = 'N0'; Sum = $true }, @{ Key = 'LastSeen'; Label = 'Last seen'; Type = 'datetime' })
    }
    & $add 'DataCollectionRules' @{
        Id = 'rules'; Title = 'Data collection rules sending to this workspace'; Noun = 'rules'; File = 'workspace-data-collection-rules'; Rows = @($Assessment.DataCollectionRules); GroupBy = @('Kind', 'ResourceGroup')
        Columns = @(
            @{ Key = 'Name'; Label = 'Rule'; Type = 'resource'; IdKey = 'ResourceId' }
            @{ Key = 'Kind'; Label = 'Kind'; Facet = $true }
            @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
            @{ Key = 'WorkspaceTransform'; Label = 'Workspace transformation'; Facet = $true }
            @{ Key = 'DataSources'; Label = 'Data sources'; Type = 'wide' }
            @{ Key = 'Streams'; Label = 'Streams'; Type = 'wide' }
            @{ Key = 'OutputTables'; Label = 'Output tables'; Type = 'wide' }
            @{ Key = 'Transformations'; Label = 'Transformations'; Type = 'number'; Format = 'N0' }
            @{ Key = 'Associations'; Label = 'Associations'; Type = 'number'; Format = 'N0'; Sum = $true }
            @{ Key = 'AssociatedResources'; Label = 'Associated with'; Type = 'wide' }
            @{ Key = 'Endpoint'; Label = 'Endpoint'; Hidden = $true }
            @{ Key = 'Description'; Label = 'Description'; Type = 'wide'; Hidden = $true }
        )
    }
    & $add 'ChangeLog' @{
        Id = 'changes'; Title = 'Change log (activity log)'; Noun = 'changes'; File = 'workspace-change-log'; Rows = @($Assessment.ChangeLog); GroupBy = @('Operation', 'Caller', 'Status')
        Sort = @{ Key = 'Time'; Desc = $true }
        Columns = @(
            @{ Key = 'Time'; Label = 'When'; Type = 'datetime' }
            @{ Key = 'Operation'; Label = 'Operation'; Facet = $true }
            @{ Key = 'Resource'; Label = 'On'; Type = 'mono' }
            @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = @{ Succeeded = 'good'; Failed = 'bad' }; Facet = $true }
            @{ Key = 'Caller'; Label = 'By'; Facet = $true }
            @{ Key = 'Detail'; Label = 'Detail'; Hidden = $true }
            @{ Key = 'Action'; Label = 'Action'; Type = 'mono'; Hidden = $true }
        )
    }

    $notices = @(
        foreach ($text in @($Assessment.Notices)) { @{ Tone = 'info'; Text = $text } }
        foreach ($key in @($Assessment.Errors.Keys)) { @{ Tone = 'warn'; Text = "$($key -replace '^\w+:', '') couldn't be read: $($Assessment.Errors[$key])" } }
    )
    $workspace = $Assessment.Workspace
    $subtitle = "$($workspace.Name) - $($workspace.PricingTier)$(if ($workspace.CommitmentTierGB) { " $($workspace.CommitmentTierGB) GB/day" }), $($workspace.RetentionDays)-day retention, last $($workspace.Days) day(s)"
    Write-AACHtmlReport -Path $Path -Title $Title -Subtitle $subtitle -Fact $Detail -Tile $tiles -Chart $charts -Table $tables.ToArray() -Notice $notices
}
