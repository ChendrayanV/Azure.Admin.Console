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
        $info = @{ Name = [string]$t['name']; Friendly = [string]$t['friendlyName']; Description = [string]$t['description']; Category = [string]$t['category']; Deprecated = [string]$t['deprecated'] -eq 'True'; Major = [int](& $member $t 'version.major') }
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
    $toolUse = @{}
    $evidenceRows = [System.Collections.Generic.List[object]]::new()
    $coverageRows = [System.Collections.Generic.List[object]]::new()
    $unreadRows = [System.Collections.Generic.List[object]]::new()
    $unknownUse = @{}

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
            $advsecState = if (-not $advsec -or -not $advsec.Enablement -or $advsec.Enablement['Error']) { 'Unknown' } elseif ([string](& $member $advsec.Enablement['Body'] 'advSecEnabled') -eq 'True') { 'On' } else { 'Off' }
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
        foreach ($b in (& $itemsOf $buildAnswer)) {
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
                    Lint = ''; Build = ''; Test = ''; Security = ''; Deploy = ''; Publish = ''; GitOps = ''; Tasks = 0; Templates = ''; Images = ''; Containers = ''; Connections = ''; VariableGroups = ''; Environments = ''; AzureTargets = ''
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
        }

        # --- Environments: checks, and deployments (DORA) --------------------------------------------------------------
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
            $production = $envName -match '(^|[-_. ])(prod|production|prd|live)([-_. ]|$)'
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

        # --- Repositories ----------------------------------------------------------------------------------------------
        foreach ($rid in @($repoById.Keys | Sort-Object -Property { $repoById[$_].Name })) {
            $r = $repoById[$rid]
            if ($r.Disabled -and -not $IncludeDisabledRepository) { $disabledRepositories++; continue }
            $days = if ($r.Push) { & $daysSince $r.Push.Date } else { $null }
            $label = "$($r.Name) (repository)"
            $before = $findings.Count
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
                    Findings         = $findings.Count - $before
                    Url              = $r.Url
                })
        }

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
                Id                 = $projectId
                Url                = $projectUrl
            })
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
            Unrecognised      = @($unknownRows).Count
            NotRead           = @($unread).Count
            DisabledRepositories = $disabledRepositories
            DisabledPipelines = $disabledPipelines
        }
    }
}
