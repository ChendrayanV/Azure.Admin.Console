function Write-AACDiagnosticSettingHtml {
    <#
    .SYNOPSIS
        Writes Get-AACDiagnosticSetting's result as an interactive HTML
        report: tiles and charts over tables of every resource's coverage,
        the misconfigurations, every diagnostic setting (flattened), coverage
        by type and the workspaces receiving logs.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Diagnostic,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Title,

        [System.Collections.IDictionary] $Detail
    )

    $stats = $Diagnostic.Stats
    $statusTones = @{ Exported = 'good'; Partial = 'warn'; 'Not to workspace' = 'bad'; 'No setting' = 'bad'; Unknown = 'neutral'; 'No logs' = 'neutral' }
    $severityTones = @{ High = 'bad'; Medium = 'warn'; Low = 'info' }
    $tiles = @(
        @{ Value = $(if ($null -ne $stats.CoveragePercent) { "$($stats.CoveragePercent)%" } else { '-' }); Label = 'exported to Log Analytics'; Tone = $(if ($stats.CoveragePercent -ge 90) { 'good' } elseif ($stats.CoveragePercent -ge 60) { 'warn' } else { 'bad' }); Table = 'coverage'; Filters = @{ Status = 'Exported' } }
        @{ Value = '{0:N0}' -f $stats.Partial; Label = 'partly exported'; Tone = 'warn'; Table = 'coverage'; Filters = @{ Status = 'Partial' } }
        @{ Value = '{0:N0}' -f $stats.NotToWorkspace; Label = 'settings, no workspace'; Tone = 'bad'; Table = 'coverage'; Filters = @{ Status = 'Not to workspace' } }
        @{ Value = '{0:N0}' -f $stats.NoSetting; Label = 'no diagnostic setting'; Tone = 'bad'; Table = 'coverage'; Filters = @{ Status = 'No setting' } }
        @{ Value = '{0:N0}' -f $stats.High; Label = 'high findings'; Tone = $(if ($stats.High) { 'bad' } else { 'good' }); Table = 'findings'; Filters = @{ Severity = 'High' } }
        @{ Value = '{0:N0}' -f ($stats.Medium + $stats.Low); Label = 'medium and low findings'; Tone = $(if ($stats.Medium) { 'warn' } else { 'neutral' }); Table = 'findings' }
        @{ Value = '{0:N0}' -f $stats.Settings; Label = 'diagnostic settings'; Tone = 'info'; Table = 'settings' }
        @{ Value = '{0:N0}' -f $stats.Workspaces; Label = 'workspaces receiving logs'; Tone = 'violet'; Table = 'workspaces' }
    )
    $charts = @(
        @{ Title = 'Resources by status'; Kind = 'donut'; CenterLabel = 'resources'; Table = 'coverage'; Column = 'Status'; Items = @($Diagnostic.Shown | Group-Object Status | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Tone = $statusTones[$_.Name] } }) }
        @{ Title = 'Findings'; Kind = 'donut'; CenterLabel = 'findings'; Table = 'findings'; Column = 'Severity'; Items = @($Diagnostic.Findings | Group-Object Severity | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Tone = $severityTones[$_.Name] } }) }
        @{ Title = 'Resource types with the most resources not exported'; Wide = $true; Tone = 'bad'; Table = 'coverage'; Column = 'ResourceType'; Items = @($Diagnostic.ByType | Where-Object { $_.NoSetting + $_.NotToWorkspace + $_.Partial } | Sort-Object { $_.NoSetting + $_.NotToWorkspace + $_.Partial } -Descending | Select-AACFirst 15 | ForEach-Object { @{ Label = $_.ResourceType; Value = $_.NoSetting + $_.NotToWorkspace + $_.Partial } }) }
    )
    $tables = @(
        @{
            Id = 'coverage'; Title = 'Resources'; Note = 'Exported: every log category reaches a Log Analytics workspace (by name or through allLogs / audit).'; Noun = 'resources'; File = 'diagnostic-coverage'
            Rows = @($Diagnostic.Shown); GroupBy = @('Status', 'ResourceType', 'SubscriptionName', 'ResourceGroup')
            Columns = @(
                @{ Key = 'Resource'; Label = 'Resource'; Type = 'resource'; IdKey = 'ResourceId' }
                @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = $statusTones; Facet = $true }
                @{ Key = 'ResourceType'; Label = 'Type'; Facet = $true }
                @{ Key = 'SubscriptionName'; Label = 'Subscription'; Facet = $true }
                @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                @{ Key = 'Location'; Label = 'Location'; Facet = $true; Hidden = $true }
                @{ Key = 'LogCategories'; Label = 'Log categories'; Type = 'number'; Format = 'N0' }
                @{ Key = 'CategoriesToWorkspace'; Label = 'To workspace'; Type = 'number'; Format = 'N0' }
                @{ Key = 'Reason'; Label = 'Why not exported'; Type = 'wide' }
                @{ Key = 'MissingCategories'; Label = 'Missing categories'; Type = 'wide'; Hidden = $true }
                @{ Key = 'Workspaces'; Label = 'Workspaces'; Facet = $true }
                @{ Key = 'Destinations'; Label = 'Destinations'; Facet = $true }
                @{ Key = 'SettingNames'; Label = 'Settings'; Type = 'wide'; Hidden = $true }
                @{ Key = 'Severity'; Label = 'Worst finding'; Type = 'badge'; Tones = $severityTones; Facet = $true }
                @{ Key = 'Findings'; Label = 'Findings'; Type = 'wide' }
                @{ Key = 'Error'; Label = 'Error'; Type = 'wide'; Hidden = $true }
            )
        }
        @{
            Id = 'findings'; Title = 'Misconfigurations'; Noun = 'findings'; File = 'diagnostic-findings'; Rows = @($Diagnostic.Findings); GroupBy = @('Finding', 'Severity', 'ResourceType')
            Columns = @(
                @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $severityTones; Facet = $true }
                @{ Key = 'Finding'; Label = 'Finding'; Facet = $true }
                @{ Key = 'Resource'; Label = 'Resource'; Type = 'resource'; IdKey = 'ResourceId' }
                @{ Key = 'ResourceType'; Label = 'Type'; Facet = $true }
                @{ Key = 'SubscriptionName'; Label = 'Subscription'; Facet = $true; Hidden = $true }
                @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true; Hidden = $true }
                @{ Key = 'Setting'; Label = 'Setting' }
                @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide' }
                @{ Key = 'Action'; Label = 'What to do'; Type = 'wide' }
                @{ Key = 'LearnMore'; Label = 'Learn more'; Type = 'link'; Hidden = $true }
            )
        }
        @{
            Id = 'settings'; Title = 'Diagnostic settings'; Note = 'One row per setting, flattened.'; Noun = 'settings'; File = 'diagnostic-settings'; Rows = @($Diagnostic.Shown | ForEach-Object { $_.Detail }); GroupBy = @('Workspace', 'ResourceType', 'Destinations', 'DestinationTable')
            Columns = @(
                @{ Key = 'Resource'; Label = 'Resource'; Type = 'resource'; IdKey = 'ResourceId' }
                @{ Key = 'ResourceType'; Label = 'Type'; Facet = $true }
                @{ Key = 'Setting'; Label = 'Setting' }
                @{ Key = 'Destinations'; Label = 'Destinations'; Facet = $true }
                @{ Key = 'Workspace'; Label = 'Workspace'; Facet = $true }
                @{ Key = 'WorkspaceFound'; Label = 'Workspace found'; Facet = $true; Hidden = $true }
                @{ Key = 'WorkspaceLocation'; Label = 'Workspace location'; Facet = $true; Hidden = $true }
                @{ Key = 'DestinationTable'; Label = 'Table'; Facet = $true }
                @{ Key = 'LogsEnabled'; Label = 'Logs enabled'; Type = 'wide' }
                @{ Key = 'LogsDisabled'; Label = 'Logs disabled'; Type = 'wide'; Hidden = $true }
                @{ Key = 'MetricsEnabled'; Label = 'Metrics'; Facet = $true }
                @{ Key = 'StorageAccount'; Label = 'Storage account'; Facet = $true }
                @{ Key = 'EventHub'; Label = 'Event hub'; Facet = $true }
                @{ Key = 'Partner'; Label = 'Partner'; Hidden = $true }
                @{ Key = 'RetentionDays'; Label = 'Retention (days)'; Hidden = $true }
                @{ Key = 'SubscriptionName'; Label = 'Subscription'; Facet = $true; Hidden = $true }
                @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true; Hidden = $true }
            )
        }
        @{
            Id = 'types'; Title = 'Coverage by resource type'; Noun = 'resource types'; File = 'diagnostic-coverage-by-type'; Rows = @($Diagnostic.ByType)
            Columns = @(
                @{ Key = 'ResourceType'; Label = 'Resource type' }
                @{ Key = 'CoveragePercent'; Label = 'Coverage'; Type = 'score' }
                @{ Key = 'Exported'; Label = 'Exported'; Type = 'number'; Format = 'N0'; Sum = $true }
                @{ Key = 'Partial'; Label = 'Partial'; Type = 'number'; Format = 'N0'; Sum = $true }
                @{ Key = 'NotToWorkspace'; Label = 'No workspace'; Type = 'number'; Format = 'N0'; Sum = $true }
                @{ Key = 'NoSetting'; Label = 'No setting'; Type = 'number'; Format = 'N0'; Sum = $true }
                @{ Key = 'Unknown'; Label = 'Unknown'; Type = 'number'; Format = 'N0'; Sum = $true; Hidden = $true }
                @{ Key = 'Resources'; Label = 'Resources'; Type = 'number'; Format = 'N0'; Sum = $true }
            )
        }
        @{
            Id = 'workspaces'; Title = 'Workspaces receiving logs'; Noun = 'workspaces'; File = 'diagnostic-workspaces'; Rows = @($Diagnostic.Workspaces)
            Columns = @(
                @{ Key = 'Workspace'; Label = 'Workspace'; Type = 'resource'; IdKey = 'ResourceId' }
                @{ Key = 'Location'; Label = 'Location'; Facet = $true }
                @{ Key = 'Found'; Label = 'Found'; Facet = $true }
                @{ Key = 'Expected'; Label = 'Expected'; Facet = $true }
                @{ Key = 'Resources'; Label = 'Resources'; Type = 'number'; Format = 'N0'; Sum = $true }
                @{ Key = 'Settings'; Label = 'Settings'; Type = 'number'; Format = 'N0'; Sum = $true }
            )
        }
    )
    $notices = @(foreach ($text in @($Diagnostic.Notice | Where-Object { $_ })) { @{ Tone = 'info'; Text = $text } })
    $subtitle = ('{0:N0} resource(s) with logs: {1:N0} exported to Log Analytics, {2:N0} partly, {3:N0} not' -f $stats.WithLogs, $stats.Exported, $stats.Partial, ($stats.NotToWorkspace + $stats.NoSetting))
    Write-AACHtmlReport -Path $Path -Title $Title -Subtitle $subtitle -Fact $Detail -Tile $tiles -Chart $charts -Table $tables -Notice $notices
}
