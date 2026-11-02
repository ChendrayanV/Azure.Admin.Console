function ConvertTo-AACActivityLogAssessment {
    <#
    .SYNOPSIS
        Joins the Activity Log (Read-AACActivityLog's distinct rows) to the
        resources: who did what to each resource, when it was last used, which
        are idle or deleted, and what needs a look. For
        Invoke-AACActivityLogAssessment.
    .DESCRIPTION
        -Row are Read-AACActivityLog's rows; -Resource the subscriptions'
        resources as Resource Manager lists them (id, name, type, location,
        tags, createdTime, changedTime) with SubscriptionId. An event on a
        child (a blob service, a diagnostic setting) counts for the top-level
        resource it belongs to.

        Callers (CallerKind): Managed identity (the token names its
        resource), Service principal (an app token, or a GUID caller), User,
        Guest user (#EXT#), Azure platform (no caller), Other. -DirectoryName
        maps an object ID to its display name (-ResolveIdentity).

        Each resource (AAC.ActivityLogResource): its activity in the window -
        operations, writes, deletes, actions, failures, changes made by
        people, callers, the last operation and by whom, the earliest write
        by - and LastUsed: the latest of its last Activity Log event, its
        last change (changedTime) and its creation, with LastUsedSource and
        IdleDays. State: Active (activity in the window), New (created in
        it), Idle (nothing for -IdleDays or more), Quiet (no activity, but
        changed more recently), Deleted (deleted in the window), Gone (has
        activity, but isn't there now and no delete was seen - another scope,
        or moved). Resources deleted in the window are listed too.

        Findings (AAC.ActivityLogFinding):
          High    a guest user changed resources; people changed access
                  (role assignments and definitions, locks, policy
                  assignments and exemptions)
          Medium  people read or regenerated keys and secrets (listKeys,
                  listSecrets, regenerateKey ...); a resource with 10 or more
                  failed operations; a subscription whose Activity Log isn't
                  sent to a workspace (90 days only), or whose workspace keeps
                  less than the window
          Low     changed by hand (people, not automation); idle for
                  -IdleDays or more; missing a -RequiredTag
          Info    deleted in the window
        Returns @{ Resources; Activity; Callers; Findings; Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyCollection()]
        [object[]] $Row = @(),

        [AllowEmptyCollection()]
        [object[]] $Resource = @(),

        [System.Collections.IDictionary] $SubscriptionName = @{},

        [Parameter(Mandatory)]
        [datetime] $Start,

        [Parameter(Mandatory)]
        [datetime] $End,

        [AllowEmptyCollection()]
        [object[]] $Coverage = @(),

        [string[]] $TagName = @(),

        [string[]] $RequiredTag = @(),

        [ValidateRange(1, 3650)]
        [int] $IdleDays = 90,

        [System.Collections.IDictionary] $DirectoryName = @{}
    )

    $comparer = [StringComparer]::OrdinalIgnoreCase
    $toTime = {
        param($Value)
        if ($null -eq $Value -or '' -eq $Value) { return $null }
        if ($Value -is [datetime]) { return $Value.ToUniversalTime() }
        [datetime]::Parse([string]$Value, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]'AdjustToUniversal, AssumeUniversal')
    }
    $subName = { param([string] $Id) if (-not $Id) { '' } else { $n = $SubscriptionName[$Id.ToLowerInvariant()]; if ($n) { [string]$n } else { $Id } } }
    $tagText = { param($Tags) if ($Tags -is [System.Collections.IDictionary]) { (@($Tags.Keys | Sort-Object | ForEach-Object { "$_=$($Tags[$_])" })) -join '; ' } else { '' } }

    # A resource ID's parts, and the top-level resource an ID belongs to. Cached: IDs repeat.
    $parts = [System.Collections.Generic.Dictionary[string, hashtable]]::new($comparer)
    $split = {
        param([string] $Id)
        if (-not $Id) { return @{ SubscriptionId = ''; ResourceGroup = ''; Type = ''; Name = ''; TopId = '' } }
        $known = $null
        if ($parts.TryGetValue($Id, [ref]$known)) { return $known }
        $p = @{ SubscriptionId = ''; ResourceGroup = ''; Type = ''; Name = ''; TopId = '' }
        $s = $Id.Trim('/').Split('/')
        $provider = -1
        for ($i = 0; $i -lt $s.Count - 1; $i++) {
            if ($s[$i] -eq 'subscriptions' -and -not $p.SubscriptionId) { $p.SubscriptionId = $s[$i + 1] }
            elseif ($s[$i] -eq 'resourcegroups' -and -not $p.ResourceGroup) { $p.ResourceGroup = $s[$i + 1] }
            elseif ($s[$i] -eq 'providers' -and $provider -lt 0) { $provider = $i }
        }
        if ($provider -ge 0 -and $s.Count -ge $provider + 4) { $p.Type = "$($s[$provider + 1])/$($s[$provider + 2])"; $p.Name = $s[$provider + 3]; $p.TopId = '/' + (($s[0..($provider + 3)]) -join '/') }
        elseif ($p.ResourceGroup) { $p.Type = 'Microsoft.Resources/resourceGroups'; $p.Name = $p.ResourceGroup; $p.TopId = "/subscriptions/$($p.SubscriptionId)/resourceGroups/$($p.ResourceGroup)" }
        elseif ($p.SubscriptionId) { $p.Type = 'Microsoft.Resources/subscriptions'; $p.Name = (& $subName $p.SubscriptionId); $p.TopId = "/subscriptions/$($p.SubscriptionId)" }
        $parts[$Id] = $p
        $p
    }
    $callers = [System.Collections.Generic.Dictionary[string, hashtable]]::new($comparer)
    $who = {
        param($R)
        $key = "$($R.Caller)|$($R.Mirid)|$($R.AppId)|$($R.TokenType)|$($R.Upn)"
        $known = $null
        if ($callers.TryGetValue($key, [ref]$known)) { return $known }
        $caller = [string]$R.Caller
        $known = Get-AACActivityLogCaller -Caller $caller -ManagedIdentity ([string]$R.Mirid) -TokenType ([string]$R.TokenType) -Upn ([string]$R.Upn)
        if ($known.Kind -eq 'Service principal' -and $DirectoryName.Contains($caller.ToLowerInvariant())) { $known.Name = "$($DirectoryName[$caller.ToLowerInvariant()]) ($caller)" }
        $callers[$key] = $known
        $known
    }
    $kindOf = { param([string] $Operation) if ($Operation -match '(?i)/delete$') { 'Delete' } elseif ($Operation -match '(?i)/write$') { 'Write' } elseif ($Operation -match '(?i)/action$') { 'Action' } else { 'Other' } }
    $accessPattern = '(?i)^microsoft\.authorization/(roleassignments|roledefinitions|locks|policyassignments|policyexemptions|policydefinitions|policysetdefinitions)/(write|delete)$'
    $secretPattern = '(?i)/(listkeys|listsecrets|regeneratekey|regeneratekeys|listcredential|listcredentials|listadminkeys|listconnectionstrings|listaccountsas|listservicesas|listkeyvalue|getsecret)/action$'

    # --- The inventory ------------------------------------------------------------------------------------------------------
    $inventory = [System.Collections.Generic.Dictionary[string, hashtable]]::new($comparer)
    foreach ($r in $Resource) {
        if ($r -isnot [System.Collections.IDictionary] -or -not $r['id']) { continue }
        $p = & $split ([string]$r['id'])
        $inventory[[string]$r['id']] = @{
            Id = [string]$r['id']; Name = [string]$r['name']; Type = [string]$r['type']; Location = [string]$r['location']; Group = $p.ResourceGroup
            SubscriptionId = $(if ($r['SubscriptionId']) { [string]$r['SubscriptionId'] } else { $p.SubscriptionId }); Tags = $(if ($r['tags'] -is [System.Collections.IDictionary]) { $r['tags'] } else { @{} })
            Created = (& $toTime $r['createdTime']); Changed = (& $toTime $r['changedTime'])
        }
    }

    # --- Distinct activity, per top-level resource -------------------------------------------------------------------------
    $merged = [System.Collections.Generic.Dictionary[string, hashtable]]::new($comparer)
    foreach ($r in $Row) {
        if ($null -eq $r) { continue }
        $p = & $split ([string]$r.ResourceId)
        $c = & $who $r
        $key = "$($p.TopId)|$($c.Name)|$($r.Operation)|$($r.Status)"
        $first = & $toTime $r.First
        $last = & $toTime $r.Last
        $m = $null
        if (-not $merged.TryGetValue($key, [ref]$m)) {
            $m = @{ Parts = $p; Caller = $c; Operation = [string]$r.Operation; OperationName = [string]$r.OperationName; Status = [string]$r.Status; Category = [string]$r.Category; Count = [long]0; First = $first; Last = $last; CallerIp = [string]$r.CallerIp; Source = [string]$r.Source
                CorrelationId = [string]$r.CorrelationId; StatusMessage = [string]$r.StatusMessage; StatusCode = [string]$r.StatusCode; SubStatus = [string]$r.SubStatus }
            $merged[$key] = $m
        }
        $m.Count += [long]$r.Count
        if ($first -and (-not $m.First -or $first -lt $m.First)) { $m.First = $first }
        if ($last -and (-not $m.Last -or $last -gt $m.Last)) {
            $m.Last = $last; $m.CorrelationId = [string]$r.CorrelationId; $m.StatusMessage = [string]$r.StatusMessage; $m.StatusCode = [string]$r.StatusCode; $m.SubStatus = [string]$r.SubStatus
            if ($r.CallerIp) { $m.CallerIp = [string]$r.CallerIp }
        }
        if (-not $m.OperationName -and $r.OperationName) { $m.OperationName = [string]$r.OperationName }
    }
    $activity = [System.Collections.Generic.List[object]]::new()
    $byResource = [System.Collections.Generic.Dictionary[string, object]]::new($comparer)
    foreach ($m in $merged.Values) {
        $p = $m.Parts
        $item = $null
        $exists = $p.TopId -and $inventory.TryGetValue($p.TopId, [ref]$item)
        $out = [ordered]@{
            PSTypeName    = 'AAC.ActivityLogActivity'
            Subscription  = (& $subName $p.SubscriptionId)
            ResourceGroup = $p.ResourceGroup
            ResourceType  = $(if ($exists) { $item.Type } else { $p.Type })
            Resource      = $(if ($exists) { $item.Name } else { $p.Name })
            Exists        = [bool]$exists -or $p.Type -like 'Microsoft.Resources/*'
            Tags          = $(if ($exists) { & $tagText $item.Tags } else { '' })
        }
        foreach ($t in $TagName) { $out["Tag:$t"] = $(if ($exists -and $item.Tags.Contains($t)) { [string]$item.Tags[$t] } else { '' }) }
        $out.CallerKind = $m.Caller.Kind
        $out.Caller = $m.Caller.Name
        $out.Operation = $(if ($m.OperationName) { $m.OperationName } else { $m.Operation })
        $out.Kind = & $kindOf $m.Operation
        $out.Status = $m.Status
        $out.Count = $m.Count
        $out.First = $m.First
        $out.Last = $m.Last
        # Why the latest failed: the same reading Get-AACResourceError gives.
        $why = if ($m.Status -eq 'Failed') { Read-AACActivityLogError -StatusMessage $m.StatusMessage -StatusCode $m.StatusCode -SubStatus $m.SubStatus -Operation $m.Operation -EventCategory $m.Category } else { $null }
        $out.ErrorCode = $(if ($why) { $why.Code } else { '' })
        $out.ErrorMessage = $(if ($why) { $why.Message } else { '' })
        $out.CallerIp = $m.CallerIp
        $out.OperationType = $m.Operation
        $out.Category = $m.Category
        $out.Source = $m.Source
        $out.ResourceId = $p.TopId
        $out.SubscriptionId = $p.SubscriptionId
        # The latest operation's: pipe the row to Show-AACActivityLogEvent for every event of it.
        $out.CorrelationId = $m.CorrelationId
        $o = [pscustomobject]$out
        $activity.Add($o)
        if ($p.TopId) {
            $list = $null
            if (-not $byResource.TryGetValue($p.TopId, [ref]$list)) { $list = [System.Collections.Generic.List[object]]::new(); $byResource[$p.TopId] = $list }
            $list.Add($o)
        }
    }
    $activityRows = @($activity | Sort-Object -Property Last -Descending)

    # --- Each resource: its activity and when it was last used ------------------------------------------------------------
    # Rows are picked by index, not Select-Object -First: that stamps 'Selected.' on the
    # objects it passes, and these are the rows the command returns.
    $findings = [System.Collections.Generic.List[object]]::new()
    $finding = {
        param([string] $Severity, [string] $Area, [string] $Subject, [string] $Text, [string] $Detail, [string] $Recommendation, [string] $Id = '')
        $findings.Add([pscustomobject]@{ PSTypeName = 'AAC.ActivityLogFinding'; Severity = $Severity; Area = $Area; Resource = $Subject; Finding = $Text; Detail = $Detail; Recommendation = $Recommendation; ResourceId = $Id })
    }
    $sum = { param($List, [scriptblock] $Where) $n = [long]0; foreach ($x in $List) { if (& $Where $x) { $n += $x.Count } }; $n }
    $resourceRows = [System.Collections.Generic.List[object]]::new()
    $ids = [System.Collections.Generic.HashSet[string]]::new([string[]]@($inventory.Keys), $comparer)
    foreach ($topId in $byResource.Keys) {
        $p = & $split $topId
        if ($p.Type -notlike 'Microsoft.Resources/*') { $null = $ids.Add($topId) }
    }
    foreach ($id in $ids) {
        $item = $null
        $exists = $inventory.TryGetValue($id, [ref]$item)
        $p = & $split $id
        $list = $null
        $null = $byResource.TryGetValue($id, [ref]$list)
        $list = @(if ($list) { $list | Sort-Object -Property Last -Descending })
        $last = if ($list.Count) { $list[0] } else { $null }
        $ok = @($list | Where-Object Status -NE 'Failed')
        $deletes = @($ok | Where-Object Kind -EQ 'Delete' | Sort-Object -Property Last -Descending)
        $deleted = if ($deletes.Count) { $deletes[0] } else { $null }
        $writes = @($ok | Where-Object Kind -EQ 'Write' | Sort-Object -Property First)
        $firstWrite = if ($writes.Count) { $writes[0] } else { $null }
        $tags = if ($exists) { $item.Tags } else { @{} }
        $used = @(
            @{ Time = $(if ($last) { $last.Last }); Source = 'Activity Log' }
            @{ Time = $(if ($exists) { $item.Changed }); Source = 'Last changed' }
            @{ Time = $(if ($exists) { $item.Created }); Source = 'Created' }
        ) | Where-Object { $_.Time } | Sort-Object -Property { $_.Time } -Descending | Select-Object -First 1
        $operations = & $sum $list { $true }
        $idle = if ($used) { [int][Math]::Floor(($End - $used.Time).TotalDays) } else { $null }
        $state = if (-not $exists -and $deleted) { 'Deleted' }
        elseif (-not $exists) { 'Gone' }
        elseif ($item.Created -and $item.Created -ge $Start) { 'New' }
        elseif ($operations) { 'Active' }
        elseif ($null -ne $idle -and $idle -ge $IdleDays) { 'Idle' }
        else { 'Quiet' }
        $name = if ($exists) { $item.Name } else { $p.Name }
        $out = [ordered]@{
            PSTypeName    = 'AAC.ActivityLogResource'
            Subscription  = (& $subName $(if ($exists) { $item.SubscriptionId } else { $p.SubscriptionId }))
            ResourceGroup = $(if ($exists) { $item.Group } else { $p.ResourceGroup })
            ResourceType  = $(if ($exists) { $item.Type } else { $p.Type })
            Resource      = $name
            State         = $state
            Location      = $(if ($exists) { $item.Location } else { '' })
            Tags          = (& $tagText $tags)
        }
        foreach ($t in $TagName) { $out["Tag:$t"] = $(if ($tags.Contains($t)) { [string]$tags[$t] } else { '' }) }
        $out.LastUsed = $(if ($used) { $used.Time })
        $out.LastUsedSource = $(if ($used) { $used.Source } else { '' })
        $out.IdleDays = $idle
        $out.Operations = $operations
        $out.Writes = & $sum $ok { param($x) $x.Kind -eq 'Write' }
        $out.Deletes = & $sum $ok { param($x) $x.Kind -eq 'Delete' }
        $out.Actions = & $sum $ok { param($x) $x.Kind -eq 'Action' }
        $out.Failed = & $sum $list { param($x) $x.Status -eq 'Failed' }
        $out.ByPeople = & $sum $ok { param($x) $x.CallerKind -in 'User', 'Guest user' -and $x.Kind -in 'Write', 'Delete' }
        $out.LastActivity = $(if ($last) { $last.Last })
        $out.LastOperation = $(if ($last) { $last.Operation })
        $out.LastCaller = $(if ($last) { $last.Caller })
        $out.LastCallerKind = $(if ($last) { $last.CallerKind })
        $out.FirstWriteBy = $(if ($firstWrite) { $firstWrite.Caller })
        $out.DeletedBy = $(if ($deleted) { $deleted.Caller })
        $out.Callers = (@($list | ForEach-Object Caller | Sort-Object -Unique)) -join '; '
        $out.Created = $(if ($exists) { $item.Created })
        $out.LastChanged = $(if ($exists) { $item.Changed })
        $out.ResourceId = $(if ($exists) { $item.Id } else { $id })
        $resourceRows.Add([pscustomobject]$out)

        if ($state -eq 'Deleted') { & $finding 'Info' 'Change' $name "Deleted $($deleted.Last.ToString('yyyy-MM-dd')) by $($deleted.Caller)" "A $($out.ResourceType) in $($out.ResourceGroup)." 'Check it was meant to go; the Activity tab shows what else was done to it.' $id }
        if ($out.Failed -ge 10) {
            $lastFailure = @($list | Where-Object Status -EQ 'Failed')[0]
            & $finding 'Medium' 'Operations' $name "$($out.Failed) failed operation(s)" "Last: $($lastFailure.Operation) by $($lastFailure.Caller)$(if ($lastFailure.ErrorCode) { " - $($lastFailure.ErrorCode): $($lastFailure.ErrorMessage)" })." 'Look at why they fail (Show-AACActivityLogEvent -CorrelationId, Get-AACResourceError): a pipeline retrying, a policy denying, or a lock.' $out.ResourceId
        }
        if ($out.ByPeople -and $exists) { & $finding 'Low' 'Change' $name "Changed by hand $($out.ByPeople) time(s)" "By $((@($list | Where-Object { $_.CallerKind -in 'User', 'Guest user' -and $_.Kind -in 'Write', 'Delete' } | ForEach-Object Caller | Sort-Object -Unique)) -join ', ')." 'Make the change in the infrastructure code too, or the next deployment undoes it.' $out.ResourceId }
        if ($state -eq 'Idle') { & $finding 'Low' 'Usage' $name "No change for $idle day(s)" "Last: $($out.LastUsedSource.ToLowerInvariant()) $($out.LastUsed.ToString('yyyy-MM-dd'))." 'Check it is still needed - its metrics show data-plane use, which the Activity Log does not.' $out.ResourceId }
        if ($exists -and $RequiredTag.Count) {
            $missing = @($RequiredTag | Where-Object { -not $tags.Contains($_) -or -not [string]$tags[$_] })
            if ($missing.Count) { & $finding 'Low' 'Tags' $name "Missing tag(s): $($missing -join ', ')" "Last changed by $(if ($out.LastCaller) { $out.LastCaller } else { 'nobody in the window' })." 'Add the tags, or enforce them with Azure Policy (Require a tag on resources).' $out.ResourceId }
        }
    }

    # --- Who acted ----------------------------------------------------------------------------------------------------------
    $callerRows = @($activityRows | Group-Object -Property Caller | ForEach-Object {
            $g = @($_.Group)
            $okRows = @($g | Where-Object Status -NE 'Failed')
            [pscustomobject]@{
                PSTypeName = 'AAC.ActivityLogCaller'
                Caller     = $_.Name
                CallerKind = $g[0].CallerKind
                Operations = & $sum $g { $true }
                Writes     = & $sum $okRows { param($x) $x.Kind -eq 'Write' }
                Deletes    = & $sum $okRows { param($x) $x.Kind -eq 'Delete' }
                Failed     = & $sum $g { param($x) $x.Status -eq 'Failed' }
                Resources  = @($g | ForEach-Object ResourceId | Where-Object { $_ } | Sort-Object -Unique).Count
                LastSeen   = ($g | Measure-Object -Property Last -Maximum).Maximum
                TopOperations = (@($g | Group-Object -Property Operation | ForEach-Object { @{ Name = $_.Name; Count = (& $sum $_.Group { $true }) } } | Sort-Object -Property { $_.Count } -Descending | Select-Object -First 3 | ForEach-Object { "$($_.Name) ($($_.Count))" })) -join '; '
            }
        } | Sort-Object -Property Operations -Descending)

    # --- Findings about people and access ----------------------------------------------------------------------------------
    foreach ($g in @($activityRows | Where-Object { $_.CallerKind -eq 'Guest user' -and $_.Status -ne 'Failed' -and $_.Kind -in 'Write', 'Delete', 'Action' } | Group-Object -Property Caller)) {
        & $finding 'High' 'Access' $g.Name "A guest user changed $(@($g.Group | ForEach-Object ResourceId | Sort-Object -Unique).Count) resource(s)" "$(& $sum $g.Group { $true }) operation(s), last $(($g.Group | Measure-Object -Property Last -Maximum).Maximum.ToString('yyyy-MM-dd')): $((@($g.Group | ForEach-Object Operation | Sort-Object -Unique | Select-Object -First 3)) -join ', ')." 'Check the guest still needs that access (Get-AACRoleAssignment), or give it to a member account.'
    }
    foreach ($g in @($activityRows | Where-Object { $_.CallerKind -in 'User', 'Guest user' -and $_.Status -ne 'Failed' -and $_.OperationType -match $accessPattern } | Group-Object -Property Caller)) {
        & $finding 'High' 'Access' $g.Name "Changed access by hand: $(& $sum $g.Group { $true }) time(s)" "$((@($g.Group | ForEach-Object { "$($_.Operation) on $($_.Resource)" } | Sort-Object -Unique | Select-Object -First 3)) -join '; ')." 'Review the change (Get-AACRoleAssignment, Get-AACGovernanceChange); make access changes through approved, coded processes.'
    }
    foreach ($g in @($activityRows | Where-Object { $_.CallerKind -in 'User', 'Guest user' -and $_.Status -ne 'Failed' -and $_.OperationType -match $secretPattern } | Group-Object -Property ResourceId)) {
        & $finding 'Medium' 'Secrets' $g.Group[0].Resource "Keys or secrets read by people $(& $sum $g.Group { $true }) time(s)" "By $((@($g.Group | ForEach-Object Caller | Sort-Object -Unique)) -join ', '): $((@($g.Group | ForEach-Object Operation | Sort-Object -Unique)) -join ', ')." 'Move the callers to Entra ID roles and managed identities, and rotate keys that were read.' $g.Name
    }
    foreach ($c in $Coverage) {
        if ($c.Source -eq 'Activity Log' -and $c.CoveredFrom -and $c.CoveredFrom -gt $Start.AddDays(1)) {
            & $finding 'Medium' 'Coverage' $c.Subscription 'The Activity Log is not sent to a workspace: only 90 days are kept' $c.Note 'Add a diagnostic setting on the subscription that sends the Activity Log to a Log Analytics workspace - it keeps as long as its retention, and makes this assessment fast.'
        }
        elseif ($c.Source -eq 'Log Analytics' -and $c.RetentionDays -and $c.CoveredFrom -gt $Start.AddDays(1)) {
            & $finding 'Medium' 'Coverage' $c.Subscription "Workspace $($c.Workspace) keeps $($c.RetentionDays) day(s), less than the window" $c.Note 'Raise the retention of the AzureActivity table (or the workspace) to cover what audits need.'
        }
    }

    $rank = Get-AACSeverityRank
    $states = @{}
    foreach ($s in 'Active', 'New', 'Idle', 'Quiet', 'Deleted', 'Gone') { $states[$s] = @($resourceRows | Where-Object State -EQ $s).Count }
    @{
        Resources = @($resourceRows | Sort-Object -Property @{ Expression = { $_.State -ne 'Active' } }, @{ Expression = { $_.Operations }; Descending = $true }, Resource)
        Activity  = $activityRows
        Callers   = $callerRows
        Findings  = @($findings | Sort-Object -Property @{ Expression = { $rank.Rank[$_.Severity] } }, Area, Resource)
        Stats     = @{
            Resources  = $resourceRows.Count
            Active     = $states['Active']; New = $states['New']; Idle = $states['Idle']; Quiet = $states['Quiet']; Deleted = $states['Deleted']; Gone = $states['Gone']
            Operations = & $sum $activityRows { $true }
            Failed     = & $sum $activityRows { param($x) $x.Status -eq 'Failed' }
            ByPeople   = & $sum $activityRows { param($x) $x.CallerKind -in 'User', 'Guest user' -and $x.Status -ne 'Failed' -and $x.Kind -in 'Write', 'Delete' }
            Callers    = $callerRows.Count
            High       = @($findings | Where-Object Severity -EQ 'High').Count
            Medium     = @($findings | Where-Object Severity -EQ 'Medium').Count
        }
    }
}
