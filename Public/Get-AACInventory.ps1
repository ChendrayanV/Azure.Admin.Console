function Get-AACInventory {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Inventories the tenant as a tree - management groups, subscriptions,
        resource groups and resources - with a Spectre.Console tree view,
        objects, and CSV, PDF and interactive HTML exports.
    .DESCRIPTION
        Reads everything with Azure Resource Graph (Reader access is enough;
        no Az modules): the management groups, the subscriptions and the
        management group each is in, the resource groups and the resources.
        The tree is:

          Tenant
            Management groups (nested as in Azure)
              Subscriptions
                Resource groups (location, most common resource types)
                  Resources (type, location, SKU)

        with the number of subscriptions, resource groups and resources
        below every node. Management groups with no subscription in the result
        are left out, unless you asked for them with -ManagementGroupId. A
        subscription in a management group you can't read is shown under the
        tenant. Empty resource groups are flagged.

        Security posture comes from Microsoft Defender for Cloud (Resource
        Graph's securityresources; Reader or Security Reader is enough), in
        colour:
          - each subscription's secure score - Defender's own (current / max)
            - and management groups' and the tenant's, their subscriptions'
            scores added up as Defender does
          - each resource's score - the share of its assessed recommendations
            that are healthy - and its unhealthy findings by severity, rolled
            up to its resource group
          - Good (70% or more) green, Fair (40-69%) amber, Poor (under 40%)
            red; High findings red, Medium amber, Low blue, Healthy green
          - the security controls with the potential score increase of fixing
            each (their impact), and every unhealthy recommendation with its
            severity, user impact, effort and resource
        Without Defender data (not enabled, or no access) the inventory is
        shown without it. -NoSecurity skips reading it.

        What you get depends on where the command runs:
          at the prompt    tiles, the tree (down to -Depth; resource groups by
                           default) and the most common resource types - a
                           page at a time
          piped onward     the objects, with no view
          -PassThru        the view and the objects
          -NoDisplay       the objects only
        One AAC.InventoryItem per node: Level (Tenant, ManagementGroup,
        Subscription, ResourceGroup, Resource), Depth, Name, Path, the
        management group, subscription and resource group it is in, Type,
        Kind, Location, SKU, State, the counts below it, TopTypes,
        SecureScore, Rating, Severity, High, Medium, Low, Findings,
        TopFindings, Tags, Id.

        -CsvPath writes every node as a CSV row. -HtmlPath writes an
        interactive report: tiles, charts, the hierarchy as a collapsible,
        searchable tree with each node's score and findings in colour (click
        a node to see it in the tables), and tables of management groups,
        subscriptions, resource groups, resources, security controls and
        recommendations, each with its own CSV download. -PdfPath writes a
        PDF: the summary, the hierarchy, security (scores, controls,
        recommendations), subscriptions, resource groups, resources by type
        and the resources. With any of them, the console shows only the progress and
        the files written.
    .PARAMETER ManagementGroupId
        Only these management groups (their IDs, e.g. 'mg-corp') and
        everything below them.
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ResourceGroupName
        Only these resource groups (in the subscriptions or management groups
        given, or in any you can see).
    .PARAMETER Depth
        How deep the console tree goes: ManagementGroup, Subscription,
        ResourceGroup (the default) or Resource. The objects and exports
        always have everything.
    .PARAMETER NoSecurity
        Don't read Microsoft Defender for Cloud: no secure scores, findings
        or recommendations.
    .PARAMETER CsvPath
        Write every node - tenant, management groups, subscriptions,
        resource groups and resources - to this CSV file.
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
        Get-AACInventory
        The whole tenant as a tree, down to resource groups.
    .EXAMPLE
        Get-AACInventory -ManagementGroupId 'mg-landingzones' -Depth Resource
        One management group, down to every resource.
    .EXAMPLE
        Get-AACInventory -SubscriptionId '00000000-0000-0000-0000-000000000000' -HtmlPath .\out\Inventory.html -PdfPath .\out\Inventory.pdf
        One subscription as an interactive HTML report and a PDF.
    .EXAMPLE
        Get-AACInventory -NoDisplay | Where-Object { $_.Level -eq 'ResourceGroup' -and $_.Resources -eq 0 }
        The empty resource groups.
    .OUTPUTS
        AAC.InventoryItem (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.InventoryItem')]
    param(
        [ValidateNotNullOrEmpty()]
        [string[]] $ManagementGroupId,

        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [ValidateNotNullOrEmpty()]
        [string[]] $ResourceGroupName,

        [ValidateSet('ManagementGroup', 'Subscription', 'ResourceGroup', 'Resource')]
        [string] $Depth = 'ResourceGroup',

        [switch] $NoSecurity,

        [string] $CsvPath,

        [string] $PdfPath,

        [string] $HtmlPath,

        [string] $Title = 'Azure tenant inventory',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    # A failure anywhere below ends as a Spectre.Console error panel and this
    # command's own terminating error, not a line inside the module.
    trap { $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $exporting = $CsvPath -or $PdfPath -or $HtmlPath
    $showView = $interactive -and -not $exporting
    $returnObjects = $PassThru -or $NoDisplay -or $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $csvFullPath = & $resolve $CsvPath
    $pdfFullPath = & $resolve $PdfPath
    $htmlFullPath = & $resolve $HtmlPath
    $quote = { param([string] $Text) "'" + ($Text -replace '\\', '\\' -replace "'", "\'") + "'" }

    # Resource Graph through ARM: rows as hashtables (tags whose keys differ
    # only by case are fine), following $skipToken; scoped to subscriptions
    # or management groups when given.
    $graph = {
        param([string] $Query, [switch] $Tenant)
        $body = @{ query = $Query; options = @{ resultFormat = 'objectArray' } }
        if (-not $Tenant) {
            if ($SubscriptionId) { $body.subscriptions = @($SubscriptionId) }
            elseif ($ManagementGroupId) { $body.managementGroups = @($ManagementGroupId) }
        }
        do {
            $response = Invoke-AACArmRequest -Method Post -Uri '/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01' -Body ($body | ConvertTo-Json -Depth 10)
            $response['data']
            $skipToken = $response['$skipToken']
            $body.options['$skipToken'] = $skipToken
        } while ($skipToken)
    }
    $groupFilter = if ($ResourceGroupName) { "($((@($ResourceGroupName | ForEach-Object { & $quote $_ })) -join ', '))" } else { '' }

    if ($interactive) {
        Write-AACRule -Title 'Azure Admin Console :: Tenant inventory' -Color 'deepskyblue3_1'
    }
    $state = Invoke-AACProgress -ScriptBlock {
        $null = Get-AACAccessToken
        $notices = [System.Collections.Generic.List[string]]::new()
        Update-AACProgress -Id 'read' -Total $(if ($NoSecurity) { 5 } else { 6 }) -Description 'Reading the tenant'
        $tenantId = if ($script:AACSession) { [string]$script:AACSession.TenantId } else { '' }
        $tenantName = ''
        try {
            $tenants = Invoke-AACArmRequest -Uri '/tenants?api-version=2022-12-01'
            $match = @($tenants['value']) | Where-Object { [string]$_['tenantId'] -eq $tenantId } | Select-Object -First 1
            if ($match) { $tenantName = (@([string]$match['displayName'], [string]$match['defaultDomain']) | Where-Object { $_ } | Select-Object -First 1) }
        }
        catch { Write-Debug "The tenant's name couldn't be read: $($_.Exception.Message)" }

        Update-AACProgress -Id 'read' -Increment 1 -Description 'Reading the management groups'
        $groups = @()
        try {
            $groups = @(& $graph "resourcecontainers | where type =~ 'microsoft.management/managementgroups' | project id, name, displayName = tostring(properties.displayName), parentId = tostring(properties.details.parent.id)" -Tenant)
        }
        catch { $notices.Add("The management groups couldn't be read ($($_.Exception.Message -replace '\s+', ' ')), so subscriptions are shown under the tenant.") }
        if (-not $groups.Count) { $notices.Add('No management groups are visible to this account, so subscriptions are shown under the tenant.') }
        # With -ManagementGroupId: those groups, the groups below them, and
        # the groups above them (the path from the tenant).
        if ($ManagementGroupId) {
            $byName = @{}
            foreach ($group in $groups) { $byName[([string]$group['name']).ToLowerInvariant()] = $group }
            $missing = @($ManagementGroupId | Where-Object { -not $byName.Contains($_.ToLowerInvariant()) })
            if ($missing.Count -eq $ManagementGroupId.Count -and $groups.Count) { throw "No management group with the ID $(($missing | ForEach-Object { "'$_'" }) -join ', ') was found. Use the group's ID (its name), not its display name." }
            foreach ($name in $missing) { Write-Warning "No management group with the ID '$name' was found; it's left out." }
        }

        Update-AACProgress -Id 'read' -Increment 1 -Description 'Reading the subscriptions'
        $subscriptions = @(& $graph "resourcecontainers | where type =~ 'microsoft.resources/subscriptions' | project subscriptionId, name, state = tostring(properties.state), parentGroup = tostring(properties.managementGroupAncestorsChain[0].name), quotaId = tostring(properties.subscriptionPolicies.quotaId), tags")

        Update-AACProgress -Id 'read' -Increment 1 -Description 'Reading the resource groups'
        $resourceGroups = @(& $graph "resourcecontainers | where type =~ 'microsoft.resources/subscriptions/resourcegroups'$(if ($groupFilter) { " and name in~ $groupFilter" }) | project id, name, subscriptionId, location, state = tostring(properties.provisioningState), managedBy, tags")
        if ($ResourceGroupName) {
            $found = @($resourceGroups | ForEach-Object { [string]$_['name'] })
            $missing = @($ResourceGroupName | Where-Object { $name = $_; -not @($found | Where-Object { $_ -eq $name }).Count })
            if ($missing.Count -eq $ResourceGroupName.Count) { throw "No resource group named $(($missing | ForEach-Object { "'$_'" }) -join ', ') was found in the subscriptions you can see$(if ($SubscriptionId -or $ManagementGroupId) { ' in that scope' })." }
            foreach ($name in $missing) { Write-Warning "No resource group named '$name' was found; it's left out." }
            # Only the subscriptions those groups are in.
            $withGroups = @($resourceGroups | ForEach-Object { ([string]$_['subscriptionId']).ToLowerInvariant() } | Select-Object -Unique)
            $subscriptions = @($subscriptions | Where-Object { ([string]$_['subscriptionId']).ToLowerInvariant() -in $withGroups })
        }

        Update-AACProgress -Id 'read' -Increment 1 -Description 'Reading the resources'
        $resources = @(& $graph "resources$(if ($groupFilter) { " | where resourceGroup in~ $groupFilter" }) | project id, name, type, kind, location, resourceGroup, subscriptionId, sku = tostring(sku.name), zones, tags")
        # Microsoft Defender for Cloud: secure scores, controls, and each
        # resource's assessments (a summary, and the unhealthy ones).
        $security = $null
        if (-not $NoSecurity) {
            Update-AACProgress -Id 'read' -Increment 1 -Description 'Reading Microsoft Defender for Cloud: secure scores and recommendations'
            try {
                $assessments = "securityresources | where type =~ 'microsoft.security/assessments' | extend resourceId = tolower(coalesce(tostring(properties.resourceDetails.Id), tostring(properties.resourceDetails.ResourceId))), status = tostring(properties.status.code), severity = tostring(properties.metadata.severity)"
                $security = @{
                    Scores          = @(& $graph "securityresources | where type =~ 'microsoft.security/securescores' and name == 'ascScore' | project subscriptionId, current = todouble(properties.score.current), max = todouble(properties.score.max)")
                    Controls        = @(& $graph "securityresources | where type =~ 'microsoft.security/securescores/securescorecontrols' | project subscriptionId, control = tostring(properties.displayName), current = todouble(properties.score.current), max = todouble(properties.score.max), healthy = toint(properties.healthyResourceCount), unhealthy = toint(properties.unhealthyResourceCount)")
                    Summary         = @(& $graph "$assessments | where status in ('Healthy', 'Unhealthy') | summarize healthy = countif(status == 'Healthy'), unhealthy = countif(status == 'Unhealthy'), high = countif(status == 'Unhealthy' and severity == 'High'), medium = countif(status == 'Unhealthy' and severity == 'Medium'), low = countif(status == 'Unhealthy' and severity == 'Low') by resourceId")
                    Recommendations = @(& $graph "$assessments | where status == 'Unhealthy' | project resourceId, subscriptionId, name = tostring(properties.displayName), severity, impact = tostring(properties.metadata.userImpact), effort = tostring(properties.metadata.implementationEffort), categories = strcat_array(properties.metadata.categories, ', '), cause = tostring(properties.status.cause)")
                }
                if (-not @(@($security.Scores) + @($security.Summary) | Where-Object { $_ }).Count) {
                    $notices.Add('No Microsoft Defender for Cloud data was found in this scope (not enabled, or no access), so there are no secure scores.')
                }
            }
            catch {
                $security = $null
                $notices.Add("Microsoft Defender for Cloud couldn't be read ($($_.Exception.Message -replace '\s+', ' ')), so there are no secure scores.")
            }
        }
        Update-AACProgress -Id 'read' -Complete -Description ('Read {0:N0} management group(s), {1:N0} subscription(s), {2:N0} resource group(s) and {3:N0} resource(s)' -f $groups.Count, $subscriptions.Count, $resourceGroups.Count, $resources.Count)

        Update-AACProgress -Id 'tree' -Description 'Building the tree' -Indeterminate
        $inventory = ConvertTo-AACInventory -TenantId $tenantId -TenantName $tenantName -ManagementGroup $groups -Subscription $subscriptions -ResourceGroup $resourceGroups -Resource $resources -KeepManagementGroup @($ManagementGroupId | Where-Object { $_ }) -Security $security
        $inventory.Notice = $notices.ToArray()
        $posture = if ($inventory.Stats.HasSecurity -and $null -ne $inventory.Stats.SecureScore) { ", secure score $($inventory.Stats.SecureScore)%" } else { '' }
        Update-AACProgress -Id 'tree' -Complete -Description ('Tree: {0:N0} management group(s) > {1:N0} subscription(s) > {2:N0} resource group(s) > {3:N0} resource(s){4}' -f $inventory.Stats.ManagementGroups, $inventory.Stats.Subscriptions, $inventory.Stats.ResourceGroups, $inventory.Stats.Resources, $posture)

        $scope = [ordered]@{
            Scope = if ($ManagementGroupId) { "management group(s) $($ManagementGroupId -join ', ')" } elseif ($SubscriptionId) { "subscription(s) $($SubscriptionId -join ', ')" } else { 'the whole tenant (everything the account can see)' }
        }
        if ($ResourceGroupName) { $scope['Resource groups'] = $ResourceGroupName -join ', ' }
        $null = Invoke-AACExport -CsvPath $csvFullPath -CsvObject @($inventory.Items | Select-Object -Property * -ExcludeProperty Depth) -Noun 'item' -PdfPath $pdfFullPath -WritePdf {
            Write-AACInventoryPdf -Inventory $inventory -Path $pdfFullPath -Title $Title -Detail $scope
        } -HtmlPath $htmlFullPath -WriteHtml {
            Write-AACInventoryHtml -Inventory $inventory -Path $htmlFullPath -Title $Title -Detail $scope
        }
        @{ Inventory = $inventory; Scope = $scope }
    }
    $inventory = $state.Inventory

    if ($showView) {
        Invoke-AACPagedOutput -NoPaging:$NoPaging -ScriptBlock {
            Show-AACInventoryView -Inventory $inventory -Depth $Depth -Scope $state.Scope
        }
    }
    elseif ($interactive -and $inventory.Notice) {
        foreach ($notice in $inventory.Notice) { Write-AACMarkup "[grey58]$([Spectre.Console.Markup]::Escape($notice))[/]" }
    }

    if ($returnObjects) {
        $inventory.Items
    }
}
