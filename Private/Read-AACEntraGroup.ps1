function Read-AACEntraGroup {
    <#
    .SYNOPSIS
        Reads Entra ID groups and their members from Microsoft Graph - the
        groups asked for, then their members and the members of every
        nested group, a level at a time, several requests at once.
    .DESCRIPTION
        Groups (GET /v1.0/groups, following @odata.nextLink):
          -GroupName            one exact displayName filter per name
          -GroupNameStartsWith  startswith(displayName, ...)
          neither               every group
        Members (GET /v1.0/groups/{id}/members, $top=999): the groups found,
        then the groups nested in them, and so on - each group read once,
        however many groups it is nested in - up to 20 levels.

        Up to 8 requests run at once (Invoke-AACHttpBatch); throttling (429)
        waits as long as Graph's Retry-After asks. The token comes from the
        Connect-AAC sign-in (Get-AACAccessToken -Resource
        https://graph.microsoft.com) - no second sign-in.

        Returns @{ Groups; Members (group ID -> members); MemberErrors
        (group ID -> why they couldn't be read); Missing (names with no
        group) }. Progress goes to the Invoke-AACProgress display.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string[]] $GroupName = @(),

        [string] $GroupNameStartsWith
    )

    $graph = 'https://graph.microsoft.com/v1.0'
    $groupSelect = 'id,displayName,description,groupTypes,securityEnabled,mailEnabled,isAssignableToRole,onPremisesSyncEnabled,membershipRule,mail'
    $memberSelect = 'id,displayName,userPrincipalName,mail,userType,accountEnabled,jobTitle,department'
    # An OData string literal: single quotes doubled, then URL-escaped.
    $literal = { param([string] $Text) [System.Uri]::EscapeDataString("'" + ($Text -replace "'", "''") + "'") }

    # --- The groups ---------------------------------------------------------------------------------
    $filters = [ordered]@{}
    foreach ($name in @($GroupName | Where-Object { $_ } | Select-Object -Unique)) { $filters["name:$name"] = "displayName eq $(& $literal $name)" }
    if ($GroupNameStartsWith) { $filters['prefix'] = "startswith(displayName,$(& $literal $GroupNameStartsWith))" }
    if (-not $filters.Count) { $filters['all'] = '' }
    $found = @{}
    foreach ($key in $filters.Keys) { $found[$key] = [System.Collections.Generic.List[object]]::new() }
    $requests = @(foreach ($key in $filters.Keys) {
            @{ Key = $key; Body = $null; Uri = "$graph/groups?`$select=$groupSelect&`$top=999$(if ($filters[$key]) { "&`$filter=$($filters[$key])" })" }
        })
    $pages = {
        param($Key, [string] $Content)
        $page = ConvertFrom-Json -InputObject $Content -AsHashtable -Depth 20
        foreach ($item in @($page['value'])) { if ($null -ne $item) { $found[$Key].Add($item) } }
        if ($page['@odata.nextLink']) { @{ Uri = [string]$page['@odata.nextLink'] } }
    }
    Update-AACProgress -Id 'groups' -Indeterminate -Description $(if ($filters.Contains('all')) { 'Finding every group in Microsoft Graph' } else { 'Finding the groups in Microsoft Graph' })
    $failures = Invoke-AACHttpBatch -Request $requests -OnResponse $pages -Resource 'https://graph.microsoft.com' -ThrottleLimit 8
    foreach ($key in $failures.Keys) {
        if ($failures[$key]) {
            throw "Microsoft Graph refused to list the groups: $($failures[$key].TrimEnd('.')). Your account needs to be allowed to read groups in Entra ID (members can by default; guests, or tenants that restrict it, can't). With an App Registration of your own in Connect-AAC -ClientId, give it Microsoft Graph's delegated Group.Read.All and User.Read.All permissions."
        }
    }
    $groups = @{}
    foreach ($key in $filters.Keys) { foreach ($g in $found[$key]) { $groups[[string]$g['id']] = $g } }
    $missing = @(foreach ($name in @($GroupName | Where-Object { $_ } | Select-Object -Unique)) { if (-not $found["name:$name"].Count) { $name } })
    Update-AACProgress -Id 'groups' -Complete -Description ('Found {0:N0} group(s){1}' -f $groups.Count, $(if ($missing.Count) { "; $($missing.Count) name(s) not found" }))

    # --- Their members, a level of nesting at a time -------------------------------------------------
    $members = @{}
    $memberErrors = @{}
    $read = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $next = @($groups.Keys)
    $level = 0
    $calls = 0
    Update-AACProgress -Id 'members' -Total ([Math]::Max(1, $next.Count)) -Description ('Reading the members of {0:N0} group(s)' -f $next.Count)
    while ($next.Count -and $level -lt 20) {
        $level++
        $batch = @($next | Where-Object { $read.Add($_) })
        if (-not $batch.Count) { break }
        foreach ($id in $batch) { $members[$id] = [System.Collections.Generic.List[object]]::new() }
        $memberPages = {
            param($Key, [string] $Content)
            $page = ConvertFrom-Json -InputObject $Content -AsHashtable -Depth 20
            foreach ($item in @($page['value'])) { if ($null -ne $item) { $members[$Key].Add($item) } }
            if ($page['@odata.nextLink']) { @{ Uri = [string]$page['@odata.nextLink'] } }
        }
        $before = $calls
        $failures = Invoke-AACHttpBatch -Request @($batch | ForEach-Object { @{ Key = $_; Body = $null; Uri = "$graph/groups/$_/members?`$select=$memberSelect&`$top=999" } }) -OnResponse $memberPages -Resource 'https://graph.microsoft.com' -ThrottleLimit 8 -OnDone {
            param($Key, $Failure, $Done, $Total)
            Update-AACProgress -Id 'members' -Total ($before + $Total) -Increment 1 -Description ('Reading the members of {0:N0} group(s){1}' -f ($before + $Done), $(if ($level -gt 1) { " (nesting level $level)" }))
        }
        $calls += $batch.Count
        foreach ($key in $failures.Keys) { if ($failures[$key]) { $memberErrors[$key] = $failures[$key] } }
        # The groups nested in these, not read yet.
        $next = @($batch | ForEach-Object { $members[$_] } | Where-Object { [string]$_['@odata.type'] -eq '#microsoft.graph.group' } | ForEach-Object { [string]$_['id'] } | Where-Object { -not $read.Contains($_) } | Select-Object -Unique)
    }
    $memberCount = 0
    foreach ($list in $members.Values) { $memberCount += $list.Count }
    Update-AACProgress -Id 'members' -Complete -Description ('Read {0:N0} membership(s) of {1:N0} group(s), {2:N0} of them nested{3}' -f $memberCount, $read.Count, ($read.Count - $groups.Count), $(if ($memberErrors.Count) { "; $($memberErrors.Count) could not be read" }))

    $plain = @{}
    foreach ($key in $members.Keys) { $plain[$key] = $members[$key].ToArray() }
    @{
        Groups       = @($groups.Values)
        Members      = $plain
        MemberErrors = $memberErrors
        Missing      = $missing
    }
}
