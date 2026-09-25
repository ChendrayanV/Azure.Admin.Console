#Requires -Version 7.4
<#
.SYNOPSIS
    Builds Azure.Admin.Console: regenerates the docs, runs the unit tests,
    stages a clean package and (only when asked) publishes it to the
    PowerShell Gallery.
.DESCRIPTION
    Tasks, run in this order:

      Docs      Writes docs\<Command>.md for every exported command and
                docs\Azure.Admin.Console.md (the index) from the
                comment-based help in Public\*.ps1, and docs\about_*.md
                from en-US\about_*.help.txt. The comment-based help is the
                one source of truth - edit it, then rerun this task.
      Test      Runs the unit tests in Tests\ (no Azure sign-in needed) and
                stops the build if any fail. -TestResultPath also writes
                JUnit XML for CI.
      Build     Copies only what the module needs at run time into
                out\Azure.Admin.Console, then validates the staged copy:
                Test-ModuleManifest, every exported function has a
                Public\*.ps1 file, a clean import in a fresh pwsh, and
                PSScriptAnalyzer errors (if it is installed). Tests\,
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
    Only regenerates the Markdown help after editing a command's help.
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
    'Public'
    'Private'
    'Checks'
    'lib'
    'en-US'
    'LICENSE'
    'README.md'
    'CHANGELOG.md'
)

function Write-Step([string] $Message) { Write-Host "==> $Message" -ForegroundColor Cyan }

# --- Docs ------------------------------------------------------------------------

# Comment-based help text -> Markdown. Lines indented by two or more spaces
# (the aligned "name   description" tables and numbered layouts the help
# uses) become fenced text blocks so they keep their alignment; everything
# else is ordinary paragraphs, with <, > and * escaped.
function ConvertTo-AACMarkdownText([string] $Text) {
    $escape = { param([string] $Line) $Line -replace '([<>*])', '\$1' }
    $out = [System.Collections.Generic.List[string]]::new()
    $lines = @(($Text -replace "`r", '').Trim("`n") -split "`n")
    $inBlock = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i].TrimEnd()
        $indented = $line -match '^\s{2,}\S'
        if ($indented -and -not $inBlock) {
            $out.Add('```text')
            $inBlock = $true
        }
        elseif ($inBlock -and -not $indented) {
            # A blank line inside a block ends it only when the next
            # non-blank line isn't indented too.
            $next = if ($i + 1 -lt $lines.Count) { @($lines[($i + 1)..($lines.Count - 1)] | Where-Object { $_.Trim() }) | Select-Object -First 1 }
            if ($line -eq '' -and $next -match '^\s{2,}\S') {
                $out.Add('')
                continue
            }
            $out.Add('```')
            $inBlock = $false
            if ($line -ne '') { $out.Add('') }
        }
        $out.Add($(if ($inBlock) { $line } else { & $escape $line }))
    }
    if ($inBlock) { $out.Add('```') }
    $out -join "`n"
}

function Get-AACParameterDefault([System.Management.Automation.Language.FunctionDefinitionAst] $Ast, [string] $Name) {
    $parameter = @($Ast.Body.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq $Name })
    if ($parameter -and $parameter[0].DefaultValue) { $parameter[0].DefaultValue.Extent.Text } else { 'None' }
}

