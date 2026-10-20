function ConvertTo-AACResourceLock {
    <#
    .SYNOPSIS
        Builds Get-AACResourceLock's list (AAC.ResourceLock) from each
        subscription's locks and the Resource Graph inventory of resource
        groups and critical resources: every lock, and the critical
        resources no lock protects.
    .DESCRIPTION
        No Azure calls.
          -Lock          the locks (Microsoft.Authorization/locks items:
                         id, name, properties.level, notes, owners)
          -ResourceGroup Resource Graph rows: id, name, subscriptionId
          -Resource      Resource Graph rows of the critical types: id,
                         name, type, resourceGroup, subscriptionId
          -SubscriptionName  ID (lower case) -> name
        A lock protects its scope and everything below it: a lock on a
        subscription covers its resource groups and resources, one on a
        resource group its resources.

        Rows (AAC.ResourceLock):
          Locked    each lock - its level (CanNotDelete or ReadOnly), scope,
                    notes. A ReadOnly lock is a finding: Medium on a
                    subscription or resource group (it blocks more than
                    writes - listing storage keys, scaling, many portal
                    blades), Low on a resource
          Unlocked  each critical resource with no lock on it, its resource
                    group or its subscription - Low: one mistaken delete
                    away from losing it
        Returns @{ Locks; Notices; Stats } - Stats with how many critical
        resources are locked directly, through a parent, or not at all, and
        how many resource groups are covered.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyCollection()]
        [object[]] $Lock = @(),

        [AllowEmptyCollection()]
        [object[]] $ResourceGroup = @(),

        [AllowEmptyCollection()]
        [object[]] $Resource = @(),

        [hashtable] $SubscriptionName = @{},

        [string[]] $Unread = @()
    )

    $get = ${function:Get-AACMember}
    $text = { param($Object, [string] $Path) $v = & $get $Object $Path; if ($null -eq $v) { '' } else { [string]$v } }
    $notices = [System.Collections.Generic.List[string]]::new()
    foreach ($u in @($Unread | Where-Object { $_ })) { $notices.Add("The locks couldn't be read for $u - its resources show as unlocked even if they aren't.") }
    $subName = { param([string] $Id) if ($SubscriptionName.Contains($Id)) { $SubscriptionName[$Id] } else { $Id } }
    $describe = {
        param([string] $ScopeId)
        $s = $ScopeId.ToLowerInvariant()
        if ($s -match '^/subscriptions/([^/]+)/resourcegroups/([^/]+)/providers/(.+)/([^/]+)$') { return @{ Type = 'Resource'; Name = "$($Matches[4]) ($($Matches[2]))"; Sub = $Matches[1]; ResourceType = (($Matches[3] -split '/') | Select-Object -First 2) -join '/' } }
        if ($s -match '^/subscriptions/([^/]+)/resourcegroups/([^/]+)$') { return @{ Type = 'Resource group'; Name = "$($Matches[2]) ($(& $subName $Matches[1]))"; Sub = $Matches[1]; ResourceType = '' } }
        if ($s -match '^/subscriptions/([^/]+)$') { return @{ Type = 'Subscription'; Name = (& $subName $Matches[1]); Sub = $Matches[1]; ResourceType = '' } }
        @{ Type = 'Other'; Name = $ScopeId; Sub = ''; ResourceType = '' }
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    $add = {
        param([string] $Severity, [string] $Status, [string] $Level, [string] $Name, $Where, [string] $Notes, [string] $Findings, [string] $ScopeId, [string] $Id, [string] $ResourceType = '')
        $item = [pscustomobject][ordered]@{
            Severity     = $Severity
            Status       = $Status
            Level        = $Level
            Lock         = $Name
            ScopeType    = $Where.Type
            Scope        = $Where.Name
            ResourceType = $(if ($ResourceType) { $ResourceType } else { $Where.ResourceType })
            Notes        = $Notes
            Findings     = $Findings
            Subscription = $(if ($Where.Sub) { & $subName $Where.Sub } else { '' })
            ScopeId      = $ScopeId
            Id           = $Id
        }
        $item.PSObject.TypeNames.Insert(0, 'AAC.ResourceLock')
        $rows.Add($item)
    }

    # --- The locks, and the scopes they cover ---------------------------------------------------------------------------------
    $lockedScopes = @{}
    $seen = @{}
    foreach ($l in @($Lock)) {
        $id = & $text $l 'id'
        if (-not $id -or $seen.Contains($id.ToLowerInvariant())) { continue }
        $seen[$id.ToLowerInvariant()] = $true
        $scopeId = ($id -replace '(?i)/providers/Microsoft\.Authorization/locks/[^/]+$', '').ToLowerInvariant()
        $where = & $describe $scopeId
        $p = & $get $l 'properties'
        $level = & $text $p 'level'
        $lockedScopes[$scopeId] = $level
        $severity = 'Info'; $finding = ''
        if ($level -eq 'ReadOnly') {
            if ($where.Type -in 'Subscription', 'Resource group') { $severity = 'Medium'; $finding = "A ReadOnly lock on a $($where.Type.ToLowerInvariant()) blocks more than changes: listing storage keys, scaling, restarting and many portal pages fail too. Use CanNotDelete unless everything in it must be frozen." }
            else { $severity = 'Low'; $finding = 'ReadOnly blocks some reads too (listing keys, connection strings): check the resource still works as needed.' }
        }
        & $add $severity 'Locked' $level (& $text $l 'name') $where (& $text $p 'notes') $finding $scopeId $id
    }

    # --- Critical resources: locked directly, through a parent, or not at all ----------------------------------------------------
    $direct = 0; $inherited = 0; $open = 0
    foreach ($r in @($Resource)) {
        $id = (& $text $r 'id').ToLowerInvariant()
        $sub = (& $text $r 'subscriptionId').ToLowerInvariant()
        $group = "/subscriptions/$sub/resourcegroups/$((& $text $r 'resourceGroup').ToLowerInvariant())"
        if ($lockedScopes.Contains($id)) { $direct++; continue }
        if ($lockedScopes.Contains($group) -or $lockedScopes.Contains("/subscriptions/$sub")) { $inherited++; continue }
        $open++
        & $add 'Low' 'Unlocked' '' '' (& $describe $id) '' 'No lock on it, its resource group or its subscription: one mistaken delete away from losing it. Add a CanNotDelete lock.' $id '' (& $text $r 'type').ToLowerInvariant()
    }
    $groupsCovered = @($ResourceGroup | Where-Object { $gid = (& $text $_ 'id').ToLowerInvariant(); $sub = (& $text $_ 'subscriptionId').ToLowerInvariant(); $lockedScopes.Contains($gid) -or $lockedScopes.Contains("/subscriptions/$sub") }).Count

    $rank = (Get-AACSeverityRank).Rank
    $order = @{ Subscription = 0; 'Resource group' = 1; Resource = 2; Other = 3 }
    $sorted = @($rows | Sort-Object -Property @{ Expression = { $rank[$_.Severity] } }, Status, @{ Expression = { $order[$_.ScopeType] } }, Scope)
    @{
        Locks   = $sorted
        Notices = @($notices)
        Stats   = @{
            Locks           = @($sorted | Where-Object Status -EQ 'Locked').Count
            ReadOnly        = @($sorted | Where-Object Level -EQ 'ReadOnly').Count
            Critical        = @($Resource).Count
            Direct          = $direct
            Inherited       = $inherited
            Unlocked        = $open
            Groups          = @($ResourceGroup).Count
            GroupsCovered   = $groupsCovered
        }
    }
}
