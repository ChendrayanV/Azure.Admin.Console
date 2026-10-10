function Get-AACAttackPath {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Maps the attack paths through your Azure estate - from what the
        Internet can reach, through the identities it runs as, to what an
        attacker could then control or read - with each path's risk, blast
        radius and the fix, most dangerous first.
    .DESCRIPTION
        Reads the estate in one Azure Resource Graph batch and builds the
        paths an attacker with a foothold would take:

          Internet > vm-web-01 (public IP: RDP 3389) > system-assigned identity
                   > Contributor on subscription sub-prod  (412 resources)

        Entry points: VMs whose public IP the NSGs (NIC and subnet, rule by
        rule in priority order) open to the Internet - management, database
        or any port; App Service and Function apps open to the public; AKS
        clusters with a public API server and no authorized IP ranges; and
        data stores (storage, key vaults, SQL, Cosmos DB, PostgreSQL, MySQL)
        open to every network.

        From each entry: its managed identities and their role assignments
        (read tenant-wide, so management group roles count) - control roles
        (Owner, Contributor, User Access Administrator, RBAC Administrator,
        custom roles with '*' or Microsoft.Authorization writes) and data
        access (data roles, key vault access policies). The blast radius is
        what that reaches: every resource under a controlled scope, the data
        stores readable, and a VM's neighbours in its virtual network.

        Risk: Critical - an open entry whose identity controls a
        subscription, management group or the tenant; High - control of a
        resource group, data access, an open management port, anonymous
        storage; Medium - other open ports, open data stores, a public API
        server; Low - storage that accepts every network. Each path says what
        to do and how much effort it is, so quick wins come first.

        With Defender CSPM, Defender for Cloud's own attack paths are added
        (Source 'Defender for Cloud'); without it, a notice says so.

        What it doesn't see: network routes through firewalls or NVAs,
        application-level flaws, and identities outside Azure RBAC. It shows
        where to look first, not proof of compromise. Read-only; Reader is
        enough.
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups (at any depth).
    .PARAMETER ResourceGroupName
        Only paths that start in these resource groups.
    .PARAMETER Severity
        Only paths of these risks (Critical, High, Medium, Low).
    .PARAMETER CsvPath
        Write the paths to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report.
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the paths.
    .PARAMETER NoDisplay
        Return the paths without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Get-AACAttackPath
        Every attack path in the subscriptions you can see, most dangerous first.
    .EXAMPLE
        Get-AACAttackPath -SubscriptionId $prod -Severity Critical, High -HtmlPath .\out\AttackPaths.html
        The critical and high paths in production, as an HTML report.
    .EXAMPLE
        Get-AACAttackPath -NoDisplay | Where-Object Category -EQ 'Internet to subscription control' | Select-Object Resource, Path, BlastRadius
        The footholds that lead to a whole subscription.
    .OUTPUTS
        AAC.AttackPath
    #>
    [CmdletBinding()]
    [OutputType('AAC.AttackPath')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string[]] $ManagementGroupId,

        [string[]] $ResourceGroupName,

        [ValidateSet('Critical', 'High', 'Medium', 'Low')]
        [string[]] $Severity,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Azure attack paths',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $request = @{ SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }) }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Attack paths' -Color 'deepskyblue3_1' }
    $state = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
        $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
        Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"
        $queries = Get-AACAttackPathQuery
        Update-AACProgress -Id 'read' -Total $queries.Count -Description 'Reading the exposure, identities, roles and data stores'
        $read = Invoke-AACGraphBatch -Query $queries -SubscriptionId $scope.GraphScope -AllowFailure @('defender', 'clusters', 'apps', 'identities', 'roleDefinitions', 'stores') -OnProgress {
            param($Name, $Done, $Total)
            Update-AACProgress -Id 'read' -Increment 1 -Description "Read the $Name ($Done of $Total)"
        }
        Update-AACProgress -Id 'read' -Complete -Description ('Read {0:N0} VM(s), {1:N0} public IP(s), {2:N0} NSG(s), {3:N0} role assignment(s)' -f @($read.Rows['vms']).Count, @($read.Rows['publicIps']).Count, @($read.Rows['nsgs']).Count, @($read.Rows['roleAssignments']).Count)
        Update-AACProgress -Id 'paths' -Indeterminate -Description 'Building the attack paths'
        $chain = @{}
        foreach ($s in $scope.Subscriptions) { $chain[([string]$s['subscriptionId']).ToLowerInvariant()] = @(@($s['chain']) | Where-Object { $_ -is [System.Collections.IDictionary] } | ForEach-Object { ([string]$_['name']).ToLowerInvariant() }) }
        $result = ConvertTo-AACAttackPath -Read $read -SubscriptionName $scope.Names -SubscriptionChain $chain
        Update-AACProgress -Id 'paths' -Complete -Description ('{0:N0} attack path(s): {1:N0} critical, {2:N0} high' -f $result.Stats.Paths, $result.Stats.Critical, $result.Stats.High)
        @{ Result = $result; Scope = $scope }
    }

    $result = $state.Result
    $paths = @($result.Paths)
    if ($ResourceGroupName) { $groups = @($ResourceGroupName | ForEach-Object { $_.ToLowerInvariant() }); $paths = @($paths | Where-Object { $groups -contains ([string]$_.ResourceGroup).ToLowerInvariant() }) }
    if ($Severity) { $paths = @($paths | Where-Object { $Severity -contains $_.Severity }) }
    $rank = Get-AACSeverityRank
    $critical = @($paths | Where-Object Severity -EQ 'Critical').Count
    $high = @($paths | Where-Object Severity -EQ 'High').Count
    $categoryTones = @{ 'Internet to subscription control' = 'bad'; 'Internet to resource group control' = 'bad'; 'Internet to data' = 'warn'; 'Management port open to the Internet' = 'warn'; 'Port open to the Internet' = 'info'; 'Data store open to the Internet' = 'warn'; 'Public API server' = 'info'; 'Defender for Cloud attack path' = 'violet' }
    $report = @{
        Subtitle = 'Attack paths: from the Internet, through identities, to control and data'
        Facts    = [ordered]@{ Scope = $state.Scope.Label; Sources = $(if ($result.Stats.Defender) { 'Defender for Cloud and the estate' } else { 'the estate (Resource Graph)' }) }
        Status   = $(if ($critical -or $high) { 'Failed' } elseif ($paths.Count) { 'Warning' } else { 'Success' })
        Headline = $(if ($paths.Count) { "$($paths.Count) attack path(s): $critical critical, $high high - the largest blast radius is $($result.Stats.MaxRadius) resource(s)" } else { 'No attack paths: nothing in scope is open to the Internet with access beyond itself.' })
        Tiles    = @(
            @{ Value = '{0:N0}' -f $critical; Label = 'critical paths'; Tone = $(if ($critical) { 'bad' } else { 'good' }); Table = 'paths'; Filters = @{ Severity = 'Critical' } }
            @{ Value = '{0:N0}' -f $high; Label = 'high'; Tone = $(if ($high) { 'bad' } else { 'good' }); Table = 'paths'; Filters = @{ Severity = 'High' } }
            @{ Value = '{0:N0}' -f $result.Stats.ExposedVms; Label = 'VMs open to the Internet'; Tone = $(if ($result.Stats.ExposedVms) { 'warn' } else { 'good' }) }
            @{ Value = '{0:N0}' -f $result.Stats.Management; Label = 'with management ports open'; Tone = $(if ($result.Stats.Management) { 'bad' } else { 'good' }) }
            @{ Value = '{0:N0}' -f $result.Stats.ExposedData; Label = 'data stores open'; Tone = $(if ($result.Stats.ExposedData) { 'warn' } else { 'good' }); Table = 'paths'; Filters = @{ Category = 'Data store open to the Internet' } }
            @{ Value = '{0:N0}' -f $result.Stats.MaxRadius; Label = 'largest blast radius'; Tone = 'violet' }
        )
        Notices  = @($result.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
        Charts   = @(
            @{ Title = 'Paths by risk'; Kind = 'donut'; CenterLabel = 'paths'; Items = @(foreach ($s in 'Critical', 'High', 'Medium', 'Low') { $n = @($paths | Where-Object Severity -EQ $s).Count; if ($n) { @{ Label = $s; Value = $n; Tone = $rank.Tone[$s]; Filter = $s } } }); Table = 'paths'; Column = 'Severity' }
            @{ Title = 'Paths by kind'; Items = @($paths | Group-Object Category | Sort-Object Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'paths'; Column = 'Category'; Tone = 'warn'; Console = $true }
            @{ Title = 'Largest blast radius'; Items = @($paths | Sort-Object BlastRadius -Descending | Select-Object -First 10 | ForEach-Object { @{ Label = $_.Resource; Value = $_.BlastRadius; Filter = $_.Resource } }); Table = 'paths'; Column = 'Resource'; Tone = 'violet' }
        )
        Tables   = @(
            @{ Id = 'paths'; Title = 'Attack paths'; Section = 'Attack paths'; Rows = $paths; Noun = 'paths'; GroupBy = @('Severity', 'Category', 'Subscription', 'Source'); ConsoleLimit = 20
                Empty = 'No attack paths: nothing in scope is open to the Internet with access beyond itself.'
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Risk'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Category'; Label = 'Kind'; Type = 'badge'; Tones = $categoryTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Resource'; Label = 'Entry point'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Path'; Label = 'Path'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'BlastRadius'; Label = 'Blast radius'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'Effort'; Label = 'Effort'; Type = 'badge'; Tones = @{ Low = 'good'; Medium = 'warn'; High = 'bad' }; Facet = $true; Console = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                    @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                    @{ Key = 'Exposure'; Label = 'Exposure'; Type = 'wide' }
                    @{ Key = 'Targets'; Label = 'What it reaches'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Impact'; Label = 'Impact'; Type = 'wide' }
                    @{ Key = 'Remediation'; Label = 'What to do'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Source'; Label = 'Source'; Facet = $true }
                    @{ Key = 'Link'; Label = 'Docs'; Type = 'link'; Text = 'Docs' }
                ) }
        )
        Hint     = '-Severity Critical, High narrows the list; -NoDisplay returns the paths; -HtmlPath, -PdfPath or -CsvPath for a report.'
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $paths -Noun 'path' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $paths -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
