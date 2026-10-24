function Get-AACPolicyState {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Azure Policy compliance for every resource - one row per resource and
        policy - by management group, subscription or resource group, with a
        Spectre.Console view, objects, and CSV, PDF and interactive HTML
        reports.
    .DESCRIPTION
        Reads the Azure Policy states with an Azure Resource Graph KQL query
        (policyresources; Reader is enough, no Az modules), with the
        policies' and initiatives' display names, and the assignments' names,
        scopes and enforcement (read tenant-wide, as many are assigned at a
        management group):
          -ManagementGroupId   every subscription under these management
                               groups
          -SubscriptionId      these subscriptions
          -ResourceGroupName   only these resource groups (with either, or
                               in every subscription you can see)
          neither              every subscription you can see
        -ComplianceState keeps only those states (NonCompliant, Compliant,
        Exempt, Unknown, Conflict, Error) - in the query itself.

        One row per resource and policy (AAC.PolicyState): ComplianceState,
        Resource, ResourceType, ResourceGroup, SubscriptionName, Location,
        Policy, PolicySet (the initiative), Assignment, AssignmentScope,
        Enforcement, Effect, EvaluatedAt, and the IDs. From them: each
        resource's compliance (non-compliant when any policy finds it so),
        each assignment's, subscription's, resource group's and policy's.
        Rolled up exactly as the Azure portal does: a resource's state
        across its policies is the one that ranks first - Non-compliant,
        Compliant, Error, Conflicting, Protected, Exempt, Unknown - and
        compliance (%) is (Compliant + Exempt + Unknown + Protected
        resources) / every resource evaluated; Not started states aren't
        counted.

        Get-AACSecurityPosture -Section Policy shows the policy headline
        beside Defender for Cloud; this command is every state in detail.
        Both read the same query.

        What you get depends on where the command runs:
          at the prompt    tiles, compliance per subscription and resource
                           group, the assignments (least compliant first),
                           the policies with non-compliant resources and
                           each of those resources - a page at a time
          piped onward     the rows, with no view
          -PassThru        the view and the rows
          -NoDisplay       the rows only
        -CsvPath writes the rows. -HtmlPath writes an interactive report:
        tiles and charts that filter tables of every state, the resources,
        assignments, policies, subscriptions and resource groups - each
        searchable and downloadable as CSV. -PdfPath writes a PDF: the
        summary, the scopes, the assignments, and the non-compliant resources
        by policy.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups (their IDs).
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ResourceGroupName
        Only these resource groups.
    .PARAMETER ComplianceState
        Only these compliance states: NonCompliant, Compliant, Exempt,
        Unknown, Conflict, Error, Protected. Every state by default.
    .PARAMETER CsvPath
        Write every row to this CSV file.
    .PARAMETER PdfPath
        Write a PDF report to this file.
    .PARAMETER HtmlPath
        Write an interactive HTML report to this file.
    .PARAMETER Title
        The PDF and HTML reports' title.
    .PARAMETER PassThru
        Show the view and also return the rows.
    .PARAMETER NoDisplay
        Return the rows without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once instead of a page at a time.
    .EXAMPLE
        Connect-AAC
        Get-AACPolicyState
        Every policy state in every subscription you can see.
    .EXAMPLE
        Get-AACPolicyState -ManagementGroupId 'mg-landingzones' -HtmlPath .\out\Policy.html -PdfPath .\out\Policy.pdf -CsvPath .\out\Policy.csv
        One management group, as an HTML report, a PDF and a CSV file.
    .EXAMPLE
        Get-AACPolicyState -SubscriptionId '00000000-0000-0000-0000-000000000000' -ResourceGroupName 'rg-app', 'rg-data'
        Two resource groups of one subscription.
    .EXAMPLE
        Get-AACPolicyState -ComplianceState NonCompliant -NoDisplay | Group-Object Policy | Sort-Object Count -Descending | Select-Object Count, Name
        The policies with the most non-compliant resources.
    .OUTPUTS
        AAC.PolicyState (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.PolicyState')]
    param(
        [ValidateNotNullOrEmpty()]
        [string[]] $ManagementGroupId,

        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [ValidateNotNullOrEmpty()]
        [string[]] $ResourceGroupName,

        [ValidateSet('NonCompliant', 'Compliant', 'Exempt', 'Unknown', 'Conflict', 'Error', 'Protected')]
        [string[]] $ComplianceState,

        [string] $CsvPath,

        [string] $PdfPath,

        [string] $HtmlPath,

        [string] $Title = 'Azure Policy compliance',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    # A failure anywhere below ends as a Spectre.Console error panel and this
    # command's own terminating error, not a line inside the module. A stopped
    # pipeline (Select-Object -First, Ctrl+C) is no failure: just return - a
    # rethrow would stop the caller's whole script, not only this command.
    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $showView = $interactive -and -not ($CsvPath -or $PdfPath -or $HtmlPath)
    $returnObjects = $PassThru -or $NoDisplay -or $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $csvFullPath = & $resolve $CsvPath
    $pdfFullPath = & $resolve $PdfPath
    $htmlFullPath = & $resolve $HtmlPath

    if ($interactive) {
        Write-AACRule -Title 'Azure Admin Console :: Azure Policy compliance' -Color 'deepskyblue3_1'
    }
    $state = Invoke-AACProgress -ScriptBlock {
        $null = Get-AACAccessToken
        # The states in scope, and - tenant-wide - the names of the
        # assignments, subscriptions and management groups (Invoke-AACGraphBatch).
        $queries = [ordered]@{
            states           = Get-AACPolicyStateQuery -ComplianceState @($ComplianceState | Where-Object { $_ }) -ResourceGroupName @($ResourceGroupName | Where-Object { $_ })
            assignments      = @{ Tenant = $true; Query = (Get-AACDefenderQuery -Name 'PolicyAssignments')['PolicyAssignments'] }
            subscriptions    = @{ Tenant = $true; Query = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions' | project subscriptionId, name" }
            managementGroups = @{ Tenant = $true; Query = "resourcecontainers | where type =~ 'microsoft.management/managementgroups' | project name, displayName = tostring(properties.displayName)" }
        }
        $labels = @{ states = 'policy states'; assignments = 'policy assignments'; subscriptions = 'subscription names'; managementGroups = 'management group names' }
        Update-AACProgress -Id 'read' -Total $queries.Count -Description 'Reading Azure Policy states from Azure Resource Graph'
        $batch = Invoke-AACGraphBatch -Query $queries -SubscriptionId $SubscriptionId -ManagementGroupId $ManagementGroupId -AllowFailure 'managementGroups' -OnProgress {
            param($Name, $Done, $Total)
            Update-AACProgress -Id 'read' -Increment 1 -Description "Read the $($labels[$Name]) ($Done of $Total queries)"
        }
        $subscriptionNames = @{}
        foreach ($row in @($batch.Rows['subscriptions'])) { $subscriptionNames[([string]$row['subscriptionId']).ToLowerInvariant()] = [string]$row['name'] }
        $groupNames = @{}
        foreach ($row in @($batch.Rows['managementGroups'])) { $groupNames[([string]$row['name']).ToLowerInvariant()] = $(if ($row['displayName']) { [string]$row['displayName'] } else { [string]$row['name'] }) }
        $compliance = ConvertTo-AACPolicyState -Row @($batch.Rows['states']) -Assignment @($batch.Rows['assignments']) -SubscriptionName $subscriptionNames -ManagementGroupName $groupNames
        $stats = $compliance.Stats
        Update-AACProgress -Id 'read' -Complete -Description ('{0:N0} policy state(s) on {1:N0} resource(s): {2} compliant, {3:N0} non-compliant resource(s), {4:N0} assignment(s)' -f $stats.States, $stats.Resources, $(if ($null -ne $stats.ComplianceRate) { "$($stats.ComplianceRate)%" } else { 'none evaluated' }), $stats.NonCompliant, $stats.Assignments)

        $notices = [System.Collections.Generic.List[string]]::new()
        foreach ($name in @($ResourceGroupName | Where-Object { $_ })) {
            if (-not @($compliance.States | Where-Object ResourceGroup -EQ $name).Count) { $notices.Add("No policy states for resource group '$name': it has no resources, none is covered by a policy assignment, or the name is wrong.") }
        }
        if (-not $stats.States) { $notices.Add("No policy states were found$(if ($ComplianceState) { " in the state(s) $($ComplianceState -join ', ')" }): no policies are assigned in this scope, or they haven't been evaluated yet.") }

        $scope = [ordered]@{
            Scope = if ($SubscriptionId) { "subscription(s) $(@($SubscriptionId | ForEach-Object { if ($subscriptionNames.Contains($_.ToLowerInvariant())) { $subscriptionNames[$_.ToLowerInvariant()] } else { $_ } }) -join ', ')" } elseif ($ManagementGroupId) { "management group(s) $(@($ManagementGroupId | ForEach-Object { if ($groupNames.Contains($_.ToLowerInvariant())) { $groupNames[$_.ToLowerInvariant()] } else { $_ } }) -join ', ')" } else { 'every subscription the account can see' }
        }
        if ($ResourceGroupName) { $scope['Resource groups'] = $ResourceGroupName -join ', ' }
        if ($ComplianceState) { $scope['States'] = $ComplianceState -join ', ' }
        $compliance.Notice = $notices.ToArray()
        $null = Invoke-AACExport -CsvPath $csvFullPath -CsvObject @($compliance.States) -Noun 'policy state' -PdfPath $pdfFullPath -WritePdf {
            Write-AACPolicyStatePdf -Compliance $compliance -Path $pdfFullPath -Title $Title -Detail $scope
        } -HtmlPath $htmlFullPath -WriteHtml {
            Write-AACPolicyStateHtml -Compliance $compliance -Path $htmlFullPath -Title $Title -Detail $scope
        }
        @{ Compliance = $compliance; Scope = $scope }
    }

    if ($showView) {
        Invoke-AACPagedOutput -NoPaging:$NoPaging -ScriptBlock {
            Show-AACPolicyStateView -Compliance $state.Compliance -Scope $state.Scope
        }
    }
    elseif ($interactive) {
        foreach ($notice in @($state.Compliance.Notice)) { Write-AACMarkup "[grey58]$([Spectre.Console.Markup]::Escape($notice))[/]" }
    }
    if ($returnObjects) {
        $state.Compliance.States
    }
}
