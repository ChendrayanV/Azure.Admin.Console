# Azure.Admin.Console's naming rule, run by Invoke-AACPSRule with PSRule for
# Azure's. Every resource type in Get-AACNamingDefault below must have names
# matching its pattern - Microsoft's Cloud Adoption Framework abbreviations
# (https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations).
# It runs without any setting:
#
#   Invoke-AACPSRule -Rule 'AAC.Resource.Naming'
#
# To change the convention:
#   - add or edit lines in Get-AACNamingDefault below (one per type), or
#   - pass AAC_NAMING_PATTERNS in -Configuration: its types replace or add to
#     the defaults, and '' turns a type off
#   - AAC_NAMING_IGNORE: name patterns never checked
#
#   Invoke-AACPSRule -Rule 'AAC.Resource.Naming' -Configuration @{
#       AAC_NAMING_PATTERNS = @{ 'Microsoft.Compute/virtualMachines' = '^vm-(prod|dev)-'; 'Microsoft.Web/sites' = '' }
#       AAC_NAMING_IGNORE   = @('^legacy-')
#   }
#
# Types and names are compared case-insensitively. Names Azure creates itself,
# which can't be renamed (AKS node resource groups, NetworkWatcherRG, ...),
# are skipped. Its help is in en\AAC.Resource.Naming.md. Leave it out with
# -ExcludeRule 'AAC.Resource.Naming'.
#
# Invoke-AACPSRule reads this table too (without running this file), so a run
# of this rule alone reads only these types: keep it a plain table of
# 'type' = 'pattern' strings.

# Resource type -> the pattern its names must match. One line per type: add
# your own here. Disks, network interfaces and VM extensions are left out:
# Azure and the portal name them (vm-web-01_OsDisk_1_...).
function global:Get-AACNamingDefault {
    @{
        'Microsoft.Resources/resourceGroups'               = '^rgp-'
        'Microsoft.Compute/virtualMachines'                = '^vm'
        'Microsoft.Compute/virtualMachineScaleSets'        = '^vmss'
        'Microsoft.Network/virtualNetworks'                = '^vnet-'
        'Microsoft.Network/networkSecurityGroups'          = '^nsg-'
        'Microsoft.Network/publicIPAddresses'              = '^pip-'
        'Microsoft.Network/loadBalancers'                  = '^lb[ie]?-'
        'Microsoft.Network/applicationGateways'            = '^agw-'
        'Microsoft.Network/azureFirewalls'                 = '^afw-'
        'Microsoft.Network/routeTables'                    = '^rt-'
        'Microsoft.Network/bastionHosts'                   = '^bas-'
        'Microsoft.Network/privateEndpoints'               = '^pep-'
        'Microsoft.KeyVault/vaults'                        = '^kv-'
        'Microsoft.Storage/storageAccounts'                = '^st[a-z0-9]{3,22}$'
        'Microsoft.Web/sites'                              = '^(app|func)-'
        'Microsoft.Web/serverFarms'                        = '^asp-'
        'Microsoft.Sql/servers'                            = '^sql-'
        'Microsoft.ContainerService/managedClusters'       = '^aks-'
        'Microsoft.ContainerRegistry/registries'           = '^cr[a-z0-9]+$'
        'Microsoft.OperationalInsights/workspaces'         = '^log-'
        'Microsoft.Insights/components'                    = '^appi-'
        'Microsoft.ApiManagement/service'                  = '^apim-'
        'Microsoft.DocumentDB/databaseAccounts'            = '^cosmos-'
        'Microsoft.ServiceBus/namespaces'                  = '^sbns-'
        'Microsoft.EventHub/namespaces'                    = '^evhns-'
        'Microsoft.ManagedIdentity/userAssignedIdentities' = '^id-'
        'Microsoft.Automation/automationAccounts'          = '^aa-'
        'Microsoft.RecoveryServices/vaults'                = '^rsv-'
    }
}

# The pattern for the target's type, and the type as the table spells it:
# -Configuration's AAC_NAMING_PATTERNS first ('' turns the type off), then the
# defaults. The setting arrives as a hashtable, or as an object when read
# from JSON. Returns @{ Type; Pattern }, or nothing.
function global:Get-AACNamingPattern {
    $type = [string]$TargetObject.type
    $patterns = $Configuration.GetValueOrDefault('AAC_NAMING_PATTERNS', $null)
    if ($null -ne $patterns) {
        $pairs = if ($patterns -is [System.Collections.IDictionary]) {
            @($patterns.Keys | ForEach-Object { @{ Type = [string]$_; Pattern = $patterns[$_] } })
        }
        else {
            @($patterns.PSObject.Properties | ForEach-Object { @{ Type = [string]$_.Name; Pattern = $_.Value } })
        }
        foreach ($pair in $pairs) {
            if ($pair.Type -eq $type) { return @{ Type = $pair.Type; Pattern = [string]$pair.Pattern } }
        }
    }
    $defaults = Get-AACNamingDefault
    foreach ($key in $defaults.Keys) {
        if ($key -eq $type) { return @{ Type = [string]$key; Pattern = [string]$defaults[$key] } }
    }
}

# A name Azure (or a service) creates and manages, which can't be renamed -
# or one the AAC_NAMING_IGNORE patterns leave out.
function global:Test-AACNamingIgnored {
    $name = [string]$TargetObject.name
    $builtIn = @(
        '^MC_'                        # AKS node resource group
        '^NetworkWatcherRG$'          # Network Watcher
        '^DefaultResourceGroup-'      # Log Analytics / Defender defaults
        '^AzureBackupRG_'             # Azure Backup restore points
        '^databricks-rg-'             # Azure Databricks managed group
        '^cloud-shell-storage-'       # Cloud Shell
        '^LogAnalyticsDefaultResources$'
    )
    foreach ($pattern in @($builtIn) + @($Configuration.GetStringValues('AAC_NAMING_IGNORE'))) {
        if ($pattern -and $name -match $pattern) { return $true }
    }
    # A resource another service manages (managedBy set) keeps the name it was given.
    [bool]$TargetObject.managedBy
}

# Synopsis: Resources and resource groups follow the naming convention.
Rule 'AAC.Resource.Naming' -Ref 'AAC-004' -Level Warning -Tag @{ release = 'GA'; 'Azure.WAF/pillar' = 'Operational Excellence' } -If {
    $convention = Get-AACNamingPattern
    $convention -and $convention.Pattern -and -not (Test-AACNamingIgnored)
} {
    $convention = Get-AACNamingPattern
    $Assert.Match($TargetObject, 'name', $convention.Pattern).Reason('The name doesn''t match ''{0}'', the naming convention for {1}.', $convention.Pattern, $convention.Type)
}
