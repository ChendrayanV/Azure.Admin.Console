function ConvertTo-AACAssessmentInsight {
    <#
    .SYNOPSIS
        Builds Invoke-AACTenantAssessment's sheets for the people who ask:
        Identity and access (IT security), Architecture, Operations
        (administrators) and Service delivery (service delivery managers) -
        with every gap as a finding.
    .DESCRIPTION
        No Azure calls: the command reads, this decides. Inputs:
          -Read           Get-AACAssessmentInsightQuery's rows, by name
          -Arm            per-subscription REST answers, by kind and key:
                          Active, Eligible (PIM schedule instances, by scope),
                          ClassicAdmin, Lock, Activity (by subscription ID),
                          Diagnostic (by resource ID), Location, Reservation,
                          SavingsPlan (key 'all')
          -Asked          kind -> the keys asked (a key asked but not in
                          -Arm couldn't be read)
          -Directory      Get-AACDirectoryObject's Objects (-DirectoryRead)
          -Application    app registrations with their credentials
                          (-ApplicationRead)
          -VaultItem, -VaultAccess  Read-AACKeyVaultObject's result
                          (-VaultRead)
          -CostTrend      subscription ID -> monthly cost rows (-CostRead)
          -Sheet          the assessment's sheets so far (Quotas, All
                          resources, Support tickets)

        Sheets, by tab:
          Identity and access  Privileged access, Custom roles, Classic
                               administrators, Defender plans, Expiring
                               credentials, Management ports open, Public
                               network access
          Architecture         Landing zone, Regions, Resilience, Network
                               topology, Private DNS zones
          Operations           Diagnostic settings, Log Analytics workspaces,
                               Monitoring, Alert rules without action group,
                               Patch compliance, Arc servers, Production
                               locks, Activity, Failed deployments,
                               Deprecated SKUs, Naming and tags
          Service delivery     Subscription offers, Reservations, Savings
                               plans, Quota headroom, Cost trend, Ownership
                               map
        Returns @{ Sheets; Findings (rows in the shape of Resource
        recommendations); Stats; Notices }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [System.Collections.IDictionary] $Read = @{},
        [hashtable] $Arm = @{},
        [hashtable] $Asked = @{},
        [hashtable] $Directory = @{},
        [AllowEmptyCollection()] [object[]] $Application = @(),
        [AllowEmptyCollection()] [object[]] $VaultItem = @(),
        [hashtable] $VaultAccess = @{},
        [hashtable] $CostTrend = @{},
        [AllowEmptyCollection()] [object[]] $Resource = @(),
        [AllowEmptyCollection()] [object[]] $Subscription = @(),
        [AllowEmptyCollection()] [object[]] $ResourceGroup = @(),
        [AllowEmptyCollection()] [object[]] $ManagementGroup = @(),
        [AllowEmptyCollection()] [object[]] $Sheet = @(),
        [string[]] $OwnerTag = @('Owner', 'Contact', 'TechnicalOwner', 'BusinessOwner'),
        [string] $ProductionPattern = '(?i)(^|[-_.\s])(prod|prd|production|live)([-_.\s]|$)',
        [int] $ExpiryDays = 30,
        [int] $ActivityDays = 30,
        [switch] $IdentityRead,
        [switch] $DirectoryRead,
        [switch] $ApplicationRead,
        [switch] $VaultRead,
        [switch] $CostRead,
        [datetime] $Now = [datetime]::UtcNow
    )

    # --- Helpers ---------------------------------------------------------------------------------------------------
    $m = { param($Item, [string] $Path) if ($null -eq $Item) { $null } else { Get-AACMember -InputObject $Item -Path $Path } }
    $rowsOf = { param([string] $Name) @(if ($Read.Contains($Name)) { $Read[$Name] | Where-Object { $null -ne $_ } }) }
    $list = { param($Item) @(if ($Item -is [System.Collections.IEnumerable] -and $Item -isnot [string] -and $Item -isnot [System.Collections.IDictionary]) { $Item } elseif ($null -ne $Item) { , $Item }) | Where-Object { $null -ne $_ } }
    $armOf = { param([string] $Kind, [string] $Key) if ($Arm.Contains($Kind) -and $Arm[$Kind].Contains($Key)) { , @($Arm[$Kind][$Key]) } else { $null } }
    $wasAsked = { param([string] $Kind, [string] $Key) $Asked.Contains($Kind) -and @($Asked[$Kind]) -contains $Key }
    $lower = { param($Text) ([string]$Text).ToLowerInvariant() }
    $leaf = { param($Id) if ($Id) { ([string]$Id).TrimEnd('/') -replace '^.*/', '' } else { '' } }
    $groupOf = { param($Id) if ([string]$Id -match '(?i)/resourceGroups/([^/]+)') { $Matches[1] } else { '' } }
    $subOf = { param($Id) if ([string]$Id -match '(?i)^/subscriptions/([^/]+)') { $Matches[1].ToLowerInvariant() } else { '' } }
    $typeOf = { param($Id) if ([string]$Id -match '(?i)/providers/([^/]+/[^/]+)/[^/]+$') { $Matches[1].ToLowerInvariant() } else { '' } }
    $short = { param([string] $Type) $Type -replace '^microsoft\.', '' }
    $date = {
        param($Text)
        if ($Text -is [datetime]) { return $Text.ToUniversalTime() }
        $d = [datetime]::MinValue
        if ($Text -and [datetime]::TryParse([string]$Text, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$d)) { $d } else { $null }
    }
    $day = { param($When) if ($When) { $When.ToString('yyyy-MM-dd') } else { '' } }
    $percent = { param([double] $Part, [double] $Whole) if ($Whole) { [Math]::Round(100.0 * $Part / $Whole, 1) } else { $null } }
    $subscriptionNames = @{}
    foreach ($row in $Subscription) { $subscriptionNames[(& $lower $row['subscriptionId'])] = [string]$row['name'] }
    $subName = { param($Id) $key = & $lower $Id; if ($subscriptionNames.Contains($key)) { $subscriptionNames[$key] } else { [string]$Id } }
    $tagValue = {
        param($Tags, [string[]] $Names)
        if ($Tags -isnot [System.Collections.IDictionary]) { return '' }
        foreach ($key in @($Tags.Keys)) { if (@($Names | Where-Object { $_ -eq [string]$key }).Count -and "$($Tags[$key])".Trim()) { return [string]$Tags[$key] } }
        ''
    }
    $environmentTags = @('Environment', 'Env', 'Stage', 'Tier')
    $isProduction = { param([string] $Name, $Tags) $Name -match $ProductionPattern -or (& $tagValue $Tags $environmentTags) -match $ProductionPattern }
    $productionSubs = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($row in $Subscription) { if (& $isProduction ([string]$row['name']) $row['tags']) { [void]$productionSubs.Add((& $lower $row['subscriptionId'])) } }
    $productionGroups = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($row in $ResourceGroup) { if (& $isProduction ([string]$row['name']) $row['tags'] -or $productionSubs.Contains((& $lower $row['subscriptionId']))) { [void]$productionGroups.Add((& $lower $row['id'])) } }
    $resourceIsProduction = { param([string] $Id, $Tags) $sub = & $subOf $Id; $productionSubs.Contains($sub) -or $productionGroups.Contains("/subscriptions/$sub/resourcegroups/$((& $groupOf $Id).ToLowerInvariant())") -or (& $tagValue $Tags $environmentTags) -match $ProductionPattern }

    $sheets = [System.Collections.Generic.List[hashtable]]::new()
    $slug = { param([string] $Name) ($Name.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-') }
    $newSheet = {
        param([string] $Category, [string] $Name, [System.Collections.IDictionary] $Types, [object[]] $Rows, [string[]] $Key, [string] $Note)
        $sheets.Add(@{ Id = & $slug $Name; Kind = 'Insight'; Category = $Category; Sheet = $Name; Columns = @($Types.Keys); Types = $Types; Rows = @($Rows); Key = @($Key); Error = ''; Note = $Note })
    }
    $findings = [System.Collections.Generic.List[object]]::new()
    $notices = [System.Collections.Generic.List[string]]::new()
    $find = {
        param([string] $Severity, [string] $Category, [string] $Source, [string] $Text, [string] $Id, [string] $Name, [string] $Remedy, [string] $Link = '', [string] $Type = '')
        $findings.Add([pscustomobject][ordered]@{
                'Severity' = $Severity; 'Category' = $Category; 'Source' = $Source; 'Recommendation' = $Text
                'Resource' = $(if ($Name) { $Name } else { & $leaf $Id }); 'Resource type' = $(if ($Type) { $Type } else { & $typeOf $Id })
                'Resource group' = & $groupOf $Id; 'Subscription' = $(if (& $subOf $Id) { & $subName (& $subOf $Id) } else { '' })
                'Remediation' = $Remedy; 'Link' = $Link; 'ResourceId' = $Id
            })
    }
    $stats = [ordered]@{}

    # Management groups: names, parents, depth (the tenant root is 0), and which are above the subscriptions in scope.
    $mgName = @{}; $mgParent = @{}
    foreach ($row in $ManagementGroup) { $key = & $lower $row['name']; $mgName[$key] = [string]$(if ($row['displayName']) { $row['displayName'] } else { $row['name'] }); $mgParent[$key] = & $lower $row['parent'] }
    $depthOf = { param([string] $Key) $d = 0; $seen = 0; while ($mgParent.Contains($Key) -and $mgParent[$Key] -and $seen -lt 20) { $Key = $mgParent[$Key]; $d++; $seen++ }; $d }
    $relevantGroups = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($row in $Subscription) { foreach ($c in @(& $list $row['chain'])) { [void]$relevantGroups.Add((& $lower (& $m $c 'name'))) } }
    $scopeLevel = {
        param([string] $Scope)
        if ($Scope -eq '/') { 'Root' } elseif ($Scope -match '^/providers/microsoft\.management/managementgroups/([^/]+)$') { 'Management group' } elseif ($Scope -match '^/subscriptions/[^/]+$') { 'Subscription' } else { '' }
    }
    $scopeName = {
        param([string] $Scope)
        if ($Scope -eq '/') { 'Root (/)' } elseif ($Scope -match '^/providers/microsoft\.management/managementgroups/([^/]+)$') { if ($mgName.Contains($Matches[1])) { $mgName[$Matches[1]] } else { $Matches[1] } } elseif ($Scope -match '^/subscriptions/([^/]+)$') { & $subName $Matches[1] } else { $Scope }
    }
    $scopeInScope = {
        param([string] $Scope)
        if ($Scope -eq '/') { return $true }
        if ($Scope -match '^/providers/microsoft\.management/managementgroups/([^/]+)$') { return $relevantGroups.Contains($Matches[1]) }
        if ($Scope -match '^/subscriptions/([^/]+)$') { return $subscriptionNames.Contains($Matches[1]) }
        $false
    }

    # ==================================================================================================================
    # Identity and access
    # ==================================================================================================================
    $tab = 'Identity and access'
    $roleDefs = @{}
    foreach ($row in & $rowsOf 'roleDefinitions') {
        $actions = @(@(& $list $row['permissions']) | ForEach-Object { & $list (& $m $_ 'actions') } | ForEach-Object { [string]$_ })
        $roleDefs[(& $lower $row['name'])] = @{ Name = [string]$row['roleName']; Type = [string]$row['roleType']; Actions = $actions; Scopes = @(& $list $row['assignableScopes'] | ForEach-Object { [string]$_ }); Id = [string]$row['id'] }
    }
    $privilegedNames = @('Owner', 'User Access Administrator', 'Role Based Access Control Administrator')
    $isPrivileged = { param([string] $Guid) $def = $roleDefs[$Guid]; $def -and ($def.Name -in $privilegedNames -or ($def.Type -eq 'CustomRole' -and $def.Actions -contains '*')) }
    $principalOf = {
        param([string] $PrincipalId, [string] $Type, $Expanded)
        $object = if ($Directory.Contains($PrincipalId)) { $Directory[$PrincipalId] } else { $null }
        $odata = [string](& $m $object '@odata.type')
        $kind = if ($odata -match 'user') { 'User' } elseif ($odata -match 'group') { 'Group' } elseif ($odata -match 'servicePrincipal') { if ([string](& $m $object 'servicePrincipalType') -eq 'ManagedIdentity') { 'Managed identity' } else { 'Service principal' } } elseif ($Type) { $Type -replace 'ServicePrincipal', 'Service principal' -replace 'ForeignGroup', 'Group' } else { '' }
        $upn = [string](& $m $object 'userPrincipalName')
        $name = [string]$(@((& $m $object 'displayName'), (& $m $Expanded 'principal.displayName'), $PrincipalId) | Where-Object { $_ } | Select-Object -First 1)
        $guest = if (-not $object) { 'Unknown' } elseif ([string](& $m $object 'userType') -eq 'Guest' -or $upn -match '#EXT#') { 'Yes' } else { 'No' }
        @{ Name = $name; Kind = $kind; Upn = $upn; Guest = $guest; Deleted = $DirectoryRead -and -not $object -and -not $Expanded }
    }
    # PIM: active assignments (Activated from an eligibility, or Assigned - permanent or time-bound) and eligibilities.
    $pimActive = @{}
    $pimEligible = [System.Collections.Generic.List[object]]::new()
    $pimRead = $false
    $pimMissing = 0
    foreach ($kind in 'Active', 'Eligible') {
        foreach ($scopeKey in @(if ($Asked.Contains($kind)) { $Asked[$kind] })) {
            $items = & $armOf $kind $scopeKey
            if ($null -eq $items) { $pimMissing++; continue }
            $pimRead = $true
            foreach ($i in $items) {
                $p = & $m $i 'properties'
                $key = "$(& $lower (& $m $p 'principalId'))|$(& $lower (& $leaf (& $m $p 'roleDefinitionId')))|$(& $lower (& $m $p 'scope'))"
                if ($kind -eq 'Active') { $pimActive[$key] = $p } else { $pimEligible.Add($p) }
            }
        }
    }
    $privilegedRows = [System.Collections.Generic.List[object]]::new()
    $ownersBySub = @{}
    $addPrivileged = {
        param([string] $PrincipalId, [string] $PrincipalType, [string] $RoleGuid, [string] $Scope, [string] $Assignment, $Ends, [string] $Since, $Expanded)
        $who = & $principalOf $PrincipalId $PrincipalType $Expanded
        $role = $roleDefs[$RoleGuid].Name
        $level = & $scopeLevel $Scope
        $privilegedRows.Add([pscustomobject][ordered]@{
                'Role' = $role; 'Level' = $level; 'Scope' = & $scopeName $Scope; 'Principal' = $who.Name; 'Principal type' = $who.Kind; 'Sign-in name' = $who.Upn
                'Guest' = $who.Guest; 'Assignment' = $Assignment; 'Ends' = & $day $Ends; 'Since' = & $day (& $date $Since); 'ResourceId' = $Scope
            })
        if ($role -eq 'Owner' -and $level -eq 'Subscription' -and $Assignment -ne 'Eligible (PIM)') {
            $sub = & $subOf $Scope
            if (-not $ownersBySub.Contains($sub)) { $ownersBySub[$sub] = [System.Collections.Generic.List[object]]::new() }
            $ownersBySub[$sub].Add(@{ Name = $who.Name; Kind = $who.Kind; Assignment = $Assignment })
        }
        $label = "$role on $(& $scopeName $Scope) ($level)"
        if ($who.Deleted) { & $find 'Medium' 'Security' 'Privileged access' "Role assignment for a deleted principal: $label" $Scope $who.Name 'Remove the assignment: its principal no longer exists, and a new object could one day reuse the ID''s place in reviews.' 'https://learn.microsoft.com/azure/role-based-access-control/troubleshoot-role-assignments' }
        elseif ($who.Guest -eq 'Yes') { & $find 'High' 'Security' 'Privileged access' "Guest with $label" $Scope $who.Name 'Give guests the least role they need, at the narrowest scope, through PIM with approval - or remove the assignment.' 'https://learn.microsoft.com/entra/id-governance/privileged-identity-management/pim-resource-roles-assign-roles' }
        elseif ($who.Kind -in 'Service principal', 'Managed identity' -and $Assignment -ne 'Eligible (PIM)') { & $find 'High' 'Security' 'Privileged access' "$($who.Kind) with $label" $Scope $who.Name 'Give the workload Contributor (or narrower) on the resource groups it deploys - an identity that can grant access can grant itself anything, and its secret can leak.' 'https://learn.microsoft.com/azure/role-based-access-control/best-practices' }
        elseif ($Assignment -eq 'Permanent' -and $who.Kind -in 'User', 'Group') { & $find $(if ($level -eq 'Subscription') { 'Medium' } else { 'High' }) 'Security' 'Privileged access' "Standing (permanent) $label" $Scope $who.Name 'Make the assignment eligible in Privileged Identity Management, with approval and a time limit, so the role is held only while it is used.' 'https://learn.microsoft.com/entra/id-governance/privileged-identity-management/pim-resource-roles-assign-roles' }
    }
    if ($IdentityRead) {
        foreach ($a in & $rowsOf 'roleAssignments') {
            $scope = & $lower $a['scope']
            $guid = & $leaf (& $lower $a['roleId'])
            if (-not (& $scopeLevel $scope) -or -not (& $scopeInScope $scope) -or -not (& $isPrivileged $guid)) { continue }
            $principalId = & $lower $a['principalId']
            $pim = $pimActive["$principalId|$guid|$scope"]
            $assignment = if ($pim) { if ([string](& $m $pim 'assignmentType') -eq 'Activated') { 'Activated (PIM)' } elseif (& $m $pim 'endDateTime') { 'Time-bound' } else { 'Permanent' } } elseif ($pimRead) { 'Permanent' } else { 'Active (PIM not read)' }
            & $addPrivileged $principalId ([string]$a['principalType']) $guid $scope $assignment $(if ($pim) { & $date (& $m $pim 'endDateTime') }) ([string]$a['createdOn']) $(if ($pim) { & $m $pim 'expandedProperties' })
        }
        foreach ($p in $pimEligible) {
            $scope = & $lower (& $m $p 'scope')
            $guid = & $leaf (& $lower (& $m $p 'roleDefinitionId'))
            if (-not (& $scopeLevel $scope) -or -not (& $isPrivileged $guid)) { continue }
            & $addPrivileged (& $lower (& $m $p 'principalId')) ([string](& $m $p 'principalType')) $guid $scope 'Eligible (PIM)' (& $date (& $m $p 'endDateTime')) ([string](& $m $p 'startDateTime')) (& $m $p 'expandedProperties')
        }
        foreach ($sub in $ownersBySub.Keys) {
            $standing = @($ownersBySub[$sub] | Where-Object { $_.Assignment -in 'Permanent', 'Active (PIM not read)' })
            if ($standing.Count -gt 3) { & $find 'Medium' 'Security' 'Privileged access' "$($standing.Count) standing Owners on the subscription" "/subscriptions/$sub" (& $subName $sub) 'Keep at most three Owners (and at least two), and make the rest eligible through PIM.' 'https://learn.microsoft.com/azure/defender-for-cloud/recommendations-reference-identity-access' 'subscription' }
        }
        if ($pimMissing) { $notices.Add("Privileged Identity Management couldn't be read for $pimMissing scope(s) (it needs Microsoft Entra ID P2, and read access): their active assignments show as 'Active (PIM not read)'.") }
    }
    & $newSheet $tab 'Privileged access' ([ordered]@{ 'Role' = 'badge'; 'Level' = 'badge'; 'Scope' = 'text'; 'Principal' = 'text'; 'Principal type' = 'badge'; 'Sign-in name' = 'text'; 'Guest' = 'badge'; 'Assignment' = 'badge'; 'Ends' = 'text'; 'Since' = 'text' }) `
        @($privilegedRows | Sort-Object { @{ Root = 0; 'Management group' = 1; Subscription = 2 }[$_.Level] }, Scope, Role, Principal) @('Role', 'Level', 'Scope', 'Principal', 'Assignment') `
        'Owner, User Access Administrator, Role Based Access Control Administrator and custom roles that allow everything (*), at the root, management groups and subscriptions - active and eligible (Privileged Identity Management).'
    $stats.PrivilegedAssignments = $privilegedRows.Count
    $stats.PrivilegedStanding = @($privilegedRows | Where-Object Assignment -EQ 'Permanent').Count
    $stats.PrivilegedGuests = @($privilegedRows | Where-Object Guest -EQ 'Yes').Count

    # Custom roles: the wildcards they allow, and whether they are used.
    $assignedRoles = @{}
    foreach ($a in & $rowsOf 'roleAssignments') { $g = & $leaf (& $lower $a['roleId']); $assignedRoles[$g] = 1 + [int]$assignedRoles[$g] }
    $customRows = @(foreach ($guid in $roleDefs.Keys) {
            $def = $roleDefs[$guid]
            if ($def.Type -ne 'CustomRole') { continue }
            $wild = @($def.Actions | Where-Object { $_ -eq '*' -or $_ -match '^(?i)Microsoft\.Authorization/(\*|roleAssignments/\*|roleAssignments/write)$' -or $_ -match '^\*/' })
            $everything = $def.Actions -contains '*'
            $count = [int]$assignedRoles[$guid]
            if ($everything) { & $find $(if ($count) { 'High' } else { 'Medium' }) 'Security' 'Custom roles' "Custom role '$($def.Name)' allows every action (*)$(if ($count) { " - $count assignment(s)" })" $def.Id $def.Name 'List the actions the role needs instead of *: as it is, the role is Owner by another name and escapes reviews of Owner.' 'https://learn.microsoft.com/azure/role-based-access-control/custom-roles' 'microsoft.authorization/roledefinitions' }
            elseif ($wild.Count) { & $find 'Medium' 'Security' 'Custom roles' "Custom role '$($def.Name)' can grant access ($($wild -join ', '))" $def.Id $def.Name 'Remove Microsoft.Authorization write actions unless the role is meant to grant access - and then review who holds it.' 'https://learn.microsoft.com/azure/role-based-access-control/custom-roles' 'microsoft.authorization/roledefinitions' }
            [pscustomobject][ordered]@{ 'Role' = $def.Name; 'Allows everything' = $(if ($everything) { 'Yes' } else { 'No' }); 'Wildcards' = $wild -join ', '; 'Actions' = $def.Actions.Count; 'Assignments' = $count; 'Assignable scopes' = $def.Scopes -join ', '; 'ResourceId' = $def.Id }
        })
    & $newSheet $tab 'Custom roles' ([ordered]@{ 'Role' = 'text'; 'Allows everything' = 'badge'; 'Wildcards' = 'wide'; 'Actions' = 'number'; 'Assignments' = 'number'; 'Assignable scopes' = 'wide' }) @($customRows | Sort-Object 'Allows everything', Role -Descending) @('Role', 'Allows everything', 'Wildcards', 'Assignments') ''

    # Classic administrators (Service Administrator, co-administrators).
    $classicRows = @(foreach ($sub in @(if ($Asked.Contains('ClassicAdmin')) { $Asked['ClassicAdmin'] })) {
            $admins = & $armOf 'ClassicAdmin' $sub
            foreach ($i in @($admins)) {
                if (-not $i) { continue }
                [pscustomobject][ordered]@{ 'Subscription' = & $subName $sub; 'Administrator' = [string](& $m $i 'properties.emailAddress'); 'Role' = [string](& $m $i 'properties.role'); 'ResourceId' = "/subscriptions/$sub" }
            }
        })
    foreach ($group in $classicRows | Group-Object Subscription) { & $find 'Medium' 'Security' 'Classic administrators' "$($group.Count) classic administrator(s) on the subscription" $group.Group[0].ResourceId $group.Name 'Give each one an Azure role (Owner only where needed) and remove the classic administrators - classic roles bypass Azure RBAC and its reviews.' 'https://learn.microsoft.com/azure/role-based-access-control/classic-administrators' 'subscription' }
    & $newSheet $tab 'Classic administrators' ([ordered]@{ 'Subscription' = 'text'; 'Administrator' = 'text'; 'Role' = 'badge' }) $classicRows @('Subscription', 'Administrator', 'Role') ''

    # Defender for Cloud plans, against what each subscription runs.
    $planTypes = @{
        VirtualMachines = @('microsoft.compute/virtualmachines', 'microsoft.hybridcompute/machines', 'microsoft.compute/virtualmachinescalesets'); SqlServers = @('microsoft.sql/servers')
        AppServices = @('microsoft.web/sites'); StorageAccounts = @('microsoft.storage/storageaccounts'); KeyVaults = @('microsoft.keyvault/vaults')
        Containers = @('microsoft.containerservice/managedclusters', 'microsoft.containerregistry/registries'); CosmosDbs = @('microsoft.documentdb/databaseaccounts')
        OpenSourceRelationalDatabases = @('microsoft.dbforpostgresql/flexibleservers', 'microsoft.dbformysql/flexibleservers', 'microsoft.dbformariadb/servers'); Api = @('microsoft.apimanagement/service')
        AI = @('microsoft.cognitiveservices/accounts'); SqlServerVirtualMachines = @('microsoft.sqlvirtualmachine/sqlvirtualmachines')
    }
    $typeCount = @{}
    foreach ($r in $Resource) { $key = "$(& $lower $r['subscriptionId'])|$(& $lower $r['type'])"; $typeCount[$key] = 1 + [int]$typeCount[$key] }
    $planRows = @(foreach ($p in & $rowsOf 'pricings') {
            $sub = [string]$p['subscriptionId']
            if (-not $subscriptionNames.Contains($sub)) { continue }
            $inUse = if ($planTypes.Contains([string]$p['name'])) { [int](@($planTypes[[string]$p['name']] | ForEach-Object { [int]$typeCount["$sub|$_"] }) | Measure-Object -Sum).Sum } elseif ([string]$p['name'] -eq 'Arm') { 1 } else { $null }
            [pscustomobject][ordered]@{ 'Subscription' = & $subName $sub; 'Plan' = [string]$p['name']; 'Tier' = [string]$p['tier']; 'Sub-plan' = [string]$p['subPlan']; 'Resources it covers' = $inUse; 'ResourceId' = "/subscriptions/$sub" }
        })
    foreach ($group in $planRows | Group-Object Subscription) {
        $off = @($group.Group | Where-Object { $_.Tier -eq 'Free' -and $_.'Resources it covers' })
        if ($off.Count) { & $find 'Medium' 'Security' 'Defender for Cloud' "Defender plans off for resources the subscription runs: $(@($off | ForEach-Object Plan) -join ', ')" $group.Group[0].ResourceId $group.Name 'Turn the plans on for the resource types the subscription runs (Defender for Cloud > Environment settings), or record why not.' 'https://learn.microsoft.com/azure/defender-for-cloud/defender-for-cloud-introduction' 'subscription' }
    }
    & $newSheet $tab 'Defender plans' ([ordered]@{ 'Subscription' = 'text'; 'Plan' = 'text'; 'Tier' = 'badge'; 'Sub-plan' = 'text'; 'Resources it covers' = 'number' }) @($planRows | Sort-Object Subscription, Plan) @('Subscription', 'Plan', 'Tier', 'Resources it covers') 'Each Defender for Cloud plan per subscription, and how many resources of the kinds it protects the subscription runs.'
    $stats.DefenderPlansOff = @($planRows | Where-Object { $_.Tier -eq 'Free' -and $_.'Resources it covers' }).Count

    # Expiring credentials: Key Vault secrets, keys and certificates, and app registration secrets and certificates.
    $statusOf = { param($Expires) if (-not $Expires) { 'No expiry' } elseif ($Expires -lt $Now) { 'Expired' } elseif ($Expires -le $Now.AddDays($ExpiryDays)) { 'Expiring' } else { 'Valid' } }
    $vaultNames = @{}
    foreach ($r in $Resource) { if ((& $lower $r['type']) -eq 'microsoft.keyvault/vaults') { $vaultNames[(& $lower $r['id'])] = [string]$r['name'] } }
    $credentialRows = [System.Collections.Generic.List[object]]::new()
    $noExpiry = @{}
    foreach ($i in $VaultItem) {
        if (-not $i -or -not $i.Enabled) { continue }
        $vault = & $lower $i.VaultId
        $expires = & $date $i.Expires
        $status = & $statusOf $expires
        if ($status -eq 'No expiry') { if ($i.Kind -ne 'Certificate') { $noExpiry[$vault] = 1 + [int]$noExpiry[$vault] }; continue }
        if ($status -eq 'Valid') { continue }
        $credentialRows.Add([pscustomobject][ordered]@{ 'Status' = $status; 'Kind' = "Key Vault $($i.Kind.ToLowerInvariant())"; 'Name' = $i.Name; 'Held by' = $(if ($vaultNames.Contains($vault)) { $vaultNames[$vault] } else { & $leaf $vault }); 'Expires' = & $day $expires; 'Days left' = [int][Math]::Floor(($expires - $Now).TotalDays); 'Subscription' = & $subName (& $subOf $vault); 'ResourceId' = $vault })
        & $find $(if ($status -eq 'Expired') { 'Medium' } else { 'Medium' }) 'Security' 'Key Vault' "Key Vault $($i.Kind.ToLowerInvariant()) '$($i.Name)' $(if ($status -eq 'Expired') { 'has expired' } else { "expires on $(& $day $expires)" })" $vault $(if ($vaultNames.Contains($vault)) { $vaultNames[$vault] } else { '' }) 'Rotate it (or set an automatic rotation policy) and update what uses it; delete it if nothing does.' 'https://learn.microsoft.com/azure/key-vault/keys/how-to-configure-key-rotation'
    }
    foreach ($vault in $noExpiry.Keys) { & $find 'Low' 'Security' 'Key Vault' "$($noExpiry[$vault]) secret(s) or key(s) with no expiry date" $vault $(if ($vaultNames.Contains($vault)) { $vaultNames[$vault] } else { '' }) 'Set an expiry date (and a rotation policy) on secrets and keys - Azure Policy can require it.' 'https://learn.microsoft.com/azure/key-vault/general/azure-policy' }
    foreach ($app in @($Application | Where-Object { $_ })) {
        foreach ($credential in @(@(& $list (& $m $app 'passwordCredentials') | ForEach-Object { @{ Kind = 'App registration secret'; C = $_ } }) + @(& $list (& $m $app 'keyCredentials') | ForEach-Object { @{ Kind = 'App registration certificate'; C = $_ } }))) {
            $expires = & $date (& $m $credential.C 'endDateTime')
            $status = & $statusOf $expires
            if ($status -notin 'Expired', 'Expiring') { continue }
            $appName = [string](& $m $app 'displayName')
            $credentialRows.Add([pscustomobject][ordered]@{ 'Status' = $status; 'Kind' = $credential.Kind; 'Name' = [string]$(@((& $m $credential.C 'displayName'), (& $m $credential.C 'keyId')) | Where-Object { $_ } | Select-Object -First 1); 'Held by' = $appName; 'Expires' = & $day $expires; 'Days left' = [int][Math]::Floor(($expires - $Now).TotalDays); 'Subscription' = '(tenant)'; 'ResourceId' = "/applications/$(& $m $app 'appId')" })
        }
    }
    foreach ($group in @($credentialRows | Where-Object { $_.Kind -like 'App registration*' }) | Group-Object 'Held by') {
        $expiring = @($group.Group | Where-Object Status -EQ 'Expiring')
        if ($expiring.Count) { & $find 'Medium' 'Security' 'App registrations' "App registration '$($group.Name)': $($expiring.Count) credential(s) expire within $ExpiryDays days" '' $group.Name 'Add a new credential, move the application to it, then remove the old one - or use a managed identity or workload identity federation instead of a secret.' 'https://learn.microsoft.com/entra/workload-id/workload-identity-federation' 'app registration' }
        elseif ($group.Group.Count) { & $find 'Low' 'Security' 'App registrations' "App registration '$($group.Name)': $($group.Group.Count) expired credential(s) still listed" '' $group.Name 'Remove expired credentials, and check the application still signs in (or delete it).' '' 'app registration' }
    }
    & $newSheet $tab 'Expiring credentials' ([ordered]@{ 'Status' = 'badge'; 'Kind' = 'badge'; 'Name' = 'text'; 'Held by' = 'text'; 'Expires' = 'text'; 'Days left' = 'number'; 'Subscription' = 'text' }) @($credentialRows | Sort-Object 'Days left', Name) @('Status', 'Kind', 'Name', 'Held by', 'Expires') `
        "Key Vault secrets, keys and certificates, and app registration secrets and certificates, expired or expiring within $ExpiryDays days (-ExpiryDays). Values are never read."
    if ($VaultRead) {
        $blocked = @($VaultAccess.Values | Where-Object { $_ -ne 'Read' })
        if ($blocked.Count) { $notices.Add("$($blocked.Count) Key Vault(s) couldn't be listed (firewall, private endpoint or no data-plane permission - Key Vault Reader), so their expiry dates are left out.") }
    }
    if (-not $ApplicationRead -and $IdentityRead) { $notices.Add('App registration credentials weren''t read: the sign-in needs Application.Read.All in Microsoft Graph.') }
    $stats.CredentialsExpiring = @($credentialRows | Where-Object Status -In 'Expired', 'Expiring').Count

    # Management ports open to the internet.
    # String keys: an ordered dictionary indexed by a number reads that position, not that key.
    $managementPorts = [ordered]@{ '22' = 'SSH'; '3389' = 'RDP'; '5985' = 'WinRM'; '5986' = 'WinRM (HTTPS)' }
    $portRows = @(foreach ($r in & $rowsOf 'nsgRules') {
            $open = [System.Collections.Generic.List[string]]::new()
            foreach ($range in @(& $list $r['ports']) | ForEach-Object { [string]$_ } | Where-Object { $_ }) {
                foreach ($key in $managementPorts.Keys) {
                    $port = [int]$key
                    $hit = if ($range -eq '*') { $true } elseif ($range -match '^(\d+)-(\d+)$') { $port -ge [int]$Matches[1] -and $port -le [int]$Matches[2] } elseif ($range -match '^\d+$') { [int]$range -eq $port } else { $false }
                    if ($hit -and -not $open.Contains($managementPorts[$key])) { $open.Add($managementPorts[$key]) }
                }
            }
            if (-not $open.Count) { continue }
            $attached = [int]$r['subnets'] + [int]$r['nics']
            & $find $(if ($attached) { 'High' } else { 'Low' }) 'Security' 'Network' "$($open -join ', ') open to the internet: rule '$($r['rule'])'$(if (-not $attached) { ' (NSG not attached)' })" ([string]$r['nsgId']) ([string]$r['nsg']) 'Close the rule; reach machines through Azure Bastion or just-in-time VM access (Defender for Cloud) instead.' 'https://learn.microsoft.com/azure/bastion/bastion-overview' 'microsoft.network/networksecuritygroups'
            [pscustomobject][ordered]@{ 'NSG' = [string]$r['nsg']; 'Rule' = [string]$r['rule']; 'Priority' = $r['priority']; 'Open' = $open -join ', '; 'Ports' = (@(& $list $r['ports']) | Where-Object { $_ }) -join ', '; 'Source' = (@(& $list $r['sources']) | Where-Object { $_ }) -join ', '; 'Attached to' = "$([int]$r['subnets']) subnet(s), $([int]$r['nics']) NIC(s)"; 'Subscription' = & $subName $r['subscriptionId']; 'Resource group' = [string]$r['resourceGroup']; 'ResourceId' = [string]$r['nsgId'] }
        })
    & $newSheet $tab 'Management ports open' ([ordered]@{ 'NSG' = 'resource'; 'Rule' = 'text'; 'Priority' = 'number'; 'Open' = 'badge'; 'Ports' = 'text'; 'Source' = 'text'; 'Attached to' = 'text'; 'Subscription' = 'text'; 'Resource group' = 'text' }) $portRows @('NSG', 'Rule', 'Open', 'Source') 'Inbound rules that allow SSH, RDP or WinRM from any address (*, Internet, 0.0.0.0/0).'
    $stats.ManagementPortsOpen = @($portRows | Where-Object { $_.'Attached to' -notmatch '^0 subnet\(s\), 0 NIC' }).Count

    # PaaS services reachable from the internet.
    $paasRows = @(foreach ($r in & $rowsOf 'paas') {
            $public = [string]$r['publicAccess']
            $default = [string]$r['defaultAction']
            $status = if ($public -match '^(?i)disabled$') { 'Private only' } elseif ($default -match '^(?i)deny$' -or [int]$r['ipRules']) { 'Public, restricted' } else { 'Open to all networks' }
            if ($status -eq 'Open to all networks') { & $find 'Medium' 'Security' 'Network' "Reachable from any network ($(& $short ([string]$r['type'])))" ([string]$r['id']) ([string]$r['name']) 'Turn off public network access and use a private endpoint - or at least allow only the networks and addresses that need it.' 'https://learn.microsoft.com/azure/private-link/private-endpoint-overview' }
            [pscustomobject][ordered]@{ 'Resource' = [string]$r['name']; 'Type' = & $short ([string]$r['type']); 'Access' = $status; 'Public network access' = $(if ($public) { $public } else { '(not set)' }); 'Default action' = $default; 'IP rules' = [int]$r['ipRules']; 'Private endpoints' = [int]$r['privateEndpoints']; 'Subscription' = & $subName $r['subscriptionId']; 'Resource group' = [string]$r['resourceGroup']; 'ResourceId' = [string]$r['id'] }
        })
    & $newSheet $tab 'Public network access' ([ordered]@{ 'Resource' = 'resource'; 'Type' = 'mono'; 'Access' = 'badge'; 'Public network access' = 'text'; 'Default action' = 'text'; 'IP rules' = 'number'; 'Private endpoints' = 'number'; 'Subscription' = 'text'; 'Resource group' = 'text' }) @($paasRows | Sort-Object Access, Type, Resource) @('Resource', 'Type', 'Access', 'Private endpoints') 'PaaS services and how they can be reached: open to all networks, public but restricted to some networks and addresses, or private only.'
    $stats.PaasOpen = @($paasRows | Where-Object Access -EQ 'Open to all networks').Count

    # ==================================================================================================================
    # Architecture
    # ==================================================================================================================
    $tab = 'Architecture'
    $policyAt = @{}
    foreach ($p in & $rowsOf 'policyAssignments') { $s = [string]$p['scope']; $policyAt[$s] = 1 + [int]$policyAt[$s] }
    $roleAt = @{}
    foreach ($a in & $rowsOf 'roleAssignments') { $s = & $lower $a['scope']; $roleAt[$s] = 1 + [int]$roleAt[$s] }
    $subsUnder = @{}; $subsBelow = @{}
    $rootGroup = @($ManagementGroup | Where-Object { -not $_['parent'] } | ForEach-Object { & $lower $_['name'] }) | Select-Object -First 1
    $atRoot = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $Subscription) {
        $chain = @(& $list $row['chain'] | ForEach-Object { & $lower (& $m $_ 'name') })
        $parent = if ($chain.Count) { $chain[0] } else { '' }
        $subsUnder[$parent] = 1 + [int]$subsUnder[$parent]
        foreach ($g in $chain) { $subsBelow[$g] = 1 + [int]$subsBelow[$g] }
        if (-not $parent -or $parent -eq $rootGroup) { $atRoot.Add($row) }
    }
    $mgRows = @(foreach ($row in $ManagementGroup) {
            $key = & $lower $row['name']
            $scope = "/providers/microsoft.management/managementgroups/$key"
            $inForce = [int]$policyAt[$scope]; $walk = $key; $guard = 0
            while ($mgParent.Contains($walk) -and $mgParent[$walk] -and $guard -lt 20) { $walk = $mgParent[$walk]; $inForce += [int]$policyAt["/providers/microsoft.management/managementgroups/$walk"]; $guard++ }
            $depth = & $depthOf $key
            if (-not $inForce -and [int]$subsBelow[$key]) { & $find 'Low' 'Governance' 'Landing zone' "Management group '$($mgName[$key])' has no policy in force (here or above)" $scope $mgName[$key] 'Assign the platform''s baseline initiatives (allowed locations, required tags, diagnostics, Defender) at an upper management group so every subscription below inherits them.' 'https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-area/resource-org-management-groups' 'management group' }
            [pscustomobject][ordered]@{
                'Management group' = $mgName[$key]; 'ID' = [string]$row['name']; 'Parent' = $(if ($mgParent[$key]) { $mgName[$mgParent[$key]] } else { '' }); 'Depth' = $depth
                'Subscriptions (direct)' = [int]$subsUnder[$key]; 'Subscriptions (all below)' = [int]$subsBelow[$key]; 'Policy assignments (here)' = [int]$policyAt[$scope]; 'Policies in force (here and above)' = $inForce
                'Role assignments (here)' = $(if ($IdentityRead) { [int]$roleAt[$scope] } else { $null }); 'ResourceId' = $scope
            }
        })
    foreach ($row in $atRoot) { & $find 'Medium' 'Governance' 'Landing zone' 'Subscription directly under the Tenant Root Group' "/subscriptions/$($row['subscriptionId'])" ([string]$row['name']) 'Move it under the management group for its purpose (platform, landing zones, sandbox, decommissioned), so it inherits the right policies and access.' 'https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-area/resource-org-management-groups' 'subscription' }
    $maxDepth = [int](@($mgRows | ForEach-Object Depth) + 0 | Measure-Object -Maximum).Maximum
    if ($maxDepth -gt 4) { & $find 'Low' 'Governance' 'Landing zone' "The management group hierarchy is $maxDepth levels deep" '' 'Tenant' 'Keep it to three or four levels below the root: deep hierarchies make policy and access hard to follow.' 'https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-area/resource-org-management-groups' 'management group' }
    & $newSheet $tab 'Landing zone' ([ordered]@{ 'Management group' = 'text'; 'ID' = 'mono'; 'Parent' = 'text'; 'Depth' = 'number'; 'Subscriptions (direct)' = 'number'; 'Subscriptions (all below)' = 'number'; 'Policy assignments (here)' = 'number'; 'Policies in force (here and above)' = 'number'; 'Role assignments (here)' = 'number' }) `
        @($mgRows | Sort-Object Depth, 'Management group') @('Management group', 'Depth', 'Subscriptions (all below)', 'Policies in force (here and above)') "The management group hierarchy: depth below the Tenant Root Group, subscriptions, and the policy and role assignments at each level. $($atRoot.Count) subscription(s) sit directly under the root."
    $stats.ManagementGroupDepth = $maxDepth
    $stats.SubscriptionsAtRoot = $atRoot.Count

    # Regions, with their pairs and zones.
    $locationInfo = @{}
    $locations = & $armOf 'Location' 'all'
    foreach ($l in @($locations)) { if ($l) { $locationInfo[(& $lower (& $m $l 'name'))] = $l } }
    $zonal = { param([string] $Location) $info = $locationInfo[(& $lower $Location)]; if (-not $info) { $null } else { @(& $list (& $m $info 'availabilityZoneMappings')).Count -gt 0 } }
    $byRegion = @{}
    foreach ($r in $Resource) { $loc = & $lower $r['location']; if (-not $loc -or $loc -eq 'global') { continue }; if (-not $byRegion.Contains($loc)) { $byRegion[$loc] = [System.Collections.Generic.List[object]]::new() }; $byRegion[$loc].Add($r) }
    $regionRows = @(foreach ($loc in $byRegion.Keys) {
            $info = $locationInfo[$loc]
            $pair = [string](@(& $list (& $m $info 'metadata.pairedRegion')) | ForEach-Object { & $m $_ 'name' } | Select-Object -First 1)
            [pscustomobject][ordered]@{
                'Region' = $(if ($info) { [string](& $m $info 'displayName') } else { $loc }); 'Resources' = $byRegion[$loc].Count; 'Subscriptions' = @($byRegion[$loc] | ForEach-Object { $_['subscriptionId'] } | Select-Object -Unique).Count
                'Resource types' = @($byRegion[$loc] | ForEach-Object { & $lower $_['type'] } | Select-Object -Unique).Count; 'Availability zones' = $(switch (& $zonal $loc) { $true { 'Yes' } $false { 'No' } default { 'Unknown' } })
                'Paired region' = $pair; 'Pair in use' = $(if (-not $pair) { '' } elseif ($byRegion.Contains($pair.ToLowerInvariant())) { 'Yes' } else { 'No' }); 'ResourceId' = ''
            }
        })
    & $newSheet $tab 'Regions' ([ordered]@{ 'Region' = 'text'; 'Resources' = 'number'; 'Subscriptions' = 'number'; 'Resource types' = 'number'; 'Availability zones' = 'badge'; 'Paired region' = 'text'; 'Pair in use' = 'badge' }) @($regionRows | Sort-Object Resources -Descending) @('Region', 'Resources', 'Availability zones', 'Paired region', 'Pair in use') 'Where the estate runs: each region''s resources, whether it has availability zones, and whether its paired region (for geo-redundant storage and disaster recovery) is used too.'
    $stats.Regions = $regionRows.Count

    # Resilience of the critical resources: zones, backup, Site Recovery.
    $backedUp = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($b in & $rowsOf 'backupItems') { [void]$backedUp.Add([string]$b['source']) }
    $replicated = [System.Collections.Generic.HashSet[string]]::new()
    $replicatedNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($a in & $rowsOf 'asrItems') { if ($a['source']) { [void]$replicated.Add([string]$a['source']) }; if ($a['name']) { [void]$replicatedNames.Add([string]$a['name']) } }
    $resilienceRows = @(foreach ($r in & $rowsOf 'resilience') {
            $type = [string]$r['type']; $zones = @(& $list $r['zones']); $sku = [string]$r['sku']
            $zone = switch ($type) {
                'microsoft.compute/virtualmachines' { if ($zones.Count) { "Zonal (zone $($zones -join ', '))" } else { 'None' } }
                'microsoft.storage/storageaccounts' { if ($sku -match 'GZRS|ZRS') { 'Zone-redundant' } elseif ($sku -match 'GRS') { 'Geo-redundant (not zonal)' } else { 'None' } }
                'microsoft.containerservice/managedclusters' { if (@(& $list $r['poolZones'] | Where-Object { @(& $list (& $m $_ 'availabilityZones')).Count -ge 2 }).Count) { 'Zone-redundant' } else { 'None' } }
                'microsoft.documentdb/databaseaccounts' { if (@(& $list $r['cosmosLocations'] | Where-Object { [string](& $m $_ 'isZoneRedundant') -eq 'True' }).Count) { 'Zone-redundant' } else { 'None' } }
                { $_ -in 'microsoft.dbforpostgresql/flexibleservers', 'microsoft.dbformysql/flexibleservers' } { switch ([string]$r['ha']) { 'ZoneRedundant' { 'Zone-redundant' } 'SameZone' { 'Same-zone high availability' } default { 'None' } } }
                { $_ -in 'microsoft.cache/redis', 'microsoft.network/applicationgateways' } { if ($zones.Count -ge 2) { 'Zone-redundant' } elseif ($zones.Count) { "Zonal (zone $($zones -join ', '))" } else { 'None' } }
                default { if ([string]$r['zoneRedundant'] -eq 'True') { 'Zone-redundant' } else { 'None' } }
            }
            if ($zone -eq 'None' -and (& $zonal ([string]$r['location'])) -eq $false) { $zone = 'No zones in this region' }
            $backup = switch ($type) {
                'microsoft.compute/virtualmachines' { if ($backedUp.Contains([string]$r['id'])) { 'Protected' } else { 'Not protected' } }
                'microsoft.containerservice/managedclusters' { if ($backedUp.Contains([string]$r['id'])) { 'Protected' } else { 'Not protected' } }
                { $_ -in 'microsoft.sql/servers/databases', 'microsoft.documentdb/databaseaccounts', 'microsoft.dbforpostgresql/flexibleservers', 'microsoft.dbformysql/flexibleservers' } { 'Built in' }
                default { 'N/A' }
            }
            $asr = if ($type -eq 'microsoft.compute/virtualmachines') { if ($replicated.Contains([string]$r['id']) -or $replicatedNames.Contains([string]$r['name'])) { 'Replicated' } else { 'No' } } else { '' }
            $production = & $resourceIsProduction ([string]$r['id']) $r['tags']
            if ($backup -eq 'Not protected' -and $type -eq 'microsoft.compute/virtualmachines') { & $find $(if ($production) { 'Medium' } else { 'Low' }) 'Reliability' 'Resilience' "$(if ($production) { 'Production VM' } else { 'VM' }) not backed up" ([string]$r['id']) ([string]$r['name']) 'Protect it with Azure Backup (a Recovery Services vault and a policy) - or record why it needs no backup (stateless, rebuilt from code).' 'https://learn.microsoft.com/azure/backup/backup-azure-vms-introduction' }
            if ($production -and $zone -eq 'None') { & $find 'Low' 'Reliability' 'Resilience' "Production $(& $short $type) with no zone redundancy" ([string]$r['id']) ([string]$r['name']) 'Use availability zones (zone-redundant SKUs, or instances spread across zones) so a datacenter failure doesn''t take it down.' 'https://learn.microsoft.com/azure/reliability/availability-zones-overview' }
            [pscustomobject][ordered]@{ 'Resource' = [string]$r['name']; 'Type' = & $short $type; 'Production' = $(if ($production) { 'Yes' } else { 'No' }); 'Zones' = $zone; 'Backup' = $backup; 'Site Recovery' = $asr; 'SKU' = $sku; 'Location' = [string]$r['location']; 'Subscription' = & $subName $r['subscriptionId']; 'Resource group' = [string]$r['resourceGroup']; 'ResourceId' = [string]$r['id'] }
        })
    & $newSheet $tab 'Resilience' ([ordered]@{ 'Resource' = 'resource'; 'Type' = 'mono'; 'Production' = 'badge'; 'Zones' = 'badge'; 'Backup' = 'badge'; 'Site Recovery' = 'badge'; 'SKU' = 'text'; 'Location' = 'text'; 'Subscription' = 'text'; 'Resource group' = 'text' }) `
        @($resilienceRows | Sort-Object Production, Type, Resource -Descending) @('Resource', 'Type', 'Zones', 'Backup', 'Site Recovery') "The critical resources - VMs, databases, storage, AKS, App Service plans, Redis, Cosmos DB, application gateways: zone redundancy, Azure Backup and Site Recovery. Production is a subscription, resource group or Environment tag matching -ProductionPattern."
    $stats.VmsNotBackedUp = @($resilienceRows | Where-Object { $_.Type -eq 'compute/virtualmachines' -and $_.Backup -eq 'Not protected' }).Count

    # Network topology: hub and spoke, Virtual WAN, overlaps, private DNS.
    $vnets = @(& $rowsOf 'vnets')
    $hubs = @(& $rowsOf 'hubs')
    $gatewayIn = @{}
    foreach ($g in & $rowsOf 'gateways') { if ($g['vnet']) { $gatewayIn[[string]$g['vnet']] = @(@($gatewayIn[[string]$g['vnet']]) + @(if ([string]$g['type'] -like '*azurefirewalls') { 'Firewall' } else { 'Gateway' }) | Where-Object { $_ } | Select-Object -Unique) } }
    $dnsLinks = @{}
    foreach ($l in & $rowsOf 'dnsLinks') { $v = [string]$l['vnet']; $dnsLinks[$v] = 1 + [int]$dnsLinks[$v] }
    $vnetById = @{}
    foreach ($v in $vnets) { $vnetById[[string]$v['id']] = $v }
    $isHub = { param($V) $gatewayIn.Contains([string]$V['id']) -or [int]$V['gatewayTransit'] -gt 0 }
    # Overlaps: every IPv4 prefix as a range, sorted by start, compared with those still open.
    $ranges = [System.Collections.Generic.List[object]]::new()
    foreach ($v in $vnets) { foreach ($prefix in @(& $list $v['prefixes'])) { $range = ConvertTo-AACCidrRange ([string]$prefix); if ($range.Valid -and $range.Version -eq 4) { $ranges.Add(@{ Start = [double]$range.Start; End = [double]$range.End; Id = [string]$v['id']; Prefix = [string]$prefix }) } } }
    foreach ($h in $hubs) { if ($h['prefix']) { $range = ConvertTo-AACCidrRange ([string]$h['prefix']); if ($range.Valid -and $range.Version -eq 4) { $ranges.Add(@{ Start = [double]$range.Start; End = [double]$range.End; Id = [string]$h['id']; Prefix = [string]$h['prefix'] }) } } }
    $overlaps = @{}
    $open = [System.Collections.Generic.List[object]]::new()
    foreach ($range in $ranges | Sort-Object { $_.Start }) {
        $still = @($open | Where-Object { $_.End -ge $range.Start })
        $open.Clear(); foreach ($o in $still) { $open.Add($o) }
        foreach ($o in $open) {
            if ($o.Id -eq $range.Id) { continue }
            foreach ($pair in @(@($o.Id, $range.Id), @($range.Id, $o.Id))) { if (-not $overlaps.Contains($pair[0])) { $overlaps[$pair[0]] = [System.Collections.Generic.HashSet[string]]::new() }; [void]$overlaps[$pair[0]].Add($pair[1]) }
        }
        $open.Add($range)
    }
    $nameOfNetwork = { param([string] $Id) if ($vnetById.Contains($Id)) { [string]$vnetById[$Id]['name'] } else { & $leaf $Id } }
    $reported = [System.Collections.Generic.HashSet[string]]::new()
    $topologyRows = @(
        foreach ($v in $vnets) {
            $id = [string]$v['id']; $remotes = @(& $list $v['remotes'] | ForEach-Object { [string]$_ })
            $toHub = @($remotes | Where-Object { $vnetById.Contains($_) -and (& $isHub $vnetById[$_]) })
            $role = if (@($remotes | Where-Object { $_ -match '/virtualhubs/|/hv_' }).Count) { 'Virtual WAN spoke' } elseif (& $isHub $v) { "Hub ($($remotes.Count) peering(s))" } elseif ($toHub.Count -or [int]$v['useRemote']) { 'Spoke' } elseif ($remotes.Count) { 'Peered' } else { 'Isolated' }
            $clash = @(if ($overlaps.Contains($id)) { $overlaps[$id] })
            foreach ($other in $clash) {
                if (-not $reported.Add((@($id, $other) | Sort-Object) -join '|')) { continue }
                $peered = $remotes -contains $other
                & $find $(if ($peered) { 'High' } else { 'Medium' }) 'Reliability' 'Network' "Address space overlaps $(& $nameOfNetwork $other)$(if ($peered) { ' (peered)' })" $id ([string]$v['name']) 'Re-address one of the networks: overlapping networks can''t be peered or routed to each other, and block hub and spoke and hybrid connectivity. Get-AACIPAMReport finds free ranges.' 'https://learn.microsoft.com/azure/virtual-network/virtual-network-peering-overview'
            }
            $dns = @(& $list $v['dns'])
            [pscustomobject][ordered]@{ 'Network' = [string]$v['name']; 'Role' = $role; 'Address space' = (@(& $list $v['prefixes']) -join ', '); 'Peerings' = $remotes.Count; 'Gateway or firewall' = (@($gatewayIn[$id]) | Where-Object { $_ }) -join ', '; 'DNS servers' = $(if ($dns.Count) { $dns -join ', ' } else { 'Azure-provided' }); 'Private DNS zones linked' = [int]$dnsLinks[$id]; 'Overlaps with' = (@($clash | ForEach-Object { & $nameOfNetwork $_ }) -join ', '); 'Location' = [string]$v['location']; 'Subscription' = & $subName $v['subscriptionId']; 'Resource group' = [string]$v['resourceGroup']; 'ResourceId' = $id }
        }
        foreach ($h in $hubs) {
            [pscustomobject][ordered]@{ 'Network' = [string]$h['name']; 'Role' = 'Virtual WAN hub'; 'Address space' = [string]$h['prefix']; 'Peerings' = $null; 'Gateway or firewall' = (@(& $rowsOf 'gateways' | Where-Object { [string]$_['hub'] -eq [string]$h['id'] } | ForEach-Object { if ([string]$_['type'] -like '*azurefirewalls') { 'Firewall' } else { 'Gateway' } }) | Select-Object -Unique) -join ', '; 'DNS servers' = ''; 'Private DNS zones linked' = $null; 'Overlaps with' = (@(if ($overlaps.Contains([string]$h['id'])) { $overlaps[[string]$h['id']] | ForEach-Object { & $nameOfNetwork $_ } }) -join ', '); 'Location' = [string]$h['location']; 'Subscription' = & $subName $h['subscriptionId']; 'Resource group' = [string]$h['resourceGroup']; 'ResourceId' = [string]$h['id'] }
        }
    )
    $hubVnets = @($vnets | Where-Object { & $isHub $_ }).Count
    $topology = if ($hubs.Count -and $hubVnets) { 'Virtual WAN, with hub virtual networks too' } elseif ($hubs.Count) { 'Virtual WAN' } elseif ($hubVnets) { 'Hub and spoke' } elseif (@($vnets | Where-Object { @(& $list $_['remotes']).Count }).Count) { 'Peered networks, no hub' } elseif ($vnets.Count) { 'Isolated networks' } else { 'No virtual networks' }
    & $newSheet $tab 'Network topology' ([ordered]@{ 'Network' = 'resource'; 'Role' = 'badge'; 'Address space' = 'text'; 'Peerings' = 'number'; 'Gateway or firewall' = 'text'; 'DNS servers' = 'text'; 'Private DNS zones linked' = 'number'; 'Overlaps with' = 'wide'; 'Location' = 'text'; 'Subscription' = 'text'; 'Resource group' = 'text' }) `
        @($topologyRows | Sort-Object Role, Network) @('Network', 'Role', 'Address space', 'Overlaps with') "Topology: $topology. Each virtual network's role (a hub has a gateway or firewall, or offers gateway transit; a spoke peers to a hub), its DNS, the private DNS zones linked to it and the networks its address space overlaps (Get-AACIPAMReport goes deeper)."
    $stats.Topology = $topology
    $stats.NetworkOverlaps = $reported.Count
    $zoneRows = @(foreach ($z in & $rowsOf 'dnsZones') {
            if (-not [int]$z['links']) { & $find 'Low' 'Operational excellence' 'Network' 'Private DNS zone linked to no virtual network' ([string]$z['id']) ([string]$z['name']) 'Link it to the networks that resolve it (in hub and spoke, the hub or the DNS resolver''s network) - or delete it.' 'https://learn.microsoft.com/azure/dns/private-dns-virtual-network-links' }
            [pscustomobject][ordered]@{ 'Zone' = [string]$z['name']; 'Network links' = [int]$z['links']; 'Records' = [int]$z['records']; 'Subscription' = & $subName $z['subscriptionId']; 'Resource group' = [string]$z['resourceGroup']; 'ResourceId' = [string]$z['id'] }
        })
    foreach ($group in $zoneRows | Group-Object Zone | Where-Object Count -GT 1) { & $find 'Medium' 'Reliability' 'Network' "Private DNS zone $($group.Name) exists $($group.Count) times" $group.Group[0].ResourceId $group.Name 'Keep one copy of each privatelink zone (in the connectivity subscription) linked to every network that resolves it: copies resolve the same name differently depending on where you ask.' 'https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/private-link-and-dns-integration-at-scale' 'microsoft.network/privatednszones' }
    & $newSheet $tab 'Private DNS zones' ([ordered]@{ 'Zone' = 'text'; 'Network links' = 'number'; 'Records' = 'number'; 'Subscription' = 'text'; 'Resource group' = 'text' }) @($zoneRows | Sort-Object Zone) @('Zone', 'Network links', 'Records') ''

    # ==================================================================================================================
    # Operations
    # ==================================================================================================================
    $tab = 'Operations'
    # Diagnostic settings, by resource type: to Log Analytics, elsewhere, or none.
    $diagnostic = @{}
    foreach ($id in @(if ($Asked.Contains('Diagnostic')) { $Asked['Diagnostic'] })) {
        $type = & $typeOf $id
        if (-not $diagnostic.Contains($type)) { $diagnostic[$type] = @{ Checked = 0; Workspace = 0; Elsewhere = 0; None = 0; Unread = 0 } }
        $settings = & $armOf 'Diagnostic' $id
        if ($null -eq $settings) { $diagnostic[$type].Unread++; continue }
        $diagnostic[$type].Checked++
        $settings = @($settings | Where-Object { $_ })
        if (@($settings | Where-Object { & $m $_ 'properties.workspaceId' }).Count) { $diagnostic[$type].Workspace++ } elseif ($settings.Count) { $diagnostic[$type].Elsewhere++ } else { $diagnostic[$type].None++ }
    }
    $diagnosticRows = @(foreach ($type in $diagnostic.Keys) {
            $d = $diagnostic[$type]
            $coverage = & $percent $d.Workspace $d.Checked
            if ($d.Checked -ge 3 -and $coverage -lt 80) { & $find 'Low' 'Operational excellence' 'Monitoring' "$($d.Checked - $d.Workspace) of $($d.Checked) $(& $short $type) resources send no logs to Log Analytics" '' (& $short $type) 'Deploy diagnostic settings at scale with Azure Policy (the built-in DeployIfNotExists policies send each type''s logs to a workspace).' 'https://learn.microsoft.com/azure/azure-monitor/essentials/diagnostic-settings-policy' $type }
            [pscustomobject][ordered]@{ 'Resource type' = & $short $type; 'Checked' = $d.Checked; 'To Log Analytics' = $d.Workspace; 'Elsewhere only' = $d.Elsewhere; 'No setting' = $d.None; 'Not read' = $d.Unread; 'Coverage (%)' = $coverage; 'ResourceId' = '' }
        })
    $checked = [int](@($diagnosticRows | ForEach-Object Checked) + 0 | Measure-Object -Sum).Sum
    & $newSheet $tab 'Diagnostic settings' ([ordered]@{ 'Resource type' = 'mono'; 'Checked' = 'number'; 'To Log Analytics' = 'number'; 'Elsewhere only' = 'number'; 'No setting' = 'number'; 'Not read' = 'number'; 'Coverage (%)' = 'score' }) @($diagnosticRows | Sort-Object 'Coverage (%)') @('Resource type', 'Checked', 'To Log Analytics', 'Coverage (%)') 'The resources that have resource logs, by type: how many send them to a Log Analytics workspace.'
    $stats.DiagnosticCoverage = & $percent ([int](@($diagnosticRows | ForEach-Object 'To Log Analytics') + 0 | Measure-Object -Sum).Sum) $checked
    $workspaceRows = @(foreach ($w in & $rowsOf 'workspaces') { [pscustomobject][ordered]@{ 'Workspace' = [string]$w['name']; 'Pricing tier' = [string]$w['sku']; 'Retention (days)' = $w['retention']; 'Daily cap (GB)' = $(if ([double]$w['cap'] -ge 0 -and $null -ne $w['cap']) { $w['cap'] } else { $null }); 'Location' = [string]$w['location']; 'Subscription' = & $subName $w['subscriptionId']; 'Resource group' = [string]$w['resourceGroup']; 'ResourceId' = [string]$w['id'] } })
    & $newSheet $tab 'Log Analytics workspaces' ([ordered]@{ 'Workspace' = 'resource'; 'Pricing tier' = 'text'; 'Retention (days)' = 'number'; 'Daily cap (GB)' = 'number'; 'Location' = 'text'; 'Subscription' = 'text'; 'Resource group' = 'text' }) $workspaceRows @('Workspace', 'Pricing tier', 'Retention (days)', 'Location') "$($workspaceRows.Count) workspace(s) in $(@($workspaceRows | ForEach-Object Location | Select-Object -Unique).Count) region(s): fewer workspaces make queries, access and cost simpler (Invoke-AACLogAnalyticsWorkspaceAssessment goes deeper)."
    $stats.Workspaces = $workspaceRows.Count

    # Monitoring: Service Health alerts per subscription, and alert rules that tell no one.
    $actionCount = {
        param($Actions)
        if ($Actions -is [System.Collections.IDictionary]) { @(& $list $Actions['actionGroups']).Count + @(& $list $Actions['actionGroupId']).Count } else { @(& $list $Actions).Count }
    }
    $monitor = @{}
    foreach ($sub in $subscriptionNames.Keys) { $monitor[$sub] = @{ ServiceHealth = 0; Activity = 0; Metric = 0; Log = 0; Silent = 0 } }
    $silentRows = [System.Collections.Generic.List[object]]::new()
    foreach ($a in & $rowsOf 'alerts') {
        $type = [string]$a['type']
        $covers = @(@([string]$a['subscriptionId']) + @(& $list $a['scopes'] | ForEach-Object { & $subOf $_ }) | Where-Object { $_ -and $monitor.Contains($_) } | Select-Object -Unique)
        $serviceHealth = $type -like '*activitylogalerts' -and (ConvertTo-Json -InputObject $a['condition'] -Depth 10 -Compress) -match 'ServiceHealth'
        foreach ($sub in $covers) {
            if ($serviceHealth) { $monitor[$sub].ServiceHealth++ } elseif ($type -like '*activitylogalerts') { $monitor[$sub].Activity++ } elseif ($type -like '*metricalerts') { $monitor[$sub].Metric++ } else { $monitor[$sub].Log++ }
        }
        if ([string]$a['enabled'] -ne 'False' -and -not (& $actionCount $a['actions'])) {
            foreach ($sub in $covers | Select-Object -First 1) { $monitor[$sub].Silent++ }
            $silentRows.Add([pscustomobject][ordered]@{ 'Alert rule' = [string]$a['name']; 'Kind' = $(if ($serviceHealth) { 'Service Health' } elseif ($type -like '*activitylogalerts') { 'Activity log' } elseif ($type -like '*metricalerts') { 'Metric' } else { 'Log search' }); 'Subscription' = & $subName $a['subscriptionId']; 'Resource group' = [string]$a['resourceGroup']; 'ResourceId' = [string]$a['id'] })
            & $find 'Low' 'Operational excellence' 'Monitoring' 'Alert rule with no action group - it fires, and tells no one' ([string]$a['id']) ([string]$a['name']) 'Add an action group (email, Teams, ITSM or a webhook to the on-call tool), or delete the rule.' 'https://learn.microsoft.com/azure/azure-monitor/alerts/action-groups'
        }
    }
    $monitorRows = @(foreach ($sub in $monitor.Keys) {
            $x = $monitor[$sub]
            if (-not $x.ServiceHealth) { & $find 'Medium' 'Operational excellence' 'Monitoring' 'No Service Health alert: Azure outages, planned maintenance and retirements affecting the subscription reach no one' "/subscriptions/$sub" (& $subName $sub) 'Create a Service Health alert (service issues, planned maintenance, health advisories, security advisories) with an action group, for every subscription - Azure Policy can deploy it.' 'https://learn.microsoft.com/azure/service-health/alerts-activity-log-service-notifications-portal' 'subscription' }
            [pscustomobject][ordered]@{ 'Subscription' = & $subName $sub; 'Service Health alerts' = $x.ServiceHealth; 'Activity log alerts' = $x.Activity; 'Metric alerts' = $x.Metric; 'Log search alerts' = $x.Log; 'Without action group' = $x.Silent; 'Action groups' = @(& $rowsOf 'actionGroups' | Where-Object { [string]$_['subscriptionId'] -eq $sub }).Count; 'ResourceId' = "/subscriptions/$sub" }
        })
    & $newSheet $tab 'Monitoring' ([ordered]@{ 'Subscription' = 'text'; 'Service Health alerts' = 'number'; 'Activity log alerts' = 'number'; 'Metric alerts' = 'number'; 'Log search alerts' = 'number'; 'Without action group' = 'number'; 'Action groups' = 'number' }) @($monitorRows | Sort-Object 'Service Health alerts', Subscription) @('Subscription', 'Service Health alerts', 'Metric alerts', 'Without action group') ''
    & $newSheet $tab 'Alert rules without action group' ([ordered]@{ 'Alert rule' = 'resource'; 'Kind' = 'badge'; 'Subscription' = 'text'; 'Resource group' = 'text' }) $silentRows.ToArray() @('Alert rule', 'Kind', 'Subscription') ''
    $stats.SubscriptionsWithoutServiceHealth = @($monitorRows | Where-Object { -not $_.'Service Health alerts' }).Count

    # Patch compliance (Update Manager) and Azure Arc servers.
    $assessment = @{}
    foreach ($p in & $rowsOf 'patches') { $assessment[[string]$p['machine']] = $p }
    $arcRows = @(& $rowsOf 'arc')
    $machines = @(@($Resource | Where-Object { (& $lower $_['type']) -eq 'microsoft.compute/virtualmachines' } | ForEach-Object { @{ Id = & $lower $_['id']; Name = [string]$_['name']; Kind = 'Azure VM'; Sub = & $lower $_['subscriptionId']; Group = [string]$_['resourceGroup'] } }) +
        @($arcRows | ForEach-Object { @{ Id = [string]$_['id']; Name = [string]$_['name']; Kind = 'Arc server'; Sub = [string]$_['subscriptionId']; Group = [string]$_['resourceGroup'] } }))
    $unassessed = @{}
    $patchRows = @(foreach ($machine in $machines) {
            $p = $assessment[$machine.Id]
            $last = if ($p) { & $date $p['last'] } else { $null }
            $status = if (-not $p) { 'Not assessed' } elseif ($last -and ($Now - $last).TotalDays -gt 7) { 'Assessment stale' } elseif ([int]$p['critical'] + [int]$p['security']) { 'Missing updates' } elseif ([int]$p['other']) { 'Updates available' } else { 'Up to date' }
            if ($status -eq 'Missing updates') { & $find 'Medium' 'Security' 'Update Manager' "$([int]$p['critical']) critical and $([int]$p['security']) security update(s) missing" $machine.Id $machine.Name 'Install them with an Update Manager maintenance configuration (scheduled patching), and keep periodic assessment on.' 'https://learn.microsoft.com/azure/update-manager/overview' }
            if ($status -in 'Not assessed', 'Assessment stale') { $unassessed[$machine.Sub] = 1 + [int]$unassessed[$machine.Sub] }
            [pscustomobject][ordered]@{ 'Machine' = $machine.Name; 'Kind' = $machine.Kind; 'Status' = $status; 'OS' = $(if ($p) { [string]$p['os'] } else { '' }); 'Critical' = $(if ($p) { [int]$p['critical'] } else { $null }); 'Security' = $(if ($p) { [int]$p['security'] } else { $null }); 'Other' = $(if ($p) { [int]$p['other'] } else { $null }); 'Reboot pending' = $(if ($p) { [string]$p['reboot'] } else { '' }); 'Last assessed' = & $day $last; 'Subscription' = & $subName $machine.Sub; 'Resource group' = $machine.Group; 'ResourceId' = $machine.Id }
        })
    foreach ($sub in $unassessed.Keys) { & $find 'Low' 'Operational excellence' 'Update Manager' "$($unassessed[$sub]) machine(s) with no recent patch assessment" "/subscriptions/$sub" (& $subName $sub) 'Turn on periodic assessment (Azure Policy: Configure periodic checking for missing system updates) so missing updates are known.' 'https://learn.microsoft.com/azure/update-manager/assessment-options' 'subscription' }
    & $newSheet $tab 'Patch compliance' ([ordered]@{ 'Machine' = 'resource'; 'Kind' = 'badge'; 'Status' = 'badge'; 'OS' = 'text'; 'Critical' = 'number'; 'Security' = 'number'; 'Other' = 'number'; 'Reboot pending' = 'text'; 'Last assessed' = 'text'; 'Subscription' = 'text'; 'Resource group' = 'text' }) `
        @($patchRows | Sort-Object Status, Machine) @('Machine', 'Kind', 'Status', 'Critical', 'Security') 'Each Azure VM and Arc server: the updates Update Manager''s latest assessment found missing.'
    $stats.MachinesMissingUpdates = @($patchRows | Where-Object Status -EQ 'Missing updates').Count
    $arcSheet = @(foreach ($a in $arcRows) {
            $changed = & $date $a['lastChange']
            if ([string]$a['status'] -in 'Disconnected', 'Expired') { & $find 'Medium' 'Operational excellence' 'Azure Arc' "Arc server $([string]$a['status'].ToLowerInvariant())$(if ($changed) { " since $(& $day $changed)" })" ([string]$a['id']) ([string]$a['name']) 'Check the machine and its Connected Machine agent (azcmagent show): a disconnected server gets no policy, patching or Defender coverage; an expired one must be onboarded again.' 'https://learn.microsoft.com/azure/azure-arc/servers/troubleshoot-agent-onboard' }
            [pscustomobject][ordered]@{ 'Server' = [string]$a['name']; 'Status' = [string]$a['status']; 'Agent version' = [string]$a['agent']; 'OS' = [string]$a['os']; 'Since' = & $day $changed; 'Location' = [string]$a['location']; 'Subscription' = & $subName $a['subscriptionId']; 'Resource group' = [string]$a['resourceGroup']; 'ResourceId' = [string]$a['id'] }
        })
    & $newSheet $tab 'Arc servers' ([ordered]@{ 'Server' = 'resource'; 'Status' = 'badge'; 'Agent version' = 'text'; 'OS' = 'text'; 'Since' = 'text'; 'Location' = 'text'; 'Subscription' = 'text'; 'Resource group' = 'text' }) @($arcSheet | Sort-Object Status, Server) @('Server', 'Status', 'Agent version', 'Since') ''

    # Locks on production subscriptions and resource groups.
    $locksAt = @{}
    $locksRead = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($sub in @(if ($Asked.Contains('Lock')) { $Asked['Lock'] })) {
        $items = & $armOf 'Lock' $sub
        if ($null -eq $items) { continue }
        [void]$locksRead.Add($sub)
        foreach ($l in @($items | Where-Object { $_ })) { $scope = (& $lower (& $m $l 'id')) -replace '/providers/microsoft\.authorization/locks/[^/]+$', ''; if (-not $locksAt.Contains($scope)) { $locksAt[$scope] = [System.Collections.Generic.List[string]]::new() }; $locksAt[$scope].Add([string](& $m $l 'properties.level')) }
    }
    $lockRows = @(
        foreach ($sub in $productionSubs) {
            $scope = "/subscriptions/$sub"
            $level = if (-not $locksRead.Contains($sub)) { 'Not read' } elseif ($locksAt.Contains($scope)) { ($locksAt[$scope] | Select-Object -Unique) -join ', ' } else { 'None' }
            if ($level -eq 'None') { & $find 'Medium' 'Reliability' 'Locks' 'Production subscription with no lock' $scope (& $subName $sub) 'Put a CanNotDelete lock on its production resource groups (or the subscription), so one mistaken delete can''t remove production.' 'https://learn.microsoft.com/azure/azure-resource-manager/management/lock-resources' 'subscription' }
            [pscustomobject][ordered]@{ 'Scope' = 'Subscription'; 'Name' = & $subName $sub; 'Subscription' = & $subName $sub; 'Lock' = $level; 'Covered by' = $(if ($level -notin 'None', 'Not read') { 'Itself' } else { '' }); 'ResourceId' = $scope }
        }
        foreach ($groupId in $productionGroups) {
            $sub = & $subOf $groupId
            if ($productionSubs.Contains($sub) -and -not $locksAt.Contains($groupId) -and $locksAt.Contains("/subscriptions/$sub")) { $level = 'Inherited'; $by = 'Subscription' }
            elseif (-not $locksRead.Contains($sub)) { $level = 'Not read'; $by = '' }
            elseif ($locksAt.Contains($groupId)) { $level = ($locksAt[$groupId] | Select-Object -Unique) -join ', '; $by = 'Itself' }
            elseif ($locksAt.Contains("/subscriptions/$sub")) { $level = 'Inherited'; $by = 'Subscription' }
            else { $level = 'None'; $by = '' }
            if ($level -eq 'None') { & $find 'Medium' 'Reliability' 'Locks' 'Production resource group with no lock' $groupId (& $groupOf $groupId) 'Add a CanNotDelete lock (Azure Policy can deploy one on every production resource group).' 'https://learn.microsoft.com/azure/azure-resource-manager/management/lock-resources' 'resource group' }
            [pscustomobject][ordered]@{ 'Scope' = 'Resource group'; 'Name' = & $groupOf $groupId; 'Subscription' = & $subName $sub; 'Lock' = $level; 'Covered by' = $by; 'ResourceId' = $groupId }
        }
    )
    if (-not $productionSubs.Count -and -not $productionGroups.Count) { $notices.Add('No production subscription or resource group was recognised (by name, or an Environment tag matching -ProductionPattern), so production locks and resilience aren''t judged as production.') }
    & $newSheet $tab 'Production locks' ([ordered]@{ 'Scope' = 'badge'; 'Name' = 'text'; 'Subscription' = 'text'; 'Lock' = 'badge'; 'Covered by' = 'text' }) @($lockRows | Sort-Object Lock, Scope, Name) @('Scope', 'Name', 'Lock', 'Covered by') 'Production subscriptions and resource groups (by name, or an Environment tag, matching -ProductionPattern) and the lock that protects each.'

    # The Activity Log: changes and failures over -ActivityDays.
    $activityRows = [System.Collections.Generic.List[object]]::new()
    $failedRows = [System.Collections.Generic.List[object]]::new()
    foreach ($sub in @(if ($Asked.Contains('Activity')) { $Asked['Activity'] })) {
        $events = & $armOf 'Activity' $sub
        if ($null -eq $events) { $activityRows.Add([pscustomobject][ordered]@{ 'Subscription' = & $subName $sub; 'Changes' = $null; 'Deletes' = $null; 'Failed' = $null; 'Failed deployments' = $null; 'People and identities' = $null; 'Most changes by' = 'Not read'; 'ResourceId' = "/subscriptions/$sub" }); continue }
        $admin = @($events | Where-Object { $_ -and [string](& $m $_ 'category.value') -eq 'Administrative' })
        $writes = @($admin | Where-Object { [string](& $m $_ 'operationName.value') -match '/(write|delete|action)$' })
        $deployments = @{}
        foreach ($e in $admin | Where-Object { [string](& $m $_ 'operationName.value') -match '(?i)^Microsoft\.Resources/deployments/write$' -and [string](& $m $_ 'status.value') -eq 'Failed' }) {
            $key = [string](& $m $e 'correlationId'); if (-not $key) { $key = [string](& $m $e 'resourceId') }
            if ($deployments.Contains($key)) { continue }
            $deployments[$key] = $e
            $failedRows.Add([pscustomobject][ordered]@{ 'When' = (([string](& $m $e 'eventTimestamp') -replace 'T', ' ') -replace '\.\d+Z?$|Z$', ''); 'Deployment' = & $leaf (& $m $e 'resourceId'); 'Resource group' = [string](& $m $e 'resourceGroupName'); 'Subscription' = & $subName $sub; 'By' = [string](& $m $e 'caller'); 'ResourceId' = [string](& $m $e 'resourceId') })
        }
        $callers = @($writes | Group-Object { [string](& $m $_ 'caller') } | Sort-Object Count -Descending)
        if ($deployments.Count) { & $find 'Low' 'Operational excellence' 'Activity Log' "$($deployments.Count) failed deployment(s) in $ActivityDays days" "/subscriptions/$sub" (& $subName $sub) 'Open each failed deployment (resource group > Deployments) for its error; repeated failures point at a template, a policy deny or a quota.' 'https://learn.microsoft.com/azure/azure-resource-manager/troubleshooting/find-error-code' 'subscription' }
        $activityRows.Add([pscustomobject][ordered]@{
                'Subscription' = & $subName $sub; 'Changes' = $writes.Count; 'Deletes' = @($writes | Where-Object { [string](& $m $_ 'operationName.value') -match '/delete$' }).Count
                'Failed' = @($writes | Where-Object { [string](& $m $_ 'status.value') -eq 'Failed' } | ForEach-Object { & $m $_ 'correlationId' } | Select-Object -Unique).Count; 'Failed deployments' = $deployments.Count
                'People and identities' = $callers.Count; 'Most changes by' = $(if ($callers.Count) { "$($callers[0].Name) ($($callers[0].Count))" } else { '' }); 'ResourceId' = "/subscriptions/$sub"
            })
    }
    & $newSheet $tab 'Activity' ([ordered]@{ 'Subscription' = 'text'; 'Changes' = 'number'; 'Deletes' = 'number'; 'Failed' = 'number'; 'Failed deployments' = 'number'; 'People and identities' = 'number'; 'Most changes by' = 'text' }) @($activityRows | Sort-Object Changes -Descending) @('Subscription', 'Changes', 'Deletes', 'Failed', 'Failed deployments') "The Activity Log over $ActivityDays days (-ActivityDays): administrative changes (write, delete and action events), deletes, failures, failed deployments and who made the changes."
    & $newSheet $tab 'Failed deployments' ([ordered]@{ 'When' = 'text'; 'Deployment' = 'text'; 'Resource group' = 'text'; 'Subscription' = 'text'; 'By' = 'text' }) @($failedRows | Sort-Object When -Descending) @('When', 'Deployment', 'Resource group', 'By') ''
    $stats.FailedDeployments = $failedRows.Count

    # Retired and retiring SKUs and resource kinds.
    $deprecatedRows = @(foreach ($r in & $rowsOf 'deprecated') {
            $type = [string]$r['type']
            $what, $when, $todo = switch -Regex ($type) {
                '^microsoft\.network/publicipaddresses$' { 'Basic SKU public IP address', '2025-09-30', 'Upgrade to a Standard SKU public IP (the portal''s Upgrade, or the upgrade script).'; break }
                '^microsoft\.network/loadbalancers$' { 'Basic SKU load balancer', '2025-09-30', 'Upgrade to a Standard load balancer (the Basic to Standard upgrade script).'; break }
                '^microsoft\.compute/virtualmachines$' { if ($r['vhd']) { 'Unmanaged disks (VHDs in a storage account)', '2025-09-30', 'Convert the VM to managed disks (ConvertTo-AzVMManagedDisk, or the portal''s Migrate to managed disks).' } else { "Av1 VM size ($($r['size']))", '2024-08-31', 'Resize to a current size (Av2, B-series or D-series).' }; break }
                '^microsoft\.classic' { 'Classic (Azure Service Manager) resource', '2024-08-31', 'Migrate it to Azure Resource Manager - classic resources are retired and unsupported.'; break }
                '^microsoft\.network/virtualnetworkgateways$' { 'Basic SKU VPN gateway', '', 'Move to a VpnGw1AZ (or higher) SKU: Basic has no zone redundancy, BGP or more than 10 tunnels.'; break }
                '^microsoft\.network/applicationgateways$' { 'Application Gateway v1', '2026-04-28', 'Migrate to Application Gateway v2 (Standard_v2 or WAF_v2).'; break }
                '^microsoft\.dbformysql/servers$' { 'Azure Database for MySQL single server', '2024-09-16', 'Migrate to Azure Database for MySQL flexible server.'; break }
                '^microsoft\.dbforpostgresql/servers$' { 'Azure Database for PostgreSQL single server', '2025-03-28', 'Migrate to Azure Database for PostgreSQL flexible server.'; break }
                '^microsoft\.cache/redis$' { "Redis version $($r['redis'])", '', 'Upgrade the cache to Redis 6.'; break }
                default { 'Retired or retiring', '', 'Check Azure Updates for the retirement and its migration path.' }
            }
            $retired = $when -and (& $date $when) -lt $Now
            & $find $(if ($retired) { 'High' } else { 'Medium' }) 'Reliability' 'Deprecated SKUs' "$what$(if ($when) { " - $(if ($retired) { 'retired' } else { 'retiring' }) $when" })" ([string]$r['id']) ([string]$r['name']) $todo 'https://azure.microsoft.com/updates/?updateType=retirements'
            [pscustomobject][ordered]@{ 'Resource' = [string]$r['name']; 'Type' = & $short $type; 'What' = $what; 'Retires' = $when; 'Status' = $(if (-not $when) { 'Legacy' } elseif ($retired) { 'Retired' } else { 'Retiring' }); 'What to do' = $todo; 'Subscription' = & $subName $r['subscriptionId']; 'Resource group' = [string]$r['resourceGroup']; 'ResourceId' = [string]$r['id'] }
        })
    & $newSheet $tab 'Deprecated SKUs' ([ordered]@{ 'Resource' = 'resource'; 'Type' = 'mono'; 'What' = 'text'; 'Retires' = 'text'; 'Status' = 'badge'; 'What to do' = 'wide'; 'Subscription' = 'text'; 'Resource group' = 'text' }) @($deprecatedRows | Sort-Object Retires, What, Resource) @('Resource', 'What', 'Retires', 'Status') 'Resources on retired or retiring SKUs and kinds, found from their configuration (Advisor''s own retirement notices are on the Retirements sheet). The API versions templates use aren''t visible to a read of Azure: check them in your infrastructure code.'
    $stats.DeprecatedResources = $deprecatedRows.Count

    # Naming (the Cloud Adoption Framework's abbreviations) and owner tags.
    $prefixes = @{
        'microsoft.compute/virtualmachines' = 'vm'; 'microsoft.network/virtualnetworks' = 'vnet'; 'microsoft.network/networksecuritygroups' = 'nsg'; 'microsoft.network/publicipaddresses' = 'pip'
        'microsoft.network/networkinterfaces' = 'nic'; 'microsoft.network/loadbalancers' = 'lb[ie]?'; 'microsoft.network/applicationgateways' = 'agw'; 'microsoft.network/azurefirewalls' = 'afw'
        'microsoft.network/virtualnetworkgateways' = 'vgw'; 'microsoft.network/privateendpoints' = 'pep'; 'microsoft.network/routetables' = 'rt'; 'microsoft.network/bastionhosts' = 'bas'
        'microsoft.keyvault/vaults' = 'kv'; 'microsoft.storage/storageaccounts' = 'st'; 'microsoft.sql/servers' = 'sql'; 'microsoft.sql/servers/databases' = 'sqldb'; 'microsoft.web/sites' = 'app|func'
        'microsoft.web/serverfarms' = 'asp'; 'microsoft.containerservice/managedclusters' = 'aks'; 'microsoft.containerregistry/registries' = 'cr'; 'microsoft.operationalinsights/workspaces' = 'log'
        'microsoft.insights/components' = 'appi'; 'microsoft.documentdb/databaseaccounts' = 'cosmos'; 'microsoft.cache/redis' = 'redis'; 'microsoft.servicebus/namespaces' = 'sbns'
        'microsoft.eventhub/namespaces' = 'evhns'; 'microsoft.logic/workflows' = 'logic'; 'microsoft.datafactory/factories' = 'adf'; 'microsoft.recoveryservices/vaults' = 'rsv'
        'microsoft.automation/automationaccounts' = 'aa'; 'microsoft.managedidentity/userassignedidentities' = 'id'; 'microsoft.compute/disks' = 'disk|osdisk'; 'microsoft.app/containerapps' = 'ca'
        'microsoft.app/managedenvironments' = 'cae'; 'microsoft.dbforpostgresql/flexibleservers' = 'psql'; 'microsoft.dbformysql/flexibleservers' = 'mysql'; 'microsoft.apimanagement/service' = 'apim'
        'microsoft.cognitiveservices/accounts' = 'cog|oai|ais'; 'microsoft.search/searchservices' = 'srch'
    }
    $follows = {
        param([string] $Type, [string] $Name)
        if (-not $prefixes.Contains($Type)) { return $null }
        $p = $prefixes[$Type]
        # A prefix (vm-web-01, stcontosoprod - storage and registries allow no dashes) or a suffix (web-vm-01).
        $Name -match "(?i)^($p)([-_.0-9]|$)" -or ($Type -in 'microsoft.storage/storageaccounts', 'microsoft.containerregistry/registries' -and $Name -match "(?i)^($p)[a-z0-9]") -or $Name -match "(?i)[-_]($p)([-_]?[0-9]*)$"
    }
    $nameRows = @(foreach ($group in $Resource | Group-Object { & $lower $_['type'] }) {
            $named = @($group.Group | Where-Object { & $follows $group.Name ([string]$_['name']) })
            $owned = @($group.Group | Where-Object { & $tagValue $_['tags'] $OwnerTag })
            [pscustomobject][ordered]@{ 'Resource type' = & $short $group.Name; 'Resources' = $group.Count; 'CAF abbreviation' = $(if ($prefixes.Contains($group.Name)) { $prefixes[$group.Name] } else { '' }); 'Named to it' = $(if ($prefixes.Contains($group.Name)) { $named.Count } else { $null }); 'Naming (%)' = $(if ($prefixes.Contains($group.Name)) { & $percent $named.Count $group.Count } else { $null }); 'With an owner tag' = $owned.Count; 'Owner tag (%)' = & $percent $owned.Count $group.Count; 'ResourceId' = '' }
        })
    $groupsNamed = @($ResourceGroup | Where-Object { [string]$_['name'] -match '(?i)^rg[-_]|[-_]rg$' }).Count
    $nameRows += [pscustomobject][ordered]@{ 'Resource type' = 'resources/resourcegroups'; 'Resources' = @($ResourceGroup).Count; 'CAF abbreviation' = 'rg'; 'Named to it' = $groupsNamed; 'Naming (%)' = & $percent $groupsNamed @($ResourceGroup).Count; 'With an owner tag' = @($ResourceGroup | Where-Object { & $tagValue $_['tags'] $OwnerTag }).Count; 'Owner tag (%)' = & $percent @($ResourceGroup | Where-Object { & $tagValue $_['tags'] $OwnerTag }).Count @($ResourceGroup).Count; 'ResourceId' = '' }
    $checkedNames = @($nameRows | Where-Object { $null -ne $_.'Named to it' })
    $namingTotal = [int](@($checkedNames | ForEach-Object Resources) + 0 | Measure-Object -Sum).Sum
    $stats.NamingCoverage = & $percent ([int](@($checkedNames | ForEach-Object 'Named to it') + 0 | Measure-Object -Sum).Sum) $namingTotal
    $stats.OwnerTagCoverage = & $percent @($Resource | Where-Object { & $tagValue $_['tags'] $OwnerTag }).Count @($Resource).Count
    foreach ($group in $Resource | Group-Object { & $lower $_['subscriptionId'] }) {
        $owned = @($group.Group | Where-Object { & $tagValue $_['tags'] $OwnerTag }).Count
        $share = & $percent $owned $group.Count
        if ($group.Count -ge 5 -and $share -lt 80) { & $find 'Low' 'Operational excellence' 'Tags' "$($group.Count - $owned) of $($group.Count) resources have no owner tag ($share% tagged)" "/subscriptions/$($group.Name)" (& $subName $group.Name) "Tag every resource with its owner ($($OwnerTag -join ', ') - -OwnerTag), or inherit it from the resource group with Azure Policy, so someone answers for each resource." 'https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-tagging' 'subscription' }
    }
    if ($namingTotal -ge 10 -and $stats.NamingCoverage -lt 50) { & $find 'Info' 'Operational excellence' 'Naming' "$($stats.NamingCoverage)% of resources follow the Cloud Adoption Framework abbreviations" '' 'Tenant' 'Agree a naming convention (the CAF''s abbreviations are a good start) and enforce it on new resources with Azure Policy.' 'https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations' 'tenant' }
    & $newSheet $tab 'Naming and tags' ([ordered]@{ 'Resource type' = 'mono'; 'Resources' = 'number'; 'CAF abbreviation' = 'mono'; 'Named to it' = 'number'; 'Naming (%)' = 'score'; 'With an owner tag' = 'number'; 'Owner tag (%)' = 'score' }) @($nameRows | Sort-Object Resources -Descending) @('Resource type', 'Resources', 'Naming (%)', 'Owner tag (%)') "Each resource type: how many names use the Cloud Adoption Framework's abbreviation (as a prefix or a suffix), and how many resources carry an owner tag ($($OwnerTag -join ', ') - -OwnerTag)."

    # ==================================================================================================================
    # Service delivery
    # ==================================================================================================================
    $tab = 'Service delivery'
    $offerOf = {
        param([string] $QuotaId)
        switch -Regex ($QuotaId) {
            '(?i)^EnterpriseAgreement' { 'Enterprise Agreement'; break }
            '(?i)MSDNDevTest' { 'Pay-as-you-go Dev/Test'; break }
            '(?i)^MSDN|VisualStudio' { 'Visual Studio subscriber (Dev/Test)'; break }
            '(?i)^PayAsYouGo' { 'Pay-as-you-go or Microsoft Customer Agreement'; break }
            '(?i)CSP' { 'Cloud Solution Provider (CSP)'; break }
            '(?i)Sponsored' { 'Sponsorship'; break }
            '(?i)FreeTrial' { 'Free trial'; break }
            '(?i)Student' { 'Azure for Students'; break }
            '(?i)Internal' { 'Microsoft internal'; break }
            default { if ($QuotaId) { $QuotaId } else { 'Unknown' } }
        }
    }
    $ticketsSheet = @($Sheet | Where-Object Sheet -EQ 'Support tickets') | Select-Object -First 1
    $planBySub = @{}
    foreach ($t in @(@(if ($ticketsSheet) { $ticketsSheet.Rows }) | Sort-Object Created -Descending)) { if (-not $planBySub.Contains($t.Subscription) -and $t.'Support plan') { $planBySub[$t.Subscription] = $t.'Support plan' } }
    $productionResources = @{}
    foreach ($r in $Resource) { if (& $resourceIsProduction ([string]$r['id']) $r['tags']) { $sub = & $lower $r['subscriptionId']; $productionResources[$sub] = 1 + [int]$productionResources[$sub] } }
    $offerRows = @(foreach ($row in $Subscription | Sort-Object { [string]$_['name'] }) {
            $sub = & $lower $row['subscriptionId']
            $offer = & $offerOf ([string]$row['quotaId'])
            if ($offer -match 'Dev/Test|Visual Studio|Free trial|Students' -and [int]$productionResources[$sub]) { & $find 'Medium' 'Governance' 'Subscription offers' "Production resources on a $offer subscription" "/subscriptions/$sub" ([string]$row['name']) 'Move production to an Enterprise Agreement or Customer Agreement subscription: Dev/Test and Visual Studio offers carry no SLA and are licensed for development and test only.' 'https://azure.microsoft.com/pricing/offers/dev-test/' 'subscription' }
            [pscustomobject][ordered]@{ 'Subscription' = [string]$row['name']; 'Offer' = $offer; 'Quota ID' = [string]$row['quotaId']; 'State' = [string]$row['state']; 'Spending limit' = [string]$row['spendingLimit']; 'Support plan' = $(if ($planBySub.Contains([string]$row['name'])) { $planBySub[[string]$row['name']] } else { 'Unknown (no recent ticket)' }); 'Production resources' = [int]$productionResources[$sub]; 'ResourceId' = "/subscriptions/$sub" }
        })
    & $newSheet $tab 'Subscription offers' ([ordered]@{ 'Subscription' = 'text'; 'Offer' = 'badge'; 'Quota ID' = 'mono'; 'State' = 'badge'; 'Spending limit' = 'text'; 'Support plan' = 'text'; 'Production resources' = 'number' }) $offerRows @('Subscription', 'Offer', 'State', 'Support plan') 'Each subscription''s offer (from its quota ID - pay-as-you-go and Customer Agreement subscriptions share one) and the support plan named on its latest support ticket.'

    # Reservations and savings plans: how much of what was bought is used.
    $utilisation = { param($Item, [int] $Days) $a = @(& $list (& $m $Item 'properties.utilization.aggregates') | Where-Object { [int](& $m $_ 'grain') -eq $Days }) | Select-Object -First 1; if ($a) { [Math]::Round([double](& $m $a 'value'), 1) } else { $null } }
    $benefitRows = {
        param([string] $Kind, [object[]] $Items)
        foreach ($i in @($Items | Where-Object { $_ })) {
            $p = & $m $i 'properties'
            $expires = & $date $(if (& $m $p 'expiryDateTime') { & $m $p 'expiryDateTime' } else { & $m $p 'expiryDate' })
            $used30 = & $utilisation $i 30; $used7 = & $utilisation $i 7
            $state = [string]$(@((& $m $p 'displayProvisioningState'), (& $m $p 'provisioningState')) | Where-Object { $_ } | Select-Object -First 1)
            $name = [string]$(@((& $m $p 'displayName'), (& $m $i 'name')) | Where-Object { $_ } | Select-Object -First 1)
            $days = if ($expires) { [int][Math]::Floor(($expires - $Now).TotalDays) } else { $null }
            if ($state -notmatch '(?i)expired|cancel') {
                if ($null -ne $used30 -and $used30 -lt 80) { & $find 'Medium' 'Cost' $Kind "$Kind '$name' is $used30% used (30 days)" ([string](& $m $i 'id')) $name $(if ($Kind -eq 'Reservations') { 'Change its scope to shared (or a management group) so more resources can use it, or exchange it for what you run.' } else { 'Widen its scope to shared, or size the next commitment to what is used.' }) 'https://learn.microsoft.com/azure/cost-management-billing/reservations/manage-reserved-vm-instance' 'benefit' }
                if ($null -ne $days -and $days -ge 0 -and $days -le 60 -and [string](& $m $p 'renew') -ne 'True') { & $find 'Low' 'Cost' $Kind "$Kind '$name' expires in $days days and won't renew" ([string](& $m $i 'id')) $name 'Turn on renewal (or buy its replacement) before it expires, or the resources it covers go back to pay-as-you-go prices.' 'https://learn.microsoft.com/azure/cost-management-billing/reservations/reservation-renew' 'benefit' }
            }
            [pscustomobject][ordered]@{
                'Name' = $name; 'SKU' = [string]$(@((& $m $i 'sku.name'), (& $m $p 'reservedResourceType')) | Where-Object { $_ } | Select-Object -First 1)
                'Quantity or commitment' = $(if (& $m $p 'commitment') { "$(& $m $p 'commitment.amount') $(& $m $p 'commitment.currencyCode') / $(& $m $p 'commitment.grain')" } else { [string](& $m $p 'quantity') })
                'Term' = [string](& $m $p 'term'); 'Scope' = [string](& $m $p 'appliedScopeType'); 'Expires' = & $day $expires; 'Days left' = $days; 'Renews' = [string](& $m $p 'renew')
                'Used 7 days (%)' = $used7; 'Used 30 days (%)' = $used30; 'State' = $state; 'ResourceId' = [string](& $m $i 'id')
            }
        }
    }
    $benefitTypes = [ordered]@{ 'Name' = 'text'; 'SKU' = 'text'; 'Quantity or commitment' = 'text'; 'Term' = 'text'; 'Scope' = 'text'; 'Expires' = 'text'; 'Days left' = 'number'; 'Renews' = 'text'; 'Used 7 days (%)' = 'score'; 'Used 30 days (%)' = 'score'; 'State' = 'badge' }
    $reservationItems = & $armOf 'Reservation' 'all'
    $savingsItems = & $armOf 'SavingsPlan' 'all'
    $reservationRows = @(& $benefitRows 'Reservations' @($reservationItems))
    $savingsRows = @(& $benefitRows 'Savings plans' @($savingsItems))
    & $newSheet $tab 'Reservations' $benefitTypes @($reservationRows | Sort-Object 'Used 30 days (%)') @('Name', 'SKU', 'Expires', 'Used 30 days (%)') $(if ($null -eq $reservationItems -and (& $wasAsked 'Reservation' 'all')) { 'Couldn''t be read: listing reservations needs Reservations Reader (or a billing role).' } else { 'The reservations the account can see, and how much of each is used.' })
    & $newSheet $tab 'Savings plans' $benefitTypes @($savingsRows | Sort-Object 'Used 30 days (%)') @('Name', 'Quantity or commitment', 'Expires', 'Used 30 days (%)') $(if ($null -eq $savingsItems -and (& $wasAsked 'SavingsPlan' 'all')) { 'Couldn''t be read: listing savings plans needs Savings plan Reader (or a billing role).' } else { 'The savings plans the account can see, and how much of each commitment is used.' })
    $used = @(@($reservationRows) + @($savingsRows) | Where-Object { $null -ne $_.'Used 30 days (%)' })
    $stats.BenefitUtilisation = if ($used.Count) { [Math]::Round((@($used | ForEach-Object 'Used 30 days (%)') | Measure-Object -Average).Average, 1) } else { $null }

    # Quota headroom: the quotas 80% or more used.
    $quotaSheet = @($Sheet | Where-Object Sheet -EQ 'Quotas') | Select-Object -First 1
    $headroomRows = @(foreach ($q in @(if ($quotaSheet) { $quotaSheet.Rows | Where-Object { $_.'Used (%)' -ge 80 } })) {
            & $find $(if ($q.'Used (%)' -ge 95) { 'High' } else { 'Medium' }) 'Performance' 'Quotas' "$($q.Quota) in $($q.Location): $($q.'Used (%)')% used ($($q.Used) of $($q.Limit))" $q.ResourceId $q.Subscription 'Request a quota increase (Quotas in the portal) before the next deployment or scale-out fails.' 'https://learn.microsoft.com/azure/quotas/per-vm-quota-requests' 'subscription'
            [pscustomobject][ordered]@{ 'Subscription' = $q.Subscription; 'Location' = $q.Location; 'Quota' = $q.Quota; 'Used' = $q.Used; 'Limit' = $q.Limit; 'Used (%)' = $q.'Used (%)'; 'Headroom' = $q.Limit - $q.Used; 'ResourceId' = $q.ResourceId }
        })
    & $newSheet $tab 'Quota headroom' ([ordered]@{ 'Subscription' = 'text'; 'Location' = 'text'; 'Quota' = 'text'; 'Used' = 'number'; 'Limit' = 'number'; 'Used (%)' = 'number'; 'Headroom' = 'number' }) @($headroomRows | Sort-Object 'Used (%)' -Descending) @('Subscription', 'Location', 'Quota', 'Used (%)', 'Headroom') $(if ($quotaSheet) { 'Compute quotas 80% or more used.' } else { 'Quotas weren''t read: add -QuotaUsage (or -Full).' })

    # Month-on-month cost, per subscription.
    $trendTypes = [ordered]@{ 'Subscription' = 'text' }
    $months = @(for ($i = 5; $i -ge 0; $i--) { $Now.AddMonths(-$i).ToString('yyyy-MM') })
    foreach ($month in $months) { $trendTypes[$(if ($month -eq $months[-1]) { "$month (to date)" } else { $month })] = 'money' }
    $trendTypes['Change (%)'] = 'number'; $trendTypes['Currency'] = 'text'
    $trendRows = @(foreach ($sub in $CostTrend.Keys) {
            $byMonth = @{}; $currency = ''
            foreach ($row in @($CostTrend[$sub] | Where-Object { $_ })) {
                $month = & $m $row 'BillingMonth'
                $key = if ($month -is [datetime]) { $month.ToString('yyyy-MM') } elseif ([string]$month -match '^(\d{4})-?(\d{2})') { "$($Matches[1])-$($Matches[2])" } else { '' }
                $byMonth[$key] = [double]$byMonth[$key] + [double](& $m $row 'Cost')
                if (& $m $row 'Currency') { $currency = [string](& $m $row 'Currency') }
            }
            $item = [ordered]@{ 'Subscription' = & $subName $sub }
            foreach ($month in $months) { $item[$(if ($month -eq $months[-1]) { "$month (to date)" } else { $month })] = $(if ($byMonth.Contains($month)) { [Math]::Round($byMonth[$month], 2) } else { $null }) }
            $last = [double]$byMonth[$months[-2]]; $before = [double]$byMonth[$months[-3]]
            $item['Change (%)'] = if ($before) { [Math]::Round(($last - $before) / $before * 100, 1) } else { $null }
            $item['Currency'] = $currency
            $item['ResourceId'] = "/subscriptions/$sub"
            if ($null -ne $item['Change (%)'] -and $item['Change (%)'] -gt 20 -and ($last - $before) -gt 100) { & $find 'Low' 'Cost' 'Cost trend' "Cost up $($item['Change (%)'])% from $($months[-3]) to $($months[-2])" "/subscriptions/$sub" (& $subName $sub) 'Find what grew (Cost by service and Top cost resources, or Cost analysis grouped by resource) and confirm it was planned.' 'https://learn.microsoft.com/azure/cost-management-billing/costs/quick-acm-cost-analysis' 'subscription' }
            [pscustomobject]$item
        })
    & $newSheet $tab 'Cost trend' $trendTypes @($trendRows | Sort-Object Subscription) @('Subscription', $months[-2], 'Change (%)') $(if ($CostRead) { 'Actual cost per month over six months; the change is the last full month against the one before.' } else { 'Cost wasn''t read: add -IncludeCost (or -Full) - it needs Cost Management Reader.' })

    # The ownership map: subscription > resource group > owner.
    $allSheet = @($Sheet | Where-Object Sheet -EQ 'All resources') | Select-Object -First 1
    $costByGroup = @{}
    if ($allSheet -and $allSheet.Columns -contains 'Cost (last month)') { foreach ($row in $allSheet.Rows) { $key = "$(& $subOf $row.ResourceId)|$((& $groupOf $row.ResourceId).ToLowerInvariant())"; if ($null -ne $row.'Cost (last month)') { $costByGroup[$key] = [double]$costByGroup[$key] + [double]$row.'Cost (last month)' } } }
    $resourcesByGroup = @{}
    foreach ($r in $Resource) { $key = "$(& $lower $r['subscriptionId'])|$(& $lower $r['resourceGroup'])"; if (-not $resourcesByGroup.Contains($key)) { $resourcesByGroup[$key] = [System.Collections.Generic.List[object]]::new() }; $resourcesByGroup[$key].Add($r) }
    $ownershipRows = @(foreach ($g in $ResourceGroup | Sort-Object { & $subName $_['subscriptionId'] }, { [string]$_['name'] }) {
            $sub = & $lower $g['subscriptionId']; $key = "$sub|$(& $lower $g['name'])"
            $members = @(if ($resourcesByGroup.Contains($key)) { $resourcesByGroup[$key] })
            $tagged = @($members | ForEach-Object { & $tagValue $_['tags'] $OwnerTag } | Where-Object { $_ })
            $groupOwner = & $tagValue $g['tags'] $OwnerTag
            [pscustomobject][ordered]@{
                'Subscription' = & $subName $sub; 'Resource group' = [string]$g['name']; 'Owner (group tag)' = $groupOwner
                'Owners on resources' = (@($tagged | Group-Object | Sort-Object Count -Descending | Select-Object -First 3 | ForEach-Object Name) -join ', '); 'Resources' = $members.Count
                'Owner tag (%)' = & $percent $tagged.Count $members.Count; 'Subscription owners' = (@(if ($ownersBySub.Contains($sub)) { $ownersBySub[$sub] | ForEach-Object Name | Select-Object -Unique -First 5 }) -join ', ')
                'Cost (last month)' = $(if ($costByGroup.Contains($key)) { [Math]::Round($costByGroup[$key], 2) } else { $null }); 'Owner known' = $(if ($groupOwner -or $tagged.Count) { 'Yes' } else { 'No' }); 'ResourceId' = [string]$g['id']
            }
        })
    & $newSheet $tab 'Ownership map' ([ordered]@{ 'Subscription' = 'text'; 'Resource group' = 'resource'; 'Owner (group tag)' = 'text'; 'Owners on resources' = 'text'; 'Resources' = 'number'; 'Owner tag (%)' = 'score'; 'Subscription owners' = 'text'; 'Cost (last month)' = 'money'; 'Owner known' = 'badge' }) `
        $ownershipRows @('Subscription', 'Resource group', 'Owner (group tag)', 'Owners on resources') "Who answers for what: each resource group's owner tag ($($OwnerTag -join ', ')), the owners tagged on its resources, the subscription's Owners (Azure RBAC) and its cost with -IncludeCost."
    $stats.GroupsWithoutOwner = @($ownershipRows | Where-Object { $_.'Owner known' -eq 'No' -and $_.Resources }).Count

    @{ Sheets = $sheets.ToArray(); Findings = $findings.ToArray(); Stats = $stats; Notices = $notices.ToArray() }
}
