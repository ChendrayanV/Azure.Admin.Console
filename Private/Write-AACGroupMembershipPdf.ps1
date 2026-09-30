function Write-AACGroupMembershipPdf {
    <#
    .SYNOPSIS
        Writes Get-AACEntraGroupMembership's result as a landscape A4 PDF.
    .DESCRIPTION
        1. Summary: title, scope, tiles (groups, unique users, guests,
           disabled accounts, nested groups, empty groups).
        2. Groups: type, source, direct members, nested groups, users,
           guests, disabled - and why a group's members couldn't be read.
        3. Members, group by group: every row - name, type, user principal
           name, member or guest, account, direct or nested (and through
           which group) - up to -MaxRows; the CSV and HTML report have them
           all. Guests in amber, disabled accounts in red.

        -Path must be a full path; see Save-AACPdfDocument.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Membership,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Title,

        [System.Collections.IDictionary] $Detail,

        [int] $MaxRows = 10000
    )

    $stats = $Membership.Stats
    $pdf = New-AACPdfDocument -Title $Title -Subject "$($stats.Groups) Entra ID groups, $($stats.Users) users" -Landscape
    $section = $pdf.Section
    $colors = $pdf.Colors
    $pt = $pdf.Pt
    $right = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Right
    $number = { param($Cell, $Value, $Color) $p = $Cell.AddParagraph(('{0:N0}' -f [double]$Value)); $p.Format.Alignment = $right; if ($Color -and [double]$Value -gt 0) { $p.Format.Font.Color = $Color; $p.Format.Font.Name = 'Segoe UI Semibold' } elseif ([double]$Value -eq 0) { $p.Format.Font.Color = $colors.Muted } }

    # --- 1. Summary -----------------------------------------------------------------------------
    & $pdf.AddTitle "Entra ID group membership · generated $($pdf.Generated.ToString('dddd d MMMM yyyy, HH:mm'))"
    if ($Detail -and $Detail.Count) {
        $factTable = & $pdf.NewTable @(4.0, ($pdf.PageWidth - 4.0))
        foreach ($key in $Detail.Keys) {
            $row = & $pdf.AddBodyRow $factTable
            $row.Cells[0].AddParagraph([string]$key).Format.Font.Color = $colors.Muted
            $row.Cells[1].AddParagraph([string]$Detail[$key]) | Out-Null
        }
        $section.AddParagraph().Format.SpaceAfter = & $pt 6
    }
    $tileData = @(
        @{ Value = $stats.Groups; Label = 'groups' }
        @{ Value = $stats.Users; Label = 'unique users' }
        @{ Value = $stats.Guests; Label = 'guests'; Color = $(if ($stats.Guests) { $pdf.Tone.Warn.Solid }) }
        @{ Value = $stats.Disabled; Label = 'disabled accounts'; Color = $(if ($stats.Disabled) { $pdf.Tone.Bad.Solid }) }
        @{ Value = $stats.NestedGroups; Label = 'nested groups' }
        @{ Value = $stats.EmptyGroups; Label = 'empty groups'; Color = $(if ($stats.EmptyGroups) { $pdf.Tone.Warn.Solid }) }
    )
    $tiles = & $pdf.NewTable @(1..$tileData.Count | ForEach-Object { $pdf.PageWidth / $tileData.Count })
    $tiles.TopPadding = & $pt 8
    $tiles.BottomPadding = & $pt 8
    $tileRow = $tiles.AddRow()
    for ($i = 0; $i -lt $tileData.Count; $i++) {
        $cell = $tileRow.Cells[$i]
        $cell.Shading.Color = $colors.Panel
        $cell.Borders.Left.Width = $(if ($i -gt 0) { 2 } else { 0 })
        $cell.Borders.Left.Color = $colors.White
        $value = $cell.AddParagraph(('{0:N0}' -f $tileData[$i].Value))
        if ($tileData[$i].Contains('Color') -and $tileData[$i].Color) { $value.Format.Font.Color = $tileData[$i].Color }
        $value.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Center
        $value.Format.Font.Size = 18
        $value.Format.Font.Name = 'Segoe UI Semibold'
        $caption = $cell.AddParagraph($tileData[$i].Label)
        $caption.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Center
        $caption.Format.Font.Size = 8
        $caption.Format.Font.Color = $colors.Muted
    }

    # --- 2. Groups ------------------------------------------------------------------------------
    $section.AddParagraph('Groups', 'Heading2') | Out-Null
    $table = & $pdf.NewTable @(7.0, 5.2, 4.2, 1.9, 2.1, 1.9, 1.8, 1.9)
    & $pdf.AddHeaderRow $table @('Group', 'Type', 'Source', 'Direct', 'Nested groups', 'Users', 'Guests', 'Disabled') @(3, 4, 5, 6, 7)
    foreach ($group in $Membership.Groups) {
        $row = & $pdf.AddBodyRow $table
        $name = $row.Cells[0].AddParagraph($group.GroupName)
        $name.Format.Font.Name = 'Segoe UI Semibold'
        if ($group.Error) {
            $why = $row.Cells[0].AddParagraph("Members not read: $($group.Error)")
            $why.Format.Font.Size = 7
            $why.Format.Font.Color = $colors.Amber
        }
        $row.Cells[1].AddParagraph($group.GroupType) | Out-Null
        $row.Cells[2].AddParagraph($group.GroupSource).Format.Font.Color = $colors.Muted
        & $number $row.Cells[3] $group.DirectMembers
        & $number $row.Cells[4] $group.NestedGroups
        & $number $row.Cells[5] $group.Users
        & $number $row.Cells[6] $group.Guests $pdf.Tone.Warn.Solid
        & $number $row.Cells[7] $group.DisabledUsers $pdf.Tone.Bad.Solid
    }

    # --- 3. Members, group by group -------------------------------------------------------------------
    $shown = 0
    $all = @($Membership.Rows)
    foreach ($group in $Membership.Groups) {
        if ($shown -ge $MaxRows) { break }
        $rows = @($all | Where-Object GroupId -EQ $group.GroupId | Select-Object -First ($MaxRows - $shown))
        $shown += $rows.Count
        $section.AddPageBreak()
        $section.AddParagraph("$($group.GroupName)", 'Heading2') | Out-Null
        $note = $section.AddParagraph("$($group.GroupType) · $($group.GroupSource) · $($group.DirectMembers) direct member(s) · $($group.Users) user(s) at every level")
        $note.Format.Font.Size = 8
        $note.Format.Font.Color = $colors.Muted
        $note.Format.SpaceAfter = & $pt 4
        $table = & $pdf.NewTable @(5.6, 2.4, 6.4, 1.8, 1.9, 1.9, 6.0)
        & $pdf.AddHeaderRow $table @('Member', 'Type', 'User principal name', 'User type', 'Account', 'Membership', 'Via')
        foreach ($item in $rows) {
            $row = & $pdf.AddBodyRow $table
            if ($item.Membership -in 'Empty', 'Not read') {
                $row.Cells[0].MergeRight = 6
                $row.Cells[0].AddParagraph($(if ($item.Membership -eq 'Empty') { 'No members.' } else { "The members couldn't be read: $($group.Error)" })).Format.Font.Color = $colors.Amber
                continue
            }
            $member = $row.Cells[0].AddParagraph(('  ' * [int]$item.Depth) + $item.MemberName)
            if ($item.MemberType -eq 'Group') { $member.Format.Font.Name = 'Segoe UI Semibold' }
            $row.Cells[1].AddParagraph($item.MemberType) | Out-Null
            $row.Cells[2].AddParagraph($item.UserPrincipalName).Format.Font.Size = 7.5
            $userType = $row.Cells[3].AddParagraph($item.UserType)
            if ($item.UserType -eq 'Guest') { $userType.Format.Font.Color = $pdf.Tone.Warn.Solid; $userType.Format.Font.Name = 'Segoe UI Semibold' }
            $account = $row.Cells[4].AddParagraph($(if ($item.MemberType -ne 'User') { '' } elseif ($item.AccountEnabled -eq $false) { 'Disabled' } else { 'Enabled' }))
            if ($item.AccountEnabled -eq $false) { $account.Format.Font.Color = $pdf.Tone.Bad.Solid; $account.Format.Font.Name = 'Segoe UI Semibold' }
            $row.Cells[5].AddParagraph($item.Membership).Format.Font.Color = $(if ($item.Membership -eq 'Nested') { $colors.Muted } else { $colors.Ink })
            $via = $row.Cells[6].AddParagraph($item.Via)
            $via.Format.Font.Size = 7
            $via.Format.Font.Color = $colors.Muted
        }
    }
    if ($shown -lt $all.Count) {
        $more = $section.AddParagraph("The first $('{0:N0}' -f $shown) of $('{0:N0}' -f $all.Count) rows are shown; the CSV and HTML report have them all.")
        $more.Format.Font.Color = $colors.Muted
    }

    Save-AACPdfDocument -Pdf $pdf -Path $Path
}
