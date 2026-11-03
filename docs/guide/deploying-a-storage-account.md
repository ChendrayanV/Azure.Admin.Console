# Deploying a storage account

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Deploy-AACStorageAccount`](../Deploy-AACStorageAccount.md)

`Deploy-AACStorageAccount` creates or updates a storage account and what's in
it - idempotently, like a Bicep or Terraform deployment, but with the Azure REST
APIs directly: no ARM, Bicep or Terraform template. It is the module's only
command that writes; everything else reads.

```powershell
# The plan and the gates - nothing is written
Deploy-AACStorageAccount -SubscriptionId <subscription> -ResourceGroupName rg-data -ConfigurationPath .\Examples\storage-account.psd1 -WhatIf

# Plan, gates, ask, apply, verify. Run it again: "No changes", nothing written.
Deploy-AACStorageAccount -SubscriptionId <subscription> -ResourceGroupName rg-data -ConfigurationPath .\Examples\storage-account.psd1

# Quick: a name, two containers and a file - AVM's defaults for the rest
Deploy-AACStorageAccount -SubscriptionId <subscription> -ResourceGroupName rg-data -Name stcontosoweb -Container web, logs -Blob @{ container = 'web'; path = '.\index.html'; contentType = 'text/html' } -Setting @{ networkAcls = @{ ipRules = @('203.0.113.10') } }

# A failing PSRule rule blocks: deploy with the suggested fixes instead (checked again)
Deploy-AACStorageAccount -SubscriptionId <subscription> -ResourceGroupName rg-data -Name stcontosoweb -Container web -UseSuggestedFix -WhatIf

# In a pipeline: apply without asking unless a gate blocks, keep the plan
Deploy-AACStorageAccount -SubscriptionId <subscription> -ResourceGroupName rg-data -ConfigurationPath .\Examples\storage-account.parameters.json -Force -PlanPath .\plan.json
```

**The configuration** uses the [Azure Verified Module](https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/storage/storage-account)'s
parameter names, in a `.psd1` or `.json` file - an AVM parameters file works as
it is - and/or as parameters (`-Name`, `-Container`, `-FileShare`, `-Queue`,
`-Table`, `-Blob`, `-Tag`, `-Setting` for the rest). AVM's defaults apply, and,
as with Bicep, are enforced on every run: StorageV2, Standard_GRS, Hot, TLS 1.2,
HTTPS only, no public blob access, infrastructure encryption, network rules
that deny by default (with the AzureServices bypass), blob and container soft
delete. AVM parameters it doesn't support yet (customer-managed keys,
identities, local users, object replication...) are refused by name rather
than ignored. See `Examples\`.

**How it stays idempotent without a template:**

| Step   | What happens                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Plan   | Everything that should exist is read (GET) and compared property by property, only on what the configuration manages. Azure's own fields (a rule's state, a category's retention policy) and what it leaves out (false values) aren't changes. Each resource is Create, Update, No change, **Replace** (a property Azure can't change in place: location, kind, hierarchical namespace, infrastructure encryption, zonal or Premium redundancy) or **Drift** (containers, shares, queues, tables that exist but aren't configured - left alone, or deleted with `-Prune`) |
| Gates  | **Name** (`checkNameAvailability`); **Azure Policy**: the assignments that apply to storage in the resource group, and Azure Policy's verdict on the exact body of every write (`checkPolicyRestrictions`) - Deny blocks, Audit is reported, Modify and Append changes are shown; **PSRule for Azure** - and the module's naming and tag rules - on the account as it will be, with its services and containers (shift left)                                                                                                                                              |
| Decide | Blocked stops before anything is written: a name taken, an immutable change, a policy Deny, **a PSRule rule that fails** (or PSRule not running), `-FailOn Audit`/`Drift`. Otherwise it asks (`-Force` or `-Confirm:$false` in a pipeline); `-WhatIf` stops after the plan                                                                                                                                                                                                                                                                                                |
| Apply  | In dependency order - account, services, containers and the rest, private endpoints, diagnostic settings, role assignments, the lock last, blobs. PUT to create; PATCH with only what changed; long-running operations followed. Role assignments are named from scope, principal and role (like Bicep's `guid()`), and an existing one is adopted, so none is duplicated. Blobs upload only when their MD5 differs                                                                                                                                                       |
| Verify | Everything read and compared again: it must now plan no changes. What Azure changed by itself (a Modify policy) is reported                                                                                                                                                                                                                                                                                                                                                                                                                                               |

**A failing PSRule rule blocks the deployment, and says how to fix it.** Each
failing rule comes with its fix: the setting and value in the configuration
(`allowSharedKeyAccess = $false`, `networkAcls.defaultAction = 'Deny'`, a GRS or
GZRS SKU, soft delete, a container's `publicAccess = 'None'`...) - or, when no
setting can fix it, what to do (Defender for Storage on the subscription, tags
only you can give, a name that can't change). The view gathers every setting
into a configuration snippet to paste; `-UseSuggestedFix` deploys with them -
the plan and every gate are checked again on the fixed configuration. A rule
that doesn't apply to an account is excluded on purpose with `-ExcludeRule`;
`-SkipPSRule` deploys without checking. With AVM's defaults alone, two rules
fail - `Azure.Storage.LocalAuth` (AVM leaves shared key access on) and
`Azure.Resource.UseTags` - so a first deployment needs `allowSharedKeyAccess = $false`
and tags.

It isn't a transaction: the first failure stops the run, what came before
stays, and running again carries on from there. Needs Contributor (or Storage
Account Contributor) on the resource group, which must exist; User Access
Administrator for role assignments; Storage Blob Data Contributor and network
access to the account for blob uploads.
