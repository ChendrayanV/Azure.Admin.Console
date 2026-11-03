function Get-AACAlertBaseline {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        The alerts Azure Monitor Baseline Alerts (AMBA) suggests for a resource
        type: metric, log and activity log alerts with their thresholds.
    .DESCRIPTION
        A starting point for monitoring, read from a copy of AMBA that ships with
        the module: no sign-in, nothing in Azure is read or changed, and it says
        nothing about whether you already have these alerts. Verified means the
        AMBA project has reviewed the alert; many are generated, so tune their
        thresholds to your workload.
    .PARAMETER ResourceType
        The resource types, wildcards allowed: Microsoft.Web/sites, Microsoft.Web/*.
        Tab completes them. Every type by default.
    .PARAMETER Severity
        Only these severities: Sev0 is the most severe, Sev4 the least.
    .PARAMETER CsvPath
        Write the alerts to this CSV file.
    .PARAMETER HtmlPath
        Write the report to this HTML file.
    .PARAMETER PdfPath
        Write the report to this PDF file.
    .PARAMETER Title
        The report's title.
    .PARAMETER PassThru
        Show the view and also return the alerts.
    .PARAMETER NoDisplay
        Return the alerts without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Get-AACAlertBaseline -ResourceType Microsoft.EventHub/namespaces
        The alerts AMBA suggests for an Event Hubs namespace.
    .EXAMPLE
        Get-AACAlertBaseline -ResourceType 'Microsoft.Web/*' -Severity Sev0, Sev1 -HtmlPath .\alerts.html
        The most severe alerts for App Service, as a report.
    .OUTPUTS
        AAC.AlertBaseline (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.AlertBaseline')]
    param(
        [Parameter(Position = 0)]
        [ArgumentCompleter({ param($Command, $Parameter, $Word) & (Get-Module -Name 'Azure.Admin.Console') { param($Typed) (Get-AACServiceBaseline -Set Alerts -ResourceType @()).Types | Where-Object { $_ -like "*$Typed*" } } $Word })]
        [SupportsWildcards()]
        [ValidateNotNullOrEmpty()]
        [string[]] $ResourceType = @('*'),

        [ValidateSet('Sev0', 'Sev1', 'Sev2', 'Sev3', 'Sev4')]
        [string[]] $Severity,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Azure Monitor baseline alerts',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Target) if ($Target) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Target) } }
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Baseline alerts' -Color 'deepskyblue3_1' }

    $baseline = Get-AACServiceBaseline -Set Alerts -ResourceType $ResourceType
    $rows = @($baseline.Rows | Where-Object { -not $Severity -or $Severity -contains $_.Severity })
    $count = { param([string] $Property, $Value) @($rows | Where-Object { $_.$Property -eq $Value }).Count }
    $severityTones = @{ Sev0 = 'bad'; Sev1 = 'bad'; Sev2 = 'warn'; Sev3 = 'info'; Sev4 = 'neutral' }
    $report = @{
        Facts    = [ordered]@{ 'Resource types' = $ResourceType -join ', '; Source = "$($baseline.Source.Name), commit $($baseline.Source.Commit.Substring(0, 12)) ($($baseline.Source.License))" }
        Status   = 'Info'
        Headline = "$($rows.Count) suggested alert(s) for $(@($rows | ForEach-Object { $_.ResourceType } | Select-Object -Unique).Count) resource type(s). A starting point: nothing here says what you already have."
        Tiles    = @(
            @{ Value = '{0:N0}' -f $rows.Count; Label = 'alerts'; Tone = 'info'; Table = 'alerts' }
            @{ Value = '{0:N0}' -f (& $count 'AlertType' 'Metric'); Label = 'metric'; Tone = 'violet'; Table = 'alerts'; Filters = @{ AlertType = 'Metric' } }
            @{ Value = '{0:N0}' -f (& $count 'AlertType' 'Log'); Label = 'log'; Tone = 'violet'; Table = 'alerts'; Filters = @{ AlertType = 'Log' } }
            @{ Value = '{0:N0}' -f (& $count 'Verified' $true); Label = 'verified by AMBA'; Tone = 'good'; Table = 'alerts' }
        )
        Tables   = @(
            @{ Id = 'alerts'; Title = 'Baseline alerts'; Section = 'Alerts'; Rows = $rows; Noun = 'alerts'; File = 'baseline-alerts'; GroupBy = @('ResourceType', 'Severity', 'AlertType'); ConsoleLimit = 30
                Empty = 'AMBA suggests no alert for this. It covers some resource types, not all.'; EmptyStatus = 'Info'; Hover = @('Description', 'Query'); HoverTitle = 'Name'
                Columns = @(
                    @{ Key = 'ResourceType'; Label = 'Type'; Type = 'mono'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Name'; Label = 'Alert'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'AlertType'; Label = 'Kind'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $severityTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Condition'; Label = 'Condition'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'Window'; Label = 'Window'; Pdf = $true }
                    @{ Key = 'Frequency'; Label = 'Every'; Pdf = $true }
                    @{ Key = 'Verified'; Label = 'Verified'; Facet = $true; Pdf = $true }
                    @{ Key = 'Description'; Label = 'Description'; Type = 'wide'; Hidden = $true }
                    @{ Key = 'Query'; Label = 'KQL'; Type = 'wide'; Hidden = $true }
                    @{ Key = 'Link'; Label = 'Learn more'; Type = 'link'; Text = 'Docs' }
                ) }
        )
        Hint     = '-ResourceType narrows it, wildcards allowed; -Severity Sev0, Sev1 for the most severe; -HtmlPath for the full list.'
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $rows -Noun 'baseline alert' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $rows -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
