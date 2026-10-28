function Read-AACServiceBusEntityState {
    <#
    .SYNOPSIS
        Reads queues and topics of one Service Bus namespace as the signed-in
        user - with a role on the namespace, or only on the entities - and
        says which of the two it had.
    .DESCRIPTION
        For Show-AACServiceBusEntity. Unlike Read-AACServiceBusEntity (the
        assessment's, which lists every entity and so needs the namespace),
        this works for someone who holds only Azure Service Bus Data Sender
        or Data Receiver on a queue or topic: those roles include read on
        that entity (and a topic's subscriptions), not on the namespace.

        Round 1, at once: the namespace itself (200 means namespace access),
        and each exact -EntityName under each kind it could be - queues,
        then topics when -EntityKind is Auto.
        Round 2, with namespace access only: the queue and topic lists, for
        wildcards or when no name is given.
        Round 3: each topic's subscriptions.

        An entity that can't be read is kept with why: NoRole (403 - no
        Service Bus role on it), NotFound (404 under every kind tried - the
        name or kind is wrong) or Failed (anything else).

        Returns @{ Access ('Namespace' or 'Entity'); Namespace (the
        namespace's body, or $null); Entities = @(@{ Name; Kind ('Queue',
        'Topic' or '' when unknown); Outcome; Status; Error; Body;
        Subscriptions (@{ Outcome; Error; Items } for a topic, else $null) });
        Notices }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $NamespaceId,

        [AllowEmptyCollection()]
        [string[]] $EntityName = @(),

        [ValidateSet('Auto', 'Queue', 'Topic')]
        [string] $EntityKind = 'Auto',

        [ValidateRange(1, 32)]
        [int] $ThrottleLimit = 12
    )

    $api = 'api-version=2021-11-01'
    $ns = $NamespaceId.TrimEnd('/')
    $notices = [System.Collections.Generic.List[string]]::new()
    $names = @($EntityName | Where-Object { $_ } | Select-Object -Unique)
    $wild = @($names | Where-Object { [WildcardPattern]::ContainsWildcardCharacters($_) })
    $exact = @($names | Where-Object { -not [WildcardPattern]::ContainsWildcardCharacters($_) })
    $kinds = switch ($EntityKind) { 'Queue' { @('queues') } 'Topic' { @('topics') } default { @('queues', 'topics') } }
    $kindName = @{ queues = 'Queue'; topics = 'Topic' }
    $entityUri = { param([string] $Kind, [string] $Name) "$ns/$Kind/$([System.Uri]::EscapeDataString($Name))?$api" }
    $failure = { param($Answer) if ($Answer -is [System.Collections.IDictionary] -and $Answer['Error']) { [string]$Answer['Error'] } else { "HTTP $($Answer['Status'])" } }

    # --- Round 1: the namespace, and each exact name under each kind it could be.
    $uris = [System.Collections.Generic.List[string]]::new()
    $uris.Add("${ns}?$api")
    foreach ($n in $exact) { foreach ($k in $kinds) { $uris.Add((& $entityUri $k $n)) } }
    $first = Invoke-AACArmParallel -Uri $uris.ToArray() -ThrottleLimit $ThrottleLimit
    $nsAnswer = $first["${ns}?$api"]
    $nsStatus = [int]$nsAnswer['Status']
    if ($nsStatus -eq 404) {
        throw "Azure Admin Console can't find the Service Bus namespace $ns. Check the resource ID (subscription, resource group and name)."
    }
    if ($nsStatus -ne 200 -and $nsStatus -ne 403) {
        throw "Azure Admin Console couldn't read the Service Bus namespace ${ns}: $(& $failure $nsAnswer). Try again, or check the network can reach Azure Resource Manager."
    }
    $access = if ($nsStatus -eq 200) { 'Namespace' } else { 'Entity' }

    $entities = [System.Collections.Generic.List[hashtable]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($n in $exact) {
        $answers = @(foreach ($k in $kinds) { @{ Kind = $k; Answer = $first[(& $entityUri $k $n)] } })
        $hit = $answers | Where-Object { [int]$_.Answer['Status'] -eq 200 } | Select-Object -First 1
        if ($hit) {
            $body = $hit.Answer['Body']
            $name = if ($body -is [System.Collections.IDictionary] -and $body['name']) { [string]$body['name'] } else { $n }
            $entities.Add(@{ Name = $name; Kind = $kindName[$hit.Kind]; Outcome = 'Read'; Status = 200; Error = ''; Body = $body; Subscriptions = $null })
            $null = $seen.Add("$($hit.Kind)|$name")
            continue
        }
        $statuses = @($answers | ForEach-Object { [int]$_.Answer['Status'] })
        # A 403 under any kind wins: with only an entity role, Azure says Forbidden even for a kind the name isn't.
        $outcome = if ($statuses -contains 403) { 'NoRole' } elseif (-not @($statuses | Where-Object { $_ -ne 404 }).Count) { 'NotFound' } else { 'Failed' }
        $known = if ($kinds.Count -eq 1) { $kindName[$kinds[0]] } else { '' }
        $message = switch ($outcome) {
            'NoRole' { 'No Service Bus role on this entity (403 Forbidden).' }
            'NotFound' { "No $((@($kinds | ForEach-Object { $kindName[$_].ToLowerInvariant() })) -join ' or ') by this name (404)." }
            default { & $failure (@($answers | Where-Object { [int]$_.Answer['Status'] -notin 403, 404 })[0].Answer) }
        }
        $entities.Add(@{ Name = $n; Kind = $known; Outcome = $outcome; Status = @($statuses | Sort-Object -Descending)[0]; Error = $message; Body = $null; Subscriptions = $null })
    }

    # --- Round 2: the lists - for wildcards or no name, and only with the namespace.
    if (-not $names.Count -or $wild.Count) {
        if ($access -eq 'Namespace') {
            $listUris = @($kinds | ForEach-Object { "$ns/${_}?$api" })
            $lists = Invoke-AACArmParallel -Uri $listUris -ThrottleLimit $ThrottleLimit
            foreach ($k in $kinds) {
                $answer = $lists["$ns/${k}?$api"]
                if ([int]$answer['Status'] -ne 200) { $notices.Add("The $k of the namespace couldn't be listed: $(& $failure $answer)"); continue }
                foreach ($item in @($answer['Items'] | Where-Object { $_ -is [System.Collections.IDictionary] })) {
                    $name = [string]$item['name']
                    if ($wild.Count -and -not @($wild | Where-Object { $name -like $_ }).Count -and $names.Count) { continue }
                    if (-not $seen.Add("$k|$name")) { continue }
                    $entities.Add(@{ Name = $name; Kind = $kindName[$k]; Outcome = 'Read'; Status = 200; Error = ''; Body = $item; Subscriptions = $null })
                }
            }
            foreach ($w in $wild) {
                if (-not @($entities | Where-Object { $_.Outcome -eq 'Read' -and $_.Name -like $w }).Count) { $notices.Add("No queue or topic matches '$w'.") }
            }
        }
        elseif (-not $names.Count) {
            throw "Azure Admin Console can't list the queues and topics of ${ns}: your account has a role on some of its entities, not on the namespace. Give the queue or topic names with -EntityName."
        }
        else {
            foreach ($w in $wild) { $notices.Add("'$w' was skipped: wildcards need read access on the namespace (Reader or Azure Service Bus Data Owner there). Give the exact queue or topic name.") }
        }
    }

    # --- Round 3: each topic's subscriptions.
    $topics = @($entities | Where-Object { $_.Outcome -eq 'Read' -and $_.Kind -eq 'Topic' })
    if ($topics.Count) {
        $subUri = { param([string] $Name) "$ns/topics/$([System.Uri]::EscapeDataString($Name))/subscriptions?$api" }
        $subs = Invoke-AACArmParallel -Uri @($topics | ForEach-Object { & $subUri $_.Name }) -ThrottleLimit $ThrottleLimit
        foreach ($t in $topics) {
            $answer = $subs[(& $subUri $t.Name)]
            $status = [int]$answer['Status']
            $t.Subscriptions = if ($status -eq 200) { @{ Outcome = 'Read'; Error = ''; Items = @($answer['Items'] | Where-Object { $_ -is [System.Collections.IDictionary] }) } }
            elseif ($status -eq 403) { @{ Outcome = 'NoRole'; Error = 'No role on the subscriptions (403 Forbidden).'; Items = @() } }
            else { @{ Outcome = 'Failed'; Error = (& $failure $answer); Items = @() } }
        }
    }

    @{ Access = $access; Namespace = $(if ($access -eq 'Namespace') { $nsAnswer['Body'] } else { $null }); Entities = $entities.ToArray(); Notices = $notices.ToArray() }
}
