function ConvertTo-AACEffectivePolicy {
    <#
    .SYNOPSIS
        Works out, resource by resource, every Azure Policy that applies -
        and the ones that don't, with the reason - and what each one does to
        it: the effect in force, the compliance state and why, the exemption
        covering it. Shared by Show-AACEffectivePolicy and
        Test-AACPolicyDeployment.
    .DESCRIPTION
        -Resource are @{ Id; Name; Type; Location; Kind; Tags; ResourceGroup;
        SubscriptionId; Planned } - existing resources, or one still to be
        deployed (Planned). -Policy is Read-AACAssignedPolicyData's result,
        -Exemption Resource Graph's exemption rows, -State the resources'
        compliance states and -Reason why the non-compliant ones are
        (Read-AACEffectivePolicyData).

        For each resource, every assignment on its path - its management
        groups (root first), subscription, resource group and itself - and,
        for an initiative, every member policy, one verdict (Applicability):
          Applies        the policy evaluates the resource
          Exempt         an exemption covers it (Waiver or Mitigated, not
                         expired, for all the initiative's policies or this
                         one); an expired one is noted, not applied
          Excluded       the assignment's notScopes leave it out
          Not selected   the assignment's resource selectors (location,
                         type) leave it out
          Not targeted   the rule's type conditions (or, without any, the
                         aliases it reads) name other types; a data-plane
                         policy (Microsoft.Kubernetes.Data, ...) another
                         kind of resource
        Azure's own compliance state wins: a state for a policy the rule
        reading thought didn't target the resource means it does.

        The effect is the member's (parameters resolved through the
        initiative and the assignment, then the assignment's overrides -
        Resolve-AACPolicySetMember), and Impact what it does here: Blocks
        (deny), Blocks delete (denyAction), Audits (audit,
        auditIfNotExists), Changes (modify, append), Deploys
        (deployIfNotExists), Manual, Disabled - or Reports only when the
        assignment isn't enforced (DoNotEnforce): a deny, change or deploy
        then only reports. A planned resource's State is 'Planned'; an
        existing one's is Azure's (Compliant, NonCompliant, Exempt, ...) or
        'Not evaluated'.

        Returns @{ Policies (AAC.EffectivePolicy - those that apply, are
        exempt or are left out by notScopes or selectors; with
        -IncludeNotApplicable the not targeted too); Resources
        (AAC.EffectivePolicyResource, one per resource); Assignments
        (AAC.EffectivePolicyAssignment, the chain: every assignment that
        reaches a resource); Exemptions (AAC.EffectivePolicyExemption);
        Findings (AAC.EffectivePolicyFinding); Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Resource,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Policy,

        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Exemption = @(),

        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $State = @(),

        [System.Collections.IDictionary] $Reason = @{},

        [switch] $IncludeNotApplicable,

        [datetime] $Now = [datetime]::UtcNow
    )

    $definitions = $Policy['Definitions']
    if ($definitions -isnot [System.Collections.IDictionary]) { $definitions = @{} }
    $subscriptionNames = if ($Policy['SubscriptionNames'] -is [System.Collections.IDictionary]) { $Policy['SubscriptionNames'] } else { @{} }
    $groupNames = if ($Policy['GroupNames'] -is [System.Collections.IDictionary]) { $Policy['GroupNames'] } else { @{} }
    $subscriptionChain = if ($Policy['SubscriptionChain'] -is [System.Collections.IDictionary]) { $Policy['SubscriptionChain'] } else { @{} }
    $groupChain = if ($Policy['GroupChain'] -is [System.Collections.IDictionary]) { $Policy['GroupChain'] } else { @{} }
    $groupPattern = '^/providers/microsoft\.management/managementgroups/([^/]+)$'
    $dataPlane = @{
        'microsoft.kubernetes.data'                 = @('microsoft.containerservice/managedclusters', 'microsoft.kubernetes/connectedclusters')
        'microsoft.keyvault.data'                   = @('microsoft.keyvault/vaults')
        'microsoft.managedhsm.data'                 = @('microsoft.keyvault/managedhsms')
        'microsoft.network.data'                    = @('microsoft.network/virtualnetworkmanagers')
        'microsoft.datafactory.data'                = @('microsoft.datafactory/factories')
        'microsoft.machinelearningservices.v2.data' = @('microsoft.machinelearningservices/workspaces')
        'microsoft.loadtestservice.data'            = @('microsoft.loadtestservice/loadtests')
    }

    $get = {
        param($Map, [string] $Name)
        if ($Map -isnot [System.Collections.IDictionary]) { return }
        foreach ($k in $Map.Keys) { if ($k -eq $Name) { return $Map[$k] } }
    }
    # Where a scope sits: its level, the name to show and the order on the path.
    $describe = {
        param([string] $Scope)
        $lower = $Scope.TrimEnd('/').ToLowerInvariant()
        # Management groups root first: by how deep they sit.
        if ($lower -match $groupPattern) { $n = $Matches[1]; return @{ Level = 'Management group'; Name = $(if ($groupNames.Contains($n)) { [string]$groupNames[$n] } else { $n }); Order = $(if ($groupChain.Contains($n)) { @($groupChain[$n]).Count / 1000 } else { 0 }) } }
        if ($lower -match '^/subscriptions/([^/]+)$') { $s = $Matches[1]; return @{ Level = 'Subscription'; Name = $(if ($subscriptionNames.Contains($s)) { [string]$subscriptionNames[$s] } else { $s }); Order = 1 } }
        if ($lower -match '^/subscriptions/[^/]+/resourcegroups/([^/]+)$') { return @{ Level = 'Resource group'; Name = ($Scope.TrimEnd('/') -split '/')[-1]; Order = 2 } }
        @{ Level = 'Resource'; Name = ($Scope.TrimEnd('/') -split '/')[-1]; Order = 3 }
    }
    # Does a scope contain the resource? A management group does when it's
    # on the subscription's path.
    $contains = {
        param([string] $Scope, [string] $Id, [string[]] $Groups)
        $s = $Scope.TrimEnd('/').ToLowerInvariant()
        if (-not $s) { return $false }
        if ($s -match $groupPattern) { return ($Groups -contains $Matches[1]) }
        $Id -eq $s -or $Id.StartsWith("$s/")
    }
    # A selector list: every selector must match. Kinds this resource can't
    # be judged on (policyDefinitionReferenceId) match.
    $selectorsMatch = {
        param($Selectors, [hashtable] $Facts, [string] $ReferenceId)
        foreach ($selector in @($Selectors)) {
            if ($selector -isnot [System.Collections.IDictionary]) { continue }
            $kind = [string](& $get $selector 'kind')
            $value = switch ($kind) {
                'resourceLocation' { $Facts.Location }
                'resourceType' { $Facts.Type }
                'resourceWithoutLocation' { if (-not $Facts.Location -or $Facts.Location -eq 'global') { 'true' } else { 'false' } }
                'policyDefinitionReferenceId' { $ReferenceId }
                default { $null }
            }
            if ($null -eq $value) { continue }
            $in = & $get $selector 'in'
            $notIn = & $get $selector 'notIn'
            if ($null -ne $in -and -not @(@($in) | Where-Object { [string]$_ -eq $value }).Count) { return $false }
            if ($null -ne $notIn -and @(@($notIn) | Where-Object { [string]$_ -eq $value }).Count) { return $false }
        }
        $true
    }
    # Resource selectors: the assignment (or exemption) covers what any of them selects.
    $resourceSelected = {
        param($ResourceSelectors, [hashtable] $Facts)
        $list = @($ResourceSelectors | Where-Object { $_ -is [System.Collections.IDictionary] })
        if (-not $list.Count) { return @{ Match = $true; Name = '' } }
        foreach ($rs in $list) { if (& $selectorsMatch (& $get $rs 'selectors') $Facts '') { return @{ Match = $true; Name = [string](& $get $rs 'name') } } }
        @{ Match = $false; Name = (@($list | ForEach-Object { [string](& $get $_ 'name') }) -join ', ') }
    }
    $impactOf = {
        param([string] $Effect, [bool] $Enforced)
        $e = $Effect.ToLowerInvariant()
        $impact = switch ($e) {
            'deny' { 'Blocks' } 'denyaction' { 'Blocks delete' } 'audit' { 'Audits' } 'auditifnotexists' { 'Audits' }
            'modify' { 'Changes' } 'append' { 'Changes' } 'deployifnotexists' { 'Deploys' } 'manual' { 'Manual' } 'disabled' { 'Disabled' }
            default { 'Unknown' }
        }
        if (-not $Enforced -and $impact -in 'Blocks', 'Blocks delete', 'Changes', 'Deploys') { 'Reports only' } else { $impact }
    }
    $effectName = @{ deny = 'Deny'; denyaction = 'DenyAction'; audit = 'Audit'; auditifnotexists = 'AuditIfNotExists'; modify = 'Modify'; append = 'Append'; deployifnotexists = 'DeployIfNotExists'; manual = 'Manual'; disabled = 'Disabled' }

    # --- Each assignment once: its scope, its policies and what each targets --------------------------------------------
    $assignments = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($row in @($Policy['Assignments'])) {
        if ($row -isnot [System.Collections.IDictionary]) { continue }
        $definitionId = ([string]$row['definitionId']).ToLowerInvariant()
        $definition = $definitions[$definitionId]
        $isSet = $definitionId -match '/policysetdefinitions/'
        if ($isSet -and $definition) {
            $members = @(Resolve-AACPolicySetMember -Member @($definition.Members) -SetParameter $definition.Parameters -Assigned $row['parameters'] -Override @($row['overrides']) -Definition $definitions)
        }
        else {
            # One policy: resolved as an initiative of one, each parameter
            # taking the assignment's value, else the definition's default.
            $refs = @{}
            if ($definition -and $definition.Parameters -is [System.Collections.IDictionary]) { foreach ($k in @($definition.Parameters.Keys)) { $refs[$k] = @{ value = "[parameters('$k')]" } } }
            $members = @(Resolve-AACPolicySetMember -Member @(@{ policyDefinitionId = $definitionId; policyDefinitionReferenceId = ''; parameters = $refs }) -SetParameter $(if ($definition) { $definition.Parameters }) -Assigned $row['parameters'] -Override @($row['overrides']) -Definition $definitions)
            foreach ($m in $members) { if ($m.EffectSource -eq 'Initiative default') { $m.EffectSource = 'Default' } }
        }
        $scope = [string]$row['scope']
        $where = & $describe $scope
        $prepared = foreach ($m in $members) {
            $d = $m.Definition
            $mode = if ($d) { [string]$d.Mode } else { '' }
            $targets = if ($d -and -not $dataPlane.Contains($mode.ToLowerInvariant())) { Get-AACPolicyResourceType -Rule $d.Rule -Parameter $m.Values } else { @{ Include = @(); Exclude = @(); Aliased = @(); Text = $(if ($mode) { $mode } else { 'All' }) } }
            $rawEffect = [string]$m.Effect
            # What an if-not-exists policy looks for, to say why it fails.
            $related = if ($d) { [string](& $get (& $get (& $get $d.Rule 'then') 'details') 'type') } else { '' }
            @{
                Member = $m; Mode = $mode; Targets = $targets; Related = $related
                Effect = $(if ($effectName.Contains($rawEffect.ToLowerInvariant())) { $effectName[$rawEffect.ToLowerInvariant()] } elseif ($rawEffect) { $rawEffect } else { '(not read)' })
                Name = $(if ($d) { [string]$d.DisplayName } else { ($m.DefinitionId -split '/')[-1] })
                Parameters = (@($m.Parameters | Where-Object { $_.Name -notmatch '^(?i)effect$' } | ForEach-Object { "$($_.Name)=$(Format-AACPolicyValue -Value $_.Value)" }) -join '; ')
            }
        }
        $assignments.Add(@{
                Row = $row; Id = ([string]$row['id']).ToLowerInvariant(); Scope = $scope; Where = $where; IsSet = $isSet; Definition = $definition
                Name = $(if ($row['displayName']) { [string]$row['displayName'] } else { [string]$row['name'] })
                SetName = $(if ($isSet) { if ($definition) { [string]$definition.DisplayName } else { ($definitionId -split '/')[-1] } } else { '' })
                Enforced = ([string]$row['enforcement'] -ne 'DoNotEnforce'); Identity = $(if ($row['identityType']) { [string]$row['identityType'] } else { 'None' })
                NotScopes = @($row['notScopes'] | Where-Object { $_ } | ForEach-Object { ([string]$_).TrimEnd('/').ToLowerInvariant() })
                Selectors = $row['resourceSelectors']; Messages = @($row['nonComplianceMessages'] | Where-Object { $_ -is [System.Collections.IDictionary] })
                Version = [string]$row['definitionVersion']; Members = @($prepared)
            })
    }

    # Does a member's rule target this type? Cached per member and type.
    $targetCache = @{}
    $targeting = {
        param([hashtable] $Prepared, [string] $Type, [string] $CacheKey)
        if ($targetCache.Contains($CacheKey)) { return $targetCache[$CacheKey] }
        $t = $Type.ToLowerInvariant()
        $mode = $Prepared.Mode.ToLowerInvariant()
        $verdict = if ($dataPlane.Contains($mode)) {
            if ($dataPlane[$mode] -contains $t) { @{ Applies = $true; Note = "Data-plane policy ($($Prepared.Mode)): evaluated inside the resource." } }
            else { @{ Applies = $false; Note = "A data-plane policy ($($Prepared.Mode)) for another kind of resource." } }
        }
        elseif ($Prepared.Targets.Include.Count) {
            if (@($Prepared.Targets.Include | Where-Object { $t -like $_.ToLowerInvariant() }).Count) { @{ Applies = $true; Note = '' } }
            else { @{ Applies = $false; Note = "The rule targets $($Prepared.Targets.Text)." } }
        }
        elseif ($Prepared.Targets.Aliased.Count) {
            if (@($Prepared.Targets.Aliased | Where-Object { $t -eq $_.ToLowerInvariant() -or $t.StartsWith("$($_.ToLowerInvariant())/") }).Count) { @{ Applies = $true; Note = '' } }
            else { @{ Applies = $false; Note = "The rule reads only properties of $($Prepared.Targets.Text)." } }
        }
        elseif (@($Prepared.Targets.Exclude | Where-Object { $t -like $_.ToLowerInvariant() }).Count) { @{ Applies = $true; Note = 'Its type is one the rule allows, so it passes on type.' } }
        else { @{ Applies = $true; Note = '' } }
        $targetCache[$CacheKey] = $verdict
        $verdict
    }

    # --- Exemptions and states, by what they cover -------------------------------------------------------------------
    $exemptionsByAssignment = @{}
    foreach ($e in @($Exemption)) {
        if ($e -isnot [System.Collections.IDictionary]) { continue }
        $id = [string]$e['id']
        $expires = $null
        $parsed = [datetime]::MinValue
        if ($e['expiresOn'] -and [datetime]::TryParse([string]$e['expiresOn'], [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]'AdjustToUniversal, AssumeUniversal', [ref]$parsed)) { $expires = $parsed }
        $info = @{
            Id = $id; Scope = ($id -replace '(?i)/providers/Microsoft\.Authorization/policyExemptions/[^/]+$', ''); Name = $(if ($e['displayName']) { [string]$e['displayName'] } else { [string]$e['name'] })
            AssignmentId = ([string]$e['assignmentId']).ToLowerInvariant(); ReferenceIds = @($e['referenceIds'] | Where-Object { $_ } | ForEach-Object { ([string]$_).ToLowerInvariant() })
            Category = [string]$e['category']; Expires = $expires; Expired = ($null -ne $expires -and $expires -lt $Now); Selectors = $e['resourceSelectors']; Description = [string]$e['description']
            Resources = [System.Collections.Generic.HashSet[string]]::new()
        }
        if (-not $exemptionsByAssignment.Contains($info.AssignmentId)) { $exemptionsByAssignment[$info.AssignmentId] = [System.Collections.Generic.List[hashtable]]::new() }
        $exemptionsByAssignment[$info.AssignmentId].Add($info)
    }
    $states = @{}
    foreach ($s in @($State)) {
        if ($s -isnot [System.Collections.IDictionary]) { continue }
        $key = '{0}|{1}|{2}' -f ([string]$s['resourceId']).ToLowerInvariant(), ([string]$s['assignmentId']).ToLowerInvariant(), ([string]$s['referenceId']).ToLowerInvariant()
        if (-not $states.Contains($key)) { $states[$key] = $s }
    }

    # --- Resource by resource -----------------------------------------------------------------------------------------
    $rows = [System.Collections.Generic.List[object]]::new()
    $findings = [System.Collections.Generic.List[object]]::new()
    $reached = @{}
    $finding = {
        param([string] $Severity, [string] $ResourceName, [string] $PolicyName, [string] $Text, [string] $Detail, [string] $Recommendation, [string] $Id)
        $findings.Add([pscustomobject]@{ PSTypeName = 'AAC.EffectivePolicyFinding'; Severity = $Severity; Resource = $ResourceName; Policy = $PolicyName; Finding = $Text; Detail = $Detail; Recommendation = $Recommendation; ResourceId = $Id })
    }
    $resourceRows = [System.Collections.Generic.List[object]]::new()
    foreach ($r in @($Resource)) {
        if ($r -isnot [System.Collections.IDictionary]) { continue }
        $id = ([string]$r['Id']).TrimEnd('/').ToLowerInvariant()
        $sub = if ($id -match '^/subscriptions/([^/]+)') { $Matches[1] } else { ([string]$r['SubscriptionId']).ToLowerInvariant() }
        $groups = @($subscriptionChain[$sub])
        $facts = @{ Location = ([string]$r['Location']).ToLowerInvariant() -replace '\s', ''; Type = ([string]$r['Type']).ToLowerInvariant() }
        $planned = [bool]$r['Planned']
        $name = [string]$r['Name']
        $group = if ([string]$r['ResourceGroup']) { [string]$r['ResourceGroup'] } elseif ($id -match '/resourcegroups/([^/]+)') { $Matches[1] } else { '' }
        $subName = if ($subscriptionNames.Contains($sub)) { [string]$subscriptionNames[$sub] } else { $sub }
        $own = [System.Collections.Generic.List[object]]::new()
        $notEvaluated = 0

        foreach ($a in $assignments) {
            if (-not (& $contains $a.Scope $id $groups)) { continue }
            $excludedBy = @($a.NotScopes | Where-Object { & $contains $_ $id $groups }) | Select-Object -First 1
            $selected = & $resourceSelected $a.Selectors $facts
            foreach ($p in $a.Members) {
                $m = $p.Member
                $ref = ([string]$m.ReferenceId).ToLowerInvariant()
                $stateRow = $states["$id|$($a.Id)|$ref"]
                $applicability = 'Applies'
                $note = ''
                if ($excludedBy) { $applicability = 'Excluded'; $note = "Left out by the assignment's notScopes ($((& $describe $excludedBy).Name))." }
                elseif (-not $selected.Match) { $applicability = 'Not selected'; $note = "The assignment's resource selectors ($($selected.Name)) don't select $($facts.Type) in $(if ($facts.Location) { $facts.Location } else { 'no location' })." }
                elseif (-not $m.Definition) { $note = "The policy definition couldn't be read, so its effect isn't known." }
                else {
                    $target = & $targeting $p ([string]$r['Type']) "$($a.Id)|$ref|$($facts.Type)"
                    if (-not $target.Applies -and -not $stateRow) { $applicability = 'Not targeted' }
                    $note = $target.Note
                }
                if ($applicability -eq 'Not targeted' -and -not $IncludeNotApplicable) { continue }

                # Exemptions: an expired one is shown, but doesn't exempt.
                $cover = $null
                $expired = $null
                if ($applicability -eq 'Applies' -and $exemptionsByAssignment.Contains($a.Id)) {
                    foreach ($e in $exemptionsByAssignment[$a.Id]) {
                        if (-not (& $contains $e.Scope $id $groups)) { continue }
                        if ($e.ReferenceIds.Count -and $e.ReferenceIds -notcontains $ref) { continue }
                        if (-not (& $resourceSelected $e.Selectors $facts).Match) { continue }
                        if ($e.Expired) { $expired = $e; continue }
                        $cover = $e
                        break
                    }
                    if ($cover) { $applicability = 'Exempt'; $null = $cover.Resources.Add($id) }
                    elseif ($expired) { $null = $expired.Resources.Add($id) }
                }
                if ($stateRow -and [string]$stateRow['state'] -eq 'Exempt' -and $applicability -eq 'Applies') { $applicability = 'Exempt' }

                $impact = switch ($applicability) {
                    'Applies' { & $impactOf $p.Effect $a.Enforced }
                    'Exempt' { 'Exempt' }
                    default { 'Not applicable' }
                }
                $stateText = if ($planned) { 'Planned' } elseif ($stateRow) { [string]$stateRow['state'] } elseif ($applicability -in 'Applies', 'Exempt') { 'Not evaluated' } else { '' }
                $evaluated = $null
                $parsedTime = [datetime]::MinValue
                if ($stateRow -and $stateRow['evaluated'] -and [datetime]::TryParse([string]$stateRow['evaluated'], [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]'AdjustToUniversal, AssumeUniversal', [ref]$parsedTime)) { $evaluated = $parsedTime }
                $why = $Reason["$id|$($a.Id)|$ref"]
                $message = @($a.Messages | Where-Object { "$(& $get $_ 'policyDefinitionReferenceId')".ToLowerInvariant() -eq $ref -and $ref }) + @($a.Messages | Where-Object { -not (& $get $_ 'policyDefinitionReferenceId') }) | Select-Object -First 1
                $shown = $cover
                if (-not $shown) { $shown = $expired }
                $row = [pscustomobject][ordered]@{
                    PSTypeName       = 'AAC.EffectivePolicy'
                    Resource         = $name
                    ResourceType     = [string]$r['Type']
                    ResourceGroup    = $group
                    Subscription     = $subName
                    Policy           = $p.Name
                    Initiative       = $a.SetName
                    ReferenceId      = [string]$m.ReferenceId
                    Assignment       = $a.Name
                    AssignedAt       = "$($a.Where.Level): $($a.Where.Name)"
                    Level            = $a.Where.Level
                    Applicability    = $applicability
                    Impact           = $impact
                    Effect           = $p.Effect
                    EffectSource     = [string]$m.EffectSource
                    Enforcement      = $(if ($a.Enforced) { 'Default' } else { 'DoNotEnforce' })
                    State            = $stateText
                    Evaluated        = $evaluated
                    Reason           = $(if ($why -and $why.Reason) { $why.Reason }
                        elseif ($stateText -ne 'NonCompliant') { $note }
                        elseif ($p.Related -and $p.Effect -in 'AuditIfNotExists', 'DeployIfNotExists') { "The $($p.Related) it looks for is missing, or doesn't meet the policy's conditions." }
                        elseif ($message) { [string](& $get $message 'message') }
                        elseif ($why -and @($why.Expressions).Count) { "A value doesn't match the policy - see the field." }
                        else { 'Azure found it non-compliant; the compliance details in the portal show the evaluation.' })
                    Detail           = $(if ($why) { @($why.Expressions) -join '; ' } else { '' })
                    Exemption        = $(if ($shown) { "$($shown.Name) ($($shown.Category)$(if ($shown.Expired) { ', expired' }))" } else { '' })
                    ExemptionExpires = $(if ($shown) { $shown.Expires } else { $null })
                    Message          = $(if ($message) { [string](& $get $message 'message') } else { '' })
                    Identity         = $(if ($p.Effect -in 'DeployIfNotExists', 'Modify') { $a.Identity } else { '' })
                    Controls         = (@($m.Groups) -join ', ')
                    Targets          = $p.Targets.Text
                    Mode             = $p.Mode
                    Version          = $a.Version
                    Category         = $(if ($m.Definition) { [string]$m.Definition.Category } else { '' })
                    PolicyType       = $(if ($m.Definition) { [string]$m.Definition.PolicyType } else { '' })
                    Parameters       = $p.Parameters
                    ResourceId       = [string]$r['Id']
                    AssignmentId     = [string]$a.Row['id']
                    DefinitionId     = [string]$m.DefinitionId
                }
                $own.Add($row)
                if ($applicability -in 'Applies', 'Exempt') {
                    if (-not $reached.Contains($a.Id)) { $reached[$a.Id] = @{ Assignment = $a; Policies = [System.Collections.Generic.HashSet[string]]::new(); Resources = [System.Collections.Generic.HashSet[string]]::new() } }
                    $null = $reached[$a.Id].Policies.Add($ref + '|' + $m.DefinitionId)
                    $null = $reached[$a.Id].Resources.Add($id)
                }

                # What to act on.
                if ($planned) { continue }
                if ($stateText -eq 'NonCompliant' -and $impact -eq 'Blocks') {
                    & $finding 'High' $name $p.Name 'Non-compliant with a deny policy: the next deployment that touches it will be refused' $row.Reason "Change $(if ($row.Detail) { "what the policy checks ($($row.Detail))" } else { 'the setting the policy checks' }) - or, if it must stay, add an exemption - before the next deployment." $row.ResourceId
                }
                elseif ($stateText -eq 'NonCompliant' -and $impact -in 'Changes', 'Deploys') {
                    if ($a.Identity -eq 'None') { & $finding 'High' $name $p.Name "Non-compliant, and the assignment can't fix it: it has no managed identity" "$($p.Effect) needs an identity with a role to remediate." 'Give the assignment a managed identity with the roles the policy names, then start a remediation task.' $row.ResourceId }
                    else { & $finding 'Medium' $name $p.Name "Non-compliant: a remediation task would fix it ($($p.Effect))" 'New and updated resources are fixed as they are deployed; existing ones wait for a remediation task.' 'Start a remediation task for the assignment (Get-AACPolicyRemediation lists the running ones).' $row.ResourceId }
                }
                if ($cover -and $cover.Expires -and ($cover.Expires - $Now).TotalDays -le 30) {
                    & $finding 'Medium' $name $p.Name "Exemption '$($cover.Name)' ends $($cover.Expires.ToString('yyyy-MM-dd'))" "After that the resource is evaluated again$(if ($impact -eq 'Exempt' -and $p.Effect -eq 'Deny') { ' - and its next deployment refused if it still breaks the policy' })." 'Fix the resource before then, or renew the exemption with a reason.' $row.ResourceId
                }
                elseif ($expired) {
                    & $finding 'Low' $name $p.Name "Exemption '$($expired.Name)' expired $($expired.Expires.ToString('yyyy-MM-dd'))" 'It no longer exempts anything, but is still assigned.' 'Delete it, or renew it if the reason still holds.' $row.ResourceId
                }
                if ($stateText -eq 'Not evaluated' -and $applicability -eq 'Applies') { $notEvaluated++ }
            }
        }
        if ($notEvaluated) {
            & $finding 'Info' $name '' "$notEvaluated applicable policy evaluation(s) have no compliance result yet" 'Azure evaluates within about 30 minutes of a change, and every 24 hours. AuditIfNotExists, DeployIfNotExists and resources in Indexed mode that hold no tags or location may never show one.' 'Check again later, or start an on-demand evaluation scan for the subscription.' ([string]$r['Id'])
        }
        foreach ($row in $own) { $rows.Add($row) }
        $applying = @($own | Where-Object Applicability -EQ 'Applies')
        $resourceRows.Add([pscustomobject][ordered]@{
                PSTypeName   = 'AAC.EffectivePolicyResource'
                Resource     = $name
                ResourceType = [string]$r['Type']
                ResourceGroup = $group
                Subscription = $subName
                Location     = [string]$r['Location']
                Policies     = $applying.Count
                Blocks       = @($applying | Where-Object Impact -EQ 'Blocks').Count
                Audits       = @($applying | Where-Object Impact -EQ 'Audits').Count
                Changes      = @($applying | Where-Object Impact -In 'Changes', 'Deploys').Count
                NonCompliant = @($own | Where-Object State -EQ 'NonCompliant').Count
                Exempt       = @($own | Where-Object Applicability -EQ 'Exempt').Count
                NotEvaluated = $notEvaluated
                State        = $(if ($planned) { 'Planned' } elseif (@($own | Where-Object State -EQ 'NonCompliant').Count) { 'NonCompliant' } elseif ($applying.Count -and -not @($own | Where-Object State -EQ 'Compliant').Count) { 'Not evaluated' } elseif ($applying.Count) { 'Compliant' } else { 'No policy' })
                ResourceId   = [string]$r['Id']
            })
    }

    # --- The chain and the exemptions ---------------------------------------------------------------------------------
    $chain = @($reached.Values | ForEach-Object {
            $a = $_.Assignment
            [pscustomobject][ordered]@{
                PSTypeName  = 'AAC.EffectivePolicyAssignment'
                Level       = $a.Where.Level
                Scope       = $a.Where.Name
                Assignment  = $a.Name
                Definition  = $(if ($a.IsSet) { $a.SetName } elseif ($a.Members.Count) { $a.Members[0].Name } else { '' })
                Kind        = $(if ($a.IsSet) { 'Initiative' } else { 'Policy' })
                Policies    = $_.Policies.Count
                Resources   = $_.Resources.Count
                Enforcement = $(if ($a.Enforced) { 'Default' } else { 'DoNotEnforce' })
                Identity    = $a.Identity
                NotScopes   = $a.NotScopes.Count
                Selectors   = (@($a.Selectors | Where-Object { $_ -is [System.Collections.IDictionary] } | ForEach-Object { [string](& $get $_ 'name') }) -join ', ')
                Version     = $a.Version
                Order       = $a.Where.Order
                AssignmentId = [string]$a.Row['id']
            }
        } | Sort-Object -Property Order, Scope, Assignment)
    $exemptionRows = @(foreach ($list in $exemptionsByAssignment.Values) {
            foreach ($e in $list) {
                if (-not $e.Resources.Count) { continue }
                $assignment = @($assignments | Where-Object { $_.Id -eq $e.AssignmentId }) | Select-Object -First 1
                [pscustomobject][ordered]@{
                    PSTypeName   = 'AAC.EffectivePolicyExemption'
                    Exemption    = $e.Name
                    Category     = $e.Category
                    Status       = $(if ($e.Expired) { 'Expired' } elseif (-not $e.Expires) { 'No end date' } elseif (($e.Expires - $Now).TotalDays -le 30) { 'Ending soon' } else { 'Active' })
                    Expires      = $e.Expires
                    Assignment   = $(if ($assignment) { $assignment.Name } else { ($e.AssignmentId -split '/')[-1] })
                    Policies     = $(if ($e.ReferenceIds.Count) { $e.ReferenceIds -join ', ' } else { 'All' })
                    DefinedAt    = "$((& $describe $e.Scope).Level): $((& $describe $e.Scope).Name)"
                    Resources    = $e.Resources.Count
                    Description  = $e.Description
                    ExemptionId  = $e.Id
                }
            }
        })
    $applies = @($rows | Where-Object Applicability -EQ 'Applies')
    @{
        Policies    = $rows.ToArray()
        Resources   = $resourceRows.ToArray()
        Assignments = $chain
        Exemptions  = $exemptionRows
        Findings    = $findings.ToArray()
        Stats       = @{
            Resources    = $resourceRows.Count
            Assignments  = $chain.Count
            Applies      = $applies.Count
            Blocks       = @($applies | Where-Object Impact -In 'Blocks', 'Blocks delete').Count
            Audits       = @($applies | Where-Object Impact -EQ 'Audits').Count
            Changes      = @($applies | Where-Object Impact -In 'Changes', 'Deploys').Count
            ReportsOnly  = @($applies | Where-Object Impact -EQ 'Reports only').Count
            Exempt       = @($rows | Where-Object Applicability -EQ 'Exempt').Count
            LeftOut      = @($rows | Where-Object Applicability -In 'Excluded', 'Not selected', 'Not targeted').Count
            NonCompliant = @($rows | Where-Object State -EQ 'NonCompliant').Count
            Compliant    = @($rows | Where-Object State -EQ 'Compliant').Count
            NotEvaluated = @($rows | Where-Object State -EQ 'Not evaluated').Count
            High         = @($findings | Where-Object Severity -EQ 'High').Count
            Expiring     = @($exemptionRows | Where-Object Status -EQ 'Ending soon').Count
        }
    }
}
