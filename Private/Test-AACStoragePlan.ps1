function Test-AACStoragePlan {
    <#
    .SYNOPSIS
        The gates of Deploy-AACStorageAccount: what would block the plan,
        break your standards, or be changed by Azure Policy - checked before
        anything is written.
    .DESCRIPTION
        Returns @{ Gates; Policies; PSRule }. Gates are AAC.StorageGate rows:
        Gate, Outcome, Resource, Item, Detail, Reference:

          Name       the account is new and its name is taken (or invalid)
                     - checkNameAvailability                        Blocks
          Immutable  a property Azure can't change in place differs  Blocks
          Unknown    something couldn't be read                      Blocks
          Lock       -Prune would delete under a lock                Blocks
          Policy     checkPolicyRestrictions with the exact body each
                     write would send (a child with its parent as scope):
                       a Deny the resource would fail                Blocks
                       an Audit it would fail                        Audit
                       a field policy will set or remove (Modify,
                       Append)                                       Changes
          PSRule     PSRule for Azure (and the module's naming and tag
                     rules) on the account as it will be - with its
                     services, containers and shares - through the
                     module's PSRule runner: a rule that fails (or
                     can't be evaluated) is Breaks, with its Fix
                     (Get-AACStorageRuleFix); PSRule not running at all
                     Blocks. Both stop the deployment.
          Network    blobs to upload while the account denies public
                     network access by default                       Warn
        Policies: the policy assignments that apply to the resource group
        and target storage (Get-AACAssignedPolicy), for reference.
        Fixes: the fix for each failing PSRule rule (AAC.StorageRuleFix).
        -SkipPolicy and -SkipPSRule leave those gates out.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Change,

        [Parameter(Mandatory)]
        [string] $SubscriptionId,

        [Parameter(Mandatory)]
        [string] $ResourceGroupName,

        [switch] $SkipPolicy,

        [switch] $SkipPSRule,

        [string] $Baseline,

        [string[]] $ExcludeRule = @(),

        # The configuration PSRule's fixes are expressed in.
        [System.Collections.IDictionary] $Configuration = @{}
    )

    $gates = [System.Collections.Generic.List[object]]::new()
    $gate = {
        param([string] $Gate, [string] $Outcome, [string] $Resource, [string] $Item, [string] $Detail, [string] $Reference = '', [string] $Severity = '', [string] $Fix = '')
        $gates.Add([pscustomobject]@{ PSTypeName = 'AAC.StorageGate'; Gate = $Gate; Outcome = $Outcome; Resource = $Resource; Item = $Item; Detail = $Detail; Severity = $Severity; Reference = $Reference; Fix = $Fix })
    }
    $group = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName"
    $account = @($Change | Where-Object Kind -EQ 'account')[0]
    $writes = @($Change | Where-Object Action -In 'Create', 'Update', 'Delete')

    # --- Name, immutables, unreadable, locks -------------------------------------------------------------------------
    if ($account.Action -eq 'Create') {
        $check = Invoke-AACArmRequest -Method Post -Uri "/subscriptions/$SubscriptionId/providers/Microsoft.Storage/checkNameAvailability?api-version=2023-05-01" -Body (ConvertTo-Json -Compress -InputObject @{ name = $account.Name; type = 'Microsoft.Storage/storageAccounts' })
        if (-not $check['nameAvailable']) { & $gate 'Name' 'Blocks' $account.Resource $account.Name "The name can't be used: $(if ($check['message']) { $check['message'] } else { $check['reason'] }). Storage account names are unique across Azure." }
        else { & $gate 'Name' 'Pass' $account.Resource $account.Name 'The name is available.' }
    }
    foreach ($item in $Change | Where-Object Action -EQ 'Replace') {
        foreach ($difference in @($item.Differences | Where-Object Immutable)) {
            & $gate 'Immutable' 'Blocks' $item.Resource $difference.Property "Azure can't change it in place: $($difference.Current) -> $($difference.Desired). Keep the current value, or create a new resource."
        }
    }
    foreach ($item in $Change | Where-Object Action -EQ 'Unknown') { & $gate 'Read' 'Blocks' $item.Resource '' $item.Reason }
    $lock = @($Change | Where-Object { $_.Kind -eq 'lock' -and $_.Exists }) | Select-AACFirst 1
    if ($lock -and @($Change | Where-Object Action -EQ 'Delete').Count) { & $gate 'Lock' 'Blocks' $lock.Resource '' "-Prune would delete $(@($Change | Where-Object Action -EQ 'Delete').Count) item(s), but the account is locked: Azure refuses the deletes. Remove the lock first, or don't prune." }
    $acl = if ($account.Planned) { $account.Planned['properties']['networkAcls'] } else { $null }
    $blobs = @($Change | Where-Object { $_.Kind -eq 'blob' -and $_.Action -in 'Create', 'Update' })
    if ($blobs.Count -and $acl -and [string]$acl['defaultAction'] -eq 'Deny') {
        & $gate 'Network' 'Warn' $account.Resource 'networkAcls.defaultAction' "$($blobs.Count) blob(s) are uploaded from this computer, but the account denies network access by default: add this computer's public IP to networkAcls.ipRules, or the uploads are refused."
    }

    # --- Azure Policy -------------------------------------------------------------------------------------------------
    $policies = @()
    if (-not $SkipPolicy) {
        Update-AACProgress -Id 'policy' -Description 'Reading the policy assignments for storage' -Indeterminate
        $rows = @(Get-AACAssignedPolicy -SubscriptionId $SubscriptionId -NoDisplay)
        $names = @{}
        foreach ($row in $rows) { $names[([string]$row.AssignmentId).ToLowerInvariant()] = [string]$row.AssignmentDisplayName }
        $applies = @($rows | Where-Object {
                $scope = ([string]$_.AssignmentScope).TrimEnd('/')
                ($group -ieq $scope -or $group.StartsWith("$scope/", [StringComparison]::OrdinalIgnoreCase)) -and
                -not @(([string]$_.NotScopes) -split ',\s*' | Where-Object { $_ -and ($group -ieq $_.TrimEnd('/') -or $group.StartsWith("$($_.TrimEnd('/'))/", [StringComparison]::OrdinalIgnoreCase)) }).Count -and
                ([string]$_.ResourceType -match 'Microsoft\.Storage' -or [string]$_.ResourceType -like 'All*')
            })
        $policies = @($applies | Group-Object AssignmentId | ForEach-Object {
                $first = $_.Group[0]
                $effect = @($_.Group | Where-Object { [string]$_.ParameterName -match 'effect' } | ForEach-Object { $_.EffectiveValue } | Select-Object -Unique) -join ', '
                [pscustomobject]@{
                    PSTypeName = 'AAC.StoragePolicy'; Assignment = $first.AssignmentDisplayName; Definition = $first.DefinitionDisplayName; Kind = $first.DefinitionType
                    Effect = $(if ($effect) { $effect } else { '(set in the rule)' }); Enforcement = $first.EnforcementMode; Scope = $first.ScopeName; ResourceType = $first.ResourceType; AssignmentId = $first.AssignmentId
                }
            } | Sort-Object Assignment)
        $checks = @($writes | Where-Object { $_.Action -in 'Create', 'Update' -and $_.Kind -notin 'roleAssignment', 'blob' })
        Update-AACProgress -Id 'policy' -Total ([Math]::Max($checks.Count, 1)) -Description "Checking $($checks.Count) change(s) against Azure Policy"
        foreach ($item in $checks) {
            $content = [ordered]@{ type = $item.Type; name = $item.Name }
            foreach ($key in @($item.Planned.Keys)) { if ($key -notin 'id', 'name', 'type', 'etag', 'systemData') { $content[$key] = $item.Planned[$key] } }
            $details = [ordered]@{ resourceContent = $content; apiVersion = ($item.Uri -replace '^.*api-version=', '') }
            $isChild = $item.Kind -ne 'account' -and $item.Kind -ne 'privateEndpoint'
            if ($isChild) { $details['scope'] = $item.Parent }
            $where = if ($item.Kind -eq 'privateEndpoint') { $item.Parent } else { $group }
            $request = [ordered]@{ resourceDetails = $details; includeAuditEffect = $true }
            try {
                $result = Invoke-AACArmRequest -Method Post -Uri "$where/providers/Microsoft.PolicyInsights/checkPolicyRestrictions?api-version=2024-10-01" -Body (ConvertTo-Json -InputObject $request -Depth 50 -Compress)
            }
            catch {
                & $gate 'Policy' 'Warn' $item.Resource '' "The policy check couldn't run: $($_.Exception.Message)"
                Update-AACProgress -Id 'policy' -Increment 1
                continue
            }
            $assignmentName = { param($Info) $id = ([string]$Info['policyAssignmentId']).ToLowerInvariant(); if ($names.Contains($id)) { $names[$id] } else { ($id -split '/')[-1] } }
            foreach ($evaluation in @($result['contentEvaluationResult']['policyEvaluations'])) {
                if ($evaluation -isnot [System.Collections.IDictionary] -or [string]$evaluation['evaluationResult'] -ne 'NonCompliant') { continue }
                $effect = [string]$evaluation['effectDetails']['policyEffect']
                $why = [string]$evaluation['evaluationDetails']['reason']
                $failed = @($evaluation['evaluationDetails']['evaluatedExpressions'] | Where-Object { $_ -is [System.Collections.IDictionary] -and [string]$_['result'] -eq 'True' -and $_['path'] -ne 'type' } | ForEach-Object { "$($_['path']) $($_['operator']) $(ConvertTo-Json -InputObject $_['targetValue'] -Compress)" })
                $detail = @($(if ($why) { $why }), $(if ($failed) { "($($failed -join '; '))" })) | Where-Object { $_ }
                & $gate 'Policy' $(if ($effect -eq 'Deny') { 'Blocks' } elseif ($effect -match 'Audit') { 'Audit' } else { 'Changes' }) $item.Resource (& $assignmentName $evaluation['policyInfo']) "$effect$(if ($detail) { ": $($detail -join ' ')" })" ([string]$evaluation['policyInfo']['policyDefinitionId'])
            }
            foreach ($field in @($result['fieldRestrictions'])) {
                if ($field -isnot [System.Collections.IDictionary]) { continue }
                foreach ($restriction in @($field['restrictions'] | Where-Object { $_ -is [System.Collections.IDictionary] })) {
                    $kind = [string]$restriction['result']
                    if ($kind -eq 'Required' -and $restriction['defaultValue']) { & $gate 'Policy' 'Changes' $item.Resource (& $assignmentName $restriction['policy']) "Sets $($field['field']) to '$($restriction['defaultValue'])' when it isn't given ($($restriction['policyEffect']))." }
                    elseif ($kind -eq 'Removed') { & $gate 'Policy' 'Changes' $item.Resource (& $assignmentName $restriction['policy']) "Removes $($field['field']) ($($restriction['policyEffect']))." }
                }
            }
            Update-AACProgress -Id 'policy' -Increment 1
        }
        $verdicts = @($gates | Where-Object Gate -EQ 'Policy')
        Update-AACProgress -Id 'policy' -Complete -Description "Azure Policy: $($policies.Count) assignment(s) apply to storage here; $(@($verdicts | Where-Object Outcome -EQ 'Blocks').Count) deny, $(@($verdicts | Where-Object Outcome -EQ 'Audit').Count) audit, $(@($verdicts | Where-Object Outcome -EQ 'Changes').Count) change(s) by policy"
        if (-not $verdicts.Count -and $checks.Count) { & $gate 'Policy' 'Pass' $account.Resource '' "No policy denies, audits or changes the $($checks.Count) change(s)." }
    }

    # --- PSRule on the account as it will be -----------------------------------------------------------------------------
    $psrule = $null
    $fixes = @()
    if (-not $SkipPSRule -and $account.Planned) {
        $children = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $Change | Where-Object { $_.Kind -in 'blobService', 'container', 'fileService', 'share', 'queueService', 'queue', 'tableService', 'table', 'managementPolicy', 'diagnosticSetting', 'lock' -and $_.Planned -and $_.Action -ne 'Delete' }) {
            $children.Add((Merge-AACObject -Base $item.Planned -Overlay ([ordered]@{ id = $item.Id; name = ($item.Name -split '/')[-1]; type = $item.Type })))
        }
        # apiVersion as a deployment has it: PSRule reads defaults by it.
        $object = Merge-AACObject -Base $account.Planned -Overlay ([ordered]@{ id = $account.Id; name = $account.Name; type = 'Microsoft.Storage/storageAccounts'; apiVersion = ($account.Uri -replace '^.*api-version=', ''); resourceGroupName = $ResourceGroupName; subscriptionId = $SubscriptionId; resources = $children.ToArray() })
        try {
            $psrule = Invoke-AACPSRuleEngine -InputObject @($object) -Baseline $Baseline -ExcludeRule $ExcludeRule
            $failing = @($psrule.Results | Where-Object { $_.Outcome -in 'Fail', 'Error' })
            $fixes = @(Get-AACStorageRuleFix -Result $failing -Configuration $Configuration -AccountExists:($account.Action -ne 'Create'))
            foreach ($result in $failing) {
                $ruleFixes = @($fixes | Where-Object { $_.Rule -eq $result.RuleName })
                $fixText = @(foreach ($fix in $ruleFixes) { if ($fix.Kind -eq 'Auto') { "Set $($fix.Setting) = $(ConvertTo-Json -InputObject $fix.Value -Compress). $($fix.Advice)" } else { $fix.Advice } }) -join ' '
                & $gate 'PSRule' 'Breaks' $result.ResourceName $result.RuleName "$($result.Title)$(if ($result.Reason) { " - $($result.Reason)" })" $result.Link $result.Severity $fixText
            }
            $passed = @($psrule.Results | Where-Object Outcome -EQ 'Pass').Count
            if ($passed) { & $gate 'PSRule' 'Pass' $account.Resource '' "$passed rule(s) pass." }
        }
        catch {
            # Not checked is not passed.
            & $gate 'PSRule' 'Blocks' $account.Resource '' "PSRule couldn't run, so the account can't be checked against your standards: $($_.Exception.Message)" '' '' 'Fix PSRule for Azure (Install-PSResource PSRule.Rules.Azure), or deploy without it with -SkipPSRule.'
        }
    }
    @{ Gates = $gates.ToArray(); Policies = $policies; PSRule = $psrule; Fixes = $fixes }
}
