---
severity: Awareness
pillar: Operational Excellence
category: Tagging
resource: All resources
online version: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/PSRule/Rules/en/AAC.Resource.AllowedTagValues.md
---

# Tags use their allowed values

## SYNOPSIS

Tags with a fixed set of values use one of them.

## DESCRIPTION

Some tags only make sense with a fixed set of values: an `Environment` of
`prod`, `test` or `dev`, for example, so that reports and policies can rely on
them. This rule checks resources and resource groups against the
`AAC_ALLOWED_TAG_VALUES` setting, a table of tag name to allowed values. A
resource without the tag passes this rule; `AAC.Resource.RequiredTags` checks
that the tag is there.

The rule does nothing until `AAC_ALLOWED_TAG_VALUES` is set.

## RECOMMENDATION

Correct the tag's value, and enforce the allowed values with Azure Policy.

## EXAMPLES

```powershell
Invoke-AACPSRule -Configuration @{ AAC_ALLOWED_TAG_VALUES = @{ Environment = @('prod', 'test', 'dev') } }
```

## LINKS

- [Define your tagging strategy](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-tagging)
