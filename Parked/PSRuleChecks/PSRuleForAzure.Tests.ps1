<#
    PSRule for Azure against the live estate: every rule of the
    PSRule.Rules.Azure module (500+, following the Azure Well-Architected
    Framework) is run on every resource, resource group and subscription the
    signed-in account can see, and each result becomes a Pester test. It
    only reads - nothing in Azure is changed.

    Where Checks\AzureEstate.Tests.ps1 re-implements some of these rules in
    this module, this runs PSRule for Azure's own rules, so it stays as
    complete and current as the PSRule.Rules.Azure version installed (a
    required module, installed with this one; Update-PSResource
    PSRule.Rules.Azure gets newer rules).

    The data PSRule needs is what Export-AzRuleData would export, read here
    with the Connect-AAC sign-in instead of the Az modules (see
    Get-AACRuleData): Azure Resource Graph for the resources, plus Azure
    Resource Manager calls for the child settings of the types PSRule
    expands (storage blob services, SQL auditing, Key Vault diagnostic
    settings, ...). Reader on the subscriptions is enough.

    Run it with Invoke-AACPester -PSRule, or on its own:

        Connect-AAC
        Invoke-AACPester -Path .\Azure.Admin.Console\PSRuleChecks -Data @{
            SubscriptionId = '00000000-0000-0000-0000-000000000000'
        }

    Each Well-Architected pillar is a Describe block tagged with its name
    (Security, Reliability, CostOptimization, OperationalExcellence,
    PerformanceEfficiency) and PSRule; each rule is a Context tagged with
    the rule's name. So:

        Invoke-AACPester -PSRule -Tag Security

    PSRule for Azure's settings (https://azure.github.io/PSRule.Rules.Azure/setup/configuring-options/)
    go in -Data Configuration, for example the regions resources may use:

        Invoke-AACPester -PSRule -Data @{
            Configuration = @{ AZURE_RESOURCE_ALLOWED_LOCATIONS = @('uksouth', 'ukwest') }
        }
#>

