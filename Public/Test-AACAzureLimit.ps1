function Test-AACAzureLimit {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Shows which scopes are close to an Azure limit - role assignments,
        custom roles, policy assignments, definitions, initiatives and
        exemptions, resource groups, tags, management group depth - before
        a deployment fails on one.
    .DESCRIPTION
        Counts, read-only and in Azure Resource Graph (so only the totals
        come back, however large the tenant), what each scope uses of each
        limit:
          Tenant             custom roles (5,000), custom initiatives
                             (2,500), management groups (10,000) and their
                             depth (6 levels below the root)
          Management group   role assignments (500), policy assignments
                             (200), custom policy definitions (500),
                             custom initiatives (200), exemptions (1,000)
          Subscription       role assignments at or below it (4,000),
                             policy assignments, definitions, initiatives
                             and exemptions, resource groups (980), tags on
                             the subscription and the most on any resource
                             group or resource (50)
          Resource group     policy assignments and exemptions - listed
                             only when they reach the warning level
        Each (AAC.AzureLimit) has its use, the maximum, the percentage, what
        is left and - when it is close - what to do. Critical at
        -CriticalPercent (95%) or more, Warning at -WarningPercent (80%).

        The maximums are Microsoft's published limits; if one changes, or
        support raised one for you, pass -Maximum with the new number.
        Reader on the scope is enough; management groups count when one of
        the subscriptions in scope sits under them.
    .PARAMETER SubscriptionId
        Only these subscriptions (and the management groups above them).
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups (at any depth).
    .PARAMETER Status
        Only these: Critical, Warning, OK.
    .PARAMETER WarningPercent
        Warning from this percentage of a limit. Default 80.
    .PARAMETER CriticalPercent
        Critical from this percentage of a limit. Default 95.
    .PARAMETER Maximum
        Your own maximums, by limit name - for a limit support raised, or one
        Microsoft changed: @{ RoleAssignmentsPerSubscription = 6000 }. The
        names: RoleAssignmentsPerSubscription,
        RoleAssignmentsPerManagementGroup, CustomRolesPerTenant,
        PolicyAssignmentsPerScope, PolicyDefinitionsPerScope,
        PolicySetDefinitionsPerScope, PolicySetDefinitionsPerTenant,
        PolicyExemptionsPerScope, ResourceGroupsPerSubscription,
        TagsPerSubscription, TagsPerResourceGroup, TagsPerResource,
        ManagementGroupDepth, ManagementGroupsPerTenant.
    .PARAMETER FailOnLimit
        Stop with an error when any limit is Critical (or, with
        -FailOnLimit Warning, at Warning) - a gate for a pipeline.
    .PARAMETER CsvPath
        Write the limits to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report.
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the limits.
    .PARAMETER NoDisplay
        Return the limits without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Test-AACAzureLimit
        Every limit in use across the tenant, the closest first.
    .EXAMPLE
        Test-AACAzureLimit -Status Critical, Warning -NoDisplay | Select-Object Limit, Scope, Used, Maximum, Percent
        Only the limits that need attention, as objects.
    .EXAMPLE
        Test-AACAzureLimit -ManagementGroupId 'mg-landingzones' -FailOnLimit Warning
        A pipeline gate: fails if anything under the landing zones is at 80% of a limit.
    .EXAMPLE
        Test-AACAzureLimit -Maximum @{ RoleAssignmentsPerSubscription = 6000 } -HtmlPath .\Limits.html
        With a raised role assignment limit, as a report.
    .OUTPUTS
        AAC.AzureLimit
    #>
    [CmdletBinding()]
    [OutputType('AAC.AzureLimit')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string[]] $ManagementGroupId,

        [ValidateSet('Critical', 'Warning', 'OK')]
        [string[]] $Status,

        [ValidateRange(1, 100)]
        [int] $WarningPercent = 80,

        [ValidateRange(1, 100)]
        [int] $CriticalPercent = 95,

        [hashtable] $Maximum = @{},

        [ValidateSet('Critical', 'Warning')]
        [string] $FailOnLimit,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Azure limits',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    if ($WarningPercent -gt $CriticalPercent) { throw "Azure Admin Console: -WarningPercent ($WarningPercent) is above -CriticalPercent ($CriticalPercent). Use a lower warning level." }
    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $request = @{ SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }); Maximum = $Maximum; WarningPercent = $WarningPercent; CriticalPercent = $CriticalPercent }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Azure limits' -Color 'orange1' }
    $outcome = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
        $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
        Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"
        $query = Get-AACAzureLimitQuery
        Update-AACProgress -Id 'count' -Total $query.Count -Description 'Counting what each scope uses'
        $read = Invoke-AACGraphBatch -Query $query -SubscriptionId $scope.GraphScope -AllowFailure @($query.Keys) -OnProgress {
            param($QueryName, $Done, $Total)
            Update-AACProgress -Id 'count' -Increment 1 -Description "Counted the $QueryName ($Done of $Total)"
        }
        Update-AACProgress -Id 'count' -Complete -Description "Counted $($query.Count - $read.Errors.Count) of $($query.Count) kinds of limit"
        @{ Result = (ConvertTo-AACAzureLimit -Read $read -Scope $scope -Maximum $request.Maximum -WarningPercent $request.WarningPercent -CriticalPercent $request.CriticalPercent); Scope = $scope }
    }

    $limits = @($outcome.Result.Limits)
    $all = $limits
    if ($Status) { $limits = @($limits | Where-Object { $Status -contains $_.Status }) }
    $critical = @($all | Where-Object Status -EQ 'Critical').Count
    $warning = @($all | Where-Object Status -EQ 'Warning').Count
    $tones = @{ Critical = 'bad'; Warning = 'warn'; OK = 'good' }
    $report = @{
        Subtitle = 'Azure limits: what each scope uses of the role assignment, policy, resource group, tag and management group limits'
        Facts    = [ordered]@{ Scope = $outcome.Scope.Label; Warning = "$WarningPercent%"; Critical = "$CriticalPercent%"; Maximums = $(if ($Maximum.Count) { 'Microsoft''s, with ' + (@($Maximum.Keys | ForEach-Object { "$_ = $($Maximum[$_])" }) -join ', ') } else { 'Microsoft''s published limits' }) }
        Status   = $(if ($critical) { 'Failed' } elseif ($warning) { 'Warning' } else { 'Success' })
        Headline = $(if ($critical -or $warning) { "$critical limit(s) critical and $warning close (of $($all.Count) in use) - the closest: $(@($all)[0].Limit) on $(@($all)[0].Scope), $(@($all)[0].Used) of $(@($all)[0].Maximum)" } elseif ($all.Count) { "Every limit is below $WarningPercent% - the closest: $(@($all)[0].Limit) on $(@($all)[0].Scope) at $(@($all)[0].Percent)%." } else { 'Nothing in scope counts toward a limit.' })
        Tiles    = @(
            @{ Value = '{0:N0}' -f $critical; Label = 'critical'; Tone = $(if ($critical) { 'bad' } else { 'good' }); Table = 'limits'; Filters = @{ Status = 'Critical' } }
            @{ Value = '{0:N0}' -f $warning; Label = 'close to the limit'; Tone = $(if ($warning) { 'warn' } else { 'good' }); Table = 'limits'; Filters = @{ Status = 'Warning' } }
            @{ Value = '{0:N0}' -f $all.Count; Label = 'limits in use'; Tone = 'info' }
            @{ Value = "$($outcome.Result.Stats.Highest)%"; Label = 'highest use'; Tone = $(if ($critical) { 'bad' } elseif ($warning) { 'warn' } else { 'good' }) }
        )
        Notices  = @($outcome.Result.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
        Charts   = @(
            @{ Title = 'Closest to the limit (%)'; Items = @($all | Select-Object -First 12 | ForEach-Object { @{ Label = "$($_.Limit): $($_.Scope)"; Value = $_.Percent; Tone = $tones[$_.Status] } }); Tone = 'warn'; Console = $true }
            @{ Title = 'By status'; Kind = 'donut'; CenterLabel = 'limits'; Items = @(foreach ($s in 'Critical', 'Warning', 'OK') { $n = @($all | Where-Object Status -EQ $s).Count; if ($n) { @{ Label = $s; Value = $n; Tone = $tones[$s]; Filter = $s } } }); Table = 'limits'; Column = 'Status' }
        )
        Tables   = @(
            @{ Id = 'limits'; Title = 'Azure limits'; Section = 'Limits'; Rows = $limits; Noun = 'limits'; GroupBy = @('ScopeType', 'Limit'); ConsoleLimit = 25
                Empty = 'Nothing in scope counts toward a limit.'; EmptyStatus = 'Success'
                Columns = @(
                    @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = $tones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Limit'; Label = 'Limit'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'ScopeType'; Label = 'Scope type'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Scope'; Label = 'Scope'; Console = $true; Pdf = $true }
                    @{ Key = 'Used'; Label = 'Used'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'Maximum'; Label = 'Maximum'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'Percent'; Label = '%'; Type = 'score'; Format = 'N1'; Console = $true; Pdf = $true }
                    @{ Key = 'Remaining'; Label = 'Left'; Type = 'number' }
                    @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide' }
                    @{ Key = 'Advice'; Label = 'What to do'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'ScopeId'; Label = 'Scope ID'; Type = 'mono' }
                ) }
        )
        Hint     = '-Status Critical, Warning narrows it; -Maximum sets a raised limit; -FailOnLimit fails a pipeline; -NoDisplay returns the limits; -HtmlPath, -PdfPath or -CsvPath for a report.'
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $limits -Noun 'limit' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $limits -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)

    if ($FailOnLimit) {
        $failing = @($all | Where-Object { $_.Status -eq 'Critical' -or ($FailOnLimit -eq 'Warning' -and $_.Status -eq 'Warning') })
        if ($failing.Count) {
            $problem = [System.InvalidOperationException]::new("Azure Admin Console: $($failing.Count) limit(s) at or above $(if ($FailOnLimit -eq 'Warning') { "$WarningPercent%" } else { "$CriticalPercent%" }): $((@($failing | Select-Object -First 3 | ForEach-Object { "$($_.Limit) on $($_.Scope) ($($_.Used) of $($_.Maximum))" })) -join '; ').")
            $problem.Data['AACHint'] = 'Free up room (see What to do in the report), or ask Azure support to raise the limit and pass it with -Maximum.'
            throw $problem
        }
    }
}
