function Get-AACSentinelIncident {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Lists the incidents on a Microsoft Sentinel workspace - severity,
        status, owner, classification, MITRE ATT&CK tactics, the rules that
        raised them, how long they have been open or took to close - open and
        newest first, with the unassigned ones called out.
    .DESCRIPTION
        Reads the workspace's incidents from Azure Resource Manager - read-only,
        nothing is changed - and, for closed ones, when each was closed from
        the workspace's SecurityIncident table (the API doesn't return it).

        By default the open incidents (New and Active), however old. -Status
        picks others; closed incidents are bounded to the last 30 days unless
        -Days says otherwise, because a busy workspace closes far too many to
        read them all. -Days bounds every status by when the incident was
        created. -Status and -Days are applied by the API; the other filters
        in PowerShell.

        Each incident: Number, Title, Severity, Status, Owner, Classification
        and its reason, Created, LastModified, Closed, HoursToClose, HoursOpen,
        Alerts, Provider, Products, Tactics, Techniques, Labels, FirstActivity,
        LastActivity, Description, IncidentId, RuleIds (the analytics rules
        that raised it) and Url (the incident in the portal). These hold
        people's names and email addresses, and so do the reports.

        At the prompt: tiles, the incidents by severity, owner, tactic and day,
        and the incidents. Get-AACSentinelAlert -IncidentNumber lists the
        alerts in an incident.

        Needs Microsoft Sentinel Reader on the workspace (and Log Analytics
        Reader for the close times).
    .PARAMETER WorkspaceId
        The workspace: its workspace ID (GUID), resource ID or name.
    .PARAMETER SubscriptionId
        Where to look for a workspace given by ID (GUID) or name. Every
        subscription the account can see by default.
    .PARAMETER ResourceGroupName
        Narrows a workspace given by name, when the name is in more than one
        resource group.
    .PARAMETER Status
        Only incidents in these states (New, Active, Closed). Default: New and
        Active.
    .PARAMETER Severity
        Only incidents of these severities (High, Medium, Low, Informational).
    .PARAMETER Days
        Only incidents created in the last this many days. Without it, open
        incidents of any age, and closed ones of the last 30 days.
    .PARAMETER Name
        Only incidents whose title matches; wildcards work.
    .PARAMETER Number
        Only these incident numbers. Without -Status, every status is read.
    .PARAMETER Owner
        Only incidents assigned to someone matching (name, UPN or email);
        wildcards work.
    .PARAMETER Unassigned
        Only incidents with no owner.
    .PARAMETER Classification
        Only closed incidents classified as one of these (TruePositive,
        BenignPositive, FalsePositive, Undetermined).
    .PARAMETER Tactic
        Only incidents with one of these MITRE ATT&CK tactics (for example
        InitialAccess, 'Lateral*'); wildcards work.
    .PARAMETER CsvPath
        Write the incidents to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report to this file.
    .PARAMETER PdfPath
        Write a PDF report to this file.
    .PARAMETER Title
        The HTML and PDF reports' title.
    .PARAMETER PassThru
        Show the view and also return the incidents.
    .PARAMETER NoDisplay
        Return the incidents without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once instead of a page at a time.
    .EXAMPLE
        Connect-AAC
        Get-AACSentinelIncident -WorkspaceId 'law-contoso-sentinel'
        The open incidents, newest first.
    .EXAMPLE
        Get-AACSentinelIncident -WorkspaceId 'law-contoso-sentinel' -Severity High -Unassigned
        The open High incidents nobody has picked up.
    .EXAMPLE
        Get-AACSentinelIncident -WorkspaceId 'law-contoso-sentinel' -Status Closed -Days 90 -Classification FalsePositive -NoDisplay | Group-Object RuleIds | Sort-Object Count -Descending
        Which rules raised the most false positives in 90 days.
    .EXAMPLE
        Get-AACSentinelIncident -WorkspaceId 'law-contoso-sentinel' -Status New, Active, Closed -Days 30 -HtmlPath .\out\Incidents.html -CsvPath .\out\Incidents.csv
        Every incident of the last 30 days, as an interactive HTML report and a CSV file.
    .EXAMPLE
        Get-AACSentinelIncident -WorkspaceId 'law-contoso-sentinel' -Number 4211 -NoDisplay | Select-Object -ExpandProperty Description
        One incident by its number, whatever its state.
    .OUTPUTS
        AAC.SentinelIncident (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.SentinelIncident')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [Alias('Workspace', 'WorkspaceName', 'ResourceId')]
        [ValidateNotNullOrEmpty()]
        [string] $WorkspaceId,

        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string] $ResourceGroupName,

        [ValidateSet('New', 'Active', 'Closed')]
        [string[]] $Status,

        [ValidateSet('High', 'Medium', 'Low', 'Informational')]
        [string[]] $Severity,

        [ValidateRange(1, 3650)]
        [int] $Days,

        [SupportsWildcards()]
        [string[]] $Name,

        [ValidateRange(1, [int]::MaxValue)]
        [int[]] $Number,

        [SupportsWildcards()]
        [string[]] $Owner,

        [switch] $Unassigned,

        [ValidateSet('TruePositive', 'BenignPositive', 'FalsePositive', 'Undetermined')]
        [string[]] $Classification,

        [SupportsWildcards()]
        [string[]] $Tactic,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Microsoft Sentinel incidents',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    # A failure anywhere below ends as a Spectre.Console error panel and this
    # command's own terminating error, not a line inside the module. A stopped
    # pipeline (Select-Object -First, Ctrl+C) is no failure: just return - a
    # rethrow would stop the caller's whole script, not only this command.
    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Target) if ($Target) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Target) } }
    # Open incidents unless told otherwise; ones asked for by number, whatever their state.
    $states = @(if ($Status) { $Status } elseif (-not $Number) { 'New', 'Active' })
    # Closed incidents pile up: without -Days, read only the last 30 days of them.
    $lookBack = if ($Days) { $Days } elseif (-not $states.Count -or $states -contains 'Closed') { 30 } else { 0 }
    $filters = [System.Collections.Generic.List[string]]::new()
    if ($lookBack) { $filters.Add("properties/createdTimeUtc ge $([datetime]::UtcNow.AddDays(-$lookBack).ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture))") }
    if ($states.Count -and $states.Count -lt 3) { $filters.Add("($(@($states | ForEach-Object { "properties/status eq '$_'" }) -join ' or '))") }
    $incidentsPath = "providers/Microsoft.SecurityInsights/incidents?api-version=2025-09-01&`$top=1000&`$orderby=$([uri]::EscapeDataString('properties/createdTimeUtc desc'))"
    if ($filters.Count) { $incidentsPath += "&`$filter=$([uri]::EscapeDataString($filters -join ' and '))" }
    # The close times are only wanted when closed incidents are.
    $kqlDays = if ($lookBack) { $lookBack } else { 90 }
    $kql = [ordered]@{}
    if (-not $states.Count -or $states -contains 'Closed') {
        $kql['incidentTimes'] = (Get-AACSentinelAssessmentQuery -Section Incidents -Days $kqlDays)['incidentTimes']
    }
    $statusLabel = if ($states.Count) { ($states | ForEach-Object { $_.ToLowerInvariant() }) -join ', ' } else { 'every status' }
    $windowLabel = if ($lookBack) { "created in the last $lookBack day(s)" } else { 'any age' }
    # Read here, not inside the progress block (it runs in Invoke-AACProgress's scope).
    $request = @{ Target = $WorkspaceId.Trim(); SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ResourceGroupName = $ResourceGroupName; Path = $incidentsPath; Kql = $kql; Timespan = "P$($kqlDays)D" }

    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Microsoft Sentinel incidents' -Color 'red3' }
    $state = Invoke-AACProgress -ScriptBlock {
        $null = Get-AACAccessToken
        Update-AACProgress -Id 'read' -Indeterminate -Description "Reading the incidents of $($request.Target)"
        $read = Read-AACSentinelWorkspace -Target $request.Target -SubscriptionId $request.SubscriptionId -ResourceGroupName $request.ResourceGroupName -Arm ([ordered]@{ incidents = $request.Path }) -Kql $request.Kql -Timespan $request.Timespan
        $converted = ConvertTo-AACSentinelAssessment -Workspace $read.Workspace -Arm $read.Arm -Kql $read.Kql
        Update-AACProgress -Id 'read' -Complete -Description "Workspace $($read.Name): $(@($converted.Incidents).Count) incident(s) ($statusLabel)"
        @{ Read = $read; Converted = $converted }
    }
    $read = $state.Read
    # Without the list there's nothing to show, and an empty one would mislead.
    if ($read.Arm['incidents'].Error) {
        $problem = [System.InvalidOperationException]::new("Azure Admin Console couldn't read the incidents of $($read.Name): $($read.Arm['incidents'].Error)")
        $problem.Data['AACHint'] = 'Your account needs Microsoft Sentinel Reader on the workspace.'
        throw $problem
    }

    # --- The filters the API didn't apply ---------------------------------------------------------------------
    $incidents = @($state.Converted.Incidents)
    $matchesAny = { param([string[]] $Value, [string[]] $Pattern) foreach ($v in $Value) { foreach ($p in $Pattern) { if ($v -and $v -like $p) { return $true } } }; $false }
    if ($states.Count) { $incidents = @($incidents | Where-Object { $states -contains $_.Status }) }
    if ($Severity) { $incidents = @($incidents | Where-Object { $Severity -contains $_.Severity }) }
    if ($Name) { $incidents = @($incidents | Where-Object { & $matchesAny @($_.Title) $Name }) }
    if ($Number) { $incidents = @($incidents | Where-Object { $Number -contains [int]$_.Number }) }
    if ($Owner) { $incidents = @($incidents | Where-Object { & $matchesAny @($_.Owner) $Owner }) }
    if ($Unassigned) { $incidents = @($incidents | Where-Object { -not $_.Owner }) }
    if ($Classification) { $incidents = @($incidents | Where-Object { $Classification -contains $_.Classification }) }
    if ($Tactic) { $incidents = @($incidents | Where-Object { & $matchesAny @($_.Tactics -split ', ') $Tactic }) }
    # Open first, then newest.
    $incidents = @($incidents | Sort-Object -Property @{ Expression = { $_.Status -eq 'Closed' } }, @{ Expression = { $_.Created }; Descending = $true })

    # --- The report -------------------------------------------------------------------------------------------
    $severityTones = @{ High = 'bad'; Medium = 'warn'; Low = 'info'; Informational = 'neutral' }
    $statusTones = @{ New = 'bad'; Active = 'warn'; Closed = 'good' }
    $open = @($incidents | Where-Object Status -NE 'Closed')
    $closed = @($incidents | Where-Object Status -EQ 'Closed')
    $openHigh = @($open | Where-Object Severity -EQ 'High').Count
    $unowned = @($open | Where-Object { -not $_.Owner }).Count
    $oldestHours = [double](@($open | ForEach-Object { $_.HoursOpen } | Where-Object { $null -ne $_ } | Measure-Object -Maximum).Maximum)
    $closeTimes = @($closed | Where-Object { $null -ne $_.HoursToClose } | ForEach-Object HoursToClose | Sort-Object)
    $median = if ($closeTimes.Count) { $middle = [Math]::Floor($closeTimes.Count / 2); if ($closeTimes.Count % 2) { $closeTimes[$middle] } else { [Math]::Round(($closeTimes[$middle - 1] + $closeTimes[$middle]) / 2, 1) } }
    $falsePositives = @($closed | Where-Object Classification -EQ 'FalsePositive').Count
    $killChain = @('Reconnaissance', 'ResourceDevelopment', 'InitialAccess', 'Execution', 'Persistence', 'PrivilegeEscalation', 'DefenseEvasion', 'CredentialAccess', 'Discovery', 'LateralMovement', 'Collection', 'CommandAndControl', 'Exfiltration', 'Impact')
    $tactics = @($incidents | ForEach-Object { @($_.Tactics -split ', ' | Where-Object { $_ }) } | Group-Object | Sort-Object { $i = [array]::IndexOf($killChain, $_.Name); if ($i -lt 0) { 99 } else { $i } })
    $headline = if (-not $incidents.Count) { "No incidents ($statusLabel, $windowLabel) on $($read.Name)." }
    elseif ($open.Count) { "$($open.Count) open incident(s): $openHigh high, $unowned with no owner - the oldest has been open $([Math]::Round($oldestHours / 24, 1)) day(s)" }
    else { "$($closed.Count) closed incident(s)$(if ($null -ne $median) { ", median $median hour(s) to close" })." }
    $report = @{
        Subtitle = 'Microsoft Sentinel incidents: what was raised, who owns it, and how long it has waited'
        Facts    = [ordered]@{ Workspace = "$($read.Name) ($($read.ResourceGroup))"; Status = $statusLabel; Window = $windowLabel }
        Status   = $(if ($openHigh -or $unowned) { 'Failed' } elseif ($open.Count) { 'Warning' } else { 'Success' })
        Headline = $headline
        Tiles    = @(
            @{ Value = '{0:N0}' -f $open.Count; Label = 'open'; Tone = $(if ($open.Count) { 'warn' } else { 'good' }); Table = 'incidents' }
            @{ Value = '{0:N0}' -f $openHigh; Label = 'open high'; Tone = $(if ($openHigh) { 'bad' } else { 'good' }); Table = 'incidents'; Filters = @{ Severity = 'High' } }
            @{ Value = '{0:N0}' -f $unowned; Label = 'open, no owner'; Tone = $(if ($unowned) { 'bad' } else { 'good' }) }
            @{ Value = '{0:N0}' -f $closed.Count; Label = 'closed'; Tone = 'neutral'; Table = 'incidents'; Filters = @{ Status = 'Closed' } }
            @{ Value = $(if ($null -ne $median) { '{0:N1}' -f $median } else { '-' }); Label = 'median hours to close'; Tone = 'info' }
            @{ Value = $(if ($closed.Count) { '{0:N0}%' -f (100 * $falsePositives / $closed.Count) } else { '-' }); Label = 'false positives'; Tone = $(if ($closed.Count -and $falsePositives * 2 -ge $closed.Count) { 'warn' } else { 'info' }) }
        )
        Notices  = @(foreach ($key in $state.Converted.Errors.Keys) { @{ Status = 'Warning'; Text = "$key couldn't be read: $($state.Converted.Errors[$key])" } })
        Charts   = @(
            @{ Title = 'Incidents by severity'; Kind = 'donut'; CenterLabel = 'incidents'; Items = @(foreach ($s in 'High', 'Medium', 'Low', 'Informational') { $n = @($incidents | Where-Object Severity -EQ $s).Count; if ($n) { @{ Label = $s; Value = $n; Tone = $severityTones[$s]; Filter = $s } } }); Table = 'incidents'; Column = 'Severity' }
            @{ Title = 'Open incidents by owner'; Items = @($open | Group-Object { if ($_.Owner) { $_.Owner } else { '(no owner)' } } | Sort-Object Count -Descending | Select-AACFirst 10 | ForEach-Object { @{ Label = $_.Name; Value = $_.Count } }); Tone = 'warn'; Console = $true }
            @{ Title = 'By MITRE ATT&CK tactic'; Items = @($tactics | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'incidents'; Column = 'Tactics'; Tone = 'bad'; Console = $true }
            @{ Title = 'Incidents by day'; Items = @($incidents | Where-Object Created | Group-Object { $_.Created.ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture) } | Sort-Object Name | Select-Object -Last 30 | ForEach-Object { @{ Label = $_.Name; Value = $_.Count } }); Tone = 'info' }
            @{ Title = 'Closed by classification'; Kind = 'donut'; CenterLabel = 'closed'; Items = @($closed | Group-Object { if ($_.Classification) { $_.Classification } else { '(none)' } } | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'incidents'; Column = 'Classification' }
        )
        Tables   = @(
            @{ Id = 'incidents'; Title = 'Incidents'; Section = 'Incidents'; Rows = $incidents; Noun = 'incidents'; File = 'sentinel-incidents'; GroupBy = @('Severity', 'Status', 'Owner', 'Classification'); ConsoleLimit = 30
                Empty = "No incidents ($statusLabel, $windowLabel)."; EmptyStatus = 'Success'; Hover = @('Description'); HoverTitle = 'Title'
                Columns = @(
                    @{ Key = 'Number'; Label = '#'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $severityTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = $statusTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Title'; Label = 'Title'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'Owner'; Label = 'Owner'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'HoursOpen'; Label = 'Hours open'; Type = 'number'; Console = $true }
                    @{ Key = 'Created'; Label = 'Created'; Type = 'datetime'; Pdf = $true }
                    @{ Key = 'Classification'; Label = 'Classification'; Facet = $true; Pdf = $true }
                    @{ Key = 'HoursToClose'; Label = 'Hours to close'; Type = 'number' }
                    @{ Key = 'Alerts'; Label = 'Alerts'; Type = 'number' }
                    @{ Key = 'Tactics'; Label = 'Tactics'; Facet = $true }
                    @{ Key = 'Techniques'; Label = 'Techniques'; Type = 'mono' }
                    @{ Key = 'Products'; Label = 'Products'; Facet = $true }
                    @{ Key = 'Labels'; Label = 'Labels'; Facet = $true }
                    @{ Key = 'ClassificationReason'; Label = 'Reason'; Hidden = $true }
                    @{ Key = 'LastModified'; Label = 'Last modified'; Type = 'datetime'; Hidden = $true }
                    @{ Key = 'Closed'; Label = 'Closed'; Type = 'datetime'; Hidden = $true }
                    @{ Key = 'Description'; Label = 'Description'; Type = 'wide'; Hidden = $true }
                    @{ Key = 'Url'; Label = 'Portal'; Type = 'link'; Text = 'Open' }
                ) }
        )
        Hint     = '-Status Closed -Days 90 for closed ones; -Severity, -Owner, -Unassigned and -Tactic narrow the list; Get-AACSentinelAlert -IncidentNumber for the alerts in one.'
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $incidents -Noun 'incident' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $incidents -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
