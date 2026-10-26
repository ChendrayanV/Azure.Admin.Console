function Invoke-AACFunctionAppAssessment {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Assesses Azure Function Apps end to end - the app and its plan, how
        it is used, its functions and triggers, configuration, networking,
        deployment slots and deployment center, backups, Service Connector
        connections, the Well-Architected Framework, PSRule for Azure,
        Advisor and Defender, and the last week's Activity Log - with a
        Spectre.Console view, objects, and CSV, PDF and a tabbed HTML report.
    .DESCRIPTION
        Read-only, REST only (no Az modules). Reader is enough for all but
        the app settings and connection strings, which need
        Microsoft.Web/sites/config/list/action (Website Contributor, or a
        custom role) - without it they are left out and said so. Setting
        values are never shown or written: only their names and kinds.

        For each function app (Windows, Linux, containers, Flex
        Consumption; not Logic Apps Standard):
          App and plan      hosting (Consumption, Flex Consumption, Elastic
                            Premium, Dedicated, App Service Environment,
                            Container Apps), SKU, instances, burst, zone
                            redundancy, the plan's CPU and memory
          Usage             executions, execution units (GB-seconds),
                            requests, 5xx and 4xx, error rate, response time,
                            memory - over -TimeRange - and, on Consumption,
                            an estimated monthly cost; idle apps
          Functions         every function, its trigger (HTTP with its auth
                            level, timer with its schedule, queue, Service
                            Bus, Event Hubs, Cosmos DB, blob, Event Grid...)
                            and bindings
          Runtime           Functions runtime, language and version against
                            its end of support, the .NET in-process model
          Configuration     every setting that matters, by area: general,
                            runtime, security, networking, scale, monitoring,
                            deployment; app settings by name and kind (Key
                            Vault reference, identity-based, key or
                            connection string, plain, platform)
          Networking        inbound (public, restricted, private endpoints,
                            public access off), SCM site rules, VNet
                            integration and route-all, outbound IPs, CORS
          Deployment        deployment center (GitHub Actions, Azure Repos,
                            external Git, zip deploy), recent deployments,
                            slots, run from package, basic publishing
                            credentials
          Backups           taken and their status, where the plan supports
                            them
          Connections       Service Connector connections, and the Key
                            Vaults, storage accounts, Service Bus / Event
                            Hubs and Cosmos DB accounts named in app settings
                            (names only) - with how each authenticates
          Activity Log      every management operation in the last
                            -ActivityDays: restarts, stops, configuration
                            changes, deployments, slot swaps, settings and
                            keys read - who, when, and whether it worked
          Well-Architected  about 30 checks across the five pillars, Pass,
                            Fail or N/A, a score per app and per pillar
          PSRule for Azure  the Azure.AppService.* and related rules on the
                            apps and plans (unless -SkipPSRule)
          Recommendations   Azure Advisor and Defender for Cloud
        Every failed check and rule, recommendation and notable Activity Log
        pattern is a finding with its severity, pillar, source and what to
        do.

        The HTML report has a tab for each audience - a service summary for
        service delivery managers (health, usage, errors, changes, owner),
        apps and plans for architects, configuration and networking for
        administrators, security findings for IT security - an App selector
        that filters every tab, and hover cards with each row's details.
    .PARAMETER SubscriptionId
        Only the apps in these subscriptions.
    .PARAMETER ManagementGroupId
        Only the apps under these management groups.
    .PARAMETER ResourceGroupName
        Only the apps in these resource groups.
    .PARAMETER Name
        Only these apps; wildcards work, e.g. 'func-orders-*'.
    .PARAMETER TimeRange
        The period usage and metrics cover: 1h, 4h, 12h, 1d, 3d, 7d (the
        default), 14d or 30d.
    .PARAMETER ActivityDays
        How many days of the Activity Log to read (7 if not given; 1 to 90).
    .PARAMETER SkipSettings
        Don't list app settings and connection strings.
    .PARAMETER SkipPSRule
        Don't run PSRule for Azure.
    .PARAMETER Baseline
        The PSRule for Azure baseline (Azure.Default by default).
    .PARAMETER ExcludeRule
        PSRule rules to leave out, by name or wildcard.
    .PARAMETER View
        What is returned and written to -CsvPath: App (default), Plan,
        Function, Setting, AppSetting, Slot, Deployment, Network, Backup,
        Connection, Activity, Check, PSRule, Recommendation or Finding.
    .PARAMETER ThrottleLimit
        How many requests run at once (1 to 32; 12 by default).
    .PARAMETER CsvPath
        Write the -View rows to this CSV file.
    .PARAMETER HtmlPath
        Write the tabbed, interactive HTML report.
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
        Connect-AAC
        Invoke-AACFunctionAppAssessment -HtmlPath .\Functions.html
        Every function app you can see, assessed, as an interactive report.
    .EXAMPLE
        Invoke-AACFunctionAppAssessment -Name 'func-orders-*' -TimeRange 30d -HtmlPath .\Orders.html -PdfPath .\Orders.pdf
        Some apps over a month: usage, cost, changes and findings.
    .EXAMPLE
        Invoke-AACFunctionAppAssessment -View Finding -NoDisplay | Where-Object Pillar -EQ 'Security'
        The security findings, for IT security.
    .EXAMPLE
        Invoke-AACFunctionAppAssessment -View Activity -ActivityDays 30 -NoDisplay | Where-Object Kind -In 'Configuration change', 'Secrets or keys read'
        Who changed the apps' configuration, or read their settings, in the last month.
    .EXAMPLE
        Invoke-AACFunctionAppAssessment -View Function -NoDisplay | Where-Object { $_.Trigger -eq 'http' -and $_.AuthLevel -eq 'anonymous' }
        The anonymous HTTP functions.
    .OUTPUTS
        AAC.FunctionApp, AAC.FunctionAppPlan, AAC.FunctionAppFunction, AAC.FunctionAppSettingView, AAC.FunctionAppAppSetting, AAC.FunctionAppSlot, AAC.FunctionAppDeployment, AAC.FunctionAppNetwork, AAC.FunctionAppBackup, AAC.FunctionAppConnection, AAC.FunctionAppActivity, AAC.FunctionAppCheck, AAC.PSRuleResult, AAC.FunctionAppRecommendation or AAC.FunctionAppFinding, by -View (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.FunctionApp', 'AAC.FunctionAppPlan', 'AAC.FunctionAppFunction', 'AAC.FunctionAppSettingView', 'AAC.FunctionAppAppSetting', 'AAC.FunctionAppSlot', 'AAC.FunctionAppDeployment', 'AAC.FunctionAppNetwork', 'AAC.FunctionAppBackup', 'AAC.FunctionAppConnection', 'AAC.FunctionAppActivity', 'AAC.FunctionAppCheck', 'AAC.PSRuleResult', 'AAC.FunctionAppRecommendation', 'AAC.FunctionAppFinding')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [ValidateNotNullOrEmpty()]
        [string[]] $ManagementGroupId,

        [ValidateNotNullOrEmpty()]
        [string[]] $ResourceGroupName,

        [SupportsWildcards()]
        [ValidateNotNullOrEmpty()]
        [string[]] $Name,

        [ValidateSet('1h', '4h', '12h', '1d', '3d', '7d', '14d', '30d')]
        [string] $TimeRange = '7d',

        [ValidateRange(1, 90)]
        [int] $ActivityDays = 7,

        [switch] $SkipSettings,

        [switch] $SkipPSRule,

        [string] $Baseline,

        [string[]] $ExcludeRule = @(),

        [ValidateSet('App', 'Plan', 'Function', 'Setting', 'AppSetting', 'Slot', 'Deployment', 'Network', 'Backup', 'Connection', 'Activity', 'Check', 'PSRule', 'Recommendation', 'Finding')]
        [string] $View = 'App',

        [ValidateRange(1, 32)]
        [int] $ThrottleLimit = 12,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Function App assessment',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $range = Get-AACTimeRange -TimeRange $TimeRange
    $end = [datetime]::UtcNow
    $request = @{
        SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }); ResourceGroupName = @($ResourceGroupName | Where-Object { $_ }); Name = @($Name | Where-Object { $_ })
        Hours = $range[0]; Interval = $range[1]; Timespan = "$($end.AddHours(-$range[0]).ToString('yyyy-MM-ddTHH:mm:ssZ'))/$($end.ToString('yyyy-MM-ddTHH:mm:ssZ'))"
        ActivityDays = $ActivityDays; SkipSettings = [bool]$SkipSettings; SkipPSRule = [bool]$SkipPSRule; Baseline = $Baseline; ExcludeRule = @($ExcludeRule | Where-Object { $_ }); ThrottleLimit = $ThrottleLimit
    }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Function App assessment' -Color 'gold1' }
    $state = Invoke-AACProgress -ScriptBlock {
        $notices = [System.Collections.Generic.List[string]]::new()
        $rowsOf = { param($Read, [string] $Key) @(if ($Read.Rows.Contains($Key)) { $Read.Rows[$Key] }) | Where-Object { $null -ne $_ } }

        # --- 1. The apps, plans, slots, endpoints, Advisor, Defender (Resource Graph) -------------------------------
        Update-AACProgress -Id 'find' -Indeterminate -Description 'Finding the function apps'
        $scope = @{}
        if ($request.SubscriptionId.Count) { $scope.SubscriptionId = $request.SubscriptionId }
        if ($request.ManagementGroupId.Count) { $scope.ManagementGroupId = $request.ManagementGroupId }
        $queries = Get-AACFunctionAppQuery -ResourceGroupName $request.ResourceGroupName
        $read = Invoke-AACGraphBatch @scope -Query $queries -AllowFailure @('advisor', 'defender', 'privateEndpoints', 'slots', 'subscriptions')
        foreach ($key in @($read.Errors.Keys | Sort-Object)) { $notices.Add("The $key couldn't be read: $($read.Errors[$key] -replace '\s+', ' ')") }
        $apps = @(& $rowsOf $read 'apps')
        if ($request.Name.Count) {
            $apps = @($apps | Where-Object { $appName = [string]$_['name']; @($request.Name | Where-Object { $appName -like $_ }).Count })
            foreach ($item in @($request.Name | Where-Object { $pattern = $_; -not @($apps | Where-Object { [string]$_['name'] -like $pattern }).Count })) { if ($apps.Count) { Write-Warning "No function app named '$item' was found; it's left out." } }
        }
        if (-not $apps.Count) {
            $problem = [System.InvalidOperationException]::new("No function app$(if ($request.Name.Count) { " named $(($request.Name | ForEach-Object { "'$_'" }) -join ', ')" }) was found$(if ($scope.Count -or $request.ResourceGroupName.Count) { ' in that scope' } else { ' in any subscription you can see' }).")
            $problem.Data['AACHint'] = 'Check the scope and the names (wildcards work: -Name ''func-*''), and that your account has Reader on the apps.'
            throw $problem
        }
        $names = @{}
        foreach ($row in @(& $rowsOf $read 'subscriptions')) { $names[([string]$row['subscriptionId']).ToLowerInvariant()] = [string]$row['name'] }
        $ids = @($apps | ForEach-Object { [string]$_['id'] })
        $planIds = @($apps | ForEach-Object { [string]$_['properties']['serverFarmId'] } | Where-Object { $_ } | Select-Object -Unique)
        $plans = @(& $rowsOf $read 'plans' | Where-Object { $planIds -contains [string]$_['id'] })
        $subscriptions = @($apps | ForEach-Object { [string]$_['subscriptionId'] } | Select-Object -Unique)
        Update-AACProgress -Id 'find' -Complete -Description ('Found {0:N0} function app(s) on {1:N0} plan(s) in {2:N0} subscription(s)' -f $apps.Count, $plans.Count, $subscriptions.Count)

        # --- 2. Each app's configuration, functions, deployments, backups, connections, Activity Log ------------------
        Update-AACProgress -Id 'detail' -Total ([Math]::Max(1, $ids.Count * 13)) -Description 'Reading configuration, functions, deployments, backups, connections and the Activity Log'
        $detail = Read-AACFunctionAppDetail -AppId $ids -ActivityDays $request.ActivityDays -SkipSettings:$request.SkipSettings -ThrottleLimit $request.ThrottleLimit -OnProgress { param($Done, $Total) Update-AACProgress -Id 'detail' -Increment 1 }
        $unreadSettings = @($detail.Values | Where-Object { $_.AppSettingsError } | ForEach-Object { $_.AppSettingsError } | Select-Object -Unique)
        foreach ($reason in $unreadSettings) { if ($reason -notlike 'Not read*') { $notices.Add("App settings: $reason Checks that need them are N/A.") } }
        $noFunctions = @($detail.Keys | Where-Object { $detail[$_].Functions -and $detail[$_].Functions['Error'] }).Count
        if ($noFunctions) { $notices.Add("The functions of $noFunctions app(s) couldn't be listed (a stopped app, or a host that can't be reached) - their triggers are left out.") }
        Update-AACProgress -Id 'detail' -Complete -Description ('Read the configuration and history of {0:N0} app(s)' -f $ids.Count)

        # --- 3. Usage (Azure Monitor) -----------------------------------------------------------------------------
        $calls = @(foreach ($id in $ids) {
                @{ Id = $id; Key = 'Http'; Metric = @('Requests', 'Http5xx', 'Http4xx'); Aggregation = @('Total'); Filter = '' }
                @{ Id = $id; Key = 'Exec'; Metric = @('FunctionExecutionCount', 'FunctionExecutionUnits'); Aggregation = @('Total'); Filter = '' }
                @{ Id = $id; Key = 'Latency'; Metric = @('HttpResponseTime'); Aggregation = @('Average'); Filter = '' }
                @{ Id = $id; Key = 'Memory'; Metric = @('MemoryWorkingSet'); Aggregation = @('Average', 'Maximum'); Filter = '' }
            }
            foreach ($p in $plans) { if ([string]$p['sku']['tier'] -notin 'Dynamic', 'FlexConsumption') { @{ Id = [string]$p['id']; Key = 'Plan'; Metric = @('CpuPercentage', 'MemoryPercentage'); Aggregation = @('Average', 'Maximum'); Filter = '' } } })
        Update-AACProgress -Id 'metrics' -Total ([Math]::Max(1, $calls.Count)) -Description 'Reading usage (Azure Monitor)'
        $metrics = Read-AACMetric -Call $calls -Timespan $request.Timespan -Interval $request.Interval -ThrottleLimit $request.ThrottleLimit -OnProgress { param($Done, $Total) Update-AACProgress -Id 'metrics' -Increment 1 }
        Update-AACProgress -Id 'metrics' -Complete -Description ('Read the usage of {0:N0} app(s) and {1:N0} plan(s)' -f $ids.Count, $plans.Count)

        # --- 4. PSRule for Azure ------------------------------------------------------------------------------------
        $psrule = @()
        if ($request.SkipPSRule) { }
        elseif (-not (Get-Module -Name 'PSRule.Rules.Azure' -ListAvailable)) { $notices.Add('PSRule for Azure is not installed, so its rules were not run: Install-PSResource PSRule.Rules.Azure -Scope CurrentUser') }
        else {
            try {
                Update-AACProgress -Id 'psrule' -Indeterminate -Description 'Running PSRule for Azure on the apps and plans'
                $ruleData = Get-AACRuleData -SubscriptionId $subscriptions -ResourceType 'Microsoft.Web/sites', 'Microsoft.Web/serverfarms' -ResourceId @($ids + $planIds)
                foreach ($line in @($ruleData.Warnings)) { $notices.Add($line) }
                $engine = @{ InputObject = @($ruleData.Resources | Where-Object { $_ }); ExcludeRule = $request.ExcludeRule }
                if ($request.Baseline) { $engine.Baseline = $request.Baseline }
                $psrule = @((Invoke-AACPSRuleEngine @engine).Results)
                Update-AACProgress -Id 'psrule' -Complete -Description ('PSRule for Azure: {0:N0} rule result(s), {1:N0} failed' -f $psrule.Count, @($psrule | Where-Object Outcome -EQ 'Fail').Count)
            }
            catch { $notices.Add("PSRule for Azure couldn't run: $($_.Exception.Message)") }
        }

        # --- 5. The assessment --------------------------------------------------------------------------------------
        Update-AACProgress -Id 'assess' -Indeterminate -Description 'Assessing the apps'
        $result = ConvertTo-AACFunctionAppAssessment -App $apps -Plan $plans -Slot @(& $rowsOf $read 'slots') -PrivateEndpoint @(& $rowsOf $read 'privateEndpoints') `
            -Advisor @(& $rowsOf $read 'advisor') -Defender @(& $rowsOf $read 'defender') -PSRule $psrule -Detail $detail -Metric $metrics -SubscriptionName $names -Hours $request.Hours -ActivityDays $request.ActivityDays
        $s = $result.Stats
        Update-AACProgress -Id 'assess' -Complete -Description ('Assessed {0:N0} app(s): WAF {1}%, {2} high, {3} medium finding(s)' -f $s.Apps, $s.WafScore, $s.High, $s.Medium)
        @{ Result = $result; Notices = $notices.ToArray() }
    }

    # --- Report ---------------------------------------------------------------------------------------------------
    $r = $state.Result
    $s = $r.Stats
    $rank = Get-AACSeverityRank
    $yes = @{ True = 'good'; False = 'warn' }
    $healthTones = @{ Available = 'good'; Degraded = 'warn'; Unavailable = 'bad'; Unknown = 'neutral' }
    $supportTones = @{ Supported = 'good'; 'Ending soon' = 'warn'; 'Out of support' = 'bad'; Unknown = 'neutral' }
    $hostingTones = @{ Consumption = 'info'; 'Flex Consumption' = 'info'; 'Elastic Premium' = 'violet'; Dedicated = 'neutral'; 'App Service Environment' = 'neutral'; 'Container Apps' = 'violet' }
    $inboundTones = @{ Public = 'bad'; Restricted = 'warn'; 'Public + private endpoint' = 'warn'; 'Private + restricted' = 'good'; Private = 'good' }
    $checkTones = @{ Pass = 'good'; Fail = 'bad'; 'N/A' = 'neutral' }
    $kindTones = @{ 'Key Vault reference' = 'good'; 'Identity-based connection' = 'good'; 'Key or connection string' = 'bad'; 'Plain value' = 'neutral'; Platform = 'info' }
    $activityTones = @{ 'Configuration change' = 'warn'; Deployment = 'info'; 'Slot swap' = 'violet'; Restart = 'warn'; Stop = 'bad'; Start = 'good'; Delete = 'bad'; 'Secrets or keys read' = 'warn'; Change = 'neutral'; Other = 'neutral' }
    $n0 = @{ Type = 'number'; Format = 'N0' }
    $report = @{
        Subtitle = "Function Apps - usage over the last $TimeRange, Activity Log over $ActivityDays day(s)"
        Scope    = @{ Key = 'App'; Label = 'Function app'; Values = @($r.Apps | ForEach-Object { $_.App } | Sort-Object); Card = 'service'; Note = 'Choose an app to see only its rows in every tab.' }
        Facts    = [ordered]@{
            Scope           = $(if ($ManagementGroupId) { "management group(s) $($ManagementGroupId -join ', ')" } elseif ($SubscriptionId) { "subscription(s) $($SubscriptionId -join ', ')" } else { 'every subscription the account can see' })
            'Usage over'    = $TimeRange; 'Activity Log' = "last $ActivityDays day(s)"; 'App settings' = $(if ($SkipSettings) { 'not read (-SkipSettings)' } elseif ($s.SettingsUnread) { "not readable for $($s.SettingsUnread) app(s)" } else { 'read (names and kinds only)' })
            'PSRule for Azure' = $(if ($SkipPSRule) { 'not run (-SkipPSRule)' } elseif (@($r.PSRule).Count) { $(if ($Baseline) { $Baseline } else { 'Azure.Default' }) } else { 'not run' })
            Generated       = "$([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture)) UTC"
        }
        Status   = $(if ($s.High) { 'Failed' } elseif ($s.Medium) { 'Warning' } else { 'Success' })
        Headline = "$($s.Apps) function app(s) on $($s.Plans) plan(s): Well-Architected $($s.WafScore)%; $('{0:N0}' -f $s.Executions) execution(s) and $('{0:N0}' -f $s.Requests) request(s) over $TimeRange; $($s.OutOfSupport) runtime(s) out of support, $($s.EndingSoon) ending soon; $($s.Public) open to every network; $($s.Idle) idle; $($s.High) high finding(s)"
        Tiles    = @(
            @{ Value = '{0:N0}' -f $s.Apps; Label = "apps on $($s.Plans) plan(s)"; Tone = 'info'; Table = 'apps' }
            @{ Value = $(if ($null -ne $s.WafScore) { "$($s.WafScore)%" } else { '-' }); Label = 'Well-Architected score'; Tone = $(if ($s.WafScore -ge 80) { 'good' } elseif ($s.WafScore -ge 60) { 'warn' } else { 'bad' }); Table = 'pillars' }
            @{ Value = '{0:N0}' -f $s.Executions; Label = "executions ($TimeRange)"; Tone = 'info'; Table = 'usage' }
            @{ Value = $(if ($s.Requests) { '{0:N2}%' -f (100.0 * $s.Http5xx / $s.Requests) } else { '-' }); Label = 'HTTP 5xx rate'; Tone = $(if ($s.Requests -and $s.Http5xx / $s.Requests -ge 0.05) { 'bad' } elseif ($s.Http5xx) { 'warn' } else { 'good' }); Table = 'usage' }
            @{ Value = '{0:N0}' -f ($s.OutOfSupport + $s.EndingSoon); Label = 'runtimes out of / ending support'; Tone = $(if ($s.OutOfSupport) { 'bad' } elseif ($s.EndingSoon) { 'warn' } else { 'good' }); Table = 'apps' }
            @{ Value = '{0:N0}' -f $s.Public; Label = 'open to every network'; Tone = $(if ($s.Public) { 'bad' } else { 'good' }); Table = 'network'; Filters = @{ Inbound = 'Public' } }
            @{ Value = '{0:N0}' -f $s.Idle; Label = "idle ($TimeRange)"; Tone = $(if ($s.Idle) { 'warn' } else { 'good' }); Table = 'usage'; Filters = @{ Idle = 'True' } }
            @{ Value = '{0:N0}' -f $s.Changes; Label = "changes in $ActivityDays day(s)"; Tone = 'info'; Table = 'activity' }
            @{ Value = '{0:N0}' -f $s.High; Label = 'high findings'; Tone = $(if ($s.High) { 'bad' } else { 'good' }); Table = 'findings'; Filters = @{ Severity = 'High' } }
        )
        Notices  = @($state.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
        Charts   = @(
            @{ Title = 'Well-Architected score by pillar'; Items = @($r.Pillars | Where-Object { $null -ne $_.Score } | ForEach-Object { @{ Label = $_.Pillar; Value = [double]$_.Score; Display = "$($_.Score)% ($($_.Passed)/$($_.Checks))"; Tone = $(if ($_.Score -ge 80) { 'good' } elseif ($_.Score -ge 60) { 'warn' } else { 'bad' }); Filter = $_.Pillar } }); Table = 'checks'; Column = 'Pillar'; Console = $true }
            @{ Title = 'Hosting'; Kind = 'donut'; CenterLabel = 'apps'; Items = @($r.Apps | Group-Object -Property Hosting | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Tone = $hostingTones[$_.Name]; Filter = $_.Name } }); Table = 'apps'; Column = 'Hosting' }
            @{ Title = 'Triggers'; Kind = 'donut'; CenterLabel = 'functions'; Items = @($r.Functions | Group-Object -Property Trigger | Sort-Object -Property Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'functions'; Column = 'Trigger' }
            @{ Title = "Executions by app ($TimeRange)"; Items = @($r.Apps | Where-Object { $_.Executions } | Sort-Object -Property Executions -Descending | Select-Object -First 12 | ForEach-Object { @{ Label = $_.App; Value = [double]$_.Executions; Filter = $_.App } }); Table = 'usage'; Column = 'App'; Tone = 'info' }
            @{ Title = "Activity Log ($ActivityDays day(s))"; Kind = 'donut'; CenterLabel = 'operations'; Items = @($r.Activity | Group-Object -Property Kind | Sort-Object -Property Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Tone = $activityTones[$_.Name]; Filter = $_.Name } }); Table = 'activity'; Column = 'Kind' }
            @{ Title = 'Findings by pillar'; Items = @($r.Findings | Group-Object -Property Pillar | Sort-Object -Property Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'findings'; Column = 'Pillar'; Tone = 'warn' }
        )
        Tabs     = @(
            @{ Name = 'Service summary'; Badge = $s.Apps; Tone = 'info'; Note = 'For service delivery: each app''s health, usage, errors and response time, the last deployment, changes in the Activity Log, open findings, and who owns it (tags).' }
            @{ Name = 'Apps & plans'; Badge = $s.Apps + $s.Plans; Tone = 'violet'; Note = 'For architects: hosting, runtime and its support, Functions model, triggers, identity, networking and resilience - and each plan''s SKU, instances, zone redundancy and load.' }
            @{ Name = 'Usage'; Badge = $s.Apps; Tone = 'info'; Note = "How each app is used over $TimeRange - executions, execution units (GB-seconds), requests, errors, response time, memory - and the estimated monthly cost on Consumption (before the free grant)." }
            @{ Name = 'Functions'; Badge = $s.Functions; Tone = 'info'; Note = 'Every function: its trigger (HTTP with its auth level, timer with its schedule...), its input and output bindings and the connections they use.' }
            @{ Name = 'Configuration'; Badge = @($r.Settings).Count; Tone = 'neutral'; Note = 'For administrators: every setting that matters, by area - then the app settings by name and kind (values are never read into the report).' }
            @{ Name = 'Networking'; Badge = $s.Apps; Tone = $(if ($s.Public) { 'bad' } else { 'good' }); Note = 'Inbound (public, restricted, private endpoints), the SCM site, VNet integration, outbound IPs and CORS.' }
            @{ Name = 'Deployment'; Badge = @($r.Deployments).Count + $s.Slots; Tone = 'info'; Note = 'The deployment center (source, repository, branch), recent deployments, and the deployment slots.' }
            @{ Name = 'Backups & connections'; Badge = @($r.Connections).Count; Tone = 'info'; Note = 'Backups where the plan supports them; Service Connector connections and the services named in app settings, with how each authenticates.' }
            @{ Name = 'Activity Log'; Badge = $s.Changes; Tone = 'info'; Note = "Every management operation in the last $ActivityDays day(s): restarts, stops, configuration changes, deployments, slot swaps, settings and keys read - who, when, and whether it worked." }
            @{ Name = 'Well-Architected'; Badge = @($r.Checks | Where-Object Status -EQ 'Fail').Count; Tone = $(if ($s.WafScore -ge 80) { 'good' } else { 'warn' }); Note = 'Each check across the five pillars, Pass, Fail or N/A, with the score per pillar.' }
            @{ Name = 'PSRule'; Badge = $s.PSRuleFailed; Tone = $(if ($s.PSRuleFailed) { 'warn' } else { 'good' }); Note = 'PSRule for Azure on the apps and their plans.' }
            @{ Name = 'Recommendations'; Badge = @($r.Recommendations).Count; Tone = 'warn'; Note = 'Azure Advisor and Defender for Cloud.' }
            @{ Name = 'Findings'; Badge = @($r.Findings).Count; Tone = $(if ($s.High) { 'bad' } else { 'warn' }); Note = 'What to act on, worst first - for IT security, filter the Security pillar.' }
        )
        Tables   = @(
            @{ Id = 'service'; Title = 'Service summary'; Section = 'Service summary'; Rows = @($r.Apps); Noun = 'apps'; GroupBy = @('Health', 'Environment', 'Subscription'); ConsoleLimit = 20
                HoverTitle = 'App'; Hover = @('Health', 'State', 'Hosting', 'Executions', 'Requests', 'ErrorRate', 'AvgResponseMs', 'LastDeployment', 'Changes', 'High', 'Owner', 'Environment', 'CostCenter')
                Columns = @(
                    @{ Key = 'App'; Label = 'App'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Health'; Label = 'Health'; Type = 'badge'; Tones = $healthTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'State'; Label = 'State'; Facet = $true }
                    @{ Key = 'Score'; Label = 'WAF'; Type = 'score'; Format = 'N0'; Console = $true; Pdf = $true }
                    $n0 + @{ Key = 'Executions'; Label = 'Executions'; Sum = $true; Console = $true; Pdf = $true }
                    $n0 + @{ Key = 'Requests'; Label = 'Requests'; Sum = $true }
                    @{ Key = 'ErrorRate'; Label = '5xx %'; Type = 'number'; Format = 'N2'; Console = $true; Pdf = $true }
                    $n0 + @{ Key = 'AvgResponseMs'; Label = 'Avg ms'; Console = $true }
                    @{ Key = 'LastDeployment'; Label = 'Last deployment'; Type = 'datetime'; Console = $true; Pdf = $true }
                    $n0 + @{ Key = 'Changes'; Label = 'Changes'; Sum = $true; Console = $true }
                    $n0 + @{ Key = 'High'; Label = 'High'; Sum = $true; Console = $true; Pdf = $true }
                    $n0 + @{ Key = 'Findings'; Label = 'Findings'; Sum = $true }
                    @{ Key = 'Owner'; Label = 'Owner'; Facet = $true; Pdf = $true }
                    @{ Key = 'Environment'; Label = 'Environment'; Facet = $true }
                    @{ Key = 'CostCenter'; Label = 'Cost center'; Facet = $true; Hidden = $true }
                    @{ Key = 'Hosting'; Label = 'Hosting'; Hidden = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                ) }
            @{ Id = 'apps'; Title = 'Apps'; Section = 'Apps & plans'; Rows = @($r.Apps); Noun = 'apps'; GroupBy = @('Hosting', 'RuntimeSupport', 'Plan'); ConsoleLimit = 20
                HoverTitle = 'App'; Hover = @('Hosting', 'Plan', 'Sku', 'Os', 'Runtime', 'RuntimeSupport', 'RuntimeEnds', 'FunctionsVersion', 'Model', 'Triggers', 'Identity', 'Inbound', 'Slots', 'Deployment', 'AppInsights')
                Columns = @(
                    @{ Key = 'App'; Label = 'App'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Score'; Label = 'WAF'; Type = 'score'; Format = 'N0'; Console = $true; Pdf = $true }
                    @{ Key = 'Hosting'; Label = 'Hosting'; Type = 'badge'; Tones = $hostingTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Plan'; Label = 'Plan'; Facet = $true }
                    @{ Key = 'Os'; Label = 'OS'; Facet = $true }
                    @{ Key = 'Runtime'; Label = 'Runtime'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'RuntimeSupport'; Label = 'Support'; Type = 'badge'; Tones = $supportTones; Facet = $true; Console = $true; Pdf = $true; Tip = 'RuntimeEnds' }
                    @{ Key = 'FunctionsVersion'; Label = 'Functions'; Facet = $true }
                    @{ Key = 'Model'; Label = '.NET model'; Facet = $true }
                    $n0 + @{ Key = 'Functions'; Label = 'Functions'; Sum = $true; Console = $true; Tip = 'Triggers' }
                    @{ Key = 'Triggers'; Label = 'Triggers'; Type = 'wide' }
                    @{ Key = 'Identity'; Label = 'Identity'; Facet = $true }
                    @{ Key = 'Inbound'; Label = 'Inbound'; Type = 'badge'; Tones = $inboundTones; Facet = $true; Console = $true }
                    $n0 + @{ Key = 'Slots'; Label = 'Slots' }
                    @{ Key = 'AppInsights'; Label = 'App Insights'; Type = 'badge'; Tones = $yes; Facet = $true }
                    @{ Key = 'RuntimeEnds'; Label = 'Support ends'; Type = 'date'; Soon = $true }
                    @{ Key = 'Sku'; Label = 'SKU'; Hidden = $true }
                    @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                    @{ Key = 'Location'; Label = 'Location'; Facet = $true }
                ) }
            @{ Id = 'plans'; Title = 'App Service plans'; Section = 'Apps & plans'; Rows = @($r.Plans); Noun = 'plans'; ConsoleLimit = 15
                HoverTitle = 'Plan'; Hover = @('Hosting', 'Sku', 'Tier', 'Os', 'Instances', 'MaximumBurst', 'ZoneRedundant', 'Apps', 'FunctionApps', 'CpuAvg', 'CpuMax', 'MemoryMax')
                Columns = @(
                    @{ Key = 'Plan'; Label = 'Plan'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Hosting'; Label = 'Hosting'; Type = 'badge'; Tones = $hostingTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Sku'; Label = 'SKU'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Instances'; Label = 'Instances'; Type = 'number'; Console = $true }
                    @{ Key = 'MaximumBurst'; Label = 'Max burst'; Type = 'number' }
                    @{ Key = 'ZoneRedundant'; Label = 'Zone redundant'; Type = 'badge'; Tones = $yes; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Apps'; Label = 'Apps'; Type = 'number'; Console = $true }
                    @{ Key = 'CpuMax'; Label = 'CPU max %'; Type = 'number'; Format = 'N1'; Console = $true; Pdf = $true }
                    @{ Key = 'MemoryMax'; Label = 'Memory max %'; Type = 'number'; Format = 'N1'; Console = $true }
                    @{ Key = 'FunctionApps'; Label = 'Function apps'; Type = 'wide' }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                ) }
            @{ Id = 'usage'; Title = 'Usage'; Section = 'Usage'; Rows = @($r.Apps | Sort-Object -Property @{ Expression = { $_.Executions }; Descending = $true }, App); Noun = 'apps'; ConsoleLimit = 20
                HoverTitle = 'App'; Hover = @('Hosting', 'Executions', 'GbSeconds', 'Requests', 'Http5xx', 'Http4xx', 'ErrorRate', 'AvgResponseMs', 'MemoryAvgMB', 'MemoryMaxMB', 'EstimatedMonthlyUsd', 'Idle')
                Columns = @(
                    @{ Key = 'App'; Label = 'App'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Hosting'; Label = 'Hosting'; Facet = $true; Console = $true }
                    $n0 + @{ Key = 'Executions'; Label = 'Executions'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'GbSeconds'; Label = 'GB-seconds'; Type = 'number'; Format = 'N1'; Sum = $true; Console = $true; Pdf = $true }
                    $n0 + @{ Key = 'Requests'; Label = 'Requests'; Sum = $true; Console = $true; Pdf = $true }
                    $n0 + @{ Key = 'Http5xx'; Label = '5xx'; Sum = $true; Console = $true }
                    $n0 + @{ Key = 'Http4xx'; Label = '4xx'; Sum = $true }
                    @{ Key = 'ErrorRate'; Label = '5xx %'; Type = 'number'; Format = 'N2'; Console = $true; Pdf = $true }
                    $n0 + @{ Key = 'AvgResponseMs'; Label = 'Avg ms'; Console = $true }
                    $n0 + @{ Key = 'MemoryAvgMB'; Label = 'Memory avg MB' }
                    $n0 + @{ Key = 'MemoryMaxMB'; Label = 'Memory max MB'; Console = $true }
                    @{ Key = 'EstimatedMonthlyUsd'; Label = 'Est. USD / month'; Type = 'number'; Format = 'N2'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Idle'; Label = 'Idle'; Type = 'badge'; Tones = @{ True = 'warn'; False = 'good' }; Facet = $true; Console = $true }
                ) }
            @{ Id = 'functions'; Title = 'Functions'; Section = 'Functions'; Rows = @($r.Functions); Noun = 'functions'; GroupBy = @('App', 'Trigger', 'AuthLevel'); ConsoleLimit = 25
                Empty = 'No function listed (stopped apps, or hosts that can''t be reached).'; EmptyStatus = 'Info'
                HoverTitle = 'Function'; Hover = @('Trigger', 'AuthLevel', 'Schedule', 'Inputs', 'Outputs', 'Connection', 'Disabled', 'InvokeUrl')
                Columns = @(
                    @{ Key = 'App'; Label = 'App'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Function'; Label = 'Function'; Console = $true; Pdf = $true }
                    @{ Key = 'Trigger'; Label = 'Trigger'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'AuthLevel'; Label = 'Auth level'; Type = 'badge'; Tones = @{ anonymous = 'bad'; function = 'good'; admin = 'good' }; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Schedule'; Label = 'Schedule'; Type = 'mono'; Console = $true }
                    @{ Key = 'Inputs'; Label = 'Inputs' }
                    @{ Key = 'Outputs'; Label = 'Outputs' }
                    @{ Key = 'Connection'; Label = 'Connection setting'; Type = 'mono' }
                    @{ Key = 'Disabled'; Label = 'Disabled'; Type = 'badge'; Tones = @{ True = 'warn'; False = 'neutral' }; Facet = $true }
                    @{ Key = 'InvokeUrl'; Label = 'URL'; Type = 'mono'; Hidden = $true }
                ) }
            @{ Id = 'settings'; Title = 'Configuration'; Section = 'Configuration'; Rows = @($r.Settings); Noun = 'settings'; GroupBy = @('App', 'Area'); Group = 'Area'; ConsoleLimit = 30; NoConsole = $true
                HoverTitle = 'Setting'; Hover = @('App', 'Area', 'Value')
                Columns = @(
                    @{ Key = 'App'; Label = 'App'; Facet = $true; Pdf = $true }
                    @{ Key = 'Area'; Label = 'Area'; Facet = $true; Pdf = $true }
                    @{ Key = 'Setting'; Label = 'Setting'; Pdf = $true }
                    @{ Key = 'Value'; Label = 'Value'; Type = 'wide'; Pdf = $true }
                ) }
            @{ Id = 'appsettings'; Title = 'App settings (names and kinds)'; Section = 'Configuration'; Rows = @($r.AppSettings); Noun = 'app settings'; GroupBy = @('App', 'Kind'); ConsoleLimit = 30; NoConsole = $true
                Empty = 'App settings weren''t read (they need Website Contributor, or -SkipSettings was given).'; EmptyStatus = 'Info'
                HoverTitle = 'Setting'; Hover = @('App', 'Kind', 'HasValue')
                Columns = @(
                    @{ Key = 'App'; Label = 'App'; Facet = $true }
                    @{ Key = 'Setting'; Label = 'Setting'; Type = 'mono' }
                    @{ Key = 'Kind'; Label = 'Kind'; Type = 'badge'; Tones = $kindTones; Facet = $true }
                    @{ Key = 'HasValue'; Label = 'Has a value'; Facet = $true }
                ) }
            @{ Id = 'network'; Title = 'Networking'; Section = 'Networking'; Rows = @($r.Networks); Noun = 'apps'; GroupBy = @('Inbound'); ConsoleLimit = 20
                HoverTitle = 'App'; Hover = @('Inbound', 'PublicNetworkAccess', 'AccessRules', 'DefaultAction', 'ScmRules', 'ScmUsesMainRules', 'PrivateEndpoints', 'VnetIntegration', 'RouteAll', 'OutboundIps', 'Cors', 'ClientCertificates')
                Columns = @(
                    @{ Key = 'App'; Label = 'App'; Console = $true; Pdf = $true }
                    @{ Key = 'Inbound'; Label = 'Inbound'; Type = 'badge'; Tones = $inboundTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'PublicNetworkAccess'; Label = 'Public access'; Facet = $true; Console = $true }
                    $n0 + @{ Key = 'AccessRules'; Label = 'Allow rules'; Console = $true }
                    @{ Key = 'DefaultAction'; Label = 'Default'; Facet = $true }
                    $n0 + @{ Key = 'ScmRules'; Label = 'SCM rules' }
                    @{ Key = 'ScmUsesMainRules'; Label = 'SCM uses main rules'; Facet = $true }
                    $n0 + @{ Key = 'PrivateEndpoints'; Label = 'Private endpoints'; Console = $true; Pdf = $true }
                    @{ Key = 'VnetIntegration'; Label = 'VNet integration'; Console = $true; Pdf = $true }
                    @{ Key = 'RouteAll'; Label = 'Route all'; Facet = $true }
                    $n0 + @{ Key = 'OutboundIps'; Label = 'Outbound IPs' }
                    @{ Key = 'Cors'; Label = 'CORS'; Type = 'wide' }
                ) }
            @{ Id = 'deployments'; Title = 'Deployments'; Section = 'Deployment'; Rows = @($r.Deployments); Noun = 'deployments'; GroupBy = @('App', 'Status'); ConsoleLimit = 15
                Empty = 'No deployment record.'; EmptyStatus = 'Info'
                HoverTitle = 'App'; Hover = @('Time', 'Status', 'Author', 'Deployer', 'Message', 'Active')
                Columns = @(
                    @{ Key = 'App'; Label = 'App'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Time'; Label = 'When'; Type = 'datetime'; Console = $true; Pdf = $true }
                    @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = @{ Succeeded = 'good'; Failed = 'bad' }; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Deployer'; Label = 'Deployer'; Facet = $true; Console = $true }
                    @{ Key = 'Author'; Label = 'Author'; Facet = $true }
                    @{ Key = 'Message'; Label = 'Message'; Type = 'wide' }
                ) }
            @{ Id = 'slots'; Title = 'Deployment slots'; Section = 'Deployment'; Rows = @($r.Slots); Noun = 'slots'; ConsoleLimit = 15
                Empty = 'No deployment slot.'; EmptyStatus = 'Info'
                HoverTitle = 'Slot'; Hover = @('App', 'State', 'HostName', 'HttpsOnly', 'LastModified')
                Columns = @(
                    @{ Key = 'App'; Label = 'App'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Slot'; Label = 'Slot'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'State'; Label = 'State'; Facet = $true; Console = $true }
                    @{ Key = 'HttpsOnly'; Label = 'HTTPS only'; Type = 'badge'; Tones = $yes; Facet = $true }
                    @{ Key = 'LastModified'; Label = 'Last modified'; Type = 'datetime' }
                    @{ Key = 'HostName'; Label = 'Host name'; Type = 'mono' }
                ) }
            @{ Id = 'backups'; Title = 'Backups'; Section = 'Backups & connections'; Rows = @($r.Backups); Noun = 'apps'; ConsoleLimit = 15
                HoverTitle = 'App'; Hover = @('Hosting', 'Supported', 'Backups', 'LastBackup', 'LastStatus', 'Note')
                Columns = @(
                    @{ Key = 'App'; Label = 'App'; Console = $true; Pdf = $true }
                    @{ Key = 'Supported'; Label = 'Supported'; Facet = $true; Console = $true }
                    $n0 + @{ Key = 'Backups'; Label = 'Backups'; Console = $true; Pdf = $true }
                    @{ Key = 'LastBackup'; Label = 'Last backup'; Type = 'datetime'; Console = $true; Pdf = $true }
                    @{ Key = 'LastStatus'; Label = 'Status'; Facet = $true }
                    @{ Key = 'Note'; Label = 'Note'; Type = 'wide' }
                ) }
            @{ Id = 'connections'; Title = 'Connections'; Section = 'Backups & connections'; Rows = @($r.Connections); Noun = 'connections'; GroupBy = @('App', 'TargetType', 'Auth'); ConsoleLimit = 20
                Empty = 'No Service Connector connection, and no service named in the settings read.'; EmptyStatus = 'Info'
                HoverTitle = 'Target'; Hover = @('App', 'Source', 'Name', 'TargetType', 'Auth')
                Columns = @(
                    @{ Key = 'App'; Label = 'App'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Source'; Label = 'Found in'; Facet = $true }
                    @{ Key = 'Target'; Label = 'Service'; Console = $true; Pdf = $true }
                    @{ Key = 'TargetType'; Label = 'Type'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Auth'; Label = 'Authentication'; Type = 'badge'; Tones = @{ 'Managed identity' = 'good'; systemAssignedIdentity = 'good'; userAssignedIdentity = 'good'; 'Managed identity (Key Vault reference)' = 'good'; 'Account key' = 'warn'; 'Shared access key' = 'warn'; secret = 'warn' }; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Name'; Label = 'Setting / connection'; Type = 'mono' }
                ) }
            @{ Id = 'activity'; Title = 'Activity Log'; Section = 'Activity Log'; Rows = @($r.Activity); Noun = 'operations'; GroupBy = @('App', 'Kind', 'Caller', 'Status'); ConsoleLimit = 25
                Empty = "No management operation in the last $ActivityDays day(s)."; EmptyStatus = 'Info'
                HoverTitle = 'Operation'; Hover = @('App', 'Time', 'Kind', 'Status', 'Caller', 'Category', 'CorrelationId')
                Columns = @(
                    @{ Key = 'Time'; Label = 'When'; Type = 'datetime'; Console = $true; Pdf = $true }
                    @{ Key = 'App'; Label = 'App'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Kind'; Label = 'Kind'; Type = 'badge'; Tones = $activityTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Operation'; Label = 'Operation'; Type = 'wide'; Console = $true }
                    @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = @{ Succeeded = 'good'; Failed = 'bad'; Started = 'info' }; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Caller'; Label = 'Caller'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Category'; Label = 'Category'; Facet = $true; Hidden = $true }
                    @{ Key = 'CorrelationId'; Label = 'Correlation ID'; Type = 'mono'; Hidden = $true }
                ) }
            @{ Id = 'pillars'; Title = 'Pillars'; Section = 'Well-Architected'; Rows = @($r.Pillars); Noun = 'pillars'; ConsoleLimit = 5
                HoverTitle = 'Pillar'; Hover = @('Score', 'Passed', 'Failed', 'Checks', 'Findings')
                Columns = @(
                    @{ Key = 'Pillar'; Label = 'Pillar'; Console = $true; Pdf = $true }
                    @{ Key = 'Score'; Label = 'Score'; Type = 'score'; Format = 'N0'; Console = $true; Pdf = $true }
                    $n0 + @{ Key = 'Passed'; Label = 'Passed'; Sum = $true; Console = $true; Pdf = $true }
                    $n0 + @{ Key = 'Failed'; Label = 'Failed'; Sum = $true; Console = $true; Pdf = $true }
                    $n0 + @{ Key = 'Findings'; Label = 'Findings'; Sum = $true }
                ) }
            @{ Id = 'checks'; Title = 'Checks'; Section = 'Well-Architected'; Rows = @($r.Checks); Noun = 'checks'; GroupBy = @('Pillar', 'Check', 'Status', 'App'); Filters = @{ Status = 'Fail' }; ConsoleLimit = 25; NoConsole = $true
                HoverTitle = 'Check'; Hover = @('App', 'Pillar', 'Status', 'Severity', 'Detail', 'Recommendation')
                Columns = @(
                    @{ Key = 'App'; Label = 'App'; Facet = $true; Pdf = $true }
                    @{ Key = 'Pillar'; Label = 'Pillar'; Facet = $true; Pdf = $true }
                    @{ Key = 'Check'; Label = 'Check'; Facet = $true; Pdf = $true }
                    @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = $checkTones; Facet = $true; Pdf = $true }
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true }
                    @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide' }
                    @{ Key = 'Recommendation'; Label = 'What to do'; Type = 'wide' }
                ) }
            @{ Id = 'psrule'; Title = 'PSRule for Azure'; Section = 'PSRule'; Rows = @($r.PSRule); Noun = 'rule results'; GroupBy = @('Outcome', 'Pillar', 'RuleName'); Filters = @{ Outcome = 'Fail' }; ConsoleLimit = 20; NoConsole = $true
                Empty = 'PSRule for Azure wasn''t run (-SkipPSRule, or not installed).'; EmptyStatus = 'Info'
                HoverTitle = 'RuleName'; Hover = @('ResourceName', 'Outcome', 'Pillar', 'Severity', 'Title', 'Reason', 'Recommendation')
                Columns = @(
                    @{ Key = 'ResourceName'; Label = 'Resource'; Facet = $true; Pdf = $true }
                    @{ Key = 'RuleName'; Label = 'Rule'; Type = 'link'; Href = 'Link'; Pdf = $true }
                    @{ Key = 'Outcome'; Label = 'Outcome'; Type = 'badge'; Tones = @{ Pass = 'good'; Fail = 'bad'; Error = 'warn' }; Facet = $true; Pdf = $true }
                    @{ Key = 'Pillar'; Label = 'Pillar'; Facet = $true }
                    @{ Key = 'Severity'; Label = 'Severity'; Facet = $true }
                    @{ Key = 'Title'; Label = 'Rule title'; Type = 'wide'; Hidden = $true }
                    @{ Key = 'Reason'; Label = 'Reason'; Type = 'wide' }
                    @{ Key = 'Recommendation'; Label = 'What to do'; Type = 'wide' }
                    @{ Key = 'Link'; Label = 'Link'; Hidden = $true }
                ) }
            @{ Id = 'recommendations'; Title = 'Recommendations'; Section = 'Recommendations'; Rows = @($r.Recommendations); Noun = 'recommendations'; GroupBy = @('Source', 'Category'); ConsoleLimit = 15
                Empty = 'No Advisor or Defender for Cloud recommendation for these apps.'; EmptyStatus = 'Success'
                HoverTitle = 'Recommendation'; Hover = @('App', 'Source', 'Category', 'Impact', 'Action')
                Columns = @(
                    @{ Key = 'App'; Label = 'App'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Source'; Label = 'Source'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Category'; Label = 'Category'; Facet = $true }
                    @{ Key = 'Impact'; Label = 'Impact'; Facet = $true; Console = $true }
                    @{ Key = 'Recommendation'; Label = 'Recommendation'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'Action'; Label = 'What to do'; Type = 'wide' }
                ) }
            @{ Id = 'findings'; Title = 'Findings'; Section = 'Findings'; Rows = @($r.Findings); Noun = 'findings'; GroupBy = @('Finding', 'Severity', 'Pillar', 'App', 'Source'); ConsoleLimit = 25
                Empty = 'Nothing to act on.'; EmptyStatus = 'Success'
                HoverTitle = 'Finding'; Hover = @('App', 'Severity', 'Pillar', 'Source', 'Detail', 'Recommendation')
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'App'; Label = 'App'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Pillar'; Label = 'Pillar'; Facet = $true; Console = $true }
                    @{ Key = 'Finding'; Label = 'Finding'; Facet = $true; Console = $true; Pdf = $true; Tip = 'Detail' }
                    @{ Key = 'Source'; Label = 'Source'; Facet = $true }
                    @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Recommendation'; Label = 'What to do'; Type = 'wide'; Pdf = $true }
                ) }
        )
        Hint     = '-View Function, Activity, Check, Finding (and more) returns those rows; -TimeRange 30d looks further back for usage; -ActivityDays 30 for changes; -Name narrows it; -HtmlPath, -PdfPath or -CsvPath for a report.'
    }
    $rows = @(switch ($View) {
            'Plan' { $r.Plans } 'Function' { $r.Functions } 'Setting' { $r.Settings } 'AppSetting' { $r.AppSettings } 'Slot' { $r.Slots } 'Deployment' { $r.Deployments }
            'Network' { $r.Networks } 'Backup' { $r.Backups } 'Connection' { $r.Connections } 'Activity' { $r.Activity } 'Check' { $r.Checks } 'PSRule' { $r.PSRule }
            'Recommendation' { $r.Recommendations } 'Finding' { $r.Findings } default { $r.Apps }
        })
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $rows -Noun $View.ToLowerInvariant() -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $rows -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
