function Get-AACPrivateEndpoint {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Audits your private endpoints - each connection's state, the
        resource behind it, its IP addresses and names, the private DNS zone
        that resolves it and whether its network can see that zone - and
        finds what breaks private connectivity: pending or disconnected
        connections, orphaned endpoints, missing or unlinked DNS zones, and
        targets still open to the Internet.
    .DESCRIPTION
        Reads, read-only:
          Resource Graph     the private endpoints and their connections
                             (automatic and manual approval), the private
                             DNS zones and their virtual network links, the
                             virtual networks (DNS servers, peerings) and
                             every resource that takes private endpoint
                             connections (does it exist, is it still public?)
          Resource Manager   each endpoint's private DNS zone groups (which
                             zone holds its record)

        One row per endpoint connection (AAC.PrivateEndpoint), Healthy,
        Review, Warning or Failed, with its issues; and the findings
        (AAC.PrivateEndpointFinding), each with what to do:
          a connection Pending, Rejected or Disconnected; an endpoint whose
          target was deleted; provisioning failed; the zone not linked to
          the endpoint's network or one peered with it; no zone group; the
          wrong zone for the service (blob in the file zone, say); the
          target still open to public networks; the same privatelink zone
          defined in several places.

        The zone each service needs is known for storage, Key Vault, SQL,
        Cosmos DB, PostgreSQL, MySQL, Container Registry, App Service,
        Service Bus and Event Hubs, App Configuration, AI Search, Redis,
        Azure AI services, Data Factory, Event Grid, SignalR, Automation,
        Azure Monitor and more. A network with custom DNS servers can't be
        checked from Azure alone: it is flagged for review.

        Read-only; Reader is enough.
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups (at any depth).
    .PARAMETER ResourceGroupName
        Only endpoints in these resource groups (their zones, networks and
        targets can be anywhere).
    .PARAMETER Name
        Only endpoints whose name matches; wildcards work.
    .PARAMETER TargetType
        Only endpoints to resources of these types (for example
        'microsoft.storage/storageaccounts', or '*sql*'); wildcards work.
    .PARAMETER Status
        Only connections in these states (Failed, Warning, Review, Healthy).
    .PARAMETER SkipDnsZoneGroup
        Don't read the DNS zone groups (one call per endpoint): faster, but
        DNS isn't checked.
    .PARAMETER CsvPath
        Write the endpoint connections to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report.
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the endpoint connections.
    .PARAMETER NoDisplay
        Return the endpoint connections without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Get-AACPrivateEndpoint
        Every private endpoint you can see, the broken ones first, and the findings.
    .EXAMPLE
        Get-AACPrivateEndpoint -Status Failed, Warning -HtmlPath .\out\PrivateEndpoints.html
        What needs fixing, as an interactive HTML report.
    .EXAMPLE
        Get-AACPrivateEndpoint -TargetType 'microsoft.storage/storageaccounts' -NoDisplay | Select-Object Endpoint, Target, GroupId, IpAddresses, DnsZones, ZoneLinked
        The storage endpoints, their IPs and DNS.
    .OUTPUTS
        AAC.PrivateEndpoint
    #>
    [CmdletBinding()]
    [OutputType('AAC.PrivateEndpoint')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string[]] $ManagementGroupId,

        [string[]] $ResourceGroupName,

        [SupportsWildcards()]
        [string[]] $Name,

        [SupportsWildcards()]
        [string[]] $TargetType,

        [ValidateSet('Failed', 'Warning', 'Review', 'Healthy')]
        [string[]] $Status,

        [switch] $SkipDnsZoneGroup,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Azure private endpoints',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $request = @{ SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }); ResourceGroupName = @($ResourceGroupName | Where-Object { $_ }); Name = @($Name | Where-Object { $_ }); SkipDnsZoneGroup = [bool]$SkipDnsZoneGroup }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Private endpoints' -Color 'mediumpurple' }
    $outcome = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
        $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
        Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"
        $queries = Get-AACPrivateEndpointQuery -ResourceGroupName $request.ResourceGroupName
        Update-AACProgress -Id 'read' -Total $queries.Count -Description 'Reading private endpoints, DNS zones, networks and targets'
        $read = Invoke-AACGraphBatch -Query $queries -SubscriptionId $scope.GraphScope -AllowFailure @('zones', 'links', 'vnets', 'targets') -OnProgress {
            param($QueryName, $Done, $Total)
            Update-AACProgress -Id 'read' -Increment 1 -Description "Read the $QueryName ($Done of $Total)"
        }
        if ($request.Name.Count) { $read.Rows['endpoints'] = @($read.Rows['endpoints'] | Where-Object { $n = [string]$_['name']; @($request.Name | Where-Object { $n -like $_ }).Count }) }
        $endpointRows = @($read.Rows['endpoints'] | Where-Object { $_ -and $scope.Names.Contains(([string]$_['subscriptionId']).ToLowerInvariant()) })
        Update-AACProgress -Id 'read' -Complete -Description ('Read {0:N0} private endpoint(s), {1:N0} private DNS zone(s)' -f $endpointRows.Count, @($read.Rows['zones']).Count)

        $zoneGroups = @{}
        if (-not $request.SkipDnsZoneGroup -and $endpointRows.Count) {
            $uris = [ordered]@{}
            foreach ($row in $endpointRows) { $uris[[string]$row['id']] = "$($row['id'])/privateDnsZoneGroups?api-version=2023-09-01" }
            Update-AACProgress -Id 'zones' -Total $uris.Count -Description "Reading the DNS zone groups of $($uris.Count) endpoint(s)"
            $answers = Invoke-AACArmParallel -Uri @($uris.Values) -OnProgress { param($ZoneDone, $ZoneTotal) Update-AACProgress -Id 'zones' -Increment 1 }
            foreach ($id in $uris.Keys) {
                $answer = $answers[$uris[$id]]
                # Assigned in each branch: an empty list out of an if expression would become $null (unread).
                if (-not $answer -or $answer.Error) { $zoneGroups[$id] = $null } else { $zoneGroups[$id] = @($answer.Items | Where-Object { $_ }) }
            }
            Update-AACProgress -Id 'zones' -Complete -Description ('Read the DNS zone groups of {0:N0} endpoint(s)' -f @($zoneGroups.Values | Where-Object { $null -ne $_ }).Count)
        }
        $result = ConvertTo-AACPrivateEndpoint -Read $read -ZoneGroup $zoneGroups -SubscriptionName $scope.Names
        @{ Result = $result; Scope = $scope }
    }

    $endpoints = @($outcome.Result.Endpoints)
    $findings = @($outcome.Result.Findings)
    if ($TargetType) {
        $endpoints = @($endpoints | Where-Object { $t = $_.TargetType; @($TargetType | Where-Object { $t -like $_ }).Count })
        $keep = @{}; foreach ($e in $endpoints) { $keep[$e.ResourceId] = $true }
        $findings = @($findings | Where-Object { $keep.Contains($_.ResourceId) })
    }
    if ($Status) { $endpoints = @($endpoints | Where-Object { $Status -contains $_.Status }) }

    $rank = Get-AACSeverityRank
    $statusTones = @{ Healthy = 'good'; Review = 'info'; Warning = 'warn'; Failed = 'bad' }
    $failed = @($endpoints | Where-Object Status -EQ 'Failed').Count
    $warning = @($endpoints | Where-Object Status -EQ 'Warning').Count
    $healthy = @($endpoints | Where-Object Status -EQ 'Healthy').Count
    $pending = @($endpoints | Where-Object ConnectionState -EQ 'Pending').Count
    $dns = @($findings | Where-Object Category -EQ 'DNS').Count
    $public = @($endpoints | Where-Object { $_.Issues -match 'target public' }).Count
    $report = @{
        Subtitle = 'Private endpoints: connections, DNS and exposure'
        Facts    = [ordered]@{ Scope = $outcome.Scope.Label; 'DNS zone groups' = $(if ($SkipDnsZoneGroup) { 'not read (-SkipDnsZoneGroup)' } else { 'read' }) }
        Status   = $(if ($failed) { 'Failed' } elseif ($warning) { 'Warning' } else { 'Success' })
        Headline = $(if ($endpoints.Count) { "$($endpoints.Count) private endpoint connection(s): $failed failed, $warning with warnings, $healthy healthy" } else { 'No private endpoints in scope.' })
        Tiles    = @(
            @{ Value = '{0:N0}' -f $endpoints.Count; Label = 'endpoint connections'; Tone = 'info' }
            @{ Value = '{0:N0}' -f $failed; Label = 'failed'; Tone = $(if ($failed) { 'bad' } else { 'good' }); Table = 'endpoints'; Filters = @{ Status = 'Failed' } }
            @{ Value = '{0:N0}' -f $warning; Label = 'warnings'; Tone = $(if ($warning) { 'warn' } else { 'good' }); Table = 'endpoints'; Filters = @{ Status = 'Warning' } }
            @{ Value = '{0:N0}' -f $pending; Label = 'pending approval'; Tone = $(if ($pending) { 'bad' } else { 'good' }); Table = 'endpoints'; Filters = @{ ConnectionState = 'Pending' } }
            @{ Value = '{0:N0}' -f $dns; Label = 'DNS findings'; Tone = $(if ($dns) { 'warn' } else { 'good' }); Table = 'findings'; Filters = @{ Category = 'DNS' } }
            @{ Value = '{0:N0}' -f $public; Label = 'targets still public'; Tone = $(if ($public) { 'warn' } else { 'good' }) }
        )
        Notices  = @($outcome.Result.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
        Charts   = @(
            @{ Title = 'By status'; Kind = 'donut'; CenterLabel = 'connections'; Items = @(foreach ($s in 'Failed', 'Warning', 'Review', 'Healthy') { $n = @($endpoints | Where-Object Status -EQ $s).Count; if ($n) { @{ Label = $s; Value = $n; Tone = $statusTones[$s]; Filter = $s } } }); Table = 'endpoints'; Column = 'Status' }
            @{ Title = 'Findings by kind'; Items = @($findings | Group-Object Finding | Sort-Object Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'findings'; Column = 'Finding'; Tone = 'warn'; Console = $true }
            @{ Title = 'By target type'; Items = @($endpoints | Group-Object TargetType | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'endpoints'; Column = 'TargetType'; Tone = 'violet' }
        )
        Tables   = @(
            @{ Id = 'findings'; Title = 'Findings'; Section = 'Findings'; Rows = $findings; Noun = 'findings'; GroupBy = @('Severity', 'Category', 'Subscription'); ConsoleLimit = 20
                Empty = 'No findings: every private endpoint is connected, resolvable and its target closed to public networks.'; EmptyStatus = 'Success'
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Finding'; Label = 'Finding'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Resource'; Label = 'Endpoint'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'Category'; Label = 'Area'; Facet = $true }
                    @{ Key = 'Impact'; Label = 'Impact'; Type = 'wide' }
                    @{ Key = 'Remediation'; Label = 'What to do'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                    @{ Key = 'Link'; Label = 'Docs'; Type = 'link'; Text = 'Docs' }
                ) }
            @{ Id = 'endpoints'; Title = 'Private endpoint connections'; Section = 'Endpoints'; Rows = $endpoints; Noun = 'connections'; GroupBy = @('Status', 'TargetType', 'VirtualNetwork', 'Subscription'); ConsoleLimit = 25
                Empty = 'No private endpoints in scope.'
                Columns = @(
                    @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = $statusTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Endpoint'; Label = 'Endpoint'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Target'; Label = 'Target'; IdKey = 'TargetId'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'GroupId'; Label = 'Sub-resource'; Facet = $true; Console = $true }
                    @{ Key = 'ConnectionState'; Label = 'Connection'; Type = 'badge'; Tones = @{ Approved = 'good'; Pending = 'bad'; Rejected = 'bad'; Disconnected = 'bad' }; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'ZoneLinked'; Label = 'DNS'; Type = 'badge'; Tones = @{ Yes = 'good'; 'Peered network' = 'good'; 'Custom DNS' = 'info'; No = 'bad'; 'No zone group' = 'warn'; 'Not checked' = 'neutral' }; Facet = $true; Console = $true }
                    @{ Key = 'IpAddresses'; Label = 'IP'; Type = 'mono'; Console = $true }
                    @{ Key = 'Issues'; Label = 'Issues'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'TargetType'; Label = 'Target type'; Type = 'type'; Facet = $true }
                    @{ Key = 'DnsZones'; Label = 'DNS zone'; Type = 'mono' }
                    @{ Key = 'ExpectedZone'; Label = 'Expected zone'; Type = 'mono' }
                    @{ Key = 'Fqdns'; Label = 'Names'; Type = 'wide' }
                    @{ Key = 'VirtualNetwork'; Label = 'Network'; Facet = $true }
                    @{ Key = 'Subnet'; Label = 'Subnet' }
                    @{ Key = 'TargetPublicAccess'; Label = 'Target public access'; Facet = $true }
                    @{ Key = 'Approval'; Label = 'Approval'; Facet = $true }
                    @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                ) }
        )
        Hint     = '-Status Failed, Warning narrows the list; -TargetType picks a service; -NoDisplay returns the connections; -HtmlPath, -PdfPath or -CsvPath for a report.'
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $endpoints -Noun 'connection' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $endpoints -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
