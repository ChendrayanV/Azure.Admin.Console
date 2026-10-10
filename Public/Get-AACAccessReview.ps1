function Get-AACAccessReview {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        A least-privilege access review of Azure and Entra ID: every Azure
        RBAC assignment (permanent, PIM-activated and eligible), classic
        administrator, Entra ID directory role and Microsoft Graph
        application permission - with who uses their access, what's too
        broad or standing, and a recommendation for each - ready to attest.
    .DESCRIPTION
        Reads, read-only:
          Azure RBAC         every role assignment and definition (Resource
                             Graph, tenant-wide - so management group and
                             root assignments that reach the scope count)
          PIM                each subscription's eligible assignments and
                             which active ones were activated just in time
          Classic admins     each subscription's (co-)administrators
          Activity           each subscription's Activity Log for the last
                             -ActivityDays (30): who made changes, so unused
                             write access shows
          Entra ID           the principals (users, guests, groups, service
                             principals, managed identities - and the deleted
                             ones), privileged users' last sign-in, the
                             directory roles (active, activated, eligible),
                             and the application permissions granted on
                             Microsoft Graph
        One row per assignment (AAC.AccessAssignment), each with its
        findings - standing privileged access that should be just-in-time,
        privileged guests, applications that can grant access or take over
        the tenant, disabled and dormant accounts, orphaned assignments,
        unused write access, wildcard custom roles, classic co-admins, too
        many Global Administrators, roles given to users directly - the
        worst finding's severity, a recommendation - Remove, Make eligible
        (PIM), Narrow the scope or role, Review usage, Use a group, or
        Keep - and the Action: what to do, in so many words.

        Service principals and managed identities are judged as the
        workloads they are: their elevated access is as much a risk as a
        person's (a leaked secret or a compromised workload acts with it,
        no MFA asked), but PIM needs a person to activate a role, so they
        are never told to be made eligible. They are told how to narrow
        the role and scope - Role Based Access Control Administrator with a
        condition in place of Owner, resource groups in place of the
        subscription - and how to protect the credential. Write access they
        haven't used in -ActivityDays is "Review usage", not "Remove": a
        monthly job or a disaster-recovery pipeline is quiet for weeks.

        For an attestation: -CsvPath writes every row with empty Decision
        and Reviewer columns to fill in and sign off; -HtmlPath and -PdfPath
        write the review as a report.

        Needs Reader on the scope; Microsoft Graph Directory.Read.All,
        RoleManagement.Read.Directory, Application.Read.All and (for last
        sign-ins) AuditLog.Read.All - what Graph refuses is left out, and
        said. -SkipEntra reads Azure only.
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups (at any depth).
    .PARAMETER ActivityDays
        How many days of Activity Log to read for unused access (0 to 90; 30
        by default; 0 skips it).
    .PARAMETER SkipEntra
        Don't read Entra ID roles and Graph application permissions (Azure
        RBAC is still reviewed; principals are still looked up).
    .PARAMETER Severity
        Only rows of these severities.
    .PARAMETER PrivilegedOnly
        Only privileged access (Owner, Contributor, User Access
        Administrator, RBAC Administrator, equivalent custom roles,
        privileged Entra roles and Graph permissions).
    .PARAMETER CsvPath
        Write every row to this CSV file - with Decision and Reviewer
        columns for the sign-off.
    .PARAMETER HtmlPath
        Write an interactive HTML report.
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the rows.
    .PARAMETER NoDisplay
        Return the rows without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Get-AACAccessReview -PrivilegedOnly
        Who holds privileged access, how, and what to change.
    .EXAMPLE
        Get-AACAccessReview -ManagementGroupId 'mg-corp' -CsvPath .\out\AccessReview.csv -HtmlPath .\out\AccessReview.html
        An attestation file and report for a management group.
    .EXAMPLE
        Get-AACAccessReview -NoDisplay | Where-Object Recommendation -EQ 'Make eligible (PIM)' | Select-Object Principal, Role, Scope
        The standing access to move into PIM.
    .OUTPUTS
        AAC.AccessAssignment
    #>
    [CmdletBinding()]
    [OutputType('AAC.AccessAssignment')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string[]] $ManagementGroupId,

        [ValidateRange(0, 90)]
        [int] $ActivityDays = 30,

        [switch] $SkipEntra,

        [ValidateSet('Critical', 'High', 'Medium', 'Low', 'Info')]
        [string[]] $Severity,

        [switch] $PrivilegedOnly,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Azure access review',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $request = @{ SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }); ActivityDays = $ActivityDays; SkipEntra = [bool]$SkipEntra }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Access review' -Color 'deepskyblue3_1' }
    $state = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
        $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
        Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"

        # --- Azure RBAC, tenant-wide --------------------------------------------------------------------------------
        Update-AACProgress -Id 'rbac' -Indeterminate -Description 'Reading the role assignments and definitions'
        $rbac = Invoke-AACGraphBatch -Query ([ordered]@{
                roleAssignments = @{ Tenant = $true; Query = "authorizationresources | where type =~ 'microsoft.authorization/roleassignments' | project id, principalId = tostring(properties.principalId), principalType = tostring(properties.principalType), roleId = tolower(tostring(properties.roleDefinitionId)), scope = tolower(tostring(properties.scope)), createdOn = tostring(properties.createdOn)" }
                roleDefinitions = @{ Tenant = $true; Query = "authorizationresources | where type =~ 'microsoft.authorization/roledefinitions' | project id = tolower(id), roleName = tostring(properties.roleName), roleType = tostring(properties.type), permissions = properties.permissions" }
            })
        $assignments = @($rbac.Rows['roleAssignments'] | Where-Object { $null -ne $_ })
        Update-AACProgress -Id 'rbac' -Complete -Description ('Read {0:N0} role assignment(s) and {1:N0} role definition(s)' -f $assignments.Count, @($rbac.Rows['roleDefinitions']).Count)

        # --- Per subscription: PIM, classic admins, activity -------------------------------------------------------------
        $uris = [ordered]@{}
        $now = [datetime]::UtcNow
        foreach ($id in $scope.Ids) {
            $uris["eligible|$id"] = "/subscriptions/$id/providers/Microsoft.Authorization/roleEligibilityScheduleInstances?api-version=2020-10-01"
            $uris["active|$id"] = "/subscriptions/$id/providers/Microsoft.Authorization/roleAssignmentScheduleInstances?api-version=2020-10-01"
            $uris["classic|$id"] = "/subscriptions/$id/providers/Microsoft.Authorization/classicAdministrators?api-version=2015-07-01"
            if ($request.ActivityDays) {
                $filter = [System.Uri]::EscapeDataString("eventTimestamp ge '$($now.AddDays(-$request.ActivityDays).ToString('o'))' and eventTimestamp le '$($now.ToString('o'))'")
                $uris["activity|$id"] = "/subscriptions/$id/providers/Microsoft.Insights/eventtypes/management/values?api-version=2015-04-01&`$filter=$filter&`$select=caller,eventTimestamp,status,authorization"
            }
        }
        Update-AACProgress -Id 'arm' -Total ([Math]::Max(1, $uris.Count)) -Description "Reading PIM, classic administrators$(if ($request.ActivityDays) { " and $($request.ActivityDays) days of Activity Log" }) for $($scope.Ids.Count) subscription(s)"
        $answers = Invoke-AACArmParallel -Uri @($uris.Values) -OnProgress { param($ArmDone, $ArmTotal) Update-AACProgress -Id 'arm' -Increment 1 }
        $eligible = [System.Collections.Generic.List[object]]::new()
        $instances = [System.Collections.Generic.List[object]]::new()
        $classic = [System.Collections.Generic.List[object]]::new()
        $activity = if ($request.ActivityDays) { @{} } else { $null }
        $unreadArm = [System.Collections.Generic.List[string]]::new()
        foreach ($key in $uris.Keys) {
            $kind, $id = $key.Split('|')
            $answer = $answers[$uris[$key]]
            if (-not $answer -or $answer.Error) { if ($kind -ne 'classic') { $unreadArm.Add("$kind for $($scope.Names[$id.ToLowerInvariant()]): $(if ($answer) { $answer.Error } else { 'no answer' })") }; continue }
            $items = @($answer.Items | Where-Object { $null -ne $_ })
            switch ($kind) {
                'eligible' { foreach ($i in $items) { $eligible.Add($i) } }
                'active' { foreach ($i in $items) { $instances.Add($i) } }
                'classic' { $classic.Add(@{ SubscriptionId = $id; Items = $items }) }
                'activity' {
                    foreach ($e in $items) {
                        $action = [string]$(if ($e['authorization'] -is [System.Collections.IDictionary]) { $e['authorization']['action'] })
                        if ($action -notmatch '/(write|delete|action)$') { continue }
                        $status = if ($e['status'] -is [System.Collections.IDictionary]) { [string]$e['status']['value'] } else { [string]$e['status'] }
                        if ($status -and $status -notin 'Succeeded', 'Started', 'Accepted') { continue }
                        $caller = ([string]$e['caller']).ToLowerInvariant()
                        $when = [datetime]::MinValue
                        if ($caller -and [datetime]::TryParse([string]$e['eventTimestamp'], [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$when)) {
                            if (-not $activity.Contains($caller) -or $activity[$caller] -lt $when) { $activity[$caller] = $when }
                        }
                    }
                }
            }
        }
        Update-AACProgress -Id 'arm' -Complete -Description ('Read {0:N0} eligible assignment(s){1}{2}' -f $eligible.Count, $(if ($null -ne $activity) { ", $($activity.Count) caller(s) with changes" }), $(if ($unreadArm.Count) { "; $($unreadArm.Count) read(s) failed" }))

        # --- Entra ID ------------------------------------------------------------------------------------------------------
        $graph = @{ Data = @{}; Errors = @{} }
        if (-not $request.SkipEntra) {
            Update-AACProgress -Id 'entra' -Indeterminate -Description 'Reading the Entra ID roles and the Microsoft Graph application permissions'
            $graphUri = 'https://graph.microsoft.com/v1.0'
            $graph = Read-AACGraphQuery -Query ([ordered]@{
                    entraAssignments = "$graphUri/roleManagement/directory/roleAssignments?`$select=id,principalId,roleDefinitionId,directoryScopeId"
                    entraEligibility = "$graphUri/roleManagement/directory/roleEligibilitySchedules?`$select=id,principalId,roleDefinitionId"
                    entraActive      = "$graphUri/roleManagement/directory/roleAssignmentScheduleInstances?`$select=principalId,roleDefinitionId,assignmentType"
                    entraDefinitions = "$graphUri/roleManagement/directory/roleDefinitions?`$select=id,displayName,templateId"
                    graphApp         = "$graphUri/servicePrincipals(appId='00000003-0000-0000-c000-000000000000')?`$select=id,appRoles"
                    graphGrants      = "$graphUri/servicePrincipals(appId='00000003-0000-0000-c000-000000000000')/appRoleAssignedTo?`$top=999"
                })
            Update-AACProgress -Id 'entra' -Complete -Description ('Read {0:N0} Entra ID role assignment(s) and {1:N0} Graph application permission(s)' -f @($graph.Data['entraAssignments']).Count, @($graph.Data['graphGrants']).Count)
        }
        $principalIds = @(@($assignments | ForEach-Object { [string]$_['principalId'] }) + @($eligible | ForEach-Object { [string]$_['properties']['principalId'] }) + @($graph.Data['entraAssignments'] + $graph.Data['entraEligibility'] + $graph.Data['graphGrants'] | Where-Object { $_ } | ForEach-Object { [string]$_['principalId'] }) | Where-Object { $_ } | Select-Object -Unique)
        Update-AACProgress -Id 'principals' -Indeterminate -Description "Looking up $($principalIds.Count) principal(s) in Entra ID"
        $directory = Get-AACDirectoryObject -Id $principalIds
        # The privileged users' last sign-in (needs AuditLog.Read.All and Entra ID P1).
        $privilegedNames = 'Owner', 'Contributor', 'User Access Administrator', 'Role Based Access Control Administrator'
        $roleNames = @{}
        foreach ($d in @($rbac.Rows['roleDefinitions'])) { if ($d) { $roleNames[([string]$d['id'] -replace '^.*/', '')] = [string]$d['roleName'] } }
        $users = @($assignments | Where-Object { $roleNames[([string]$_['roleId'] -replace '^.*/', '')] -in $privilegedNames } | ForEach-Object { ([string]$_['principalId']).ToLowerInvariant() } | Where-Object { $directory.Objects.Contains($_) -and [string]$directory.Objects[$_]['@odata.type'] -like '*user' } | Select-Object -Unique -First 300)
        $signIns = @{}
        $signInError = ''
        if ($users.Count -and -not $directory.Error) {
            $signInQuery = [ordered]@{}
            foreach ($u in $users) { $signInQuery[$u] = "https://graph.microsoft.com/v1.0/users/$($u)?`$select=id,signInActivity" }
            $signInRead = Read-AACGraphQuery -Query $signInQuery
            foreach ($u in $users) {
                $last = if ($signInRead.Data.Contains($u) -and $signInRead.Data[$u]['signInActivity']) { [string]$signInRead.Data[$u]['signInActivity']['lastSignInDateTime'] } else { '' }
                $when = [datetime]::MinValue
                if ($last -and [datetime]::TryParse($last, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$when)) { $signIns[$u] = $when }
            }
            $signInError = @($signInRead.Errors.Values | Where-Object { $_ }) | Select-Object -First 1
        }
        Update-AACProgress -Id 'principals' -Complete -Description ('Looked up {0:N0} principal(s){1}' -f $directory.Objects.Count, $(if ($directory.Error) { " - Graph refused: $($directory.Error)" }))

        Update-AACProgress -Id 'review' -Indeterminate -Description 'Reviewing every assignment'
        $chain = @{}
        foreach ($s in $scope.Subscriptions) { $chain[([string]$s['subscriptionId']).ToLowerInvariant()] = @(@($s['chain']) | Where-Object { $_ -is [System.Collections.IDictionary] } | ForEach-Object { ([string]$_['name']).ToLowerInvariant() }) }
        $appRoles = @{}
        if ($graph.Data['graphApp']) { foreach ($r in @($graph.Data['graphApp']['appRoles'])) { if ($r) { $appRoles[([string]$r['id']).ToLowerInvariant()] = [string]$r['value'] } } }
        $activated = @($graph.Data['entraActive'] | Where-Object { $_ -and [string]$_['assignmentType'] -eq 'Activated' } | ForEach-Object { "$(([string]$_['principalId']).ToLowerInvariant())|$(([string]$_['roleDefinitionId']).ToLowerInvariant())" })
        $review = @{
            Assignment = $assignments; Definition = @($rbac.Rows['roleDefinitions'] | Where-Object { $_ }); Eligibility = $eligible.ToArray(); ScheduleInstance = $instances.ToArray(); ClassicAdmin = $classic.ToArray()
            SignIn = $signIns; ActivityDays = $request.ActivityDays; SubscriptionName = $scope.Names; SubscriptionChain = $chain; InScope = $scope.Ids
            EntraAssignment = @($graph.Data['entraAssignments'] | Where-Object { $_ }); EntraEligibility = @($graph.Data['entraEligibility'] | Where-Object { $_ }); EntraDefinition = @($graph.Data['entraDefinitions'] | Where-Object { $_ }); EntraActivated = $activated
            AppGrant = @($graph.Data['graphGrants'] | Where-Object { $_ }); GraphAppRole = $appRoles
        }
        if (-not $directory.Error) { $review.Directory = $directory.Objects }
        if ($null -ne $activity) { $review.Activity = $activity }
        $result = ConvertTo-AACAccessReview @review
        $notices = [System.Collections.Generic.List[string]]::new()
        foreach ($n in $result.Notices) { $notices.Add($n) }
        foreach ($n in $unreadArm) { $notices.Add("Couldn't read the $n") }
        if ($signInError) { $notices.Add("Privileged users' last sign-in couldn't be read (AuditLog.Read.All and Entra ID P1): $signInError") }
        $graphLabels = @{ entraAssignments = 'Entra ID role assignments'; entraEligibility = 'eligible Entra ID roles'; entraActive = 'Entra ID role activations'; entraDefinitions = 'Entra ID role names'; graphApp = 'Microsoft Graph app roles'; graphGrants = 'Microsoft Graph application permissions' }
        foreach ($key in @($graph.Errors.Keys | Sort-Object)) { if ($graph.Errors[$key]) { $notices.Add("Microsoft Graph refused the $($graphLabels[$key]): $($graph.Errors[$key])") } }
        Update-AACProgress -Id 'review' -Complete -Description ('{0:N0} assignment(s): {1:N0} critical, {2:N0} high - {3:N0} to remove, {4:N0} to make eligible' -f $result.Stats.Assignments, $result.Stats.Critical, $result.Stats.High, $result.Stats.ToRemove, $result.Stats.ToEligible)
        @{ Result = $result; Scope = $scope; Notices = $notices.ToArray() }
    }

    $result = $state.Result
    $rows = @($result.Rows)
    if ($PrivilegedOnly) { $rows = @($rows | Where-Object Privileged -EQ 'Yes') }
    if ($Severity) { $rows = @($rows | Where-Object { $Severity -contains $_.Severity }) }
    $s = $result.Stats
    $rank = Get-AACSeverityRank
    $recommendTones = @{ Remove = 'bad'; 'Make eligible (PIM)' = 'warn'; 'Narrow the scope or role' = 'warn'; 'Review usage' = 'info'; 'Use a group' = 'info'; Keep = 'good' }
    $report = @{
        Subtitle = 'Access review: Azure RBAC, PIM, Entra ID roles and Microsoft Graph application permissions'
        Facts    = [ordered]@{ Scope = $state.Scope.Label; Activity = $(if ($ActivityDays) { "the last $ActivityDays day(s)" } else { 'not read' }); 'Entra ID' = $(if ($SkipEntra) { 'principals only (-SkipEntra)' } else { 'roles and Graph permissions' }) }
        Status   = $(if ($s.Critical -or $s.High) { 'Failed' } elseif ($s.ToRemove -or $s.ToEligible) { 'Warning' } else { 'Success' })
        Headline = "$($s.Assignments) assignment(s) for $($s.Principals) principal(s): $($s.Critical) critical, $($s.High) high - $($s.ToRemove) to remove, $($s.ToEligible) to make just-in-time"
        Tiles    = @(
            @{ Value = '{0:N0}' -f $s.Assignments; Label = 'assignments'; Tone = 'info'; Table = 'access' }
            @{ Value = '{0:N0}' -f $s.Privileged; Label = 'privileged'; Tone = 'violet'; Table = 'access'; Filters = @{ Privileged = 'Yes' } }
            @{ Value = '{0:N0}' -f $s.Standing; Label = 'standing privileged (users)'; Tone = $(if ($s.Standing) { 'bad' } else { 'good' }) }
            @{ Value = '{0:N0}' -f $s.Eligible; Label = 'eligible (PIM)'; Tone = 'good'; Table = 'access'; Filters = @{ Assignment = 'Eligible (PIM)' } }
            @{ Value = '{0:N0}' -f $s.Orphaned; Label = 'orphaned'; Tone = $(if ($s.Orphaned) { 'warn' } else { 'good' }) }
            @{ Value = $(if ($ActivityDays) { '{0:N0}' -f $s.Unused } else { '-' }); Label = 'unused write access'; Tone = $(if ($s.Unused) { 'warn' } else { 'good' }) }
            @{ Value = '{0:N0}' -f $s.Guests; Label = 'privileged guests'; Tone = $(if ($s.Guests) { 'bad' } else { 'good' }) }
            @{ Value = '{0:N0}' -f $s.RiskyApps; Label = 'apps with risky Graph access'; Tone = $(if ($s.RiskyApps) { 'bad' } else { 'good' }) }
        )
        Notices  = @($state.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
        Charts   = @(
            @{ Title = 'Recommendations'; Kind = 'donut'; CenterLabel = 'assignments'; Items = @($rows | Group-Object Recommendation | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Tone = $recommendTones[$_.Name]; Filter = $_.Name } }); Table = 'access'; Column = 'Recommendation'; Console = $true }
            @{ Title = 'Privileged access by principal type'; Items = @($rows | Where-Object Privileged -EQ 'Yes' | Group-Object PrincipalType | Sort-Object Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'access'; Column = 'PrincipalType'; Tone = 'violet' }
            @{ Title = 'Assignments by scope'; Items = @($rows | Group-Object ScopeLevel | Sort-Object Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'access'; Column = 'ScopeLevel'; Tone = 'info' }
        )
        Tables   = @(
            @{ Id = 'access'; Title = 'Access'; Section = 'Access'; Rows = $rows; Noun = 'assignments'; GroupBy = @('Severity', 'Recommendation', 'Principal', 'Role', 'Subscription', 'Source'); ConsoleLimit = 25
                Empty = 'No assignments match.'
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Principal'; Label = 'Principal'; Console = $true; Pdf = $true }
                    @{ Key = 'PrincipalType'; Label = 'Type'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Role'; Label = 'Role'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Scope'; Label = 'Scope'; Console = $true; Pdf = $true }
                    @{ Key = 'Assignment'; Label = 'Assignment'; Type = 'badge'; Tones = @{ Permanent = 'warn'; 'Activated (PIM)' = 'good'; 'Eligible (PIM)' = 'good' }; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Recommendation'; Label = 'Recommendation'; Type = 'badge'; Tones = $recommendTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Findings'; Label = 'Findings'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Action'; Label = 'What to do'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'SignInName'; Label = 'Sign-in name'; Type = 'mono' }
                    @{ Key = 'Privileged'; Label = 'Privileged'; Type = 'badge'; Tones = @{ Yes = 'violet'; No = 'neutral' }; Facet = $true }
                    @{ Key = 'ScopeLevel'; Label = 'Scope level'; Facet = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                    @{ Key = 'Source'; Label = 'Source'; Facet = $true }
                    @{ Key = 'Enabled'; Label = 'Enabled'; Type = 'badge'; Tones = @{ Yes = 'good'; No = 'bad' } }
                    @{ Key = 'LastSignIn'; Label = 'Last sign-in'; Type = 'datetime' }
                    @{ Key = 'LastActivity'; Label = 'Last change made'; Type = 'datetime' }
                    @{ Key = 'Created'; Label = 'Assigned'; Type = 'datetime' }
                    @{ Key = 'Decision'; Label = 'Decision' }
                    @{ Key = 'Reviewer'; Label = 'Reviewer' }
                ) }
        )
        Hint     = '-PrivilegedOnly or -Severity narrows the list; -CsvPath writes the attestation (Decision and Reviewer to fill in); -NoDisplay returns the rows.'
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $rows -Noun 'assignment' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $rows -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
