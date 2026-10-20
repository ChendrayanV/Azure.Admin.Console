function Export-AACTerraform {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Exports existing Azure resources as Terraform - a folder ready for
        terraform init and plan, with the import blocks - through the Azure
        Export for Terraform API, and shows what couldn't be exported.
    .DESCRIPTION
        Asks Azure to write the Terraform configuration of what you choose -
        a resource group, resources by ID (or piped from any command that
        returns resources), or a Resource Graph query - and waits for it.

        The export is a long-running operation that Azure does on its side,
        and its time grows with the number of resources. So the command:
          - counts the resources first (Resource Graph), and says when an
            export is large and how to make it faster
          - with -BatchSize, splits it into exports of that many resources
            that run at the same time (-ThrottleLimit at once), and merges
            them into one folder
          - shows each export as it runs: its status, how long it has run,
            and how many batches are done - not a percentage Azure doesn't
            give
          - saves the operations in export.json as soon as Azure accepts
            them: after Ctrl+C or -TimeoutMinutes, -Resume collects the
            result without exporting again

        The folder (-Path) gets:
          terraform.tf   the providers the configuration needs
          providers.tf   the provider blocks, with the subscription ID
          main.tf        the resources
          azapi.tf       with -FallbackToAzApi: what azurerm couldn't
                         export, as azapi resources
          import.tf      import blocks, so terraform plan brings the
                         existing resources under Terraform - no
                         terraform import commands to run
          export.json    what was asked, the operations, what was skipped
                         and why
        Several subscriptions get a folder each, under -Path, exported at
        the same time.

        Several resource groups of one subscription are exported together,
        in one query (with their child resources), so they share one
        folder and their names can't clash. With -BatchSize, each batch
        gets names of its own (res-b1-0, res-b2-0...); a resource two
        batches both return is kept once. Resources in different batches
        refer to each other by Azure ID rather than by Terraform address.

        What couldn't be exported is listed, never silently dropped: a
        resource type the azurerm provider doesn't support yet is Skipped -
        -FallbackToAzApi exports those again with the azapi provider, which
        covers every Azure resource type. Sensitive values are masked
        unless -IncludeSensitive.

        -Plan proves the export: it runs terraform init, validate and plan
        in each folder and reads the plan (as Get-AACTerraformPlan does).
        A faithful export plans only imports; anything else - an attribute
        Terraform would change - is what the export didn't capture. It
        needs the terraform CLI, signed in its own way (az login, or
        ARM_CLIENT_ID, ARM_CLIENT_SECRET and ARM_TENANT_ID): Terraform
        doesn't use the Connect-AAC sign-in.

        The export reads Azure; it changes nothing there. It needs Reader
        on what is exported, and the Microsoft.AzureTerraform resource
        provider registered on the subscription - -RegisterProvider
        registers it (that is a change, so it asks first and honours
        -WhatIf; registering needs a role such as Contributor).

        The API is in preview (api-version 2026-09-01-preview); -ApiVersion
        picks another.
    .PARAMETER ResourceGroupName
        The resource groups to export. Found by name in the subscriptions
        you can see (or -SubscriptionId).
    .PARAMETER ResourceId
        The resources to export, by Azure resource ID - or piped: any object
        with an Id or ResourceId (Export-AACResource, Get-AACUnusedResource,
        Get-AACResourceHealth...), or the IDs as text.
    .PARAMETER Query
        A Resource Graph where-clause choosing the resources, such as
        'type =~ "microsoft.network/virtualnetworks" and location =~ "uksouth"'.
    .PARAMETER Table
        With -Query: the Resource Graph table (Resources if not given).
    .PARAMETER Resume
        Collect an export that was still running - after Ctrl+C or
        -TimeoutMinutes - from the operations saved in -Path\export.json (or
        in its subscription folders), without exporting again. -Plan and the
        report parameters still apply; the rest is read from export.json.
    .PARAMETER SubscriptionId
        With -ResourceGroupName: where to look for them. With -Query: the
        subscriptions to export from (every one you can see if not given).
    .PARAMETER Path
        The folder to write. Created if it doesn't exist; Terraform files
        already in it are not overwritten without -Force.
    .PARAMETER Provider
        azurerm (the default) or azapi.
    .PARAMETER Include
        Also export: ResourceGroup (the resource group itself, with
        -ResourceId or -Query), RoleAssignment, Lock, DiagnosticSetting (the
        extension resources on what is exported), ManagedResource (resources
        Azure manages for you, normally left out). Each makes the export
        larger, and slower.
    .PARAMETER Recurse
        With -ResourceId or -Query: the child resources too (subnets of a
        virtual network, databases of a server...).
    .PARAMETER Exclude
        Azure resource IDs to leave out - case-insensitive regular
        expressions, such as '/subscriptions/.+/resourceGroups/rg-app/providers/Microsoft.Insights/.*'.
    .PARAMETER ExcludeType
        Terraform resource types to leave out, such as azurerm_network_watcher.
    .PARAMETER NamePrefix
        The prefix of the Terraform resource names (res- if not given:
        res-0, res-1...).
    .PARAMETER Compact
        Leave out properties with empty values.
    .PARAMETER IncludeSensitive
        Don't mask sensitive values. They are then in the .tf files in clear
        text: keep the folder out of source control.
    .PARAMETER FallbackToAzApi
        Export what the azurerm provider couldn't again, with the azapi
        provider, into azapi.tf - so nothing is left out.
    .PARAMETER BatchSize
        Split an export of more resources than this into exports of this
        many, run at the same time and merged into one folder - the way to
        make a large export faster. 0 (the default): one export.
    .PARAMETER ThrottleLimit
        How many exports run at the same time (8 if not given) - batches,
        subscriptions and the azapi pass alike.
    .PARAMETER Plan
        Run terraform init, validate and plan in each folder, and show what
        Terraform would change beyond the imports.
    .PARAMETER TerraformPath
        The terraform executable, if it isn't on PATH.
    .PARAMETER RegisterProvider
        Register the Microsoft.AzureTerraform resource provider on the
        subscriptions where it isn't.
    .PARAMETER Force
        Overwrite Terraform files already in the folder.
    .PARAMETER TimeoutMinutes
        How long to wait for each export (30 if not given). One still
        running then is left running: -Resume collects it.
    .PARAMETER ApiVersion
        The Azure Export for Terraform API version.
    .PARAMETER CsvPath
        Write the resources - exported, skipped and errors - to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report.
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return an object per folder.
    .PARAMETER NoDisplay
        Return an object per folder without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Export-AACTerraform -ResourceGroupName rg-app -Path .\terraform\rg-app
        The resource group as Terraform, with import blocks.
    .EXAMPLE
        Export-AACTerraform -ResourceGroupName rg-platform -BatchSize 50 -Path .\terraform\platform
        A large resource group, split into exports of 50 resources that run at the same time.
    .EXAMPLE
        Export-AACTerraform -Resume -Path .\terraform\platform
        Collects the export that was still running when the command was stopped.
    .EXAMPLE
        Export-AACTerraform -ResourceGroupName rg-hub, rg-spoke -FallbackToAzApi -Plan -Path .\terraform\network
        Two resource groups in one folder, azapi for what azurerm can't do, and terraform plan to prove it.
    .EXAMPLE
        Export-AACTerraform -Query 'type =~ "microsoft.keyvault/vaults"' -SubscriptionId $sub -Include RoleAssignment, Lock -Path .\terraform\vaults
        Every key vault of a subscription, with its role assignments and locks.
    .EXAMPLE
        Get-AACUnusedResource -NoDisplay | Export-AACTerraform -Path .\terraform\unused
        The unused resources as Terraform, piped by ID - a record of them before they are cleaned up.
    .EXAMPLE
        Export-AACTerraform -ResourceGroupName rg-app -Path .\tf -RegisterProvider -WhatIf
        Shows where the resource provider would be registered, without registering it.
    .OUTPUTS
        AAC.TerraformExport
    #>
    [CmdletBinding(DefaultParameterSetName = 'ResourceGroup', SupportsShouldProcess)]
    [OutputType('AAC.TerraformExport')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ResourceGroup')]
        [ValidateNotNullOrEmpty()]
        [string[]] $ResourceGroupName,

        [Parameter(Mandatory, ParameterSetName = 'ResourceId', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Id')]
        [string[]] $ResourceId,

        [Parameter(Mandatory, ParameterSetName = 'Query')]
        [ValidateNotNullOrEmpty()]
        [string] $Query,

        [Parameter(ParameterSetName = 'Query')]
        [string] $Table,

        [Parameter(Mandatory, ParameterSetName = 'Resume')]
        [switch] $Resume,

        [Parameter(ParameterSetName = 'ResourceGroup')]
        [Parameter(ParameterSetName = 'Query')]
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [Parameter(Mandatory)]
        [string] $Path,

        [ValidateSet('azurerm', 'azapi')]
        [string] $Provider = 'azurerm',

        [ValidateSet('ResourceGroup', 'RoleAssignment', 'Lock', 'DiagnosticSetting', 'ManagedResource')]
        [string[]] $Include,

        [switch] $Recurse,

        [string[]] $Exclude,

        [string[]] $ExcludeType,

        [ValidatePattern('^[A-Za-z_][A-Za-z0-9_-]*$')]
        [string] $NamePrefix = 'res-',

        [switch] $Compact,

        [switch] $IncludeSensitive,

        [switch] $FallbackToAzApi,

        [ValidateRange(0, 1000)]
        [int] $BatchSize = 0,

        [ValidateRange(1, 20)]
        [int] $ThrottleLimit = 8,

        [switch] $Plan,

        [string] $TerraformPath,

        [switch] $RegisterProvider,

        [switch] $Force,

        [ValidateRange(1, 240)]
        [int] $TimeoutMinutes = 30,

        [ValidateNotNullOrEmpty()]
        [string] $ApiVersion = '2026-09-01-preview',

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Terraform export',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    begin {
        $pipedIds = [System.Collections.Generic.List[string]]::new()
    }

    process {
        foreach ($id in @($ResourceId | Where-Object { $_ })) { $pipedIds.Add([string]$id) }
    }

    end {
        trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

        $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
        $interactive = -not $NoDisplay -and -not $pipedOnward
        $resolve = { param([string] $Target) if ($Target) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Target) } }
        $root = & $resolve $Path
        $mode = $PSCmdlet.ParameterSetName
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        $exportUri = { param([string] $Subscription, [string] $Version) "/subscriptions/$Subscription/providers/Microsoft.AzureTerraform/exportTerraform?api-version=$Version" }
        # An export this large takes minutes on Azure's side: say so, and how to make it faster.
        $largeExport = 100

        # -Plan needs the terraform CLI: found now, before anything is exported.
        $terraform = ''
        if ($Plan) {
            $terraform = if ($TerraformPath) { & $resolve $TerraformPath } else { [string](Get-Command -Name 'terraform' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 | ForEach-Object { $_.Source }) }
            if (-not $terraform -or -not (Test-Path -LiteralPath $terraform -PathType Leaf)) {
                throw 'Azure Admin Console found no terraform CLI for -Plan. Install it (https://developer.hashicorp.com/terraform/install) and put it on PATH, or give its path with -TerraformPath.'
            }
        }

        # The options - from the parameters, or (-Resume) from the export being collected.
        $options = [ordered]@{ provider = $Provider; fallbackToAzApi = [bool]$FallbackToAzApi; compact = [bool]$Compact; includeSensitive = [bool]$IncludeSensitive; namePrefix = $NamePrefix; batchSize = $BatchSize; apiVersion = $ApiVersion }

        # What every request shares.
        $common = [ordered]@{ targetProvider = $Provider; fullProperties = -not $Compact; maskSensitive = -not $IncludeSensitive; namePattern = $NamePrefix }
        if ($Exclude) { $common.excludeAzureResource = @($Exclude) }
        if ($ExcludeType) { $common.excludeTerraformResource = @($ExcludeType) }
        $extensionNames = @{ RoleAssignment = 'role-assignments'; Lock = 'locks'; DiagnosticSetting = 'diagnostic-settings' }
        $extensions = @($Include | Where-Object { $_ -and $extensionNames.ContainsKey($_) } | ForEach-Object { $extensionNames[$_] })
        if ($extensions.Count) { $common.includeExtensions = $extensions }
        if ($Include -contains 'ManagedResource') { $common.includeManagedResource = $true }
        $withCommon = { param([System.Collections.IDictionary] $Body) $copy = [ordered]@{}; foreach ($key in $Body.Keys) { $copy[$key] = $Body[$key] }; foreach ($key in $common.Keys) { if (-not $copy.Contains($key)) { $copy[$key] = $common[$key] } }; $copy }
        $quote = { param([string] $Value) "'$($Value -replace "'", "\'")'" }
        $clock = { param([timespan] $Span) if ($Span.TotalHours -ge 1) { '{0}:{1:mm\:ss}' -f [int][Math]::Floor($Span.TotalHours), $Span } else { '{0:m\:ss}' -f $Span } }

        # export.json: written when the export starts, updated as Azure accepts each operation, final when done.
        $saveManifest = {
            param([hashtable] $Job, [string] $Status)
            $record = [ordered]@{
                status = $Status; exportedBy = "Azure.Admin.Console $((Get-Module -Name 'Azure.Admin.Console').Version)"; startedAt = $Job.StartedAt.ToString('o')
                subscriptionId = $Job.SubscriptionId; subscription = $Job.Subscription; label = $Job.Label; resources = $Job.Planned; options = $options
                operations = @($Job.Requests | ForEach-Object { [ordered]@{ key = $_.Key; phase = $_.Phase; part = $_.Part; url = $_.OperationUrl; request = $_.Body } })
            }
            if ($Status -ne 'InProgress') { $record.finishedAt = [datetime]::UtcNow.ToString('o'); $record.skippedResources = @($Job.Skipped); $record.errors = @($Job.Errors); $record.duplicates = [int]$Job.Duplicates }
            $null = [System.IO.Directory]::CreateDirectory($Job.Path)
            [System.IO.File]::WriteAllText((Join-Path -Path $Job.Path -ChildPath 'export.json'), (ConvertTo-Json -InputObject $record -Depth 30), $utf8)
        }
        $newJob = {
            param([string] $Subscription, [string] $Label)
            @{ Index = 0; SubscriptionId = $Subscription.ToLowerInvariant(); Subscription = ''; Label = $Label; Path = ''; Body = $null; Failure = ''; Pending = $false; Planned = $null; Ids = @(); Groups = @()
                Requests = [System.Collections.Generic.List[hashtable]]::new(); Skipped = @(); Errors = @(); Duplicates = 0; Advice = @(); StartedAt = [datetime]::UtcNow; Resumed = $false; OperationId = ''; FallbackTried = $false }
        }

        $null = Get-AACAccessToken
        if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Terraform export' -Color 'mediumpurple' }
        $outcome = Invoke-AACProgress -ScriptBlock {
            $jobs = [System.Collections.Generic.List[hashtable]]::new()
            $scopeLabel = ''
            if ($mode -eq 'Resume') {
                # 0. -Resume: the exports saved in export.json, still in progress.
                $manifests = @(@(Join-Path -Path $root -ChildPath 'export.json') + @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | ForEach-Object { Join-Path -Path $_.FullName -ChildPath 'export.json' }) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
                foreach ($file in $manifests) {
                    $saved = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($file)) -AsHashtable -Depth 50
                    if ([string]$saved['status'] -ne 'InProgress') { continue }
                    $job = & $newJob ([string]$saved['subscriptionId']) ([string]$saved['label'])
                    $job.Subscription = [string]$saved['subscription']
                    $job.Path = Split-Path -Path $file -Parent
                    $job.Planned = $saved['resources']
                    $job.Resumed = $true
                    $job.Index = $jobs.Count + 1
                    # ConvertFrom-Json reads an ISO date as a DateTime already.
                    $started = $saved['startedAt']
                    if ($started -is [datetime]) { $job.StartedAt = $started.ToUniversalTime() }
                    elseif ($started) { $job.StartedAt = [datetime]::Parse([string]$started, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime() }
                    if ($saved['options'] -is [System.Collections.IDictionary]) { foreach ($key in @($saved['options'].Keys)) { $options[$key] = $saved['options'][$key] } }
                    foreach ($op in @($saved['operations'])) {
                        $job.Requests.Add(@{ Key = "$($job.Index)/$($op['part'])"; Phase = [string]$op['phase']; Part = [string]$op['part']; OperationUrl = [string]$op['url']; Body = $op['request']; Uri = (& $exportUri $job.SubscriptionId ([string]$options.apiVersion)) })
                    }
                    $jobs.Add($job)
                }
                if (-not $jobs.Count) { throw "Azure Admin Console found no export in progress in $root (an export.json with status InProgress). Start a new export without -Resume." }
                $scopeLabel = "$($jobs.Count) export(s) resumed"
                Update-AACProgress -Id 'scope' -Complete -Description "Resuming $(@($jobs | ForEach-Object { "$($_.Label) in $($_.Subscription)" }) -join '; ')"
            }
            else {
                # 1. What to export: one export per subscription.
                Update-AACProgress -Id 'scope' -Indeterminate -Description 'Working out what to export'
                switch ($mode) {
                    'ResourceGroup' {
                        $scope = Resolve-AACScope -SubscriptionId @($SubscriptionId | Where-Object { $_ })
                        $names = ($ResourceGroupName | ForEach-Object { & $quote $_ }) -join ', '
                        $found = Invoke-AACGraphBatch -Query ([ordered]@{ groups = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions/resourcegroups' and name in~ ($names) | project name, subscriptionId = tolower(subscriptionId)" }) -SubscriptionId $scope.GraphScope
                        $groups = @($found.Rows['groups'] | Where-Object { $_ -and $ResourceGroupName -contains [string]$_['name'] })
                        foreach ($name in $ResourceGroupName) {
                            $hits = @($groups | Where-Object { [string]$_['name'] -ieq $name })
                            if (-not $hits.Count) { throw "Azure Admin Console found no resource group named '$name' in $($scope.Label). Check the name, or give -SubscriptionId." }
                            if (@($hits | ForEach-Object { $_['subscriptionId'] } | Select-Object -Unique).Count -gt 1) { throw "Azure Admin Console found a resource group named '$name' in more than one subscription. Give -SubscriptionId to choose." }
                        }
                        foreach ($bySubscription in @($groups | Group-Object -Property { [string]$_['subscriptionId'] })) {
                            $inSubscription = @($bySubscription.Group | ForEach-Object { [string]$_['name'] } | Select-Object -Unique)
                            $job = & $newJob $bySubscription.Name "resource group $($inSubscription -join ', ')"
                            $job.Groups = $inSubscription
                            $job.Body = if ($inSubscription.Count -eq 1) {
                                [ordered]@{ type = 'ExportResourceGroup'; resourceGroupName = $inSubscription[0] }
                            }
                            else {
                                # One query for them all: one folder, and no two resources named res-0.
                                [ordered]@{ type = 'ExportQuery'; query = "resourceGroup in~ ($(($inSubscription | ForEach-Object { & $quote $_ }) -join ', '))"; recursive = $true; includeResourceGroup = $true }
                            }
                            $jobs.Add($job)
                        }
                    }
                    'ResourceId' {
                        $bySubscription = [ordered]@{}
                        foreach ($id in $pipedIds) {
                            $m = [regex]::Match($id, '^/subscriptions/([0-9a-fA-F-]{36})(/|$)')
                            if (-not $m.Success) { throw "Azure Admin Console can't export '$id': it isn't an Azure resource ID (/subscriptions/<id>/resourceGroups/...)." }
                            $sub = $m.Groups[1].Value.ToLowerInvariant()
                            if (-not $bySubscription.Contains($sub)) { $bySubscription[$sub] = [System.Collections.Generic.List[string]]::new() }
                            if (-not $bySubscription[$sub].Contains($id)) { $bySubscription[$sub].Add($id) }
                        }
                        if (-not $bySubscription.Count) { throw 'Azure Admin Console got no resource IDs to export. Pipe resources in, or give -ResourceId.' }
                        $scope = Resolve-AACScope -SubscriptionId @($bySubscription.Keys)
                        foreach ($sub in $bySubscription.Keys) {
                            $job = & $newJob $sub "$($bySubscription[$sub].Count) resource(s)"
                            $job.Ids = @($bySubscription[$sub])
                            $job.Planned = $job.Ids.Count
                            $job.Body = [ordered]@{ type = 'ExportResource'; resourceIds = $job.Ids }
                            if ($Recurse) { $job.Body.recursive = $true }
                            if ($Include -contains 'ResourceGroup') { $job.Body.includeResourceGroup = $true }
                            $jobs.Add($job)
                        }
                    }
                    'Query' {
                        $scope = Resolve-AACScope -SubscriptionId @($SubscriptionId | Where-Object { $_ })
                        foreach ($sub in $scope.Ids) {
                            $job = & $newJob $sub "query $Query"
                            $job.Body = [ordered]@{ type = 'ExportQuery'; query = $Query }
                            if ($Table) { $job.Body.table = $Table }
                            if ($Recurse) { $job.Body.recursive = $true }
                            if ($Include -contains 'ResourceGroup') { $job.Body.includeResourceGroup = $true }
                            $jobs.Add($job)
                        }
                    }
                }
                $scopeLabel = [string]$scope.Label
                # A folder each when there are several subscriptions, named after them.
                $index = 0
                foreach ($job in $jobs) {
                    $job.Index = ++$index
                    $job.Subscription = [string]$scope.Names[$job.SubscriptionId]
                    if (-not $job.Subscription) { $job.Subscription = $job.SubscriptionId }
                    $job.Path = if ($jobs.Count -eq 1) { $root } else { Join-Path -Path $root -ChildPath (($job.Subscription -replace '[^\w.-]', '-').Trim('-')) }
                    if (-not $Force -and (Test-Path -LiteralPath $job.Path -PathType Container) -and @(Get-ChildItem -LiteralPath $job.Path -Filter '*.tf' -File).Count) {
                        throw "Azure Admin Console won't overwrite the Terraform files in $($job.Path). Choose an empty folder, or add -Force."
                    }
                }
                Update-AACProgress -Id 'scope' -Complete -Description "$($jobs.Count) export(s): $(@($jobs | ForEach-Object { "$($_.Label) in $($_.Subscription)" }) -join '; ')"

                # 2. The resource provider: registered, or registered now (-RegisterProvider), or a clear reason.
                foreach ($job in $jobs) {
                    $state = ''
                    try { $state = [string](Invoke-AACArmRequest -Uri "/subscriptions/$($job.SubscriptionId)/providers/Microsoft.AzureTerraform?api-version=2021-04-01")['registrationState'] }
                    catch { $state = '' }
                    # Unreadable (no right to read providers): let the export itself say.
                    if (-not $state -or $state -eq 'Registered') { continue }
                    if (-not $RegisterProvider) {
                        $job.Failure = "The Microsoft.AzureTerraform resource provider isn't registered on $($job.Subscription) ($state). Run again with -RegisterProvider, or register it in the portal (Subscription > Resource providers)."
                        continue
                    }
                    if (-not $PSCmdlet.ShouldProcess("subscription $($job.Subscription)", 'Register the Microsoft.AzureTerraform resource provider')) {
                        $job.Failure = "Not exported: the Microsoft.AzureTerraform resource provider isn't registered on $($job.Subscription), and -WhatIf left it so."
                        continue
                    }
                    Update-AACProgress -Id "register$($job.Index)" -Indeterminate -Description "Registering Microsoft.AzureTerraform on $($job.Subscription)"
                    $null = Invoke-AACArmWrite -Method Post -Uri "/subscriptions/$($job.SubscriptionId)/providers/Microsoft.AzureTerraform/register?api-version=2021-04-01"
                    $deadline = [datetime]::UtcNow.AddMinutes(5)
                    while ($state -ne 'Registered' -and [datetime]::UtcNow -lt $deadline) {
                        Start-Sleep -Seconds 5
                        $state = [string](Invoke-AACArmRequest -Uri "/subscriptions/$($job.SubscriptionId)/providers/Microsoft.AzureTerraform?api-version=2021-04-01")['registrationState']
                    }
                    if ($state -ne 'Registered') { $job.Failure = "Microsoft.AzureTerraform is still $state on $($job.Subscription) after 5 minutes. Try again in a few minutes." }
                    Update-AACProgress -Id "register$($job.Index)" -Complete -Description "Microsoft.AzureTerraform on $($job.Subscription): $state"
                }

                # 3. How big: the resources counted (Resource Graph), so a large export is seen coming - and can be split.
                $sizing = [ordered]@{}
                foreach ($job in @($jobs | Where-Object { -not $_.Failure -and -not $_.Ids.Count })) {
                    $sizing["j$($job.Index)"] = switch ($mode) {
                        'ResourceGroup' { "resources | where subscriptionId =~ '$($job.SubscriptionId)' and resourceGroup in~ ($(($job.Groups | ForEach-Object { & $quote $_ }) -join ', ')) | project id" }
                        'Query' { "$(if ($Table) { $Table } else { 'resources' }) | where subscriptionId =~ '$($job.SubscriptionId)' | where $Query | project id" }
                    }
                }
                if ($sizing.Count) {
                    Update-AACProgress -Id 'size' -Indeterminate -Description 'Counting the resources to export'
                    $sized = Invoke-AACGraphBatch -Query $sizing -SubscriptionId @($jobs | ForEach-Object { $_.SubscriptionId } | Select-Object -Unique) -AllowFailure @($sizing.Keys)
                    foreach ($job in @($jobs | Where-Object { $sizing.Contains("j$($_.Index)") })) {
                        if ($sized.Errors.Contains("j$($job.Index)")) { continue }
                        $job.Ids = @($sized.Rows["j$($job.Index)"] | Where-Object { $_ } | ForEach-Object { [string]$_['id'] })
                        $job.Planned = $job.Ids.Count
                    }
                    Update-AACProgress -Id 'size' -Complete -Description "To export: $(@($jobs | Where-Object { -not $_.Failure } | ForEach-Object { "$(if ($null -ne $_.Planned) { '{0:N0} resource(s)' -f $_.Planned } else { 'an unknown number of resources' }) in $($_.Subscription)" }) -join '; ')"
                }

                # Advice for a large export: batches, and the types most often left out.
                $noise = [ordered]@{ 'microsoft.network/networkwatchers' = 'azurerm_network_watcher'; 'microsoft.alertsmanagement/smartdetectoralertrules' = 'azurerm_monitor_smart_detector_alert_rule'; 'microsoft.insights/actiongroups' = 'azurerm_monitor_action_group' }
                foreach ($job in @($jobs | Where-Object { -not $_.Failure -and $null -ne $_.Planned -and $_.Planned -ge $largeExport })) {
                    if (-not $BatchSize) { $job.Advice += "$($job.Planned) resources: a large export takes several minutes on Azure's side. -BatchSize 50 splits it into exports that run at the same time." }
                    $types = @($job.Ids | ForEach-Object { [regex]::Match($_, '/providers/([^/]+/[^/]+)/[^/]+$').Groups[1].Value.ToLowerInvariant() } | Where-Object { $noise.Contains($_) } | Select-Object -Unique)
                    $leaveOut = @($types | ForEach-Object { $noise[$_] } | Where-Object { $ExcludeType -notcontains $_ })
                    if ($leaveOut.Count) { $job.Advice += "Not managed with Terraform? -ExcludeType $($leaveOut -join ', ') leaves those out." }
                }
                foreach ($job in $jobs) { foreach ($line in $job.Advice) { Update-AACProgress -Id "advice$($job.Index)$([guid]::NewGuid().ToString('n'))" -Complete -Description "$($job.Subscription): $line" } }

                # The requests: one export, or (-BatchSize) batches of resource IDs.
                foreach ($job in @($jobs | Where-Object { -not $_.Failure })) {
                    $uri = & $exportUri $job.SubscriptionId $ApiVersion
                    if ($BatchSize -and $job.Ids.Count -gt $BatchSize) {
                        $recursive = if ($mode -eq 'ResourceGroup') { $true } else { [bool]$Recurse }
                        $ids = @($job.Ids | Sort-Object -Unique)
                        if ($recursive) {
                            # A child whose parent is in the list comes with its parent: left out, so batches don't export it twice.
                            $listed = [System.Collections.Generic.HashSet[string]]::new([string[]]@($ids | ForEach-Object { $_.ToLowerInvariant() }), [System.StringComparer]::Ordinal)
                            $ids = @($ids | Where-Object { $lower = $_.ToLowerInvariant(); $parent = $false; for ($at = $lower.IndexOf('/', 1); $at -gt 0; $at = $lower.IndexOf('/', $at + 1)) { if ($listed.Contains($lower.Substring(0, $at))) { $parent = $true; break } }; -not $parent })
                        }
                        $part = 0
                        for ($at = 0; $at -lt $ids.Count; $at += $BatchSize) {
                            $part++
                            $body = [ordered]@{ type = 'ExportResource'; resourceIds = @($ids[$at..([Math]::Min($at + $BatchSize, $ids.Count) - 1)]); recursive = $recursive; namePattern = "${NamePrefix}b$part-" }
                            if ($mode -ne 'ResourceGroup' -and $Include -contains 'ResourceGroup') { $body.includeResourceGroup = $true }
                            $job.Requests.Add(@{ Key = "$($job.Index)/b$part"; Phase = 'primary'; Part = "b$part"; Uri = $uri; Body = (& $withCommon $body); OperationUrl = '' })
                        }
                        if ($mode -eq 'ResourceGroup') {
                            # The resource groups themselves, on their own: not recursive, or they would bring everything again.
                            $groupIds = @($job.Groups | ForEach-Object { "/subscriptions/$($job.SubscriptionId)/resourceGroups/$_" })
                            $job.Requests.Add(@{ Key = "$($job.Index)/rg"; Phase = 'primary'; Part = 'rg'; Uri = $uri; Body = (& $withCommon ([ordered]@{ type = 'ExportResource'; resourceIds = $groupIds; recursive = $false; namePattern = "${NamePrefix}rg-" })); OperationUrl = '' })
                        }
                    }
                    else {
                        $job.Requests.Add(@{ Key = "$($job.Index)/1"; Phase = 'primary'; Part = '1'; Uri = $uri; Body = (& $withCommon $job.Body); OperationUrl = '' })
                    }
                    & $saveManifest $job 'InProgress'
                }
            }

            # 4. Run the exports: all at once (-ThrottleLimit), each followed until Azure is done.
            $byKey = @{}
            $tracker = @{}
            foreach ($job in $jobs) { foreach ($request in $job.Requests) { $byKey[$request.Key] = @{ Job = $job; Request = $request } } }
            $describe = {
                param([hashtable] $Track)
                $size = if ($null -ne $Track.Job.Planned) { ' ({0:N0} resources{1})' -f $Track.Job.Planned, $(if ($Track.Total -gt 1) { " in $($Track.Total) exports" } else { '' }) } else { '' }
                $done = if ($Track.Total -gt 1) { " - $($Track.Done) of $($Track.Total) done" } else { '' }
                "$($Track.Verb) $($Track.Job.Label) from $($Track.Job.Subscription)$size - $($Track.Status), $(& $clock ([datetime]::UtcNow - $Track.Started))$done"
            }
            $run = {
                param([object[]] $Requests, [string] $Verb)
                if (-not $Requests.Count) { return [ordered]@{} }
                $tracker.Clear()
                foreach ($group in @($Requests | Group-Object -Property { [string]$byKey[$_.Key].Job.Index })) {
                    $job = $byKey[$group.Group[0].Key].Job
                    $track = @{ Id = "export$([guid]::NewGuid().ToString('n'))"; Job = $job; Total = $group.Count; Done = 0; Status = 'submitting'; Started = $(if ($job.Resumed -and $Verb -eq 'Exporting') { $job.StartedAt } else { [datetime]::UtcNow }); Verb = $Verb }
                    $tracker[[string]$job.Index] = $track
                    if ($track.Total -gt 1) { Update-AACProgress -Id $track.Id -Total $track.Total -Description (& $describe $track) }
                    else { Update-AACProgress -Id $track.Id -Indeterminate -Description (& $describe $track) }
                }
                $answers = Invoke-AACArmOperationBatch -Request $Requests -ThrottleLimit $ThrottleLimit -TimeoutMinutes $TimeoutMinutes -OnSubmitted {
                    param($Key, $Url)
                    $entry = $byKey[$Key]
                    $entry.Request.OperationUrl = $Url
                    & $saveManifest $entry.Job 'InProgress'
                    $track = $tracker[[string]$entry.Job.Index]; $track.Status = 'accepted'
                    Update-AACProgress -Id $track.Id -Description (& $describe $track)
                } -OnPoll {
                    param($Key, $Status, $Percent)
                    $track = $tracker[[string]$byKey[$Key].Job.Index]
                    $track.Status = $(if ($Status) { $Status } else { 'running' }) + $(if ($null -ne $Percent) { " $([int]$Percent)%" } else { '' })
                    Update-AACProgress -Id $track.Id -Description (& $describe $track)
                } -OnDone {
                    param($Key, $Succeeded, $ErrorText)
                    $track = $tracker[[string]$byKey[$Key].Job.Index]
                    $track.Done++
                    if ($track.Total -gt 1) { Update-AACProgress -Id $track.Id -Increment 1 -Description (& $describe $track) }
                }
                foreach ($track in $tracker.Values) {
                    $failed = @($track.Job.Requests | Where-Object { $answers.Contains($_.Key) -and -not $answers[$_.Key].Succeeded }).Count
                    $track.Status = if ($failed) { "$failed failed" } else { 'done' }
                    Update-AACProgress -Id $track.Id -Complete -Description (& $describe $track)
                }
                $answers
            }

            $answers = & $run @($jobs | Where-Object { -not $_.Failure } | ForEach-Object { $_.Requests } | Where-Object { $_.Phase -eq 'primary' -or $_.Phase -eq 'azapi' }) 'Exporting'
            $propertiesOf = { param($Answer) if ($Answer.Result -is [System.Collections.IDictionary] -and $Answer.Result['properties'] -is [System.Collections.IDictionary]) { $Answer.Result['properties'] } else { @{} } }

            # Each export's outcome: the batches that worked, what they skipped, what failed.
            foreach ($job in @($jobs | Where-Object { -not $_.Failure })) {
                $mine = @($job.Requests | Where-Object { $_.Phase -eq 'primary' })
                $results = @($mine | ForEach-Object { $answers[$_.Key] })
                if (@($results | Where-Object { $_.TimedOut }).Count) {
                    $job.Pending = $true
                    $job.Failure = "Still running after $TimeoutMinutes minute(s). Export-AACTerraform -Resume -Path '$root' collects it (export.json keeps the operations)."
                    continue
                }
                $worked = @($mine | Where-Object { $answers[$_.Key].Succeeded })
                if (-not $worked.Count) {
                    $first = [string]$results[0].Error
                    $job.Failure = if ($mine.Count -gt 1) { "All $($mine.Count) exports failed - the first: $first" } else { $first }
                    continue
                }
                $job.Sources = [System.Collections.Generic.List[hashtable]]::new()
                $skipped = [System.Collections.Generic.List[string]]::new()
                $errors = [System.Collections.Generic.List[object]]::new()
                $fileFor = if ($options.provider -eq 'azapi') { 'azapi.tf' } else { 'main.tf' }
                foreach ($request in $mine) {
                    $answer = $answers[$request.Key]
                    if (-not $answer.Succeeded) { $errors.Add(@{ code = 'BatchFailed'; message = "Export $($request.Part) failed: $($answer.Error)"; target = '' }); continue }
                    $properties = & $propertiesOf $answer
                    $job.Sources.Add(@{ Result = $properties; Provider = [string]$options.provider; File = $fileFor })
                    foreach ($id in @($properties['skippedResources'] | Where-Object { $_ })) { if (-not ($skipped | Where-Object { $_ -ieq $id })) { $skipped.Add([string]$id) } }
                    foreach ($e in @($properties['errors'] | Where-Object { $_ })) { $errors.Add($e) }
                    if (-not $job.OperationId) { $job.OperationId = [string]$answer.Result['name'] }
                }
                $job.Skipped = $skipped.ToArray()
                $job.Errors = $errors.ToArray()
                $job.FallbackTried = $false
                # A resumed export whose azapi pass was already submitted: collected with the rest.
                $azapi = @($job.Requests | Where-Object { $_.Phase -eq 'azapi' })
                if ($azapi.Count) { $job.FallbackDone = @($azapi | ForEach-Object { $answers[$_.Key] }) }
            }

            # 5. -FallbackToAzApi: what azurerm skipped, exported again with azapi - all at once, in batches if asked.
            $fallbackRequests = [System.Collections.Generic.List[hashtable]]::new()
            if ($options.fallbackToAzApi -and $options.provider -eq 'azurerm') {
                foreach ($job in @($jobs | Where-Object { -not $_.Failure -and $_.Skipped.Count -and -not $_.ContainsKey('FallbackDone') })) {
                    $size = if ([int]$options.batchSize) { [int]$options.batchSize } else { $job.Skipped.Count }
                    $part = 0
                    for ($at = 0; $at -lt $job.Skipped.Count; $at += $size) {
                        $part++
                        $prefix = if ($job.Skipped.Count -gt $size) { "$($options.namePrefix)azapi-b$part-" } else { "$($options.namePrefix)azapi-" }
                        $body = [ordered]@{ type = 'ExportResource'; resourceIds = @($job.Skipped[$at..([Math]::Min($at + $size, $job.Skipped.Count) - 1)]); targetProvider = 'azapi'; fullProperties = -not $options.compact; maskSensitive = -not $options.includeSensitive; namePattern = $prefix }
                        $request = @{ Key = "$($job.Index)/azapi$part"; Phase = 'azapi'; Part = "azapi$part"; Uri = (& $exportUri $job.SubscriptionId ([string]$options.apiVersion)); Body = $body; OperationUrl = '' }
                        $job.Requests.Add($request)
                        $byKey[$request.Key] = @{ Job = $job; Request = $request }
                        $fallbackRequests.Add($request)
                    }
                    & $saveManifest $job 'InProgress'
                }
            }
            $second = & $run $fallbackRequests.ToArray() 'Exporting with azapi'
            foreach ($job in @($jobs | Where-Object { -not $_.Failure -and $_.ContainsKey('Sources') })) {
                $azapiAnswers = @(if ($job.ContainsKey('FallbackDone')) { $job.FallbackDone } else { $job.Requests | Where-Object { $_.Phase -eq 'azapi' -and $second.Contains($_.Key) } | ForEach-Object { $second[$_.Key] } })
                if (-not $azapiAnswers.Count) { continue }
                $job.FallbackTried = $true
                $still = [System.Collections.Generic.List[string]]::new()
                $errors = [System.Collections.Generic.List[object]]::new(); foreach ($e in $job.Errors) { $errors.Add($e) }
                foreach ($answer in $azapiAnswers) {
                    if (-not $answer.Succeeded) { $errors.Add(@{ code = 'BatchFailed'; message = "The azapi export failed: $($answer.Error)"; target = '' }); continue }
                    $properties = & $propertiesOf $answer
                    $job.Sources.Add(@{ Result = $properties; Provider = 'azapi'; File = 'azapi.tf' })
                    foreach ($id in @($properties['skippedResources'] | Where-Object { $_ })) { $still.Add([string]$id) }
                    foreach ($e in @($properties['errors'] | Where-Object { $_ })) { $errors.Add($e) }
                }
                # What a failed azapi export was asked for stays skipped.
                if (@($azapiAnswers | Where-Object { -not $_.Succeeded }).Count) { foreach ($id in $job.Skipped) { if (-not ($still -contains $id)) { $still.Add($id) } } }
                $job.Skipped = @($still | Select-Object -Unique)
                $job.Errors = $errors.ToArray()
            }

            # 6. The folders: merged, written, export.json made final.
            $folders = [System.Collections.Generic.List[object]]::new()
            foreach ($job in $jobs) {
                $folder = [ordered]@{ Path = $job.Path; Label = $job.Label; SubscriptionId = $job.SubscriptionId; Subscription = $job.Subscription; Provider = [string]$options.provider; Imports = @(); Skipped = @(); FallbackTried = $false; Errors = @()
                    Files = @(); OperationId = ''; Duration = ([datetime]::UtcNow - $job.StartedAt); Plan = $null; Failure = $job.Failure; Pending = $job.Pending; Planned = $job.Planned
                    Batches = @($job.Requests | Where-Object { $_.Phase -eq 'primary' }).Count; Duplicates = 0 }
                if (-not $job.Failure -and $job.ContainsKey('Sources')) {
                    $layout = ConvertTo-AACTerraformFile -Source $job.Sources.ToArray() -SubscriptionId $job.SubscriptionId
                    $null = [System.IO.Directory]::CreateDirectory($job.Path)
                    foreach ($name in $layout.Files.Keys) { [System.IO.File]::WriteAllText((Join-Path -Path $job.Path -ChildPath $name), [string]$layout.Files[$name], $utf8) }
                    $job.Duplicates = $layout.Duplicates
                    & $saveManifest $job 'Succeeded'
                    $folder.Imports = @($layout.Imports)
                    $folder.Skipped = @($job.Skipped)
                    $folder.Errors = @($job.Errors)
                    $folder.FallbackTried = [bool]$job.FallbackTried
                    $folder.Files = @(@($layout.Files.Keys) + 'export.json')
                    $folder.OperationId = [string]$job['OperationId']
                    $folder.Duplicates = $layout.Duplicates
                }
                elseif ($job.Requests.Count -and -not $job.Pending) { & $saveManifest $job 'Failed' }
                $folders.Add($folder)
            }

            # 7. -Plan: terraform init, validate and plan in each folder; the plan read as Get-AACTerraformPlan reads it.
            if ($Plan) {
                foreach ($folder in @($folders | Where-Object { -not $_.Failure -and @($_.Imports).Count })) {
                    $progressId = "plan$([guid]::NewGuid().ToString('n'))"
                    $result = [ordered]@{ Ran = $false; Step = ''; Message = ''; Import = 0; Create = 0; Update = 0; Replace = 0; Delete = 0; Clean = $false; PlanPath = ''; Changes = @() }
                    $environment = @{ TF_IN_AUTOMATION = '1'; ARM_SUBSCRIPTION_ID = $folder.SubscriptionId }
                    $steps = [ordered]@{
                        init     = @('init', '-backend=false', '-input=false', '-no-color')
                        validate = @('validate', '-no-color')
                        plan     = @('plan', '-input=false', '-lock=false', '-no-color', '-out=tfplan')
                        show     = @('show', '-json', '-no-color', 'tfplan')
                    }
                    Update-AACProgress -Id $progressId -Total $steps.Count -Description "terraform plan in $($folder.Path)"
                    $shown = ''
                    foreach ($step in $steps.Keys) {
                        Update-AACProgress -Id $progressId -Description "terraform $step in $($folder.Path)"
                        $cli = Invoke-AACTerraformCli -FilePath $terraform -Argument $steps[$step] -WorkingDirectory $folder.Path -Environment $environment -TimeoutMinutes ([Math]::Min($TimeoutMinutes, 120))
                        Update-AACProgress -Id $progressId -Increment 1
                        if ($cli.ExitCode -ne 0) {
                            $said = @("$($cli.Error)`n$($cli.Output)" -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^[│╷╵]*$' })
                            $result.Step = $step
                            $result.Message = "terraform $step failed: $(@($said | Select-Object -Last 6) -join ' ')"
                            break
                        }
                        if ($step -eq 'show') { $shown = [string]$cli.Output }
                    }
                    if ($shown) {
                        $planPath = Join-Path -Path $folder.Path -ChildPath 'plan.json'
                        [System.IO.File]::WriteAllText($planPath, $shown, $utf8)
                        $read = ConvertTo-AACTerraformPlan -Plan (ConvertFrom-Json -InputObject $shown -AsHashtable -Depth 200) -Path $planPath
                        $changes = @($read.Changes | Where-Object { $_.Mode -ne 'output' -and $_.Action -notin 'Import', 'NoOp', 'Read' })
                        $result.Ran = $true
                        $result.PlanPath = $planPath
                        foreach ($key in 'Import', 'Create', 'Update', 'Replace', 'Delete') { $result[$key] = [int]$read.Stats[$key] }
                        $result.Changes = $changes
                        $result.Clean = -not $changes.Count
                        $folder.Files = @($folder.Files) + 'plan.json'
                    }
                    Update-AACProgress -Id $progressId -Complete -Description $(if ($result.Ran) { "terraform plan in $($folder.Path): $($result.Import) to import, $(@($result.Changes).Count) to change" } else { $result.Message })
                    $folder.Plan = [pscustomobject]$result
                }
            }

            @{ Result = (ConvertTo-AACTerraformExport -Folder @($folders | ForEach-Object { [pscustomobject]$_ })); Label = $scopeLabel; Advice = @($jobs | ForEach-Object { $_.Advice }) }
        }

        $result = $outcome.Result
        $s = $result.Stats
        $rows = @($result.Rows)
        $folderObjects = @($result.Folders)
        $planned = @($folderObjects | Where-Object { $_.Plan -and $_.Plan.Ran })
        $planChanges = @($planned | ForEach-Object { $f = $_; @($f.Plan.Changes) | ForEach-Object { [pscustomobject]@{ Folder = $f.Path; Action = $_.Action; Address = $_.Address; Type = $_.Type; Importing = [bool]$_.Importing } } })
        $planImports = [int](@($planned | ForEach-Object { $_.Plan.Import }) | Measure-Object -Sum).Sum
        $longest = @($folderObjects | ForEach-Object { $_.Duration } | Sort-Object -Descending | Select-Object -First 1)
        $took = if ($longest.Count) { $longest[0] } else { [timespan]::Zero }
        $clockText = if ($took.TotalHours -ge 1) { '{0}:{1:mm\:ss}' -f [int][Math]::Floor($took.TotalHours), $took } else { '{0:m\:ss}' -f $took }
        $notices = [System.Collections.Generic.List[hashtable]]::new()
        foreach ($f in @($folderObjects | Where-Object { $_.Status -eq 'Running' })) { $notices.Add(@{ Status = 'Warning'; Text = "$($f.Scope) in $($f.Subscription): $($f.Message)" }) }
        foreach ($f in @($folderObjects | Where-Object { $_.Status -eq 'Failed' })) { $notices.Add(@{ Status = 'Failed'; Text = "$($f.Scope) in $($f.Subscription): $($f.Message)" }) }
        foreach ($line in @($outcome.Advice | Where-Object { $_ })) { $notices.Add(@{ Status = 'Info'; Text = $line }) }
        foreach ($f in @($folderObjects | Where-Object { $_.Duplicates })) { $notices.Add(@{ Status = 'Info'; Text = "$($f.Path): $($f.Duplicates) resource(s) more than one batch returned, kept once." }) }
        foreach ($f in @($folderObjects | Where-Object { $_.Plan -and -not $_.Plan.Ran })) { $notices.Add(@{ Status = 'Warning'; Text = "$($f.Path): $($f.Plan.Message) (Terraform signs in on its own: az login, or ARM_CLIENT_ID, ARM_CLIENT_SECRET and ARM_TENANT_ID.)" }) }
        if ($s.Skipped -and -not $FallbackToAzApi -and $Provider -eq 'azurerm' -and $mode -ne 'Resume') { $notices.Add(@{ Status = 'Info'; Text = "$($s.Skipped) resource(s) skipped: azurerm has no support for their type yet. -FallbackToAzApi exports them with the azapi provider." }) }
        foreach ($f in @($folderObjects | Where-Object { $_.Status -in 'Exported', 'Partial' })) {
            $next = if ($f.Plan -and $f.Plan.Ran) { "terraform apply brings $($f.Plan.Import) resource(s) under Terraform" } else { 'terraform init, then terraform plan' }
            $notices.Add(@{ Status = 'Info'; Text = "Next, in $($f.Path): $next." })
        }

        $planPart = if ($planned.Count) { "; terraform plan: $planImports to import, $($planChanges.Count) to change" } else { '' }
        $statusTones = @{ Exported = 'good'; Skipped = 'warn'; Error = 'bad'; Failed = 'bad'; Running = 'info' }
        $finished = $s.Folders - $s.Failed - $s.Running
        $report = @{
            Subtitle = 'Terraform export: existing Azure resources as Terraform, with import blocks'
            Facts    = [ordered]@{ Scope = [string]$outcome.Label; Provider = $(if ($FallbackToAzApi -and $Provider -eq 'azurerm') { 'azurerm, then azapi' } else { $Provider }); Folder = $root; 'Took' = $clockText; 'API version' = $ApiVersion }
            Status   = $(if ($s.Folders -and ($s.Failed + $s.Running) -eq $s.Folders) { $(if ($s.Running) { 'Warning' } else { 'Failed' }) } elseif ($s.Skipped -or $s.Errors -or $s.Failed -or $s.Running -or $planChanges.Count) { 'Warning' } else { 'Success' })
            Headline = "$($s.Exported) resource(s) exported to $finished folder(s) in $clockText$(if ($s.AzApi) { " ($($s.AzApi) with azapi)" }); $($s.Skipped) skipped, $($s.Errors) error(s)$(if ($s.Failed) { ", $($s.Failed) export(s) failed" })$(if ($s.Running) { ", $($s.Running) still running" })$planPart"
            Tiles    = @(
                @{ Value = '{0:N0}' -f $s.Exported; Label = 'exported'; Tone = 'good'; Table = 'resources'; Filters = @{ Status = 'Exported' } }
                @{ Value = '{0:N0}' -f $s.Skipped; Label = 'skipped'; Tone = $(if ($s.Skipped) { 'warn' } else { 'good' }); Table = 'resources'; Filters = @{ Status = 'Skipped' } }
                @{ Value = '{0:N0}' -f ($s.Errors + $s.Failed); Label = 'errors'; Tone = $(if ($s.Errors + $s.Failed) { 'bad' } else { 'good' }) }
                $(if ($planned.Count) { @{ Value = '{0:N0}' -f $planChanges.Count; Label = 'to change (plan)'; Tone = $(if ($planChanges.Count) { 'warn' } else { 'good' }) } } else { @{ Value = $clockText; Label = 'to export'; Tone = 'info' } })
            )
            Notices  = @($notices)
            Charts   = @(
                @{ Title = 'By Terraform type'; Items = @($rows | Where-Object { $_.Status -eq 'Exported' } | Group-Object -Property TerraformType | Sort-Object -Property Count -Descending | Select-Object -First 15 | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'resources'; Column = 'TerraformType'; Tone = 'info'; Console = $true }
                @{ Title = 'By status'; Kind = 'donut'; CenterLabel = 'resources'; Items = @(foreach ($status in 'Exported', 'Skipped', 'Error', 'Failed', 'Running') { $n = @($rows | Where-Object { $_.Status -eq $status }).Count; if ($n) { @{ Label = $status; Value = $n; Tone = $statusTones[$status]; Filter = $status } } }); Table = 'resources'; Column = 'Status' }
            )
            Tables   = @(@(
                    @{ Id = 'resources'; Title = 'Resources'; Section = 'Export'; Rows = $rows; Noun = 'resources'; GroupBy = @('Status', 'TerraformType'); ConsoleLimit = 30
                        Empty = 'Nothing was exported.'; EmptyStatus = 'Warning'
                        Columns = @(
                            @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = $statusTones; Facet = $true; Console = $true; Pdf = $true }
                            @{ Key = 'Address'; Label = 'Terraform address'; Type = 'mono'; Console = $true; Pdf = $true }
                            @{ Key = 'ResourceType'; Label = 'Azure type'; Facet = $true; Console = $true }
                            @{ Key = 'Name'; Label = 'Name'; Console = $true; Pdf = $true }
                            @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true; Console = $true }
                            @{ Key = 'Note'; Label = 'Note'; Type = 'wide'; Console = $true; Pdf = $true }
                            @{ Key = 'TerraformType'; Label = 'Terraform type'; Facet = $true }
                            @{ Key = 'Provider'; Label = 'Provider'; Facet = $true }
                            @{ Key = 'File'; Label = 'File'; Facet = $true }
                            @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                            @{ Key = 'Folder'; Label = 'Folder' }
                            @{ Key = 'ResourceId'; Label = 'Resource ID'; Type = 'mono' }
                        ) }
                    $(if ($planned.Count) {
                            @{ Id = 'plan'; Title = 'What terraform plan would change'; Section = 'Plan'; Rows = $planChanges; Noun = 'changes'; GroupBy = @('Action'); ConsoleLimit = 20
                                Empty = 'terraform plan changes nothing beyond the imports: the export is faithful.'; EmptyStatus = 'Success'
                                Columns = @(
                                    @{ Key = 'Action'; Label = 'Action'; Type = 'badge'; Tones = @{ Update = 'warn'; Replace = 'bad'; Delete = 'bad'; Create = 'info' }; Facet = $true; Console = $true; Pdf = $true }
                                    @{ Key = 'Address'; Label = 'Terraform address'; Type = 'mono'; Console = $true; Pdf = $true }
                                    @{ Key = 'Type'; Label = 'Type'; Facet = $true; Console = $true }
                                    @{ Key = 'Importing'; Label = 'Imported'; Console = $true }
                                    @{ Key = 'Folder'; Label = 'Folder' }
                                ) }
                        })
                ) | Where-Object { $null -ne $_ })
            Hint     = '-BatchSize splits a large export into exports that run at the same time; -Resume collects one still running; -FallbackToAzApi exports what azurerm can''t; -Plan runs terraform plan to prove it; -HtmlPath or -CsvPath for a report.'
        }
        Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $rows -Noun 'resource' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
            -ShowView:$interactive -NoPaging:$NoPaging -Object $folderObjects -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
    }
}
