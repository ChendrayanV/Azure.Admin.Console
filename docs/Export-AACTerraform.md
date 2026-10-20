---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Export-AACTerraform.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Export-AACTerraform
---

# Export-AACTerraform

## SYNOPSIS

Exports existing Azure resources as Terraform - a folder ready for terraform init and plan, with the import blocks - through the Azure Export for Terraform API, and shows what couldn't be exported.

## SYNTAX

### ResourceGroup (Default)

```
Export-AACTerraform -ResourceGroupName <string[]> -Path <string> [-SubscriptionId <string[]>]
 [-Provider <string>] [-Include <string[]>] [-Recurse] [-Exclude <string[]>]
 [-ExcludeType <string[]>] [-NamePrefix <string>] [-Compact] [-IncludeSensitive] [-FallbackToAzApi]
 [-BatchSize <int>] [-ThrottleLimit <int>] [-Plan] [-TerraformPath <string>] [-RegisterProvider]
 [-Force] [-TimeoutMinutes <int>] [-ApiVersion <string>] [-CsvPath <string>] [-HtmlPath <string>]
 [-PdfPath <string>] [-Title <string>] [-PassThru] [-NoDisplay] [-NoPaging] [-WhatIf] [-Confirm]
```

### ResourceId

```
Export-AACTerraform -ResourceId <string[]> -Path <string> [-Provider <string>] [-Include <string[]>]
 [-Recurse] [-Exclude <string[]>] [-ExcludeType <string[]>] [-NamePrefix <string>] [-Compact]
 [-IncludeSensitive] [-FallbackToAzApi] [-BatchSize <int>] [-ThrottleLimit <int>] [-Plan]
 [-TerraformPath <string>] [-RegisterProvider] [-Force] [-TimeoutMinutes <int>]
 [-ApiVersion <string>] [-CsvPath <string>] [-HtmlPath <string>] [-PdfPath <string>]
 [-Title <string>] [-PassThru] [-NoDisplay] [-NoPaging] [-WhatIf] [-Confirm]
```

### Query

```
Export-AACTerraform -Query <string> -Path <string> [-Table <string>] [-SubscriptionId <string[]>]
 [-Provider <string>] [-Include <string[]>] [-Recurse] [-Exclude <string[]>]
 [-ExcludeType <string[]>] [-NamePrefix <string>] [-Compact] [-IncludeSensitive] [-FallbackToAzApi]
 [-BatchSize <int>] [-ThrottleLimit <int>] [-Plan] [-TerraformPath <string>] [-RegisterProvider]
 [-Force] [-TimeoutMinutes <int>] [-ApiVersion <string>] [-CsvPath <string>] [-HtmlPath <string>]
 [-PdfPath <string>] [-Title <string>] [-PassThru] [-NoDisplay] [-NoPaging] [-WhatIf] [-Confirm]
```

### Resume

```
Export-AACTerraform -Resume -Path <string> [-Provider <string>] [-Include <string[]>] [-Recurse]
 [-Exclude <string[]>] [-ExcludeType <string[]>] [-NamePrefix <string>] [-Compact]
 [-IncludeSensitive] [-FallbackToAzApi] [-BatchSize <int>] [-ThrottleLimit <int>] [-Plan]
 [-TerraformPath <string>] [-RegisterProvider] [-Force] [-TimeoutMinutes <int>]
 [-ApiVersion <string>] [-CsvPath <string>] [-HtmlPath <string>] [-PdfPath <string>]
 [-Title <string>] [-PassThru] [-NoDisplay] [-NoPaging] [-WhatIf] [-Confirm]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Asks Azure to write the Terraform configuration of what you choose -
a resource group, resources by ID (or piped from any command that
returns resources), or a Resource Graph query - and waits for it.

The export is a long-running operation that Azure does on its side,
and its time grows with the number of resources. So the command:

```text
  - counts the resources first (Resource Graph), and says when an
    export is large and how to make it faster
  - with -BatchSize, splits it into exports of that many resources
    that run at the same time (-ThrottleLimit at once), and merges
    them into one folder
  - shows each export as it runs: its status, how long it has run,
    and how many batches are done - not a percentage Azure doesn't
    give
  - saves the operations in export.json as soon as Azure accepts
    them: after Ctrl+C or -TimeoutMinutes, -Resume collects the
    result without exporting again
