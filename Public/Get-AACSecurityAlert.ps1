function Get-AACSecurityAlert {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Lists Microsoft Defender for Cloud's security alerts across your
        subscriptions - what was detected, on which resource, its MITRE
        ATT&CK tactics and techniques, the hosts, accounts and IP addresses
        involved, and what to do - open and most severe first, with the
        alerts that keep coming back called out.
    .DESCRIPTION
        The equivalent of Get-AzSecurityAlert (Az.Security), read for every
        subscription in one Azure Resource Graph query rather than one
        subscription and location at a time, and with more to filter on and
        more in each alert:

          Alert, Severity, Status   what Defender for Cloud detected
          Intent, Techniques        the MITRE ATT&CK tactics (kill-chain
                                    stages) and technique IDs
          Resource                  the Azure resource it is about (type,
                                    resource group, subscription), else the
                                    compromised entity
          Hosts, Accounts,          the entities in the alert, each kind on
          IpAddresses, Entities     its own, ready to pivot on
          TimeGenerated, AgeDays    when, and how long ago
          Remediation               Defender's steps, as plain text
          ExtendedProperties        the alert's own details (a dictionary)
          Occurrences               how many alerts in the list share its
                                    type and resource
          Incident                  a Defender incident (correlated alerts)
          AlertUrl                  the alert in the Azure portal

        By default the open alerts (Active and In progress); -Status picks
        others (-Name on its own reads every status, as Get-AzSecurityAlert
        -Name does). -Severity, -Status and -Days are applied in Resource
        Graph; the rest in PowerShell.

        At the prompt: tiles, the alerts by severity, MITRE tactic (in
        kill-chain order), day and resource, the alerts, and the recurring
        ones - three or more of a type on one resource, to fix at the source
        or tune with a suppression rule. Subscriptions with no Defender plan
        on are pointed out: they raise no alerts, so an empty list there
        proves nothing.

        Read-only; Reader (or Security Reader) is enough. Changing an alert's
        state is done in Defender for Cloud.
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups (at any depth).
    .PARAMETER ResourceGroupName
        Only alerts on resources in these resource groups.
    .PARAMETER ResourceId
        Only alerts on these resources, or on anything under them (a
        resource group or subscription ID works too). Takes ResourceId or Id
        from the pipeline, so resources from Get-AACInventory, Get-AzResource
        or Get-AzVM can be piped in.
    .PARAMETER Name
        Only alerts whose name (Get-AzSecurityAlert's -Name, the alert's
        resource name) or display name matches; wildcards work. Without
        -Status, every status is read.
    .PARAMETER AlertType
        Only alerts of these types (for example VM_SuspiciousLogin, or
        'K8S_*'); wildcards work.
    .PARAMETER Severity
        Only alerts of these severities (High, Medium, Low, Informational).
    .PARAMETER Status
        Only alerts in these states (Active, InProgress, Resolved,
        Dismissed). Default: Active and InProgress.
    .PARAMETER Tactic
        Only alerts with one of these MITRE ATT&CK tactics (for example
        InitialAccess, CredentialAccess, 'Lateral*'); wildcards work.
    .PARAMETER Days
        Only alerts generated in the last this many days.
    .PARAMETER Incident
        Only incidents: Defender's correlations of related alerts.
    .PARAMETER CsvPath
        Write the alerts to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report.
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the alerts.
    .PARAMETER NoDisplay
        Return the alerts without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Get-AACSecurityAlert
        The open alerts in every subscription you can see, most severe first.
    .EXAMPLE
        Get-AACSecurityAlert -Severity High -Days 7 -HtmlPath .\out\Alerts.html
        This week's open High alerts, as an interactive HTML report.
    .EXAMPLE
        Get-AACSecurityAlert -Status Active, InProgress, Resolved, Dismissed -Days 90 -CsvPath .\out\Alerts.csv
        Every alert of the last 90 days, whatever its state, to CSV.
    .EXAMPLE
        Get-AACSecurityAlert -Tactic CredentialAccess, LateralMovement -NoDisplay | Select-Object Alert, Resource, Accounts, IpAddresses
        Who and where for the alerts that point to an attacker moving around.
    .EXAMPLE
        Get-AACSecurityAlert -NoDisplay | Where-Object IpAddresses -Match '203\.0\.113\.' | Group-Object Resource
        Every resource an IP address range shows up against.
    .EXAMPLE
        Get-AACInventory -NoDisplay | Where-Object ResourceGroup -EQ 'rg-prod' | Get-AACSecurityAlert
        The open alerts on the resources piped in.
    .EXAMPLE
        Get-AACSecurityAlert -Name '2517*' -NoDisplay | Select-Object -ExpandProperty ExtendedProperties
        One alert by its name, whatever its state, with Defender's details.
    .OUTPUTS
        AAC.SecurityAlert
    #>
    [CmdletBinding()]
    [OutputType('AAC.SecurityAlert')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string[]] $ManagementGroupId,

        [string[]] $ResourceGroupName,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Id')]
        [string[]] $ResourceId,

        [SupportsWildcards()]
        [string[]] $Name,

        [SupportsWildcards()]
        [string[]] $AlertType,

        [ValidateSet('High', 'Medium', 'Low', 'Informational')]
        [string[]] $Severity,

        [ValidateSet('Active', 'InProgress', 'Resolved', 'Dismissed')]
        [string[]] $Status,

        [SupportsWildcards()]
        [string[]] $Tactic,

        [ValidateRange(1, 3650)]
        [int] $Days,

        [switch] $Incident,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Defender for Cloud security alerts',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    begin {
        $wantedResources = [System.Collections.Generic.List[string]]::new()
    }

    process {
        foreach ($id in @($ResourceId | Where-Object { $_ })) { $wantedResources.Add($id.TrimEnd('/').ToLowerInvariant()) }
    }

    end {
        trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

        $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
        $interactive = -not $NoDisplay -and -not $pipedOnward
        $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
        $request = @{ SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }) }
        # Open alerts unless told otherwise; one asked for by name, whatever its state.
        $states = @(if ($Status) { $Status } elseif (-not $Name) { 'Active', 'InProgress' })
        $filter = @{ Days = $Days }
        if ($states.Count) { $filter.Status = $states }
        if ($Severity) { $filter.Severity = $Severity }
        $queries = Get-AACSecurityAlertQuery @filter
        $statusLabel = if ($states.Count) { ($states | ForEach-Object { @{ InProgress = 'in progress' }[$_] ?? $_.ToLowerInvariant() }) -join ', ' } else { 'every status' }

        $null = Get-AACAccessToken
        if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Security alerts' -Color 'red3' }
        $state = Invoke-AACProgress -ScriptBlock {
            Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
            $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
            Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"
            Update-AACProgress -Id 'read' -Total $queries.Count -Description 'Reading the security alerts and Defender plans'
            $read = Invoke-AACGraphBatch -Query $queries -SubscriptionId $scope.GraphScope -AllowFailure @('plans') -OnProgress {
                param($QueryName, $Done, $Total)
                Update-AACProgress -Id 'read' -Increment 1 -Description "Read the $QueryName ($Done of $Total)"
            }
            $result = ConvertTo-AACSecurityAlert -Read $read -SubscriptionName $scope.Names
            Update-AACProgress -Id 'read' -Complete -Description ('{0:N0} alert(s) ({1}): {2:N0} open, {3:N0} high' -f $result.Stats.Alerts, $statusLabel, $result.Stats.Open, $result.Stats.High)
            @{ Result = $result; Scope = $scope }
        }

        # --- The filters Resource Graph didn't apply ---------------------------------------------------------------
        $result = $state.Result
        $alerts = @($result.Alerts)
        $matchesAny = { param([string[]] $Value, [string[]] $Pattern) foreach ($v in $Value) { foreach ($p in $Pattern) { if ($v -and $v -like $p) { return $true } } }; $false }
        if ($Name) { $alerts = @($alerts | Where-Object { & $matchesAny @($_.AlertName, $_.Alert) $Name }) }
        if ($AlertType) { $alerts = @($alerts | Where-Object { & $matchesAny @($_.AlertType) $AlertType }) }
        if ($Tactic) { $alerts = @($alerts | Where-Object { & $matchesAny @($_.Intent -split ', ') $Tactic }) }
        if ($Incident) { $alerts = @($alerts | Where-Object Incident) }
        if ($ResourceGroupName) { $groups = @($ResourceGroupName | ForEach-Object { $_.ToLowerInvariant() }); $alerts = @($alerts | Where-Object { $groups -contains ([string]$_.ResourceGroup).ToLowerInvariant() }) }
        if ($wantedResources.Count) {
            $alerts = @($alerts | Where-Object {
                    foreach ($id in @($_.ResourceIds | ForEach-Object { $_.ToLowerInvariant() })) { foreach ($want in $wantedResources) { if ($id -eq $want -or $id.StartsWith("$want/")) { return $true } } }
                    $false
                })
        }
        $recurring = @($result.Recurring | Where-Object { $r = $_; @($alerts | Where-Object { $_.AlertType -eq $r.AlertType -and $_.ResourceId -eq $r.ResourceId }).Count })

        # --- The report --------------------------------------------------------------------------------------------
        $severityTones = @{ High = 'bad'; Medium = 'warn'; Low = 'info'; Informational = 'neutral' }
        $statusTones = @{ Active = 'bad'; InProgress = 'warn'; Resolved = 'good'; Dismissed = 'neutral' }
        $open = @($alerts | Where-Object Open)
        $high = @($open | Where-Object Severity -EQ 'High').Count
        $medium = @($open | Where-Object Severity -EQ 'Medium').Count
        $incidents = @($alerts | Where-Object Incident).Count
        $resources = @($open | ForEach-Object { if ($_.ResourceId) { $_.ResourceId.ToLowerInvariant() } else { $_.Resource } } | Where-Object { $_ } | Select-Object -Unique).Count
        $oldest = [int](@($open | ForEach-Object { $_.AgeDays } | Where-Object { $null -ne $_ } | Measure-Object -Maximum).Maximum)
        # The MITRE ATT&CK tactics in kill-chain order (Defender's older names last).
        $killChain = @('PreAttack', 'Reconnaissance', 'ResourceDevelopment', 'InitialAccess', 'Execution', 'Persistence', 'PrivilegeEscalation', 'DefenseEvasion', 'CredentialAccess', 'Discovery', 'LateralMovement', 'Collection', 'CommandAndControl', 'Exfiltration', 'Impact', 'Probing', 'Exploitation')
        $tactics = @($alerts | ForEach-Object { @($_.Intent -split ', ' | Where-Object { $_ }) } | Group-Object | Sort-Object { $i = [array]::IndexOf($killChain, $_.Name); if ($i -lt 0) { 99 } else { $i } })
        $rows = @($alerts | ForEach-Object {
                [pscustomobject][ordered]@{
                    Severity           = $_.Severity
                    Status             = $_.Status
                    Alert              = $_.Alert
                    Resource           = $_.Resource
                    ResourceType       = $_.ResourceType
                    ResourceGroup      = $_.ResourceGroup
                    SubscriptionName   = $_.SubscriptionName
                    Intent             = $_.Intent
                    Techniques         = $_.Techniques
                    TimeGenerated      = $_.TimeGenerated
                    AgeDays            = $_.AgeDays
                    Occurrences        = $_.Occurrences
                    Incident           = $(if ($_.Incident) { 'Yes' } else { 'No' })
                    CompromisedEntity  = $_.CompromisedEntity
                    Hosts              = $_.Hosts
                    Accounts           = $_.Accounts
                    IpAddresses        = $_.IpAddresses
                    Entities           = $_.Entities
                    Description        = $_.Description
                    Remediation        = $_.Remediation
                    ExtendedProperties = (@($_.ExtendedProperties.GetEnumerator() | ForEach-Object { "$($_.Key): $($_.Value)" }) -join '; ')
                    AlertType          = $_.AlertType
                    Product            = $_.Product
                    StartTime          = $_.StartTime
                    EndTime            = $_.EndTime
                    AlertName          = $_.AlertName
                    Location           = $_.Location
                    AlertUrl           = $_.AlertUrl
                    SubscriptionId     = $_.SubscriptionId
                    ResourceId         = $_.ResourceId
                    Id                 = $_.Id
                }
            })
        $headline = if (-not $alerts.Count) { "No security alerts ($statusLabel) in scope." }
        elseif ($open.Count) { "$($open.Count) open alert(s) on $resources resource(s): $high high, $medium medium$(if ($incidents) { "; $incidents incident(s)" }) - the oldest is $oldest day(s) old" }
        else { "$($alerts.Count) alert(s), none open." }
        $report = @{
            Subtitle = 'Microsoft Defender for Cloud security alerts: what was detected, where, and what to do'
            Facts    = [ordered]@{ Scope = $state.Scope.Label; Status = $statusLabel; Window = $(if ($Days) { "the last $Days day(s)" } else { 'every alert Defender for Cloud holds' }) }
            Status   = $(if ($high) { 'Failed' } elseif ($open.Count) { 'Warning' } else { 'Success' })
            Headline = $headline
            Tiles    = @(
                @{ Value = '{0:N0}' -f $open.Count; Label = 'open alerts'; Tone = $(if ($high) { 'bad' } elseif ($open.Count) { 'warn' } else { 'good' }) }
                @{ Value = '{0:N0}' -f $high; Label = 'high'; Tone = $(if ($high) { 'bad' } else { 'good' }); Table = 'alerts'; Filters = @{ Severity = 'High' } }
                @{ Value = '{0:N0}' -f $medium; Label = 'medium'; Tone = $(if ($medium) { 'warn' } else { 'good' }); Table = 'alerts'; Filters = @{ Severity = 'Medium' } }
                @{ Value = '{0:N0}' -f $incidents; Label = 'incidents'; Tone = $(if ($incidents) { 'violet' } else { 'good' }); Table = 'alerts'; Filters = @{ Incident = 'Yes' } }
                @{ Value = '{0:N0}' -f $resources; Label = 'resources with open alerts'; Tone = $(if ($resources) { 'warn' } else { 'good' }) }
                @{ Value = '{0:N0}' -f $recurring.Count; Label = 'recurring'; Tone = $(if ($recurring.Count) { 'info' } else { 'good' }); Table = 'recurring' }
            )
            Notices  = @($result.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
            Charts   = @(
                @{ Title = 'Alerts by severity'; Kind = 'donut'; CenterLabel = 'alerts'; Items = @(foreach ($s in 'High', 'Medium', 'Low', 'Informational') { $n = @($alerts | Where-Object Severity -EQ $s).Count; if ($n) { @{ Label = $s; Value = $n; Tone = $severityTones[$s]; Filter = $s } } }); Table = 'alerts'; Column = 'Severity' }
                @{ Title = 'By MITRE ATT&CK tactic'; Items = @($tactics | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'alerts'; Column = 'Intent'; Tone = 'bad'; Console = $true }
                @{ Title = 'Most alerted resources'; Items = @($alerts | Where-Object Resource | Group-Object Resource | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'alerts'; Column = 'Resource'; Tone = 'warn'; Console = $true }
                @{ Title = 'Alerts by day'; Items = @($alerts | Where-Object TimeGenerated | Group-Object { $_.TimeGenerated.ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture) } | Sort-Object Name | Select-Object -Last 30 | ForEach-Object { @{ Label = $_.Name; Value = $_.Count } }); Tone = 'info' }
                @{ Title = 'By alert type'; Items = @($alerts | Group-Object Alert | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'alerts'; Column = 'Alert'; Tone = 'violet' }
            )
            Tables   = @(
                @{ Id = 'alerts'; Title = 'Security alerts'; Section = 'Alerts'; Rows = $rows; Noun = 'alerts'; GroupBy = @('Severity', 'Status', 'Intent', 'Resource', 'SubscriptionName'); ConsoleLimit = 25
                    Empty = "No security alerts ($statusLabel) in scope."; EmptyStatus = 'Success'
                    Columns = @(
                        @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $severityTones; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = $statusTones; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Alert'; Label = 'Alert'; Type = 'wide'; Console = $true; Pdf = $true }
                        @{ Key = 'Resource'; Label = 'Resource'; Type = 'resource'; Console = $true; Pdf = $true }
                        @{ Key = 'Intent'; Label = 'Tactics'; Facet = $true; Console = $true }
                        @{ Key = 'AgeDays'; Label = 'Age (days)'; Type = 'number'; Console = $true; Pdf = $true }
                        @{ Key = 'TimeGenerated'; Label = 'Generated'; Type = 'datetime'; Pdf = $true }
                        @{ Key = 'Occurrences'; Label = 'Occurrences'; Type = 'number' }
                        @{ Key = 'Incident'; Label = 'Incident'; Type = 'badge'; Tones = @{ Yes = 'violet'; No = 'neutral' }; Facet = $true }
                        @{ Key = 'SubscriptionName'; Label = 'Subscription'; Facet = $true }
                        @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                        @{ Key = 'ResourceType'; Label = 'Resource type'; Type = 'type'; Facet = $true }
                        @{ Key = 'Techniques'; Label = 'Techniques'; Type = 'mono' }
                        @{ Key = 'Hosts'; Label = 'Hosts' }
                        @{ Key = 'Accounts'; Label = 'Accounts' }
                        @{ Key = 'IpAddresses'; Label = 'IP addresses'; Type = 'mono' }
                        @{ Key = 'Entities'; Label = 'Entities'; Type = 'wide' }
                        @{ Key = 'Description'; Label = 'Description'; Type = 'wide' }
                        @{ Key = 'Remediation'; Label = 'What to do'; Type = 'wide'; Pdf = $true }
                        @{ Key = 'ExtendedProperties'; Label = 'Details'; Type = 'wide' }
                        @{ Key = 'Product'; Label = 'Product'; Facet = $true }
                        @{ Key = 'AlertType'; Label = 'Alert type'; Type = 'mono'; Hidden = $true }
                        @{ Key = 'AlertUrl'; Label = 'Portal'; Type = 'link'; Text = 'Open' }
                    ) }
                @{ Id = 'recurring'; Title = 'Recurring alerts'; Section = 'Recurring'; Rows = $recurring; Noun = 'recurring alerts'; ConsoleLimit = 10
                    Note = 'Three or more alerts of one type on one resource: fix the cause, or tune expected ones with a suppression rule that expires.'
                    Columns = @(
                        @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $severityTones; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Alert'; Label = 'Alert'; Type = 'wide'; Console = $true; Pdf = $true }
                        @{ Key = 'Resource'; Label = 'Resource'; Type = 'resource'; Console = $true; Pdf = $true }
                        @{ Key = 'Occurrences'; Label = 'Occurrences'; Type = 'number'; Console = $true; Pdf = $true }
                        @{ Key = 'Open'; Label = 'Open'; Type = 'number'; Console = $true }
                        @{ Key = 'FirstSeen'; Label = 'First seen'; Type = 'datetime' }
                        @{ Key = 'LastSeen'; Label = 'Last seen'; Type = 'datetime'; Pdf = $true }
                        @{ Key = 'SubscriptionName'; Label = 'Subscription'; Facet = $true }
                        @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                        @{ Key = 'AlertType'; Label = 'Alert type'; Type = 'mono' }
                        @{ Key = 'Advice'; Label = 'What to do'; Type = 'wide' }
                    ) }
            )
            Hint     = '-Severity, -Tactic, -Days and -Status narrow the list (-Status Resolved, Dismissed for closed ones); -NoDisplay returns the alerts; -HtmlPath, -PdfPath or -CsvPath for a report.'
        }
        Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $rows -Noun 'alert' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
            -ShowView:$interactive -NoPaging:$NoPaging -Object $alerts -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
    }
}
