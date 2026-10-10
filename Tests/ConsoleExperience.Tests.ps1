<#
    Unit tests for the console experience: the status vocabulary
    (Get-AACStatus, Write-AACStatusLine, Show-AACCallout) in Unicode and
    ASCII consoles, the JSON colouring and Show-AACJson, and Show-AACDashboard
    over a faked Azure Resource Graph - its status, the view, the scope,
    the selection prompt and what it couldn't read.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    $script:capture = {
        param([scriptblock] $Render, [bool] $Unicode = $false)
        $real = [Spectre.Console.AnsiConsole]::Console
        $buffer = [System.IO.StringWriter]::new()
        $settings = [Spectre.Console.AnsiConsoleSettings]::new()
        $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer)
        $settings.Ansi = [Spectre.Console.AnsiSupport]::No
        $settings.Enrichment.UseDefaultEnrichers = $false
        $console = [Spectre.Console.AnsiConsole]::Create($settings)
        $console.Profile.Width = 160
        $console.Profile.Capabilities.Unicode = $Unicode
        try {
            [Spectre.Console.AnsiConsole]::Console = $console
            $output = @(& $Render)
        }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
    $script:inModule = { param([scriptblock] $Script, [hashtable] $Parameters = @{}) InModuleScope 'Azure.Admin.Console' -Parameters $Parameters $Script }
    $script:codePageSafe = {
        param([string] $Text)
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            @($Text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ })
        }
    }

    # --- A made-up estate, as Resource Graph returns it ---------------------------------------------------------
    $prod = '11111111-1111-1111-1111-111111111111'
    $dev = '22222222-2222-2222-2222-222222222222'
    $rid = { param([string] $Sub, [string] $Group, [string] $Type, [string] $Name) "/subscriptions/$Sub/resourceGroups/$Group/providers/$Type/$Name" }
    $script:estate = @{
        Prod          = $prod; Dev = $dev
        subscriptions = @(@{ id = "/subscriptions/$prod"; subscriptionId = $prod; name = 'sub-prod'; state = 'Enabled' }, @{ id = "/subscriptions/$dev"; subscriptionId = $dev; name = 'sub-dev'; state = 'Warned' })
        totals        = @(@{ resources = 120; types = 18; groups = 9; regions = 3 })
        regions       = @(@{ location = 'westeurope'; resources = 80 }, @{ location = 'northeurope'; resources = 35 }, @{ location = ''; resources = 5 })
        health        = @(@{ state = 'Available'; resources = 40 }, @{ state = 'Unavailable'; resources = 1 }, @{ state = 'Degraded'; resources = 2 }, @{ state = 'Unknown'; resources = 3 })
        unhealthy     = @(
            @{ id = 'h1'; resourceId = (& $rid $prod 'rg-web' 'Microsoft.Compute/virtualMachines' 'vm-web-2'); state = 'Degraded'; summary = 'Slow disk'; reason = 'Unplanned'; since = '2026-10-09T07:00:00Z' }
            @{ id = 'h2'; resourceId = (& $rid $prod 'rg-web' 'Microsoft.Compute/virtualMachines' 'vm-web-1'); state = 'Unavailable'; summary = 'The VM stopped'; reason = 'Unplanned'; since = '2026-10-09T06:00:00Z' }
        )
        serviceIssues = @(
            @{ id = 'e1'; subscriptionId = $prod; trackingId = 'TRK-1'; title = 'Storage - West Europe'; eventType = 'ServiceIssue'; level = 'Warning'; started = '1791529200' }
            @{ id = 'e2'; subscriptionId = $dev; trackingId = 'TRK-1'; title = 'Storage - West Europe'; eventType = 'ServiceIssue'; level = 'Warning'; started = '1791529200' }
            @{ id = 'e3'; subscriptionId = $prod; trackingId = 'PM-7'; title = 'Planned maintenance - VMs'; eventType = 'PlannedMaintenance'; level = 'Informational'; started = '2026-10-12T00:00:00Z' }
        )
        advisor       = @(@{ category = 'Cost'; impact = 'High'; recommendations = 2 }, @{ category = 'HighAvailability'; impact = 'Medium'; recommendations = 4 }, @{ category = 'Security'; impact = 'Low'; recommendations = 1 })
        changes       = @(@{ changeType = 'Create'; changes = 3 }, @{ changeType = 'Update'; changes = 7 }, @{ changeType = 'Delete'; changes = 1 })
        recentChanges = @(
            @{ id = 'c1'; at = '2026-10-09T09:30:00Z'; changeType = 'Delete'; resourceId = (& $rid $dev 'rg-old' 'Microsoft.Storage/storageAccounts' 'stold'); resourceType = 'Microsoft.Storage/storageAccounts'; changedBy = 'ada@contoso.example'; operation = 'Microsoft.Storage/storageAccounts/delete' }
            @{ id = 'c2'; at = '2026-10-09T08:00:00Z'; changeType = 'Create'; resourceId = (& $rid $prod 'rg-web' 'Microsoft.Web/sites' 'app-[blue]'); resourceType = 'Microsoft.Web/sites'; changedBy = 'pipeline-sp'; operation = 'Microsoft.Web/sites/write' }
        )
    }
    $script:dashboard = { param([hashtable] $Read, [object[]] $Subscription = $script:estate.subscriptions) & $script:inModule { param($R, $S) ConvertTo-AACDashboard -Read $R -Subscription $S -Hours 24 -Session ([pscustomobject]@{ Account = 'admin@contoso.example'; TenantId = 't-1'; Flow = 'Browser'; ExpiresOn = [datetime]'2026-10-09T11:00:00' }) -Now ([datetime]'2026-10-09T10:00:00') } @{ R = $Read; S = $Subscription } }
    $script:readOf = {
        param([string[]] $Keys = @('totals', 'regions', 'health', 'unhealthy', 'serviceIssues', 'advisor', 'changes', 'recentChanges'), [hashtable] $Errors = @{})
        $rows = @{}
        foreach ($key in $Keys) { $rows[$key] = @(if ($Errors.Contains($key)) { } else { $script:estate[$key] }) }
        @{ Rows = $rows; Errors = $Errors }
    }
}

