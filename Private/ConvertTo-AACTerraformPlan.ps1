function ConvertTo-AACTerraformPlan {
    <#
    .SYNOPSIS
        Flattens a Terraform plan in JSON (terraform show -json) into one row
        per resource change and one row per attribute that changes.
    .DESCRIPTION
        -Plan is the plan read with ConvertFrom-Json -AsHashtable. Returns
        @{ Info; Changes; Attributes; Stats }:

          Changes     AAC.TerraformChange: one per resource in
                      resource_changes (Source 'Plan'), resource_drift
                      (Source 'Drift': changed outside Terraform) and
                      output_changes (Mode 'output') - with Action Create,
                      Update, Replace, Delete, Read, Import, Move, Forget or
                      NoOp, its Azure name, resource group, location and ID,
                      why (action_reason), and its attribute changes
          Attributes  (on each change) AAC.TerraformAttributeChange: one
                      per changed attribute, flattened to a path -
                        tags["cost.centre"]   a map key
                        site_config[0].always_on
                        security_rule[name=ssh].destination_port_range
                                              a list of blocks, an element
                                              named by its 'name'
                        policy_rule{json}.then.effect
                                              inside a JSON-encoded string
                      with Before, After, Change (Added, Removed, Modified,
                      Known after apply, Reordered) and ForcesReplacement
                      (from replace_paths)

        Updates and replacements list only what changes; a create lists
        every attribute set (and those known after apply), a delete every
        attribute the object had. Elements of a list of blocks are paired
        first by being identical, then by name, then in order, so a rule
        added to a set doesn't show every rule after it as changed.

        Sensitive values are never returned: the plan JSON holds them in
        clear text, marked in before_sensitive and after_sensitive; they
        come back as '(sensitive)'.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Plan,

        [string] $Path,

        # Called with (done, total) every 25 resources, for a progress line.
        [scriptblock] $OnProgress
    )

    $actionOrder = @{ Delete = 0; Replace = 1; Update = 2; Create = 3; Import = 4; Move = 5; Read = 6; Forget = 7; NoOp = 8 }
    $reasons = @{
        replace_because_tainted            = 'tainted (a create or update failed, or terraform taint)'
        replace_because_cannot_update      = 'a changed attribute forces replacement'
        replace_by_request                 = 'replacement requested (-replace)'
        replace_by_triggers                = 'something in its replace_triggered_by changed'
        delete_because_no_resource_config  = 'removed from the configuration'
        delete_because_no_module           = 'its module was removed from the configuration'
        delete_because_wrong_repetition    = 'count or for_each was added or removed'
        delete_because_count_index         = 'its count index is out of range'
        delete_because_each_key            = 'its for_each key is gone'
        delete_because_no_move_target      = 'the target of its moved block is not in the configuration'
        read_because_config_unknown        = 'its configuration depends on values known only after apply'
        read_because_dependency_pending    = 'it depends on resources with changes pending'
        read_because_check_nested          = 'a check block reads it'
    }

    # The values themselves are walked in C# (Import-AACTerraformPlanFlattener).
    Import-AACTerraformPlanFlattener

    function Get-Action([object[]] $Actions) {
        switch ($Actions -join ',') {
            'no-op' { 'NoOp' }
            'create' { 'Create' }
            'read' { 'Read' }
            'update' { 'Update' }
            'delete' { 'Delete' }
            'delete,create' { 'Replace' }
            'create,delete' { 'Replace' }
            'forget' { 'Forget' }
            default { $_ }
        }
    }

    $attributeRows = [System.Collections.Generic.List[object]]::new()

    function ConvertTo-Change {
        param([System.Collections.IDictionary] $Item, [string] $Source)

        $change = $Item['change']
        if ($change -isnot [System.Collections.IDictionary]) { $change = @{} }
        $actions = @($change['actions'])
        $action = Get-Action $actions
        $before = $change['before']
        $after = $change['after']
        $previous = [string]$Item['previous_address']
        $deposed = [string]$Item['deposed']
        $importing = $change['importing'] -is [System.Collections.IDictionary]
        if ($action -eq 'NoOp' -and $importing) { $action = 'Import' }
        elseif ($action -eq 'NoOp' -and $previous) { $action = 'Move' }

        $flattener = [AzureAdminConsole.TerraformPlanFlattener]
        $leaves = if ($action -notin 'NoOp', 'Import', 'Move', 'Forget') {
            $flattener::Flatten($before, $after, $change['after_unknown'], $change['before_sensitive'], $change['after_sensitive'], $(if ($Item['mode'] -eq 'output') { 'value' } else { '' }), $change['replace_paths'])
        }
        $address = [string]$Item['address']
        $mode = [string]$Item['mode']
        $type = [string]$Item['type']
        $provider = [string]$Item['provider_name']
        $resourceName = $flattener::Fact($after, $before, 'name')
        # A literal [pscustomobject]@{} per row: a plan can change a hundred
        # thousand attributes, and building each row any other way is slower.
        $rows = foreach ($leaf in $leaves) {
            [pscustomobject]@{
                PSTypeName        = 'AAC.TerraformAttributeChange'
                Source            = $Source
                Action            = $action
                Address           = $address
                Type              = $type
                ResourceName      = $resourceName
                Attribute         = $leaf.Attribute
                Change            = $leaf.Change
                Before            = $leaf.Before
                After             = $leaf.After
                ForcesReplacement = $leaf.ForcesReplacement
                Sensitive         = $leaf.Sensitive
            }
        }
        $rows = @($rows)
        $attributeRows.AddRange([object[]]$rows)

        [pscustomobject][ordered]@{
            PSTypeName        = 'AAC.TerraformChange'
            Source            = $Source
            Action            = $action
            Address           = $address
            Module            = [string]$Item['module_address']
            Mode              = $mode
            Type              = $type
            Name              = [string]$Item['name']
            Index             = $(if ($Item.Contains('index')) { [string]$Item['index'] })
            Provider          = $(if ($provider) { ($provider -split '/')[-1] })
            ResourceName      = $resourceName
            ResourceGroup     = $flattener::Fact($after, $before, 'resource_group_name')
            Location          = $flattener::Fact($after, $before, 'location')
            ResourceId        = $flattener::Fact($before, $after, 'id')
            Reason            = $(if ($Item['action_reason']) { $(if ($reasons.Contains([string]$Item['action_reason'])) { $reasons[[string]$Item['action_reason']] } else { [string]$Item['action_reason'] }) } elseif ($deposed) { 'a deposed object: the old copy left when a create_before_destroy replacement failed' })
            Deposed           = $deposed
            ReplaceOrder      = $(switch ($actions -join ',') { 'delete,create' { 'Destroy then create' } 'create,delete' { 'Create then destroy' } })
            ReplacePaths      = $flattener::ReplacePathLabels($change['replace_paths']) -join ', '
            PreviousAddress   = $previous
            Importing         = $importing
            ChangedAttributes = @(foreach ($row in $rows) { $row.Attribute }) -join ', '
            AttributeCount    = $rows.Count
            Attributes        = $rows
        }
    }

    $resourceItems = @($Plan['resource_changes'] | Where-Object { $_ -is [System.Collections.IDictionary] })
    $driftItems = @($Plan['resource_drift'] | Where-Object { $_ -is [System.Collections.IDictionary] })
    $total = $resourceItems.Count + $driftItems.Count
    $done = 0
    $changes = [System.Collections.Generic.List[object]]::new()
    foreach ($pair in @(@{ Items = $resourceItems; Source = 'Plan' }, @{ Items = $driftItems; Source = 'Drift' })) {
        foreach ($item in $pair.Items) {
            $changes.Add((ConvertTo-Change -Item $item -Source $pair.Source))
            $done++
            if ($OnProgress -and ($done % 25 -eq 0 -or $done -eq $total)) { & $OnProgress $done $total }
        }
    }
    $outputs = $Plan['output_changes']
    if ($outputs -is [System.Collections.IDictionary]) {
        $names = [string[]]@($outputs.Keys)
        [Array]::Sort($names, [StringComparer]::Ordinal)
        foreach ($name in $names) {
            $changes.Add((ConvertTo-Change -Item @{ address = "output.$name"; mode = 'output'; type = 'output'; name = $name; change = $outputs[$name] } -Source 'Plan'))
        }
    }

    $sorted = @($changes | Sort-Object -Property @{ Expression = { $actionOrder[$_.Action] ?? 9 } }, Address)
    # Counted in one pass each: a plan can hold a hundred thousand rows.
    $stats = [ordered]@{ Resources = 0; Create = 0; Update = 0; Replace = 0; Delete = 0; Read = 0; Forget = 0; NoOp = 0; Import = 0; Move = 0; Outputs = 0; Drift = 0; Attributes = 0; Sensitive = 0; Forced = 0 }
    foreach ($change in $sorted) {
        if ($change.Source -eq 'Drift') { $stats.Drift++; continue }
        if ($change.Mode -eq 'output') { if ($change.Action -ne 'NoOp') { $stats.Outputs++ }; continue }
        $stats.Resources++
        if ($stats.Contains($change.Action)) { $stats[$change.Action]++ }
        if ($change.Importing) { $stats.Import++ }
        if ($change.PreviousAddress) { $stats.Move++ }
    }
    foreach ($row in $attributeRows) {
        if ($row.Source -eq 'Plan') { $stats.Attributes++ }
        if ($row.Sensitive) { $stats.Sensitive++ }
        if ($row.ForcesReplacement) { $stats.Forced++ }
    }
    # Terraform's own summary line: a replacement adds one and destroys one.
    $stats['ToAdd'] = $stats.Create + $stats.Replace
    $stats['ToChange'] = $stats.Update
    $stats['ToDestroy'] = $stats.Delete + $stats.Replace

    # Check results (check blocks, preconditions, postconditions): those
    # that fail, error or can't be known until apply, with their messages.
    $checks = @(foreach ($check in @($Plan['checks'])) {
            if ($check -isnot [System.Collections.IDictionary] -or [string]$check['status'] -notin 'fail', 'error', 'unknown') { continue }
            $problems = @(foreach ($instance in @($check['instances'])) {
                    if ($instance -isnot [System.Collections.IDictionary]) { continue }
                    foreach ($problem in @($instance['problems'])) { if ($problem -is [System.Collections.IDictionary] -and $problem['message']) { [string]$problem['message'] } }
                })
            $address = if ($check['address'] -is [System.Collections.IDictionary]) { [string]$check['address']['to_display'] } else { '' }
            [pscustomobject]@{ Address = $address; Status = [string]$check['status']; Problems = @($problems | Select-Object -Unique) }
        })
    $stats['ChecksFailed'] = @($checks | Where-Object Status -In 'fail', 'error').Count
    $stats['ChecksUnknown'] = @($checks | Where-Object Status -EQ 'unknown').Count

    $info = [ordered]@{
        Path             = $Path
        TerraformVersion = [string]$Plan['terraform_version']
        FormatVersion    = [string]$Plan['format_version']
        # ConvertFrom-Json reads the ISO 8601 text as a UTC [datetime].
        Timestamp        = $(if ($Plan['timestamp'] -is [datetime]) { $Plan['timestamp'].ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss 'UTC'", [cultureinfo]::InvariantCulture) } elseif ($Plan['timestamp']) { [string]$Plan['timestamp'] })
        Applyable        = $(if ($Plan.Contains('applyable')) { [bool]$Plan['applyable'] })
        Complete         = $(if ($Plan.Contains('complete')) { [bool]$Plan['complete'] })
        Errored          = [bool]$Plan['errored']
        Checks           = $checks
    }

    @{
        Info       = $info
        Changes    = $sorted
        Stats      = $stats
    }
}
