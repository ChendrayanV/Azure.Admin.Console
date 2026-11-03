<div align="center">

<img src="assets/readme/profile-flip.svg" width="200" alt="Azure.Admin.Console: a profile picture that flips to Azure, Reports, Lens, M365, Audit, Entra and Logs icons">

# Azure.Admin.Console

**Azure, Microsoft 365 and Azure DevOps - assessed, reported and explained from PowerShell.**
Plain REST. No Az or Microsoft.Graph modules. Read-only by default.

[![CI](https://github.com/ChendrayanV/Azure.Admin.Console/actions/workflows/ci.yml/badge.svg)](https://github.com/ChendrayanV/Azure.Admin.Console/actions/workflows/ci.yml)
[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/Azure.Admin.Console?label=PowerShell%20Gallery&color=0078D4)](https://www.powershellgallery.com/packages/Azure.Admin.Console)
[![Downloads](https://img.shields.io/powershellgallery/dt/Azure.Admin.Console?label=downloads&color=2E9E6B)](https://www.powershellgallery.com/packages/Azure.Admin.Console)
[![PowerShell 7.2+](https://img.shields.io/badge/PowerShell-7.2%2B-5391FE?logo=powershell&logoColor=white)](https://github.com/PowerShell/PowerShell)
[![Platforms](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20macOS-555555)](#how-to-use-it)
[![License: MIT](https://img.shields.io/badge/license-MIT-7B61FF.svg)](LICENSE)
[![Sponsor](https://img.shields.io/github/sponsors/ChendrayanV?label=Sponsor&logo=githubsponsors&color=EA4AAA)](https://github.com/sponsors/ChendrayanV)

[How to use it](#how-to-use-it) · [What's new](#whats-new-in-0149) · [Architecture design](#architecture-design) · [Commands](#whats-inside) · [Full guide](GUIDE.md) · [Contribute](#contributing) · [Contact](#contact)

</div>

---

> **Azure doesn't stop at the subscription.** Every identity is governed in Microsoft 365, and every change ships through Azure DevOps. Assess one without the others and you're reading a third of the story - Azure.Admin.Console reads all three.

## Who it's for

| You are | You get |
|---|---|
| **Azure administrator** | Health, inventory, locks, diagnostics and errors - one command each |
| **Platform / cloud engineer** | Assessments for AKS, networks, storage, Cosmos DB, Service Bus, Log Analytics, WAF and ALZ |
| **Security and compliance** | Defender, Azure Policy, attack paths, access reviews, legacy authentication, NSGs |
| **FinOps** | Costs, anomalies, unused and under-used resources, Advisor savings |
| **Solution architect** | A guided design - patterns, components, policy checks, draw.io and Mermaid diagrams, decision records - before anything is deployed |
| **Microsoft 365 / Entra admin** | Tenant assessment, nested group membership, application permissions |
| **DevOps team** | An Azure DevOps assessment: pipelines, tools, SBOM, security, DORA - and a plan to move to GitHub |
| **Consultant** | Hand-over-ready HTML, PDF and CSV reports from a read-only sign-in |

## What's new in 0.14.9

Click a tab to open it.

<details open>
<summary><b>📜 Activity Log assessment</b> &nbsp;·&nbsp; <i><code>Invoke-AACActivityLogAssessment</code>, 90, 180 or 365 days</i></summary>

<br>

Every resource's activity, with subscription, resource group, resource and tags on every row: who changed what and when, when each resource was last used, which are idle or were deleted, changes made by hand, guests and people changing access, keys read by people. It reads the Log Analytics workspace each subscription already sends its Activity Log to, found automatically, so a year takes seconds. Subscriptions with no export fall back to the REST API, which keeps 90 days. A Coverage tab says which source each subscription used.

```powershell
Invoke-AACActivityLogAssessment -ManagementGroupId 'mg-landingzones' -Days 365 -TagName CostCenter -RequiredTag CostCenter -HtmlPath .\activity.html
```

</details>

<details>
<summary><b>🔎 Activity Log events, readable</b> &nbsp;·&nbsp; <i><code>Show-AACActivityLogEvent</code></i></summary>

<br>

An Activity Log event holds about sixty values, nested six levels deep. This command makes each one a card: what failed and why (the innermost error and what to do), who (decoded from the token: service principal, managed identity or user, how it signed in, which tenant, which roles), where, and the IDs to trace it. It reads the JSON you copy from the portal (no sign-in needed), takes a correlation ID, or accepts the failures an assessment found from the pipeline.

```powershell
Show-AACActivityLogEvent -Path .\event.json -PdfPath .\incident.pdf
```

</details>

<details>
<summary><b>🛡️ Effective Azure Policy</b> &nbsp;·&nbsp; <i><code>Show-AACEffectivePolicy</code> · <code>Test-AACPolicyDeployment</code></i></summary>

<br>

Starts from the resource, not the assignment. You see every policy that applies, what it does to the resource (blocks, audits, changes, deploys), where it is assigned, whether the resource complies and why not, and what exempts it or leaves it out. For a resource you haven't deployed yet, Azure Policy itself says what it would refuse and which values it allows. `Test-AACPolicyDeployment` checks an ARM template or Bicep file before it deploys, and can fail a pipeline.

```powershell
Show-AACEffectivePolicy -ResourceId $storageId
Test-AACPolicyDeployment -TemplatePath .\main.bicep -SubscriptionId $sub -ResourceGroupName 'rg-orders' -FailOn Deny
```

</details>

<details>
<summary><b>📨 Service Bus entities</b> &nbsp;·&nbsp; <i><code>Show-AACServiceBusEntity</code></i></summary>

<br>

Queues and topics as the signed-in user can see them, whether the role is on the namespace or only on the entities. You get live counts, dead-letters, subscriptions and configuration, plus Azure Monitor metrics with trends when the role covers the namespace. With an entity role only, `-Sample` builds a backlog trend instead.

```powershell
Show-AACServiceBusEntity -NamespaceId $namespaceId -EntityName 'orders-*' -TimeRange 7d -HtmlPath .\sb.html
```

</details>

<details>
<summary><b>🔑 Key Vault assessment</b> &nbsp;·&nbsp; <i><code>Invoke-AACKeyVaultAssessment</code> (was <code>Get-AACKeyVaultInsight</code>)</i></summary>

<br>

Renamed to match the other `Invoke-AAC<Thing>Assessment` commands; it works as before. Replace the old name in your scripts, and `AAC.KeyVaultInsight` with `AAC.KeyVaultAssessment` anywhere you test the type.

</details>

The breaking change (one rename, no alias) is in the [changelog](CHANGELOG.md), with 0.14.8 (the Architecture design area) and earlier releases.

## Architecture design

**Design it before you deploy it, and draw it the way you'll deploy it.** Architecture reviews usually start from a whiteboard sketch that nobody keeps up to date, then find out at deployment that a policy denies it. The Architecture commands turn the conversation into a design: they ask the questions an Azure architect would ask, pick the [cloud design patterns](https://learn.microsoft.com/azure/architecture/patterns/) that fit, lay out the components, check them against the Well-Architected Framework and your landing zone's Azure Policy, and draw the result. The diagram, the findings and the decision records all come from the same model, so they agree.

| Step | Command | What you get |
|:---:|---|---|
| 1 | `New-AACArchitectureBrief` | About 20 probe questions - business, reliability, security, performance, data, cost, operations. Answer them at the prompt, from a hashtable or a file; whatever isn't answered is listed as an assumption |
| 2 | `Get-AACArchitecturePattern` | 15 patterns ranked for the brief (Cache-Aside, Queue-Based Load Leveling, Deployment Stamps, Geode...), each with why it fits and its trade-offs |
| 3 | `New-AACArchitectureDesign` | The components and their settings: SKUs, zone redundancy, private endpoints, identity, hub and spoke, a second region when the RTO or SLA needs one. Signed in, it reads the landing zone's inherited policy and allowed locations |
| 4 | `Test-AACArchitectureDesign` | Findings by pillar and severity, each mapped to its Azure Policy definition and PSRule for Azure rule; *Blocking* when the landing zone would deny it. `-FailOnGap` fails a pipeline |
| 5 | `New-AACArchitectureDiagram` | Mermaid, Markdown and a multi-page **draw.io** diagram with Azure icons |
| 6 | `Export-AACArchitectureDecision` | Architecture decision records: the topology, each pattern, each accepted risk with its owner and review date |

```powershell
$brief  = New-AACArchitectureBrief -Name 'contoso-orders'                    # asks the questions
$design = Get-AACArchitecturePattern -Brief $brief -RecommendedOnly |
          New-AACArchitectureDesign -Brief $brief -LandingZone 'mg-corp' -OutPath .\contoso-orders.design.json
Test-AACArchitectureDesign -Design $design -HtmlPath .\validation.html
New-AACArchitectureDiagram -Design $design -Path .\diagrams                   # .mmd, .md, .drawio
Export-AACArchitectureDecision -Design $design -Path .\adr -Owner 'Orders team'
```

**The diagram.** `New-AACArchitectureDiagram` writes a draw.io file you can open in the desktop app, [app.diagrams.net](https://app.diagrams.net) or VS Code, and keep editing. It isn't a picture:

- **Azure icons** inside real containers: landing zone, region, hub and spoke virtual networks, data tier, operations, delivery pipeline. Move a box and what's in it moves too.
- **A status dot** on every component for its worst open finding: green, amber or red.
- **Shape data** on every component (Edit > Edit Data): service, SKU, region, zone redundancy, private endpoint, identity, open findings.
- **Layers** you can turn on and off: WAF badges, Azure Policy, guardrail zones, the PSRule gate, Advisor and Defender recommendations.
- **Five pages:** a cover, the architecture, policy and compliance, the findings, and a legend.

<table>
<tr>
<td colspan="2" align="center"><b>Architecture</b> - two regions in a landing zone, Azure icons, finding dots, policy chips, guardrail zones<br><img src="assets/readme/architecture-diagram.png" alt="draw.io architecture page: a landing zone holding a global edge, two regions with hub and spoke virtual networks and private data tiers, operations and a delivery pipeline, drawn with Azure icons"></td>
</tr>
<tr>
<td width="50%" align="center"><b>Cover</b> - facts, open findings, pillar scores<br><img src="assets/readme/architecture-cover.png" alt="draw.io cover page with the design's facts, open findings by severity and Well-Architected pillar scores"></td>
<td width="50%" align="center"><b>Policy and compliance</b> - its own tab<br><img src="assets/readme/architecture-policy.png" alt="draw.io policy page listing inherited Azure Policy assignments and each component's rules with Azure Policy, PSRule and result"></td>
</tr>
<tr>
<td colspan="2" align="center"><b>Validation report</b> - <code>Test-AACArchitectureDesign -HtmlPath</code><br><img src="assets/readme/architecture-validation.png" alt="HTML validation report with the Well-Architected score, blocking and high findings and a score per pillar"></td>
</tr>
</table>

<sub>Snapshots from a fictional design (contoso-orders) in a fictional landing zone.</sub>

Everything except reading the landing zone runs offline, so a design can be reviewed before there is a subscription for it. The walkthrough is in [the guide](docs/guide/architecture-design.md).

## What's inside

89 commands. Every one gives a **console view**, **objects**, and **CSV, HTML and PDF** reports.

| Area | Commands |
|---|---|
| **Design** | `New-AACArchitectureBrief` · `Get-AACArchitecturePattern` · `New-AACArchitectureDesign` · `Test-AACArchitectureDesign` · `New-AACArchitectureDiagram` · `Export-AACArchitectureDecision` |
| **Assess** | `Invoke-AACTenantAssessment` · `Invoke-AACWafAssessment` · `Invoke-AACGovernanceAssessment` · `Invoke-AACPSRule` · `Test-AACGoLiveReadiness` · `Invoke-AACAksAssessment` · `Invoke-AACFunctionAppAssessment` and 11 more |
| **See** | `Show-AACDashboard` · `Get-AACInventory` · `Show-AACResourceMap` · `Show-AACNetworkTopology` · `Get-AACDependencyGraph` |
| **Cost** | `Show-AACCost` · `Get-AACCostAnomaly` · `Get-AACUnusedResource` · `Get-AACResourceUtilization` · `Get-AACAdvisorRecommendation` |
| **Secure** | `Get-AACSecurityPosture` · `Get-AACAttackPath` · `Get-AACAccessReview` · `Get-AACNetworkSecurityGroup` · `Get-AACLegacyAuthentication` |
| **Plan IPs** | `Get-AACIPAMReport` - your address plan, every IP address, overlaps and the next free ranges |
| **Govern** | `Show-AACEffectivePolicy` 🆕 · `Test-AACPolicyDeployment` 🆕 · `Get-AACPolicyState` · `Get-AACComplianceGap` · `Get-AACConfigurationDrift` · `Get-AACResourceLock` · `Test-AACAzureLimit` |
| **Operate** | `Get-AACResourceHealth` · `Get-AACChangeHistory` · `Get-AACResourceError` · `Invoke-AACHealthCheck` · `Get-AACFailoverReadiness` · `Invoke-AACActivityLogAssessment` 🆕 · `Show-AACActivityLogEvent` 🆕 · `Show-AACServiceBusEntity` 🆕 |
| **Microsoft 365** | `Invoke-AACM365Assessment` · `Get-AACEntraGroupMembership` · `Get-AACApplicationPermission` · `New-AACApplicationPermission` |
| **Azure DevOps** | `Invoke-AACADOAssessment` |
| **Build** | `Export-AACTerraform` · `Get-AACTerraformPlan` · `Deploy-AACStorageAccount` |

Every command, with examples: [**the full guide**](GUIDE.md) and [**docs/**](docs/).

## How to use it

```powershell
Install-PSResource -Name Azure.Admin.Console        # or: Install-Module Azure.Admin.Console -Scope CurrentUser
Connect-AAC                                         # sign in once, in your browser

Show-AACDashboard                                         # the estate on one screen
Invoke-AACTenantAssessment -HtmlPath .\tenant.html        # the whole environment, as a report
Invoke-AACADOAssessment -Organization contoso -UseAzureSignIn -HtmlPath .\ado.html
```

The same switches work everywhere:

| Switch | What it does |
|---|---|
| `-HtmlPath` · `-PdfPath` · `-CsvPath` | Write a report |
| `-NoDisplay` | Return objects only, for scripts |
| `-PassThru` | Show the view and return the objects |
| `Get-Help <command> -Full` | The permissions it needs, and examples |

PowerShell 7.2+ on Windows, Linux and macOS. PDF reports need Windows and PowerShell 7.4+.
Only `Deploy-AACStorageAccount` and `New-AACApplicationPermission` change anything in Azure or Entra ID, and both support `-WhatIf`.

<a href="https://www.youtube.com/watch?v=xBkStQ1H2OU">Watch the walkthrough on YouTube</a>

## Contributing

New commands, fixes, ideas and bug reports are all welcome - you don't need to be an expert to help.
Open an [issue](https://github.com/ChendrayanV/Azure.Admin.Console/issues) to say what you'd like to work on, and we'll shape it together. The rules and steps, for people and AI coding agents, are in [AGENTS.md](AGENTS.md).

<details>
<summary><b>How the project is laid out - and how to add a command</b></summary>

```text
Azure.Admin.Console.psd1 / .psm1   the module: loads each area of src\, Core first
src\
  Core\     sign-in, REST helpers, console views, CSV / HTML / PDF reports
  Azure\    commands scoped to subscriptions and management groups
  M365\     commands for the Entra ID / Microsoft 365 tenant
  DevOps\   commands for Azure DevOps
  Architecture\  architecture design: brief, patterns, design, rules, diagrams, decisions
    <Area>\Public\    one exported command per file
    <Area>\Private\   its helpers
Tests\<Area>\         Pester tests, fully mocked - no Azure sign-in needed
Tests\Fixtures\       fake API answers the tests read
```

To add a command, copy a sibling:

1. `src\<Area>\Public\Verb-AACThing.ps1` - the command, with comment-based help.
2. `src\<Area>\Private\` - turn API rows into objects, then the view and reports.
3. Add it to `FunctionsToExport` in `Azure.Admin.Console.psd1`.
4. `Tests\<Area>\Thing.Tests.ps1` with a fixture in `Tests\Fixtures\`.

House rules: REST through the Core helpers (no Az or Graph modules), read-only unless the command supports `-WhatIf`, and `Set-StrictMode -Version Latest` clean.

```powershell
Invoke-Pester -Path ./Tests/Azure/Cost.Tests.ps1 -Output Detailed   # one test file while you work
./build.ps1 -Task Docs                                             # after changing help
./build.ps1                                                        # docs, every test, analyzer, package
```

</details>

## Credits

With thanks to the people whose work and ideas shaped this module:

| GitHub |
|:---:|
| <img src="https://github.com/shashi-create.png?size=80" width="40" height="40" alt="Shashi Shetty"> **Shashi Shetty** [![GitHub](https://img.shields.io/badge/GitHub-shashi--create-181717?logo=github)](https://github.com/shashi-create) |

Built on [Spectre.Console](https://spectreconsole.net), [PDFsharp and MigraDoc](https://www.pdfsharp.com) and [PSRule for Azure](https://azure.github.io/PSRule.Rules.Azure/), with alert and resiliency data from [Azure Monitor Baseline Alerts](https://github.com/Azure/azure-monitor-baseline-alerts) and the [Azure Proactive Resiliency Library](https://github.com/Azure/Azure-Proactive-Resiliency-Library-v2) ([notices](THIRD-PARTY-NOTICES.md)).

## Contact

**Chendrayan Venkatesan** - Azure | DevSecOps | PowerShell

[![GitHub](https://img.shields.io/badge/GitHub-ChendrayanV-181717?logo=github)](https://github.com/ChendrayanV)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-chendrayanv-0A66C2?logo=linkedin&logoColor=white)](https://www.linkedin.com/in/chendrayanv/)
[![X](https://img.shields.io/badge/X-@ChendrayanV-000000?logo=x&logoColor=white)](https://twitter.com/ChendrayanV)
[![Blog](https://img.shields.io/badge/Blog-about--powershell.com-FF6B35)](https://about-powershell.com)

Questions and bugs: [open an issue](https://github.com/ChendrayanV/Azure.Admin.Console/issues/new).

<sub>MIT licensed - see [LICENSE](LICENSE).</sub>
