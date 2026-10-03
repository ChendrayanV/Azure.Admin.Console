---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Deploy-AACStorageAccount.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Deploy-AACStorageAccount
---

# Deploy-AACStorageAccount

## SYNOPSIS

Creates or updates a storage account - and its containers, file shares, queues, tables, blobs and settings - idempotently, with the Azure REST APIs: plan, gates (Azure Policy and PSRule), then apply. No ARM, Bicep or Terraform template.

## SYNTAX

### __AllParameterSets

```
Deploy-AACStorageAccount [-SubscriptionId] <string> [-ResourceGroupName] <string>
 [[-ConfigurationPath] <string>] [[-Name] <string>] [[-Location] <string>] [[-SkuName] <string>]
 [[-Kind] <string>] [[-AccessTier] <string>] [[-Tag] <hashtable>] [[-Container] <Object[]>]
 [[-FileShare] <Object[]>] [[-Queue] <Object[]>] [[-Table] <string[]>] [[-Blob] <hashtable[]>]
 [[-Setting] <hashtable>] [[-FailOn] <string[]>] [[-Baseline] <string>] [[-ExcludeRule] <string[]>]
 [[-PlanPath] <string>] [[-ThrottleLimit] <int>] [-Prune] [-UseSuggestedFix] [-SkipPolicy]
 [-SkipPSRule] [-Force] [-PassThru] [-NoDisplay] [-WhatIf] [-Confirm]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Works like a Bicep or Terraform deployment, without a template:

```text
  1. Desired state   your configuration, with the Azure Verified
                     Module's parameter names and its defaults
                     (avm/res/storage/storage-account): StorageV2,
                     Standard_GRS, Hot, TLS 1.2, HTTPS only, no
                     public blob access, infrastructure encryption,
                     network rules denying by default with the
                     AzureServices bypass, blob and container soft
                     delete - enforced on every run, as Bicep would.
  2. Plan            what exists is read (GET) and compared property
                     by property: Create, Update, No change - or
                     Replace, when Azure can't change a property in
                     place (location, kind, hierarchical namespace,
                     infrastructure encryption...). Containers,
                     shares, queues and tables that exist but aren't
                     configured are Drift (left alone) - or deleted
                     with -Prune.
  3. Gates           the name (checkNameAvailability); the policy
                     assignments that apply to storage in the
                     resource group; Azure Policy's verdict on the
                     exact body of every write (checkPolicyRestrictions):
                     Deny blocks, Audit is reported, Modify and Append
                     changes are shown; PSRule for Azure - and the
                     module's naming and tag rules - on the account as
                     it will be (shift left): what breaks your
                     standards.
  4. Decide          blocked stops here, before anything is written:
                     a name taken, an immutable change, a policy
                     Deny, a PSRule rule that fails (or PSRule not
                     running), -FailOn. Each failing PSRule rule comes
                     with its fix - the setting and value, or what to
                     do - and a configuration snippet with all of
                     them; -UseSuggestedFix deploys with those
                     settings (and checks every gate again). A rule
                     that doesn't apply is excluded on purpose with
                     -ExcludeRule. Otherwise you are asked before
                     anything is written (-Force, or -Confirm:$false,
                     for pipelines); -WhatIf stops after the plan.
  5. Apply           in dependency order, PUT to create, PATCH with
                     only what changed to update (long-running
                     operations followed); role assignments named from
                     scope, principal and role, so they are found
                     again; blobs uploaded only when their MD5 differs.
                     Not a transaction: the first failure stops, and
                     running again carries on.
  6. Verify          everything read and compared again: the plan
                     must now be "no changes". What Azure changed by
                     itself (a Modify policy) is reported.
