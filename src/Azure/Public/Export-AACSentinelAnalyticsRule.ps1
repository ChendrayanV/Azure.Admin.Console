function Export-AACSentinelAnalyticsRule {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Backs up the analytics rules of a Microsoft Sentinel workspace - and,
        with -IncludeAutomationRule, its automation rules - as one JSON file
        per rule: ARM deployment templates ready for source control, Sentinel
        Repositories or another workspace.
    .DESCRIPTION
        Reads the rules from Azure Resource Manager - read-only in Azure,
        nothing there is changed - and writes a file per rule into -Path
        (automation rules into -Path\AutomationRules):

          -Format ArmTemplate   (the default) the template the Sentinel portal
                                exports: deploy it to any workspace with
                                New-AzResourceGroupDeployment, the Azure CLI or
                                Sentinel Repositories, giving the workspace's
                                name as the 'workspace' parameter
          -Format Json          the rule as the API returns it

        Properties Azure sets itself (last modified, created by) are left out,
        and keys are sorted, so exporting an unchanged rule again gives the
        same file: commit the folder and the diff shows what changed. A file
        name is the rule's display name; two rules with one name get the rule
        ID added. Files already there are left alone unless -Force; -WhatIf
        shows what would be written.

        Needs Microsoft Sentinel Reader on the workspace.
    .PARAMETER WorkspaceId
        The workspace: its workspace ID (GUID), resource ID or name.
    .PARAMETER Path
        The folder to write the files into. It is created if missing.
    .PARAMETER SubscriptionId
        Where to look for a workspace given by ID (GUID) or name. Every
        subscription the account can see by default.
    .PARAMETER ResourceGroupName
        Narrows a workspace given by name, when the name is in more than one
        resource group.
    .PARAMETER Name
        Only rules whose display name or rule ID matches; wildcards work.
    .PARAMETER Kind
        Only analytics rules of these kinds (Scheduled, NRT, Fusion,
        MicrosoftSecurityIncidentCreation, MLBehaviorAnalytics,
        ThreatIntelligence).
    .PARAMETER State
        Only Enabled or only Disabled analytics rules.
    .PARAMETER IncludeAutomationRule
        Also export the automation rules, into an AutomationRules folder.
    .PARAMETER Format
        ArmTemplate (deployable; the default) or Json (the rule as read).
    .PARAMETER Force
        Overwrite files that are already there.
    .PARAMETER PassThru
        Show the view and also return what was written.
    .PARAMETER NoDisplay
        Return what was written without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once instead of a page at a time.
    .EXAMPLE
        Connect-AAC
        Export-AACSentinelAnalyticsRule -WorkspaceId 'law-contoso-sentinel' -Path .\sentinel\rules
        Every analytics rule as an ARM template, one file each.
    .EXAMPLE
        Export-AACSentinelAnalyticsRule -WorkspaceId 'law-contoso-sentinel' -Path .\sentinel -IncludeAutomationRule -Force
        Analytics and automation rules, overwriting the last backup - commit the folder to see what changed.
    .EXAMPLE
        Export-AACSentinelAnalyticsRule -WorkspaceId 'law-contoso-sentinel' -Path .\out\custom -Kind Scheduled, NRT -State Enabled -WhatIf
        Which files the enabled scheduled and NRT rules would be written to, writing nothing.
    .EXAMPLE
        Export-AACSentinelAnalyticsRule -WorkspaceId 'law-contoso-sentinel' -Path .\out\rules -NoDisplay | ForEach-Object { New-AzResourceGroupDeployment -ResourceGroupName rg-contoso-sec-dr -TemplateFile $_.File -workspace law-contoso-sentinel-dr }
        Copy every rule to a second workspace (Az.Resources does the deploying).
    .OUTPUTS
        AAC.SentinelRuleExport (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('AAC.SentinelRuleExport')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [Alias('Workspace', 'WorkspaceName', 'ResourceId')]
        [ValidateNotNullOrEmpty()]
        [string] $WorkspaceId,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string] $ResourceGroupName,

        [SupportsWildcards()]
        [string[]] $Name,

        [ValidateSet('Scheduled', 'NRT', 'Fusion', 'MicrosoftSecurityIncidentCreation', 'MLBehaviorAnalytics', 'ThreatIntelligence')]
        [string[]] $Kind,

        [ValidateSet('Enabled', 'Disabled')]
        [string] $State,

        [switch] $IncludeAutomationRule,

        [ValidateSet('ArmTemplate', 'Json')]
        [string] $Format = 'ArmTemplate',

        [switch] $Force,

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
    $folder = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    if (Test-Path -LiteralPath $folder -PathType Leaf) {
        throw [System.IO.IOException]::new("Azure Admin Console can't write into $folder`: it is a file. Give -Path a folder.")
    }
    $insights = 'providers/Microsoft.SecurityInsights'
    $arm = [ordered]@{ alertRules = "$insights/alertRules?api-version=2025-09-01" }
    if ($IncludeAutomationRule) { $arm['automationRules'] = "$insights/automationRules?api-version=2025-09-01" }
    # Read here, not inside the progress block (it runs in Invoke-AACProgress's scope).
    $request = @{ Target = $WorkspaceId.Trim(); SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ResourceGroupName = $ResourceGroupName; Arm = $arm }

    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Export Microsoft Sentinel rules' -Color 'deepskyblue3_1' }
    $read = Invoke-AACProgress -ScriptBlock {
        $null = Get-AACAccessToken
        Update-AACProgress -Id 'read' -Indeterminate -Description "Reading the rules of $($request.Target)"
        $workspace = Read-AACSentinelWorkspace -Target $request.Target -SubscriptionId $request.SubscriptionId -ResourceGroupName $request.ResourceGroupName -Arm $request.Arm
        Update-AACProgress -Id 'read' -Complete -Description "Workspace $($workspace.Name): rules read"
        $workspace
    }
    foreach ($key in @($arm.Keys)) {
        if ($read.Arm[$key].Error) {
            $problem = [System.InvalidOperationException]::new("Azure Admin Console couldn't read the $(@{ alertRules = 'analytics'; automationRules = 'automation' }[$key]) rules of $($read.Name): $($read.Arm[$key].Error)")
            $problem.Data['AACHint'] = 'Your account needs Microsoft Sentinel Reader on the workspace.'
            throw $problem
        }
    }

    # --- Which rules ------------------------------------------------------------------------------------------
    $matchesAny = { param([string[]] $Value, [string[]] $Pattern) foreach ($v in $Value) { foreach ($p in $Pattern) { if ($v -and $v -like $p) { return $true } } }; $false }
    $label = { param($Rule) @([string]$Rule['name'], $(if ($Rule['properties'] -is [System.Collections.IDictionary]) { [string]$Rule['properties']['displayName'] })) }
    $analytics = @($read.Arm['alertRules'].Items | Where-Object { $_ -is [System.Collections.IDictionary] })
    if ($Name) { $analytics = @($analytics | Where-Object { & $matchesAny (& $label $_) $Name }) }
    if ($Kind) { $analytics = @($analytics | Where-Object { $Kind -contains [string]$_['kind'] }) }
    if ($State) { $analytics = @($analytics | Where-Object { [bool]($_['properties'] -is [System.Collections.IDictionary] -and $_['properties']['enabled']) -eq ($State -eq 'Enabled') }) }
    $automation = @(if ($IncludeAutomationRule) { $read.Arm['automationRules'].Items | Where-Object { $_ -is [System.Collections.IDictionary] } })
    if ($Name) { $automation = @($automation | Where-Object { & $matchesAny (& $label $_) $Name }) }
    $files = @(ConvertTo-AACSentinelRuleExport -AnalyticsRule $analytics -AutomationRule $automation -Format $Format)

    # --- The files --------------------------------------------------------------------------------------------
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $results = @(foreach ($file in $files) {
            $target = Join-Path -Path $folder -ChildPath $file.FileName
            $status = if ((Test-Path -LiteralPath $target -PathType Leaf) -and -not $Force) { 'Exists' }
            elseif ($PSCmdlet.ShouldProcess($target, "Write the $($file.Type.ToLowerInvariant()) '$($file.Name)'")) {
                # Not New-Item: a '[' in the folder's name would be read as a wildcard.
                $null = [System.IO.Directory]::CreateDirectory((Split-Path -Path $target -Parent))
                [System.IO.File]::WriteAllText($target, "$($file.Content)`n", $utf8)
                'Written'
            }
            else { 'Skipped' }
            [pscustomobject][ordered]@{
                PSTypeName = 'AAC.SentinelRuleExport'
                Name       = $file.Name
                Type       = $file.Type
                Kind       = $file.Kind
                Enabled    = $file.Enabled
                Status     = $status
                File       = $target
                RuleId     = $file.RuleId
            }
        })

    # --- The report -------------------------------------------------------------------------------------------
    $written = @($results | Where-Object Status -EQ 'Written').Count
    $exists = @($results | Where-Object Status -EQ 'Exists').Count
    $skipped = @($results | Where-Object Status -EQ 'Skipped').Count
    $headline = if (-not $results.Count) { "No rules match on $($read.Name): nothing to export." }
    elseif ($exists) { "$written file(s) written to $folder; $exists left alone because they are already there - add -Force to overwrite them" }
    elseif ($skipped -and -not $written) { "$skipped file(s) would be written to $folder." }
    else { "$written file(s) written to $folder." }
    $report = @{
        Facts    = [ordered]@{ Workspace = "$($read.Name) ($($read.ResourceGroup))"; Format = $Format }
        Status   = $(if ($exists) { 'Warning' } else { 'Success' })
        Headline = $headline
        Tiles    = @(
            @{ Value = '{0:N0}' -f @($results | Where-Object Type -EQ 'Analytics rule').Count; Label = 'analytics rules'; Tone = 'info' }
            @{ Value = '{0:N0}' -f @($results | Where-Object Type -EQ 'Automation rule').Count; Label = 'automation rules'; Tone = 'violet' }
            @{ Value = '{0:N0}' -f $written; Label = 'written'; Tone = 'good' }
            @{ Value = '{0:N0}' -f $exists; Label = 'already there'; Tone = $(if ($exists) { 'warn' } else { 'good' }) }
        )
        Tables   = @(
            @{ Id = 'files'; Title = 'Exported rules'; Section = 'Files'; Rows = $results; Noun = 'rules'; ConsoleLimit = 40
                Empty = 'No rules match the filters.'; EmptyStatus = 'Info'
                Columns = @(
                    @{ Key = 'Name'; Label = 'Rule'; Type = 'wide'; Console = $true }
                    @{ Key = 'Type'; Label = 'Type'; Console = $true }
                    @{ Key = 'Kind'; Label = 'Kind'; Console = $true }
                    @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = @{ Written = 'good'; Exists = 'warn'; Skipped = 'neutral' }; Console = $true }
                    @{ Key = 'File'; Label = 'File'; Type = 'mono'; Console = $true }
                ) }
        )
        Hint     = '-IncludeAutomationRule adds automation rules; -Force overwrites; -WhatIf writes nothing. Deploy a file with its workspace parameter set to the target workspace''s name.'
    }
    Invoke-AACReportOutput -Report $report -Title 'Microsoft Sentinel rules exported' -ShowView:$interactive -NoPaging:$NoPaging -Object $results -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
