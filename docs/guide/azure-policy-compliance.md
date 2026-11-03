# Azure Policy compliance

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Get-AACAssignedPolicy`](../Get-AACAssignedPolicy.md) · [`Get-AACPolicyRemediation`](../Get-AACPolicyRemediation.md) · [`Get-AACPolicyState`](../Get-AACPolicyState.md) · [`Invoke-AACPolicyAssessment`](../Invoke-AACPolicyAssessment.md) · [`Show-AACEffectivePolicy`](../Show-AACEffectivePolicy.md) · [`Test-AACPolicyDeployment`](../Test-AACPolicyDeployment.md)

`Get-AACPolicyState` reads the Azure Policy states with one Azure Resource
Graph KQL query (`policyresources`), with the policies' and initiatives'
display names. The assignments' names, scopes and enforcement are read
tenant-wide, because many are assigned at a management group. Reader is
enough.

```powershell
Get-AACPolicyState                                                           # every subscription you can see
Get-AACPolicyState -ManagementGroupId 'mg-landingzones'                      # every subscription under a management group
Get-AACPolicyState -SubscriptionId $sub -ResourceGroupName 'rg-app', 'rg-data'
Get-AACPolicyState -ComplianceState NonCompliant -HtmlPath .\Policy.html -PdfPath .\Policy.pdf -CsvPath .\Policy.csv
Get-AACPolicyState -ComplianceState NonCompliant -NoDisplay | Group-Object Policy | Sort-Object Count -Descending
```

| Scope                |                                                                                                 |
| -------------------- | ----------------------------------------------------------------------------------------------- |
| `-ManagementGroupId` | Every subscription under these management groups                                                |
| `-SubscriptionId`    | These subscriptions                                                                             |
| `-ResourceGroupName` | Only these resource groups, with either of the above or on its own                              |
| `-ComplianceState`   | Only NonCompliant, Compliant, Exempt, Unknown, Conflict or Error states - filtered in the query |

**One row per resource and policy** (`AAC.PolicyState`): compliance state,
resource, type, resource group, subscription, location, policy, initiative,
assignment, where it is assigned (management group, subscription or resource
group, by name), enforcement, effect and when it was evaluated.

From those rows:

- each **resource** takes the state that ranks first across its policies,
  as the Azure portal does: Non-compliant, Compliant, Error, Conflicting,
  Protected, Exempt, Unknown;
- **compliance (%)** is the portal's: (compliant + exempt + unknown +
  protected resources) / every resource evaluated; _Not started_ states
  aren't counted;
- compliance **per assignment** (least compliant first, with enforcement),
  **per subscription**, **per resource group** and **per policy**.

The console shows tiles, compliance by subscription and by resource group,
the assignments, and every non-compliant resource grouped by policy. The
HTML report has a donut of the states and charts that filter tables of
resources, states, assignments, policies, subscriptions and resource groups.
The PDF has the summary, the scopes, the assignments and the non-compliant
resources by policy. `-CsvPath` writes every state.

## Policy assessment

`Invoke-AACPolicyAssessment` assesses Azure Policy as a whole: what is
assigned, how compliant it is, the exemptions, and what to improve. It follows
the analysis of [AzPolicyLens](https://github.com/Azure/AzPolicyLens): Reader
only, Azure Resource Graph only, no Az modules.

```powershell
Invoke-AACPolicyAssessment                                                     # everything you can see
Invoke-AACPolicyAssessment -ManagementGroupId 'mg-landingzones' -HtmlPath .\Policy.html -PdfPath .\Policy.pdf -CsvPath .\policy
Invoke-AACPolicyAssessment -SubscriptionId '00000000-0000-0000-0000-000000000000' -Audience Application -HtmlPath .\Policy.html
Invoke-AACPolicyAssessment -NoDisplay | Where-Object Rating -NE 'Good'          # assignments under the threshold
```

| What                 | How it works                                                                                                                                                                                                                                                                                                                                                 |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Compliance           | Each resource is counted once, at its worst state (NonCompliant, then Compliant, Conflict, Exempt). Compliance = (compliant + exempt) / all. It is reported overall and by subscription, management group, assignment (and subscription), policy and category. A value under `-ComplianceWarningPercent` (default 80) is a Warning; under half of it is Poor |
| Scope                | No scope: everything. `-ManagementGroupId`: the management group and everything under it. `-SubscriptionId`: those subscriptions and every assignment that reaches them, including assignments made on their management groups (excluded scopes are honoured)                                                                                                |
| Assignments findings | A definition assigned directly instead of in an initiative; DoNotEnforce; a definition that can't be found; compliance under the threshold; deprecated or preview policies assigned; excluded scopes that don't exist; the same definition assigned twice on one scope path; Deny without a non-compliance message                                           |
| Identity findings    | DeployIfNotExists and Modify assignments with no managed identity, or with an identity missing the roles their policies list (`roleDefinitionIds`)                                                                                                                                                                                                           |
| Exemptions findings  | Expired; expiring within `-ExemptionWarningDays` (default 30); no expiry; for an assignment that no longer exists                                                                                                                                                                                                                                            |
| Definitions findings | Unassigned custom definitions and initiatives; unused policy definition groups; one control under different group names; no category in the metadata                                                                                                                                                                                                         |
| Audience             | `Platform` (default, like AzPolicyLens's detailed wiki): everything, including `hidden-` metadata and tags. `Application` (its basic wiki): an application team's assignments, compliance and exemptions, without the unassigned definitions or metadata hygiene                                                                                             |

**Outputs**

- **Console view:** tiles, compliance by subscription and category, the
  assignments (least compliant first), the exemptions that need attention,
  and the High and Medium findings.
- **Objects:** `AAC.PolicyAssignmentReport`. Each has its `Compliance` (by
  subscription), `PolicyStates` and `Findings`.
- **`-CsvPath`:** one CSV per table.
- **`-HtmlPath`:** the management group hierarchy as a tree, with each
  level's compliance. The tables are grouped under Overview, Compliance,
  Exemptions and Definitions.
- **`-PdfPath`:** a PDF of the same content.

`Get-AACPolicyState` (every resource's state) and `Get-AACAssignedPolicy`
(every assignment's parameters) stay as they are.

## Assigned policies and their parameters

`Get-AACPolicyState` is about compliance; `Get-AACAssignedPolicy` is about
what is assigned. It reads the assignments, the definitions and initiatives
they assign and the initiatives' member policies from Azure Resource Manager's
REST APIs (Reader, no Az modules) - Azure Resource Graph only for what those
couldn't read, and the report says when it was - and flattens them to one row
per assignment and parameter. That is a call per subscription, management group
and definition, so naming a scope is quicker in a large tenant:

```powershell
Get-AACAssignedPolicy                                                          # everything you can see
Get-AACAssignedPolicy -SubscriptionId '00000000-0000-0000-0000-000000000000'    # what applies to one subscription
Get-AACAssignedPolicy -ManagementGroupId 'mg-landingzones' -HtmlPath .\AssignedPolicy.html -PdfPath .\AssignedPolicy.pdf
Get-AACAssignedPolicy -NoDisplay | Where-Object ValueSource -EQ 'Assigned'      # the parameters set on the assignment
```

`-HtmlPath` and `-PdfPath` write one report, with tabs in HTML and a bookmarked
chapter for each tab in the PDF: Summary, Assignments, Policies in force,
Resource types (what is assigned per type: how many policies block, audit,
change or only report, and which) and Parameters.

| Column                                                                     | What it is                                                                                                                                                                                                                                                                                                                                                                                                           |
| -------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `DefaultValue`, `AssignedValue`, `EffectiveValue`                          | The definition's default, the assignment's value, and the one that applies (assigned, else default). Lists are joined with `, `, objects written as compact JSON                                                                                                                                                                                                                                                     |
| `ValueSource`                                                              | `Assigned`, `Default` or `Not set`                                                                                                                                                                                                                                                                                                                                                                                   |
| `ResourceType`                                                             | What the policy targets: the types in its rule's `"field": "type"` conditions, with `[parameters()]` resolved to the effective values; else the types of the aliases it reads; else `All except ...` (a rule that only leaves types out, such as _Allowed resource types_) or `All`. For an initiative, the types of the member policies that use the row's parameter (`All` when one of them applies to every type) |
| `ScopeType`, `ScopeName`, `Inherited`                                      | Where it is assigned. With `-SubscriptionId` or `-ManagementGroupId`, assignments inherited from the management groups above are included and marked `Inherited`                                                                                                                                                                                                                                                     |
| `DefinitionType`, `PolicyType`, `Category`, `EnforcementMode`, `NotScopes` | Policy or initiative, built-in or custom, its category, whether it is enforced, and the scopes left out                                                                                                                                                                                                                                                                                                              |

A policy without parameters is one row with no parameter, so every
assignment is listed. The console view shows the assignments by scope, the
resource types with the most assignments, and each assignment's parameters
as a tree (assigned values in green, defaults in grey).

## The policy that applies to a resource

The commands above start from the assignment. `Show-AACEffectivePolicy`
starts from the resource and answers the question admins and architects
actually ask: *what applies to this, what does it do to it, and why?*

```powershell
Show-AACEffectivePolicy -ResourceId $storageId                                 # one resource (or pipe resources in)
Show-AACEffectivePolicy -SubscriptionId $sub -ResourceGroupName 'rg-orders' -HtmlPath .\orders-policy.html
Show-AACEffectivePolicy -ResourceId $vmId -Impact Blocks, 'Blocks delete'       # only what refuses a change or a delete
Show-AACEffectivePolicy -ResourceId $storageId -IncludeNotApplicable            # also what's on the path but doesn't target it, and why

