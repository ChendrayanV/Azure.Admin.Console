#Requires -Version 7.2
Set-StrictMode -Version Latest

$moduleRoot = $PSScriptRoot

# $PSScriptRoot inside a dot-sourced *.ps1 resolves to that file's own folder, not
# the module root, so any function that needs the module root (e.g. to find the
# bundled Tests folder or the vendored Spectre.Console.dll) reads this instead.
$script:AACModuleRoot = $moduleRoot

# The active sign-in, set by Connect-AAC and read/refreshed by Get-AACAccessToken.
# It is $global: rather than $script: because Pester runs each test file in its
# own dynamic module, which can't reliably see this module's $script: scope, and
# the bundled Azure tests need the session. Declared here rather than
# left implicitly $null because Set-StrictMode -Version Latest treats reading a
# variable that was never assigned as an error.
$global:AACSession = $null

# Set by Import-AACPdfLibrary once the PDF assemblies in .\lib\pdf are loaded
# (only when a PDF report is first exported).
$script:AACPdfLibraryLoaded = $false

# The live Spectre.Console progress display (Invoke-AACProgress) and its
# tasks by Id (Update-AACProgress); $null when no display is running.
$script:AACProgressContext = $null
$script:AACProgressTasks = @{}
# True while Invoke-AACProgress runs without a live display (output is not
# an interactive terminal): finished tasks are then written as plain lines.
$script:AACProgressPlain = $false

# This module renders its UI with Spectre.Console (https://spectreconsole.net)
# loaded directly from the vendored DLL in .\lib - no PowerShell wrapper module
# in between. That DLL must be loaded before anything else, because a function
# whose parameters are typed as a Spectre.Console type (e.g. [Spectre.Console.Color])
# needs that type resolvable at *parse* time, not just when the function runs.
$spectreConsolePath = Join-Path -Path $moduleRoot -ChildPath 'lib/Spectre.Console.dll'
if (-not (Test-Path -LiteralPath $spectreConsolePath)) {
    throw "Azure Admin Console could not find its vendored Spectre.Console.dll at '$spectreConsolePath'. Reinstall the module."
}
# Pinned SHA-256 of the vendored Spectre.Console 0.49.1 - a swapped or
# tampered DLL is refused rather than loaded. Update it together with the DLL.
$spectreConsoleHash = '26BB8DC1CA36D7ADA9979FFC9DDF658FF48068CEE0154AC540A8870FA7434359'
if ((Get-FileHash -LiteralPath $spectreConsolePath -Algorithm SHA256).Hash -ne $spectreConsoleHash) {
    throw "Azure Admin Console refused to load '$spectreConsolePath': its SHA-256 hash doesn't match the Spectre.Console.dll this module was released with. Reinstall the module."
}
try {
    Add-Type -Path $spectreConsolePath -ErrorAction Stop
}
catch {
    throw "Azure Admin Console failed to load Spectre.Console.dll: $($_.Exception.Message)"
}

# Load order matters: Private helpers first, then the public, exported
# commands that use them.
foreach ($folder in 'Private', 'Public') {
    $folderPath = Join-Path -Path $moduleRoot -ChildPath $folder
    if (-not (Test-Path -LiteralPath $folderPath)) {
        continue
    }

    $files = Get-ChildItem -LiteralPath $folderPath -Filter '*.ps1' -File | Sort-Object -Property Name
    foreach ($file in $files) {
        try {
            . $file.FullName
        }
        catch {
            throw "Azure Admin Console failed to load '$($file.FullName)': $($_.Exception.Message)"
        }
    }
}

# Export-AACFirewallRule's objects carry ~35 properties (all of them go to
# CSV); at the console show a readable table by default. Select-Object * or
# Format-List * shows everything.
Update-TypeData -TypeName 'AAC.FirewallRule' -DefaultDisplayPropertySet 'FirewallPolicy', 'RuleCollection', 'RuleName', 'Action' -Force
# Same for Get-AACAdvisorRecommendation's ~25 (or more, with Ext_ columns).
Update-TypeData -TypeName 'AAC.AdvisorRecommendation' -DefaultDisplayPropertySet 'Category', 'Impact', 'ResourceName', 'Problem' -Force

$publicFunctionNames = Get-ChildItem -LiteralPath (Join-Path -Path $moduleRoot -ChildPath 'Public') -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty BaseName

Export-ModuleMember -Function $publicFunctionNames
