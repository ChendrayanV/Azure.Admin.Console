function Write-AACFirewallRulePdf {
    <#
    .SYNOPSIS
        Writes AAC.FirewallRule objects (from Get-AACFirewallRule) as a
        landscape A4 PDF report.
    .DESCRIPTION
        Layout:
          1. Summary: title, where the rules came from, tiles with the number
             of policies, rule collection groups, rule collections and DNAT,
             network and application rules, and one row per policy (base
             policy, firewalls, location and counts).
          2. One part per policy (each starting on a new page): its rule
             collection groups by priority, and in each its rule collections
             by priority with their type and action (Allow in green, Deny in
             red, DNAT in amber), then a table of the collection's rules in
             order - source, destination, protocols and ports, and the DNAT
             translation or TLS inspection where there is one. IP Groups are
             shown by name with their addresses underneath.

        -Path must be a full path; see Save-AACPdfDocument.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Rule,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Title,

        [System.Collections.IDictionary] $Detail
    )

    $policyCount = @($Rule | Select-Object -ExpandProperty FirewallPolicyId -Unique).Count
    $pdf = New-AACPdfDocument -Title $Title -Subject "$($Rule.Count) Azure Firewall rules in $policyCount policies" -Landscape
    $section = $pdf.Section
    $colors = $pdf.Colors
    $pt = $pdf.Pt
    $actionTone = @{ Allow = $pdf.Tone.Good; Deny = $pdf.Tone.Bad; DNAT = $pdf.Tone.Warn }

    $count = { param([string] $Type) @($Rule | Where-Object RuleType -eq $Type).Count }
    $unique = { param([string] $Property) @($Rule | ForEach-Object { "$($_.FirewallPolicyId)|$($_.$Property)" } | Select-Object -Unique).Count }

    # Adds "label  values" as its own paragraph in a cell, when there are values.
    $addLabelled = {
        param($Cell, [string] $Label, [string] $Values)
        if (-not $Values) {
            return
        }
        $paragraph = $Cell.AddParagraph()
        if ($Label) {
            $labelText = $paragraph.AddFormattedText("$Label  ")
            $labelText.Size = 7
            $labelText.Color = $colors.Muted
        }
        $paragraph.AddText($Values) | Out-Null
    }
    # IP Groups as "name" in semibold with the addresses in small grey under
    # it, from Get-AACFirewallRule's "name: a, b | name2: c" format.
    $addIpGroups = {
        param($Cell, [string] $Described)
        if (-not $Described) {
            return
        }
        foreach ($entry in ($Described -split ' \| ')) {
            $name, $addresses = $entry -split ': ', 2
            $nameText = $Cell.AddParagraph()
            $label = $nameText.AddFormattedText('IP group  ')
            $label.Size = 7
            $label.Color = $colors.Muted
            $nameText.AddFormattedText($name).FontName = 'Segoe UI Semibold'
            if ($addresses) {
                $addressText = $Cell.AddParagraph($addresses)
                $addressText.Format.Font.Size = 7.5
                $addressText.Format.Font.Color = $colors.Muted
            }
        }
    }

    # --- 1. Summary ---------------------------------------------------------------
    & $pdf.AddTitle "$('{0:N0}' -f $Rule.Count) rules in $policyCount firewall $(if ($policyCount -eq 1) { 'policy' } else { 'policies' }) · generated $($pdf.Generated.ToString('dddd d MMMM yyyy, HH:mm'))"

    $facts = [ordered]@{}
    $session = Get-Variable -Name 'AACSession' -Scope Global -ValueOnly -ErrorAction Ignore
    if ($session) {
        $facts['Azure account'] = [string]$session.Account
        $facts['Tenant'] = [string]$session.TenantId
    }
    if ($Detail) {
        foreach ($key in $Detail.Keys) { $facts[[string]$key] = [string]$Detail[$key] }
    }
    $facts['Rule order'] = 'Listed by rule collection group priority, then rule collection priority, as in the Azure portal. Azure Firewall applies all DNAT rules first, then network rules, then application rules (each in that priority order), and a base policy''s rules before the policy''s own.'
    $factTable = & $pdf.NewTable @(4.0, ($pdf.PageWidth - 4.0))
    foreach ($key in $facts.Keys) {
        $row = & $pdf.AddBodyRow $factTable
        $row.Cells[0].AddParagraph($key).Format.Font.Color = $colors.Muted
        $row.Cells[1].AddParagraph($facts[$key]) | Out-Null
    }

    $section.AddParagraph().Format.SpaceAfter = & $pt 6
    $tileData = @(
        @{ Value = $policyCount; Label = 'policies' }
        @{ Value = (& $unique 'RuleCollectionGroup'); Label = 'rule collection groups' }
        @{ Value = (& $unique 'RuleCollection'); Label = 'rule collections' }
        @{ Value = (& $count 'NatRule'); Label = 'DNAT rules' }
        @{ Value = (& $count 'NetworkRule'); Label = 'network rules' }
        @{ Value = (& $count 'ApplicationRule'); Label = 'application rules' }
    )
    $tileWidth = $pdf.PageWidth / $tileData.Count
    $tiles = & $pdf.NewTable @(1..$tileData.Count | ForEach-Object { $tileWidth })
    $tiles.TopPadding = & $pt 8
    $tiles.BottomPadding = & $pt 8
    $tileRow = $tiles.AddRow()
    for ($i = 0; $i -lt $tileData.Count; $i++) {
        $cell = $tileRow.Cells[$i]
        $cell.Shading.Color = $colors.Panel
        $cell.Borders.Left.Width = $(if ($i -gt 0) { 2 } else { 0 })
        $cell.Borders.Left.Color = $colors.White
        $number = $cell.AddParagraph(('{0:N0}' -f $tileData[$i].Value))
        $number.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Center
        $number.Format.Font.Size = 18
        $number.Format.Font.Name = 'Segoe UI Semibold'
        $caption = $cell.AddParagraph($tileData[$i].Label)
        $caption.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Center
        $caption.Format.Font.Size = 8
        $caption.Format.Font.Color = $colors.Muted
    }

    $policyGroups = @($Rule | Group-Object -Property FirewallPolicyId | Sort-Object { $_.Group[0].FirewallPolicy })

    $section.AddParagraph('Firewall policies', 'Heading2') | Out-Null
    $policyTable = & $pdf.NewTable @(4.6, 3.4, 4.2, 5.3, 2.2, 1.3, 1.5, 1.2, 1.2, 1.2)
    & $pdf.AddHeaderRow $policyTable @('Policy', 'Base policy', 'Firewalls', 'Subscription · resource group', 'Location', 'Groups', 'Collections', 'DNAT', 'Network', 'App') @(5, 6, 7, 8, 9)
    foreach ($policy in $policyGroups) {
        $first = $policy.Group[0]
        $row = & $pdf.AddBodyRow $policyTable
        $row.Cells[0].AddParagraph($first.FirewallPolicy).Format.Font.Name = 'Segoe UI Semibold'
        $row.Cells[1].AddParagraph($(if ($first.BasePolicy) { $first.BasePolicy } else { '-' })) | Out-Null
        $row.Cells[2].AddParagraph($(if ($first.Firewalls) { $first.Firewalls } else { 'not attached' })) | Out-Null
        $row.Cells[3].AddParagraph("$(if ($first.SubscriptionName) { $first.SubscriptionName } else { $first.SubscriptionId }) · $($first.ResourceGroup)") | Out-Null
        $row.Cells[4].AddParagraph([string]$first.Location) | Out-Null
        $values = @(
            @($policy.Group | Select-Object -ExpandProperty RuleCollectionGroup -Unique).Count
            @($policy.Group | ForEach-Object { "$($_.RuleCollectionGroup)|$($_.RuleCollection)" } | Select-Object -Unique).Count
            @($policy.Group | Where-Object RuleType -eq 'NatRule').Count
            @($policy.Group | Where-Object RuleType -eq 'NetworkRule').Count
            @($policy.Group | Where-Object RuleType -eq 'ApplicationRule').Count
        )
        for ($i = 0; $i -lt $values.Count; $i++) {
            $number = $row.Cells[$i + 5].AddParagraph(('{0:N0}' -f $values[$i]))
            $number.Format.Alignment = [MigraDoc.DocumentObjectModel.ParagraphAlignment]::Right
            if ($values[$i] -eq 0) { $number.Format.Font.Color = $colors.Muted }
        }
    }
    if ($policyGroups.Count -eq 0) {
        $none = $section.AddParagraph('No Firewall Policy rules were found.')
        $none.Format.Font.Color = $colors.Muted
    }

    # --- 2. Every rule, policy by policy -------------------------------------------------
    foreach ($policy in $policyGroups) {
        $first = $policy.Group[0]
        $section.AddPageBreak()
        $section.AddParagraph($first.FirewallPolicy, 'Heading1') | Out-Null
        $about = $section.AddParagraph(@(
                "Base policy: $(if ($first.BasePolicy) { $first.BasePolicy } else { 'none' })"
                "Firewalls: $(if ($first.Firewalls) { $first.Firewalls } else { 'not attached' })"
                "$(if ($first.SubscriptionName) { $first.SubscriptionName } else { $first.SubscriptionId }) · $($first.ResourceGroup) · $($first.Location)"
            ) -join '  ·  ')
        $about.Format.Font.Color = $colors.Muted
        $about.Format.SpaceAfter = & $pt 4

        foreach ($group in @($policy.Group | Group-Object -Property RuleCollectionGroup | Sort-Object { $_.Group[0].RuleCollectionGroupPriority }, Name)) {
            $groupHeading = $section.AddParagraph('', 'Heading2')
            $groupHeading.AddText($group.Name) | Out-Null
            $groupPriority = $groupHeading.AddFormattedText("   rule collection group · priority $($group.Group[0].RuleCollectionGroupPriority)")
            $groupPriority.Size = 9
            $groupPriority.Color = $colors.Muted

            foreach ($collection in @($group.Group | Group-Object -Property RuleCollection | Sort-Object { $_.Group[0].RuleCollectionPriority }, Name)) {
                $info = $collection.Group[0]
                $collectionHeading = $section.AddParagraph('', 'Heading3')
                $collectionHeading.AddText($collection.Name) | Out-Null
                $collectionMeta = $collectionHeading.AddFormattedText("   priority $($info.RuleCollectionPriority) · $($info.RuleCollectionType) · $($collection.Count) rule(s)   ")
                $collectionMeta.Size = 8.5
                $collectionMeta.Color = $colors.Muted
                $tone = $actionTone[[string]$info.Action]
                if (-not $tone) { $tone = $pdf.Tone.Neutral }
                $actionText = $collectionHeading.AddFormattedText(" $(([string]$info.Action).ToUpperInvariant()) ")
                $actionText.Size = 8
                $actionText.Bold = $true
                $actionText.Color = $tone.Text
                $actionText.Font.Name = 'Segoe UI'

                $table = & $pdf.NewTable @(4.6, 6.2, 7.2, 4.1, 4.0)
                & $pdf.AddHeaderRow $table @('Rule', 'Source', 'Destination', 'Protocols and ports', 'Translation / inspection')
                foreach ($item in $collection.Group) {
                    $row = & $pdf.AddBodyRow $table
                    # A coloured bar on the left edge carries the collection's action.
                    $row.Cells[0].Borders.Left.Width = 2.5
                    $row.Cells[0].Borders.Left.Color = $tone.Solid

                    $name = $row.Cells[0].AddParagraph($item.RuleName)
                    $name.Format.Font.Name = 'Segoe UI Semibold'
                    $kind = $row.Cells[0].AddParagraph(($item.RuleType -replace 'Rule$', '' -replace '^Nat$', 'DNAT') + ' rule')
                    $kind.Format.Font.Size = 7
                    $kind.Format.Font.Color = $colors.Muted
                    if ($item.Description) {
                        $description = $row.Cells[0].AddParagraph($item.Description)
                        $description.Format.Font.Size = 7.5
                        $description.Format.Font.Color = $colors.Muted
                    }

                    & $addLabelled $row.Cells[1] '' $item.SourceAddresses
                    & $addIpGroups $row.Cells[1] $item.SourceIpGroupAddresses

                    & $addLabelled $row.Cells[2] '' $item.DestinationAddresses
                    & $addIpGroups $row.Cells[2] $item.DestinationIpGroupAddresses
                    & $addLabelled $row.Cells[2] 'FQDNs' $item.DestinationFqdns
                    & $addLabelled $row.Cells[2] 'FQDNs' $item.TargetFqdns
                    & $addLabelled $row.Cells[2] 'URLs' $item.TargetUrls
                    & $addLabelled $row.Cells[2] 'FQDN tags' $item.FqdnTags
                    & $addLabelled $row.Cells[2] 'Web categories' $item.WebCategories

                    & $addLabelled $row.Cells[3] '' $item.Protocols
                    & $addLabelled $row.Cells[3] 'Ports' $item.DestinationPorts

                    if ($item.RuleType -eq 'NatRule') {
                        $target = if ($item.TranslatedFqdn) { $item.TranslatedFqdn } else { $item.TranslatedAddress }
                        & $addLabelled $row.Cells[4] 'To' "$target$(if ($item.TranslatedPort) { ":$($item.TranslatedPort)" })"
                    }
                    elseif ($item.RuleType -eq 'ApplicationRule') {
                        & $addLabelled $row.Cells[4] 'TLS inspection' $(if ($item.TerminateTls) { 'on' } else { 'off' })
                    }
                    foreach ($cell in $row.Cells) {
                        if ($cell.Elements.Count -eq 0) {
                            $cell.AddParagraph('-').Format.Font.Color = $colors.Muted
                        }
                    }
                }
            }
        }
    }

    Save-AACPdfDocument -Pdf $pdf -Path $Path
}
