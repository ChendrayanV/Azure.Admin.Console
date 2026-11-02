function Find-AACSentinelHuntingQuery {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Lists the hunting queries you could deploy to Microsoft Sentinel - for
        Entra ID sign-ins and audit, Microsoft 365 and Intune - and, for a
        workspace, whether each is ready and how it stands there.
    .DESCRIPTION
        The shopping list: Get-AACSentinelHuntingQuery is the inventory of what
        a workspace already has. Pipe this command to
        Deploy-AACSentinelHuntingQuery. Read-only.

        The packs:
          SignIn       Entra ID sign-ins (SigninLogs and non-interactive)
          M365         Microsoft 365 (OfficeActivity, CloudAppEvents)
          EntraAudit   Entra ID directory changes (AuditLogs)
          Intune       Intune, written for this module: the Azure-Sentinel
                       repository has none
        The first three come from the Azure-Sentinel repository on GitHub, at a
        commit pinned in the module, including the queries that repository
        moved into its solutions. These queries are community content: read
        one before relying on it. -Ref picks another commit, and -Path reads a
        local clone instead of GitHub.

        -YamlSource looks at files you name instead of the packs: links to
        GitHub, or files on this computer. A link to a branch reads whatever is
        on it now, not the pinned commit.

        With -WorkspaceId, each query also says:
          Readiness    Ready; Missing data (a table it needs had nothing in the
                       last -Days); Missing watchlist; Unknown
          Deployment   New; Current; Update available; Changed (edited in the
                       workspace, or not deployed by this module); Other copy
                       (this name under another ID, say from Content hub)
        Without it, it lists the catalog and needs no Azure sign-in.

        Intune's tables fill only when Intune's diagnostic settings send logs
        to the workspace (Intune admin center, Reports, Diagnostics settings).

        What you get depends on where the command runs:
          at the prompt    a summary, then the queries
          piped onward     the queries, with no view
          -PassThru        the view and the queries
          -NoDisplay       the queries only
        -CsvPath, -HtmlPath and -PdfPath write reports instead of the view.
    .PARAMETER Pack
        SignIn, M365, EntraAudit, Intune. All of them by default.
    .PARAMETER YamlSource
        Hunting query YAML files, instead of the packs: github.com/.../blob/...
        or raw.githubusercontent.com links, or local paths. A stub in
        Azure/Azure-Sentinel is followed to where the query moved. Stops if one
        can't be read.
    .PARAMETER Name
        Only queries with these names (wildcards work).
    .PARAMETER Tactic
        Only queries for these MITRE ATT&CK tactics, such as InitialAccess.
    .PARAMETER WorkspaceId
        The workspace to check against: its workspace ID (GUID), resource ID or
        name. Without it, only the catalog is listed.
    .PARAMETER SubscriptionId
        Where to look for a workspace given by ID (GUID) or name. Every
        subscription the account can see by default.
    .PARAMETER ResourceGroupName
        Narrows a workspace given by name, when the name is in more than one
        resource group.
    .PARAMETER Days
        How far back a table must have data to count: 1 to 90 days, 30 by
        default.
    .PARAMETER Ref
        The commit, branch or tag of Azure/Azure-Sentinel to read. A commit
        pinned in the module by default.
    .PARAMETER Path
        The top folder of a local clone of Azure/Azure-Sentinel, instead of
        GitHub.
    .PARAMETER CsvPath
        Write the queries to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report to this file.
    .PARAMETER PdfPath
        Write a PDF report to this file.
    .PARAMETER Title
        The HTML and PDF reports' title.
    .PARAMETER PassThru
        Show the view and also return the queries.
    .PARAMETER NoDisplay
        Return the queries without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once instead of a page at a time.
    .EXAMPLE
        Find-AACSentinelHuntingQuery -Pack Intune
        The Intune queries, with no Azure sign-in.
    .EXAMPLE
        Connect-AAC
        Find-AACSentinelHuntingQuery -Pack SignIn, M365, Intune -WorkspaceId 'law-contoso-sentinel' -HtmlPath .\out\Hunting.html
        What each pack offers, what this workspace is ready for, as a report.
    .EXAMPLE
        Find-AACSentinelHuntingQuery -Pack SignIn -Tactic InitialAccess -WorkspaceId 'law-contoso-sentinel' | Where-Object Ready | Deploy-AACSentinelHuntingQuery -WorkspaceId 'law-contoso-sentinel' -WhatIf
        What deploying the ready sign-in queries for initial access would do.
    .EXAMPLE
        (Find-AACSentinelHuntingQuery -Name '*break-glass*' -NoDisplay).Query
        Read a query before deploying it.
    .EXAMPLE
        Find-AACSentinelHuntingQuery -YamlSource 'https://github.com/Azure/Azure-Sentinel/blob/master/Hunting%20Queries/OfficeActivity/AnomolousUserAccessingOtherUsersMailbox.yaml' -WorkspaceId 'law-contoso-sentinel'
        Look at one file, and whether this workspace is ready for it.
    .OUTPUTS
        AAC.SentinelHuntingQuery (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding(DefaultParameterSetName = 'Pack')]
    [OutputType('AAC.SentinelHuntingQuery')]
    param(
        [Parameter(ParameterSetName = 'Pack')]
        [ValidateSet('SignIn', 'M365', 'EntraAudit', 'Intune')]
        [string[]] $Pack = @('SignIn', 'M365', 'EntraAudit', 'Intune'),

        [Parameter(Mandatory, ParameterSetName = 'YamlSource')]
        [ValidateNotNullOrEmpty()]
        [string[]] $YamlSource,

        [SupportsWildcards()]
        [string[]] $Name,

        [string[]] $Tactic,

        [Alias('Workspace', 'WorkspaceName', 'ResourceId')]
        [string] $WorkspaceId,

        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string] $ResourceGroupName,

        [ValidateRange(1, 90)]
        [int] $Days = 30,

        [Parameter(ParameterSetName = 'Pack')]
        [ValidatePattern('^[\w./-]+$')]
        [string] $Ref,

        [Parameter(ParameterSetName = 'Pack')]
        [string] $Path,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Microsoft Sentinel hunting queries',

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
    # Read here, not inside the progress block (it runs in Invoke-AACProgress's scope).
    $catalogArguments = @{ Pack = $Pack }
    if ($Ref) { $catalogArguments.Ref = $Ref }
    if ($Path) { $catalogArguments.Path = & $resolve $Path }
    $yamlSources = @($YamlSource | Where-Object { $_ } | ForEach-Object { if ($_ -match '^[a-zA-Z][a-zA-Z0-9+.-]*://') { $_ } else { & $resolve $_ } })
    $request = @{ Name = @($Name | Where-Object { $_ }); Tactic = @($Tactic | Where-Object { $_ }); Target = $WorkspaceId.Trim(); SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ResourceGroupName = $ResourceGroupName; Days = $Days }
    # What the view calls the packs: the files named are a pack of their own.
    $shownPacks = if ($yamlSources.Count) { @('YAML') } else { $Pack }

    if ($interactive) {
        Write-AACRule -Title 'Azure Admin Console :: Sentinel hunting queries' -Color 'deepskyblue3_1'
    }
    $state = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'catalog' -Description 'Reading the hunting queries' -Indeterminate
        $catalog = if ($yamlSources.Count) { Get-AACHuntingQueryFromYaml -Source $yamlSources } else { Get-AACHuntingQueryCatalog @catalogArguments }
        $rows = @($catalog.Queries | Where-Object {
                $row = $_
                (-not $request.Name.Count -or @($request.Name | Where-Object { $row.Name -like $_ }).Count) -and
                (-not $request.Tactic.Count -or @($request.Tactic | Where-Object { ([string]$row.Tactics -split ',\s*') -contains $_ }).Count)
            })
        Update-AACProgress -Id 'catalog' -Complete -Description "$($rows.Count) hunting query(ies) in the catalog"
        $workspace = $null
        if ($request.Target) {
            $null = Get-AACAccessToken
            Update-AACProgress -Id 'workspace' -Description "Checking workspace $($request.Target)" -Indeterminate
            $workspace = Read-AACHuntingWorkspace -Target $request.Target -SubscriptionId $request.SubscriptionId -ResourceGroupName $request.ResourceGroupName -Days $request.Days
            $rows = @(ConvertTo-AACHuntingQueryState -Query $rows -Workspace $workspace)
            Update-AACProgress -Id 'workspace' -Complete -Description "Workspace $($workspace.Name): $(@($rows | Where-Object Ready).Count) ready, $(@($rows | Where-Object Deployment -EQ 'New').Count) new"
        }
        @{ Rows = $rows; Workspace = $workspace; Catalog = $catalog }
    }
    $rows = @($state.Rows)
    $workspace = $state.Workspace

    # --- The report model -------------------------------------------------------------------------------------------
    $readinessTones = @{ Ready = 'good'; 'Missing data' = 'warn'; 'Missing watchlist' = 'warn'; Unknown = 'neutral' }
    $deploymentTones = @{ New = 'info'; Current = 'good'; 'Update available' = 'warn'; Changed = 'warn'; 'Other copy' = 'neutral'; Unknown = 'neutral' }
    $notices = @(
        if ($workspace -and -not $workspace.SentinelEnabled) { @{ Status = 'Warning'; Text = 'Microsoft Sentinel is not enabled on this workspace, so its hunting page does not exist yet. Enable it before deploying.' } }
        if ($workspace) { foreach ($key in @($workspace.Errors.Keys)) { @{ Status = 'Warning'; Text = "$key couldn't be read: $($workspace.Errors[$key])" } } }
        foreach ($key in @($state.Catalog.Failures.Keys)) { @{ Status = 'Warning'; Text = "$key couldn't be read: $($state.Catalog.Failures[$key])" } }
    )
    $count = { param([string] $Property, [string] $Value) @($rows | Where-Object { $_.$Property -eq $Value }).Count }
    $facts = [ordered]@{ Packs = $shownPacks -join ', '; Source = "commit $($state.Catalog.Ref)" }
    if ($Path) { $facts.Source = "local clone $Path" }
    if ($yamlSources.Count) { $facts.Source = @($rows | ForEach-Object { $_.Source } | Select-Object -Unique) -join ', ' }
    if ($workspace) { $facts['Workspace'] = "$($workspace.Name) ($($workspace.ResourceGroup))"; $facts['Period'] = "last $Days day(s)" }
    $report = @{
        Facts    = $facts
        Status   = $(if ($notices.Count) { 'Warning' } else { 'Success' })
        Headline = $(if ($workspace) { "$($rows.Count) hunting query(ies): $(& $count 'Readiness' 'Ready') ready for $($workspace.Name), $(& $count 'Deployment' 'New') new, $(& $count 'Deployment' 'Current') already current" } else { "$($rows.Count) hunting query(ies) in the catalog. Add -WorkspaceId to see what a workspace is ready for." })
        Tiles    = @(
            @{ Value = '{0:N0}' -f $rows.Count; Label = 'queries'; Tone = 'info'; Table = 'queries' }
            foreach ($packName in $shownPacks) { @{ Value = '{0:N0}' -f @($rows | Where-Object { ([string]$_.Pack -split ',\s*') -contains $packName }).Count; Label = "$packName pack"; Tone = 'violet'; Table = 'queries' } }
            if ($workspace) {
                @{ Value = '{0:N0}' -f (& $count 'Readiness' 'Ready'); Label = 'ready'; Tone = 'good'; Table = 'queries'; Filters = @{ Readiness = 'Ready' } }
                @{ Value = '{0:N0}' -f (& $count 'Readiness' 'Missing data'); Label = 'missing data'; Tone = 'warn'; Table = 'queries'; Filters = @{ Readiness = 'Missing data' } }
                @{ Value = '{0:N0}' -f (& $count 'Deployment' 'New'); Label = 'new'; Tone = 'info'; Table = 'queries'; Filters = @{ Deployment = 'New' } }
            }
        )
        Notices  = $notices
        Charts   = @(@{ Title = 'Queries by tactic'; Tone = 'violet'; Format = 'N0'; Table = 'queries'; Items = @($rows | ForEach-Object { ([string]$_.Tactics -split ',\s*') } | Where-Object { $_ } | Group-Object | Sort-Object Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count } }) })
        Tables   = @(
            @{ Id = 'queries'; Title = 'Hunting queries'; Section = 'Queries'; Rows = $rows; Noun = 'queries'; File = 'sentinel-hunting-queries'; GroupBy = @('Pack', 'Readiness', 'Deployment', 'Source'); ConsoleLimit = 30
                Empty = 'No hunting query matches.'; EmptyStatus = 'Info'; Hover = @('Description', 'Query'); HoverTitle = 'Name'
                Columns = @(
                    @{ Key = 'Name'; Label = 'Query'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'Pack'; Label = 'Pack'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Tactics'; Label = 'Tactics'; Console = $true; Pdf = $true }
                    @{ Key = 'Readiness'; Label = 'Readiness'; Type = 'badge'; Tones = $readinessTones; Facet = $true; Console = [bool]$workspace; Pdf = $true }
                    @{ Key = 'Missing'; Label = 'Missing'; Console = [bool]$workspace; Pdf = $true }
                    @{ Key = 'Deployment'; Label = 'Deployment'; Type = 'badge'; Tones = $deploymentTones; Facet = $true; Console = [bool]$workspace; Pdf = $true }
                    @{ Key = 'DataTypes'; Label = 'Tables'; Console = -not $workspace; Pdf = $true }
                    @{ Key = 'Techniques'; Label = 'Techniques'; Hidden = $true }
                    @{ Key = 'Watchlists'; Label = 'Watchlists'; Hidden = $true }
                    @{ Key = 'Version'; Label = 'Version'; Hidden = $true }
                    @{ Key = 'Source'; Label = 'Source'; Facet = $true }
                    @{ Key = 'RepoPath'; Label = 'File'; Type = 'mono'; Hidden = $true }
                    @{ Key = 'Description'; Label = 'Description'; Type = 'wide'; Hidden = $true }
                    @{ Key = 'Query'; Label = 'KQL'; Type = 'wide'; Hidden = $true }
                ) }
        )
        Hint     = "Pipe to Deploy-AACSentinelHuntingQuery -WorkspaceId <workspace> -WhatIf; -PassThru returns the queries with their KQL; -HtmlPath for the full list."
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $rows -Noun 'hunting query' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $rows -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