```

The folder (-Path) gets:

```text
  terraform.tf   the providers the configuration needs
  providers.tf   the provider blocks, with the subscription ID
  main.tf        the resources
  azapi.tf       with -FallbackToAzApi: what azurerm couldn't
                 export, as azapi resources
  import.tf      import blocks, so terraform plan brings the
                 existing resources under Terraform - no
                 terraform import commands to run
  export.json    what was asked, the operations, what was skipped
                 and why
```

Several subscriptions get a folder each, under -Path, exported at
the same time.

Several resource groups of one subscription are exported together,
in one query (with their child resources), so they share one
folder and their names can't clash. With -BatchSize, each batch
gets names of its own (res-b1-0, res-b2-0...); a resource two
batches both return is kept once. Resources in different batches
refer to each other by Azure ID rather than by Terraform address.

What couldn't be exported is listed, never silently dropped: a
resource type the azurerm provider doesn't support yet is Skipped -
-FallbackToAzApi exports those again with the azapi provider, which
covers every Azure resource type. Sensitive values are masked
unless -IncludeSensitive.

-Plan proves the export: it runs terraform init, validate and plan
in each folder and reads the plan (as Get-AACTerraformPlan does).
A faithful export plans only imports; anything else - an attribute
Terraform would change - is what the export didn't capture. It
needs the terraform CLI, signed in its own way (az login, or
ARM_CLIENT_ID, ARM_CLIENT_SECRET and ARM_TENANT_ID): Terraform
doesn't use the Connect-AAC sign-in.

The export reads Azure; it changes nothing there. It needs Reader
on what is exported, and the Microsoft.AzureTerraform resource
provider registered on the subscription - -RegisterProvider
registers it (that is a change, so it asks first and honours
-WhatIf; registering needs a role such as Contributor).

The API is in preview (api-version 2026-09-01-preview); -ApiVersion
picks another.

## EXAMPLES

### Example 1

```powershell
Export-AACTerraform -ResourceGroupName rg-app -Path .\terraform\rg-app
```

The resource group as Terraform, with import blocks.

### Example 2

```powershell
Export-AACTerraform -ResourceGroupName rg-platform -BatchSize 50 -Path .\terraform\platform
A large resource group, split into exports of 50 resources that run at the same time.
```

### Example 3

```powershell
Export-AACTerraform -Resume -Path .\terraform\platform
```

Collects the export that was still running when the command was stopped.

### Example 4

```powershell
Export-AACTerraform -ResourceGroupName rg-hub, rg-spoke -FallbackToAzApi -Plan -Path .\terraform\network
```

Two resource groups in one folder, azapi for what azurerm can't do, and terraform plan to prove it.

### Example 5

```powershell
Export-AACTerraform -Query 'type =~ "microsoft.keyvault/vaults"' -SubscriptionId $sub -Include RoleAssignment, Lock -Path .\terraform\vaults
```

Every key vault of a subscription, with its role assignments and locks.

### Example 6

```powershell
Get-AACUnusedResource -NoDisplay | Export-AACTerraform -Path .\terraform\unused
```

The unused resources as Terraform, piped by ID - a record of them before they are cleaned up.

### Example 7

```powershell
Export-AACTerraform -ResourceGroupName rg-app -Path .\tf -RegisterProvider -WhatIf
```

Shows where the resource provider would be registered, without registering it.

## PARAMETERS

### -ApiVersion

The Azure Export for Terraform API version.

```yaml
Type: System.String
DefaultValue: "'2026-09-01-preview'"
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

### -BatchSize

