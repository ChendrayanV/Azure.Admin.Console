function New-AACServiceBlueprint {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Plans the Azure services you name: what your tenant's Azure Policy
        allows, what PSRule for Azure says about a secure configuration, the
        alerts and resiliency guidance that go with them, the resources' names,
        and a diagram in draw.io, HTML or PDF.
    .DESCRIPTION
        Name the services; nothing is deployed and nothing in Azure changes.
        For each one the blueprint plans a secure starting configuration -
        private, no shared keys or local authentication, TLS 1.2, a managed
        identity, zone redundancy and soft delete where the service has them -
        and checks it.

          Naming      -NamingConvention filled in for each resource and checked
                      against what Azure accepts for that type. A name that
                      can't be used is reported, never shortened.
          Azure Policy  with -SubscriptionId: the policies in force for each
                      type (Get-AACAssignedPolicy), the guardrails (allowed
                      region and resource types, public network access) and
                      Azure's own verdict on each planned resource
                      (checkPolicyRestrictions). With -ManagementGroupId: what
                      is assigned and the guardrails, no verdicts; Azure answers
                      that question for a subscription. With neither: policy
                      isn't read, no sign-in is needed, and the report says so.
          PSRule      PSRule for Azure's rules on each planned resource, as a
                      deployment would present it. Rules about what a blueprint
                      doesn't plan, such as an Event Hubs namespace's hubs, fail
                      until you add it: they are a to-do list. The module's own
                      naming rule is left out: -NamingConvention decides the
                      names here. -SkipPSRule leaves PSRule out.

          Alerts      what Azure Monitor Baseline Alerts (AMBA) suggests for each
                      type, as Get-AACAlertBaseline shows it.
          Resiliency  what the Azure Proactive Resiliency Library (APRL)
                      recommends, as Get-AACResiliencyRecommendation shows it.
                      Alerts and recommendations are suggestions, not results,
                      so they don't change a resource's status.

        Each resource is Blocked, Needs attention, Ready or Not fully checked.
        Not checked is never reported as ready.

        DeployIfNotExists and AuditIfNotExists policies look at other resources
        after a deployment, so Azure gives no verdict on them beforehand. They
        are listed on the Policies tab, not counted as passed or failed.

        Services come from Azure's own list, the one behind the portal's New
        support request page: tab completes them once you have run Connect-AAC,
        and a resource type works too. That list says what a service's resource
        types are, and nothing about how to configure one. So only FunctionApp
        (with its plan), StorageAccount, EventHub and EventGrid, which have a
        hand-checked secure configuration, get Azure Policy's verdict and PSRule.
        Any other service is planned as its resource types, with the policies in
        force, the guardrails, the alerts and the recommendations; it is never
        better than Not fully checked, and its names aren't checked against
        Azure's rules. Those four need no sign-in. A Function App needs a storage
        account at run time: add StorageAccount, or you are told it is missing.

        -OutputFormat writes to -Path. <name> is <workload>-<env>-blueprint:
          DrawIo   <name>.drawio, editable, with a Legend page. An existing file
                   isn't overwritten without -Force: it may hold your edits.
          Html     <name>.html, the diagram to pan, zoom and search, offline,
                   and <name>-report.html, the tabbed report
          Pdf      <name>.pdf, the diagram (needs Microsoft Edge or Google
                   Chrome), and <name>-report.pdf, the report
        -Show opens what was written: the HTML page in your browser when there
        is one, else the first file. Without -Path, the console view only.
    .PARAMETER Service
        The services, as Azure's list names them, or a resource type. Tab completes
        them; spaces, hyphens and case don't matter. Part of a name works when
        only one service fits. Without Connect-AAC: FunctionApp, StorageAccount,
        EventHub and EventGrid.
    .PARAMETER SubscriptionId
        The subscription the resources would go in. Gives Azure's verdict.
    .PARAMETER ManagementGroupId
        The management group they would go under: what is assigned, no verdicts.
    .PARAMETER Region
        The region (westeurope by default).
    .PARAMETER NamingConvention
        The names' pattern, from {type} (the Cloud Adoption Framework's
        abbreviation), {workload}, {env}, {region} (a short code) and {instance}.
        '{type}-{workload}-{env}-{region}-{instance}' by default.
    .PARAMETER Workload
        The {workload} in the names (app by default).
    .PARAMETER Environment
        The {env} in the names (dev by default).
    .PARAMETER Instance
        The {instance} in the names (01 by default).
    .PARAMETER Tag
        Tags for every planned resource, so policies and rules that require
        tags can pass: @{ CostCenter = 'cc-123' }.
    .PARAMETER OutputFormat
        DrawIo, Html, Pdf or several; tab completes them. DrawIo when -Path is
        given without it.
    .PARAMETER Path
        The folder to write to.
    .PARAMETER SkipPSRule
        Don't run PSRule for Azure.
    .PARAMETER Title
        The diagram's and report's title.
    .PARAMETER Force
        Overwrite an existing .drawio file.
    .PARAMETER Show
        Open what was written.
    .PARAMETER PassThru
        Show the view and also return the planned resources.
    .PARAMETER NoDisplay
        Return the planned resources without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        New-AACServiceBlueprint -Service FunctionApp, StorageAccount, EventHub, EventGrid -Workload orders -Environment prod -SkipPSRule
        The names and the resources, offline: no sign-in, no policy.
    .EXAMPLE
        Connect-AAC
        New-AACServiceBlueprint -Service FunctionApp, StorageAccount -SubscriptionId $sub -Workload orders -Environment prod -Tag @{ CostCenter = 'cc-123' } -OutputFormat DrawIo, Html -Path .\out -Show
        Checked against the subscription's policy and PSRule; the diagram and report open in the browser.
    .EXAMPLE
        New-AACServiceBlueprint -Service EventHub -ManagementGroupId 'mg-landingzones' -NamingConvention '{workload}-{type}-{env}' -Workload orders -OutputFormat Pdf -Path .\out
        What a landing zone assigns for Event Hubs, with your own naming pattern, as PDFs.
    .EXAMPLE
        Connect-AAC
        New-AACServiceBlueprint -Service 'Virtual Network', 'Key Vault' -SubscriptionId $sub -Workload orders -OutputFormat Html -Path .\out
        Services without a secure configuration here: the policies in force, the alerts and the recommendations for their types.
    .EXAMPLE
        New-AACServiceBlueprint -Service StorageAccount -SubscriptionId $sub -NoDisplay | Where-Object Status -EQ 'Blocked'
        In a script: whether anything would be refused.
    .OUTPUTS
        AAC.ServiceBlueprintComponent (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('AAC.ServiceBlueprintComponent')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ArgumentCompleter({ param($Command, $Parameter, $Word) & (Get-Module -Name 'Azure.Admin.Console') { param($Typed) Get-AACServiceBlueprintChoice -Word $Typed } $Word })]
        [ValidateNotNullOrEmpty()]
        [string[]] $Service,

        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string] $SubscriptionId,

        [ValidateNotNullOrEmpty()]
        [string] $ManagementGroupId,

        [ValidateNotNullOrEmpty()]
        [string] $Region = 'westeurope',

        [ValidateNotNullOrEmpty()]
        [string] $NamingConvention = '{type}-{workload}-{env}-{region}-{instance}',

        [ValidateNotNullOrEmpty()]
        [string] $Workload = 'app',

        [ValidateNotNullOrEmpty()]
        [string] $Environment = 'dev',

        [ValidateNotNullOrEmpty()]
        [string] $Instance = '01',

        [System.Collections.IDictionary] $Tag = @{},

        [ValidateSet('DrawIo', 'Html', 'Pdf')]
        [string[]] $OutputFormat,

        [string] $Path,

        [switch] $SkipPSRule,

        [string] $Title,

        [switch] $Force,

        [switch] $Show,

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    if ($SubscriptionId -and $ManagementGroupId) { throw 'Azure Admin Console: give -SubscriptionId or -ManagementGroupId, not both. -SubscriptionId also gets Azure''s verdict on each resource.' }
    if ($OutputFormat -and -not $Path) { throw 'Azure Admin Console: -OutputFormat needs -Path, the folder to write to.' }
    if ($Show -and -not $Path) { throw 'Azure Admin Console: -Show opens the files written, so it needs -Path.' }
    $formats = @(if ($OutputFormat) { $OutputFormat | Select-Object -Unique } elseif ($Path) { 'DrawIo' })
    $Region = $Region.ToLowerInvariant()

    # --- What was asked for ------------------------------------------------------------------------------
    $templates = Get-AACServiceTemplate
    # Azure's list is only read for a name a template doesn't answer, so the
    # templates' services still work offline, without a sign-in.
    $templateNames = @(foreach ($key in $templates.Keys) { $key; $templates[$key].Name }) | ForEach-Object { ($_ -replace '[^A-Za-z0-9]', '').ToLowerInvariant() }
    $needsList = @($Service | Where-Object { ($_ -replace '[^A-Za-z0-9]', '').ToLowerInvariant() -notin $templateNames }).Count -gt 0
    $azureServices = @(if ($needsList -and $script:AACSession) { Get-AACServiceCatalog })
    $wantedNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $wanted = @(foreach ($name in $Service) {
            $found = Resolve-AACServiceBlueprintService -Name $name -Template $templates -Catalog $azureServices
            if ($wantedNames.Add($found.Name)) { $found }
        })
    $slug = { param([string] $Text) ($Text -replace '[^A-Za-z0-9._-]', '-').Trim('-') }
    $base = "$(& $slug $Workload)-$(& $slug $Environment)-blueprint"
    $reportTitle = if ($Title) { $Title } else { "Service blueprint: $Workload ($Environment)" }
    $folder = if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } else { '' }
    $drawioPath = if ($formats -contains 'DrawIo') { Join-Path -Path $folder -ChildPath "$base.drawio" } else { '' }
    if ($drawioPath -and (Test-Path -LiteralPath $drawioPath) -and -not $Force) { throw "Azure Admin Console won't overwrite $drawioPath - it may hold your edits. Add -Force to replace it, or choose another -Path." }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    # Read here, not inside the progress block (it runs in Invoke-AACProgress's scope).
    $request = @{ SubscriptionId = $SubscriptionId; ManagementGroupId = $ManagementGroupId; Region = $Region; SkipPSRule = [bool]$SkipPSRule; Tag = $Tag; Wanted = $wanted; Templates = $templates; Pattern = $NamingConvention; Workload = $Workload; Environment = $Environment; Instance = $Instance }
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Service blueprint' -Color 'deepskyblue3_1' }

    $state = Invoke-AACProgress -ScriptBlock {
        # --- Names and planned resources --------------------------------------------------------------------
        $nameOf = {
            param([string] $Abbreviation, [System.Collections.IDictionary] $Rule)
            ConvertTo-AACServiceBlueprintName -Pattern $request.Pattern -Abbreviation $Abbreviation -Workload $request.Workload -Environment $request.Environment -Region $request.Region -Instance $request.Instance -Rule $Rule
        }
        $groupName = (& $nameOf 'rg' @{ Min = 1; Max = 90; Pattern = '^[a-z0-9._()-]*[a-z0-9_()-]$'; Strip = $false; Text = '1-90 letters, numbers, hyphens, underscores, periods and parentheses, not ending with a period' })
        # An ID PSRule and the body can use; no scope means no subscription to name.
        $subscription = if ($request.SubscriptionId) { $request.SubscriptionId } else { '00000000-0000-0000-0000-000000000000' }
        $groupId = "/subscriptions/$subscription/resourceGroups/$($groupName.Name)"
        $items = [System.Collections.Generic.List[hashtable]]::new()
        $notices = [System.Collections.Generic.List[string]]::new()
        # Azure's list spells types in upper case; the data has them as they are written.
        $knownTypes = @{}
        foreach ($set in 'Alerts', 'Resiliency') { foreach ($type in (Get-AACServiceBaseline -Set $set -ResourceType @()).Types) { $knownTypes[$type.ToLowerInvariant()] = $type } }
        $seenTypes = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in $request.Wanted) {
            $parts = if ($entry.Template) { $request.Templates[$entry.Template].Components }
            else {
                foreach ($rawType in $entry.ResourceTypes) {
                    $type = if ($knownTypes.ContainsKey($rawType.ToLowerInvariant())) { $knownTypes[$rawType.ToLowerInvariant()] } else { $rawType }
                    $leaf = ($type -split '/')[-1].ToLowerInvariant()
                    @{ Id = "type-$(($type -replace '[^A-Za-z0-9]', '-').ToLowerInvariant())"; Label = "$($entry.Name) ($(($type -split '/')[-1]))"; Type = $type; ApiVersion = ''; Icon = 'resource'; Abbreviation = ($leaf -replace 's$', ''); Sku = 'Not planned'; Public = @{}; Body = $null
                        # Azure's rules for this type aren't known here: the name is the convention's, unchecked.
                        Naming = @{ Min = 1; Max = 260; Pattern = '.'; Strip = $false; Text = 'a name' } }
                }
            }
            foreach ($part in $parts) {
                if (-not $seenTypes.Add($part.Type)) { continue }
                $named = & $nameOf $part.Abbreviation $part.Naming
                $items.Add(@{ Service = $entry.Name; Id = $part.Id; Label = $part.Label; Type = $part.Type; ApiVersion = $part.ApiVersion; Icon = $part.Icon; Sku = $part.Sku; Public = $part.Public; Body = $part.Body; Children = @($part['Children'] | Where-Object { $_ }); Name = $named.Name; Adjusted = $named.Adjusted; Problem = $named.Problem; Location = $request.Region; ResourceId = "$groupId/providers/$($part.Type)/$($named.Name)" })
            }
        }
        $ids = @{}
        foreach ($item in $items) { $ids[$item.Id] = $item.ResourceId }
        foreach ($item in $items) {
            $item.Resource = if ($item.Body) { & $item.Body $ids }
            if ($item.Resource -and $request.Tag.Count) { $item.Resource['tags'] = $request.Tag }
            # A web app's alerts aren't a Function App's: AMBA says which kinds each is for.
            $kind = if ($item.Resource -and $item.Resource.Contains('kind')) { [string]$item.Resource['kind'] } else { '' }
            $item.Alerts = @((Get-AACServiceBaseline -Set Alerts -ResourceType @($item.Type) -Kind $kind).Rows)
            $item.Resiliency = @((Get-AACServiceBaseline -Set Resiliency -ResourceType @($item.Type)).Rows)
        }
        $unplanned = @($items | Where-Object { -not $_.Resource })
        if ($unplanned.Count) { $notices.Add("No secure configuration is planned for $(@($unplanned | ForEach-Object { $_.Type }) -join ', '): the policies in force, alerts and recommendations are shown, but there is no Azure Policy verdict or PSRule check, and the names aren't checked against Azure's rules.") }
        if ($groupName.Problem) { $notices.Add("The resource group's name: $($groupName.Problem)") }
        if ($ids.ContainsKey('functionapp') -and -not $ids.ContainsKey('storage')) { $notices.Add('A Function App needs a storage account at run time, and the blueprint has none: add StorageAccount to -Service, or plan to use an existing one.') }

        # --- Azure Policy -----------------------------------------------------------------------------------
        $policy = $null
        if ($request.SubscriptionId -or $request.ManagementGroupId) {
            $null = Get-AACAccessToken
            $policy = Read-AACServiceBlueprintPolicy -Component $items.ToArray() -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId -Region $request.Region
            foreach ($line in @($policy.Notices)) { $notices.Add($line) }
        }
        else { $notices.Add('Azure Policy wasn''t read: give -SubscriptionId for Azure''s verdict, or -ManagementGroupId for what is assigned.') }

        # --- PSRule for Azure -----------------------------------------------------------------------------------
        $psrule = $null
        if ($request.SkipPSRule) { $notices.Add('PSRule for Azure was skipped, so these resources aren''t checked against it.') }
        else {
            $objects = @(foreach ($item in @($items | Where-Object { $_.Resource })) {
                    # As a deployment would present it: apiVersion, because PSRule reads defaults by it.
                    $children = @(foreach ($child in $item.Children) { Merge-AACObject -Base $child -Overlay ([ordered]@{ id = "$($item.ResourceId)/$(($child.type -split '/')[-1])/$($child.name)" }) })
                    $object = [ordered]@{ id = $item.ResourceId; name = $item.Name; type = $item.Type; apiVersion = $item.ApiVersion; location = $item.Location; resourceGroupName = $groupName.Name; subscriptionId = $subscription; resources = $children }
                    foreach ($key in $item.Resource.Keys) { $object[$key] = $item.Resource[$key] }
                    $object
                })
            if ($objects.Count) {
                try { $psrule = @((Invoke-AACPSRuleEngine -InputObject $objects -ExcludeRule 'AAC.Resource.Naming').Results) }
                catch { $notices.Add("PSRule for Azure couldn't run, so these resources aren't checked against it: $($_.Exception.Message)") }
            }
        }

        $result = ConvertTo-AACServiceBlueprint -Component $items.ToArray() -Policy $policy -PSRuleResult $psrule
        $withComponent = {
            param([string] $Field)
            foreach ($item in $items) { foreach ($row in $item[$Field]) { $row | Select-Object -Property @{ Name = 'Component'; Expression = { $item.Name } }, * } }
        }
        @{ Result = $result; Policy = $policy; PSRule = $psrule; Notices = $notices.ToArray(); GroupName = $groupName.Name; Alerts = @(& $withComponent 'Alerts'); Resiliency = @(& $withComponent 'Resiliency') }
    }

    # --- The report --------------------------------------------------------------------------------------------
    $result = $state.Result
    $stats = $result.Stats
    $policies = @(if ($state.Policy) { $state.Policy.Policies })
    $guardrails = @(if ($state.Policy) { $state.Policy.Guardrails })
    $alerts = @($state.Alerts)
    $resiliency = @($state.Resiliency)
    $resiliencyHigh = @($resiliency | Where-Object Impact -EQ 'High').Count
    $baselineSource = { param([string] $Set) $source = (Get-AACServiceBaseline -Set $Set -ResourceType @()).Source; "$($source.Name), commit $($source.Commit.Substring(0, 12)) ($($source.License))" }
    $scopeText = if ($SubscriptionId) { "subscription $SubscriptionId" } elseif ($ManagementGroupId) { "management group $ManagementGroupId" } else { 'none (policy not read)' }
    $severityTones = @{ Blocking = 'bad'; High = 'bad'; Medium = 'warn'; Low = 'info' }
    $statusTones = @{ Blocked = 'bad'; 'Needs attention' = 'warn'; Ready = 'good'; 'Not fully checked' = 'neutral' }
    $impactTones = @{ Blocks = 'bad'; 'Blocks delete' = 'bad'; Audits = 'warn'; Changes = 'info'; Deploys = 'info'; 'Reports only' = 'neutral'; Manual = 'neutral'; Unknown = 'neutral' }
    $outcomeTones = @{ Blocks = 'bad'; Refused = 'good'; 'Probably refused' = 'info'; Allowed = 'good'; 'Not refused' = 'warn'; Unknown = 'neutral' }
    $report = @{
        Subtitle = "$(@($result.Components).Count) planned resource(s) in $Region - nothing deployed"
        Facts    = [ordered]@{ Scope = $scopeText; Region = $Region; 'Resource group' = $state.GroupName; 'Naming convention' = $NamingConvention; 'Alerts from' = (& $baselineSource 'Alerts'); 'Resiliency from' = (& $baselineSource 'Resiliency') }
        Status   = $(if ($stats.Blocked) { 'Failed' } elseif ($stats.Attention -or $stats.NotChecked -or $state.Notices.Count) { 'Warning' } else { 'Success' })
        Headline = "$($stats.Components) planned resource(s): $($stats.Blocked) blocked, $($stats.Attention) need attention, $($stats.Ready) ready, $($stats.NotChecked) not fully checked"
        Tiles    = @(
            @{ Value = '{0:N0}' -f $stats.Components; Label = 'planned resources'; Tone = 'info'; Table = 'components' }
            @{ Value = '{0:N0}' -f $stats.Blocked; Label = 'blocked'; Tone = $(if ($stats.Blocked) { 'bad' } else { 'good' }); Table = 'components'; Filters = @{ Status = 'Blocked' } }
            @{ Value = '{0:N0}' -f $stats.High; Label = 'high findings'; Tone = $(if ($stats.High) { 'bad' } else { 'good' }); Table = 'findings'; Filters = @{ Severity = 'High' } }
            @{ Value = '{0:N0}' -f $stats.Medium; Label = 'medium findings'; Tone = $(if ($stats.Medium) { 'warn' } else { 'good' }); Table = 'findings'; Filters = @{ Severity = 'Medium' } }
            @{ Value = '{0:N0}' -f $policies.Count; Label = 'policies assigned'; Tone = 'violet'; Table = 'policies' }
            @{ Value = '{0:N0}' -f $alerts.Count; Label = 'suggested alerts'; Tone = 'info'; Table = 'alerts' }
            @{ Value = '{0:N0}' -f $resiliencyHigh; Label = 'high impact resiliency'; Tone = 'violet'; Table = 'resiliency'; Filters = @{ Impact = 'High' } }
        )
        Notices  = @($state.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
        Tabs     = @(
            @{ Name = 'Resources'; Badge = $stats.Components; Tone = 'info'; Note = 'What the blueprint would create, and where each stands. Not fully checked means a policy verdict or PSRule is missing, not that it passed.' }
            @{ Name = 'Findings'; Badge = @($result.Findings).Count; Tone = $(if ($stats.Blocking -or $stats.High) { 'bad' } else { 'warn' }); Note = 'What to do, worst first. PSRule rules about what a blueprint doesn''t plan, such as diagnostic settings, fail until you add it.' }
            @{ Name = 'Guardrails'; Badge = $guardrails.Count; Tone = 'violet'; Note = 'The limits your tenant sets. Source says how it is known: Azure Policy (checked) is Azure''s answer; the others are read from assignments.' }
            @{ Name = 'Policies'; Badge = $policies.Count; Tone = 'violet'; Note = 'The policies in force for each type, assigned at the scope or inherited. DeployIfNotExists and AuditIfNotExists act after a deployment, so Azure gives no verdict on them beforehand.' }
            @{ Name = 'Alerts'; Badge = $alerts.Count; Tone = 'info'; Note = 'What Azure Monitor Baseline Alerts suggests for each type. Suggestions, not results: they don''t change a status. Verified means the AMBA project has reviewed the alert.' }
            @{ Name = 'Resiliency'; Badge = $resiliency.Count; Tone = 'violet'; Note = 'What the Azure Proactive Resiliency Library recommends for each type. To review, not results: they don''t change a status, and the secure configuration may already cover some.' }
        )
        Tables   = @(
            @{ Id = 'components'; Title = 'Planned resources'; Section = 'Resources'; Rows = @($result.Components); Noun = 'resources'; File = 'blueprint-resources'
                Columns = @(
                    @{ Key = 'Name'; Label = 'Name'; Type = 'mono'; Console = $true; Pdf = $true }
                    @{ Key = 'Label'; Label = 'Resource'; Facet = $true; Pdf = $true }
                    @{ Key = 'Sku'; Label = 'SKU'; Pdf = $true }
                    @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = $statusTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Blocks'; Label = 'Blocks'; Type = 'number'; Format = 'N0'; Console = $true; Pdf = $true }
                    @{ Key = 'Audits'; Label = 'Audits'; Type = 'number'; Format = 'N0'; Console = $true; Pdf = $true }
                    @{ Key = 'PoliciesAssigned'; Label = 'Policies'; Type = 'number'; Format = 'N0'; Pdf = $true }
                    @{ Key = 'PSRuleFailed'; Label = 'PSRule failed'; Type = 'number'; Format = 'N0'; Console = $true; Pdf = $true }
                    @{ Key = 'PSRulePassed'; Label = 'PSRule passed'; Type = 'number'; Format = 'N0'; Pdf = $true }
                    @{ Key = 'BaselineAlerts'; Label = 'AMBA alerts'; Type = 'number'; Format = 'N0'; Console = $true; Pdf = $true }
                    @{ Key = 'ResiliencyTotal'; Label = 'APRL'; Type = 'number'; Format = 'N0'; Console = $true; Pdf = $true }
                    @{ Key = 'ResiliencyHigh'; Label = 'APRL high'; Type = 'number'; Format = 'N0'; Pdf = $true }
                    @{ Key = 'Planned'; Label = 'Configuration planned'; Facet = $true }
                    @{ Key = 'ResourceType'; Label = 'Type'; Type = 'mono' }
                    @{ Key = 'PolicyChecked'; Label = 'Verdict read'; Facet = $true }
                    @{ Key = 'PSRuleChecked'; Label = 'PSRule ran'; Facet = $true }
                    @{ Key = 'NameProblem'; Label = 'Name problem'; Type = 'wide' }
                ) }
            @{ Id = 'findings'; Title = 'Findings'; Section = 'Findings'; Rows = @($result.Findings); Noun = 'findings'; File = 'blueprint-findings'; GroupBy = @('Severity', 'Component', 'Source'); ConsoleLimit = 20
                Empty = 'No findings.'; EmptyStatus = 'Success'
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $severityTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Source'; Label = 'Source'; Facet = $true; Pdf = $true }
                    @{ Key = 'Component'; Label = 'Resource'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Item'; Label = 'Rule or assignment'; Type = 'mono'; Console = $true; Pdf = $true }
                    @{ Key = 'Detail'; Label = 'Finding'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Fix'; Label = 'What to do'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Link'; Label = 'Learn more'; Type = 'link'; Text = 'Docs' }
                ) }
            @{ Id = 'guardrails'; Title = 'Guardrails'; Section = 'Guardrails'; Rows = $guardrails; Noun = 'guardrails'; File = 'blueprint-guardrails'; GroupBy = @('Guardrail', 'Outcome')
                Columns = @(
                    @{ Key = 'Guardrail'; Label = 'Guardrail'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'AppliesTo'; Label = 'Applies to'; Type = 'mono'; Console = $true; Pdf = $true }
                    @{ Key = 'Outcome'; Label = 'Outcome'; Type = 'badge'; Tones = $outcomeTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Source'; Label = 'Source'; Facet = $true; Pdf = $true }
                    @{ Key = 'Assignment'; Label = 'Assignment'; Type = 'wide' }
                ) }
            @{ Id = 'policies'; Title = 'Policies in force'; Section = 'Policies'; Rows = $policies; Noun = 'policies'; File = 'blueprint-policies'; GroupBy = @('Component', 'Impact', 'Assignment'); NoConsole = $true
                Columns = @(
                    @{ Key = 'Component'; Label = 'Resource'; Facet = $true; Pdf = $true }
                    @{ Key = 'Impact'; Label = 'What it does'; Type = 'badge'; Tones = $impactTones; Facet = $true; Pdf = $true }
                    @{ Key = 'Policy'; Label = 'Policy'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Assignment'; Label = 'Assignment'; Facet = $true; Pdf = $true }
                    @{ Key = 'AssignedAt'; Label = 'Assigned at'; Facet = $true; Pdf = $true }
                    @{ Key = 'Effect'; Label = 'Effect'; Facet = $true }
                    @{ Key = 'Initiative'; Label = 'Initiative'; Facet = $true }
                    @{ Key = 'Enforcement'; Label = 'Enforcement'; Facet = $true }
                ) }
            @{ Id = 'alerts'; Title = 'Suggested alerts'; Section = 'Alerts'; Rows = $alerts; Noun = 'alerts'; File = 'blueprint-alerts'; GroupBy = @('Component', 'Severity', 'AlertType'); NoConsole = $true
                Empty = 'AMBA suggests no alert for these types. It covers some resource types, not all.'; EmptyStatus = 'Info'
                Columns = @(
                    @{ Key = 'Component'; Label = 'Resource'; Facet = $true; Pdf = $true }
                    @{ Key = 'Name'; Label = 'Alert'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'AlertType'; Label = 'Kind'; Facet = $true; Pdf = $true }
                    @{ Key = 'Severity'; Label = 'Severity'; Facet = $true; Pdf = $true }
                    @{ Key = 'Condition'; Label = 'Condition'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Window'; Label = 'Window' }
                    @{ Key = 'Verified'; Label = 'Verified'; Facet = $true }
                    @{ Key = 'Link'; Label = 'Learn more'; Type = 'link'; Text = 'Docs' }
                ) }
            @{ Id = 'resiliency'; Title = 'Resiliency recommendations'; Section = 'Resiliency'; Rows = $resiliency; Noun = 'recommendations'; File = 'blueprint-resiliency'; GroupBy = @('Component', 'Impact', 'Control'); NoConsole = $true
                Empty = 'APRL has no recommendation for these types. It covers some resource types, not all.'; EmptyStatus = 'Info'
                Columns = @(
                    @{ Key = 'Component'; Label = 'Resource'; Facet = $true; Pdf = $true }
                    @{ Key = 'Name'; Label = 'Recommendation'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Impact'; Label = 'Impact'; Type = 'badge'; Tones = @{ High = 'bad'; Medium = 'warn'; Low = 'info' }; Facet = $true; Pdf = $true }
                    @{ Key = 'Control'; Label = 'Area'; Facet = $true; Pdf = $true }
                    @{ Key = 'Benefit'; Label = 'Benefit'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Link'; Label = 'Learn more'; Type = 'link'; Text = 'Docs' }
                ) }
        )
        Hint     = '-SubscriptionId gets Azure''s verdict; -NamingConvention sets the names; -OutputFormat DrawIo, Html, Pdf with -Path writes the diagram and report; -Show opens them.'
    }

    $written = [System.Collections.Generic.List[string]]::new()
    if ($formats.Count -and $PSCmdlet.ShouldProcess($folder, "Write the blueprint as $($formats -join ', ')")) {
        $null = Invoke-AACProgress -ScriptBlock {
            if (-not (Test-Path -LiteralPath $folder)) { $null = New-Item -ItemType Directory -Path $folder -Force }
            $map = ConvertTo-AACServiceBlueprintMap -Component @($result.Components) -Finding @($result.Findings) -Region $Region -ResourceGroupName $state.GroupName
            $facts = @("Region $Region", "Scope: $scopeText", "Naming: $NamingConvention", 'Planned, not deployed')
            if ($formats -contains 'DrawIo') {
                Update-AACProgress -Id 'blueprint-drawio' -Indeterminate -Description 'Drawing the diagram'
                $asset = Get-AACResourceMapAsset
                $drawn = ConvertTo-AACServiceBlueprintDrawio -Map $map -Icons $asset.Icons -Title $reportTitle -Component @($result.Components) -Fact $facts
                [System.IO.File]::WriteAllText($drawioPath, $drawn.Xml, [System.Text.UTF8Encoding]::new($false))
                $written.Add($drawioPath)
                Update-AACProgress -Id 'blueprint-drawio' -Complete -Description "Diagram: $drawioPath"
            }
            $look = @{ Map = $map; Title = $reportTitle; Fact = $facts; Theme = 'light'; Layout = 'packed'; Hierarchy = 'packed' }
            if ($formats -contains 'Html') {
                $page = Join-Path -Path $folder -ChildPath "$base.html"
                Write-AACResourceMapHtml @look -Path $page
                $written.Add($page)
            }
            if ($formats -contains 'Pdf') {
                $page = Join-Path -Path $folder -ChildPath "$base.pdf"
                Update-AACProgress -Id 'blueprint-pdf' -Indeterminate -Description 'Drawing the PDF in a headless browser'
                Write-AACResourceMapPdf @look -Path $page
                $written.Add($page)
                Update-AACProgress -Id 'blueprint-pdf' -Complete -Description "PDF: $page"
            }
        }
        $reportHtml = if ($formats -contains 'Html') { Join-Path -Path $folder -ChildPath "$base-report.html" } else { '' }
        $reportPdf = if ($formats -contains 'Pdf') { Join-Path -Path $folder -ChildPath "$base-report.pdf" } else { '' }
        if ($reportHtml -or $reportPdf) { Invoke-AACReportOutput -Report $report -Title $reportTitle -HtmlPath $reportHtml -PdfPath $reportPdf }
        foreach ($file in @($reportHtml, $reportPdf) | Where-Object { $_ }) { $written.Add($file) }
    }
    elseif ($interactive -and -not $formats.Count) { Invoke-AACReportOutput -Report $report -Title $reportTitle -ShowView -NoPaging:$NoPaging }

    if ($interactive -and $written.Count) {
        foreach ($notice in @($state.Notices)) { Write-AACMarkup "[grey58]$([Spectre.Console.Markup]::Escape($notice))[/]" }
        foreach ($file in $written) { Write-AACMarkup "[grey58]Written: $([Spectre.Console.Markup]::Escape($file))[/]" }
    }
    if ($Show -and $written.Count) {
        $first = $written | Where-Object { $_ -like '*.html' -and $_ -notlike '*-report.html' } | Select-Object -First 1
        Open-AACFile -Path $(if ($first) { $first } else { $written[0] })
    }
    if ($PassThru -or $NoDisplay -or $pipedOnward) { $result.Components }
}
