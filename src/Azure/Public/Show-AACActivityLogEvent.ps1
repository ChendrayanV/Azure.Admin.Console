function Show-AACActivityLogEvent {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Shows Activity Log events the way an admin reads them - when, what,
        the result and why it failed, who (decoded from the token), where -
        from the JSON the portal shows, a correlation ID, a Log Analytics
        workspace or the pipeline; as a console view, CSV, HTML and PDF.
    .DESCRIPTION
        Read-only. An Activity Log event holds about sixty values, six levels
        deep; the useful ones are hard to read as stored. Each event becomes
        one flat row (AAC.ActivityLogEvent, ConvertTo-AACActivityLogEvent):

          When    time, phase (begin or end request), ingestion delay
          What    operation, the authorised action and scope, category,
                  channel, level
          Result  status, HTTP status and sub-status, and for a failure the
                  innermost error code, message and target from the
                  statusMessage (JSON inside a string), what kind of failure
                  it is and what to do - as Get-AACResourceError reads it
          Who     user, guest, service principal, managed identity or Azure;
                  app and object ID; how it signed in (public client, client
                  secret, certificate or federated credential, or a user's
                  authentication methods); home or external tenant;
                  directory roles; when the token was issued and expires;
                  caller IP. -ResolveIdentity names the service principal
                  and the roles from Microsoft Graph
          Where   subscription, resource group, type, name, location, tags,
                  a portal link
          Trace   correlation, operation and event IDs, tenant, hierarchy

        The token's opaque values (aio, rh, uti, xms_*) are left out:
        -IncludeClaims adds every claim (Claim:<name> columns, and a Claims
        view).

        Where the events come from:
          -Path            a JSON file: one event as the portal's JSON tab
                           shows it, an array of them, or a REST response
                           ({ value: [...] })
          -CorrelationId   every event of the operation, from the Activity
                           Log (90 days; -SubscriptionId, else every
                           subscription you can see) or, with -WorkspaceId,
                           the Log Analytics workspace it is sent to (as far
                           back as -Days and its retention)
          the pipeline     event objects or JSON text (ConvertFrom-Json,
                           Get-Content -Raw), or rows with a CorrelationId -
                           Invoke-AACActivityLogAssessment -View Activity and
                           Get-AACResourceError rows, for instance
        Signed in, the events are enriched with subscription names and the
        resource's location and tags; a file needs no sign-in.
    .PARAMETER Path
        JSON files of Activity Log events.
    .PARAMETER InputObject
        Event objects, JSON text, or rows with a CorrelationId (and
        SubscriptionId or ResourceId), from the pipeline.
    .PARAMETER CorrelationId
        Show every event of these operations.
    .PARAMETER SubscriptionId
        Where to look for -CorrelationId (every subscription you can see by
        default).
    .PARAMETER WorkspaceId
        Read -CorrelationId's events from this Log Analytics workspace
        (its workspace ID) instead of the Activity Log.
    .PARAMETER Days
        How far back to look for -CorrelationId (90 by default; the Activity
        Log keeps 90, a workspace its retention).
    .PARAMETER Status
        Only events with these statuses (Failed, Succeeded, Started...).
    .PARAMETER ResolveIdentity
        Name service principals and directory roles from Microsoft Graph.
    .PARAMETER IncludeClaims
        Add every token claim, the opaque ones too.
    .PARAMETER View
        Event, Detail, Error, Caller or Claim: what is returned and written to
        -CsvPath.
    .PARAMETER CsvPath
        Write the -View rows to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report.
    .PARAMETER PdfPath
        Write a PDF report - a card per event, for an incident or change.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the rows.
    .PARAMETER NoDisplay
        Return the rows without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Show-AACActivityLogEvent -Path .\event.json
        An event copied from the portal's JSON tab, readable: who, what, the error and what to do.
    .EXAMPLE
        Connect-AAC
        Show-AACActivityLogEvent -CorrelationId $correlationId -SubscriptionId $sub -PdfPath .\incident.pdf
        Every event of one operation, as a PDF to attach to the incident.
    .EXAMPLE
        Invoke-AACActivityLogAssessment -SubscriptionId $sub -View Activity -NoDisplay | Where-Object Status -EQ 'Failed' | Show-AACActivityLogEvent -HtmlPath .\failures.html
        The full events behind the failed operations an assessment found.
    .EXAMPLE
        Show-AACActivityLogEvent -CorrelationId $correlationId -WorkspaceId $workspaceId -Days 365 -ResolveIdentity -IncludeClaims -CsvPath .\event.csv
        From the workspace the Activity Log is sent to, with names from Microsoft Graph and every claim.
    .OUTPUTS
        AAC.ActivityLogEvent, AAC.ActivityLogEventDetail, AAC.ActivityLogEventError, AAC.ActivityLogEventCaller or AAC.ActivityLogEventClaim, by -View (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding(DefaultParameterSetName = 'Query')]
    [OutputType('AAC.ActivityLogEvent', 'AAC.ActivityLogEventDetail', 'AAC.ActivityLogEventError', 'AAC.ActivityLogEventCaller', 'AAC.ActivityLogEventClaim')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [ValidateNotNullOrEmpty()]
        [string[]] $Path,

        [Parameter(ParameterSetName = 'Query', ValueFromPipeline)]
        [object[]] $InputObject,

        [Parameter(ParameterSetName = 'Query')]
        [ValidatePattern('^[0-9a-fA-F-]{36}$')]
        [string[]] $CorrelationId,

        [ValidatePattern('^[0-9a-fA-F-]{36}$')]
        [string[]] $SubscriptionId,

        [ValidatePattern('^[0-9a-fA-F-]{36}$')]
        [string] $WorkspaceId,

        [ValidateRange(1, 3650)]
        [int] $Days = 90,

        [ValidateNotNullOrEmpty()]
        [string[]] $Status,

        [switch] $ResolveIdentity,

        [switch] $IncludeClaims,

        [ValidateSet('Event', 'Detail', 'Error', 'Caller', 'Claim')]
        [string] $View = 'Event',

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Activity Log events',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    begin {
        $raw = [System.Collections.Generic.List[object]]::new()
        $lookups = [ordered]@{}
        # An event's keys, raw or from a workspace; anything else is a row to look up by correlation ID.
        $isEvent = { param([System.Collections.IDictionary] $Item) $Item.Contains('eventTimestamp') -or $Item.Contains('operationName') -or $Item.Contains('TimeGenerated') -or $Item.Contains('OperationNameValue') }
        $addEvents = {
            param($Parsed, [string] $From)
            $items = if ($Parsed -is [System.Collections.IDictionary] -and $Parsed['value'] -is [System.Collections.IList]) { @($Parsed['value']) } elseif ($Parsed -is [System.Collections.IList]) { @($Parsed) } else { @($Parsed) }
            foreach ($item in $items) {
                if ($item -is [System.Collections.IDictionary] -and (& $isEvent $item)) { $raw.Add(@{ Event = $item; Source = $From }) }
            }
        }
        $addLookup = {
            param([string] $Correlation, [string] $Subscription)
            if (-not $Correlation) { return }
            $key = $Correlation.ToLowerInvariant()
            if (-not $lookups.Contains($key)) { $lookups[$key] = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase) }
            if ($Subscription) { $null = $lookups[$key].Add($Subscription) }
        }
    }

    process {
        foreach ($item in @($InputObject | Where-Object { $null -ne $_ })) {
            if ($item -is [string]) {
                if ($item -match '^[0-9a-fA-F-]{36}$') { & $addLookup $item ''; continue }
                try { & $addEvents (ConvertFrom-Json -InputObject $item -AsHashtable -Depth 64 -ErrorAction Stop) 'Pipeline' } catch { Write-Warning "Azure Admin Console skipped text that isn't an Activity Log event in JSON: $($_.Exception.Message)" }
                continue
            }
            $map = if ($item -is [System.Collections.IDictionary]) { $item } else { ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $item -Depth 64 -Compress) -AsHashtable -Depth 64 }
            if ($map -isnot [System.Collections.IDictionary]) { continue }
            if ((& $isEvent $map) -or $map['value'] -is [System.Collections.IList]) { & $addEvents $map 'Pipeline'; continue }
            $correlation = [string]$(if ($map['CorrelationId']) { $map['CorrelationId'] } else { $map['LastCorrelationId'] })
            $subscription = [string]$map['SubscriptionId']
            if (-not $subscription -and [string]$map['ResourceId'] -match '^/subscriptions/([^/]+)') { $subscription = $Matches[1] }
            if ($correlation) { & $addLookup $correlation $subscription }
            else { Write-Warning 'Azure Admin Console skipped a pipeline object that is neither an Activity Log event nor a row with a CorrelationId.' }
        }
    }

    end {
        trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

        $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
        $interactive = -not $NoDisplay -and -not $pipedOnward
        $resolve = { param([string] $Target) if ($Target) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Target) } }
        foreach ($file in @($Path | Where-Object { $_ })) {
            $full = & $resolve $file
            if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Azure Admin Console can't find '$file'. Give the path of a JSON file of Activity Log events (the portal's JSON tab, saved)." }
            try { $parsed = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $full -Raw) -AsHashtable -Depth 64 -ErrorAction Stop }
            catch { throw "Azure Admin Console can't read '$file' as JSON: $($_.Exception.Message) Save the event from the portal's JSON tab as it is shown." }
            $before = $raw.Count
            & $addEvents $parsed (Split-Path -Path $full -Leaf)
            if ($raw.Count -eq $before) { Write-Warning "Azure Admin Console found no Activity Log event in '$file'." }
        }
        foreach ($c in @($CorrelationId | Where-Object { $_ })) { & $addLookup $c '' }
        if (-not $raw.Count -and -not $lookups.Count) { throw 'Azure Admin Console has no event to show. Give -Path (a JSON file), -CorrelationId, or pipe events or rows with a CorrelationId.' }

        # Signed in, the events are fetched and enriched; a file needs no sign-in.
        $signedIn = $true
        try { $null = Get-AACAccessToken } catch { if ($lookups.Count) { throw }; $signedIn = $false }
        $request = @{
            Raw = $raw; Lookups = $lookups; SubscriptionId = @($SubscriptionId | Where-Object { $_ }); WorkspaceId = $WorkspaceId; Days = $Days; SignedIn = $signedIn
            ResolveIdentity = [bool]$ResolveIdentity; IncludeClaims = [bool]$IncludeClaims; Status = @($Status | Where-Object { $_ })
        }
        if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Activity Log events' -Color 'deepskyblue3_1' }
        $state = Invoke-AACProgress -ScriptBlock {
            $notices = [System.Collections.Generic.List[string]]::new()
            $iso = { param([datetime] $When) $When.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture) }
            $names = @{}

            # --- Events by correlation ID ---------------------------------------------------------------------------------
            if ($request.Lookups.Count) {
                $ids = @($request.Lookups.Keys)
                if ($request.WorkspaceId) {
                    Update-AACProgress -Id 'events' -Indeterminate -Description "Reading $($ids.Count) operation(s) from the Log Analytics workspace"
                    $query = "AzureActivity | where TimeGenerated > ago($($request.Days)d) | where CorrelationId in~ ($((@($ids | ForEach-Object { ConvertTo-AACKqlLiteral -Text $_ })) -join ', ')) | order by TimeGenerated asc"
                    foreach ($row in @(Invoke-AACLogQuery -Kind Workspace -Id $request.WorkspaceId -Query $query -Timespan "P$($request.Days)D")) { $request.Raw.Add(@{ Event = $row; Source = 'Log Analytics' }) }
                    Update-AACProgress -Id 'events' -Complete -Description "Read $($request.Raw.Count) event(s) from Log Analytics"
                }
                else {
                    $scope = $null
                    $everywhere = @($request.SubscriptionId)
                    if (-not $everywhere.Count -and @($request.Lookups.Values | Where-Object { -not $_.Count }).Count) {
                        $scope = Resolve-AACScope
                        $everywhere = @($scope.Ids)
                        $names = $scope.Names
                    }
                    $reach = [Math]::Min($request.Days, 89.9)
                    if ($request.Days -gt 90) { $notices.Add('The Activity Log keeps 90 days: older events need -WorkspaceId (the workspace it is sent to).') }
                    $from = [datetime]::UtcNow.AddDays(-$reach)
                    $uris = [ordered]@{}
                    foreach ($id in $ids) {
                        $subs = if ($request.Lookups[$id].Count) { @($request.Lookups[$id]) } else { $everywhere }
                        foreach ($s in $subs) {
                            $filter = "eventTimestamp ge '$(& $iso $from)' and eventTimestamp le '$(& $iso ([datetime]::UtcNow))' and correlationId eq '$id'"
                            $uris["/subscriptions/$s/providers/Microsoft.Insights/eventtypes/management/values?api-version=2015-04-01&`$filter=$([System.Uri]::EscapeDataString($filter))"] = $id
                        }
                    }
                    Update-AACProgress -Id 'events' -Total ([Math]::Max(1, $uris.Count)) -Description "Reading $($ids.Count) operation(s) from the Activity Log ($($uris.Count) request(s))"
                    $answers = Invoke-AACArmParallel -Uri @($uris.Keys) -OnProgress { param($EventDone, $EventTotal) Update-AACProgress -Id 'events' -Increment 1 }
                    $found = @{}
                    foreach ($uri in $uris.Keys) {
                        $answer = $answers[$uri]
                        if (-not $answer -or $answer.Error) { $notices.Add("A subscription couldn't be searched: $(if ($answer) { $answer.Error } else { 'no answer' })"); continue }
                        foreach ($item in @($answer.Items | Where-Object { $_ -is [System.Collections.IDictionary] })) { $request.Raw.Add(@{ Event = $item; Source = 'Activity Log' }); $found[$uris[$uri]] = $true }
                    }
                    $missing = @($ids | Where-Object { -not $found.Contains($_) })
                    if ($missing.Count) { $notices.Add("No event found for $($missing.Count) correlation ID(s) in the last $([Math]::Floor($reach)) day(s): $(@($missing | Select-Object -First 3) -join ', ')$(if ($missing.Count -gt 3) { ', ...' }).") }
                    Update-AACProgress -Id 'events' -Complete -Description "Read $($request.Raw.Count) event(s) from the Activity Log"
                }
            }

            # --- Names, locations, tags ---------------------------------------------------------------------------------
            $get = ${function:Get-AACMember}
            $resources = @{}
            $directory = @{}
            $roles = @{}
            if ($request.SignedIn -and $request.Raw.Count) {
                Update-AACProgress -Id 'enrich' -Indeterminate -Description 'Adding subscription names, locations and tags'
                if (-not $names.Count) { try { $names = (Resolve-AACScope).Names } catch { $notices.Add("Subscription names couldn't be read: $($_.Exception.Message)") } }
                $ids = @($request.Raw | ForEach-Object { $r = $_.Event; [string]$(if ($r['resourceId']) { $r['resourceId'] } elseif ($r['_ResourceId']) { $r['_ResourceId'] } else { $r['ResourceId'] }) } | Where-Object { $_ -match '/providers/' } | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object -Unique)
                if ($ids.Count) {
                    $queries = [ordered]@{}
                    for ($i = 0; $i -lt $ids.Count; $i += 200) { $queries["resources-$i"] = @{ Tenant = $true; Query = "resources | where tolower(id) in ($((@($ids[$i..([Math]::Min($i + 199, $ids.Count - 1))] | ForEach-Object { ConvertTo-AACKqlLiteral -Text $_ })) -join ', ')) | project id = tolower(id), location, tags" } }
                    $read = Invoke-AACGraphBatch -Query $queries -AllowFailure @($queries.Keys)
                    foreach ($rows in $read.Rows.Values) { foreach ($row in @($rows)) { if ($row -is [System.Collections.IDictionary]) { $resources[[string]$row['id']] = @{ Location = [string]$row['location']; Tags = $(if ($row['tags'] -is [System.Collections.IDictionary]) { $row['tags'] } else { @{} }) } } } }
                }
                if ($request.ResolveIdentity) {
                    $objectIds = @($request.Raw | ForEach-Object {
                            $r = $_.Event
                            $claims = if ($r['claims'] -is [System.Collections.IDictionary]) { $r['claims'] } elseif ($r['Claims_d'] -is [System.Collections.IDictionary]) { $r['Claims_d'] } else { @{} }
                            [string](& $get $claims 'http://schemas.microsoft.com/identity/claims/objectidentifier')
                            $caller = [string]$(if ($r['caller']) { $r['caller'] } else { $r['Caller'] })
                            if ($caller -match '^[0-9a-fA-F-]{36}$') { $caller }
                        } | Where-Object { $_ -match '^[0-9a-fA-F-]{36}$' } | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object -Unique)
                    if ($objectIds.Count) {
                        $found = Get-AACDirectoryObject -Id $objectIds
                        foreach ($k in @($found.Objects.Keys)) { if ($found.Objects[$k]['displayName']) { $directory[$k] = [string]$found.Objects[$k]['displayName'] } }
                        if ($found.Error) { $notices.Add("Names couldn't all be read from Microsoft Graph: $($found.Error)") }
                    }
                    try {
                        $graph = 'https://graph.microsoft.com/v1.0/directoryRoleTemplates?$select=id,displayName'
                        $answer = (Invoke-AACArmParallel -Uri @($graph) -Authorization "Bearer $(Get-AACAccessToken -Resource 'https://graph.microsoft.com')")[$graph]
                        foreach ($t in @($answer.Items | Where-Object { $_ -is [System.Collections.IDictionary] })) { $roles[([string]$t['id']).ToLowerInvariant()] = [string]$t['displayName'] }
                    }
                    catch { $notices.Add("Directory role names couldn't be read from Microsoft Graph: $($_.Exception.Message)") }
                }
                Update-AACProgress -Id 'enrich' -Complete -Description "Added names, locations and tags for $($resources.Count) resource(s)"
            }

            Update-AACProgress -Id 'flatten' -Indeterminate -Description "Reading $($request.Raw.Count) event(s)"
            $events = @(foreach ($g in @($request.Raw | Group-Object -Property { $_.Source })) {
                    ConvertTo-AACActivityLogEvent -Entry @($g.Group | ForEach-Object { $_.Event }) -SubscriptionName $names -Resource $resources -DirectoryName $directory -RoleName $roles -IncludeClaims:$request.IncludeClaims -Source $g.Name
                })
            if ($request.Status.Count) { $events = @($events | Where-Object { $_.Status -in $request.Status }) }
            $events = @($events | Sort-Object -Property Time)
            Update-AACProgress -Id 'flatten' -Complete -Description ('{0:N0} event(s): {1:N0} failed' -f $events.Count, @($events | Where-Object Status -EQ 'Failed').Count)
            @{ Events = $events; Notices = $notices.ToArray() }
        }

        # --- The views ---------------------------------------------------------------------------------------------
        $events = @($state.Events)
        $failed = @($events | Where-Object Status -EQ 'Failed')
        $label = { param($E, [int] $N) "#$N $(if ($E.Time) { $E.Time.ToString('yyyy-MM-dd HH:mm:ss') }) $($E.Operation) ($($E.Status))" }
        $sections = [ordered]@{
            When   = [ordered]@{ Time = 'Time'; Phase = 'Phase'; 'Ingestion delay' = 'IngestionDelay' }
            What   = [ordered]@{ Operation = 'Operation'; Action = 'Action'; Category = 'Category'; Channel = 'Channel'; Level = 'Level' }
            Result = [ordered]@{ Status = 'Status'; 'HTTP status' = 'HttpStatus'; 'Sub-status' = 'SubStatus'; 'Error code' = 'ErrorCode'; Message = 'ErrorMessage'; Target = 'ErrorTarget'; Kind = 'ErrorCategory'; 'What to do' = 'Fix'; Docs = 'Link' }
            Who    = [ordered]@{ Kind = 'CallerKind'; Caller = 'Caller'; Name = 'CallerName'; 'App ID' = 'AppId'; 'Object ID' = 'ObjectId'; 'Signed in with' = 'AuthMethod'; Tenant = 'Tenant'; 'Directory roles' = 'DirectoryRoles'; 'Token issued' = 'TokenIssued'; 'Token expires' = 'TokenExpires'; 'Caller IP' = 'CallerIp' }
            Where  = [ordered]@{ Subscription = 'Subscription'; 'Resource group' = 'ResourceGroup'; 'Resource type' = 'ResourceType'; Resource = 'Resource'; Location = 'Location'; Tags = 'Tags'; Scope = 'Scope'; Portal = 'PortalLink' }
            Trace  = [ordered]@{ 'Correlation ID' = 'CorrelationId'; 'Operation ID' = 'OperationId'; 'Event data ID' = 'EventDataId'; 'Tenant ID' = 'TenantId'; Hierarchy = 'Hierarchy'; Source = 'Source' }
        }
        $details = [System.Collections.Generic.List[object]]::new()
        $claimRows = [System.Collections.Generic.List[object]]::new()
        for ($n = 0; $n -lt $events.Count; $n++) {
            $e = $events[$n]
            $name = & $label $e ($n + 1)
            foreach ($section in $sections.Keys) {
                foreach ($field in $sections[$section].Keys) {
                    $v = $e.($sections[$section][$field])
                    if ($null -eq $v -or '' -eq $v) { continue }
                    if ($v -is [datetime]) { $v = $v.ToString('yyyy-MM-dd HH:mm:ss') + ' UTC' }
                    $details.Add([pscustomobject]@{ PSTypeName = 'AAC.ActivityLogEventDetail'; Event = $name; Section = $section; Field = $field; Value = [string]$v })
                }
            }
            foreach ($p in @($e.PSObject.Properties | Where-Object { $_.Name -like 'Claim:*' })) { $claimRows.Add([pscustomobject]@{ PSTypeName = 'AAC.ActivityLogEventClaim'; Event = $name; Claim = $p.Name.Substring(6); Value = [string]$p.Value }) }
        }
        $errors = @($failed | Group-Object -Property ErrorCode | ForEach-Object {
                $g = @($_.Group | Sort-Object -Property Time -Descending)
                [pscustomobject]@{
                    PSTypeName = 'AAC.ActivityLogEventError'; ErrorCode = $_.Name; Category = $g[0].ErrorCategory; Events = $g.Count
                    Resources = @($g | ForEach-Object ResourceId | Where-Object { $_ } | Sort-Object -Unique).Count; Callers = (@($g | ForEach-Object Caller | Sort-Object -Unique)) -join ', '
                    LastSeen = $g[0].Time; Message = $g[0].ErrorMessage; Fix = $g[0].Fix; Link = $g[0].Link
                }
            } | Sort-Object -Property Events -Descending)
        $callers = @($events | Group-Object -Property Caller | ForEach-Object {
                $g = @($_.Group)
                [pscustomobject]@{
                    PSTypeName = 'AAC.ActivityLogEventCaller'; Caller = $_.Name; CallerKind = $g[0].CallerKind; CallerName = $g[0].CallerName; AuthMethod = $g[0].AuthMethod; Tenant = $g[0].Tenant
                    Events = $g.Count; Failed = @($g | Where-Object Status -EQ 'Failed').Count; LastSeen = ($g | Measure-Object -Property Time -Maximum).Maximum
                }
            } | Sort-Object -Property Events -Descending)
        $statusTones = @{ Succeeded = 'good'; Failed = 'bad'; Started = 'neutral'; Accepted = 'neutral'; Active = 'info'; Resolved = 'good' }
        $kindTones = @{ User = 'info'; 'Guest user' = 'warn'; 'Service principal' = 'violet'; 'Managed identity' = 'good'; 'Azure platform' = 'neutral'; Other = 'neutral' }
        $few = $events.Count -le 3
        $report = @{
            Subtitle    = "Activity Log - $($events.Count) event(s)"
            Facts       = [ordered]@{
                Events = $events.Count; Failed = $failed.Count; From = (@($events | ForEach-Object Source | Sort-Object -Unique) -join ', ')
                Window = $(if ($events.Count) { "$($events[0].Time.ToString('yyyy-MM-dd HH:mm')) to $($events[-1].Time.ToString('yyyy-MM-dd HH:mm')) UTC" } else { '' })
                Generated = "$([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture)) UTC"
            }
            Status      = $(if ($failed.Count) { 'Failed' } else { 'Success' })
            Headline    = $(if (-not $events.Count) { 'No event to show.' } elseif ($failed.Count) { "$($failed.Count) of $($events.Count) event(s) failed$(if ($errors.Count) { ": $((@($errors | Select-Object -First 3 -Property ErrorCode | ForEach-Object ErrorCode)) -join ', ')" })" } else { "$($events.Count) event(s), none failed" })
            OverviewTab = 'Summary'
            Tiles       = @(
                @{ Value = '{0:N0}' -f $events.Count; Label = 'events'; Tone = 'info'; Table = 'events' }
                @{ Value = '{0:N0}' -f $failed.Count; Label = 'failed'; Tone = $(if ($failed.Count) { 'bad' } else { 'good' }); Table = 'events'; Filters = @{ Status = 'Failed' } }
                @{ Value = '{0:N0}' -f $errors.Count; Label = 'error codes'; Tone = $(if ($errors.Count) { 'warn' } else { 'good' }); Table = 'errors' }
                @{ Value = '{0:N0}' -f $callers.Count; Label = 'callers'; Tone = 'violet'; Table = 'callers' }
                @{ Value = '{0:N0}' -f @($events | ForEach-Object ResourceId | Where-Object { $_ } | Sort-Object -Unique).Count; Label = 'resources'; Tone = 'info'; Table = 'events' }
            )
            Notices     = @($state.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
            Charts      = @(
                @{ Title = 'Events by status'; Kind = 'donut'; CenterLabel = 'events'; Items = @($events | Group-Object -Property Status | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Tone = $(if ($statusTones.Contains($_.Name)) { $statusTones[$_.Name] } else { 'neutral' }) } }) }
                @{ Title = 'Failures by error code'; Items = @($errors | Select-Object -First 10 -Property ErrorCode, Events | ForEach-Object { @{ Label = $_.ErrorCode; Value = $_.Events; Filter = $_.ErrorCode } }); Table = 'errors'; Column = 'ErrorCode'; Tone = 'bad'; Console = (-not $few) }
            )
            Tabs        = @(
                @{ Name = 'Events'; Badge = $events.Count; Tone = 'info'; Note = 'Each event in one row, oldest first. Group by correlation ID to follow one operation from start to end.' }
                @{ Name = 'Details'; Badge = $events.Count; Tone = 'neutral'; Note = 'Each event as a card: when, what, the result and why, who, where, and the IDs to trace it.' }
                @{ Name = 'Errors'; Badge = $errors.Count; Tone = $(if ($errors.Count) { 'bad' } else { 'good' }); Note = 'The failures grouped by error code - the innermost code of the event''s status message - with what to do.' }
                @{ Name = 'Callers'; Badge = $callers.Count; Tone = 'violet'; Note = 'Who made the calls, how they signed in, and from which tenant.' }
                $(if ($claimRows.Count) { @{ Name = 'Claims'; Badge = $claimRows.Count; Tone = 'neutral'; Note = 'Every claim of each event''s token (-IncludeClaims), opaque values included.' } })
            )
            Tables      = @(
                @{ Id = 'events'; Title = 'Events'; Section = 'Events'; Rows = $events; Noun = 'events'; GroupBy = @('CorrelationId', 'Status', 'ErrorCode'); ConsoleLimit = 25; NoConsole = $few
                    Columns = @(
                        @{ Key = 'Time'; Label = 'Time'; Type = 'datetime'; Console = $true; Pdf = $true }
                        @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = $statusTones; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Operation'; Label = 'Operation'; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Phase'; Label = 'Phase'; Facet = $true }
                        @{ Key = 'ErrorCode'; Label = 'Error'; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'HttpStatus'; Label = 'HTTP'; Facet = $true }
                        @{ Key = 'CallerKind'; Label = 'Caller kind'; Type = 'badge'; Tones = $kindTones; Facet = $true }
                        @{ Key = 'Caller'; Label = 'Caller'; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'AuthMethod'; Label = 'Signed in with'; Facet = $true }
                        @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                        @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                        @{ Key = 'ResourceType'; Label = 'Resource type'; Facet = $true }
                        @{ Key = 'Resource'; Label = 'Resource'; Console = $true; Pdf = $true }
                        @{ Key = 'ErrorMessage'; Label = 'Message'; Type = 'wide' }
                        @{ Key = 'Fix'; Label = 'What to do'; Type = 'wide' }
                        @{ Key = 'CallerIp'; Label = 'Caller IP' }
                        @{ Key = 'Level'; Label = 'Level'; Facet = $true }
                        @{ Key = 'CorrelationId'; Label = 'Correlation ID' }
                    ) }
                @{ Id = 'details'; Title = 'Event details'; Section = 'Details'; Rows = $details.ToArray(); Noun = 'fields'; GroupBy = @('Event', 'Section'); ConsoleLimit = 120; NoConsole = (-not $few)
                    Columns = @(
                        @{ Key = 'Event'; Label = 'Event'; Facet = $true; Pdf = $true }
                        @{ Key = 'Section'; Label = 'Section'; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Field'; Label = 'Field'; Console = $true; Pdf = $true }
                        @{ Key = 'Value'; Label = 'Value'; Type = 'wide'; Console = $true; Pdf = $true }
                    ) }
                @{ Id = 'errors'; Title = 'Errors'; Section = 'Errors'; Rows = $errors; Noun = 'error codes'; GroupBy = @('Category'); ConsoleLimit = 10; NoConsole = (-not $errors.Count -or $few); Empty = 'Nothing failed.'; EmptyStatus = 'Success'
                    Columns = @(
                        @{ Key = 'ErrorCode'; Label = 'Error code'; Console = $true; Pdf = $true }
                        @{ Key = 'Category'; Label = 'Kind'; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Events'; Label = 'Events'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Resources'; Label = 'Resources'; Type = 'number' }
                        @{ Key = 'Callers'; Label = 'Callers'; Type = 'wide' }
                        @{ Key = 'LastSeen'; Label = 'Last seen'; Type = 'datetime' }
                        @{ Key = 'Message'; Label = 'Message'; Type = 'wide'; Console = $true; Pdf = $true }
                        @{ Key = 'Fix'; Label = 'What to do'; Type = 'wide'; Pdf = $true }
                        @{ Key = 'Link'; Label = 'Docs' }
                    ) }
                @{ Id = 'callers'; Title = 'Callers'; Section = 'Callers'; Rows = $callers; Noun = 'callers'; GroupBy = @('CallerKind'); NoConsole = $true
                    Columns = @(
                        @{ Key = 'Caller'; Label = 'Caller'; Pdf = $true }
                        @{ Key = 'CallerKind'; Label = 'Kind'; Type = 'badge'; Tones = $kindTones; Facet = $true; Pdf = $true }
                        @{ Key = 'CallerName'; Label = 'Name'; Pdf = $true }
                        @{ Key = 'AuthMethod'; Label = 'Signed in with'; Facet = $true; Pdf = $true }
                        @{ Key = 'Tenant'; Label = 'Tenant'; Facet = $true }
                        @{ Key = 'Events'; Label = 'Events'; Type = 'number'; Sum = $true; Pdf = $true }
                        @{ Key = 'Failed'; Label = 'Failed'; Type = 'number'; Sum = $true; Pdf = $true }
                        @{ Key = 'LastSeen'; Label = 'Last seen'; Type = 'datetime' }
                    ) }
                @{ Id = 'claims'; Title = 'Token claims'; Section = 'Claims'; Rows = $claimRows.ToArray(); Noun = 'claims'; GroupBy = @('Event'); NoConsole = $true
                    Columns = @(
                        @{ Key = 'Event'; Label = 'Event'; Facet = $true }
                        @{ Key = 'Claim'; Label = 'Claim'; Facet = $true }
                        @{ Key = 'Value'; Label = 'Value'; Type = 'wide' }
                    ) }
            )
            Hint        = '-CorrelationId shows every event of an operation; -ResolveIdentity names the caller and its roles; -IncludeClaims adds every token claim; -Status Failed keeps the failures; -View Detail, Error, Caller or Claim returns those rows; -HtmlPath, -PdfPath or -CsvPath for a report.'
        }
        $rows = @(switch ($View) { 'Detail' { $details.ToArray() } 'Error' { $errors } 'Caller' { $callers } 'Claim' { $claimRows.ToArray() } default { $events } })
        Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $rows -Noun $View.ToLowerInvariant() -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
            -ShowView:$interactive -NoPaging:$NoPaging -Object $rows -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
    }
}
