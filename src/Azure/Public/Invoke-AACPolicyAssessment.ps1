function Invoke-AACPolicyAssessment {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Assesses Azure Policy across a tenant, management group or set of
        subscriptions - what is assigned, how compliant it is (overall, by
        subscription, assignment, policy and category), the exemptions and
        the managed identities' roles - and what to improve, with a
        Spectre.Console view, objects, and CSV, PDF and interactive HTML
        reports. In the spirit of AzPolicyLens (github.com/Azure/AzPolicyLens).
    .DESCRIPTION
        Read-only (Reader is enough), Azure Resource Graph only - no Az
        modules. Every assignment, exemption, custom definition and
        initiative, and the management group hierarchy are read tenant-wide,
        so what a management group assigns to a subscription is there; the
        built-in definitions that are assigned are read by ID; compliance is
        read in the subscriptions in scope.

        Compliance is counted as AzPolicyLens counts it: each resource once,
        at its worst state (NonCompliant, then Compliant, Conflict, Exempt),
        and compliance = (compliant + exempt) / all - overall, by
        subscription, by management group, by assignment (and subscription),
        by policy and by category. Under -ComplianceWarningPercent (80) is
        Warning, under half of it Poor.

        Every assigned initiative is opened up (InitiativePolicies, and the
        initiative-policies CSV and HTML table): each member policy with its
        effect - an effect override on the assignment included - the value
        each of its parameters ends up with (from the assignment, else the
        initiative or the policy's default, as noted) and its compliance.
        For one row per policy and parameter, see Get-AACAssignedPolicy
        -ExpandPolicySet.

        The findings (each with its severity, what was found and what to do):
          Assignments  definitions assigned directly (not in an initiative),
                       DoNotEnforce, a definition that can't be found,
                       below the compliance threshold, deprecated or preview
                       policies assigned, excluded scopes that don't exist,
                       the same definition assigned twice on a scope path,
                       Deny with no non-compliance message
          Identity     DeployIfNotExists and Modify assignments with no
                       managed identity, or one missing the roles their
                       policies list
          Exemptions   expired, expiring within -ExemptionWarningDays (30),
                       never expiring, for an assignment that is gone
          Definitions  unassigned custom definitions and initiatives, unused
                       policy definition groups, the same control under
                       different group names, no category in the metadata
          Compliance   subscriptions below the threshold

        -Audience Platform (the default; AzPolicyLens's detailed wiki) is for
        the team that runs Azure Policy: everything, with hidden- metadata and
        tags. Application (its basic wiki) is for an application team: their
        assignments, compliance and exemptions, without the unassigned
        definitions, metadata hygiene or hidden- metadata.

        What you get depends on where the command runs:
          at the prompt    tiles, compliance by subscription and category,
                           the assignments least compliant first, the
                           exemptions that need attention and the High and
                           Medium findings, a page at a time
          piped onward     the AAC.PolicyAssignmentReport objects, each with
                           its Compliance, PolicyStates,
                           InitiativePolicies and Findings
          -PassThru        the view and the objects
          -NoDisplay       the objects only
        -CsvPath (a folder) writes a CSV per table. -HtmlPath writes an
        interactive report - the management group hierarchy as a tree with
        each level's compliance, then every table; -PdfPath a PDF.
    .PARAMETER ManagementGroupId
        Assess this management group and everything under it.
    .PARAMETER SubscriptionId
        Assess these subscriptions, and every assignment that reaches them -
        from their management groups too.
    .PARAMETER Audience
        Platform (the default): everything. Application: what an application
        team needs - no unassigned definitions, metadata hygiene or hidden-
        metadata.
    .PARAMETER ComplianceWarningPercent
        Compliance under this percentage (80 by default) is a Warning, under
        half of it Poor - and an assignment or subscription under it is a
        finding.
    .PARAMETER ExemptionWarningDays
        Exemptions expiring within this many days (30 by default) are
        flagged.
    .PARAMETER CsvPath
        A folder to write a CSV per table to.
    .PARAMETER PdfPath
        Write a PDF report to this file.
    .PARAMETER HtmlPath
        Write an interactive HTML report to this file.
    .PARAMETER Title
        The PDF and HTML reports' title.
    .PARAMETER PassThru
        Show the view and also return the objects.
    .PARAMETER NoDisplay
        Return the objects without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once instead of a page at a time.
    .EXAMPLE
        Connect-AAC
        Invoke-AACPolicyAssessment
        Azure Policy across every subscription and management group the account can see.
    .EXAMPLE
        Invoke-AACPolicyAssessment -ManagementGroupId 'mg-landingzones' -HtmlPath .\out\Policy.html -PdfPath .\out\Policy.pdf -CsvPath .\out\policy
        A landing zone's policy, with every report.
    .EXAMPLE
        Invoke-AACPolicyAssessment -SubscriptionId 00000000-0000-0000-0000-000000000000 -Audience Application -HtmlPath .\Policy.html
        An application team's report: the policies on their subscription, how compliant it is, and their exemptions.
    .EXAMPLE
        Invoke-AACPolicyAssessment -NoDisplay | Where-Object { $_.Rating -ne 'Good' } | Select-Object Assignment, Scope, CompliancePercent, NonCompliant
        The assignments under the compliance threshold.
    .EXAMPLE
        (Invoke-AACPolicyAssessment -NoDisplay | Where-Object Assignment -Like '*PostgreSQL*').InitiativePolicies | Format-Table Policy, Effect, Parameters, CompliancePercent
        The policies inside an initiative assignment: effect, parameter values and compliance.
    .OUTPUTS
        AAC.PolicyAssignmentReport (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding(DefaultParameterSetName = 'Tenant')]
    [OutputType('AAC.PolicyAssignmentReport')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ManagementGroup')]
        [ValidateNotNullOrEmpty()]
        [string] $ManagementGroupId,

        [Parameter(Mandatory, ParameterSetName = 'Subscription')]
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [ValidateSet('Platform', 'Application')]
        [string] $Audience = 'Platform',

        [ValidateRange(1, 99)]
        [int] $ComplianceWarningPercent = 80,

        [ValidateRange(1, 365)]
        [int] $ExemptionWarningDays = 30,

        [string] $CsvPath,

        [string] $PdfPath,

        [string] $HtmlPath,

        [string] $Title = 'Azure Policy assessment',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    # A failure anywhere below ends as a Spectre.Console error panel and this
    # command's own terminating error; a stopped pipeline just returns.
    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $showView = $interactive -and -not ($CsvPath -or $PdfPath -or $HtmlPath)
    $returnObjects = $PassThru -or $NoDisplay -or $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    # Read here, not inside the progress block (it runs in Invoke-AACProgress's scope).
    $request = @{
        ManagementGroupId        = $ManagementGroupId
        SubscriptionId           = @($SubscriptionId | Where-Object { $_ })
        Audience                 = $Audience
        ComplianceWarningPercent = $ComplianceWarningPercent
        ExemptionWarningDays     = $ExemptionWarningDays
        CsvPath                  = & $resolve $CsvPath
        PdfPath                  = & $resolve $PdfPath
        HtmlPath                 = & $resolve $HtmlPath
        Title                    = $Title
    }

    if ($interactive) {
        Write-AACRule -Title 'Azure Admin Console :: Azure Policy assessment' -Color 'deepskyblue3_1'
    }
    $state = Invoke-AACProgress -ScriptBlock {
        $null = Get-AACAccessToken
        $rowsOf = { param($Read, [string] $Key) @(if ($Read.Rows.Contains($Key)) { $Read.Rows[$Key] }) | Where-Object { $null -ne $_ } }
        $rowsLike = { param($Read, [string] $Prefix) @(foreach ($key in @($Read.Rows.Keys)) { if ($key -like "$Prefix*") { $Read.Rows[$key] } }) | Where-Object { $null -ne $_ } }
        $notices = [System.Collections.Generic.List[string]]::new()

        # --- 1. Discovery: the hierarchy, assignments, exemptions, custom definitions ------------------------------------
        $queries = Get-AACPolicyAssessmentQuery -Stage Discovery
        $labels = @{ subscriptions = 'subscriptions'; managementGroups = 'management groups'; assignments = 'policy assignments'; exemptions = 'policy exemptions'; customDefinitions = 'custom policy definitions'; customInitiatives = 'custom initiatives'; roleDefinitions = 'role definitions' }
        Update-AACProgress -Id 'discover' -Total $queries.Count -Description 'Reading the management groups, subscriptions, assignments, exemptions and custom definitions'
        $discovery = Invoke-AACGraphBatch -Query $queries -AllowFailure @('exemptions', 'roleDefinitions', 'customDefinitions', 'customInitiatives') -OnProgress {
            param($Name, $Done, $Total)
            Update-AACProgress -Id 'discover' -Increment 1 -Description "Read the $($labels[$Name]) ($Done of $Total)"
        }
        foreach ($key in $discovery.Errors.Keys) { $notices.Add("The $($labels[$key]) couldn't be read: $($discovery.Errors[$key])") }
        $subscriptions = @(& $rowsOf $discovery 'subscriptions')
        $groups = @(& $rowsOf $discovery 'managementGroups')
        $assignments = @(& $rowsOf $discovery 'assignments')
        $exemptions = @(& $rowsOf $discovery 'exemptions')
        if ($request.ManagementGroupId -and -not @($groups | Where-Object { [string]$_['name'] -eq $request.ManagementGroupId }).Count) {
            $problem = [System.InvalidOperationException]::new("No management group named '$($request.ManagementGroupId)' was found.")
            $problem.Data['AACHint'] = 'Use the management group''s ID (its name, not its display name), and check your account can read it.'
            throw $problem
        }
        $missing = @($request.SubscriptionId | Where-Object { $wanted = $_; -not @($subscriptions | Where-Object { [string]$_['subscriptionId'] -eq $wanted }).Count })
        foreach ($item in $missing) { Write-Warning "Subscription $item wasn't found, or your account can't read it; it's left out." }
        if ($request.SubscriptionId.Count -and $missing.Count -eq $request.SubscriptionId.Count) {
            $problem = [System.InvalidOperationException]::new('None of those subscriptions was found.')
            $problem.Data['AACHint'] = 'Check the subscription IDs, and that your account has Reader on them.'
            throw $problem
        }
        Update-AACProgress -Id 'discover' -Complete -Description ('Found {0:N0} assignment(s), {1:N0} exemption(s), {2:N0} management group(s) and {3:N0} subscription(s)' -f $assignments.Count, $exemptions.Count, $groups.Count, $subscriptions.Count)

        # --- 2. The built-in definitions assigned (Resource Graph by ID, then Resource Manager) ---------------------------------
        $definitions = @{}
        foreach ($row in @(& $rowsOf $discovery 'customDefinitions') + @(& $rowsOf $discovery 'customInitiatives')) { $definitions[([string]$row['id']).ToLowerInvariant()] = $row }
        $wanted = { param([string[]] $Ids) @($Ids | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() } | Where-Object { -not $definitions.Contains($_) } | Sort-Object -Unique) }
        $fetch = {
            param([string[]] $Ids)
            if (-not $Ids.Count) { return }
            $read = Invoke-AACGraphBatch -Query (Get-AACPolicyAssessmentQuery -Stage Definitions -Id $Ids) -AllowFailure @() -OnProgress { param($Name, $Done, $Total) Update-AACProgress -Id 'definitions' -Increment 1 }
            foreach ($row in @(& $rowsLike $read 'definitions')) { $definitions[([string]$row['id']).ToLowerInvariant()] = $row }
            # Resource Graph doesn't have them all (definitions at a scope it doesn't index): Resource Manager.
            $left = @($Ids | Where-Object { -not $definitions.Contains($_) })
            if ($left.Count) {
                $answers = Invoke-AACArmParallel -Uri @($left | ForEach-Object { "$_`?api-version=2023-04-01" })
                foreach ($id in $left) {
                    $answer = $answers["$id`?api-version=2023-04-01"]
                    if (-not $answer -or $answer.Error -or $answer.Body -isnot [System.Collections.IDictionary]) { continue }
                    $p = $answer.Body['properties']
                    $definitions[$id] = @{ id = [string]$answer.Body['id']; name = [string]$answer.Body['name']; type = [string]$answer.Body['type']; displayName = [string]$p['displayName']; description = [string]$p['description']; policyType = [string]$p['policyType']; mode = [string]$p['mode']; version = [string]$p['version']; metadata = $p['metadata']; parameters = $p['parameters']; rule = $p['policyRule']; members = $p['policyDefinitions']; groups = $p['policyDefinitionGroups'] }
                }
            }
        }
        $assignedIds = & $wanted @($assignments | ForEach-Object { [string]$_['definitionId'] })
        Update-AACProgress -Id 'definitions' -Description "Reading the $($assignedIds.Count) built-in definition(s) and initiative(s) assigned" -Indeterminate
        & $fetch $assignedIds
        # Then the policies inside the assigned initiatives.
        $memberIds = & $wanted @($assignments | ForEach-Object { $set = $definitions[([string]$_['definitionId']).ToLowerInvariant()]; if ($set) { @($set['members']) | Where-Object { $_ } | ForEach-Object { [string]$_['policyDefinitionId'] } } })
        & $fetch $memberIds
        $unreadDefinitions = @(& $wanted @($assignedIds + $memberIds)).Count
        Update-AACProgress -Id 'definitions' -Complete -Description ('Read {0:N0} definition(s) and initiative(s){1}' -f $definitions.Count, $(if ($unreadDefinitions) { ", $unreadDefinitions not readable" }))

        # --- 3. The managed identities' roles ------------------------------------------------------------------------------
        $principals = @($assignments | ForEach-Object {
                $identity = $_['identity']
                if ($identity -is [System.Collections.IDictionary]) {
                    [string]$identity['principalId']
                    if ($identity['userAssignedIdentities'] -is [System.Collections.IDictionary]) { foreach ($user in $identity['userAssignedIdentities'].Values) { [string]$user['principalId'] } }
                }
            } | Where-Object { $_ })
        $roles = @()
        if ($principals.Count) {
            Update-AACProgress -Id 'roles' -Description "Reading the roles of $($principals.Count) managed identit$(if ($principals.Count -eq 1) { 'y' } else { 'ies' })" -Indeterminate
            $read = Invoke-AACGraphBatch -Query (Get-AACPolicyAssessmentQuery -Stage Roles -Id $principals) -AllowFailure @()
            $roles = @(& $rowsLike $read 'roles')
            Update-AACProgress -Id 'roles' -Complete -Description ('Read {0:N0} role assignment(s) of the assignments'' managed identities' -f $roles.Count)
        }

        # --- 4. Compliance in the subscriptions in scope -------------------------------------------------------------------
        $scope = @{}
        if ($request.SubscriptionId.Count) { $scope.SubscriptionId = $request.SubscriptionId }
        elseif ($request.ManagementGroupId) { $scope.ManagementGroupId = @($request.ManagementGroupId) }
        $queries = Get-AACPolicyAssessmentQuery -Stage Compliance
        $labels = @{ complianceBySubscription = 'compliance by subscription'; complianceByAssignment = 'compliance by assignment'; complianceByPolicy = 'compliance by policy' }
        Update-AACProgress -Id 'compliance' -Total $queries.Count -Description 'Reading the compliance states'
        $compliance = Invoke-AACGraphBatch @scope -Query $queries -AllowFailure @($queries.Keys) -OnProgress {
            param($Name, $Done, $Total)
            Update-AACProgress -Id 'compliance' -Increment 1 -Description "Read the $($labels[$Name]) ($Done of $Total)"
        }
        foreach ($key in $compliance.Errors.Keys) { $notices.Add("The $($labels[$key]) couldn't be read: $($compliance.Errors[$key])") }
        Update-AACProgress -Id 'compliance' -Complete -Description ('Read the compliance of {0:N0} subscription(s) and {1:N0} assignment(s)' -f @(& $rowsOf $compliance 'complianceBySubscription').Count, @(& $rowsOf $compliance 'complianceByAssignment' | ForEach-Object { $_['assignmentId'] } | Sort-Object -Unique).Count)

        # --- 5. The assessment ----------------------------------------------------------------------------------------------
        Update-AACProgress -Id 'assess' -Description 'Assessing the assignments, compliance, exemptions and definitions' -Indeterminate
        $assessment = ConvertTo-AACPolicyAssessment -Subscription $subscriptions -ManagementGroup $groups -Assignment $assignments -Exemption $exemptions -Definition $definitions `
            -RoleAssignment $roles -RoleDefinition @(& $rowsOf $discovery 'roleDefinitions') -ComplianceBySubscription @(& $rowsOf $compliance 'complianceBySubscription') `
            -ComplianceByAssignment @(& $rowsOf $compliance 'complianceByAssignment') -ComplianceByPolicy @(& $rowsOf $compliance 'complianceByPolicy') `
            -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId -Audience $request.Audience -ComplianceWarningPercent $request.ComplianceWarningPercent -ExemptionWarningDays $request.ExemptionWarningDays
        if ($unreadDefinitions) { $notices.Add("$unreadDefinitions definition(s) or initiative(s) couldn't be read, so their names, effects and roles are missing.") }
        $assessment.Notices = $notices.ToArray()
        $stats = $assessment.Stats
        Update-AACProgress -Id 'assess' -Complete -Description ('Assessed {0:N0} assignment(s): {1} compliant, {2} high, {3} medium, {4} low finding(s)' -f $stats.Assignments, $(if ($null -ne $stats.CompliancePercent) { "$($stats.CompliancePercent)%" } else { 'no data' }), $stats.High, $stats.Medium, $stats.Low)

        $detail = [ordered]@{ Scope = if ($request.ManagementGroupId) { "management group $($request.ManagementGroupId)" } elseif ($request.SubscriptionId.Count) { "subscription(s) $($request.SubscriptionId -join ', ')" } else { 'every subscription and management group the account can see' } }
        $detail['Audience'] = if ($request.Audience -eq 'Platform') { 'Platform team (everything)' } else { 'Application team' }
        $detail['Thresholds'] = "compliance under $($request.ComplianceWarningPercent)% is a warning; exemptions expiring within $($request.ExemptionWarningDays) days"
        if ($request.CsvPath) {
            Update-AACProgress -Id 'csv' -Description 'Writing the CSV files' -Indeterminate
            $files = @(Write-AACPolicyAssessmentCsv -Assessment $assessment -Path $request.CsvPath)
            Update-AACProgress -Id 'csv' -Complete -Description "CSV: $($files.Count) file(s) in $($request.CsvPath)"
        }
        $null = Invoke-AACExport -PdfPath $request.PdfPath -WritePdf {
            Write-AACPolicyAssessmentPdf -Assessment $assessment -Path $request.PdfPath -Title $request.Title -Detail $detail
        } -HtmlPath $request.HtmlPath -WriteHtml {
            Write-AACPolicyAssessmentHtml -Assessment $assessment -Path $request.HtmlPath -Title $request.Title -Detail $detail
        }
        @{ Assessment = $assessment; Scope = $detail }
    }

    $assessment = $state.Assessment
    if ($showView) {
        Invoke-AACPagedOutput -NoPaging:$NoPaging -ScriptBlock {
            Show-AACPolicyAssessmentView -Assessment $assessment -Scope $state.Scope
        }
    }
    elseif ($interactive) {
        foreach ($notice in @($assessment.Notices)) { Write-AACMarkup "[grey58]$([Spectre.Console.Markup]::Escape($notice))[/]" }
    }
    if ($returnObjects) {
        foreach ($item in $assessment.Assignments) {
            $id = $item.ResourceId
            $item | Add-Member -NotePropertyMembers ([ordered]@{
                    Compliance = @($assessment.AssignmentCompliance | Where-Object AssignmentId -EQ $id)
                    PolicyStates = @($assessment.Policies | Where-Object AssignmentId -EQ $id)
                    InitiativePolicies = @($assessment.InitiativePolicies | Where-Object AssignmentId -EQ $id)
                    Findings   = @($assessment.Findings | Where-Object ResourceId -EQ $id)
                }) -Force
            $item
        }
    }
}
