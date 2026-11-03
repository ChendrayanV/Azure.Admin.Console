# PSRule for Azure

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Invoke-AACPSRule`](../Invoke-AACPSRule.md)

`Invoke-AACPSRule` checks your live estate with
[PSRule for Azure](https://azure.github.io/PSRule.Rules.Azure/): its 500+
rules, following the Azure Well-Architected Framework, on every resource,
resource group and subscription you can see. The module's own rules and your
custom rules run alongside them.

```powershell
Connect-AAC
Invoke-AACPSRule                                                  # the console view
Invoke-AACPSRule -SubscriptionId '00000000-0000-0000-0000-000000000000' -HtmlPath .\PSRule.html
Invoke-AACPSRule -CsvPath .\PSRule.csv -PdfPath .\PSRule.pdf -FailedOnly
Invoke-AACPSRule -Rule 'Azure.Storage.*', 'Azure.KeyVault.*'      # only these rules
Invoke-AACPSRule -ExcludeRule 'Azure.Resource.UseTags', 'AAC.*'    # leave these out
Invoke-AACPSRule -Baseline 'Azure.Pillar.Security'                 # a PSRule for Azure baseline
Invoke-AACPSRule -FailedOnly | Group-Object RuleName | Sort-Object Count -Descending
```

The console view has tiles for objects checked, rules, passed, failed,
"could not evaluate" and pass rate. A bar chart shows the failures by pillar.
Then each pillar gets a table of its failing rules, most severe first, with
the resources each one failed on and why. The HTML report opens on the
failures, grouped by rule, with portal and rule documentation links. The PDF
lists every failing resource under its rule, with the rule's recommendation.

## The rules

| Source              | Rules                                                                                          |                                                                                                                                                                                                                       |
| ------------------- | ---------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| PSRule for Azure    | Every rule of the installed PSRule.Rules.Azure                                                 | `-Baseline` picks one of its baselines                                                                                                                                                                                |
| Azure.Admin.Console | `AAC.Resource.RequiredTags`, `AAC.ResourceGroup.RequiredTags`, `AAC.Resource.AllowedTagValues` | Check the tags named in `Get-AACTagDefault` (`PSRule\Rules\AAC.Tags.Rule.ps1`, empty as shipped) or in `AAC_REQUIRED_TAGS` / `AAC_ALLOWED_TAG_VALUES`; with no tags named they check nothing, and the command says so |
| Azure.Admin.Console | `AAC.Resource.Naming`                                                                          | On by default: the Cloud Adoption Framework abbreviations (`rg-`, `vnet-`, `kv-`, `st...`), or your own with `AAC_NAMING_PATTERNS`                                                                                    |
| Custom              | Your own rule files, from `-RulePath`                                                          | `*.Rule.ps1`, `*.Rule.yaml` or `*.Rule.jsonc`                                                                                                                                                                         |

`-Rule` runs only the rules named, and `-ExcludeRule` leaves rules out. Both
take names or wildcards. `-Configuration` passes settings to every rule:
PSRule for Azure's
[options](https://azure.github.io/PSRule.Rules.Azure/setup/configuring-options/),
the module's `AAC_*` settings, or your rules' own.

```powershell
Invoke-AACPSRule -Configuration @{
    AAC_REQUIRED_TAGS                = @('Owner', 'CostCenter', 'Environment')
    AAC_ALLOWED_TAG_VALUES           = @{ Environment = @('prod', 'test', 'dev') }
    AZURE_RESOURCE_ALLOWED_LOCATIONS = @('uksouth', 'ukwest')
}
```

**Insights** (`-Insight`) add what the estate is made of and what needs
attention, from the same parallel Resource Graph read (about 11 more
queries):

|                     |                                                                                                                                                                                                                                                                                                                                                |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Mix**             | VM sizes, operating systems (Windows Server 2022, Ubuntu 22.04, ... - from the VM's instance view, or its image), VM power states, Azure VMs and Azure Arc servers, storage account replication, database tiers (Azure SQL DTU / vCore / serverless, Cosmos DB, PostgreSQL, MySQL), tag coverage                                               |
| **Needs attention** | Unattached disks (with their size), unused public IPs and NICs, VMs **stopped but still billed** (stopped in the OS, not deallocated), disconnected Arc servers, classic resources (retired), subnets 80% full or more, VPN and ExpressRoute connections down, empty resource groups - each with its cost this month when `-Cost` is given too |
| **Network**         | Every subnet's used and usable IPs (Azure keeps 5 per subnet), and the VPN and ExpressRoute connections with their status                                                                                                                                                                                                                      |

The console shows them as proportion charts and a table; the HTML report as
donut charts that filter a machines table, and tables of what needs
attention, subnets and connections; the PDF as a page of its own.

**Tags.** The tag rules check the tags you name. Name them for one run with
`-Configuration`, or for every run in `Get-AACTagDefault` in
`PSRule\Rules\AAC.Tags.Rule.ps1`:

```powershell
function global:Get-AACTagDefault {
    @{
        RequiredTags  = @('Owner', 'CostCenter', 'Environment')
        AllowedValues = @{ Environment = @('prod', 'test', 'dev') }
    }
}
```

`-Configuration` wins over the defaults. When a tag rule you asked for has
no tags to check, the view (and `-HtmlPath`, or a warning with `-NoDisplay`)
says so instead of leaving it out silently.

**Naming conventions.** `AAC.Resource.Naming` checks the names of resource
groups and about 30 common resource types against Microsoft's
[Cloud Adoption Framework abbreviations](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations),
with no setting needed. Run on its own, it reads only the types it checks and
no child settings: a few Resource Graph queries, however large the estate.
Names Azure creates and manages (`MC_*`, `NetworkWatcherRG`, ...) are skipped.

```powershell
Invoke-AACPSRule -Rule 'AAC.Resource.Naming'                       # the defaults
Invoke-AACPSRule -Rule 'AAC.Resource.Naming' -Configuration @{
    AAC_NAMING_PATTERNS = @{ 'Microsoft.Compute/virtualMachines' = '^vm-(prod|test|dev)-'; 'Microsoft.Web/sites' = '' }   # '' = don't check
    AAC_NAMING_IGNORE   = @('^legacy-')
}
```

To change the defaults for everyone who uses your copy of the module, edit
the table in `PSRule\Rules\AAC.Naming.Rule.ps1` (`Get-AACNamingDefault`), one
line per type. To keep your own convention without editing the module, set
it once in your profile:
`$PSDefaultParameterValues['Invoke-AACPSRule:Configuration'] = @{ AAC_NAMING_PATTERNS = @{ ... } }`.

`-Rule` takes rule names, not files: the module's rules always load, and
`-RulePath` adds rule files of your own. A `-Rule` that matches no rule is an
error rather than an empty result.

## Your own rules

Write rules the way PSRule does:
[PowerShell, YAML or JSON](https://microsoft.github.io/PSRule/v2/authoring/writing-rules/).
Then pass the file or folder to `-RulePath`. PSRule for Azure's binding
applies to them too, so `-Type 'Microsoft.Storage/storageAccounts'` works. A
`# Synopsis:` comment names the rule, and an `Azure.WAF/pillar` tag places it
in a pillar. A help file in `en\<rule name>.md` next to it adds the severity,
recommendation and documentation link. See `PSRule\Rules` for examples.

