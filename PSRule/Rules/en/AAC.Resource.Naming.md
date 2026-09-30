---
severity: Awareness
pillar: Operational Excellence
category: Naming
resource: All resources
online version: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/PSRule/Rules/en/AAC.Resource.Naming.md
---

# Names follow the naming convention

## SYNOPSIS

Resources and resource groups follow the naming convention.

## DESCRIPTION

A consistent naming convention tells you a resource's type, workload and
environment at a glance, and lets scripts, policies and cost reports rely on
it. This rule checks the names of about 30 common resource types, and of
resource groups, against Microsoft's Cloud Adoption Framework abbreviations:
`rg-` for resource groups, `vnet-` for virtual networks, `kv-` for key vaults,
`st` plus 3-22 lowercase letters and digits for storage accounts, and so on.
Types and names are compared case-insensitively. Disks, network interfaces
and VM extensions aren't checked: Azure and the portal name them.

To use your own convention, give `AAC_NAMING_PATTERNS` - a table of resource
type to the regular expression its names must match. Its types replace or add
to the defaults, and an empty pattern (`''`) turns a type off. The defaults
are in `PSRule\Rules\AAC.Naming.Rule.ps1` (`Get-AACNamingDefault`).

Names Azure creates and manages itself are skipped, because they can't be
renamed: AKS node resource groups (`MC_*`), `NetworkWatcherRG`,
`DefaultResourceGroup-*`, `AzureBackupRG_*`, `databricks-rg-*`,
`cloud-shell-storage-*`, and anything another service manages. Add your own
exceptions with `AAC_NAMING_IGNORE`, a list of regular expressions.

The rule runs without any setting. Leave it out with
`-ExcludeRule 'AAC.Resource.Naming'`.

## RECOMMENDATION

Most Azure resources can't be renamed: create new resources with a compliant
name and move the workload, or record the exception in `AAC_NAMING_IGNORE`.
Enforce the convention for new resources with Azure Policy.

## EXAMPLES

```powershell
# The Cloud Adoption Framework defaults.
Invoke-AACPSRule -Rule 'AAC.Resource.Naming'

# Your own patterns for some types, one type off, and names never checked.
Invoke-AACPSRule -Rule 'AAC.Resource.Naming' -Configuration @{
    AAC_NAMING_PATTERNS = @{
        'Microsoft.Compute/virtualMachines' = '^vm-(prod|test|dev)-'
        'Microsoft.Web/sites'               = ''
    }
    AAC_NAMING_IGNORE   = @('^legacy-')
}
```

Run alone, the rule reads only the resource types it checks, and no child
settings - a few Resource Graph queries, however large the estate.

## LINKS

- [Define your naming convention](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming)
- [Abbreviation recommendations for Azure resources](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations)