```

Running the same configuration again plans no changes and writes
nothing.

The configuration: -ConfigurationPath (.psd1, or .json - including an
AVM parameters file), and/or parameters, which win over the file:
-Name, -Location, -SkuName, -Kind, -AccessTier, -Tag, -Container,
-FileShare, -Queue, -Table, -Blob, and -Setting for any other AVM
parameter. Supported AVM parameters: name, location, kind, skuName,
accessTier, tags, allowBlobPublicAccess, allowSharedKeyAccess,
allowCrossTenantReplication, defaultToOAuthAuthentication,
minimumTlsVersion, supportsHttpsTrafficOnly, publicNetworkAccess,
networkAcls, requireInfrastructureEncryption, largeFileSharesState,
enableHierarchicalNamespace, enableNfsV3, enableSftp,
isLocalUserEnabled, allowedCopyScope, dnsEndpointType, blobServices
(with containers, their roleAssignments, and diagnosticSettings),
fileServices (shares), queueServices (queues), tableServices
(tables), managementPolicyRules, privateEndpoints (with a private DNS
zone group), diagnosticSettings, roleAssignments, lock - and blobs
(files to upload: @{ container; path; name; contentType }). Others
are refused by name rather than ignored.

Needs Contributor (or Storage Account Contributor) on the resource
group, which must exist; User Access Administrator (or Owner) for
role assignments; Storage Blob Data Contributor for blob uploads.

## EXAMPLES

### Example 1

```powershell
Deploy-AACStorageAccount -SubscriptionId 00000000-0000-0000-0000-000000000000 -ResourceGroupName rg-data -Name stcontosodata -Container logs, exports -WhatIf
```

The plan and the gates for a new account with two containers - nothing is written.

### Example 2

```powershell
Deploy-AACStorageAccount -SubscriptionId 00000000-0000-0000-0000-000000000000 -ResourceGroupName rg-data -ConfigurationPath .\stcontosodata.json
```

Plan, gates, ask, apply, verify. Run it again: no changes.

### Example 3

```powershell
Deploy-AACStorageAccount -SubscriptionId 00000000-0000-0000-0000-000000000000 -ResourceGroupName rg-data -ConfigurationPath .\stcontosodata.psd1 -Force -PlanPath .\plan.json
```

In a pipeline: apply without asking unless a gate blocks, and keep the plan.

### Example 4

```powershell
Deploy-AACStorageAccount -SubscriptionId 00000000-0000-0000-0000-000000000000 -ResourceGroupName rg-data -Name stcontosodata -Container logs -UseSuggestedFix -WhatIf
```

Plan with the settings that fix the failing PSRule rules - shown, to copy into the configuration.

### Example 5

```powershell
Deploy-AACStorageAccount -SubscriptionId 00000000-0000-0000-0000-000000000000 -ResourceGroupName rg-data -Name stcontosodata -Container web -Blob @{ container = 'web'; path = '.\index.html'; contentType = 'text/html' } -Setting @{ networkAcls = @{ ipRules = @('203.0.113.10') } }
A container and a file in it, from this computer's IP.
```

## PARAMETERS

### -AccessTier

Hot (default), Cool, Cold or Premium.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 7
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Baseline

The PSRule baseline, e.g. Azure.GA_2024_09. All rules by default.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 16
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Blob

Files to upload: hashtables @{ container; path (the local file);
name (in the container; the file's name by default); contentType }.
Uploaded only when new or changed (MD5); up to 256 MB each.

```yaml
Type: System.Collections.Hashtable[]
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 13
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ConfigurationPath

A .psd1 or .json file with the configuration (AVM parameter names),
or an AVM / ARM parameters file.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 2
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

### -Container

Containers: names, or hashtables @{ name; publicAccess; metadata;
roleAssignments }.

```yaml
Type: System.Object[]
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 9
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ExcludeRule

PSRule rules to leave out, by name or wildcard - for rules that don't
apply to this account.

```yaml
Type: System.String[]
DefaultValue: '@()'
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 17
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -FailOn

Also stop for: Audit (an Azure Policy audit), Drift (items the
configuration doesn't name). A failing PSRule rule always stops.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 15
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -FileShare

File shares: names, or hashtables @{ name; shareQuota; accessTier;
enabledProtocols; metadata }.

```yaml
Type: System.Object[]
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 10
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Force

Apply without asking (for pipelines). Blocked plans still stop.

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

StorageV2 (default), BlockBlobStorage, FileStorage, BlobStorage, Storage.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 6
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Location

Its region. The resource group's by default (an existing account's own).

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 4
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Name

The account's name: 3-24 lower-case letters and digits, unique across Azure.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 3
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -NoDisplay

Return the deployment without showing the view.

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

Show the view and also return the deployment.

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

### -PlanPath

Write the plan - changes, request bodies, gates - to this JSON file.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 18
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Prune

Delete the containers, file shares, queues and tables the account has
but the configuration doesn't - with everything in them.

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

### -Queue

Queues: names, or hashtables @{ name; metadata }.

```yaml
Type: System.Object[]
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 11
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ResourceGroupName

The resource group the account is in (it must exist).

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 1
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Setting

Any other supported AVM parameter, as a hashtable:
@{ networkAcls = @{ ipRules = @('203.0.113.10') }; lock = @{ kind = 'CanNotDelete' } }.

```yaml
Type: System.Collections.Hashtable
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 14
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SkipPolicy

Don't check Azure Policy (the writes are still subject to it).

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

### -SkipPSRule

Don't run PSRule for Azure - deploy without checking your standards.

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

### -SkuName

Standard_LRS, Standard_GRS (default), Standard_RAGRS, Standard_ZRS,
Standard_GZRS, Standard_RAGZRS, Premium_LRS, Premium_ZRS.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 5
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SubscriptionId

The subscription of the resource group.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Table

Tables, by name.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 12
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Tag

The account's tags - all of them: tags not listed are removed.

```yaml
Type: System.Collections.Hashtable
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 8
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ThrottleLimit

How many reads run at once: 1 to 32, 12 by default.

```yaml
Type: System.Int32
DefaultValue: 12
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 19
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -UseSuggestedFix

Deploy with the settings that fix the failing PSRule rules (the
ones a setting can fix): the configuration is changed for this run,
then planned and checked again - every gate. The view shows the
changes, to put in the configuration file.

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

### AAC.StorageDeployment (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Deploy-AACStorageAccount.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
