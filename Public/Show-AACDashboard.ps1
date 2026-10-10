function Show-AACDashboard {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        A one-screen dashboard of your Azure estate: who you're signed in
        as, the subscriptions in scope, resources by region, Resource Health,
        active Azure Service Health events, Advisor and the latest changes -
        with one status at the top.
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

    # --- Everything else, in one batch -------------------------------------------------------------------------------
    $queries = Get-AACDashboardQuery -Hours $Hours
    $read = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'dashboard' -Total $queries.Count -Description 'Reading the estate, Resource Health, Service Health, Advisor and the recent changes'
        $batch = Invoke-AACGraphBatch -Query $queries -SubscriptionId $scopeIds -AllowFailure @($queries.Keys | Where-Object { $_ -ne 'totals' }) -OnProgress {
            param($Name, $Done, $Total)
            Update-AACProgress -Id 'dashboard' -Increment 1 -Description "Read $Name ($Done of $Total)"
        }
        $unread = @($batch.Errors.Keys | Where-Object { $batch.Errors[$_] }).Count
        Update-AACProgress -Id 'dashboard' -Complete -Description ('Read the dashboard for {0:N0} subscription(s){1}' -f $subscriptions.Count, $(if ($unread) { "; $unread source(s) couldn't be read" }))
        $batch
    }
    $dashboard = ConvertTo-AACDashboard -Read $read -Subscription $subscriptions -Hours $Hours -Session $script:AACSession

    if ($showView) {
        $scope = [ordered]@{ Scope = $(if ($scopeIds.Count) { "$($scopeIds.Count) subscription(s)" } else { 'all subscriptions' }) }
        Invoke-AACPagedOutput -NoPaging:$NoPaging -ScriptBlock { Show-AACDashboardView -Dashboard $dashboard -Scope $scope }
    }
    if ($returnObject) { $dashboard }
}
