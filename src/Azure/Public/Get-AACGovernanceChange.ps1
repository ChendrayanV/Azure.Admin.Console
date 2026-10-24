function Get-AACGovernanceChange {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Shows who changed policy and access in the last days - policy
        definitions, initiatives and assignments, custom roles and role
        assignments created or updated - with the author resolved to a name
        and the notable changes flagged.
    .DESCRIPTION
        Reads, read-only and tenant-wide in Azure Resource Graph, the
        created and updated times and authors Azure keeps on each policy
        definition, initiative and assignment (their metadata), custom role
        and role assignment, and looks the authors up in Entra ID.

        A row per change (AAC.GovernanceChange), newest first: when, created
        or updated, what, its name and scope, who, and Detail - the role and
        principal of a role assignment, the enforcement of a policy
        assignment. Medium: a privileged role assigned (Owner, Contributor,
        User Access Administrator, RBAC Administrator), a custom role
        changed, a policy assignment that does not enforce.

        Get-AACChangeHistory covers resources (Change Analysis); this covers
        the governance around them. Azure keeps only the latest update of
        each item: for every update, export the activity log. Reader is
        enough; Directory.Read.All for the authors' names.
    .PARAMETER SubscriptionId
        Only changes in these subscriptions (management group and root ones
        above them always count).
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups (at any depth).
    .PARAMETER Days
        How far back. Default 30.
    .PARAMETER Kind
        Only these: PolicyDefinition, Initiative, PolicyAssignment,
        CustomRole, RoleAssignment.
    .PARAMETER By
        Only changes by these people or applications (wildcards work).
    .PARAMETER SkipEntra
        Don't look up the authors: they are shown by ID.
    .PARAMETER CsvPath
        Write the changes to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report.
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the changes.
    .PARAMETER NoDisplay
        Return the changes without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Get-AACGovernanceChange
        The last 30 days of policy and access changes, newest first.
    .EXAMPLE
        Get-AACGovernanceChange -Days 7 -Kind RoleAssignment -NoDisplay | Where-Object Severity -EQ 'Medium'
        Privileged access granted this week.
    .EXAMPLE
        Get-AACGovernanceChange -Days 90 -By '*@contoso.com' -HtmlPath .\Changes.html
        A quarter's changes by people, as a report.
    .OUTPUTS
        AAC.GovernanceChange
    #>
    [CmdletBinding()]
    [OutputType('AAC.GovernanceChange')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string[]] $ManagementGroupId,

        [ValidateRange(1, 365)]
        [int] $Days = 30,

        [ValidateSet('PolicyDefinition', 'Initiative', 'PolicyAssignment', 'CustomRole', 'RoleAssignment')]
        [string[]] $Kind,

        [SupportsWildcards()]
        [string[]] $By,

        [switch] $SkipEntra,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Governance changes',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $request = @{ SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }); Days = $Days; Entra = -not $SkipEntra }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Governance changes' -Color 'gold1' }
    $outcome = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
        $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
        Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"
        $since = [datetime]::UtcNow.AddDays(-$request.Days)
        $window = "where todatetime(createdOn) > ago($($request.Days)d) or todatetime(updatedOn) > ago($($request.Days)d)"
        $policy = "createdOn = tostring(properties.metadata.createdOn), createdBy = tostring(properties.metadata.createdBy), updatedOn = tostring(properties.metadata.updatedOn), updatedBy = tostring(properties.metadata.updatedBy)"
        $atScope = "scope = tolower(substring(id, 0, indexof(tolower(id), '/providers/microsoft.authorization/')))"
        $query = [ordered]@{
            policyDefinitions = @{ Tenant = $true; Query = "policyresources | where type =~ 'microsoft.authorization/policydefinitions' and tostring(properties.policyType) =~ 'Custom' | project id, name = tostring(properties.displayName), $atScope, $policy | $window" }
            policySets        = @{ Tenant = $true; Query = "policyresources | where type =~ 'microsoft.authorization/policysetdefinitions' and tostring(properties.policyType) =~ 'Custom' | project id, name = tostring(properties.displayName), $atScope, $policy | $window" }
            policyAssignments = @{ Tenant = $true; Query = "policyresources | where type =~ 'microsoft.authorization/policyassignments' | project id, name = tostring(properties.displayName), scope = tolower(tostring(properties.scope)), enforcement = tostring(properties.enforcementMode), $policy | $window" }
            roleDefinitions   = @{ Tenant = $true; Query = "authorizationresources | where type =~ 'microsoft.authorization/roledefinitions' and tostring(properties.type) =~ 'CustomRole' | project id, name = tostring(properties.roleName), scope = tolower(tostring(properties.assignableScopes[0])), createdOn = tostring(properties.createdOn), createdBy = tostring(properties.createdBy), updatedOn = tostring(properties.updatedOn), updatedBy = tostring(properties.updatedBy) | $window" }
            roleAssignments   = @{ Tenant = $true; Query = "authorizationresources | where type =~ 'microsoft.authorization/roleassignments' | project id, name, scope = tolower(tostring(properties.scope)), roleId = tolower(tostring(properties.roleDefinitionId)), principalId = tostring(properties.principalId), principalType = tostring(properties.principalType), createdOn = tostring(properties.createdOn), createdBy = tostring(properties.createdBy), updatedOn = tostring(properties.updatedOn), updatedBy = tostring(properties.updatedBy) | $window" }
            roleNames         = @{ Tenant = $true; Query = "authorizationresources | where type =~ 'microsoft.authorization/roledefinitions' | project id = tolower(id), roleName = tostring(properties.roleName)" }
        }
        Update-AACProgress -Id 'read' -Total $query.Count -Description "Reading $($request.Days) days of policy and access changes"
        $read = Invoke-AACGraphBatch -Query $query -AllowFailure @($query.Keys) -OnProgress {
            param($QueryName, $Done, $Total)
            Update-AACProgress -Id 'read' -Increment 1 -Description "Read the $QueryName ($Done of $Total)"
        }
        Update-AACProgress -Id 'read' -Complete -Description 'Read the changes'

        $directory = $null
        if ($request.Entra) {
            $ids = @(foreach ($k in 'policyDefinitions', 'policySets', 'policyAssignments', 'roleDefinitions', 'roleAssignments') { foreach ($row in @($read.Rows[$k] | Where-Object { $_ })) { [string]$row['createdBy']; [string]$row['updatedBy']; [string]$row['principalId'] } })
            $ids = @($ids | Where-Object { $_ -match '^[0-9a-fA-F-]{36}$' } | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique)
            Update-AACProgress -Id 'authors' -Indeterminate -Description "Looking up $($ids.Count) author(s) and principal(s)"
            $directory = Get-AACDirectoryObject -Id $ids
            Update-AACProgress -Id 'authors' -Complete -Description ('Looked up {0:N0} author(s) and principal(s)' -f $directory.Objects.Count)
        }
        # In scope: the subscriptions in scope and anything above them (management groups, root).
        $subs = @{}; foreach ($id in $scope.Ids) { $subs[$id.ToLowerInvariant()] = $true }
        $groups = @{}; foreach ($s in $scope.Subscriptions) { foreach ($m in @($s['chain'])) { if ($m -is [System.Collections.IDictionary]) { $groups[([string]$m['name']).ToLowerInvariant()] = $true } } }
        $unscoped = -not @($scope.GraphScope).Count
        $inScope = {
            param([string] $Scope)
            if ($unscoped -or -not $Scope -or $Scope -eq '/') { return $true }
            if ($Scope -match '^/subscriptions/([^/]+)') { return $subs.Contains($Matches[1].ToLowerInvariant()) }
            if ($Scope -match '/managementgroups/([^/]+)') { return $groups.Contains($Matches[1].ToLowerInvariant()) }
            $true
        }.GetNewClosure()
        @{ Result = (ConvertTo-AACGovernanceChange -Read $read -Directory $directory -Since $since -InScope $inScope); Scope = $scope }
    }

    $changes = @($outcome.Result.Changes)
    if ($Kind) { $kinds = @{ PolicyDefinition = 'Policy definition'; Initiative = 'Initiative'; PolicyAssignment = 'Policy assignment'; CustomRole = 'Custom role'; RoleAssignment = 'Role assignment' }; $wanted = @($Kind | ForEach-Object { $kinds[$_] }); $changes = @($changes | Where-Object { $wanted -contains $_.Kind }) }
    if ($By) { $changes = @($changes | Where-Object { $author = $_.By; @($By | Where-Object { $author -like $_ }).Count }) }
    $notable = @($changes | Where-Object Severity -EQ 'Medium').Count
    $rank = Get-AACSeverityRank
    $report = @{
        Subtitle = 'Governance changes: policy and access created or updated, and who did it'
        Facts    = [ordered]@{ Scope = $outcome.Scope.Label; Window = "last $Days days"; Authors = $(if ($SkipEntra) { 'by ID (-SkipEntra)' } else { 'resolved in Entra ID' }) }
        Status   = $(if ($notable) { 'Warning' } else { 'Success' })
        Headline = $(if ($changes.Count) { "$($changes.Count) change(s) in $Days days by $(@($changes | ForEach-Object { $_.By } | Where-Object { $_ } | Select-Object -Unique).Count) author(s); $notable notable" } else { "No policy or access changes in the last $Days days." })
        Tiles    = @(
            @{ Value = '{0:N0}' -f $changes.Count; Label = 'changes'; Tone = 'info' }
            @{ Value = '{0:N0}' -f $notable; Label = 'notable'; Tone = $(if ($notable) { 'warn' } else { 'good' }); Table = 'changes'; Filters = @{ Severity = 'Medium' } }
            @{ Value = '{0:N0}' -f @($changes | Where-Object Kind -EQ 'Role assignment').Count; Label = 'role assignments'; Tone = 'violet'; Table = 'changes'; Filters = @{ Kind = 'Role assignment' } }
            @{ Value = '{0:N0}' -f @($changes | Where-Object Kind -Like 'Polic*').Count; Label = 'policy changes'; Tone = 'info' }
        )
        Notices  = @($outcome.Result.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
        Charts   = @(
            @{ Title = 'By day'; Items = @($changes | Group-Object { $_.When.ToString('yyyy-MM-dd') } | Sort-Object Name | ForEach-Object { @{ Label = $_.Name; Value = $_.Count } }); Tone = 'info' }
            @{ Title = 'By kind'; Items = @($changes | Group-Object Kind | Sort-Object Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'changes'; Column = 'Kind'; Tone = 'violet'; Console = $true }
            @{ Title = 'Most changes by'; Items = @($changes | Where-Object By | Group-Object By | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'changes'; Column = 'By'; Tone = 'warn' }
        )
        Tables   = @(
            @{ Id = 'changes'; Title = 'Changes'; Section = 'Changes'; Rows = $changes; Noun = 'changes'; GroupBy = @('Kind', 'By'); ConsoleLimit = 30
                Empty = "No policy or access changes in the last $Days days."; EmptyStatus = 'Success'
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'When'; Label = 'When'; Type = 'datetime'; Console = $true; Pdf = $true }
                    @{ Key = 'Change'; Label = 'Change'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Kind'; Label = 'What'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Name'; Label = 'Name'; Console = $true; Pdf = $true }
                    @{ Key = 'Scope'; Label = 'Scope'; Console = $true }
                    @{ Key = 'By'; Label = 'By'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Note'; Label = 'Why it matters'; Type = 'wide' }
                    @{ Key = 'Id'; Label = 'ID'; Type = 'mono' }
                ) }
        )
        Hint     = '-Days sets the window; -Kind and -By narrow it; -NoDisplay returns the changes; -HtmlPath, -PdfPath or -CsvPath for a report.'
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $changes -Noun 'change' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $changes -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
