function Read-AACDevOpsInventory {
    <#
    .SYNOPSIS
        Reads what Get-AACADOInventory needs from one Azure DevOps
        organization - projects, pipelines and their last run, classic
        releases, repositories and their last push, every YAML file and the
        templates it includes, the task catalogue, the security resources
        (service connections, variable groups, environments, branch
        policies), run history and GitHub Advanced Security - many requests
        at once.
    .DESCRIPTION
        GET requests only (REST API 7.1), through Invoke-AACArmParallel with
        -Authorization, in rounds:
          0. the organization's task catalogue (names, descriptions and
             versions of every built-in and installed task - and the IDs
             classic pipelines refer to them by)
          1. the projects
          2. per project: build definitions (all properties, the latest
             build), classic releases, Git repositories; with Security:
             service connections, variable groups, environments, branch
             policies; with Metrics: the runs of the last -MetricDays
          3. per repository its last push (and, with AdvancedSecurity, its
             enablement); per YAML pipeline in Azure Repos its file; with
             Security: who may use each service connection, variable group
             and environment, each environment's checks; with Metrics: each
             environment's deployments
          4. with AdvancedSecurity: the active alerts of each enabled
             repository
          5. the templates the files include - local ones, and those of
             other Azure Repos repositories through the pipeline's
             resources (template.yml@alias) - nested up to -TemplateDepth
          6. what the pipelines run that isn't in the YAML, from the
             pipeline's own repository (two levels: a script a script
             calls): script files (filePath / scriptPath inputs, ./x.sh,
             pwsh -File x.ps1...), package.json where npm/yarn/pnpm run a
             script, the Makefile where make runs a target - at most
             -MaxScriptFiles a pipeline; a path built from a variable can't
             be followed and is reported
        -Skip leaves out Yaml, Security, Metrics or AdvancedSecurity. A
        request that fails is kept with its error and the rest carry on.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $OrganizationUrl,

        [Parameter(Mandatory)]
        [string] $Authorization,

        [string[]] $Project,

        [int[]] $PipelineId,

        [ValidateSet('Yaml', 'Security', 'Metrics', 'AdvancedSecurity')]
        [string[]] $Skip = @(),

        [ValidateRange(1, 365)]
        [int] $MetricDays = 30,

        [ValidateRange(0, 10)]
        [int] $TemplateDepth = 3,

        [ValidateRange(0, 200)]
        [int] $MaxScriptFiles = 25,

        [ValidateRange(1, 32)]
        [int] $ThrottleLimit = 8,

        # Called with (stage text) as each round starts.
        [scriptblock] $OnStage,

        # Called as requests finish, with (step number, text, done, total):
        # the text names the stage, the project whose request just finished,
        # how many projects of the stage are done and the time left.
        [scriptblock] $OnProgress
    )

    $api = 'api-version=7.1'
    $org = $OrganizationUrl.TrimEnd('/')
    $orgName = if ($org -match '^https://dev\.azure\.com/([^/]+)') { $Matches[1] } else { [regex]::Match($org, '^https://([^.]+)\.').Groups[1].Value }
    # Classic releases live on vsrm.dev.azure.com (or <org>.vsrm.visualstudio.com); Advanced Security on advsec.dev.azure.com.
    $releaseHost = if ($org -match '^https://dev\.azure\.com/') { $org -replace '^https://dev\.azure\.com/', 'https://vsrm.dev.azure.com/' } else { $org -replace '^https://([^.]+)\.visualstudio\.com', 'https://$1.vsrm.visualstudio.com' }
    $advsecHost = "https://advsec.dev.azure.com/$orgName"
    $want = @{ Yaml = $Skip -notcontains 'Yaml'; Security = $Skip -notcontains 'Security'; Metrics = $Skip -notcontains 'Metrics'; AdvancedSecurity = $Skip -notcontains 'AdvancedSecurity' }
    # Progress: the scriptblock below runs inside Invoke-AACArmParallel, whose
    # own variables ($done, $total, $job...) would hide ours - so every name it
    # uses is prefixed 'progress'.
    $progressState = @{ Step = 0; Text = ''; Names = @{} }
    $progressCallback = $OnProgress
    $progressProject = {
        # The project a request is for: the path segment before /_apis/ - an ID, or a (template's) project name.
        param([string] $Target)
        $progressSegment = [System.Uri]::UnescapeDataString([regex]::Match($Target, '/([^/]+)/_apis/').Groups[1].Value)
        if ($progressState.Names.ContainsKey($progressSegment)) { $progressState.Names[$progressSegment] } else { '' }
    }
    $progressLeft = {
        param([timespan] $Elapsed, [double] $Fraction)
        if ($Fraction -lt 0.05 -or $Elapsed.TotalSeconds -lt 3) { return 'estimating' }
        $progressSeconds = $Elapsed.TotalSeconds / $Fraction - $Elapsed.TotalSeconds
        if ($progressSeconds -lt 60) { '< 1 min left' } elseif ($progressSeconds -lt 5400) { '~{0:N0} min left' -f [Math]::Ceiling($progressSeconds / 60) } else { '~{0:N1} h left' -f ($progressSeconds / 3600) }
    }
    $run = {
        param([System.Collections.IDictionary] $Uris)
        if (-not $Uris.Count) { return @{} }
        # How many requests each project has in this round, so a project is 'done' when its last one is.
        $progressRound = @{ Started = [datetime]::UtcNow; Left = @{}; Projects = 0; Finished = 0 }
        foreach ($progressUri in $Uris.Values) { $progressName = & $progressProject $progressUri; if ($progressName) { $progressRound.Left[$progressName] = 1 + [int]$progressRound.Left[$progressName] } }
        $progressRound.Projects = $progressRound.Left.Count
        if ($progressCallback) { & $progressCallback $progressState.Step "$($progressState.Text) - estimating" 0 $Uris.Count }
        Invoke-AACArmParallel -Uri @($Uris.Values) -ThrottleLimit $ThrottleLimit -Authorization $Authorization -OnProgress {
            param($ProgressDone, $ProgressTotal, $ProgressKey)
            if (-not $progressCallback) { return }
            $progressName = if ($ProgressKey) { & $progressProject ([string]$ProgressKey) } else { '' }
            if ($progressName -and $progressRound.Left[$progressName] -gt 0) {
                $progressRound.Left[$progressName]--
                if (-not $progressRound.Left[$progressName]) { $progressRound.Finished++ }
            }
            # The time left first and the project last: a narrow console cuts the line from the end.
            $progressParts = @($progressState.Text)
            if ($progressRound.Projects -gt 1) { $progressParts += '{0:N0}/{1:N0} projects' -f $progressRound.Finished, $progressRound.Projects }
            $progressParts += & $progressLeft ([datetime]::UtcNow - $progressRound.Started) ($ProgressDone / [Math]::Max(1, $ProgressTotal))
            if ($progressName) { $progressParts += $progressName }
            & $progressCallback $progressState.Step ($progressParts -join ' - ') $ProgressDone $ProgressTotal
        }
    }
    $itemsOf = { param($Answer) @(if ($Answer -and -not $Answer['Error']) { $Answer['Items'] | Where-Object { $_ } }) }
    $stage = { param([string] $Text) $progressState.Step++; $progressState.Text = $Text; if ($OnStage) { & $OnStage $Text } }
    $enc = { param([string] $Text) [System.Uri]::EscapeDataString($Text) }
    $versionOf = { param([string] $Ref) if (-not $Ref) { '' } elseif ($Ref -match '^refs/tags/(.+)$') { "&versionDescriptor.version=$(& $enc $Matches[1])&versionDescriptor.versionType=tag" } else { "&versionDescriptor.version=$(& $enc ($Ref -replace '^refs/heads/', ''))&versionDescriptor.versionType=branch" } }

    # 0 and 1. The task catalogue, and the projects.
    & $stage 'Projects and task catalogue'
    $first = [ordered]@{ projects = "$org/_apis/projects?$api"; tasks = "$org/_apis/distributedtask/tasks?$api" }
    $answers = & $run $first
    $answer = $answers[$first.projects]
    if (-not $answer -or $answer['Error']) {
        throw "Azure Admin Console couldn't read the projects of $org - $(if ($answer) { $answer['Error'] } else { 'no answer' }). Check the organization's name, and that the token can read projects (Project and Team: Read)."
    }
    $tasks = @(& $itemsOf $answers[$first.tasks])
    $projects = @(& $itemsOf $answer)
    $wanted = @($Project | Where-Object { $_ })
    if ($wanted.Count) {
        foreach ($name in $wanted) {
            if (-not @($projects | Where-Object { [string]$_['name'] -ieq $name -or [string]$_['id'] -ieq $name }).Count) {
                throw "Azure Admin Console found no project '$name' in $org. Projects it can see: $((@($projects | ForEach-Object { [string]$_['name'] } | Sort-Object) | Select-Object -First 20) -join ', ')."
            }
        }
        $projects = @($projects | Where-Object { $p = $_; @($wanted | Where-Object { [string]$p['name'] -ieq $_ -or [string]$p['id'] -ieq $_ }).Count })
    }
    foreach ($p in $projects) { $progressState.Names[[string]$p['id']] = [string]$p['name']; $progressState.Names[[string]$p['name']] = [string]$p['name'] }

    # 2. Per project.
    & $stage "Pipelines, repositories$(if ($want.Security) { ', security' })$(if ($want.Metrics) { ', runs' })"
    $since = [datetime]::UtcNow.AddDays(-$MetricDays).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $parts = [ordered]@{ definitions = "_apis/build/definitions?includeAllProperties=true&includeLatestBuilds=true&$api"; repositories = "_apis/git/repositories?$api" }
    if ($want.Security) { $parts.endpoints = "_apis/serviceendpoint/endpoints?includeFailed=true&api-version=7.1-preview.4"; $parts.groups = "_apis/distributedtask/variablegroups?api-version=7.1-preview.2"; $parts.environments = "_apis/distributedtask/environments?api-version=7.1-preview.1"; $parts.policies = "_apis/policy/configurations?$api" }
    if ($want.Metrics) { $parts.builds = "_apis/build/builds?minTime=$since&queryOrder=queueTimeDescending&$api" }
    $second = [ordered]@{}
    foreach ($p in $projects) {
        $id = [string]$p['id']
        foreach ($part in $parts.Keys) { $second["$id|$part"] = "$org/$id/$($parts[$part])" }
        if (-not $PipelineId) { $second["$id|releases"] = "$releaseHost/$id/_apis/release/definitions?`$expand=lastRelease&$api" }
    }
    $answers = & $run $second
    $byProject = @{}
    foreach ($name in @($parts.Keys) + 'releases') { $byProject[$name] = @{} }
    foreach ($key in $second.Keys) {
        $id, $what = $key -split '\|', 2
        $byProject[$what][$id] = $answers[$second[$key]]
    }
    if ($PipelineId) {
        foreach ($id in @($byProject.definitions.Keys)) {
            $d = $byProject.definitions[$id]
            # A filtered copy - never the answer itself.
            if ($d -and -not $d['Error']) { $byProject.definitions[$id] = @{ Status = $d['Status']; Body = $d['Body']; Error = ''; Items = [System.Collections.Generic.List[object]]@(& $itemsOf $d | Where-Object { $PipelineId -contains [int]$_['id'] }) } }
        }
    }

    # 3. Pushes, YAML files, permissions, checks, deployments, Advanced Security enablement.
    & $stage 'Pushes, YAML, permissions, checks'
    $third = [ordered]@{}
    $yaml = @{}
    foreach ($p in $projects) {
        $id = [string]$p['id']
        $disabled = @{}
        foreach ($r in (& $itemsOf $byProject.repositories[$id])) {
            if ([string]$r['isDisabled'] -eq 'True') { $disabled[[string]$r['id']] = $true; continue }
            $third["push|$($r['id'])"] = "$org/$id/_apis/git/repositories/$($r['id'])/pushes?`$top=1&$api"
            if ($want.AdvancedSecurity) { $third["advsec|$id|$($r['id'])"] = "$advsecHost/$id/_apis/management/repositories/$($r['id'])/enablement?api-version=7.2-preview.1" }
        }
        foreach ($d in (& $itemsOf $byProject.definitions[$id])) {
            if ([int](Get-AACMember -InputObject $d -Path 'process.type') -ne 2) { continue }
            $file = [string](Get-AACMember -InputObject $d -Path 'process.yamlFilename')
            $repoType = [string](Get-AACMember -InputObject $d -Path 'repository.type')
            $repoId = [string](Get-AACMember -InputObject $d -Path 'repository.id')
            $branch = [string](Get-AACMember -InputObject $d -Path 'repository.defaultBranch')
            $entry = @{ Path = $file; Branch = ($branch -replace '^refs/heads/', ''); Ref = $branch; RepositoryId = $repoId; RepositoryName = [string](Get-AACMember -InputObject $d -Path 'repository.name'); ProjectId = $id; Content = ''; Error = ''; Templates = [System.Collections.Generic.List[string]]::new() }
            $yaml["$id|$($d['id'])"] = $entry
            if (-not $want.Yaml) { $entry.Error = 'Not read (-Skip Yaml).'; continue }
            # A disabled repository can't be read (and its pipelines can't run): no request for it.
            if ($disabled.ContainsKey($repoId)) { $entry.Error = 'The repository is disabled - not read.'; continue }
            if ($repoType -ne 'TfsGit') { $entry.Error = "The YAML is in a $(if ($repoType) { $repoType } else { 'non-Azure Repos' }) repository - not read."; continue }
            $third["yaml|$id|$($d['id'])"] = "$org/$id/_apis/git/repositories/$repoId/items?path=$(& $enc $file)$(& $versionOf $branch)&includeContent=true&`$format=json&$api"
        }
        if ($want.Security) {
            foreach ($e in (& $itemsOf $byProject.endpoints[$id])) { $third["perm|$id|endpoint|$($e['id'])"] = "$org/$id/_apis/pipelines/pipelinePermissions/endpoint/$($e['id'])?api-version=7.1-preview.1" }
            foreach ($g in (& $itemsOf $byProject.groups[$id])) { $third["perm|$id|variablegroup|$($g['id'])"] = "$org/$id/_apis/pipelines/pipelinePermissions/variablegroup/$($g['id'])?api-version=7.1-preview.1" }
            foreach ($env in (& $itemsOf $byProject.environments[$id])) {
                $third["perm|$id|environment|$($env['id'])"] = "$org/$id/_apis/pipelines/pipelinePermissions/environment/$($env['id'])?api-version=7.1-preview.1"
                $third["checks|$id|$($env['id'])"] = "$org/$id/_apis/pipelines/checks/configurations?resourceType=environment&resourceId=$($env['id'])&`$expand=settings&api-version=7.1-preview.1"
                if ($want.Metrics) { $third["deploy|$id|$($env['id'])"] = "$org/$id/_apis/distributedtask/environments/$($env['id'])/environmentdeploymentrecords?top=500&api-version=7.1-preview.1" }
            }
        }
    }
    $answers = & $run $third
    $pushes = @{}; $permissions = @{}; $checks = @{}; $deployments = @{}; $advancedSecurity = @{}
    foreach ($key in $third.Keys) {
        $kind, $rest = $key -split '\|', 2
        $a = $answers[$third[$key]]
        switch ($kind) {
            'push' { $pushes[$rest] = $a }
            'perm' { $permissions[$rest] = $a }
            'checks' { $checks[$rest] = $a }
            'deploy' { $deployments[$rest] = $a }
            'advsec' { $advancedSecurity[$rest] = @{ Enablement = $a; Alerts = $null } }
            'yaml' {
                $entry = $yaml[$rest]
                if (-not $a -or $a['Error']) { $entry.Error = "The YAML couldn't be read: $(if ($a) { $a['Error'] } else { 'no answer' })" }
                else { $entry.Content = [string](Get-AACMember -InputObject $a['Body'] -Path 'content') }
            }
        }
    }

    # 4. Active Advanced Security alerts of the repositories that have it on.
    $fourth = [ordered]@{}
    foreach ($key in $advancedSecurity.Keys) {
        $e = $advancedSecurity[$key].Enablement
        if ($e -and -not $e['Error'] -and [string](Get-AACMember -InputObject $e['Body'] -Path 'advSecEnabled') -eq 'True') {
            $projectId, $repoId = $key -split '\|', 2
            $fourth[$key] = "$advsecHost/$projectId/_apis/alert/repositories/$repoId/alerts?criteria.states=active&top=1000&api-version=7.2-preview.1"
        }
    }
    if ($fourth.Count) {
        & $stage "Advanced Security alerts ($($fourth.Count) repositories)"
        $answers = & $run $fourth
        foreach ($key in $fourth.Keys) { $advancedSecurity[$key].Alerts = $answers[$fourth[$key]] }
    }

    # 5. Templates: local, and from other Azure Repos repositories through resources, nested up to -TemplateDepth.
    $templateContent = @{}
    $templateIncludes = @{}
    $pending = [System.Collections.Generic.List[hashtable]]::new()
    $resolveRef = {
        # A template reference -> where its file is: project, repository, ref, path - or why it can't be read.
        param([hashtable] $From, [hashtable] $Template, [object[]] $Repositories)
        if ($Template.Alias) {
            if ($Template.Alias -eq 'self') { return @{ Project = $From.Project; Repository = $From.Repository; Ref = $From.Ref; Path = '/' + $Template.Path.TrimStart('/') } }
            $res = @($Repositories | Where-Object { $_.Alias -eq $Template.Alias }) | Select-Object -First 1
            if (-not $res) { return @{ Error = "No repository resource '$($Template.Alias)'." } }
            if ($res.Type -and $res.Type -ne 'git') { return @{ Error = "Template repository '$($res.Name)' is $($res.Type) - not read." } }
            $projectName, $repoName = if ($res.Name.Contains('/')) { $res.Name -split '/', 2 } else { $From.Project, $res.Name }
            return @{ Project = $projectName; Repository = $repoName; Ref = $res.Ref; Path = '/' + $Template.Path.TrimStart('/') }
        }
        # Local: relative to the including file, or the repository root with a leading /.
        $folder = if ($From.Path.Contains('/')) { $From.Path.Substring(0, $From.Path.LastIndexOf('/')) } else { '' }
        $raw = if ($Template.Path.StartsWith('/')) { $Template.Path.TrimStart('/') } else { (@($folder.TrimStart('/'), $Template.Path) | Where-Object { $_ }) -join '/' }
        $segments = [System.Collections.Generic.List[string]]::new()
        foreach ($segment in ($raw -split '/')) { if ($segment -eq '..') { if ($segments.Count) { $segments.RemoveAt($segments.Count - 1) } } elseif ($segment -and $segment -ne '.') { $segments.Add($segment) } }
        @{ Project = $From.Project; Repository = $From.Repository; Ref = $From.Ref; Path = '/' + ($segments -join '/') }
    }
    foreach ($key in @($yaml.Keys)) {
        $entry = $yaml[$key]
        if (-not $entry.Content) { continue }
        $parsed = ConvertFrom-AACPipelineYaml -Text $entry.Content
        $entry.Resources = $parsed.Repositories
        $from = @{ Project = $entry.ProjectId; Repository = $entry.RepositoryId; Ref = $entry.Ref; Path = '/' + $entry.Path.TrimStart('/') }
        foreach ($t in $parsed.Templates) { $pending.Add(@{ Entry = $entry; From = $from; Template = $t; Depth = 1 }) }
    }
    $depth = 1
    while ($pending.Count -and $depth -le $TemplateDepth) {
        $round = [ordered]@{}
        $waiting = [System.Collections.Generic.List[hashtable]]::new()
        foreach ($item in $pending) {
            $where = & $resolveRef $item.From $item.Template @($item.Entry['Resources'])
            $label = if ($item.Template.Alias) { "$($item.Template.Path)@$($item.Template.Alias)" } else { $item.Template.Path }
            if ($where.Contains('Error')) {
                $tkey = "unreadable|$label"
                $templateContent[$tkey] = @{ Content = ''; Error = $where.Error; Label = $label; Depth = $item.Depth }
                if (-not $item.Entry.Templates.Contains($tkey)) { $item.Entry.Templates.Add($tkey) }
                continue
            }
            # A template nested in another repository's template is named with that repository.
            if (-not $item.Template.Alias -and $where.Repository -ne $item.Entry.RepositoryId) { $label = "$($where.Path.TrimStart('/'))@$($where.Repository)" }
            $tkey = "$($where.Project)|$($where.Repository)|$($where.Ref)|$($where.Path)"
            if (-not $item.Entry.Templates.Contains($tkey)) { $item.Entry.Templates.Add($tkey) }
            $item.Where = $where; $item.Key = $tkey; $item.Label = $label
            $waiting.Add($item)
            if (-not $templateContent.ContainsKey($tkey) -and -not $round.Contains($tkey)) {
                $round[$tkey] = "$org/$(& $enc $where.Project)/_apis/git/repositories/$(& $enc $where.Repository)/items?path=$(& $enc $where.Path)$(& $versionOf $where.Ref)&includeContent=true&`$format=json&$api"
            }
        }
        if ($round.Count) { & $stage "Templates, level $depth ($($round.Count))" }
        $answers = & $run $round
        foreach ($tkey in $round.Keys) {
            $a = $answers[$round[$tkey]]
            $templateContent[$tkey] = if (-not $a -or $a['Error']) { @{ Content = ''; Error = $(if ($a) { [string]$a['Error'] } else { 'no answer' }); Label = ''; Depth = $depth } } else { @{ Content = [string](Get-AACMember -InputObject $a['Body'] -Path 'content'); Error = ''; Label = ''; Depth = $depth } }
        }
        # The templates these templates include - the pipeline's resources still resolve their aliases.
        $next = [System.Collections.Generic.List[hashtable]]::new()
        foreach ($item in $waiting) {
            $tc = $templateContent[$item.Key]
            if (-not $tc.Label) { $tc.Label = $item.Label }
            if (-not $tc.Content -or $item.Depth -ge $TemplateDepth) { continue }
            $from = @{ Project = $item.Where.Project; Repository = $item.Where.Repository; Ref = $item.Where.Ref; Path = $item.Where.Path }
            # A template many pipelines include is parsed once.
            if (-not $templateIncludes.ContainsKey($item.Key)) { $templateIncludes[$item.Key] = @((ConvertFrom-AACPipelineYaml -Text $tc.Content).Templates) }
            foreach ($t in $templateIncludes[$item.Key]) {
                # A template in another repository includes its own local templates from that repository.
                $next.Add(@{ Entry = $item.Entry; From = $from; Template = $t; Depth = $item.Depth + 1 })
            }
        }
        $pending = $next
        $depth++
    }

    # 6. Script files, package.json and Makefiles the pipelines run - from each pipeline's own repository.
    $scriptContent = @{}
    $refCache = @{}
    $variablePrefix = '^\$\((Build\.SourcesDirectory|System\.DefaultWorkingDirectory|Build\.Repository\.LocalPath)\)[/\\]|^\$\(Pipeline\.Workspace\)[/\\]s[/\\]'
    $normalise = {
        # A repository path from what a step wrote - or '' when a variable makes it unknowable.
        param([string] $Path, [string] $Folder)
        $clean = ($Path.Trim().Trim('"', "'") -replace $variablePrefix, '').Replace('\', '/')
        if (-not $clean -or $clean -match '\$[\({]|%\w+%') { return '' }
        $raw = if ($clean.StartsWith('/')) { $clean } else { (@($Folder.Trim('/'), ($clean -replace '^\./', '')) | Where-Object { $_ }) -join '/' }
        $segments = [System.Collections.Generic.List[string]]::new()
        foreach ($segment in ($raw -split '/')) { if ($segment -eq '..') { if ($segments.Count) { $segments.RemoveAt($segments.Count - 1) } } elseif ($segment -and $segment -ne '.') { $segments.Add($segment) } }
        '/' + ($segments -join '/')
    }
    $refsIn = {
        # The script files, npm scripts and make targets a text refers to (worked out once per text).
        param([string] $Key, [string] $Text)
        if ($refCache.ContainsKey($Key)) { return $refCache[$Key] }
        $text = [regex]::Replace($Text, '(?m)(^|[ \t])#[^\r\n]*', '')
        $folders = @(@('') + @([regex]::Matches($text, '(?m)^\s*(workingDirectory|workingDir|cwd)\s*:\s*[''"]?([^''"\r\n]+)') | ForEach-Object { $_.Groups[2].Value.Trim() }) | Select-Object -Unique)
        $files = [System.Collections.Generic.List[string]]::new()
        foreach ($m in [regex]::Matches($text, '(?m)^\s*(filePath|scriptPath|ScriptPath|scriptName)\s*:\s*[''"]?([^''"\r\n]+)')) { $files.Add($m.Groups[2].Value.Trim()) }
        foreach ($m in [regex]::Matches($text, '(?:^|[\s;&|(''"=])((?:\$\([\w.]+\)[/\\])?(?:\.{1,2}/)?[\w.-]+(?:[/\\][\w.-]+)*\.(?:sh|ps1|psm1|py|cmd|bat))\b')) { $files.Add($m.Groups[1].Value) }
        $npm = @([regex]::Matches($text, '\b(?:npm\s+(?:run|run-script)\s+|yarn\s+(?:run\s+)?|pnpm\s+(?:run\s+)?)([\w:.-]+)') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -notin 'install', 'add', 'ci', 'remove', 'upgrade', 'dlx', 'exec', 'i' -and -not $_.StartsWith('-') })
        $npm += @([regex]::Matches($text, '\bnpm\s+(test|start)\b') | ForEach-Object { $_.Groups[1].Value })
        $make = @([regex]::Matches($text, '(?m)(?:^|[\s;&|(])make(?:\s+-[\w-]+)*\s+([\w][\w.-]*)') | ForEach-Object { $_.Groups[1].Value })
        $refCache[$Key] = @{ Folders = $folders; Files = @($files | Select-Object -Unique); Npm = @($npm | Select-Object -Unique); Make = @($make | Select-Object -Unique) }
        $refCache[$Key]
    }
    $fileRound = [ordered]@{}
    $fileQueue = [System.Collections.Generic.List[hashtable]]::new()
    $addFile = {
        # One file for one pipeline: requested once however many pipelines run it.
        param([hashtable] $Entry, [string] $Path, [string] $Kind, [string[]] $Names, [int] $Level)
        $key = "$($Entry.ProjectId)|$($Entry.RepositoryId)|$($Entry.Ref)|$Path"
        $known = @($Entry.Files | Where-Object { $_.Key -eq $key }) | Select-Object -First 1
        if ($known) { $known.Names = @(@($known.Names) + @($Names) | Where-Object { $_ } | Select-Object -Unique); return }
        if ($Entry.Files.Count -ge $MaxScriptFiles) { return }
        $Entry.Files.Add(@{ Key = $key; Path = $Path; Kind = $Kind; Names = @($Names | Where-Object { $_ }); Level = $Level })
        if (-not $scriptContent.ContainsKey($key) -and -not $fileRound.Contains($key)) {
            $fileRound[$key] = "$org/$($Entry.ProjectId)/_apis/git/repositories/$($Entry.RepositoryId)/items?path=$(& $enc $Path)$(& $versionOf $Entry.Ref)&includeContent=true&`$format=json&$api"
            $fileQueue.Add(@{ Entry = $Entry; Key = $key; Level = $Level })
        }
    }
    $follow = {
        # What one text refers to, as files of the pipeline's repository.
        param([hashtable] $Entry, [string] $Key, [string] $Text, [string] $Folder, [int] $Level)
        $refs = & $refsIn $Key $Text
        foreach ($f in $refs.Files) {
            $path = & $normalise $f $Folder
            if ($path) { & $addFile $Entry $path 'Script file' @() $Level }
            else { $Entry.Unread.Add(@{ What = 'Script file'; Name = $f; Reason = 'Its path is built from a variable - it can''t be read before the run.' }) }
        }
        foreach ($dir in $refs.Folders) {
            $base = & $normalise $(if ($dir) { $dir } else { '.' }) $Folder
            if (-not $base -and $dir) { continue }
            if ($refs.Npm.Count) { & $addFile $Entry ((($base.TrimEnd('/')) + '/package.json') -replace '^/+', '/') 'package.json' $refs.Npm $Level }
            if ($refs.Make.Count) { & $addFile $Entry ((($base.TrimEnd('/')) + '/Makefile') -replace '^/+', '/') 'Makefile' $refs.Make $Level }
        }
    }
    if ($want.Yaml -and $MaxScriptFiles) {
        foreach ($entry in @($yaml.Values | Where-Object { $_.Content })) {
            $entry.Files = [System.Collections.Generic.List[hashtable]]::new()
            $entry.Unread = [System.Collections.Generic.List[hashtable]]::new()
            & $follow $entry "yaml|$($entry.ProjectId)|$($entry.Path)|$($entry.RepositoryId)" $entry.Content '' 1
            foreach ($tkey in @($entry.Templates)) { $tc = $templateContent[$tkey]; if ($tc -and $tc.Content) { & $follow $entry "tpl|$tkey" $tc.Content '' 1 } }
        }
        # Two levels: the files the pipelines run, then the script files those scripts run.
        for ($level = 1; $level -le 2 -and $fileRound.Count; $level++) {
            & $stage "Script files, package.json, Makefiles ($($fileRound.Count))"
            $answers = & $run $fileRound
            $queued = @($fileQueue)
            foreach ($key in $fileRound.Keys) {
                $a = $answers[$fileRound[$key]]
                $content = if ($a -and -not $a['Error']) { [string](Get-AACMember -InputObject $a['Body'] -Path 'content') } else { '' }
                # A file too big to be a script (a bundle, a lock file) is left out.
                $scriptContent[$key] = if (-not $a -or $a['Error']) { @{ Content = ''; Error = $(if ($a) { [string]$a['Error'] } else { 'no answer' }) } } elseif ($content.Length -gt 300KB) { @{ Content = ''; Error = 'Larger than 300 KB - not read.' } } else { @{ Content = $content; Error = '' } }
            }
            $fileRound = [ordered]@{}
            $fileQueue = [System.Collections.Generic.List[hashtable]]::new()
            if ($level -ge 2) { break }
            foreach ($item in $queued) {
                $sc = $scriptContent[$item.Key]
                $file = @($item.Entry.Files | Where-Object { $_.Key -eq $item.Key }) | Select-Object -First 1
                if (-not $sc.Content -or -not $file -or $file.Kind -ne 'Script file') { continue }
                # A script runs in the job's working directory (the repository), so its paths are from the root too.
                & $follow $item.Entry "file|$($item.Key)" $sc.Content '' 2
            }
        }
    }

    # What -Skip left out is empty rather than missing, so the converter needn't ask.
    foreach ($name in 'endpoints', 'groups', 'environments', 'policies', 'builds') { if (-not $byProject.ContainsKey($name)) { $byProject[$name] = @{} } }
    @{
        Organization = $org; OrganizationName = $orgName; Projects = $projects; Tasks = $tasks
        Definitions = $byProject.definitions; Releases = $byProject.releases; Repositories = $byProject.repositories
        Endpoints = $byProject['endpoints']; Groups = $byProject['groups']; Environments = $byProject['environments']; Policies = $byProject['policies']; Builds = $byProject['builds']
        Pushes = $pushes; Permissions = $permissions; Checks = $checks; Deployments = $deployments; AdvancedSecurity = $advancedSecurity
        Yaml = $yaml; TemplateContent = $templateContent; ScriptContent = $scriptContent; Skip = $Skip; MetricDays = $MetricDays
    }
}
