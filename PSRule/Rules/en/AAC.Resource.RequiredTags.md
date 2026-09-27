---
severity: Important
pillar: Operational Excellence
category: Tagging
resource: All resources
online version: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/PSRule/Rules/en/AAC.Resource.RequiredTags.md
---

# Resources carry the required tags

## SYNOPSIS

Resources carry every tag your organisation requires.

## DESCRIPTION

Tags tell you who owns a resource, who pays for it and what it is for.
This rule checks every resource (not resource groups or subscriptions) for the
tags named in the `AAC_REQUIRED_TAGS` setting, and fails for each one that is
missing or empty. Tag names are compared without regard to case.

The rule does nothing until `AAC_REQUIRED_TAGS` is set.

## RECOMMENDATION

Add the missing tags, and enforce them with Azure Policy (the "Require a tag
on resources" and "Inherit a tag from the resource group" built-in policies).

## EXAMPLES

```powershell
Invoke-AACPSRule -Configuration @{ AAC_REQUIRED_TAGS = @('Owner', 'CostCenter', 'Environment') }
```

## LINKS

- [Define your tagging strategy](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-tagging)
- [Assign policy definitions for tag compliance](https://learn.microsoft.com/azure/azure-resource-manager/management/tag-policies)
