#Requires -Version 7.4
<#
.SYNOPSIS
    Builds Azure.Admin.Console: regenerates the docs, runs the unit tests,
    stages a clean package and (only when asked) publishes it to the
    PowerShell Gallery.
.DESCRIPTION
    Tasks, run in this order:

      Docs      Builds the help with Microsoft.PowerShell.PlatyPS
                (tools\Build-Help.ps1): docs\<Command>.md for every
                exported command, en-US\Azure.Admin.Console-help.xml (the
                MAML help Get-Help shows), docs\about_*.md from
                en-US\about_*.help.txt and the docs\ index. The
                comment-based help in Public\*.ps1 is the one source -
                edit it, then rerun this task. Needs PlatyPS 1.0+ on the
                build machine only (Install-PSResource
                Microsoft.PowerShell.PlatyPS).
      Test      Runs the unit tests in Tests\ (no Azure sign-in needed) and
                stops the build if any fail. -TestResultPath also writes
                JUnit XML for CI.
      Build     Copies only what the module needs at run time into
                out\Azure.Admin.Console, then validates the staged copy:
                Test-ModuleManifest, every exported function has a
                Public\*.ps1 file, a clean import in a fresh pwsh, and
                PSScriptAnalyzer errors and warnings (if it is installed;
                settings in PSScriptAnalyzerSettings.psd1). Tests\,
                docs\ and this script are not packaged.
      Publish   Publishes out\Azure.Admin.Console to the PowerShell Gallery
                with Publish-PSResource. Never runs by default. Needs
                -ApiKey (or $env:PSGALLERY_API_KEY). Add -WhatIf to see
                what would happen without publishing.

    A published version can never be replaced, only unlisted - bump
    ModuleVersion in Azure.Admin.Console.psd1 before each release.
.EXAMPLE
    ./build.ps1
    Docs, Test and Build: leaves a validated package in out\Azure.Admin.Console.
.EXAMPLE
    ./build.ps1 -Task Docs
    Only rebuilds the help (Markdown and MAML) after editing a command's help.
.EXAMPLE
    $env:PSGALLERY_API_KEY = '<key from powershellgallery.com>'
    ./build.ps1 -Task Build, Publish
    Stages, validates and publishes the module.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Docs', 'Test', 'Build', 'Publish')]
    [string[]] $Task = @('Docs', 'Test', 'Build'),

    [string] $ApiKey = $env:PSGALLERY_API_KEY,

    [string] $Repository = 'PSGallery',

    # Test task: also write the results here as JUnit XML (for CI).
    [string] $TestResultPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleName = 'Azure.Admin.Console'
$root = $PSScriptRoot
$manifestPath = Join-Path $root "$moduleName.psd1"
$stage = Join-Path $root "out/$moduleName"
$docs = Join-Path $root 'docs'

# What the installed module needs at run time - nothing else is packaged.
$packageItems = @(
    "$moduleName.psd1"
    "$moduleName.psm1"
    "$moduleName.Format.ps1xml"
    'Public'
    'Private'
    'PSRule'
    'lib'
    'en-US'
    'LICENSE'
    'README.md'
    'CHANGELOG.md'
)

function Write-Step([string] $Message) { Write-Host "==> $Message" -ForegroundColor Cyan }

# --- Docs ------------------------------------------------------------------------

# The help is built with Microsoft.PowerShell.PlatyPS by tools\Build-Help.ps1
# (see there): docs\<Command>.md, en-US\Azure.Admin.Console-help.xml (MAML,
# what Get-Help shows), docsbout_*.md and the docs\ index. It runs in a
# pwsh process of its own, because PlatyPS and PSRule each load their own
# YamlDotNet.dll and one process can hold only one version of it.
function Invoke-DocsTask {
    Write-Step 'Docs: building the help with PlatyPS (docs\*.md and en-US MAML)'
    & pwsh -NoProfile -NonInteractive -File (Join-Path $root 'tools/Build-Help.ps1') -ModuleManifest $manifestPath -DocsPath $docs -HelpPath (Join-Path $root 'en-US')
    if ($LASTEXITCODE) { throw 'Building the help failed.' }
}

# --- Test ------------------------------------------------------------------------

function Invoke-TestTask {
    Write-Step 'Test: running the unit tests in Tests'
    # A fresh process, so the tests import the module the way a user would.
    $resultPath = if ($TestResultPath) { $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TestResultPath) } else { '' }
    $script = @"