# Before deploying: what would Azure Policy do to a new storage account there?
Show-AACEffectivePolicy -Scope "/subscriptions/$sub/resourceGroups/rg-new" -ResourceType 'Microsoft.Storage/storageAccounts' `
    -Location 'westeurope' -Sku 'Standard_LRS' -Tag @{ CostCenter = 'cc-01' }
```

Every assignment on the resource's path (its management groups, root first,
then its subscription, resource group and the resource itself) is expanded.
Each initiative becomes its member policies. Each policy gets one verdict:

| Verdict        | Meaning                                                                                                                       |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `Applies`      | The policy evaluates the resource                                                                                             |
| `Exempt`       | An exemption covers it: Waiver or Mitigated, for every policy in the assignment or only some, until a date. An expired exemption is shown but no longer exempts |
| `Excluded`     | The assignment's `notScopes` leave it out                                                                                     |
| `Not selected` | The assignment's resource selectors (location, type) leave it out                                                            |
| `Not targeted` | The rule is about other resource types, or a data-plane policy (`Microsoft.Kubernetes.Data`, ...) is for another kind of resource. Shown with `-IncludeNotApplicable` |

**Impact** says what the effect does to the resource. The effect is worked
out from the parameters, then the initiative, then the assignment, then its
overrides. `Blocks` (deny), `Blocks delete` (denyAction), `Changes`
(modify, append), `Deploys` (deployIfNotExists), `Audits`, `Manual` and
`Disabled` are the effects themselves. `Reports only` means the assignment
isn't enforced (`DoNotEnforce`), so a deny, change or deploy only reports.

