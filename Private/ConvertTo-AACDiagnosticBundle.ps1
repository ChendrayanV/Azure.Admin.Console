function ConvertTo-AACDiagnosticBundle {
    <#
    .SYNOPSIS
        Organizes what Export-AACDiagnosticBundle read into one set of
        sections per resource - configuration, health, activity, diagnostic
        settings, locks, recommendations, compliance, alerts, changes and
        role assignments - with a summary row each.
    .DESCRIPTION
        No Azure calls, no files. -ResourceId is the resources asked for;
        -Read is Invoke-AACGraphBatch's result for
        Get-AACDiagnosticBundleQuery (every row with a 'target'); -Arm maps
        a resource ID (lower case) to @{ Activity; Diagnostics; Locks;
        History } - Invoke-AACArmParallel's answers (Items, Error) for its
        Activity Log, diagnostic settings, locks and Resource Health history.

        Returns @{ Resources (@{ Id; Name; Folder; Sections (ordered: file
        name -> data); Summary (AAC.DiagnosticBundleResource) }); Warnings }.
        Nothing is redacted here: the writer does it.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string[]] $ResourceId,

        [Parameter(Mandatory)]
        [hashtable] $Read,

        [hashtable] $Arm = @{},

        [hashtable] $SubscriptionName = @{}
    )

    $value = { param($Object, [string] $Key) if ($Object -is [System.Collections.IDictionary] -and $Object.Contains($Key)) { $Object[$Key] } }
    $text = { param($Object, [string] $Key) $v = & $value $Object $Key; if ($null -eq $v) { '' } else { [string]$v } }
    $byTarget = @{}
    foreach ($name in @($Read.Rows.Keys)) {
        $byTarget[$name] = @{}
        foreach ($row in @($Read.Rows[$name] | Where-Object { $_ })) {
            $t = & $text $row 'target'
            if (-not $byTarget[$name].Contains($t)) { $byTarget[$name][$t] = [System.Collections.Generic.List[object]]::new() }
            $byTarget[$name][$t].Add($row)
        }
    }
    $rowsFor = { param([string] $Name, [string] $Id) if ($byTarget.Contains($Name) -and $byTarget[$Name].Contains($Id)) { @($byTarget[$Name][$Id]) } else { @() } }
    $warnings = [System.Collections.Generic.List[string]]::new()
    foreach ($key in @($Read.Errors.Keys | Sort-Object)) { $warnings.Add("Resource Graph: the $key couldn't be read: $($Read.Errors[$key] -replace '\s+', ' ')") }
    $answer = {
        param([string] $Id, [string] $Part, [string] $Label)
        $a = if ($Arm.Contains($Id)) { $Arm[$Id][$Part] } else { $null }
        if ($null -eq $a) { return @{ Read = $false; Items = @() } }
        if ($a.Error) { $warnings.Add("$(($Id -split '/')[-1]): the $Label couldn't be read: $($a.Error -replace '\s+', ' ')"); return @{ Read = $false; Items = @() } }
        @{ Read = $true; Items = @($a.Items | Where-Object { $_ }) }
    }
    $folders = @{}
    $resources = @(foreach ($raw in @($ResourceId | ForEach-Object { $_.TrimEnd('/').ToLowerInvariant() } | Select-Object -Unique)) {
            $config = @(& $rowsFor 'config' $raw) | Select-Object -First 1
            $name = if ($config) { & $text $config 'name' } else { ($raw -split '/')[-1] }
            $folder = ($name -replace '[^\w.\-]', '_')
            if ($folders.Contains($folder.ToLowerInvariant())) { $folder = "$folder-$($folders.Count + 1)" }
            $folders[$folder.ToLowerInvariant()] = $true
            $activity = & $answer $raw 'Activity' 'Activity Log'
            $diagnostics = & $answer $raw 'Diagnostics' 'diagnostic settings'
            $locks = & $answer $raw 'Locks' 'locks'
            $history = & $answer $raw 'History' 'Resource Health history'
            $health = @(& $rowsFor 'health' $raw) | Select-Object -First 1
            $failedOps = @($activity.Items | Where-Object { [string](& $value (& $value $_ 'status') 'value') -eq 'Failed' })
            $sections = [ordered]@{
                'config.json'              = $config
                'health.json'              = [ordered]@{ current = $health; history = $history.Items; events = @(& $rowsFor 'healthEvents' $raw) }
                'activity-log.json'        = $activity.Items
                'diagnostic-settings.json' = $diagnostics.Items
                'locks.json'               = $locks.Items
                'advisor.json'             = @(& $rowsFor 'advisor' $raw)
                'defender.json'            = @(& $rowsFor 'defender' $raw)
                'policy.json'              = @(& $rowsFor 'policy' $raw)
                'alerts.json'              = @(& $rowsFor 'alerts' $raw)
                'changes.json'             = @(& $rowsFor 'changes' $raw)
                'role-assignments.json'    = @(& $rowsFor 'roleAssignments' $raw)
            }
            if (-not $config) { $warnings.Add("$name wasn't found in Resource Graph (deleted, a typo, or no access): its configuration is missing.") }
            $subscription = if ($raw -match '^/subscriptions/([^/]+)') { $Matches[1] } else { '' }
            $issues = @(
                if (-not $config) { 'not found' }
                if ($health -and (& $text $health 'state') -in 'Unavailable', 'Degraded') { "health $((& $text $health 'state').ToLowerInvariant())" }
                if ($failedOps.Count) { "$($failedOps.Count) failed operation(s)" }
                if (@(& $rowsFor 'alerts' $raw).Count) { "$(@(& $rowsFor 'alerts' $raw).Count) alert(s)" }
                if ($diagnostics.Read -and -not $diagnostics.Items.Count) { 'no diagnostic settings' }
            )
            $summary = [pscustomobject][ordered]@{
                Status             = $(if (-not $config -or ($health -and (& $text $health 'state') -eq 'Unavailable')) { 'Failed' } elseif ($issues.Count) { 'Warning' } else { 'Success' })
                Resource           = $name
                ResourceType       = $(if ($config) { & $text $config 'type' } else { '' })
                ResourceGroup      = $(if ($config) { & $text $config 'resourceGroup' } elseif ($raw -match '/resourcegroups/([^/]+)') { $Matches[1] } else { '' })
                Subscription       = $(if ($SubscriptionName.Contains($subscription)) { $SubscriptionName[$subscription] } else { $subscription })
                Health             = $(if ($health) { & $text $health 'state' } else { '' })
                ActivityEvents     = $activity.Items.Count
                FailedOperations   = $failedOps.Count
                Alerts             = @(& $rowsFor 'alerts' $raw).Count
                Advisor            = @(& $rowsFor 'advisor' $raw).Count
                Defender           = @(& $rowsFor 'defender' $raw).Count
                PolicyNonCompliant = @(& $rowsFor 'policy' $raw).Count
                Changes            = @(& $rowsFor 'changes' $raw).Count
                Locks              = $locks.Items.Count
                DiagnosticSettings = $(if ($diagnostics.Read) { $diagnostics.Items.Count } else { $null })
                Issues             = ($issues -join ', ')
                Folder             = "resources/$folder"
                ResourceId         = $raw
            }
            $summary.PSObject.TypeNames.Insert(0, 'AAC.DiagnosticBundleResource')
            @{ Id = $raw; Name = $name; Folder = $folder; Sections = $sections; Summary = $summary }
        })
    @{ Resources = $resources; Warnings = @($warnings) }
}
