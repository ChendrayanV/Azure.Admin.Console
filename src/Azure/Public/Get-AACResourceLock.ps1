function Get-AACResourceLock {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Lists every resource lock - on subscriptions, resource groups and
        resources - and the critical resources no lock protects, with
        ReadOnly locks that break more than they protect flagged.
    .DESCRIPTION
        Reads, read-only: each subscription's locks (Resource Manager - a
        subscription's list includes those on its resource groups and
        resources), and from Resource Graph its resource groups and the
        resources of the critical types.

        Rows (AAC.ResourceLock):
          Locked    each lock: level (CanNotDelete or ReadOnly), scope,
                    notes. ReadOnly is a finding - Medium on a subscription
                    or resource group, where it also blocks listing keys,
                    scaling and many portal pages; Low on a resource
          Unlocked  each critical resource with no lock on it, its
                    resource group or its subscription (Low)
        A lock covers its scope and everything below it. The headline says
        how many critical resources are locked directly, through a parent,
        or not at all, and how many resource groups a lock covers.

        The critical types (-CriticalType to choose your own): key vaults,
        storage accounts, SQL servers, Cosmos DB, PostgreSQL and MySQL
        flexible servers, Recovery Services and backup vaults, virtual
        networks, ExpressRoute circuits, Azure Firewalls, public and private
        DNS zones, Log Analytics workspaces. Reader is enough.
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups (at any depth).
    .PARAMETER CriticalType
        The resource types that should be locked (Resource Graph type names,
        such as 'microsoft.keyvault/vaults'), instead of the default list.
    .PARAMETER Status
        Only these: Locked, Unlocked.
    .PARAMETER CsvPath
        Write the locks to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report.
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the rows.
    .PARAMETER NoDisplay
        Return the rows without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Get-AACResourceLock
        Every lock, and the critical resources left unlocked.
    .EXAMPLE
        Get-AACResourceLock -Status Unlocked -NoDisplay | Select-Object Scope, ResourceType
        The critical resources nothing protects from deletion.
    .EXAMPLE
        Get-AACResourceLock -CriticalType 'microsoft.keyvault/vaults', 'microsoft.recoveryservices/vaults' -HtmlPath .\Locks.html
        Locks, judged against your own list of critical types.
    .OUTPUTS
        AAC.ResourceLock
    #>
    [CmdletBinding()]
    [OutputType('AAC.ResourceLock')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string[]] $ManagementGroupId,

        [ValidatePattern('^[A-Za-z0-9.]+/[A-Za-z0-9/]+$')]
        [string[]] $CriticalType = @('microsoft.keyvault/vaults', 'microsoft.storage/storageaccounts', 'microsoft.sql/servers', 'microsoft.documentdb/databaseaccounts', 'microsoft.dbforpostgresql/flexibleservers', 'microsoft.dbformysql/flexibleservers', 'microsoft.recoveryservices/vaults', 'microsoft.dataprotection/backupvaults', 'microsoft.network/virtualnetworks', 'microsoft.network/expressroutecircuits', 'microsoft.network/azurefirewalls', 'microsoft.network/dnszones', 'microsoft.network/privatednszones', 'microsoft.operationalinsights/workspaces'),

        [ValidateSet('Locked', 'Unlocked')]
        [string[]] $Status,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Resource locks',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $request = @{ SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }); CriticalType = @($CriticalType | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique) }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Resource locks' -Color 'orange1' }
    $outcome = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
        $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
        Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"

        $types = ($request.CriticalType | ForEach-Object { "'$_'" }) -join ', '
        Update-AACProgress -Id 'inventory' -Indeterminate -Description 'Reading the resource groups and critical resources'
        $inventory = Invoke-AACGraphBatch -Query ([ordered]@{
                groups    = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions/resourcegroups' | project id = tolower(id), name, subscriptionId = tolower(subscriptionId)"
                resources = "resources | where type in~ ($types) | project id = tolower(id), name, type = tolower(type), resourceGroup, subscriptionId = tolower(subscriptionId)"
            }) -SubscriptionId $scope.GraphScope
        Update-AACProgress -Id 'inventory' -Complete -Description ('Read {0:N0} resource group(s) and {1:N0} critical resource(s)' -f @($inventory.Rows['groups']).Count, @($inventory.Rows['resources']).Count)

        $uris = [ordered]@{}
        foreach ($id in $scope.Ids) { $uris[$id] = "/subscriptions/$id/providers/Microsoft.Authorization/locks?api-version=2016-09-01" }
        Update-AACProgress -Id 'locks' -Total ([Math]::Max(1, $uris.Count)) -Description "Reading the locks of $($scope.Ids.Count) subscription(s)"
        $answers = Invoke-AACArmParallel -Uri @($uris.Values) -OnProgress { param($LockDone, $LockTotal) Update-AACProgress -Id 'locks' -Increment 1 }
        $locks = [System.Collections.Generic.List[object]]::new()
        $unread = [System.Collections.Generic.List[string]]::new()
        foreach ($id in $uris.Keys) {
            $answer = $answers[$uris[$id]]
            if (-not $answer -or $answer.Error) { $unread.Add("$($scope.Names[$id.ToLowerInvariant()]) ($(if ($answer) { $answer.Error } else { 'no answer' }))"); continue }
            foreach ($l in @($answer.Items | Where-Object { $null -ne $_ })) { $locks.Add($l) }
        }
        Update-AACProgress -Id 'locks' -Complete -Description ('Read {0:N0} lock(s)' -f $locks.Count)
        $result = ConvertTo-AACResourceLock -Lock $locks.ToArray() -ResourceGroup @($inventory.Rows['groups'] | Where-Object { $_ }) -Resource @($inventory.Rows['resources'] | Where-Object { $_ }) -SubscriptionName $scope.Names -Unread $unread.ToArray()
        @{ Result = $result; Scope = $scope }
    }

    $rows = @($outcome.Result.Locks)
    if ($Status) { $rows = @($rows | Where-Object { $Status -contains $_.Status }) }
    $s = $outcome.Result.Stats
    $rank = Get-AACSeverityRank
    $statusTones = @{ Locked = 'good'; Unlocked = 'warn' }
    $report = @{
        Subtitle = 'Resource locks: every lock, and the critical resources no lock protects'
        Facts    = [ordered]@{ Scope = $outcome.Scope.Label; 'Critical types' = "$($request.CriticalType.Count)" }
        Status   = $(if ($s.Unlocked -or @($rows | Where-Object Severity -EQ 'Medium').Count) { 'Warning' } else { 'Success' })
        Headline = "$($s.Locks) lock(s) ($($s.ReadOnly) ReadOnly); of $($s.Critical) critical resource(s), $($s.Direct) locked directly, $($s.Inherited) through a parent, $($s.Unlocked) unlocked; $($s.GroupsCovered) of $($s.Groups) resource group(s) covered"
        Tiles    = @(
            @{ Value = '{0:N0}' -f $s.Locks; Label = 'locks'; Tone = 'info'; Table = 'locks'; Filters = @{ Status = 'Locked' } }
            @{ Value = '{0:N0}' -f $s.Unlocked; Label = 'critical, unlocked'; Tone = $(if ($s.Unlocked) { 'warn' } else { 'good' }); Table = 'locks'; Filters = @{ Status = 'Unlocked' } }
            @{ Value = '{0:N0}' -f $s.ReadOnly; Label = 'ReadOnly locks'; Tone = $(if ($s.ReadOnly) { 'warn' } else { 'good' }) }
            @{ Value = $(if ($s.Groups) { '{0:N0}%' -f (100 * $s.GroupsCovered / $s.Groups) } else { '-' }); Label = 'resource groups covered'; Tone = 'info' }
        )
        Notices  = @($outcome.Result.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
        Charts   = @(
            @{ Title = 'Critical resources'; Kind = 'donut'; CenterLabel = 'resources'; Items = @(@{ Label = 'Locked directly'; Value = $s.Direct; Tone = 'good' }, @{ Label = 'Through a parent'; Value = $s.Inherited; Tone = 'info' }, @{ Label = 'Unlocked'; Value = $s.Unlocked; Tone = 'warn' } | Where-Object { $_.Value }); Console = $true }
            @{ Title = 'Unlocked, by type'; Items = @($rows | Where-Object Status -EQ 'Unlocked' | Group-Object ResourceType | Sort-Object Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'locks'; Column = 'ResourceType'; Tone = 'warn' }
        )
        Tables   = @(
            @{ Id = 'locks'; Title = 'Locks and unlocked critical resources'; Section = 'Locks'; Rows = $rows; Noun = 'rows'; GroupBy = @('Status', 'ScopeType'); ConsoleLimit = 30
                Empty = 'No locks, and no critical resources.'; EmptyStatus = 'Info'
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = $statusTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Level'; Label = 'Level'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'ScopeType'; Label = 'Scope type'; Facet = $true; Console = $true }
                    @{ Key = 'Scope'; Label = 'Scope'; Console = $true; Pdf = $true }
                    @{ Key = 'ResourceType'; Label = 'Type'; Facet = $true; Console = $true }
                    @{ Key = 'Lock'; Label = 'Lock'; Console = $true }
                    @{ Key = 'Findings'; Label = 'Findings'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Notes'; Label = 'Notes'; Type = 'wide' }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                    @{ Key = 'ScopeId'; Label = 'Scope ID'; Type = 'mono' }
                ) }
        )
        Hint     = '-Status Unlocked shows what nothing protects; -CriticalType sets the types to check; -NoDisplay returns the rows; -HtmlPath, -PdfPath or -CsvPath for a report.'
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $rows -Noun 'row' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $rows -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
