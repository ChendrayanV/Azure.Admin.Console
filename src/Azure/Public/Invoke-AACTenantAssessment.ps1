function Invoke-AACTenantAssessment {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Assesses an Azure tenant end to end - the organization, an inventory
        of every resource type with its key settings and policy compliance,
        Azure Policy, the Well-Architected Framework, PSRule for Azure,
        Advisor, retirements, Defender for Cloud, FinOps and cost, outages
        and quotas - as CSV files, an interactive HTML report, a PDF and
        interactive diagrams, with a live Spectre.Console progress display.
    .DESCRIPTION
        The module's take on Azure Resource Inventory (ARI), and the one
        command to run first in a tenant you need to understand: it reads
        the tenant (or the subscriptions, management groups, resource
        groups or tag you name) and writes the reports you choose.
        Read-only; Reader is enough (Security Reader for Defender, Cost
        Management Reader for cost); no Az modules, no Excel. -Full turns on
        everything that is off by default.

        The focused assessments go deeper into one service or discipline -
        Invoke-AACWafAssessment (a workload's review, with the team's
        answers and the trend), Invoke-AACPolicyAssessment,
        Invoke-AACDefenderAssessment, Invoke-AACGovernanceAssessment and the
        service ones (AKS, Cosmos DB, Function Apps, Log Analytics, Service
        Bus, storage, virtual networks).

        What it reads, in phases - each a line of the progress display:
          1. Scope        the subscriptions (with their management groups) in
                          scope, and the tenant's management groups
          2. Estate       every resource and resource group, the resource
                          types present; Advisor recommendations (and
                          retirements, always); Defender for Cloud
                          (-SecurityCenter); Azure Policy compliance - by
                          policy, resource group and resource (unless
                          -SkipPolicy); support tickets
          3. Inventory    a sheet per resource type present - ~95 types, in
                          the categories Compute, Hybrid, Containers,
                          Databases, Analytics, AI, Integration, IoT,
                          Management, Monitoring, Networking, Security,
                          Storage and Web - each with the settings that
                          matter for it (a VM's size, power state, OS, disks,
                          IP, network and security settings; a storage
                          account's TLS, public access, shared keys and
                          firewall; ...), as Resource Graph projections
          4. Azure APIs   per subscription: the Advisor score, reservation
                          recommendations, the budgets, the last 6 months'
                          outages (Resource Health service issues), compute
                          quotas (-QuotaUsage), and VM sizes' vCPUs and
                          memory (unless -SkipVMDetail); -SkipApi skips them
                          all
          5. Well-Architected  the checks of Invoke-AACWafAssessment across
                          the five pillars - Reliability, Security, Cost
                          Optimization, Operational Excellence, Performance
                          Efficiency - scored by pillar, design principle
                          and check (unless -SkipWaf)
          6. Cost         each resource's cost, this month and last
                          (-IncludeCost, Cost Management)
          7. PSRule       PSRule for Azure's rules on the resources (-PSRule)
          8. Governance   the policy assignments in force and every policy
                          they apply (unless -SkipPolicy), FinOps, and one
                          list of recommendations
          9. Reports      the reports asked for (-HtmlPath, -PdfPath,
                          -CsvPath, -DiagramPath), then an upload to a blob
                          container (-StorageAccount)

        Every inventory sheet (and All resources) adds, after its own
        columns: Retirement (an Advisor retirement notice for the
        resource), Advisor (its number of recommendations), its policy
        compliance (Policy - Non-compliant, Compliant, Exempt or Not
        evaluated; Non-compliant policies; Failing policies, by name), WAF
        gaps (the Well-Architected checks it fails), PSRule failures (with
        -PSRule), its cost with -IncludeCost, and its tags with -IncludeTag.
        The overview sheets: Subscriptions, Resource groups, Resource types,
        All resources; then Advisor recommendations, Advisor score,
        Retirements, Security recommendations, Secure score, Policy
        compliance, Outages, Quotas, Support tickets and Reservation
        recommendations. Then:
          Well-Architected   WAF pillars (score and maturity), WAF design
                             principles, WAF checks and WAF findings (each
                             failed check on each resource, with what to do)
          FinOps             Savings opportunities (by lever: Waste -
                             unattached disks, unused public IPs, VMs
                             stopped but billed, empty plans, old snapshots;
                             Rightsizing and Rate - Advisor's cost
                             recommendations, reservations, savings plans;
                             Licensing - Azure Hybrid Benefit; Modernise -
                             old VM generations - each with its estimated
                             annual saving), Cost allocation (the resources
                             with a cost-allocation tag, -CostTag, and the
                             cost of those without), Budgets (spent and
                             forecast against each budget, the alerts, the
                             subscriptions with none) and, with
                             -IncludeCost, Cost by service, Cost by
                             resource group and Top cost resources (this
                             month projected against last month)
        and the governance sheets:
          Policy compliance  Compliance by initiative, by resource group and
                             by standard (the controls of CIS, NIST, ISO
                             27001, the Microsoft cloud security benchmark
                             ... initiatives), and each non-compliant
                             resource with why and how to fix it
          Policy inventory   Policy assignments, and every policy in force
                             with its effect, resource types, controls and
                             status (Failed, Passed, Manual review, Exempt,
                             Not evaluated, Disabled)
          PSRule results     PSRule rules (checked, passed, failed, with
                             their documentation) and the failed resources
                             (-PSRule)
          Recommendations    Resource recommendations: Advisor, Defender,
                             retirements, unattached and empty resources,
                             policy non-compliance, PSRule, the
                             Well-Architected findings and FinOps (budgets,
                             cost allocation) in one list, each with a
                             severity, category and what to do

        The reports - each written only where its own parameter says, none
        by default:
          -HtmlPath     a tabbed workbook: an Executive summary (tiles - the
                    Well-Architected score, the estimated savings, cost-tag
                    coverage ... - charts - a click filters the table behind
                    them - and the tenant tree), then Policy compliance,
                    Policy inventory, Well-Architected, PSRule results,
                    Resource recommendations, FinOps, Resources, Inventory,
                    Advisor, Security and Health; every table
                    searchable, filterable, groupable, with each row's
                    details a click away, and downloadable as CSV
          -PdfPath      the summary, then each category with its sheets' key
                        columns (bookmarked)
          -CsvPath      a folder: a CSV file per sheet
          -DiagramPath  a folder: TenantAssessment-Network.html, the network
                        topology - virtual networks, subnets, peerings,
                        gateways, firewalls, load balancers, private
                        endpoints, NSGs and routes (-DiagramFullEnvironment:
                        every resource and how they connect);
                        TenantAssessment-Organization.html, management
                        groups > subscriptions > resource groups;
                        TenantAssessment-Resources.html, each subscription
                        with its resource types and counts. Interactive:
                        pan, zoom, search, details on click, PNG and SVG
                        export.
        Without any of them the run shows its summary and returns the
        assessment (-PassThru, -NoDisplay): every sheet is in its Sheets.

        Sign-in: the Connect-AAC session. -TenantId signs in to that tenant
        first (in the browser) when the session is for another one. In
        Azure Automation, -Automation signs in with the account's managed
        identity (Connect-AAC -Identity) if no session is there yet, and
        writes plain progress lines for the job log. -StorageAccount and
        -StorageContainer upload the reports written to blob storage, under
        TenantAssessment/<date>/ (Storage Blob Data Contributor needed);
        with no report path given, every report is written to a temporary
        folder for the upload.
    .PARAMETER TenantId
        The tenant to assess. Signs in to it first if the current session is
        for another tenant (or there is none).
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups (at any depth).
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ResourceGroupName
        Only these resource groups.
    .PARAMETER TagKey
        Only resources with this tag (any case).
    .PARAMETER TagValue
        Only resources with this tag value (with -TagKey: that tag with that
        value).
    .PARAMETER Category
        Only these inventory categories: Compute, Hybrid, Containers,
        Databases, Analytics, AI, Integration, IoT, Management, Monitoring,
        Networking, Security, Storage, Web. The overview sheets are always
        written.
    .PARAMETER IncludeTag
        Add each resource's tags to every inventory sheet.
    .PARAMETER SecurityCenter
        Read Defender for Cloud: the unhealthy recommendations and each
        subscription's secure score.
    .PARAMETER SkipAdvisor
        Don't read Advisor recommendations (retirements are still read).
    .PARAMETER SkipPolicy
        Don't read Azure Policy compliance, or the policy inventory.
    .PARAMETER PSRule
        Run PSRule for Azure's rules on the resources in scope too: the
        PSRule results tab, and its failures among the recommendations.
        Needs PSRule.Rules.Azure (Install-PSResource PSRule.Rules.Azure
        -Scope CurrentUser); it reads each resource's child settings, so it
        takes a while on a large estate.
    .PARAMETER PSRuleBaseline
        The PSRule for Azure baseline (Azure.Default by default), e.g.
        Azure.Pillar.Security or Azure.GA_2024_12.
    .PARAMETER SkipWaf
        Don't run the Well-Architected checks: no Well-Architected tab, WAF
        gaps column or WAF findings among the recommendations, and the
        FinOps waste comes from the inventory alone.
    .PARAMETER CostTag
        The tag names that allocate cost (any one counts), for the Cost
        allocation sheet and the Well-Architected cost-tag checks.
    .PARAMETER IncludeCost
        Read each resource's actual cost, this month and last (Cost
        Management Reader): the cost columns, the estimated savings, and
        the Cost by service, Cost by resource group and Top cost resources
        sheets.
    .PARAMETER QuotaUsage
        Read the compute quotas in use, per subscription and region.
    .PARAMETER Full
        Everything that is off by default: -SecurityCenter, -IncludeCost,
        -IncludeTag, -PSRule and -QuotaUsage.
    .PARAMETER SkipIdentity
        Don't read access: no privileged role assignments, Privileged
        Identity Management, custom roles or Microsoft Graph (principals and
        app registration credentials).
    .PARAMETER SkipKeyVault
        Don't list the Key Vaults' secrets, keys and certificates (their
        expiry dates come from each vault's data plane - Key Vault Reader,
        and a network path to the vault).
    .PARAMETER ActivityDays
        The days of Activity Log read for changes and failed deployments (30
        by default; 0 reads none).
    .PARAMETER ExpiryDays
        Credentials expiring within this many days are flagged (30 by
        default).
    .PARAMETER OwnerTag
        The tag names that name an owner (any one counts), for the owner-tag
        coverage and the ownership map.
    .PARAMETER ProductionPattern
        A regular expression that recognises production in a subscription
        or resource group name, or an Environment, Env, Stage or Tier tag
        value: production resources are judged more strictly (backup, zones,
        locks, Dev/Test offers).
    .PARAMETER SkipApi
        Don't call the per-subscription Azure APIs (Advisor score,
        reservations, budgets, outages, quotas, VM sizes, PIM, classic
        administrators, locks, the Activity Log, diagnostic settings,
        regions, reservation and savings plan use) - Resource Graph only.
    .PARAMETER SkipVMDetail
        Don't read VM sizes' vCPUs and memory (Compute SKUs).
    .PARAMETER HtmlPath
        Write the interactive HTML report to this file.
    .PARAMETER PdfPath
        Write the PDF report to this file.
    .PARAMETER CsvPath
        Write a CSV file per sheet into this folder (made if missing).
    .PARAMETER DiagramPath
        Draw the network, organization and resources diagrams into this
        folder (made if missing).
    .PARAMETER DiagramFullEnvironment
        Draw every resource in the network diagram, not only the network.
    .PARAMETER Automation
        Run in an Azure Automation runbook: sign in with the managed
        identity if not signed in, and write plain progress lines.
    .PARAMETER StorageAccount
        Upload the reports to this storage account (with -StorageContainer).
    .PARAMETER StorageContainer
        The blob container to upload to.
    .PARAMETER Title
        The HTML and PDF reports' title.
    .PARAMETER PassThru
        Show the summary and also return the assessment.
    .PARAMETER NoDisplay
        Return the assessment without showing the summary.
    .PARAMETER NoPaging
        Show the summary at once instead of a page at a time.
    .EXAMPLE
        Connect-AAC
        Invoke-AACTenantAssessment -HtmlPath .\Tenant.html -PdfPath .\Tenant.pdf
        The whole tenant (everything the account can see), as an HTML and a PDF report.
    .EXAMPLE
        Invoke-AACTenantAssessment -HtmlPath C:\Reports\Tenant.html -CsvPath C:\Reports\csv -DiagramPath C:\Reports\diagrams
        The HTML report, a CSV file per sheet and the diagrams, each where you say.
    .EXAMPLE
        Invoke-AACTenantAssessment -TenantId 'contoso.onmicrosoft.com' -Full
        Another tenant, with everything: Defender for Cloud, cost, tags, PSRule for Azure and quotas.
    .EXAMPLE
        Invoke-AACTenantAssessment -SecurityCenter -IncludeTag -IncludeCost -CostTag 'CostCenter', 'Department'
        Defender for Cloud, tags and cost, with the organisation's own cost-allocation tags.
    .EXAMPLE
        (Invoke-AACTenantAssessment -IncludeCost -NoDisplay).Sheets['Savings opportunities'] | Sort-Object 'Est. annual savings' -Descending | Select-Object -First 10
        The ten biggest savings.
    .EXAMPLE
        (Invoke-AACTenantAssessment -NoDisplay).Sheets['All resources'] | Where-Object Policy -EQ 'Non-compliant' | Select-Object Name, Type, 'Failing policies'
        Each non-compliant resource and the policies it fails.
    .EXAMPLE
        Invoke-AACTenantAssessment -ManagementGroupId 'mg-landingzones' -HtmlPath .\LandingZones.html -DiagramPath .\diagrams
        A management group's subscriptions: the HTML report and the diagrams.
    .EXAMPLE
        Invoke-AACTenantAssessment -SubscriptionId 00000000-0000-0000-0000-000000000000 -TagKey 'Environment' -TagValue 'Production' -Category Compute, Networking
        Production's compute and network resources in one subscription.
    .EXAMPLE
        Invoke-AACTenantAssessment -Automation -StorageAccount 'stcontosoreports' -StorageContainer 'assessments'
        In an Azure Automation runbook: managed identity sign-in, and every report uploaded to blob storage.
    .EXAMPLE
        (Invoke-AACTenantAssessment -NoDisplay).Sheets['Virtual machines'] | Where-Object 'Power state' -NE 'VM running'
        The VMs that aren't running.
    .OUTPUTS
        AAC.TenantAssessment (with -PassThru or -NoDisplay, or piped onward)
    #>
    [CmdletBinding()]
    [OutputType('AAC.TenantAssessment')]
    param(
        [ValidateNotNullOrEmpty()]
        [string] $TenantId,

        [ValidateNotNullOrEmpty()]
        [string[]] $ManagementGroupId,

        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [ValidateNotNullOrEmpty()]
        [string[]] $ResourceGroupName,

        [string] $TagKey,

        [string] $TagValue,

        [ValidateSet('Compute', 'Hybrid', 'Containers', 'Databases', 'Analytics', 'AI', 'Integration', 'IoT', 'Management', 'Monitoring', 'Networking', 'Security', 'Storage', 'Web')]
        [string[]] $Category,

        [switch] $IncludeTag,

        [switch] $SecurityCenter,

        [switch] $SkipAdvisor,

        [switch] $SkipPolicy,

        [switch] $PSRule,

        [string] $PSRuleBaseline,

        [switch] $SkipWaf,

        [ValidateNotNullOrEmpty()]
        [string[]] $CostTag = @('CostCenter', 'CostCentre', 'Cost Center', 'Project', 'Application', 'BillingCode'),

        [switch] $IncludeCost,

        [switch] $QuotaUsage,

        [switch] $Full,

        [switch] $SkipIdentity,

        [switch] $SkipKeyVault,

        [ValidateRange(0, 90)]
        [int] $ActivityDays = 30,

        [ValidateRange(1, 365)]
        [int] $ExpiryDays = 30,

        [ValidateNotNullOrEmpty()]
        [string[]] $OwnerTag = @('Owner', 'Contact', 'TechnicalOwner', 'BusinessOwner'),

        [ValidateNotNullOrEmpty()]
        [string] $ProductionPattern = '(?i)(^|[-_.\s])(prod|prd|production|live)([-_.\s]|$)',

        [switch] $SkipApi,

        [switch] $SkipVMDetail,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $CsvPath,

        [string] $DiagramPath,

        [switch] $DiagramFullEnvironment,

        [switch] $Automation,

        [string] $StorageAccount,

        [string] $StorageContainer,

        [string] $Title = 'Azure tenant assessment',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    # A failure anywhere below ends as a Spectre.Console error panel and this
    # command's own terminating error, not a line inside the module. A stopped
    # pipeline (Select-Object -First, Ctrl+C) is no failure: just return - a
    # rethrow would stop the caller's whole script, not only this command.
    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    if (($StorageAccount -and -not $StorageContainer) -or ($StorageContainer -and -not $StorageAccount)) {
        throw 'Uploading the reports needs both -StorageAccount and -StorageContainer.'
    }
    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward -and -not $Automation
    $returnObjects = $PassThru -or $NoDisplay -or $pipedOnward

    # --- Sign-in -----------------------------------------------------------------------------------------------
    $session = $script:AACSession
    if ($Automation -and -not $session) {
        Connect-AAC -Identity | Out-Null
    }
    elseif ($TenantId) {
        # A domain is the tenant's too: compare their IDs.
        $wantedTenant = Resolve-AACTenantId -Tenant $TenantId
        if (-not $session -or ([string]$session.TenantId).ToLowerInvariant() -ne $wantedTenant) {
            Connect-AAC -TenantId $wantedTenant | Out-Null
        }
    }

    # --- Where the reports go --------------------------------------------------------------------------------------
    # Each report where its own parameter says. An upload with no report asked
    # for writes them all to a temporary folder, so a runbook needs no paths.
    $stamp = Get-Date -Format 'yyyy-MM-dd_HHmm'
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } else { '' } }
    $paths = @{ Html = & $resolve $HtmlPath; Pdf = & $resolve $PdfPath; Csv = & $resolve $CsvPath; Diagram = & $resolve $DiagramPath }
    if ($StorageAccount -and -not @($paths.Values | Where-Object { $_ }).Count) {
        $temporary = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "TenantAssessment-$stamp"
        $paths = @{ Html = Join-Path -Path $temporary -ChildPath 'TenantAssessment.html'; Pdf = Join-Path -Path $temporary -ChildPath 'TenantAssessment.pdf'; Csv = Join-Path -Path $temporary -ChildPath 'csv'; Diagram = Join-Path -Path $temporary -ChildPath 'diagrams' }
    }

    # Read here, not inside the progress block (it runs in Invoke-AACProgress's scope).
    $request = @{
        ManagementGroupId = @($ManagementGroupId | Where-Object { $_ })
        SubscriptionId    = @($SubscriptionId | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() })
        ResourceGroupName = @($ResourceGroupName | Where-Object { $_ })
        TagKey            = $TagKey
        TagValue          = $TagValue
        Category          = @($Category | Where-Object { $_ })
        IncludeTag        = [bool]($IncludeTag -or $Full)
        SecurityCenter    = [bool]($SecurityCenter -or $Full)
        SkipAdvisor       = [bool]$SkipAdvisor
        SkipPolicy        = [bool]$SkipPolicy
        PSRule            = [bool]($PSRule -or $Full)
        PSRuleBaseline    = $PSRuleBaseline
        Waf               = -not $SkipWaf
        CostTag           = @($CostTag)
        IncludeCost       = [bool]($IncludeCost -or $Full)
        QuotaUsage        = [bool]($QuotaUsage -or $Full)
        SkipIdentity      = [bool]$SkipIdentity
        SkipKeyVault      = [bool]$SkipKeyVault
        ActivityDays      = $ActivityDays
        ExpiryDays        = $ExpiryDays
        OwnerTag          = @($OwnerTag)
        ProductionPattern = $ProductionPattern
        SkipApi           = [bool]$SkipApi
        SkipVMDetail      = [bool]$SkipVMDetail
        FullEnvironment   = [bool]$DiagramFullEnvironment
        Paths             = $paths
        Stamp             = $stamp
        Title             = $Title
        StorageAccount    = $StorageAccount
        StorageContainer  = $StorageContainer
    }

    if ($interactive) {
        Write-AACRule -Title 'Azure Admin Console :: Azure tenant assessment' -Color 'deepskyblue3_1'
    }
    $state = Invoke-AACProgress -ScriptBlock {
        $null = Get-AACAccessToken
        $timing = [ordered]@{}
        $clock = [System.Diagnostics.Stopwatch]::StartNew()
        $lap = { param([string] $Phase) $timing[$Phase] = $clock.Elapsed; $clock.Restart() }
        $rowsOf = { param($Read, [string] $Name) @(if ($Read.Rows.Contains($Name)) { $Read.Rows[$Name] }) | Where-Object { $null -ne $_ } }

        # --- 1. Scope ---------------------------------------------------------------------------------------------
        Update-AACProgress -Id 'scope' -Description 'Finding the subscriptions and management groups in scope' -Indeterminate
        $read = Invoke-AACGraphBatch -Query (Get-AACAssessmentExtraQuery -Stage Scope) -AllowFailure 'managementGroups'
        $subscriptions = @(& $rowsOf $read 'subscriptions')
        $managementGroups = @(& $rowsOf $read 'managementGroups')
        $chainNames = { param($Row) @(@($Row['chain']) | Where-Object { $_ } | ForEach-Object { ([string]$_['name']).ToLowerInvariant() }) }
        if ($request.ManagementGroupId.Count) {
            $wanted = @($request.ManagementGroupId | ForEach-Object { $_.ToLowerInvariant() })
            $subscriptions = @($subscriptions | Where-Object { $names = & $chainNames $_; @($wanted | Where-Object { $names -contains $_ }).Count })
            if (-not $subscriptions.Count) {
                $problem = [System.InvalidOperationException]::new("No subscription the account can see is under management group $($request.ManagementGroupId -join ', ').")
                $problem.Data['AACHint'] = 'Use the management group''s ID (its name), not its display name - and check the account has Reader on it.'
                throw $problem
            }
        }
        if ($request.SubscriptionId.Count) {
            $found = @($subscriptions | Where-Object { $request.SubscriptionId -contains ([string]$_['subscriptionId']).ToLowerInvariant() })
            foreach ($id in $request.SubscriptionId) { if (-not @($found | Where-Object { ([string]$_['subscriptionId']).ToLowerInvariant() -eq $id }).Count) { Write-Warning "Subscription $id isn't one the account can see; it's left out." } }
            if (-not $found.Count) { throw "None of the subscriptions $($request.SubscriptionId -join ', ') is one the account can see." }
            $subscriptions = $found
        }
        if (-not $subscriptions.Count) {
            $problem = [System.InvalidOperationException]::new('The account can see no subscription.')
            $problem.Data['AACHint'] = 'Give the account Reader on the subscriptions (or a management group above them), or sign in to the right tenant with Connect-AAC -TenantId.'
            throw $problem
        }
        $scoped = $request.ManagementGroupId.Count -or $request.SubscriptionId.Count
        # Unscoped, every query covers everything the account can see.
        $graphScope = if ($scoped) { @($subscriptions | ForEach-Object { [string]$_['subscriptionId'] }) } else { @() }
        $subscriptionNames = @{}
        foreach ($row in $subscriptions) { $subscriptionNames[([string]$row['subscriptionId']).ToLowerInvariant()] = [string]$row['name'] }
        Update-AACProgress -Id 'scope' -Complete -Description ('Scope: {0:N0} subscription(s){1}' -f $subscriptions.Count, $(if ($managementGroups.Count) { " under $($managementGroups.Count) management group(s)" }))
        & $lap 'Scope'

        # --- 2. Estate: every resource, the containers, Advisor, Defender, Policy ----------------------------------------
        $filter = Get-AACAssessmentQuery -Filter -ResourceGroupName $request.ResourceGroupName -TagKey $request.TagKey -TagValue $request.TagValue
        $estate = Get-AACAssessmentExtraQuery -Stage Estate -Filter $filter -ResourceGroupName $request.ResourceGroupName -SkipAdvisor:$request.SkipAdvisor -SecurityCenter:$request.SecurityCenter -SkipPolicy:$request.SkipPolicy
        $labels = @{ types = 'resource types'; resources = 'resources'; groups = 'resource groups'; advisor = $(if ($request.SkipAdvisor) { 'retirements' } else { 'Advisor recommendations' }); security = 'Defender for Cloud recommendations'; secureScores = 'secure scores'; policy = 'Azure Policy compliance'; policyByGroup = 'policy compliance by resource group'; policyByResource = 'policy compliance by resource'; policyResources = 'non-compliant resources'; supportTickets = 'support tickets' }
        Update-AACProgress -Id 'estate' -Total $estate.Count -Description 'Reading every resource, resource group, Advisor, Defender and Policy'
        $read = Invoke-AACGraphBatch -Query $estate -SubscriptionId $graphScope -AllowFailure @($estate.Keys | Where-Object { $_ -notin 'types', 'resources' }) -OnProgress {
            param($Name, $Done, $Total)
            Update-AACProgress -Id 'estate' -Increment 1 -Description "Read the $($labels[$Name]) ($Done of $Total)"
        }
        $failed = [ordered]@{}
        foreach ($key in $read.Errors.Keys) { if ($key -ne 'supportTickets') { $failed[$labels[$key]] = $read.Errors[$key] } }
        $resources = @(& $rowsOf $read 'resources')
        $typeRows = @(& $rowsOf $read 'types')
        Update-AACProgress -Id 'estate' -Complete -Description ('Estate: {0:N0} resource(s) of {1:N0} type(s) in {2:N0} resource group(s)' -f $resources.Count, @($typeRows | ForEach-Object { $_['type'] } | Select-Object -Unique).Count, @(& $rowsOf $read 'groups').Count)
        $estateRead = $read
        & $lap 'Estate'

        # --- 3. Inventory: a sheet per resource type present ----------------------------------------------------------
        $present = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($row in $typeRows) { [void]$present.Add(([string]$row['type']).ToLowerInvariant()) }
        $catalog = @(Get-AACAssessmentCatalog | Where-Object { -not $request.Category.Count -or $request.Category -contains $_.Category })
        $sheetQueries = [ordered]@{}
        $compiled = @{}
        foreach ($sheet in $catalog) {
            $table = if ($sheet.Contains('Table') -and $sheet.Table) { $sheet.Table } else { 'resources' }
            # Other tables (backup items, session hosts) aren't in the type count: always asked.
            if ($table -eq 'resources' -and -not @($sheet.Type | Where-Object { $present.Contains(([string]$_).ToLowerInvariant()) }).Count) { continue }
            $query = Get-AACAssessmentQuery -Sheet $sheet -ResourceGroupName $request.ResourceGroupName -TagKey $request.TagKey -TagValue $request.TagValue -IncludeTag:$request.IncludeTag
            $compiled[$sheet.Sheet] = $query
            $sheetQueries[$sheet.Sheet] = $query.Query
        }
        $sheetRows = @{}
        $sheetErrors = @{}
        if ($sheetQueries.Count) {
            Update-AACProgress -Id 'inventory' -Total $sheetQueries.Count -Description "Reading $($sheetQueries.Count) resource type sheet(s)"
            $read = Invoke-AACGraphBatch -Query $sheetQueries -SubscriptionId $graphScope -AllowFailure @($sheetQueries.Keys) -OnProgress {
                param($Name, $Done, $Total)
                Update-AACProgress -Id 'inventory' -Increment 1 -Description "Read $Name ($Done of $Total sheets)"
            }
            foreach ($name in $sheetQueries.Keys) { $sheetRows[$name] = @(& $rowsOf $read $name) }
            foreach ($name in $read.Errors.Keys) { $sheetErrors[$name] = $read.Errors[$name] }
        }
        $withRows = @($sheetRows.Keys | Where-Object { $sheetRows[$_].Count }).Count
        Update-AACProgress -Id 'inventory' -Complete -Description ('Inventory: {0:N0} sheet(s) with resources{1}' -f $withRows, $(if ($sheetErrors.Count) { ", $($sheetErrors.Count) couldn't be read" }))
        & $lap 'Inventory'

        # --- 4. Azure APIs, per subscription ---------------------------------------------------------------------------
        $arm = @{}
        if (-not $request.SkipApi) {
            $active = @($subscriptions | Where-Object { [string]$_['state'] -in 'Enabled', 'Warned', 'PastDue', '' } | ForEach-Object { [string]$_['subscriptionId'] })
            $uris = [ordered]@{}
            $since = [uri]::EscapeDataString((Get-Date).AddMonths(-6).ToString('MM/dd/yyyy', [cultureinfo]::InvariantCulture))
            foreach ($sub in $active) {
                if (-not $request.SkipAdvisor) { $uris["AdvisorScore|$sub"] = "/subscriptions/$sub/providers/Microsoft.Advisor/advisorScore?api-version=2023-01-01" }
                $uris["Reservation|$sub"] = "/subscriptions/$sub/providers/Microsoft.Consumption/reservationRecommendations?api-version=2023-05-01"
                $uris["Budget|$sub"] = "/subscriptions/$sub/providers/Microsoft.Consumption/budgets?api-version=2023-05-01"
                $uris["Outage|$sub"] = "/subscriptions/$sub/providers/Microsoft.ResourceHealth/events?api-version=2022-10-01&queryStartTime=$since"
            }
            # Where the VMs and scale sets are: their sizes, and the quotas.
            $computeTypes = 'microsoft.compute/virtualmachines', 'microsoft.compute/virtualmachinescalesets'
            $computeAt = @($typeRows | Where-Object { [string]$_['type'] -in $computeTypes })
            if (-not $request.SkipVMDetail) {
                foreach ($location in @($computeAt | ForEach-Object { ([string]$_['location']).ToLowerInvariant() } | Where-Object { $_ } | Select-Object -Unique)) {
                    $sub = @($computeAt | Where-Object { ([string]$_['location']).ToLowerInvariant() -eq $location } | ForEach-Object { [string]$_['subscriptionId'] })[0]
                    $uris["Sku|$location"] = "/subscriptions/$sub/providers/Microsoft.Compute/skus?api-version=2021-07-01&`$filter=$([uri]::EscapeDataString("location eq '$location'"))"
                }
            }
            if ($request.QuotaUsage) {
                foreach ($pair in @($computeAt | ForEach-Object { "$([string]$_['subscriptionId'])|$(([string]$_['location']).ToLowerInvariant())" } | Select-Object -Unique)) {
                    $sub, $location = $pair -split '\|', 2
                    $uris["Quota|$pair"] = "/subscriptions/$sub/providers/Microsoft.Compute/locations/$location/usages?api-version=2023-09-01"
                }
            }
            if ($uris.Count) {
                Update-AACProgress -Id 'api' -Total $uris.Count -Description "Asking $($active.Count) subscription(s) for the Advisor score, reservations, budgets, outages$(if ($request.QuotaUsage) { ', quotas' })$(if (-not $request.SkipVMDetail) { ' and VM sizes' })"
                $answers = Invoke-AACArmParallel -Uri @($uris.Values) -OnProgress { param($Done, $Total) Update-AACProgress -Id 'api' -Increment 1 }
                $unread = 0
                foreach ($key in $uris.Keys) {
                    $kind, $rest = $key -split '\|', 2
                    $answer = $answers[$uris[$key]]
                    if (-not $arm.Contains($kind)) { $arm[$kind] = @{} }
                    if (-not $answer -or $answer.Error) { $unread++; Write-Debug "$key couldn't be read: $(if ($answer) { $answer.Error })"; continue }
                    $arm[$kind][$rest] = @(if ($null -ne $answer.Items) { $answer.Items } elseif ($answer.Body -is [System.Collections.IDictionary] -and $answer.Body.Contains('value')) { $answer.Body['value'] })
                }
                Update-AACProgress -Id 'api' -Complete -Description ('Azure APIs: {0:N0} call(s){1}' -f $uris.Count, $(if ($unread) { ", $unread not answered (no access, or not registered)" }))
            }
        }
        & $lap 'APIs'
        $notices = [System.Collections.Generic.List[string]]::new()
        $inScopeIds = @($subscriptions | ForEach-Object { ([string]$_['subscriptionId']).ToLowerInvariant() })
        # A tag filter or resource groups narrow the estate; the WAF and PSRule
        # reads can't apply a tag filter, so their results are kept to these.
        $estateIds = $null
        if ($request.TagKey -or $request.TagValue -or $request.ResourceGroupName.Count) {
            $estateIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($row in $resources) { [void]$estateIds.Add(([string]$row['id']).ToLowerInvariant()) }
        }

        # --- 5. Well-Architected: Invoke-AACWafAssessment's checks, across the scope -----------------------------------
        $waf = $null
        if ($request.Waf) {
            $wafCatalog = Get-AACWafCatalog
            $wafTypes = @($wafCatalog.Checks | ForEach-Object { $_.Type } | Select-Object -Unique)
            $wafCategories = if ($request.SkipAdvisor) { @() } else { @('HighAvailability', 'Security', 'Cost', 'OperationalExcellence', 'Performance') }
            $wafQueries = Get-AACWafQuery -ResourceType $wafTypes -ResourceGroupName $request.ResourceGroupName -AdvisorCategory $wafCategories -NoDefender:(-not $request.SecurityCenter)
            Update-AACProgress -Id 'waf' -Total $wafQueries.Count -Description 'Reading what the Well-Architected checks test'
            $read = Invoke-AACGraphBatch -Query $wafQueries -SubscriptionId $graphScope -AllowFailure @($wafQueries.Keys) -OnProgress {
                param($Name, $Done, $Total)
                Update-AACProgress -Id 'waf' -Increment 1 -Description "Well-Architected: read the $Name ($Done of $Total)"
            }
            if ($read.Errors.Contains('resources')) {
                $notices.Add("The Well-Architected checks couldn't run: $($read.Errors['resources'] -replace '\s+', ' ')")
                Update-AACProgress -Id 'waf' -Complete -Description 'Well-Architected: not assessed - the resources couldn''t be read'
            }
            else {
                foreach ($key in @($read.Errors.Keys | Sort-Object)) { $notices.Add("Well-Architected: the $key couldn't be read, so their checks are left out: $($read.Errors[$key] -replace '\s+', ' ')") }
                $waf = ConvertTo-AACWafAssessment -Read $read.Rows -Catalog $wafCatalog -SubscriptionName $subscriptionNames -CostTag $request.CostTag
                if ($estateIds) { $waf.Results = @($waf.Results | Where-Object { [string]$_.ResourceId -notmatch '(?i)/providers/' -or $estateIds.Contains(([string]$_.ResourceId).ToLowerInvariant()) }) }
                Update-AACProgress -Id 'waf' -Complete -Description ('Well-Architected: {0} overall; {1:N0} check(s) on {2:N0} resource(s), {3:N0} failed ({4:N0} high)' -f $(if ($null -ne $waf.Overall) { "$($waf.Overall)/100" } else { 'not scored' }), $waf.Stats.Assessed, $waf.Stats.Resources, $waf.Stats.Failed, $waf.Stats.High)
            }
        }
        & $lap 'Well-Architected'

        # --- 6. Cost -------------------------------------------------------------------------------------------------
        $cost = $null
        if ($request.IncludeCost) {
            $costScope = @($subscriptions | ForEach-Object { @{ subscriptionId = [string]$_['subscriptionId']; name = [string]$_['name']; state = [string]$_['state'] } })
            $cost = Read-AACInventoryCost -TenantId ([string]$script:AACSession.TenantId) -Subscription $costScope -ManagementGroupId $request.ManagementGroupId -PerSubscription:([bool]($request.SubscriptionId.Count -or $request.ResourceGroupName.Count -or $request.TagKey -or $request.TagValue))
        }
        & $lap 'Cost'

        # --- 7. PSRule for Azure ---------------------------------------------------------------------------------------
        $psruleResults = @()
        $psruleRead = $false
        if ($request.PSRule) {
            if (-not (Get-Module -Name 'PSRule.Rules.Azure' -ListAvailable)) {
                $notices.Add('PSRule for Azure is not installed, so its rules were not run: Install-PSResource PSRule.Rules.Azure -Scope CurrentUser')
            }
            else {
                try {
                    $engine = @{ SubscriptionId = $inScopeIds }
                    if ($request.PSRuleBaseline) { $engine.Baseline = $request.PSRuleBaseline }
                    $psruleResults = @((Invoke-AACPSRuleEngine @engine).Results)
                    if ($request.ResourceGroupName.Count) { $psruleResults = @($psruleResults | Where-Object { $request.ResourceGroupName -contains [string]$_.ResourceGroup }) }
                    $psruleRead = $true
                }
                catch { $notices.Add("PSRule for Azure couldn't run: $($_.Exception.Message)") }
            }
            & $lap 'PSRule'
        }

        # --- 7b. Identity, architecture, operations and service delivery ---------------------------------------------------
        $insightQueries = Get-AACAssessmentInsightQuery -Filter $filter -SkipIdentity:$request.SkipIdentity
        Update-AACProgress -Id 'insight' -Total $insightQueries.Count -Description 'Reading access, network, monitoring and patching (one Resource Graph batch)'
        $insightRead = Invoke-AACGraphBatch -Query $insightQueries -SubscriptionId $graphScope -AllowFailure @($insightQueries.Keys) -OnProgress {
            param($Name, $Done, $Total)
            Update-AACProgress -Id 'insight' -Increment 1 -Description "Read the $Name ($Done of $Total)"
        }
        foreach ($key in @($insightRead.Errors.Keys | Sort-Object)) { $notices.Add("The $key couldn't be read, so what depends on it is left out: $($insightRead.Errors[$key] -replace '\s+', ' ')") }
        Update-AACProgress -Id 'insight' -Complete -Description "Read access, network, monitoring and patching ($($insightQueries.Count) queries)"
        $insightArm = @{}
        $insightAsked = @{}
        if (-not $request.SkipApi) {
            $insightUris = [ordered]@{}
            $ask = { param([string] $Kind, [string] $Key, [string] $Uri) $insightUris["$Kind|$Key"] = $Uri; if (-not $insightAsked.Contains($Kind)) { $insightAsked[$Kind] = [System.Collections.Generic.List[string]]::new() }; $insightAsked[$Kind].Add($Key) }
            $activeSubs = @($subscriptions | Where-Object { [string]$_['state'] -in 'Enabled', 'Warned', 'PastDue', '' } | ForEach-Object { ([string]$_['subscriptionId']).ToLowerInvariant() })
            $from = [uri]::EscapeDataString("eventTimestamp ge '$((Get-Date).ToUniversalTime().AddDays(-$request.ActivityDays).ToString('yyyy-MM-ddTHH:mm:ssZ'))' and eventTimestamp le '$((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))'")
            foreach ($sub in $activeSubs) {
                & $ask 'ClassicAdmin' $sub "/subscriptions/$sub/providers/Microsoft.Authorization/classicAdministrators?api-version=2015-07-01"
                & $ask 'Lock' $sub "/subscriptions/$sub/providers/Microsoft.Authorization/locks?api-version=2020-05-01"
                if ($request.ActivityDays -gt 0) { & $ask 'Activity' $sub "/subscriptions/$sub/providers/Microsoft.Insights/eventtypes/management/values?api-version=2015-04-01&`$filter=$from&`$select=$([uri]::EscapeDataString('eventTimestamp,operationName,status,caller,resourceId,resourceGroupName,category,correlationId'))" }
                if (-not $request.SkipIdentity) {
                    & $ask 'Active' "/subscriptions/$sub" "/subscriptions/$sub/providers/Microsoft.Authorization/roleAssignmentScheduleInstances?api-version=2020-10-01&`$filter=atScope()"
                    & $ask 'Eligible' "/subscriptions/$sub" "/subscriptions/$sub/providers/Microsoft.Authorization/roleEligibilityScheduleInstances?api-version=2020-10-01&`$filter=atScope()"
                }
            }
            if (-not $request.SkipIdentity) {
                # The management groups above the subscriptions in scope (privileged roles there reach every subscription below).
                $groupsAbove = @($subscriptions | ForEach-Object { @($_['chain']) } | Where-Object { $_ } | ForEach-Object { ([string]$_['name']).ToLowerInvariant() } | Select-Object -Unique)
                foreach ($group in $groupsAbove) {
                    $scope = "/providers/Microsoft.Management/managementGroups/$group"
                    & $ask 'Active' $scope.ToLowerInvariant() "$scope/providers/Microsoft.Authorization/roleAssignmentScheduleInstances?api-version=2020-10-01&`$filter=atScope()"
                    & $ask 'Eligible' $scope.ToLowerInvariant() "$scope/providers/Microsoft.Authorization/roleEligibilityScheduleInstances?api-version=2020-10-01&`$filter=atScope()"
                }
            }
            if ($activeSubs.Count) { & $ask 'Location' 'all' "/subscriptions/$($activeSubs[0])/locations?api-version=2022-12-01" }
            & $ask 'Reservation' 'all' '/providers/Microsoft.Capacity/reservations?api-version=2022-11-01'
            & $ask 'SavingsPlan' 'all' "/providers/Microsoft.BillingBenefits/savingsPlans?api-version=2022-11-01&`$expand=$([uri]::EscapeDataString('properties/utilization'))"
            # Diagnostic settings of the types that have resource logs (a sample of at most 500 resources).
            $logTypes = @(
                'microsoft.keyvault/vaults', 'microsoft.sql/servers/databases', 'microsoft.web/sites', 'microsoft.network/applicationgateways', 'microsoft.network/azurefirewalls', 'microsoft.network/networksecuritygroups'
                'microsoft.containerservice/managedclusters', 'microsoft.documentdb/databaseaccounts', 'microsoft.eventhub/namespaces', 'microsoft.servicebus/namespaces', 'microsoft.logic/workflows'
                'microsoft.cognitiveservices/accounts', 'microsoft.apimanagement/service', 'microsoft.dbforpostgresql/flexibleservers', 'microsoft.dbformysql/flexibleservers', 'microsoft.containerregistry/registries'
                'microsoft.network/frontdoors', 'microsoft.cdn/profiles', 'microsoft.datafactory/factories', 'microsoft.recoveryservices/vaults', 'microsoft.automation/automationaccounts', 'microsoft.network/virtualnetworkgateways', 'microsoft.cache/redis'
            )
            $logged = @($resources | Where-Object { ([string]$_['type']).ToLowerInvariant() -in $logTypes })
            foreach ($row in $logged | Select-Object -First 500) { $id = ([string]$row['id']).ToLowerInvariant(); & $ask 'Diagnostic' $id "$id/providers/Microsoft.Insights/diagnosticSettings?api-version=2021-05-01-preview" }
            if ($logged.Count -gt 500) { $notices.Add("Diagnostic settings were checked for 500 of the $($logged.Count) resources that have resource logs (Get-AACDiagnosticSetting checks them all).") }
            Update-AACProgress -Id 'insight-api' -Total $insightUris.Count -Description "Asking for PIM, classic administrators, locks, the Activity Log, diagnostic settings, reservations and savings plans ($($insightUris.Count) calls)"
            $answers = Invoke-AACArmParallel -Uri @($insightUris.Values) -OnProgress { param($Done, $Total) Update-AACProgress -Id 'insight-api' -Increment 1 }
            foreach ($key in $insightUris.Keys) {
                $kind, $rest = $key -split '\|', 2
                $answer = $answers[$insightUris[$key]]
                if (-not $answer -or $answer.Error) { continue }
                if (-not $insightArm.Contains($kind)) { $insightArm[$kind] = @{} }
                $insightArm[$kind][$rest] = @(if ($null -ne $answer.Items) { $answer.Items } elseif ($answer.Body -is [System.Collections.IDictionary] -and $answer.Body.Contains('value')) { $answer.Body['value'] })
            }
            Update-AACProgress -Id 'insight-api' -Complete -Description "Asked $($insightUris.Count) question(s) of Azure Resource Manager"
        }
        # Microsoft Graph: who the privileged principals are, and the app registrations' credentials.
        $directory = @{}; $directoryRead = $false; $applications = @(); $applicationsRead = $false
        if (-not $request.SkipIdentity) {
            $privilegedRoles = @(& $rowsOf $insightRead 'roleDefinitions' | Where-Object { [string]$_['roleName'] -in 'Owner', 'User Access Administrator', 'Role Based Access Control Administrator' -or ([string]$_['roleType'] -eq 'CustomRole' -and (ConvertTo-Json -InputObject $_['permissions'] -Depth 6 -Compress) -match '"\*"') } | ForEach-Object { ([string]$_['name']).ToLowerInvariant() })
            $eligibleIds = @(if ($insightArm.Contains('Eligible')) { $insightArm.Eligible.Values | ForEach-Object { $_ } | Where-Object { $_ } | ForEach-Object { ([string](Get-AACMember -InputObject $_ -Path 'properties.principalId')).ToLowerInvariant() } })
            $principalIds = @(@(& $rowsOf $insightRead 'roleAssignments' | Where-Object { ([string]$_['roleId'] -replace '^.*/', '') -in $privilegedRoles -and [string]$_['scope'] -match '^(/|/providers/microsoft\.management/managementgroups/[^/]+|/subscriptions/[^/]+)$' } | ForEach-Object { [string]$_['principalId'] }) + $eligibleIds | Where-Object { $_ } | Select-Object -Unique)
            Update-AACProgress -Id 'entra' -Indeterminate -Description 'Reading the privileged principals and app registrations from Microsoft Graph'
            try {
                if ($principalIds.Count) { $found = Get-AACDirectoryObject -Id $principalIds; $directory = $found.Objects; $directoryRead = -not $found.Error; if ($found.Error) { $notices.Add("The privileged principals couldn't be looked up in Microsoft Graph: $($found.Error)") } }
                $graph = Read-AACGraphQuery -Query ([ordered]@{ applications = 'https://graph.microsoft.com/v1.0/applications?$select=id,appId,displayName,passwordCredentials,keyCredentials&$top=999' })
                if (-not $graph.Errors.Contains('applications')) { $applications = @($graph.Data['applications']); $applicationsRead = $true }
            }
            catch { $notices.Add("Microsoft Graph couldn't be read: $($_.Exception.Message)") }
            Update-AACProgress -Id 'entra' -Complete -Description ('Microsoft Graph: {0:N0} privileged principal(s), {1:N0} app registration(s)' -f $principalIds.Count, $applications.Count)
        }
        # Key Vault expiry dates, from each vault's data plane (metadata only, never a value).
        $vaultItems = @(); $vaultAccess = @{}; $vaultRead = $false
        $vaultRows = @($resources | Where-Object { ([string]$_['type']).ToLowerInvariant() -eq 'microsoft.keyvault/vaults' })
        if (-not $request.SkipKeyVault -and $vaultRows.Count) {
            Update-AACProgress -Id 'vaults' -Indeterminate -Description "Listing the secrets, keys and certificates of $($vaultRows.Count) Key Vault(s)"
            try {
                $vaultObjects = Read-AACKeyVaultObject -Vault @($vaultRows | ForEach-Object { @{ Id = [string]$_['id']; Name = [string]$_['name']; Uri = "https://$($_['name']).vault.azure.net/" } })
                $vaultItems = @($vaultObjects.Items); $vaultAccess = $vaultObjects.Access; $vaultRead = $true
            }
            catch { $notices.Add("The Key Vaults couldn't be listed: $($_.Exception.Message)") }
            Update-AACProgress -Id 'vaults' -Complete -Description ('Key Vaults: {0:N0} secret(s), key(s) and certificate(s) in {1:N0} vault(s)' -f $vaultItems.Count, $vaultRows.Count)
        }
        # Six months of cost per subscription, for the month-on-month trend.
        $costTrend = @{}
        if ($request.IncludeCost) {
            $first = (Get-Date).Date.AddDays(1 - (Get-Date).Day).AddMonths(-5)
            $trendBody = @{ type = 'ActualCost'; timeframe = 'Custom'; timePeriod = @{ from = $first.ToString('yyyy-MM-ddT00:00:00Z'); to = (Get-Date).ToString('yyyy-MM-ddT23:59:59Z') }; dataset = @{ granularity = 'Monthly'; aggregation = @{ totalCost = @{ name = 'Cost'; function = 'Sum' } } } }
            try {
                $trend = Invoke-AACCostBatch -Scope @($inScopeIds | ForEach-Object { "/subscriptions/$_" }) -Body $trendBody
                foreach ($scope in $trend.Keys) { if ($trend[$scope].Status -eq 'OK') { $costTrend[($scope -replace '^/subscriptions/', '')] = @($trend[$scope].Rows) } }
            }
            catch { $notices.Add("The cost trend couldn't be read: $($_.Exception.Message)") }
        }
        & $lap 'Insight'

        # --- 8. The assessment -------------------------------------------------------------------------------------------
        Update-AACProgress -Id 'assess' -Description 'Building the sheets and the overview' -Indeterminate
        $tenantRoot = @($managementGroups | Where-Object { -not $_['parent'] }) | Select-Object -First 1
        $policyRead = -not $request.SkipPolicy -and -not $estateRead.Errors.Contains('policy')
        $assessment = ConvertTo-AACAssessment -Catalog $catalog -Compiled $compiled -SheetRow $sheetRows -SheetError $sheetErrors -Resource $resources `
            -Subscription $subscriptions -ResourceGroup @(& $rowsOf $estateRead 'groups') -ManagementGroup $managementGroups -Advisor @(& $rowsOf $estateRead 'advisor') `
            -Security @(& $rowsOf $estateRead 'security') -SecureScore @(& $rowsOf $estateRead 'secureScores') -Policy @(& $rowsOf $estateRead 'policy') `
            -SupportTicket @(& $rowsOf $estateRead 'supportTickets') -Arm $arm -Cost $cost -TenantId ([string]$script:AACSession.TenantId) `
            -TenantName $(if ($tenantRoot) { [string]$tenantRoot['displayName'] } else { '' }) -IncludeTag:$request.IncludeTag `
            -AdvisorRead:(-not $request.SkipAdvisor -and -not $estateRead.Errors.Contains('advisor')) -SecurityRead:($request.SecurityCenter -and -not $estateRead.Errors.Contains('security')) `
            -PolicyRead:($policyRead -and -not $estateRead.Errors.Contains('policyByResource')) -PolicyByResource @(& $rowsOf $estateRead 'policyByResource') `
            -WafResult @(if ($waf) { $waf.Results }) -WafRead:([bool]$waf) -PSRuleResult $psruleResults -PSRuleRead:$psruleRead
        foreach ($line in @($assessment.Notices)) { $notices.Add($line) }
        foreach ($key in $failed.Keys) { $notices.Add("The $key couldn't be read: $($failed[$key])") }
        if ($cost) { foreach ($line in @($cost.Notice)) { if ($line) { $notices.Add($line) } } }
        if ($waf) {
            $wafSheets = ConvertTo-AACAssessmentWaf -Waf $waf
            $assessment.Sheets = @($assessment.Sheets) + @($wafSheets.Sheets)
            foreach ($key in $wafSheets.Stats.Keys) { $assessment.Stats[$key] = $wafSheets.Stats[$key] }
        }
        $finops = ConvertTo-AACAssessmentCost -Sheet $assessment.Sheets -Resource $resources -Subscription $subscriptions -WafResult @(if ($waf) { $waf.Results }) `
            -Budget $(if ($arm.Contains('Budget')) { $arm.Budget } else { @{} }) -BudgetRead:(-not $request.SkipApi) -CostRead:([bool]$cost) -CostTag $request.CostTag
        $assessment.Sheets = @($assessment.Sheets) + @($finops.Sheets)
        foreach ($key in $finops.Stats.Keys) { $assessment.Stats[$key] = $finops.Stats[$key] }
        $insight = ConvertTo-AACAssessmentInsight -Read $insightRead.Rows -Arm $insightArm -Asked $insightAsked -Directory $directory -Application $applications -VaultItem $vaultItems -VaultAccess $vaultAccess `
            -CostTrend $costTrend -Resource $resources -Subscription $subscriptions -ResourceGroup @(& $rowsOf $estateRead 'groups') -ManagementGroup $managementGroups -Sheet $assessment.Sheets `
            -OwnerTag $request.OwnerTag -ProductionPattern $request.ProductionPattern -ExpiryDays $request.ExpiryDays -ActivityDays $request.ActivityDays `
            -IdentityRead:(-not $request.SkipIdentity -and -not $insightRead.Errors.Contains('roleAssignments')) -DirectoryRead:$directoryRead -ApplicationRead:$applicationsRead -VaultRead:$vaultRead -CostRead:([bool]$costTrend.Count)
        $assessment.Sheets = @($assessment.Sheets) + @($insight.Sheets)
        foreach ($key in $insight.Stats.Keys) { $assessment.Stats[$key] = $insight.Stats[$key] }
        foreach ($line in @($insight.Notices)) { $notices.Add($line) }
        $assessment.Notices = $notices.ToArray()
        Update-AACProgress -Id 'assess' -Complete -Description ('Assessed: {0:N0} sheet(s), {1:N0} retirement(s){2}; {3:N0} savings opportunit(ies)' -f @($assessment.Sheets | Where-Object { @($_.Rows).Count }).Count, $assessment.Stats.Retirements, $(if ($null -ne $assessment.Stats.Advisor) { ", $($assessment.Stats.AdvisorHigh) High-impact Advisor recommendation(s)" }), $assessment.Stats.SavingsOpportunities)
        & $lap 'Assess'

        # --- 8b. Governance: the policy inventory, one list of recommendations ----------------------------------------------
        $assignedPolicy = $null
        if (-not $request.SkipPolicy) {
            try {
                $policyData = Read-AACAssignedPolicyData
                $assignedPolicy = ConvertTo-AACAssignedPolicy -Assignment $policyData.Assignments -Definition $policyData.Definitions -SubscriptionName $policyData.SubscriptionNames -ManagementGroupName $policyData.GroupNames `
                    -SubscriptionChain $policyData.SubscriptionChain -GroupChain $policyData.GroupChain -SubscriptionId $inScopeIds
            }
            catch { $notices.Add("The policy assignments couldn't be read: $($_.Exception.Message)") }
        }
        Update-AACProgress -Id 'governance' -Description 'Building the policy, PSRule and recommendation sheets' -Indeterminate
        $nameOf = @{}
        foreach ($sub in $subscriptions) { $nameOf[([string]$sub['subscriptionId']).ToLowerInvariant()] = [string]$sub['name'] }
        $governance = ConvertTo-AACAssessmentGovernance -Sheet $assessment.Sheets -Policy @(& $rowsOf $estateRead 'policy') -PolicyByGroup @(& $rowsOf $estateRead 'policyByGroup') `
            -PolicyResource @(& $rowsOf $estateRead 'policyResources') -AssignedPolicy $assignedPolicy -PSRuleResult $psruleResults -SubscriptionName $nameOf -PolicyRead:$policyRead -PSRuleRead:$psruleRead -Finding @($insight.Findings)
        $assessment.Sheets = @($assessment.Sheets) + @($governance.Sheets)
        foreach ($key in $governance.Stats.Keys) { $assessment.Stats[$key] = $governance.Stats[$key] }
        foreach ($line in @($governance.Notices)) { $notices.Add($line) }
        $assessment.Notices = $notices.ToArray()
        $g = $governance.Stats
        Update-AACProgress -Id 'governance' -Complete -Description ('Governance: {0:N0} policy assignment(s), {1:N0} failed polic(ies), {2:N0} non-compliant resource(s){3}; {4:N0} recommendation(s), {5:N0} critical or high' -f $g.PolicyAssignments, $g.PoliciesFailed, $g.NonCompliantResources, $(if ($psruleRead) { "; PSRule: $($g.PSRuleFailed) failure(s)" }), $g.Recommendations, $g.RecommendationsUrgent)
        & $lap 'Governance'

        # --- 7. The reports --------------------------------------------------------------------------------------------
        $scope = [ordered]@{
            Scope = if ($request.ManagementGroupId.Count) { "management group(s) $($request.ManagementGroupId -join ', ')" } elseif ($request.SubscriptionId.Count) { "subscription(s) $(@($subscriptions | ForEach-Object { $_['name'] }) -join ', ')" } else { 'everything the account can see' }
        }
        if ($request.ResourceGroupName.Count) { $scope['Resource groups'] = $request.ResourceGroupName -join ', ' }
        if ($request.TagKey -or $request.TagValue) { $scope['Tag'] = "$(if ($request.TagKey) { $request.TagKey } else { '*' }) = $(if ($request.TagValue) { $request.TagValue } else { '*' })" }
        if ($request.Category.Count) { $scope['Categories'] = $request.Category -join ', ' }
        $files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
        # The upload keeps each report's place: the CSV files and diagrams in a folder of their own.
        $uploadRoot = @{}
        $write = {
            # One report: its own progress line; a failure is noted, the others still written.
            param([string] $Id, [string] $Doing, [string] $Folder, [scriptblock] $Writer)
            Update-AACProgress -Id $Id -Description $Doing -Indeterminate
            try {
                if ($Folder -and -not (Test-Path -LiteralPath $Folder)) { New-Item -ItemType Directory -Path $Folder -Force | Out-Null }
                $written = @(& $Writer)
                foreach ($item in $written) { if ($item -is [System.IO.FileInfo]) { $files.Add($item); $uploadRoot[$item.FullName] = $Folder } }
                $first = @($written | Where-Object { $_ -is [System.IO.FileInfo] })
                Update-AACProgress -Id $Id -Complete -Description $(if ($first.Count -eq 1) { "${Id}: $($first[0].FullName)" } else { "${Id}: $($first.Count) file(s) in $Folder" })
            }
            catch {
                $notices.Add("The $Id report couldn't be written: $($_.Exception.Message)")
                Update-AACProgress -Id $Id -Complete -Description "${Id}: not written - $($_.Exception.Message)"
            }
        }
        $reportPath = $request.Paths
        if ($reportPath.Html) { & $write 'HTML' 'Writing the HTML report' (Split-Path -Path $reportPath.Html -Parent) { Write-AACAssessmentHtml -Assessment $assessment -Path $reportPath.Html -Title $request.Title -Detail $scope } }
        if ($reportPath.Pdf) { & $write 'PDF' 'Writing the PDF report' (Split-Path -Path $reportPath.Pdf -Parent) { Write-AACAssessmentPdf -Assessment $assessment -Path $reportPath.Pdf -Title $request.Title -Detail $scope } }
        if ($reportPath.Csv) { & $write 'CSV' 'Writing a CSV file per sheet' (Split-Path -Path $reportPath.Csv -Parent) { Write-AACAssessmentCsv -Assessment $assessment -Path $reportPath.Csv } }
        if ($reportPath.Diagram) {
            & $write 'Diagrams' 'Reading the network and drawing the diagrams' (Split-Path -Path $reportPath.Diagram -Parent) {
                if (-not (Test-Path -LiteralPath $reportPath.Diagram)) { New-Item -ItemType Directory -Path $reportPath.Diagram -Force | Out-Null }
                $diagram = Get-AACAssessmentExtraQuery -Stage Diagram -Filter $filter -FullEnvironment:$request.FullEnvironment
                $rows = @(& $rowsOf (Invoke-AACGraphBatch -Query $diagram -SubscriptionId $graphScope) 'diagram')
                Write-AACAssessmentDiagram -Folder $reportPath.Diagram -ReportName 'TenantAssessment' -Resource $rows -Inventory $resources -Organization $assessment.Organization -SubscriptionName $subscriptionNames -Scope $scope.Scope -FullEnvironment:$request.FullEnvironment
            }
        }
        & $lap 'Reports'

        # --- 8. Upload ----------------------------------------------------------------------------------------------
        $uploads = @()
        if ($request.StorageAccount -and $files.Count) {
            Update-AACProgress -Id 'upload' -Description "Uploading $($files.Count) file(s) to $($request.StorageAccount)/$($request.StorageContainer)" -Indeterminate
            $uploads = @(foreach ($group in $files | Group-Object { $uploadRoot[$_.FullName] }) {
                    Send-AACBlobFile -StorageAccount $request.StorageAccount -Container $request.StorageContainer -Path @($group.Group | ForEach-Object FullName) -Root $group.Name -Prefix "TenantAssessment/$($request.Stamp)"
                })
            $bad = @($uploads | Where-Object { $_.Status -ne 'Uploaded' })
            foreach ($item in $bad) { $notices.Add("$($item.Blob) wasn't uploaded: $($item.Error)") }
            Update-AACProgress -Id 'upload' -Complete -Description ('Uploaded {0} of {1} file(s) to {2}/{3}' -f ($uploads.Count - $bad.Count), $uploads.Count, $request.StorageAccount, $request.StorageContainer)
            & $lap 'Upload'
        }
        $assessment.Notices = $notices.ToArray()
        @{ Assessment = $assessment; Scope = $scope; Files = $files.ToArray(); Timing = $timing; Uploads = $uploads }
    }

    $assessment = $state.Assessment
    if ($interactive) {
        Invoke-AACPagedOutput -NoPaging:$NoPaging -ScriptBlock {
            Show-AACAssessmentView -Assessment $assessment -Scope $state.Scope -File $state.Files -Timing $state.Timing
        }
    }
    elseif ($Automation) {
        foreach ($line in @($assessment.Notices)) { Write-Warning $line }
        Write-Output ('Assessed {0:N0} resource(s) in {1:N0} subscription(s): {2:N0} file(s) written' -f $assessment.Stats.Resources, $assessment.Stats.Subscriptions, @($state.Files).Count)
    }
    if ($returnObjects) {
        $sheets = [ordered]@{}
        foreach ($sheet in $assessment.Sheets) { $sheets[$sheet.Sheet] = @($sheet.Rows) }
        [pscustomobject][ordered]@{
            PSTypeName     = 'AAC.TenantAssessment'
            Subscriptions  = $assessment.Stats.Subscriptions
            ResourceGroups = $assessment.Stats.ResourceGroups
            Resources      = $assessment.Stats.Resources
            ResourceTypes  = $assessment.Stats.ResourceTypes
            AdvisorHigh    = $assessment.Stats.AdvisorHigh
            Retirements    = $assessment.Stats.Retirements
            SecurityHigh   = $assessment.Stats.SecurityHigh
            Outages        = $assessment.Stats.Outages
            WafScore       = $(if ($assessment.Stats.Contains('WafScore')) { $assessment.Stats.WafScore } else { $null })
            AnnualSavings  = $assessment.Stats.AnnualSavings
            Recommendations = $assessment.Stats.Recommendations
            Files          = @($state.Files)
            Sheets         = $sheets
            Stats          = $assessment.Stats
            Notices        = @($assessment.Notices)
            Timing         = $state.Timing
            Uploads        = @($state.Uploads)
        }
    }
}
