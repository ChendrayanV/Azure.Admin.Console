<#
    Basic sanity tests for the module scaffold itself: the manifest is valid, the
    expected public functions are exported, and every public function documents
    itself with at least a synopsis.
#>

BeforeDiscovery {
    $script:aacModulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    $script:aacManifestPath = Join-Path -Path $script:aacModulePath -ChildPath 'Azure.Admin.Console.psd1'
    # Import only if not already loaded - a -Force reimport here would
    # replace the module Invoke-AACPester is running from, mid-run.
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name $script:aacManifestPath -ErrorAction Stop
    }

    $script:aacExportedFunctionCases = (Get-Command -Module 'Azure.Admin.Console') | ForEach-Object {
        @{ Name = $_.Name }
    }
}

Describe 'Azure Admin Console - Module scaffold' {
    BeforeAll {
        # Re-establish this here, not just in BeforeDiscovery: when Invoke-AACPester
        # runs every *.Tests.ps1 file together in one Invoke-Pester call, a script-scoped
        # variable set only during Discovery is not reliably readable from inside an
        # It block's body during the later Run phase.
        $script:aacModulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
        $script:aacManifestPath = Join-Path -Path $script:aacModulePath -ChildPath 'Azure.Admin.Console.psd1'
    }

    It 'has a valid module manifest' {
        { Test-ModuleManifest -Path $script:aacManifestPath -ErrorAction Stop } | Should -Not -Throw
    }

    It 'exports the expected public functions' {
        $expectedFunctions = @(
            'Connect-AAC'
            'Disconnect-AAC'
            'Get-AACAdvisorRecommendation'
            'Get-AACFirewallRule'
            'Invoke-AACPester'
            'Show-AACCost'
            'Show-AACResource'
        )
        $exportedFunctions = (Get-Command -Module 'Azure.Admin.Console').Name

        foreach ($functionName in $expectedFunctions) {
            $exportedFunctions | Should -Contain $functionName
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

    It 'depends only on Pester (no PwshSpectreConsole, Az.* or Microsoft.Graph.* modules)' {
        $requiredModuleNames = (Get-Module -Name 'Azure.Admin.Console').RequiredModules.Name
        $requiredModuleNames | Should -Be @('Pester')
    }
}
