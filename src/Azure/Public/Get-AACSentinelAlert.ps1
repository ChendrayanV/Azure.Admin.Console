function Get-AACSentinelAlert {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Lists the security alerts in a Microsoft Sentinel workspace - from its
        analytics rules and every connected product (Defender XDR, Defender for
        Cloud, Entra ID Protection...) - with their MITRE ATT&CK tactics, the
        hosts, accounts and IP addresses involved, and the incident each is in.
    .DESCRIPTION
        Queries the workspace's SecurityAlert table with KQL - read-only,
        nothing is changed - taking the latest record of each alert (an alert
        is written again when its status changes), and SecurityIncident for the
        incident each alert was grouped into.

        Each alert: Alert, Severity, Status, Open, Product, Provider,
        Component, Tactics, Techniques, CompromisedEntity, Hosts, Accounts,
        IpAddresses, Entities (the other kinds), TimeGenerated, AgeDays,
        StartTime, EndTime, IncidentNumber, IncidentTitle, IncidentStatus,
        Occurrences (alerts in the list with the same name and compromised
        entity), Description, Remediation, ExtendedProperties (a dictionary),
        AlertType, AlertId and AlertUrl.

        The last 7 days by default (-Days), newest first, at most -Limit
        alerts (10,000). -Severity is applied in the query; the other filters
        in PowerShell.

        At the prompt: tiles, the alerts by severity, product, tactic and day,
        the alerts, and the ones raised again and again. Alerts in no incident
        come from rules that don't create incidents, or products whose
        incidents aren't synced: -NoIncident lists them.

        Needs Log Analytics Reader (or Microsoft Sentinel Reader) on the
        workspace. Get-AACSecurityAlert lists Defender for Cloud's alerts
        across subscriptions instead.
    .PARAMETER WorkspaceId
        The workspace: its workspace ID (GUID), resource ID or name.
    .PARAMETER SubscriptionId
        Where to look for a workspace given by ID (GUID) or name. Every
        subscription the account can see by default.
    .PARAMETER ResourceGroupName
        Narrows a workspace given by name, when the name is in more than one
        resource group.
    .PARAMETER Days
        How far back to look: 1 to 3650 days, 7 by default.
    .PARAMETER Severity
        Only alerts of these severities (High, Medium, Low, Informational).
    .PARAMETER Status
        Only alerts in these states (New, InProgress, Resolved, Dismissed).
    .PARAMETER Name
        Only alerts whose name matches; wildcards work.
    .PARAMETER Product
        Only alerts from products whose name matches (for example 'Azure
        Sentinel', 'Microsoft Defender*'); wildcards work.
    .PARAMETER Tactic
        Only alerts with one of these MITRE ATT&CK tactics (for example
        InitialAccess, 'Lateral*'); wildcards work.
    .PARAMETER Entity
        Only alerts whose compromised entity, hosts, accounts, IP addresses or
        other entities match; wildcards work (for example '*alice*').
    .PARAMETER IncidentNumber
        Only the alerts in these incidents.
    .PARAMETER NoIncident
        Only the alerts that are in no incident.
    .PARAMETER Limit
        Read at most this many alerts, newest first: 10,000 by default.
    .PARAMETER CsvPath
        Write the alerts to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report to this file.
    .PARAMETER PdfPath
        Write a PDF report to this file.
    .PARAMETER Title
        The HTML and PDF reports' title.
    .PARAMETER PassThru
        Show the view and also return the alerts.
    .PARAMETER NoDisplay
        Return the alerts without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once instead of a page at a time.
    .EXAMPLE
        Connect-AAC
        Get-AACSentinelAlert -WorkspaceId 'law-contoso-sentinel'
        The last 7 days of alerts, newest first.
    .EXAMPLE
        Get-AACSentinelAlert -WorkspaceId 'law-contoso-sentinel' -Days 30 -Severity High, Medium -HtmlPath .\out\SentinelAlerts.html
        A month of High and Medium alerts, as an interactive HTML report.
    .EXAMPLE
        Get-AACSentinelAlert -WorkspaceId 'law-contoso-sentinel' -IncidentNumber 4211 -NoDisplay | Select-Object Alert, Accounts, Hosts, IpAddresses
        Who and what is in one incident's alerts.
    .EXAMPLE
        Get-AACSentinelAlert -WorkspaceId 'law-contoso-sentinel' -Entity '*alice*' -Days 90 -NoDisplay | Sort-Object TimeGenerated
        Every alert about one user over 90 days, oldest first.
    .EXAMPLE
        Get-AACSentinelAlert -WorkspaceId 'law-contoso-sentinel' -NoIncident -NoDisplay | Group-Object Alert | Sort-Object Count -Descending
        The alerts no incident was created for, by name.
    .OUTPUTS
        AAC.SentinelAlert (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.SentinelAlert')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [Alias('Workspace', 'WorkspaceName', 'ResourceId')]
        [ValidateNotNullOrEmpty()]
        [string] $WorkspaceId,

        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string] $ResourceGroupName,

        [ValidateRange(1, 3650)]
        [int] $Days = 7,

        [ValidateSet('High', 'Medium', 'Low', 'Informational')]
        [string[]] $Severity,

        [ValidateSet('New', 'InProgress', 'Resolved', 'Dismissed')]
        [string[]] $Status,

        [SupportsWildcards()]
        [string[]] $Name,

        [SupportsWildcards()]
        [string[]] $Product,

        [SupportsWildcards()]
        [string[]] $Tactic,

        [SupportsWildcards()]
        [string[]] $Entity,

        [ValidateRange(1, [int]::MaxValue)]
        [int[]] $IncidentNumber,

        [switch] $NoIncident,

        [ValidateRange(1, 500000)]
        [int] $Limit = 10000,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Microsoft Sentinel alerts',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    # A failure anywhere below ends as a Spectre.Console error panel and this
    # command's own terminating error, not a line inside the module. A stopped
    # pipeline (Select-Object -First, Ctrl+C) is no failure: just return - a
    # rethrow would stop the caller's whole script, not only this command.
    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    if ($IncidentNumber -and $NoIncident) {
        throw [System.ArgumentException]::new('Azure Admin Console can''t list alerts both in -IncidentNumber and in no incident. Use one of -IncidentNumber or -NoIncident.')
    }
    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Target) if ($Target) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Target) } }
    $queryArguments = @{ Days = $Days; Limit = $Limit }
    if ($Severity) { $queryArguments.Severity = $Severity }
    # Read here, not inside the progress block (it runs in Invoke-AACProgress's scope).
    $request = @{ Target = $WorkspaceId.Trim(); SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ResourceGroupName = $ResourceGroupName; Kql = (Get-AACSentinelAlertQuery @queryArguments); Days = $Days }

    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Microsoft Sentinel alerts' -Color 'red3' }
    $state = Invoke-AACProgress -ScriptBlock {
        $null = Get-AACAccessToken
        Update-AACProgress -Id 'read' -Indeterminate -Description "Querying the alerts of the last $($request.Days) day(s) in $($request.Target)"
        $read = Read-AACSentinelWorkspace -Target $request.Target -SubscriptionId $request.SubscriptionId -ResourceGroupName $request.ResourceGroupName -Kql $request.Kql -Timespan "P$($request.Days)D"
        $alerts = @(ConvertTo-AACSentinelAlert -Row @($read.Kql.Rows['alerts']) -IncidentRow @($read.Kql.Rows['incidents']))
        Update-AACProgress -Id 'read' -Complete -Description "Workspace $($read.Name): $($alerts.Count) alert(s) in the last $($request.Days) day(s)"
        @{ Read = $read; Alerts = $alerts }
    }
    $read = $state.Read
    # No SecurityAlert table means nothing has ever raised an alert there: an
    # empty list, not a failure. Anything else and the list would mislead.
    $alertError = [string]$read.Kql.Errors['alerts']
    if ($alertError -and $alertError -notmatch '(?i)failed to resolve.*SecurityAlert') {
        $problem = [System.InvalidOperationException]::new("Azure Admin Console couldn't query the alerts of $($read.Name): $alertError")
        $problem.Data['AACHint'] = 'Your account needs Log Analytics Reader (or Microsoft Sentinel Reader) on the workspace.'
        throw $problem
    }
    $notices = [System.Collections.Generic.List[hashtable]]::new()
    $incidentError = [string]$read.Kql.Errors['incidents']
    if ($incidentError -and $incidentError -notmatch '(?i)failed to resolve.*SecurityIncident') { $notices.Add(@{ Status = 'Warning'; Text = "The incidents couldn't be read, so no alert shows its incident: $incidentError" }) }
    if (@($read.Kql.Rows['alerts']).Count -ge $Limit) { $notices.Add(@{ Status = 'Warning'; Text = "Only the newest $Limit alerts were read. Narrow the list with -Days or -Severity, or raise -Limit." }) }

    # --- The filters the query didn't apply -------------------------------------------------------------------
    $alerts = @($state.Alerts)
    $matchesAny = { param([string[]] $Value, [string[]] $Pattern) foreach ($v in $Value) { foreach ($p in $Pattern) { if ($v -and $v -like $p) { return $true } } }; $false }
    if ($Status) { $alerts = @($alerts | Where-Object { $Status -contains $_.Status }) }
    if ($Name) { $alerts = @($alerts | Where-Object { & $matchesAny @($_.Alert) $Name }) }
    if ($Product) { $alerts = @($alerts | Where-Object { & $matchesAny @($_.Product, $_.Provider) $Product }) }
    if ($Tactic) { $alerts = @($alerts | Where-Object { & $matchesAny @($_.Tactics -split ', ') $Tactic }) }
    if ($Entity) { $alerts = @($alerts | Where-Object { & $matchesAny @(@($_.CompromisedEntity) + @("$($_.Hosts), $($_.Accounts), $($_.IpAddresses), $($_.Entities)" -split ', ')) $Entity }) }
    if ($IncidentNumber) { $alerts = @($alerts | Where-Object { $null -ne $_.IncidentNumber -and $IncidentNumber -contains [int]$_.IncidentNumber }) }
    if ($NoIncident) { $alerts = @($alerts | Where-Object { $null -eq $_.IncidentNumber }) }

    # --- The report -------------------------------------------------------------------------------------------
    $severityTones = @{ High = 'bad'; Medium = 'warn'; Low = 'info'; Informational = 'neutral' }
    $statusTones = @{ New = 'bad'; InProgress = 'warn'; Resolved = 'good'; Dismissed = 'neutral' }
    $high = @($alerts | Where-Object Severity -EQ 'High').Count
    $medium = @($alerts | Where-Object Severity -EQ 'Medium').Count
    $noIncidentCount = @($alerts | Where-Object { $null -eq $_.IncidentNumber }).Count
    $products = @($alerts | Group-Object Product | Sort-Object Count -Descending)
    # Raised three times or more for one entity: worth fixing at the source or tuning.
    $recurring = @($alerts | Where-Object Occurrences -GE 3 | Group-Object { "$($_.Alert)|$($_.CompromisedEntity)" } | ForEach-Object {
            $group = @($_.Group | Sort-Object TimeGenerated)
            [pscustomobject][ordered]@{
                Severity          = $group[-1].Severity
                Alert             = $group[-1].Alert
                CompromisedEntity = $group[-1].CompromisedEntity
                Occurrences       = $group.Count
                Product           = $group[-1].Product
                FirstSeen         = $group[0].TimeGenerated
                LastSeen          = $group[-1].TimeGenerated
                InIncidents       = @($group | Where-Object { $null -ne $_.IncidentNumber } | ForEach-Object IncidentNumber | Select-Object -Unique).Count
            }
        } | Sort-Object Occurrences -Descending)
    $killChain = @('Reconnaissance', 'ResourceDevelopment', 'InitialAccess', 'Execution', 'Persistence', 'PrivilegeEscalation', 'DefenseEvasion', 'CredentialAccess', 'Discovery', 'LateralMovement', 'Collection', 'CommandAndControl', 'Exfiltration', 'Impact')
    $tactics = @($alerts | ForEach-Object { @($_.Tactics -split ', ' | Where-Object { $_ }) } | Group-Object | Sort-Object { $i = [array]::IndexOf($killChain, $_.Name); if ($i -lt 0) { 99 } else { $i } })
    $rows = @($alerts | ForEach-Object {
            [pscustomobject][ordered]@{
                Severity           = $_.Severity
                Status             = $_.Status
                Alert              = $_.Alert
                Product            = $_.Product
                CompromisedEntity  = $_.CompromisedEntity
                Tactics            = $_.Tactics
                Techniques         = $_.Techniques
                TimeGenerated      = $_.TimeGenerated
                AgeDays            = $_.AgeDays
                Incident           = $(if ($null -ne $_.IncidentNumber) { "#$($_.IncidentNumber)" } else { 'None' })
                IncidentTitle      = $_.IncidentTitle
                Occurrences        = $_.Occurrences
                Hosts              = $_.Hosts
                Accounts           = $_.Accounts
                IpAddresses        = $_.IpAddresses
                Entities           = $_.Entities
                Description        = $_.Description
                Remediation        = $_.Remediation
                ExtendedProperties = (@($_.ExtendedProperties.GetEnumerator() | ForEach-Object { "$($_.Key): $($_.Value)" }) -join '; ')
                Provider           = $_.Provider
                Component          = $_.Component
                AlertType          = $_.AlertType
                AlertId            = $_.AlertId
                AlertUrl           = $_.AlertUrl
            }
        })
    $headline = if (-not $alerts.Count) { "No alerts in the last $Days day(s) on $($read.Name)." }
    else { "$($alerts.Count) alert(s) in the last $Days day(s) from $($products.Count) product(s): $high high, $medium medium$(if ($noIncidentCount) { "; $noIncidentCount in no incident" })" }
    $report = @{
        Subtitle = 'Microsoft Sentinel alerts: what was detected, about whom, and which incident it is in'
        Facts    = [ordered]@{ Workspace = "$($read.Name) ($($read.ResourceGroup))"; Window = "the last $Days day(s)" }
        Status   = $(if ($high) { 'Failed' } elseif ($alerts.Count) { 'Warning' } else { 'Success' })
        Headline = $headline
        Tiles    = @(
            @{ Value = '{0:N0}' -f $alerts.Count; Label = 'alerts'; Tone = $(if ($alerts.Count) { 'info' } else { 'good' }); Table = 'alerts' }
            @{ Value = '{0:N0}' -f $high; Label = 'high'; Tone = $(if ($high) { 'bad' } else { 'good' }); Table = 'alerts'; Filters = @{ Severity = 'High' } }
            @{ Value = '{0:N0}' -f $medium; Label = 'medium'; Tone = $(if ($medium) { 'warn' } else { 'good' }); Table = 'alerts'; Filters = @{ Severity = 'Medium' } }
            @{ Value = '{0:N0}' -f $noIncidentCount; Label = 'in no incident'; Tone = $(if ($noIncidentCount) { 'violet' } else { 'good' }); Table = 'alerts'; Filters = @{ Incident = 'None' } }
            @{ Value = '{0:N0}' -f $products.Count; Label = 'products'; Tone = 'neutral' }
            @{ Value = '{0:N0}' -f $recurring.Count; Label = 'recurring'; Tone = $(if ($recurring.Count) { 'info' } else { 'good' }); Table = 'recurring' }
        )
        Notices  = @($notices)
        Charts   = @(
            @{ Title = 'Alerts by severity'; Kind = 'donut'; CenterLabel = 'alerts'; Items = @(foreach ($s in 'High', 'Medium', 'Low', 'Informational') { $n = @($alerts | Where-Object Severity -EQ $s).Count; if ($n) { @{ Label = $s; Value = $n; Tone = $severityTones[$s]; Filter = $s } } }); Table = 'alerts'; Column = 'Severity' }
            @{ Title = 'By product'; Items = @($products | Select-AACFirst 10 | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'alerts'; Column = 'Product'; Tone = 'violet'; Console = $true }
            @{ Title = 'By MITRE ATT&CK tactic'; Items = @($tactics | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'alerts'; Column = 'Tactics'; Tone = 'bad'; Console = $true }
            @{ Title = 'Most frequent alerts'; Items = @($alerts | Group-Object Alert | Sort-Object Count -Descending | Select-AACFirst 10 | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'alerts'; Column = 'Alert'; Tone = 'warn'; Console = $true }
            @{ Title = 'Alerts by day'; Items = @($alerts | Where-Object TimeGenerated | Group-Object { $_.TimeGenerated.ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture) } | Sort-Object Name | Select-Object -Last 30 | ForEach-Object { @{ Label = $_.Name; Value = $_.Count } }); Tone = 'info' }
            @{ Title = 'Most alerted entities'; Items = @($alerts | Where-Object CompromisedEntity | Group-Object CompromisedEntity | Sort-Object Count -Descending | Select-AACFirst 10 | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'alerts'; Column = 'CompromisedEntity'; Tone = 'warn' }
        )
        Tables   = @(
            @{ Id = 'alerts'; Title = 'Alerts'; Section = 'Alerts'; Rows = $rows; Noun = 'alerts'; File = 'sentinel-alerts'; GroupBy = @('Severity', 'Product', 'Tactics', 'Incident'); ConsoleLimit = 30
                Empty = "No alerts in the last $Days day(s)."; EmptyStatus = 'Success'; Hover = @('Description', 'Remediation'); HoverTitle = 'Alert'
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $severityTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Alert'; Label = 'Alert'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'Product'; Label = 'Product'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'CompromisedEntity'; Label = 'Entity'; Console = $true; Pdf = $true }
                    @{ Key = 'Incident'; Label = 'Incident'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'AgeDays'; Label = 'Age (days)'; Type = 'number'; Console = $true }
                    @{ Key = 'TimeGenerated'; Label = 'Generated'; Type = 'datetime'; Pdf = $true }
                    @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = $statusTones; Facet = $true }
                    @{ Key = 'Tactics'; Label = 'Tactics'; Facet = $true }
                    @{ Key = 'Techniques'; Label = 'Techniques'; Type = 'mono' }
                    @{ Key = 'Occurrences'; Label = 'Occurrences'; Type = 'number' }
                    @{ Key = 'Hosts'; Label = 'Hosts' }
                    @{ Key = 'Accounts'; Label = 'Accounts' }
                    @{ Key = 'IpAddresses'; Label = 'IP addresses'; Type = 'mono' }
                    @{ Key = 'Entities'; Label = 'Other entities'; Type = 'wide'; Hidden = $true }
                    @{ Key = 'IncidentTitle'; Label = 'Incident title'; Hidden = $true }
                    @{ Key = 'Description'; Label = 'Description'; Type = 'wide'; Hidden = $true }
                    @{ Key = 'Remediation'; Label = 'What to do'; Type = 'wide'; Hidden = $true }
                    @{ Key = 'ExtendedProperties'; Label = 'Details'; Type = 'wide'; Hidden = $true }
                    @{ Key = 'AlertType'; Label = 'Alert type'; Type = 'mono'; Hidden = $true }
                    @{ Key = 'AlertUrl'; Label = 'Portal'; Type = 'link'; Text = 'Open' }
                ) }
            @{ Id = 'recurring'; Title = 'Recurring alerts'; Section = 'Recurring'; Rows = $recurring; Noun = 'recurring alerts'; ConsoleLimit = 10
                Note = 'Three or more alerts of one name about one entity: fix the cause, or tune the rule or an automation rule for the expected ones.'
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $severityTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Alert'; Label = 'Alert'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'CompromisedEntity'; Label = 'Entity'; Console = $true; Pdf = $true }
                    @{ Key = 'Occurrences'; Label = 'Occurrences'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'InIncidents'; Label = 'Incidents'; Type = 'number'; Console = $true }
                    @{ Key = 'Product'; Label = 'Product'; Facet = $true }
                    @{ Key = 'FirstSeen'; Label = 'First seen'; Type = 'datetime' }
                    @{ Key = 'LastSeen'; Label = 'Last seen'; Type = 'datetime'; Pdf = $true }
                ) }
        )
        Hint     = '-Days, -Severity, -Product, -Tactic and -Entity narrow the list; -IncidentNumber for one incident''s alerts, -NoIncident for alerts no incident holds.'
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $rows -Noun 'alert' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $alerts -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
