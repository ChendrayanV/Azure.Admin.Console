function ConvertTo-AACManagedIdentity {
    <#
    .SYNOPSIS
        Builds Get-AACManagedIdentity's list (AAC.ManagedIdentity): every
        system- and user-assigned managed identity in scope - what it belongs
        to, what it is attached to, its Azure roles, its API permissions
        (Microsoft Graph and other APIs) and federated credentials - with
        findings for the access that matters.
    .DESCRIPTION
        No Azure calls.
          -Read          Invoke-AACGraphBatch's result: userIdentities,
                         systemIdentities (resources with a system-assigned
                         identity, and the user-assigned ones they also use),
                         attached (every resource's user-assigned identities
                         and AKS kubelet identity, tenant-wide),
                         policyIdentities (policy assignments with an
                         identity), roleAssignments (service principals'),
                         roleDefinitions
          -Federated     user-assigned identity resource ID (lower case) ->
                         its federated credentials (ARM items), when read
          -Permission    principal ID (lower case) -> its app role
                         assignments (resourceId, resourceDisplayName,
                         appRoleId), when read; $null when Entra ID was not
                         read
          -ApiRole       resource service principal ID (lower case) ->
                         @{ Name; Roles = app role ID (lower case) -> value }
          -InScope       subscription IDs (lower case) in scope; empty for
                         every subscription (policy assignments above a
                         subscription always count)
        Findings:
          High    an API permission that can take over the tenant
                  (RoleManagement.ReadWrite.Directory,
                  AppRoleAssignment.ReadWrite.All, Application.ReadWrite.All);
                  Owner, User Access Administrator or Role Based Access
                  Control Administrator on a subscription or above
          Medium  another privileged API permission (Directory.ReadWrite.All,
                  Mail.Send, Sites.FullControl.All...); Contributor on a
                  subscription or above; a user-assigned identity shared by
                  more than -SharedLimit resources with privileged access;
                  one attached to nothing that still holds access; a
                  federated credential on an identity with privileged access
          Low     a user-assigned identity attached to nothing, without
                  access; a resource with both a system-assigned and
                  user-assigned identities
        Returns @{ Identities; Access (one row per role or permission);
        Notices; Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Read,

        [hashtable] $Federated = @{},

        [hashtable] $Permission,

        [hashtable] $ApiRole = @{},

        [hashtable] $SubscriptionName = @{},

        [string[]] $InScope = @(),

        [ValidateRange(1, 1000)]
        [int] $SharedLimit = 10
    )

    $get = ${function:Get-AACMember}
    $text = { param($Object, [string] $Path) $v = & $get $Object $Path; if ($null -eq $v) { '' } else { [string]$v } }
    $lower = { param($Object, [string] $Path) (& $text $Object $Path).ToLowerInvariant() }
    $list = { param($Item) @(if ($Item -is [System.Collections.IEnumerable] -and $Item -isnot [string] -and $Item -isnot [System.Collections.IDictionary]) { $Item } elseif ($null -ne $Item) { , $Item }) | Where-Object { $null -ne $_ -and '' -ne $_ } }
    $rowsOf = { param([string] $Name) @(if ($Read.Rows -and $Read.Rows.Contains($Name)) { $Read.Rows[$Name] | Where-Object { $null -ne $_ } }) }
    $keysOf = { param($Bag) @(if ($Bag -is [System.Collections.IDictionary]) { $Bag.Keys | ForEach-Object { ([string]$_).ToLowerInvariant() } } elseif ($Bag -is [psobject] -and $Bag -isnot [string]) { $Bag.PSObject.Properties.Name | ForEach-Object { ([string]$_).ToLowerInvariant() } }) }
    $leaf = { param([string] $Id) ($Id -split '/')[-1] }
    $tagText = {
        param($Tags)
        $pairs = @(if ($Tags -is [System.Collections.IDictionary]) { $Tags.Keys | Sort-Object | ForEach-Object { "$_=$($Tags[$_])" } } elseif ($Tags -is [psobject] -and $Tags -isnot [string]) { $Tags.PSObject.Properties | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" } })
        $pairs -join '; '
    }
    $scopeText = { param([string] $Scope) if ($Scope -eq '/') { 'root' } elseif ($Scope -match '/managementgroups/([^/]+)$') { "management group $($Matches[1])" } elseif ($Scope -match '^/subscriptions/([^/]+)$') { $s = $Matches[1]; "subscription $(if ($SubscriptionName.Contains($s)) { $SubscriptionName[$s] } else { $s })" } elseif ($Scope -match '/resourcegroups/([^/]+)$') { "resource group $($Matches[1])" } else { & $leaf $Scope } }
    $wide = { param([string] $Scope) $Scope -eq '/' -or $Scope -match '/managementgroups/[^/]+$' -or $Scope -match '^/subscriptions/[^/]+$' }
    $scopeIds = @{}; foreach ($s in $InScope) { if ($s) { $scopeIds[$s.ToLowerInvariant()] = $true } }
    $covers = { param([string] $SubscriptionId) -not $scopeIds.Count -or $scopeIds.Contains($SubscriptionId.ToLowerInvariant()) }

    $notices = [System.Collections.Generic.List[string]]::new()
    foreach ($key in @($Read.Errors.Keys | Sort-Object)) { $notices.Add("The $key couldn't be read: $($Read.Errors[$key] -replace '\s+', ' ')") }

    # Role names, and the Azure roles of each principal.
    $grantIds = @('8e3af657-a8ff-443c-a75c-2fe8c4bcb635', '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9', 'f58310d9-a9f6-439a-9e8d-f62e7b41a168')
    $contributorId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
    $roleName = @{}
    foreach ($row in (& $rowsOf 'roleDefinitions')) { $roleName[(& $leaf (& $lower $row 'id'))] = & $text $row 'roleName' }
    $roles = @{}
    foreach ($row in (& $rowsOf 'roleAssignments')) {
        $p = & $lower $row 'principalId'
        if (-not $p) { continue }
        $guid = & $leaf (& $lower $row 'roleId')
        $scope = & $lower $row 'scope'
        if (-not $roles.Contains($p)) { $roles[$p] = [System.Collections.Generic.List[object]]::new() }
        $level = if ($grantIds -contains $guid -and (& $wide $scope)) { 'High' } elseif ($guid -eq $contributorId -and (& $wide $scope)) { 'Medium' } else { '' }
        $roles[$p].Add(@{ Name = $(if ($roleName.Contains($guid)) { $roleName[$guid] } else { $guid }); Scope = $scope; Level = $level; Privileged = ($grantIds + $contributorId) -contains $guid })
    }

    # API permissions: the ones that can take over the tenant, and the other privileged ones.
    $takeover = @('RoleManagement.ReadWrite.Directory', 'AppRoleAssignment.ReadWrite.All', 'Application.ReadWrite.All')
    $broad = @(
        'Directory.ReadWrite.All', 'Application.ReadWrite.OwnedBy', 'Group.ReadWrite.All', 'GroupMember.ReadWrite.All', 'User.ReadWrite.All', 'UserAuthenticationMethod.ReadWrite.All'
        'Policy.ReadWrite.ConditionalAccess', 'Domain.ReadWrite.All', 'Mail.ReadWrite', 'Mail.Send', 'MailboxSettings.ReadWrite', 'Files.ReadWrite.All', 'Sites.ReadWrite.All'
        'Sites.FullControl.All', 'Exchange.ManageAsApp', 'full_access_as_app', 'Device.ReadWrite.All', 'PrivilegedAccess.ReadWrite.AzureADGroup', 'RoleAssignmentSchedule.ReadWrite.Directory'
    )
    $apiOf = {
        param([string] $PrincipalId)
        if ($null -eq $Permission -or -not $Permission.Contains($PrincipalId)) { return @() }
        foreach ($a in @(& $list $Permission[$PrincipalId])) {
            $rid = & $lower $a 'resourceId'
            $roleId = & $lower $a 'appRoleId'
            $api = if ($ApiRole.Contains($rid) -and $ApiRole[$rid].Name) { $ApiRole[$rid].Name } elseif (& $text $a 'resourceDisplayName') { & $text $a 'resourceDisplayName' } else { $rid }
            $value = if ($roleId -eq '00000000-0000-0000-0000-000000000000') { 'default access' } elseif ($ApiRole.Contains($rid) -and $ApiRole[$rid].Roles.Contains($roleId)) { $ApiRole[$rid].Roles[$roleId] } else { $roleId }
            @{ Api = $api; Name = $value; Level = $(if ($takeover -contains $value) { 'High' } elseif ($broad -contains $value) { 'Medium' } else { '' }) }
        }
    }

    # What each user-assigned identity is attached to: resources (and AKS kubelets) anywhere in the tenant, and policy assignments.
    $attachedTo = @{}
    $attach = { param([string] $IdentityId, [string] $By) if (-not $attachedTo.Contains($IdentityId)) { $attachedTo[$IdentityId] = [System.Collections.Generic.List[string]]::new() }; if (-not $attachedTo[$IdentityId].Contains($By)) { $attachedTo[$IdentityId].Add($By) } }
    foreach ($row in (& $rowsOf 'attached')) {
        foreach ($k in (& $keysOf (& $get $row 'identities'))) { & $attach $k (& $lower $row 'id') }
        if (& $text $row 'kubelet') { & $attach (& $lower $row 'kubelet') (& $lower $row 'id') }
    }
    foreach ($row in (& $rowsOf 'policyIdentities')) { foreach ($k in (& $keysOf (& $get $row 'identities'))) { & $attach $k (& $lower $row 'id') } }

    $rank = (Get-AACSeverityRank).Rank
    $items = [System.Collections.Generic.List[object]]::new()
    $access = [System.Collections.Generic.List[object]]::new()
    $add = {
        param([hashtable] $Base, [string[]] $AlsoUses)
        $principalId = $Base.PrincipalId
        $azure = @(if ($principalId -and $roles.Contains($principalId)) { $roles[$principalId] })
        $api = @(if ($principalId) { & $apiOf $principalId })
        $isUser = $Base.Kind -eq 'User-assigned'
        $attached = @(if ($isUser -and $attachedTo.Contains($Base.ResourceId)) { $attachedTo[$Base.ResourceId] })
        $fed = @(if ($isUser -and $Federated.Contains($Base.ResourceId)) { & $list $Federated[$Base.ResourceId] })
        $issuers = @($fed | ForEach-Object { $i = & $text $_ 'properties.issuer'; if ($i -match '^https?://([^/]+)') { $Matches[1] } else { $i } } | Where-Object { $_ } | Select-Object -Unique)
        $privileged = @(@($azure | Where-Object Level) + @($api | Where-Object Level))
        $hasAccess = ($azure.Count + $api.Count) -gt 0

        $findings = [System.Collections.Generic.List[object]]::new()
        foreach ($p in @($api | Where-Object Level -EQ 'High')) { $findings.Add(@{ S = 'High'; T = "$($p.Api) $($p.Name) can take over the tenant - any code running on what this identity is attached to holds it. Replace it with the least-privileged permission the workload needs." }) }
        foreach ($r in @($azure | Where-Object Level -EQ 'High')) { $findings.Add(@{ S = 'High'; T = "$($r.Name) on $(& $scopeText $r.Scope): it can grant itself, or anyone, any access there. Scope it to the resources it manages." }) }
        $medApi = @($api | Where-Object Level -EQ 'Medium' | ForEach-Object { $_.Name } | Select-Object -Unique)
        if ($medApi.Count) { $findings.Add(@{ S = 'Medium'; T = "Privileged API permission(s) $($medApi -join ', ') - tenant-wide. Prefer a scoped alternative (Sites.Selected, Exchange RBAC for applications, an administrative unit)." }) }
        foreach ($r in @($azure | Where-Object Level -EQ 'Medium')) { $findings.Add(@{ S = 'Medium'; T = "$($r.Name) on $(& $scopeText $r.Scope): it can change every resource there. Scope it to a resource group or the resources it needs." }) }
        if ($isUser -and $attached.Count -gt $SharedLimit -and $privileged.Count) { $findings.Add(@{ S = 'Medium'; T = "Shared by $($attached.Count) resources with privileged access: each of them acts with it. Give each workload its own identity." }) }
        if ($isUser -and -not $attached.Count -and -not $fed.Count) {
            if ($hasAccess) { $findings.Add(@{ S = 'Medium'; T = 'Attached to nothing and no federated credential, yet it still holds access: remove its roles and permissions, or delete it if nothing will use it.' }) }
            else { $findings.Add(@{ S = 'Low'; T = 'Attached to nothing, no federated credential and no access: delete it if nothing will use it.' }) }
        }
        if ($fed.Count -and $privileged.Count) { $findings.Add(@{ S = 'Medium'; T = "Federated with $($issuers -join ', ') and holds privileged access: whoever runs that workload or pipeline acts with it. Restrict the subject to a protected branch or environment." }) }
        if ($AlsoUses.Count) { $findings.Add(@{ S = 'Low'; T = "The resource also uses user-assigned identit(ies) $($AlsoUses -join ', '): make sure the code asks for the one meant (AZURE_CLIENT_ID), and turn the other off if unused." }) }
        $worst = @($findings | Sort-Object { $rank[$_.S] } | Select-Object -First 1)

        $item = [pscustomobject][ordered]@{
            Severity             = $(if ($worst.Count) { $worst[0].S } else { 'Info' })
            Name                 = $Base.Name
            Kind                 = $Base.Kind
            ResourceType         = $Base.ResourceType
            Subscription         = $Base.Subscription
            ResourceGroup        = $Base.ResourceGroup
            Location             = $Base.Location
            AttachedTo           = $(if ($isUser) { $attached.Count } else { $null })
            AttachedResources    = $(if ($isUser) { (@($attached | Select-Object -First 5 | ForEach-Object { & $leaf $_ }) -join ', ') + $(if ($attached.Count -gt 5) { ", +$($attached.Count - 5) more" } else { '' }) } else { '' })
            AzureRoles           = $azure.Count
            PrivilegedRoles      = (@($azure | Where-Object Privileged | ForEach-Object { $_.Name } | Select-Object -Unique) -join ', ')
            Roles                = (@($azure | Sort-Object { -not $_.Privileged } | Select-Object -First 5 | ForEach-Object { "$($_.Name) on $(& $scopeText $_.Scope)" }) -join '; ') + $(if ($azure.Count -gt 5) { "; +$($azure.Count - 5) more" } else { '' })
            ApiPermissions       = $(if ($null -eq $Permission) { $null } else { $api.Count })
            PrivilegedPermissions = (@($api | Where-Object Level | ForEach-Object { $_.Name } | Select-Object -Unique) -join ', ')
            Permissions          = (@($api | Group-Object Api | Sort-Object Name | ForEach-Object { "$($_.Name): $(@($_.Group | ForEach-Object { $_.Name } | Sort-Object -Unique) -join ', ')" }) -join '; ')
            FederatedCredentials = $(if ($isUser) { $fed.Count } else { $null })
            FederatedIssuers     = ($issuers -join ', ')
            Tags                 = $Base.Tags
            Findings             = (@($findings | ForEach-Object { $_.T }) -join ' ')
            PrincipalId          = $principalId
            ClientId             = $Base.ClientId
            AzureResourceId      = $Base.ResourceId
        }
        $item.PSObject.TypeNames.Insert(0, 'AAC.ManagedIdentity')
        $items.Add($item)
        foreach ($r in $azure) { $access.Add([pscustomobject][ordered]@{ Name = $Base.Name; Kind = $Base.Kind; Type = 'Azure role'; Permission = $r.Name; Target = (& $scopeText $r.Scope); Privileged = [bool]$r.Privileged; PrincipalId = $principalId }) }
        foreach ($p in $api) { $access.Add([pscustomobject][ordered]@{ Name = $Base.Name; Kind = $Base.Kind; Type = 'API permission'; Permission = $p.Name; Target = $p.Api; Privileged = [bool]$p.Level; PrincipalId = $principalId }) }
    }

    $nameOf = @{}
    foreach ($row in (& $rowsOf 'userIdentities')) { $nameOf[(& $lower $row 'id')] = & $text $row 'name' }
    foreach ($row in (& $rowsOf 'userIdentities')) {
        $sub = & $lower $row 'subscriptionId'
        if (-not (& $covers $sub)) { continue }
        & $add @{ Name = (& $text $row 'name'); Kind = 'User-assigned'; ResourceType = 'microsoft.managedidentity/userassignedidentities'; Subscription = $(if ($SubscriptionName.Contains($sub)) { $SubscriptionName[$sub] } else { $sub }); ResourceGroup = (& $text $row 'resourceGroup'); Location = (& $text $row 'location'); Tags = (& $tagText (& $get $row 'tags')); PrincipalId = (& $lower $row 'principalId'); ClientId = (& $text $row 'clientId'); ResourceId = (& $lower $row 'id') } @()
    }
    foreach ($row in (& $rowsOf 'systemIdentities')) {
        $sub = & $lower $row 'subscriptionId'
        if (-not (& $lower $row 'principalId') -or -not (& $covers $sub)) { continue }
        $also = @(& $keysOf (& $get $row 'identities') | ForEach-Object { if ($nameOf.Contains($_)) { $nameOf[$_] } else { & $leaf $_ } })
        & $add @{ Name = (& $text $row 'name'); Kind = 'System-assigned'; ResourceType = (& $lower $row 'type'); Subscription = $(if ($SubscriptionName.Contains($sub)) { $SubscriptionName[$sub] } else { $sub }); ResourceGroup = (& $text $row 'resourceGroup'); Location = (& $text $row 'location'); Tags = (& $tagText (& $get $row 'tags')); PrincipalId = (& $lower $row 'principalId'); ClientId = ''; ResourceId = (& $lower $row 'id') } $also
    }
    foreach ($row in (& $rowsOf 'policyIdentities')) {
        $scope = & $lower $row 'scope'
        if (-not (& $lower $row 'principalId')) { continue }
        if ($scope -match '^/subscriptions/([^/]+)' -and -not (& $covers $Matches[1])) { continue }
        $display = & $text $row 'displayName'
        & $add @{ Name = $(if ($display) { $display } else { & $text $row 'name' }); Kind = 'Policy assignment'; ResourceType = 'microsoft.authorization/policyassignments'; Subscription = $(if ($scope -match '^/subscriptions/([^/]+)') { $s = $Matches[1]; if ($SubscriptionName.Contains($s)) { $SubscriptionName[$s] } else { $s } } else { & $scopeText $scope }); ResourceGroup = $(if ($scope -match '/resourcegroups/([^/]+)') { $Matches[1] } else { '' }); Location = (& $text $row 'location'); Tags = ''; PrincipalId = (& $lower $row 'principalId'); ClientId = ''; ResourceId = (& $lower $row 'id') } @()
    }

    $sorted = @($items | Sort-Object -Property @{ Expression = { $rank[$_.Severity] } }, @{ Expression = { $_.AzureRoles + [int]$_.ApiPermissions }; Descending = $true }, Name)
    @{
        Identities = $sorted
        Access     = @($access | Sort-Object -Property @{ Expression = 'Privileged'; Descending = $true }, Name, Type, Permission)
        Notices    = @($notices)
        Stats      = @{
            Identities  = $sorted.Count
            System      = @($sorted | Where-Object Kind -NE 'User-assigned').Count
            User        = @($sorted | Where-Object Kind -EQ 'User-assigned').Count
            WithApi     = @($sorted | Where-Object ApiPermissions -GT 0).Count
            Privileged  = @($sorted | Where-Object { $_.PrivilegedRoles -or $_.PrivilegedPermissions }).Count
            Unattached  = @($sorted | Where-Object { $_.Kind -eq 'User-assigned' -and $_.AttachedTo -eq 0 -and -not $_.FederatedCredentials }).Count
            Federated   = @($sorted | Where-Object FederatedCredentials -GT 0).Count
            High        = @($sorted | Where-Object Severity -EQ 'High').Count
        }
    }
}
