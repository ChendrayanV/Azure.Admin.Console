function Get-AACDependencyGraph {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Maps which Azure resources depend on which - networks, gateways and
        Front Door to their backends, apps to their plans and data, private
        endpoints, managed identities, and (from Application Insights) who
        calls whom - and finds each one's blast radius, the single points of
        failure, circular dependencies and the most critical services.
    .DESCRIPTION
        Builds the graph from one Azure Resource Graph batch: VMs on their
        disks and networks, load balancers and Application Gateways on their
        backend pools, Front Door on its origins, apps on their App Service
        plans and integration networks, SQL databases on their servers,
        private endpoints on their targets, and every resource whose managed
        identity has a role on another (the data it reads, the registry it
        pulls from). -IncludeTelemetry adds Application Insights' recorded
        dependencies (the last -TelemetryHours): which app calls which
        database, API or external service, how often, and how many calls
        failed.

        For each resource (AAC.DependencyNode): what it depends on, what
        depends on it, its blast radius (every resource that depends on it,
        directly or through others), whether it's redundant (zones, instances,
        SKU), and whether it's a single point of failure. Findings: single
        points of failure (High with a blast radius of 3 or more), circular
        dependencies, and the five most critical services - with the
        resilience fix for each: redundancy, failover, circuit breakers.

        -DotPath writes the graph in Graphviz DOT (dot -Tsvg graph.dot -o
        graph.svg); single points of failure are red. Read-only; Reader is
        enough (and Log Analytics Reader for -IncludeTelemetry).
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups (at any depth).
    .PARAMETER ResourceGroupName
        Only the resources in these resource groups (and what they depend on).
    .PARAMETER IncludeTelemetry
        Add the dependencies Application Insights recorded (workspace-based
        components).
    .PARAMETER TelemetryHours
        How far back the telemetry goes (1 to 720 hours; 24 by default).
    .PARAMETER DotPath
        Write the graph in Graphviz DOT to this file.
    .PARAMETER CsvPath
        Write the resources (nodes) to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report: findings, resources and every
        dependency.
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
        Get-AACDependencyGraph -ResourceGroupName 'rg-shop-prod' -IncludeTelemetry
        The shop's dependencies, with who calls whom.
    .EXAMPLE
        Get-AACDependencyGraph -DotPath .\out\deps.dot; dot -Tsvg .\out\deps.dot -o .\out\deps.svg
        The graph as a picture (with Graphviz).
    .EXAMPLE
        Get-AACDependencyGraph -NoDisplay | Where-Object SinglePointOfFailure -EQ 'Yes' | Sort-Object BlastRadius -Descending
        The single points of failure, the widest first.
    .OUTPUTS
        AAC.DependencyNode
    #>
    [CmdletBinding()]
    [OutputType('AAC.DependencyNode')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string[]] $ManagementGroupId,

        [string[]] $ResourceGroupName,

        [switch] $IncludeTelemetry,

        [ValidateRange(1, 720)]
        [int] $TelemetryHours = 24,

        [string] $DotPath,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Azure dependency graph',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $dotFile = & $resolve $DotPath
    $request = @{ SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }); ResourceGroupName = @($ResourceGroupName | Where-Object { $_ }); IncludeTelemetry = [bool]$IncludeTelemetry; TelemetryHours = $TelemetryHours }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Dependency graph' -Color 'deepskyblue3_1' }
    $state = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
        $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
        Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"
        $queries = Get-AACDependencyQuery -ResourceGroupName $request.ResourceGroupName
        Update-AACProgress -Id 'read' -Total $queries.Count -Description 'Reading the resources and what links them'
        $read = Invoke-AACGraphBatch -Query $queries -SubscriptionId $scope.GraphScope -AllowFailure @('roles', 'insights', 'workspaces', 'origins', 'profiles', 'identities') -OnProgress { param($Name, $Done, $Total) Update-AACProgress -Id 'read' -Increment 1 -Description "Read the $Name ($Done of $Total)" }
        $notices = [System.Collections.Generic.List[string]]::new()
        foreach ($key in $read.Errors.Keys) { if ($read.Errors[$key]) { $notices.Add("The $key couldn't be read: $($read.Errors[$key]) - dependencies through them are missing.") } }
        Update-AACProgress -Id 'read' -Complete -Description "Read the resources ($(@($queries.Keys).Count) queries)"

        # Application Insights: the dependencies each workspace recorded.
        $telemetry = [System.Collections.Generic.List[object]]::new()
        if ($request.IncludeTelemetry) {
            $customerIds = @{}
            foreach ($w in @($read.Rows['workspaces'] | Where-Object { $_ })) { $customerIds[([string]$w['id']).ToLowerInvariant()] = [string]$w['customerId'] }
            $workspaces = @(@($read.Rows['insights'] | Where-Object { $_ }) | ForEach-Object { ([string]$_['workspace']).ToLowerInvariant() } | Where-Object { $_ -and $customerIds.Contains($_) } | Select-Object -Unique)
            if (-not $workspaces.Count) { $notices.Add('No workspace-based Application Insights component in scope: no telemetry dependencies.') }
            Update-AACProgress -Id 'telemetry' -Total ([Math]::Max(1, $workspaces.Count)) -Description "Reading the dependencies Application Insights recorded in $($workspaces.Count) workspace(s)"
            foreach ($w in $workspaces) {
                $logs = Invoke-AACLogQueryBatch -WorkspaceId $customerIds[$w] -Query @{ dependencies = "AppDependencies | where TimeGenerated > ago($($request.TelemetryHours)h) | summarize Calls = sum(ItemCount), Failed = sumif(ItemCount, Success == false) by AppRoleName, Target, DependencyType | top 500 by Calls" }
                if ($logs.Errors['dependencies']) { $notices.Add("The telemetry of workspace $($w -replace '^.*/', '') couldn't be read: $($logs.Errors['dependencies'])") }
                foreach ($row in @($logs.Rows['dependencies'])) { if ($row) { $telemetry.Add($row) } }
                Update-AACProgress -Id 'telemetry' -Increment 1
            }
            Update-AACProgress -Id 'telemetry' -Complete -Description ('Read {0:N0} recorded dependenc(ies)' -f $telemetry.Count)
        }
        Update-AACProgress -Id 'graph' -Indeterminate -Description 'Building the graph: blast radius, single points of failure, cycles'
        $result = ConvertTo-AACDependencyGraph -Read $read -Telemetry $telemetry.ToArray() -SubscriptionName $scope.Names
        Update-AACProgress -Id 'graph' -Complete -Description ('{0:N0} resource(s), {1:N0} dependenc(ies): {2:N0} single point(s) of failure, {3:N0} cycle(s)' -f $result.Stats.Nodes, $result.Stats.Edges, $result.Stats.Spof, $result.Stats.Cycles)
        @{ Result = $result; Scope = $scope; Notices = $notices.ToArray() }
    }

    $result = $state.Result
    $nodes = @($result.Nodes)
    $s = $result.Stats
    if ($dotFile) {
        $quote = { param([string] $Text) '"' + ($Text -replace '\\', '\\' -replace '"', '\"') + '"' }
        $spofIds = @($nodes | Where-Object SinglePointOfFailure -EQ 'Yes' | ForEach-Object { if ($_.ResourceId) { $_.ResourceId } else { "external:$($_.Resource)" } })
        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add('digraph AzureDependencies {')
        $lines.Add('  rankdir=LR; node [shape=box, style="rounded,filled", fillcolor="#EEF2FF", fontname="Segoe UI"]; edge [fontname="Segoe UI", fontsize=9];')
        foreach ($n in $nodes) {
            $id = if ($n.ResourceId) { $n.ResourceId } else { "external:$($n.Resource)" }
            $fill = if ($spofIds -contains $id) { '#FEE2E2' } elseif ($n.Type -eq 'external') { '#F3F4F6' } else { '#EEF2FF' }
            $lines.Add("  $(& $quote $id) [label=$(& $quote "$($n.Resource)`n$($n.Type -replace '^microsoft\.', '')"), fillcolor=$(& $quote $fill)];")
        }
        foreach ($e in $result.Edges) { $lines.Add("  $(& $quote $e.FromId) -> $(& $quote $e.ToId) [label=$(& $quote $e.Relation)$(if ($e.Relation -eq 'peered') { ', dir=both, style=dashed' })];") }
        $lines.Add('}')
        $folder = Split-Path -Path $dotFile -Parent
        if ($folder -and -not (Test-Path -LiteralPath $folder)) { $null = New-Item -ItemType Directory -Path $folder -Force }
        [System.IO.File]::WriteAllLines($dotFile, $lines, [System.Text.UTF8Encoding]::new($false))
        if ($interactive) { Write-AACStatusLine Success "Graphviz DOT: $dotFile" -Detail 'dot -Tsvg graph.dot -o graph.svg' }
    }
    $rank = Get-AACSeverityRank
    $report = @{
        Subtitle = 'Dependency graph: blast radius, single points of failure, circular dependencies'
        Facts    = [ordered]@{ Scope = $state.Scope.Label; 'Resource groups' = $(if ($ResourceGroupName) { $ResourceGroupName -join ', ' } else { 'all' }); Telemetry = $(if ($IncludeTelemetry) { "Application Insights, the last $TelemetryHours h" } else { 'not read (-IncludeTelemetry)' }) }
        Status   = $(if (@($result.Findings | Where-Object Severity -EQ 'High').Count) { 'Failed' } elseif ($s.Spof -or $s.Cycles) { 'Warning' } else { 'Success' })
        Headline = $(if ($s.Nodes) { "$($s.Nodes) resource(s), $($s.Edges) dependenc(ies): $($s.Spof) single point(s) of failure, $($s.Cycles) circular dependenc(ies) - the widest blast radius is $($s.MaxRadius)" } else { 'No dependencies found in scope.' })
        Tiles    = @(
            @{ Value = '{0:N0}' -f $s.Nodes; Label = 'resources'; Tone = 'info'; Table = 'nodes' }
            @{ Value = '{0:N0}' -f $s.Edges; Label = 'dependencies'; Tone = 'violet'; Table = 'edges' }
            @{ Value = '{0:N0}' -f $s.Spof; Label = 'single points of failure'; Tone = $(if ($s.Spof) { 'bad' } else { 'good' }); Table = 'nodes'; Filters = @{ SinglePointOfFailure = 'Yes' } }
            @{ Value = '{0:N0}' -f $s.Cycles; Label = 'circular dependencies'; Tone = $(if ($s.Cycles) { 'warn' } else { 'good' }) }
            @{ Value = '{0:N0}' -f $s.MaxRadius; Label = 'widest blast radius'; Tone = 'warn' }
            @{ Value = '{0:N0}' -f $s.External; Label = 'external dependencies'; Tone = 'neutral' }
        )
        Notices  = @($state.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
        Charts   = @(
            @{ Title = 'Widest blast radius'; Items = @($nodes | Where-Object { $_.BlastRadius -gt 0 } | Select-Object -First 12 | ForEach-Object { @{ Label = $_.Resource; Value = $_.BlastRadius; Filter = $_.Resource; Tone = $(if ($_.SinglePointOfFailure -eq 'Yes') { 'bad' } else { 'info' }) } }); Table = 'nodes'; Column = 'Resource'; Console = $true }
            @{ Title = 'Dependencies by kind'; Kind = 'donut'; CenterLabel = 'dependencies'; Items = @($result.Edges | Group-Object Relation | Sort-Object Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'edges'; Column = 'Relation' }
        )
        Tables   = @(
            @{ Id = 'findings'; Title = 'Findings'; Section = 'Findings'; Rows = $result.Findings; Noun = 'findings'; ConsoleLimit = 20
                Empty = 'No single points of failure or circular dependencies found.'
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Category'; Label = 'Kind'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Finding'; Label = 'Finding'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'BlastRadius'; Label = 'Blast radius'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide' }
                    @{ Key = 'Remediation'; Label = 'What to do'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Link'; Label = 'Docs'; Type = 'link'; Text = 'Docs' }
                ) }
            @{ Id = 'nodes'; Title = 'Resources'; Section = 'Resources'; Rows = $nodes; Noun = 'resources'; ConsoleLimit = 15; GroupBy = @('Type', 'ResourceGroup', 'SinglePointOfFailure')
                Columns = @(
                    @{ Key = 'Resource'; Label = 'Resource'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Type'; Label = 'Type'; Type = 'mono'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'BlastRadius'; Label = 'Blast radius'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'Dependents'; Label = 'Dependents'; Type = 'number'; Console = $true }
                    @{ Key = 'DependsOn'; Label = 'Depends on'; Type = 'number'; Console = $true }
                    @{ Key = 'Redundant'; Label = 'Redundant'; Type = 'badge'; Tones = @{ Yes = 'good'; No = 'warn' }; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'SinglePointOfFailure'; Label = 'Single point of failure'; Type = 'badge'; Tones = @{ Yes = 'bad'; No = 'neutral' }; Facet = $true; Pdf = $true }
                    @{ Key = 'DependentsList'; Label = 'Depended on by'; Type = 'wide' }
                    @{ Key = 'DependsOnList'; Label = 'Depends on (names)'; Type = 'wide' }
                    @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                ) }
            @{ Id = 'edges'; Title = 'Dependencies'; Section = 'Dependencies'; Rows = $result.Edges; Noun = 'dependencies'; NoConsole = $true; GroupBy = @('From', 'Relation', 'To')
                Columns = @(@{ Key = 'From'; Label = 'Resource' }, @{ Key = 'Relation'; Label = 'Relation'; Facet = $true }, @{ Key = 'To'; Label = 'Depends on' }, @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide' }) }
        )
        Hint     = '-IncludeTelemetry adds who calls whom; -DotPath writes the graph for Graphviz; -NoDisplay returns the resources.'
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $nodes -Noun 'resource' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $nodes -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
