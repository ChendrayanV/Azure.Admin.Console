# Quick start

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Connect-AAC`](../Connect-AAC.md)

```powershell
Import-Module Azure.Admin.Console
Connect-AAC                                  # opens your browser to sign in

# Azure Advisor: the console view, or CSV, PDF and interactive HTML reports
Get-AACAdvisorRecommendation
Get-AACAdvisorRecommendation -CsvPath .\Advisor.csv -PdfPath .\Advisor.pdf -HtmlPath .\Advisor.html

# Azure Firewall Policy rules, as an interactive HTML report
Get-AACFirewallRule -HtmlPath .\FirewallRules.html

# Which firewall rules let 10.1.2.3 reach 10.0.0.4 on UDP 53?
Get-AACFirewallRule -SourceAddress 10.1.2.3 -DestinationAddress 10.0.0.4 -Port 53 -Protocol UDP

# What you run, and what it costs
Get-AACInventory -View Chart
Get-AACInventory -View Chart -HtmlPath .\Inventory.html     # every resource, with portal links
Show-AACCost

# The tenant as a tree, with secure scores and costs
Get-AACInventory -Cost -HtmlPath .\Inventory.html

# The whole environment, ARI-style: inventory, Advisor, retirements, policy, outages - CSV, HTML, PDF, diagrams
Invoke-AACTenantAssessment -SecurityCenter -IncludeCost

# Defender for Cloud and Azure Policy: scores, recommendations, alerts, plans, compliance
Invoke-AACDefenderAssessment -View Posture -HtmlPath .\Security.html

# Every network security group, assessed
Get-AACNetworkSecurityGroup

# Azure Policy: every resource's compliance, for one management group
Get-AACPolicyState -ManagementGroupId 'mg-landingzones' -HtmlPath .\Policy.html

# What is assigned: every policy assignment, its parameter values and resource types
Get-AACAssignedPolicy -SubscriptionId '00000000-0000-0000-0000-000000000000' -CsvPath .\AssignedPolicy.csv

# Which VM sizes a new three-zone AKS node pool can use, and why not
Get-AACSkuAvailability -ClusterName 'aks-contoso' -Zone 1, 2, 3 -Series D, E -NodeCount 3

# How much is in every blob container, by access tier, with the largest blobs
Get-AACStorageAccountContainerSize -AuthMode Auto -HtmlPath .\Storage.html

# What a Terraform plan changes, down to each attribute (offline, no sign-in)
Get-AACTerraformPlan -Path .\plan.json

# Who is in your Entra ID groups, nested groups included
Get-AACEntraGroupMembership -GroupNameStartsWith 'grp-' -HtmlPath .\Groups.html

# A diagram of a resource group, in your browser
Show-AACResourceMap -ResourceGroupName 'rg-app'

# The whole network: hubs at the centre of their spokes, peerings, firewalls, private endpoints
Show-AACNetworkTopology

# PSRule for Azure on the live estate, as a clickable HTML report
Invoke-AACPSRule -HtmlPath .\PSRule.html

# Just the module's naming and tag rules - quick: names, types and tags only
Invoke-AACPSRule -Rule 'AAC.*'

# A storage account, idempotently: plan, Azure Policy and PSRule gates, then apply (no template)
Deploy-AACStorageAccount -SubscriptionId <subscription> -ResourceGroupName rg-data -ConfigurationPath .\Examples\storage-account.psd1 -WhatIf

# Which resources' logs don't reach Log Analytics - and what is misconfigured
Get-AACDiagnosticSetting -ExpectedWorkspace 'law-central' -HtmlPath .\Diagnostics.html

# A Log Analytics workspace: table sizes, settings, recommendations, insights
Invoke-AACLogAnalyticsWorkspaceAssessment -WorkspaceId 'law-contoso-prod' -HtmlPath .\Workspace.html -PdfPath .\Workspace.pdf

# Virtual networks: available IPs, subnets, peerings, NSGs, ASGs, DNS and security
Invoke-AACVirtualNetworkAssessment -HtmlPath .\VNet.html

# IP address management: your address plan, every IP address, overlaps and the next free ranges
Get-AACIPAMReport -AddressPlan .\ipam-plan.psd1 -Open

# The last 2 hours of exceptions from Application Insights
Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-contoso-prod'
```

## Console view or reports

Every command works the same way:

- **Console view:** at the prompt, a command draws its view. A view longer
  than the terminal is shown a page at a time: press any key for the next
  page, or A for the rest. `-NoPaging` turns paging off, and it's skipped
  automatically when output is redirected.
- **Reports:** with `-CsvPath`, `-PdfPath` or `-HtmlPath`, the report is in
  the files. The console shows only the progress and the files written, not
  the view. Add `-PassThru` to get the objects as well.
- **Objects:** piped onward, or with `-NoDisplay`, a command returns its
  objects and draws no view. Stopping early is fine:
  `Get-AACSkuAvailability -Location uksouth | Select-Object -First 5` ends the
  command quietly and the rest of your script carries on.
- **Progress:** every command shows the same progress display: the title,
  then one line per step with a bar, a percentage and the elapsed time, each
  finishing with what it did.
- **Status:** every command shows a state the same way, as a symbol, a
  colour and a word, so nothing depends on colour alone:

  | State       | Symbol | Colour | Used for                                        |
  | ----------- | ------ | ------ | ----------------------------------------------- |
  | Success     | ✓ (+)  | green  | done, verified, healthy, nothing to fix         |
  | Warning     | ⚠ (!)  | orange | partly read, degraded, needs attention          |
  | Failed      | ✗ (x)  | red    | failed, blocked, unavailable                    |
  | In progress | ↻ (~)  | blue   | running, ready to apply                         |
  | Info        | ℹ (i)  | grey   | nothing found, notes                            |

  Outcomes that matter (verified, blocked, no changes, nothing found, what
  couldn't be read) are callouts: a rounded panel in the state's colour,
  headed by its symbol. Notices are status lines. The symbols in brackets
  are what a console that isn't UTF-8 (code page 437 or 850) shows instead.

**Nothing is cut off.** Console views wrap long text - reasons,
recommendations, messages - rather than truncating it, and list every
finding; the PSRule view lists up to 50 resources per rule and says how many
more there are. The objects' default tables at the prompt wrap too
(`Azure.Admin.Console.Format.ps1xml`), and `Format-List *` or
`Select-Object *` shows every property.

The HTML reports are single, self-contained files with no external scripts,
styles or fonts, so they open offline and work as email attachments or
pipeline artifacts. Each one has:

- tables that start collapsed: click a table's title (or press Enter on it)
  to show or hide it, or use _Expand all_ / _Collapse all_; a tile, chart or
  tree link opens the table it filters, and printing shows every table;
- clickable tiles and bar charts that filter the table;
- search, filter drop-downs, sortable columns, and grouping with subtotals;
- Azure portal links and _Copy ID_ for every resource;
- a CSV download of exactly the rows shown;
- light and dark themes, and a layout that works on a phone.

The PDF reports open with the bookmarks panel showing: one bookmark per
section and table, nested, and collapsed so the panel starts as a short list
of sections. A PDF can't hide its tables the way a web page can, so the
bookmarks are how you jump to the one you want.
