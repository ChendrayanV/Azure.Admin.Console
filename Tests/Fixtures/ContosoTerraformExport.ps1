<#
    Made-up answers of the Azure Export for Terraform API for Contoso: the
    export of rg-app with azurerm (two resources exported, a Grafana
    workspace skipped - no azurerm support), the azapi export of that
    Grafana workspace, and a terraform plan of the folder (show -json):
    two imports, one of them with an attribute Terraform would change.
#>

function Get-AACContosoTerraformExport {
    $sub = '11111111-1111-1111-1111-111111111111'
    $rg = "/subscriptions/$sub/resourceGroups/rg-app"
    $vnet = "$rg/providers/Microsoft.Network/virtualNetworks/vnet-app"
    $grafana = "$rg/providers/Microsoft.Dashboard/grafana/amg-app"
    $nl = "`n"
    @{
        Sub     = $sub
        Rg      = $rg
        Vnet    = $vnet
        Grafana = $grafana
        AzureRm = @{
            configuration    = (@(
                    'terraform {', '  required_providers {', '    azurerm = {', '      source  = "azurerm"', '      version = "4.80.0"', '    }', '  }', '}'
                    'provider "azurerm" {', '  features {}', '}'
                    'resource "azurerm_resource_group" "res-0" {', '  location = "uksouth"', '  name     = "rg-app"', '  tags     = { note = "a } in a string" }', '}'
                    'resource "azurerm_virtual_network" "res-1" {', '  address_space       = ["10.1.0.0/16"]', '  location            = "uksouth"', '  name                = "vnet-app"', '  resource_group_name = "rg-app"', '  depends_on          = [azurerm_resource_group.res-0]', '}'
                ) -join $nl) + $nl
            import           = (@(
                    'import {', "  id = `"$rg`"", '  to = azurerm_resource_group.res-0', '}'
                    'import {', "  id = `"$vnet`"", '  to = azurerm_virtual_network.res-1', '}'
                ) -join $nl) + $nl
            skippedResources = @($grafana)
            errors           = @(@{ code = 'PropertyNotSupported'; message = 'A property was left out.'; target = $vnet })
        }
        AzApi   = @{
            configuration    = (@(
                    'terraform {', '  required_providers {', '    azapi = {', '      source  = "Azure/azapi"', '      version = "2.5.0"', '    }', '  }', '}'
                    'provider "azapi" {', '}'
                    'resource "azapi_resource" "res-azapi-0" {', '  type      = "Microsoft.Dashboard/grafana@2024-10-01"', '  parent_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-app"', '  name      = "amg-app"', '  body = <<EOT', '{ "properties": { } }', 'EOT', '}'
                ) -join $nl) + $nl
            import           = (@('import {', "  id = `"${grafana}?api-version=2024-10-01`"", '  to = azapi_resource.res-azapi-0', '}') -join $nl) + $nl
            skippedResources = @()
            errors           = @()
        }
        PlanJson = (ConvertTo-Json -Depth 20 -Compress -InputObject ([ordered]@{
                    format_version   = '1.2'
                    terraform_version = '1.9.0'
                    resource_changes = @(
                        [ordered]@{ address = 'azurerm_resource_group.res-0'; type = 'azurerm_resource_group'; name = 'res-0'; provider_name = 'registry.terraform.io/hashicorp/azurerm'; mode = 'managed'
                            change = [ordered]@{ actions = @('no-op'); before = @{ name = 'rg-app' }; after = @{ name = 'rg-app' }; importing = @{ id = $rg } } }
                        [ordered]@{ address = 'azurerm_virtual_network.res-1'; type = 'azurerm_virtual_network'; name = 'res-1'; provider_name = 'registry.terraform.io/hashicorp/azurerm'; mode = 'managed'
                            change = [ordered]@{ actions = @('update'); before = @{ name = 'vnet-app'; flow_timeout_in_minutes = 4 }; after = @{ name = 'vnet-app'; flow_timeout_in_minutes = $null }; importing = @{ id = $vnet } } }
                    )
                }))
    }
}
