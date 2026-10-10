function Read-AACM365Graph {
    <#
    .SYNOPSIS
        Reads what Invoke-AACM365Assessment needs from Microsoft Graph, a
        batch at a time, with one token, and looks up the redirect URIs'
        hosts in DNS.
    .DESCRIPTION
        The queries of -Query (Get-AACM365AssessmentQuery) are read in
        batches, one after another, each in parallel:
          Entra ID: tenant and policies
          Entra ID: admin roles, MFA and users
          Sign-in and audit logs
          Applications
          Microsoft 365
          Intune
        A batch reads its queries, then those that need their answers
        (DependsOn): Microsoft Graph's app-role grants after its service
        principal; Users - not every user, which with their last sign-in
        takes many minutes in a large tenant, but the principals of the role
        assignments and the users Conditional Access excludes, by ID 15 to a
        query (Graph's limit for 'in'), and break-glass-like names - and
        those lookups again without the last sign-in (Fallback) if Graph
        refuses it. LegacySignIns is read once per legacy protocol, from
        -SignInDays ago; a query with MaxItems stops after that many (the
        latest audit event, the latest Secure Score). Last, every redirect
        URI host, in DNS (Resolve-AACHostName).

        -OnProgress is called with (batch, what was just read, reads done,
        reads in the batch so far, what is still being read, done?) - the
        batch's first call has nothing read yet, its last has done = $true.

        Returns @{ Data; Errors (as Read-AACGraphQuery's, the per-protocol
        and per-batch reads merged under LegacySignIns and Users); Resolved
        (host -> $true, $false or $null); Fallbacks (the queries answered
        by their Fallback) }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Query,

        [ValidateRange(1, 30)]
        [int] $SignInDays = 7,

        [datetime] $Now = [datetime]::UtcNow,

        [scriptblock] $OnProgress
    )

    $batches = [ordered]@{
        'Entra ID: tenant and policies'        = @('Organization', 'Licenses', 'SecurityDefaults', 'AuthorizationPolicy', 'AuthenticationMethods', 'CrossTenantAccess', 'ConditionalAccess', 'NamedLocations', 'AdminConsentPolicy', 'IdentityProviders', 'DirectorySync', 'PimPolicies')
        'Entra ID: admin roles, MFA and users' = @('RoleDefinitions', 'RoleAssignments', 'RoleEligibility', 'Registration', 'AccessReviews', 'Users', 'Groups', 'GroupMembers')
        'Sign-in and audit logs'               = @('LegacySignIns', 'DirectoryAudits')
        'Threat protection'                    = @('RiskyUsers', 'RiskDetections', 'Incidents')
        'Applications'                         = @('Applications', 'ServicePrincipals', 'GraphServicePrincipal', 'DelegatedGrants', 'GraphAppRoleGrants')
        'Microsoft 365'                        = @('Domains', 'SecureScore', 'SecureScoreProfiles', 'SharePoint', 'UsageReport')
        'Intune'                               = @('DeviceManagement', 'EnrollmentRestrictions', 'ComplianceSummary', 'CompliancePolicies', 'ConfigurationPolicies', 'Intents', 'Templates', 'AppProtectionIos', 'AppProtectionAndroid', 'ManagedDevices', 'EntraDevices')
    }
    # A query in no batch (added later, and not placed above) still gets read.
    $placed = @($batches.Values | ForEach-Object { $_ })
    $others = @($Query.Keys | Where-Object { $placed -notcontains $_ })
    if ($others.Count) { $batches['Other'] = $others }

    $legacyProtocols = @('IMAP4', 'POP3', 'Authenticated SMTP', 'Exchange ActiveSync', 'Exchange Web Services', 'MAPI Over HTTP', 'Outlook Anywhere (RPC over HTTP)', 'Autodiscover', 'Exchange Online PowerShell', 'Other clients')
    $since = $Now.AddDays(-$SignInDays).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $quote = { param([string] $Text) "'" + ($Text -replace "'", "''") + "'" }
    $spec = { param($Q, [string] $Uri) if ($Q['MaxItems']) { @{ Uri = $Uri; MaxItems = $Q['MaxItems'] } } else { $Uri } }
    $data = @{}; $errors = @{}
    $fallbacks = [System.Collections.Generic.List[string]]::new()
    $split = [System.Collections.Generic.List[string]]::new()   # keys read in parts: Name|part

    # The callbacks run inside Invoke-AACHttpBatch: every name they use is m365-prefixed.
    $m365Progress = $OnProgress
    $m365Labels = @{}
    $m365State = @{ Batch = ''; Done = 0; Total = 0; Pending = [System.Collections.Generic.List[string]]::new() }
    $m365Round = {
        param([System.Collections.IDictionary] $Reads)
        $m365State.Total += $Reads.Count
        foreach ($k in $Reads.Keys) { $m365State.Pending.Add($k) }
        if ($m365Progress) { & $m365Progress $m365State.Batch '' $m365State.Done $m365State.Total '' $false }
        $result = Read-AACGraphQuery -Query $Reads -ThrottleLimit 8 -OnDone {
            param($Key, $Failure, $Done, $Total)
            $m365State.Done++; $null = $m365State.Pending.Remove($Key)
            if ($m365Progress) {
                $waiting = @($m365State.Pending | ForEach-Object { $m365Labels[$_] } | Select-Object -Unique)
                & $m365Progress $m365State.Batch $m365Labels[$Key] $m365State.Done $m365State.Total ($waiting -join ', ') $false
            }
        }
        foreach ($k in $Reads.Keys) { if ($result.Data.Contains($k)) { $data[$k] = $result.Data[$k]; $errors.Remove($k) } else { $errors[$k] = $result.Errors[$k] } }
    }

    foreach ($batch in $batches.Keys) {
        $names = @($batches[$batch] | Where-Object { $Query.Contains($_) })
        if (-not $names.Count) { continue }
        $m365State.Batch = $batch; $m365State.Done = 0; $m365State.Total = 0; $m365State.Pending.Clear()

        # --- What the batch reads first ------------------------------------------------------------------------------
        $first = [ordered]@{}
        foreach ($name in $names) {
            $q = $Query[$name]
            if ($q['DependsOn']) { continue }
            if ($name -eq 'LegacySignIns') {
                foreach ($protocol in $legacyProtocols) {
                    $key = "LegacySignIns|$protocol"
                    $first[$key] = & $spec $q ($q.Uri -f $since, [System.Uri]::EscapeDataString($protocol))
                    $m365Labels[$key] = 'legacy authentication sign-ins'; $split.Add($key)
                }
                continue
            }
            $first[$name] = & $spec $q ($q.Uri.Replace('{since}', $since))
            $m365Labels[$name] = ([string]$q.Data).ToLowerInvariant()
        }
        if ($first.Count) { & $m365Round $first }

        # --- Then what needed those answers ------------------------------------------------------------------------------
        $second = [ordered]@{}
        $lookups = [ordered]@{}   # Users part -> its $filter
        foreach ($name in $names) {
            $q = $Query[$name]
            if (-not $q['DependsOn']) { continue }
            if ($name -eq 'GroupMembers') { continue }   # after the groups are known, below
            if ($q['Lookup']) {
                # Users: the principals of the role assignments, and whom Conditional Access
                # excludes. Groups: the groups it excludes, and any role principal that is one.
                $principals = @(@($data['RoleAssignments']) + @($data['RoleEligibility']) | Where-Object { $_ -is [System.Collections.IDictionary] } | ForEach-Object { [string]$_['principalId'] })
                $policyUsers = @(@($data['ConditionalAccess']) | Where-Object { $_ -is [System.Collections.IDictionary] -and $_['conditions'] -is [System.Collections.IDictionary] -and $_['conditions']['users'] -is [System.Collections.IDictionary] } | ForEach-Object { $_['conditions']['users'] })
                $ids = if ($name -eq 'Groups') { @($principals) + @($policyUsers | ForEach-Object { @($_['excludeGroups']) }) } else { @($principals) + @($policyUsers | ForEach-Object { @($_['excludeUsers']) }) }
                $ids = @($ids | Where-Object { $_ -and $_ -notin 'All', 'None', 'GuestsOrExternalUsers' -and $_ -notmatch '\s' } | ForEach-Object { ([string]$_).ToLowerInvariant() } | Select-Object -Unique)
                $mine = [ordered]@{}
                for ($i = 0; $i -lt $ids.Count; $i += 15) {
                    $mine["$name|ids$i"] = "id in ($((@($ids[$i..([Math]::Min($i + 14, $ids.Count - 1))] | ForEach-Object { & $quote $_ })) -join ','))"
                }
                if ($name -eq 'Users') { $mine["$name|names"] = (@(foreach ($field in 'displayName', 'userPrincipalName') { foreach ($prefix in 'break', 'emergency', 'bg-', 'bga') { "startswith($field,$(& $quote $prefix))" } }) -join ' or ') }
                if (-not $mine.Count) {
                    # Nothing to look up: none, or because what names them couldn't be read.
                    $sources = @('RoleAssignments', 'RoleEligibility', 'ConditionalAccess' | Where-Object { $names -contains $_ })
                    if ($sources.Count -and -not @($sources | Where-Object { $data.Contains($_) }).Count) { $errors[$name] = "Not read: it needs $($sources -join ' or '), which couldn't be read." }
                    else { $data[$name] = @() }
                    continue
                }
                foreach ($key in $mine.Keys) { $lookups[$key] = $mine[$key]; $second[$key] = ($q.Uri -f [System.Uri]::EscapeDataString($mine[$key])); $m365Labels[$key] = ([string]$q.Data).ToLowerInvariant(); $split.Add($key) }
                continue
            }
            $parent = $data[$q.DependsOn]
            $id = if ($parent -is [System.Collections.IDictionary]) { [string]$parent['id'] } else { '' }
            if ($id) { $second[$name] = & $spec $q ($q.Uri -f $id); $m365Labels[$name] = ([string]$q.Data).ToLowerInvariant() }
            else { $errors[$name] = "Not read: it needs $($q.DependsOn), which couldn't be read." }
        }
        if ($second.Count) { & $m365Round $second }

        # --- And the lookups Graph refused, without what needs a licence; the groups' members ----------------------------------
        $third = [ordered]@{}
        foreach ($key in $lookups.Keys) {
            $name = $key.Split('|')[0]
            if ($errors.Contains($key) -and $Query[$name]['Fallback']) { $third[$key] = ($Query[$name].Fallback -f [System.Uri]::EscapeDataString($lookups[$key])) }
        }
        if ($names -contains 'GroupMembers') {
            $q = $Query['GroupMembers']
            $groupIds = @($split | Where-Object { $_ -like 'Groups|*' -and $data.Contains($_) } | ForEach-Object { @($data[$_]) } | Where-Object { $_ -is [System.Collections.IDictionary] } | ForEach-Object { [string]$_['id'] } | Select-Object -Unique)
            # At most 30 groups: the ones that matter are a handful; a tenant that excludes more has a finding anyway.
            foreach ($groupId in @($groupIds | Select-Object -First 30)) {
                $key = "GroupMembers|$groupId"
                $third[$key] = & $spec $q ($q.Uri -f $groupId); $m365Labels[$key] = ([string]$q.Data).ToLowerInvariant(); $split.Add($key)
            }
            $groupParts = @($split | Where-Object { $_ -like 'Groups|*' })
            if ($groupParts.Count -and -not @($groupParts | Where-Object { $data.Contains($_) }).Count) { $errors['GroupMembers'] = 'Not read: it needs the groups, which couldn''t be read.' }
            elseif ($errors.Contains('Groups')) { $errors['GroupMembers'] = 'Not read: it needs the groups, which couldn''t be read.' }
            elseif (-not $groupIds.Count) { $data['GroupMembers'] = @() }
        }
        if ($third.Count) {
            & $m365Round $third
            foreach ($key in $third.Keys) { if ($data.Contains($key) -and $lookups.Contains($key)) { $name = $key.Split('|')[0]; if (-not $fallbacks.Contains($name)) { $fallbacks.Add($name) } } }
        }
        if ($m365Progress) { & $m365Progress $batch '' $m365State.Done $m365State.Total '' $true }
    }

    # --- One name per query: the per-protocol and per-batch parts merged ----------------------------------------------------------
    foreach ($name in @($split | ForEach-Object { $_.Split('|')[0] } | Select-Object -Unique)) {
        $parts = @($split | Where-Object { $_ -like "$name|*" } | Select-Object -Unique)
        $readParts = @($parts | Where-Object { $data.Contains($_) })
        if ($readParts.Count) {
            $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $data[$name] = @(foreach ($part in $readParts) {
                    foreach ($item in @($data[$part])) {
                        # A group's members: each tagged with its group (a user may be in several).
                        if ($name -eq 'GroupMembers') { if ($item -is [System.Collections.IDictionary]) { $item['_groupId'] = $part.Split('|')[1] }; $item; continue }
                        if ($item -is [System.Collections.IDictionary] -and $item['id'] -and -not $seen.Add([string]$item['id'])) { continue }
                        $item
                    }
                })
            $errors.Remove($name)
        }
        else { $errors[$name] = [string](@($parts | ForEach-Object { $errors[$_] } | Where-Object { $_ }) | Select-Object -First 1) }
        foreach ($part in $parts) { $data.Remove($part); $errors.Remove($part) }
    }

    # --- Redirect URI hosts, in DNS -----------------------------------------------------------------------------------------------
    $hosts = @(foreach ($app in @($data['Applications'])) {
            if ($app -isnot [System.Collections.IDictionary]) { continue }
            foreach ($kind in 'web', 'spa', 'publicClient') {
                foreach ($uri in @($app[$kind] | Where-Object { $_ -is [System.Collections.IDictionary] } | ForEach-Object { $_['redirectUris'] })) {
                    $parsed = $null
                    if ([System.Uri]::TryCreate([string]$uri, [System.UriKind]::Absolute, [ref]$parsed) -and $parsed.Scheme -in 'http', 'https' -and $parsed.Host -and $parsed.Host -notmatch '^(localhost|127\.|\[::1\])' -and $parsed.Host -notmatch '\*') { $parsed.Host }
                }
            }
        })
    if ($hosts.Count -and $m365Progress) { & $m365Progress 'Redirect URIs in DNS' '' 0 ($hosts | Select-Object -Unique).Count 'DNS lookups' $false }
    $resolved = Resolve-AACHostName -HostName $hosts
    if ($hosts.Count -and $m365Progress) { & $m365Progress 'Redirect URIs in DNS' '' $resolved.Count $resolved.Count '' $true }
    @{ Data = $data; Errors = $errors; Resolved = $resolved; Fallbacks = $fallbacks.ToArray() }
}
