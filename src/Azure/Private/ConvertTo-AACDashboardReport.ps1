function ConvertTo-AACDashboardReport {
    <#
    .SYNOPSIS
        Show-AACDashboard's AAC.Dashboard as the report model the HTML and
        PDF reports are written from (Invoke-AACReportOutput): score tiles
        and charts on the Overview, then a tab per section - What to do next,
        Health, Security, Policy, Governance, Advisor, Estate, Changes and
        (with -IncludeCost) Cost.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [object] $Dashboard,

        [string[]] $Section = @('Health', 'Security', 'Policy', 'Governance', 'Advisor', 'Estate', 'Changes', 'Cost'),

        [System.Collections.IDictionary] $Scope = @{}
    )

    $d = $Dashboard
    $rank = Get-AACSeverityRank
    $pct = { param($Value) if ($null -eq $Value) { '-' } else { "$Value%" } }
    $money = { param($Value, [string] $Currency) if ($null -eq $Value) { '-' } else { '{0:N0} {1}' -f $Value, $Currency } }
    $toneOf = { param($Value, [double] $Good = 80, [double] $Warn = 60) if ($null -eq $Value) { 'neutral' } elseif ($Value -ge $Good) { 'good' } elseif ($Value -ge $Warn) { 'warn' } else { 'bad' } }
    $want = { param([string] $Name) $Section -contains $Name }

    $tiles = [System.Collections.Generic.List[object]]::new()
    $tiles.Add(@{ Value = $(if ($null -ne $d.Score.Value) { "$($d.Score.Value)" } else { '-' }); Label = 'Estate score (of 100)'; Tone = (& $toneOf $d.Score.Value) })
    $tiles.Add(@{ Value = (& $pct $d.Score.Health); Label = 'resources available'; Tone = (& $toneOf $d.Score.Health 99 95) })
    if (& $want 'Security') { $tiles.Add(@{ Value = (& $pct $d.Security.SecureScore); Label = 'secure score'; Tone = (& $toneOf $d.Security.SecureScore) }) }
    if (& $want 'Policy') { $tiles.Add(@{ Value = (& $pct $d.Policy.Compliance); Label = 'policy compliance'; Tone = (& $toneOf $d.Policy.Compliance) }) }
    if (& $want 'Advisor') { $tiles.Add(@{ Value = $(if ($null -ne $d.AdvisorScore) { "$($d.AdvisorScore)" } else { '-' }); Label = 'Advisor score'; Tone = (& $toneOf $d.AdvisorScore) }) }
    if (& $want 'Governance') { $tiles.Add(@{ Value = $(if ($d.Governance.ClosestLimit) { "$($d.Governance.ClosestLimit.Percent)%" } else { '-' }); Label = 'closest limit'; Tone = $(if (-not $d.Governance.ClosestLimit) { 'neutral' } elseif ($d.Governance.ClosestLimit.Percent -ge 95) { 'bad' } elseif ($d.Governance.ClosestLimit.Percent -ge 80) { 'warn' } else { 'good' }) }) }
    if ((& $want 'Cost') -and $d.Cost) { $tiles.Add(@{ Value = (& $money $d.Cost.MonthToDate $d.Cost.Currency); Label = $(if ($null -ne $d.Cost.ChangePercent) { "month to date ($('{0:+0.#;-0.#;0}' -f $d.Cost.ChangePercent)% vs last month)" } else { 'month to date' }); Tone = $(if ($null -ne $d.Cost.ChangePercent -and $d.Cost.ChangePercent -gt 10) { 'warn' } else { 'info' }) }) }
    $tiles.Add(@{ Value = '{0:N0}' -f ($d.Changes.Created + $d.Changes.Updated + $d.Changes.Deleted); Label = "changes in $($d.Hours)h"; Tone = 'violet' })

    $tabs = [System.Collections.Generic.List[object]]::new()
    $tables = [System.Collections.Generic.List[object]]::new()
    $tab = { param([string] $Name, $Badge, [string] $Tone, [string] $Note) $tabs.Add(@{ Name = $Name; Badge = $Badge; Tone = $Tone; Note = $Note }) }
    $sevCol = @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }

    $actions = @($d.Actions)
    & $tab 'What to do next' $actions.Count $(if (@($actions | Where-Object Severity -EQ 'High').Count) { 'bad' } elseif ($actions.Count) { 'warn' } else { 'good' }) 'Ranked across every section - and the command that goes deeper.'
    $tables.Add(@{ Id = 'actions'; Title = 'What to do next'; Section = 'What to do next'; Rows = $actions; Noun = 'actions'; Columns = @($sevCol, @{ Key = 'Area'; Label = 'Area'; Facet = $true; Pdf = $true }, @{ Key = 'Action'; Label = 'What'; Type = 'wide'; Pdf = $true }, @{ Key = 'Command'; Label = 'Go deeper'; Type = 'mono'; Pdf = $true }) })

    if (& $want 'Health') {
        & $tab 'Health' (@($d.UnhealthyResources).Count + @($d.ServiceEvents).Count) $(if ($d.Health.Unavailable) { 'bad' } elseif ($d.Health.Degraded -or @($d.ServiceEvents).Count) { 'warn' } else { 'good' }) "Resource Health: $($d.Health.Available) available, $($d.Health.Unavailable) unavailable, $($d.Health.Degraded) degraded, $($d.Health.Unknown) unknown - and the active Azure Service Health events."
        $tables.Add(@{ Id = 'unhealthy'; Title = 'Unhealthy resources'; Section = 'Health'; Rows = @($d.UnhealthyResources); Noun = 'resources'; Columns = @(@{ Key = 'Resource'; Label = 'Resource'; Pdf = $true }, @{ Key = 'State'; Label = 'State'; Type = 'badge'; Tones = @{ Unavailable = 'bad'; Degraded = 'warn' }; Facet = $true; Pdf = $true }, @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true; Pdf = $true }, @{ Key = 'Summary'; Label = 'Why'; Type = 'wide'; Pdf = $true }, @{ Key = 'Since'; Label = 'Since'; Type = 'datetime' }) })
        $tables.Add(@{ Id = 'events'; Title = 'Azure Service Health - active events'; Section = 'Health'; Rows = @($d.ServiceEvents); Noun = 'events'; Columns = @(@{ Key = 'Type'; Label = 'Type'; Type = 'badge'; Tones = @{ 'Service issue' = 'bad'; 'Security advisory' = 'warn'; 'Planned maintenance' = 'info'; 'Health advisory' = 'info' }; Facet = $true; Pdf = $true }, @{ Key = 'Title'; Label = 'Title'; Type = 'wide'; Pdf = $true }, @{ Key = 'TrackingId'; Label = 'Tracking ID'; Type = 'mono'; Pdf = $true }, @{ Key = 'Started'; Label = 'Since'; Type = 'datetime' }, @{ Key = 'Subscription'; Label = 'Subscriptions' }) })
    }
    if (& $want 'Security') {
        $sec = @(foreach ($kind in 'Alerts', 'Recommendations') { foreach ($sev in 'High', 'Medium', 'Low') { [pscustomobject]@{ Severity = $sev; Kind = $(if ($kind -eq 'Alerts') { 'Active security alerts' } else { 'Unresolved recommendations' }); Count = [int]$d.Security.$kind.$sev } } })
        & $tab 'Security' ($d.Security.Alerts.High + $d.Security.Alerts.Medium + $d.Security.Alerts.Low) $(if ($d.Security.Alerts.High) { 'bad' } else { & $toneOf $d.Security.SecureScore }) "Secure score $(& $pct $d.Security.SecureScore); Defender plans on $(if ($d.Security.DefenderPlans) { $d.Security.DefenderPlans } else { '-' }). Get-AACSecurityAlert and Invoke-AACDefenderAssessment go deeper."
        $tables.Add(@{ Id = 'security'; Title = 'Security alerts and recommendations'; Section = 'Security'; Rows = $sec; Noun = 'rows'; Columns = @($sevCol, @{ Key = 'Kind'; Label = 'What'; Facet = $true; Pdf = $true }, @{ Key = 'Count'; Label = 'Count'; Type = 'number'; Pdf = $true }) })
    }
    if (& $want 'Policy') {
        & $tab 'Policy' $d.Policy.NonCompliant (& $toneOf $d.Policy.Compliance) "Compliance $(& $pct $d.Policy.Compliance): $($d.Policy.Compliant) compliant and $($d.Policy.NonCompliant) non-compliant resources, each counted once. Invoke-AACPolicyAssessment goes deeper."
        $tables.Add(@{ Id = 'policyTop'; Title = 'Assignments with the most non-compliant resources'; Section = 'Policy'; Rows = @($d.Policy.Top); Noun = 'assignments'; Columns = @(@{ Key = 'Assignment'; Label = 'Assignment'; Pdf = $true }, @{ Key = 'Scope'; Label = 'Scope'; Pdf = $true }, @{ Key = 'Resources'; Label = 'Non-compliant resources'; Type = 'number'; Pdf = $true }) })
    }
    if (& $want 'Governance') {
        $g = $d.Governance
        $rows = @(
            $(if ($g.ClosestLimit) { [pscustomobject]@{ Item = "Closest limit: $($g.ClosestLimit.Limit) on $($g.ClosestLimit.Scope)"; Value = "$($g.ClosestLimit.Used) of $($g.ClosestLimit.Maximum) ($($g.ClosestLimit.Percent)%)"; Command = 'Test-AACAzureLimit' } })
            [pscustomobject]@{ Item = 'Privileged role assignments at subscription or above'; Value = "$($g.PrivilegedAssignments) ($((@($g.PrivilegedByType.PSObject.Properties | ForEach-Object { "$($_.Value) $($_.Name)" })) -join ', '))"; Command = 'Get-AACRoleAssignment -Privileged' }
            [pscustomobject]@{ Item = 'Unused disks, public IPs and network interfaces'; Value = "$($g.Unused)"; Command = 'Get-AACUnusedResource -IncludeCost' }
            [pscustomobject]@{ Item = 'Resources with at least one tag'; Value = (& $pct $g.TagCoverage); Command = 'Get-AACTagUsage' }
        )
        & $tab 'Governance' $(if ($g.ClosestLimit) { "$($g.ClosestLimit.Percent)%" } else { $g.Unused }) $(if ($g.ClosestLimit -and $g.ClosestLimit.Percent -ge 95) { 'bad' } elseif ($g.Unused -or ($g.ClosestLimit -and $g.ClosestLimit.Percent -ge 80)) { 'warn' } else { 'info' }) 'Limits, privileged access, unused resources and tags. Invoke-AACGovernanceAssessment has the full workbook.'
        $tables.Add(@{ Id = 'governance'; Title = 'Governance'; Section = 'Governance'; Rows = $rows; Noun = 'items'; Columns = @(@{ Key = 'Item'; Label = 'What'; Type = 'wide'; Pdf = $true }, @{ Key = 'Value'; Label = 'Value'; Pdf = $true }, @{ Key = 'Command'; Label = 'Go deeper'; Type = 'mono'; Pdf = $true }) })
    }
    if (& $want 'Advisor') {
        & $tab 'Advisor' $d.AdvisorHigh $(if ($d.AdvisorHigh) { 'warn' } else { 'good' }) "Advisor score $(if ($null -ne $d.AdvisorScore) { $d.AdvisorScore } else { '-' })$(if ($d.AdvisorSavings) { "; $(& $money $d.AdvisorSavings.Annual $d.AdvisorSavings.Currency) a year to save in $($d.AdvisorSavings.Recommendations) cost recommendation(s)" }). Get-AACAdvisorRecommendation goes deeper."
        $tables.Add(@{ Id = 'advisor'; Title = 'Azure Advisor recommendations'; Section = 'Advisor'; Rows = @($d.Advisor); Noun = 'categories'; Columns = @(@{ Key = 'Category'; Label = 'Category'; Pdf = $true }, @{ Key = 'High'; Label = 'High'; Type = 'number'; Pdf = $true }, @{ Key = 'Medium'; Label = 'Medium'; Type = 'number'; Pdf = $true }, @{ Key = 'Low'; Label = 'Low'; Type = 'number'; Pdf = $true }) })
    }
    if (& $want 'Estate') {
        & $tab 'Estate' $d.Resources 'info' "$($d.Resources) resources of $($d.ResourceTypes) types in $($d.ResourceGroups) resource groups and $($d.Regions) regions, across $(@($d.Subscriptions).Count) subscription(s)."
        $tables.Add(@{ Id = 'types'; Title = 'Resources by type'; Section = 'Estate'; Rows = @($d.TopTypes); Noun = 'types'; Columns = @(@{ Key = 'Name'; Label = 'Type'; Pdf = $true }, @{ Key = 'Resources'; Label = 'Resources'; Type = 'number'; Pdf = $true }, @{ Key = 'Type'; Label = 'Resource type'; Type = 'mono' }) })
        $tables.Add(@{ Id = 'bySubscription'; Title = 'Resources by subscription'; Section = 'Estate'; Rows = @($d.BySubscription); Noun = 'subscriptions'; Columns = @(@{ Key = 'Subscription'; Label = 'Subscription'; Pdf = $true }, @{ Key = 'Resources'; Label = 'Resources'; Type = 'number'; Pdf = $true }) })
        $tables.Add(@{ Id = 'regions'; Title = 'Resources by region'; Section = 'Estate'; Rows = @($d.TopRegions); Noun = 'regions'; Columns = @(@{ Key = 'Region'; Label = 'Region'; Pdf = $true }, @{ Key = 'Resources'; Label = 'Resources'; Type = 'number'; Pdf = $true }) })
    }
    if (& $want 'Changes') {
        & $tab 'Changes' ($d.Changes.Created + $d.Changes.Updated + $d.Changes.Deleted) $(if ($d.Changes.Deleted) { 'warn' } else { 'violet' }) "In $($d.Hours)h: $($d.Changes.Created) created, $($d.Changes.Updated) updated, $($d.Changes.Deleted) deleted. Get-AACChangeHistory goes deeper."
        $tables.Add(@{ Id = 'timeline'; Title = 'The last 14 days'; Section = 'Changes'; Rows = @($d.ChangeTimeline); Noun = 'days'; Columns = @(@{ Key = 'Day'; Label = 'Day'; Type = 'date'; Pdf = $true }, @{ Key = 'Created'; Label = 'Created'; Type = 'number'; Pdf = $true }, @{ Key = 'Updated'; Label = 'Updated'; Type = 'number'; Pdf = $true }, @{ Key = 'Deleted'; Label = 'Deleted'; Type = 'number'; Pdf = $true }) })
        $tables.Add(@{ Id = 'changers'; Title = 'Who made the most changes'; Section = 'Changes'; Rows = @($d.TopChangers); Noun = 'people and applications'; Columns = @(@{ Key = 'ChangedBy'; Label = 'Changed by'; Pdf = $true }, @{ Key = 'Changes'; Label = 'Changes'; Type = 'number'; Pdf = $true }, @{ Key = 'Deletes'; Label = 'Deletes'; Type = 'number'; Pdf = $true }) })
        $tables.Add(@{ Id = 'recent'; Title = 'Recent changes'; Section = 'Changes'; Rows = @($d.RecentChanges); Noun = 'changes'; Columns = @(@{ Key = 'Time'; Label = 'When'; Type = 'datetime'; Pdf = $true }, @{ Key = 'Change'; Label = 'Change'; Type = 'badge'; Tones = @{ Create = 'good'; Update = 'info'; Delete = 'bad' }; Facet = $true; Pdf = $true }, @{ Key = 'Resource'; Label = 'Resource'; Pdf = $true }, @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }, @{ Key = 'ChangedBy'; Label = 'By'; Facet = $true; Pdf = $true }) })
    }
    if ((& $want 'Cost') -and $d.Cost) {
        $c = $d.Cost
        & $tab 'Cost' (& $money $c.MonthToDate $c.Currency) $(if ($null -ne $c.ChangePercent -and $c.ChangePercent -gt 10) { 'warn' } else { 'info' }) "Month to date $(& $money $c.MonthToDate $c.Currency) against $(& $money $c.LastMonthToDate $c.Currency) for the same days last month; last month in all $(& $money $c.LastMonth $c.Currency); forecast (this month's daily average carried on) $(& $money $c.Forecast $c.Currency)."
        $tables.Add(@{ Id = 'services'; Title = 'What costs most this month'; Section = 'Cost'; Rows = @($c.TopServices); Noun = 'services'; Columns = @(@{ Key = 'Service'; Label = 'Service'; Pdf = $true }, @{ Key = 'Cost'; Label = "Cost ($($c.Currency))"; Type = 'money'; Pdf = $true }) })
    }

    $charts = @(
        @{ Title = 'Resources by region'; Items = @($d.TopRegions | Select-Object -First 10 | ForEach-Object { @{ Label = $_.Region; Value = $_.Resources } }); Tone = 'info' }
        $(if (& $want 'Estate') { @{ Title = 'Resources by type'; Items = @($d.TopTypes | Select-Object -First 10 | ForEach-Object { @{ Label = $_.Name; Value = $_.Resources } }); Tone = 'violet' } })
        $(if (& $want 'Health') { @{ Title = 'Resource Health'; Kind = 'donut'; CenterLabel = 'resources'; Items = @(@{ Label = 'Available'; Value = $d.Health.Available; Tone = 'good' }, @{ Label = 'Degraded'; Value = $d.Health.Degraded; Tone = 'warn' }, @{ Label = 'Unavailable'; Value = $d.Health.Unavailable; Tone = 'bad' }, @{ Label = 'Unknown'; Value = $d.Health.Unknown; Tone = 'neutral' } | Where-Object { $_.Value }) } })
        $(if (& $want 'Changes') { @{ Title = 'Changes per day (14 days)'; Items = @($d.ChangeTimeline | ForEach-Object { @{ Label = $_.Day.ToString('d MMM'); Value = $_.Created + $_.Updated + $_.Deleted } }); Tone = 'violet' } })
        $(if ((& $want 'Cost') -and $d.Cost) { @{ Title = "Daily cost, 30 days ($($d.Cost.Currency))"; Items = @($d.Cost.Daily | ForEach-Object { @{ Label = $_.Day.ToString('d MMM'); Value = $_.Cost } }); Tone = 'info' } })
    ) | Where-Object { $_ -and @($_.Items).Count }

    $facts = [ordered]@{}
    foreach ($k in $Scope.Keys) { $facts[$k] = $Scope[$k] }
    $facts['Changes'] = "last $($d.Hours)h"
    if ($d.Account) { $facts['Account'] = $d.Account }
    @{
        Subtitle = 'Dashboard: health, security, policy, governance, Advisor, the estate, recent changes - and what to do next'
        Facts    = $facts
        Status   = $d.Status
        Headline = "$(@{ Success = 'Healthy'; Warning = 'Needs attention'; Failed = 'Action needed' }[$d.Status]): $($d.Headline)"
        Tiles    = $tiles.ToArray()
        Notices  = @($d.Unread.PSObject.Properties | ForEach-Object { @{ Status = 'Warning'; Text = "Couldn't read $($_.Name): $($_.Value)" } })
        Charts   = @($charts)
        Tabs     = $tabs.ToArray()
        Tables   = $tables.ToArray()
    }
}
