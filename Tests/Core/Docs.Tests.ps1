<#
    Unit tests for the hand-written docs: GUIDE.md is the index of docs\guide, so
    every command has to be in it and every link has to lead somewhere. Nothing
    signs in: these only read files in the repository.
#>

BeforeAll {
    $script:root = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $script:guideIndex = Get-Content -LiteralPath (Join-Path -Path $script:root -ChildPath 'GUIDE.md') -Raw
    $script:pages = @(
        Get-Item -LiteralPath (Join-Path -Path $script:root -ChildPath 'GUIDE.md'), (Join-Path -Path $script:root -ChildPath 'README.md'), (Join-Path -Path $script:root -ChildPath 'AGENTS.md'), (Join-Path -Path $script:root -ChildPath 'THIRD-PARTY-NOTICES.md')
        Get-ChildItem -LiteralPath (Join-Path -Path $script:root -ChildPath 'docs/guide') -Filter '*.md' -File
    )
    # As GitHub makes a heading's anchor.
    $script:anchorOf = { param([string] $Heading) (($Heading.Trim().ToLowerInvariant() -replace '[^a-z0-9 _-]', '') -replace ' ', '-') }
    # A page's text without its code fences: a link in an example isn't a link.
    $script:prose = {
        param([string] $Path)
        $inFence = $false
        foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
            if ($line -match '^\s*```') { $inFence = -not $inFence; continue }
            if (-not $inFence) { $line }
        }
    }
}

Describe 'Azure Admin Console - the guide' {
    It 'lists every exported command in its tables, with a link to its reference' {
        $manifest = Import-PowerShellDataFile -LiteralPath (Join-Path -Path $script:root -ChildPath 'Azure.Admin.Console.psd1')
        $missing = @($manifest.FunctionsToExport | Where-Object { -not $script:guideIndex.Contains("[``$_``](docs/$_.md)") })
        $missing | Should -BeNullOrEmpty -Because 'GUIDE.md is how people find a command'
    }

    It 'lists every page of docs\guide in its topics' {
        foreach ($page in @($script:pages | Where-Object { $_.DirectoryName -match 'guide$' })) {
            $script:guideIndex.Contains("(docs/guide/$($page.Name))") | Should -BeTrue -Because "$($page.Name) would otherwise be out of reach"
        }
    }

    It 'has links and anchors that lead somewhere' {
        $broken = [System.Collections.Generic.List[string]]::new()
        foreach ($page in $script:pages) {
            $text = @(& $script:prose $page.FullName) -join "`n"
            foreach ($match in [regex]::Matches($text, '\]\((?!https?:|mailto:)(?<path>[^)#\s]*)(?:#(?<anchor>[^)\s]+))?\)')) {
                $target = if ($match.Groups['path'].Value) { Join-Path -Path $page.DirectoryName -ChildPath $match.Groups['path'].Value } else { $page.FullName }
                if (-not (Test-Path -LiteralPath $target)) { $broken.Add("$($page.Name): $($match.Value)"); continue }
                if ($match.Groups['anchor'].Success -and $target -match '\.md$') {
                    $anchors = @(& $script:prose $target | Where-Object { $_ -match '^#{1,6} ' } | ForEach-Object { & $script:anchorOf ($_ -replace '^#+ ', '') })
                    if ($match.Groups['anchor'].Value -notin $anchors) { $broken.Add("$($page.Name): $($match.Value)") }
                }
            }
        }
        $broken | Should -BeNullOrEmpty
    }
}

Describe 'Azure Admin Console - the llms files' {
    It 'link to every command and carry each page, and name the current version' {
        $manifest = Import-PowerShellDataFile -LiteralPath (Join-Path -Path $script:root -ChildPath 'Azure.Admin.Console.psd1')
        $short = Get-Content -LiteralPath (Join-Path -Path $script:root -ChildPath 'llms.txt') -Raw
        $full = Get-Content -LiteralPath (Join-Path -Path $script:root -ChildPath 'llms-full.txt') -Raw
        $short | Should -Match "Version $([regex]::Escape($manifest.ModuleVersion))"
        @($manifest.FunctionsToExport | Where-Object { -not $short.Contains("[$_](") }) | Should -BeNullOrEmpty
        @($manifest.FunctionsToExport | Where-Object { -not $full.Contains("/docs/$_.md -->") }) | Should -BeNullOrEmpty
        foreach ($page in @($script:pages | Where-Object { $_.DirectoryName -match 'guide$' })) { $full.Contains("/docs/guide/$($page.Name) -->") | Should -BeTrue }
    }
}

Describe 'Azure Admin Console - third-party notices' {
    It 'names the commit and copyright of each project whose data ships with the module' {
        $data = Get-Content -LiteralPath (Join-Path -Path $script:root -ChildPath 'src/Azure/Private/ServiceBaseline.json') -Raw | ConvertFrom-Json -AsHashtable
        $notice = Get-Content -LiteralPath (Join-Path -Path $script:root -ChildPath 'THIRD-PARTY-NOTICES.md') -Raw
        foreach ($set in 'Alerts', 'Resiliency') {
            $notice.Contains($data.Sources[$set].Commit) | Should -BeTrue -Because "a refresh of the $set data has to update the notice"
            $notice.Contains($data.Sources[$set].Name) | Should -BeTrue
        }
        $notice | Should -Match 'Copyright \(c\) Microsoft Corporation'
    }

    It 'ships in the package' {
        (Get-Content -LiteralPath (Join-Path -Path $script:root -ChildPath 'build.ps1') -Raw) | Should -Match "'THIRD-PARTY-NOTICES\.md'"
    }
}