For an existing resource you also get Azure's compliance state and when it
was last evaluated. A non-compliant resource also says why: the field, the
value the policy expects and the value it found, read from Policy
Insights for up to 25 resources. Skip that read with `-SkipReason`.

For a planned resource, Azure Policy itself is asked: `checkPolicyRestrictions`,
with audits included. It says what would refuse the resource, audit it or
change it, and which values are allowed: locations, types and SKUs, plus
required tags. `deployIfNotExists`, `auditIfNotExists` and `denyAction` act
on what exists after the deployment, so they show as `After deployment`.

The HTML report has these tabs:
- **In force**: worst impact first.
- **Non-compliant**: each evaluation with its reason.
- **Allowed values**: planned resources only.
- **Exemptions**: with the dates they end.
- **Left out**: each policy with the reason.
- **Assignment chain**: scope, enforcement, managed identity, exclusions, resource selectors and definition version.
- **Resources.**
- **Findings**, as follows:
  - **High:** a non-compliant resource that a deny will refuse at its next deployment.
  - **High:** a remediation that can't run because the assignment has no managed identity.
  - **Medium:** remediation that hasn't run yet.
  - **Medium:** an exemption that ends within 30 days.
  - **Low:** an expired exemption.
  - **Info:** policies with no result yet.

## Testing a template against Azure Policy

