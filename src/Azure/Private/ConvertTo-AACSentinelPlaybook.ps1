function ConvertTo-AACSentinelPlaybook {
    <#
    .SYNOPSIS
        Turns Microsoft Sentinel playbooks (Logic Apps with a Sentinel trigger),
        their runs, the automation rules that run them and the role
        assignments on their resource groups into AAC.SentinelPlaybook
        objects, each with findings.
    .DESCRIPTION
        No Azure calls, so it can be tested with made-up data.

          -Workflow        Resource Graph rows: id, name, resourceGroup,
                           subscriptionId, location, state, identityType,
                           triggers, connections, changedTime
          -Run             lower-case workflow ID -> Invoke-AACArmParallel
                           result of its runs over -Days
          -AutomationRule  the workspace's automation rules (Resource Manager)
          -RoleAssignment  lower-case resource group ID -> Invoke-AACArmParallel
                           result of its role assignments (atScope)

        Sentinel runs a playbook as its own service principal, which needs
        Microsoft Sentinel Automation Contributor on the playbook's resource
        group. Whose principal it is isn't checked (that needs Microsoft
        Graph): any assignment of the role counts, so SentinelCanRun is a
        good sign, not proof. Blank when the assignments couldn't be read.

        An automation rule that names a playbook not in -Workflow gets a row
        of its own, State Missing.
    #>
    [CmdletBinding()]
    [OutputType('AAC.SentinelPlaybook')]
    param(
        [AllowEmptyCollection()]
        [object[]] $Workflow = @(),

        [System.Collections.IDictionary] $Run = @{},

        [AllowEmptyCollection()]
        [object[]] $AutomationRule = @(),

        [System.Collections.IDictionary] $RoleAssignment = @{},

        [ValidateRange(1, 90)]
        [int] $Days = 7,

        [datetime] $Now = [datetime]::UtcNow
    )

    # Microsoft Sentinel Automation Contributor, the role Sentinel needs to run a playbook.
    $automationContributor = 'f4c81013-99ee-4d62-a7ee-b3f1f648599a'
    $failedStates = 'Failed', 'TimedOut', 'Aborted'
    $inv = [cultureinfo]::InvariantCulture
    $get = {
        param($Object, [string[]] $Path)
        $value = $Object
        foreach ($key in $Path) {
            if ($value -isnot [System.Collections.IDictionary] -or -not $value.Contains($key)) { return $null }
            $value = $value[$key]
        }
        $value
    }
    $date = {
        param($Value)
        if ($Value -is [datetime]) { return $Value.ToUniversalTime() }
        $parsed = [datetime]::MinValue
        if ($Value -and [datetime]::TryParse([string]$Value, $inv, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) { return $parsed }
        $null
    }
    $key = { param([string] $Id) if ($Id) { $Id.TrimEnd('/').ToLowerInvariant() } else { '' } }

    # Which automation rules run which playbook, and whether each rule is live.
    $rulesByPlaybook = @{}
    foreach ($rule in @($AutomationRule | Where-Object { $_ -is [System.Collections.IDictionary] })) {
        $properties = & $get $rule 'properties'
        $expires = & $date (& $get $properties 'triggeringLogic', 'expirationTimeUtc')
        $live = [bool](& $get $properties 'triggeringLogic', 'isEnabled') -and -not ($expires -and $expires -lt $Now)
        foreach ($action in @(& $get $properties 'actions' | Where-Object { $_ -is [System.Collections.IDictionary] })) {
            if ([string]$action['actionType'] -ne 'RunPlaybook') { continue }
            $playbookId = & $key ([string](& $get $action 'actionConfiguration', 'logicAppResourceId'))
            if (-not $playbookId) { continue }
            if (-not $rulesByPlaybook.Contains($playbookId)) { $rulesByPlaybook[$playbookId] = [System.Collections.Generic.List[object]]::new() }
            $rulesByPlaybook[$playbookId].Add(@{ Name = [string](& $get $properties 'displayName'); Live = $live })
        }
    }

    $result = [System.Collections.Generic.List[object]]::new()
    $seen = @{}
    foreach ($row in @($Workflow | Where-Object { $_ -is [System.Collections.IDictionary] })) {
        $id = [string]$row['id']
        $seen[(& $key $id)] = $true
        $triggerText = ConvertTo-Json -InputObject $row['triggers'] -Compress -Depth 30
        $trigger = if ($triggerText -match 'incident-creation') { 'Incident' } elseif ($triggerText -match '/subscribe') { 'Alert' } elseif ($triggerText -match '/entity') { 'Entity' } else { 'Other' }
        # The Sentinel connection: with a managed identity, nobody's account can expire under it.
        $sentinelAuth = 'Unknown'
        $connections = $row['connections']
        if ($connections -is [System.Collections.IDictionary]) {
            foreach ($name in $connections.Keys) {
                $connection = $connections[$name]
                if ("$name $(& $get $connection 'id')" -notmatch '(?i)sentinel') { continue }
                $sentinelAuth = if ([string](& $get $connection 'connectionProperties', 'authentication', 'type') -eq 'ManagedServiceIdentity') { 'ManagedIdentity' } else { 'Connection' }
            }
        }

        $runRead = $Run[(& $key $id)]
        $runsRead = $runRead -and -not $runRead.Error
        $runs = @(if ($runsRead) { $runRead.Items | Where-Object { $_ -is [System.Collections.IDictionary] } })
        $failed = @($runs | Where-Object { $failedStates -contains [string](& $get $_ 'properties', 'status') })
        $lastRun = @($runs | ForEach-Object { & $date (& $get $_ 'properties', 'startTime') } | Where-Object { $_ } | Sort-Object -Descending | Select-AACFirst 1)
        $lastFailed = @($failed | Sort-Object -Property { & $date (& $get $_ 'properties', 'startTime') } -Descending | Select-AACFirst 1)
        $lastError = if ($lastFailed.Count) { $e = & $get $lastFailed[0] 'properties', 'error'; [string]$(if ($e -is [System.Collections.IDictionary]) { @($e['code'], $e['message'] | Where-Object { $_ }) -join ': ' } else { & $get $lastFailed[0] 'properties', 'code' }) } else { '' }

        $segments = $id -split '/'
        $groupId = & $key ($segments[0..4] -join '/')
        $roleRead = $RoleAssignment[$groupId]
        $canRun = if ($roleRead -and -not $roleRead.Error) { [bool]@($roleRead.Items | Where-Object { [string](& $get $_ 'properties', 'roleDefinitionId') -match $automationContributor }).Count } else { $null }

        $rules = @(if ($rulesByPlaybook.Contains((& $key $id))) { $rulesByPlaybook[(& $key $id)] })
        $liveRules = @($rules | Where-Object Live)
        $state = [string]$row['state']
        # Each finding with its level; the playbook takes the worst.
        $findings = [System.Collections.Generic.List[hashtable]]::new()
        $raise = { param([string] $Level, [string] $Text) $findings.Add(@{ Level = $Level; Text = $Text }) }
        if ($state -eq 'Disabled' -and $liveRules.Count) { & $raise 'High' "Disabled, but $($liveRules.Count) enabled automation rule(s) run it" }
        if ($canRun -eq $false -and $trigger -ne 'Other') { & $raise 'High' 'No Microsoft Sentinel Automation Contributor on its resource group: Sentinel can''t run it' }
        if ($failed.Count) { & $raise 'Medium' "$($failed.Count) of $($runs.Count) run(s) failed in $Days day(s)" }
        if ($sentinelAuth -eq 'Connection') { & $raise 'Low' 'Its Sentinel connection signs in as an account, not a managed identity: it breaks when that account changes' }
        if (-not $rules.Count -and $trigger -in 'Incident', 'Alert') { & $raise 'Low' 'No automation rule runs it: it runs only when someone starts it' }
        elseif ($rules.Count -and -not $liveRules.Count) { & $raise 'Low' 'Only disabled or expired automation rules run it' }
        $rank = @{ High = 0; Medium = 1; Low = 2 }
        $severity = @($findings | Sort-Object -Property { $rank[$_.Level] } | ForEach-Object { $_.Level } | Select-AACFirst 1) -join ''

        $result.Add([pscustomobject][ordered]@{
                PSTypeName      = 'AAC.SentinelPlaybook'
                Name            = [string]$row['name']
                State           = $state
                Trigger         = $trigger
                AutomationRules = $rules.Count
                RuleNames       = @($rules | ForEach-Object { $_.Name }) -join ', '
                Runs            = $(if ($runsRead) { $runs.Count })
                Failed          = $(if ($runsRead) { $failed.Count })
                FailurePercent  = $(if ($runs.Count) { [Math]::Round(100 * $failed.Count / $runs.Count, 1) } elseif ($runsRead) { 0 })
                LastRun         = $(if ($lastRun.Count) { $lastRun[0] })
                LastError       = $lastError
                SentinelCanRun  = $canRun
                SentinelAuth    = $sentinelAuth
                Identity        = $(if ($row['identityType']) { [string]$row['identityType'] } else { 'None' })
                Severity        = $severity
                Findings        = @($findings | ForEach-Object { $_.Text }) -join '; '
                ResourceGroup   = [string]$row['resourceGroup']
                SubscriptionId  = [string]$row['subscriptionId']
                Location        = [string]$row['location']
                LastModified    = & $date $row['changedTime']
                RunsError       = $(if ($runRead -and $runRead.Error) { [string]$runRead.Error } else { '' })
                ResourceId      = $id
            })
    }
    # Playbooks an automation rule names that weren't found.
    foreach ($playbookId in $rulesByPlaybook.Keys) {
        if ($seen.Contains($playbookId)) { continue }
        $rules = @($rulesByPlaybook[$playbookId])
        $result.Add([pscustomobject][ordered]@{
                PSTypeName      = 'AAC.SentinelPlaybook'
                Name            = ($playbookId -split '/')[-1]
                State           = 'Missing'
                Trigger         = ''
                AutomationRules = $rules.Count
                RuleNames       = @($rules | ForEach-Object { $_.Name }) -join ', '
                Runs            = $null
                Failed          = $null
                FailurePercent  = $null
                LastRun         = $null
                LastError       = ''
                SentinelCanRun  = $null
                SentinelAuth    = ''
                Identity        = ''
                Severity        = $(if (@($rules | Where-Object Live).Count) { 'High' } else { 'Low' })
                Findings        = 'An automation rule runs it, but it isn''t in the subscriptions searched: deleted, moved, or out of reach'
                ResourceGroup   = $(($playbookId -split '/')[4])
                SubscriptionId  = $(($playbookId -split '/')[2])
                Location        = ''
                LastModified    = $null
                RunsError       = ''
                ResourceId      = $playbookId
            })
    }
    $order = @{ High = 0; Medium = 1; Low = 2 }
    @($result | Sort-Object -Property @{ Expression = { if ($_.Severity) { $order[$_.Severity] } else { 3 } } }, 'Name')
}
