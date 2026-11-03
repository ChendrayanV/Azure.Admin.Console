function Get-AACServiceTemplate {
    <#
    .SYNOPSIS
        The services New-AACServiceBlueprint has a hand-checked plan for: the
        resources each one needs, their secure starting configuration and their
        naming rules.
    .DESCRIPTION
        Which services exist comes from Azure (Get-AACServiceCatalog). What it can't
        say is here: its list has a name and resource types, but no API version,
        SKU, naming rule or secure configuration. A service without a template
        is still planned, as its types, with what doesn't need a body.

        Returns an ordered dictionary: service key -> @{ Name; Anchor; NameLike;
        Components }. Anchor is the resource type that identifies the service in
        Azure's list; NameLike narrows it where a type is shared: Microsoft.Web/sites
        is a web app as well as a Function App.
        A component is @{ Id; Label; Type; ApiVersion; Icon; Abbreviation;
        Naming = @{ Min; Max; Pattern; Strip; Text }; Sku; Public; Body;
        Children }.
          Abbreviation  the Cloud Adoption Framework's
          Naming        what Azure accepts: the length and the characters;
                        Strip removes the hyphens the name can't have
          Body          a script block taking the planned resources' IDs by
                        component ID, returning the resource without its
                        name and location: private, no shared keys or local
                        auth, TLS 1.2, a managed identity and zone redundancy
                        where the service has them
          Public        the properties that would open it to the internet -
                        the question put to Azure Policy: is that refused?
          Children      its planned sub-resources, for PSRule (optional)
        Each body is hand-checked, so a service is added on purpose.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()

    [ordered]@{
        FunctionApp    = @{
            Name       = 'Function App'
            Anchor     = 'Microsoft.Web/sites'
            NameLike   = '*function*'
            Components = @(
                @{
                    Id = 'plan'; Label = 'App Service plan'; Type = 'Microsoft.Web/serverfarms'; ApiVersion = '2025-03-01'; Icon = 'appserviceplan'; Abbreviation = 'asp'; Sku = 'EP1'; Public = @{}
                    Naming = @{ Min = 1; Max = 60; Pattern = '^[a-z0-9-]+$'; Strip = $false; Text = '1-60 letters, numbers and hyphens' }
                    Body = { param($Ids) [ordered]@{ kind = 'elastic'; sku = @{ name = 'EP1'; tier = 'ElasticPremium'; capacity = 3 }; properties = [ordered]@{ reserved = $true; zoneRedundant = $true; maximumElasticWorkerCount = 20 } } }
                }
                @{
                    Id = 'functionapp'; Label = 'Function App'; Type = 'Microsoft.Web/sites'; ApiVersion = '2025-03-01'; Icon = 'functionapp'; Abbreviation = 'func'; Sku = 'On the plan'; Public = @{ publicNetworkAccess = 'Enabled' }
                    Naming = @{ Min = 2; Max = 60; Pattern = '^[a-z0-9]([a-z0-9-]*[a-z0-9])?$'; Strip = $false; Text = '2-60 letters, numbers and hyphens, not starting or ending with a hyphen' }
                    Body = {
                        param($Ids)
                        [ordered]@{
                            kind = 'functionapp,linux'; identity = @{ type = 'SystemAssigned' }
                            properties = [ordered]@{
                                serverFarmId = $Ids['plan']; httpsOnly = $true; publicNetworkAccess = 'Disabled'; clientAffinityEnabled = $false
                                siteConfig = [ordered]@{ linuxFxVersion = 'DOTNET-ISOLATED|8.0'; minTlsVersion = '1.2'; ftpsState = 'Disabled'; http20Enabled = $true; alwaysOn = $false }
                            }
                        }
                    }
                }
            )
        }
        StorageAccount = @{
            Name       = 'Storage account'
            Anchor     = 'Microsoft.Storage/storageAccounts'
            Components = @(
                @{
                    Id = 'storage'; Label = 'Storage account'; Type = 'Microsoft.Storage/storageAccounts'; ApiVersion = '2023-05-01'; Icon = 'storage'; Abbreviation = 'st'; Sku = 'Standard_ZRS'; Public = @{ publicNetworkAccess = 'Enabled'; networkAcls = @{ defaultAction = 'Allow'; bypass = 'AzureServices' } }
                    Naming = @{ Min = 3; Max = 24; Pattern = '^[a-z0-9]+$'; Strip = $true; Text = '3-24 lowercase letters and numbers' }
                    Body = {
                        param($Ids)
                        [ordered]@{
                            kind = 'StorageV2'; sku = @{ name = 'Standard_ZRS' }; identity = @{ type = 'SystemAssigned' }
                            properties = [ordered]@{
                                accessTier = 'Hot'; minimumTlsVersion = 'TLS1_2'; supportsHttpsTrafficOnly = $true; allowBlobPublicAccess = $false; allowSharedKeyAccess = $false
                                defaultToOAuthAuthentication = $true; publicNetworkAccess = 'Disabled'; networkAcls = @{ defaultAction = 'Deny'; bypass = 'AzureServices' }
                            }
                        }
                    }
                    Children = @(
                        [ordered]@{ name = 'default'; type = 'Microsoft.Storage/storageAccounts/blobServices'; properties = [ordered]@{ deleteRetentionPolicy = @{ enabled = $true; days = 7 }; containerDeleteRetentionPolicy = @{ enabled = $true; days = 7 } } }
                    )
                }
            )
        }
        EventHub       = @{
            Name       = 'Event Hubs'
            Anchor     = 'Microsoft.EventHub/namespaces'
            Components = @(
                @{
                    Id = 'eventhub'; Label = 'Event Hubs namespace'; Type = 'Microsoft.EventHub/namespaces'; ApiVersion = '2024-01-01'; Icon = 'eventhub'; Abbreviation = 'evhns'; Sku = 'Standard'; Public = @{ publicNetworkAccess = 'Enabled' }
                    Naming = @{ Min = 6; Max = 50; Pattern = '^[a-z][a-z0-9-]*[a-z0-9]$'; Strip = $false; Text = '6-50 letters, numbers and hyphens, starting with a letter and ending with a letter or number' }
                    Body = {
                        param($Ids)
                        [ordered]@{
                            sku = @{ name = 'Standard'; tier = 'Standard'; capacity = 1 }; identity = @{ type = 'SystemAssigned' }
                            properties = [ordered]@{ minimumTlsVersion = '1.2'; publicNetworkAccess = 'Disabled'; disableLocalAuth = $true; zoneRedundant = $true }
                        }
                    }
                }
            )
        }
        EventGrid      = @{
            Name       = 'Event Grid'
            Anchor     = 'Microsoft.EventGrid/topics'
            Components = @(
                @{
                    Id = 'eventgrid'; Label = 'Event Grid topic'; Type = 'Microsoft.EventGrid/topics'; ApiVersion = '2025-02-15'; Icon = 'eventgridtopic'; Abbreviation = 'evgt'; Sku = 'Basic'; Public = @{ publicNetworkAccess = 'Enabled' }
                    Naming = @{ Min = 3; Max = 50; Pattern = '^[a-z0-9-]+$'; Strip = $false; Text = '3-50 letters, numbers and hyphens' }
                    Body = {
                        param($Ids)
                        [ordered]@{
                            identity = @{ type = 'SystemAssigned' }
                            properties = [ordered]@{ inputSchema = 'CloudEventSchemaV1_0'; publicNetworkAccess = 'Disabled'; disableLocalAuth = $true; minimumTlsVersionAllowed = '1.2' }
                        }
                    }
                }
            )
        }
    }
}
