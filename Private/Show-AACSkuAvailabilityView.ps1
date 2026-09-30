function Show-AACSkuAvailabilityView {
    <#
    .SYNOPSIS
        Renders Get-AACSkuAvailability's result as a Spectre.Console view.
    .DESCRIPTION
        The scope, tiles (sizes checked, available, in some zones, short of
        quota, zone unavailable, not supported, restricted), then:
          Zones        logical to physical, per subscription and region
          Quota        the region's vCPUs and each family the sizes use,
                       most used first
          Node pools   -ClusterName: each pool's size, its status now, and
                       the family's free vCPUs
          Sizes        each size with its status, vCPUs, memory, zones,
                       features and reason - usable first, up to -MaxSize
        Wrap the call in Invoke-AACPagedOutput to page it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Availability,

        [System.Collections.IDictionary] $Scope,

        [int] $MaxSize = 250
    )

    $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
    $glyph = Get-AACGlyph
    $stats = $Availability.Stats
    $statusColor = @{ Available = 'green3'; Partial = 'orange1'; NoQuota = 'orange1'; ZoneUnavailable = 'red1'; NotSupported = 'red1'; Restricted = 'red1'; NotChecked = 'grey50' }
    $statusText = @{ Available = 'Available'; Partial = 'Some zones'; NoQuota = 'No quota'; ZoneUnavailable = 'Not in zones'; NotSupported = 'Not for AKS'; Restricted = 'Restricted'; NotChecked = 'Not checked' }
    $status = { param([string] $Name) "[bold $($statusColor[$Name])]$($statusText[$Name])[/]" }
    $number = { param($Value) if ($null -eq $Value) { '[grey50]-[/]' } else { '{0:N0}' -f $Value } }
    $newTable = {
        param([string] $Title, [string] $Color, [object[]] $Columns)
        $table = [Spectre.Console.Table]::new()
        $table.Border = [Spectre.Console.TableBorder]::Rounded
        $table.BorderStyle = [Spectre.Console.Style]::Parse($Color)
        $table.Expand = $true
        $table.Title = [Spectre.Console.TableTitle]::new($Title)
        foreach ($column in $Columns) {
            $spectre = [Spectre.Console.TableColumn]::new("[grey62]$($column[0])[/]")
            if ($column[1]) { $spectre.Alignment = [Spectre.Console.Justify]::Right; $spectre.NoWrap = $true }
            if ($column.Count -gt 2 -and $column[2]) { $spectre.NoWrap = $true }
            $table.AddColumn($spectre) | Out-Null
        }
        $table
    }
    $addRow = { param($Table, [string[]] $Cells) [Spectre.Console.TableExtensions]::AddRow($Table, [Spectre.Console.Rendering.IRenderable[]]@($Cells | ForEach-Object { [Spectre.Console.Markup]::new($_) })) | Out-Null }
    $multiple = $stats.Locations -gt 1 -or $stats.Subscriptions -gt 1
    # The features column only where there's room for it; the reports always have it.
    $wide = [Spectre.Console.AnsiConsole]::Profile.Width -ge 140

    $facts = [System.Collections.Generic.List[string]]::new()
    if ($script:AACSession) { $facts.Add("[white]$(& $escape $script:AACSession.Account)[/]") }
    if ($Scope) { foreach ($key in $Scope.Keys) { $facts.Add("$(& $escape $key): $(& $escape $Scope[$key])") } }
    $facts.Add((Get-Date).ToString('d MMM yyyy HH:mm'))
    Write-AACMarkup "[grey58]$($facts -join " $($glyph.Dot) ")[/]"
    [Spectre.Console.AnsiConsole]::WriteLine()

    Show-AACTileRow -Tile @(
        @{ Value = '{0:N0}' -f $stats.Sizes; Caption = 'sizes checked'; Color = 'deepskyblue1' }
        @{ Value = '{0:N0}' -f $stats.Available; Caption = 'available'; Color = $(if ($stats.Available) { 'green3' } else { 'grey50' }) }
        @{ Value = '{0:N0}' -f $stats.Partial; Caption = 'in some zones only'; Color = $(if ($stats.Partial) { 'orange1' } else { 'grey50' }) }
        @{ Value = '{0:N0}' -f $stats.NoQuota; Caption = 'short of quota'; Color = $(if ($stats.NoQuota) { 'orange1' } else { 'grey50' }) }
        @{ Value = '{0:N0}' -f ($stats.ZoneUnavailable + $stats.NotSupported); Caption = 'not in the zones / not for AKS'; Color = $(if ($stats.ZoneUnavailable + $stats.NotSupported) { 'red1' } else { 'grey50' }) }
        @{ Value = '{0:N0}' -f $stats.Restricted; Caption = 'restricted for the subscription'; Color = $(if ($stats.Restricted) { 'red1' } else { 'grey50' }) }
    )
    [Spectre.Console.AnsiConsole]::WriteLine()
    foreach ($notice in @($Availability.Notice | Where-Object { $_ })) { Write-AACMarkup "[deepskyblue1]i[/] [grey70]$(& $escape $notice)[/]" }
    if (@($Availability.Notice).Count) { [Spectre.Console.AnsiConsole]::WriteLine() }

    # --- Zones: logical to physical -------------------------------------------------------------------------
    if (@($Availability.Zones).Count) {
        $table = & $newTable "[bold]$($glyph.Bullet) Availability zones[/] [grey58]$($glyph.Dot) logical zone to physical zone; another subscription's zone 1 may be a different datacentre[/]" 'grey42' @(@('Subscription', $false), @('Region', $false), @('Zones', $false))
        foreach ($group in @($Availability.Zones | Group-Object -Property SubscriptionName, Location)) {
            $first = $group.Group[0]
            & $addRow $table @("[bold]$(& $escape $first.SubscriptionName)[/]", (& $escape $first.Location), ((@($group.Group | Sort-Object LogicalZone | ForEach-Object { "[white]$($_.LogicalZone)[/] [grey50]->[/] $(& $escape $_.PhysicalZone)" })) -join '   '))
        }
        [Spectre.Console.AnsiConsole]::Write($table)
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    # --- Quota -----------------------------------------------------------------------------------------------
    if (@($Availability.Quotas).Count) {
        $columns = [System.Collections.Generic.List[object]]::new()
        if ($multiple) { $columns.Add(@('Subscription', $false)); $columns.Add(@('Region', $false)) }
        foreach ($column in @(@('vCPU quota', $false), @('Used', $true), @('Limit', $true), @('Free', $true), @('Used %', $true))) { $columns.Add($column) }
        $table = & $newTable "[bold mediumpurple2]$($glyph.Bullet) vCPU quota[/] [grey58]$($glyph.Dot) the region, then each family of the sizes checked, most used first[/]" 'mediumpurple2' $columns.ToArray()
        $shown = @($Availability.Quotas | Where-Object { -not $_.Family -or $_.Used -gt 0 -or $_.Limit -eq 0 } | Select-Object -First 40)
        foreach ($item in $shown) {
            $color = if ($null -eq $item.UsedPercent) { 'grey50' } elseif ($item.UsedPercent -ge 90) { 'red1' } elseif ($item.UsedPercent -ge 70) { 'orange1' } else { 'green3' }
            & $addRow $table @(
                if ($multiple) { (& $escape $item.SubscriptionName); (& $escape $item.Location) }
                $(if ($item.Family) { & $escape $item.Quota } else { "[bold]$(& $escape $item.Quota)[/]" })
                (& $number $item.Used); (& $number $item.Limit)
                $(if ($item.Free -le 0) { "[bold red1]$(& $number $item.Free)[/]" } else { & $number $item.Free })
                $(if ($null -eq $item.UsedPercent) { '[grey50]-[/]' } else { "[$color]$($item.UsedPercent)%[/]" })
            )
        }
        [Spectre.Console.AnsiConsole]::Write($table)
        $unused = @($Availability.Quotas).Count - $shown.Count
        if ($unused -gt 0) { Write-AACMarkup "[grey50]  $unused more famil$(if ($unused -eq 1) { 'y' } else { 'ies' }) with nothing used; -HtmlPath or -PdfPath lists them.[/]" }
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    # --- AKS node pools --------------------------------------------------------------------------------------
    if (@($Availability.Pools).Count) {
        $table = & $newTable "[bold deepskyblue1]$($glyph.Bullet) The cluster's node pools[/] [grey58]$($glyph.Dot) their size here now, and the family's free vCPUs[/]" 'deepskyblue3' @(@('Pool', $false), @('Size', $false, $true), @('Nodes', $true), @('Zones', $false), @('Size status', $false), @('Family free', $true), @('Why', $false))
        foreach ($item in $Availability.Pools) {
            & $addRow $table @(
                "[bold]$(& $escape $item.Pool)[/]$(if ($item.Mode) { "`n[grey50]$(& $escape $item.Mode)$(if ($item.OsType) { ", $(& $escape $item.OsType)" })[/]" })"
                (& $escape $item.VmSize); (& $number $item.Nodes)
                $(if ($item.Zones) { & $escape $item.Zones } else { '[grey50]none[/]' })
                (& $status $item.SizeStatus); (& $number $item.FamilyVCpuFree)
                "[grey70]$(& $escape $item.Reason)[/]"
            )
        }
        [Spectre.Console.AnsiConsole]::Write($table)
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    # --- Sizes -----------------------------------------------------------------------------------------------
    $skus = @($Availability.Skus)
    if ($skus.Count) {
        $columns = [System.Collections.Generic.List[object]]::new()
        foreach ($column in @(@('Size', $false, $true), @('Status', $false))) { $columns.Add($column) }
        if ($multiple) { $columns.Add(@('Where', $false)) }
        foreach ($column in @(@('vCPUs', $true), @('GB', $true), @('Zones', $false))) { $columns.Add($column) }
        if ($wide) { $columns.Add(@('Family free', $true)); $columns.Add(@('Features', $false)) }
        $columns.Add(@('Why', $false))
        $table = & $newTable "[bold green3]$($glyph.Bullet) VM sizes[/] [grey58]$($glyph.Dot) usable first$(if ($skus.Count -gt $MaxSize) { ", the first $MaxSize of $($skus.Count)" })[/]" 'green4' $columns.ToArray()
        foreach ($item in @($skus | Select-Object -First $MaxSize)) {
            $features = @(
                if ($item.Architecture -eq 'Arm64') { 'Arm64' }
                if ($item.GPUs) { "$($item.GPUs) GPU" }
                if ($item.EphemeralOSDisk) { 'ephemeral OS' }
                if ($item.AcceleratedNetworking) { 'accel. net' }
                if ($item.PremiumStorage) { 'premium' }
            )
            $zones = if ($item.Zones) { & $escape $item.Zones } else { '[grey50]none[/]' }
            if ($item.ZonesMissing) { $zones += " [red1]-$(& $escape $item.ZonesMissing)[/]" }
            $why = @($item.Reason, $item.Note, $(if ($item.InUse) { "in use: $($item.InUse)" })) | Where-Object { $_ }
            & $addRow $table @(
                "[bold]$(& $escape $item.Sku)[/]"
                (& $status $item.Status)
                if ($multiple) { "[grey70]$(& $escape $item.Location)$(if ($stats.Subscriptions -gt 1) { "`n$(& $escape $item.SubscriptionName)" })[/]" }
                (& $number $item.vCPUs); ('{0:0.##}' -f $item.MemoryGB); $zones
                if ($wide) { (& $number $item.FamilyVCpuFree); "[grey70]$(& $escape ($features -join ', '))[/]" }
                "[grey70]$(& $escape ($why -join '; '))[/]"
            )
        }
        [Spectre.Console.AnsiConsole]::Write($table)
        if ($skus.Count -gt $MaxSize) { Write-AACMarkup "[grey50]  ... and $($skus.Count - $MaxSize) more: narrow with -Series, -Sku or -Architecture, or use -PassThru, -CsvPath or -HtmlPath for them all.[/]" }
        [Spectre.Console.AnsiConsole]::WriteLine()
    }
    Write-AACMarkup '[grey42]Read-only: Microsoft.Compute SKUs (offered zones and the subscription''s restrictions), vCPU usage and the zone mapping. Capacity at deployment time can''t be checked without deploying. Add -PassThru (or pipe the command) for the sizes as objects; -CsvPath, -PdfPath or -HtmlPath for a report.[/]'
}
