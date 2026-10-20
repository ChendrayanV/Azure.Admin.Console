function Get-AACRoleAssignment {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Lists every Azure role assignment - root, management groups,
        subscriptions, resource groups and resources - with who holds it and
        what they are, what the role can do, how far it reaches, whether it
        is standing or PIM, the groups' members, who created it - and flags
        orphaned assignments, risky grants and custom roles that are unused
        or as powerful as Owner.
    .DESCRIPTION
        The inventory under the access review: where Get-AACAccessReview
        says what to fix, this lists everything as it is. Reads, read-only:
          Resource Graph   every role assignment and definition (tenant-
                           wide, so management group and root assignments
                           that reach the scope count), the management
                           groups, the user-assigned identities and the
                           roles policies use
          PIM              each subscription's eligible assignments and
                           which active ones were activated just in time
          Microsoft Graph  the principals and the assignments' creators;
                           with -ExpandGroup, each group's members
                           (transitive)

        Each assignment (AAC.RoleAssignment):
          Principal        name, sign-in name, and its type: User, Guest,
                           Group, Application, Application (external - another
                           tenant's), Managed identity (system- or
                           user-assigned), or Deleted
          Role             name; Built-in or Custom; Privileged (Owner,
                           Contributor, User Access Administrator, RBAC
                           Administrator, or a custom role with every action
                           or able to grant access); CanWriteRoleAssignments
          Scope            type (Root, Management group, Subscription,
                           Resource group, Resource), name, and Reach - Direct,
                           or "Inherited by N subscription(s)"
          Assignment       Permanent, Activated (PIM) or Eligible (PIM)
          More             Members and MemberNames (groups, with
                           -ExpandGroup), Condition (ABAC), CreatedOn,
                           CreatedBy, EndsOn (eligible)
          Findings         and the worst one's Severity: High for a deleted
                           principal with a privileged role, a guest with
                           one, an application as Owner on a subscription or
                           above, a custom role equivalent to Owner; Medium for
                           orphaned assignments and Owner or User Access
                           Administrator given to a user directly; Low for
                           standing privileged access a person could hold
                           eligible
        The report also lists the custom roles (AAC.CustomRole): their
        assignments, whether a policy uses them, unused, equivalent to
        Owner, able to grant access.

        Reader on the scope; for Entra ID Directory.Read.All (GroupMember.
        Read.All for -ExpandGroup). What Graph or PIM refuses is left out,
        and said. -SkipEntra reads Azure only.
    .PARAMETER SubscriptionId
        Only these subscriptions (and the management group and root
        assignments that reach them).
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups (at any depth).
    .PARAMETER PrincipalType
        Only these principals: User, Guest, Group, Application,
        ManagedIdentity, Deleted.
    .PARAMETER RoleName
        Only these roles; wildcards work ('*Owner*').
    .PARAMETER ScopeType
        Only assignments at these scopes: Root, ManagementGroup,
        Subscription, ResourceGroup, Resource.
    .PARAMETER Privileged
        Only privileged roles.
    .PARAMETER WithFinding
        Only assignments with a finding.
    .PARAMETER ExpandGroup
        Read each group's members (transitive, up to 200 groups).
    .PARAMETER IncludeCustomRole
        Also return the custom roles (AAC.CustomRole), after the
        assignments.
    .PARAMETER SkipPim
        Don't read PIM (eligible and activated assignments).
    .PARAMETER SkipEntra
        Don't read Entra ID: principals are shown by ID and type.
    .PARAMETER CsvPath
        Write the assignments to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report (assignments and custom roles).
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the assignments.
    .PARAMETER NoDisplay
        Return the assignments without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Get-AACRoleAssignment
        Every role assignment the account can see, those with findings first.
    .EXAMPLE
        Get-AACRoleAssignment -SubscriptionId $sub -ExpandGroup -HtmlPath .\Rbac.html
        One subscription's assignments - including those inherited from management groups - with each group's members.
    .EXAMPLE
        Get-AACRoleAssignment -PrincipalType Guest, Deleted -Privileged -NoDisplay | Select-Object Principal, Role, Scope
        Privileged guests and orphaned privileged assignments.
    .EXAMPLE
        Get-AACRoleAssignment -RoleName 'Owner' -ScopeType ManagementGroup, Subscription -CsvPath .\Owners.csv
        Who is Owner at the top of the hierarchy, for review.
    .OUTPUTS
        AAC.RoleAssignment (and AAC.CustomRole, with -IncludeCustomRole)
    #>
    [CmdletBinding()]
    [OutputType('AAC.RoleAssignment')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string[]] $ManagementGroupId,

        [ValidateSet('User', 'Guest', 'Group', 'Application', 'ManagedIdentity', 'Deleted')]
        [string[]] $PrincipalType,

        [SupportsWildcards()]
        [string[]] $RoleName,

        [ValidateSet('Root', 'ManagementGroup', 'Subscription', 'ResourceGroup', 'Resource')]
        [string[]] $ScopeType,

        [switch] $Privileged,

        [switch] $WithFinding,

        [switch] $ExpandGroup,

        [switch] $IncludeCustomRole,

        [switch] $SkipPim,

        [switch] $SkipEntra,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Azure role assignments',

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
        ExpandGroup = [bool]$ExpandGroup; Pim = -not $SkipPim; Entra = -not $SkipEntra; TenantId = [string]$(if ($script:AACSession) { $script:AACSession.TenantId })
    }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Role assignments' -Color 'deepskyblue3_1' }
    $outcome = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
        $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
        Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"

        $query = Get-AACRoleAssignmentQuery
        Update-AACProgress -Id 'read' -Total $query.Count -Description 'Reading the role assignments and definitions'
        $read = Invoke-AACGraphBatch -Query $query -SubscriptionId $scope.GraphScope -AllowFailure @('managementGroups', 'userIdentities', 'policyRoles') -OnProgress {
            param($QueryName, $Done, $Total)
            Update-AACProgress -Id 'read' -Increment 1 -Description "Read the $QueryName ($Done of $Total)"
        }
        Update-AACProgress -Id 'read' -Complete -Description ('Read {0:N0} role assignment(s) and {1:N0} role definition(s)' -f @($read.Rows['roleAssignments']).Count, @($read.Rows['roleDefinitions']).Count)

        # PIM: eligible assignments, and which active ones were activated.
        $pim = $null
        if ($request.Pim) {
            $uris = [ordered]@{}
            foreach ($id in $scope.Ids) {
                $uris["eligible|$id"] = "/subscriptions/$id/providers/Microsoft.Authorization/roleEligibilityScheduleInstances?api-version=2020-10-01"
                $uris["active|$id"] = "/subscriptions/$id/providers/Microsoft.Authorization/roleAssignmentScheduleInstances?api-version=2020-10-01"
            }
            Update-AACProgress -Id 'pim' -Total ([Math]::Max(1, $uris.Count)) -Description "Reading PIM for $($scope.Ids.Count) subscription(s)"
            $answers = Invoke-AACArmParallel -Uri @($uris.Values) -OnProgress { param($PimDone, $PimTotal) Update-AACProgress -Id 'pim' -Increment 1 }
            $pim = @{ Eligible = [System.Collections.Generic.List[object]]::new(); Instances = [System.Collections.Generic.List[object]]::new(); Errors = [System.Collections.Generic.List[string]]::new(); Read = $false }
            foreach ($key in $uris.Keys) {
                $kind, $id = $key.Split('|')
                $answer = $answers[$uris[$key]]
                if (-not $answer -or $answer.Error) { $pim.Errors.Add("$($scope.Names[$id.ToLowerInvariant()]) ($kind): $(if ($answer) { $answer.Error } else { 'no answer' })"); continue }
                $pim.Read = $true
                foreach ($i in @($answer.Items | Where-Object { $null -ne $_ })) { if ($kind -eq 'eligible') { $pim.Eligible.Add($i) } else { $pim.Instances.Add($i) } }
            }
            Update-AACProgress -Id 'pim' -Complete -Description ('Read {0:N0} eligible assignment(s){1}' -f $pim.Eligible.Count, $(if ($pim.Errors.Count) { "; $($pim.Errors.Count) read(s) refused" }))
        }

        # Entra ID: the principals and creators, and the groups' members.
        $directory = $null
        $members = $null
        if ($request.Entra) {
            $ids = @(@($read.Rows['roleAssignments'] | Where-Object { $_ } | ForEach-Object { [string]$_['principalId']; [string]$_['createdBy'] }) + @(if ($pim) { $pim.Eligible | ForEach-Object { [string]$_['properties']['principalId'] } }) | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique)
            Update-AACProgress -Id 'principals' -Indeterminate -Description "Looking up $($ids.Count) principal(s) in Entra ID"
            $directory = Get-AACDirectoryObject -Id $ids -Property 'appOwnerOrganizationId'
            Update-AACProgress -Id 'principals' -Complete -Description ('Looked up {0:N0} principal(s){1}' -f $directory.Objects.Count, $(if ($directory.Error) { " - Graph refused: $($directory.Error)" }))
            if ($request.ExpandGroup -and -not $directory.Error) {
                $groups = @($directory.Objects.Keys | Where-Object { [string]$directory.Objects[$_]['@odata.type'] -like '*group' } | Select-Object -First 200)
                if ($groups.Count) {
                    $q = [ordered]@{}
                    foreach ($g in $groups) { $q[$g] = "https://graph.microsoft.com/v1.0/groups/$g/transitiveMembers?`$select=id,displayName,userPrincipalName&`$top=999" }
                    Update-AACProgress -Id 'members' -Total $q.Count -Description "Reading the members of $($q.Count) group(s)"
                    $answer = Read-AACGraphQuery -Query $q -OnDone { param($Key, $Failure, $GraphDone, $GraphTotal) Update-AACProgress -Id 'members' -Increment 1 }
                    $members = @{}
                    foreach ($g in $groups) {
                        if ($answer.Errors.Contains($g)) { $members[$g] = @{ Error = [string]$answer.Errors[$g] }; continue }
                        $people = @(@($answer.Data[$g]) | Where-Object { $_ })
                        $names = @($people | Select-Object -First 10 | ForEach-Object { if ($_['userPrincipalName']) { [string]$_['userPrincipalName'] } else { [string]$_['displayName'] } })
                        $members[$g] = @{ Count = $people.Count; Names = ($names -join ', ') + $(if ($people.Count -gt 10) { ", +$($people.Count - 10) more" } else { '' }) }
                    }
                    Update-AACProgress -Id 'members' -Complete -Description "Read the members of $($groups.Count) group(s)"
                }
            }
        }
        $result = ConvertTo-AACRoleAssignment -Read $read -Scope $scope -Pim $pim -Directory $directory -Members $members -TenantId $request.TenantId
        @{ Result = $result; Scope = $scope }
    }

    $assignments = @($outcome.Result.Assignments)
    if ($PrincipalType) {
        $types = @{ User = @('User'); Guest = @('Guest'); Group = @('Group', 'Group (foreign)'); Application = @('Application', 'Application (external)', 'Service principal'); ManagedIdentity = @('Managed identity (system-assigned)', 'Managed identity (user-assigned)'); Deleted = @('Deleted') }
        $wanted = @($PrincipalType | ForEach-Object { $types[$_] })
        $assignments = @($assignments | Where-Object { $wanted -contains $_.PrincipalType })
    }
    if ($RoleName) { $assignments = @($assignments | Where-Object { $role = $_.Role; @($RoleName | Where-Object { $role -like $_ }).Count }) }
    if ($ScopeType) { $scopes = @{ Root = 'Root'; ManagementGroup = 'Management group'; Subscription = 'Subscription'; ResourceGroup = 'Resource group'; Resource = 'Resource' }; $wantedScopes = @($ScopeType | ForEach-Object { $scopes[$_] }); $assignments = @($assignments | Where-Object { $wantedScopes -contains $_.ScopeType }) }
    if ($Privileged) { $assignments = @($assignments | Where-Object Privileged) }
    if ($WithFinding) { $assignments = @($assignments | Where-Object Findings) }

    $stats = $outcome.Result.Stats
    $customRoles = @($outcome.Result.CustomRoles)
    $rank = Get-AACSeverityRank
    $high = @($assignments | Where-Object Severity -EQ 'High').Count
    $findingCount = @($assignments | Where-Object Findings).Count
    $typeTones = @{ User = 'info'; Guest = 'warn'; Group = 'good'; Application = 'violet'; 'Application (external)' = 'bad'; 'Managed identity (system-assigned)' = 'neutral'; 'Managed identity (user-assigned)' = 'neutral'; Deleted = 'bad' }
    $kindTones = @{ Permanent = 'warn'; 'Activated (PIM)' = 'good'; 'Eligible (PIM)' = 'good' }
    $report = @{
        Subtitle = 'Role assignments: every Azure RBAC assignment at every scope - who, what, how far it reaches, and what is risky'
        Facts    = [ordered]@{ Scope = $outcome.Scope.Label; PIM = $(if ($SkipPim) { 'not read (-SkipPim)' } else { 'read' }); 'Entra ID' = $(if ($SkipEntra) { 'not read (-SkipEntra)' } else { 'read' }); Groups = $(if ($ExpandGroup) { 'members expanded' } else { 'not expanded (-ExpandGroup)' }) }
        Status   = $(if ($high) { 'Failed' } elseif ($findingCount) { 'Warning' } else { 'Success' })
        Headline = "$($assignments.Count) role assignment(s): $(@($assignments | Where-Object Privileged).Count) privileged, $(@($assignments | Where-Object Assignment -EQ 'Eligible (PIM)').Count) eligible in PIM, $findingCount with a finding ($high high)$(if ($stats.UnusedRoles -or $stats.OwnerRoles) { "; $($stats.UnusedRoles) unused custom role(s), $($stats.OwnerRoles) equivalent to Owner" })"
        Tiles    = @(
            @{ Value = '{0:N0}' -f $assignments.Count; Label = 'role assignments'; Tone = 'info' }
            @{ Value = '{0:N0}' -f @($assignments | Where-Object Privileged).Count; Label = 'privileged'; Tone = 'warn'; Table = 'assignments'; Filters = @{ Privileged = 'True' } }
            @{ Value = '{0:N0}' -f @($assignments | Where-Object Assignment -EQ 'Eligible (PIM)').Count; Label = 'eligible (PIM)'; Tone = 'good'; Table = 'assignments'; Filters = @{ Assignment = 'Eligible (PIM)' } }
            @{ Value = '{0:N0}' -f @($assignments | Where-Object { $_.PrincipalType -eq 'Deleted' -or $_.RoleType -eq 'Unknown' }).Count; Label = 'orphaned'; Tone = $(if ($stats.Orphaned) { 'bad' } else { 'good' }); Table = 'assignments'; Filters = @{ PrincipalType = 'Deleted' } }
            @{ Value = '{0:N0}' -f $high; Label = 'high findings'; Tone = $(if ($high) { 'bad' } else { 'good' }); Table = 'assignments'; Filters = @{ Severity = 'High' } }
            @{ Value = '{0:N0}' -f $customRoles.Count; Label = "custom roles ($($stats.UnusedRoles) unused)"; Tone = $(if ($stats.OwnerRoles) { 'bad' } elseif ($stats.UnusedRoles) { 'warn' } else { 'info' }); Table = 'customRoles' }
        )
        Notices  = @($outcome.Result.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
        Charts   = @(
            @{ Title = 'By principal type'; Kind = 'donut'; CenterLabel = 'assignments'; Items = @($assignments | Group-Object PrincipalType | Sort-Object Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Tone = $typeTones[$_.Name]; Filter = $_.Name } }); Table = 'assignments'; Column = 'PrincipalType'; Console = $true }
            @{ Title = 'By scope'; Items = @(foreach ($s in 'Root', 'Management group', 'Subscription', 'Resource group', 'Resource') { $n = @($assignments | Where-Object ScopeType -EQ $s).Count; if ($n) { @{ Label = $s; Value = $n; Filter = $s } } }); Table = 'assignments'; Column = 'ScopeType'; Tone = 'info' }
            @{ Title = 'Most assigned roles'; Items = @($assignments | Group-Object Role | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'assignments'; Column = 'Role'; Tone = 'violet' }
        )
        Tables   = @(
            @{ Id = 'assignments'; Title = 'Role assignments'; Section = 'Assignments'; Rows = $assignments; Noun = 'assignments'; GroupBy = @('ScopeType', 'Role', 'PrincipalType'); ConsoleLimit = 30
                Empty = 'No role assignment matches.'; EmptyStatus = 'Info'
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Principal'; Label = 'Principal'; Console = $true; Pdf = $true }
                    @{ Key = 'PrincipalType'; Label = 'Type'; Type = 'badge'; Tones = $typeTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Role'; Label = 'Role'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'ScopeType'; Label = 'Scope type'; Facet = $true; Console = $true }
                    @{ Key = 'Scope'; Label = 'Scope'; Console = $true; Pdf = $true }
                    @{ Key = 'Assignment'; Label = 'Assignment'; Type = 'badge'; Tones = $kindTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Reach'; Label = 'Reach' }
                    @{ Key = 'Findings'; Label = 'Findings'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'RoleType'; Label = 'Role type'; Facet = $true }
                    @{ Key = 'Privileged'; Label = 'Privileged'; Facet = $true }
                    @{ Key = 'CanWriteRoleAssignments'; Label = 'Can grant access'; Facet = $true }
                    @{ Key = 'Members'; Label = 'Members'; Type = 'number' }
                    @{ Key = 'MemberNames'; Label = 'Member names'; Type = 'wide' }
                    @{ Key = 'SignInName'; Label = 'Sign-in name' }
                    @{ Key = 'Condition'; Label = 'Condition' }
                    @{ Key = 'CreatedOn'; Label = 'Created'; Type = 'date' }
                    @{ Key = 'CreatedBy'; Label = 'Created by' }
                    @{ Key = 'EndsOn'; Label = 'Eligible until'; Type = 'date' }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                    @{ Key = 'PrincipalId'; Label = 'Principal ID'; Type = 'mono' }
                    @{ Key = 'ScopeId'; Label = 'Scope ID'; Type = 'mono' }
                ) }
            @{ Id = 'customRoles'; Title = 'Custom roles'; Section = 'Custom roles'; Rows = $customRoles; Noun = 'roles'; ConsoleLimit = 15
                Columns = @(
                    @{ Key = 'Role'; Label = 'Role'; Console = $true; Pdf = $true }
                    @{ Key = 'Assignments'; Label = 'Assignments'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'Unused'; Label = 'Unused'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'OwnerEquivalent'; Label = 'Equivalent to Owner'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'CanWriteRoleAssignments'; Label = 'Can grant access'; Facet = $true; Console = $true }
                    @{ Key = 'UsedByPolicy'; Label = 'Used by a policy'; Facet = $true }
                    @{ Key = 'Actions'; Label = 'Actions'; Type = 'number' }
                    @{ Key = 'AssignableScopes'; Label = 'Assignable scopes'; Type = 'wide'; Pdf = $true }
                ) }
        )
        Hint     = '-PrincipalType, -RoleName, -ScopeType, -Privileged and -WithFinding narrow it; -ExpandGroup reads groups'' members; -NoDisplay returns the assignments; -HtmlPath, -PdfPath or -CsvPath for a report.'
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $assignments -Noun 'assignment' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object (@($assignments) + @(if ($IncludeCustomRole) { $customRoles })) -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
