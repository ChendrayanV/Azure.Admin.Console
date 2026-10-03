function Get-AACDiagnosticSetting {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Lists every resource's diagnostic settings, flattened, and finds the
        resources whose logs don't reach a Log Analytics workspace - and the
        settings that are misconfigured - with a Spectre.Console view,
        objects, and CSV, PDF and interactive HTML reports.
    .DESCRIPTION
        Read-only, in three steps:
          1. Every resource in scope, with a KQL query (Azure Resource Graph),
             and the subscriptions (for their activity log). A storage
             account's logs are set on its blob, file, queue and table
             services, which Resource Graph doesn't list: they are added.
          2. Which of them have resource logs: Azure's own list of a
             resource's diagnostic categories
             ({id}/providers/Microsoft.Insights/diagnosticSettingsCategories),
             read once per resource type and kind - the log categories, their
             category groups (allLogs, audit), and the metrics.
          3. The diagnostic settings of every resource that has logs
             ({id}/providers/Microsoft.Insights/diagnosticSettings,
             2021-05-01-preview), -ThrottleLimit at a time.

        Each resource with logs gets a Status (AAC.DiagnosticCoverage):
          Exported           every log category reaches a Log Analytics
                             workspace
          Partial            some categories do, others don't
          Not to workspace   diagnostic settings exist, but none sends logs
                             to a workspace that exists (storage, Event Hubs
                             or a partner only)
          No setting         no diagnostic setting at all
          Unknown            couldn't be read (the reason is in Error)
        A category reaches the workspace when a setting enables it by name
        or through a category group (allLogs, audit) it belongs to. Types
        with no log categories are left out (-IncludeUnsupported lists them
        as No logs).

        Misconfigurations found (AAC.DiagnosticFinding, by severity):
          High     no diagnostic setting; activity log not exported; settings
                   with no workspace destination; a workspace that doesn't
                   exist (deleted, or out of your sight)
          Medium   log categories missing; a setting with nothing enabled; the
                   same category sent to a workspace twice (billed twice); a
                   workspace other than -ExpectedWorkspace
          Low      workspace in another region; the retired retention policy
                   still set on a setting

        -ExpandSetting returns one row per diagnostic setting instead
        (AAC.DiagnosticSettingDetail): destinations, workspace (found or
        not, region), destination table (resource-specific or
        AzureDiagnostics), storage account, event hub, partner, log
        categories and groups enabled and disabled, metrics, retention.

        What you get depends on where the command runs:
          at the prompt    tiles, coverage by resource type, the workspaces
                           used, the findings, and the resources whose logs
                           don't reach a workspace - a page at a time
          piped onward     the rows, with no view
          -PassThru        the view and the rows
          -NoDisplay       the rows only
        -CsvPath writes the rows returned; -HtmlPath an interactive report
        (coverage, findings, every setting, by type, workspaces); -PdfPath a
        PDF.

        A large estate means many calls: one per resource with logs. Narrow
        it with -SubscriptionId, -ManagementGroupId, -ResourceGroupName or
        -ResourceType.
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups.
    .PARAMETER ResourceGroupName
        Only these resource groups (subscriptions' activity logs are then
        left out).
    .PARAMETER ResourceType
        Only these resource types, wildcards allowed: 'microsoft.keyvault/vaults',
        'microsoft.web/*'. 'microsoft.resources/subscriptions' is the
        activity log.
    .PARAMETER ExpectedWorkspace
        The workspace (or workspaces) logs should go to - names or resource
        IDs. A setting sending to any other is a finding.
    .PARAMETER NotExportedOnly
        Only the resources whose logs don't all reach a workspace: No
        setting, Not to workspace and Partial.
    .PARAMETER IncludeUnsupported
        Also list the resources whose type has no log categories (No logs).
    .PARAMETER ExpandSetting
        Return (and write to -CsvPath) one row per diagnostic setting.
    .PARAMETER ThrottleLimit
        How many Azure Resource Manager calls run at once: 1 to 32, 12 by
        default.
    .PARAMETER CsvPath
        Write the rows to this CSV file.
    .PARAMETER PdfPath
        Write a PDF report to this file.
    .PARAMETER HtmlPath
        Write an interactive HTML report to this file.
    .PARAMETER Title
        The PDF and HTML reports' title.
    .PARAMETER PassThru
        Show the view and also return the rows.
    .PARAMETER NoDisplay
        Return the rows without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once instead of a page at a time.
    .EXAMPLE
        Connect-AAC
        Get-AACDiagnosticSetting -SubscriptionId 00000000-0000-0000-0000-000000000000
        Every resource with logs in one subscription, and whether they reach Log Analytics.
    .EXAMPLE
        Get-AACDiagnosticSetting -ManagementGroupId 'mg-landingzones' -ExpectedWorkspace 'law-central' -HtmlPath .\out\Diagnostics.html -PdfPath .\out\Diagnostics.pdf
        A management group against the central workspace, as HTML and PDF reports.
    .EXAMPLE
        Get-AACDiagnosticSetting -NotExportedOnly -NoDisplay | Group-Object ResourceType | Sort-Object Count -Descending
        The resource types with the most resources whose logs don't reach a workspace.
    .EXAMPLE
        Get-AACDiagnosticSetting -ResourceType 'microsoft.keyvault/vaults' -ExpandSetting -CsvPath .\out\KeyVaultSettings.csv
        Every Key Vault diagnostic setting, one row each, as CSV.
    .OUTPUTS
        AAC.DiagnosticCoverage, or AAC.DiagnosticSettingDetail with -ExpandSetting (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.DiagnosticCoverage', 'AAC.DiagnosticSettingDetail')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [ValidateNotNullOrEmpty()]
        [string[]] $ManagementGroupId,

        [ValidateNotNullOrEmpty()]
        [string[]] $ResourceGroupName,

        [SupportsWildcards()]
        [ValidateNotNullOrEmpty()]
        [string[]] $ResourceType,

        [ValidateNotNullOrEmpty()]
        [string[]] $ExpectedWorkspace,

        [switch] $NotExportedOnly,

        [switch] $IncludeUnsupported,

        [switch] $ExpandSetting,

        [ValidateRange(1, 32)]
        [int] $ThrottleLimit = 12,

        [string] $CsvPath,

        [string] $PdfPath,

        [string] $HtmlPath,

        [string] $Title = 'Diagnostic settings',

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
    # Everything the work below needs, read here: it runs inside
    # Invoke-AACProgress and other helpers, whose variables could hide ours.
    $request = @{
        SubscriptionId     = @($SubscriptionId | Where-Object { $_ })
        ManagementGroupId  = @($ManagementGroupId | Where-Object { $_ })
        ResourceGroupName  = @($ResourceGroupName | Where-Object { $_ })
        ResourceType       = @($ResourceType | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() })
        ExpectedWorkspace  = @($ExpectedWorkspace | Where-Object { $_ })
        NotExportedOnly    = [bool]$NotExportedOnly
        IncludeUnsupported = [bool]$IncludeUnsupported
        ExpandSetting      = [bool]$ExpandSetting
        ThrottleLimit      = $ThrottleLimit
        Title              = $Title
        CsvPath            = & $resolve $CsvPath
        PdfPath            = & $resolve $PdfPath
        HtmlPath           = & $resolve $HtmlPath
    }
    $apiVersion = '2021-05-01-preview'

    if ($interactive) {
        Write-AACRule -Title 'Azure Admin Console :: Diagnostic settings' -Color 'deepskyblue3_1'
    }
    $state = Invoke-AACProgress -ScriptBlock {
        $null = Get-AACAccessToken
        $quote = { param([string] $Text) "'" + ($Text -replace '\\', '\\' -replace "'", "\'") + "'" }
        $groupFilter = if ($request.ResourceGroupName.Count) { " | where resourceGroup in~ ($(@($request.ResourceGroupName | ForEach-Object { & $quote $_ }) -join ', '))" } else { '' }

        # --- 1. Every resource (KQL), the subscriptions, the workspaces -----------------------------------------
        Update-AACProgress -Id 'list' -Total 3 -Description 'Listing the resources with Azure Resource Graph'
        $batch = Invoke-AACGraphBatch -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId -Query ([ordered]@{
                # 'kind' is a KQL keyword: as an output column it must be renamed (or bracketed).
                resources     = "resources$groupFilter | project id, name, type = tolower(type), resourceKind = tolower(kind), location, resourceGroup, subscriptionId"
                subscriptions = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions' | project subscriptionId, name"
                workspaces    = @{ Tenant = $true; Query = "resources | where type =~ 'microsoft.operationalinsights/workspaces' | project id = tolower(id), name, location" }
            }) -OnProgress { param($Name, $Done, $Total) Update-AACProgress -Id 'list' -Increment 1 }
        $subscriptionNames = @{}
        foreach ($row in @($batch.Rows['subscriptions'] | Where-Object { $null -ne $_ })) { $subscriptionNames[([string]$row['subscriptionId']).ToLowerInvariant()] = [string]$row['name'] }
        $workspaces = @{}
        foreach ($row in @($batch.Rows['workspaces'] | Where-Object { $null -ne $_ })) { $workspaces[[string]$row['id']] = @{ Name = [string]$row['name']; Location = [string]$row['location'] } }

        $typeWanted = { param([string] $Type) -not $request.ResourceType.Count -or @($request.ResourceType | Where-Object { $Type -like $_ }).Count -gt 0 }
        $targets = [System.Collections.Generic.List[object]]::new()
        $addTarget = {
            param([string] $Id, [string] $Resource, [string] $Type, [string] $Kind, [string] $Group, [string] $Subscription, [string] $Location)
            $targets.Add([pscustomobject]@{ Id = $Id; Resource = $Resource; Type = $Type; Kind = $Kind; ResourceGroup = $Group; SubscriptionId = $Subscription; Location = $Location; Key = "$Type|$Kind" })
        }
        $storageServices = @{ blobServices = 'blob'; fileServices = 'file'; queueServices = 'queue'; tableServices = 'table' }
        foreach ($row in @($batch.Rows['resources'] | Where-Object { $null -ne $_ })) {
            $type = [string]$row['type']
            $id = [string]$row['id']
            if (& $typeWanted $type) { & $addTarget $id ([string]$row['name']) $type ([string]$row['resourceKind']) ([string]$row['resourceGroup']) ([string]$row['subscriptionId']) ([string]$row['location']) }
            # A storage account's logs are on its services.
            if ($type -eq 'microsoft.storage/storageaccounts') {
                foreach ($service in $storageServices.Keys | Sort-Object) {
                    $serviceType = "microsoft.storage/storageaccounts/$($service.ToLowerInvariant())"
                    if (& $typeWanted $serviceType) { & $addTarget "$id/$service/default" "$([string]$row['name']) ($($storageServices[$service]))" $serviceType ([string]$row['resourceKind']) ([string]$row['resourceGroup']) ([string]$row['subscriptionId']) ([string]$row['location']) }
                }
            }
        }
        # Each subscription's activity log - unless the scope is resource groups.
        if (-not $request.ResourceGroupName.Count -and (& $typeWanted 'microsoft.resources/subscriptions')) {
            $inScope = @($subscriptionNames.Keys | Where-Object { -not $request.SubscriptionId.Count -or $request.SubscriptionId -contains $_ })
            if ($request.ManagementGroupId.Count) { $inScope = @($batch.Rows['resources'] | Where-Object { $null -ne $_ } | ForEach-Object { ([string]$_['subscriptionId']).ToLowerInvariant() } | Select-Object -Unique) }
            foreach ($sub in $inScope | Sort-Object) { & $addTarget "/subscriptions/$sub" "$($subscriptionNames[$sub]) (activity log)" 'microsoft.resources/subscriptions' '' '' $sub 'global' }
        }
        Update-AACProgress -Id 'list' -Complete -Description ('{0:N0} resource(s), {1:N0} subscription(s), {2:N0} workspace(s) visible' -f @($batch.Rows['resources']).Count, $subscriptionNames.Count, $workspaces.Count)

        # --- 2. Which types have logs: diagnosticSettingsCategories, once per type and kind ---------------------
        $samples = @{}
        foreach ($t in $targets) { if (-not $samples.Contains($t.Key)) { $samples[$t.Key] = [System.Collections.Generic.List[string]]::new() }; if ($samples[$t.Key].Count -lt 3) { $samples[$t.Key].Add($t.Id) } }
        $categories = @{}
        Update-AACProgress -Id 'types' -Total ([Math]::Max($samples.Count, 1)) -Description "Reading the diagnostic categories of $($samples.Count) resource type(s)"
        for ($attempt = 0; $attempt -lt 3; $attempt++) {
            $pending = @($samples.Keys | Where-Object { -not $categories.Contains($_) -or ($categories[$_].State -eq 'Unknown' -and $samples[$_].Count -gt $attempt) })
            $calls = @{}
            foreach ($key in $pending) { if ($samples[$key].Count -gt $attempt) { $calls["$($samples[$key][$attempt])/providers/Microsoft.Insights/diagnosticSettingsCategories?api-version=$apiVersion"] = $key } }
            if (-not $calls.Count) { break }
            $read = Invoke-AACArmParallel -Uri @($calls.Keys) -ThrottleLimit $request.ThrottleLimit
            foreach ($uri in $calls.Keys) {
                $key = $calls[$uri]
                $result = $read[$uri]
                if ($result.Status -eq 200) {
                    $items = @($(if ($null -ne $result.Items) { $result.Items } else { $result.Body['value'] }) | Where-Object { $_ -is [System.Collections.IDictionary] })
                    $logs = @($items | Where-Object { [string]$_['properties']['categoryType'] -eq 'Logs' } | ForEach-Object { @{ Name = [string]$_['name']; Groups = @($_['properties']['categoryGroups'] | Where-Object { $_ }) } })
                    $metrics = @($items | Where-Object { [string]$_['properties']['categoryType'] -eq 'Metrics' } | ForEach-Object { [string]$_['name'] })
                    $categories[$key] = @{ State = $(if ($logs.Count) { 'Logs' } else { 'NoLogs' }); Logs = $logs; Metrics = $metrics; Error = '' }
                    Update-AACProgress -Id 'types' -Increment 1
                }
                elseif ($result.Status -in 400, 405 -or ($result.Status -eq 404 -and $attempt -eq $samples[$key].Count - 1)) {
                    # The type doesn't support diagnostic settings.
                    $categories[$key] = @{ State = 'NoLogs'; Logs = @(); Metrics = @(); Error = [string]$result.Error }
                    Update-AACProgress -Id 'types' -Increment 1
                }
                else {
                    $categories[$key] = @{ State = 'Unknown'; Logs = @(); Metrics = @(); Error = [string]$result.Error }
                    if ($attempt -eq $samples[$key].Count - 1) { Update-AACProgress -Id 'types' -Increment 1 }
                }
            }
        }
        $typesWithLogs = @($categories.Keys | Where-Object { $categories[$_].State -eq 'Logs' }).Count
        Update-AACProgress -Id 'types' -Complete -Description "$typesWithLogs of $($samples.Count) resource type(s) have resource logs"

        # --- 3. The diagnostic settings of every resource with logs --------------------------------------------
        $withLogs = @($targets | Where-Object { $categories[$_.Key] -and $categories[$_.Key].State -eq 'Logs' })
        $settingUris = @{}
        foreach ($t in $withLogs) { $settingUris[$t.Id] = "$($t.Id)/providers/Microsoft.Insights/diagnosticSettings?api-version=$apiVersion" }
        $settings = @{}
        if ($withLogs.Count) {
            Update-AACProgress -Id 'settings' -Total $withLogs.Count -Description ('Reading the diagnostic settings of {0:N0} resource(s)' -f $withLogs.Count)
            $read = Invoke-AACArmParallel -Uri @($settingUris.Values) -ThrottleLimit $request.ThrottleLimit -OnProgress {
                param($Done, $Total)
                Update-AACProgress -Id 'settings' -Increment 1 -Description ('Reading the diagnostic settings ({0:N0} of {1:N0})' -f $Done, $Total)
            }
            foreach ($id in $settingUris.Keys) { $settings[$id] = $read[$settingUris[$id]] }
        }
        $result = ConvertTo-AACDiagnosticCoverage -Target $targets.ToArray() -Category $categories -Setting $settings -Workspace $workspaces -ExpectedWorkspace $request.ExpectedWorkspace -SubscriptionName $subscriptionNames
        $stats = $result.Stats
        Update-AACProgress -Id 'settings' -Complete -Description ('{0:N0} resource(s) with logs: {1:N0} exported to Log Analytics, {2:N0} partly, {3:N0} not' -f $stats.WithLogs, $stats.Exported, $stats.Partial, ($stats.NotToWorkspace + $stats.NoSetting))

        # --- What to return -----------------------------------------------------------------------------------------
        $shown = @($result.Coverage | Where-Object {
                ($request.IncludeUnsupported -or $_.Status -ne 'No logs') -and
                (-not $request.NotExportedOnly -or $_.Status -in 'No setting', 'Not to workspace', 'Partial')
            })
        $result['Shown'] = $shown
        $rows = if ($request.ExpandSetting) { @($shown | ForEach-Object { $_.Detail }) } else { $shown }
        $result['Rows'] = $rows
        $notices = [System.Collections.Generic.List[string]]::new()
        if (-not $targets.Count) { $notices.Add('No resources were found in this scope.') }
        if ($stats.Unknown) { $notices.Add("$($stats.Unknown) resource(s) couldn't be read - see their Error (no access to Microsoft.Insights/diagnosticSettings/read, or throttling).") }
        if (-not $workspaces.Count) { $notices.Add('No Log Analytics workspace is visible to your account: every workspace destination is reported as not found.') }
        $result['Notice'] = $notices.ToArray()
        $scope = [ordered]@{
            Scope = if ($request.SubscriptionId.Count) { "subscription(s) $(@($request.SubscriptionId | ForEach-Object { if ($subscriptionNames.Contains($_.ToLowerInvariant())) { $subscriptionNames[$_.ToLowerInvariant()] } else { $_ } }) -join ', ')" } elseif ($request.ManagementGroupId.Count) { "management group(s) $($request.ManagementGroupId -join ', ')" } else { 'every subscription the account can see' }
        }
        if ($request.ResourceGroupName.Count) { $scope['Resource groups'] = $request.ResourceGroupName -join ', ' }
        if ($request.ResourceType.Count) { $scope['Resource types'] = $request.ResourceType -join ', ' }
        if ($request.ExpectedWorkspace.Count) { $scope['Expected workspace'] = $request.ExpectedWorkspace -join ', ' }
        $result['Scope'] = $scope
        $csvRows = if ($request.ExpandSetting) { $rows } else { @($rows | Select-Object -Property * -ExcludeProperty Detail) }
        $null = Invoke-AACExport -CsvPath $request.CsvPath -CsvObject @($csvRows) -Noun $(if ($request.ExpandSetting) { 'diagnostic setting' } else { 'resource' }) -PdfPath $request.PdfPath -WritePdf {
            Write-AACDiagnosticSettingPdf -Diagnostic $result -Path $request.PdfPath -Title $request.Title -Detail $scope
        } -HtmlPath $request.HtmlPath -WriteHtml {
            Write-AACDiagnosticSettingHtml -Diagnostic $result -Path $request.HtmlPath -Title $request.Title -Detail $scope
        }
        $result
    }

    if ($showView) {
        Invoke-AACPagedOutput -NoPaging:$NoPaging -ScriptBlock {
            Show-AACDiagnosticSettingView -Diagnostic $state
        }
    }
    elseif ($interactive) {
        foreach ($notice in @($state.Notice)) { Write-AACMarkup "[grey58]$([Spectre.Console.Markup]::Escape($notice))[/]" }
    }
    if ($returnObjects) {
        $state.Rows
    }
}
