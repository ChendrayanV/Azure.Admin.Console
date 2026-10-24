function Get-AACTerraformPlan {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Reads a Terraform plan in JSON (terraform show -json) and flattens it
        into what will be created, updated, replaced, deleted, read, imported
        and moved - down to each attribute's before and after value - with a
        Spectre.Console view, objects, and CSV and interactive HTML reports.
    .DESCRIPTION
        Reads the whole plan file - every resource change, the outputs, and
        what changed outside Terraform since the last run (resource_drift) -
        and flattens it so it reads at a glance. Offline: no Azure sign-in,
        no Terraform needed, nothing changed.

        Make the JSON from a saved plan:

          terraform plan -out tfplan
          terraform show -json tfplan > plan.json

        A binary plan (tfplan), Terraform state or any other JSON is refused,
        with what to run instead. UTF-16 files (Windows PowerShell's >) are
        read as well.

        One row per resource (AAC.TerraformChange): Action, Address, Module,
        Type, Name, Index, Provider, the Azure name, resource group,
        location and ID where the resource has them, Reason (why it is
        replaced or deleted), ReplaceOrder, ReplacePaths (the attributes
        that force the replacement), PreviousAddress (moved), Importing,
        Deposed (the old copy a failed create_before_destroy left behind),
        ChangedAttributes and Attributes. Actions: Create, Update, Replace,
        Delete, Read (data sources), Import, Move, Forget and NoOp. Outputs
        are rows too, with Mode 'output' and Address 'output.<name>'.

        -ExpandAttribute returns one row per changed attribute instead
        (AAC.TerraformAttributeChange): Address, Attribute, Change (Added,
        Removed, Modified, Known after apply, Reordered, Reformatted),
        Before, After, ForcesReplacement and Sensitive. Nested values are flattened to a
        path:
          tags["cost.centre"]                       a map key
          site_config[0].always_on                  a nested block
          security_rule[name=ssh].destination_port_range
                                                    a block in a list,
                                                    by its name
          policy_rule{json}.then.effect             inside a JSON string
        Updates and replacements list only what changes. Blocks in a list
        are matched by content, then by name, then in order - a rule added
        to an NSG doesn't show every rule after it as changed.

        Checks (check blocks, preconditions, postconditions) that fail, or
        can't be known until apply, are listed with their messages.

        Sensitive values are never shown or returned: the plan JSON holds
        them in clear text, and they come back as '(sensitive)'. Values
        Terraform knows only after apply read '(known after apply)'.

        What you get depends on where the command runs:
          at the prompt    Terraform's summary (to add, change, destroy),
                           tiles, then the deletes, replacements, updates,
                           creates and the rest - each with its attribute
                           changes - the outputs and the drift, a page at
                           a time
          piped onward     the rows, with no view
          -PassThru        the view and the rows
          -NoDisplay       the rows only
        -CsvPath writes the rows returned (resources, or attributes with
        -ExpandAttribute). -HtmlPath writes an interactive report: tiles and
        charts that filter tables of the resources, every attribute change,
        the outputs and the drift - each searchable and downloadable as CSV.
    .PARAMETER Path
        The plan in JSON: terraform show -json tfplan > plan.json.
    .PARAMETER Action
        Only these actions: Create, Update, Replace, Delete, Read, Import,
        Move, Forget, NoOp. Every action but NoOp by default.
    .PARAMETER Address
        Only resources whose address matches one of these (wildcards):
        'module.network.*', '*azurerm_key_vault*'.
    .PARAMETER ResourceType
        Only these resource types (wildcards): 'azurerm_storage_account',
        'azurerm_network_*'.
    .PARAMETER ExpandAttribute
        Return (and write to -CsvPath) one row per changed attribute, not
        per resource.
    .PARAMETER IncludeDrift
        Also return the changes made outside Terraform (Source 'Drift').
        The view always shows them.
    .PARAMETER CsvPath
        Write the rows to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report to this file.
    .PARAMETER Title
        The HTML report's title.
    .PARAMETER PassThru
        Show the view and also return the rows.
    .PARAMETER NoDisplay
        Return the rows without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once instead of a page at a time.
    .EXAMPLE
        terraform plan -out tfplan
        terraform show -json tfplan > plan.json
        Get-AACTerraformPlan -Path .\plan.json
        What the plan changes, at the prompt.
    .EXAMPLE
        Get-AACTerraformPlan -Path .\plan.json -Action Delete, Replace -NoDisplay | Select-Object Address, ResourceName, Reason, ReplacePaths
        Everything the plan destroys, and why.
    .EXAMPLE
        Get-AACTerraformPlan -Path .\plan.json -ExpandAttribute -NoDisplay | Where-Object ForcesReplacement
        The attribute changes that force a replacement.
    .EXAMPLE
        Get-AACTerraformPlan -Path .\plan.json -HtmlPath .\out\Plan.html -CsvPath .\out\Plan.csv -ExpandAttribute
        An HTML report, and every attribute change as CSV - for a pull request or a pipeline artifact.
    .OUTPUTS
        AAC.TerraformChange, or AAC.TerraformAttributeChange with -ExpandAttribute (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.TerraformChange', 'AAC.TerraformAttributeChange')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [Alias('FullName', 'PlanFile')]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [ValidateSet('Create', 'Update', 'Replace', 'Delete', 'Read', 'Import', 'Move', 'Forget', 'NoOp')]
        [string[]] $Action,

        [ValidateNotNullOrEmpty()]
        [string[]] $Address,

        [ValidateNotNullOrEmpty()]
        [string[]] $ResourceType,

        [switch] $ExpandAttribute,

        [switch] $IncludeDrift,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $Title = 'Terraform plan',

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
    $showView = $interactive -and -not ($CsvPath -or $HtmlPath)
    $returnObjects = $PassThru -or $NoDisplay -or $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $planFullPath = & $resolve $Path
    $csvFullPath = & $resolve $CsvPath
    $htmlFullPath = & $resolve $HtmlPath

    if ($interactive) {
        Write-AACRule -Title 'Azure Admin Console :: Terraform plan' -Color 'mediumpurple2'
    }
    # The filters, read here: the script block below runs inside
    # Invoke-AACProgress, and is safer not reaching back for parameters.
    $filter = @{
        Action          = @($Action | Where-Object { $_ })
        Address         = @($Address | Where-Object { $_ })
        ResourceType    = @($ResourceType | Where-Object { $_ })
        ExpandAttribute = [bool]$ExpandAttribute
        IncludeDrift    = [bool]$IncludeDrift
        Title           = $Title
    }
    $state = Invoke-AACProgress -ScriptBlock {
        $fileName = Split-Path -Path $planFullPath -Leaf
        $showJson = "terraform show -json $(if ($fileName -match '\.json$') { 'tfplan' } else { $fileName }) > plan.json"
        $refuse = {
            param([string] $Message, [string] $Hint)
            $problem = [System.InvalidOperationException]::new($Message)
            $problem.Data['AACHint'] = $Hint
            throw $problem
        }
        if (-not (Test-Path -LiteralPath $planFullPath -PathType Leaf)) {
            & $refuse "No file at '$planFullPath'." "Save the plan and convert it to JSON: terraform plan -out tfplan, then terraform show -json tfplan > plan.json."
        }
        Update-AACProgress -Id 'read' -Description "Reading $fileName" -Indeterminate
        # A saved plan (terraform plan -out) is a zip file: 'PK' first.
        $head = [byte[]]::new(2)
        $stream = [System.IO.File]::OpenRead($planFullPath)
        try { $null = $stream.Read($head, 0, 2) } finally { $stream.Dispose() }
        if ($head[0] -eq 0x50 -and $head[1] -eq 0x4B) {
            & $refuse "'$fileName' is a binary Terraform plan, not JSON." "Convert it first: $showJson"
        }
        # ReadAllText follows the byte order mark: UTF-8, or UTF-16 from
        # Windows PowerShell's > redirection.
        $text = [System.IO.File]::ReadAllText($planFullPath)
        try {
            $plan = ConvertFrom-Json -InputObject $text -AsHashtable -ErrorAction Stop
        }
        catch {
            & $refuse "'$fileName' isn't valid JSON: $($_.Exception.Message)" "Make the JSON with Terraform itself: $showJson"
        }
        if ($plan -isnot [System.Collections.IDictionary] -or -not $plan.Contains('format_version')) {
            & $refuse "'$fileName' isn't Terraform's JSON output: it has no format_version." "Make it with: $showJson"
        }
        if (-not ($plan.Contains('resource_changes') -or $plan.Contains('output_changes') -or $plan.Contains('planned_values'))) {
            & $refuse "'$fileName' is Terraform state, not a plan: it has no planned changes." "Run terraform show -json on a saved plan file, not on its own: terraform plan -out tfplan, then terraform show -json tfplan > plan.json."
        }
        $text = $null

        $total = @($plan['resource_changes']).Count + @($plan['resource_drift']).Count
        Update-AACProgress -Id 'read' -Total ([Math]::Max($total, 1)) -Description "Flattening $total resource change(s) in $fileName"
        $tick = @{ Done = 0 }
        $result = ConvertTo-AACTerraformPlan -Plan $plan -Path $planFullPath -OnProgress {
            param($Done, $Total)
            Update-AACProgress -Id 'read' -Increment ($Done - $tick.Done) -Description "Flattening the resource changes ($Done of $Total)"
            $tick.Done = $Done
        }
        $plan = $null
        $stats = $result.Stats
        Update-AACProgress -Id 'read' -Complete -Description ('{0}: {1:N0} to add, {2:N0} to change, {3:N0} to destroy - {4:N0} attribute change(s)' -f $fileName, $stats.ToAdd, $stats.ToChange, $stats.ToDestroy, $stats.Attributes)

        # The filters: actions (all but no-op by default), addresses, types.
        $actions = if ($filter.Action) { $filter.Action } else { 'Create', 'Update', 'Replace', 'Delete', 'Read', 'Import', 'Move', 'Forget' }
        $like = { param([string] $Value, [string[]] $Pattern) foreach ($item in $Pattern) { if ($Value -like $item) { return $true } }; $false }
        $selected = @($result.Changes | Where-Object {
                $_.Action -in $actions -and
                (-not $filter.Address -or (& $like $_.Address $filter.Address)) -and
                (-not $filter.ResourceType -or ($_.Mode -ne 'output' -and (& $like $_.Type $filter.ResourceType)))
            })
        $result['Selected'] = $selected
        $result['Filtered'] = [bool]($filter.Action -or $filter.Address -or $filter.ResourceType)

        $notices = [System.Collections.Generic.List[string]]::new()
        $hasChanges = [bool]($stats.ToAdd + $stats.ToChange + $stats.ToDestroy + $stats.Import + $stats.Move + $stats.Read + $stats.Forget + $stats.Outputs)
        if ($result.Info.Errored) { $notices.Add('Terraform hit an error while planning: this plan is incomplete and can''t be applied. Fix the errors terraform plan reported and plan again.') }
        elseif ($false -eq $result.Info.Applyable -and $hasChanges) { $notices.Add('Terraform marked this plan as not applyable.') }
        elseif ($false -eq $result.Info.Complete) { $notices.Add('This plan is incomplete: applying it leaves changes for another plan (deferred or partial changes).') }
        foreach ($check in @($result.Info.Checks)) {
            $what = if ($check.Status -eq 'unknown') { 'can''t be checked until apply' } else { "fails ($($check.Status))" }
            $notices.Add("Check $($check.Address) $what$(if ($check.Problems) { ': ' + ($check.Problems -join ' ') })")
        }
        if ($stats.Sensitive) { $notices.Add("$($stats.Sensitive) sensitive value(s) are hidden as '(sensitive)'.") }
        if (-not $hasChanges) { $notices.Add('No changes: the infrastructure matches the configuration.') }
        elseif ($result.Filtered -and -not $selected.Count) { $notices.Add('No changes match -Action, -Address or -ResourceType.') }
        $result['Notice'] = $notices.ToArray()

        $rows = [System.Collections.Generic.List[object]]::new()
        foreach ($change in $selected) {
            if (-not $filter.IncludeDrift -and $change.Source -ne 'Plan') { continue }
            if ($filter.ExpandAttribute) { $rows.AddRange([object[]]$change.Attributes) } else { $rows.Add($change) }
        }
        $rows = $rows.ToArray()
        $result['Rows'] = $rows
        $detail = [ordered]@{ 'Plan file' = $planFullPath }
        if ($result.Info.TerraformVersion) { $detail['Terraform'] = "v$($result.Info.TerraformVersion) (format $($result.Info.FormatVersion))" }
        if ($result.Info.Timestamp) { $detail['Planned'] = [string]$result.Info.Timestamp }
        if ($filter.Action) { $detail['Actions'] = $filter.Action -join ', ' }
        if ($filter.Address) { $detail['Addresses'] = $filter.Address -join ', ' }
        if ($filter.ResourceType) { $detail['Resource types'] = $filter.ResourceType -join ', ' }
        $result['Detail'] = $detail
        $csvRows = if ($filter.ExpandAttribute) { $rows } else { @($rows | Select-Object -Property * -ExcludeProperty Attributes) }
        $null = Invoke-AACExport -CsvPath $csvFullPath -CsvObject @($csvRows) -Noun $(if ($filter.ExpandAttribute) { 'attribute change' } else { 'resource change' }) -HtmlPath $htmlFullPath -WriteHtml {
            Write-AACTerraformPlanHtml -Plan $result -Path $htmlFullPath -Title $filter.Title -Detail $detail
        }
        $result
    }

    if ($showView) {
        Invoke-AACPagedOutput -NoPaging:$NoPaging -ScriptBlock {
            Show-AACTerraformPlanView -Plan $state
        }
    }
    elseif ($interactive) {
        foreach ($notice in @($state.Notice)) { Write-AACMarkup "[grey58]$([Spectre.Console.Markup]::Escape($notice))[/]" }
    }
    if ($returnObjects) {
        $state.Rows
    }
}
