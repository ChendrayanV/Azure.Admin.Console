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

[How to use it](#how-to-use-it) · [Commands](#whats-inside) · [Full guide](GUIDE.md) · [Contribute](#contributing) · [Contact](#contact)

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
| **Microsoft 365 / Entra admin** | Tenant assessment, nested group membership, application permissions |
| **DevOps team** | An Azure DevOps inventory: pipelines, tools, security, DORA - and a plan to move to GitHub |
| **Consultant** | Hand-over-ready HTML, PDF and CSV reports from a read-only sign-in |

## What's inside

78 commands. Every one gives a **console view**, **objects**, and **CSV, HTML and PDF** reports.

| Area | Commands |
|---|---|
| **Assess** | `Invoke-AACAssessment` · `Invoke-AACWafAssessment` · `Invoke-AACGovernanceAssessment` · `Invoke-AACPSRule` · `Test-AACGoLiveReadiness` · `Invoke-AACAksAssessment` · `Invoke-AACFunctionAppAssessment` and 11 more |
| **See** | `Show-AACDashboard` · `Get-AACInventory` · `Show-AACResourceMap` · `Show-AACNetworkTopology` · `Get-AACDependencyGraph` |
| **Cost** | `Show-AACCost` · `Get-AACCostAnomaly` · `Get-AACUnusedResource` · `Get-AACResourceUtilization` · `Get-AACAdvisorRecommendation` |
| **Secure** | `Get-AACSecurityPosture` · `Get-AACAttackPath` · `Get-AACAccessReview` · `Get-AACNetworkSecurityGroup` · `Get-AACLegacyAuthentication` |
| **Plan IPs** | `Get-AACIPAMReport` - your address plan, every IP address, overlaps and the next free ranges |
| **Govern** | `Get-AACPolicyState` · `Get-AACComplianceGap` · `Get-AACConfigurationDrift` · `Get-AACResourceLock` · `Test-AACAzureLimit` |
| **Operate** | `Get-AACResourceHealth` · `Get-AACChangeHistory` · `Get-AACResourceError` · `Invoke-AACHealthCheck` · `Get-AACFailoverReadiness` |
| **Microsoft 365** | `Invoke-AACM365Assessment` · `Get-AACEntraGroupMembership` · `Get-AACApplicationPermission` · `New-AACApplicationPermission` |
| **Azure DevOps** | `Get-AACADOInventory` |
| **Build** | `Export-AACTerraform` · `Get-AACTerraformPlan` · `Deploy-AACStorageAccount` |

Every command, with examples: [**the full guide**](GUIDE.md) and [**docs/**](docs/).

## How to use it

```powershell
Install-PSResource -Name Azure.Admin.Console        # or: Install-Module Azure.Admin.Console -Scope CurrentUser
Connect-AAC                                         # sign in once, in your browser

Show-AACDashboard                                   # the estate on one screen
Invoke-AACAssessment -HtmlPath .\assessment.html    # the whole environment, as a report
Get-AACADOInventory -Organization contoso -UseAzureSignIn -HtmlPath .\ado.html
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
Open an [issue](https://github.com/ChendrayanV/Azure.Admin.Console/issues) to say what you'd like to work on, and we'll shape it together.

<details>
<summary><b>How the project is laid out - and how to add a command</b></summary>

```text
Azure.Admin.Console.psd1 / .psm1   the module: loads each area of src\, Core first
src\
  Core\     sign-in, REST helpers, console views, CSV / HTML / PDF reports
  Azure\    commands scoped to subscriptions and management groups
  M365\     commands for the Entra ID / Microsoft 365 tenant
  DevOps\   commands for Azure DevOps
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

Built on [Spectre.Console](https://spectreconsole.net), [PDFsharp and MigraDoc](https://www.pdfsharp.com) and [PSRule for Azure](https://azure.github.io/PSRule.Rules.Azure/).

## Contact

**Chendrayan Venkatesan** - Azure | DevSecOps | PowerShell

[![GitHub](https://img.shields.io/badge/GitHub-ChendrayanV-181717?logo=github)](https://github.com/ChendrayanV)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-chendrayanv-0A66C2?logo=linkedin&logoColor=white)](https://www.linkedin.com/in/chendrayanv/)
[![X](https://img.shields.io/badge/X-@ChendrayanV-000000?logo=x&logoColor=white)](https://twitter.com/ChendrayanV)
[![Blog](https://img.shields.io/badge/Blog-about--powershell.com-FF6B35)](https://about-powershell.com)

Questions and bugs: [open an issue](https://github.com/ChendrayanV/Azure.Admin.Console/issues/new).

<sub>MIT licensed - see [LICENSE](LICENSE).</sub>
