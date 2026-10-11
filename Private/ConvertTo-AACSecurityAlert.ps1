function ConvertTo-AACSecurityAlert {
    <#
    .SYNOPSIS
        Builds Get-AACSecurityAlert's alerts (AAC.SecurityAlert) from the
        Resource Graph rows of Get-AACSecurityAlertQuery: what was detected,
        on which resource, the MITRE ATT&CK tactics and techniques, the
        entities involved (hosts, accounts, IP addresses, files, processes),
        the extended properties, the remediation steps, how often it recurs
        - and the subscriptions with no Defender plan on.
    .DESCRIPTION
        No Azure calls. -Read is Invoke-AACGraphBatch's result (Rows: alerts,
        plans; Errors). -SubscriptionName names the subscriptions in scope
        (lower-case ID -> name); rows of others are left out.

        Occurrences: how many alerts in the list share the alert's type and
        resource - three or more is a recurring alert, worth fixing at the
        source or tuning with a suppression rule.

        Sorted: open (Active, InProgress) before closed, then severity, then
        newest first. Returns @{ Alerts; Recurring; Notices; Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Read,

        [hashtable] $SubscriptionName = @{},

        [datetime] $Now = [datetime]::UtcNow
    )

    # --- Helpers ---------------------------------------------------------------------------------------------
    # Alert properties have come back in both cases: read keys case-insensitively.
    $get = {
        param($Object, [string] $Key)
        if ($Object -isnot [System.Collections.IDictionary]) { return $null }
        foreach ($k in $Object.Keys) { if ($k -eq $Key) { return $Object[$k] } }
    }
    $text = { param($Object, [string] $Key) $v = & $get $Object $Key; if ($null -eq $v) { '' } else { [string]$v } }
    $list = { param($Item) @(if ($Item -is [System.Collections.IEnumerable] -and $Item -isnot [string] -and $Item -isnot [System.Collections.IDictionary]) { $Item } elseif ($null -ne $Item) { , $Item }) | Where-Object { $null -ne $_ -and '' -ne $_ } }
    $rowsOf = { param([string] $Name) @(if ($Read.Rows -and $Read.Rows.Contains($Name)) { $Read.Rows[$Name] | Where-Object { $null -ne $_ } }) }
    $inScope = { param([string] $Subscription) $Subscription -and $SubscriptionName.Contains($Subscription.ToLowerInvariant()) }
    $subscriptionLabel = { param([string] $Id) $key = ([string]$Id).ToLowerInvariant(); if ($SubscriptionName.Contains($key)) { $SubscriptionName[$key] } else { $Id } }
    $date = {
        param([string] $Value)
        $d = [datetime]::MinValue
        if ($Value -and [datetime]::TryParse($Value, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$d)) { $d } else { $null }
    }
    # Defender's texts carry HTML (<br>, links, &nbsp;): as plain text, one step a line.
    $plain = {
        param([string] $Html)
        if (-not $Html) { return '' }
        $t = $Html -replace '(?i)<br\s*/?>|</p>|</li>', "`n" -replace '(?i)<li[^>]*>', '- ' -replace '<[^>]+>', ''
        ([System.Net.WebUtility]::HtmlDecode($t).Replace([char]0x00A0, ' ') -replace '[ \t]+\n', "`n" -replace '\n{3,}', "`n`n").Trim()
    }
    # /subscriptions/s/resourceGroups/g/providers/Microsoft.Compute/virtualMachines/vm -> its parts.
    $parse = {
        param([string] $Id)
        $r = @{ Name = ''; Type = ''; Group = '' }
        if (-not $Id) { return $r }
        if ($Id -notmatch '^/') { $r.Name = $Id; return $r }
        $parts = $Id.Trim('/').Split('/')
        $lower = @($parts | ForEach-Object { $_.ToLowerInvariant() })
        $g = [array]::IndexOf($lower, 'resourcegroups')
        if ($g -ge 0 -and $g + 1 -lt $parts.Count) { $r.Group = $parts[$g + 1] }
        $p = [array]::LastIndexOf($lower, 'providers')
        if ($p -ge 0 -and $p + 2 -lt $parts.Count) { $r.Type = ($lower[$p + 1] + '/' + (@(for ($j = $p + 2; $j -lt $parts.Count; $j += 2) { $lower[$j] }) -join '/')) }
        elseif ($r.Group) { $r.Type = 'microsoft.resources/resourcegroups' }
        else { $r.Type = 'microsoft.resources/subscriptions' }
        $r.Name = $parts[-1]
        $r
    }
    # One entity (Defender's alert schema) -> @{ Kind; Value }, or nothing for a bare $ref.
    $entityOf = {
        param($Entity)
        $kind = (& $text $Entity 'type').ToLowerInvariant()
        if (-not $kind) { return }
        $value = switch -Wildcard ($kind) {
            'host' {
                $hostName = & $text $Entity 'HostName'
                if (-not $hostName) { $hostName = & $text $Entity 'NetBiosName' }
                if (-not $hostName -and (& $text $Entity 'AzureID')) { $hostName = ((& $text $Entity 'AzureID') -split '/')[-1] }
                if ($hostName -and (& $text $Entity 'DnsDomain') -and $hostName -notmatch '\.') { "$hostName.$(& $text $Entity 'DnsDomain')" } else { $hostName }
            }
            'ip' { & $text $Entity 'Address' }
            'account' {
                $name = & $text $Entity 'Name'
                if ($name -and (& $text $Entity 'UPNSuffix')) { "$name@$(& $text $Entity 'UPNSuffix')" }
                elseif ($name -and (& $text $Entity 'NTDomain')) { "$(& $text $Entity 'NTDomain')\$name" }
                elseif ($name) { $name }
                else { & $text $Entity 'AadUserId' }
            }
            'file' { $n = & $text $Entity 'Name'; $d = & $text $Entity 'Directory'; if ($d -and $n) { "$($d.TrimEnd('\', '/'))$(if ($d -match '/') { '/' } else { '\' })$n" } else { $n } }
            'filehash' { $v = & $text $Entity 'Value'; if ($v) { "$(& $text $Entity 'Algorithm') $v".Trim() } }
            'process' { $c = & $text $Entity 'CommandLine'; if ($c) { if ($c.Length -gt 160) { $c.Substring(0, 157) + '...' } else { $c } } elseif (& $text $Entity 'ProcessId') { "PID $(& $text $Entity 'ProcessId')" } }
            'azure-resource' { ((& $text $Entity 'ResourceId') -split '/')[-1] }
            'url' { & $text $Entity 'Url' }
            'dns' { & $text $Entity 'DomainName' }
            'mailbox' { & $text $Entity 'MailboxPrimaryAddress' }
            'blob*' { $u = & $text $Entity 'Url'; if ($u) { $u } else { & $text $Entity 'Name' } }
            default { foreach ($k in 'Name', 'FriendlyName', 'DisplayName', 'Address', 'Url') { $v = & $text $Entity $k; if ($v) { $v; break } } }
        }
        if ($value) { @{ Kind = $kind; Value = [string]$value } }
    }
    $rank = (Get-AACSeverityRank).Rank
    $rank['Informational'] = 4
    $rankOf = { param([string] $Severity) if ($Severity -and $rank.Contains($Severity)) { $rank[$Severity] } else { 5 } }
    $notices = [System.Collections.Generic.List[string]]::new()

    # --- Alerts ------------------------------------------------------------------------------------------------
    $alerts = @(foreach ($row in (& $rowsOf 'alerts')) {
            $subscription = & $text $row 'subscriptionId'
            if (-not (& $inScope $subscription)) { continue }
            $identifiers = @(& $list (& $get $row 'resources'))
            # The Azure resource it is about, else the compromised entity.
            $target = [string](@($identifiers | ForEach-Object { & $text $_ 'AzureResourceId' } | Where-Object { $_ }) | Select-Object -First 1)
            $where = & $parse $target
            $entities = @(@(& $list (& $get $row 'entities')) | ForEach-Object { & $entityOf $_ } | Where-Object { $_ })
            $seen = @{}
            $entities = @($entities | Where-Object { $key = "$($_.Kind)|$($_.Value)".ToLowerInvariant(); if ($seen.Contains($key)) { $false } else { $seen[$key] = 1; $true } })
            $ofKind = { param([string[]] $Kind) (@($entities | Where-Object { $Kind -contains $_.Kind } | ForEach-Object { $_.Value }) -join '; ') }
            $extended = [ordered]@{}
            $bag = & $get $row 'extended'
            if ($bag -is [System.Collections.IDictionary]) { foreach ($k in @($bag.Keys | Sort-Object)) { $extended[[string]$k] = [string]$bag[$k] } }
            $when = & $date (& $text $row 'generated')
            $status = & $text $row 'status'
            $compromised = & $text $row 'entity'
            $item = [pscustomobject][ordered]@{
                Alert              = & $text $row 'name'
                Severity           = & $text $row 'severity'
                Status             = $status
                Open               = $status -in 'Active', 'InProgress'
                Intent             = (@((& $text $row 'intent') -split '\s*,\s*' | Where-Object { $_ }) -join ', ')
                Techniques         = (@(@(& $list (& $get $row 'techniques')) + @(& $list (& $get $row 'subTechniques')) | ForEach-Object { [string]$_ } | Select-Object -Unique) -join ', ')
                Resource           = $(if ($where.Name) { $where.Name } else { $compromised })
                ResourceType       = $where.Type
                ResourceGroup      = $where.Group
                SubscriptionName   = & $subscriptionLabel $subscription
                CompromisedEntity  = $compromised
                TimeGenerated      = $when
                StartTime          = & $date (& $text $row 'start')
                EndTime            = & $date (& $text $row 'end')
                AgeDays            = $(if ($when) { [int][Math]::Floor(($Now - $when).TotalDays) } else { $null })
                AlertType          = & $text $row 'alertType'
                Product            = & $text $row 'product'
                Vendor             = & $text $row 'vendor'
                Incident           = (& $text $row 'isIncident') -eq 'True'
                Hosts              = & $ofKind 'host'
                Accounts           = & $ofKind 'account'
                IpAddresses        = & $ofKind 'ip'
                Entities           = (@($entities | ForEach-Object { "$($_.Kind): $($_.Value)" }) -join '; ')
                Description        = & $plain (& $text $row 'description')
                Remediation        = & $plain ((@(& $list (& $get $row 'remediation')) | ForEach-Object { [string]$_ }) -join "`n")
                ExtendedProperties = $extended
                Occurrences        = 1
                AlertName          = & $text $row 'alertName'
                Location           = & $text $row 'location'
                AlertUrl           = & $text $row 'link'
                SubscriptionId     = $subscription.ToLowerInvariant()
                ResourceId         = $target
                ResourceIds        = @($identifiers | ForEach-Object { & $text $_ 'AzureResourceId' } | Where-Object { $_ } | Select-Object -Unique)
                Id                 = & $text $row 'id'
            }
            $item.PSObject.TypeNames.Insert(0, 'AAC.SecurityAlert')
            $item
        })
    $alerts = @($alerts | Sort-Object -Property @{ Expression = { if ($_.Open) { 0 } else { 1 } } }, @{ Expression = { & $rankOf $_.Severity } }, @{ Expression = 'TimeGenerated'; Descending = $true })

    # --- Recurring: the same alert type on the same resource ---------------------------------------------------
    $recurring = @(foreach ($group in @($alerts | Group-Object -Property { "$($_.AlertType)|$(if ($_.ResourceId) { $_.ResourceId.ToLowerInvariant() } else { $_.Resource })" })) {
            foreach ($alert in $group.Group) { $alert.Occurrences = $group.Count }
            if ($group.Count -lt 3) { continue }
            $first = $group.Group[0]
            $times = @($group.Group | ForEach-Object { $_.TimeGenerated } | Where-Object { $_ } | Sort-Object)
            [pscustomobject][ordered]@{
                Alert            = $first.Alert
                Severity         = @($group.Group | Sort-Object { & $rankOf $_.Severity })[0].Severity
                Resource         = $first.Resource
                ResourceGroup    = $first.ResourceGroup
                SubscriptionName = $first.SubscriptionName
                Occurrences      = $group.Count
                Open             = @($group.Group | Where-Object Open).Count
                FirstSeen        = $(if ($times.Count) { $times[0] } else { $null })
                LastSeen         = $(if ($times.Count) { $times[-1] } else { $null })
                AlertType        = $first.AlertType
                Advice           = 'Recurs: fix the cause on the resource, or - if it is expected (a scanner, an admin tool) - dismiss it with a suppression rule that expires.'
                ResourceId       = $first.ResourceId
            }
        })
    $recurring = @($recurring | Sort-Object -Property @{ Expression = 'Occurrences'; Descending = $true }, Alert)

    # --- Plans: a subscription with none on has no alerts to show ------------------------------------------------
    $plansRead = $Read.Rows -and $Read.Rows.Contains('plans') -and -not ($Read.Errors -and $Read.Errors.Contains('plans'))
    $unprotected = @()
    if ($plansRead) {
        $on = @{}
        foreach ($row in (& $rowsOf 'plans')) {
            $subscription = (& $text $row 'subscriptionId').ToLowerInvariant()
            if ((& $text $row 'tier') -eq 'Standard') { $on[$subscription] = $true }
        }
        $unprotected = @($SubscriptionName.Keys | Where-Object { -not $on.Contains($_) } | Sort-Object { $SubscriptionName[$_] })
        if ($unprotected.Count) {
            $names = @($unprotected | Select-Object -First 5 | ForEach-Object { $SubscriptionName[$_] }) -join ', '
            $more = if ($unprotected.Count -gt 5) { " and $($unprotected.Count - 5) more" } else { '' }
            $notices.Add("No Defender plan is on in $($unprotected.Count) subscription(s) ($names$more): they raise no security alerts, so an empty list there is not a clean bill of health.")
        }
    }
    elseif ($Read.Errors -and $Read.Errors.Contains('plans')) {
        $notices.Add("The Defender plans couldn't be read, so subscriptions with no plan on (and so no alerts) can't be pointed out.")
    }

    $open = @($alerts | Where-Object Open)
    @{
        Alerts    = $alerts
        Recurring = $recurring
        Notices   = @($notices)
        Stats     = @{
            Alerts      = $alerts.Count
            Open        = $open.Count
            High        = @($open | Where-Object Severity -EQ 'High').Count
            Medium      = @($open | Where-Object Severity -EQ 'Medium').Count
            Incidents   = @($alerts | Where-Object Incident).Count
            Resources   = @($open | ForEach-Object { if ($_.ResourceId) { $_.ResourceId.ToLowerInvariant() } else { $_.Resource } } | Where-Object { $_ } | Select-Object -Unique).Count
            OldestOpen  = $(if ($open.Count) { [int](@($open | ForEach-Object { $_.AgeDays } | Where-Object { $null -ne $_ } | Measure-Object -Maximum).Maximum) } else { 0 })
            Unprotected = $unprotected.Count
        }
    }
}