```powershell
# .\MyRules\Contoso.Storage.Rule.ps1
# Synopsis: Storage accounts use the Contoso naming convention.
Rule 'Contoso.Storage.Name' -Type 'Microsoft.Storage/storageAccounts' -Tag @{ 'Azure.WAF/pillar' = 'Operational Excellence' } {
    $Assert.Match($TargetObject, 'name', '^stcontoso')
}
```

```powershell
Invoke-AACPSRule -RulePath .\MyRules -Rule 'Contoso.*'
```

## How it reads the estate

PSRule for Azure normally reads its data from `Export-AzRuleData`, which
needs the Az modules. This reads the same data with the `Connect-AAC`
sign-in instead:

- Resource Graph returns every resource with its properties, plus the
  resource groups and subscriptions.
- Azure Resource Manager provides the child settings PSRule's rules look at,
  such as storage blob services and containers, SQL auditing and firewall
  rules, Key Vault diagnostic settings, App Service config, and API
  Management APIs, products and policies. It reads the same children, with
  the same API versions, as `Export-AzRuleData` (PSRule.Rules.Azure v1.47).

When only the module's `AAC.*` rules run, the child settings aren't read:
those rules look only at names, types and tags. `-NoExpand` does the same for
your own rules that need nothing more.

Reader access is enough. When a setting can't be read, the command warns and
names it, because the rules using it may be wrong for that resource. VPN
connection shared keys are masked before PSRule sees them. A rule that can't
evaluate a resource is reported as "could not evaluate" for that resource,
and every other rule still runs. PSRule runs in a `pwsh` process of its own,
so its `YamlDotNet.dll` never clashes with the different versions that
platyPS, powershell-yaml or Az.Aks may have loaded into your session.
