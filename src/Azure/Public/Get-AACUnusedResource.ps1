function Get-AACUnusedResource {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Finds the Azure resources nobody uses - unattached disks, NICs and
        public IPs, empty App Service plans, pools and gateways, stopped VMs
        still billed, old snapshots, empty resource groups and more - with
        whether each is still billed, since when, and what to do.
    .DESCRIPTION
        Reads the estate in one Azure Resource Graph batch and lists what is
        attached to nothing, serves nothing or is switched off:

          Unattached disk                  managed disks on no VM (since when)
          Unattached network interface     NICs on no VM or private endpoint
          Unassociated public IP           public IPs on nothing
          Unassociated NSG / route table   on no subnet or NIC
          Unused NAT gateway               on no subnet
          Load balancer / Application      every backend pool empty (or a
          Gateway with no backends         gateway stopped)
          Empty App Service plan           no apps on it
          Empty SQL elastic pool           no databases in it
          Stopped VM still billed          stopped from the OS, not
                                           deallocated
          Deallocated VM                   only its disks are billed
          Old snapshot                     older than -SnapshotDays (90)
          Unlinked private DNS zone        linked to no network
          Empty availability set, Traffic Manager profile, unused IP group,
          DDoS protection plan or WAF policy, expired certificate, empty
          resource group

        Each (AAC.UnusedResource) has a severity - High for what is billed
        heavily while doing nothing, Medium for what is billed by the hour or
        GB, Low for clutter - Billed (Yes, Partly, No), Since and AgeDays
        where Azure records it, and the fix. -IncludeCost adds each one's
        cost last month (Cost Management), and the total that deleting them
        would save.

        This is about configuration - what is attached to nothing. For
        resources that run but are idle (CPU, memory, requests), use
        Get-AACResourceUtilization. Read-only; Reader is enough (and Cost
        Management Reader for -IncludeCost).
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups (at any depth).
    .PARAMETER ResourceGroupName
        Only these resource groups.
    .PARAMETER ResourceType
        Only resources of these types (for example
        'microsoft.compute/disks', or '*network*'); wildcards work.
    .PARAMETER Category
        Only these kinds of finding (for example 'Unattached disk', or
        '*VM*'); wildcards work.
    .PARAMETER Severity
        Only these severities (High, Medium, Low).
    .PARAMETER SnapshotDays
        Snapshots older than this many days are listed. Default 90.
    .PARAMETER IncludeCost
        Read each resource's cost last month from Cost Management.
    .PARAMETER CsvPath
        Write the resources to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report.
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the resources.
    .PARAMETER NoDisplay
        Return the resources without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Get-AACUnusedResource
        Everything unused in the subscriptions you can see, what's billed first.
    .EXAMPLE
        Get-AACUnusedResource -IncludeCost -HtmlPath .\out\Unused.html
        With last month's cost of each, as an interactive HTML report.
    .EXAMPLE
        Get-AACUnusedResource -Category 'Unattached disk' -NoDisplay | Where-Object AgeDays -GT 30 | Select-Object Resource, Sku, AgeDays, ResourceId
        The disks unattached for more than a month.
    .EXAMPLE
        Get-AACUnusedResource -Severity High, Medium -CsvPath .\out\Cleanup.csv
        What costs money, as a clean-up list.
    .OUTPUTS
        AAC.UnusedResource
    #>
    [CmdletBinding()]
    [OutputType('AAC.UnusedResource')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string[]] $ManagementGroupId,

        [string[]] $ResourceGroupName,

        [SupportsWildcards()]
        [string[]] $ResourceType,

        [SupportsWildcards()]
        [string[]] $Category,

        [ValidateSet('High', 'Medium', 'Low')]
        [string[]] $Severity,

        [ValidateRange(1, 3650)]
        [int] $SnapshotDays = 90,

        [switch] $IncludeCost,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Unused Azure resources',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $request = @{ SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }); ResourceGroupName = @($ResourceGroupName | Where-Object { $_ }); SnapshotDays = $SnapshotDays; IncludeCost = [bool]$IncludeCost }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Unused resources' -Color 'darkorange' }
    $state = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
        $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
        Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"
        $queries = Get-AACUnusedResourceQuery -ResourceGroupName $request.ResourceGroupName
        Update-AACProgress -Id 'read' -Total $queries.Count -Description 'Reading disks, networks, plans, VMs and resource groups'
        $read = Invoke-AACGraphBatch -Query $queries -SubscriptionId $scope.GraphScope -AllowFailure @($queries.Keys) -OnProgress {
            param($QueryName, $Done, $Total)
            Update-AACProgress -Id 'read' -Increment 1 -Description "Read the $QueryName ($Done of $Total)"
        }
        Update-AACProgress -Id 'read' -Complete -Description "Read $($queries.Count - $read.Errors.Count) of $($queries.Count) kinds of resource"
        $notices = [System.Collections.Generic.List[string]]::new()
        foreach ($key in @($read.Errors.Keys | Sort-Object)) { $notices.Add("The $key couldn't be read: $($read.Errors[$key] -replace '\s+', ' ')") }

        $costs = @{}
        if ($request.IncludeCost) {
            Update-AACProgress -Id 'cost' -Indeterminate -Description 'Reading last month''s cost of each resource (Cost Management)'
            $costRead = Read-AACInventoryCost -TenantId ([string]$script:AACSession.TenantId) -Subscription @($scope.Subscriptions | ForEach-Object { @{ subscriptionId = [string]$_['subscriptionId']; name = [string]$_['name']; state = [string]$_['state'] } }) -ManagementGroupId $request.ManagementGroupId -PerSubscription:([bool]$request.SubscriptionId.Count)
            foreach ($row in @($costRead.Rows)) {
                $id = ([string](Get-AACPropertyValue -InputObject $row -Name 'ResourceId')).ToLowerInvariant()
                if (-not $id) { continue }
                $monthRaw = @('BillingMonth', 'UsageDate' | ForEach-Object { Get-AACPropertyValue -InputObject $row -Name $_ } | Where-Object { $_ }) | Select-Object -First 1
                $month = if ($monthRaw -is [datetime]) { $monthRaw.ToString('yyyy-MM') } else { ([string]$monthRaw).Substring(0, [Math]::Min(7, ([string]$monthRaw).Length)) -replace '^(\d{4})(\d{2}).*$', '$1-$2' }
                if ($month -ne $costRead.LastMonth) { continue }
                if (-not $costs.Contains($id)) { $costs[$id] = @{ Cost = 0.0; Currency = [string](Get-AACPropertyValue -InputObject $row -Name 'Currency') } }
                $costs[$id].Cost += [double](Get-AACPropertyValue -InputObject $row -Name 'Cost')
            }
            if ($costRead.Notice) { $notices.Add([string]$costRead.Notice) }
            Update-AACProgress -Id 'cost' -Complete -Description ('Read the cost of {0:N0} resource(s) for {1}' -f $costs.Count, $costRead.LastMonth)
        }
        $result = ConvertTo-AACUnusedResource -Read $read -SubscriptionName $scope.Names -SnapshotDays $request.SnapshotDays -Cost $costs
        @{ Result = $result; Scope = $scope; Notices = $notices.ToArray() }
    }

    $items = @($state.Result.Items)
    if ($ResourceType) { $items = @($items | Where-Object { $t = $_.ResourceType; @($ResourceType | Where-Object { $t -like $_ }).Count }) }
    if ($Category) { $items = @($items | Where-Object { $c = $_.Category; @($Category | Where-Object { $c -like $_ }).Count }) }
    if ($Severity) { $items = @($items | Where-Object { $Severity -contains $_.Severity }) }

    $rank = Get-AACSeverityRank
    $high = @($items | Where-Object Severity -EQ 'High').Count
    $billed = @($items | Where-Object Billed -EQ 'Yes').Count
    $priced = @($items | Where-Object { $null -ne $_.MonthlyCost })
    $monthly = 0.0; foreach ($p in $priced) { $monthly += [double]$p.MonthlyCost }; $monthly = [Math]::Round($monthly, 2)
    $currency = [string](@($priced | ForEach-Object { $_.Currency } | Where-Object { $_ }) | Select-Object -First 1)
    $report = @{
        Subtitle = 'Unused resources: attached to nothing, serving nothing or switched off'
        Facts    = [ordered]@{ Scope = $state.Scope.Label; Snapshots = "older than $SnapshotDays days"; Cost = $(if ($IncludeCost) { 'last month, Cost Management' } else { 'not read (-IncludeCost)' }) }
        Status   = $(if ($high) { 'Failed' } elseif ($billed) { 'Warning' } elseif ($items.Count) { 'Info' } else { 'Success' })
        Headline = $(if ($items.Count) { "$($items.Count) unused resource(s): $billed still billed, $high high$(if ($IncludeCost -and $priced.Count) { " - $('{0:N2}' -f $monthly) $currency a month" })" } else { 'Nothing unused in scope.' })
        Tiles    = @(
            @{ Value = '{0:N0}' -f $items.Count; Label = 'unused resources'; Tone = $(if ($items.Count) { 'warn' } else { 'good' }) }
            @{ Value = '{0:N0}' -f $high; Label = 'high'; Tone = $(if ($high) { 'bad' } else { 'good' }); Table = 'unused'; Filters = @{ Severity = 'High' } }
            @{ Value = '{0:N0}' -f $billed; Label = 'still billed'; Tone = $(if ($billed) { 'warn' } else { 'good' }); Table = 'unused'; Filters = @{ Billed = 'Yes' } }
            @{ Value = $(if ($IncludeCost) { '{0:N2} {1}' -f $monthly, $currency } else { '-' }); Label = 'a month (last month)'; Tone = $(if ($monthly -gt 0) { 'bad' } else { 'neutral' }) }
            @{ Value = '{0:N0}' -f @($items | Where-Object Category -EQ 'Unattached disk').Count; Label = 'unattached disks'; Tone = 'info'; Table = 'unused'; Filters = @{ Category = 'Unattached disk' } }
            @{ Value = '{0:N0}' -f @($items | Where-Object Category -EQ 'Empty resource group').Count; Label = 'empty resource groups'; Tone = 'neutral'; Table = 'unused'; Filters = @{ Category = 'Empty resource group' } }
        )
        Notices  = @($state.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
        Charts   = @(
            @{ Title = 'By severity'; Kind = 'donut'; CenterLabel = 'resources'; Items = @(foreach ($s in 'High', 'Medium', 'Low') { $n = @($items | Where-Object Severity -EQ $s).Count; if ($n) { @{ Label = $s; Value = $n; Tone = $rank.Tone[$s]; Filter = $s } } }); Table = 'unused'; Column = 'Severity' }
            @{ Title = 'By kind'; Items = @($items | Group-Object Category | Sort-Object Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'unused'; Column = 'Category'; Tone = 'warn'; Console = $true }
            @{ Title = 'By subscription'; Items = @($items | Group-Object Subscription | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'unused'; Column = 'Subscription'; Tone = 'info' }
            @{ Title = 'Costliest (last month)'; Items = @($priced | Sort-Object MonthlyCost -Descending | Select-Object -First 10 | ForEach-Object { @{ Label = $_.Resource; Value = $_.MonthlyCost; Filter = $_.Resource } }); Table = 'unused'; Column = 'Resource'; Tone = 'bad'; Console = [bool]$IncludeCost }
        )
        Tables   = @(
            @{ Id = 'unused'; Title = 'Unused resources'; Section = 'Unused resources'; Rows = $items; Noun = 'resources'; GroupBy = @('Category', 'Severity', 'Subscription', 'ResourceGroup'); ConsoleLimit = 30
                Empty = 'Nothing unused in scope.'; EmptyStatus = 'Success'
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Category'; Label = 'Kind'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Resource'; Label = 'Resource'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Billed'; Label = 'Billed'; Type = 'badge'; Tones = @{ Yes = 'bad'; Partly = 'warn'; No = 'neutral' }; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'AgeDays'; Label = 'Age (days)'; Type = 'number'; Console = $true }
                    @{ Key = 'MonthlyCost'; Label = 'Last month'; Type = 'money'; CurrencyKey = 'Currency'; Sum = $true; Console = [bool]$IncludeCost; Pdf = [bool]$IncludeCost }
                    @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true; Console = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                    @{ Key = 'ResourceType'; Label = 'Type'; Type = 'type'; Facet = $true }
                    @{ Key = 'Sku'; Label = 'SKU'; Facet = $true }
                    @{ Key = 'Location'; Label = 'Location'; Facet = $true }
                    @{ Key = 'Since'; Label = 'Since'; Type = 'date' }
                    @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Remediation'; Label = 'What to do'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Link'; Label = 'Docs'; Type = 'link'; Text = 'Docs' }
                ) }
        )
        Hint     = '-IncludeCost adds last month''s cost; -Category, -ResourceType and -Severity narrow the list; -NoDisplay returns the objects; -HtmlPath, -PdfPath or -CsvPath for a report.'
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $items -Noun 'resource' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $items -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
