function Write-AACNsgHtml {
    <#
    .SYNOPSIS
        Writes the network security group assessment (ConvertTo-AACNsgAssessment)
        as an interactive HTML report.
    .DESCRIPTION
        Tiles (NSGs, rules, findings by severity, unassociated NSGs, NSGs
        without flow logs or diagnostics - each filtering its table), charts
        (findings by severity and by check, NSGs by risk), and tables - each
        searchable, filterable, groupable and downloadable as CSV:
          NSGs          metadata, what each is applied to, rule counts, flow
                        logs, Traffic Analytics, diagnostics, risk, findings
          Rules         every rule, grouped by NSG, in evaluation order, with
                        its risk and finding
          Findings      severity, check, NSG, rule, what was found and what to do
          Associations  each NSG's subnets and network interfaces
          Logging       each NSG's flow logs and diagnostic settings
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
    $groups = @($Assessment.Groups)
    $severityTones = @{ High = 'bad'; Medium = 'warn'; Low = 'info'; Info = 'neutral' }
    $flowTones = @{ 'Enabled (VNet flow log)' = 'good'; 'Enabled (NSG flow log)' = 'warn'; Disabled = 'bad'; None = 'bad' }
    $diagTones = @{ Enabled = 'good'; Disabled = 'bad'; Unknown = 'neutral'; 'Not checked' = 'neutral' }

    $tiles = @(
        @{ Value = '{0:N0}' -f $stats.Groups; Label = 'network security groups'; Tone = 'info'; Table = 'nsgs' }
        @{ Value = '{0:N0}' -f $stats.Rules; Label = 'custom rules'; Tone = 'neutral'; Table = 'rules'; Filters = @{ Kind = 'Custom' } }
        @{ Value = '{0:N0}' -f $stats.High; Label = 'high-severity findings'; Tone = $(if ($stats.High) { 'bad' } else { 'good' }); Table = 'findings'; Filters = @{ Severity = 'High' } }
        @{ Value = '{0:N0}' -f $stats.Medium; Label = 'medium-severity findings'; Tone = $(if ($stats.Medium) { 'warn' } else { 'good' }); Table = 'findings'; Filters = @{ Severity = 'Medium' } }
        @{ Value = '{0:N0}' -f $stats.Low; Label = 'low-severity findings'; Tone = 'info'; Table = 'findings'; Filters = @{ Severity = 'Low' } }
        @{ Value = '{0:N0}' -f $stats.Unassociated; Label = 'unassociated NSGs'; Tone = $(if ($stats.Unassociated) { 'warn' } else { 'good' }); Table = 'nsgs'; Filters = @{ Associated = 'No' } }
        @{ Value = '{0:N0}' -f $stats.WithoutFlowLogs; Label = 'without flow logs'; Tone = $(if ($stats.WithoutFlowLogs) { 'warn' } else { 'good' }); Table = 'findings'; Filters = @{ Check = 'No flow logs' } }
        @{ Value = '{0:N0}' -f $stats.WithoutDiagnostics; Label = 'without diagnostic settings'; Tone = $(if ($stats.WithoutDiagnostics) { 'warn' } else { 'good' }); Table = 'nsgs'; Filters = @{ Diagnostics = 'Disabled' } }
    )
    $bySeverity = @(foreach ($level in 'High', 'Medium', 'Low', 'Info') {
            $n = @($Assessment.Findings | Where-Object Severity -EQ $level).Count
            if ($n) { @{ Label = $level; Value = $n; Tone = $severityTones[$level] -replace 'neutral', ''; Filter = $level } }
        })
    $byCheck = @($Assessment.Findings | Group-Object -Property Check | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, Name | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } })
    $byRisk = @($groups | Where-Object Risk | Sort-Object -Property @{ Expression = { $_.High * 1000 + $_.Medium * 10 + $_.Low }; Descending = $true } | Select-Object -First 12 | ForEach-Object {
            @{ Label = $_.Name; Value = $_.High + $_.Medium + $_.Low; Display = "H$($_.High) M$($_.Medium) L$($_.Low)"; Tone = $severityTones[$_.Risk] -replace 'neutral', ''; Filter = $_.Name }
        })
    $charts = @(
        @{ Title = 'Findings by severity'; Items = $bySeverity; Table = 'findings'; Column = 'Severity' }
        @{ Title = 'Findings by check'; Items = $byCheck; Table = 'findings'; Column = 'Check'; Tone = 'warn' }
        @{ Title = 'NSGs with the most findings'; Items = $byRisk; Table = 'findings'; Column = 'Nsg' }
        @{ Title = 'VMs protected per NSG (through their NIC or subnet)'; Items = @($groups | Where-Object { $_.VirtualMachines -gt 0 } | Sort-Object -Property @{ Expression = 'VirtualMachines'; Descending = $true }, Name | Select-Object -First 15 | ForEach-Object { @{ Label = $_.Name; Value = $_.VirtualMachines; Filter = $_.Name } }); Table = 'nsgs'; Column = 'Name'; Tone = 'info' }
    )

    $nsgRows = @($groups | Select-Object -Property *, @{ Name = 'AssociatedText'; Expression = { if ($_.Associated) { 'Yes' } else { 'No' } } }, @{ Name = 'Analytics'; Expression = { if ($_.TrafficAnalytics) { 'On' } elseif ($_.FlowLogs -like 'Enabled*') { 'Off' } else { '' } } })
    foreach ($row in $nsgRows) { $row | Add-Member -NotePropertyName 'Associated' -NotePropertyValue $row.AssociatedText -Force }
    $ruleRows = @($Assessment.Rules | Select-Object -Property *, @{ Name = 'Kind'; Expression = { if ($_.IsDefault) { 'Default' } else { 'Custom' } } })
    $associations = @(foreach ($nsg in $groups) {
            foreach ($subnet in $nsg.Subnets) { [pscustomobject]@{ Nsg = $nsg.Name; Kind = 'Subnet'; Name = $subnet.Name; Where = $subnet.VirtualNetwork; Address = $subnet.Prefix; ResourceGroup = $nsg.ResourceGroup; SubscriptionName = $nsg.SubscriptionName; Id = $subnet.Id } }
            foreach ($nic in $nsg.NetworkInterfaces) { [pscustomobject]@{ Nsg = $nsg.Name; Kind = 'Network interface'; Name = $nic.Name; Where = $nic.VirtualMachine; Address = $nic.PrivateIp; ResourceGroup = $nsg.ResourceGroup; SubscriptionName = $nsg.SubscriptionName; Id = $nic.Id } }
        })
    $logging = @(foreach ($nsg in $groups) {
            foreach ($log in $nsg.FlowLogDetail) {
                [pscustomobject]@{ Nsg = $nsg.Name; Kind = $log.Kind; Name = $log.Name; Status = $(if ($log.Enabled) { 'Enabled' } else { 'Disabled' }); Destination = $(if ($log.Storage) { "Storage: $($log.Storage)" }); Retention = $(if ($log.RetentionEnabled -and $log.RetentionDays) { "$($log.RetentionDays) days" } else { 'no limit' }); Analytics = $(if ($log.Analytics) { "On$(if ($log.Workspace) { " ($($log.Workspace), every $($log.Interval) min)" })" } else { 'Off' }); Id = $log.Id }
            }
            foreach ($setting in $nsg.DiagnosticSettings) {
                [pscustomobject]@{ Nsg = $nsg.Name; Kind = 'Diagnostic setting'; Name = $setting.Name; Status = $(if ($setting.Categories) { 'Enabled' } else { 'Disabled' }); Destination = (@($(if ($setting.Workspace) { "Log Analytics: $($setting.Workspace)" }), $(if ($setting.Storage) { "Storage: $($setting.Storage)" }), $(if ($setting.EventHub) { "Event Hub: $($setting.EventHub)" })) | Where-Object { $_ }) -join '; '; Retention = ''; Analytics = "Logs: $($setting.Categories)"; Id = '' }
            }
        })

    $tables = @(
        @{
            Id = 'nsgs'; Title = 'Network security groups'; Noun = 'NSGs'; File = 'nsgs'; Rows = $nsgRows; GroupBy = @('SubscriptionName', 'ResourceGroup', 'Location', 'Risk')
            Columns = @(
                @{ Key = 'Name'; Label = 'NSG'; Type = 'resource'; IdKey = 'Id' }
                @{ Key = 'Risk'; Label = 'Risk'; Type = 'badge'; Tones = $severityTones; Facet = $true }
                @{ Key = 'High'; Label = 'High'; Type = 'number'; Sum = $true; Format = 'N0'; Tone = 'bad' }
                @{ Key = 'Medium'; Label = 'Medium'; Type = 'number'; Sum = $true; Format = 'N0'; Tone = 'warn' }
                @{ Key = 'Low'; Label = 'Low'; Type = 'number'; Sum = $true; Format = 'N0' }
                @{ Key = 'VirtualMachines'; Label = 'VMs protected'; Type = 'number'; Sum = $true; Format = 'N0' }
                @{ Key = 'AppliedTo'; Label = 'Applied to'; Type = 'wide' }
                @{ Key = 'Associated'; Label = 'Associated'; Type = 'badge'; Tones = @{ Yes = 'good'; No = 'warn' }; Facet = $true }
                @{ Key = 'InboundRules'; Label = 'Inbound'; Type = 'number' }
                @{ Key = 'OutboundRules'; Label = 'Outbound'; Type = 'number' }
                @{ Key = 'FlowLogs'; Label = 'Flow logs'; Type = 'badge'; Tones = $flowTones; Facet = $true }
                @{ Key = 'FlowLogRetention'; Label = 'Retention' }
                @{ Key = 'Analytics'; Label = 'Traffic Analytics'; Type = 'badge'; Tones = @{ On = 'good'; Off = 'warn' }; Facet = $true }
                @{ Key = 'Diagnostics'; Label = 'Diagnostics'; Type = 'badge'; Tones = $diagTones; Facet = $true }
                @{ Key = 'LogDestinations'; Label = 'Log destinations'; Type = 'wide' }
                @{ Key = 'SubscriptionName'; Label = 'Subscription'; Facet = $true }
                @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                @{ Key = 'Location'; Label = 'Location'; Facet = $true }
                @{ Key = 'Tags'; Label = 'Tags'; Type = 'wide' }
                @{ Key = 'Id'; Label = 'Resource ID'; Hidden = $true }
            )
        }
        @{
            Id = 'findings'; Title = 'Findings'; Note = 'Most severe first. Hover a rule''s finding in the rules table for the same detail.'; Noun = 'findings'; File = 'nsg-findings'; Rows = @($Assessment.Findings)
            GroupBy = @('Nsg', 'Check', 'Severity')
            Columns = @(
                @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $severityTones; Facet = $true }
                @{ Key = 'Check'; Label = 'Check'; Facet = $true }
                @{ Key = 'Nsg'; Label = 'NSG'; Type = 'resource'; IdKey = 'NsgId'; Facet = $true }
                @{ Key = 'Rule'; Label = 'Rule' }
                @{ Key = 'Detail'; Label = 'What was found'; Type = 'wide' }
                @{ Key = 'Recommendation'; Label = 'What to do'; Type = 'wide' }
                @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                @{ Key = 'SubscriptionName'; Label = 'Subscription'; Facet = $true }
                @{ Key = 'NsgId'; Label = 'NSG ID'; Hidden = $true }
            )
        }
        @{
            Id = 'rules'; Title = 'Rules'; Note = 'Per NSG and direction, in the order Azure evaluates them: custom rules by priority, then the defaults.'; Noun = 'rules'; File = 'nsg-rules'; Rows = $ruleRows
            GroupBy = @('Nsg', 'Direction', 'Access', 'Risk'); Group = 'Nsg'
            Columns = @(
                @{ Key = 'Nsg'; Label = 'NSG'; Facet = $true }
                @{ Key = 'Direction'; Label = 'Direction'; Type = 'badge'; Tones = @{ Inbound = 'info'; Outbound = 'violet' }; Facet = $true }
                @{ Key = 'Priority'; Label = 'Priority'; Type = 'number' }
                @{ Key = 'Name'; Label = 'Rule' }
                @{ Key = 'Access'; Label = 'Access'; Type = 'badge'; Tones = @{ Allow = 'good'; Deny = 'bad' }; Facet = $true }
                @{ Key = 'Protocol'; Label = 'Protocol'; Facet = $true }
                @{ Key = 'Source'; Label = 'Source'; Type = 'wide' }
                @{ Key = 'SourcePorts'; Label = 'Source ports' }
                @{ Key = 'Destination'; Label = 'Destination'; Type = 'wide' }
                @{ Key = 'DestinationPorts'; Label = 'Destination ports' }
                @{ Key = 'Risk'; Label = 'Risk'; Type = 'badge'; Tones = $severityTones; Facet = $true }
                @{ Key = 'Finding'; Label = 'Finding'; Type = 'wide' }
                @{ Key = 'Kind'; Label = 'Custom or default'; Type = 'badge'; Tones = @{ Custom = 'info'; Default = 'neutral' }; Facet = $true }
                @{ Key = 'Description'; Label = 'Description'; Type = 'wide' }
                @{ Key = 'ResourceGroup'; Label = 'Resource group'; Hidden = $true }
                @{ Key = 'SubscriptionName'; Label = 'Subscription'; Hidden = $true }
            )
        }
        @{
            Id = 'associations'; Title = 'Associations'; Note = 'The subnets and network interfaces each NSG is applied to.'; Noun = 'associations'; File = 'nsg-associations'; Rows = $associations; GroupBy = @('Nsg', 'Kind')
            Columns = @(
                @{ Key = 'Nsg'; Label = 'NSG'; Facet = $true }
                @{ Key = 'Kind'; Label = 'Kind'; Type = 'badge'; Tones = @{ Subnet = 'info'; 'Network interface' = 'violet' }; Facet = $true }
                @{ Key = 'Name'; Label = 'Subnet or NIC'; Type = 'resource'; IdKey = 'Id' }
                @{ Key = 'Where'; Label = 'Virtual network or VM' }
                @{ Key = 'Address'; Label = 'Prefix or IP' }
                @{ Key = 'ResourceGroup'; Label = 'NSG resource group'; Facet = $true }
                @{ Key = 'SubscriptionName'; Label = 'Subscription'; Facet = $true }
            )
        }
        @{
            Id = 'logging'; Title = 'Logging'; Note = 'Flow logs (an NSG flow log, or a virtual network flow log on the NSG''s VNet, subnet or NIC) and diagnostic settings.'; Noun = 'log settings'; File = 'nsg-logging'; Rows = $logging; GroupBy = @('Nsg', 'Kind')
            Columns = @(
                @{ Key = 'Nsg'; Label = 'NSG'; Facet = $true }
                @{ Key = 'Kind'; Label = 'Kind'; Type = 'badge'; Tones = @{ 'Virtual network flow log' = 'good'; 'NSG flow log' = 'warn'; 'Diagnostic setting' = 'info' }; Facet = $true }
                @{ Key = 'Name'; Label = 'Name' }
                @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = @{ Enabled = 'good'; Disabled = 'bad' }; Facet = $true }
                @{ Key = 'Destination'; Label = 'Destination'; Type = 'wide' }
                @{ Key = 'Retention'; Label = 'Retention' }
                @{ Key = 'Analytics'; Label = 'Traffic Analytics / logs'; Type = 'wide' }
            )
        }
    )
    $notices = @()
    if (@($groups | Where-Object Diagnostics -EQ 'Not checked').Count) { $notices += @{ Tone = 'info'; Text = 'Diagnostic settings were not read (-NoDiagnosticSetting).' } }
    Write-AACHtmlReport -Path $Path -Title $Title -Subtitle 'Network security groups: associations, rules, logging and risks' -Fact $Detail -Tile $tiles -Chart $charts -Table $tables -Notice $notices
}
