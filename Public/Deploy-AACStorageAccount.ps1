function Deploy-AACStorageAccount {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Creates or updates a storage account - and its containers, file
        shares, queues, tables, blobs and settings - idempotently, with the
        Azure REST APIs: plan, gates (Azure Policy and PSRule), then apply.
        No ARM, Bicep or Terraform template.
    .DESCRIPTION
        Works like a Bicep or Terraform deployment, without a template:
          1. Desired state   your configuration, with the Azure Verified
                             Module's parameter names and its defaults
                             (avm/res/storage/storage-account): StorageV2,
                             Standard_GRS, Hot, TLS 1.2, HTTPS only, no
                             public blob access, infrastructure encryption,
                             network rules denying by default with the
                             AzureServices bypass, blob and container soft
                             delete - enforced on every run, as Bicep would.
          2. Plan            what exists is read (GET) and compared property
                             by property: Create, Update, No change - or
                             Replace, when Azure can't change a property in
                             place (location, kind, hierarchical namespace,
                             infrastructure encryption...). Containers,
                             shares, queues and tables that exist but aren't
                             configured are Drift (left alone) - or deleted
                             with -Prune.
          3. Gates           the name (checkNameAvailability); the policy
                             assignments that apply to storage in the
                             resource group; Azure Policy's verdict on the
                             exact body of every write (checkPolicyRestrictions):
                             Deny blocks, Audit is reported, Modify and Append
                             changes are shown; PSRule for Azure - and the
                             module's naming and tag rules - on the account as
                             it will be (shift left): what breaks your
                             standards.
          4. Decide          blocked stops here, before anything is written:
                             a name taken, an immutable change, a policy
                             Deny, a PSRule rule that fails (or PSRule not
                             running), -FailOn. Each failing PSRule rule comes
                             with its fix - the setting and value, or what to
                             do - and a configuration snippet with all of
                             them; -UseSuggestedFix deploys with those
                             settings (and checks every gate again). A rule
                             that doesn't apply is excluded on purpose with
                             -ExcludeRule. Otherwise you are asked before
                             anything is written (-Force, or -Confirm:$false,
                             for pipelines); -WhatIf stops after the plan.
          5. Apply           in dependency order, PUT to create, PATCH with
                             only what changed to update (long-running
                             operations followed); role assignments named from
                             scope, principal and role, so they are found
                             again; blobs uploaded only when their MD5 differs.
                             Not a transaction: the first failure stops, and
                             running again carries on.
          6. Verify          everything read and compared again: the plan
                             must now be "no changes". What Azure changed by
                             itself (a Modify policy) is reported.
        Running the same configuration again plans no changes and writes
        nothing.

        The configuration: -ConfigurationPath (.psd1, or .json - including an
        AVM parameters file), and/or parameters, which win over the file:
        -Name, -Location, -SkuName, -Kind, -AccessTier, -Tag, -Container,
        -FileShare, -Queue, -Table, -Blob, and -Setting for any other AVM
        parameter. Supported AVM parameters: name, location, kind, skuName,
        accessTier, tags, allowBlobPublicAccess, allowSharedKeyAccess,
        allowCrossTenantReplication, defaultToOAuthAuthentication,
        minimumTlsVersion, supportsHttpsTrafficOnly, publicNetworkAccess,
        networkAcls, requireInfrastructureEncryption, largeFileSharesState,
        enableHierarchicalNamespace, enableNfsV3, enableSftp,
        isLocalUserEnabled, allowedCopyScope, dnsEndpointType, blobServices
        (with containers, their roleAssignments, and diagnosticSettings),
        fileServices (shares), queueServices (queues), tableServices
        (tables), managementPolicyRules, privateEndpoints (with a private DNS
        zone group), diagnosticSettings, roleAssignments, lock - and blobs
        (files to upload: @{ container; path; name; contentType }). Others
        are refused by name rather than ignored.

        Needs Contributor (or Storage Account Contributor) on the resource
        group, which must exist; User Access Administrator (or Owner) for
        role assignments; Storage Blob Data Contributor for blob uploads.
    .PARAMETER SubscriptionId
        The subscription of the resource group.
    .PARAMETER ResourceGroupName
        The resource group the account is in (it must exist).
    .PARAMETER ConfigurationPath
        A .psd1 or .json file with the configuration (AVM parameter names),
        or an AVM / ARM parameters file.
    .PARAMETER Name
        The account's name: 3-24 lower-case letters and digits, unique across Azure.
    .PARAMETER Location
        Its region. The resource group's by default (an existing account's own).
    .PARAMETER SkuName
        Standard_LRS, Standard_GRS (default), Standard_RAGRS, Standard_ZRS,
        Standard_GZRS, Standard_RAGZRS, Premium_LRS, Premium_ZRS.
    .PARAMETER Kind
        StorageV2 (default), BlockBlobStorage, FileStorage, BlobStorage, Storage.
    .PARAMETER AccessTier
        Hot (default), Cool, Cold or Premium.
    .PARAMETER Tag
        The account's tags - all of them: tags not listed are removed.
    .PARAMETER Container
        Containers: names, or hashtables @{ name; publicAccess; metadata;
        roleAssignments }.
    .PARAMETER FileShare
        File shares: names, or hashtables @{ name; shareQuota; accessTier;
        enabledProtocols; metadata }.
    .PARAMETER Queue
        Queues: names, or hashtables @{ name; metadata }.
    .PARAMETER Table
        Tables, by name.
    .PARAMETER Blob
        Files to upload: hashtables @{ container; path (the local file);
        name (in the container; the file's name by default); contentType }.
        Uploaded only when new or changed (MD5); up to 256 MB each.
    .PARAMETER Setting
        Any other supported AVM parameter, as a hashtable:
        @{ networkAcls = @{ ipRules = @('203.0.113.10') }; lock = @{ kind = 'CanNotDelete' } }.
    .PARAMETER Prune
        Delete the containers, file shares, queues and tables the account has
        but the configuration doesn't - with everything in them.
    .PARAMETER FailOn
        Also stop for: Audit (an Azure Policy audit), Drift (items the
        configuration doesn't name). A failing PSRule rule always stops.
    .PARAMETER UseSuggestedFix
        Deploy with the settings that fix the failing PSRule rules (the
        ones a setting can fix): the configuration is changed for this run,
        then planned and checked again - every gate. The view shows the
        changes, to put in the configuration file.
    .PARAMETER SkipPolicy
        Don't check Azure Policy (the writes are still subject to it).
    .PARAMETER SkipPSRule
        Don't run PSRule for Azure - deploy without checking your standards.
    .PARAMETER Baseline
        The PSRule baseline, e.g. Azure.GA_2024_09. All rules by default.
    .PARAMETER ExcludeRule
        PSRule rules to leave out, by name or wildcard - for rules that don't
        apply to this account.
    .PARAMETER PlanPath
        Write the plan - changes, request bodies, gates - to this JSON file.
    .PARAMETER Force
        Apply without asking (for pipelines). Blocked plans still stop.
    .PARAMETER ThrottleLimit
        How many reads run at once: 1 to 32, 12 by default.
    .PARAMETER PassThru
        Show the view and also return the deployment.
    .PARAMETER NoDisplay
        Return the deployment without showing the view.
    .EXAMPLE
        Deploy-AACStorageAccount -SubscriptionId 00000000-0000-0000-0000-000000000000 -ResourceGroupName rg-data -Name stcontosodata -Container logs, exports -WhatIf
        The plan and the gates for a new account with two containers - nothing is written.
    .EXAMPLE
        Deploy-AACStorageAccount -SubscriptionId 00000000-0000-0000-0000-000000000000 -ResourceGroupName rg-data -ConfigurationPath .\stcontosodata.json
        Plan, gates, ask, apply, verify. Run it again: no changes.
    .EXAMPLE
        Deploy-AACStorageAccount -SubscriptionId 00000000-0000-0000-0000-000000000000 -ResourceGroupName rg-data -ConfigurationPath .\stcontosodata.psd1 -Force -PlanPath .\plan.json
        In a pipeline: apply without asking unless a gate blocks, and keep the plan.
    .EXAMPLE
        Deploy-AACStorageAccount -SubscriptionId 00000000-0000-0000-0000-000000000000 -ResourceGroupName rg-data -Name stcontosodata -Container logs -UseSuggestedFix -WhatIf
        Plan with the settings that fix the failing PSRule rules - shown, to copy into the configuration.
    .EXAMPLE
        Deploy-AACStorageAccount -SubscriptionId 00000000-0000-0000-0000-000000000000 -ResourceGroupName rg-data -Name stcontosodata -Container web -Blob @{ container = 'web'; path = '.\index.html'; contentType = 'text/html' } -Setting @{ networkAcls = @{ ipRules = @('203.0.113.10') } }
        A container and a file in it, from this computer's IP.
    .OUTPUTS
        AAC.StorageDeployment (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('AAC.StorageDeployment')]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string] $SubscriptionId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ResourceGroupName,

        [string] $ConfigurationPath,

        [ValidatePattern('^[a-z0-9]{3,24}$')]
        [string] $Name,

        [string] $Location,

        [ValidateSet('Standard_LRS', 'Standard_GRS', 'Standard_RAGRS', 'Standard_ZRS', 'Standard_GZRS', 'Standard_RAGZRS', 'Premium_LRS', 'Premium_ZRS')]
        [string] $SkuName,

        [ValidateSet('StorageV2', 'BlockBlobStorage', 'FileStorage', 'BlobStorage', 'Storage')]
        [string] $Kind,

        [ValidateSet('Hot', 'Cool', 'Cold', 'Premium')]
        [string] $AccessTier,

        [hashtable] $Tag,

        [object[]] $Container,

        [object[]] $FileShare,

        [object[]] $Queue,

        [string[]] $Table,

        [hashtable[]] $Blob,

        [hashtable] $Setting,

        [switch] $Prune,

        [ValidateSet('Audit', 'Drift')]
        [string[]] $FailOn,

        [switch] $UseSuggestedFix,

        [switch] $SkipPolicy,

        [switch] $SkipPSRule,

        [string] $Baseline,

        [string[]] $ExcludeRule = @(),

        [string] $PlanPath,

        [switch] $Force,

        [ValidateRange(1, 32)]
        [int] $ThrottleLimit = 12,

        [switch] $PassThru,

        [switch] $NoDisplay
    )

    # A failure anywhere below ends as a Spectre.Console error panel and this
    # command's own terminating error, not a line inside the module. A stopped
    # pipeline (Select-Object -First, Ctrl+C) is no failure: just return - a
    # rethrow would stop the caller's whole script, not only this command.
    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $returnObjects = $PassThru -or $NoDisplay -or $pipedOnward
    # The parameters as AVM names; they win over the file.
    $override = [ordered]@{}
    if ($Setting) { foreach ($key in $Setting.Keys) { $override[[string]$key] = $Setting[$key] } }
    foreach ($pair in @(@('Name', 'name'), @('Location', 'location'), @('SkuName', 'skuName'), @('Kind', 'kind'), @('AccessTier', 'accessTier'), @('Tag', 'tags'), @('Blob', 'blobs'))) {
        if ($PSBoundParameters.ContainsKey($pair[0])) { $override[$pair[1]] = $PSBoundParameters[$pair[0]] }
    }
    $request = @{
        SubscriptionId = $SubscriptionId.ToLowerInvariant(); ResourceGroupName = $ResourceGroupName
        ConfigurationPath = $(if ($ConfigurationPath) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ConfigurationPath) })
        PlanPath = $(if ($PlanPath) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($PlanPath) })
        Override = $override; Container = $Container; FileShare = $FileShare; Queue = $Queue; Table = $Table
        Prune = [bool]$Prune; FailOn = @($FailOn | Where-Object { $_ }); UseSuggestedFix = [bool]$UseSuggestedFix; SkipPolicy = [bool]$SkipPolicy; SkipPSRule = [bool]$SkipPSRule
        Baseline = $Baseline; ExcludeRule = @($ExcludeRule); ThrottleLimit = $ThrottleLimit
    }

    if ($interactive) {
        Write-AACRule -Title 'Azure Admin Console :: Deploy storage account' -Color 'springgreen3'
    }

    # --- Desired state, plan, gates ------------------------------------------------------------------------------
    $state = Invoke-AACProgress -ScriptBlock {
        # The plan only reads - -WhatIf is for the apply below. Off here: under
        # -WhatIf, ForEach-Object <Name> on a hashtable treats reading the key
        # as an operation and returns nothing, in this and every helper.
        $WhatIfPreference = $false
        $null = Get-AACAccessToken
        Update-AACProgress -Id 'read' -Description 'Reading the configuration and the resource group' -Indeterminate
        $configuration = ConvertTo-AACStorageConfiguration -Path $request.ConfigurationPath -Override $request.Override
        # Containers, shares, queues and tables given as parameters join the file's.
        foreach ($entry in @(@('Container', 'blobServices', 'containers'), @('FileShare', 'fileServices', 'shares'), @('Queue', 'queueServices', 'queues'), @('Table', 'tableServices', 'tables'))) {
            $items = @($request[$entry[0]] | Where-Object { $null -ne $_ })
            if (-not $items.Count) { continue }
            if ($configuration[$entry[1]] -isnot [System.Collections.IDictionary]) {
                $configuration[$entry[1]] = if ($entry[1] -eq 'blobServices') { [ordered]@{ containerDeleteRetentionPolicyEnabled = $true; containerDeleteRetentionPolicyDays = 7; deleteRetentionPolicyEnabled = $true; deleteRetentionPolicyDays = 6 } } else { [ordered]@{} }
            }
            $known = @(@($configuration[$entry[1]][$entry[2]]) | Where-Object { $null -ne $_ })
            $names = @($known | ForEach-Object { if ($_ -is [System.Collections.IDictionary]) { [string]$_['name'] } else { [string]$_ } })
            $configuration[$entry[1]][$entry[2]] = @($known) + @($items | Where-Object { $names -notcontains $(if ($_ -is [System.Collections.IDictionary]) { [string]$_['name'] } else { [string]$_ }) })
        }
        $group = "/subscriptions/$($request.SubscriptionId)/resourceGroups/$($request.ResourceGroupName)"
        $groupInfo = try { Invoke-AACArmRequest -Uri "$group`?api-version=2021-04-01" } catch {
            if ($_.Exception.Data['StatusCode'] -eq 404) {
                $problem = [System.InvalidOperationException]::new("Resource group $($request.ResourceGroupName) doesn't exist in subscription $($request.SubscriptionId).")
                $problem.Data['AACHint'] = 'Create the resource group first: this command deploys into an existing one.'
                throw $problem
            }
            throw
        }
        # The region: as configured; else an existing account's own; else the resource group's.
        $existingLocation = try { [string](Invoke-AACArmRequest -Uri "$group/providers/Microsoft.Storage/storageAccounts/$($configuration['name'])?api-version=2023-05-01")['location'] } catch { if ($_.Exception.Data['StatusCode'] -ne 404) { throw }; '' }
        $region = if ($configuration['location']) { [string]$configuration['location'] } elseif ($existingLocation) { $existingLocation } else { [string]$groupInfo['location'] }
        # The plan and the gates for a configuration - run again with the
        # suggested fixes (-UseSuggestedFix): every gate is checked afresh.
        $evaluate = {
            param([System.Collections.IDictionary] $Wanted)
            $nodes = Get-AACStorageDesiredState -Configuration $Wanted -SubscriptionId $request.SubscriptionId -ResourceGroupName $request.ResourceGroupName -Location $region
            Update-AACProgress -Id 'read' -Complete -Description "$($nodes.Count) resource(s) in the configuration of $($Wanted['name'])"
            Update-AACProgress -Id 'plan' -Description 'Reading what exists and comparing' -Indeterminate
            $changes = Get-AACStoragePlan -Node $nodes -SubscriptionId $request.SubscriptionId -Prune:$request.Prune -ThrottleLimit $request.ThrottleLimit
            $count = { param([string] $Action) @($changes | Where-Object Action -EQ $Action).Count }
            Update-AACProgress -Id 'plan' -Complete -Description "Plan: $(& $count 'Create') to create, $(& $count 'Update') to update, $(& $count 'Delete') to delete, $(& $count 'NoChange') unchanged"

            $tests = Test-AACStoragePlan -Change $changes -SubscriptionId $request.SubscriptionId -ResourceGroupName $request.ResourceGroupName -SkipPolicy:$request.SkipPolicy -SkipPSRule:$request.SkipPSRule -Baseline $request.Baseline -ExcludeRule $request.ExcludeRule -Configuration $Wanted
            $gates = [System.Collections.Generic.List[object]]::new()
            foreach ($item in $tests.Gates) { $gates.Add($item) }
            foreach ($item in $changes | Where-Object Action -EQ 'Drift') { $gates.Add([pscustomobject]@{ PSTypeName = 'AAC.StorageGate'; Gate = 'Drift'; Outcome = $(if ($request.FailOn -contains 'Drift') { 'Blocks' } else { 'Info' }); Resource = $item.Resource; Item = ''; Detail = $item.Reason; Severity = ''; Reference = ''; Fix = $(if ($request.FailOn -contains 'Drift') { 'Add it to the configuration, or delete it with -Prune.' } else { '' }) }) }
            if ($request.FailOn -contains 'Audit') { foreach ($item in $gates | Where-Object Outcome -EQ 'Audit') { $item.Outcome = 'Blocks'; $item.Detail = "$($item.Detail) (-FailOn Audit)" } }

            $account = @($changes | Where-Object Kind -EQ 'account')[0]
            @{
                Name = [string]$Wanted['name']; ResourceId = $account.Id; SubscriptionId = $request.SubscriptionId; ResourceGroupName = $request.ResourceGroupName; Location = $region
                Configuration = $Wanted; Nodes = $nodes; Changes = $changes; Gates = $gates.ToArray(); Policies = $tests.Policies; PSRule = $tests.PSRule; Fixes = @($tests.Fixes); FixesApplied = @()
                # A failing PSRule rule (Breaks) stops the deployment as a
                # block does: fix it, or exclude the rule on purpose.
                Blocked = @($gates | Where-Object Outcome -In 'Blocks', 'Breaks').Count -gt 0; Writes = @($changes | Where-Object Action -In 'Create', 'Update', 'Delete').Count
                Applied = @(); Verification = @(); Status = ''
            }
        }
        $result = & $evaluate $configuration
        $automatic = @($result.Fixes | Where-Object Kind -EQ 'Auto')
        if ($request.UseSuggestedFix -and $automatic.Count) {
            Update-AACProgress -Id 'fix' -Complete -Description "Applying $($automatic.Count) suggested fix(es) to the configuration and checking again: $(@($automatic | ForEach-Object { $_.Setting }) -join ', ')"
            $fixed = Set-AACStorageConfigurationFix -Configuration $configuration -Fix $automatic
            $result = & $evaluate $fixed
            $result.FixesApplied = $automatic
        }
        if ($request.PlanPath) {
            $folder = Split-Path -Path $request.PlanPath -Parent
            if ($folder -and -not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
            $record = [ordered]@{
                account = $result.Name; resourceId = $result.ResourceId; subscriptionId = $result.SubscriptionId; resourceGroupName = $result.ResourceGroupName; location = $region; generated = [datetime]::UtcNow.ToString('o')
                changes = @($result.Changes | ForEach-Object { [ordered]@{ order = $_.Order; action = $_.Action; resource = $_.Resource; method = $_.Method; uri = $_.Uri; reason = $_.Reason; differences = @($_.Differences); body = $_.Body } })
                gates = @($result.Gates); policies = @($result.Policies); fixes = @($result.Fixes); fixesApplied = @($result.FixesApplied)
            }
            [System.IO.File]::WriteAllText($request.PlanPath, (ConvertTo-Json -InputObject $record -Depth 50), [System.Text.UTF8Encoding]::new($false))
        }
        $result
    }

    # --- Decide ------------------------------------------------------------------------------------------------------------
    if ($interactive) { Invoke-AACPagedOutput -NoPaging -ScriptBlock { $WhatIfPreference = $false; Show-AACStoragePlanView -Deployment $state } }
    $target = "storage account $($state.Name) in $($state.ResourceGroupName)"
    if ($state.Blocked) {
        $state.Status = 'Blocked'
        $blockers = @($state.Gates | Where-Object Outcome -In 'Blocks', 'Breaks')
        if (-not $WhatIfPreference) {
            $problem = [System.InvalidOperationException]::new("The plan for $target is blocked - nothing was changed: $(@($blockers | ForEach-Object { "$($_.Gate): $($_.Resource)$(if ($_.Item) { " ($($_.Item))" })" }) -join '; ').")
            $automatic = @($state.Fixes | Where-Object Kind -EQ 'Auto')
            $problem.Data['AACHint'] = @(
                foreach ($blocker in $blockers | Where-Object Fix) { "$($blocker.Item): $($blocker.Fix)" }
                if ($automatic.Count -and -not $state.FixesApplied.Count) { "Add -UseSuggestedFix to deploy with the $($automatic.Count) suggested setting(s) - every gate is checked again - or put them in the configuration." }
                if (@($blockers | Where-Object Gate -EQ 'PSRule').Count) { 'A rule that does not apply to this account can be excluded on purpose with -ExcludeRule <rule>.' }
            ) -join ' '
            throw $problem
        }
    }
    elseif (-not $state.Writes) {
        $state.Status = 'NoChanges'
    }
    elseif ($WhatIfPreference) {
        $null = $PSCmdlet.ShouldProcess($target, "Apply $($state.Writes) change(s)")
        $state.Status = 'Planned'
    }
    elseif ($Force -or $PSCmdlet.ShouldProcess($target, "Apply $($state.Writes) change(s)")) {
        # --- Apply and verify ----------------------------------------------------------------------------------------
        $state = Invoke-AACProgress -ScriptBlock {
            $state.Applied = @(Invoke-AACStoragePlan -Change $state.Changes)
            if (@($state.Applied | Where-Object Status -EQ 'Failed').Count) { $state.Status = 'Failed'; return $state }
            Update-AACProgress -Id 'verify' -Description 'Verifying: reading everything again' -Indeterminate
            $again = Get-AACStoragePlan -Node $state.Nodes -SubscriptionId $state.SubscriptionId -Prune:$request.Prune -ThrottleLimit $request.ThrottleLimit
            $state.Verification = @($again | Where-Object Action -In 'Create', 'Update', 'Delete', 'Replace', 'Unknown')
            $state.Status = 'Applied'
            Update-AACProgress -Id 'verify' -Complete -Description $(if ($state.Verification.Count) { "Verified: $($state.Verification.Count) resource(s) differ from the configuration after apply - see below" } else { 'Verified: everything matches the configuration' })
            $state
        }
        if ($interactive) { Invoke-AACPagedOutput -NoPaging -ScriptBlock { $WhatIfPreference = $false; Show-AACStorageApplyView -Deployment $state } }
        if ($state.Status -eq 'Failed') {
            $failure = @($state.Applied | Where-Object Status -EQ 'Failed')[0]
            $problem = [System.InvalidOperationException]::new("$($failure.Resource) couldn't be $(if ($failure.Action -eq 'Delete') { 'deleted' } elseif ($failure.Action -eq 'Create') { 'created' } else { 'updated' }): $($failure.Detail)")
            $problem.Data['AACHint'] = "$(@($state.Applied | Where-Object Status -EQ 'Applied').Count) change(s) before it were applied and stay; fix the cause and run again - it carries on from there."
            throw $problem
        }
    }
    else {
        $state.Status = 'Declined'
    }

    if ($returnObjects) {
        [pscustomobject]@{
            PSTypeName        = 'AAC.StorageDeployment'
            Name              = $state.Name
            Status            = $state.Status
            Writes            = $state.Writes
            ResourceGroupName = $state.ResourceGroupName
            Location          = $state.Location
            Changes           = $state.Changes
            Gates             = $state.Gates
            Policies          = $state.Policies
            Fixes             = $state.Fixes
            FixesApplied      = $state.FixesApplied
            Applied           = $state.Applied
            Verification      = $state.Verification
            ResourceId        = $state.ResourceId
        }
    }
}
