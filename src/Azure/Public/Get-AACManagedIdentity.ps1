function Get-AACManagedIdentity {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Lists every managed identity - system-assigned (on a resource or a
        policy assignment) and user-assigned - with what it belongs to, what
        it is attached to, its Azure roles, its API permissions (Microsoft
        Graph and other APIs) and federated credentials, and findings for the
        access that matters.
    .DESCRIPTION
        Read-only. Reads:
          Resource Graph     the user-assigned identities, every resource's
                             system-assigned identity, the resources (and AKS
                             kubelets) and policy assignments using each
                             user-assigned identity, and the role assignments
                             and definitions (tenant-wide, so management group
                             and root assignments count)
          Resource Manager   each user-assigned identity's federated
                             credentials (workload identity federation)
          Microsoft Graph    each identity's API permissions (app role
                             assignments) and their names - the Azure portal
                             doesn't show these anywhere for a managed
                             identity (-SkipEntra leaves them out)

        Each identity (AAC.ManagedIdentity) has its kind, resource type,
        subscription, resource group, location and tags; for a user-assigned
        one, the resources it is attached to and its federated credentials;
        its Azure roles and API permissions, the privileged ones apart; and
        findings:
          High    an API permission that can take over the tenant
                  (RoleManagement.ReadWrite.Directory,
                  AppRoleAssignment.ReadWrite.All, Application.ReadWrite.All);
                  Owner, User Access Administrator or Role Based Access
                  Control Administrator on a subscription or above
          Medium  another privileged API permission (Directory.ReadWrite.All,
                  Mail.Send, Sites.FullControl.All...); Contributor on a
                  subscription or above; a user-assigned identity shared by
                  more than -SharedLimit resources with privileged access, or
                  attached to nothing yet still holding access; a federated
                  credential on an identity with privileged access
          Low     a user-assigned identity attached to nothing, without
                  access; a resource with both a system-assigned and
                  user-assigned identities

        The objects pipe into Get-AACApplicationPermission (by PrincipalId)
        for everything else an identity holds: directory roles, PIM,
        ownership, group membership.

        Reader in Azure; Application.Read.All (or Directory Readers) in Entra
        ID for the API permissions. Part of it that can't be read is a
        notice, not an error.
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups (at any depth).
    .PARAMETER Name
        Only identities with these names (wildcards allowed). A
        system-assigned identity has its resource's name.
    .PARAMETER ResourceGroupName
        Only identities in these resource groups (wildcards allowed).
    .PARAMETER SystemAssigned
        Only system-assigned identities (of resources and policy assignments).
    .PARAMETER UserAssigned
        Only user-assigned identities.
    .PARAMETER SkipEntra
        Don't read the API permissions from Microsoft Graph - faster, and
        needs no Entra ID access.
    .PARAMETER SharedLimit
        A user-assigned identity with privileged access attached to more
        resources than this is a finding. Default 10.
    .PARAMETER MaxIdentity
        Read the API permissions of at most this many identities (one
        Microsoft Graph call each). Default 1000.
    .PARAMETER CsvPath
        Write the identities to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report.
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the identities.
    .PARAMETER NoDisplay
        Return the identities without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Get-AACManagedIdentity
        Every managed identity, the riskiest first, with an overview.
    .EXAMPLE
        Get-AACManagedIdentity -UserAssigned -ResourceGroupName 'rg-app-*' -NoDisplay | Select-Object Name, AttachedTo, AzureRoles, ApiPermissions
        The user-assigned identities of the application resource groups.
    .EXAMPLE
        Get-AACManagedIdentity -NoDisplay | Where-Object ApiPermissions | Select-Object Name, Kind, Permissions
        The managed identities with Microsoft Graph (or other API) permissions.
    .EXAMPLE
        Get-AACManagedIdentity -Name 'func-orders' -NoDisplay | Get-AACApplicationPermission
        Everything one identity holds, directory roles included.
    .EXAMPLE
        Get-AACManagedIdentity -ManagementGroupId mg-landingzones -HtmlPath .\ManagedIdentities.html
        A report for one management group.
    .OUTPUTS
        AAC.ManagedIdentity
    #>
    [CmdletBinding()]
    [OutputType('AAC.ManagedIdentity')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string[]] $ManagementGroupId,

        [SupportsWildcards()]
        [string[]] $Name,

        [SupportsWildcards()]
        [string[]] $ResourceGroupName,

        [switch] $SystemAssigned,

        [switch] $UserAssigned,

        [switch] $SkipEntra,

        [ValidateRange(1, 1000)]
        [int] $SharedLimit = 10,

        [ValidateRange(1, 10000)]
        [int] $MaxIdentity = 1000,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Managed identities',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $request = @{
        SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ })
        Name = @($Name | Where-Object { $_ }); ResourceGroupName = @($ResourceGroupName | Where-Object { $_ })
        # Both switches, or neither, mean both kinds.
        System = $SystemAssigned -or -not $UserAssigned; User = $UserAssigned -or -not $SystemAssigned
        Entra = -not $SkipEntra; SharedLimit = $SharedLimit; MaxIdentity = $MaxIdentity
    }
    # The filters, applied before Microsoft Graph is read: one call per identity, so only for the ones asked for.
    $select = {
        param([object[]] $Identities)
        @($Identities | Where-Object {
                $identity = $_
                (($request.User -and $identity.Kind -eq 'User-assigned') -or ($request.System -and $identity.Kind -ne 'User-assigned')) -and
                (-not $request.Name.Count -or @($request.Name | Where-Object { $identity.Name -like $_ }).Count) -and
                (-not $request.ResourceGroupName.Count -or @($request.ResourceGroupName | Where-Object { $identity.ResourceGroup -like $_ }).Count)
            })
    }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Managed identities' -Color 'mediumpurple' }
    $outcome = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
        $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
        Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"

        $queries = [ordered]@{
            userIdentities   = "resources | where type =~ 'microsoft.managedidentity/userassignedidentities' | project id = tolower(id), name, resourceGroup, subscriptionId, location, tags, principalId = tolower(tostring(properties.principalId)), clientId = tostring(properties.clientId)"
            systemIdentities = "resources | where isnotempty(tostring(identity.principalId)) | project id = tolower(id), name, type = tolower(type), resourceGroup, subscriptionId, location, tags, principalId = tolower(tostring(identity.principalId)), identities = identity.userAssignedIdentities"
            # Tenant-wide: a user-assigned identity in scope may be used by a resource in another subscription.
            attached         = @{ Tenant = $true; Query = "resources | where isnotnull(identity.userAssignedIdentities) or isnotempty(tostring(properties.identityProfile.kubeletidentity.resourceId)) | project id = tolower(id), identities = identity.userAssignedIdentities, kubelet = tolower(tostring(properties.identityProfile.kubeletidentity.resourceId))" }
            policyIdentities = @{ Tenant = $true; Query = "policyresources | where type =~ 'microsoft.authorization/policyassignments' and (isnotempty(tostring(identity.principalId)) or isnotnull(identity.userAssignedIdentities)) | project id = tolower(id), name, displayName = tostring(properties.displayName), location, scope = tolower(tostring(properties.scope)), principalId = tolower(tostring(identity.principalId)), identities = identity.userAssignedIdentities" }
            roleAssignments  = @{ Tenant = $true; Query = "authorizationresources | where type =~ 'microsoft.authorization/roleassignments' and tostring(properties.principalType) =~ 'ServicePrincipal' | project id, principalId = tolower(tostring(properties.principalId)), roleId = tolower(tostring(properties.roleDefinitionId)), scope = tolower(tostring(properties.scope))" }
            roleDefinitions  = @{ Tenant = $true; Query = "authorizationresources | where type =~ 'microsoft.authorization/roledefinitions' | project id = tolower(id), roleName = tostring(properties.roleName)" }
        }
        Update-AACProgress -Id 'read' -Total $queries.Count -Description 'Reading the managed identities and role assignments'
        $read = Invoke-AACGraphBatch -Query $queries -SubscriptionId $scope.GraphScope -AllowFailure @('attached', 'policyIdentities', 'roleDefinitions') -OnProgress {
            param($QueryName, $Done, $Total)
            Update-AACProgress -Id 'read' -Increment 1 -Description "Read the $QueryName ($Done of $Total)"
        }
        $convert = @{ Read = $read; SubscriptionName = $scope.Names; InScope = @($scope.GraphScope | ForEach-Object { ([string]$_).ToLowerInvariant() }); SharedLimit = $request.SharedLimit }
        $wanted = & $select (ConvertTo-AACManagedIdentity @convert).Identities
        Update-AACProgress -Id 'read' -Complete -Description ('Found {0:N0} managed identit(ies)' -f $wanted.Count)
        $notices = [System.Collections.Generic.List[string]]::new()

        # Federated credentials of the user-assigned identities (workload identity federation).
        $federated = @{}
        $users = @($wanted | Where-Object Kind -EQ 'User-assigned')
        if ($users.Count) {
            if ($users.Count -gt $request.MaxIdentity) { $notices.Add("$($users.Count) user-assigned identities: the federated credentials of the first $($request.MaxIdentity) were read (-MaxIdentity)."); $users = @($users | Select-Object -First $request.MaxIdentity) }
            $uris = [ordered]@{}
            foreach ($u in $users) { $uris[$u.AzureResourceId] = "$($u.AzureResourceId)/federatedIdentityCredentials?api-version=2023-01-31" }
            Update-AACProgress -Id 'federated' -Total $uris.Count -Description "Reading the federated credentials of $($uris.Count) user-assigned identit(ies)"
            $answers = Invoke-AACArmParallel -Uri @($uris.Values) -OnProgress { param($FedDone, $FedTotal) Update-AACProgress -Id 'federated' -Increment 1 }
            $failed = 0
            foreach ($id in $uris.Keys) { $answer = $answers[$uris[$id]]; if ($answer -and -not $answer.Error) { $federated[$id] = @($answer.Items | Where-Object { $_ }) } else { $failed++ } }
            if ($failed) { $notices.Add("The federated credentials of $failed user-assigned identit(ies) couldn't be read.") }
            Update-AACProgress -Id 'federated' -Complete -Description ('Read the federated credentials of {0:N0} identit(ies)' -f $federated.Count)
        }
        $convert['Federated'] = $federated

        # API permissions: one Microsoft Graph call per identity, then the APIs' role names.
        if ($request.Entra) {
            $principals = @($wanted | ForEach-Object { $_.PrincipalId } | Where-Object { $_ } | Sort-Object -Unique)
            if ($principals.Count -gt $request.MaxIdentity) { $notices.Add("$($principals.Count) identities: the API permissions of the first $($request.MaxIdentity) were read (-MaxIdentity)."); $principals = @($principals | Select-Object -First $request.MaxIdentity) }
            $permission = @{}
            $apiRole = @{}
            if ($principals.Count) {
                $q = [ordered]@{}
                foreach ($p in $principals) { $q[$p] = "https://graph.microsoft.com/v1.0/servicePrincipals/$p/appRoleAssignments?`$select=resourceId,resourceDisplayName,appRoleId" }
                Update-AACProgress -Id 'entra' -Total $q.Count -Description "Reading the API permissions of $($q.Count) identit(ies)"
                $answer = Read-AACGraphQuery -Query $q -OnDone { param($Key, $Failure, $GraphDone, $GraphTotal) Update-AACProgress -Id 'entra' -Increment 1 }
                foreach ($p in $principals) { if ($answer.Data.Contains($p)) { $permission[$p] = @($answer.Data[$p] | Where-Object { $_ }) } }
                if ($answer.Errors.Count) { $notices.Add("The API permissions of $($answer.Errors.Count) identit(ies) couldn't be read: $(@($answer.Errors.Values)[0] -replace '\s+', ' ')") }
                $resources = @($permission.Values | ForEach-Object { $_ } | ForEach-Object { ([string]$_['resourceId']).ToLowerInvariant() } | Where-Object { $_ } | Sort-Object -Unique)
                if ($resources.Count) {
                    $rq = [ordered]@{}
                    foreach ($r in $resources) { $rq[$r] = "https://graph.microsoft.com/v1.0/servicePrincipals/$r`?`$select=id,displayName,appRoles" }
                    $apis = Read-AACGraphQuery -Query $rq
                    foreach ($r in $resources) {
                        if (-not $apis.Data.Contains($r) -or $null -eq $apis.Data[$r]) { continue }
                        $names = @{}
                        foreach ($role in @($apis.Data[$r]['appRoles'] | Where-Object { $_ })) { $names[([string]$role['id']).ToLowerInvariant()] = [string]$role['value'] }
                        $apiRole[$r] = @{ Name = [string]$apis.Data[$r]['displayName']; Roles = $names }
                    }
                }
                Update-AACProgress -Id 'entra' -Complete -Description ('Read the API permissions of {0:N0} identit(ies)' -f $permission.Count)
            }
            $convert['Permission'] = $permission
            $convert['ApiRole'] = $apiRole
        }
        $result = ConvertTo-AACManagedIdentity @convert
        @{ Result = $result; Identities = (& $select $result.Identities); Scope = $scope; Notices = @($result.Notices) + $notices.ToArray() }
    }

    $identities = @($outcome.Identities)
    $kept = @{}; foreach ($i in $identities) { if ($i.PrincipalId) { $kept[$i.PrincipalId] = $true } }
    $accessRows = @($outcome.Result.Access | Where-Object { $_ -and $kept.Contains($_.PrincipalId) })
    $rank = Get-AACSeverityRank
    $count = { param([scriptblock] $Where) @($identities | Where-Object $Where).Count }
    $high = & $count { $_.Severity -eq 'High' }
    $withApi = & $count { $_.ApiPermissions -gt 0 }
    $privileged = & $count { $_.PrivilegedRoles -or $_.PrivilegedPermissions }
    $unattached = & $count { $_.Kind -eq 'User-assigned' -and $_.AttachedTo -eq 0 -and -not $_.FederatedCredentials }
    $federatedCount = & $count { $_.FederatedCredentials -gt 0 }
    $userCount = & $count { $_.Kind -eq 'User-assigned' }
    $kindTones = @{ 'System-assigned' = 'info'; 'User-assigned' = 'violet'; 'Policy assignment' = 'neutral' }
    $report = @{
        Subtitle = 'Managed identities: every system- and user-assigned identity - what it belongs to, what it can do in Azure and through Microsoft Graph, and how it is used'
        Facts    = [ordered]@{ Scope = $outcome.Scope.Label; 'API permissions' = $(if ($SkipEntra) { 'not read (-SkipEntra)' } else { 'read' }) }
        Status   = $(if ($high) { 'Failed' } elseif (& $count { $_.Severity -in 'Medium', 'Low' }) { 'Warning' } else { 'Success' })
        Headline = $(if ($identities.Count) { "$($identities.Count) managed identit(ies): $($identities.Count - $userCount) system-assigned, $userCount user-assigned; $privileged with privileged access, $withApi with API permissions, $unattached attached to nothing" } else { 'No managed identities found.' })
        Tiles    = @(
            @{ Value = '{0:N0}' -f $identities.Count; Label = 'managed identities'; Tone = 'info' }
            @{ Value = '{0:N0}' -f ($identities.Count - $userCount); Label = 'system-assigned'; Tone = 'neutral'; Table = 'identities'; Filters = @{ Kind = 'System-assigned' } }
            @{ Value = '{0:N0}' -f $userCount; Label = 'user-assigned'; Tone = 'neutral'; Table = 'identities'; Filters = @{ Kind = 'User-assigned' } }
            @{ Value = $(if ($SkipEntra) { '-' } else { '{0:N0}' -f $withApi }); Label = 'with API permissions'; Tone = $(if ($withApi) { 'warn' } else { 'good' }) }
            @{ Value = '{0:N0}' -f $privileged; Label = 'with privileged access'; Tone = $(if ($privileged) { 'warn' } else { 'good' }) }
            @{ Value = '{0:N0}' -f $unattached; Label = 'attached to nothing'; Tone = $(if ($unattached) { 'warn' } else { 'good' }) }
            @{ Value = '{0:N0}' -f $federatedCount; Label = 'federated'; Tone = 'neutral' }
            @{ Value = '{0:N0}' -f $high; Label = 'high findings'; Tone = $(if ($high) { 'bad' } else { 'good' }); Table = 'identities'; Filters = @{ Severity = 'High' } }
        )
        Notices  = @($outcome.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
        Charts   = @(
            @{ Title = 'By kind'; Kind = 'donut'; CenterLabel = 'identities'; Items = @($identities | Group-Object Kind | Sort-Object Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Tone = $kindTones[$_.Name]; Filter = $_.Name } }); Table = 'identities'; Column = 'Kind'; Console = $true }
            @{ Title = 'By severity'; Items = @(foreach ($s in 'High', 'Medium', 'Low') { $n = & $count { $_.Severity -eq $s }; if ($n) { @{ Label = $s; Value = $n; Tone = $rank.Tone[$s]; Filter = $s } } }); Table = 'identities'; Column = 'Severity'; Tone = 'warn' }
            @{ Title = 'By resource type'; Items = @($identities | Where-Object Kind -EQ 'System-assigned' | Group-Object ResourceType | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'identities'; Column = 'ResourceType'; Tone = 'info' }
            @{ Title = 'Most access'; Items = @($identities | Where-Object { $_.AzureRoles + [int]$_.ApiPermissions } | Sort-Object { $_.AzureRoles + [int]$_.ApiPermissions } -Descending | Select-Object -First 10 | ForEach-Object { @{ Label = $_.Name; Value = $_.AzureRoles + [int]$_.ApiPermissions; Filter = $_.Name } }); Table = 'identities'; Column = 'Name'; Tone = 'violet' }
        )
        Tables   = @(
            @{ Id = 'identities'; Title = 'Managed identities'; Section = 'Identities'; Rows = $identities; Noun = 'identities'; GroupBy = @('Kind', 'Severity'); ConsoleLimit = 30
                Empty = 'No managed identities found in scope.'; EmptyStatus = 'Info'
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Name'; Label = 'Identity'; Console = $true; Pdf = $true }
                    @{ Key = 'Kind'; Label = 'Kind'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'ResourceType'; Label = 'Resource type'; Facet = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true; Pdf = $true }
                    @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true; Console = $true }
                    @{ Key = 'AttachedTo'; Label = 'Attached'; Type = 'number'; Console = $true }
                    @{ Key = 'AzureRoles'; Label = 'Roles'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'ApiPermissions'; Label = 'API'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'FederatedCredentials'; Label = 'Federated'; Type = 'number' }
                    @{ Key = 'PrivilegedRoles'; Label = 'Privileged roles' }
                    @{ Key = 'PrivilegedPermissions'; Label = 'Privileged permissions' }
                    @{ Key = 'Findings'; Label = 'Findings'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Roles'; Label = 'Azure roles'; Type = 'wide' }
                    @{ Key = 'Permissions'; Label = 'API permissions'; Type = 'wide' }
                    @{ Key = 'AttachedResources'; Label = 'Attached to' }
                    @{ Key = 'FederatedIssuers'; Label = 'Federated with' }
                    @{ Key = 'Location'; Label = 'Location' }
                    @{ Key = 'Tags'; Label = 'Tags' }
                    @{ Key = 'PrincipalId'; Label = 'Principal ID'; Type = 'mono' }
                    @{ Key = 'ClientId'; Label = 'Client ID'; Type = 'mono' }
                    @{ Key = 'AzureResourceId'; Label = 'Resource'; Type = 'mono' }
                ) }
            @{ Id = 'access'; Title = 'Access: every Azure role and API permission'; Section = 'Access'; Rows = $accessRows; Noun = 'grants'; GroupBy = @('Type')
                Empty = 'No managed identity in scope holds an Azure role or API permission.'; EmptyStatus = 'Info'
                Columns = @(
                    @{ Key = 'Name'; Label = 'Identity' }
                    @{ Key = 'Kind'; Label = 'Kind'; Facet = $true }
                    @{ Key = 'Type'; Label = 'Type'; Facet = $true }
                    @{ Key = 'Permission'; Label = 'Role or permission'; Facet = $true }
                    @{ Key = 'Target'; Label = 'Scope or API' }
                    @{ Key = 'Privileged'; Label = 'Privileged'; Facet = $true }
                ) }
        )
        Hint     = '-Name, -ResourceGroupName, -SystemAssigned and -UserAssigned narrow it; pipe to Get-AACApplicationPermission for directory roles; -NoDisplay returns the identities; -HtmlPath, -PdfPath or -CsvPath for a report.'
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $identities -Noun 'identity' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $identities -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
