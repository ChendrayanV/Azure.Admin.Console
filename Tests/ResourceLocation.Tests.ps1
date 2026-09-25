<#
    Checks that every Azure resource lives in an allowed location - UK South
    by default. One Context per resource type, one It per resource, so the
    Invoke-AACPester report groups the results by type and shows
    each resource as Passed (in an allowed location) or Failed (anywhere else).

    This is a live check against Azure: it needs a Connect-AAC sign-in in the
    same PowerShell session. Without one, it reports a single Skipped test
    rather than failing. Resources come from Azure Resource Graph across every
    Enabled subscription the signed-in account can see (see
    Get-AACResourceInventory).

    Resources Azure keeps in the "global" location (e.g. DNS zones, Front
    Door, Traffic Manager) can't be placed in a region, so they fail under the
    default rule. To accept them, or to check other regions or only certain
    subscriptions, run this file with data:

        $container = New-PesterContainer -Path .\Tests\ResourceLocation.Tests.ps1 -Data @{
            AllowedLocation = @('uksouth', 'global')
            SubscriptionId  = @('00000000-0000-0000-0000-000000000000')
        }
        Invoke-Pester -Container $container -Output Detailed
#>

param(
    # Locations are compared case-insensitively with spaces removed, so
    # 'UK South' and 'uksouth' are the same.
    [string[]] $AllowedLocation = @('uksouth'),

    # Defaults to every Enabled subscription the signed-in account can see.
    [string[]] $SubscriptionId = @()
)

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    # Import only if not already loaded - a -Force reimport here would
    # replace the module Invoke-AACPester is running from, mid-run.
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }

    $allowed = @($AllowedLocation | ForEach-Object { ($_ -replace '\s', '').ToLowerInvariant() })

    # Exactly one of these ends up non-empty, and decides which tests exist.
    $script:aacResourceTypeCases = @()
    $script:aacNotConnectedCase = @()
    $script:aacInventoryErrorCase = @()
    $script:aacNoResourcesCase = @()

    if (-not $global:AACSession) {
        $script:aacNotConnectedCase = @(@{ Allowed = $allowed -join ', ' })
    }
    else {
        try {
            # Runs in the module's scope so it can use the private inventory helper.
            $resources = @(& (Get-Module -Name 'Azure.Admin.Console') { param($Ids) Get-AACResourceInventory -SubscriptionId $Ids } $SubscriptionId)

            if ($resources.Count -eq 0) {
                $script:aacNoResourcesCase = @(@{ Allowed = $allowed -join ', ' })
            }
            else {
                $script:aacResourceTypeCases = @($resources | Group-Object -Property Type | Sort-Object -Property Name | ForEach-Object {
                        @{
                            ResourceType = $_.Name
                            Count        = $_.Count
                            Resources    = @($_.Group | Sort-Object -Property Name | ForEach-Object {
                                    @{
                                        Name               = $_.Name
                                        ResourceGroup      = $_.ResourceGroup
                                        Subscription       = if ($_.SubscriptionName) { $_.SubscriptionName } else { $_.SubscriptionId }
                                        Location           = $_.Location
                                        NormalizedLocation = $_.NormalizedLocation
                                        Allowed            = $allowed
                                    }
                                })
                        }
                    })
            }
        }
        catch {
            $script:aacInventoryErrorCase = @(@{ Message = $_.Exception.Message })
        }
    }
}

Describe 'Azure Admin Console - Resource location' {
    Context '<ResourceType> (<Count>)' -ForEach $script:aacResourceTypeCases {
        It '<Name> · <ResourceGroup> · <Location>' -ForEach $Resources {
            # A plain throw rather than Should -BeIn, so the report shows a short
            # "where is it / what's allowed" reason instead of Pester's generic
            # "Expected collection ... to contain ..." wording.
            if ($NormalizedLocation -notin $Allowed) {
                throw "In '$Location', not $($Allowed -join ' / ') · subscription $Subscription"
            }
        }
    }

    It 'Resources are in <Allowed> (needs Connect-AAC)' -ForEach $script:aacNotConnectedCase {
        Set-ItResult -Skipped -Because 'there is no active Azure sign-in in this session - run Connect-AAC, then Invoke-AACPester again'
    }

    It 'Resources are in <Allowed>' -ForEach $script:aacNoResourcesCase {
        Set-ItResult -Skipped -Because 'the signed-in account can see no resources in any Enabled subscription'
    }

    It 'Resource inventory could be read from Azure' -ForEach $script:aacInventoryErrorCase {
        throw "Could not list resources: $Message"
    }
}