Describe 'Azure Admin Console - the status vocabulary' {
    It 'gives each state one colour, symbol and word - Unicode, or ASCII in a console that can''t show it' {
        $states = 'Success', 'Warning', 'Failed', 'InProgress', 'Info'
        $unicode = (& $script:capture { foreach ($s in $states) { & $script:inModule { param($S) Get-AACStatus $S } @{ S = $s } } } $true).Output
        @($unicode | ForEach-Object { "$($_.Color) $($_.Glyph) $($_.Label)" }) | Should -Be @("green3 $([char]0x2713) OK", "orange1 $([char]0x26A0) Warning", "red1 $([char]0x2717) Failed", "deepskyblue1 $([char]0x21BB) In progress", "grey70 $([char]0x2139) Note")
        $ascii = (& $script:capture { foreach ($s in $states) { & $script:inModule { param($S) Get-AACStatus $S } @{ S = $s } } }).Output
        @($ascii.Glyph) | Should -Be @('+', '!', 'x', '~', 'i')
        $ascii[0].Markup | Should -Be '[green3]+[/]'
    }

    It 'writes a status line and a callout, the same in every command, in characters any console can show' {
        $text = (& $script:capture {
                & $script:inModule {
                    Write-AACStatusLine Success 'Disconnected admin@contoso.example.'
                    Write-AACStatusLine Warning 'Advisor couldn''t be read' -Detail '[403] Forbidden' -Indent 2
                    Show-AACCallout Failed '[bold red1]Blocked[/] - nothing will be written.' -Title 'Blocked' -Line 'Fix the [rules] first.'
                }
            }).Text
        $text | Should -Match '(?m)^\+ Disconnected admin@contoso\.example\.'
        $text | Should -Match '(?m)^  ! Advisor couldn''t be read  \[403\] Forbidden'
        $text | Should -Match 'x Blocked'
        $text | Should -Match 'Fix the \[rules\] first\.' -Because 'the lines are escaped'
        & $script:codePageSafe $text | Should -BeNullOrEmpty
    }

    It 'is what the commands use for their outcomes and notices' {
        $root = Join-Path $PSScriptRoot '..'
        @(Select-String -Path (Join-Path $root 'Private/Show-*.ps1'), (Join-Path $root 'Public/*.ps1') -Pattern 'Show-AACPanel ' | Where-Object { $_.Line -match "-BorderColor '(green\d?|grey50|orange1|red1)'" }) | Should -BeNullOrEmpty -Because 'status panels are callouts now'
        (Get-Content -Raw (Join-Path $root 'Public/Disconnect-AAC.ps1')) | Should -Match 'Write-AACStatusLine Success'
    }
}

