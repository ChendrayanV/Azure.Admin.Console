function Show-AACNsgView {
    <#
    .SYNOPSIS
        Renders the network security group assessment (ConvertTo-AACNsgAssessment)
        as a Spectre.Console view.
    .DESCRIPTION
        The scope; tiles (NSGs, custom rules, High and Medium findings,
        unassociated NSGs, NSGs without flow logs or diagnostics); a table of
        the NSGs - applied to, rules, flow logs, diagnostics, risk and
        findings by severity; the High and Medium findings with what to do;
        and, for up to -Detail NSGs, each one in detail: its associations,
        telemetry and its inbound and outbound rules in evaluation order,
        Allow in green, Deny in red, risky rules flagged. Severities: High
        red, Medium amber, Low blue, Info grey. Output goes straight to the
        Spectre console; wrap the call in Invoke-AACPagedOutput to page it.
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
    $groups = @($Assessment.Groups)
    $severityColor = @{ High = 'red1'; Medium = 'orange1'; Low = 'deepskyblue1'; Info = 'grey62' }
    $flowColor = { param([string] $Status) if ($Status -like 'Enabled*') { 'green3' } elseif ($Status -eq 'Disabled' -or $Status -eq 'None') { 'orange1' } else { 'grey62' } }
    $counts = {
        param($Item)
        $parts = foreach ($level in 'High', 'Medium', 'Low', 'Info') {
            $n = [int]$Item.$level
            if ($n) { "[$($severityColor[$level])]$($level.Substring(0, 1))$n[/]" }
        }
        if ($parts) { $parts -join ' ' } else { "[green3]$($glyph.Tick)[/]" }
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
    [Spectre.Console.AnsiConsole]::WriteLine()

    if (-not $groups.Count) {
        Show-AACCallout Info -Message '[bold]No network security groups[/] [grey58]were found in this scope.[/]'
        return
    }
    Show-AACTileRow -Tile @(
        @{ Value = '{0:N0}' -f $stats.Groups; Caption = 'NSGs'; Color = 'deepskyblue1' }
        @{ Value = '{0:N0}' -f $stats.Rules; Caption = 'custom rules'; Color = 'grey70' }
        @{ Value = '{0:N0}' -f $stats.High; Caption = 'high findings'; Color = $(if ($stats.High) { 'red1' } else { 'green3' }) }
        @{ Value = '{0:N0}' -f $stats.Medium; Caption = 'medium findings'; Color = $(if ($stats.Medium) { 'orange1' } else { 'green3' }) }
        @{ Value = '{0:N0}' -f $stats.Unassociated; Caption = 'unassociated'; Color = $(if ($stats.Unassociated) { 'orange1' } else { 'green3' }) }
        @{ Value = '{0:N0}' -f $stats.WithoutFlowLogs; Caption = 'without flow logs'; Color = $(if ($stats.WithoutFlowLogs) { 'orange1' } else { 'green3' }) }
    )
    [Spectre.Console.AnsiConsole]::WriteLine()

    # --- The NSGs ---------------------------------------------------------------------------------------
    $table = & $newTable "[bold]$($glyph.Bullet) Network security groups[/] [grey58]$($glyph.Dot) most at risk first[/]" 'deepskyblue3_1' @('NSG', 'Applied to', 'In', 'Out', 'Flow logs', 'Diagnostics', 'Findings') @('In', 'Out')
    foreach ($nsg in $groups) {
        & $addRow $table @(
            "[bold]$(& $escape $nsg.Name)[/]`n[grey50]$(& $escape $nsg.ResourceGroup) $($glyph.Dot) $(& $escape $nsg.SubscriptionName)[/]"
            $(if ($nsg.Associated) { "[grey85]$(& $escape ($nsg.AppliedTo -replace '; ', "`n"))[/]" } else { '[orange1]nothing[/]' })
            "$($nsg.InboundRules)"
            "$($nsg.OutboundRules)"
            "[$(& $flowColor $nsg.FlowLogs)]$(& $escape $nsg.FlowLogs)[/]$(if ($nsg.FlowLogRetention) { "`n[grey50]$(& $escape $nsg.FlowLogRetention)$(if ($nsg.TrafficAnalytics) { ', Traffic Analytics' })[/]" })"
            "[$(if ($nsg.Diagnostics -eq 'Enabled') { 'green3' } elseif ($nsg.Diagnostics -eq 'Disabled') { 'orange1' } else { 'grey62' })]$(& $escape $nsg.Diagnostics)[/]"
            (& $counts $nsg)
        )
    }
    [Spectre.Console.AnsiConsole]::Write($table)
    [Spectre.Console.AnsiConsole]::WriteLine()

    # --- VMs per NSG: how standard the perimeter is -----------------------------------------------------------
    $perNsg = @($Assessment.Groups | Where-Object { $_.VirtualMachines -gt 0 } | Sort-Object -Property @{ Expression = 'VirtualMachines'; Descending = $true }, Name | Select-Object -First 15 | ForEach-Object { @{ Label = $_.Name; Value = $_.VirtualMachines } })
    if ($perNsg.Count) {
        Show-AACBarChart -Item $perNsg -Title 'VMs protected per NSG (through their NIC or subnet)'
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    # --- High and Medium findings ----------------------------------------------------------------------------
    $serious = @($Assessment.Findings | Where-Object { $_.Severity -in 'High', 'Medium' } | Sort-Object -Property @{ Expression = { if ($_.Severity -eq 'High') { 0 } else { 1 } } }, Nsg, Check)
    if ($serious.Count) {
        Write-AACMarkup "[bold]$($glyph.Bullet) Findings[/] [grey58]$($glyph.Dot) High and Medium, $($serious.Count) in all[/]"
        foreach ($finding in $serious) {
            $color = $severityColor[$finding.Severity]
            Write-AACMarkup "  [$color]$($finding.Severity.ToUpperInvariant().PadRight(6))[/] [white]$(& $escape $finding.Nsg)[/]$(if ($finding.Rule) { " [grey50]$(& $escape $finding.Rule)[/]" }) [grey62]$(& $escape $finding.Check)[/]"
            Write-AACMarkup "         [grey85]$(& $escape $finding.Detail)[/]"
            Write-AACMarkup "         [grey50]$($glyph.Arrow) $(& $escape $finding.Recommendation)[/]"
        }
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    # --- A few NSGs in detail ------------------------------------------------------------------------------
    if ($groups.Count -le $Detail) {
        foreach ($nsg in $groups) {
            Write-AACRule -Title "[bold]$(& $escape $nsg.Name)[/]" -Color 'grey50'
            Write-AACMarkup "[grey58]$(& $escape $nsg.Id)[/]"
            Write-AACMarkup "[grey58]Location[/] $(& $escape $nsg.Location)  [grey58]Subscription[/] $(& $escape $nsg.SubscriptionName)  [grey58]Resource group[/] $(& $escape $nsg.ResourceGroup)"
            foreach ($subnet in $nsg.Subnets) { Write-AACMarkup "  [deepskyblue1]Subnet[/] $(& $escape $subnet.VirtualNetwork)/$(& $escape $subnet.Name) [grey50]$(& $escape $subnet.Prefix)[/]" }
            foreach ($nic in $nsg.NetworkInterfaces) { Write-AACMarkup "  [deepskyblue1]NIC[/] $(& $escape $nic.Name) [grey50]$(& $escape (@($nic.VirtualMachine, $nic.PrivateIp) | Where-Object { $_ }) -join ' · ')[/]" }
            if (-not $nsg.Associated) { Write-AACMarkup '  [orange1]Applied to nothing.[/]' }
            Write-AACMarkup "  [grey58]Flow logs[/] [$(& $flowColor $nsg.FlowLogs)]$(& $escape $nsg.FlowLogs)[/]$(foreach ($log in $nsg.FlowLogDetail) { " [grey50]$(& $escape $log.Name) ($(& $escape $log.Kind)$(if ($log.Storage) { ", storage $(& $escape $log.Storage)" })$(if ($log.Analytics) { ', Traffic Analytics' }))[/]" })"
            Write-AACMarkup "  [grey58]Diagnostics[/] $(& $escape $nsg.Diagnostics)$(if ($nsg.LogDestinations) { " [grey50]$(& $escape $nsg.LogDestinations)[/]" })"
            [Spectre.Console.AnsiConsole]::WriteLine()
            foreach ($direction in 'Inbound', 'Outbound') {
                $rules = @($nsg.Rules | Where-Object Direction -EQ $direction)
                $table = & $newTable "[bold]$direction rules[/] [grey58]$($glyph.Dot) in the order Azure evaluates them[/]" 'grey42' @('Priority', 'Name', 'Access', 'Protocol', 'Source', 'Ports', 'Destination', 'Risk') @('Priority')
                foreach ($rule in $rules) {
                    $dim = if ($rule.IsDefault) { 'grey50' } else { 'grey85' }
                    & $addRow $table @(
                        "[$dim]$($rule.Priority)[/]"
                        "[$(if ($rule.IsDefault) { 'grey50' } else { 'white' })]$(& $escape $rule.Name)[/]"
                        "[$(if ($rule.Access -eq 'Allow') { 'green3' } else { 'red1' })]$(& $escape $rule.Access)[/]"
                        "[$dim]$(& $escape $rule.Protocol)[/]"
                        "[$dim]$(& $escape $rule.Source)[/]"
                        "[$dim]$(& $escape $rule.DestinationPorts)[/]"
                        "[$dim]$(& $escape $rule.Destination)[/]"
                        $(if ($rule.Risk) { "[$($severityColor[$rule.Risk])]$(& $escape $rule.Risk)[/]" } else { '' })
                    )
                }
                [Spectre.Console.AnsiConsole]::Write($table)
            }
            [Spectre.Console.AnsiConsole]::WriteLine()
        }
    }
    else {
        Write-AACMarkup "[grey42]-Name shows an NSG in detail with its rules; -HtmlPath or -PdfPath has every NSG and rule.[/]"
    }
    Write-AACMarkup "[grey42]Add -PassThru (or pipe the command) for the objects; -CsvPath writes every rule.[/]"
}
