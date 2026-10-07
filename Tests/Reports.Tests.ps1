<#
    Unit tests for what every report shares: the HTML page's collapsible
    tables (Private\DataReport.html) and the PDF bookmarks
    (Save-AACPdfDocument, Set-AACPdfOutline).
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
    $script:canWritePdf = $IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4'
}

BeforeAll {
    $script:canWritePdf = $IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4'
}

Describe 'Azure Admin Console - collapsible tables in the HTML reports' {
    BeforeAll {
        $script:template = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../Private/DataReport.html') -Raw
        $script:page = Join-Path $TestDrive 'report.html'
        $null = InModuleScope 'Azure.Admin.Console' -Parameters @{ Path = $script:page } {
            param($Path)
            Write-AACHtmlReport -Path $Path -Title 'Report' -Tile @(@{ Value = '1'; Label = 'rows'; Table = 't1' }) -Table @(
                @{ Id = 't1'; Title = 'First table'; Noun = 'things'; Rows = @(@{ A = 'x' }); Columns = @(@{ Key = 'A'; Label = 'A' }) }
                @{ Id = 't2'; Title = 'Second table'; Rows = @(); Columns = @(@{ Key = 'A'; Label = 'A' }) }
            )
        }
    }

    It 'starts every table collapsed, its header a keyboard-operable toggle' {
        $script:template | Should -Match "el\('section', 'tbl collapsed'\)"
        $script:template | Should -Match "section\.tbl\.collapsed \.tbl-body \{ display: none; \}"
        $script:template | Should -Match "setAttribute\('role', 'button'\)"
        $script:template | Should -Match "setAttribute\('aria-expanded', 'false'\)"
        $script:template | Should -Match "e\.key === 'Enter' \|\| e\.key === ' '"
    }

    It 'opens a table when a tile, chart or tree link filters it, and offers expand and collapse all' {
        $script:template | Should -Match "function focusTable\(id, filters\) \{\s+var t = tables\[id\]; if \(!t\) return;\s+if \(showTabOf\) showTabOf\(t\.section\);\s+t\.setOpen\(true\);"
        $script:template | Should -Match 'Expand all tables'
        $script:template | Should -Match 'Collapse all tables'
    }

    It 'prints every table, collapsed or not' {
        $print = [regex]::Match($script:template, '@media print \{(.+?)\n\}', 'Singleline').Groups[1].Value
        $print | Should -Match 'section\.tbl\.collapsed \.tbl-body \{ display: block !important; \}'
        $print | Should -Match '\.tbl-bulk'
    }

    It 'scrolls each table in its own box - the header row and first column stay put' {
        $script:template | Should -Match '\.scroller \{ overflow: auto; max-height: var\(--table-max\);'
        $script:template | Should -Match 'th \{ position: sticky; top: 0;'
        $script:template | Should -Match 'th\.pin, td\.pin \{ position: sticky; left: 0;'
        $script:template | Should -Match "i === 0 \? ' pin' : ''"
    }

    It 'fits the window on wide screens and compacts rows on short ones, unless the viewer chose (remembered)' {
        $script:template | Should -Match '@media \(min-width: 1600px\) \{ :root:not\(\[data-width\]\) \{ --page-max: none;'
        $script:template | Should -Match '@media \(max-height: 900px\) \{ :root:not\(\[data-density\]\) \{ --cell-y: 3px;'
        $script:template | Should -Match '\.wrap \{ max-width: var\(--page-max\);'
        $script:template | Should -Match "key: 'aac-width'"
        $script:template | Should -Match "key: 'aac-density'"
        $script:template | Should -Match 'id="width"'
        $script:template | Should -Match 'id="density"'
    }

    It 'opens a row''s every field - hidden columns too - in a details panel, Esc to close, arrows to move' {
        $script:template | Should -Match 'role="dialog" aria-modal="true"'
        $script:template | Should -Match "openDrawer\(T\.title, cols, shownRows\.slice\(\), index, mark\)"
        $script:template | Should -Match "if \(c\.hidden\) dt\.appendChild\(el\('span', 'hid', 'not in the table'\)\)"
        $script:template | Should -Match "e\.key === 'Escape'"
        $script:template | Should -Match "e\.key === 'ArrowDown' \|\| e\.key === 'ArrowUp'"
        $script:template | Should -Match "if \(e\.target\.closest\('a, button'\)\) return;"
    }

    It 'prints at full width: no scroll boxes, pinned columns, clamps or panel' {
        $print = [regex]::Match($script:template, '@media print \{(.+?)\n\}', 'Singleline').Groups[1].Value
        $print | Should -Match '\.scroller \{ overflow: visible; max-height: none;'
        $print | Should -Match '\.drawer, \.drawer-bg'
        $print | Should -Match 'td\.wide \.clamp \{ display: block;'
        $print | Should -Match 'td\.txt \{ white-space: normal;'
    }

    It 'turns sections into tabs when a report asks: Overview first, the tab in the URL, a filtered table opening its tab' {
        $script:template | Should -Match "if \(D\.tabs && sectionOrder\.length\)"
        $script:template | Should -Match "var names = \['Overview'\]"
        $script:template | Should -Match "history\.replaceState\(null, '', '#tab=' \+ encodeURIComponent\(name\)\)"
        $script:template | Should -Match "e\.key === 'ArrowRight'"
        $script:template | Should -Match '@media screen \{ \.tab-off \{ display: none !important; \} \}' -Because 'printed, every tab is'
        $tabbed = Join-Path $TestDrive 'tabbed.html'
        $null = InModuleScope 'Azure.Admin.Console' -Parameters @{ Path = $tabbed } {
            param($Path)
            Write-AACHtmlReport -Path $Path -Title 'Tabs' -Tab @(@{ Name = 'Second'; Badge = '3'; Tone = 'bad' }) -Table @(
                @{ Id = 'a'; Title = 'A'; Section = 'First'; Rows = @(@{ A = 'x' }); Columns = @(@{ Key = 'A'; Label = 'A' }) }
                @{ Id = 'b'; Title = 'B'; Section = 'Second'; Rows = @(@{ A = 'p → q' }); Columns = @(@{ Key = 'A'; Label = 'A'; Type = 'path' }) }
            )
        }
        $tabs = [regex]::Match((Get-Content -LiteralPath $tabbed -Raw), '"tabs":\[\{[^\]]+\]').Value
        $tabs | Should -Match '"name":"Second"'
        $tabs | Should -Match '"badge":"3"'
        $tabs | Should -Match '"tone":"bad"'
    }

    It 'is the page every command writes' {
        $html = Get-Content -LiteralPath $script:page -Raw
        $html | Should -Match "el\('section', 'tbl collapsed'\)"
        $html | Should -Match 'First table'
    }
}

