function Get-AACSentinelPlaybook {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Lists the Microsoft Sentinel playbooks - Logic Apps with a Sentinel
        trigger - with the automation rules that run them, their runs and
        failures over the last days, and whether Sentinel is allowed to run
        them: disabled playbooks still in use, missing permissions, failing
        runs and missing playbooks called out.
    .DESCRIPTION
        Reads - read-only, nothing is changed - from:
          Azure Resource Graph     every Logic App whose trigger is a
                                   Microsoft Sentinel one (incident, alert or
                                   entity), in the subscriptions searched
          Azure Resource Manager   the workspace's automation rules, each
                                   playbook's runs over -Days, and the role
                                   assignments on each playbook's resource
                                   group

        Each playbook: Name, State, Trigger (Incident, Alert, Entity),
        AutomationRules and RuleNames (the rules that run it), Runs, Failed,
        FailurePercent, LastRun, LastError, SentinelCanRun, SentinelAuth
        (ManagedIdentity or Connection), Identity, Severity, Findings,
        ResourceGroup, SubscriptionId, Location, LastModified and ResourceId.

        Findings:
          High     disabled, but an enabled automation rule runs it; no
                   Microsoft Sentinel Automation Contributor on its resource
                   group, so Sentinel can't run it; an automation rule runs a
                   playbook that isn't there (State Missing)
          Medium   runs that failed in the period
          Low      its Sentinel connection signs in as an account rather
                   than a managed identity; no live automation rule runs it

        SentinelCanRun counts any assignment of the role on the resource group
        or above: checking it is Sentinel's own principal would need
        Microsoft Graph. A playbook can also be started by hand from an
        incident, so one no rule runs isn't necessarily unused.

        Needs Microsoft Sentinel Reader on the workspace and Reader (or Logic
        App Operator) on the playbooks.
    .PARAMETER WorkspaceId
        The workspace: its workspace ID (GUID), resource ID or name.
    .PARAMETER SubscriptionId
        Where to look for the workspace, if given by ID or name, and for the
        playbooks. Every subscription the account can see by default.
    .PARAMETER ResourceGroupName
        Narrows a workspace given by name, when the name is in more than one
        resource group.
    .PARAMETER Name
        Only playbooks whose name matches; wildcards work.
    .PARAMETER Trigger
        Only playbooks with these triggers (Incident, Alert, Entity).
    .PARAMETER Days
        How far back to read the runs: 1 to 90 days, 7 by default.
    .PARAMETER CsvPath
        Write the playbooks to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report to this file.
    .PARAMETER PdfPath
        Write a PDF report to this file.
    .PARAMETER Title
        The HTML and PDF reports' title.
    .PARAMETER PassThru
        Show the view and also return the playbooks.
    .PARAMETER NoDisplay
        Return the playbooks without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once instead of a page at a time.
    .EXAMPLE
        Connect-AAC
        Get-AACSentinelPlaybook -WorkspaceId 'law-contoso-sentinel'
        Every Sentinel playbook, the ones with findings first.
    .EXAMPLE
        Get-AACSentinelPlaybook -WorkspaceId 'law-contoso-sentinel' -Days 30 -NoDisplay | Where-Object Failed -GT 0 | Select-Object Name, Runs, Failed, LastError
        The playbooks that failed in the last 30 days, and why.
    .EXAMPLE
        Get-AACSentinelPlaybook -WorkspaceId 'law-contoso-sentinel' -Trigger Incident -HtmlPath .\out\Playbooks.html
        The incident-triggered playbooks, as an interactive HTML report.
    .OUTPUTS
        AAC.SentinelPlaybook (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.SentinelPlaybook')]
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

        [ValidateSet('Incident', 'Alert', 'Entity')]
        [string[]] $Trigger,

        [ValidateRange(1, 90)]
        [int] $Days = 7,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Microsoft Sentinel playbooks',

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
    # The Sentinel connector's triggers name it 'azuresentinel' in their connection.
    $graphQuery = @'
resources
| where type =~ 'microsoft.logic/workflows'
| extend triggers = properties.definition.triggers
| where tostring(triggers) has 'azuresentinel'
| project id, name, resourceGroup, subscriptionId, location, state = tostring(properties.state), identityType = tostring(identity.type), triggers, connections = properties.parameters['$connections'].value, changedTime = tostring(properties.changedTime)
'@
    $since = [datetime]::UtcNow.AddDays(-$Days).ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture)
    # Read here, not inside the progress block (it runs in Invoke-AACProgress's scope).
    $request = @{ Target = $WorkspaceId.Trim(); SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ResourceGroupName = $ResourceGroupName; Graph = $graphQuery; Since = $since; Days = $Days }

    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Microsoft Sentinel playbooks' -Color 'deepskyblue3_1' }
    $outcome = Invoke-AACProgress -ScriptBlock {
        $null = Get-AACAccessToken
        Update-AACProgress -Id 'read' -Indeterminate -Description "Reading the automation rules of $($request.Target)"
        $read = Read-AACSentinelWorkspace -Target $request.Target -SubscriptionId $request.SubscriptionId -ResourceGroupName $request.ResourceGroupName -Arm ([ordered]@{ automationRules = 'providers/Microsoft.SecurityInsights/automationRules?api-version=2025-09-01' })
        Update-AACProgress -Id 'read' -Complete -Description "Workspace $($read.Name): automation rules read"

        Update-AACProgress -Id 'find' -Indeterminate -Description 'Finding the Logic Apps with a Sentinel trigger'
        $graph = @{ Query = @{ playbooks = $request.Graph } }
        if ($request.SubscriptionId.Count) { $graph.SubscriptionId = $request.SubscriptionId }
        $workflows = @((Invoke-AACGraphBatch @graph).Rows['playbooks'] | Where-Object { $null -ne $_ })
        Update-AACProgress -Id 'find' -Complete -Description "$($workflows.Count) playbook(s) found"

        # Runs per playbook, and role assignments once per resource group.
        $runUris = [ordered]@{}
        $roleUris = [ordered]@{}
        foreach ($w in $workflows) {
            $id = ([string]$w['id']).TrimEnd('/')
            $runUris[$id.ToLowerInvariant()] = "$id/runs?api-version=2016-06-01&`$filter=$([uri]::EscapeDataString("startTime ge $($request.Since)"))"
            $group = (($id -split '/')[0..4] -join '/').ToLowerInvariant()
            $roleUris[$group] = "$group/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&`$filter=atScope()"
        }
        $runs = @{}
        $roles = @{}
        if ($runUris.Count) {
            Update-AACProgress -Id 'runs' -Total ($runUris.Count + $roleUris.Count) -Description 'Reading the runs and permissions'
            $readAll = Invoke-AACArmParallel -Uri @(@($runUris.Values) + @($roleUris.Values)) -OnProgress { param($Done, $Total) Update-AACProgress -Id 'runs' -Increment 1 -Description "Reading the runs and permissions ($Done of $Total)" }
            foreach ($k in $runUris.Keys) { $runs[$k] = $readAll[$runUris[$k]] }
            foreach ($k in $roleUris.Keys) { $roles[$k] = $readAll[$roleUris[$k]] }
            Update-AACProgress -Id 'runs' -Complete -Description "Read the runs of the last $($request.Days) day(s)"
        }
        $automation = @(if (-not $read.Arm['automationRules'].Error) { $read.Arm['automationRules'].Items })
        $playbooks = @(ConvertTo-AACSentinelPlaybook -Workflow $workflows -Run $runs -AutomationRule $automation -RoleAssignment $roles -Days $request.Days)
        @{ Read = $read; Playbooks = $playbooks }
    }
    $read = $outcome.Read
    $notices = [System.Collections.Generic.List[hashtable]]::new()
    if ($read.Arm['automationRules'].Error) { $notices.Add(@{ Status = 'Warning'; Text = "The automation rules couldn't be read, so no playbook shows the rules that run it: $($read.Arm['automationRules'].Error)" }) }
    $runErrors = @($outcome.Playbooks | Where-Object RunsError).Count
    if ($runErrors) { $notices.Add(@{ Status = 'Warning'; Text = "The runs of $runErrors playbook(s) couldn't be read (Runs is blank): your account needs Reader on them." }) }
    if (@($outcome.Playbooks | Where-Object { $_.State -ne 'Missing' -and $null -eq $_.SentinelCanRun }).Count) { $notices.Add(@{ Status = 'Info'; Text = 'The role assignments of some resource groups couldn''t be read, so SentinelCanRun is blank for their playbooks.' }) }

    $playbooks = @($outcome.Playbooks)
    if ($Name) { $playbooks = @($playbooks | Where-Object { $p = $_; @($Name | Where-Object { $p.Name -like $_ }).Count }) }
    if ($Trigger) { $playbooks = @($playbooks | Where-Object { $Trigger -contains $_.Trigger }) }

    # --- The report -------------------------------------------------------------------------------------------
    $severityTones = @{ High = 'bad'; Medium = 'warn'; Low = 'info' }
    $high = @($playbooks | Where-Object Severity -EQ 'High').Count
    $failing = @($playbooks | Where-Object { $_.Failed -gt 0 }).Count
    $totalRuns = [int](@($playbooks | ForEach-Object { $_.Runs } | Where-Object { $null -ne $_ } | Measure-Object -Sum).Sum)
    $totalFailed = [int](@($playbooks | ForEach-Object { $_.Failed } | Where-Object { $null -ne $_ } | Measure-Object -Sum).Sum)
    $headline = if (-not $playbooks.Count) { 'No Sentinel playbooks found in the subscriptions searched.' }
    else { "$($playbooks.Count) playbook(s): $high need attention now, $failing with failed runs ($totalFailed of $totalRuns run(s) in $Days day(s))" }
    $report = @{
        Subtitle = 'Microsoft Sentinel playbooks: what runs them, whether they work, and whether Sentinel may run them'
        Facts    = [ordered]@{ Workspace = "$($read.Name) ($($read.ResourceGroup))"; Runs = "last $Days day(s)" }
        Status   = $(if ($high) { 'Failed' } elseif ($failing) { 'Warning' } else { 'Success' })
        Headline = $headline
        Tiles    = @(
            @{ Value = '{0:N0}' -f $playbooks.Count; Label = 'playbooks'; Tone = 'info'; Table = 'playbooks' }
            @{ Value = '{0:N0}' -f $high; Label = 'high findings'; Tone = $(if ($high) { 'bad' } else { 'good' }); Table = 'playbooks'; Filters = @{ Severity = 'High' } }
            @{ Value = '{0:N0}' -f $failing; Label = 'with failed runs'; Tone = $(if ($failing) { 'warn' } else { 'good' }) }
            @{ Value = '{0:N0}' -f $totalRuns; Label = "runs ($Days days)"; Tone = 'neutral' }
            @{ Value = $(if ($totalRuns) { '{0:N1}%' -f (100 * $totalFailed / $totalRuns) } else { '-' }); Label = 'runs failed'; Tone = $(if ($totalFailed) { 'warn' } else { 'good' }) }
        )
        Notices  = @($notices)
        Charts   = @(
            @{ Title = 'Playbooks by trigger'; Kind = 'donut'; CenterLabel = 'playbooks'; Items = @($playbooks | Where-Object Trigger | Group-Object Trigger | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'playbooks'; Column = 'Trigger' }
            @{ Title = 'Most failed runs'; Items = @($playbooks | Where-Object { $_.Failed -gt 0 } | Sort-Object Failed -Descending | Select-AACFirst 10 | ForEach-Object { @{ Label = $_.Name; Value = $_.Failed; Filter = $_.Name } }); Table = 'playbooks'; Column = 'Name'; Tone = 'bad'; Console = $true }
            @{ Title = 'Most runs'; Items = @($playbooks | Where-Object { $_.Runs -gt 0 } | Sort-Object Runs -Descending | Select-AACFirst 10 | ForEach-Object { @{ Label = $_.Name; Value = $_.Runs; Filter = $_.Name } }); Table = 'playbooks'; Column = 'Name'; Tone = 'info' }
        )
        Tables   = @(
            @{ Id = 'playbooks'; Title = 'Playbooks'; Section = 'Playbooks'; Rows = $playbooks; Noun = 'playbooks'; File = 'sentinel-playbooks'; GroupBy = @('Severity', 'Trigger', 'State', 'ResourceGroup'); ConsoleLimit = 30
                Empty = 'No Logic Apps with a Microsoft Sentinel trigger were found.'; EmptyStatus = 'Info'; Hover = @('Findings', 'LastError', 'RuleNames'); HoverTitle = 'Name'
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $severityTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Name'; Label = 'Playbook'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'State'; Label = 'State'; Type = 'badge'; Tones = @{ Enabled = 'good'; Disabled = 'neutral'; Missing = 'bad' }; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Trigger'; Label = 'Trigger'; Facet = $true; Console = $true }
                    @{ Key = 'AutomationRules'; Label = 'Rules'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'Runs'; Label = 'Runs'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'Failed'; Label = 'Failed'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'Findings'; Label = 'Findings'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'LastRun'; Label = 'Last run'; Type = 'datetime' }
                    @{ Key = 'LastError'; Label = 'Last error'; Type = 'wide' }
                    @{ Key = 'SentinelCanRun'; Label = 'Sentinel can run'; Facet = $true }
                    @{ Key = 'SentinelAuth'; Label = 'Sentinel connection'; Facet = $true }
                    @{ Key = 'Identity'; Label = 'Identity'; Facet = $true }
                    @{ Key = 'RuleNames'; Label = 'Automation rules'; Type = 'wide'; Hidden = $true }
                    @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                    @{ Key = 'SubscriptionId'; Label = 'Subscription'; Type = 'mono'; Hidden = $true }
                    @{ Key = 'ResourceId'; Label = 'Resource ID'; Type = 'mono'; Hidden = $true }
                ) }
        )
        Hint     = '-Days reads further back; -Trigger and -Name narrow the list; -SubscriptionId says where to look for playbooks.'
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $playbooks -Noun 'playbook' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $playbooks -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
