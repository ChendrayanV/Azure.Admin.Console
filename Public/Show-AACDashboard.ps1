function Show-AACDashboard {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        A dashboard of your Azure estate: health, security, policy,
        governance, Advisor, the estate itself, the latest changes and (with
        -IncludeCost) the spend - one status and an Estate score at the top,
        and what to do next at the bottom.
    .DESCRIPTION
        Reads it all in one Azure Resource Graph batch (no Az modules), with
        the Connect-AAC sign-in:

          ── Azure Admin Console :: Dashboard ─────────────────────────────
          admin@contoso.com · tenant ... · all subscriptions · 9 Oct 2026 10:42
          ✗ Action needed  2 resource(s) unavailable; 1 active Azure service issue(s)

          [ subscriptions ] [ resources ] [ resource groups ] [ regions ]
          [ unhealthy ] [ Advisor High ] [ changes in 24h ]

          ╭─ Session ─────────────────╮ ╭─ Resource Health ──────────╮
          │ Account   admin@...       │ │ ✓ Available    1,204       │
          │ Tenant    ...             │ │ ✗ Unavailable  2           │
          │ Token     ✓ valid until … │ │ ⚠ Degraded     1           │
          ╰───────────────────────────╯ ╰────────────────────────────╯
          Subscriptions (state) · Resources by region · Azure Service
          Health - active events · Unhealthy resources · Azure Advisor
          recommendations · Recent changes (create, update, delete - what,
          where, who)

        The status at the top:
          ✗ Action needed     resources are unavailable, or an Azure
                              service issue is active in these subscriptions
          ⚠ Needs attention   resources are degraded, Advisor has
                              High-impact recommendations, planned
                              maintenance or an advisory is active, or
                              something couldn't be read
          ✓ Healthy           none of these

        Beyond that one screen, from the same Resource Graph batch:
          Scores       the Estate score (0-100: the average of the share of
                       resources available, the secure score, the policy
                       compliance and the Advisor score that could be read,
                       less a little when a subscription nears the role
                       assignment limit or spend jumps)
          Security     secure score, active alerts and unresolved
                       recommendations by severity, Defender plans on
          Governance   policy compliance and the assignments with the most
                       non-compliant resources, the closest role assignment
                       limit, privileged role assignments at subscription or
                       above, unused disks, public IPs and NICs, tag coverage
          Advisor      the Advisor score and the potential annual savings
          Estate       resources by type and by subscription
          Changes      the last 14 days, day by day, and who made the most
          Cost         with -IncludeCost (Cost Management, one query per
                       subscription): month to date against the same days
                       last month, a forecast, the last 30 days, the services
                       that cost most
          Next         what to do, ranked across every section, with the
                       command that goes deeper
        -Section shows only some sections. -HtmlPath and -PdfPath write it
        as a report - an Overview, then a tab per section; -CsvPath writes
        what to do next. -Watch refreshes it every so many seconds, for a
        screen on the wall (Ctrl+C stops it).

        Symbols and colours are the module's (Unicode, or ASCII in a console
        that isn't UTF-8), so the state never depends on colour alone. What
        couldn't be read (Resource Health, Service Health, Advisor or the
        change history need Reader on the subscriptions) is listed at the
        end, and the rest is still shown.

        Scope: every subscription the account can see, those in
        -SubscriptionId, or - with -Select - those you tick in a list at the
        console.
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER Select
        Pick the subscriptions from a list at the console (arrow keys, space
        to tick, Enter to accept). Needs an interactive console; in a script
        use -SubscriptionId.
    .PARAMETER Hours
        How far back the recent changes go, in hours (1 to 336 - Resource
        Graph keeps 14 days). Defaults to 24.
    .PARAMETER Section
        Only these sections: Health, Security, Policy, Governance, Advisor,
        Estate, Changes, Cost. The status, scores and what to do next always
        show.
    .PARAMETER IncludeCost
        Read the spend from Cost Management (slower: Cost Management allows
        a few queries a minute).
    .PARAMETER HtmlPath
        Write the dashboard as an interactive HTML report.
    .PARAMETER PdfPath
        Write the dashboard as a PDF report.
    .PARAMETER CsvPath
        Write what to do next to this CSV file.
    .PARAMETER Title
        The reports' title.
    .PARAMETER Watch
        Refresh the dashboard every this many seconds (30 or more) until
        Ctrl+C.
    .PARAMETER PassThru
        Show the dashboard and also return it as an AAC.Dashboard object.
    .PARAMETER NoDisplay
        Return the AAC.Dashboard object without showing the dashboard.
    .PARAMETER NoPaging
        Show the whole dashboard at once instead of a page at a time.
    .EXAMPLE
        Connect-AAC
        Show-AACDashboard
        The dashboard for every subscription you can see.
    .EXAMPLE
        Show-AACDashboard -Select -Hours 72
        Pick the subscriptions from a list, with the changes of the last three days.
    .EXAMPLE
        Show-AACDashboard -IncludeCost -HtmlPath .\Dashboard.html
        Everything, with the spend, as a report with a tab per section.
    .EXAMPLE
        Show-AACDashboard -Section Health, Security -Watch 300
        Health and security, refreshed every five minutes.
    .EXAMPLE
        (Show-AACDashboard -NoDisplay).Actions | Format-Table
        What to do next, as objects.
    .EXAMPLE
        (Show-AACDashboard -NoDisplay).UnhealthyResources | Format-Table
        The unavailable and degraded resources, as objects.
    .EXAMPLE
        if ((Show-AACDashboard -SubscriptionId $prod -NoDisplay).Status -eq 'Failed') { Send-MyAlert }
        Act on the dashboard's status in a script.
    .OUTPUTS
        AAC.Dashboard (with -PassThru or -NoDisplay, or piped onward)
    #>
    [CmdletBinding(DefaultParameterSetName = 'All')]
    [OutputType('AAC.Dashboard')]
    param(
        [Parameter(ParameterSetName = 'Subscription')]
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [Parameter(ParameterSetName = 'Select')]
        [switch] $Select,

        [ValidateRange(1, 336)]
        [int] $Hours = 24,

        [ValidateSet('Health', 'Security', 'Policy', 'Governance', 'Advisor', 'Estate', 'Changes', 'Cost')]
        [string[]] $Section,

        [switch] $IncludeCost,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $CsvPath,

        [string] $Title = 'Azure dashboard',

        [ValidateRange(30, 86400)]
        [int] $Watch,

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
    $showView = -not $NoDisplay -and -not $pipedOnward
    $returnObject = $PassThru -or $NoDisplay -or $pipedOnward

    # Signed in? (Get-AACAccessToken says what to do when not.)
    $null = Get-AACAccessToken
    if ($showView) { Write-AACRule -Title 'Azure Admin Console :: Dashboard' -Color 'deepskyblue3_1' }

    # --- The subscriptions, and which are in scope ------------------------------------------------------------
    $subscriptions = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'subscriptions' -Indeterminate -Description 'Finding the subscriptions'
        $read = Invoke-AACGraphBatch -Query ([ordered]@{ subscriptions = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions' | project id, subscriptionId, name, state = tostring(properties.state)" })
        $rows = @($read.Rows['subscriptions'] | Where-Object { $null -ne $_ })
        Update-AACProgress -Id 'subscriptions' -Complete -Description ('Found {0:N0} subscription(s)' -f $rows.Count)
        , $rows
    }
    $subscriptions = @($subscriptions)
    if (-not $subscriptions.Count) { throw 'The account can see no subscriptions. It needs Reader (or any role) on at least one.' }
    if ($SubscriptionId) {
        $wanted = @($SubscriptionId | ForEach-Object { $_.ToLowerInvariant() })
        foreach ($id in $wanted) { if (-not @($subscriptions | Where-Object { ([string]$_['subscriptionId']).ToLowerInvariant() -eq $id }).Count) { Write-Warning "Subscription $id isn't visible to this account; it's left out." } }
        $subscriptions = @($subscriptions | Where-Object { $wanted -contains ([string]$_['subscriptionId']).ToLowerInvariant() })
        if (-not $subscriptions.Count) { throw "None of the subscriptions asked for ($($SubscriptionId -join ', ')) is visible to this account." }
    }
    elseif ($Select) {
        $subscriptions = @(Read-AACSelection -Title 'Which subscriptions should the dashboard cover?' -Item ($subscriptions | Sort-Object -Property { [string]$_['name'] }) -Label { param($S) "$($S['name'])  ($($S['subscriptionId']))" } -Multiple -Hint 'Use -SubscriptionId to name the subscriptions.')
    }
    $scopeIds = @(if ($SubscriptionId -or $Select) { $subscriptions | ForEach-Object { [string]$_['subscriptionId'] } })

    # --- Everything else, in one batch - again and again with -Watch ---------------------------------------------------
    $sections = @(if ($Section) { $Section } else { 'Health', 'Security', 'Policy', 'Governance', 'Advisor', 'Estate', 'Changes'; if ($IncludeCost) { 'Cost' } })
    if ($IncludeCost -and $sections -notcontains 'Cost') { $sections += 'Cost' }
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $exporting = [bool]($CsvPath -or $HtmlPath -or $PdfPath)
    $queries = Get-AACDashboardQuery -Hours $Hours
    $scope = [ordered]@{ Scope = $(if ($scopeIds.Count) { "$($scopeIds.Count) subscription(s)" } else { 'all subscriptions' }) }
    $costIds = @($subscriptions | Where-Object { -not $_['state'] -or [string]$_['state'] -eq 'Enabled' } | ForEach-Object { [string]$_['subscriptionId'] })
    $names = @{}; foreach ($sub in $subscriptions) { $names[([string]$sub['subscriptionId']).ToLowerInvariant()] = [string]$sub['name'] }
    $pass = 0
    do {
        $pass++
        if ($pass -gt 1 -and $showView) {
            # No real console (redirected, a CI log) can't be cleared: keep scrolling instead.
            try { [Spectre.Console.AnsiConsole]::Clear() } catch { [Spectre.Console.AnsiConsole]::WriteLine() }
            Write-AACRule -Title 'Azure Admin Console :: Dashboard' -Color 'deepskyblue3_1'
        }
        $read = Invoke-AACProgress -ScriptBlock {
            Update-AACProgress -Id 'dashboard' -Total $queries.Count -Description 'Reading the estate, health, security, policy, governance, Advisor and the changes'
            $batch = Invoke-AACGraphBatch -Query $queries -SubscriptionId $scopeIds -AllowFailure @($queries.Keys | Where-Object { $_ -ne 'totals' }) -OnProgress {
                param($Name, $Done, $Total)
                Update-AACProgress -Id 'dashboard' -Increment 1 -Description "Read $Name ($Done of $Total)"
            }
            $unread = @($batch.Errors.Keys | Where-Object { $batch.Errors[$_] }).Count
            Update-AACProgress -Id 'dashboard' -Complete -Description ('Read the dashboard for {0:N0} subscription(s){1}' -f $subscriptions.Count, $(if ($unread) { "; $unread source(s) couldn't be read" }))
            $batch
        }
        $cost = $null
        if ($sections -contains 'Cost') { $cost = Invoke-AACProgress -ScriptBlock { Read-AACDashboardCost -SubscriptionId $costIds -SubscriptionName $names } }
        $dashboard = ConvertTo-AACDashboard -Read $read -Subscription $subscriptions -Hours $Hours -Session $script:AACSession -Cost $cost

        if ($exporting) {
            Invoke-AACReportOutput -Report (ConvertTo-AACDashboardReport -Dashboard $dashboard -Section $sections -Scope $scope) -Title $Title -CsvObject @($dashboard.Actions) -Noun 'action' `
                -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath)
        }
        elseif ($showView) {
            Invoke-AACPagedOutput -NoPaging:($NoPaging -or [bool]$Watch) -ScriptBlock { Show-AACDashboardView -Dashboard $dashboard -Scope $scope -Section $sections }
        }
        if ($returnObject -and -not $Watch) { $dashboard }
        if ($Watch) {
            Write-AACMarkup "[grey42]Refreshing every $Watch second(s) - Ctrl+C to stop. Read at $((Get-Date).ToString('HH:mm:ss')).[/]"
            Start-Sleep -Seconds $Watch
        }
    } while ($Watch)
}
