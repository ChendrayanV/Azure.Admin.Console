---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Show-AACEffectivePolicy.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Show-AACEffectivePolicy
---

# Show-AACEffectivePolicy

## SYNOPSIS

Shows the Azure Policy that applies to a resource - one that exists, or one you are about to deploy - and what each policy does to it: blocks, audits, changes or deploys, where it is assigned, its compliance state and why, and what exempts or leaves it out.

## SYNTAX

### Resource (Default)

```
Show-AACEffectivePolicy -ResourceId <string[]> [-Impact <string[]>] [-IncludeNotApplicable]
 [-SkipReason] [-View <string>] [-CsvPath <string>] [-HtmlPath <string>] [-PdfPath <string>]
 [-Title <string>] [-PassThru] [-NoDisplay] [-NoPaging]
```

### Scope

```
Show-AACEffectivePolicy -SubscriptionId <string> [-ResourceGroupName <string[]>]
 [-ResourceType <string[]>] [-Impact <string[]>] [-IncludeNotApplicable] [-SkipReason]
 [-MaxResource <int>] [-View <string>] [-CsvPath <string>] [-HtmlPath <string>] [-PdfPath <string>]
 [-Title <string>] [-PassThru] [-NoDisplay] [-NoPaging]
```

### Planned

```
Show-AACEffectivePolicy -ResourceType <string[]> -Scope <string> [-Location <string>]
 [-Name <string>] [-Tag <hashtable>] [-Sku <string>] [-Kind <string>] [-Property <hashtable>]
 [-Impact <string[]>] [-IncludeNotApplicable] [-SkipReason] [-View <string>] [-CsvPath <string>]
 [-HtmlPath <string>] [-PdfPath <string>] [-Title <string>] [-PassThru] [-NoDisplay] [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Read-only. Starts from the resource, not the assignment: every
assignment on its path - its management groups, subscription,
resource group and the resource itself - and, for an initiative,
each member policy, with one verdict:

```text
  Applies        the policy evaluates the resource
  Exempt         an exemption covers it (Waiver or Mitigated, all
                 policies or some, until when)
  Excluded       the assignment's notScopes leave it out
  Not selected   the assignment's resource selectors leave it out
  Not targeted   the rule is about other resource types (shown with
                 -IncludeNotApplicable)
```

For each policy that applies: the effect in force - parameters
resolved through the initiative and the assignment, then its
overrides - and what it means here (Impact): Blocks (deny), Blocks
delete (denyAction), Audits, Changes (modify, append), Deploys
(deployIfNotExists), Manual, Disabled, or Reports only when the
assignment isn't enforced. Also its non-compliance message, the
assignment's managed identity (for remediation), definition version,
regulatory controls, mode and parameters.

An existing resource: Azure's compliance state, when it was last
evaluated and - for a non-compliant one - why: the field, the value
the policy expects and the value it found (Policy Insights).

A planned resource (-Scope with -ResourceType): Azure Policy is
asked what it would do (checkPolicyRestrictions) - what would refuse
it, audit it or change it, and the values allowed: locations, SKUs,
types, required tags. DeployIfNotExists and AuditIfNotExists act
after a deployment, so they are listed as such.

Findings: non-compliant resources a deny will refuse at their next
deployment, remediation that can't run (no managed identity) or
hasn't, exemptions ending within 30 days or expired, policies with
no result yet.

Needs Reader on the resources and their scopes; assignments,
definitions and exemptions are read tenant-wide from Resource Graph,
so those inherited from management groups you can read are included.

## EXAMPLES

### Example 1

```powershell
Connect-AAC
Show-AACEffectivePolicy -ResourceId $storageId
```

Every policy that applies to one storage account: what blocks, audits or changes it, where it is assigned, whether it complies and why not.

### Example 2

```powershell
Show-AACEffectivePolicy -SubscriptionId $sub -ResourceGroupName 'rg-orders' -HtmlPath .\orders-policy.html
A resource group's resources, with a tabbed report: in force, non-compliant, exemptions, left out, the assignment chain.
```

### Example 3

```powershell
Show-AACEffectivePolicy -Scope "/subscriptions/$sub/resourceGroups/rg-new" -ResourceType 'Microsoft.Storage/storageAccounts' -Location 'westeurope' -Sku 'Standard_LRS' -Tag @{ CostCenter = 'cc-01' }
```

Before deploying: what Azure Policy would refuse, audit, change or deploy for a new storage account there, and the values it allows.

### Example 4

```powershell
Show-AACEffectivePolicy -ResourceId $vmId -Impact Blocks, 'Blocks delete' -NoDisplay
```

Only the policies that would refuse a change to the VM, or its deletion.

## PARAMETERS

### -CsvPath

Write the -View rows to this CSV file.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -HtmlPath

Write an interactive HTML report.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Impact

Only policies with these impacts: Blocks, Blocks delete, Audits,
Changes, Deploys, Manual, Reports only, Disabled, Exempt.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -IncludeNotApplicable

Also list the policies on the path that don't target the resource,
with the reason.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Kind

The planned resource's kind.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Planned
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Location

The planned resource's location.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Planned
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -MaxResource

With -SubscriptionId: the most resources to show (500 by default).

```yaml
Type: System.Int32
DefaultValue: 500
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Scope
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Name

The planned resource's name, for naming policies.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Planned
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -NoDisplay

Return the rows without showing the view.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -NoPaging

Show the whole view at once.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -PassThru

Show the view and also return the rows.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -PdfPath

Write a PDF report.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Property

More of the planned resource's body, as Azure Resource Manager takes
it, e.g. @{ properties = @{ minimumTlsVersion = 'TLS1_0' } }.

```yaml
Type: System.Collections.Hashtable
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Planned
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ResourceGroupName

With -SubscriptionId: only these resource groups.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Scope
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ResourceId

The resources (also resource groups or subscriptions) to show. Takes
ResourceId or Id from the pipeline.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
Aliases:
- Id
ParameterSets:
- Name: Resource
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: true
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ResourceType

With -SubscriptionId: only these types. With -Scope: the type of the
planned resource, e.g. Microsoft.Storage/storageAccounts.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Planned
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: Scope
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Scope

A planned resource: the subscription or resource group ID it will be
deployed to (the resource group doesn't have to exist yet).

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Planned
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SkipReason

Don't read why non-compliant resources are non-compliant (one Policy
Insights call per resource).

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Sku

The planned resource's SKU name (sku.name).

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Planned
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SubscriptionId

Show every resource in this subscription (with -ResourceGroupName and
-ResourceType to narrow it) - at most -MaxResource.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Scope
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Tag

The planned resource's tags.

```yaml
Type: System.Collections.Hashtable
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Planned
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Title

The reports' title.

```yaml
Type: System.String
DefaultValue: "'Effective Azure Policy'"
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -View

Policy, Resource, Assignment, Exemption, Restriction or Finding: what
is returned and written to -CsvPath.

```yaml
Type: System.String
DefaultValue: "'Policy'"
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.EffectivePolicy, AAC.EffectivePolicyResource, AAC.EffectivePolicyAssignment, AAC.EffectivePolicyExemption, AAC.EffectivePolicyRestriction or AAC.EffectivePolicyFinding, by -View (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Show-AACEffectivePolicy.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
