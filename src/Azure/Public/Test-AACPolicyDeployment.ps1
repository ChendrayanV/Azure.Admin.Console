function Test-AACPolicyDeployment {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Tests an ARM template or Bicep file against Azure Policy before it is
        deployed: what policy would refuse, audit or change, resource by
        resource, why, and the values it allows - for a pull request or a
        pipeline gate.
    .DESCRIPTION
        Read-only: nothing is deployed. The template's resources are worked
        out offline (parameters, variables and most template functions;
        Bicep modules followed - Get-AACTemplateResource) and each body is
        sent to Azure Policy's checkPolicyRestrictions for the resource
        group (or subscription) it goes to, with audits included:
          Blocked      a deny would refuse it - the field, the expected and
                       the found value, and the values allowed
          Audited      it deploys, but is reported non-compliant
          Changed      modify or append would change it as it deploys
          Passes       nothing refuses, audits or changes it
          Not checked  Azure couldn't be asked
        Policies that act on what exists after the deployment
        (deployIfNotExists, auditIfNotExists, denyAction) are listed as
        After deployment, so "Passes" isn't read as "fully compliant".

        What can't be known before deploying (uniqueString(), reference(),
        a parameter with no value) is left out of the body, never guessed,
        and named on the resource - a policy that reads it isn't judged.

        A .bicep file is compiled with the Bicep CLI (bicep build) when it is
        on the PATH. -FailOn Deny (or Audit) ends with an error when a
        resource would be refused (or audited), after the report is
        written - for a pipeline.

        Needs Reader where the resources go. checkPolicyRestrictions honours
        the policy and exemptions assigned at the subscription, resource
        group and above.
    .PARAMETER TemplatePath
        The ARM template (.json) or Bicep file (.bicep).
    .PARAMETER ParameterPath
        An ARM parameters file (.json) for the template.
    .PARAMETER Parameter
        Parameter values, over those in -ParameterPath and the defaults.
    .PARAMETER SubscriptionId
        The subscription the template is deployed to.
    .PARAMETER ResourceGroupName
        The resource group a resource-group template is deployed to. Leave
        it out for a subscription template.
    .PARAMETER Location
        The resource group's location, for resourceGroup().location - read
        from Azure when the group exists.
    .PARAMETER FailOn
        None (the default), Deny or Audit: end with an error when a resource
        would be refused - or, with Audit, refused or audited.
    .PARAMETER View
        Resource, Policy, Restriction or Finding: what is returned and
        written to -CsvPath.
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
        Test-AACPolicyDeployment -TemplatePath .\main.bicep -SubscriptionId $sub -ResourceGroupName 'rg-orders'
        What Azure Policy would refuse, audit or change in the deployment, resource by resource.
    .EXAMPLE
        Test-AACPolicyDeployment -TemplatePath .\main.json -ParameterPath .\prod.parameters.json -SubscriptionId $sub -ResourceGroupName 'rg-orders' -FailOn Deny -HtmlPath .\policy-gate.html
        A pipeline gate: a report for the run, and an error when policy would refuse a resource.
    .EXAMPLE
        Test-AACPolicyDeployment -TemplatePath .\main.json -SubscriptionId $sub -ResourceGroupName 'rg-new' -Location 'uksouth' -View Restriction -NoDisplay
        For a resource group not created yet: the values policy allows for each resource's fields.
    .OUTPUTS
        AAC.PolicyDeploymentResource, AAC.EffectivePolicy, AAC.EffectivePolicyRestriction or AAC.EffectivePolicyFinding, by -View (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.PolicyDeploymentResource', 'AAC.EffectivePolicy', 'AAC.EffectivePolicyRestriction', 'AAC.EffectivePolicyFinding')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $TemplatePath,

        [ValidateNotNullOrEmpty()]
        [string] $ParameterPath,

        [hashtable] $Parameter = @{},

        [Parameter(Mandatory)]
        [ValidatePattern('^[0-9a-fA-F-]{36}$')]
        [string] $SubscriptionId,

        [ValidateNotNullOrEmpty()]
        [string] $ResourceGroupName,

        [ValidateNotNullOrEmpty()]
        [string] $Location,

        [ValidateSet('None', 'Deny', 'Audit')]
        [string] $FailOn = 'None',

        [ValidateSet('Resource', 'Policy', 'Restriction', 'Finding')]
        [string] $View = 'Resource',

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Azure Policy deployment check',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }

    # --- The template and its parameters ----------------------------------------------------------------------------
    $templateFile = & $resolve $TemplatePath
    if (-not (Test-Path -LiteralPath $templateFile -PathType Leaf)) { throw "Azure Admin Console can't find the template '$TemplatePath'. Give the path of an ARM template (.json) or a Bicep file (.bicep)." }
    $json = if ($templateFile -match '(?i)\.bicep$') {
        $bicep = Get-Command -Name 'bicep' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $bicep) { throw "Azure Admin Console can't compile '$TemplatePath': the Bicep CLI isn't on the PATH. Install it (https://aka.ms/bicep-install), or run 'bicep build' and give the .json file." }
        $built = Invoke-AACTerraformCli -FilePath $bicep.Source -Argument @('build', $templateFile, '--stdout') -WorkingDirectory (Split-Path -Path $templateFile -Parent) -TimeoutMinutes 5
        if ($built.ExitCode -ne 0) { throw "Azure Admin Console couldn't compile '$TemplatePath' with Bicep: $($built.Error.Trim()) Fix the Bicep errors, then run this again." }
        $built.Output
    }
    else { Get-Content -LiteralPath $templateFile -Raw }
    try { $template = ConvertFrom-Json -InputObject $json -AsHashtable -Depth 100 }
    catch { throw "Azure Admin Console can't read '$TemplatePath' as JSON: $($_.Exception.Message) Give an ARM template, or a Bicep file." }
    if ($template -isnot [System.Collections.IDictionary] -or -not $template.Contains('resources')) { throw "Azure Admin Console found no 'resources' in '$TemplatePath': it doesn't look like an ARM template." }
    $values = @{}
    if ($ParameterPath) {
        $parameterFile = & $resolve $ParameterPath
        if (-not (Test-Path -LiteralPath $parameterFile -PathType Leaf)) { throw "Azure Admin Console can't find the parameters file '$ParameterPath'." }
        $file = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $parameterFile -Raw) -AsHashtable -Depth 100
        $declared = if ($file -is [System.Collections.IDictionary] -and $file['parameters'] -is [System.Collections.IDictionary]) { $file['parameters'] } else { @{} }
        # A Key Vault reference is read at deployment: left unresolved.
        foreach ($key in @($declared.Keys)) { if ($declared[$key] -is [System.Collections.IDictionary] -and $declared[$key].Contains('value')) { $values[$key] = $declared[$key]['value'] } }
    }
    foreach ($key in @($Parameter.Keys)) { $values[[string]$key] = $Parameter[$key] }
    $request = @{ Template = $template; Values = $values; SubscriptionId = $SubscriptionId; ResourceGroupName = $ResourceGroupName; Location = $Location; Source = (Split-Path -Path $templateFile -Leaf) }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Azure Policy deployment check' -Color 'mediumpurple' }
    $state = Invoke-AACProgress -ScriptBlock {
        $notices = [System.Collections.Generic.List[string]]::new()
        $group = "/subscriptions/$($request.SubscriptionId)/resourceGroups/$($request.ResourceGroupName)"
        $groupExists = $true
        $rgLocation = $request.Location
        if ($request.ResourceGroupName) {
            try {
                $rg = Invoke-AACArmRequest -Uri "$($group)?api-version=2021-04-01"
                if (-not $rgLocation -and $rg -is [System.Collections.IDictionary]) { $rgLocation = [string]$rg['location'] }
            }
            catch {
                if ($_.Exception.Data['StatusCode'] -ne 404) { throw }
                $groupExists = $false
                $notices.Add("The resource group '$($request.ResourceGroupName)' doesn't exist yet: Azure Policy is asked at the subscription.$(if (-not $rgLocation) { ' Give -Location for what uses resourceGroup().location.' })")
            }
        }

        Update-AACProgress -Id 'deploy-read' -Indeterminate -Description "Working out the resources in $($request.Source)"
        $expanded = Get-AACTemplateResource -Template $request.Template -Parameter $request.Values -SubscriptionId $request.SubscriptionId -ResourceGroupName $request.ResourceGroupName -Location $rgLocation -Source $request.Source
        foreach ($n in $expanded.Notices) { $notices.Add($n) }
        $targets = @($expanded.Resources | Where-Object { $_.Type -match '^[A-Za-z0-9]+\.[A-Za-z0-9.]+/' })
        Update-AACProgress -Id 'deploy-read' -Complete -Description "Found $($targets.Count) resource(s) in $($request.Source)"

        $data = Read-AACEffectivePolicyData -SkipResource -SkipState -SkipReason
        foreach ($e in $data.Errors) { $notices.Add($e) }
        $facts = @($targets | ForEach-Object { @{ Id = $_.Id; Name = $_.Name; Type = $_.Type; Location = $_.Location; Kind = $_.Kind; Tags = $_.Tags; ResourceGroup = $_.ResourceGroup; SubscriptionId = $request.SubscriptionId; Planned = $true } })
        $result = ConvertTo-AACEffectivePolicy -Resource $facts -Policy $data.Policy -Exemption $data.Exemptions
        $names = @{}
        foreach ($a in @($data.Policy.Assignments)) { $names[([string]$a['id']).ToLowerInvariant()] = $(if ($a['displayName']) { [string]$a['displayName'] } else { [string]$a['name'] }) }

        Update-AACProgress -Id 'deploy-check' -Total ([Math]::Max($targets.Count, 1)) -Description "Asking Azure Policy about $($targets.Count) resource(s)"
        $policies = [System.Collections.Generic.List[object]]::new()
        $restrictions = [System.Collections.Generic.List[object]]::new()
        $findings = [System.Collections.Generic.List[object]]::new()
        $resourceRows = [System.Collections.Generic.List[object]]::new()
        foreach ($t in $targets) {
            $scope = if (-not $groupExists -and $t.ScopeId -ieq $group) { "/subscriptions/$($request.SubscriptionId)" } else { $t.ScopeId }
            $check = Invoke-AACPolicyRestrictionCheck -Scope $scope -ResourceContent $t.Content -ApiVersion $t.ApiVersion -ParentId $t.ParentId -AssignmentName $names
            $own = @($result.Policies | Where-Object { $_.ResourceId -eq $t.Id })
            $verdict = ConvertTo-AACPolicyVerdict -Policy $own -Check $check -Definition $data.Policy.Definitions -ResourceName $t.Name -ResourceType $t.Type -ResourceId $t.Id -Checked:(-not $check.Error)
            $all = @($own) + @($verdict.Policies)
            foreach ($row in $all) { $policies.Add($row) }
            foreach ($row in $verdict.Restrictions) { $restrictions.Add($row) }
            foreach ($row in $verdict.Findings) { $findings.Add($row) }
            $failing = @($all | Where-Object State -EQ 'Would fail')
            $outcome = if ($check.Error) { 'Not checked' } elseif (@($failing | Where-Object Impact -EQ 'Blocks').Count) { 'Blocked' } elseif (@($failing | Where-Object Impact -EQ 'Audits').Count) { 'Audited' } elseif ($failing.Count) { 'Changed' } else { 'Passes' }
            if ($check.Error) { $findings.Add([pscustomobject]@{ PSTypeName = 'AAC.EffectivePolicyFinding'; Severity = 'Medium'; Resource = $t.Name; Policy = ''; Finding = "Azure Policy couldn't be asked about it"; Detail = $check.Error; Recommendation = 'Check you have Reader where it goes, then run this again.'; ResourceId = $t.Id }) }
            if (@($t.Unresolved).Count) { $findings.Add([pscustomobject]@{ PSTypeName = 'AAC.EffectivePolicyFinding'; Severity = 'Info'; Resource = $t.Name; Policy = ''; Finding = "$(@($t.Unresolved).Count) value(s) are only known at deployment"; Detail = "Not sent, so not judged: $(@($t.Unresolved) -join ', ')."; Recommendation = 'Give the parameters a value (-ParameterPath, -Parameter) to check them too; uniqueString(), reference() and similar stay unknown.'; ResourceId = $t.Id }) }
            $resourceRows.Add([pscustomobject][ordered]@{
                    PSTypeName      = 'AAC.PolicyDeploymentResource'
                    Resource        = $t.Name
                    ResourceType    = $t.Type
                    Outcome         = $outcome
                    Blocks          = @($failing | Where-Object Impact -EQ 'Blocks').Count
                    Audits          = @($failing | Where-Object Impact -EQ 'Audits').Count
                    Changes         = @($failing | Where-Object Impact -In 'Changes', 'Deploys').Count
                    AfterDeployment = @($all | Where-Object State -EQ 'After deployment').Count
                    Policies        = @($all | Where-Object Applicability -EQ 'Applies').Count
                    Location        = $t.Location
                    Source          = $t.Source
                    Unresolved      = (@($t.Unresolved) -join ', ')
                    Copy            = $t.Copy
                    ResourceId      = $t.Id
                })
            Update-AACProgress -Id 'deploy-check' -Increment 1
        }
        $blocked = @($resourceRows | Where-Object Outcome -EQ 'Blocked').Count
        Update-AACProgress -Id 'deploy-check' -Complete -Description "Azure Policy: $blocked of $($targets.Count) resource(s) would be refused"
        @{ Resources = $resourceRows.ToArray(); Policies = $policies.ToArray(); Restrictions = $restrictions.ToArray(); Findings = $findings.ToArray(); Exemptions = @($result.Exemptions); Notices = $notices.ToArray() }
    }

    # --- Report ------------------------------------------------------------------------------------------------
    $rank = Get-AACSeverityRank
    $outcomeOrder = @{ Blocked = 0; 'Not checked' = 1; Audited = 2; Changed = 3; Passes = 4 }
    $resources = @($state.Resources | Sort-Object -Property @{ Expression = { $outcomeOrder[$_.Outcome] } }, Resource)
    $stateOrder = @{ 'Would fail' = 0; 'Not checked' = 1; 'After deployment' = 2; Passes = 3 }
    $policies = @($state.Policies | Where-Object Applicability -In 'Applies', 'Exempt' | Sort-Object -Property @{ Expression = { if ($stateOrder.Contains($_.State)) { $stateOrder[$_.State] } else { 4 } } }, Resource, Policy)
    $failing = @($policies | Where-Object State -EQ 'Would fail')
    $after = @($policies | Where-Object State -EQ 'After deployment')
    $findings = @($state.Findings | Sort-Object -Property @{ Expression = { $rank.Rank[$_.Severity] } }, Resource)
    $count = @{}
    foreach ($o in 'Blocked', 'Audited', 'Changed', 'Passes', 'Not checked') { $count[$o] = @($resources | Where-Object Outcome -EQ $o).Count }
    $outcomeTones = @{ Blocked = 'bad'; Audited = 'warn'; Changed = 'info'; Passes = 'good'; 'Not checked' = 'warn' }
    $impactTones = @{ 'Blocks' = 'bad'; 'Blocks delete' = 'bad'; 'Audits' = 'warn'; 'Changes' = 'info'; 'Deploys' = 'info'; 'Manual' = 'neutral'; 'Reports only' = 'neutral'; 'Disabled' = 'neutral'; 'Exempt' = 'info'; 'Unknown' = 'neutral' }
    $stateTones = @{ 'Would fail' = 'bad'; Passes = 'good'; 'After deployment' = 'info'; 'Not checked' = 'warn'; Planned = 'neutral' }
    $report = @{
        Subtitle    = "Azure Policy deployment check - $($request.Source)"
        Facts       = [ordered]@{
            Template = $request.Source; Target = $(if ($request.ResourceGroupName) { "Resource group $($request.ResourceGroupName)" } else { 'Subscription' }); Resources = $resources.Count
            Generated = "$([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture)) UTC"
        }
        Status      = $(if ($count.Blocked) { 'Failed' } elseif ($count.Audited -or $count['Not checked']) { 'Warning' } else { 'Success' })
        Headline    = $(if (-not $resources.Count) { 'The template deploys no resource to check.' } else { "$($resources.Count) resource(s): $($count.Blocked) would be refused, $($count.Audited) audited, $($count.Changed) changed by policy, $($count.Passes) pass$(if ($count['Not checked']) { "; $($count['Not checked']) couldn't be checked" }). $($after.Count) policy evaluation(s) act after the deployment." })
        OverviewTab = 'Summary'
        Tiles       = @(
            @{ Value = '{0:N0}' -f $resources.Count; Label = 'resources'; Tone = 'info'; Table = 'resources' }
            @{ Value = '{0:N0}' -f $count.Blocked; Label = 'would be refused'; Tone = $(if ($count.Blocked) { 'bad' } else { 'good' }); Table = 'resources'; Filters = @{ Outcome = 'Blocked' } }
            @{ Value = '{0:N0}' -f $count.Audited; Label = 'audited'; Tone = $(if ($count.Audited) { 'warn' } else { 'neutral' }); Table = 'resources'; Filters = @{ Outcome = 'Audited' } }
            @{ Value = '{0:N0}' -f $count.Changed; Label = 'changed by policy'; Tone = 'info'; Table = 'resources'; Filters = @{ Outcome = 'Changed' } }
            @{ Value = '{0:N0}' -f $count.Passes; Label = 'pass'; Tone = 'good'; Table = 'resources'; Filters = @{ Outcome = 'Passes' } }
            @{ Value = '{0:N0}' -f $after.Count; Label = 'after deployment'; Tone = 'neutral'; Table = 'policies'; Filters = @{ State = 'After deployment' } }
        )
        Notices     = @(
            @{ Status = 'Info'; Text = 'Azure Policy judged each resource''s body as the template would send it. DeployIfNotExists, AuditIfNotExists and DenyAction act on what exists after the deployment: they are listed, not judged.' }
            $state.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } }
        )
        Charts      = @(
            @{ Title = 'Resources by outcome'; Kind = 'donut'; CenterLabel = 'resources'; Items = @('Blocked', 'Audited', 'Changed', 'Passes', 'Not checked' | Where-Object { $count[$_] } | ForEach-Object { @{ Label = $_; Value = $count[$_]; Tone = $outcomeTones[$_] } }) }
            @{ Title = 'Policies that would fail'; Items = @(@($failing | Group-Object Policy | Sort-Object Count -Descending | Select-Object -First 10) | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'failing'; Column = 'Policy'; Tone = 'bad'; Console = $true }
        )
        Tabs        = @(
            @{ Name = 'Resources'; Badge = $resources.Count; Tone = $(if ($count.Blocked) { 'bad' } else { 'good' }); Note = 'Each resource in the template, refused ones first.' }
            @{ Name = 'Would fail'; Badge = $failing.Count; Tone = $(if ($failing.Count) { 'bad' } else { 'good' }); Note = 'What Azure Policy would refuse, audit or change, and why: the field, the value it expects and the value in the template.' }
            @{ Name = 'Allowed values'; Badge = @($state.Restrictions).Count; Tone = 'violet'; Note = 'What policy requires, refuses, sets or removes for the resources'' fields.' }
            @{ Name = 'Policies'; Badge = $policies.Count; Tone = 'info'; Note = 'Every policy that applies to each resource, with its verdict - including those that act after the deployment.' }
            @{ Name = 'Findings'; Badge = $findings.Count; Tone = $(if ($count.Blocked) { 'bad' } else { 'warn' }); Note = 'What to change before deploying, worst first.' }
        )
        Tables      = @(
            @{ Id = 'resources'; Title = 'Resources'; Section = 'Resources'; Rows = $resources; Noun = 'resources'; GroupBy = @('Outcome', 'ResourceType'); ConsoleLimit = 30
                Columns = @(
                    @{ Key = 'Resource'; Label = 'Resource'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'ResourceType'; Label = 'Type'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Outcome'; Label = 'Outcome'; Type = 'badge'; Tones = $outcomeTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Blocks'; Label = 'Refuse'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Audits'; Label = 'Audit'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Changes'; Label = 'Change'; Type = 'number'; Sum = $true; Console = $true }
                    @{ Key = 'AfterDeployment'; Label = 'After deployment'; Type = 'number'; Sum = $true }
                    @{ Key = 'Policies'; Label = 'Policies'; Type = 'number' }
                    @{ Key = 'Location'; Label = 'Location'; Facet = $true }
                    @{ Key = 'Source'; Label = 'From'; Facet = $true }
                    @{ Key = 'Unresolved'; Label = 'Known only at deployment'; Type = 'wide' }
                ) }
            @{ Id = 'failing'; Title = 'What Azure Policy would do'; Section = 'Would fail'; Rows = $failing; Noun = 'evaluations'; GroupBy = @('Impact', 'Policy'); ConsoleLimit = 25
                Empty = 'Azure Policy would neither refuse, audit nor change anything in the template.'; EmptyStatus = 'Success'
                Columns = @(
                    @{ Key = 'Resource'; Label = 'Resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Impact'; Label = 'Impact'; Type = 'badge'; Tones = $impactTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Policy'; Label = 'Policy'; Console = $true; Pdf = $true }
                    @{ Key = 'Reason'; Label = 'Why'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'Detail'; Label = 'Field, expected and found'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'Assignment'; Label = 'Assignment'; Facet = $true }
                    @{ Key = 'AssignedAt'; Label = 'Assigned at'; Facet = $true }
                ) }
            @{ Id = 'restrictions'; Title = 'Allowed values'; Section = 'Allowed values'; Rows = @($state.Restrictions); Noun = 'restrictions'; GroupBy = @('Field', 'Rule'); ConsoleLimit = 15; NoConsole = (-not $count.Blocked)
                Columns = @(
                    @{ Key = 'Resource'; Label = 'Resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Field'; Label = 'Field'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Rule'; Label = 'Rule'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Values'; Label = 'Values'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'Policy'; Label = 'Policy'; Pdf = $true }
                    @{ Key = 'Effect'; Label = 'Effect'; Facet = $true }
                ) }
            @{ Id = 'policies'; Title = 'Policies that apply'; Section = 'Policies'; Rows = $policies; Noun = 'policies'; GroupBy = @('State', 'Impact', 'Resource'); ConsoleLimit = 20; NoConsole = $true
                Columns = @(
                    @{ Key = 'Resource'; Label = 'Resource'; Facet = $true; Pdf = $true }
                    @{ Key = 'Policy'; Label = 'Policy'; Pdf = $true }
                    @{ Key = 'State'; Label = 'Verdict'; Type = 'badge'; Tones = $stateTones; Facet = $true; Pdf = $true }
                    @{ Key = 'Impact'; Label = 'Impact'; Type = 'badge'; Tones = $impactTones; Facet = $true; Pdf = $true }
                    @{ Key = 'Effect'; Label = 'Effect'; Facet = $true }
                    @{ Key = 'AssignedAt'; Label = 'Assigned at'; Facet = $true }
                    @{ Key = 'Initiative'; Label = 'Initiative'; Facet = $true }
                    @{ Key = 'Enforcement'; Label = 'Enforcement'; Facet = $true }
                    @{ Key = 'Exemption'; Label = 'Exemption' }
                    @{ Key = 'Identity'; Label = 'Identity'; Facet = $true }
                ) }
            @{ Id = 'findings'; Title = 'Findings'; Section = 'Findings'; Rows = $findings; Noun = 'findings'; GroupBy = @('Severity', 'Finding'); ConsoleLimit = 20
                Empty = 'Nothing to change.'; EmptyStatus = 'Success'
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Resource'; Label = 'Resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Finding'; Label = 'Finding'; Console = $true; Pdf = $true }
                    @{ Key = 'Policy'; Label = 'Policy'; Pdf = $true }
                    @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Recommendation'; Label = 'What to do'; Type = 'wide'; Console = $true; Pdf = $true }
                ) }
        )
        Hint        = '-ParameterPath gives the parameters a value; -FailOn Deny makes it a pipeline gate; -View Policy, Restriction or Finding returns those rows; Show-AACEffectivePolicy -ResourceId shows a deployed resource''s policy; -HtmlPath, -PdfPath or -CsvPath for a report.'
    }
    $rows = @(switch ($View) { 'Policy' { $policies } 'Restriction' { $state.Restrictions } 'Finding' { $findings } default { $resources } })
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $rows -Noun $View.ToLowerInvariant() -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $rows -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)

    $failed = switch ($FailOn) { 'Deny' { $count.Blocked } 'Audit' { $count.Blocked + $count.Audited } default { 0 } }
    if ($failed) { throw "Azure Admin Console: Azure Policy would $(if ($FailOn -eq 'Audit') { 'refuse or audit' } else { 'refuse' }) $failed resource(s) in $($request.Source). See the Would fail tab or -View Finding, fix the values, or ask for an exemption." }
}
