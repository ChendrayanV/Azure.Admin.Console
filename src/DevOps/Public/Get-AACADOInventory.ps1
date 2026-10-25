function Get-AACADOInventory {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Inventories one or more Azure DevOps organizations - projects,
        pipelines (YAML, or classic with no YAML file - flagged) with their
        last run and delivery metrics, every task and tool they use (with
        versions), repositories, service connections, variable groups and
        environments with their security posture - as a Spectre.Console
        view, objects, and CSV, HTML and PDF reports.
    .DESCRIPTION
        Read-only, through the Azure DevOps REST API - nothing is changed.
        For each organization (-Organization, or -DiscoverOrganization) and
        project (or -Project), it reads:
          pipelines     every build pipeline: YAML or classic (designer,
                        no YAML file), its folder, repository, state and
                        last run, and every classic release pipeline
          steps         YAML pipelines' files from their default branch
                        (Azure Repos Git) and the templates they include -
                        local or template@repository, nested to
                        -TemplateDepth; the script files, package.json
                        scripts and Makefile targets they run (from the
                        pipeline's repository); classic pipelines' tasks,
                        named through the organization's task catalogue
          repositories  the last push, the branch policies on the default
                        branch, GitHub Advanced Security for Azure DevOps
                        (on or off, and active alerts by type and severity)
          security      service connections, variable groups and
                        environments: who may use them, their checks
          runs          the runs of the last -MetricDays and each
                        environment's deployments

        Tools: one catalogue (about 150 tools) is matched against every file
        a pipeline runs - its YAML and templates, script files, package.json
        scripts, Makefile targets, a classic pipeline's tasks - and against
        container images (fluxcd/flux-cli...). Categories: Lint, Build,
        Test, Security, Deploy, Publish, GitOps (Flux, Argo CD,
        Kustomize...) and Tooling (az, git, jq...). Every match is evidence
        (-View Evidence): the pipeline, the tool, its version (an installer
        task, an image tag), how it was found, the file and line, and the
        line itself (credentials masked). -View Tool is the matrix of tools
        with their pipelines, projects and versions; -View Coverage which
        stages each pipeline has; -View Unrecognised the commands scripts
        run that no rule knows (most-run first) and the templates and files
        that couldn't be read. -ToolRule and -ToolRulePath add tools of
        your own.

        Tasks (-View Task): every task with its major version and what it
        does (the task catalogue's description), packages installed at a
        version, shells, container images, agent images and pools.

        Findings: classic pipelines; never run, not run in -StaleDays, last
        run failed, disabled; no security scanning, no tests, no linting;
        deprecated or older task versions; unpinned container images;
        retired hosted images; a value that looks like a secret written in
        the YAML (its key and line - never the value); unreliable pipelines
        and long queues; service connections open to every pipeline, using a
        client secret rather than workload identity federation, or unused;
        variable groups with secrets outside Key Vault, secret-looking
        values not marked secret, open to every pipeline; production
        environments with no approval, environments with no checks or open
        to every pipeline; default branches with no required reviewers or
        build validation; Advanced Security off, exposed secrets, critical
        and high alerts; idle repositories.

        Delivery metrics over -MetricDays: each pipeline's runs, success
        rate (cancelled runs left out), average duration and queue time,
        runs a week; each environment's deployments, deployments a week,
        and change failure rate (DORA).

        Branching: every branch with its role (from its name - develop,
        release/*, hotfix/*, feature/*...), last commit, ahead and behind the
        default branch, stale after -StaleBranchDays, and the policies on it;
        each repository's strategy (GitFlow, trunk-based with release
        branches, trunk-based / GitHub flow, feature branching, single
        branch). Every branch policy, on or off, with its settings in words
        and its GitHub equivalent (rulesets, CODEOWNERS).

        DORA, per project and for the organization: deployment frequency,
        lead time (run queued to deployed), change failure rate and time to
        restore, from production environments and classic release stages
        (every environment when a project has no production one), each
        banded Elite, High, Medium or Low; overall is the weakest.

        Moving to GitHub: variables by name (pipeline settings, YAML,
        variable groups - secret or not, never values), Azure Artifacts feeds
        and their packages (and whether GitHub Packages can hold them), test
        plans, wikis, service hooks, open pull requests, Git LFS, agent pools
        and agents, marketplace extensions and the tasks pipelines use from
        them, Advanced Security settings per repository and project; a
        summary per project with rough effort points and a map of where each
        kind of thing lands on GitHub and the tool that moves it.

        -IncludeAzure (with Connect-AAC) follows each Azure service
        connection to its service principal and the Azure roles it holds,
        and flags pipeline identities that are Owner (or can grant access),
        or Contributor on a whole subscription.

        Signing in, in this order:
          -PersonalAccessToken   a PAT with read scopes: Build, Code,
                                 Project and Team, Release, Service
                                 Connections, Variable Groups, Environment,
                                 Advanced Security, Packaging, Test
                                 Management, Wiki, Agent Pools, Extensions
          AZURE_DEVOPS_EXT_PAT   the same, from the environment (the
                                 variable the Azure DevOps CLI reads)
          -UseAzureSignIn        your Connect-AAC sign-in (Microsoft Entra
                                 ID), for organizations connected to your
                                 tenant - no PAT to create or rotate
        The token is sent only to Azure DevOps and never written anywhere.
    .PARAMETER Organization
        One or more organizations: a name (contoso) or a URL
        (https://dev.azure.com/contoso or https://contoso.visualstudio.com).
    .PARAMETER DiscoverOrganization
        Add every organization the signed-in account is a member of (best
        with -UseAzureSignIn, or a PAT for all accessible organizations).
    .PARAMETER Project
        Only these projects, by name or ID.
    .PARAMETER PipelineId
        Only these build pipelines (definition IDs) - with -Project, as IDs
        are per project. Classic releases are then left out.
    .PARAMETER PersonalAccessToken
        A personal access token, as a SecureString (Read-Host -AsSecureString).
    .PARAMETER UseAzureSignIn
        Use the Connect-AAC sign-in instead of a PAT.
    .PARAMETER Skip
        Leave parts out, to read faster: Yaml (no YAML files or templates),
        Security (no service connections, variable groups, environments or
        branch policies), Metrics (no run history or deployments),
        AdvancedSecurity, Members (no Project Administrators or teams - who
        to contact), Branches (no branches, tags or branching strategy),
        Migration (no feeds, test plans, wikis, pull requests, agent pools,
        service hooks or extensions - the move-to-GitHub data).
    .PARAMETER SkipYaml
        The same as -Skip Yaml.
    .PARAMETER MetricDays
        The days of run history the delivery metrics cover (30 if not
        given; 1 to 365).
    .PARAMETER TemplateDepth
        How deep included templates are followed (3 if not given; 0 reads
        none).
    .PARAMETER StaleDays
        A pipeline not run in this many days is flagged (90 if not given).
    .PARAMETER InactiveDays
        A repository with no push in this many days is flagged (180 if not
        given).
    .PARAMETER StaleBranchDays
        A branch (not the default one) with no commit in this many days is
        stale (90 if not given).
    .PARAMETER ToolRule
        Tools of your own to look for: @(@{ Category = 'Security'; Tool =
        'Acme Scan'; Pattern = 'acme-scan' }). Category is Lint, Build, Test,
        Security, Deploy, Publish, GitOps or Tooling; Pattern a regular
        expression, matched ignoring case; Purpose (optional) says what the
        tool does.
    .PARAMETER ToolRulePath
        A .psd1 or .json file of rules in the -ToolRule shape - a list of
        @{ Category; Tool; Pattern; Purpose } - so a team keeps its own tools
        in a file. Added to -ToolRule.
    .PARAMETER MaxScriptFiles
        At most this many script files, package.json and Makefiles are read
        for one pipeline (25 if not given; 0 reads none).
    .PARAMETER IncludeAzure
        Link Azure service connections to their service principals' Azure
        role assignments (needs Connect-AAC, Microsoft Graph read access to
        service principals, and Reader on the scopes).
    .PARAMETER IncludeDisabledRepository
        List disabled repositories, and the pipelines that build them (with a
        finding each). By default both are left out, and the report says how
        many; a disabled repository's YAML is never read.
    .PARAMETER YamlPath
        Save every pipeline's YAML (and the templates it includes), and each
        classic pipeline's steps as JSON, under this folder - for offline
        review and diffs.
    .PARAMETER View
        What is returned and written to -CsvPath: Pipeline (default),
        Project, Repository, Task, Tool, Evidence, Coverage, Unrecognised,
        ServiceConnection, VariableGroup, Environment, Member (who to contact),
        Branch, BranchPolicy, Variable, Dora, Feed, TestPlan, AgentPool,
        Extension, Migration, MigrationMap or Finding.
    .PARAMETER ThrottleLimit
        How many requests run at once (1 to 32; 8 by default).
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
        $pat = Read-Host -Prompt 'Azure DevOps PAT' -AsSecureString
        Get-AACADOInventory -Organization contoso -PersonalAccessToken $pat
        Every project, pipeline and repository of the organization, with its tools, security posture and findings.
    .EXAMPLE
        Get-AACADOInventory -Organization contoso -PersonalAccessToken $pat -HtmlPath .\ADO.html -PdfPath .\ADO.pdf -CsvPath .\ADO.csv
        The same as reports.
    .EXAMPLE
        Get-AACADOInventory -Organization contoso -PersonalAccessToken $pat -View Task -NoDisplay | Where-Object Kind -EQ 'CLI' | Group-Object -Property Name, Version
        Every command-line tool the pipelines run, and the versions they set.
    .EXAMPLE
        Get-AACADOInventory -Organization contoso -PersonalAccessToken $pat -View ServiceConnection -NoDisplay | Where-Object OpenToAllPipelines
        Service connections any pipeline can use.
    .EXAMPLE
        Connect-AAC
        Get-AACADOInventory -DiscoverOrganization -UseAzureSignIn -IncludeAzure -HtmlPath .\ADO.html
        Every organization you belong to, with each Azure service connection's roles in Azure.
    .EXAMPLE
        Get-AACADOInventory -Organization contoso -PersonalAccessToken $pat -View Migration -NoDisplay | Sort-Object -Property Effort -Descending
        Projects by how much work the move to GitHub is.
    .EXAMPLE
        Get-AACADOInventory -Organization contoso -Project Payments -PersonalAccessToken $pat -YamlPath .\pipelines -Skip Security, Metrics
        Save the project's pipelines and templates to a folder, to review or diff offline.
    .OUTPUTS
        AAC.DevOpsPipeline, AAC.DevOpsProject, AAC.DevOpsRepository, AAC.DevOpsTask, AAC.DevOpsToolUsage, AAC.DevOpsServiceConnection, AAC.DevOpsVariableGroup, AAC.DevOpsEnvironment, AAC.DevOpsMember, AAC.DevOpsToolEvidence, AAC.DevOpsCoverage, AAC.DevOpsUnrecognised, AAC.DevOpsBranch, AAC.DevOpsBranchPolicy, AAC.DevOpsVariable, AAC.DevOpsDora, AAC.DevOpsFeed, AAC.DevOpsTestPlan, AAC.DevOpsAgentPool, AAC.DevOpsExtension, AAC.DevOpsMigration, AAC.DevOpsMigrationMap or AAC.DevOpsFinding, by -View (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.DevOpsPipeline', 'AAC.DevOpsProject', 'AAC.DevOpsRepository', 'AAC.DevOpsTask', 'AAC.DevOpsToolUsage', 'AAC.DevOpsServiceConnection', 'AAC.DevOpsVariableGroup', 'AAC.DevOpsEnvironment', 'AAC.DevOpsMember', 'AAC.DevOpsToolEvidence', 'AAC.DevOpsCoverage', 'AAC.DevOpsUnrecognised', 'AAC.DevOpsBranch', 'AAC.DevOpsBranchPolicy', 'AAC.DevOpsVariable', 'AAC.DevOpsDora', 'AAC.DevOpsFeed', 'AAC.DevOpsTestPlan', 'AAC.DevOpsAgentPool', 'AAC.DevOpsExtension', 'AAC.DevOpsMigration', 'AAC.DevOpsMigrationMap', 'AAC.DevOpsFinding')]
    param(
        [string[]] $Organization,

        [switch] $DiscoverOrganization,

        [Alias('ProjectId')]
        [string[]] $Project,

        [int[]] $PipelineId,

        [Alias('PAT')]
        [System.Security.SecureString] $PersonalAccessToken,

        [switch] $UseAzureSignIn,

        [ValidateSet('Yaml', 'Security', 'Metrics', 'AdvancedSecurity', 'Members', 'Branches', 'Migration')]
        [string[]] $Skip = @(),

        [switch] $SkipYaml,

        [ValidateRange(1, 365)]
        [int] $MetricDays = 30,

        [ValidateRange(0, 10)]
        [int] $TemplateDepth = 3,

        [ValidateRange(1, 3650)]
        [int] $StaleDays = 90,

        [ValidateRange(1, 3650)]
        [int] $InactiveDays = 180,

        [ValidateRange(1, 3650)]
        [int] $StaleBranchDays = 90,

        [object[]] $ToolRule,

        [string] $ToolRulePath,

        [ValidateRange(0, 200)]
        [int] $MaxScriptFiles = 25,

        [switch] $IncludeAzure,

        [switch] $IncludeDisabledRepository,

        [string] $YamlPath,

        [ValidateSet('Pipeline', 'Project', 'Repository', 'Task', 'Tool', 'Evidence', 'Coverage', 'Unrecognised', 'ServiceConnection', 'VariableGroup', 'Environment', 'Member', 'Branch', 'BranchPolicy', 'Variable', 'Dora', 'Feed', 'TestPlan', 'AgentPool', 'Extension', 'Migration', 'MigrationMap', 'Finding')]
        [string] $View = 'Pipeline',

        [ValidateRange(1, 32)]
        [int] $ThrottleLimit = 8,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Azure DevOps inventory',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $parts = @(@($Skip) + @(if ($SkipYaml) { 'Yaml' }) | Select-Object -Unique)

    # An organization's URL: a name, dev.azure.com/<name>, or the older <name>.visualstudio.com.
    $toUrl = {
        param([string] $Name)
        $url = if ($Name -match '^https?://') { $Name.TrimEnd('/') -replace '^http://', 'https://' } elseif ($Name.Contains('.')) { "https://$($Name.TrimEnd('/'))" } else { "https://dev.azure.com/$Name" }
        if ($url -notmatch '^https://(dev\.azure\.com/[^/]+|[^/.]+\.visualstudio\.com)$') {
            throw "Azure Admin Console can't read '$Name' as an Azure DevOps organization. Give its name (contoso) or its URL (https://dev.azure.com/contoso)."
        }
        $url
    }
    $orgUrls = [System.Collections.Generic.List[string]]::new()
    foreach ($name in @($Organization | Where-Object { $_ })) { $u = & $toUrl $name; if (-not $orgUrls.Contains($u)) { $orgUrls.Add($u) } }
    if (-not $orgUrls.Count -and -not $DiscoverOrganization) {
        throw 'Azure Admin Console needs an organization: -Organization contoso (one or more), or -DiscoverOrganization for every one you are a member of.'
    }

    # Signing in: a PAT (the parameter, or AZURE_DEVOPS_EXT_PAT), or the Connect-AAC sign-in.
    $authentication = ''
    $authorization = if ($PersonalAccessToken) {
        $authentication = 'Personal access token'
        $plain = [System.Net.NetworkCredential]::new('', $PersonalAccessToken).Password
        'Basic ' + [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$plain"))
        $plain = $null
    }
    elseif ($env:AZURE_DEVOPS_EXT_PAT -and -not $UseAzureSignIn) {
        $authentication = 'Personal access token (AZURE_DEVOPS_EXT_PAT)'
        'Basic ' + [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$env:AZURE_DEVOPS_EXT_PAT"))
    }
    elseif ($UseAzureSignIn) {
        $authentication = 'Azure sign-in (Microsoft Entra ID)'
        # Azure DevOps' own application ID is its token audience.
        'Bearer ' + (Get-AACAccessToken -Resource '499b84ac-1321-427f-aa17-267ca6975798')
    }
    else {
        throw 'Azure Admin Console needs a way to sign in to Azure DevOps: -PersonalAccessToken (read scopes: Build, Code, Project and Team, Release), the AZURE_DEVOPS_EXT_PAT environment variable, or -UseAzureSignIn after Connect-AAC.'
    }

    $rules = @(Get-AACDevOpsToolRule)
    # A hashtable or an object: Category, Tool, Pattern.
    $field = { param($Entry, [string] $Name) if ($Entry -is [System.Collections.IDictionary]) { [string](Get-AACMember -InputObject $Entry -Path $Name) } elseif ($Entry.PSObject.Properties[$Name]) { [string]$Entry.PSObject.Properties[$Name].Value } else { '' } }
    # Rules from a file (.psd1: @( @{...}, ... ) or @{ Rules = @(...) }; .json: a list) join -ToolRule.
    $fromFile = @()
    if ($ToolRulePath) {
        $rulePath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ToolRulePath)
        if (-not (Test-Path -LiteralPath $rulePath)) { throw "Azure Admin Console can't find the rule file $rulePath. Give the path of a .psd1 or .json file of rules." }
        $loaded = if ($rulePath -match '\.json$') { ConvertFrom-Json -InputObject (Get-Content -LiteralPath $rulePath -Raw) -AsHashtable } else { Import-PowerShellDataFile -LiteralPath $rulePath }
        $fromFile = @(if ($loaded -is [System.Collections.IDictionary] -and $loaded.Contains('Rules')) { $loaded['Rules'] } else { $loaded })
    }
    foreach ($custom in @(@($ToolRule) + @($fromFile) | Where-Object { $_ })) {
        $category = & $field $custom 'Category'
        $tool = & $field $custom 'Tool'
        $pattern = & $field $custom 'Pattern'
        if ($category -notin 'Lint', 'Build', 'Test', 'Security', 'Deploy', 'Publish', 'GitOps', 'Tooling' -or -not $tool -or -not $pattern) {
            throw "Azure Admin Console can't use the -ToolRule entry for '$tool': give Category (Lint, Build, Test, Security, Deploy, Publish, GitOps or Tooling), Tool and Pattern."
        }
        try { $null = [regex]::new($pattern) } catch { throw "Azure Admin Console can't use the -ToolRule pattern for '$tool': $($_.Exception.Message)" }
        $rules += [pscustomobject]@{ Category = $category; Tool = $tool; Pattern = $pattern; Purpose = $(& $field $custom 'Purpose'); VersionOf = $tool }
    }
    $cliRules = Get-AACDevOpsCliRule
    $yamlFolder = & $resolve $YamlPath

    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Azure DevOps inventory' -Color 'dodgerblue1' }
    $state = Invoke-AACProgress -ScriptBlock {
        $notices = [System.Collections.Generic.List[string]]::new()
        if ($DiscoverOrganization) {
            # The account's member ID, then the organizations it belongs to.
            Update-AACProgress -Id 'read' -Indeterminate -Description 'Finding your organizations'
            $profileUri = 'https://app.vssps.visualstudio.com/_apis/profile/profiles/me?api-version=7.1'
            $me = (Invoke-AACArmParallel -Uri $profileUri -Authorization $authorization)[$profileUri]
            $memberId = if ($me -and -not $me['Error']) { [string](Get-AACMember -InputObject $me['Body'] -Path 'id') } else { '' }
            $accounts = @()
            if ($memberId) {
                $accountsUri = "https://app.vssps.visualstudio.com/_apis/accounts?memberId=$memberId&api-version=7.1"
                $answer = (Invoke-AACArmParallel -Uri $accountsUri -Authorization $authorization)[$accountsUri]
                $accounts = @(if ($answer -and -not $answer['Error']) { $answer['Items'] | Where-Object { $_ } })
            }
            $before = $orgUrls.Count
            foreach ($a in $accounts) { $u = & $toUrl ([string]$a['accountName']); if (-not $orgUrls.Contains($u)) { $orgUrls.Add($u) } }
            if (-not $memberId -or -not $accounts.Count) {
                $reason = if (-not $me -or $me['Error']) { $(if ($me) { [string]$me['Error'] } else { 'no answer' }) } else { 'no organization listed' }
                $message = "Azure Admin Console couldn't list your Azure DevOps organizations ($reason). Use -UseAzureSignIn, or a PAT for all accessible organizations - or name them with -Organization."
                if (-not $orgUrls.Count) { throw $message }
                $notices.Add($message)
            }
            elseif ($orgUrls.Count -eq $before) { $notices.Add('-DiscoverOrganization found no organization beyond those named.') }
        }

        $reads = [System.Collections.Generic.List[hashtable]]::new()
        $saved = 0
        foreach ($orgUrl in $orgUrls) {
            Update-AACProgress -Id 'read' -Indeterminate -Description "Reading $orgUrl"
            # A line for each stage of the read, with its bar: the stage, the project whose request just
            # finished, the projects done and the time left. The names are prefixed 'ado': the script
            # block runs inside the reader and Invoke-AACArmParallel, whose variables would hide ours.
            $adoProgress = @{ Org = $orgUrl; Prefix = $(if ($orgUrls.Count -gt 1) { "$($orgUrl -replace '^https://(dev\.azure\.com/)?', ''): " } else { '' }); Current = ''; Stage = ''; Done = @{} }
            $adoFinishStage = { if ($adoProgress.Current) { Update-AACProgress -Id $adoProgress.Current -Complete -Description "$($adoProgress.Prefix)$($adoProgress.Stage) - done" } }
            try {
                $read = Read-AACDevOpsInventory -OrganizationUrl $orgUrl -Authorization $authorization -Project $Project -PipelineId $PipelineId -Skip $parts -MetricDays $MetricDays -TemplateDepth $TemplateDepth -MaxScriptFiles $MaxScriptFiles -ThrottleLimit $ThrottleLimit -OnProgress {
                    param($Step, $Text, $Done, $Total)
                    $adoLine = "$($adoProgress.Org)|$Step"
                    if ($adoProgress.Current -ne $adoLine) { & $adoFinishStage; $adoProgress.Current = $adoLine; $adoProgress.Done[$adoLine] = 0 }
                    $adoProgress.Stage = ([string]$Text -split ' - ', 2)[0]
                    Update-AACProgress -Id $adoLine -Description "$($adoProgress.Prefix)$Text" -Total $Total -Increment ($Done - $adoProgress.Done[$adoLine])
                    $adoProgress.Done[$adoLine] = $Done
                }
                & $adoFinishStage
            }
            catch {
                # One organization that can't be read doesn't stop the others.
                if ($orgUrls.Count -eq 1) { throw }
                $notices.Add("$orgUrl was left out: $($_.Exception.Message)")
                continue
            }
            $reads.Add($read)
            $releaseErrors = @($read.Releases.Values | Where-Object { $_ -and $_['Error'] })
            if ($releaseErrors.Count) { $notices.Add("$($read.OrganizationName): classic releases couldn't be read in $($releaseErrors.Count) project(s): $([string]$releaseErrors[0]['Error']) - give the token Release (Read) to include them.") }
            if ($parts -notcontains 'Security') {
                $endpointErrors = @($read.Endpoints.Values | Where-Object { $_ -and $_['Error'] })
                if ($endpointErrors.Count) { $notices.Add("$($read.OrganizationName): service connections couldn't be read in $($endpointErrors.Count) project(s): $([string]$endpointErrors[0]['Error']) - give the token Service Connections (Read) and Variable Groups (Read).") }
            }
            if ($yamlFolder) { $saved += Save-AACDevOpsYaml -Read $read -Path $yamlFolder }
        }
        if (-not $reads.Count) { throw "Azure Admin Console couldn't read any organization. $($notices -join ' ')" }
        $yamlRead = @($reads | ForEach-Object { $_.Yaml.Values } | Where-Object { $_.Content }).Count
        Update-AACProgress -Id 'read' -Complete -Description ('Read {0:N0} organization(s), {1:N0} project(s) and {2:N0} YAML file(s)' -f $reads.Count, @($reads | ForEach-Object { $_.Projects }).Count, $yamlRead)
        if ($yamlFolder) { $notices.Add("Saved $saved pipeline and template file(s) to $yamlFolder.") }

        # Azure: the service principals behind the Azure service connections, and their roles.
        $azureLink = @{}
        if ($IncludeAzure) {
            Update-AACProgress -Id 'azure' -Indeterminate -Description 'Reading the service connections'' Azure roles'
            $appIds = @($reads | ForEach-Object { $rd = $_; $rd.Endpoints.Values } | ForEach-Object { if ($_ -and -not $_['Error']) { $_['Items'] } } | Where-Object { $_ -and [string]$_['type'] -eq 'azurerm' } | ForEach-Object { [string](Get-AACMember -InputObject $_ -Path 'authorization.parameters.serviceprincipalid') } | Where-Object { $_ })
            try {
                $linked = Get-AACDevOpsAzureLink -AppId $appIds
                $azureLink = $linked.Link
                foreach ($problem in $linked.Errors) { $notices.Add("Azure link: $problem") }
            }
            catch { $notices.Add("Azure Admin Console couldn't read the Azure roles (-IncludeAzure): $($_.Exception.Message) Run Connect-AAC first.") }
            Update-AACProgress -Id 'azure' -Complete -Description "Linked $($azureLink.Count) of $(@($appIds | Select-Object -Unique).Count) service principal(s) to Azure"
        }

        # One organization's rows after another; the totals added up.
        $result = @{ Projects = @(); Pipelines = @(); Tasks = @(); Repositories = @(); ServiceConnections = @(); VariableGroups = @(); Environments = @(); Members = @(); Branches = @(); BranchPolicies = @(); Variables = @(); Dora = @(); Feeds = @(); TestPlans = @(); AgentPools = @(); Extensions = @(); Migration = @(); MigrationMap = @(); Tools = @(); Evidence = @(); Coverage = @(); Unrecognised = @(); Findings = @(); Stats = @{} }
        $doraByOrg = [System.Collections.Generic.List[hashtable]]::new()
        foreach ($read in $reads) {
            # Working through thousands of pipelines takes a while too: a line of its own, with the time left.
            # (Names prefixed 'ado': the script block runs inside the converter, whose variables would hide ours.)
            $adoAnalysis = @{ Id = "analyse|$($read.Organization)"; Started = [datetime]::UtcNow; Done = 0; Prefix = $(if ($reads.Count -gt 1) { "$($read.OrganizationName): " } else { '' }) }
            $one = ConvertTo-AACDevOpsInventory -Read $read -ToolRule $rules -CliRule $cliRules -StaleDays $StaleDays -InactiveDays $InactiveDays -StaleBranchDays $StaleBranchDays -AzureLink $azureLink -IncludeDisabledRepository:$IncludeDisabledRepository -OnProgress {
                param($ProjectName, $Done, $Total)
                $adoElapsed = ([datetime]::UtcNow - $adoAnalysis.Started).TotalSeconds
                $adoFraction = $Done / [Math]::Max(1, $Total)
                $adoLeft = if ($adoFraction -lt 0.05 -or $adoElapsed -lt 3) { 'estimating' } else { $adoSeconds = $adoElapsed / $adoFraction - $adoElapsed; if ($adoSeconds -lt 60) { '< 1 min left' } else { '~{0:N0} min left' -f [Math]::Ceiling($adoSeconds / 60) } }
                Update-AACProgress -Id $adoAnalysis.Id -Description ('{0}Analysing pipelines - {1:N0}/{2:N0} - {3} - {4}' -f $adoAnalysis.Prefix, $Done, $Total, $adoLeft, $ProjectName) -Total $Total -Increment ($Done - $adoAnalysis.Done)
                $adoAnalysis.Done = $Done
            }
            Update-AACProgress -Id $adoAnalysis.Id -Complete -Description ('{0}Analysed {1:N0} pipeline(s)' -f $adoAnalysis.Prefix, $adoAnalysis.Done)
            if ($one.MembersError) { $notices.Add("$($read.OrganizationName): who to contact couldn't be read for every project: $($one.MembersError) - give the token Identity (Read) and Project and Team (Read), or -Skip Members.") }
            if ($one.Stats.DisabledRepositories -or $one.Stats.DisabledPipelines) { $notices.Add("$($read.OrganizationName): left out $($one.Stats.DisabledRepositories) disabled repository(ies) and the $($one.Stats.DisabledPipelines) pipeline(s) that build them - -IncludeDisabledRepository lists them.") }
            foreach ($k in @($result.Keys | Where-Object { $_ -ne 'Stats' })) { $result[$k] += @($one[$k]) }
            # The DORA keys are levels and medians - they don't add up across organizations: kept per organization.
            $doraByOrg.Add(@{ Organization = $read.OrganizationName; Dora = $one.Stats.Dora })
            foreach ($k in @($one.Stats.Keys | Where-Object { $_ -ne 'Dora' })) { $result.Stats[$k] = $(if ($result.Stats.ContainsKey($k)) { $result.Stats[$k] } else { 0 }) + $one.Stats[$k] }
        }
        $rank = @{ High = 0; Medium = 1; Low = 2; Info = 3 }
        $result.Findings = @($result.Findings | Sort-Object -Property @{ Expression = { $rank[$_.Severity] } }, Organization, Project, Item, Finding)
        $result.Stats.Dora = $(if ($doraByOrg.Count -eq 1) { $doraByOrg[0].Dora } else { @{} })
        @{ Result = $result; Notices = $notices.ToArray(); Organizations = @($reads | ForEach-Object { $_.Organization }) }
    }
    $authorization = $null

    # --- Report ------------------------------------------------------------------------------------------------
    $r = $state.Result
    $s = $r.Stats
    $multi = @($state.Organizations).Count -gt 1
    $rank = Get-AACSeverityRank
    $yesBad = @{ True = 'bad'; False = 'good' }
    $kindTones = @{ YAML = 'good'; 'Classic build' = 'warn'; 'Classic release' = 'warn' }
    $resultTones = @{ succeeded = 'good'; failed = 'bad'; partiallySucceeded = 'warn'; canceled = 'neutral'; 'Never run' = 'neutral'; 'Never released' = 'neutral' }
    $categoryTones = @{ Security = 'good'; Test = 'info'; Lint = 'violet'; Build = 'neutral'; Deploy = 'warn'; Publish = 'neutral'; GitOps = 'info'; Tooling = 'neutral' }
    $pipelines = @($r.Pipelines | Sort-Object -Property Organization, Project, @{ Expression = { @('YAML', 'Classic build', 'Classic release').IndexOf($_.Kind) } }, Pipeline)
    $toolColumns = foreach ($c in 'Lint', 'Build', 'Test', 'Security', 'Deploy', 'Publish', 'GitOps') { @{ Key = $c; Label = $c; Type = 'wide'; Console = $c -in 'Security', 'Test'; Pdf = $c -in 'Security', 'Test', 'Build' } }
    $orgColumn = @{ Key = 'Organization'; Label = 'Organization'; Facet = $true; Console = $multi; Pdf = $multi }
    $openColumn = @{ Key = 'OpenToAllPipelines'; Label = 'Open to all pipelines'; Type = 'badge'; Tones = $yesBad; Facet = $true; Console = $true; Pdf = $true }
    $findingsColumn = @{ Key = 'Findings'; Label = 'Findings'; Type = 'number'; Sum = $true; Console = $true }
    $openColumnLink = @{ Key = 'Url'; Label = 'Open'; Type = 'link'; Text = 'Open' }
    $orgLabel = (@($state.Organizations) | ForEach-Object { $_ -replace '^https://(dev\.azure\.com/)?', '' }) -join ', '
    $deployRate = if ($s.Deployments) { '{0:N1}%' -f (100.0 * $s.FailedDeployments / $s.Deployments) } else { '-' }
    $dora = if ($s.Dora -is [hashtable]) { $s.Dora } else { @{} }
    $doraTones = @{ Elite = 'good'; High = 'info'; Medium = 'warn'; Low = 'bad' }
    $doraTone = if ($dora['Overall']) { $doraTones[$dora['Overall']] } else { 'neutral' }
    $complexityTones = @{ Low = 'good'; Medium = 'warn'; High = 'bad' }
    $doraText = if ($dora['Overall']) { "Organization: $($dora['Overall']) - $($dora['DeploymentsPerWeek']) deployments a week ($($dora['Frequency'])), lead time $($dora['LeadTimeHours']) h ($($dora['LeadTime'])), change failure $($dora['ChangeFailureRate'])% ($($dora['ChangeFailure'])), time to restore $(if ($null -ne $dora['TimeToRestoreHours']) { "$($dora['TimeToRestoreHours']) h ($($dora['TimeToRestore']))" } else { 'no failure to restore' }). " } else { '' }
    $report = @{
        Subtitle = "Azure DevOps - $orgLabel"
        # The HTML report's project selector: every table with a Project column filtered to the one chosen,
        # the project's facts from the Overview table and its people from the People table.
        Scope    = @{ Key = 'Project'; Label = 'Project'; Values = @($r.Projects | ForEach-Object { $_.Project } | Sort-Object -Unique); Card = 'projects'; Contacts = 'members' }
        Facts    = [ordered]@{ Organizations = $orgLabel; Projects = $(if ($Project) { $Project -join ', ' } else { 'all' }); 'Signed in with' = $authentication; 'Metrics over' = "$MetricDays days"; Generated = "$([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture)) UTC" }
        Status   = $(if ($s.High) { 'Failed' } elseif (@($r.Findings | Where-Object { $_.Severity -ne 'Info' }).Count) { 'Warning' } else { 'Success' })
        Headline = "$($s.Projects) project(s), $($s.Pipelines) pipeline(s): $($s.Yaml) YAML, $($s.ClassicBuild) classic build and $($s.ClassicRelease) classic release; $($s.WithScanning) of $($s.YamlRead) pipeline(s) read scan for security; $($s.OpenResources) resource(s) open to every pipeline; $($s.NeverRun) never run, $($s.Stale) not run in $StaleDays days, $($s.Failed) failing"
        Tiles    = @(
            @{ Value = '{0:N0}' -f $s.Projects; Label = 'projects'; Tone = 'info'; Table = 'projects' }
            @{ Value = '{0:N0}' -f $s.Pipelines; Label = 'pipelines'; Tone = 'info'; Table = 'pipelines' }
            @{ Value = '{0:N0}' -f ($s.ClassicBuild + $s.ClassicRelease); Label = 'classic (no YAML)'; Tone = $(if ($s.ClassicBuild + $s.ClassicRelease) { 'warn' } else { 'good' }); Table = 'findings'; Filters = @{ Finding = 'Classic build pipeline (no YAML)' } }
            @{ Value = $(if ($s.YamlRead) { '{0:N0}%' -f (100 * $s.WithScanning / $s.YamlRead) } else { '-' }); Label = 'with security scanning'; Tone = $(if ($s.YamlRead -and $s.WithScanning -eq $s.YamlRead) { 'good' } else { 'warn' }); Table = 'findings'; Filters = @{ Finding = 'No security scanning' } }
            @{ Value = '{0:N0}' -f $s.OpenResources; Label = 'open to every pipeline'; Tone = $(if ($s.OpenResources) { 'bad' } else { 'good' }); Table = 'findings'; Filters = @{ Finding = 'Open to every pipeline' } }
            @{ Value = '{0:N0}' -f $s.Deployments; Label = "deployments in $MetricDays days"; Tone = 'info'; Table = 'environments' }
            @{ Value = $deployRate; Label = 'change failure rate'; Tone = $(if ($s.FailedDeployments) { 'warn' } else { 'good' }); Table = 'environments' }
            @{ Value = $(if ($dora['Overall']) { $dora['Overall'] } else { '-' }); Label = 'DORA level'; Tone = $doraTone; Table = 'dora' }
            @{ Value = '{0:N0}' -f $s.HighComplexity; Label = 'projects hard to move to GitHub'; Tone = $(if ($s.HighComplexity) { 'warn' } else { 'good' }); Table = 'migration'; Filters = @{ Complexity = 'High' } }
            @{ Value = '{0:N0}' -f $s.High; Label = 'high findings'; Tone = $(if ($s.High) { 'bad' } else { 'good' }); Table = 'findings'; Filters = @{ Severity = 'High' } }
        )
        Notices  = @($state.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
        Charts   = @(
            @{ Title = 'Pipelines by kind'; Kind = 'donut'; CenterLabel = 'pipelines'; Items = @(foreach ($k in 'YAML', 'Classic build', 'Classic release') { $n = @($r.Pipelines | Where-Object { $_.Kind -eq $k }).Count; if ($n) { @{ Label = $k; Value = $n; Tone = $kindTones[$k]; Filter = $k } } }); Table = 'pipelines'; Column = 'Kind' }
            @{ Title = 'Findings by area'; Kind = 'donut'; CenterLabel = 'findings'; Items = @($r.Findings | Group-Object -Property Area | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'findings'; Column = 'Area' }
            @{ Title = 'Security tools'; Items = @($r.Tools | Where-Object { $_.Category -eq 'Security' } | Select-Object -First 12 | ForEach-Object { @{ Label = $_.Tool; Value = $_.Pipelines; Filter = $_.Tool } }); Table = 'tools'; Column = 'Tool'; Tone = 'good'; Console = $true }
            @{ Title = 'Most-used tools (pipelines)'; Items = @($r.Tools | Sort-Object -Property @{ Expression = { $_.Pipelines }; Descending = $true } | Select-Object -First 12 | ForEach-Object { @{ Label = $_.Tool; Value = $_.Pipelines; Filter = $_.Tool } }); Table = 'evidence'; Column = 'Tool'; Tone = 'info' }
            @{ Title = 'Pipelines using each kind of tool'; Items = @(foreach ($c in 'Lint', 'Build', 'Test', 'Security', 'Deploy', 'Publish', 'GitOps') { @{ Label = $c; Value = @($r.Pipelines | Where-Object { $_.$c }).Count; Filter = $c } }); Table = 'tools'; Column = 'Category'; Tone = 'info' }
        )
        Tabs     = @(
            @{ Name = 'Overview'; Badge = $s.Projects; Tone = 'info'; Note = 'Each project: its pipelines by kind, how many scan for security, its repositories and security resources, the last run and the last push, and who to contact. Choose a project above to see only its rows in every tab.' }
            @{ Name = 'People'; Badge = @($r.Members).Count; Tone = 'violet'; Note = 'Who to contact in each project: its Project Administrators (users, or groups in that group), its team admins and team members - one row per person, with their roles and teams.' }
            @{ Name = 'Pipelines'; Badge = $s.Pipelines; Tone = $(if ($s.ClassicBuild) { 'warn' } else { 'good' }); Note = "Every pipeline - YAML, classic build or classic release - with its last run, its delivery metrics over $MetricDays days, the tools found in its steps, and what it connects to." }
            @{ Name = 'Tasks'; Badge = @($r.Tasks).Count; Tone = 'info'; Note = 'Every task (with its version and what it does), command-line tool (with the version an installer task or the script sets), package, container, agent image and pool - YAML and classic.' }
            @{ Name = 'Repositories'; Badge = $s.Repositories; Tone = 'violet'; Note = 'Every Git repository: its last push, the branch policies on its default branch, and GitHub Advanced Security with its active alerts.' }
            @{ Name = 'Branches'; Badge = $s.Branches; Tone = $(if ($s.StaleBranches) { 'warn' } else { 'violet' }); Note = "Every branch of every repository: its role (from its name), last commit, how far ahead and behind the default branch, stale after $StaleBranchDays days, and the policies on it. The Repositories tab names each repository's branching strategy." }
            @{ Name = 'Branch policies'; Badge = $s.BranchPolicies; Tone = 'violet'; Note = 'Every branch policy - on or off, blocking or optional - with the branch (or prefix) it covers, its settings in words, and what it becomes on GitHub.' }
            @{ Name = 'Service connections'; Badge = @($r.ServiceConnections).Count; Tone = $(if (@($r.ServiceConnections | Where-Object { $_.OpenToAllPipelines }).Count) { 'bad' } else { 'good' }); Note = 'Who may use each service connection, how it signs in, which pipelines use it, and (with -IncludeAzure) its roles in Azure.' }
            @{ Name = 'Variable groups'; Badge = @($r.VariableGroups).Count; Tone = 'info'; Note = 'Each variable group: Key Vault or Azure DevOps, its secrets (names only), who may use it.' }
            @{ Name = 'Environments'; Badge = @($r.Environments).Count; Tone = 'info'; Note = "Each environment: its checks and approvals, who may deploy, and its deployments over $MetricDays days with the change failure rate." }
            @{ Name = 'Variables'; Badge = @($r.Variables).Count; Tone = 'info'; Note = 'Every variable by name - pipeline settings, YAML and variable groups - secret or not, and where it goes on GitHub. Values are never read; secrets must be re-created by hand.' }
            @{ Name = 'DORA'; Badge = @($r.Dora).Count; Tone = $doraTone; Note = "$($doraText)The four DORA keys per project over $MetricDays days, from production deployments (environments named prod, production, prd or live) or, when a project has none, every environment: deployment frequency, lead time (run queued to deployed), change failure rate and time to restore (a failure to the next success) - each with its band (Elite, High, Medium, Low); overall is the weakest." }
            @{ Name = 'Artifacts'; Badge = @($r.Feeds).Count; Tone = $(if (@($r.Feeds | Where-Object { $_.Unsupported }).Count) { 'warn' } else { 'info' }); Note = 'Each Azure Artifacts feed: its packages by type, upstream sources, and whether GitHub Packages can hold them (npm, NuGet, Maven - not PyPI, Universal Packages or Cargo).' }
            @{ Name = 'Test plans'; Badge = @($r.TestPlans).Count; Tone = $(if (@($r.TestPlans).Count) { 'warn' } else { 'good' }); Note = 'Each test plan - GitHub has no test case management, so these stay in Azure Test Plans or move to another tool.' }
            @{ Name = 'Agents and extensions'; Badge = @($r.AgentPools).Count + @($r.Extensions).Count; Tone = 'info'; Note = 'Agent pools (self-hosted agents become self-hosted runners) and the marketplace extensions installed, with the pipelines whose tasks come from them.' }
            @{ Name = 'Migration'; Badge = @($r.Migration).Count; Tone = $(if ($s.HighComplexity) { 'warn' } else { 'good' }); Note = 'Moving to GitHub: per project, what there is to move and a rough effort (classic pipelines, marketplace tasks, secrets, feeds, test plans, large or LFS repositories weigh most) - then where each kind of thing lands on GitHub and the tool that moves it.' }
            @{ Name = 'Tools'; Badge = @($r.Tools).Count; Tone = 'info'; Note = 'Each tool by category: how many pipelines and projects use it, the versions seen and how it was found.' }
            @{ Name = 'Coverage'; Badge = @($r.Coverage).Count; Tone = 'info'; Note = 'Which stages each build pipeline has: lint, build, test, security, deploy, publish, GitOps.' }
            @{ Name = 'Evidence'; Badge = @($r.Evidence).Count; Tone = 'neutral'; Note = 'Every tool found, with the file and line it was found on - credentials masked.' }
            @{ Name = 'Unrecognised'; Badge = @($r.Unrecognised).Count; Tone = $(if (@($r.Unrecognised).Count) { 'warn' } else { 'good' }); Note = 'Commands scripts run that no rule knows (add them with -ToolRule or -ToolRulePath), and templates and files that couldn''t be read.' }
            @{ Name = 'Findings'; Badge = @($r.Findings).Count; Tone = $(if ($s.High) { 'bad' } else { 'warn' }); Note = 'What to fix, worst first.' }
        )
        Tables   = @(
            @{ Id = 'projects'; Title = 'Overview'; Section = 'Overview'; Rows = @($r.Projects); Noun = 'projects'; ConsoleLimit = 20
                Columns = @(
                    $orgColumn
                    @{ Key = 'Project'; Label = 'Project'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Pipelines'; Label = 'Pipelines'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Yaml'; Label = 'YAML'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'ClassicBuild'; Label = 'Classic build'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'ClassicRelease'; Label = 'Classic release'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'WithScanning'; Label = 'Scanning'; Type = 'number'; Sum = $true; Console = $true }
                    @{ Key = 'Repositories'; Label = 'Repositories'; Type = 'number'; Sum = $true; Console = $true }
                    @{ Key = 'ServiceConnections'; Label = 'Connections'; Type = 'number'; Sum = $true }
                    @{ Key = 'VariableGroups'; Label = 'Variable groups'; Type = 'number'; Sum = $true }
                    @{ Key = 'Environments'; Label = 'Environments'; Type = 'number'; Sum = $true }
                    @{ Key = 'LastRun'; Label = 'Last run'; Type = 'datetime'; Console = $true; Pdf = $true }
                    @{ Key = 'LastPush'; Label = 'Last push'; Type = 'datetime'; Console = $true; Pdf = $true }
                    $findingsColumn
                    @{ Key = 'Contacts'; Label = 'Contacts'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Administrators'; Label = 'Project administrators'; Type = 'number' }
                    @{ Key = 'Teams'; Label = 'Teams'; Type = 'number' }
                    @{ Key = 'Members'; Label = 'People'; Type = 'number'; Sum = $true }
                    @{ Key = 'Visibility'; Label = 'Visibility'; Facet = $true }
                    $openColumnLink
                ) }
            @{ Id = 'members'; Title = 'People'; Section = 'People'; Rows = @($r.Members); Noun = 'people'; GroupBy = @('Project', 'Kind'); ConsoleLimit = 25
                Empty = 'Nobody read (or -Skip Members).'; EmptyStatus = 'Info'
                Columns = @(
                    $orgColumn
                    @{ Key = 'Project'; Label = 'Project'; Facet = $true; Pdf = $true }
                    @{ Key = 'Name'; Label = 'Name'; Console = $true; Pdf = $true }
                    @{ Key = 'Email'; Label = 'Email or account'; Type = 'mono'; Console = $true; Pdf = $true }
                    @{ Key = 'Roles'; Label = 'Roles'; Console = $true; Pdf = $true }
                    @{ Key = 'Teams'; Label = 'Teams'; Type = 'wide'; Console = $true }
                    @{ Key = 'Kind'; Label = 'Kind'; Facet = $true }
                    @{ Key = 'ProjectAdministrator'; Label = 'Project administrator'; Facet = $true }
                    @{ Key = 'TeamAdmin'; Label = 'Team admin'; Facet = $true }
                ) }
            @{ Id = 'pipelines'; Title = 'Pipelines'; Section = 'Pipelines'; Rows = $pipelines; Noun = 'pipelines'; GroupBy = @('Project', 'Kind', 'LastResult'); ConsoleLimit = 25
                Empty = 'No pipelines.'; EmptyStatus = 'Info'
                Columns = @(
                    $orgColumn
                    @{ Key = 'Project'; Label = 'Project'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Pipeline'; Label = 'Pipeline'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Kind'; Label = 'Kind'; Type = 'badge'; Tones = $kindTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'LastResult'; Label = 'Last run'; Type = 'badge'; Tones = $resultTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'DaysSinceRun'; Label = 'Days ago'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'SuccessRate'; Label = 'Success %'; Type = 'number'; Format = 'N1'; Console = $true; Pdf = $true }
                    @{ Key = 'Runs'; Label = "Runs ($MetricDays d)"; Type = 'number'; Sum = $true }
                    @{ Key = 'RunsPerWeek'; Label = 'Runs a week'; Type = 'number'; Format = 'N1' }
                    @{ Key = 'AvgDurationMin'; Label = 'Avg minutes'; Type = 'number'; Format = 'N1'; Pdf = $true }
                    @{ Key = 'AvgQueueMin'; Label = 'Avg queue minutes'; Type = 'number'; Format = 'N1' }
                    @{ Key = 'DaysSincePush'; Label = 'Last push, days'; Type = 'number' }
                ) + @($toolColumns) + @(
                    @{ Key = 'Tasks'; Label = 'Tasks'; Type = 'number' }
                    @{ Key = 'Connections'; Label = 'Service connections'; Type = 'wide' }
                    @{ Key = 'AzureTargets'; Label = 'Azure targets'; Type = 'wide' }
                    @{ Key = 'Environments'; Label = 'Environments' }
                    @{ Key = 'VariableGroups'; Label = 'Variable groups' }
                    @{ Key = 'Variables'; Label = 'Variables'; Type = 'number' }
                    @{ Key = 'SecretVariables'; Label = 'Secret variables'; Type = 'number'; Sum = $true }
                    @{ Key = 'ExtensionTasks'; Label = 'Marketplace tasks'; Type = 'wide' }
                    @{ Key = 'Pools'; Label = 'Agent pools' }
                    @{ Key = 'YamlFile'; Label = 'YAML file'; Type = 'mono' }
                    @{ Key = 'Yaml'; Label = 'YAML read'; Facet = $true }
                    @{ Key = 'Templates'; Label = 'Templates'; Type = 'wide' }
                    @{ Key = 'Repository'; Label = 'Repository'; Facet = $true }
                    @{ Key = 'RepositoryType'; Label = 'Repository type'; Facet = $true }
                    @{ Key = 'LastRun'; Label = 'Last run at'; Type = 'datetime' }
                    @{ Key = 'LastRunBy'; Label = 'Run by' }
                    @{ Key = 'LastRunBranch'; Label = 'Branch' }
                    @{ Key = 'LastPush'; Label = 'Last push at'; Type = 'datetime' }
                    @{ Key = 'LastPushBy'; Label = 'Pushed by' }
                    @{ Key = 'Images'; Label = 'Hosted images' }
                    @{ Key = 'Containers'; Label = 'Containers' }
                    @{ Key = 'State'; Label = 'State'; Facet = $true }
                    @{ Key = 'Folder'; Label = 'Folder'; Type = 'path' }
                    $findingsColumn
                    $openColumnLink
                ) }
            @{ Id = 'tasks'; Title = 'Tasks and tools'; Section = 'Tasks'; Rows = @($r.Tasks); Noun = 'tasks and tools'; GroupBy = @('Kind', 'Name', 'Pipeline'); ConsoleLimit = 30
                Empty = 'No steps read - no YAML or classic tasks.'; EmptyStatus = 'Info'
                Columns = @(
                    $orgColumn
                    @{ Key = 'Project'; Label = 'Project'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Pipeline'; Label = 'Pipeline'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Kind'; Label = 'Kind'; Type = 'badge'; Tones = @{ Task = 'info'; CLI = 'violet'; Package = 'neutral'; Container = 'warn'; Shell = 'neutral'; Template = 'neutral' }; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Name'; Label = 'Name'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Version'; Label = 'Version'; Type = 'mono'; Console = $true; Pdf = $true }
                    @{ Key = 'Functionality'; Label = 'What it does'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'Category'; Label = 'Category'; Facet = $true }
                    @{ Key = 'Detail'; Label = 'Step'; Type = 'wide' }
                    @{ Key = 'Source'; Label = 'File'; Type = 'path' }
                    @{ Key = 'Enabled'; Label = 'Enabled'; Facet = $true }
                ) }
            @{ Id = 'repositories'; Title = 'Repositories'; Section = 'Repositories'; Rows = @($r.Repositories | Sort-Object -Property Organization, Project, Repository); Noun = 'repositories'; GroupBy = @('Project', 'AdvancedSecurity'); ConsoleLimit = 20
                Empty = 'No Git repositories.'; EmptyStatus = 'Info'
                Columns = @(
                    $orgColumn
                    @{ Key = 'Project'; Label = 'Project'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Repository'; Label = 'Repository'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'DaysSincePush'; Label = 'Last push, days'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'Pipelines'; Label = 'Pipelines'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'Reviewers'; Label = 'Required reviewers'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'BuildValidation'; Label = 'Build validation'; Type = 'badge'; Tones = @{ True = 'good'; False = 'warn' }; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'AdvancedSecurity'; Label = 'Advanced Security'; Type = 'badge'; Tones = @{ On = 'good'; Off = 'warn'; Unknown = 'neutral' }; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'CriticalAlerts'; Label = 'Critical'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'HighAlerts'; Label = 'High'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'MediumAlerts'; Label = 'Medium'; Type = 'number'; Sum = $true }
                    @{ Key = 'LowAlerts'; Label = 'Low'; Type = 'number'; Sum = $true }
                    @{ Key = 'CodeAlerts'; Label = 'Code alerts'; Type = 'number'; Sum = $true }
                    @{ Key = 'DependencyAlerts'; Label = 'Dependency alerts'; Type = 'number'; Sum = $true }
                    @{ Key = 'SecretAlerts'; Label = 'Secret alerts'; Type = 'number'; Sum = $true }
                    @{ Key = 'Policies'; Label = 'Branch policies'; Type = 'wide' }
                    @{ Key = 'Strategy'; Label = 'Branching strategy'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Branches'; Label = 'Branches'; Type = 'number'; Sum = $true }
                    @{ Key = 'StaleBranches'; Label = 'Stale branches'; Type = 'number'; Sum = $true }
                    @{ Key = 'Tags'; Label = 'Tags'; Type = 'number' }
                    @{ Key = 'OpenPullRequests'; Label = 'Open pull requests'; Type = 'number'; Sum = $true }
                    @{ Key = 'Lfs'; Label = 'Git LFS'; Facet = $true }
                    @{ Key = 'PushProtection'; Label = 'Push protection'; Facet = $true }
                    @{ Key = 'AdvsecSettings'; Label = 'Advanced Security settings'; Type = 'wide' }
                    @{ Key = 'LastPush'; Label = 'Last push'; Type = 'datetime' }
                    @{ Key = 'LastPushBy'; Label = 'Pushed by' }
                    @{ Key = 'DefaultBranch'; Label = 'Default branch' }
                    @{ Key = 'SizeMB'; Label = 'Size MB'; Type = 'number'; Format = 'N1' }
                    @{ Key = 'Disabled'; Label = 'Disabled'; Facet = $true }
                    $findingsColumn
                    $openColumnLink
                ) }
            @{ Id = 'connections'; Title = 'Service connections'; Section = 'Service connections'; Rows = @($r.ServiceConnections); Noun = 'service connections'; GroupBy = @('Type', 'Scheme', 'OpenToAllPipelines'); ConsoleLimit = 20
                Empty = 'No service connections (or -Skip Security).'; EmptyStatus = 'Info'
                Columns = @(
                    $orgColumn
                    @{ Key = 'Project'; Label = 'Project'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Connection'; Label = 'Connection'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Type'; Label = 'Type'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Scheme'; Label = 'Signs in with'; Type = 'badge'; Tones = @{ WorkloadIdentityFederation = 'good'; ManagedServiceIdentity = 'good'; ServicePrincipal = 'warn' }; Facet = $true; Console = $true; Pdf = $true }
                    $openColumn
                    @{ Key = 'AuthorizedPipelines'; Label = 'Authorized pipelines'; Type = 'number' }
                    @{ Key = 'UsedBy'; Label = 'Used by'; Type = 'wide'; Console = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription' }
                    @{ Key = 'AzureScope'; Label = 'Scope'; Type = 'path' }
                    @{ Key = 'AzureIdentity'; Label = 'Azure identity' }
                    @{ Key = 'AzureRoles'; Label = 'Azure roles'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Ready'; Label = 'Ready'; Facet = $true }
                    @{ Key = 'CreatedBy'; Label = 'Created by' }
                    $findingsColumn
                    $openColumnLink
                ) }
            @{ Id = 'groups'; Title = 'Variable groups'; Section = 'Variable groups'; Rows = @($r.VariableGroups); Noun = 'variable groups'; GroupBy = @('Type'); ConsoleLimit = 20
                Empty = 'No variable groups (or -Skip Security).'; EmptyStatus = 'Info'
                Columns = @(
                    $orgColumn
                    @{ Key = 'Project'; Label = 'Project'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'VariableGroup'; Label = 'Variable group'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Type'; Label = 'Kept in'; Type = 'badge'; Tones = @{ 'Key Vault' = 'good'; 'Azure DevOps' = 'neutral' }; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Variables'; Label = 'Variables'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'Secrets'; Label = 'Secrets'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'NotMarkedSecret'; Label = 'Secret-looking, not secret'; Type = 'wide'; Console = $true; Pdf = $true }
                    $openColumn
                    @{ Key = 'KeyVault'; Label = 'Key Vault' }
                    @{ Key = 'UsedBy'; Label = 'Used by'; Type = 'wide' }
                    $findingsColumn
                    $openColumnLink
                ) }
            @{ Id = 'environments'; Title = 'Environments'; Section = 'Environments'; Rows = @($r.Environments); Noun = 'environments'; GroupBy = @('Production', 'Approval'); ConsoleLimit = 20
                Empty = 'No environments (or -Skip Security).'; EmptyStatus = 'Info'
                Columns = @(
                    $orgColumn
                    @{ Key = 'Project'; Label = 'Project'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Environment'; Label = 'Environment'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Production'; Label = 'Production'; Facet = $true }
                    @{ Key = 'Approval'; Label = 'Approval'; Type = 'badge'; Tones = @{ True = 'good'; False = 'warn' }; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Checks'; Label = 'Checks'; Type = 'wide'; Console = $true; Pdf = $true }
                    $openColumn
                    @{ Key = 'Deployments'; Label = "Deployments ($MetricDays d)"; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'DeploymentsPerWeek'; Label = 'A week'; Type = 'number'; Format = 'N1'; Console = $true }
                    @{ Key = 'ChangeFailureRate'; Label = 'Change failure %'; Type = 'number'; Format = 'N1'; Console = $true; Pdf = $true }
                    @{ Key = 'Failed'; Label = 'Failed'; Type = 'number'; Sum = $true }
                    @{ Key = 'LastDeployment'; Label = 'Last deployment'; Type = 'datetime' }
                    @{ Key = 'UsedBy'; Label = 'Pipelines'; Type = 'wide' }
                    $findingsColumn
                    $openColumnLink
                ) }
            @{ Id = 'branches'; Title = 'Branches'; Section = 'Branches'; Rows = @($r.Branches | Sort-Object -Property Organization, Project, Repository, @{ Expression = { -not $_.IsDefault } }, Branch); Noun = 'branches'; GroupBy = @('Repository', 'Kind', 'Stale'); ConsoleLimit = 25
                Empty = 'No branches read (or -Skip Branches).'; EmptyStatus = 'Info'
                Columns = @(
                    $orgColumn
                    @{ Key = 'Project'; Label = 'Project'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Repository'; Label = 'Repository'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Branch'; Label = 'Branch'; Type = 'mono'; Console = $true; Pdf = $true }
                    @{ Key = 'Kind'; Label = 'Kind'; Type = 'badge'; Tones = @{ Default = 'good'; Mainline = 'good'; Develop = 'info'; Release = 'violet'; Hotfix = 'warn'; Feature = 'neutral'; Bugfix = 'neutral'; Personal = 'neutral'; Other = 'neutral' }; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'DaysSinceCommit'; Label = 'Last commit, days'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'Ahead'; Label = 'Ahead'; Type = 'number'; Console = $true }
                    @{ Key = 'Behind'; Label = 'Behind'; Type = 'number'; Console = $true }
                    @{ Key = 'Stale'; Label = 'Stale'; Type = 'badge'; Tones = $yesBad; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Policies'; Label = 'Policies'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Author'; Label = 'Last author' }
                    @{ Key = 'LastCommit'; Label = 'Last commit'; Type = 'datetime' }
                ) }
            @{ Id = 'policies'; Title = 'Branch policies'; Section = 'Branch policies'; Rows = @($r.BranchPolicies | Sort-Object -Property Organization, Project, Repository, Branch, Policy); Noun = 'policies'; GroupBy = @('Policy', 'Repository'); ConsoleLimit = 25
                Empty = 'No branch policies (or -Skip Security).'; EmptyStatus = 'Info'
                Columns = @(
                    $orgColumn
                    @{ Key = 'Project'; Label = 'Project'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Repository'; Label = 'Repository'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Branch'; Label = 'Branch'; Type = 'mono'; Console = $true; Pdf = $true }
                    @{ Key = 'Policy'; Label = 'Policy'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Enabled'; Label = 'Enabled'; Type = 'badge'; Tones = @{ True = 'good'; False = 'neutral' }; Facet = $true; Console = $true }
                    @{ Key = 'Blocking'; Label = 'Required'; Type = 'badge'; Tones = @{ True = 'good'; False = 'neutral' }; Facet = $true; Console = $true }
                    @{ Key = 'Settings'; Label = 'Settings'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'GitHub'; Label = 'On GitHub'; Type = 'wide'; Pdf = $true }
                ) }
            @{ Id = 'variables'; Title = 'Variables'; Section = 'Variables'; Rows = @($r.Variables | Sort-Object -Property Organization, Project, Scope, Owner, Variable); Noun = 'variables'; GroupBy = @('Scope', 'Owner', 'Secret'); ConsoleLimit = 25
                Empty = 'No variables.'; EmptyStatus = 'Info'
                Columns = @(
                    $orgColumn
                    @{ Key = 'Project'; Label = 'Project'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Scope'; Label = 'Defined in'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Owner'; Label = 'Pipeline or group'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Variable'; Label = 'Variable'; Type = 'mono'; Console = $true; Pdf = $true }
                    @{ Key = 'Secret'; Label = 'Secret'; Type = 'badge'; Tones = @{ True = 'warn'; False = 'neutral' }; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Settable'; Label = 'Settable at queue time'; Facet = $true }
                    @{ Key = 'GitHub'; Label = 'On GitHub'; Type = 'wide' }
                ) }
            @{ Id = 'dora'; Title = 'DORA'; Section = 'DORA'; Rows = @($r.Dora | Sort-Object -Property Organization, Project); Noun = 'projects'; GroupBy = @('Overall'); ConsoleLimit = 20
                Empty = "No deployments to an environment (or a classic release stage) in $MetricDays days - or -Skip Metrics."; EmptyStatus = 'Info'
                Columns = @(
                    $orgColumn
                    @{ Key = 'Project'; Label = 'Project'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Overall'; Label = 'Overall'; Type = 'badge'; Tones = $doraTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'DeploymentsPerWeek'; Label = 'Deployments a week'; Type = 'number'; Format = 'N1'; Console = $true; Pdf = $true }
                    @{ Key = 'Frequency'; Label = 'Frequency'; Type = 'badge'; Tones = $doraTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'LeadTimeHours'; Label = 'Lead time, h'; Type = 'number'; Format = 'N1'; Console = $true; Pdf = $true }
                    @{ Key = 'LeadTime'; Label = 'Lead time'; Type = 'badge'; Tones = $doraTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'ChangeFailureRate'; Label = 'Change failure %'; Type = 'number'; Format = 'N1'; Console = $true; Pdf = $true }
                    @{ Key = 'ChangeFailure'; Label = 'Change failure'; Type = 'badge'; Tones = $doraTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'TimeToRestoreHours'; Label = 'Time to restore, h'; Type = 'number'; Format = 'N1'; Console = $true; Pdf = $true }
                    @{ Key = 'TimeToRestore'; Label = 'Time to restore'; Type = 'badge'; Tones = $doraTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Deployments'; Label = 'Deployments'; Type = 'number'; Sum = $true }
                    @{ Key = 'Scope'; Label = 'From'; Facet = $true }
                ) }
            @{ Id = 'feeds'; Title = 'Artifacts feeds'; Section = 'Artifacts'; Rows = @($r.Feeds | Sort-Object -Property Organization, Project, Feed); Noun = 'feeds'; GroupBy = @('GitHubPackages'); ConsoleLimit = 20
                Empty = 'No Azure Artifacts feeds (or -Skip Migration).'; EmptyStatus = 'Info'
                Columns = @(
                    $orgColumn
                    @{ Key = 'Project'; Label = 'Project'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Feed'; Label = 'Feed'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Packages'; Label = 'Packages'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Protocols'; Label = 'By type'; Console = $true; Pdf = $true }
                    @{ Key = 'GitHubPackages'; Label = 'GitHub Packages'; Type = 'badge'; Tones = @{ Supported = 'good'; 'Nothing to move' = 'neutral'; 'Not read' = 'neutral' }; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Upstreams'; Label = 'Upstream sources'; Type = 'wide' }
                    $openColumnLink
                ) }
            @{ Id = 'testplans'; Title = 'Test plans'; Section = 'Test plans'; Rows = @($r.TestPlans | Sort-Object -Property Organization, Project, TestPlan); Noun = 'test plans'; GroupBy = @('Project', 'State'); ConsoleLimit = 20
                Empty = 'No test plans (or -Skip Migration).'; EmptyStatus = 'Success'
                Columns = @(
                    $orgColumn
                    @{ Key = 'Project'; Label = 'Project'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'TestPlan'; Label = 'Test plan'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'State'; Label = 'State'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Owner'; Label = 'Owner'; Console = $true; Pdf = $true }
                    @{ Key = 'AreaPath'; Label = 'Area'; Type = 'path' }
                    @{ Key = 'Iteration'; Label = 'Iteration'; Type = 'path' }
                    @{ Key = 'Updated'; Label = 'Updated'; Type = 'datetime'; Console = $true }
                    $openColumnLink
                ) }
            @{ Id = 'pools'; Title = 'Agent pools'; Section = 'Agents and extensions'; Rows = @($r.AgentPools | Sort-Object -Property Organization, Hosted, Pool); Noun = 'agent pools'; GroupBy = @('Hosted'); ConsoleLimit = 20
                Empty = 'No agent pools read (or -Skip Migration).'; EmptyStatus = 'Info'
                Columns = @(
                    $orgColumn
                    @{ Key = 'Pool'; Label = 'Pool'; Console = $true; Pdf = $true }
                    @{ Key = 'Hosted'; Label = 'Microsoft-hosted'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Agents'; Label = 'Agents'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Online'; Label = 'Online'; Type = 'number'; Sum = $true; Console = $true }
                    @{ Key = 'Pipelines'; Label = 'Pipelines'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'GitHub'; Label = 'On GitHub'; Type = 'wide' }
                ) }
            @{ Id = 'extensions'; Title = 'Marketplace extensions'; Section = 'Agents and extensions'; Rows = @($r.Extensions); Noun = 'extensions'; ConsoleLimit = 20
                Empty = 'No marketplace extensions installed (or -Skip Migration).'; EmptyStatus = 'Info'
                Columns = @(
                    $orgColumn
                    @{ Key = 'Extension'; Label = 'Extension'; Console = $true; Pdf = $true }
                    @{ Key = 'Publisher'; Label = 'Publisher'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Version'; Label = 'Version'; Type = 'mono' }
                    @{ Key = 'Pipelines'; Label = 'Pipelines'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'UsedBy'; Label = 'Used by'; Type = 'wide'; Console = $true }
                    @{ Key = 'Disabled'; Label = 'Disabled'; Facet = $true }
                    @{ Key = 'GitHub'; Label = 'On GitHub'; Type = 'wide' }
                ) }
            @{ Id = 'migration'; Title = 'Migration to GitHub'; Section = 'Migration'; Rows = @($r.Migration | Sort-Object -Property @{ Expression = { $_.Effort }; Descending = $true }, Project); Noun = 'projects'; GroupBy = @('Complexity'); ConsoleLimit = 20
                Columns = @(
                    $orgColumn
                    @{ Key = 'Project'; Label = 'Project'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Complexity'; Label = 'Complexity'; Type = 'badge'; Tones = $complexityTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Effort'; Label = 'Effort points'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Repositories'; Label = 'Repositories'; Type = 'number'; Sum = $true; Console = $true }
                    @{ Key = 'RepositoriesMB'; Label = 'MB'; Type = 'number'; Format = 'N1'; Sum = $true }
                    @{ Key = 'YamlPipelines'; Label = 'YAML'; Type = 'number'; Sum = $true; Console = $true }
                    @{ Key = 'ClassicPipelines'; Label = 'Classic'; Type = 'number'; Sum = $true; Console = $true }
                    @{ Key = 'MarketplaceTasks'; Label = 'Marketplace tasks'; Type = 'number'; Sum = $true }
                    @{ Key = 'SecretVariables'; Label = 'Secrets'; Type = 'number'; Sum = $true; Console = $true }
                    @{ Key = 'Variables'; Label = 'Variables'; Type = 'number'; Sum = $true }
                    @{ Key = 'ServiceConnections'; Label = 'Connections'; Type = 'number'; Sum = $true }
                    @{ Key = 'Environments'; Label = 'Environments'; Type = 'number'; Sum = $true }
                    @{ Key = 'Feeds'; Label = 'Feeds'; Type = 'number'; Sum = $true }
                    @{ Key = 'Packages'; Label = 'Packages'; Type = 'number'; Sum = $true }
                    @{ Key = 'TestPlans'; Label = 'Test plans'; Type = 'number'; Sum = $true }
                    @{ Key = 'Wikis'; Label = 'Wikis'; Type = 'number' }
                    @{ Key = 'ServiceHooks'; Label = 'Service hooks'; Type = 'number' }
                    @{ Key = 'OpenPullRequests'; Label = 'Open pull requests'; Type = 'number'; Sum = $true }
                    @{ Key = 'LfsRepositories'; Label = 'LFS repositories'; Type = 'number' }
                    @{ Key = 'AdvancedSecurity'; Label = 'Advanced Security defaults'; Type = 'wide' }
                    @{ Key = 'Notes'; Label = 'What needs work'; Type = 'wide'; Pdf = $true }
                ) }
            @{ Id = 'migrationmap'; Title = 'Where everything goes'; Section = 'Migration'; Rows = @($r.MigrationMap | Group-Object -Property AzureDevOps | ForEach-Object { $first = $_.Group[0]; [pscustomobject][ordered]@{ PSTypeName = 'AAC.DevOpsMigrationMap'; Organization = (@($_.Group | ForEach-Object { $_.Organization }) | Select-Object -Unique) -join ', '; AzureDevOps = $_.Name; Count = $(if ($null -eq $first.Count) { $null } else { (@($_.Group | ForEach-Object { [int]$_.Count }) | Measure-Object -Sum).Sum }); GitHub = $first.GitHub; HowToMove = $first.HowToMove; Note = $first.Note } }); Noun = 'kinds'; ConsoleLimit = 20
                Columns = @(
                    @{ Key = 'AzureDevOps'; Label = 'Azure DevOps'; Console = $true; Pdf = $true }
                    @{ Key = 'Count'; Label = 'Count'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'GitHub'; Label = 'GitHub'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'HowToMove'; Label = 'How to move'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'Note'; Label = 'Note'; Type = 'wide' }
                ) }
            @{ Id = 'tools'; Title = 'Tools'; Section = 'Tools'; Rows = @($r.Tools); Noun = 'tools'; GroupBy = @('Category'); ConsoleLimit = 30
                Empty = 'No tools found - no steps were read.'; EmptyStatus = 'Info'
                Columns = @(
                    $orgColumn
                    @{ Key = 'Category'; Label = 'Category'; Type = 'badge'; Tones = $categoryTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Tool'; Label = 'Tool'; Console = $true; Pdf = $true }
                    @{ Key = 'Pipelines'; Label = 'Pipelines'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'Projects'; Label = 'Projects'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'Versions'; Label = 'Versions seen'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'Found'; Label = 'Found in'; Type = 'wide'; Console = $true }
                    @{ Key = 'Purpose'; Label = 'What it does'; Type = 'wide' }
                    @{ Key = 'Evidence'; Label = 'Evidence'; Type = 'number' }
                    @{ Key = 'ProjectNames'; Label = 'In'; Type = 'wide' }
                ) }
            @{ Id = 'coverage'; Title = 'Coverage'; Section = 'Coverage'; Rows = @($r.Coverage | Sort-Object -Property Organization, Project, Pipeline); Noun = 'pipelines'; GroupBy = @('Project', 'Security', 'Test', 'Lint'); ConsoleLimit = 25
                Empty = 'No build pipelines.'; EmptyStatus = 'Info'
                Columns = @(
                    $orgColumn
                    @{ Key = 'Project'; Label = 'Project'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Pipeline'; Label = 'Pipeline'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Kind'; Label = 'Kind'; Facet = $true }
                ) + @(foreach ($c in 'Lint', 'Build', 'Test', 'Security', 'Deploy', 'Publish', 'GitOps') { @{ Key = $c; Label = $c; Type = 'badge'; Tones = @{ Yes = 'good'; No = $(if ($c -in 'Security', 'Test', 'Lint') { 'bad' } else { 'neutral' }); 'Not read' = 'neutral' }; Facet = $true; Console = $true; Pdf = $true } }) + @(
                    @{ Key = 'Tools'; Label = 'Tools'; Type = 'number' }
                ) }
            @{ Id = 'evidence'; Title = 'Evidence'; Section = 'Evidence'; Rows = @($r.Evidence); Noun = 'matches'; GroupBy = @('Tool', 'Found', 'Pipeline'); ConsoleLimit = 30
                Empty = 'No tools found - no steps were read.'; EmptyStatus = 'Info'
                Columns = @(
                    $orgColumn
                    @{ Key = 'Project'; Label = 'Project'; Facet = $true }
                    @{ Key = 'Pipeline'; Label = 'Pipeline'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Tool'; Label = 'Tool'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Category'; Label = 'Category'; Type = 'badge'; Tones = $categoryTones; Facet = $true }
                    @{ Key = 'Version'; Label = 'Version'; Type = 'mono'; Console = $true; Pdf = $true }
                    @{ Key = 'Found'; Label = 'Found'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'File'; Label = 'File'; Type = 'path'; Console = $true; Pdf = $true }
                    @{ Key = 'Line'; Label = 'Line'; Type = 'number'; Console = $true }
                    @{ Key = 'Evidence'; Label = 'Line text'; Type = 'mono'; Pdf = $true }
                    @{ Key = 'Matches'; Label = 'Matches'; Type = 'number' }
                ) }
            @{ Id = 'unrecognised'; Title = 'Unrecognised'; Section = 'Unrecognised'; Rows = @($r.Unrecognised); Noun = 'items'; GroupBy = @('Kind'); ConsoleLimit = 30
                Empty = 'Every command is known, and every file was read.'; EmptyStatus = 'Success'
                Columns = @(
                    $orgColumn
                    @{ Key = 'Kind'; Label = 'Kind'; Type = 'badge'; Tones = @{ Command = 'warn' }; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Name'; Label = 'Command or file'; Type = 'mono'; Console = $true; Pdf = $true }
                    @{ Key = 'Pipelines'; Label = 'Pipelines'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'Lines'; Label = 'Lines'; Type = 'number'; Console = $true }
                    @{ Key = 'Example'; Label = 'Example'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide' }
                ) }
            @{ Id = 'findings'; Title = 'Findings'; Section = 'Findings'; Rows = @($r.Findings); Noun = 'findings'; GroupBy = @('Finding', 'Severity', 'Area', 'Project'); ConsoleLimit = 25
                Empty = 'Nothing to fix.'; EmptyStatus = 'Success'
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                    $orgColumn
                    @{ Key = 'Project'; Label = 'Project'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Area'; Label = 'Area'; Facet = $true }
                    @{ Key = 'Item'; Label = 'Item'; Console = $true; Pdf = $true }
                    @{ Key = 'Finding'; Label = 'Finding'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Recommendation'; Label = 'What to do'; Type = 'wide'; Pdf = $true }
                ) }
        )
        Hint     = '-View Tool, Evidence, Coverage, Unrecognised, Task, Branch, Dora, Migration or Finding returns those rows; -ToolRulePath adds tools of your own; -Skip Security, Metrics is faster; -YamlPath saves the YAML; -IncludeAzure adds Azure roles; -HtmlPath, -PdfPath or -CsvPath for a report.'
    }
    $rows = @(switch ($View) {
            'Project' { $r.Projects }
            'Repository' { $r.Repositories }
            'Task' { $r.Tasks }
            'Tool' { $r.Tools }
            'Evidence' { $r.Evidence }
            'Coverage' { $r.Coverage }
            'Unrecognised' { $r.Unrecognised }
            'ServiceConnection' { $r.ServiceConnections }
            'VariableGroup' { $r.VariableGroups }
            'Environment' { $r.Environments }
            'Member' { $r.Members }
            'Branch' { $r.Branches }
            'BranchPolicy' { $r.BranchPolicies }
            'Variable' { $r.Variables }
            'Dora' { $r.Dora }
            'Feed' { $r.Feeds }
            'TestPlan' { $r.TestPlans }
            'AgentPool' { $r.AgentPools }
            'Extension' { $r.Extensions }
            'Migration' { $r.Migration }
            'MigrationMap' { $r.MigrationMap }
            'Finding' { $r.Findings }
            default { $pipelines }
        })
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $rows -Noun $View.ToLowerInvariant() -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $rows -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
