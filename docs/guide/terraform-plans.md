# Terraform plans

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Get-AACTerraformPlan`](../Get-AACTerraformPlan.md)

`Get-AACTerraformPlan` reads a whole Terraform plan - every resource
change, the outputs and the drift - and flattens it so you can see what
changes before you apply it. It works offline: no Azure sign-in, and no
Terraform on the machine that reads it.

```powershell
terraform plan -out tfplan
terraform show -json tfplan > plan.json

Get-AACTerraformPlan -Path .\plan.json                                    # the view
Get-AACTerraformPlan -Path .\plan.json -Action Delete, Replace -NoDisplay # what is destroyed, and why
Get-AACTerraformPlan -Path .\plan.json -ExpandAttribute -NoDisplay | Where-Object ForcesReplacement
Get-AACTerraformPlan -Path .\plan.json -HtmlPath .\Plan.html -CsvPath .\Plan.csv -ExpandAttribute
```

One row per resource (`AAC.TerraformChange`): the action (Create, Update,
Replace, Delete, Read, Import, Move, Forget), the address and module, the
Azure name, resource group, location and ID, why it's replaced or deleted,
the attributes that force a replacement, and the attributes that change.
`-ExpandAttribute` gives one row per attribute instead
(`AAC.TerraformAttributeChange`), with its before and after value. Nested
values are flattened to a path - `tags["cost.centre"]`,
`site_config[0].always_on`, `security_rule[name=ssh].access`, and
`policy_rule{json}.then.effect` inside a JSON-encoded string. Blocks in a
list are matched by content, then by name, so a rule added to an NSG
doesn't show every rule after it as changed.

The plan JSON holds sensitive values in clear text. They are never shown,
returned or written: they read `(sensitive)`. The view opens with
Terraform's own summary line (`Plan: 2 to add, 5 to change, 2 to destroy.`),
then a table per action - deletes and replacements first - with each
resource's attribute changes as `+`, `-` and `~` lines, the outputs, and what
changed outside Terraform. `-HtmlPath` writes tables of the resources, every
attribute change, the outputs and the drift, with tiles and charts that
filter them.