Import-Module Pester -MinimumVersion 5.7.1
`$config = New-PesterConfiguration
`$config.Run.Path = '$(Join-Path $root 'Tests')'
`$config.Run.PassThru = `$true
`$config.Output.Verbosity = 'Detailed'
if ('$resultPath') {
    `$config.TestResult.Enabled = `$true
    `$config.TestResult.OutputFormat = 'JUnitXml'
    `$config.TestResult.OutputPath = '$resultPath'
}
`$r = Invoke-Pester -Configuration `$config
exit (`$r.FailedCount + `$r.FailedContainersCount)
"@
    & pwsh -NoProfile -Command $script
    if ($LASTEXITCODE -ne 0) { throw "Unit tests failed ($LASTEXITCODE failure(s))." }
}

# --- Build -----------------------------------------------------------------------

function Invoke-BuildTask {
    Write-Step "Build: staging the package in $stage"
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    foreach ($item in $packageItems) {
        $source = Join-Path $root $item
        if (-not (Test-Path -LiteralPath $source)) { throw "Missing package item: $item" }
        Copy-Item -LiteralPath $source -Destination $stage -Recurse -Force
    }

    Write-Step 'Build: validating the staged package'
    $stagedManifest = Join-Path $stage "$moduleName.psd1"
    $manifest = Test-ModuleManifest -Path $stagedManifest
    Write-Host "    manifest OK: $($manifest.Name) $($manifest.Version)"

    $publicFiles = @(Get-ChildItem -Path (Join-Path $stage 'Public') -Filter '*.ps1' | ForEach-Object BaseName)
    $declared = @((Import-PowerShellDataFile $stagedManifest).FunctionsToExport)
    $missing = @($declared | Where-Object { $_ -notin $publicFiles })
    $undeclared = @($publicFiles | Where-Object { $_ -notin $declared })
    if ($missing -or $undeclared) {
        throw "FunctionsToExport and Public\*.ps1 disagree. Missing files: $($missing -join ', '). Not in the manifest: $($undeclared -join ', ')."
    }
    Write-Host "    exports OK: $($declared.Count) functions"

    $imported = & pwsh -NoProfile -Command "Import-Module '$stagedManifest' -ErrorAction Stop; (Get-Command -Module $moduleName).Count"
    if ($LASTEXITCODE -ne 0 -or [int]($imported | Select-Object -Last 1) -ne $declared.Count) {
        throw "The staged module did not import cleanly: $imported"
    }
    Write-Host '    clean import OK'

    if (Get-Module -Name PSScriptAnalyzer -ListAvailable) {
        # Errors and warnings, less the exclusions (each with its reason) in
        # PSScriptAnalyzerSettings.psd1.
        $findings = @(Invoke-ScriptAnalyzer -Path $stage -Recurse -Settings (Join-Path $root 'PSScriptAnalyzerSettings.psd1'))
        if ($findings) {
            $findings | Format-Table RuleName, ScriptName, Line, Message -AutoSize | Out-String | Write-Host
            throw "PSScriptAnalyzer reported $($findings.Count) finding(s) - fix them, or exclude a rule with its reason in PSScriptAnalyzerSettings.psd1."
        }
        Write-Host "    PSScriptAnalyzer: no errors or warnings"
    }
    else {
        Write-Warning 'PSScriptAnalyzer is not installed; skipped (Install-PSResource PSScriptAnalyzer).'
    }

    $psData = (Import-PowerShellDataFile $stagedManifest).PrivateData.PSData
    foreach ($key in 'ProjectUri', 'LicenseUri') {
        if (-not $psData.ContainsKey($key) -or -not $psData[$key]) {
            Write-Warning "PrivateData.PSData.$key is not set - the Gallery page will have no link. Set it in $moduleName.psd1 before publishing."
        }
    }

    $size = (Get-ChildItem -LiteralPath $stage -Recurse -File | Measure-Object Length -Sum).Sum
    Write-Host ("    package: {0} files, {1:N1} MB" -f @(Get-ChildItem -LiteralPath $stage -Recurse -File).Count, ($size / 1MB))
}

# --- Publish ---------------------------------------------------------------------

function Invoke-PublishTask {
    $stagedManifest = Join-Path $stage "$moduleName.psd1"
    if (-not (Test-Path -LiteralPath $stagedManifest)) { throw 'Nothing staged - run the Build task first.' }
    if (-not $ApiKey) { throw 'Publishing needs -ApiKey or $env:PSGALLERY_API_KEY.' }
    $version = (Import-PowerShellDataFile $stagedManifest).ModuleVersion

    $existing = Find-PSResource -Name $moduleName -Version $version -Repository $Repository -ErrorAction Ignore
    if ($existing) { throw "$moduleName $version is already on $Repository. Bump ModuleVersion first." }

    if ($PSCmdlet.ShouldProcess("$moduleName $version", "Publish to $Repository")) {
        Write-Step "Publish: $moduleName $version to $Repository"
        Publish-PSResource -Path $stage -Repository $Repository -ApiKey $ApiKey
        Write-Host "    published: https://www.powershellgallery.com/packages/$moduleName/$version"
    }
}

foreach ($name in @('Docs', 'Test', 'Build', 'Publish' | Where-Object { $_ -in $Task })) {
    & "Invoke-${name}Task"
}
