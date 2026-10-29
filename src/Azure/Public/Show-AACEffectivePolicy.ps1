function Show-AACEffectivePolicy {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Shows the Azure Policy that applies to a resource - one that exists,
        or one you are about to deploy - and what each policy does to it:
        blocks, audits, changes or deploys, where it is assigned, its
        compliance state and why, and what exempts or leaves it out.
    .DESCRIPTION
        Read-only. Starts from the resource, not the assignment: every
        assignment on its path - its management groups, subscription,
        resource group and the resource itself - and, for an initiative,
        each member policy, with one verdict:
          Applies        the policy evaluates the resource
          Exempt         an exemption covers it (Waiver or Mitigated, all
                         policies or some, until when)
          Excluded       the assignment's notScopes leave it out
          Not selected   the assignment's resource selectors leave it out
          Not targeted   the rule is about other resource types (shown with
                         -IncludeNotApplicable)

        For each policy that applies: the effect in force - parameters
        resolved through the initiative and the assignment, then its
        overrides - and what it means here (Impact): Blocks (deny), Blocks
        delete (denyAction), Audits, Changes (modify, append), Deploys
        (deployIfNotExists), Manual, Disabled, or Reports only when the
        assignment isn't enforced. Also its non-compliance message, the
        assignment's managed identity (for remediation), definition version,
        regulatory controls, mode and parameters.

        An existing resource: Azure's compliance state, when it was last
        evaluated and - for a non-compliant one - why: the field, the value
        the policy expects and the value it found (Policy Insights).

        A planned resource (-Scope with -ResourceType): Azure Policy is
        asked what it would do (checkPolicyRestrictions) - what would refuse
        it, audit it or change it, and the values allowed: locations, SKUs,
        types, required tags. DeployIfNotExists and AuditIfNotExists act
        after a deployment, so they are listed as such.

        Findings: non-compliant resources a deny will refuse at their next
        deployment, remediation that can't run (no managed identity) or
        hasn't, exemptions ending within 30 days or expired, policies with
        no result yet.

        Needs Reader on the resources and their scopes; assignments,
        definitions and exemptions are read tenant-wide from Resource Graph,
        so those inherited from management groups you can read are included.
    .PARAMETER ResourceId
        The resources (also resource groups or subscriptions) to show. Takes
        ResourceId or Id from the pipeline.
    .PARAMETER SubscriptionId
        Show every resource in this subscription (with -ResourceGroupName and
        -ResourceType to narrow it) - at most -MaxResource.
    .PARAMETER ResourceGroupName
        With -SubscriptionId: only these resource groups.
    .PARAMETER ResourceType
        With -SubscriptionId: only these types. With -Scope: the type of the
        planned resource, e.g. Microsoft.Storage/storageAccounts.
    .PARAMETER Scope
        A planned resource: the subscription or resource group ID it will be
        deployed to (the resource group doesn't have to exist yet).
    .PARAMETER Location
        The planned resource's location.
    .PARAMETER Name
        The planned resource's name, for naming policies.
    .PARAMETER Tag
        The planned resource's tags.
    .PARAMETER Sku
        The planned resource's SKU name (sku.name).
    .PARAMETER Kind
        The planned resource's kind.
    .PARAMETER Property
        More of the planned resource's body, as Azure Resource Manager takes
        it, e.g. @{ properties = @{ minimumTlsVersion = 'TLS1_0' } }.
    .PARAMETER Impact
        Only policies with these impacts: Blocks, Blocks delete, Audits,
        Changes, Deploys, Manual, Reports only, Disabled, Exempt.
    .PARAMETER IncludeNotApplicable
        Also list the policies on the path that don't target the resource,
        with the reason.
    .PARAMETER SkipReason
        Don't read why non-compliant resources are non-compliant (one Policy
        Insights call per resource).
    .PARAMETER MaxResource
        With -SubscriptionId: the most resources to show (500 by default).
    .PARAMETER View
        Policy, Resource, Assignment, Exemption, Restriction or Finding: what
        is returned and written to -CsvPath.
    .PARAMETER CsvPath
        Write the -View rows to this CSV file.
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
        Connect-AAC
        Show-AACEffectivePolicy -ResourceId $storageId
        Every policy that applies to one storage account: what blocks, audits or changes it, where it is assigned, whether it complies and why not.
    .EXAMPLE
        Show-AACEffectivePolicy -SubscriptionId $sub -ResourceGroupName 'rg-orders' -HtmlPath .\orders-policy.html
        A resource group's resources, with a tabbed report: in force, non-compliant, exemptions, left out, the assignment chain.
    .EXAMPLE
        Show-AACEffectivePolicy -Scope "/subscriptions/$sub/resourceGroups/rg-new" -ResourceType 'Microsoft.Storage/storageAccounts' -Location 'westeurope' -Sku 'Standard_LRS' -Tag @{ CostCenter = 'cc-01' }
        Before deploying: what Azure Policy would refuse, audit, change or deploy for a new storage account there, and the values it allows.
    .EXAMPLE
        Show-AACEffectivePolicy -ResourceId $vmId -Impact Blocks, 'Blocks delete' -NoDisplay
        Only the policies that would refuse a change to the VM, or its deletion.
    .OUTPUTS
        AAC.EffectivePolicy, AAC.EffectivePolicyResource, AAC.EffectivePolicyAssignment, AAC.EffectivePolicyExemption, AAC.EffectivePolicyRestriction or AAC.EffectivePolicyFinding, by -View (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding(DefaultParameterSetName = 'Resource')]
    [OutputType('AAC.EffectivePolicy', 'AAC.EffectivePolicyResource', 'AAC.EffectivePolicyAssignment', 'AAC.EffectivePolicyExemption', 'AAC.EffectivePolicyRestriction', 'AAC.EffectivePolicyFinding')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Resource', ValueFromPipelineByPropertyName)]
        [Alias('Id')]
        [ValidateNotNullOrEmpty()]
        [string[]] $ResourceId,

        [Parameter(Mandatory, ParameterSetName = 'Scope')]
        [ValidatePattern('^[0-9a-fA-F-]{36}$')]
        [string] $SubscriptionId,

        [Parameter(ParameterSetName = 'Scope')]
        [ValidateNotNullOrEmpty()]
        [string[]] $ResourceGroupName,

        [Parameter(ParameterSetName = 'Scope')]
        [Parameter(Mandatory, ParameterSetName = 'Planned')]
        [ValidatePattern('^[A-Za-z0-9]+(\.[A-Za-z0-9]+)+(/[A-Za-z0-9]+)+$')]
        [string[]] $ResourceType,

        [Parameter(Mandatory, ParameterSetName = 'Planned')]
        [ValidatePattern('^/subscriptions/[0-9a-fA-F-]{36}(/resourceGroups/[^/]+)?/?$')]
        [string] $Scope,

        [Parameter(ParameterSetName = 'Planned')]
        [ValidateNotNullOrEmpty()]
        [string] $Location,

        [Parameter(ParameterSetName = 'Planned')]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter(ParameterSetName = 'Planned')]
        [hashtable] $Tag,

        [Parameter(ParameterSetName = 'Planned')]
        [ValidateNotNullOrEmpty()]
        [string] $Sku,

        [Parameter(ParameterSetName = 'Planned')]
        [ValidateNotNullOrEmpty()]
        [string] $Kind,

        [Parameter(ParameterSetName = 'Planned')]
        [hashtable] $Property,

        [ValidateSet('Blocks', 'Blocks delete', 'Audits', 'Changes', 'Deploys', 'Manual', 'Reports only', 'Disabled', 'Exempt')]
        [string[]] $Impact,

        [switch] $IncludeNotApplicable,

        [switch] $SkipReason,

        [Parameter(ParameterSetName = 'Scope')]
        [ValidateRange(1, 5000)]
        [int] $MaxResource = 500,

        [ValidateSet('Policy', 'Resource', 'Assignment', 'Exemption', 'Restriction', 'Finding')]
        [string] $View = 'Policy',

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Effective Azure Policy',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    begin {
        $wanted = [System.Collections.Generic.List[string]]::new()
    }

    process {
        foreach ($id in @($ResourceId | Where-Object { $_ })) {
            if ($id -match '^/subscriptions/[^/]+(/|$)') { $wanted.Add($id.TrimEnd('/')) } else { Write-Warning "Azure Admin Console skipped '$id': not a resource, resource group or subscription ID." }
        }
    }

    end {
        trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

        $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
        $interactive = -not $NoDisplay -and -not $pipedOnward
        $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
        $mode = $PSCmdlet.ParameterSetName
        if ($mode -eq 'Resource' -and -not $wanted.Count) { throw 'Azure Admin Console found no resource ID to show. Give -ResourceId (or pipe resources with a ResourceId or Id), -SubscriptionId, or -Scope with -ResourceType for a planned resource.' }
        if ($mode -eq 'Planned' -and @($ResourceType).Count -ne 1) { throw 'Azure Admin Console checks one planned resource at a time: give a single -ResourceType. For a whole template, use Test-AACPolicyDeployment.' }
        $request = @{
            Mode = $mode; ResourceId = $wanted.ToArray(); SubscriptionId = $SubscriptionId; ResourceGroupName = @($ResourceGroupName | Where-Object { $_ }); MaxResource = $MaxResource
            ResourceType = @($ResourceType | Where-Object { $_ }); Scope = $Scope.TrimEnd('/'); Location = $Location; Name = $Name; Tag = $Tag; Sku = $Sku; Kind = $Kind; Property = $Property
            SkipReason = [bool]$SkipReason; IncludeNotApplicable = [bool]$IncludeNotApplicable
        }

        $null = Get-AACAccessToken
        if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Effective Azure Policy' -Color 'mediumpurple' }
        $state = Invoke-AACProgress -ScriptBlock {
            $planned = $request.Mode -eq 'Planned'
            $data = if ($planned) { Read-AACEffectivePolicyData -SkipResource -SkipState -SkipReason }
            elseif ($request.Mode -eq 'Scope') { Read-AACEffectivePolicyData -SubscriptionId $request.SubscriptionId -ResourceGroupName $request.ResourceGroupName -ResourceType $request.ResourceType -MaxResource $request.MaxResource -SkipReason:$request.SkipReason }
            else { Read-AACEffectivePolicyData -ResourceId $request.ResourceId -SkipReason:$request.SkipReason }
            $notices = [System.Collections.Generic.List[string]]::new()
            foreach ($e in $data.Errors) { $notices.Add($e) }
            if (@($data.Missing).Count) { $notices.Add("$(@($data.Missing).Count) resource ID(s) weren't found, or you can't read them: $(@($data.Missing | Select-Object -First 3) -join ', ')$(if (@($data.Missing).Count -gt 3) { ', ...' })") }
            if ($data.Truncated) { $notices.Add("More than $($request.MaxResource) resources matched: the first $($request.MaxResource) are shown. Narrow with -ResourceGroupName or -ResourceType, or raise -MaxResource.") }
            if ($data.ReasonsSkipped) { $notices.Add("Why is read for the first 25 non-compliant resources; $($data.ReasonsSkipped) more aren't explained. Narrow the scope to see theirs.") }

            $resources = @($data.Resources)
            $restrictions = @()
            $content = $null
            if ($planned) {
                $type = $request.ResourceType[0]
                $plannedName = if ($request.Name) { $request.Name } else { 'planned-resource' }
                $group = if ($request.Scope -match '/resourceGroups/([^/]+)$') { $Matches[1] } else { '' }
                $resources = @(@{ Id = "$($request.Scope)/providers/$type/$plannedName"; Name = $(if ($request.Name) { $request.Name } else { '(new resource)' }); Type = $type; Location = $request.Location; Kind = $request.Kind; Tags = $(if ($request.Tag) { $request.Tag } else { @{} }); ResourceGroup = $group; SubscriptionId = ($request.Scope -split '/')[2]; Planned = $true })
                $content = [ordered]@{ type = $type }
                if ($request.Name) { $content['name'] = $request.Name }
                if ($request.Location) { $content['location'] = $request.Location }
                if ($request.Tag) { $content['tags'] = $request.Tag }
                if ($request.Sku) { $content['sku'] = @{ name = $request.Sku } }
                if ($request.Kind) { $content['kind'] = $request.Kind }
                if ($request.Property) { $content = Merge-AACObject -Base $content -Overlay $request.Property }
            }
            Update-AACProgress -Id 'effective-work' -Indeterminate -Description 'Working out what applies to each resource'
            $result = ConvertTo-AACEffectivePolicy -Resource $resources -Policy $data.Policy -Exemption $data.Exemptions -State $data.States -Reason $data.Reasons -IncludeNotApplicable:$request.IncludeNotApplicable
            Update-AACProgress -Id 'effective-work' -Complete -Description ('{0:N0} policy evaluation(s) apply to {1:N0} resource(s)' -f $result.Stats.Applies, $result.Stats.Resources)

            if ($planned) {
                Update-AACProgress -Id 'effective-check' -Indeterminate -Description 'Asking Azure Policy what it would do (checkPolicyRestrictions)'
                $names = @{}
                foreach ($a in @($data.Policy.Assignments)) { $names[([string]$a['id']).ToLowerInvariant()] = $(if ($a['displayName']) { [string]$a['displayName'] } else { [string]$a['name'] }) }
                $pending = @('location', 'type', 'tags') + @(if (-not $request.Name) { 'name' })
                $check = Invoke-AACPolicyRestrictionCheck -Scope $request.Scope -ResourceContent $content -PendingField $pending -AssignmentName $names
                if ($check.Error -and $request.Scope -match '/resourceGroups/' -and $check.Error -match '(?i)ResourceGroupNotFound|could not be found') {
                    $notices.Add("The resource group doesn't exist yet: Azure Policy was asked at the subscription.")
                    $check = Invoke-AACPolicyRestrictionCheck -Scope (($request.Scope -split '/')[0..2] -join '/') -ResourceContent $content -PendingField $pending -AssignmentName $names
                }
                if ($check.Error) { $notices.Add("Azure Policy couldn't be asked what it would do: $($check.Error) The list shows what is assigned, without verdicts.") }
                $verdict = ConvertTo-AACPolicyVerdict -Policy $result.Policies -Check $check -Definition $data.Policy.Definitions -ResourceName $resources[0].Name -ResourceType $resources[0].Type -ResourceId $resources[0].Id -Checked:(-not $check.Error)
                $restrictions = @($verdict.Restrictions)
                $result.Policies = @(@($result.Policies) + @($verdict.Policies))
                $result.Findings = @(@($result.Findings) + @($verdict.Findings))
                Update-AACProgress -Id 'effective-check' -Complete -Description $(if ($check.Error) { "Azure Policy couldn't be asked" } else { "Azure Policy: $(@($check.Evaluations | Where-Object Outcome -EQ 'Blocks').Count) would refuse, $(@($check.Evaluations | Where-Object Outcome -EQ 'Audits').Count) would audit, $(@($check.Evaluations | Where-Object Outcome -EQ 'Changes').Count) would change it" })
            }
            @{ Result = $result; Restrictions = $restrictions; Notices = $notices.ToArray(); Planned = $planned }
        }

        # --- Report ------------------------------------------------------------------------------------------------
        $r = $state.Result
        $stats = $r.Stats
        $rank = Get-AACSeverityRank
        $impactOrder = @{ 'Blocks' = 0; 'Blocks delete' = 1; 'Changes' = 2; 'Deploys' = 3; 'Audits' = 4; 'Manual' = 5; 'Reports only' = 6; 'Exempt' = 7; 'Disabled' = 8; 'Unknown' = 9; 'Not applicable' = 10 }
        $policies = @($r.Policies | Where-Object { -not $Impact -or $_.Impact -in $Impact } | Sort-Object -Property @{ Expression = { $impactOrder[$_.Impact] } }, @{ Expression = { $_.State -ne 'NonCompliant' } }, Resource, Policy)
        $inForce = @($policies | Where-Object Applicability -In 'Applies', 'Exempt')
        $nonCompliant = @($policies | Where-Object { $_.State -in 'NonCompliant', 'Would fail' })
        $leftOut = @($policies | Where-Object Applicability -In 'Excluded', 'Not selected', 'Not targeted')
        $findings = @($r.Findings | Sort-Object -Property @{ Expression = { $rank.Rank[$_.Severity] } }, Resource, Policy)
        $planned = $state.Planned
        $single = $stats.Resources -eq 1
        $subject = if ($single) { "$(@($r.Resources)[0].Resource) ($(@($r.Resources)[0].ResourceType))" } else { "$($stats.Resources) resources" }
        $impactTones = @{ 'Blocks' = 'bad'; 'Blocks delete' = 'bad'; 'Audits' = 'warn'; 'Changes' = 'info'; 'Deploys' = 'info'; 'Manual' = 'neutral'; 'Reports only' = 'neutral'; 'Disabled' = 'neutral'; 'Exempt' = 'info'; 'Not applicable' = 'neutral'; 'Unknown' = 'neutral' }
        $stateTones = @{ Compliant = 'good'; NonCompliant = 'bad'; Exempt = 'info'; 'Not evaluated' = 'neutral'; Unknown = 'neutral'; Conflicting = 'warn'; Protected = 'info'; Error = 'bad'; Planned = 'neutral'; 'Would fail' = 'bad'; Passes = 'good'; 'After deployment' = 'info'; 'Not checked' = 'warn' }
        $applicabilityTones = @{ Applies = 'good'; Exempt = 'info'; Excluded = 'neutral'; 'Not selected' = 'neutral'; 'Not targeted' = 'neutral' }
        $wouldFail = @($r.Policies | Where-Object State -EQ 'Would fail')
        $headline = if (-not $stats.Resources) { 'No resource to show.' }
        elseif ($planned) { "$subject - $($stats.Applies) policy evaluation(s) would apply: $(@($wouldFail | Where-Object Impact -EQ 'Blocks').Count) would refuse it, $(@($wouldFail | Where-Object Impact -EQ 'Audits').Count) would audit it, $(@($r.Policies | Where-Object { $_.Applicability -eq 'Applies' -and $_.Impact -in 'Changes', 'Deploys' }).Count) change or deploy" }
        else { "$subject - $($stats.Applies) policy evaluation(s) in force: $($stats.Blocks) block, $($stats.Audits) audit, $($stats.Changes) change or deploy; $($stats.NonCompliant) non-compliant, $($stats.Exempt) exempt" }
        $report = @{
            Subtitle    = "Effective Azure Policy - $subject"
            Facts       = [ordered]@{
                Subject = $subject; Mode = $(if ($planned) { 'Planned resource (before deployment)' } else { 'Existing resources' }); Assignments = $stats.Assignments
                Generated = "$([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture)) UTC"
            }
            Status      = $(if ($stats.High -or @($wouldFail | Where-Object Impact -EQ 'Blocks').Count) { 'Failed' } elseif ($stats.NonCompliant -or @($findings | Where-Object Severity -EQ 'Medium').Count) { 'Warning' } else { 'Success' })
            Headline    = $headline
            OverviewTab = 'Summary'
            Tiles       = @(
                @{ Value = '{0:N0}' -f $stats.Applies; Label = 'policies in force'; Tone = 'info'; Table = 'inforce' }
                @{ Value = '{0:N0}' -f $stats.Blocks; Label = 'block'; Tone = $(if ($stats.Blocks) { 'bad' } else { 'neutral' }); Table = 'inforce'; Filters = @{ Impact = 'Blocks' } }
                @{ Value = '{0:N0}' -f $stats.Audits; Label = 'audit'; Tone = $(if ($stats.Audits) { 'warn' } else { 'neutral' }); Table = 'inforce'; Filters = @{ Impact = 'Audits' } }
                @{ Value = '{0:N0}' -f $stats.Changes; Label = 'change or deploy'; Tone = 'info'; Table = 'inforce' }
                $(if ($planned) { @{ Value = '{0:N0}' -f @($wouldFail | Where-Object Impact -EQ 'Blocks').Count; Label = 'would refuse it'; Tone = $(if (@($wouldFail | Where-Object Impact -EQ 'Blocks').Count) { 'bad' } else { 'good' }); Table = 'noncompliant' } }
                    else { @{ Value = '{0:N0}' -f $stats.NonCompliant; Label = 'non-compliant'; Tone = $(if ($stats.NonCompliant) { 'bad' } else { 'good' }); Table = 'noncompliant' } })
                @{ Value = '{0:N0}' -f $stats.Exempt; Label = 'exempt'; Tone = $(if ($stats.Expiring) { 'warn' } else { 'neutral' }); Table = 'exemptions' }
            )
            Notices     = @(
                $(if ($planned) { @{ Status = 'Info'; Text = 'A planned resource: the verdicts are Azure Policy''s answer for the body given. DeployIfNotExists and AuditIfNotExists look at other resources after the deployment, so they show as After deployment.' } })
                $(if ($stats.ReportsOnly) { @{ Status = 'Info'; Text = "$($stats.ReportsOnly) policy evaluation(s) are assigned with enforcement off (DoNotEnforce): they report, but don't deny, change or deploy." } })
                $state.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } }
            )
            Charts      = @(
                @{ Title = 'What the policies in force do'; Kind = 'donut'; CenterLabel = 'policies'; Items = @(@($inForce | Group-Object Impact | Sort-Object { $impactOrder[$_.Name] }) | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Tone = $impactTones[$_.Name] } }) }
                @{ Title = 'Where they are assigned'; Items = @(@($inForce | Group-Object AssignedAt | Sort-Object Count -Descending | Select-Object -First 10) | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'inforce'; Column = 'AssignedAt'; Tone = 'info'; Console = $true }
            )
            Tabs        = @(
                @{ Name = 'In force'; Badge = $inForce.Count; Tone = 'info'; Note = 'Every policy that applies, worst impact first. Impact is what the effect does here: Blocks (deny), Blocks delete (denyAction), Changes (modify, append), Deploys (deployIfNotExists), Audits, or Reports only when the assignment is not enforced.' }
                @{ Name = $(if ($planned) { 'Would fail' } else { 'Non-compliant' }); Badge = $nonCompliant.Count; Tone = $(if ($nonCompliant.Count) { 'bad' } else { 'good' }); Note = $(if ($planned) { 'What Azure Policy would do to the planned body, and why.' } else { 'Each non-compliant evaluation, and why: the field the policy checks, the value it expects and the value it found.' }) }
                $(if ($planned) { @{ Name = 'Allowed values'; Badge = @($state.Restrictions).Count; Tone = 'violet'; Note = 'What policy requires or refuses for the planned resource''s fields - allowed locations, types and SKUs, required tags - and the values policy would set.' } })
                @{ Name = 'Exemptions'; Badge = @($r.Exemptions).Count; Tone = $(if ($stats.Expiring) { 'warn' } else { 'violet' }); Note = 'The exemptions that cover these resources: Waiver (accepted risk) or Mitigated (handled another way), for all the assignment''s policies or some, and when they end. An expired exemption no longer exempts.' }
                @{ Name = 'Left out'; Badge = $leftOut.Count; Tone = 'neutral'; Note = 'Policies on the path that don''t evaluate these resources, and why: the assignment''s notScopes, its resource selectors (location, type) or - with -IncludeNotApplicable - a rule about other resource types.' }
                @{ Name = 'Assignment chain'; Badge = @($r.Assignments).Count; Tone = 'neutral'; Note = 'Every assignment that reaches these resources, from the root management group down: its scope, enforcement, managed identity (needed to remediate), exclusions, resource selectors and definition version.' }
                $(if (-not $single) { @{ Name = 'Resources'; Badge = $stats.Resources; Tone = 'info'; Note = 'Each resource: how many policies apply, and what they do.' } })
                @{ Name = 'Findings'; Badge = $findings.Count; Tone = $(if ($stats.High) { 'bad' } else { 'warn' }); Note = 'What to act on, worst first.' }
            )
            Tables      = @(
                @{ Id = 'inforce'; Title = 'Policies in force'; Section = 'In force'; Rows = $inForce; Noun = 'policies'; GroupBy = @('Impact', 'AssignedAt', 'State'); ConsoleLimit = 40
                    Columns = @(
                        @{ Key = 'Resource'; Label = 'Resource'; Type = 'resource'; Console = (-not $single); Pdf = (-not $single) }
                        @{ Key = 'Impact'; Label = 'Impact'; Type = 'badge'; Tones = $impactTones; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Policy'; Label = 'Policy'; Console = $true; Pdf = $true }
                        @{ Key = 'Effect'; Label = 'Effect'; Facet = $true }
                        @{ Key = 'State'; Label = 'State'; Type = 'badge'; Tones = $stateTones; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'AssignedAt'; Label = 'Assigned at'; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Initiative'; Label = 'Initiative'; Facet = $true }
                        @{ Key = 'Assignment'; Label = 'Assignment'; Facet = $true }
                        @{ Key = 'EffectSource'; Label = 'Effect from'; Facet = $true }
                        @{ Key = 'Enforcement'; Label = 'Enforcement'; Facet = $true }
                        @{ Key = 'Exemption'; Label = 'Exemption' }
                        @{ Key = 'Evaluated'; Label = 'Evaluated'; Type = 'datetime' }
                        @{ Key = 'Identity'; Label = 'Identity'; Facet = $true }
                        @{ Key = 'Controls'; Label = 'Controls'; Type = 'wide' }
                        @{ Key = 'Message'; Label = 'Non-compliance message'; Type = 'wide' }
                        @{ Key = 'Parameters'; Label = 'Parameters'; Type = 'wide' }
                        @{ Key = 'Category'; Label = 'Category'; Facet = $true }
                        @{ Key = 'PolicyType'; Label = 'Built-in or custom'; Facet = $true }
                        @{ Key = 'Version'; Label = 'Version' }
                    ) }
                @{ Id = 'noncompliant'; Title = $(if ($planned) { 'What Azure Policy would do' } else { 'Non-compliant, and why' }); Section = $(if ($planned) { 'Would fail' } else { 'Non-compliant' }); Rows = $nonCompliant; Noun = 'evaluations'; GroupBy = @('Impact', 'Policy'); ConsoleLimit = 25
                    Empty = $(if ($planned) { 'Azure Policy would neither refuse, audit nor change the planned body.' } else { 'Nothing non-compliant.' }); EmptyStatus = 'Success'
                    Columns = @(
                        @{ Key = 'Resource'; Label = 'Resource'; Console = (-not $single); Pdf = (-not $single) }
                        @{ Key = 'Impact'; Label = 'Impact'; Type = 'badge'; Tones = $impactTones; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Policy'; Label = 'Policy'; Console = $true; Pdf = $true }
                        @{ Key = 'Reason'; Label = 'Why'; Type = 'wide'; Console = $true; Pdf = $true }
                        @{ Key = 'Detail'; Label = 'Field, expected and found'; Type = 'wide'; Console = $true; Pdf = $true }
                        @{ Key = 'Message'; Label = 'Non-compliance message'; Type = 'wide' }
                        @{ Key = 'AssignedAt'; Label = 'Assigned at'; Facet = $true }
                        @{ Key = 'Evaluated'; Label = 'Evaluated'; Type = 'datetime' }
                    ) }
                @{ Id = 'restrictions'; Title = 'Allowed values'; Section = 'Allowed values'; Rows = @($state.Restrictions); Noun = 'restrictions'; GroupBy = @('Field', 'Rule'); ConsoleLimit = 20; NoConsole = (-not $planned)
                    Columns = @(
                        @{ Key = 'Field'; Label = 'Field'; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Rule'; Label = 'Rule'; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Values'; Label = 'Values'; Type = 'wide'; Console = $true; Pdf = $true }
                        @{ Key = 'Policy'; Label = 'Policy'; Console = $true; Pdf = $true }
                        @{ Key = 'Effect'; Label = 'Effect'; Facet = $true }
                        @{ Key = 'Assignment'; Label = 'Assignment'; Facet = $true }
                    ) }
                @{ Id = 'exemptions'; Title = 'Exemptions'; Section = 'Exemptions'; Rows = @($r.Exemptions); Noun = 'exemptions'; GroupBy = @('Status', 'Category'); ConsoleLimit = 15; NoConsole = (-not @($r.Exemptions).Count)
                    Columns = @(
                        @{ Key = 'Exemption'; Label = 'Exemption'; Console = $true; Pdf = $true }
                        @{ Key = 'Category'; Label = 'Category'; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = @{ Active = 'good'; 'Ending soon' = 'warn'; Expired = 'bad'; 'No end date' = 'neutral' }; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Expires'; Label = 'Ends'; Type = 'datetime'; Console = $true; Pdf = $true }
                        @{ Key = 'Assignment'; Label = 'Assignment'; Console = $true; Pdf = $true }
                        @{ Key = 'Policies'; Label = 'Policies'; Type = 'wide' }
                        @{ Key = 'DefinedAt'; Label = 'Defined at'; Facet = $true }
                        @{ Key = 'Resources'; Label = 'Resources'; Type = 'number' }
                        @{ Key = 'Description'; Label = 'Why'; Type = 'wide' }
                    ) }
                @{ Id = 'leftout'; Title = 'Left out, and why'; Section = 'Left out'; Rows = $leftOut; Noun = 'policies'; GroupBy = @('Applicability', 'AssignedAt'); ConsoleLimit = 15; NoConsole = $true
                    Columns = @(
                        @{ Key = 'Resource'; Label = 'Resource'; Pdf = (-not $single) }
                        @{ Key = 'Policy'; Label = 'Policy'; Pdf = $true }
                        @{ Key = 'Applicability'; Label = 'Verdict'; Type = 'badge'; Tones = $applicabilityTones; Facet = $true; Pdf = $true }
                        @{ Key = 'Reason'; Label = 'Why'; Type = 'wide'; Pdf = $true }
                        @{ Key = 'Targets'; Label = 'The rule targets'; Type = 'wide' }
                        @{ Key = 'AssignedAt'; Label = 'Assigned at'; Facet = $true }
                        @{ Key = 'Initiative'; Label = 'Initiative'; Facet = $true }
                    ) }
                @{ Id = 'chain'; Title = 'Assignment chain'; Section = 'Assignment chain'; Rows = @($r.Assignments); Noun = 'assignments'; GroupBy = @('Level', 'Kind'); ConsoleLimit = 20; NoConsole = (-not $single)
                    Columns = @(
                        @{ Key = 'Level'; Label = 'Level'; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Scope'; Label = 'Scope'; Console = $true; Pdf = $true }
                        @{ Key = 'Assignment'; Label = 'Assignment'; Console = $true; Pdf = $true }
                        @{ Key = 'Kind'; Label = 'Kind'; Facet = $true; Console = $true }
                        @{ Key = 'Policies'; Label = 'Policies'; Type = 'number'; Console = $true; Pdf = $true }
                        @{ Key = 'Enforcement'; Label = 'Enforcement'; Type = 'badge'; Tones = @{ Default = 'good'; DoNotEnforce = 'warn' }; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Identity'; Label = 'Identity'; Facet = $true }
                        @{ Key = 'Definition'; Label = 'Definition' }
                        @{ Key = 'NotScopes'; Label = 'Exclusions'; Type = 'number' }
                        @{ Key = 'Selectors'; Label = 'Resource selectors' }
                        @{ Key = 'Version'; Label = 'Version' }
                    ) }
                @{ Id = 'resources'; Title = 'Resources'; Section = 'Resources'; Rows = @($r.Resources); Noun = 'resources'; GroupBy = @('ResourceType', 'State'); ConsoleLimit = 20; NoConsole = $single
                    Columns = @(
                        @{ Key = 'Resource'; Label = 'Resource'; Type = 'resource'; Console = $true; Pdf = $true }
                        @{ Key = 'ResourceType'; Label = 'Type'; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                        @{ Key = 'State'; Label = 'State'; Type = 'badge'; Tones = $stateTones + @{ 'No policy' = 'neutral' }; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Policies'; Label = 'Policies'; Type = 'number'; Console = $true; Pdf = $true }
                        @{ Key = 'Blocks'; Label = 'Block'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Audits'; Label = 'Audit'; Type = 'number'; Sum = $true; Console = $true }
                        @{ Key = 'Changes'; Label = 'Change or deploy'; Type = 'number'; Sum = $true; Console = $true }
                        @{ Key = 'NonCompliant'; Label = 'Non-compliant'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Exempt'; Label = 'Exempt'; Type = 'number'; Sum = $true }
                        @{ Key = 'Location'; Label = 'Location'; Facet = $true }
                    ) }
                @{ Id = 'findings'; Title = 'Findings'; Section = 'Findings'; Rows = $findings; Noun = 'findings'; GroupBy = @('Severity', 'Finding'); ConsoleLimit = 20
                    Empty = 'Nothing to act on.'; EmptyStatus = 'Success'
                    Columns = @(
                        @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                        @{ Key = 'Resource'; Label = 'Resource'; Console = (-not $single); Pdf = $true }
                        @{ Key = 'Policy'; Label = 'Policy'; Console = $true; Pdf = $true }
                        @{ Key = 'Finding'; Label = 'Finding'; Console = $true; Pdf = $true }
                        @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide'; Pdf = $true }
                        @{ Key = 'Recommendation'; Label = 'What to do'; Type = 'wide'; Console = $true; Pdf = $true }
                    ) }
            )
            Hint        = '-Impact Blocks shows only what refuses; -IncludeNotApplicable lists the policies that don''t target the resource and why; -Scope with -ResourceType, -Location, -Sku and -Tag checks a resource before it exists; Test-AACPolicyDeployment checks a whole template; -View Resource, Assignment, Exemption, Restriction or Finding returns those rows; -HtmlPath, -PdfPath or -CsvPath for a report.'
        }
        $rows = @(switch ($View) { 'Resource' { $r.Resources } 'Assignment' { $r.Assignments } 'Exemption' { $r.Exemptions } 'Restriction' { $state.Restrictions } 'Finding' { $findings } default { $policies } })
        Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $rows -Noun $View.ToLowerInvariant() -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
            -ShowView:$interactive -NoPaging:$NoPaging -Object $rows -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
    }
}
