function Get-AACConfigurationDrift {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Finds configuration drift: what's deployed against what it should be
        - a baseline you saved, desired-state rules (yours, or a built-in
        security baseline), or your Terraform code - with who or what changed
        it, how to put it right, and whether drift is trending better or
        worse.
    .DESCRIPTION
        Desired state, one or more of:
          -BaselinePath      a snapshot saved earlier with -SaveBaseline:
                             every setting of every resource (SKU, tags,
                             properties - not provisioning states, timestamps
                             or counters) compared; resources created or
                             deleted since
          -DesiredStatePath  your rules (.psd1 or .json): a resource type, a
                             setting, what it must be (Equals, NotEquals, In,
                             Match, Exists), a severity and the fix
          -UseDefaultRules   a built-in security baseline: TLS 1.2, HTTPS
                             only, no anonymous blob access, soft delete and
                             purge protection, RBAC, no local or shared-key
                             authentication, no admin users...
          -TerraformPlanPath a plan's JSON (terraform show -json plan.out):
                             its resource_drift - what changed outside
                             Terraform
        -SaveBaseline writes today's snapshot, for the next run's
        -BaselinePath (it can be the same file: compare, then save).

        Why it drifted: Resource Graph's change history (14 days) - who
        changed the setting, when, and whether a person (Manual), an
        application or pipeline (Automation) or Azure (a platform update).
        The strategy follows: Fix (a rule), Revert or Re-deploy (a manual
        change), Update the baseline (an intended or platform change),
        Review (unknown).

        -HistoryPath keeps a CSV line per run - resources checked, drifted,
        high - and the report shows whether drift is better or worse than
        last time.

        Read-only: nothing is changed or remediated; the fixes are the
        operator's to apply (through infrastructure as code, ideally).
        Reader is enough.
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups (at any depth).
    .PARAMETER ResourceGroupName
        Only these resource groups.
    .PARAMETER ResourceType
        Only these resource types (wildcards work).
    .PARAMETER BaselinePath
        A snapshot saved earlier with -SaveBaseline, to compare with.
    .PARAMETER SaveBaseline
        Save today's snapshot to this file.
    .PARAMETER DesiredStatePath
        Desired-state rules (.psd1 or .json).
    .PARAMETER UseDefaultRules
        Check the built-in security baseline too.
    .PARAMETER TerraformPlanPath
        A Terraform plan in JSON: its resource_drift.
    .PARAMETER HistoryPath
        A CSV file that keeps a line per run, for the trend.
    .PARAMETER MaxResources
        At most this many resources (1 to 20000; 5000 by default).
    .PARAMETER CsvPath
        Write the drift to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report.
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the drift.
    .PARAMETER NoDisplay
        Return the drift without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Get-AACConfigurationDrift -ResourceGroupName 'rg-app-prod' -SaveBaseline .\baseline\app-prod.json
        Save the production app's configuration as its baseline.
    .EXAMPLE
        Get-AACConfigurationDrift -ResourceGroupName 'rg-app-prod' -BaselinePath .\baseline\app-prod.json -HistoryPath .\baseline\history.csv
        What changed since, who changed it, and the trend.
    .EXAMPLE
        Get-AACConfigurationDrift -UseDefaultRules -DesiredStatePath .\desired.psd1 -HtmlPath .\out\Drift.html
        The built-in security baseline and your own rules, as a report.
    .EXAMPLE
        terraform show -json plan.out > plan.json; Get-AACConfigurationDrift -TerraformPlanPath .\plan.json
        What changed outside Terraform, and who changed it.
    .OUTPUTS
        AAC.ConfigurationDrift
    #>
    [CmdletBinding()]
    [OutputType('AAC.ConfigurationDrift')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string[]] $ManagementGroupId,

        [string[]] $ResourceGroupName,

        [SupportsWildcards()]
        [string[]] $ResourceType,

        [string] $BaselinePath,

        [string] $SaveBaseline,

        [string] $DesiredStatePath,

        [switch] $UseDefaultRules,

        [string] $TerraformPlanPath,

        [string] $HistoryPath,

        [ValidateRange(1, 20000)]
        [int] $MaxResources = 5000,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Configuration drift',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    if (-not ($BaselinePath -or $SaveBaseline -or $DesiredStatePath -or $UseDefaultRules -or $TerraformPlanPath)) {
        $problem = [System.ArgumentException]::new('Nothing to compare with.')
        $problem.Data['AACHint'] = 'Give a desired state: -UseDefaultRules, -DesiredStatePath, -BaselinePath (saved earlier with -SaveBaseline) or -TerraformPlanPath.'
        throw $problem
    }
    # Read the files first, so a bad one fails before any Azure call.
    $baseline = $null
    $baselineInfo = ''
    if ($BaselinePath) {
        $file = & $resolve $BaselinePath
        if (-not (Test-Path -LiteralPath $file)) { throw "The baseline $file doesn't exist. Save one first with -SaveBaseline." }
        $saved = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -AsHashtable -Depth 50
        if ($saved -isnot [System.Collections.IDictionary] -or -not $saved.Contains('Resources')) { throw "$file isn't a baseline saved by Get-AACConfigurationDrift -SaveBaseline." }
        $baseline = @{}
        foreach ($k in $saved['Resources'].Keys) { $entry = $saved['Resources'][$k]; $baseline[$k] = @{ Type = [string]$entry['Type']; Name = [string]$entry['Name']; Settings = $(if ($entry['Settings']) { $entry['Settings'] } else { @{} }) } }
        $baselineInfo = "$(Split-Path -Leaf $file), saved $([string]$saved['CapturedAt'])"
    }
    $rules = @(Get-AACDriftRule -Path (& $resolve $DesiredStatePath) -Default:$UseDefaultRules)
    $terraform = @()
    if ($TerraformPlanPath) {
        $planFile = & $resolve $TerraformPlanPath
        if (-not (Test-Path -LiteralPath $planFile)) { throw "The Terraform plan $planFile doesn't exist." }
        $plan = Get-Content -LiteralPath $planFile -Raw | ConvertFrom-Json -AsHashtable -Depth 100
        if ($plan -isnot [System.Collections.IDictionary] -or -not ($plan.Contains('resource_changes') -or $plan.Contains('resource_drift') -or $plan.Contains('format_version'))) { throw "$planFile isn't a Terraform plan in JSON: make one with terraform show -json plan.out." }
        $terraform = @($plan['resource_drift'] | Where-Object { $_ })
    }
    $request = @{
        SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }); ResourceGroupName = @($ResourceGroupName | Where-Object { $_ })
        ResourceType = @($ResourceType | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() }); MaxResources = $MaxResources
    }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Configuration drift' -Color 'deepskyblue3_1' }
    $state = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
        $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
        Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"
        $quote = { param([string] $Text) "'" + ($Text -replace "'", "\'") + "'" }
        $filters = @(
            if ($request.ResourceGroupName.Count) { "resourceGroup in~ ($((@($request.ResourceGroupName | ForEach-Object { & $quote $_ })) -join ', '))" }
            if ($request.ResourceType.Count) { "($((@($request.ResourceType | ForEach-Object { "tolower(type) matches regex @'^$([regex]::Escape($_) -replace '\\\*', '.*')$'" })) -join ' or '))" }
        )
        $where = if ($filters.Count) { " | where $($filters -join ' and ')" } else { '' }
        $queries = [ordered]@{ resources = "resources$where | project id, name, type, location, sku, kind, tags, identity, properties | take $($request.MaxResources)" }
        $queries['changes'] = "resourcechanges | extend p = properties | extend at = todatetime(p.changeAttributes.timestamp) | where at > ago(14d) | extend resourceId = tolower(tostring(p.targetResourceId))$(if ($request.ResourceGroupName.Count) { " | where tostring(split(resourceId, '/')[4]) in~ ($((@($request.ResourceGroupName | ForEach-Object { & $quote $_.ToLowerInvariant() })) -join ', '))" }) | project id, at, resourceId, changedBy = tostring(p.changeAttributes.changedBy), clientType = tostring(p.changeAttributes.clientType), changes = p.changes"
        Update-AACProgress -Id 'read' -Total $queries.Count -Description 'Reading the configuration and its change history'
        $read = Invoke-AACGraphBatch -Query $queries -SubscriptionId $scope.GraphScope -AllowFailure @('changes') -OnProgress { param($Name, $Done, $Total) Update-AACProgress -Id 'read' -Increment 1 -Description "Read the $Name ($Done of $Total)" }
        $notices = [System.Collections.Generic.List[string]]::new()
        if ($read.Errors['changes']) { $notices.Add("The change history couldn't be read, so who changed what is unknown: $($read.Errors['changes'])") }
        $resources = @($read.Rows['resources'] | Where-Object { $_ })
        if ($resources.Count -ge $request.MaxResources) { $notices.Add("Only $($request.MaxResources) resources were read (-MaxResources): narrow the scope for the rest.") }
        Update-AACProgress -Id 'read' -Complete -Description ('Read {0:N0} resource(s) and {1:N0} recorded change(s)' -f $resources.Count, @($read.Rows['changes']).Count)
        Update-AACProgress -Id 'drift' -Indeterminate -Description 'Comparing with the desired state'
        $snapshot = ConvertTo-AACConfigurationSnapshot -Resource $resources
        $driftArgs = @{ Current = $snapshot; Rule = $rules; TerraformDrift = $terraform; Change = @($read.Rows['changes'] | Where-Object { $_ }); SubscriptionName = $scope.Names }
        if ($null -ne $baseline) { $driftArgs.Baseline = $baseline }
        $result = ConvertTo-AACConfigurationDrift @driftArgs
        Update-AACProgress -Id 'drift' -Complete -Description ('{0:N0} resource(s) checked: {1:N0} drifted, {2:N0} item(s), {3:N0} high' -f $result.Stats.Checked, $result.Stats.Resources, $result.Stats.Items, $result.Stats.High)
        @{ Result = $result; Scope = $scope; Snapshot = $snapshot; Notices = $notices }
    }

    $result = $state.Result
    $drift = @($result.Drift)
    $s = $result.Stats
    $notices = $state.Notices
    # Today's snapshot - after the comparison, so the same file can be compared with, then replaced.
    if ($SaveBaseline) {
        $target = & $resolve $SaveBaseline
        $folder = Split-Path -Path $target -Parent
        if ($folder -and -not (Test-Path -LiteralPath $folder)) { $null = New-Item -ItemType Directory -Path $folder -Force }
        $json = ConvertTo-Json -InputObject ([ordered]@{ Version = 1; CapturedAt = [datetime]::UtcNow.ToString('o'); Scope = $state.Scope.Label; Resources = $state.Snapshot }) -Depth 10 -Compress
        [System.IO.File]::WriteAllText($target, $json, [System.Text.UTF8Encoding]::new($false))
        $notices.Add("Baseline saved: $($state.Snapshot.Count) resource(s) in $target.")
    }
    # The trend: a line per run.
    $history = @()
    if ($HistoryPath) {
        $historyFile = & $resolve $HistoryPath
        if (Test-Path -LiteralPath $historyFile) { $history = @(Import-Csv -LiteralPath $historyFile) }
        $line = [pscustomobject][ordered]@{ Date = [datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm'); Scope = $state.Scope.Label; Checked = $s.Checked; Drifted = $s.Resources; Items = $s.Items; High = $s.High; Manual = $s.Manual }
        $folder = Split-Path -Path $historyFile -Parent
        if ($folder -and -not (Test-Path -LiteralPath $folder)) { $null = New-Item -ItemType Directory -Path $folder -Force }
        $line | Export-Csv -LiteralPath $historyFile -NoTypeInformation -Append -Encoding utf8
        $history = @($history) + $line
    }
    $trend = if ($history.Count -ge 2) {
        $previous = $history[-2]
        $delta = [int]$s.Items - [int]$previous.Items
        if ($delta -lt 0) { "better: $(-$delta) fewer drift item(s) than on $($previous.Date)" } elseif ($delta -gt 0) { "worse: $delta more drift item(s) than on $($previous.Date)" } else { "unchanged since $($previous.Date)" }
    }
    $rank = Get-AACSeverityRank
    $strategyTones = @{ Fix = 'bad'; Revert = 'warn'; 'Re-deploy' = 'warn'; 'Update the baseline' = 'info'; Review = 'neutral' }
    $sources = @(if ($BaselinePath) { "baseline ($baselineInfo)" }; if ($DesiredStatePath) { "rules ($(Split-Path -Leaf $DesiredStatePath))" }; if ($UseDefaultRules) { 'the built-in security baseline' }; if ($TerraformPlanPath) { "Terraform ($(Split-Path -Leaf $TerraformPlanPath))" })
    $report = @{
        Subtitle = 'Configuration drift: the deployed configuration against its desired state'
        Facts    = [ordered]@{ Scope = $state.Scope.Label; 'Desired state' = $(if ($sources.Count) { $sources -join '; ' } else { 'none - baseline saved only' }); Trend = $(if ($trend) { $trend } else { '-' }) }
        Status   = $(if ($s.High) { 'Failed' } elseif ($s.Items) { 'Warning' } else { 'Success' })
        Headline = $(if (-not $sources.Count) { "Baseline saved for $($s.Checked) resource(s): compare with it next time (-BaselinePath)." } elseif ($s.Items) { "$($s.Resources) of $($s.Checked) resource(s) drifted: $($s.Items) item(s), $($s.High) high, $($s.Manual) changed by hand$(if ($trend) { " - $trend" })" } else { "No drift: $($s.Checked) resource(s) match their desired state$(if ($trend) { " - $trend" })." })
        Tiles    = @(
            @{ Value = '{0:N0}' -f $s.Resources; Label = "drifted of $($s.Checked)"; Tone = $(if ($s.Resources) { 'warn' } else { 'good' }); Table = 'drift' }
            @{ Value = '{0:N0}' -f $s.High; Label = 'high'; Tone = $(if ($s.High) { 'bad' } else { 'good' }); Table = 'drift'; Filters = @{ Severity = 'High' } }
            @{ Value = '{0:N0}' -f $s.Violations; Label = 'rule violations'; Tone = $(if ($s.Violations) { 'bad' } else { 'good' }); Table = 'drift'; Filters = @{ Source = 'Rule' } }
            @{ Value = '{0:N0}' -f $s.Manual; Label = 'changed by hand'; Tone = $(if ($s.Manual) { 'warn' } else { 'good' }); Table = 'drift'; Filters = @{ Origin = 'Manual' } }
            @{ Value = $(if ($trend) { ($trend -split ':')[0] } else { '-' }); Label = 'since last run'; Tone = $(if ($trend -like 'better*') { 'good' } elseif ($trend -like 'worse*') { 'bad' } else { 'neutral' }) }
        )
        Notices  = @($notices | ForEach-Object { @{ Status = $(if ($_ -like 'Baseline saved*') { 'Success' } else { 'Warning' }); Text = $_ } })
        Charts   = @(
            @{ Title = 'Drift by strategy'; Kind = 'donut'; CenterLabel = 'items'; Items = @($drift | Group-Object Strategy | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Tone = $strategyTones[$_.Name]; Filter = $_.Name } }); Table = 'drift'; Column = 'Strategy'; Console = $true }
            @{ Title = 'Drift by origin'; Items = @($drift | Group-Object Origin | Sort-Object Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'drift'; Column = 'Origin'; Tone = 'warn' }
            @{ Title = 'Most drifted resources'; Items = @($drift | Group-Object Resource | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'drift'; Column = 'Resource'; Tone = 'violet' }
        )
        Tables   = @(
            @{ Id = 'drift'; Title = 'Drift'; Section = 'Drift'; Rows = $drift; Noun = 'items'; GroupBy = @('Resource', 'Source', 'Strategy', 'Origin', 'Severity'); ConsoleLimit = 30
                Empty = $(if ($sources.Count) { 'No drift: everything matches its desired state.' } else { 'Nothing compared: the baseline was saved.' }); EmptyStatus = $(if ($sources.Count) { 'Success' } else { 'Info' })
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Resource'; Label = 'Resource'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Category'; Label = 'Drift'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Property'; Label = 'Setting'; Type = 'mono'; Console = $true; Pdf = $true }
                    @{ Key = 'Detail'; Label = 'Expected -> actual'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'ChangedBy'; Label = 'Changed by'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Strategy'; Label = 'Strategy'; Type = 'badge'; Tones = $strategyTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'ChangedAt'; Label = 'Changed'; Type = 'datetime' }
                    @{ Key = 'Origin'; Label = 'Origin'; Type = 'badge'; Tones = @{ Manual = 'warn'; Automation = 'info'; Azure = 'neutral'; Unknown = 'neutral' }; Facet = $true }
                    @{ Key = 'Source'; Label = 'Source'; Facet = $true }
                    @{ Key = 'ResourceType'; Label = 'Type'; Type = 'mono'; Facet = $true }
                    @{ Key = 'Remediation'; Label = 'What to do'; Type = 'wide' }
                    @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                ) }
            @{ Id = 'history'; Title = 'History'; Section = 'History'; Rows = @($history); Noun = 'runs'; ConsoleLimit = 10
                Columns = @(@{ Key = 'Date'; Label = 'Date'; Console = $true }, @{ Key = 'Checked'; Label = 'Checked'; Console = $true }, @{ Key = 'Drifted'; Label = 'Drifted'; Console = $true }, @{ Key = 'Items'; Label = 'Items'; Console = $true }, @{ Key = 'High'; Label = 'High'; Console = $true }, @{ Key = 'Manual'; Label = 'By hand'; Console = $true }) }
        )
        Hint     = '-SaveBaseline, then -BaselinePath next time; -UseDefaultRules or -DesiredStatePath for rules; -TerraformPlanPath for Terraform; -HistoryPath for the trend.'
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $drift -Noun 'drift item' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $drift -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
