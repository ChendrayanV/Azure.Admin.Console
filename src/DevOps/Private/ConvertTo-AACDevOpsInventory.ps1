function ConvertTo-AACDevOpsInventory {
    <#
    .SYNOPSIS
        Turns what Read-AACDevOpsInventory read from one organization into
        projects, pipelines (with their delivery metrics), every task and
        tool each pipeline uses (with versions and what it does),
        repositories (with branch policies and Advanced Security), service
        connections, variable groups, environments (with DORA-style
        deployment metrics), tool usage and findings.
    .DESCRIPTION
        No calls. The YAML - the pipeline and every template it includes -
        is read by ConvertFrom-AACPipelineYaml; classic pipelines' steps are
        named through the organization's task catalogue. Both then go
        through the same checks:
          tasks        each task step: its major version, what it does
                       (the catalogue's description), whether it is
                       deprecated or an older major than the newest
          tools        command-line tools in scripts (Get-AACDevOpsCliRule)
                       with the version an installer task (UseNode@1,
                       HelmInstaller@1...) or the script itself (npm -g
                       x@1.2, Install-Module -RequiredVersion...) sets;
                       shells, containers, agent images and pools
          categories   Lint, Build, Test, Security, Deploy, Publish
                       (Get-AACDevOpsToolRule, and -ToolRule)
        Security: service connections (open to every pipeline, a secret
        rather than workload identity federation, unused), variable groups
        (secrets kept outside Key Vault, secret-looking values not marked
        secret - names only, never values), environments (production with
        no approval, no checks, open to every pipeline), branch policies on
        each repository's default branch (required reviewers, build
        validation). Metrics over the reader's -MetricDays: runs, success
        rate, average duration and queue time per pipeline; deployments,
        deployments a week and change failure rate per environment.

        Branching: each branch's role (from its name), age, ahead/behind and
        policies; each repository's strategy; every branch policy in words
        with its GitHub equivalent. DORA per project (and for the
        organization, in Stats.Dora): deployment frequency, lead time (run
        queued to deployed), change failure rate and time to restore, from
        production environments and classic release stages, banded Elite to
        Low. The move to GitHub: variables by name, feeds and packages, test
        plans, agent pools, extensions, a summary per project with effort
        points, and a map of where each kind of thing goes.

        -AzureLink (from Get-AACADOInventory -IncludeAzure) maps a service
        principal's application ID to its Azure role assignments.

        Disabled repositories, and the pipelines that build them, are left
        out (counted in Stats) unless -IncludeDisabledRepository.

        Speed: an organization has thousands of pipelines sharing a few
        hundred templates, so each file (pipeline or template) is parsed,
        stripped of comments, matched against the rules and scanned for
        secrets once, and the result reused by every pipeline that includes
        it; the rules' regular expressions are built once. -OnProgress is
        called with (project, pipelines done, pipelines in all).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Read,

        [object[]] $ToolRule = @(),

        [hashtable] $CliRule = (Get-AACDevOpsCliRule),

        [int] $StaleDays = 90,

        [int] $InactiveDays = 180,

        # A branch with no commit in this many days (not the default one) is stale.
        [int] $StaleBranchDays = 90,

        # Application ID (lower case) -> @{ DisplayName; Roles = @(@{ Role; Scope }) }.
        [hashtable] $AzureLink = @{},

        [switch] $IncludeDisabledRepository,

        [scriptblock] $OnProgress,

        [datetime] $Now = [datetime]::UtcNow
    )

    $org = ([string]$Read.Organization).TrimEnd('/')
    $orgName = [string]$Read.OrganizationName
    $itemsOf = { param($Answer) @(if ($Answer -and -not $Answer['Error']) { $Answer['Items'] | Where-Object { $_ } }) }
    $member = { param($Row, [string] $Path) Get-AACMember -InputObject $Row -Path $Path }
    $when = {
        param($Value)
        $d = if ($Value -is [datetime]) { $Value } elseif ($Value) { try { [datetime]::Parse([string]$Value, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal) } catch { $null } } else { $null }
        if ($d -and $d.Year -gt 2000) { $d.ToUniversalTime() } else { $null }
    }
    $daysSince = { param($Date) if ($Date) { [int][Math]::Floor(($Now - $Date).TotalDays) } else { $null } }
    $round = { param($Number, [int] $Digits = 1) if ($null -eq $Number) { $null } else { [Math]::Round([double]$Number, $Digits) } }
    $mean = { param([object[]] $Numbers) $n = @($Numbers | Where-Object { $null -ne $_ }); if ($n.Count) { ($n | Measure-Object -Average).Average } else { $null } }
    $sumOf = { param([object[]] $Rows, [string] $Property) $total = 0; foreach ($r in $Rows) { if ($null -ne $r.$Property) { $total += [int]$r.$Property } }; $total }
    # Hosted images retired (or retiring) by Microsoft: a pipeline asking for one queues forever or fails.
    $retired = '^(ubuntu-16\.04|ubuntu-18\.04|ubuntu-20\.04|windows-2016|vs2017-win2016|vs2015-win2012r2|win1803|windows-2019|macos-10\.\d+|macos-11|macos-12|macos-13)$'
    $categories = @('Lint', 'Build', 'Test', 'Security', 'Deploy', 'Publish', 'GitOps')
    $metricDays = [Math]::Max(1, [int]$Read.MetricDays)
    $since = $Now.AddDays(-$metricDays)
    $weeks = [Math]::Max(1.0, $metricDays / 7.0)
    $secretName = '(password|passwd|secret|token|apikey|api_key|connectionstring|accesskey|privatekey|clientsecret)$|^(password|secret|token)'
    $grantRoles = @('Owner', 'User Access Administrator', 'Role Based Access Control Administrator')
    $shellNames = @{ pwsh = 'PowerShell 7 (pwsh)'; powershell = 'Windows PowerShell 5.1'; bash = 'Bash'; cmd = 'cmd'; az = 'Azure CLI shell'; script = 'Shell (bash on Linux and macOS, cmd on Windows)' }
    $productionName = '(^|[-_. ])(prod|production|prd|live)([-_. ]|$)'
    # Advanced Security is on when any of its enablement flags is (the names changed with the Secret Protection / Code Security split).
    $advsecOn = { param($Body) [bool]@('advSecEnabled', 'advSecIsEnabled', 'secretProtectionEnabled', 'codeSecurityEnabled' | Where-Object { [string](Get-AACMember -InputObject $Body -Path $_) -eq 'True' }).Count }
    # A settings object as 'name=value' text: its flags and short values - not IDs, links or nested objects.
    $settingsText = {
        param($Body)
        if ($Body -isnot [System.Collections.IDictionary]) { return '' }
        (@(foreach ($settingName in $Body.Keys) {
                    $settingValue = $Body[$settingName]
                    if ([string]$settingName -match 'id$|url|_links|descriptor|^scope$' -or $null -eq $settingValue -or $settingValue -is [System.Collections.IDictionary] -or ($settingValue -is [System.Collections.IList])) { continue }
                    "$settingName=$settingValue"
                })) -join '; '
    }
    # A branch's role, from its name - what the branching strategy is read from.
    $branchKind = {
        param([string] $Name, [string] $Default)
        if ($Name -eq $Default) { 'Default' }
        elseif ($Name -match '^(develop|development|dev)$') { 'Develop' }
        elseif ($Name -match '^(release|releases|rel)[/-]') { 'Release' }
        elseif ($Name -match '^hotfix(es)?[/-]') { 'Hotfix' }
        elseif ($Name -match '^(feature|features|feat)[/-]') { 'Feature' }
        elseif ($Name -match '^(bugfix|bug|fix|fixes)[/-]') { 'Bugfix' }
        elseif ($Name -match '^users?/|@') { 'Personal' }
        elseif ($Name -match '^(main|master|trunk)$') { 'Mainline' }
        else { 'Other' }
    }
    # The DORA performance bands (State of DevOps 2023, rounded): frequency in deployments a day, lead time
    # and time to restore in hours, change failure rate in percent.
    $doraLevel = {
        param([string] $Metric, $Value)
        if ($null -eq $Value) { return '' }
        switch ($Metric) {
            'Frequency' { if ($Value -ge 1) { 'Elite' } elseif ($Value -ge (1 / 7)) { 'High' } elseif ($Value -ge (1 / 30)) { 'Medium' } else { 'Low' } }
            'Lead' { if ($Value -lt 24) { 'Elite' } elseif ($Value -lt 168) { 'High' } elseif ($Value -lt 720) { 'Medium' } else { 'Low' } }
            'Failure' { if ($Value -le 5) { 'Elite' } elseif ($Value -le 10) { 'High' } elseif ($Value -le 15) { 'Medium' } else { 'Low' } }
            'Restore' { if ($Value -lt 1) { 'Elite' } elseif ($Value -lt 24) { 'High' } elseif ($Value -lt 168) { 'Medium' } else { 'Low' } }
        }
    }
    $levelOrder = @('Elite', 'High', 'Medium', 'Low')
    $median = { param([object[]] $Numbers) $n = @($Numbers | Where-Object { $null -ne $_ } | Sort-Object); if (-not $n.Count) { return $null }; if ($n.Count % 2) { $n[[int][Math]::Floor($n.Count / 2)] } else { ($n[$n.Count / 2 - 1] + $n[$n.Count / 2]) / 2 } }
    # Each failed deployment to the time the same environment next deployed successfully: hours to restore.
    $restoreHours = {
        param([object[]] $Records)
        foreach ($group in @($Records | Where-Object { $_.Finish } | Group-Object -Property Environment)) {
            $ordered = @($group.Group | Sort-Object -Property Finish)
            # The last deployment has nothing after it (and strict mode won't index past the end).
            for ($i = 0; $i -lt $ordered.Count - 1; $i++) {
                # A run of failures is one outage, timed from its first failure.
                if ($ordered[$i].Result -ne 'failed' -or ($i -gt 0 -and $ordered[$i - 1].Result -eq 'failed')) { continue }
                $next = @($ordered[($i + 1)..($ordered.Count - 1)] | Where-Object { $_.Result -eq 'succeeded' }) | Select-Object -First 1
                if ($next) { ($next.Finish - $ordered[$i].Finish).TotalHours }
            }
        }
    }
    # Branch policies: what each does in words, and what it becomes on GitHub.
    $policyGitHub = @{
        'Minimum number of reviewers' = 'Ruleset: required approving reviews'; 'Build' = 'Ruleset: required status check (a workflow)'
        'Required reviewers' = 'CODEOWNERS and required code-owner review'; 'Comment requirements' = 'Ruleset: require conversation resolution'
        'Work item linking' = 'No equivalent (a pull request check, or the Azure Boards app)'; 'Require a merge strategy' = 'Allowed merge methods (repository or ruleset)'
        'Status' = 'Ruleset: required status check'; 'File size restriction' = 'Push ruleset: maximum file size'
        'Path Length restriction' = 'Push ruleset: maximum file path length'; 'Reserved names restriction' = 'Push ruleset: restricted file paths'
        'File name restriction' = 'Push ruleset: restricted file paths or extensions'
    }
    $policySummary = {
        param([string] $Type, $Settings, [hashtable] $PipelineNames)
        $at = { param([string] $Path) Get-AACMember -InputObject $Settings -Path $Path }
        switch ($Type) {
            'Minimum number of reviewers' { "at least $(& $at 'minimumApproverCount'); creator's vote counts: $([string](& $at 'creatorVoteCounts') -eq 'True'); reset on new pushes: $([string](& $at 'resetOnSourcePush') -eq 'True'); downvotes allowed: $([string](& $at 'allowDownvotes') -eq 'True')" }
            'Build' {
                $bid = [string](& $at 'buildDefinitionId')
                $minutes = [string](& $at 'validDuration')
                (@("pipeline $(if ($PipelineNames.ContainsKey($bid)) { $PipelineNames[$bid] } else { "#$bid" })"
                        $(if ($minutes -and $minutes -ne '0') { "valid for $minutes min" })
                        $(if ([string](& $at 'manualQueueOnly') -eq 'True') { 'queued by hand' } else { 'queued automatically' })) | Where-Object { $_ }) -join '; '
            }
            'Required reviewers' { "$(@(& $at 'requiredReviewerIds').Count) reviewer(s)$(if (& $at 'filenamePatterns') { " for $(@(& $at 'filenamePatterns') -join ', ')" })" }
            'Require a merge strategy' { 'allowed: ' + (@(@{ allowSquash = 'squash'; allowNoFastForward = 'merge (no fast-forward)'; allowRebase = 'rebase'; allowRebaseMerge = 'rebase and merge' }.GetEnumerator() | Where-Object { [string](& $at $_.Key) -eq 'True' } | ForEach-Object { $_.Value } | Sort-Object) -join ', ') }
            'Status' { "status $(& $at 'statusGenre')/$(& $at 'statusName')" }
            'File size restriction' { "files up to $([Math]::Round([double](& $at 'maximumGitBlobSizeInBytes') / 1MB, 1)) MB" }
            default { & $settingsText $Settings }
        }
    }
    # An Azure Artifacts feed with what is in it, and whether GitHub Packages can take it (npm, NuGet, Maven - not PyPI,
    # Universal Packages or Cargo).
    $feedRow = {
        param($Feed, $PackagesAnswer, [string] $ProjectLabel, [string] $Link)
        $packagesRead = [bool]($PackagesAnswer -and -not $PackagesAnswer['Error'])
        $packageList = @(& $itemsOf $PackagesAnswer)
        $protocols = @($packageList | ForEach-Object { ([string]$_['protocolType']).ToLowerInvariant() } | Select-Object -Unique)
        $unsupported = @($protocols | Where-Object { $_ -notin 'npm', 'nuget', 'maven' })
        [pscustomobject][ordered]@{
            PSTypeName     = 'AAC.DevOpsFeed'; Organization = $orgName; Project = $ProjectLabel; Feed = [string]$Feed['name']
            Packages       = $(if ($packagesRead) { $packageList.Count } else { $null })
            Protocols      = (@($packageList | Group-Object -Property { [string]$_['protocolType'] } | Sort-Object -Property Name | ForEach-Object { "$($_.Name) $($_.Count)" })) -join ', '
            Upstreams      = (@(@($Feed['upstreamSources']) | Where-Object { $_ } | ForEach-Object { [string]$_['name'] })) -join ', '
            GitHubPackages = $(if (-not $packagesRead) { 'Not read' } elseif (-not $packageList.Count) { 'Nothing to move' } elseif ($unsupported.Count) { "Not for $($unsupported -join ', ')" } else { 'Supported' })
            Unsupported    = @($packageList | Where-Object { ([string]$_['protocolType']).ToLowerInvariant() -in $unsupported }).Count
            Url            = $Link
        }
    }

    # The catalogue's regular expressions, built once: [regex]::IsMatch with a pattern string keeps only
    # 15 in its cache, and there are well over a hundred rules - each would be parsed again every time.
    # Multiline: a rule may anchor to a line (^\s*environment:); each file is matched as a whole.
    $toolRegex = @(foreach ($rule in $ToolRule) {
            # A rule of your own (-ToolRule) may have no Purpose or VersionOf.
            $versionOf = if ($rule.PSObject.Properties['VersionOf'] -and $rule.VersionOf) { [string]$rule.VersionOf } else { [string]$rule.Tool }
            $purpose = if ($rule.PSObject.Properties['Purpose']) { [string]$rule.Purpose } else { '' }
            @{ Rule = $rule; Regex = [regex]::new($rule.Pattern, 'IgnoreCase, Multiline'); VersionOf = $versionOf; Purpose = $purpose }
        })
    # All of them in one, to tell whether a script line is known to any rule (the Unrecognised tab).
    $anyRule = [regex]::new((@($ToolRule | ForEach-Object { "(?:$($_.Pattern))" }) -join '|'), 'IgnoreCase')
    $packageRegex = @(foreach ($rule in @($CliRule.Package)) { if ($rule) { @{ Rule = $rule; Regex = [regex]::new($rule.Pattern, 'IgnoreCase') } } })
    $secretRegex = [regex]::new('^[ \t]*-?[ \t]*([\w.-]*(password|passwd|secret|token|apikey|api_key|connectionstring|accesskey)[\w.-]*)[ \t]*:[ \t]*[''"]?(?!\$\(|\$\{\{|\$\[)([^\s''"#]{8,})', 'IgnoreCase, Multiline')
    # An evidence line goes into a report: anything that looks like a credential is masked first.
    $redact = {
        param([string] $Line)
        $masked = [regex]::Replace($Line.Trim(), '(?i)(password|passwd|pwd|secret|token|apikey|api[_-]?key|access[_-]?key|authorization|sig|connectionstring)(["'']?\s*[:=]\s*["'']?)[^\s"'';&]+', '$1$2***')
        $masked = [regex]::Replace($masked, '(?i)\b(bearer|basic)\s+[A-Za-z0-9._~+/=-]+', '$1 ***')
        $masked = [regex]::Replace($masked, '[A-Za-z0-9+/_=-]{32,}', '***')
        if ($masked.Length -gt 160) { $masked.Substring(0, 157) + '...' } else { $masked }
    }
    # Shell and PowerShell words that are no tool of their own: not "unrecognised".
    $builtins = [System.Collections.Generic.HashSet[string]]::new([string[]]@(
            'echo', 'cd', 'export', 'set', 'unset', 'if', 'then', 'else', 'elif', 'fi', 'for', 'while', 'until', 'do', 'done', 'case', 'esac', 'function', 'return', 'exit', 'source', 'true', 'false', 'test'
            'mkdir', 'rm', 'rmdir', 'cp', 'mv', 'ls', 'cat', 'chmod', 'chown', 'touch', 'pwd', 'sleep', 'find', 'grep', 'egrep', 'sed', 'awk', 'tr', 'cut', 'sort', 'uniq', 'head', 'tail', 'xargs', 'tee', 'printf', 'read', 'local', 'declare', 'eval'
            'exec', 'trap', 'shift', 'wait', 'env', 'sudo', 'basename', 'dirname', 'date', 'wc', 'tar', 'zip', 'unzip', 'gzip', 'base64', 'ln', 'which', 'command', 'type', 'readonly', 'let', 'shopt', 'umask', 'whoami', 'hostname', 'uname', 'df', 'du', 'ps', 'kill', 'diff', 'realpath', 'mktemp', 'seq', 'yes', 'nohup', 'time', 'timeout', 'stat', 'file', 'ssh', 'scp', 'rsync'
            'call', 'rem', 'setlocal', 'endlocal', 'goto', 'pushd', 'popd', 'dir', 'copy', 'del', 'md', 'rd', 'xcopy', 'robocopy', 'cls', 'start', 'where', 'ver'
            'param', 'try', 'catch', 'finally', 'foreach', 'elseif', 'switch', 'throw', 'break', 'continue', 'begin', 'process', 'end', 'filter', 'class', 'enum', 'using', 'import', 'trap', 'data'
        ), [System.StringComparer]::OrdinalIgnoreCase)
    $verbs = [System.Collections.Generic.HashSet[string]]::new([string[]]@(Get-Verb | ForEach-Object { $_.Verb }), [System.StringComparer]::OrdinalIgnoreCase)
    $unknownIn = {
        # The commands in script text that no catalogue rule knows - the first word of each line.
        param([string] $Text)
        $lineNumber = 0
        foreach ($line in ($Text -split "`r?`n")) {
            $lineNumber++
            $words = @($line.Trim() -split '\s+' | Where-Object { $_ })
            if (-not $words.Count) { continue }
            $word = $words[0]
            if ($word -eq 'sudo' -and $words.Count -gt 1) { $word = $words[1] }
            $word = ($word -replace '^&$', '' -replace '\.exe$', '').Trim('"', "'")
            if (-not $word -or $word -notmatch '^[A-Za-z][\w.+-]*$' -or $builtins.Contains($word)) { continue }
            # A PowerShell cmdlet (an approved verb, a dash) is PowerShell itself, not a tool.
            if ($word -match '^([A-Za-z]+)-\w' -and $verbs.Contains($Matches[1])) { continue }
            if ($anyRule.IsMatch($line)) { continue }
            @{ Command = $word.ToLowerInvariant(); Line = $lineNumber; Text = (& $redact $line) }
        }
    }
    # The packages a script installs at a version - kept on the step, and by script text: the same
    # script in many files (or pipelines) is matched once.
    $scriptCache = @{}
    $scriptHits = {
        param([hashtable] $Step)
        if (-not $scriptCache.ContainsKey($Step.Script)) {
            $scriptCache[$Step.Script] = @{
                Packages = @(foreach ($pk in $packageRegex) { foreach ($m in $pk.Regex.Matches($Step.Script)) { @{ Tool = $pk.Rule.Tool; Name = $m.Groups[1].Value; Version = $m.Groups[2].Value } } })
                Unknown  = @(& $unknownIn $Step.Script)
            }
        }
        $Step.Packages = $scriptCache[$Step.Script].Packages
        $Step.Unknown = $scriptCache[$Step.Script].Unknown
    }
    # Where a text matches the catalogue: per rule, the first line (number and text, masked), how many
    # times, and the image tag when the match is a container image (fluxcd/flux-cli:v2.3.0).
    $hitsIn = {
        param([string] $Text)
        if (-not $Text.Trim()) { return }
        # displayName is prose and template: names a file, not a tool: blanked.
        $blanked = [regex]::Replace($Text, '(?m)^(\s*-?\s*(displayName|template)\s*:).*$', '$1')
        # Each distinct line once (a file repeats the same steps): far less text for over a hundred
        # rules, with each distinct line's first line number and how often it occurs.
        $firstLine = [System.Collections.Generic.Dictionary[string, int]]::new()
        $occurs = [System.Collections.Generic.Dictionary[string, int]]::new()
        $distinctLines = [System.Collections.Generic.List[string]]::new()
        $number = 0
        foreach ($line in ($blanked -split "`r?`n")) {
            $number++
            if (-not $line.Trim()) { continue }
            if ($firstLine.ContainsKey($line)) { $occurs[$line]++ } else { $firstLine[$line] = $number; $occurs[$line] = 1; $distinctLines.Add($line) }
        }
        $matchText = $distinctLines -join "`n"
        $newlines = [System.Collections.Generic.List[int]]::new()
        for ($at = $matchText.IndexOf([char]10); $at -ge 0; $at = $matchText.IndexOf([char]10, $at + 1)) { $newlines.Add($at) }
        for ($i = 0; $i -lt $toolRegex.Count; $i++) {
            $m = $toolRegex[$i].Regex.Match($matchText)
            if (-not $m.Success) { continue }
            $before = $newlines.BinarySearch($m.Index)
            $lineIndex = if ($before -lt 0) { -bnot $before } else { $before + 1 }
            if ($lineIndex -ge $distinctLines.Count) { $lineIndex = $distinctLines.Count - 1 }
            $lineText = $distinctLines[$lineIndex]
            # An image on the line (registry/name:tag) that holds the match: its tag is the version.
            $tag = ''
            foreach ($image in [regex]::Matches($lineText, '((?:[\w.-]+/)+[\w.-]+):([A-Za-z0-9][\w.-]*)')) { if ($image.Groups[1].Value.IndexOf($m.Value.Trim(), [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $tag = $image.Groups[2].Value; break } }
            @{ Index = $i; Line = $firstLine[$lineText]; Text = (& $redact $lineText); Count = $occurs[$lineText]; Tag = $tag; Task = $lineText -match '^\s*-?\s*task\s*:'; Image = [bool]$tag -or $lineText -match '^\s*-?\s*(image|container|vmImage)\s*:' }
        }
    }
    # The task and tool rows (and the task version checks) a set of steps makes - worked out once per
    # file. An installer's 'sets ...' note (SetsTool) depends on the whole pipeline, so it is filled in
    # per pipeline.
    $specsOf = {
        param([object[]] $Steps)
        $rows = [System.Collections.Generic.List[hashtable]]::new()
        $checks = [System.Collections.Generic.List[hashtable]]::new()
        foreach ($s in $Steps) {
            if ($s.Kind -eq 'Task') {
                $nameKey = $s.Name.ToLowerInvariant()
                $info = if ($taskByName.ContainsKey("$nameKey|$($s.Major)")) { $taskByName["$nameKey|$($s.Major)"] } elseif ($taskByName.ContainsKey($nameKey)) { $taskByName[$nameKey] } else { $null }
                $inst = $CliRule.Installer[$s.Name]
                $rows.Add(@{ Kind = 'Task'; Name = $s.Name; Version = $(if ($s.Major) { "@$($s.Major)" } else { '' }); Purpose = $(if (-not $info) { '' } elseif ($info.Description) { $info.Description } else { $info.Friendly }); Category = $(if ($info) { $info.Category } else { '' }); Source = $s.Source; Note = $s.DisplayName; Enabled = $s.Enabled; SetsTool = $(if ($inst) { $inst.Tool } else { '' }) })
                $checks.Add(@{ NameKey = $nameKey; Name = $s.Name; Major = $s.Major; Deprecated = [bool]($info -and $info.Deprecated) })
            }
            elseif ($s.Kind -in 'Template', 'Checkout', 'Download', 'Publish') {
                $rows.Add(@{ Kind = $s.Kind; Name = $s.Name; Version = ''; Purpose = @{ Template = 'Includes a template'; Checkout = 'Checks out a repository'; Download = 'Downloads artifacts'; Publish = 'Publishes artifacts' }[$s.Kind]; Category = ''; Source = $s.Source; Note = $s.DisplayName; Enabled = $s.Enabled; SetsTool = '' })
            }
            if (-not $s.Script) { continue }
            if ($s.Kind -ne 'Task' -and $shellNames.ContainsKey($s.Shell)) { $rows.Add(@{ Kind = 'Shell'; Name = $shellNames[$s.Shell]; Version = ''; Purpose = 'Runs an inline script'; Category = 'Script'; Source = $s.Source; Note = $s.DisplayName; Enabled = $s.Enabled; SetsTool = '' }) }
            foreach ($pkg in @($s.Packages)) { $rows.Add(@{ Kind = 'Package'; Name = $pkg.Name; Version = $pkg.Version; Purpose = "Installed by $($pkg.Tool)"; Category = 'Package'; Source = $s.Source; Note = $s.DisplayName; Enabled = $s.Enabled; SetsTool = '' }) }
        }
        @{ Rows = $rows.ToArray(); Checks = $checks.ToArray() }
    }
    # A file's analysis, by key ('pipeline|project|id', the template's key, or a script file's): read
    # once, used by every pipeline. Kind: YAML (parsed into steps), or Script file, package.json,
    # Makefile (text the pipeline runs: matched and scanned for commands, no steps).
    $fileCache = @{}
    $analyse = {
        param([string] $Key, [string] $Label, [string] $Text, [string] $Kind = 'YAML')
        if ($fileCache.ContainsKey($Key)) { return $fileCache[$Key] }
        $stripped = [regex]::Replace($Text, '(?m)(^|[ \t])#[^\r\n]*', '')
        if ($Kind -ne 'YAML') {
            $unknown = @(& $unknownIn $stripped)
            $fileCache[$Key] = @{ Label = $Label; Kind = $Kind; Parsed = @{ Steps = @() }; Steps = @(); Specs = @{ Rows = @(); Checks = @() }; TaskCount = 0; Hits = @(& $hitsIn $stripped); Secrets = @(); Unknown = $unknown }
            return $fileCache[$Key]
        }
        $parsed = ConvertFrom-AACPipelineYaml -Text $Text
        foreach ($s in $parsed.Steps) { $s.Source = $Label }
        # A literal value under a secret-looking key: its key and line only, never the value.
        # One pass over the whole text; the line is the newlines before the match, plus one.
        $secrets = @(foreach ($m in $secretRegex.Matches($Text)) { @{ Key = $m.Groups[1].Value; Line = 1 + ($Text.Substring(0, $m.Index).Split([char]10).Count - 1) } })
        # Each distinct step once: thirty identical build steps make the same rows and findings as one.
        $distinct = [System.Collections.Generic.List[hashtable]]::new()
        $signatures = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($s in $parsed.Steps) {
            $signature = "$($s.Kind)|$($s.Name)|$($s.Major)|$($s.DisplayName)|$($s.Enabled)|$($s.Shell)|$($s.Script)"
            # An installer's inputs set a version: keep each set of them.
            if ($CliRule.Installer[$s.Name]) { $signature += '|' + ((@($s.Inputs.GetEnumerator()) | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ';') }
            if ($signatures.Add($signature)) { if ($s.Script) { & $scriptHits $s }; $distinct.Add($s) }
        }
        # Commands no rule knows, from the inline scripts (the YAML around them is structure, not commands).
        $unknown = @(foreach ($s in $distinct) { foreach ($u in @($s['Unknown'])) { if ($u) { @{ Command = $u.Command; Line = $s.Line + $u.Line; Text = $u.Text } } } })
        $fileCache[$Key] = @{ Label = $Label; Kind = 'YAML'; Parsed = $parsed; Steps = $distinct.ToArray(); Specs = (& $specsOf $distinct.ToArray()); TaskCount = $(@(foreach ($s in $parsed.Steps) { if ($s.Kind -eq 'Task') { 1 } }).Count); Hits = @(& $hitsIn $stripped); Secrets = $secrets; Unknown = $unknown }
        $fileCache[$Key]
    }
    # What a pipeline runs from package.json and a Makefile: only the scripts and targets it names
    # (with npm's pre/post scripts, and the npm scripts those run), as text with one line each.
    $runText = {
        param([string] $Kind, [string] $Content, [string[]] $Names)
        if ($Kind -eq 'package.json') {
            $scripts = try { (ConvertFrom-Json -InputObject $Content -AsHashtable -Depth 10)['scripts'] } catch { $null }
            if ($scripts -isnot [System.Collections.IDictionary]) { return '' }
            $wanted = [System.Collections.Generic.List[string]]::new()
            foreach ($n in $Names) { foreach ($candidate in @("pre$n", $n, "post$n")) { if ($scripts.Contains($candidate) -and -not $wanted.Contains($candidate)) { $wanted.Add($candidate) } } }
            foreach ($n in @($wanted)) { foreach ($m in [regex]::Matches([string]$scripts[$n], '\b(?:npm\s+run|yarn|pnpm(?:\s+run)?)\s+([\w:.-]+)')) { if ($scripts.Contains($m.Groups[1].Value) -and -not $wanted.Contains($m.Groups[1].Value)) { $wanted.Add($m.Groups[1].Value) } } }
            return (@($wanted | ForEach-Object { [string]$scripts[$_] }) -join "`n")
        }
        # Makefile: the recipe lines (tab-indented) of the targets named.
        $out = [System.Collections.Generic.List[string]]::new()
        $inTarget = $false
        foreach ($line in ($Content -split "`r?`n")) {
            if ($line -match '^([\w][\w./ -]*):(?!=)') { $inTarget = @($Matches[1] -split '\s+') | Where-Object { $_ -in $Names } | Select-Object -First 1; continue }
            if ($inTarget -and $line -match '^\t(.*)$') { $out.Add(($Matches[1] -replace '^[@-]+', '')) }
            elseif ($line.Trim() -and $line -notmatch '^\t') { $inTarget = $false }
        }
        $out -join "`n"
    }
    $pipelinesInAll = 0
    foreach ($answer in @($Read.Definitions.Values)) { $pipelinesInAll += @(& $itemsOf $answer).Count }
    $pipelinesDone = 0
    $disabledRepositories = 0
    $disabledPipelines = 0

    # The task catalogue: by ID (classic steps) and by name (YAML steps); the newest major of each.
    $taskById = @{}; $taskByName = @{}; $latestMajor = @{}
    foreach ($t in @($Read.Tasks)) {
        if (-not $t) { continue }
        # Contribution: set for a task an extension installed (marketplace) - built-in tasks have none.
        $info = @{ Name = [string]$t['name']; Friendly = [string]$t['friendlyName']; Description = [string]$t['description']; Category = [string]$t['category']; Deprecated = [string]$t['deprecated'] -eq 'True'; Major = [int](& $member $t 'version.major'); Author = [string]$t['author']; Contribution = [string]$t['contributionIdentifier'] }
        $taskId = ([string]$t['id']).ToLowerInvariant()
        $nameKey = $info.Name.ToLowerInvariant()
        $taskById["$taskId|$($info.Major)"] = $info
        $taskByName["$nameKey|$($info.Major)"] = $info
        if (-not $latestMajor.ContainsKey($nameKey) -or $info.Major -gt $latestMajor[$nameKey]) { $latestMajor[$nameKey] = $info.Major; $taskByName[$nameKey] = $info; $taskById[$taskId] = $info }
    }

    $findings = [System.Collections.Generic.List[object]]::new()
    $pipelines = [System.Collections.Generic.List[object]]::new()
    $taskRows = [System.Collections.Generic.List[object]]::new()
    $repositoryRows = [System.Collections.Generic.List[object]]::new()
    $projectRows = [System.Collections.Generic.List[object]]::new()
    $connectionRows = [System.Collections.Generic.List[object]]::new()
    $groupRows = [System.Collections.Generic.List[object]]::new()
    $environmentRows = [System.Collections.Generic.List[object]]::new()
    $memberRows = [System.Collections.Generic.List[object]]::new()
    # The first reason the people of a project couldn't be read (a token without Identity or Project and Team read).
    $membersError = ''
    $toolUse = @{}
    $evidenceRows = [System.Collections.Generic.List[object]]::new()
    $coverageRows = [System.Collections.Generic.List[object]]::new()
    $unreadRows = [System.Collections.Generic.List[object]]::new()
    $unknownUse = @{}
    # Branching, the move to GitHub, and DORA.
    $branchRows = [System.Collections.Generic.List[object]]::new()
    $policyRows = [System.Collections.Generic.List[object]]::new()
    $variableRows = [System.Collections.Generic.List[object]]::new()
    $doraRows = [System.Collections.Generic.List[object]]::new()
    $feedRows = [System.Collections.Generic.List[object]]::new()
    $testPlanRows = [System.Collections.Generic.List[object]]::new()
    $migrationRows = [System.Collections.Generic.List[object]]::new()
    # Every deployment of the organization (for its DORA tiles), and the pipelines that use each pool and extension.
    $orgDeployments = [System.Collections.Generic.List[object]]::new()
    $poolUse = @{}
    $extensionUse = @{}
    $useIn = { param([hashtable] $Table, [string] $Key, [string] $Who) if (-not $Key) { return }; $k = $Key.ToLowerInvariant(); if (-not $Table.ContainsKey($k)) { $Table[$k] = [System.Collections.Generic.HashSet[string]]::new() }; $null = $Table[$k].Add($Who) }
    $hookList = @(& $itemsOf $(if ($Read.Contains('Hooks')) { $Read.Hooks }))
    $readOf = { param([string] $Name, [string] $Key) if ($Read.Contains($Name) -and $Read[$Name] -is [System.Collections.IDictionary] -and $Read[$Name].Contains($Key)) { $Read[$Name][$Key] } else { $null } }

    foreach ($p in @($Read.Projects | Sort-Object -Property { [string]$_['name'] })) {
        $projectId = [string]$p['id']
        $projectName = [string]$p['name']
        $projectUrl = "$org/$([System.Uri]::EscapeDataString($projectName))"
        $projectFindingsFrom = $findings.Count
        $find = {
            param([string] $Severity, [string] $Subject, [string] $Title, [string] $Detail, [string] $Fix, [string] $Area = 'Pipeline')
            $findings.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.DevOpsFinding'; Severity = $Severity; Organization = $orgName; Project = $projectName; Area = $Area; Item = $Subject; Finding = $Title; Detail = $Detail; Recommendation = $Fix })
        }
        # Who may use a service connection, variable group or environment: every pipeline, or how many.
        $permissionOf = {
            param([string] $ResourceKind, [string] $ResourceId)
            $a = $Read.Permissions["$projectId|$ResourceKind|$ResourceId"]
            if (-not $a -or $a['Error']) { return @{ Known = $false; All = $false; Count = 0 } }
            @{ Known = $true; All = [string](& $member $a['Body'] 'allPipelines.authorized') -eq 'True'; Count = @(@(& $member $a['Body'] 'pipelines') | Where-Object { $_ -and [string]$_['authorized'] -ne 'False' }).Count }
        }

        # --- Service connections, variable groups, environments (the pipelines below say which they use) --------------
        $endpoints = @(& $itemsOf $Read.Endpoints[$projectId])
        $endpointByName = @{}; $endpointById = @{}
        foreach ($e in $endpoints) { $endpointByName[([string]$e['name']).ToLowerInvariant()] = $e; $endpointById[([string]$e['id']).ToLowerInvariant()] = $e }
        $groups = @(& $itemsOf $Read.Groups[$projectId])
        $environments = @(& $itemsOf $Read.Environments[$projectId])
        $usedConnections = @{}; $usedGroups = @{}; $usedEnvironments = @{}
        $use = { param([hashtable] $Table, [string] $Resource, [string] $Pipeline) $k = $Resource.ToLowerInvariant(); if (-not $Table.ContainsKey($k)) { $Table[$k] = [System.Collections.Generic.List[string]]::new() }; if (-not $Table[$k].Contains($Pipeline)) { $Table[$k].Add($Pipeline) } }
        $usersOf = { param([hashtable] $Table, [string] $Resource) $k = $Resource.ToLowerInvariant(); if ($Table.ContainsKey($k)) { $Table[$k] -join ', ' } else { '' } }

        # --- Repositories: last push, branch policies, Advanced Security ------------------------------------------------
        $policyAnswer = $Read.Policies[$projectId]
        $policiesRead = [bool]($policyAnswer -and -not $policyAnswer['Error'])
        $policies = @(& $itemsOf $policyAnswer | Where-Object { [string]$_['isEnabled'] -eq 'True' -and [string]$_['isDeleted'] -ne 'True' -and [string]$_['isBlocking'] -eq 'True' })
        # Every policy (on or off, blocking or not) for the Branch policies tab; build policies name their pipeline.
        $allPolicies = @(& $itemsOf $policyAnswer | Where-Object { [string]$_['isDeleted'] -ne 'True' })
        $pipelineNames = @{}
        foreach ($d in (& $itemsOf $Read.Definitions[$projectId])) { $pipelineNames[[string]$d['id']] = [string]$d['name'] }
        $repoById = @{}
        foreach ($r in (& $itemsOf $Read.Repositories[$projectId])) {
            $rid = [string]$r['id']
            $defaultRef = [string]$r['defaultBranch']
            $latest = @(& $itemsOf $(if ($Read.Pushes.Contains($rid)) { $Read.Pushes[$rid] })) | Select-Object -First 1
            $push = if ($latest) { @{ Date = & $when $latest['date']; By = [string](& $member $latest 'pushedBy.displayName') } } else { $null }
            # The blocking policies that cover the default branch: on this repository (or every one), exact or by prefix.
            $covering = @($policies | Where-Object {
                    @(@(& $member $_ 'settings.scope') | Where-Object { $_ -and (-not $_['repositoryId'] -or [string]$_['repositoryId'] -eq $rid) -and (-not $_['refName'] -or ([string]$_['matchKind'] -ne 'Prefix' -and [string]$_['refName'] -eq $defaultRef) -or ([string]$_['matchKind'] -eq 'Prefix' -and $defaultRef.StartsWith([string]$_['refName']))) }).Count
                })
            $reviewers = @($covering | Where-Object { [string](& $member $_ 'type.displayName') -eq 'Minimum number of reviewers' } | ForEach-Object { [int](& $member $_ 'settings.minimumApproverCount') } | Sort-Object -Descending) | Select-Object -First 1
            $advsec = $Read.AdvancedSecurity["$projectId|$rid"]
            $advsecBody = if ($advsec -and $advsec.Enablement -and -not $advsec.Enablement['Error']) { $advsec.Enablement['Body'] } else { $null }
            $advsecState = if (-not $advsecBody) { 'Unknown' } elseif (& $advsecOn $advsecBody) { 'On' } else { 'Off' }
            # Branches (with their last commit), tags, open pull requests and Git LFS - for the branching strategy and the move to GitHub.
            $branchAnswer = if ($Read.Contains('Branches') -and $Read.Branches.ContainsKey($rid)) { $Read.Branches[$rid] } else { $null }
            $tagAnswer = if ($Read.Contains('Tags') -and $Read.Tags.ContainsKey($rid)) { $Read.Tags[$rid] } else { $null }
            $prAnswer = if ($Read.Contains('PullRequests') -and $Read.PullRequests.ContainsKey($rid)) { $Read.PullRequests[$rid] } else { $null }
            $attrAnswer = if ($Read.Contains('GitAttributes') -and $Read.GitAttributes.ContainsKey($rid)) { $Read.GitAttributes[$rid] } else { $null }
            $alerts = @(if ($advsec -and $advsec.Alerts) { & $itemsOf $advsec.Alerts })
            $count = { param([string] $Field, [string] $Expected) @($alerts | Where-Object { [string]$_[$Field] -eq $Expected }).Count }
            $repoById[$rid] = @{
                Name             = [string]$r['name']
                DefaultBranch    = $($defaultRef -replace '^refs/heads/', '')
                Push             = $push
                Disabled         = [string]$r['isDisabled'] -eq 'True'
                SizeMB           = $(if ($null -ne $r['size']) { & $round ([double]$r['size'] / 1MB) } else { $null })
                Pipelines        = 0
                Url              = [string]$r['webUrl']
                Reviewers        = $(if ($null -ne $reviewers) { $reviewers } elseif ($policiesRead) { 0 } else { $null })
                BuildValidation  = $(if ($policiesRead) { [bool]@($covering | Where-Object { [string](& $member $_ 'type.displayName') -eq 'Build' }).Count } else { $null })
                Policies         = $(if ($policiesRead) { (@($covering | ForEach-Object { [string](& $member $_ 'type.displayName') } | Select-Object -Unique) -join ', ') } else { '' })
                AdvancedSecurity = $advsecState
                AdvsecSettings   = $(if ($advsecBody) { & $settingsText $advsecBody } else { '' })
                PushProtection   = $(if (-not $advsecBody) { $null } else { [bool]@($advsecBody.Keys | Where-Object { [string]$_ -match 'push|block' -and [string]$advsecBody[$_] -eq 'True' }).Count })
                BranchStats      = @(& $itemsOf $branchAnswer)
                BranchesRead     = [bool]($branchAnswer -and -not $branchAnswer['Error'])
                Tags             = $(if ($tagAnswer -and -not $tagAnswer['Error']) { @(& $itemsOf $tagAnswer).Count } else { $null })
                OpenPullRequests = $(if ($prAnswer -and -not $prAnswer['Error']) { @(& $itemsOf $prAnswer).Count } else { $null })
                Lfs              = $(if (-not $attrAnswer) { $null } elseif ($attrAnswer['Error']) { $false } else { [string](& $member $attrAnswer['Body'] 'content') -match 'filter=lfs' })
                CriticalAlerts   = & $count 'severity' 'critical'
                HighAlerts       = & $count 'severity' 'high'
                MediumAlerts     = & $count 'severity' 'medium'
                LowAlerts        = & $count 'severity' 'low'
                CodeAlerts       = & $count 'alertType' 'code'
                DependencyAlerts = & $count 'alertType' 'dependency'
                SecretAlerts     = & $count 'alertType' 'secret'
            }
        }

        # --- Runs of the last -MetricDays, by pipeline -----------------------------------------------------------------
        $buildAnswer = $Read.Builds[$projectId]
        $metricsRead = [bool]($buildAnswer -and -not $buildAnswer['Error'])
        $runsByDefinition = @{}
        # Runs by ID: a deployment record names the run that deployed (owner.id), whose queue time starts its lead time.
        $buildById = @{}
        foreach ($b in (& $itemsOf $buildAnswer)) {
            $buildById[[string]$b['id']] = $b
            $did = [string](& $member $b 'definition.id')
            if (-not $runsByDefinition.ContainsKey($did)) { $runsByDefinition[$did] = [System.Collections.Generic.List[object]]::new() }
            $runsByDefinition[$did].Add($b)
        }

        # --- Build pipelines: YAML or classic ---------------------------------------------------------------------------
        $mine = [System.Collections.Generic.List[object]]::new()
        $definitionsAnswer = $Read.Definitions[$projectId]
        if ($definitionsAnswer -and $definitionsAnswer['Error']) { & $find 'Info' $projectName 'Pipelines couldn''t be read' $definitionsAnswer['Error'] 'Give the token Build (Read).' }
        foreach ($d in (& $itemsOf $definitionsAnswer)) {
            $id = [int]$d['id']
            $name = [string]$d['name']
            $label = "$name (#$id)"
            $isYaml = [int](& $member $d 'process.type') -eq 2
            $repoId = [string](& $member $d 'repository.id')
            $pipelinesDone++
            if ($OnProgress) { & $OnProgress $projectName $pipelinesDone $pipelinesInAll }
            $onDisabled = $repoById.ContainsKey($repoId) -and $repoById[$repoId].Disabled
            if ($onDisabled -and -not $IncludeDisabledRepository) { $disabledPipelines++; continue }
            if ($repoById.ContainsKey($repoId)) { $repoById[$repoId].Pipelines++ }
            $last = & $member $d 'latestBuild'
            $lastRun = & $when (& $member $last 'finishTime')
            if (-not $lastRun) { $lastRun = & $when (& $member $last 'queueTime') }
            $result = [string](& $member $last 'result')
            $state = [string]$d['queueStatus']
            $push = if ($repoById.ContainsKey($repoId)) { $repoById[$repoId].Push } else { $null }

            # The steps: the YAML (the pipeline and every template it includes), or the classic designer's.
            $entry = if ($Read.Yaml.Contains("$projectId|$id")) { $Read.Yaml["$projectId|$id"] } else { $null }
            $templateLabels = [System.Collections.Generic.List[string]]::new()
            $sources = [System.Collections.Generic.List[hashtable]]::new()
            if ($isYaml -and $entry -and $entry.Content) {
                $sources.Add((& $analyse "pipeline|$projectId|$id" $entry.Path $entry.Content))
                foreach ($tkey in @($entry.Templates)) {
                    $tc = $Read.TemplateContent[$tkey]
                    if (-not $tc) { continue }
                    if ($tc.Label) { $templateLabels.Add($tc.Label) }
                    if ($tc.Content) { $sources.Add((& $analyse $tkey $tc.Label $tc.Content)) }
                    elseif ($tc.Error) { $unreadRows.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.DevOpsUnrecognised'; Organization = $orgName; Kind = 'Template not read'; Name = $tc.Label; Pipelines = 1; Lines = $null; Example = "$projectName / $name"; Detail = $tc.Error }) }
                }
                # What the pipeline runs outside the YAML: script files, package.json scripts, Makefile targets.
                if ($entry.Contains('Files')) {
                    foreach ($f in $entry.Files) {
                        $sc = $Read.ScriptContent[$f.Key]
                        if (-not $sc) { continue }
                        if (-not $sc.Content) { $unreadRows.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.DevOpsUnrecognised'; Organization = $orgName; Kind = "$($f.Kind) not read"; Name = $f.Path; Pipelines = 1; Lines = $null; Example = "$projectName / $name"; Detail = $sc.Error }); continue }
                        $fileText = if ($f.Kind -eq 'Script file') { $sc.Content } else { & $runText $f.Kind $sc.Content @($f.Names) }
                        $fileLabel = if ($f.Kind -eq 'Script file') { $f.Path } else { "$($f.Path) ($(@($f.Names) -join ', '))" }
                        $sources.Add((& $analyse "file|$($f.Key)|$(@($f.Names) -join ',')" $fileLabel $fileText $f.Kind))
                    }
                    foreach ($u in $entry.Unread) { $unreadRows.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.DevOpsUnrecognised'; Organization = $orgName; Kind = "$($u.What) not read"; Name = $u.Name; Pipelines = 1; Lines = $null; Example = "$projectName / $name"; Detail = $u.Reason }) }
                }
            }
            $steps = [System.Collections.Generic.List[hashtable]]::new()
            $refs = @{}
            foreach ($k in 'Images', 'Containers', 'Pools', 'Groups', 'Environments', 'Connections') { $refs[$k] = [System.Collections.Generic.List[string]]::new() }
            $taskCount = 0
            foreach ($src in $sources) {
                foreach ($s in $src.Steps) { $steps.Add($s) }
                $taskCount += $src.TaskCount
                foreach ($k in @($refs.Keys)) { foreach ($v in @($src.Parsed[$k])) { if ($v -and -not $refs[$k].Contains($v)) { $refs[$k].Add($v) } } }
            }
            $classicRead = $false
            if (-not $isYaml) {
                foreach ($phase in @(& $member $d 'process.phases')) {
                    foreach ($cs in @(& $member $phase 'steps')) {
                        if (-not $cs) { continue }
                        $classicRead = $true
                        $taskId = ([string](& $member $cs 'task.id')).ToLowerInvariant()
                        $major = ([string](& $member $cs 'task.versionSpec') -split '\.')[0]
                        $info = if ($taskById.ContainsKey("$taskId|$major")) { $taskById["$taskId|$major"] } elseif ($taskById.ContainsKey($taskId)) { $taskById[$taskId] } else { $null }
                        $inputs = [ordered]@{}
                        $rawInputs = & $member $cs 'inputs'
                        if ($rawInputs -is [System.Collections.IDictionary]) { foreach ($k in $rawInputs.Keys) { $inputs[$k] = [string]$rawInputs[$k] } }
                        $script = @($inputs.Keys | Where-Object { $_ -in 'script', 'inlineScript', 'Inline' } | ForEach-Object { $inputs[$_] } | Where-Object { $_ }) -join "`n"
                        $shell = if (-not $script -or -not $info) { '' } else { @{ PowerShell = $(if ($inputs['pwsh'] -eq 'true') { 'pwsh' } else { 'powershell' }); Bash = 'bash'; CmdLine = 'cmd'; AzureCLI = 'az'; AzurePowerShell = 'pwsh' }[$info.Name] }
                        $classicStep = @{ Kind = 'Task'; Name = $(if ($info) { $info.Name } else { $taskId }); Major = $major; DisplayName = [string]$cs['displayName']; Enabled = [string]$cs['enabled'] -ne 'False'; Inputs = $inputs; Script = $script; Shell = [string]$shell; Line = 0; Source = 'classic' }
                        if ($script) { & $scriptHits $classicStep }
                        $steps.Add($classicStep)
                        $taskCount++
                        # Classic inputs name service connections by their ID.
                        foreach ($v in $inputs.Values) {
                            foreach ($guid in ([string]$v -split '[,; ]')) {
                                $e = $endpointById[$guid.ToLowerInvariant()]
                                if ($e -and -not $refs.Connections.Contains([string]$e['name'])) { $refs.Connections.Add([string]$e['name']) }
                            }
                        }
                    }
                }
                foreach ($vg in @(& $member $d 'variableGroups')) { if ($vg -and $vg['name']) { $refs.Groups.Add([string]$vg['name']) } }
            }
            $stepsRead = ($isYaml -and $sources.Count) -or $classicRead
            foreach ($c in $refs.Connections) { & $use $usedConnections $c $name }
            foreach ($g in $refs.Groups) { & $use $usedGroups $g $name }
            foreach ($env in $refs.Environments) { & $use $usedEnvironments $env $name }

            # --- Variables (names only), marketplace tasks and pools: what the move to GitHub has to carry ------------
            $pipelineVariables = [System.Collections.Generic.List[string]]::new()
            $secretVariables = 0
            $definitionVariables = & $member $d 'variables'
            if ($definitionVariables -is [System.Collections.IDictionary]) {
                foreach ($variableName in $definitionVariables.Keys) {
                    $isSecret = [string](& $member $definitionVariables[$variableName] 'isSecret') -eq 'True'
                    if ($isSecret) { $secretVariables++ }
                    $pipelineVariables.Add([string]$variableName)
                    $variableRows.Add([pscustomobject][ordered]@{
                            PSTypeName = 'AAC.DevOpsVariable'; Organization = $orgName; Project = $projectName; Scope = 'Pipeline settings'; Owner = $name; Variable = [string]$variableName
                            Secret = $isSecret; Settable = [string](& $member $definitionVariables[$variableName] 'allowOverride') -eq 'True'
                            GitHub = $(if ($isSecret) { 'Repository or environment secret (secrets.NAME)' } else { 'Repository or environment variable (vars.NAME)' })
                        })
                }
            }
            foreach ($src in $sources) {
                foreach ($variableName in @($src.Parsed['Variables'])) {
                    if (-not $variableName -or $pipelineVariables.Contains([string]$variableName)) { continue }
                    $pipelineVariables.Add([string]$variableName)
                    $variableRows.Add([pscustomobject][ordered]@{
                            PSTypeName = 'AAC.DevOpsVariable'; Organization = $orgName; Project = $projectName; Scope = 'YAML'; Owner = "$name ($($src.Label))"; Variable = [string]$variableName
                            Secret = $false; Settable = $false; GitHub = 'env: in the workflow (or vars.NAME if shared)'
                        })
                }
            }
            $extensionTasks = [System.Collections.Generic.List[string]]::new()
            foreach ($s in @($steps | Where-Object { $_.Kind -eq 'Task' })) {
                $nameKey = ([string]$s.Name).ToLowerInvariant()
                $info = if ($taskByName.ContainsKey("$nameKey|$($s.Major)")) { $taskByName["$nameKey|$($s.Major)"] } elseif ($taskByName.ContainsKey($nameKey)) { $taskByName[$nameKey] } else { $null }
                if (-not $info -or -not $info.Contribution) { continue }
                if (-not $extensionTasks.Contains($info.Name)) { $extensionTasks.Add($info.Name) }
                # publisher.extension.contribution: the first two parts name the extension.
                & $useIn $extensionUse ((@($info.Contribution -split '\.') | Select-Object -First 2) -join '.') "$projectName / $name"
            }
            $poolNames = @(@($refs.Pools) + @([string](& $member $d 'queue.pool.name'), [string](& $member $d 'queue.name')) | Where-Object { $_ } | Select-Object -Unique -First 3)
            foreach ($poolName in $poolNames) { & $useIn $poolUse $poolName "$projectName / $name" }

            # --- Tasks and tools, with versions and what they do --------------------------------------------------
            # One row for each distinct use: two identical steps in a file (or one CLI in two scripts) are one row.
            $taskSeen = [System.Collections.Generic.HashSet[string]]::new()
            $taskRow = {
                param([string] $Kind, [string] $ToolName, [string] $Version, [string] $Purpose, [string] $Category, [string] $From, [string] $Note, [bool] $On = $true)
                if (-not $taskSeen.Add("$Kind|$ToolName|$Version|$From|$Note")) { return }
                $taskRows.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.DevOpsTask'; Organization = $orgName; Project = $projectName; Pipeline = $name; PipelineId = $id; Kind = $Kind; Name = $ToolName; Version = $Version; Functionality = $Purpose; Category = $Category; Source = $From; Detail = $Note; Enabled = $On })
            }
            # Versions set by installer tasks (UseNode@1 version: 20.x...): the CLIs below are reported with them.
            $toolVersion = @{}
            foreach ($s in @($steps | Where-Object { $_.Kind -eq 'Task' })) {
                $inst = $CliRule.Installer[$s.Name]
                if (-not $inst) { continue }
                if ($s.Name -eq 'PowerShell') { $toolVersion['PowerShell'] = if ([string]$s.Inputs['pwsh'] -eq 'true') { 'PowerShell 7 (pwsh)' } else { 'Windows PowerShell 5.1' }; continue }
                $v = @($inst.Inputs | ForEach-Object { $s.Inputs[$_] } | Where-Object { $_ }) | Select-Object -First 1
                if ($v) { $toolVersion[$inst.Tool] = [string]$v } elseif ($inst.Default -and -not $toolVersion.ContainsKey($inst.Tool)) { $toolVersion[$inst.Tool] = $inst.Default }
            }
            $reported = [System.Collections.Generic.HashSet[string]]::new()
            # The files' rows (worked out once per file) and the classic steps', filled in for this pipeline -
            # inline rather than through $taskRow: tens of thousands of rows make each call count.
            $specSets = @(@($sources | ForEach-Object { $_.Specs }) + @(if ($classicRead) { & $specsOf @($steps | Where-Object { $_.Source -eq 'classic' }) }))
            foreach ($specSet in $specSets) {
                foreach ($spec in $specSet.Rows) {
                    $version = $spec.Version
                    $note = $spec.Note
                    if ($spec.SetsTool -and $toolVersion.ContainsKey($spec.SetsTool)) { $note = $(if ($note) { "$note - " } else { '' }) + "sets $($spec.SetsTool) $($toolVersion[$spec.SetsTool])" }
                    if (-not $taskSeen.Add("$($spec.Kind)|$($spec.Name)|$version|$($spec.Source)|$note")) { continue }
                    $taskRows.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.DevOpsTask'; Organization = $orgName; Project = $projectName; Pipeline = $name; PipelineId = $id; Kind = $spec.Kind; Name = $spec.Name; Version = $version; Functionality = $spec.Purpose; Category = $spec.Category; Source = $spec.Source; Detail = $note; Enabled = $spec.Enabled })
                }
                foreach ($check in $specSet.Checks) {
                    if ($check.Deprecated) {
                        if ($reported.Add("deprecated|$($check.NameKey)")) { & $find 'Medium' $label 'Deprecated task' "$($check.Name)@$($check.Major) is deprecated." 'Replace it with the task its description points to, before it stops working.' }
                    }
                    elseif ($latestMajor.ContainsKey($check.NameKey) -and $check.Major -match '^\d+$' -and [int]$check.Major -lt $latestMajor[$check.NameKey] -and $reported.Add("older|$($check.NameKey)")) { & $find 'Low' $label 'Older task version' "$($check.Name)@$($check.Major) - @$($latestMajor[$check.NameKey]) is the newest." "Move to $($check.Name)@$($latestMajor[$check.NameKey]) (its release notes list changed inputs)." }
                }
            }
            foreach ($image in $refs.Containers) {
                $tag = if ($image -match ':([\w.-]+)$') { $Matches[1] } else { 'latest' }
                & $taskRow 'Container' ($image -replace ':[\w.-]+$', '') $tag 'Runs a job or a service in this container image' 'Container' '' ''
                if ($tag -eq 'latest' -and $reported.Add("latest|$image")) { & $find 'Low' $label 'Container image not pinned' "$image runs whatever 'latest' is at the time." 'Pin a version (or a digest), so a new image can''t change the build unannounced.' }
            }
            foreach ($image in $refs.Images) { & $taskRow 'Agent image' $image '' 'Microsoft-hosted agent image' 'Agent' '' '' }
            foreach ($pool in $refs.Pools) { & $taskRow 'Agent pool' $pool '' 'Agent pool the jobs run on' 'Agent' '' '' }

            # Tools, from the catalogue: the same rules for every file the pipeline runs - its YAML and templates,
            # its script files, package.json scripts and Makefile targets, a classic pipeline's tasks (their name
            # and inputs stand in for YAML). Each match is evidence: the file, the line and what it says.
            $classicText = @($steps | Where-Object { $_.Source -eq 'classic' } | ForEach-Object { "task: $($_.Name)@$($_.Major)`n$($_.DisplayName)`n$((@($_.Inputs.GetEnumerator()) | ForEach-Object { "$($_.Key): $($_.Value)" }) -join "`n")" }) -join "`n"
            $evidenceSets = @(@($sources | ForEach-Object { @{ Kind = $_.Kind; Label = $_.Label; Hits = $_.Hits } }) + @(if ($classicText.Trim()) { @{ Kind = 'Classic'; Label = 'classic'; Hits = @(& $hitsIn $classicText) } }))
            $found = [ordered]@{}
            foreach ($c in $categories) { $found[$c] = [System.Collections.Generic.List[string]]::new() }
            $counted = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($set in $evidenceSets) {
                foreach ($hit in @($set.Hits)) {
                    if (-not $hit) { continue }
                    $entryRule = $toolRegex[$hit.Index]
                    $rule = $entryRule.Rule
                    $how = if ($set.Kind -eq 'Classic') { 'Classic task' } elseif ($set.Kind -ne 'YAML') { $set.Kind } elseif ($hit.Image) { 'Container image' } elseif ($hit.Task) { 'Task' } else { 'YAML / inline script' }
                    # 'agent default': a command run with whatever version the agent has - not a YAML setting (environment:).
                    $isSetting = $hit.Text -match '^\s*-?\s*[\w.]+\s*:' -and $hit.Text -notmatch '^\s*-?\s*(script|bash|pwsh|powershell|inlineScript|Inline|arguments)\s*:'
                    $version = if ($hit.Tag) { $hit.Tag } elseif ($toolVersion.ContainsKey($entryRule.VersionOf)) { $toolVersion[$entryRule.VersionOf] } elseif ($how -in 'YAML / inline script', 'Script file', 'package.json', 'Makefile' -and -not $isSetting) { 'agent default' } else { '' }
                    $evidenceRows.Add([pscustomobject][ordered]@{
                            PSTypeName = 'AAC.DevOpsToolEvidence'; Organization = $orgName; Project = $projectName; Pipeline = $name; PipelineId = $id
                            Tool = $rule.Tool; Category = $rule.Category; Version = $version; Found = $how; File = $set.Label; Line = $hit.Line; Matches = $hit.Count; Evidence = $hit.Text; Purpose = $entryRule.Purpose
                        })
                    if ($found.Contains($rule.Category) -and -not $found[$rule.Category].Contains($rule.Tool)) { $found[$rule.Category].Add($rule.Tool) }
                    $useKey = "$($rule.Category)|$($rule.Tool)"
                    if (-not $toolUse.ContainsKey($useKey)) { $toolUse[$useKey] = @{ Category = $rule.Category; Tool = $rule.Tool; Purpose = $entryRule.Purpose; Pipelines = 0; Evidence = 0; Projects = [System.Collections.Generic.HashSet[string]]::new(); Versions = [System.Collections.Generic.HashSet[string]]::new(); Found = [System.Collections.Generic.HashSet[string]]::new() } }
                    $usage = $toolUse[$useKey]
                    if ($counted.Add($useKey)) { $usage.Pipelines++ }
                    $usage.Evidence++
                    $null = $usage.Projects.Add($(if ($orgName) { "$orgName/$projectName" } else { $projectName }))
                    if ($version) { $null = $usage.Versions.Add($version) }
                    $null = $usage.Found.Add($how)
                }
            }
            # Commands no rule knows: across all pipelines, so a missing tool shows by how often it runs.
            $unknownHere = @(@(foreach ($src in $sources) { foreach ($u in @($src.Unknown)) { if ($u) { @{ Command = $u.Command; Line = $u.Line; Text = $u.Text; File = $src.Label } } } }) + @($steps | Where-Object { $_.Source -eq 'classic' } | ForEach-Object { foreach ($u in @($_['Unknown'])) { if ($u) { @{ Command = $u.Command; Line = $u.Line; Text = $u.Text; File = 'classic' } } } }))
            foreach ($u in $unknownHere) {
                if (-not $unknownUse.ContainsKey($u.Command)) { $unknownUse[$u.Command] = @{ Lines = 0; Pipelines = [System.Collections.Generic.HashSet[string]]::new(); Example = "$projectName / $name - $($u.File):$($u.Line): $($u.Text)" } }
                $unknownUse[$u.Command].Lines++
                $null = $unknownUse[$u.Command].Pipelines.Add("$projectName|$id")
            }

            # --- Delivery metrics ----------------------------------------------------------------------------------
            $runs = @(if ($runsByDefinition.ContainsKey([string]$id)) { $runsByDefinition[[string]$id] | Where-Object { [string]$_['status'] -eq 'completed' } })
            # Cancelled runs say nothing about the pipeline's health: the success rate leaves them out.
            $judgedRuns = @($runs | Where-Object { [string]$_['result'] -in 'succeeded', 'failed', 'partiallySucceeded' })
            $succeeded = @($runs | Where-Object { [string]$_['result'] -eq 'succeeded' }).Count
            $durations = @($runs | ForEach-Object { $s0 = & $when $_['startTime']; $f0 = & $when $_['finishTime']; if ($s0 -and $f0) { ($f0 - $s0).TotalMinutes } })
            $queues = @($runs | ForEach-Object { $q0 = & $when $_['queueTime']; $s0 = & $when $_['startTime']; if ($q0 -and $s0) { ($s0 - $q0).TotalMinutes } })
            $successRate = if ($judgedRuns.Count) { & $round (100.0 * $succeeded / $judgedRuns.Count) } else { $null }
            $avgQueue = & $round (& $mean $queues)

            # --- Findings ------------------------------------------------------------------------------------------
            $before = $findings.Count
            if (-not $isYaml) { & $find 'Medium' $label 'Classic build pipeline (no YAML)' 'Defined in the designer: its steps aren''t in the repository, so they aren''t reviewed, versioned or branched with the code.' 'Move it to YAML (Export to YAML in the pipeline''s menu gives a start), then disable the classic one.' }
            $runDays = & $daysSince $lastRun
            if (-not $last) { & $find 'Low' $label 'Never run' 'The pipeline has no run.' 'Run it, or delete it if nothing needs it.' }
            elseif ($null -ne $runDays -and $runDays -gt $StaleDays) { & $find 'Low' $label "Not run in $StaleDays days" "Last run $runDays days ago." 'Delete it, or disable it, if it is no longer used.' }
            if ($result -eq 'failed') { & $find 'Medium' $label 'Last run failed' "Run $([string](& $member $last 'buildNumber')) on $(([string](& $member $last 'sourceBranch')) -replace '^refs/heads/', '') failed." 'Open the run and fix the failing step - a red default branch hides new failures.' }
            elseif ($result -eq 'partiallySucceeded') { & $find 'Low' $label 'Last run partially succeeded' 'A step failed with continueOnError.' 'Check the warnings: a skipped test or scan stage can go unnoticed.' }
            if ($state -in 'disabled', 'paused') { & $find 'Info' $label "Pipeline $state" "New runs are $state." 'Delete it if it is no longer needed.' }
            if ($onDisabled) { & $find 'Low' $label 'Pipeline on a disabled repository' "Its repository, $($repoById[$repoId].Name), is disabled: the pipeline can't run." 'Delete the pipeline, or enable the repository if it is still needed.' }
            elseif ($isYaml -and $entry -and -not $entry.Content) { & $find 'Info' $label 'YAML not read' $entry.Error 'Tools and checks can''t be judged for this pipeline.' }
            foreach ($tkey in @(if ($entry) { $entry.Templates })) { $tc = $Read.TemplateContent[$tkey]; if ($tc -and $tc.Error) { & $find 'Info' $label 'Template not read' "$($tc.Label): $($tc.Error)" 'Tools in that template aren''t counted.' } }
            if ($stepsRead) {
                if (-not $found['Security'].Count) { & $find 'Medium' $label 'No security scanning' "No code, dependency, secret, container or infrastructure scanner found in $(if ($isYaml) { 'the YAML or its templates' } else { 'the classic pipeline''s tasks' })." 'Add Microsoft Security DevOps (or GitHub Advanced Security for Azure DevOps), and a dependency and secret scan.' }
                if ($found['Build'].Count -and -not $found['Test'].Count) { & $find 'Low' $label 'No tests' 'It builds, but no test runner or test results were found.' 'Run the tests in the pipeline and publish their results (PublishTestResults@2).' }
                if (-not $found['Lint'].Count) { & $find 'Low' $label 'No linting' 'No linter or format check found.' 'Add the language''s linter (ESLint, PSScriptAnalyzer, Ruff, TFLint...) so style and simple bugs fail the build.' }
            }
            foreach ($image in $refs.Images) { if ($image -match $retired) { & $find 'Medium' $label 'Retired hosted image' "vmImage: $image is retired (or retiring) on Microsoft-hosted agents." 'Use a current image - ubuntu-latest, windows-latest or macOS-latest, or a pinned supported version.' } }
            foreach ($src in $sources) {
                foreach ($hit in $src.Secrets) { & $find 'High' $label 'Possible secret in the YAML' "Key '$($hit.Key)' on line $($hit.Line) of $($src.Label) has a literal value." 'Move it to a secret variable, a variable group linked to Key Vault, or a service connection - and rotate it: it is in the repository history.' }
            }
            if ($null -ne $successRate -and $judgedRuns.Count -ge 5 -and $successRate -lt 80) { & $find 'Medium' $label 'Unreliable pipeline' "$successRate% of $($judgedRuns.Count) runs in $metricDays days succeeded." 'Look at what fails most (flaky tests, agents, outside services) - a pipeline that often fails stops being trusted.' }
            if ($null -ne $avgQueue -and $avgQueue -ge 10) { & $find 'Low' $label 'Long queue times' "Runs waited $avgQueue minutes on average for an agent." 'Add parallel jobs or agents, or spread out scheduled runs.' }

            $mine.Add([pscustomobject][ordered]@{
                    PSTypeName     = 'AAC.DevOpsPipeline'
                    Organization   = $orgName
                    Project        = $projectName
                    Pipeline       = $name
                    Id             = $id
                    Kind           = $(if ($isYaml) { 'YAML' } else { 'Classic build' })
                    Folder         = [string]$d['path']
                    YamlFile       = $(if ($isYaml) { [string](& $member $d 'process.yamlFilename') } else { '' })
                    Yaml           = $(if ($onDisabled) { 'Repository disabled' } elseif (-not $isYaml) { 'Classic' } elseif ($sources.Count) { 'Read' } else { 'Not read' })
                    Repository     = [string](& $member $d 'repository.name')
                    RepositoryType = [string](& $member $d 'repository.type')
                    DefaultBranch  = $(([string](& $member $d 'repository.defaultBranch')) -replace '^refs/heads/', '')
                    State          = $state
                    LastRun        = $lastRun
                    LastResult     = $(if ($result) { $result } elseif ($last) { [string](& $member $last 'status') } else { 'Never run' })
                    LastRunBy      = [string](& $member $last 'requestedFor.displayName')
                    LastRunBranch  = $(([string](& $member $last 'sourceBranch')) -replace '^refs/heads/', '')
                    DaysSinceRun   = $runDays
                    LastPush       = $(if ($push) { $push.Date } else { $null })
                    LastPushBy     = $(if ($push) { $push.By } else { '' })
                    DaysSincePush  = $(if ($push) { & $daysSince $push.Date } else { $null })
                    Runs           = $(if ($metricsRead) { $runs.Count } else { $null })
                    SuccessRate    = $successRate
                    AvgDurationMin = $(& $round (& $mean $durations))
                    AvgQueueMin    = $avgQueue
                    RunsPerWeek    = $(if ($metricsRead) { & $round ($runs.Count / $weeks) } else { $null })
                    Lint           = $found['Lint'] -join ', '
                    Build          = $found['Build'] -join ', '
                    Test           = $found['Test'] -join ', '
                    Security       = $found['Security'] -join ', '
                    Deploy         = $found['Deploy'] -join ', '
                    Publish        = $found['Publish'] -join ', '
                    GitOps         = $found['GitOps'] -join ', '
                    Tasks          = $taskCount
                    Templates      = $templateLabels -join ', '
                    Images         = $refs.Images -join ', '
                    Containers     = $refs.Containers -join ', '
                    Connections    = $refs.Connections -join ', '
                    VariableGroups = $refs.Groups -join ', '
                    Environments   = $refs.Environments -join ', '
                    Pools          = $poolNames -join ', '
                    Variables      = $pipelineVariables.Count
                    SecretVariables = $secretVariables
                    ExtensionTasks = $extensionTasks -join ', '
                    AzureTargets   = ''
                    Findings       = $findings.Count - $before
                    Url            = "$projectUrl/_build?definitionId=$id"
                })
            # Coverage: which stages the pipeline has - Yes, No, or Not read (its steps couldn't be read).
            $coverage = [ordered]@{ PSTypeName = 'AAC.DevOpsCoverage'; Organization = $orgName; Project = $projectName; Pipeline = $name; Kind = $(if ($isYaml) { 'YAML' } else { 'Classic build' }) }
            foreach ($c in 'Lint', 'Build', 'Test', 'Security', 'Deploy', 'Publish', 'GitOps') { $coverage[$c] = if (-not $stepsRead) { 'Not read' } elseif ($found[$c].Count) { 'Yes' } else { 'No' } }
            $coverage.Tools = @($found.Values | ForEach-Object { $_ }).Count
            $coverageRows.Add([pscustomobject]$coverage)
        }

        # --- Classic release pipelines ---------------------------------------------------------------------------------
        $releaseAnswer = if ($Read.Releases.Contains($projectId)) { $Read.Releases[$projectId] } else { $null }
        foreach ($rd in (& $itemsOf $releaseAnswer)) {
            $id = [int]$rd['id']
            $label = "$([string]$rd['name']) (release #$id)"
            $lastRelease = & $when (& $member $rd 'lastRelease.createdOn')
            $releaseDays = & $daysSince $lastRelease
            $before = $findings.Count
            & $find 'Low' $label 'Classic release pipeline' 'A classic release: its stages and approvals aren''t in the repository.' 'Move it to YAML stages with environments - approvals and checks then live with the code.'
            if (-not $lastRelease) { & $find 'Low' $label 'Never released' 'The release pipeline has no release.' 'Delete it if nothing needs it.' }
            elseif ($releaseDays -gt $StaleDays) { & $find 'Low' $label "No release in $StaleDays days" "Last release $releaseDays days ago." 'Delete it if it is no longer used.' }
            $mine.Add([pscustomobject][ordered]@{
                    PSTypeName = 'AAC.DevOpsPipeline'; Organization = $orgName; Project = $projectName; Pipeline = [string]$rd['name']; Id = $id; Kind = 'Classic release'; Folder = [string]$rd['path']; YamlFile = ''; Yaml = 'Classic'
                    Repository = ''; RepositoryType = ''; DefaultBranch = ''; State = ''; LastRun = $lastRelease; LastResult = $(if ($lastRelease) { [string](& $member $rd 'lastRelease.name') } else { 'Never released' })
                    LastRunBy = [string](& $member $rd 'lastRelease.createdBy.displayName'); LastRunBranch = ''; DaysSinceRun = $releaseDays; LastPush = $null; LastPushBy = ''; DaysSincePush = $null
                    Runs = $null; SuccessRate = $null; AvgDurationMin = $null; AvgQueueMin = $null; RunsPerWeek = $null
                    Lint = ''; Build = ''; Test = ''; Security = ''; Deploy = ''; Publish = ''; GitOps = ''; Tasks = 0; Templates = ''; Images = ''; Containers = ''; Connections = ''; VariableGroups = ''; Environments = ''
                    Pools = ''; Variables = $null; SecretVariables = $null; ExtensionTasks = ''; AzureTargets = ''
                    Findings = $findings.Count - $before; Url = "$projectUrl/_release?definitionId=$id"
                })
        }
        # The pipelines' Azure targets: the subscriptions (or scopes) their Azure connections reach.
        foreach ($pl in $mine) {
            $targets = @($pl.Connections -split ', ' | Where-Object { $_ } | ForEach-Object { $endpointByName[$_.ToLowerInvariant()] } | Where-Object { $_ -and [string]$_['type'] -eq 'azurerm' } | ForEach-Object {
                    $sub = [string](& $member $_ 'data.subscriptionName')
                    if ($sub) { $sub } else { [string](& $member $_ 'authorization.parameters.scope') }
                } | Where-Object { $_ } | Select-Object -Unique)
            $pl.AzureTargets = $targets -join ', '
        }
        $pipelines.AddRange([object[]]$mine.ToArray())

        # --- Service connections ---------------------------------------------------------------------------------------
        foreach ($e in @($endpoints | Sort-Object -Property { [string]$_['name'] })) {
            $eid = [string]$e['id']
            $ename = [string]$e['name']
            $type = [string]$e['type']
            $scheme = [string](& $member $e 'authorization.scheme')
            $perm = & $permissionOf 'endpoint' $eid
            $usedBy = & $usersOf $usedConnections $ename
            $appId = ([string](& $member $e 'authorization.parameters.serviceprincipalid')).ToLowerInvariant()
            $scope = [string](& $member $e 'authorization.parameters.scope')
            $link = if ($appId -and $AzureLink.ContainsKey($appId)) { $AzureLink[$appId] } else { $null }
            $label = "$ename (service connection)"
            $before = $findings.Count
            if ($perm.All) { & $find $(if ($type -in 'azurerm', 'kubernetes', 'dockerregistry') { 'High' } else { 'Medium' }) $label 'Open to every pipeline' "Any pipeline in $projectName can use '$ename' ($type) without being granted it." 'Turn off "Grant access permission to all pipelines" and authorize the pipelines that need it; add an approval check on the connection.' 'Security' }
            if ($type -eq 'azurerm' -and $scheme -eq 'ServicePrincipal') { & $find 'Medium' $label 'Uses a client secret' "'$ename' signs in to Azure with a service principal's secret - it expires, and it can leak." 'Convert it to workload identity federation (the connection''s Convert button) - no secret to store or rotate.' 'Security' }
            elseif ($scheme -in 'UsernamePassword', 'PublishProfile') { & $find 'Low' $label 'Long-lived credential' "'$ename' stores a $scheme credential." 'Prefer workload identity federation or a managed identity where the service supports it.' 'Security' }
            if ([string]$e['isReady'] -eq 'False') { & $find 'Low' $label 'Not ready' "'$ename' failed to set up or to verify." 'Fix or delete it.' 'Security' }
            if ($perm.Known -and -not $perm.All -and -not $perm.Count -and -not $usedBy) { & $find 'Low' $label 'Unused service connection' 'No pipeline is authorized to use it, and none refers to it.' 'Delete it - an unused credential is still a credential.' 'Security' }
            if ($link) {
                $granting = @($link.Roles | Where-Object { $_.Role -in $grantRoles })
                if ($granting.Count) { & $find 'High' $label 'Can grant Azure access' "Its identity ($($link.DisplayName)) holds $(@($granting | ForEach-Object { "$($_.Role) on $($_.Scope)" }) -join '; ')." 'Deploy with Contributor (or narrower) on the resource groups it needs; keep Owner off pipeline identities.' 'Security' }
                elseif (@($link.Roles | Where-Object { $_.Role -eq 'Contributor' -and $_.Level -in 'Subscription', 'Management group', 'Tenant' }).Count) { & $find 'Medium' $label 'Contributor on a whole subscription' "Its identity ($($link.DisplayName)) is Contributor at subscription scope or above." 'Narrow it to the resource groups the pipeline deploys.' 'Security' }
            }
            $connectionRows.Add([pscustomobject][ordered]@{
                    PSTypeName          = 'AAC.DevOpsServiceConnection'
                    Organization        = $orgName
                    Project             = $projectName
                    Connection          = $ename
                    Type                = $type
                    Scheme              = $scheme
                    OpenToAllPipelines  = $(if ($perm.Known) { $perm.All } else { $null })
                    AuthorizedPipelines = $(if ($perm.Known) { $perm.Count } else { $null })
                    UsedBy              = $usedBy
                    Subscription        = [string](& $member $e 'data.subscriptionName')
                    SubscriptionId      = [string](& $member $e 'data.subscriptionId')
                    AzureScope          = $(if ($scope) { $scope } else { [string](& $member $e 'data.scopeLevel') })
                    AppId               = $appId
                    AzureIdentity       = $(if ($link) { $link.DisplayName } else { '' })
                    AzureRoles          = $(if ($link) { (@($link.Roles | ForEach-Object { "$($_.Role) on $($_.Scope)" }) -join '; ') } else { '' })
                    Ready               = [string]$e['isReady'] -ne 'False'
                    CreatedBy           = [string](& $member $e 'createdBy.displayName')
                    Findings            = $findings.Count - $before
                    Url                 = "$projectUrl/_settings/adminservices?resourceId=$eid"
                })
        }

        # --- Variable groups -------------------------------------------------------------------------------------------
        foreach ($g in @($groups | Sort-Object -Property { [string]$_['name'] })) {
            $gname = [string]$g['name']
            $type = [string]$g['type']
            $vars = & $member $g 'variables'
            $names = @(if ($vars -is [System.Collections.IDictionary]) { $vars.Keys })
            $secrets = @($names | Where-Object { [string](& $member $vars[$_] 'isSecret') -eq 'True' })
            # Names only - a value is never read into a finding or a row.
            $exposed = @(if ($type -ne 'AzureKeyVault') { $names | Where-Object { $_ -match $secretName -and [string](& $member $vars[$_] 'isSecret') -ne 'True' } })
            $perm = & $permissionOf 'variablegroup' ([string]$g['id'])
            $label = "$gname (variable group)"
            $before = $findings.Count
            if ($exposed.Count) { & $find 'High' $label 'Secret-looking variable not marked secret' "$($exposed -join ', ') - anyone who can see the library can read the value." 'Mark them secret (or move them to Key Vault), then rotate them.' 'Security' }
            if ($secrets.Count -and $type -ne 'AzureKeyVault') { & $find 'Medium' $label 'Secrets kept outside Key Vault' "$($secrets.Count) secret(s) stored in Azure DevOps." 'Link the group to an Azure Key Vault, so secrets are rotated and audited in one place.' 'Security' }
            if ($perm.All -and ($secrets.Count -or $type -eq 'AzureKeyVault')) { & $find 'Medium' $label 'Secrets open to every pipeline' "Any pipeline in $projectName can read '$gname'." 'Turn off open access and authorize the pipelines that need it.' 'Security' }
            $groupRows.Add([pscustomobject][ordered]@{
                    PSTypeName         = 'AAC.DevOpsVariableGroup'
                    Organization       = $orgName
                    Project            = $projectName
                    VariableGroup      = $gname
                    Type               = $(if ($type -eq 'AzureKeyVault') { 'Key Vault' } else { 'Azure DevOps' })
                    KeyVault           = [string](& $member $g 'providerData.vault')
                    Variables          = $names.Count
                    Secrets            = $secrets.Count
                    NotMarkedSecret    = $exposed -join ', '
                    OpenToAllPipelines = $(if ($perm.Known) { $perm.All } else { $null })
                    UsedBy             = & $usersOf $usedGroups $gname
                    Findings           = $findings.Count - $before
                    Url                = "$projectUrl/_library?itemType=VariableGroups&view=VariableGroupView&variableGroupId=$($g['id'])"
                })
            foreach ($variableName in $names) {
                $isSecret = $type -eq 'AzureKeyVault' -or [string](& $member $vars[$variableName] 'isSecret') -eq 'True'
                $variableRows.Add([pscustomobject][ordered]@{
                        PSTypeName = 'AAC.DevOpsVariable'; Organization = $orgName; Project = $projectName; Scope = $(if ($type -eq 'AzureKeyVault') { 'Variable group (Key Vault)' } else { 'Variable group' }); Owner = $gname; Variable = [string]$variableName
                        Secret = $isSecret; Settable = $false
                        GitHub = $(if ($type -eq 'AzureKeyVault') { 'Keep in Key Vault: azure/login (OIDC), then read it in the workflow' } elseif ($isSecret) { 'Organization or environment secret' } else { 'Organization or environment variable' })
                    })
            }
        }

        # --- Environments: checks, and deployments (DORA) --------------------------------------------------------------
        # Each deployment: where, how it ended, when, and its lead time - from the run being queued to the deployment
        # finishing (the commit's own time isn't read, so this is the pipeline part of the lead time).
        $projectDeployments = [System.Collections.Generic.List[object]]::new()
        $deploymentOf = {
            param([string] $Where, [bool] $IsProduction, [string] $Outcome, $Finished, $Started)
            $normalised = switch -Regex ($Outcome) { '^(succeeded|succeededWithIssues|partiallySucceeded)$' { 'succeeded' } '^(failed|rejected)$' { 'failed' } default { $Outcome.ToLowerInvariant() } }
            [pscustomobject]@{ Environment = $Where; Production = $IsProduction; Result = $normalised; Finish = $Finished; LeadHours = $(if ($Finished -and $Started -and $Finished -ge $Started) { ($Finished - $Started).TotalHours } else { $null }) }
        }
        foreach ($env in @($environments | Sort-Object -Property { [string]$_['name'] })) {
            $envId = [string]$env['id']
            $envName = [string]$env['name']
            $checkAnswer = $Read.Checks["$projectId|$envId"]
            $checkList = @(& $itemsOf $checkAnswer)
            $checkNames = @($checkList | ForEach-Object { $n = [string](& $member $_ 'settings.displayName'); if (-not $n) { $n = [string](& $member $_ 'type.name') }; $n } | Where-Object { $_ } | Select-Object -Unique)
            $approval = [bool]@($checkList | Where-Object { [string](& $member $_ 'type.name') -match 'Approval' }).Count
            $perm = & $permissionOf 'environment' $envId
            $deployAnswer = $Read.Deployments["$projectId|$envId"]
            $records = @(& $itemsOf $deployAnswer | Where-Object { $q = & $when $_['queueTime']; $q -and $q -ge $since })
            $ok = @($records | Where-Object { [string]$_['result'] -eq 'succeeded' }).Count
            $failed = @($records | Where-Object { [string]$_['result'] -eq 'failed' }).Count
            $lastDeploy = @($records | ForEach-Object { & $when $_['finishTime'] } | Where-Object { $_ } | Sort-Object -Descending) | Select-Object -First 1
            $production = $envName -match $productionName
            foreach ($record in $records) {
                $run = $buildById[[string](& $member $record 'owner.id')]
                $projectDeployments.Add((& $deploymentOf $envName $production ([string]$record['result']) (& $when $record['finishTime']) $(if ($run) { & $when $run['queueTime'] } else { $null })))
            }
            $label = "$envName (environment)"
            $before = $findings.Count
            if ($checkAnswer -and -not $checkAnswer['Error']) {
                if ($production -and -not $approval) { & $find 'High' $label 'Production with no approval' "Deployments to '$envName' need no one's approval." 'Add an Approvals check (and branch control) on the environment.' 'Security' }
                elseif (-not $checkNames.Count) { & $find 'Low' $label 'No checks' "Deployments to '$envName' run with no approval, branch control or other check." 'Add the checks this environment''s stage needs.' 'Security' }
            }
            if ($perm.All) { & $find 'Medium' $label 'Open to every pipeline' "Any pipeline in $projectName can deploy to '$envName'." 'Turn off open access and authorize the pipelines that deploy there.' 'Security' }
            $deployRead = [bool]($deployAnswer -and -not $deployAnswer['Error'])
            $environmentRows.Add([pscustomobject][ordered]@{
                    PSTypeName         = 'AAC.DevOpsEnvironment'
                    Organization       = $orgName
                    Project            = $projectName
                    Environment        = $envName
                    Production         = $production
                    Checks             = $checkNames -join ', '
                    Approval           = $approval
                    OpenToAllPipelines = $(if ($perm.Known) { $perm.All } else { $null })
                    Deployments        = $(if ($deployRead) { $records.Count } else { $null })
                    DeploymentsPerWeek = $(if ($deployRead) { & $round ($records.Count / $weeks) } else { $null })
                    Succeeded          = $ok
                    Failed             = $failed
                    ChangeFailureRate  = $(if ($ok + $failed) { & $round (100.0 * $failed / ($ok + $failed)) } else { $null })
                    LastDeployment     = $lastDeploy
                    UsedBy             = & $usersOf $usedEnvironments $envName
                    Findings           = $findings.Count - $before
                    Url                = "$projectUrl/_environments/$envId"
                })
        }

        # Classic release deployments count too (their lead time starts when the deployment was queued).
        $releaseDeploymentAnswer = & $readOf 'ReleaseDeployments' $projectId
        foreach ($rdep in (& $itemsOf $releaseDeploymentAnswer)) {
            $finished = & $when $rdep['completedOn']
            if (-not $finished -or $finished -lt $since) { continue }
            $stage = [string](& $member $rdep 'releaseEnvironment.name')
            $projectDeployments.Add((& $deploymentOf $stage ($stage -match $productionName) ([string]$rdep['deploymentStatus']) $finished (& $when $rdep['queuedOn'])))
        }

        # --- DORA: the four keys over -MetricDays, from production deployments when there are any ------------------
        $doraSource = @($projectDeployments | Where-Object { $_.Production -and $_.Result -in 'succeeded', 'failed' })
        $doraScope = 'Production'
        if (-not $doraSource.Count) { $doraSource = @($projectDeployments | Where-Object { $_.Result -in 'succeeded', 'failed' }); $doraScope = 'All environments' }
        if ($doraSource.Count) {
            foreach ($dep in $doraSource) { $orgDeployments.Add(([pscustomobject]@{ Project = $projectName; Environment = "$projectName/$($dep.Environment)"; Result = $dep.Result; Finish = $dep.Finish; LeadHours = $dep.LeadHours })) }
            $okDeployments = @($doraSource | Where-Object { $_.Result -eq 'succeeded' })
            $perDay = $okDeployments.Count / $metricDays
            $leadHours = & $median @($okDeployments | ForEach-Object { $_.LeadHours })
            $failureRate = 100.0 * @($doraSource | Where-Object { $_.Result -eq 'failed' }).Count / $doraSource.Count
            $restore = & $median @(& $restoreHours $doraSource)
            $levels = @((& $doraLevel 'Frequency' $perDay), (& $doraLevel 'Lead' $leadHours), (& $doraLevel 'Failure' $failureRate), (& $doraLevel 'Restore' $restore) | Where-Object { $_ })
            $doraRows.Add([pscustomobject][ordered]@{
                    PSTypeName          = 'AAC.DevOpsDora'
                    Organization        = $orgName
                    Project             = $projectName
                    Scope               = $doraScope
                    Deployments         = $doraSource.Count
                    DeploymentsPerWeek  = & $round ($okDeployments.Count / $weeks)
                    Frequency           = & $doraLevel 'Frequency' $perDay
                    LeadTimeHours       = & $round $leadHours
                    LeadTime            = & $doraLevel 'Lead' $leadHours
                    ChangeFailureRate   = & $round $failureRate
                    ChangeFailure       = & $doraLevel 'Failure' $failureRate
                    TimeToRestoreHours  = & $round $restore
                    TimeToRestore       = & $doraLevel 'Restore' $restore
                    # The weakest key sets the overall level: a team is only as fast as its slowest key.
                    Overall             = $(@($levelOrder | Where-Object { $_ -in $levels }) | Select-Object -Last 1)
                })
        }

        # --- Branch policies: every one, in words, with its GitHub equivalent ------------------------------------------
        foreach ($policy in $allPolicies) {
            $policyType = [string](& $member $policy 'type.displayName')
            $policySettings = & $member $policy 'settings'
            foreach ($scopeItem in @(@(& $member $policy 'settings.scope') | Where-Object { $_ })) {
                $scopeRepo = [string]$scopeItem['repositoryId']
                $refName = [string]$scopeItem['refName']
                $policyRows.Add([pscustomobject][ordered]@{
                        PSTypeName   = 'AAC.DevOpsBranchPolicy'
                        Organization = $orgName
                        Project      = $projectName
                        Repository   = $(if (-not $scopeRepo) { 'All repositories' } elseif ($repoById.ContainsKey($scopeRepo)) { $repoById[$scopeRepo].Name } else { $scopeRepo })
                        Branch       = $(if (-not $refName) { 'All branches' } elseif ([string]$scopeItem['matchKind'] -eq 'Prefix') { ($refName -replace '^refs/heads/', '') + '*' } else { $refName -replace '^refs/heads/', '' })
                        Policy       = $policyType
                        Enabled      = [string]$policy['isEnabled'] -eq 'True'
                        Blocking     = [string]$policy['isBlocking'] -eq 'True'
                        Settings     = [string](& $policySummary $policyType $policySettings $pipelineNames)
                        GitHub       = $(if ($policyGitHub.ContainsKey($policyType)) { $policyGitHub[$policyType] } else { 'Check by hand' })
                    })
            }
        }

        # --- Repositories ----------------------------------------------------------------------------------------------
        foreach ($rid in @($repoById.Keys | Sort-Object -Property { $repoById[$_].Name })) {
            $r = $repoById[$rid]
            if ($r.Disabled -and -not $IncludeDisabledRepository) { $disabledRepositories++; continue }
            $days = if ($r.Push) { & $daysSince $r.Push.Date } else { $null }
            $label = "$($r.Name) (repository)"
            $before = $findings.Count

            # --- Branches: role, last commit, ahead/behind the default, policies - and the strategy they add up to -----
            $branchesHere = [System.Collections.Generic.List[object]]::new()
            foreach ($bs in $r.BranchStats) {
                $branchName = [string]$bs['name']
                $commitDate = & $when (& $member $bs 'commit.committer.date')
                if (-not $commitDate) { $commitDate = & $when (& $member $bs 'commit.author.date') }
                $branchDays = & $daysSince $commitDate
                $isDefault = $branchName -eq $r.DefaultBranch
                $ref = "refs/heads/$branchName"
                $onBranch = @($allPolicies | Where-Object { [string]$_['isEnabled'] -eq 'True' } | Where-Object {
                        @(@(& $member $_ 'settings.scope') | Where-Object { $_ -and (-not $_['repositoryId'] -or [string]$_['repositoryId'] -eq $rid) -and (-not $_['refName'] -or ([string]$_['matchKind'] -ne 'Prefix' -and [string]$_['refName'] -eq $ref) -or ([string]$_['matchKind'] -eq 'Prefix' -and $ref.StartsWith([string]$_['refName']))) }).Count
                    } | ForEach-Object { [string](& $member $_ 'type.displayName') } | Select-Object -Unique)
                $branchRow = [pscustomobject][ordered]@{
                    PSTypeName      = 'AAC.DevOpsBranch'
                    Organization    = $orgName
                    Project         = $projectName
                    Repository      = $r.Name
                    Branch          = $branchName
                    Kind            = & $branchKind $branchName $r.DefaultBranch
                    IsDefault       = $isDefault
                    LastCommit      = $commitDate
                    Author          = [string](& $member $bs 'commit.author.name')
                    DaysSinceCommit = $branchDays
                    Ahead           = $(if ($isDefault) { 0 } else { [int]$bs['aheadCount'] })
                    Behind          = $(if ($isDefault) { 0 } else { [int]$bs['behindCount'] })
                    Stale           = -not $isDefault -and $null -ne $branchDays -and $branchDays -gt $StaleBranchDays
                    Policies        = $onBranch -join ', '
                }
                $branchesHere.Add($branchRow)
                $branchRows.Add($branchRow)
            }
            $others = @($branchesHere | Where-Object { -not $_.IsDefault })
            $staleBranches = @($others | Where-Object { $_.Stale }).Count
            $kinds = @($branchesHere | ForEach-Object { $_.Kind })
            $strategy = if (-not $r.BranchesRead) { 'Not read' }
            elseif ($branchesHere.Count -le 1) { 'Single branch' }
            elseif ('Develop' -in $kinds -and ('Release' -in $kinds -or 'Hotfix' -in $kinds)) { 'GitFlow' }
            elseif ('Develop' -in $kinds) { 'GitFlow-like (a develop branch)' }
            elseif ('Release' -in $kinds) { 'Trunk-based with release branches' }
            elseif ($others.Count -and $staleBranches / $others.Count -ge 0.5) { 'Feature branching (long-lived branches)' }
            else { 'Trunk-based / GitHub flow (short-lived branches)' }
            $releaseUnprotected = @($branchesHere | Where-Object { $_.Kind -eq 'Release' -and -not $_.Stale -and -not $_.Policies })
            if (-not $r.Disabled) {
                if ($staleBranches -ge 20) { & $find 'Low' $label 'Many stale branches' "$staleBranches branches with no commit in $StaleBranchDays days." 'Delete merged and abandoned branches before the move - they are migrated (and kept) otherwise.' 'Repository' }
                if ($releaseUnprotected.Count) { & $find 'Low' $label 'Release branches without a policy' "$(@($releaseUnprotected | Select-Object -First 5 | ForEach-Object { $_.Branch }) -join ', ')$(if ($releaseUnprotected.Count -gt 5) { ', ...' }) take changes with no review." 'Add a branch policy on release/* (reviewers and build validation), as on the default branch.' 'Repository' }
                if ($null -ne $r.SizeMB -and $r.SizeMB -ge 1024) { & $find 'Medium' $label 'Large repository' "$($r.SizeMB) MB - GitHub recommends repositories under 1 GB (and blocks files over 100 MB)." 'Clean the history (git filter-repo) or move large files to Git LFS before migrating.' 'Migration' }
                if ($r.Lfs) { & $find 'Info' $label 'Uses Git LFS' 'Its .gitattributes stores files in Git LFS.' 'LFS objects aren''t moved by GitHub Enterprise Importer: push them separately (git lfs push --all) and check the LFS storage quota.' 'Migration' }
                if ($r.DefaultBranch -eq 'master') { & $find 'Info' $label 'Default branch is master' 'GitHub''s default for new repositories is main.' 'Optional: rename it to main during the move (pipelines and policies that name master must follow).' 'Migration' }
            }
            if (-not $r.Disabled) {
                if ($null -ne $days -and $days -gt $InactiveDays) { & $find 'Low' $label "No push in $InactiveDays days" "Last push $days days ago." 'Archive (disable) it if it is no longer worked on.' 'Repository' }
                if (-not $r.Pipelines -and $r.Push) { & $find 'Info' $label 'Repository with no pipeline' 'No build pipeline builds this repository.' 'Add a pipeline - even a lint and scan one - or archive the repository.' 'Repository' }
                if ($r.Push -and $r.Reviewers -eq 0) { & $find 'Medium' $label 'No required reviewers' "Changes reach $($r.DefaultBranch) without a review." 'Add a "Minimum number of reviewers" branch policy on the default branch (2, without counting your own vote).' 'Repository' }
                if ($r.BuildValidation -eq $false -and $r.Pipelines) { & $find 'Low' $label 'No build validation' "Pull requests to $($r.DefaultBranch) aren't built before they merge." 'Add a Build validation policy with the repository''s pipeline.' 'Repository' }
                if ($r.AdvancedSecurity -eq 'Off') { & $find 'Low' $label 'Advanced Security off' 'No code, dependency or secret scanning on the repository.' 'Turn on GitHub Advanced Security for Azure DevOps (Secret Protection and Code Security).' 'Repository' }
                if ($r.SecretAlerts) { & $find 'High' $label 'Exposed secrets' "$($r.SecretAlerts) active secret alert(s)." 'Revoke and rotate each secret, then close its alert.' 'Repository' }
                if ($r.CriticalAlerts + $r.HighAlerts) { & $find 'Medium' $label 'Critical or high security alerts' "$($r.CriticalAlerts) critical and $($r.HighAlerts) high active alert(s)." 'Fix them, the critical ones first.' 'Repository' }
            }
            $repositoryRows.Add([pscustomobject][ordered]@{
                    PSTypeName       = 'AAC.DevOpsRepository'
                    Organization     = $orgName
                    Project          = $projectName
                    Repository       = $r.Name
                    DefaultBranch    = $r.DefaultBranch
                    Disabled         = $r.Disabled
                    Pipelines        = $r.Pipelines
                    LastPush         = $(if ($r.Push) { $r.Push.Date } else { $null })
                    LastPushBy       = $(if ($r.Push) { $r.Push.By } else { '' })
                    DaysSincePush    = $days
                    Reviewers        = $r.Reviewers
                    BuildValidation  = $r.BuildValidation
                    Policies         = $r.Policies
                    AdvancedSecurity = $r.AdvancedSecurity
                    CriticalAlerts   = $r.CriticalAlerts
                    HighAlerts       = $r.HighAlerts
                    MediumAlerts     = $r.MediumAlerts
                    LowAlerts        = $r.LowAlerts
                    CodeAlerts       = $r.CodeAlerts
                    DependencyAlerts = $r.DependencyAlerts
                    SecretAlerts     = $r.SecretAlerts
                    SizeMB           = $r.SizeMB
                    Branches         = $(if ($r.BranchesRead) { $branchesHere.Count } else { $null })
                    StaleBranches    = $(if ($r.BranchesRead) { $staleBranches } else { $null })
                    Strategy         = $strategy
                    Tags             = $r.Tags
                    OpenPullRequests = $r.OpenPullRequests
                    Lfs              = $r.Lfs
                    PushProtection   = $r.PushProtection
                    AdvsecSettings   = $r.AdvsecSettings
                    Findings         = $findings.Count - $before
                    Url              = $r.Url
                })
        }

        # --- People: who to contact - the Project Administrators, the team admins, the team members -----------------
        # One entry per person (a generic Dictionary: names from the directory can't shadow its own members).
        $people = [System.Collections.Generic.Dictionary[string, hashtable]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $personOf = {
            param([string] $Key, [string] $Name, [string] $Email, [string] $Kind)
            if (-not $people.ContainsKey($Key)) { $people[$Key] = @{ Name = $Name; Email = $Email; Kind = $Kind; Roles = [System.Collections.Generic.List[string]]::new(); Teams = [System.Collections.Generic.List[string]]::new(); Rank = 9; Admin = $false; TeamAdmin = $false } }
            $people[$Key]
        }
        $addRole = { param([hashtable] $Who, [string] $Role, [int] $Rank) if (-not $Who.Roles.Contains($Role)) { $Who.Roles.Add($Role) }; if ($Rank -lt $Who.Rank) { $Who.Rank = $Rank } }
        foreach ($answer in @(if ($Read.Contains('AdminMembers') -and $Read.AdminMembers.ContainsKey($projectId)) { $Read.AdminMembers[$projectId] })) {
            if (-not $answer) { continue }
            if ($answer['Error'] -and -not $membersError) { $membersError = [string]$answer['Error'] }
            foreach ($identity in (& $itemsOf $answer)) {
                $name = [string]$(if ($identity['customDisplayName']) { $identity['customDisplayName'] } else { $identity['providerDisplayName'] })
                $email = [string](& $member $identity 'properties.Mail.$value')
                if (-not $email) { $email = [string](& $member $identity 'properties.Account.$value') }
                $who = & $personOf $(if ($email) { $email } else { [string]$identity['id'] }) $name $email $(if ([string]$identity['isContainer'] -eq 'True') { 'Group' } else { 'User' })
                & $addRole $who 'Project Administrator' 0
                $who.Admin = $true
            }
        }
        $teamAnswer = if ($Read.Contains('Teams')) { $Read.Teams[$projectId] } else { $null }
        if ($teamAnswer -and $teamAnswer['Error'] -and -not $membersError) { $membersError = [string]$teamAnswer['Error'] }
        $adminAnswer = if ($Read.Contains('Admins')) { $Read.Admins[$projectId] } else { $null }
        if ($adminAnswer -and $adminAnswer['Error'] -and -not $membersError) { $membersError = [string]$adminAnswer['Error'] }
        $teamList = @(& $itemsOf $teamAnswer)
        foreach ($team in $teamList) {
            $teamName = [string]$team['name']
            $answer = if ($Read.TeamMembers.ContainsKey("$projectId|$($team['id'])")) { $Read.TeamMembers["$projectId|$($team['id'])"] } else { $null }
            foreach ($m in (& $itemsOf $answer)) {
                $identity = $m['identity']
                if (-not $identity) { continue }
                $email = [string]$identity['uniqueName']
                $who = & $personOf $(if ($email) { $email } else { [string]$identity['id'] }) ([string]$identity['displayName']) $email $(if ([string]$identity['isContainer'] -eq 'True') { 'Group' } else { 'User' })
                $isAdmin = [string]$m['isTeamAdmin'] -eq 'True'
                & $addRole $who $(if ($isAdmin) { 'Team admin' } else { 'Team member' }) $(if ($isAdmin) { 1 } else { 2 })
                if ($isAdmin) { $who.TeamAdmin = $true }
                $label = if ($isAdmin) { "$teamName (admin)" } else { $teamName }
                if (-not $who.Teams.Contains($label)) { $who.Teams.Add($label) }
            }
        }
        $sortedPeople = @($people.Values | Sort-Object -Property @{ Expression = { $_.Rank } }, @{ Expression = { $_.Kind -ne 'User' } }, @{ Expression = { $_.Name } })
        foreach ($who in $sortedPeople) {
            $memberRows.Add([pscustomobject][ordered]@{
                    PSTypeName = 'AAC.DevOpsMember'; Organization = $orgName; Project = $projectName; Name = $who.Name; Email = $who.Email; Kind = $who.Kind
                    Roles = $who.Roles -join '; '; Teams = $who.Teams -join ', '; ProjectAdministrator = $who.Admin; TeamAdmin = $who.TeamAdmin
                })
        }
        # The project's first contacts: its administrators (people before groups), then its team admins.
        $contacts = @($sortedPeople | Where-Object { $_.Admin -or $_.TeamAdmin } | Select-Object -First 6 | ForEach-Object { if ($_.Kind -eq 'User' -and $_.Email -and $_.Email -ne $_.Name) { "$($_.Name) <$($_.Email)>" } else { $_.Name } })
        $contactsMore = @($sortedPeople | Where-Object { $_.Admin -or $_.TeamAdmin }).Count - $contacts.Count

        # --- Artifacts, test plans, wikis, service hooks, Advanced Security defaults: the rest of the move to GitHub --
        $feedsAnswer = & $readOf 'Feeds' $projectId
        $projectFeeds = @(foreach ($feed in (& $itemsOf $feedsAnswer)) {
                $row = & $feedRow $feed (& $readOf 'Packages' "$projectId/$($feed['id'])") $projectName "$projectUrl/_artifacts/feed/$([System.Uri]::EscapeDataString([string]$feed['name']))"
                $feedRows.Add($row)
                $row
            })
        $testPlansAnswer = & $readOf 'TestPlans' $projectId
        $projectPlans = @(foreach ($plan in (& $itemsOf $testPlansAnswer)) {
                $row = [pscustomobject][ordered]@{
                    PSTypeName = 'AAC.DevOpsTestPlan'; Organization = $orgName; Project = $projectName; TestPlan = [string]$plan['name']; Id = [int]$plan['id']
                    State = [string]$plan['state']; AreaPath = [string]$plan['areaPath']; Iteration = [string]$plan['iteration']; Owner = [string](& $member $plan 'owner.displayName')
                    Updated = & $when $plan['updatedDate']
                    GitHub = 'No GitHub equivalent: keep Azure Test Plans (Basic + Test Plans licence), or move to a test management tool'
                    Url = "$projectUrl/_testPlans/define?planId=$($plan['id'])"
                }
                $testPlanRows.Add($row)
                $row
            })
        $wikiList = @(& $itemsOf (& $readOf 'Wikis' $projectId))
        $projectHooks = @($hookList | Where-Object { [string](& $member $_ 'publisherInputs.projectId') -eq $projectId })
        $advsecProjectAnswer = & $readOf 'AdvancedSecurityProject' $projectId
        $advsecProjectBody = if ($advsecProjectAnswer -and -not $advsecProjectAnswer['Error']) { $advsecProjectAnswer['Body'] } else { $null }
        $unsupportedFeeds = @($projectFeeds | Where-Object { $_.Unsupported })
        if ($unsupportedFeeds.Count) { & $find 'Medium' "$projectName (artifacts)" 'Packages GitHub Packages can''t hold' "$(@($unsupportedFeeds | ForEach-Object { "$($_.Feed): $($_.GitHubPackages -replace '^Not for ', '')" }) -join '; ')." 'Keep those feeds in Azure Artifacts, or move them to another registry (JFrog, a cloud registry), before switching off Azure DevOps.' 'Migration' }
        if ($projectPlans.Count) { & $find 'Info' "$projectName (test plans)" 'Test plans to keep or move' "$($projectPlans.Count) test plan(s) - GitHub has no test case management." 'Keep Azure Test Plans running beside GitHub, or export the plans to a test management tool.' 'Migration' }

        # --- Migration summary: what moves easily, what needs work, and roughly how much ----------------------------
        $projectRepos = @($repositoryRows | Where-Object { $_.Project -eq $projectName })
        $classicBuilds = @($mine | Where-Object { $_.Kind -eq 'Classic build' }).Count
        $classicReleases = @($mine | Where-Object { $_.Kind -eq 'Classic release' }).Count
        $marketplaceTasks = @($mine | ForEach-Object { $_.ExtensionTasks -split ', ' } | Where-Object { $_ } | Select-Object -Unique)
        $secretCount = @($variableRows | Where-Object { $_.Project -eq $projectName -and $_.Secret }).Count
        $approvalEnvironments = @($environmentRows | Where-Object { $_.Project -eq $projectName -and $_.Approval }).Count
        $secretConnections = @($connectionRows | Where-Object { $_.Project -eq $projectName -and $_.Scheme -in 'ServicePrincipal', 'UsernamePassword', 'PublishProfile', 'Token' }).Count
        $largeRepos = @($projectRepos | Where-Object { $null -ne $_.SizeMB -and $_.SizeMB -ge 1024 }).Count
        $lfsRepos = @($projectRepos | Where-Object { $_.Lfs }).Count
        $effort = 2 * $classicBuilds + 3 * $classicReleases + 2 * $marketplaceTasks.Count + $(if ($projectPlans.Count) { 3 } else { 0 }) + 3 * $unsupportedFeeds.Count + 3 * $largeRepos + $lfsRepos + [int][Math]::Ceiling($secretCount / 10) + $approvalEnvironments + $secretConnections + $(if ($wikiList.Count) { 1 } else { 0 })
        $notes = @(
            $(if ($classicBuilds + $classicReleases) { "$($classicBuilds + $classicReleases) classic pipeline(s) to rewrite as workflows (GitHub Actions Importer helps)" })
            $(if ($marketplaceTasks.Count) { "marketplace tasks to replace with actions: $(@($marketplaceTasks | Select-Object -First 5) -join ', ')" })
            $(if ($secretCount) { "$secretCount secret variable(s) to re-create - values can't be exported" })
            $(if ($secretConnections) { "$secretConnections service connection(s) with stored credentials - use OIDC (azure/login) instead" })
            $(if ($approvalEnvironments) { "$approvalEnvironments environment(s) with approvals - set up protection rules on GitHub environments" })
            $(if ($unsupportedFeeds.Count) { 'feeds with packages GitHub Packages can''t hold' })
            $(if ($projectPlans.Count) { 'test plans have no GitHub equivalent' })
            $(if ($largeRepos + $lfsRepos) { 'large or LFS repositories need extra steps' })
        ) | Where-Object { $_ }
        $migrationRows.Add([pscustomobject][ordered]@{
                PSTypeName           = 'AAC.DevOpsMigration'
                Organization         = $orgName
                Project              = $projectName
                Repositories         = $projectRepos.Count
                RepositoriesMB       = & $round (& $sumOf $projectRepos 'SizeMB')
                LfsRepositories      = $lfsRepos
                YamlPipelines        = @($mine | Where-Object { $_.Kind -eq 'YAML' }).Count
                ClassicPipelines     = $classicBuilds + $classicReleases
                MarketplaceTasks     = $marketplaceTasks.Count
                Variables            = @($variableRows | Where-Object { $_.Project -eq $projectName }).Count
                SecretVariables      = $secretCount
                ServiceConnections   = $endpoints.Count
                Environments         = $environments.Count
                Feeds                = $projectFeeds.Count
                Packages             = & $sumOf $projectFeeds 'Packages'
                TestPlans            = $(if ($testPlansAnswer -and -not $testPlansAnswer['Error']) { $projectPlans.Count } else { $null })
                Wikis                = $wikiList.Count
                ServiceHooks         = $projectHooks.Count
                OpenPullRequests     = & $sumOf $projectRepos 'OpenPullRequests'
                AdvancedSecurity     = $(if ($advsecProjectBody) { & $settingsText $advsecProjectBody } else { '' })
                Effort               = $effort
                Complexity           = $(if ($effort -lt 5) { 'Low' } elseif ($effort -lt 15) { 'Medium' } else { 'High' })
                Notes                = $notes -join '; '
            })

        $projectPushes = @($repoById.Values | Where-Object { $_.Push -and $_.Push.Date } | ForEach-Object { $_.Push.Date } | Sort-Object -Descending)
        $projectRows.Add([pscustomobject][ordered]@{
                PSTypeName         = 'AAC.DevOpsProject'
                Organization       = $orgName
                Project            = $projectName
                Pipelines          = $mine.Count
                Yaml               = @($mine | Where-Object { $_.Kind -eq 'YAML' }).Count
                ClassicBuild       = @($mine | Where-Object { $_.Kind -eq 'Classic build' }).Count
                ClassicRelease     = @($mine | Where-Object { $_.Kind -eq 'Classic release' }).Count
                WithScanning       = @($mine | Where-Object { $_.Security }).Count
                Repositories       = @($repoById.Values | Where-Object { $IncludeDisabledRepository -or -not $_.Disabled }).Count
                ServiceConnections = $endpoints.Count
                VariableGroups     = $groups.Count
                Environments       = $environments.Count
                LastRun            = $($mine | Where-Object { $_.LastRun } | ForEach-Object { $_.LastRun } | Sort-Object -Descending | Select-Object -First 1)
                LastPush           = $(if ($projectPushes.Count) { $projectPushes[0] } else { $null })
                Visibility         = [string]$p['visibility']
                State              = [string]$p['state']
                LastUpdate         = & $when $p['lastUpdateTime']
                Findings           = $findings.Count - $projectFindingsFrom
                Administrators     = @($sortedPeople | Where-Object { $_.Admin }).Count
                Teams              = $teamList.Count
                Members            = $sortedPeople.Count
                Contacts           = ($contacts -join '; ') + $(if ($contactsMore -gt 0) { "; and $contactsMore more" } else { '' })
                Id                 = $projectId
                Url                = $projectUrl
            })
    }

    # --- The organization's own: feeds outside a project, agent pools, extensions --------------------------------------
    foreach ($feed in (& $itemsOf $(if ($Read.Contains('OrganizationFeeds')) { $Read.OrganizationFeeds }))) {
        $feedRows.Add((& $feedRow $feed (& $readOf 'Packages' "org/$($feed['id'])") '(organization)' "$org/_artifacts/feed/$([System.Uri]::EscapeDataString([string]$feed['name']))"))
    }
    $poolRows = @(foreach ($pool in (& $itemsOf $(if ($Read.Contains('Pools')) { $Read.Pools }))) {
            $hosted = [string]$pool['isHosted'] -eq 'True'
            $agentAnswer = & $readOf 'Agents' ([string]$pool['id'])
            $agentList = @(& $itemsOf $agentAnswer)
            $users = $poolUse[([string]$pool['name']).ToLowerInvariant()]
            [pscustomobject][ordered]@{
                PSTypeName = 'AAC.DevOpsAgentPool'; Organization = $orgName; Pool = [string]$pool['name']; Hosted = $hosted; Type = [string]$pool['poolType']
                Agents = $(if ($hosted) { $null } elseif ($agentAnswer -and -not $agentAnswer['Error']) { $agentList.Count } else { $null })
                Online = $(if ($hosted -or -not $agentList.Count) { $null } else { @($agentList | Where-Object { [string]$_['status'] -eq 'online' }).Count })
                Pipelines = $(if ($users) { $users.Count } else { 0 })
                GitHub = $(if ($hosted) { 'GitHub-hosted runners' } elseif ($agentList.Count) { 'Self-hosted runners (or larger GitHub-hosted runners, with private networking if they reach private resources)' } else { 'Nothing to move' })
            }
        })
    $extensionRows = @(@(foreach ($ext in (& $itemsOf $(if ($Read.Contains('Extensions')) { $Read.Extensions }))) {
            # Built-in (Microsoft's, installed with every organization) extensions have nothing to move.
            if ([string]$ext['flags'] -match 'builtIn|system' -or [string]$ext['publisherId'] -eq 'ms') { continue }
            $extKey = "$($ext['publisherId']).$($ext['extensionId'])"
            $users = $extensionUse[$extKey.ToLowerInvariant()]
            [pscustomobject][ordered]@{
                PSTypeName = 'AAC.DevOpsExtension'; Organization = $orgName; Extension = [string]$ext['extensionName']; Publisher = [string]$ext['publisherName']; Id = $extKey; Version = [string]$ext['version']
                Disabled = [string](& $member $ext 'installState.flags') -match 'disabled'
                Pipelines = $(if ($users) { $users.Count } else { 0 })
                UsedBy = $(if ($users) { (@($users) | Sort-Object | Select-Object -First 5) -join ', ' } else { '' })
                GitHub = $(if ($users) { 'Find a GitHub Action (or a script) for each of its tasks' } else { 'Not used by a pipeline - nothing to move' })
            }
        }) | Sort-Object -Property @{ Expression = { $_.Pipelines }; Descending = $true }, Extension)
    # Where each Azure DevOps thing lands on GitHub, with how many there are.
    $mapRow = { param([string] $Thing, $Count, [string] $GitHub, [string] $Tool, [string] $Note) [pscustomobject][ordered]@{ PSTypeName = 'AAC.DevOpsMigrationMap'; Organization = $orgName; AzureDevOps = $Thing; Count = $Count; GitHub = $GitHub; HowToMove = $Tool; Note = $Note } }
    $mapRows = @(
        & $mapRow 'Git repositories' $repositoryRows.Count 'Repositories' 'GitHub Enterprise Importer (gh ado2gh)' 'History, branches, tags; pull requests and their comments come too.'
        & $mapRow 'Branch policies' $policyRows.Count 'Rulesets (and CODEOWNERS)' 'gh ado2gh migrates some; recreate the rest' 'See the Branch policies tab for each one''s GitHub equivalent.'
        & $mapRow 'YAML pipelines' @($pipelines | Where-Object { $_.Kind -eq 'YAML' }).Count 'GitHub Actions workflows' 'GitHub Actions Importer (gh actions-importer)' 'Templates become reusable workflows or composite actions.'
        & $mapRow 'Classic pipelines' @($pipelines | Where-Object { $_.Kind -ne 'YAML' }).Count 'GitHub Actions workflows' 'GitHub Actions Importer (it reads classic too)' 'Classic releases: stages become jobs with environments.'
        & $mapRow 'Variables' @($variableRows | Where-Object { -not $_.Secret }).Count 'Variables (repository, environment, organization)' 'Re-create (gh variable set)' ''
        & $mapRow 'Secret variables' @($variableRows | Where-Object { $_.Secret }).Count 'Secrets (repository, environment, organization)' 'Re-create (gh secret set) - values can''t be exported' 'Key Vault groups: read the vault from the workflow instead.'
        & $mapRow 'Service connections' $connectionRows.Count 'OIDC federated credentials, secrets' 'Re-create' 'Azure: a federated credential for the repository plus azure/login.'
        & $mapRow 'Environments' $environmentRows.Count 'Environments with protection rules' 'Re-create' 'Approvals become required reviewers; branch control becomes deployment branch rules.'
        & $mapRow 'Agent pools' @($poolRows | Where-Object { -not $_.Hosted }).Count 'Self-hosted runners (runner groups)' 'Install the runner' ''
        & $mapRow 'Artifacts feeds' $feedRows.Count 'GitHub Packages (npm, NuGet, Maven, containers)' 'Re-publish packages' 'PyPI, Universal Packages and Cargo have no GitHub Packages registry.'
        & $mapRow 'Marketplace extensions' @($extensionRows | Where-Object { $_.Pipelines }).Count 'GitHub Actions (Marketplace)' 'Find an equivalent' ''
        & $mapRow 'Test plans' $testPlanRows.Count 'None' 'Keep Azure Test Plans, or a test management tool' ''
        & $mapRow 'Advanced Security' @($repositoryRows | Where-Object { $_.AdvancedSecurity -eq 'On' }).Count 'GitHub Advanced Security (Secret Protection, Code Security)' 'Turn it on per repository (or by policy)' 'Alerts are not moved: they are found again on the first scans.'
        & $mapRow 'Boards and wikis' $null 'Azure Boards (with the GitHub app) or Issues and Projects; wikis' 'Keep Boards linked (AB#123), or migrate with a tool' 'Not counted by this report.'
    )
    # The organization's DORA: every project's deployments together.
    $orgDora = @{}
    if ($orgDeployments.Count) {
        $okAll = @($orgDeployments | Where-Object { $_.Result -eq 'succeeded' })
        $perDayAll = $okAll.Count / $metricDays
        $leadAll = & $median @($okAll | ForEach-Object { $_.LeadHours })
        $failureAll = 100.0 * @($orgDeployments | Where-Object { $_.Result -eq 'failed' }).Count / $orgDeployments.Count
        $restoreAll = & $median @(& $restoreHours $orgDeployments.ToArray())
        $levelsAll = @((& $doraLevel 'Frequency' $perDayAll), (& $doraLevel 'Lead' $leadAll), (& $doraLevel 'Failure' $failureAll), (& $doraLevel 'Restore' $restoreAll) | Where-Object { $_ })
        $orgDora = @{
            DeploymentsPerWeek = & $round ($okAll.Count / $weeks); Frequency = & $doraLevel 'Frequency' $perDayAll
            LeadTimeHours = & $round $leadAll; LeadTime = & $doraLevel 'Lead' $leadAll
            ChangeFailureRate = & $round $failureAll; ChangeFailure = & $doraLevel 'Failure' $failureAll
            TimeToRestoreHours = & $round $restoreAll; TimeToRestore = & $doraLevel 'Restore' $restoreAll
            Overall = $(@($levelOrder | Where-Object { $_ -in $levelsAll }) | Select-Object -Last 1)
        }
    }

    $rank = @{ High = 0; Medium = 1; Low = 2; Info = 3 }
    $toolOrder = @($categories) + 'Tooling'
    $tools = @($toolUse.Values | ForEach-Object {
            [pscustomobject][ordered]@{
                PSTypeName = 'AAC.DevOpsToolUsage'; Organization = $orgName; Category = $_.Category; Tool = $_.Tool; Purpose = $_.Purpose; Pipelines = $_.Pipelines; Projects = $_.Projects.Count
                Versions = (@($_.Versions) | Sort-Object) -join ', '; Found = (@($_.Found) | Sort-Object) -join ', '; Evidence = $_.Evidence; ProjectNames = (@($_.Projects) | Sort-Object) -join ', '
            }
        } | Sort-Object -Property @{ Expression = { $i = [array]::IndexOf($toolOrder, $_.Category); if ($i -lt 0) { 99 } else { $i } } }, @{ Expression = { $_.Pipelines }; Descending = $true }, Tool)
    # The Unrecognised tab: commands no rule knows (most-run first), then what couldn't be read.
    # .PSBase.Keys: the keys are commands from scripts, and a command named 'keys' (or 'values',
    # 'count') would answer $unknownUse.Keys itself - a hashtable's keys come before its properties.
    $unknownRows = @($unknownUse.PSBase.Keys | ForEach-Object { $u = $unknownUse[$_]; [pscustomobject][ordered]@{ PSTypeName = 'AAC.DevOpsUnrecognised'; Organization = $orgName; Kind = 'Command'; Name = $_; Pipelines = $u.Pipelines.Count; Lines = $u.Lines; Example = $u.Example; Detail = 'Run in a script, but no catalogue rule knows it - add one with -ToolRule or -ToolRulePath if it matters.' } } | Sort-Object -Property @{ Expression = { $_.Pipelines }; Descending = $true }, @{ Expression = { $_.Lines }; Descending = $true }, Name | Select-Object -First 300)
    # The same unreadable file for many pipelines is one row.
    $unread = @($unreadRows | Group-Object -Property Kind, Name | ForEach-Object { $first = $_.Group[0]; [pscustomobject][ordered]@{ PSTypeName = 'AAC.DevOpsUnrecognised'; Organization = $orgName; Kind = $first.Kind; Name = $first.Name; Pipelines = $_.Count; Lines = $null; Example = $first.Example; Detail = $first.Detail } } | Sort-Object -Property Kind, Name)
    $yamlPipelines = @($pipelines | Where-Object { $_.Kind -eq 'YAML' })
    # Judged: the pipelines whose steps were read - YAML that could be read, and classic builds with tasks.
    $judged = @($pipelines | Where-Object { $_.Yaml -eq 'Read' -or ($_.Kind -eq 'Classic build' -and $_.Tasks) })
    @{
        Projects           = $projectRows.ToArray()
        Pipelines          = $pipelines.ToArray()
        Tasks              = $taskRows.ToArray()
        Repositories       = $repositoryRows.ToArray()
        ServiceConnections = $connectionRows.ToArray()
        VariableGroups     = $groupRows.ToArray()
        Environments       = $environmentRows.ToArray()
        Members            = $memberRows.ToArray()
        MembersError       = $membersError
        Branches           = $branchRows.ToArray()
        BranchPolicies     = $policyRows.ToArray()
        Variables          = $variableRows.ToArray()
        Dora               = $doraRows.ToArray()
        Feeds              = $feedRows.ToArray()
        TestPlans          = $testPlanRows.ToArray()
        AgentPools         = $poolRows
        Extensions         = $extensionRows
        Migration          = $migrationRows.ToArray()
        MigrationMap       = $mapRows
        Tools              = $tools
        Evidence           = $evidenceRows.ToArray()
        Coverage           = $coverageRows.ToArray()
        Unrecognised       = @(@($unknownRows) + @($unread))
        Findings           = @($findings | Sort-Object -Property @{ Expression = { $rank[$_.Severity] } }, Project, Item, Finding)
        Stats              = @{
            Projects          = $projectRows.Count
            Pipelines         = $pipelines.Count
            Yaml              = $yamlPipelines.Count
            ClassicBuild      = @($pipelines | Where-Object { $_.Kind -eq 'Classic build' }).Count
            ClassicRelease    = @($pipelines | Where-Object { $_.Kind -eq 'Classic release' }).Count
            YamlRead          = $judged.Count
            WithScanning      = @($judged | Where-Object { $_.Security }).Count
            NeverRun          = @($pipelines | Where-Object { $_.LastResult -in 'Never run', 'Never released' }).Count
            Stale             = @($pipelines | Where-Object { $null -ne $_.DaysSinceRun -and $_.DaysSinceRun -gt $StaleDays }).Count
            Failed            = @($pipelines | Where-Object { $_.LastResult -eq 'failed' }).Count
            Repositories      = $repositoryRows.Count
            OpenResources     = @(@($connectionRows) + @($groupRows) + @($environmentRows) | Where-Object { $_.OpenToAllPipelines }).Count
            Deployments       = & $sumOf $environmentRows 'Deployments'
            FailedDeployments = & $sumOf $environmentRows 'Failed'
            High              = @($findings | Where-Object { $_.Severity -eq 'High' }).Count
            Members           = $memberRows.Count
            Unrecognised      = @($unknownRows).Count
            NotRead           = @($unread).Count
            DisabledRepositories = $disabledRepositories
            DisabledPipelines = $disabledPipelines
            Branches          = $branchRows.Count
            StaleBranches     = @($branchRows | Where-Object { $_.Stale }).Count
            BranchPolicies    = $policyRows.Count
            SecretVariables   = @($variableRows | Where-Object { $_.Secret }).Count
            Packages          = & $sumOf $feedRows 'Packages'
            TestPlans         = $testPlanRows.Count
            MigrationEffort   = & $sumOf $migrationRows 'Effort'
            HighComplexity    = @($migrationRows | Where-Object { $_.Complexity -eq 'High' }).Count
            Dora              = $orgDora
        }
    }
}
