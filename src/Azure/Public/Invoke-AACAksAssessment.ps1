function Invoke-AACAksAssessment {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Assesses AKS clusters through every lens - current settings, the
        Well-Architected Framework, PSRule for Azure, Azure Policy for
        Kubernetes (consolidated by namespace, workload, policy and
        cluster), versions and upgrades, capacity, Advisor and Defender -
        with a Spectre.Console view, objects, and CSV, PDF and interactive
        HTML reports.
    .DESCRIPTION
        Read-only (Reader is enough; -IncludeConstraint needs more, below),
        REST only - no Az modules, no kubectl. For each cluster:

          Current settings  every setting that matters, by area: general
                            (version, tier, support plan, power state),
                            upgrades (channels, maintenance windows),
                            identity and access (Entra ID, Azure RBAC, local
                            accounts, workload identity), networking
                            (plugin, dataplane, policy, outbound, CIDRs,
                            private cluster, authorized ranges), security
                            (Defender, Azure Policy, KMS, image cleaner, Key
                            Vault provider, node resource group lockdown),
                            monitoring (Container insights, Prometheus, cost
                            analysis, diagnostic settings), add-ons and the
                            autoscaler profile - and each node pool: size,
                            mode, OS, nodes, autoscale, zones, max pods,
                            versions, node image and its age, disks, Spot,
                            subnet, taints
          Well-Architected  about 35 checks across the five pillars -
                            Reliability (SLA tier, zones, system pool, Spot,
                            version support, maintenance, surge), Security
                            (local accounts, Entra ID, Azure RBAC, API server
                            exposure, network policy, Azure Policy, Defender,
                            workload identity, pod identity, image cleaner,
                            KMS, node public IPs, encryption at host, managed
                            identity, node images, lockdown), Operational
                            Excellence (upgrade channels, Container insights,
                            Prometheus, audit logs, version drift, retired
                            add-ons), Cost Optimization (autoscaler, cost
                            analysis) and Performance Efficiency (ephemeral
                            OS disks, kubenet, load balancer, subnet IPs at
                            full scale) - Pass or Fail, a score per pillar
          PSRule for Azure  the Azure.AKS.* rules (unless -SkipPSRule), on
                            the cluster as Export-AzRuleData reads it -
                            -Baseline and -ExcludeRule as for Invoke-AACPSRule
          Azure Policy      the AKS Policy Compliance Toolkit's view
                            (github.com/sam-cogan/aks-policy-compliance-toolkit):
                            every non-compliant pod, service or network
                            policy, with its namespace and workload (inferred
                            from the pod's name), policy and effect - and the
                            same rolled up by namespace, by workload, by
                            policy and by cluster; the policies evaluated on
                            each cluster resource; the assignments
          Gatekeeper        with -IncludeConstraint: each constraint's
                            complete violation count from inside the cluster
                            (Azure Policy keeps 500 records per policy and
                            cluster), with AKS run command
          Versions          the control plane's version and its support
                            (supported, long-term support, out of support),
                            the upgrades available, how far behind the
                            newest it is; each pool's version and node image,
                            and the newest node image
          Advisor, Defender the clusters' Advisor recommendations and
                            retirements, and Defender for Cloud's unhealthy
                            assessments
        Every failed check and rule, recommendation and policy finding is a
        finding, with its severity, pillar, source and what to do.

        What you get depends on where the command runs:
          at the prompt    tiles, the clusters with their WAF scores, the
                           pillars, the High and Medium findings, policy
                           compliance by namespace, and - for up to three
                           clusters - each in detail, a page at a time
          piped onward     the AAC.AksCluster objects (each with its
                           NodePools, Settings, Checks, Findings, Upgrades
                           and PolicyViolations), with no view
          -PassThru        the view and the objects
          -NoDisplay       the objects only
        -CsvPath (a folder) writes a CSV per table - and the non-compliant
        workloads per namespace, as the toolkit exports them. -HtmlPath writes
        an interactive report with every table; -PdfPath a PDF with a
        section per cluster.
    .PARAMETER SubscriptionId
        Only the clusters in these subscriptions.
    .PARAMETER ManagementGroupId
        Only the clusters under these management groups.
    .PARAMETER ResourceGroupName
        Only the clusters in these resource groups.
    .PARAMETER Name
        Only these clusters; wildcards work, e.g. 'aks-prod-*'.
    .PARAMETER IncludeSystemNamespace
        Keep kube-system, gatekeeper-system and the other system namespaces
        in the policy compliance views (they are left out by default).
    .PARAMETER IncludeConstraint
        Read the Gatekeeper constraints' complete violation counts from
        inside each cluster with AKS run command. Needs the
        Microsoft.ContainerService/managedClusters/runCommand/action
        permission (Azure Kubernetes Service Cluster Admin, Contributor) and
        run command allowed on the cluster; it starts a short-lived pod in
        the aks-command namespace.
    .PARAMETER SkipPSRule
        Don't run PSRule for Azure.
    .PARAMETER Baseline
        The PSRule for Azure baseline (Azure.Default by default), e.g.
        Azure.GA_2024_12.
    .PARAMETER ExcludeRule
        PSRule rules to leave out, by name or wildcard.
    .PARAMETER CsvPath
        A folder to write a CSV per table to.
    .PARAMETER PdfPath
        Write a PDF report to this file.
    .PARAMETER HtmlPath
        Write an interactive HTML report to this file.
    .PARAMETER Title
        The PDF and HTML reports' title.
    .PARAMETER PassThru
        Show the view and also return the objects.
    .PARAMETER NoDisplay
        Return the objects without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once instead of a page at a time.
    .EXAMPLE
        Connect-AAC
        Invoke-AACAksAssessment
        Every AKS cluster the account can see, assessed.
    .EXAMPLE
        Invoke-AACAksAssessment -Name 'aks-prod-*' -HtmlPath .\out\AKS.html -PdfPath .\out\AKS.pdf -CsvPath .\out\aks
        The production clusters, with every report.
    .EXAMPLE
        Invoke-AACAksAssessment -ManagementGroupId 'mg-landingzones' -IncludeConstraint -NoDisplay | Select-Object -ExpandProperty PolicyViolations | Group-Object Namespace
        Kubernetes policy violations by namespace, with Gatekeeper's complete counts - before moving policies from Audit to Deny.
    .EXAMPLE
        (Invoke-AACAksAssessment -SubscriptionId 00000000-0000-0000-0000-000000000000 -NoDisplay).Checks | Where-Object { $_.Status -eq 'Fail' -and $_.Pillar -eq 'Security' }
        The failed Well-Architected security checks.
    .OUTPUTS
        AAC.AksCluster (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.AksCluster')]
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

        [switch] $IncludeSystemNamespace,

        [switch] $IncludeConstraint,

        [switch] $SkipPSRule,

        [string] $Baseline,

        [string[]] $ExcludeRule = @(),

        [string] $CsvPath,

        [string] $PdfPath,

        [string] $HtmlPath,

        [string] $Title = 'AKS cluster assessment',

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
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $showView = $interactive -and -not ($CsvPath -or $PdfPath -or $HtmlPath)
    $returnObjects = $PassThru -or $NoDisplay -or $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    # Read here, not inside the progress block (it runs in Invoke-AACProgress's scope).
    $request = @{
        SubscriptionId         = @($SubscriptionId | Where-Object { $_ })
        ManagementGroupId      = @($ManagementGroupId | Where-Object { $_ })
        ResourceGroupName      = @($ResourceGroupName | Where-Object { $_ })
        Name                   = @($Name | Where-Object { $_ })
        IncludeSystemNamespace = [bool]$IncludeSystemNamespace
        IncludeConstraint      = [bool]$IncludeConstraint
        SkipPSRule             = [bool]$SkipPSRule
        Baseline               = $Baseline
        ExcludeRule            = @($ExcludeRule | Where-Object { $_ })
        CsvPath                = & $resolve $CsvPath
        PdfPath                = & $resolve $PdfPath
        HtmlPath               = & $resolve $HtmlPath
        Title                  = $Title
    }

    if ($interactive) {
        Write-AACRule -Title 'Azure Admin Console :: AKS cluster assessment' -Color 'deepskyblue3_1'
    }
    $state = Invoke-AACProgress -ScriptBlock {
        $null = Get-AACAccessToken
        $rowsOf = { param($Read, [string] $Key) @(if ($Read.Rows.Contains($Key)) { $Read.Rows[$Key] }) | Where-Object { $null -ne $_ } }
        $notices = [System.Collections.Generic.List[string]]::new()

        # --- 1. The clusters ---------------------------------------------------------------------------------------
        Update-AACProgress -Id 'find' -Description 'Finding the AKS clusters' -Indeterminate
        $scope = @{}
        if ($request.SubscriptionId.Count) { $scope.SubscriptionId = $request.SubscriptionId }
        if ($request.ManagementGroupId.Count) { $scope.ManagementGroupId = $request.ManagementGroupId }
        $read = Invoke-AACGraphBatch @scope -Query (Get-AACAksQuery -Stage Clusters -ResourceGroupName $request.ResourceGroupName)
        $found = @(& $rowsOf $read 'clusters')
        if ($request.Name.Count) {
            $found = @($found | Where-Object { $clusterName = [string]$_['name']; @($request.Name | Where-Object { $clusterName -like $_ }).Count })
            $missing = @($request.Name | Where-Object { $pattern = $_; -not @($found | Where-Object { [string]$_['name'] -like $pattern }).Count })
            foreach ($item in $missing) { if ($found.Count) { Write-Warning "No AKS cluster named '$item' was found; it's left out." } }
        }
        if (-not $found.Count) {
            $problem = [System.InvalidOperationException]::new("No AKS cluster$(if ($request.Name.Count) { " named $(($request.Name | ForEach-Object { "'$_'" }) -join ', ')" }) was found$(if ($scope.Count -or $request.ResourceGroupName.Count) { ' in that scope' } else { ' in any subscription you can see' }).")
            $problem.Data['AACHint'] = 'Check the scope and the names (wildcards work: -Name ''aks-*''), and that your account has Reader on the clusters.'
            throw $problem
        }
        $subscriptionNames = @{}
        foreach ($row in @(& $rowsOf $read 'subscriptions')) { $subscriptionNames[([string]$row['subscriptionId']).ToLowerInvariant()] = [string]$row['name'] }
        $ids = @($found | ForEach-Object { [string]$_['id'] })
        $subscriptions = @($found | ForEach-Object { [string]$_['subscriptionId'] } | Sort-Object -Unique)
        Update-AACProgress -Id 'find' -Complete -Description ('Found {0:N0} cluster(s) in {1:N0} subscription(s)' -f $found.Count, $subscriptions.Count)

        # --- 2. Each cluster as PSRule reads it: properties, diagnostic settings, maintenance windows, subnets ----------------
        $ruleData = Get-AACRuleData -SubscriptionId $subscriptions -ResourceType 'Microsoft.ContainerService/managedClusters' -ResourceId $ids
        $clusters = @($ruleData.Resources | Where-Object { [string]$_['type'] -like '*managedClusters' })
        foreach ($line in @($ruleData.Warnings)) { $notices.Add($line) }

        # --- 3. Policy, Advisor, Defender (Resource Graph) ----------------------------------------------------------------
        $queries = Get-AACAksQuery -Stage Assess
        $labels = @{ clusterStates = 'cluster policy states'; components = 'non-compliant Kubernetes components'; assignments = 'policy assignments'; advisor = 'Advisor recommendations'; defender = 'Defender for Cloud assessments' }
        Update-AACProgress -Id 'graph' -Total $queries.Count -Description 'Reading Azure Policy, Advisor and Defender for Cloud'
        $graph = Invoke-AACGraphBatch -Query $queries -SubscriptionId $subscriptions -AllowFailure @($queries.Keys) -OnProgress {
            param($Name, $Done, $Total)
            Update-AACProgress -Id 'graph' -Increment 1 -Description "Read the $($labels[$Name]) ($Done of $Total)"
        }
        foreach ($key in $graph.Errors.Keys) { $notices.Add("The $($labels[$key]) couldn't be read: $($graph.Errors[$key])") }
        $components = @(& $rowsOf $graph 'components')
        $clusterStates = @(& $rowsOf $graph 'clusterStates')
        Update-AACProgress -Id 'graph' -Complete -Description ('Azure Policy: {0:N0} cluster policy state(s), {1:N0} non-compliant component(s); {2:N0} Advisor and {3:N0} Defender finding(s)' -f $clusterStates.Count, $components.Count, @(& $rowsOf $graph 'advisor').Count, @(& $rowsOf $graph 'defender').Count)

        # --- 4. Upgrades, versions, subnets and policy names (Resource Manager) --------------------------------------------
        $uris = [ordered]@{}
        foreach ($cluster in $clusters) {
            $id = [string]$cluster['id']
            $uris["upgrade|$($id.ToLowerInvariant())"] = "$id/upgradeProfiles/default?api-version=2024-02-01"
            foreach ($pool in @($cluster['properties']['agentPoolProfiles'])) {
                if ($pool) { $uris["pool|$($id.ToLowerInvariant())/$(([string]$pool['name']).ToLowerInvariant())"] = "$id/agentPools/$($pool['name'])/upgradeProfiles/default?api-version=2024-02-01" }
            }
            $location = ([string]$cluster['location']).ToLowerInvariant()
            if (-not @($uris.Keys | Where-Object { $_ -like "versions|$location" }).Count) { $uris["versions|$location"] = "/subscriptions/$($cluster['subscriptionId'])/providers/Microsoft.ContainerService/locations/$location/kubernetesVersions?api-version=2024-02-01" }
        }
        # Subnets PSRule's data doesn't have (it reads them for Azure CNI only), and pod subnets.
        $subnets = @{}
        foreach ($cluster in $clusters) { foreach ($child in @($cluster['resources'])) { if ($child -and [string]$child['type'] -like '*virtualNetworks/subnets') { $subnets[([string]$child['id']).ToLowerInvariant()] = $child } } }
        foreach ($cluster in $clusters) {
            foreach ($pool in @($cluster['properties']['agentPoolProfiles'])) {
                foreach ($subnetId in @($pool['vnetSubnetID'], $pool['podSubnetID'])) {
                    $key = ([string]$subnetId).ToLowerInvariant()
                    if ($key -and -not $subnets.Contains($key)) { $uris["subnet|$key"] = "$subnetId`?api-version=2023-09-01" }
                }
            }
        }
        foreach ($definitionId in @(@($components) + @($clusterStates) | ForEach-Object { [string]$_['definitionId']; [string]$_['setId'] } | Where-Object { $_ } | Sort-Object -Unique)) {
            $uris["definition|$definitionId"] = "$definitionId`?api-version=2023-04-01"
        }
        Update-AACProgress -Id 'arm' -Total $uris.Count -Description 'Reading upgrade profiles, Kubernetes versions, subnets and policy names'
        $answers = Invoke-AACArmParallel -Uri @($uris.Values) -OnProgress { param($Done, $Total) Update-AACProgress -Id 'arm' -Increment 1 }
        $upgradeProfiles = @{}; $poolUpgrades = @{}; $versions = @{}; $definitionNames = @{}
        $unread = 0
        foreach ($key in $uris.Keys) {
            $kind, $rest = $key -split '\|', 2
            $answer = $answers[$uris[$key]]
            if (-not $answer -or $answer.Error -or $answer.Body -isnot [System.Collections.IDictionary]) { $unread++; continue }
            switch ($kind) {
                'upgrade' { $upgradeProfiles[$rest] = $answer.Body }
                'pool' { $poolUpgrades[$rest] = $answer.Body }
                'versions' { $versions[$rest] = @($answer.Body['values']) }
                'subnet' { $subnets[$rest] = $answer.Body }
                'definition' { $definitionNames[$rest] = [string]$answer.Body['properties']['displayName'] }
            }
        }
        Update-AACProgress -Id 'arm' -Complete -Description ('Read {0:N0} upgrade profile(s), the versions of {1:N0} region(s) and {2:N0} policy name(s){3}' -f $upgradeProfiles.Count, $versions.Count, $definitionNames.Count, $(if ($unread) { ", $unread not readable" }))

        # --- 5. PSRule for Azure ------------------------------------------------------------------------------------------
        $psrule = @()
        if ($request.SkipPSRule) { }
        elseif (-not (Get-Module -Name 'PSRule.Rules.Azure' -ListAvailable)) {
            $notices.Add('PSRule for Azure is not installed, so its rules were not run: Install-PSResource PSRule.Rules.Azure -Scope CurrentUser')
        }
        else {
            try {
                $engine = @{ InputObject = $clusters; ExcludeRule = $request.ExcludeRule }
                if ($request.Baseline) { $engine.Baseline = $request.Baseline }
                $psrule = @((Invoke-AACPSRuleEngine @engine).Results | Where-Object { [string]$_.ResourceType -like '*managedclusters' -or $ids -contains [string]$_.ResourceId })
            }
            catch { $notices.Add("PSRule for Azure couldn't run: $($_.Exception.Message)") }
        }

        # --- 6. Gatekeeper, in each cluster -----------------------------------------------------------------------------
        $constraints = @{}
        if ($request.IncludeConstraint) {
            Update-AACProgress -Id 'gatekeeper' -Total $clusters.Count -Description 'Reading Gatekeeper''s constraints in each cluster (AKS run command)'
            foreach ($cluster in $clusters) {
                $properties = $cluster['properties']
                $result = Get-AACAksConstraint -ClusterId ([string]$cluster['id']) -EntraId:([bool]$properties['aadProfile'])
                $constraints[([string]$cluster['id']).ToLowerInvariant()] = $result
                if ($result.Status -ne 'OK') { $notices.Add("Gatekeeper on $($cluster['name']): $(if ($result.Status -eq 'NoGatekeeper') { 'no constraints (the Azure Policy add-on is off, or no Kubernetes policy is assigned)' } else { $result.Status })") }
                Update-AACProgress -Id 'gatekeeper' -Increment 1 -Description "Read Gatekeeper in $($cluster['name'])"
            }
            Update-AACProgress -Id 'gatekeeper' -Complete -Description ('Gatekeeper: {0:N0} violation(s) in {1:N0} constraint(s)' -f (@($constraints.Values | ForEach-Object { $_.Totals } | ForEach-Object TotalViolations) | Measure-Object -Sum).Sum, @($constraints.Values | ForEach-Object { $_.Totals }).Count)
        }

        # --- 7. The assessment ----------------------------------------------------------------------------------------
        Update-AACProgress -Id 'assess' -Description 'Assessing the clusters through every lens' -Indeterminate
        $clusterNames = @{}
        foreach ($cluster in $clusters) { $clusterNames[([string]$cluster['id']).ToLowerInvariant()] = [string]$cluster['name'] }
        $policy = ConvertTo-AACAksPolicyCompliance -Component $components -ClusterState $clusterStates -Assignment @(& $rowsOf $graph 'assignments') -DefinitionName $definitionNames -ClusterName $clusterNames -SubscriptionName $subscriptionNames -IncludeSystemNamespace:$request.IncludeSystemNamespace
        $assessment = ConvertTo-AACAksAssessment -Cluster $clusters -UpgradeProfile $upgradeProfiles -PoolUpgrade $poolUpgrades -KubernetesVersion $versions -Subnet $subnets `
            -Advisor @(& $rowsOf $graph 'advisor') -Defender @(& $rowsOf $graph 'defender') -PSRule $psrule -Policy $policy -Constraint $constraints -SubscriptionName $subscriptionNames
        $assessment.Notices = $notices.ToArray()
        $stats = $assessment.Stats
        Update-AACProgress -Id 'assess' -Complete -Description ('Assessed {0:N0} cluster(s): WAF {1}%, {2} high, {3} medium, {4} low finding(s); {5:N0} policy violation(s)' -f $stats.Clusters, $stats.WafScore, $stats.High, $stats.Medium, $stats.Low, $policy.Stats.Violations)

        $detail = [ordered]@{ Scope = if ($request.ManagementGroupId.Count) { "management group(s) $($request.ManagementGroupId -join ', ')" } elseif ($request.SubscriptionId.Count) { "subscription(s) $($request.SubscriptionId -join ', ')" } else { 'every subscription the account can see' } }
        if ($request.ResourceGroupName.Count) { $detail['Resource groups'] = $request.ResourceGroupName -join ', ' }
        if ($request.Name.Count) { $detail['Clusters'] = $request.Name -join ', ' }
        $detail['Policy views'] = if ($request.IncludeSystemNamespace) { 'every namespace' } else { 'system namespaces left out' }
        if ($psrule.Count) { $detail['PSRule baseline'] = if ($request.Baseline) { $request.Baseline } else { 'Azure.Default' } }
        if ($request.CsvPath) {
            Update-AACProgress -Id 'csv' -Description 'Writing the CSV files' -Indeterminate
            $files = @(Write-AACAksCsv -Assessment $assessment -Path $request.CsvPath)
            Update-AACProgress -Id 'csv' -Complete -Description "CSV: $($files.Count) file(s) in $($request.CsvPath)"
        }
        $null = Invoke-AACExport -PdfPath $request.PdfPath -WritePdf {
            Write-AACAksPdf -Assessment $assessment -Path $request.PdfPath -Title $request.Title -Detail $detail
        } -HtmlPath $request.HtmlPath -WriteHtml {
            Write-AACAksHtml -Assessment $assessment -Path $request.HtmlPath -Title $request.Title -Detail $detail
        }
        @{ Assessment = $assessment; Scope = $detail }
    }

    $assessment = $state.Assessment
    if ($showView) {
        Invoke-AACPagedOutput -NoPaging:$NoPaging -ScriptBlock {
            Show-AACAksView -Assessment $assessment -Scope $state.Scope
        }
    }
    elseif ($interactive) {
        foreach ($notice in @($assessment.Notices)) { Write-AACMarkup "[grey58]$([Spectre.Console.Markup]::Escape($notice))[/]" }
    }
    if ($returnObjects) {
        foreach ($cluster in $assessment.Clusters) {
            $id = $cluster.ResourceId
            $cluster | Add-Member -NotePropertyMembers ([ordered]@{
                    NodePools        = @($assessment.NodePools | Where-Object ClusterId -EQ $id)
                    Settings         = @($assessment.Settings | Where-Object ClusterId -EQ $id)
                    Checks           = @($assessment.Checks | Where-Object ClusterId -EQ $id)
                    Findings         = @($assessment.Findings | Where-Object ClusterId -EQ $id)
                    Upgrades         = @($assessment.Upgrades | Where-Object ClusterId -EQ $id)
                    PolicyViolations = @(if ($assessment.Policy) { $assessment.Policy.Components | Where-Object { $_.ClusterId -eq $id.ToLowerInvariant() } })
                    PSRule           = @($assessment.PSRule | Where-Object { $_.ResourceName -eq $cluster.Name })
                }) -Force
            $cluster
        }
    }
}
