# Terraform export

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Export-AACTerraform`](../Export-AACTerraform.md)

`Export-AACTerraform` turns resources you already have into Terraform,
through Azure's own [Export for Terraform API](https://learn.microsoft.com/rest/api/terraform/terraform/export-terraform).
The export is a long-running operation: the command submits it, polls it as
Azure asks (`Retry-After`), shows its progress, and writes a folder you can
run straight away.

```powershell
Export-AACTerraform -ResourceGroupName rg-app -Path .\terraform\rg-app
Export-AACTerraform -ResourceGroupName rg-platform -BatchSize 50 -Path .\terraform\platform   # a large one, in batches at once
Export-AACTerraform -Resume -Path .\terraform\platform                                       # collect one still running
Export-AACTerraform -ResourceGroupName rg-hub, rg-spoke -FallbackToAzApi -Plan -Path .\terraform\network
Export-AACTerraform -Query 'type =~ "microsoft.keyvault/vaults"' -Include RoleAssignment, Lock -Path .\terraform\vaults
Get-AACUnusedResource -NoDisplay | Export-AACTerraform -Path .\terraform\unused   # piped by ID
```

The folder:

| File | What |
|---|---|
| `terraform.tf` | The providers the configuration needs |
| `providers.tf` | The provider blocks, with the subscription ID |
| `main.tf` | The resources |
| `azapi.tf` | With `-FallbackToAzApi`: what azurerm couldn't export, as azapi resources |
| `import.tf` | Import blocks: `terraform plan` brings the existing resources under Terraform, with no `terraform import` to run |
| `export.json` | What was asked, what was skipped and why |
| `plan.json` | With `-Plan`: the plan, for `Get-AACTerraformPlan` |

- **Large exports, faster.** The export runs on Azure's side and its time
  grows with the number of resources - a large resource group takes
  minutes. The command counts the resources first and says when an export
  is large (and which types are often left out with `-ExcludeType`).
  `-BatchSize 50` splits it into exports of 50 resources that run at the
  same time (`-ThrottleLimit`, 8 at once by default) and merges them into
  one folder: each batch has names of its own (`res-b1-0`), and a resource
  two batches both return is kept once. Several subscriptions are exported
  at the same time too.
- **Progress you can read.** Each export shows its status, how long it has
  run and how many batches are done - Azure gives no percentage.
- **Stop and come back.** The operations are saved in `export.json` as soon
  as Azure accepts them. After Ctrl+C, or when `-TimeoutMinutes` (30) runs
  out, the export goes on in Azure: `-Resume -Path <folder>` collects it
  without exporting again.
- **Three ways to choose.** Resource groups (several in one subscription
  are exported together, with their child resources, so their names can't
  clash), resource IDs (or anything piped with an `Id` or `ResourceId`), or
  a Resource Graph where-clause. Several subscriptions get a folder each.
- **Nothing silently dropped.** A type the azurerm provider doesn't support
  yet is listed as Skipped; `-FallbackToAzApi` exports those again with the
  azapi provider, which covers every Azure resource type, and merges both
  into one module.
- **Proved with `-Plan`.** It runs `terraform init`, `validate` and `plan`
  in the folder and reads the plan as `Get-AACTerraformPlan` does. A
  faithful export plans only imports; anything else is what the export
  didn't capture, listed by address. Terraform signs in on its own (`az
  login`, or `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET` and `ARM_TENANT_ID`).
- **Safe.** The export reads Azure and changes nothing there. Sensitive
  values are masked unless `-IncludeSensitive`; Terraform files already in
  the folder aren't overwritten without `-Force`.
- **The resource provider.** The API needs `Microsoft.AzureTerraform`
  registered on the subscription. When it isn't, the command says so;
  `-RegisterProvider` registers it (it asks first, and honours `-WhatIf`).
- `-Provider azapi`, `-Include` (the resource group, role assignments,
  locks, diagnostic settings, Azure-managed resources), `-Recurse`,
  `-Exclude`, `-ExcludeType`, `-NamePrefix` and `-Compact` map to the API's
  options. The API is in preview (`2026-09-01-preview`); `-ApiVersion`
  picks another.
