function Get-AACSentinelHuntingQuery {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Lists the hunting queries on a Microsoft Sentinel workspace: whatever
        put them there.
    .DESCRIPTION
        The inventory: Find-AACSentinelHuntingQuery is the shopping list of what
        could be deployed. Reads the workspace's saved searches in the Hunting
        Queries category, which is how Sentinel stores them. Read-only.

        For each: its name, tactics and techniques, description and KQL, and
          Source   This module (deployed by Deploy-AACSentinelHuntingQuery), or
                   Elsewhere (the portal, Content hub, another tool)
          Origin   for this module's: the pack's source file and commit
          Edited   this module's query was changed in the workspace after it was
                   deployed; blank for queries from elsewhere, which this
                   module can't judge

        What you get depends on where the command runs:
          at the prompt    a summary, then the queries
          piped onward     the queries, with no view
          -PassThru        the view and the queries
          -NoDisplay       the queries only
        -CsvPath, -HtmlPath and -PdfPath write reports instead of the view.

        Needs Reader, Microsoft Sentinel Reader or Log Analytics Reader on the
        workspace.
    .PARAMETER WorkspaceId
        The workspace: its workspace ID (GUID), resource ID or name.
    .PARAMETER SubscriptionId
        Where to look for a workspace given by ID (GUID) or name. Every
        subscription the account can see by default.
    .PARAMETER ResourceGroupName
        Narrows a workspace given by name, when the name is in more than one
        resource group.
    .PARAMETER Name
        Only queries with these names (wildcards work).
    .PARAMETER Tactic
        Only queries for these MITRE ATT&CK tactics, such as InitialAccess.
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
        Connect-AAC
        Get-AACSentinelHuntingQuery -WorkspaceId 'law-contoso-sentinel'
        Every hunting query on the workspace.
    .EXAMPLE
        Get-AACSentinelHuntingQuery -WorkspaceId 'law-contoso-sentinel' | Where-Object Source -EQ 'This module' | Where-Object Edited
        The queries this module deployed that someone has since edited.
    .OUTPUTS
        AAC.SentinelInstalledHuntingQuery (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.SentinelInstalledHuntingQuery')]
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

        [string[]] $Tactic,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Microsoft Sentinel hunting queries on the workspace',

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
    $request = @{ Target = $WorkspaceId.Trim(); SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ResourceGroupName = $ResourceGroupName }

    if ($interactive) {
        Write-AACRule -Title 'Azure Admin Console :: Sentinel hunting queries on the workspace' -Color 'deepskyblue3_1'
    }
    $workspace = Invoke-AACProgress -ScriptBlock {
        $null = Get-AACAccessToken
        Update-AACProgress -Id 'workspace' -Description "Reading the saved searches of $($request.Target)" -Indeterminate
        $read = Read-AACHuntingWorkspace -Target $request.Target -SubscriptionId $request.SubscriptionId -ResourceGroupName $request.ResourceGroupName -SavedSearchesOnly
        Update-AACProgress -Id 'workspace' -Complete -Description "Workspace $($read.Name): $(@($read.SavedSearches).Count) hunting query(ies)"
        $read
    }
    # Without the list there's nothing to show, and an empty one would mislead.
    if ($workspace.Errors.Contains('Saved searches')) {
        $problem = [System.InvalidOperationException]::new("Azure Admin Console couldn't read the saved searches of $($workspace.Name): $($workspace.Errors['Saved searches'])")
        $problem.Data['AACHint'] = 'Check your role on the workspace, then run the command again.'
        throw $problem
    }

    $rows = @(foreach ($saved in @($workspace.SavedSearches)) {
            $properties = $saved['properties']
            $query = [string]$properties['query']
            $deployedHash = Get-AACHuntingQueryTag -SavedSearch $saved -Name 'aacQueryHash'
            [pscustomobject][ordered]@{
                PSTypeName  = 'AAC.SentinelInstalledHuntingQuery'
                Name        = [string]$properties['displayName']
                Id          = [string]$saved['name']
                Tactics     = ((Get-AACHuntingQueryTag -SavedSearch $saved -Name 'tactics') -split ',\s*' | Where-Object { $_ }) -join ', '
                Techniques  = ((Get-AACHuntingQueryTag -SavedSearch $saved -Name 'techniques') -split ',\s*' | Where-Object { $_ }) -join ', '
                Source      = $(if ($deployedHash) { 'This module' } else { 'Elsewhere' })
                Origin      = Get-AACHuntingQueryTag -SavedSearch $saved -Name 'aacSource'
                Version     = Get-AACHuntingQueryTag -SavedSearch $saved -Name 'aacVersion'
                Edited      = $(if ($deployedHash) { $deployedHash -ne (Get-AACHuntingQueryHash -Query $query) })
                Description = Get-AACHuntingQueryTag -SavedSearch $saved -Name 'description'
                Query       = $query
            }
        })
    if ($Name) { $rows = @($rows | Where-Object { $row = $_; @($Name | Where-Object { $row.Name -like $_ }).Count }) }
    if ($Tactic) { $rows = @($rows | Where-Object { $row = $_; @($Tactic | Where-Object { ([string]$row.Tactics -split ',\s*') -contains $_ }).Count }) }
    $rows = @($rows | Sort-Object -Property Name)

    $report = @{
        Facts    = [ordered]@{ Workspace = "$($workspace.Name) ($($workspace.ResourceGroup))" }
        Status   = 'Success'
        Headline = "$($rows.Count) hunting query(ies) on $($workspace.Name): $(@($rows | Where-Object Source -EQ 'This module').Count) from this module, $(@($rows | Where-Object Source -EQ 'Elsewhere').Count) from elsewhere"
        Tiles    = @(
            @{ Value = '{0:N0}' -f $rows.Count; Label = 'hunting queries'; Tone = 'info'; Table = 'queries' }
            @{ Value = '{0:N0}' -f @($rows | Where-Object Source -EQ 'This module').Count; Label = 'from this module'; Tone = 'violet'; Table = 'queries'; Filters = @{ Source = 'This module' } }
            @{ Value = '{0:N0}' -f @($rows | Where-Object Source -EQ 'Elsewhere').Count; Label = 'from elsewhere'; Tone = 'neutral'; Table = 'queries'; Filters = @{ Source = 'Elsewhere' } }
            @{ Value = '{0:N0}' -f @($rows | Where-Object Edited).Count; Label = 'edited since deployed'; Tone = 'warn'; Table = 'queries' }
        )
        Tables   = @(
            @{ Id = 'queries'; Title = 'Hunting queries on the workspace'; Section = 'Queries'; Rows = $rows; Noun = 'queries'; File = 'sentinel-installed-hunting-queries'; GroupBy = @('Source'); ConsoleLimit = 30
                Empty = 'This workspace has no hunting queries in its saved searches.'; EmptyStatus = 'Info'; Hover = @('Description', 'Query'); HoverTitle = 'Name'
                Columns = @(
                    @{ Key = 'Name'; Label = 'Query'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'Tactics'; Label = 'Tactics'; Console = $true; Pdf = $true }
                    @{ Key = 'Source'; Label = 'Source'; Type = 'badge'; Tones = @{ 'This module' = 'info'; Elsewhere = 'neutral' }; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Edited'; Label = 'Edited'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Version'; Label = 'Version'; Console = $true }
                    @{ Key = 'Techniques'; Label = 'Techniques'; Hidden = $true }
                    @{ Key = 'Origin'; Label = 'Origin'; Type = 'mono'; Hidden = $true }
                    @{ Key = 'Id'; Label = 'ID'; Type = 'mono'; Hidden = $true }
                    @{ Key = 'Description'; Label = 'Description'; Type = 'wide'; Hidden = $true }
                    @{ Key = 'Query'; Label = 'KQL'; Type = 'wide'; Hidden = $true }
                ) }
        )
        Hint     = 'Find-AACSentinelHuntingQuery lists what could be added; -PassThru returns the queries with their KQL.'
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $rows -Noun 'hunting query' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $rows -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
