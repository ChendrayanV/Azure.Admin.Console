<#
    Builds the two files that tell AI tools what is in the repository, following
    https://llmstxt.org:

      llms.txt        what the module is, with a link to every guide page and
                      every command's reference, each as plain Markdown
      llms-full.txt   the guide pages and every command's reference, in one file

    Both come from GUIDE.md, docs\guide\ and the pages PlatyPS has just written,
    so run by build.ps1 -Task Docs, after tools\Build-Help.ps1. Don't edit them by
    hand: CI fails when they don't match what this writes. No dates, so they only
    change when the docs do.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ModuleManifest,
    [Parameter(Mandatory)] [string] $Root
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$manifest = Import-PowerShellDataFile -LiteralPath $ModuleManifest
$moduleName = [System.IO.Path]::GetFileNameWithoutExtension($ModuleManifest)
$projectUri = ([string]$manifest.PrivateData.PSData.ProjectUri).TrimEnd('/')
# Raw files, not GitHub's pages: a tool reading these wants the Markdown.
$rawRoot = [uri]($projectUri.Replace('https://github.com/', 'https://raw.githubusercontent.com/') + '/main/')
$summary = 'A PowerShell 7.2+ module for Azure, Microsoft 365 and Azure DevOps administration over plain REST: no Az or Microsoft.Graph modules and no app registration. Read-only by default; every command gives a console view, typed objects, and CSV, HTML and PDF reports.'

function Read-Markdown([string] $Path) {
    ([System.IO.File]::ReadAllText($Path) -replace "`r`n", "`n").TrimEnd()
}

# A link in a page -> the same link from anywhere. Code fences are left as they are.
function ConvertTo-AbsoluteLink([string] $Markdown, [string] $RelativePath) {
    $page = [uri]::new($rawRoot, $RelativePath)
    $inFence = $false
    $lines = foreach ($line in $Markdown -split "`n") {
        if ($line -match '^\s*```') { $inFence = -not $inFence }
        if ($inFence) { $line; continue }
        [regex]::Replace($line, '\]\((?!https?:|mailto:|#)([^)\s]+)\)', { param($Match) '](' + [uri]::new($page, $Match.Groups[1].Value).AbsoluteUri + ')' })
    }
    $lines -join "`n"
}

# The guide's pages, in the index's order. A page the index leaves out stops the
# build: nobody would find it.
$guideIndex = Read-Markdown (Join-Path -Path $Root -ChildPath 'GUIDE.md')
$guide = @([regex]::Matches($guideIndex, '(?m)^- \[(?<title>[^\]]+)\]\(docs/guide/(?<file>[^)#]+\.md)\)$') | ForEach-Object {
        [pscustomobject]@{ Title = $_.Groups['title'].Value; Path = "docs/guide/$($_.Groups['file'].Value)" }
    })
$onDisk = @(Get-ChildItem -LiteralPath (Join-Path -Path $Root -ChildPath 'docs/guide') -Filter '*.md' -File | ForEach-Object { "docs/guide/$($_.Name)" })
$notIndexed = @($onDisk | Where-Object { $_ -notin $guide.Path })
if ($notIndexed) { throw "Azure Admin Console's guide index doesn't list $($notIndexed -join ', '). Add them to the topics in GUIDE.md." }
$noPage = @($guide.Path | Where-Object { $_ -notin $onDisk })
if ($noPage) { throw "Azure Admin Console's guide index lists $($noPage -join ', '), which don't exist. Fix the topics in GUIDE.md." }

# The commands by area, from the index PlatyPS's run has just written.
$areas = [System.Collections.Generic.List[object]]::new()
foreach ($line in (Read-Markdown (Join-Path -Path $Root -ChildPath "docs/$moduleName.md")) -split "`n") {
    if ($line -match '^### (.+)$') {
        $areas.Add([pscustomobject]@{ Title = $Matches[1]; Commands = [System.Collections.Generic.List[object]]::new() })
    }
    elseif ($areas.Count -and $line -match '^\| \[(?<name>[^\]]+)\]\([^)]+\) \| (?<synopsis>.*) \|$') {
        $areas[-1].Commands.Add([pscustomobject]@{ Name = $Matches['name']; Synopsis = ($Matches['synopsis'] -replace '\\\|', '|'); Path = "docs/$($Matches['name']).md" })
    }
}
$commandCount = ($areas | ForEach-Object { $_.Commands.Count } | Measure-Object -Sum).Sum
if (-not $commandCount) { throw "Azure Admin Console found no commands in docs/$moduleName.md. Run ./build.ps1 -Task Docs." }

# --- llms.txt ---------------------------------------------------------------------
$short = [System.Collections.Generic.List[string]]::new()
$short.Add("# $moduleName")
$short.Add('')
$short.Add("> $summary")
$short.Add('')
$short.Add("Version $($manifest.ModuleVersion), $commandCount commands. Install with ``Install-PSResource -Name $moduleName``, sign in with ``Connect-AAC``. Inside PowerShell, ``Get-Help <command> -Full`` gives the same reference as the pages below.")
$short.Add('')
$short.Add('## Guide')
$short.Add('')
foreach ($page in $guide) { $short.Add("- [$($page.Title)]($($rawRoot)$($page.Path))") }
foreach ($area in $areas) {
    $short.Add('')
    $short.Add("## Commands: $($area.Title)")
    $short.Add('')
    foreach ($command in $area.Commands) { $short.Add("- [$($command.Name)]($($rawRoot)$($command.Path)): $($command.Synopsis)") }
}
$short.Add('')
$short.Add('## Optional')
$short.Add('')
$short.Add("- [Everything in one file]($($rawRoot)llms-full.txt): the guide and every command's reference")
$short.Add("- [Contributing]($($rawRoot)AGENTS.md): how the code is laid out, its rules, and how to add a command")
$short.Add("- [Changelog]($($rawRoot)CHANGELOG.md): what changed in each release")
$short.Add("- [Third-party notices]($($rawRoot)THIRD-PARTY-NOTICES.md): the data and libraries that ship with the module")

# --- llms-full.txt ----------------------------------------------------------------
$full = [System.Collections.Generic.List[string]]::new()
$full.Add("# $moduleName")
$full.Add('')
$full.Add("> $summary")
$full.Add('')
$full.Add("Version $($manifest.ModuleVersion). The guide comes first, then the reference for each of the $commandCount commands.")
foreach ($path in @($guide.Path) + @($areas | ForEach-Object { $_.Commands.Path })) {
    # PlatyPS's front matter is for its own tools.
    $body = (Read-Markdown (Join-Path -Path $Root -ChildPath $path)) -replace '(?s)\A---\n.*?\n---\n+', ''
    $full.Add('')
    $full.Add("<!-- Source: $($rawRoot)$path -->")
    $full.Add('')
    $full.Add((ConvertTo-AbsoluteLink -Markdown $body -RelativePath $path))
}

$utf8 = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText((Join-Path -Path $Root -ChildPath 'llms.txt'), ($short -join "`n") + "`n", $utf8)
[System.IO.File]::WriteAllText((Join-Path -Path $Root -ChildPath 'llms-full.txt'), ($full -join "`n") + "`n", $utf8)
Write-Host "    llms.txt, llms-full.txt ($($guide.Count) guide pages, $commandCount commands)"