function Export-AACCommandMarkdown([System.Management.Automation.FunctionInfo] $Command) {
    $help = $Command.ScriptBlock.Ast.GetHelpContent()
    if (-not $help) { throw "$($Command.Name) has no comment-based help." }
    $ast = $Command.ScriptBlock.Ast
    $common = [System.Management.Automation.Cmdlet]::CommonParameters + [System.Management.Automation.Cmdlet]::OptionalCommonParameters

    $md = [System.Collections.Generic.List[string]]::new()
    $md.Add("# $($Command.Name)")
    $md.Add('')
    $md.Add("[$moduleName]($moduleName.md) · [about_$moduleName](about_$moduleName.md)")
    $md.Add('')
    $md.Add('## Synopsis')
    $md.Add('')
    $md.Add((($help.Synopsis.Trim() -split '\s*\r?\n\s*') -join ' '))
    $md.Add('')
    $md.Add('## Syntax')
    $md.Add('')
    foreach ($set in $Command.ParameterSets) {
        $md.Add('```powershell')
        $md.Add("$($Command.Name) $set")
        $md.Add('```')
        $md.Add('')
    }
    $md.Add('## Description')
    $md.Add('')
    $md.Add((ConvertTo-AACMarkdownText $help.Description))
    $md.Add('')

    if ($help.Examples.Count) {
        $md.Add('## Examples')
        $md.Add('')
        $number = 0
        foreach ($example in $help.Examples) {
            $number++
            $lines = @(($example -replace "`r", '').Trim() -split "`n")
            # The help's convention: the code, then one line saying what it
            # does. A one-line example is all code.
            $code = $lines
            $remark = ''
            if ($lines.Count -gt 1 -and $lines[-1] -cmatch '^[A-Z][a-z]' -and $lines[-1] -cnotmatch '^[A-Z][a-z]+-[A-Z]') {
                $code = $lines[0..($lines.Count - 2)]
                $remark = $lines[-1]
            }
            $md.Add("### Example $number")
            $md.Add('')
            $md.Add('```powershell')
            foreach ($line in $code) { $md.Add($line.TrimEnd()) }
            $md.Add('```')
            $md.Add('')
            if ($remark) {
                $md.Add((ConvertTo-AACMarkdownText $remark))
                $md.Add('')
            }
        }
    }

    $parameters = @($Command.Parameters.Values | Where-Object { $_.Name -notin $common })
    if ($parameters.Count) {
        $md.Add('## Parameters')
        $md.Add('')
        # Declaration order, as in the syntax block.
        $order = @($ast.Body.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
        foreach ($parameter in @($parameters | Sort-Object { $order.IndexOf($_.Name) })) {
            $attribute = @($parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }) | Select-Object -First 1
            if (-not $attribute) { $attribute = [System.Management.Automation.ParameterAttribute]::new() }
            $validateSet = @($parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] })
            $wildcards = @($parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.SupportsWildcardsAttribute] }).Count -gt 0
            $pipeline = @(if ($attribute.ValueFromPipeline) { 'ByValue' }; if ($attribute.ValueFromPipelineByPropertyName) { 'ByPropertyName' })
            $text = $help.Parameters[$parameter.Name.ToUpperInvariant()]

            $md.Add("### -$($parameter.Name)")
            $md.Add('')
            $md.Add($(if ($text) { ConvertTo-AACMarkdownText $text } else { '_No description._' }))
            $md.Add('')
            $md.Add('| | |')
            $md.Add('|---|---|')
            $md.Add("| Type | ``$($parameter.ParameterType.Name)`` |")
            if ($validateSet) {
                $values = ($validateSet[0].ValidValues | ForEach-Object { '`' + $_ + '`' }) -join ', '
                $md.Add("| Accepted values | $values |")
            }
            $md.Add("| Required | $(if ($attribute.Mandatory) { 'Yes' } else { 'No' }) |")
            $md.Add("| Position | $(if ($attribute.Position -ge 0) { $attribute.Position } else { 'Named' }) |")
            $default = if ($parameter.SwitchParameter) { 'False' } else { Get-AACParameterDefault $ast $parameter.Name }
            $md.Add("| Default value | ``$($default -replace '\|', '\|')`` |")
            $md.Add("| Accepts pipeline input | $(if ($pipeline) { $pipeline -join ', ' } else { 'No' }) |")
            $md.Add("| Accepts wildcards | $(if ($wildcards) { 'Yes' } else { 'No' }) |")
            $md.Add('')
        }
        $md.Add('### CommonParameters')
        $md.Add('')
        $md.Add('This command supports the common parameters (`-Verbose`, `-ErrorAction`, `-WarningAction` and so on). See [about_CommonParameters](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_commonparameters).')
        $md.Add('')
    }

    $outputs = @($help.Outputs | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($outputs.Count) {
        $md.Add('## Outputs')
        $md.Add('')
        foreach ($output in $outputs) { $md.Add((ConvertTo-AACMarkdownText $output)); $md.Add('') }
    }
    if ($help.Notes) {
        $md.Add('## Notes')
        $md.Add('')
        $md.Add((ConvertTo-AACMarkdownText $help.Notes))
        $md.Add('')
    }

    ($md -join "`n").TrimEnd() + "`n"
}

function Invoke-DocsTask {
    Write-Step 'Docs: generating docs\*.md from comment-based help'
    Import-Module $manifestPath -Force
    $commands = @(Get-Command -Module $moduleName -CommandType Function | Sort-Object Name)
    New-Item -ItemType Directory -Path $docs -Force | Out-Null

    foreach ($command in $commands) {
        $path = Join-Path $docs "$($command.Name).md"
        Set-Content -LiteralPath $path -Value (Export-AACCommandMarkdown $command) -Encoding utf8NoBOM -NoNewline
        Write-Host "    $($command.Name).md"
    }

    # about_ topics: the .help.txt in en-US is the source (it is what
    # Get-Help about_Azure.Admin.Console shows); docs\ gets a readable copy.
    foreach ($about in @(Get-ChildItem -Path (Join-Path $root 'en-US') -Filter 'about_*.help.txt' -File)) {
        $name = $about.Name -replace '\.help\.txt$', ''
        $body = "# $name`n`n[$moduleName]($moduleName.md)`n`n``````text`n$((Get-Content -LiteralPath $about.FullName -Raw).TrimEnd())`n```````n"
        Set-Content -LiteralPath (Join-Path $docs "$name.md") -Value $body -Encoding utf8NoBOM -NoNewline
        Write-Host "    $name.md"
    }

    $manifest = Import-PowerShellDataFile $manifestPath
    $index = [System.Collections.Generic.List[string]]::new()
    $index.Add("# $moduleName $($manifest.ModuleVersion)")
    $index.Add('')
    $index.Add($manifest.Description)
    $index.Add('')
    $index.Add("Start with [about_$moduleName](about_$moduleName.md), or ``Get-Help about_$moduleName`` once the module is imported.")
    $index.Add('')
    $index.Add('## Commands')
    $index.Add('')
    $index.Add('| Command | Synopsis |')
    $index.Add('|---|---|')
    foreach ($command in $commands) {
        $synopsis = (($command.ScriptBlock.Ast.GetHelpContent().Synopsis.Trim() -split '\s*\r?\n\s*') -join ' ') -replace '\|', '\|'
        $index.Add("| [$($command.Name)]($($command.Name).md) | $synopsis |")
    }
    Set-Content -LiteralPath (Join-Path $docs "$moduleName.md") -Value (($index -join "`n") + "`n") -Encoding utf8NoBOM -NoNewline
    Write-Host "    $moduleName.md"
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
        $findings = @(Invoke-ScriptAnalyzer -Path $stage -Recurse -Severity Error)
        if ($findings) {
            $findings | Format-Table RuleName, ScriptName, Line, Message -AutoSize | Out-String | Write-Host
            throw "PSScriptAnalyzer reported $($findings.Count) error(s)."
        }
        Write-Host '    PSScriptAnalyzer: no errors'
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
