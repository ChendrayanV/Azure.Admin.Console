function ConvertTo-AACDiagnosticCoverage {
    <#
    .SYNOPSIS
        Works out, for every resource that has resource logs, whether its
        diagnostic settings export them to a Log Analytics workspace - and
        what is misconfigured.
    .DESCRIPTION
        No Azure calls: Get-AACDiagnosticSetting reads, this decides.

          -Target      what diagnostic settings were read for: @{ Id;
                       Resource; Type; Kind; ResourceGroup; SubscriptionId;
                       Location; Key } - the resources, a storage account's
                       blob, file, queue and table services, subscriptions
          -Category    by Key ("type|kind"): @{ State = 'Logs' | 'NoLogs' |
                       'Unknown'; Logs = @(@{ Name; Groups }); Metrics =
                       @(names); Error }
          -Setting     by target Id: Invoke-AACArmParallel's result for
                       {id}/providers/Microsoft.Insights/diagnosticSettings
          -Workspace   every workspace the account can see, by lower-case ID:
                       @{ Name; Location }
          -ExpectedWorkspace  workspace names or IDs logs should go to

        A log category reaches Log Analytics when a setting with a workspace
        that exists enables it - by name, or through a category group it
        belongs to (allLogs, audit).

        Returns @{ Coverage; Settings; Findings; ByType; Workspaces; Stats }:
          Coverage   AAC.DiagnosticCoverage, one per target, with Status:
                       Exported            every log category reaches a workspace
                       Partial             some do
                       Not to workspace    settings, but none to a workspace
                       No setting          no diagnostic setting at all
                       No logs             the type has no log categories
                       Unknown             couldn't be read
          Settings   AAC.DiagnosticSettingDetail, one per setting, flattened
          Findings   AAC.DiagnosticFinding, by severity
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyCollection()]
        [object[]] $Target = @(),

        [System.Collections.IDictionary] $Category = @{},

        [System.Collections.IDictionary] $Setting = @{},

        [System.Collections.IDictionary] $Workspace = @{},

        [string[]] $ExpectedWorkspace = @(),

        [System.Collections.IDictionary] $SubscriptionName = @{}
    )

    $leaf = { param([string] $Id) if ($Id) { ($Id.TrimEnd('/') -split '/')[-1] } else { '' } }
    $at = {
        param($Value, [string[]] $Keys)
        foreach ($key in $Keys) { if ($Value -is [System.Collections.IDictionary] -and $Value.Contains($key)) { $Value = $Value[$key] } else { return $null } }
        $Value
    }
    $object = {
        param([string] $TypeName, [System.Collections.IDictionary] $Property)
        $item = [pscustomobject]$Property
        $item.PSObject.TypeNames.Insert(0, $TypeName)
        $item
    }
    $expected = @($ExpectedWorkspace | Where-Object { $_ } | ForEach-Object { $_.Trim().ToLowerInvariant() })
    $isExpected = { param([string] $WorkspaceId) $id = $WorkspaceId.ToLowerInvariant(); @($expected | Where-Object { $_ -eq $id -or $_ -eq (& $leaf $id) }).Count -gt 0 }
    $docs = 'https://learn.microsoft.com/azure/azure-monitor/essentials/diagnostic-settings'

    $coverage = [System.Collections.Generic.List[object]]::new()
    $details = [System.Collections.Generic.List[object]]::new()
    $findings = [System.Collections.Generic.List[object]]::new()
    $workspaceUse = @{}

    foreach ($t in $Target) {
        $subscription = if ($SubscriptionName.Contains(([string]$t.SubscriptionId).ToLowerInvariant())) { $SubscriptionName[([string]$t.SubscriptionId).ToLowerInvariant()] } else { [string]$t.SubscriptionId }
        $base = [ordered]@{ Resource = $t.Resource; ResourceType = $t.Type; ResourceGroup = $t.ResourceGroup; SubscriptionName = $subscription }
        $find = {
            param([string] $Severity, [string] $Title, [string] $SettingName, [string] $Detail, [string] $Action)
            $row = [ordered]@{ Severity = $Severity; Finding = $Title }
            foreach ($key in $base.Keys) { $row[$key] = $base[$key] }
            $row['Setting'] = $SettingName; $row['Detail'] = $Detail; $row['Action'] = $Action; $row['LearnMore'] = $docs; $row['ResourceId'] = $t.Id
            $item = & $object 'AAC.DiagnosticFinding' $row
            $findings.Add($item)
            $item
        }
        $typeInfo = $Category[$t.Key]
        $state = if ($typeInfo) { $typeInfo.State } else { 'Unknown' }
        $logs = @(if ($typeInfo) { $typeInfo.Logs })
        $read = $Setting[$t.Id]
        $settingsRead = $state -eq 'Logs' -and $read -and -not $read.Error
        $listed = if ($settingsRead) { if ($null -ne $read.Items) { $read.Items } else { & $at $read.Body 'value' } }
        $items = @($listed | Where-Object { $_ -is [System.Collections.IDictionary] })
        $own = [System.Collections.Generic.List[object]]::new()
        $covered = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $sentBy = @{}
        $workspaces = [System.Collections.Generic.List[string]]::new()

        foreach ($item in $items) {
            $properties = & $at $item 'properties'
            $name = [string]$item['name']
            $workspaceId = [string](& $at $properties 'workspaceId')
            $storage = [string](& $at $properties 'storageAccountId')
            $eventHub = [string](& $at $properties 'eventHubAuthorizationRuleId')
            $partner = [string](& $at $properties 'marketplacePartnerId')
            $known = if ($workspaceId) { $Workspace[$workspaceId.ToLowerInvariant()] }
            $logEntries = @(& $at $properties 'logs' | Where-Object { $_ -is [System.Collections.IDictionary] })
            $metricEntries = @(& $at $properties 'metrics' | Where-Object { $_ -is [System.Collections.IDictionary] })
            $enabledLogs = @($logEntries | Where-Object { $_['enabled'] })
            $enabledNames = @($enabledLogs | ForEach-Object { if ($_['category']) { [string]$_['category'] } else { "group:$([string]$_['categoryGroup'])" } })
            $disabledNames = @($logEntries | Where-Object { -not $_['enabled'] } | ForEach-Object { if ($_['category']) { [string]$_['category'] } else { "group:$([string]$_['categoryGroup'])" } })
            $enabledMetrics = @($metricEntries | Where-Object { $_['enabled'] } | ForEach-Object { [string]$_['category'] })
            # The log categories this setting turns on: named ones, and every
            # category in an enabled group.
            $reaches = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($entry in $enabledLogs) {
                if ($entry['category']) { $null = $reaches.Add([string]$entry['category']) }
                elseif ($entry['categoryGroup']) {
                    $group = [string]$entry['categoryGroup']
                    foreach ($log in $logs) { if ($group -eq 'allLogs' -or @($log.Groups) -contains $group) { $null = $reaches.Add($log.Name) } }
                }
            }
            $retention = @(@($logEntries) + @($metricEntries) | Where-Object { (& $at $_ 'retentionPolicy', 'enabled') -and [int](& $at $_ 'retentionPolicy', 'days') -gt 0 } | ForEach-Object { [int](& $at $_ 'retentionPolicy', 'days') } | Sort-Object -Unique)
            $destinationType = [string](& $at $properties 'logAnalyticsDestinationType')
            $detail = [ordered]@{}
            foreach ($key in $base.Keys) { $detail[$key] = $base[$key] }
            $detail['Setting'] = $name
            $detail['Destinations'] = @(@($(if ($workspaceId) { 'Log Analytics' }), $(if ($storage) { 'Storage' }), $(if ($eventHub) { 'Event Hubs' }), $(if ($partner) { 'Partner' })) | Where-Object { $_ }) -join ', '
            $detail['Workspace'] = $(if ($known) { $known.Name } elseif ($workspaceId) { & $leaf $workspaceId } else { '' })
            $detail['WorkspaceFound'] = $(if ($workspaceId) { [bool]$known } else { $null })
            $detail['WorkspaceLocation'] = $(if ($known) { $known.Location } else { '' })
            $detail['DestinationTable'] = $(if (-not $workspaceId) { '' } elseif ($destinationType -eq 'Dedicated') { 'Resource-specific' } else { 'AzureDiagnostics' })
            $detail['StorageAccount'] = & $leaf $storage
            $detail['EventHub'] = $(if ($eventHub) { "$(& $leaf ($eventHub -replace '/authorizationrules/.*$', ''))$(if (& $at $properties 'eventHubName') { "/$(& $at $properties 'eventHubName')" })" } else { '' })
            $detail['Partner'] = & $leaf $partner
            $detail['LogsEnabled'] = $enabledNames -join ', '
            $detail['LogsDisabled'] = $disabledNames -join ', '
            $detail['LogCategoriesReached'] = $reaches.Count
            $detail['MetricsEnabled'] = $enabledMetrics -join ', '
            $detail['RetentionDays'] = $retention -join ', '
            $detail['WorkspaceResourceId'] = $workspaceId
            $detail['ResourceId'] = $t.Id
            $row = & $object 'AAC.DiagnosticSettingDetail' $detail
            $details.Add($row)
            $own.Add($row)

            if ($workspaceId -and $known) {
                $workspaces.Add($known.Name)
                foreach ($name2 in $reaches) {
                    $null = $covered.Add($name2)
                    $key = "$($workspaceId.ToLowerInvariant())|$name2"
                    if (-not $sentBy.Contains($key)) { $sentBy[$key] = [System.Collections.Generic.List[string]]::new() }
                    $sentBy[$key].Add($name)
                }
                $useKey = $workspaceId.ToLowerInvariant()
                if (-not $workspaceUse.Contains($useKey)) { $workspaceUse[$useKey] = @{ Workspace = $known.Name; Location = $known.Location; Found = $true; Resources = [System.Collections.Generic.HashSet[string]]::new(); Settings = 0; ResourceId = $workspaceId } }
                $null = $workspaceUse[$useKey].Resources.Add($t.Id); $workspaceUse[$useKey].Settings++
            }
            elseif ($workspaceId) {
                $useKey = $workspaceId.ToLowerInvariant()
                if (-not $workspaceUse.Contains($useKey)) { $workspaceUse[$useKey] = @{ Workspace = (& $leaf $workspaceId); Location = ''; Found = $false; Resources = [System.Collections.Generic.HashSet[string]]::new(); Settings = 0; ResourceId = $workspaceId } }
                $null = $workspaceUse[$useKey].Resources.Add($t.Id); $workspaceUse[$useKey].Settings++
            }

            # Misconfigurations of this setting.
            if (-not $enabledLogs.Count -and -not $enabledMetrics.Count) {
                $null = & $find 'Medium' 'Diagnostic setting with nothing enabled' $name 'No log category or metric is enabled: the setting sends nothing.' 'Enable the allLogs category group, or delete the setting.'
            }
            if ($workspaceId -and -not $known) {
                $null = & $find 'High' 'Sends to a workspace that doesn''t exist' $name "The workspace $(& $leaf $workspaceId) isn't among the workspaces you can see: it was deleted, or is in a subscription you can't read. Logs sent to a deleted workspace are lost." 'Point the setting at an existing Log Analytics workspace.'
            }
            if ($known -and $expected.Count -and -not (& $isExpected $workspaceId)) {
                $null = & $find 'Medium' 'Sends to a workspace other than the expected one' $name "Logs go to $($known.Name), not to $($ExpectedWorkspace -join ', ')." 'Send them to the central workspace, or add this one to -ExpectedWorkspace if it is intended.'
            }
            if ($known -and $known.Location -and $t.Location -and $t.Location -ne 'global' -and $known.Location -ne $t.Location) {
                $null = & $find 'Low' 'Workspace in another region' $name "The resource is in $($t.Location), the workspace in $($known.Location): data leaves the region (bandwidth charges, data residency)." 'Use a workspace in the same region where residency or egress cost matters.'
            }
            if ($retention.Count) {
                $null = & $find 'Low' 'Deprecated retention policy on a diagnostic setting' $name "Retention of $($retention -join ', ') day(s) is set on the setting's categories. Diagnostic settings storage retention is retired: it no longer deletes anything." 'Remove the retention policy and use an Azure Storage lifecycle management policy instead.'
            }
        }

        # Duplicates: the same category to the same workspace from two settings.
        foreach ($key in @($sentBy.Keys)) {
            if ($sentBy[$key].Count -gt 1) {
                $parts = $key -split '\|', 2
                $null = & $find 'Medium' 'The same logs sent to a workspace twice' ($sentBy[$key] -join ', ') "Category $($parts[1]) goes to $(& $leaf $parts[0]) from $($sentBy[$key].Count) settings: it is ingested, and billed, $($sentBy[$key].Count) times." 'Keep one setting per destination workspace.'
            }
        }

        $logNames = @($logs | ForEach-Object { $_.Name })
        $missing = @($logNames | Where-Object { -not $covered.Contains($_) })
        $status = switch ($true) {
            ($state -eq 'NoLogs') { 'No logs'; break }
            ($state -ne 'Logs' -or ($read -and $read.Error)) { 'Unknown'; break }
            (-not $items.Count) { 'No setting'; break }
            (-not $covered.Count) { 'Not to workspace'; break }
            ([bool]$missing.Count) { 'Partial'; break }
            default { 'Exported' }
        }
        $isActivityLog = $t.Type -eq 'microsoft.resources/subscriptions'
        $what = if ($isActivityLog) { 'activity log' } else { 'resource logs' }
        switch ($status) {
            'No setting' { $null = & $find 'High' $(if ($isActivityLog) { 'Activity log not exported' } else { 'No diagnostic setting' }) '' "Its $($logNames.Count) log categor$(if ($logNames.Count -eq 1) { 'y goes' } else { 'ies go' }) nowhere: $($logNames -join ', ')." "Add a diagnostic setting that sends the allLogs category group to a Log Analytics workspace$(if (-not $isActivityLog) { ' - or assign the built-in policy initiative that does it for every supported resource' })." }
            'Not to workspace' { $null = & $find 'High' "No $what reach Log Analytics" (@($own | ForEach-Object Setting) -join ', ') "$($items.Count) diagnostic setting(s), but none sends a log category to a Log Analytics workspace that exists (destinations: $(@($own | ForEach-Object { if ($_.Destinations) { $_.Destinations } else { 'none' } } | Select-Object -Unique) -join '; '))." 'Add a Log Analytics workspace destination with the allLogs category group to a setting.' }
            'Partial' { $null = & $find 'Medium' 'Some log categories don''t reach Log Analytics' (@($own | ForEach-Object Setting) -join ', ') "$($missing.Count) of $($logNames.Count) categories are missing: $($missing -join ', ')." 'Enable the allLogs category group on the workspace setting, so new categories are included too.' }
        }
        $own = $own.ToArray()
        $ownFindings = @($findings | Where-Object { $_.ResourceId -eq $t.Id })
        $severityRank = @{ High = 3; Medium = 2; Low = 1 }
        $worst = @($ownFindings | Sort-Object { $severityRank[$_.Severity] } -Descending | Select-AACFirst 1 | ForEach-Object Severity)
        $row = [ordered]@{ Status = $status }
        foreach ($key in $base.Keys) { $row[$key] = $base[$key] }
        $row['Location'] = $t.Location
        $row['LogCategories'] = $logNames.Count
        $row['CategoriesToWorkspace'] = $covered.Count
        $row['MissingCategories'] = $missing -join ', '
        $row['Settings'] = $items.Count
        $row['SettingNames'] = @($own | ForEach-Object Setting) -join ', '
        $row['Workspaces'] = @($workspaces | Select-Object -Unique) -join ', '
        $row['Destinations'] = @($own | ForEach-Object Destinations | Where-Object { $_ } | ForEach-Object { $_ -split ', ' } | Select-Object -Unique) -join ', '
        # Why the logs don't (all) arrive, in a line.
        $row['Reason'] = switch ($status) {
            'No setting' { "$($logNames.Count) log categor$(if ($logNames.Count -eq 1) { 'y' } else { 'ies' }), no diagnostic setting" }
            'Not to workspace' {
                @(foreach ($detail in $own) {
                        if (-not $detail.WorkspaceResourceId) { "$($detail.Setting): to $(if ($detail.Destinations) { $detail.Destinations } else { 'no destination' })" }
                        elseif (-not $detail.WorkspaceFound) { "$($detail.Setting): workspace $($detail.Workspace) doesn't exist" }
                        elseif (-not $detail.LogCategoriesReached) { "$($detail.Setting): no log category enabled" }
                    }) -join '; '
            }
            'Partial' { "missing: $($missing -join ', ')" }
            'Unknown' { 'couldn''t be read' }
            default { '' }
        }
        $row['Severity'] = $(if ($worst) { $worst[0] } else { '' })
        $row['Findings'] = @($ownFindings | ForEach-Object Finding) -join '; '
        $row['Error'] = $(if ($status -eq 'Unknown') { if ($read -and $read.Error) { [string]$read.Error } elseif ($typeInfo -and $typeInfo.Error) { [string]$typeInfo.Error } else { 'Not read.' } } else { '' })
        $row['ResourceId'] = $t.Id
        $row['Detail'] = $own
        $coverage.Add((& $object 'AAC.DiagnosticCoverage' $row))
    }

    $rank = @{ High = 0; Medium = 1; Low = 2 }
    $statusOrder = @{ 'No setting' = 0; 'Not to workspace' = 1; 'Partial' = 2; 'Unknown' = 3; 'Exported' = 4; 'No logs' = 5 }
    $sortedCoverage = @($coverage | Sort-Object -Property @{ Expression = { $statusOrder[$_.Status] } }, ResourceType, Resource)
    $sortedFindings = @($findings | Sort-Object -Property @{ Expression = { $rank[$_.Severity] } }, Finding, Resource)
    $withLogs = @($sortedCoverage | Where-Object { $_.Status -notin 'No logs' })
    $count = { param([string] $Status) @($sortedCoverage | Where-Object Status -EQ $Status).Count }
    $byType = @($withLogs | Group-Object ResourceType | ForEach-Object {
            $exported = @($_.Group | Where-Object Status -EQ 'Exported').Count
            $known = @($_.Group | Where-Object Status -NE 'Unknown').Count
            [pscustomobject][ordered]@{
                ResourceType   = $_.Name
                Resources      = $_.Count
                Exported       = $exported
                Partial        = @($_.Group | Where-Object Status -EQ 'Partial').Count
                NotToWorkspace = @($_.Group | Where-Object Status -EQ 'Not to workspace').Count
                NoSetting      = @($_.Group | Where-Object Status -EQ 'No setting').Count
                Unknown        = @($_.Group | Where-Object Status -EQ 'Unknown').Count
                CoveragePercent = $(if ($known) { [Math]::Round($exported / $known * 100, 1) } else { $null })
            }
        } | Sort-Object -Property @{ Expression = { if ($null -eq $_.CoveragePercent) { 101 } else { $_.CoveragePercent } } }, @{ Expression = 'Resources'; Descending = $true })
    $workspaceRows = @($workspaceUse.Values | ForEach-Object {
            [pscustomobject][ordered]@{ Workspace = $_.Workspace; Location = $_.Location; Found = $_.Found; Resources = $_.Resources.Count; Settings = $_.Settings; Expected = $(if ($expected.Count) { & $isExpected $_.ResourceId } else { $null }); ResourceId = $_.ResourceId }
        } | Sort-Object -Property @{ Expression = 'Resources'; Descending = $true }, Workspace)
    $assessed = @($withLogs | Where-Object Status -NE 'Unknown').Count
    $stats = [ordered]@{
        Targets         = $sortedCoverage.Count
        WithLogs        = $withLogs.Count
        Exported        = & $count 'Exported'
        Partial         = & $count 'Partial'
        NotToWorkspace  = & $count 'Not to workspace'
        NoSetting       = & $count 'No setting'
        NoLogs          = & $count 'No logs'
        Unknown         = & $count 'Unknown'
        CoveragePercent = $(if ($assessed) { [Math]::Round((& $count 'Exported') / $assessed * 100, 1) } else { $null })
        Settings        = $details.Count
        Workspaces      = @($workspaceRows | Where-Object Found).Count
        High            = @($sortedFindings | Where-Object Severity -EQ 'High').Count
        Medium          = @($sortedFindings | Where-Object Severity -EQ 'Medium').Count
        Low             = @($sortedFindings | Where-Object Severity -EQ 'Low').Count
    }
    @{
        Coverage   = $sortedCoverage
        Settings   = $details.ToArray()
        Findings   = $sortedFindings
        ByType     = $byType
        Workspaces = $workspaceRows
        Stats      = $stats
    }
}
