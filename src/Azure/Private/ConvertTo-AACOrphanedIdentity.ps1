function ConvertTo-AACOrphanedIdentity {
    <#
    .SYNOPSIS
        Builds Get-AACOrphanedIdentity's list (AAC.OrphanedIdentity) from the
        Resource Graph rows and Microsoft Graph answers of
        Get-AACOrphanedIdentityQuery: identities nobody uses any more - and
        the access they still hold.
    .DESCRIPTION
        No Azure calls. -Read is Invoke-AACGraphBatch's result; -Federated
        maps a user-assigned identity's ID (lower case) to its number of
        federated credentials ($null: not read); -Directory is
        Get-AACDirectoryObject's result for the role assignments' principals
        ($null: not read); -Entra is Read-AACGraphQuery's ($null: not read).
        Role assignments count when their scope is a subscription in
        -SubscriptionName (or below it), a management group or the root.

          Deleted principal       role assignments to a principal Entra ID no
                                  longer has ("Identity not found")
          User-assigned identity  attached to no resource and no federated
                                  credential (not used by any workload)
          Managed identity        the resource it belonged to is gone
          Application             the tenant's service principal not signed
                                  in for -InactiveDays (or ever), disabled
                                  but still assigned roles; its app
                                  registration with only expired
                                  credentials, or no owners

        Severity follows the access left behind: High when it holds a
        privileged role (Owner, Contributor, User Access Administrator, Role
        Based Access Control Administrator), Medium with other roles (or
        only expired credentials), Low with none.

        Returns @{ Identities; Notices; Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Read,

        [hashtable] $Federated = @{},

        [hashtable] $Directory,

        [hashtable] $Entra,

        [string] $TenantId = '',

        [ValidateRange(1, 3650)]
        [int] $InactiveDays = 90,

        [hashtable] $SubscriptionName = @{},

        [datetime] $Now = [datetime]::UtcNow
    )

    $get = ${function:Get-AACMember}
    $text = { param($Object, [string] $Path) $v = & $get $Object $Path; if ($null -eq $v) { '' } else { [string]$v } }
    $list = { param($Item) @(if ($Item -is [System.Collections.IEnumerable] -and $Item -isnot [string] -and $Item -isnot [System.Collections.IDictionary]) { $Item } elseif ($null -ne $Item) { , $Item }) | Where-Object { $null -ne $_ -and '' -ne $_ } }
    $rowsOf = { param([string] $Name) @(if ($Read.Rows -and $Read.Rows.Contains($Name)) { $Read.Rows[$Name] | Where-Object { $null -ne $_ } }) }
    $readOk = { param([string] $Name) $Read.Rows -and $Read.Rows.Contains($Name) -and -not ($Read.Errors -and $Read.Errors.Contains($Name)) }
    $subscriptionOf = { param([string] $Id) if ($Id -match '^/subscriptions/([^/]+)') { $Matches[1].ToLowerInvariant() } else { '' } }
    $label = { param([string] $Id) $s = ([string]$Id).ToLowerInvariant(); if ($SubscriptionName.Contains($s)) { $SubscriptionName[$s] } else { $Id } }
    $date = {
        param([string] $Value)
        $d = [datetime]::MinValue
        if ($Value -and [datetime]::TryParse($Value, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$d)) { $d } else { $null }
    }
    $notices = [System.Collections.Generic.List[string]]::new()
    foreach ($key in @($Read.Errors.Keys | Sort-Object)) { $notices.Add("The $key couldn't be read: $($Read.Errors[$key] -replace '\s+', ' ')") }

    # --- Role assignments in scope, by principal ------------------------------------------------------------------
    $privileged = @('8e3af657-a8ff-443c-a75c-2fe8c4bcb635', 'b24988ac-6180-42a0-ab88-20f7382dd24c', '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9', 'f58310d9-a9f6-439a-9e8d-f62e7b41a168')
    $roleName = @{}
    foreach ($row in (& $rowsOf 'roleDefinitions')) { $roleName[((& $text $row 'id') -split '/')[-1]] = & $text $row 'roleName' }
    $assigned = @{}
    foreach ($row in (& $rowsOf 'roleAssignments')) {
        $scope = & $text $row 'scope'
        $sub = & $subscriptionOf $scope
        if ($sub -and -not $SubscriptionName.Contains($sub)) { continue }
        $principal = (& $text $row 'principalId').ToLowerInvariant()
        if (-not $principal) { continue }
        $guid = ((& $text $row 'roleId') -split '/')[-1]
        if (-not $assigned.Contains($principal)) { $assigned[$principal] = [System.Collections.Generic.List[object]]::new() }
        $assigned[$principal].Add(@{ Role = $(if ($roleName.Contains($guid)) { $roleName[$guid] } else { $guid }); Scope = $scope; Privileged = $privileged -contains $guid; Type = (& $text $row 'principalType') })
    }
    $access = {
        param([string] $PrincipalId)
        $a = @(if ($PrincipalId -and $assigned.Contains($PrincipalId.ToLowerInvariant())) { $assigned[$PrincipalId.ToLowerInvariant()] })
        $scopeText = { param([string] $Scope) if ($Scope -match '/managementgroups/([^/]+)$') { "management group $($Matches[1])" } elseif ($Scope -eq '/') { 'root' } elseif ($Scope -match '^/subscriptions/([^/]+)$') { "subscription $(& $label $Matches[1])" } else { ($Scope -split '/')[-1] } }
        @{ Count = $a.Count; Privileged = @($a | Where-Object { $_.Privileged }).Count -gt 0; Text = (@($a | Sort-Object { -not $_.Privileged } | Select-Object -First 5 | ForEach-Object { "$($_.Role) on $(& $scopeText $_.Scope)" }) -join '; ') + $(if ($a.Count -gt 5) { "; +$($a.Count - 5) more" } else { '' }) }
    }
    $severityFor = { param($Access, [string] $Floor = 'Low') if ($Access.Privileged) { 'High' } elseif ($Access.Count -or $Floor -eq 'Medium') { 'Medium' } else { 'Low' } }
    $identities = [System.Collections.Generic.List[object]]::new()
    $add = {
        param([string] $Severity, [string] $Kind, [string] $Identity, [string[]] $Reasons, $Access, [string] $Remediation, [hashtable] $More = @{})
        $item = [pscustomobject][ordered]@{
            Severity        = $Severity
            Kind            = $Kind
            Identity        = $Identity
            Reason          = ($Reasons -join ' ')
            LastSignIn      = $More['LastSignIn']
            DaysInactive    = $(if ($More['LastSignIn']) { [int][Math]::Floor(($Now - $More['LastSignIn']).TotalDays) } else { $null })
            RoleAssignments = $Access.Count
            Roles           = $Access.Text
            Credentials     = [string]$More['Credentials']
            Owners          = $More['Owners']
            Created         = $More['Created']
            Remediation     = $Remediation
            AppId           = [string]$More['AppId']
            PrincipalId     = [string]$More['PrincipalId']
            ResourceGroup   = [string]$More['ResourceGroup']
            Subscription    = [string]$More['Subscription']
            ResourceId      = [string]$More['ResourceId']
            Id              = [string]$More['Id']
        }
        $item.PSObject.TypeNames.Insert(0, 'AAC.OrphanedIdentity')
        $identities.Add($item)
    }

    # --- Role assignments to deleted principals --------------------------------------------------------------------------
    if ($null -ne $Directory) {
        if ($Directory.Error) { $notices.Add("The role assignments' principals couldn't be looked up in Entra ID: $($Directory.Error)") }
        else {
            foreach ($principal in @($assigned.Keys | Sort-Object)) {
                if ($Directory.Objects.Contains($principal)) { continue }
                $a = & $access $principal
                $type = @($assigned[$principal] | ForEach-Object { $_.Type } | Where-Object { $_ } | Select-Object -Unique) -join ', '
                & $add (& $severityFor $a 'Medium') 'Deleted principal' "Identity not found ($(if ($type) { $type } else { 'unknown type' }))" @('The principal no longer exists in Entra ID, but its role assignments remain - shown as "Identity not found" in the portal.') $a 'Remove its role assignments (they grant nothing, but they clutter every access review and hide real ones).' @{ PrincipalId = $principal }
            }
        }
    }

    # --- User-assigned identities nothing uses --------------------------------------------------------------------------
    $used = @{}
    foreach ($row in (& $rowsOf 'attached')) {
        $bag = & $get $row 'identities'
        if ($bag -is [System.Collections.IDictionary]) { foreach ($k in $bag.Keys) { $used[([string]$k).ToLowerInvariant()] = $true } }
        $kubelet = & $text $row 'kubelet'
        if ($kubelet) { $used[$kubelet] = $true }
    }
    if (& $readOk 'attached') {
        foreach ($row in (& $rowsOf 'userIdentities')) {
            $sub = (& $text $row 'subscriptionId').ToLowerInvariant()
            if (-not $SubscriptionName.Contains($sub)) { continue }
            $id = & $text $row 'id'
            if ($used.Contains($id)) { continue }
            $credentialCount = if ($Federated.Contains($id)) { $Federated[$id] } else { $null }
            if ($credentialCount -gt 0) { continue }
            $a = & $access (& $text $row 'principalId')
            & $add (& $severityFor $a) 'User-assigned identity' (& $text $row 'name') @("Attached to no resource$(if ($null -eq $credentialCount) { ' (federated credentials not checked)' } else { ' and with no federated credential' }).") $a $(if ($a.Count) { 'Delete it (and its role assignments) if nothing will use it - anyone allowed to assign it to a resource gets its access.' } else { 'Delete it if nothing will use it.' }) @{ PrincipalId = (& $text $row 'principalId'); AppId = (& $text $row 'clientId'); ResourceGroup = (& $text $row 'resourceGroup'); Subscription = (& $label $sub); ResourceId = $id }
        }
    }

    # --- Entra ID: managed identities and applications ------------------------------------------------------------------
    if ($null -ne $Entra) {
        $data = if ($Entra.Contains('Data')) { $Entra.Data } else { @{} }
        $failed = if ($Entra.Contains('Errors')) { $Entra.Errors } else { @{} }
        foreach ($key in @($failed.Keys | Sort-Object)) { $notices.Add("$(@{ servicePrincipals = 'The service principals'; managedIdentities = 'The managed identities'; applications = 'The app registrations'; signIns = 'The service principals'' sign-in activity (it needs AuditLog.Read.All and Entra ID P1)' }[$key]) couldn't be read: $($failed[$key] -replace '\s+', ' ')") }

        # Managed identities whose resource is gone.
        if ((& $readOk 'systemIdentities') -and (& $readOk 'userIdentities')) {
            $exists = @{}
            foreach ($row in (& $rowsOf 'systemIdentities')) { $exists[(& $text $row 'id')] = $true }
            foreach ($row in (& $rowsOf 'userIdentities')) { $exists[(& $text $row 'id')] = $true }
            foreach ($mi in @(& $list $data['managedIdentities'])) {
                $resourceId = [string](@(& $list (& $get $mi 'alternativeNames')) | Where-Object { $_ -match '^/subscriptions/' } | Select-Object -First 1)
                $sub = & $subscriptionOf $resourceId
                if (-not $resourceId -or -not $SubscriptionName.Contains($sub) -or $exists.Contains($resourceId.ToLowerInvariant())) { continue }
                $a = & $access (& $text $mi 'id')
                & $add (& $severityFor $a) 'Managed identity' (& $text $mi 'displayName') @("The resource it belonged to ($(($resourceId -split '/')[-1])) no longer exists.") $a 'Remove its role assignments; Entra ID deletes the service principal of a deleted resource''s identity (open a support case if it stays).' @{ PrincipalId = (& $text $mi 'id'); AppId = (& $text $mi 'appId'); Subscription = (& $label $sub); ResourceId = $resourceId.ToLowerInvariant(); Id = (& $text $mi 'id') }
            }
        }

        # Applications: the tenant's service principals and app registrations.
        $signInsRead = $data.Contains('signIns') -and -not $failed.Contains('signIns')
        $lastOf = @{}
        foreach ($s in @(& $list $data['signIns'])) { $lastOf[(& $text $s 'appId').ToLowerInvariant()] = & $date (& $text $s 'lastSignInActivity.lastSignInDateTime') }
        $apps = @{}
        foreach ($app in @(& $list $data['applications'])) { $apps[(& $text $app 'appId').ToLowerInvariant()] = $app }
        $sps = @{}
        foreach ($sp in @(& $list $data['servicePrincipals'])) { if (-not $TenantId -or (& $text $sp 'appOwnerOrganizationId') -eq $TenantId) { $sps[(& $text $sp 'appId').ToLowerInvariant()] = $sp } }
        foreach ($appId in @(@($apps.Keys) + @($sps.Keys) | Select-Object -Unique | Sort-Object)) {
            $app = $apps[$appId]; $sp = $sps[$appId]
            $reasons = [System.Collections.Generic.List[string]]::new()
            $floor = 'Low'
            $a = if ($sp) { & $access (& $text $sp 'id') } else { @{ Count = 0; Privileged = $false; Text = '' } }
            $created = & $date (& $text $(if ($app) { $app } else { $sp }) 'createdDateTime')
            $last = if ($lastOf.Contains($appId)) { $lastOf[$appId] } else { $null }
            if ($sp -and $signInsRead -and (-not $created -or ($Now - $created).TotalDays -ge $InactiveDays)) {
                if (-not $last) { $reasons.Add("No sign-in recorded$(if ($created) { " since it was created ($($created.ToString('yyyy-MM-dd')))" }).") }
                elseif (($Now - $last).TotalDays -ge $InactiveDays) { $reasons.Add("No sign-in for $([int][Math]::Floor(($Now - $last).TotalDays)) days (last $($last.ToString('yyyy-MM-dd'))).") }
            }
            if ($sp -and (& $text $sp 'accountEnabled') -eq 'False' -and $a.Count) { $reasons.Add('Disabled, but still assigned roles.') }
            $credentials = @(@(& $list (& $get $app 'passwordCredentials')) + @(& $list (& $get $app 'keyCredentials')))
            $credentialText = ''
            if ($app) {
                $secrets = @(& $list (& $get $app 'passwordCredentials')).Count; $certs = @(& $list (& $get $app 'keyCredentials')).Count
                $credentialText = "$secrets secret(s), $certs certificate(s)"
                $ends = @($credentials | ForEach-Object { & $date (& $text $_ 'endDateTime') } | Where-Object { $_ })
                if ($ends.Count -and -not @($ends | Where-Object { $_ -gt $Now }).Count) { $reasons.Add("Every credential has expired (the last on $((@($ends | Sort-Object))[-1].ToString('yyyy-MM-dd'))): nothing can sign in as it."); $floor = 'Medium'; $credentialText += ', all expired' }
                if (-not @(& $list (& $get $app 'owners')).Count) { $reasons.Add('No owners: nobody is accountable for it.') }
            }
            if (-not $reasons.Count) { continue }
            & $add (& $severityFor $a $floor) 'Application' (& $text $(if ($app) { $app } else { $sp }) 'displayName') $reasons.ToArray() $a $(if ($a.Count) { 'Confirm with its owner it is unused; remove its role assignments, disable the service principal for a while, then delete the app registration.' } else { 'Confirm it is unused, then delete the app registration (or assign owners if it is still needed).' }) @{
                LastSignIn = $last; Credentials = $credentialText; Owners = $(if ($app) { @(& $list (& $get $app 'owners')).Count } else { $null }); Created = $created; AppId = $appId; PrincipalId = $(if ($sp) { & $text $sp 'id' } else { '' }); Id = $(if ($app) { & $text $app 'id' } else { & $text $sp 'id' })
            }
        }
        if (-not $signInsRead -and $data.Contains('servicePrincipals')) { $notices.Add('Without sign-in activity, inactive service principals can''t be told apart: only expired credentials, missing owners and disabled ones are listed.') }
    }

    $rank = (Get-AACSeverityRank).Rank
    $sorted = @($identities | Sort-Object -Property @{ Expression = { $rank[$_.Severity] } }, @{ Expression = 'RoleAssignments'; Descending = $true }, Kind, Identity)
    $assignmentTotal = 0; foreach ($i in $sorted) { $assignmentTotal += [int]$i.RoleAssignments }
    @{
        Identities = $sorted
        Notices    = @($notices)
        Stats      = @{
            Identities   = $sorted.Count
            High         = @($sorted | Where-Object Severity -EQ 'High').Count
            Deleted      = @($sorted | Where-Object Kind -EQ 'Deleted principal').Count
            Unattached   = @($sorted | Where-Object Kind -EQ 'User-assigned identity').Count
            Applications = @($sorted | Where-Object Kind -EQ 'Application').Count
            WithAccess   = @($sorted | Where-Object RoleAssignments -GT 0).Count
            Assignments  = $assignmentTotal
        }
    }
}
