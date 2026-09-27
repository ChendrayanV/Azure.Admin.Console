---
severity: Important
pillar: Operational Excellence
category: Tagging
resource: Resource group
online version: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/PSRule/Rules/en/AAC.ResourceGroup.RequiredTags.md
---

# Resource groups carry the required tags

## SYNOPSIS

Resource groups carry every tag your organisation requires.

## DESCRIPTION

A resource group's tags can be inherited by the resources in it through Azure
Policy, so they matter as much as the resources' own tags. This rule checks
every resource group for the tags named in the `AAC_REQUIRED_TAGS` setting.

The rule does nothing until `AAC_REQUIRED_TAGS` is set.

## RECOMMENDATION

Add the missing tags, and enforce them with Azure Policy (the "Require a tag
on resource groups" built-in policy).

## EXAMPLES

```powershell
Invoke-AACPSRule -Configuration @{ AAC_REQUIRED_TAGS = @('Owner', 'CostCenter') }
```

## LINKS

- [Define your tagging strategy](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-tagging)
