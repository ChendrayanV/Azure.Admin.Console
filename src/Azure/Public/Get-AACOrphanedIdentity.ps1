function Get-AACOrphanedIdentity {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Finds the identities nobody uses any more - role assignments to
        deleted principals, user-assigned identities attached to nothing,
        managed identities of deleted resources, service principals that
        haven't signed in for months, app registrations with only expired
        credentials or no owners - and the access each still holds.
    .DESCRIPTION
        Reads, read-only:
          Resource Graph     user-assigned identities and the resources (and
                             AKS clusters' kubelets) that use them; every
                             resource's system-assigned identity; the role
                             assignments and definitions, tenant-wide
          Resource Manager   the federated credentials of each user-assigned
                             identity nothing uses (a workload identity
                             federation counts as use)
          Microsoft Graph    the role assignments' principals (which still
                             exist), the tenant's application service
                             principals and managed identities, the app
                             registrations (credentials, owners) and the
                             service principals' last sign-in

        Each identity (AAC.OrphanedIdentity) has its kind, why it looks
        unused, its last sign-in, its role assignments (how many, which),
        credentials and owners, and what to do. Severity follows the access
        left behind: High with a privileged role (Owner, Contributor, User
        Access Administrator, RBAC Administrator), Medium with other roles
        or only expired credentials, Low with none.

        "Unused" is an inference: a quarterly job, a disaster-recovery
        pipeline or a break-glass app can be quiet for months. Confirm with
        the owner, disable before deleting. Reader in Azure; for Entra ID
        Directory.Read.All and Application.Read.All, and AuditLog.Read.All
        with Entra ID P1 for sign-in activity. -SkipEntra checks the
        user-assigned identities only.
    .PARAMETER SubscriptionId
        Only these subscriptions (role assignments at management group and
        root scope always count).
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups (at any depth).
    .PARAMETER Kind
        Only these kinds: DeletedPrincipal, UserAssignedIdentity,
        ManagedIdentity, Application.
    .PARAMETER Severity
        Only these severities (High, Medium, Low).
    .PARAMETER InactiveDays
        A service principal not signed in for this many days is inactive.
        Default 90.
    .PARAMETER SkipEntra
        Don't read Entra ID (Microsoft Graph): user-assigned identities
        only.
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
        Get-AACOrphanedIdentity
        Every identity that looks unused, the ones with the most access first.
    .EXAMPLE
        Get-AACOrphanedIdentity -Kind DeletedPrincipal -NoDisplay | Select-Object PrincipalId, Roles
        The role assignments left behind by deleted principals.
    .EXAMPLE
        Get-AACOrphanedIdentity -Kind Application -InactiveDays 180 -CsvPath .\out\StaleApps.csv
        Applications not signed in for six months, for review.
    .OUTPUTS
        AAC.OrphanedIdentity
    #>
    [CmdletBinding()]
    [OutputType('AAC.OrphanedIdentity')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string[]] $ManagementGroupId,

        [ValidateSet('DeletedPrincipal', 'UserAssignedIdentity', 'ManagedIdentity', 'Application')]
        [string[]] $Kind,

        [ValidateSet('High', 'Medium', 'Low')]
        [string[]] $Severity,

        [ValidateRange(30, 730)]
        [int] $InactiveDays = 90,

        [switch] $SkipEntra,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Orphaned identities',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $request = @{ SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }); InactiveDays = $InactiveDays; Entra = -not $SkipEntra; TenantId = [string]$(if ($script:AACSession) { $script:AACSession.TenantId }) }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Orphaned identities' -Color 'mediumpurple' }
    $outcome = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
        $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
        Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"
        $q = Get-AACOrphanedIdentityQuery
        Update-AACProgress -Id 'read' -Total $q.Graph.Count -Description 'Reading identities and role assignments'
        $read = Invoke-AACGraphBatch -Query $q.Graph -SubscriptionId $scope.GraphScope -AllowFailure @('attached', 'systemIdentities', 'roleDefinitions') -OnProgress {
            param($QueryName, $Done, $Total)
            Update-AACProgress -Id 'read' -Increment 1 -Description "Read the $QueryName ($Done of $Total)"
        }
        Update-AACProgress -Id 'read' -Complete -Description ('Read {0:N0} user-assigned identit(ies) and {1:N0} role assignment(s)' -f @($read.Rows['userIdentities']).Count, @($read.Rows['roleAssignments']).Count)
        $notices = [System.Collections.Generic.List[string]]::new()

        # Federated credentials of the user-assigned identities nothing is attached to.
        $federated = @{}
        $used = @{}
        foreach ($row in @($read.Rows['attached'] | Where-Object { $_ })) {
            if ($row['identities'] -is [System.Collections.IDictionary]) { foreach ($k in $row['identities'].Keys) { $used[([string]$k).ToLowerInvariant()] = $true } }
            if ($row['kubelet']) { $used[[string]$row['kubelet']] = $true }
        }
        $loose = @($read.Rows['userIdentities'] | Where-Object { $_ -and -not $used.Contains([string]$_['id']) -and $scope.Names.Contains(([string]$_['subscriptionId']).ToLowerInvariant()) })
        if ($loose.Count) {
            if ($loose.Count -gt 300) { $notices.Add("$($loose.Count) unattached identities: the federated credentials of the first 300 were read."); $loose = @($loose | Select-Object -First 300) }
            $uris = [ordered]@{}
            foreach ($row in $loose) { $uris[[string]$row['id']] = "$($row['id'])/federatedIdentityCredentials?api-version=2023-01-31" }
            Update-AACProgress -Id 'federated' -Total $uris.Count -Description "Reading the federated credentials of $($uris.Count) unattached identit(ies)"
            $answers = Invoke-AACArmParallel -Uri @($uris.Values) -OnProgress { param($FedDone, $FedTotal) Update-AACProgress -Id 'federated' -Increment 1 }
            foreach ($id in $uris.Keys) { $answer = $answers[$uris[$id]]; if ($answer -and -not $answer.Error) { $federated[$id] = @($answer.Items | Where-Object { $_ }).Count } }
            Update-AACProgress -Id 'federated' -Complete -Description ('Read the federated credentials of {0:N0} identit(ies)' -f $federated.Count)
        }

        $directory = $null
        $entra = $null
        if ($request.Entra) {
            $principals = @($read.Rows['roleAssignments'] | Where-Object { $_ } | ForEach-Object { ([string]$_['principalId']).ToLowerInvariant() } | Where-Object { $_ } | Select-Object -Unique)
            Update-AACProgress -Id 'directory' -Indeterminate -Description "Looking up $($principals.Count) principal(s) in Entra ID"
            $directory = if ($principals.Count) { Get-AACDirectoryObject -Id $principals } else { @{ Objects = @{}; Error = '' } }
            Update-AACProgress -Id 'directory' -Complete -Description ('Found {0:N0} of {1:N0} principal(s)' -f $directory.Objects.Count, $principals.Count)
            Update-AACProgress -Id 'entra' -Total $q.Entra.Count -Description 'Reading service principals, app registrations and sign-in activity'
            $entra = Read-AACGraphQuery -Query $q.Entra -OnDone { param($Key, $Failure, $GraphDone, $GraphTotal) Update-AACProgress -Id 'entra' -Increment 1 }
            Update-AACProgress -Id 'entra' -Complete -Description "Read $($q.Entra.Count - $entra.Errors.Count) of $($q.Entra.Count) Entra ID queries"
        }
        $result = ConvertTo-AACOrphanedIdentity -Read $read -Federated $federated -Directory $directory -Entra $entra -TenantId $request.TenantId -InactiveDays $request.InactiveDays -SubscriptionName $scope.Names
        @{ Result = $result; Scope = $scope; Notices = @($result.Notices) + $notices.ToArray() }
    }

    $identities = @($outcome.Result.Identities)
    if ($Kind) { $kinds = @{ DeletedPrincipal = 'Deleted principal'; UserAssignedIdentity = 'User-assigned identity'; ManagedIdentity = 'Managed identity'; Application = 'Application' }; $wanted = @($Kind | ForEach-Object { $kinds[$_] }); $identities = @($identities | Where-Object { $wanted -contains $_.Kind }) }
    if ($Severity) { $identities = @($identities | Where-Object { $Severity -contains $_.Severity }) }

    $rank = Get-AACSeverityRank
    $high = @($identities | Where-Object Severity -EQ 'High').Count
    $withAccess = @($identities | Where-Object RoleAssignments -GT 0).Count
    $kindTones = @{ 'Deleted principal' = 'bad'; 'User-assigned identity' = 'info'; 'Managed identity' = 'warn'; Application = 'violet' }
    $report = @{
        Subtitle = 'Orphaned identities: unused service principals, managed identities and leftover role assignments'
        Facts    = [ordered]@{ Scope = $outcome.Scope.Label; Inactive = "no sign-in for $InactiveDays days"; 'Entra ID' = $(if ($SkipEntra) { 'not read (-SkipEntra)' } else { 'read' }) }
        Status   = $(if ($high) { 'Failed' } elseif ($identities.Count) { 'Warning' } else { 'Success' })
        Headline = $(if ($identities.Count) { "$($identities.Count) identit(ies) look unused: $withAccess still hold role assignments, $high a privileged role" } else { 'No orphaned identities found.' })
        Tiles    = @(
            @{ Value = '{0:N0}' -f $identities.Count; Label = 'orphaned identities'; Tone = $(if ($identities.Count) { 'warn' } else { 'good' }) }
            @{ Value = '{0:N0}' -f $high; Label = 'with a privileged role'; Tone = $(if ($high) { 'bad' } else { 'good' }); Table = 'identities'; Filters = @{ Severity = 'High' } }
            @{ Value = '{0:N0}' -f @($identities | Where-Object Kind -EQ 'Deleted principal').Count; Label = 'deleted principals'; Tone = 'bad'; Table = 'identities'; Filters = @{ Kind = 'Deleted principal' } }
            @{ Value = '{0:N0}' -f @($identities | Where-Object Kind -EQ 'User-assigned identity').Count; Label = 'unattached identities'; Tone = 'info'; Table = 'identities'; Filters = @{ Kind = 'User-assigned identity' } }
            @{ Value = '{0:N0}' -f @($identities | Where-Object Kind -EQ 'Application').Count; Label = 'applications'; Tone = 'violet'; Table = 'identities'; Filters = @{ Kind = 'Application' } }
            @{ Value = '{0:N0}' -f $withAccess; Label = 'still hold roles'; Tone = $(if ($withAccess) { 'warn' } else { 'good' }) }
        )
        Notices  = @($outcome.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
        Charts   = @(
            @{ Title = 'By kind'; Kind = 'donut'; CenterLabel = 'identities'; Items = @($identities | Group-Object Kind | Sort-Object Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Tone = $kindTones[$_.Name]; Filter = $_.Name } }); Table = 'identities'; Column = 'Kind' }
            @{ Title = 'By severity'; Items = @(foreach ($s in 'High', 'Medium', 'Low') { $n = @($identities | Where-Object Severity -EQ $s).Count; if ($n) { @{ Label = $s; Value = $n; Tone = $rank.Tone[$s]; Filter = $s } } }); Table = 'identities'; Column = 'Severity'; Tone = 'warn'; Console = $true }
            @{ Title = 'Most role assignments'; Items = @($identities | Where-Object RoleAssignments | Sort-Object RoleAssignments -Descending | Select-Object -First 10 | ForEach-Object { @{ Label = $_.Identity; Value = $_.RoleAssignments; Filter = $_.Identity } }); Table = 'identities'; Column = 'Identity'; Tone = 'bad' }
        )
        Tables   = @(
            @{ Id = 'identities'; Title = 'Orphaned identities'; Section = 'Identities'; Rows = $identities; Noun = 'identities'; GroupBy = @('Kind', 'Severity'); ConsoleLimit = 30
                Empty = 'No orphaned identities found.'; EmptyStatus = 'Success'
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Kind'; Label = 'Kind'; Type = 'badge'; Tones = $kindTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Identity'; Label = 'Identity'; Console = $true; Pdf = $true }
                    @{ Key = 'RoleAssignments'; Label = 'Roles'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'Reason'; Label = 'Why'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'Roles'; Label = 'Role assignments'; Type = 'wide' }
                    @{ Key = 'LastSignIn'; Label = 'Last sign-in'; Type = 'date' }
                    @{ Key = 'DaysInactive'; Label = 'Days inactive'; Type = 'number' }
                    @{ Key = 'Credentials'; Label = 'Credentials' }
                    @{ Key = 'Owners'; Label = 'Owners'; Type = 'number' }
                    @{ Key = 'Remediation'; Label = 'What to do'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'AppId'; Label = 'App / client ID'; Type = 'mono' }
                    @{ Key = 'PrincipalId'; Label = 'Object ID'; Type = 'mono' }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                ) }
        )
        Hint     = '-Kind narrows it (DeletedPrincipal, UserAssignedIdentity, ManagedIdentity, Application); -InactiveDays sets what inactive means; -NoDisplay returns the identities; -HtmlPath, -PdfPath or -CsvPath for a report.'
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $identities -Noun 'identity' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $identities -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
