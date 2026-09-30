<#
    Basic sanity tests for the module scaffold itself: the manifest is valid, the
    expected public functions are exported, and every public function documents
    itself with at least a synopsis.
#>

BeforeDiscovery {
    $script:aacModulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    $script:aacManifestPath = Join-Path -Path $script:aacModulePath -ChildPath 'Azure.Admin.Console.psd1'
    # Import only if not already loaded - a -Force reimport here would
    # replace the module other test files are mocking into, mid-run.
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name $script:aacManifestPath -ErrorAction Stop
    }

    $script:aacExportedFunctionCases = (Get-Command -Module 'Azure.Admin.Console') | ForEach-Object {
        @{ Name = $_.Name }
    }
}

Describe 'Azure Admin Console - Module scaffold' {
    BeforeAll {
        # Re-establish this here, not just in BeforeDiscovery: when every
        # *.Tests.ps1 file runs together in one Invoke-Pester call, a script-scoped
        # variable set only during Discovery is not reliably readable from inside an
        # It block's body during the later Run phase.
        $script:aacModulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
        $script:aacManifestPath = Join-Path -Path $script:aacModulePath -ChildPath 'Azure.Admin.Console.psd1'
    }

    It 'has a valid module manifest' {
        { Test-ModuleManifest -Path $script:aacManifestPath -ErrorAction Stop } | Should -Not -Throw
    }

    It 'exports exactly the public functions, and nothing parked or private' {
        $expectedFunctions = @(
            'Connect-AAC'
            'Disconnect-AAC'
            'Get-AACAdvisorRecommendation'
            'Get-AACEntraGroupMembership'
            'Get-AACFirewallRule'
            'Get-AACInventory'
            'Get-AACNetworkSecurityGroup'
            'Get-AACPolicyState'
            'Get-AACSecurityPosture'
            'Get-AACSkuAvailability'
            'Invoke-AACApplicationInsightQuery'
            'Invoke-AACPSRule'
            'Show-AACCost'
            'Show-AACResource'
            'Show-AACResourceMap'
        )
        @((Get-Command -Module 'Azure.Admin.Console').Name | Sort-Object) | Should -Be @($expectedFunctions | Sort-Object)
        Get-Command -Name 'Invoke-AACPester' -ErrorAction Ignore | Should -BeNullOrEmpty -Because 'Invoke-AACPester is parked (Parked\README.md)'
    }

    It 'has a Public\<name>.ps1 file for every exported function, and exports every one' {
        $files = @(Get-ChildItem -Path (Join-Path $script:aacModulePath 'Public') -Filter '*.ps1' | ForEach-Object BaseName | Sort-Object)
        $files | Should -Be @((Import-PowerShellDataFile $script:aacManifestPath).FunctionsToExport | Sort-Object)
    }

    It 'ships MAML help for every exported function' {
        $maml = Join-Path $script:aacModulePath 'en-US/Azure.Admin.Console-help.xml'
        $maml | Should -Exist
        $names = @(([xml](Get-Content -LiteralPath $maml -Raw)).helpItems.command.details.name)
        foreach ($name in (Import-PowerShellDataFile $script:aacManifestPath).FunctionsToExport) {
            $names | Should -Contain $name -Because 'run ./build.ps1 -Task Docs after adding a command'
        }
    }

    It "<Name> has comment-based help with a real synopsis" -ForEach $script:aacExportedFunctionCases {
        $synopsis = (Get-Help -Name $Name).Synopsis
        $synopsis | Should -Not -BeNullOrEmpty -Because "function $Name should document its purpose"
        # When comment-based help fails to parse (e.g. a description line that
        # starts with ".something", which the parser misreads as an unknown
        # help keyword and aborts on), Get-Help silently falls back to showing
        # the syntax diagram as the "synopsis" instead of throwing - so a
        # not-null check alone isn't enough to catch that failure mode.
        $synopsis | Should -Not -Match ([regex]::Escape("$Name ")) -Because 'a real synopsis should not just be the syntax diagram'
    }

    It 'loaded the vendored Spectre.Console.dll directly' {
        $loaded = [AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq 'Spectre.Console' }
        $loaded | Should -Not -BeNullOrEmpty
    }

    It 'depends only on PSRule for Azure (no Pester, PwshSpectreConsole, Az.* or Microsoft.Graph.* modules)' {
        $requiredModuleNames = (Get-Module -Name 'Azure.Admin.Console').RequiredModules.Name
        $requiredModuleNames | Should -Be @('PSRule.Rules.Azure')
    }
}
