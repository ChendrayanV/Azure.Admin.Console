function Show-AACVirtualNetworkView {
    <#
    .SYNOPSIS
        Renders the virtual network assessment
        (ConvertTo-AACVirtualNetworkAssessment) as a Spectre.Console view.
    .DESCRIPTION
        The scope; tiles (networks, subnets, available IPs, subnets 80% used
        or more, peering problems, High and Medium findings); a table of the
        networks - role, address space, IPs used and available, peerings,
        DNS, DDoS, flow logs, findings by severity; the fullest subnets as a
        bar chart; the High and Medium findings with what to do; and, for up
        to -Detail networks, each one in detail: its facts, subnets (with
        their capacity, NSG, routes and outbound path), peerings and free
        ranges. Severities: High red, Medium amber, Low blue, Info grey.
        Output goes straight to the Spectre console; wrap the call in
        Invoke-AACPagedOutput to page it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Assessment,

        [System.Collections.IDictionary] $Scope,

        [int] $Detail = 3
    )

    $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
    $glyph = Get-AACGlyph
    $stats = $Assessment.Stats
    $vnets = @($Assessment.VirtualNetworks)
    $severityColor = @{ High = 'red1'; Medium = 'orange1'; Low = 'deepskyblue1'; Info = 'grey62' }
    $counts = {
        param($Item)
        $parts = foreach ($level in 'High', 'Medium', 'Low') {
            $n = [int]$Item.$level
            if ($n) { "[$($severityColor[$level])]$($level.Substring(0, 1))$n[/]" }
        }
        if ($parts) { $parts -join ' ' } else { "[green3]$($glyph.Tick)[/]" }
    }
    $usage = {
        param($Percent)
        if ($null -eq $Percent) { return '[grey50]-[/]' }
        $color = if ($Percent -ge 95) { 'red1' } elseif ($Percent -ge 80) { 'orange1' } else { 'green3' }
        "[$color]$Percent%[/]"
    }
    $newTable = {
        param([string] $TitleText, [string] $Border, [string[]] $Headers, [string[]] $Right = @())
        $table = [Spectre.Console.Table]::new()
        $table.Border = [Spectre.Console.TableBorder]::Rounded
        $table.BorderStyle = [Spectre.Console.Style]::Parse($Border)
        $table.Expand = $true
        if ($TitleText) { $table.Title = [Spectre.Console.TableTitle]::new($TitleText) }
        foreach ($header in $Headers) {
            $column = [Spectre.Console.TableColumn]::new("[grey62]$header[/]")
            if ($header -in $Right) { $column.Alignment = [Spectre.Console.Justify]::Right }
            $table.AddColumn($column) | Out-Null
        }
        $table
    }
    $addRow = { param($Table, [string[]] $Cells) [Spectre.Console.TableExtensions]::AddRow($Table, [Spectre.Console.Rendering.IRenderable[]]@($Cells | ForEach-Object { [Spectre.Console.Markup]::new($_) })) | Out-Null }

    $facts = [System.Collections.Generic.List[string]]::new()
    if ($script:AACSession) { $facts.Add("[white]$(& $escape $script:AACSession.Account)[/]") }
    if ($Scope) { foreach ($key in $Scope.Keys) { $facts.Add("$(& $escape $key): $(& $escape $Scope[$key])") } }
    $facts.Add((Get-Date).ToString('d MMM yyyy HH:mm'))
    Write-AACMarkup "[grey58]$($facts -join " $($glyph.Dot) ")[/]"
    foreach ($key in @($Assessment['Failed'] | Where-Object { $_ })) { Write-AACMarkup "[orange1]The $(& $escape $key) couldn't be read: the findings that need them may be missing.[/]" }
    [Spectre.Console.AnsiConsole]::WriteLine()

    if (-not $vnets.Count) {
        Show-AACCallout Info -Message '[bold]No virtual networks[/] [grey58]were found in this scope.[/]'
        return
    }
    Show-AACTileRow -Tile @(
        @{ Value = '{0:N0}' -f $stats.VirtualNetworks; Caption = 'virtual networks'; Color = 'deepskyblue1' }
        @{ Value = '{0:N0}' -f $stats.Subnets; Caption = 'subnets'; Color = 'grey70' }
        @{ Value = '{0:N0}' -f $stats.AvailableIps; Caption = "IPs available ($($stats.UsedPercent)% used)"; Color = 'green3' }
        @{ Value = '{0:N0}' -f $stats.FullSubnets; Caption = 'subnets 80%+ used'; Color = $(if ($stats.FullSubnets) { 'orange1' } else { 'green3' }) }
        @{ Value = '{0:N0}' -f $stats.PeeringProblems; Caption = 'peering problems'; Color = $(if ($stats.PeeringProblems) { 'red1' } else { 'green3' }) }
        @{ Value = '{0:N0}' -f $stats.High; Caption = 'high findings'; Color = $(if ($stats.High) { 'red1' } else { 'green3' }) }
        @{ Value = '{0:N0}' -f $stats.Medium; Caption = 'medium findings'; Color = $(if ($stats.Medium) { 'orange1' } else { 'green3' }) }
    )
    [Spectre.Console.AnsiConsole]::WriteLine()

    # --- The networks ------------------------------------------------------------------------------------------
    $table = & $newTable "[bold]$($glyph.Bullet) Virtual networks[/] [grey58]$($glyph.Dot) most at risk first[/]" 'deepskyblue3_1' @('Network', 'Role', 'Address space', 'Subnets', 'IPs used', 'Available', 'Peerings', 'DNS', 'DDoS', 'Flow logs', 'Findings') @('Subnets', 'Available', 'Peerings')
    foreach ($vnet in $vnets) {
        & $addRow $table @(
            "[bold]$(& $escape $vnet.Name)[/]`n[grey50]$(& $escape $vnet.Location) $($glyph.Dot) $(& $escape $vnet.ResourceGroup) $($glyph.Dot) $(& $escape $vnet.SubscriptionName)[/]"
            "[grey85]$(& $escape $vnet.Role)[/]"
            "[grey85]$(& $escape ($vnet.AddressSpace -replace ', ', "`n"))[/]$(if ($vnet.Overlaps) { "`n[orange1]overlaps $(& $escape $vnet.Overlaps)[/]" })"
            "$($vnet.SubnetCount)"
            "$('{0:N0}' -f $vnet.UsedIps) [grey50]of $('{0:N0}' -f $vnet.UsableIps)[/]`n$(& $usage $vnet.UsedPercent)"
            "$('{0:N0}' -f $vnet.AvailableIps)$(if ($vnet.UnallocatedIps) { "`n[grey50]+$('{0:N0}' -f $vnet.UnallocatedIps) free[/]" })"
            "$($vnet.PeeringCount)$(if ($vnet.PeeringsNotConnected) { " [red1]$($vnet.PeeringsNotConnected) down[/]" })"
            "[grey85]$(& $escape $vnet.DnsServers)[/]"
            "[$(if ($vnet.DdosProtection -eq 'Infrastructure only') { 'grey62' } else { 'green3' })]$(& $escape $vnet.DdosProtection)[/]"
            "[$(if ($vnet.FlowLogs -eq 'None') { 'orange1' } else { 'green3' })]$(& $escape $vnet.FlowLogs)[/]"
            (& $counts $vnet)
        )
    }
    [Spectre.Console.AnsiConsole]::Write($table)
    [Spectre.Console.AnsiConsole]::WriteLine()

    # --- The fullest subnets ------------------------------------------------------------------------------------
    $fullest = @($Assessment.Subnets | Where-Object { $null -ne $_.UsedPercent -and $_.Used -gt 0 } | Sort-Object -Property @{ Expression = 'UsedPercent'; Descending = $true }, Subnet | Select-AACFirst 12 | ForEach-Object { @{ Label = "$($_.VirtualNetwork)/$($_.Subnet)"; Value = $_.UsedPercent } })
    if ($fullest.Count) {
        Show-AACBarChart -Item $fullest -Title 'Subnets by IPs used (%)'
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    # --- High and Medium findings ----------------------------------------------------------------------------
    $serious = @($Assessment.Findings | Where-Object { $_.Severity -in 'High', 'Medium' })
    if ($serious.Count) {
        Write-AACMarkup "[bold]$($glyph.Bullet) Findings[/] [grey58]$($glyph.Dot) High and Medium, $($serious.Count) in all[/]"
        foreach ($finding in $serious) {
            $color = $severityColor[$finding.Severity]
            $where = @($finding.VirtualNetwork, $finding.Item | Where-Object { $_ }) -join ' / '
            Write-AACMarkup "  [$color]$($finding.Severity.ToUpperInvariant().PadRight(6))[/] [white]$(& $escape $where)[/] [grey62]$(& $escape $finding.Finding)[/] [grey42]$(& $escape $finding.Category)[/]"
            Write-AACMarkup "         [grey85]$(& $escape $finding.Detail)[/]"
            if ($finding.Action) { Write-AACMarkup "         [grey50]$($glyph.Arrow) $(& $escape $finding.Action)[/]" }
        }
        [Spectre.Console.AnsiConsole]::WriteLine()
    }
    $minor = @($Assessment.Findings | Where-Object { $_.Severity -in 'Low', 'Info' }).Count
    if ($minor) { Write-AACMarkup "[grey42]$minor Low and Info finding(s) more: -HtmlPath or -PdfPath has them all, or (... -NoDisplay).Findings.[/]"; [Spectre.Console.AnsiConsole]::WriteLine() }

    # --- A few networks in detail ------------------------------------------------------------------------------
    if ($vnets.Count -le $Detail) {
        foreach ($vnet in $vnets) {
            Write-AACRule -Title "[bold]$(& $escape $vnet.Name)[/] [grey58]$(& $escape $vnet.Role)[/]" -Color 'grey50'
            Write-AACMarkup "[grey58]$(& $escape $vnet.ResourceId)[/]"
            Write-AACMarkup "[grey58]Address space[/] $(& $escape $vnet.AddressSpace)  [grey58]IPs[/] $('{0:N0}' -f $vnet.TotalIps) [grey50]($('{0:N0}' -f $vnet.IpsInSubnets) in subnets, $('{0:N0}' -f $vnet.UnallocatedIps) unallocated)[/]  [grey58]Usable[/] $('{0:N0}' -f $vnet.UsableIps)  [grey58]Used[/] $('{0:N0}' -f $vnet.UsedIps)  [grey58]Available[/] $('{0:N0}' -f $vnet.AvailableIps)"
            Write-AACMarkup "[grey58]DNS[/] $(& $escape $vnet.DnsServers)$(if ($vnet.PrivateDnsZones) { "  [grey58]Private DNS zones[/] $(& $escape $vnet.PrivateDnsZones)" })$(if ($vnet.DnsResolvers) { "  [grey58]Resolvers[/] $(& $escape $vnet.DnsResolvers)" })"
            Write-AACMarkup "[grey58]DDoS[/] $(& $escape $vnet.DdosProtection)  [grey58]Encryption[/] $(& $escape $vnet.Encryption)  [grey58]Flow logs[/] $(& $escape $vnet.FlowLogs)"
            $edges = @(@('Gateways', $vnet.Gateways), @('Firewalls', $vnet.Firewalls), @('Bastion', $vnet.Bastions)) | Where-Object { $_[1] } | ForEach-Object { "[grey58]$($_[0])[/] $(& $escape $_[1])" }
            if ($edges) { Write-AACMarkup ($edges -join '  ') }
            [Spectre.Console.AnsiConsole]::WriteLine()

            $table = & $newTable '[bold]Subnets[/]' 'grey42' @('Subnet', 'Prefix', 'Usable', 'Used', 'Free', 'NSG', 'Route / outbound', 'Endpoints and delegations') @('Usable', 'Used', 'Free')
            foreach ($subnet in $vnet.Subnets) {
                $extras = @(
                    if ($subnet.ServiceEndpoints) { "SE: $($subnet.ServiceEndpoints)" }
                    if ($subnet.Delegations) { "delegated: $($subnet.Delegations)" }
                    if ($subnet.PrivateEndpoints) { "$($subnet.PrivateEndpoints) private endpoint(s)" }
                    if ($subnet.Nics) { "$($subnet.Nics) NIC(s), $($subnet.Vms) VM(s)$(if ($subnet.PublicIpNics) { ", $($subnet.PublicIpNics) with a public IP" })" }
                ) -join "`n"
                & $addRow $table @(
                    "[white]$(& $escape $subnet.Subnet)[/]`n[grey50]$(& $escape $subnet.Purpose)[/]"
                    "[grey85]$(& $escape $subnet.Prefix)[/]"
                    "$($subnet.Usable)"
                    "$($subnet.Used)`n$(& $usage $subnet.UsedPercent)"
                    "$($subnet.Available)"
                    $(if ($subnet.Nsg) { "[grey85]$(& $escape $subnet.Nsg)[/]" } elseif ($subnet.Purpose -in 'Gateway', 'Azure Firewall', 'Azure Firewall management', 'Route Server') { '[grey50]n/a[/]' } else { '[orange1]none[/]' })
                    "[grey85]$(& $escape (@($subnet.DefaultRoute, $subnet.Outbound) | Where-Object { $_ } | Select-Object -Unique) -join "`n")[/]"
                    "[grey62]$(& $escape $extras)[/]"
                )
            }
            if ($vnet.Subnets.Count) { [Spectre.Console.AnsiConsole]::Write($table) }
            if ($vnet.Peerings.Count) {
                $table = & $newTable '[bold]Peerings[/]' 'grey42' @('Peering', 'Remote network', 'State', 'Sync', 'Gateway', 'Forwarded', 'Remote address space')
                foreach ($peering in $vnet.Peerings) {
                    & $addRow $table @(
                        "[white]$(& $escape $peering.Peering)[/]"
                        "[grey85]$(& $escape $peering.RemoteVirtualNetwork)[/]`n[grey50]$(& $escape (@($peering.RemoteSubscription, $peering.RemoteLocation) | Where-Object { $_ }) -join ' · ')$(if ($peering.Global) { ' · global' })[/]"
                        "[$(if ($peering.State -eq 'Connected') { 'green3' } else { 'red1' })]$(& $escape $peering.State)[/]"
                        "[$(if ($peering.Sync -in '', 'FullyInSync') { 'green3' } else { 'orange1' })]$(& $escape $peering.Sync)[/]"
                        "[grey85]$(if ($peering.AllowGatewayTransit) { 'offers transit' } elseif ($peering.UseRemoteGateways) { 'uses remote' } else { '-' })[/]"
                        "[grey85]$(if ($peering.AllowForwardedTraffic) { 'allowed' } else { 'blocked' })[/]"
                        "[grey85]$(& $escape $peering.RemoteAddressSpace)[/]"
                    )
                }
                [Spectre.Console.AnsiConsole]::Write($table)
            }
            $ranges = @($vnet.FreeRangeList | Select-AACFirst 10 | ForEach-Object { $_.Prefix })
            Write-AACMarkup "[grey58]Free for new subnets[/] $(if ($ranges.Count) { "[green3]$(& $escape ($ranges -join ', '))[/]$(if ($vnet.FreeRangeList.Count -gt 10) { " [grey50]and $($vnet.FreeRangeList.Count - 10) more[/]" })" } else { '[orange1]none - every address is in a subnet[/]' })"
            [Spectre.Console.AnsiConsole]::WriteLine()
        }
    }
    else {
        Write-AACMarkup "[grey42]-Name shows a network in detail with its subnets, peerings and free ranges; -HtmlPath or -PdfPath has every one.[/]"
    }
    Write-AACMarkup "[grey42]Add -PassThru (or pipe the command) for the objects; -CsvPath writes every subnet.[/]"
}
