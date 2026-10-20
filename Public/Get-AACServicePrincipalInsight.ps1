function Get-AACServicePrincipalInsight {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Lists every service principal and managed identity that holds an
        Azure role - application or another tenant's, system- or
        user-assigned identity, policy assignment identity - with its roles,
        the resources it is attached to, and credentials about to expire.
    .DESCRIPTION
        Reads, read-only:
          Resource Graph   the role assignments to service principals and the
                           role names (tenant-wide), the user-assigned
                           identities and the resources they are attached to
          Microsoft Graph  each principal (type, owner tenant, the resource a
                           managed identity belongs to, its own credentials)
                           and the app registrations' secrets and
                           certificates
        Each principal (AAC.ServicePrincipalInsight): its kind, role
        assignments and privileged roles, attached resources (user-assigned
        identities), credentials and the next to expire, and findings:
          High    another tenant's application with a privileged role
          Medium  another tenant's application with any role; only expired
                  credentials; a user-assigned identity with roles attached
                  to nothing, or shared by many resources with a privileged
                  role
          Low     a credential expiring within -ExpiryDays (30); a client
                  secret valid for more than a year
        Deleted principals are left to Get-AACRoleAssignment and
        Get-AACOrphanedIdentity. Reader in Azure; Directory.Read.All and
        Application.Read.All in Entra ID.
    .PARAMETER SubscriptionId
        Only role assignments in these subscriptions (management group and
        root ones always count).
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups (at any depth).
    .PARAMETER Kind
        Only these kinds: Application, ExternalApplication, ManagedIdentity.
    .PARAMETER ExpiryDays
        A credential expiring within this many days is a finding. Default 30.
    .PARAMETER SharedLimit
        A user-assigned identity with a privileged role attached to more
        resources than this is a finding. Default 10.
    .PARAMETER CsvPath
        Write the principals to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report.
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the principals.
    .PARAMETER NoDisplay
        Return the principals without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Get-AACServicePrincipalInsight
        Every workload identity with Azure access, the riskiest first.
    .EXAMPLE
        Get-AACServicePrincipalInsight -Kind ExternalApplication -NoDisplay | Select-Object ServicePrincipal, OwnerTenant, PrivilegedRoles
        Other tenants' applications with access to your Azure.
    .EXAMPLE
        Get-AACServicePrincipalInsight -ExpiryDays 60 -CsvPath .\Expiring.csv
        Credentials to rotate in the next two months.
    .OUTPUTS
        AAC.ServicePrincipalInsight
    #>
    [CmdletBinding()]
    [OutputType('AAC.ServicePrincipalInsight')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string[]] $ManagementGroupId,

        [ValidateSet('Application', 'ExternalApplication', 'ManagedIdentity')]
        [string[]] $Kind,

        [ValidateRange(1, 365)]
        [int] $ExpiryDays = 30,

        [ValidateRange(1, 1000)]
        [int] $SharedLimit = 10,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Service principals',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $request = @{ SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }); ExpiryDays = $ExpiryDays; SharedLimit = $SharedLimit; TenantId = [string]$(if ($script:AACSession) { $script:AACSession.TenantId }) }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Service principals' -Color 'mediumpurple' }
    $outcome = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
        $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
        Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"
        Update-AACProgress -Id 'read' -Indeterminate -Description 'Reading the service principals'' role assignments and the user-assigned identities'
        $read = Invoke-AACGraphBatch -Query ([ordered]@{
                roleAssignments = @{ Tenant = $true; Query = "authorizationresources | where type =~ 'microsoft.authorization/roleassignments' and tostring(properties.principalType) =~ 'ServicePrincipal' | project id, principalId = tolower(tostring(properties.principalId)), roleId = tolower(tostring(properties.roleDefinitionId)), scope = tolower(tostring(properties.scope))" }
                roleDefinitions = @{ Tenant = $true; Query = "authorizationresources | where type =~ 'microsoft.authorization/roledefinitions' | project id = tolower(id), roleName = tostring(properties.roleName)" }
                userIdentities  = @{ Tenant = $true; Query = "resources | where type =~ 'microsoft.managedidentity/userassignedidentities' | project id = tolower(id), name, principalId = tolower(tostring(properties.principalId))" }
                attached        = @{ Tenant = $true; Query = "resources | where isnotnull(identity.userAssignedIdentities) | project id, identities = identity.userAssignedIdentities" }
            }) -AllowFailure @('userIdentities', 'attached')
        # Role assignments in scope: under a subscription in scope, or above (management group, root).
        $inScope = @{}; foreach ($id in $scope.Ids) { $inScope[$id.ToLowerInvariant()] = $true }
        $read.Rows['roleAssignments'] = @($read.Rows['roleAssignments'] | Where-Object { $_ -and (-not ([string]$_['scope'] -match '^/subscriptions/([^/]+)') -or $inScope.Contains($Matches[1])) })
        $principals = @($read.Rows['roleAssignments'] | ForEach-Object { [string]$_['principalId'] } | Where-Object { $_ } | Select-Object -Unique)
        Update-AACProgress -Id 'read' -Complete -Description ('{0:N0} service principal(s) hold Azure roles' -f $principals.Count)

        Update-AACProgress -Id 'entra' -Indeterminate -Description "Looking up $($principals.Count) service principal(s) in Entra ID"
        $directory = Get-AACDirectoryObject -Id $principals -Property 'appOwnerOrganizationId', 'alternativeNames', 'passwordCredentials', 'keyCredentials'
        $apps = @{}
        if (-not $directory.Error) {
            $appIds = @($directory.Objects.Values | Where-Object { [string]$_['servicePrincipalType'] -eq 'Application' -and (-not $request.TenantId -or [string]$_['appOwnerOrganizationId'] -eq $request.TenantId) } | ForEach-Object { [string]$_['appId'] } | Where-Object { $_ } | Sort-Object -Unique)
            # Sorted, so the same principals always make the same requests (the directory lookup comes back in any order).
            if ($appIds.Count) {
                $q = [ordered]@{}
                for ($i = 0; $i -lt $appIds.Count; $i += 15) {
                    $filter = (@($appIds[$i..([Math]::Min($i + 14, $appIds.Count - 1))] | ForEach-Object { "'$_'" }) -join ',')
                    $q["apps$i"] = "https://graph.microsoft.com/v1.0/applications?`$filter=appId in ($filter)&`$select=appId,displayName,passwordCredentials,keyCredentials"
                }
                $answer = Read-AACGraphQuery -Query $q
                foreach ($key in @($answer.Data.Keys)) { foreach ($a in @($answer.Data[$key] | Where-Object { $_ })) { $apps[([string]$a['appId']).ToLowerInvariant()] = $a } }
            }
        }
        Update-AACProgress -Id 'entra' -Complete -Description ('Looked up {0:N0} principal(s) and {1:N0} app registration(s)' -f $directory.Objects.Count, $apps.Count)
        @{ Result = (ConvertTo-AACServicePrincipalInsight -Read $read -Directory $directory -Application $apps -TenantId $request.TenantId -ExpiryDays $request.ExpiryDays -SharedLimit $request.SharedLimit); Scope = $scope }
    }

    $principalRows = @($outcome.Result.Principals)
    if ($Kind) {
        $principalRows = @($principalRows | Where-Object { ($Kind -contains 'Application' -and $_.Kind -eq 'Application') -or ($Kind -contains 'ExternalApplication' -and $_.Kind -eq 'Application (external)') -or ($Kind -contains 'ManagedIdentity' -and $_.Kind -like 'Managed identity*') })
    }
    $s = $outcome.Result.Stats
    $rank = Get-AACSeverityRank
    $report = @{
        Subtitle = 'Service principals: every application and managed identity with Azure roles - what it is, what it can do, and its credentials'
        Facts    = [ordered]@{ Scope = $outcome.Scope.Label; Expiring = "within $ExpiryDays days" }
        Status   = $(if ($s.High) { 'Failed' } elseif (@($principalRows | Where-Object Findings).Count) { 'Warning' } else { 'Success' })
        Headline = "$($s.Principals) service principal(s) hold Azure roles: $($s.External) from other tenants, $($s.Managed) managed identit(ies), $($s.Expiring) with a credential expiring within $ExpiryDays days"
        Tiles    = @(
            @{ Value = '{0:N0}' -f $s.Principals; Label = 'with Azure roles'; Tone = 'info' }
            @{ Value = '{0:N0}' -f $s.External; Label = 'other tenants'' apps'; Tone = $(if ($s.External) { 'warn' } else { 'good' }); Table = 'principals'; Filters = @{ Kind = 'Application (external)' } }
            @{ Value = '{0:N0}' -f $s.Managed; Label = 'managed identities'; Tone = 'neutral' }
            @{ Value = '{0:N0}' -f $s.Expiring; Label = 'credentials expiring'; Tone = $(if ($s.Expiring) { 'warn' } else { 'good' }) }
            @{ Value = '{0:N0}' -f $s.High; Label = 'high findings'; Tone = $(if ($s.High) { 'bad' } else { 'good' }); Table = 'principals'; Filters = @{ Severity = 'High' } }
        )
        Notices  = @($outcome.Result.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
        Charts   = @(
            @{ Title = 'By kind'; Kind = 'donut'; CenterLabel = 'principals'; Items = @($principalRows | Group-Object { ($_.Kind -replace ':.*\)$', ')') } | Sort-Object Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count } }); Console = $true }
            @{ Title = 'Most role assignments'; Items = @($principalRows | Sort-Object RoleAssignments -Descending | Select-Object -First 10 | ForEach-Object { @{ Label = $_.ServicePrincipal; Value = $_.RoleAssignments; Filter = $_.ServicePrincipal } }); Table = 'principals'; Column = 'ServicePrincipal'; Tone = 'violet' }
        )
        Tables   = @(
            @{ Id = 'principals'; Title = 'Service principals with Azure roles'; Section = 'Principals'; Rows = $principalRows; Noun = 'principals'; GroupBy = @('Kind'); ConsoleLimit = 30
                Empty = 'No service principal holds an Azure role in scope.'; EmptyStatus = 'Info'
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'ServicePrincipal'; Label = 'Service principal'; Console = $true; Pdf = $true }
                    @{ Key = 'Kind'; Label = 'Kind'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'RoleAssignments'; Label = 'Roles'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'PrivilegedRoles'; Label = 'Privileged'; Console = $true; Pdf = $true }
                    @{ Key = 'AttachedResources'; Label = 'Attached to'; Type = 'number'; Console = $true }
                    @{ Key = 'NextExpiry'; Label = 'Next expiry'; Type = 'date'; Console = $true; Pdf = $true }
                    @{ Key = 'Findings'; Label = 'Findings'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Roles'; Label = 'Role assignments'; Type = 'wide' }
                    @{ Key = 'Credentials'; Label = 'Credentials' }
                    @{ Key = 'OwnerTenant'; Label = 'Owner tenant'; Type = 'mono' }
                    @{ Key = 'AppId'; Label = 'App ID'; Type = 'mono' }
                    @{ Key = 'ResourceId'; Label = 'Resource'; Type = 'mono' }
                ) }
        )
        Hint     = '-Kind narrows it; -ExpiryDays sets what expiring means; -NoDisplay returns the principals; -HtmlPath, -PdfPath or -CsvPath for a report.'
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $principalRows -Noun 'principal' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $principalRows -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
