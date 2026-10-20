function Invoke-AACGovernanceAssessment {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Assesses governance across the tenant in one run - the management
        group hierarchy, access, workload identities, policy remediation,
        Azure limits, tenant settings, tags, locks and recent changes - as
        a tabbed workbook, and as a Markdown page for a wiki.
    .DESCRIPTION
        Runs, read-only, the governance commands and puts their results
        together (in the spirit of the Azure Governance Visualizer):
          Hierarchy    Show-AACManagementGroupMap's model: each management
                       group, its subscriptions, policy and role assignments
          Access       Get-AACRoleAssignment: every role assignment, and the
                       custom roles
          Identities   Get-AACServicePrincipalInsight
          Policy       Get-AACPolicyRemediation
          Limits       Test-AACAzureLimit
          Settings     Get-AACGovernanceSetting
          Tags         Get-AACTagUsage
          Locks        Get-AACResourceLock
          Changes      Get-AACGovernanceChange (the last -Days)
        -Area runs only some. An area that fails is reported and the others
        still run.

        At the prompt: the totals and the findings that matter most (High
        and Medium, every area). -HtmlPath writes the workbook - Summary,
        Findings and a tab per area, the hierarchy as a tree; -PdfPath the
        same as a PDF; -CsvPath the findings; -MarkdownPath one Markdown
        page with the hierarchy as a Mermaid diagram and a table per area -
        for a GitHub or Azure DevOps wiki (-MarkdownFlavor), refreshed from a
        pipeline. -PassThru returns everything (AAC.GovernanceAssessment).

        Needs what the areas need: Reader on the scope (Reader on the tenant
        root group for its settings), and in Entra ID Directory.Read.All and
        Application.Read.All. -SkipEntra reads Azure only.
    .PARAMETER SubscriptionId
        Only these subscriptions (and the management groups above them).
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups (at any depth).
    .PARAMETER Area
        Only these areas: Hierarchy, Access, Identities, Policy, Limits,
        Settings, Tags, Locks, Changes.
    .PARAMETER Days
        How far back the Changes area looks. Default 30.
    .PARAMETER RequiredTag
        Tags every resource should carry (the Tags area checks their
        coverage).
    .PARAMETER SkipEntra
        Don't read Entra ID (Access, Identities and Changes show principals
        by ID; Identities is skipped).
    .PARAMETER SkipPim
        Don't read PIM in the Access area.
    .PARAMETER CsvPath
        Write the findings to this CSV file.
    .PARAMETER HtmlPath
        Write the workbook as an interactive HTML report.
    .PARAMETER PdfPath
        Write the workbook as a PDF report.
    .PARAMETER MarkdownPath
        Write the assessment as a Markdown page.
    .PARAMETER MarkdownFlavor
        GitHub (the default: ```mermaid blocks) or AzureDevOps (::: mermaid
        blocks).
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the assessment.
    .PARAMETER NoDisplay
        Return the assessment without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Invoke-AACGovernanceAssessment -HtmlPath .\Governance.html
        The whole governance workbook for every subscription the account can see.
    .EXAMPLE
        Invoke-AACGovernanceAssessment -ManagementGroupId 'mg-landingzones' -MarkdownPath .\wiki\Governance.md -MarkdownFlavor AzureDevOps -NoDisplay
        The landing zones' governance as an Azure DevOps wiki page - from a pipeline.
    .EXAMPLE
        Invoke-AACGovernanceAssessment -Area Access, Limits, Settings -PdfPath .\Governance.pdf
        Three areas, as a PDF.
    .OUTPUTS
        AAC.GovernanceAssessment, with -PassThru or -NoDisplay
    #>
    [CmdletBinding()]
    [OutputType('AAC.GovernanceAssessment')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string[]] $ManagementGroupId,

        [ValidateSet('Hierarchy', 'Access', 'Identities', 'Policy', 'Limits', 'Settings', 'Tags', 'Locks', 'Changes')]
        [string[]] $Area = @('Hierarchy', 'Access', 'Identities', 'Policy', 'Limits', 'Settings', 'Tags', 'Locks', 'Changes'),

        [ValidateRange(1, 365)]
        [int] $Days = 30,

        [string[]] $RequiredTag,

        [switch] $SkipEntra,

        [switch] $SkipPim,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $MarkdownPath,

        [ValidateSet('GitHub', 'AzureDevOps')]
        [string] $MarkdownFlavor = 'GitHub',

        [string] $Title = 'Azure governance assessment',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $scopeArgs = @{}
    if ($SubscriptionId) { $scopeArgs.SubscriptionId = $SubscriptionId }
    if ($ManagementGroupId) { $scopeArgs.ManagementGroupId = $ManagementGroupId }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Governance assessment' -Color 'deepskyblue3_1' }

    # --- Each area: the command, quietly; a failure is noted and the others run ---------------------------
    $notices = [System.Collections.Generic.List[string]]::new()
    $results = [ordered]@{}
    $run = {
        param([string] $Name, [scriptblock] $Work)
        if ($Area -notcontains $Name) { return }
        try { $results[$Name] = @(& $Work) }
        catch { $notices.Add("The $($Name.ToLowerInvariant()) area couldn't be assessed: $($_.Exception.Message -replace '\s+', ' ')"); $results[$Name] = @() }
    }
    $hierarchy = @()
    if ($Area -contains 'Hierarchy') {
        try {
            $built = Invoke-AACProgress -ScriptBlock { Read-AACManagementGroupMap @scopeArgs }
            $hierarchy = @($built.Map.Hierarchy)
            $results['Hierarchy'] = $hierarchy
        }
        catch { $notices.Add("The hierarchy area couldn't be assessed: $($_.Exception.Message -replace '\s+', ' ')"); $results['Hierarchy'] = @() }
    }
    & $run 'Access' { Get-AACRoleAssignment @scopeArgs -IncludeCustomRole -SkipPim:$SkipPim -SkipEntra:$SkipEntra -NoDisplay }
    if ($SkipEntra -and $Area -contains 'Identities') { $notices.Add('The identities area needs Entra ID: skipped (-SkipEntra).') }
    elseif ($Area -contains 'Identities') { & $run 'Identities' { Get-AACServicePrincipalInsight @scopeArgs -NoDisplay } }
    & $run 'Policy' { Get-AACPolicyRemediation @scopeArgs -NoDisplay }
    & $run 'Limits' { Test-AACAzureLimit @scopeArgs -NoDisplay }
    & $run 'Settings' { Get-AACGovernanceSetting @scopeArgs -NoDisplay }
    & $run 'Tags' { $tagArgs = @{} + $scopeArgs; if ($RequiredTag) { $tagArgs.RequiredTag = $RequiredTag }; Get-AACTagUsage @tagArgs -NoDisplay }
    & $run 'Locks' { Get-AACResourceLock @scopeArgs -NoDisplay }
    & $run 'Changes' { Get-AACGovernanceChange @scopeArgs -Days $Days -SkipEntra:$SkipEntra -NoDisplay }

    $isType = { param($Row, [string] $Type) $Row -and $Row.PSObject.TypeNames -contains $Type }
    $access = @(if ($results.Contains('Access')) { $results['Access'] | Where-Object { & $isType $_ 'AAC.RoleAssignment' } })
    $customRoles = @(if ($results.Contains('Access')) { $results['Access'] | Where-Object { & $isType $_ 'AAC.CustomRole' } })
    $rowsOf = { param([string] $Name) @(if ($results.Contains($Name)) { $results[$Name] }) }

    # --- The findings that matter: High and Medium, every area ------------------------------------------------
    $findings = [System.Collections.Generic.List[object]]::new()
    $add = {
        param([string] $AreaName, [string] $Severity, [string] $Item, [string] $Finding, [string] $Action = '')
        if ($Severity -notin 'Critical', 'High', 'Medium') { return }
        $f = [pscustomobject][ordered]@{ Severity = $Severity; Area = $AreaName; Item = $Item; Finding = $Finding; Action = $Action }
        $f.PSObject.TypeNames.Insert(0, 'AAC.GovernanceFinding')
        $findings.Add($f)
    }
    foreach ($r in $access) { & $add 'Access' $r.Severity "$($r.Role) for $($r.Principal) on $($r.Scope)" $r.Findings }
    foreach ($r in $customRoles) { if ($r.OwnerEquivalent) { & $add 'Access' 'High' "Custom role $($r.Role)" 'Equivalent to Owner: every action, including granting access.' 'Narrow its actions, or use built-in roles.' } }
    foreach ($r in (& $rowsOf 'Identities')) { & $add 'Identities' $r.Severity $r.ServicePrincipal $r.Findings }
    foreach ($r in (& $rowsOf 'Policy')) { & $add 'Policy' $r.Severity "$($r.Policy) ($($r.Assignment))" $r.Findings }
    foreach ($r in (& $rowsOf 'Limits')) { & $add 'Limits' $(@{ Critical = 'High'; Warning = 'Medium'; OK = 'Info' }[$r.Status]) "$($r.Limit) on $($r.Scope)" "$($r.Used) of $($r.Maximum) ($($r.Percent)%)" $r.Advice }
    foreach ($r in (& $rowsOf 'Settings')) { if ($r.Status -eq 'Warning') { & $add 'Settings' 'Medium' "$($r.Setting) ($($r.Scope))" $r.Value $r.Recommendation } }
    foreach ($r in (& $rowsOf 'Tags')) { & $add 'Tags' $r.Severity "Tag $($r.Tag)" $r.Findings }
    foreach ($r in (& $rowsOf 'Locks')) { & $add 'Locks' $r.Severity "$($r.Scope)" $r.Findings }
    foreach ($r in (& $rowsOf 'Changes')) { & $add 'Changes' $r.Severity "$($r.Kind) $($r.Name) ($($r.Change) by $($r.By))" $r.Note }
    $rank = Get-AACSeverityRank
    $findings = @($findings | Sort-Object -Property @{ Expression = { $rank.Rank[$_.Severity] } }, Area, Item)
    $high = @($findings | Where-Object Severity -In 'Critical', 'High').Count

    # --- Columns from the objects: badges for severity and status, numbers, dates, wide text -----------------
    $statusTones = @{ Critical = 'bad'; Warning = 'warn'; OK = 'good'; Info = 'info'; Locked = 'good'; Unlocked = 'warn' }
    $wide = 'Findings', 'Finding', 'Recommendation', 'Advice', 'Detail', 'Note', 'Roles', 'MemberNames', 'SampleValues', 'Value', 'Action', 'AssignableScopes'
    $facets = 'Severity', 'Status', 'Area', 'Kind', 'PrincipalType', 'ScopeType', 'Limit', 'Assignment', 'Change', 'Level', 'RoleType', 'Effect', 'LastTask', 'Privileged', 'Unused', 'OwnerEquivalent', 'Subscription'
    $columnsFor = {
        param([object[]] $Rows, [string[]] $Skip = @())
        $first = @($Rows | Where-Object { $_ }) | Select-Object -First 1
        if (-not $first) { return @() }
        $i = 0
        @(foreach ($p in $first.PSObject.Properties) {
                if ($Skip -contains $p.Name) { continue }
                $i++
                $c = @{ Key = $p.Name; Label = ($p.Name -creplace '(?<=[a-z])(?=[A-Z])', ' '); Pdf = ($i -le 6) }
                if ($p.Name -eq 'Severity') { $c.Type = 'badge'; $c.Tones = $rank.Tone }
                elseif ($p.Name -eq 'Status') { $c.Type = 'badge'; $c.Tones = $statusTones }
                elseif ($p.Value -is [datetime] -or $p.Name -match '(On|When|Expiry)$') { $c.Type = 'date' }
                elseif ($p.Value -is [int] -or $p.Value -is [long] -or $p.Value -is [double]) { $c.Type = 'number' }
                elseif ($p.Name -match 'Id$') { $c.Type = 'mono' }
                elseif ($wide -contains $p.Name) { $c.Type = 'wide' }
                if ($facets -contains $p.Name) { $c.Facet = $true }
                $c
            })
    }
    $areaTables = [ordered]@{
        Hierarchy  = @{ Id = 'hierarchy'; Title = 'Management groups'; Rows = $hierarchy; Note = 'Each management group: its parent and depth, the subscriptions directly in it and below, and the policy and role assignments made at it.' }
        Access     = @{ Id = 'access'; Title = 'Role assignments'; Rows = $access; Note = 'Every Azure role assignment that reaches the scope (Get-AACRoleAssignment), riskiest first; the custom roles below.' }
        Identities = @{ Id = 'identities'; Title = 'Service principals'; Rows = (& $rowsOf 'Identities'); Note = 'Applications and managed identities with Azure roles, and their credentials (Get-AACServicePrincipalInsight).' }
        Policy     = @{ Id = 'policy'; Title = 'Policy remediation'; Rows = (& $rowsOf 'Policy'); Note = 'DeployIfNotExists and Modify policies with resources they could fix, and their remediation tasks (Get-AACPolicyRemediation).' }
        Limits     = @{ Id = 'limits'; Title = 'Azure limits'; Rows = (& $rowsOf 'Limits'); Note = 'What each scope uses of the Azure limits, the closest first (Test-AACAzureLimit).' }
        Settings   = @{ Id = 'settings'; Title = 'Governance settings'; Rows = (& $rowsOf 'Settings'); Note = 'Management group hierarchy settings and diagnostics, subscriptions, Defender contacts, classic administrators, preview features, resource providers (Get-AACGovernanceSetting).' }
        Tags       = @{ Id = 'tags'; Title = 'Tags'; Rows = (& $rowsOf 'Tags'); Note = 'Every tag name, its coverage and values, and what is inconsistent (Get-AACTagUsage).' }
        Locks      = @{ Id = 'locks'; Title = 'Locks'; Rows = (& $rowsOf 'Locks'); Note = 'Every lock, and the critical resources no lock protects (Get-AACResourceLock).' }
        Changes    = @{ Id = 'changes'; Title = 'Changes'; Rows = (& $rowsOf 'Changes'); Note = "Policy and access created or updated in the last $Days days, and who did it (Get-AACGovernanceChange)." }
    }
    $tables = [System.Collections.Generic.List[object]]::new()
    $tables.Add(@{ Id = 'findings'; Title = 'Findings'; Section = 'Findings'; Rows = $findings; Noun = 'findings'; GroupBy = @('Area', 'Severity'); ConsoleLimit = 30
            Empty = 'No high or medium findings in any area.'; EmptyStatus = 'Success'
            Columns = @(
                @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                @{ Key = 'Area'; Label = 'Area'; Facet = $true; Console = $true; Pdf = $true }
                @{ Key = 'Item'; Label = 'Item'; Console = $true; Pdf = $true }
                @{ Key = 'Finding'; Label = 'Finding'; Type = 'wide'; Console = $true; Pdf = $true }
                @{ Key = 'Action'; Label = 'What to do'; Type = 'wide'; Pdf = $true }
            ) })
    $tabs = [System.Collections.Generic.List[object]]::new()
    $tabs.Add(@{ Name = 'Findings'; Badge = $findings.Count; Tone = $(if ($high) { 'bad' } elseif ($findings.Count) { 'warn' } else { 'good' }); Note = 'The high and medium findings of every area, worst first.' })
    foreach ($name in $areaTables.Keys) {
        if (-not $results.Contains($name)) { continue }
        $t = $areaTables[$name]
        $rows = @($t.Rows)
        $tables.Add(@{ Id = $t.Id; Title = $t.Title; Section = $name; Rows = $rows; Noun = 'rows'; NoConsole = $true; Columns = (& $columnsFor $rows @('Id', 'ScopeId', 'PrincipalId', 'RoleDefinitionId', 'AssignmentId', 'DefinitionId', 'ReferenceId', 'ResourceId', 'LimitName')) })
        if ($name -eq 'Access' -and $customRoles.Count) { $tables.Add(@{ Id = 'customRoles'; Title = 'Custom roles'; Section = $name; Rows = $customRoles; Noun = 'roles'; NoConsole = $true; Columns = (& $columnsFor $customRoles @('Id')) }) }
        $areaHigh = @($findings | Where-Object { $_.Area -eq $name -and $_.Severity -in 'Critical', 'High' }).Count
        $areaAll = @($findings | Where-Object Area -EQ $name).Count
        $tabs.Add(@{ Name = $name; Badge = $rows.Count; Tone = $(if ($areaHigh) { 'bad' } elseif ($areaAll) { 'warn' } else { 'info' }); Note = $t.Note })
    }

    # The hierarchy as a tree on the Summary tab.
    $tree = $null
    if ($hierarchy.Count) {
        $nodeOf = @{}
        foreach ($h in $hierarchy) { $nodeOf[$h.ManagementGroup] = @{ l = $(if (-not $h.Parent) { 't' } else { 'm' }); n = $h.ManagementGroup; d = $h.Name; c = @(@($h.SubscriptionsBelow, 'subscriptions'), @($h.PolicyAssignments, 'policy assignments'), @($h.RoleAssignments, 'role assignments')); k = [System.Collections.Generic.List[object]]::new() } }
        $roots = [System.Collections.Generic.List[object]]::new()
        foreach ($h in $hierarchy) { if ($h.Parent -and $nodeOf.Contains($h.Parent)) { $nodeOf[$h.Parent].k.Add($nodeOf[$h.ManagementGroup]) } else { $roots.Add($nodeOf[$h.ManagementGroup]) } }
        $tree = @{ Title = 'Management group hierarchy'; OpenTo = 'm'; Root = $(if ($roots.Count -eq 1) { $roots[0] } else { @{ l = 't'; n = 'Tenant'; d = ''; c = @(); k = $roots } }) }
    }

    $areasRun = @($results.Keys)
    $tiles = @(
        @{ Value = '{0:N0}' -f $high; Label = 'high findings'; Tone = $(if ($high) { 'bad' } else { 'good' }); Table = 'findings'; Filters = @{ Severity = 'High' } }
        @{ Value = '{0:N0}' -f ($findings.Count - $high); Label = 'medium findings'; Tone = $(if ($findings.Count - $high) { 'warn' } else { 'good' }); Table = 'findings'; Filters = @{ Severity = 'Medium' } }
        @{ Value = '{0:N0}' -f $hierarchy.Count; Label = 'management groups'; Tone = 'info' }
        @{ Value = '{0:N0}' -f $access.Count; Label = 'role assignments'; Tone = 'violet' }
        @{ Value = '{0:N0}' -f @(& $rowsOf 'Identities').Count; Label = 'workload identities'; Tone = 'neutral' }
        @{ Value = '{0:N0}' -f @(& $rowsOf 'Limits' | Where-Object Status -NE 'OK').Count; Label = 'limits near'; Tone = $(if (@(& $rowsOf 'Limits' | Where-Object Status -EQ 'Critical').Count) { 'bad' } else { 'warn' }) }
    )
    $report = @{
        Subtitle = 'Governance assessment: hierarchy, access, identities, policy, limits, settings, tags, locks and changes'
        Facts    = [ordered]@{ Scope = $(if ($ManagementGroupId) { "management group $($ManagementGroupId -join ', ')" } elseif ($SubscriptionId) { "$($SubscriptionId.Count) subscription(s)" } else { 'every subscription the account can see' }); Areas = ($areasRun -join ', ') }
        Status   = $(if ($high) { 'Failed' } elseif ($findings.Count) { 'Warning' } else { 'Success' })
        Headline = "$($findings.Count) finding(s) across $($areasRun.Count) area(s): $high high$(if ($findings.Count) { " - most in $(@($findings | Group-Object Area | Sort-Object Count -Descending)[0].Name)" })"
        Tiles    = $tiles
        Notices  = @($notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
        Charts   = @(
            @{ Title = 'Findings by area'; Items = @($findings | Group-Object Area | Sort-Object Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'findings'; Column = 'Area'; Tone = 'warn'; Console = $true }
            @{ Title = 'By severity'; Kind = 'donut'; CenterLabel = 'findings'; Items = @(foreach ($s in 'High', 'Medium') { $n = @($findings | Where-Object Severity -EQ $s).Count; if ($n) { @{ Label = $s; Value = $n; Tone = $rank.Tone[$s]; Filter = $s } } }); Table = 'findings'; Column = 'Severity' }
        )
        Tabs     = $tabs.ToArray()
        Tables   = $tables.ToArray()
        Hint     = '-Area runs some areas; -HtmlPath writes the workbook (a tab per area); -MarkdownPath a wiki page; -PassThru returns everything.'
    }
    if ($tree) { $report.Tree = $tree }

    if ($MarkdownPath) {
        $sections = [ordered]@{ Findings = @{ Note = 'The high and medium findings of every area, worst first.'; Rows = $findings; Columns = @('Severity', 'Area', 'Item', 'Finding', 'Action') } }
        $markdownColumns = @{ Access = @('Severity', 'Principal', 'PrincipalType', 'Role', 'ScopeType', 'Scope', 'Assignment'); Identities = @('Severity', 'ServicePrincipal', 'Kind', 'RoleAssignments', 'PrivilegedRoles', 'NextExpiry'); Policy = @('Severity', 'Assignment', 'Policy', 'NonCompliant', 'LastTask'); Limits = @('Status', 'Limit', 'ScopeType', 'Scope', 'Used', 'Maximum', 'Percent'); Settings = @('Status', 'Area', 'Scope', 'Setting', 'Value'); Tags = @('Severity', 'Tag', 'Resources', 'Coverage', 'Values'); Locks = @('Severity', 'Status', 'Level', 'ScopeType', 'Scope'); Changes = @('When', 'Change', 'Kind', 'Name', 'By'); Hierarchy = @('ManagementGroup', 'Parent', 'Depth', 'SubscriptionsBelow', 'PolicyAssignments', 'RoleAssignments') }
        foreach ($name in $areaTables.Keys) { if ($results.Contains($name) -and $name -ne 'Hierarchy') { $sections[$name] = @{ Note = $areaTables[$name].Note; Rows = @($areaTables[$name].Rows); Columns = $markdownColumns[$name] } } }
        if ($customRoles.Count) { $sections['Custom roles'] = @{ Rows = $customRoles; Columns = @('Role', 'Assignments', 'Unused', 'OwnerEquivalent', 'CanWriteRoleAssignments') } }
        Write-AACGovernanceMarkdown -Path (& $resolve $MarkdownPath) -Title $Title -Fact $report.Facts -Headline $report.Headline -Tile @($tiles | ForEach-Object { @{ Label = $_.Label; Value = $_.Value } }) -Hierarchy $hierarchy -Section $sections -Flavor $MarkdownFlavor
        if (-not $NoDisplay) { Write-AACMarkup "[grey58]Markdown: $([Spectre.Console.Markup]::Escape((& $resolve $MarkdownPath)))[/]" }
    }

    $assessment = [pscustomobject][ordered]@{
        PSTypeName        = 'AAC.GovernanceAssessment'
        Findings          = $findings
        Hierarchy         = $hierarchy
        RoleAssignments   = $access
        CustomRoles       = $customRoles
        ServicePrincipals = @(& $rowsOf 'Identities')
        PolicyRemediation = @(& $rowsOf 'Policy')
        Limits            = @(& $rowsOf 'Limits')
        Settings          = @(& $rowsOf 'Settings')
        Tags              = @(& $rowsOf 'Tags')
        Locks             = @(& $rowsOf 'Locks')
        Changes           = @(& $rowsOf 'Changes')
        Notices           = @($notices)
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $findings -Noun 'finding' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:($interactive -and -not ($CsvPath -or $HtmlPath -or $PdfPath)) -NoPaging:$NoPaging -Object @($assessment) -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
