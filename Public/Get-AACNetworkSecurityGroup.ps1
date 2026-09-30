function Get-AACNetworkSecurityGroup {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        A detailed assessment of network security groups: what each is
        applied to, every rule, its flow logs and diagnostic settings, and the
        risks in them - with a Spectre.Console view, objects, and CSV, PDF and
        interactive HTML reports.
    .DESCRIPTION
        Reads the NSGs, the network interfaces and subnets they are applied
        to and the Network Watcher flow logs with Azure Resource Graph, and
        each NSG's diagnostic settings through Azure Resource Manager - with
        the Connect-AAC sign-in; Reader access is enough, no Az modules.
        Without parameters it assesses every NSG the account can see.

        For each NSG:
          Metadata      name, resource ID, subscription, resource group,
                        location, tags
          Associations  the subnets (VNet, prefix) and network interfaces
                        (VM, private IP) it is applied to
          Rules         every rule, custom and default, in the order Azure
                        evaluates them: priority, direction, protocol,
                        source, source port, destination, destination port
                        (application security groups by name), action
          Telemetry     diagnostic settings (enabled or not; Log Analytics
                        workspace, storage account, event hub; log
                        categories), flow logs (an NSG flow log, or a virtual
                        network flow log on its VNet, subnet or NIC; enabled,
                        retention, storage) and Traffic Analytics

        Findings, each with a severity, the rule it is about and what to do:
          High    an inbound Allow from *, Internet or 0.0.0.0/0 to every
                  port or to a management or database port (SSH, RDP, WinRM,
                  SMB, Telnet, FTP, SQL, MySQL, PostgreSQL, Oracle, MongoDB,
                  Redis, VNC, Docker, ...)
          Medium  a wide port range (over 100 ports) open to the internet; an
                  NSG on no subnet and no NIC; a NIC NSG and its subnet's NSG
                  that disagree - one allows what the other denies, so the
                  traffic is blocked (both are evaluated, first matching rule
                  by priority, as Azure does); applied to something with no
                  flow log, or a disabled one
          Low     ICMP from the internet; everything allowed from the whole
                  virtual network; a shadowed rule - one an earlier rule
                  fully covers, so it never applies; flow logs kept under 90
                  days; no diagnostic settings
          Info    flow logs without Traffic Analytics; only an NSG flow log
                  (they retire on 30 September 2027: migrate to virtual
                  network flow logs); over 800 of the 1,000 rules an NSG can
                  hold

        What you get depends on where the command runs:
          at the prompt    tiles, a table of the NSGs with their risk, the
                           High and Medium findings, and - for up to three
                           NSGs - each one in detail with its rules, a page
                           at a time
          piped onward     the AAC.NetworkSecurityGroup objects, with no view
          -PassThru        the view and the objects
          -NoDisplay       the objects only
        -CsvPath writes every rule (with its NSG, risk and finding) to CSV.
        -HtmlPath writes an interactive report - tiles, charts, and tables of
        the NSGs, rules, findings, associations and logging, each with its
        own CSV download. -PdfPath writes a PDF: the summary, the findings,
        and a section per NSG with its associations, telemetry and rules.
        With any of them, the console shows only the progress and the files
        written.
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ResourceGroupName
        Only NSGs in these resource groups.
    .PARAMETER Name
        Only these NSGs; wildcards work, e.g. 'nsg-web-*'.
    .PARAMETER NoDiagnosticSetting
        Don't read the NSGs' diagnostic settings (one Azure Resource Manager
        call per NSG); their status is then "Not checked".
    .PARAMETER CsvPath
        Write every rule, with its NSG, risk and finding, to this CSV file.
    .PARAMETER PdfPath
        Write a PDF report to this file.
    .PARAMETER HtmlPath
        Write an interactive HTML report to this file.
    .PARAMETER Title
        The PDF and HTML reports' title.
    .PARAMETER PassThru
        Show the view and also return the objects.
    .PARAMETER NoDisplay
        Return the objects without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once instead of a page at a time.
    .EXAMPLE
        Connect-AAC
        Get-AACNetworkSecurityGroup
        Every NSG the account can see, assessed.
    .EXAMPLE
        Get-AACNetworkSecurityGroup -SubscriptionId '00000000-0000-0000-0000-000000000000' -ResourceGroupName 'rg-network' -Name 'nsg-web', 'nsg-app'
        Two NSGs in detail, with their rules.
    .EXAMPLE
        Get-AACNetworkSecurityGroup -HtmlPath .\out\NSG.html -PdfPath .\out\NSG.pdf -CsvPath .\out\NSG-rules.csv
        The full assessment as an interactive HTML report, a PDF and a CSV of every rule.
    .EXAMPLE
        (Get-AACNetworkSecurityGroup -NoDisplay).Findings | Where-Object Severity -EQ 'High'
        The High-severity findings.
    .OUTPUTS
        AAC.NetworkSecurityGroup (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.NetworkSecurityGroup')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [ValidateNotNullOrEmpty()]
        [string[]] $ResourceGroupName,

        [SupportsWildcards()]
        [ValidateNotNullOrEmpty()]
        [string[]] $Name,

        [switch] $NoDiagnosticSetting,

        [string] $CsvPath,

        [string] $PdfPath,

        [string] $HtmlPath,

        [string] $Title = 'Network security group assessment',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    # A failure anywhere below ends as a Spectre.Console error panel and this
    # command's own terminating error, not a line inside the module. A stopped
    # pipeline (Select-Object -First, Ctrl+C) is no failure: just return - a
    # rethrow would stop the caller's whole script, not only this command.
    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $showView = $interactive -and -not ($CsvPath -or $PdfPath -or $HtmlPath)
    $returnObjects = $PassThru -or $NoDisplay -or $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $csvFullPath = & $resolve $CsvPath
    $pdfFullPath = & $resolve $PdfPath
    $htmlFullPath = & $resolve $HtmlPath
    $quote = { param([string] $Text) "'" + ($Text -replace '\\', '\\' -replace "'", "\'") + "'" }
    $groupFilter = if ($ResourceGroupName) { " | where resourceGroup in~ ($((@($ResourceGroupName | ForEach-Object { & $quote $_ })) -join ', '))" } else { '' }
    $last = { param([string] $Id) if ($Id) { ($Id -split '/')[-1] } else { '' } }
    # A nested value from Resource Graph hashtables, or $null where a level is missing.
    $at = {
        param($Value, [string[]] $Keys)
        foreach ($key in $Keys) { if ($Value -is [System.Collections.IDictionary]) { $Value = $Value[$key] } else { return $null } }
        $Value
    }

    if ($interactive) {
        Write-AACRule -Title 'Azure Admin Console :: Network security groups' -Color 'deepskyblue3_1'
    }
    $state = Invoke-AACProgress -ScriptBlock {
        $null = Get-AACAccessToken
        # The five queries at once (Invoke-AACGraphBatch).
        Update-AACProgress -Id 'read' -Total 5 -Description 'Reading the NSGs, network interfaces, subnets and flow logs'
        $batch = Invoke-AACGraphBatch -SubscriptionId $SubscriptionId -Query ([ordered]@{
                subscriptions = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions' | project subscriptionId, name"
                groups        = "resources | where type =~ 'microsoft.network/networksecuritygroups'$groupFilter | project id, name, resourceGroup, subscriptionId, location, tags, properties"
                nics          = "resources | where type =~ 'microsoft.network/networkinterfaces' | project id, name, resourceGroup, nsg = tolower(tostring(properties.networkSecurityGroup.id)), vm = tolower(tostring(properties.virtualMachine.id)), ipConfigurations = properties.ipConfigurations"
                subnets       = "resources | where type =~ 'microsoft.network/virtualnetworks' | mv-expand subnet = properties.subnets | project subnetId = tolower(tostring(subnet.id)), name = tostring(subnet.name), vnetId = tolower(id), vnetName = name, prefix = tostring(coalesce(subnet.properties.addressPrefix, subnet.properties.addressPrefixes[0])), nsg = tolower(tostring(subnet.properties.networkSecurityGroup.id))"
                flowLogs      = "resources | where type =~ 'microsoft.network/networkwatchers/flowlogs' | extend analytics = properties.flowAnalyticsConfiguration.networkWatcherFlowAnalyticsConfiguration | project id, name, target = tolower(tostring(properties.targetResourceId)), enabled = tobool(properties.enabled), retentionEnabled = tobool(properties.retentionPolicy.enabled), retentionDays = toint(properties.retentionPolicy.days), storageId = tostring(properties.storageId), analytics = tobool(analytics.enabled), workspace = tostring(analytics.workspaceResourceId), interval = toint(analytics.trafficAnalyticsInterval), version = toint(properties.format.version)"
            }) -OnProgress { param($Name, $Done, $Total) Update-AACProgress -Id 'read' -Increment 1 -Description "Read the $Name ($Done of $Total queries)" }
        $subscriptionNames = @{}
        foreach ($row in @($batch.Rows['subscriptions'])) {
            $subscriptionNames[([string]$row['subscriptionId']).ToLowerInvariant()] = [string]$row['name']
        }
        $groups = @($batch.Rows['groups'])
        if ($Name) {
            $groups = @($groups | Where-Object { $nsgName = [string]$_['name']; @($Name | Where-Object { $nsgName -like $_ }).Count })
            $missing = @($Name | Where-Object { $pattern = $_; -not @($groups | Where-Object { [string]$_['name'] -like $pattern }).Count })
            if ($missing.Count -eq $Name.Count) { throw "No network security group named $(($missing | ForEach-Object { "'$_'" }) -join ', ') was found$(if ($SubscriptionId -or $ResourceGroupName) { ' in that scope' } else { ' in any subscription you can see' })." }
            foreach ($item in $missing) { Write-Warning "No network security group named '$item' was found; it's left out." }
        }

        $nics = @(foreach ($row in @($batch.Rows['nics'])) {
                $configurations = @($row['ipConfigurations'] | Where-Object { $_ })
                @{
                    id = [string]$row['id']; name = [string]$row['name']; resourceGroup = [string]$row['resourceGroup']; nsg = [string]$row['nsg']; vm = [string]$row['vm']
                    subnet = $(if ($configurations) { [string](& $at $configurations[0] 'properties', 'subnet', 'id') } else { '' })
                    ips = @($configurations | ForEach-Object { [string](& $at $_ 'properties', 'privateIPAddress') } | Where-Object { $_ })
                    asgs = @($configurations | ForEach-Object { @(& $at $_ 'properties', 'applicationSecurityGroups') } | Where-Object { $_ } | ForEach-Object { [string](& $at $_ 'id') })
                }
            })

        $subnets = @($batch.Rows['subnets'])
        $flowLogs = @($batch.Rows['flowLogs'])
        Update-AACProgress -Id 'read' -Complete -Description ('Read {0:N0} NSG(s), {1:N0} network interface(s), {2:N0} subnet(s) and {3:N0} flow log(s)' -f $groups.Count, $nics.Count, $subnets.Count, $flowLogs.Count)

        # Diagnostic settings aren't in Resource Graph: one ARM call per NSG,
        # up to 12 at once.
        $diagnostics = $null
        if (-not $NoDiagnosticSetting -and $groups.Count) {
            $diagnostics = @{}
            Update-AACProgress -Id 'diag' -Total $groups.Count -Description 'Reading the diagnostic settings'
            $uris = @{}
            foreach ($group in $groups) { $uris[([string]$group['id']).ToLowerInvariant()] = "$($group['id'])/providers/Microsoft.Insights/diagnosticSettings?api-version=2021-05-01-preview" }
            $read = Invoke-AACArmParallel -Uri @($uris.Values) -OnProgress { param($Done, $Total) Update-AACProgress -Id 'diag' -Total $Total -Increment 1 }
            foreach ($group in $groups) {
                $key = ([string]$group['id']).ToLowerInvariant()
                $result = $read[$uris[$key]]
                if (-not $result -or $result.Error -or $null -eq $result.Items) {
                    Write-Debug "The diagnostic settings of $($group['name']) couldn't be read: $(if ($result) { $result.Error })"
                    $diagnostics[$key] = @{ Status = 'Unknown'; Settings = @() }
                    continue
                }
                $settings = @(foreach ($setting in @($result.Items | Where-Object { $_ })) {
                        $p = $setting['properties']
                        if ($p -isnot [System.Collections.IDictionary]) { $p = @{} }
                        $logs = @(@($p['logs']) | Where-Object { $_ -and [string]$_['enabled'] -eq 'True' } | ForEach-Object { if ($_['categoryGroup']) { [string]$_['categoryGroup'] } else { [string]$_['category'] } })
                        [pscustomobject]@{
                            Name = [string]$setting['name']; Workspace = & $last ([string]$p['workspaceId']); Storage = & $last ([string]$p['storageAccountId'])
                            EventHub = $(if ($p['eventHubName']) { [string]$p['eventHubName'] } elseif ($p['eventHubAuthorizationRuleId']) { (([string]$p['eventHubAuthorizationRuleId']) -split '/')[-3] } else { '' })
                            Categories = $logs -join ', '
                        }
                    })
                $diagnostics[$key] = @{ Status = $(if (@($settings | Where-Object Categories).Count) { 'Enabled' } else { 'Disabled' }); Settings = $settings }
            }
            Update-AACProgress -Id 'diag' -Complete -Description ('Read the diagnostic settings of {0:N0} NSG(s)' -f $groups.Count)
        }

        Update-AACProgress -Id 'assess' -Description 'Assessing the rules, associations and logging' -Indeterminate
        $assessment = ConvertTo-AACNsgAssessment -NetworkSecurityGroup $groups -NetworkInterface $nics -Subnet $subnets -FlowLog $flowLogs -Diagnostic $diagnostics -SubscriptionName $subscriptionNames
        $stats = $assessment.Stats
        Update-AACProgress -Id 'assess' -Complete -Description ('Assessed {0:N0} NSG(s) and {1:N0} custom rule(s): {2} high, {3} medium, {4} low finding(s)' -f $stats.Groups, $stats.Rules, $stats.High, $stats.Medium, $stats.Low)

        $scope = [ordered]@{
            Scope = if ($SubscriptionId) { "subscription(s) $($SubscriptionId -join ', ')" } else { 'every subscription the account can see' }
        }
        if ($ResourceGroupName) { $scope['Resource groups'] = $ResourceGroupName -join ', ' }
        if ($Name) { $scope['NSGs'] = $Name -join ', ' }
        $csvRows = @($assessment.Rules | Select-Object -Property Nsg, Priority, Direction, Name, Access, Protocol, Source, SourcePorts, Destination, DestinationPorts, IsDefault, Risk, Finding, Description, ResourceGroup, SubscriptionName, NsgId)
        $null = Invoke-AACExport -CsvPath $csvFullPath -CsvObject $csvRows -Noun 'rule' -PdfPath $pdfFullPath -WritePdf {
            Write-AACNsgPdf -Assessment $assessment -Path $pdfFullPath -Title $Title -Detail $scope
        } -HtmlPath $htmlFullPath -WriteHtml {
            Write-AACNsgHtml -Assessment $assessment -Path $htmlFullPath -Title $Title -Detail $scope
        }
        @{ Assessment = $assessment; Scope = $scope }
    }

    if ($showView) {
        Invoke-AACPagedOutput -NoPaging:$NoPaging -ScriptBlock {
            Show-AACNsgView -Assessment $state.Assessment -Scope $state.Scope
        }
    }
    if ($returnObjects) {
        $state.Assessment.Groups
    }
}
