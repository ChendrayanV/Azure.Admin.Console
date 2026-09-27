function Invoke-AACPSRuleEngine {
    <#
    .SYNOPSIS
        Reads the estate and runs PSRule for Azure - and the module's and
        your custom rules - on it; returns one AAC.PSRuleResult per rule and
        resource. The engine behind Invoke-AACPSRule.
    .DESCRIPTION
        1. Get-AACRuleData reads the estate in Export-AzRuleData's shape with
           the Connect-AAC sign-in (Resource Graph plus the child settings
           PSRule's rules read).
        2. PSRule\PSRuleRunner.ps1 runs the rules in a pwsh process of its
           own (PSRule's YamlDotNet.dll must not meet another version of it
           in this session): PSRule for Azure's, the module's own
           (PSRule\Rules) and any -RulePath files, narrowed by -Rule and
           -ExcludeRule (names or wildcards).
        3. Each result becomes an AAC.PSRuleResult: the rule (name, title,
           Well-Architected pillar, severity, reference, documentation link,
           recommendation, source), the resource (name, type, group,
           subscription, ID) and the outcome with its reasons.

        Progress goes to the Invoke-AACProgress display (psrule-read,
        psrule-expand, psrule-rules). Returns @{ Results; Warnings; Rules;
        Objects }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    # $failure is assigned inside the ForEach-Object script block that reads
    # the runner's output, and read after it - the analyzer can't see that.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'failure', Justification = 'Assigned in a ForEach-Object script block, read after it.')]
    param(
        [string[]] $SubscriptionId = @(),
        [string[]] $ResourceType = @(),
        [string[]] $Rule = @(),
        [string[]] $ExcludeRule = @(),
        [string] $Baseline,
        [hashtable] $Configuration = @{},
        [string[]] $RulePath = @()
    )

    $installed = Get-Module -Name 'PSRule.Rules.Azure' -ListAvailable | Sort-Object -Property Version -Descending | Select-Object -First 1
    if (-not $installed) {
        throw 'PSRule for Azure is not installed. Run: Install-PSResource PSRule.Rules.Azure -Scope CurrentUser'
    }

    # --- Read the estate, as Export-AzRuleData would ------------------------------------
    $data = Get-AACRuleData -SubscriptionId $SubscriptionId -ResourceType $ResourceType

    # PSRule's PowerShell rules need objects, and the estate goes to the
    # runner as JSON. Keys differing only by case ('Owner' and 'owner'
    # tags) would make that JSON unreadable, so each resource is first made
    # an object, which keeps just the first of them - quickly by a JSON round
    # trip, or exactly when the round trip refuses the duplicate keys.
    $objects = @(foreach ($resource in $data.Resources) {
            try {
                ConvertTo-Json -InputObject $resource -Depth 100 -Compress | ConvertFrom-Json -Depth 100 -ErrorAction Stop
            }
            catch {
                ConvertTo-AACPSObject -InputObject $resource
            }
        })

    # --- Run the rules, in a process of their own --------------------------------------------
    $paths = @(Join-Path -Path $script:AACModuleRoot -ChildPath 'PSRule/Rules') + @($RulePath)
    $work = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "aac-psrule-$([guid]::NewGuid().ToString('n'))"
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $ruleCount = 0
    try {
        $inputFile = Join-Path -Path $work -ChildPath 'input.json'
        $settingFile = Join-Path -Path $work -ChildPath 'settings.json'
        $outputFile = Join-Path -Path $work -ChildPath 'results.json'
        [System.IO.File]::WriteAllText($inputFile, (ConvertTo-Json -InputObject $objects -Depth 100 -Compress), [System.Text.UTF8Encoding]::new($false))
        $settings = @{ Rule = @($Rule); ExcludeRule = @($ExcludeRule); Baseline = $Baseline; Configuration = $Configuration; RulePath = $paths }
        [System.IO.File]::WriteAllText($settingFile, (ConvertTo-Json -InputObject $settings -Depth 20), [System.Text.UTF8Encoding]::new($false))

        Update-AACProgress -Id 'psrule-rules' -Total ([Math]::Max(1, $objects.Count)) -Description "Loading PSRule for Azure $($installed.Version)"
        # The same pwsh as this session.
        $pwsh = (Get-Process -Id $PID).Path
        $runner = Join-Path -Path $script:AACModuleRoot -ChildPath 'PSRule/PSRuleRunner.ps1'
        $failure = $null
        $other = [System.Collections.Generic.List[string]]::new()
        $done = 0
        & $pwsh -NoProfile -NonInteractive -File $runner -ModulePath $installed.Path -InputPath $inputFile -SettingPath $settingFile -OutputPath $outputFile 2>&1 | ForEach-Object {
            $line = [string]$_
            if ($line -match '^PROGRESS (\d+)$') {
                $now = [int]$Matches[1]
                if ($now -gt $done) {
                    Update-AACProgress -Id 'psrule-rules' -Increment ($now - $done)
                    $done = $now
                }
            }
            elseif ($line -match '^RULES (\d+)$') {
                $ruleCount = [int]$Matches[1]
                Update-AACProgress -Id 'psrule-rules' -Description ('Running {0:N0} rules on {1:N0} objects' -f $ruleCount, $objects.Count)
            }
            elseif ($line -match '^ERROR (.*)$') {
                $failure = $Matches[1]
            }
            elseif ($line.Trim()) {
                $other.Add($line)
            }
        }
        $exitCode = $LASTEXITCODE
        if ($failure -or $exitCode -ne 0 -or -not (Test-Path -LiteralPath $outputFile)) {
            $reason = if ($failure) { $failure } elseif ($other.Count) { (@($other) | Select-Object -Last 5) -join ' ' } else { "PowerShell exited with code $exitCode" }
            throw "PSRule for Azure $($installed.Version) failed: $reason"
        }
        $raw = @(Get-Content -LiteralPath $outputFile -Raw | ConvertFrom-Json -Depth 10)
    }
    finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction Ignore
    }

    # --- Results as objects --------------------------------------------------------------------
    $pillarOrder = @('Security', 'Reliability', 'Cost Optimization', 'Operational Excellence', 'Performance Efficiency')
    $outcomeOrder = @{ Fail = 0; Error = 1; Pass = 2 }
    $names = $data.SubscriptionNames
    $results = @(foreach ($item in $raw) {
            $name = [string]$item.RuleName
            $source = if ($item.ModuleName -eq 'PSRule.Rules.Azure') { 'PSRule for Azure' } elseif ($name -like 'AAC.*') { 'Azure.Admin.Console' } else { 'Custom' }
            $link = if ($item.Link) { [string]$item.Link } elseif ($source -eq 'PSRule for Azure') { "https://azure.github.io/PSRule.Rules.Azure/en/rules/$name/" } else { '' }
            $type = [string]$item.Type
            $subscriptionKey = [string]$item.SubscriptionId
            $reasons = @($item.Reason | Where-Object { $_ })
            if ([string]$item.Outcome -eq 'Error' -and $item.ErrorMessage) { $reasons = @("The rule could not be evaluated: $($item.ErrorMessage)") }
            [pscustomobject]@{
                PSTypeName       = 'AAC.PSRuleResult'
                Outcome          = [string]$item.Outcome
                Pillar           = $(if ($item.Pillar) { [string]$item.Pillar } else { 'Other' })
                RuleName         = $name
                Title            = $(if ($item.DisplayName -and $item.DisplayName -ne $name) { [string]$item.DisplayName } else { [string]$item.Synopsis })
                Severity         = $(if ($item.Severity) { [string]$item.Severity } else { [string]$item.Level })
                ResourceName     = $(if ($item.TargetName) { [string]$item.TargetName } else { [string]$item.Name })
                ResourceType     = $type.ToLowerInvariant()
                ResourceGroup    = $(if ($item.ResourceGroupName) { [string]$item.ResourceGroupName } elseif ($type -eq 'Microsoft.Subscription') { '' } else { '' })
                SubscriptionName = $(if ($subscriptionKey -and $names.ContainsKey($subscriptionKey)) { $names[$subscriptionKey] } else { $subscriptionKey })
                SubscriptionId   = $subscriptionKey
                Reason           = $reasons -join '; '
                Recommendation   = [string]$item.Recommendation
                Synopsis         = [string]$item.Synopsis
                Ref              = [string]$item.Ref
                Link             = $link
                Source           = $source
                ResourceId       = [string]$item.Id
            }
        })
    $results = @($results | Sort-Object -Property @(
            @{ Expression = { $i = $pillarOrder.IndexOf($_.Pillar); if ($i -lt 0) { 99 } else { $i } } }
            @{ Expression = { $outcomeOrder[$_.Outcome] } }
            'RuleName', 'SubscriptionName', 'ResourceGroup', 'ResourceName'
        ))
    $failed = @($results | Where-Object Outcome -NE 'Pass').Count
    Update-AACProgress -Id 'psrule-rules' -Complete -Description ('PSRule for Azure {0}: {1:N0} rules, {2:N0} results - {3:N0} passed, {4:N0} failed' -f $installed.Version, $ruleCount, $results.Count, ($results.Count - $failed), $failed)

    @{
        Results  = $results
        Warnings = @($data.Warnings)
        Rules    = $ruleCount
        Objects  = $objects.Count
        Version  = [string]$installed.Version
    }
}
