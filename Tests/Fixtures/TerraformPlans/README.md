# Sample Terraform plans

Hand-written plans in Terraform's [JSON output format](https://developer.hashicorp.com/terraform/internals/json-format)
(`terraform show -json tfplan`, format 1.2), one scenario each, for trying
`Get-AACTerraformPlan` without Terraform or Azure. All IDs and secrets are made up.
`Tests\TerraformPlan.Tests.ps1` runs every one.

| File | What it covers | Terraform would say |
|---|---|---|
| `01-create-landing-zone.json` | Creates: nested blocks, lists, values known after apply, a sensitive output | 3 to add |
| `02-update-in-place.json` | Updates: map keys added and removed, a sensitive app setting, nested `site_config`, a block added by name, list of strings changed | 2 to change |
| `03-replace-every-reason.json` | Both replacement orders and every replace reason: cannot update (nested `replace_paths`), tainted, `-replace`, `replace_triggered_by` | 5 to add, 5 to destroy |
| `04-delete-every-reason.json` | Every delete reason: removed from config, module removed, count/for_each, count index, for_each key, no moved target | 6 to destroy |
| `05-data-sources-read.json` | Data sources read during apply, each read reason, a sensitive value in a data source | (reads only) |
| `06-import-and-move.json` | `import` blocks (with and without changes, `generated_config`), `moved` blocks into a module and from `count` to `for_each` | 2 to change |
| `07-drift-outside-terraform.json` | `resource_drift`: a rule added in the portal and a container deleted outside Terraform, and the plan that undoes them | 1 to add, 1 to change |
| `08-sensitive-values.json` | Secrets in clear text in the JSON: a password, a whole sensitive block, a sensitive map key in an output, a fully sensitive output | 1 to add, 2 to change |
| `09-json-encoded-strings.json` | Policy rules and ARM parameters as JSON strings (diffed inside), a rule only reformatted, an `azapi` body | 4 to change |
| `10-no-changes.json` | Nothing to do (`applyable: false`, as Terraform writes it) | No changes |
| `11-errored-plan.json` | `errored: true`: a partial plan that can't be applied | 1 to add |
| `12-deposed-object.json` | A `deposed` object left by a failed `create_before_destroy`, at the same address as the live one | 1 to destroy |
| `13-checks.json` | `checks`: a failing postcondition with its message, an unknown check block, a passing output check | 1 to change |
| `14-forget-removed-block.json` | `removed` block with `destroy = false` (action `forget`) | 1 to forget |
| `15-nested-modules.json` | Nested modules with `for_each` keys and a `count` index | 2 to add, 1 to change |
| `invalid-state-not-plan.json` | `terraform show -json` without a plan file: state, refused | - |
| `invalid-not-terraform.json` | Some other JSON, refused | - |

Try them:

```powershell
Import-Module .\Azure.Admin.Console.psd1
$plans = '.\Tests\Fixtures\TerraformPlans'

Get-AACTerraformPlan -Path "$plans\03-replace-every-reason.json"                       # the view
Get-AACTerraformPlan -Path "$plans\02-update-in-place.json" -ExpandAttribute -NoDisplay | Format-Table
Get-AACTerraformPlan -Path "$plans\07-drift-outside-terraform.json" -IncludeDrift -NoDisplay
Get-AACTerraformPlan -Path "$plans\08-sensitive-values.json" -HtmlPath .\out\Sensitive.html
Get-ChildItem "$plans\0*.json", "$plans\1*.json" | ForEach-Object { Get-AACTerraformPlan -Path $_.FullName -NoPaging }
```

For a real plan, any small configuration works without Azure - `terraform_data`
is built into Terraform and needs no provider:

```powershell
terraform init; terraform apply -auto-approve      # once, to have state
# change the configuration, then:
terraform plan -out tfplan
terraform show -json tfplan > plan.json            # PowerShell 5.1 writes UTF-16 here; that's read too
Get-AACTerraformPlan -Path .\plan.json
```
