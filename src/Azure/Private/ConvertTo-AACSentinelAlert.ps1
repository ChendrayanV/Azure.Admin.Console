function ConvertTo-AACSentinelAlert {
    <#
    .SYNOPSIS
        Turns SecurityAlert rows (Get-AACSentinelAlertQuery's 'alerts') into
        AAC.SentinelAlert objects, with the incident each one is in.
    .DESCRIPTION
        No Azure calls, so it can be tested with made-up rows.

        SecurityAlert keeps a few columns as JSON text: Entities (an array of
        entities, some of them only a $ref to another), ExtendedProperties (an
        object) and Techniques (an array). They are parsed here, the entities
        split by kind - Hosts, Accounts, IpAddresses - as Get-AACSecurityAlert
        does, ready to pivot on. JSON that doesn't parse is kept as it is.

        Occurrences is how many alerts in the list share the alert's name and
        compromised entity. Returns the alerts newest first.
    #>
    [CmdletBinding()]
    [OutputType('AAC.SentinelAlert')]
    param(
        [AllowEmptyCollection()]
        [object[]] $Row = @(),

        # Get-AACSentinelAlertQuery's 'incidents' rows: AlertId, IncidentNumber, IncidentTitle, IncidentStatus.
        [AllowEmptyCollection()]
        [object[]] $IncidentRow = @(),

        [datetime] $Now = [datetime]::UtcNow
    )

    $inv = [cultureinfo]::InvariantCulture
    $date = {
        param($Value)
        if ($Value -is [datetime]) { return $Value.ToUniversalTime() }
        $parsed = [datetime]::MinValue
        if ($Value -and [datetime]::TryParse([string]$Value, $inv, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) { return $parsed }
        $null
    }
    $json = {
        param($Text)
        if ($Text -isnot [string]) { return $Text }
        if (-not $Text.Trim()) { return $null }
        try { ConvertFrom-Json -InputObject $Text -AsHashtable -Depth 50 -ErrorAction Stop } catch { $null }
    }
    $unique = { param($Items) @($Items | Where-Object { $_ } | Select-Object -Unique) -join ', ' }

    $incidentByAlert = @{}
    foreach ($item in @($IncidentRow | Where-Object { $null -ne $_ })) {
        $alertId = ([string]$item['AlertId']).ToLowerInvariant()
        if ($alertId) { $incidentByAlert[$alertId] = $item }
    }

    $alerts = @(foreach ($item in @($Row | Where-Object { $null -ne $_ })) {
            $hosts = [System.Collections.Generic.List[string]]::new()
            $accounts = [System.Collections.Generic.List[string]]::new()
            $addresses = [System.Collections.Generic.List[string]]::new()
            $others = [System.Collections.Generic.List[string]]::new()
            foreach ($entity in @(& $json $item['Entities'])) {
                # A $ref repeats an entity listed earlier: counting it again would double it.
                if ($entity -isnot [System.Collections.IDictionary] -or -not $entity.Contains('Type')) { continue }
                $value = { param([string[]] $Key) foreach ($k in $Key) { if ($entity.Contains($k) -and $entity[$k]) { return [string]$entity[$k] } }; '' }
                switch ([string]$entity['Type']) {
                    'host' { $hosts.Add((& $value 'HostName', 'NetBiosName', 'FQDN')) }
                    'account' {
                        $accountName = & $value 'Name'
                        $accounts.Add($(if ($entity['UPNSuffix']) { "$accountName@$($entity['UPNSuffix'])" } elseif ($entity['NTDomain']) { "$($entity['NTDomain'])\$accountName" } elseif ($accountName) { $accountName } else { & $value 'AadUserId', 'Sid' }))
                    }
                    'ip' { $addresses.Add((& $value 'Address')) }
                    default { $text = & $value 'Url', 'Name', 'ResourceId', 'MailboxPrimaryAddress', 'CommandLine', 'DomainName', 'Value'; if ($text) { $others.Add("$($entity['Type']): $text") } }
                }
            }
            # A JSON array of one comes back from $json as a plain string, so test the text, not the type.
            $listText = { param([string] $Text, [string] $Separator) if ($Text.TrimStart().StartsWith('[')) { @(& $json $Text | Where-Object { $_ }) -join $Separator } else { $Text } }
            $techniqueText = & $listText ([string]$item['Techniques']) ', '
            $extended = & $json $item['ExtendedProperties']
            $generated = & $date $item['TimeGenerated']
            $alertStatus = [string]$item['Status']
            $incident = $incidentByAlert[([string]$item['SystemAlertId']).ToLowerInvariant()]
            [pscustomobject][ordered]@{
                PSTypeName         = 'AAC.SentinelAlert'
                Alert              = [string]$item['AlertName']
                Severity           = [string]$item['AlertSeverity']
                Status             = $alertStatus
                Open               = $alertStatus -in 'New', 'InProgress'
                Product            = $(if ($item['ProductName']) { [string]$item['ProductName'] } else { [string]$item['ProviderName'] })
                Provider           = [string]$item['ProviderName']
                Component          = [string]$item['ProductComponentName']
                # Sentinel writes 'Unknown' for a rule that declares no tactic.
                Tactics            = & $unique @(([string]$item['Tactics']) -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -ne 'Unknown' })
                Techniques         = $techniqueText
                CompromisedEntity  = [string]$item['CompromisedEntity']
                Hosts              = & $unique $hosts
                Accounts           = & $unique $accounts
                IpAddresses        = & $unique $addresses
                Entities           = & $unique $others
                TimeGenerated      = $generated
                AgeDays            = $(if ($generated) { [Math]::Round(($Now - $generated).TotalDays, 1) })
                StartTime          = & $date $item['StartTime']
                EndTime            = & $date $item['EndTime']
                IncidentNumber     = $(if ($incident) { $incident['IncidentNumber'] })
                IncidentTitle      = $(if ($incident) { [string]$incident['IncidentTitle'] } else { '' })
                IncidentStatus     = $(if ($incident) { [string]$incident['IncidentStatus'] } else { '' })
                Occurrences        = 1
                Description        = [string]$item['Description']
                Remediation        = & $listText ([string]$item['RemediationSteps']) ' '
                ExtendedProperties = $(if ($extended -is [System.Collections.IDictionary]) { $extended } else { [ordered]@{} })
                AlertType          = [string]$item['AlertType']
                AlertId            = [string]$item['SystemAlertId']
                AlertUrl           = [string]$item['AlertLink']
            }
        })
    $counts = @{}
    foreach ($alert in $alerts) { $key = "$($alert.Alert)|$($alert.CompromisedEntity)".ToLowerInvariant(); $counts[$key] = 1 + [int]$counts[$key] }
    foreach ($alert in $alerts) { $alert.Occurrences = $counts["$($alert.Alert)|$($alert.CompromisedEntity)".ToLowerInvariant()] }
    @($alerts | Sort-Object -Property @{ Expression = { $_.TimeGenerated }; Descending = $true })
}
