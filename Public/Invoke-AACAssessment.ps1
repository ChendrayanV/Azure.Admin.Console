function Invoke-AACAssessment {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Assesses an Azure environment end to end - an inventory of every
        resource type with its key settings, the organization, Advisor,
        retirements, Defender for Cloud, Azure Policy, outages, quotas and
        cost - as CSV files, an interactive HTML report, a PDF and
        interactive diagrams, with a live Spectre.Console progress display.
    .DESCRIPTION
        The module's take on Azure Resource Inventory (ARI): one command
        reads the tenant (or the subscriptions, management groups, resource
        groups or tag you name) and writes the reports you choose. Read-only;
        Reader is enough (Security Reader for Defender, Cost Management
        Reader for cost); no Az modules, no Excel.

        What it reads, in phases - each a line of the progress display:
          1. Scope        the subscriptions (with their management groups) in
                          scope, and the tenant's management groups
          2. Estate       every resource and resource group, the resource
                          types present; Advisor recommendations (and
                          retirements, always); Defender for Cloud
                          (-SecurityCenter); Azure Policy compliance (unless
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
                          recommendations, the last 6 months' outages
                          (Resource Health service issues), compute quotas
                          (-QuotaUsage), and VM sizes' vCPUs and memory
                          (unless -SkipVMDetail); -SkipApi skips them all
          5. Cost         each resource's cost, this month and last
                          (-IncludeCost, Cost Management)
          6. Reports      CSV, HTML, PDF and diagrams (-Output), then an
                          upload to a blob container (-StorageAccount)

        Every inventory sheet adds, after its own columns: Retirement (an
        Advisor retirement notice for the resource), Advisor (its number of
        recommendations), its cost with -IncludeCost, and its tags with
        -IncludeTag. The overview sheets: Subscriptions, Resource groups,
        Resource types, All resources; then Advisor recommendations,
        Advisor score, Retirements, Security recommendations, Secure score,
        Policy compliance, Outages, Quotas, Support tickets and Reservation
        recommendations.

        The reports, in -ReportDir (a folder named after -ReportName and
        the time):
          HTML      one page: tiles, charts, the tenant tree, and every sheet
                    as a table under its category, listed in the contents -
                    searchable, filterable, groupable, each downloadable as CSV
          CSV       a file per sheet
          PDF       the summary, then each category with its sheets' key
                    columns (bookmarked)
          Diagram   <name>-Network.html: the network topology - virtual
                    networks, subnets, peerings, gateways, firewalls, load
                    balancers, private endpoints, NSGs and routes
                    (-DiagramFullEnvironment: every resource and how they
                    connect); <name>-Organization.html: management groups >
                    subscriptions > resource groups; <name>-Resources.html:
                    each subscription with its resource types and counts.
                    Interactive: pan, zoom, search, details on click, PNG and
                    SVG export.

        Sign-in: the Connect-AAC session. -TenantId signs in to that tenant
        first (in the browser) when the session is for another one. In
        Azure Automation, -Automation signs in with the account's managed
        identity (Connect-AAC -Identity) if no session is there yet,
        writes plain progress lines for the job log, and with
        -StorageAccount and -StorageContainer uploads the reports to blob
        storage (Storage Blob Data Contributor needed).
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
        Don't read Azure Policy compliance.
    .PARAMETER IncludeCost
        Read each resource's actual cost, this month and last (Cost
        Management Reader).
    .PARAMETER QuotaUsage
        Read the compute quotas in use, per subscription and region.
    .PARAMETER SkipApi
        Don't call the per-subscription Azure APIs (Advisor score,
        reservations, outages, quotas, VM sizes) - Resource Graph only.
    .PARAMETER SkipVMDetail
        Don't read VM sizes' vCPUs and memory (Compute SKUs).
    .PARAMETER SkipDiagram
        Don't draw the diagrams (same as leaving Diagram out of -Output).
    .PARAMETER DiagramFullEnvironment
        Draw every resource in the network diagram, not only the network.
    .PARAMETER Output
        The reports to write: Html, Pdf, Csv, Diagram. All of them by default.
    .PARAMETER ReportName
        The reports' name: AzureAssessment by default.
    .PARAMETER ReportDir
        Where the reports go: a folder named <ReportName>-<date> is made in
        it. The current folder by default (the temporary folder with
        -Automation).
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
        Invoke-AACAssessment
        The whole tenant (everything the account can see): every report, in .\AzureAssessment-<date>.
    .EXAMPLE
        Invoke-AACAssessment -TenantId 'contoso.onmicrosoft.com' -SecurityCenter -IncludeTag -IncludeCost
        Another tenant, with Defender for Cloud, tags and cost.
    .EXAMPLE
        Invoke-AACAssessment -ManagementGroupId 'mg-landingzones' -ReportDir C:\Reports -Output Html, Diagram
        A management group's subscriptions: the HTML report and the diagrams.
    .EXAMPLE
        Invoke-AACAssessment -SubscriptionId 00000000-0000-0000-0000-000000000000 -TagKey 'Environment' -TagValue 'Production' -Category Compute, Networking
        Production's compute and network resources in one subscription.
    .EXAMPLE
        Invoke-AACAssessment -Automation -StorageAccount 'stcontosoreports' -StorageContainer 'assessments'
        In an Azure Automation runbook: managed identity sign-in, and the reports uploaded to blob storage.
    .EXAMPLE
        (Invoke-AACAssessment -Output Csv -NoDisplay).Sheets['Virtual machines'] | Where-Object 'Power state' -NE 'VM running'
        The VMs that aren't running.
    .OUTPUTS
        AAC.Assessment (with -PassThru or -NoDisplay, or piped onward)
    #>
    [CmdletBinding()]
    [OutputType('AAC.Assessment')]
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

        [switch] $IncludeCost,

        [switch] $QuotaUsage,

        [switch] $SkipApi,

        [switch] $SkipVMDetail,

        [switch] $SkipDiagram,

        [switch] $DiagramFullEnvironment,

        [ValidateSet('Html', 'Pdf', 'Csv', 'Diagram')]
        [string[]] $Output = @('Html', 'Pdf', 'Csv', 'Diagram'),

        [ValidatePattern('^[^\\/:*?"<>|]+$')]
        [string] $ReportName = 'AzureAssessment',

        [string] $ReportDir,

        [switch] $Automation,

        [string] $StorageAccount,

        [string] $StorageContainer,

        [string] $Title = 'Azure environment assessment',

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
    $stamp = Get-Date -Format 'yyyy-MM-dd_HHmm'
    $baseDir = if ($ReportDir) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReportDir) } elseif ($Automation) { [System.IO.Path]::GetTempPath() } else { $PSCmdlet.SessionState.Path.CurrentFileSystemLocation.ProviderPath }
    $folder = Join-Path -Path $baseDir -ChildPath "$ReportName-$stamp"
    $outputs = @($Output | Where-Object { $_ -ne 'Diagram' -or -not $SkipDiagram })

    # Read here, not inside the progress block (it runs in Invoke-AACProgress's scope).
    $request = @{
        ManagementGroupId = @($ManagementGroupId | Where-Object { $_ })
        SubscriptionId    = @($SubscriptionId | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() })
        ResourceGroupName = @($ResourceGroupName | Where-Object { $_ })
        TagKey            = $TagKey
        TagValue          = $TagValue
        Category          = @($Category | Where-Object { $_ })
        IncludeTag        = [bool]$IncludeTag
        SecurityCenter    = [bool]$SecurityCenter
        SkipAdvisor       = [bool]$SkipAdvisor
        SkipPolicy        = [bool]$SkipPolicy
        IncludeCost       = [bool]$IncludeCost
        QuotaUsage        = [bool]$QuotaUsage
        SkipApi           = [bool]$SkipApi
        SkipVMDetail      = [bool]$SkipVMDetail
        FullEnvironment   = [bool]$DiagramFullEnvironment
        Outputs           = $outputs
        Folder            = $folder
        ReportName        = $ReportName
        Title             = $Title
        StorageAccount    = $StorageAccount
        StorageContainer  = $StorageContainer
    }

    if ($interactive) {
        Write-AACRule -Title 'Azure Admin Console :: Azure environment assessment' -Color 'deepskyblue3_1'
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
        $labels = @{ types = 'resource types'; resources = 'resources'; groups = 'resource groups'; advisor = $(if ($request.SkipAdvisor) { 'retirements' } else { 'Advisor recommendations' }); security = 'Defender for Cloud recommendations'; secureScores = 'secure scores'; policy = 'Azure Policy compliance'; supportTickets = 'support tickets' }
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
                Update-AACProgress -Id 'api' -Total $uris.Count -Description "Asking $($active.Count) subscription(s) for the Advisor score, reservations, outages$(if ($request.QuotaUsage) { ', quotas' })$(if (-not $request.SkipVMDetail) { ' and VM sizes' })"
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

        # --- 5. Cost -------------------------------------------------------------------------------------------------
        $cost = $null
        if ($request.IncludeCost) {
            $costScope = @($subscriptions | ForEach-Object { @{ subscriptionId = [string]$_['subscriptionId']; name = [string]$_['name']; state = [string]$_['state'] } })
            $cost = Read-AACInventoryCost -TenantId ([string]$script:AACSession.TenantId) -Subscription $costScope -ManagementGroupId $request.ManagementGroupId -PerSubscription:([bool]($request.SubscriptionId.Count -or $request.ResourceGroupName.Count -or $request.TagKey -or $request.TagValue))
        }
        & $lap 'Cost'

        # --- 6. The assessment -------------------------------------------------------------------------------------------
        Update-AACProgress -Id 'assess' -Description 'Building the sheets and the overview' -Indeterminate
        $tenantRoot = @($managementGroups | Where-Object { -not $_['parent'] }) | Select-Object -First 1
        $assessment = ConvertTo-AACAssessment -Catalog $catalog -Compiled $compiled -SheetRow $sheetRows -SheetError $sheetErrors -Resource $resources `
            -Subscription $subscriptions -ResourceGroup @(& $rowsOf $estateRead 'groups') -ManagementGroup $managementGroups -Advisor @(& $rowsOf $estateRead 'advisor') `
            -Security @(& $rowsOf $estateRead 'security') -SecureScore @(& $rowsOf $estateRead 'secureScores') -Policy @(& $rowsOf $estateRead 'policy') `
            -SupportTicket @(& $rowsOf $estateRead 'supportTickets') -Arm $arm -Cost $cost -TenantId ([string]$script:AACSession.TenantId) `
            -TenantName $(if ($tenantRoot) { [string]$tenantRoot['displayName'] } else { '' }) -IncludeTag:$request.IncludeTag `
            -AdvisorRead:(-not $request.SkipAdvisor -and -not $estateRead.Errors.Contains('advisor')) -SecurityRead:($request.SecurityCenter -and -not $estateRead.Errors.Contains('security')) `
            -PolicyRead:(-not $request.SkipPolicy -and -not $estateRead.Errors.Contains('policy'))
        $notices = [System.Collections.Generic.List[string]]::new()
        foreach ($line in @($assessment.Notices)) { $notices.Add($line) }
        foreach ($key in $failed.Keys) { $notices.Add("The $key couldn't be read: $($failed[$key])") }
        if ($cost) { foreach ($line in @($cost.Notice)) { if ($line) { $notices.Add($line) } } }
        $assessment.Notices = $notices.ToArray()
        Update-AACProgress -Id 'assess' -Complete -Description ('Assessed: {0:N0} sheet(s), {1:N0} retirement(s){2}' -f @($assessment.Sheets | Where-Object { @($_.Rows).Count }).Count, $assessment.Stats.Retirements, $(if ($null -ne $assessment.Stats.Advisor) { ", $($assessment.Stats.AdvisorHigh) High-impact Advisor recommendation(s)" }))
        & $lap 'Assess'

        # --- 7. The reports --------------------------------------------------------------------------------------------
        $scope = [ordered]@{
            Scope = if ($request.ManagementGroupId.Count) { "management group(s) $($request.ManagementGroupId -join ', ')" } elseif ($request.SubscriptionId.Count) { "subscription(s) $(@($subscriptions | ForEach-Object { $_['name'] }) -join ', ')" } else { 'everything the account can see' }
        }
        if ($request.ResourceGroupName.Count) { $scope['Resource groups'] = $request.ResourceGroupName -join ', ' }
        if ($request.TagKey -or $request.TagValue) { $scope['Tag'] = "$(if ($request.TagKey) { $request.TagKey } else { '*' }) = $(if ($request.TagValue) { $request.TagValue } else { '*' })" }
        if ($request.Category.Count) { $scope['Categories'] = $request.Category -join ', ' }
        $files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
        if (-not (Test-Path -LiteralPath $request.Folder)) { New-Item -ItemType Directory -Path $request.Folder -Force | Out-Null }
        $write = {
            # One report: its own progress line; a failure is noted, the others still written.
            param([string] $Id, [string] $Doing, [scriptblock] $Writer)
            Update-AACProgress -Id $Id -Description $Doing -Indeterminate
            try {
                $written = @(& $Writer)
                foreach ($item in $written) { if ($item -is [System.IO.FileInfo]) { $files.Add($item) } }
                $first = @($written | Where-Object { $_ -is [System.IO.FileInfo] })
                Update-AACProgress -Id $Id -Complete -Description $(if ($first.Count -eq 1) { "${Id}: $($first[0].FullName)" } else { "${Id}: $($first.Count) file(s) in $($request.Folder)" })
            }
            catch {
                $notices.Add("The $Id report couldn't be written: $($_.Exception.Message)")
                Update-AACProgress -Id $Id -Complete -Description "${Id}: not written - $($_.Exception.Message)"
            }
        }
        $base = Join-Path -Path $request.Folder -ChildPath $request.ReportName
        if ($request.Outputs -contains 'Csv') { & $write 'CSV' 'Writing a CSV file per sheet' { Write-AACAssessmentCsv -Assessment $assessment -Path (Join-Path -Path $request.Folder -ChildPath 'csv') } }
        if ($request.Outputs -contains 'Html') { & $write 'HTML' 'Writing the HTML report' { Write-AACAssessmentHtml -Assessment $assessment -Path "$base.html" -Title $request.Title -Detail $scope } }
        if ($request.Outputs -contains 'Pdf') { & $write 'PDF' 'Writing the PDF report' { Write-AACAssessmentPdf -Assessment $assessment -Path "$base.pdf" -Title $request.Title -Detail $scope } }
        if ($request.Outputs -contains 'Diagram') {
            & $write 'Diagrams' 'Reading the network and drawing the diagrams' {
                $diagram = Get-AACAssessmentExtraQuery -Stage Diagram -Filter $filter -FullEnvironment:$request.FullEnvironment
                $rows = @(& $rowsOf (Invoke-AACGraphBatch -Query $diagram -SubscriptionId $graphScope) 'diagram')
                Write-AACAssessmentDiagram -Folder $request.Folder -ReportName $request.ReportName -Resource $rows -Inventory $resources -Organization $assessment.Organization -SubscriptionName $subscriptionNames -Scope $scope.Scope -FullEnvironment:$request.FullEnvironment
            }
        }
        & $lap 'Reports'

        # --- 8. Upload ----------------------------------------------------------------------------------------------
        $uploads = @()
        if ($request.StorageAccount -and $files.Count) {
            Update-AACProgress -Id 'upload' -Description "Uploading $($files.Count) file(s) to $($request.StorageAccount)/$($request.StorageContainer)" -Indeterminate
            $uploads = @(Send-AACBlobFile -StorageAccount $request.StorageAccount -Container $request.StorageContainer -Path @($files | ForEach-Object FullName) -Root (Split-Path -Path $request.Folder -Parent) -Prefix $request.ReportName)
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
        Write-Output ('Assessed {0:N0} resource(s) in {1:N0} subscription(s): {2:N0} file(s) in {3}' -f $assessment.Stats.Resources, $assessment.Stats.Subscriptions, @($state.Files).Count, $folder)
    }
    if ($returnObjects) {
        $sheets = [ordered]@{}
        foreach ($sheet in $assessment.Sheets) { $sheets[$sheet.Sheet] = @($sheet.Rows) }
        [pscustomobject][ordered]@{
            PSTypeName     = 'AAC.Assessment'
            Subscriptions  = $assessment.Stats.Subscriptions
            ResourceGroups = $assessment.Stats.ResourceGroups
            Resources      = $assessment.Stats.Resources
            ResourceTypes  = $assessment.Stats.ResourceTypes
            AdvisorHigh    = $assessment.Stats.AdvisorHigh
            Retirements    = $assessment.Stats.Retirements
            SecurityHigh   = $assessment.Stats.SecurityHigh
            Outages        = $assessment.Stats.Outages
            ReportFolder   = $folder
            Files          = @($state.Files)
            Sheets         = $sheets
            Stats          = $assessment.Stats
            Notices        = @($assessment.Notices)
            Timing         = $state.Timing
            Uploads        = @($state.Uploads)
        }
    }
}
