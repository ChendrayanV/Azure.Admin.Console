function Get-AACSentinelContentHub {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Lists the Content hub solutions and standalone content installed on a
        Microsoft Sentinel workspace - version, whether an update is out,
        support tier, the analytics rules, workbooks, hunting queries,
        playbooks, parsers and data connectors each brought, and how many of
        its analytics templates have a rule.
    .DESCRIPTION
        Reads the workspace from Azure Resource Manager - read-only, nothing is
        changed: the installed content packages, the Content hub catalog (for
        the latest versions), the templates the installed packages brought,
        and the analytics rules.

        Each package: Name, State (Installed, or Available with
        -IncludeAvailable), Kind (Solution or Standalone), Publisher, Support
        (Microsoft, Partner or Community), InstalledVersion, LatestVersion,
        UpdateAvailable, Deprecated, Preview, AnalyticsRuleTemplates,
        TemplatesUsed (templates with a rule), RulesCreated, RulesEnabled,
        Workbooks, HuntingQueries, Playbooks, Parsers, DataConnectors,
        OtherTemplates, Findings, Domains, LastPublished and ContentId.

        Findings:
          Update available        a newer version is in Content hub; updating
                                  brings new and fixed templates, but doesn't
                                  change rules already created from them
          Deprecated              Microsoft no longer maintains it: look for
                                  its replacement
          No enabled rule         installed, but none of its analytics
                                  templates has an enabled rule - it detects
                                  nothing yet

        Needs Microsoft Sentinel Reader on the workspace.
    .PARAMETER WorkspaceId
        The workspace: its workspace ID (GUID), resource ID or name.
    .PARAMETER SubscriptionId
        Where to look for a workspace given by ID (GUID) or name. Every
        subscription the account can see by default.
    .PARAMETER ResourceGroupName
        Narrows a workspace given by name, when the name is in more than one
        resource group.
    .PARAMETER Name
        Only packages whose name matches; wildcards work.
    .PARAMETER UpdateAvailable
        Only installed packages with a newer version in Content hub.
    .PARAMETER IncludeAvailable
        Also list the catalog's packages that aren't installed (several
        hundred).
    .PARAMETER CsvPath
        Write the packages to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report to this file.
    .PARAMETER PdfPath
        Write a PDF report to this file.
    .PARAMETER Title
        The HTML and PDF reports' title.
    .PARAMETER PassThru
        Show the view and also return the packages.
    .PARAMETER NoDisplay
        Return the packages without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once instead of a page at a time.
    .EXAMPLE
        Connect-AAC
        Get-AACSentinelContentHub -WorkspaceId 'law-contoso-sentinel'
        The installed solutions, the ones with findings first.
    .EXAMPLE
        Get-AACSentinelContentHub -WorkspaceId 'law-contoso-sentinel' -UpdateAvailable
        The solutions with an update waiting.
    .EXAMPLE
        Get-AACSentinelContentHub -WorkspaceId 'law-contoso-sentinel' -NoDisplay | Where-Object { $_.AnalyticsRuleTemplates -and -not $_.RulesEnabled }
        Solutions installed for detections that have none turned on.
    .EXAMPLE
        Get-AACSentinelContentHub -WorkspaceId 'law-contoso-sentinel' -IncludeAvailable -Name '*Okta*', '*CrowdStrike*'
        Whether solutions for these products are installed, and what is offered.
    .OUTPUTS
        AAC.SentinelContentPackage (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.SentinelContentPackage')]
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

        [switch] $UpdateAvailable,

        [switch] $IncludeAvailable,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Microsoft Sentinel Content hub',

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
    $arm = [ordered]@{
        installed  = "$insights/contentPackages?api-version=2025-09-01"
        catalog    = "$insights/contentProductPackages?api-version=2025-09-01"
        templates  = "$insights/contentTemplates?api-version=2025-09-01"
        alertRules = "$insights/alertRules?api-version=2025-09-01"
    }
    # Read here, not inside the progress block (it runs in Invoke-AACProgress's scope).
    $request = @{ Target = $WorkspaceId.Trim(); SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ResourceGroupName = $ResourceGroupName; Arm = $arm; IncludeAvailable = [bool]$IncludeAvailable }

    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Microsoft Sentinel Content hub' -Color 'deepskyblue3_1' }
    $state = Invoke-AACProgress -ScriptBlock {
        $null = Get-AACAccessToken
        Update-AACProgress -Id 'read' -Indeterminate -Description "Reading Content hub on $($request.Target)"
        $read = Read-AACSentinelWorkspace -Target $request.Target -SubscriptionId $request.SubscriptionId -ResourceGroupName $request.ResourceGroupName -Arm $request.Arm
        $listed = { param([string] $Key) if ($read.Arm[$Key].Error) { @() } else { @($read.Arm[$Key].Items | Where-Object { $null -ne $_ }) } }
        $packages = @(ConvertTo-AACSentinelContentPackage -Installed @(& $listed 'installed') -Catalog @(& $listed 'catalog') -Template @(& $listed 'templates') -Rule @(& $listed 'alertRules') -IncludeAvailable:$request.IncludeAvailable)
        Update-AACProgress -Id 'read' -Complete -Description "Workspace $($read.Name): $(@($packages | Where-Object State -EQ 'Installed').Count) package(s) installed"
        @{ Read = $read; Packages = $packages }
    }
    $read = $state.Read
    # Without the list there's nothing to show, and an empty one would mislead.
    if ($read.Arm['installed'].Error) {
        $problem = [System.InvalidOperationException]::new("Azure Admin Console couldn't read the installed Content hub packages of $($read.Name): $($read.Arm['installed'].Error)")
        $problem.Data['AACHint'] = 'Your account needs Microsoft Sentinel Reader on the workspace.'
        throw $problem
    }
    $notices = [System.Collections.Generic.List[hashtable]]::new()
    $why = @{ catalog = 'so no update is reported'; templates = 'so the templates each package brought are not counted'; alertRules = 'so no rule is counted against a template' }
    foreach ($k in 'catalog', 'templates', 'alertRules') {
        if ($read.Arm[$k].Error) { $notices.Add(@{ Status = 'Warning'; Text = "The $(@{ catalog = 'Content hub catalog'; templates = 'content templates'; alertRules = 'analytics rules' }[$k]) couldn't be read, $($why[$k]): $($read.Arm[$k].Error)" }) }
    }

    $packages = @($state.Packages)
    if ($Name) { $packages = @($packages | Where-Object { $p = $_; @($Name | Where-Object { $p.Name -like $_ }).Count }) }
    if ($UpdateAvailable) { $packages = @($packages | Where-Object UpdateAvailable) }

    # --- The report -------------------------------------------------------------------------------------------
    $installed = @($packages | Where-Object State -EQ 'Installed')
    $updates = @($installed | Where-Object UpdateAvailable).Count
    $deprecated = @($installed | Where-Object Deprecated).Count
    $idle = @($installed | Where-Object { $_.AnalyticsRuleTemplates -and -not $_.RulesEnabled }).Count
    $templateCount = [int](@($installed | ForEach-Object { $_.AnalyticsRuleTemplates } | Measure-Object -Sum).Sum)
    $usedCount = [int](@($installed | ForEach-Object { $_.TemplatesUsed } | Measure-Object -Sum).Sum)
    $headline = if (-not $installed.Count -and -not $packages.Count) { "No Content hub packages match on $($read.Name)." }
    else { "$($installed.Count) package(s) installed: $updates with an update, $deprecated deprecated, $idle with no enabled rule; $usedCount of $templateCount analytics template(s) have a rule" }
    $report = @{
        Subtitle = 'Microsoft Sentinel Content hub: what is installed, what is out of date, and what is used'
        Facts    = [ordered]@{ Workspace = "$($read.Name) ($($read.ResourceGroup))" }
        Status   = $(if ($deprecated) { 'Failed' } elseif ($updates -or $idle) { 'Warning' } else { 'Success' })
        Headline = $headline
        Tiles    = @(
            @{ Value = '{0:N0}' -f $installed.Count; Label = 'installed'; Tone = 'info'; Table = 'packages'; Filters = @{ State = 'Installed' } }
            @{ Value = '{0:N0}' -f $updates; Label = 'update available'; Tone = $(if ($updates) { 'warn' } else { 'good' }) }
            @{ Value = '{0:N0}' -f $deprecated; Label = 'deprecated'; Tone = $(if ($deprecated) { 'bad' } else { 'good' }) }
            @{ Value = '{0:N0}' -f $idle; Label = 'no enabled rule'; Tone = $(if ($idle) { 'warn' } else { 'good' }) }
            @{ Value = "$usedCount/$templateCount"; Label = 'analytics templates with a rule'; Tone = 'violet' }
        )
        Notices  = @($notices)
        Charts   = @(
            @{ Title = 'Installed by support tier'; Kind = 'donut'; CenterLabel = 'packages'; Items = @($installed | Group-Object { if ($_.Support) { $_.Support } else { '(unknown)' } } | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'packages'; Column = 'Support' }
            @{ Title = 'Most analytics templates'; Items = @($installed | Where-Object AnalyticsRuleTemplates | Sort-Object AnalyticsRuleTemplates -Descending | Select-AACFirst 10 | ForEach-Object { @{ Label = $_.Name; Value = $_.AnalyticsRuleTemplates; Filter = $_.Name } }); Table = 'packages'; Column = 'Name'; Tone = 'info'; Console = $true }
        )
        Tables   = @(
            @{ Id = 'packages'; Title = 'Content hub packages'; Section = 'Packages'; Rows = $packages; Noun = 'packages'; File = 'sentinel-content-hub'; GroupBy = @('State', 'Kind', 'Support', 'Publisher'); ConsoleLimit = 40
                Empty = 'No Content hub packages are installed on this workspace.'; EmptyStatus = 'Info'
                Columns = @(
                    @{ Key = 'Name'; Label = 'Package'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'State'; Label = 'State'; Type = 'badge'; Tones = @{ Installed = 'good'; Available = 'neutral' }; Facet = $true }
                    @{ Key = 'InstalledVersion'; Label = 'Installed'; Type = 'mono'; Console = $true; Pdf = $true }
                    @{ Key = 'LatestVersion'; Label = 'Latest'; Type = 'mono'; Console = $true; Pdf = $true }
                    @{ Key = 'Support'; Label = 'Support'; Facet = $true; Console = $true }
                    @{ Key = 'AnalyticsRuleTemplates'; Label = 'Analytics templates'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'RulesEnabled'; Label = 'Rules enabled'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'Findings'; Label = 'Findings'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'Kind'; Label = 'Kind'; Facet = $true }
                    @{ Key = 'Publisher'; Label = 'Publisher'; Facet = $true }
                    @{ Key = 'Workbooks'; Label = 'Workbooks'; Type = 'number' }
                    @{ Key = 'HuntingQueries'; Label = 'Hunting queries'; Type = 'number' }
                    @{ Key = 'Playbooks'; Label = 'Playbooks'; Type = 'number' }
                    @{ Key = 'Parsers'; Label = 'Parsers'; Type = 'number' }
                    @{ Key = 'DataConnectors'; Label = 'Data connectors'; Type = 'number' }
                    @{ Key = 'Domains'; Label = 'Domains'; Facet = $true; Hidden = $true }
                    @{ Key = 'LastPublished'; Label = 'Last published'; Type = 'datetime'; Hidden = $true }
                    @{ Key = 'ContentId'; Label = 'Content ID'; Type = 'mono'; Hidden = $true }
                ) }
        )
        Hint     = '-UpdateAvailable for what to update; -IncludeAvailable -Name ''*product*'' to see what Content hub offers; Get-AACSentinelAnalyticsRule for the rules themselves.'
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $packages -Noun 'package' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $packages -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