Describe 'Azure Admin Console - JSON at the console' {
    It 'colours names, strings, numbers, booleans and null, and escapes the rest' {
        $markup = & $script:inModule { ConvertTo-AACJsonMarkup -Json '{ "name": "st[1]", "size": -1.5e3, "on": true, "tags": null, "list": [1] }' }
        $markup | Should -BeLike '*`[grey50`]{`[/`] `[deepskyblue1`]"name"`[/`]`[grey50`]:`[/`] `[darkseagreen2`]"st`[`[1`]`]"`[/`]*'
        $markup | Should -BeLike '*`[mediumpurple2`]-1.5e3`[/`]*`[gold1`]true`[/`]*`[grey50 italic`]null`[/`]*'
        { [Spectre.Console.Markup]::new($markup) } | Should -Not -Throw
    }

    It 'shows objects and JSON text indented in a panel - several objects as one array - and passes them on with -PassThru' {
        $shown = & $script:capture { [pscustomobject]@{ name = 'stcontoso'; https = $true } | Show-AACJson -Title 'Storage' -NoPaging }
        $shown.Text | Should -Match 'Storage'
        $shown.Text | Should -Match '"name": "stcontoso"'
        $shown.Text | Should -Match '"https": true'
        (& $script:capture { '{"a":{"b":[1,2]}}' | Show-AACJson -NoPaging }).Text | Should -Match '(?m)^\W*"a": \{'
        $many = & $script:capture { 1, 2 | ForEach-Object { [pscustomobject]@{ n = $_ } } | Show-AACJson -NoPaging -PassThru }
        $many.Text | Should -Match '(?s)\[.*"n": 1.*"n": 2.*\]'
        @($many.Output.n) | Should -Be @(1, 2)
    }

    It 'shows JSON that isn''t valid as it is, and says so' {
        $result = & $script:capture { Show-AACJson -InputObject '{ "broken": ' -NoPaging -WarningVariable seen -WarningAction SilentlyContinue; $seen }
        $result.Text | Should -Match '"broken":'
        "$($result.Output)" | Should -BeLike "That isn't valid JSON*"
    }
}