Describe 'Azure Admin Console - PDF bookmarks' {
    It 'bookmarks every heading, nested by level - skipped levels without blank entries - collapsed, and opens with the bookmarks panel' -Skip:(-not $script:canWritePdf) {
        $path = Join-Path $TestDrive 'outline.pdf'
        $tree = InModuleScope 'Azure.Admin.Console' -Parameters @{ Path = $path } {
            param($Path)
            $pdf = New-AACPdfDocument -Title 'Outline'
            & $pdf.AddTitle 'Bookmarks'
            $section = $pdf.Section
            # As the reports write them: sections at Heading2 before any
            # Heading1, Heading3 straight under a Heading1.
            foreach ($heading in @(@('Summary', 2), @('Findings', 2), @('nsg-web', 1), @('Inbound rules', 3), @('Outbound rules', 3), @('nsg-data', 1), @('Associations', 2), @('Inbound rules', 3))) {
                if ($heading[0] -eq 'nsg-data') { $section.AddPageBreak() }
                $section.AddParagraph($heading[0], "Heading$($heading[1])") | Out-Null
                $section.AddParagraph('text') | Out-Null
            }
            $null = Save-AACPdfDocument -Pdf $pdf -Path $Path
            $document = [PdfSharp.Pdf.IO.PdfReader]::Open($Path, [PdfSharp.Pdf.IO.PdfDocumentOpenMode]::Import)
            $lines = [System.Collections.Generic.List[string]]::new()
            $walk = { param($Items, [int] $Depth) foreach ($item in $Items) { $lines.Add(('{0}{1} {2}' -f ('  ' * $Depth), $item.Title, $item.Elements.GetInteger('/Count'))); & $walk $item.Outlines ($Depth + 1) } }
            & $walk $document.Outlines 0
            @{ Lines = $lines.ToArray(); PageMode = $document.Internals.Catalog.Elements.GetName('/PageMode') }
        }
        $tree.Lines | Should -Be @(
            'Summary 0'
            'Findings 0'
            'nsg-web -2'
            '  Inbound rules 0'
            '  Outbound rules 0'
            'nsg-data -2'
            '  Associations -1'
            '    Inbound rules 0'
        ) -Because 'a negative count is a collapsed bookmark hiding that many entries'
        $tree.PageMode | Should -Be '/UseOutlines'
    }
}
