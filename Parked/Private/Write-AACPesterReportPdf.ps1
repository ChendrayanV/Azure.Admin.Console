function Write-AACPesterReportPdf {
    <#
    .SYNOPSIS
        Writes a Pester v5 result as a PDF report: a summary page, pass/fail
        counts per check, and every test result with the reason for each
        failure. Used by Invoke-AACPester -PdfPath.
    .DESCRIPTION
        Renders an A4 PDF from the object Invoke-Pester -PassThru returns:

          1. Summary: title, when and where it ran (with the Azure account
             and tenant when Connect-AAC is signed in), a PASSED/FAILED
             verdict, total/passed/failed/skipped/pass-rate tiles and a
             proportion bar.
          2. Results by check: one row per Describe/Context with its test,
             passed, failed and skipped counts - the quickest way to see
             which rules fail most.
          3. Test results: one table per test file and Describe block, each
             test marked PASS, FAIL or SKIP, with the failure message or skip
             reason directly under the test it belongs to.

        With -FailedOnly the results tables list only failed tests; the
        summary and per-check counts still cover every test.

        The PDF is drawn with PDFsharp + MigraDoc (MIT), vendored in
        lib\pdf and loaded only when a report is exported, after every DLL
        has been checked against a pinned SHA-256 hash. Needs Windows (for
        its fonts) and PowerShell 7.4 or later.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $PesterResult,

        [Parameter(Mandatory)]
        [string] $Path,

        [string] $Title = 'Azure Admin Console test report',

        [System.Collections.IDictionary] $Detail,

        [switch] $FailedOnly
    )

    process {
        if (-not (Get-AACPropertyValue -InputObject $PesterResult -Name 'Containers')) {
            throw 'PesterResult must be the object returned by Invoke-AACPester -PassThru or Invoke-Pester -PassThru.'
        }

        $fullPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

        $formatDuration = {
            param([TimeSpan] $Duration)
            if ($Duration.TotalMilliseconds -lt 1000) { '{0:N0} ms' -f $Duration.TotalMilliseconds }
            elseif ($Duration.TotalMinutes -lt 1) { '{0:N2} s' -f $Duration.TotalSeconds }
            else { '{0:N1} min' -f $Duration.TotalMinutes }
        }
        $errorText = {
            param([object] $Record, [int] $MaxLines = 15)
            $errors = @(Get-AACPropertyValue -InputObject $Record -Name 'ErrorRecord')
            if ($errors.Count -eq 0 -or -not $errors[0]) {
                return ''
            }
            $lines = @(([string]$errors[0].Exception.Message).Trim() -split "`r?`n")
            if ($lines.Count -gt $MaxLines) {
                $lines = @($lines | Select-Object -First $MaxLines) + "... ($($lines.Count - $MaxLines) more lines)"
            }
            $lines
        }
        $addLines = {
            param($Paragraph, [string[]] $Lines)
            for ($i = 0; $i -lt $Lines.Count; $i++) {
                if ($i -gt 0) { $Paragraph.AddLineBreak() | Out-Null }
                $Paragraph.AddText($Lines[$i]) | Out-Null
            }
        }

        # --- Gather the results -----------------------------------------------------
        $collectTests = {
            param([object] $Block, [string[]] $Trail)
            foreach ($test in $Block.Tests) {
                [pscustomobject]@{ Test = $test; Group = ($Trail -join ' / ') }
            }
            foreach ($child in $Block.Blocks) {
                & $collectTests $child (@($Trail) + [string]$child.ExpandedName)
            }
        }
        $containers = @(Get-AACPropertyValue -InputObject $PesterResult -Name 'Containers')
        $files = @(foreach ($container in $containers) {
                $isBroken = [string]$container.Result -eq 'Failed' -and @($container.Blocks).Count -eq 0
                [pscustomobject]@{
                    Name     = Split-Path -Path ([string]$container.Item) -Leaf
                    Broken   = $isBroken
                    Error    = if ($isBroken) { & $errorText $container } else { @() }
                    Count    = Get-AACPesterOutcomeCount -Node $container
                    Blocks   = @(foreach ($block in $container.Blocks) {
                            $entries = @(& $collectTests $block @() | Where-Object { [string]$_.Test.Result -in 'Passed', 'Failed', 'Skipped' })
                            if ($entries.Count -gt 0) {
                                [pscustomobject]@{ Name = [string]$block.ExpandedName; Entries = $entries }
                            }
                        })
                }
            })

        $passed = [int]$PesterResult.PassedCount
        $failed = [int]$PesterResult.FailedCount + @($files | Where-Object Broken).Count
        $skipped = [int]$PesterResult.SkippedCount
        $ran = $passed + $failed + $skipped
        $decided = $passed + $failed
        $passRate = if ($decided -gt 0) { '{0:N1}%' -f (100 * $passed / $decided) } else { '-' }

        # --- Document, in the module's shared report style ---------------------------
        $pdf = New-AACPdfDocument -Title $Title -Subject "Pester results: $ran tests, $failed failed"
        $section = $pdf.Section
        $pageWidth = $pdf.PageWidth
        $generated = $pdf.Generated
        $cm = $pdf.Cm
        $pt = $pdf.Pt
        $color = $pdf.Color
        $newTable = $pdf.NewTable
        $addHeaderRow = $pdf.AddHeaderRow
        $addBodyRow = $pdf.AddBodyRow
        $ink = $pdf.Colors.Ink
        $muted = $pdf.Colors.Muted
        $rule = $pdf.Colors.Rule
        $panel = $pdf.Colors.Panel
        $accent = $pdf.Colors.Accent
        $white = $pdf.Colors.White
        $status = @{
            Passed  = $pdf.Tone.Good + @{ Label = 'PASS' }
            Failed  = $pdf.Tone.Bad + @{ Label = 'FAIL' }
            Skipped = $pdf.Tone.Neutral + @{ Label = 'SKIP' }
        }

        # --- 1. Summary ---------------------------------------------------------------
        & $pdf.AddTitle "$('{0:N0}' -f $ran) tests in $(@($files).Count) file(s) · ran for $(& $formatDuration $PesterResult.Duration) · generated $($generated.ToString('dddd d MMMM yyyy, HH:mm'))"

        $facts = [ordered]@{}
        $session = Get-Variable -Name 'AACSession' -Scope Global -ValueOnly -ErrorAction Ignore
        if ($session) {
            $facts['Azure account'] = [string]$session.Account
            $facts['Tenant'] = [string]$session.TenantId
        }
        $facts['Test files'] = (@($files | ForEach-Object Name) -join ', ')
        if ($Detail) {
            foreach ($key in $Detail.Keys) { $facts[[string]$key] = [string]$Detail[$key] }
        }
        $facts['Computer'] = "$([Environment]::MachineName) · PowerShell $($PSVersionTable.PSVersion) · Pester $((Get-Module -Name Pester | Select-Object -First 1).Version)"
        $factTable = & $newTable @(4.0, ($pageWidth - 4.0))
        foreach ($key in $facts.Keys) {
            $row = & $addBodyRow $factTable
            $label = $row.Cells[0].AddParagraph($key)
            $label.Format.Font.Color = $muted
            $row.Cells[1].AddParagraph($facts[$key]) | Out-Null
        }

        # Verdict banner
        $verdict = if ($failed -gt 0) { @{ Text = "FAILED  ·  $('{0:N0}' -f $failed) of $('{0:N0}' -f $ran) tests failed"; Fill = $status.Failed.Solid } }
        elseif ($ran -eq 0) { @{ Text = 'NO TESTS RAN'; Fill = (& $color '#CA8A04') } }
        elseif ($passed -eq 0) { @{ Text = "SKIPPED  ·  all $('{0:N0}' -f $skipped) tests were skipped"; Fill = (& $color '#CA8A04') } }
        else { @{ Text = "PASSED  ·  all $('{0:N0}' -f $passed) tests passed$(if ($skipped) { ", $('{0:N0}' -f $skipped) skipped" })"; Fill = $status.Passed.Solid } }
        $section.AddParagraph().Format.SpaceAfter = & $pt 6
        $banner = & $newTable @($pageWidth)
        $banner.TopPadding = & $pt 9
        $banner.BottomPadding = & $pt 9
        $bannerRow = $banner.AddRow()
        $bannerRow.Shading.Color = $verdict.Fill
        $bannerText = $bannerRow.Cells[0].AddParagraph($verdict.Text)
        $bannerText.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Center
        $bannerText.Format.Font.Size = 14
        $bannerText.Format.Font.Name = 'Segoe UI Semibold'
        $bannerText.Format.Font.Color = $white

        # Tiles
        $section.AddParagraph().Format.SpaceAfter = & $pt 6
        $tiles = & $newTable @(3.48, 3.48, 3.48, 3.48, 3.48)
        $tiles.TopPadding = & $pt 8
        $tiles.BottomPadding = & $pt 8
        $tileRow = $tiles.AddRow()
        $tileData = @(
            @{ Value = '{0:N0}' -f $ran; Label = 'tests run'; Color = $ink }
            @{ Value = '{0:N0}' -f $passed; Label = 'passed'; Color = $(if ($passed) { $status.Passed.Text } else { $muted }) }
            @{ Value = '{0:N0}' -f $failed; Label = 'failed'; Color = $(if ($failed) { $status.Failed.Text } else { $muted }) }
            @{ Value = '{0:N0}' -f $skipped; Label = 'skipped'; Color = $muted }
            @{ Value = $passRate; Label = 'pass rate'; Color = $ink }
        )
        for ($i = 0; $i -lt $tileData.Count; $i++) {
            $cell = $tileRow.Cells[$i]
            $cell.Shading.Color = $panel
            $cell.Borders.Left.Width = $(if ($i -gt 0) { 2 } else { 0 })
            $cell.Borders.Left.Color = $white
            $number = $cell.AddParagraph($tileData[$i].Value)
            $number.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Center
            $number.Format.Font.Size = 18
            $number.Format.Font.Name = 'Segoe UI Semibold'
            $number.Format.Font.Color = $tileData[$i].Color
            $caption = $cell.AddParagraph($tileData[$i].Label)
            $caption.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Center
            $caption.Format.Font.Size = 8
            $caption.Format.Font.Color = $muted
        }

        # Proportion bar and legend
        if ($ran -gt 0) {
            $section.AddParagraph().Format.SpaceAfter = & $pt 4
            $parts = @(foreach ($name in 'Passed', 'Failed', 'Skipped') {
                    $n = switch ($name) { 'Passed' { $passed } 'Failed' { $failed } 'Skipped' { $skipped } }
                    if ($n -gt 0) { @{ Name = $name; Width = [math]::Max(0.2, $pageWidth * $n / $ran) } }
                })
            $scale = $pageWidth / ($parts | Measure-Object -Property Width -Sum).Sum
            $bar = & $newTable @($parts | ForEach-Object { $_.Width * $scale })
            $bar.TopPadding = 0
            $bar.BottomPadding = 0
            $barRow = $bar.AddRow()
            $barRow.Height = & $cm 0.35
            $barRow.HeightRule = [MigraDoc.DocumentObjectModel.Tables.RowHeightRule]::Exactly
            for ($i = 0; $i -lt $parts.Count; $i++) {
                $barRow.Cells[$i].Shading.Color = $status[$parts[$i].Name].Solid
                $barRow.Cells[$i].AddParagraph().Format.Font.Size = 1
            }
            $legend = $section.AddParagraph()
            $legend.Format.SpaceBefore = & $pt 4
            $legend.Format.Font.Size = 8
            $legend.Format.Font.Color = $muted
            foreach ($name in 'Passed', 'Failed', 'Skipped') {
                $n = switch ($name) { 'Passed' { $passed } 'Failed' { $failed } 'Skipped' { $skipped } }
                $swatch = $legend.AddFormattedText([string][char]0x25A0)
                $swatch.FontName = 'Segoe UI Symbol'
                $swatch.Color = $status[$name].Solid
                $legend.AddText(" $name $('{0:N0}' -f $n)$(if ($ran) { ' ({0:N1}%)' -f (100 * $n / $ran) })      ") | Out-Null
            }
        }

        # --- 2. Results by check -------------------------------------------------------
        $section.AddParagraph('Results by check', 'Heading2') | Out-Null
        $intro = $section.AddParagraph('Each row is one Describe / Context block. Failed counts are the tests to look at first.')
        $intro.Format.Font.Color = $muted
        $intro.Format.SpaceAfter = & $pt 6
        $byCheck = & $newTable @(9.4, 1.6, 1.6, 1.6, 1.6, 1.6)
        & $addHeaderRow $byCheck @('Check', 'Tests', 'Passed', 'Failed', 'Skipped', 'Pass rate') @(1, 2, 3, 4, 5)
        foreach ($file in $files) {
            if (@($files).Count -gt 1) {
                $fileRow = $byCheck.AddRow()
                $fileRow.Cells[0].MergeRight = 5
                $fileLabel = $fileRow.Cells[0].AddParagraph($file.Name)
                $fileLabel.Format.Font.Name = 'Segoe UI Semibold'
                $fileLabel.Format.Font.Color = $accent
            }
            if ($file.Broken) {
                $row = & $addBodyRow $byCheck
                $row.Cells[0].AddParagraph('File could not be loaded') | Out-Null
                $row.Cells[3].AddParagraph('1').Format.Font.Color = $status.Failed.Text
                continue
            }
            foreach ($block in $file.Blocks) {
                # Groups in the order the tests ran.
                $groups = [ordered]@{}
                foreach ($entry in $block.Entries) {
                    if (-not $groups.Contains($entry.Group)) { $groups[$entry.Group] = [System.Collections.Generic.List[object]]::new() }
                    $groups[$entry.Group].Add($entry)
                }
                foreach ($group in @($groups.GetEnumerator() | ForEach-Object { [pscustomobject]@{ Name = $_.Key; Group = $_.Value; Count = $_.Value.Count } })) {
                    $counts = @{ Passed = 0; Failed = 0; Skipped = 0 }
                    foreach ($entry in $group.Group) { $counts[[string]$entry.Test.Result]++ }
                    $row = & $addBodyRow $byCheck
                    $name = $row.Cells[0].AddParagraph()
                    if ($group.Name) {
                        $name.AddFormattedText("$($block.Name) · ").Color = $muted
                        $name.AddText($group.Name) | Out-Null
                    }
                    else {
                        $name.AddText($block.Name) | Out-Null
                    }
                    $values = @($group.Count, $counts.Passed, $counts.Failed, $counts.Skipped)
                    for ($i = 0; $i -lt $values.Count; $i++) {
                        $p = $row.Cells[$i + 1].AddParagraph('{0:N0}' -f $values[$i])
                        $p.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Right
                        if ($i -eq 2 -and $values[$i] -gt 0) { $p.Format.Font.Color = $status.Failed.Text; $p.Format.Font.Bold = $true }
                        elseif ($values[$i] -eq 0) { $p.Format.Font.Color = $muted }
                    }
                    $groupDecided = $counts.Passed + $counts.Failed
                    $rate = $row.Cells[5].AddParagraph($(if ($groupDecided) { '{0:N0}%' -f (100 * $counts.Passed / $groupDecided) } else { '-' }))
                    $rate.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Right
                }
            }
        }

        # --- 3. Every test --------------------------------------------------------------
        $resultsHeading = $section.AddParagraph('Test results', 'Heading1')
        $resultsHeading.Format.SpaceBefore = & $pt 24
        if ($FailedOnly) {
            $note = $section.AddParagraph("Only failed tests are listed. The $('{0:N0}' -f $passed) passed and $('{0:N0}' -f $skipped) skipped tests are counted in the summary but not shown here.")
            $note.Format.Font.Color = $muted
            $note.Format.SpaceAfter = & $pt 6
        }

        foreach ($file in $files) {
            $fileHeading = $section.AddParagraph('', 'Heading2')
            $fileHeading.AddText($file.Name) | Out-Null
            $fileCounts = $fileHeading.AddFormattedText("    $($file.Count.Passed) passed · $($file.Count.Failed) failed · $($file.Count.Skipped) skipped")
            $fileCounts.Size = 9
            $fileCounts.Color = $muted

            if ($file.Broken) {
                $broken = $section.AddParagraph()
                $broken.Format.Font.Color = $status.Failed.Text
                & $addLines $broken (@('This file failed before any test ran:') + @($file.Error))
                continue
            }

            $shownAny = $false
            foreach ($block in $file.Blocks) {
                $entries = @($block.Entries | Where-Object { -not $FailedOnly -or [string]$_.Test.Result -eq 'Failed' })
                if ($entries.Count -eq 0) {
                    continue
                }
                $shownAny = $true
                $hasGroups = @($entries | Where-Object { $_.Group }).Count -gt 0
                $section.AddParagraph($block.Name, 'Heading3') | Out-Null

                $table = & $newTable @(1.3, 14.4, 1.7)
                & $addHeaderRow $table @('Result', 'Test', 'Time') @(2)

                $previousGroup = $null
                foreach ($entry in $entries) {
                    # Each Context starts with a full-width row naming it.
                    if ($hasGroups -and $entry.Group -ne $previousGroup) {
                        $groupRow = $table.AddRow()
                        $groupRow.KeepWith = 1
                        $groupRow.Cells[0].MergeRight = 2
                        $groupRow.Borders.Bottom.Width = 0.75
                        $groupRow.Borders.Bottom.Color = $rule
                        $groupRow.TopPadding = & $pt 7
                        $groupText = $groupRow.Cells[0].AddParagraph($entry.Group)
                        $groupText.Format.Font.Name = 'Segoe UI Semibold'
                        $groupText.Format.Font.Size = 9.5
                        $groupText.Format.Font.Color = $accent
                    }
                    $previousGroup = $entry.Group

                    $result = [string]$entry.Test.Result
                    $look = $status[$result]
                    $row = & $addBodyRow $table
                    $column = 0

                    $badge = $row.Cells[$column++]
                    $badge.Shading.Color = $look.Fill
                    $badgeText = $badge.AddParagraph($look.Label)
                    $badgeText.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Center
                    $badgeText.Format.Font.Size = 7.5
                    $badgeText.Format.Font.Bold = $true
                    $badgeText.Format.Font.Color = $look.Text

                    $testCell = $row.Cells[$column++]
                    $testCell.AddParagraph([string]$entry.Test.ExpandedName) | Out-Null
                    if ($result -eq 'Failed') {
                        $message = $testCell.AddParagraph()
                        $message.Format.Font.Size = 7.5
                        $message.Format.Font.Color = $status.Failed.Text
                        $message.Format.SpaceBefore = & $pt 1.5
                        & $addLines $message @(& $errorText $entry.Test)
                    }
                    elseif ($result -eq 'Skipped') {
                        $reason = (@(& $errorText $entry.Test -MaxLines 3) -join ' ') -replace '^is skipped, because ', ''
                        if ($reason) {
                            $reasonText = $testCell.AddParagraph("Skipped: $reason")
                            $reasonText.Format.Font.Size = 7.5
                            $reasonText.Format.Font.Color = $muted
                        }
                    }

                    $time = $row.Cells[$column].AddParagraph((& $formatDuration $entry.Test.Duration))
                    $time.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Right
                    $time.Format.Font.Size = 8
                    $time.Format.Font.Color = $muted
                }
            }
            if (-not $shownAny) {
                $none = $section.AddParagraph($(if ($FailedOnly) { 'No failed tests in this file.' } else { 'No tests ran in this file.' }))
                $none.Format.Font.Color = $muted
            }
        }

        # --- Write it -----------------------------------------------------------------------
        Save-AACPdfDocument -Pdf $pdf -Path $fullPath
    }
}