`Test-AACPolicyDeployment` checks an ARM template or a Bicep file before it
is deployed, which makes it useful in a pull request or as a pipeline gate.

```powershell
Test-AACPolicyDeployment -TemplatePath .\main.bicep -SubscriptionId $sub -ResourceGroupName 'rg-orders'
Test-AACPolicyDeployment -TemplatePath .\main.json -ParameterPath .\prod.parameters.json -SubscriptionId $sub `
    -ResourceGroupName 'rg-orders' -FailOn Deny -HtmlPath .\policy-gate.html
```

The template's resources are worked out offline: parameters, variables,
most template functions, Bicep modules (followed into other resource groups)
and child resources. Each resource body is then sent to Azure Policy. The
outcomes:

| Outcome       | Meaning                                                        |
| ------------- | -------------------------------------------------------------- |
| `Blocked`     | A deny would refuse it. You get the field, the expected and found values, and the values allowed |
| `Audited`     | It deploys, but is reported non-compliant                      |
| `Changed`     | Modify or append would change it as it deploys                 |
| `Passes`      | Nothing refuses, audits or changes it                          |
| `Not checked` | Azure couldn't be asked                                        |

Some values can only be known at deployment, such as `uniqueString()`,
`reference()` or a parameter with no value. They are left out of the body,
never guessed, and named on the resource, because a policy that reads them
can't be judged. A `.bicep` file is compiled with the Bicep CLI when
`bicep` is on the PATH. A resource group that doesn't exist yet is checked
at the subscription; give `-Location` for anything that uses
`resourceGroup().location`. `-FailOn Deny` (or `Audit`) ends with an error
after the report is written, which fails the pipeline.

## Which policy command?

| You want to know                                                              | Command                                       |
| ----------------------------------------------------------------------------- | --------------------------------------------- |
| What applies to this resource, what it does to it, and why                   | `Show-AACEffectivePolicy -ResourceId`         |
| What Azure Policy would do to a resource I'm about to create                  | `Show-AACEffectivePolicy -Scope -ResourceType` |
| Whether my template or Bicep file will deploy                                 | `Test-AACPolicyDeployment`                    |
| How compliant a scope is, per resource and policy                             | `Get-AACPolicyState`                          |
| What is assigned, with which parameter values                                 | `Get-AACAssignedPolicy`                       |
| Whether our policy programme is healthy (identities, exemptions, hygiene)     | `Invoke-AACPolicyAssessment`                  |
| Whether remediation tasks are running                                         | `Get-AACPolicyRemediation`                    |
| How we stand against CIS, PCI, ISO or the Microsoft cloud security benchmark  | `Get-AACComplianceGap`                        |
| How our management groups compare with the Azure Landing Zones reference      | `Test-AACAlzPolicy`                           |
| Who changed policy recently                                                   | `Get-AACGovernanceChange`                     |
| What policy denied in the activity log                                        | `Get-AACResourceError`                        |
