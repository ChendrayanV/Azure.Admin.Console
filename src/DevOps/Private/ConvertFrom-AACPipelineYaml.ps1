function ConvertFrom-AACPipelineYaml {
    <#
    .SYNOPSIS
        Reads an Azure Pipelines YAML file's steps - each task with its
        major version and inputs, each script with its shell - and what the
        pipeline refers to: templates, repositories, containers, images,
        pools, variable groups, environments and service connections.
    .DESCRIPTION
        No YAML module: the steps are found by their indentation, which is
        how Azure Pipelines YAML is written - a step starts with
        '- task:', '- script:', '- bash:', '- pwsh:', '- powershell:',
        '- checkout:', '- template:'..., its block is every deeper line,
        'inputs:' holds key: value pairs, and '|' or '>' starts a multi-line
        value. Comments are taken out first.

        Inline scripts inside tasks (PowerShell@2 script, Bash@3 script,
        AzureCLI@2 inlineScript, AzurePowerShell@5 Inline) count as scripts,
        with the shell the task runs them in.

        Returns @{ Steps (@{ Kind - Task or Script; Name; Major; DisplayName;
        Enabled; Inputs; Script; Shell; Line }); Templates (@{ Path; Alias });
        Repositories (@{ Alias; Type; Name; Ref }); Images (vmImage);
        Containers; Pools; Groups; Environments; Connections; Variables (the
        names the YAML defines - never their values) }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyString()]
        [string] $Text
    )

    # Comments out, over the whole text at once (a pipeline per line is slow over thousands of files).
    $lines = [regex]::Replace($Text, '(?m)(^|[ \t])#[^\r\n]*', '') -split "`r?`n"
    # Each line's indentation, worked out once (-1 for a blank line, which belongs to any block):
    # an organization's thousands of files make a script block call per line add up to minutes.
    $indent = [int[]]::new($lines.Count)
    for ($n = 0; $n -lt $lines.Count; $n++) { $trimmed = $lines[$n].TrimStart(); $indent[$n] = if ($trimmed) { $lines[$n].Length - $trimmed.Length } else { -1 } }
    $unquote = { param([string] $Value) $Value.Trim().Trim('"', "'") }
    # A key's value: inline, or the deeper lines after '|' / '>'.
    $valueAt = {
        param([int] $Index, [string] $Inline)
        $inline = $Inline.Trim()
        if ($inline -notmatch '^[|>][+-]?$') { return @{ Value = (& $unquote $inline); Next = $Index + 1 } }
        # Deeper than the key itself - for '- script: |' that is two past the dash.
        $own = [regex]::Match($lines[$Index], '^\s*(-\s+)?').Length
        $collected = [System.Collections.Generic.List[string]]::new()
        $j = $Index + 1
        while ($j -lt $lines.Count -and ($indent[$j] -lt 0 -or $indent[$j] -gt $own)) { $collected.Add($lines[$j].Trim()); $j++ }
        @{ Value = ($collected -join "`n").Trim(); Next = $j }
    }
    $connectionKeys = '^(azureSubscription|azureSubscriptionEndpoint|connectedServiceName|connectedServiceNameARM|azureResourceManagerConnection|ConnectedServiceNameARM|kubernetesServiceEndpoint|kubernetesServiceConnection|dockerRegistryServiceConnection|containerRegistry|serviceConnection|externalEndpoint|gitHubConnection|SonarQube|SonarCloud|azureContainerRegistry|environmentServiceConnection|backendServiceArm|ensureBackend)$'
    $inlineScript = @{ PowerShell = @('script', 'pwsh'); Bash = @('script', 'bash'); AzureCLI = @('inlineScript', 'az'); AzurePowerShell = @('Inline', 'pwsh'); CmdLine = @('script', 'cmd') }

    $steps = [System.Collections.Generic.List[hashtable]]::new()
    $connections = [System.Collections.Generic.List[string]]::new()
    $i = 0
    while ($i -lt $lines.Count) {
        $m = [regex]::Match($lines[$i], '^(\s*)-\s+(task|script|bash|pwsh|powershell|checkout|template|download|publish)\s*:\s*(.*)$')
        if (-not $m.Success) { $i++; continue }
        $own = $m.Groups[1].Value.Length
        $kind = $m.Groups[2].Value
        $start = $i
        # The step's block: every deeper line (its own keys are at $own + 2).
        $j = $i + 1
        while ($j -lt $lines.Count -and ($indent[$j] -lt 0 -or $indent[$j] -gt $own)) { $j++ }
        $step = @{ Kind = 'Script'; Name = ''; Major = ''; DisplayName = ''; Enabled = $true; Inputs = [ordered]@{}; Script = ''; Shell = ''; Line = $start + 1 }
        switch ($kind) {
            'task' {
                $value = $m.Groups[3].Value.Trim().Trim('"', "'")
                $step.Kind = 'Task'
                $step.Name = ($value -split '@')[0]
                $step.Major = if ($value.Contains('@')) { ($value -split '@')[1] } else { '' }
            }
            { $_ -in 'script', 'bash', 'pwsh', 'powershell' } {
                $v = & $valueAt $i $m.Groups[3].Value
                $step.Script = $v.Value
                $step.Shell = @{ script = 'script'; bash = 'bash'; pwsh = 'pwsh'; powershell = 'powershell' }[$kind]
                $step.Name = $kind
            }
            default { $step.Kind = $kind.Substring(0, 1).ToUpperInvariant() + $kind.Substring(1); $step.Name = $m.Groups[3].Value.Trim().Trim('"', "'") }
        }
        # Its keys: displayName, enabled, and the inputs.
        for ($k = $i + 1; $k -lt $j; $k++) {
            $line = $lines[$k]
            if ($indent[$k] -lt 0) { continue }
            $key = [regex]::Match($line, '^(\s*)([\w.-]+)\s*:\s*(.*)$')
            if (-not $key.Success) { continue }
            switch ($key.Groups[2].Value) {
                'displayName' { if ($indent[$k] -le $own + 2) { $step.DisplayName = $key.Groups[3].Value.Trim().Trim('"', "'") } }
                'enabled' { if ($indent[$k] -le $own + 2) { $step.Enabled = $key.Groups[3].Value.Trim().Trim('"', "'") -ne 'false' } }
                'inputs' {
                    $inputIndent = $indent[$k]
                    $n = $k + 1
                    while ($n -lt $j) {
                        if ($indent[$n] -lt 0) { $n++; continue }
                        if ($indent[$n] -le $inputIndent) { break }
                        $pair = [regex]::Match($lines[$n], '^\s*([\w.-]+)\s*:\s*(.*)$')
                        if ($pair.Success -and $indent[$n] -eq ($inputIndent + 2)) {
                            $inline = $pair.Groups[2].Value.Trim()
                            # Most inputs are one line: only a block (| or >) needs the slower path.
                            if ($inline -notmatch '^[|>][+-]?$') { $step.Inputs[$pair.Groups[1].Value] = $inline.Trim('"', "'"); $n++; continue }
                            $v = & $valueAt $n $inline
                            $step.Inputs[$pair.Groups[1].Value] = $v.Value
                            $n = $v.Next
                            continue
                        }
                        $n++
                    }
                    $k = $n - 1
                }
            }
        }
        if ($step.Kind -eq 'Task') {
            # An inline script inside a task, with the shell it runs in.
            if ($inlineScript.ContainsKey($step.Name)) {
                $key, $shell = $inlineScript[$step.Name]
                $found = @($step.Inputs.Keys | Where-Object { $_ -ieq $key }) | Select-Object -First 1
                if ($found -and $step.Inputs[$found]) {
                    $step.Script = [string]$step.Inputs[$found]
                    $step.Shell = if ($step.Name -eq 'PowerShell') { if ([string]$step.Inputs['pwsh'] -eq 'true') { 'pwsh' } else { 'powershell' } } elseif ($step.Name -eq 'AzureCLI') { @{ pscore = 'pwsh'; ps = 'powershell'; bash = 'bash'; batch = 'cmd' }[[string]$step.Inputs['scriptType']] } else { $shell }
                }
            }
            foreach ($inputKey in $step.Inputs.Keys) { if ($inputKey -match $connectionKeys -and $step.Inputs[$inputKey] -and $step.Inputs[$inputKey] -notmatch '^\$') { $connections.Add([string]$step.Inputs[$inputKey]) } }
        }
        $steps.Add($step)
        $i = [Math]::Max($i + 1, $j)
    }

    # The variables it defines - names only, never values: the mapping form (variables: then name: value)
    # and the list form (- name: x), at pipeline, stage or job level; groups and templates are listed apart.
    $variableNames = [System.Collections.Generic.List[string]]::new()
    for ($v = 0; $v -lt $lines.Count; $v++) {
        if ($lines[$v] -notmatch '^\s*variables:\s*$') { continue }
        $base = $indent[$v]
        $child = -1
        for ($w = $v + 1; $w -lt $lines.Count; $w++) {
            if ($indent[$w] -lt 0) { continue }
            if ($indent[$w] -le $base) { break }
            if ($child -lt 0) { $child = $indent[$w] }
            $item = [regex]::Match($lines[$w], '^\s*-\s*name:\s*[''"]?([\w.-]+)')
            if ($item.Success) { if (-not $variableNames.Contains($item.Groups[1].Value)) { $variableNames.Add($item.Groups[1].Value) }; continue }
            $pair = [regex]::Match($lines[$w], '^\s*([\w.-]+)\s*:')
            if ($pair.Success -and $indent[$w] -eq $child -and $lines[$w].TrimStart() -notmatch '^-' -and $pair.Groups[1].Value -notin 'name', 'value', 'group', 'template', 'readonly') {
                if (-not $variableNames.Contains($pair.Groups[1].Value)) { $variableNames.Add($pair.Groups[1].Value) }
            }
        }
    }

    # What the pipeline refers to.
    $all = $lines -join "`n"
    $templates = @([regex]::Matches($all, '(?m)\btemplate:\s*[''"]?([^''"\s]+)') | ForEach-Object {
            $ref = $_.Groups[1].Value
            if ($ref.Contains('$')) { return }
            $at = $ref.LastIndexOf('@')
            @{ Path = $(if ($at -gt 0) { $ref.Substring(0, $at) } else { $ref }); Alias = $(if ($at -gt 0) { $ref.Substring($at + 1) } else { '' }) }
        })
    $repositories = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($r in [regex]::Matches($all, '(?ms)^(\s*)-\s+repository:\s*([\w.-]+)\s*$(.*?)(?=^\1-\s|^\S|\z)')) {
        $body = $r.Groups[3].Value
        $field = { param([string] $Name) $f = [regex]::Match($body, "(?m)^\s*$Name\s*:\s*(.+)$"); if ($f.Success) { & $unquote $f.Groups[1].Value } else { '' } }
        $repositories.Add(@{ Alias = $r.Groups[2].Value; Type = (& $field 'type'); Name = (& $field 'name'); Ref = (& $field 'ref'); Endpoint = (& $field 'endpoint') })
    }
    $environments = @([regex]::Matches($all, '(?m)^\s*environment:\s*[''"]?([\w.-]+)') | ForEach-Object { $_.Groups[1].Value }) + @([regex]::Matches($all, '(?ms)^\s*environment:\s*$\s*name:\s*[''"]?([\w.-]+)') | ForEach-Object { $_.Groups[1].Value })
    @{
        Steps        = $steps.ToArray()
        Templates    = $templates
        Repositories = $repositories.ToArray()
        Images       = @([regex]::Matches($all, '(?m)\bvmImage:\s*[''"]?([\w.-]+)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
        # image: is always an image; container: is one only when it looks like it (in resources it names an alias).
        Containers   = @(@([regex]::Matches($all, '(?m)^\s*(?:-\s*)?image:\s*[''"]?([\w./-]+(?::[\w.-]+)?)\s*[''"]?\s*$') | ForEach-Object { $_.Groups[1].Value }) + @([regex]::Matches($all, '(?m)^\s*(?:-\s*)?container:\s*[''"]?([\w./-]+(?::[\w.-]+)?)\s*[''"]?\s*$') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -match '[/:]' }) | Select-Object -Unique)
        Pools        = @([regex]::Matches($all, '(?m)^\s*pool:\s*[''"]?([\w. -]+?)[''"]?\s*$') | ForEach-Object { $_.Groups[1].Value.Trim() } | Where-Object { $_ } | Select-Object -Unique) + @([regex]::Matches($all, '(?ms)^\s*pool:\s*$\s*name:\s*[''"]?([\w. -]+?)[''"]?\s*$') | ForEach-Object { $_.Groups[1].Value.Trim() } | Select-Object -Unique)
        Groups       = @([regex]::Matches($all, '(?m)^\s*-\s*group:\s*[''"]?([^''"\n]+?)[''"]?\s*$') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
        Environments = @($environments | Select-Object -Unique)
        Connections  = @($connections | Select-Object -Unique)
        Variables    = $variableNames.ToArray()
    }
}
