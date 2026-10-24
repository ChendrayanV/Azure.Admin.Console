function ConvertTo-AACServicePrincipalInsight {
    <#
    .SYNOPSIS
        Builds Get-AACServicePrincipalInsight's list
        (AAC.ServicePrincipalInsight): every service principal and managed
        identity that holds an Azure role - what it is, what it can do,
        what it is attached to, and its credentials.
    .DESCRIPTION
        No Azure calls.
          -Read         Invoke-AACGraphBatch's result: roleAssignments
                        (service principals'), roleDefinitions,
                        userIdentities, attached (resources with
                        user-assigned identities)
          -Directory    Get-AACDirectoryObject's result for the principals
                        (with appOwnerOrganizationId, alternativeNames,
                        passwordCredentials, keyCredentials), or $null
          -Application  the app registrations (appId -> the application:
                        displayName, passwordCredentials, keyCredentials)
        Each principal: Kind - Application, Application (external), Managed
        identity (system-assigned, with its resource type), Managed identity
        (user-assigned), Managed identity (policy assignment) - its role
        assignments and privileged roles, the resources a user-assigned
        identity is attached to, its credentials (the app registration's and
        the service principal's) and the next to expire, and findings:
          High    another tenant's application with a privileged role
          Medium  another tenant's application with any role; an expired
                  credential on an application that still holds roles; a
                  user-assigned identity with roles attached to nothing; one
                  shared by more than -SharedLimit resources with a
                  privileged role
          Low     a credential expiring within -ExpiryDays; a secret valid
                  for more than a year
        Returns @{ Principals; Notices; Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Read,

        [hashtable] $Directory,

        [hashtable] $Application = @{},

        [string] $TenantId = '',

        [ValidateRange(1, 365)]
        [int] $ExpiryDays = 30,

        [ValidateRange(1, 1000)]
        [int] $SharedLimit = 10,

        [datetime] $Now = [datetime]::UtcNow
    )

    $get = ${function:Get-AACMember}
    $text = { param($Object, [string] $Path) $v = & $get $Object $Path; if ($null -eq $v) { '' } else { [string]$v } }
    $list = { param($Item) @(if ($Item -is [System.Collections.IEnumerable] -and $Item -isnot [string] -and $Item -isnot [System.Collections.IDictionary]) { $Item } elseif ($null -ne $Item) { , $Item }) | Where-Object { $null -ne $_ -and '' -ne $_ } }
    $rowsOf = { param([string] $Name) @(if ($Read.Rows -and $Read.Rows.Contains($Name)) { $Read.Rows[$Name] | Where-Object { $null -ne $_ } }) }
    $date = {
        param([string] $Value)
        $d = [datetime]::MinValue
        if ($Value -and [datetime]::TryParse($Value, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$d)) { $d } else { $null }
    }
    $notices = [System.Collections.Generic.List[string]]::new()
    foreach ($key in @($Read.Errors.Keys | Sort-Object)) { $notices.Add("The $key couldn't be read: $($Read.Errors[$key] -replace '\s+', ' ')") }
    if ($null -eq $Directory) { $notices.Add('Entra ID was not read: the principals are shown by ID, without their kind or credentials.') }
    elseif ($Directory.Error) { $notices.Add("The principals couldn't be looked up in Entra ID ($($Directory.Error)): they are shown by ID.") }

    $privilegedIds = @('8e3af657-a8ff-443c-a75c-2fe8c4bcb635', '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9', 'f58310d9-a9f6-439a-9e8d-f62e7b41a168', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    $roleName = @{}
    foreach ($row in (& $rowsOf 'roleDefinitions')) { $roleName[((& $text $row 'id') -split '/')[-1].ToLowerInvariant()] = & $text $row 'roleName' }
    $scopeText = { param([string] $Scope) if ($Scope -eq '/') { 'root' } elseif ($Scope -match '/managementgroups/([^/]+)$') { "management group $($Matches[1])" } elseif ($Scope -match '^/subscriptions/([^/]+)$') { "subscription $($Matches[1])" } elseif ($Scope -match '/resourcegroups/([^/]+)$') { "resource group $($Matches[1])" } else { ($Scope -split '/')[-1] } }

    # Roles per principal.
    $roles = @{}
    foreach ($row in (& $rowsOf 'roleAssignments')) {
        $p = (& $text $row 'principalId').ToLowerInvariant()
        if (-not $p) { continue }
        $guid = ((& $text $row 'roleId') -split '/')[-1].ToLowerInvariant()
        if (-not $roles.Contains($p)) { $roles[$p] = [System.Collections.Generic.List[object]]::new() }
        $roles[$p].Add(@{ Role = $(if ($roleName.Contains($guid)) { $roleName[$guid] } else { $guid }); Scope = (& $text $row 'scope'); Privileged = $privilegedIds -contains $guid })
    }
    # User-assigned identities and what they are attached to.
    $uami = @{}
    foreach ($row in (& $rowsOf 'userIdentities')) { $uami[(& $text $row 'principalId').ToLowerInvariant()] = @{ Id = (& $text $row 'id').ToLowerInvariant(); Name = (& $text $row 'name'); Attached = 0 } }
    $byResourceId = @{}; foreach ($k in $uami.Keys) { $byResourceId[$uami[$k].Id] = $k }
    foreach ($row in (& $rowsOf 'attached')) {
        $bag = & $get $row 'identities'
        if ($bag -is [System.Collections.IDictionary]) { foreach ($k in $bag.Keys) { $key = ([string]$k).ToLowerInvariant(); if ($byResourceId.Contains($key)) { $uami[$byResourceId[$key]].Attached++ } } }
    }

    $rank = (Get-AACSeverityRank).Rank
    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($principalId in @($roles.Keys)) {
        $o = if ($Directory -and -not $Directory.Error -and $Directory.Objects.Contains($principalId)) { $Directory.Objects[$principalId] } else { $null }
        if ($Directory -and -not $Directory.Error -and -not $o) { continue }  # deleted: Get-AACRoleAssignment and Get-AACOrphanedIdentity report those
        $odata = [string]$(if ($o -is [System.Collections.IDictionary] -and $o.Contains('@odata.type')) { $o['@odata.type'] })
        if ($o -and $odata -notlike '*servicePrincipal') { continue }
        $assigned = @($roles[$principalId])
        $privileged = @($assigned | Where-Object Privileged | ForEach-Object { $_.Role } | Select-Object -Unique)
        $kind = 'Service principal'; $resource = ''; $attached = $null; $credentials = @(); $owner = ''
        if ($o) {
            $alt = @(& $list (& $get $o 'alternativeNames'))
            $resource = [string](@($alt | Where-Object { [string]$_ -match '^/subscriptions/|^/providers/' }) | Select-Object -First 1)
            if ((& $text $o 'servicePrincipalType') -eq 'ManagedIdentity') {
                if ($uami.Contains($principalId)) { $kind = 'Managed identity (user-assigned)'; $attached = $uami[$principalId].Attached; $resource = $uami[$principalId].Id }
                elseif ($resource -match '/policyassignments/') { $kind = 'Managed identity (policy assignment)' }
                else { $kind = "Managed identity (system-assigned$(if ($resource -match '/providers/([^/]+/[^/]+)/[^/]+$') { ": $($Matches[1].ToLowerInvariant())" }))" }
            }
            else {
                $owner = & $text $o 'appOwnerOrganizationId'
                $kind = if ($TenantId -and $owner -and $owner -ne $TenantId) { 'Application (external)' } else { 'Application' }
                $app = if ($Application.Contains((& $text $o 'appId').ToLowerInvariant())) { $Application[(& $text $o 'appId').ToLowerInvariant()] } else { $null }
                foreach ($source in @($app, $o)) {
                    if (-not $source) { continue }
                    foreach ($c in @(& $list (& $get $source 'passwordCredentials'))) { $credentials += @{ Kind = 'secret'; Start = (& $date (& $text $c 'startDateTime')); End = (& $date (& $text $c 'endDateTime')) } }
                    foreach ($c in @(& $list (& $get $source 'keyCredentials'))) { $credentials += @{ Kind = 'certificate'; Start = (& $date (& $text $c 'startDateTime')); End = (& $date (& $text $c 'endDateTime')) } }
                }
            }
        }
        $live = @($credentials | Where-Object { $_.End -and $_.End -gt $Now })
        $expired = @($credentials | Where-Object { $_.End -and $_.End -le $Now })
        $next = @($live | Sort-Object { $_.End } | Select-Object -First 1)
        $findings = [System.Collections.Generic.List[object]]::new()
        if ($kind -eq 'Application (external)') {
            if ($privileged.Count) { $findings.Add(@{ S = 'High'; T = "Another tenant's application holds $($privileged -join ', ') - whoever controls that app's credentials has this access. Confirm the vendor needs it, at this scope." }) }
            else { $findings.Add(@{ S = 'Medium'; T = "Another tenant's application holds Azure roles - check the vendor still needs them." }) }
        }
        if ($expired.Count -and -not $live.Count) { $findings.Add(@{ S = 'Medium'; T = "Every credential has expired: whatever uses it fails to sign in - rotate it, or remove the application and its roles." }) }
        if ($next.Count -and ($next[0].End - $Now).TotalDays -le $ExpiryDays) { $findings.Add(@{ S = 'Low'; T = "A $($next[0].Kind) expires in $([int][Math]::Ceiling(($next[0].End - $Now).TotalDays)) day(s) ($($next[0].End.ToString('yyyy-MM-dd'))) - rotate it before then." }) }
        if (@($live | Where-Object { $_.Kind -eq 'secret' -and $_.Start -and ($_.End - $_.Start).TotalDays -gt 366 }).Count) { $findings.Add(@{ S = 'Low'; T = 'A client secret is valid for more than a year: prefer short-lived secrets, a certificate, or a managed identity / workload identity federation.' }) }
        if ($null -ne $attached -and $attached -eq 0) { $findings.Add(@{ S = 'Medium'; T = 'A user-assigned identity with Azure roles, attached to no resource: delete it, or its roles, if nothing will use it.' }) }
        if ($null -ne $attached -and $attached -gt $SharedLimit -and $privileged.Count) { $findings.Add(@{ S = 'Medium'; T = "Shared by $attached resources with $($privileged -join ', '): each of them acts with that access - split it per workload." }) }
        $worst = @($findings | Sort-Object { $rank[$_.S] } | Select-Object -First 1)
        $item = [pscustomobject][ordered]@{
            Severity          = $(if ($worst.Count) { $worst[0].S } else { 'Info' })
            ServicePrincipal  = $(if ($o -and (& $text $o 'displayName')) { & $text $o 'displayName' } else { $principalId })
            Kind              = $kind
            RoleAssignments   = $assigned.Count
            PrivilegedRoles   = ($privileged -join ', ')
            Roles             = (@($assigned | Sort-Object { -not $_.Privileged } | Select-Object -First 5 | ForEach-Object { "$($_.Role) on $(& $scopeText $_.Scope)" }) -join '; ') + $(if ($assigned.Count -gt 5) { "; +$($assigned.Count - 5) more" } else { '' })
            AttachedResources = $attached
            Credentials       = $(if ($credentials.Count) { "$(@($credentials | Where-Object Kind -EQ 'secret').Count) secret(s), $(@($credentials | Where-Object Kind -EQ 'certificate').Count) certificate(s)$(if ($expired.Count) { ", $($expired.Count) expired" })" } else { '' })
            NextExpiry        = $(if ($next.Count) { $next[0].End } else { $null })
            Findings          = (@($findings | ForEach-Object { $_.T }) -join ' ')
            OwnerTenant       = $owner
            AppId             = $(if ($o) { & $text $o 'appId' } else { '' })
            PrincipalId       = $principalId
            ResourceId        = $resource
        }
        $item.PSObject.TypeNames.Insert(0, 'AAC.ServicePrincipalInsight')
        $items.Add($item)
    }
    $sorted = @($items | Sort-Object -Property @{ Expression = { $rank[$_.Severity] } }, @{ Expression = 'RoleAssignments'; Descending = $true }, ServicePrincipal)
    @{
        Principals = $sorted
        Notices    = @($notices)
        Stats      = @{
            Principals = $sorted.Count
            External   = @($sorted | Where-Object Kind -EQ 'Application (external)').Count
            Managed    = @($sorted | Where-Object Kind -Like 'Managed identity*').Count
            Expiring   = @($sorted | Where-Object { $_.NextExpiry -and ($_.NextExpiry - $Now).TotalDays -le $ExpiryDays }).Count
            High       = @($sorted | Where-Object Severity -EQ 'High').Count
        }
    }
}