Split an export of more resources than this into exports of this
many, run at the same time and merged into one folder - the way to
make a large export faster. 0 (the default): one export.

```yaml
Type: System.Int32
DefaultValue: 0
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

### -Compact

Leave out properties with empty values.

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

### -Confirm



```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases:
- cf
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

### -CsvPath

Write the resources - exported, skipped and errors - to this CSV file.

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

### -Exclude

Azure resource IDs to leave out - case-insensitive regular
expressions, such as '/subscriptions/.+/resourceGroups/rg-app/providers/Microsoft.Insights/.\*'.

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

### -ExcludeType

Terraform resource types to leave out, such as azurerm_network_watcher.

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

### -FallbackToAzApi

Export what the azurerm provider couldn't again, with the azapi
provider, into azapi.tf - so nothing is left out.

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

### -Force

Overwrite Terraform files already in the folder.

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

### -Include

Also export: ResourceGroup (the resource group itself, with
-ResourceId or -Query), RoleAssignment, Lock, DiagnosticSetting (the
extension resources on what is exported), ManagedResource (resources
Azure manages for you, normally left out). Each makes the export
larger, and slower.

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

### -IncludeSensitive

Don't mask sensitive values. They are then in the .tf files in clear
text: keep the folder out of source control.

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

### -NamePrefix

The prefix of the Terraform resource names (res- if not given:
res-0, res-1...).

```yaml
Type: System.String
DefaultValue: "'res-'"
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

### -NoDisplay

Return an object per folder without showing the view.

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

Show the view and also return an object per folder.

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

### -Path

The folder to write. Created if it doesn't exist; Terraform files
already in it are not overwritten without -Force.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: true
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

### -Plan

Run terraform init, validate and plan in each folder, and show what
Terraform would change beyond the imports.

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

### -Provider

azurerm (the default) or azapi.

```yaml
Type: System.String
DefaultValue: "'azurerm'"
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

### -Query

A Resource Graph where-clause choosing the resources, such as
'type =~ "microsoft.network/virtualnetworks" and location =~ "uksouth"'.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Query
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Recurse

With -ResourceId or -Query: the child resources too (subnets of a
virtual network, databases of a server...).

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

### -RegisterProvider

Register the Microsoft.AzureTerraform resource provider on the
subscriptions where it isn't.

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

### -ResourceGroupName

The resource groups to export. Found by name in the subscriptions
you can see (or -SubscriptionId).

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: ResourceGroup
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ResourceId

The resources to export, by Azure resource ID - or piped: any object
with an Id or ResourceId (Export-AACResource, Get-AACUnusedResource,
Get-AACResourceHealth...), or the IDs as text.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
Aliases:
- Id
ParameterSets:
- Name: ResourceId
  Position: Named
  IsRequired: true
  ValueFromPipeline: true
  ValueFromPipelineByPropertyName: true
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Resume

Collect an export that was still running - after Ctrl+C or
-TimeoutMinutes - from the operations saved in -Path\export.json (or
in its subscription folders), without exporting again. -Plan and the
report parameters still apply; the rest is read from export.json.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Resume
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SubscriptionId

With -ResourceGroupName: where to look for them. With -Query: the
subscriptions to export from (every one you can see if not given).

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Query
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
- Name: ResourceGroup
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Table

With -Query: the Resource Graph table (Resources if not given).

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Query
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -TerraformPath

The terraform executable, if it isn't on PATH.

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

### -ThrottleLimit

How many exports run at the same time (8 if not given) - batches,
subscriptions and the azapi pass alike.

```yaml
Type: System.Int32
DefaultValue: 8
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

### -TimeoutMinutes

How long to wait for each export (30 if not given). One still
running then is left running: -Resume collects it.

```yaml
Type: System.Int32
DefaultValue: 30
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

### -Title

The reports' title.

```yaml
Type: System.String
DefaultValue: "'Terraform export'"
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

### -WhatIf



```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases:
- wi
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

### AAC.TerraformExport

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Export-AACTerraform.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
