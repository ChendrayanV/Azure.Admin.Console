function Write-AACGroupMembershipPdf {
    <#
    .SYNOPSIS
        Writes Get-AACEntraGroupMembership's result as a landscape A4 PDF.
    .DESCRIPTION
        1. Summary: title, scope, tiles (groups, unique users, guests,
           disabled accounts, nested groups, empty groups).
        2. Groups: type, membership type and owners under the name, source
           and created date, direct members, nested groups, users, guests,
           disabled - and why a group's members couldn't be read.
        3. Each group on its own page: its details (type, source,
           membership type, created, owners, counts), its direct members,
           then each nested group's members under its path - name, type,
           user principal name, member or guest, account - up to -MaxRows
           rows; the CSV and HTML report have them all. Guests in amber,
           disabled accounts in red.

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
        $ownerLine = $row.Cells[0].AddParagraph("Owners: $($group.Owners)")
        $ownerLine.Format.Font.Size = 7
        $ownerLine.Format.Font.Color = $(if ($group.OwnerCount) { $colors.Muted } else { $colors.Amber })
        $row.Cells[1].AddParagraph($group.GroupType) | Out-Null
        $kind = $row.Cells[1].AddParagraph($group.MembershipType)
        $kind.Format.Font.Size = 7
        $kind.Format.Font.Color = $colors.Muted
        $row.Cells[2].AddParagraph($group.GroupSource).Format.Font.Color = $colors.Muted
        if ($group.Created) {
            $when = $row.Cells[2].AddParagraph("Created $($group.Created.ToString('yyyy-MM-dd'))")
            $when.Format.Font.Size = 7
            $when.Format.Font.Color = $colors.Muted
        }
        & $number $row.Cells[3] $group.DirectMembers
        & $number $row.Cells[4] $group.NestedGroups
        & $number $row.Cells[5] $group.Users
        & $number $row.Cells[6] $group.Guests $pdf.Tone.Warn.Solid
        & $number $row.Cells[7] $group.DisabledUsers $pdf.Tone.Bad.Solid
    }

    # --- 3. Members, group by group -------------------------------------------------------------------
    # --- 3. Each group: its details, its direct members, then each nested group's members ---------------
    $shown = 0
    $total = 0
    foreach ($parts in $Membership.Sections.Values) { foreach ($part in @($parts)) { $total += $part.Members.Count } }
    foreach ($group in $Membership.Groups) {
        if ($shown -ge $MaxRows) { break }
        $people = @($Membership.People | Where-Object GroupId -EQ $group.GroupId)
        $section.AddPageBreak()
        $section.AddParagraph("$($group.GroupName)", 'Heading2') | Out-Null

        # The details: label and value, two pairs a row.
        $facts = [ordered]@{
            'Type'       = $group.GroupType
            'Created'    = $(if ($group.Created) { $group.Created.ToString('yyyy-MM-dd HH:mm') + ' UTC' } else { 'unknown' })
            'Source'     = $group.GroupSource
            'Owners'     = $group.Owners
            'Membership' = $group.MembershipType
            'Members'    = "$($group.DirectMembers) direct · $($group.NestedGroups) nested group(s) · $($people.Count) in all ($(@($people | Where-Object UserType -EQ 'Guest').Count) guest(s), $(@($people | Where-Object { $_.AccountEnabled -eq $false }).Count) disabled)"
        }
        if ($group.MembershipRule) { $facts['Rule'] = $group.MembershipRule; $facts[' '] = '' }
        $details = & $pdf.NewTable @(2.6, 8.0, 2.2, 13.8)
        $keys = @($facts.Keys)
        for ($i = 0; $i -lt $keys.Count; $i += 2) {
            $row = $details.AddRow()
            foreach ($j in 0, 1) {
                if ($i + $j -ge $keys.Count) { break }
                $label = $row.Cells[$j * 2].AddParagraph([string]$keys[$i + $j])
                $label.Format.Font.Color = $colors.Muted
                $value = $row.Cells[$j * 2 + 1].AddParagraph([string]$facts[$keys[$i + $j]])
                if ($keys[$i + $j] -eq 'Owners' -and -not $group.OwnerCount) { $value.Format.Font.Color = $colors.Amber }
            }
        }

        foreach ($part in @($Membership.Sections[$group.GroupId])) {
            if ($shown -ge $MaxRows) { break }
            $count = $part.Members.Count
            $heading = if ($part.Depth -eq 0) { "Direct members ($count)" } else { "Nested group: $($part.Path) ($count member$(if ($count -ne 1) { 's' }))" }
            $section.AddParagraph($heading, 'Heading3') | Out-Null
            if ($part.Error -or -not $count) {
                $note = $section.AddParagraph($(if ($part.Error) { "The members couldn't be read: $($part.Error)" } else { 'No members.' }))
                $note.Format.Font.Color = $colors.Amber
                continue
            }
            $table = & $pdf.NewTable @(6.4, 3.0, 8.2, 2.2, 2.2, 4.6)
            & $pdf.AddHeaderRow $table @('Member', 'Type', 'User principal name', 'User type', 'Account', 'Note')
            foreach ($item in @($part.Members | Sort-Object -Property @{ Expression = { $_.MemberType -eq 'Group' } }, MemberName | Select-Object -First ($MaxRows - $shown))) {
                $shown++
                $row = & $pdf.AddBodyRow $table
                $member = $row.Cells[0].AddParagraph($(if ($item.MemberName) { $item.MemberName } elseif ($item.UserPrincipalName) { $item.UserPrincipalName } else { $item.MemberId }))
                if ($item.MemberType -eq 'Group') {
                    $member.Format.Font.Name = 'Segoe UI Semibold'
                    $row.Cells[1].AddParagraph('Nested group').Format.Font.Color = $pdf.Tone.Warn.Solid
                    $row.Cells[5].AddParagraph($(if ($part.Loops.Contains($item.MemberId)) { 'Already listed above (a loop)' } else { 'Its members follow' })).Format.Font.Color = $colors.Muted
                    continue
                }
                $row.Cells[1].AddParagraph($item.MemberType) | Out-Null
                $row.Cells[2].AddParagraph($item.UserPrincipalName).Format.Font.Size = 7.5
                $userType = $row.Cells[3].AddParagraph($item.UserType)
                if ($item.UserType -eq 'Guest') { $userType.Format.Font.Color = $pdf.Tone.Warn.Solid; $userType.Format.Font.Name = 'Segoe UI Semibold' }
                $account = $row.Cells[4].AddParagraph($(if ($item.MemberType -ne 'User') { '' } elseif ($item.AccountEnabled -eq $false) { 'Disabled' } else { 'Enabled' }))
                if ($item.AccountEnabled -eq $false) { $account.Format.Font.Color = $pdf.Tone.Bad.Solid; $account.Format.Font.Name = 'Segoe UI Semibold' }
            }
        }
    }
    if ($shown -lt $total) {
        $more = $section.AddParagraph("The first $('{0:N0}' -f $shown) of $('{0:N0}' -f $total) rows are shown; the CSV and HTML report have them all.")
        $more.Format.Font.Color = $colors.Muted
    }

    Save-AACPdfDocument -Pdf $pdf -Path $Path
}