Describe 'Azure Admin Console - the dashboard' {
    It 'sums up the estate, its health, Service Health, Advisor and the changes - Failed when resources are down or a service issue is active' {
        $d = & $script:dashboard (& $script:readOf)
        $d.PSObject.TypeNames | Should -Contain 'AAC.Dashboard'
        $d.Status | Should -Be 'Failed'
        $d.Headline | Should -Be '1 resource(s) unavailable; 1 active Azure service issue(s); 2 resource(s) degraded; 1 planned maintenance or advisory event(s); 2 High-impact Advisor recommendation(s)'
        "$($d.Resources) $($d.ResourceGroups) $($d.Regions)" | Should -Be '120 9 3'
        "$($d.Health.Available) $($d.Health.Unavailable) $($d.Health.Degraded) $($d.Health.Unknown)" | Should -Be '40 1 2 3'
        @($d.UnhealthyResources.Resource) | Should -Be @('vm-web-1', 'vm-web-2') -Because 'unavailable first'
        $issue = $d.ServiceEvents[0]
        "$($issue.Type) | $($issue.TrackingId) | $($issue.Subscription)" | Should -Be 'Service issue | TRK-1 | sub-prod, sub-dev' -Because 'one event in two subscriptions is listed once'
        $issue.Started | Should -BeOfType [datetime]
        @($d.Advisor | ForEach-Object { "$($_.Category) $($_.High) $($_.Medium) $($_.Low)" }) | Should -Be @('Cost 2 0 0', 'Reliability 0 4 0', 'Security 0 0 1')
        "$($d.Changes.Created) $($d.Changes.Updated) $($d.Changes.Deleted)" | Should -Be '3 7 1'
        "$($d.RecentChanges[0].Change) $($d.RecentChanges[0].Resource) $($d.RecentChanges[0].ResourceGroup)" | Should -Be 'Delete stold rg-old'
        $d.TopRegions[2].Region | Should -Be '(global)'
    }

    It 'is Healthy when nothing needs attention, and Needs attention when something couldn''t be read' {
        $healthy = @{ Rows = @{ totals = $script:estate.totals; health = @(@{ state = 'Available'; resources = 10 }) }; Errors = @{} }
        $d = & $script:dashboard $healthy
        "$($d.Status) | $($d.Headline)" | Should -Be 'Success | Every resource Resource Health reports on is available, and no Azure service issue is active.'
        $partial = @{ Rows = $healthy.Rows; Errors = @{ advisor = 'Forbidden'; changes = '' } }
        $d = & $script:dashboard $partial
        $d.Status | Should -Be 'Warning'
        @($d.Unread.PSObject.Properties | ForEach-Object { "$($_.Name): $($_.Value)" }) | Should -Be @('Azure Advisor: Forbidden')
    }

    It 'draws the dashboard: the status, tiles, session and health, subscriptions, regions, events, Advisor and changes - in characters any console can show' {
        $d = & $script:dashboard (& $script:readOf -Errors @{ advisor = 'Forbidden' })
        $text = (& $script:capture { & $script:inModule { param($D) Show-AACDashboardView -Dashboard $D -Scope ([ordered]@{ Scope = 'all subscriptions' }) } @{ D = $d } }).Text
        foreach ($expected in 'x Action needed', 'unhealthy', 'Session', 'Resource Health', 'x Unavailable', '! Degraded', 'sub-prod', '! Warned', 'Resources by region', 'westeurope', 'Azure Service Health - active events', 'TRK-1', 'vm-web-1', 'The VM stopped', 'Recent changes - last 24h: 3 created, 7 updated, 1 deleted', '- Delete', 'app-[blue]', "! Couldn't read Azure Advisor  Forbidden") {
            $text | Should -Match ([regex]::Escape($expected))
        }
        $text | Should -Not -Match 'Azure Advisor recommendations' -Because 'Advisor wasn''t read'
        & $script:codePageSafe $text | Should -BeNullOrEmpty
    }

    Context 'the command' {
        BeforeEach {
            $script:batches = [System.Collections.Generic.List[object]]::new()
            Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
            Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
                $script:batches.Add(@{ Keys = @($Query.Keys); SubscriptionId = @($SubscriptionId | Where-Object { $_ }); AllowFailure = @($AllowFailure) })
                $rows = @{}
                foreach ($key in $Query.Keys) { $rows[$key] = @($script:estate[$key]) }
                @{ Rows = $rows; Errors = @{} }
            }
            InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.example'; TenantId = 't-1'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1); Flow = 'Browser' } }
        }
        AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

        It 'reads the subscriptions, then everything else in one batch - only totals must be read - and returns the dashboard' {
            $d = Show-AACDashboard -NoDisplay -Hours 72
            $d.Status | Should -Be 'Failed'
            $d.Hours | Should -Be 72
            $script:batches.Count | Should -Be 2
            @($script:batches[1].Keys) | Should -Be @('totals', 'regions', 'health', 'unhealthy', 'serviceIssues', 'advisor', 'changes', 'recentChanges')
            $script:batches[1].AllowFailure | Should -Not -Contain 'totals'
            $script:batches[1].SubscriptionId.Count | Should -Be 0 -Because 'with no scope, everything the account can see'
            (& $script:inModule { Get-AACDashboardQuery -Hours 72 }).changes | Should -BeLike '*where at > ago(72h)*'
        }

        It 'narrows to -SubscriptionId, and says which it can''t see' {
            $result = & $script:capture { Show-AACDashboard -SubscriptionId $script:estate.Prod, '99999999-9999-9999-9999-999999999999' -NoDisplay -WarningVariable seen -WarningAction SilentlyContinue; $seen }
            @($result.Output[0].Subscriptions.Name) | Should -Be @('sub-prod')
            $script:batches[1].SubscriptionId | Should -Be @($script:estate.Prod)
            "$($result.Output[1])" | Should -BeLike '*99999999-9999-9999-9999-999999999999*left out*'
        }

        It 'lets you tick the subscriptions with -Select, and asks for -SubscriptionId where no one can answer' {
            Mock -ModuleName 'Azure.Admin.Console' -CommandName Read-AACSelection -MockWith { $script:asked = @{ Title = $Title; Labels = @($Item | ForEach-Object { & $Label $_ }) }; @($Item | Where-Object { $_['name'] -eq 'sub-dev' }) }
            $d = Show-AACDashboard -Select -NoDisplay
            $script:asked.Labels | Should -Be @("sub-dev  ($($script:estate.Dev))", "sub-prod  ($($script:estate.Prod))")
            $script:batches[1].SubscriptionId | Should -Be @($script:estate.Dev)
            @($d.Subscriptions.Name) | Should -Be @('sub-dev')
        }

        It 'asks for -SubscriptionId instead when there''s no one at the console to pick' {
            { & $script:inModule { Read-AACSelection -Title 'Pick' -Item 'a', 'b' -Multiple -Hint 'Use -SubscriptionId.' } } | Should -Throw "There's no interactive console to ask in. Use -SubscriptionId."
            { Show-AACDashboard -Select -NoDisplay } | Should -Throw "*There's no interactive console to ask in. Use -SubscriptionId to name the subscriptions.*"
        }

        It 'shows the dashboard at the prompt' {
            $text = (& $script:capture { Show-AACDashboard -NoPaging }).Text
            $text | Should -Match 'Azure Admin Console :: Dashboard'
            $text | Should -Match 'x Action needed'
            $text | Should -Match 'Scope: all subscriptions'
        }
    }
}
