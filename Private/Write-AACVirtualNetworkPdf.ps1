function Write-AACVirtualNetworkPdf {
    <#
    .SYNOPSIS
        Writes the virtual network assessment
        (ConvertTo-AACVirtualNetworkAssessment) as a landscape A4 PDF report.
    .DESCRIPTION
        1. Summary: title, scope, tiles, and a table of the networks - role,
           address space, IPs used and available, subnets, peerings, DNS,
           DDoS, flow logs, findings by severity.
        2. Findings, most severe first: severity (High red, Medium amber, Low
           blue, Info grey), category, where, what was found, what to do.
        3. One section per network (a bookmark each): its facts, subnets
           with their capacity, NSG, routes and outbound path, peerings,
           free ranges and private endpoints.

        -Path must be a full path; see Save-AACPdfDocument.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Assessment,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Title,

        [System.Collections.IDictionary] $Detail
    )

    $stats = $Assessment.Stats
    $vnets = @($Assessment.VirtualNetworks)
    $pdf = New-AACPdfDocument -Title $Title -Subject "$($stats.VirtualNetworks) virtual networks" -Landscape
    $section = $pdf.Section
    $colors = $pdf.Colors
    $pt = $pdf.Pt
    $right = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Right
    $blue = [MigraDoc.DocumentObjectModel.Color]::Parse('#0369A1')
    $severityColor = @{ High = $pdf.Tone.Bad.Solid; Medium = $pdf.Tone.Warn.Solid; Low = $blue; Info = $colors.Muted }
    $small = { param($Paragraph) $Paragraph.Format.Font.Size = 7.5; $Paragraph }
    $muted = { param($Paragraph) $Paragraph.Format.Font.Size = 7.5; $Paragraph.Format.Font.Color = $colors.Muted; $Paragraph }
    $number = { param($Cell, $Value) $p = & $small ($Cell.AddParagraph($(if ($null -eq $Value) { '-' } else { '{0:N0}' -f $Value }))); $p.Format.Alignment = $right; $p }
    $colored = {
        param($Cell, [string] $Text, $Color, [switch] $Bold)
        $p = $Cell.AddParagraph($Text)
        if ($Color) { $p.Format.Font.Color = $Color }
        if ($Bold) { $p.Format.Font.Name = 'Segoe UI Semibold' }
        $p
    }
    $usageColor = { param($Percent) if ($null -eq $Percent) { $colors.Muted } elseif ($Percent -ge 95) { $pdf.Tone.Bad.Solid } elseif ($Percent -ge 80) { $pdf.Tone.Warn.Solid } else { $pdf.Tone.Good.Solid } }
    $findingCounts = {
        param($Cell, $Item)
        $p = $Cell.AddParagraph()
        $p.Format.Alignment = $right
        foreach ($level in 'High', 'Medium', 'Low') {
            $n = [int]$Item.$level
            if (-not $n) { continue }
            $t = $p.AddFormattedText("$($level.Substring(0, 1))$n ")
            $t.Color = $severityColor[$level]
            $t.Bold = $true
        }
    }

    # --- 1. Summary ---------------------------------------------------------------------------------
    & $pdf.AddTitle "Virtual network assessment · generated $($pdf.Generated.ToString('dddd d MMMM yyyy, HH:mm'))"
    $facts = [ordered]@{}
    if ($script:AACSession) { $facts['Azure account'] = [string]$script:AACSession.Account; $facts['Tenant'] = [string]$script:AACSession.TenantId }
    if ($Detail) { foreach ($key in $Detail.Keys) { $facts[[string]$key] = [string]$Detail[$key] } }
    $facts['How IPs are counted'] = 'Usable: each subnet''s addresses less the 5 Azure keeps. Used: the IP configurations in the subnet (NICs, private endpoints, gateways, load balancers). Unallocated: addresses in no subnet.'
    foreach ($key in @($Assessment['Failed'] | Where-Object { $_ })) { $facts["Not read: $key"] = 'The findings that need them may be missing.' }
    $factTable = & $pdf.NewTable @(4.0, ($pdf.PageWidth - 4.0))
    foreach ($key in $facts.Keys) {
        $row = & $pdf.AddBodyRow $factTable
        $row.Cells[0].AddParagraph($key).Format.Font.Color = $colors.Muted
        $row.Cells[1].AddParagraph($facts[$key]) | Out-Null
    }
    $section.AddParagraph().Format.SpaceAfter = & $pt 6
    $tileData = @(
        @{ Value = $stats.VirtualNetworks; Label = 'virtual networks' }
        @{ Value = $stats.Subnets; Label = 'subnets' }
        @{ Value = $stats.AvailableIps; Label = "IPs available ($($stats.UsedPercent)% used)"; Color = $pdf.Tone.Good.Solid }
        @{ Value = $stats.FullSubnets; Label = 'subnets 80%+ used'; Color = $(if ($stats.FullSubnets) { $pdf.Tone.Warn.Solid }) }
        @{ Value = $stats.PeeringProblems; Label = 'peering problems'; Color = $(if ($stats.PeeringProblems) { $pdf.Tone.Bad.Solid }) }
        @{ Value = $stats.High; Label = 'high findings'; Color = $(if ($stats.High) { $pdf.Tone.Bad.Solid }) }
        @{ Value = $stats.Medium; Label = 'medium findings'; Color = $(if ($stats.Medium) { $pdf.Tone.Warn.Solid }) }
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
        $value.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Center
        $value.Format.Font.Size = 18
        $value.Format.Font.Name = 'Segoe UI Semibold'
        if ($tileData[$i].Contains('Color') -and $tileData[$i].Color) { $value.Format.Font.Color = $tileData[$i].Color }
        $caption = $cell.AddParagraph($tileData[$i].Label)
        $caption.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Center
        $caption.Format.Font.Size = 8
        $caption.Format.Font.Color = $colors.Muted
    }

    $section.AddParagraph('Virtual networks', 'Heading2') | Out-Null
    $table = & $pdf.NewTable @(5.2, 1.7, 3.6, 1.5, 2.0, 2.0, 1.6, 2.8, 2.5, 1.6, 1.6)
    & $pdf.AddHeaderRow $table @('Network', 'Role', 'Address space', 'Subnets', 'Used', 'Available', 'Peerings', 'DNS', 'DDoS / flow logs', 'Used %', 'Findings') @(3, 4, 5, 6, 9, 10)
    foreach ($vnet in $vnets) {
        $row = & $pdf.AddBodyRow $table
        $name = $row.Cells[0].AddParagraph($vnet.Name)
        $name.Format.Font.Name = 'Segoe UI Semibold'
        & $muted ($row.Cells[0].AddParagraph("$($vnet.Location) · $($vnet.ResourceGroup) · $($vnet.SubscriptionName)")) | Out-Null
        & $small ($row.Cells[1].AddParagraph($vnet.Role)) | Out-Null
        & $small ($row.Cells[2].AddParagraph(($vnet.AddressSpace -replace ', ', "`n"))) | Out-Null
        if ($vnet.Overlaps) { (& $small ($row.Cells[2].AddParagraph("overlaps $($vnet.Overlaps)"))).Format.Font.Color = $pdf.Tone.Warn.Solid }
        & $number $row.Cells[3] $vnet.SubnetCount | Out-Null
        & $number $row.Cells[4] $vnet.UsedIps | Out-Null
        & $number $row.Cells[5] $vnet.AvailableIps | Out-Null
        $peers = & $number $row.Cells[6] $vnet.PeeringCount
        if ($vnet.PeeringsNotConnected) { $peers.Format.Font.Color = $pdf.Tone.Bad.Solid }
        & $small ($row.Cells[7].AddParagraph($vnet.DnsServers)) | Out-Null
        & $small ($row.Cells[8].AddParagraph($vnet.DdosProtection)) | Out-Null
        (& $small ($row.Cells[8].AddParagraph("Flow logs: $($vnet.FlowLogs)"))).Format.Font.Color = $(if ($vnet.FlowLogs -eq 'None') { $pdf.Tone.Warn.Solid } else { $colors.Muted })
        $used = & $small ($row.Cells[9].AddParagraph($(if ($null -eq $vnet.UsedPercent) { '-' } else { "$($vnet.UsedPercent)%" })))
        $used.Format.Alignment = $right
        $used.Format.Font.Color = & $usageColor $vnet.UsedPercent
        & $findingCounts $row.Cells[10] $vnet
    }

    # --- 2. Findings --------------------------------------------------------------------------------------
    $findings = @($Assessment.Findings)
    if ($findings.Count) {
        $section.AddPageBreak()
        $section.AddParagraph('Findings', 'Heading2') | Out-Null
        $table = & $pdf.NewTable @(1.8, 2.3, 4.2, 4.2, 7.6, 6.0)
        & $pdf.AddHeaderRow $table @('Severity', 'Category', 'Finding', 'Where', 'What was found', 'What to do')
        foreach ($finding in $findings) {
            $row = & $pdf.AddBodyRow $table
            & $colored $row.Cells[0] $finding.Severity $severityColor[$finding.Severity] -Bold | Out-Null
            & $small ($row.Cells[1].AddParagraph($finding.Category)) | Out-Null
            & $small ($row.Cells[2].AddParagraph($finding.Finding)) | Out-Null
            & $small ($row.Cells[3].AddParagraph((@($finding.VirtualNetwork, $finding.Item) | Where-Object { $_ }) -join "`n")) | Out-Null
            & $small ($row.Cells[4].AddParagraph($finding.Detail)) | Out-Null
            & $muted ($row.Cells[5].AddParagraph($finding.Action)) | Out-Null
        }
    }

    # --- 3. Each network ------------------------------------------------------------------------------------
    foreach ($vnet in $vnets) {
        $section.AddPageBreak()
        $section.AddParagraph("$($vnet.Name) ($($vnet.Role))", 'Heading1') | Out-Null
        & $muted ($section.AddParagraph($vnet.ResourceId)) | Out-Null
        $meta = & $pdf.NewTable @(3.6, 9.4, 3.6, 9.5)
        $pairs = @(
            , @('Subscription', $vnet.SubscriptionName, 'Resource group', $vnet.ResourceGroup)
            , @('Location', $vnet.Location, 'Tags', $vnet.Tags)
            , @('Address space', $vnet.AddressSpace, 'IPs', "$('{0:N0}' -f $vnet.TotalIps) in all; $('{0:N0}' -f $vnet.IpsInSubnets) in subnets, $('{0:N0}' -f $vnet.UnallocatedIps) unallocated`n$('{0:N0}' -f $vnet.UsableIps) usable, $('{0:N0}' -f $vnet.UsedIps) used, $('{0:N0}' -f $vnet.AvailableIps) available")
            , @('DNS servers', $vnet.DnsServers, 'Private DNS zones', $vnet.PrivateDnsZones)
            , @('DDoS', $vnet.DdosProtection, 'Encryption', $vnet.Encryption)
            , @('Flow logs', $vnet.FlowLogs, 'DNS resolvers', $vnet.DnsResolvers)
            , @('Gateways', $vnet.Gateways, 'Firewalls / Bastion', ((@($vnet.Firewalls, $vnet.Bastions) | Where-Object { $_ }) -join "`n"))
            , @('Overlaps with', $vnet.Overlaps, 'Flow timeout / BGP', ((@($(if ($vnet.FlowTimeoutMinutes) { "$($vnet.FlowTimeoutMinutes) min" }), $vnet.BgpCommunity) | Where-Object { $_ }) -join ' · '))
        )
        foreach ($pair in $pairs) {
            $row = & $pdf.AddBodyRow $meta
            $row.Cells[0].AddParagraph($pair[0]).Format.Font.Color = $colors.Muted
            & $small ($row.Cells[1].AddParagraph($(if ($pair[1]) { [string]$pair[1] } else { '-' }))) | Out-Null
            $row.Cells[2].AddParagraph($pair[2]).Format.Font.Color = $colors.Muted
            & $small ($row.Cells[3].AddParagraph($(if ($pair[3]) { [string]$pair[3] } else { '-' }))) | Out-Null
        }

        if ($vnet.Subnets.Count) {
            $section.AddParagraph('Subnets', 'Heading3') | Out-Null
            $table = & $pdf.NewTable @(4.2, 2.6, 1.4, 1.4, 1.4, 2.8, 4.4, 4.0, 3.9)
            & $pdf.AddHeaderRow $table @('Subnet', 'Prefix', 'Usable', 'Used', 'Free', 'NSG', 'Route / outbound', 'Endpoints / delegations', 'Workloads') @(2, 3, 4)
            foreach ($subnet in $vnet.Subnets) {
                $row = & $pdf.AddBodyRow $table
                & $small ($row.Cells[0].AddParagraph($subnet.Subnet)) | ForEach-Object { $_.Format.Font.Name = 'Segoe UI Semibold' }
                & $muted ($row.Cells[0].AddParagraph($subnet.Purpose)) | Out-Null
                & $small ($row.Cells[1].AddParagraph($subnet.Prefix)) | Out-Null
                & $number $row.Cells[2] $subnet.Usable | Out-Null
                (& $number $row.Cells[3] $subnet.Used).Format.Font.Color = & $usageColor $subnet.UsedPercent
                & $number $row.Cells[4] $subnet.Available | Out-Null
                if ($subnet.Nsg) { & $small ($row.Cells[5].AddParagraph($subnet.Nsg)) | Out-Null }
                elseif ($subnet.Purpose -in 'Gateway', 'Azure Firewall', 'Azure Firewall management', 'Route Server') { & $muted ($row.Cells[5].AddParagraph('n/a')) | Out-Null }
                else { (& $small ($row.Cells[5].AddParagraph('none'))).Format.Font.Color = $pdf.Tone.Warn.Solid }
                & $small ($row.Cells[6].AddParagraph((@($(if ($subnet.RouteTable) { "$($subnet.RouteTable): $(if ($subnet.DefaultRoute) { "0.0.0.0/0 → $($subnet.DefaultRoute)" } else { 'no default route' })" }), $(if ($subnet.NatGateway) { "NAT: $($subnet.NatGateway)" }), $subnet.Outbound) | Where-Object { $_ } | Select-Object -Unique) -join "`n")) | Out-Null
                & $small ($row.Cells[7].AddParagraph((@($(if ($subnet.ServiceEndpoints) { "SE: $($subnet.ServiceEndpoints)" }), $(if ($subnet.Delegations) { "Delegated: $($subnet.Delegations)" }), $(if ($subnet.PrivateEndpoints) { "$($subnet.PrivateEndpoints) private endpoint(s), policies $($subnet.PrivateEndpointPolicies)" })) | Where-Object { $_ }) -join "`n")) | Out-Null
                & $small ($row.Cells[8].AddParagraph($(if ($subnet.Nics) { "$($subnet.Nics) NIC(s), $($subnet.Vms) VM(s)$(if ($subnet.PublicIpNics) { "`n$($subnet.PublicIpNics) with a public IP" })" } else { '' }))) | Out-Null
            }
        }
        if ($vnet.Peerings.Count) {
            $section.AddParagraph('Peerings', 'Heading3') | Out-Null
            $table = & $pdf.NewTable @(4.0, 5.0, 2.2, 2.8, 3.0, 2.2, 6.9)
            & $pdf.AddHeaderRow $table @('Peering', 'Remote network', 'State', 'Sync', 'Gateway transit', 'Forwarded', 'Remote address space')
            foreach ($peering in $vnet.Peerings) {
                $row = & $pdf.AddBodyRow $table
                & $small ($row.Cells[0].AddParagraph($peering.Peering)) | Out-Null
                & $small ($row.Cells[1].AddParagraph($peering.RemoteVirtualNetwork)) | Out-Null
                & $muted ($row.Cells[1].AddParagraph((@($peering.RemoteSubscription, $peering.RemoteLocation, $(if ($peering.Global) { 'global' })) | Where-Object { $_ }) -join ' · ')) | Out-Null
                & $colored $row.Cells[2] $peering.State $(if ($peering.State -eq 'Connected') { $pdf.Tone.Good.Solid } else { $pdf.Tone.Bad.Solid }) -Bold | Out-Null
                & $colored $row.Cells[3] $peering.Sync $(if ($peering.Sync -in '', 'FullyInSync') { $pdf.Tone.Good.Solid } else { $pdf.Tone.Warn.Solid }) | Out-Null
                & $small ($row.Cells[4].AddParagraph($(if ($peering.AllowGatewayTransit) { 'offers transit' } elseif ($peering.UseRemoteGateways) { 'uses remote gateways' } else { '-' }))) | Out-Null
                & $small ($row.Cells[5].AddParagraph($(if ($peering.AllowForwardedTraffic) { 'allowed' } else { 'blocked' }))) | Out-Null
                & $small ($row.Cells[6].AddParagraph($peering.RemoteAddressSpace)) | Out-Null
            }
        }
        $ranges = @($vnet.FreeRangeList | ForEach-Object { $_.Prefix })
        $section.AddParagraph('Free for new subnets', 'Heading3') | Out-Null
        & $small ($section.AddParagraph($(if ($ranges.Count) { $ranges -join ', ' } else { 'None: every address is in a subnet.' }))) | Out-Null
        if ($vnet.PrivateEndpointList.Count) {
            $section.AddParagraph('Private endpoints', 'Heading3') | Out-Null
            $table = & $pdf.NewTable @(4.4, 3.0, 5.0, 5.4, 2.6, 2.4, 3.3)
            & $pdf.AddHeaderRow $table @('Private endpoint', 'Subnet', 'Target', 'Target type', 'Sub-resource', 'Connection', 'Zone linked')
            foreach ($endpoint in $vnet.PrivateEndpointList) {
                $row = & $pdf.AddBodyRow $table
                & $small ($row.Cells[0].AddParagraph($endpoint.PrivateEndpoint)) | Out-Null
                & $small ($row.Cells[1].AddParagraph($endpoint.Subnet)) | Out-Null
                & $small ($row.Cells[2].AddParagraph($endpoint.Target)) | Out-Null
                & $small ($row.Cells[3].AddParagraph($endpoint.TargetType)) | Out-Null
                & $small ($row.Cells[4].AddParagraph($endpoint.Groups)) | Out-Null
                & $colored $row.Cells[5] $endpoint.Status $(if ($endpoint.Status -eq 'Approved') { $pdf.Tone.Good.Solid } else { $pdf.Tone.Warn.Solid }) | Out-Null
                & $colored $row.Cells[6] $endpoint.ZoneLinked $(if ($endpoint.ZoneLinked -eq 'No') { $pdf.Tone.Bad.Solid } else { $colors.Muted }) | Out-Null
            }
        }
    }

    Save-AACPdfDocument -Pdf $pdf -Path $Path
}
