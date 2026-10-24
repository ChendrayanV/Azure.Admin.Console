function ConvertTo-AACChangeHistory {
    <#
    .SYNOPSIS
        Turns the Activity Log, Resource Graph's resource changes, fired
        alerts and Resource Health into a change history: one entry per
        operation (its correlation ID) - who, what, when, from where, how it
        ended, the properties it changed (before and after), how hard it is
        to undo, and the incidents that followed it.
    .DESCRIPTION
        Activity Log events (administrative: writes, deletes, actions) are
        grouped by correlation ID: one change, its time the first event's,
        its status the last one's. Its resource's property changes from
        Resource Graph (resourcechanges) are joined by correlation ID, or by
        resource and time.

        Risk:
          High    deletes; access (role assignments, key vault access
                  policies, locks), network security (NSG and firewall
                  rules, firewall policies, public IPs), Azure Policy
                  (assignments, exemptions), keys read (listKeys) and
                  diagnostic settings removed
          Medium  other network changes; SKU or size changes; restarts,
                  stops and deallocations
          Low     anything else
        A change followed (within -CorrelationMinutes) by an alert or a
        Resource Health event on the same resource - or an alert on its
        resource group - is linked to it ('Possibly caused'), and is at
        least High.

        Revert: Create - delete it if unwanted; Update - set the changed
        properties back (their before values); Delete - recreate it from
        infrastructure as code or a backup (soft-deleted key vaults can be
        recovered); actions can't be undone.

        Origin: Manual (a user), Automation (an application, managed
        identity or pipeline) or Azure (the platform), for change control:
        manual changes are the ones outside infrastructure as code.
        Returns @{ Changes (AAC.ChangeRecord); Incidents (alerts and health
        events in the window); Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        # Activity Log events (hashtables, as Resource Manager returns them).
        [AllowEmptyCollection()] [object[]] $ActivityEvent = @(),
        # Resource Graph resourcechanges rows.
        [AllowEmptyCollection()] [object[]] $Change = @(),
        # Resource Graph fired alerts.
        [AllowEmptyCollection()] [object[]] $Alert = @(),
        # Resource Graph unhealthy resources (availability statuses).
        [AllowEmptyCollection()] [object[]] $Health = @(),
        [System.Collections.IDictionary] $SubscriptionName = @{},
        [int] $CorrelationMinutes = 120,
        [string[]] $ResourceGroupName = @(),
        [string[]] $ResourceType = @(),
        [string[]] $Caller = @(),
        [switch] $IncludeFailed
    )

    $get = { param($Row, [string] $Name) if ($Row -is [System.Collections.IDictionary]) { $Row[$Name] } elseif ($null -ne $Row) { $p = $Row.PSObject.Properties[$Name]; if ($p) { $p.Value } } }
    $text = { param($Value) if ($Value -is [System.Collections.IDictionary]) { [string]$Value['value'] } else { [string]$Value } }
    $lower = { param($Text) ([string]$Text).ToLowerInvariant() }
    $leaf = { param($Id) ([string]$Id).TrimEnd('/') -replace '^.*/', '' }
    $time = { param($Raw) if ($Raw -is [datetime]) { $Raw.ToUniversalTime() } else { $d = [datetime]::MinValue; if ($Raw -and [datetime]::TryParse([string]$Raw, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$d)) { $d } else { $null } } }
    $typeOf = { param($Id) if ([string]$Id -match '(?i)/providers/(.+)/[^/]+$') { ($Matches[1] -replace '/[^/]+/(?=[^/]+$)', '/').ToLowerInvariant() } elseif ([string]$Id -match '(?i)/resourcegroups/[^/]+$') { 'microsoft.resources/resourcegroups' } else { '' } }
    $groupOf = { param($Id) if ([string]$Id -match '(?i)/resourceGroups/([^/]+)') { $Matches[1] } else { '' } }
    $subOf = { param($Id) if ([string]$Id -match '(?i)^/subscriptions/([^/]+)') { $s = $Matches[1].ToLowerInvariant(); if ($SubscriptionName.Contains($s)) { [string]$SubscriptionName[$s] } else { $s } } else { '' } }
    $like = { param([string] $Value, [string[]] $Patterns) -not $Patterns.Count -or @($Patterns | Where-Object { $Value -like $_ }).Count -gt 0 }
    $severity = Get-AACSeverityRank

    # --- Property changes, by correlation ID and by resource ---------------------------------------------------------
    $byCorrelation = @{}; $byResource = @{}
    foreach ($c in $Change) {
        $item = @{ At = & $time (& $get $c 'at'); ResourceId = & $lower (& $get $c 'resourceId'); Kind = [string](& $get $c 'changeType'); Changes = & $get $c 'changes'; ChangedBy = [string](& $get $c 'changedBy'); ClientType = [string](& $get $c 'clientType') }
        $correlation = & $lower (& $get $c 'correlationId')
        if ($correlation) { if (-not $byCorrelation.Contains($correlation)) { $byCorrelation[$correlation] = [System.Collections.Generic.List[object]]::new() }; $byCorrelation[$correlation].Add($item) }
        if (-not $byResource.Contains($item.ResourceId)) { $byResource[$item.ResourceId] = [System.Collections.Generic.List[object]]::new() }
        $byResource[$item.ResourceId].Add($item)
    }
    $describe = {
        # 'properties.sku.name: Standard_D2s_v5 -> Standard_D4s_v5' - what the caller changed, not what
        # Azure updated along with it (provisioning states, timestamps), when the two are told apart.
        param($Changes)
        if ($Changes -isnot [System.Collections.IDictionary]) { return @() }
        $paths = @($Changes.Keys | Where-Object { [string](& $get $Changes[$_] 'changeCategory') -ne 'System' })
        if (-not $paths.Count) { $paths = @($Changes.Keys) }
        @($paths | Sort-Object | ForEach-Object {
                $d = $Changes[$_]
                $before = & $get $d 'beforeValue'; $after = & $get $d 'afterValue'
                @{ Path = [string]$_; Before = $(if ($null -eq $before) { '(none)' } else { [string]$before }); After = $(if ($null -eq $after) { '(none)' } else { [string]$after }) }
            })
    }

    # --- Incidents: alerts and health events --------------------------------------------------------------------------------
    $incidents = [System.Collections.Generic.List[object]]::new()
    foreach ($a in $Alert) {
        $incidents.Add([pscustomobject][ordered]@{
                PSTypeName = 'AAC.ChangeIncident'; Time = & $time (& $get $a 'fired'); Kind = 'Alert'; Name = [string](& $get $a 'name'); Severity = [string](& $get $a 'severity')
                State = [string](& $get $a 'state'); Resource = & $leaf (& $get $a 'target'); ResourceGroup = [string](& $get $a 'targetGroup'); Detail = $(@([string](& $get $a 'signal'), [string](& $get $a 'description')) | Where-Object { $_ }) -join ': '
                ResourceId = & $lower (& $get $a 'target')
            })
    }
    foreach ($h in $Health) {
        $id = & $lower (& $get $h 'resourceId')
        $incidents.Add([pscustomobject][ordered]@{
                PSTypeName = 'AAC.ChangeIncident'; Time = & $time (& $get $h 'since'); Kind = 'Resource Health'; Name = [string](& $get $h 'state'); Severity = $(if ([string](& $get $h 'state') -eq 'Unavailable') { 'Sev1' } else { 'Sev2' })
                State = [string](& $get $h 'state'); Resource = & $leaf $id; ResourceGroup = & $lower (& $groupOf $id); Detail = [string](& $get $h 'summary'); ResourceId = $id
            })
    }

    # --- One change per operation ---------------------------------------------------------------------------------------------
    $groups = [ordered]@{}
    foreach ($e in $ActivityEvent) {
        if ((& $text (& $get $e 'category')) -notin '', 'Administrative') { continue }
        $correlation = & $lower (& $get $e 'correlationId')
        $key = if ($correlation) { $correlation } else { [string](& $get $e 'eventDataId') }
        if (-not $groups.Contains($key)) { $groups[$key] = [System.Collections.Generic.List[object]]::new() }
        $groups[$key].Add($e)
    }
    $changes = [System.Collections.Generic.List[object]]::new()
    foreach ($key in $groups.Keys) {
        $events = @($groups[$key] | Sort-Object -Property { & $time (& $get $_ 'eventTimestamp') })
        $first = $events[0]; $last = $events[-1]
        $main = @($events | Where-Object { [string](& $get (& $get $_ 'authorization') 'action') })[0]
        if (-not $main) { $main = $first }
        $action = [string](& $get (& $get $main 'authorization') 'action')
        if ($action -notmatch '(?i)/(write|delete|action)$') { continue }
        $status = & $text (& $get $last 'status')
        $resourceId = & $lower $(if (& $get $main 'resourceId') { & $get $main 'resourceId' } else { & $get (& $get $main 'authorization') 'scope' })
        $type = & $typeOf $resourceId
        $who = [string](& $get $main 'caller')
        if (-not (& $like (& $groupOf $resourceId) @($ResourceGroupName))) { continue }
        if (-not (& $like $type @($ResourceType | ForEach-Object { $_.ToLowerInvariant() }))) { continue }
        if (-not (& $like $who @($Caller))) { continue }
        if ($status -eq 'Failed' -and -not $IncludeFailed) { continue }
        $at = & $time (& $get $first 'eventTimestamp')
        $kind = if ($action -match '(?i)/delete$') { 'Delete' } elseif ($action -match '(?i)/action$') { 'Action' } else { 'Write' }
        # Its property changes.
        $diffs = @()
        $created = $false
        $found = @(if ($byCorrelation.Contains($key)) { $byCorrelation[$key] | Where-Object { $_.ResourceId -eq $resourceId -or -not $resourceId } })
        if (-not $found.Count -and $byResource.Contains($resourceId)) { $found = @($byResource[$resourceId] | Where-Object { $_.At -and $at -and [Math]::Abs(($_.At - $at).TotalMinutes) -le 5 }) }
        foreach ($f in $found) { if ($f.Kind -eq 'Create') { $created = $true }; $diffs += @(& $describe $f.Changes) }
        if ($kind -eq 'Write') { $kind = if ($created) { 'Create' } else { 'Update' } }
        # The risk of the operation.
        $risky = '(?i)Microsoft\.Authorization/(roleAssignments|locks|policyAssignments|policyExemptions|roleDefinitions)|Microsoft\.KeyVault/vaults/accessPolicies|Microsoft\.Network/(networkSecurityGroups|azureFirewalls|firewallPolicies|publicIPAddresses)|/listKeys/action|/regenerateKey|Microsoft\.Insights/diagnosticSettings/delete|/securityRules/'
        $risk = if ($kind -eq 'Delete' -or $action -match $risky) { 'High' }
        elseif ($action -match '(?i)^Microsoft\.Network/' -or @($diffs | Where-Object { $_.Path -match '(?i)sku|vmSize|hardwareProfile|capacity|tier' }).Count -or $action -match '(?i)/(restart|deallocate|powerOff|stop)/action$') { 'Medium' }
        else { 'Low' }
        if ($status -eq 'Failed') { $risk = 'Info' }
        # How to undo it.
        $revert = switch ($kind) {
            'Create' { 'Delete it if it wasn''t wanted.' }
            'Update' { if ($diffs.Count) { 'Set back: ' + ((@($diffs | Select-Object -First 4 | ForEach-Object { "$($_.Path) = $($_.Before)" })) -join '; ') + $(if ($diffs.Count -gt 4) { " (+$($diffs.Count - 4) more)" }) } else { 'Redeploy the previous configuration (the property changes weren''t recorded).' } }
            'Delete' { if ($type -eq 'microsoft.keyvault/vaults') { 'Recover the soft-deleted vault (Key Vault > Manage deleted vaults), within its retention.' } else { 'Recreate it from infrastructure as code or a backup - a delete is the hardest change to undo.' } }
            default { if ($action -match '(?i)listKeys') { 'Not reversible: the keys were read - rotate them if that wasn''t expected.' } else { 'Not reversible (an action), but usually repeatable or harmless.' } }
        }
        $effort = switch ($kind) { 'Create' { 'Low' } 'Update' { if ($diffs.Count -and $diffs.Count -le 4) { 'Low' } else { 'Medium' } } 'Delete' { if ($type -eq 'microsoft.keyvault/vaults') { 'Medium' } else { 'High' } } default { 'Low' } }
        # What followed it.
        $groupName = & $lower (& $groupOf $resourceId)
        $after = @($incidents | Where-Object { $_.Time -and $at -and $_.Time -ge $at -and ($_.Time - $at).TotalMinutes -le $CorrelationMinutes -and ($_.ResourceId -eq $resourceId -or ($_.Kind -eq 'Alert' -and $groupName -and $_.ResourceGroup -eq $groupName)) } | Sort-Object Time)
        if ($after.Count -and $status -ne 'Failed') {
            $worst = @($after.Severity | ForEach-Object { [string]$_ } | Sort-Object)[0]
            $risk = if ($worst -in 'Sev0', 'Sev1' -and $risk -in 'High', 'Critical') { 'Critical' } elseif ($severity.Rank[$risk] -gt 1) { 'High' } else { $risk }
        }
        $client = [string](& $get (& $get $main 'httpRequest') 'clientIpAddress')
        $originKind = if ($who -match '@') { 'Manual' } elseif ($who -match '^[0-9a-fA-F-]{36}$') { 'Automation' } elseif ($who) { 'Automation' } else { 'Azure' }
        $changes.Add((New-AACFinding -TypeName 'AAC.ChangeRecord' -Severity $risk -Category $kind -Finding "$kind $(& $leaf $resourceId) - $(& $text (& $get $main 'operationName'))$(if ($status -and $status -ne 'Succeeded') { " ($status)" })" `
                    -ResourceId $resourceId -ResourceType $type -Subscription (& $subOf $resourceId) -Detail $(if ($diffs.Count) { (@($diffs | Select-Object -First 6 | ForEach-Object { "$($_.Path): $($_.Before) -> $($_.After)" })) -join '; ' } else { '' }) `
                    -Impact $(if ($after.Count) { "Followed by: " + ((@($after | Select-Object -First 3 | ForEach-Object { "$($_.Kind) $($_.Name) ($($_.Severity)) at $($_.Time.ToString('HH:mm'))" })) -join '; ') } else { '' }) `
                    -Remediation $revert -Effort $effort -Link "https://portal.azure.com/#view/Microsoft_Azure_ActivityLog/ActivityLogBlade" -Property ([ordered]@{
                        Time = $at; Caller = $who; Origin = $originKind; ClientIp = $client; Operation = $action; Status = $(if ($status) { $status } else { 'Started' }); CorrelationId = $key
                        PropertiesChanged = $diffs.Count; Revert = $revert; RelatedIncidents = $after.Count
                    })))
    }
    $sorted = @($changes | Sort-Object -Property Time -Descending)
    @{
        Changes   = $sorted
        Incidents = @($incidents | Sort-Object -Property Time -Descending)
        Stats     = @{
            Changes  = $sorted.Count
            Deletes  = @($sorted | Where-Object Category -EQ 'Delete').Count
            High     = @($sorted | Where-Object { $_.Severity -in 'Critical', 'High' }).Count
            Manual   = @($sorted | Where-Object Origin -EQ 'Manual').Count
            Linked   = @($sorted | Where-Object { $_.RelatedIncidents -gt 0 }).Count
            Failed   = @($sorted | Where-Object Status -EQ 'Failed').Count
            Callers  = @($sorted | ForEach-Object Caller | Where-Object { $_ } | Select-Object -Unique).Count
        }
    }
}