param(
    # Defaults to every subscription the signed-in account can see.
    [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
    [string[]] $SubscriptionId = @(),

    # Only check resources of these types, e.g. 'microsoft.storage/*'.
    # Case-insensitive; wildcards work. Defaults to every type, plus
    # resource groups and subscriptions.
    [string[]] $ResourceType = @(),

    # Only run these rules: names or wildcards, e.g. 'Azure.Storage.*'.
    [string[]] $Rule = @(),

    # Leave out these rules (names, no wildcards).
    [string[]] $ExcludeRule = @(),

    # A PSRule for Azure baseline, e.g. 'Azure.GA_2024_12' or
    # 'Azure.Pillar.Security'. Defaults to the module's default baseline.
    [string] $Baseline = '',

    # PSRule for Azure configuration values, e.g.
    # @{ AZURE_RESOURCE_ALLOWED_LOCATIONS = @('uksouth') }.
    [hashtable] $Configuration = @{}
)

BeforeDiscovery {
    # Import only if not already loaded - a -Force reimport would replace the
    # module Invoke-AACPester is running from and clear the Connect-AAC sign-in.
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '../Azure.Admin.Console.psd1') -ErrorAction Stop
    }
    $module = Get-Module -Name 'Azure.Admin.Console'

    # Exactly one of the first five ends up non-empty, and decides which tests exist.
    $pillars = @()
    $notConnectedCase = @()
    $notInstalledCase = @()
    $noResultsCase = @()
    $readErrorCase = @()
    $warningCase = @()

    # Moves on a line of Invoke-AACPester's progress display (see
    # Update-AACProgress); does nothing under plain Invoke-Pester.
    function Write-CheckProgress {
        param([string] $Id, [string] $Description, [double] $Total, [double] $Increment, [switch] $Indeterminate, [switch] $Complete)
        & $module { param($Parameters) Update-AACProgress @Parameters } $PSBoundParameters
    }

    $installed = Get-Module -Name 'PSRule.Rules.Azure' -ListAvailable | Sort-Object -Property Version -Descending | Select-Object -First 1

    if (-not $global:AACSession) {
        $notConnectedCase = @(@{})
    }
    elseif (-not $installed) {
        $notInstalledCase = @(@{})
    }
    else {
        try {
            # --- Read the estate, as Export-AzRuleData would -------------------
            $data = & $module { param($s, $t) Get-AACRuleData -SubscriptionId $s -ResourceType $t } $SubscriptionId $ResourceType

            if ($data.Warnings.Count -gt 0) {
                $shown = @($data.Warnings | Select-Object -First 8)
                $more = $data.Warnings.Count - $shown.Count
                $warningCase = @(@{
                        Count  = $data.Warnings.Count
                        Detail = ($shown -join '; ') + $(if ($more -gt 0) { "; and $more more" })
                    })
            }

            # --- Run PSRule for Azure, in a process of its own ------------------------
            # PSRule's YamlDotNet.dll clashes with other versions of it that
            # modules such as platyPS, powershell-yaml and Az.Aks load; see
            # PSRuleRunner.ps1. The estate goes over as JSON. Keys differing
            # only by case ('Owner' and 'owner' tags) would make that JSON
            # unreadable, so each resource is first made an object, which
            # keeps just the first of them - quickly by a JSON round trip, or
            # exactly when the round trip refuses the duplicate keys.
            $objects = @(foreach ($resource in $data.Resources) {
                    try {
                        ConvertTo-Json -InputObject $resource -Depth 100 -Compress | ConvertFrom-Json -Depth 100 -ErrorAction Stop
                    }
                    catch {
                        & $module { param($r) ConvertTo-AACPSObject -InputObject $r } $resource
                    }
                })
            $work = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "aac-psrule-$([guid]::NewGuid().ToString('n'))"
            New-Item -ItemType Directory -Path $work -Force | Out-Null
            try {
                $inputFile = Join-Path -Path $work -ChildPath 'input.json'
                $settingFile = Join-Path -Path $work -ChildPath 'settings.json'
                $outputFile = Join-Path -Path $work -ChildPath 'results.json'
                [System.IO.File]::WriteAllText($inputFile, (ConvertTo-Json -InputObject $objects -Depth 100 -Compress), [System.Text.UTF8Encoding]::new($false))
                $settings = @{ Rule = @($Rule); ExcludeRule = @($ExcludeRule); Baseline = $Baseline; Configuration = $Configuration }
                [System.IO.File]::WriteAllText($settingFile, (ConvertTo-Json -InputObject $settings -Depth 20), [System.Text.UTF8Encoding]::new($false))

                Write-CheckProgress -Id 'psrule-rules' -Total $objects.Count -Description ('Running PSRule for Azure {0} on {1:N0} objects' -f $installed.Version, $objects.Count)
                # The same pwsh as this session.
                $pwsh = (Get-Process -Id $PID).Path
                $runner = Join-Path -Path $PSScriptRoot -ChildPath 'PSRuleRunner.ps1'
                $failure = $null
                $other = [System.Collections.Generic.List[string]]::new()
                $done = 0
                & $pwsh -NoProfile -NonInteractive -File $runner -ModulePath $installed.Path -InputPath $inputFile -SettingPath $settingFile -OutputPath $outputFile 2>&1 | ForEach-Object {
                    $line = [string]$_
                    if ($line -match '^PROGRESS (\d+)$') {
                        $now = [int]$Matches[1]
                        if ($now -gt $done) {
                            Write-CheckProgress -Id 'psrule-rules' -Increment ($now - $done)
                            $done = $now
                        }
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
                $results = @(Get-Content -LiteralPath $outputFile -Raw | ConvertFrom-Json -Depth 10)
            }
            finally {
                Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction Ignore
            }
            Write-CheckProgress -Id 'psrule-rules' -Complete -Description ('PSRule for Azure {0}: {1:N0} results - {2:N0} passed, {3:N0} failed' -f $installed.Version, $results.Count,
                @($results | Where-Object { $_.Outcome -eq 'Pass' }).Count, @($results | Where-Object { $_.Outcome -ne 'Pass' }).Count)

            # --- Results as test cases: pillar > rule > resource -----------------------
            $subscriptionNames = $data.SubscriptionNames
            $order = @('Security', 'Reliability', 'Cost Optimization', 'Operational Excellence', 'Performance Efficiency')
            $byRule = [ordered]@{}
            foreach ($result in $results) {
                $name = $result.RuleName
                if (-not $byRule.Contains($name)) {
                    $byRule[$name] = @{
                        RuleName       = $name
                        Title          = $(if ($result.DisplayName -and $result.DisplayName -ne $name) { $result.DisplayName } else { $result.Synopsis })
                        Pillar         = $(if ($result.Pillar) { $result.Pillar } else { 'Other' })
                        Ref            = $result.Ref
                        Link           = $(if ($result.Link) { $result.Link } else { "https://azure.github.io/PSRule.Rules.Azure/en/rules/$name/" })
                        Severity       = $(if ($result.Severity) { $result.Severity } else { $result.Level })
                        Synopsis       = $result.Synopsis
                        Recommendation = $result.Recommendation
                        Cases          = [System.Collections.Generic.List[hashtable]]::new()
                    }
                }
                # Not $subscriptionId: that is this file's [string[]] parameter.
                $targetSubscription = $result.SubscriptionId
                $subscription = if ($targetSubscription -and $subscriptionNames.ContainsKey($targetSubscription)) { $subscriptionNames[$targetSubscription] } else { $targetSubscription }
                $type = [string]$result.Type
                $byRule[$name].Cases.Add(@{
                        Name           = $(if ($result.TargetName) { $result.TargetName } else { $result.Name })
                        Type           = $type.ToLowerInvariant()
                        RG             = $(if ($result.ResourceGroupName) { $result.ResourceGroupName } elseif ($type -eq 'Microsoft.Subscription') { 'subscription' } else { '-' })
                        Subscription   = $subscription
                        ResourceId     = $result.Id
                        Outcome        = $result.Outcome
                        Reason         = @($result.Reason)
                        ErrorMessage   = $result.ErrorMessage
                        RuleName       = $name
                        Ref            = $result.Ref
                        Link           = $byRule[$name].Link
                        Severity       = $byRule[$name].Severity
                        Pillar         = $byRule[$name].Pillar
                        Recommendation = $byRule[$name].Recommendation
                    })
            }
            $pillarNames = @($byRule.Values | ForEach-Object { $_.Pillar } | Select-Object -Unique | Sort-Object -Property { $i = $order.IndexOf($_); if ($i -lt 0) { 99 } else { $i } }, { $_ })
            $pillars = @(foreach ($pillarName in $pillarNames) {
                    @{
                        Pillar = $pillarName
                        Tag    = $pillarName -replace '\s', ''
                        Rules  = @($byRule.Values | Where-Object { $_.Pillar -eq $pillarName } | Sort-Object -Property RuleName | ForEach-Object {
                                $_.Cases = @($_.Cases | Sort-Object -Property { $_.Name })
                                $_
                            })
                    }
                })
            if ($pillars.Count -eq 0) {
                $noResultsCase = @(@{})
            }
        }
        catch {
            $readErrorCase = @(@{ Message = $_.Exception.Message })
        }
    }
}

# One Describe per Well-Architected pillar, tagged with its name and PSRule;
# one Context per rule, tagged with the rule's name.
foreach ($pillarCase in $pillars) {
    Describe '<Pillar>' -Tag 'PSRule', $pillarCase.Tag -ForEach @($pillarCase) {
        foreach ($ruleCase in $Rules) {
            Context '<RuleName> - <Title>' -Tag $ruleCase.RuleName -ForEach @($ruleCase) {
                It '<Name> (<Type>, <RG>)' -ForEach $Cases {
                    switch ($Outcome) {
                        'Pass' { }
                        'Fail' {
                            $lines = @(
                                $(if ($Reason.Count -gt 0) { $Reason } else { 'The rule failed.' })
                                "Recommendation: $Recommendation"
                                "PSRule $RuleName ($Ref, $Severity) - subscription $Subscription - $Link"
                            )
                            throw ($lines -join [Environment]::NewLine)
                        }
                        default {
                            throw "PSRule could not evaluate $RuleName on this resource: $ErrorMessage"
                        }
                    }
                }
            }
        }
    }
}

Describe 'PSRule for Azure' -Tag 'PSRule', 'Security', 'Reliability', 'CostOptimization', 'OperationalExcellence', 'PerformanceEfficiency' {
    It 'Estate meets PSRule for Azure (needs Connect-AAC)' -ForEach $notConnectedCase {
        Set-ItResult -Skipped -Because 'there is no active Azure sign-in in this session - run Connect-AAC first'
    }

    It 'Estate meets PSRule for Azure (needs PSRule.Rules.Azure)' -ForEach $notInstalledCase {
        Set-ItResult -Skipped -Because 'the PSRule.Rules.Azure module is not installed - run: Install-Module PSRule.Rules.Azure -Scope CurrentUser'
    }

    It 'Estate meets PSRule for Azure' -ForEach $noResultsCase {
        Set-ItResult -Skipped -Because 'no PSRule for Azure rule applies to what the signed-in account can see (in the chosen subscriptions, types and rules)'
    }

    It 'Estate could be read and checked' -ForEach $readErrorCase {
        throw "Could not run PSRule for Azure: $Message"
    }

    It 'Every resource setting could be read' -ForEach $warningCase {
        Set-ItResult -Skipped -Because "the settings of $Count resource(s) could not be read, so rules that use them may report them wrongly - $Detail"
    }
}
