function ConvertTo-AACActivityLogEvent {
    <#
    .SYNOPSIS
        Flattens Activity Log events - as the portal's JSON tab, the REST API
        or a Log Analytics workspace (AzureActivity) gives them - into one
        readable row each: when, what, the result and why it failed, who
        (decoded from the token), where, and the IDs to trace it. For
        Show-AACActivityLogEvent.
    .DESCRIPTION
        -Entry are hashtables (ConvertFrom-Json -AsHashtable): raw events
        (eventTimestamp, operationName, claims, properties...) or AzureActivity
        rows (TimeGenerated, OperationNameValue, Claims_d, Properties_d...) -
        each is recognised by its keys.

        Decoded on the way:
          the error      properties.statusMessage (JSON inside a string) ->
                         its innermost code, message and target, the kind of
                         failure and what to do (Read-AACActivityLogError);
                         HttpStatus from the sub-status or status code
          the caller     kind (Get-AACActivityLogCaller), app and object ID,
                         how it signed in (appidacr: public client, client
                         secret, certificate or federated credential; a
                         user's authentication methods), home or external
                         tenant (the token's issuer against the event's
                         tenant), directory roles (wids, named from -RoleName
                         and the common built-in roles), when the token was
                         issued and expires (iat, exp)
          the resource   subscription (named from -SubscriptionName), resource
                         group, type and name from resourceId; location and
                         tags from -Resource; a portal link
        The token's opaque values (aio, rh, uti, xms_*) are left out;
        -IncludeClaims adds every claim as a Claim:<name> column.
        -DirectoryName maps an object or app ID (lower case) to a name.

        Returns AAC.ActivityLogEvent rows, oldest first.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowEmptyCollection()]
        [object[]] $Entry = @(),

        [System.Collections.IDictionary] $SubscriptionName = @{},

        [System.Collections.IDictionary] $Resource = @{},

        [System.Collections.IDictionary] $DirectoryName = @{},

        [System.Collections.IDictionary] $RoleName = @{},

        [switch] $IncludeClaims,

        [string] $Source = 'Activity Log'
    )

    $get = ${function:Get-AACMember}
    $text = { param($Object, [string] $Path) $v = & $get $Object $Path; if ($null -eq $v) { '' } else { [string]$v } }
    # A field that may be an object, a JSON string or a { value, localizedValue } pair.
    $map = { param($Value) if ($Value -is [System.Collections.IDictionary]) { $Value } elseif ($Value -is [string] -and $Value.TrimStart().StartsWith('{')) { try { ConvertFrom-Json -InputObject $Value -AsHashtable -Depth 32 -ErrorAction Stop } catch { @{} } } else { @{} } }
    $pair = { param($Value, [switch] $Localized) if ($Value -is [System.Collections.IDictionary]) { $v = & $text $Value $(if ($Localized) { 'localizedValue' } else { 'value' }); if ($v) { $v } else { & $text $Value 'value' } } elseif ($null -eq $Value) { '' } else { [string]$Value } }
    $time = {
        param($Value)
        if ($Value -is [datetime]) { return $Value.ToUniversalTime() }
        $d = [datetime]::MinValue
        if ($Value -and [datetime]::TryParse([string]$Value, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]'AdjustToUniversal, AssumeUniversal', [ref]$d)) { $d } else { $null }
    }
    $epoch = { param($Value) $n = [long]0; if ($Value -and [long]::TryParse([string]$Value, [ref]$n)) { [DateTimeOffset]::FromUnixTimeSeconds($n).UtcDateTime } else { $null } }
    $httpCodes = @{ OK = 200; Created = 201; Accepted = 202; NoContent = 204; BadRequest = 400; Unauthorized = 401; Forbidden = 403; NotFound = 404; MethodNotAllowed = 405; Conflict = 409; PreconditionFailed = 412; TooManyRequests = 429; InternalServerError = 500; BadGateway = 502; ServiceUnavailable = 503; GatewayTimeout = 504 }
    $builtInRoles = @{
        '62e90394-69f5-4237-9190-012177145e10' = 'Global Administrator'; 'f2ef992c-3afb-46b9-b7cf-a126ee74c451' = 'Global Reader'; '88d8e3e3-8f55-4a1e-953a-9b9898b8876b' = 'Directory Readers'
        'fe930be7-5e62-47db-91af-98c3a49a38b1' = 'User Administrator'; 'e8611ab8-c189-46e8-94e1-60213ab1f814' = 'Privileged Role Administrator'; '194ae4cb-b126-40b2-bd5b-6091b380977d' = 'Security Administrator'
        '5d6b6bb7-de71-4623-b4af-96380a352509' = 'Security Reader'; '9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3' = 'Application Administrator'; '158c047a-c907-4556-b7ef-446551a6b5f7' = 'Cloud Application Administrator'
        'b79fbf4d-3ef9-4689-8143-76b194e85509' = 'User (default member)'
    }
    $claimUri = @{
        Upn      = 'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn'
        ObjectId = 'http://schemas.microsoft.com/identity/claims/objectidentifier'
        Tenant   = 'http://schemas.microsoft.com/identity/claims/tenantid'
        Methods  = 'http://schemas.microsoft.com/claims/authnmethodsreferences'
    }

    $rows = foreach ($e in @($Entry)) {
        if ($e -isnot [System.Collections.IDictionary]) { continue }
        $workspace = $e.Contains('TimeGenerated') -or $e.Contains('OperationNameValue')
        if ($workspace) {
            $f = @{
                Time = & $time $e['TimeGenerated']; Operation = & $text $e 'OperationNameValue'; Label = & $text $e 'OperationName'; Status = & $text $e 'ActivityStatusValue'
                SubStatus = & $text $e 'ActivitySubstatusValue'; SubStatusText = & $text $e 'ActivitySubstatusValue'; Level = & $text $e 'Level'; Category = & $text $e 'CategoryValue'; Channel = ''; Phase = ''
                Caller = & $text $e 'Caller'; CallerIp = & $text $e 'CallerIpAddress'
                Claims = $(if ($e['Claims_d'] -is [System.Collections.IDictionary]) { $e['Claims_d'] } else { & $map $e['Claims'] })
                Authorization = $(if ($e['Authorization_d'] -is [System.Collections.IDictionary]) { $e['Authorization_d'] } else { & $map $e['Authorization'] })
                Properties = $(if ($e['Properties_d'] -is [System.Collections.IDictionary]) { $e['Properties_d'] } else { & $map $e['Properties'] })
                ResourceId = $(if ($e['_ResourceId']) { [string]$e['_ResourceId'] } else { & $text $e 'ResourceId' }); ResourceType = ''
                SubscriptionId = & $text $e 'SubscriptionId'; TenantId = & $text $e 'TenantId'; CorrelationId = & $text $e 'CorrelationId'; OperationId = & $text $e 'OperationId'
                EventDataId = & $text $e 'EventDataId'; Submitted = & $time $e['EventSubmissionTimestamp']; Hierarchy = & $text $e 'Hierarchy'
            }
            if (-not $f.CallerIp) { $f.CallerIp = & $text (& $map $e['HTTPRequest']) 'clientIpAddress' }
            # AzureActivity says Failure, Success, Start; the REST API (and the rest of this) Failed, Succeeded, Started.
            $f.Status = switch ($f.Status) { 'Failure' { 'Failed' } 'Success' { 'Succeeded' } 'Start' { 'Started' } 'Accept' { 'Accepted' } default { $f.Status } }
        }
        else {
            $f = @{
                Time = & $time $e['eventTimestamp']; Operation = & $pair $e['operationName']; Label = & $pair $e['operationName'] -Localized; Status = & $pair $e['status']
                SubStatus = & $pair $e['subStatus']; SubStatusText = & $pair $e['subStatus'] -Localized; Level = & $text $e 'level'; Category = & $pair $e['category']; Channel = & $text $e 'channels'
                Phase = & $pair $e['eventName'] -Localized; Caller = & $text $e 'caller'; CallerIp = & $text $e 'httpRequest.clientIpAddress'
                Claims = & $map $e['claims']; Authorization = & $map $e['authorization']; Properties = & $map $e['properties']
                ResourceId = & $text $e 'resourceId'; ResourceType = & $pair $e['resourceType']
                SubscriptionId = & $text $e 'subscriptionId'; TenantId = & $text $e 'tenantId'; CorrelationId = & $text $e 'correlationId'; OperationId = & $text $e 'operationId'
                EventDataId = & $text $e 'eventDataId'; Submitted = & $time $e['submissionTimestamp']; Hierarchy = ''
            }
            $f.Hierarchy = & $text $f.Properties 'hierarchy'
        }
        if (-not $f.Label) { $f.Label = $f.Operation }

        # --- Who: the token decoded --------------------------------------------------------------------------------------
        $claims = $f.Claims
        # By key, not Get-AACMember's dotted path: claim names are URLs full of dots.
        $claimOf = { param([string] $Name) if ($claims -isnot [System.Collections.IDictionary]) { return }; foreach ($k in $claims.Keys) { if ($k -eq $Name) { return , $claims[$k] } } }
        $claim = { param([string] $Name) $v = & $claimOf $Name; if ($null -eq $v) { '' } else { [string]$v } }
        $upn = & $claim $claimUri.Upn
        if (-not $upn) { $upn = & $claim 'upn' }
        $mirid = & $claim 'xms_mirid'
        $caller = Get-AACActivityLogCaller -Caller $f.Caller -ManagedIdentity $mirid -TokenType (& $claim 'idtyp') -Upn $upn
        $appId = & $claim 'appid'
        if (-not $appId) { $appId = & $claim 'azp' }
        $objectId = & $claim $claimUri.ObjectId
        if (-not $objectId) { $objectId = & $claim 'oid' }
        if (-not $objectId -and $f.Caller -match '^[0-9a-fA-F-]{36}$') { $objectId = $f.Caller }
        $acr = & $claim 'appidacr'
        if (-not $acr) { $acr = & $claim 'azpacr' }
        $methods = @(@(& $claimOf $claimUri.Methods) + @(& $claimOf 'amr') | Where-Object { $_ } | ForEach-Object { ([string]$_) -split '[,\s]+' } | Where-Object { $_ } | Select-Object -Unique)
        $auth = if ($caller.Person) { "User sign-in$(if ($methods.Count) { " ($($methods -join ', '))" })" }
        elseif ($acr -eq '0') { 'Public client' }
        elseif ($acr -eq '1') { 'Client secret' }
        elseif ($acr -eq '2') { 'Certificate or federated credential' }
        elseif ($caller.Kind -eq 'Azure platform') { '' }
        else { '' }
        $issuer = if ((& $claim 'iss') -match '([0-9a-fA-F-]{36})') { $Matches[1] } else { '' }
        $tenantKind = if (-not $issuer -or -not $f.TenantId) { '' } elseif ($issuer -eq $f.TenantId) { 'Home' } else { "External ($issuer)" }
        $roles = @(@(& $claimOf 'wids') | Where-Object { $_ } | ForEach-Object { ([string]$_) -split '[,\s]+' } | Where-Object { $_ } | ForEach-Object {
                $k = $_.ToLowerInvariant()
                if ($RoleName.Contains($k)) { [string]$RoleName[$k] } elseif ($builtInRoles.Contains($k)) { $builtInRoles[$k] } else { $_ }
            })
        $callerName = if ($objectId -and $DirectoryName.Contains($objectId.ToLowerInvariant())) { [string]$DirectoryName[$objectId.ToLowerInvariant()] }
        elseif ($appId -and $DirectoryName.Contains($appId.ToLowerInvariant())) { [string]$DirectoryName[$appId.ToLowerInvariant()] }
        elseif ($caller.Person -and (& $claim 'name')) { & $claim 'name' }
        else { '' }

        # --- Where -------------------------------------------------------------------------------------------------------
        $segments = $f.ResourceId.Trim('/').Split('/')
        $group = ''; $sub = $f.SubscriptionId
        for ($i = 0; $i -lt $segments.Count - 1; $i++) {
            if ($segments[$i] -eq 'resourcegroups' -and -not $group) { $group = $segments[$i + 1] }
            if ($segments[$i] -eq 'subscriptions' -and -not $sub) { $sub = $segments[$i + 1] }
        }
        $provider = [Array]::LastIndexOf([string[]]@($segments | ForEach-Object { $_.ToLowerInvariant() }), 'providers')
        $type = $f.ResourceType
        if (-not $type -and $provider -ge 0 -and $segments.Count -gt $provider + 2) { $type = "$($segments[$provider + 1])/$((@(for ($j = $provider + 2; $j -lt $segments.Count; $j += 2) { $segments[$j] })) -join '/')" }
        $known = if ($f.ResourceId) { $Resource[$f.ResourceId.ToLowerInvariant()] } else { $null }
        $tags = if ($known -and $known.Tags -is [System.Collections.IDictionary]) { (@($known.Tags.Keys | Sort-Object | ForEach-Object { "$_=$($known.Tags[$_])" })) -join '; ' } else { '' }

        # --- The result: why it failed -------------------------------------------------------------------------------------
        $statusCode = & $text $f.Properties 'statusCode'
        $failed = $f.Status -eq 'Failed' -or ($f.Category -eq 'Policy' -and $f.Operation -match '(?i)deny')
        $why = if ($failed) { Read-AACActivityLogError -StatusMessage (& $text $f.Properties 'statusMessage') -StatusCode $statusCode -SubStatus $f.SubStatus -Operation $f.Operation -EventCategory $f.Category } else { $null }
        $http = if ($f.SubStatusText -match 'HTTP Status Code:\s*(\d{3})') { [int]$Matches[1] }
        elseif ($statusCode -match '^\d{3}$') { [int]$statusCode }
        elseif ($httpCodes.Contains($statusCode)) { $httpCodes[$statusCode] }
        elseif ($httpCodes.Contains($f.SubStatus)) { $httpCodes[$f.SubStatus] }
        else { $null }
        $delay = if ($f.Time -and $f.Submitted -and $f.Submitted -ge $f.Time) { ($f.Submitted - $f.Time).ToString('hh\:mm\:ss') } else { '' }

        $row = [ordered]@{
            PSTypeName     = 'AAC.ActivityLogEvent'
            Time           = $f.Time
            Status         = $f.Status
            Operation      = $f.Label
            Phase          = $f.Phase
            Level          = $f.Level
            Category       = $f.Category
            Channel        = $f.Channel
            CallerKind     = $caller.Kind
            Caller         = $caller.Name
            CallerName     = $callerName
            AppId          = $appId
            ObjectId       = $objectId
            AuthMethod     = $auth
            Tenant         = $tenantKind
            DirectoryRoles = ($roles -join ', ')
            TokenIssued    = & $epoch (& $claim 'iat')
            TokenExpires   = & $epoch (& $claim 'exp')
            CallerIp       = $f.CallerIp
            Subscription   = $(if ($sub -and $SubscriptionName.Contains($sub.ToLowerInvariant())) { [string]$SubscriptionName[$sub.ToLowerInvariant()] } else { $sub })
            ResourceGroup  = $group
            ResourceType   = $type
            Resource       = $(if ($f.ResourceId) { $segments[-1] } else { '' })
            Location       = $(if ($known) { [string]$known.Location } else { '' })
            Tags           = $tags
            Action         = & $text $f.Authorization 'action'
            Scope          = & $text $f.Authorization 'scope'
            HttpStatus     = $http
            SubStatus      = $f.SubStatusText
            ErrorCode      = $(if ($why) { $why.Code } else { '' })
            ErrorMessage   = $(if ($why) { $why.Message } else { '' })
            ErrorTarget    = $(if ($why) { $why.Target } else { '' })
            ErrorCategory  = $(if ($why) { $why.Category } else { '' })
            Fix            = $(if ($why) { $why.Fix } else { '' })
            Link           = $(if ($why) { $why.Link } else { '' })
            IngestionDelay = $delay
            CorrelationId  = $f.CorrelationId
            OperationId    = $f.OperationId
            EventDataId    = $f.EventDataId
            SubscriptionId = $sub
            TenantId       = $f.TenantId
            Hierarchy      = $f.Hierarchy
            PortalLink     = $(if ($f.ResourceId) { "https://portal.azure.com/#@$($f.TenantId)/resource$($f.ResourceId)" } else { '' })
            ResourceId     = $f.ResourceId
            OperationType  = $f.Operation
            Source         = $Source
        }
        if ($IncludeClaims -and $claims -is [System.Collections.IDictionary]) {
            foreach ($k in @($claims.Keys | Sort-Object)) {
                $short = ([string]$k -split '/')[-1]
                $name = "Claim:$short"
                if ($row.Contains($name)) { $name = "Claim:$k" }
                $v = $claims[$k]
                $row[$name] = if ($v -is [System.Collections.IList] -and $v -isnot [string]) { (@($v) -join ', ') } else { [string]$v }
            }
        }
        [pscustomobject]$row
    }
    @($rows | Sort-Object -Property Time)
}
