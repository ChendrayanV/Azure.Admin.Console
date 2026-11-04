# Governance

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Get-AACGovernanceChange`](../Get-AACGovernanceChange.md) · [`Get-AACGovernanceSetting`](../Get-AACGovernanceSetting.md) · [`Get-AACResourceLock`](../Get-AACResourceLock.md) · [`Get-AACRoleAssignment`](../Get-AACRoleAssignment.md) · [`Get-AACServicePrincipalInsight`](../Get-AACServicePrincipalInsight.md) · [`Get-AACTagUsage`](../Get-AACTagUsage.md) · [`Invoke-AACGovernanceAssessment`](../Invoke-AACGovernanceAssessment.md) · [`Show-AACManagementGroupMap`](../Show-AACManagementGroupMap.md) · [`Test-AACAlzPolicy`](../Test-AACAlzPolicy.md) · [`Test-AACAzureLimit`](../Test-AACAzureLimit.md)

Governance questions across the whole tenant, in the spirit of the
[Azure Governance Visualizer](https://github.com/Azure/Azure-Governance-Visualizer) -
each one a command of its own, and all of them together in one workbook.

```powershell
Invoke-AACGovernanceAssessment -HtmlPath .\Governance.html                     # everything, as a tabbed workbook
Invoke-AACGovernanceAssessment -MarkdownPath .\wiki\Governance.md -MarkdownFlavor AzureDevOps -NoDisplay   # a wiki page, from a pipeline
Show-AACManagementGroupMap                                                     # the hierarchy, in the browser
Get-AACRoleAssignment -ExpandGroup -HtmlPath .\Rbac.html                       # every role assignment, groups expanded
Test-AACAzureLimit -FailOnLimit Warning                                        # fail a pipeline at 80% of any limit
Test-AACAlzPolicy -LibraryPath C:\alz-library -ManagementGroupMap @{ alz = 'contoso' }
```

| Area | Command | What it answers |
|---|---|---|
| Hierarchy | `Show-AACManagementGroupMap` | Each management group, its subscriptions, policy and role assignments - a map, a tree, or `Export-AACDiagram -View Governance` for draw.io |
| Access | `Get-AACRoleAssignment` | Every role assignment at every scope; orphaned ones, privileged guests, applications as Owner, custom roles unused or as powerful as Owner |
| Identities | `Get-AACServicePrincipalInsight` | Applications and managed identities with Azure roles; credentials about to expire; other tenants' apps |
| Policy | `Get-AACPolicyRemediation` | Policies that could fix what they find, and whether remediation ran (`Invoke-AACPolicyAssessment` covers assignments, compliance, exemptions and identities' roles) |
| Limits | `Test-AACAzureLimit` | Scopes close to an Azure limit, with what to do; `-IncludeQuota` adds each region's compute, network and storage quota |
| Settings | `Get-AACGovernanceSetting` | Hierarchy settings, management group activity logs, security contacts, classic administrators, preview features, providers |
| Tags | `Get-AACTagUsage` | Tag coverage and consistency |
| Locks | `Get-AACResourceLock` | Locks, and critical resources left unlocked |
| Changes | `Get-AACGovernanceChange` | Policy and access changes, and who made them |
| Reference | `Test-AACAlzPolicy` | Policy assignments against the Azure Landing Zones archetypes |

**The workbook.** `Invoke-AACGovernanceAssessment` runs the areas (or those in
`-Area`), keeps going when one fails (it says which, and why), and writes a
Summary with the hierarchy as a tree, a Findings tab with the high and medium
findings of every area, and a tab per area. `-MarkdownPath` writes the same as
one Markdown page - the hierarchy as a Mermaid diagram, a table per area -
for a GitHub or Azure DevOps wiki (`-MarkdownFlavor`).

**The Azure Landing Zones check.** `Test-AACAlzPolicy` reads a copy of the
[Azure Landing Zones Library](https://github.com/Azure/Azure-Landing-Zones-Library)
you clone yourself, at the release you want - nothing is downloaded. If your
management groups are named differently from the reference, map them:
`-ManagementGroupMap @{ alz = 'contoso'; landingzones = 'contoso-lz' }`.

**What it needs.** Reader on the scope (Reader on the tenant root group for
its settings), and in Entra ID Directory.Read.All and Application.Read.All for
names and credentials (GroupMember.Read.All for `-ExpandGroup`). What can't
be read is left out, and said.
