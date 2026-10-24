function Show-AACStorageSizeView {
    <#
    .SYNOPSIS
        Renders Get-AACStorageAccountContainerSize's report
        (ConvertTo-AACStorageSizeReport) as a Spectre.Console view.
    .DESCRIPTION
        The scope; tiles (storage accounts, containers, blobs, size, the
        largest container, what couldn't be read); the size by access tier
        as one proportion bar with its legend; the largest containers as a
        bar chart; every subscription, storage account and container as a
        tree - each container with a size bar against the account's largest,
        coloured by the tier most of it is in; the largest blobs; and what
        couldn't be read, with what to do. Tiers: Hot orange, Cool blue, Cold
        steel blue, Archive purple, no tier grey. Output goes straight to the
        Spectre console; wrap the call in Invoke-AACPagedOutput to page it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Report,

        [System.Collections.IDictionary] $Scope,

        # Containers shown per storage account in the tree.
        [int] $ContainersPerAccount = 25,

        # Blobs in the largest-blobs table.
        [int] $LargestBlobs = 15
    )

    $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
    $glyph = Get-AACGlyph
    $unicode = [Spectre.Console.AnsiConsole]::Profile.Capabilities.Unicode
    $stats = $Report.Stats
    $tierColor = [ordered]@{ Hot = 'orangered1'; Cool = 'deepskyblue1'; Cold = 'steelblue1'; Archive = 'mediumpurple2'; None = 'grey62' }
    $tierLabel = @{ Hot = 'Hot'; Cool = 'Cool'; Cold = 'Cold'; Archive = 'Archive'; None = 'No tier' }
    $size = { param([double] $Bytes) Format-AACByteSize -Bytes $Bytes }
    $full = if ($unicode) { [string][char]0x2588 } else { '#' }
    $empty = if ($unicode) { [string][char]0x2591 } else { '.' }
    $bar = {
        param([double] $Share, [string] $Color, [int] $Width = 12)
        $filled = [int][Math]::Round([Math]::Max(0, [Math]::Min(1, $Share)) * $Width)
        if ($Share -gt 0 -and $filled -eq 0) { $filled = 1 }
        "[$Color]$($full * $filled)[/][grey23]$($empty * ($Width - $filled))[/]"
    }
    # The tier holding most of a container's bytes.
    $dominant = {
        param($Row)
        $best = 'None'; $most = [long]-1
        foreach ($name in 'Hot', 'Cool', 'Cold', 'Archive') { if ($Row."Size$name" -gt $most) { $best = $name; $most = $Row."Size$name" } }
        if ($Row.SizeNoTier -gt $most) { $best = 'None'; $most = $Row.SizeNoTier }
        @{ Tier = $best; Share = $(if ($Row.Size) { $most / $Row.Size } else { 0 }) }
    }
    $sum = { param([object[]] $Items, [string] $Property) $total = [long]0; foreach ($item in $Items) { $total += [long]$item.$Property }; $total }
    $blobCount = { param([long] $Count) if ($Count -eq 1) { '1 blob' } else { '{0:N0} blobs' -f $Count } }
    # '30 Sept' this year, 'Jun 2025' before: short enough for a narrow terminal.
    $when = { param($Date) $local = ([datetime]$Date).ToLocalTime(); if ($local.Year -eq (Get-Date).Year) { $local.ToString('d MMM') } else { $local.ToString('MMM yyyy') } }
    $statusColor = @{ OK = 'green3'; Partial = 'orange1'; Failed = 'red1'; Empty = 'grey58'; 'No blob service' = 'grey50' }

    $facts = [System.Collections.Generic.List[string]]::new()
    if ($script:AACSession) { $facts.Add("[white]$(& $escape $script:AACSession.Account)[/]") }
    if ($Scope) { foreach ($key in $Scope.Keys) { $facts.Add("$(& $escape $key): $(& $escape $Scope[$key])") } }
    $facts.Add((Get-Date).ToString('d MMM yyyy HH:mm'))
    Write-AACMarkup "[grey58]$($facts -join " $($glyph.Dot) ")[/]"
    [Spectre.Console.AnsiConsole]::WriteLine()

    if (-not @($Report.Accounts).Count) {
        Show-AACCallout Info -Message '[bold]No storage accounts[/] [grey58]were found in this scope.[/]'
        return
    }

    # --- Tiles ------------------------------------------------------------------------------------------
    $biggest = $stats.LargestContainer
    $notRead = $stats.Failed + $stats.Partial
    Show-AACTileRow -Tile @(
        @{ Value = '{0:N0}' -f $stats.Accounts; Caption = 'storage accounts'; Color = 'deepskyblue1' }
        @{ Value = '{0:N0}' -f $stats.Containers; Caption = $(if ($stats.Empty) { "containers ($('{0:N0}' -f $stats.Empty) empty)" } else { 'containers' }); Color = 'mediumpurple2' }
        @{ Value = '{0:N0}' -f $stats.Blobs; Caption = 'blobs'; Color = 'turquoise2' }
        @{ Value = (& $size $stats.Bytes); Caption = $(if ($stats.TotalBytes -gt $stats.Bytes) { "stored ($(& $size $stats.TotalBytes) with snapshots, versions, deleted)" } else { 'stored' }); Color = 'springgreen2' }
        @{ Value = $(if ($biggest -and $biggest.Size) { & $size $biggest.Size } else { '-' }); Caption = $(if ($biggest -and $biggest.Size) { "largest: $($biggest.StorageAccount)/$($biggest.Container)" } else { 'largest container' }); Color = 'gold1' }
        @{ Value = '{0:N0}' -f $notRead; Caption = 'not read in full'; Color = $(if ($notRead) { 'red1' } else { 'green3' }) }
    )
    [Spectre.Console.AnsiConsole]::WriteLine()

    # --- Size by access tier ------------------------------------------------------------------------------
    if ($stats.Bytes -gt 0) {
        $slices = [ordered]@{}
        $colors = @{}
        $legend = foreach ($name in $tierColor.Keys) {
            $bytes = [double]$Report.Tiers[$name]
            if ($bytes -le 0) { continue }
            $slices[$tierLabel[$name]] = $bytes
            $colors[$tierLabel[$name]] = $tierColor[$name]
            "[$($tierColor[$name])]$($glyph.Bullet)[/] $($tierLabel[$name]) [bold]$(& $size $bytes)[/] [grey58]$('{0:N0}%' -f ($bytes / $stats.Bytes * 100))[/]"
        }
        Show-AACBreakdownChart -Data $slices -Color $colors -Title 'Size by access tier' -Width 100 -HideTags
        Write-AACMarkup ($legend -join '   ')
        if ($stats.Snapshots -or $stats.Versions -or $stats.Deleted) {
            Write-AACMarkup "[grey58]Not in the bar: $('{0:N0}' -f $stats.Snapshots) snapshot(s) $(& $size $stats.SnapshotBytes) $($glyph.Dot) $('{0:N0}' -f $stats.Versions) previous version(s) $(& $size $stats.VersionBytes) $($glyph.Dot) $('{0:N0}' -f $stats.Deleted) deleted blob(s) $(& $size $stats.DeletedBytes)[/]"
        }
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    # --- The largest containers ----------------------------------------------------------------------------
    $top = @($Report.Rows | Where-Object { $null -ne $_.Container -and $_.Size -gt 0 } | Sort-Object -Property Size -Descending | Select-Object -First 12)
    if ($top.Count) {
        $unit = Get-AACByteUnit -Bytes $top[0].Size
        $power = Get-AACByteUnit -Bytes $top[0].Size -AsPower
        $items = @($top | ForEach-Object { @{ Label = "$($_.StorageAccount)/$($_.Container)"; Value = $_.Size / [Math]::Pow(1024, $power); Color = $tierColor[(& $dominant $_).Tier] } })
        Show-AACBarChart -Item $items -Title "Largest containers ($unit, coloured by their main tier)" -Format $(if ($power) { 'N2' } else { 'N0' }) -Suffix " $unit"
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    # --- Subscriptions, accounts and containers --------------------------------------------------------------
    $rowsByAccount = @{}
    foreach ($row in $Report.Rows) {
        $key = [string]$row.StorageAccountId
        if (-not $rowsByAccount.ContainsKey($key)) { $rowsByAccount[$key] = [System.Collections.Generic.List[object]]::new() }
        if ($null -ne $row.Container) { $rowsByAccount[$key].Add($row) }
    }
    $root = [Spectre.Console.Tree]::new([Spectre.Console.Markup]::new("[bold deepskyblue1]$($glyph.Bullet) Storage[/] [grey58]$(& $size $stats.Bytes) $($glyph.Dot) $('{0:N0}' -f $stats.Blobs) blobs in $('{0:N0}' -f $stats.Containers) containers, $('{0:N0}' -f $stats.Accounts) accounts[/]"))
    $root.Style = [Spectre.Console.Style]::Parse('grey42')
    if (-not $unicode) { $root.Guide = [Spectre.Console.TreeGuide]::Ascii }
    foreach ($subscription in @($Report.Accounts | Group-Object -Property SubscriptionName | Sort-Object -Property @{ Expression = { & $sum $_.Group 'Size' }; Descending = $true }, Name)) {
        $subBytes = & $sum $subscription.Group 'Size'
        $subNode = [Spectre.Console.TreeNode]::new([Spectre.Console.Markup]::new("[bold]$(& $escape $subscription.Name)[/] [springgreen2]$(& $size $subBytes)[/] [grey58]$($glyph.Dot) $($subscription.Count) account(s)[/]"))
        $root.Nodes.Add($subNode)
        foreach ($account in $subscription.Group) {
            $detail = @($account.Kind, $account.Sku, $account.Location, $(if ($account.HierarchicalNamespace) { 'Data Lake' }), $(if ($account.NetworkAccess -ne 'All networks') { $account.NetworkAccess })) | Where-Object { $_ }
            $color = $statusColor[$account.Status]
            $state = switch ($account.Status) {
                'OK' { '' }
                'Empty' { '  [grey58]no containers[/]' }
                'No blob service' { "  [grey50]$(& $escape $account.Reason)[/]" }
                default { "  [$color]$(& $escape $account.Status): $('{0:N0}' -f $account.Failed) not read[/]" }
            }
            $label = "[bold deepskyblue1]$(& $escape $account.StorageAccount)[/] [grey50]$(& $escape ($detail -join " $($glyph.Dot) "))[/]"
            if ($account.Status -ne 'No blob service') {
                $label += "  [bold springgreen2]$(& $size $account.Size)[/] [grey58]$($glyph.Dot) $(& $blobCount $account.BlobCount) $($glyph.Dot) $($account.Containers) container$(if ($account.Containers -ne 1) { 's' })[/]"
            }
            $accountNode = [Spectre.Console.TreeNode]::new([Spectre.Console.Markup]::new($label + $state))
            $subNode.Nodes.Add($accountNode)

            $rows = @(if ($rowsByAccount.ContainsKey([string]$account.StorageAccountId)) { $rowsByAccount[[string]$account.StorageAccountId] })
            if ($account.Status -eq 'Failed' -and -not $rows.Count) {
                $accountNode.Nodes.Add([Spectre.Console.TreeNode]::new([Spectre.Console.Markup]::new("[red1]$($glyph.Cross) $(& $escape $account.Reason)[/]"))) | Out-Null
                continue
            }
            $max = [double]0
            $width = 8
            foreach ($row in $rows) { $max = [Math]::Max($max, [double]$row.Size); $width = [Math]::Max($width, $row.Container.Length) }
            $width = [Math]::Min(36, $width)
            foreach ($row in @($rows | Select-Object -First $ContainersPerAccount)) {
                $name = & $escape $row.Container.PadRight($width)
                if ($row.Status -eq 'Failed') {
                    $code = ($row.Error -split ':')[0]
                    $text = "[grey23]$($empty * 12)[/] [white]$name[/]  [red1]$($glyph.Cross) $(& $escape $code)[/]"
                }
                else {
                    $main = & $dominant $row
                    $flags = @(
                        if ($row.BlobCount -eq 0) { '[grey50]empty[/]' }
                        else { "[grey58]$(& $blobCount $row.BlobCount) $($glyph.Dot) [/][$($tierColor[$main.Tier])]$($tierLabel[$main.Tier]) $('{0:N0}%' -f ($main.Share * 100))[/]" }
                        if ($row.LastModified) { "[grey50]$($glyph.Dot) changed $(& $escape (& $when $row.LastModified))[/]" }
                        if ($row.PublicAccess -and $row.PublicAccess -ne 'None') { "[orange1]$($glyph.Dot) public ($(& $escape $row.PublicAccess))[/]" }
                        if ($row.Status -eq 'Partial') { "[orange1]$($glyph.Dot) partial: $(& $escape (($row.Error -split ':')[0]))[/]" }
                    )
                    $text = "$(& $bar ($(if ($max) { $row.Size / $max } else { 0 })) $tierColor[$main.Tier]) [white]$name[/] [bold]$((& $size $row.Size).PadLeft(11))[/]  $($flags -join ' ')"
                }
                $accountNode.Nodes.Add([Spectre.Console.TreeNode]::new([Spectre.Console.Markup]::new($text))) | Out-Null
            }
            if ($rows.Count -gt $ContainersPerAccount) {
                $rest = @($rows | Select-Object -Skip $ContainersPerAccount)
                $accountNode.Nodes.Add([Spectre.Console.TreeNode]::new([Spectre.Console.Markup]::new("[grey50]$($glyph.Chevron) $($rest.Count) more container(s), $(& $size (& $sum $rest 'Size')) - -HtmlPath or -CsvPath lists them all[/]"))) | Out-Null
            }
        }
    }
    [Spectre.Console.AnsiConsole]::Write($root)
    [Spectre.Console.AnsiConsole]::WriteLine()

    # --- The largest blobs ------------------------------------------------------------------------------
    $blobs = @($Report.Largest | Select-Object -First $LargestBlobs)
    if ($blobs.Count) {
        $table = [Spectre.Console.Table]::new()
        $table.Border = [Spectre.Console.TableBorder]::Rounded
        $table.BorderStyle = [Spectre.Console.Style]::Parse('gold1')
        $table.Expand = $true
        $table.Title = [Spectre.Console.TableTitle]::new("[bold]$($glyph.Bullet) Largest blobs[/] [grey58]$($glyph.Dot) the $($blobs.Count) largest[/]")
        foreach ($header in '#', 'Blob', 'Account / container', 'Tier', 'Type', 'Size', 'Changed') {
            $column = [Spectre.Console.TableColumn]::new("[grey62]$header[/]")
            if ($header -in '#', 'Size') { $column.Alignment = [Spectre.Console.Justify]::Right }
            $table.AddColumn($column) | Out-Null
        }
        $rank = 0
        foreach ($blob in $blobs) {
            $rank++
            $cells = @(
                "[grey50]$rank[/]"
                "[white]$(& $escape $blob.Name)[/]"
                "[grey70]$(& $escape $blob.StorageAccount)[/][grey50]/$(& $escape $blob.Container)[/]"
                "[$($tierColor[$(if ($tierColor.Contains($blob.AccessTier)) { $blob.AccessTier } else { 'None' })])]$(& $escape $tierLabel[$(if ($tierLabel.ContainsKey($blob.AccessTier)) { $blob.AccessTier } else { 'None' })])[/]"
                "[grey58]$(& $escape ($blob.BlobType -replace 'Blob$', ''))[/]"
                "[bold]$(& $size $blob.Size)[/]"
                "[grey58]$(if ($blob.LastModified) { & $escape (& $when $blob.LastModified) })[/]"
            )
            [Spectre.Console.TableExtensions]::AddRow($table, [Spectre.Console.Rendering.IRenderable[]]@($cells | ForEach-Object { [Spectre.Console.Markup]::new($_) })) | Out-Null
        }
        [Spectre.Console.AnsiConsole]::Write($table)
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    # --- What couldn't be read ------------------------------------------------------------------------------
    $failures = @($Report.Failures)
    if ($failures.Count) {
        $lines = [System.Collections.Generic.List[string]]::new()
        foreach ($group in @($failures | Group-Object -Property { ($_.Error -split ':')[0] } | Sort-Object -Property Count -Descending)) {
            $sample = $group.Group[0]
            $where = @($group.Group | ForEach-Object { if ($null -ne $_.Container) { "$($_.StorageAccount)/$($_.Container)" } else { $_.StorageAccount } })
            $shown = ($where | Select-Object -First 4) -join ', '
            if ($where.Count -gt 4) { $shown += " and $($where.Count - 4) more" }
            $lines.Add("[red1]$($glyph.Cross)[/] [bold]$(& $escape $group.Name)[/] [grey58]$($glyph.Dot) $($group.Count) $(if ($group.Count -eq 1) { 'item' } else { 'items' }): $(& $escape $shown)[/]")
            $reason = ($sample.Error -replace '^[^:]*:\s*', '')
            $lines.Add("  [grey70]$(& $escape $reason)[/]")
        }
        Show-AACCallout Warning -Message ($lines -join "`n") -Title 'Not read in full'
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    $elapsed = $stats.Elapsed
    $took = if ($elapsed.TotalMinutes -ge 1) { '{0}m {1:00}s' -f [int][Math]::Floor($elapsed.TotalMinutes), $elapsed.Seconds } else { '{0:N1}s' -f $elapsed.TotalSeconds }
    Write-AACMarkup "[grey42]Read $('{0:N0}' -f $stats.Blobs) blob(s) in $took ($('{0:N0}' -f $stats.BlobsPerSecond) a second). Add -PassThru (or pipe the command) for the rows; -CsvPath, -BlobCsvPath and -HtmlPath write them.[/]"
}
